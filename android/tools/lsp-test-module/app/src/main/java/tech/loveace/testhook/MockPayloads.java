package tech.loveace.testhook;

import java.net.URI;
import java.time.DayOfWeek;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.LocalTime;
import java.time.format.DateTimeFormatter;
import java.util.Locale;

final class MockPayloads {
    static final String JWC_HOST = "jwcxk2-aufe-edu-cn.vpn2.aufe.edu.cn";
    static final String CAMPUS_CARD_HOST = "ykt-aufe-edu-cn-s.vpn2.aufe.edu.cn";
    static final String SEMESTER_URL =
            "https://loveace-semsync.oss-cn-beijing.aliyuncs.com/loveace/semesters.json";

    private static final DateTimeFormatter TIME_FORMAT = DateTimeFormatter.ofPattern("HH:mm", Locale.ROOT);

    private MockPayloads() {}

    static MockResponseSpec forHttpRequest(
            String method,
            String url,
            HookSettings.Snapshot settings,
            LocalDateTime now
    ) {
        if (!settings.enabled) return null;

        URI uri;
        try {
            uri = URI.create(url);
        } catch (IllegalArgumentException ignored) {
            return null;
        }
        String path = uri.getPath();
        MockPart part = partForRequest(method, uri.getHost(), path);
        if (part == null || !settings.isPartEnabled(part)) return null;

        if (settings.scenario == MockScenario.SERVER_ERROR) {
            return new MockResponseSpec(
                    part,
                    503,
                    contentType(part),
                    isHtmlPart(part)
                            ? "<!doctype html><title>Mock service unavailable</title>"
                            : "{\"success\":false,\"message\":\"mock service unavailable\"}",
                    settings.latencyMs
            );
        }

        if (settings.scenario == MockScenario.MALFORMED) {
            return new MockResponseSpec(
                    part,
                    200,
                    contentType(part),
                    malformedBody(part),
                    settings.latencyMs
            );
        }

        String body = switch (part) {
            case ACADEMIC -> academicInfoJson(settings);
            case EXAM_INDEX -> examIndexHtml(settings);
            case SCHOOL_EXAMS -> schoolExamsJson(settings, now);
            case OTHER_EXAMS -> otherExamsJson(settings, now);
            case SCORES_INDEX -> scoresIndexHtml();
            case SCORES_DATA -> scoresJson(settings);
            case SCHEDULE_INDEX -> scheduleIndexHtml();
            case STUDENT_SCHEDULE -> studentScheduleJson(settings, now);
            case COURSE_CATALOG_INDEX -> courseCatalogIndexHtml();
            case COURSE_CATALOG_DATA -> courseCatalogJson(settings);
            case CAMPUS_CARD_SESSION -> campusCardSessionHtml();
            case CAMPUS_CARD_BALANCE -> campusCardBalanceHtml(settings);
            case CAMPUS_CARD_TRANSACTIONS -> campusCardTransactionsHtml(settings, now);
            case TRAINING_PLAN_SUMMARY -> trainingPlanSummaryJson(settings);
            case TRAINING_PLAN_DETAIL -> trainingPlanHtml(settings);
            case SEMESTER -> throw new IllegalStateException("Semester data does not use HttpClient");
        };
        return new MockResponseSpec(part, 200, contentType(part), body, settings.latencyMs);
    }

    static MockResponseSpec forSemesterRequest(
            String url,
            HookSettings.Snapshot settings,
            LocalDate today
    ) {
        if (!SEMESTER_URL.equals(url) || !settings.isPartEnabled(MockPart.SEMESTER)) return null;
        String body;
        if (settings.scenario == MockScenario.SERVER_ERROR) {
            body = "{\"error\":\"mock service unavailable\"}";
        } else if (settings.scenario == MockScenario.MALFORMED) {
            body = "{\"semesters\":[";
        } else {
            body = semesterJson(settings, today);
        }
        return new MockResponseSpec(
                MockPart.SEMESTER,
                200,
                "application/json; charset=utf-8",
                body,
                settings.latencyMs
        );
    }

    private static MockPart partForRequest(String method, String host, String path) {
        if (host == null || path == null) return null;
        if (JWC_HOST.equalsIgnoreCase(host)) return partForJwcRequest(method, path);
        if (CAMPUS_CARD_HOST.equalsIgnoreCase(host)) return partForCampusCardRequest(method, path);
        return null;
    }

