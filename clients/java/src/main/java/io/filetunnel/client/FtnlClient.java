package io.filetunnel.client;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URI;
import java.net.URLDecoder;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;
import java.time.Duration;
import java.time.Instant;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.Objects;

/** Android-compatible client for the File Tunnel v1 HTTP contract. */
public final class FtnlClient {
    private static final int MAX_ERROR_BYTES = 64 * 1024;
    private static final int MAX_JSON_BYTES = 1024 * 1024;

    private final URI baseUri;
    private final int timeoutMillis;

    public FtnlClient(String baseUrl) {
        this(URI.create(baseUrl), Duration.ofSeconds(30));
    }

    public FtnlClient(URI baseUri, Duration requestTimeout) {
        this.baseUri = checkedBaseUri(baseUri);
        Objects.requireNonNull(requestTimeout, "requestTimeout");
        long millis = requestTimeout.toMillis();
        if (millis <= 0 || millis > Integer.MAX_VALUE) {
            throw new IllegalArgumentException("requestTimeout must be between 1ms and 2147483647ms");
        }
        this.timeoutMillis = (int) millis;
    }

    public Tunnel createTunnel(
            String applicationId,
            List<String> accept,
            int maxFiles,
            long maxFileBytes,
            int expiresInSeconds) throws IOException {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("application_id", requireText(applicationId, "applicationId"));
        body.put("accept", List.copyOf(accept));
        body.put("max_files", maxFiles);
        body.put("max_file_bytes", maxFileBytes);
        body.put("expires_in_seconds", expiresInSeconds);
        return Tunnel.fromJson(json(send("POST", "/v1/tunnels", null, null, encodeJson(body))));
    }

    public Tunnel createTunnel(String applicationId) throws IOException {
        return createTunnel(applicationId, List.of("image/*"), 10, 50L * 1024L * 1024L, 600);
    }

    public Claim claimTunnel(String tunnelId, String pairingSecret, String deviceLabel) throws IOException {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("pairing_secret", requireText(pairingSecret, "pairingSecret"));
        if (deviceLabel != null && !deviceLabel.isBlank()) {
            body.put("device_label", deviceLabel);
        }
        return Claim.fromJson(json(send(
                "POST",
                "/v1/tunnels/" + segment(tunnelId) + "/claim",
                null,
                null,
                encodeJson(body))));
    }

    public TunnelSnapshot snapshot(String tunnelId, String capability) throws IOException {
        return TunnelSnapshot.fromJson(json(send(
                "GET", "/v1/tunnels/" + segment(tunnelId), capability, null, null)));
    }

    public FileDescriptor declareFile(
            String tunnelId,
            String capability,
            String name,
            String mediaType,
            long sizeBytes,
            Long lastModifiedMillis,
            String sha256,
            String idempotencyKey) throws IOException {
        Map<String, Object> body = new LinkedHashMap<>();
        body.put("name", requireText(name, "name"));
        body.put("media_type", requireText(mediaType, "mediaType"));
        body.put("size_bytes", sizeBytes);
        if (lastModifiedMillis != null) body.put("last_modified_ms", lastModifiedMillis);
        if (sha256 != null) body.put("sha256", sha256);
        return FileDescriptor.fromJson(json(send(
                "POST",
                "/v1/tunnels/" + segment(tunnelId) + "/files",
                capability,
                idempotencyKey,
                encodeJson(body))));
    }

    public FileDescriptor declareFile(
            String tunnelId, String capability, String name, String mediaType, long sizeBytes)
            throws IOException {
        return declareFile(tunnelId, capability, name, mediaType, sizeBytes, null, null, null);
    }

    public void upload(String tunnelId, String fileId, String capability, byte[] bytes) throws IOException {
        send(
                "PUT",
                "/v1/tunnels/" + segment(tunnelId) + "/files/" + segment(fileId) + "/content",
                capability,
                null,
                Objects.requireNonNull(bytes, "bytes"));
    }

