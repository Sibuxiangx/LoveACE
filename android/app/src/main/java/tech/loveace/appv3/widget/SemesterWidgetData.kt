package tech.loveace.appv3.widget

import android.content.Context
import androidx.compose.ui.graphics.Color
import kotlinx.serialization.SerialName
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import tech.loveace.appv3.data.model.ScheduleCourse
import tech.loveace.appv3.data.model.ScheduleTimePlace
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalTime
import java.time.temporal.ChronoUnit

// ── 小组件数据（从缓存读取，不做网络请求） ──

// ── JSON 模型 ──

@Serializable
data class WidgetSemesterData(
    val version: Int = 1,
    @SerialName("updated_at") val updatedAt: String = "",
    val semesters: List<WidgetSemesterItem> = emptyList(),
)

@Serializable
data class WidgetSemesterItem(
    val code: String,
    val name: String,
    @SerialName("start_date") val startDate: String,
    val weeks: Int = 18,
)

/** 本地考试快照（widget_cache/exams.json）。文件缺失或旧快照都表示"无考试"。 */
@Serializable
data class WidgetExamSnapshot(
    val exams: List<WidgetExamItem> = emptyList(),
)

/** 一场考试。examDate 为 yyyy-MM-dd（同步时已规范化），examTime 原样保存，如 "14:00-16:00"。 */
@Serializable
data class WidgetExamItem(
    val courseName: String = "",
    val examDate: String = "",
    val examTime: String = "",
    val examLocation: String = "",
)

private val TERM_MAP = mapOf("1" to "秋季学期", "2" to "春季学期")

fun WidgetSemesterItem.displayName(): String {
    val parts = code.split("-")
    if (parts.size == 3) {
        val termText = TERM_MAP[parts[2]] ?: "第${parts[2]}学期"
        return "${parts[0]}-${parts[1]} $termText"
    }
    return name.ifEmpty { code }
}

// ── 节次时间映射 ──

private val SESSION_TIMES = mapOf(
    1 to "08:00", 2 to "08:55", 3 to "10:10", 4 to "11:05",
    5 to "14:00", 6 to "14:55", 7 to "16:10", 8 to "17:05",
    9 to "19:00", 10 to "19:55", 11 to "20:50",
)

/** 每节课时长（分钟）：节次结束 = 结束节次开始 + 45 分钟 */
private const val CLASS_DURATION_MINUTES = 45

private val EXAM_TIME_RANGE = Regex("(\\d{1,2})[:：](\\d{2})\\s*[-~～—–至到]\\s*(\\d{1,2})[:：](\\d{2})")

fun sessionTimeRange(start: Int, end: Int): String {
    val s = SESSION_TIMES[start] ?: "第${start}节"
    val e = SESSION_TIMES[end]?.let { t ->
        val h = t.substringBefore(":").toInt()
        val m = t.substringAfter(":").toInt() + CLASS_DURATION_MINUTES
        "%02d:%02d".format(h + m / 60, m % 60)
    } ?: "第${end}节"
    return "$s-$e"
}

/** 节次开始时刻（当天第几分钟）；未知节次返回 null */
private fun sessionStartMinute(session: Int): Int? =
    SESSION_TIMES[session]?.let { LocalTime.parse(it).let { t -> t.hour * 60 + t.minute } }

/** 当前时刻（当天第几分钟） */
fun currentMinuteOfDay(): Int = LocalTime.now().let { it.hour * 60 + it.minute }

// ── 课程配色（与 ScheduleScreen 一致） ──

data class WidgetCourseColor(val bg: Color, val border: Color, val text: Color)

