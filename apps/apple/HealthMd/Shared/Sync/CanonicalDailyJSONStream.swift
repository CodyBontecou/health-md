import Foundation

/// Validates and compacts one canonical daily JSON document with bounded working
/// memory. The source may be arbitrarily large; only object keys and selected
/// schema scalars are captured.
enum CanonicalDailyJSONStream {
    enum StreamError: Error, Equatable {
        case malformedJSON
        case nestingTooDeep
        case tokenTooLarge
        case schemaMismatch
        case archiveSchemaMismatch
    }

    static func compactValidated(
        sourceURL: URL,
        expectsLosslessArchive: Bool
    ) throws -> ConnectedTransferPreparedFile {
        let outputURL = try ConnectedTransferFile.makeRestrictedTemporaryFile(
            prefix: "canonical-day-compact"
        )
        do {
            let parser = try Parser(sourceURL: sourceURL, outputURL: outputURL)
            let metadata = try parser.parse()
            guard metadata.rootIsObject,
                  metadata.schema == HealthMdExportSchema.identifier,
                  metadata.schemaVersion == HealthMdExportSchema.version else {
                throw StreamError.schemaMismatch
            }
            if expectsLosslessArchive {
                guard metadata.sawArchive,
                      metadata.archiveSchema == HealthKitRecordArchive.canonicalSchemaIdentifier,
                      metadata.archiveSchemaVersion == HealthKitRecordArchive.currentRecordSchemaVersion else {
                    throw StreamError.archiveSchemaMismatch
                }
            } else if metadata.sawArchive {
                // Summary projections must not over-deliver granular source
                // records merely because a mismatched peer included an archive.
                throw StreamError.archiveSchemaMismatch
            }
            return try ConnectedTransferFile.inspect(outputURL)
        } catch {
            try? FileManager.default.removeItem(at: outputURL)
            throw error
        }
    }

    private struct Metadata {
        var rootIsObject = false
        var schema: String?
        var schemaVersion: Int?
        var sawArchive = false
        var archiveSchema: String?
        var archiveSchemaVersion: Int?
    }

    private final class Parser {
        private let reader: Reader
        private let writer: Writer
        private var metadata = Metadata()
        private let maximumDepth = 256
        private let maximumKeyBytes = 4_096
        private let maximumScalarBytes = 8_192
        private let maximumKeysPerObject = 16_384

        init(sourceURL: URL, outputURL: URL) throws {
            reader = try Reader(fileURL: sourceURL)
            writer = try Writer(fileURL: outputURL)
        }

        func parse() throws -> Metadata {
            try skipWhitespace()
            try parseValue(path: [], depth: 0)
            try skipWhitespace()
            guard try reader.peek() == nil else { throw StreamError.malformedJSON }
            try writer.finish()
            return metadata
        }

        private func parseValue(path: [String], depth: Int) throws {
            guard depth <= maximumDepth, let byte = try reader.peek() else {
                throw depth > maximumDepth ? StreamError.nestingTooDeep : StreamError.malformedJSON
            }
            switch byte {
            case 0x7b: try parseObject(path: path, depth: depth + 1)
            case 0x5b: try parseArray(path: path, depth: depth + 1)
            case 0x22:
                let capture = shouldCapture(path)
                let value = try parseString(capture: capture, limit: maximumScalarBytes)
                applyCapturedString(value, path: path)
            case 0x74: try parseLiteral("true")
            case 0x66: try parseLiteral("false")
            case 0x6e: try parseLiteral("null")
            case 0x2d, 0x30...0x39:
                let value = try parseNumber(capture: shouldCapture(path))
                applyCapturedNumber(value, path: path)
            default: throw StreamError.malformedJSON
            }
        }

