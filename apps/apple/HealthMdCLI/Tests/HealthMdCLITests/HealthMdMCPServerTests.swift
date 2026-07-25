import Foundation
import XCTest
@testable import HealthMdMCPCore

final class HealthMdMCPServerTests: XCTestCase {
    func testInitializeAndToolListExposeOnlyTools() async throws {
        let client = MCPHTTPClientFake()
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
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
        XCTAssertTrue(tools.contains { $0["name"] as? String == "healthmd_doctor" })
        XCTAssertTrue(tools.contains { $0["name"] as? String == "healthmd_sleep_sessions" })
        XCTAssertTrue(tools.contains { $0["name"] as? String == "healthmd_training_alignment" })
        XCTAssertTrue(tools.contains { $0["name"] as? String == "healthmd_workouts" })
        XCTAssertTrue(tools.contains { $0["name"] as? String == "healthmd_compare_periods" })
        XCTAssertFalse(tools.contains { $0["name"] as? String == "healthmd_profiles" })
        XCTAssertFalse(tools.contains { $0["name"] as? String == "healthmd_activity" })
        let workouts = try XCTUnwrap(tools.first { $0["name"] as? String == "healthmd_workouts" })
        let workoutSchema = try XCTUnwrap(workouts["inputSchema"] as? [String: Any])
        XCTAssertEqual(workoutSchema["additionalProperties"] as? Bool, false)
        XCTAssertFalse(tools.contains { ($0["name"] as? String)?.contains("shell") == true })
    }

    func testDoctorUsesUnauthenticatedLoopbackReadinessRoute() async throws {
        let client = MCPHTTPClientFake(response: .init(
            statusCode: 200,
            body: Data(#"{"schema":"healthmd.local_readiness","schema_version":1,"status":"ready"}"#.utf8)
        ))
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: client
        )

        let response = try await responseObject(server, request: [
            "jsonrpc": "2.0",
            "id": "doctor-1",
            "method": "tools/call",
            "params": ["name": "healthmd_doctor", "arguments": [:]]
        ])
        let capturedRequest = await client.lastRequest()
        let recorded = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(recorded.method, "GET")
        XCTAssertEqual(recorded.path, "/v1/agent/readiness")
        XCTAssertNil(recorded.headers["Authorization"])
        XCTAssertNil(recorded.body)
        XCTAssertEqual((response["result"] as? [String: Any])?["isError"] as? Bool, false)
    }

    func testTypedSleepToolBuildsFixedWindowRequestAndLosslessDefault() async throws {
        let client = MCPHTTPClientFake()
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: client
        )
        _ = try await responseObject(server, request: [
            "jsonrpc": "2.0",
            "id": "sleep-1",
            "method": "tools/call",
            "params": [
                "name": "healthmd_sleep_sessions",
                "arguments": [
                    "dates": ["type": "all_available"],
                    "metrics": [
                        "type": "explicit",
                        "metric_ids": ["sleep_total", "heart_rate"]
                    ],
                    "detail_level": "summary",
                    "window": ["start_offset_seconds": 0, "duration_seconds": 14_400]
                ]
            ]
        ])