val WIDGET_COURSE_COLORS = listOf(
    WidgetCourseColor(Color(0x2E0078D4), Color(0x800078D4), Color(0xFF0063B1)),
    WidgetCourseColor(Color(0x2E107C10), Color(0x80107C10), Color(0xFF0E6E0E)),
    WidgetCourseColor(Color(0x2E881798), Color(0x80881798), Color(0xFF6B1076)),
    WidgetCourseColor(Color(0x2ECA5010), Color(0x80CA5010), Color(0xFFA34D0A)),
    WidgetCourseColor(Color(0x2E0063B1), Color(0x800063B1), Color(0xFF004E8C)),
    WidgetCourseColor(Color(0x2EE3008C), Color(0x80E3008C), Color(0xFFB3006E)),
    WidgetCourseColor(Color(0x2E008575), Color(0x80008575), Color(0xFF006A5D)),
    WidgetCourseColor(Color(0x2E8E562E), Color(0x808E562E), Color(0xFF6E4224)),
    WidgetCourseColor(Color(0x2E0099BC), Color(0x800099BC), Color(0xFF007A96)),
    WidgetCourseColor(Color(0x2E7A7574), Color(0x807A7574), Color(0xFF3B3A39)),
)

val WIDGET_COURSE_COLORS_DARK = listOf(
    WidgetCourseColor(Color(0x2E4CA6E8), Color(0x804CA6E8), Color(0xFF8DC9F9)),
    WidgetCourseColor(Color(0x2E4CAF50), Color(0x804CAF50), Color(0xFF81C784)),
    WidgetCourseColor(Color(0x2EBA68C8), Color(0x80BA68C8), Color(0xFFCE93D8)),
    WidgetCourseColor(Color(0x2EFF9800), Color(0x80FF9800), Color(0xFFFFCC80)),
    WidgetCourseColor(Color(0x2E42A5F5), Color(0x8042A5F5), Color(0xFF90CAF9)),
    WidgetCourseColor(Color(0x2EEC407A), Color(0x80EC407A), Color(0xFFF48FB1)),
    WidgetCourseColor(Color(0x2E26A69A), Color(0x8026A69A), Color(0xFF80CBC4)),
    WidgetCourseColor(Color(0x2EA1887F), Color(0x80A1887F), Color(0xFFBCAAA4)),
    WidgetCourseColor(Color(0x2E29B6F6), Color(0x8029B6F6), Color(0xFF81D4FA)),
    WidgetCourseColor(Color(0x2E9E9E9E), Color(0x809E9E9E), Color(0xFFBDBDBD)),
)

/** 考试统一用警示色，不占用课程配色 */
val WIDGET_EXAM_COLOR = WidgetCourseColor(Color(0x2ED32F2F), Color(0x80D32F2F), Color(0xFFD32F2F))
val WIDGET_EXAM_COLOR_DARK = WidgetCourseColor(Color(0x2EEF5350), Color(0x80EF5350), Color(0xFFEF9A9A))

// ── 小组件课程条目（课程与考试共用） ──

/**
 * 当天/某周的一项：课程或考试。
 * startMinute / endMinute 为当天第几分钟，用于"下一项"判断；考试时间无法解析时为全天。
 * 考试的 sessionStart / sessionEnd 为时间重叠的节次；时间无法解析时为 0（不占周课表格子）。
 */
data class WidgetCourseEntry(
    val courseName: String,
    val location: String,
    val teacherName: String = "",
    val sessionStart: Int,
    val sessionEnd: Int,
    val timeText: String,       // "08:00-09:40"，考试为原始考试时间
    val sessionText: String,    // "1-2节"，考试为"考试"
    val colorIndex: Int = 0,
    val startMinute: Int,
    val endMinute: Int,
    val isExam: Boolean = false,
) {
    val rowSpan get() = sessionEnd - sessionStart + 1

    fun paletteColor(isDark: Boolean): WidgetCourseColor = when {
        isExam -> if (isDark) WIDGET_EXAM_COLOR_DARK else WIDGET_EXAM_COLOR
        else -> (if (isDark) WIDGET_COURSE_COLORS_DARK else WIDGET_COURSE_COLORS).let { it[colorIndex % it.size] }
    }
}

// ── 小组件考试卡片 ──

data class WidgetExamCard(
    val courseName: String,
    val date: LocalDate,
    val timeText: String,
    val location: String,
    val daysUntil: Long,
)

fun WidgetExamCard.dateText(): String =
    "${date.monthValue}月${date.dayOfMonth}日 ${WEEKDAY_NAMES[date.dayOfWeek.value - 1]}"

