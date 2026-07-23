package tech.loveace.appv3.ui.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import tech.loveace.appv3.analytics.Analytics
import tech.loveace.appv3.data.local.UpdatePreferenceState
import tech.loveace.appv3.data.local.UpdatePreferences
import tech.loveace.appv3.service.AppAnnouncement
import tech.loveace.appv3.service.DownloadProgress
import tech.loveace.appv3.service.OtaService
import tech.loveace.appv3.service.UpdateInfo
import java.io.File

enum class OtaDialogMode { INFO, DOWNLOADING, ERROR }

data class OtaUiState(
    val startupCheckComplete: Boolean = false,
    val checking: Boolean = false,
    val updateInfo: UpdateInfo? = null,
    val announcement: AppAnnouncement? = null,
    val showUpdateDialog: Boolean = false,
    val showAnnouncementDialog: Boolean = false,
    val noUpdateMessage: String? = null,
    val dialogMode: OtaDialogMode = OtaDialogMode.INFO,
    val downloadProgress: Float = 0f,
    val downloadError: String? = null,
    val downloadedFile: File? = null,
    val dismissingAnnouncement: Boolean = false,
)

class OtaViewModel(application: Application) : AndroidViewModel(application) {
    private val preferences = UpdatePreferences(application)
    private val _state = MutableStateFlow(OtaUiState())
    val state: StateFlow<OtaUiState> = _state.asStateFlow()

    private var pendingAnnouncements: List<AppAnnouncement> = emptyList()
    private var pendingUpdate: UpdateInfo? = null

    fun checkForUpdate(silent: Boolean = false) {
        if (_state.value.checking) return
        viewModelScope.launch {
            _state.value = _state.value.copy(checking = true, noUpdateMessage = null)
            val result = if (silent) {
                withTimeoutOrNull(10_000) { OtaService.checkManifest(getApplication()) }
                    ?: Result.failure(IllegalStateException("启动更新检查超时"))
            } else {
                OtaService.checkManifest(getApplication())
            }
            result.onSuccess { manifest ->
                val preferenceState = runCatching { preferences.getState() }
                    .getOrDefault(UpdatePreferenceState())
                val update = manifest.updateInfo
                Analytics.trackOtaCheck(
                    result = if (update == null) "up_to_date" else "update_available",
                    currentVersion = update?.currentVersion
                        ?: OtaService.getCurrentVersion(getApplication()),
                    latestVersion = update?.latestVersion,
                )

                if (!silent) {
                    pendingAnnouncements = emptyList()
                    pendingUpdate = null
                    _state.value = _state.value.copy(
                        checking = false,
                        updateInfo = update,
                        announcement = null,
                        showAnnouncementDialog = false,
                        showUpdateDialog = update != null,
                        dialogMode = OtaDialogMode.INFO,
                        downloadedFile = _state.value.downloadedFile?.takeIf {
                            _state.value.updateInfo?.releaseKey == update?.releaseKey
                        },
                        noUpdateMessage = if (update == null) "当前已是最新版本" else null,
                    )
                    return@onSuccess
                }

                val unreadAnnouncements = manifest.announcements.filterNot {
                    it.id in preferenceState.dismissedAnnouncementIds
                }
                val visibleOptionalUpdate = update?.takeUnless {
                    !it.forceUpdate && it.releaseKey in preferenceState.ignoredReleaseKeys
                }
                if (update?.forceUpdate == true) {
                    pendingAnnouncements = unreadAnnouncements
                    pendingUpdate = null
                    showUpdate(update)
                } else {
                    pendingAnnouncements = unreadAnnouncements.drop(1)
                    pendingUpdate = visibleOptionalUpdate
                    val firstAnnouncement = unreadAnnouncements.firstOrNull()
                    if (firstAnnouncement != null) {
                        showAnnouncement(firstAnnouncement)
                    } else if (visibleOptionalUpdate != null) {
                        pendingUpdate = null
                        showUpdate(visibleOptionalUpdate)
                    } else {
                        _state.value = _state.value.copy(
                            checking = false,
                            startupCheckComplete = true,
                        )
                    }
                }
            }.onFailure {
                Analytics.trackOtaCheck(
                    result = "check_failed",
                    currentVersion = OtaService.getCurrentVersion(getApplication()),
                    latestVersion = null,
                )
                _state.value = _state.value.copy(
                    checking = false,
                    startupCheckComplete = if (silent) true else _state.value.startupCheckComplete,
                    noUpdateMessage = if (silent) null else "检查更新失败，请稍后重试",
                )
            }
        }
    }

