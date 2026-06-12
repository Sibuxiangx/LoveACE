package tech.loveace.appv3.ui.viewmodel

import android.app.Application
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import tech.loveace.appv3.analytics.Analytics
import tech.loveace.appv3.service.DownloadProgress
import tech.loveace.appv3.service.OtaService
import tech.loveace.appv3.service.UpdateInfo
import java.io.File

enum class OtaDialogMode { INFO, DOWNLOADING, ERROR }

data class OtaUiState(
    val checking: Boolean = false,
    val updateInfo: UpdateInfo? = null,
    val showDialog: Boolean = false,
    val noUpdateMessage: String? = null,
    val dialogMode: OtaDialogMode = OtaDialogMode.INFO,
    val downloadProgress: Float = 0f,
    val downloadError: String? = null,
    val downloadedFile: File? = null,
)

class OtaViewModel(application: Application) : AndroidViewModel(application) {
    private val _state = MutableStateFlow(OtaUiState())
    val state: StateFlow<OtaUiState> = _state.asStateFlow()

    fun checkForUpdate(silent: Boolean = false) {
        if (_state.value.checking) return
        viewModelScope.launch {
            _state.value = _state.value.copy(checking = true, noUpdateMessage = null)
            val info = OtaService.checkForUpdate(getApplication())
            Analytics.trackOtaCheck(
                result = if (info == null) "up_to_date" else "update_available",
                currentVersion = info?.currentVersion ?: OtaService.getCurrentVersion(getApplication()),
                latestVersion = info?.latestVersion,
            )
            _state.value = _state.value.copy(
                checking = false,
                updateInfo = info,
                showDialog = info != null,
                dialogMode = OtaDialogMode.INFO,
                noUpdateMessage = if (info == null && !silent) "当前已是最新版本" else null,
            )
        }
    }

    fun dismissDialog() {
        if (_state.value.dialogMode == OtaDialogMode.DOWNLOADING) return
        _state.value = _state.value.copy(showDialog = false)
    }

    fun clearMessage() {
        _state.value = _state.value.copy(noUpdateMessage = null)
    }

    fun startDownload() {
        val info = _state.value.updateInfo ?: return
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
                        )
                        OtaService.installApk(getApplication(), progress.file)
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
}
