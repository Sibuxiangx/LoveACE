package tech.loveace.appv3.service

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import okhttp3.Call
import okhttp3.Callback
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.IOException
import java.util.concurrent.TimeUnit
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

private val QQ_GROUP_URLS = listOf(
    "https://loveace.linota.cn/loveace/qq_group_v1.json",
    "https://release.loveace.top/loveace/qq_group_v1.json",
)

private val qqGroupJson = Json { ignoreUnknownKeys = true }

private val qqGroupClient = OkHttpClient.Builder()
    .connectTimeout(8, TimeUnit.SECONDS)
    .readTimeout(8, TimeUnit.SECONDS)
    .build()

/** 交流群入口的独立远程配置（qq_group_v1.json），与 manifest_v2 无关。 */
@Serializable
data class QqGroupManifest(
    @SerialName("schema_version") val schemaVersion: Int = 0,
    val revision: String = "",
    @SerialName("updated_at") val updatedAt: String = "",
    val enabled: Boolean = false,
    val title: String = "",
    @SerialName("group_number") val groupNumber: String = "",
    @SerialName("share_url") val shareUrl: String = "",
    @SerialName("qr_image_url") val qrImageUrl: String = "",
)

object QqGroupService {
    /**
     * 拉取交流群配置。网络失败、非 2xx、解码失败或 schema 不匹配时依次尝试下一地址；
     * 全部失败、或 enabled 为 false 时返回 null，调用方据此不渲染任何入口。
     * 结果只保存在调用方内存中，不落盘，也不记录响应内容。
     */
    suspend fun fetch(): QqGroupManifest? = withContext(Dispatchers.IO) {
        val manifest = try {
            fetchWithFallback(QQ_GROUP_URLS) { raw ->
                qqGroupJson.decodeFromString<QqGroupManifest>(raw).also { parsed ->
                    require(parsed.schemaVersion == 1) { "不支持的交流群配置版本" }
                }
            }
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (_: Exception) {
            return@withContext null
        }
        manifest.takeIf { it.enabled }
    }

    private suspend fun readUrl(url: String): String = suspendCancellableCoroutine { continuation ->
        val call = qqGroupClient.newCall(Request.Builder().url(url).build())
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, error: IOException) {
                if (continuation.isActive) continuation.resumeWithException(error)
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    if (!response.isSuccessful) {
                        if (continuation.isActive) {
                            continuation.resumeWithException(IOException("远程服务返回 HTTP ${response.code}"))
                        }
                        return
                    }
                    val body = response.body
                    if (body == null) {
                        if (continuation.isActive) {
                            continuation.resumeWithException(IOException("远程服务返回空响应"))
                        }
                    } else if (continuation.isActive) {
                        continuation.resume(body.string())
                    }
                }
            }
        })
    }

    private suspend fun <T> fetchWithFallback(
        urls: List<String>,
        decode: (String) -> T,
    ): T {
        var lastError: Exception? = null
        for (url in urls) {
            try {
                return decode(readUrl(url))
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (error: Exception) {
                lastError = error
            }
        }
        throw lastError ?: IOException("没有可用的交流群配置地址")
    }
}
