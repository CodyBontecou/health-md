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
        XCTAssertTrue(tools.contains { $0["name"] as? String == "healthmd_metric_chart" })
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
        let chart = try XCTUnwrap(tools.first { $0["name"] as? String == "healthmd_metric_chart" })
        XCTAssertNil((chart["_meta"] as? [String: Any])?["ui"])
        let export = try XCTUnwrap(tools.first { $0["name"] as? String == "healthmd_export_files" })
        XCTAssertEqual(
            (export["_meta"] as? [String: Any])?["anthropic/requiresUserInteraction"] as? Bool,
            true
        )
        for name in [
            "healthmd_export_files", "healthmd_export_job_resume",
            "healthmd_export_job_cancel", "healthmd_refresh", "healthmd_job_resume",
            "healthmd_job_cancel"
        ] {
            let mutatingTool = try XCTUnwrap(tools.first { $0["name"] as? String == name })
            XCTAssertEqual(
                (mutatingTool["annotations"] as? [String: Any])?["readOnlyHint"] as? Bool,
                false,
                name
            )
            XCTAssertEqual(
                (mutatingTool["annotations"] as? [String: Any])?["destructiveHint"] as? Bool,
                true,
                name
            )
            XCTAssertEqual(
                (mutatingTool["_meta"] as? [String: Any])?["anthropic/requiresUserInteraction"] as? Bool,
                true,
                name
            )
        }
    }

    func testMCPAppsNegotiationExposesAuditableResourceAndConditionalToolMetadata() async throws {
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: MCPHTTPClientFake()
        )
        let initialized = try await responseObject(server, request: [
            "jsonrpc": "2.0",
            "id": "init-ui",
            "method": "initialize",
            "params": [
                "protocolVersion": "2025-11-25",
                "capabilities": [
                    "extensions": [
                        "io.modelcontextprotocol/ui": [
                            "mimeTypes": ["text/html;profile=mcp-app"]
                        ]
                    ]
                ]
            ]
        ])
        let capabilities = try XCTUnwrap(
            (initialized["result"] as? [String: Any])?["capabilities"] as? [String: Any]
        )
        XCTAssertNotNil(capabilities["resources"])
        let extensions = try XCTUnwrap(capabilities["extensions"] as? [String: Any])
        XCTAssertEqual(
            ((extensions["io.modelcontextprotocol/ui"] as? [String: Any])?["mimeTypes"] as? [String]),
            ["text/html;profile=mcp-app"]
        )

        let listedTools = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "tools-ui", "method": "tools/list", "params": [:]
        ])
        let tools = try XCTUnwrap(
            (listedTools["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        )
        let chart = try XCTUnwrap(tools.first { $0["name"] as? String == "healthmd_metric_chart" })
        let chartUI = try XCTUnwrap(
            (chart["_meta"] as? [String: Any])?["ui"] as? [String: Any]
        )
        XCTAssertEqual(chartUI["resourceUri"] as? String, "ui://healthmd/query-visualization-v1")
        XCTAssertEqual(chartUI["visibility"] as? [String], ["model"])
        let status = try XCTUnwrap(tools.first { $0["name"] as? String == "healthmd_status" })
        XCTAssertNil(status["_meta"])

        let listedResources = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "resources-ui", "method": "resources/list", "params": [:]
        ])
        let resources = try XCTUnwrap(
            (listedResources["result"] as? [String: Any])?["resources"] as? [[String: Any]]
        )
        XCTAssertEqual(resources.count, 1)
        XCTAssertEqual(resources[0]["uri"] as? String, "ui://healthmd/query-visualization-v1")
        XCTAssertEqual(resources[0]["mimeType"] as? String, "text/html;profile=mcp-app")

        let resourceRead = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "resource-read", "method": "resources/read",
            "params": ["uri": "ui://healthmd/query-visualization-v1"]
        ])
        let contents = try XCTUnwrap(
            (resourceRead["result"] as? [String: Any])?["contents"] as? [[String: Any]]
        )
        let content = try XCTUnwrap(contents.first)
        XCTAssertEqual(content["mimeType"] as? String, "text/html;profile=mcp-app")
        let html = try XCTUnwrap(content["text"] as? String)
        XCTAssertTrue(html.hasPrefix("<!doctype html>"))
        XCTAssertTrue(html.contains("ui/initialize"))
        XCTAssertTrue(html.contains("ui/notifications/tool-result"))
        XCTAssertTrue(html.contains("ui/notifications/size-changed"))
        XCTAssertTrue(html.contains("healthmd.mcp_query_pages"))
        XCTAssertTrue(html.contains("const packetFacts = new Map()"))
        XCTAssertTrue(html.contains("packetMetadataIsInvariant"))
        XCTAssertTrue(html.contains("const coverageByValue = new Map()"))
        XCTAssertTrue(html.contains("Comparison coverage and missingness"))
        XCTAssertTrue(html.contains("point.status !== \"available\""))
        XCTAssertFalse(html.contains("<script src="))
        XCTAssertFalse(html.contains("fetch("))
        XCTAssertFalse(html.contains("localStorage"))
        let ui = try XCTUnwrap(
            (content["_meta"] as? [String: Any])?["ui"] as? [String: Any]
        )
        let csp = try XCTUnwrap(ui["csp"] as? [String: Any])
        XCTAssertEqual(csp["connectDomains"] as? [String], [])
        XCTAssertEqual(csp["resourceDomains"] as? [String], [])
        XCTAssertEqual(csp["frameDomains"] as? [String], [])
    }

    func testMCPAppsRequireExactNegotiatedMIMEType() async throws {
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: MCPHTTPClientFake()
        )
        let initialized = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "wrong-ui", "method": "initialize",
            "params": [
                "protocolVersion": "2025-11-25",
                "capabilities": [
                    "extensions": [
                        "io.modelcontextprotocol/ui": ["mimeTypes": ["text/html"]]
                    ]
                ]
            ]
        ])
        let capabilities = try XCTUnwrap(
            (initialized["result"] as? [String: Any])?["capabilities"] as? [String: Any]
        )
        XCTAssertNil(capabilities["resources"])
        XCTAssertNil(capabilities["extensions"])
        let response = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "no-resource", "method": "resources/list", "params": [:]
        ])
        XCTAssertEqual((response["error"] as? [String: Any])?["code"] as? Int, -32601)
    }

    func testMetricChartBuildsTypedSeriesAndReturnsStructuredContentForMCPApps() async throws {
        let body = Data(#"{"schema":"healthmd.query_response","schema_version":1,"items":[{"type":"metric","metric":{"metric_id":"steps","display_name":"Steps","owner_date":"2026-07-01","value":{"type":"count","value":1234},"status":"available","evidence":[],"limitations":[]}}],"packet":null,"coverage":{"requested_range":null,"available_range":{"start_date":"2026-07-01","end_date":"2026-07-01"},"status":"available","days_considered":1,"days_with_values":1,"missing":[]},"sources":[],"evidence":[],"next_cursor":null,"limitations":[]}"#.utf8)
        let client = MCPHTTPClientFake(response: .init(statusCode: 200, body: body))
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: client
        )
        _ = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "init-chart", "method": "initialize",
            "params": [
                "protocolVersion": "2025-11-25",
                "capabilities": [
                    "extensions": [
                        "io.modelcontextprotocol/ui": [
                            "mimeTypes": ["text/html;profile=mcp-app"]
                        ]
                    ]
                ]
            ]
        ])
        let response = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "chart", "method": "tools/call",
            "params": [
                "name": "healthmd_metric_chart",
                "arguments": [
                    "dates": ["type": "exact", "range": [
                        "start_date": "2026-07-01", "end_date": "2026-07-01"
                    ]],
                    "metrics": ["type": "explicit", "metric_ids": ["steps"]]
                ]
            ]
        ])
        let capturedRequest = await client.lastRequest()
        let recorded = try XCTUnwrap(capturedRequest)
        XCTAssertEqual(recorded.path, "/v1/agent/query")
        let requestBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(recorded.body)) as? [String: Any]
        )
        let request = try XCTUnwrap(requestBody["request"] as? [String: Any])
        XCTAssertEqual((request["operation"] as? [String: Any])?["type"] as? String, "metric_series")
        XCTAssertEqual(requestBody["detail_level"] as? String, "summary")

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, false)
        let text = try XCTUnwrap((result["content"] as? [[String: Any]])?.first?["text"] as? String)
        XCTAssertEqual(Data(text.utf8), body)
        let structured = try XCTUnwrap(result["structuredContent"] as? [String: Any])
        XCTAssertEqual(structured["schema"] as? String, "healthmd.query_response")
        XCTAssertEqual((structured["items"] as? [Any])?.count, 1)
    }

    func testMetricChartReturnsPNGForClientsWithoutMCPApps() async throws {
        XCTAssertTrue(HealthMdMCPChartRenderer.isPlottableStatus("available"))
        XCTAssertFalse(HealthMdMCPChartRenderer.isPlottableStatus("partial"))
        XCTAssertFalse(HealthMdMCPChartRenderer.isPlottableStatus("failed"))
        let body = Data(#"{"schema":"healthmd.query_response","schema_version":1,"items":[{"type":"metric","metric":{"metric_id":"steps","display_name":"Steps","owner_date":"2026-07-01","value":{"type":"count","value":1234},"status":"available","evidence":[],"limitations":[]}},{"type":"metric","metric":{"metric_id":"steps","display_name":"Steps","owner_date":"2026-07-02","value":{"type":"count","value":9999},"status":"partial","evidence":[],"limitations":[]}},{"type":"metric","metric":{"metric_id":"steps","display_name":"Steps","owner_date":"2026-07-03","value":{"type":"count","value":4321},"status":"available","evidence":[],"limitations":[]}}],"packet":null,"coverage":{"requested_range":null,"available_range":{"start_date":"2026-07-01","end_date":"2026-07-03"},"status":"partial","days_considered":3,"days_with_values":2,"missing":[]},"sources":[],"evidence":[],"next_cursor":null,"limitations":[]}"#.utf8)
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: MCPHTTPClientFake(response: .init(statusCode: 200, body: body))
        )
        let response = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "chart-image", "method": "tools/call",
            "params": [
                "name": "healthmd_metric_chart",
                "arguments": [
                    "dates": ["type": "all_available"],
                    "metrics": ["type": "explicit", "metric_ids": ["steps"]]
                ]
            ]
        ])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertNil(result["structuredContent"])
        let content = try XCTUnwrap(result["content"] as? [[String: Any]])
        XCTAssertEqual(content.count, 2)
        XCTAssertEqual(content[0]["type"] as? String, "text")
        XCTAssertEqual(content[1]["type"] as? String, "image")
        XCTAssertEqual(content[1]["mimeType"] as? String, "image/png")
        XCTAssertEqual(
            (content[1]["_meta"] as? [String: Any])?["codex/imageDetail"] as? String,
            "original"
        )
        let png = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(content[1]["data"] as? String)))
        XCTAssertEqual(Array(png.prefix(8)), [137, 80, 78, 71, 13, 10, 26, 10])
        XCTAssertGreaterThan(png.count, 10_000)
    }

    func testGeneratedFileExportIsApprovalMarkedScopedAndVisualizable() async throws {
        let body = Data(#"{"status":"success","message":"Export complete.","files_written":3,"destination_display_name":"Health Vault"}"#.utf8)
        let client = MCPHTTPClientFake(
            response: .init(statusCode: 200, body: body),
            echoesExportJobID: true
        )
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: client
        )
        _ = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "init-export", "method": "initialize",
            "params": [
                "protocolVersion": "2025-11-25",
                "capabilities": [
                    "extensions": [
                        "io.modelcontextprotocol/ui": [
                            "mimeTypes": ["text/html;profile=mcp-app"]
                        ]
                    ]
                ]
            ]
        ])

        let listed = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "list-export", "method": "tools/list", "params": [:]
        ])
        let tools = try XCTUnwrap(
            (listed["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        )
        let exportTool = try XCTUnwrap(
            tools.first { $0["name"] as? String == "healthmd_export_files" }
        )
        let annotations = try XCTUnwrap(exportTool["annotations"] as? [String: Any])
        XCTAssertEqual(annotations["readOnlyHint"] as? Bool, false)
        XCTAssertEqual(annotations["destructiveHint"] as? Bool, true)
        let metadata = try XCTUnwrap(exportTool["_meta"] as? [String: Any])
        XCTAssertEqual(metadata["anthropic/requiresUserInteraction"] as? Bool, true)
        XCTAssertEqual(
            (metadata["ui"] as? [String: Any])?["resourceUri"] as? String,
            "ui://healthmd/query-visualization-v1"
        )

        let response = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "export", "method": "tools/call",
            "params": [
                "name": "healthmd_export_files",
                "arguments": [
                    "date_selection": "explicit_range",
                    "date_range": ["start": "2026-07-01", "end": "2026-07-03"],
                    "settings_policy": "requested_dates_only",
                    "categories": ["Sleep"],
                    "detail_level": "lossless",
                    "wait_timeout_seconds": 120
                ]
            ]
        ])
        let captured = await client.lastRequest()
        let recorded = try XCTUnwrap(captured)
        XCTAssertEqual(recorded.method, "POST")
        XCTAssertEqual(recorded.path, "/v1/exports")
        let requestBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(recorded.body)) as? [String: Any]
        )
        XCTAssertEqual(requestBody["source"] as? String, "connected_iphone")
        XCTAssertEqual(requestBody["response_mode"] as? String, "write_files")
        XCTAssertEqual(requestBody["date_selection"] as? String, "explicit_range")
        let requestJobID = try XCTUnwrap(requestBody["job_id"] as? String)
        XCTAssertNotNil(UUID(uuidString: requestJobID))
        XCTAssertNil(requestBody["raw_profile"])
        let selection = try XCTUnwrap(requestBody["canonical_selection"] as? [String: Any])
        XCTAssertEqual(selection["categories"] as? [String], ["Sleep"])
        XCTAssertEqual(selection["detail_level"] as? String, "lossless")
        XCTAssertEqual(selection["source_ids"] as? [String], ["apple_health"])

        let result = try XCTUnwrap(response["result"] as? [String: Any])
        let structured = try XCTUnwrap(result["structuredContent"] as? [String: Any])
        XCTAssertEqual(structured["schema"] as? String, "healthmd.mcp_export_result")
        XCTAssertEqual(structured["operation"] as? String, "healthmd_export_files")
        XCTAssertEqual(
            (structured["response"] as? [String: Any])?["job_id"] as? String,
            requestJobID
        )
        let resultText = try XCTUnwrap(
            (result["content"] as? [[String: Any]])?.first?["text"] as? String
        )
        let resultObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(resultText.utf8)) as? [String: Any]
        )
        XCTAssertEqual(resultObject["job_id"] as? String, requestJobID)
    }

    func testMismatchedExportReceiptReturnsRecoverableUnknownOutcomeError() async throws {
        let client = MCPHTTPClientFake(response: .init(
            statusCode: 200,
            body: Data(#"{"status":"success","job_id":"00000000-0000-4000-8000-000000000399","message":"Wrong job."}"#.utf8)
        ))
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: client
        )
        _ = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "init-mismatch", "method": "initialize",
            "params": [
                "protocolVersion": "2025-11-25",
                "capabilities": ["extensions": [
                    "io.modelcontextprotocol/ui": [
                        "mimeTypes": ["text/html;profile=mcp-app"]
                    ]
                ]]
            ]
        ])
        let response = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "mismatch", "method": "tools/call",
            "params": [
                "name": "healthmd_export_files",
                "arguments": ["date_selection": "all_available"]
            ]
        ])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        XCTAssertNil(result["structuredContent"])
        let capturedRequest = await client.lastRequest()
        let request = try XCTUnwrap(capturedRequest)
        let requestBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(request.body)) as? [String: Any]
        )
        let expectedJobID = try XCTUnwrap(requestBody["job_id"] as? String)
        let text = try XCTUnwrap(
            (result["content"] as? [[String: Any]])?.first?["text"] as? String
        )
        let error = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        XCTAssertEqual(error["error"] as? String, "healthmd_export_receipt_invalid")
        XCTAssertEqual(error["job_id"] as? String, expectedJobID)
        XCTAssertEqual(error["http_status"] as? Int, 200)
    }

    func testTimedOutExportRetainsStructuredDurableReceiptForMCPApp() async throws {
        let client = MCPHTTPClientFake(
            response: .init(
                statusCode: 408,
                body: Data(#"{"status":"timed_out","message":"The waiter timed out.","state":"paused","processed_days":3,"total_count":7}"#.utf8)
            ),
            echoesExportJobID: true
        )
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: client
        )
        _ = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "init-timeout", "method": "initialize",
            "params": [
                "protocolVersion": "2025-11-25",
                "capabilities": ["extensions": [
                    "io.modelcontextprotocol/ui": [
                        "mimeTypes": ["text/html;profile=mcp-app"]
                    ]
                ]]
            ]
        ])
        let response = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "timeout", "method": "tools/call",
            "params": [
                "name": "healthmd_export_files",
                "arguments": ["date_selection": "all_available"]
            ]
        ])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        let structured = try XCTUnwrap(result["structuredContent"] as? [String: Any])
        let receipt = try XCTUnwrap(structured["response"] as? [String: Any])
        XCTAssertEqual(receipt["status"] as? String, "timed_out")
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(receipt["job_id"] as? String)))
        XCTAssertEqual(receipt["processed_days"] as? Int, 3)
    }

    func testExportDateSelectionAndDurableJobRoutesFailClosed() async throws {
        let client = MCPHTTPClientFake(response: .init(
            statusCode: 202,
            body: Data(#"{"status":"accepted","job_id":"00000000-0000-4000-8000-000000000302","message":"Queued."}"#.utf8)
        ))
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: client
        )
        let invalidArguments: [[String: Any]] = [
            [
                "date_selection": "all_available",
                "date_range": ["start": "2026-01-01", "end": "2026-01-02"]
            ],
            ["date_selection": "all_available", "settings_policy": true],
            ["date_selection": "all_available", "metric_ids": "steps", "categories": ["Sleep"]],
            ["date_selection": "all_available", "all_metrics": "yes"],
            ["date_selection": "all_available", "metric_ids": ["steps"], "detail_level": true],
            ["date_selection": "all_available", "wait_timeout_seconds": "300"]
        ]
        for (index, arguments) in invalidArguments.enumerated() {
            let invalid = try await responseObject(server, request: [
                "jsonrpc": "2.0", "id": "bad-export-\(index)", "method": "tools/call",
                "params": ["name": "healthmd_export_files", "arguments": arguments]
            ])
            XCTAssertEqual(
                (invalid["error"] as? [String: Any])?["code"] as? Int,
                -32602,
                "Invalid mutation argument set \(index) must fail before HTTP"
            )
        }
        let rejectedRequests = await client.allRequests()
        XCTAssertTrue(rejectedRequests.isEmpty)

        let jobID = "00000000-0000-4000-8000-000000000302"
        for (name, arguments) in [
            ("healthmd_export_job_status", ["job_id": jobID] as [String: Any]),
            ("healthmd_export_job_resume", ["job_id": jobID, "wait_timeout_seconds": 180] as [String: Any]),
            ("healthmd_export_job_cancel", ["job_id": jobID] as [String: Any])
        ] {
            _ = try await responseObject(server, request: [
                "jsonrpc": "2.0", "id": name, "method": "tools/call",
                "params": ["name": name, "arguments": arguments]
            ])
        }
        let requests = await client.allRequests()
        XCTAssertEqual(requests.map(\.method), ["GET", "POST", "POST"])
        XCTAssertEqual(requests.map(\.path), [
            "/v1/exports/\(jobID)",
            "/v1/exports/\(jobID)/resume",
            "/v1/exports/\(jobID)/cancel"
        ])
        let resumeBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(requests[1].body)) as? [String: Any]
        )
        XCTAssertEqual(resumeBody as NSDictionary, ["wait_timeout_seconds": 180] as NSDictionary)
        let cancelBody = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(requests[2].body)) as? [String: Any]
        )
        XCTAssertTrue(cancelBody.isEmpty)
    }

    func testUnknownExportTransportOutcomeReturnsDurableJobIDBeforeRetry() async throws {
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: MCPHTTPClientFailing()
        )
        let response = try await responseObject(server, request: [
            "jsonrpc": "2.0", "id": "unknown-export", "method": "tools/call",
            "params": [
                "name": "healthmd_export_files",
                "arguments": ["date_selection": "all_available"]
            ]
        ])
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        let text = try XCTUnwrap(
            (result["content"] as? [[String: Any]])?.first?["text"] as? String
        )
        let error = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        XCTAssertEqual(error["error"] as? String, "healthmd_unavailable")
        XCTAssertEqual(error["operation_outcome"] as? String, "unknown")
        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(error["job_id"] as? String)))
        XCTAssertTrue((error["message"] as? String)?.contains("before retrying") == true)
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
        XCTAssertEqual(limitedResult["isError"] as? Bool, false)
        let limitedText = try XCTUnwrap(
            (limitedResult["content"] as? [[String: Any]])?.first?["text"] as? String
        )
        let limitedObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(limitedText.utf8)) as? [String: Any]
        )
        XCTAssertEqual((limitedObject["pages"] as? [Any])?.count, 1)
        let limitedReceipt = try XCTUnwrap(limitedObject["receipt"] as? [String: Any])
        XCTAssertEqual(limitedReceipt["traversal_complete"] as? Bool, false)
        XCTAssertEqual(limitedReceipt["next_cursor"] as? String, "next-page")
        XCTAssertEqual(limitedReceipt["limit_reason"] as? String, "maximum_pages")
        let limitedRequests = await limitedClient.allRequests()
        XCTAssertEqual(limitedRequests.count, 1)

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

    func testStdioExecutableNegotiatesMCPAppEndToEnd() throws {
        let packageRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let candidates = [
            packageRoot.appendingPathComponent(".build/debug/healthmd-mcp"),
            packageRoot.appendingPathComponent(".build/arm64-apple-macosx/debug/healthmd-mcp"),
            Bundle.main.bundleURL.deletingLastPathComponent().appendingPathComponent("healthmd-mcp")
        ]
        let executable = try XCTUnwrap(candidates.first {
            FileManager.default.isExecutableFile(atPath: $0.path)
        })
        let process = Process()
        process.executableURL = executable
        let input = Pipe()
        let output = Pipe()
        let errors = Pipe()
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
        try process.run()

        let requests: [[String: Any]] = [
            [
                "jsonrpc": "2.0", "id": 1, "method": "initialize",
                "params": [
                    "protocolVersion": "2025-11-25",
                    "capabilities": [
                        "extensions": [
                            "io.modelcontextprotocol/ui": [
                                "mimeTypes": ["text/html;profile=mcp-app"]
                            ]
                        ]
                    ],
                    "clientInfo": ["name": "healthmd-tests", "version": "1"]
                ]
            ],
            ["jsonrpc": "2.0", "method": "notifications/initialized", "params": [:]],
            ["jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": [:]],
            ["jsonrpc": "2.0", "id": 3, "method": "resources/list", "params": [:]]
        ]
        let lines = try requests.map { request in
            String(decoding: try JSONSerialization.data(withJSONObject: request), as: UTF8.self)
        }.joined(separator: "\n") + "\n"
        try input.fileHandleForWriting.write(contentsOf: Data(lines.utf8))
        try input.fileHandleForWriting.close()
        process.waitUntilExit()

        let errorText = String(
            decoding: errors.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        )
        XCTAssertEqual(process.terminationStatus, 0, errorText)
        let responseLines = String(
            decoding: output.fileHandleForReading.readDataToEndOfFile(),
            as: UTF8.self
        ).split(separator: "\n")
        XCTAssertEqual(responseLines.count, 3)
        let responses = try responseLines.map { line in
            try XCTUnwrap(
                JSONSerialization.jsonObject(with: Data(line.utf8)) as? [String: Any]
            )
        }
        let responsesByID = Dictionary(uniqueKeysWithValues: try responses.map { response in
            (try XCTUnwrap(response["id"] as? Int), response)
        })
        let capabilities = try XCTUnwrap(
            (responsesByID[1]?["result"] as? [String: Any])?["capabilities"] as? [String: Any]
        )
        XCTAssertNotNil(capabilities["resources"])
        let tools = try XCTUnwrap(
            (responsesByID[2]?["result"] as? [String: Any])?["tools"] as? [[String: Any]]
        )
        XCTAssertEqual(tools.count, 21)
        XCTAssertTrue(tools.contains { $0["name"] as? String == "healthmd_metric_chart" })
        XCTAssertTrue(tools.contains { $0["name"] as? String == "healthmd_export_files" })
        let resources = try XCTUnwrap(
            (responsesByID[3]?["result"] as? [String: Any])?["resources"] as? [[String: Any]]
        )
        XCTAssertEqual(resources.first?["uri"] as? String, "ui://healthmd/query-visualization-v1")
    }

    func testCancelledNotificationDetachesInFlightExportWaiter() async throws {
        let client = MCPHTTPClientSlowFake()
        let server = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: client
        )
        let callLine = try jsonLine([
            "jsonrpc": "2.0", "id": "export-wait", "method": "tools/call",
            "params": [
                "name": "healthmd_export_files",
                "arguments": ["date_selection": "all_available"]
            ]
        ])
        let call = Task {
            await server.handle(line: callLine)
        }
        for _ in 0..<1_000 {
            if await client.didStart() { break }
            await Task.yield()
        }
        let didStart = await client.didStart()
        XCTAssertTrue(didStart)
        let notification = try jsonLine([
            "jsonrpc": "2.0", "method": "notifications/cancelled",
            "params": ["requestId": "export-wait", "reason": "host cancelled"]
        ])
        let notificationResponse = await server.handle(line: notification)
        XCTAssertNil(notificationResponse)
        let callResponse = await call.value
        let responseLine = try XCTUnwrap(callResponse)
        let response = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(responseLine.utf8)) as? [String: Any]
        )
        let result = try XCTUnwrap(response["result"] as? [String: Any])
        XCTAssertEqual(result["isError"] as? Bool, true)
        let text = try XCTUnwrap(
            (result["content"] as? [[String: Any]])?.first?["text"] as? String
        )
        let error = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(text.utf8)) as? [String: Any]
        )
        XCTAssertEqual(error["error"] as? String, "healthmd_export_wait_cancelled")
        XCTAssertEqual(error["operation_outcome"] as? String, "unknown")
        let startedJobID = await client.startedJobID()
        XCTAssertEqual(error["job_id"] as? String, startedJobID)

        let preCancelledClient = MCPHTTPClientFake()
        let preCancelledServer = HealthMdMCPServer(
            configuration: try HealthMdMCPConfiguration(),
            httpClient: preCancelledClient
        )
        let earlyNotification = try jsonLine([
            "jsonrpc": "2.0", "method": "notifications/cancelled",
            "params": ["requestId": "cancel-before-start"]
        ])
        _ = await preCancelledServer.handle(line: earlyNotification)
        let earlyResponse = try await responseObject(preCancelledServer, request: [
            "jsonrpc": "2.0", "id": "cancel-before-start", "method": "tools/call",
            "params": [
                "name": "healthmd_export_files",
                "arguments": ["date_selection": "all_available"]
            ]
        ])
        XCTAssertEqual(
            (earlyResponse["error"] as? [String: Any])?["code"] as? Int,
            -32800
        )
        let preCancelledRequests = await preCancelledClient.allRequests()
        XCTAssertTrue(preCancelledRequests.isEmpty)
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

