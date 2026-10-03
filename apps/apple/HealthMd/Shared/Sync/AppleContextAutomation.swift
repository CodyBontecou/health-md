import Darwin
import Foundation

/// Apple Sync extension v1; not an export, direct-CLI, or Shared Setup grammar.
/// Only the authenticated Manual IP v2 transport can negotiate this family.
enum AppleContextMessage: Codable {
    case refresh(AppleContextRequest)
    case status(AppleContextRequest)
    case receipt(AppleContextReceipt)
}

struct AppleContextRequest: Codable, Equatable {
    let version: Int
    let id: UUID
    let phoneInstallationID: UUID
    let macInstallationID: UUID
    let profileID: UUID
    let ownerDates: [String]
    let timeZoneIdentifier: String
    let startDate: Date
    let endDate: Date
    let selection: CanonicalHealthDataSelection

    init(id: UUID = UUID(), phoneInstallationID: UUID, macInstallationID: UUID,
         profileID: UUID, ownerDates: [String], timeZoneIdentifier: String,
         startDate: Date, endDate: Date, selection: CanonicalHealthDataSelection) {
        version = 1
        self.id = id
        self.phoneInstallationID = phoneInstallationID
        self.macInstallationID = macInstallationID
        self.profileID = profileID
        self.ownerDates = ownerDates
        self.timeZoneIdentifier = timeZoneIdentifier
        self.startDate = startDate
        self.endDate = endDate
        self.selection = selection
    }

    private enum CodingKeys: String, CodingKey, CaseIterable {
        case version, id, phoneInstallationID, macInstallationID, profileID
        case ownerDates, timeZoneIdentifier, startDate, endDate, selection
    }
    private struct Key: CodingKey {
        var stringValue: String
        var intValue: Int? { nil }
        init?(stringValue: String) { self.stringValue = stringValue }
        init?(intValue: Int) { return nil }
    }
    init(from decoder: Decoder) throws {
        let keys = try decoder.container(keyedBy: Key.self)
        guard Set(keys.allKeys.map(\.stringValue)).isSubset(of: Set(CodingKeys.allCases.map(\.rawValue))) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown context request field"))
        }
        let c = try decoder.container(keyedBy: CodingKeys.self)
        version = try c.decode(Int.self, forKey: .version)
        id = try c.decode(UUID.self, forKey: .id)
        phoneInstallationID = try c.decode(UUID.self, forKey: .phoneInstallationID)
        macInstallationID = try c.decode(UUID.self, forKey: .macInstallationID)
        profileID = try c.decode(UUID.self, forKey: .profileID)
        ownerDates = try c.decode([String].self, forKey: .ownerDates)
        timeZoneIdentifier = try c.decode(String.self, forKey: .timeZoneIdentifier)
        startDate = try c.decode(Date.self, forKey: .startDate)
        endDate = try c.decode(Date.self, forKey: .endDate)
        let selectionKeys = try c.nestedContainer(keyedBy: Key.self, forKey: .selection)
        guard Set(selectionKeys.allKeys.map(\.stringValue)).isSubset(of:
            ["metric_ids", "source_ids", "detail_level", "object_paths", "field_pointers"]) else {
            throw DecodingError.dataCorrupted(.init(codingPath: decoder.codingPath, debugDescription: "Unknown context selection field"))
        }
        selection = try c.decode(CanonicalHealthDataSelection.self, forKey: .selection)
    }

    var isValid: Bool {
        guard version == 1, let zone = TimeZone(identifier: timeZoneIdentifier),
              !ownerDates.isEmpty, ownerDates == Array(Set(ownerDates)).sorted(),
              !selection.metricIDs.isEmpty, selection.metricIDs == Array(Set(selection.metricIDs)).sorted(),
              selection.metricIDs.allSatisfy(HealthMetrics.availableMetricIDsInCurrentBuild.contains),
              selection.sourceIDs == ["apple_health"],
              selection.objectPaths.isEmpty, selection.fieldPointers.isEmpty else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let formatter = Self.formatter(zone: zone)
        let dates = ownerDates.compactMap { formatter.date(from: $0) }
        guard dates.count == ownerDates.count, dates.map({ formatter.string(from: $0) }) == ownerDates,
              dates.first == startDate, dates.last == endDate else { return false }
        return ExportOrchestrator.dateRange(from: startDate, to: endDate, calendar: calendar) == dates
    }

    static func formatter(zone: TimeZone) -> DateFormatter {
        let f = DateFormatter()
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        f.calendar = calendar
        f.timeZone = zone
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.isLenient = false
        return f
    }

    func matches(_ manifest: ConnectedCorpusExportManifest) -> Bool {
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { return false }
        let dates = ownerDates.compactMap { Self.formatter(zone: zone).date(from: $0) }
        return manifest.mode == .encryptedContext && manifest.rawProfile == nil && manifest.requestedTarget == nil
            && manifest.sourceTimeZoneIdentifier == timeZoneIdentifier
            && manifest.settingsSnapshot.calendarTimeZoneIdentifier == timeZoneIdentifier
            && manifest.originalCalendarTimeZoneIdentifier == timeZoneIdentifier
            && manifest.dateRangeStart == startDate && manifest.dateRangeEnd == endDate
            && manifest.requestedDateIdentifiers == ownerDates && manifest.requestedDates == dates
            && manifest.originalRequestedDates == dates && manifest.transferDates == dates
            && manifest.canonicalSelection == selection && manifest.selectedSourceIDs == selection.sourceIDs
            && manifest.settingsSnapshot.metricSelection.enabledMetricIDs == Set(selection.metricIDs)
            && manifest.settingsSnapshot.detailPolicy == (selection.detailLevel == .lossless ? .lossless : .summary)
    }

    func matches(_ request: IPhoneExportRequest) -> Bool {
        request.jobID == id && request.responseMode == .contextStore
            && request.dateSelection == .explicitRange && request.requestedBy == .cli
            && request.settingsPolicy == .requestedDatesOnly && request.rawProfile == nil
            && request.dateRangeStart == startDate && request.dateRangeEnd == endDate
            && request.requestedDateIdentifiers == ownerDates && request.canonicalSelection == selection
    }
}