fun WidgetExamCard.daysText(): String = if (daysUntil <= 0L) "今天考试" else "还有${daysUntil}天"

// ── 周课表网格 ──

data class WidgetGridCell(
    val entry: WidgetCourseEntry,
    val rowSpan: Int,
)

fun buildWidgetGrid(
    weekCourses: Map<Int, List<WidgetCourseEntry>>,
): Map<String, WidgetGridCell> {
    val grid = mutableMapOf<String, WidgetGridCell>()
    for ((day, entries) in weekCourses) {
        for (entry in entries) {
            if (entry.sessionStart < 1) continue // 时间未知的考试不占格
            val cell = WidgetGridCell(entry, entry.rowSpan)
            for (s in entry.sessionStart..entry.sessionEnd) {
                grid["$day-$s"] = cell
            }
        }
    }
    return grid
}

fun widgetGridMaxSession(grid: Map<String, WidgetGridCell>): Int {
    var max = 0
    for ((_, cell) in grid) {
        val end = cell.entry.sessionEnd
        if (end > max) max = end
    }
    return max.coerceIn(8, 12)
}

fun isWidgetCellCovered(grid: Map<String, WidgetGridCell>, day: Int, session: Int): Boolean {
    for (s in (session - 1) downTo 1) {
        val cell = grid["$day-$s"] ?: continue
        if (s + cell.rowSpan > session) return true
    }
    return false
}

// ── 小组件状态 ──

sealed class WidgetState {
    data class Vacation(
        val nextSemesterName: String? = null,
        val nextStartDate: String? = null,
        val daysUntilStart: Long? = null,
        val nextExam: WidgetExamCard? = null,
    ) : WidgetState()

    data class InSession(
        val semesterName: String,
        val currentWeek: Int,
        val totalWeeks: Int,
        val dayOfWeek: Int,
        val dayOfWeekText: String,
        val dateText: String,
        val weekDays: List<WeekDayInfo>,
        val isEnding: Boolean,
        val todayCourses: List<WidgetCourseEntry>,
        val weekCourses: Map<Int, List<WidgetCourseEntry>>, // dayOfWeek(1-7) -> courses
        val hasCourseData: Boolean,
    ) : WidgetState()

    /** 学期中，今天没有剩余的课程或考试：下一项槽位显示之后最早的一项 */
    data class NoCourseToday(
        val semesterName: String,
        val currentWeek: Int,
        val totalWeeks: Int,
        val dayOfWeek: Int,
        val dayOfWeekText: String,
        val dateText: String,
        val weekDays: List<WeekDayInfo>,
        val isEnding: Boolean,
        val weekCourses: Map<Int, List<WidgetCourseEntry>>,
        val nextCourse: WidgetCourseEntry? = null,
        val nextCourseDay: String? = null,
        val todayFinished: Boolean = false,
    ) : WidgetState()

    /** 教学结束后仍有未结束的考试 */
    data class ExamWeek(val nextExam: WidgetExamCard) : WidgetState()

    /** 尚未缓存数据，需要先打开 App */
    data object NoCache : WidgetState()

    /** App 未登录 */
    data object NotLoggedIn : WidgetState()

    data object Error : WidgetState()
}

data class WeekDayInfo(
    val dayOfWeek: String,
    val dayOfMonth: Int,
    val isToday: Boolean,
    val isPast: Boolean,
    val courseCount: Int = 0,
)

// ── 学期阶段（App 首页与小组件共用） ──

sealed class SemesterPhase {
    /** 教学周内（含第 weeks 周周末），weekNum 从 1 开始 */
    data class Teaching(val semester: WidgetSemesterItem, val weekNum: Int) : SemesterPhase()

    /** 教学结束后仍有日期 >= 今天的考试 */
    data class ExamWeek(val nextExam: WidgetExamCard) : SemesterPhase()

    /** 假期：未开学，或教学结束且没有未结束的考试 */
    data class Vacation(
        val nextSemester: WidgetSemesterItem? = null,
        val daysUntilStart: Long? = null,
        val nextExam: WidgetExamCard? = null,
    ) : SemesterPhase()
}

