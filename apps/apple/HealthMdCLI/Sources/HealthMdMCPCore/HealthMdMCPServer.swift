import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

public indirect enum MCPJSONValue: Codable, Equatable, Sendable {
    case null
    case bool(Bool)
    case integer(Int64)
    case number(Double)
    case string(String)
    case array([MCPJSONValue])
    case object([String: MCPJSONValue])

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Int64.self) { self = .integer(value) }
        else if let value = try? container.decode(Double.self) {
            guard value.isFinite else { throw MCPServerError.invalidJSON }
            self = .number(value)
        } else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([MCPJSONValue].self) { self = .array(value) }
        else { self = .object(try container.decode([String: MCPJSONValue].self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .null: try container.encodeNil()
        case .bool(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .number(let value):
            guard value.isFinite else { throw MCPServerError.invalidJSON }
            try container.encode(value)
        case .string(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        }
    }

    var objectValue: [String: MCPJSONValue]? {
        guard case .object(let value) = self else { return nil }
        return value
    }

    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var boolValue: Bool? {
        guard case .bool(let value) = self else { return nil }
        return value
    }

    var arrayValue: [MCPJSONValue]? {
        guard case .array(let value) = self else { return nil }
        return value
    }

    var doubleValue: Double? {
        switch self {
        case .integer(let value): return Double(value)
        case .number(let value): return value
        default: return nil
        }
    }
}

public enum MCPServerError: Error, Equatable, Sendable {
    case invalidBaseURL
    case invalidJSON
    case responseTooLarge
}

public struct HealthMdMCPConfiguration: Equatable, Sendable {
    public let baseURL: URL

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:17645")!
    ) throws {
        guard baseURL.scheme?.lowercased() == "http",
              baseURL.user == nil,
              baseURL.password == nil,
              baseURL.query == nil,
              baseURL.fragment == nil,
              baseURL.path.isEmpty || baseURL.path == "/",
              let host = baseURL.host?.lowercased(),
              ["127.0.0.1", "::1", "localhost"].contains(host) else {
            throw MCPServerError.invalidBaseURL
        }
        self.baseURL = baseURL
    }
}

public struct HealthMdMCPHTTPResponse: Equatable, Sendable {
    public let statusCode: Int
    public let body: Data

    public init(statusCode: Int, body: Data) {
        self.statusCode = statusCode
        self.body = body
    }
}

public protocol HealthMdMCPHTTPClient: Sendable {
    func send(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String]
    ) async throws -> HealthMdMCPHTTPResponse
}

private final class HealthMdMCPNoRedirectDelegate: NSObject, URLSessionTaskDelegate, @unchecked Sendable {
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

public struct URLSessionHealthMdMCPHTTPClient: HealthMdMCPHTTPClient, Sendable {
    public static let maximumResponseBytes = 2 * 1_024 * 1_024
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL) {
        self.baseURL = baseURL
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        self.session = URLSession(
            configuration: configuration,
            delegate: HealthMdMCPNoRedirectDelegate(),
            delegateQueue: nil
        )
    }

