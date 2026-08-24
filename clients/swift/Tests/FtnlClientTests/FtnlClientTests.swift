import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import XCTest
@testable import FtnlClient

final class FtnlClientTests: XCTestCase {
    private let tunnelId = "8be939aa-686e-41c4-a7e1-d4152150a8ad"
    private let fileId = "e156358a-8382-4ad8-91f3-7d9becd8b69d"
    private let pairingSecret = "pairing-secret-000000000000000000"
    private let desktopCapability = "desktop-capability-00000000000000"
    private let phoneCapability = "phone-capability-0000000000000000"
    private let eventTicket = "event-ticket-000000000000000000000"

    override func tearDown() {
        MockURLProtocol.handler = nil
        super.tearDown()
    }

    func testFullTransferContractAndCredentialPlacement() async throws {
        let payload = Data([0, 1, 2, 3, 255])
        var uploaded: Data?
        MockURLProtocol.handler = { [self] request in
            let path = request.url?.path
            switch (request.httpMethod, path) {
            case ("POST", "/v1/tunnels"):
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                let body = try XCTUnwrap(request.httpBody)
                XCTAssertTrue(String(decoding: body, as: UTF8.self).contains("\"application_id\":\"swift-conformance\""))
                return .json(201, """
                    {"api_version":"v1","tunnel_id":"\(tunnelId)","status":"waiting",\
                    "pairing_uri":"https://file-tunnel.dev/pair/\(tunnelId)#c=\(pairingSecret)",\
                    "desktop_capability":"\(desktopCapability)","expires_at":"2030-01-01T00:00:00Z"}
                    """)
            case ("POST", "/v1/tunnels/\(tunnelId)/claim"):
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                XCTAssertTrue(String(decoding: try XCTUnwrap(request.httpBody), as: UTF8.self).contains(pairingSecret))
                return .json(200, """
                    {"phone_capability":"\(phoneCapability)","expires_at":"2030-01-01T00:00:00Z"}
                    """)
            case ("GET", "/v1/tunnels/\(tunnelId)"):
                checkCapability(request, desktopCapability)
                return .json(200, """
                    {"tunnel_id":"\(tunnelId)","status":"connected",\
                    "expires_at":"2030-01-01T00:00:00Z","files":[]}
                    """)
            case ("POST", "/v1/tunnels/\(tunnelId)/files"):
                checkCapability(request, phoneCapability)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), "swift-test-request")
                return .json(201, """
                    {"file_id":"\(fileId)","name":"photo.jpg","media_type":"image/jpeg",\
                    "size_bytes":5,"bytes_transferred":0,"status":"declared",\
                    "created_at":"2030-01-01T00:00:00Z"}
                    """)
            case ("PUT", "/v1/tunnels/\(tunnelId)/files/\(fileId)/content"):
                checkCapability(request, phoneCapability)
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")
                uploaded = request.httpBody
                return .empty(204)
            case ("GET", "/v1/tunnels/\(tunnelId)/files/\(fileId)/content"):
                checkCapability(request, desktopCapability)
                return .bytes(200, payload)
            case ("POST", "/v1/tunnels/\(tunnelId)/event-tickets"):
                checkCapability(request, desktopCapability)
                return .json(201, """
                    {"ticket":"\(eventTicket)","expires_at":"2030-01-01T00:00:00Z"}
                    """)
            case ("DELETE", "/v1/tunnels/\(tunnelId)"):
                checkCapability(request, desktopCapability)
                return .empty(204)
            default:
                XCTFail("unexpected request: \(request.httpMethod ?? "nil") \(path ?? "nil")")
                return .empty(404)
            }
        }

        let client = try testClient()
        let tunnel = try await client.createTunnel(
            applicationId: "swift-conformance",
            accept: ["image/*"],
            maxFiles: 2,
            maxFileBytes: 1024,
            expiresInSeconds: 120
        )
        XCTAssertEqual(tunnel.tunnelId, tunnelId)
        XCTAssertEqual(FtnlClient.pairingSecret(from: tunnel.pairingUri), pairingSecret)
        XCTAssertFalse(tunnel.description.contains(pairingSecret))
        XCTAssertFalse(tunnel.description.contains(desktopCapability))
        XCTAssertNil(FtnlClient.pairingSecret(
            from: URL(string: "https://file-tunnel.dev/pair/\(tunnelId)?c=\(pairingSecret)")!
        ))

        let claim = try await client.claimTunnel(
            tunnelId: tunnelId,
            pairingSecret: pairingSecret,
            deviceLabel: "ios-example"
        )
        XCTAssertEqual(claim.phoneCapability, phoneCapability)
        XCTAssertFalse(claim.description.contains(phoneCapability))
        XCTAssertTrue(try await client.snapshot(tunnelId: tunnelId, capability: desktopCapability).files.isEmpty)

        let file = try await client.declareFile(
            tunnelId: tunnelId,
            capability: phoneCapability,
            name: "photo.jpg",
            mediaType: "image/jpeg",
            sizeBytes: Int64(payload.count),
            lastModifiedMillis: 123,
            sha256: String(repeating: "a", count: 64),
            idempotencyKey: "swift-test-request"
        )
        XCTAssertEqual(file.fileId, fileId)
        try await client.upload(tunnelId: tunnelId, fileId: fileId, capability: phoneCapability, data: payload)
        XCTAssertEqual(uploaded, payload)
        XCTAssertEqual(
            try await client.download(tunnelId: tunnelId, fileId: fileId, capability: desktopCapability),
            payload
        )

        let eventURL = try await client.eventSocketURL(tunnelId: tunnelId, capability: desktopCapability)
        XCTAssertEqual(eventURL.scheme, "wss")
        XCTAssertEqual(URLComponents(url: eventURL, resolvingAgainstBaseURL: false)?.queryItems?.first?.value, eventTicket)
        try await client.cancel(tunnelId: tunnelId, capability: desktopCapability)
    }

    func testErrorsDoNotExposeResponseBodiesOrCapabilities() async throws {
        let bodySecret = "body-secret-must-never-escape"
        MockURLProtocol.handler = { _ in
            .json(401, "{\"code\":\"pairing_expired\",\"detail\":\"\(bodySecret)\"}")
        }
        let client = try testClient()
        do {
            _ = try await client.snapshot(tunnelId: "error", capability: desktopCapability)
            XCTFail("expected an API error")
        } catch let error as FtnlClientError {
            XCTAssertEqual(error, .http(status: 401, code: "pairing_expired"))
            XCTAssertFalse(error.description.contains(bodySecret))
            XCTAssertFalse(error.description.contains(desktopCapability))
        }
    }

    func testBaseURLAndRedirectPolicy() throws {
        XCTAssertNoThrow(try FtnlClient(baseURL: URL(string: "http://[::1]:8080")!))
        XCTAssertThrowsError(try FtnlClient(baseURL: URL(string: "http://example.com")!))
        XCTAssertThrowsError(try FtnlClient(baseURL: URL(string: "http://[2001:4860:4860::8888]")!))
        XCTAssertThrowsError(try FtnlClient(baseURL: URL(string: "ftp://localhost")!))
        XCTAssertThrowsError(try FtnlClient(baseURL: URL(string: "https://user:secret@example.com")!))
        XCTAssertThrowsError(try FtnlClient(baseURL: URL(string: "https://example.com")!, requestTimeout: 0))

        let delegate = NoRedirectDelegate()
        let session = URLSession(configuration: .ephemeral)
        let task = session.dataTask(with: URL(string: "https://example.com/start")!)
        let response = try XCTUnwrap(HTTPURLResponse(
            url: URL(string: "https://example.com/start")!,
            statusCode: 302,
            httpVersion: nil,
            headerFields: ["Location": "https://example.com/end"]
        ))
        var redirected: URLRequest? = URLRequest(url: URL(string: "https://example.com/end")!)
        delegate.urlSession(
            session,
            task: task,
            willPerformHTTPRedirection: response,
            newRequest: redirected!,
            completionHandler: { redirected = $0 }
        )
        XCTAssertNil(redirected)
    }

    private func testClient() throws -> FtnlClient {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MockURLProtocol.self]
        return try FtnlClient(
            baseURL: URL(string: "https://api.file-tunnel.dev")!,
            requestTimeout: 5,
            session: URLSession(configuration: configuration)
        )
    }

    private func checkCapability(_ request: URLRequest, _ expected: String) {
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer \(expected)")
        XCTAssertNil(request.url?.query)
    }
}

private final class MockURLProtocol: URLProtocol {
    struct Result {
        let status: Int
        let headers: [String: String]
        let data: Data

        static func json(_ status: Int, _ body: String) -> Result {
            Result(status: status, headers: ["Content-Type": "application/json"], data: Data(body.utf8))
        }

        static func bytes(_ status: Int, _ body: Data) -> Result {
            Result(status: status, headers: ["Content-Type": "application/octet-stream"], data: body)
        }

        static func empty(_ status: Int) -> Result {
            Result(status: status, headers: [:], data: Data())
        }
    }

    static var handler: ((URLRequest) throws -> Result)?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let result = try XCTUnwrap(Self.handler)(request)
            let response = try XCTUnwrap(HTTPURLResponse(
                url: try XCTUnwrap(request.url),
                statusCode: result.status,
                httpVersion: "HTTP/1.1",
                headerFields: result.headers
            ))
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: result.data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}