/**
 * 学期阶段判定。教学结束 = start + weeks*7 天（下一周一）。
 * 教学周内（含第 18 周周末）为 Teaching，考试只影响课表条目，不影响周次。
 * 教学结束后，只要存在日期 >= today 的考试即为 ExamWeek；考试全部结束后回到假期。
 */
fun resolveSemesterPhase(
    semesters: List<WidgetSemesterItem>,
    exams: List<WidgetExamItem>,
    today: LocalDate,
): SemesterPhase {
    val nextExam = exams
        .map { it to LocalDate.parse(it.examDate) }
        .filter { !it.second.isBefore(today) }
        .minByOrNull { it.second }
        ?.let { (exam, date) ->
            WidgetExamCard(exam.courseName, date, exam.examTime, exam.examLocation, ChronoUnit.DAYS.between(today, date))
        }

    var anyEnded = false
    var upcoming: WidgetSemesterItem? = null
    for (sem in semesters.sortedBy { it.startDate }) {
        val start = LocalDate.parse(sem.startDate)
        if (today.isBefore(start)) {
            upcoming = sem
            break
        }
        if (today.isBefore(start.plusWeeks(sem.weeks.toLong()))) {
            return SemesterPhase.Teaching(sem, (ChronoUnit.DAYS.between(start, today) / 7 + 1).toInt())
        }
        anyEnded = true
    }

    if (anyEnded && nextExam != null) return SemesterPhase.ExamWeek(nextExam)
    return SemesterPhase.Vacation(
        nextSemester = upcoming,
        daysUntilStart = upcoming?.let { ChronoUnit.DAYS.between(today, LocalDate.parse(it.startDate)) },
        nextExam = nextExam,
    )
}

// ── 数据获取 ──

private val json = Json { ignoreUnknownKeys = true }
private val WEEKDAY_NAMES = arrayOf("周一", "周二", "周三", "周四", "周五", "周六", "周日")
private val WEEKDAY_SHORT = arrayOf("一", "二", "三", "四", "五", "六", "日")

/** 读取本地考试快照；缺失或损坏都视为无考试 */
fun loadWidgetExams(context: Context): List<WidgetExamItem> {
    val raw = WidgetDataStore.loadExamsJson(context) ?: return emptyList()
    return try {
        json.decodeFromString<WidgetExamSnapshot>(raw).exams
    } catch (e: Exception) {
        android.util.Log.e("WidgetData", "Exam snapshot decode failed", e)
        emptyList()
    }
}

fun fetchWidgetState(context: Context): WidgetState {
    return try {
        val semJson = WidgetDataStore.loadSemesterJson(context)
        if (semJson == null) {
            android.util.Log.w("WidgetData", "No cached semester data")
            return WidgetState.NoCache
        }
        val semData = json.decodeFromString<WidgetSemesterData>(semJson)
        val coursesJson = WidgetDataStore.loadCoursesJson(context)
        val courses: List<ScheduleCourse> = if (coursesJson != null) {
            try { json.decodeFromString(coursesJson) } catch (_: Exception) { emptyList() }
        } else emptyList()
        val exams = loadWidgetExams(context)
        android.util.Log.d("WidgetData", "File cache: ${semData.semesters.size} semesters, ${courses.size} courses, ${exams.size} exams")
        computeWidgetState(semData, exams, courses)
    } catch (e: Exception) {
        android.util.Log.e("WidgetData", "fetchWidgetState failed", e)
        WidgetState.Error
    }
}

/** 判断课程在第 weekNum 周是否有课 */
private fun ScheduleTimePlace.runsInWeek(weekNum: Int): Boolean {
    if (weekNum < 1 || weekNum > classWeek.length) return false
    // classWeek 是 24 位二进制字符串，0-indexed: index 0 = 第1周
    val idx = weekNum - 1
    return idx < classWeek.length && classWeek[idx] == '1'
}

