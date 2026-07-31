import Foundation
#if DEBUG
import CryptoKit
import Security
#endif

struct APIExportUploadResult {
    let statusCode: Int
    let responseBodyPreview: String?
}

enum APIExportClientError: LocalizedError {
    case invalidEndpoint
    case invalidPayload
    case invalidResponse
    case responseTooLarge(statusCode: Int?, maximumBytes: Int)
    case serverRejected(statusCode: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Configure a valid HTTP or HTTPS API endpoint before exporting."
        case .invalidPayload:
            return "Health.md could not prepare the API export payload."
        case .invalidResponse:
            return "The API endpoint returned an invalid response."
        case .responseTooLarge(let statusCode, let maximumBytes):
            let status = statusCode.map { " (HTTP \($0))" } ?? ""
            return "API endpoint response\(status) exceeded the \(maximumBytes)-byte safety limit."
        case .serverRejected(let statusCode, _):
            // Endpoint response bodies are untrusted and may echo request data
            // or authorization values. Keep durable/UI errors status-only.
            return "API endpoint returned HTTP \(statusCode)."
        }
    }
}

struct APIExportClient {
    nonisolated static let defaultMaximumResponseBytes = 64 * 1_024
    #if DEBUG
    static let debugPinnedCertificateSHA256Key =
        "HealthMd.ExportPerformanceLab.apiServerCertificateSHA256"
    #endif

    private let responseLoader: BoundedURLSessionDataLoader
    private let maximumResponseBytes: Int

    init(
        maximumResponseBytes: Int = APIExportClient.defaultMaximumResponseBytes
    ) {
        #if DEBUG
        if ExportPerformanceInstrumentation.currentRunContext?.target == .apiEndpoint,
           let endpointValue = UserDefaults.standard.string(
                forKey: APIExportSettings.endpointURLStorageKey
           ),
           let host = URL(string: endpointValue)?.host,
           let digest = UserDefaults.standard.string(
                forKey: Self.debugPinnedCertificateSHA256Key
           ),
           digest.utf8.count == 64 {
            self.responseLoader = BoundedURLSessionDataLoader(
                configuration: URLSession.shared.configuration,
                challengeHandler: Self.pinnedChallengeHandler(
                    expectedHost: host,
                    expectedDigest: digest
                )
            )
        } else {
            self.responseLoader = BoundedURLSessionDataLoader(
                configuration: URLSession.shared.configuration
            )
        }
        #else
        self.responseLoader = BoundedURLSessionDataLoader(
            configuration: URLSession.shared.configuration
        )
        #endif
        self.maximumResponseBytes = max(1, maximumResponseBytes)
    }

    init(
        session: URLSession,
        maximumResponseBytes: Int = APIExportClient.defaultMaximumResponseBytes
    ) {
        self.responseLoader = BoundedURLSessionDataLoader(session: session)
        self.maximumResponseBytes = max(1, maximumResponseBytes)
    }

    @MainActor
    func upload(
        records: [HealthData],
        failedDateDetails: [FailedDateDetail],
        externalRecords: [ExternalDailyRecord] = [],
        settings: AdvancedExportSettings,
        apiSettings: APIExportSettings,
        dateRangeStart: Date,
        dateRangeEnd: Date
    ) async throws -> APIExportUploadResult {
        guard let destination = apiSettings.destinationSnapshot else {
            throw APIExportClientError.invalidEndpoint
        }
        return try await upload(
            records: records,
            failedDateDetails: failedDateDetails,
            externalRecords: externalRecords,
            settings: settings,
            destination: destination,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd
        )
    }

    @MainActor
    func upload(
        records: [HealthData],
        failedDateDetails: [FailedDateDetail],
        externalRecords: [ExternalDailyRecord] = [],
        settings: AdvancedExportSettings,
        destination: APIExportDestinationSnapshot,
        dateRangeStart: Date,
        dateRangeEnd: Date
    ) async throws -> APIExportUploadResult {
        let body = try Self.makePayload(
            records: records,
            failedDateDetails: failedDateDetails,
            externalRecords: externalRecords,
            settings: settings,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd
        )
        return try await upload(payload: body, destination: destination)
    }

