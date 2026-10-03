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
    /// A durable marker precedes replacement of the authority file. Its previous
    /// record was proven before this transaction; its candidate is NEVER authority
    /// while the marker exists, including on restart and after post-write errors.
    private struct Transaction: Codable {
        let version: Int
        let previous: Record?
        let candidate: Record
    }
    private let root: URL
    private var records: [UUID: Record] = [:]
    private var transactions: [UUID: Transaction] = [:]
    private var uncertain: Set<UUID> = []
    private var knownIDs: Set<UUID> = []
    private var directoryReadFailed = false
    #if DEBUG
    enum WriteFailurePoint: Equatable { case afterFinalAtomicWrite, finalFileSync, afterFinalDirectorySync }
    var failWritesForTesting = false
    var writeFailurePointForTesting: WriteFailurePoint?
    var failFinalWriteNumberForTesting: Int?
    private var finalWriteAttempts = 0
    #endif

    init(root: URL) {
        self.root = root
        reload()
    }

    private func valid(_ record: Record) -> Bool {
        record.request.isValid && (record.receipt == nil ||
            (record.receipt?.request == record.request && record.receipt?.version == 1 && (record.receipt?.revision ?? 0) > 0))
    }

    private func valid(_ transaction: Transaction, id: UUID) -> Bool {
        guard transaction.version == 1, transaction.candidate.request.id == id,
              valid(transaction.candidate) else { return false }
        guard let previous = transaction.previous else { return true }
        guard valid(previous), previous.request == transaction.candidate.request,
              !previous.jobWasAdmitted || transaction.candidate.jobWasAdmitted else { return false }
        if let receipt = previous.receipt {
            guard let next = transaction.candidate.receipt,
                  next.revision >= receipt.revision else { return false }
            if receipt.state.isTerminal || next.revision == receipt.revision { return next == receipt }
        }
        return true
    }

    private func authorityURL(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".json") }
    private func markerURL(_ id: UUID) -> URL { root.appendingPathComponent(id.uuidString + ".pending.json") }

    private func reload() {
        let files: [URL]
        do {
            files = try FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: nil)
            directoryReadFailed = false
        } catch {
            let failure = error as NSError
            // Only an explicit ENOENT-style result, with no previously observed
            // identities, is a first-run absence. Permission/corruption errors
            // are never treated as an empty journal or a replacement opportunity.
            let absent = failure.domain == NSCocoaErrorDomain &&
                (failure.code == CocoaError.fileReadNoSuchFile.rawValue || failure.code == CocoaError.fileNoSuchFile.rawValue)
            directoryReadFailed = !absent || !knownIDs.isEmpty || !records.isEmpty
            return
        }
        var finalFiles: [UUID: URL] = [:]
        var markers: [UUID: URL] = [:]
        for file in files where file.pathExtension == "json" {
            if file.lastPathComponent.hasSuffix(".pending.json"),
               let id = UUID(uuidString: file.deletingPathExtension().deletingPathExtension().lastPathComponent) {
                markers[id] = file
            } else if let id = UUID(uuidString: file.deletingPathExtension().lastPathComponent) {
                finalFiles[id] = file
            }
        }
        knownIDs.formUnion(finalFiles.keys)
        knownIDs.formUnion(markers.keys)
        uncertain = []
        transactions = [:]
        for id in knownIDs {
            if let marker = markers[id] {
                uncertain.insert(id)
                do {
                    let transaction = try JSONDecoder().decode(Transaction.self, from: Data(contentsOf: marker))
                    guard valid(transaction, id: id) else { throw Failure.persistence }
                    transactions[id] = transaction
                    if let previous = transaction.previous { records[id] = previous }
                    // Never adopt the final candidate, even if it decodes cleanly.
                } catch {
                    // Retain any already-proven memory record, but block dispatch
                    // and repair of unreadable/corrupt transactions. No overwrite.
                }
            } else if let file = finalFiles[id] {
                do {
                    let record = try JSONDecoder().decode(Record.self, from: Data(contentsOf: file))
                    guard valid(record), record.request.id == id else { throw Failure.persistence }
                    records[id] = record
                } catch { uncertain.insert(id) }
            } else { uncertain.insert(id) } // observed authority disappeared
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
    /// Health-free identifiers may be offered for explicit recovery, never used
    /// as admitted scope or a completed receipt by lookup/query alone.
    var recoverableIDs: [UUID] { reload(); return Array(Set(records.keys).union(transactions.keys)) }
    func record(_ id: UUID) -> Record? { reload(); return records[id] }
    func recoveryRequest(_ id: UUID) -> AppleContextRequest? { reload(); return transactions[id]?.candidate.request ?? records[id]?.request }
    func hasUncertainAuthority(_ id: UUID) -> Bool { reload(); return directoryReadFailed || uncertain.contains(id) }
    func isKnown(_ id: UUID) -> Bool { reload(); return knownIDs.contains(id) || records[id] != nil }

    /// One explicit, bounded retry of the ORIGINAL transaction, not a reload
    /// side effect. No new identity, profile resolution, receipt, or fallback.
    @discardableResult
    func retryDurability(_ id: UUID, expectedRequest: AppleContextRequest) throws -> Bool {
        reload()
        guard !directoryReadFailed else { throw Failure.persistence }
        guard uncertain.contains(id) else { return false }
        guard let transaction = transactions[id], transaction.candidate.request == expectedRequest else {
            throw Failure.changedIdentity
        }
        try finish(transaction)
        records[id] = transaction.candidate
        uncertain.remove(id)
        transactions[id] = nil
        return true
    }

    func admit(_ request: AppleContextRequest) throws {
        guard request.isValid else { throw Failure.invalidScope }
        reload()
        guard !directoryReadFailed, !uncertain.contains(request.id) else { throw Failure.persistence }
        if let existing = records[request.id] {
            guard existing.request == request else { throw Failure.changedIdentity }
            return
        }
        guard !knownIDs.contains(request.id) else { throw Failure.persistence }
        let record = Record(request: request, receipt: nil)
        try persist(record)
        records[request.id] = record
    }

    func markJobAdmitted(_ id: UUID) throws {
        reload()
        guard !directoryReadFailed, !uncertain.contains(id) else { throw Failure.persistence }
        guard var record = records[id] else { throw Failure.changedIdentity }
        if record.jobWasAdmitted { return }
        record.jobWasAdmitted = true
        try persist(record)
        records[id] = record
    }

    @discardableResult
    func accept(_ receipt: AppleContextReceipt, authenticatedPeer: UUID, localID: UUID, onPhone: Bool) throws -> Bool {
        let request = receipt.request
        reload()
        guard !directoryReadFailed, !uncertain.contains(request.id) else { throw Failure.persistence }
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
        guard !directoryReadFailed, !uncertain.contains(record.request.id) else { throw Failure.persistence }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true,
                                               attributes: [.posixPermissions: 0o700])
        let transaction = Transaction(version: 1, previous: records[record.request.id], candidate: record)
        guard valid(transaction, id: record.request.id) else { throw Failure.changedIdentity }
        // The marker and preserved previous authority are synchronized BEFORE
        // touching the final file. A marker-write failure never changes final.
        try writeAndSynchronize(try JSONEncoder().encode(transaction), to: markerURL(record.request.id), isFinal: false)
        knownIDs.insert(record.request.id)
        uncertain.insert(record.request.id)
        transactions[record.request.id] = transaction
        try finish(transaction)
        uncertain.remove(record.request.id)
        transactions[record.request.id] = nil
    }

    private func finish(_ transaction: Transaction) throws {
        #if DEBUG
        if failWritesForTesting { throw Failure.persistence }
        #endif
        let id = transaction.candidate.request.id
        try writeAndSynchronize(try JSONEncoder().encode(transaction.candidate), to: authorityURL(id), isFinal: true)
        // This is the commit point: final data AND its namespace are already
        // durable. unlink must succeed; nothing throwable occurs after it. The
        // unlink is intentionally not another durability dependency: if a crash
        // resurrects the marker, recovery conservatively requires explicit retry.
        guard Darwin.unlink(markerURL(id).path) == 0 else { throw Failure.persistence }
    }

    private func writeAndSynchronize(_ data: Data, to url: URL, isFinal: Bool) throws {
        #if DEBUG
        if isFinal { finalWriteAttempts += 1 }
        let injectFailure = isFinal && (failFinalWriteNumberForTesting == nil || failFinalWriteNumberForTesting == finalWriteAttempts)
        #endif
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        #if DEBUG
        if injectFailure && writeFailurePointForTesting == .afterFinalAtomicWrite { throw Failure.persistence }
        #endif
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        #if DEBUG
        if injectFailure && writeFailurePointForTesting == .finalFileSync { throw Failure.persistence }
        #endif
        try handle.synchronize()
        try handle.close()
        // Also cover a newly-created Health.md/temporary parent entry.
        for directory in [root, root.deletingLastPathComponent(), root.deletingLastPathComponent().deletingLastPathComponent()] {
            let descriptor = Darwin.open(directory.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw Failure.persistence }
            let result = Darwin.fsync(descriptor)
            Darwin.close(descriptor)
            guard result == 0 else { throw Failure.persistence }
        }
        #if DEBUG
        if injectFailure && writeFailurePointForTesting == .afterFinalDirectorySync { throw Failure.persistence }
        #endif
    }

    enum Failure: Error { case invalidScope, changedIdentity, persistence }
}
