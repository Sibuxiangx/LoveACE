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

private val ROW_HEIGHT = 36.dp
private val TIME_COL_WIDTH = 20.dp
private val HEADER_HEIGHT = 18.dp

private val OnSurface = ColorProvider(Color(0xFF1C1B1F), Color(0xFFE6E1E5))
private val OnSurfaceVariant = ColorProvider(Color(0xFF49454F), Color(0xFFCAC4D0))
private val Surface = ColorProvider(Color(0xFFFFFBFE), Color(0xFF1C1B1F))
private val Primary = ColorProvider(Color(0xFF6750A4), Color(0xFFD0BCFF))
private val PrimaryContainer = ColorProvider(Color(0xFFEADDFF), Color(0xFF4F378B))
private val OnPrimaryContainer = ColorProvider(Color(0xFF21005D), Color(0xFFEADDFF))
private val Outline = ColorProvider(Color(0x1F000000), Color(0x1FFFFFFF))
private val TodayColumnBg = ColorProvider(Color(0x0C6750A4), Color(0x0CD0BCFF))

class SemesterWeekWidget : GlanceAppWidget() {
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
            is WidgetState.ExamWeek -> ExamWeekContent(state)
            is WidgetState.Vacation -> VacationContent(state)
            is WidgetState.InSession -> WeekGridContent(
                semesterName = state.semesterName, currentWeek = state.currentWeek,
                totalWeeks = state.totalWeeks, dayOfWeek = state.dayOfWeek,
                dateText = state.dateText, weekDays = state.weekDays,
                isEnding = state.isEnding,
                weekCourses = state.weekCourses, hasCourseData = state.hasCourseData,
                isDark = isDark,
            )
            is WidgetState.NoCourseToday -> WeekGridContent(
                semesterName = state.semesterName, currentWeek = state.currentWeek,
                totalWeeks = state.totalWeeks, dayOfWeek = state.dayOfWeek,
                dateText = state.dateText, weekDays = state.weekDays,
                isEnding = state.isEnding,
                weekCourses = state.weekCourses, hasCourseData = true,
                isDark = isDark,
            )
            is WidgetState.NoCache, is WidgetState.NotLoggedIn -> PlaceholderContent(
                icon = "📚", title = "等待数据同步",
                subtitle = "点击打开 App 加载课表",
            )
            is WidgetState.Error -> PlaceholderContent(
                icon = "⚠️", title = "加载失败",
                subtitle = "点击重试",
            )
        }
    }
}

@Composable
private fun VacationContent(state: WidgetState.Vacation) {
    Column(
        modifier = GlanceModifier.fillMaxSize().padding(16.dp),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Text("🏖️", style = TextStyle(fontSize = 36.sp))
        Spacer(GlanceModifier.height(8.dp))
        Text("假期中", style = TextStyle(color = OnSurface, fontSize = 18.sp, fontWeight = FontWeight.Bold))
        if (state.nextSemesterName != null && state.daysUntilStart != null) {
            Spacer(GlanceModifier.height(4.dp))
            Text(
                "${state.daysUntilStart} 天后开学",
                style = TextStyle(color = Primary, fontSize = 13.sp, fontWeight = FontWeight.Medium),
            )
            Spacer(GlanceModifier.height(2.dp))
            Text(state.nextSemesterName, style = TextStyle(color = OnSurfaceVariant, fontSize = 11.sp))
        }
        state.nextExam?.let { exam ->
            Spacer(GlanceModifier.height(10.dp))
            Text("下一场考试", style = TextStyle(color = OnSurfaceVariant, fontSize = 10.sp))
            Spacer(GlanceModifier.height(4.dp))
            ExamCardBlock(exam)
        }
    }
}

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

// ── 周课表网格 ──

