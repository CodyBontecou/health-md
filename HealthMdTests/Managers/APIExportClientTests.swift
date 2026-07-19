import XCTest
@testable import HealthMd

@MainActor
final class APIExportClientTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings contains nested
    // observation state that can crash during test-process teardown on macOS 26.
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testWHOOPSidecarsUseAPIEnvelopeV2AndAreRedacted() throws {
        let date = Self.day(2026, 7, 13)
        var healthData = HealthData(date: date)
        healthData.activity.steps = 1234
        let settings = makeSettings()
        Self.retainedSettings.append(settings)
        let external = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-07-13",
            payloads: [ExternalProviderPayload(
                name: "cycles",
                endpoint: "https://api.prod.whoop.com/developer/v2/cycle?nextToken=opaque&access_token=secret",
                statusCode: 200,
                data: .object([
                    "access_token": .string("secret"),
                    "records": .array([.object(["id": .number(1)])])
                ])
            )]
        )

        let data = try APIExportClient.makePayload(
            records: [healthData],
            failedDateDetails: [],
            externalRecords: [external],
            settings: settings,
            dateRangeStart: date,
            dateRangeEnd: date,
            connectedAppsEnabled: true
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["schema" ] as? String, "healthmd.api_export")
        XCTAssertEqual(json["schema_version"] as? Int, 2)
        XCTAssertEqual(json["external_record_schema"] as? String, ExternalDailyRecord.schema)
        XCTAssertEqual(json["external_record_schema_version"] as? Int, 1)
        XCTAssertEqual(json["external_record_count"] as? Int, 1)
        XCTAssertEqual((json["external_records"] as? [Any])?.count, 1)
        let text = String(decoding: data, as: UTF8.self)
        XCTAssertFalse(text.contains("secret"))
        XCTAssertFalse(text.contains("opaque"))
    }

    func testAPIPayloadCarriesCurrentV6DailyDocumentWithCompleteCanonicalArchive() throws {
        let date = Self.day(2026, 7, 13)
        let archive = HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: "2026-07-13",
                intervalStart: Calendar.current.startOfDay(for: date),
                intervalEnd: Calendar.current.date(byAdding: .day, value: 1, to: Calendar.current.startOfDay(for: date))!,
                calendarTimeZoneIdentifier: TimeZone.current.identifier
            )
        )
        let healthData = HealthData(
            date: date,
            healthKitRecordArchive: archive,
            healthKitRecordCaptureStatus: .complete
        )
        let settings = makeSettings()
        settings.includeGranularData = true
        Self.retainedSettings.append(settings)

        let data = try APIExportClient.makePayload(
            records: [healthData],
            failedDateDetails: [],
            settings: settings,
            dateRangeStart: date,
            dateRangeEnd: date,
            connectedAppsEnabled: false
        )
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        XCTAssertEqual(envelope["daily_record_schema"] as? String, HealthMdExportSchema.identifier)
        XCTAssertEqual(envelope["daily_record_schema_version"] as? Int, HealthMdExportSchema.version)
        let records = try XCTUnwrap(envelope["records"] as? [[String: Any]])
        let daily = try XCTUnwrap(records.first)
        XCTAssertEqual(daily["schema"] as? String, HealthMdExportSchema.identifier)
        XCTAssertEqual(daily["schema_version"] as? Int, HealthMdExportSchema.version)
        let encodedArchive = try XCTUnwrap(daily["healthkit_record_archive"] as? [String: Any])
        XCTAssertEqual(encodedArchive["schema"] as? String, HealthKitRecordArchive.canonicalSchemaIdentifier)
        XCTAssertEqual(
            encodedArchive["schema_version"] as? Int,
            HealthKitRecordArchive.currentRecordSchemaVersion
        )
        XCTAssertEqual(encodedArchive["capture_status"] as? String, "complete")
    }

    func testAPIDailyRecordExactlyMatchesLocalJSONSnapshot() throws {
        let date = Self.day(2026, 7, 18)
        let healthData = HealthData(
            date: date,
            activity: ActivityData(steps: 2_500),
            heart: HeartData(restingHeartRate: 61)
        )
        let settings = makeSettings()
        Self.retainedSettings.append(settings)

        let localJSON = try healthData.exportThrowing(format: .json, settings: settings)
        let localData = try XCTUnwrap(localJSON.data(using: .utf8))
        let localRecord = try XCTUnwrap(
            JSONSerialization.jsonObject(with: localData) as? [String: Any]
        )

        let payload = try APIExportClient.makePayload(
            records: [healthData],
            failedDateDetails: [],
            settings: settings,
            dateRangeStart: date,
            dateRangeEnd: date,
            connectedAppsEnabled: false
        )
        let envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: payload) as? [String: Any]
        )
        let apiRecord = try XCTUnwrap((envelope["records"] as? [[String: Any]])?.first)

        XCTAssertTrue(NSDictionary(dictionary: apiRecord).isEqual(to: localRecord))
    }

    func testSerializedFailedDatesRemainInsideEnvelopeDateRange() throws {
        let start = Calendar.current.startOfDay(for: Self.day(2026, 7, 7))
        let end = Calendar.current.startOfDay(for: Self.day(2026, 7, 13))
        let failedDates = (0..<7).map {
            Calendar.current.date(byAdding: .day, value: $0, to: start)!
        }
        let settings = makeSettings()
        Self.retainedSettings.append(settings)

        let data = try APIExportClient.makePayload(
            records: [],
            failedDateDetails: failedDates.map {
                FailedDateDetail(date: $0, reason: .noHealthData)
            },
            settings: settings,
            dateRangeStart: start,
            dateRangeEnd: end,
            connectedAppsEnabled: false
        )
        let envelope = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let failedObjects = try XCTUnwrap(envelope["failed_date_details"] as? [Any])
        let failedData = try JSONSerialization.data(withJSONObject: failedObjects)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let serializedDetails = try decoder.decode([FailedDateDetail].self, from: failedData)

        XCTAssertEqual(serializedDetails.count, failedDates.count)
        XCTAssertTrue(serializedDetails.allSatisfy {
            $0.date >= start && $0.date <= end
        })
    }

    func testPreparedPayloadUploadSendsExactMeasuredBytes() async throws {
        ExternalIntegrationURLProtocolStub.reset()
        defer { ExternalIntegrationURLProtocolStub.reset() }
        let expectedBody = Data("{\"schema\":\"healthmd.api_export\",\"marker\":\"exact-bytes\"}".utf8)
        let endpoint = URL(string: "https://api.example.com/healthmd")!
        ExternalIntegrationURLProtocolStub.setHandler { request in
            XCTAssertEqual(request.url, endpoint)
            XCTAssertEqual(try request.externalIntegrationHTTPBody(), expectedBody)
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "application/json")
            return (
                HTTPURLResponse(
                    url: endpoint,
                    statusCode: 202,
                    httpVersion: "HTTP/1.1",
                    headerFields: nil
                )!,
                Data()
            )
        }

        let result = try await APIExportClient(
            session: .externalIntegrationTestSession()
        ).upload(
            payload: expectedBody,
            destination: APIExportDestinationSnapshot(
                endpointURL: endpoint,
                authorizationHeaderValue: "Bearer test-token",
                displayName: "api.example.com",
                redactedEndpointDescription: "https://api.example.com/healthmd"
            )
        )

        XCTAssertEqual(result.statusCode, 202)
    }

    func testServerRejectionDescriptionOmitsUntrustedResponseBody() {
        let error = APIExportClientError.serverRejected(
            statusCode: 413,
            body: "Authorization: Bearer secret-token; health_payload=private"
        )

        XCTAssertEqual(error.localizedDescription, "API endpoint returned HTTP 413.")
        XCTAssertFalse(error.localizedDescription.contains("secret-token"))
        XCTAssertFalse(error.localizedDescription.contains("health_payload"))
    }

    func testDisabledConnectedAppsKeepsActiveEnvelopeV1() throws {
        let date = Self.day(2026, 7, 13)
        var healthData = HealthData(date: date)
        healthData.activity.steps = 1234

        let settings = makeSettings()
        Self.retainedSettings.append(settings)
        let data = try APIExportClient.makePayload(
            records: [healthData],
            failedDateDetails: [],
            settings: settings,
            dateRangeStart: date,
            dateRangeEnd: date,
            connectedAppsEnabled: false
        )
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(json["schema_version"] as? Int, 1)
        XCTAssertNil(json["external_records"])
        XCTAssertNil(json["external_record_schema"])
    }

    private func makeSettings() -> AdvancedExportSettings {
        let suiteName = "APIExportClientTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        return AdvancedExportSettings(userDefaults: defaults)
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: year, month: month, day: day, hour: 12))!
    }
}
