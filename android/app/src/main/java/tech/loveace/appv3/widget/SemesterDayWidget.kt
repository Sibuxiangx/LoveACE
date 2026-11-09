package tech.loveace.appv3.widget

import android.content.Context
import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.glance.*
import androidx.glance.appwidget.*
import androidx.glance.appwidget.lazy.LazyColumn
import androidx.glance.appwidget.lazy.items
import androidx.glance.layout.*
import androidx.glance.text.*
import androidx.glance.action.ActionParameters
import androidx.glance.action.actionParametersOf
import androidx.glance.action.actionStartActivity
import androidx.glance.action.clickable
import androidx.glance.color.ColorProvider
import tech.loveace.appv3.MainActivity

private val NavTargetKey = ActionParameters.Key<String>("navigate_to")
private val WEEKDAY_LABELS = arrayOf("一", "二", "三", "四", "五", "六", "日")

private val OnSurface = ColorProvider(Color(0xFF1C1B1F), Color(0xFFE6E1E5))
private val OnSurfaceVariant = ColorProvider(Color(0xFF49454F), Color(0xFFCAC4D0))
private val Surface = ColorProvider(Color(0xFFFFFBFE), Color(0xFF1C1B1F))
private val Primary = ColorProvider(Color(0xFF6750A4), Color(0xFFD0BCFF))
private val PrimaryContainer = ColorProvider(Color(0xFFEADDFF), Color(0xFF4F378B))
private val OnPrimaryContainer = ColorProvider(Color(0xFF21005D), Color(0xFFEADDFF))
private val Outline = ColorProvider(Color(0x1F000000), Color(0x1FFFFFFF))
private val DayRed = ColorProvider(Color(0xFFD32F2F), Color(0xFFEF5350))

class SemesterDayWidget : GlanceAppWidget() {
    override suspend fun provideGlance(context: Context, id: GlanceId) {
        val state = try { fetchWidgetState(context) } catch (_: Exception) { WidgetState.Error }
        val isDark = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            context.resources.configuration.isNightModeActive
        } else false
        provideContent { Content(state, isDark) }
    }
}

@Composable
private fun Content(state: WidgetState, isDark: Boolean) {
    val clickAction = actionStartActivity<MainActivity>(
        actionParametersOf(NavTargetKey to "schedule")
    )
    Box(
        modifier = GlanceModifier
            .fillMaxSize()
            .cornerRadius(20.dp)
            .background(Surface)
            .clickable(clickAction),
    ) {
        when (state) {
            is WidgetState.Vacation -> VacationContent(state)
            is WidgetState.InSession -> DayScheduleContent(state, isDark)
            is WidgetState.NoCourseToday -> NoCourseContent(state, isDark)
            is WidgetState.ExamWeek -> ExamWeekContent(state)
            is WidgetState.NoCache, is WidgetState.NotLoggedIn -> PlaceholderContent(
                "📚", "等待数据同步", "点击打开 App 加载课表",
            )
            is WidgetState.Error -> PlaceholderContent("⚠️", "加载失败", "点击重试")
        }
    }
}

// ── 假期 ──

@Composable
private fun VacationContent(state: WidgetState.Vacation) {
    Column(
        modifier = GlanceModifier.fillMaxSize().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("🏖️", style = TextStyle(fontSize = 32.sp))
        Spacer(GlanceModifier.height(8.dp))
        Text("假期中", style = TextStyle(color = OnSurface, fontSize = 18.sp, fontWeight = FontWeight.Bold))
        if (state.nextSemesterName != null && state.daysUntilStart != null) {
            Spacer(GlanceModifier.height(4.dp))
            Text(
                "${state.daysUntilStart} 天后开学",
                style = TextStyle(color = Primary, fontSize = 13.sp, fontWeight = FontWeight.Medium),
            )
        }
        state.nextExam?.let { exam ->
            Spacer(GlanceModifier.height(10.dp))
            Text("下一场考试", style = TextStyle(color = OnSurfaceVariant, fontSize = 10.sp))
            Spacer(GlanceModifier.height(4.dp))
            ExamCardBlock(exam)
        }
    }
}

