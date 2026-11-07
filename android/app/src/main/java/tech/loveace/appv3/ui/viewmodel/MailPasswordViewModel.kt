package tech.loveace.appv3.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import tech.loveace.appv3.data.model.MailInitialPassword
import tech.loveace.appv3.data.service.PortalService

data class MailPasswordUiState(
    val isLoading: Boolean = false,
    val hasLoaded: Boolean = false,
    /** 仅内存保存；[MailPasswordViewModel.clear] 在页面离开时清空 */
    val password: MailInitialPassword? = null,
    val error: String? = null,
)

class MailPasswordViewModel : ViewModel() {
    private val _uiState = MutableStateFlow(MailPasswordUiState())
    val uiState: StateFlow<MailPasswordUiState> = _uiState.asStateFlow()

    /** 每次加载或清除都递增；旧请求返回时丢弃，离开页面后迟到的结果不会重新写入密码 */
    private var generation = 0

    fun load(service: PortalService?) {
        generation += 1
        val token = generation
        if (service == null) {
            _uiState.value = _uiState.value.copy(isLoading = false, hasLoaded = true, error = "请先登录")
            return
        }
        _uiState.value = _uiState.value.copy(isLoading = true, error = null)
        viewModelScope.launch {
            val response = service.mailInitialPassword()
            if (token != generation) return@launch
            _uiState.value = if (response.success) {
                _uiState.value.copy(isLoading = false, hasLoaded = true, password = response.data, error = null)
            } else {
                // 刷新失败保留已加载的密码，只显示错误和重试
                _uiState.value.copy(
                    isLoading = false,
                    hasLoaded = true,
                    error = response.error ?: "加载失败，请稍后重试",
                )
            }
        }
    }

    fun clear() {
        generation += 1
        _uiState.value = MailPasswordUiState()
    }
}
