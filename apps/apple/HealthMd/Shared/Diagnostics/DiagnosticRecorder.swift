import Foundation

nonisolated enum DiagnosticValue: Codable, Equatable, Sendable {
    case text(String), integer(Int64), boolean(Bool), invalid

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Bool.self) { self = .boolean(value) }
        else if let value = try? container.decode(Int64.self) { self = .integer(value) }
        else if let value = try? container.decode(String.self) { self = .text(value) }
        else { self = .invalid } // Unsupported shapes are never retained as arbitrary payloads.
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .text(let value): try container.encode(value)
        case .integer(let value): try container.encode(value)
        case .boolean(let value): try container.encode(value)
        case .invalid: try container.encodeNil()
        }
    }
}

nonisolated enum DiagnosticVerbosity: String, Codable, CaseIterable, Sendable {
    case info, debug, trace
    func includes(_ severity: String) -> Bool {
        switch severity {
        case "trace": return self == .trace
        case "debug": return self != .info
        default: return ["info", "warning", "error"].contains(severity)
        }
    }
}

nonisolated struct DiagnosticSettings: Codable, Sendable {
    var enabled = true
    var verbosity: DiagnosticVerbosity = .debug
    var privateContextUntil: Double = 0
}

nonisolated struct DiagnosticEvent: Codable, Identifiable, Sendable {
    let schema: String
    let schema_version: Int
    let timestamp: String
    let session_id: String
    let sequence: Int64
    let monotonic_ms: Int64
    let platform: String
    let event_id: DiagnosticEventID
    let subsystem: String
    let severity: String
    let source: String
    var fields: [String: DiagnosticValue]
    var omitted_fields: [String: String]
    var id: String { "\(session_id.lowercased()):\(sequence)" }

    /// Disk contents and sharing use the same catalog. Unknown keys/values never
    /// become operational just because a persisted record calls them redacted.
    func filtered(includePrivate: Bool) -> DiagnosticEvent? {
        guard schema == "healthmd.diagnostic_event", schema_version == 1,
              UUID(uuidString: session_id) != nil, session_id.count == 36,
              sequence >= 0, sequence <= 9_007_199_254_740_991, monotonic_ms >= 0, monotonic_ms <= 9_007_199_254_740_991,
              ["ios", "macos", "android"].contains(platform),
              subsystem == event_id.subsystem, severity == event_id.severity,
              DiagnosticRecorder.parseTimestamp(timestamp).map(DiagnosticRecorder.timestamp) == timestamp,
              source.range(of: "^[A-Za-z0-9_]+/[A-Za-z0-9_+.-]+\\.(swift|kt):[0-9]+$", options: .regularExpression) != nil
        else { return nil }
        var result = self
        result.fields = [:]
        result.omitted_fields = omitted_fields.filter {
            DiagnosticField(rawValue: $0.key) != nil && ["not_recorded", "redacted", "unavailable", "truncated", "invalid"].contains($0.value)
        }
        for (key, value) in fields {
            guard let field = DiagnosticField(rawValue: key) else { continue }
            guard field.accepts(value) else { result.omitted_fields[key] = "invalid"; continue }
            if field.isPrivate && !includePrivate { result.omitted_fields[key] = "redacted" }
            else { result.fields[key] = value; result.omitted_fields.removeValue(forKey: key) }
        }
        return result
    }

    var jsonLine: String {
        guard let data = try? DiagnosticRecorder.encoder().encode(self) else { return "" }
        return String(decoding: data, as: UTF8.self)
    }
}

nonisolated struct DiagnosticSnapshot: Sendable {
    let events: [DiagnosticEvent]
    let droppedEventCount: Int
    let invalidEventCount: Int
    let truncated: Bool
}

