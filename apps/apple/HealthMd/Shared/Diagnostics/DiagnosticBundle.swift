import CryptoKit
import Foundation

nonisolated enum DiagnosticBundleError: String, Error, LocalizedError, Sendable {
    case attachmentLimit = "Attachments exceed 100 MiB or 50 files. Remove files and prepare again."
    case invalidAttachment = "An attachment is unavailable or is not a regular file. Select the file again."
    case bundleChanged = "The reviewed bundle changed or was deleted. Prepare and review it again."
    case invalidDirectory = "Diagnostic storage is unavailable. Check local storage and try again."
    var errorDescription: String? { rawValue }
}

nonisolated struct DiagnosticBundleFile: Codable, Identifiable, Sendable {
    let path: String
    let byte_count: Int64
    let sha256: String
    let privacy: String
    let original_name: String?
    let original_name_truncated: Bool
    var id: String { path }
}

nonisolated struct DiagnosticBundleManifest: Encodable, Sendable {
    let schema = "healthmd.diagnostic_bundle"
    let schema_version = 1
    let generated_at: String
    let platform: String
    let app_version: String
    let app_build: String
    let os_version: String
    let include_private_context: Bool
    let contains_private_context: Bool
    let health_content: String
    let event_count: Int
    let session_dropped_event_count: Int
    let invalid_event_count: Int
    let truncated: Bool
    let selection_since: String?
    let selection_subsystem: String?
    let selection_operation_id: String?
    let files: [DiagnosticBundleFile]
}

/// The reviewed artifact is immutable to the composer: selections are never
/// reapplied at share time. The ZIP digest is checked before exposing it.
nonisolated struct PreparedDiagnosticBundle: Sendable, Identifiable {
    let directory: URL
    let zipURL: URL
    let zipSHA256: String
    let manifestSHA256: String
    let manifest: DiagnosticBundleManifest
    var id: String { directory.lastPathComponent }

    func verifiedURL() throws -> URL {
        guard try DiagnosticBundleBuilder.digest(zipURL) == zipSHA256 else { throw DiagnosticBundleError.bundleChanged }
        for path in ["manifest.json"] + manifest.files.map(\.path) { try verifyFile(path) }
        return zipURL
    }
    func preview(_ path: String, maximumBytes: Int = 128 * 1024) throws -> (text: String, truncated: Bool) {
        guard path == "manifest.json" || manifest.files.contains(where: { $0.path == path }) else { throw DiagnosticBundleError.bundleChanged }
        try verifyFile(path)
        let url = directory.appendingPathComponent(path)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        let bytes = try handle.read(upToCount: maximumBytes + 1) ?? Data()
        let prefix = bytes.prefix(maximumBytes)
        guard let text = String(data: prefix, encoding: .utf8) else {
            return ("Binary or non-UTF-8 file. Original bytes are included unchanged; inspect it with a trusted local viewer before sharing.", bytes.count > maximumBytes)
        }
        return (text, bytes.count > maximumBytes)
    }
    private func verifyFile(_ path: String) throws {
        let expected = path == "manifest.json" ? manifestSHA256 : manifest.files.first { $0.path == path }?.sha256
        guard try DiagnosticBundleBuilder.digest(directory.appendingPathComponent(path)) == expected else { throw DiagnosticBundleError.bundleChanged }
    }
    func delete() { try? FileManager.default.removeItem(at: directory) }
}

