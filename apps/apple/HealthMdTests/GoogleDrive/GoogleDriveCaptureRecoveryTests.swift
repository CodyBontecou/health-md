import Foundation
import HealthKit
import XCTest
@testable import HealthMd

/// Real HealthKitManager -> exporter -> Drive materializer/service -> protected journal/runner.
/// Only HealthStoreProviding, credential storage, and the remote Drive API are synthetic.
@MainActor
final class GoogleDriveCaptureRecoveryTests: XCTestCase {
    nonisolated deinit {}

    func testPartialCaptureHistoryAndScheduledResidualSurviveRestart() async throws {
        try await exerciseResidual(profileID: nil, existingAppend: false)
    }

    func testProfileResidualDoesNotReappendCompletedOwner() async throws {
        try await exerciseResidual(profileID: UUID(), existingAppend: true)
    }

    private func exerciseResidual(profileID: UUID?, existingAppend: Bool) async throws {
        let harness = try Harness(existingAppend: existingAppend)
        defer { harness.cleanup() }
        let operationID = UUID()
        let request = PendingExportRequest(
            id: operationID, dates: harness.dates, source: .scheduled,
            exportTarget: .googleDrive, settingsSnapshot: harness.snapshot, profileID: profileID,
            googleDriveDestinationSnapshot: GoogleDriveDestinationSnapshot(destination: harness.destination),
            calendar: harness.calendar
        )
        let pending = InMemoryPendingExportStore()
        try pending.upsert(request)
        let coordinator = ScheduledExportCoordinator(
            pendingExportStore: pending, exportNotificationScheduler: SilentDriveNotifications(), calendar: harness.calendar
        )
        let initial = await harness.export(operationID: operationID, profileID: profileID, dates: request.dates)
        XCTAssertEqual(initial.successCount, 1)
        XCTAssertEqual(initial.completedDates, [harness.dates[0]])
        XCTAssertEqual(initial.failedDateDetails.map(\.date), [harness.dates[1]])
        _ = try await coordinator.completePendingScheduledExport(request, result: initial)
        let residual = try XCTUnwrap(pending.loadAll().first)
        XCTAssertEqual(residual.id, operationID)
        XCTAssertEqual(residual.dates, [harness.dates[1]])
        let firstBytes = try await harness.api.bytes(named: "2026-03-15.json")

        // Recreate service, managed store, and journal store over the same protected files.
        let restartedService = try harness.service()
        let recoveredValue = await restartedService.resumeRecoverableOperation(operationID)
        let recovered = try XCTUnwrap(recoveredValue)
        XCTAssertEqual(recovered.result.successCount, 1)
        XCTAssertEqual(recovered.result.completedDates, [harness.dates[0]])
        XCTAssertEqual(recovered.result.failedDateDetails.map(\.date), [harness.dates[1]])
        XCTAssertFalse(recovered.result.isFullSuccess, "history/quota must not acknowledge uncaptured B")
        XCTAssertEqual(recovered.result.failedDateDetails.first?.reason, initial.failedDateDetails.first?.reason)
        XCTAssertEqual(harness.healthStore.queriedSumIdentifiers.count, 1, "history resume must not query")

        harness.allowResidualCapture()
        let retried = await harness.export(operationID: residual.id, profileID: profileID, dates: residual.dates)
        XCTAssertEqual(retried.successCount, 1)
        XCTAssertEqual(retried.completedDates, [harness.dates[1]])
        _ = try await coordinator.completePendingScheduledExport(residual, result: retried)
        XCTAssertTrue(try pending.loadAll().isEmpty)
        XCTAssertEqual(harness.healthStore.queriedSumIdentifiers.count, 2, "B requires its own capture")
        let commits = await harness.api.commitCounts()
        XCTAssertEqual(commits["2026-03-15.json"], 1)
        XCTAssertEqual(commits["2026-03-16.json"], 1)
        let unchanged = try await harness.api.bytes(named: "2026-03-15.json")
        XCTAssertEqual(unchanged, firstBytes)
    }

