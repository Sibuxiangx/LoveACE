package tech.loveace.appv3.diagnostics

import java.io.IOException
import java.util.UUID
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import tech.loveace.appv3.BuildConfig
import tech.loveace.appv3.analytics.Analytics

/** 上传成功（契约第 1 节 201 响应） */
@Serializable
data class DiagnosticsUploadSuccess(
    val id: String,
    val url: String,
    val llmUrl: String,
    val expiresAt: String,
)

/** 上传失败：[code] 是契约中的服务端错误码（如 `rate_limited`），或本地错误码（如 `network_error`） */
class DiagnosticsUploadException(val code: String) : Exception(code)

/** 登录页上传按钮的状态 */
sealed interface DiagnosticsUploadState {
    object Idle : DiagnosticsUploadState
    object Uploading : DiagnosticsUploadState
    class Done(val result: DiagnosticsUploadSuccess) : DiagnosticsUploadState
    class Failed(val code: String) : DiagnosticsUploadState
}

/**
 * 登录诊断上传（契约第 1 节）。签名方式与 `/v1/events` 相同：
 * `X-LoveACE-Signature = hex(HMAC_SHA256(ANALYTICS_SIGNING_SECRET, "<timestamp>.<nonce>.<bodyHash>"))`。
 */
object DiagnosticsUploader {
    const val ENDPOINT = "https://analyst-api.loveace.top/v1/diagnostics"

    /** 契约规定的请求体上限：1 MiB（1048576 字节） */
    private const val MAX_BODY_BYTES = 1_048_576

    private val client = OkHttpClient.Builder()
        .connectTimeout(20, TimeUnit.SECONDS)
        .writeTimeout(60, TimeUnit.SECONDS)
        .readTimeout(60, TimeUnit.SECONDS)
        .build()
    private val jsonMediaType = "application/json; charset=utf-8".toMediaType()
    private val json = Json { ignoreUnknownKeys = true }

    /**
     * 上传 diagnostic.json 文本。网络请求在 [Dispatchers.IO] 执行；失败抛出 [DiagnosticsUploadException]。
     * 响应体只用于解析，错误时只取 `error` 字段，不记录或保存正文。
     */
    suspend fun upload(body: String): DiagnosticsUploadSuccess = withContext(Dispatchers.IO) {
        if (BuildConfig.ANALYTICS_API_KEY.isBlank() || BuildConfig.ANALYTICS_SIGNING_SECRET.isBlank()) {
            throw DiagnosticsUploadException("not_configured")
        }
        val bytes = body.toByteArray(Charsets.UTF_8)
        if (bytes.size > MAX_BODY_BYTES) throw DiagnosticsUploadException("payload_too_large")

        val timestamp = (System.currentTimeMillis() / 1000).toString()
        val nonce = UUID.randomUUID().toString()
        val bodyHash = Analytics.sha256(body)
        val signature = Analytics.hmacSha256(BuildConfig.ANALYTICS_SIGNING_SECRET, "$timestamp.$nonce.$bodyHash")
        val request = Request.Builder()
            .url(ENDPOINT)
            .header("Authorization", "Bearer ${BuildConfig.ANALYTICS_API_KEY}")
            .header("X-LoveACE-Timestamp", timestamp)
            .header("X-LoveACE-Nonce", nonce)
            .header("X-LoveACE-Signature", signature)
            .post(bytes.toRequestBody(jsonMediaType))
            .build()

        try {
            client.newCall(request).execute().use { response ->
                val text = response.body?.string().orEmpty()
                if (response.code == 201) {
                    try {
                        json.decodeFromString<DiagnosticsUploadSuccess>(text)
                    } catch (_: Exception) {
                        throw DiagnosticsUploadException("invalid_response")
                    }
                } else {
                    throw DiagnosticsUploadException(serverErrorCode(response.code, text))
                }
            }
        } catch (_: IOException) {
            throw DiagnosticsUploadException("network_error")
        }
    }

    /** 服务端错误码：取响应里的 `error` 字段；取不到时用 `http_<状态码>` */
    private fun serverErrorCode(status: Int, text: String): String =
        runCatching { json.parseToJsonElement(text).jsonObject["error"]?.jsonPrimitive?.content }
            .getOrNull()
            ?.takeIf { it.isNotBlank() }
            ?: "http_$status"
}
