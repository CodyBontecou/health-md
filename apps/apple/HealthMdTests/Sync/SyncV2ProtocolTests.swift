import Combine
import XCTest
@testable import HealthMd

final class SyncV2ProtocolTests: XCTestCase {

    @MainActor
    func testRepeatedSendFailureDoesNotRepublishIdenticalTransportError() {
        let service = SyncService()
        var publications = 0
        let observation = service.objectWillChange.sink { publications += 1 }

        service.send(.ping)
        let publicationsAfterFirstFailure = publications
        XCTAssertGreaterThan(publicationsAfterFirstFailure, 0)
        XCTAssertEqual(service.lastError, "No connected device")

        service.send(.ping)
        XCTAssertEqual(publications, publicationsAfterFirstFailure)
        withExtendedLifetime(observation) {}
    }

    func testPeerCapabilities_codableAndCompatibility() throws {
        let capabilities = SyncPeerCapabilities(
            protocolVersion: SyncPeerCapabilities.currentProtocolVersion,
            appVersion: "2.0",
            buildNumber: "200",
            platform: .macOS,
            supportsMacExportJobs: true,
            supportsMacDestinationStatus: true,
            supportsJobCancellation: true,
            supportsGranularPayloads: true,
            supportsRollupSummaries: true
        )

        let data = try JSONEncoder().encode(capabilities)
        let decoded = try JSONDecoder().decode(SyncPeerCapabilities.self, from: data)

        XCTAssertEqual(decoded, capabilities)
        XCTAssertTrue(decoded.isCompatibleWithMacExportJobs)

        let oldMac = SyncPeerCapabilities(
            protocolVersion: 1,
            appVersion: "1.0",
            buildNumber: "100",
            platform: .macOS,
            supportsMacExportJobs: false,
            supportsMacDestinationStatus: false,
            supportsJobCancellation: false,
            supportsGranularPayloads: false
        )
        XCTAssertFalse(oldMac.isCompatibleWithMacExportJobs)
    }

    func testPeerCapabilities_legacyPayloadDefaultsRollupSupportToFalse() throws {
        let legacyJSON = """
        {
          "protocolVersion": 2,
          "appVersion": "2.0",
          "buildNumber": "200",
          "platform": "macOS",
          "supportsMacExportJobs": true,
          "supportsMacDestinationStatus": true,
          "supportsJobCancellation": true,
          "supportsGranularPayloads": true
        }
        """.data(using: .utf8)!

        let decoded = try JSONDecoder().decode(SyncPeerCapabilities.self, from: legacyJSON)

        XCTAssertFalse(decoded.isCompatibleWithMacExportJobs)
        XCTAssertFalse(decoded.supportsAuthoritativeMacExportFileAccounting)
        XCTAssertFalse(decoded.supportsRollupSummaries)
        XCTAssertFalse(decoded.supportsRangeV9Summaries)
        XCTAssertFalse(decoded.supportsSummaryOnlyExports)
        XCTAssertFalse(decoded.supportsAllAvailableHistoryExportRequests)
        XCTAssertFalse(decoded.supportsChunkedMacExportJobs)
        XCTAssertFalse(decoded.supportsSizeBoundedConnectedTransfers)
        XCTAssertFalse(decoded.supportsStrictRawStreaming)
        XCTAssertFalse(decoded.supportsPerDateExportCompletion)
        XCTAssertFalse(decoded.supportsDailyNoteOnlyExports)
        XCTAssertFalse(decoded.supportsDataDictionaryExportPreference)
        XCTAssertNil(decoded.installationID)
        XCTAssertFalse(decoded.supportsDurableConnectedExportRecovery)
        XCTAssertTrue(decoded.connectedTransferBinaryFrameVersions.isEmpty)
        XCTAssertEqual(decoded.connectedTransferMaximumInFlightChunks, 1)
        XCTAssertFalse(decoded.supportsScheduledConnectedMacExports)
        XCTAssertFalse(decoded.supportsManualIPSync)
        XCTAssertTrue(decoded.manualIPSyncRequiresPairing)
        XCTAssertFalse(decoded.supportsRequestedMacExportFeatures(rollupSummariesEnabled: false))
        XCTAssertFalse(decoded.supportsRequestedMacExportFeatures(rollupSummariesEnabled: true))
        XCTAssertFalse(decoded.supportsRequestedMacExportFeatures(
            rollupSummariesEnabled: true,
            summaryOnlyExportEnabled: true
        ))
        XCTAssertFalse(decoded.supportsRequestedMacExportFeatures(
            rollupSummariesEnabled: false,
            dailyNotesOnlyExportEnabled: true
        ))
        XCTAssertFalse(decoded.supportsRequestedMacExportFeatures(
            rollupSummariesEnabled: false,
            dataDictionarySuppressionRequested: true
        ))
    }

    func testPeerCapabilities_mixedPeerWithHistoricalRollupsRejectsRangeV9() {
        let mixed = SyncPeerCapabilities(
            protocolVersion: SyncPeerCapabilities.currentProtocolVersion,
            appVersion: "mixed",
            buildNumber: "1",
            platform: .macOS,
            supportsMacExportJobs: true,
            supportsMacDestinationStatus: true,
            supportsJobCancellation: true,
            supportsGranularPayloads: true,
            supportsRollupSummaries: true,
            supportsRangeV9Summaries: false
        )

        XCTAssertTrue(mixed.supportsRequestedMacExportFeatures(
            rollupSummariesEnabled: true
        ))
        XCTAssertFalse(mixed.supportsRequestedMacExportFeatures(
            rollupSummariesEnabled: false,
            rangeV9SummaryEnabled: true
        ))
    }

    func testPeerCapabilities_losslessFileJobsRequireBoundedCurrentArchiveSupport() {
        func peer(bounded: Bool, archiveVersions: [Int]) -> SyncPeerCapabilities {
            SyncPeerCapabilities(
                protocolVersion: SyncPeerCapabilities.currentProtocolVersion,
                appVersion: "mixed",
                buildNumber: "1",
                platform: .macOS,
                supportsMacExportJobs: true,
                supportsMacDestinationStatus: true,
                supportsJobCancellation: true,
                supportsGranularPayloads: true,
                supportsRollupSummaries: true,
                supportsSummaryOnlyExports: true,
                supportsSizeBoundedConnectedTransfers: bounded,
                canonicalArchiveSchemaVersions: archiveVersions
            )
        }

        let missingArchive = peer(bounded: true, archiveVersions: [])
        let unbounded = peer(
            bounded: false,
            archiveVersions: [HealthKitRecordArchive.currentRecordSchemaVersion]
        )
        let wrongArchive = peer(
            bounded: true,
            archiveVersions: [HealthKitRecordArchive.currentRecordSchemaVersion + 1]
        )
        let current = peer(
            bounded: true,
            archiveVersions: [HealthKitRecordArchive.currentRecordSchemaVersion]
        )

        for incompatible in [missingArchive, unbounded, wrongArchive] {
            XCTAssertFalse(incompatible.supportsRequestedMacExportFeatures(
                rollupSummariesEnabled: false,
                effectiveGranularDataEnabled: true
            ))
        }
        XCTAssertTrue(current.supportsRequestedMacExportFeatures(
            rollupSummariesEnabled: false,
            effectiveGranularDataEnabled: true
        ))
        XCTAssertTrue(missingArchive.supportsRequestedMacExportFeatures(
            rollupSummariesEnabled: true,
            summaryOnlyExportEnabled: true,
            effectiveGranularDataEnabled: false
        ), "A true summary-only job remains compatible without archive negotiation")
        XCTAssertTrue(unbounded.supportsRequestedMacExportFeatures(
            rollupSummariesEnabled: false,
            effectiveGranularDataEnabled: false
        ), "A non-granular legacy file job remains compatible")
    }

    func testPeerCapabilities_currentAdvertisesChunkedMacExportJobs() {
        let iosInstallationID = UUID()
        let macInstallationID = UUID()
        let currentIOS = SyncPeerCapabilities.current(
            platform: .iOS,
            installationID: iosInstallationID
        )
        let currentMac = SyncPeerCapabilities.current(
            platform: .macOS,
            installationID: macInstallationID
        )
        XCTAssertTrue(currentIOS.supportsChunkedMacExportJobs)
        XCTAssertTrue(currentMac.supportsChunkedMacExportJobs)
        XCTAssertTrue(currentIOS.supportsAllAvailableHistoryExportRequests)
        XCTAssertTrue(currentMac.supportsAllAvailableHistoryExportRequests)
        XCTAssertTrue(currentIOS.supportsSizeBoundedConnectedTransfers)
        XCTAssertTrue(currentMac.supportsStrictRawStreaming)
        XCTAssertTrue(currentMac.supportsPerDateExportCompletion)
        XCTAssertTrue(currentMac.supportsDailyNoteOnlyExports)
        XCTAssertTrue(currentMac.supportsDataDictionaryExportPreference)
        XCTAssertTrue(currentMac.supportsRangeV9Summaries)
        XCTAssertEqual(currentIOS.installationID, iosInstallationID)
        XCTAssertEqual(currentMac.installationID, macInstallationID)
        XCTAssertTrue(currentIOS.supportsDurableConnectedExportRecovery)
        XCTAssertTrue(currentMac.supportsDurableConnectedExportRecovery)
        XCTAssertEqual(
            currentMac.connectedTransferBinaryFrameVersions,
            [ConnectedTransferBinaryFrame.currentVersion]
        )
        XCTAssertEqual(currentMac.connectedTransferMaximumInFlightChunks, 4)
        XCTAssertEqual(currentMac.connectedCorpusTransferCapabilities?.protocolVersions, [1, 2, 3, 4])
        XCTAssertTrue(currentMac.supportsRequestedMacExportFeatures(
            rollupSummariesEnabled: false,
            dailyNotesOnlyExportEnabled: true,
            dataDictionarySuppressionRequested: true
        ))
        XCTAssertTrue(currentMac.supportsScheduledConnectedMacExports)
        XCTAssertEqual(
            currentMac.canonicalArchiveSchemaVersions,
            [HealthKitRecordArchive.currentRecordSchemaVersion]
        )
    }

