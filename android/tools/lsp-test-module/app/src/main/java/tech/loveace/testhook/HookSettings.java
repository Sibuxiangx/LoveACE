package tech.loveace.testhook;

import android.content.SharedPreferences;

final class HookSettings {
    static final String GROUP = "exam_mock";

    static final String KEY_ENABLED = "enabled";
    static final String KEY_SCENARIO = "scenario";
    static final String KEY_MOCK_SEMESTER = "mock_semester";
    static final String KEY_MOCK_ACADEMIC = "mock_academic";
    static final String KEY_MOCK_EXAM_INDEX = "mock_exam_index";
    static final String KEY_MOCK_SCHOOL_EXAMS = "mock_school_exams";
    static final String KEY_MOCK_OTHER_EXAMS = "mock_other_exams";
    static final String KEY_MOCK_SCORES = "mock_scores";
    static final String KEY_MOCK_SCHEDULE = "mock_schedule";
    static final String KEY_MOCK_CAMPUS_CARD = "mock_campus_card";
    static final String KEY_MOCK_TRAINING_PLAN = "mock_training_plan";
    static final String KEY_TRACE_ENABLED = "trace_enabled";
    static final String KEY_TRACE_EVENTS = "trace_events";
    static final String KEY_HOOK_STATE = "hook_state";
    static final String KEY_HOOK_PROCESS = "hook_process";
    static final String KEY_HOOK_DETAIL = "hook_detail";
    static final String KEY_HOOK_UPDATED_AT = "hook_updated_at";
    static final String KEY_LATENCY_MS = "latency_ms";
    static final String KEY_CUSTOM_DAY_OFFSET = "custom_day_offset";
    static final String KEY_CUSTOM_START_OFFSET_MINUTES = "custom_start_offset_minutes";
    static final String KEY_CUSTOM_DURATION_MINUTES = "custom_duration_minutes";
    static final String KEY_SEMESTER_END_OFFSET_DAYS = "semester_end_offset_days";
    static final String KEY_COURSE_NAME = "course_name";
    static final String KEY_ROOM = "room";
    static final String KEY_SEAT = "seat";

    private HookSettings() {}

    static Snapshot read(SharedPreferences preferences) {
        return new Snapshot(
                preferences.getBoolean(KEY_ENABLED, false),
                MockScenario.fromWireName(preferences.getString(KEY_SCENARIO, null)),
                preferences.getBoolean(KEY_MOCK_SEMESTER, true),
                preferences.getBoolean(KEY_MOCK_ACADEMIC, false),
                preferences.getBoolean(KEY_MOCK_EXAM_INDEX, true),
                preferences.getBoolean(KEY_MOCK_SCHOOL_EXAMS, true),
                preferences.getBoolean(KEY_MOCK_OTHER_EXAMS, true),
                clamp(preferences.getInt(KEY_LATENCY_MS, 0), 0, 10_000),
                clamp(preferences.getInt(KEY_CUSTOM_DAY_OFFSET, 0), -365, 365),
                clamp(preferences.getInt(KEY_CUSTOM_START_OFFSET_MINUTES, -30), -1_440, 10_080),
                clamp(preferences.getInt(KEY_CUSTOM_DURATION_MINUTES, 120), 1, 720),
                clamp(preferences.getInt(KEY_SEMESTER_END_OFFSET_DAYS, -1), -365, 365),
                valueOrDefault(preferences.getString(KEY_COURSE_NAME, null), "高等数学"),
                valueOrDefault(preferences.getString(KEY_ROOM, null), "博学楼 101"),
                valueOrDefault(preferences.getString(KEY_SEAT, null), "18"),
                preferences.getBoolean(KEY_MOCK_SCORES, false),
                preferences.getBoolean(KEY_MOCK_SCHEDULE, false),
                preferences.getBoolean(KEY_MOCK_CAMPUS_CARD, false),
                preferences.getBoolean(KEY_MOCK_TRAINING_PLAN, false),
                preferences.getBoolean(KEY_TRACE_ENABLED, false)
        );
    }

    static void writeDefaults(SharedPreferences preferences) {
        if (preferences.contains(KEY_SCENARIO)) return;
        preferences.edit()
                .putBoolean(KEY_ENABLED, false)
                .putString(KEY_SCENARIO, MockScenario.TODAY_ACTIVE.wireName)
                .putBoolean(KEY_MOCK_SEMESTER, true)
                .putBoolean(KEY_MOCK_ACADEMIC, false)
                .putBoolean(KEY_MOCK_EXAM_INDEX, true)
                .putBoolean(KEY_MOCK_SCHOOL_EXAMS, true)
                .putBoolean(KEY_MOCK_OTHER_EXAMS, true)
                .putBoolean(KEY_MOCK_SCORES, false)
                .putBoolean(KEY_MOCK_SCHEDULE, false)
                .putBoolean(KEY_MOCK_CAMPUS_CARD, false)
                .putBoolean(KEY_MOCK_TRAINING_PLAN, false)
                .putBoolean(KEY_TRACE_ENABLED, false)
                .putInt(KEY_LATENCY_MS, 0)
                .putInt(KEY_CUSTOM_DAY_OFFSET, 0)
                .putInt(KEY_CUSTOM_START_OFFSET_MINUTES, -30)
                .putInt(KEY_CUSTOM_DURATION_MINUTES, 120)
                .putInt(KEY_SEMESTER_END_OFFSET_DAYS, -1)
                .putString(KEY_COURSE_NAME, "高等数学")
                .putString(KEY_ROOM, "博学楼 101")
                .putString(KEY_SEAT, "18")
                .apply();
    }

