import Foundation

struct APIExportUploadResult {
    let statusCode: Int
    let responseBodyPreview: String?
}

enum APIExportClientError: LocalizedError {
    case invalidEndpoint
    case invalidPayload
    case invalidResponse
    case serverRejected(statusCode: Int, body: String?)

    var errorDescription: String? {
        switch self {
        case .invalidEndpoint:
            return "Configure a valid HTTP or HTTPS API endpoint before exporting."
        case .invalidPayload:
            return "Health.md could not prepare the API export payload."
        case .invalidResponse:
            return "The API endpoint returned an invalid response."
        case .serverRejected(let statusCode, let body):
            if let body, !body.isEmpty {
                return "API endpoint returned HTTP \(statusCode): \(body)"
            }
            return "API endpoint returned HTTP \(statusCode)."
        }
    }
}

struct APIExportClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
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
        guard let endpointURL = apiSettings.endpointURL else {
            throw APIExportClientError.invalidEndpoint
        }

        let body = try Self.makePayload(
            records: records,
            failedDateDetails: failedDateDetails,
            externalRecords: externalRecords,
            settings: settings,
            dateRangeStart: dateRangeStart,
            dateRangeEnd: dateRangeEnd
        )

        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("Health.md iOS API Export", forHTTPHeaderField: "User-Agent")
        if let authorization = apiSettings.authorizationHeaderValue {
            request.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        request.httpBody = body

        let (data, response) = try await session.data(for: request)
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
        exportedAt: Date = Date()
    ) throws -> Data {
        let dateFormatter = DateFormatter()
        dateFormatter.calendar = Calendar(identifier: .gregorian)
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.timeZone = TimeZone.current
        dateFormatter.dateFormat = "yyyy-MM-dd"

        let isoFormatter = ISO8601DateFormatter()
        isoFormatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]

        let recordObjects: [Any] = try records.map { record in
            let json = record.export(format: .json, settings: settings)
            guard let data = json.data(using: .utf8) else {
                throw APIExportClientError.invalidPayload
            }
            return try JSONSerialization.jsonObject(with: data)
        }

        let failedDateObjects = try jsonObject(from: failedDateDetails)

        var envelope: [String: Any] = [
            "schema": "healthmd.api_export",
            "schema_version": 1,
            "daily_record_schema": HealthMdExportSchema.identifier,
            "daily_record_schema_version": HealthMdExportSchema.version,
            "exported_at": isoFormatter.string(from: exportedAt),
            "source": "ios",
            "date_range": [
                "start": dateFormatter.string(from: dateRangeStart),
                "end": dateFormatter.string(from: dateRangeEnd)
            ],
            "record_count": recordObjects.count,
            "records": recordObjects,
            "failed_date_details": failedDateObjects
        ]

        if ConnectedAppsFeature.isEnabled {
            let exportableExternalRecords = externalRecords.filter(\.shouldExport)
            envelope["schema_version"] = 2
            envelope["external_record_schema"] = ExternalDailyRecord.schema
            envelope["external_record_schema_version"] = ExternalDailyRecord.schemaVersion
            envelope["external_record_count"] = exportableExternalRecords.count
            envelope["external_records"] = try jsonObject(from: exportableExternalRecords)
        }

        guard JSONSerialization.isValidJSONObject(envelope) else {
            throw APIExportClientError.invalidPayload
        }
        return try JSONSerialization.data(withJSONObject: envelope, options: [.prettyPrinted, .sortedKeys])
    }

    private static func responsePreview(from data: Data) -> String? {
        guard !data.isEmpty,
              let text = String(data: data, encoding: .utf8) else { return nil }
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        if trimmed.count <= 500 { return trimmed }
        return String(trimmed.prefix(500)) + "…"
    }

    private static func jsonObject<T: Encodable>(from value: T) throws -> Any {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(value)
        return try JSONSerialization.jsonObject(with: data)
    }
}
