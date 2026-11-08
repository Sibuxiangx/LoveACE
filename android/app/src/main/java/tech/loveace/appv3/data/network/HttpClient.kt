package tech.loveace.appv3.data.network

import android.util.Log
import okhttp3.*
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.RequestBody.Companion.toRequestBody
import java.util.concurrent.TimeUnit
import okio.Buffer
import tech.loveace.appv3.diagnostics.HttpRecord
import tech.loveace.appv3.diagnostics.LoginDiagnostics

/**
 * HTTP 客户端封装
 * - 自动 cookie 管理
 * - 响应嗅探：检测 VPN session 过期（返回 HTML 而非 JSON）
 */
class HttpClient(
    private val baseUrl: String = "",
    private val timeoutMs: Long = 60_000,
    private val followRedirects: Boolean = true,
) {
    val cookieJar = SmartCookieJar()

    /** 当检测到 session 过期时回调，外部负责重连 */
    var onSessionExpired: (() -> Unit)? = null

    private val client: OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(timeoutMs, TimeUnit.MILLISECONDS)
        .readTimeout(timeoutMs, TimeUnit.MILLISECONDS)
        .writeTimeout(timeoutMs, TimeUnit.MILLISECONDS)
        .followRedirects(followRedirects)
        .followSslRedirects(followRedirects)
        .cookieJar(cookieJar)
        .addInterceptor { chain ->
            val original = chain.request()
            val builder = original.newBuilder()
            if (original.header("User-Agent").isNullOrBlank()) {
                builder.header("User-Agent", USER_AGENT)
            }
            val request = builder.build()
            Log.d(TAG, "🌐 ${request.method} ${request.url}")
            chain.proceed(request)
        }
        .build()

    fun get(url: String, headers: Map<String, String> = emptyMap()): Response {
        val fullUrl = resolveUrl(url)
        val builder = Request.Builder().url(fullUrl).get()
        headers.forEach { (k, v) -> builder.header(k, v) }
        return execute(builder.build())
    }

    fun post(
        url: String,
        formData: Map<String, String> = emptyMap(),
        headers: Map<String, String> = emptyMap(),
    ): Response {
        val fullUrl = resolveUrl(url)
        val body = FormBody.Builder().apply {
            formData.forEach { (k, v) -> add(k, v) }
        }.build()
        val builder = Request.Builder().url(fullUrl).post(body)
        headers.forEach { (k, v) -> builder.header(k, v) }
        return execute(builder.build())
    }

    fun postRaw(url: String, rawBody: String, contentType: String, headers: Map<String, String> = emptyMap()): Response {
        val fullUrl = resolveUrl(url)
        val body = rawBody.toRequestBody(contentType.toMediaType())
        val builder = Request.Builder().url(fullUrl).post(body)
        headers.forEach { (k, v) -> builder.header(k, v) }
        return execute(builder.build())
    }

    private fun execute(request: Request): Response {
        // 登录诊断只在登录进行中才组装记录（请求头与请求体、响应头与响应体的大小和关键词）
        val recording = LoginDiagnostics.isRecording()
        val requestHeaders = if (recording) request.headers.names().associateWith { request.header(it).orEmpty() } else emptyMap()
        val requestBody = if (recording) requestBodyBytes(request.body) else null
        val startedAt = System.nanoTime()
        val response = try {
            client.newCall(request).execute()
        } catch (e: Exception) {
            if (recording) {
                LoginDiagnostics.recordHttp(
                    HttpRecord(
                        method = request.method,
                        url = request.url.toString(),
                        status = null,
                        durationMs = elapsedMs(startedAt),
                        requestHeaders = requestHeaders,
                        requestBody = requestBody,
                        responseHeaders = emptyMap(),
                        responseBody = null,
                        error = describe(e),
                    )
                )
            }
            throw e
        }
        val durationMs = elapsedMs(startedAt)
        if (recording) {
            LoginDiagnostics.recordHttp(
                HttpRecord(
                    method = request.method,
                    url = request.url.toString(),
                    status = response.code,
                    durationMs = durationMs,
                    requestHeaders = requestHeaders,
                    requestBody = requestBody,
                    responseHeaders = response.headers.names().associateWith { response.header(it).orEmpty() },
                    responseBody = try { response.peekBody(Long.MAX_VALUE).bytes() } catch (_: Exception) { null },
                    error = null,
                )
            )
        }
        Log.d(TAG, "✅ ${response.code} ${request.url}")

        // 嗅探：用 peekBody 检查是否被重定向到 VPN 登录页
        // peekBody 不消耗 body，后续 .string() 仍可正常读取
        try {
            val peek = response.peekBody(512).string()
            if (isVpnLoginPage(peek, response.request.url.toString())) {
                Log.w(TAG, "⚠️ Session expired detected for ${request.url}")
                onSessionExpired?.invoke()
            }
        } catch (_: Exception) { /* peek 失败不影响正常流程 */ }

        return response
    }

    /** 请求体字节（只在登录诊断进行中读取；非表单正文同样交给遮挡流程，不会原样记录） */
    private fun requestBodyBytes(body: RequestBody?): ByteArray? {
        if (body == null) return null
        return try {
            Buffer().also { body.writeTo(it) }.readByteArray()
        } catch (_: Exception) {
            null
        }
    }

    private fun describe(e: Exception): String {
        val name = e.javaClass.simpleName
        return e.message?.let { "$name: $it" } ?: name
    }

    private fun elapsedMs(startedAt: Long): Long = (System.nanoTime() - startedAt) / 1_000_000L

    /** 检测响应是否是 VPN 登录页 */
    private fun isVpnLoginPage(body: String, url: String): Boolean {
        // URL 被重定向到 VPN 登录
        if (url.contains("/por/login_auth.csp") || url.contains("/por/login_psw.csp")) return true
        // 响应内容是 HTML 而请求的是 API（非 .aspx/.jsp 等本身返回 HTML 的页面）
        val trimmed = body.trimStart()
        if (trimmed.startsWith("<!DOCTYPE") || trimmed.startsWith("<html")) {
            // 包含 VPN 登录特征
            if (body.contains("login_auth.csp") || body.contains("TWFID") || body.contains("svpn_name")) {
                return true
            }
        }
        return false
    }

    private fun resolveUrl(url: String): String {
        return if (url.startsWith("http://") || url.startsWith("https://")) url
        else "${baseUrl.trimEnd('/')}/${url.trimStart('/')}"
    }

    fun copyCookiesFrom(other: HttpClient) {
        cookieJar.copyFrom(other.cookieJar)
    }
    /** 把 other 的 Cookie 合并进本 client（保留本地已有 Cookie） */
    fun mergeCookiesFrom(other: HttpClient) {
        cookieJar.mergeFrom(other.cookieJar)
    }

    fun close() {
        client.dispatcher.executorService.shutdown()
        client.connectionPool.evictAll()
    }

    companion object {
        private const val TAG = "HttpClient"
        private const val USER_AGENT =
            "Mozilla/5.0 (Linux; Android 14) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Mobile Safari/537.36"
    }
}