        private func parseObject(path: [String], depth: Int) throws {
            if path.isEmpty { metadata.rootIsObject = true }
            if path == ["healthkit_record_archive"] { metadata.sawArchive = true }
            try expect(0x7b)
            try skipWhitespace()
            if try consumeIf(0x7d) { return }
            var keys: Set<String> = []
            while true {
                guard keys.count < maximumKeysPerObject,
                      try reader.peek() == 0x22,
                      let key = try parseString(capture: true, limit: maximumKeyBytes) else {
                    throw keys.count >= maximumKeysPerObject
                        ? StreamError.tokenTooLarge : StreamError.malformedJSON
                }
                guard keys.insert(key).inserted else { throw StreamError.malformedJSON }
                try skipWhitespace()
                try expect(0x3a)
                try skipWhitespace()
                try parseValue(path: path + [key], depth: depth)
                try skipWhitespace()
                if try consumeIf(0x7d) { return }
                try expect(0x2c)
                try skipWhitespace()
            }
        }

        private func parseArray(path: [String], depth: Int) throws {
            try expect(0x5b)
            try skipWhitespace()
            if try consumeIf(0x5d) { return }
            while true {
                try parseValue(path: path + ["[]"], depth: depth)
                try skipWhitespace()
                if try consumeIf(0x5d) { return }
                try expect(0x2c)
                try skipWhitespace()
            }
        }

        private func parseString(capture: Bool, limit: Int) throws -> String? {
            try expect(0x22)
            var encoded = capture ? Data([0x22]) : Data()
            var continuationBytes = 0
            var nextContinuationRange: ClosedRange<UInt8> = 0x80...0xbf
            while let byte = try reader.read() {
                if byte == 0x22 {
                    try writer.write(byte)
                    guard continuationBytes == 0 else { throw StreamError.malformedJSON }
                    guard capture else { return nil }
                    encoded.append(0x22)
                    guard let value = try JSONSerialization.jsonObject(
                        with: encoded,
                        options: [.fragmentsAllowed]
                    ) as? String else {
                        throw StreamError.malformedJSON
                    }
                    return value
                }
                if byte < 0x20 { throw StreamError.malformedJSON }
                if capture {
                    guard encoded.count < limit else { throw StreamError.tokenTooLarge }
                    encoded.append(byte)
                }
                if byte == 0x5c {
                    guard continuationBytes == 0,
                          let escaped = try reader.read(),
                          [0x22, 0x5c, 0x2f, 0x62, 0x66, 0x6e, 0x72, 0x74, 0x75]
                            .contains(escaped) else {
                        throw StreamError.malformedJSON
                    }
                    if escaped == 0x2f {
                        // Match JSONSerialization's `.withoutEscapingSlashes`
                        // output used by the legacy strict-result writer.
                        try writer.write(escaped)
                    } else {
                        try writer.write(byte)
                        try writer.write(escaped)
                    }
                    if capture { encoded.append(escaped) }
                    if escaped == 0x75 {
                        for _ in 0..<4 {
                            guard let hex = try reader.read(),
                                  (0x30...0x39).contains(hex)
                                    || (0x41...0x46).contains(hex)
                                    || (0x61...0x66).contains(hex) else {
                                throw StreamError.malformedJSON
                            }
                            try writer.write(hex)
                            if capture { encoded.append(hex) }
                        }
                    }
                } else {
                    try writer.write(byte)
                    try validateUTF8Byte(
                        byte,
                        continuationBytes: &continuationBytes,
                        nextContinuationRange: &nextContinuationRange
                    )
                }
            }
            throw StreamError.malformedJSON
        }

        private func parseNumber(capture: Bool) throws -> String? {
            var bytes = Data()
            while let byte = try reader.peek(),
                  (0x30...0x39).contains(byte)
                    || [0x2d, 0x2b, 0x2e, 0x45, 0x65].contains(byte) {
                _ = try reader.read()
                try writer.write(byte)
                guard bytes.count < 1_024 else { throw StreamError.tokenTooLarge }
                bytes.append(byte)
            }
            guard !bytes.isEmpty,
                  (try? JSONSerialization.jsonObject(
                    with: bytes,
                    options: [.fragmentsAllowed]
                  )) is NSNumber else {
                throw StreamError.malformedJSON
            }
            return capture ? String(data: bytes, encoding: .utf8) : nil
        }

