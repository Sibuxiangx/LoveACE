package tech.loveace.testhook;

import android.content.SharedPreferences;
import android.os.SystemClock;
import android.util.Log;

import java.lang.reflect.Method;
import java.net.URL;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.util.concurrent.atomic.AtomicBoolean;

import io.github.libxposed.api.XposedInterface;
import io.github.libxposed.api.XposedModule;

public final class ModernModuleEntry extends XposedModule {
    private static final String TAG = "LoveACELspTest";
    static final String HTTP_CLIENT_CLASS =
            "tech.loveace.appv3.data.network.HttpClient";

    private final AtomicBoolean installed = new AtomicBoolean(false);
    private volatile String processName = "";
    private volatile SharedPreferences preferences;

    @Override
    public void onModuleLoaded(ModuleLoadedParam param) {
        processName = param.getProcessName();
        log(Log.INFO, TAG, "Loaded API " + getApiVersion() + " in " + processName);
    }

    @Override
    public void onPackageReady(PackageReadyParam param) {
        if (installed.get()) return;

        Method execute;
        try {
            execute = findHttpExecuteMethod(param.getClassLoader());
        } catch (ReflectiveOperationException exception) {
            log(Log.WARN, TAG, "LoveACE HTTP client probe failed", exception);
            return;
        }
        if (execute == null || !installed.compareAndSet(false, true)) return;

        try {
            preferences = getRemotePreferences(HookSettings.GROUP);
            installHttpHook(param.getClassLoader(), execute);
            installSemesterHook();
            TraceStore.markHookReady(preferences, processName, getApiVersion());
            log(Log.INFO, TAG, "Hooks ready in " + processName);
        } catch (Throwable throwable) {
            installed.set(false);
            TraceStore.markHookError(preferences, processName, throwable);
            log(Log.ERROR, TAG, "Hook installation failed", throwable);
        }
    }

    static Method findHttpExecuteMethod(ClassLoader classLoader)
            throws ReflectiveOperationException {
        Class<?> httpClient;
        try {
            httpClient = Class.forName(HTTP_CLIENT_CLASS, false, classLoader);
        } catch (ClassNotFoundException ignored) {
            return null;
        }

        Method compatible = null;
        for (Method method : httpClient.getDeclaredMethods()) {
            if (!isHttpExecuteSignature(method)) continue;
            if ("execute".equals(method.getName())) return method;
            compatible = method;
        }
        if (compatible == null) {
            throw new NoSuchMethodException(HTTP_CLIENT_CLASS + ".*(okhttp3.Request)");
        }
        return compatible;
    }

    static boolean isHttpExecuteSignature(Method method) {
        return method.getParameterCount() == 1
                && "okhttp3.Request".equals(method.getParameterTypes()[0].getName())
                && "okhttp3.Response".equals(method.getReturnType().getName());
    }

    private void installHttpHook(ClassLoader classLoader, Method execute) {
        execute.setAccessible(true);

        hook(execute)
                .setId("loveace.lsp-test.http")
                .setPriority(XposedInterface.PRIORITY_HIGHEST)
                .setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                .intercept(chain -> {
                    HookSettings.Snapshot settings = HookSettings.read(preferences);
                    long startedAt = SystemClock.elapsedRealtime();
                    String url = null;
                    String method = null;
                    try {
                        Object request = chain.getArg(0);
                        url = OkHttpReflection.requestUrl(request);
                        method = OkHttpReflection.requestMethod(request);
                        MockResponseSpec response = MockPayloads.forHttpRequest(
                                method,
                                url,
                                settings,
                                LocalDateTime.now()
                        );
                        if (response != null) {
                            sleep(response.latencyMs);
                            Object mocked = OkHttpReflection.buildResponse(
                                    classLoader,
                                    request,
                                    response
                            );
                            recordCompleted(
                                    settings,
                                    "OKHTTP",
                                    method,
                                    url,
                                    response.part,
                                    response.statusCode,
                                    startedAt
                            );
                            log(
                                    Log.INFO,
                                    TAG,
                                    "Mock " + response.part + " " + method + " " + url
                            );
                            return mocked;
                        }

                        Object original = chain.proceed();
                        recordCompleted(
                                settings,
                                "OKHTTP",
                                method,
                                url,
                                null,
                                OkHttpReflection.responseCodeOrUnknown(original),
                                startedAt
                        );
                        return original;
                    } catch (Throwable throwable) {
                        recordFailed(settings, "OKHTTP", method, url, throwable, startedAt);
                        throw throwable;
                    }
                });
    }

    private void installSemesterHook() throws ReflectiveOperationException {
        Method openConnection = URL.class.getDeclaredMethod("openConnection");
        openConnection.setAccessible(true);
        hook(openConnection)
                .setId("loveace.lsp-test.url")
                .setPriority(XposedInterface.PRIORITY_HIGHEST)
                .setExceptionMode(XposedInterface.ExceptionMode.PROTECTIVE)
                .intercept(chain -> {
                    Object owner = chain.getThisObject();
                    if (!(owner instanceof URL url)) return chain.proceed();
                    HookSettings.Snapshot settings = HookSettings.read(preferences);
                    long startedAt = SystemClock.elapsedRealtime();
                    try {
                        MockResponseSpec response = MockPayloads.forSemesterRequest(
                                url.toString(),
                                settings,
                                LocalDate.now()
                        );
                        if (response != null) {
                            recordCompleted(
                                    settings,
                                    "URLCONNECTION",
                                    "GET",
                                    url.toString(),
                                    response.part,
                                    response.statusCode,
                                    startedAt
                            );
                            log(Log.INFO, TAG, "Mock SEMESTER GET " + url);
                            return new MockUrlConnection(url, response);
                        }
                        Object original = chain.proceed();
                        recordCompleted(
                                settings,
                                "URLCONNECTION",
                                "GET",
                                url.toString(),
                                null,
                                RequestTrace.UNKNOWN_STATUS,
                                startedAt
                        );
                        return original;
                    } catch (Throwable throwable) {
                        recordFailed(
                                settings,
                                "URLCONNECTION",
                                "GET",
                                url.toString(),
                                throwable,
                                startedAt
                        );
                        throw throwable;
                    }
                });
    }

    private void recordCompleted(
            HookSettings.Snapshot settings,
            String transport,
            String method,
            String url,
            MockPart mockPart,
            int statusCode,
            long startedAt
    ) {
        if (!settings.traceEnabled) return;
        TraceStore.append(
                preferences,
                RequestTrace.completed(
                        processName,
                        transport,
                        method,
                        url,
                        mockPart,
                        statusCode,
                        elapsedSince(startedAt)
                )
        );
    }

    private void recordFailed(
            HookSettings.Snapshot settings,
            String transport,
            String method,
            String url,
            Throwable throwable,
            long startedAt
    ) {
        if (!settings.traceEnabled) return;
        TraceStore.append(
                preferences,
                RequestTrace.failed(
                        processName,
                        transport,
                        method,
                        url,
                        throwable,
                        elapsedSince(startedAt)
                )
        );
    }

    private static long elapsedSince(long startedAt) {
        return Math.max(0, SystemClock.elapsedRealtime() - startedAt);
    }

    private static void sleep(int milliseconds) throws InterruptedException {
        if (milliseconds > 0) Thread.sleep(milliseconds);
    }
}
