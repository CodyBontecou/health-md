import HealthMdConnectionCore
import XCTest
@testable import HealthMd

final class IPhoneDirectFileJournalTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings owns nested observation state that
    // is unsafe during test teardown on some macOS runtimes. See docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testVersionOneJournalDecodesAsLegacy() throws {
        let journal = try makeJournal()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as? [String: Any]
        )
        object["version"] = IPhoneDirectFileJournal.legacyVersion
        object.removeValue(forKey: "appleExportEnginePin")
        object.removeValue(forKey: "appleDirectProtocolPin")
        var settings = try XCTUnwrap(object["settingsSnapshot"] as? [String: Any])
        settings.removeValue(forKey: "appleExportEnginePin")
        settings.removeValue(forKey: "calendarTimeZoneIdentifier")
        object["settingsSnapshot"] = settings

        let decoded = try JSONDecoder().decode(
            IPhoneDirectFileJournal.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.version, 1)
        XCTAssertTrue(IPhoneDirectFileJournal.isSupportedVersion(decoded.version))
        XCTAssertNil(decoded.appleExportEnginePin)
        XCTAssertNil(decoded.appleDirectProtocolPin)
        XCTAssertNil(decoded.settingsSnapshot.appleExportEnginePin)
        XCTAssertNil(decoded.settingsSnapshot.calendarTimeZoneIdentifier)
    }

    func testCapturedDayRoundTripsHistoryFactsAndDecodesLegacyDefaults() throws {
        let day = IPhoneDirectCapturedDay(
            sourceDate: Date(timeIntervalSince1970: 1_800_000_000),
            sourceDateIdentifier: "2027-01-15",
            isRequestedDate: true,
            relativePath: "captured-00000000.json",
            succeeded: true,
            includedGranularData: true,
            sampleCount: 12,
            recordCount: 14,
            externalRecordCount: 2,
            partialFailureCount: 1,
            integrityWarningCount: 3,
            hadWarnings: true,
            failureReason: .deviceLocked,
            historyFactsRecorded: true
        )
        let data = try JSONEncoder().encode(day)
        XCTAssertEqual(try JSONDecoder().decode(IPhoneDirectCapturedDay.self, from: data), day)

        var legacyObject = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        for key in [
            "includedGranularData", "sampleCount", "recordCount", "externalRecordCount",
            "partialFailureCount", "integrityWarningCount", "hadWarnings", "failureReason",
            "historyFactsRecorded"
        ] {
            legacyObject.removeValue(forKey: key)
        }
        let legacy = try JSONDecoder().decode(
            IPhoneDirectCapturedDay.self,
            from: JSONSerialization.data(withJSONObject: legacyObject)
        )
        XCTAssertNil(legacy.includedGranularData)
        XCTAssertEqual(legacy.sampleCount, 0)
        XCTAssertEqual(legacy.recordCount, 0)
        XCTAssertEqual(legacy.externalRecordCount, 0)
        XCTAssertEqual(legacy.partialFailureCount, 0)
        XCTAssertEqual(legacy.integrityWarningCount, 0)
        XCTAssertFalse(legacy.hadWarnings)
        XCTAssertNil(legacy.failureReason)
        XCTAssertFalse(legacy.historyFactsRecorded)
    }

    func testVersionThreeJournalRoundTripsPinnedGeneratedFileAndProtocolAuthority() throws {
        let journal = try makeJournal()

        let decoded = try JSONDecoder().decode(
            IPhoneDirectFileJournal.self,
            from: JSONEncoder().encode(journal)
        )

        XCTAssertEqual(decoded.version, IPhoneDirectFileJournal.currentVersion)
        XCTAssertEqual(decoded.appleExportEnginePin, journal.appleExportEnginePin)
        XCTAssertEqual(decoded.appleExportEnginePin?.engine, .rust)
        XCTAssertEqual(decoded.appleDirectProtocolPin, journal.appleDirectProtocolPin)
        XCTAssertEqual(decoded.appleDirectProtocolPin?.engine, .rust)
        XCTAssertEqual(decoded.settingsSnapshot.appleExportEnginePin, journal.appleExportEnginePin)
        XCTAssertEqual(decoded.settingsSnapshot.calendarTimeZoneIdentifier, "America/Los_Angeles")
        XCTAssertTrue(decoded.settingsSnapshot.generateWeeklyRollups)
        XCTAssertEqual(decoded.request, journal.request)
        XCTAssertEqual(decoded.accepted, journal.accepted)
        XCTAssertEqual(decoded.session, journal.session)
    }

    func testPresentVersionThreeEnginePinsRejectUnknownOrExplicitLegacyAuthority() throws {
        let journal = try makeJournal()
        let encoded = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as? [String: Any]
        )

        for (containerKey, invalidEngine) in [
            ("appleExportEnginePin", "future-engine"),
            ("settingsSnapshot", "legacy"),
        ] {
            var object = encoded
            if containerKey == "appleExportEnginePin" {
                var pin = try XCTUnwrap(object[containerKey] as? [String: Any])
                pin["engine"] = invalidEngine
                object[containerKey] = pin
            } else {
                var settings = try XCTUnwrap(object[containerKey] as? [String: Any])
                var pin = try XCTUnwrap(settings["appleExportEnginePin"] as? [String: Any])
                pin["engine"] = invalidEngine
                settings["appleExportEnginePin"] = pin
                object[containerKey] = settings
            }
            XCTAssertThrowsError(
                try JSONDecoder().decode(
                    IPhoneDirectFileJournal.self,
                    from: JSONSerialization.data(withJSONObject: object)
                )
            )
        }
    }

    func testVersionTwoIgnoresUnexpectedProtocolPin() throws {
        let journal = try makeJournal()
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(journal)) as? [String: Any]
        )
        object["version"] = IPhoneDirectFileJournal.exportEnginePinVersion

        let decoded = try JSONDecoder().decode(
            IPhoneDirectFileJournal.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.version, 2)
        XCTAssertNotNil(decoded.appleExportEnginePin)
        XCTAssertNil(decoded.appleDirectProtocolPin)
    }

    #if os(iOS)
    @MainActor
    func testNewDirectGeneratedFileJobFreezesLegacyBeforePinWhenProviderSidecarsArePossible() {
        let defaults = UserDefaults(suiteName: "IPhoneDirectFileJournalTests.Surface.\(UUID().uuidString)")!
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let request = DirectExportRequest(
            jobID: UUID(),
            createdAt: Date(),
            dateSelection: .exact(start: "2026-07-25", end: "2026-07-25"),
            responseMode: .writeFiles,
            destination: DirectExportDestination(rootPath: "/synthetic")
        )

        XCTAssertEqual(
            IPhoneDirectFileExportProducer.operationSurfaceForNewGeneratedFileJob(
                request: request,
                settings: settings,
                connectedProviderCount: 1
            ),
            .legacyOnly
        )
        XCTAssertEqual(
            IPhoneDirectFileExportProducer.operationSurfaceForNewGeneratedFileJob(
                request: request,
                settings: settings,
                connectedProviderCount: 0
            ),
            .directGeneratedFilesWithoutSideEffects
        )
    }

    func testGeneratedFileProgressKeepsDurablePreparedFrontier() {
        func capturedDay(identifier: String, requested: Bool) -> IPhoneDirectCapturedDay {
            IPhoneDirectCapturedDay(
                sourceDate: Date(timeIntervalSince1970: 1_800_000_000),
                sourceDateIdentifier: identifier,
                isRequestedDate: requested,
                relativePath: "\(identifier).json",
                succeeded: true,
                includedGranularData: false,
                sampleCount: 0,
                recordCount: 0,
                externalRecordCount: 0,
                partialFailureCount: 0,
                integrityWarningCount: 0,
                hadWarnings: false,
                failureReason: nil,
                historyFactsRecorded: true
            )
        }

        let rollupSource = capturedDay(identifier: "2027-01-14", requested: false)
        let firstRequested = capturedDay(identifier: "2027-01-15", requested: true)
        let secondRequested = capturedDay(identifier: "2027-01-16", requested: true)

        XCTAssertEqual(
            IPhoneDirectFileExportProducer.preparedRequestedDayCount(
                in: [rollupSource, firstRequested, secondRequested]
            ),
            2
        )
    }

    @MainActor
    func testPinnedDirectRangeInputSeparatesRequestedDailyOutputFromRollupSources() throws {
        let defaults = UserDefaults(suiteName: "IPhoneDirectFileJournalTests.Range.\(UUID().uuidString)")!
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.exportFormats = [.json]
        settings.generateWeeklyRollups = true
        settings.exportTimeZoneOverride = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            calendarTimeZoneIdentifier: "UTC"
        )
        let first = ExportFixtures.partialDay
        let secondDate = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: first.date)
        )
        var second = HealthData(date: secondDate, timeContext: ExportFixtures.timeContext)
        second.sleep = first.sleep
        second.activity = first.activity
        let days = [
            IPhoneDirectCapturedDay(
                sourceDate: first.date,
                sourceDateIdentifier: "2026-03-15",
                isRequestedDate: true,
                relativePath: "captured-00000000.json",
                succeeded: true
            ),
            IPhoneDirectCapturedDay(
                sourceDate: second.date,
                sourceDateIdentifier: "2026-03-16",
                isRequestedDate: false,
                relativePath: "captured-00000001.json",
                succeeded: true
            ),
        ]
        let payloads = [
            ConnectedCorpusHealthDayPayload(
                sourceDate: first.date,
                isRequestedDate: true,
                record: first,
                externalDailyRecords: [],
                failure: nil
            ),
            ConnectedCorpusHealthDayPayload(
                sourceDate: second.date,
                isRequestedDate: false,
                record: second,
                externalDailyRecords: [],
                failure: nil
            ),
        ]

        let input = try IPhoneDirectFileExportProducer.rangePlanningInput(
            capturedDays: days,
            payloads: payloads,
            settings: settings,
            settingsSnapshot: snapshot
        )
        XCTAssertEqual(input.records.map(\.date), [first.date, second.date])
        XCTAssertEqual(input.dailyOutputOwnerDates, ["2026-03-15"])

        settings.summaryOnlyExport = true
        let summarySnapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            calendarTimeZoneIdentifier: "UTC"
        )
        let summaryInput = try IPhoneDirectFileExportProducer.rangePlanningInput(
            capturedDays: days,
            payloads: payloads,
            settings: settings,
            settingsSnapshot: summarySnapshot
        )
        XCTAssertTrue(summaryInput.dailyOutputOwnerDates.isEmpty)
    }

    @MainActor
    func testPinnedDirectRollupRangeFailsClosedWhenSourceCaptureIsUnavailable() throws {
        let defaults = UserDefaults(suiteName: "IPhoneDirectFileJournalTests.RangeFailure.\(UUID().uuidString)")!
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.exportFormats = [.json]
        settings.generateWeeklyRollups = true
        settings.exportTimeZoneOverride = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            calendarTimeZoneIdentifier: "UTC"
        )
        let date = ExportFixtures.partialDay.date
        let day = IPhoneDirectCapturedDay(
            sourceDate: date,
            sourceDateIdentifier: "2026-03-15",
            isRequestedDate: true,
            relativePath: "captured-00000000.json",
            succeeded: false
        )
        let payload = ConnectedCorpusHealthDayPayload(
            sourceDate: date,
            isRequestedDate: true,
            record: nil,
            externalDailyRecords: [],
            failure: FailedDateDetail(date: date, reason: .noHealthData)
        )

        XCTAssertThrowsError(try IPhoneDirectFileExportProducer.rangePlanningInput(
            capturedDays: [day],
            payloads: [payload],
            settings: settings,
            settingsSnapshot: snapshot
        )) { error in
            XCTAssertEqual(error as? AppleLooseDailyExportPlannerError, .rustPlanningFailed)
        }
    }

    @MainActor
    func testCanonicalDirectSelectionCannotProduceProviderSidecars() {
        let defaults = UserDefaults(suiteName: "IPhoneDirectFileJournalTests.Selection.\(UUID().uuidString)")!
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        let request = DirectExportRequest(
            jobID: UUID(),
            createdAt: Date(),
            dateSelection: .exact(start: "2026-07-25", end: "2026-07-25"),
            responseMode: .writeFiles,
            canonicalSelection: DirectCanonicalSelection(metricIDs: ["sleep_total"]),
            destination: DirectExportDestination(rootPath: "/synthetic")
        )

        XCTAssertEqual(
            IPhoneDirectFileExportProducer.operationSurfaceForNewGeneratedFileJob(
                request: request,
                settings: settings,
                connectedProviderCount: 1
            ),
            .directGeneratedFilesWithoutSideEffects
        )
    }
    #endif

    #if os(iOS)
    func testDirectCLIPairingLinkAcceptsOnlyExactBoundedIPv4Payload() throws {
        let valid = try XCTUnwrap(IPhoneDirectCLIPairingLink(
            url: try XCTUnwrap(URL(
                string: "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=123456"
            ))
        ))
        XCTAssertEqual(valid.host, "192.168.1.42")
        XCTAssertEqual(valid.port, 17_647)
        XCTAssertEqual(valid.pairingCode, "123456")

        for invalid in [
            "https://direct-cli/pair?host=192.168.1.42&port=17647&code=123456",
            "healthmd://direct-cli/pair?host=example.com&port=17647&code=123456",
            "healthmd://direct-cli/pair?host=192.168.1.42&port=0&code=123456",
            "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=12345a",
            "healthmd://direct-cli/pair?host=192.168.1.42&port=17647&code=123456&extra=1",
            "healthmd://other/pair?host=192.168.1.42&port=17647&code=123456"
        ] {
            XCTAssertNil(IPhoneDirectCLIPairingLink(url: try XCTUnwrap(URL(string: invalid))))
        }
    }
    #endif

    private func makeJournal() throws -> IPhoneDirectFileJournal {
        let jobID = UUID(uuidString: "11111111-2222-3333-4444-555555555555")!
        let peerBinding = DirectPeerBinding(
            sourceInstallationID: UUID(uuidString: "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa")!,
            destinationInstallationID: UUID(uuidString: "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb")!
        )
        let createdAt = Date(timeIntervalSince1970: 1_800_000_000)
        let request = DirectExportRequest(
            jobID: jobID,
            createdAt: createdAt,
            dateSelection: .exact(start: "2027-01-15", end: "2027-01-15"),
            responseMode: .writeFiles,
            destination: DirectExportDestination(rootPath: "/synthetic")
        )
        let accepted = DirectExportAccepted(
            jobID: jobID,
            acceptedAt: createdAt,
            peerBinding: peerBinding,
            resolvedDateIdentifiers: ["2027-01-15"],
            sourceDeviceName: "Synthetic iPhone",
            sourceTimeZoneIdentifier: "America/Los_Angeles"
        )
        let session = try DirectTransferSession(
            sessionID: UUID(uuidString: "cccccccc-cccc-cccc-cccc-cccccccccccc")!,
            jobID: jobID,
            requestFingerprint: try DirectRequestFingerprint.make(for: request),
            peerBinding: peerBinding,
            partitionTargetBytes: DirectTransferLimits.preferredPartitionBytes,
            createdAt: createdAt
        )
        let defaults = UserDefaults(suiteName: "IPhoneDirectFileJournalTests.\(UUID().uuidString)")!
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.generateWeeklyRollups = true
        let pin = try makeSyntheticAppleExportEnginePin()
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            appleExportEnginePin: pin,
            calendarTimeZoneIdentifier: "America/Los_Angeles"
        )

        let protocolPin = try AppleDirectProtocolPin(
            engine: .rust,
            coreAPIVersion: 4,
            protocolAPIRevision: 1,
            appleApplicationProtocolVersion: 1,
            transferProtocolVersion: 1,
            coreCrateVersion: "0.1.0-test",
            coreSourceRevision: "test-revision"
        )

        return IPhoneDirectFileJournal(
            request: request,
            accepted: accepted,
            session: session,
            settingsSnapshot: snapshot,
            appleExportEnginePin: pin,
            appleDirectProtocolPin: protocolPin,
            healthSubfolder: "Health",
            requestedDates: [createdAt],
            transferDates: [createdAt],
            capturedDays: [],
            generatedFiles: [],
            partitions: [],
            committedPartitionCount: 0,
            committedBytes: 0,
            state: "preparing",
            completionRecorded: false,
            updatedAt: createdAt
        )
    }
}
