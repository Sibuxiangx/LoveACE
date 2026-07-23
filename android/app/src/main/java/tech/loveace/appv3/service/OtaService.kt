package tech.loveace.appv3.service

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.os.Build
import android.util.Log
import androidx.core.content.FileProvider
import androidx.core.content.pm.PackageInfoCompat
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.withContext
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import java.io.File
import java.net.HttpURLConnection
import java.net.URL
import java.security.MessageDigest
import java.time.OffsetDateTime

private const val TAG = "OtaService"

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

data class AppAnnouncement(
    val id: String,
    val title: String,
    val content: String,
    val level: String = "info",
    val requireConfirmation: Boolean = false,
)

data class UpdateInfo(
    val releaseKey: String,
    val currentVersion: String,
    val currentBuild: Long,
    val latestVersion: String,
    val latestBuild: Long?,
    val downloadUrl: String,
    val forceUpdate: Boolean,
    val content: String,
    val changelog: List<OtaChangelogEntry>,
    val sha256: String? = null,
    val md5: String? = null,
)

data class AppManifestInfo(
    val updateInfo: UpdateInfo?,
    val announcements: List<AppAnnouncement>,
)

sealed class DownloadProgress {
    data class Downloading(val progress: Float) : DownloadProgress()
    data class Done(val file: File) : DownloadProgress()
    data class Error(val message: String) : DownloadProgress()
}

