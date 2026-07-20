import Foundation

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

    private let responseLoader: BoundedURLSessionDataLoader
    private let maximumResponseBytes: Int

    init(
        maximumResponseBytes: Int = APIExportClient.defaultMaximumResponseBytes
    ) {
        self.responseLoader = BoundedURLSessionDataLoader(
            configuration: URLSession.shared.configuration
        )
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
            connectedAppsEnabled: connectedAppsEnabled ?? ConnectedAppsFeature.isEnabled
        )
    }

    /// Encodes one selected daily record once. Batch sizing and upload reuse the
    /// exact compact bytes rather than rebuilding canonical JSON object graphs.
    @MainActor
    static func makeRecordJSONData(
        _ record: HealthData,
        settings: AdvancedExportSettings
    ) throws -> Data {
        let filtered = record.filtered(by: settings.metricSelection)
        let json = try filtered.toJSONThrowing(
            customization: settings.formatCustomization,
            outputFormatting: [.sortedKeys]
        )
        guard let data = json.data(using: .utf8) else {
            throw APIExportClientError.invalidPayload
        }
        return data
    }

    @MainActor
    static func makePayload(
        recordData: [Data],
        failedDateData: [Data],
        externalRecordData: [Data],
        dateRangeStart: Date,
        dateRangeEnd: Date,
        exportedAt: Date,
        connectedAppsEnabled: Bool
    ) throws -> Data {
        let segments = try envelopeSegments(
            recordData: recordData,
            failedDateData: failedDateData,
            externalRecordData: externalRecordData,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd,
            exportedAt: exportedAt,
            connectedAppsEnabled: connectedAppsEnabled
        )
        var payload = Data()
        payload.reserveCapacity(segments.reduce(0) { $0 + $1.count })
        for segment in segments {
            payload.append(segment)
        }
        return payload
    }

    @MainActor
    static func payloadByteCount(
        recordData: [Data],
        failedDateData: [Data],
        externalRecordData: [Data],
        dateRangeStart: Date,
        dateRangeEnd: Date,
        exportedAt: Date,
        connectedAppsEnabled: Bool
    ) throws -> Int {
        try envelopeSegments(
            recordData: recordData,
            failedDateData: failedDateData,
            externalRecordData: externalRecordData,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd,
            exportedAt: exportedAt,
            connectedAppsEnabled: connectedAppsEnabled
        ).reduce(0) { $0 + $1.count }
    }

    /// Returns fixed-order JSON segments so exact body sizing only sums cached
    /// byte counts. Large daily fragments are copied once, when the final batch
    /// body is assembled for upload.
    @MainActor
    private static func envelopeSegments(
        recordData: [Data],
        failedDateData: [Data],
        externalRecordData: [Data],
        dateRangeStart: Date,
        dateRangeEnd: Date,
        exportedAt: Date,
        connectedAppsEnabled: Bool
    ) throws -> [Data] {
        func scalar(_ value: String) throws -> [Data] {
            [try makeJSONData(from: value)]
        }

        func integer(_ value: Int) -> [Data] {
            [Data(String(value).utf8)]
        }

        func array(_ values: [Data]) -> [Data] {
            var segments = [Data("[".utf8)]
            segments.reserveCapacity(values.count * 2 + 2)
            for (index, value) in values.enumerated() {
                if index > 0 { segments.append(Data(",".utf8)) }
                segments.append(value)
            }
            segments.append(Data("]".utf8))
            return segments
        }

        func object(_ members: [(String, [Data])]) throws -> [Data] {
            let sorted = members.sorted { $0.0 < $1.0 }
            var segments = [Data("{".utf8)]
            for (index, member) in sorted.enumerated() {
                if index > 0 { segments.append(Data(",".utf8)) }
                segments.append(try makeJSONData(from: member.0))
                segments.append(Data(":".utf8))
                segments.append(contentsOf: member.1)
            }
            segments.append(Data("}".utf8))
            return segments
        }

        let dateRange = try object([
            ("start", try scalar(dayString(from: dateRangeStart))),
            ("end", try scalar(dayString(from: dateRangeEnd)))
        ])
        var members: [(String, [Data])] = [
            ("schema", try scalar("healthmd.api_export")),
            ("schema_version", integer(connectedAppsEnabled ? 2 : 1)),
            ("daily_record_schema", try scalar(HealthMdExportSchema.identifier)),
            ("daily_record_schema_version", integer(HealthMdExportSchema.version)),
            ("exported_at", try scalar(isoString(from: exportedAt))),
            ("source", try scalar("ios")),
            ("date_range", dateRange),
            ("record_count", integer(recordData.count)),
            ("records", array(recordData)),
            ("failed_date_details", array(failedDateData))
        ]
        if connectedAppsEnabled {
            members.append(contentsOf: [
                ("external_record_schema", try scalar(ExternalDailyRecord.schema)),
                ("external_record_schema_version", integer(ExternalDailyRecord.schemaVersion)),
                ("external_record_count", integer(externalRecordData.count)),
                ("external_records", array(externalRecordData))
            ])
        }
        return try object(members)
    }

    private static func dayString(from date: Date) -> String {
        let timeZone = TimeZone.current
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

    private static func isoString(from date: Date) -> String {
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
