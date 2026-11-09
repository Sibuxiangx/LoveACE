package tech.loveace.appv3.widget

import android.content.Context
import android.util.Log
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.updateAll
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import tech.loveace.appv3.data.model.UnifiedExamInfo
import tech.loveace.appv3.data.service.JWCService
import tech.loveace.appv3.data.service.StudentScheduleService
import tech.loveace.appv3.service.CourseNotificationService
import tech.loveace.appv3.service.RemoteManifestService
import tech.loveace.appv3.ui.theme.ThemePreferences
import java.time.LocalDate

/**
 * Widget 数据同步助手
 * 登录成功后进入首页时预取，之后每次 App 进入前台时再次调用（不节流）。
 * 学期 feed、课程、考试各自成功才覆盖本地快照；失败保留旧快照。
 */
object WidgetSyncHelper {
    private const val TAG = "WidgetSync"
    private val json = Json { ignoreUnknownKeys = true }
    private val EXAM_DATE = Regex("(\\d{4})[-/.](\\d{1,2})[-/.](\\d{1,2})")

    private val _snapshotVersion = MutableStateFlow(0)

    /** 每次同步结束递增；App 内学期状态据此从本地快照重新计算。 */
    val snapshotVersion: StateFlow<Int> = _snapshotVersion.asStateFlow()

    suspend fun syncWidgetData(
        context: Context,
        jwcService: JWCService?,
        scheduleService: StudentScheduleService?,
    ) {
        try {
            val manager = GlanceAppWidgetManager(context)
            val hasDay = manager.getGlanceIds(SemesterDayWidget::class.java).isNotEmpty()
            val hasWeek = manager.getGlanceIds(SemesterWeekWidget::class.java).isNotEmpty()
            val notifEnabled = try {
                ThemePreferences(context).themeConfig.first().courseNotificationEnabled
            } catch (_: Exception) { false }

            Log.d(TAG, "Syncing widget data...")

            // 1. 获取 semester 数据
            try {
                val semesterJson = RemoteManifestService.fetchSemesterJson()
                json.decodeFromString<WidgetSemesterData>(semesterJson)
                WidgetDataStore.saveSemesterJson(context, semesterJson)
                Log.d(TAG, "Semester saved")
            } catch (e: Exception) {
                Log.e(TAG, "Semester fetch failed", e)
            }

            // 2. 获取课程数据
            if (jwcService != null && scheduleService != null) {
                try {
                    val termsResult = jwcService.getAllTerms()
                    if (termsResult.success && termsResult.data != null) {
                        val currentTerm = termsResult.data.firstOrNull { it.isCurrent }
                            ?: termsResult.data.firstOrNull()
                        if (currentTerm != null) {
                            val scheduleResult = scheduleService.getStudentSchedule(currentTerm.termCode)
                            if (scheduleResult.success && scheduleResult.data != null) {
                                WidgetDataStore.saveCourses(context, json.encodeToString(scheduleResult.data.courses))
                                Log.d(TAG, "Courses saved: ${scheduleResult.data.courses.size}")
                            }
                        }
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Schedule fetch failed", e)
                }
            }

            // 3. 获取考试数据（复用 JWC 考试查询）
            if (jwcService != null) {
                try {
                    val examResult = jwcService.getExamInfo()
                    val exams = examResult.data
                    if (examResult.success && exams != null) {
                        val snapshot = WidgetExamSnapshot(exams = exams.mapNotNull { it.toWidgetExamItem() })
                        WidgetDataStore.saveExamsJson(context, json.encodeToString(snapshot))
                        Log.d(TAG, "Exams saved: ${snapshot.exams.size}")
                    }
                } catch (e: Exception) {
                    Log.e(TAG, "Exam fetch failed", e)
                }
            }
            _snapshotVersion.update { it + 1 }

            // 4. 刷新 widget
            if (hasDay) SemesterDayWidget().updateAll(context)
            if (hasWeek) SemesterWeekWidget().updateAll(context)
            Log.d(TAG, "Widget update requested")

            // 5. 刷新常驻通知（重启服务以更新内容）
            if (notifEnabled) {
                try {
                    CourseNotificationService.start(context)
                    Log.d(TAG, "Course notification refreshed")
                } catch (e: Exception) {
                    Log.e(TAG, "Notification refresh failed", e)
                }
            }

        } catch (e: Exception) {
            Log.e(TAG, "Sync failed", e)
        }
    }

    /** 考试日期规范化为 yyyy-MM-dd；无法解析的记录丢弃 */
    private fun UnifiedExamInfo.toWidgetExamItem(): WidgetExamItem? {
        val m = EXAM_DATE.find(examDate) ?: return null
        val date = try {
            LocalDate.of(m.groupValues[1].toInt(), m.groupValues[2].toInt(), m.groupValues[3].toInt())
        } catch (_: Exception) {
            return null
        }
        return WidgetExamItem(
            courseName = courseName,
            examDate = date.toString(),
            examTime = examTime,
            examLocation = examLocation,
        )
    }
}
