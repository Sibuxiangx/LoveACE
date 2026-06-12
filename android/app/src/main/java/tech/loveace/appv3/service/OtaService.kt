package tech.loveace.appv3.service

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.content.FileProvider
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File
import java.net.HttpURLConnection
import java.net.URL

private const val TAG = "OtaService"
private const val MANIFEST_URL = "https://loveace.linota.cn/loveace/manifest.json"

private val json = Json { ignoreUnknownKeys = true }

@Serializable
data class OtaManifest(
    val announcement: OtaAnnouncement? = null,
    val ota: OtaInfo? = null,
)

@Serializable
data class OtaAnnouncement(
    val title: String = "",
    val content: String = "",
    @SerialName("confirm_require") val confirmRequire: Boolean = false,
    val md5: String = "",
)

@Serializable
data class OtaChangelogEntry(
    val version: String = "",
    val changes: String = "",
)

@Serializable
data class OtaPlatformRelease(
    val version: String = "",
    @SerialName("force_ota") val forceOta: Boolean = false,
    val url: String = "",
    val md5: String? = null,
    val type: String = "native",
)

@Serializable
data class OtaInfo(
    val content: String = "",
    val notice: String? = null,
    val changelog: List<OtaChangelogEntry> = emptyList(),
    val android: OtaPlatformRelease? = null,
)

data class UpdateInfo(
    val currentVersion: String,
    val latestVersion: String,
    val downloadUrl: String,
    val forceUpdate: Boolean,
    val content: String,
    val changelog: List<OtaChangelogEntry>,
    val md5: String?,
)

sealed class DownloadProgress {
    data class Downloading(val progress: Float) : DownloadProgress()
    data class Done(val file: File) : DownloadProgress()
    data class Error(val message: String) : DownloadProgress()
}

object OtaService {

    suspend fun checkForUpdate(context: Context): UpdateInfo? = withContext(Dispatchers.IO) {
        try {
            val body = URL(MANIFEST_URL).readText()
            val manifest = json.decodeFromString<OtaManifest>(body)
            val android = manifest.ota?.android ?: return@withContext null

            val currentVersion = getCurrentVersion(context)
            if (!isNewer(android.version, currentVersion)) return@withContext null

            UpdateInfo(
                currentVersion = currentVersion,
                latestVersion = android.version,
                downloadUrl = android.url,
                forceUpdate = android.forceOta,
                content = manifest.ota.content,
                changelog = manifest.ota.changelog,
                md5 = android.md5,
            )
        } catch (e: Exception) {
            Log.e(TAG, "Check update failed", e)
            null
        }
    }

    fun getCurrentVersion(context: Context): String {
        return try {
            context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "0.0.0"
        } catch (_: Exception) {
            "0.0.0"
        }
    }

    private fun isNewer(remote: String, local: String): Boolean {
        val r = remote.split(".").mapNotNull { it.toIntOrNull() }
        val l = local.split(".").mapNotNull { it.toIntOrNull() }
        for (i in 0 until maxOf(r.size, l.size)) {
            val rv = r.getOrElse(i) { 0 }
            val lv = l.getOrElse(i) { 0 }
            if (rv > lv) return true
            if (rv < lv) return false
        }
        return false
    }

    fun downloadApk(context: Context, info: UpdateInfo): Flow<DownloadProgress> = flow {
        val fileName = "LoveACE-${info.latestVersion}.apk"
        val outFile = File(context.cacheDir, fileName)
        if (outFile.exists()) outFile.delete()

        try {
            val conn = URL(info.downloadUrl).openConnection() as HttpURLConnection
            conn.connectTimeout = 30_000
            conn.readTimeout = 60_000
            conn.connect()

            val totalBytes = conn.contentLength.toLong()
            var downloadedBytes = 0L

            conn.inputStream.use { input ->
                outFile.outputStream().use { output ->
                    val buffer = ByteArray(8192)
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        downloadedBytes += bytesRead
                        val progress = if (totalBytes > 0) (downloadedBytes.toFloat() / totalBytes).coerceIn(0f, 1f) else 0f
                        emit(DownloadProgress.Downloading(progress))
                    }
                }
            }

            emit(DownloadProgress.Done(outFile))
        } catch (e: Exception) {
            Log.e(TAG, "Download failed", e)
            outFile.delete()
            emit(DownloadProgress.Error(e.message ?: "下载失败"))
        }
    }.flowOn(Dispatchers.IO)

    fun installApk(context: Context, file: File) {
        val uri = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N) {
            FileProvider.getUriForFile(context, "${context.packageName}.fileprovider", file)
        } else {
            Uri.fromFile(file)
        }

        val intent = Intent(Intent.ACTION_VIEW).apply {
            setDataAndType(uri, "application/vnd.android.package-archive")
            addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            addFlags(Intent.FLAG_GRANT_READ_URI_PERMISSION)
        }
        context.startActivity(intent)
    }
}