    fun dismissAnnouncement() {
        val state = _state.value
        if (state.dismissingAnnouncement) return
        val announcement = state.announcement ?: return
        _state.value = state.copy(dismissingAnnouncement = true)
        viewModelScope.launch {
            try {
                preferences.dismissAnnouncement(announcement.id)
                val next = pendingAnnouncements.firstOrNull()
                pendingAnnouncements = pendingAnnouncements.drop(1)
                if (next != null) {
                    showAnnouncement(next)
                } else {
                    val update = pendingUpdate
                    pendingUpdate = null
                    if (update != null) {
                        showUpdate(update)
                    } else {
                        _state.value = _state.value.copy(
                            announcement = null,
                            showAnnouncementDialog = false,
                            dismissingAnnouncement = false,
                        )
                    }
                }
            } catch (_: Exception) {
                _state.value = _state.value.copy(dismissingAnnouncement = false)
            }
        }
    }

    fun dismissUpdateDialog() {
        val state = _state.value
        if (state.dialogMode == OtaDialogMode.DOWNLOADING || state.updateInfo?.forceUpdate == true) {
            return
        }
        _state.value = state.copy(showUpdateDialog = false)
    }

    fun ignoreUpdate() {
        val info = _state.value.updateInfo ?: return
        if (info.forceUpdate) return
        viewModelScope.launch {
            preferences.ignoreRelease(info.releaseKey)
            _state.value = _state.value.copy(showUpdateDialog = false)
        }
    }

    fun clearMessage() {
        _state.value = _state.value.copy(noUpdateMessage = null)
    }

    fun startDownload() {
        val info = _state.value.updateInfo ?: return
        _state.value.downloadedFile?.takeIf { it.exists() }?.let { file ->
            try {
                OtaService.installApk(getApplication(), file)
            } catch (error: Exception) {
                _state.value = _state.value.copy(
                    showUpdateDialog = true,
                    dialogMode = OtaDialogMode.ERROR,
                    downloadError = error.message ?: "无法打开系统安装程序",
                )
            }
            return
        }
        Analytics.trackOtaUpdateClick(info.currentVersion, info.latestVersion)
        _state.value = _state.value.copy(
            dialogMode = OtaDialogMode.DOWNLOADING,
            downloadProgress = 0f,
            downloadError = null,
        )
        viewModelScope.launch {
            OtaService.downloadApk(getApplication(), info).collect { progress ->
                when (progress) {
                    is DownloadProgress.Downloading -> {
                        _state.value = _state.value.copy(downloadProgress = progress.progress)
                    }
                    is DownloadProgress.Done -> {
                        _state.value = _state.value.copy(
                            downloadProgress = 1f,
                            downloadedFile = progress.file,
                            showUpdateDialog = info.forceUpdate,
                            dialogMode = OtaDialogMode.INFO,
                        )
                        try {
                            OtaService.installApk(getApplication(), progress.file)
                        } catch (error: Exception) {
                            _state.value = _state.value.copy(
                                showUpdateDialog = true,
                                dialogMode = OtaDialogMode.ERROR,
                                downloadError = error.message ?: "无法打开系统安装程序",
                            )
                        }
                    }
                    is DownloadProgress.Error -> {
                        _state.value = _state.value.copy(
                            dialogMode = OtaDialogMode.ERROR,
                            downloadError = progress.message,
                        )
                    }
                }
            }
        }
    }

    fun retryDownload() {
        startDownload()
    }

    private fun showAnnouncement(announcement: AppAnnouncement) {
        _state.value = _state.value.copy(
            checking = false,
            startupCheckComplete = true,
            announcement = announcement,
            showAnnouncementDialog = true,
            showUpdateDialog = false,
            dismissingAnnouncement = false,
        )
    }

    private fun showUpdate(update: UpdateInfo) {
        _state.value = _state.value.copy(
            checking = false,
            startupCheckComplete = true,
            updateInfo = update,
            announcement = null,
            showAnnouncementDialog = false,
            showUpdateDialog = true,
            dialogMode = OtaDialogMode.INFO,
            downloadProgress = 0f,
            downloadError = null,
            downloadedFile = null,
            dismissingAnnouncement = false,
        )
    }
}