    /// Uploads an already encoded API envelope. The runner uses this overload
    /// so the payload measured for byte-aware batching is exactly the payload
    /// placed on the wire.
    func upload(
        payload: Data,
        destination: APIExportDestinationSnapshot
    ) async throws -> APIExportUploadResult {
        guard !payload.isEmpty else { throw APIExportClientError.invalidPayload }

        var request = URLRequest(url: destination.endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Health.md iOS API Export", forHTTPHeaderField: "User-Agent")
        if let authorization = destination.authorizationHeaderValue {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        #if DEBUG
        if let context = ExportPerformanceInstrumentation.currentRunContext,
           context.target == .apiEndpoint {
            request.setValue(
                context.runID,
                forHTTPHeaderField: "X-HealthMd-Export-Lab-Run"
            )
        }
        #endif
        request.httpBody = payload

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await responseLoader.data(
                for: request,
                maximumBytes: maximumResponseBytes
            )
        } catch let error as BoundedURLSessionDataLoaderError {
            switch error {
            case .responseTooLarge(let statusCode, let maximumBytes, _):
                throw APIExportClientError.responseTooLarge(
                    statusCode: statusCode,
                    maximumBytes: maximumBytes
                )
            }
        } catch {
            #if DEBUG
            Self.recordTransportFailure(error)
            #endif
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIExportClientError.invalidResponse
        }

        let responsePreview = Self.responsePreview(from: data)
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIExportClientError.serverRejected(
                statusCode: httpResponse.statusCode,
                body: responsePreview
            )
        }

        return APIExportUploadResult(
            statusCode: httpResponse.statusCode,
            responseBodyPreview: responsePreview
        )
    }

    func upload(
        payloadArtifact: ExportArtifactFile,
        destination: APIExportDestinationSnapshot
    ) async throws -> APIExportUploadResult {
        guard payloadArtifact.descriptor.byteCount > 0 else {
            throw APIExportClientError.invalidPayload
        }

        var request = URLRequest(url: destination.endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Health.md iOS API Export", forHTTPHeaderField: "User-Agent")
        if let authorization = destination.authorizationHeaderValue {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        #if DEBUG
        if let context = ExportPerformanceInstrumentation.currentRunContext,
           context.target == .apiEndpoint {
            request.setValue(
                context.runID,
                forHTTPHeaderField: "X-HealthMd-Export-Lab-Run"
            )
        }
        #endif

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await responseLoader.upload(
                for: request,
                fromFile: payloadArtifact.url,
                maximumBytes: maximumResponseBytes
            )
        } catch let error as BoundedURLSessionDataLoaderError {
            switch error {
            case .responseTooLarge(let statusCode, let maximumBytes, _):
                throw APIExportClientError.responseTooLarge(
                    statusCode: statusCode,
                    maximumBytes: maximumBytes
                )
            }
        } catch {
            #if DEBUG
            Self.recordTransportFailure(error)
            #endif
            throw error
        }
        guard let httpResponse = response as? HTTPURLResponse else {
            throw APIExportClientError.invalidResponse
        }
        let responsePreview = Self.responsePreview(from: data)
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw APIExportClientError.serverRejected(
                statusCode: httpResponse.statusCode,
                body: responsePreview
            )
        }
        return APIExportUploadResult(
            statusCode: httpResponse.statusCode,
            responseBodyPreview: responsePreview
        )
    }

    #if DEBUG
    private static func pinnedChallengeHandler(
        expectedHost: String,
        expectedDigest: String
    ) -> BoundedURLSessionDataLoader.ChallengeHandler {
        { @Sendable challenge, completion in
            guard challenge.protectionSpace.authenticationMethod
                    == NSURLAuthenticationMethodServerTrust,
                  challenge.protectionSpace.host == expectedHost,
                  let trust = challenge.protectionSpace.serverTrust,
                  let chain = SecTrustCopyCertificateChain(trust) as? [SecCertificate],
                  let certificate = chain.first else {
                completion(.performDefaultHandling, nil)
                return
            }
            let certificateData = SecCertificateCopyData(certificate) as Data
            let actualDigest = SHA256.hash(data: certificateData)
                .map { String(format: "%02x", $0) }
                .joined()
            guard actualDigest == expectedDigest else {
                completion(.cancelAuthenticationChallenge, nil)
                return
            }
            completion(.useCredential, URLCredential(trust: trust))
        }
    }