    public byte[] download(String tunnelId, String fileId, String capability) throws IOException {
        return send(
                "GET",
                "/v1/tunnels/" + segment(tunnelId) + "/files/" + segment(fileId) + "/content",
                capability,
                null,
                null);
    }

    public void cancel(String tunnelId, String capability) throws IOException {
        send("DELETE", "/v1/tunnels/" + segment(tunnelId), capability, null, null);
    }

    public URI eventSocketUri(String tunnelId, String capability) throws IOException {
        Map<String, Object> ticket = json(send(
                "POST",
                "/v1/tunnels/" + segment(tunnelId) + "/event-tickets",
                capability,
                null,
                null));
        String value = text(ticket, "ticket");
        String scheme = baseUri.getScheme().equals("https") ? "wss" : "ws";
        try {
            URI socketBase = new URI(
                    scheme,
                    null,
                    baseUri.getHost(),
                    baseUri.getPort(),
                    "/v1/tunnels/" + segment(tunnelId) + "/events",
                    null,
                    null);
            return URI.create(socketBase.toASCIIString()
                    + "?ticket=" + URLEncoder.encode(value, StandardCharsets.UTF_8));
        } catch (Exception exception) {
            throw new IOException("could not construct event socket URI", exception);
        }
    }

    /** Extracts the pairing secret only from the URI fragment; query credentials are rejected. */
    public static String pairingSecretFromUri(URI uri) {
        Objects.requireNonNull(uri, "uri");
        if (uri.getRawQuery() != null && queryValue(uri.getRawQuery(), "c") != null) {
            return null;
        }
        return queryValue(uri.getRawFragment(), "c");
    }

    private byte[] send(
            String method,
            String path,
            String capability,
            String idempotencyKey,
            byte[] body) throws IOException {
        HttpURLConnection connection = (HttpURLConnection) baseUri.resolve(path).toURL().openConnection();
        connection.setInstanceFollowRedirects(false);
        connection.setConnectTimeout(timeoutMillis);
        connection.setReadTimeout(timeoutMillis);
        connection.setRequestMethod(method);
        connection.setRequestProperty("Accept", "application/json, application/octet-stream");
        if (capability != null) {
            connection.setRequestProperty("Authorization", "Bearer " + requireText(capability, "capability"));
        }
        if (idempotencyKey != null) {
            connection.setRequestProperty("Idempotency-Key", requireText(idempotencyKey, "idempotencyKey"));
        }
        if (body != null) {
            connection.setDoOutput(true);
            connection.setFixedLengthStreamingMode(body.length);
            connection.setRequestProperty(
                    "Content-Type",
                    method.equals("PUT") ? "application/octet-stream" : "application/json");
            try (OutputStream output = connection.getOutputStream()) {
                output.write(body);
            }
        }

        int status = connection.getResponseCode();
        if (status >= 200 && status < 300) {
            try (InputStream input = connection.getInputStream()) {
                return readAll(input, -1);
            } finally {
                connection.disconnect();
            }
        }

        String code = "request_failed";
        try (InputStream error = connection.getErrorStream()) {
            if (error != null) {
                byte[] bytes = readAll(error, MAX_ERROR_BYTES);
                try {
                    Object parsed = Json.parse(new String(bytes, StandardCharsets.UTF_8));
                    if (parsed instanceof Map<?, ?> map && map.get("code") instanceof String value) {
                        code = value;
                    }
                } catch (IllegalArgumentException ignored) {
                    // Never include an arbitrary error body: it may contain capabilities or file data.
                }
            }
        } finally {
            connection.disconnect();
        }
        throw new FileTunnelException(status, code);
    }