private actor MCPHTTPClientSlowFake: HealthMdMCPHTTPClient {
    private var started = false
    private var jobID: String?

    func send(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String]
    ) async throws -> HealthMdMCPHTTPResponse {
        started = true
        if let body,
           let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any] {
            jobID = object["job_id"] as? String
        }
        try await Task.sleep(for: .seconds(30))
        return HealthMdMCPHTTPResponse(
            statusCode: 200,
            body: Data(#"{"status":"success","message":"done"}"#.utf8)
        )
    }

    func didStart() -> Bool { started }
    func startedJobID() -> String? { jobID }
}

private struct MCPHTTPClientFailing: HealthMdMCPHTTPClient {
    struct Failure: Error {}

    func send(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String]
    ) async throws -> HealthMdMCPHTTPResponse {
        throw Failure()
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
    private let echoesExportJobID: Bool
    private var requests: [Request] = []

    init(
        response: HealthMdMCPHTTPResponse = .init(
            statusCode: 200,
            body: Data(#"{"status":"ok"}"#.utf8)
        ),
        echoesExportJobID: Bool = false
    ) {
        self.responses = [response]
        self.echoesExportJobID = echoesExportJobID
    }

    init(responses: [HealthMdMCPHTTPResponse]) {
        self.responses = responses
        self.echoesExportJobID = false
    }

    func send(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String]
    ) async throws -> HealthMdMCPHTTPResponse {
        requests.append(Request(method: method, path: path, body: body, headers: headers))
        let response = responses[min(requests.count - 1, responses.count - 1)]
        guard echoesExportJobID, path == "/v1/exports", let body,
              let requestObject = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let jobID = requestObject["job_id"] as? String,
              var responseObject = try? JSONSerialization.jsonObject(with: response.body) as? [String: Any] else {
            return response
        }
        responseObject["job_id"] = jobID
        return HealthMdMCPHTTPResponse(
            statusCode: response.statusCode,
            body: try JSONSerialization.data(withJSONObject: responseObject, options: [.sortedKeys])
        )
    }

    func lastRequest() -> Request? { requests.last }
    func allRequests() -> [Request] { requests }
}
