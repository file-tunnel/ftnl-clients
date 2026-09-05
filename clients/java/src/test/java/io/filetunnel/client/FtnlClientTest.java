package io.filetunnel.client;

import com.sun.net.httpserver.HttpExchange;
import com.sun.net.httpserver.HttpServer;
import java.io.IOException;
import java.net.InetSocketAddress;
import java.net.URI;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.util.List;
import java.util.concurrent.atomic.AtomicReference;

public final class FtnlClientTest {
    private static final String TUNNEL_ID = "8be939aa-686e-41c4-a7e1-d4152150a8ad";
    private static final String FILE_ID = "e156358a-8382-4ad8-91f3-7d9becd8b69d";
    private static final String PAIRING_SECRET = "pairing-secret-000000000000000000";
    private static final String DESKTOP_CAPABILITY = "desktop-capability-00000000000000";
    private static final String PHONE_CAPABILITY = "phone-capability-0000000000000000";
    private static final String EVENT_TICKET = "event-ticket-000000000000000000000";
    private static final byte[] PAYLOAD = new byte[] {0, 1, 2, 3, (byte) 255};

    private FtnlClientTest() {}

    public static void main(String[] args) throws Exception {
        AtomicReference<byte[]> uploaded = new AtomicReference<>();
        HttpServer server = HttpServer.create(new InetSocketAddress("127.0.0.1", 0), 0);
        server.createContext("/", exchange -> handle(exchange, uploaded));
        server.start();
        try {
            URI base = URI.create("http://127.0.0.1:" + server.getAddress().getPort());
            FtnlClient client = new FtnlClient(base, Duration.ofSeconds(5));

            FtnlClient.Tunnel tunnel = client.createTunnel("java-conformance", List.of("image/*"), 2, 1024, 120);
            check(tunnel.tunnelId().equals(TUNNEL_ID), "create tunnel id");
            check(tunnel.status().equals("waiting"), "create status");
            check(tunnel.toString().contains(TUNNEL_ID), "safe tunnel summary");
            check(!tunnel.toString().contains(PAIRING_SECRET), "pairing secret redaction");
            check(!tunnel.toString().contains(DESKTOP_CAPABILITY), "desktop capability redaction");
            check(PAIRING_SECRET.equals(FtnlClient.pairingSecretFromUri(tunnel.pairingUri())), "fragment pairing");
            check(FtnlClient.pairingSecretFromUri(
                    URI.create("https://file-tunnel.dev/pair/" + TUNNEL_ID + "?c=" + PAIRING_SECRET)) == null,
                    "query pairing rejected");

            FtnlClient.Claim claim = client.claimTunnel(TUNNEL_ID, PAIRING_SECRET, "android-example");
            check(claim.phoneCapability().equals(PHONE_CAPABILITY), "claim capability");
            check(!claim.toString().contains(PHONE_CAPABILITY), "phone capability redaction");

            FtnlClient.TunnelSnapshot snapshot = client.snapshot(TUNNEL_ID, DESKTOP_CAPABILITY);
            check(snapshot.files().isEmpty(), "initial snapshot");

            FtnlClient.FileDescriptor file = client.declareFile(
                    TUNNEL_ID,
                    PHONE_CAPABILITY,
                    "photo.jpg",
                    "image/jpeg",
                    PAYLOAD.length,
                    123L,
                    "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa",
                    "java-test-request");
            check(file.fileId().equals(FILE_ID), "declared file id");

            client.upload(TUNNEL_ID, FILE_ID, PHONE_CAPABILITY, PAYLOAD);
            check(java.util.Arrays.equals(uploaded.get(), PAYLOAD), "uploaded bytes");
            check(java.util.Arrays.equals(client.download(TUNNEL_ID, FILE_ID, DESKTOP_CAPABILITY), PAYLOAD),
                    "downloaded bytes");

            URI eventUri = client.eventSocketUri(TUNNEL_ID, DESKTOP_CAPABILITY);
            check(eventUri.getScheme().equals("ws"), "event socket scheme");
            check(eventUri.getRawQuery().equals("ticket=" + EVENT_TICKET), "one-time event ticket");

            client.cancel(TUNNEL_ID, DESKTOP_CAPABILITY);
            verifySafeError(client);
            verifyBaseUriPolicy();
        } finally {
            server.stop(0);
        }
    }

    private static void verifySafeError(FtnlClient client) throws Exception {
        String bodySecret = "body-secret-must-never-escape";
        try {
            client.snapshot("error", DESKTOP_CAPABILITY);
            throw new AssertionError("expected an API error");
        } catch (FtnlClient.FileTunnelException exception) {
            check(exception.status() == 401, "error status");
            check(exception.code().equals("pairing_expired"), "problem code");
            check(!exception.getMessage().contains(bodySecret), "error body redaction");
            check(!exception.getMessage().contains(DESKTOP_CAPABILITY), "capability redaction");
        }
    }

    private static void verifyBaseUriPolicy() {
        new FtnlClient("http://[::1]:8080");
        expectIllegal(() -> new FtnlClient("http://example.com"), "public cleartext rejected");
        expectIllegal(
                () -> new FtnlClient("http://[2001:4860:4860::8888]"),
                "public IPv6 cleartext rejected");
        expectIllegal(() -> new FtnlClient("ftp://localhost"), "unsupported scheme rejected");
        expectIllegal(() -> new FtnlClient("https://user:secret@example.com"), "userinfo rejected");
        expectIllegal(
                () -> new FtnlClient(URI.create("https://example.com"), Duration.ZERO),
                "invalid timeout rejected");
    }

