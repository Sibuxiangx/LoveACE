package tech.loveace.testhook;

import android.content.SharedPreferences;

import java.util.ArrayList;
import java.util.List;

final class TraceStore {
    static final int MAX_EVENTS = 40;

    private static final Object WRITE_LOCK = new Object();

    private TraceStore() {}

    static List<RequestTrace> read(SharedPreferences preferences) {
        if (preferences == null) return List.of();
        try {
            return RequestTrace.decode(
                    preferences.getString(HookSettings.KEY_TRACE_EVENTS, "[]")
            );
        } catch (RuntimeException ignored) {
            return List.of();
        }
    }

    static void append(SharedPreferences preferences, RequestTrace trace) {
        if (preferences == null || trace == null) return;
        try {
            if (!preferences.getBoolean(HookSettings.KEY_TRACE_ENABLED, false)) return;
            synchronized (WRITE_LOCK) {
                List<RequestTrace> next = new ArrayList<>(read(preferences));
                next.add(0, trace);
                if (next.size() > MAX_EVENTS) {
                    next = new ArrayList<>(next.subList(0, MAX_EVENTS));
                }
                preferences.edit()
                        .putString(HookSettings.KEY_TRACE_EVENTS, RequestTrace.encode(next))
                        .apply();
            }
        } catch (RuntimeException ignored) {
            // Observation must never affect the target request.
        }
    }

    static void clear(SharedPreferences preferences) {
        if (preferences == null) return;
        preferences.edit().remove(HookSettings.KEY_TRACE_EVENTS).apply();
    }

    static void markHookReady(SharedPreferences preferences, String processName, int apiVersion) {
        writeHookState(preferences, "READY", processName, "API " + apiVersion);
    }

    static void markHookError(
            SharedPreferences preferences,
            String processName,
            Throwable throwable
    ) {
        String detail = throwable == null ? "Throwable" : throwable.getClass().getSimpleName();
        writeHookState(preferences, "ERROR", processName, detail);
    }

    private static void writeHookState(
            SharedPreferences preferences,
            String state,
            String processName,
            String detail
    ) {
        if (preferences == null) return;
        try {
            preferences.edit()
                    .putString(HookSettings.KEY_HOOK_STATE, state)
                    .putString(HookSettings.KEY_HOOK_PROCESS, processName)
                    .putString(HookSettings.KEY_HOOK_DETAIL, detail)
                    .putLong(HookSettings.KEY_HOOK_UPDATED_AT, System.currentTimeMillis())
                    .apply();
        } catch (RuntimeException ignored) {
            // Runtime diagnostics are best-effort and stay outside the hooked call path.
        }
    }
}
