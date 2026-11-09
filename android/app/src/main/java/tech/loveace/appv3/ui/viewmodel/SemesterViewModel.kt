package tech.loveace.appv3.ui.viewmodel

import android.app.Application
import android.util.Log
import androidx.glance.appwidget.updateAll
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch
import kotlinx.serialization.json.Json
import tech.loveace.appv3.service.RemoteManifestService
import tech.loveace.appv3.widget.SemesterDayWidget
import tech.loveace.appv3.widget.SemesterPhase
import tech.loveace.appv3.widget.SemesterWeekWidget
import tech.loveace.appv3.widget.WidgetDataStore
import tech.loveace.appv3.widget.WidgetExamCard
import tech.loveace.appv3.widget.WidgetSemesterData
import tech.loveace.appv3.widget.WidgetSyncHelper
import tech.loveace.appv3.widget.displayName
import tech.loveace.appv3.widget.loadWidgetExams
import tech.loveace.appv3.widget.resolveSemesterPhase
import java.time.LocalDate

// ── 状态 ──

sealed class SemesterStatus {
    data object Loading : SemesterStatus()
    data class Vacation(
        val message: String = "假期中",
        val nextSemesterName: String? = null,
        val nextStartDate: String? = null,
        val daysUntilStart: Long? = null,
    ) : SemesterStatus()
    data class InSession(
        val semesterName: String,
        val currentWeek: Int,
        val totalWeeks: Int,
        val remainingWeeks: Int,
        val isEnding: Boolean,
    ) : SemesterStatus()
    /** 教学结束后仍有未结束的考试 */
    data class ExamWeek(val nextExam: WidgetExamCard) : SemesterStatus()
    data class Error(val message: String) : SemesterStatus()
}

data class SemesterUiState(
    val status: SemesterStatus = SemesterStatus.Loading,
)

// ── ViewModel ──

class SemesterViewModel(application: Application) : AndroidViewModel(application) {

    private val _uiState = MutableStateFlow(SemesterUiState())
    val uiState: StateFlow<SemesterUiState> = _uiState.asStateFlow()

    private val json = Json { ignoreUnknownKeys = true }

    init {
        loadSemesterInfo()
        // 首页预取写入新快照后，只从本地缓存重新计算（不触网）
        viewModelScope.launch {
            WidgetSyncHelper.snapshotVersion.drop(1).collect { recomputeFromCache() }
        }
    }

    fun loadSemesterInfo() {
        viewModelScope.launch {
            _uiState.value = SemesterUiState(SemesterStatus.Loading)
            try {
                val rawText = RemoteManifestService.fetchSemesterJson()
                val data = json.decodeFromString<WidgetSemesterData>(rawText)
                WidgetDataStore.saveSemesterJson(getApplication(), rawText)
                _uiState.value = SemesterUiState(computeStatus(data))
                // 请求刷新 widget
                SemesterDayWidget().updateAll(getApplication())
                SemesterWeekWidget().updateAll(getApplication())
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load semester info", e)
                _uiState.value = SemesterUiState(SemesterStatus.Error("无法获取学期信息"))
            }
        }
    }

    private fun recomputeFromCache() {
        val raw = WidgetDataStore.loadSemesterJson(getApplication()) ?: return
        try {
            _uiState.value = SemesterUiState(computeStatus(json.decodeFromString<WidgetSemesterData>(raw)))
        } catch (e: Exception) {
            Log.e(TAG, "Failed to recompute semester status", e)
        }
    }

    private fun computeStatus(data: WidgetSemesterData): SemesterStatus {
        val exams = loadWidgetExams(getApplication())
        return when (val phase = resolveSemesterPhase(data.semesters, exams, LocalDate.now())) {
            is SemesterPhase.Teaching -> {
                val weeks = phase.semester.weeks
                SemesterStatus.InSession(
                    semesterName = phase.semester.displayName(),
                    currentWeek = phase.weekNum,
                    totalWeeks = weeks,
                    remainingWeeks = weeks - phase.weekNum,
                    isEnding = weeks - phase.weekNum <= 2,
                )
            }
            is SemesterPhase.ExamWeek -> SemesterStatus.ExamWeek(phase.nextExam)
            is SemesterPhase.Vacation -> SemesterStatus.Vacation(
                nextSemesterName = phase.nextSemester?.displayName(),
                nextStartDate = phase.nextSemester?.startDate,
                daysUntilStart = phase.daysUntilStart,
            )
        }
    }

    companion object {
        private const val TAG = "SemesterViewModel"
    }
}
