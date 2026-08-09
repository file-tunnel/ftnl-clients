package io.filetunnel.client;

import java.io.IOException;
import java.net.URI;
import java.net.http.HttpClient;
import java.net.http.HttpRequest;
import java.net.http.HttpResponse;
import java.time.Duration;

public final class FtnlClient {
    private final String baseUrl;
    private final String token;
    private final HttpClient httpClient;

    public FtnlClient(String baseUrl, String token) {
        this.baseUrl = baseUrl.replaceAll("/+$", "");
        this.token = token;
        this.httpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build();
    }

    public String request(String method, String path, String jsonBody) throws IOException, InterruptedException {
        HttpRequest.Builder builder = HttpRequest.newBuilder()
                .uri(URI.create(baseUrl + "/" + path.replaceFirst("^/+", "")))
                .timeout(Duration.ofSeconds(30))
                .header("Accept", "application/json");
        if (token != null && !token.isBlank()) { builder.header("Authorization", "Bearer " + token); }
        if (jsonBody == null) {
            builder.method(method.toUpperCase(), HttpRequest.BodyPublishers.noBody());
        } else {
            builder.header("Content-Type", "application/json");
            builder.method(method.toUpperCase(), HttpRequest.BodyPublishers.ofString(jsonBody));
        }
        HttpResponse<String> response = httpClient.send(builder.build(), HttpResponse.BodyHandlers.ofString());
        if (response.statusCode() < 200 || response.statusCode() >= 300) {
            throw new IOException("File Tunnel API returned HTTP " + response.statusCode() + ": " + response.body());
        }
        return response.body();
    }

    public String health() throws IOException, InterruptedException {
        return request("GET", "/health", null);
    }
}