    private static MockPart partForJwcRequest(String method, String path) {
        if (isMethod(method, "POST") && "/main/academicInfo".equals(path)) {
            return MockPart.ACADEMIC;
        }
        if (isMethod(method, "GET")
                && "/student/examinationManagement/examPlan/index".equals(path)) {
            return MockPart.EXAM_INDEX;
        }
        if (isMethod(method, "GET")
                && "/student/examinationManagement/examPlan/detail".equals(path)) {
            return MockPart.SCHOOL_EXAMS;
        }
        if (isMethod(method, "POST")
                && "/student/examinationManagement/othersExamPlan/queryScores".equals(path)) {
            return MockPart.OTHER_EXAMS;
        }
        if (isMethod(method, "GET")
                && "/student/integratedQuery/scoreQuery/allTermScores/index".equals(path)) {
            return MockPart.SCORES_INDEX;
        }
        if (isMethod(method, "POST")
                && path.matches("/student/integratedQuery/scoreQuery/[A-Za-z0-9]+/allTermScores/data")) {
            return MockPart.SCORES_DATA;
        }
        if (isMethod(method, "GET")
                && "/student/courseSelect/calendarSemesterCurriculum/index".equals(path)) {
            return MockPart.SCHEDULE_INDEX;
        }
        if (isMethod(method, "POST")
                && path.matches("/student/courseSelect/thisSemesterCurriculum/[A-Za-z0-9]+/ajaxStudentSchedule/past/callback")) {
            return MockPart.STUDENT_SCHEDULE;
        }
        if (isMethod(method, "GET")
                && "/student/integratedQuery/course/courseSchdule/index".equals(path)) {
            return MockPart.COURSE_CATALOG_INDEX;
        }
        if (isMethod(method, "POST")
                && "/student/integratedQuery/course/courseSchdule/courseInfo".equals(path)) {
            return MockPart.COURSE_CATALOG_DATA;
        }
        if (isMethod(method, "GET") && "/main/showPyfaInfo".equals(path)) {
            return MockPart.TRAINING_PLAN_SUMMARY;
        }
        if (isMethod(method, "GET")
                && ("/student/integratedQuery/planCompletion/index".equals(path)
                || path.matches("/student/integratedQuery/planCompletion/getPyfaIndex/[A-Za-z0-9]+"))) {
            return MockPart.TRAINING_PLAN_DETAIL;
        }
        return null;
    }

    private static MockPart partForCampusCardRequest(String method, String path) {
        if (isMethod(method, "GET") && "/casLogin.jsp".equals(path)) {
            return MockPart.CAMPUS_CARD_SESSION;
        }
        if (isMethod(method, "GET") && "/queryUserBalances.action".equals(path)) {
            return MockPart.CAMPUS_CARD_BALANCE;
        }
        if (isMethod(method, "POST") && "/queryUserCostList.action".equals(path)) {
            return MockPart.CAMPUS_CARD_TRANSACTIONS;
        }
        return null;
    }

    private static boolean isMethod(String actual, String expected) {
        return expected.equalsIgnoreCase(actual);
    }

    private static String academicInfoJson(HookSettings.Snapshot settings) {
        int completed = settings.scenario == MockScenario.EMPTY ? 0 : 32;
        int failed = settings.scenario == MockScenario.EMPTY ? 0 : 1;
        int pending = settings.scenario == MockScenario.EMPTY ? 0 : 5;
        return "[{"
                + "\"courseNum\":" + completed + ","
                + "\"coursePas\":" + failed + ","
                + "\"gpa\":3.82,"
                + "\"sspjf_jd\":88.6,"
                + "\"sspjf_pm\":8,"
                + "\"sspjf_rs\":120,"
                + "\"courseNum_bxqyxd\":" + pending + ","
                + "\"zxjxjhh\":\"2025-2026-2-1\""
                + "}]";
    }

    private static String examIndexHtml(HookSettings.Snapshot settings) {
        String course = htmlEscape(settings.courseName);
        String seat = htmlEscape(settings.seat);
        return "<!doctype html><html><body>"
                + "<div class=\"widget-box\">"
                + "<h5 class=\"widget-title\">（1）" + course + "</h5>"
                + "<div class=\"widget-main\">座位号：" + seat + " 准考证号：MOCK-2026</div>"
                + "</div></body></html>";
    }

