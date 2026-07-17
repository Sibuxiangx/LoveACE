package tech.loveace.testhook;

import com.google.gson.JsonArray;
import com.google.gson.JsonObject;
import com.google.gson.JsonParser;

import java.net.URI;
import java.time.Instant;
import java.time.ZoneId;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Locale;

final class RequestTrace {
    static final int UNKNOWN_STATUS = -1;

    private static final DateTimeFormatter TIME_FORMAT =
            DateTimeFormatter.ofPattern("HH:mm:ss.SSS", Locale.ROOT);

    final long timestampMs;
    final String processName;
    final String transport;
    final String method;
    final String endpoint;
    final String mode;
    final String detail;
    final int statusCode;
    final long elapsedMs;

    RequestTrace(
            long timestampMs,
            String processName,
            String transport,
            String method,
            String endpoint,
            String mode,
            String detail,
            int statusCode,
            long elapsedMs
    ) {
        this.timestampMs = timestampMs;
        this.processName = valueOr(processName, "unknown");
        this.transport = valueOr(transport, "HTTP");
        this.method = valueOr(method, "REQUEST").toUpperCase(Locale.ROOT);
        this.endpoint = valueOr(endpoint, "<unknown-endpoint>");
        this.mode = valueOr(mode, "PASSTHROUGH");
        this.detail = detail == null ? "" : detail;
        this.statusCode = statusCode;
        this.elapsedMs = Math.max(0, elapsedMs);
    }

    static RequestTrace completed(
            String processName,
            String transport,
            String method,
            String rawUrl,
            MockPart mockPart,
            int statusCode,
            long elapsedMs
    ) {
        return new RequestTrace(
                System.currentTimeMillis(),
                processName,
                transport,
                method,
                safeEndpoint(rawUrl),
                mockPart == null ? "PASSTHROUGH" : "MOCK",
                mockPart == null ? "" : mockPart.name(),
                statusCode,
                elapsedMs
        );
    }

    static RequestTrace failed(
            String processName,
            String transport,
            String method,
            String rawUrl,
            Throwable throwable,
            long elapsedMs
    ) {
        return new RequestTrace(
                System.currentTimeMillis(),
                processName,
                transport,
                method,
                safeEndpoint(rawUrl),
                "ERROR",
                throwable == null ? "Throwable" : throwable.getClass().getSimpleName(),
                UNKNOWN_STATUS,
                elapsedMs
        );
    }

    String displayLine() {
        String time = TIME_FORMAT.format(
                Instant.ofEpochMilli(timestampMs).atZone(ZoneId.systemDefault())
        );
        StringBuilder output = new StringBuilder()
                .append(time).append("  ")
                .append(mode).append("  ")
                .append(method).append(' ')
                .append(endpoint).append("  ")
                .append(elapsedMs).append(" ms");
        if (statusCode >= 0) output.append("  HTTP ").append(statusCode);
        if (!detail.isEmpty()) output.append("  ").append(detail);
        return output.toString();
    }

    JsonObject toJson() {
        JsonObject json = new JsonObject();
        json.addProperty("timestampMs", timestampMs);
        json.addProperty("processName", processName);
        json.addProperty("transport", transport);
        json.addProperty("method", method);
        json.addProperty("endpoint", endpoint);
        json.addProperty("mode", mode);
        json.addProperty("detail", detail);
        json.addProperty("statusCode", statusCode);
        json.addProperty("elapsedMs", elapsedMs);
        return json;
    }

    static RequestTrace fromJson(JsonObject json) {
        return new RequestTrace(
                json.get("timestampMs").getAsLong(),
                json.get("processName").getAsString(),
                json.get("transport").getAsString(),
                json.get("method").getAsString(),
                json.get("endpoint").getAsString(),
                json.get("mode").getAsString(),
                stringOr(json, "detail", ""),
                intOr(json, "statusCode", UNKNOWN_STATUS),
                longOr(json, "elapsedMs", 0)
        );
    }

    static String encode(List<RequestTrace> traces) {
        JsonArray array = new JsonArray();
        for (RequestTrace trace : traces) {
            array.add(trace.toJson());
        }
        return array.toString();
    }

    static List<RequestTrace> decode(String encoded) {
        List<RequestTrace> traces = new ArrayList<>();
        if (encoded == null || encoded.isBlank()) return traces;
        try {
            JsonArray array = JsonParser.parseString(encoded).getAsJsonArray();
            for (int index = 0; index < array.size(); index++) {
                try {
                    traces.add(fromJson(array.get(index).getAsJsonObject()));
                } catch (RuntimeException ignored) {
                    // Keep valid records when one persisted item is incomplete.
                }
            }
        } catch (RuntimeException ignored) {
            // Treat an interrupted or stale preference write as an empty trace list.
        }
        return traces;
    }

    static String safeEndpoint(String rawUrl) {
        if (rawUrl == null || rawUrl.isBlank()) return "<unknown-endpoint>";
        try {
            URI uri = URI.create(rawUrl);
            String host = uri.getHost();
            if (host == null || host.isBlank()) return "<invalid-url>";
            StringBuilder output = new StringBuilder(host);
            if (uri.getPort() >= 0) output.append(':').append(uri.getPort());
            String path = uri.getRawPath();
            output.append(path == null || path.isBlank() ? "/" : path);
            return output.toString();
        } catch (IllegalArgumentException ignored) {
            return "<invalid-url>";
        }
    }

    private static String valueOr(String value, String fallback) {
        return value == null || value.isBlank() ? fallback : value;
    }

    private static String stringOr(JsonObject json, String name, String fallback) {
        return json.has(name) && !json.get(name).isJsonNull()
                ? json.get(name).getAsString()
                : fallback;
    }

    private static int intOr(JsonObject json, String name, int fallback) {
        return json.has(name) && !json.get(name).isJsonNull()
                ? json.get(name).getAsInt()
                : fallback;
    }

    private static long longOr(JsonObject json, String name, long fallback) {
        return json.has(name) && !json.get(name).isJsonNull()
                ? json.get(name).getAsLong()
                : fallback;
    }
}