// ── 占位 ──

@Composable
private fun PlaceholderContent(icon: String, title: String, subtitle: String) {
    Column(
        modifier = GlanceModifier.fillMaxSize().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(icon, style = TextStyle(fontSize = 28.sp))
        Spacer(GlanceModifier.height(8.dp))
        Text(title, style = TextStyle(color = OnSurface, fontSize = 14.sp, fontWeight = FontWeight.Bold))
        Spacer(GlanceModifier.height(4.dp))
        Text(subtitle, style = TextStyle(color = OnSurfaceVariant, fontSize = 11.sp))
    }
}

// ── 今日课程列表 ──

@Composable
private fun DayScheduleContent(state: WidgetState.InSession, isDark: Boolean) {
    Column(modifier = GlanceModifier.fillMaxSize()) {
        // Header
        HeaderBar(
            weekText = "第${state.currentWeek}周",
            dayText = state.dayOfWeekText,
            dateText = state.dateText,
            courseCount = state.todayCourses.size,
        )

        // Weekday indicator
        WeekdayIndicatorRow(state.weekDays)

        Box(GlanceModifier.fillMaxWidth().height(1.dp).padding(horizontal = 8.dp).background(Outline)) {}

        if (state.todayCourses.isEmpty()) {
            PlaceholderContent("📚", "点击进入课程表", "尚未加载课程数据")
        } else {
            val clickAction = actionStartActivity<MainActivity>(
                actionParametersOf(NavTargetKey to "schedule")
            )
            Column(
                modifier = GlanceModifier
                    .fillMaxWidth()
                    .defaultWeight()
                    .padding(horizontal = 8.dp, vertical = 4.dp),
            ) {
                state.todayCourses.forEach { course ->
                    Box(modifier = GlanceModifier.clickable(clickAction)) {
                        CourseCard(course, isDark)
                    }
                }
            }
        }

        if (state.isEnding) {
            Box(GlanceModifier.fillMaxWidth().padding(vertical = 2.dp), contentAlignment = Alignment.Center) {
                Text(
                    "第${state.currentWeek}/${state.totalWeeks}周 · 学期即将结束",
                    style = TextStyle(color = DayRed, fontSize = 9.sp),
                )
            }
        }
    }
}

// ── 今日无课 ──

