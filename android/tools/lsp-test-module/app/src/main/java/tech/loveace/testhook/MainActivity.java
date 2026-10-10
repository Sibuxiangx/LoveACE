package tech.loveace.testhook;

import android.app.Activity;
import android.content.ClipData;
import android.content.ClipboardManager;
import android.content.Intent;
import android.content.SharedPreferences;
import android.content.pm.ResolveInfo;
import android.graphics.Typeface;
import android.os.Build;
import android.os.Bundle;
import android.os.Handler;
import android.os.Looper;
import android.text.Editable;
import android.text.TextWatcher;
import android.transition.TransitionManager;
import android.view.HapticFeedbackConstants;
import android.view.View;
import android.view.inputmethod.EditorInfo;
import android.widget.ArrayAdapter;
import android.widget.ScrollView;
import android.widget.TextView;

import androidx.core.graphics.Insets;
import androidx.core.view.ViewCompat;
import androidx.core.view.WindowCompat;
import androidx.core.view.WindowInsetsCompat;

import com.google.android.material.dialog.MaterialAlertDialogBuilder;
import com.google.android.material.materialswitch.MaterialSwitch;
import com.google.android.material.snackbar.Snackbar;
import com.google.android.material.textfield.TextInputEditText;
import com.google.android.material.transition.platform.MaterialFadeThrough;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.IdentityHashMap;
import java.util.LinkedHashSet;
import java.util.List;
import java.util.Locale;
import java.util.Map;
import java.util.Set;
import java.time.Instant;
import java.time.LocalDateTime;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;

import io.github.libxposed.service.HookedTarget;
import io.github.libxposed.service.XposedService;
import tech.loveace.testhook.databinding.ActivityMainBinding;