    func testSyncServiceInstallationID_isStableAndRepairsInvalidPersistedValues() {
        let suiteName = "SyncServiceInstallationIDTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SyncService.persistedInstallationID(in: defaults)
        let second = SyncService.persistedInstallationID(in: defaults)
        XCTAssertEqual(second, first)
        XCTAssertEqual(
            defaults.string(forKey: SyncService.installationIDDefaultsKey),
            first.uuidString
        )

        defaults.set("not-a-uuid", forKey: SyncService.installationIDDefaultsKey)
        let repaired = SyncService.persistedInstallationID(in: defaults)
        XCTAssertNotEqual(repaired, first)
        XCTAssertEqual(
            defaults.string(forKey: SyncService.installationIDDefaultsKey),
            repaired.uuidString
        )
    }

    func testMacDestinationStatus_readinessMapping() {
        let ready = MacDestinationStatus(
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
        XCTAssertTrue(ready.canReceiveExports)
        XCTAssertNil(ready.notReadyReason)

        let noFolder = MacDestinationStatus(
            isConnected: true,
            isReadyForExports: false,
            destinationFolderSelected: false,
            folderAccessHealthy: false,
            destinationDisplayName: nil,
            destinationPathForDisplay: nil,
            lastError: nil,
            activeJobID: nil,
            capabilities: .current(platform: .macOS)
        )
        XCTAssertFalse(noFolder.canReceiveExports)
        XCTAssertEqual(noFolder.notReadyReason, "Choose a folder on Mac")

        let busy = MacDestinationStatus(
            isConnected: true,
            isReadyForExports: false,
            destinationFolderSelected: true,
            folderAccessHealthy: true,
            destinationDisplayName: "Exports",
            destinationPathForDisplay: nil,
            lastError: nil,
            activeJobID: UUID(),
            capabilities: .current(platform: .macOS)
        )
        XCTAssertFalse(busy.canReceiveExports)
        XCTAssertEqual(busy.notReadyReason, "Mac is exporting…")
    }

    @MainActor
    func testSyncServiceMacReadiness_requiresConnectionCapabilitiesAndReadyStatus() {
        let service = SyncService()

        XCTAssertFalse(service.canExportToConnectedMac)
        XCTAssertEqual(service.macExportReadinessMessage, "Open Health.md on your Mac to connect")

        service.connectionState = .connected
        service.remoteCapabilities = SyncPeerCapabilities(
            protocolVersion: 1,
            appVersion: "1.0",
            buildNumber: "100",
            platform: .macOS,
            supportsMacExportJobs: false,
            supportsMacDestinationStatus: false,
            supportsJobCancellation: false,
            supportsGranularPayloads: false
        )
        XCTAssertFalse(service.canExportToConnectedMac)
        XCTAssertEqual(service.macExportReadinessMessage, "Update Health.md on Mac")

        service.remoteCapabilities = .current(platform: .macOS)
        service.macDestinationStatus = MacDestinationStatus(
            isConnected: true,
            isReadyForExports: false,
            destinationFolderSelected: false,
            folderAccessHealthy: false,
            destinationDisplayName: nil,
            destinationPathForDisplay: nil,
            lastError: nil,
            activeJobID: nil,
            capabilities: .current(platform: .macOS)
        )
        XCTAssertFalse(service.canExportToConnectedMac)
        XCTAssertEqual(service.macExportReadinessMessage, "Choose a folder on Mac")

        service.macDestinationStatus = MacDestinationStatus(
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
        XCTAssertTrue(service.canExportToConnectedMac)
        XCTAssertEqual(service.macExportReadinessMessage, "Ready to export to Mac")
    }

    @MainActor
    func testSyncServiceMacReadiness_requiresRollupCapableMacWhenRollupsEnabled() {
        let service = SyncService()
        service.connectionState = .connected
        service.remoteCapabilities = SyncPeerCapabilities(
            protocolVersion: SyncPeerCapabilities.currentProtocolVersion,
            appVersion: "2.0",
            buildNumber: "200",
            platform: .macOS,
            supportsMacExportJobs: true,
            supportsMacDestinationStatus: true,
            supportsJobCancellation: true,
            supportsGranularPayloads: true,
            supportsRollupSummaries: false
        )
        service.macDestinationStatus = MacDestinationStatus(
            isConnected: true,
            isReadyForExports: true,
            destinationFolderSelected: true,
            folderAccessHealthy: true,
            destinationDisplayName: "Exports",
            destinationPathForDisplay: nil,
            lastError: nil,
            activeJobID: nil,
            capabilities: service.remoteCapabilities
        )

        let settings = makeSettings()
        settings.generateWeeklyRollups = true

        XCTAssertTrue(service.canExportToConnectedMac)
        XCTAssertFalse(service.canExportToConnectedMac(requiring: settings))
        XCTAssertEqual(
            service.macExportReadinessMessage(requiring: settings),
            "Update Health.md on Mac to export range summaries"
        )

        service.remoteCapabilities = .current(platform: .macOS)
        service.macDestinationStatus = MacDestinationStatus(
            isConnected: true,
            isReadyForExports: true,
            destinationFolderSelected: true,
            folderAccessHealthy: true,
            destinationDisplayName: "Exports",
            destinationPathForDisplay: nil,
            lastError: nil,
            activeJobID: nil,
            capabilities: service.remoteCapabilities
        )

        XCTAssertTrue(service.canExportToConnectedMac(requiring: settings))
        XCTAssertEqual(service.macExportReadinessMessage(requiring: settings), "Ready to export to Mac")
    }

    @MainActor
    func testSyncServiceMacReadiness_requiresSummaryOnlyCapableMacWhenSummaryOnlyEnabled() {
        let service = SyncService()
        service.connectionState = .connected
        service.remoteCapabilities = SyncPeerCapabilities(
            protocolVersion: SyncPeerCapabilities.currentProtocolVersion,
            appVersion: "2.0",
            buildNumber: "200",
            platform: .macOS,
            supportsMacExportJobs: true,
            supportsMacDestinationStatus: true,
            supportsJobCancellation: true,
            supportsGranularPayloads: true,
            supportsRollupSummaries: true,
            supportsSummaryOnlyExports: false
        )
        service.macDestinationStatus = MacDestinationStatus(
            isConnected: true,
            isReadyForExports: true,
            destinationFolderSelected: true,
            folderAccessHealthy: true,
            destinationDisplayName: "Exports",
            destinationPathForDisplay: nil,
            lastError: nil,
            activeJobID: nil,
            capabilities: service.remoteCapabilities
        )

        let settings = makeSettings()
        settings.generateMonthlyRollups = true
        settings.summaryOnlyExport = true

        XCTAssertFalse(service.canExportToConnectedMac(requiring: settings))
        XCTAssertEqual(
            service.macExportReadinessMessage(requiring: settings),
            "Update Health.md on Mac to export summary-only roll-ups"
        )

        service.remoteCapabilities = .current(platform: .macOS)
        service.macDestinationStatus = MacDestinationStatus(
            isConnected: true,
            isReadyForExports: true,
            destinationFolderSelected: true,
            folderAccessHealthy: true,
            destinationDisplayName: "Exports",
            destinationPathForDisplay: nil,
            lastError: nil,
            activeJobID: nil,
            capabilities: service.remoteCapabilities
        )

        XCTAssertTrue(service.canExportToConnectedMac(requiring: settings))
    }

    @MainActor
    func testSyncServiceMacReadiness_requiresDailyNoteOnlyCapableMac() {
        let service = SyncService()
        service.connectionState = .connected
        service.remoteCapabilities = SyncPeerCapabilities(
            protocolVersion: SyncPeerCapabilities.currentProtocolVersion,
            appVersion: "2.0",
            buildNumber: "200",
            platform: .macOS,
            supportsMacExportJobs: true,
            supportsMacDestinationStatus: true,
            supportsJobCancellation: true,
            supportsGranularPayloads: true,
            supportsDailyNoteOnlyExports: false
        )
        service.macDestinationStatus = MacDestinationStatus(
            isConnected: true,
            isReadyForExports: true,
            destinationFolderSelected: true,
            folderAccessHealthy: true,
            destinationDisplayName: "Exports",
            destinationPathForDisplay: nil,
            lastError: nil,
            activeJobID: nil,
            capabilities: service.remoteCapabilities
        )

        let settings = makeSettings()
        settings.exportFormats = []
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.dailyNotesOnly = true

        XCTAssertFalse(service.canExportToConnectedMac(requiring: settings))
        XCTAssertEqual(
            service.macExportReadinessMessage(requiring: settings),
            "Update Health.md on Mac to use Daily Notes Only"
        )

        service.remoteCapabilities = .current(platform: .macOS)
        service.macDestinationStatus = MacDestinationStatus(
            isConnected: true,
            isReadyForExports: true,
            destinationFolderSelected: true,
            folderAccessHealthy: true,
            destinationDisplayName: "Exports",
            destinationPathForDisplay: nil,
            lastError: nil,
            activeJobID: nil,
            capabilities: service.remoteCapabilities
        )

        XCTAssertTrue(service.canExportToConnectedMac(requiring: settings))
    }

    @MainActor
    func testSyncServiceMacReadiness_requiresDictionaryPreferenceCapableMacWhenSuppressed() {
        let service = SyncService()
        service.connectionState = .connected
        service.remoteCapabilities = SyncPeerCapabilities(
            protocolVersion: SyncPeerCapabilities.currentProtocolVersion,
            appVersion: "legacy",
            buildNumber: "1",
            platform: .macOS,
            supportsMacExportJobs: true,
            supportsMacDestinationStatus: true,
            supportsJobCancellation: true,
            supportsGranularPayloads: true,
            supportsDataDictionaryExportPreference: false
        )
        service.macDestinationStatus = MacDestinationStatus(
            isConnected: true,
            isReadyForExports: true,
            destinationFolderSelected: true,
            folderAccessHealthy: true,
            destinationDisplayName: "Exports",
            destinationPathForDisplay: nil,
            lastError: nil,
            activeJobID: nil,
            capabilities: service.remoteCapabilities
        )
        let settings = makeSettings()
        settings.includeGranularData = false
        settings.includeDataDictionary = false

        XCTAssertFalse(service.canExportToConnectedMac(requiring: settings))
        XCTAssertEqual(
            service.macExportReadinessMessage(requiring: settings),
            "Update Health.md on Mac to omit the data dictionary"
        )

        service.remoteCapabilities = .current(platform: .macOS)
        service.macDestinationStatus = MacDestinationStatus(
            isConnected: true,
            isReadyForExports: true,
            destinationFolderSelected: true,
            folderAccessHealthy: true,
            destinationDisplayName: "Exports",
            destinationPathForDisplay: nil,
            lastError: nil,
            activeJobID: nil,
            capabilities: service.remoteCapabilities
        )

        XCTAssertTrue(service.canExportToConnectedMac(requiring: settings))
    }

    func testLegacyMacJobAndStreamDecodeWithoutOriginalRangeAuthority() throws {
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = makeSnapshot()
        let job = MacExportJob(
            jobID: UUID(),
            createdAt: date,
            sourceDeviceName: "Legacy iPhone",
            dateRangeStart: date,
            dateRangeEnd: date,
            requestedDates: [date],
            originalRequestedDates: [date],
            originalCalendarTimeZoneIdentifier: snapshot.calendarTimeZoneIdentifier,
            records: [makeMedicationHealthData(date: date)],
            settingsSnapshot: snapshot,
            requestedTarget: nil
        )
        var jobObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(job)) as? [String: Any]
        )
        jobObject.removeValue(forKey: "originalRequestedDates")
        jobObject.removeValue(forKey: "originalCalendarTimeZoneIdentifier")
        let legacyJob = try JSONDecoder().decode(
            MacExportJob.self,
            from: JSONSerialization.data(withJSONObject: jobObject)
        )
        XCTAssertNil(legacyJob.originalRequestedDates)
        XCTAssertNil(legacyJob.originalCalendarTimeZoneIdentifier)

        let stream = MacExportStreamStart(
            jobID: UUID(),
            createdAt: date,
            sourceDeviceName: "Legacy iPhone",
            dateRangeStart: date,
            dateRangeEnd: date,
            requestedDates: [date],
            originalRequestedDates: [date],
            originalCalendarTimeZoneIdentifier: snapshot.calendarTimeZoneIdentifier,
            totalRequestedDays: 1,
            totalTransferDays: 1,
            settingsSnapshot: snapshot,
            requestedTarget: nil,
            chunkStrategyVersion: 1
        )
        var streamObject = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(stream)) as? [String: Any]
        )
        streamObject.removeValue(forKey: "originalRequestedDates")
        streamObject.removeValue(forKey: "originalCalendarTimeZoneIdentifier")
        let legacyStream = try JSONDecoder().decode(
            MacExportStreamStart.self,
            from: JSONSerialization.data(withJSONObject: streamObject)
        )
        XCTAssertNil(legacyStream.originalRequestedDates)
        XCTAssertNil(legacyStream.originalCalendarTimeZoneIdentifier)
    }

    func testSyncMessageV2Cases_codable() throws {
        let jobID = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = makeSnapshot()
        let healthData = makeMedicationHealthData(date: date)
        let externalRecord = ExternalDailyRecord(
            provider: .strava,
            date: "2027-01-15",
            payloads: [ExternalProviderPayload(
                name: "activities",
                endpoint: "https://www.strava.com/api/v3/athlete/activities",
                statusCode: 200,
                data: .array([])
            )],
            warnings: ["scope limited"]
        )
        let job = MacExportJob(
            jobID: jobID,
            createdAt: date,
            sourceDeviceName: "Cody's iPhone",
            dateRangeStart: date,
            dateRangeEnd: date,
            requestedDates: [date],
            originalRequestedDates: [date],
            originalCalendarTimeZoneIdentifier: snapshot.calendarTimeZoneIdentifier,
            records: [healthData],
            externalDailyRecords: [externalRecord],
            settingsSnapshot: snapshot,
            requestedTarget: ExportTargetSnapshot(
                kind: .connectedMac,
                displayName: "Connected Mac",
                destinationDisplayName: "MacBook Pro"
            )
        )

        try assertRoundTrip(.hello(.current(platform: .iOS))) { decoded in
            guard case .hello(let capabilities) = decoded else { return XCTFail("Expected hello") }
            XCTAssertEqual(capabilities.platform, .iOS)
            XCTAssertTrue(capabilities.supportsMacExportJobs)
        }

        try assertRoundTrip(.macStatus(MacDestinationStatus(
            isConnected: true,
            isReadyForExports: true,
            destinationFolderSelected: true,
            folderAccessHealthy: true,
            destinationDisplayName: "Exports",
            destinationPathForDisplay: "/Users/cody/Exports",
            lastError: nil,
            activeJobID: nil,
            capabilities: .current(platform: .macOS)
        ))) { decoded in
            guard case .macStatus(let status) = decoded else { return XCTFail("Expected macStatus") }
            XCTAssertTrue(status.canReceiveExports)
            XCTAssertEqual(status.destinationDisplayName, "Exports")
        }

        try assertRoundTrip(.macExportRequest(job)) { decoded in
            guard case .macExportRequest(let decodedJob) = decoded else { return XCTFail("Expected macExportRequest") }
            XCTAssertEqual(decodedJob.jobID, jobID)
            XCTAssertEqual(decodedJob.sourceDeviceName, "Cody's iPhone")
            XCTAssertEqual(decodedJob.records.count, 1)
            XCTAssertEqual(decodedJob.requestedDates, [date])
            XCTAssertEqual(decodedJob.originalRequestedDates, [date])
            XCTAssertEqual(decodedJob.originalCalendarTimeZoneIdentifier, snapshot.calendarTimeZoneIdentifier)
            XCTAssertEqual(decodedJob.records.first?.medications?.medications.first?.exportName, "D3")
            XCTAssertEqual(decodedJob.records.first?.medications?.doseEvents.first?.logStatus, .taken)
            XCTAssertEqual(decodedJob.externalDailyRecords.count, 1)
            XCTAssertEqual(decodedJob.externalDailyRecords.first?.provider, .strava)
            XCTAssertEqual(decodedJob.settingsSnapshot, snapshot)
            XCTAssertEqual(decodedJob.settingsSnapshot.healthSubfolder, "2. Areas/Health")
            XCTAssertEqual(decodedJob.requestedTarget?.kind, .connectedMac)
        }

        try assertRoundTrip(.macExportStreamStart(MacExportStreamStart(
            jobID: jobID,
            createdAt: date,
            sourceDeviceName: "Cody's iPhone",
            dateRangeStart: date,
            dateRangeEnd: date,
            requestedDates: [date],
            originalRequestedDates: [date],
            originalCalendarTimeZoneIdentifier: snapshot.calendarTimeZoneIdentifier,
            totalRequestedDays: 193,
            totalTransferDays: 193,
            settingsSnapshot: snapshot,
            requestedTarget: job.requestedTarget,
            chunkStrategyVersion: 1
        ))) { decoded in
            guard case .macExportStreamStart(let start) = decoded else { return XCTFail("Expected macExportStreamStart") }
            XCTAssertEqual(start.jobID, jobID)
            XCTAssertEqual(start.sourceDeviceName, "Cody's iPhone")
            XCTAssertEqual(start.requestedDates, [date])
            XCTAssertEqual(start.originalRequestedDates, [date])
            XCTAssertEqual(start.originalCalendarTimeZoneIdentifier, snapshot.calendarTimeZoneIdentifier)
            XCTAssertEqual(start.totalRequestedDays, 193)
            XCTAssertEqual(start.totalTransferDays, 193)
            XCTAssertEqual(start.settingsSnapshot, snapshot)
            XCTAssertEqual(start.requestedTarget?.destinationDisplayName, "MacBook Pro")
            XCTAssertEqual(start.chunkStrategyVersion, 1)
        }

        try assertRoundTrip(.macExportStreamChunk(MacExportStreamChunk(
            jobID: jobID,
            sequence: 2,
            records: [healthData],
            externalDailyRecords: [externalRecord],
            processedTransferDays: 20,
            totalTransferDays: 193
        ))) { decoded in
            guard case .macExportStreamChunk(let chunk) = decoded else { return XCTFail("Expected macExportStreamChunk") }
            XCTAssertEqual(chunk.jobID, jobID)
            XCTAssertEqual(chunk.sequence, 2)
            XCTAssertEqual(chunk.records.count, 1)
            XCTAssertEqual(chunk.records.first?.medications?.medications.first?.exportName, "D3")
            XCTAssertEqual(chunk.externalDailyRecords.first?.provider, .strava)
            XCTAssertEqual(chunk.processedTransferDays, 20)
            XCTAssertEqual(chunk.totalTransferDays, 193)
        }

        try assertRoundTrip(.macExportStreamChunkAck(MacExportStreamChunkAck(
            jobID: jobID,
            sequence: 2,
            accepted: true,
            message: "Chunk accepted",
            processedDays: 20,
            filesWritten: 40
        ))) { decoded in
            guard case .macExportStreamChunkAck(let ack) = decoded else { return XCTFail("Expected macExportStreamChunkAck") }
            XCTAssertEqual(ack.jobID, jobID)
            XCTAssertEqual(ack.sequence, 2)
            XCTAssertTrue(ack.accepted)
            XCTAssertEqual(ack.message, "Chunk accepted")
            XCTAssertEqual(ack.processedDays, 20)
            XCTAssertEqual(ack.filesWritten, 40)
        }

        try assertRoundTrip(.macExportStreamComplete(MacExportStreamComplete(
            jobID: jobID,
            totalChunks: 10,
            iphoneFailedDateDetails: [FailedDateDetail(date: date, reason: .noHealthData, errorDetails: "No samples")]
        ))) { decoded in
            guard case .macExportStreamComplete(let complete) = decoded else { return XCTFail("Expected macExportStreamComplete") }
            XCTAssertEqual(complete.jobID, jobID)
            XCTAssertEqual(complete.totalChunks, 10)
            XCTAssertEqual(complete.iphoneFailedDateDetails.count, 1)
            XCTAssertEqual(complete.iphoneFailedDateDetails.first?.reason, .noHealthData)
        }

        try assertRoundTrip(.macExportStreamAbort(MacExportStreamAbort(
            jobID: jobID,
            reason: .payloadDecodeFailure,
            message: "Could not decode chunk."
        ))) { decoded in
            guard case .macExportStreamAbort(let abort) = decoded else { return XCTFail("Expected macExportStreamAbort") }
            XCTAssertEqual(abort.jobID, jobID)
            XCTAssertEqual(abort.reason, .payloadDecodeFailure)
            XCTAssertEqual(abort.message, "Could not decode chunk.")
        }

        try assertRoundTrip(.macExportAccepted(MacExportAcknowledgement(
            jobID: jobID,
            acceptedAt: date,
            message: "Accepted"
        ))) { decoded in
            guard case .macExportAccepted(let acknowledgement) = decoded else { return XCTFail("Expected macExportAccepted") }
            XCTAssertEqual(acknowledgement.jobID, jobID)
            XCTAssertEqual(acknowledgement.message, "Accepted")
        }

        try assertRoundTrip(.macExportProgress(MacExportProgress(
            jobID: jobID,
            phase: .writing,
            processedDays: 1,
            totalDays: 2,
            currentDate: date,
            filesWritten: 3,
            message: "Writing files…"
        ))) { decoded in
            guard case .macExportProgress(let progress) = decoded else { return XCTFail("Expected macExportProgress") }
            XCTAssertEqual(progress.phase, .writing)
            XCTAssertEqual(progress.fractionComplete, 0.5, accuracy: 0.001)
            XCTAssertEqual(progress.filesWritten, 3)
        }

        try assertRoundTrip(.macExportResult(MacExportResultPayload(
            jobID: jobID,
            status: .partialSuccess,
            successCount: 1,
            totalCount: 2,
            formatsPerDate: 4,
            totalFilesWritten: 5,
            externalRecordFileCount: 1,
            dailyNoteUpdateCount: 1,
            dailyNoteSkipCount: 1,
            failedDateDetails: [FailedDateDetail(date: date, reason: .noHealthData, errorDetails: "No samples")],
            completedDates: [date],
            destinationDisplayName: "Exports",
            destinationPathForDisplay: "/Users/cody/Exports",
            completedAt: date
        ))) { decoded in
            guard case .macExportResult(let result) = decoded else { return XCTFail("Expected macExportResult") }
            XCTAssertEqual(result.status, .partialSuccess)
            XCTAssertEqual(result.successCount, 1)
            XCTAssertEqual(result.failedDateDetails.count, 1)
            XCTAssertEqual(result.totalFilesWritten, 5)
            XCTAssertEqual(result.externalRecordFileCount, 1)
            XCTAssertEqual(result.dailyNoteUpdateCount, 1)
            XCTAssertEqual(result.dailyNoteSkipCount, 1)
            XCTAssertEqual(result.completedDates, [date])
        }

        try assertRoundTrip(.macExportCancel(jobID: jobID)) { decoded in
            guard case .macExportCancel(jobID: let decodedJobID) = decoded else { return XCTFail("Expected macExportCancel") }
            XCTAssertEqual(decodedJobID, jobID)
        }


        try assertRoundTrip(.macExportFailed(MacExportFailure(
            jobID: jobID,
            reason: .macFolderAccessDenied,
            message: "Cannot access the selected folder.",
            underlyingError: "Bookmark stale",
            occurredAt: date
        ))) { decoded in
            guard case .macExportFailed(let failure) = decoded else { return XCTFail("Expected macExportFailed") }
            XCTAssertEqual(failure.jobID, jobID)
            XCTAssertEqual(failure.reason, .macFolderAccessDenied)
            XCTAssertEqual(failure.underlyingError, "Bookmark stale")
        }

        try assertRoundTrip(.iphoneExportRequest(IPhoneExportRequest(
            jobID: jobID,
            createdAt: date,
            dateSelection: .allAvailable,
            dateRangeStart: date,
            dateRangeEnd: date,
            requestedBy: .cli,
            settingsPolicy: .requestedDatesOnly,
            responseMode: .rawJSON
        ))) { decoded in
            guard case .iphoneExportRequest(let request) = decoded else { return XCTFail("Expected iphoneExportRequest") }
            XCTAssertEqual(request.jobID, jobID)
            XCTAssertEqual(request.dateSelection, .allAvailable)
            XCTAssertEqual(request.requestedBy, .cli)
            XCTAssertEqual(request.settingsPolicy, .requestedDatesOnly)
            XCTAssertEqual(request.responseMode, .rawJSON)
        }

        try assertRoundTrip(.iphoneExportRawData(IPhoneExportRawDataPayload(
            jobID: jobID,
            createdAt: date,
            sourceDeviceName: "Cody's iPhone",
            dateRangeStart: date,
            dateRangeEnd: date,
            totalDays: 1,
            records: [healthData],
            externalDailyRecords: [externalRecord],
            failedDateDetails: [],
            settingsSnapshot: snapshot
        ))) { decoded in
            guard case .iphoneExportRawData(let payload) = decoded else { return XCTFail("Expected iphoneExportRawData") }
            XCTAssertEqual(payload.jobID, jobID)
            XCTAssertEqual(payload.sourceDeviceName, "Cody's iPhone")
            XCTAssertEqual(payload.totalDays, 1)
            XCTAssertEqual(payload.records.count, 1)
            XCTAssertEqual(payload.externalDailyRecords.first?.provider, .strava)
            XCTAssertEqual(payload.settingsSnapshot, snapshot)
            XCTAssertNil(payload.strictResult)
        }

        let transferManifest = ConnectedTransferManifest(
            kind: .canonicalRawResultV1,
            jobID: jobID,
            payloadSchemaVersion: 1
        )
        let transferBytes = Data("bounded chunk".utf8)
        let transferHash = ConnectedTransferFile.sha256Hex(transferBytes)
        try assertRoundTrip(.connectedTransferStart(ConnectedTransferStart(
            protocolVersion: 1,
            transferID: jobID,
            manifest: transferManifest,
            totalBytes: Int64(transferBytes.count),
            totalChunks: 1,
            chunkBytes: ConnectedTransferReceiver.maximumChunkBytes,
            sha256: transferHash
        ))) { decoded in
            guard case .connectedTransferStart(let start) = decoded else { return XCTFail("Expected connectedTransferStart") }
            XCTAssertEqual(start.manifest, transferManifest)
            XCTAssertEqual(start.totalChunks, 1)
        }
        try assertRoundTrip(.connectedTransferChunk(ConnectedTransferChunk(
            transferID: jobID,
            sequence: 1,
            data: transferBytes,
            sha256: transferHash
        ))) { decoded in
            guard case .connectedTransferChunk(let chunk) = decoded else { return XCTFail("Expected connectedTransferChunk") }
            XCTAssertEqual(chunk.data, transferBytes)
        }
        try assertRoundTrip(.connectedTransferAck(ConnectedTransferAck(
            transferID: jobID,
            sequence: 1,
            accepted: true,
            sha256: transferHash,
            message: nil
        ))) { decoded in
            guard case .connectedTransferAck(let acknowledgement) = decoded else { return XCTFail("Expected connectedTransferAck") }
            XCTAssertTrue(acknowledgement.accepted)
        }
        try assertRoundTrip(.connectedTransferComplete(ConnectedTransferComplete(
            transferID: jobID,
            totalBytes: Int64(transferBytes.count),
            totalChunks: 1,
            sha256: transferHash
        ))) { decoded in
            guard case .connectedTransferComplete(let complete) = decoded else { return XCTFail("Expected connectedTransferComplete") }
            XCTAssertEqual(complete.sha256, transferHash)
        }
        try assertRoundTrip(.connectedTransferFinalAck(ConnectedTransferFinalAck(
            transferID: jobID,
            accepted: true,
            sha256: transferHash,
            message: nil
        ))) { decoded in
            guard case .connectedTransferFinalAck(let acknowledgement) = decoded else { return XCTFail("Expected connectedTransferFinalAck") }
            XCTAssertTrue(acknowledgement.accepted)
        }
        try assertRoundTrip(.connectedTransferAbort(ConnectedTransferAbort(
            transferID: jobID,
            jobID: jobID,
            reason: .cancelled,
            message: "Cancelled"
        ))) { decoded in
            guard case .connectedTransferAbort(let abort) = decoded else { return XCTFail("Expected connectedTransferAbort") }
            XCTAssertEqual(abort.reason, .cancelled)
        }

        try assertRoundTrip(.iphoneExportAccepted(IPhoneExportAcknowledgement(
            jobID: jobID,
            acceptedAt: date,
            message: "Preparing",
            resolvedDateRangeStart: date,
            resolvedDateRangeEnd: date,
            resolvedDateIdentifiers: ["2023-11-14"]
        ))) { decoded in
            guard case .iphoneExportAccepted(let acknowledgement) = decoded else { return XCTFail("Expected iphoneExportAccepted") }
            XCTAssertEqual(acknowledgement.jobID, jobID)
            XCTAssertEqual(acknowledgement.message, "Preparing")
            XCTAssertEqual(acknowledgement.resolvedDateRangeStart, date)
            XCTAssertEqual(acknowledgement.resolvedDateRangeEnd, date)
            XCTAssertEqual(acknowledgement.resolvedDateIdentifiers, ["2023-11-14"])
        }

        try assertRoundTrip(.iphoneExportPreparationProgress(IPhoneExportPreparationProgress(
            jobID: jobID,
            processedDays: 1,
            totalDays: 4,
            currentDate: date,
            message: "Preparing on iPhone…"
        ))) { decoded in
            guard case .iphoneExportPreparationProgress(let progress) = decoded else { return XCTFail("Expected iphoneExportPreparationProgress") }
            XCTAssertEqual(progress.jobID, jobID)
            XCTAssertEqual(progress.fractionComplete, 0.25, accuracy: 0.001)
        }

        try assertRoundTrip(.iphoneExportRejected(IPhoneExportFailure(
            jobID: jobID,
            reason: .macDestinationUnavailable,
            message: "Mac destination is not ready.",
            underlyingError: "No folder",
            occurredAt: date
        ))) { decoded in
            guard case .iphoneExportRejected(let failure) = decoded else { return XCTFail("Expected iphoneExportRejected") }
            XCTAssertEqual(failure.jobID, jobID)
            XCTAssertEqual(failure.reason, .macDestinationUnavailable)
            XCTAssertEqual(failure.underlyingError, "No folder")
        }
    }

    func testIPhoneExportRequestLegacyPayloadDefaultsToExplicitRange() throws {
        let date = Date(timeIntervalSince1970: 1_700_000_000)
        let request = IPhoneExportRequest(
            jobID: UUID(),
            createdAt: date,
            dateRangeStart: date,
            dateRangeEnd: date,
            requestedBy: .cli,
            settingsPolicy: .requestedDatesOnly
        )
        let encoded = try JSONEncoder().encode(request)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "dateSelection")

        let decoded = try JSONDecoder().decode(
            IPhoneExportRequest.self,
            from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        )

        XCTAssertEqual(decoded.dateSelection, .explicitRange)
        XCTAssertEqual(decoded.dateRangeStart, date)
        XCTAssertEqual(decoded.dateRangeEnd, date)
    }

    func testLegacyMessagesStillDecode() throws {
        let legacyMessages: [SyncMessage] = [
            .requestData(dates: [Date(timeIntervalSince1970: 1_700_000_000)]),
            .requestAllData,
            .healthData(SyncPayload(
                deviceName: "iPhone",
                syncTimestamp: Date(timeIntervalSince1970: 1_700_000_001),
                healthRecords: [HealthData(date: Date(timeIntervalSince1970: 1_700_000_000))]
            )),
            .syncProgress(SyncProgressInfo(
                totalDays: 10,
                processedDays: 5,
                recordsInBatch: 2,
                isComplete: false,
                message: "Syncing…"
            )),
            .ping,
            .pong
        ]

        for message in legacyMessages {
            let data = try JSONEncoder().encode(message)
            XCTAssertNoThrow(try JSONDecoder().decode(SyncMessage.self, from: data))
        }
    }

    private func assertRoundTrip(
        _ message: SyncMessage,
        file: StaticString = #filePath,
        line: UInt = #line,
        assert: (SyncMessage) -> Void
    ) throws {
        let data = try JSONEncoder().encode(message)
        let decoded = try JSONDecoder().decode(SyncMessage.self, from: data)
        assert(decoded)
    }

    private func makeMedicationHealthData(date: Date) -> HealthData {
        var data = HealthData(date: date)
        data.medications = MedicationsData(
            medications: [
                Medication(
                    conceptIdentifier: "rxnorm:617314",
                    displayName: "Vitamin D3",
                    nickname: "D3",
                    generalForm: "tablet",
                    isArchived: false,
                    hasSchedule: true,
                    relatedCodings: [MedicationCoding(system: "http://www.nlm.nih.gov/research/umls/rxnorm", version: nil, code: "617314")]
                )
            ],
            doseEvents: [
                MedicationDoseEvent(
                    id: UUID(uuidString: "22222222-2222-2222-2222-222222222222")!,
                    medicationConceptIdentifier: "rxnorm:617314",
                    medicationName: "D3",
                    startDate: date,
                    endDate: date.addingTimeInterval(60),
                    scheduledDate: date,
                    doseQuantity: 1,
                    scheduledDoseQuantity: 1,
                    unit: "tablet",
                    logStatus: .taken,
                    scheduleType: .scheduled
                )
            ]
        )
        return data
    }

    private func makeSnapshot() -> ExportSettingsSnapshot {
        let settings = makeSettings()
        settings.exportFormats = [.markdown, .json]
        settings.includeGranularData = true
        return .from(settings, healthSubfolder: "2. Areas/Health")
    }

    private func makeSettings() -> AdvancedExportSettings {
        let suiteName = "SyncV2ProtocolTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        return LifecycleHarness.retain(settings)
    }
}

