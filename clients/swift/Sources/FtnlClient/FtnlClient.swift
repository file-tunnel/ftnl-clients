import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FtnlClientError: Error, Equatable, CustomStringConvertible {
    case invalidBaseURL
    case invalidRequest
    case invalidResponse
    case invalidPayload
    case http(status: Int, code: String)

    public var description: String {
        switch self {
        case .invalidBaseURL: return "File Tunnel base URL is invalid or insecure"
        case .invalidRequest: return "File Tunnel request is invalid"
        case .invalidResponse: return "File Tunnel returned a non-HTTP response"
        case .invalidPayload: return "File Tunnel returned an invalid payload"
        case let .http(status, code): return "File Tunnel request failed (HTTP \(status), code \(code))"
        }
    }
}

public struct Tunnel: Codable, Sendable, CustomStringConvertible {
    public let apiVersion: String
    public let tunnelId: String
    public let status: String
    public let pairingUri: URL
    public let desktopCapability: String
    public let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case apiVersion = "api_version"
        case tunnelId = "tunnel_id"
        case status
        case pairingUri = "pairing_uri"
        case desktopCapability = "desktop_capability"
        case expiresAt = "expires_at"
    }

    public var description: String {
        "Tunnel(apiVersion: \(apiVersion), tunnelId: \(tunnelId), status: \(status), expiresAt: \(expiresAt))"
    }
}

public struct Claim: Codable, Sendable, CustomStringConvertible {
    public let phoneCapability: String
    public let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case phoneCapability = "phone_capability"
        case expiresAt = "expires_at"
    }

    public var description: String { "Claim(expiresAt: \(expiresAt))" }
}

public struct FileDescriptor: Codable, Sendable, Equatable {
    public let fileId: String
    public let name: String
    public let mediaType: String
    public let sizeBytes: Int64
    public let bytesTransferred: Int64
    public let status: String
    public let createdAt: Date

    enum CodingKeys: String, CodingKey {
        case fileId = "file_id"
        case name
        case mediaType = "media_type"
        case sizeBytes = "size_bytes"
        case bytesTransferred = "bytes_transferred"
        case status
        case createdAt = "created_at"
    }
}

public struct TunnelSnapshot: Codable, Sendable, Equatable {
    public let tunnelId: String
    public let status: String
    public let expiresAt: Date
    public let files: [FileDescriptor]

    enum CodingKeys: String, CodingKey {
        case tunnelId = "tunnel_id"
        case status
        case expiresAt = "expires_at"
        case files
    }
}

private struct CreateTunnelRequest: Encodable {
    let applicationId: String
    let accept: [String]
    let maxFiles: Int
    let maxFileBytes: Int64
    let expiresInSeconds: Int

    enum CodingKeys: String, CodingKey {
        case applicationId = "application_id"
        case accept
        case maxFiles = "max_files"
        case maxFileBytes = "max_file_bytes"
        case expiresInSeconds = "expires_in_seconds"
    }
}

private struct ClaimTunnelRequest: Encodable {
    let pairingSecret: String
    let deviceLabel: String?

    enum CodingKeys: String, CodingKey {
        case pairingSecret = "pairing_secret"
        case deviceLabel = "device_label"
    }
}

private struct DeclareFileRequest: Encodable {
    let name: String
    let mediaType: String
    let sizeBytes: Int64
    let lastModifiedMillis: Int64?
    let sha256: String?

    enum CodingKeys: String, CodingKey {
        case name
        case mediaType = "media_type"
        case sizeBytes = "size_bytes"
        case lastModifiedMillis = "last_modified_ms"
        case sha256
    }
}

private struct EventTicket: Decodable {
    let ticket: String
    let expiresAt: Date

    enum CodingKeys: String, CodingKey {
        case ticket
        case expiresAt = "expires_at"
    }
}

private struct Problem: Decodable {
    let code: String?
}

final class NoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        completionHandler(nil)
    }
}

public struct FtnlClient: @unchecked Sendable {
    public let baseURL: URL
    public let session: URLSession
    public let requestTimeout: TimeInterval

