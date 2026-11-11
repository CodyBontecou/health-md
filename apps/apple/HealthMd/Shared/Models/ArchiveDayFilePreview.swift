import Foundation

/// A day's written file, read for the Archive day card and the day page.
nonisolated struct ArchiveDayFile: Equatable, Sendable {
    let fileURL: URL
    let rootURL: URL?
    let source: String
    let byteCount: Int

    /// Above this the day page shows the first lines only; the full viewer reads the rest.
    static let maximumBytes = 512 * 1024
    static let maximumLines = 400

    var lines: [String] {
        sourceLines.prefix(Self.maximumLines).map(String.init)
    }

    var isTruncated: Bool {
        byteCount > Self.maximumBytes || sourceLines.count > Self.maximumLines
    }

    private var sourceLines: [Substring] {
        let all = source.split(separator: "\n", omittingEmptySubsequences: false)
        // A trailing newline is not a line of its own.
        return all.last == "" ? Array(all.dropLast()) : all
    }

    var sizeText: String {
        ByteCountFormatter.string(fromByteCount: Int64(byteCount), countStyle: .file)
    }

    /// Reads the located file as UTF-8 text. Touches the disk, so call it off the main actor.
    nonisolated static func read(fileURL: URL, rootURL: URL?) -> ArchiveDayFile? {
        let didAccess = rootURL?.startAccessingSecurityScopedResource() ?? false
        defer { if didAccess { rootURL?.stopAccessingSecurityScopedResource() } }
        guard let handle = try? FileHandle(forReadingFrom: fileURL) else { return nil }
        defer { try? handle.close() }
        let size = (try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        // One look-ahead byte also identifies truncation if size metadata is unavailable.
        guard let bytes = try? (handle.read(upToCount: maximumBytes + 1) ?? Data()) else { return nil }
        let data = Data(bytes.prefix(maximumBytes))
        var source = String(data: data, encoding: .utf8)
        if source == nil, size > data.count || bytes.count > maximumBytes {
            // A UTF-8 scalar has at most four bytes. Remove only its incomplete
            // suffix, preserving every complete character and rejecting interior corruption.
            for count in 1...min(3, data.count) {
                if let decoded = String(data: data.dropLast(count), encoding: .utf8) {
                    source = decoded
                    break
                }
            }
        }
        guard let source else { return nil }
        return ArchiveDayFile(fileURL: fileURL, rootURL: rootURL, source: source, byteCount: max(size, bytes.count))
    }
}
