package tech.loveace.testhook;

import android.app.Activity;
import android.content.BroadcastReceiver;
import android.content.Context;
import android.content.Intent;
import android.content.SharedPreferences;

import io.github.libxposed.service.XposedService;

public final class DebugConfigReceiver extends BroadcastReceiver {
    private static final String ACTION = "tech.loveace.testhook.DEBUG_CONFIG";

    @Override
    public void onReceive(Context context, Intent intent) {
        if (!ACTION.equals(intent.getAction())) return;

        XposedService service = MockHookApplication.currentService();
        if (service == null) {
            setResultCode(Activity.RESULT_CANCELED);
            setResultData("xposed_service_pending");
            return;
        }

        SharedPreferences preferences = service.getRemotePreferences(HookSettings.GROUP);
        SharedPreferences.Editor editor = preferences.edit();
        putBoolean(intent, editor, "enabled", HookSettings.KEY_ENABLED);
        putBoolean(intent, editor, "semester", HookSettings.KEY_MOCK_SEMESTER);
        putBoolean(intent, editor, "academic", HookSettings.KEY_MOCK_ACADEMIC);
        putBoolean(intent, editor, "exam_index", HookSettings.KEY_MOCK_EXAM_INDEX);
        putBoolean(intent, editor, "school_exams", HookSettings.KEY_MOCK_SCHOOL_EXAMS);
        putBoolean(intent, editor, "other_exams", HookSettings.KEY_MOCK_OTHER_EXAMS);
        putBoolean(intent, editor, "scores", HookSettings.KEY_MOCK_SCORES);
        putBoolean(intent, editor, "schedule", HookSettings.KEY_MOCK_SCHEDULE);
        putBoolean(intent, editor, "campus_card", HookSettings.KEY_MOCK_CAMPUS_CARD);
        putBoolean(intent, editor, "training_plan", HookSettings.KEY_MOCK_TRAINING_PLAN);
        putBoolean(intent, editor, "trace", HookSettings.KEY_TRACE_ENABLED);
        putInt(intent, editor, "latency_ms", HookSettings.KEY_LATENCY_MS);
        putInt(intent, editor, "day_offset", HookSettings.KEY_CUSTOM_DAY_OFFSET);
        putInt(intent, editor, "start_offset_minutes", HookSettings.KEY_CUSTOM_START_OFFSET_MINUTES);
        putInt(intent, editor, "duration_minutes", HookSettings.KEY_CUSTOM_DURATION_MINUTES);
        putInt(intent, editor, "semester_end_offset_days", HookSettings.KEY_SEMESTER_END_OFFSET_DAYS);
        putString(intent, editor, "scenario", HookSettings.KEY_SCENARIO);
        putString(intent, editor, "course", HookSettings.KEY_COURSE_NAME);
        putString(intent, editor, "room", HookSettings.KEY_ROOM);
        putString(intent, editor, "seat", HookSettings.KEY_SEAT);

        if (intent.hasExtra("all_sources")) {
            boolean enabled = intent.getBooleanExtra("all_sources", false);
            editor.putBoolean(HookSettings.KEY_MOCK_SEMESTER, enabled);
            editor.putBoolean(HookSettings.KEY_MOCK_ACADEMIC, enabled);
            editor.putBoolean(HookSettings.KEY_MOCK_EXAM_INDEX, enabled);
            editor.putBoolean(HookSettings.KEY_MOCK_SCHOOL_EXAMS, enabled);
            editor.putBoolean(HookSettings.KEY_MOCK_OTHER_EXAMS, enabled);
            editor.putBoolean(HookSettings.KEY_MOCK_SCORES, enabled);
            editor.putBoolean(HookSettings.KEY_MOCK_SCHEDULE, enabled);
            editor.putBoolean(HookSettings.KEY_MOCK_CAMPUS_CARD, enabled);
            editor.putBoolean(HookSettings.KEY_MOCK_TRAINING_PLAN, enabled);
        }
        if (intent.getBooleanExtra("clear_trace", false)) {
            editor.remove(HookSettings.KEY_TRACE_EVENTS);
        }

        editor.apply();
        setResultCode(Activity.RESULT_OK);
        setResultData("applied");
    }

    private static void putBoolean(
            Intent intent,
            SharedPreferences.Editor editor,
            String extra,
            String key
    ) {
        if (intent.hasExtra(extra)) editor.putBoolean(key, intent.getBooleanExtra(extra, false));
    }

    private static void putInt(
            Intent intent,
            SharedPreferences.Editor editor,
            String extra,
            String key
    ) {
        if (intent.hasExtra(extra)) editor.putInt(key, intent.getIntExtra(extra, 0));
    }

    private static void putString(
            Intent intent,
            SharedPreferences.Editor editor,
            String extra,
            String key
    ) {
        if (intent.hasExtra(extra)) editor.putString(key, intent.getStringExtra(extra));
    }
}