    public init(baseURL: URL, requestTimeout: TimeInterval = 30, session: URLSession? = nil) throws {
        guard requestTimeout > 0, requestTimeout.isFinite, Self.isAllowed(baseURL) else {
            throw FtnlClientError.invalidBaseURL
        }
        self.baseURL = baseURL
        self.requestTimeout = requestTimeout
        if let session {
            self.session = session
        } else {
            let configuration = URLSessionConfiguration.ephemeral
            configuration.timeoutIntervalForRequest = requestTimeout
            configuration.timeoutIntervalForResource = requestTimeout
            configuration.httpShouldSetCookies = false
            configuration.httpCookieStorage = nil
            configuration.urlCredentialStorage = nil
            self.session = URLSession(
                configuration: configuration,
                delegate: NoRedirectDelegate(),
                delegateQueue: nil
            )
        }
    }

    public func createTunnel(
        applicationId: String,
        accept: [String] = ["image/*"],
        maxFiles: Int = 10,
        maxFileBytes: Int64 = 50 * 1024 * 1024,
        expiresInSeconds: Int = 600
    ) async throws -> Tunnel {
        try await send(
            method: "POST",
            path: "/v1/tunnels",
            json: CreateTunnelRequest(
                applicationId: applicationId,
                accept: accept,
                maxFiles: maxFiles,
                maxFileBytes: maxFileBytes,
                expiresInSeconds: expiresInSeconds
            ),
            as: Tunnel.self
        )
    }

    public func claimTunnel(
        tunnelId: String,
        pairingSecret: String,
        deviceLabel: String? = nil
    ) async throws -> Claim {
        try await send(
            method: "POST",
            path: "/v1/tunnels/\(try Self.segment(tunnelId))/claim",
            json: ClaimTunnelRequest(pairingSecret: pairingSecret, deviceLabel: deviceLabel),
            as: Claim.self
        )
    }

    public func snapshot(tunnelId: String, capability: String) async throws -> TunnelSnapshot {
        try await send(
            method: "GET",
            path: "/v1/tunnels/\(try Self.segment(tunnelId))",
            capability: capability,
            as: TunnelSnapshot.self
        )
    }

    public func declareFile(
        tunnelId: String,
        capability: String,
        name: String,
        mediaType: String,
        sizeBytes: Int64,
        lastModifiedMillis: Int64? = nil,
        sha256: String? = nil,
        idempotencyKey: String? = nil
    ) async throws -> FileDescriptor {
        try await send(
            method: "POST",
            path: "/v1/tunnels/\(try Self.segment(tunnelId))/files",
            capability: capability,
            idempotencyKey: idempotencyKey,
            json: DeclareFileRequest(
                name: name,
                mediaType: mediaType,
                sizeBytes: sizeBytes,
                lastModifiedMillis: lastModifiedMillis,
                sha256: sha256
            ),
            as: FileDescriptor.self
        )
    }

    public func upload(tunnelId: String, fileId: String, capability: String, data: Data) async throws {
        _ = try await sendData(
            method: "PUT",
            path: "/v1/tunnels/\(try Self.segment(tunnelId))/files/\(try Self.segment(fileId))/content",
            capability: capability,
            contentType: "application/octet-stream",
            body: data
        )
    }

    public func download(tunnelId: String, fileId: String, capability: String) async throws -> Data {
        try await sendData(
            method: "GET",
            path: "/v1/tunnels/\(try Self.segment(tunnelId))/files/\(try Self.segment(fileId))/content",
            capability: capability
        )
    }

    public func cancel(tunnelId: String, capability: String) async throws {
        _ = try await sendData(
            method: "DELETE",
            path: "/v1/tunnels/\(try Self.segment(tunnelId))",
            capability: capability
        )
    }

