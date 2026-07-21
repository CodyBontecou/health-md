import XCTest
@testable import HealthMd

#if os(macOS)
import Network
#endif

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

    #if os(macOS)
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
        XCTAssertFalse(temporary.summaryOnlyModeEnabled)
        XCTAssertFalse(saved.includeGranularData)
        XCTAssertTrue(saved.generateWeeklyRollups)

        let reloaded = LifecycleHarness.retain(AdvancedExportSettings(userDefaults: defaults))
        XCTAssertFalse(reloaded.includeGranularData)
        XCTAssertTrue(reloaded.generateWeeklyRollups)
    }
    #endif

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

        #if os(macOS)
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
        #endif
    }

    #if os(macOS)
    func testFileControlResponseReportsDailyNoteOnlyCountsWithoutFiles() throws {
        let response = MacIPhoneExportRequestCoordinator.ExportResponse(
            status: .success,
            jobID: UUID(),
            message: "Updated 2 daily notes",
            successCount: 2,
            totalCount: 2,
            filesWritten: 0,
            externalRecordCount: 0,
            dailyNotesUpdated: 2,
            dailyNotesSkipped: nil,
            destinationDisplayName: "Vault",
            destinationPath: "/tmp/Vault",
            failureReason: nil,
            rawData: nil,
            rawResult: nil
        )
        let data = try JSONEncoder().encode(response)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])

        XCTAssertEqual(object["files_written"] as? Int, 0)
        XCTAssertEqual(object["daily_notes_updated"] as? Int, 2)
        XCTAssertNil(object["daily_notes_skipped"])
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
    #endif

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

    func testStrictValidationRejectsWrongAndDuplicateDateSets() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let wrongDates = CanonicalRawResultEnvelope(
            createdAt: date,
            sourceDeviceName: "iPhone",
            requestedDates: ["2027-01-15", "2027-01-17"],
            days: [
                .failed(date: "2027-01-15", code: "healthkit_error"),
                .failed(date: "2027-01-17", code: "healthkit_error")
            ]
        )
        XCTAssertTrue(wrongDates.strictValidationIssues(
            expectedDates: ["2027-01-15", "2027-01-16"]
        ).contains("raw_result_date_set_mismatch"))

        let valid = CanonicalRawResultEnvelope(
            createdAt: date,
            sourceDeviceName: "iPhone",
            requestedDates: ["2027-01-15", "2027-01-16"],
            days: [
                .failed(date: "2027-01-15", code: "healthkit_error"),
                .failed(date: "2027-01-16", code: "healthkit_error")
            ]
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(valid)) as? [String: Any]
        )
        let days = try XCTUnwrap(object["days"] as? [[String: Any]])
        object["days"] = [days[0], days[0]]
        let duplicated = try JSONDecoder().decode(
            CanonicalRawResultEnvelope.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        let duplicateIssues = duplicated.strictValidationIssues(
            expectedDates: ["2027-01-15", "2027-01-16"]
        )
        XCTAssertTrue(duplicateIssues.contains("raw_result_duplicate_dates"))
        XCTAssertTrue(duplicateIssues.contains("raw_result_date_set_mismatch"))
    }

    func testStrictValidationRejectsWrongDailyVersionAndMissingArchive() {
        func day(json: String) -> CanonicalRawDayResult {
            CanonicalRawDayResult(
                date: "2027-01-15",
                status: .complete,
                captureStatus: .complete,
                sampleCount: 0,
                recordCount: 0,
                queryStatusCounts: .init(),
                integrityWarningCount: 0,
                integrityWarningCodes: [],
                partialFailureCount: 0,
                partialFailureTypes: [],
                failureCode: nil,
                canonicalDailyJSON: json
            )
        }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let wrongVersion = CanonicalRawResultEnvelope(
            createdAt: date,
            sourceDeviceName: "iPhone",
            requestedDates: ["2027-01-15"],
            days: [day(json: """
            {"schema":"healthmd.health_data","schema_version":5,"healthkit_record_archive":{"schema":"healthmd.healthkit_records","schema_version":1}}
            """)]
        )
        XCTAssertTrue(wrongVersion.strictValidationIssues(
            expectedDates: ["2027-01-15"]
        ).contains("daily_schema_version_mismatch:2027-01-15"))

        let missingArchive = CanonicalRawResultEnvelope(
            createdAt: date,
            sourceDeviceName: "iPhone",
            requestedDates: ["2027-01-15"],
            days: [day(json: """
            {"schema":"healthmd.health_data","schema_version":\(HealthMdExportSchema.version)}
            """)]
        )
        XCTAssertTrue(missingArchive.strictValidationIssues(
            expectedDates: ["2027-01-15"]
        ).contains("canonical_archive_missing:2027-01-15"))
    }

    #if os(macOS)
    @MainActor
    func testCoordinatorAllowsMultiYearCorpusRequest() async throws {
        let service = SyncService()
        service.connectionState = .connected
        service.remoteCapabilities = .current(platform: .iOS)
        var sentRequest: IPhoneExportRequest?
        service.testMessageSendObserver = { message in
            if case .iphoneExportRequest(let request) = message {
                sentRequest = request
            }
        }
        let coordinator = MacIPhoneExportRequestCoordinator()
        let calendar = Calendar.current
        let end = calendar.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let start = try XCTUnwrap(calendar.date(byAdding: .day, value: -999, to: end))

        let task = Task { @MainActor in
            await coordinator.requestExport(
                .init(
                    startDate: start,
                    endDate: end,
                    requestedBy: .cli,
                    settingsPolicy: .requestedDatesOnly,
                    responseMode: .writeFiles,
                    rawProfile: nil,
                    waitTimeoutSeconds: 30
                ),
                syncService: service,
                destinationStatus: makeDestinationStatus()
            )
        }
        while coordinator.activeJobID == nil { await Task.yield() }
        let jobID = try XCTUnwrap(coordinator.activeJobID)

        XCTAssertEqual(sentRequest?.dateRangeStart, start)
        XCTAssertEqual(sentRequest?.dateRangeEnd, end)
        XCTAssertEqual(ExportOrchestrator.dateRange(from: start, to: end).count, 1_000)

        coordinator.complete(with: MacExportFailure(
            jobID: jobID,
            reason: .cancelled,
            message: "Test cleanup"
        ))
        let response = await task.value
        XCTAssertEqual(response.status, .cancelled)
    }

    @MainActor
    func testCoordinatorPinsAllAvailableHistoryFromIPhoneAcknowledgement() async throws {
        let service = SyncService()
        service.connectionState = .connected
        service.remoteCapabilities = .current(platform: .iOS)
        var sentRequest: IPhoneExportRequest?
        service.testMessageSendObserver = { message in
            if case .iphoneExportRequest(let request) = message {
                sentRequest = request
            }
        }
        let coordinator = MacIPhoneExportRequestCoordinator()
        let placeholder = Date(timeIntervalSince1970: 1_800_000_000)
        let resolvedStart = Date(timeIntervalSince1970: 1_700_006_400)
        let resolvedEnd = Date(timeIntervalSince1970: 1_700_092_800)
        let identifiers = ["2023-11-15", "2023-11-16"]

        let task = Task { @MainActor in
            await coordinator.requestExport(
                .init(
                    dateSelection: .allAvailable,
                    startDate: placeholder,
                    endDate: placeholder,
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
        XCTAssertEqual(sentRequest?.dateSelection, .allAvailable)
        XCTAssertNil(sentRequest?.requestedDateIdentifiers)

        coordinator.handleAccepted(IPhoneExportAcknowledgement(
            jobID: jobID,
            acceptedAt: placeholder,
            message: "Pinned all history",
            resolvedDateRangeStart: resolvedStart,
            resolvedDateRangeEnd: resolvedEnd,
            resolvedDateIdentifiers: identifiers
        ))
        let envelope = CanonicalRawResultEnvelope(
            createdAt: placeholder,
            sourceDeviceName: "iPhone",
            requestedDates: identifiers,
            days: identifiers.map { .failed(date: $0, code: "healthkit_error") }
        )
        XCTAssertTrue(coordinator.complete(with: envelope, jobID: jobID))
        let response = await task.value

        XCTAssertEqual(response.status, .partialSuccess)
        XCTAssertEqual(response.totalCount, 2)
    }

    @MainActor
    func testCoordinatorRejectsAllAvailableHistoryOnLegacyPeer() async {
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
                dateSelection: .allAvailable,
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
        XCTAssertEqual(response.failureReason, "unsupported_all_available_history")
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
        XCTAssertTrue(coordinator.complete(with: envelope, jobID: jobID))
        let response = await task.value

        XCTAssertEqual(response.status, .partialSuccess)
        XCTAssertEqual(response.failureReason, "incomplete_raw_capture")
        XCTAssertEqual(response.successCount, 0)
        XCTAssertNotNil(response.rawResult)
        XCTAssertNil(response.rawData)
    }

    @MainActor
    func testCoordinatorReturnsDiskBackedStrictCorpusControlResponse() async throws {
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
        let dayURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "strict-spool-day-test")
        try JSONEncoder().encode(
            CanonicalRawDayResult.failed(date: "2027-01-15", code: "healthkit_error")
        ).write(to: dayURL)
        defer { try? FileManager.default.removeItem(at: dayURL) }
        let strictSpool = try await CanonicalRawResultSpoolWriter.write(
            createdAt: date,
            sourceDeviceName: "iPhone",
            expectedDates: ["2027-01-15"],
            dayFiles: [dayURL]
        )

        let completed = await coordinator.complete(with: strictSpool, jobID: jobID)
        XCTAssertTrue(completed)
        let response = await task.value
        let controlSpool = try XCTUnwrap(response.spooledControlResponse)
        defer { controlSpool.remove() }
        XCTAssertEqual(response.status, .partialSuccess)
        XCTAssertNil(response.rawResult)
        XCTAssertEqual(try ConnectedTransferFile.inspect(controlSpool.url).sha256, controlSpool.sha256)
        let object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: controlSpool.url)) as? [String: Any]
        )
        XCTAssertEqual(object["status"] as? String, "partial_success")
        let rawResult = try XCTUnwrap(object["raw_result"] as? [String: Any])
        XCTAssertEqual(rawResult["schema"] as? String, CanonicalRawResultEnvelope.schemaIdentifier)
    }

    @MainActor
    func testCoordinatorRejectsWrongSameCountStrictDateSet() async throws {
        let service = SyncService()
        service.connectionState = .connected
        service.remoteCapabilities = .current(platform: .iOS)
        let coordinator = MacIPhoneExportRequestCoordinator()
        let start = Calendar.current.date(from: DateComponents(
            year: 2027,
            month: 1,
            day: 15,
            hour: 12
        ))!
        let end = Calendar.current.date(byAdding: .day, value: 1, to: start)!
        let task = Task { @MainActor in
            await coordinator.requestExport(
                .init(
                    startDate: start,
                    endDate: end,
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
            createdAt: start,
            sourceDeviceName: "iPhone",
            requestedDates: ["2027-01-15", "2027-01-17"],
            days: [
                .failed(date: "2027-01-15", code: "healthkit_error"),
                .failed(date: "2027-01-17", code: "healthkit_error")
            ]
        )

        XCTAssertFalse(coordinator.complete(with: envelope, jobID: jobID))
        let response = await task.value
        XCTAssertEqual(response.status, .failure)
        XCTAssertEqual(response.failureReason, "raw_profile_response_mismatch")
        XCTAssertNil(response.rawResult)
    }

    @MainActor
    func testCoordinatorRejectsWholePayloadFallbackForStrictRaw() async throws {
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
        XCTAssertEqual(response.status, .failure)
        XCTAssertEqual(response.failureReason, "strict_raw_stream_required")
        XCTAssertNil(response.rawResult)
    }

    @MainActor
    func testCoordinatorDisconnectPausesAndDetachesWithoutCancellation() async throws {
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

        XCTAssertEqual(response.status, .accepted)
        XCTAssertEqual(response.paused, true)
        XCTAssertFalse(sentMessages.contains { message in
            if case .iphoneExportCancel(jobID: let cancelledID) = message { return cancelledID == jobID }
            return false
        })
        XCTAssertFalse(sentMessages.contains { message in
            if case .connectedTransferAbort(let abort) = message { return abort.jobID == jobID }
            return false
        })
        XCTAssertEqual(coordinator.jobResponse(jobID: jobID).paused, true)
    }

    @MainActor
    func testCoordinatorTimeoutDetachesWithoutCancellingAndAcceptsLateResult() async throws {
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
        XCTAssertFalse(sentMessages.contains { message in
            if case .iphoneExportCancel(jobID: let cancelledID) = message { return cancelledID == jobID }
            return false
        })

        let envelope = CanonicalRawResultEnvelope(
            createdAt: date,
            sourceDeviceName: "iPhone",
            requestedDates: ["2027-01-15"],
            days: [.failed(date: "2027-01-15", code: "late")]
        )
        XCTAssertTrue(coordinator.complete(with: envelope, jobID: jobID))
        XCTAssertEqual(coordinator.jobResponse(jobID: jobID).status, .partialSuccess)
    }

    @MainActor
    func testCoordinatorPersistsDurableCorpusStatusFrontier() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("durable-corpus-status-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let service = SyncService()
        let peerInstallationID = UUID()
        service.connectionState = .connected
        service.remoteCapabilities = .current(
            platform: .iOS,
            installationID: peerInstallationID
        )
        let coordinator = MacIPhoneExportRequestCoordinator(rootURL: root, now: { date })
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
        let jobID = try XCTUnwrap(response.jobID)
        service.connectionState = .connected
        service.remoteCapabilities = .current(
            platform: .iOS,
            installationID: peerInstallationID
        )
        let sessionID = UUID()
        let fingerprint = ConnectedCorpusRequestFingerprint(
            sha256: String(repeating: "a", count: 64)
        )
        coordinator.handleCorpusStatus(
            ConnectedCorpusProgressSnapshot(
                jobID: jobID,
                sessionID: sessionID,
                requestFingerprint: fingerprint,
                state: .paused,
                processedDays: 183,
                totalDays: 365,
                committedPartitionCount: 41,
                committedBytes: 2_147_483_648,
                currentDate: date,
                message: "Waiting for iPhone",
                updatedAt: date,
                expiresAt: date.addingTimeInterval(7 * 24 * 60 * 60)
            ),
            syncService: service
        )
        coordinator.handleCorpusStatus(
            ConnectedCorpusProgressSnapshot(
                jobID: jobID,
                sessionID: sessionID,
                requestFingerprint: fingerprint,
                state: .preparing,
                processedDays: 12,
                totalDays: 365,
                committedPartitionCount: 3,
                committedBytes: 64,
                currentDate: date.addingTimeInterval(-86_400),
                message: "Delayed pre-ack status",
                updatedAt: date.addingTimeInterval(-60),
                expiresAt: date.addingTimeInterval(7 * 24 * 60 * 60)
            ),
            syncService: service
        )
        XCTAssertEqual(coordinator.jobResponse(jobID: jobID).durableState, "paused")

        coordinator.handlePreparationProgress(IPhoneExportPreparationProgress(
            jobID: jobID,
            processedDays: 2,
            totalDays: 365,
            currentDate: date.addingTimeInterval(-86_400),
            message: "Delayed preparation progress"
        ))
        XCTAssertEqual(coordinator.jobResponse(jobID: jobID).durableState, "paused")
        coordinator.handlePeerDisconnectForResume()

        let restored = MacIPhoneExportRequestCoordinator(
            rootURL: root,
            now: { date.addingTimeInterval(60) }
        )
        let status = restored.jobResponse(jobID: jobID)
        XCTAssertEqual(status.paused, true)
        XCTAssertEqual(status.durable, true)
        XCTAssertEqual(status.durableState, "paused")
        XCTAssertEqual(status.sessionID, sessionID)
        XCTAssertEqual(status.processedDays, 183)
        XCTAssertEqual(status.committedPartitions, 41)
        XCTAssertEqual(status.committedBytes, 2_147_483_648)
    }

    @MainActor
    func testCoordinatorRejectsInboundProgressAndCompletionAfterFixedExpiry() async throws {
        var clock = Date(timeIntervalSince1970: 1_800_000_000)
        let service = SyncService()
        service.connectionState = .connected
        service.remoteCapabilities = .current(platform: .iOS, installationID: UUID())
        let coordinator = MacIPhoneExportRequestCoordinator(now: { clock })
        let response = await coordinator.requestExport(
            .init(
                startDate: clock,
                endDate: clock,
                requestedBy: .cli,
                settingsPolicy: .requestedDatesOnly,
                responseMode: .rawJSON,
                rawProfile: .canonicalSourceRecordsV1,
                waitTimeoutSeconds: 0.02
            ),
            syncService: service,
            destinationStatus: makeDestinationStatus()
        )
        let jobID = try XCTUnwrap(response.jobID)
        clock = clock.addingTimeInterval(8 * 24 * 60 * 60)

        coordinator.handlePreparationProgress(IPhoneExportPreparationProgress(
            jobID: jobID,
            processedDays: 1,
            totalDays: 1,
            currentDate: clock,
            message: "Late progress"
        ))
        XCTAssertFalse(coordinator.complete(with: MacExportFailure(
            jobID: jobID,
            reason: .exportWriteFailure,
            message: "Late completion",
            underlyingError: nil,
            occurredAt: clock
        )))
        let status = coordinator.jobResponse(jobID: jobID)
        XCTAssertEqual(status.status, .unavailable)
        XCTAssertEqual(status.failureReason, "job_not_found")
    }

    @MainActor
    func testCoordinatorTerminalCorpusStatusPersistsFinalFrontierAndWireState() async throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let service = SyncService()
        let peerInstallationID = UUID()
        service.connectionState = .connected
        service.remoteCapabilities = .current(
            platform: .iOS,
            installationID: peerInstallationID
        )
        let coordinator = MacIPhoneExportRequestCoordinator(now: { date })
        var locallyTerminatedJobID: UUID?
        var terminalStatusRequestedPeerNotification: Bool?
        coordinator.onRequestTermination = { jobID, notifyPeer in
            locallyTerminatedJobID = jobID
            terminalStatusRequestedPeerNotification = notifyPeer
        }
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
        let jobID = try XCTUnwrap(response.jobID)
        service.connectionState = .connected
        service.remoteCapabilities = .current(
            platform: .iOS,
            installationID: peerInstallationID
        )
        let sessionID = UUID()
        coordinator.handleCorpusStatus(
            ConnectedCorpusProgressSnapshot(
                jobID: jobID,
                sessionID: sessionID,
                requestFingerprint: ConnectedCorpusRequestFingerprint(
                    sha256: String(repeating: "b", count: 64)
                ),
                state: .expired,
                processedDays: 90,
                totalDays: 100,
                committedPartitionCount: 22,
                committedBytes: 987_654_321,
                message: "Durable iPhone checkpoint expired.",
                updatedAt: date,
                expiresAt: date
            ),
            syncService: service
        )

        let status = coordinator.jobResponse(jobID: jobID)
        XCTAssertEqual(status.status, .failure)
        XCTAssertEqual(status.durableState, "expired")
        XCTAssertEqual(status.sessionID, sessionID)
        XCTAssertEqual(status.processedDays, 90)
        XCTAssertEqual(status.committedPartitions, 22)
        XCTAssertEqual(status.committedBytes, 987_654_321)
        XCTAssertEqual(locallyTerminatedJobID, jobID)
        XCTAssertEqual(terminalStatusRequestedPeerNotification, false)
    }

    @MainActor
    func testCoordinatorCancelDoesNotTargetDifferentIPhoneInstallation() async throws {
        let service = SyncService()
        let originalPeerID = UUID()
        service.connectionState = .connected
        service.remoteCapabilities = .current(platform: .iOS, installationID: originalPeerID)
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
        let jobID = try XCTUnwrap(response.jobID)

        var sentRemoteCancellation = false
        var cancelledLocalSession = false
        service.connectionState = .connected
        service.remoteCapabilities = .current(platform: .iOS, installationID: UUID())
        service.testMessageSendObserver = { message in
            switch message {
            case .iphoneExportCancel, .connectedTransferAbort:
                sentRemoteCancellation = true
            default:
                break
            }
        }
        coordinator.onRequestTermination = { cancelledJobID, notifyPeer in
            cancelledLocalSession = cancelledJobID == jobID
            XCTAssertFalse(notifyPeer)
        }

        let cancellation = coordinator.cancelExport(jobID: jobID, syncService: service)
        XCTAssertEqual(cancellation.status, .cancelled)
        XCTAssertTrue(cancelledLocalSession)
        XCTAssertFalse(sentRemoteCancellation)

        service.remoteCapabilities = .current(
            platform: .iOS,
            installationID: originalPeerID
        )
        coordinator.resumePausedJobsAfterHello(
            syncService: service,
            destinationStatus: makeDestinationStatus()
        )
        XCTAssertTrue(sentRemoteCancellation, "The cancellation tombstone must reach the bound iPhone after reconnect")
    }

    @MainActor
    func testCoordinatorMigratesLegacyUnboundJobOnlyForAuthenticatedLivePeer() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("durable-v1-binding-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let jobID = UUID()
        let sourceInstallationID = UUID()
        let service = SyncService()
        service.connectionState = .connected
        service.remoteCapabilities = .current(
            platform: .iOS,
            installationID: sourceInstallationID
        )
        let coordinator = MacIPhoneExportRequestCoordinator(rootURL: root, now: { date })
        _ = await coordinator.requestExport(
            .init(
                jobID: jobID,
                startDate: date,
                endDate: date,
                requestedDateIdentifiers: ["2027-01-15"],
                requestedBy: .cli,
                settingsPolicy: .requestedDatesOnly,
                responseMode: .writeFiles,
                rawProfile: nil,
                waitTimeoutSeconds: 0.02
            ),
            syncService: service,
            destinationStatus: makeDestinationStatus()
        )

        let recordURL = root
            .appendingPathComponent(jobID.uuidString, isDirectory: true)
            .appendingPathComponent("record.json")
        var persisted = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: recordURL)) as? [String: Any]
        )
        persisted["version"] = 1
        persisted.removeValue(forKey: "sourceInstallationID")
        persisted.removeValue(forKey: "destinationInstallationID")
        try JSONSerialization.data(withJSONObject: persisted, options: [.sortedKeys])
            .write(to: recordURL, options: .atomic)

        let settings = makeSettingsSnapshot()
        let manifest = ConnectedCorpusExportManifest(
            mode: .writeFiles,
            createdAt: date,
            sourceDeviceName: "Legacy iPhone",
            dateRangeStart: date,
            dateRangeEnd: date,
            requestedDates: [date],
            requestedDateIdentifiers: ["2027-01-15"],
            transferDates: [date],
            settingsSnapshot: settings,
            requestedTarget: nil
        )
        let sessionID = UUID()
        let fingerprint = try ConnectedCorpusRequestFingerprint.make(for: manifest)
        let binding = ConnectedCorpusPeerBinding(
            sourceInstallationID: sourceInstallationID,
            destinationInstallationID: service.installationID
        )
        let session = ConnectedCorpusTransferSession(
            sessionID: sessionID,
            jobID: jobID,
            requestFingerprint: fingerprint,
            protocolVersion: 2,
            createdAt: date,
            peerBinding: binding
        )
        let open = ConnectedCorpusTransferOpen(
            session: session,
            partition: ConnectedCorpusPartitionDescriptor(
                sessionID: sessionID,
                jobID: jobID,
                index: 0,
                sourceDates: [date],
                byteCount: 1,
                sha256: String(repeating: "a", count: 64),
                previousSHA256: nil
            ),
            exportManifest: manifest
        )

        let restored = MacIPhoneExportRequestCoordinator(rootURL: root, now: { date })
        XCTAssertTrue(restored.accepts(
            open,
            localInstallationID: service.installationID,
            remoteInstallationID: sourceInstallationID
        ))

        let migrated = MacIPhoneExportRequestCoordinator(rootURL: root, now: { date })
        XCTAssertFalse(migrated.accepts(
            open,
            localInstallationID: service.installationID,
            remoteInstallationID: UUID()
        ))
        XCTAssertTrue(migrated.accepts(
            open,
            localInstallationID: service.installationID,
            remoteInstallationID: sourceInstallationID
        ))
    }

    @MainActor
    func testCoordinatorRestoresExactPausedRequestAndFixedExpiry() async throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("durable-job-test-\(UUID().uuidString)", isDirectory: true)
        defer { try? FileManager.default.removeItem(at: root) }
        let service = SyncService()
        service.connectionState = .connected
        service.remoteCapabilities = .current(platform: .iOS)
        var original: IPhoneExportRequest?
        service.testMessageSendObserver = { message in
            if case .iphoneExportRequest(let request) = message { original = request }
        }
        let coordinator = MacIPhoneExportRequestCoordinator(rootURL: root)
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let task = Task { @MainActor in
            await coordinator.requestExport(
                .init(
                    startDate: date,
                    endDate: date,
                    requestedDateIdentifiers: ["2027-01-15"],
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
        coordinator.handlePeerDisconnectForResume()
        _ = await task.value

        let restored = MacIPhoneExportRequestCoordinator(rootURL: root)
        let restoredStatus = restored.jobResponse(jobID: jobID)
        XCTAssertEqual(restoredStatus.status, .preparing)
        XCTAssertEqual(restoredStatus.paused, true)
        let expiresAt = try XCTUnwrap(restoredStatus.expiresAt)
        XCTAssertEqual(
            expiresAt.timeIntervalSince(try XCTUnwrap(original?.createdAt)),
            MacIPhoneExportRequestCoordinator.jobLifetime,
            accuracy: 0.001
        )

        var resent: IPhoneExportRequest?
        service.connectionState = .connected
        service.remoteCapabilities = .current(platform: .iOS, installationID: UUID())
        service.testMessageSendObserver = { message in
            if case .iphoneExportRequest(let request) = message { resent = request }
        }
        restored.resumePausedJobsAfterHello(
            syncService: service,
            destinationStatus: makeDestinationStatus()
        )
        XCTAssertNil(resent, "A different iPhone installation must not receive the durable request")

        service.remoteCapabilities = .current(platform: .iOS)
        restored.resumePausedJobsAfterHello(
            syncService: service,
            destinationStatus: makeDestinationStatus()
        )
        XCTAssertEqual(resent, original)
        XCTAssertEqual(restored.cancelExport(jobID: jobID, syncService: service).status, .cancelled)
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

        let generatedJobID = UUID()
        let enrichedPost = try HealthMdControlServer.requestByInjectingExportJobID(
            generatedJobID,
            into: validPost
        )
        XCTAssertEqual(HealthMdControlServer.exportJobID(from: enrichedPost.body), generatedJobID)

        let statusPath = "/v1/exports/\(generatedJobID.uuidString.lowercased())"
        XCTAssertEqual(HealthMdControlServer.exportJobRoute(statusPath)?.jobID, generatedJobID)
        XCTAssertNil(HealthMdControlServer.exportJobRoute(statusPath)?.action)
        let resumeRequest = HealthMdControlServer.ParsedHTTPRequest(
            method: "POST",
            path: statusPath + "/resume",
            headers: ["content-length": "2", "content-type": "application/json"],
            body: Data("{}".utf8)
        )
        XCTAssertEqual(HealthMdControlServer.validationDecision(for: resumeRequest), .valid)
        XCTAssertEqual(HealthMdControlServer.exportJobRoute(resumeRequest.path)?.action, "resume")
    }
    #endif

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

    #if os(macOS)
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
    #endif
}