        private func parseLiteral(_ literal: String) throws {
            for byte in literal.utf8 { try expect(byte) }
        }

        private func skipWhitespace() throws {
            while let byte = try reader.peek(), [0x20, 0x09, 0x0a, 0x0d].contains(byte) {
                _ = try reader.read()
            }
        }

        private func expect(_ expected: UInt8) throws {
            guard try reader.read() == expected else { throw StreamError.malformedJSON }
            try writer.write(expected)
        }

        private func consumeIf(_ expected: UInt8) throws -> Bool {
            guard try reader.peek() == expected else { return false }
            _ = try reader.read()
            try writer.write(expected)
            return true
        }

        private func shouldCapture(_ path: [String]) -> Bool {
            path == ["schema"]
                || path == ["schema_version"]
                || path == ["healthkit_record_archive", "schema"]
                || path == ["healthkit_record_archive", "schema_version"]
        }

        private func applyCapturedString(_ value: String?, path: [String]) {
            if path == ["schema"] { metadata.schema = value }
            if path == ["healthkit_record_archive", "schema"] {
                metadata.archiveSchema = value
            }
        }

        private func applyCapturedNumber(_ value: String?, path: [String]) {
            guard let value, let integer = Int(value) else { return }
            if path == ["schema_version"] { metadata.schemaVersion = integer }
            if path == ["healthkit_record_archive", "schema_version"] {
                metadata.archiveSchemaVersion = integer
            }
        }

        private func validateUTF8Byte(
            _ byte: UInt8,
            continuationBytes: inout Int,
            nextContinuationRange: inout ClosedRange<UInt8>
        ) throws {
            if continuationBytes > 0 {
                guard nextContinuationRange.contains(byte) else { throw StreamError.malformedJSON }
                continuationBytes -= 1
                nextContinuationRange = 0x80...0xbf
                return
            }
            switch byte {
            case 0x00...0x7f: return
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
            default: throw StreamError.malformedJSON
            }
        }
    }

    private final class Reader {
        private let handle: FileHandle
        private var buffer = Data()
        private var index = 0
        private var reachedEOF = false

        init(fileURL: URL) throws { handle = try FileHandle(forReadingFrom: fileURL) }
        deinit { try? handle.close() }

        func peek() throws -> UInt8? {
            try fillIfNeeded()
            return index < buffer.count ? buffer[index] : nil
        }

        func read() throws -> UInt8? {
            try fillIfNeeded()
            guard index < buffer.count else { return nil }
            defer { index += 1 }
            return buffer[index]
        }

        private func fillIfNeeded() throws {
            guard index >= buffer.count, !reachedEOF else { return }
            buffer = try handle.read(upToCount: 64 * 1_024) ?? Data()
            index = 0
            reachedEOF = buffer.isEmpty
        }
    }

    private final class Writer {
        private let handle: FileHandle
        private var buffer = Data()
        private var finished = false

        init(fileURL: URL) throws {
            handle = try FileHandle(forWritingTo: fileURL)
            buffer.reserveCapacity(64 * 1_024)
        }

        deinit { try? handle.close() }

        func write(_ byte: UInt8) throws {
            buffer.append(byte)
            if buffer.count >= 64 * 1_024 { try flush() }
        }

        func finish() throws {
            guard !finished else { return }
            try flush()
            try handle.synchronize()
            try handle.close()
            finished = true
        }

        private func flush() throws {
            guard !buffer.isEmpty else { return }
            try handle.write(contentsOf: buffer)
            buffer.removeAll(keepingCapacity: true)
        }
    }
}