@Composable
private fun WeekGridContent(
    semesterName: String,
    currentWeek: Int,
    totalWeeks: Int,
    dayOfWeek: Int,
    dateText: String,
    weekDays: List<WeekDayInfo>,
    isEnding: Boolean,
    weekCourses: Map<Int, List<WidgetCourseEntry>>,
    hasCourseData: Boolean,
    isDark: Boolean,
) {
    val grid = buildWidgetGrid(weekCourses)
    if (!hasCourseData && grid.isEmpty()) {
        PlaceholderContent("📚", "点击进入课程表", "尚未加载课程数据")
        return
    }

    val maxSession = widgetGridMaxSession(grid)

    Column(modifier = GlanceModifier.fillMaxSize()) {
        // Header bar
        Row(
            modifier = GlanceModifier.fillMaxWidth().padding(horizontal = 10.dp, vertical = 5.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Text(
                "第${currentWeek}周",
                style = TextStyle(color = OnSurface, fontSize = 12.sp, fontWeight = FontWeight.Bold),
            )
            Spacer(GlanceModifier.width(6.dp))
            Text(dateText, style = TextStyle(color = OnSurfaceVariant, fontSize = 10.sp))
            Spacer(GlanceModifier.defaultWeight())
            Text(semesterName, style = TextStyle(color = OnSurfaceVariant, fontSize = 9.sp))
        }

        // Weekday header row
        Row(modifier = GlanceModifier.fillMaxWidth().padding(horizontal = 1.dp)) {
            Box(GlanceModifier.width(TIME_COL_WIDTH).height(HEADER_HEIGHT), contentAlignment = Alignment.Center) {}
            for (d in 0..6) {
                val info = weekDays[d]
                Box(
                    modifier = GlanceModifier.defaultWeight().height(HEADER_HEIGHT),
                    contentAlignment = Alignment.Center,
                ) {
                    if (info.isToday) {
                        Box(
                            modifier = GlanceModifier
                                .size(width = 16.dp, height = 15.dp)
                                .cornerRadius(8.dp)
                                .background(PrimaryContainer),
                            contentAlignment = Alignment.Center,
                        ) {
                            Text(
                                WEEKDAY_LABELS[d],
                                style = TextStyle(color = OnPrimaryContainer, fontSize = 9.sp, fontWeight = FontWeight.Bold),
                            )
                        }
                    } else {
                        Text(
                            WEEKDAY_LABELS[d],
                            style = TextStyle(
                                color = if (info.isPast) OnSurfaceVariant else OnSurface,
                                fontSize = 9.sp,
                                fontWeight = FontWeight.Medium,
                            ),
                        )
                    }
                }
            }
        }

        Box(GlanceModifier.fillMaxWidth().height(1.dp).background(Outline)) {}

        // Scrollable grid body — column-per-day layout inside LazyColumn for scroll support
        val clickAction = actionStartActivity<MainActivity>(
            actionParametersOf(NavTargetKey to "schedule")
        )
        Column(modifier = GlanceModifier.fillMaxWidth().defaultWeight().padding(horizontal = 1.dp)) {
            Column(modifier = GlanceModifier.fillMaxWidth()) {
                Row(modifier = GlanceModifier.fillMaxWidth().clickable(clickAction)) {
                    // Session number column
                    Column(modifier = GlanceModifier.width(TIME_COL_WIDTH)) {
                        for (s in 1..maxSession) {
                            Box(
                                GlanceModifier.height(ROW_HEIGHT).fillMaxWidth(),
                                contentAlignment = Alignment.Center,
                            ) {
                                Text(
                                    "$s",
                                    style = TextStyle(color = OnSurfaceVariant, fontSize = 9.sp, fontWeight = FontWeight.Medium),
                                )
                            }
                        }
                    }

                    // 7 day columns
                    for (day in 1..7) {
                        val isToday = day == dayOfWeek
                        Column(modifier = GlanceModifier.defaultWeight()) {
                            var session = 1
                            while (session <= maxSession) {
                                val cell = grid["$day-$session"]
                                if (cell != null && cell.entry.sessionStart == session) {
                                    val cellHeight = ROW_HEIGHT * cell.rowSpan
                                    CourseCell(cell, isDark, GlanceModifier.fillMaxWidth().height(cellHeight).padding(1.dp))
                                    session += cell.rowSpan
                                } else if (cell != null) {
                                    session++
                                } else {
                                    if (isToday) {
                                        Box(
                                            modifier = GlanceModifier
                                                .fillMaxWidth()
                                                .height(ROW_HEIGHT)
                                                .padding(1.dp)
                                                .cornerRadius(3.dp)
                                                .background(TodayColumnBg),
                                        ) {}
                                    } else {
                                        Spacer(GlanceModifier.fillMaxWidth().height(ROW_HEIGHT))
                                    }
                                    session++
                                }
                            }
                        }
                    }
                }
            }
        }

        // Footer
        if (isEnding) {
            Box(
                GlanceModifier.fillMaxWidth().padding(vertical = 2.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    "第${currentWeek}/${totalWeeks}周 · 学期即将结束",
                    style = TextStyle(
                        color = ColorProvider(Color(0xFFD32F2F), Color(0xFFEF5350)),
                        fontSize = 9.sp,
                    ),
                )
            }
        }
    }
}

private fun truncateName(name: String, maxLen: Int = 6): String {
    return if (name.length > maxLen) name.take(maxLen) + "…" else name
}

@Composable
private fun CourseCell(
    cell: WidgetGridCell,
    isDark: Boolean,
    modifier: GlanceModifier,
) {
    val c = cell.entry.paletteColor(isDark)
    val bgColor = ColorProvider(c.bg, c.bg)
    val borderColor = ColorProvider(c.border, c.border)
    val textColor = ColorProvider(c.text, c.text)

    Box(
        modifier = modifier
            .cornerRadius(5.dp)
            .background(bgColor)
            .padding(start = 3.dp),
    ) {
        // Left accent border
        Box(
            modifier = GlanceModifier
                .width(3.dp)
                .fillMaxHeight()
                .padding(vertical = 3.dp)
                .cornerRadius(2.dp)
                .background(borderColor),
        ) {}
        // Content
        Column(
            modifier = GlanceModifier
                .fillMaxSize()
                .padding(start = 5.dp, end = 2.dp, top = 2.dp, bottom = 2.dp),
        ) {
            Text(
                truncateName(cell.entry.courseName),
                style = TextStyle(color = textColor, fontSize = 8.sp, fontWeight = FontWeight.Bold),
                maxLines = if (cell.rowSpan >= 2) 2 else 1,
            )
            if (cell.entry.location.isNotEmpty()) {
                Text(
                    cell.entry.location,
                    style = TextStyle(color = textColor, fontSize = 7.sp),
                    maxLines = 2,
                )
            }
            if (cell.entry.teacherName.isNotEmpty()) {
                Text(
                    cell.entry.teacherName,
                    style = TextStyle(color = textColor, fontSize = 7.sp),
                    maxLines = 1,
                )
            }
        }
    }
}

class SemesterWeekWidgetReceiver : GlanceAppWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = SemesterWeekWidget()
}
