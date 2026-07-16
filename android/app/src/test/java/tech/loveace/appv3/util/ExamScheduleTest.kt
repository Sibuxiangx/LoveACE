package tech.loveace.appv3.util

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import tech.loveace.appv3.data.model.UnifiedExamInfo
import tech.loveace.appv3.ui.viewmodel.SemesterData
import tech.loveace.appv3.ui.viewmodel.SemesterItem
import tech.loveace.appv3.ui.viewmodel.SemesterStatus
import tech.loveace.appv3.ui.viewmodel.computeSemesterStatus
import java.time.LocalDate
import java.time.LocalDateTime

class ExamScheduleTest {
    private val now = LocalDateTime.of(2026, 6, 29, 10, 0)

    @Test
    fun `finished exams are excluded and today's active exams take priority`() {
        val overview = buildHomeExamOverview(
            listOf(
                exam("已结束", "2026-06-29", "08:00-09:00"),
                exam("进行中", "2026-06-29", "09:00-11:00"),
                exam("明天", "2026-06-30", "09:00-11:00"),
            ),
            now,
        )

        assertEquals(HomeExamPeriod.Today, overview?.period)
        assertEquals(listOf("进行中"), overview?.exams?.map { it.courseName })
    }

    @Test
    fun `this week's exams are shown when today has none`() {
        val overview = buildHomeExamOverview(
            listOf(
                exam("本周", "2026-07-03", "09:00-11:00"),
                exam("下周", "2026-07-06", "09:00-11:00"),
            ),
            now,
        )

        assertEquals(HomeExamPeriod.ThisWeek, overview?.period)
        assertEquals(listOf("本周"), overview?.exams?.map { it.courseName })
    }

    @Test
    fun `nearest future exam keeps final exam week active`() {
        val overview = buildHomeExamOverview(
            listOf(
                exam("最近一", "20260706", "09:00-11:00"),
                exam("最近二", "20260706", "14:00-16:00"),
                exam("更晚", "2026-07-08", "09:00-11:00"),
            ),
            now,
        )

        assertEquals(HomeExamPeriod.Upcoming, overview?.period)
        assertEquals(listOf("最近一", "最近二"), overview?.exams?.map { it.courseName })
    }

    @Test
    fun `invalid or fully finished schedules have no overview`() {
        val overview = buildHomeExamOverview(
            listOf(
                exam("无日期", "待定", ""),
                exam("昨天", "2026-06-28", ""),
            ),
            now,
        )

        assertNull(overview)
    }

    @Test
    fun `exam is no longer pending at its exact end time`() {
        val overview = buildHomeExamOverview(
            listOf(exam("刚结束", "2026-06-29", "09:00-10:00")),
            now,
        )

        assertNull(overview)
    }

    @Test
    fun `semester becomes final exam week only after week eighteen`() {
        val data = SemesterData(
            semesters = listOf(
                SemesterItem(
                    code = "2025-2026-2",
                    name = "春季学期",
                    startDate = "2026-02-23",
                    weeks = 18,
                ),
            ),
        )

        assertTrue(
            computeSemesterStatus(
                data,
                today = LocalDate.of(2026, 6, 29),
                hasPendingExams = true,
            ) is SemesterStatus.FinalExamWeek,
        )
        assertTrue(
            computeSemesterStatus(
                data,
                today = LocalDate.of(2026, 6, 29),
                hasPendingExams = false,
            ) is SemesterStatus.Vacation,
        )
        assertTrue(
            computeSemesterStatus(
                data,
                today = LocalDate.of(2026, 6, 28),
                hasPendingExams = true,
            ) is SemesterStatus.InSession,
        )
    }

    @Test
    fun `new semester takes precedence over pending exams from previous semester`() {
        val data = SemesterData(
            semesters = listOf(
                SemesterItem(
                    code = "2025-2026-2",
                    name = "春季学期",
                    startDate = "2026-02-23",
                    weeks = 18,
                ),
                SemesterItem(
                    code = "2026-2027-1",
                    name = "秋季学期",
                    startDate = "2026-08-31",
                    weeks = 18,
                ),
            ),
        )

        val status = computeSemesterStatus(
            data,
            today = LocalDate.of(2026, 8, 31),
            hasPendingExams = true,
        )

        assertTrue(status is SemesterStatus.InSession)
        assertEquals(1, (status as SemesterStatus.InSession).currentWeek)
    }

    private fun exam(name: String, date: String, time: String) = UnifiedExamInfo(
        courseName = name,
        examDate = date,
        examTime = time,
    )
}