    public func send(
        method: String,
        path: String,
        body: Data?,
        headers: [String: String]
    ) async throws -> HealthMdMCPHTTPResponse {
        guard path.hasPrefix("/v1/"),
              var components = URLComponents(url: baseURL, resolvingAgainstBaseURL: false) else {
            throw MCPServerError.invalidBaseURL
        }
        components.path = path
        guard let url = components.url else { throw MCPServerError.invalidBaseURL }
        let isDurableWait = path == "/v1/agent/refresh"
            || path == "/v1/exports"
            || path.hasSuffix("/resume")
        var request = URLRequest(
            url: url,
            timeoutInterval: isDurableWait ? 7 * 24 * 60 * 60 : 30
        )
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (bytes, response) = try await session.bytes(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              let finalURL = httpResponse.url,
              finalURL.scheme?.lowercased() == "http",
              finalURL.host?.lowercased() == baseURL.host?.lowercased(),
              finalURL.port == baseURL.port else {
            throw MCPServerError.invalidBaseURL
        }
        let expectedLength = httpResponse.expectedContentLength
        guard expectedLength < 0 || expectedLength <= Self.maximumResponseBytes else {
            throw MCPServerError.responseTooLarge
        }
        var data = Data()
        if expectedLength > 0 {
            data.reserveCapacity(Int(expectedLength))
        }
        for try await byte in bytes {
            guard data.count < Self.maximumResponseBytes else {
                throw MCPServerError.responseTooLarge
            }
            data.append(byte)
        }
        return HealthMdMCPHTTPResponse(
            statusCode: httpResponse.statusCode,
            body: data
        )
    }
}

public actor HealthMdMCPServer {
    public static let supportedProtocolVersions = [
        "2024-11-05", "2025-03-26", "2025-06-18", "2025-11-25"
    ]

    private let configuration: HealthMdMCPConfiguration
    private let httpClient: any HealthMdMCPHTTPClient
    private let maximumTraversalBytes: Int
    private let maximumTraversalPages: Int
    private var uiEnabled = false
    private var inFlightToolCalls: [String: Task<String?, Never>] = [:]
    private var cancelledRequestKeys: Set<String> = []
    private var seenRequestKeys: Set<String> = []
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public init(
        configuration: HealthMdMCPConfiguration,
        httpClient: (any HealthMdMCPHTTPClient)? = nil,
        maximumTraversalBytes: Int = URLSessionHealthMdMCPHTTPClient.maximumResponseBytes,
        maximumTraversalPages: Int = 4_096
    ) {
        self.configuration = configuration
        self.httpClient = httpClient ?? URLSessionHealthMdMCPHTTPClient(baseURL: configuration.baseURL)
        self.maximumTraversalBytes = max(1, maximumTraversalBytes)
        self.maximumTraversalPages = max(1, maximumTraversalPages)
    }

    /// Handles one newline-delimited JSON-RPC message. Notifications return nil.
    /// MCP App resources are exposed only after negotiating `io.modelcontextprotocol/ui`.
    /// The server has no prompts, roots, sampling, shell, SQL, file, or URL-fetch capability.
    public func handle(line: String) async -> String? {
        guard let data = line.data(using: .utf8),
              let request = try? decoder.decode(JSONRPCRequest.self, from: data),
              request.jsonrpc == "2.0" else {
            return encodeResponse(.error(id: nil, code: -32700, message: "Parse error"))
        }
        if request.id == nil {
            if request.method == "notifications/cancelled",
               let cancelledID = request.params?.objectValue?["requestId"],
               let key = requestKey(cancelledID) {
                if let task = inFlightToolCalls[key] {
                    task.cancel()
                } else if !seenRequestKeys.contains(key) {
                    if cancelledRequestKeys.count >= 1_024,
                       let arbitraryKey = cancelledRequestKeys.first {
                        cancelledRequestKeys.remove(arbitraryKey)
                    }
                    cancelledRequestKeys.insert(key)
                }
            }
            // Notifications intentionally have no response.
            return nil
        }
        if let key = requestKey(request.id), !seenRequestKeys.contains(key) {
            if seenRequestKeys.count >= 4_096,
               let arbitraryKey = seenRequestKeys.first {
                seenRequestKeys.remove(arbitraryKey)
            }
            seenRequestKeys.insert(key)
        }

        switch request.method {
        case "initialize": return handleInitialize(request)
        case "ping": return encodeResponse(.success(id: request.id, result: .object([:])))
        case "tools/list":
            return encodeResponse(.success(
                id: request.id,
                result: .object([
                    "tools": .array(Self.tools.map { $0.jsonValue(uiEnabled: uiEnabled) })
                ])
            ))
        case "tools/call": return await handleToolCall(request)
        case "resources/list":
            guard uiEnabled else {
                return encodeResponse(.error(id: request.id, code: -32601, message: "Method not found"))
            }
            return encodeResponse(.success(
                id: request.id,
                result: .object(["resources": .array([HealthMdMCPApp.resourceDeclaration])])
            ))
        case "resources/read": return handleResourceRead(request)
        default:
            return encodeResponse(.error(id: request.id, code: -32601, message: "Method not found"))
        }
    }

    private func handleInitialize(_ request: JSONRPCRequest) -> String? {
        uiEnabled = false
        guard let parameters = request.params?.objectValue,
              let requestedVersion = parameters["protocolVersion"]?.stringValue,
              Self.supportedProtocolVersions.contains(requestedVersion) else {
            return encodeResponse(.error(
                id: request.id,
                code: -32602,
                message: "Unsupported MCP protocol version"
            ))
        }
        uiEnabled = Self.supportsMCPApps(parameters)
        var capabilities: [String: MCPJSONValue] = [
            "tools": .object(["listChanged": .bool(false)])
        ]
        if uiEnabled {
            capabilities["resources"] = .object([
                "subscribe": .bool(false),
                "listChanged": .bool(false)
            ])
            capabilities["extensions"] = .object([
                HealthMdMCPApp.extensionID: .object([
                    "mimeTypes": .array([.string(HealthMdMCPApp.mimeType)])
                ])
            ])
        }
        return encodeResponse(.success(
            id: request.id,
            result: .object([
                "protocolVersion": .string(requestedVersion),
                "capabilities": .object(capabilities),
                "serverInfo": .object([
                    "name": .string("healthmd-mcp"),
                    "version": .string("1.1.0")
                ]),
                "instructions": .string(
                    "Health.md returns factual local health context with units, provenance, coverage, and missingness. It does not diagnose or recommend treatment. Use healthmd_metric_chart for native factual visualizations when available. Use the separate healthmd extract CLI for original healthmd.health_data objects. Set all_pages=true on query tools for complete cursor traversal, or continue next_cursor manually."
                )
            ])
        ))
    }

    private static func supportsMCPApps(_ parameters: [String: MCPJSONValue]) -> Bool {
        guard let capabilities = parameters["capabilities"]?.objectValue,
              let extensions = capabilities["extensions"]?.objectValue,
              let ui = extensions[HealthMdMCPApp.extensionID]?.objectValue,
              let mimeTypes = ui["mimeTypes"]?.arrayValue else { return false }
        return mimeTypes.contains(.string(HealthMdMCPApp.mimeType))
    }

    private func handleResourceRead(_ request: JSONRPCRequest) -> String? {
        guard uiEnabled else {
            return encodeResponse(.error(id: request.id, code: -32601, message: "Method not found"))
        }
        guard let parameters = request.params?.objectValue,
              parameters["uri"]?.stringValue == HealthMdMCPApp.resourceURI else {
            return encodeResponse(.error(id: request.id, code: -32602, message: "Unknown resource URI"))
        }
        return encodeResponse(.success(
            id: request.id,
            result: .object(["contents": .array([HealthMdMCPApp.resourceContent])])
        ))
    }

    private func handleToolCall(_ request: JSONRPCRequest) async -> String? {
        guard let key = requestKey(request.id), inFlightToolCalls[key] == nil else {
            return encodeResponse(.error(
                id: request.id,
                code: -32600,
                message: "Duplicate in-flight request id"
            ))
        }
        if cancelledRequestKeys.remove(key) != nil {
            return encodeResponse(.error(
                id: request.id,
                code: -32800,
                message: "Request cancelled before execution"
            ))
        }
        let task = Task { await self.performToolCall(request) }
        inFlightToolCalls[key] = task
        let response = await task.value
        inFlightToolCalls[key] = nil
        return response
    }

    private func performToolCall(_ request: JSONRPCRequest) async -> String? {
        guard let parameters = request.params?.objectValue,
              let name = parameters["name"]?.stringValue,
              let tool = Self.toolsByName[name] else {
            return encodeResponse(.error(id: request.id, code: -32602, message: "Unknown tool"))
        }
        let arguments = parameters["arguments"]?.objectValue ?? [:]
        let endpoint: (method: String, path: String, body: Data?)
        do {
            endpoint = try route(for: tool.name, arguments: arguments)
        } catch {
            return encodeResponse(.error(id: request.id, code: -32602, message: "Invalid tool arguments"))
        }
        let headers: [String: String] = [:]
        do {
            let shouldTraverse = arguments["all_pages"]?.boolValue == true
                && endpoint.method == "POST"
                && ["/v1/agent/query", "/v1/agent/evidence"].contains(endpoint.path)
            let response = shouldTraverse
                ? try await sendAllQueryPages(endpoint: endpoint, headers: headers)
                : try await httpClient.send(
                    method: endpoint.method,
                    path: endpoint.path,
                    body: endpoint.body,
                    headers: headers
                )
            let text = String(data: response.body, encoding: .utf8)
                ?? #"{"error":"invalid_utf8_response"}"#
            let isError = !(200...299).contains(response.statusCode)
            let canStructureResult = !isError || tool.name.hasPrefix("healthmd_export")
            let expectedExportJobID = exportJobID(for: endpoint)
            let validatedContent = canStructureResult
                ? validatedVisualizationContent(
                    response.body,
                    toolName: tool.name,
                    expectedExportJobID: expectedExportJobID
                )
                : nil
            if tool.name.hasPrefix("healthmd_export"), validatedContent == nil {
                return encodeResponse(.success(
                    id: request.id,
                    result: toolResult(
                        text: invalidExportReceiptText(
                            expectedJobID: expectedExportJobID,
                            statusCode: response.statusCode
                        ),
                        isError: true,
                        structuredContent: nil,
                        additionalContent: []
                    )
                ))
            }
            let structuredContent = uiEnabled && tool.resourceURI != nil
                ? validatedContent
                : nil
            let fallbackImages = !uiEnabled && tool.name == "healthmd_metric_chart" && !isError
                ? HealthMdMCPChartRenderer.imageContents(response.body)
                : []
            return encodeResponse(.success(
                id: request.id,
                result: toolResult(
                    text: text,
                    isError: isError,
                    structuredContent: structuredContent,
                    additionalContent: fallbackImages
                )
            ))
        } catch {
            if Task.isCancelled {
                if let jobID = exportJobID(for: endpoint) {
                    return encodeResponse(.success(
                        id: request.id,
                        result: toolResult(
                            text: cancelledExportWaitText(jobID: jobID),
                            isError: true,
                            structuredContent: nil,
                            additionalContent: []
                        )
                    ))
                }
                return encodeResponse(.error(
                    id: request.id,
                    code: -32800,
                    message: "Request cancelled"
                ))
            }
            return encodeResponse(.success(
                id: request.id,
                result: toolResult(
                    text: transportFailureText(for: endpoint),
                    isError: true,
                    structuredContent: nil,
                    additionalContent: []
                )
            ))
        }
    }

    private func requestKey(_ id: MCPJSONValue?) -> String? {
        switch id {
        case .string(let value): return "s:\(value)"
        case .integer(let value): return "i:\(value)"
        case .number(let value): return "n:\(value.bitPattern)"
        default: return nil
        }
    }

    private func route(
        for tool: String,
        arguments: [String: MCPJSONValue]
    ) throws -> (method: String, path: String, body: Data?) {
        switch tool {
        case "healthmd_status": return ("GET", "/v1/status", nil)
        case "healthmd_doctor": return ("GET", "/v1/agent/readiness", nil)
        case "healthmd_capabilities": return ("GET", "/v1/agent/capabilities", nil)
        case "healthmd_metrics": return ("GET", "/v1/agent/metrics", nil)
        case "healthmd_metric_chart":
            return (
                "POST", "/v1/agent/query",
                try typedQueryBody(
                    arguments,
                    operation: .object(["type": .string("metric_series")]),
                    defaultMetrics: nil
                )
            )
        case "healthmd_sleep_sessions":
            let queryArguments = Self.losslessSleepArguments(
                arguments,
                includingWorkouts: false
            )
            var operation: [String: MCPJSONValue] = [
                "type": .string("sleep_session_listing"),
                "include_naps": arguments["include_naps"] ?? .bool(false)
            ]
            if let window = arguments["window"] { operation["window"] = window }
            return (
                "POST", "/v1/agent/query",
                try typedQueryBody(
                    queryArguments,
                    operation: .object(operation),
                    defaultMetrics: Self.sleepSessionMetrics(includingWorkouts: false),
                    defaultDetailLevel: "lossless"
                )
            )
        case "healthmd_training_alignment":
            let queryArguments = Self.losslessSleepArguments(
                arguments,
                includingWorkouts: true
            )
            var operation: [String: MCPJSONValue] = [
                "type": .string("workout_sleep_alignment"),
                "include_naps": arguments["include_naps"] ?? .bool(false)
            ]
            if let window = arguments["window"] { operation["window"] = window }
            if let activity = arguments["workout_activity"] {
                operation["workout_activity"] = activity
            }
            return (
                "POST", "/v1/agent/query",
                try typedQueryBody(
                    queryArguments,
                    operation: .object(operation),
                    defaultMetrics: Self.sleepSessionMetrics(includingWorkouts: true),
                    defaultDetailLevel: "lossless"
                )
            )
        case "healthmd_workouts":
            return (
                "POST", "/v1/agent/query",
                try typedQueryBody(
                    arguments,
                    operation: .object(["type": .string("workout_listing")]),
                    defaultMetrics: .object([
                        "type": .string("explicit"),
                        "metric_ids": .array([.string("workouts")])
                    ])
                )
            )
        case "healthmd_coverage":
            return (
                "POST", "/v1/agent/query",
                try typedQueryBody(
                    arguments,
                    operation: .object(["type": .string("coverage")]),
                    defaultMetrics: nil
                )
            )
        case "healthmd_compare_periods":
            guard let first = arguments["first"],
                  let second = arguments["second"],
                  let aggregations = arguments["aggregations"] else {
                throw MCPServerError.invalidJSON
            }
            return (
                "POST", "/v1/agent/query",
                try typedQueryBody(
                    arguments,
                    operation: .object([
                        "type": .string("period_comparison"),
                        "first": first,
                        "second": second,
                        "aggregations": aggregations
                    ]),
                    defaultMetrics: nil
                )
            )
        case "healthmd_training_evidence":
            let detailIDs = arguments["detail_ids"] ?? .array([])
            let hasDetailIDs: Bool
            if case .array(let values) = detailIDs { hasDetailIDs = !values.isEmpty }
            else { hasDetailIDs = true }
            return (
                "POST", "/v1/agent/evidence",
                try typedQueryBody(
                    arguments,
                    operation: .object([
                        "type": .string("derive_packet"),
                        "kind": .string("training"),
                        "detail_ids": detailIDs
                    ]),
                    defaultMetrics: .object([
                        "type": .string("explicit"),
                        "metric_ids": .array([.string("workouts")])
                    ]),
                    defaultDetailLevel: hasDetailIDs ? "lossless" : "summary"
                )
            )
        case "healthmd_query": return ("POST", "/v1/agent/query", try encodeAPIArguments(arguments))
        case "healthmd_evidence_packet": return ("POST", "/v1/agent/evidence", try encodeAPIArguments(arguments))
        case "healthmd_export_files":
            return ("POST", "/v1/exports", try fileExportBody(arguments))
        case "healthmd_export_job_status", "healthmd_export_job_resume", "healthmd_export_job_cancel":
            guard let id = arguments["job_id"]?.stringValue,
                  let uuid = UUID(uuidString: id) else { throw MCPServerError.invalidJSON }
            let base = "/v1/exports/\(uuid.uuidString.lowercased())"
            switch tool {
            case "healthmd_export_job_status":
                guard Set(arguments.keys) == Set(["job_id"]) else {
                    throw MCPServerError.invalidJSON
                }
                return ("GET", base, nil)
            case "healthmd_export_job_resume":
                guard Set(arguments.keys).isSubset(of: ["job_id", "wait_timeout_seconds"]) else {
                    throw MCPServerError.invalidJSON
                }
                let body: [String: MCPJSONValue]
                if let timeout = arguments["wait_timeout_seconds"] {
                    guard let value = timeout.doubleValue,
                          value.isFinite, value >= 5, value <= 900 else {
                        throw MCPServerError.invalidJSON
                    }
                    body = ["wait_timeout_seconds": timeout]
                } else {
                    body = [:]
                }
                return ("POST", base + "/resume", try encodeObject(body))
            default:
                guard Set(arguments.keys) == Set(["job_id"]) else {
                    throw MCPServerError.invalidJSON
                }
                return ("POST", base + "/cancel", try encodeObject([:]))
            }
        case "healthmd_refresh": return ("POST", "/v1/agent/refresh", try encodeObject(arguments))
        case "healthmd_job_status", "healthmd_job_resume", "healthmd_job_cancel":
            guard let id = arguments["job_id"]?.stringValue,
                  let uuid = UUID(uuidString: id) else { throw MCPServerError.invalidJSON }
            let base = "/v1/agent/jobs/\(uuid.uuidString.lowercased())"
            switch tool {
            case "healthmd_job_status": return ("GET", base, nil)
            case "healthmd_job_resume": return ("POST", base + "/resume", try encodeObject(arguments))
            default: return ("POST", base + "/cancel", try encodeObject([:]))
            }
        default: throw MCPServerError.invalidJSON
        }
    }

    private func fileExportBody(_ arguments: [String: MCPJSONValue]) throws -> Data {
        let allowedKeys: Set<String> = [
            "date_selection", "date_range", "settings_policy", "metric_ids",
            "categories", "all_metrics", "detail_level", "wait_timeout_seconds"
        ]
        guard Set(arguments.keys).isSubset(of: allowedKeys),
              let dateSelection = arguments["date_selection"]?.stringValue,
              ["explicit_range", "all_available"].contains(dateSelection) else {
            throw MCPServerError.invalidJSON
        }
        let dateRange = arguments["date_range"]
        switch dateSelection {
        case "explicit_range":
            guard let range = dateRange?.objectValue,
                  Set(range.keys) == Set(["start", "end"]),
                  range["start"]?.stringValue?.isEmpty == false,
                  range["end"]?.stringValue?.isEmpty == false else {
                throw MCPServerError.invalidJSON
            }
        case "all_available":
            guard dateRange == nil else { throw MCPServerError.invalidJSON }
        default: throw MCPServerError.invalidJSON
        }
        let settingsPolicy: String
        if let supplied = arguments["settings_policy"] {
            guard let value = supplied.stringValue,
                  ["requested_dates_only", "current_iphone_settings"].contains(value) else {
                throw MCPServerError.invalidJSON
            }
            settingsPolicy = value
        } else {
            settingsPolicy = "requested_dates_only"
        }
        let waitTimeout: MCPJSONValue
        if let supplied = arguments["wait_timeout_seconds"] {
            guard let value = supplied.doubleValue,
                  value.isFinite, value >= 5, value <= 900 else {
                throw MCPServerError.invalidJSON
            }
            waitTimeout = supplied
        } else {
            waitTimeout = .integer(300)
        }

        var body: [String: MCPJSONValue] = [
            "job_id": .string(UUID().uuidString.lowercased()),
            "source": .string("connected_iphone"),
            "date_selection": .string(dateSelection),
            "settings_policy": .string(settingsPolicy),
            "response_mode": .string("write_files"),
            "wait_timeout_seconds": waitTimeout
        ]
        if let dateRange { body["date_range"] = dateRange }

        let selectionKeys = ["metric_ids", "categories", "all_metrics", "detail_level"]
        if selectionKeys.contains(where: { arguments[$0] != nil }) {
            guard settingsPolicy == "requested_dates_only" else {
                throw MCPServerError.invalidJSON
            }
            let metricIDs: [MCPJSONValue]
            if let supplied = arguments["metric_ids"] {
                guard let values = supplied.arrayValue else { throw MCPServerError.invalidJSON }
                metricIDs = values
            } else {
                metricIDs = []
            }
            let categories: [MCPJSONValue]
            if let supplied = arguments["categories"] {
                guard let values = supplied.arrayValue else { throw MCPServerError.invalidJSON }
                categories = values
            } else {
                categories = []
            }
            guard metricIDs.count <= 512,
                  categories.count <= 64,
                  metricIDs.allSatisfy({ $0.stringValue != nil }),
                  categories.allSatisfy({ $0.stringValue != nil }),
                  Set(metricIDs.compactMap(\.stringValue)).count == metricIDs.count,
                  Set(categories.compactMap(\.stringValue)).count == categories.count else {
                throw MCPServerError.invalidJSON
            }
            let allMetrics: Bool
            if let supplied = arguments["all_metrics"] {
                guard let value = supplied.boolValue else { throw MCPServerError.invalidJSON }
                allMetrics = value
            } else {
                allMetrics = false
            }
            guard !(allMetrics && (!metricIDs.isEmpty || !categories.isEmpty)),
                  allMetrics || !metricIDs.isEmpty || !categories.isEmpty else {
                throw MCPServerError.invalidJSON
            }
            let detailLevel: String
            if let supplied = arguments["detail_level"] {
                guard let value = supplied.stringValue,
                      ["summary", "lossless"].contains(value) else {
                    throw MCPServerError.invalidJSON
                }
                detailLevel = value
            } else {
                detailLevel = "summary"
            }
            body["canonical_selection"] = .object([
                "metric_ids": .array(metricIDs),
                "categories": .array(categories),
                "all_metrics": .bool(allMetrics),
                "source_ids": .array([.string("apple_health")]),
                "detail_level": .string(detailLevel),
                "object_paths": .array([]),
                "field_pointers": .array([])
            ])
        }
        return try encodeObject(body)
    }

    private func sendAllQueryPages(
        endpoint: (method: String, path: String, body: Data?),
        headers: [String: String]
    ) async throws -> HealthMdMCPHTTPResponse {
        guard let body = endpoint.body,
              var root = try decoder.decode(MCPJSONValue.self, from: body).objectValue,
              var request = root["request"]?.objectValue,
              var page = request["page"]?.objectValue else {
            throw MCPServerError.invalidJSON
        }
        var pages: [MCPJSONValue] = []
        var cursor: String?
        var seen = Set<String>()
        var itemCount = 0
        var factCount = 0
        var aggregateBytes = 0
        var traversalComplete = true
        var continuationCursor: String?
        var limitReason: String?
        let pageBudget = max(1, maximumTraversalBytes - 16_384)
        repeat {
            if pages.count >= maximumTraversalPages {
                traversalComplete = false
                continuationCursor = cursor
                limitReason = "maximum_pages"
                break
            }
            page["cursor"] = cursor.map(MCPJSONValue.string) ?? .null
            request["page"] = .object(page)
            root["request"] = .object(request)
            let response = try await httpClient.send(
                method: endpoint.method,
                path: endpoint.path,
                body: try encoder.encode(MCPJSONValue.object(root)),
                headers: headers
            )
            guard (200...299).contains(response.statusCode) else { return response }
            guard response.body.count <= pageBudget - aggregateBytes else {
                guard !pages.isEmpty else {
                    let failure = MCPJSONValue.object([
                        "error": .string("query_traversal_aggregate_limit"),
                        "message": .string("One query page exceeded the bounded MCP aggregate response limit; request a smaller page."),
                        "maximum_aggregate_bytes": .integer(Int64(maximumTraversalBytes))
                    ])
                    return HealthMdMCPHTTPResponse(
                        statusCode: 413,
                        body: try encoder.encode(failure)
                    )
                }
                traversalComplete = false
                continuationCursor = cursor
                limitReason = "maximum_aggregate_bytes"
                break
            }
            aggregateBytes += response.body.count
            let value = try decoder.decode(MCPJSONValue.self, from: response.body)
            guard let object = value.objectValue,
                  object["schema"]?.stringValue == "healthmd.query_response" else {
                throw MCPServerError.invalidJSON
            }
            pages.append(value)
            if case .array(let items)? = object["items"] { itemCount += items.count }
            if let packet = object["packet"]?.objectValue,
               case .array(let facts)? = packet["facts"] { factCount += facts.count }
            cursor = object["next_cursor"]?.stringValue
            if let cursor {
                guard seen.insert(cursor).inserted else {
                    throw MCPServerError.invalidJSON
                }
            }
        } while cursor != nil

        let result = MCPJSONValue.object([
            "schema": .string("healthmd.mcp_query_pages"),
            "schema_version": .integer(1),
            "pages": .array(pages),
            "receipt": .object([
                "page_count": .integer(Int64(pages.count)),
                "item_count": .integer(Int64(itemCount)),
                "packet_fact_count": .integer(Int64(factCount)),
                "traversal_complete": .bool(traversalComplete),
                "next_cursor": continuationCursor.map(MCPJSONValue.string) ?? .null,
                "limit_reason": limitReason.map(MCPJSONValue.string) ?? .null
            ])
        ])
        let resultBody = try encoder.encode(result)
        guard resultBody.count <= maximumTraversalBytes else {
            let failure = MCPJSONValue.object([
                "error": .string("query_traversal_aggregate_limit"),
                "message": .string("The aggregated MCP response exceeded its bounded output limit; narrow scope or page manually.")
            ])
            return HealthMdMCPHTTPResponse(statusCode: 413, body: try encoder.encode(failure))
        }
        return HealthMdMCPHTTPResponse(statusCode: 200, body: resultBody)
    }

    private static func losslessSleepArguments(
        _ arguments: [String: MCPJSONValue],
        includingWorkouts: Bool
    ) -> [String: MCPJSONValue] {
        var result = arguments
        result["detail_level"] = .string("lossless")
        guard var metrics = result["metrics"]?.objectValue,
              metrics["type"]?.stringValue == "explicit",
              case .array(let requested)? = metrics["metric_ids"] else {
            return result
        }
        let required = sleepMetricIDs(includingWorkouts: includingWorkouts)
        let combined = Set(requested.compactMap(\.stringValue)).union(required)
        metrics["metric_ids"] = .array(combined.sorted().map(MCPJSONValue.string))
        result["metrics"] = .object(metrics)
        return result
    }

    private static func sleepMetricIDs(includingWorkouts: Bool) -> [String] {
        var metricIDs = [
            "sleep_total", "sleep_bedtime", "sleep_wake", "sleep_deep",
            "sleep_rem", "sleep_core", "sleep_awake", "sleep_in_bed"
        ]
        if includingWorkouts { metricIDs.append("workouts") }
        return metricIDs
    }

    private static func sleepSessionMetrics(includingWorkouts: Bool) -> MCPJSONValue {
        let metricIDs = sleepMetricIDs(includingWorkouts: includingWorkouts)
        return .object([
            "type": .string("explicit"),
            "metric_ids": .array(metricIDs.sorted().map(MCPJSONValue.string))
        ])
    }

    private func typedQueryBody(
        _ arguments: [String: MCPJSONValue],
        operation: MCPJSONValue,
        defaultMetrics: MCPJSONValue?,
        defaultDetailLevel: String = "summary"
    ) throws -> Data {
        guard let dates = arguments["dates"],
              let metrics = arguments["metrics"] ?? defaultMetrics else {
            throw MCPServerError.invalidJSON
        }
        let sources = arguments["sources"] ?? .object(["type": .string("all_available")])
        let page = arguments["page"] ?? .object([
            "max_items": .integer(250),
            "max_bytes": .integer(262_144),
            "cursor": .null
        ])
        let body: [String: MCPJSONValue] = [
            "detail_level": arguments["detail_level"] ?? .string(defaultDetailLevel),
            "request": .object([
                "schema": .string("healthmd.query_request"),
                "schema_version": .integer(1),
                "metrics": metrics,
                "sources": sources,
                "dates": dates,
                "operation": operation,
                "page": page
            ])
        ]
        return try encodeObject(body)
    }

    private func encodeAPIArguments(
        _ object: [String: MCPJSONValue]
    ) throws -> Data {
        var filtered = object
        filtered.removeValue(forKey: "all_pages")
        return try encodeObject(filtered)
    }

    private func encodeObject(_ object: [String: MCPJSONValue]) throws -> Data {
        try encoder.encode(MCPJSONValue.object(object))
    }

    private func transportFailureText(
        for endpoint: (method: String, path: String, body: Data?)
    ) -> String {
        guard endpoint.path == "/v1/exports" || endpoint.path.hasPrefix("/v1/exports/") else {
            return #"{"error":"healthmd_unavailable"}"#
        }
        let jobID = exportJobID(for: endpoint)
        var error: [String: MCPJSONValue] = [
            "error": .string("healthmd_unavailable"),
            "operation_outcome": .string("unknown"),
            "message": .string("The durable export may still be running. Inspect its status before retrying.")
        ]
        if let jobID { error["job_id"] = .string(jobID) }
        guard let data = try? encoder.encode(MCPJSONValue.object(error)) else {
            return #"{"error":"healthmd_unavailable","operation_outcome":"unknown"}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func exportJobID(
        for endpoint: (method: String, path: String, body: Data?)
    ) -> String? {
        if endpoint.path == "/v1/exports",
           let body = endpoint.body,
           let object = try? decoder.decode(MCPJSONValue.self, from: body).objectValue,
           let value = object["job_id"]?.stringValue,
           let uuid = UUID(uuidString: value) {
            return uuid.uuidString.lowercased()
        }
        let parts = endpoint.path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count >= 3, parts[0] == "v1", parts[1] == "exports",
              let uuid = UUID(uuidString: String(parts[2])) else { return nil }
        return uuid.uuidString.lowercased()
    }

    private func validatedVisualizationContent(
        _ data: Data,
        toolName: String,
        expectedExportJobID: String?
    ) -> MCPJSONValue? {
        guard let decoded = try? decoder.decode(MCPJSONValue.self, from: data),
              let object = decoded.objectValue else { return nil }
        if toolName.hasPrefix("healthmd_export") {
            let validStatuses = Set([
                "accepted", "preparing", "success", "partial_success", "failure",
                "cancelled", "unavailable", "timed_out"
            ])
            guard let status = object["status"]?.stringValue,
                  validStatuses.contains(status),
                  object["message"]?.stringValue != nil else { return nil }
            guard let expectedExportJobID,
                  let value = object["job_id"]?.stringValue,
                  let uuid = UUID(uuidString: value),
                  uuid.uuidString.lowercased() == expectedExportJobID else { return nil }
            return .object([
                "schema": .string("healthmd.mcp_export_result"),
                "schema_version": .integer(1),
                "operation": .string(toolName),
                "response": .object(object)
            ])
        }
        guard object["schema_version"] == .integer(1),
              let schema = object["schema"]?.stringValue,
              ["healthmd.query_response", "healthmd.mcp_query_pages"].contains(schema) else {
            return nil
        }
        return decoded
    }

    private func cancelledExportWaitText(jobID: String) -> String {
        let error = MCPJSONValue.object([
            "error": .string("healthmd_export_wait_cancelled"),
            "job_id": .string(jobID),
            "operation_outcome": .string("unknown"),
            "message": .string(
                "The MCP waiter detached. An accepted durable export continues independently; inspect this job ID before retrying."
            )
        ])
        guard let data = try? encoder.encode(error) else {
            return #"{"error":"healthmd_export_wait_cancelled"}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func invalidExportReceiptText(
        expectedJobID: String?,
        statusCode: Int
    ) -> String {
        var error: [String: MCPJSONValue] = [
            "error": .string("healthmd_export_receipt_invalid"),
            "http_status": .integer(Int64(statusCode)),
            "message": .string(
                "Health.md returned an invalid or mismatched durable export receipt. Inspect this job ID before retrying a mutation."
            )
        ]
        if let expectedJobID { error["job_id"] = .string(expectedJobID) }
        guard let data = try? encoder.encode(MCPJSONValue.object(error)) else {
            return #"{"error":"healthmd_export_receipt_invalid"}"#
        }
        return String(decoding: data, as: UTF8.self)
    }

    private func toolResult(
        text: String,
        isError: Bool,
        structuredContent: MCPJSONValue?,
        additionalContent: [MCPJSONValue]
    ) -> MCPJSONValue {
        let textContent = MCPJSONValue.object([
            "type": .string("text"),
            "text": .string(text)
        ])
        var result: [String: MCPJSONValue] = [
            "content": .array([textContent] + additionalContent),
            "isError": .bool(isError)
        ]
        if let structuredContent { result["structuredContent"] = structuredContent }
        return .object(result)
    }

    private func encodeResponse(_ response: JSONRPCResponse) -> String? {
        guard let data = try? encoder.encode(response) else { return nil }
        return String(decoding: data, as: UTF8.self)
    }

    private struct JSONRPCRequest: Decodable {
        let jsonrpc: String
        let id: MCPJSONValue?
        let method: String
        let params: MCPJSONValue?
    }

    private struct JSONRPCResponse: Encodable {
        let jsonrpc = "2.0"
        let id: MCPJSONValue?
        let result: MCPJSONValue?
        let error: RPCError?

        static func success(id: MCPJSONValue?, result: MCPJSONValue) -> Self {
            Self(id: id, result: result, error: nil)
        }

        static func error(id: MCPJSONValue?, code: Int, message: String) -> Self {
            Self(id: id, result: nil, error: RPCError(code: code, message: message))
        }

        struct RPCError: Encodable {
            let code: Int
            let message: String
        }
    }

    private struct Tool: Sendable {
        let name: String
        let description: String
        let required: [String]
        let properties: [String: MCPJSONValue]
        let allowsAdditionalProperties: Bool
        let resourceURI: String?
        let annotations: MCPJSONValue?
        let metadata: [String: MCPJSONValue]

        init(
            name: String,
            description: String,
            required: [String],
            properties: [String: MCPJSONValue],
            allowsAdditionalProperties: Bool = true,
            resourceURI: String? = nil,
            annotations: MCPJSONValue? = nil,
            metadata: [String: MCPJSONValue] = [:]
        ) {
            self.name = name
            self.description = description
            self.required = required
            self.properties = properties
            self.allowsAdditionalProperties = allowsAdditionalProperties
            self.resourceURI = resourceURI
            self.annotations = annotations
            self.metadata = metadata
        }

        func jsonValue(uiEnabled: Bool) -> MCPJSONValue {
            var value: [String: MCPJSONValue] = [
                "name": .string(name),
                "description": .string(description),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object(properties),
                    "required": .array(required.map(MCPJSONValue.string)),
                    "additionalProperties": .bool(allowsAdditionalProperties)
                ])
            ]
            if let annotations { value["annotations"] = annotations }
            var resolvedMetadata = metadata
            if uiEnabled, let resourceURI {
                resolvedMetadata["ui"] = .object([
                    "resourceUri": .string(resourceURI),
                    "visibility": .array([.string("model")])
                ])
            }
            if !resolvedMetadata.isEmpty { value["_meta"] = .object(resolvedMetadata) }
            return .object(value)
        }
    }

    private static let queryObject: MCPJSONValue = .object([
        "type": .string("object"),
        "description": .string("Versioned Health.md request object")
    ])
    private static let stringProperty: MCPJSONValue = .object(["type": .string("string")])
    private static let stringArrayProperty: MCPJSONValue = .object([
        "type": .string("array"),
        "items": .object(["type": .string("string")])
    ])
    private static let datesProperty: MCPJSONValue = .object([
        "type": .string("object"),
        "description": .string("healthmd.query_request/1 exact or all_available date selector")
    ])
    private static let metricsProperty: MCPJSONValue = .object([
        "type": .string("object"),
        "description": .string("Explicit or all_available canonical metric selector")
    ])
    private static let pageProperty: MCPJSONValue = .object([
        "type": .string("object"),
        "description": .string("Bounded max_items/max_bytes controls and optional cursor")
    ])
    private static let exportDateRangeProperty: MCPJSONValue = .object([
        "type": .string("object"),
        "required": .array([.string("start"), .string("end")]),
        "additionalProperties": .bool(false),
        "properties": .object([
            "start": .object([
                "type": .string("string"),
                "description": .string("Inclusive yyyy-MM-dd start date")
            ]),
            "end": .object([
                "type": .string("string"),
                "description": .string("Inclusive yyyy-MM-dd end date")
            ])
        ])
    ])
    private static let writeAnnotations: MCPJSONValue = .object([
        "readOnlyHint": .bool(false),
        "destructiveHint": .bool(true),
        "idempotentHint": .bool(false),
        "openWorldHint": .bool(false)
    ])
    private static let readAnnotations: MCPJSONValue = .object([
        "readOnlyHint": .bool(true),
        "destructiveHint": .bool(false),
        "idempotentHint": .bool(true),
        "openWorldHint": .bool(false)
    ])
    private static let requiresUserInteraction: [String: MCPJSONValue] = [
        "anthropic/requiresUserInteraction": .bool(true)
    ]
    private static let aggregationArrayProperty: MCPJSONValue = .object([
        "type": .string("array"),
        "items": .object([
            "type": .string("object"),
            "required": .array([.string("metric_id"), .string("kind")]),
            "additionalProperties": .bool(false),
            "properties": .object([
                "metric_id": stringProperty,
                "kind": .object([
                    "type": .string("string"),
                    "enum": .array([
                        .string("sum"), .string("average"), .string("minimum"),
                        .string("maximum"), .string("latest"), .string("count"),
                        .string("duration_sum")
                    ])
                ]),
                "expected_unit": stringProperty
            ])
        ])
    ])

    private static func typedQueryProperties(
        extra: [String: MCPJSONValue] = [:]
    ) -> [String: MCPJSONValue] {
        var properties: [String: MCPJSONValue] = [
            "dates": datesProperty,
            "metrics": metricsProperty,
            "sources": queryObject,
            "detail_level": .object([
                "type": .string("string"),
                "enum": .array([.string("summary"), .string("lossless")])
            ]),
            "page": pageProperty,
            "all_pages": .object([
                "type": .string("boolean"),
                "description": .string("Traverse opaque cursors within bounded aggregate limits and return healthmd.mcp_query_pages/1")
            ])
        ]
        properties.merge(extra) { _, replacement in replacement }
        return properties
    }

    private static let tools: [Tool] = [
        Tool(name: "healthmd_status", description: "Check the running Mac app and connected iPhone readiness.", required: [], properties: [:]),
        Tool(name: "healthmd_doctor", description: "Diagnose encrypted-cache and fresh-iPhone readiness with actionable next steps.", required: [], properties: [:]),
        Tool(name: "healthmd_capabilities", description: "List versioned local query, evidence, refresh, and pagination capabilities.", required: [], properties: [:]),
        Tool(name: "healthmd_metrics", description: "List canonical queryable metric IDs, categories, units, and availability requirements.", required: [], properties: [:], allowsAdditionalProperties: false),
        Tool(name: "healthmd_metric_chart", description: "Query factual metric series and render an in-app chart with units, coverage, missingness, evidence, and limitations.", required: ["dates", "metrics"], properties: typedQueryProperties(), allowsAdditionalProperties: false, resourceURI: HealthMdMCPApp.resourceURI),
        Tool(name: "healthmd_sleep_sessions", description: "List and visualize first-class sleep sessions with optional fixed session-relative window and explicit physiology coverage.", required: ["dates"], properties: typedQueryProperties(extra: ["window": .object(["type": .string("object"), "required": .array([.string("duration_seconds")]), "additionalProperties": .bool(false), "properties": .object(["start_offset_seconds": .object(["type": .string("number"), "minimum": .integer(0)]), "duration_seconds": .object(["type": .string("number"), "exclusiveMinimum": .integer(0), "maximum": .integer(86_400)])])]), "include_naps": .object(["type": .string("boolean")])]), allowsAdditionalProperties: false, resourceURI: HealthMdMCPApp.resourceURI),
        Tool(name: "healthmd_training_alignment", description: "Align and visualize workouts against nearest preceding/following sleep sessions using factual timing only.", required: ["dates"], properties: typedQueryProperties(extra: ["window": .object(["type": .string("object"), "required": .array([.string("duration_seconds")]), "additionalProperties": .bool(false), "properties": .object(["start_offset_seconds": .object(["type": .string("number"), "minimum": .integer(0)]), "duration_seconds": .object(["type": .string("number"), "exclusiveMinimum": .integer(0), "maximum": .integer(86_400)])])]), "workout_activity": stringProperty, "include_naps": .object(["type": .string("boolean")])]), allowsAdditionalProperties: false, resourceURI: HealthMdMCPApp.resourceURI),
        Tool(name: "healthmd_workouts", description: "List and visualize workouts using the typed workout_listing operation.", required: ["dates"], properties: typedQueryProperties(), allowsAdditionalProperties: false, resourceURI: HealthMdMCPApp.resourceURI),
        Tool(name: "healthmd_coverage", description: "Inspect and visualize factual metric/date coverage and explicit missingness.", required: ["dates", "metrics"], properties: typedQueryProperties(), allowsAdditionalProperties: false, resourceURI: HealthMdMCPApp.resourceURI),
        Tool(name: "healthmd_compare_periods", description: "Compare and visualize two exact periods with explicit factual aggregation semantics.", required: ["dates", "metrics", "first", "second", "aggregations"], properties: typedQueryProperties(extra: ["first": queryObject, "second": queryObject, "aggregations": aggregationArrayProperty]), allowsAdditionalProperties: false, resourceURI: HealthMdMCPApp.resourceURI),
        Tool(name: "healthmd_training_evidence", description: "Create and visualize a factual training evidence packet with selected workout details.", required: ["dates"], properties: typedQueryProperties(extra: ["detail_ids": stringArrayProperty]), allowsAdditionalProperties: false, resourceURI: HealthMdMCPApp.resourceURI),
        Tool(name: "healthmd_query", description: "Run and visualize a directly scoped query; set all_pages=true for complete cursor traversal.", required: ["request"], properties: ["request": queryObject, "detail_level": .object(["type": .string("string"), "enum": .array([.string("summary"), .string("lossless")])]), "all_pages": .object(["type": .string("boolean")])], resourceURI: HealthMdMCPApp.resourceURI),
        Tool(name: "healthmd_evidence_packet", description: "Create and visualize a directly scoped factual evidence packet with optional all_pages traversal.", required: ["request"], properties: ["request": queryObject, "detail_level": .object(["type": .string("string"), "enum": .array([.string("summary"), .string("lossless")])]), "all_pages": .object(["type": .string("boolean")])], resourceURI: HealthMdMCPApp.resourceURI),
        Tool(name: "healthmd_export_files", description: "After explicit user approval, run a durable connected-iPhone export into the folder already selected in Health.md. Use explicit_range with date_range, or all_available without date_range. Optional metric/category/all-metrics selection may include summary/lossless detail and narrows iPhone acquisition without changing saved settings.", required: ["date_selection"], properties: ["date_selection": .object(["type": .string("string"), "enum": .array([.string("explicit_range"), .string("all_available")])]), "date_range": exportDateRangeProperty, "settings_policy": .object(["type": .string("string"), "enum": .array([.string("requested_dates_only"), .string("current_iphone_settings")])]), "metric_ids": .object(["type": .string("array"), "maxItems": .integer(512), "uniqueItems": .bool(true), "items": .object(["type": .string("string")])]), "categories": .object(["type": .string("array"), "maxItems": .integer(64), "uniqueItems": .bool(true), "items": .object(["type": .string("string")])]), "all_metrics": .object(["type": .string("boolean")]), "detail_level": .object(["type": .string("string"), "enum": .array([.string("summary"), .string("lossless")])]), "wait_timeout_seconds": .object(["type": .string("number"), "minimum": .integer(5), "maximum": .integer(900)])], allowsAdditionalProperties: false, resourceURI: HealthMdMCPApp.resourceURI, annotations: writeAnnotations, metadata: requiresUserInteraction),
        Tool(name: "healthmd_export_job_status", description: "Inspect a durable generated-file export job and its destination/progress receipt.", required: ["job_id"], properties: ["job_id": stringProperty], allowsAdditionalProperties: false, resourceURI: HealthMdMCPApp.resourceURI, annotations: readAnnotations),
        Tool(name: "healthmd_export_job_resume", description: "After explicit user approval, resume the exact immutable durable generated-file export job.", required: ["job_id"], properties: ["job_id": stringProperty, "wait_timeout_seconds": .object(["type": .string("number"), "minimum": .integer(5), "maximum": .integer(900)])], allowsAdditionalProperties: false, resourceURI: HealthMdMCPApp.resourceURI, annotations: writeAnnotations, metadata: requiresUserInteraction),
        Tool(name: "healthmd_export_job_cancel", description: "After explicit user approval, explicitly cancel a durable generated-file export job. This cannot be undone.", required: ["job_id"], properties: ["job_id": stringProperty], allowsAdditionalProperties: false, resourceURI: HealthMdMCPApp.resourceURI, annotations: .object(["readOnlyHint": .bool(false), "destructiveHint": .bool(true), "idempotentHint": .bool(true), "openWorldHint": .bool(false)]), metadata: requiresUserInteraction),
        Tool(name: "healthmd_refresh", description: "After explicit user approval, request iPhone acquisition for the supplied scope; all history remains resumable.", required: ["dates", "metrics", "sources"], properties: ["dates": datesProperty, "metrics": metricsProperty, "sources": queryObject, "detail_level": .object(["type": .string("string"), "enum": .array([.string("summary"), .string("lossless")])]), "wait_timeout_seconds": .object(["type": .string("number"), "minimum": .integer(5), "maximum": .integer(900)])], annotations: writeAnnotations, metadata: requiresUserInteraction),
        Tool(name: "healthmd_job_status", description: "Inspect a durable local acquisition job.", required: ["job_id"], properties: ["job_id": stringProperty], annotations: readAnnotations),
        Tool(name: "healthmd_job_resume", description: "After explicit user approval, resume a durable local acquisition job.", required: ["job_id"], properties: ["job_id": stringProperty], annotations: writeAnnotations, metadata: requiresUserInteraction),
        Tool(name: "healthmd_job_cancel", description: "After explicit user approval, explicitly cancel a durable local acquisition job.", required: ["job_id"], properties: ["job_id": stringProperty], annotations: .object(["readOnlyHint": .bool(false), "destructiveHint": .bool(true), "idempotentHint": .bool(true), "openWorldHint": .bool(false)]), metadata: requiresUserInteraction)
    ]
    private static let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
}
