package tech.loveace.testhook;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertNull;
import static org.junit.Assert.assertTrue;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import org.junit.Test;
import org.jsoup.Jsoup;
import org.jsoup.nodes.Document;

import java.time.LocalDate;
import java.time.LocalDateTime;

public class MockPayloadsTest {
    private static final LocalDateTime NOW = LocalDateTime.of(2026, 7, 17, 10, 30);
    private static final String BASE = "http://" + MockPayloads.JWC_HOST + ":8118";

    @Test
    public void disabledConfigurationPassesEveryRequestThrough() {
        HookSettings.Snapshot settings = settings(false, MockScenario.TODAY_ACTIVE);

        MockResponseSpec response = MockPayloads.forHttpRequest(
                "GET",
                BASE + "/student/examinationManagement/examPlan/detail",
                settings,
                NOW
        );

        assertNull(response);
        assertNull(MockPayloads.forSemesterRequest(
                MockPayloads.SEMESTER_URL,
                settings,
                NOW.toLocalDate()
        ));
    }

    @Test
    public void eachEndpointCanBePassedThroughIndependently() {
        HookSettings.Snapshot defaults = settings(true, MockScenario.TODAY_ACTIVE);
        HookSettings.Snapshot schoolDisabled = copy(defaults, false);

        assertNull(MockPayloads.forHttpRequest(
                "GET",
                BASE + "/student/examinationManagement/examPlan/detail",
                schoolDisabled,
                NOW
        ));
        assertTrue(MockPayloads.forHttpRequest(
                "POST",
                BASE + "/student/examinationManagement/othersExamPlan/queryScores?sf_request_type=ajax",
                schoolDisabled,
                NOW
        ).body.contains("大学英语"));
    }

    @Test
    public void todayScenarioEmitsCurrentExamAndEscapedSeatHtml() {
        HookSettings.Snapshot settings = new HookSettings.Snapshot(
                true,
                MockScenario.TODAY_ACTIVE,
                true,
                true,
                true,
                true,
                true,
                250,
                0,
                -30,
                120,
                -1,
                "高数 \"A\"",
                "博学楼 <101>",
                "18 & 19"
        );

        MockResponseSpec detail = MockPayloads.forHttpRequest(
                "GET",
                BASE + "/student/examinationManagement/examPlan/detail?start=2026-07-17",
                settings,
                NOW
        );
        MockResponseSpec index = MockPayloads.forHttpRequest(
                "GET",
                BASE + "/student/examinationManagement/examPlan/index",
                settings,
                NOW
        );

        assertEquals(MockPart.SCHOOL_EXAMS, detail.part);
        assertEquals(250, detail.latencyMs);
        assertTrue(detail.body.contains("2026-07-17"));
        assertTrue(detail.body.contains("10:00-12:00"));
        assertTrue(detail.body.contains("高数 \\\"A\\\""));
        assertTrue(index.body.contains("18 &amp; 19"));
        assertFalse(index.body.contains("博学楼"));
    }

    @Test
    public void semesterScenarioEndsCurrentTermYesterday() {
        HookSettings.Snapshot settings = settings(true, MockScenario.TODAY_ACTIVE);

        MockResponseSpec semester = MockPayloads.forSemesterRequest(
                MockPayloads.SEMESTER_URL,
                settings,
                LocalDate.of(2026, 7, 17)
        );

        assertEquals(MockPart.SEMESTER, semester.part);
        assertTrue(semester.body.contains("\"start_date\":\"2026-03-13\""));
        assertTrue(semester.body.contains("\"start_date\":\"2026-09-15\""));
    }

    @Test
    public void customScenarioUsesRelativeDateAndTime() {
        HookSettings.Snapshot settings = new HookSettings.Snapshot(
                true,
                MockScenario.CUSTOM,
                true,
                true,
                true,
                true,
                true,
                0,
                3,
                90,
                45,
                -1,
                "编译原理",
                "东区 303",
                "7"
        );

        MockResponseSpec response = MockPayloads.forHttpRequest(
                "GET",
                BASE + "/student/examinationManagement/examPlan/detail",
                settings,
                NOW
        );

        assertTrue(response.body.contains("2026-07-20"));
        assertTrue(response.body.contains("12:00-12:45"));
        assertTrue(response.body.contains("编译原理"));
    }