object OtaService {
    suspend fun checkManifest(context: Context): Result<AppManifestInfo> = withContext(Dispatchers.IO) {
        try {
            Result.success(fromV2(context, RemoteManifestService.fetchManifestV2()))
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (v2Error: Exception) {
            Log.w(TAG, "Manifest v2 unavailable, falling back to legacy", v2Error)
            try {
                Result.success(fromLegacy(context, RemoteManifestService.fetchLegacyOta()))
            } catch (cancellation: CancellationException) {
                throw cancellation
            } catch (legacyError: Exception) {
                Log.e(TAG, "All update checks failed", legacyError)
                Result.failure(legacyError)
            }
        }
    }

    private fun fromV2(context: Context, manifest: ManifestV2): AppManifestInfo {
        val currentVersion = getCurrentVersion(context)
        val currentBuild = getCurrentBuild(context)
        val platform = manifest.platforms["android"]
        val release = platform?.releases?.firstOrNull { it.channel == "stable" }
            ?: platform?.releases?.firstOrNull()
        val artifact = release?.artifacts?.firstOrNull { it.type == "apk" }
        val isNewer = release != null && when (release.build) {
            null -> isNewerVersion(release.version, currentVersion)
            else -> release.build > currentBuild
        }
        val forceUpdate = platform?.minimumSupportedBuild?.let { currentBuild < it } == true
        val update = if (release != null && artifact != null && isNewer) {
            UpdateInfo(
                releaseKey = release.id.ifEmpty {
                    "android:${release.version}:${release.build ?: artifact.url}"
                },
                currentVersion = currentVersion,
                currentBuild = currentBuild,
                latestVersion = release.version,
                latestBuild = release.build,
                downloadUrl = artifact.url,
                forceUpdate = forceUpdate,
                content = release.summary,
                changelog = release.changelog.map {
                    OtaChangelogEntry(version = release.version, changes = it)
                },
                sha256 = artifact.checksums.sha256,
                md5 = artifact.checksums.md5,
            )
        } else {
            null
        }

        val announcements = manifest.announcements
            .filter(::isAndroidAppAnnouncement)
            .map {
                AppAnnouncement(
                    id = it.id,
                    title = it.title,
                    content = it.content,
                    level = it.level,
                    requireConfirmation = it.requireConfirmation,
                )
            }
        return AppManifestInfo(updateInfo = update, announcements = announcements)
    }

    private fun fromLegacy(context: Context, manifest: OtaManifest): AppManifestInfo {
        val currentVersion = getCurrentVersion(context)
        val currentBuild = getCurrentBuild(context)
        val ota = manifest.ota
        val android = ota?.android
        val update = if (android != null && isNewerVersion(android.version, currentVersion)) {
            val changelog = ota?.changelog.orEmpty().filter { entry ->
                val label = entry.version.lowercase()
                label.startsWith("android ") || listOf("windows ", "macos ", "ios ", "linux ")
                    .none { prefix -> label.startsWith(prefix) }
            }
            UpdateInfo(
                releaseKey = "legacy-android:${android.version}:${android.md5 ?: android.url}",
                currentVersion = currentVersion,
                currentBuild = currentBuild,
                latestVersion = android.version,
                latestBuild = null,
                downloadUrl = android.url,
                forceUpdate = android.forceOta,
                content = ota?.content.orEmpty(),
                changelog = changelog,
                md5 = android.md5,
            )
        } else {
            null
        }
        val announcement = manifest.announcement?.takeIf {
            it.title.isNotEmpty() || it.content.isNotEmpty()
        }?.let {
            val id = if (it.md5.isNotEmpty()) "legacy-${it.md5}" else {
                "legacy-${digestText("SHA-256", it.title + it.content)}"
            }
            AppAnnouncement(
                id = id,
                title = it.title,
                content = it.content,
                requireConfirmation = it.confirmRequire,
            )
        }
        return AppManifestInfo(updateInfo = update, announcements = listOfNotNull(announcement))
    }

    fun getCurrentVersion(context: Context): String = try {
        context.packageManager.getPackageInfo(context.packageName, 0).versionName ?: "0.0.0"
    } catch (_: Exception) {
        "0.0.0"
    }

    fun getCurrentBuild(context: Context): Long = try {
        PackageInfoCompat.getLongVersionCode(
            context.packageManager.getPackageInfo(context.packageName, 0)
        )
    } catch (_: Exception) {
        0L
    }

    internal fun isNewerVersion(remote: String, local: String): Boolean {
        val remoteParts = remote.split(".").map { it.toIntOrNull() ?: return false }
        val localParts = local.split(".").map { it.toIntOrNull() ?: return false }
        for (index in 0 until maxOf(remoteParts.size, localParts.size)) {
            val remoteValue = remoteParts.getOrElse(index) { 0 }
            val localValue = localParts.getOrElse(index) { 0 }
            if (remoteValue > localValue) return true
            if (remoteValue < localValue) return false
        }
        return false
    }

    fun downloadApk(context: Context, info: UpdateInfo): Flow<DownloadProgress> = flow {
        val buildSuffix = info.latestBuild?.let { "-$it" } ?: ""
        val outFile = File(context.cacheDir, "LoveACE-${info.latestVersion}$buildSuffix.apk")
        if (outFile.exists()) outFile.delete()
        var connection: HttpURLConnection? = null

        try {
            connection = URL(info.downloadUrl).openConnection() as HttpURLConnection
            connection.connectTimeout = 30_000
            connection.readTimeout = 60_000
            connection.connect()
            if (connection.responseCode !in 200..299) {
                error("下载服务返回 HTTP ${connection.responseCode}")
            }

            val totalBytes = connection.contentLengthLong
            var downloadedBytes = 0L
            connection.inputStream.use { input ->
                outFile.outputStream().use { output ->
                    val buffer = ByteArray(8192)
                    var bytesRead: Int
                    while (input.read(buffer).also { bytesRead = it } != -1) {
                        output.write(buffer, 0, bytesRead)
                        downloadedBytes += bytesRead
                        val progress = if (totalBytes > 0) {
                            (downloadedBytes.toFloat() / totalBytes).coerceIn(0f, 1f)
                        } else {
                            0f
                        }
                        emit(DownloadProgress.Downloading(progress))
                    }
                }
            }

            val valid = when {
                !info.sha256.isNullOrBlank() -> verifyDigest(outFile, "SHA-256", info.sha256)
                !info.md5.isNullOrBlank() -> verifyDigest(outFile, "MD5", info.md5)
                else -> false
            }
            if (!valid) {
                outFile.delete()
                emit(DownloadProgress.Error("安装包校验失败，请重新下载"))
                return@flow
            }
            emit(DownloadProgress.Done(outFile))
        } catch (cancellation: CancellationException) {
            throw cancellation
        } catch (error: Exception) {
            Log.e(TAG, "Download failed", error)
            outFile.delete()
            emit(DownloadProgress.Error(error.message ?: "下载失败"))
        } finally {
            connection?.disconnect()
        }
    }.flowOn(Dispatchers.IO)

    private fun verifyDigest(file: File, algorithm: String, expected: String): Boolean {
        return digestFile(file, algorithm).equals(expected, ignoreCase = true)
    }

    internal fun digestFile(file: File, algorithm: String): String {
        val digest = MessageDigest.getInstance(algorithm)
        file.inputStream().use { input ->
            val buffer = ByteArray(8192)
            var count: Int
            while (input.read(buffer).also { count = it } != -1) {
                digest.update(buffer, 0, count)
            }
        }
        return digest.digest().joinToString("") { "%02x".format(it) }
    }

    private fun digestText(algorithm: String, value: String): String {
        val digest = MessageDigest.getInstance(algorithm).digest(value.toByteArray())
        return digest.joinToString("") { "%02x".format(it) }
    }

    private fun isAndroidAppAnnouncement(announcement: ManifestAnnouncement): Boolean {
        val targetsAndroid = "all" in announcement.platforms || "android" in announcement.platforms
        val targetsApp = "app" in announcement.surfaces
        val active = announcement.expiresAt?.let { expiresAt ->
            runCatching { OffsetDateTime.parse(expiresAt).toInstant() > java.time.Instant.now() }
                .getOrDefault(false)
        } ?: true
        return announcement.id.isNotEmpty() && targetsAndroid && targetsApp && active
    }

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