    private static func recordTransportFailure(_ error: Error) {
        let phase: String
        switch (error as? URLError)?.code {
        case .serverCertificateHasBadDate, .serverCertificateUntrusted,
             .secureConnectionFailed, .clientCertificateRejected,
             .clientCertificateRequired:
            phase = "transport-tls"
        case .cannotConnectToHost:
            phase = "transport-connect"
        case .cannotFindHost, .dnsLookupFailed:
            phase = "transport-dns"
        case .timedOut:
            phase = "transport-timeout"
        case .networkConnectionLost:
            phase = "transport-disconnected"
        case .notConnectedToInternet:
            phase = "transport-offline"
        default:
            phase = "transport-failure"
        }
        ExportPerformanceInstrumentation.beginSpan(
            pipeline: "api-endpoint",
            phase: phase
        ).finish(outcome: .failure)
    }
    #endif

    @MainActor
    static func makePayload(
        records: [HealthData],
        failedDateDetails: [FailedDateDetail],
        externalRecords: [ExternalDailyRecord] = [],
        settings: AdvancedExportSettings,
        dateRangeStart: Date,
        dateRangeEnd: Date,
        exportedAt: Date = Date(),
        connectedAppsEnabled: Bool? = nil
    ) throws -> Data {
        let recordData = try records.map {
            try makeRecordJSONData($0, settings: settings)
        }
        let failedDateData = try failedDateDetails.map {
            try makeJSONData(from: $0)
        }
        let externalRecordData = try externalRecords
            .filter(\.shouldExport)
            .map { try makeJSONData(from: $0) }
        return try makePayload(
            recordData: recordData,
            failedDateData: failedDateData,
            externalRecordData: externalRecordData,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd,
            exportedAt: exportedAt,
            connectedAppsEnabled: connectedAppsEnabled ?? ConnectedAppsFeature.isEnabled,
            calendarTimeZone: settings.exportTimeZoneOverride ?? .current
        )
    }

    /// Encodes one selected daily record once. Batch sizing and upload reuse the
    /// exact compact bytes rather than rebuilding canonical JSON object graphs.
    @MainActor
    static func makeRecordJSONData(
        _ record: HealthData,
        settings: AdvancedExportSettings
    ) throws -> Data {
        try makeSelectedRecordJSONData(
            record.filtered(by: settings.metricSelection),
            settings: settings
        )
    }

    /// Encodes a record whose capture boundary already applied `settings.metricSelection`.
    /// APIEndpointExportRunner uses this after HealthKitDailyCapture filtering so a
    /// lossless archive graph is not traversed repeatedly before serialization.
    @MainActor
    static func makeSelectedRecordJSONData(
        _ record: HealthData,
        settings: AdvancedExportSettings
    ) throws -> Data {
        try record.toJSONDataThrowing(
            customization: settings.formatCustomization,
            outputFormatting: [.sortedKeys]
        )
    }

    @MainActor
    static func makeSelectedRecordJSONArtifact(
        _ record: HealthData,
        settings: AdvancedExportSettings,
        directoryURL: URL
    ) throws -> ExportArtifactFile {
        try ExportArtifactIO.renderTemporary(
            in: directoryURL,
            prefix: "api-daily-record",
            mediaType: "application/json"
        ) { sink in
            try record.writeJSONThrowing(
                to: sink,
                customization: settings.formatCustomization,
                outputFormatting: [.sortedKeys]
            )
        }
    }

    private enum EnvelopeSegment {
        case data(Data)
        case file(ExportArtifactFile)

        var byteCount: UInt64 {
            switch self {
            case .data(let data): UInt64(data.count)
            case .file(let file): file.descriptor.byteCount
            }
        }

        func write(to sink: ExportByteSink) throws {
            switch self {
            case .data(let data):
                try sink.write(data)
            case .file(let file):
                try file.forEachChunk { try sink.write($0) }
            }
        }
    }

