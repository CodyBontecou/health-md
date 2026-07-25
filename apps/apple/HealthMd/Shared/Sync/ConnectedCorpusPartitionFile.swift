import Foundation

struct MacCorpusDerivedOutputResult {
    let rollupFileCount: Int
    let archiveFileCount: Int
}

/// Application items carried by corpus partitions. Each item is encoded and
/// spooled independently so an item may span physical partitions without
/// keeping the corpus in memory.
enum ConnectedCorpusItemKind: String, Codable, Equatable, Sendable {
    case macHealthDay = "mac_health_day"
    case strictRawDay = "strict_raw_day"
}

nonisolated struct ConnectedCorpusHealthDayPayload: Codable, Sendable {
    let sourceDate: Date
    let isRequestedDate: Bool
    let record: HealthData?
    let externalDailyRecords: [ExternalDailyRecord]
    let failure: FailedDateDetail?
}

extension ConnectedCorpusRequestFingerprint {
    static func make(for manifest: ConnectedCorpusExportManifest) throws -> Self {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let encoded = try encoder.encode(manifest)
        var parser = CanonicalFingerprintJSONParser(data: encoded)
        let data = try parser.parse()
        return Self(sha256: ConnectedTransferFile.sha256Hex(data))
    }
}

/// Canonicalizes JSONEncoder output without Foundation object bridging. Object
/// keys and array elements are recursively sorted; string/number tokens are
/// preserved byte-for-byte. This keeps set-valued settings deterministic on both
/// peers and avoids an iOS JSONSerialization bridging crash.
private struct CanonicalFingerprintJSONParser {
    private let bytes: [UInt8]
    private var index = 0

    init(data: Data) {
        bytes = Array(data)
    }

    mutating func parse() throws -> Data {
        skipWhitespace()
        let value = try parseValue(depth: 0)
        skipWhitespace()
        guard index == bytes.count else { throw CocoaError(.coderInvalidValue) }
        return value
    }

    private mutating func parseValue(depth: Int) throws -> Data {
        guard depth <= 256, index < bytes.count else { throw CocoaError(.coderInvalidValue) }
        switch bytes[index] {
        case 0x7b: return try parseObject(depth: depth + 1)
        case 0x5b: return try parseArray(depth: depth + 1)
        case 0x22: return try parseStringToken()
        case 0x74: return try parseLiteral(Array("true".utf8))
        case 0x66: return try parseLiteral(Array("false".utf8))
        case 0x6e: return try parseLiteral(Array("null".utf8))
        case 0x2d, 0x30...0x39: return try parseNumberToken()
        default: throw CocoaError(.coderInvalidValue)
        }
    }

    private mutating func parseObject(depth: Int) throws -> Data {
        try expect(0x7b)
        skipWhitespace()
        if consume(0x7d) { return Data("{}".utf8) }
        var entries: [(key: Data, value: Data)] = []
        while true {
            guard index < bytes.count, bytes[index] == 0x22 else {
                throw CocoaError(.coderInvalidValue)
            }
            let key = try parseStringToken()
            skipWhitespace()
            try expect(0x3a)
            skipWhitespace()
            entries.append((key, try parseValue(depth: depth)))
            skipWhitespace()
            if consume(0x7d) { break }
            try expect(0x2c)
            skipWhitespace()
        }
        entries.sort { $0.key.lexicographicallyPrecedes($1.key) }
        var result = Data("{".utf8)
        for (offset, entry) in entries.enumerated() {
            if offset > 0 { result.append(0x2c) }
            result.append(entry.key)
            result.append(0x3a)
            result.append(entry.value)
        }
        result.append(0x7d)
        return result
    }

    private mutating func parseArray(depth: Int) throws -> Data {
        try expect(0x5b)
        skipWhitespace()
        if consume(0x5d) { return Data("[]".utf8) }
        var elements: [Data] = []
        while true {
            elements.append(try parseValue(depth: depth))
            skipWhitespace()
            if consume(0x5d) { break }
            try expect(0x2c)
            skipWhitespace()
        }
        elements.sort { $0.lexicographicallyPrecedes($1) }
        var result = Data("[".utf8)
        for (offset, element) in elements.enumerated() {
            if offset > 0 { result.append(0x2c) }
            result.append(element)
        }
        result.append(0x5d)
        return result
    }

