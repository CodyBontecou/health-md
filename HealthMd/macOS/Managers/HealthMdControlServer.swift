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

            enum CodingKeys: String, CodingKey {
                case jobID = "job_id"
                case message
                case fractionComplete = "fraction_complete"
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

    private struct ExportRequestBody: Codable {
        struct DateRange: Codable {
            let start: String
            let end: String
        }

        let source: String?
        let dateRange: DateRange?
        let from: String?
        let to: String?
        let settingsPolicy: String?
        let responseMode: String?
        let waitTimeoutSeconds: TimeInterval?

        enum CodingKeys: String, CodingKey {
            case source
            case dateRange = "date_range"
            case from
            case to
            case settingsPolicy = "settings_policy"
            case responseMode = "response_mode"
            case waitTimeoutSeconds = "wait_timeout_seconds"
        }
    }

    private let port: NWEndpoint.Port = 17645
    private var listener: NWListener?
    private var statusProvider: (() -> StatusResponse)?
    private var exportHandler: ((MacIPhoneExportRequestCoordinator.ExportRequest) async -> MacIPhoneExportRequestCoordinator.ExportResponse)?
    private let encoder: JSONEncoder = {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }()

    @Published private(set) var isRunning = false
    @Published private(set) var endpointDescription = "http://127.0.0.1:17645"

    func start(
        statusProvider: @escaping () -> StatusResponse,
        exportHandler: @escaping (MacIPhoneExportRequestCoordinator.ExportRequest) async -> MacIPhoneExportRequestCoordinator.ExportResponse
    ) {
        self.statusProvider = statusProvider
        self.exportHandler = exportHandler
        guard listener == nil else { return }

        do {
            let parameters = NWParameters.tcp
            parameters.allowLocalEndpointReuse = true
            let listener = try NWListener(using: parameters, on: port)
            listener.newConnectionHandler = { [weak self] connection in
                connection.start(queue: .main)
                Task { @MainActor in
                    self?.handle(connection: connection)
                }
            }
            listener.stateUpdateHandler = { [weak self] state in
                Task { @MainActor in
                    switch state {
                    case .ready:
                        self?.isRunning = true
                    case .failed, .cancelled:
                        self?.isRunning = false
                    default:
                        break
                    }
                }
            }
            listener.start(queue: .main)
            self.listener = listener
        } catch {
            isRunning = false
        }
    }

    func stop() {
        listener?.cancel()
        listener = nil
        isRunning = false
    }

    private func handle(connection: NWConnection) {
        receiveRequest(connection: connection, accumulated: Data()) { [weak self] data in
            Task { @MainActor in
                guard let self else { return }
                let response = await self.response(for: data)
                self.send(response, on: connection)
            }
        }
    }

    private func receiveRequest(
        connection: NWConnection,
        accumulated: Data,
        completion: @escaping (Data) -> Void
    ) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 64 * 1024) { [weak self] data, _, isComplete, error in
            guard error == nil else {
                connection.cancel()
                return
            }
            var next = accumulated
            if let data { next.append(data) }
            if self?.isCompleteHTTPRequest(next) == true || isComplete {
                completion(next)
            } else {
                Task { @MainActor in
                    self?.receiveRequest(connection: connection, accumulated: next, completion: completion)
                }
            }
        }
    }

    private func isCompleteHTTPRequest(_ data: Data) -> Bool {
        guard let headerEnd = data.range(of: Data("\r\n\r\n".utf8)) else { return false }
        let headerData = data[..<headerEnd.lowerBound]
        guard let header = String(data: headerData, encoding: .utf8) else { return false }
        let contentLength = header
            .components(separatedBy: "\r\n")
            .first { $0.lowercased().hasPrefix("content-length:") }
            .flatMap { Int($0.split(separator: ":", maxSplits: 1).last?.trimmingCharacters(in: .whitespaces) ?? "") } ?? 0
        let bodyStart = headerEnd.upperBound
        return data.count - bodyStart >= contentLength
    }

    private func response(for data: Data) async -> (statusCode: Int, body: Data) {
        guard let requestText = String(data: data, encoding: .utf8),
              let requestLine = requestText.components(separatedBy: "\r\n").first else {
            return jsonResponse(statusCode: 400, value: ["error": "invalid_request"])
        }

        let parts = requestLine.split(separator: " ")
        guard parts.count >= 2 else {
            return jsonResponse(statusCode: 400, value: ["error": "invalid_request_line"])
        }

        let method = String(parts[0])
        let path = String(parts[1]).split(separator: "?").first.map(String.init) ?? String(parts[1])

        switch (method, path) {
        case ("GET", "/v1/status"):
            guard let statusProvider else { return jsonResponse(statusCode: 503, value: ["error": "server_not_ready"]) }
            return jsonResponse(statusCode: 200, value: statusProvider())
        case ("POST", "/v1/exports"):
            return await exportResponse(from: data)
        default:
            return jsonResponse(statusCode: 404, value: ["error": "not_found"])
        }
    }

    private func exportResponse(from requestData: Data) async -> (statusCode: Int, body: Data) {
        guard let exportHandler else { return jsonResponse(statusCode: 503, value: ["error": "server_not_ready"]) }
        guard let bodyRange = requestData.range(of: Data("\r\n\r\n".utf8)) else {
            return jsonResponse(statusCode: 400, value: ["error": "missing_body"])
        }
        let body = requestData[bodyRange.upperBound...]
        let decoded: ExportRequestBody
        do {
            decoded = try JSONDecoder().decode(ExportRequestBody.self, from: Data(body))
        } catch {
            return jsonResponse(statusCode: 400, value: ["error": "invalid_json", "message": error.localizedDescription])
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

        let response = await exportHandler(MacIPhoneExportRequestCoordinator.ExportRequest(
            startDate: startDate,
            endDate: endDate,
            requestedBy: .cli,
            settingsPolicy: settingsPolicy,
            responseMode: responseMode,
            waitTimeoutSeconds: decoded.waitTimeoutSeconds ?? 300
        ))
        let statusCode = response.status == .success || response.status == .partialSuccess ? 200 : 409
        return jsonResponse(statusCode: statusCode, value: response)
    }

    private func jsonResponse<T: Encodable>(statusCode: Int, value: T) -> (statusCode: Int, body: Data) {
        do {
            return (statusCode, try encoder.encode(value))
        } catch {
            return (500, Data("{\"error\":\"encode_failed\"}".utf8))
        }
    }

    private func send(_ response: (statusCode: Int, body: Data), on connection: NWConnection) {
        let reason = response.statusCode == 200 ? "OK" : response.statusCode == 404 ? "Not Found" : "Error"
        var header = "HTTP/1.1 \(response.statusCode) \(reason)\r\n"
        header += "Content-Type: application/json; charset=utf-8\r\n"
        header += "Content-Length: \(response.body.count)\r\n"
        header += "Connection: close\r\n\r\n"
        var data = Data(header.utf8)
        data.append(response.body)
        connection.send(content: data, completion: .contentProcessed { _ in
            connection.cancel()
        })
    }

    private static let dateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter
    }()
}
#endif
