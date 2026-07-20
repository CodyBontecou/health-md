#if os(macOS)
import Combine
import Foundation
import Network

@MainActor
final class HealthMdControlServer: ObservableObject {
    struct StatusResponse: Codable {
        struct IPhone: Codable {
            let connected: Bool
            let name: String?
            let canTriggerExports: Bool
            let canTriggerRawExports: Bool

            enum CodingKeys: String, CodingKey {
                case connected
                case name
                case canTriggerExports = "can_trigger_exports"
                case canTriggerRawExports = "can_trigger_raw_exports"
            }
        }

        struct Destination: Codable {
            let selected: Bool
            let writable: Bool
            let path: String?
            let displayName: String?

            enum CodingKeys: String, CodingKey {
                case selected
                case writable
                case path
                case displayName = "display_name"
            }
        }

        struct ActiveExport: Codable {
            let jobID: UUID?
            let message: String?
            let fractionComplete: Double?
            let durable: Bool?
            let paused: Bool?
            let processedDays: Int?
            let totalDays: Int?
            let expiresAt: Date?
            let state: String?
            let sessionID: UUID?
            let committedPartitions: Int?
            let committedBytes: Int64?

            enum CodingKeys: String, CodingKey {
                case jobID = "job_id"
                case message
                case fractionComplete = "fraction_complete"
                case durable
                case paused
                case processedDays = "processed_days"
                case totalDays = "total_days"
                case expiresAt = "expires_at"
                case state
                case sessionID = "session_id"
                case committedPartitions = "committed_partitions"
                case committedBytes = "committed_bytes"
            }

            init(
                jobID: UUID?,
                message: String?,
                fractionComplete: Double?,
                durable: Bool? = nil,
                paused: Bool? = nil,
                processedDays: Int? = nil,
                totalDays: Int? = nil,
                expiresAt: Date? = nil,
                state: String? = nil,
                sessionID: UUID? = nil,
                committedPartitions: Int? = nil,
                committedBytes: Int64? = nil
            ) {
                self.jobID = jobID
                self.message = message
                self.fractionComplete = fractionComplete
                self.durable = durable
                self.paused = paused
                self.processedDays = processedDays
                self.totalDays = totalDays
                self.expiresAt = expiresAt
                self.state = state
                self.sessionID = sessionID
                self.committedPartitions = committedPartitions
                self.committedBytes = committedBytes
            }
        }

        let macApp: String
        let iphone: IPhone
        let destination: Destination
        let activeExport: ActiveExport?

        enum CodingKeys: String, CodingKey {
            case macApp = "mac_app"
            case iphone
            case destination
            case activeExport = "active_export"
        }
    }

    struct ParsedHTTPRequest {
        let method: String
        let path: String
        let headers: [String: String]
        let body: Data
    }

    enum RequestFramingDecision: Equatable {
        case incomplete
        case complete(expectedLength: Int)
        case reject(statusCode: Int, error: String)
    }

    enum RequestValidationDecision: Equatable {
        case valid
        case reject(statusCode: Int, error: String)
    }

    private struct ExportRequestBody: Codable {
        struct DateRange: Codable {
            let start: String
            let end: String
        }

