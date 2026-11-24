import Foundation
import HealthKit

/// Per-profile incremental export state on disk (Application Support, never synced).
///
/// `committed` is what the last successful run saved. A run stages its next state with
/// its pending request ID; only `commit(requestID:)` after that request completes makes
/// it the committed state, so a failed or interrupted run re-detects the same changes.
/// An unreadable file reads as no state, which makes the next run a full export.
struct IncrementalExportProfileRecord: Codable, Equatable {
    struct Staged: Codable, Equatable {
        let requestID: UUID
        let state: IncrementalExportCommittedState
        let summary: IncrementalRunSummary
    }

    var committed: IncrementalExportCommittedState?
    var staged: Staged?
    var lastSummary: IncrementalRunSummary?
}

final class IncrementalScheduledExportStore {
    private let directory: URL
    private let fileManager: FileManager

    static let defaultDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("IncrementalScheduledExport", isDirectory: true)
    }()

    init(directory: URL = IncrementalScheduledExportStore.defaultDirectory, fileManager: FileManager = .default) {
        self.directory = directory
        self.fileManager = fileManager
    }

    private func url(for profileID: UUID) -> URL {
        directory.appendingPathComponent("\(profileID.uuidString.lowercased()).json")
    }

    func record(for profileID: UUID) -> IncrementalExportProfileRecord {
        guard let data = try? Data(contentsOf: url(for: profileID)),
              let record = try? JSONDecoder().decode(IncrementalExportProfileRecord.self, from: data) else {
            return IncrementalExportProfileRecord()
        }
        // A state written by a future format is unusable: run a full export instead.
        var checked = record
        if let committed = record.committed,
           committed.version != IncrementalExportCommittedState.currentVersion
            || committed.fingerprint.version != IncrementalExportSettingsFingerprint.currentVersion {
            checked.committed = nil
        }
        return checked
    }

    func save(_ record: IncrementalExportProfileRecord, for profileID: UUID) throws {
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)
        let data = try JSONEncoder().encode(record)
        try data.write(to: url(for: profileID), options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
    }

    func stage(_ staged: IncrementalExportProfileRecord.Staged, for profileID: UUID) throws {
        var record = record(for: profileID)
        record.staged = staged
        try save(record, for: profileID)
    }

    /// Promotes the staged state when it belongs to `requestID`. Returns the summary.
    @discardableResult
    func commit(requestID: UUID, for profileID: UUID) throws -> IncrementalRunSummary? {
        var record = record(for: profileID)
        guard let staged = record.staged, staged.requestID == requestID else { return nil }
        record.committed = staged.state
        record.lastSummary = staged.summary
        record.staged = nil
        try save(record, for: profileID)
        return staged.summary
    }

    /// "Re-export everything": forget anchors and settings so the next run is full.
    func reset(profileID: UUID) throws {
        var record = record(for: profileID)
        record.committed = nil
        record.staged = nil
        try save(record, for: profileID)
    }

    func remove(profileID: UUID) {
        try? fileManager.removeItem(at: url(for: profileID))
    }
}

/// Source of HealthKit changes since saved anchors.
protocol IncrementalHealthChangeSource {
    /// HealthKit sample types a profile's enabled metrics read.
    func sampleTypeIdentifiers(for settings: ExportSettingsSnapshot) -> [String]
    /// One entry per type. A type without a usable anchor is queried over the window
    /// (`windowStart` onward) and reported with `startedWithoutAnchor`.
    func changes(
        typeIdentifiers: [String],
        anchors: [String: Data],
        windowStart: Date
    ) async throws -> [IncrementalTypeChanges]
}

/// `HKAnchoredObjectQuery` per sample type.
///
/// With a saved anchor the query has no predicate, so it reports every addition and
/// deletion since the anchor (the planner keeps those inside the window). Without one
/// it is limited to samples overlapping the window, which seeds the UUID-to-day index
/// that later deletions are resolved against.
final class HealthKitIncrementalChangeSource: IncrementalHealthChangeSource {
    private let store: HKHealthStore

    init(store: HKHealthStore = HKHealthStore()) {
        self.store = store
    }

    func sampleTypeIdentifiers(for settings: ExportSettingsSnapshot) -> [String] {
        let descriptors = HealthKitRecordCatalog.authorizationDescriptors(
            enabledMetricIDs: settings.metricSelection.enabledMetricIDs
        )
        let types = descriptors.compactMap { HealthKitRecordCatalog.resolveObjectType($0) as? HKSampleType }
        for type in types { resolvedTypes[type.identifier] = type }
        return Set(types.map(\.identifier))
            .subtracting(HealthKitRecordCatalog.clinicalTypeIdentifiers)
            .sorted()
    }

    func changes(
        typeIdentifiers: [String],
        anchors: [String: Data],
        windowStart: Date
    ) async throws -> [IncrementalTypeChanges] {
        let types = sampleTypes(for: typeIdentifiers)
        var results: [IncrementalTypeChanges] = []
        for type in types {
            try Task.checkCancellation()
            let anchor = anchors[type.identifier].flatMap(Self.unarchive)
            let predicate = anchor == nil
                ? HKQuery.predicateForSamples(withStart: windowStart, end: nil, options: [])
                : nil
            let (samples, deleted, newAnchor) = try await query(type: type, predicate: predicate, anchor: anchor)
            results.append(IncrementalTypeChanges(
                typeIdentifier: type.identifier,
                startedWithoutAnchor: anchor == nil,
                added: samples.map { IncrementalSampleChange(uuid: $0.uuid, startDate: $0.startDate, endDate: $0.endDate) },
                deletedUUIDs: deleted.map(\.uuid),
                newAnchor: newAnchor.flatMap(Self.archive)
            ))
        }
        return results
    }

    private func query(
        type: HKSampleType,
        predicate: NSPredicate?,
        anchor: HKQueryAnchor?
    ) async throws -> ([HKSample], [HKDeletedObject], HKQueryAnchor?) {
        try await withCheckedThrowingContinuation { continuation in
            let query = HKAnchoredObjectQuery(
                type: type,
                predicate: predicate,
                anchor: anchor,
                limit: HKObjectQueryNoLimit
            ) { _, samples, deleted, newAnchor, error in
                if let error {
                    continuation.resume(throwing: error)
                } else {
                    continuation.resume(returning: (samples ?? [], deleted ?? [], newAnchor))
                }
            }
            store.execute(query)
        }
    }

    /// Types resolved by `sampleTypeIdentifiers(for:)`, reused so the query runs on the
    /// exact catalog type (including deployment-guarded ones) instead of re-deriving it.
    private var resolvedTypes: [String: HKSampleType] = [:]

    private func sampleTypes(for identifiers: [String]) -> [HKSampleType] {
        identifiers.compactMap { identifier in
            if let type = resolvedTypes[identifier] { return type }
            if identifier == HKObjectType.workoutType().identifier { return HKObjectType.workoutType() }
            if let type = HKQuantityType.quantityType(forIdentifier: HKQuantityTypeIdentifier(rawValue: identifier)) {
                return type
            }
            return HKCategoryType.categoryType(forIdentifier: HKCategoryTypeIdentifier(rawValue: identifier))
        }
    }

    static func archive(_ anchor: HKQueryAnchor) -> Data? {
        try? NSKeyedArchiver.archivedData(withRootObject: anchor, requiringSecureCoding: true)
    }

    static func unarchive(_ data: Data) -> HKQueryAnchor? {
        try? NSKeyedUnarchiver.unarchivedObject(ofClass: HKQueryAnchor.self, from: data)
    }
}
