import Foundation
#if canImport(Darwin)
import Darwin
#else
import Glibc
#endif

nonisolated struct ReceiverCoverageConfiguration: Codable, Equatable, Sendable {
    let preflightURL: String
    let scopeID: String
    let refreshRecentDays: Int
    static let warning = "Already retained completed days may be skipped. Late source updates outside the correction window will not be resent automatically. Use full lookback or a manual re-export to refresh older snapshots."
}

/// Atomic, flushed local metadata. Credentials and installation keys never enter these files.
nonisolated enum ReceiverCoverageAtomicFile {
    static func write(_ data: Data, to url: URL) throws {
        try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
        #if os(iOS)
        try data.write(to: url, options: [.atomic, .completeFileProtectionUntilFirstUserAuthentication])
        #else
        try data.write(to: url, options: .atomic)
        #endif
        let file = try FileHandle(forWritingTo: url)
        defer { try? file.close() }
        try file.synchronize()
        let fd = open(url.deletingLastPathComponent().path, O_RDONLY)
        guard fd >= 0 else { throw ReceiverCoveragePreflight.BoundaryError.invalidOccurrence }
        defer { _ = close(fd) }
        guard fsync(fd) == 0 else { throw ReceiverCoveragePreflight.BoundaryError.invalidOccurrence }
    }
}

/// One file per native occurrence. The provisional full plan is committed BEFORE HTTP: if the
/// process dies/cancels then, recovery fixes that conservative plan without another preflight.
nonisolated final class ReceiverCoverageJournal: @unchecked Sendable {
    private struct Envelope: Codable {
        let version: Int
        let authority: String
        var preflightPending: Bool
        var plan: String
    }
    private static let lock = NSRecursiveLock()
    private let directory: URL
    init(directory: URL) { self.directory = directory }
    private func url(_ id: String) throws -> URL {
        guard id.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { throw ReceiverCoveragePreflight.BoundaryError.invalidOccurrence }
        return directory.appendingPathComponent(id + ".json")
    }
    private func load(_ id: String) throws -> Envelope? {
        let path = try url(id)
        guard FileManager.default.fileExists(atPath: path.path) else { return nil }
        let data = try Data(contentsOf: path)
        guard data.count <= 128 * 1024 else { throw ReceiverCoveragePreflight.BoundaryError.invalidOccurrence }
        let record = try JSONDecoder().decode(Envelope.self, from: data)
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        guard record.version == 1, try encoder.encode(record) == data else { throw ReceiverCoveragePreflight.BoundaryError.invalidOccurrence }
        return record
    }
    private func save(_ value: Envelope, id: String) throws {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try ReceiverCoverageAtomicFile.write(encoder.encode(value), to: url(id))
    }
    func exists(_ id: String) throws -> Bool { Self.lock.lock(); defer { Self.lock.unlock() }; return try load(id) != nil }

    private func admit(id: String, authority: String, fallback: ReceiverCoveragePlan) throws -> (ReceiverCoveragePlan, Bool) {
        Self.lock.lock(); defer { Self.lock.unlock() }
        if var existing = try load(id) {
            guard existing.authority == authority else { throw ReceiverCoveragePreflight.BoundaryError.destinationChanged }
            let plan = try ReceiverCoveragePlan.restore(existing.plan, binding: fallback.destinationBinding)
            if existing.preflightPending { existing.preflightPending = false; try save(existing, id: id) }
            return (plan, false)
        }
        try save(Envelope(version: 1, authority: authority, preflightPending: true, plan: fallback.json()), id: id)
        return (fallback, true)
    }
    private func commit(id: String, authority: String, fallback: ReceiverCoveragePlan, chosen: ReceiverCoveragePlan) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard let existing = try load(id), existing.authority == authority,
              existing.preflightPending, existing.plan == (try fallback.json()) else { throw ReceiverCoveragePreflight.BoundaryError.invalidOccurrence }
        try save(Envelope(version: 1, authority: authority, preflightPending: false, plan: chosen.json()), id: id)
    }

    func resolve(id: String, authority: String, preflight: ReceiverCoveragePreflight, candidates: [String], now: Date,
                 todayRefresh: Bool, authorized: @Sendable () async -> Bool,
                 query: @Sendable (ReceiverCoverageRequest) async throws -> ReceiverCoverageOutcome = { try await ReceiverCoverageHTTPClient().query($0) }) async throws -> ReceiverCoveragePlan {
        // Existing plans are restored before consulting today's clock/candidates or the receiver.
        if let plan = try restore(id: id, authority: authority, binding: preflight.destinationBinding) { return plan }
        let today = ReceiverCoveragePlan.label(now, zone: preflight.calendarTimeZone)
        let requestID = UUID().uuidString.lowercased()
        let fallback = try ReceiverCoveragePlan.select(requestID: requestID, scopeID: preflight.scopeID,
            zone: preflight.calendarTimeZoneIdentifier, candidates: candidates, today: today, binding: preflight.destinationBinding,
            refreshRecentDays: preflight.refreshRecentDays, todayRefresh: todayRefresh, outcome: .fallbackFull)
        let (plan, fresh) = try admit(id: id, authority: authority, fallback: fallback)
        guard fresh else { return plan }
        try Task.checkCancellation()
        guard await authorized() else { throw CancellationError() }
        let request = try preflight.freezeRequest(requestID: requestID, candidates: candidates, now: now)
        let outcome = try await query(request)
        try Task.checkCancellation()
        guard await authorized() else { throw CancellationError() }
        let chosen = try ReceiverCoveragePlan.select(requestID: requestID, scopeID: preflight.scopeID,
            zone: preflight.calendarTimeZoneIdentifier, candidates: candidates, today: today, binding: preflight.destinationBinding,
            refreshRecentDays: preflight.refreshRecentDays, todayRefresh: todayRefresh, outcome: outcome)
        try commit(id: id, authority: authority, fallback: fallback, chosen: chosen)
        return chosen
    }
    func restore(id: String, authority: String, binding: String) throws -> ReceiverCoveragePlan? {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard var existing = try load(id) else { return nil }
        guard existing.authority == authority else { throw ReceiverCoveragePreflight.BoundaryError.destinationChanged }
        let plan = try ReceiverCoveragePlan.restore(existing.plan, binding: binding)
        if existing.preflightPending { existing.preflightPending = false; try save(existing, id: id) }
        return plan
    }
    func acknowledge(id: String, authority: String, binding: String, dates: [String]) throws {
        Self.lock.lock(); defer { Self.lock.unlock() }
        guard var value = try load(id), value.authority == authority, !value.preflightPending else { throw ReceiverCoveragePreflight.BoundaryError.invalidOccurrence }
        let plan = try ReceiverCoveragePlan.restore(value.plan, binding: binding).acknowledging(dates)
        value.plan = try plan.json()
        try save(value, id: id)
    }
}
