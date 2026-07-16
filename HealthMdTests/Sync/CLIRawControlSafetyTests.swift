import Network
import XCTest
@testable import HealthMd

final class CLIRawControlSafetyTests: XCTestCase {
    func testStrictRequestAndCapabilitiesRoundTripWithLegacyDefaults() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let request = IPhoneExportRequest(
            jobID: UUID(),
            createdAt: date,
            dateRangeStart: date,
            dateRangeEnd: date,
            requestedBy: .cli,
            settingsPolicy: .requestedDatesOnly,
            responseMode: .rawJSON,
            rawProfile: .canonicalSourceRecordsV1
        )
        let decodedRequest = try JSONDecoder().decode(
            IPhoneExportRequest.self,
            from: JSONEncoder().encode(request)
        )
        XCTAssertEqual(decodedRequest.rawProfile, .canonicalSourceRecordsV1)

        let strictEnvelope = CanonicalRawResultEnvelope(
            createdAt: date,
            sourceDeviceName: "iPhone",
            requestedDates: ["2027-01-15"],
            days: [.failed(date: "2027-01-15", code: "healthkit_error")]
        )
        XCTAssertEqual(
            try JSONDecoder().decode(
                CanonicalRawResultEnvelope.self,
                from: JSONEncoder().encode(strictEnvelope)
            ),
            strictEnvelope
        )

        let current = SyncPeerCapabilities.current(platform: .iOS)
        XCTAssertTrue(current.supports(rawProfile: .canonicalSourceRecordsV1))
        XCTAssertEqual(current.canonicalArchiveSchemaVersions, [HealthKitRecordArchive.currentRecordSchemaVersion])
        XCTAssertEqual(current.canonicalRawResultSchemaVersions, [CanonicalRawResultEnvelope.currentSchemaVersion])

        let legacyRequestJSON = try JSONSerialization.data(withJSONObject: [
            "jobID": UUID().uuidString,
            "createdAt": date.timeIntervalSinceReferenceDate,
            "dateRangeStart": date.timeIntervalSinceReferenceDate,
            "dateRangeEnd": date.timeIntervalSinceReferenceDate,
            "requestedBy": "cli",
            "settingsPolicy": "requestedDatesOnly",
            "responseMode": "rawJSON"
        ])
        let legacyRequest = try JSONDecoder().decode(IPhoneExportRequest.self, from: legacyRequestJSON)
        XCTAssertNil(legacyRequest.rawProfile)