    @Test
    public void failureScenariosKeepEndpointSpecificShapes() {
        HookSettings.Snapshot malformed = settings(true, MockScenario.MALFORMED);
        HookSettings.Snapshot serverError = settings(true, MockScenario.SERVER_ERROR);

        MockResponseSpec malformedHtml = MockPayloads.forHttpRequest(
                "GET",
                BASE + "/student/examinationManagement/examPlan/index",
                malformed,
                NOW
        );
        MockResponseSpec error = MockPayloads.forHttpRequest(
                "POST",
                BASE + "/main/academicInfo?sf_request_type=ajax",
                serverError,
                NOW
        );

        assertTrue(malformedHtml.contentType.startsWith("text/html"));
        assertTrue(malformedHtml.body.contains("<broken>"));
        assertEquals(503, error.statusCode);
    }

    @Test
    public void unrelatedHostsAndPathsPassThrough() {
        HookSettings.Snapshot settings = settings(true, MockScenario.TODAY_ACTIVE);

        assertNull(MockPayloads.forHttpRequest("GET", "https://example.com/main/academicInfo", settings, NOW));
        assertNull(MockPayloads.forHttpRequest("GET", BASE + "/student/course/list", settings, NOW));
        assertNull(MockPayloads.forSemesterRequest("https://example.com/semesters.json", settings, NOW.toLocalDate()));
    }

    @Test
    public void scoreAndScheduleFixturesMatchTheAppContracts() {
        HookSettings.Snapshot settings = allDomainSettings(MockScenario.TODAY_ACTIVE);

        MockResponseSpec scoreIndex = response(
                "GET",
                BASE + "/student/integratedQuery/scoreQuery/allTermScores/index",
                settings
        );
        MockResponseSpec scores = response(
                "POST",
                BASE + "/student/integratedQuery/scoreQuery/MOCKSCORE/allTermScores/data",
                settings
        );
        Document scheduleIndex = Jsoup.parse(response(
                "GET",
                BASE + "/student/courseSelect/calendarSemesterCurriculum/index",
                settings
        ).body);
        JsonObject schedule = JsonParser.parseString(response(
                "POST",
                BASE + "/student/courseSelect/thisSemesterCurriculum/MOCKSCHEDULE/"
                        + "ajaxStudentSchedule/past/callback",
                settings
        ).body).getAsJsonObject();

        assertTrue(scoreIndex.body.contains("/MOCKSCORE/allTermScores/data"));
        JsonObject scoreList = JsonParser.parseString(scores.body)
                .getAsJsonObject().getAsJsonObject("list");
        assertEquals(3, scoreList.getAsJsonArray("records").size());
        assertEquals(3, scoreList.getAsJsonObject("pageContext").get("totalCount").getAsInt());
        assertEquals("2025-2026-2-1", scheduleIndex.selectFirst("select#planCode option").attr("value"));
        assertTrue(scheduleIndex.html().contains("/MOCKSCHEDULE/ajaxStudentSchedule"));
        assertEquals("", schedule.get("errorMessage").getAsString());
        assertEquals(1, schedule.getAsJsonArray("dateList").size());
    }

    @Test
    public void campusCardAndPlanFixturesMatchTheAppContracts() {
        HookSettings.Snapshot settings = allDomainSettings(MockScenario.TODAY_ACTIVE);
        String cardBase = "http://" + MockPayloads.CAMPUS_CARD_HOST + ":8118";

        String balance = response("GET", cardBase + "/queryUserBalances.action", settings).body;
        String transactions = response("POST", cardBase + "/queryUserCostList.action", settings).body;
        JsonObject summary = JsonParser.parseString(response(
                "GET",
                BASE + "/main/showPyfaInfo",
                settings
        ).body).getAsJsonObject();
        Document plan = Jsoup.parse(response(
                "GET",
                BASE + "/student/integratedQuery/planCompletion/index",
                settings
        ).body);

        assertTrue(balance.matches("(?s).*余额[：:]?\\s*</label>\\s*<label>\\s*[\\d.]+\\s*元.*"));
        assertEquals(2, Jsoup.parse(transactions).select("tr").size());
        assertTrue(summary.getAsJsonArray("data").get(0).getAsJsonArray().get(0)
                .getAsString().contains("培养方案"));
        assertTrue(plan.selectFirst("h4.widget-title").text().contains("培养方案"));
        String script = plan.selectFirst("script").data();
        JsonArray nodes = JsonParser.parseString(
                script.substring(script.indexOf('['), script.lastIndexOf(']') + 1)
        ).getAsJsonArray();
        assertEquals(4, nodes.size());
        assertTrue(script.contains("fa-frown-o fa-1x red"));
    }

