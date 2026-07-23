package tech.loveace.appv3.ui.viewmodel

import android.app.Application
import android.util.Log
import androidx.glance.appwidget.updateAll
import androidx.lifecycle.AndroidViewModel
import androidx.lifecycle.viewModelScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import tech.loveace.appv3.widget.SemesterDayWidget
import tech.loveace.appv3.widget.SemesterWeekWidget
import tech.loveace.appv3.widget.WidgetDataStore
import tech.loveace.appv3.service.RemoteManifestService
import java.time.LocalDate
import java.time.format.DateTimeFormatter
import java.time.temporal.ChronoUnit

// ── 数据模型 ──

@Serializable
data class SemesterData(
    val version: Int = 1,
    @SerialName("updated_at") val updatedAt: String = "",
    val semesters: List<SemesterItem> = emptyList(),
)

@Serializable
data class SemesterItem(
    val code: String,
    val name: String,
    @SerialName("start_date") val startDate: String,
    val weeks: Int = 18,
)

private val TERM_NAME_MAP = mapOf("1" to "第一学期（秋季）", "2" to "第二学期（春季）")

fun SemesterItem.displayName(): String {
    val parts = code.split("-")
    if (parts.size == 3) {
        val yearPart = "${parts[0]}-${parts[1]}"
        val termText = TERM_NAME_MAP[parts[2]] ?: "第${parts[2]}学期"
        return "${yearPart}学年 $termText"
    }
    return name.ifEmpty { code }
}


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
    }

    fun loadSemesterInfo() {
        viewModelScope.launch {
            _uiState.value = SemesterUiState(SemesterStatus.Loading)
            try {
                val rawText = RemoteManifestService.fetchSemesterJson()
                val data = json.decodeFromString<SemesterData>(rawText)
                WidgetDataStore.saveSemesterJson(getApplication(), rawText)
                val status = computeStatus(data)
                _uiState.value = SemesterUiState(status)
                // 请求刷新 widget
                SemesterDayWidget().updateAll(getApplication())
                SemesterWeekWidget().updateAll(getApplication())
            } catch (e: Exception) {
                Log.e(TAG, "Failed to load semester info", e)
                _uiState.value = SemesterUiState(SemesterStatus.Error("无法获取学期信息"))
            }
        }
    }

    private fun computeStatus(data: SemesterData): SemesterStatus {
        val today = LocalDate.now()
        val semesters = data.semesters.sortedBy { it.startDate }

        for (sem in semesters) {
            val start = LocalDate.parse(sem.startDate, DateTimeFormatter.ISO_LOCAL_DATE)
            val end = start.plusWeeks(sem.weeks.toLong()).minusDays(1)
            val display = sem.displayName()

            if (today.isBefore(start)) {
                val daysUntil = ChronoUnit.DAYS.between(today, start)
                return SemesterStatus.Vacation(
                    nextSemesterName = display,
                    nextStartDate = sem.startDate,
                    daysUntilStart = daysUntil,
                )
            }

            if (!today.isBefore(start) && !today.isAfter(end)) {
                val weekNum = (ChronoUnit.DAYS.between(start, today) / 7 + 1).toInt()
                val remaining = sem.weeks - weekNum
                return SemesterStatus.InSession(
                    semesterName = display,
                    currentWeek = weekNum,
                    totalWeeks = sem.weeks,
                    remainingWeeks = remaining,
                    isEnding = remaining <= 2,
                )
            }
        }

        return SemesterStatus.Vacation()
    }

    companion object {
        private const val TAG = "SemesterViewModel"
    }
}
