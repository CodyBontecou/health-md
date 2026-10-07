import Foundation
import XCTest
@testable import HealthMdWatchExport

private final class StubProtocol: URLProtocol {
    static var status = 200
    static var responseBody = Data()
    static var error: Error?
    static var receivedRequest: URLRequest?
    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func startLoading() {
        Self.receivedRequest = request
        if let error = Self.error {
            client?.urlProtocol(self, didFailWithError: error)
            return
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: Self.status, httpVersion: "HTTP/1.1",
                                       headerFields: ["Content-Type": "application/json"])!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.responseBody)
        client?.urlProtocolDidFinishLoading(self)
    }
    override func stopLoading() {}
}

final class WatchExportHTTPTests: XCTestCase {
    private let id = UUID(uuidString: "00000000-0000-0000-0000-000000000171")!
    private func acknowledgement(id: UUID? = nil, accepted: Bool = true) -> Data {
        Data("{\"schema\":\"healthmd.watch_ack\",\"schema_version\":1,\"upload_id\":\"\((id ?? self.id).uuidString)\",\"accepted\":\(accepted)}".utf8)
    }

    func testEndpointAndCredentialValidationRejectsUnsafeConfiguration() throws {
        for endpoint in ["http://example.com", "https://u:p@example.com", "https://example.com?token=x",
                         "https://example.com#fragment", "file:///tmp/test", "https:///", "https://example.com:0"] {
            XCTAssertThrowsError(try WatchExportDestination(endpoint: endpoint, bearerToken: "synthetic"), endpoint)
        }
        for token in ["", "a\r\nX-Header: injected", "a b", "🗝", String(repeating: "a", count: 4097)] {
            XCTAssertThrowsError(try WatchExportDestination(endpoint: "https://example.com", bearerToken: token))
        }
        _ = try WatchExportDestination(endpoint: "https://example.com:8443/watch", bearerToken: "synthetic-._~+/=")
    }

    func testRequestCarriesExactBodyIdentityAndOnlyConfiguredDestination() throws {
        let pending = WatchPendingUpload(id: id, body: Data("synthetic health payload".utf8))
        let destination = try WatchExportDestination(endpoint: "https://example.com/watch", bearerToken: "synthetic-token")
        let request = try WatchExportHTTP.request(pending, destination: destination)
        XCTAssertEqual(request.url, destination.endpoint)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.httpBody, pending.body)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Bearer synthetic-token")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Idempotency-Key"), id.uuidString)
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
        XCTAssertEqual(request.timeoutInterval, 30)
    }

    func testAcknowledgementRequiresCommitStatusSchemaAndMatchingIdentity() throws {
        for status in [200, 201] {
            XCTAssertNoThrow(try WatchExportHTTP.validateAcknowledgement(acknowledgement(), statusCode: status, uploadID: id))
        }
        for status in [202, 204, 301, 307, 401, 403, 409, 429, 500] {
            XCTAssertThrowsError(try WatchExportHTTP.validateAcknowledgement(acknowledgement(), statusCode: status, uploadID: id))
        }
        for body in [Data(), Data("{}".utf8), acknowledgement(id: UUID()), acknowledgement(accepted: false),
                     Data(repeating: 32, count: 8193),
                     Data("{\"schema\":\"other\",\"schema_version\":1,\"upload_id\":\"\(id)\",\"accepted\":true}".utf8)] {
            XCTAssertThrowsError(try WatchExportHTTP.validateAcknowledgement(body, statusCode: 200, uploadID: id))
        }
    }

    func testDelegateRefusesRedirectEvenWithinSameOrigin() throws {
        let transport = WatchExportHTTP()
        let session = URLSession(configuration: .ephemeral)
        defer { session.invalidateAndCancel() }
        let original = URL(string: "https://example.com/watch")!
        let task = session.dataTask(with: original)
        for target in ["https://example.com/other", "https://other.example/watch", "http://example.com/watch"] {
            var called = false
            transport.urlSession(session, task: task,
                                 willPerformHTTPRedirection: HTTPURLResponse(url: original, statusCode: 307, httpVersion: nil, headerFields: nil)!,
                                 newRequest: URLRequest(url: URL(string: target)!)) { request in
                called = true
                XCTAssertNil(request)
            }
            XCTAssertTrue(called)
        }
    }

    func testURLSessionTransportAcceptsOnlyMatchingAckAndSanitizesFailures() async throws {
        let transport = WatchExportHTTP(protocolClasses: [StubProtocol.self])
        let destination = try WatchExportDestination(endpoint: "https://example.com/watch", bearerToken: "synthetic-token")
        let pending = WatchPendingUpload(id: id, body: Data("{}".utf8))
        StubProtocol.status = 200
        StubProtocol.responseBody = acknowledgement()
        StubProtocol.error = nil
        try await transport.upload(pending, to: destination)
        XCTAssertEqual(StubProtocol.receivedRequest?.url, destination.endpoint)
        for (status, body, error) in [
            (202, acknowledgement(), nil as Error?),
            (403, acknowledgement(), nil),
            (200, acknowledgement(id: UUID()), nil),
            (200, Data(repeating: 32, count: 8193), nil),
            (200, Data(), NSError(domain: "secret-token-and-url-must-not-escape", code: 1))
        ] {
            StubProtocol.status = status
            StubProtocol.responseBody = body
            StubProtocol.error = error
            do {
                try await transport.upload(pending, to: destination)
                XCTFail("Expected rejected/uncertain delivery")
            } catch {
                XCTAssertTrue(error is WatchExportError)
                XCTAssertFalse(error.localizedDescription.contains("secret-token"))
            }
        }
        StubProtocol.error = nil
    }
}