@Composable
private fun NoCourseContent(state: WidgetState.NoCourseToday, isDark: Boolean) {
    Column(modifier = GlanceModifier.fillMaxSize()) {
        HeaderBar(
            weekText = "第${state.currentWeek}周",
            dayText = state.dayOfWeekText,
            dateText = state.dateText,
            courseCount = 0,
        )

        WeekdayIndicatorRow(state.weekDays)

        Box(GlanceModifier.fillMaxWidth().height(1.dp).padding(horizontal = 8.dp).background(Outline)) {}

        Column(
            modifier = GlanceModifier.fillMaxWidth().defaultWeight().padding(16.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(if (state.todayFinished) "✅" else "😴", style = TextStyle(fontSize = 32.sp))
            Spacer(GlanceModifier.height(6.dp))
            Text(
                if (state.todayFinished) "今日课程已结束" else "今日无课",
                style = TextStyle(color = OnSurface, fontSize = 16.sp, fontWeight = FontWeight.Bold),
            )

            if (state.nextCourse != null && state.nextCourseDay != null) {
                Spacer(GlanceModifier.height(10.dp))
                Text("下一节课", style = TextStyle(color = OnSurfaceVariant, fontSize = 10.sp))
                Spacer(GlanceModifier.height(4.dp))
                NextCourseCard(state.nextCourseDay, state.nextCourse, isDark)
            }
        }

        if (state.isEnding) {
            Box(GlanceModifier.fillMaxWidth().padding(vertical = 2.dp), contentAlignment = Alignment.Center) {
                Text(
                    "第${state.currentWeek}/${state.totalWeeks}周 · 学期即将结束",
                    style = TextStyle(color = DayRed, fontSize = 9.sp),
                )
            }
        }
    }
}

// ── 考试 ──

@Composable
internal fun ExamWeekContent(state: WidgetState.ExamWeek) {
    Column(
        modifier = GlanceModifier.fillMaxSize().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("📝", style = TextStyle(fontSize = 28.sp))
        Spacer(GlanceModifier.height(6.dp))
        Text("考试周", style = TextStyle(color = OnSurface, fontSize = 16.sp, fontWeight = FontWeight.Bold))
        Spacer(GlanceModifier.height(10.dp))
        Text("下一场考试", style = TextStyle(color = OnSurfaceVariant, fontSize = 10.sp))
        Spacer(GlanceModifier.height(4.dp))
        ExamCardBlock(state.nextExam)
    }
}

@Composable
internal fun ExamCardBlock(exam: WidgetExamCard) {
    Column(
        modifier = GlanceModifier
            .fillMaxWidth()
            .cornerRadius(10.dp)
            .background(PrimaryContainer)
            .padding(horizontal = 10.dp, vertical = 8.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Text(
            exam.courseName,
            style = TextStyle(color = OnPrimaryContainer, fontSize = 13.sp, fontWeight = FontWeight.Bold),
            maxLines = 1,
        )
        Spacer(GlanceModifier.height(2.dp))
        Text(
            listOf(exam.dateText(), exam.timeText).filter { it.isNotEmpty() }.joinToString(" "),
            style = TextStyle(color = OnPrimaryContainer, fontSize = 10.sp),
        )
        if (exam.location.isNotEmpty()) {
            Text(
                exam.location,
                style = TextStyle(color = OnPrimaryContainer, fontSize = 10.sp),
                maxLines = 2,
            )
        }
        Spacer(GlanceModifier.height(2.dp))
        Text(
            exam.daysText(),
            style = TextStyle(color = OnPrimaryContainer, fontSize = 11.sp, fontWeight = FontWeight.Bold),
        )
    }
}

// ── 通用组件 ──

@Composable
private fun HeaderBar(weekText: String, dayText: String, dateText: String, courseCount: Int) {
    Row(
        modifier = GlanceModifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text(weekText, style = TextStyle(color = Primary, fontSize = 13.sp, fontWeight = FontWeight.Bold))
        Spacer(GlanceModifier.width(8.dp))
        Text(dayText, style = TextStyle(color = OnSurface, fontSize = 13.sp, fontWeight = FontWeight.Bold))
        Spacer(GlanceModifier.width(6.dp))
        Text(dateText, style = TextStyle(color = OnSurfaceVariant, fontSize = 11.sp))
        Spacer(GlanceModifier.defaultWeight())
        if (courseCount > 0) {
            Text(
                "${courseCount}节课",
                style = TextStyle(color = Primary, fontSize = 11.sp, fontWeight = FontWeight.Medium),
            )
        }
    }
}

@Composable
private fun WeekdayIndicatorRow(weekDays: List<WeekDayInfo>) {
    Row(
        modifier = GlanceModifier.fillMaxWidth().padding(horizontal = 12.dp, vertical = 4.dp),
    ) {
        for (i in 0..6) {
            val info = weekDays[i]
            Box(
                modifier = GlanceModifier.defaultWeight().height(20.dp),
                contentAlignment = Alignment.Center,
            ) {
                if (info.isToday) {
                    Box(
                        modifier = GlanceModifier
                            .size(20.dp)
                            .cornerRadius(10.dp)
                            .background(PrimaryContainer),
                        contentAlignment = Alignment.Center,
                    ) {
                        Text(
                            WEEKDAY_LABELS[i],
                            style = TextStyle(
                                color = OnPrimaryContainer,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Bold,
                            ),
                        )
                    }
                } else {
                    Column(horizontalAlignment = Alignment.CenterHorizontally) {
                        Text(
                            WEEKDAY_LABELS[i],
                            style = TextStyle(
                                color = if (info.isPast) OnSurfaceVariant else OnSurface,
                                fontSize = 10.sp,
                                fontWeight = FontWeight.Medium,
                            ),
                        )
                    }
                }
            }
        }
    }
}

@Composable
private fun CourseCard(course: WidgetCourseEntry, isDark: Boolean) {
    val c = course.paletteColor(isDark)
    val bgColor = ColorProvider(c.bg, c.bg)
    val borderColor = ColorProvider(c.border, c.border)
    val textColor = ColorProvider(c.text, c.text)

    Row(
        modifier = GlanceModifier
            .fillMaxWidth()
            .padding(vertical = 2.dp)
            .cornerRadius(8.dp)
            .background(bgColor)
            .padding(start = 3.dp, end = 8.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Left accent border
        Box(
            modifier = GlanceModifier
                .width(3.dp)
                .height(36.dp)
                .cornerRadius(2.dp)
                .background(borderColor),
        ) {}
        Spacer(GlanceModifier.width(8.dp))

        // Session info
        Column(modifier = GlanceModifier.width(52.dp)) {
            Text(
                course.sessionText,
                style = TextStyle(color = textColor, fontSize = 11.sp, fontWeight = FontWeight.Bold),
            )
            Text(
                course.timeText,
                style = TextStyle(color = OnSurfaceVariant, fontSize = 9.sp),
            )
        }

        Spacer(GlanceModifier.width(6.dp))

        // Course info
        Column(modifier = GlanceModifier.defaultWeight()) {
            Text(
                course.courseName,
                style = TextStyle(color = OnSurface, fontSize = 12.sp, fontWeight = FontWeight.Bold),
                maxLines = 1,
            )
            if (course.location.isNotEmpty()) {
                Text(
                    course.location,
                    style = TextStyle(color = OnSurfaceVariant, fontSize = 10.sp),
                    maxLines = 2,
                )
            }
            if (course.teacherName.isNotEmpty()) {
                Text(
                    course.teacherName,
                    style = TextStyle(color = OnSurfaceVariant, fontSize = 9.sp),
                    maxLines = 1,
                )
            }
        }
    }
}

@Composable
private fun NextCourseCard(
    dayLabel: String,
    course: WidgetCourseEntry,
    isDark: Boolean,
) {
    val c = course.paletteColor(isDark)
    val bgColor = ColorProvider(c.bg, c.bg)
    val borderColor = ColorProvider(c.border, c.border)
    val textColor = ColorProvider(c.text, c.text)

    Row(
        modifier = GlanceModifier
            .cornerRadius(10.dp)
            .background(bgColor)
            .padding(start = 3.dp, end = 10.dp, top = 8.dp, bottom = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(
            modifier = GlanceModifier
                .width(3.dp)
                .height(30.dp)
                .cornerRadius(2.dp)
                .background(borderColor),
        ) {}
        Spacer(GlanceModifier.width(8.dp))
        Text(
            dayLabel,
            style = TextStyle(color = textColor, fontSize = 11.sp, fontWeight = FontWeight.Bold),
        )
        Spacer(GlanceModifier.width(8.dp))
        Column {
            Text(
                course.courseName,
                style = TextStyle(color = OnSurface, fontSize = 12.sp, fontWeight = FontWeight.Medium),
                maxLines = 1,
            )
            Text(
                (if (course.isExam) listOf("考试", course.timeText, course.location)
                else listOf(course.sessionText, course.location))
                    .filter { it.isNotEmpty() }.joinToString(" · "),
                style = TextStyle(color = OnSurfaceVariant, fontSize = 10.sp),
                maxLines = 1,
            )
            if (course.teacherName.isNotEmpty()) {
                Text(
                    course.teacherName,
                    style = TextStyle(color = OnSurfaceVariant, fontSize = 9.sp),
                    maxLines = 1,
                )
            }
        }
    }
}

class SemesterDayWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = SemesterDayWidget()
}
