import CryptoKit
import Darwin
import Foundation

/// V4 connected-corpus application items use a disk-backed Codable token stream.
/// Corpus protocol v1-v3 intentionally retain their historical sorted JSON bytes.
nonisolated enum ConnectedCorpusApplicationItemCodec {
    static let formatVersion: UInt16 = 1
    static let headerBytes = 12
    private static let magic = Data("HMDCITEM".utf8)
    private static let maximumDepth = 128
    private static let maximumObjectKeys = 16_384
    private static let maximumKeyBytes = 4_096
    fileprivate static let copyBufferBytes = 256 * 1_024
    private static let inlineNodeBytes = 256 * 1_024
    /// Aggregate retained token bodies stay fixed while allowing ordinary day
    /// graphs to finish in memory instead of cascading through thousands of
    /// tiny temporary files. Individual nodes remain capped at 256 KiB.
    private static let inlineGraphBytes = 16 * 1_024 * 1_024

    enum CodecError: Error, Equatable {
        case invalidHeader
        case invalidKind
        case malformedToken
        case unsupportedValue
        case excessiveDepth
        case excessiveObjectKeys
        case duplicateKey
        case invalidUTF8
        case invalidNumber
        case trailingBytes
    }

    struct DecodedRawDay {
        let sourceDate: Date
        /// Metadata only. `canonicalDailyJSON` is nil when a canonical token was present.
        let day: CanonicalRawDayResult
        let canonicalJSONFile: ConnectedTransferPreparedFile?
        let hasCanonicalJSON: Bool
    }

    static func usesStreamableItems(protocolVersion: Int) -> Bool {
        protocolVersion >= ConnectedCorpusTransferCapabilities.streamableItemProtocolVersion
    }

    static func encode<T: Encodable>(
        _ value: T,
        kind: ConnectedCorpusItemKind
    ) throws -> ConnectedTransferPreparedFile {
        try Task.checkCancellation()
        let root = try TokenEncoder.encode(value, codingPath: [], depth: 0)
        defer { root.remove() }
        let outputURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(
            prefix: "corpus-application-item"
        )
        do {
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }
            try write(magic, to: output)
            try write(uint16BigEndian(formatVersion), to: output)
            try write(Data([kindByte(kind), 0]), to: output)
            try root.write(to: output)
            try Task.checkCancellation()
            try output.synchronize()
            try output.close()
            return try ConnectedTransferFile.inspect(outputURL)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    @MainActor
    static func encodeRawDay(
        sourceDate: Date,
        day: CanonicalRawDayResult,
        canonicalJSONFile: ConnectedTransferPreparedFile
    ) throws -> ConnectedTransferPreparedFile {
        let inspected = try ConnectedTransferFile.inspect(canonicalJSONFile.url)
        guard inspected.totalBytes == canonicalJSONFile.totalBytes,
              inspected.sha256 == canonicalJSONFile.sha256,
              inspected.totalBytes > 0 else {
            throw CodecError.malformedToken
        }
        return try encode(
            RawDayPayloadProxy(
                sourceDate: sourceDate,
                day: RawDayProxy(
                    day: day,
                    canonicalJSON: FileBackedUTF8String(file: canonicalJSONFile)
                )
            ),
            kind: .strictRawDay
        )
    }

    static func decode<T: Decodable>(
        _ type: T.Type,
        from fileURL: URL,
        expectedKind: ConnectedCorpusItemKind
    ) throws -> T {
        let source = try TokenSource(fileURL: fileURL)
        defer { source.close() }
        return try decode(type, source: source, expectedKind: expectedKind)
    }

    static func decode<T: Decodable>(
        _ type: T.Type,
        fromFileDescriptor fileDescriptor: Int32,
        expectedKind: ConnectedCorpusItemKind
    ) throws -> T {
        let source = try TokenSource(fileDescriptor: fileDescriptor)
        defer { source.close() }
        return try decode(type, source: source, expectedKind: expectedKind)
    }

    /// Decodes strict-raw metadata while optionally copying the potentially very
    /// large `canonical_daily_json` string payload directly to a restricted file.
    @MainActor
    static func decodeRawDay(
        from fileURL: URL,
        extractCanonicalJSON: Bool = true
    ) throws -> DecodedRawDay {
        let source = try TokenSource(fileURL: fileURL)
        defer { source.close() }
        return try decodeRawDay(source: source, extractCanonicalJSON: extractCanonicalJSON)
    }

    @MainActor
    static func decodeRawDay(
        fromFileDescriptor fileDescriptor: Int32,
        extractCanonicalJSON: Bool = true
    ) throws -> DecodedRawDay {
        let source = try TokenSource(fileDescriptor: fileDescriptor)
        defer { source.close() }
        return try decodeRawDay(source: source, extractCanonicalJSON: extractCanonicalJSON)
    }

    @MainActor
    private static func decodeRawDay(
        source: TokenSource,
        extractCanonicalJSON: Bool
    ) throws -> DecodedRawDay {
        let root = try validatedRoot(source: source, expectedKind: .strictRawDay)
        let rootDecoder = TokenDecoder(
            source: source,
            range: root,
            codingPath: [],
            depth: 0,
            suppressedKeyNames: ["canonical_daily_json"]
        )
        let payload = try rootDecoder.decode(ConnectedCorpusRawDayPayload.self)
        try rootDecoder.validateCompleteNode()

        let rootEntries = try TokenDecoder.objectEntries(
            source: source,
            range: root,
            depth: 0
        )
        guard let dayRange = rootEntries["day"] else { throw CodecError.malformedToken }
        let dayEntries = try TokenDecoder.objectEntries(
            source: source,
            range: dayRange,
            depth: 1
        )
        guard let canonicalRange = dayEntries["canonical_daily_json"] else {
            return DecodedRawDay(
                sourceDate: payload.sourceDate,
                day: payload.day,
                canonicalJSONFile: nil,
                hasCanonicalJSON: false
            )
        }
        let canonicalHeader = try source.nodeHeader(in: canonicalRange)
        if canonicalHeader.tag == .null {
            return DecodedRawDay(
                sourceDate: payload.sourceDate,
                day: payload.day,
                canonicalJSONFile: nil,
                hasCanonicalJSON: false
            )
        }
        guard canonicalHeader.tag == .string else { throw CodecError.malformedToken }
        guard extractCanonicalJSON else {
            return DecodedRawDay(
                sourceDate: payload.sourceDate,
                day: payload.day,
                canonicalJSONFile: nil,
                hasCanonicalJSON: true
            )
        }
        let outputURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(
            prefix: "corpus-canonical-day"
        )
        do {
            let output = try FileHandle(forWritingTo: outputURL)
            defer { try? output.close() }
            try source.copy(
                offset: canonicalHeader.payloadOffset,
                count: canonicalHeader.payloadLength,
                to: output,
                validateUTF8: true
            )
            try output.synchronize()
            try output.close()
            let inspected = try ConnectedTransferFile.inspect(outputURL)
            return DecodedRawDay(
                sourceDate: payload.sourceDate,
                day: payload.day,
                canonicalJSONFile: inspected,
                hasCanonicalJSON: true
            )
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private static func decode<T: Decodable>(
        _ type: T.Type,
        source: TokenSource,
        expectedKind: ConnectedCorpusItemKind
    ) throws -> T {
        let root = try validatedRoot(source: source, expectedKind: expectedKind)
        let decoder = TokenDecoder(source: source, range: root, codingPath: [], depth: 0)
        let value = try decoder.decode(type)
        try decoder.validateCompleteNode()
        return value
    }

    static func validateHeader(
        at fileURL: URL,
        expectedKind: ConnectedCorpusItemKind
    ) throws {
        let source = try TokenSource(fileURL: fileURL)
        defer { source.close() }
        _ = try validatedRoot(source: source, expectedKind: expectedKind)
    }

    private static func validatedRoot(
        source: TokenSource,
        expectedKind: ConnectedCorpusItemKind
    ) throws -> FileRange {
        guard source.byteCount > Int64(headerBytes),
              try source.read(offset: 0, count: 8) == magic,
              try source.readUInt16(offset: 8) == formatVersion,
              try source.readByte(offset: 10) == kindByte(expectedKind),
              try source.readByte(offset: 11) == 0 else {
            throw CodecError.invalidHeader
        }
        let root = FileRange(
            offset: Int64(headerBytes),
            length: source.byteCount - Int64(headerBytes)
        )
        _ = try source.nodeHeader(in: root)
        return root
    }

    private static func kindByte(_ kind: ConnectedCorpusItemKind) -> UInt8 {
        switch kind {
        case .macHealthDay: return 1
        case .strictRawDay: return 2
        }
    }

    fileprivate static func uint16BigEndian(_ value: UInt16) -> Data {
        Data([UInt8((value >> 8) & 0xff), UInt8(value & 0xff)])
    }

    fileprivate static func uint32BigEndian(_ value: UInt32) -> Data {
        Data([
            UInt8((value >> 24) & 0xff), UInt8((value >> 16) & 0xff),
            UInt8((value >> 8) & 0xff), UInt8(value & 0xff)
        ])
    }

    fileprivate static func uint64BigEndian(_ value: UInt64) -> Data {
        Data((0..<8).map { shift in
            UInt8((value >> UInt64((7 - shift) * 8)) & 0xff)
        })
    }

    fileprivate static func copyFile(
        _ url: URL,
        to output: FileHandle,
        expected: ConnectedTransferPreparedFile? = nil
    ) throws {
        let inputDescriptor = Darwin.open(url.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
        guard inputDescriptor >= 0 else { throw CocoaError(.fileReadNoSuchFile) }
        defer { Darwin.close(inputDescriptor) }
        var initial = stat()
        guard Darwin.fstat(inputDescriptor, &initial) == 0,
              initial.st_mode & S_IFMT == S_IFREG,
              initial.st_nlink == 1,
              initial.st_size >= 0,
              expected.map({ $0.totalBytes == Int64(initial.st_size) }) ?? true else {
            throw CocoaError(.fileReadCorruptFile)
        }
        var hasher = SHA256()
        var copied: Int64 = 0
        var buffer = [UInt8](repeating: 0, count: copyBufferBytes)
        while true {
            try Task.checkCancellation()
            let count = buffer.withUnsafeMutableBytes {
                Darwin.read(inputDescriptor, $0.baseAddress, $0.count)
            }
            if count < 0, errno == EINTR { continue }
            guard count >= 0 else { throw CocoaError(.fileReadUnknown) }
            if count == 0 { break }
            let next = copied.addingReportingOverflow(Int64(count))
            guard !next.overflow,
                  expected.map({ next.partialValue <= $0.totalBytes }) ?? true else {
                throw CocoaError(.fileReadCorruptFile)
            }
            let data = Data(buffer[0..<count])
            if expected != nil { hasher.update(data: data) }
            try write(data, to: output)
            copied = next.partialValue
        }
        var final = stat()
        guard Darwin.fstat(inputDescriptor, &final) == 0,
              final.st_mode & S_IFMT == S_IFREG,
              final.st_nlink == 1,
              initial.st_dev == final.st_dev,
              initial.st_ino == final.st_ino,
              initial.st_size == final.st_size,
              copied == Int64(final.st_size) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        if let expected {
            let digest = hasher.finalize().map { String(format: "%02x", $0) }.joined()
            guard copied == expected.totalBytes, digest == expected.sha256 else {
                throw CocoaError(.fileReadCorruptFile)
            }
        }
    }

    fileprivate static func write(_ data: Data, to output: FileHandle) throws {
        try data.withUnsafeBytes { bytes in
            guard let baseAddress = bytes.baseAddress else { return }
            var offset = 0
            while offset < bytes.count {
                let count = Darwin.write(
                    output.fileDescriptor,
                    baseAddress.advanced(by: offset),
                    bytes.count - offset
                )
                if count < 0, errno == EINTR { continue }
                guard count > 0 else { throw CocoaError(.fileWriteUnknown) }
                offset += count
            }
        }
    }

    fileprivate static func write(
        _ bytes: UnsafeBufferPointer<UInt8>,
        to output: FileHandle
    ) throws {
        guard let baseAddress = bytes.baseAddress else { return }
        var offset = 0
        while offset < bytes.count {
            let count = Darwin.write(
                output.fileDescriptor,
                baseAddress.advanced(by: offset),
                bytes.count - offset
            )
            if count < 0, errno == EINTR { continue }
            guard count > 0 else { throw CocoaError(.fileWriteUnknown) }
            offset += count
        }
    }

    fileprivate struct FileRange: Equatable {
        let offset: Int64
        let length: Int64
    }

    private struct FileBackedUTF8String: Encodable {
        let file: ConnectedTransferPreparedFile

        func encode(to _: Encoder) throws {
            throw CodecError.unsupportedValue
        }
    }

    private struct RawDayPayloadProxy: Encodable {
        let sourceDate: Date
        let day: RawDayProxy
    }

    private struct RawDayProxy: Encodable {
        let day: CanonicalRawDayResult
        let canonicalJSON: FileBackedUTF8String

        private enum CodingKeys: String, CodingKey {
            case date
            case status
            case captureStatus = "capture_status"
            case sampleCount = "sample_count"
            case recordCount = "record_count"
            case queryStatusCounts = "query_status_counts"
            case integrityWarningCount = "integrity_warning_count"
            case integrityWarningCodes = "integrity_warning_codes"
            case partialFailureCount = "partial_failure_count"
            case partialFailureTypes = "partial_failure_types"
            case failureCode = "failure_code"
            case canonicalDailyJSON = "canonical_daily_json"
        }

        func encode(to encoder: Encoder) throws {
            var container = encoder.container(keyedBy: CodingKeys.self)
            try container.encode(day.date, forKey: .date)
            try container.encode(day.status, forKey: .status)
            try container.encodeIfPresent(day.captureStatus, forKey: .captureStatus)
            try container.encode(day.sampleCount, forKey: .sampleCount)
            try container.encode(day.recordCount, forKey: .recordCount)
            try container.encode(day.queryStatusCounts, forKey: .queryStatusCounts)
            try container.encode(day.integrityWarningCount, forKey: .integrityWarningCount)
            try container.encode(day.integrityWarningCodes, forKey: .integrityWarningCodes)
            try container.encode(day.partialFailureCount, forKey: .partialFailureCount)
            try container.encode(day.partialFailureTypes, forKey: .partialFailureTypes)
            try container.encodeIfPresent(day.failureCode, forKey: .failureCode)
            try container.encode(canonicalJSON, forKey: .canonicalDailyJSON)
        }
    }

    fileprivate enum Tag: UInt8 {
        case object = 1
        case array = 2
        case null = 3
        case boolean = 4
        case signedInteger = 5
        case unsignedInteger = 6
        case double = 7
        case string = 8
        case data = 9
        case date = 10
    }

    fileprivate struct NodeHeader {
        let tag: Tag
        let payloadOffset: Int64
        let payloadLength: Int64
    }

    fileprivate struct TemporaryNode {
        enum Storage {
            case inline(Data)
            case file(URL)
        }

        let storage: Storage
        let byteCount: Int64

        init(url: URL, byteCount: Int64) {
            storage = .file(url)
            self.byteCount = byteCount
        }

        init(data: Data) {
            storage = .inline(data)
            byteCount = Int64(data.count)
        }

        var inlineData: Data? {
            if case .inline(let data) = storage { return data }
            return nil
        }

        func write(to output: FileHandle) throws {
            switch storage {
            case .inline(let data): try ConnectedCorpusApplicationItemCodec.write(data, to: output)
            case .file(let url): try ConnectedCorpusApplicationItemCodec.copyFile(url, to: output)
            }
        }

        func remove() {
            if case .file(let url) = storage {
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    fileprivate final class TokenSource {
        private var descriptor: Int32
        let byteCount: Int64

        init(fileURL: URL) throws {
            descriptor = Darwin.open(fileURL.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
            guard descriptor >= 0 else { throw CocoaError(.fileReadNoSuchFile) }
            var metadata = stat()
            guard Darwin.fstat(descriptor, &metadata) == 0,
                  metadata.st_mode & S_IFMT == S_IFREG,
                  metadata.st_nlink == 1,
                  metadata.st_size >= 0 else {
                Darwin.close(descriptor)
                descriptor = -1
                throw CocoaError(.fileReadCorruptFile)
            }
            byteCount = metadata.st_size
        }

        init(fileDescriptor: Int32) throws {
            descriptor = Darwin.dup(fileDescriptor)
            guard descriptor >= 0 else { throw CocoaError(.fileReadUnknown) }
            var metadata = stat()
            guard Darwin.fstat(descriptor, &metadata) == 0,
                  metadata.st_mode & S_IFMT == S_IFREG,
                  metadata.st_nlink == 1,
                  metadata.st_size >= 0 else {
                Darwin.close(descriptor)
                descriptor = -1
                throw CocoaError(.fileReadCorruptFile)
            }
            byteCount = metadata.st_size
        }

        func close() {
            if descriptor >= 0 {
                Darwin.close(descriptor)
                descriptor = -1
            }
        }

        deinit { close() }

        func readByte(offset: Int64) throws -> UInt8 {
            let data = try read(offset: offset, count: 1)
            guard let byte = data.first else { throw CodecError.malformedToken }
            return byte
        }

        func readUInt16(offset: Int64) throws -> UInt16 {
            let bytes = try read(offset: offset, count: 2)
            return bytes.reduce(UInt16(0)) { ($0 << 8) | UInt16($1) }
        }

        func readUInt32(offset: Int64) throws -> UInt32 {
            let bytes = try read(offset: offset, count: 4)
            return bytes.reduce(UInt32(0)) { ($0 << 8) | UInt32($1) }
        }

        func readUInt64(offset: Int64) throws -> UInt64 {
            let bytes = try read(offset: offset, count: 8)
            return bytes.reduce(UInt64(0)) { ($0 << 8) | UInt64($1) }
        }

        func read(offset: Int64, count: Int) throws -> Data {
            guard offset >= 0, count >= 0 else { throw CodecError.malformedToken }
            let end = offset.addingReportingOverflow(Int64(count))
            guard !end.overflow, end.partialValue <= byteCount else {
                throw CodecError.malformedToken
            }
            var data = Data(count: count)
            var completed = 0
            while completed < count {
                let readCount = data.withUnsafeMutableBytes { bytes in
                    Darwin.pread(
                        descriptor,
                        bytes.baseAddress?.advanced(by: completed),
                        count - completed,
                        off_t(offset + Int64(completed))
                    )
                }
                if readCount < 0, errno == EINTR { continue }
                guard readCount > 0 else { throw CodecError.malformedToken }
                completed += readCount
            }
            return data
        }

        func mappedData(offset: Int64, count: Int) throws -> Data {
            guard offset >= 0, count >= 0 else { throw CodecError.malformedToken }
            let end = offset.addingReportingOverflow(Int64(count))
            guard !end.overflow, end.partialValue <= byteCount else {
                throw CodecError.malformedToken
            }
            guard count > 0 else { return Data() }
            let pageSize = Int64(Darwin.getpagesize())
            let alignedOffset = offset - (offset % pageSize)
            let delta = offset - alignedOffset
            let mappingLength = delta.addingReportingOverflow(Int64(count))
            guard !mappingLength.overflow,
                  mappingLength.partialValue <= Int64(Int.max) else {
                throw CodecError.malformedToken
            }
            let length = Int(mappingLength.partialValue)
            let mapping = Darwin.mmap(
                nil,
                length,
                PROT_READ,
                MAP_PRIVATE,
                descriptor,
                off_t(alignedOffset)
            )
            guard mapping != MAP_FAILED, let mapping else {
                throw CocoaError(.fileReadUnknown)
            }
            let bytes = mapping.advanced(by: Int(delta))
            return Data(
                bytesNoCopy: bytes,
                count: count,
                deallocator: .custom { _, _ in
                    _ = Darwin.munmap(mapping, length)
                }
            )
        }

        func decodeUTF8String(offset: Int64, count: Int) throws -> String {
            guard offset >= 0, count >= 0 else { throw CodecError.malformedToken }
            let end = offset.addingReportingOverflow(Int64(count))
            guard !end.overflow, end.partialValue <= byteCount else {
                throw CodecError.malformedToken
            }
            var result = String()
            result.reserveCapacity(count)
            var validator = UTF8Validator()
            var pending = Data()
            var cursor = offset
            var remaining = count
            while remaining > 0 {
                let chunkCount = min(copyBufferBytes, remaining)
                let chunk = try read(offset: cursor, count: chunkCount)
                try validator.consume(chunk)
                var combined = pending
                combined.append(chunk)
                let completeCount = Self.completeUTF8PrefixLength(combined)
                if completeCount > 0 {
                    result.append(String(decoding: combined.prefix(completeCount), as: UTF8.self))
                }
                pending = Data(combined.dropFirst(completeCount))
                guard pending.count <= 3 else { throw CodecError.invalidUTF8 }
                cursor += Int64(chunkCount)
                remaining -= chunkCount
            }
            try validator.finish()
            guard pending.isEmpty else { throw CodecError.invalidUTF8 }
            return result
        }

        private static func completeUTF8PrefixLength(_ data: Data) -> Int {
            guard !data.isEmpty else { return 0 }
            var leadIndex = data.count - 1
            while leadIndex > 0, (0x80...0xbf).contains(data[leadIndex]) {
                leadIndex -= 1
            }
            let lead = data[leadIndex]
            let expectedLength: Int
            switch lead {
            case 0x00...0x7f: expectedLength = 1
            case 0xc2...0xdf: expectedLength = 2
            case 0xe0...0xef: expectedLength = 3
            case 0xf0...0xf4: expectedLength = 4
            default: return data.count
            }
            return data.count - leadIndex < expectedLength ? leadIndex : data.count
        }

        func nodeHeader(in range: FileRange) throws -> NodeHeader {
            guard range.length >= 9,
                  let tag = Tag(rawValue: try readByte(offset: range.offset)) else {
                throw CodecError.malformedToken
            }
            let lengthValue = try readUInt64(offset: range.offset + 1)
            guard lengthValue <= UInt64(Int64.max) else { throw CodecError.malformedToken }
            let payloadLength = Int64(lengthValue)
            let total = payloadLength.addingReportingOverflow(9)
            guard !total.overflow, total.partialValue == range.length else {
                throw CodecError.trailingBytes
            }
            return NodeHeader(
                tag: tag,
                payloadOffset: range.offset + 9,
                payloadLength: payloadLength
            )
        }

        func copy(
            offset: Int64,
            count: Int64,
            to output: FileHandle,
            validateUTF8: Bool = false
        ) throws {
            guard count >= 0 else { throw CodecError.malformedToken }
            let end = offset.addingReportingOverflow(count)
            guard !end.overflow, offset >= 0, end.partialValue <= byteCount else {
                throw CodecError.malformedToken
            }
            var remaining = count
            var cursor = offset
            var utf8 = UTF8Validator()
            while remaining > 0 {
                let chunk = Int(min(Int64(copyBufferBytes), remaining))
                let data = try read(offset: cursor, count: chunk)
                if validateUTF8 { try utf8.consume(data) }
                try write(data, to: output)
                remaining -= Int64(chunk)
                cursor += Int64(chunk)
            }
            if validateUTF8 { try utf8.finish() }
        }
    }

    fileprivate struct UTF8Validator {
        private var continuationBytes = 0
        private var nextContinuationRange: ClosedRange<UInt8> = 0x80...0xbf

        mutating func consume(_ data: Data) throws {
            for byte in data {
                if continuationBytes > 0 {
                    guard nextContinuationRange.contains(byte) else { throw CodecError.invalidUTF8 }
                    continuationBytes -= 1
                    nextContinuationRange = 0x80...0xbf
                    continue
                }
                switch byte {
                case 0x00...0x7f: break
                case 0xc2...0xdf: continuationBytes = 1
                case 0xe0:
                    continuationBytes = 2
                    nextContinuationRange = 0xa0...0xbf
                case 0xe1...0xec, 0xee...0xef: continuationBytes = 2
                case 0xed:
                    continuationBytes = 2
                    nextContinuationRange = 0x80...0x9f
                case 0xf0:
                    continuationBytes = 3
                    nextContinuationRange = 0x90...0xbf
                case 0xf1...0xf3: continuationBytes = 3
                case 0xf4:
                    continuationBytes = 3
                    nextContinuationRange = 0x80...0x8f
                default: throw CodecError.invalidUTF8
                }
            }
        }

        func finish() throws {
            guard continuationBytes == 0 else { throw CodecError.invalidUTF8 }
        }
    }

    fileprivate final class TokenEncoder: Encoder {
        fileprivate final class InlineBudget {
            private var remaining = inlineGraphBytes

            func claim(_ byteCount: Int) -> Bool {
                guard byteCount >= 0, byteCount <= remaining else { return false }
                remaining -= byteCount
                return true
            }

            func release(_ byteCount: Int) {
                guard byteCount > 0 else { return }
                remaining = min(inlineGraphBytes, remaining + byteCount)
            }
        }

        fileprivate final class KeyedState {
            fileprivate enum EntryStorage {
                case inline(Data)
                case file(URL)
                case spooled(offset: UInt64)
            }

            fileprivate struct Entry {
                let keyData: Data
                let byteCount: Int64
                var storage: EntryStorage
            }

            let inlineBudget: InlineBudget
            var pendingValues: [String: TokenEncoder] = [:]
            var entries: [String: Entry] = [:]
            private var claimedInlineByteCount = 0
            private var spoolURL: URL?
            private var spoolHandle: FileHandle?

            var count: Int { pendingValues.count + entries.count }

            init(inlineBudget: InlineBudget) {
                self.inlineBudget = inlineBudget
            }

            deinit { consume() }

            func insertPending(_ child: TokenEncoder, key: String) throws {
                try validateNewKey(key)
                pendingValues[key] = child
            }

            func insertFinalized(_ child: TokenEncoder, key: String) throws {
                try Task.checkCancellation()
                try validateNewKey(key)
                let node = try child.finalize()
                if try !append(node, key: key) { node.remove() }
            }

            func finish() throws -> [Entry] {
                let pending = pendingValues
                pendingValues.removeAll(keepingCapacity: false)
                for (key, child) in pending {
                    try Task.checkCancellation()
                    let node = try child.finalize()
                    if try !append(node, key: key) { node.remove() }
                }
                try spoolHandle?.close()
                spoolHandle = nil
                return entries.sorted {
                    $0.key.utf8.lexicographicallyPrecedes($1.key.utf8)
                }.map(\.value)
            }

            func write(_ entry: Entry, to output: FileHandle) throws {
                switch entry.storage {
                case .inline(let data):
                    try ConnectedCorpusApplicationItemCodec.write(data, to: output)
                case .file(let url):
                    try ConnectedCorpusApplicationItemCodec.copyFile(url, to: output)
                case .spooled(let offset):
                    guard let spoolURL else { throw CodecError.unsupportedValue }
                    let input = try FileHandle(forReadingFrom: spoolURL)
                    defer { try? input.close() }
                    try input.seek(toOffset: offset)
                    var remaining = entry.byteCount
                    while remaining > 0 {
                        try Task.checkCancellation()
                        let count = Int(min(Int64(copyBufferBytes), remaining))
                        guard let data = try input.read(upToCount: count), data.count == count else {
                            throw CodecError.malformedToken
                        }
                        try ConnectedCorpusApplicationItemCodec.write(data, to: output)
                        remaining -= Int64(data.count)
                    }
                }
            }

            func consume() {
                try? spoolHandle?.close()
                spoolHandle = nil
                if let spoolURL { try? FileManager.default.removeItem(at: spoolURL) }
                spoolURL = nil
                for entry in entries.values {
                    if case .file(let url) = entry.storage {
                        try? FileManager.default.removeItem(at: url)
                    }
                }
                entries.removeAll(keepingCapacity: false)
                pendingValues.removeAll(keepingCapacity: false)
                inlineBudget.release(claimedInlineByteCount)
                claimedInlineByteCount = 0
            }

            private func validateNewKey(_ key: String) throws {
                guard count < maximumObjectKeys else { throw CodecError.excessiveObjectKeys }
                guard entries[key] == nil, pendingValues[key] == nil else {
                    throw CodecError.duplicateKey
                }
                let keyData = Data(key.utf8)
                guard !keyData.isEmpty, keyData.count <= maximumKeyBytes else {
                    throw CodecError.malformedToken
                }
            }

            /// Returns true when ownership of a file-backed node was adopted.
            private func append(_ node: TemporaryNode, key: String) throws -> Bool {
                let keyData = Data(key.utf8)
                let storage: EntryStorage
                let adoptedFile: Bool
                switch node.storage {
                case .file(let url):
                    storage = .file(url)
                    adoptedFile = true
                case .inline(let inline)
                    where inlineBudget.claim(inline.count):
                    storage = .inline(inline)
                    claimedInlineByteCount += inline.count
                    adoptedFile = false
                case .inline:
                    if spoolHandle == nil {
                        let url = try ConnectedTransferFile.makeRestrictedTemporaryFile(
                            prefix: "corpus-object-body"
                        )
                        spoolURL = url
                        spoolHandle = try FileHandle(forWritingTo: url)
                    }
                    guard let spoolHandle else { throw CodecError.unsupportedValue }
                    let offset = try spoolHandle.offset()
                    try node.write(to: spoolHandle)
                    storage = .spooled(offset: offset)
                    adoptedFile = false
                }
                entries[key] = Entry(
                    keyData: keyData,
                    byteCount: node.byteCount,
                    storage: storage
                )
                return adoptedFile
            }
        }

        fileprivate final class UnkeyedState {
            let inlineBudget: InlineBudget
            var count = 0
            var bodyByteCount: Int64 = 0
            var bodyData = Data()
            private var claimedInlineByteCount = 0
            var bodyURL: URL?
            var bodyHandle: FileHandle?
            var pendingNestedChildren: [TokenEncoder] = []
            var deferredError: Error?

            init(inlineBudget: InlineBudget) {
                self.inlineBudget = inlineBudget
            }

            deinit {
                try? bodyHandle?.close()
                if let bodyURL { try? FileManager.default.removeItem(at: bodyURL) }
            }

            func append(_ child: TokenEncoder) throws {
                try flushPendingNestedChildren()
                try appendFinalized(child)
            }

            func appendNested(_ child: TokenEncoder) {
                pendingNestedChildren.append(child)
            }

            func finish() throws -> (
                count: Int,
                bodyByteCount: Int64,
                bodyURL: URL?,
                bodyData: Data
            ) {
                if let deferredError { throw deferredError }
                try flushPendingNestedChildren()
                try bodyHandle?.close()
                bodyHandle = nil
                return (count, bodyByteCount, bodyURL, bodyData)
            }

            func consumeBody() {
                if let bodyURL { try? FileManager.default.removeItem(at: bodyURL) }
                bodyURL = nil
                bodyData.removeAll(keepingCapacity: false)
                inlineBudget.release(claimedInlineByteCount)
                claimedInlineByteCount = 0
            }

            private func flushPendingNestedChildren() throws {
                let children = pendingNestedChildren
                pendingNestedChildren.removeAll(keepingCapacity: false)
                for child in children {
                    try Task.checkCancellation()
                    try appendFinalized(child)
                }
            }

            private func appendFinalized(_ child: TokenEncoder) throws {
                try Task.checkCancellation()
                let node = try child.finalize()
                defer { node.remove() }
                let entryBytes = Int64(8).addingReportingOverflow(node.byteCount)
                let total = bodyByteCount.addingReportingOverflow(entryBytes.partialValue)
                guard !entryBytes.overflow, !total.overflow else {
                    throw CodecError.malformedToken
                }
                if bodyHandle == nil,
                   let inline = node.inlineData,
                   inlineBudget.claim(8 + inline.count) {
                    bodyData.append(uint64BigEndian(UInt64(node.byteCount)))
                    bodyData.append(inline)
                    claimedInlineByteCount += 8 + inline.count
                } else {
                    if bodyHandle == nil {
                        let url = try ConnectedTransferFile.makeRestrictedTemporaryFile(
                            prefix: "corpus-array-body"
                        )
                        bodyURL = url
                        bodyHandle = try FileHandle(forWritingTo: url)
                        if !bodyData.isEmpty {
                            try write(bodyData, to: bodyHandle!)
                            bodyData.removeAll(keepingCapacity: false)
                            inlineBudget.release(claimedInlineByteCount)
                            claimedInlineByteCount = 0
                        }
                    }
                    guard let bodyHandle else { throw CodecError.unsupportedValue }
                    try write(uint64BigEndian(UInt64(node.byteCount)), to: bodyHandle)
                    try node.write(to: bodyHandle)
                }
                bodyByteCount = total.partialValue
                count += 1
            }
        }

        fileprivate enum Scalar {
            case null
            case boolean(Bool)
            case signed(Int64)
            case unsigned(UInt64)
            case double(Double)
            case string(String)
            case fileBackedUTF8(ConnectedTransferPreparedFile)
            case fileBackedData(HealthKitFileBackedBlob)
            case data(Data)
            case date(Date)
        }

        fileprivate enum Storage {
            case unset
            case keyed(KeyedState)
            case unkeyed(UnkeyedState)
            case scalar(Scalar)
            case child(TokenEncoder)
        }

        var codingPath: [CodingKey]
        var userInfo: [CodingUserInfoKey: Any] = [:]
        fileprivate let depth: Int
        fileprivate let inlineBudget: InlineBudget
        fileprivate var storage: Storage = .unset

        fileprivate init(
            codingPath: [CodingKey],
            depth: Int,
            inlineBudget: InlineBudget = InlineBudget()
        ) {
            self.codingPath = codingPath
            self.depth = depth
            self.inlineBudget = inlineBudget
        }

        fileprivate static func encode<T: Encodable>(
            _ value: T,
            codingPath: [CodingKey],
            depth: Int
        ) throws -> TemporaryNode {
            guard depth <= maximumDepth else { throw CodecError.excessiveDepth }
            let encoder = TokenEncoder(codingPath: codingPath, depth: depth)
            if let date = value as? Date {
                encoder.storage = .scalar(.date(date))
            } else if let data = value as? Data {
                encoder.storage = .scalar(.data(data))
            } else if let blob = value as? HealthKitFileBackedBlob {
                encoder.storage = .scalar(.fileBackedData(blob))
            } else if let file = value as? FileBackedUTF8String {
                encoder.storage = .scalar(.fileBackedUTF8(file.file))
            } else {
                try value.encode(to: encoder)
            }
            return try encoder.finalize()
        }

        fileprivate static func child<T: Encodable>(
            _ value: T,
            codingPath: [CodingKey],
            depth: Int,
            inlineBudget: InlineBudget
        ) throws -> TokenEncoder {
            guard depth <= maximumDepth else { throw CodecError.excessiveDepth }
            let encoder = TokenEncoder(
                codingPath: codingPath,
                depth: depth,
                inlineBudget: inlineBudget
            )
            if let date = value as? Date {
                encoder.storage = .scalar(.date(date))
            } else if let data = value as? Data {
                encoder.storage = .scalar(.data(data))
            } else if let blob = value as? HealthKitFileBackedBlob {
                encoder.storage = .scalar(.fileBackedData(blob))
            } else if let file = value as? FileBackedUTF8String {
                encoder.storage = .scalar(.fileBackedUTF8(file.file))
            } else {
                try value.encode(to: encoder)
            }
            return encoder
        }

        func container<Key>(keyedBy _: Key.Type) -> KeyedEncodingContainer<Key> where Key: CodingKey {
            let state: KeyedState
            switch storage {
            case .unset:
                state = KeyedState(inlineBudget: inlineBudget)
                storage = .keyed(state)
            case .keyed(let existing): state = existing
            default:
                state = KeyedState(inlineBudget: inlineBudget)
                storage = .keyed(state)
            }
            return KeyedEncodingContainer(KeyedContainer<Key>(encoder: self, state: state))
        }

        func unkeyedContainer() -> UnkeyedEncodingContainer {
            let state: UnkeyedState
            switch storage {
            case .unset:
                state = UnkeyedState(inlineBudget: inlineBudget)
                storage = .unkeyed(state)
            case .unkeyed(let existing): state = existing
            default:
                state = UnkeyedState(inlineBudget: inlineBudget)
                storage = .unkeyed(state)
            }
            return UnkeyedContainer(encoder: self, state: state)
        }

        func singleValueContainer() -> SingleValueEncodingContainer {
            SingleValueContainer(encoder: self)
        }

        fileprivate func finalize() throws -> TemporaryNode {
            guard depth <= maximumDepth else { throw CodecError.excessiveDepth }
            switch storage {
            case .unset: throw CodecError.unsupportedValue
            case .scalar(let scalar): return try writeScalar(scalar)
            case .child(let child): return try child.finalize()
            case .keyed(let state): return try writeObject(state)
            case .unkeyed(let state): return try writeArray(state)
            }
        }

        fileprivate func setScalar(_ scalar: Scalar) throws {
            guard case .unset = storage else { throw CodecError.unsupportedValue }
            storage = .scalar(scalar)
        }

        private func writeScalar(_ scalar: Scalar) throws -> TemporaryNode {
            if let inline = try inlineScalar(scalar) { return inline }
            let outputURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "corpus-token")
            do {
                let output = try FileHandle(forWritingTo: outputURL)
                defer { try? output.close() }
                let tag: Tag
                let payloadLength: UInt64
                switch scalar {
                case .null:
                    tag = .null; payloadLength = 0
                case .boolean:
                    tag = .boolean; payloadLength = 1
                case .signed:
                    tag = .signedInteger; payloadLength = 8
                case .unsigned:
                    tag = .unsignedInteger; payloadLength = 8
                case .double(let value):
                    guard value.isFinite else { throw CodecError.invalidNumber }
                    tag = .double; payloadLength = 8
                case .string(let value):
                    tag = .string; payloadLength = try Self.utf8Length(value)
                case .fileBackedUTF8(let file):
                    guard file.totalBytes > 0 else { throw CodecError.malformedToken }
                    tag = .string; payloadLength = UInt64(file.totalBytes)
                case .data(let value):
                    tag = .data; payloadLength = UInt64(value.count)
                case .fileBackedData(let value):
                    tag = .data; payloadLength = value.byteCount
                case .date(let value):
                    let seconds = value.timeIntervalSinceReferenceDate
                    guard seconds.isFinite else { throw CodecError.invalidNumber }
                    tag = .date; payloadLength = 8
                }
                try write(Data([tag.rawValue]), to: output)
                try write(uint64BigEndian(payloadLength), to: output)
                switch scalar {
                case .null: break
                case .boolean(let value): try write(Data([value ? 1 : 0]), to: output)
                case .signed(let value):
                    try write(uint64BigEndian(UInt64(bitPattern: value)), to: output)
                case .unsigned(let value):
                    try write(uint64BigEndian(value), to: output)
                case .double(let value):
                    try write(uint64BigEndian(value.bitPattern), to: output)
                case .date(let value):
                    try write(
                        uint64BigEndian(value.timeIntervalSinceReferenceDate.bitPattern),
                        to: output
                    )
                case .data(let value):
                    try write(value, to: output)
                case .fileBackedData(let value):
                    guard value.byteCount <= UInt64(Int64.max) else {
                        throw CodecError.malformedToken
                    }
                    try copyFile(
                        value.url,
                        to: output,
                        expected: ConnectedTransferPreparedFile(
                            url: value.url,
                            totalBytes: Int64(value.byteCount),
                            sha256: value.sha256
                        )
                    )
                case .string(let value):
                    _ = try Self.streamUTF8(value, to: output)
                case .fileBackedUTF8(let file):
                    try copyFile(file.url, to: output, expected: file)
                }
                try output.close()
                return TemporaryNode(
                    url: outputURL,
                    byteCount: Int64(9) + Int64(payloadLength)
                )
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }
        }

        private func inlineScalar(_ scalar: Scalar) throws -> TemporaryNode? {
            let tag: Tag
            let payload: Data
            switch scalar {
            case .null:
                tag = .null
                payload = Data()
            case .boolean(let value):
                tag = .boolean
                payload = Data([value ? 1 : 0])
            case .signed(let value):
                tag = .signedInteger
                payload = uint64BigEndian(UInt64(bitPattern: value))
            case .unsigned(let value):
                tag = .unsignedInteger
                payload = uint64BigEndian(value)
            case .double(let value):
                guard value.isFinite else { throw CodecError.invalidNumber }
                tag = .double
                payload = uint64BigEndian(value.bitPattern)
            case .date(let value):
                let seconds = value.timeIntervalSinceReferenceDate
                guard seconds.isFinite else { throw CodecError.invalidNumber }
                tag = .date
                payload = uint64BigEndian(seconds.bitPattern)
            case .string(let value):
                guard value.utf8.count <= inlineNodeBytes - 9 else { return nil }
                tag = .string
                payload = Data(value.utf8)
            case .data(let value):
                guard value.count <= inlineNodeBytes - 9 else { return nil }
                tag = .data
                payload = value
            case .fileBackedUTF8, .fileBackedData:
                return nil
            }
            var encoded = Data(capacity: 9 + payload.count)
            encoded.append(tag.rawValue)
            encoded.append(uint64BigEndian(UInt64(payload.count)))
            encoded.append(payload)
            return TemporaryNode(data: encoded)
        }

        private static func utf8Length(_ value: String) throws -> UInt64 {
            try streamUTF8(value, to: nil)
        }

        /// CoreFoundation converts bounded UTF-16 ranges directly into the fixed
        /// buffer. This avoids Swift/NSString creating a complete UTF-8 bridge for
        /// one arbitrarily large String.
        private static func streamUTF8(
            _ value: String,
            to output: FileHandle?
        ) throws -> UInt64 {
            let string = value as CFString
            let characterCount = CFStringGetLength(string)
            var characterOffset = 0
            var totalBytes: UInt64 = 0
            var buffer = [UInt8](repeating: 0, count: copyBufferBytes)
            while characterOffset < characterCount {
                try Task.checkCancellation()
                var usedBytes = 0
                let convertedCharacters = buffer.withUnsafeMutableBufferPointer { bytes in
                    CFStringGetBytes(
                        string,
                        CFRange(
                            location: characterOffset,
                            length: characterCount - characterOffset
                        ),
                        CFStringBuiltInEncodings.UTF8.rawValue,
                        0,
                        false,
                        bytes.baseAddress,
                        bytes.count,
                        &usedBytes
                    )
                }
                guard convertedCharacters > 0, usedBytes > 0 else {
                    throw CodecError.invalidUTF8
                }
                let sum = totalBytes.addingReportingOverflow(UInt64(usedBytes))
                guard !sum.overflow else { throw CodecError.malformedToken }
                totalBytes = sum.partialValue
                if let output {
                    try buffer.withUnsafeBufferPointer { bytes in
                        guard let baseAddress = bytes.baseAddress else { return }
                        try write(
                            UnsafeBufferPointer(start: baseAddress, count: usedBytes),
                            to: output
                        )
                    }
                }
                characterOffset += convertedCharacters
            }
            return totalBytes
        }

        private func writeObject(_ state: KeyedState) throws -> TemporaryNode {
            guard state.count <= maximumObjectKeys else { throw CodecError.excessiveObjectKeys }
            let entries = try state.finish()
            defer { state.consume() }
            var payloadLength = Int64(4)
            for entry in entries {
                try Task.checkCancellation()
                for component in [Int64(4 + entry.keyData.count + 8), entry.byteCount] {
                    let sum = payloadLength.addingReportingOverflow(component)
                    guard !sum.overflow else { throw CodecError.malformedToken }
                    payloadLength = sum.partialValue
                }
            }
            let allInline = entries.allSatisfy {
                if case .inline = $0.storage { return true }
                return false
            }
            if payloadLength + 9 <= Int64(inlineNodeBytes), allInline {
                var encoded = Data(capacity: Int(payloadLength + 9))
                encoded.append(Tag.object.rawValue)
                encoded.append(uint64BigEndian(UInt64(payloadLength)))
                encoded.append(uint32BigEndian(UInt32(entries.count)))
                for entry in entries {
                    try Task.checkCancellation()
                    encoded.append(uint32BigEndian(UInt32(entry.keyData.count)))
                    encoded.append(entry.keyData)
                    encoded.append(uint64BigEndian(UInt64(entry.byteCount)))
                    guard case .inline(let data) = entry.storage else {
                        throw CodecError.unsupportedValue
                    }
                    encoded.append(data)
                }
                return TemporaryNode(data: encoded)
            }
            return try writeComposite(tag: .object, payloadLength: payloadLength) { output in
                try write(uint32BigEndian(UInt32(entries.count)), to: output)
                for entry in entries {
                    try Task.checkCancellation()
                    try write(uint32BigEndian(UInt32(entry.keyData.count)), to: output)
                    try write(entry.keyData, to: output)
                    try write(uint64BigEndian(UInt64(entry.byteCount)), to: output)
                    try state.write(entry, to: output)
                }
            }
        }

        private func writeArray(_ state: UnkeyedState) throws -> TemporaryNode {
            let body = try state.finish()
            let payload = Int64(8).addingReportingOverflow(body.bodyByteCount)
            guard !payload.overflow else { throw CodecError.malformedToken }
            defer { state.consumeBody() }
            if body.bodyURL == nil,
               payload.partialValue + 9 <= Int64(inlineNodeBytes) {
                var encoded = Data(capacity: Int(payload.partialValue + 9))
                encoded.append(Tag.array.rawValue)
                encoded.append(uint64BigEndian(UInt64(payload.partialValue)))
                encoded.append(uint64BigEndian(UInt64(body.count)))
                encoded.append(body.bodyData)
                return TemporaryNode(data: encoded)
            }
            return try writeComposite(tag: .array, payloadLength: payload.partialValue) { output in
                try write(uint64BigEndian(UInt64(body.count)), to: output)
                if !body.bodyData.isEmpty { try write(body.bodyData, to: output) }
                if let bodyURL = body.bodyURL { try copyFile(bodyURL, to: output) }
            }
        }

        private func writeComposite(
            tag: Tag,
            payloadLength: Int64,
            body: (FileHandle) throws -> Void
        ) throws -> TemporaryNode {
            guard payloadLength >= 0 else { throw CodecError.malformedToken }
            let outputURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "corpus-token")
            do {
                let output = try FileHandle(forWritingTo: outputURL)
                defer { try? output.close() }
                try write(Data([tag.rawValue]), to: output)
                try write(uint64BigEndian(UInt64(payloadLength)), to: output)
                try body(output)
                try output.close()
                return TemporaryNode(url: outputURL, byteCount: payloadLength + 9)
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }
        }
    }

    fileprivate struct KeyedContainer<Key: CodingKey>: KeyedEncodingContainerProtocol {
        let encoder: TokenEncoder
        let state: TokenEncoder.KeyedState
        var codingPath: [CodingKey] { encoder.codingPath }

        mutating func encodeNil(forKey key: Key) throws { try put(.scalar(.null), forKey: key) }
        mutating func encode(_ value: Bool, forKey key: Key) throws { try put(.scalar(.boolean(value)), forKey: key) }
        mutating func encode(_ value: String, forKey key: Key) throws { try put(.scalar(.string(value)), forKey: key) }
        mutating func encode(_ value: Double, forKey key: Key) throws { try put(.scalar(.double(value)), forKey: key) }
        mutating func encode(_ value: Float, forKey key: Key) throws { try encode(Double(value), forKey: key) }
        mutating func encode(_ value: Int, forKey key: Key) throws { try encode(Int64(value), forKey: key) }
        mutating func encode(_ value: Int8, forKey key: Key) throws { try encode(Int64(value), forKey: key) }
        mutating func encode(_ value: Int16, forKey key: Key) throws { try encode(Int64(value), forKey: key) }
        mutating func encode(_ value: Int32, forKey key: Key) throws { try encode(Int64(value), forKey: key) }
        mutating func encode(_ value: Int64, forKey key: Key) throws { try put(.scalar(.signed(value)), forKey: key) }
        mutating func encode(_ value: UInt, forKey key: Key) throws { try encode(UInt64(value), forKey: key) }
        mutating func encode(_ value: UInt8, forKey key: Key) throws { try encode(UInt64(value), forKey: key) }
        mutating func encode(_ value: UInt16, forKey key: Key) throws { try encode(UInt64(value), forKey: key) }
        mutating func encode(_ value: UInt32, forKey key: Key) throws { try encode(UInt64(value), forKey: key) }
        mutating func encode(_ value: UInt64, forKey key: Key) throws { try put(.scalar(.unsigned(value)), forKey: key) }

        mutating func encode<T>(_ value: T, forKey key: Key) throws where T: Encodable {
            try state.insertFinalized(
                TokenEncoder.child(
                    value,
                    codingPath: codingPath + [key],
                    depth: encoder.depth + 1,
                    inlineBudget: encoder.inlineBudget
                ),
                key: key.stringValue
            )
        }

        mutating func nestedContainer<NestedKey>(
            keyedBy _: NestedKey.Type,
            forKey key: Key
        ) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
            let child = TokenEncoder(
                codingPath: codingPath + [key],
                depth: encoder.depth + 1,
                inlineBudget: encoder.inlineBudget
            )
            try? state.insertPending(child, key: key.stringValue)
            return child.container(keyedBy: NestedKey.self)
        }

        mutating func nestedUnkeyedContainer(forKey key: Key) -> UnkeyedEncodingContainer {
            let child = TokenEncoder(
                codingPath: codingPath + [key],
                depth: encoder.depth + 1,
                inlineBudget: encoder.inlineBudget
            )
            try? state.insertPending(child, key: key.stringValue)
            return child.unkeyedContainer()
        }

        mutating func superEncoder() -> Encoder {
            if let key = Key(stringValue: "super") {
                return superEncoder(forKey: key)
            }
            let child = TokenEncoder(
                codingPath: codingPath + [IndexKey(intValue: -1)],
                depth: encoder.depth + 1,
                inlineBudget: encoder.inlineBudget
            )
            try? state.insertPending(child, key: "super")
            return child
        }

        mutating func superEncoder(forKey key: Key) -> Encoder {
            let child = TokenEncoder(
                codingPath: codingPath + [key],
                depth: encoder.depth + 1,
                inlineBudget: encoder.inlineBudget
            )
            try? state.insertPending(child, key: key.stringValue)
            return child
        }

        private mutating func put(_ storage: TokenEncoder.Storage, forKey key: Key) throws {
            let child = TokenEncoder(
                codingPath: codingPath + [key],
                depth: encoder.depth + 1,
                inlineBudget: encoder.inlineBudget
            )
            child.storage = storage
            try state.insertFinalized(child, key: key.stringValue)
        }
    }

    fileprivate struct UnkeyedContainer: UnkeyedEncodingContainer {
        let encoder: TokenEncoder
        let state: TokenEncoder.UnkeyedState
        var codingPath: [CodingKey] { encoder.codingPath }
        var count: Int { state.count + state.pendingNestedChildren.count }

        mutating func encodeNil() throws { try append(.scalar(.null)) }
        mutating func encode(_ value: Bool) throws { try append(.scalar(.boolean(value))) }
        mutating func encode(_ value: String) throws { try append(.scalar(.string(value))) }
        mutating func encode(_ value: Double) throws { try append(.scalar(.double(value))) }
        mutating func encode(_ value: Float) throws { try encode(Double(value)) }
        mutating func encode(_ value: Int) throws { try encode(Int64(value)) }
        mutating func encode(_ value: Int8) throws { try encode(Int64(value)) }
        mutating func encode(_ value: Int16) throws { try encode(Int64(value)) }
        mutating func encode(_ value: Int32) throws { try encode(Int64(value)) }
        mutating func encode(_ value: Int64) throws { try append(.scalar(.signed(value))) }
        mutating func encode(_ value: UInt) throws { try encode(UInt64(value)) }
        mutating func encode(_ value: UInt8) throws { try encode(UInt64(value)) }
        mutating func encode(_ value: UInt16) throws { try encode(UInt64(value)) }
        mutating func encode(_ value: UInt32) throws { try encode(UInt64(value)) }
        mutating func encode(_ value: UInt64) throws { try append(.scalar(.unsigned(value))) }

        mutating func encode<T>(_ value: T) throws where T: Encodable {
            try state.append(TokenEncoder.child(
                value,
                codingPath: codingPath + [IndexKey(intValue: count)],
                depth: encoder.depth + 1,
                inlineBudget: encoder.inlineBudget
            ))
        }

        mutating func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type) -> KeyedEncodingContainer<NestedKey> where NestedKey: CodingKey {
            let child = TokenEncoder(
                codingPath: codingPath + [IndexKey(intValue: count)],
                depth: encoder.depth + 1,
                inlineBudget: encoder.inlineBudget
            )
            state.appendNested(child)
            return child.container(keyedBy: NestedKey.self)
        }

        mutating func nestedUnkeyedContainer() -> UnkeyedEncodingContainer {
            let child = TokenEncoder(
                codingPath: codingPath + [IndexKey(intValue: count)],
                depth: encoder.depth + 1,
                inlineBudget: encoder.inlineBudget
            )
            state.appendNested(child)
            return child.unkeyedContainer()
        }

        mutating func superEncoder() -> Encoder {
            let child = TokenEncoder(
                codingPath: codingPath + [IndexKey(intValue: count)],
                depth: encoder.depth + 1,
                inlineBudget: encoder.inlineBudget
            )
            state.appendNested(child)
            return child
        }

        private mutating func append(_ storage: TokenEncoder.Storage) throws {
            let child = TokenEncoder(
                codingPath: codingPath + [IndexKey(intValue: count)],
                depth: encoder.depth + 1,
                inlineBudget: encoder.inlineBudget
            )
            child.storage = storage
            try state.append(child)
        }
    }

    fileprivate struct SingleValueContainer: SingleValueEncodingContainer {
        let encoder: TokenEncoder
        var codingPath: [CodingKey] { encoder.codingPath }

        func encodeNil() throws { try encoder.setScalar(.null) }
        func encode(_ value: Bool) throws { try encoder.setScalar(.boolean(value)) }
        func encode(_ value: String) throws { try encoder.setScalar(.string(value)) }
        func encode(_ value: Double) throws { try encoder.setScalar(.double(value)) }
        func encode(_ value: Float) throws { try encode(Double(value)) }
        func encode(_ value: Int) throws { try encode(Int64(value)) }
        func encode(_ value: Int8) throws { try encode(Int64(value)) }
        func encode(_ value: Int16) throws { try encode(Int64(value)) }
        func encode(_ value: Int32) throws { try encode(Int64(value)) }
        func encode(_ value: Int64) throws { try encoder.setScalar(.signed(value)) }
        func encode(_ value: UInt) throws { try encode(UInt64(value)) }
        func encode(_ value: UInt8) throws { try encode(UInt64(value)) }
        func encode(_ value: UInt16) throws { try encode(UInt64(value)) }
        func encode(_ value: UInt32) throws { try encode(UInt64(value)) }
        func encode(_ value: UInt64) throws { try encoder.setScalar(.unsigned(value)) }

        func encode<T>(_ value: T) throws where T: Encodable {
            encoder.storage = .child(try TokenEncoder.child(
                value,
                codingPath: codingPath,
                depth: encoder.depth + 1,
                inlineBudget: encoder.inlineBudget
            ))
        }
    }

    fileprivate struct IndexKey: CodingKey {
        let intValue: Int?
        let stringValue: String

        init(intValue: Int) {
            self.intValue = intValue
            stringValue = String(intValue)
        }

        init?(stringValue: String) {
            self.stringValue = stringValue
            intValue = Int(stringValue)
        }
    }

    fileprivate final class TokenDecoder: Decoder {
        let source: TokenSource
        let range: FileRange
        var codingPath: [CodingKey]
        var userInfo: [CodingUserInfoKey: Any] = [
            .healthKitFileBackedDataDecoding: true
        ]
        let depth: Int
        let suppressedKeyNames: Set<String>

        init(
            source: TokenSource,
            range: FileRange,
            codingPath: [CodingKey],
            depth: Int,
            suppressedKeyNames: Set<String> = []
        ) {
            self.source = source
            self.range = range
            self.codingPath = codingPath
            self.depth = depth
            self.suppressedKeyNames = suppressedKeyNames
        }

        func decode<T: Decodable>(_ type: T.Type) throws -> T {
            guard depth <= maximumDepth else { throw CodecError.excessiveDepth }
            if type == Date.self {
                return try decodeDate() as! T
            }
            if type == Data.self {
                return try decodeData() as! T
            }
            if type == HealthKitFileBackedBlob.self {
                return try decodeFileBackedBlob() as! T
            }
            return try T(from: self)
        }

        func container<Key>(keyedBy _: Key.Type) throws -> KeyedDecodingContainer<Key> where Key: CodingKey {
            let entries = try Self.objectEntries(source: source, range: range, depth: depth)
            return KeyedDecodingContainer(KeyedDecoding<Key>(decoder: self, entries: entries))
        }

        func unkeyedContainer() throws -> UnkeyedDecodingContainer {
            let header = try source.nodeHeader(in: range)
            guard header.tag == .array, header.payloadLength >= 8 else {
                throw CodecError.malformedToken
            }
            let count = try source.readUInt64(offset: header.payloadOffset)
            let bodyBytes = header.payloadLength - 8
            // Every encoded element requires an 8-byte length and at least a
            // 9-byte token header. Reject inflated counts before Array.Decodable
            // can reserve attacker-controlled capacity.
            guard count <= UInt64(Int.max),
                  count <= UInt64(bodyBytes / 17) else {
                throw CodecError.malformedToken
            }
            return UnkeyedDecoding(
                decoder: self,
                count: Int(count),
                cursor: header.payloadOffset + 8,
                end: header.payloadOffset + header.payloadLength
            )
        }

        func singleValueContainer() throws -> SingleValueDecodingContainer {
            SingleValueDecoding(decoder: self)
        }

        func validateCompleteNode() throws {
            _ = try source.nodeHeader(in: range)
        }

        fileprivate func child(_ childRange: FileRange, key: CodingKey) throws -> TokenDecoder {
            guard depth + 1 <= maximumDepth else { throw CodecError.excessiveDepth }
            return TokenDecoder(
                source: source,
                range: childRange,
                codingPath: codingPath + [key],
                depth: depth + 1,
                suppressedKeyNames: suppressedKeyNames
            )
        }

        fileprivate func decodeDate() throws -> Date {
            let header = try source.nodeHeader(in: range)
            guard header.tag == .date, header.payloadLength == 8 else {
                throw CodecError.malformedToken
            }
            let seconds = Double(bitPattern: try source.readUInt64(offset: header.payloadOffset))
            guard seconds.isFinite else { throw CodecError.invalidNumber }
            return Date(timeIntervalSinceReferenceDate: seconds)
        }

        fileprivate func decodeFileBackedBlob() throws -> HealthKitFileBackedBlob {
            let header = try source.nodeHeader(in: range)
            guard header.tag == .data, header.payloadLength >= 0 else {
                throw CodecError.malformedToken
            }
            let outputURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(
                prefix: "corpus-decoded-blob"
            )
            do {
                let output = try FileHandle(forWritingTo: outputURL)
                var outputIsOpen = true
                do {
                    var hasher = SHA256()
                    var offset = header.payloadOffset
                    var remaining = header.payloadLength
                    while remaining > 0 {
                        try Task.checkCancellation()
                        let count = Int(min(Int64(copyBufferBytes), remaining))
                        let data = try source.read(offset: offset, count: count)
                        try write(data, to: output)
                        hasher.update(data: data)
                        offset += Int64(count)
                        remaining -= Int64(count)
                    }
                    try output.synchronize()
                    try output.close()
                    outputIsOpen = false
                    let descriptor = ExportArtifactDescriptor(
                        byteCount: UInt64(header.payloadLength),
                        sha256: hasher.finalize().map {
                            String(format: "%02x", $0)
                        }.joined(),
                        mediaType: "application/octet-stream"
                    )
                    return HealthKitFileBackedBlob(artifact: ExportArtifactFile(
                        descriptor: descriptor,
                        lease: RestrictedArtifactFileLease(url: outputURL)
                    ))
                } catch {
                    if outputIsOpen { try? output.close() }
                    throw error
                }
            } catch {
                try? FileManager.default.removeItem(at: outputURL)
                throw error
            }
        }

        fileprivate func decodeData() throws -> Data {
            let header = try source.nodeHeader(in: range)
            guard header.tag == .data,
                  header.payloadLength <= Int64(Int.max) else {
                throw CodecError.malformedToken
            }
            return try source.mappedData(
                offset: header.payloadOffset,
                count: Int(header.payloadLength)
            )
        }

        fileprivate static func objectEntries(
            source: TokenSource,
            range: FileRange,
            depth: Int
        ) throws -> [String: FileRange] {
            guard depth <= maximumDepth else { throw CodecError.excessiveDepth }
            let header = try source.nodeHeader(in: range)
            guard header.tag == .object, header.payloadLength >= 4 else {
                throw CodecError.malformedToken
            }
            let count = Int(try source.readUInt32(offset: header.payloadOffset))
            guard count <= maximumObjectKeys else { throw CodecError.excessiveObjectKeys }
            var cursor = header.payloadOffset + 4
            let end = header.payloadOffset + header.payloadLength
            var result: [String: FileRange] = [:]
            var previousKey: Data?
            for _ in 0..<count {
                guard cursor + 4 <= end else { throw CodecError.malformedToken }
                let keyLength = Int(try source.readUInt32(offset: cursor))
                cursor += 4
                guard keyLength > 0, keyLength <= maximumKeyBytes,
                      cursor + Int64(keyLength) + 8 <= end else {
                    throw CodecError.malformedToken
                }
                let keyData = try source.read(offset: cursor, count: keyLength)
                cursor += Int64(keyLength)
                guard let key = String(data: keyData, encoding: .utf8),
                      previousKey.map({ $0.lexicographicallyPrecedes(keyData) }) ?? true else {
                    throw CodecError.invalidUTF8
                }
                previousKey = keyData
                let childLengthValue = try source.readUInt64(offset: cursor)
                cursor += 8
                guard childLengthValue <= UInt64(Int64.max) else { throw CodecError.malformedToken }
                let childLength = Int64(childLengthValue)
                let childEnd = cursor.addingReportingOverflow(childLength)
                guard childLength >= 9, !childEnd.overflow, childEnd.partialValue <= end else {
                    throw CodecError.malformedToken
                }
                let childRange = FileRange(offset: cursor, length: childLength)
                _ = try source.nodeHeader(in: childRange)
                guard result.updateValue(childRange, forKey: key) == nil else {
                    throw CodecError.duplicateKey
                }
                cursor = childEnd.partialValue
            }
            guard cursor == end else { throw CodecError.trailingBytes }
            return result
        }
    }

    fileprivate struct KeyedDecoding<Key: CodingKey>: KeyedDecodingContainerProtocol {
        let decoder: TokenDecoder
        let entries: [String: FileRange]
        var codingPath: [CodingKey] { decoder.codingPath }
        var allKeys: [Key] {
            entries.keys.sorted().compactMap { key in
                guard !decoder.suppressedKeyNames.contains(key) else { return nil }
                return Key(stringValue: key)
            }
        }

        func contains(_ key: Key) -> Bool {
            !decoder.suppressedKeyNames.contains(key.stringValue)
                && entries[key.stringValue] != nil
        }

        func decodeNil(forKey key: Key) throws -> Bool {
            if decoder.suppressedKeyNames.contains(key.stringValue) { return true }
            guard let range = entries[key.stringValue] else { return true }
            return try decoder.source.nodeHeader(in: range).tag == .null
        }

        func decode(_ type: Bool.Type, forKey key: Key) throws -> Bool { try scalar(key).decode(type) }
        func decode(_ type: String.Type, forKey key: Key) throws -> String { try scalar(key).decode(type) }
        func decode(_ type: Double.Type, forKey key: Key) throws -> Double { try scalar(key).decode(type) }
        func decode(_ type: Float.Type, forKey key: Key) throws -> Float { try scalar(key).decode(type) }
        func decode(_ type: Int.Type, forKey key: Key) throws -> Int { try scalar(key).decode(type) }
        func decode(_ type: Int8.Type, forKey key: Key) throws -> Int8 { try scalar(key).decode(type) }
        func decode(_ type: Int16.Type, forKey key: Key) throws -> Int16 { try scalar(key).decode(type) }
        func decode(_ type: Int32.Type, forKey key: Key) throws -> Int32 { try scalar(key).decode(type) }
        func decode(_ type: Int64.Type, forKey key: Key) throws -> Int64 { try scalar(key).decode(type) }
        func decode(_ type: UInt.Type, forKey key: Key) throws -> UInt { try scalar(key).decode(type) }
        func decode(_ type: UInt8.Type, forKey key: Key) throws -> UInt8 { try scalar(key).decode(type) }
        func decode(_ type: UInt16.Type, forKey key: Key) throws -> UInt16 { try scalar(key).decode(type) }
        func decode(_ type: UInt32.Type, forKey key: Key) throws -> UInt32 { try scalar(key).decode(type) }
        func decode(_ type: UInt64.Type, forKey key: Key) throws -> UInt64 { try scalar(key).decode(type) }

        func decode<T>(_ type: T.Type, forKey key: Key) throws -> T where T: Decodable {
            guard !decoder.suppressedKeyNames.contains(key.stringValue),
                  let range = entries[key.stringValue] else {
                throw DecodingError.keyNotFound(key, .init(
                    codingPath: codingPath,
                    debugDescription: "Missing connected-corpus token key"
                ))
            }
            return try decoder.child(range, key: key).decode(type)
        }

        func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type, forKey key: Key) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
            try child(key).container(keyedBy: NestedKey.self)
        }

        func nestedUnkeyedContainer(forKey key: Key) throws -> UnkeyedDecodingContainer {
            try child(key).unkeyedContainer()
        }

        func superDecoder() throws -> Decoder {
            guard let key = Key(stringValue: "super") else { throw CodecError.malformedToken }
            return try child(key)
        }

        func superDecoder(forKey key: Key) throws -> Decoder { try child(key) }

        private func child(_ key: Key) throws -> TokenDecoder {
            guard let range = entries[key.stringValue] else {
                throw DecodingError.keyNotFound(key, .init(
                    codingPath: codingPath,
                    debugDescription: "Missing connected-corpus token key"
                ))
            }
            return try decoder.child(range, key: key)
        }

        private func scalar(_ key: Key) throws -> SingleValueDecoding {
            SingleValueDecoding(decoder: try child(key))
        }
    }

    fileprivate struct UnkeyedDecoding: UnkeyedDecodingContainer {
        let decoder: TokenDecoder
        let count: Int?
        var currentIndex = 0
        var cursor: Int64
        let end: Int64
        var codingPath: [CodingKey] { decoder.codingPath }
        var isAtEnd: Bool { currentIndex >= (count ?? 0) }

        mutating func decodeNil() throws -> Bool {
            let range = try nextRange(advance: false)
            if try decoder.source.nodeHeader(in: range).tag == .null {
                _ = try nextRange(advance: true)
                return true
            }
            return false
        }

        mutating func decode(_ type: Bool.Type) throws -> Bool { try scalar().decode(type) }
        mutating func decode(_ type: String.Type) throws -> String { try scalar().decode(type) }
        mutating func decode(_ type: Double.Type) throws -> Double { try scalar().decode(type) }
        mutating func decode(_ type: Float.Type) throws -> Float { try scalar().decode(type) }
        mutating func decode(_ type: Int.Type) throws -> Int { try scalar().decode(type) }
        mutating func decode(_ type: Int8.Type) throws -> Int8 { try scalar().decode(type) }
        mutating func decode(_ type: Int16.Type) throws -> Int16 { try scalar().decode(type) }
        mutating func decode(_ type: Int32.Type) throws -> Int32 { try scalar().decode(type) }
        mutating func decode(_ type: Int64.Type) throws -> Int64 { try scalar().decode(type) }
        mutating func decode(_ type: UInt.Type) throws -> UInt { try scalar().decode(type) }
        mutating func decode(_ type: UInt8.Type) throws -> UInt8 { try scalar().decode(type) }
        mutating func decode(_ type: UInt16.Type) throws -> UInt16 { try scalar().decode(type) }
        mutating func decode(_ type: UInt32.Type) throws -> UInt32 { try scalar().decode(type) }
        mutating func decode(_ type: UInt64.Type) throws -> UInt64 { try scalar().decode(type) }

        mutating func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
            let index = currentIndex
            let range = try nextRange(advance: true)
            return try decoder.child(range, key: IndexKey(intValue: index)).decode(type)
        }

        mutating func nestedContainer<NestedKey>(keyedBy _: NestedKey.Type) throws -> KeyedDecodingContainer<NestedKey> where NestedKey: CodingKey {
            let index = currentIndex
            let range = try nextRange(advance: true)
            return try decoder.child(range, key: IndexKey(intValue: index)).container(keyedBy: NestedKey.self)
        }

        mutating func nestedUnkeyedContainer() throws -> UnkeyedDecodingContainer {
            let index = currentIndex
            let range = try nextRange(advance: true)
            return try decoder.child(range, key: IndexKey(intValue: index)).unkeyedContainer()
        }

        mutating func superDecoder() throws -> Decoder {
            let index = currentIndex
            let range = try nextRange(advance: true)
            return try decoder.child(range, key: IndexKey(intValue: index))
        }

        private mutating func scalar() throws -> SingleValueDecoding {
            let index = currentIndex
            let range = try nextRange(advance: true)
            return SingleValueDecoding(decoder: try decoder.child(
                range,
                key: IndexKey(intValue: index)
            ))
        }

        private mutating func nextRange(advance: Bool) throws -> FileRange {
            guard !isAtEnd, cursor + 8 <= end else { throw CodecError.malformedToken }
            let lengthValue = try decoder.source.readUInt64(offset: cursor)
            guard lengthValue <= UInt64(Int64.max) else { throw CodecError.malformedToken }
            let length = Int64(lengthValue)
            let range = FileRange(offset: cursor + 8, length: length)
            let next = range.offset.addingReportingOverflow(length)
            guard length >= 9, !next.overflow, next.partialValue <= end else {
                throw CodecError.malformedToken
            }
            _ = try decoder.source.nodeHeader(in: range)
            if advance {
                cursor = next.partialValue
                currentIndex += 1
                if isAtEnd, cursor != end { throw CodecError.trailingBytes }
            }
            return range
        }
    }

    fileprivate struct SingleValueDecoding: SingleValueDecodingContainer {
        let decoder: TokenDecoder
        var codingPath: [CodingKey] { decoder.codingPath }

        func decodeNil() -> Bool {
            (try? decoder.source.nodeHeader(in: decoder.range).tag) == .null
        }

        func decode(_ type: Bool.Type) throws -> Bool {
            let header = try expected(.boolean, length: 1)
            let byte = try decoder.source.readByte(offset: header.payloadOffset)
            guard byte == 0 || byte == 1 else { throw CodecError.malformedToken }
            return byte == 1
        }

        func decode(_ type: String.Type) throws -> String {
            let header = try expected(.string)
            guard header.payloadLength <= Int64(Int.max) else { throw CodecError.malformedToken }
            return try decoder.source.decodeUTF8String(
                offset: header.payloadOffset,
                count: Int(header.payloadLength)
            )
        }

        func decode(_ type: Double.Type) throws -> Double {
            let header = try expected(.double, length: 8)
            let value = Double(bitPattern: try decoder.source.readUInt64(offset: header.payloadOffset))
            guard value.isFinite else { throw CodecError.invalidNumber }
            return value
        }

        func decode(_ type: Float.Type) throws -> Float {
            let value = try decode(Double.self)
            guard value >= -Double(Float.greatestFiniteMagnitude),
                  value <= Double(Float.greatestFiniteMagnitude) else {
                throw CodecError.invalidNumber
            }
            return Float(value)
        }

        func decode(_ type: Int.Type) throws -> Int { try exactSigned(Int.self) }
        func decode(_ type: Int8.Type) throws -> Int8 { try exactSigned(Int8.self) }
        func decode(_ type: Int16.Type) throws -> Int16 { try exactSigned(Int16.self) }
        func decode(_ type: Int32.Type) throws -> Int32 { try exactSigned(Int32.self) }
        func decode(_ type: Int64.Type) throws -> Int64 {
            let header = try expected(.signedInteger, length: 8)
            return Int64(bitPattern: try decoder.source.readUInt64(offset: header.payloadOffset))
        }
        func decode(_ type: UInt.Type) throws -> UInt { try exactUnsigned(UInt.self) }
        func decode(_ type: UInt8.Type) throws -> UInt8 { try exactUnsigned(UInt8.self) }
        func decode(_ type: UInt16.Type) throws -> UInt16 { try exactUnsigned(UInt16.self) }
        func decode(_ type: UInt32.Type) throws -> UInt32 { try exactUnsigned(UInt32.self) }
        func decode(_ type: UInt64.Type) throws -> UInt64 {
            let header = try expected(.unsignedInteger, length: 8)
            return try decoder.source.readUInt64(offset: header.payloadOffset)
        }

        func decode<T>(_ type: T.Type) throws -> T where T: Decodable {
            try decoder.decode(type)
        }

        private func expected(_ tag: Tag, length: Int64? = nil) throws -> NodeHeader {
            let header = try decoder.source.nodeHeader(in: decoder.range)
            guard header.tag == tag, length.map({ $0 == header.payloadLength }) ?? true else {
                throw CodecError.malformedToken
            }
            return header
        }

        private func exactSigned<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
            let value = try decode(Int64.self)
            guard let result = T(exactly: value) else { throw CodecError.invalidNumber }
            return result
        }

        private func exactUnsigned<T: FixedWidthInteger>(_ type: T.Type) throws -> T {
            let value = try decode(UInt64.self)
            guard let result = T(exactly: value) else { throw CodecError.invalidNumber }
            return result
        }
    }
}