    private static String schoolExamsJson(HookSettings.Snapshot settings, LocalDateTime now) {
        ExamMoment moment = momentFor(settings, now);
        if (settings.scenario == MockScenario.EMPTY) return "[]";
        String title = jsonEscape(settings.courseName + "\n" + moment.timeRange() + "\n" + settings.room);
        return "[{\"title\":\"" + title + "\",\"start\":\"" + moment.date + "\"}]";
    }

    private static String otherExamsJson(HookSettings.Snapshot settings, LocalDateTime now) {
        if (settings.scenario == MockScenario.EMPTY
                || settings.scenario == MockScenario.JUST_ENDED
                || settings.scenario == MockScenario.ALL_FINISHED) {
            return "{\"records\":[]}";
        }
        ExamMoment primary = momentFor(settings, now);
        LocalDate secondDate = primary.date.plusDays(1);
        return "{\"records\":[{"
                + "\"KCM\":\"大学英语\","
                + "\"KSRQ\":\"" + secondDate + "\","
                + "\"KSSJ\":\"14:00-16:00\","
                + "\"KSDD\":\"笃行楼 202\","
                + "\"BZ\":\"座位号: 27\""
                + "}]}";
    }

    private static String scoresIndexHtml() {
        return "<!doctype html><html><body><script>"
                + "var scoreUrl='/student/integratedQuery/scoreQuery/MOCKSCORE/allTermScores/data';"
                + "</script></body></html>";
    }

    private static String scoresJson(HookSettings.Snapshot settings) {
        if (settings.scenario == MockScenario.EMPTY) {
            return "{\"list\":{\"pageContext\":{\"totalCount\":0},\"records\":[]}}";
        }
        String course = jsonEscape(settings.courseName);
        return "{\"list\":{\"pageContext\":{\"totalCount\":3},\"records\":["
                + "[1,\"2025-2026-2-1\",\"MATH101\",\"01\",\"" + course
                + "\",\"Advanced Mathematics\",\"4\",64,\"必修\",\"考试\",\"92\",null,null],"
                + "[2,\"2025-2026-2-1\",\"CS204\",\"01\",\"数据结构\","
                + "\"Data Structures\",\"3\",48,\"必修\",\"考试\",\"86\",null,null],"
                + "[3,\"2025-2026-2-1\",\"STAT201\",\"01\",\"概率论与数理统计\","
                + "\"Probability and Statistics\",\"3\",48,\"必修\",\"考试\",\"58\",null,null]"
                + "]}}";
    }

    private static String scheduleIndexHtml() {
        return "<!doctype html><html><body>"
                + "<select id=\"planCode\">"
                + "<option value=\"2025-2026-2-1\" selected>2025-2026学年下学期（当前）</option>"
                + "<option value=\"2025-2026-1-1\">2025-2026学年上学期</option>"
                + "</select><script>var scheduleUrl='"
                + "/student/courseSelect/thisSemesterCurriculum/MOCKSCHEDULE/"
                + "ajaxStudentSchedule/past/callback';</script></body></html>";
    }

    private static String studentScheduleJson(
            HookSettings.Snapshot settings,
            LocalDateTime now
    ) {
        if (settings.scenario == MockScenario.EMPTY) {
            return "{\"allUnits\":0,\"errorMessage\":\"\",\"dateList\":[]}";
        }
        String course = jsonEscape(settings.courseName);
        String room = jsonEscape(settings.room);
        int classDay = now.getDayOfWeek().getValue();
        return "{\"allUnits\":4.0,\"errorMessage\":\"\",\"dateList\":[{"
                + "\"programPlanCode\":\"2025-2026-2-1\","
                + "\"programPlanName\":\"Mock 春季学期\",\"totalUnits\":4.0,"
                + "\"selectCourseList\":[{"
                + "\"id\":{\"executiveEducationPlanNumber\":\"MOCK-PLAN\","
                + "\"coureNumber\":\"MATH101\",\"coureSequenceNumber\":\"01\","
                + "\"studentNumber\":\"MOCK-STUDENT\"},"
                + "\"courseName\":\"" + course + "\",\"unit\":4.0,"
                + "\"programPlanName\":\"Mock 春季学期\",\"attendClassTeacher\":\"测试教师\","
                + "\"studyModeName\":\"正常修读\",\"coursePropertiesName\":\"必修\","
                + "\"examTypeName\":\"考试\",\"courseCategoryName\":\"专业课\","
                + "\"selectCourseStatusName\":\"已选\",\"timeAndPlaceList\":[{"
                + "\"classWeek\":\"1-18\",\"classDay\":" + classDay + ","
                + "\"classSessions\":1,\"continuingSession\":2,\"campusName\":\"东校区\","
                + "\"teachingBuildingName\":\"\",\"classroomName\":\"" + room + "\","
                + "\"weekDescription\":\"1-18周\",\"coursePropertiesName\":\"必修\","
                + "\"coureName\":\"" + course + "\"}]}]}]}";
    }