    @MainActor
    static func makePayload(
        recordData: [Data],
        failedDateData: [Data],
        externalRecordData: [Data],
        dateRangeStart: Date,
        dateRangeEnd: Date,
        exportedAt: Date,
        connectedAppsEnabled: Bool,
        calendarTimeZone: TimeZone = .current
    ) throws -> Data {
        let segments = try envelopeSegments(
            recordValues: recordData.map { [.data($0)] },
            failedDateData: failedDateData,
            externalRecordData: externalRecordData,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd,
            exportedAt: exportedAt,
            connectedAppsEnabled: connectedAppsEnabled,
            calendarTimeZone: calendarTimeZone
        )
        let byteCount = try exactByteCount(segments)
        let sink = MemoryExportByteSink(
            mediaType: "application/json",
            reservingCapacity: byteCount
        )
        for segment in segments { try segment.write(to: sink) }
        _ = try sink.finish()
        return sink.data
    }

    @MainActor
    static func makePayloadArtifact(
        recordArtifacts: [ExportArtifactFile],
        failedDateData: [Data],
        externalRecordData: [Data],
        dateRangeStart: Date,
        dateRangeEnd: Date,
        exportedAt: Date,
        connectedAppsEnabled: Bool,
        calendarTimeZone: TimeZone = .current,
        directoryURL: URL
    ) throws -> ExportArtifactFile {
        let segments = try envelopeSegments(
            recordValues: recordArtifacts.map { [.file($0)] },
            failedDateData: failedDateData,
            externalRecordData: externalRecordData,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd,
            exportedAt: exportedAt,
            connectedAppsEnabled: connectedAppsEnabled,
            calendarTimeZone: calendarTimeZone
        )
        return try ExportArtifactIO.renderTemporary(
            in: directoryURL,
            prefix: "api-envelope",
            mediaType: "application/json"
        ) { sink in
            for segment in segments { try segment.write(to: sink) }
        }
    }

    @MainActor
    static func payloadByteCount(
        recordData: [Data],
        failedDateData: [Data],
        externalRecordData: [Data],
        dateRangeStart: Date,
        dateRangeEnd: Date,
        exportedAt: Date,
        connectedAppsEnabled: Bool,
        calendarTimeZone: TimeZone = .current
    ) throws -> Int {
        try exactByteCount(envelopeSegments(
            recordValues: recordData.map { [.data($0)] },
            failedDateData: failedDateData,
            externalRecordData: externalRecordData,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd,
            exportedAt: exportedAt,
            connectedAppsEnabled: connectedAppsEnabled,
            calendarTimeZone: calendarTimeZone
        ))
    }

    @MainActor
    static func payloadByteCount(
        recordArtifacts: [ExportArtifactFile],
        failedDateData: [Data],
        externalRecordData: [Data],
        dateRangeStart: Date,
        dateRangeEnd: Date,
        exportedAt: Date,
        connectedAppsEnabled: Bool,
        calendarTimeZone: TimeZone = .current
    ) throws -> Int {
        try exactByteCount(envelopeSegments(
            recordValues: recordArtifacts.map { [.file($0)] },
            failedDateData: failedDateData,
            externalRecordData: externalRecordData,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd,
            exportedAt: exportedAt,
            connectedAppsEnabled: connectedAppsEnabled,
            calendarTimeZone: calendarTimeZone
        ))
    }