/// One serial disk seam, no network dependency, and no forwarding to OSLog.
/// Calls from transport/background delegates are bounded and non-blocking.
nonisolated final class DiagnosticRecorder: @unchecked Sendable {
    static let retentionSeconds: Double = 7 * 24 * 60 * 60
    static let privateRetentionSeconds: Double = 24 * 60 * 60
    static let defaultByteLimit = 20 * 1024 * 1024
    static let shared: DiagnosticRecorder = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        if ProcessInfo.processInfo.environment["XCTestConfigurationFilePath"] != nil {
            let recorder = DiagnosticRecorder(directory: FileManager.default.temporaryDirectory.appendingPathComponent("diagnostics-test-unused-\(UUID().uuidString)"))
            recorder.settingsValue.enabled = false
            recorder.updateAdmissionSettings()
            return recorder
        }
        return DiagnosticRecorder(directory: base.appendingPathComponent("Health.md/Diagnostics-v1", isDirectory: true))
    }()

    let directory: URL
    private let queue = DispatchQueue(label: "app.healthmd.diagnostics", qos: .utility)
    private let admission = NSLock()
    private var pending = 0
    private var dropped = 0
    private var settingsValue: DiagnosticSettings
    private var sequence: Int64 = 0
    private let sessionID = UUID().uuidString.lowercased()
    private let startedAt = ProcessInfo.processInfo.systemUptime
    private let clock: @Sendable () -> Date
    private let byteLimit: Int
    private var aliases: [String: String] = [:]
    private var activeFiles: [Bool: URL] = [:]
    private var privateDeadlineUptime: Double = 0
    private var admissionSettings = DiagnosticSettings()
    private var admissionPrivateDeadline: Double = 0

    init(directory: URL, byteLimit: Int = defaultByteLimit, clock: @escaping @Sendable () -> Date = { Date() }) {
        self.directory = directory
        self.byteLimit = max(1024, byteLimit)
        self.clock = clock
        let settingsURL = directory.appendingPathComponent("settings.json")
        let values = try? settingsURL.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])
        settingsValue = values?.isRegularFile == true && values?.isSymbolicLink != true && (values?.fileSize ?? Int.max) <= 16 * 1024
            ? ((try? Data(contentsOf: settingsURL)).flatMap { try? JSONDecoder().decode(DiagnosticSettings.self, from: $0) } ?? DiagnosticSettings())
            : DiagnosticSettings()
        // Time-box consent cannot be extended by a restored/tampered expiry.
        if settingsValue.privateContextUntil > clock().timeIntervalSince1970 + 15 * 60 {
            settingsValue.privateContextUntil = 0
        }
        privateDeadlineUptime = ProcessInfo.processInfo.systemUptime + max(0, settingsValue.privateContextUntil - clock().timeIntervalSince1970)
        updateAdmissionSettings()
        queue.async { [self] in prune() }
    }

    var settings: DiagnosticSettings { queue.sync { settingsValue } }

    func configure(enabled: Bool, verbosity: DiagnosticVerbosity) {
        queue.sync {
            settingsValue.enabled = enabled
            settingsValue.verbosity = verbosity
            if !enabled { settingsValue.privateContextUntil = 0 }
            updateAdmissionSettings()
            saveSettings()
        }
    }

    func startPrivateContextRecording() {
        queue.sync {
            settingsValue.privateContextUntil = settingsValue.enabled ? clock().timeIntervalSince1970 + 15 * 60 : 0
            privateDeadlineUptime = ProcessInfo.processInfo.systemUptime + (settingsValue.enabled ? 15 * 60 : 0)
            updateAdmissionSettings()
            saveSettings()
        }
        record(.recordingStarted)
    }

    func stopPrivateContextRecording() {
        queue.sync { settingsValue.privateContextUntil = 0; updateAdmissionSettings(); saveSettings() }
        record(.recordingStopped)
    }

    func peerFields(_ name: String) -> [DiagnosticField: DiagnosticValue] {
        admission.lock()
        defer { admission.unlock() }
        if aliases[name] == nil && aliases.count < 128 { aliases[name] = "peer_\(aliases.count + 1)" }
        return [.peerAlias: .text(aliases[name] ?? "peer_0"), .peerName: .text(name)]
    }

    func record(_ id: DiagnosticEventID, fields: [DiagnosticField: DiagnosticValue] = [:], unavailable: Set<DiagnosticField> = [], file: String = #fileID, line: UInt = #line) {
        let observedAt = clock()
        let observedUptime = ProcessInfo.processInfo.systemUptime
        admission.lock()
        guard admissionSettings.enabled, admissionSettings.verbosity.includes(id.severity) else { admission.unlock(); return }
        guard pending < 128 else { dropped += 1; admission.unlock(); return }
        let privateAtAdmission = admissionSettings.privateContextUntil > observedAt.timeIntervalSince1970 && observedUptime < admissionPrivateDeadline
        pending += 1
        admission.unlock()
        queue.async { [self] in
            defer { admission.lock(); pending -= 1; admission.unlock() }
            guard settingsValue.enabled, settingsValue.verbosity.includes(id.severity) else { return }
            do {
                try prepareDirectory()
                prune()
                sequence += 1
                let now = clock()
                var accepted: [String: DiagnosticValue] = [:]
                var omitted = Dictionary(uniqueKeysWithValues: unavailable.map { ($0.rawValue, "unavailable") })
                for (field, value) in fields {
                    if !field.accepts(value) { omitted[field.rawValue] = "invalid" }
                    else if field.isPrivate && (!privateAtAdmission || settingsValue.privateContextUntil <= now.timeIntervalSince1970 || ProcessInfo.processInfo.systemUptime >= privateDeadlineUptime) {
                        omitted[field.rawValue] = "not_recorded"
                    } else { accepted[field.rawValue] = value; omitted.removeValue(forKey: field.rawValue) }
                }
                let source = file.split(separator: "/").suffix(2).joined(separator: "/") + ":\(line)"
                let event = DiagnosticEvent(
                    schema: "healthmd.diagnostic_event", schema_version: 1,
                    timestamp: Self.timestamp(observedAt), session_id: sessionID, sequence: sequence,
                    monotonic_ms: Int64(max(0, observedUptime - startedAt) * 1000),
                    platform: Self.platform, event_id: id, subsystem: id.subsystem, severity: id.severity,
                    source: source, fields: accepted, omitted_fields: omitted
                )
                guard event.filtered(includePrivate: true) != nil else { noteDrop(); return }
                var data = try Self.encoder().encode(event)
                data.append(0x0A)
                guard data.count <= 16 * 1024, data.count <= byteLimit else { noteDrop(); return }
                let isPrivate = accepted.keys.contains { DiagnosticField(rawValue: $0)?.isPrivate == true }
                var target = activeFiles[isPrivate]
                if let existing = target {
                    let size = (try? existing.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
                    if !FileManager.default.fileExists(atPath: existing.path) || size + data.count > min(1024 * 1024, byteLimit) { target = nil }
                }
                if target == nil {
                    target = directory.appendingPathComponent("\(isPrivate ? "private" : "operational")-\(Int64(now.timeIntervalSince1970 * 1000))-\(UUID().uuidString).jsonl")
                    guard let target else { return }
                    guard FileManager.default.createFile(atPath: target.path, contents: nil, attributes: Self.fileAttributes) else { throw CocoaError(.fileWriteUnknown) }
                    activeFiles[isPrivate] = target
                }
                guard let target, try isRegular(target) else { throw CocoaError(.fileWriteUnknown) }
                let handle = try FileHandle(forWritingTo: target)
                defer { try? handle.close() }
                try handle.seekToEnd()
                try handle.write(contentsOf: data)
                prune()
            } catch { noteDrop() } // Logging never changes the caller's outcome.
        }
    }

    func snapshot(includePrivate: Bool = false, since: Date? = nil, subsystem: String? = nil, operationID: String? = nil) -> DiagnosticSnapshot {
        queue.sync {
            prune()
            var events: [DiagnosticEvent] = []
            var seen: Set<String> = []
            var invalid = 0
            var truncated = false
            for url in segmentFiles() where isRetained(url) {
                guard let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
                      size <= min(1024 * 1024, byteLimit),
                      let data = try? Data(contentsOf: url), data.count <= min(1024 * 1024, byteLimit) else { invalid += 1; continue }
                for line in data.split(separator: 0x0A) {
                    guard line.count <= 16 * 1024,
                          let decoded = try? JSONDecoder().decode(DiagnosticEvent.self, from: Data(line)),
                          let event = decoded.filtered(includePrivate: includePrivate) else { invalid += 1; continue }
                    guard seen.insert(event.id).inserted else { invalid += 1; continue }
                    guard since == nil || (Self.parseTimestamp(event.timestamp) ?? .distantPast) >= since! else { continue }
                    guard subsystem == nil || event.subsystem == subsystem else { continue }
                    guard operationID == nil || event.fields["operation_id"] == .text(operationID!) else { continue }
                    events.append(event)
                    if events.count > 10_000 { truncated = true }
                }
            }
            admission.lock(); let droppedCount = dropped; admission.unlock()
            return DiagnosticSnapshot(events: Array(events.sorted { ($0.timestamp, $0.session_id, $0.sequence) < ($1.timestamp, $1.session_id, $1.sequence) }.suffix(10_000)), droppedEventCount: droppedCount, invalidEventCount: invalid, truncated: truncated)
        }
    }

    @discardableResult func clear() -> Bool {
        queue.sync {
            settingsValue.privateContextUntil = 0
            updateAdmissionSettings()
            activeFiles = [:]
            admission.lock(); aliases = [:]; admission.unlock()
            var cleared = true
            for url in segmentFiles() { do { try FileManager.default.removeItem(at: url) } catch { cleared = false } }
            // Prepared bundles/attachment copies are diagnostics too.
            let bundles = directory.appendingPathComponent("bundles", isDirectory: true)
            if (try? bundles.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true {
                if FileManager.default.fileExists(atPath: bundles.path) {
                    do { try FileManager.default.removeItem(at: bundles) } catch { cleared = false }
                }
            }
            admission.lock(); dropped = 0; admission.unlock()
            saveSettings()
            return cleared
        }
    }

    private func updateAdmissionSettings() {
        admission.lock()
        admissionSettings = settingsValue
        admissionPrivateDeadline = privateDeadlineUptime
        admission.unlock()
    }
    private func noteDrop() { admission.lock(); dropped += 1; admission.unlock() }
    private func prepareDirectory() throws {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
        guard values.isDirectory == true, values.isSymbolicLink != true else { throw CocoaError(.fileWriteUnknown) }
        var root = directory
        var flags = URLResourceValues(); flags.isExcludedFromBackup = true
        try root.setResourceValues(flags)
    }
    private func saveSettings() {
        do {
            try prepareDirectory()
            let url = directory.appendingPathComponent("settings.json")
            try Self.encoder().encode(settingsValue).write(to: url, options: .atomic)
            try FileManager.default.setAttributes(Self.fileAttributes, ofItemAtPath: url.path)
        }
        catch { noteDrop() }
    }
    private func isRegular(_ url: URL) throws -> Bool {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        return values.isRegularFile == true && values.isSymbolicLink != true
    }
    private func segmentFiles() -> [URL] {
        guard (try? directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true else { return [] }
        return ((try? FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey, .fileSizeKey])) ?? [])
            .filter { $0.lastPathComponent.range(of: "^(operational|private)-[0-9]+-[A-Fa-f0-9-]{36}\\.jsonl$", options: .regularExpression) != nil && (try? isRegular($0)) == true }
            .sorted { segmentTime($0) < segmentTime($1) }
    }
    private func segmentTime(_ url: URL) -> Double {
        Double(url.lastPathComponent.split(separator: "-")[1]).map { $0 / 1000 } ?? 0
    }
    private func isRetained(_ url: URL) -> Bool {
        let age = clock().timeIntervalSince1970 - segmentTime(url)
        let ttl = url.lastPathComponent.hasPrefix("private-") ? Self.privateRetentionSeconds : Self.retentionSeconds
        return age < ttl && age >= -60
    }
    private func prune() {
        let bundles = directory.appendingPathComponent("bundles", isDirectory: true)
        if (try? bundles.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink) != true { DiagnosticBundleBuilder.sweep(bundles) }
        let now = clock().timeIntervalSince1970
        var total = 0
        var keep: [(URL, Int)] = []
        for url in segmentFiles() {
            let age = now - segmentTime(url)
            let ttl = url.lastPathComponent.hasPrefix("private-") ? Self.privateRetentionSeconds : Self.retentionSeconds
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
            if age >= ttl || age < -60 || size > min(1024 * 1024, byteLimit) { try? FileManager.default.removeItem(at: url) }
            else { total += size; keep.append((url, size)) }
        }
        for (url, size) in keep where total > byteLimit { try? FileManager.default.removeItem(at: url); total -= size }
    }

    static func encoder() -> JSONEncoder { let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]; return encoder }
    static func timestamp(_ date: Date) -> String { let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter.string(from: date) }
    static func parseTimestamp(_ value: String) -> Date? { let formatter = ISO8601DateFormatter(); formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]; return formatter.date(from: value) }
    static var platform: String {
        #if os(macOS)
        "macos"
        #else
        "ios"
        #endif
    }
    static var fileAttributes: [FileAttributeKey: Any] {
        #if os(iOS)
        [.posixPermissions: 0o600, .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication]
        #else
        [.posixPermissions: 0o600]
        #endif
    }
    static func errorFields(_ error: Error) -> [DiagnosticField: DiagnosticValue] {
        let native = error as NSError
        let domain = DiagnosticField.errorDomain.accepts(.text(native.domain)) ? native.domain : "unknown"
        return [.errorDomain: .text(domain), .errorCode: .integer(Int64(native.code))]
    }
}