    private mutating func parseStringToken() throws -> Data {
        let start = index
        try expect(0x22)
        while index < bytes.count {
            let byte = bytes[index]
            index += 1
            if byte == 0x22 {
                return Data(bytes[start..<index])
            }
            guard byte >= 0x20 else { throw CocoaError(.coderInvalidValue) }
            if byte == 0x5c {
                guard index < bytes.count else { throw CocoaError(.coderInvalidValue) }
                let escaped = bytes[index]
                index += 1
                guard [0x22, 0x5c, 0x2f, 0x62, 0x66, 0x6e, 0x72, 0x74, 0x75].contains(escaped) else {
                    throw CocoaError(.coderInvalidValue)
                }
                if escaped == 0x75 {
                    guard index + 4 <= bytes.count else { throw CocoaError(.coderInvalidValue) }
                    for hex in bytes[index..<(index + 4)] {
                        guard (0x30...0x39).contains(hex)
                                || (0x41...0x46).contains(hex)
                                || (0x61...0x66).contains(hex) else {
                            throw CocoaError(.coderInvalidValue)
                        }
                    }
                    index += 4
                }
            }
        }
        throw CocoaError(.coderInvalidValue)
    }

    private mutating func parseNumberToken() throws -> Data {
        let start = index
        while index < bytes.count,
              (0x30...0x39).contains(bytes[index])
                || [0x2d, 0x2b, 0x2e, 0x45, 0x65].contains(bytes[index]) {
            index += 1
        }
        guard index > start else { throw CocoaError(.coderInvalidValue) }
        return Data(bytes[start..<index])
    }

    private mutating func parseLiteral(_ literal: [UInt8]) throws -> Data {
        guard index + literal.count <= bytes.count,
              Array(bytes[index..<(index + literal.count)]) == literal else {
            throw CocoaError(.coderInvalidValue)
        }
        index += literal.count
        return Data(literal)
    }

    private mutating func skipWhitespace() {
        while index < bytes.count, [0x20, 0x09, 0x0a, 0x0d].contains(bytes[index]) {
            index += 1
        }
    }

    private mutating func expect(_ byte: UInt8) throws {
        guard index < bytes.count, bytes[index] == byte else { throw CocoaError(.coderInvalidValue) }
        index += 1
    }

    private mutating func consume(_ byte: UInt8) -> Bool {
        guard index < bytes.count, bytes[index] == byte else { return false }
        index += 1
        return true
    }
}

struct ConnectedCorpusRawDayPayload: Codable, Equatable {
    let sourceDate: Date
    let day: CanonicalRawDayResult
}

struct ConnectedCorpusItemSegment: Codable, Equatable, Sendable {
    let itemID: UUID
    let kind: ConnectedCorpusItemKind
    let sourceDate: Date
    let isRequestedDate: Bool
    let totalItemBytes: Int64
    let itemSHA256: String
    let itemOffset: Int64
    let segmentBytes: Int64
    let isFinalSegment: Bool
}

struct ConnectedCorpusPartitionFileManifest: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let sessionID: UUID
    let jobID: UUID
    let partitionIndex: Int
    let previousPartitionSHA256: String?
    let segments: [ConnectedCorpusItemSegment]
}

struct ConnectedCorpusSpoolItem {
    let itemID: UUID
    let kind: ConnectedCorpusItemKind
    let sourceDate: Date
    let isRequestedDate: Bool
    let file: ConnectedTransferPreparedFile