        let capturedRequest = await client.lastRequest()
        let recorded = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(recorded.path, "/v1/agent/query")
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(recorded.body)) as? [String: Any]
        )
        XCTAssertEqual(body["detail_level"] as? String, "lossless")
        let request = try XCTUnwrap(body["request"] as? [String: Any])
        let operation = try XCTUnwrap(request["operation"] as? [String: Any])
        XCTAssertEqual(operation["type"] as? String, "sleep_session_listing")
        XCTAssertEqual(
            Set((request["metrics"] as? [String: Any])?["metric_ids"] as? [String] ?? []),
            Set([
                "heart_rate", "sleep_total", "sleep_bedtime", "sleep_wake",
                "sleep_deep", "sleep_rem", "sleep_core", "sleep_awake", "sleep_in_bed"
            ])
        )
        XCTAssertEqual(operation["include_naps"] as? Bool, false)
        XCTAssertEqual(
            (operation["window"] as? [String: Any])?["duration_seconds"] as? Int,
            14_400
        )
    }

    func testTypedTrainingAlignmentBuildsFactualAlignmentOperation() async throws {
        let client = MCPHTTPClientFake()
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: client
        )
        _ = try await responseObject(server, request: [
            "jsonrpc": "2.0",
            "id": "alignment-1",
            "method": "tools/call",
            "params": [
                "name": "healthmd_training_alignment",
                "arguments": [
                    "dates": ["type": "all_available"],
                    "workout_activity": "running",
                    "window": ["duration_seconds": 14_400]
                ]
            ]
        ])
        let capturedRequest = await client.lastRequest()
        let recorded = try XCTUnwrap(capturedRequest)
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(recorded.body)) as? [String: Any]
        )
        XCTAssertEqual(body["detail_level"] as? String, "lossless")
        let request = try XCTUnwrap(body["request"] as? [String: Any])
        let operation = try XCTUnwrap(request["operation"] as? [String: Any])
        XCTAssertEqual(operation["type"] as? String, "workout_sleep_alignment")
        XCTAssertEqual(operation["workout_activity"] as? String, "running")
        XCTAssertEqual(
            Set((request["metrics"] as? [String: Any])?["metric_ids"] as? [String] ?? []),
            Set([
                "workouts", "sleep_total", "sleep_bedtime", "sleep_wake",
                "sleep_deep", "sleep_rem", "sleep_core", "sleep_awake", "sleep_in_bed"
            ])
        )
    }

    func testTrainingEvidenceUsesSummaryUnlessDetailIDsAreRequested() async throws {
        let client = MCPHTTPClientFake()
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: client
        )
        let baseArguments: [String: Any] = [
            "dates": ["type": "all_available"]
        ]
        _ = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "evidence-summary", "method": "tools/call",
            "params": ["name": "healthmd_training_evidence", "arguments": baseArguments]
        ])
        var requests = await client.allRequests()
        var body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(requests.last?.body)) as? [String: Any]
        )
        XCTAssertEqual(body["detail_level"] as? String, "summary")

        var detailedArguments = baseArguments
        detailedArguments["detail_ids"] = ["workout:detail"]
        _ = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "evidence-detail", "method": "tools/call",
            "params": ["name": "healthmd_training_evidence", "arguments": detailedArguments]
        ])
        requests = await client.allRequests()
        body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(requests.last?.body)) as? [String: Any]
        )
        XCTAssertEqual(body["detail_level"] as? String, "lossless")
    }

    func testTypedToolAllPagesTraversesCursorsAndReturnsReceipt() async throws {
        let page1 = #"{"schema":"healthmd.query_response","schema_version":1,"items":[{"type":"workout"}],"packet":null,"coverage":{},"sources":[],"evidence":[],"next_cursor":"next-page","limitations":[]}"#
        let page2 = #"{"schema":"healthmd.query_response","schema_version":1,"items":[{"type":"workout"}],"packet":null,"coverage":{},"sources":[],"evidence":[],"next_cursor":null,"limitations":[]}"#
        let client = MCPHTTPClientFake(responses: [
            .init(statusCode: 200, body: Data(page1.utf8)),
            .init(statusCode: 200, body: Data(page2.utf8))
        ])
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: client
        )
        let response = try await responseObject(server, request: [
            "jsonrpc": "2.0",
            "id": "paging-1",
            "method": "tools/call",
            "params": [
                "name": "healthmd_workouts",
                "arguments": [
                    "dates": ["type": "all_available"],
                    "all_pages": true
                ]
            ]
        ])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        let text = try XCTUnwrap(content.first?["text"] as? String)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        XCTAssertEqual(object["schema"] as? String, "healthmd.mcp_query_pages")
        XCTAssertEqual((object["pages"] as? [Any])?.count, 2)
        let receipt = try XCTUnwrap(object["receipt"] as? [String: Any])
        XCTAssertEqual(receipt["page_count"] as? Int, 2)
        XCTAssertEqual(receipt["item_count"] as? Int, 2)
        XCTAssertEqual(receipt["traversal_complete"] as? Bool, true)

        let limitedClient = MCPHTTPClientFake(responses: [
            .init(statusCode: 200, body: Data(page1.utf8)),
            .init(statusCode: 200, body: Data(page2.utf8))
        ])
        let limitedServer = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: limitedClient,
            maximumTraversalPages: 1
        )
        let limitedResponse = try await responseObject(limitedServer, request: [
            "jsonrpc": "2.0",
            "id": "paging-limit",
            "method": "tools/call",
            "params": [
                "name": "healthmd_workouts",
                "arguments": [
                    "dates": ["type": "all_available"],
                    "all_pages": true
                ]
            ]
        ])
        let limitedResult = try XCTUnwrap(limitedResponse["result"] as? [String: Any])
        XCTAssertEqual(limitedResult["isError"] as? Bool, true)
        let limitedText = try XCTUnwrap(
            (limitedResult["content"] as? [[String: Any]])?.first?["text"] as? String
        )
        XCTAssertTrue(limitedText.contains("query_traversal_aggregate_limit"))

        let requests = await client.allRequests()
        XCTAssertEqual(requests.count, 2)
        let firstBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(requests[0].body)) as? [String: Any]
        )
        let secondBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(requests[1].body)) as? [String: Any]
        )
        let firstRequest = firstBody["request"] as? [String: Any]
        let secondRequest = secondBody["request"] as? [String: Any]
        XCTAssertTrue(((firstRequest?["page"] as? [String: Any])?["cursor"]) is NSNull)
        XCTAssertEqual(
            (secondRequest?["page"] as? [String: Any])?["cursor"] as? String,
            "next-page"
        )
    }

    func testTypedWorkoutToolBuildsVersionedWorkoutListingRequest() async throws {
        let client = MCPHTTPClientFake()
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: client
        )
        _ = try await responseObject(server, request: [
            "jsonrpc": "2.0",
            "id": "workouts-1",
            "method": "tools/call",
            "params": [
                "name": "healthmd_workouts",
                "arguments": [
                    "dates": [
                        "type": "exact",
                        "range": ["start_date": "2026-07-01", "end_date": "2026-07-14"]
                    ]
                ]
            ]
        ])

        let capturedRequest = await client.lastRequest()
        let recorded = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(recorded.path, "/v1/agent/query")
        let body = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(recorded.body)) as? [String: Any]
        )
        let query = try XCTUnwrap(body["request"] as? [String: Any])
        XCTAssertEqual(query["schema"] as? String, "healthmd.query_request")
        XCTAssertEqual(
            (query["operation"] as? [String: Any])?["type"] as? String,
            "workout_listing"
        )
        XCTAssertEqual(
            ((query["metrics"] as? [String: Any])?["metric_ids"] as? [String]),
            ["workouts"]
        )
    }

    func testQueryForwardsDirectScopeToFixedLoopbackRoute() async throws {
        let client = MCPHTTPClientFake(response: .init(
            statusCode: 200,
            body: Data(#"{"schema":"healthmd.query_response","schema_version":1}"#.utf8)
        ))
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: client
        )
        let arguments: [String: Any] = [
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
        XCTAssertNil(recorded.headers["Authorization"])
        XCTAssertNil(recorded.headers["X-HealthMd-Surface"])
        XCTAssertEqual(
            try JSONSerialization.jsonObject(with: try XCTUnwrap(recorded.body)) as? NSDictionary,
            arguments as NSDictionary
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
    }

    func testLocalToolCallsDoNotRequireCredentials() async throws {
        let client = MCPHTTPClientFake()
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: client
        )
        let response = try await responseObject(server, request: [
            "jsonrpc": "2.0",
            "id": 3,
            "method": "tools/call",
            "params": ["name": "healthmd_capabilities", "arguments": [:]]
        ])

        let capturedRequest = await client.lastRequest()
        XCTAssertEqual(capturedRequest?.path, "/v1/agent/capabilities")
        XCTAssertNil(capturedRequest?.headers["Authorization"])
        XCTAssertEqual((response["result"] as? [String: Any])?["isError"] as? Bool, false)
    }

    func testConfigurationRejectsRemoteOrUserInfoBearingBaseURLs() {
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

    private let responses: [HealthMdMCPHTTPResponse]
    private var requests: [Request] = []

    init(response: HealthMdMCPHTTPResponse = .init(
        statusCode: 200,
        body: Data(#"{"status":"ok"}"#.utf8)
    )) {
        self.responses = [response]
    }

    init(responses: [HealthMdMCPHTTPResponse]) {
        self.responses = responses
    }

    func send(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String]
    ) async throws -> HealthMdMCPHTTPResponse {
        requests.append(Request(method: method, path: path, body: body, headers: headers))
        return responses[min(requests.count - 1, responses.count - 1)]
    }

    func lastRequest() -> Request? { requests.last }
    func allRequests() -> [Request] { requests }
}