    func testInterruptedTransportResumesExactAppendBytesAndRetainsCaptureFailure() async throws {
        let harness = try Harness(existingAppend: true)
        defer { harness.cleanup() }
        let operationID = UUID()
        await harness.api.interruptNextUpload()
        let initial = await harness.export(operationID: operationID, profileID: nil, dates: harness.dates)
        XCTAssertEqual(initial.successCount, 0)
        let initialAttempts = await harness.api.attempts(named: "2026-03-15.json")
        let firstAttempt = try XCTUnwrap(initialAttempts.first)
        let resumed = await harness.export(operationID: operationID, profileID: nil, dates: harness.dates)
        XCTAssertEqual(resumed.successCount, 1)
        XCTAssertEqual(resumed.completedDates, [harness.dates[0]])
        XCTAssertEqual(resumed.failedDateDetails.map(\.date), [harness.dates[1]])
        XCTAssertEqual(harness.healthStore.queriedSumIdentifiers.count, 1)
        let attempts = await harness.api.attempts(named: "2026-03-15.json")
        XCTAssertEqual(attempts, [firstAttempt, firstAttempt])
        let uploaded = try await harness.api.bytes(named: "2026-03-15.json")
        XCTAssertEqual(uploaded, firstAttempt)
    }

    func testResidualUploadRestartUsesPersistedChildIdentityAndExactBytes() async throws {
        let harness = try Harness(existingAppend: true)
        defer { harness.cleanup() }
        let operationID = UUID()
        let initial = await harness.export(operationID: operationID, profileID: nil, dates: harness.dates)
        XCTAssertEqual(initial.completedDates, [harness.dates[0]])
        let firstBytes = try await harness.api.bytes(named: "2026-03-15.json")
        harness.allowResidualCapture()
        await harness.api.interruptNextUpload()
        let residualDates = [harness.dates[1]]
        let interrupted = await harness.export(operationID: operationID, profileID: nil, dates: residualDates)
        XCTAssertEqual(interrupted.successCount, 0)
        XCTAssertEqual(interrupted.completedDates, [])
        let attempts = await harness.api.attempts(named: "2026-03-16.json")
        let staged = try XCTUnwrap(attempts.first)
        let journals = try GoogleDriveJournalStore(rootURL: harness.root)
        let parent = try await journals.load(operationID: operationID)
        XCTAssertEqual(parent.version, 2)
        XCTAssertEqual(parent.residualOperationIDs.count, 1)
        let childID = try XCTUnwrap(parent.residualOperationIDs.first)
        XCTAssertNotEqual(childID, operationID)
        let child = try await journals.load(operationID: childID)
        XCTAssertEqual(child.captureEvidence?.completedDates, residualDates)
        XCTAssertEqual(child.settingsSnapshotData, parent.settingsSnapshotData)
        XCTAssertEqual(child.destinationSnapshot, parent.destinationSnapshot)

        // Another freshly constructed service finds the child before recapturing or appending.
        let resumed = await harness.export(operationID: operationID, profileID: nil, dates: residualDates)
        XCTAssertTrue(resumed.isFullSuccess)
        XCTAssertEqual(resumed.completedDates, residualDates)
        XCTAssertEqual(harness.healthStore.queriedSumIdentifiers.count, 2)
        let retries = await harness.api.attempts(named: "2026-03-16.json")
        XCTAssertEqual(retries, [staged, staged])
        let unchanged = try await harness.api.bytes(named: "2026-03-15.json")
        XCTAssertEqual(unchanged, firstBytes)
        let commits = await harness.api.commitCounts()
        XCTAssertEqual(commits["2026-03-15.json"], 1)
        XCTAssertEqual(commits["2026-03-16.json"], 1)
        await (try harness.service()).acknowledgeCompletedOperation(operationID)
        let recoverable = await journals.loadRecoverable()
        XCTAssertTrue(recoverable.isEmpty, "durable history acknowledgement covers child uploads too")
    }

    func testLegacyFutureAndMissingCaptureEvidenceStayUnchangedAndNeverClaimSuccess() async throws {
        let harness = try Harness(existingAppend: false)
        defer { harness.cleanup() }
        let operationID = UUID()
        let initial = await harness.export(operationID: operationID, profileID: nil, dates: harness.dates)
        XCTAssertEqual(initial.successCount, 1)
        let url = harness.root.appendingPathComponent("journals/\(operationID.uuidString.lowercased()).json")
        let original = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        for version in [1, 2, 99] {
            var unknown = original
            unknown["version"] = version
            unknown.removeValue(forKey: "captureEvidence")
            if version == 1 {
                unknown.removeValue(forKey: "residualOperationIDs")
                unknown.removeValue(forKey: "settingsDigest")
                unknown.removeValue(forKey: "settingsSnapshotData")
            }
            let bytes = try JSONSerialization.data(withJSONObject: unknown, options: [.sortedKeys])
            try bytes.write(to: url, options: [.atomic])
            let result = await harness.export(operationID: operationID, profileID: nil, dates: [harness.dates[1]])
            XCTAssertEqual(result.successCount, 0, "unknown journal version \(version)")
            XCTAssertEqual(result.completedDates, [])
            let recovered = await (try harness.service()).resumeRecoverableOperation(operationID)
            XCTAssertNil(recovered)
            XCTAssertEqual(try Data(contentsOf: url), bytes)
        }
        XCTAssertEqual(harness.healthStore.queriedSumIdentifiers.count, 1)
        let commits = await harness.api.commitCounts()
        XCTAssertEqual(commits["2026-03-15.json"], 1)
        XCTAssertNil(commits["2026-03-16.json"])
    }