        let jobID: UUID?
        let source: String?
        let dateRange: DateRange?
        let from: String?
        let to: String?
        let settingsPolicy: String?
        let responseMode: String?
        let rawProfile: String?
        let waitTimeoutSeconds: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case jobID = "job_id"
            case source
            case dateRange = "date_range"
            case from
            case to
            case settingsPolicy = "settings_policy"
            case responseMode = "response_mode"
            case rawProfile = "raw_profile"
            case waitTimeoutSeconds = "wait_timeout_seconds"
        }
    }

    private struct ResumeRequestBody: Codable {
        let waitTimeoutSeconds: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case waitTimeoutSeconds = "wait_timeout_seconds"
        }
    }

    private struct RequestRejection: Error {
        let statusCode: Int
        let error: String
    }

    enum HTTPResponseBody {
        case data(Data)
        /// A protected spool streamed to the loopback client in bounded chunks.
        /// When cleanup is true, ownership transfers to the response sender.
        case file(url: URL, length: Int64, sha256: String, cleanup: Bool)

        var length: Int64 {
            switch self {
            case .data(let data): return Int64(data.count)
            case .file(_, let length, _, _): return length
            }
        }
    }

    struct HTTPResponse {
        let statusCode: Int
        let body: HTTPResponseBody
        let headers: [String: String]

        init(statusCode: Int, body: HTTPResponseBody, headers: [String: String] = [:]) {
            self.statusCode = statusCode
            self.body = body
            self.headers = headers
        }
    }

    /// Authentication can be added behind this boundary later. For now the
    /// listener and accepted peer endpoint must both be loopback.
    private enum AuthorizationBoundary {
        case loopbackOnly
    }

    nonisolated static let maximumHeaderBytes = 16 * 1024
    nonisolated static let maximumBodyBytes = 256 * 1024
    nonisolated static let receiveDeadlineSeconds: TimeInterval = 10
    nonisolated static let minimumWaitTimeoutSeconds: TimeInterval = 5
    nonisolated static let maximumWaitTimeoutSeconds: TimeInterval = 900

    private let port: NWEndpoint.Port = 17645
    private let authorizationBoundary: AuthorizationBoundary = .loopbackOnly
    private var listeners: [NWListener] = []
    private var readyListenerIDs: Set<ObjectIdentifier> = []
    private var receiveDeadlineTasks: [ObjectIdentifier: Task<Void, Never>] = [:]
    private var statusProvider: (() -> StatusResponse)?
    private var exportHandler: ((MacIPhoneExportRequestCoordinator.ExportRequest) async -> MacIPhoneExportRequestCoordinator.ExportResponse)?
    private var jobStatusHandler: ((UUID) -> MacIPhoneExportRequestCoordinator.ExportResponse)?
    private var resumeExportHandler: ((UUID, TimeInterval) async -> MacIPhoneExportRequestCoordinator.ExportResponse)?
    private var explicitCancelExportHandler: ((UUID) -> MacIPhoneExportRequestCoordinator.ExportResponse)?
    /// Detaches only the transient HTTP waiter when a client closes early.
    private var cancelExportHandler: ((UUID) -> Void)?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    @Published private(set) var isRunning = false
    @Published private(set) var endpointDescription = "http://127.0.0.1:17645 (also http://[::1]:17645)"

    func start(
        statusProvider: @escaping () -> StatusResponse,
        exportHandler: @escaping (MacIPhoneExportRequestCoordinator.ExportRequest) async -> MacIPhoneExportRequestCoordinator.ExportResponse,
        jobStatusHandler: ((UUID) -> MacIPhoneExportRequestCoordinator.ExportResponse)? = nil,
        resumeExportHandler: ((UUID, TimeInterval) async -> MacIPhoneExportRequestCoordinator.ExportResponse)? = nil,
        explicitCancelExportHandler: ((UUID) -> MacIPhoneExportRequestCoordinator.ExportResponse)? = nil,
        cancelExportHandler: ((UUID) -> Void)? = nil
    ) {
        self.statusProvider = statusProvider
        self.exportHandler = exportHandler
        self.jobStatusHandler = jobStatusHandler
        self.resumeExportHandler = resumeExportHandler
        self.explicitCancelExportHandler = explicitCancelExportHandler
        self.cancelExportHandler = cancelExportHandler
        guard listeners.isEmpty else { return }

        for host in [NWEndpoint.Host("127.0.0.1"), NWEndpoint.Host("::1")] {
            do {
                let parameters = NWParameters.tcp
                parameters.allowLocalEndpointReuse = true
                parameters.requiredLocalEndpoint = .hostPort(host: host, port: port)
                let listener = try NWListener(using: parameters)
                let listenerID = ObjectIdentifier(listener)
                listener.newConnectionHandler = { connection in
                    connection.start(queue: .main)
                    Task { @MainActor [weak self, connection] in
                        self?.handle(connection: connection)
                    }
                }
                listener.stateUpdateHandler = { state in
                    Task { @MainActor [weak self] in
                        self?.updateListenerState(state, listenerID: listenerID)
                    }
                }
                listeners.append(listener)
                listener.start(queue: .main)
            } catch {
                // The other loopback family may still be available.
            }
        }
        isRunning = false
    }

    func stop() {
        listeners.forEach { $0.cancel() }
        listeners.removeAll()
        readyListenerIDs.removeAll()
        receiveDeadlineTasks.values.forEach { $0.cancel() }
        receiveDeadlineTasks.removeAll()
        isRunning = false
    }

    private func updateListenerState(_ state: NWListener.State, listenerID: ObjectIdentifier) {
        switch state {
        case .ready:
            readyListenerIDs.insert(listenerID)
        case .failed, .cancelled:
            readyListenerIDs.remove(listenerID)
        default:
            break
        }
        isRunning = !readyListenerIDs.isEmpty
    }

    private func handle(connection: NWConnection) {
        switch authorizationBoundary {
        case .loopbackOnly:
            guard Self.isLoopbackEndpoint(connection.endpoint) else {
                send(jsonResponse(statusCode: 403, value: ["error": "loopback_required"]), on: connection)
                return
            }
        }

        let connectionID = ObjectIdentifier(connection)
        receiveDeadlineTasks[connectionID] = Task { [weak self, weak connection] in
            do {
                try await Task.sleep(nanoseconds: UInt64(Self.receiveDeadlineSeconds * 1_000_000_000))
            } catch {
                return
            }
            guard !Task.isCancelled, let self, let connection else { return }
            self.expireReceive(on: connection, connectionID: connectionID)
        }

        receiveRequest(connection: connection, connectionID: connectionID, accumulated: Data()) { [weak self] result in
            Task { @MainActor in
                guard let self, self.finishReceiving(connectionID: connectionID) else { return }
                switch result {
                case .success(let data):
                    do {
                        var request = try Self.parseCompleteRequest(data)
                        if request.method == "POST", request.path == "/v1/exports" {
                            let jobID: UUID
                            if let supplied = Self.exportJobID(from: request.body) {
                                jobID = supplied
                            } else {
                                jobID = UUID()
                                request = try Self.requestByInjectingExportJobID(jobID, into: request)
                            }
                            self.monitorClientClosure(on: connection, jobID: jobID)
                        } else if request.method == "POST",
                                  let route = Self.exportJobRoute(request.path),
                                  route.action == "resume" {
                            self.monitorClientClosure(on: connection, jobID: route.jobID)
                        }
                        let response = await self.response(for: request)
                        self.send(response, on: connection)
                    } catch let rejection as RequestRejection {
                        self.send(
                            self.jsonResponse(statusCode: rejection.statusCode, value: ["error": rejection.error]),
                            on: connection
                        )
                    } catch {
                        self.send(self.jsonResponse(statusCode: 400, value: ["error": "invalid_request"]), on: connection)
                    }
                case .failure(let rejection):
                    self.send(
                        self.jsonResponse(statusCode: rejection.statusCode, value: ["error": rejection.error]),
                        on: connection
                    )
                }
            }
        }
    }

    private func expireReceive(on connection: NWConnection, connectionID: ObjectIdentifier) {
        guard finishReceiving(connectionID: connectionID) else { return }
        send(jsonResponse(statusCode: 408, value: ["error": "request_timeout"]), on: connection)
    }

    @discardableResult
    private func finishReceiving(connectionID: ObjectIdentifier) -> Bool {
        guard let task = receiveDeadlineTasks.removeValue(forKey: connectionID) else { return false }
        task.cancel()
        return true
    }

    private func receiveRequest(
        connection: NWConnection,
        connectionID: ObjectIdentifier,
        accumulated: Data,
        completion: @escaping (Result<Data, RequestRejection>) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 16 * 1024) { data, _, isComplete, error in
            Task { @MainActor [weak self, connection] in
                guard let self, self.receiveDeadlineTasks[connectionID] != nil else {
                    connection.cancel()
                    return
                }
                guard error == nil else {
                    _ = self.finishReceiving(connectionID: connectionID)
                    connection.cancel()
                    return
                }

                var next = accumulated
                if let data { next.append(data) }
                switch Self.framingDecision(for: next) {
                case .complete(let expectedLength):
                    completion(.success(Data(next.prefix(expectedLength))))
                case .reject(let statusCode, let error):
                    completion(.failure(RequestRejection(statusCode: statusCode, error: error)))
                case .incomplete:
                    if isComplete {
                        completion(.failure(RequestRejection(statusCode: 400, error: "incomplete_request")))
                    } else {
                        self.receiveRequest(
                            connection: connection,
                            connectionID: connectionID,
                            accumulated: next,
                            completion: completion
                        )
                    }
                }
            }
        }
    }

    nonisolated static func exportJobID(from body: Data) -> UUID? {
        guard let object = try? JSONSerialization.jsonObject(with: body) as? [String: Any],
              let value = object["job_id"] as? String else { return nil }
        return UUID(uuidString: value)
    }

    nonisolated static func exportJobRoute(_ path: String) -> (jobID: UUID, action: String?)? {
        let parts = path.split(separator: "/", omittingEmptySubsequences: true)
        guard parts.count == 3 || parts.count == 4,
              parts[0] == "v1", parts[1] == "exports",
              let jobID = UUID(uuidString: String(parts[2])) else { return nil }
        let action = parts.count == 4 ? String(parts[3]) : nil
        guard action == nil || action == "resume" || action == "cancel" else { return nil }
        return (jobID, action)
    }

    nonisolated static func requestByInjectingExportJobID(
        _ jobID: UUID,
        into request: ParsedHTTPRequest
    ) throws -> ParsedHTTPRequest {
        guard var object = try JSONSerialization.jsonObject(with: request.body) as? [String: Any] else {
            throw RequestRejection(statusCode: 400, error: "invalid_json")
        }
        object["job_id"] = jobID.uuidString.lowercased()
        return ParsedHTTPRequest(
            method: request.method,
            path: request.path,
            headers: request.headers,
            body: try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )
    }

    private func monitorClientClosure(on connection: NWConnection, jobID: UUID) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 1) { [weak self, weak connection] _, _, isComplete, error in
            guard let owner = self else { return }
            let liveConnection = connection
            let clientClosed = isComplete || error != nil
            Task { @MainActor [owner, liveConnection, clientClosed] in
                if clientClosed {
                    owner.cancelExportHandler?(jobID)
                    return
                }
                if let liveConnection {
                    owner.monitorClientClosure(on: liveConnection, jobID: jobID)
                }
            }
        }
    }

    nonisolated static func framingDecision(for data: Data) -> RequestFramingDecision {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator) else {
            return data.count > maximumHeaderBytes
                ? .reject(statusCode: 431, error: "request_headers_too_large")
                : .incomplete
        }
        guard headerEnd.upperBound <= maximumHeaderBytes else {
            return .reject(statusCode: 431, error: "request_headers_too_large")
        }
        guard let header = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else {
            return .reject(statusCode: 400, error: "invalid_headers")
        }

        let lines = header.components(separatedBy: "\r\n")
        let contentLengthValues = lines.dropFirst().compactMap { line -> String? in
            guard let colon = line.firstIndex(of: ":") else { return nil }
            let name = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard name == "content-length" else { return nil }
            return line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        }
        guard contentLengthValues.count <= 1 else {
            return .reject(statusCode: 400, error: "invalid_content_length")
        }
        let hasTransferEncoding = lines.dropFirst().contains { line in
            guard let colon = line.firstIndex(of: ":") else { return false }
            return line[..<colon]
                .trimmingCharacters(in: .whitespacesAndNewlines)
                .lowercased() == "transfer-encoding"
        }
        if hasTransferEncoding {
            return .reject(statusCode: 400, error: "transfer_encoding_not_supported")
        }

        let contentLength: Int
        if let value = contentLengthValues.first {
            guard let parsed = Int(value), parsed >= 0 else {
                return .reject(statusCode: 400, error: "invalid_content_length")
            }
            contentLength = parsed
        } else {
            contentLength = 0
        }
        guard contentLength <= maximumBodyBytes else {
            return .reject(statusCode: 413, error: "request_body_too_large")
        }

        let expectedLength = headerEnd.upperBound + contentLength
        guard expectedLength <= maximumHeaderBytes + maximumBodyBytes else {
            return .reject(statusCode: 413, error: "request_too_large")
        }
        return data.count >= expectedLength ? .complete(expectedLength: expectedLength) : .incomplete
    }

    nonisolated static func parseCompleteRequest(_ data: Data) throws -> ParsedHTTPRequest {
        let separator = Data("\r\n\r\n".utf8)
        guard let headerEnd = data.range(of: separator),
              let header = String(data: data[..<headerEnd.lowerBound], encoding: .utf8) else {
            throw RequestRejection(statusCode: 400, error: "invalid_request")
        }
        let lines = header.components(separatedBy: "\r\n")
        guard let requestLine = lines.first else {
            throw RequestRejection(statusCode: 400, error: "invalid_request_line")
        }
        let parts = requestLine.split(separator: " ", omittingEmptySubsequences: true)
        guard parts.count == 3, parts[2] == "HTTP/1.1" || parts[2] == "HTTP/1.0" else {
            throw RequestRejection(statusCode: 400, error: "invalid_request_line")
        }

        var headers: [String: String] = [:]
        for line in lines.dropFirst() where !line.isEmpty {
            guard let colon = line.firstIndex(of: ":") else {
                throw RequestRejection(statusCode: 400, error: "invalid_headers")
            }
            let name = line[..<colon].trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            guard !name.isEmpty, headers[name] == nil else {
                throw RequestRejection(statusCode: 400, error: "invalid_headers")
            }
            headers[name] = line[line.index(after: colon)...].trimmingCharacters(in: .whitespacesAndNewlines)
        }

        let contentLength = headers["content-length"].flatMap(Int.init) ?? 0
        let bodyStart = headerEnd.upperBound
        guard data.count >= bodyStart + contentLength else {
            throw RequestRejection(statusCode: 400, error: "incomplete_request")
        }
        let path = String(parts[1]).split(separator: "?", maxSplits: 1).first.map(String.init) ?? String(parts[1])
        return ParsedHTTPRequest(
            method: String(parts[0]),
            path: path,
            headers: headers,
            body: Data(data[bodyStart..<(bodyStart + contentLength)])
        )
    }

    nonisolated static func isLoopbackEndpoint(_ endpoint: NWEndpoint) -> Bool {
        guard case .hostPort(let host, _) = endpoint else { return false }
        switch host {
        case .ipv4(let address):
            return address.rawValue.first == 127
        case .ipv6(let address):
            let bytes = [UInt8](address.rawValue)
            if bytes == Array(repeating: 0, count: 15) + [1] { return true }
            // IPv4-mapped loopback (::ffff:127.0.0.0/104).
            return bytes.count == 16 &&
                bytes[0..<10].allSatisfy { $0 == 0 } &&
                bytes[10] == 0xff && bytes[11] == 0xff && bytes[12] == 127
        case .name(let name, _):
            return name.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: ".")) == "localhost"
        @unknown default:
            return false
        }
    }

    nonisolated static func isValidWaitTimeout(_ timeout: TimeInterval) -> Bool {
        timeout.isFinite && timeout >= minimumWaitTimeoutSeconds && timeout <= maximumWaitTimeoutSeconds
    }

    nonisolated static func validationDecision(for request: ParsedHTTPRequest) -> RequestValidationDecision {
        if request.path == "/v1/status" {
            guard request.method == "GET" else {
                return .reject(statusCode: 405, error: "method_not_allowed")
            }
            return request.body.isEmpty ? .valid : .reject(statusCode: 400, error: "unexpected_body")
        }
        if request.path == "/v1/exports" {
            guard request.method == "POST" else {
                return .reject(statusCode: 405, error: "method_not_allowed")
            }
            return validateJSONPost(request)
        }
        if let route = exportJobRoute(request.path) {
            if route.action == nil {
                guard request.method == "GET" else {
                    return .reject(statusCode: 405, error: "method_not_allowed")
                }
                return request.body.isEmpty ? .valid : .reject(statusCode: 400, error: "unexpected_body")
            }
            guard request.method == "POST" else {
                return .reject(statusCode: 405, error: "method_not_allowed")
            }
            return validateJSONPost(request)
        }
        return .valid
    }

    nonisolated private static func validateJSONPost(_ request: ParsedHTTPRequest) -> RequestValidationDecision {
        guard request.headers["content-length"] != nil else {
            return .reject(statusCode: 411, error: "content_length_required")
        }
        let mediaType = request.headers["content-type"]?
            .split(separator: ";", maxSplits: 1)
            .first?
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
        return mediaType == "application/json"
            ? .valid
            : .reject(statusCode: 415, error: "application_json_required")
    }

    private func response(for request: ParsedHTTPRequest) async -> HTTPResponse {
        if case .reject(let statusCode, let error) = Self.validationDecision(for: request) {
            return jsonResponse(statusCode: statusCode, value: ["error": error])
        }

        switch (request.method, request.path) {
        case ("GET", "/v1/status"):
            guard let statusProvider else {
                return jsonResponse(statusCode: 503, value: ["error": "server_not_ready"])
            }
            return jsonResponse(statusCode: 200, value: statusProvider())

        case ("POST", "/v1/exports"):
            return await exportResponse(from: request.body)

        default:
            guard let route = Self.exportJobRoute(request.path) else {
                return jsonResponse(statusCode: 404, value: ["error": "not_found"])
            }
            switch (request.method, route.action) {
            case ("GET", nil):
                guard let jobStatusHandler else {
                    return jsonResponse(statusCode: 503, value: ["error": "server_not_ready"])
                }
                return controlResponse(jobStatusHandler(route.jobID))
            case ("POST", .some("resume")):
                guard let resumeExportHandler else {
                    return jsonResponse(statusCode: 503, value: ["error": "server_not_ready"])
                }
                let decoded = (try? JSONDecoder().decode(ResumeRequestBody.self, from: request.body))
                guard request.body.isEmpty || decoded != nil else {
                    return jsonResponse(statusCode: 400, value: ["error": "invalid_json"])
                }
                let timeout = decoded?.waitTimeoutSeconds ?? 300
                guard Self.isValidWaitTimeout(timeout) else {
                    return jsonResponse(statusCode: 400, value: ["error": "invalid_timeout"])
                }
                return controlResponse(await resumeExportHandler(route.jobID, timeout))
            case ("POST", .some("cancel")):
                guard let explicitCancelExportHandler else {
                    return jsonResponse(statusCode: 503, value: ["error": "server_not_ready"])
                }
                guard request.body.isEmpty || (try? JSONSerialization.jsonObject(with: request.body)) != nil else {
                    return jsonResponse(statusCode: 400, value: ["error": "invalid_json"])
                }
                return controlResponse(explicitCancelExportHandler(route.jobID))
            default:
                return jsonResponse(statusCode: 404, value: ["error": "not_found"])
            }
        }
    }

    private func exportResponse(from body: Data) async -> HTTPResponse {
        guard let exportHandler else {
            return jsonResponse(statusCode: 503, value: ["error": "server_not_ready"])
        }

        let decoded: ExportRequestBody
        do {
            decoded = try JSONDecoder().decode(ExportRequestBody.self, from: body)
        } catch {
            return jsonResponse(
                statusCode: 400,
                value: ["error": "invalid_json", "message": "Request body must be valid JSON."]
            )
        }

        guard decoded.source == nil || decoded.source == "connected_iphone" else {
            return jsonResponse(statusCode: 400, value: ["error": "unsupported_source"])
        }

        let startString = decoded.dateRange?.start ?? decoded.from
        let endString = decoded.dateRange?.end ?? decoded.to
        guard let startString, let endString,
              let startDate = Self.dateFormatter.date(from: startString),
              let endDate = Self.dateFormatter.date(from: endString) else {
            return jsonResponse(statusCode: 400, value: ["error": "invalid_date_range"])
        }

        let settingsPolicy: IPhoneExportRequest.SettingsPolicy
        switch decoded.settingsPolicy ?? "requested_dates_only" {
        case "requested_dates_only", "requestedDatesOnly":
            settingsPolicy = .requestedDatesOnly
        case "current_iphone_settings", "currentIPhoneSettings":
            settingsPolicy = .currentIPhoneSettings
        default:
            return jsonResponse(statusCode: 400, value: ["error": "unsupported_settings_policy"])
        }

        let responseMode: IPhoneExportRequest.ResponseMode
        switch decoded.responseMode ?? "write_files" {
        case "write_files", "writeFiles":
            responseMode = .writeFiles
        case "raw_json", "rawJSON":
            responseMode = .rawJSON
        default:
            return jsonResponse(statusCode: 400, value: ["error": "unsupported_response_mode"])
        }

        let rawProfile: IPhoneExportRequest.RawProfile?
        switch decoded.rawProfile {
        case nil:
            rawProfile = nil
        case IPhoneExportRequest.RawProfile.canonicalSourceRecordsV1.rawValue:
            rawProfile = .canonicalSourceRecordsV1
        default:
            return jsonResponse(statusCode: 400, value: ["error": "unsupported_raw_profile"])
        }
        guard rawProfile == nil || responseMode == .rawJSON else {
            return jsonResponse(statusCode: 400, value: ["error": "raw_profile_requires_raw_json"])
        }

        let timeout = decoded.waitTimeoutSeconds ?? 300
        guard Self.isValidWaitTimeout(timeout) else {
            return jsonResponse(
                statusCode: 400,
                value: [
                    "error": "invalid_timeout",
                    "message": "wait_timeout_seconds must be finite and between 5 and 900 seconds."
                ]
            )
        }

        let requestedDateIdentifiers = ExportOrchestrator.dateRange(
            from: startDate,
            to: endDate
        ).map { Self.dateFormatter.string(from: $0) }
        let response = await exportHandler(MacIPhoneExportRequestCoordinator.ExportRequest(
            jobID: decoded.jobID,
            startDate: startDate,
            endDate: endDate,
            requestedDateIdentifiers: requestedDateIdentifiers,
            requestedBy: .cli,
            settingsPolicy: settingsPolicy,
            responseMode: responseMode,
            rawProfile: rawProfile,
            waitTimeoutSeconds: timeout
        ))
        return controlResponse(response)
    }

    private func controlResponse(_ response: MacIPhoneExportRequestCoordinator.ExportResponse) -> HTTPResponse {
        let statusCode: Int
        switch response.status {
        case .success, .partialSuccess: statusCode = 200
        case .accepted, .preparing: statusCode = 202
        case .timedOut: statusCode = 408
        case .unavailable where response.failureReason == "job_not_found": statusCode = 404
        default: statusCode = 409
        }
        if let spool = response.spooledControlResponse {
            var headers = [
                "X-Healthmd-Export-Status": response.status.rawValue,
                "X-Healthmd-Raw-Schema": "healthmd.raw_result/1",
                "X-Healthmd-Raw-Validated": "1"
            ]
            if let start = response.spooledRawDateRangeStart,
               let end = response.spooledRawDateRangeEnd,
               let total = response.spooledRawTotalDays {
                headers["X-Healthmd-Raw-Date-Start"] = start
                headers["X-Healthmd-Raw-Date-End"] = end
                headers["X-Healthmd-Raw-Total-Days"] = String(total)
            }
            return HTTPResponse(
                statusCode: statusCode,
                body: .file(
                    url: spool.url,
                    length: spool.totalBytes,
                    sha256: spool.sha256,
                    // The spool belongs to the durable job. A successful or
                    // broken HTTP download must never consume its only copy.
                    cleanup: false
                ),
                headers: headers
            )
        }
        do {
            let data = try response.controlAPIData(using: encoder)
            if let strictResult = response.rawResult, statusCode == 200 {
                return HTTPResponse(
                    statusCode: statusCode,
                    body: .data(data),
                    headers: [
                        "X-Healthmd-Export-Status": response.status.rawValue,
                        "X-Healthmd-Raw-Schema": "healthmd.raw_result/1",
                        "X-Healthmd-Raw-Validated": "1",
                        "X-Healthmd-Raw-Date-Start": strictResult.dateRangeStart,
                        "X-Healthmd-Raw-Date-End": strictResult.dateRangeEnd,
                        "X-Healthmd-Raw-Total-Days": String(strictResult.totalRequestedDays),
                        "X-Healthmd-Body-SHA256": ConnectedTransferFile.sha256Hex(data)
                    ]
                )
            }
            return HTTPResponse(statusCode: statusCode, body: .data(data))
        } catch {
            return jsonResponse(statusCode: 500, value: ["error": "encode_failed"])
        }
    }

    private func jsonResponse<T: Encodable>(statusCode: Int, value: T) -> HTTPResponse {
        do {
            return HTTPResponse(statusCode: statusCode, body: .data(try encoder.encode(value)))
        } catch {
            return HTTPResponse(statusCode: 500, body: .data(Data("{\"error\":\"encode_failed\"}".utf8)))
        }
    }

    private func send(_ response: HTTPResponse, on connection: NWConnection) {
        let reason: String
        switch response.statusCode {
        case 200: reason = "OK"
        case 202: reason = "Accepted"
        case 400: reason = "Bad Request"
        case 403: reason = "Forbidden"
        case 404: reason = "Not Found"
        case 405: reason = "Method Not Allowed"
        case 408: reason = "Request Timeout"
        case 409: reason = "Conflict"
        case 411: reason = "Length Required"
        case 413: reason = "Payload Too Large"
        case 415: reason = "Unsupported Media Type"
        case 431: reason = "Request Header Fields Too Large"
        case 503: reason = "Service Unavailable"
        default: reason = "Error"
        }
        var header = "HTTP/1.1 \(response.statusCode) \(reason)\r\n"
        header += "Content-Type: application/json; charset=utf-8\r\n"
        header += "Content-Length: \(response.body.length)\r\n"
        for (name, value) in response.headers.sorted(by: { $0.key < $1.key }) {
            guard !name.contains("\r"), !name.contains("\n"),
                  !value.contains("\r"), !value.contains("\n") else { continue }
            header += "\(name): \(value)\r\n"
        }
        if case .file(_, _, let sha256, _) = response.body {
            header += "X-Healthmd-Body-SHA256: \(sha256)\r\n"
        }
        header += "Connection: close\r\n\r\n"

        switch response.body {
        case .data(let body):
            var data = Data(header.utf8)
            data.append(body)
            connection.send(content: data, completion: .contentProcessed { _ in
                connection.cancel()
            })
        case .file(let url, _, _, let cleanup):
            let deadlineTask = Task { @MainActor in
                try? await Task.sleep(nanoseconds: 7 * 24 * 60 * 60 * 1_000_000_000)
                if cleanup { try? FileManager.default.removeItem(at: url) }
                connection.cancel()
            }
            connection.send(content: Data(header.utf8), completion: .contentProcessed { [weak self] error in
                guard error == nil else {
                    deadlineTask.cancel()
                    if cleanup { try? FileManager.default.removeItem(at: url) }
                    connection.cancel()
                    return
                }
                self?.streamFileResponse(
                    url: url,
                    on: connection,
                    cleanup: cleanup,
                    deadlineTask: deadlineTask
                )
            })
        }
    }

    nonisolated private func streamFileResponse(
        url: URL,
        on connection: NWConnection,
        cleanup: Bool,
        deadlineTask: Task<Void, Never>
    ) {
        do {
            let handle = try FileHandle(forReadingFrom: url)
            sendNextFileChunk(
                from: handle,
                url: url,
                on: connection,
                cleanup: cleanup,
                deadlineTask: deadlineTask
            )
        } catch {
            deadlineTask.cancel()
            if cleanup { try? FileManager.default.removeItem(at: url) }
            connection.cancel()
        }
    }

    nonisolated private func sendNextFileChunk(
        from handle: FileHandle,
        url: URL,
        on connection: NWConnection,
        cleanup: Bool,
        deadlineTask: Task<Void, Never>
    ) {
        do {
            let chunk = try handle.read(upToCount: 512 * 1_024) ?? Data()
            if chunk.isEmpty {
                try? handle.close()
                connection.send(content: nil, isComplete: true, completion: .contentProcessed { _ in
                    deadlineTask.cancel()
                    if cleanup { try? FileManager.default.removeItem(at: url) }
                    connection.cancel()
                })
                return
            }
            connection.send(content: chunk, completion: .contentProcessed { [weak self] error in
                guard error == nil else {
                    deadlineTask.cancel()
                    try? handle.close()
                    if cleanup { try? FileManager.default.removeItem(at: url) }
                    connection.cancel()
                    return
                }
                self?.sendNextFileChunk(
                    from: handle,
                    url: url,
                    on: connection,
                    cleanup: cleanup,
                    deadlineTask: deadlineTask
                )
            })
        } catch {
            deadlineTask.cancel()
            try? handle.close()
            if cleanup { try? FileManager.default.removeItem(at: url) }
            connection.cancel()
        }
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }()
}
#endif
