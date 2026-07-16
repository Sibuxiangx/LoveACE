package tech.loveace.appv3.ui.viewmodel

import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import tech.loveace.appv3.data.model.*
import tech.loveace.appv3.data.service.JWCService

data class AcademicUiState(
    val isLoading: Boolean = false,
    val academicInfo: AcademicInfo? = null,
    val terms: List<TermItem> = emptyList(),
    val selectedTerm: TermItem? = null,
    val scores: TermScoreResponse? = null,
    val scoresLoading: Boolean = false,
    val selectedScore: ScoreRecord? = null,
    val scoreDetail: ScoreDetail? = null,
    val scoreDetailLoading: Boolean = false,
    val scoreDetailError: String? = null,
    val error: String? = null,
)

class AcademicViewModel : ViewModel() {
    private var service: JWCService? = null

    private val _uiState = MutableStateFlow(AcademicUiState())
    val uiState: StateFlow<AcademicUiState> = _uiState.asStateFlow()

    fun init(service: JWCService) {
        this.service = service
    }

    fun loadAcademicInfo() {
        val svc = service ?: return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(isLoading = true, error = null)
            val result = svc.getAcademicInfo()
            _uiState.value = if (result.success) {
                _uiState.value.copy(isLoading = false, academicInfo = result.data)
            } else {
                _uiState.value.copy(isLoading = false, error = result.error)
            }
        }
    }

    fun loadTerms() {
        val svc = service ?: return
        viewModelScope.launch {
            val result = svc.getAllTerms()
            if (result.success && result.data != null) {
                val terms = result.data
                val current = terms.firstOrNull { it.isCurrent } ?: terms.firstOrNull()
                _uiState.value = _uiState.value.copy(terms = terms, selectedTerm = current)
                current?.let { loadScores(it.termCode) }
            }
        }
    }

    fun selectTerm(term: TermItem) {
        _uiState.value = _uiState.value.copy(
            selectedTerm = term,
            selectedScore = null,
            scoreDetail = null,
            scoreDetailError = null,
        )
        loadScores(term.termCode)
    }

    fun loadScores(termCode: String) {
        val svc = service ?: return
        viewModelScope.launch {
            _uiState.value = _uiState.value.copy(scoresLoading = true)
            val result = if (_uiState.value.selectedTerm?.isCurrent == true) {
                svc.getThisTermScores()
            } else {
                svc.getTermScore(termCode)
            }
            _uiState.value = if (result.success) {
                _uiState.value.copy(scoresLoading = false, scores = result.data)
            } else {
                _uiState.value.copy(scoresLoading = false, error = result.error)
            }
        }
    }

    fun loadScoreDetail(record: ScoreRecord) {
        val svc = service ?: return
        _uiState.value = _uiState.value.copy(
            selectedScore = record,
            scoreDetail = null,
            scoreDetailLoading = true,
            scoreDetailError = null,
        )
        viewModelScope.launch {
            val result = svc.getScoreDetail(record)
            _uiState.value = if (result.success) {
                _uiState.value.copy(scoreDetail = result.data, scoreDetailLoading = false)
            } else {
                _uiState.value.copy(scoreDetailLoading = false, scoreDetailError = result.error)
            }
        }
    }

    fun dismissScoreDetail() {
        _uiState.value = _uiState.value.copy(
            selectedScore = null,
            scoreDetail = null,
            scoreDetailLoading = false,
            scoreDetailError = null,
        )
    }

    companion object {
        private const val TAG = "AcademicViewModel"
    }
}