    func testResidualRejectsChangedSettingsAndContradictoryCaptureEvidence() async throws {
        let harness = try Harness(existingAppend: true)
        defer { harness.cleanup() }
        let operationID = UUID()
        _ = await harness.export(operationID: operationID, profileID: nil, dates: harness.dates)
        harness.allowResidualCapture()
        var editedSnapshot = harness.snapshot
        editedSnapshot.filenameFormat = "edited-{date}"
        let blocked = await (try harness.service()).export(operationID: operationID, profileID: nil,
            destinationSnapshot: GoogleDriveDestinationSnapshot(destination: harness.destination), dates: [harness.dates[1]],
            healthKitManager: harness.healthManager, settingsSnapshot: editedSnapshot)
        XCTAssertEqual(blocked.successCount, 0)
        XCTAssertEqual(harness.healthStore.queriedSumIdentifiers.count, 1)

        let url = harness.root.appendingPathComponent("journals/\(operationID.uuidString.lowercased()).json")
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: url)) as? [String: Any])
        var evidence = try XCTUnwrap(object["captureEvidence"] as? [String: Any])
        evidence["completedDates"] = object["sourceDates"] // falsely claims the known query-failed B
        object["captureEvidence"] = evidence
        let bytes = try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
        try bytes.write(to: url, options: [.atomic])
        let invalid = await harness.export(operationID: operationID, profileID: nil, dates: harness.dates)
        XCTAssertEqual(invalid.successCount, 0)
        XCTAssertEqual(invalid.completedDates, [])
        XCTAssertEqual(try Data(contentsOf: url), bytes)
        XCTAssertEqual(harness.healthStore.queriedSumIdentifiers.count, 1)
        let commits = await harness.api.commitCounts()
        XCTAssertEqual(commits["2026-03-15.json"], 1)
        XCTAssertNil(commits["2026-03-16.json"])
    }

    private final class Harness {
        let root: URL
        let suiteName = "GoogleDriveCaptureRecoveryTests.\(UUID().uuidString)"
        let defaults: UserDefaults
        let healthStore = FakeHealthStore()
        let healthManager: HealthKitManager
        let settings: AdvancedExportSettings
        let snapshot: ExportSettingsSnapshot
        let destination: GoogleDriveDestination
        let api: SyntheticDriveAPI
        let credentials: GoogleDriveCredentialStore
        var calendar: Calendar {
            var value = Calendar(identifier: .gregorian)
            value.timeZone = TimeZone(identifier: "UTC")!
            return value
        }
        let dates = [Date(timeIntervalSince1970: 1_773_532_800), Date(timeIntervalSince1970: 1_773_619_200)]

        init(existingAppend: Bool) throws {
            root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
            defaults = UserDefaults(suiteName: suiteName)!
            settings = AdvancedExportSettings(userDefaults: defaults)
            settings.exportFormats = [.json]
            settings.includeGranularData = false
            settings.writeMode = .append
            settings.metricSelection.deselectAll()
            settings.metricSelection.enabledMetrics = ["steps"]
            snapshot = ExportSettingsSnapshot.from(settings, healthSubfolder: "Health",
                appleExportEngineAuthorityIsFrozen: true, calendarTimeZoneIdentifier: "UTC")
            healthManager = HealthKitManager(store: healthStore, userDefaults: defaults)
            destination = GoogleDriveDestination(credentialReferenceID: UUID(), accountPermissionID: "synthetic-permission",
                folderID: "folder", canAddChildren: true)
            api = SyntheticDriveAPI(destination: destination, existingAppend: existingAppend)
            credentials = GoogleDriveCredentialStore(keychain: DriveMemoryKeychain())
            try credentials.save(GoogleDriveTokenCredential(accessToken: "synthetic", refreshToken: "synthetic-refresh",
                expiresAt: .distantFuture, grantedScopes: [GoogleDriveConfiguration.driveFileScope]),
                referenceID: destination.credentialReferenceID)
            GoogleDriveDestinationStore(userDefaults: defaults).upsert(destination)
            if existingAppend {
                let managed = GoogleDriveManagedObjectStore(rootURL: root)
                try managed.upsert(GoogleDriveManagedObjectBinding(destinationID: destination.id,
                    relativePathHash: GoogleDrivePath.hash("Health"), objectID: "health-folder", parentID: "folder",
                    expectedName: "Health", mimeType: GoogleDriveFileMetadata.folderMIMEType))
                try managed.upsert(GoogleDriveManagedObjectBinding(destinationID: destination.id,
                    relativePathHash: GoogleDrivePath.hash("Health/2026-03-15.json"), objectID: "existing-first", parentID: "health-folder",
                    expectedName: "2026-03-15.json", mimeType: "application/json"))
            }
            // The SDK boundary succeeds for A then becomes unavailable for B. No HealthKit query
            // ever reaches a real store, and the actual exporter records the per-date failure.
            let store = healthStore
            store.querySumResult = { identifier, _ in
                guard identifier == .stepCount else { return nil }
                store.available = false
                return 100
            }
        }

        func allowResidualCapture() {
            healthStore.available = true
            healthStore.querySumResult = { identifier, _ in identifier == .stepCount ? 200 : nil }
        }

        func service() throws -> GoogleDriveExportService {
            let destinations = GoogleDriveDestinationStore(userDefaults: defaults)
            let connection = GoogleDriveConnectionManager(
                configuration: GoogleDriveConfiguration(clientID: "synthetic-public", redirectURI: "synthetic:/oauth"),
                destinationStore: destinations, credentialStore: credentials, api: api
            )
            return try GoogleDriveExportService(destinationStore: destinations, connectionManager: connection,
                runner: GoogleDriveDestinationRunner(api: api, managedStore: GoogleDriveManagedObjectStore(rootURL: root),
                    journalStore: GoogleDriveJournalStore(rootURL: root)))
        }

        func export(operationID: UUID, profileID: UUID?, dates: [Date]) async -> ExportOrchestrator.ExportResult {
            do {
                return await (try service()).export(operationID: operationID, profileID: profileID,
                    destinationSnapshot: GoogleDriveDestinationSnapshot(destination: destination), dates: dates,
                    healthKitManager: healthManager, settingsSnapshot: snapshot)
            } catch {
                XCTFail("Synthetic harness setup failed: \(error)")
                return ExportOrchestrator.ExportResult(successCount: 0, totalCount: dates.count, failedDateDetails: [], completedDates: [])
            }
        }

        func cleanup() {
            try? FileManager.default.removeItem(at: root)
            defaults.removePersistentDomain(forName: suiteName)
        }
    }
}