final class MacExportFileAccountingCompatibilityTests: XCTestCase {
    func testLegacyPeerWithoutAccountingCapabilityIsRejectedInBothDirections() throws {
        let currentIOS = SyncPeerCapabilities.current(
            platform: .iOS,
            installationID: UUID(uuidString: "10000000-0000-0000-0000-000000000001")!
        )
        let currentMac = SyncPeerCapabilities.current(
            platform: .macOS,
            installationID: UUID(uuidString: "20000000-0000-0000-0000-000000000002")!
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(currentMac)) as? [String: Any]
        )
        object.removeValue(forKey: "supportsAuthoritativeMacExportFileAccounting")
        let legacyMac = try JSONDecoder().decode(
            SyncPeerCapabilities.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertFalse(legacyMac.supportsAuthoritativeMacExportFileAccounting)
        XCTAssertFalse(legacyMac.isCompatibleWithMacExportJobs)
        XCTAssertTrue(currentIOS.supportsAuthoritativeMacExportFileAccounting)
        XCTAssertTrue(currentMac.supportsAuthoritativeMacExportFileAccounting)

        object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(currentIOS)) as? [String: Any]
        )
        object.removeValue(forKey: "supportsAuthoritativeMacExportFileAccounting")
        let legacyIOS = try JSONDecoder().decode(
            SyncPeerCapabilities.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertFalse(legacyIOS.isCompatibleWithMacExportJobs)
    }

    func testMissingAuthorityMetadataDecodesAsLowerBound() throws {
        let payload = makePayload(status: .partialSuccess)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        )
        object.removeValue(forKey: "isTotalFilesWrittenAuthoritative")
        object.removeValue(forKey: "outputBreakdown")
        object.removeValue(forKey: "hadTerminalRangeFailure")
        let decoded = try JSONDecoder().decode(
            MacExportResultPayload.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertFalse(decoded.isTotalFilesWrittenAuthoritative)
        XCTAssertFalse(decoded.hadTerminalRangeFailure)
    }

    func testLegacyPayloadWithoutBreakdownRejectsImpliedFilesAboveWireTotal() {
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .success,
            successCount: 2,
            totalCount: 2,
            formatsPerDate: 2,
            totalFilesWritten: 4,
            isTotalFilesWrittenAuthoritative: true,
            externalRecordFileCount: 1,
            failedDateDetails: [],
            completedDates: [
                Date(timeIntervalSince1970: 1_700_000_000),
                Date(timeIntervalSince1970: 1_700_086_400)
            ],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date()
        )

        XCTAssertNil(payload.outputBreakdown)
        XCTAssertFalse(payload.hasConsistentFileAccounting)
        XCTAssertFalse(payload.hasAuthoritativeFileCount)
    }

    func testLegacyPayloadWithoutBreakdownSeparatesSidecarsAndRemainder() {
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .success,
            successCount: 1,
            totalCount: 1,
            formatsPerDate: 2,
            totalFilesWritten: 5,
            isTotalFilesWrittenAuthoritative: true,
            externalRecordFileCount: 1,
            failedDateDetails: [],
            completedDates: [Date(timeIntervalSince1970: 1_700_000_000)],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date()
        )

        XCTAssertTrue(payload.hasConsistentFileAccounting)
        let result = ExportOrchestrator.ExportResult(macExportPayload: payload)
        XCTAssertEqual(result.looseAggregateFileCount, 2)
        XCTAssertEqual(result.externalRecordFileCount, 1)
        XCTAssertEqual(result.unclassifiedFileCount, 2)
        XCTAssertEqual(result.categorizedFileCount, 3)
        XCTAssertEqual(result.knownFileCount, 5)
        XCTAssertEqual(result.totalFilesWritten, 5)
        XCTAssertEqual(result.outputBreakdown.generatedFileCount, 5)
    }

    func testCancelledPayloadWithoutBreakdownDoesNotDoubleCountSidecars() {
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .cancelled,
            successCount: 1,
            totalCount: 3,
            formatsPerDate: 2,
            totalFilesWritten: 4,
            externalRecordFileCount: 1,
            failedDateDetails: [],
            completedDates: [Date(timeIntervalSince1970: 1_700_000_000)],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date()
        )

        XCTAssertTrue(payload.hasConsistentFileAccounting)
        let result = ExportOrchestrator.ExportResult(macExportPayload: payload)
        XCTAssertTrue(result.wasCancelled)
        XCTAssertEqual(result.looseAggregateFileCount, 2)
        XCTAssertEqual(result.externalRecordFileCount, 1)
        XCTAssertEqual(result.unclassifiedFileCount, 1)
        XCTAssertEqual(result.knownFileCount, 4)
        XCTAssertEqual(result.totalFilesWritten, 4)
        XCTAssertFalse(result.hasAuthoritativeFileCount)
    }

    func testAuthoritativeTotalAboveCapReconstructsPayloadWithConservativeAuthority() throws {
        let budget = ExportHistoryOutputBreakdown.maximumPersistedCount
        let breakdown = ExportHistoryOutputBreakdown(
            requestedDataDayCount: 1,
            successfulDataDayCount: 1,
            looseAggregateFileCount: budget,
            providerSidecarFileCount: 1,
            isFileCategoryBreakdownComplete: true
        )
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .success,
            successCount: 1,
            totalCount: 1,
            formatsPerDate: 1,
            totalFilesWritten: budget + 1,
            isTotalFilesWrittenAuthoritative: true,
            externalRecordFileCount: 1,
            outputBreakdown: breakdown,
            failedDateDetails: [],
            completedDates: [Date(timeIntervalSince1970: 1_700_000_000)],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date()
        )

        XCTAssertTrue(breakdown.isFileCategoryBreakdownComplete)
        XCTAssertTrue(breakdown.wasTruncated)
        XCTAssertEqual(breakdown.providerSidecarFileCount, 0)
        XCTAssertLessThan(breakdown.providerSidecarFileCount, payload.externalRecordFileCount)
        XCTAssertTrue(payload.hasConsistentFileAccounting)
        XCTAssertFalse(payload.isTotalFilesWrittenAuthoritative)
        XCTAssertFalse(payload.hasAuthoritativeFileCount)
        XCTAssertEqual(payload.generatedFileCountDescription, "at least \(budget + 1) file(s)")

        struct LegacyAccountingReader: Decodable {
            let totalFilesWritten: Int
            let isTotalFilesWrittenAuthoritative: Bool
        }
        let legacyDecoded = try JSONDecoder().decode(
            LegacyAccountingReader.self,
            from: JSONEncoder().encode(payload)
        )
        XCTAssertEqual(legacyDecoded.totalFilesWritten, budget + 1)
        XCTAssertFalse(legacyDecoded.isTotalFilesWrittenAuthoritative)

        let roundTrippedPayload = try JSONDecoder().decode(
            MacExportResultPayload.self,
            from: JSONEncoder().encode(payload)
        )
        let result = ExportOrchestrator.ExportResult(macExportPayload: roundTrippedPayload)
        XCTAssertEqual(result.totalFilesWritten, budget + 1)
        XCTAssertFalse(result.hasAuthoritativeFileCount)
        XCTAssertTrue(result.localizedGeneratedFileAndDataDayDescription.hasPrefix("≥ "))
        XCTAssertTrue(result.outputBreakdown.isFileCategoryBreakdownComplete)
        XCTAssertTrue(result.outputBreakdown.wasTruncated)
        XCTAssertEqual(result.outputBreakdown.unclassifiedFileCount, 0)

        let reconstructedHistory = ExportHistoryEntry(
            source: .macAgent,
            success: true,
            dateRangeStart: Date(),
            dateRangeEnd: Date(),
            successCount: 1,
            totalCount: 1,
            fileCount: result.totalFilesWritten,
            outputBreakdown: result.outputBreakdown
        )
        XCTAssertNil(reconstructedHistory.fileCount)
        XCTAssertTrue(reconstructedHistory.outputBreakdown?.wasTruncated == true)
    }

    func testDecodeNormalizesTruncatedBreakdownAuthorityFromMixedVersionPeer() throws {
        let budget = ExportHistoryOutputBreakdown.maximumPersistedCount
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .success,
            successCount: 1,
            totalCount: 1,
            formatsPerDate: 1,
            totalFilesWritten: budget + 1,
            isTotalFilesWrittenAuthoritative: true,
            outputBreakdown: ExportHistoryOutputBreakdown(
                requestedDataDayCount: 1,
                successfulDataDayCount: 1,
                looseAggregateFileCount: budget,
                providerSidecarFileCount: 1,
                isFileCategoryBreakdownComplete: true
            ),
            failedDateDetails: [],
            completedDates: [Date(timeIntervalSince1970: 1_700_000_000)],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date()
        )
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(payload)) as? [String: Any]
        )
        object["isTotalFilesWrittenAuthoritative"] = true

        let decoded = try JSONDecoder().decode(
            MacExportResultPayload.self,
            from: JSONSerialization.data(withJSONObject: object)
        )

        XCTAssertEqual(decoded.totalFilesWritten, budget + 1)
        XCTAssertTrue(decoded.outputBreakdown?.wasTruncated == true)
        XCTAssertFalse(decoded.isTotalFilesWrittenAuthoritative)
        XCTAssertFalse(decoded.hasAuthoritativeFileCount)
    }

    func testPayloadRejectsDailyNoteUpdateMismatchBetweenBreakdownAndTopLevel() {
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .success,
            successCount: 1,
            totalCount: 1,
            formatsPerDate: 1,
            totalFilesWritten: 1,
            outputBreakdown: ExportHistoryOutputBreakdown(
                requestedDataDayCount: 1,
                successfulDataDayCount: 1,
                looseAggregateFileCount: 1,
                dailyNoteUpdateCount: 1
            ),
            dailyNoteUpdateCount: 2,
            failedDateDetails: [],
            completedDates: [Date(timeIntervalSince1970: 1_700_000_000)],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date()
        )

        XCTAssertFalse(payload.hasConsistentFileAccounting)
    }

    func testPayloadRejectsDailyNoteSkipMismatchBetweenBreakdownAndTopLevel() {
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .partialSuccess,
            successCount: 0,
            totalCount: 1,
            formatsPerDate: 0,
            totalFilesWritten: 0,
            outputBreakdown: ExportHistoryOutputBreakdown(
                requestedDataDayCount: 1,
                successfulDataDayCount: 0,
                dailyNoteSkipCount: 1
            ),
            dailyNoteSkipCount: 2,
            failedDateDetails: [
                FailedDateDetail(
                    date: Date(timeIntervalSince1970: 1_700_000_000),
                    reason: .noHealthData
                )
            ],
            completedDates: [Date(timeIntervalSince1970: 1_700_000_000)],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date()
        )

        XCTAssertFalse(payload.hasConsistentFileAccounting)
    }

    func testPayloadWithoutBreakdownRejectsDailyNoteActionsAboveTotalCount() {
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .partialSuccess,
            successCount: 0,
            totalCount: 1,
            formatsPerDate: 0,
            totalFilesWritten: 0,
            dailyNoteUpdateCount: 1,
            dailyNoteSkipCount: 1,
            failedDateDetails: [],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date()
        )

        XCTAssertNil(payload.outputBreakdown)
        XCTAssertFalse(payload.hasConsistentFileAccounting)
    }

    func testPayloadWithBreakdownRejectsDailyNoteActionsAboveTotalCount() {
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .partialSuccess,
            successCount: 0,
            totalCount: 1,
            formatsPerDate: 0,
            totalFilesWritten: 0,
            outputBreakdown: ExportHistoryOutputBreakdown(
                requestedDataDayCount: 1,
                successfulDataDayCount: 0,
                dailyNoteUpdateCount: 1,
                dailyNoteSkipCount: 1
            ),
            dailyNoteUpdateCount: 1,
            dailyNoteSkipCount: 1,
            failedDateDetails: [],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date()
        )

        XCTAssertEqual(payload.outputBreakdown?.dailyNoteUpdateCount, payload.dailyNoteUpdateCount)
        XCTAssertEqual(payload.outputBreakdown?.dailyNoteSkipCount, payload.dailyNoteSkipCount)
        XCTAssertFalse(payload.hasConsistentFileAccounting)
    }

    func testPayloadStatusAcceptsFullSuccessAndRejectsContradictorySuccess() {
        let fullSuccess = makeStatusPayload(
            status: .success,
            successCount: 1,
            totalCount: 1,
            formatsPerDate: 0,
            totalFilesWritten: 0,
            dailyNoteUpdateCount: 1
        )
        let zeroOfRequested = makeStatusPayload(
            status: .success,
            successCount: 0,
            totalCount: 2
        )
        let failedFullCount = makeStatusPayload(
            status: .success,
            successCount: 2,
            totalCount: 2,
            failedDateDetails: [FailedDateDetail(date: Date(), reason: .fileWriteError)]
        )
        let emptyRequest = makeStatusPayload(
            status: .success,
            successCount: 0,
            totalCount: 0
        )

        XCTAssertTrue(fullSuccess.hasCoherentStatus, "Daily-note success can be fileless")
        XCTAssertFalse(zeroOfRequested.hasCoherentStatus)
        XCTAssertFalse(failedFullCount.hasCoherentStatus)
        XCTAssertFalse(emptyRequest.hasCoherentStatus)
    }

    func testPayloadStatusRequiresEvidenceForPartialSuccess() {
        let successfulDay = makeStatusPayload(
            status: .partialSuccess,
            successCount: 1,
            totalCount: 2,
            formatsPerDate: 1,
            totalFilesWritten: 1
        )
        let skippedDailyNote = makeStatusPayload(
            status: .partialSuccess,
            successCount: 0,
            totalCount: 2,
            dailyNoteSkipCount: 1
        )
        let terminalFile = makeStatusPayload(
            status: .partialSuccess,
            successCount: 0,
            totalCount: 2,
            totalFilesWritten: 1,
            hadTerminalRangeFailure: true
        )
        let noEvidence = makeStatusPayload(
            status: .partialSuccess,
            successCount: 0,
            totalCount: 2
        )
        let mislabeledFullSuccess = makeStatusPayload(
            status: .partialSuccess,
            successCount: 2,
            totalCount: 2
        )

        XCTAssertTrue(successfulDay.hasCoherentStatus)
        XCTAssertTrue(skippedDailyNote.hasCoherentStatus)
        XCTAssertTrue(terminalFile.hasCoherentStatus)
        XCTAssertFalse(noEvidence.hasCoherentStatus)
        XCTAssertFalse(mislabeledFullSuccess.hasCoherentStatus)
    }

    func testPayloadStatusFailureCannotClaimSuccessfulEffects() {
        let terminalNoData = makeStatusPayload(
            status: .failure,
            successCount: 0,
            totalCount: 2,
            hadTerminalRangeFailure: true,
            failedDateDetails: [FailedDateDetail(date: Date(), reason: .noHealthData)]
        )
        let successfulDay = makeStatusPayload(
            status: .failure,
            successCount: 1,
            totalCount: 2
        )
        let generatedFile = makeStatusPayload(
            status: .failure,
            successCount: 0,
            totalCount: 2,
            totalFilesWritten: 1
        )
        let dailyNoteEffect = makeStatusPayload(
            status: .failure,
            successCount: 0,
            totalCount: 2,
            dailyNoteUpdateCount: 1
        )

        XCTAssertTrue(terminalNoData.hasCoherentStatus)
        XCTAssertFalse(successfulDay.hasCoherentStatus)
        XCTAssertFalse(generatedFile.hasCoherentStatus)
        XCTAssertFalse(dailyNoteEffect.hasCoherentStatus)
    }

    func testPayloadStatusAllowsCancellationBeforeOrAfterOutput() {
        let beforeOutput = makeStatusPayload(
            status: .cancelled,
            successCount: 0,
            totalCount: 2
        )
        let afterOutput = makeStatusPayload(
            status: .cancelled,
            successCount: 1,
            totalCount: 2,
            formatsPerDate: 1,
            totalFilesWritten: 1
        )
        let emptyRequest = makeStatusPayload(
            status: .cancelled,
            successCount: 0,
            totalCount: 0
        )

        XCTAssertTrue(beforeOutput.hasCoherentStatus)
        XCTAssertTrue(afterOutput.hasCoherentStatus)
        XCTAssertFalse(emptyRequest.hasCoherentStatus)
    }

    func testPayloadRejectsOverflowingTopLevelAccounting() {
        let multiplicationOverflow = MacExportResultPayload(
            jobID: UUID(),
            status: .success,
            successCount: Int.max,
            totalCount: Int.max,
            formatsPerDate: 2,
            totalFilesWritten: Int.max,
            failedDateDetails: [],
            destinationDisplayName: nil,
            destinationPathForDisplay: nil,
            completedAt: Date()
        )
        XCTAssertFalse(multiplicationOverflow.hasConsistentFileAccounting)

        let knownFileSumOverflow = MacExportResultPayload(
            jobID: UUID(),
            status: .success,
            successCount: Int.max,
            totalCount: Int.max,
            formatsPerDate: 1,
            totalFilesWritten: Int.max,
            externalRecordFileCount: 1,
            failedDateDetails: [],
            destinationDisplayName: nil,
            destinationPathForDisplay: nil,
            completedAt: Date()
        )
        XCTAssertFalse(knownFileSumOverflow.hasConsistentFileAccounting)

        let noteSumOverflow = MacExportResultPayload(
            jobID: UUID(),
            status: .success,
            successCount: 0,
            totalCount: Int.max,
            formatsPerDate: 0,
            totalFilesWritten: 0,
            dailyNoteUpdateCount: Int.max,
            dailyNoteSkipCount: 1,
            failedDateDetails: [],
            destinationDisplayName: nil,
            destinationPathForDisplay: nil,
            completedAt: Date()
        )
        XCTAssertFalse(noteSumOverflow.hasConsistentFileAccounting)
    }

    func testMaximumNonoverflowingAccountingRemainsSafeAcrossResultOperations() {
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .success,
            successCount: Int.max,
            totalCount: Int.max,
            formatsPerDate: 1,
            totalFilesWritten: Int.max,
            failedDateDetails: [],
            destinationDisplayName: nil,
            destinationPathForDisplay: nil,
            completedAt: Date()
        )

        XCTAssertTrue(payload.hasConsistentFileAccounting)
        let result = ExportOrchestrator.ExportResult(macExportPayload: payload)
        XCTAssertEqual(result.knownFileCount, Int.max)
        XCTAssertEqual(result.totalFilesWritten, Int.max)
        XCTAssertFalse(result.hasAuthoritativeFileCount)
        XCTAssertTrue(result.outputBreakdown.wasTruncated)

        let saturated = ExportOrchestrator.ExportResult(
            successCount: 1,
            totalCount: 1,
            failedDateDetails: [],
            looseAggregateFileCount: Int.max,
            individualEntryFileCount: Int.max,
            unclassifiedFileCount: Int.max
        )
        XCTAssertEqual(saturated.categorizedFileCount, Int.max)
        XCTAssertEqual(saturated.knownFileCount, Int.max)
        XCTAssertEqual(saturated.totalFilesWritten, Int.max)
    }

    func testTruncatedPayloadRejectsProviderSidecarCountAboveWireTotal() {
        let budget = ExportHistoryOutputBreakdown.maximumPersistedCount
        let breakdown = ExportHistoryOutputBreakdown(
            requestedDataDayCount: 1,
            successfulDataDayCount: 1,
            looseAggregateFileCount: budget - 2,
            providerSidecarFileCount: 2,
            unclassifiedFileCount: 1,
            isFileCategoryBreakdownComplete: true
        )
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .success,
            successCount: 1,
            totalCount: 1,
            formatsPerDate: 1,
            totalFilesWritten: budget + 1,
            isTotalFilesWrittenAuthoritative: true,
            externalRecordFileCount: 1,
            outputBreakdown: breakdown,
            failedDateDetails: [],
            completedDates: [Date(timeIntervalSince1970: 1_700_000_000)],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date()
        )

        XCTAssertTrue(breakdown.wasTruncated)
        XCTAssertGreaterThan(breakdown.providerSidecarFileCount, payload.externalRecordFileCount)
        XCTAssertFalse(payload.hasConsistentFileAccounting)
    }

    func testPayloadRejectsWireSidecarCountAboveTotalFilesWritten() {
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .success,
            successCount: 1,
            totalCount: 1,
            formatsPerDate: 1,
            totalFilesWritten: 1,
            isTotalFilesWrittenAuthoritative: true,
            externalRecordFileCount: 2,
            failedDateDetails: [],
            completedDates: [Date(timeIntervalSince1970: 1_700_000_000)],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date()
        )

        XCTAssertFalse(payload.hasConsistentFileAccounting)
        XCTAssertFalse(payload.hasAuthoritativeFileCount)
        XCTAssertEqual(payload.generatedFileCountDescription, "at least 1 file(s)")
    }

    func testNontruncatedPayloadRejectsCategorySumAboveWireTotal() {
        let breakdown = ExportHistoryOutputBreakdown(
            requestedDataDayCount: 1,
            successfulDataDayCount: 1,
            looseAggregateFileCount: 2,
            isFileCategoryBreakdownComplete: true
        )
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .success,
            successCount: 1,
            totalCount: 1,
            formatsPerDate: 1,
            totalFilesWritten: 1,
            isTotalFilesWrittenAuthoritative: true,
            outputBreakdown: breakdown,
            failedDateDetails: [],
            completedDates: [Date(timeIntervalSince1970: 1_700_000_000)],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date()
        )

        XCTAssertFalse(breakdown.wasTruncated)
        XCTAssertGreaterThan(breakdown.generatedFileCount, payload.totalFilesWritten)
        XCTAssertFalse(payload.hasConsistentFileAccounting)
        XCTAssertFalse(payload.hasAuthoritativeFileCount)
    }

    func testNontruncatedPayloadRetainsExactAuthorityAndDisplay() {
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .success,
            successCount: 1,
            totalCount: 1,
            formatsPerDate: 2,
            totalFilesWritten: 2,
            isTotalFilesWrittenAuthoritative: true,
            outputBreakdown: ExportHistoryOutputBreakdown(
                requestedDataDayCount: 1,
                successfulDataDayCount: 1,
                looseAggregateFileCount: 2,
                isFileCategoryBreakdownComplete: true
            ),
            failedDateDetails: [],
            completedDates: [Date(timeIntervalSince1970: 1_700_000_000)],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date()
        )

        XCTAssertTrue(payload.hasConsistentFileAccounting)
        XCTAssertTrue(payload.hasAuthoritativeFileCount)
        XCTAssertEqual(payload.generatedFileCountDescription, "2 file(s)")
        let result = ExportOrchestrator.ExportResult(macExportPayload: payload)
        XCTAssertTrue(result.hasAuthoritativeFileCount)
        XCTAssertFalse(result.localizedGeneratedFileAndDataDayDescription.hasPrefix("≥ "))
        XCTAssertFalse(result.outputBreakdown.wasTruncated)
    }

    func testPartialFailuresRoundTripAndLegacyOmissionDecodesNil() throws {
        let warning = ExportPartialFailure(
            date: Date(timeIntervalSince1970: 1_700_000_000),
            dataType: "Individual entries",
            dateRangeDescription: "2026-08-16",
            errorDescription: "Lossless records produced no individual entries for tracked metrics: weight not selected for the daily export."
        )
        let payload = makePayload(status: .partialSuccess)
        let withWarnings = MacExportResultPayload(
            jobID: payload.jobID,
            status: payload.status,
            successCount: payload.successCount,
            totalCount: payload.totalCount,
            formatsPerDate: payload.formatsPerDate,
            totalFilesWritten: payload.totalFilesWritten,
            failedDateDetails: payload.failedDateDetails,
            partialFailures: [warning],
            completedDates: payload.completedDates,
            destinationDisplayName: nil,
            destinationPathForDisplay: nil,
            completedAt: payload.completedAt
        )

        let encoded = try JSONEncoder().encode(withWarnings)
        let decoded = try JSONDecoder().decode(MacExportResultPayload.self, from: encoded)
        XCTAssertEqual(decoded.partialFailures, [warning])

        // Legacy peers never send the field; it must decode as nil, not fail.
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: encoded) as? [String: Any]
        )
        object.removeValue(forKey: "partialFailures")
        let legacyDecoded = try JSONDecoder().decode(
            MacExportResultPayload.self,
            from: JSONSerialization.data(withJSONObject: object)
        )
        XCTAssertNil(legacyDecoded.partialFailures)

        // Warnings ride through the shared ExportResult mapping unchanged.
        let exportResult = ExportOrchestrator.ExportResult(macExportPayload: decoded)
        XCTAssertEqual(exportResult.partialFailures, [warning])
        XCTAssertTrue(exportResult.hasPartialFailures)
    }

    func testOrdinaryPartialResultUsesExactCompletedDatesForResidualRetry() {
        let first = Date(timeIntervalSince1970: 1_700_000_000)
        let second = first.addingTimeInterval(86_400)
        let payload = MacExportResultPayload(
            jobID: UUID(),
            status: .partialSuccess,
            successCount: 1,
            totalCount: 2,
            formatsPerDate: 1,
            totalFilesWritten: 2,
            isTotalFilesWrittenAuthoritative: true,
            outputBreakdown: ExportHistoryOutputBreakdown(
                requestedDataDayCount: 2,
                successfulDataDayCount: 1,
                looseAggregateFileCount: 1,
                dataDictionaryFileCount: 1
            ),
            failedDateDetails: [FailedDateDetail(date: second, reason: .noHealthData)],
            completedDates: [first, second],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date()
        )
        let result = ExportOrchestrator.ExportResult(macExportPayload: payload)
        XCTAssertEqual(result.remainingDates(from: [first, second]), [])

        let rangeFailure = MacExportResultPayload(
            jobID: payload.jobID,
            status: .partialSuccess,
            successCount: 1,
            totalCount: 2,
            formatsPerDate: 1,
            totalFilesWritten: 2,
            isTotalFilesWrittenAuthoritative: true,
            outputBreakdown: payload.outputBreakdown,
            hadTerminalRangeFailure: true,
            failedDateDetails: payload.failedDateDetails,
            completedDates: [first],
            destinationDisplayName: "Mac",
            destinationPathForDisplay: nil,
            completedAt: Date()
        )
        XCTAssertNil(
            ExportOrchestrator.ExportResult(macExportPayload: rangeFailure)
                .remainingDates(from: [first, second])
        )
    }

    private func makeStatusPayload(
        status: MacExportResultStatus,
        successCount: Int,
        totalCount: Int,
        formatsPerDate: Int = 0,
        totalFilesWritten: Int = 0,
        hadTerminalRangeFailure: Bool = false,
        dailyNoteUpdateCount: Int = 0,
        dailyNoteSkipCount: Int = 0,
        failedDateDetails: [FailedDateDetail] = []
    ) -> MacExportResultPayload {
        MacExportResultPayload(
            jobID: UUID(),
            status: status,
            successCount: successCount,
            totalCount: totalCount,
            formatsPerDate: formatsPerDate,
            totalFilesWritten: totalFilesWritten,
            hadTerminalRangeFailure: hadTerminalRangeFailure,
            dailyNoteUpdateCount: dailyNoteUpdateCount,
            dailyNoteSkipCount: dailyNoteSkipCount,
            failedDateDetails: failedDateDetails,
            completedDates: [],
            destinationDisplayName: nil,
            destinationPathForDisplay: nil,
            completedAt: Date()
        )
    }

    private func makePayload(status: MacExportResultStatus) -> MacExportResultPayload {
        MacExportResultPayload(
            jobID: UUID(),
            status: status,
            successCount: 1,
            totalCount: 2,
            formatsPerDate: 1,
            totalFilesWritten: 1,
            failedDateDetails: [],
            completedDates: [],
            destinationDisplayName: nil,
            destinationPathForDisplay: nil,
            completedAt: Date()
        )
    }
}