    static func encode<T: Encodable>(
        _ value: T,
        kind: ConnectedCorpusItemKind,
        sourceDate: Date,
        isRequestedDate: Bool,
        itemID: UUID = UUID()
    ) throws -> Self {
        let temporaryDirectory = FileManager.default.temporaryDirectory
        guard let values = try? temporaryDirectory.resourceValues(forKeys: [
            .volumeAvailableCapacityForImportantUsageKey,
            .volumeAvailableCapacityKey
        ]),
        let available = values.volumeAvailableCapacityForImportantUsage
            ?? values.volumeAvailableCapacity.map(Int64.init),
        available >= 128 * 1_024 * 1_024 else {
            throw CocoaError(.fileWriteOutOfSpace)
        }
        let encoded = try ConnectedTransferFile.encode(value)
        guard encoded.totalBytes <= ConnectedCorpusTransferConstants.maximumItemBytes else {
            encoded.remove()
            throw ConnectedCorpusTransferModelError.invalidItemByteCount
        }
        return Self(
            itemID: itemID,
            kind: kind,
            sourceDate: sourceDate,
            isRequestedDate: isRequestedDate,
            file: encoded
        )
    }

    func remove() { file.remove() }
}

struct ConnectedCorpusPreparedPartition {
    let transferID: UUID
    let descriptor: ConnectedCorpusPartitionDescriptor
    let file: ConnectedTransferPreparedFile
    let manifest: ConnectedCorpusPartitionFileManifest

    func remove() { file.remove() }
}

/// Disk-backed partition assembler. It retains only item spool URLs and small
/// descriptors; item bytes are copied to a bounded partition file in 1 MiB
/// windows. A single dense day can therefore span several physical partitions.
final class ConnectedCorpusPartitionAssembler {
    private struct PendingItem {
        let item: ConnectedCorpusSpoolItem
        var offset: Int64
    }

    fileprivate static let headerMagic = Data("HMDCORP1".utf8)
    fileprivate static let maximumManifestBytes = 1 * 1_024 * 1_024
    /// Keeps even worst-case JSON segment metadata comfortably below the 1 MiB
    /// wire-manifest ceiling when a corpus contains thousands of tiny days.
    fileprivate static let maximumSegmentsPerPartition = 1_024
    fileprivate static let copyBufferBytes = 1 * 1_024 * 1_024

    let sessionID: UUID
    let jobID: UUID
    let targetBytes: Int64
    private(set) var nextPartitionIndex: Int
    private(set) var previousPartitionSHA256: String?
    private(set) var totalPartitionBytes: Int64 = 0
    private var pending: [PendingItem] = []

    init(
        sessionID: UUID,
        jobID: UUID,
        targetBytes: Int64,
        nextPartitionIndex: Int = 0,
        previousPartitionSHA256: String? = nil
    ) throws {
        let validTargetRange = ConnectedCorpusTransferConstants.minimumPartitionTargetBytes...ConnectedCorpusTransferConstants.maximumPartitionTargetBytes
        guard validTargetRange.contains(targetBytes),
              nextPartitionIndex >= 0,
              (nextPartitionIndex == 0) == (previousPartitionSHA256 == nil) else {
            throw ConnectedCorpusTransferModelError.invalidPartitionTarget
        }
        self.sessionID = sessionID
        self.jobID = jobID
        self.targetBytes = targetBytes
        self.nextPartitionIndex = nextPartitionIndex
        self.previousPartitionSHA256 = previousPartitionSHA256
    }

    deinit {
        pending.forEach { $0.item.remove() }
    }

    var hasPendingItems: Bool { !pending.isEmpty }

    var bufferedItemBytes: Int64 {
        pending.reduce(0) { $0 + max(0, $1.item.file.totalBytes - $1.offset) }
    }

    var shouldFlush: Bool {
        bufferedItemBytes >= payloadTargetBytes
            || pending.count >= Self.maximumSegmentsPerPartition
    }

    func append(_ item: ConnectedCorpusSpoolItem) {
        pending.append(PendingItem(item: item, offset: 0))
    }

    func abandon() {
        pending.forEach { $0.item.remove() }
        pending.removeAll()
    }