    private static URI checkedBaseUri(URI uri) {
        Objects.requireNonNull(uri, "baseUri");
        String scheme = uri.getScheme();
        if (!("https".equals(scheme) || "http".equals(scheme))
                || uri.getHost() == null
                || uri.getUserInfo() != null
                || uri.getRawQuery() != null
                || uri.getRawFragment() != null) {
            throw new IllegalArgumentException("baseUri must be an absolute HTTP(S) URI without credentials, query, or fragment");
        }
        if ("http".equals(scheme) && !internalHostAllowed(uri.getHost())) {
            throw new IllegalArgumentException("cleartext HTTP is allowed only for loopback or internal hosts");
        }
        return uri.resolve("/");
    }

    private static boolean internalHostAllowed(String host) {
        String lower = host.toLowerCase();
        if (lower.startsWith("[") && lower.endsWith("]")) {
            lower = lower.substring(1, lower.length() - 1);
        }
        if (lower.equals("localhost") || lower.endsWith(".localhost")
                || (!lower.contains(".") && !lower.contains(":")) || lower.endsWith(".internal")
                || lower.endsWith(".svc.cluster.local")) {
            return true;
        }
        if (lower.contains(":")) {
            return lower.equals("::1") || lower.equals("::") || lower.startsWith("fc")
                    || lower.startsWith("fd") || lower.startsWith("fe8") || lower.startsWith("fe9")
                    || lower.startsWith("fea") || lower.startsWith("feb");
        }
        String[] octets = lower.split("\\.", -1);
        if (octets.length != 4) {
            return false;
        }
        int[] values = new int[4];
        try {
            for (int index = 0; index < octets.length; index++) {
                values[index] = Integer.parseInt(octets[index]);
                if (values[index] < 0 || values[index] > 255) return false;
            }
        } catch (NumberFormatException ignored) {
            return false;
        }
        return values[0] == 127 || values[0] == 10 || values[0] == 0
                || (values[0] == 172 && values[1] >= 16 && values[1] <= 31)
                || (values[0] == 192 && values[1] == 168)
                || (values[0] == 169 && values[1] == 254);
    }

    private static String segment(String value) {
        String text = requireText(value, "path segment");
        if (!text.matches("[A-Za-z0-9._~-]+")) {
            throw new IllegalArgumentException("invalid path segment");
        }
        return text;
    }

    private static String requireText(String value, String name) {
        if (value == null || value.isBlank()) throw new IllegalArgumentException(name + " must not be blank");
        return value;
    }

    private static byte[] readAll(InputStream input, int limit) throws IOException {
        ByteArrayOutputStream output = new ByteArrayOutputStream();
        byte[] buffer = new byte[8192];
        int total = 0;
        while (limit < 0 || total < limit) {
            int count = input.read(buffer, 0, limit < 0 ? buffer.length : Math.min(buffer.length, limit - total));
            if (count < 0) break;
            output.write(buffer, 0, count);
            total += count;
        }
        return output.toByteArray();
    }

    private static byte[] encodeJson(Map<String, Object> value) {
        return Json.stringify(value).getBytes(StandardCharsets.UTF_8);
    }

    @SuppressWarnings("unchecked")
    private static Map<String, Object> json(byte[] bytes) {
        if (bytes.length > MAX_JSON_BYTES) throw new IllegalArgumentException("JSON response exceeded safe limit");
        Object value = Json.parse(new String(bytes, StandardCharsets.UTF_8));
        if (!(value instanceof Map<?, ?>)) throw new IllegalArgumentException("expected a JSON object");
        return (Map<String, Object>) value;
    }

    private static String text(Map<String, Object> value, String key) {
        Object result = value.get(key);
        if (!(result instanceof String string)) throw new IllegalArgumentException("missing JSON string: " + key);
        return string;
    }

    private static long integer(Map<String, Object> value, String key) {
        Object result = value.get(key);
        if (!(result instanceof Number number)) throw new IllegalArgumentException("missing JSON integer: " + key);
        return number.longValue();
    }