        let legacyCapabilitiesJSON = """
        {
          "protocolVersion": 2,
          "platform": "iOS",
          "supportsMacExportJobs": true,
          "supportsMacDestinationStatus": true,
          "supportsJobCancellation": true,
          "supportsGranularPayloads": true,
          "supportsIPhoneExportRequests": true
        }
        """.data(using: .utf8)!
        let legacyCapabilities = try JSONDecoder().decode(
            SyncPeerCapabilities.self,
            from: legacyCapabilitiesJSON
        )
        XCTAssertEqual(legacyCapabilities.canonicalArchiveSchemaVersions, [])
        XCTAssertEqual(legacyCapabilities.canonicalRawResultSchemaVersions, [])
        XCTAssertFalse(legacyCapabilities.supports(rawProfile: .canonicalSourceRecordsV1))
    }

    @MainActor
    func testStrictSettingsForceGranularWithoutPersistingSavedSetting() {
        let suite = "CLIRawControlSafetyTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let saved = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: defaults))
        saved.includeGranularData = false
        saved.generateWeeklyRollups = true

        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let request = IPhoneExportRequest(
            jobID: UUID(),
            createdAt: date,
            dateRangeStart: date,
            dateRangeEnd: date,
            requestedBy: .cli,
            settingsPolicy: .requestedDatesOnly,
            responseMode: .rawJSON,
            rawProfile: .canonicalSourceRecordsV1
        )
        let temporary = IPhoneExportRequestSettingsResolver.settings(for: request, savedSettings: saved)

        XCTAssertTrue(temporary.includeGranularData)
        XCTAssertFalse(temporary.generateWeeklyRollups)
        XCTAssertFalse(saved.includeGranularData)
        XCTAssertTrue(saved.generateWeeklyRollups)

        let reloaded = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: defaults))
        XCTAssertFalse(reloaded.includeGranularData)
        XCTAssertTrue(reloaded.generateWeeklyRollups)
    }

    func testStrictEnvelopeRetainsCompleteEmptyDayAsCanonicalSuccess() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let ownerDate = "2027-01-15"
        let archive = makeArchive(
            date: date,
            ownerDate: ownerDate,
            captureStatus: .complete,
            queryResults: [makeQuery(date: date, status: .success, count: 0)]
        )
        let record = HealthData(
            date: date,
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC"),
            healthKitRecordArchive: archive,
            healthKitRecordCaptureStatus: .complete
        )
        let customization = LifecycleHarness.retain(FormatCustomization())
        let day = try CanonicalRawDayResult.captured(record, customization: customization)
        let envelope = CanonicalRawResultEnvelope(
            createdAt: date,
            sourceDeviceName: "iPhone",
            requestedDates: [ownerDate],
            days: [day]
        )

        XCTAssertEqual(day.status, .completeEmpty)
        XCTAssertNotNil(day.canonicalDailyJSON)
        XCTAssertFalse(envelope.hasPartialResult)
        XCTAssertEqual(envelope.calculatedCaptureSummary.retainedDayCount, 1)
        XCTAssertEqual(envelope.calculatedCaptureSummary.completeEmptyDayCount, 1)

        let api = try envelope.controlAPIJSONObject()
        let apiDay = (api["days"] as? [[String: Any]])?.first
        let healthData = apiDay?["health_data"] as? [String: Any]
        XCTAssertEqual(healthData?["schema"] as? String, HealthMdExportSchema.identifier)
        XCTAssertNotNil(healthData?["schema_version"])
        XCTAssertNotNil(healthData?["time_context"])
        XCTAssertNotNil(healthData?["healthkit_record_archive"])

        let response = MacIPhoneExportRequestCoordinator.ExportResponse(
            status: .success,
            jobID: UUID(),
            message: "Complete",
            successCount: 1,
            totalCount: 1,
            filesWritten: 0,
            externalRecordCount: 0,
            destinationDisplayName: nil,
            destinationPath: nil,
            failureReason: nil,
            rawData: nil,
            rawResult: envelope
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let responseObject = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: response.controlAPIData(using: encoder)) as? [String: Any]
        )
        XCTAssertNil(responseObject["raw_data"])
        let rawResult = try XCTUnwrap(responseObject["raw_result"] as? [String: Any])
        let responseDay = try XCTUnwrap((rawResult["days"] as? [[String: Any]])?.first)
        XCTAssertTrue(responseDay["health_data"] is [String: Any])
        XCTAssertNil(responseDay["canonical_daily_json"])
    }

    func testControlAPIInjectionPreservesLargeCanonicalIntegers() throws {
        let canonicalJSON = """
        {"schema":"healthmd.health_data","schema_version":1,"time_context":{"calendar_timezone":"UTC","timestamp_timezone":"UTC"},"healthkit_record_archive":{},"large_unsigned":18446744073709551615}
        """
        let day = CanonicalRawDayResult(
            date: "2027-01-15",
            status: .complete,
            captureStatus: .complete,
            sampleCount: 1,
            recordCount: 1,
            queryStatusCounts: .init(),
            integrityWarningCount: 0,
            integrityWarningCodes: [],
            partialFailureCount: 0,
            partialFailureTypes: [],
            failureCode: nil,
            canonicalDailyJSON: canonicalJSON
        )
        let envelope = CanonicalRawResultEnvelope(
            createdAt: Date(timeIntervalSince1970: 1_800_000_000),
            sourceDeviceName: "iPhone",
            requestedDates: ["2027-01-15"],
            days: [day]
        )
        let response = MacIPhoneExportRequestCoordinator.ExportResponse(
            status: .success,
            jobID: UUID(),
            message: "Complete",
            successCount: 1,
            totalCount: 1,
            filesWritten: 0,
            externalRecordCount: 0,
            destinationDisplayName: nil,
            destinationPath: nil,
            failureReason: nil,
            rawData: nil,
            rawResult: envelope
        )
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try response.controlAPIData(using: encoder)
        XCTAssertTrue(String(decoding: data, as: UTF8.self).contains("18446744073709551615"))
    }

    func testStrictEnvelopeAggregatesPartialQueriesWarningsFailuresAndMissingDays() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let ownerDate = "2027-01-15"
        let archive = makeArchive(
            date: date,
            ownerDate: ownerDate,
            captureStatus: .partial,
            queryResults: [
                makeQuery(date: date, status: .success, count: 0),
                makeQuery(date: date, status: .unsupported, count: 0)
            ],
            warnings: [HealthKitRecordIntegrityWarning(code: "relationship_missing", message: "A related record was unavailable.")]
        )
        let record = HealthData(
            date: date,
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC"),
            partialFailures: [ExportPartialFailure(
                date: date,
                dataType: "workouts",
                dateRangeDescription: ownerDate,
                errorDescription: "Query did not complete."
            )],
            healthKitRecordArchive: archive,
            healthKitRecordCaptureStatus: .partial
        )
        let day = try CanonicalRawDayResult.captured(
            record,
            customization: LifecycleHarness.retain(FormatCustomization())
        )
        let envelope = CanonicalRawResultEnvelope(
            createdAt: date,
            sourceDeviceName: "iPhone",
            requestedDates: [ownerDate, "2027-01-16"],
            days: [day]
        )

        XCTAssertEqual(envelope.days.count, 2)
        XCTAssertEqual(envelope.days[0].status, .partial)
        XCTAssertEqual(envelope.days[1].status, .missing)
        XCTAssertEqual(envelope.missingDates, ["2027-01-16"])
        XCTAssertTrue(envelope.hasPartialResult)
        XCTAssertEqual(envelope.calculatedCaptureSummary.partialDayCount, 1)
        XCTAssertEqual(envelope.calculatedCaptureSummary.missingDayCount, 1)
        XCTAssertEqual(envelope.calculatedCaptureSummary.queryStatusCounts.success, 1)
        XCTAssertEqual(envelope.calculatedCaptureSummary.queryStatusCounts.unsupported, 1)
        XCTAssertEqual(envelope.calculatedCaptureSummary.integrityWarningCount, 1)
        XCTAssertEqual(envelope.calculatedCaptureSummary.partialFailureCount, 1)
    }

    @MainActor
    func testCoordinatorRejectsStrictRawProfileOnLegacyPeerWithoutDowngrade() async {
        let service = SyncService()
        service.connectionState = .connected
        service.remoteCapabilities = SyncPeerCapabilities(
            protocolVersion: SyncPeerCapabilities.currentProtocolVersion,
            appVersion: "old",
            buildNumber: "1",
            platform: .iOS,
            supportsMacExportJobs: true,
            supportsMacDestinationStatus: true,
            supportsJobCancellation: true,
            supportsGranularPayloads: true,
            supportsIPhoneExportRequests: true
        )
        let coordinator = MacIPhoneExportRequestCoordinator()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let response = await coordinator.requestExport(
            .init(
                startDate: date,
                endDate: date,
                requestedBy: .cli,
                settingsPolicy: .requestedDatesOnly,
                responseMode: .rawJSON,
                rawProfile: .canonicalSourceRecordsV1,
                waitTimeoutSeconds: 30
            ),
            syncService: service,
            destinationStatus: makeDestinationStatus()
        )

        XCTAssertEqual(response.status, .unavailable)
        XCTAssertEqual(response.failureReason, "unsupported_raw_profile")
        XCTAssertNil(response.rawData)
        XCTAssertNil(response.rawResult)
    }

    @MainActor
    func testCoordinatorMapsStrictIncompleteCaptureToPartialSuccess() async throws {
        let service = SyncService()
        service.connectionState = .connected
        service.remoteCapabilities = .current(platform: .iOS)
        let coordinator = MacIPhoneExportRequestCoordinator()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let task = Task { @MainActor in
            await coordinator.requestExport(
                .init(
                    startDate: date,
                    endDate: date,
                    requestedBy: .cli,
                    settingsPolicy: .requestedDatesOnly,
                    responseMode: .rawJSON,
                    rawProfile: .canonicalSourceRecordsV1,
                    waitTimeoutSeconds: 30
                ),
                syncService: service,
                destinationStatus: makeDestinationStatus()
            )
        }
        while coordinator.activeJobID == nil { await Task.yield() }
        let jobID = try XCTUnwrap(coordinator.activeJobID)
        let envelope = CanonicalRawResultEnvelope(
            createdAt: date,
            sourceDeviceName: "iPhone",
            requestedDates: ["2027-01-15"],
            days: [.failed(date: "2027-01-15", code: "healthkit_error")]
        )
        XCTAssertTrue(coordinator.complete(with: IPhoneExportRawDataPayload(
            jobID: jobID,
            createdAt: date,
            sourceDeviceName: "iPhone",
            dateRangeStart: date,
            dateRangeEnd: date,
            totalDays: 1,
            records: [],
            failedDateDetails: [],
            settingsSnapshot: makeSettingsSnapshot(),
            strictResult: envelope
        )))
        let response = await task.value

        XCTAssertEqual(response.status, .partialSuccess)
        XCTAssertEqual(response.failureReason, "incomplete_raw_capture")
        XCTAssertEqual(response.successCount, 0)
        XCTAssertNotNil(response.rawResult)
        XCTAssertNil(response.rawData)
    }

    @MainActor
    func testCoordinatorDisconnectSendsCancellationAndCompletesPendingRequest() async throws {
        let service = SyncService()
        service.connectionState = .connected
        service.remoteCapabilities = .current(platform: .iOS)
        var sentMessages: [SyncMessage] = []
        service.testMessageSendObserver = { sentMessages.append($0) }

        let coordinator = MacIPhoneExportRequestCoordinator()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let task = Task { @MainActor in
            await coordinator.requestExport(
                .init(
                    startDate: date,
                    endDate: date,
                    requestedBy: .cli,
                    settingsPolicy: .requestedDatesOnly,
                    responseMode: .rawJSON,
                    rawProfile: .canonicalSourceRecordsV1,
                    waitTimeoutSeconds: 30
                ),
                syncService: service,
                destinationStatus: makeDestinationStatus()
            )
        }
        while coordinator.activeJobID == nil { await Task.yield() }
        let jobID = try XCTUnwrap(coordinator.activeJobID)
        coordinator.cancelActiveRequestForDisconnect()
        let response = await task.value

        XCTAssertEqual(response.status, .unavailable)
        XCTAssertEqual(response.failureReason, "iphone_disconnected")
        XCTAssertTrue(sentMessages.contains { message in
            if case .iphoneExportCancel(jobID: let cancelledID) = message {
                return cancelledID == jobID
            }
            return false
        })
    }

    @MainActor
    func testCoordinatorTimeoutSendsCancellationAndIgnoresLateStrictResult() async throws {
        let service = SyncService()
        service.connectionState = .connected
        service.remoteCapabilities = .current(platform: .iOS)
        var sentMessages: [SyncMessage] = []
        service.testMessageSendObserver = { sentMessages.append($0) }

        let coordinator = MacIPhoneExportRequestCoordinator()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let response = await coordinator.requestExport(
            .init(
                startDate: date,
                endDate: date,
                requestedBy: .cli,
                settingsPolicy: .requestedDatesOnly,
                responseMode: .rawJSON,
                rawProfile: .canonicalSourceRecordsV1,
                waitTimeoutSeconds: 0.02
            ),
            syncService: service,
            destinationStatus: makeDestinationStatus()
        )

        XCTAssertEqual(response.status, .timedOut)
        let jobID = try XCTUnwrap(response.jobID)
        XCTAssertTrue(sentMessages.contains { message in
            if case .iphoneExportCancel(jobID: let cancelledID) = message {
                return cancelledID == jobID
            }
            return false
        })

        let envelope = CanonicalRawResultEnvelope(
            createdAt: date,
            sourceDeviceName: "iPhone",
            requestedDates: ["2027-01-15"],
            days: [.failed(date: "2027-01-15", code: "late")]
        )
        let latePayload = IPhoneExportRawDataPayload(
            jobID: jobID,
            createdAt: date,
            sourceDeviceName: "iPhone",
            dateRangeStart: date,
            dateRangeEnd: date,
            totalDays: 1,
            records: [],
            failedDateDetails: [],
            settingsSnapshot: makeSettingsSnapshot(),
            strictResult: envelope
        )
        XCTAssertFalse(coordinator.complete(with: latePayload))
    }

    func testControlServerLoopbackFramingValidationAndTimeoutBounds() throws {
        XCTAssertTrue(HealthMdControlServer.isLoopbackEndpoint(.hostPort(
            host: NWEndpoint.Host("127.0.0.1"), port: 17645
        )))
        XCTAssertTrue(HealthMdControlServer.isLoopbackEndpoint(.hostPort(
            host: NWEndpoint.Host("::1"), port: 17645
        )))
        XCTAssertFalse(HealthMdControlServer.isLoopbackEndpoint(.hostPort(
            host: NWEndpoint.Host("192.168.1.10"), port: 17645
        )))

        let oversizedHeader = Data(repeating: 65, count: HealthMdControlServer.maximumHeaderBytes + 1)
        XCTAssertEqual(
            HealthMdControlServer.framingDecision(for: oversizedHeader),
            .reject(statusCode: 431, error: "request_headers_too_large")
        )
        let oversizedBodyRequest = Data("POST /v1/exports HTTP/1.1\r\nContent-Length: \(HealthMdControlServer.maximumBodyBytes + 1)\r\n\r\n".utf8)
        XCTAssertEqual(
            HealthMdControlServer.framingDecision(for: oversizedBodyRequest),
            .reject(statusCode: 413, error: "request_body_too_large")
        )
        XCTAssertEqual(
            HealthMdControlServer.framingDecision(for: Data("GET /v1/status HTTP/1.1\r\n".utf8)),
            .incomplete
        )
        XCTAssertEqual(HealthMdControlServer.receiveDeadlineSeconds, 10)

        XCTAssertFalse(HealthMdControlServer.isValidWaitTimeout(.nan))
        XCTAssertFalse(HealthMdControlServer.isValidWaitTimeout(.infinity))
        XCTAssertFalse(HealthMdControlServer.isValidWaitTimeout(4.999))
        XCTAssertTrue(HealthMdControlServer.isValidWaitTimeout(5))
        XCTAssertTrue(HealthMdControlServer.isValidWaitTimeout(900))
        XCTAssertFalse(HealthMdControlServer.isValidWaitTimeout(900.001))

        let wrongMethod = HealthMdControlServer.ParsedHTTPRequest(
            method: "DELETE",
            path: "/v1/exports",
            headers: [:],
            body: Data()
        )
        XCTAssertEqual(
            HealthMdControlServer.validationDecision(for: wrongMethod),
            .reject(statusCode: 405, error: "method_not_allowed")
        )
        let wrongContentType = HealthMdControlServer.ParsedHTTPRequest(
            method: "POST",
            path: "/v1/exports",
            headers: ["content-length": "2", "content-type": "text/plain"],
            body: Data("{}".utf8)
        )
        XCTAssertEqual(
            HealthMdControlServer.validationDecision(for: wrongContentType),
            .reject(statusCode: 415, error: "application_json_required")
        )
        let validPost = HealthMdControlServer.ParsedHTTPRequest(
            method: "POST",
            path: "/v1/exports",
            headers: ["content-length": "2", "content-type": "application/json; charset=utf-8"],
            body: Data("{}".utf8)
        )
        XCTAssertEqual(HealthMdControlServer.validationDecision(for: validPost), .valid)
    }

    private func makeArchive(
        date: Date,
        ownerDate: String,
        captureStatus: HealthKitRecordCaptureStatus,
        queryResults: [HealthKitQueryResult],
        warnings: [HealthKitRecordIntegrityWarning] = []
    ) -> HealthKitRecordArchive {
        HealthKitRecordArchive(
            captureStatus: captureStatus,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: ownerDate,
                intervalStart: date,
                intervalEnd: date.addingTimeInterval(86_400),
                calendarTimeZoneIdentifier: "UTC"
            ),
            queryManifest: HealthKitQueryManifest(results: queryResults),
            integrityWarnings: warnings
        )
    }

    private func makeQuery(
        date: Date,
        status: HealthKitQueryResultStatus,
        count: Int
    ) -> HealthKitQueryResult {
        HealthKitQueryResult(
            identifier: "HKQuantityTypeIdentifierStepCount.\(status.rawValue)",
            objectTypeIdentifier: "HKQuantityTypeIdentifierStepCount",
            operation: "sampleQuery",
            metricIDs: ["steps"],
            interval: HealthKitQueryInterval(startDate: date, endDate: date.addingTimeInterval(86_400)),
            status: status,
            recordCount: count
        )
    }

    @MainActor
    private func makeDestinationStatus() -> MacDestinationStatus {
        MacDestinationStatus(
            isConnected: true,
            isReadyForExports: true,
            destinationFolderSelected: true,
            folderAccessHealthy: true,
            destinationDisplayName: "Exports",
            destinationPathForDisplay: nil,
            lastError: nil,
            activeJobID: nil,
            capabilities: .current(platform: .macOS)
        )
    }

    @MainActor
    private func makeSettingsSnapshot() -> ExportSettingsSnapshot {
        let suite = "CLIRawControlSafetyTests.snapshot.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: defaults))
        settings.includeGranularData = true
        return .from(settings)
    }
}