    @Test
    public void readOnlyDomainSwitchesAndMethodsStayIndependent() {
        HookSettings.Snapshot settings = new HookSettings.Snapshot(
                true,
                MockScenario.TODAY_ACTIVE,
                false,
                false,
                false,
                false,
                false,
                0,
                0,
                -30,
                120,
                -1,
                "高等数学",
                "博学楼 101",
                "18",
                true,
                false,
                false,
                false
        );

        assertTrue(response(
                "POST",
                BASE + "/student/integratedQuery/scoreQuery/MOCKSCORE/allTermScores/data",
                settings
        ).body.contains("records"));
        assertNull(MockPayloads.forHttpRequest(
                "GET",
                BASE + "/student/integratedQuery/scoreQuery/MOCKSCORE/allTermScores/data",
                settings,
                NOW
        ));
        assertNull(MockPayloads.forHttpRequest(
                "GET",
                BASE + "/student/courseSelect/calendarSemesterCurriculum/index",
                settings,
                NOW
        ));
    }

    @Test
    public void emptyReadOnlyDomainsReturnValidContainers() {
        HookSettings.Snapshot settings = allDomainSettings(MockScenario.EMPTY);
        String cardBase = "http://" + MockPayloads.CAMPUS_CARD_HOST + ":8118";

        JsonObject scores = JsonParser.parseString(response(
                "POST",
                BASE + "/student/integratedQuery/scoreQuery/MOCKSCORE/allTermScores/data",
                settings
        ).body).getAsJsonObject();
        JsonObject schedule = JsonParser.parseString(response(
                "POST",
                BASE + "/student/courseSelect/thisSemesterCurriculum/MOCKSCHEDULE/"
                        + "ajaxStudentSchedule/past/callback",
                settings
        ).body).getAsJsonObject();

        assertEquals(0, scores.getAsJsonObject("list").getAsJsonArray("records").size());
        assertEquals(0, schedule.getAsJsonArray("dateList").size());
        assertEquals(0, Jsoup.parse(response(
                "POST",
                cardBase + "/queryUserCostList.action",
                settings
        ).body).select("tr").size());
    }

    private static MockResponseSpec response(
            String method,
            String url,
            HookSettings.Snapshot settings
    ) {
        MockResponseSpec response = MockPayloads.forHttpRequest(method, url, settings, NOW);
        if (response == null) throw new AssertionError("Expected fixture for " + method + " " + url);
        return response;
    }

    private static HookSettings.Snapshot allDomainSettings(MockScenario scenario) {
        return new HookSettings.Snapshot(
                true,
                scenario,
                true,
                true,
                true,
                true,
                true,
                0,
                0,
                -30,
                120,
                -1,
                "高等数学",
                "博学楼 101",
                "18",
                true,
                true,
                true,
                true
        );
    }

    private static HookSettings.Snapshot settings(boolean enabled, MockScenario scenario) {
        return new HookSettings.Snapshot(
                enabled,
                scenario,
                true,
                true,
                true,
                true,
                true,
                0,
                0,
                -30,
                120,
                -1,
                "高等数学",
                "博学楼 101",
                "18"
        );
    }

    private static HookSettings.Snapshot copy(
            HookSettings.Snapshot source,
            boolean mockSchoolExams
    ) {
        return new HookSettings.Snapshot(
                source.enabled,
                source.scenario,
                source.mockSemester,
                source.mockAcademic,
                source.mockExamIndex,
                mockSchoolExams,
                source.mockOtherExams,
                source.latencyMs,
                source.customDayOffset,
                source.customStartOffsetMinutes,
                source.customDurationMinutes,
                source.semesterEndOffsetDays,
                source.courseName,
                source.room,
                source.seat
        );
    }
}
