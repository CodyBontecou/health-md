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
            supportsGranularPayloads: true
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

    func testSyncMessageV2Cases_codable() throws {
        let jobID = UUID()
        let date = Date(timeIntervalSince1970: 1_800_000_000)
        let snapshot = makeSnapshot()
        let job = MacExportJob(
            jobID: jobID,
            createdAt: date,
            sourceDeviceName: "Cody's iPhone",
            dateRangeStart: date,
            dateRangeEnd: date,
            records: [HealthData(date: date)],
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
            XCTAssertEqual(decodedJob.settingsSnapshot, snapshot)
            XCTAssertEqual(decodedJob.requestedTarget?.kind, .connectedMac)
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
            totalFilesWritten: 4,
            failedDateDetails: [FailedDateDetail(date: date, reason: .noHealthData, errorDetails: "No samples")],
            destinationDisplayName: "Exports",
            destinationPathForDisplay: "/Users/cody/Exports",
            completedAt: date
        ))) { decoded in
            guard case .macExportResult(let result) = decoded else { return XCTFail("Expected macExportResult") }
            XCTAssertEqual(result.status, .partialSuccess)
            XCTAssertEqual(result.successCount, 1)
            XCTAssertEqual(result.failedDateDetails.count, 1)
            XCTAssertEqual(result.totalFilesWritten, 4)
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

    private func makeSnapshot() -> ExportSettingsSnapshot {
        let suiteName = "SyncV2ProtocolTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.markdown, .json]
        settings.includeGranularData = true
        LifecycleHarness.retain(settings)
        return .from(settings)
    }
}
