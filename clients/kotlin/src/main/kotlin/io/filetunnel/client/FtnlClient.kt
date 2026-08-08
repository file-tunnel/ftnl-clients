package io.filetunnel.client

import java.net.URI
import java.net.http.HttpClient
import java.net.http.HttpRequest
import java.net.http.HttpResponse
import java.time.Duration

class FtnlClient(
    baseUrl: String,
    private val token: String? = null,
    private val httpClient: HttpClient = HttpClient.newBuilder().connectTimeout(Duration.ofSeconds(10)).build(),
) {
    private val baseUrl = baseUrl.trimEnd('/')

    fun request(method: String, path: String, jsonBody: String? = null): String {
        val builder = HttpRequest.newBuilder()
            .uri(URI.create("$baseUrl/${path.trimStart('/')}"))
            .timeout(Duration.ofSeconds(30))
            .header("Accept", "application/json")
        token?.takeIf { it.isNotBlank() }?.let { builder.header("Authorization", "Bearer $it") }
        if (jsonBody == null) {
            builder.method(method.uppercase(), HttpRequest.BodyPublishers.noBody())
        } else {
            builder.header("Content-Type", "application/json")
            builder.method(method.uppercase(), HttpRequest.BodyPublishers.ofString(jsonBody))
        }
        val response = httpClient.send(builder.build(), HttpResponse.BodyHandlers.ofString())
        check(response.statusCode() in 200..299) { "File Tunnel API returned HTTP ${response.statusCode()}: ${response.body()}" }
        return response.body()
    }

    fun health(): String = request("GET", "/health")
}
