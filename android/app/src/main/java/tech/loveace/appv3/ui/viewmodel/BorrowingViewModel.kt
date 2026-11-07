package tech.loveace.appv3.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import tech.loveace.appv3.data.model.BorrowRecord
import tech.loveace.appv3.data.service.PortalService

data class BorrowingUiState(
    val current: List<BorrowRecord> = emptyList(),
    val history: List<BorrowRecord> = emptyList(),
    /** 至少成功加载过一次 */
    val loaded: Boolean = false,
    val isLoading: Boolean = false,
    /** 首次加载失败时的整页错误 */
    val error: String? = null,
    /** 已加载过数据后刷新失败的错误，列表保留 */
    val refreshError: String? = null,
    val needsLogin: Boolean = false,
)

class BorrowingViewModel : ViewModel() {
    private var service: PortalService? = null
    private var generation = 0L
    private val _uiState = MutableStateFlow(BorrowingUiState())
    val uiState: StateFlow<BorrowingUiState> = _uiState.asStateFlow()

    fun bind(service: PortalService?) {
        this.service = service
    }

    fun load() {
        val gen = ++generation
        val current = _uiState.value
        val svc = service
        if (svc == null) {
            _uiState.value = current.copy(
                isLoading = false, error = null, refreshError = null, needsLogin = true,
            )
            return
        }
        _uiState.value = current.copy(isLoading = true, error = null, refreshError = null, needsLogin = false)
        viewModelScope.launch {
            val result = svc.borrowing()
            if (gen != generation) return@launch
            val latest = _uiState.value
            val data = result.data
            if (result.success && data != null) {
                _uiState.value = latest.copy(
                    current = data.current,
                    history = data.history,
                    loaded = true,
                    isLoading = false,
                    error = null,
                    refreshError = null,
                )
            } else {
                val message = result.error ?: "加载失败，请稍后重试"
                // 已有数据时刷新失败：保留原列表，只显示错误
                _uiState.value = if (latest.loaded) {
                    latest.copy(isLoading = false, refreshError = message)
                } else {
                    latest.copy(isLoading = false, error = message)
                }
            }
        }
    }

    fun retry() = load()

    override fun onCleared() {
        generation++
        super.onCleared()
    }
}