    /// Returns the next partition when the target is reached, or when force is
    /// true for the final smaller partition.
    func makeNextPartition(force: Bool = false) throws -> ConnectedCorpusPreparedPartition? {
        guard !pending.isEmpty, force || shouldFlush else { return nil }
        guard pending.allSatisfy({
            $0.item.file.totalBytes > 0
                && $0.item.file.totalBytes <= ConnectedCorpusTransferConstants.maximumItemBytes
        }) else {
            throw ConnectedCorpusTransferModelError.invalidItemByteCount
        }

        var remainingBudget = payloadTargetBytes
        var selected: [(pendingIndex: Int, segment: ConnectedCorpusItemSegment)] = []
        for index in pending.indices {
            guard remainingBudget > 0,
                  selected.count < Self.maximumSegmentsPerPartition else { break }
            let entry = pending[index]
            let remainingItemBytes = entry.item.file.totalBytes - entry.offset
            guard remainingItemBytes > 0 else { continue }
            let segmentBytes = min(remainingItemBytes, remainingBudget)
            let segment = ConnectedCorpusItemSegment(
                itemID: entry.item.itemID,
                kind: entry.item.kind,
                sourceDate: entry.item.sourceDate,
                isRequestedDate: entry.item.isRequestedDate,
                totalItemBytes: entry.item.file.totalBytes,
                itemSHA256: entry.item.file.sha256,
                itemOffset: entry.offset,
                segmentBytes: segmentBytes,
                isFinalSegment: entry.offset + segmentBytes == entry.item.file.totalBytes
            )
            selected.append((index, segment))
            remainingBudget -= segmentBytes
        }
        guard !selected.isEmpty else { return nil }

        let manifest = ConnectedCorpusPartitionFileManifest(
            version: ConnectedCorpusPartitionFileManifest.currentVersion,
            sessionID: sessionID,
            jobID: jobID,
            partitionIndex: nextPartitionIndex,
            previousPartitionSHA256: previousPartitionSHA256,
            segments: selected.map(\.segment)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifestData = try encoder.encode(manifest)
        guard manifestData.count <= Self.maximumManifestBytes else {
            throw ConnectedCorpusTransferModelError.invalidPartitionByteCount
        }

        let outputURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "corpus-partition")
        do {
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }
            try output.write(contentsOf: Self.headerMagic)
            try output.write(contentsOf: Self.uint32BigEndian(UInt32(manifestData.count)))
            try output.write(contentsOf: manifestData)

            for selection in selected {
                let source = pending[selection.pendingIndex].item.file.url
                try Self.copyRange(
                    from: source,
                    offset: selection.segment.itemOffset,
                    count: selection.segment.segmentBytes,
                    to: output
                )
            }
            try output.synchronize()
            try output.close()

            let inspected = try ConnectedTransferFile.inspect(outputURL)
            guard inspected.totalBytes <= ConnectedCorpusTransferConstants.maximumPartitionTargetBytes else {
                throw ConnectedCorpusTransferModelError.invalidPartitionByteCount
            }
            let sourceDates = Array(Set(selected.map(\.segment.sourceDate))).sorted()
            let descriptor = ConnectedCorpusPartitionDescriptor(
                sessionID: sessionID,
                jobID: jobID,
                index: nextPartitionIndex,
                sourceDates: sourceDates,
                byteCount: inspected.totalBytes,
                sha256: inspected.sha256,
                previousSHA256: previousPartitionSHA256
            )
            try descriptor.validate()

            // Advance only after the complete partition and descriptor are durable.
            for selection in selected {
                pending[selection.pendingIndex].offset += selection.segment.segmentBytes
            }
            let completedIDs = Set(pending.filter { $0.offset == $0.item.file.totalBytes }.map { $0.item.itemID })
            for entry in pending where completedIDs.contains(entry.item.itemID) { entry.item.remove() }
            pending.removeAll { completedIDs.contains($0.item.itemID) }
            nextPartitionIndex += 1
            previousPartitionSHA256 = inspected.sha256
            totalPartitionBytes += inspected.totalBytes

            return ConnectedCorpusPreparedPartition(
                transferID: UUID(),
                descriptor: descriptor,
                file: inspected,
                manifest: manifest
            )
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    fileprivate var payloadTargetBytes: Int64 {
        // Reserve room for the fixed header and a worst-case bounded manifest.
        min(
            targetBytes - Int64(Self.maximumManifestBytes),
            ConnectedCorpusTransferConstants.maximumPartitionTargetBytes - Int64(Self.maximumManifestBytes)
        )
    }

    fileprivate static func copyRange(
        from sourceURL: URL,
        offset: Int64,
        count: Int64,
        to output: FileHandle
    ) throws {
        let source = try FileHandle(forReadingFrom: sourceURL)
        defer { try? source.close() }
        try source.seek(toOffset: UInt64(offset))
        var remaining = count
        while remaining > 0 {
            let requested = Int(min(Int64(copyBufferBytes), remaining))
            guard let data = try source.read(upToCount: requested), !data.isEmpty else {
                throw CocoaError(.fileReadCorruptFile)
            }
            try output.write(contentsOf: data)
            remaining -= Int64(data.count)
        }
    }

    fileprivate static func uint32BigEndian(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff), UInt8(value & 0xff)
        ])
    }
}

