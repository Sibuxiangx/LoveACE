package tech.loveace.appv3.service

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
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

private const val MANIFEST_V2_URL = "https://release.loveace.top/loveace/manifest_v2.json"
internal const val LEGACY_OTA_URL = "https://loveace.linota.cn/loveace/manifest.json"
private const val LEGACY_SEMESTER_URL =
    "https://loveace-semsync.oss-cn-beijing.aliyuncs.com/loveace/semesters.json"

internal val remoteManifestJson = Json { ignoreUnknownKeys = true }

private val remoteManifestClient = OkHttpClient.Builder()
    .connectTimeout(8, TimeUnit.SECONDS)
    .readTimeout(8, TimeUnit.SECONDS)
    .build()

@Serializable
data class ManifestV2(
    @SerialName("schema_version") val schemaVersion: Int = 0,
    val announcements: List<ManifestAnnouncement> = emptyList(),
    val platforms: Map<String, ManifestPlatform> = emptyMap(),
    val semester: ManifestSemester? = null,
)

@Serializable
data class ManifestAnnouncement(
    val id: String = "",
    val title: String = "",
    val content: String = "",
    val level: String = "info",
    val platforms: List<String> = emptyList(),
    val surfaces: List<String> = emptyList(),
    @SerialName("expires_at") val expiresAt: String? = null,
    @SerialName("require_confirmation") val requireConfirmation: Boolean = false,
)

@Serializable
data class ManifestPlatform(
    @SerialName("minimum_supported_build") val minimumSupportedBuild: Long? = null,
    val releases: List<ManifestRelease> = emptyList(),
)

@Serializable
data class ManifestRelease(
    val id: String = "",
    val version: String = "",
    val build: Long? = null,
    val channel: String = "stable",
    val summary: String = "",
    val changelog: List<String> = emptyList(),
    val artifacts: List<ManifestArtifact> = emptyList(),
)

@Serializable
data class ManifestArtifact(
    val type: String = "",
    val url: String = "",
    val checksums: ManifestChecksums = ManifestChecksums(),
)

@Serializable
data class ManifestChecksums(
    val sha256: String? = null,
    val md5: String? = null,
)

@Serializable
data class ManifestSemester(
    @SerialName("schema_version") val schemaVersion: Int = 1,
    @SerialName("updated_at") val updatedAt: String = "",
    val semesters: List<ManifestSemesterItem> = emptyList(),
)

@Serializable
data class ManifestSemesterItem(
    val code: String,
    val name: String,
    @SerialName("start_date") val startDate: String,
    val weeks: Int = 18,
)

@Serializable
private data class SemesterCachePayload(
    val version: Int = 1,
    @SerialName("updated_at") val updatedAt: String = "",
    val semesters: List<ManifestSemesterItem> = emptyList(),
)

object RemoteManifestService {
    suspend fun fetchManifestV2(): ManifestV2 = withContext(Dispatchers.IO) {
        val manifest = remoteManifestJson.decodeFromString<ManifestV2>(readUrl(MANIFEST_V2_URL))
        require(manifest.schemaVersion == 2) { "不支持的远程配置版本" }
        manifest
    }

    suspend fun fetchLegacyOta(): OtaManifest = withContext(Dispatchers.IO) {
        remoteManifestJson.decodeFromString<OtaManifest>(readUrl(LEGACY_OTA_URL))
    }

    suspend fun fetchSemesterJson(): String = withContext(Dispatchers.IO) {
        try {
            val semester = fetchManifestV2().semester
                ?: error("远程配置缺少学期数据")
            require(semester.semesters.isNotEmpty()) { "远程配置没有学期数据" }
            remoteManifestJson.encodeToString(
                SemesterCachePayload(
                    version = semester.schemaVersion,
                    updatedAt = semester.updatedAt,
                    semesters = semester.semesters,
                )
            )
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (v2Error: Exception) {
            val raw = readUrl(LEGACY_SEMESTER_URL)
            val legacy = remoteManifestJson.decodeFromString<SemesterCachePayload>(raw)
            require(legacy.semesters.isNotEmpty()) { "旧版学期数据为空" }
            remoteManifestJson.encodeToString(legacy)
        }
    }

    private suspend fun readUrl(url: String): String = suspendCancellableCoroutine { continuation ->
        val call = remoteManifestClient.newCall(Request.Builder().url(url).build())
        continuation.invokeOnCancellation { call.cancel() }
        call.enqueue(object : Callback {
            override fun onFailure(call: Call, error: IOException) {
                if (continuation.isActive) continuation.resumeWithException(error)
            }

            override fun onResponse(call: Call, response: Response) {
                response.use {
                    if (!response.isSuccessful) {
                        if (continuation.isActive) {
                            continuation.resumeWithException(
                                IOException("远程服务返回 HTTP ${response.code}")
                            )
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
}