private fun filterCoursesForDay(
    courses: List<ScheduleCourse>, weekNum: Int, dayOfWeek: Int,
    colorMap: Map<String, Int>,
): List<WidgetCourseEntry> {
    val entries = mutableListOf<WidgetCourseEntry>()
    for (course in courses) {
        for (tp in course.timeAndPlaceList) {
            if (tp.classDay == dayOfWeek && tp.runsInWeek(weekNum)) {
                val end = tp.classSessions + tp.continuingSession - 1
                entries.add(
                    WidgetCourseEntry(
                        courseName = course.courseName,
                        location = listOf(tp.teachingBuildingName, tp.classroomName)
                            .filter { it.isNotEmpty() }.joinToString(" "),
                        teacherName = course.attendClassTeacher,
                        sessionStart = tp.classSessions,
                        sessionEnd = end,
                        timeText = sessionTimeRange(tp.classSessions, end),
                        sessionText = "${tp.classSessions}-${end}节",
                        colorIndex = colorMap[course.courseCode] ?: 0,
                        startMinute = sessionStartMinute(tp.classSessions) ?: 0,
                        endMinute = sessionStartMinute(end)?.plus(CLASS_DURATION_MINUTES) ?: 24 * 60,
                    )
                )
            }
        }
    }
    return entries.sortedBy { it.startMinute }
}

/**
 * 考试转为课表条目：占用与考试时间重叠的节次。
 * 时间无法解析时不占节次（sessionStart = 0），但仍显示在当天列表中并视为全天。
 */
private fun WidgetExamItem.toCourseEntry(): WidgetCourseEntry {
    val m = EXAM_TIME_RANGE.find(examTime)
    if (m == null) {
        return WidgetCourseEntry(
            courseName = courseName,
            location = examLocation,
            sessionStart = 0,
            sessionEnd = 0,
            timeText = "时间待定",
            sessionText = "考试",
            startMinute = 0,
            endMinute = 24 * 60,
            isExam = true,
        )
    }
    val startMin = m.groupValues[1].toInt() * 60 + m.groupValues[2].toInt()
    val endMin = m.groupValues[3].toInt() * 60 + m.groupValues[4].toInt()
    val sessions = SESSION_TIMES.keys.sorted()
    val sessionStart = sessions.lastOrNull { (sessionStartMinute(it) ?: 0) <= startMin } ?: 1
    val sessionEnd = sessions
        .lastOrNull { (sessionStartMinute(it) ?: 0) < endMin }
        ?.let { maxOf(it, sessionStart) } ?: sessionStart
    return WidgetCourseEntry(
        courseName = courseName,
        location = examLocation,
        sessionStart = sessionStart,
        sessionEnd = sessionEnd,
        timeText = examTime,
        sessionText = "考试",
        startMinute = startMin,
        endMinute = endMin,
        isExam = true,
    )
}

private fun buildCourseColorMap(courses: List<ScheduleCourse>): Map<String, Int> {
    val map = mutableMapOf<String, Int>()
    var idx = 0
    for (course in courses) {
        if (course.courseCode !in map) {
            map[course.courseCode] = idx % WIDGET_COURSE_COLORS.size
            idx++
        }
    }
    return map
}

private fun computeWidgetState(
    data: WidgetSemesterData,
    exams: List<WidgetExamItem>,
    courses: List<ScheduleCourse>,
): WidgetState {
    val today = LocalDate.now()
    return when (val phase = resolveSemesterPhase(data.semesters, exams, today)) {
        is SemesterPhase.Teaching -> teachingState(phase.semester, phase.weekNum, today, courses, exams)
        is SemesterPhase.ExamWeek -> WidgetState.ExamWeek(phase.nextExam)
        is SemesterPhase.Vacation -> WidgetState.Vacation(
            nextSemesterName = phase.nextSemester?.displayName(),
            nextStartDate = phase.nextSemester?.startDate,
            daysUntilStart = phase.daysUntilStart,
            nextExam = phase.nextExam,
        )
    }
}