/// Non-mutating partition construction used by durable outbound sessions. The
/// caller advances item offsets only after the Mac has durably acknowledged the
/// returned descriptor, so a process crash can replay these exact bytes.
enum ConnectedCorpusDurablePartitionBuilder {
    struct Source {
        let item: ConnectedCorpusSpoolItem
        let offset: Int64
    }

    static func shouldFlush(sources: [Source], targetBytes: Int64) -> Bool {
        bufferedBytes(sources) >= payloadTargetBytes(for: targetBytes)
            || sources.count >= ConnectedCorpusPartitionAssembler.maximumSegmentsPerPartition
    }

    static func bufferedBytes(_ sources: [Source]) -> Int64 {
        sources.reduce(0) { result, source in
            result + max(0, source.item.file.totalBytes - source.offset)
        }
    }

    static func prepare(
        sessionID: UUID,
        jobID: UUID,
        targetBytes: Int64,
        partitionIndex: Int,
        previousPartitionSHA256: String?,
        sources: [Source],
        transferID: UUID = UUID()
    ) throws -> ConnectedCorpusPreparedPartition {
        let validTargetRange = ConnectedCorpusTransferConstants.minimumPartitionTargetBytes
            ... ConnectedCorpusTransferConstants.maximumPartitionTargetBytes
        guard validTargetRange.contains(targetBytes),
              partitionIndex >= 0,
              (partitionIndex == 0) == (previousPartitionSHA256 == nil),
              !sources.isEmpty,
              sources.allSatisfy({ source in
                  source.item.file.totalBytes > 0
                      && source.item.file.totalBytes <= ConnectedCorpusTransferConstants.maximumItemBytes
                      && source.offset >= 0
                      && source.offset < source.item.file.totalBytes
              }) else {
            throw ConnectedCorpusTransferModelError.invalidPartitionTarget
        }

        var remainingBudget = payloadTargetBytes(for: targetBytes)
        var selected: [(source: Source, segment: ConnectedCorpusItemSegment)] = []
        for source in sources {
            guard remainingBudget > 0,
                  selected.count < ConnectedCorpusPartitionAssembler.maximumSegmentsPerPartition else {
                break
            }
            let remainingItemBytes = source.item.file.totalBytes - source.offset
            let segmentBytes = min(remainingItemBytes, remainingBudget)
            let segment = ConnectedCorpusItemSegment(
                itemID: source.item.itemID,
                kind: source.item.kind,
                sourceDate: source.item.sourceDate,
                isRequestedDate: source.item.isRequestedDate,
                totalItemBytes: source.item.file.totalBytes,
                itemSHA256: source.item.file.sha256,
                itemOffset: source.offset,
                segmentBytes: segmentBytes,
                isFinalSegment: source.offset + segmentBytes == source.item.file.totalBytes
            )
            selected.append((source, segment))
            remainingBudget -= segmentBytes
        }
        guard !selected.isEmpty else {
            throw ConnectedCorpusTransferModelError.invalidPartitionByteCount
        }

        let manifest = ConnectedCorpusPartitionFileManifest(
            version: ConnectedCorpusPartitionFileManifest.currentVersion,
            sessionID: sessionID,
            jobID: jobID,
            partitionIndex: partitionIndex,
            previousPartitionSHA256: previousPartitionSHA256,
            segments: selected.map(\.segment)
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let manifestData = try encoder.encode(manifest)
        guard manifestData.count <= ConnectedCorpusPartitionAssembler.maximumManifestBytes else {
            throw ConnectedCorpusTransferModelError.invalidPartitionByteCount
        }

        let outputURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(
            prefix: "durable-corpus-partition"
        )
        do {
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }
            try output.write(contentsOf: ConnectedCorpusPartitionAssembler.headerMagic)
            try output.write(contentsOf: ConnectedCorpusPartitionAssembler.uint32BigEndian(
                UInt32(manifestData.count)
            ))
            try output.write(contentsOf: manifestData)
            for selection in selected {
                try ConnectedCorpusPartitionAssembler.copyRange(
                    from: selection.source.item.file.url,
                    offset: selection.segment.itemOffset,
                    count: selection.segment.segmentBytes,
                    to: output
                )
            }
            try output.synchronize()
            try output.close()

            let inspected = try ConnectedTransferFile.inspect(outputURL)
            guard inspected.totalBytes <= ConnectedCorpusTransferConstants.maximumPartitionTargetBytes else {
                throw ConnectedCorpusTransferModelError.invalidPartitionByteCount
            }
            let descriptor = ConnectedCorpusPartitionDescriptor(
                sessionID: sessionID,
                jobID: jobID,
                index: partitionIndex,
                sourceDates: Array(Set(selected.map(\.segment.sourceDate))).sorted(),
                byteCount: inspected.totalBytes,
                sha256: inspected.sha256,
                previousSHA256: previousPartitionSHA256
            )
            try descriptor.validate()
            return ConnectedCorpusPreparedPartition(
                transferID: transferID,
                descriptor: descriptor,
                file: inspected,
                manifest: manifest
            )
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func payloadTargetBytes(for targetBytes: Int64) -> Int64 {
        min(
            targetBytes - Int64(ConnectedCorpusPartitionAssembler.maximumManifestBytes),
            ConnectedCorpusTransferConstants.maximumPartitionTargetBytes
                - Int64(ConnectedCorpusPartitionAssembler.maximumManifestBytes)
        )
    }
}

/// Parses and applies a verified partition without reading its complete payload
/// into memory. Item assembly files are truncated back to the declared offset on
/// replay, making an interrupted segment application restartable.
enum ConnectedCorpusPartitionReader {
    struct ParsedManifest {
        let manifest: ConnectedCorpusPartitionFileManifest
        let payloadOffset: UInt64
    }

    static func parseManifest(
        at fileURL: URL,
        expected descriptor: ConnectedCorpusPartitionDescriptor
    ) throws -> ParsedManifest {
        let inspected = try ConnectedTransferFile.inspect(fileURL)
        guard inspected.totalBytes == descriptor.byteCount,
              inspected.sha256 == descriptor.sha256 else {
            throw ConnectedCorpusTransferModelError.invalidDigest
        }
        let input = try FileHandle(forReadingFrom: fileURL)
        defer { try? input.close() }
        guard let magic = try input.read(upToCount: 8), magic == Data("HMDCORP1".utf8),
              let lengthData = try input.read(upToCount: 4), lengthData.count == 4 else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let manifestLength = lengthData.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        guard manifestLength > 0, manifestLength <= 1_048_576,
              let manifestData = try input.read(upToCount: Int(manifestLength)),
              manifestData.count == Int(manifestLength) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        let manifest = try JSONDecoder().decode(ConnectedCorpusPartitionFileManifest.self, from: manifestData)
        guard manifest.version == ConnectedCorpusPartitionFileManifest.currentVersion,
              manifest.sessionID == descriptor.sessionID,
              manifest.jobID == descriptor.jobID,
              manifest.partitionIndex == descriptor.index,
              manifest.previousPartitionSHA256 == descriptor.previousSHA256,
              !manifest.segments.isEmpty,
              Array(Set(manifest.segments.map(\.sourceDate))).sorted() == descriptor.sourceDates else {
            throw ConnectedCorpusTransferModelError.mismatchedSession
        }
        var declaredPayloadBytes: Int64 = 0
        var seenItemIDs: Set<UUID> = []
        for segment in manifest.segments {
            let segmentEnd = segment.itemOffset.addingReportingOverflow(segment.segmentBytes)
            let payloadSum = declaredPayloadBytes.addingReportingOverflow(segment.segmentBytes)
            guard !segmentEnd.overflow,
                  !payloadSum.overflow,
                  segment.totalItemBytes > 0,
                  segment.totalItemBytes <= ConnectedCorpusTransferConstants.maximumItemBytes,
                  segment.itemOffset >= 0,
                  segment.segmentBytes > 0,
                  segmentEnd.partialValue <= segment.totalItemBytes,
                  segment.isFinalSegment == (segmentEnd.partialValue == segment.totalItemBytes),
                  segment.itemSHA256.isConnectedCorpusSHA256,
                  seenItemIDs.insert(segment.itemID).inserted else {
                throw ConnectedCorpusTransferModelError.invalidPartitionByteCount
            }
            declaredPayloadBytes = payloadSum.partialValue
        }
        let payloadOffset = UInt64(12 + manifestData.count)
        let totalBytes = Int64(payloadOffset).addingReportingOverflow(declaredPayloadBytes)
        guard !totalBytes.overflow,
              totalBytes.partialValue == descriptor.byteCount else {
            throw ConnectedCorpusTransferModelError.invalidPartitionByteCount
        }
        return ParsedManifest(manifest: manifest, payloadOffset: payloadOffset)
    }

    /// Appends each segment to the URL returned by destinationURL. The callback
    /// receives an item only after its full byte count and SHA-256 validate.
    static func applySegments(
        from partitionURL: URL,
        parsed: ParsedManifest,
        destinationURL: (ConnectedCorpusItemSegment) throws -> URL,
        completedItem: (ConnectedCorpusItemSegment, URL) throws -> Void
    ) throws {
        let input = try FileHandle(forReadingFrom: partitionURL)
        defer { try? input.close() }
        try input.seek(toOffset: parsed.payloadOffset)

        for segment in parsed.manifest.segments {
            let targetURL = try destinationURL(segment)
            if !FileManager.default.fileExists(atPath: targetURL.path) {
                guard segment.itemOffset == 0,
                      FileManager.default.createFile(
                        atPath: targetURL.path,
                        contents: nil,
                        attributes: [.posixPermissions: 0o600]
                      ) else { throw CocoaError(.fileWriteUnknown) }
            } else {
                let attributes = try FileManager.default.attributesOfItem(atPath: targetURL.path)
                guard let currentSize = attributes[.size] as? NSNumber,
                      currentSize.int64Value >= segment.itemOffset else {
                    throw ConnectedCorpusTransferModelError.invalidPartitionByteCount
                }
            }
            let output = try FileHandle(forWritingTo: targetURL)
            do {
                try output.truncate(atOffset: UInt64(segment.itemOffset))
                try output.seekToEnd()
                var remaining = segment.segmentBytes
                while remaining > 0 {
                    let requested = Int(min(Int64(1_048_576), remaining))
                    guard let data = try input.read(upToCount: requested), !data.isEmpty else {
                        throw CocoaError(.fileReadCorruptFile)
                    }
                    try output.write(contentsOf: data)
                    remaining -= Int64(data.count)
                }
                try output.synchronize()
                try output.close()
            } catch {
                try? output.close()
                throw error
            }

            if segment.isFinalSegment {
                let inspected = try ConnectedTransferFile.inspect(targetURL)
                guard inspected.totalBytes == segment.totalItemBytes,
                      inspected.sha256 == segment.itemSHA256 else {
                    throw ConnectedCorpusTransferModelError.invalidDigest
                }
                try completedItem(segment, targetURL)
            }
        }
    }
}
