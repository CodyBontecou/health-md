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

public struct URLSessionHealthMdMCPHTTPClient: HealthMdMCPHTTPClient, Sendable {
    public static let maximumResponseBytes = 2 * 1_024 * 1_024
    private let baseURL: URL
    private let session: URLSession

    public init(baseURL: URL, session: URLSession = .shared) {
        self.baseURL = baseURL
        self.session = session
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
        let isDurableWait = path == "/v1/agent/refresh" || path.hasSuffix("/resume")
        var request = URLRequest(
            url: url,
            timeoutInterval: isDurableWait ? 7 * 24 * 60 * 60 : 30
        )
        request.httpMethod = method
        request.httpBody = body
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
        let (data, response) = try await session.data(for: request)
        guard data.count <= Self.maximumResponseBytes else { throw MCPServerError.responseTooLarge }
        return HealthMdMCPHTTPResponse(
            statusCode: (response as? HTTPURLResponse)?.statusCode ?? 503,
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
    /// The server has no resources, prompts, roots, sampling, shell, SQL, file, or URL-fetch capability.
    public func handle(line: String) async -> String? {
        guard let data = line.data(using: .utf8),
              let request = try? decoder.decode(JSONRPCRequest.self, from: data),
              request.jsonrpc == "2.0" else {
            return encodeResponse(.error(id: nil, code: -32700, message: "Parse error"))
        }
        if request.id == nil {
            // Initialized/cancel notifications intentionally have no response.
            return nil
        }

        switch request.method {
        case "initialize": return handleInitialize(request)
        case "ping": return encodeResponse(.success(id: request.id, result: .object([:])))
        case "tools/list":
            return encodeResponse(.success(
                id: request.id,
                result: .object([
                    "tools": .array(Self.tools.map(\.jsonValue))
                ])
            ))
        case "tools/call": return await handleToolCall(request)
        default:
            return encodeResponse(.error(id: request.id, code: -32601, message: "Method not found"))
        }
    }

    private func handleInitialize(_ request: JSONRPCRequest) -> String? {
        guard let parameters = request.params?.objectValue,
              let requestedVersion = parameters["protocolVersion"]?.stringValue,
              Self.supportedProtocolVersions.contains(requestedVersion) else {
            return encodeResponse(.error(
                id: request.id,
                code: -32602,
                message: "Unsupported MCP protocol version"
            ))
        }
        return encodeResponse(.success(
            id: request.id,
            result: .object([
                "protocolVersion": .string(requestedVersion),
                "capabilities": .object([
                    "tools": .object(["listChanged": .bool(false)])
                ]),
                "serverInfo": .object([
                    "name": .string("healthmd-mcp"),
                    "version": .string("1.0.0")
                ]),
                "instructions": .string(
                    "Health.md returns factual local health context with units, provenance, coverage, and missingness. It does not diagnose or recommend treatment. Use the separate healthmd extract CLI for original healthmd.health_data objects. Set all_pages=true on query tools for complete cursor traversal, or continue next_cursor manually."
                )
            ])
        ))
    }

    private func handleToolCall(_ request: JSONRPCRequest) async -> String? {
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
            return encodeResponse(.success(
                id: request.id,
                result: toolResult(
                    text: text,
                    isError: !(200...299).contains(response.statusCode)
                )
            ))
        } catch {
            return encodeResponse(.success(
                id: request.id,
                result: toolResult(
                    text: #"{"error":"healthmd_unavailable"}"#,
                    isError: true
                )
            ))
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
        repeat {
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
            guard response.body.count <= maximumTraversalBytes - aggregateBytes,
                  pages.count < maximumTraversalPages else {
                let failure = MCPJSONValue.object([
                    "error": .string("query_traversal_aggregate_limit"),
                    "message": .string("Automatic traversal exceeded the bounded MCP aggregate response limit; narrow scope or page manually."),
                    "maximum_aggregate_bytes": .integer(Int64(maximumTraversalBytes)),
                    "maximum_pages": .integer(Int64(maximumTraversalPages)),
                    "completed_pages": .integer(Int64(pages.count))
                ])
                return HealthMdMCPHTTPResponse(
                    statusCode: 413,
                    body: try encoder.encode(failure)
                )
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
                "traversal_complete": .bool(true)
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

    private func toolResult(text: String, isError: Bool) -> MCPJSONValue {
        .object([
            "content": .array([.object([
                "type": .string("text"),
                "text": .string(text)
            ])]),
            "isError": .bool(isError)
        ])
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

        init(
            name: String,
            description: String,
            required: [String],
            properties: [String: MCPJSONValue],
            allowsAdditionalProperties: Bool = true
        ) {
            self.name = name
            self.description = description
            self.required = required
            self.properties = properties
            self.allowsAdditionalProperties = allowsAdditionalProperties
        }

        var jsonValue: MCPJSONValue {
            .object([
                "name": .string(name),
                "description": .string(description),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object(properties),
                    "required": .array(required.map(MCPJSONValue.string)),
                    "additionalProperties": .bool(allowsAdditionalProperties)
                ])
            ])
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
        Tool(name: "healthmd_sleep_sessions", description: "List first-class sleep sessions with optional fixed session-relative window and explicit physiology coverage.", required: ["dates"], properties: typedQueryProperties(extra: ["window": .object(["type": .string("object"), "required": .array([.string("duration_seconds")]), "additionalProperties": .bool(false), "properties": .object(["start_offset_seconds": .object(["type": .string("number"), "minimum": .integer(0)]), "duration_seconds": .object(["type": .string("number"), "exclusiveMinimum": .integer(0), "maximum": .integer(86_400)])])]), "include_naps": .object(["type": .string("boolean")])]), allowsAdditionalProperties: false),
        Tool(name: "healthmd_training_alignment", description: "Align workouts to nearest preceding/following sleep sessions using factual timing only.", required: ["dates"], properties: typedQueryProperties(extra: ["window": .object(["type": .string("object"), "required": .array([.string("duration_seconds")]), "additionalProperties": .bool(false), "properties": .object(["start_offset_seconds": .object(["type": .string("number"), "minimum": .integer(0)]), "duration_seconds": .object(["type": .string("number"), "exclusiveMinimum": .integer(0), "maximum": .integer(86_400)])])]), "workout_activity": stringProperty, "include_naps": .object(["type": .string("boolean")])]), allowsAdditionalProperties: false),
        Tool(name: "healthmd_workouts", description: "List workouts using the typed workout_listing operation.", required: ["dates"], properties: typedQueryProperties(), allowsAdditionalProperties: false),
        Tool(name: "healthmd_coverage", description: "Inspect factual metric/date coverage and explicit missingness.", required: ["dates", "metrics"], properties: typedQueryProperties(), allowsAdditionalProperties: false),
        Tool(name: "healthmd_compare_periods", description: "Compare two exact periods with explicit factual aggregation semantics.", required: ["dates", "metrics", "first", "second", "aggregations"], properties: typedQueryProperties(extra: ["first": queryObject, "second": queryObject, "aggregations": aggregationArrayProperty]), allowsAdditionalProperties: false),
        Tool(name: "healthmd_training_evidence", description: "Create a factual training evidence packet with selected workout details.", required: ["dates"], properties: typedQueryProperties(extra: ["detail_ids": stringArrayProperty]), allowsAdditionalProperties: false),
        Tool(name: "healthmd_query", description: "Run a directly scoped query; set all_pages=true for complete cursor traversal.", required: ["request"], properties: ["request": queryObject, "detail_level": .object(["type": .string("string"), "enum": .array([.string("summary"), .string("lossless")])]), "all_pages": .object(["type": .string("boolean")])]),
        Tool(name: "healthmd_evidence_packet", description: "Create a directly scoped factual evidence packet with optional all_pages traversal.", required: ["request"], properties: ["request": queryObject, "detail_level": .object(["type": .string("string"), "enum": .array([.string("summary"), .string("lossless")])]), "all_pages": .object(["type": .string("boolean")])]),
        Tool(name: "healthmd_refresh", description: "Request explicit iPhone acquisition for the supplied scope; all history remains resumable.", required: ["dates", "metrics", "sources"], properties: ["dates": datesProperty, "metrics": metricsProperty, "sources": queryObject, "detail_level": .object(["type": .string("string"), "enum": .array([.string("summary"), .string("lossless")])]), "wait_timeout_seconds": .object(["type": .string("number"), "minimum": .integer(5), "maximum": .integer(900)])]),
        Tool(name: "healthmd_job_status", description: "Inspect a durable local acquisition job.", required: ["job_id"], properties: ["job_id": stringProperty]),
        Tool(name: "healthmd_job_resume", description: "Resume a durable local acquisition job.", required: ["job_id"], properties: ["job_id": stringProperty]),
        Tool(name: "healthmd_job_cancel", description: "Explicitly cancel a durable local acquisition job.", required: ["job_id"], properties: ["job_id": stringProperty])
    ]
    private static let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
}