    @MainActor
    private static func envelopeSegments(
        recordValues: [[EnvelopeSegment]],
        failedDateData: [Data],
        externalRecordData: [Data],
        dateRangeStart: Date,
        dateRangeEnd: Date,
        exportedAt: Date,
        connectedAppsEnabled: Bool,
        calendarTimeZone: TimeZone
    ) throws -> [EnvelopeSegment] {
        func scalar(_ value: String) throws -> [EnvelopeSegment] {
            [.data(try makeJSONData(from: value))]
        }

        func integer(_ value: Int) -> [EnvelopeSegment] {
            [.data(Data(String(value).utf8))]
        }

        func array(_ values: [[EnvelopeSegment]]) -> [EnvelopeSegment] {
            var segments: [EnvelopeSegment] = [.data(Data("[".utf8))]
            for (index, value) in values.enumerated() {
                if index > 0 { segments.append(.data(Data(",".utf8))) }
                segments.append(contentsOf: value)
            }
            segments.append(.data(Data("]".utf8)))
            return segments
        }

        func object(_ members: [(String, [EnvelopeSegment])]) throws -> [EnvelopeSegment] {
            let sorted = members.sorted { $0.0 < $1.0 }
            var segments: [EnvelopeSegment] = [.data(Data("{".utf8))]
            for (index, member) in sorted.enumerated() {
                if index > 0 { segments.append(.data(Data(",".utf8))) }
                segments.append(.data(try makeJSONData(from: member.0)))
                segments.append(.data(Data(":".utf8)))
                segments.append(contentsOf: member.1)
            }
            segments.append(.data(Data("}".utf8)))
            return segments
        }

        let dateRange = try object([
            ("start", try scalar(dayString(from: dateRangeStart, timeZone: calendarTimeZone))),
            ("end", try scalar(dayString(from: dateRangeEnd, timeZone: calendarTimeZone)))
        ])
        var members: [(String, [EnvelopeSegment])] = [
            ("schema", try scalar("healthmd.api_export")),
            ("schema_version", integer(connectedAppsEnabled ? 2 : 1)),
            ("daily_record_schema", try scalar(HealthMdExportSchema.identifier)),
            ("daily_record_schema_version", integer(HealthMdExportSchema.version)),
            ("exported_at", try scalar(timestampString(from: exportedAt))),
            ("source", try scalar("ios")),
            ("date_range", dateRange),
            ("record_count", integer(recordValues.count)),
            ("records", array(recordValues)),
            ("failed_date_details", array(failedDateData.map { [.data($0)] }))
        ]
        if connectedAppsEnabled {
            members.append(contentsOf: [
                ("external_record_schema", try scalar(ExternalDailyRecord.schema)),
                ("external_record_schema_version", integer(ExternalDailyRecord.schemaVersion)),
                ("external_record_count", integer(externalRecordData.count)),
                ("external_records", array(externalRecordData.map { [.data($0)] }))
            ])
        }
        return try object(members)
    }

    private static func exactByteCount(_ segments: [EnvelopeSegment]) throws -> Int {
        var total: UInt64 = 0
        for segment in segments {
            let addition = total.addingReportingOverflow(segment.byteCount)
            guard !addition.overflow else { throw APIExportClientError.invalidPayload }
            total = addition.partialValue
        }
        guard let result = Int(exactly: total) else {
            throw APIExportClientError.invalidPayload
        }
        return result
    }

    static func dayString(from date: Date, timeZone: TimeZone = .current) -> String {
        let cacheKey = "healthmd.api-day.\(timeZone.identifier)"
        let formatter: DateFormatter
        if let cached = Thread.current.threadDictionary[cacheKey] as? DateFormatter {
            formatter = cached
        } else {
            let created = DateFormatter()
            created.calendar = Calendar(identifier: .gregorian)
            created.locale = Locale(identifier: "en_US_POSIX")
            created.timeZone = timeZone
            created.dateFormat = "yyyy-MM-dd"
            Thread.current.threadDictionary[cacheKey] = created
            formatter = created
        }
        return formatter.string(from: date)
    }

    static func timestampString(from date: Date) -> String {
        let cacheKey = "healthmd.api-iso8601-fractional"
        let formatter: ISO8601DateFormatter
        if let cached = Thread.current.threadDictionary[cacheKey]
            as? ISO8601DateFormatter {
            formatter = cached
        } else {
            let created = ISO8601DateFormatter()
            created.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            Thread.current.threadDictionary[cacheKey] = created
            formatter = created
        }
        return formatter.string(from: date)
    }

    private static func responsePreview(from data: Data) -> String? {
        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= 500 { return trimmed }
        return String(trimmed.prefix(500)) + "…"
    }

    static func makeJSONData<T: Encodable>(from value: T) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return try encoder.encode(value)
    }
}