public final class MainActivity extends Activity
        implements MockHookApplication.ServiceListener,
        SharedPreferences.OnSharedPreferenceChangeListener {
    private ActivityMainBinding binding;
    private XposedService service;
    private SharedPreferences preferences;
    private boolean updatingUi;
    private MockScenario renderedScenario;
    private List<String> targetPackages = List.of(TargetPackages.PRODUCTION);
    private static final DateTimeFormatter STATUS_TIME_FORMAT =
            DateTimeFormatter.ofPattern("MM-dd HH:mm:ss", Locale.ROOT);
    private final Handler mainHandler = new Handler(Looper.getMainLooper());
    private final Map<TextInputEditText, Runnable> pendingTextSaves = new IdentityHashMap<>();
    private final Runnable statusRefresh = new Runnable() {
        @Override
        public void run() {
            renderServiceState();
            mainHandler.postDelayed(this, 2_000L);
        }
    };

    @Override
    protected void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);
        WindowCompat.setDecorFitsSystemWindows(getWindow(), false);
        binding = ActivityMainBinding.inflate(getLayoutInflater());
        setContentView(binding.getRoot());
        targetPackages = discoverTargetPackages();
        configureWindowInsets();
        configureStaticUi();
        setConfigurationEnabled(false);
        binding.contentRoot.setAlpha(0.92f);
        binding.contentRoot.animate().alpha(1f).setDuration(220L).start();
    }

    private void configureWindowInsets() {
        ViewCompat.setOnApplyWindowInsetsListener(binding.getRoot(), (view, windowInsets) -> {
            Insets safeArea = windowInsets.getInsets(
                    WindowInsetsCompat.Type.systemBars()
                            | WindowInsetsCompat.Type.displayCutout()
            );
            view.setPadding(safeArea.left, safeArea.top, safeArea.right, safeArea.bottom);
            return windowInsets;
        });
        ViewCompat.requestApplyInsets(binding.getRoot());
    }

    @Override
    protected void onStart() {
        super.onStart();
        targetPackages = discoverTargetPackages();
        MockHookApplication.addServiceListener(this);
        mainHandler.removeCallbacks(statusRefresh);
        mainHandler.post(statusRefresh);
    }

    @Override
    protected void onStop() {
        mainHandler.removeCallbacks(statusRefresh);
        flushPendingTextSaves();
        MockHookApplication.removeServiceListener(this);
        detachPreferences();
        super.onStop();
    }

    @Override
    public void onServiceChanged(XposedService nextService) {
        runOnUiThread(() -> bindService(nextService));
    }

    @Override
    public void onSharedPreferenceChanged(SharedPreferences sharedPreferences, String key) {
        runOnUiThread(() -> {
            if (isRuntimeDiagnosticKey(key)) {
                renderDebugState();
            } else {
                renderConfiguration();
            }
        });
    }

    private void configureStaticUi() {
        List<String> labels = new ArrayList<>();
        for (MockScenario scenario : MockScenario.values()) labels.add(scenario.displayName);
        binding.scenarioDropdown.setAdapter(
                new ArrayAdapter<>(this, android.R.layout.simple_list_item_1, labels)
        );
        binding.scenarioDropdown.setOnItemClickListener((parent, view, position, id) -> {
            if (updatingUi || preferences == null) return;
            binding.scenarioDropdown.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP);
            MockScenario scenario = MockScenario.values()[position];
            preferences.edit().putString(HookSettings.KEY_SCENARIO, scenario.wireName).apply();
            renderConfiguration();
        });

        bindSwitch(binding.masterSwitch, HookSettings.KEY_ENABLED);
        bindSwitch(binding.semesterSwitch, HookSettings.KEY_MOCK_SEMESTER);
        bindSwitch(binding.academicSwitch, HookSettings.KEY_MOCK_ACADEMIC);
        bindSwitch(binding.examIndexSwitch, HookSettings.KEY_MOCK_EXAM_INDEX);
        bindSwitch(binding.schoolExamsSwitch, HookSettings.KEY_MOCK_SCHOOL_EXAMS);
        bindSwitch(binding.otherExamsSwitch, HookSettings.KEY_MOCK_OTHER_EXAMS);
        bindSwitch(binding.scoresSwitch, HookSettings.KEY_MOCK_SCORES);
        bindSwitch(binding.scheduleSwitch, HookSettings.KEY_MOCK_SCHEDULE);
        bindSwitch(binding.campusCardSwitch, HookSettings.KEY_MOCK_CAMPUS_CARD);
        bindSwitch(binding.trainingPlanSwitch, HookSettings.KEY_MOCK_TRAINING_PLAN);
        bindSwitch(binding.traceSwitch, HookSettings.KEY_TRACE_ENABLED);

        binding.modeToggleGroup.addOnButtonCheckedListener((group, checkedId, isChecked) -> {
            if (!isChecked) return;
            binding.modeToggleGroup.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP);
            showMode(checkedId == R.id.modeDebugButton);
        });

        binding.latencySlider.addOnChangeListener((slider, value, fromUser) -> {
            binding.latencyValue.setText(getString(R.string.latency_format, Math.round(value)));
        });
        binding.latencySlider.addOnSliderTouchListener(
                new com.google.android.material.slider.Slider.OnSliderTouchListener() {
                    @Override
                    public void onStartTrackingTouch(com.google.android.material.slider.Slider slider) {}

                    @Override
                    public void onStopTrackingTouch(com.google.android.material.slider.Slider slider) {
                        if (preferences != null) {
                            preferences.edit()
                                    .putInt(HookSettings.KEY_LATENCY_MS, Math.round(slider.getValue()))
                                    .apply();
                        }
                    }
                }
        );

        bindIntField(binding.dayOffsetInput, HookSettings.KEY_CUSTOM_DAY_OFFSET, 0);
        bindIntField(binding.startOffsetInput, HookSettings.KEY_CUSTOM_START_OFFSET_MINUTES, -30);
        bindIntField(binding.durationInput, HookSettings.KEY_CUSTOM_DURATION_MINUTES, 120);
        bindIntField(binding.semesterEndOffsetInput, HookSettings.KEY_SEMESTER_END_OFFSET_DAYS, -1);
        bindStringField(binding.courseNameInput, HookSettings.KEY_COURSE_NAME);
        bindStringField(binding.roomInput, HookSettings.KEY_ROOM);
        bindStringField(binding.seatInput, HookSettings.KEY_SEAT);

        binding.requestScopeButton.setOnClickListener(view -> requestTargetScope());
        binding.selectAllSourcesButton.setOnClickListener(view -> setAllSources(true));
        binding.clearAllSourcesButton.setOnClickListener(view -> setAllSources(false));
        binding.examPresetButton.setOnClickListener(view -> applyExamPreset());
        binding.previewButton.setOnClickListener(view -> showResponsePreview());
        binding.resetButton.setOnClickListener(view -> confirmReset());
        binding.openLoveAceButton.setOnClickListener(view -> openLoveAce());
        binding.debugOpenLoveAceButton.setOnClickListener(view -> openLoveAce());
        binding.viewTraceButton.setOnClickListener(view -> showRequestTraces());
        binding.clearTraceButton.setOnClickListener(view -> clearRequestTraces());
        binding.processDetailsButton.setOnClickListener(view -> showProcessDetails());
        binding.copyDiagnosticsButton.setOnClickListener(view -> copyDiagnostics());
        binding.toolbar.setOnMenuItemClickListener(item -> {
            if (item.getItemId() != R.id.action_refresh) return false;
            binding.toolbar.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP);
            renderServiceState();
            renderConfiguration();
            showMessage(getString(R.string.configuration_synced));
            return true;
        });
    }

    private void bindService(XposedService nextService) {
        if (service == nextService && preferences != null) {
            renderServiceState();
            return;
        }
        detachPreferences();
        service = nextService;
        if (service != null) {
            try {
                preferences = service.getRemotePreferences(HookSettings.GROUP);
                HookSettings.writeDefaults(preferences);
                preferences.registerOnSharedPreferenceChangeListener(this);
                setConfigurationEnabled(true);
                renderConfiguration();
                binding.contentRoot.animate().alpha(1f).setDuration(160L).start();
            } catch (RuntimeException exception) {
                preferences = null;
                setConfigurationEnabled(false);
                showMessage(getString(R.string.remote_config_failed));
            }
        } else {
            setConfigurationEnabled(false);
        }
        renderServiceState();
    }

    private void detachPreferences() {
        if (preferences != null) {
            preferences.unregisterOnSharedPreferenceChangeListener(this);
            preferences = null;
        }
    }

    private void renderServiceState() {
        XposedService current = service;
        if (current == null) {
            binding.statusDot.setBackgroundResource(R.drawable.bg_status_waiting);
            binding.frameworkStatus.setText(R.string.framework_waiting);
            binding.scopeStatus.setText(R.string.scope_waiting);
            binding.processStatus.setText(R.string.process_waiting);
            binding.requestScopeButton.setEnabled(false);
            binding.requestScopeButton.setVisibility(View.VISIBLE);
            binding.serviceProgress.setVisibility(View.VISIBLE);
            binding.processDetailsButton.setEnabled(false);
            renderDebugState();
            return;
        }

        try {
            targetPackages = discoverTargetPackages();
            binding.statusDot.setBackgroundResource(R.drawable.bg_status_connected);
            binding.serviceProgress.setVisibility(View.GONE);
            binding.frameworkStatus.setText(getString(
                    R.string.framework_format,
                    current.getFrameworkName(),
                    current.getFrameworkVersion(),
                    current.getApiVersion()
            ));
            List<String> activeScope = current.getScope();
            long scopedTargets = targetPackages.stream()
                    .filter(current.getScope()::contains)
                    .count();
            boolean allInScope = scopedTargets == targetPackages.size();
            binding.scopeStatus.setText(getString(
                    R.string.scope_dynamic_format,
                    scopedTargets,
                    targetPackages.size()
            ));
            binding.requestScopeButton.setEnabled(!allInScope);
            binding.requestScopeButton.setVisibility(allInScope ? View.GONE : View.VISIBLE);

            if (current.getApiVersion() >= 102) {
                long running = current.getRunningTargets().stream()
                        .filter(target -> TargetPackages.supportsProcess(
                                target.getProcessName(),
                                activeScope
                        ))
                        .count();
                binding.processStatus.setText(
                        running > 0
                                ? getString(R.string.process_running, running)
                                : getString(R.string.process_not_running)
                );
                binding.processDetailsButton.setEnabled(true);
            } else {
                binding.processStatus.setText(R.string.process_old_api);
                binding.processDetailsButton.setEnabled(false);
            }
        } catch (RuntimeException exception) {
            binding.statusDot.setBackgroundResource(R.drawable.bg_status_waiting);
            binding.serviceProgress.setVisibility(View.GONE);
            binding.frameworkStatus.setText(R.string.framework_error);
            binding.scopeStatus.setText(R.string.scope_read_failed);
            binding.processStatus.setText(exception.getClass().getSimpleName());
            binding.processDetailsButton.setEnabled(false);
        }
        renderDebugState();
    }

    private void renderConfiguration() {
        if (preferences == null) return;
        HookSettings.Snapshot state = HookSettings.read(preferences);
        updatingUi = true;
        try {
            binding.masterSwitch.setChecked(state.enabled);
            binding.semesterSwitch.setChecked(state.mockSemester);
            binding.academicSwitch.setChecked(state.mockAcademic);
            binding.examIndexSwitch.setChecked(state.mockExamIndex);
            binding.schoolExamsSwitch.setChecked(state.mockSchoolExams);
            binding.otherExamsSwitch.setChecked(state.mockOtherExams);
            binding.scoresSwitch.setChecked(state.mockScores);
            binding.scheduleSwitch.setChecked(state.mockSchedule);
            binding.campusCardSwitch.setChecked(state.mockCampusCard);
            binding.trainingPlanSwitch.setChecked(state.mockTrainingPlan);
            binding.traceSwitch.setChecked(state.traceEnabled);
            binding.scenarioDropdown.setText(state.scenario.displayName, false);
            setCustomFieldsVisible(state.scenario == MockScenario.CUSTOM);
            binding.latencySlider.setValue(Math.min(5000, state.latencyMs));
            binding.latencyValue.setText(getString(R.string.latency_format, state.latencyMs));
            setTextIfDifferent(binding.dayOffsetInput, Integer.toString(state.customDayOffset));
            setTextIfDifferent(binding.startOffsetInput, Integer.toString(state.customStartOffsetMinutes));
            setTextIfDifferent(binding.durationInput, Integer.toString(state.customDurationMinutes));
            setTextIfDifferent(binding.semesterEndOffsetInput, Integer.toString(state.semesterEndOffsetDays));
            setTextIfDifferent(binding.courseNameInput, state.courseName);
            setTextIfDifferent(binding.roomInput, state.room);
            setTextIfDifferent(binding.seatInput, state.seat);
            binding.scenarioSummary.setText(scenarioSummary(state.scenario));
            binding.liveSummary.setText(liveSummary(state));
            renderedScenario = state.scenario;
        } finally {
            updatingUi = false;
        }
        renderDebugState();
    }

    private void bindSwitch(MaterialSwitch control, String key) {
        control.setOnCheckedChangeListener((button, checked) -> {
            if (updatingUi || preferences == null) return;
            control.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP);
            preferences.edit().putBoolean(key, checked).apply();
        });
    }

    private void bindIntField(TextInputEditText field, String key, int fallback) {
        Runnable save = () -> {
            if (updatingUi || preferences == null) return;
            String value = field.getText() == null ? "" : field.getText().toString().trim();
            int parsed;
            try {
                parsed = Integer.parseInt(value);
            } catch (NumberFormatException ignored) {
                parsed = fallback;
            }
            preferences.edit().putInt(key, parsed).apply();
        };
        field.setOnFocusChangeListener((view, hasFocus) -> {
            if (!hasFocus) flushTextSave(field, save);
        });
        field.addTextChangedListener(textWatcher(field, save));
        field.setOnEditorActionListener((view, actionId, event) -> {
            if (actionId == EditorInfo.IME_ACTION_DONE || actionId == EditorInfo.IME_ACTION_NEXT) {
                flushTextSave(field, save);
            }
            return false;
        });
    }

    private void bindStringField(TextInputEditText field, String key) {
        Runnable save = () -> {
            if (updatingUi || preferences == null) return;
            String value = field.getText() == null ? "" : field.getText().toString().trim();
            preferences.edit().putString(key, value).apply();
        };
        field.setOnFocusChangeListener((view, hasFocus) -> {
            if (!hasFocus) flushTextSave(field, save);
        });
        field.addTextChangedListener(textWatcher(field, save));
        field.setOnEditorActionListener((view, actionId, event) -> {
            if (actionId == EditorInfo.IME_ACTION_DONE || actionId == EditorInfo.IME_ACTION_NEXT) {
                flushTextSave(field, save);
            }
            return false;
        });
    }

    private TextWatcher textWatcher(TextInputEditText field, Runnable save) {
        return new TextWatcher() {
            @Override
            public void beforeTextChanged(CharSequence value, int start, int count, int after) {}

            @Override
            public void onTextChanged(CharSequence value, int start, int before, int count) {}

            @Override
            public void afterTextChanged(Editable value) {
                if (updatingUi || preferences == null) return;
                Runnable oldTask = pendingTextSaves.remove(field);
                if (oldTask != null) mainHandler.removeCallbacks(oldTask);
                Runnable newTask = new Runnable() {
                    @Override
                    public void run() {
                        pendingTextSaves.remove(field);
                        save.run();
                    }
                };
                pendingTextSaves.put(field, newTask);
                mainHandler.postDelayed(newTask, 320L);
            }
        };
    }

    private void flushTextSave(TextInputEditText field, Runnable fallback) {
        Runnable task = pendingTextSaves.remove(field);
        if (task != null) {
            mainHandler.removeCallbacks(task);
            task.run();
        } else {
            fallback.run();
        }
    }

    private void flushPendingTextSaves() {
        List<Runnable> tasks = new ArrayList<>(pendingTextSaves.values());
        pendingTextSaves.clear();
        for (Runnable task : tasks) {
            mainHandler.removeCallbacks(task);
            task.run();
        }
    }

    private void setCustomFieldsVisible(boolean visible) {
        int targetVisibility = visible ? View.VISIBLE : View.GONE;
        if (binding.customGroup.getVisibility() == targetVisibility) return;
        if (renderedScenario != null) {
            MaterialFadeThrough transition = new MaterialFadeThrough();
            transition.setDuration(180L);
            TransitionManager.beginDelayedTransition(binding.contentRoot, transition);
        }
        binding.customGroup.setVisibility(targetVisibility);
    }

    private void showMode(boolean debugMode) {
        int debugVisibility = debugMode ? View.VISIBLE : View.GONE;
        if (binding.debugPanel.getVisibility() == debugVisibility) return;
        MaterialFadeThrough transition = new MaterialFadeThrough();
        transition.setDuration(180L);
        TransitionManager.beginDelayedTransition(binding.contentRoot, transition);
        binding.debugPanel.setVisibility(debugVisibility);
        binding.mockPanel.setVisibility(debugMode ? View.GONE : View.VISIBLE);
        binding.contentScroll.post(() -> binding.contentScroll.smoothScrollTo(0, 0));
    }

    private void renderDebugState() {
        if (binding == null) return;
        if (preferences == null) {
            binding.traceSummary.setText(R.string.trace_empty);
            binding.lastTrace.setText(R.string.trace_waiting);
            binding.hookStatus.setText(R.string.hook_waiting);
            binding.viewTraceButton.setEnabled(false);
            binding.clearTraceButton.setEnabled(false);
            return;
        }

        List<RequestTrace> traces = TraceStore.read(preferences);
        binding.traceSummary.setText(getString(R.string.trace_count, traces.size()));
        binding.lastTrace.setText(
                traces.isEmpty() ? getString(R.string.trace_waiting) : traces.get(0).displayLine()
        );
        binding.hookStatus.setText(hookStatusText());
        binding.viewTraceButton.setEnabled(!traces.isEmpty());
        binding.clearTraceButton.setEnabled(!traces.isEmpty());
    }

    private String hookStatusText() {
        if (preferences == null) return getString(R.string.hook_waiting);
        String state = preferences.getString(HookSettings.KEY_HOOK_STATE, "WAITING");
        String process = preferences.getString(HookSettings.KEY_HOOK_PROCESS, "");
        String detail = preferences.getString(HookSettings.KEY_HOOK_DETAIL, "");
        long updatedAt = preferences.getLong(HookSettings.KEY_HOOK_UPDATED_AT, 0);
        String time = updatedAt <= 0
                ? getString(R.string.time_unknown)
                : STATUS_TIME_FORMAT.format(
                        Instant.ofEpochMilli(updatedAt).atZone(ZoneId.systemDefault())
                );
        if ("READY".equals(state)) {
            return getString(R.string.hook_ready, process, detail, time);
        }
        if ("ERROR".equals(state)) {
            return getString(R.string.hook_error, process, detail, time);
        }
        return getString(R.string.hook_waiting);
    }

    private static boolean isRuntimeDiagnosticKey(String key) {
        return key != null && (
                HookSettings.KEY_TRACE_EVENTS.equals(key)
                        || HookSettings.KEY_HOOK_STATE.equals(key)
                        || HookSettings.KEY_HOOK_PROCESS.equals(key)
                        || HookSettings.KEY_HOOK_DETAIL.equals(key)
                        || HookSettings.KEY_HOOK_UPDATED_AT.equals(key)
        );
    }

    private void setConfigurationEnabled(boolean enabled) {
        List<View> controls = Arrays.asList(
                binding.masterSwitch,
                binding.semesterSwitch,
                binding.academicSwitch,
                binding.examIndexSwitch,
                binding.schoolExamsSwitch,
                binding.otherExamsSwitch,
                binding.scoresSwitch,
                binding.scheduleSwitch,
                binding.campusCardSwitch,
                binding.trainingPlanSwitch,
                binding.traceSwitch,
                binding.scenarioDropdown,
                binding.latencySlider,
                binding.dayOffsetInput,
                binding.startOffsetInput,
                binding.durationInput,
                binding.courseNameInput,
                binding.roomInput,
                binding.seatInput,
                binding.semesterEndOffsetInput,
                binding.selectAllSourcesButton,
                binding.clearAllSourcesButton,
                binding.examPresetButton,
                binding.previewButton,
                binding.resetButton
        );
        for (View control : controls) control.setEnabled(enabled);
    }

    private void requestTargetScope() {
        if (service == null) return;
        targetPackages = discoverTargetPackages();
        service.requestScope(
                targetPackages,
                new XposedService.OnScopeEventListener() {
                    @Override
                    public void onScopeRequestApproved(List<String> approved) {
                        runOnUiThread(() -> {
                            showMessage(getString(R.string.scope_updated));
                            renderServiceState();
                        });
                    }

                    @Override
                    public void onScopeRequestFailed(String message) {
                        runOnUiThread(() -> showMessage(
                                getString(R.string.scope_update_failed, message)
                        ));
                    }
                }
        );
    }

    private void setAllSources(boolean enabled) {
        if (preferences == null) return;
        binding.contentRoot.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP);
        preferences.edit()
                .putBoolean(HookSettings.KEY_MOCK_SEMESTER, enabled)
                .putBoolean(HookSettings.KEY_MOCK_ACADEMIC, enabled)
                .putBoolean(HookSettings.KEY_MOCK_EXAM_INDEX, enabled)
                .putBoolean(HookSettings.KEY_MOCK_SCHOOL_EXAMS, enabled)
                .putBoolean(HookSettings.KEY_MOCK_OTHER_EXAMS, enabled)
                .putBoolean(HookSettings.KEY_MOCK_SCORES, enabled)
                .putBoolean(HookSettings.KEY_MOCK_SCHEDULE, enabled)
                .putBoolean(HookSettings.KEY_MOCK_CAMPUS_CARD, enabled)
                .putBoolean(HookSettings.KEY_MOCK_TRAINING_PLAN, enabled)
                .apply();
    }

    private void applyExamPreset() {
        if (preferences == null) return;
        binding.contentRoot.performHapticFeedback(HapticFeedbackConstants.KEYBOARD_TAP);
        preferences.edit()
                .putBoolean(HookSettings.KEY_MOCK_SEMESTER, true)
                .putBoolean(HookSettings.KEY_MOCK_ACADEMIC, false)
                .putBoolean(HookSettings.KEY_MOCK_EXAM_INDEX, true)
                .putBoolean(HookSettings.KEY_MOCK_SCHOOL_EXAMS, true)
                .putBoolean(HookSettings.KEY_MOCK_OTHER_EXAMS, true)
                .putBoolean(HookSettings.KEY_MOCK_SCORES, false)
                .putBoolean(HookSettings.KEY_MOCK_SCHEDULE, false)
                .putBoolean(HookSettings.KEY_MOCK_CAMPUS_CARD, false)
                .putBoolean(HookSettings.KEY_MOCK_TRAINING_PLAN, false)
                .apply();
        showMessage(getString(R.string.exam_preset_applied));
    }

    private void showResponsePreview() {
        if (preferences == null) return;
        HookSettings.Snapshot settings = HookSettings.read(preferences);
        LocalDateTime now = LocalDateTime.now();
        StringBuilder preview = new StringBuilder();
        appendPreview(
                preview,
                "SEMESTER · GET semesters.json",
                MockPayloads.forSemesterRequest(MockPayloads.SEMESTER_URL, settings, now.toLocalDate())
        );
        appendPreview(
                preview,
                "ACADEMIC · POST /main/academicInfo",
                MockPayloads.forHttpRequest(
                        "POST",
                        "http://" + MockPayloads.JWC_HOST + ":8118/main/academicInfo?sf_request_type=ajax",
                        settings,
                        now
                )
        );
        appendPreview(
                preview,
                "EXAM_INDEX · GET /examPlan/index",
                MockPayloads.forHttpRequest(
                        "GET",
                        "http://" + MockPayloads.JWC_HOST
                                + ":8118/student/examinationManagement/examPlan/index",
                        settings,
                        now
                )
        );
        appendPreview(
                preview,
                "SCHOOL_EXAMS · GET /examPlan/detail",
                MockPayloads.forHttpRequest(
                        "GET",
                        "http://" + MockPayloads.JWC_HOST
                                + ":8118/student/examinationManagement/examPlan/detail",
                        settings,
                        now
                )
        );
        appendPreview(
                preview,
                "OTHER_EXAMS · POST /othersExamPlan/queryScores",
                MockPayloads.forHttpRequest(
                        "POST",
                        "http://" + MockPayloads.JWC_HOST
                                + ":8118/student/examinationManagement/othersExamPlan/queryScores",
                        settings,
                        now
                )
        );
        String jwcBase = "http://" + MockPayloads.JWC_HOST + ":8118";
        appendHttpPreview(preview, "SCORES_INDEX", "GET",
                jwcBase + "/student/integratedQuery/scoreQuery/allTermScores/index", settings, now);
        appendHttpPreview(preview, "SCORES_DATA", "POST",
                jwcBase + "/student/integratedQuery/scoreQuery/MOCKSCORE/allTermScores/data",
                settings, now);
        appendHttpPreview(preview, "SCHEDULE_INDEX", "GET",
                jwcBase + "/student/courseSelect/calendarSemesterCurriculum/index", settings, now);
        appendHttpPreview(preview, "STUDENT_SCHEDULE", "POST",
                jwcBase + "/student/courseSelect/thisSemesterCurriculum/MOCKSCHEDULE/"
                        + "ajaxStudentSchedule/past/callback",
                settings, now);
        appendHttpPreview(preview, "COURSE_CATALOG_INDEX", "GET",
                jwcBase + "/student/integratedQuery/course/courseSchdule/index", settings, now);
        appendHttpPreview(preview, "COURSE_CATALOG_DATA", "POST",
                jwcBase + "/student/integratedQuery/course/courseSchdule/courseInfo",
                settings, now);
        String cardBase = "http://" + MockPayloads.CAMPUS_CARD_HOST + ":8118";
        appendHttpPreview(preview, "CAMPUS_CARD_SESSION", "GET",
                cardBase + "/casLogin.jsp", settings, now);
        appendHttpPreview(preview, "CAMPUS_CARD_BALANCE", "GET",
                cardBase + "/queryUserBalances.action", settings, now);
        appendHttpPreview(preview, "CAMPUS_CARD_TRANSACTIONS", "POST",
                cardBase + "/queryUserCostList.action", settings, now);
        appendHttpPreview(preview, "TRAINING_PLAN_SUMMARY", "GET",
                jwcBase + "/main/showPyfaInfo", settings, now);
        appendHttpPreview(preview, "TRAINING_PLAN_DETAIL", "GET",
                jwcBase + "/student/integratedQuery/planCompletion/index", settings, now);

        showCopyableTextDialog(
                R.string.preview_title,
                "LoveACE mock responses",
                preview.toString()
        );
    }

    private void showRequestTraces() {
        List<RequestTrace> traces = TraceStore.read(preferences);
        if (traces.isEmpty()) {
            showMessage(getString(R.string.trace_empty));
            return;
        }
        StringBuilder output = new StringBuilder();
        for (RequestTrace trace : traces) {
            if (output.length() > 0) output.append('\n');
            output.append(trace.displayLine())
                    .append("  [")
                    .append(trace.transport)
                    .append(" · ")
                    .append(trace.processName)
                    .append(']');
        }
        showCopyableTextDialog(
                R.string.trace_dialog_title,
                "LoveACE request trace",
                output.toString()
        );
    }

    private void clearRequestTraces() {
        TraceStore.clear(preferences);
        renderDebugState();
        showMessage(getString(R.string.trace_cleared));
    }

    private void showProcessDetails() {
        showCopyableTextDialog(
                R.string.process_details_title,
                "LoveACE process details",
                processDetailsText()
        );
    }

    private void copyDiagnostics() {
        copyText("LoveACE LSP diagnostics", diagnosticReport());
        showMessage(getString(R.string.diagnostics_copied));
    }

    private String diagnosticReport() {
        StringBuilder output = new StringBuilder()
                .append("LoveACE LSP Test Tool ")
                .append(BuildConfig.VERSION_NAME)
                .append('\n')
                .append("Generated: ")
                .append(STATUS_TIME_FORMAT.format(Instant.now().atZone(ZoneId.systemDefault())))
                .append('\n')
                .append("Device: ")
                .append(Build.MANUFACTURER).append(' ').append(Build.MODEL)
                .append(" · Android ").append(Build.VERSION.RELEASE)
                .append(" (API ").append(Build.VERSION.SDK_INT).append(")\n")
                .append("Detected targets: ").append(String.join(", ", targetPackages))
                .append('\n');

        XposedService current = service;
        if (current == null) {
            output.append("Framework: disconnected\n");
        } else {
            try {
                output.append("Framework: ")
                        .append(current.getFrameworkName()).append(' ')
                        .append(current.getFrameworkVersion())
                        .append(" · API ").append(current.getApiVersion()).append('\n')
                        .append("Scope: ").append(String.join(", ", current.getScope())).append('\n');
            } catch (RuntimeException exception) {
                output.append("Framework: ").append(exception.getClass().getSimpleName()).append('\n');
            }
        }

        output.append("Hook: ").append(hookStatusText()).append('\n');
        if (preferences != null) {
            HookSettings.Snapshot settings = HookSettings.read(preferences);
            output.append("Mock: ").append(liveSummary(settings)).append('\n')
                    .append("Trace: ")
                    .append(settings.traceEnabled ? "enabled" : "disabled")
                    .append(" · ").append(TraceStore.read(preferences).size()).append(" events\n");
        }
        output.append('\n').append(processDetailsText());

        List<RequestTrace> traces = TraceStore.read(preferences);
        if (!traces.isEmpty()) {
            output.append("\nRecent traces:\n");
            int limit = Math.min(10, traces.size());
            for (int index = 0; index < limit; index++) {
                output.append("- ").append(traces.get(index).displayLine()).append('\n');
            }
        }
        return output.toString().trim();
    }

    private String processDetailsText() {
        XposedService current = service;
        if (current == null) return getString(R.string.framework_waiting);
        try {
            List<HookedTarget> targets = current.getRunningTargets();
            if (targets.isEmpty()) return getString(R.string.process_not_running);
            StringBuilder output = new StringBuilder();
            for (HookedTarget target : targets) {
                if (output.length() > 0) output.append('\n');
                output.append(target.getProcessName())
                        .append("\n  PID ").append(target.getPid())
                        .append(" · UID ").append(target.getUid())
                        .append(" · ").append(target.getState())
                        .append("\n  loaded module versionCode ")
                        .append(target.getLoadedVersionCode());
            }
            return output.toString();
        } catch (RuntimeException exception) {
            return exception.getClass().getSimpleName();
        }
    }

    private void showCopyableTextDialog(int title, String clipboardLabel, String content) {
        TextView textView = new TextView(this);
        int padding = Math.round(16 * getResources().getDisplayMetrics().density);
        textView.setPadding(padding, padding, padding, padding);
        textView.setText(content);
        textView.setTextIsSelectable(true);
        textView.setTextSize(12f);
        textView.setTypeface(Typeface.MONOSPACE);

        ScrollView scrollView = new ScrollView(this);
        scrollView.addView(textView);
        new MaterialAlertDialogBuilder(this)
                .setTitle(title)
                .setView(scrollView)
                .setNegativeButton(R.string.close, null)
                .setPositiveButton(R.string.copy, (dialog, which) -> {
                    copyText(clipboardLabel, content);
                    showMessage(getString(R.string.copied));
                })
                .show();
    }

    private void copyText(String label, CharSequence content) {
        ClipboardManager clipboard = getSystemService(ClipboardManager.class);
        if (clipboard != null) {
            clipboard.setPrimaryClip(ClipData.newPlainText(label, content));
        }
    }

    private static void appendHttpPreview(
            StringBuilder output,
            String title,
            String method,
            String url,
            HookSettings.Snapshot settings,
            LocalDateTime now
    ) {
        appendPreview(
                output,
                title + " · " + method,
                MockPayloads.forHttpRequest(method, url, settings, now)
        );
    }

    private static void appendPreview(
            StringBuilder output,
            String title,
            MockResponseSpec response
    ) {
        if (output.length() > 0) output.append("\n\n");
        output.append("=== ").append(title).append(" ===\n");
        if (response == null) {
            output.append("PASSTHROUGH");
            return;
        }
        output.append("HTTP ").append(response.statusCode)
                .append(" · ").append(response.contentType)
                .append(" · delay=").append(response.latencyMs).append("ms\n")
                .append(response.body);
    }

    private void confirmReset() {
        if (preferences == null) return;
        new MaterialAlertDialogBuilder(this)
                .setTitle(R.string.reset_title)
                .setMessage(R.string.reset_message)
                .setNegativeButton(R.string.cancel, null)
                .setPositiveButton(R.string.reset, (dialog, which) -> {
                    preferences.edit().clear().apply();
                    HookSettings.writeDefaults(preferences);
                    renderConfiguration();
                })
                .show();
    }

    private void openLoveAce() {
        targetPackages = discoverTargetPackages();
        List<String> candidates = new ArrayList<>();
        if (service != null && service.getApiVersion() >= 102) {
            try {
                for (HookedTarget target : service.getRunningTargets()) {
                    String packageName = TargetPackages.packageFromProcess(target.getProcessName());
                    if (!candidates.contains(packageName)) candidates.add(packageName);
                }
            } catch (RuntimeException ignored) {
                // Fall back to installed launcher targets.
            }
        }
        for (String packageName : targetPackages) {
            if (!candidates.contains(packageName)) candidates.add(packageName);
        }

        Intent launchIntent = null;
        for (String packageName : candidates) {
            launchIntent = getPackageManager().getLaunchIntentForPackage(packageName);
            if (launchIntent != null) break;
        }
        if (launchIntent == null) {
            showMessage(getString(R.string.loveace_not_found));
            return;
        }
        launchIntent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
        startActivity(launchIntent);
    }

    @SuppressWarnings("deprecation")
    private List<String> discoverTargetPackages() {
        Set<String> discovered = new LinkedHashSet<>();
        Intent launcher = new Intent(Intent.ACTION_MAIN)
                .addCategory(Intent.CATEGORY_LAUNCHER);
        for (ResolveInfo info : getPackageManager().queryIntentActivities(launcher, 0)) {
            if (info.activityInfo == null) continue;
            String packageName = info.activityInfo.packageName;
            if (TargetPackages.isKnownVariant(packageName)) discovered.add(packageName);
        }
        if (getPackageManager().getLaunchIntentForPackage(TargetPackages.PRODUCTION) != null) {
            discovered.add(TargetPackages.PRODUCTION);
        }
        if (discovered.isEmpty()) discovered.add(TargetPackages.PRODUCTION);
        return List.copyOf(discovered);
    }

    private String liveSummary(HookSettings.Snapshot state) {
        if (!state.enabled) return getString(R.string.real_passthrough);
        int count = 0;
        if (state.mockSemester) count++;
        if (state.mockAcademic) count++;
        if (state.mockExamIndex) count++;
        if (state.mockSchoolExams) count++;
        if (state.mockOtherExams) count++;
        if (state.mockScores) count++;
        if (state.mockSchedule) count++;
        if (state.mockCampusCard) count++;
        if (state.mockTrainingPlan) count++;
        return getString(R.string.live_summary, state.scenario.displayName, count);
    }

    private String scenarioSummary(MockScenario scenario) {
        return switch (scenario) {
            case TODAY_ACTIVE -> getString(R.string.scenario_today_summary);
            case THIS_WEEK -> getString(R.string.scenario_week_summary);
            case UPCOMING -> getString(R.string.scenario_upcoming_summary);
            case JUST_ENDED -> getString(R.string.scenario_ended_summary);
            case ALL_FINISHED -> getString(R.string.scenario_finished_summary);
            case EMPTY -> getString(R.string.scenario_empty_summary);
            case MALFORMED -> getString(R.string.scenario_malformed_summary);
            case SERVER_ERROR -> getString(R.string.scenario_error_summary);
            case CUSTOM -> getString(R.string.scenario_custom_summary);
        };
    }

    private static void setTextIfDifferent(TextInputEditText field, String value) {
        String current = field.getText() == null ? "" : field.getText().toString();
        if (!current.equals(value)) field.setText(value);
    }

    private void showMessage(String message) {
        Snackbar.make(binding.getRoot(), message, Snackbar.LENGTH_SHORT).show();
    }
}
