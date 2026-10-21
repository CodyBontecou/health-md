import CryptoKit
import Darwin
import Foundation
import HealthMdConnectionCore

/// Independently versioned, native-only captured bytes. It is not a portable file, transfer
/// journal or permission token. The accepted job, protected key and original native fence own it.
@MainActor
final class AgentBridgeNativeCaptureSpool {
    nonisolated private struct Record: Codable, Equatable {
        let version: Int
        let requestSHA256: String
        let resolutionSHA256: String
        let claimID: String
        let expiresAt: String
        let kind: String
        let day: String?
        let payload: Data
    }
    nonisolated private struct Signed: Codable { let record: Record; let mac: Data }
    private static let domain = Data("HealthMd.AgentBridge.NativeCaptureSpool.v1\0".utf8)
    private static let payloadLimit = 64 * 1024
    private static let jobLimit = 64 * 1024 * 1024
    private let reservation: AgentBridgeExportCaptureReservation
    private let key: SymmetricKey
    private let fence: @MainActor () throws -> Void
    private let issuer: URL
    private let captures: URL
    private let directory: URL
    private var issuerFD: Int32 = -1
    private var capturesFD: Int32 = -1
    private var directoryFD: Int32 = -1
    private var lockFD: Int32 = -1
    private var identities: [AgentBridgeExportFileIdentity] = []
    private var storedBytes = 0
    private var closed = false

    init(issuer: URL, reservation: AgentBridgeExportCaptureReservation, key: SymmetricKey, create: Bool,
         fence: @escaping @MainActor () throws -> Void) throws {
        self.issuer = issuer; self.reservation = reservation; self.key = key; self.fence = fence
        captures = issuer.appendingPathComponent("captures", isDirectory: true)
        directory = captures.appendingPathComponent(reservation.job.requestSHA256.rawValue, isDirectory: true)
        do {
            try reservation.job.validate()
            guard reservation.claim.version == 1, reservation.claim.requestSHA256 == reservation.job.requestSHA256,
                  reservation.claim.claimedAt.rawValue >= reservation.job.acceptedAt.rawValue,
                  reservation.claim.claimedAt.rawValue < reservation.job.expiresAt.rawValue else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            try fence()
            issuerFD = try AgentBridgeExportPrivateFiles.openDirectory(issuer, privateLeaf: true)
            identities = [try AgentBridgeExportPrivateFiles.identity(issuerFD)]
            try check()
            if create { try Self.mkdir(issuerFD, "captures", exclusive: false) }
            capturesFD = try AgentBridgeExportPrivateFiles.openDirectory(captures, privateLeaf: true)
            try Self.verifyProtection(capturesFD)
            identities.append(try AgentBridgeExportPrivateFiles.identity(capturesFD))
            try check()
            if create { try Self.mkdir(capturesFD, reservation.job.requestSHA256.rawValue, exclusive: true) }
            directoryFD = try AgentBridgeExportPrivateFiles.openDirectory(directory, privateLeaf: true)
            try Self.verifyProtection(directoryFD)
            identities.append(try AgentBridgeExportPrivateFiles.identity(directoryFD))
            try check()
            if create {
                let fd = openat(directoryFD, "lock", O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
                guard fd >= 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                do { try Self.protect(fd); guard fsync(fd) == 0, fsync(directoryFD) == 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired } }
                catch { Darwin.close(fd); throw error }
                Darwin.close(fd)
            }
            lockFD = try AgentBridgeExportPrivateFiles.openPrivateFile(directoryFD, "lock", flags: O_RDWR)
            try Self.verifyProtection(lockFD)
            guard flock(lockFD, LOCK_EX | LOCK_NB) == 0 else { throw AgentBridgeValidationError.busy }
            guard try fileSize("lock") == 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            try check()
            for name in try Self.entries(directoryFD) {
                guard name == "lock" || name == "header.json" || name == "progress.json" || Self.dayName(name) || Self.pendingName(name) else {
                    throw AgentBridgeValidationError.spoolMissingRestartRequired
                }
                storedBytes += try fileSize(name)
                guard storedBytes <= Self.jobLimit else { throw AgentBridgeValidationError.queryBudgetExceeded }
            }
            if create {
                try publish("header.json", record: record(kind: "job", day: nil))
                try publish("progress.json", record: record(kind: "progress", day: nil, payload: JSONEncoder().encode([String]())))
            } else {
                guard try read("header.json") == record(kind: "job", day: nil) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                _ = try progress()
            }
            try validateStoredProgress()
            try check()
        } catch { close(); throw Self.safe(error) }
    }
    deinit { Darwin.close(lockFD); Darwin.close(directoryFD); Darwin.close(capturesFD); Darwin.close(issuerFD) }

