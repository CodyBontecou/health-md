import CryptoKit
import Foundation
#if canImport(Darwin)
import Darwin
#endif

/// Native-local records only. No credential, health payload or externally supplied URL is stored.
struct ClinicRefreshRequest: Codable, Equatable, Sendable {
    let requestID: String
    let subjectID: String
    let deviceID: String
    let connectionID: String
    let profileID: String
    let revision: String
    let start: Date
    let end: Date
    let expiresAt: Date
    /// Explicit patient-approved owner-day interval. Nil retains exact timestamp semantics.
    let ownerDayZone: String?
    init(requestID: String, subjectID: String, deviceID: String, connectionID: String, profileID: String,
         revision: String, start: Date, end: Date, expiresAt: Date, ownerDayZone: String? = nil) {
        self.requestID = requestID; self.subjectID = subjectID; self.deviceID = deviceID; self.connectionID = connectionID
        self.profileID = profileID; self.revision = revision; self.start = start; self.end = end
        self.expiresAt = expiresAt; self.ownerDayZone = ownerDayZone
    }

    func validate(now: Date) throws {
        guard [requestID, subjectID, deviceID, connectionID, profileID, revision].allSatisfy({
            !$0.isEmpty && $0.utf8.count <= 200 && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) })
        }), start < end, start <= now, expiresAt > now else { throw ClinicNativeError.unavailable }
        if let ownerDayZone {
            guard !ownerDayZone.isEmpty, ownerDayZone.utf8.count <= 100, let zone = TimeZone(identifier: ownerDayZone) else { throw ClinicNativeError.unavailable }
            var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
            guard calendar.startOfDay(for: start) == start, calendar.startOfDay(for: end) == end,
                  let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now)), end <= tomorrow,
                  let days = calendar.dateComponents([.day], from: start, to: end).day, (1...366).contains(days)
            else { throw ClinicNativeError.unavailable }
        } else {
            guard end <= now, end.timeIntervalSince(start) <= 366 * 86400 else { throw ClinicNativeError.unavailable }
        }
    }
    /// Existing exporters own complete days. Never round a timestamp request or change its approved zone.
    func ownerDates(timeZoneIdentifier: String, now: Date = Date()) throws -> [Date] {
        try validate(now: now)
        if let ownerDayZone, ownerDayZone != timeZoneIdentifier { throw ClinicNativeError.profileChanged }
        guard let zone = TimeZone(identifier: timeZoneIdentifier) else { throw ClinicNativeError.unavailable }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        guard calendar.startOfDay(for: start) == start, calendar.startOfDay(for: end) == end
        else { throw ClinicNativeError.unavailable }
        var dates: [Date] = []; var day = start
        while day < end {
            dates.append(day)
            guard dates.count <= 366, let next = calendar.date(byAdding: .day, value: 1, to: day), next > day
            else { throw ClinicNativeError.unavailable }
            day = next
        }
        return dates
    }
}

enum ClinicNativeError: Error { case unavailable, interrupted, profileChanged, invalidJournal, capacity, incompleteExport }

protocol ClinicStoredRecord: Codable { var storageVersion: Int { get } }

struct ClinicRefreshRecord: ClinicStoredRecord, Equatable, Sendable {
    var storageVersion = 1
    enum State: String, Codable, Sendable { case requested, executing, uploaded, failed }
    let request: ClinicRefreshRequest
    var state: State
    var exportID: String?
    var uploadedAt: Date?
}

