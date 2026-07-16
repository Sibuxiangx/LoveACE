package tech.loveace.appv3.ui.viewmodel

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import tech.loveace.appv3.data.model.UnifiedExamInfo
import tech.loveace.appv3.data.service.JWCService

data class ExamUiState(
    val isLoading: Boolean = false,
    val hasLoaded: Boolean = false,
    val exams: List<UnifiedExamInfo> = emptyList(),
    val error: String? = null,
)

class ExamViewModel : ViewModel() {
    private var service: JWCService? = null
    private val _uiState = MutableStateFlow(ExamUiState())
    val uiState: StateFlow<ExamUiState> = _uiState.asStateFlow()

    fun init(service: JWCService) { this.service = service }

    fun loadExams() {
        val svc = service ?: return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            val result = svc.getExamInfo()
            _uiState.value = if (result.success) {
                ExamUiState(hasLoaded = true, exams = result.data ?: emptyList())
            } else {
                _uiState.value.copy(isLoading = false, hasLoaded = true, error = result.error)
            }
        }
    }
}