    private static String courseCatalogIndexHtml() {
        return "<!doctype html><html><body><select id=\"zxjxjhh\">"
                + "<option value=\"2025-2026-2-1\" selected>2025-2026学年下学期</option>"
                + "<option value=\"2025-2026-1-1\">2025-2026学年上学期</option>"
                + "</select></body></html>";
    }

    private static String courseCatalogJson(HookSettings.Snapshot settings) {
        if (settings.scenario == MockScenario.EMPTY) {
            return "{\"list\":{\"pageContext\":{\"totalCount\":0},\"records\":[]}}";
        }
        return "{\"list\":{\"pageContext\":{\"totalCount\":1},\"records\":[{"
                + "\"kch\":\"MATH101\",\"kxh\":\"01\",\"kcm\":\""
                + jsonEscape(settings.courseName) + "\",\"xf\":4,\"xs\":64,"
                + "\"kkxsjc\":\"数学学院\",\"kslxmc\":\"考试\",\"skjs\":\"测试教师\","
                + "\"bkskrl\":60,\"bkskyl\":12,\"xkmssm\":\"直选\",\"kkxqm\":\"东校区\","
                + "\"skzc\":\"1-18\",\"skxq\":1,\"skjc\":1,\"cxjc\":2,"
                + "\"zcsm\":\"1-18周\",\"kclbmc\":\"专业必修课\",\"xqm\":\"东校区\","
                + "\"jxlm\":\"博学楼\",\"jasm\":\"101\",\"mxbj\":\"测试班\",\"xss\":48"
                + "}]}}";
    }

    private static String campusCardSessionHtml() {
        return "<!doctype html><html><body>mock campus-card session</body></html>";
    }

    private static String campusCardBalanceHtml(HookSettings.Snapshot settings) {
        String balance = settings.scenario == MockScenario.EMPTY ? "0.00" : "42.35";
        return "<!doctype html><html><body><label>余额：</label><label>"
                + balance + " 元</label></body></html>";
    }

    private static String campusCardTransactionsHtml(
            HookSettings.Snapshot settings,
            LocalDateTime now
    ) {
        if (settings.scenario == MockScenario.EMPTY) {
            return "<!doctype html><html><body><table></table></body></html>";
        }
        LocalDate today = now.toLocalDate();
        return "<!doctype html><html><body><table>"
                + transactionRow(today + " 08:05", today + " 08:03", "8.50", "", "食堂消费", "42.35", "东校区食堂", "POS-101")
                + transactionRow(today.minusDays(1) + " 14:20", today.minusDays(1) + " 14:18", "", "50.00", "账户充值", "50.85", "线上充值", "APP")
                + "</table></body></html>";
    }

    private static String transactionRow(
            String accountingTime,
            String transactionTime,
            String expense,
            String income,
            String type,
            String balance,
            String area,
            String terminal
    ) {
        return "<tr><td>" + accountingTime + "</td><td>" + transactionTime + "</td><td>"
                + expense + "</td><td>" + income + "</td><td>" + type + "</td><td>"
                + balance + "</td><td>" + area + "</td><td>" + terminal + "</td></tr>";
    }

    private static String trainingPlanSummaryJson(HookSettings.Snapshot settings) {
        String major = settings.scenario == MockScenario.EMPTY ? "测试专业" : "计算机科学与技术";
        return "{\"data\":[[\"2022级" + major + "本科培养方案\"]]}";
    }

