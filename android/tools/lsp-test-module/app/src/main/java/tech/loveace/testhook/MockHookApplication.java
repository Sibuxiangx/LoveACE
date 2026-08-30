package tech.loveace.testhook;

import android.app.Application;

import com.google.android.material.color.DynamicColors;

import java.util.Set;
import java.util.concurrent.CopyOnWriteArraySet;

import io.github.libxposed.service.XposedService;
import io.github.libxposed.service.XposedServiceHelper;

public final class MockHookApplication extends Application
        implements XposedServiceHelper.OnServiceListener {
    interface ServiceListener {
        void onServiceChanged(XposedService service);
    }

    private static final Set<ServiceListener> LISTENERS = new CopyOnWriteArraySet<>();
    private static volatile XposedService service;

    @Override
    public void onCreate() {
        super.onCreate();
        DynamicColors.applyToActivitiesIfAvailable(this);
        XposedServiceHelper.registerListener(this);
    }

    static void addServiceListener(ServiceListener listener) {
        LISTENERS.add(listener);
        listener.onServiceChanged(service);
    }

    static void removeServiceListener(ServiceListener listener) {
        LISTENERS.remove(listener);
    }

    static XposedService currentService() {
        return service;
    }

    @Override
    public void onServiceBind(XposedService boundService) {
        service = boundService;
        notifyListeners(boundService);
    }

    @Override
    public void onServiceDied(XposedService deadService) {
        if (service == deadService) service = null;
        notifyListeners(service);
    }

    private static void notifyListeners(XposedService current) {
        for (ServiceListener listener : LISTENERS) {
            listener.onServiceChanged(current);
        }
    }
}
