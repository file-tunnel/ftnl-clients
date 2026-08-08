import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public enum FtnlClientError: Error {
    case invalidURL
    case http(status: Int, body: Data)
}

public struct FtnlClient: Sendable {
    public let baseURL: URL
    public let token: String?
    public let session: URLSession

    public init(baseURL: URL, token: String? = nil, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.token = token
        self.session = session
    }

    public func request(method: String, path: String, body: Data? = nil) async throws -> Data {
        guard let url = URL(string: path.trimmingCharacters(in: CharacterSet(charactersIn: "/")), relativeTo: baseURL.appendingPathComponent("/")) else {
            throw FtnlClientError.invalidURL
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.uppercased()
        request.timeoutInterval = 30
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty { request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization") }
        if let body {
            request.httpBody = body
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw FtnlClientError.http(status: (response as? HTTPURLResponse)?.statusCode ?? -1, body: data)
        }
        return data
    }

    public func health() async throws -> Data {
        try await request(method: "GET", path: "/health")
    }
}
