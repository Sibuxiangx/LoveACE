package tech.loveace.appv3.util

import tech.loveace.appv3.data.model.UnifiedExamInfo
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.temporal.TemporalAdjusters

internal enum class HomeExamPeriod(val title: String) {
    Today("今日考试"),
    ThisWeek("本周考试"),
    Upcoming("最近考试"),
}

internal data class HomeExamOverview(
    val period: HomeExamPeriod,
    val exams: List<UnifiedExamInfo>,
)

private data class ParsedExam(
    val exam: UnifiedExamInfo,
    val date: LocalDate,
    val startsAt: LocalDateTime,
    val endsAt: LocalDateTime,
)

private val separatedDatePattern = Regex("""(\d{4})[-/.](\d{1,2})[-/.](\d{1,2})""")
private val compactDatePattern = Regex("""(?<!\d)(\d{4})(\d{2})(\d{2})(?!\d)""")
private val timePattern = Regex("""(?<!\d)([01]?\d|2[0-3]):([0-5]\d)(?::[0-5]\d)?(?!\d)""")

internal fun buildHomeExamOverview(
    exams: List<UnifiedExamInfo>,
    now: LocalDateTime = LocalDateTime.now(),
): HomeExamOverview? {
    val pending = exams.mapNotNull(::parseExam)
        .filter { it.endsAt.isAfter(now) }
        .sortedWith(compareBy({ it.startsAt }, { it.exam.courseName }))
    if (pending.isEmpty()) return null

    val today = now.toLocalDate()
    val todayExams = pending.filter { it.date == today }
    if (todayExams.isNotEmpty()) {
        return HomeExamOverview(HomeExamPeriod.Today, todayExams.map { it.exam })
    }

    val endOfWeek = today.with(TemporalAdjusters.nextOrSame(DayOfWeek.SUNDAY))
    val thisWeekExams = pending.filter { !it.date.isAfter(endOfWeek) }
    if (thisWeekExams.isNotEmpty()) {
        return HomeExamOverview(HomeExamPeriod.ThisWeek, thisWeekExams.map { it.exam })
    }

    val nearestDate = pending.first().date
    return HomeExamOverview(
        HomeExamPeriod.Upcoming,
        pending.filter { it.date == nearestDate }.map { it.exam },
    )
}

private fun parseExam(exam: UnifiedExamInfo): ParsedExam? {
    val date = parseExamDate(exam.examDate) ?: return null
    val times = timePattern.findAll(exam.examTime).map { match ->
        LocalTime.of(match.groupValues[1].toInt(), match.groupValues[2].toInt())
    }.toList()
    val startsAt = date.atTime(times.firstOrNull() ?: LocalTime.MIN)
    val endsAt = if (times.size >= 2) {
        date.atTime(times.last())
    } else {
        date.atTime(LocalTime.MAX)
    }
    return ParsedExam(exam, date, startsAt, endsAt)
}

private fun parseExamDate(value: String): LocalDate? {
    val match = separatedDatePattern.find(value) ?: compactDatePattern.find(value) ?: return null
    return runCatching {
        LocalDate.of(
            match.groupValues[1].toInt(),
            match.groupValues[2].toInt(),
            match.groupValues[3].toInt(),
        )
    }.getOrNull()
}