/// App-private, backup-excluded, protected metadata. Corrupt/missing-in-flight state never becomes a fresh export.
/// MainActor serializes stores across coordinator instances in the app process.
@MainActor
final class ClinicPrivateStore {
    private let root: URL
    private let manager = FileManager.default
    init(root: URL) throws {
        self.root = root
        try manager.createDirectory(at: root, withIntermediateDirectories: true,
                                    attributes: [.posixPermissions: 0o700])
        guard try root.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
            throw ClinicNativeError.invalidJournal
        }
        var location = root
        var values = URLResourceValues(); values.isExcludedFromBackup = true
        try location.setResourceValues(values)
    }
    static func applicationStore() throws -> ClinicPrivateStore {
        let base = try FileManager.default.url(for: .applicationSupportDirectory, in: .userDomainMask,
                                               appropriateFor: nil, create: true)
        return try ClinicPrivateStore(root: base.appendingPathComponent("ClinicIntegration", isDirectory: true))
    }
    private func path(_ key: String) -> URL {
        let hash = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return root.appendingPathComponent(hash + ".json")
    }
    func executionIdentity(_ key: String) -> String { path(key).standardizedFileURL.resolvingSymlinksInPath().path }
    func load<T: ClinicStoredRecord>(_ type: T.Type, key: String) throws -> T? {
        let file = path(key)
        guard manager.fileExists(atPath: file.path) || (try? manager.attributesOfItem(atPath: file.path)[.type]) != nil else { return nil }
        let values = try file.resourceValues(forKeys: [.isSymbolicLinkKey, .isRegularFileKey, .fileSizeKey])
        guard values.isSymbolicLink != true, values.isRegularFile == true,
              let size = values.fileSize, size <= 1_048_576 else { throw ClinicNativeError.invalidJournal }
        do {
            let decoded = try JSONDecoder().decode(type, from: Data(contentsOf: file))
            guard decoded.storageVersion == 1 else { throw ClinicNativeError.invalidJournal }
            if let record = decoded as? ClinicRefreshRecord {
                guard record.state == .uploaded ? (record.exportID?.isEmpty == false && record.uploadedAt != nil)
                    : (record.exportID == nil && record.uploadedAt == nil) else { throw ClinicNativeError.invalidJournal }
            }
            return decoded
        }
        catch { throw ClinicNativeError.invalidJournal }
    }
    func save<T: ClinicStoredRecord>(_ value: T, key: String) throws {
        guard (try manager.contentsOfDirectory(atPath: root.path)).count < 1000 || manager.fileExists(atPath: path(key).path)
        else { throw ClinicNativeError.capacity }
        let data = try JSONEncoder().encode(value)
        guard data.count <= 1_048_576 else { throw ClinicNativeError.capacity }
        #if os(iOS)
        try data.write(to: path(key), options: [.atomic, .completeFileProtection])
        #else
        try data.write(to: path(key), options: .atomic)
        #endif
        try manager.setAttributes([.posixPermissions: 0o600], ofItemAtPath: path(key).path)
        let handle = try FileHandle(forWritingTo: path(key)); try handle.synchronize(); try handle.close()
        #if canImport(Darwin)
        let descriptor = open(root.path, O_RDONLY)
        guard descriptor >= 0 else { throw ClinicNativeError.invalidJournal }
        defer { close(descriptor) }
        guard fsync(descriptor) == 0 else { throw ClinicNativeError.invalidJournal }
        #endif
    }
}