    private static String queryValue(String rawQuery, String name) {
        if (rawQuery == null || rawQuery.isEmpty()) return null;
        for (String pair : rawQuery.split("&")) {
            String[] pieces = pair.split("=", 2);
            if (decode(pieces[0]).equals(name)) return pieces.length == 2 ? decode(pieces[1]) : "";
        }
        return null;
    }

    private static String decode(String value) {
        return URLDecoder.decode(value, StandardCharsets.UTF_8);
    }

    public record Tunnel(
            String apiVersion,
            String tunnelId,
            String status,
            URI pairingUri,
            String desktopCapability,
            Instant expiresAt) {
        static Tunnel fromJson(Map<String, Object> value) {
            return new Tunnel(
                    text(value, "api_version"),
                    text(value, "tunnel_id"),
                    text(value, "status"),
                    URI.create(text(value, "pairing_uri")),
                    text(value, "desktop_capability"),
                    Instant.parse(text(value, "expires_at")));
        }

        @Override
        public String toString() {
            return "Tunnel[apiVersion=" + apiVersion + ", tunnelId=" + tunnelId
                    + ", status=" + status + ", expiresAt=" + expiresAt + "]";
        }
    }

    public record Claim(String phoneCapability, Instant expiresAt) {
        static Claim fromJson(Map<String, Object> value) {
            return new Claim(text(value, "phone_capability"), Instant.parse(text(value, "expires_at")));
        }

        @Override
        public String toString() {
            return "Claim[expiresAt=" + expiresAt + "]";
        }
    }

    public record FileDescriptor(
            String fileId,
            String name,
            String mediaType,
            long sizeBytes,
            long bytesTransferred,
            String status,
            Instant createdAt) {
        static FileDescriptor fromJson(Map<String, Object> value) {
            return new FileDescriptor(
                    text(value, "file_id"),
                    text(value, "name"),
                    text(value, "media_type"),
                    integer(value, "size_bytes"),
                    integer(value, "bytes_transferred"),
                    text(value, "status"),
                    Instant.parse(text(value, "created_at")));
        }
    }

    public record TunnelSnapshot(String tunnelId, String status, Instant expiresAt, List<FileDescriptor> files) {
        static TunnelSnapshot fromJson(Map<String, Object> value) {
            Object rawFiles = value.get("files");
            if (!(rawFiles instanceof List<?> list)) throw new IllegalArgumentException("missing JSON array: files");
            List<FileDescriptor> files = new ArrayList<>();
            for (Object item : list) {
                if (!(item instanceof Map<?, ?> raw)) throw new IllegalArgumentException("invalid file descriptor");
                @SuppressWarnings("unchecked")
                Map<String, Object> file = (Map<String, Object>) raw;
                files.add(FileDescriptor.fromJson(file));
            }
            return new TunnelSnapshot(
                    text(value, "tunnel_id"),
                    text(value, "status"),
                    Instant.parse(text(value, "expires_at")),
                    List.copyOf(files));
        }
    }

    public static final class FileTunnelException extends IOException {
        private final int status;
        private final String code;

        public FileTunnelException(int status, String code) {
            super("File Tunnel request failed (HTTP " + status + ", code " + code + ")");
            this.status = status;
            this.code = code;
        }

        public int status() { return status; }
        public String code() { return code; }
    }

    private static final class Json {
        private final String source;
        private int offset;

        private Json(String source) { this.source = source; }

        static Object parse(String source) {
            Json parser = new Json(source);
            Object value = parser.value();
            parser.space();
            if (parser.offset != source.length()) throw parser.invalid();
            return value;
        }

        static String stringify(Object value) {
            if (value == null) return "null";
            if (value instanceof String string) return quote(string);
            if (value instanceof Number || value instanceof Boolean) return value.toString();
            if (value instanceof List<?> list) {
                List<String> items = new ArrayList<>();
                for (Object item : list) items.add(stringify(item));
                return "[" + String.join(",", items) + "]";
            }
            if (value instanceof Map<?, ?> map) {
                List<String> entries = new ArrayList<>();
                for (Map.Entry<?, ?> entry : map.entrySet()) {
                    entries.add(quote(String.valueOf(entry.getKey())) + ":" + stringify(entry.getValue()));
                }
                return "{" + String.join(",", entries) + "}";
            }
            throw new IllegalArgumentException("unsupported JSON value");
        }

