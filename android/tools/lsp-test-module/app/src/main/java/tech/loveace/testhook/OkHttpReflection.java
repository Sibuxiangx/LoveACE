package tech.loveace.testhook;

import java.lang.reflect.Method;
import java.util.Locale;

final class OkHttpReflection {
    private OkHttpReflection() {}

    static String requestUrl(Object request) throws ReflectiveOperationException {
        return invokeNoArg(request, "url", "getUrl").toString();
    }

    static String requestMethod(Object request) throws ReflectiveOperationException {
        return invokeNoArg(request, "method", "getMethod").toString();
    }

    static int responseCodeOrUnknown(Object response) {
        if (response == null) return RequestTrace.UNKNOWN_STATUS;
        try {
            Object value = invokeNoArg(response, "code", "getCode");
            return value instanceof Number number
                    ? number.intValue()
                    : RequestTrace.UNKNOWN_STATUS;
        } catch (ReflectiveOperationException ignored) {
            return RequestTrace.UNKNOWN_STATUS;
        }
    }

    @SuppressWarnings({"rawtypes", "unchecked"})
    static Object buildResponse(
            ClassLoader classLoader,
            Object request,
            MockResponseSpec spec
    ) throws ReflectiveOperationException {
        Class<?> mediaTypeClass = Class.forName("okhttp3.MediaType", false, classLoader);
        Class<?> responseBodyClass = Class.forName("okhttp3.ResponseBody", false, classLoader);
        Class<?> requestClass = Class.forName("okhttp3.Request", false, classLoader);
        Class<?> protocolClass = Class.forName("okhttp3.Protocol", false, classLoader);
        Class<?> builderClass = Class.forName("okhttp3.Response$Builder", false, classLoader);

        Object mediaType = mediaTypeClass.getMethod("parse", String.class)
                .invoke(null, spec.contentType);
        Object responseBody = responseBodyClass
                .getMethod("create", mediaTypeClass, String.class)
                .invoke(null, mediaType, spec.body);
        Object protocol = Enum.valueOf((Class<? extends Enum>) protocolClass, "HTTP_1_1");
        Object builder = builderClass.getConstructor().newInstance();

        builderClass.getMethod("request", requestClass).invoke(builder, request);
        builderClass.getMethod("protocol", protocolClass).invoke(builder, protocol);
        builderClass.getMethod("code", int.class).invoke(builder, spec.statusCode);
        builderClass.getMethod("message", String.class)
                .invoke(builder, statusMessage(spec.statusCode));
        builderClass.getMethod("header", String.class, String.class)
                .invoke(builder, "Content-Type", spec.contentType);
        builderClass.getMethod("header", String.class, String.class)
                .invoke(builder, "X-LoveACE-Mock", spec.part.name().toLowerCase(Locale.ROOT));
        builderClass.getMethod("body", responseBodyClass).invoke(builder, responseBody);
        return builderClass.getMethod("build").invoke(builder);
    }

    private static Object invokeNoArg(Object instance, String primary, String fallback)
            throws ReflectiveOperationException {
        try {
            return instance.getClass().getMethod(primary).invoke(instance);
        } catch (NoSuchMethodException ignored) {
            return instance.getClass().getMethod(fallback).invoke(instance);
        }
    }

    private static String statusMessage(int statusCode) {
        if (statusCode >= 200 && statusCode < 300) return "OK";
        if (statusCode == 503) return "Service Unavailable";
        return "Mock Response";
    }
}
