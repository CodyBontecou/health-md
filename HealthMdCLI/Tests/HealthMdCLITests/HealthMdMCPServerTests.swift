import Foundation
import XCTest
@testable import HealthMdMCPCore

final class HealthMdMCPServerTests: XCTestCase {
    func testInitializeAndToolListExposeOnlyTools() async throws {
        let client = MCPHTTPClientFake()
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(bearerToken: "secret"),
            httpClient: client
        )

        let initialized = try await responseObject(server, request: [
            "jsonrpc": "2.0",
            "id": 1,
            "method": "initialize",
            "params": ["protocolVersion": "2025-11-25"]
        ])
        let result = try XCTUnwrap(initialized["result"] as? [String: Any])
        XCTAssertEqual(result["protocolVersion"] as? String, "2025-11-25")
        let capabilities = try XCTUnwrap(result["capabilities"] as? [String: Any])
        XCTAssertNotNil(capabilities["tools"])
        XCTAssertNil(capabilities["resources"])
        XCTAssertNil(capabilities["prompts"])
        XCTAssertNil(capabilities["sampling"])

        let listed = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": [:]
        ])
        let tools = try XCTUnwrap(
            (listed["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        )
        XCTAssertTrue(tools.contains { $0["name"] as? String == "healthmd_query" })
        XCTAssertFalse(tools.contains { ($0["name"] as? String)?.contains("shell") == true })
    }

    func testQueryForwardsExactArgumentsAndBearerCredentialToFixedLoopbackRoute() async throws {
        let client = MCPHTTPClientFake(response: .init(
            statusCode: 200,
            body: Data(#"{"schema":"healthmd.query_response","schema_version":1}"#.utf8)
        ))
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(bearerToken: "top-secret"),
            httpClient: client
        )
        let arguments: [String: Any] = [
            "grant_id": "11111111-1111-1111-1111-111111111111",
            "profile": ["profile_id": "22222222-2222-2222-2222-222222222222"],
            "request": [
                "schema": "healthmd.query_request",
                "schema_version": 1,
                "metrics": ["type": "all_available"],
                "dates": ["type": "all_available"]
            ]
        ]

        let response = try await responseObject(server, request: [
            "jsonrpc": "2.0",
            "id": "query-1",
            "method": "tools/call",
            "params": ["name": "healthmd_query", "arguments": arguments]
        ])
        let capturedRequest = await client.lastRequest()
        let recorded = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(recorded.method, "POST")
        XCTAssertEqual(recorded.path, "/v1/agent/query")
        XCTAssertEqual(recorded.headers["Authorization"], "Bearer top-secret")
        XCTAssertEqual(recorded.headers["X-HealthMd-Surface"], "mcp_stdio")
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: try XCTUnwrap(recorded.body)) as? NSDictionary,
            arguments as NSDictionary
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
    }

    func testAuthenticatedToolFailsBeforeHTTPWithoutCredential() async throws {
        let client = MCPHTTPClientFake()
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: client
        )
        let response = try await responseObject(server, request: [
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": ["name": "healthmd_profiles", "arguments": [:]]
        ])

        let capturedRequest = await client.lastRequest()
        XCTAssertNil(capturedRequest)
        XCTAssertEqual((response["result"] as? [String: Any])?["isError"] as? Bool, true)
    }

    func testConfigurationRejectsRemoteOrCredentialBearingBaseURLs() {
        XCTAssertThrowsError(try HealthMdMCPConfiguration(
            baseURL: URL(string: "https://example.com")!
        ))
        XCTAssertThrowsError(try HealthMdMCPConfiguration(
            baseURL: URL(string: "http://user:password@127.0.0.1:17645")!
        ))
        XCTAssertNoThrow(try HealthMdMCPConfiguration(
            baseURL: URL(string: "http://[::1]:17645")!
        ))
    }

    func testNotificationsHaveNoResponseAndUnknownMethodsAreStructured() async throws {
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: MCPHTTPClientFake()
        )
        let notification = try jsonLine([
            "jsonrpc": "2.0", "method": "notifications/initialized", "params": [:]
        ])
        let notificationResponse = await server.handle(line: notification)
        XCTAssertNil(notificationResponse)

        let response = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": 4, "method": "resources/list", "params": [:]
        ])
        XCTAssertEqual((response["error"] as? [String: Any])?["code"] as? Int, -32601)
    }

    private func responseObject(
        _ server: HealthMdMCPServer,
        request: [String: Any]
    ) async throws -> [String: Any] {
        let responseLine = await server.handle(line: try jsonLine(request))
        let response = try XCTUnwrap(responseLine)
        return try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(response.utf8)) as? [String: Any]
        )
    }

    private func jsonLine(_ object: [String: Any]) throws -> String {
        String(decoding: try JSONSerialization.data(withJSONObject: object), as: UTF8.self)
    }
}

private actor MCPHTTPClientFake: HealthMdMCPHTTPClient {
    struct Request: Sendable {
        let method: String
        let path: String
        let body: Data?
        let headers: [String: String]
    }

    private let response: HealthMdMCPHTTPResponse
    private var request: Request?

    init(response: HealthMdMCPHTTPResponse = .init(
        statusCode: 200,
        body: Data(#"{"status":"ok"}"#.utf8)
    )) {
        self.response = response
    }

    func send(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String]
    ) async throws -> HealthMdMCPHTTPResponse {
        request = Request(method: method, path: path, body: body, headers: headers)
        return response
    }

    func lastRequest() -> Request? { request }
}
