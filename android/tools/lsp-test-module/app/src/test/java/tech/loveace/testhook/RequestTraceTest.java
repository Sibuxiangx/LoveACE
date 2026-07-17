package tech.loveace.testhook;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

import org.junit.Test;

import java.util.List;

public class RequestTraceTest {
    @Test
    public void endpointDropsCredentialsQueryAndFragment() {
        String endpoint = RequestTrace.safeEndpoint(
                "https://user:secret@example.test:8443/student/scores?token=TOKEN#private"
        );

        assertEquals("example.test:8443/student/scores", endpoint);
        assertFalse(endpoint.contains("secret"));
        assertFalse(endpoint.contains("TOKEN"));
    }

    @Test
    public void invalidUrlDoesNotEchoRawInput() {
        assertEquals("<invalid-url>", RequestTrace.safeEndpoint("TOKEN is not a URL"));
    }

    @Test
    public void jsonRoundTripPreservesStructuredFields() {
        RequestTrace original = new RequestTrace(
                1_700_000_000_000L,
                "tech.loveace.appv3.debug",
                "OKHTTP",
                "post",
                "example.test/main/academicInfo",
                "MOCK",
                "ACADEMIC",
                200,
                42
        );

        List<RequestTrace> decoded = RequestTrace.decode(RequestTrace.encode(List.of(original)));

        assertEquals(1, decoded.size());
        RequestTrace restored = decoded.get(0);
        assertEquals(original.processName, restored.processName);
        assertEquals(original.endpoint, restored.endpoint);
        assertEquals("POST", restored.method);
        assertEquals(200, restored.statusCode);
        assertEquals(42, restored.elapsedMs);
    }

    @Test
    public void malformedPersistedTraceIsTreatedAsEmpty() {
        assertTrue(RequestTrace.decode("{not-an-array}").isEmpty());
    }

    @Test
    public void knownPackageVariantsAreAcceptedWithoutHardCodedPrNumbers() {
        assertTrue(TargetPackages.isKnownVariant("tech.loveace.appv3"));
        assertTrue(TargetPackages.isKnownVariant("tech.loveace.appv3.debug"));
        assertTrue(TargetPackages.isKnownVariant("tech.loveace.appv3.pr999"));
        assertFalse(TargetPackages.isKnownVariant("example.test"));
    }
}
