package tech.loveace.testhook;

import java.io.ByteArrayInputStream;
import java.io.IOException;
import java.io.InputStream;
import java.net.URL;
import java.net.URLConnection;
import java.nio.charset.StandardCharsets;

final class MockUrlConnection extends URLConnection {
    private final MockResponseSpec response;

    MockUrlConnection(URL url, MockResponseSpec response) {
        super(url);
        this.response = response;
    }

    @Override
    public void connect() {
        connected = true;
    }

    @Override
    public InputStream getInputStream() throws IOException {
        if (response.latencyMs > 0) {
            try {
                Thread.sleep(response.latencyMs);
            } catch (InterruptedException exception) {
                Thread.currentThread().interrupt();
                throw new IOException("Mock response delay interrupted", exception);
            }
        }
        connected = true;
        return new ByteArrayInputStream(response.body.getBytes(StandardCharsets.UTF_8));
    }

    @Override
    public String getContentType() {
        return response.contentType;
    }

    @Override
    public int getContentLength() {
        return response.body.getBytes(StandardCharsets.UTF_8).length;
    }
}