/// The service/session adapter must supply authenticated requests and revocation/status checks.
/// Production has no adapter and remains behind the existing unqualified Practice gate.
@MainActor
final class ClinicForegroundRefresh {
    private final class ActiveExecution {
        let request: ClinicRefreshRequest
        var waiters: [CheckedContinuation<ClinicRefreshRecord, Error>] = []
        init(_ request: ClinicRefreshRequest) { self.request = request }
    }
    private static var active: [String: ActiveExecution] = [:]
    private let store: ClinicPrivateStore
    private let enabled: () -> Bool
    init(store: ClinicPrivateStore, enabled: @escaping () -> Bool = { PracticeFeaturePolicy.current.isEnabled }) {
        self.store = store; self.enabled = enabled
    }
    func run(
        request: ClinicRefreshRequest,
        now: @escaping @MainActor () -> Date = Date.init,
        authenticate: @escaping @MainActor () async throws -> Void,
        authorize: @escaping @MainActor () async throws -> Void,
        export: @MainActor (_ check: @escaping @MainActor () async throws -> Void) async throws -> String,
        report: @MainActor (ClinicRefreshRecord) async throws -> Void
    ) async throws -> ClinicRefreshRecord {
        guard enabled() else { throw ClinicNativeError.unavailable }
        let key = ["refresh", request.subjectID, request.deviceID, request.requestID].joined(separator: "\u{0}")
        // Retry callers authenticate independently. The owner alone executes and reports outcomes.
        try await authenticate()
        let identity = store.executionIdentity(key)
        if let execution = Self.active[identity] {
            guard execution.request == request else { throw ClinicNativeError.profileChanged }
            return try await withCheckedThrowingContinuation { execution.waiters.append($0) }
        }
        let execution = ActiveExecution(request)
        Self.active[identity] = execution
        do {
            let result = try await runOwned(request: request, key: key, now: now, authenticate: authenticate,
                                            authorize: authorize, export: export, report: report)
            Self.active.removeValue(forKey: identity)
            for waiter in execution.waiters { waiter.resume(returning: result) }
            return result
        } catch {
            Self.active.removeValue(forKey: identity)
            for waiter in execution.waiters { waiter.resume(throwing: error) }
            throw error
        }
    }
    private func runOwned(
        request: ClinicRefreshRequest, key: String, now: @escaping @MainActor () -> Date,
        authenticate: @escaping @MainActor () async throws -> Void,
        authorize: @escaping @MainActor () async throws -> Void,
        export: @MainActor (_ check: @escaping @MainActor () async throws -> Void) async throws -> String,
        report: @MainActor (ClinicRefreshRecord) async throws -> Void
    ) async throws -> ClinicRefreshRecord {
        // No live in-process owner exists here. An executing record therefore denotes interrupted work.
        if var old = try store.load(ClinicRefreshRecord.self, key: key), old.state != .requested {
            guard old.request == request else { throw ClinicNativeError.profileChanged }
            if old.state == .executing { old.state = .failed; try store.save(old, key: key) }
            try await report(old); return old
        }
        if let stored = try store.load(ClinicRefreshRecord.self, key: key), stored.request != request { throw ClinicNativeError.profileChanged }
        try request.validate(now: now())
        if try store.load(ClinicRefreshRecord.self, key: key) == nil {
            try store.save(ClinicRefreshRecord(request: request, state: .requested), key: key)
        }
        let check: @MainActor () async throws -> Void = {
            guard self.enabled() else { throw ClinicNativeError.unavailable }
            try request.validate(now: now()); try await authenticate(); try await authorize()
        }
        try await check()
        // An interleaved coordinator may have reserved this request while authorization suspended.
        guard let queued = try store.load(ClinicRefreshRecord.self, key: key), queued.request == request, queued.state == .requested
        else { throw ClinicNativeError.interrupted }
        var record = ClinicRefreshRecord(request: request, state: .executing)
        try store.save(record, key: key)
        do {
            let exportID = try await export(check)
            guard !exportID.isEmpty, exportID.utf8.count <= 200 else { throw ClinicNativeError.incompleteExport }
            record.state = .uploaded; record.exportID = exportID; record.uploadedAt = now()
        } catch {
            record.state = .failed; try store.save(record, key: key)
            try await report(record); throw error
        }
        // Keep this outside the export catch: an acknowledgment failure cannot replace upload evidence.
        try store.save(record, key: key)
        try await report(record)
        return record
    }
}

/// Trusted native state, never imported setup or URL flags. The policy-dependent clinic route defaults off.
struct ClinicExportGates {
    let subjectID: String
    let deviceID: String
    let connectionID: String
    let foreground: Bool
    let sharingConsent: Bool
    let healthDataAvailable: Bool
    let consumerAllowsExport: Bool
    let verifiedClinicGrant: Bool
    var clinicEntitlementRouteEnabled = false
    func require(for request: ClinicRefreshRequest) throws {
        guard subjectID == request.subjectID, deviceID == request.deviceID, connectionID == request.connectionID,
              foreground, sharingConsent, healthDataAvailable,
              consumerAllowsExport || (clinicEntitlementRouteEnabled && verifiedClinicGrant)
        else { throw ClinicNativeError.unavailable }
    }
}