struct AppleContextReceipt: Codable, Equatable {
    enum State: String, Codable {
        case pending, completed, partial, failed, locked, unavailable, incompatible
        var isTerminal: Bool { self == .completed || self == .partial || self == .failed }
    }
    let request: AppleContextRequest
    let revision: UInt64
    let state: State
}

/// Shared durable identity journal. No payloads, destinations, or access tokens.
/// Errors are surfaced; neither send nor acknowledgement may follow a failed write.
@MainActor
final class AppleContextJournal {
    struct Record: Codable, Equatable {
        let request: AppleContextRequest
        var receipt: AppleContextReceipt?
        var jobWasAdmitted = false
    }
    private let root: URL
    private var records: [UUID: Record] = [:]
    #if DEBUG
    var failWritesForTesting = false
    #endif

    init(root: URL) {
        self.root = root
        reload()
    }

    private func reload() {
        if let files = try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil) {
            for file in files where file.pathExtension == "json" {
                if let data = try? Data(contentsOf: file),
                   let record = try? JSONDecoder().decode(Record.self, from: data),
                   file.lastPathComponent == record.request.id.uuidString + ".json", record.request.isValid,
                   record.receipt == nil || record.receipt?.request == record.request {
                    records[record.request.id] = record
                }
            }
        }
    }

    static func productionRoot(_ name: String) -> URL {
        // No temporary-storage fallback in production. Failure to create/access
        // Application Support must prevent sending, not create an ephemeral job.
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Health.md", isDirectory: true)
            .appendingPathComponent(name, isDirectory: true)
    }

    var allRecords: [Record] { reload(); return Array(records.values) }
    func record(_ id: UUID) -> Record? { reload(); return records[id] }

    func admit(_ request: AppleContextRequest) throws {
        guard request.isValid else { throw Failure.invalidScope }
        if let existing = record(request.id) {
            guard existing.request == request else { throw Failure.changedIdentity }
            return
        }
        guard !FileManager.default.fileExists(atPath: root.appendingPathComponent(request.id.uuidString + ".json").path) else {
            throw Failure.persistence // unreadable/corrupt identity is never overwritten
        }
        let record = Record(request: request, receipt: nil)
        try persist(record)
        records[request.id] = record
    }

    func markJobAdmitted(_ id: UUID) throws {
        guard var record = records[id] else { throw Failure.changedIdentity }
        if record.jobWasAdmitted { return }
        record.jobWasAdmitted = true
        try persist(record)
        records[id] = record
    }

    @discardableResult
    func accept(_ receipt: AppleContextReceipt, authenticatedPeer: UUID, localID: UUID, onPhone: Bool) throws -> Bool {
        let request = receipt.request
        guard onPhone ? (request.macInstallationID == authenticatedPeer && request.phoneInstallationID == localID)
                : (request.phoneInstallationID == authenticatedPeer && request.macInstallationID == localID),
              var record = records[request.id], record.request == request else { return false }
        if let previous = record.receipt {
            guard !previous.state.isTerminal, receipt.revision > previous.revision else { return false }
        }
        record.receipt = receipt
        try persist(record)
        records[request.id] = record
        return true
    }

    private func persist(_ record: Record) throws {
        #if DEBUG
        if failWritesForTesting { throw Failure.persistence }
        #endif
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let url = root.appendingPathComponent(record.request.id.uuidString + ".json")
        #if os(iOS)
        try JSONEncoder().encode(record).write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try JSONEncoder().encode(record).write(to: url, options: .atomic)
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        try handle.synchronize()
        let directory = Darwin.open(root.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard directory >= 0 else { throw Failure.persistence }
        defer { Darwin.close(directory) }
        guard Darwin.fsync(directory) == 0 else { throw Failure.persistence }
        let parent = Darwin.open(root.deletingLastPathComponent().path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard parent >= 0 else { throw Failure.persistence }
        defer { Darwin.close(parent) }
        guard Darwin.fsync(parent) == 0 else { throw Failure.persistence }
    }

    enum Failure: Error { case invalidScope, changedIdentity, persistence }
}
