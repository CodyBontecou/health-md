import XCTest
@testable import HealthMd

final class SyncV2ProtocolTests: XCTestCase {

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

        XCTAssertTrue(decoded.isCompatibleWithMacExportJobs)
        XCTAssertFalse(decoded.supportsRollupSummaries)
        XCTAssertFalse(decoded.supportsSummaryOnlyExports)
        XCTAssertFalse(decoded.supportsAllAvailableHistoryExportRequests)
        XCTAssertFalse(decoded.supportsChunkedMacExportJobs)
        XCTAssertFalse(decoded.supportsSizeBoundedConnectedTransfers)
        XCTAssertFalse(decoded.supportsStrictRawStreaming)
        XCTAssertFalse(decoded.supportsPerDateExportCompletion)
        XCTAssertFalse(decoded.supportsDailyNoteOnlyExports)
        XCTAssertNil(decoded.installationID)
        XCTAssertFalse(decoded.supportsDurableConnectedExportRecovery)
        XCTAssertTrue(decoded.connectedTransferBinaryFrameVersions.isEmpty)
        XCTAssertEqual(decoded.connectedTransferMaximumInFlightChunks, 1)
        XCTAssertFalse(decoded.supportsScheduledConnectedMacExports)
        XCTAssertFalse(decoded.supportsManualIPSync)
        XCTAssertTrue(decoded.manualIPSyncRequiresPairing)
        XCTAssertTrue(decoded.supportsRequestedMacExportFeatures(rollupSummariesEnabled: false))
        XCTAssertFalse(decoded.supportsRequestedMacExportFeatures(rollupSummariesEnabled: true))
        XCTAssertFalse(decoded.supportsRequestedMacExportFeatures(
            rollupSummariesEnabled: true,
            summaryOnlyExportEnabled: true
        ))
        XCTAssertFalse(decoded.supportsRequestedMacExportFeatures(
            rollupSummariesEnabled: false,
            dailyNotesOnlyExportEnabled: true
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
        XCTAssertEqual(currentIOS.installationID, iosInstallationID)
        XCTAssertEqual(currentMac.installationID, macInstallationID)
        XCTAssertTrue(currentIOS.supportsDurableConnectedExportRecovery)
        XCTAssertTrue(currentMac.supportsDurableConnectedExportRecovery)
        XCTAssertEqual(
            currentMac.connectedTransferBinaryFrameVersions,
            [ConnectedTransferBinaryFrame.currentVersion]
        )
        XCTAssertEqual(currentMac.connectedTransferMaximumInFlightChunks, 4)
        XCTAssertEqual(currentMac.connectedCorpusTransferCapabilities?.protocolVersions, [1, 2])
        XCTAssertTrue(currentMac.supportsRequestedMacExportFeatures(
            rollupSummariesEnabled: false,
            dailyNotesOnlyExportEnabled: true
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
            "Update Health.md on Mac to export roll-up summaries"
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