private fun teachingState(
    sem: WidgetSemesterItem,
    weekNum: Int,
    today: LocalDate,
    courses: List<ScheduleCourse>,
    exams: List<WidgetExamItem>,
): WidgetState {
    val start = LocalDate.parse(sem.startDate)
    val teachingEnd = start.plusWeeks(sem.weeks.toLong())
    val hasCourseData = courses.isNotEmpty()
    val colorMap = if (hasCourseData) buildCourseColorMap(courses) else emptyMap()
    val examsByDate: Map<LocalDate, List<WidgetCourseEntry>> = exams
        .mapNotNull { exam ->
            LocalDate.parse(exam.examDate)
                .takeIf { !it.isBefore(start) && it.isBefore(teachingEnd) }
                ?.let { it to exam.toCourseEntry() }
        }
        .groupBy({ it.first }, { it.second })

    // 某天的全部条目（课程 + 考试）；教学周之外为空
    fun entriesOn(date: LocalDate): List<WidgetCourseEntry> {
        if (date.isBefore(start) || !date.isBefore(teachingEnd)) return emptyList()
        val week = (ChronoUnit.DAYS.between(start, date) / 7 + 1).toInt()
        val classes = if (hasCourseData) filterCoursesForDay(courses, week, date.dayOfWeek.value, colorMap) else emptyList()
        return (classes + examsByDate[date].orEmpty()).sortedBy { it.startMinute }
    }

    val nowMin = currentMinuteOfDay()
    val todayEntries = entriesOn(today)
    val hasRemainingToday = todayEntries.any { it.endMinute > nowMin }
    val next: Pair<LocalDate, WidgetCourseEntry>? = generateSequence(today.plusDays(1)) { it.plusDays(1) }
        .takeWhile { it.isBefore(teachingEnd) }
        .firstNotNullOfOrNull { date -> entriesOn(date).firstOrNull()?.let { date to it } }

    val monday = today.with(DayOfWeek.MONDAY)
    val weekCourses = (1..7).associateWith { d -> entriesOn(monday.plusDays((d - 1).toLong())) }
    val weekDays = (0..6).map { offset ->
        val date = monday.plusDays(offset.toLong())
        WeekDayInfo(
            dayOfWeek = WEEKDAY_SHORT[offset],
            dayOfMonth = date.dayOfMonth,
            isToday = date == today,
            isPast = date.isBefore(today),
            courseCount = weekCourses[offset + 1]?.size ?: 0,
        )
    }

    val display = sem.displayName()
    val dow = today.dayOfWeek.value
    val remaining = sem.weeks - weekNum
    val isEnding = remaining <= 2
    val dateText = "${today.monthValue}月${today.dayOfMonth}日"

    if (hasRemainingToday || (todayEntries.isEmpty() && !hasCourseData)) {
        return WidgetState.InSession(
            semesterName = display,
            currentWeek = weekNum,
            totalWeeks = sem.weeks,
            dayOfWeek = dow,
            dayOfWeekText = WEEKDAY_NAMES[dow - 1],
            dateText = dateText,
            weekDays = weekDays,
            isEnding = isEnding,
            todayCourses = todayEntries,
            weekCourses = weekCourses,
            hasCourseData = hasCourseData,
        )
    }

    return WidgetState.NoCourseToday(
        semesterName = display,
        currentWeek = weekNum,
        totalWeeks = sem.weeks,
        dayOfWeek = dow,
        dayOfWeekText = WEEKDAY_NAMES[dow - 1],
        dateText = dateText,
        weekDays = weekDays,
        isEnding = isEnding,
        weekCourses = weekCourses,
        nextCourse = next?.second,
        nextCourseDay = next?.let { dayLabelFor(it.first, today) },
        todayFinished = todayEntries.isNotEmpty(),
    )
}

/** 下一项的日期标签：本周"周X"，下周"下周X"，更远显示日期 */
private fun dayLabelFor(date: LocalDate, today: LocalDate): String {
    val name = WEEKDAY_NAMES[date.dayOfWeek.value - 1]
    return when (ChronoUnit.WEEKS.between(today.with(DayOfWeek.MONDAY), date.with(DayOfWeek.MONDAY))) {
        0L -> name
        1L -> "下$name"
        else -> "${date.monthValue}/${date.dayOfMonth} $name"
    }
}