    private static void handle(HttpExchange exchange, AtomicReference<byte[]> uploaded) throws IOException {
        String path = exchange.getRequestURI().getPath();
        String method = exchange.getRequestMethod();
        byte[] requestBody = exchange.getRequestBody().readAllBytes();

        if (path.equals("/v1/tunnels") && method.equals("POST")) {
            String body = new String(requestBody, StandardCharsets.UTF_8);
            check(body.contains("\"application_id\":\"java-conformance\""), "create request body");
            json(exchange, 201, "{\"api_version\":\"v1\",\"tunnel_id\":\"" + TUNNEL_ID
                    + "\",\"status\":\"waiting\",\"pairing_uri\":\"https://file-tunnel.dev/pair/" + TUNNEL_ID
                    + "#c=" + PAIRING_SECRET + "\",\"desktop_capability\":\"" + DESKTOP_CAPABILITY
                    + "\",\"expires_at\":\"2030-01-01T00:00:00Z\"}");
            return;
        }
        if (path.equals("/v1/tunnels/" + TUNNEL_ID + "/claim") && method.equals("POST")) {
            String body = new String(requestBody, StandardCharsets.UTF_8);
            check(body.contains(PAIRING_SECRET), "claim secret body");
            check(exchange.getRequestHeaders().getFirst("Authorization") == null, "claim is unauthenticated");
            json(exchange, 200, "{\"phone_capability\":\"" + PHONE_CAPABILITY
                    + "\",\"expires_at\":\"2030-01-01T00:00:00Z\"}");
            return;
        }
        if (path.equals("/v1/tunnels/" + TUNNEL_ID) && method.equals("GET")) {
            capability(exchange, DESKTOP_CAPABILITY);
            json(exchange, 200, "{\"tunnel_id\":\"" + TUNNEL_ID
                    + "\",\"status\":\"connected\",\"expires_at\":\"2030-01-01T00:00:00Z\",\"files\":[]}");
            return;
        }
        if (path.equals("/v1/tunnels/" + TUNNEL_ID + "/files") && method.equals("POST")) {
            capability(exchange, PHONE_CAPABILITY);
            check("java-test-request".equals(exchange.getRequestHeaders().getFirst("Idempotency-Key")),
                    "idempotency header");
            json(exchange, 201, "{\"file_id\":\"" + FILE_ID
                    + "\",\"name\":\"photo.jpg\",\"media_type\":\"image/jpeg\",\"size_bytes\":5,"
                    + "\"bytes_transferred\":0,\"status\":\"declared\",\"created_at\":\"2030-01-01T00:00:00Z\"}");
            return;
        }
        if (path.equals("/v1/tunnels/" + TUNNEL_ID + "/files/" + FILE_ID + "/content")) {
            if (method.equals("PUT")) {
                capability(exchange, PHONE_CAPABILITY);
                uploaded.set(requestBody);
                empty(exchange, 204);
            } else {
                capability(exchange, DESKTOP_CAPABILITY);
                bytes(exchange, 200, PAYLOAD);
            }
            return;
        }
        if (path.equals("/v1/tunnels/" + TUNNEL_ID + "/event-tickets") && method.equals("POST")) {
            capability(exchange, DESKTOP_CAPABILITY);
            json(exchange, 201, "{\"ticket\":\"" + EVENT_TICKET
                    + "\",\"expires_at\":\"2030-01-01T00:00:00Z\"}");
            return;
        }
        if (path.equals("/v1/tunnels/" + TUNNEL_ID) && method.equals("DELETE")) {
            capability(exchange, DESKTOP_CAPABILITY);
            empty(exchange, 204);
            return;
        }
        if (path.equals("/v1/tunnels/error")) {
            json(exchange, 401, "{\"code\":\"pairing_expired\",\"detail\":\"body-secret-must-never-escape\"}");
            return;
        }
        empty(exchange, 404);
    }

    private static void capability(HttpExchange exchange, String expected) {
        check(("Bearer " + expected).equals(exchange.getRequestHeaders().getFirst("Authorization")),
                "capability header");
        check(exchange.getRequestURI().getRawQuery() == null, "capability absent from URL");
    }

    private static void json(HttpExchange exchange, int status, String value) throws IOException {
        exchange.getResponseHeaders().set("Content-Type", "application/json");
        bytes(exchange, status, value.getBytes(StandardCharsets.UTF_8));
    }

    private static void empty(HttpExchange exchange, int status) throws IOException {
        exchange.sendResponseHeaders(status, -1);
        exchange.close();
    }

    private static void bytes(HttpExchange exchange, int status, byte[] value) throws IOException {
        exchange.sendResponseHeaders(status, value.length);
        exchange.getResponseBody().write(value);
        exchange.close();
    }

    private static void expectIllegal(CheckedRunnable operation, String message) {
        try {
            operation.run();
            throw new AssertionError(message);
        } catch (IllegalArgumentException expected) {
            // Expected.
        } catch (Exception exception) {
            throw new AssertionError(message, exception);
        }
    }

    private static void check(boolean condition, String message) {
        if (!condition) throw new AssertionError(message);
    }

    @FunctionalInterface
    private interface CheckedRunnable {
        void run() throws Exception;
    }
}