    private static String trainingPlanHtml(HookSettings.Snapshot settings) {
        String header = "2022级计算机科学与技术本科培养方案";
        String rootName;
        String courses;
        if (settings.scenario == MockScenario.EMPTY) {
            rootName = "专业必修课(最低修读学分:0.0,通过学分:0.0,已修课程门数:0,"
                    + "已及格课程门数:0,未及格课程门数:0,必修课缺修门数:0)";
            courses = "";
        } else {
            rootName = "专业必修课(最低修读学分:10.0,通过学分:7.0,已修课程门数:3,"
                    + "已及格课程门数:2,未及格课程门数:1,必修课缺修门数:0)";
            courses = ","
                    + planCourseNode("plan-course-1", "MATH101", settings.courseName, "4.0", "92", true)
                    + "," + planCourseNode("plan-course-2", "CS204", "数据结构", "3.0", "86", true)
                    + "," + planCourseNode("plan-course-3", "STAT201", "概率论与数理统计", "3.0", "58", false);
        }
        return "<!doctype html><html><body><h4 class=\"widget-title\">" + header + "</h4>"
                + "<div id=\"treeDemo\"></div><script>var setting={};$.fn.zTree.init($(\"#treeDemo\"),setting,["
                + "{\"id\":\"plan-root\",\"pId\":\"-1\",\"flagId\":\"required\","
                + "\"flagType\":\"001\",\"name\":\"" + jsonEscape(rootName) + "\"}"
                + courses + "]);</script></body></html>";
    }

    private static String planCourseNode(
            String id,
            String code,
            String name,
            String credits,
            String score,
            boolean passed
    ) {
        String icon = passed ? "fa-smile-o fa-1x green" : "fa-frown-o fa-1x red";
        String display = "[" + code + "] " + name + " [" + credits
                + "学分] (必修," + score + ",20260110) <i class='" + icon + "'></i>";
        return "{\"id\":\"" + id + "\",\"pId\":\"plan-root\",\"flagId\":\""
                + code + "\",\"flagType\":\"kch\",\"name\":\""
                + jsonEscape(display) + "\"}";
    }

    private static ExamMoment momentFor(HookSettings.Snapshot settings, LocalDateTime now) {
        return switch (settings.scenario) {
            case TODAY_ACTIVE -> activeToday(now);
            case THIS_WEEK -> futureThisWeek(now);
            case UPCOMING -> fixedFuture(now, 8);
            case JUST_ENDED -> justEnded(now);
            case ALL_FINISHED -> new ExamMoment(now.toLocalDate().minusDays(1), LocalTime.of(9, 0), LocalTime.of(11, 0));
            case EMPTY, MALFORMED, SERVER_ERROR -> activeToday(now);
            case CUSTOM -> customMoment(settings, now);
        };
    }

    private static ExamMoment activeToday(LocalDateTime now) {
        int minuteOfDay = now.getHour() * 60 + now.getMinute();
        int startMinute = Math.max(0, minuteOfDay - 30);
        int endMinute = Math.min(23 * 60 + 59, minuteOfDay + 90);
        return new ExamMoment(
                now.toLocalDate(),
                LocalTime.of(startMinute / 60, startMinute % 60),
                LocalTime.of(endMinute / 60, endMinute % 60)
        );
    }

    private static ExamMoment futureThisWeek(LocalDateTime now) {
        int daysUntilSunday = DayOfWeek.SUNDAY.getValue() - now.getDayOfWeek().getValue();
        int offset = Math.max(1, daysUntilSunday == 0 ? 1 : Math.min(2, daysUntilSunday));
        return new ExamMoment(now.toLocalDate().plusDays(offset), LocalTime.of(9, 0), LocalTime.of(11, 0));
    }

    private static ExamMoment fixedFuture(LocalDateTime now, int dayOffset) {
        return new ExamMoment(now.toLocalDate().plusDays(dayOffset), LocalTime.of(9, 0), LocalTime.of(11, 0));
    }

    private static ExamMoment justEnded(LocalDateTime now) {
        if (now.toLocalTime().isBefore(LocalTime.of(2, 0))) {
            return new ExamMoment(now.toLocalDate().minusDays(1), LocalTime.of(22, 0), LocalTime.of(23, 0));
        }
        LocalDateTime end = now.minusMinutes(30);
        LocalDateTime start = end.minusMinutes(90);
        return new ExamMoment(start.toLocalDate(), start.toLocalTime(), end.toLocalTime());
    }

