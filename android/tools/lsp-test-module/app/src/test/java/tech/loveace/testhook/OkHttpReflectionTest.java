package tech.loveace.testhook;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

import org.junit.Test;

import okhttp3.Request;
import okhttp3.Response;

public class OkHttpReflectionTest {
    @Test
    public void buildsReadableResponseUsingTargetOkHttpTypes() throws Exception {
        Request request = new Request.Builder()
                .url("http://example.test/mock")
                .get()
                .build();
        MockResponseSpec spec = new MockResponseSpec(
                MockPart.SCHOOL_EXAMS,
                200,
                "application/json; charset=utf-8",
                "[{\"title\":\"高等数学\"}]",
                0
        );

        Object result = OkHttpReflection.buildResponse(
                request.getClass().getClassLoader(),
                request,
                spec
        );

        Response response = (Response) result;
        assertEquals(200, response.code());
        assertEquals(200, OkHttpReflection.responseCodeOrUnknown(response));
        assertEquals("school_exams", response.header("X-LoveACE-Mock"));
        assertEquals(spec.body, response.body().string());
        assertNull(response.networkResponse());
    }

    @Test
    public void readsRequestPropertiesAcrossKotlinJvmAccessors() throws Exception {
        Request request = new Request.Builder()
                .url("http://example.test/path?q=1")
                .post(okhttp3.RequestBody.Companion.create(new byte[0]))
                .build();

        assertEquals("POST", OkHttpReflection.requestMethod(request));
        assertEquals("http://example.test/path?q=1", OkHttpReflection.requestUrl(request));
    }

    @Test
    public void returnsUnknownStatusForNonResponseObjects() {
        assertEquals(
                RequestTrace.UNKNOWN_STATUS,
                OkHttpReflection.responseCodeOrUnknown(new Object())
        );
    }
}
