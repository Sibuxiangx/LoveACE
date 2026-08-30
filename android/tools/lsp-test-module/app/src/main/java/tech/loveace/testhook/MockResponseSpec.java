package tech.loveace.testhook;

final class MockResponseSpec {
    final MockPart part;
    final int statusCode;
    final String contentType;
    final String body;
    final int latencyMs;

    MockResponseSpec(MockPart part, int statusCode, String contentType, String body, int latencyMs) {
        this.part = part;
        this.statusCode = statusCode;
        this.contentType = contentType;
        this.body = body;
        this.latencyMs = latencyMs;
    }
}