private actor SyntheticDriveAPI: GoogleDriveAPIClientProtocol {
    let destination: GoogleDriveDestination
    private var files: [String: GoogleDriveFileMetadata] = [:]
    private var contents: [String: Data] = [:]
    private var sessions: [URL: String] = [:]
    private var uploads: [(String, Data)] = []
    private var commits: [String: Int] = [:]
    private var interrupted = false
    private var serial = 0

    init(destination: GoogleDriveDestination, existingAppend: Bool) {
        self.destination = destination
        if existingAppend {
            files["health-folder"] = GoogleDriveFileMetadata(id: "health-folder", name: "Health",
                mimeType: GoogleDriveFileMetadata.folderMIMEType, parents: [destination.folderID], version: "1", trashed: false)
            let baseline = Data("synthetic-baseline\n".utf8)
            files["existing-first"] = GoogleDriveFileMetadata(id: "existing-first", name: "2026-03-15.json",
                mimeType: "application/json", parents: ["health-folder"], version: "1", size: UInt64(baseline.count),
                sha256Checksum: GoogleDriveDigest.sha256(baseline), trashed: false)
            contents["existing-first"] = baseline
        }
    }
    func interruptNextUpload() { interrupted = true }
    func commitCounts() -> [String: Int] { commits }
    func attempts(named name: String) -> [Data] { uploads.filter { $0.0 == name }.map { $0.1 } }
    func bytes(named name: String) throws -> Data {
        guard let id = files.values.first(where: { $0.name == name })?.id, let bytes = contents[id] else { throw GoogleDriveError(.folderUnavailable) }
        return bytes
    }
    func about(accessToken: String) async throws -> String { destination.accountPermissionID }
    func metadata(id: String, resourceKey: String?, accessToken: String) async throws -> GoogleDriveFileMetadata {
        guard let file = files[id], contents[id] != nil || file.mimeType == GoogleDriveFileMetadata.folderMIMEType else { throw GoogleDriveError(.folderUnavailable) }
        return file
    }
    func validateFolder(_ destination: GoogleDriveDestination, accessToken: String) async throws -> GoogleDriveFileMetadata {
        GoogleDriveFileMetadata(id: destination.folderID, name: "Synthetic", mimeType: GoogleDriveFileMetadata.folderMIMEType,
            parents: [], trashed: false, canAddChildren: true)
    }
    func generateIDs(count: Int, accessToken: String) async throws -> [String] {
        (0..<count).map { _ in serial += 1; return "reserved-\(serial)" }
    }
    func createFolder(id: String, name: String, parentID: String, pathHash: String, operationID: UUID, resourceKeys: [String: String], accessToken: String) async throws -> GoogleDriveFileMetadata {
        let metadata = GoogleDriveFileMetadata(id: id, name: name, mimeType: GoogleDriveFileMetadata.folderMIMEType,
            parents: [parentID], version: "1", trashed: false)
        files[id] = metadata
        return metadata
    }
    func findManagedObjects(parentID: String, name: String, pathHash: String, resourceKeys: [String: String], accessToken: String) async throws -> [GoogleDriveFileMetadata] {
        files.values.filter { $0.name == name && $0.parents == [parentID] }
    }
    func startResumableCreate(id: String, name: String, parentID: String, mediaType: String, byteCount: UInt64, sha256: String, pathHash: String, operationID: UUID, resourceKeys: [String: String], accessToken: String) async throws -> URL {
        files[id] = GoogleDriveFileMetadata(id: id, name: name, mimeType: mediaType, parents: [parentID], version: "0", trashed: false)
        return session(id: id)
    }
    func startResumableUpdate(id: String, mediaType: String, byteCount: UInt64, sha256: String, pathHash: String, operationID: UUID, resourceKeys: [String: String], accessToken: String) async throws -> URL { session(id: id) }
    private func session(id: String) -> URL {
        let url = URL(string: "https://www.googleapis.com/upload/\(id)")!
        sessions[url] = id
        return url
    }
    func upload(sessionURL: URL, data: Data, offset: UInt64, totalByteCount: UInt64, accessToken: String) async throws -> GoogleDriveUploadResponse {
        let id = sessions[sessionURL]!
        let old = files[id]!
        uploads.append((old.name, data))
        if interrupted { interrupted = false; throw GoogleDriveError(.ambiguousCommit) }
        let metadata = GoogleDriveFileMetadata(id: id, name: old.name, mimeType: old.mimeType, parents: old.parents,
            version: String((Int(old.version ?? "0") ?? 0) + 1), size: UInt64(data.count),
            sha256Checksum: GoogleDriveDigest.sha256(data), trashed: false)
        files[id] = metadata
        contents[id] = data
        commits[old.name, default: 0] += 1
        return .completed(metadata)
    }
    func uploadStatus(sessionURL: URL, totalByteCount: UInt64, accessToken: String) async throws -> GoogleDriveUploadResponse { .incomplete(acknowledgedByteCount: 0) }
    func download(id: String, resourceKey: String?, accessToken: String) async throws -> Data {
        guard let bytes = contents[id] else { throw GoogleDriveError(.folderUnavailable) }
        return bytes
    }
}

private struct SilentDriveNotifications: ExportNotificationScheduling {
    var fallbackDelay: TimeInterval { 60 }
    func schedulePendingExportNotification(for request: PendingExportRequest) async throws {}
    func sendImmediatePendingExportNotification(for request: PendingExportRequest) async throws {}
    func cancelPendingExportNotification(id: UUID) {}
}

private final class DriveMemoryKeychain: KeychainStoring, @unchecked Sendable {
    var values: [String: String] = [:]
    func readInt(key: String) -> Int { 0 }
    func writeInt(key: String, value: Int) {}
    func readString(key: String) -> String? { values[key] }
    func readStringOrThrow(key: String) throws -> String? { values[key] }
    func writeString(key: String, value: String) { values[key] = value }
    func writeStringOrThrow(key: String, value: String) throws { writeString(key: key, value: value) }
    func remove(key: String) { values.removeValue(forKey: key) }
    func removeOrThrow(key: String) throws { remove(key: key) }
}