    private static ExamMoment customMoment(HookSettings.Snapshot settings, LocalDateTime now) {
        LocalDateTime start = now
                .plusDays(settings.customDayOffset)
                .plusMinutes(settings.customStartOffsetMinutes);
        LocalDateTime end = start.plusMinutes(settings.customDurationMinutes);
        if (!end.toLocalDate().equals(start.toLocalDate())) {
            end = start.toLocalDate().atTime(23, 59);
        }
        return new ExamMoment(start.toLocalDate(), start.toLocalTime(), end.toLocalTime());
    }

    private static String semesterJson(HookSettings.Snapshot settings, LocalDate today) {
        LocalDate currentEnd = today.plusDays(settings.semesterEndOffsetDays);
        LocalDate currentStart = currentEnd.minusDays(125);
        LocalDate nextStart = today.plusDays(60);
        return "{"
                + "\"version\":1,"
                + "\"updated_at\":\"" + today + "T00:00:00+08:00\","
                + "\"semesters\":["
                + "{\"code\":\"2025-2026-2\",\"name\":\"Mock 春季学期\",\"start_date\":\""
                + currentStart + "\",\"weeks\":18},"
                + "{\"code\":\"2026-2027-1\",\"name\":\"Mock 秋季学期\",\"start_date\":\""
                + nextStart + "\",\"weeks\":18}"
                + "]}";
    }

    private static String contentType(MockPart part) {
        return isHtmlPart(part)
                ? "text/html; charset=utf-8"
                : "application/json; charset=utf-8";
    }

    private static boolean isHtmlPart(MockPart part) {
        return switch (part) {
            case EXAM_INDEX, SCORES_INDEX, SCHEDULE_INDEX, COURSE_CATALOG_INDEX,
                    CAMPUS_CARD_SESSION, CAMPUS_CARD_BALANCE, CAMPUS_CARD_TRANSACTIONS,
                    TRAINING_PLAN_DETAIL -> true;
            default -> false;
        };
    }

    private static String malformedBody(MockPart part) {
        return switch (part) {
            case ACADEMIC -> "[{\"zxjxjhh\":";
            case EXAM_INDEX -> "<html><div class=\"widget-box\"><broken>";
            case SCHOOL_EXAMS -> "[{\"title\":42,\"start\":null}]";
            case OTHER_EXAMS -> "{\"records\":[null,{\"unexpected\":true}]}";
            case SCORES_INDEX -> "<html><script>var scoreUrl='missing';</script></html>";
            case SCORES_DATA -> "{\"list\":{\"records\":[";
            case SCHEDULE_INDEX -> "<html><select id=\"wrong\"></select></html>";
            case STUDENT_SCHEDULE -> "{\"dateList\":[null]}";
            case COURSE_CATALOG_INDEX -> "<html><select name=\"wrong\"></select></html>";
            case COURSE_CATALOG_DATA -> "{\"list\":{\"records\":[null]}}";
            case CAMPUS_CARD_SESSION -> "<html><broken>";
            case CAMPUS_CARD_BALANCE -> "<html><label>余额未知</label></html>";
            case CAMPUS_CARD_TRANSACTIONS -> "<table><tr><td>broken</td></tr></table>";
            case TRAINING_PLAN_SUMMARY -> "{\"data\":";
            case TRAINING_PLAN_DETAIL -> "<html><script>zTree.init([broken]);</script></html>";
            case SEMESTER -> "{\"semesters\":[";
        };
    }

    private static String jsonEscape(String value) {
        return value
                .replace("\\", "\\\\")
                .replace("\"", "\\\"")
                .replace("\n", "\\n")
                .replace("\r", "\\r")
                .replace("\t", "\\t");
    }

    private static String htmlEscape(String value) {
        return value
                .replace("&", "&amp;")
                .replace("<", "&lt;")
                .replace(">", "&gt;")
                .replace("\"", "&quot;");
    }

    private static final class ExamMoment {
        final LocalDate date;
        final LocalTime start;
        final LocalTime end;

        ExamMoment(LocalDate date, LocalTime start, LocalTime end) {
            this.date = date;
            this.start = start;
            this.end = end;
        }

        String timeRange() {
            return TIME_FORMAT.format(start) + "-" + TIME_FORMAT.format(end);
        }
    }
}