    public func eventSocketURL(tunnelId: String, capability: String) async throws -> URL {
        let ticket: EventTicket = try await send(
            method: "POST",
            path: "/v1/tunnels/\(try Self.segment(tunnelId))/event-tickets",
            capability: capability,
            as: EventTicket.self
        )
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw FtnlClientError.invalidRequest
        }
        components.scheme = components.scheme == "https" ? "wss" : "ws"
        components.path = "/v1/tunnels/\(try Self.segment(tunnelId))/events"
        components.queryItems = [URLQueryItem(name: "ticket", value: ticket.ticket)]
        guard let url = components.url else { throw FtnlClientError.invalidRequest }
        return url
    }

    public static func pairingSecret(from uri: URL) -> String? {
        guard let components = URLComponents(url: uri, resolvingAgainstBaseURL: false),
              components.queryItems?.contains(where: { $0.name == "c" }) != true,
              let fragment = components.fragment,
              let fragmentComponents = URLComponents(string: "?\(fragment)") else {
            return nil
        }
        return fragmentComponents.queryItems?.first(where: { $0.name == "c" })?.value
    }

    private func send<Request: Encodable, Response: Decodable>(
        method: String,
        path: String,
        capability: String? = nil,
        idempotencyKey: String? = nil,
        json request: Request,
        as response: Response.Type
    ) async throws -> Response {
        let body: Data
        do {
            body = try JSONEncoder().encode(request)
        } catch {
            throw FtnlClientError.invalidRequest
        }
        let data = try await sendData(
            method: method,
            path: path,
            capability: capability,
            idempotencyKey: idempotencyKey,
            contentType: "application/json",
            body: body
        )
        return try decode(data, as: response)
    }

    private func send<Response: Decodable>(
        method: String,
        path: String,
        capability: String? = nil,
        as response: Response.Type
    ) async throws -> Response {
        try decode(
            await sendData(method: method, path: path, capability: capability),
            as: response
        )
    }

    private func decode<Response: Decodable>(_ data: Data, as response: Response.Type) throws -> Response {
        guard data.count <= 1024 * 1024 else { throw FtnlClientError.invalidPayload }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        do {
            return try decoder.decode(response, from: data)
        } catch {
            throw FtnlClientError.invalidPayload
        }
    }

    private func sendData(
        method: String,
        path: String,
        capability: String? = nil,
        idempotencyKey: String? = nil,
        contentType: String? = nil,
        body: Data? = nil
    ) async throws -> Data {
        guard var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw FtnlClientError.invalidRequest
        }
        components.path = path
        components.query = nil
        components.fragment = nil
        guard let url = components.url else { throw FtnlClientError.invalidRequest }
        var request = URLRequest(url: url)
        request.httpMethod = method
        request.timeoutInterval = requestTimeout
        request.httpBody = body
        request.setValue("application/json, application/octet-stream", forHTTPHeaderField: "Accept")
        if let capability {
            guard !capability.isEmpty else { throw FtnlClientError.invalidRequest }
            request.setValue("Bearer \(capability)", forHTTPHeaderField: "Authorization")
        }
        if let idempotencyKey {
            guard !idempotencyKey.isEmpty else { throw FtnlClientError.invalidRequest }
            request.setValue(idempotencyKey, forHTTPHeaderField: "Idempotency-Key")
        }
        if let contentType { request.setValue(contentType, forHTTPHeaderField: "Content-Type") }

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else { throw FtnlClientError.invalidResponse }
        guard (200...299).contains(http.statusCode) else {
            var code = "request_failed"
            if data.count <= 64 * 1024,
               let problem = try? JSONDecoder().decode(Problem.self, from: data),
               let problemCode = problem.code {
                code = problemCode
            }
            throw FtnlClientError.http(status: http.statusCode, code: code)
        }
        return data
    }

    private static func segment(_ value: String) throws -> String {
        guard !value.isEmpty,
              value.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._~-")
                      .contains($0)
              }) else {
            throw FtnlClientError.invalidRequest
        }
        return value
    }

    private static func isAllowed(_ url: URL) -> Bool {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false),
              let scheme = components.scheme?.lowercased(),
              let host = components.host?.lowercased(),
              components.user == nil,
              components.password == nil,
              components.query == nil,
              components.fragment == nil,
              scheme == "https" || scheme == "http" else {
            return false
        }
        return scheme == "https" || internalHostAllowed(host)
    }

    private static func internalHostAllowed(_ host: String) -> Bool {
        let normalized = host.trimmingCharacters(in: CharacterSet(charactersIn: "[]")).lowercased()
        if normalized == "localhost" || normalized.hasSuffix(".localhost")
            || (!normalized.contains(".") && !normalized.contains(":"))
            || normalized.hasSuffix(".internal") || normalized.hasSuffix(".svc.cluster.local") {
            return true
        }
        let octets = normalized.split(separator: ".").compactMap { Int($0) }
        guard octets.count == 4, octets.allSatisfy({ (0...255).contains($0) }) else {
            return normalized == "::1" || normalized == "::" || normalized.hasPrefix("fc")
                || normalized.hasPrefix("fd") || normalized.hasPrefix("fe8")
                || normalized.hasPrefix("fe9") || normalized.hasPrefix("fea")
                || normalized.hasPrefix("feb")
        }
        return octets[0] == 127 || octets[0] == 10 || octets[0] == 0
            || (octets[0] == 172 && (16...31).contains(octets[1]))
            || (octets[0] == 192 && octets[1] == 168)
            || (octets[0] == 169 && octets[1] == 254)
    }
}
