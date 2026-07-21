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
}

public enum MCPServerError: Error, Equatable, Sendable {
    case invalidBaseURL
    case invalidJSON
    case responseTooLarge
}

public struct HealthMdMCPConfiguration: Equatable, Sendable {
    public let baseURL: URL
    public let bearerToken: String?

    public init(
        baseURL: URL = URL(string: "http://127.0.0.1:17645")!,
        bearerToken: String? = nil
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
        self.bearerToken = bearerToken?.trimmingCharacters(in: .whitespacesAndNewlines)
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
        var request = URLRequest(url: url, timeoutInterval: 30)
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
    private let decoder = JSONDecoder()
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return encoder
    }()

    public init(
        configuration: HealthMdMCPConfiguration,
        httpClient: (any HealthMdMCPHTTPClient)? = nil
    ) {
        self.configuration = configuration
        self.httpClient = httpClient ?? URLSessionHealthMdMCPHTTPClient(baseURL: configuration.baseURL)
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
                    "Health.md returns factual local health context with units, provenance, coverage, and missingness. It does not diagnose or recommend treatment. Continue query cursors until next_cursor is absent."
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
        if tool.requiresAuthentication,
           configuration.bearerToken?.isEmpty != false {
            return encodeResponse(.success(
                id: request.id,
                result: toolResult(
                    text: #"{"error":"agent_authentication_required"}"#,
                    isError: true
                )
            ))
        }

        let endpoint: (method: String, path: String, body: Data?)
        do {
            endpoint = try route(for: tool.name, arguments: arguments)
        } catch {
            return encodeResponse(.error(id: request.id, code: -32602, message: "Invalid tool arguments"))
        }
        var headers: [String: String] = [:]
        if let token = configuration.bearerToken, !token.isEmpty {
            headers["Authorization"] = "Bearer \(token)"
        }
        do {
            let response = try await httpClient.send(
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
        case "healthmd_capabilities": return ("GET", "/v1/agent/capabilities", nil)
        case "healthmd_profiles": return ("GET", "/v1/agent/profiles", nil)
        case "healthmd_query": return ("POST", "/v1/agent/query", try encodeObject(arguments))
        case "healthmd_evidence_packet": return ("POST", "/v1/agent/evidence", try encodeObject(arguments))
        case "healthmd_refresh": return ("POST", "/v1/agent/refresh", try encodeObject(arguments))
        case "healthmd_activity": return ("POST", "/v1/agent/activity/query", try encodeObject(arguments))
        case "healthmd_job_status", "healthmd_job_resume", "healthmd_job_cancel":
            guard let id = arguments["job_id"]?.stringValue,
                  let uuid = UUID(uuidString: id) else { throw MCPServerError.invalidJSON }
            let base = "/v1/exports/\(uuid.uuidString.lowercased())"
            switch tool {
            case "healthmd_job_status": return ("GET", base, nil)
            case "healthmd_job_resume": return ("POST", base + "/resume", try encodeObject(arguments))
            default: return ("POST", base + "/cancel", try encodeObject([:]))
            }
        default: throw MCPServerError.invalidJSON
        }
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
        let requiresAuthentication: Bool

        var jsonValue: MCPJSONValue {
            .object([
                "name": .string(name),
                "description": .string(description),
                "inputSchema": .object([
                    "type": .string("object"),
                    "properties": .object(properties),
                    "required": .array(required.map(MCPJSONValue.string)),
                    "additionalProperties": .bool(true)
                ])
            ])
        }
    }

    private static let queryObject: MCPJSONValue = .object([
        "type": .string("object"),
        "description": .string("Versioned Health.md query request plus exact grant/profile reference")
    ])
    private static let stringProperty: MCPJSONValue = .object(["type": .string("string")])

    private static let tools: [Tool] = [
        Tool(name: "healthmd_status", description: "Check the running Mac app and connected iPhone readiness.", required: [], properties: [:], requiresAuthentication: false),
        Tool(name: "healthmd_capabilities", description: "List versioned local query, evidence, refresh, and pagination capabilities.", required: [], properties: [:], requiresAuthentication: true),
        Tool(name: "healthmd_profiles", description: "List Health Context Profiles visible to this registered client.", required: [], properties: [:], requiresAuthentication: true),
        Tool(name: "healthmd_query", description: "Run one authorized paged query. Follow next_cursor until absent to reach every result.", required: ["request", "grant_id", "profile"], properties: ["request": queryObject, "grant_id": stringProperty, "profile": queryObject], requiresAuthentication: true),
        Tool(name: "healthmd_evidence_packet", description: "Create a factual evidence packet with units, coverage, missingness, and resolvable evidence.", required: ["request", "grant_id", "profile"], properties: ["request": queryObject, "grant_id": stringProperty, "profile": queryObject], requiresAuthentication: true),
        Tool(name: "healthmd_refresh", description: "Request explicit iPhone acquisition under an authorized profile; all history remains resumable.", required: ["grant_id", "profile"], properties: ["grant_id": stringProperty, "profile": queryObject], requiresAuthentication: true),
        Tool(name: "healthmd_activity", description: "Read PHI-minimized local agent activity using complete cursor traversal.", required: [], properties: ["cursor": stringProperty], requiresAuthentication: true),
        Tool(name: "healthmd_job_status", description: "Inspect a durable acquisition job owned by this client.", required: ["job_id"], properties: ["job_id": stringProperty], requiresAuthentication: true),
        Tool(name: "healthmd_job_resume", description: "Resume a durable acquisition job owned by this client.", required: ["job_id"], properties: ["job_id": stringProperty], requiresAuthentication: true),
        Tool(name: "healthmd_job_cancel", description: "Explicitly cancel a durable acquisition job owned by this client.", required: ["job_id"], properties: ["job_id": stringProperty], requiresAuthentication: true)
    ]
    private static let toolsByName = Dictionary(uniqueKeysWithValues: tools.map { ($0.name, $0) })
}