        private Object value() {
            space();
            if (offset >= source.length()) throw invalid();
            char current = source.charAt(offset);
            if (current == '{') return object();
            if (current == '[') return array();
            if (current == '\"') return string();
            if (current == 't') return literal("true", true);
            if (current == 'f') return literal("false", false);
            if (current == 'n') return literal("null", null);
            return number();
        }

        private Map<String, Object> object() {
            offset++;
            Map<String, Object> result = new LinkedHashMap<>();
            space();
            if (take('}')) return result;
            do {
                space();
                if (offset >= source.length() || source.charAt(offset) != '\"') throw invalid();
                String key = string();
                space();
                if (!take(':')) throw invalid();
                result.put(key, value());
                space();
            } while (take(','));
            if (!take('}')) throw invalid();
            return result;
        }

        private List<Object> array() {
            offset++;
            List<Object> result = new ArrayList<>();
            space();
            if (take(']')) return result;
            do {
                result.add(value());
                space();
            } while (take(','));
            if (!take(']')) throw invalid();
            return result;
        }

        private String string() {
            offset++;
            StringBuilder result = new StringBuilder();
            while (offset < source.length()) {
                char current = source.charAt(offset++);
                if (current == '\"') return result.toString();
                if (current == '\\') {
                    if (offset >= source.length()) throw invalid();
                    char escaped = source.charAt(offset++);
                    switch (escaped) {
                        case '\"', '\\', '/' -> result.append(escaped);
                        case 'b' -> result.append('\b');
                        case 'f' -> result.append('\f');
                        case 'n' -> result.append('\n');
                        case 'r' -> result.append('\r');
                        case 't' -> result.append('\t');
                        case 'u' -> {
                            if (offset + 4 > source.length()) throw invalid();
                            result.append((char) Integer.parseInt(source.substring(offset, offset + 4), 16));
                            offset += 4;
                        }
                        default -> throw invalid();
                    }
                } else {
                    result.append(current);
                }
            }
            throw invalid();
        }

        private Number number() {
            int start = offset;
            while (offset < source.length() && "-+0123456789.eE".indexOf(source.charAt(offset)) >= 0) offset++;
            try {
                String value = source.substring(start, offset);
                return value.contains(".") || value.contains("e") || value.contains("E")
                        ? Double.parseDouble(value)
                        : Long.parseLong(value);
            } catch (NumberFormatException exception) {
                throw invalid();
            }
        }

        private Object literal(String token, Object value) {
            if (!source.startsWith(token, offset)) throw invalid();
            offset += token.length();
            return value;
        }

        private boolean take(char expected) {
            if (offset < source.length() && source.charAt(offset) == expected) {
                offset++;
                return true;
            }
            return false;
        }

        private void space() {
            while (offset < source.length() && Character.isWhitespace(source.charAt(offset))) offset++;
        }

        private IllegalArgumentException invalid() {
            return new IllegalArgumentException("invalid JSON response");
        }

        private static String quote(String value) {
            StringBuilder result = new StringBuilder("\"");
            for (int index = 0; index < value.length(); index++) {
                char current = value.charAt(index);
                switch (current) {
                    case '\"' -> result.append("\\\"");
                    case '\\' -> result.append("\\\\");
                    case '\b' -> result.append("\\b");
                    case '\f' -> result.append("\\f");
                    case '\n' -> result.append("\\n");
                    case '\r' -> result.append("\\r");
                    case '\t' -> result.append("\\t");
                    default -> {
                        if (current < 0x20) result.append(String.format("\\u%04x", (int) current));
                        else result.append(current);
                    }
                }
            }
            return result.append('\"').toString();
        }
    }
}
