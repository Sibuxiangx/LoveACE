package tech.loveace.appv3.widget

import android.content.Context
import android.util.Log
import androidx.glance.appwidget.GlanceAppWidgetManager
import androidx.glance.appwidget.updateAll
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import tech.loveace.appv3.data.service.JWCService
import tech.loveace.appv3.data.service.StudentScheduleService
import tech.loveace.appv3.service.CourseNotificationService
import tech.loveace.appv3.service.RemoteManifestService
import tech.loveace.appv3.ui.theme.ThemePreferences
import kotlinx.coroutines.flow.first

/**
 * Widget 数据同步助手
 * 在登录成功后和每次 App 进入前台时调用
 */
object WidgetSyncHelper {
    private const val TAG = "WidgetSync"
    private val json = Json { ignoreUnknownKeys = true }

    suspend fun syncWidgetDataIfNeeded(
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
            
            if (!hasDay && !hasWeek && !notifEnabled) {
                Log.d(TAG, "No widgets or notification, skipping sync")
                return
            }

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

            // 3. 刷新 widget
            if (hasDay) SemesterDayWidget().updateAll(context)
            if (hasWeek) SemesterWeekWidget().updateAll(context)
            Log.d(TAG, "Widget update requested")

            // 4. 刷新常驻通知（重启服务以更新内容）
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
}
