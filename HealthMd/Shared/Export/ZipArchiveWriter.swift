import Foundation

/// Minimal ZIP writer for export archives.
///
/// Uses the ZIP "store" method (no compression). The main win for large iCloud
/// exports is moving one archive instead of thousands of individual `.md` files.
enum ZipArchiveWriter {
    struct Entry {
        let path: String
        let data: Data

        init(path: String, data: Data) {
            self.path = ZipArchiveWriter.normalizedEntryPath(path)
            self.data = data
        }
    }

    static func write(entries: [Entry], to destinationURL: URL, fileManager: FileManager = .default) throws {
        let parentURL = destinationURL.deletingLastPathComponent()
        if !fileManager.fileExists(atPath: parentURL.path) {
            try fileManager.createDirectory(at: parentURL, withIntermediateDirectories: true)
        }

        var archive = Data()
        var centralDirectory = Data()
        let timestamp = dosTimestampComponents(for: Date())
        var writtenEntryCount: UInt16 = 0

        for entry in entries where !entry.path.isEmpty {
            guard let nameData = entry.path.data(using: .utf8) else { continue }
            let localHeaderOffset = UInt32(archive.count)
            let crc = CRC32.checksum(entry.data)
            let size = UInt32(entry.data.count)
            let nameLength = UInt16(nameData.count)

            archive.appendUInt32LE(0x04034b50) // Local file header signature
            archive.appendUInt16LE(20) // Version needed to extract
            archive.appendUInt16LE(0x0800) // UTF-8 file names
            archive.appendUInt16LE(0) // Store/no compression
            archive.appendUInt16LE(timestamp.time)
            archive.appendUInt16LE(timestamp.date)
            archive.appendUInt32LE(crc)
            archive.appendUInt32LE(size)
            archive.appendUInt32LE(size)
            archive.appendUInt16LE(nameLength)
            archive.appendUInt16LE(0) // Extra field length
            archive.append(nameData)
            archive.append(entry.data)

            centralDirectory.appendUInt32LE(0x02014b50) // Central directory signature
            centralDirectory.appendUInt16LE(20) // Version made by
            centralDirectory.appendUInt16LE(20) // Version needed to extract
            centralDirectory.appendUInt16LE(0x0800) // UTF-8 file names
            centralDirectory.appendUInt16LE(0) // Store/no compression
            centralDirectory.appendUInt16LE(timestamp.time)
            centralDirectory.appendUInt16LE(timestamp.date)
            centralDirectory.appendUInt32LE(crc)
            centralDirectory.appendUInt32LE(size)
            centralDirectory.appendUInt32LE(size)
            centralDirectory.appendUInt16LE(nameLength)
            centralDirectory.appendUInt16LE(0) // Extra field length
            centralDirectory.appendUInt16LE(0) // Comment length
            centralDirectory.appendUInt16LE(0) // Disk number start
            centralDirectory.appendUInt16LE(0) // Internal attributes
            centralDirectory.appendUInt32LE(0) // External attributes
            centralDirectory.appendUInt32LE(localHeaderOffset)
            centralDirectory.append(nameData)
            writtenEntryCount += 1
        }

        let centralDirectoryOffset = UInt32(archive.count)
        archive.append(centralDirectory)
        archive.appendUInt32LE(0x06054b50) // End of central directory signature
        archive.appendUInt16LE(0) // Disk number
        archive.appendUInt16LE(0) // Central directory start disk
        archive.appendUInt16LE(writtenEntryCount)
        archive.appendUInt16LE(writtenEntryCount)
        archive.appendUInt32LE(UInt32(centralDirectory.count))
        archive.appendUInt32LE(centralDirectoryOffset)
        archive.appendUInt16LE(0) // ZIP comment length

        let temporaryURL = parentURL.appendingPathComponent(".\(destinationURL.lastPathComponent).tmp-\(UUID().uuidString)")
        try archive.write(to: temporaryURL, options: .atomic)
        if fileManager.fileExists(atPath: destinationURL.path) {
            try fileManager.removeItem(at: destinationURL)
        }
        try fileManager.moveItem(at: temporaryURL, to: destinationURL)
    }

    private static func normalizedEntryPath(_ path: String) -> String {
        path
            .replacingOccurrences(of: "\\", with: "/")
            .split(separator: "/")
            .map(String.init)
            .filter { !$0.isEmpty && $0 != "." && $0 != ".." }
            .joined(separator: "/")
    }

    private static func dosTimestampComponents(for date: Date) -> (date: UInt16, time: UInt16) {
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: date)
        let year = max((components.year ?? 1980), 1980)
        let dosDate = UInt16(((year - 1980) << 9) | ((components.month ?? 1) << 5) | (components.day ?? 1))
        let dosTime = UInt16(((components.hour ?? 0) << 11) | ((components.minute ?? 0) << 5) | ((components.second ?? 0) / 2))
        return (dosDate, dosTime)
    }
}

private extension Data {
    mutating func appendUInt16LE(_ value: UInt16) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
    }

    mutating func appendUInt32LE(_ value: UInt32) {
        append(UInt8(value & 0xff))
        append(UInt8((value >> 8) & 0xff))
        append(UInt8((value >> 16) & 0xff))
        append(UInt8((value >> 24) & 0xff))
    }
}

private enum CRC32 {
    private static let table: [UInt32] = (0..<256).map { index in
        var crc = UInt32(index)
        for _ in 0..<8 {
            crc = (crc & 1) == 1 ? (0xedb88320 ^ (crc >> 1)) : (crc >> 1)
        }
        return crc
    }

    static func checksum(_ data: Data) -> UInt32 {
        var crc: UInt32 = 0xffffffff
        for byte in data {
            let index = Int((crc ^ UInt32(byte)) & 0xff)
            crc = table[index] ^ (crc >> 8)
        }
        return crc ^ 0xffffffff
    }
}