    private static int clamp(int value, int min, int max) {
        return Math.max(min, Math.min(max, value));
    }

    private static String valueOrDefault(String value, String fallback) {
        if (value == null || value.trim().isEmpty()) return fallback;
        return value.trim();
    }

    static final class Snapshot {
        final boolean enabled;
        final MockScenario scenario;
        final boolean mockSemester;
        final boolean mockAcademic;
        final boolean mockExamIndex;
        final boolean mockSchoolExams;
        final boolean mockOtherExams;
        final boolean mockScores;
        final boolean mockSchedule;
        final boolean mockCampusCard;
        final boolean mockTrainingPlan;
        final boolean traceEnabled;
        final int latencyMs;
        final int customDayOffset;
        final int customStartOffsetMinutes;
        final int customDurationMinutes;
        final int semesterEndOffsetDays;
        final String courseName;
        final String room;
        final String seat;

        Snapshot(
                boolean enabled,
                MockScenario scenario,
                boolean mockSemester,
                boolean mockAcademic,
                boolean mockExamIndex,
                boolean mockSchoolExams,
                boolean mockOtherExams,
                int latencyMs,
                int customDayOffset,
                int customStartOffsetMinutes,
                int customDurationMinutes,
                int semesterEndOffsetDays,
                String courseName,
                String room,
                String seat
        ) {
            this(
                    enabled,
                    scenario,
                    mockSemester,
                    mockAcademic,
                    mockExamIndex,
                    mockSchoolExams,
                    mockOtherExams,
                    latencyMs,
                    customDayOffset,
                    customStartOffsetMinutes,
                    customDurationMinutes,
                    semesterEndOffsetDays,
                    courseName,
                    room,
                    seat,
                    false,
                    false,
                    false,
                    false
            );
        }

        Snapshot(
                boolean enabled,
                MockScenario scenario,
                boolean mockSemester,
                boolean mockAcademic,
                boolean mockExamIndex,
                boolean mockSchoolExams,
                boolean mockOtherExams,
                int latencyMs,
                int customDayOffset,
                int customStartOffsetMinutes,
                int customDurationMinutes,
                int semesterEndOffsetDays,
                String courseName,
                String room,
                String seat,
                boolean mockScores,
                boolean mockSchedule,
                boolean mockCampusCard,
                boolean mockTrainingPlan
        ) {
            this(
                    enabled,
                    scenario,
                    mockSemester,
                    mockAcademic,
                    mockExamIndex,
                    mockSchoolExams,
                    mockOtherExams,
                    latencyMs,
                    customDayOffset,
                    customStartOffsetMinutes,
                    customDurationMinutes,
                    semesterEndOffsetDays,
                    courseName,
                    room,
                    seat,
                    mockScores,
                    mockSchedule,
                    mockCampusCard,
                    mockTrainingPlan,
                    false
            );
        }

        Snapshot(
                boolean enabled,
                MockScenario scenario,
                boolean mockSemester,
                boolean mockAcademic,
                boolean mockExamIndex,
                boolean mockSchoolExams,
                boolean mockOtherExams,
                int latencyMs,
                int customDayOffset,
                int customStartOffsetMinutes,
                int customDurationMinutes,
                int semesterEndOffsetDays,
                String courseName,
                String room,
                String seat,
                boolean mockScores,
                boolean mockSchedule,
                boolean mockCampusCard,
                boolean mockTrainingPlan,
                boolean traceEnabled
        ) {
            this.enabled = enabled;
            this.scenario = scenario;
            this.mockSemester = mockSemester;
            this.mockAcademic = mockAcademic;
            this.mockExamIndex = mockExamIndex;
            this.mockSchoolExams = mockSchoolExams;
            this.mockOtherExams = mockOtherExams;
            this.mockScores = mockScores;
            this.mockSchedule = mockSchedule;
            this.mockCampusCard = mockCampusCard;
            this.mockTrainingPlan = mockTrainingPlan;
            this.traceEnabled = traceEnabled;
            this.latencyMs = latencyMs;
            this.customDayOffset = customDayOffset;
            this.customStartOffsetMinutes = customStartOffsetMinutes;
            this.customDurationMinutes = customDurationMinutes;
            this.semesterEndOffsetDays = semesterEndOffsetDays;
            this.courseName = courseName;
            this.room = room;
            this.seat = seat;
        }

        boolean isPartEnabled(MockPart part) {
            if (!enabled) return false;
            return switch (part) {
                case SEMESTER -> mockSemester;
                case ACADEMIC -> mockAcademic;
                case EXAM_INDEX -> mockExamIndex;
                case SCHOOL_EXAMS -> mockSchoolExams;
                case OTHER_EXAMS -> mockOtherExams;
                case SCORES_INDEX, SCORES_DATA -> mockScores;
                case SCHEDULE_INDEX, STUDENT_SCHEDULE,
                        COURSE_CATALOG_INDEX, COURSE_CATALOG_DATA -> mockSchedule;
                case CAMPUS_CARD_SESSION, CAMPUS_CARD_BALANCE,
                        CAMPUS_CARD_TRANSACTIONS -> mockCampusCard;
                case TRAINING_PLAN_SUMMARY, TRAINING_PLAN_DETAIL -> mockTrainingPlan;
            };
        }
    }
}