    /// A retained successful capture is immutable. A started marker without captured bytes is
    /// ambiguous and must never trigger a second SDK read, including after process restart.
    func loadOrBegin(_ day: AgentBridgeDate) throws -> Data? {
        do {
            try check()
            let started = "started-\(day.rawValue).json", captured = "day-\(day.rawValue).json"
            let (previous, days) = try progress()
            if days.contains(day.rawValue) {
                guard try exists(captured) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                guard try read(started) == record(kind: "started", day: day.rawValue) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                let value = try read(captured)
                guard value.kind == "captured", value.day == day.rawValue, !value.payload.isEmpty else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                try check(); return value.payload
            }
            guard try !exists(started), try !exists(captured) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            guard days.count < 4096 else { throw AgentBridgeValidationError.queryBudgetExceeded }
            guard storedBytes + 2 * Self.payloadLimit < Self.jobLimit else { throw AgentBridgeValidationError.queryBudgetExceeded }
            let next = try JSONEncoder().encode((days + [day.rawValue]).sorted())
            try publish("progress.json", record: record(kind: "progress", day: nil, payload: next), replacing: previous)
            try publish(started, record: record(kind: "started", day: day.rawValue))
            return nil
        } catch { throw Self.safe(error) }
    }
    func commit(_ day: AgentBridgeDate, payload: Data) throws {
        do {
            guard !payload.isEmpty, payload.count <= Self.payloadLimit else { throw AgentBridgeValidationError.queryBudgetExceeded }
            try check()
            guard try progress().1.contains(day.rawValue) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            guard try read("started-\(day.rawValue).json") == record(kind: "started", day: day.rawValue) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            try publish("day-\(day.rawValue).json", record: record(kind: "captured", day: day.rawValue, payload: payload))
        } catch { throw Self.safe(error) }
    }
    func close() {
        if closed { return }; closed = true
        if lockFD >= 0 { _ = flock(lockFD, LOCK_UN); Darwin.close(lockFD); lockFD = -1 }
        if directoryFD >= 0 { Darwin.close(directoryFD); directoryFD = -1 }
        if capturesFD >= 0 { Darwin.close(capturesFD); capturesFD = -1 }
        if issuerFD >= 0 { Darwin.close(issuerFD); issuerFD = -1 }
    }
    private func record(kind: String, day: String?, payload: Data = Data()) -> Record {
        .init(version: 1, requestSHA256: reservation.job.requestSHA256.rawValue,
              resolutionSHA256: AgentBridgeV4Codec.sha256(reservation.job.nativeResolution),
              claimID: reservation.claim.claimID.rawValue, expiresAt: reservation.job.expiresAt.rawValue,
              kind: kind, day: day, payload: payload)
    }
    private func validateStoredProgress() throws {
        let (_, days) = try progress()
        var expected: Set<String> = ["lock", "header.json", "progress.json"]
        for day in days {
            let started = "started-\(day).json", captured = "day-\(day).json"
            expected.insert(started); expected.insert(captured)
            guard try read(started) == record(kind: "started", day: day) else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            let value = try read(captured)
            guard value.kind == "captured", value.day == day, !value.payload.isEmpty else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        }
        let names = Set(try Self.entries(directoryFD).filter { !Self.pendingName($0) })
        guard names == expected else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
    }
    private func progress() throws -> (Record, [String]) {
        let value = try read("progress.json")
        let days = try JSONDecoder().decode([String].self, from: value.payload)
        guard value.kind == "progress", value.day == nil, days.count <= 4096,
              Set(days).count == days.count, days == days.sorted(),
              try JSONEncoder().encode(days) == value.payload else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        for day in days { _ = try AgentBridgeDate(day) }
        return (value, days)
    }
    private func check() throws { try pins(); try fence(); try pins() }
    private func pins() throws {
        guard !closed, !identities.isEmpty else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        for (index, url) in [issuer, captures, directory].prefix(identities.count).enumerated() {
            let fd = try AgentBridgeExportPrivateFiles.openDirectory(url, privateLeaf: true)
            defer { Darwin.close(fd) }
            guard try AgentBridgeExportPrivateFiles.identity(fd) == identities[index] else { throw AgentBridgeValidationError.bindingChanged }
            if index > 0 { try Self.verifyProtection(fd) }
        }
        if lockFD >= 0 {
            try AgentBridgeExportPrivateFiles.checkPath(directoryFD, "lock", fd: lockFD)
            try Self.verifyProtection(lockFD)
        }
    }
    private func exists(_ name: String) throws -> Bool {
        var value = stat()
        if fstatat(directoryFD, name, &value, AT_SYMLINK_NOFOLLOW) == 0 { return true }
        guard errno == ENOENT else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        return false
    }
    private func fileSize(_ name: String) throws -> Int {
        let fd = try AgentBridgeExportPrivateFiles.openPrivateFile(directoryFD, name, flags: O_RDONLY)
        defer { Darwin.close(fd) }
        try Self.verifyProtection(fd)
        var value = stat()
        guard fstat(fd, &value) == 0, value.st_size >= 0, value.st_size <= 2 * Self.payloadLimit else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        return Int(value.st_size)
    }
    private func read(_ name: String) throws -> Record {
        try check()
        guard try exists(name), try fileSize(name) > 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        let bytes = try AgentBridgeExportPrivateFiles.read(directoryFD, name)
        let record: Record
        do {
            let canonical = try AgentBridgeV4Codec.canonicalize(bytes)
            let value = try JSONDecoder().decode(Signed.self, from: canonical)
            guard try Self.canonical(value) == canonical,
                  HMAC<SHA256>.isValidAuthenticationCode(value.mac, authenticating: Self.domain + (try Self.canonical(value.record)), using: key),
                  value.record == self.record(kind: value.record.kind, day: value.record.day, payload: value.record.payload),
                  value.record.payload.count <= Self.payloadLimit else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            record = value.record
        } catch { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        try check(); return record
    }
    private func publish(_ name: String, record: Record, replacing previous: Record? = nil) throws {
        let body = try Self.canonical(record)
        let bytes = try Self.canonical(Signed(record: record, mac: Data(HMAC<SHA256>.authenticationCode(for: Self.domain + body, using: key))))
        guard bytes.count <= 2 * Self.payloadLimit, storedBytes + bytes.count <= Self.jobLimit else { throw AgentBridgeValidationError.queryBudgetExceeded }
        let previousBytes = try previous.map { value in
            try Self.canonical(Signed(record: value, mac: Data(HMAC<SHA256>.authenticationCode(for: Self.domain + (try Self.canonical(value)), using: key))))
        }
        try check()
        if let previousBytes {
            guard try AgentBridgeExportPrivateFiles.read(directoryFD, name) == previousBytes else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        } else { guard try !exists(name) else { throw AgentBridgeValidationError.busy } }
        let temporary = "pending-" + UUID().uuidString.lowercased()
        let fd = openat(directoryFD, temporary, O_WRONLY | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        guard fd >= 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        defer {
            if (try? AgentBridgeExportPrivateFiles.checkPath(directoryFD, temporary, fd: fd)) != nil { _ = unlinkat(directoryFD, temporary, 0) }
            Darwin.close(fd)
        }
        try Self.protect(fd)
        try bytes.withUnsafeBytes { buffer in
            var offset = 0
            while offset < buffer.count {
                let count = Darwin.write(fd, buffer.baseAddress!.advanced(by: offset), buffer.count - offset)
                if count < 0 && errno == EINTR { continue }
                guard count > 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
                offset += count
            }
        }
        try AgentBridgeExportPrivateFiles.checkPath(directoryFD, temporary, fd: fd)
        guard fsync(fd) == 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        try check()
        try AgentBridgeExportPrivateFiles.checkPath(directoryFD, temporary, fd: fd)
        if let previousBytes {
            guard try AgentBridgeExportPrivateFiles.read(directoryFD, name) == previousBytes else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        }
        guard renameatx_np(directoryFD, temporary, directoryFD, name, previous == nil ? UInt32(RENAME_EXCL) : 0) == 0,
              fsync(directoryFD) == 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        storedBytes += bytes.count - (previousBytes?.count ?? 0)
        try AgentBridgeExportPrivateFiles.checkPath(directoryFD, name, fd: fd)
        try check()
    }
    private static func canonical<T: Encodable>(_ value: T) throws -> Data { try AgentBridgeV4Codec.canonicalize(JSONEncoder().encode(value)) }
    private static func mkdir(_ parent: Int32, _ name: String, exclusive: Bool) throws {
        if mkdirat(parent, name, 0o700) != 0 {
            guard !exclusive, errno == EEXIST else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        } else {
            let fd = openat(parent, name, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
            guard fd >= 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
            defer { Darwin.close(fd) }
            try protect(fd)
            guard fsync(fd) == 0, fsync(parent) == 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        }
    }
    private static func protect(_ fd: Int32) throws {
        #if os(iOS)
        let path = try protectedPath(fd)
        try FileManager.default.setAttributes([.protectionKey: FileProtectionType.complete], ofItemAtPath: path)
        try verifyProtection(fd)
        #endif
    }
    private static func verifyProtection(_ fd: Int32) throws {
        #if os(iOS)
        let path = try protectedPath(fd)
        let attributes = try FileManager.default.attributesOfItem(atPath: path)
        guard attributes[.protectionKey] as? FileProtectionType == .complete,
              try protectedPath(fd) == path else { throw AgentBridgeValidationError.permissionRequired }
        #endif
    }
    #if os(iOS)
    /// Foundation owns the public protection-class mapping. Pin its pathname to the original
    /// descriptor before and after attribute work; never repair protection while opening a spool.
    private static func protectedPath(_ fd: Int32) throws -> String {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN))
        guard fcntl(fd, F_GETPATH, &buffer) == 0 else { throw AgentBridgeValidationError.permissionRequired }
        let path = String(cString: buffer)
        var opened = stat(), named = stat()
        guard fstat(fd, &opened) == 0, lstat(path, &named) == 0,
              opened.st_dev == named.st_dev, opened.st_ino == named.st_ino,
              named.st_mode & mode_t(S_IFMT) != mode_t(S_IFLNK) else { throw AgentBridgeValidationError.bindingChanged }
        return path
    }
    #endif
    private static func entries(_ fd: Int32) throws -> [String] {
        // dup shares the original directory cursor. Each inventory needs a fresh description.
        let inventoryFD = openat(fd, ".", O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC)
        guard inventoryFD >= 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        guard let directory = fdopendir(inventoryFD) else {
            Darwin.close(inventoryFD)
            throw AgentBridgeValidationError.spoolMissingRestartRequired
        }
        defer { closedir(directory) }
        var result: [String] = []
        errno = 0
        while let entry = readdir(directory) {
            let name = withUnsafePointer(to: entry.pointee.d_name) { pointer in
                pointer.withMemoryRebound(to: CChar.self, capacity: Int(MAXNAMLEN) + 1) { String(cString: $0) }
            }
            if name == "." || name == ".." { continue }
            guard result.count < 8258 else { throw AgentBridgeValidationError.queryBudgetExceeded }
            result.append(name)
        }
        guard errno == 0 else { throw AgentBridgeValidationError.spoolMissingRestartRequired }
        return result
    }
    private static func dayName(_ name: String) -> Bool { name.range(of: "^(started|day)-[0-9]{4}-[0-9]{2}-[0-9]{2}\\.json$", options: .regularExpression) != nil }
    private static func pendingName(_ name: String) -> Bool { name.range(of: "^pending-[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$", options: .regularExpression) != nil }
    private static func safe(_ error: Error) -> Error {
        if error is CancellationError || error is AgentBridgeValidationError { return error }
        return AgentBridgeValidationError.spoolMissingRestartRequired
    }
}

/// Private capture payload v1: canonical scalar values only. Never reuse public HealthData Codable
/// as a private journal format; adding output fields must not reinterpret an already captured day.
nonisolated struct AgentBridgeCapturedScalarDay: Codable {
    let version: Int
    let day: String
    let calendarTimezone: String
    let values: [String: Double]
}
