package tech.loveace.appv3.service

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Handler
import android.os.IBinder
import android.os.Looper
import android.util.Log
import androidx.core.app.NotificationCompat
import tech.loveace.appv3.MainActivity
import tech.loveace.appv3.R
import tech.loveace.appv3.widget.WidgetState
import tech.loveace.appv3.widget.fetchWidgetState
import tech.loveace.appv3.widget.WidgetCourseEntry
import tech.loveace.appv3.widget.WidgetExamCard
import tech.loveace.appv3.widget.currentMinuteOfDay
import tech.loveace.appv3.widget.dateText
import tech.loveace.appv3.widget.daysText

class CourseNotificationService : Service() {

    companion object {
        private const val TAG = "CourseNotif"
        private const val CHANNEL_ID = "course_tip"
        private const val CHANNEL_REMINDER_ID = "course_reminder"
        private const val NOTIFICATION_ID = 10001
        private const val REMINDER_NOTIFICATION_ID = 10002
        private const val REFRESH_INTERVAL_MS = 30_000L

        fun start(context: Context) {
            context.startForegroundService(Intent(context, CourseNotificationService::class.java))
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, CourseNotificationService::class.java))
        }
    }

    private val handler = Handler(Looper.getMainLooper())
    private val refreshRunnable = object : Runnable {
        override fun run() {
            refreshNotification()
            handler.postDelayed(this, REFRESH_INTERVAL_MS)
        }
    }
    private var lastRemindedKey: String? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onCreate() {
        super.onCreate()
        ensureChannels()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        refreshNotification()
        handler.removeCallbacks(refreshRunnable)
        handler.postDelayed(refreshRunnable, REFRESH_INTERVAL_MS)
        return START_STICKY
    }

    override fun onDestroy() {
        handler.removeCallbacks(refreshRunnable)
        getSystemService(NotificationManager::class.java)?.cancel(REMINDER_NOTIFICATION_ID)
        super.onDestroy()
    }

    // ── Channels ──

    private fun ensureChannels() {
        val nm = getSystemService(NotificationManager::class.java) ?: return
        if (nm.getNotificationChannel(CHANNEL_ID) == null) {
            nm.createNotificationChannel(NotificationChannel(
                CHANNEL_ID, "课程提示", NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = "常驻通知栏显示课程信息"
                setShowBadge(false)
            })
        }
        if (nm.getNotificationChannel(CHANNEL_REMINDER_ID) == null) {
            nm.createNotificationChannel(NotificationChannel(
                CHANNEL_REMINDER_ID, "课前提醒", NotificationManager.IMPORTANCE_HIGH,
            ).apply {
                description = "上课前10分钟提醒"
            })
        }
    }

    // ── Core refresh ──

    private fun refreshNotification() {
        val result = try {
            resolveState(fetchWidgetState(this))
        } catch (e: Exception) {
            Log.e(TAG, "refreshNotification failed", e)
            ResolvedState("课程提示", "数据加载失败")
        }

        startForeground(NOTIFICATION_ID, buildMainNotification(result))

        if (result.postReminder) postReminder(result.reminderTitle, result.reminderText)
        if (result.clearReminder) dismissReminder()
    }

    // ── State resolution ──

    private data class ResolvedState(
        val title: String,
        val text: String,
        val inClass: Boolean = false,
        val preClass: Boolean = false,
        val progressMax: Int = 0,
        val progressCur: Int = 0,
        val postReminder: Boolean = false,
        val clearReminder: Boolean = false,
        val reminderTitle: String = "",
        val reminderText: String = "",
    )

    private fun resolveState(state: WidgetState): ResolvedState = when (state) {
        is WidgetState.InSession -> resolveInSession(state)
        is WidgetState.NoCourseToday -> {
            val next = state.nextCourse
            val whereText = "${state.semesterName} 第${state.currentWeek}周"
            when {
                next != null -> ResolvedState(
                    next.titleText(),
                    "${state.nextCourseDay.orEmpty()} ${next.timeText} · ${next.location}".trim(),
                )
                state.todayFinished -> ResolvedState("今日课程已结束", whereText)
                else -> ResolvedState("今日无课", whereText)
            }
        }
        is WidgetState.ExamWeek -> examResolved(state.nextExam)
        is WidgetState.Vacation -> state.nextExam?.let { examResolved(it) } ?: run {
            val d = state.daysUntilStart?.let { "还有${it}天开学" } ?: ""
            ResolvedState("假期中", "${state.nextSemesterName ?: ""} $d".trim())
        }
        is WidgetState.NoCache -> ResolvedState("课程提示", "请打开 App 同步数据")
        is WidgetState.NotLoggedIn -> ResolvedState("课程提示", "请先登录")
        is WidgetState.Error -> ResolvedState("课程提示", "数据异常")
    }

    private fun resolveInSession(state: WidgetState.InSession): ResolvedState {
        if (state.todayCourses.isEmpty()) {
            return ResolvedState("今日无课", "${state.semesterName} 第${state.currentWeek}周")
        }

        val nowMin = currentMinuteOfDay()

        // 下一项：结束时间仍在未来的最早一项（课或考试）
        val item = state.todayCourses
            .filter { it.endMinute > nowMin }
            .minByOrNull { it.startMinute }
            ?: return ResolvedState("今日课程已结束", "共${state.todayCourses.size}节课")

        if (nowMin >= item.startMinute) {
            val parts = mutableListOf("${minuteText(item.endMinute)}${if (item.isExam) "结束" else "下课"}")
            if (item.location.isNotEmpty()) parts += item.location
            if (item.teacherName.isNotEmpty()) parts += item.teacherName
            return ResolvedState(
                title = "${item.courseName}（${if (item.isExam) "考试中" else "上课中"}）",
                text = parts.joinToString(" · "),
                inClass = true,
                progressMax = item.endMinute - item.startMinute,
                progressCur = nowMin - item.startMinute,
                clearReminder = true,
            )
        }

        val minutesUntil = item.startMinute - nowMin
        val sessionKey = "${java.time.LocalDate.now()}-${item.startMinute}"
        // 考试不发课前提醒推送，只在常驻通知中显示
        val shouldRemind = !item.isExam && minutesUntil <= 10 && lastRemindedKey != sessionKey
        if (shouldRemind) lastRemindedKey = sessionKey

        val parts = mutableListOf(item.timeText)
        if (item.location.isNotEmpty()) parts += item.location
        if (item.teacherName.isNotEmpty()) parts += item.teacherName

        return ResolvedState(
            title = item.titleText(),
            text = parts.joinToString(" · "),
            preClass = minutesUntil <= 10,
            postReminder = shouldRemind,
            reminderTitle = "${item.courseName} 即将开始",
            reminderText = buildString {
                append("${minutesUntil}分钟后")
                if (item.location.isNotEmpty()) append(" · ${item.location}")
                if (item.teacherName.isNotEmpty()) append(" · ${item.teacherName}")
            },
        )
    }

    private fun examResolved(exam: WidgetExamCard) = ResolvedState(
        title = "${exam.courseName}（考试）",
        text = listOf(exam.dateText(), exam.timeText, exam.location, exam.daysText())
            .filter { it.isNotEmpty() }.joinToString(" · "),
    )

    private fun WidgetCourseEntry.titleText(): String = if (isExam) "$courseName（考试）" else courseName

    // ── Notification builders ──

    private fun buildMainNotification(result: ResolvedState): android.app.Notification {
        val pi = PendingIntent.getActivity(
            this, 0,
            Intent(this, MainActivity::class.java).apply {
                putExtra("navigate_to", "schedule")
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

        val builder = NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_notif_schedule)
            .setContentTitle(result.title)
            .setContentText(result.text)
            .setContentIntent(pi)
            .setOngoing(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColor(0xFF5B5FE6.toInt())
            .setSilent(true)
            .setShowWhen(false)

        when {
            result.inClass && result.progressMax > 0 ->
                builder.setProgress(result.progressMax, result.progressCur, false)
            result.preClass ->
                builder.setProgress(0, 0, true)
        }

        return builder.build()
    }

    private fun postReminder(title: String, text: String) {
        val pi = PendingIntent.getActivity(
            this, 1,
            Intent(this, MainActivity::class.java).apply {
                putExtra("navigate_to", "schedule")
                flags = Intent.FLAG_ACTIVITY_SINGLE_TOP or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val n = NotificationCompat.Builder(this, CHANNEL_REMINDER_ID)
            .setSmallIcon(R.drawable.ic_notif_schedule)
            .setContentTitle(title)
            .setContentText(text)
            .setContentIntent(pi)
            .setAutoCancel(true)
            .setVisibility(NotificationCompat.VISIBILITY_PUBLIC)
            .setColor(0xFF5B5FE6.toInt())
            .setCategory(NotificationCompat.CATEGORY_REMINDER)
            .build()
        getSystemService(NotificationManager::class.java)?.notify(REMINDER_NOTIFICATION_ID, n)
    }

    private fun dismissReminder() {
        getSystemService(NotificationManager::class.java)?.cancel(REMINDER_NOTIFICATION_ID)
    }

    // ── Time helpers ──

    private fun minuteText(minuteOfDay: Int): String = "%02d:%02d".format(minuteOfDay / 60, minuteOfDay % 60)
}