nonisolated enum DiagnosticBundleBuilder {
    static let attachmentByteLimit: Int64 = 100 * 1024 * 1024
    static let readme = """
    Health.md diagnostics v1

    This ZIP is NOT encrypted. Health.md does not upload it automatically.
    Review manifest.json, events.jsonl, and every attachment before sharing.
    Operational diagnostics exclude health measurements, health record IDs,
    requested health dates, paths, endpoint addresses, and credential values.
    Private context is opt-in and is not anonymous. Original user attachments
    are copied unchanged and may contain health data, identifiers or secrets.
    Attachments are not automatically scrubbed. No new health reads are made.
    Public GitHub/Discord posts may be accessible to anyone. Email and other
    destinations have their own retention and security rules. Shared copies
    cannot be recalled by Health.md. Delete local copies in Diagnostics.

    Events use stable event IDs and catalog-validated typed fields. Omitted fields
    distinguish not_recorded (absent at capture), redacted (excluded at sharing),
    and invalid (rejected by the catalog). Truncation, malformed events, and
    drops in the current app process are disclosed in the manifest. Wall clocks
    can differ between devices; sequence/monotonic timing orders each session.
    Existing session/operation IDs are random operational IDs, not health IDs.
    Source locations refer to the open-source app, not local filesystem paths.

    Catalog: packages/contracts/diagnostics/v1/catalog.json
    Source: https://github.com/CodyBontecou/health-md
    """

    static func prepare(recorder: DiagnosticRecorder = .shared, includePrivate: Bool = false, since: Date? = nil, subsystem: String? = nil, operationID: String? = nil, attachments: [URL] = []) throws -> PreparedDiagnosticBundle {
        guard attachments.count <= 50 else { throw DiagnosticBundleError.attachmentLimit }
        let root = recorder.directory.appendingPathComponent("bundles", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        guard (try root.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true,
              (try recorder.directory.resourceValues(forKeys: [.isSymbolicLinkKey])).isSymbolicLink != true else { throw DiagnosticBundleError.invalidDirectory }
        sweep(root)
        let directory = root.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        var backupFlags = URLResourceValues(); backupFlags.isExcludedFromBackup = true
        var protectedRoot = directory; try protectedRoot.setResourceValues(backupFlags)
        var complete = false
        defer { if !complete { try? FileManager.default.removeItem(at: directory) } }
        let snapshot = recorder.snapshot(includePrivate: includePrivate, since: since, subsystem: subsystem, operationID: operationID)
        var files: [DiagnosticBundleFile] = []
        func add(_ path: String, data: Data, privacy: String = "operational") throws {
            let url = directory.appendingPathComponent(path)
            try data.write(to: url, options: .atomic)
            try protect(url)
            files.append(DiagnosticBundleFile(path: path, byte_count: Int64(data.count), sha256: try digest(url), privacy: privacy, original_name: nil, original_name_truncated: false))
        }
        try add("README.txt", data: Data(readme.utf8))
        let jsonl = snapshot.events.map(\.jsonLine).joined(separator: "\n") + (snapshot.events.isEmpty ? "" : "\n")
        let hasPrivate = snapshot.events.contains { $0.fields.keys.contains { DiagnosticField(rawValue: $0)?.isPrivate == true } }
        try add("events.jsonl", data: Data(jsonl.utf8), privacy: hasPrivate ? "private_context" : "operational")
        let text = snapshot.events.map { "\($0.timestamp) [\($0.severity)] \($0.event_id.rawValue) \($0.source)\n\($0.jsonLine)" }.joined(separator: "\n\n")
        try add("events.txt", data: Data(text.utf8), privacy: hasPrivate ? "private_context" : "operational")
        var attachmentBytes: Int64 = 0
        if !attachments.isEmpty { try FileManager.default.createDirectory(at: directory.appendingPathComponent("attachments"), withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700]) }
        for (index, source) in attachments.enumerated() {
            let scoped = source.startAccessingSecurityScopedResource()
            defer { if scoped { source.stopAccessingSecurityScopedResource() } }
            let originalValues = try source.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            guard originalValues.isRegularFile == true, originalValues.isSymbolicLink != true else { throw DiagnosticBundleError.invalidAttachment }
            let ext = source.pathExtension.lowercased()
            let safeExtension = ext.range(of: "^[a-z0-9]{1,10}$", options: .regularExpression) != nil ? ext : "bin"
            let path = "attachments/attachment-\(index + 1).\(safeExtension)"
            let destination = directory.appendingPathComponent(path)
            var coordinatedError: NSError?
            var copyError: Error?
            NSFileCoordinator().coordinate(readingItemAt: source, options: [], error: &coordinatedError) { readable in
                do {
                    let values = try readable.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
                    guard values.isRegularFile == true, values.isSymbolicLink != true else { throw DiagnosticBundleError.invalidAttachment }
                    let input = try FileHandle(forReadingFrom: readable)
                    defer { try? input.close() }
                    guard FileManager.default.createFile(atPath: destination.path, contents: nil, attributes: DiagnosticRecorder.fileAttributes) else { throw DiagnosticBundleError.invalidDirectory }
                    let output = try FileHandle(forWritingTo: destination)
                    defer { try? output.close() }
                    while let chunk = try input.read(upToCount: 64 * 1024), !chunk.isEmpty {
                        attachmentBytes += Int64(chunk.count)
                        guard attachmentBytes <= attachmentByteLimit else { throw DiagnosticBundleError.attachmentLimit }
                        try output.write(contentsOf: chunk)
                    }
                    try output.synchronize()
                } catch { copyError = error }
            }
            if let copyError { throw copyError }
            if coordinatedError != nil { throw DiagnosticBundleError.invalidAttachment }
            try protect(destination)
            let size = try destination.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
            files.append(DiagnosticBundleFile(path: path, byte_count: Int64(size), sha256: try digest(destination), privacy: "user_attachment", original_name: String(source.lastPathComponent.prefix(512)), original_name_truncated: source.lastPathComponent.count > 512))
        }
        let manifest = DiagnosticBundleManifest(
            generated_at: DiagnosticRecorder.timestamp(Date()), platform: DiagnosticRecorder.platform,
            app_version: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "unavailable",
            app_build: Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "unavailable",
            os_version: ProcessInfo.processInfo.operatingSystemVersionString,
            include_private_context: includePrivate, contains_private_context: hasPrivate || !attachments.isEmpty,
            health_content: hasPrivate || !attachments.isEmpty ? "possible" : "not_included",
            event_count: snapshot.events.count, session_dropped_event_count: snapshot.droppedEventCount,
            invalid_event_count: snapshot.invalidEventCount, truncated: snapshot.truncated,
            selection_since: since.map(DiagnosticRecorder.timestamp), selection_subsystem: subsystem, selection_operation_id: operationID,
            files: files
        )
        let manifestURL = directory.appendingPathComponent("manifest.json")
        try DiagnosticRecorder.encoder().encode(manifest).write(to: manifestURL, options: .atomic)
        try protect(manifestURL)
        let zip = directory.appendingPathComponent("healthmd-diagnostics.zip")
        let writer = try ZipArchiveWriter.begin(to: zip, workingDirectoryURL: directory)
        for path in ["manifest.json"] + files.map(\.path) { try writer.append(path: path, contentsOf: directory.appendingPathComponent(path)) }
        try writer.finish()
        try protect(zip)
        let prepared = PreparedDiagnosticBundle(directory: directory, zipURL: zip, zipSHA256: try digest(zip), manifestSHA256: try digest(manifestURL), manifest: manifest)
        complete = true
        return prepared
    }

    static func digest(_ url: URL) throws -> String {
        let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
        guard values.isRegularFile == true, values.isSymbolicLink != true else { throw DiagnosticBundleError.bundleChanged }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hash = SHA256()
        while let bytes = try handle.read(upToCount: 64 * 1024), !bytes.isEmpty { hash.update(data: bytes) }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    private static func protect(_ url: URL) throws {
        var attributes = DiagnosticRecorder.fileAttributes
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        try FileManager.default.setAttributes(attributes, ofItemAtPath: url.path)
    }
    static func sweep(_ root: URL) {
        let directories = ((try? FileManager.default.contentsOfDirectory(at: root, includingPropertiesForKeys: [.creationDateKey, .isSymbolicLinkKey])) ?? []).filter { UUID(uuidString: $0.lastPathComponent) != nil }.sorted {
            ((try? $0.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast) > ((try? $1.resourceValues(forKeys: [.creationDateKey]).creationDate) ?? .distantPast)
        }
        for (index, directory) in directories.enumerated() {
            let values = try? directory.resourceValues(forKeys: [.creationDateKey, .isSymbolicLinkKey])
            if values?.isSymbolicLink != true && (index >= 2 || Date().timeIntervalSince(values?.creationDate ?? .distantPast) >= 24 * 60 * 60) {
                try? FileManager.default.removeItem(at: directory)
            }
        }
    }
}
