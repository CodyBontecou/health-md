import Foundation
import HealthMdConnectionCore
import Testing
@testable import HealthMd

@MainActor
struct AppleDirectArtifactRecoveryTests {
    // STATIC RETENTION JUSTIFICATION: Match the AdvancedExportSettings observation teardown
    // policy in docs/testing/lifecycle-audit.md; these synthetic settings have no live effects.
    private static var retainedSettings: [AdvancedExportSettings] = []

    @Test(arguments: ["artifact", "manifest", "partition", "missing", "foreign", "symlink", "truncated", "duplicate", "frontier", "segment", "chain"])
    func corruptedSuccessorCannotRecoverOrAcquireOwnership(damage: String) async throws {
        let (storage, directory, original) = try await fixture()
        defer { try? FileManager.default.removeItem(at: storage.support) }
        let artifact = directory.appendingPathComponent("generated/synthetic.json")
        let file = try #require(original.generatedFiles.first)
        let partition = try #require(original.partitions.first)
        var changed = original
        switch damage {
        case "artifact":
            var bytes = try Data(contentsOf: artifact)
            bytes[0] ^= 1
            try bytes.write(to: artifact)
        case "manifest":
            changed.generatedFiles = [IPhoneDirectGeneratedFile(manifest: try DirectExportFileManifest(
                jobID: file.manifest.jobID, fileID: file.manifest.fileID, relativePath: file.relativePath,
                byteCount: file.manifest.byteCount, sha256: String(repeating: "0", count: 64), writeMode: .overwrite),
                relativePath: file.relativePath)]
        case "partition":
            changed.partitions = [try DirectTransferPartition(index: 0, transferID: partition.transferID,
                sourceDates: partition.sourceDates, byteCount: partition.byteCount, chunkCount: partition.chunkCount,
                sha256: String(repeating: "0", count: 64), previousSHA256: nil, itemSegment: partition.itemSegment)]
        case "missing": try FileManager.default.removeItem(at: artifact)
        case "foreign":
            let outside = directory.deletingLastPathComponent().appendingPathComponent("retained.json")
            try Data(contentsOf: artifact).write(to: outside)
            changed.generatedFiles = [IPhoneDirectGeneratedFile(manifest: try DirectExportFileManifest(
                jobID: file.manifest.jobID, fileID: file.manifest.fileID, relativePath: "../../retained.json",
                byteCount: file.manifest.byteCount, sha256: file.manifest.sha256, writeMode: .overwrite),
                relativePath: "../../retained.json")]
        case "symlink":
            let outside = storage.support.appendingPathComponent("retained.json")
            try Data(contentsOf: artifact).write(to: outside)
            try FileManager.default.removeItem(at: artifact)
            try FileManager.default.createSymbolicLink(at: artifact, withDestinationURL: outside)
        case "truncated": changed.partitions = []
        case "duplicate": changed.generatedFiles += changed.generatedFiles
        case "frontier": changed.committedPartitionCount = 1
        case "segment", "chain": break // Corrupt decoded fields that validated initializers refuse.
        default: Issue.record("Unknown synthetic corruption")
        }
        let journalURL = directory.appendingPathComponent("journal.json")
        var bytes = try encode(changed)
        if damage == "segment" || damage == "chain" {
            var object = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            var partitions = try #require(object["partitions"] as? [[String: Any]])
            if damage == "segment" {
                var segment = try #require(partitions[0]["itemSegment"] as? [String: Any])
                segment["offset"] = 1
                partitions[0]["itemSegment"] = segment
            } else { partitions[0]["previousSHA256"] = String(repeating: "0", count: 64) }
            object["partitions"] = partitions
            bytes = try JSONSerialization.data(withJSONObject: object)
        }
        try bytes.write(to: journalURL)
        let retainedArtifact = try? Data(contentsOf: artifact)
        let retainedEntries = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        #expect(throws: AppleExportJournalRecovery.RecoveryError.self) {
            _ = try storage.loadGeneratedJournal(jobID: original.request.jobID)
        }
        #expect(try Data(contentsOf: journalURL) == bytes)
        #expect((try? Data(contentsOf: artifact)) == retainedArtifact)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == retainedEntries)
    }

    @Test(arguments: ["ready", "unpartitioned", "empty", "multiple", "partial", "committed", "historical"])
    func qualifiedRecoveryPreservesBytesAndStableOwnership(mode: String) async throws {
        let (storage, directory, original) = try await fixture(attribution: mode == "historical" ? .nightBegins : .morningEnds)
        defer { try? FileManager.default.removeItem(at: storage.support) }
        var journal = original
        let artifact = directory.appendingPathComponent("generated/synthetic.json")
        let fileID = try #require(journal.generatedFiles.first).manifest.fileID
        if mode == "unpartitioned" { journal.partitions = []; journal.state = "preparing" }
        if mode == "empty" || mode == "multiple" || mode == "partial" {
            let bytes = mode == "empty" ? Data() : Data(repeating: 65, count: 256 * 1024 + 17)
            try bytes.write(to: artifact)
            let manifest = try DirectExportFileManifest(jobID: journal.request.jobID, fileID: fileID,
                relativePath: "synthetic.json", byteCount: Int64(bytes.count), sha256: DirectTransferFile.sha256Hex(bytes), writeMode: .overwrite)
            journal.generatedFiles = [IPhoneDirectGeneratedFile(manifest: manifest, relativePath: manifest.relativePath)]
            journal.partitions = []
            if !bytes.isEmpty {
                var offset = 0
                var previous: String?
                for count in [128 * 1024 + 1, 128 * 1024 + 16] {
                    let sha = DirectTransferFile.sha256Hex(bytes.subdata(in: offset ..< offset + count))
                    journal.partitions.append(try DirectTransferPartition(index: journal.partitions.count, transferID: UUID(),
                        sourceDates: [fileID.uuidString.lowercased()], byteCount: Int64(count), chunkCount: 1,
                        sha256: sha, previousSHA256: previous, itemSegment: DirectTransferItemSegment(
                            itemID: fileID.uuidString.lowercased(), offset: Int64(offset), itemByteCount: Int64(bytes.count),
                            isFinalSegment: offset + count == bytes.count)))
                    previous = sha
                    offset += count
                }
            }
        }
        if mode == "partial" || mode == "committed" {
            journal.committedPartitionCount = 1
            journal.committedBytes = try #require(journal.partitions.first).byteCount
        }
        if mode == "historical" { try Data(repeating: 65, count: 42).write(to: artifact) }
        let journalURL = directory.appendingPathComponent("journal.json")
        let bytes = try encode(journal)
        try bytes.write(to: journalURL)
        let artifactBytes = try Data(contentsOf: artifact)
        let first = try #require(try storage.loadGeneratedJournal(jobID: journal.request.jobID))
        try first.checkpoint.validateGeneration(fileManager: .default)
        let entries = try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted()
        let marker = directory.appendingPathComponent(".journal-generation")
        let markerBytes = try Data(contentsOf: marker)
        let second = try #require(try storage.loadGeneratedJournal(jobID: journal.request.jobID))
        #expect(first.generatedFiles == second.generatedFiles)
        #expect(first.partitions == journal.partitions)
        #expect(try Data(contentsOf: journalURL) == bytes)
        #expect(try Data(contentsOf: artifact) == artifactBytes)
        #expect(try Data(contentsOf: marker) == markerBytes)
        #expect(try FileManager.default.contentsOfDirectory(atPath: directory.path).sorted() == entries)
    }

    #if os(iOS)
    @Test(arguments: ["valid-expired", "corrupt-expired", "corrupt-unexpired"])
    func actualCoordinatorExpiryRetainsCorruptSpoolsAndSkipsUnexpiredContent(mode: String) async throws {
        let (storage, directory, journal) = try await fixture(legacyProtocol: true)
        defer { try? FileManager.default.removeItem(at: storage.support) }
        let journalURL = directory.appendingPathComponent("journal.json")
        let bytes = try encode(journal)
        try bytes.write(to: journalURL)
        _ = try #require(try storage.loadGeneratedJournal(jobID: journal.request.jobID))
        let artifact = directory.appendingPathComponent("generated/synthetic.json")
        if mode != "valid-expired" {
            var changed = try Data(contentsOf: artifact)
            changed[0] ^= 1
            try changed.write(to: artifact)
        }
        let artifactBytes = try Data(contentsOf: artifact)
        let marker = directory.appendingPathComponent(".journal-generation")
        let markerBytes = try Data(contentsOf: marker)
        let manager = ArtifactRecoverySupportFileManager(support: storage.support)
        let coordinator = IPhoneDirectExportCoordinator(fileManager: manager,
            fileProducer: IPhoneDirectFileExportProducer(fileManager: manager))
        let now = journal.request.createdAt.addingTimeInterval(mode == "corrupt-unexpired" ? 0 : HealthMdDirectProtocol.jobLifetime + 1)
        coordinator.cleanupExpiredJobs(now: now)
        if mode == "valid-expired" {
            #expect(!FileManager.default.fileExists(atPath: directory.path))
        } else {
            #expect(try Data(contentsOf: journalURL) == bytes)
            #expect(try Data(contentsOf: artifact) == artifactBytes)
            #expect(try Data(contentsOf: marker) == markerBytes)
        }
        #expect(mode == "corrupt-unexpired" ? manager.artifactInspections == 0 : manager.artifactInspections >= 2)
    }
    #endif

    private func fixture(attribution: SleepDayAttribution = .morningEnds, legacyProtocol: Bool = false) async throws -> (AppleDirectJobStorage, URL, IPhoneDirectFileJournal) {
        let support = FileManager.default.temporaryDirectory.appendingPathComponent("synthetic-direct-artifacts-\(UUID())")
        try FileManager.default.createDirectory(at: support, withIntermediateDirectories: true)
        var ready = false
        defer { if !ready { try? FileManager.default.removeItem(at: support) } }
        let storage = AppleDirectJobStorage(support: support.standardizedFileURL.resolvingSymlinksInPath(), fileManager: .default)
        let id = UUID()
        let base = try IPhoneDirectFileJournalTests.makeJournal(jobID: id)
        let suite = "AppleDirectArtifactRecoveryTests.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.exportFormats = [.json]
        settings.writeMode = .overwrite
        settings.archiveExportFiles = false
        settings.summaryOnlyExport = false
        settings.includeGranularData = false
        settings.generateRangeSummary = false
        settings.dailyNoteInjection.enabled = false
        settings.individualTracking.globalEnabled = false
        settings.metricSelection.enabledMetrics = ["sleep_total"]
        settings.executionSleepCaptureContext = AppleSleepCaptureContext(
            timeZone: try #require(TimeZone(identifier: "America/Los_Angeles")), sleepDayAttribution: attribution)
        settings.executionSleepCaptureContextIsFrozen = true
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(settings, healthSubfolder: "Health",
            surface: .localVaultWithoutSideEffects,
            policyResolver: AppleExportEnginePolicyResolver(injectedOverride: "legacy", userDefaults: nil, environment: [:]))
        if attribution == .morningEnds { #expect(try #require(snapshot.appleExportEnginePin).isWakeDate) }
        let directory = try storage.prepareDirectory(jobID: id, kind: .files, snapshot: snapshot).1
        let staging = directory.appendingPathComponent("generated", isDirectory: true)
        try FileManager.default.createDirectory(at: staging, withIntermediateDirectories: true)
        let bytes = Data("{\"sleep\":{\"totalDuration\":7201.728395064}}".utf8)
        try bytes.write(to: staging.appendingPathComponent("synthetic.json"))
        let fileID = UUID()
        let manifest = try DirectExportFileManifest(jobID: id, fileID: fileID, relativePath: "synthetic.json",
            byteCount: Int64(bytes.count), sha256: DirectTransferFile.sha256Hex(bytes), writeMode: .overwrite)
        let partition = try DirectTransferPartition(index: 0, transferID: UUID(), sourceDates: [fileID.uuidString.lowercased()],
            byteCount: Int64(bytes.count), chunkCount: 1, sha256: manifest.sha256, previousSHA256: nil,
            itemSegment: DirectTransferItemSegment(itemID: fileID.uuidString.lowercased(), offset: 0,
                itemByteCount: Int64(bytes.count), isFinalSegment: true))
        let journal = IPhoneDirectFileJournal(request: base.request, accepted: base.accepted, session: base.session,
            settingsSnapshot: snapshot, appleExportEnginePin: snapshot.appleExportEnginePin,
            appleDirectProtocolPin: legacyProtocol ? nil : base.appleDirectProtocolPin, healthSubfolder: base.healthSubfolder,
            requestedDates: base.requestedDates, transferDates: base.transferDates, capturedDays: [],
            generatedFiles: [IPhoneDirectGeneratedFile(manifest: manifest, relativePath: manifest.relativePath)],
            partitions: [partition], committedPartitionCount: 0, committedBytes: 0,
            generationCompleted: true, state: "transferring", completionRecorded: false, updatedAt: base.updatedAt)
        ready = true
        return (storage, directory, journal)
    }

    private func encode(_ journal: IPhoneDirectFileJournal) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.userInfo[ExportSettingsSnapshot.durableSleepContextEncoding] = true
        return try encoder.encode(journal)
    }
}

#if os(iOS)
nonisolated private final class ArtifactRecoverySupportFileManager: FileManager, @unchecked Sendable {
    let support: URL
    private let inspectionLock = NSLock()
    private var inspectionCount = 0
    var artifactInspections: Int { inspectionLock.withLock { inspectionCount } }
    init(support: URL) { self.support = support; super.init() }
    override func url(for directory: SearchPathDirectory, in domain: SearchPathDomainMask,
                      appropriateFor url: URL?, create shouldCreate: Bool) throws -> URL {
        guard directory == .applicationSupportDirectory else { throw CocoaError(.fileReadNoSuchFile) }
        return support
    }
    override func attributesOfItem(atPath path: String) throws -> [FileAttributeKey: Any] {
        if path.contains("/generated") { inspectionLock.withLock { inspectionCount += 1 } }
        return try super.attributesOfItem(atPath: path)
    }
}
#endif
