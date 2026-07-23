import Foundation

func canonicalLoopbackBaseURL(_ value: String) throws -> String {
    guard let components = URLComponents(string: value),
          components.scheme?.lowercased() == "http",
          components.user == nil,
          components.password == nil,
          components.query == nil,
          components.fragment == nil,
          components.path.isEmpty || components.path == "/",
          let parsedHost = components.host?.lowercased(),
          components.url != nil else {
        throw CLIError.invalidURL(value)
    }
    let host = parsedHost.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
    guard ["127.0.0.1", "::1", "localhost"].contains(host) else {
        throw CLIError.invalidURL(value)
    }
    var canonical = URLComponents()
    canonical.scheme = "http"
    canonical.host = parsedHost
    canonical.port = components.port
    guard let result = canonical.string else { throw CLIError.invalidURL(value) }
    return result
}

enum StreamingStrictRawValidationError: Error {
    case malformedJSON
    case nestingTooDeep
    case capturedTokenTooLarge
}

enum StreamingJSONPathComponent: Equatable {
    case key(String)
    case index(Int)
}

enum StreamingJSONScalar {
    case string(String)
    case number(String)
    case boolean(Bool)
    case null
}

/// Validates the strict public response while reading bounded file chunks. It
/// deliberately captures only schema/date/count scalars; raw health strings and
/// nested sample values are scanned for valid JSON syntax but never retained.
func streamingStrictRawValidationIssues(
    fileURL: URL,
    expectedDates: [String],
    expectedProfile: String? = nil
) throws -> [String] {
    let accumulator = StreamingStrictRawAccumulator(
        expectedDates: expectedDates,
        expectedProfile: expectedProfile
    )
    let parser = try StreamingJSONParser(fileURL: fileURL, visitor: accumulator)
    try parser.parse()
    return accumulator.issues()
}

private final class StreamingStrictRawAccumulator: StreamingJSONVisitor {
    private struct Day {
        var date: String?
        var status: String?
        var hasHealthData = false
        var dailySchema: String?
        var dailySchemaVersion: Int?
        var hasArchive = false
        var archiveSchema: String?
        var archiveSchemaVersion: Int?
    }

    private let expectedDates: [String]
    private let expectedProfile: String?
    private var responseStatus: String?
    private var rawSchema: String?
    private var rawSchemaVersion: Int?
    private var rawProfile: String?
    private var selectionDetailLevel: String?
    private var sawCanonicalSelection = false
    private var rawCreatedAt: String?
    private var rawSourceDeviceName: String?
    private var rawDateStart: String?
    private var rawDateEnd: String?
    private var totalRequestedDays: Int?
    private var retainedDayCount: Int?
    private var missingDayCount: Int?
    private var missingDates: [Int: String] = [:]
    private var days: [Int: Day] = [:]
    private var sawRootObject = false
    private var sawRawResultObject = false
    private var sawDaysArray = false
    private var sawCaptureSummary = false
    private var sawUnexpectedDayIndex = false
    private var sawUnexpectedMissingDateIndex = false

    init(expectedDates: [String], expectedProfile: String?) {
        self.expectedDates = expectedDates
        self.expectedProfile = expectedProfile
    }

    func wantsScalar(at path: [StreamingJSONPathComponent]) -> Bool {
        if path == [.key("status")] { return true }
        if path.count == 2, path[0] == .key("raw_result") {
            return [
                "schema", "schema_version", "profile", "created_at",
                "source_device_name", "total_requested_days"
            ].contains(path.key(at: 1))
        }
        if path == [
            .key("raw_result"), .key("canonical_selection"), .key("detail_level")
        ] { return true }
        if path.count == 3,
           path[0] == .key("raw_result"), path[1] == .key("date_range") {
            return path.key(at: 2) == "start" || path.key(at: 2) == "end"
        }
        if path.count == 3,
           path[0] == .key("raw_result"), path[1] == .key("missing_dates"),
           path.index(at: 2) != nil { return true }
        if path.count == 3,
           path[0] == .key("raw_result"), path[1] == .key("capture_summary") {
            return path.key(at: 2) == "retained_day_count" || path.key(at: 2) == "missing_day_count"
        }
        guard path.count >= 4,
              path[0] == .key("raw_result"), path[1] == .key("days"),
              path.index(at: 2) != nil else { return false }
        if path.count == 4 {
            return path.key(at: 3) == "date" || path.key(at: 3) == "status"
        }
        if path.count == 5, path[3] == .key("health_data") {
            return path.key(at: 4) == "schema" || path.key(at: 4) == "schema_version"
        }
        if path.count == 6,
           path[3] == .key("health_data"),
           path[4] == .key("healthkit_record_archive") {
            return path.key(at: 5) == "schema" || path.key(at: 5) == "schema_version"
        }
        return false
    }

    func didStartObject(at path: [StreamingJSONPathComponent]) {
        if path.isEmpty { sawRootObject = true }
        if path == [.key("raw_result")] { sawRawResultObject = true }
        if path == [.key("raw_result"), .key("capture_summary")] { sawCaptureSummary = true }
        if path == [.key("raw_result"), .key("canonical_selection")] {
            sawCanonicalSelection = true
        }
        guard path.count >= 4,
              path[0] == .key("raw_result"), path[1] == .key("days"),
              let index = path.index(at: 2) else { return }
        guard expectedDates.indices.contains(index) else {
            sawUnexpectedDayIndex = true
            return
        }
        if path.count == 4, path[3] == .key("health_data") {
            days[index, default: Day()].hasHealthData = true
        }
        if path.count == 5,
           path[3] == .key("health_data"),
           path[4] == .key("healthkit_record_archive") {
            days[index, default: Day()].hasArchive = true
        }
    }

    func didStartArray(at path: [StreamingJSONPathComponent]) {
        if path == [.key("raw_result"), .key("days")] { sawDaysArray = true }
    }

    func didReadScalar(_ scalar: StreamingJSONScalar, at path: [StreamingJSONPathComponent]) {
        if path == [.key("status")] { responseStatus = scalar.stringValue; return }
        if path == [.key("raw_result"), .key("schema")] { rawSchema = scalar.stringValue; return }
        if path == [.key("raw_result"), .key("schema_version")] { rawSchemaVersion = scalar.intValue; return }
        if path == [.key("raw_result"), .key("profile")] { rawProfile = scalar.stringValue; return }
        if path == [.key("raw_result"), .key("canonical_selection"), .key("detail_level")] {
            selectionDetailLevel = scalar.stringValue; return
        }
        if path == [.key("raw_result"), .key("created_at")] { rawCreatedAt = scalar.stringValue; return }
        if path == [.key("raw_result"), .key("source_device_name")] {
            rawSourceDeviceName = scalar.stringValue; return
        }
        if path == [.key("raw_result"), .key("total_requested_days")] { totalRequestedDays = scalar.intValue; return }
        if path == [.key("raw_result"), .key("date_range"), .key("start")] { rawDateStart = scalar.stringValue; return }
        if path == [.key("raw_result"), .key("date_range"), .key("end")] { rawDateEnd = scalar.stringValue; return }
        if path == [.key("raw_result"), .key("capture_summary"), .key("retained_day_count")] {
            retainedDayCount = scalar.intValue; return
        }
        if path == [.key("raw_result"), .key("capture_summary"), .key("missing_day_count")] {
            missingDayCount = scalar.intValue; return
        }
        if path.count == 3,
           path[0] == .key("raw_result"), path[1] == .key("missing_dates"),
           let index = path.index(at: 2), let value = scalar.stringValue {
            guard expectedDates.indices.contains(index) else {
                sawUnexpectedMissingDateIndex = true
                return
            }
            missingDates[index] = value
            return
        }
        guard path.count >= 4,
              path[0] == .key("raw_result"), path[1] == .key("days"),
              let index = path.index(at: 2), let key = path.key(at: path.count - 1) else { return }
        guard expectedDates.indices.contains(index) else {
            sawUnexpectedDayIndex = true
            return
        }
        var day = days[index, default: Day()]
        if path.count == 4 {
            if key == "date" { day.date = scalar.stringValue }
            if key == "status" { day.status = scalar.stringValue }
        } else if path.count == 5, path[3] == .key("health_data") {
            if key == "schema" { day.dailySchema = scalar.stringValue }
            if key == "schema_version" { day.dailySchemaVersion = scalar.intValue }
        } else if path.count == 6,
                  path[3] == .key("health_data"),
                  path[4] == .key("healthkit_record_archive") {
            if key == "schema" { day.archiveSchema = scalar.stringValue }
            if key == "schema_version" { day.archiveSchemaVersion = scalar.intValue }
        }
        days[index] = day
    }

    func issues() -> [String] {
        var issues: [String] = []
        if !sawRootObject { issues.append("success_response_not_object") }
        if responseStatus != "success" && responseStatus != "partial_success" {
            issues.append("success_response_status_mismatch")
        }
        if !sawRawResultObject { issues.append("raw_result_missing") }
        if rawSchema != "healthmd.raw_result" { issues.append("raw_result_schema_mismatch") }
        if rawSchemaVersion != 1 { issues.append("raw_result_schema_version_mismatch") }
        let recognizedProfiles = Set(["canonical_source_records_v1", "health_data_projection"])
        if !recognizedProfiles.contains(rawProfile ?? "")
            || (expectedProfile != nil && rawProfile != expectedProfile) {
            issues.append("raw_result_profile_mismatch")
        }
        if rawProfile == "health_data_projection" {
            if !sawCanonicalSelection { issues.append("canonical_selection_missing") }
            if selectionDetailLevel != "summary" && selectionDetailLevel != "lossless" {
                issues.append("canonical_selection_detail_mismatch")
            }
        }
        if rawCreatedAt == nil { issues.append("raw_result_created_at_missing") }
        if rawSourceDeviceName == nil { issues.append("raw_result_source_device_name_missing") }
        if totalRequestedDays != expectedDates.count { issues.append("raw_result_total_requested_days_mismatch") }
        if rawDateStart != expectedDates.first || rawDateEnd != expectedDates.last {
            issues.append("raw_result_date_range_mismatch")
        }
        if !sawDaysArray { issues.append("raw_result_days_missing") }
        if !sawCaptureSummary { issues.append("raw_result_capture_summary_missing") }

        let orderedDays = days.keys.sorted().compactMap { days[$0] }
        if sawUnexpectedDayIndex || days.keys.sorted() != Array(0..<days.count) {
            issues.append("raw_result_day_index_mismatch")
        }
        let suppliedDates = orderedDays.compactMap(\.date)
        if suppliedDates != expectedDates { issues.append("raw_result_date_set_mismatch") }
        if Set(suppliedDates).count != suppliedDates.count { issues.append("raw_result_duplicate_dates") }
        let calculatedMissing = orderedDays.compactMap { $0.status == "missing" ? $0.date : nil }
        let declaredMissing = missingDates.keys.sorted().compactMap { missingDates[$0] }
        if sawUnexpectedMissingDateIndex || declaredMissing != calculatedMissing {
            issues.append("raw_result_missing_dates_mismatch")
        }
        let retained = orderedDays.filter(\.hasHealthData).count
        if retainedDayCount != retained || missingDayCount != calculatedMissing.count {
            issues.append("raw_result_capture_summary_mismatch")
        }

        for day in orderedDays {
            let date = day.date ?? "unknown"
            if day.hasHealthData {
                if day.dailySchema != "healthmd.health_data" { issues.append("daily_schema_mismatch:\(date)") }
                if day.dailySchemaVersion != currentDailySchemaVersion {
                    issues.append("daily_schema_version_mismatch:\(date)")
                }
                let expectsArchive = rawProfile == "canonical_source_records_v1"
                    || selectionDetailLevel == "lossless"
                if expectsArchive {
                    if !day.hasArchive { issues.append("canonical_archive_missing:\(date)") }
                    if day.archiveSchema != "healthmd.healthkit_records" {
                        issues.append("canonical_archive_schema_mismatch:\(date)")
                    }
                    if day.archiveSchemaVersion != 1 {
                        issues.append("canonical_archive_schema_version_mismatch:\(date)")
                    }
                } else if day.hasArchive {
                    issues.append("canonical_archive_not_requested_but_present:\(date)")
                }
            } else if !(responseStatus == "partial_success"
                        && ["failed", "cancelled", "missing"].contains(day.status ?? "")) {
                issues.append("daily_health_data_missing:\(date)")
            }
        }
        return issues
    }
}

private protocol StreamingJSONVisitor: AnyObject {
    func wantsScalar(at path: [StreamingJSONPathComponent]) -> Bool
    func didStartObject(at path: [StreamingJSONPathComponent])
    func didEndObject(at path: [StreamingJSONPathComponent], byteRange: Range<Int64>)
    func didStartArray(at path: [StreamingJSONPathComponent])
    func didReadScalar(_ scalar: StreamingJSONScalar, at path: [StreamingJSONPathComponent])
}

private extension StreamingJSONVisitor {
    func didEndObject(at _: [StreamingJSONPathComponent], byteRange _: Range<Int64>) {}
}

private final class StreamingJSONParser {
    private let reader: StreamingByteReader
    private weak var visitor: StreamingJSONVisitor?
    private let maximumDepth = 256

    init(fileURL: URL, visitor: StreamingJSONVisitor) throws {
        reader = try StreamingByteReader(fileURL: fileURL)
        self.visitor = visitor
    }

    func parse() throws {
        try skipWhitespace()
        try parseValue(path: [], depth: 0)
        try skipWhitespace()
        guard try reader.peek() == nil else { throw StreamingStrictRawValidationError.malformedJSON }
    }

    private func parseValue(path: [StreamingJSONPathComponent], depth: Int) throws {
        guard depth <= maximumDepth, let byte = try reader.peek() else {
            throw depth > maximumDepth
                ? StreamingStrictRawValidationError.nestingTooDeep
                : StreamingStrictRawValidationError.malformedJSON
        }
        switch byte {
        case 0x7b: try parseObject(path: path, depth: depth + 1) // {
        case 0x5b: try parseArray(path: path, depth: depth + 1) // [
        case 0x22:
            let value = try parseString(capture: visitor?.wantsScalar(at: path) == true, limit: 8_192)
            if let value { visitor?.didReadScalar(.string(value), at: path) }
        case 0x74: try parseLiteral("true", scalar: .boolean(true), path: path)
        case 0x66: try parseLiteral("false", scalar: .boolean(false), path: path)
        case 0x6e: try parseLiteral("null", scalar: .null, path: path)
        case 0x2d, 0x30...0x39:
            let number = try parseNumber(capture: visitor?.wantsScalar(at: path) == true)
            if let number { visitor?.didReadScalar(.number(number), at: path) }
        default: throw StreamingStrictRawValidationError.malformedJSON
        }
    }

    private func parseObject(path: [StreamingJSONPathComponent], depth: Int) throws {
        let startOffset = reader.offset
        try expect(0x7b)
        visitor?.didStartObject(at: path)
        try skipWhitespace()
        if try consumeIf(0x7d) {
            visitor?.didEndObject(at: path, byteRange: startOffset..<reader.offset)
            return
        }
        var seenValidatedKeys = Set<String>()
        while true {
            guard try reader.peek() == 0x22,
                  let key = try parseString(capture: true, limit: 1_024) else {
                throw StreamingStrictRawValidationError.malformedJSON
            }
            if Self.requiresUniqueKey(key, at: path), !seenValidatedKeys.insert(key).inserted {
                throw StreamingStrictRawValidationError.malformedJSON
            }
            try skipWhitespace(); try expect(0x3a); try skipWhitespace()
            try parseValue(path: path + [.key(key)], depth: depth)
            try skipWhitespace()
            if try consumeIf(0x7d) {
                visitor?.didEndObject(at: path, byteRange: startOffset..<reader.offset)
                return
            }
            try expect(0x2c); try skipWhitespace()
        }
    }

    private func parseArray(path: [StreamingJSONPathComponent], depth: Int) throws {
        try expect(0x5b)
        visitor?.didStartArray(at: path)
        try skipWhitespace()
        if try consumeIf(0x5d) { return }
        var index = 0
        while true {
            try parseValue(path: path + [.index(index)], depth: depth)
            index += 1
            try skipWhitespace()
            if try consumeIf(0x5d) { return }
            try expect(0x2c); try skipWhitespace()
        }
    }

    private func parseString(capture: Bool, limit: Int) throws -> String? {
        try expect(0x22)
        var encoded = capture ? Data([0x22]) : Data()
        var continuationBytes = 0
        var nextContinuationRange: ClosedRange<UInt8> = 0x80...0xbf
        while let byte = try reader.read() {
            if byte == 0x22 {
                guard continuationBytes == 0 else {
                    throw StreamingStrictRawValidationError.malformedJSON
                }
                if !capture { return nil }
                encoded.append(0x22)
                guard let value = try JSONSerialization.jsonObject(
                    with: encoded,
                    options: [.fragmentsAllowed]
                ) as? String else { throw StreamingStrictRawValidationError.malformedJSON }
                return value
            }
            if byte < 0x20 { throw StreamingStrictRawValidationError.malformedJSON }
            if capture {
                guard encoded.count < limit else { throw StreamingStrictRawValidationError.capturedTokenTooLarge }
                encoded.append(byte)
            }
            if byte == 0x5c { // backslash
                guard continuationBytes == 0,
                      let escaped = try reader.read(),
                      [0x22, 0x5c, 0x2f, 0x62, 0x66, 0x6e, 0x72, 0x74, 0x75].contains(escaped) else {
                    throw StreamingStrictRawValidationError.malformedJSON
                }
                if capture { encoded.append(escaped) }
                if escaped == 0x75 {
                    for _ in 0..<4 {
                        guard let hex = try reader.read(),
                              (0x30...0x39).contains(hex) || (0x41...0x46).contains(hex) || (0x61...0x66).contains(hex) else {
                            throw StreamingStrictRawValidationError.malformedJSON
                        }
                        if capture { encoded.append(hex) }
                    }
                }
            } else {
                try Self.validateUTF8Byte(
                    byte,
                    continuationBytes: &continuationBytes,
                    nextContinuationRange: &nextContinuationRange
                )
            }
        }
        throw StreamingStrictRawValidationError.malformedJSON
    }

    private static func requiresUniqueKey(
        _ key: String,
        at path: [StreamingJSONPathComponent]
    ) -> Bool {
        if path.isEmpty { return ["status", "raw_result"].contains(key) }
        if path == [.key("raw_result")] {
            return [
                "schema", "schema_version", "profile", "canonical_selection", "created_at",
                "source_device_name", "date_range", "total_requested_days", "days",
                "capture_summary", "missing_dates"
            ].contains(key)
        }
        if path == [.key("raw_result"), .key("date_range")] {
            return key == "start" || key == "end"
        }
        if path == [.key("raw_result"), .key("canonical_selection")] {
            return ["metric_ids", "source_ids", "detail_level", "object_paths", "field_pointers"].contains(key)
        }
        if path == [.key("raw_result"), .key("capture_summary")] {
            return key == "retained_day_count" || key == "missing_day_count"
        }
        if path.count == 3,
           path[0] == .key("raw_result"), path[1] == .key("days"),
           path.index(at: 2) != nil {
            return ["date", "status", "health_data"].contains(key)
        }
        if path.count == 4,
           path[0] == .key("raw_result"), path[1] == .key("days"),
           path.index(at: 2) != nil, path[3] == .key("health_data") {
            return ["schema", "schema_version", "healthkit_record_archive"].contains(key)
        }
        if path.count == 5,
           path[0] == .key("raw_result"), path[1] == .key("days"),
           path.index(at: 2) != nil, path[3] == .key("health_data"),
           path[4] == .key("healthkit_record_archive") {
            return key == "schema" || key == "schema_version"
        }
        return false
    }

    private static func validateUTF8Byte(
        _ byte: UInt8,
        continuationBytes: inout Int,
        nextContinuationRange: inout ClosedRange<UInt8>
    ) throws {
        if continuationBytes > 0 {
            guard nextContinuationRange.contains(byte) else {
                throw StreamingStrictRawValidationError.malformedJSON
            }
            continuationBytes -= 1
            nextContinuationRange = 0x80...0xbf
            return
        }
        switch byte {
        case 0x00...0x7f:
            return
        case 0xc2...0xdf:
            continuationBytes = 1
        case 0xe0:
            continuationBytes = 2
            nextContinuationRange = 0xa0...0xbf
        case 0xe1...0xec, 0xee...0xef:
            continuationBytes = 2
        case 0xed:
            continuationBytes = 2
            nextContinuationRange = 0x80...0x9f
        case 0xf0:
            continuationBytes = 3
            nextContinuationRange = 0x90...0xbf
        case 0xf1...0xf3:
            continuationBytes = 3
        case 0xf4:
            continuationBytes = 3
            nextContinuationRange = 0x80...0x8f
        default:
            throw StreamingStrictRawValidationError.malformedJSON
        }
    }

    private func parseNumber(capture: Bool) throws -> String? {
        var bytes = Data()
        while let byte = try reader.peek(),
              (0x30...0x39).contains(byte) || [0x2d, 0x2b, 0x2e, 0x45, 0x65].contains(byte) {
            _ = try reader.read()
            guard bytes.count < 1_024 else { throw StreamingStrictRawValidationError.capturedTokenTooLarge }
            bytes.append(byte)
        }
        guard !bytes.isEmpty,
              let value = String(data: bytes, encoding: .utf8),
              (try? JSONSerialization.jsonObject(with: bytes, options: [.fragmentsAllowed])) is NSNumber else {
            throw StreamingStrictRawValidationError.malformedJSON
        }
        return capture ? value : nil
    }

    private func parseLiteral(
        _ literal: String,
        scalar: StreamingJSONScalar,
        path: [StreamingJSONPathComponent]
    ) throws {
        for byte in literal.utf8 { try expect(byte) }
        if visitor?.wantsScalar(at: path) == true { visitor?.didReadScalar(scalar, at: path) }
    }

    private func skipWhitespace() throws {
        while let byte = try reader.peek(), [0x20, 0x09, 0x0a, 0x0d].contains(byte) {
            _ = try reader.read()
        }
    }

    private func expect(_ expected: UInt8) throws {
        guard try reader.read() == expected else { throw StreamingStrictRawValidationError.malformedJSON }
    }

    private func consumeIf(_ expected: UInt8) throws -> Bool {
        guard try reader.peek() == expected else { return false }
        _ = try reader.read()
        return true
    }
}

private final class StreamingByteReader {
    private let handle: FileHandle
    private var buffer = Data()
    private var index = 0
    private var reachedEOF = false
    private(set) var offset: Int64 = 0

    init(fileURL: URL) throws {
        handle = try FileHandle(forReadingFrom: fileURL)
    }

    deinit { try? handle.close() }

    func peek() throws -> UInt8? {
        try fillIfNeeded()
        return index < buffer.count ? buffer[index] : nil
    }

    func read() throws -> UInt8? {
        try fillIfNeeded()
        guard index < buffer.count else { return nil }
        let byte = buffer[index]
        index += 1
        offset += 1
        return byte
    }

    private func fillIfNeeded() throws {
        guard index >= buffer.count, !reachedEOF else { return }
        buffer = try handle.read(upToCount: 64 * 1_024) ?? Data()
        index = 0
        reachedEOF = buffer.isEmpty
    }
}

private extension Array where Element == StreamingJSONPathComponent {
    func key(at index: Int) -> String? {
        guard indices.contains(index), case .key(let value) = self[index] else { return nil }
        return value
    }

    func index(at index: Int) -> Int? {
        guard indices.contains(index), case .index(let value) = self[index] else { return nil }
        return value
    }
}

struct CanonicalTransportDay: Equatable {
    var date: String?
    var status: String?
    var failureCode: String?
    var hasHealthData = false
    var sampleCount: Int?
    var recordCount: Int?
    var queryStatusCounts: [String: Int] = [:]
    var integrityWarningCount: Int?
    var integrityWarningCodes: [String] = []
    var partialFailureCount: Int?
    var partialFailureTypes: [String] = []
}

struct CanonicalTransportMetadata: Equatable {
    let responseStatus: String?
    let profile: String?
    let metricIDs: [String]
    let sourceIDs: [String]
    let detailLevel: String?
    let objectPaths: [String]
    let fieldPointers: [String]
    let dateStart: String?
    let dateEnd: String?
    let totalRequestedDays: Int?
    let days: [CanonicalTransportDay]
    let missingDates: [String]
    let captureSummary: [String: Int]
    let queryStatusCounts: [String: Int]
    let dayStatusCounts: [String: Int]
}

private final class CanonicalTransportMetadataCollector: StreamingJSONVisitor {
    private(set) var responseStatus: String?
    private(set) var profile: String?
    private(set) var detailLevel: String?
    private(set) var dateStart: String?
    private(set) var dateEnd: String?
    private(set) var totalRequestedDays: Int?
    private var metricIDs: [Int: String] = [:]
    private var sourceIDs: [Int: String] = [:]
    private var objectPaths: [Int: String] = [:]
    private var fieldPointers: [Int: String] = [:]
    private var missingDates: [Int: String] = [:]
    private var days: [Int: CanonicalTransportDay] = [:]
    private var captureSummary: [String: Int] = [:]
    private var queryStatusCounts: [String: Int] = [:]
    private var dayStatusCounts: [String: Int] = [:]

    func wantsScalar(at path: [StreamingJSONPathComponent]) -> Bool {
        if path == [.key("status")]
            || path == [.key("raw_result"), .key("profile")]
            || path == [.key("raw_result"), .key("total_requested_days")]
            || path == [.key("raw_result"), .key("canonical_selection"), .key("detail_level")]
            || path == [.key("raw_result"), .key("date_range"), .key("start")]
            || path == [.key("raw_result"), .key("date_range"), .key("end")] {
            return true
        }
        if path.count == 4,
           path[0] == .key("raw_result"), path[1] == .key("canonical_selection"),
           path.index(at: 3) != nil {
            return ["metric_ids", "source_ids", "object_paths", "field_pointers"]
                .contains(path.key(at: 2) ?? "")
        }
        if path.count == 3,
           path[0] == .key("raw_result"), path[1] == .key("missing_dates"),
           path.index(at: 2) != nil { return true }
        if path.count == 4,
           path[0] == .key("raw_result"), path[1] == .key("days"),
           path.index(at: 2) != nil {
            return [
                "date", "status", "failure_code", "sample_count", "record_count",
                "integrity_warning_count", "partial_failure_count"
            ].contains(path.key(at: 3) ?? "")
        }
        if path.count == 5,
           path[0] == .key("raw_result"), path[1] == .key("days"),
           path.index(at: 2) != nil {
            return path[3] == .key("query_status_counts")
                || path[3] == .key("integrity_warning_codes")
                || path[3] == .key("partial_failure_types")
        }
        if path.count == 3,
           path[0] == .key("raw_result"), path[1] == .key("capture_summary") {
            return true
        }
        if path.count == 4,
           path[0] == .key("raw_result"), path[1] == .key("capture_summary"),
           (path[2] == .key("query_status_counts") || path[2] == .key("day_status_counts")) {
            return true
        }
        return false
    }

    func didStartObject(at path: [StreamingJSONPathComponent]) {
        guard path.count == 4,
              path[0] == .key("raw_result"), path[1] == .key("days"),
              let index = path.index(at: 2), path[3] == .key("health_data") else { return }
        days[index, default: CanonicalTransportDay()].hasHealthData = true
    }
    func didStartArray(at _: [StreamingJSONPathComponent]) {}

    func didReadScalar(_ scalar: StreamingJSONScalar, at path: [StreamingJSONPathComponent]) {
        if path == [.key("status")] { responseStatus = scalar.stringValue; return }
        if path == [.key("raw_result"), .key("profile")] { profile = scalar.stringValue; return }
        if path == [.key("raw_result"), .key("total_requested_days")] {
            totalRequestedDays = scalar.intValue; return
        }
        if path == [.key("raw_result"), .key("canonical_selection"), .key("detail_level")] {
            detailLevel = scalar.stringValue; return
        }
        if path == [.key("raw_result"), .key("date_range"), .key("start")] {
            dateStart = scalar.stringValue; return
        }
        if path == [.key("raw_result"), .key("date_range"), .key("end")] {
            dateEnd = scalar.stringValue; return
        }
        if path.count == 4,
           path[0] == .key("raw_result"), path[1] == .key("canonical_selection"),
           let index = path.index(at: 3), let value = scalar.stringValue {
            switch path.key(at: 2) {
            case "metric_ids": metricIDs[index] = value
            case "source_ids": sourceIDs[index] = value
            case "object_paths": objectPaths[index] = value
            case "field_pointers": fieldPointers[index] = value
            default: break
            }
            return
        }
        if path.count == 3,
           path[0] == .key("raw_result"), path[1] == .key("missing_dates"),
           let index = path.index(at: 2), let value = scalar.stringValue {
            missingDates[index] = value
            return
        }
        if path.count == 4,
           path[0] == .key("raw_result"), path[1] == .key("days"),
           let index = path.index(at: 2), let key = path.key(at: 3) {
            var day = days[index, default: CanonicalTransportDay()]
            if key == "date" { day.date = scalar.stringValue }
            if key == "status" { day.status = scalar.stringValue }
            if key == "failure_code" { day.failureCode = scalar.stringValue }
            if key == "sample_count" { day.sampleCount = scalar.intValue }
            if key == "record_count" { day.recordCount = scalar.intValue }
            if key == "integrity_warning_count" { day.integrityWarningCount = scalar.intValue }
            if key == "partial_failure_count" { day.partialFailureCount = scalar.intValue }
            days[index] = day
            return
        }
        if path.count == 5,
           path[0] == .key("raw_result"), path[1] == .key("days"),
           let index = path.index(at: 2) {
            var day = days[index, default: CanonicalTransportDay()]
            if path[3] == .key("query_status_counts"),
               let key = path.key(at: 4), let value = scalar.intValue {
                day.queryStatusCounts[key] = value
            }
            if path[3] == .key("integrity_warning_codes"), let value = scalar.stringValue {
                day.integrityWarningCodes.append(value)
            }
            if path[3] == .key("partial_failure_types"), let value = scalar.stringValue {
                day.partialFailureTypes.append(value)
            }
            days[index] = day
            return
        }
        if path.count == 3,
           path[0] == .key("raw_result"), path[1] == .key("capture_summary"),
           let key = path.key(at: 2), let value = scalar.intValue {
            captureSummary[key] = value
            return
        }
        if path.count == 4,
           path[0] == .key("raw_result"), path[1] == .key("capture_summary"),
           let key = path.key(at: 3), let value = scalar.intValue {
            if path[2] == .key("query_status_counts") { queryStatusCounts[key] = value }
            if path[2] == .key("day_status_counts") { dayStatusCounts[key] = value }
        }
    }

    var metadata: CanonicalTransportMetadata {
        CanonicalTransportMetadata(
            responseStatus: responseStatus,
            profile: profile,
            metricIDs: metricIDs.keys.sorted().compactMap { metricIDs[$0] },
            sourceIDs: sourceIDs.keys.sorted().compactMap { sourceIDs[$0] },
            detailLevel: detailLevel,
            objectPaths: objectPaths.keys.sorted().compactMap { objectPaths[$0] },
            fieldPointers: fieldPointers.keys.sorted().compactMap { fieldPointers[$0] },
            dateStart: dateStart,
            dateEnd: dateEnd,
            totalRequestedDays: totalRequestedDays,
            days: days.keys.sorted().compactMap { days[$0] },
            missingDates: missingDates.keys.sorted().compactMap { missingDates[$0] },
            captureSummary: captureSummary,
            queryStatusCounts: queryStatusCounts,
            dayStatusCounts: dayStatusCounts
        )
    }
}

func canonicalTransportMetadata(fileURL: URL) throws -> CanonicalTransportMetadata {
    let collector = CanonicalTransportMetadataCollector()
    let parser = try StreamingJSONParser(fileURL: fileURL, visitor: collector)
    try parser.parse()
    return collector.metadata
}

private final class CanonicalHealthDataRangeCollector: StreamingJSONVisitor {
    private(set) var ranges: [Range<Int64>] = []

    func wantsScalar(at _: [StreamingJSONPathComponent]) -> Bool { false }
    func didStartObject(at _: [StreamingJSONPathComponent]) {}
    func didStartArray(at _: [StreamingJSONPathComponent]) {}
    func didReadScalar(_: StreamingJSONScalar, at _: [StreamingJSONPathComponent]) {}

    func didEndObject(at path: [StreamingJSONPathComponent], byteRange: Range<Int64>) {
        guard path.count == 4,
              path[0] == .key("raw_result"), path[1] == .key("days"),
              path.index(at: 2) != nil, path[3] == .key("health_data") else { return }
        ranges.append(byteRange)
    }
}

func canonicalHealthDataRanges(fileURL: URL) throws -> [Range<Int64>] {
    let collector = CanonicalHealthDataRangeCollector()
    let parser = try StreamingJSONParser(fileURL: fileURL, visitor: collector)
    try parser.parse()
    return collector.ranges.sorted { $0.lowerBound < $1.lowerBound }
}

private extension StreamingJSONScalar {
    var stringValue: String? {
        guard case .string(let value) = self else { return nil }
        return value
    }

    var intValue: Int? {
        guard case .number(let value) = self,
              !value.contains("."), !value.contains("e"), !value.contains("E") else { return nil }
        return Int(value)
    }
}

import CryptoKit
import Foundation

private let defaultBaseURL = "http://127.0.0.1:17645"
/// The Mac app enforces the user-selected inactivity timeout and resets it on
/// validated progress. Keep the local HTTP connection alive for corpus-scale
/// exports that can legitimately run far longer than one inactivity window.
private let corpusExportHTTPTimeout: TimeInterval = 7 * 24 * 60 * 60

struct ParsedCommand {
    var baseURL: String
    var command: Command

    init(
        baseURL: String = defaultBaseURL,
        command: Command
    ) {
        self.baseURL = baseURL
        self.command = command
    }
}

enum AgentCommand {
    case capabilities
    case query(Data)
    case evidence(Data)
    case refresh(Data)
    case jobStatus(UUID)
    case jobResume(UUID, timeout: Double)
    case jobCancel(UUID)
}

enum Command {
    case status(jobID: UUID?)
    case doctor
    case extract(ExportOptions)
    case export(ExportOptions)
    case resume(UUID, ResumeOptions)
    case cancel(UUID)
    case metrics(MetricsOptions)
    case query(MetricQueryOptions)
    case agent(AgentCommand)
    case help
    case noOp
}

struct ResumeOptions {
    var timeout: Double = 300
    var outputPath: String?
    var allowPartial = false
}

enum CanonicalExtractionFormat: String, Equatable {
    case json
    case jsonl
}

struct ExportOptions {
    var fromDate: String?
    var toDate: String?
    var lastDays: Int?
    var yesterday = false
    var allAvailable = false
    var timeout: Double = 300
    var raw = false
    var allowPartial = false
    var useIPhoneSettings = false
    var outputPath: String?
    var canonicalProjection = false
    var metricIDs: [String] = []
    var categories: [String] = []
    var allMetrics = false
    var detail: MetricQueryDetail = .summary
    var sourceIDs: [String] = []
    var objectPaths: [String] = []
    var fieldPointers: [String] = []
    var extractionFormat: CanonicalExtractionFormat = .json
    var selectionRequested = false
}

struct MetricsOptions {
    var category: String?
}

enum MetricQueryDetail: String, Equatable {
    case summary
    case lossless
}

enum MetricQueryOutputFormat: String, Equatable {
    case json
    case table
}

enum HighLevelQueryOperation: Equatable {
    case metricSeries
    case workoutListing
    case sleepSessions(windowSeconds: Double?, includeNaps: Bool)
    case workoutSleepAlignment(
        windowSeconds: Double?,
        workoutActivity: String?,
        includeNaps: Bool
    )
    case coverage
    case periodComparison(
        firstStart: String,
        firstEnd: String,
        secondStart: String,
        secondEnd: String,
        aggregations: [(metricID: String, kind: String)]
    )
    case trainingEvidence(detailIDs: [String])

    static func == (lhs: HighLevelQueryOperation, rhs: HighLevelQueryOperation) -> Bool {
        switch (lhs, rhs) {
        case (.metricSeries, .metricSeries), (.workoutListing, .workoutListing), (.coverage, .coverage):
            return true
        case let (.sleepSessions(lhsWindow, lhsNaps), .sleepSessions(rhsWindow, rhsNaps)):
            return lhsWindow == rhsWindow && lhsNaps == rhsNaps
        case let (
            .workoutSleepAlignment(lhsWindow, lhsActivity, lhsNaps),
            .workoutSleepAlignment(rhsWindow, rhsActivity, rhsNaps)
        ):
            return lhsWindow == rhsWindow
                && lhsActivity == rhsActivity
                && lhsNaps == rhsNaps
        case let (.trainingEvidence(lhsIDs), .trainingEvidence(rhsIDs)):
            return lhsIDs == rhsIDs
        case let (.periodComparison(lfs, lfe, lss, lse, la), .periodComparison(rfs, rfe, rss, rse, ra)):
            return lfs == rfs && lfe == rfe && lss == rss && lse == rse
                && la.map { [$0.metricID, $0.kind] } == ra.map { [$0.metricID, $0.kind] }
        default:
            return false
        }
    }

    var name: String {
        switch self {
        case .metricSeries: return "metric_series"
        case .workoutListing: return "workout_listing"
        case .sleepSessions: return "sleep_session_listing"
        case .workoutSleepAlignment: return "workout_sleep_alignment"
        case .coverage: return "coverage"
        case .periodComparison: return "period_comparison"
        case .trainingEvidence: return "training_evidence"
        }
    }

    var usesEvidenceEndpoint: Bool {
        if case .trainingEvidence = self { return true }
        return false
    }

    var supportsCoverageReuse: Bool {
        switch self {
        case .metricSeries, .workoutListing, .coverage, .periodComparison:
            return true
        case .trainingEvidence(let detailIDs):
            return detailIDs.isEmpty
        case .sleepSessions, .workoutSleepAlignment:
            return false
        }
    }

    func requestObject(detail: MetricQueryDetail) -> [String: Any] {
        switch self {
        case .metricSeries:
            return ["type": detail == .lossless ? "source_record_listing" : "metric_series"]
        case .workoutListing:
            return ["type": "workout_listing"]
        case .sleepSessions(let windowSeconds, let includeNaps):
            var operation: [String: Any] = [
                "type": "sleep_session_listing",
                "include_naps": includeNaps
            ]
            if let windowSeconds {
                operation["window"] = [
                    "start_offset_seconds": 0,
                    "duration_seconds": windowSeconds
                ]
            }
            return operation
        case .workoutSleepAlignment(let windowSeconds, let workoutActivity, let includeNaps):
            var operation: [String: Any] = [
                "type": "workout_sleep_alignment",
                "include_naps": includeNaps
            ]
            if let workoutActivity { operation["workout_activity"] = workoutActivity }
            if let windowSeconds {
                operation["window"] = [
                    "start_offset_seconds": 0,
                    "duration_seconds": windowSeconds
                ]
            }
            return operation
        case .coverage:
            return ["type": "coverage"]
        case .periodComparison(
            let firstStart, let firstEnd, let secondStart, let secondEnd, let aggregations
        ):
            return [
                "type": "period_comparison",
                "first": ["start_date": firstStart, "end_date": firstEnd],
                "second": ["start_date": secondStart, "end_date": secondEnd],
                "aggregations": aggregations.map {
                    ["metric_id": $0.metricID, "kind": $0.kind]
                }
            ]
        case .trainingEvidence(let detailIDs):
            return [
                "type": "derive_packet",
                "kind": "training",
                "detail_ids": Array(Set(detailIDs)).sorted()
            ]
        }
    }
}

struct MetricQueryOptions {
    var metricIDs: [String] = []
    var categories: [String] = []
    var fromDate: String?
    var toDate: String?
    var lastDays: Int?
    var yesterday = false
    var allAvailable = false
    var cached = false
    var detail: MetricQueryDetail = .summary
    var timeout: Double = 300
    var allowPartial = false
    var outputPath: String?
    var allPages = false
    var progressJSON = false
    var reuseCovered = false
    var outputFormat: MetricQueryOutputFormat = .json
    var operation: HighLevelQueryOperation = .metricSeries
}

struct HTTPResult {
    let statusCode: Int
    let payload: Any
}

struct DownloadedHTTPResult {
    let statusCode: Int
    let fileURL: URL
    let headers: [String: String]

    var exportStatus: String? { headers["x-healthmd-export-status"] }

    var bodyLength: Int64 {
        let attributes = try? FileManager.default.attributesOfItem(atPath: fileURL.path)
        return (attributes?[.size] as? NSNumber)?.int64Value ?? Int64.max
    }

    var isValidatedStrictRawResponse: Bool {
        headers["x-healthmd-raw-schema"] == "healthmd.raw_result/1"
            && headers["x-healthmd-raw-validated"] == "1"
            && headers["x-healthmd-body-sha256"] != nil
            && headers["x-healthmd-raw-date-start"] != nil
            && headers["x-healthmd-raw-date-end"] != nil
            && Int(headers["x-healthmd-raw-total-days"] ?? "") != nil
            && exportStatus != nil
    }

    func matchesRequestedRange(start: String, end: String, totalDays: Int) -> Bool {
        headers["x-healthmd-raw-date-start"] == start
            && headers["x-healthmd-raw-date-end"] == end
            && Int(headers["x-healthmd-raw-total-days"] ?? "") == totalDays
    }

    var bodyDigestIsValid: Bool {
        guard let expected = headers["x-healthmd-body-sha256"] else { return false }
        return (try? sha256OfFile(fileURL)) == expected
    }
}

enum CLIError: Error, CustomStringConvertible {
    case usage(String)
    case invalidDate(String)
    case invalidInteger(String)
    case invalidDouble(String)
    case invalidURL(String)
    case fileOutput(String)

    var description: String {
        switch self {
        case .usage(let message): return message
        case .invalidDate(let value): return "invalid date '\(value)', expected YYYY-MM-DD"
        case .invalidInteger(let value): return "invalid integer '\(value)'"
        case .invalidDouble(let value): return "invalid number '\(value)'"
        case .invalidURL(let value): return "invalid base URL '\(value)'"
        case .fileOutput(let message): return message
        }
    }
}

@main
struct HealthMdCLI {
    static func main() async {
        do {
            let parsed = try parse(Array(CommandLine.arguments.dropFirst()))
            let exitCode = try await run(parsed)
            Foundation.exit(Int32(exitCode))
        } catch let error as CLIError {
            fputs("\(error.description)\n", stderr)
            Foundation.exit(2)
        } catch {
            fputs("\(error.localizedDescription)\n", stderr)
            Foundation.exit(1)
        }
    }
}

private func run(_ parsed: ParsedCommand) async throws -> Int {
    switch parsed.command {
    case .help:
        printGeneralHelp()
        return 0
    case .noOp:
        return 0
    case .doctor:
        return await runDoctorCommand(parsed)
    case .metrics(let options):
        return try await runMetricsCommand(options, parsed: parsed)
    case .query(let options):
        return try await runMetricQueryCommand(options, parsed: parsed)
    case .agent(let command):
        let result: HTTPResult
        switch command {
        case .capabilities:
            result = await requestAgentJSON(
                method: "GET", path: "/v1/agent/capabilities",
                baseURL: parsed.baseURL
            )
        case .query(let body):
            result = await requestAgentJSON(
                method: "POST", path: "/v1/agent/query", body: body,
                baseURL: parsed.baseURL
            )
        case .evidence(let body):
            result = await requestAgentJSON(
                method: "POST", path: "/v1/agent/evidence", body: body,
                baseURL: parsed.baseURL
            )
        case .refresh(let body):
            result = await requestAgentJSON(
                method: "POST", path: "/v1/agent/refresh", body: body,
                baseURL: parsed.baseURL,
                timeout: corpusExportHTTPTimeout
            )
        case .jobStatus(let jobID):
            result = await requestAgentJSON(
                method: "GET",
                path: "/v1/agent/jobs/\(jobID.uuidString.lowercased())",
                baseURL: parsed.baseURL
            )
        case .jobResume(let jobID, let timeout):
            let body = try JSONSerialization.data(withJSONObject: ["wait_timeout_seconds": timeout])
            result = await requestAgentJSON(
                method: "POST",
                path: "/v1/agent/jobs/\(jobID.uuidString.lowercased())/resume",
                body: body, baseURL: parsed.baseURL,
                timeout: corpusExportHTTPTimeout
            )
        case .jobCancel(let jobID):
            result = await requestAgentJSON(
                method: "POST",
                path: "/v1/agent/jobs/\(jobID.uuidString.lowercased())/cancel",
                body: Data("{}".utf8), baseURL: parsed.baseURL
            )
        }
        printJSON(result.payload)
        return (200...299).contains(result.statusCode) ? 0 : 1
    case .status(nil):
        let result = await requestJSON(method: "GET", path: "/v1/status", baseURL: parsed.baseURL)
        printJSON(result.payload)
        return result.statusCode == 200 ? 0 : 1
    case .status(.some(let jobID)):
        let downloaded = await requestDownloadedJSON(
            method: "GET",
            path: "/v1/exports/\(jobID.uuidString.lowercased())",
            baseURL: parsed.baseURL,
            timeout: corpusExportHTTPTimeout
        )
        defer { try? FileManager.default.removeItem(at: downloaded.fileURL) }
        if downloaded.isValidatedStrictRawResponse,
           let start = downloaded.headers["x-healthmd-raw-date-start"],
           let end = downloaded.headers["x-healthmd-raw-date-end"] {
            let dates = requestedISODateRange(startDate: start, endDate: end)
            guard downloaded.bodyDigestIsValid,
                  downloaded.matchesRequestedRange(start: start, end: end, totalDays: dates.count),
                  (try? streamingStrictRawValidationIssues(
                    fileURL: downloaded.fileURL,
                    expectedDates: dates
                  ).isEmpty) == true else {
                printJSON(["error": "invalid_durable_raw_response"])
                return 1
            }
            let metadata = try canonicalTransportMetadata(fileURL: downloaded.fileURL)
            if metadata.profile == "health_data_projection" {
                if downloaded.exportStatus == "partial_success" {
                    printJSON([
                        "error": "partial_canonical_extraction",
                        "message": "This durable extraction is incomplete; use `healthmd resume \(jobID.uuidString.lowercased()) --allow-partial` to emit retained data.",
                        "receipt": canonicalExtractionReceipt(metadata)
                    ])
                    return 1
                }
                var extraction = ExportOptions()
                extraction.raw = true
                extraction.canonicalProjection = true
                extraction.objectPaths = metadata.objectPaths
                extraction.fieldPointers = metadata.fieldPointers
                try emitCanonicalHealthData(sourceURL: downloaded.fileURL, options: extraction)
            } else {
                try emitDownloadedResponse(downloaded.fileURL, outputPath: nil)
            }
            return exportExitCode(
                httpStatusCode: downloaded.statusCode,
                status: downloaded.exportStatus,
                isRaw: true,
                allowPartial: false
            )
        }
        guard downloaded.bodyLength <= 16 * 1_024 * 1_024 else {
            printJSON(["error": "unvalidated_response_too_large"])
            return 1
        }
        let payload = parsePayload((try? Data(contentsOf: downloaded.fileURL)) ?? Data()) ?? [:]
        printJSON(payload)
        return downloaded.statusCode == 200 || downloaded.statusCode == 202 ? 0 : 1
    case .cancel(let jobID):
        let result = await requestJSON(
            method: "POST",
            path: "/v1/exports/\(jobID.uuidString.lowercased())/cancel",
            body: [:],
            baseURL: parsed.baseURL
        )
        printJSON(result.payload)
        let status = (result.payload as? [String: Any])?["status"] as? String
        return status == "cancelled" ? 0 : 1
    case .resume(let jobID, let options):
        let downloaded = await requestDownloadedJSON(
            method: "POST",
            path: "/v1/exports/\(jobID.uuidString.lowercased())/resume",
            body: ["wait_timeout_seconds": options.timeout],
            baseURL: parsed.baseURL,
            timeout: corpusExportHTTPTimeout
        )
        defer { try? FileManager.default.removeItem(at: downloaded.fileURL) }
        if downloaded.isValidatedStrictRawResponse {
            guard let start = downloaded.headers["x-healthmd-raw-date-start"],
                  let end = downloaded.headers["x-healthmd-raw-date-end"] else {
                printJSON(["error": "raw_response_date_range_mismatch"])
                return 1
            }
            let dates = requestedISODateRange(startDate: start, endDate: end)
            guard downloaded.bodyDigestIsValid,
                  downloaded.matchesRequestedRange(start: start, end: end, totalDays: dates.count) else {
                printJSON(["error": "response_digest_or_range_mismatch"])
                return 1
            }
            let issues = (try? streamingStrictRawValidationIssues(
                fileURL: downloaded.fileURL,
                expectedDates: dates
            )) ?? ["malformed_streamed_json"]
            guard issues.isEmpty else {
                printJSON(["error": "invalid_strict_raw_success", "validation_errors": issues])
                return 1
            }
            let metadata = try canonicalTransportMetadata(fileURL: downloaded.fileURL)
            if metadata.profile == "health_data_projection" {
                if downloaded.exportStatus == "partial_success" && !options.allowPartial {
                    printJSON([
                        "error": "partial_canonical_extraction",
                        "message": "Canonical extraction was incomplete; rerun resume with --allow-partial to emit retained data.",
                        "receipt": canonicalExtractionReceipt(metadata)
                    ])
                    return 1
                }
                var extraction = ExportOptions()
                extraction.raw = true
                extraction.canonicalProjection = true
                extraction.objectPaths = metadata.objectPaths
                extraction.fieldPointers = metadata.fieldPointers
                extraction.outputPath = options.outputPath
                try emitCanonicalHealthData(sourceURL: downloaded.fileURL, options: extraction)
            } else {
                try emitDownloadedResponse(downloaded.fileURL, outputPath: options.outputPath)
            }
            return exportExitCode(
                httpStatusCode: downloaded.statusCode,
                status: downloaded.exportStatus,
                isRaw: true,
                allowPartial: options.allowPartial
            )
        }
        guard downloaded.bodyLength <= 16 * 1_024 * 1_024 else {
            printJSON(["error": "unvalidated_response_too_large"])
            return 1
        }
        let data = (try? Data(contentsOf: downloaded.fileURL)) ?? Data()
        let payload = parsePayload(data) ?? [:]
        if let outputPath = options.outputPath {
            try emitDataResponse(data, outputPath: outputPath)
        } else {
            printJSON(payload)
        }
        let status = (payload as? [String: Any])?["status"] as? String
        return exportExitCode(
            httpStatusCode: downloaded.statusCode,
            status: status,
            isRaw: false,
            allowPartial: options.allowPartial
        )
    case .extract(let options):
        let range = options.allAvailable ? nil : try resolveDateRange(options)
        var body = makeExportRequestBody(
            options: options,
            startDate: range?.start,
            endDate: range?.end
        )
        body["job_id"] = UUID().uuidString.lowercased()
        let downloaded = await requestDownloadedJSON(
            method: "POST",
            path: "/v1/exports",
            body: body,
            baseURL: parsed.baseURL,
            timeout: corpusExportHTTPTimeout
        )
        defer { try? FileManager.default.removeItem(at: downloaded.fileURL) }
        guard downloaded.isValidatedStrictRawResponse else {
            guard downloaded.bodyLength <= 16 * 1_024 * 1_024 else {
                printJSON(["error": "unvalidated_response_too_large"])
                return 1
            }
            let payload = parsePayload((try? Data(contentsOf: downloaded.fileURL)) ?? Data()) ?? [:]
            printJSON(payload)
            return 1
        }
        guard let expectedStart = options.allAvailable
                ? downloaded.headers["x-healthmd-raw-date-start"] : range?.start,
              let expectedEnd = options.allAvailable
                ? downloaded.headers["x-healthmd-raw-date-end"] : range?.end else {
            printJSON(["error": "canonical_response_date_range_mismatch"])
            return 1
        }
        let expectedDates = requestedISODateRange(startDate: expectedStart, endDate: expectedEnd)
        guard downloaded.bodyDigestIsValid,
              downloaded.matchesRequestedRange(
                  start: expectedStart,
                  end: expectedEnd,
                  totalDays: expectedDates.count
              ) else {
            printJSON(["error": "canonical_response_digest_or_range_mismatch"])
            return 1
        }
        do {
            let issues = try streamingStrictRawValidationIssues(
                fileURL: downloaded.fileURL,
                expectedDates: expectedDates,
                expectedProfile: "health_data_projection"
            )
            guard issues.isEmpty else {
                printJSON([
                    "error": "invalid_canonical_health_data_response",
                    "status": "failure",
                    "validation_errors": issues
                ])
                return 1
            }
            let metadata = try canonicalTransportMetadata(fileURL: downloaded.fileURL)
            if downloaded.exportStatus == "partial_success" && !options.allowPartial {
                printJSON([
                    "error": "partial_canonical_extraction",
                    "message": "Canonical extraction was incomplete; pass --allow-partial to emit retained data.",
                    "receipt": canonicalExtractionReceipt(metadata)
                ])
                return 1
            }
            try emitCanonicalHealthData(sourceURL: downloaded.fileURL, options: options)
        } catch {
            throw CLIError.fileOutput("could not emit canonical health_data: \(error.localizedDescription)")
        }
        return exportExitCode(
            httpStatusCode: downloaded.statusCode,
            status: downloaded.exportStatus,
            isRaw: true,
            allowPartial: options.allowPartial
        )
    case .export(let options):
        let range = options.allAvailable ? nil : try resolveDateRange(options)
        var body = makeExportRequestBody(
            options: options,
            startDate: range?.start,
            endDate: range?.end
        )
        body["job_id"] = UUID().uuidString.lowercased()
        if options.raw {
            let downloaded = await requestDownloadedJSON(
                method: "POST",
                path: "/v1/exports",
                body: body,
                baseURL: parsed.baseURL,
                timeout: corpusExportHTTPTimeout
            )
            defer { try? FileManager.default.removeItem(at: downloaded.fileURL) }
            if downloaded.isValidatedStrictRawResponse {
                guard let expectedStart = options.allAvailable
                        ? downloaded.headers["x-healthmd-raw-date-start"] : range?.start,
                      let expectedEnd = options.allAvailable
                        ? downloaded.headers["x-healthmd-raw-date-end"] : range?.end else {
                    printJSON(["error": "raw_response_date_range_mismatch"])
                    return 1
                }
                let expectedDates = requestedISODateRange(startDate: expectedStart, endDate: expectedEnd)
                guard downloaded.bodyDigestIsValid else {
                    printJSON(["error": "response_digest_mismatch"])
                    return 1
                }
                guard downloaded.matchesRequestedRange(
                    start: expectedStart,
                    end: expectedEnd,
                    totalDays: expectedDates.count
                ) else {
                    printJSON(["error": "raw_response_date_range_mismatch"])
                    return 1
                }
                do {
                    let issues = try streamingStrictRawValidationIssues(
                        fileURL: downloaded.fileURL,
                        expectedDates: expectedDates,
                        expectedProfile: "canonical_source_records_v1"
                    )
                    guard issues.isEmpty else {
                        printJSON([
                            "error": "invalid_strict_raw_success",
                            "status": "failure",
                            "validation_errors": issues
                        ])
                        return 1
                    }
                } catch {
                    printJSON([
                        "error": "invalid_strict_raw_success",
                        "status": "failure",
                        "validation_errors": ["malformed_streamed_json"]
                    ])
                    return 1
                }
                do {
                    try emitDownloadedResponse(downloaded.fileURL, outputPath: options.outputPath)
                } catch {
                    throw CLIError.fileOutput("could not write raw response: \(error.localizedDescription)")
                }
                return exportExitCode(
                    httpStatusCode: downloaded.statusCode,
                    status: downloaded.exportStatus,
                    isRaw: true,
                    allowPartial: options.allowPartial
                )
            }

            guard downloaded.bodyLength <= 16 * 1_024 * 1_024 else {
                printJSON(["error": "unvalidated_response_too_large"])
                return 1
            }
            let data = (try? Data(contentsOf: downloaded.fileURL)) ?? Data()
            let payload = parsePayload(data) ?? [:]
            let status = (payload as? [String: Any])?["status"] as? String
            if downloaded.statusCode == 200 {
                let expectedDates: [String]
                if options.allAvailable {
                    guard let resolved = strictRawResolvedDateRange(payload: payload) else {
                        printJSON(["error": "raw_response_date_range_mismatch"])
                        return 1
                    }
                    expectedDates = requestedISODateRange(startDate: resolved.start, endDate: resolved.end)
                } else {
                    guard let range else {
                        printJSON(["error": "raw_response_date_range_mismatch"])
                        return 1
                    }
                    expectedDates = requestedISODateRange(startDate: range.start, endDate: range.end)
                }
                let validation = validateStrictRawHTTPSuccess(payload: payload, expectedDates: expectedDates)
                if !validation.isValid {
                    printJSON(validation.outputPayload)
                    return 1
                }
            }
            if let outputPath = options.outputPath {
                try emitDataResponse(data, outputPath: outputPath)
            } else {
                printJSON(payload)
            }
            return exportExitCode(
                httpStatusCode: downloaded.statusCode,
                status: status,
                isRaw: true,
                allowPartial: options.allowPartial
            )
        }

        let result = await requestJSON(
            method: "POST",
            path: "/v1/exports",
            body: body,
            baseURL: parsed.baseURL,
            timeout: corpusExportHTTPTimeout
        )
        let status = (result.payload as? [String: Any])?["status"] as? String
        printJSON(result.payload)
        return exportExitCode(
            httpStatusCode: result.statusCode,
            status: status,
            isRaw: false,
            allowPartial: options.allowPartial
        )
    }
}

private func runDoctorCommand(_ parsed: ParsedCommand) async -> Int {
    let publicStatus = await requestJSON(
        method: "GET",
        path: "/v1/status",
        baseURL: parsed.baseURL
    )
    guard publicStatus.statusCode == 200 else {
        printJSON(makeCLIDoctorEnvelope(
            status: "unavailable",
            publicStatus: publicStatus.payload,
            localReadiness: nil,
            checks: [[
                "code": "mac_app",
                "status": "unavailable",
                "blocking": true,
                "message": "Health.md for Mac is not reachable on the configured loopback endpoint."
            ]],
            nextActions: [[
                "code": "open_mac_app",
                "message": "Open Health.md for Mac, then rerun healthmd doctor."
            ]]
        ))
        return 1
    }

    let readiness = await requestAgentJSON(
        method: "GET",
        path: "/v1/agent/readiness",
        baseURL: parsed.baseURL
    )
    guard readiness.statusCode == 200,
          let readinessObject = readiness.payload as? [String: Any],
          readinessObject["schema"] as? String == "healthmd.local_readiness",
          readinessObject["schema_version"] as? Int == 1 else {
        printJSON(makeCLIDoctorEnvelope(
            status: "unavailable",
            publicStatus: publicStatus.payload,
            localReadiness: readiness.payload,
            checks: publicDoctorChecks(publicStatus.payload) + [[
                "code": "local_api",
                "status": "unavailable",
                "blocking": true,
                "message": "Health.md could not return local CLI readiness."
            ]],
            nextActions: [[
                "code": "retry_local_readiness",
                "message": "Keep Health.md open and rerun healthmd doctor."
            ]]
        ))
        return 1
    }

    let status = readinessObject["status"] as? String ?? "unavailable"
    let checks = readinessObject["checks"] as? [[String: Any]] ?? []
    let nextActions = readinessObject["next_actions"] as? [[String: Any]] ?? []
    printJSON(makeCLIDoctorEnvelope(
        status: status,
        publicStatus: publicStatus.payload,
        localReadiness: readinessObject,
        checks: checks,
        nextActions: nextActions
    ))
    return status == "ready" ? 0 : 1
}

func makeCLIDoctorEnvelope(
    status: String,
    publicStatus: Any,
    localReadiness: Any?,
    checks: [[String: Any]],
    nextActions: [[String: Any]]
) -> [String: Any] {
    [
        "schema": "healthmd.cli_doctor",
        "schema_version": 1,
        "status": status,
        "public_status": publicStatus,
        "local_readiness": localReadiness ?? NSNull(),
        "checks": checks,
        "next_actions": nextActions
    ]
}

func publicDoctorChecks(_ payload: Any) -> [[String: Any]] {
    guard let object = payload as? [String: Any] else { return [] }
    var checks: [[String: Any]] = [[
        "code": "mac_app",
        "status": object["mac_app"] as? String == "running" ? "ready" : "unavailable",
        "blocking": object["mac_app"] as? String != "running",
        "message": object["mac_app"] as? String == "running"
            ? "Health.md for Mac is reachable."
            : "Health.md for Mac did not report a running state."
    ]]
    if let iphone = object["iphone"] as? [String: Any] {
        let connected = iphone["connected"] as? Bool == true
        checks.append([
            "code": "iphone_connection",
            "status": connected ? "ready" : "warning",
            "blocking": false,
            "message": connected
                ? "An iPhone is connected."
                : "No iPhone is connected; cached queries may still work."
        ])
    }
    return checks
}

private func runMetricsCommand(
    _ options: MetricsOptions,
    parsed: ParsedCommand
) async throws -> Int {
    let result = await requestAgentJSON(
        method: "GET",
        path: "/v1/agent/metrics",
        baseURL: parsed.baseURL
    )
    guard result.statusCode == 200 else {
        printJSON(result.payload)
        return 1
    }
    guard let catalog = result.payload as? [String: Any],
          catalog["schema"] as? String == "healthmd.metric_catalog",
          catalog["schema_version"] as? Int == 1,
          catalog["metrics"] is [[String: Any]] else {
        printJSON(metricQueryFailure(
            code: "invalid_metric_catalog",
            message: "The Mac app returned an invalid metric catalog."
        ))
        return 1
    }
    guard let filtered = filteredMetricCatalog(catalog, category: options.category) else {
        printJSON(metricQueryFailure(
            code: "unknown_metric_category",
            message: "No queryable Health.md metrics match the requested category.",
            details: options.category.map { ["category": $0] } ?? [:]
        ))
        return 1
    }
    printJSON(filtered)
    return 0
}

func supportsRequestScopedContextAcquisition(_ capabilities: [String: Any]) -> Bool {
    capabilities["request_scoped_context_acquisition"] as? Bool == true
}

private func runMetricQueryCommand(
    _ options: MetricQueryOptions,
    parsed: ParsedCommand
) async throws -> Int {
    let dates = try resolveMetricQueryDateSelection(options)

    let capabilitiesResult = await requestAgentJSON(
        method: "GET",
        path: "/v1/agent/capabilities",
        baseURL: parsed.baseURL
    )
    guard capabilitiesResult.statusCode == 200,
          let capabilities = capabilitiesResult.payload as? [String: Any] else {
        return try emitMetricQueryEnvelope(
            makeMetricQueryEnvelope(
                status: "failure",
                requestedMetricIDs: options.metricIDs,
                acquisition: capabilitiesResult.payload,
                query: nil,
                error: "capabilities_unavailable",
                operation: options.operation.name
            ),
            outputPath: options.outputPath,
            allowPartial: options.allowPartial
        )
    }
    if !options.cached, !supportsRequestScopedContextAcquisition(capabilities) {
        return try emitMetricQueryEnvelope(
            makeMetricQueryEnvelope(
                status: "failure",
                requestedMetricIDs: options.metricIDs,
                acquisition: metricQueryFailure(
                    code: "request_scoped_context_acquisition_unsupported",
                    message: "Update Health.md on Mac before running request-scoped metric queries.",
                    details: ["capabilities": capabilities]
                ),
                query: nil,
                error: "request_scoped_context_acquisition_unsupported",
                operation: options.operation.name
            ),
            outputPath: options.outputPath,
            allowPartial: options.allowPartial
        )
    }

    let catalogResult = await requestAgentJSON(
        method: "GET",
        path: "/v1/agent/metrics",
        baseURL: parsed.baseURL
    )
    guard catalogResult.statusCode == 200 else {
        return try emitMetricQueryEnvelope(
            makeMetricQueryEnvelope(
                status: "failure",
                requestedMetricIDs: options.metricIDs,
                acquisition: catalogResult.payload,
                query: nil,
                error: "metric_catalog_unavailable",
                operation: options.operation.name
            ),
            outputPath: options.outputPath,
            allowPartial: options.allowPartial
        )
    }
    let metricResolution = resolveRequestedMetricIDs(
        catalogResult.payload,
        directMetricIDs: options.metricIDs,
        categories: options.categories
    )
    guard let requestedMetricIDs = metricResolution.metricIDs else {
        return try emitMetricQueryEnvelope(
            makeMetricQueryEnvelope(
                status: "failure",
                requestedMetricIDs: options.metricIDs,
                acquisition: metricResolution.failure ?? metricQueryFailure(
                    code: "invalid_metric_selection",
                    message: "The requested metric selection is invalid."
                ),
                query: nil,
                error: "invalid_metric_selection",
                operation: options.operation.name
            ),
            outputPath: options.outputPath,
            allowPartial: options.allowPartial
        )
    }

    emitCLIProgress(
        enabled: options.progressJSON,
        phase: "scope_resolved",
        details: [
            "operation": options.operation.name,
            "requested_metric_ids": requestedMetricIDs,
            "acquisition_mode": options.cached ? "cached" : (options.reuseCovered ? "reuse_covered" : "fresh")
        ]
    )
    var acquisition: Any? = nil
    var acquisitionWasPartial = false
    var acquisitionRequestedScopeStatus: String?
    var acquisitionCorpusStatus: String?
    var unrelatedSkips: [Any] = []
    var acquisitionMode = options.cached ? "cached" : "fresh"
    var shouldRefresh = !options.cached

    if options.reuseCovered,
       options.detail == .summary,
       options.operation.supportsCoverageReuse {
        emitCLIProgress(
            enabled: options.progressJSON,
            phase: "coverage_reuse_check_started"
        )
        let coverageBody = makeMetricQueryRequestBody(
            dates: dates,
            metricIDs: requestedMetricIDs,
            detail: .summary,
            operation: .coverage
        )
        let coverageTraversal = try await requestMetricQueryPages(
            path: "/v1/agent/query",
            initialBody: coverageBody,
            baseURL: parsed.baseURL,
            timeout: max(10, options.timeout),
            allPages: true,
            progressJSON: options.progressJSON
        )
        let canReuse = (coverageTraversal.failure.map { _ in false } ?? true)
            && coverageTraversal.traversalComplete
            && metricCoveragePagesAreComplete(coverageTraversal.pages)
        emitCLIProgress(
            enabled: options.progressJSON,
            phase: "coverage_reuse_check_completed",
            details: [
                "cache_reused": canReuse,
                "coverage_page_count": coverageTraversal.pages.count
            ]
        )
        if canReuse {
            shouldRefresh = false
            acquisitionMode = "reused_covered_cache"
            acquisitionRequestedScopeStatus = "success"
            acquisitionCorpusStatus = "not_requested"
            acquisition = [
                "schema": "healthmd.cli_cache_reuse",
                "schema_version": 1,
                "status": "success",
                "message": "Fresh acquisition was skipped because every requested metric/day was already complete in the encrypted cache.",
                "coverage_pages": coverageTraversal.pages
            ]
        }
    } else if options.reuseCovered {
        emitCLIProgress(
            enabled: options.progressJSON,
            phase: "coverage_reuse_check_skipped",
            details: [
                "reason": options.detail == .lossless
                    ? "lossless_detail_requires_fresh_acquisition"
                    : "operation_requires_fresh_context"
            ]
        )
    }

    if shouldRefresh {
        emitCLIProgress(
            enabled: options.progressJSON,
            phase: "acquisition_started",
            details: ["mode": options.reuseCovered ? "fresh_after_incomplete_cache" : "fresh"]
        )
        let refreshBody = makeMetricRefreshRequestBody(
            dates: dates,
            metricIDs: requestedMetricIDs,
            detail: options.detail,
            timeout: options.timeout
        )
        let refreshResult = await requestAgentJSON(
            method: "POST",
            path: "/v1/agent/refresh",
            body: try JSONSerialization.data(withJSONObject: refreshBody),
            baseURL: parsed.baseURL,
            timeout: corpusExportHTTPTimeout
        )
        acquisition = refreshResult.payload
        let completion = metricAcquisitionCompletion(refreshResult.payload)
        acquisitionCorpusStatus = completion.corpusStatus
        acquisitionRequestedScopeStatus = completion.requestedScopeStatus
        unrelatedSkips = completion.unrelatedSkips
        acquisitionWasPartial = completion.requestedScopeStatus == "partial_success"
        emitCLIProgress(
            enabled: options.progressJSON,
            phase: "acquisition_completed",
            details: [
                "corpus_status": completion.corpusStatus ?? "unknown",
                "requested_scope_status": completion.requestedScopeStatus ?? "unknown",
                "unrelated_skip_count": completion.unrelatedSkips.count
            ]
        )
        guard (200...299).contains(refreshResult.statusCode),
              completion.corpusIsTerminalSuccess,
              completion.scopeIsUsable else {
            return try emitMetricQueryEnvelope(
                makeMetricQueryEnvelope(
                    status: "failure",
                    requestedMetricIDs: requestedMetricIDs,
                    acquisition: refreshResult.payload,
                    query: nil,
                    error: "fresh_acquisition_incomplete",
                    operation: options.operation.name
                ),
                outputPath: options.outputPath,
                allowPartial: options.allowPartial
            )
        }
    }

    let queryBody = makeMetricQueryRequestBody(
        dates: dates,
        metricIDs: requestedMetricIDs,
        detail: options.detail,
        operation: options.operation
    )
    emitCLIProgress(
        enabled: options.progressJSON,
        phase: "query_started",
        details: ["all_pages": options.allPages]
    )
    let traversal = try await requestMetricQueryPages(
        path: options.operation.usesEvidenceEndpoint
            ? "/v1/agent/evidence" : "/v1/agent/query",
        initialBody: queryBody,
        baseURL: parsed.baseURL,
        timeout: max(10, options.timeout),
        allPages: options.allPages,
        progressJSON: options.progressJSON
    )
    if let failure = traversal.failure {
        return try emitMetricQueryEnvelope(
            makeMetricQueryEnvelope(
                status: "failure",
                requestedMetricIDs: requestedMetricIDs,
                acquisition: acquisition,
                query: failure.payload,
                error: "metric_query_failed",
                operation: options.operation.name,
                requestedScopeStatus: acquisitionRequestedScopeStatus,
                corpusStatus: acquisitionCorpusStatus,
                unrelatedSkips: unrelatedSkips,
                pages: traversal.pages.isEmpty ? nil : traversal.pages
            ),
            outputPath: options.outputPath,
            allowPartial: options.allowPartial
        )
    }
    guard let firstPage = traversal.pages.first else {
        return try emitMetricQueryEnvelope(
            makeMetricQueryEnvelope(
                status: "failure",
                requestedMetricIDs: requestedMetricIDs,
                acquisition: acquisition,
                query: nil,
                error: "metric_query_empty",
                operation: options.operation.name
            ),
            outputPath: options.outputPath,
            allowPartial: options.allowPartial
        )
    }

    let requestedScopeStatus = acquisitionRequestedScopeStatus
        ?? requestedScopeStatus(forQueryPages: traversal.pages)
    let scopeWasPartial = requestedScopeStatus == "partial_success"
    let receipt = makeMetricQueryReceipt(
        operation: options.operation.name,
        requestedMetricIDs: requestedMetricIDs,
        pages: traversal.pages,
        traversalComplete: traversal.traversalComplete,
        acquisitionMode: acquisitionMode,
        outputFormat: options.outputFormat
    )
    let envelope = makeMetricQueryEnvelope(
        status: scopeWasPartial || acquisitionWasPartial || !traversal.traversalComplete
            ? "partial_success" : "success",
        requestedMetricIDs: requestedMetricIDs,
        acquisition: acquisition,
        query: firstPage,
        error: nil,
        operation: options.operation.name,
        requestedScopeStatus: requestedScopeStatus,
        corpusStatus: acquisitionCorpusStatus,
        unrelatedSkips: unrelatedSkips,
        pages: options.allPages ? traversal.pages : nil,
        receipt: receipt
    )
    let exitCode: Int
    if options.outputFormat == .table {
        exitCode = try emitMetricQueryTable(
            pages: traversal.pages,
            receipt: receipt,
            status: envelope["status"] as? String,
            diagnostics: [
                "requested_scope_status": envelope["requested_scope_status"] ?? NSNull(),
                "corpus_status": envelope["corpus_status"] ?? NSNull(),
                "unrelated_skips": envelope["unrelated_skips"] ?? []
            ],
            outputPath: options.outputPath,
            allowPartial: options.allowPartial
        )
    } else {
        exitCode = try emitMetricQueryEnvelope(
            envelope,
            outputPath: options.outputPath,
            allowPartial: options.allowPartial
        )
    }
    emitCLIProgress(
        enabled: options.progressJSON,
        phase: "completed",
        details: ["receipt": receipt, "exit_code": exitCode]
    )
    return exitCode
}

func filteredMetricCatalog(_ payload: Any, category: String?) -> [String: Any]? {
    guard var catalog = payload as? [String: Any],
          catalog["schema"] as? String == "healthmd.metric_catalog",
          catalog["schema_version"] as? Int == 1,
          let metrics = catalog["metrics"] as? [[String: Any]] else { return nil }
    guard let category else { return catalog }
    let requested = category.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !requested.isEmpty else { return nil }
    let filtered = metrics.filter {
        ($0["category"] as? String)?.caseInsensitiveCompare(requested) == .orderedSame
    }
    guard !filtered.isEmpty else { return nil }
    catalog["metrics"] = filtered
    return catalog
}

func resolveRequestedMetricIDs(
    _ catalogPayload: Any,
    directMetricIDs: [String],
    categories: [String]
) -> (metricIDs: [String]?, failure: [String: Any]?) {
    guard let catalog = catalogPayload as? [String: Any],
          catalog["schema"] as? String == "healthmd.metric_catalog",
          catalog["schema_version"] as? Int == 1,
          let metrics = catalog["metrics"] as? [[String: Any]] else {
        return (nil, metricQueryFailure(
            code: "invalid_metric_catalog",
            message: "The Mac app returned an invalid metric catalog."
        ))
    }
    let knownIDs = Set(metrics.compactMap { $0["id"] as? String })
    let normalizedDirect = directMetricIDs.map {
        $0.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    let unknownIDs = Array(Set(normalizedDirect.filter { !knownIDs.contains($0) })).sorted()

    var resolved = Set(normalizedDirect.filter(knownIDs.contains))
    var unknownCategories: [String] = []
    for category in categories {
        let requested = category.trimmingCharacters(in: .whitespacesAndNewlines)
        let matches = metrics.compactMap { metric -> String? in
            guard let actual = metric["category"] as? String,
                  actual.caseInsensitiveCompare(requested) == .orderedSame else { return nil }
            return metric["id"] as? String
        }
        if matches.isEmpty {
            unknownCategories.append(requested)
        } else {
            resolved.formUnion(matches)
        }
    }
    if !unknownIDs.isEmpty || !unknownCategories.isEmpty {
        return (nil, metricQueryFailure(
            code: "unknown_metric_selection",
            message: "One or more requested metrics or categories are unknown.",
            details: [
                "unknown_metric_ids": unknownIDs,
                "unknown_categories": Array(Set(unknownCategories)).sorted()
            ]
        ))
    }
    guard !resolved.isEmpty else {
        return (nil, metricQueryFailure(
            code: "empty_metric_selection",
            message: "Select at least one metric or category."
        ))
    }
    return (resolved.sorted(), nil)
}

func makeMetricRefreshRequestBody(
    dates: [String: Any],
    metricIDs: [String],
    detail: MetricQueryDetail,
    timeout: Double
) -> [String: Any] {
    [
        "dates": dates,
        "metrics": ["type": "explicit", "metric_ids": metricIDs],
        "sources": [
            "type": "explicit",
            "source_ids": ["apple_health"],
            "provider_ids": []
        ],
        "detail_level": detail.rawValue,
        "wait_timeout_seconds": timeout
    ]
}

func makeMetricQueryRequestBody(
    dates: [String: Any],
    metricIDs: [String],
    detail: MetricQueryDetail,
    operation: HighLevelQueryOperation = .metricSeries,
    cursor: String? = nil
) -> [String: Any] {
    [
        "detail_level": detail.rawValue,
        "request": [
            "schema": "healthmd.query_request",
            "schema_version": 1,
            "metrics": ["type": "explicit", "metric_ids": metricIDs],
            "sources": [
                "type": "explicit",
                "source_ids": ["apple_health"],
                "provider_ids": []
            ],
            "dates": dates,
            "operation": operation.requestObject(detail: detail),
            "page": [
                "max_items": 1_000,
                "max_bytes": 1_048_576,
                "cursor": cursor.map { $0 as Any } ?? NSNull()
            ]
        ]
    ]
}

func isValidMetricQueryResponse(_ payload: Any) -> Bool {
    guard let response = payload as? [String: Any],
          response["schema"] as? String == "healthmd.query_response",
          response["schema_version"] as? Int == 1,
          response["items"] is [Any],
          response["coverage"] is [String: Any],
          response["sources"] is [Any],
          response["evidence"] is [Any],
          response["limitations"] is [Any],
          let nextCursor = response["next_cursor"],
          nextCursor is NSNull || nextCursor is String else { return false }
    return true
}

func metricQueryNextCursor(_ payload: Any) -> String? {
    guard let cursor = (payload as? [String: Any])?["next_cursor"] as? String,
          !cursor.isEmpty else { return nil }
    return cursor
}

struct MetricQueryTraversal {
    let pages: [Any]
    let failure: HTTPResult?
    let traversalComplete: Bool
}

func requestMetricQueryPages(
    path: String,
    initialBody: [String: Any],
    baseURL: String,
    timeout: TimeInterval,
    allPages: Bool,
    progressJSON: Bool,
    maximumAggregateBytes: Int = 64 * 1_024 * 1_024,
    maximumPages: Int = 4_096,
    requestPage: (([String: Any]) async throws -> HTTPResult)? = nil
) async throws -> MetricQueryTraversal {
    var pages: [Any] = []
    var aggregateBytes = 0
    var cursor: String?
    var seenCursors = Set<String>()
    var pageNumber = 0

    repeat {
        var body = initialBody
        guard var request = body["request"] as? [String: Any],
              var page = request["page"] as? [String: Any] else {
            return MetricQueryTraversal(
                pages: pages,
                failure: HTTPResult(
                    statusCode: 0,
                    payload: metricQueryFailure(
                        code: "invalid_query_request",
                        message: "The generated query request is invalid."
                    )
                ),
                traversalComplete: false
            )
        }
        page["cursor"] = cursor.map { $0 as Any } ?? NSNull()
        request["page"] = page
        body["request"] = request
        let result: HTTPResult
        if let requestPage {
            result = try await requestPage(body)
        } else {
            result = await requestAgentJSON(
                method: "POST",
                path: path,
                body: try JSONSerialization.data(withJSONObject: body),
                baseURL: baseURL,
                timeout: timeout
            )
        }
        guard (200...299).contains(result.statusCode),
              isValidMetricQueryResponse(result.payload) else {
            return MetricQueryTraversal(
                pages: pages,
                failure: result,
                traversalComplete: false
            )
        }
        let encodedPageBytes = (try? JSONSerialization.data(
            withJSONObject: result.payload,
            options: []
        ).count) ?? maximumAggregateBytes + 1
        guard encodedPageBytes <= maximumAggregateBytes - aggregateBytes,
              pageNumber < maximumPages else {
            return MetricQueryTraversal(
                pages: pages,
                failure: HTTPResult(
                    statusCode: 413,
                    payload: metricQueryFailure(
                        code: "query_traversal_aggregate_limit",
                        message: "Automatic traversal exceeded its bounded aggregate byte or page limit; narrow the date/metric scope or page manually.",
                        details: [
                            "maximum_aggregate_bytes": maximumAggregateBytes,
                            "maximum_pages": maximumPages,
                            "completed_pages": pageNumber
                        ]
                    )
                ),
                traversalComplete: false
            )
        }
        aggregateBytes += encodedPageBytes
        pages.append(result.payload)
        pageNumber += 1
        let object = result.payload as? [String: Any]
        let itemCount = (object?["items"] as? [Any])?.count ?? 0
        let factCount = ((object?["packet"] as? [String: Any])?["facts"] as? [Any])?.count ?? 0
        emitCLIProgress(
            enabled: progressJSON,
            phase: "query_page_completed",
            details: [
                "page": pageNumber,
                "item_count": itemCount,
                "packet_fact_count": factCount,
                "has_next_page": metricQueryNextCursor(result.payload) != nil
            ]
        )
        guard allPages else {
            return MetricQueryTraversal(
                pages: pages,
                failure: nil,
                traversalComplete: metricQueryNextCursor(result.payload) == nil
            )
        }
        cursor = metricQueryNextCursor(result.payload)
        if let cursor {
            guard seenCursors.insert(cursor).inserted else {
                return MetricQueryTraversal(
                    pages: pages,
                    failure: HTTPResult(
                        statusCode: 0,
                        payload: metricQueryFailure(
                            code: "cursor_cycle_detected",
                            message: "Query traversal returned a repeated cursor or exceeded the page safety bound."
                        )
                    ),
                    traversalComplete: false
                )
            }
        }
    } while cursor != nil

    return MetricQueryTraversal(pages: pages, failure: nil, traversalComplete: true)
}

func emitCLIProgress(
    enabled: Bool,
    phase: String,
    details: [String: Any] = [:]
) {
    guard enabled else { return }
    var event: [String: Any] = [
        "schema": "healthmd.cli_progress",
        "schema_version": 1,
        "phase": phase,
        "timestamp": ISO8601DateFormatter().string(from: Date())
    ]
    event.merge(details) { _, replacement in replacement }
    guard let data = try? JSONSerialization.data(
        withJSONObject: event,
        options: [.sortedKeys, .withoutEscapingSlashes]
    ) else { return }
    FileHandle.standardError.write(data)
    FileHandle.standardError.write(Data("\n".utf8))
}

func makeMetricQueryReceipt(
    operation: String,
    requestedMetricIDs: [String],
    pages: [Any],
    traversalComplete: Bool,
    acquisitionMode: String,
    outputFormat: MetricQueryOutputFormat
) -> [String: Any] {
    let objects = pages.compactMap { $0 as? [String: Any] }
    let itemCount = objects.reduce(0) { $0 + (($1["items"] as? [Any])?.count ?? 0) }
    let factCount = objects.reduce(0) {
        $0 + (((($1["packet"] as? [String: Any])?["facts"] as? [Any])?.count) ?? 0)
    }
    let evidenceCount = objects.reduce(0) {
        $0 + (($1["evidence"] as? [Any])?.count ?? 0)
    }
    return [
        "schema": "healthmd.cli_query_receipt",
        "schema_version": 1,
        "operation": operation,
        "requested_metric_ids": requestedMetricIDs.sorted(),
        "acquisition_mode": acquisitionMode,
        "output_format": outputFormat.rawValue,
        "page_count": pages.count,
        "item_count": itemCount,
        "packet_fact_count": factCount,
        "evidence_reference_count": evidenceCount,
        "traversal_complete": traversalComplete,
        "generated_at": ISO8601DateFormatter().string(from: Date())
    ]
}

func makeMetricQueryEnvelope(
    status: String,
    requestedMetricIDs: [String],
    acquisition: Any?,
    query: Any?,
    error: String?,
    operation: String,
    requestedScopeStatus: String? = nil,
    corpusStatus: String? = nil,
    unrelatedSkips: [Any] = [],
    pages: [Any]? = nil,
    receipt: [String: Any]? = nil
) -> [String: Any] {
    var envelope: [String: Any] = [
        "schema": "healthmd.cli_metric_query",
        "schema_version": 1,
        "status": status,
        "operation": operation,
        "requested_metric_ids": requestedMetricIDs.sorted(),
        "requested_scope_status": requestedScopeStatus
            ?? (status == "failure" ? "unavailable" : "unknown"),
        "corpus_status": corpusStatus ?? (acquisition.map { _ in "unknown" } ?? "not_requested"),
        "unrelated_skips": unrelatedSkips,
        "acquisition": acquisition ?? NSNull(),
        "query": query ?? NSNull()
    ]
    if let error { envelope["error"] = error }
    if let pages { envelope["pages"] = pages }
    if let receipt { envelope["receipt"] = receipt }
    return envelope
}

struct MetricAcquisitionCompletion {
    let corpusStatus: String?
    let requestedScopeStatus: String?
    let unrelatedSkips: [Any]

    var corpusIsTerminalSuccess: Bool {
        corpusStatus == "success" || corpusStatus == "partial_success"
    }

    var scopeIsUsable: Bool {
        requestedScopeStatus == "success" || requestedScopeStatus == "partial_success"
    }
}

func metricAcquisitionCompletion(_ payload: Any) -> MetricAcquisitionCompletion {
    let object = payload as? [String: Any]
    let wireStatus = object?["status"] as? String
    let corpusStatus = object?["corpus_status"] as? String ?? wireStatus
    return MetricAcquisitionCompletion(
        corpusStatus: corpusStatus,
        requestedScopeStatus: object?["requested_scope_status"] as? String ?? wireStatus,
        unrelatedSkips: object?["unrelated_skips"] as? [Any] ?? []
    )
}

func metricCoveragePagesAreComplete(_ pages: [Any]) -> Bool {
    guard !pages.isEmpty else { return false }
    return pages.allSatisfy { page in
        guard let object = page as? [String: Any],
              let coverage = object["coverage"] as? [String: Any],
              let status = coverage["status"] as? String else { return false }
        if let metadata = object["metadata"] as? [String: Any],
           let requestedStatus = metadata["requested_scope_status"] as? String {
            return requestedStatus == "success"
        }
        if status == "available" || status == "complete_empty" { return true }
        if status == "partial", let missing = coverage["missing"] as? [[String: Any]],
           !missing.isEmpty {
            return missing.allSatisfy { $0["status"] as? String == "complete_empty" }
        }
        return false
    }
}

func requestedScopeStatus(forQueryPages pages: [Any]) -> String {
    guard !pages.isEmpty else { return "unavailable" }
    if metricCoveragePagesAreComplete(pages) { return "success" }
    let statuses = pages.compactMap { page -> String? in
        guard let object = page as? [String: Any] else { return nil }
        if let metadata = object["metadata"] as? [String: Any],
           let scope = metadata["requested_scope_status"] as? String {
            return scope
        }
        return (object["coverage"] as? [String: Any])?["status"] as? String
    }
    if statuses.contains("partial") || statuses.contains("partial_success") {
        return "partial_success"
    }
    let hasComplete = statuses.contains("available")
        || statuses.contains("complete_empty")
        || statuses.contains("success")
    return hasComplete ? "partial_success" : "failure"
}

func requestedScopeStatus(forCoverageStatus status: String?) -> String {
    switch status {
    case "available", "complete_empty": return "success"
    case "partial": return "partial_success"
    case "failed", "unsupported", "skipped", "cancelled", "not_synchronized": return "failure"
    default: return "unavailable"
    }
}

func metricQueryExitCode(status: String?, allowPartial: Bool) -> Int {
    switch status {
    case "success": return 0
    case "partial_success": return allowPartial ? 0 : 1
    default: return 1
    }
}

func renderMetricQueryTable(
    pages: [Any],
    receipt: [String: Any],
    status: String?,
    diagnostics: [String: Any] = [:]
) -> String {
    var lines = ["type\tidentity\tstart_or_date\tend\tvalue\tstatus"]
    for page in pages.compactMap({ $0 as? [String: Any] }) {
        for item in page["items"] as? [[String: Any]] ?? [] {
            let type = item["type"] as? String ?? "unknown"
            switch type {
            case "metric":
                let value = item["metric"] as? [String: Any] ?? [:]
                lines.append(tableLine([
                    type,
                    value["metric_id"] as? String,
                    value["owner_date"] as? String,
                    nil,
                    compactQueryValue(value["value"]),
                    value["status"] as? String
                ]))
            case "workout":
                let value = item["workout"] as? [String: Any] ?? [:]
                lines.append(tableLine([
                    type,
                    value["activity"] as? String ?? value["workout_id"] as? String,
                    value["start"] as? String,
                    value["end"] as? String,
                    value["workout_id"] as? String,
                    nil
                ]))
            case "sleep_session":
                let value = item["sleep_session"] as? [String: Any] ?? [:]
                lines.append(tableLine([
                    type,
                    value["session_id"] as? String,
                    value["local_start"] as? String ?? value["start"] as? String,
                    value["local_end"] as? String ?? value["end"] as? String,
                    (value["asleep_duration_seconds"] as? NSNumber)?.stringValue,
                    value["completeness"] as? String
                ]))
            case "workout_sleep_alignment":
                let value = item["workout_sleep_alignment"] as? [String: Any] ?? [:]
                let workout = value["workout"] as? [String: Any] ?? [:]
                lines.append(tableLine([
                    type,
                    workout["activity"] as? String ?? value["alignment_id"] as? String,
                    workout["start"] as? String,
                    workout["end"] as? String,
                    value["alignment_id"] as? String,
                    value["status"] as? String
                ]))
            case "comparison":
                let value = item["comparison"] as? [String: Any] ?? [:]
                lines.append(tableLine([
                    type,
                    value["metric_id"] as? String,
                    nil,
                    nil,
                    "\(compactQueryValue(value["first_value"])) → \(compactQueryValue(value["second_value"]))",
                    value["direction"] as? String
                ]))
            case "evidence":
                let value = item["evidence"] as? [String: Any] ?? [:]
                let reference = value["reference"] as? [String: Any] ?? [:]
                lines.append(tableLine([
                    type,
                    reference["evidence_id"] as? String,
                    nil,
                    nil,
                    compactQueryValue(value["value"]),
                    nil
                ]))
            default:
                lines.append(tableLine([type, nil, nil, nil, compactQueryValue(item), nil]))
            }
        }
        if let packet = page["packet"] as? [String: Any] {
            for fact in packet["facts"] as? [[String: Any]] ?? [] {
                lines.append(tableLine([
                    "packet_fact",
                    fact["label"] as? String ?? fact["fact_id"] as? String,
                    fact["owner_date"] as? String,
                    nil,
                    compactQueryValue(fact["value"]),
                    nil
                ]))
            }
        }
    }
    lines.append("# status=\(status ?? "unknown") pages=\(receipt["page_count"] ?? 0) items=\(receipt["item_count"] ?? 0) facts=\(receipt["packet_fact_count"] ?? 0) complete=\(receipt["traversal_complete"] ?? false)")
    let pageDiagnostics: [[String: Any]] = pages.compactMap { page in
        guard let object = page as? [String: Any] else { return nil }
        return [
            "coverage": object["coverage"] ?? NSNull(),
            "sources": object["sources"] ?? [],
            "limitations": object["limitations"] ?? [],
            "metadata": object["metadata"] ?? NSNull(),
            "evidence_reference_count": (object["evidence"] as? [Any])?.count ?? 0
        ]
    }
    var diagnosticObject = diagnostics
    diagnosticObject["pages"] = pageDiagnostics
    if let data = try? JSONSerialization.data(
        withJSONObject: diagnosticObject,
        options: [.sortedKeys, .withoutEscapingSlashes]
    ) {
        lines.append("# table_projection=lossy; diagnostics_json=\(String(decoding: data, as: UTF8.self))")
    }
    return lines.joined(separator: "\n") + "\n"
}

private func tableLine(_ values: [String?]) -> String {
    values.map { value in
        (value ?? "").replacingOccurrences(of: "\t", with: " ")
            .replacingOccurrences(of: "\n", with: " ")
    }.joined(separator: "\t")
}

private func compactQueryValue(_ value: Any?) -> String {
    guard let value, !(value is NSNull) else { return "" }
    if let object = value as? [String: Any] {
        switch object["type"] as? String {
        case "quantity":
            return "\(object["value"] ?? "") \(object["unit"] ?? "")"
                .trimmingCharacters(in: .whitespaces)
        case "duration": return "\(object["seconds"] ?? "") s"
        case "count", "string", "boolean", "timestamp", "date":
            return String(describing: object["value"] ?? "")
        default: break
        }
    }
    guard JSONSerialization.isValidJSONObject(value),
          let data = try? JSONSerialization.data(
            withJSONObject: value,
            options: [.sortedKeys, .withoutEscapingSlashes]
          ) else { return String(describing: value) }
    return String(decoding: data, as: UTF8.self)
}

private func emitMetricQueryTable(
    pages: [Any],
    receipt: [String: Any],
    status: String?,
    diagnostics: [String: Any],
    outputPath: String?,
    allowPartial: Bool
) throws -> Int {
    let table = renderMetricQueryTable(
        pages: pages,
        receipt: receipt,
        status: status,
        diagnostics: diagnostics
    )
    if let outputPath {
        try emitDataResponse(Data(table.utf8), outputPath: outputPath)
    } else {
        print(table, terminator: "")
    }
    return metricQueryExitCode(status: status, allowPartial: allowPartial)
}

private func emitMetricQueryEnvelope(
    _ envelope: [String: Any],
    outputPath: String?,
    allowPartial: Bool
) throws -> Int {
    guard JSONSerialization.isValidJSONObject(envelope) else {
        printJSON(["status": "failure", "error": "encode_failed"])
        return 1
    }
    if let outputPath {
        do {
            let data = try JSONSerialization.data(
                withJSONObject: envelope,
                options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
            )
            try emitDataResponse(data, outputPath: outputPath)
        } catch {
            printJSON(makeMetricQueryEnvelope(
                status: "failure",
                requestedMetricIDs: envelope["requested_metric_ids"] as? [String] ?? [],
                acquisition: envelope["acquisition"],
                query: metricQueryFailure(
                    code: "output_write_failed",
                    message: error.localizedDescription,
                    details: ["output_path": outputPath]
                ),
                error: "output_write_failed",
                operation: envelope["operation"] as? String ?? "unknown"
            ))
            return 1
        }
    } else {
        printJSON(envelope)
    }
    return metricQueryExitCode(
        status: envelope["status"] as? String,
        allowPartial: allowPartial
    )
}

func metricQueryFailure(
    code: String,
    message: String,
    details: [String: Any] = [:]
) -> [String: Any] {
    [
        "schema": "healthmd.query_error",
        "schema_version": 1,
        "code": code,
        "message": message,
        "retryable": false,
        "details": details
    ]
}

private func requestJSON(
    method: String,
    path: String,
    body: [String: Any]? = nil,
    baseURL: String,
    timeout: Double = 10
) async -> HTTPResult {
    guard let url = URL(string: baseURL + path) else {
        return HTTPResult(statusCode: 503, payload: ["error": "invalid_base_url", "message": baseURL])
    }

    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
    }

    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
        let payload = parsePayload(data) ?? [:]
        return HTTPResult(statusCode: statusCode, payload: payload)
    } catch {
        return HTTPResult(
            statusCode: 503,
            payload: [
                "error": "mac_app_unreachable",
                "message": readableNetworkError(error)
            ]
        )
    }
}

private func requestAgentJSON(
    method: String,
    path: String,
    body: Data? = nil,
    baseURL: String,
    timeout: Double = 10
) async -> HTTPResult {
    guard let url = URL(string: baseURL + path) else {
        return HTTPResult(statusCode: 503, payload: ["error": "invalid_base_url", "message": baseURL])
    }
    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = body
    }
    do {
        let (data, response) = try await URLSession.shared.data(for: request)
        return HTTPResult(
            statusCode: (response as? HTTPURLResponse)?.statusCode ?? 0,
            payload: parsePayload(data) ?? [:]
        )
    } catch {
        return HTTPResult(
            statusCode: 503,
            payload: [
                "error": "mac_app_unreachable",
                "message": readableNetworkError(error)
            ]
        )
    }
}

private func requestDownloadedJSON(
    method: String,
    path: String,
    body: [String: Any]? = nil,
    baseURL: String,
    timeout: Double
) async -> DownloadedHTTPResult {
    guard let url = URL(string: baseURL + path) else {
        let fallback = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try? Data("{\"error\":\"invalid_base_url\"}".utf8).write(to: fallback)
        return DownloadedHTTPResult(statusCode: 503, fileURL: fallback, headers: [:])
    }

    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.httpMethod = method
    request.setValue("application/json", forHTTPHeaderField: "Accept")
    if let body {
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try? JSONSerialization.data(withJSONObject: body, options: [])
    }

    do {
        let (temporaryURL, response) = try await URLSession.shared.download(for: request)
        let retainedURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("healthmd-download-\(UUID().uuidString).json")
        try FileManager.default.moveItem(at: temporaryURL, to: retainedURL)
        let httpResponse = response as? HTTPURLResponse
        let headers = (httpResponse?.allHeaderFields ?? [:]).reduce(into: [String: String]()) { result, pair in
            result[String(describing: pair.key).lowercased()] = String(describing: pair.value)
        }
        return DownloadedHTTPResult(
            statusCode: httpResponse?.statusCode ?? 0,
            fileURL: retainedURL,
            headers: headers
        )
    } catch {
        let fallback = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        let payload: [String: Any] = [
            "error": "mac_app_unreachable",
            "message": readableNetworkError(error)
        ]
        let data = (try? JSONSerialization.data(withJSONObject: payload, options: [])) ?? Data("{}".utf8)
        try? data.write(to: fallback)
        return DownloadedHTTPResult(statusCode: 503, fileURL: fallback, headers: [:])
    }
}

func sha256OfFile(_ url: URL) throws -> String {
    let handle = try FileHandle(forReadingFrom: url)
    defer { try? handle.close() }
    var hasher = SHA256()
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
        hasher.update(data: data)
    }
    return hasher.finalize().map { String(format: "%02x", $0) }.joined()
}

private func emitDownloadedResponse(_ sourceURL: URL, outputPath: String?) throws {
    if let outputPath {
        let destination = URL(fileURLWithPath: outputPath).standardizedFileURL
        let parent = destination.deletingLastPathComponent()
        let temporary = parent.appendingPathComponent(".\(destination.lastPathComponent).tmp-\(UUID().uuidString)")
        do {
            try FileManager.default.copyItem(at: sourceURL, to: temporary)
            if FileManager.default.fileExists(atPath: destination.path) {
                _ = try FileManager.default.replaceItemAt(destination, withItemAt: temporary)
            } else {
                try FileManager.default.moveItem(at: temporary, to: destination)
            }
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o600],
                ofItemAtPath: destination.path
            )
        } catch {
            try? FileManager.default.removeItem(at: temporary)
            throw error
        }
        return
    }

    let handle = try FileHandle(forReadingFrom: sourceURL)
    defer { try? handle.close() }
    while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
        try FileHandle.standardOutput.write(contentsOf: data)
    }
    try FileHandle.standardOutput.write(contentsOf: Data("\n".utf8))
}

private let maximumCanonicalFieldProjectionBytes = 64 * 1_024 * 1_024

func emitCanonicalHealthData(
    sourceURL: URL,
    options: ExportOptions
) throws {
    let metadata = try canonicalTransportMetadata(fileURL: sourceURL)
    let receipt = canonicalExtractionReceipt(metadata)
    let receiptData = try JSONSerialization.data(
        withJSONObject: receipt,
        options: [.sortedKeys, .withoutEscapingSlashes]
    )
    let ranges = try canonicalHealthDataRanges(fileURL: sourceURL)
    let temporaryURL = FileManager.default.temporaryDirectory
        .appendingPathComponent("healthmd-canonical-projection-\(UUID().uuidString).json")
    FileManager.default.createFile(atPath: temporaryURL.path, contents: nil)
    let output = try FileHandle(forWritingTo: temporaryURL)
    let input = try FileHandle(forReadingFrom: sourceURL)
    defer {
        try? output.close()
        try? input.close()
        try? FileManager.default.removeItem(at: temporaryURL)
    }

    let selectedPointers = Array(Set(options.objectPaths + options.fieldPointers)).sorted()
    if options.extractionFormat == .json {
        let dataKey = selectedPointers.isEmpty ? "health_data" : "projections"
        try output.write(contentsOf: Data(
            "{\"protocol\":\"healthmd.extract_result\",\"protocol_version\":1,\"\(dataKey)\":[".utf8
        ))
    }
    let statusPairs: [(String, String)] = metadata.days.compactMap { day in
        guard let date = day.date, let status = day.status else { return nil }
        return (date, status)
    }
    let statusesByDate = Dictionary(uniqueKeysWithValues: statusPairs)
    for (index, range) in ranges.enumerated() {
        if index > 0 {
            try output.write(contentsOf: Data(options.extractionFormat == .json ? ",".utf8 : "\n".utf8))
        }
        if selectedPointers.isEmpty {
            try copyFileRange(range, from: input, to: output)
        } else {
            guard range.count <= maximumCanonicalFieldProjectionBytes else {
                throw CLIError.fileOutput(
                    "one canonical day exceeds the 64 MiB field-projection bound; narrow metrics or omit --field/--object"
                )
            }
            try input.seek(toOffset: UInt64(range.lowerBound))
            let data = try input.read(upToCount: range.count) ?? Data()
            guard data.count == range.count,
                  let source = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
                throw CLIError.fileOutput("canonical health_data could not be decoded for field projection")
            }
            let date = source["date"] as? String
            let projected = try projectCanonicalHealthData(
                source,
                pointers: selectedPointers,
                dayStatus: date.flatMap { statusesByDate[$0] }
            )
            let encoded = try JSONSerialization.data(
                withJSONObject: projected,
                options: [.sortedKeys, .withoutEscapingSlashes]
            )
            try output.write(contentsOf: encoded)
        }
    }
    if options.extractionFormat == .json {
        try output.write(contentsOf: Data("],\"receipt\":".utf8))
        try output.write(contentsOf: receiptData)
        try output.write(contentsOf: Data("}\n".utf8))
    } else {
        if !ranges.isEmpty { try output.write(contentsOf: Data("\n".utf8)) }
    }
    try output.synchronize()
    try output.close()
    try input.close()
    try emitDownloadedResponse(temporaryURL, outputPath: options.outputPath)

    if options.extractionFormat == .jsonl {
        if let outputPath = options.outputPath {
            try emitDataResponse(
                receiptData + Data("\n".utf8),
                outputPath: outputPath + ".receipt.json"
            )
        } else {
            try FileHandle.standardError.write(contentsOf: receiptData + Data("\n".utf8))
        }
    }
}

func canonicalExtractionReceipt(_ metadata: CanonicalTransportMetadata) -> [String: Any] {
    var selection: [String: Any] = [
        "metric_ids": metadata.metricIDs,
        "source_ids": metadata.sourceIDs,
        "object_paths": metadata.objectPaths,
        "field_pointers": metadata.fieldPointers
    ]
    if let detailLevel = metadata.detailLevel { selection["detail_level"] = detailLevel }
    var captureSummary: [String: Any] = metadata.captureSummary
    captureSummary["query_status_counts"] = metadata.queryStatusCounts
    captureSummary["day_status_counts"] = metadata.dayStatusCounts
    var receipt: [String: Any] = [
        "protocol": "healthmd.extract_receipt",
        "protocol_version": 1,
        "status": metadata.responseStatus ?? "unknown",
        "source_schema": "healthmd.health_data",
        "source_schema_version": currentDailySchemaVersion,
        "selection": selection,
        "days": metadata.days.map { day in
            var value: [String: Any] = ["health_data_retained": day.hasHealthData]
            if let date = day.date { value["date"] = date }
            if let status = day.status { value["status"] = status }
            if let failureCode = day.failureCode { value["failure_code"] = failureCode }
            if let sampleCount = day.sampleCount { value["sample_count"] = sampleCount }
            if let recordCount = day.recordCount { value["record_count"] = recordCount }
            if !day.queryStatusCounts.isEmpty { value["query_status_counts"] = day.queryStatusCounts }
            if let count = day.integrityWarningCount { value["integrity_warning_count"] = count }
            if !day.integrityWarningCodes.isEmpty {
                value["integrity_warning_codes"] = day.integrityWarningCodes
            }
            if let count = day.partialFailureCount { value["partial_failure_count"] = count }
            if !day.partialFailureTypes.isEmpty { value["partial_failure_types"] = day.partialFailureTypes }
            return value
        },
        "missing_dates": metadata.missingDates,
        "capture_summary": captureSummary
    ]
    if let start = metadata.dateStart, let end = metadata.dateEnd {
        receipt["date_range"] = ["start": start, "end": end]
    }
    if let count = metadata.totalRequestedDays { receipt["total_requested_days"] = count }
    return receipt
}

private func copyFileRange(
    _ range: Range<Int64>,
    from input: FileHandle,
    to output: FileHandle
) throws {
    try input.seek(toOffset: UInt64(range.lowerBound))
    var remaining = range.count
    while remaining > 0 {
        let count = min(remaining, 1_048_576)
        guard let data = try input.read(upToCount: count), !data.isEmpty else {
            throw CLIError.fileOutput("canonical response ended before the selected document")
        }
        try output.write(contentsOf: data)
        remaining -= data.count
    }
}

private func projectCanonicalHealthData(
    _ source: [String: Any],
    pointers: [String],
    dayStatus: String?
) throws -> [String: Any] {
    var sourceReference: [String: Any] = [
        "schema": source["schema"] ?? currentDailySchema,
        "schema_version": source["schema_version"] ?? currentDailySchemaVersion
    ]
    if let date = source["date"] { sourceReference["date"] = date }
    if let capture = source["raw_capture_status"] { sourceReference["raw_capture_status"] = capture }
    let completeStatuses = Set(["complete", "complete_empty", "complete_with_warnings"])
    let selections: [[String: Any]] = try pointers.map { pointer in
        let components = try canonicalPointerComponents(pointer)
        if let value = canonicalValue(at: components, in: source) {
            return ["pointer": pointer, "status": "available", "value": value]
        }
        return [
            "pointer": pointer,
            "status": completeStatuses.contains(dayStatus ?? "") ? "complete_empty" : (dayStatus ?? "unavailable")
        ]
    }
    return [
        "source": sourceReference,
        "selections": selections
    ]
}

private func canonicalPointerComponents(_ pointer: String) throws -> [String] {
    guard isValidCanonicalPointer(pointer) else {
        throw CLIError.usage("invalid canonical JSON Pointer: \(pointer)")
    }
    return pointer.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map {
        String($0).replacingOccurrences(of: "~1", with: "/")
            .replacingOccurrences(of: "~0", with: "~")
    }
}

private func canonicalValue(at components: [String], in source: Any) -> Any? {
    guard let first = components.first else { return source }
    if let object = source as? [String: Any], let value = object[first] {
        return canonicalValue(at: Array(components.dropFirst()), in: value)
    }
    if let array = source as? [Any], let index = Int(first), array.indices.contains(index) {
        return canonicalValue(at: Array(components.dropFirst()), in: array[index])
    }
    return nil
}

private func emitDataResponse(_ data: Data, outputPath: String) throws {
    let destination = URL(fileURLWithPath: outputPath).standardizedFileURL
    let parent = destination.deletingLastPathComponent()
    let temporary = parent.appendingPathComponent(
        ".\(destination.lastPathComponent).tmp-\(UUID().uuidString)"
    )
    let fileManager = FileManager.default
    guard fileManager.createFile(
        atPath: temporary.path,
        contents: nil,
        attributes: [.posixPermissions: 0o600]
    ) else {
        throw CLIError.fileOutput("could not create protected output file")
    }
    do {
        let handle = try FileHandle(forWritingTo: temporary)
        try handle.write(contentsOf: data)
        try handle.synchronize()
        try handle.close()
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
        try? fileManager.setAttributes(
            [.posixPermissions: 0o600],
            ofItemAtPath: destination.path
        )
    } catch {
        try? fileManager.removeItem(at: temporary)
        throw error
    }
}

private func parsePayload(_ data: Data) -> Any? {
    guard !data.isEmpty else { return [:] }
    if let object = try? JSONSerialization.jsonObject(with: data, options: []) {
        return object
    }
    return String(data: data, encoding: .utf8).map { ["error": $0] }
}

private func readableNetworkError(_ error: Error) -> String {
    let nsError = error as NSError
    if nsError.domain == NSURLErrorDomain {
        switch nsError.code {
        case NSURLErrorCannotConnectToHost:
            return "Connection refused"
        case NSURLErrorTimedOut:
            return "The request timed out"
        default:
            break
        }
    }
    return error.localizedDescription
}

private func printJSON(_ object: Any) {
    let jsonObject: Any
    if JSONSerialization.isValidJSONObject(object) {
        jsonObject = object
    } else {
        jsonObject = ["error": String(describing: object)]
    }

    do {
        let data = try JSONSerialization.data(withJSONObject: jsonObject, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        if let string = String(data: data, encoding: .utf8) {
            print(string)
        }
    } catch {
        print("{\"error\":\"encode_failed\"}")
    }
}

func parse(_ arguments: [String]) throws -> ParsedCommand {
    var args = arguments
    var baseURL = defaultBaseURL

    if args.isEmpty || args.first == "-h" || args.first == "--help" {
        return ParsedCommand(baseURL: baseURL, command: .help)
    }

    while let first = args.first {
        if first == "--base-url" {
            guard args.count >= 2 else { throw CLIError.usage("--base-url requires a value") }
            baseURL = args[1]
            args.removeFirst(2)
        } else if first.hasPrefix("--base-url=") {
            baseURL = String(first.dropFirst("--base-url=".count))
            args.removeFirst()
        } else if first == "--token" || first.hasPrefix("--token=") || first == "--token-file" {
            throw CLIError.usage("credentials were removed; delete --token/--token-file and run the command directly")
        } else {
            break
        }
    }

    baseURL = try canonicalLoopbackBaseURL(baseURL)

    guard let command = args.first else {
        return ParsedCommand(baseURL: baseURL, command: .help)
    }
    args.removeFirst()

    func parsed(_ command: Command) -> ParsedCommand {
        ParsedCommand(baseURL: baseURL, command: command)
    }

    switch command {
    case "status":
        if args.contains("-h") || args.contains("--help") {
            printStatusHelp()
            return parsed(.noOp)
        }
        if args.isEmpty { return parsed(.status(jobID: nil)) }
        guard args.count == 2, args[0] == "--job", let jobID = UUID(uuidString: args[1]) else {
            throw CLIError.usage("status accepts only --job UUID")
        }
        return parsed(.status(jobID: jobID))
    case "doctor":
        if args.contains("-h") || args.contains("--help") {
            printDoctorHelp()
            return parsed(.noOp)
        }
        guard args.isEmpty || args == ["--json"] else {
            throw CLIError.usage("doctor accepts only --json")
        }
        return parsed(.doctor)
    case "metrics":
        if args.contains("-h") || args.contains("--help") {
            printMetricsHelp()
            return parsed(.noOp)
        }
        return parsed(.metrics(try parseMetricsOptions(args)))
    case "query":
        if args.contains("-h") || args.contains("--help") {
            printQueryHelp()
            return parsed(.noOp)
        }
        return parsed(.query(try parseMetricQueryOptions(args)))
    case "sleep":
        if args.contains("-h") || args.contains("--help") {
            printSleepHelp()
            return parsed(.noOp)
        }
        return parsed(.query(try parseSleepSessionQueryOptions(args)))
    case "training":
        if args.contains("-h") || args.contains("--help") {
            printTrainingHelp()
            return parsed(.noOp)
        }
        return parsed(.query(try parseTrainingAlignmentOptions(args)))
    case "workouts":
        if args.contains("-h") || args.contains("--help") {
            printWorkoutsHelp()
            return parsed(.noOp)
        }
        return parsed(.query(try parseWorkoutQueryOptions(args)))
    case "coverage":
        if args.contains("-h") || args.contains("--help") {
            printCoverageHelp()
            return parsed(.noOp)
        }
        return parsed(.query(try parseCoverageQueryOptions(args)))
    case "compare":
        if args.contains("-h") || args.contains("--help") {
            printCompareHelp()
            return parsed(.noOp)
        }
        return parsed(.query(try parseCompareQueryOptions(args)))
    case "evidence":
        if args.contains("-h") || args.contains("--help") {
            printEvidenceHelp()
            return parsed(.noOp)
        }
        return parsed(.query(try parseTrainingEvidenceOptions(args)))
    case "extract":
        if args.contains("-h") || args.contains("--help") {
            printExtractHelp()
            return parsed(.noOp)
        }
        return parsed(.extract(try parseExportOptions(args, canonicalProjection: true)))
    case "export":
        if args.contains("-h") || args.contains("--help") {
            printExportHelp()
            return parsed(.noOp)
        }
        return parsed(.export(try parseExportOptions(args)))
    case "resume":
        if args.contains("-h") || args.contains("--help") {
            printResumeHelp()
            return parsed(.noOp)
        }
        guard let value = args.first, let jobID = UUID(uuidString: value) else {
            throw CLIError.usage("resume requires a job UUID")
        }
        return parsed(.resume(jobID, try parseResumeOptions(Array(args.dropFirst()))))
    case "cancel":
        if args.contains("-h") || args.contains("--help") {
            printCancelHelp()
            return parsed(.noOp)
        }
        guard args.count == 1, let jobID = UUID(uuidString: args[0]) else {
            throw CLIError.usage("cancel requires exactly one job UUID")
        }
        return parsed(.cancel(jobID))
    case "agent":
        if args.contains("-h") || args.contains("--help") {
            printAgentHelp()
            return parsed(.noOp)
        }
        return parsed(.agent(try parseAgentCommand(args)))
    default:
        throw CLIError.usage("unknown command '\(command)'\n\nRun 'healthmd --help' for usage.")
    }
}

func parseAgentCommand(_ args: [String]) throws -> AgentCommand {
    guard let command = args.first else {
        throw CLIError.usage("agent requires a subcommand; run 'healthmd agent --help'")
    }
    let rest = Array(args.dropFirst())
    switch command {
    case "pair", "unpair", "profiles", "activity":
        throw CLIError.usage("agent \(command) was removed; local requests no longer use credentials, grants, profiles, or access activity")
    case "capabilities":
        guard rest.isEmpty else { throw CLIError.usage("agent capabilities accepts no arguments") }
        return .capabilities
    case "query": return .query(try parseAgentJSONBody(rest, required: true))
    case "evidence": return .evidence(try parseAgentJSONBody(rest, required: true))
    case "refresh": return .refresh(try parseAgentJSONBody(rest, required: true))
    case "job":
        guard rest.count >= 2,
              let jobID = UUID(uuidString: rest[1]) else {
            throw CLIError.usage("agent job requires {status,resume,cancel} UUID")
        }
        switch rest[0] {
        case "status":
            guard rest.count == 2 else { throw CLIError.usage("agent job status requires exactly one UUID") }
            return .jobStatus(jobID)
        case "cancel":
            guard rest.count == 2 else { throw CLIError.usage("agent job cancel requires exactly one UUID") }
            return .jobCancel(jobID)
        case "resume":
            let options = try parseResumeOptions(Array(rest.dropFirst(2)))
            guard options.outputPath == nil, !options.allowPartial else {
                throw CLIError.usage("agent job resume accepts only --timeout")
            }
            return .jobResume(jobID, timeout: options.timeout)
        default:
            throw CLIError.usage("unknown agent job action '\(rest[0])'")
        }
    default:
        throw CLIError.usage("unknown agent subcommand '\(command)'")
    }
}

func parseAgentJSONBody(_ args: [String], required: Bool) throws -> Data {
    if args.isEmpty {
        if required { throw CLIError.usage("agent request requires --input PATH|- or --json JSON") }
        return Data("{}".utf8)
    }
    guard args.count == 2 else {
        throw CLIError.usage("use exactly one of --input PATH|- or --json JSON")
    }
    let data: Data
    switch args[0] {
    case "--json":
        data = Data(args[1].utf8)
    case "--input":
        if args[1] == "-" {
            data = FileHandle.standardInput.readDataToEndOfFile()
        } else {
            do {
                data = try Data(contentsOf: URL(fileURLWithPath: args[1]))
            } catch {
                throw CLIError.fileOutput("could not read agent request: \(error.localizedDescription)")
            }
        }
    default:
        throw CLIError.usage("use --input PATH|- or --json JSON")
    }
    guard !data.isEmpty,
          (try? JSONSerialization.jsonObject(with: data)) is [String: Any] else {
        throw CLIError.usage("agent request body must be one JSON object")
    }
    return data
}

func parseMetricsOptions(_ args: [String]) throws -> MetricsOptions {
    var args = args
    if args.first == "list" { args.removeFirst() }
    var options = MetricsOptions()
    var index = 0
    while index < args.count {
        switch args[index] {
        case "--category":
            guard index + 1 < args.count else {
                throw CLIError.usage("--category requires a value")
            }
            index += 1
            let value = args[index].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { throw CLIError.usage("--category cannot be empty") }
            guard options.category == nil else {
                throw CLIError.usage("metrics list accepts at most one --category")
            }
            options.category = value
        default:
            throw CLIError.usage(
                "unknown metrics option '\(args[index])'\n\nRun 'healthmd metrics --help' for usage."
            )
        }
        index += 1
    }
    return options
}

func parseMetricQueryOptions(_ args: [String]) throws -> MetricQueryOptions {
    var options = MetricQueryOptions()
    var index = 0

    func requireValue(for flag: String) throws -> String {
        guard index + 1 < args.count else { throw CLIError.usage("\(flag) requires a value") }
        index += 1
        return args[index]
    }

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--metric":
            let value = try requireValue(for: arg).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { throw CLIError.usage("--metric cannot be empty") }
            options.metricIDs.append(value)
        case "--category":
            let value = try requireValue(for: arg).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { throw CLIError.usage("--category cannot be empty") }
            options.categories.append(value)
        case "--from":
            options.fromDate = try normalizedISODate(try requireValue(for: arg))
        case "--to":
            options.toDate = try normalizedISODate(try requireValue(for: arg))
        case "--last":
            let value = try requireValue(for: arg)
            guard let days = Int(value), days >= 1 else {
                throw CLIError.usage("--last must be at least 1")
            }
            options.lastDays = days
        case "--yesterday":
            options.yesterday = true
        case "--all":
            options.allAvailable = true
        case "--cached":
            options.cached = true
        case "--reuse-covered":
            options.reuseCovered = true
        case "--all-pages":
            options.allPages = true
        case "--progress-json":
            options.progressJSON = true
        case "--format":
            let value = try requireValue(for: arg)
            guard let format = MetricQueryOutputFormat(rawValue: value) else {
                throw CLIError.usage("--format must be json or table")
            }
            options.outputFormat = format
        case "--detail":
            let value = try requireValue(for: arg)
            guard let detail = MetricQueryDetail(rawValue: value) else {
                throw CLIError.usage("--detail must be summary or lossless")
            }
            options.detail = detail
        case "--grant":
            throw CLIError.usage("--grant was removed; request scope is supplied directly")
        case "--timeout":
            let value = try requireValue(for: arg)
            guard let timeout = Double(value), timeout.isFinite,
                  timeout >= 5, timeout <= 900 else {
                throw CLIError.usage("--timeout must be a finite number between 5 and 900 seconds")
            }
            options.timeout = timeout
        case "--allow-partial":
            options.allowPartial = true
        case "--output":
            options.outputPath = try requireValue(for: arg)
        case "--iphone":
            break
        default:
            throw CLIError.usage(
                "unknown query option '\(arg)'\n\nRun 'healthmd query --help' for usage."
            )
        }
        index += 1
    }

    guard !(options.cached && options.reuseCovered) else {
        throw CLIError.usage("--cached and --reuse-covered are mutually exclusive")
    }
    guard !options.metricIDs.isEmpty || !options.categories.isEmpty else {
        throw CLIError.usage("query requires at least one --metric or --category")
    }
    let hasFrom = options.fromDate != nil
    let hasTo = options.toDate != nil
    guard hasFrom == hasTo else {
        throw CLIError.usage("--from and --to must be supplied together")
    }
    let dateSelectionCount = (hasFrom ? 1 : 0)
        + (options.lastDays == nil ? 0 : 1)
        + (options.yesterday ? 1 : 0)
        + (options.allAvailable ? 1 : 0)
    guard dateSelectionCount == 1 else {
        throw CLIError.usage(
            "query requires exactly one of --from/--to, --last, --yesterday, or --all"
        )
    }
    if let start = options.fromDate, let end = options.toDate,
       requestedISODateRange(startDate: start, endDate: end).isEmpty {
        throw CLIError.usage("--from must not be later than --to")
    }
    return options
}

func parseWorkoutQueryOptions(_ args: [String]) throws -> MetricQueryOptions {
    var options = try parseMetricQueryOptions(["--metric", "workouts"] + args)
    options.operation = .workoutListing
    return options
}

func parseSleepSessionQueryOptions(_ args: [String]) throws -> MetricQueryOptions {
    guard args.first == "sessions" else {
        throw CLIError.usage("sleep currently requires the 'sessions' subcommand")
    }
    var remaining: [String] = []
    var physiologyMetricIDs: [String] = []
    var windowSeconds: Double?
    var includeNaps = false
    var index = 1
    while index < args.count {
        switch args[index] {
        case "--last-nights":
            guard index + 1 < args.count else {
                throw CLIError.usage("--last-nights requires a positive integer")
            }
            remaining.append(contentsOf: ["--last", args[index + 1]])
            index += 2
        case "--window":
            guard index + 1 < args.count else {
                throw CLIError.usage("--window requires first:DURATION, for example first:4h")
            }
            windowSeconds = try parseSleepWindow(args[index + 1])
            index += 2
        case "--include-naps":
            includeNaps = true
            index += 1
        case "--physiology-metric":
            guard index + 1 < args.count else {
                throw CLIError.usage("--physiology-metric requires a canonical metric ID")
            }
            let metricID = args[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !metricID.isEmpty else {
                throw CLIError.usage("--physiology-metric cannot be empty")
            }
            physiologyMetricIDs.append(metricID)
            index += 2
        default:
            remaining.append(args[index])
            index += 1
        }
    }
    var synthetic = [
        "--metric", "sleep_total",
        "--metric", "sleep_bedtime",
        "--metric", "sleep_wake",
        "--metric", "sleep_deep",
        "--metric", "sleep_rem",
        "--metric", "sleep_core",
        "--metric", "sleep_awake",
        "--metric", "sleep_in_bed"
    ]
    for metricID in physiologyMetricIDs {
        synthetic.append(contentsOf: ["--metric", metricID])
    }
    synthetic.append(contentsOf: remaining)
    var options = try parseMetricQueryOptions(synthetic)
    options.detail = .lossless
    options.operation = .sleepSessions(
        windowSeconds: windowSeconds,
        includeNaps: includeNaps
    )
    return options
}

func parseTrainingAlignmentOptions(_ args: [String]) throws -> MetricQueryOptions {
    guard args.first == "align" else {
        throw CLIError.usage("training currently requires the 'align' subcommand")
    }
    var remaining: [String] = []
    var physiologyMetricIDs: [String] = []
    var workoutActivity: String?
    var windowSeconds: Double?
    var includeNaps = false
    var index = 1
    while index < args.count {
        switch args[index] {
        case "--workout":
            guard index + 1 < args.count else {
                throw CLIError.usage("--workout requires an activity name")
            }
            let activity = args[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !activity.isEmpty else { throw CLIError.usage("--workout cannot be empty") }
            workoutActivity = activity
            index += 2
        case "--sleep-window":
            guard index + 1 < args.count else {
                throw CLIError.usage("--sleep-window requires first:DURATION")
            }
            windowSeconds = try parseSleepWindow(args[index + 1])
            index += 2
        case "--include-naps":
            includeNaps = true
            index += 1
        case "--physiology-metric":
            guard index + 1 < args.count else {
                throw CLIError.usage("--physiology-metric requires a canonical metric ID")
            }
            let metricID = args[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !metricID.isEmpty else {
                throw CLIError.usage("--physiology-metric cannot be empty")
            }
            physiologyMetricIDs.append(metricID)
            index += 2
        default:
            remaining.append(args[index])
            index += 1
        }
    }
    var synthetic = [
        "--metric", "workouts",
        "--metric", "sleep_total",
        "--metric", "sleep_bedtime",
        "--metric", "sleep_wake",
        "--metric", "sleep_deep",
        "--metric", "sleep_rem",
        "--metric", "sleep_core",
        "--metric", "sleep_awake",
        "--metric", "sleep_in_bed"
    ]
    for metricID in physiologyMetricIDs {
        synthetic.append(contentsOf: ["--metric", metricID])
    }
    synthetic.append(contentsOf: remaining)
    var options = try parseMetricQueryOptions(synthetic)
    options.detail = .lossless
    options.operation = .workoutSleepAlignment(
        windowSeconds: windowSeconds,
        workoutActivity: workoutActivity,
        includeNaps: includeNaps
    )
    return options
}

func parseSleepWindow(_ value: String) throws -> Double {
    guard value.hasPrefix("first:") else {
        throw CLIError.usage("--window supports session-relative first:DURATION windows")
    }
    let duration = String(value.dropFirst("first:".count)).lowercased()
    guard let suffix = duration.last, ["h", "m", "s"].contains(suffix) else {
        throw CLIError.usage("sleep window duration must end in h, m, or s")
    }
    let numberText = String(duration.dropLast())
    guard let number = Double(numberText), number.isFinite, number > 0 else {
        throw CLIError.usage("sleep window duration must be a positive finite number")
    }
    let multiplier: Double = suffix == "h" ? 3_600 : (suffix == "m" ? 60 : 1)
    let seconds = number * multiplier
    guard seconds <= 24 * 3_600 else {
        throw CLIError.usage("sleep window duration cannot exceed 24 hours")
    }
    return seconds
}

func parseCoverageQueryOptions(_ args: [String]) throws -> MetricQueryOptions {
    var options = try parseMetricQueryOptions(args)
    options.operation = .coverage
    return options
}

func parseTrainingEvidenceOptions(_ args: [String]) throws -> MetricQueryOptions {
    guard args.first == "training" else {
        throw CLIError.usage("evidence currently requires the 'training' packet kind")
    }
    var remaining: [String] = []
    var detailIDs: [String] = []
    var index = 1
    while index < args.count {
        if args[index] == "--workout-detail" {
            guard index + 1 < args.count else {
                throw CLIError.usage("--workout-detail requires a value")
            }
            let detail = args[index + 1].trimmingCharacters(in: .whitespacesAndNewlines)
            guard !detail.isEmpty else {
                throw CLIError.usage("--workout-detail cannot be empty")
            }
            detailIDs.append(detail)
            index += 2
        } else {
            remaining.append(args[index])
            index += 1
        }
    }
    var options = try parseMetricQueryOptions(["--metric", "workouts"] + remaining)
    if !detailIDs.isEmpty { options.detail = .lossless }
    options.operation = .trainingEvidence(detailIDs: Array(Set(detailIDs)).sorted())
    return options
}

func parseCompareQueryOptions(_ args: [String]) throws -> MetricQueryOptions {
    let validAggregations = Set([
        "sum", "average", "minimum", "maximum", "latest", "count", "duration_sum"
    ])
    var firstStart: String?
    var firstEnd: String?
    var secondStart: String?
    var secondEnd: String?
    var aggregations: [(metricID: String, kind: String)] = []
    var common: [String] = []
    var index = 0

    func requiredValue(_ flag: String) throws -> String {
        guard index + 1 < args.count else { throw CLIError.usage("\(flag) requires a value") }
        index += 1
        return args[index]
    }

    while index < args.count {
        let argument = args[index]
        switch argument {
        case "--metric":
            let descriptor = try requiredValue(argument)
            let parts = descriptor.split(separator: ":", omittingEmptySubsequences: false)
            guard parts.count == 2 else {
                throw CLIError.usage("--metric must use METRIC_ID:AGGREGATION")
            }
            let metricID = String(parts[0]).trimmingCharacters(in: .whitespacesAndNewlines)
            let kind = String(parts[1]).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !metricID.isEmpty, validAggregations.contains(kind) else {
                throw CLIError.usage(
                    "comparison aggregation must be sum, average, minimum, maximum, latest, count, or duration_sum"
                )
            }
            aggregations.append((metricID, kind))
        case "--first-from":
            firstStart = try normalizedISODate(try requiredValue(argument))
        case "--first-to":
            firstEnd = try normalizedISODate(try requiredValue(argument))
        case "--second-from":
            secondStart = try normalizedISODate(try requiredValue(argument))
        case "--second-to":
            secondEnd = try normalizedISODate(try requiredValue(argument))
        default:
            common.append(argument)
        }
        index += 1
    }

    guard let firstStart, let firstEnd, let secondStart, let secondEnd else {
        throw CLIError.usage(
            "compare requires --first-from/--first-to and --second-from/--second-to"
        )
    }
    guard !requestedISODateRange(startDate: firstStart, endDate: firstEnd).isEmpty,
          !requestedISODateRange(startDate: secondStart, endDate: secondEnd).isEmpty else {
        throw CLIError.usage("each comparison period must have a start date no later than its end date")
    }
    guard !aggregations.isEmpty else {
        throw CLIError.usage("compare requires at least one --metric METRIC_ID:AGGREGATION")
    }
    let duplicateMetrics = Dictionary(grouping: aggregations, by: \.metricID)
        .filter { $0.value.count > 1 }
        .keys
        .sorted()
    guard duplicateMetrics.isEmpty else {
        throw CLIError.usage("comparison metrics must be unique: \(duplicateMetrics.joined(separator: ","))")
    }

    let combinedStart = min(firstStart, secondStart)
    let combinedEnd = max(firstEnd, secondEnd)
    var synthetic = common
    for aggregation in aggregations {
        synthetic.append(contentsOf: ["--metric", aggregation.metricID])
    }
    synthetic.append(contentsOf: ["--from", combinedStart, "--to", combinedEnd])
    var options = try parseMetricQueryOptions(synthetic)
    options.operation = .periodComparison(
        firstStart: firstStart,
        firstEnd: firstEnd,
        secondStart: secondStart,
        secondEnd: secondEnd,
        aggregations: aggregations.sorted { $0.metricID < $1.metricID }
    )
    return options
}

func isValidCanonicalPointer(_ value: String) -> Bool {
    guard !value.isEmpty, value.hasPrefix("/"), value.utf8.count <= 1_024,
          !value.unicodeScalars.contains(where: CharacterSet.controlCharacters.contains) else {
        return false
    }
    var index = value.startIndex
    while index < value.endIndex {
        if value[index] == "~" {
            let next = value.index(after: index)
            guard next < value.endIndex, value[next] == "0" || value[next] == "1" else {
                return false
            }
            index = value.index(after: next)
        } else {
            index = value.index(after: index)
        }
    }
    return true
}

func canonicalObjectPath(
    _ value: String
) throws -> (path: String, category: String?, requiresLossless: Bool) {
    if isValidCanonicalPointer(value) {
        return (value, nil, value.hasPrefix("/healthkit_record_archive"))
    }
    let normalized = value.lowercased().replacingOccurrences(of: "_", with: "-")
    let topLevel: [String: (String, String)] = [
        "sleep": ("/sleep", "Sleep"),
        "activity": ("/activity", "Activity"),
        "heart": ("/heart", "Heart"),
        "vitals": ("/vitals", "Vitals"),
        "body": ("/body", "Body Measurements"),
        "nutrition": ("/nutrition", "Nutrition"),
        "mindfulness": ("/mindfulness", "Mindfulness"),
        "mobility": ("/mobility", "Mobility"),
        "hearing": ("/hearing", "Hearing"),
        "reproductive-health": ("/reproductiveHealth", "Reproductive Health"),
        "cycling": ("/cyclingPerformance", "Cycling"),
        "vitamins": ("/vitamins", "Vitamins"),
        "minerals": ("/minerals", "Minerals"),
        "symptoms": ("/symptoms", "Symptoms"),
        "medications": ("/medications", "Medications"),
        "other": ("/other", "Other"),
        "workouts": ("/workouts", "Workouts")
    ]
    if let (path, category) = topLevel[normalized] {
        return (path, category, false)
    }
    let archivePaths: [String: String] = [
        "archive": "/healthkit_record_archive",
        "records": "/healthkit_record_archive/records",
        "external-records": "/healthkit_record_archive/external_records",
        "query-results": "/healthkit_record_archive/query_manifest/results",
        "warnings": "/healthkit_record_archive/integrity_warnings"
    ]
    if let path = archivePaths[normalized] { return (path, nil, true) }
    throw CLIError.usage(
        "unknown canonical object '\(value)'; use a documented object name or JSON Pointer"
    )
}

func parseExportOptions(
    _ args: [String],
    canonicalProjection: Bool = false
) throws -> ExportOptions {
    var options = ExportOptions()
    options.canonicalProjection = canonicalProjection
    if canonicalProjection { options.raw = true }
    var index = 0

    func requireValue(for flag: String) throws -> String {
        guard index + 1 < args.count else { throw CLIError.usage("\(flag) requires a value") }
        index += 1
        return args[index]
    }

    while index < args.count {
        let arg = args[index]
        switch arg {
        case "--from":
            let value = try requireValue(for: arg)
            options.fromDate = try normalizedISODate(value)
        case "--to":
            let value = try requireValue(for: arg)
            options.toDate = try normalizedISODate(value)
        case "--last":
            let value = try requireValue(for: arg)
            guard let n = Int(value) else { throw CLIError.invalidInteger(value) }
            options.lastDays = n
        case "--yesterday":
            options.yesterday = true
        case "--all":
            options.allAvailable = true
        case "--timeout":
            let value = try requireValue(for: arg)
            guard let timeout = Double(value),
                  timeout.isFinite,
                  timeout >= 5,
                  timeout <= 900 else {
                throw CLIError.usage("--timeout must be a finite number between 5 and 900 seconds")
            }
            options.timeout = timeout
        case "--raw":
            guard !canonicalProjection else {
                throw CLIError.usage("extract already returns canonical JSON; do not pass --raw")
            }
            options.raw = true
        case "--metric":
            let value = try requireValue(for: arg).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { throw CLIError.usage("--metric cannot be empty") }
            options.metricIDs.append(value)
            options.selectionRequested = true
        case "--category":
            let value = try requireValue(for: arg).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { throw CLIError.usage("--category cannot be empty") }
            options.categories.append(value)
            options.selectionRequested = true
        case "--all-metrics":
            options.allMetrics = true
            options.selectionRequested = true
        case "--detail":
            let value = try requireValue(for: arg)
            guard let detail = MetricQueryDetail(rawValue: value) else {
                throw CLIError.usage("--detail must be summary or lossless")
            }
            options.detail = detail
            options.selectionRequested = true
        case "--source":
            let value = try requireValue(for: arg).trimmingCharacters(in: .whitespacesAndNewlines)
            guard !value.isEmpty else { throw CLIError.usage("--source cannot be empty") }
            options.sourceIDs.append(value)
            options.selectionRequested = true
        case "--object" where canonicalProjection:
            let value = try requireValue(for: arg)
            let resolved = try canonicalObjectPath(value)
            options.objectPaths.append(resolved.path)
            options.selectionRequested = true
            if let category = resolved.category { options.categories.append(category) }
            if resolved.requiresLossless { options.detail = .lossless }
        case "--field" where canonicalProjection:
            let value = try requireValue(for: arg)
            guard isValidCanonicalPointer(value) else {
                throw CLIError.usage("--field requires a JSON Pointer beginning with /")
            }
            options.fieldPointers.append(value)
            options.selectionRequested = true
        case "--format" where canonicalProjection:
            let value = try requireValue(for: arg)
            guard let format = CanonicalExtractionFormat(rawValue: value) else {
                throw CLIError.usage("--format must be json or jsonl")
            }
            options.extractionFormat = format
        case "--allow-partial":
            options.allowPartial = true
        case "--use-iphone-settings":
            options.useIPhoneSettings = true
        case "--output":
            options.outputPath = try requireValue(for: arg)
        case "--iphone":
            break
        default:
            throw CLIError.usage("unknown export option '\(arg)'\n\nRun 'healthmd export --help' for usage.")
        }
        index += 1
    }

    if options.outputPath != nil && !options.raw {
        throw CLIError.usage("--output requires --raw")
    }
    if options.selectionRequested || canonicalProjection {
        guard !options.useIPhoneSettings else {
            throw CLIError.usage("request-scoped selection cannot use --use-iphone-settings")
        }
        guard canonicalProjection || !options.raw else {
            throw CLIError.usage("use `healthmd extract` for scoped canonical JSON instead of combining --raw with selectors")
        }
        guard !(options.allMetrics && (!options.metricIDs.isEmpty || !options.categories.isEmpty)) else {
            throw CLIError.usage("--all-metrics cannot be combined with --metric or --category")
        }
        guard options.allMetrics || !options.metricIDs.isEmpty || !options.categories.isEmpty else {
            throw CLIError.usage(
                "archive/path objects require --metric, --category, or explicit --all-metrics acquisition scope"
            )
        }
        let sources = options.sourceIDs.isEmpty ? ["apple_health"] : options.sourceIDs
        guard Set(sources) == ["apple_health"] else {
            throw CLIError.usage("canonical health_data extraction currently supports only --source apple_health")
        }
        options.sourceIDs = ["apple_health"]
        options.metricIDs = Array(Set(options.metricIDs)).sorted()
        options.categories = Array(Set(options.categories)).sorted()
        options.objectPaths = Array(Set(options.objectPaths)).sorted()
        options.fieldPointers = Array(Set(options.fieldPointers)).sorted()
        if options.objectPaths.contains(where: { $0.hasPrefix("/healthkit_record_archive") })
            || options.fieldPointers.contains(where: { $0.hasPrefix("/healthkit_record_archive") }) {
            options.detail = .lossless
        }
    }
    if options.allAvailable,
       options.fromDate != nil || options.toDate != nil || options.lastDays != nil || options.yesterday {
        throw CLIError.usage("--all cannot be combined with --from/--to, --last, or --yesterday")
    }
    return options
}

func parseResumeOptions(_ args: [String]) throws -> ResumeOptions {
    var options = ResumeOptions()
    var index = 0
    while index < args.count {
        switch args[index] {
        case "--timeout":
            guard index + 1 < args.count else { throw CLIError.usage("--timeout requires a value") }
            index += 1
            let value = args[index]
            guard let timeout = Double(value), timeout.isFinite, timeout >= 5, timeout <= 900 else {
                throw CLIError.usage("--timeout must be a finite number between 5 and 900 seconds")
            }
            options.timeout = timeout
        case "--output":
            guard index + 1 < args.count else { throw CLIError.usage("--output requires a value") }
            index += 1
            options.outputPath = args[index]
        case "--allow-partial":
            options.allowPartial = true
        default:
            throw CLIError.usage("unknown resume option '\(args[index])'")
        }
        index += 1
    }
    return options
}

func makeExportRequestBody(
    options: ExportOptions,
    startDate: String?,
    endDate: String?
) -> [String: Any] {
    var body: [String: Any] = [
        "source": "connected_iphone",
        "date_selection": options.allAvailable ? "all_available" : "explicit_range",
        "settings_policy": options.useIPhoneSettings ? "current_iphone_settings" : "requested_dates_only",
        "response_mode": options.raw ? "raw_json" : "write_files",
        "wait_timeout_seconds": options.timeout
    ]
    if !options.allAvailable, let startDate, let endDate {
        body["date_range"] = ["start": startDate, "end": endDate]
    }
    if options.canonicalProjection {
        body["raw_profile"] = "health_data_projection"
    } else if options.raw {
        body["raw_profile"] = "canonical_source_records_v1"
    }
    if options.selectionRequested || options.canonicalProjection {
        body["canonical_selection"] = [
            "metric_ids": options.metricIDs,
            "categories": options.categories,
            "all_metrics": options.allMetrics,
            "source_ids": options.sourceIDs,
            "detail_level": options.detail.rawValue,
            "object_paths": options.objectPaths,
            "field_pointers": options.fieldPointers
        ]
    }
    return body
}

func strictRawResolvedDateRange(payload: Any) -> (start: String, end: String)? {
    guard let response = payload as? [String: Any],
          let rawResult = response["raw_result"] as? [String: Any],
          let dateRange = rawResult["date_range"] as? [String: Any],
          let start = dateRange["start"] as? String,
          let end = dateRange["end"] as? String else { return nil }
    return (start, end)
}

private let strictRawResultSchema = "healthmd.raw_result"
private let strictRawResultVersion = 1
private let strictRawProfile = "canonical_source_records_v1"
private let currentDailySchema = "healthmd.health_data"
private let currentDailySchemaVersion = 7
private let currentArchiveSchema = "healthmd.healthkit_records"
private let currentArchiveSchemaVersion = 1

func strictRawValidationIssues(payload: Any, expectedDates: [String]) -> [String] {
    guard let response = payload as? [String: Any] else {
        return ["success_response_not_object"]
    }
    guard let rawResult = response["raw_result"] as? [String: Any] else {
        return ["raw_result_missing"]
    }

    var issues: [String] = []
    let responseStatus = response["status"] as? String
    if responseStatus != "success" && responseStatus != "partial_success" {
        issues.append("success_response_status_mismatch")
    }
    if rawResult["schema"] as? String != strictRawResultSchema {
        issues.append("raw_result_schema_mismatch")
    }
    if rawResult["schema_version"] as? Int != strictRawResultVersion {
        issues.append("raw_result_schema_version_mismatch")
    }
    if rawResult["profile"] as? String != strictRawProfile {
        issues.append("raw_result_profile_mismatch")
    }
    if rawResult["created_at"] as? String == nil {
        issues.append("raw_result_created_at_missing")
    }
    if rawResult["source_device_name"] as? String == nil {
        issues.append("raw_result_source_device_name_missing")
    }
    if rawResult["total_requested_days"] as? Int != expectedDates.count {
        issues.append("raw_result_total_requested_days_mismatch")
    }
    if let dateRange = rawResult["date_range"] as? [String: Any] {
        if dateRange["start"] as? String != expectedDates.first
            || dateRange["end"] as? String != expectedDates.last {
            issues.append("raw_result_date_range_mismatch")
        }
    } else {
        issues.append("raw_result_date_range_missing")
    }

    let captureSummary = rawResult["capture_summary"] as? [String: Any]
    if captureSummary == nil { issues.append("raw_result_capture_summary_missing") }
    let declaredMissingDates = rawResult["missing_dates"] as? [String]
    if declaredMissingDates == nil { issues.append("raw_result_missing_dates_missing") }

    guard let days = rawResult["days"] as? [[String: Any]] else {
        issues.append("raw_result_days_missing")
        return issues
    }
    let suppliedDates = days.compactMap { $0["date"] as? String }
    if suppliedDates.count != days.count {
        issues.append("raw_result_day_date_missing")
    }
    if Set(suppliedDates).count != suppliedDates.count {
        issues.append("raw_result_duplicate_dates")
    }
    if suppliedDates != expectedDates {
        issues.append("raw_result_date_set_mismatch")
    }
    let calculatedMissingDates = days.compactMap { day in
        day["status"] as? String == "missing" ? day["date"] as? String : nil
    }.sorted()
    if declaredMissingDates?.sorted() != calculatedMissingDates {
        issues.append("raw_result_missing_dates_mismatch")
    }
    let retainedDayCount = days.filter { $0["health_data"] is [String: Any] }.count
    if captureSummary?["retained_day_count"] as? Int != retainedDayCount {
        issues.append("raw_result_capture_summary_mismatch")
    }
    if captureSummary?["missing_day_count"] as? Int != calculatedMissingDates.count {
        issues.append("raw_result_capture_summary_mismatch")
    }

    for day in days {
        let date = day["date"] as? String ?? "unknown"
        let status = day["status"] as? String
        let mayOmitHealthData = responseStatus == "partial_success"
            && (status == "failed" || status == "cancelled" || status == "missing")
        guard let healthData = day["health_data"] as? [String: Any] else {
            if !mayOmitHealthData { issues.append("daily_health_data_missing:\(date)") }
            continue
        }
        if healthData["schema"] as? String != currentDailySchema {
            issues.append("daily_schema_mismatch:\(date)")
        }
        if healthData["schema_version"] as? Int != currentDailySchemaVersion {
            issues.append("daily_schema_version_mismatch:\(date)")
        }
        guard let archive = healthData["healthkit_record_archive"] as? [String: Any] else {
            issues.append("canonical_archive_missing:\(date)")
            continue
        }
        if archive["schema"] as? String != currentArchiveSchema {
            issues.append("canonical_archive_schema_mismatch:\(date)")
        }
        if archive["schema_version"] as? Int != currentArchiveSchemaVersion {
            issues.append("canonical_archive_schema_version_mismatch:\(date)")
        }
    }
    return issues
}

func validateStrictRawHTTPSuccess(
    payload: Any,
    expectedDates: [String]
) -> (isValid: Bool, outputPayload: Any) {
    let issues = strictRawValidationIssues(payload: payload, expectedDates: expectedDates)
    guard !issues.isEmpty else { return (true, payload) }
    return (false, strictRawValidationFailurePayload(
        serverPayload: payload,
        expectedDates: expectedDates,
        issues: issues
    ))
}

func strictRawValidationFailurePayload(
    serverPayload: Any,
    expectedDates: [String],
    issues: [String]
) -> [String: Any] {
    [
        "status": "failure",
        "error": "invalid_strict_raw_success",
        "message": "The Mac app returned HTTP 200 with an invalid strict raw success envelope.",
        "diagnostics": [
            "validation": "strict_raw_success_envelope",
            "issues": issues,
            "requested_dates": expectedDates
        ],
        "server_response": serverPayload
    ]
}

func requestedISODateRange(startDate: String, endDate: String) -> [String] {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    guard let start = formatter.date(from: startDate),
          let end = formatter.date(from: endDate),
          start <= end else { return [] }

    var dates: [String] = []
    var date = start
    while date <= end {
        dates.append(formatter.string(from: date))
        guard let next = formatter.calendar.date(byAdding: .day, value: 1, to: date) else { break }
        date = next
    }
    return dates
}

func exportExitCode(
    httpStatusCode: Int,
    status: String?,
    isRaw: Bool,
    allowPartial: Bool
) -> Int {
    guard httpStatusCode == 200 else { return 1 }
    switch status {
    case "success":
        return 0
    case "partial_success":
        // Preserve the historical file-export exit behavior. Strict raw capture
        // requires an explicit opt-in before partial results exit successfully.
        return !isRaw || allowPartial ? 0 : 1
    default:
        return 1
    }
}

func resolveMetricQueryDateSelection(_ options: MetricQueryOptions) throws -> [String: Any] {
    if options.allAvailable {
        return ["type": "all_available"]
    }

    let range: (start: String, end: String)
    if options.yesterday {
        let day = try dateString(daysFromToday: -1)
        range = (day, day)
    } else if let days = options.lastDays {
        guard days >= 1 else { throw CLIError.usage("--last must be at least 1") }
        range = (
            try dateString(daysFromToday: -days),
            try dateString(daysFromToday: -1)
        )
    } else if let start = options.fromDate, let end = options.toDate {
        guard !requestedISODateRange(startDate: start, endDate: end).isEmpty else {
            throw CLIError.usage("--from must not be later than --to")
        }
        range = (start, end)
    } else {
        throw CLIError.usage(
            "query requires exactly one of --from/--to, --last, --yesterday, or --all"
        )
    }

    return [
        "type": "exact",
        "range": [
            "start_date": range.start,
            "end_date": range.end
        ]
    ]
}

private func resolveDateRange(_ options: ExportOptions) throws -> (start: String, end: String) {
    if options.yesterday {
        let day = try dateString(daysFromToday: -1)
        return (day, day)
    }

    if let n = options.lastDays {
        guard n >= 1 else { throw CLIError.usage("--last must be at least 1") }
        let end = try dateString(daysFromToday: -1)
        let start = try dateString(daysFromToday: -n)
        return (start, end)
    }

    guard let fromDate = options.fromDate, let toDate = options.toDate else {
        throw CLIError.usage("export requires --from/--to, --last, --yesterday, or --all")
    }
    return (fromDate, toDate)
}

private func normalizedISODate(_ value: String) throws -> String {
    let formatter = DateFormatter()
    formatter.calendar = Calendar(identifier: .gregorian)
    formatter.locale = Locale(identifier: "en_US_POSIX")
    formatter.timeZone = TimeZone(secondsFromGMT: 0)
    formatter.dateFormat = "yyyy-MM-dd"
    guard let date = formatter.date(from: value) else { throw CLIError.invalidDate(value) }
    return formatter.string(from: date)
}

private func dateString(daysFromToday offset: Int) throws -> String {
    let calendar = Calendar.current
    guard let target = calendar.date(byAdding: .day, value: offset, to: Date()) else {
        throw CLIError.usage("Requested lookback is outside the supported calendar range")
    }
    let components = calendar.dateComponents([.year, .month, .day], from: target)
    return String(format: "%04d-%02d-%02d", components.year ?? 1970, components.month ?? 1, components.day ?? 1)
}

private func printGeneralHelp() {
    print("""
    usage: healthmd [-h] [--base-url BASE_URL]
                    {status,doctor,metrics,extract,query,sleep,training,workouts,coverage,compare,evidence,export,resume,cancel,agent} ...

    Control the running Health.md Mac app

    positional arguments:
      {status,doctor,metrics,extract,query,sleep,training,workouts,coverage,compare,evidence,export,resume,cancel,agent}
        status         Show connection readiness, or inspect one durable job
        doctor         Diagnose CLI, cache, and iPhone readiness
        metrics        List canonical metrics available to local queries
        extract        Export selected objects directly from healthmd.health_data
        query          Run compatibility/derived metric queries over selected data
        sleep          List first-class overnight sessions and fixed session windows
        training       Align workouts to preceding/following sleep without causal claims
        workouts       List selected workouts through the typed query contract
        coverage       Inspect explicit metric/date coverage and missingness
        compare        Compare two periods with explicit metric aggregations
        evidence       Create factual typed evidence packets
        export         Ask the connected/open iPhone to export to this Mac
        resume         Resume and wait for a durable export job
        cancel         Explicitly cancel a durable export job
        agent          Use the low-level local query/evidence/job API

    options:
      -h, --help       show this help message and exit
      --base-url URL   loopback Mac app URL (default: http://127.0.0.1:17645)
    """)
}

private func printDoctorHelp() {
    print("""
    usage: healthmd doctor [--json]

    Return machine-readable Mac, encrypted-cache, and iPhone readiness with
    actionable next steps. JSON is always used; --json is an explicit
    compatibility flag.
    """)
}

private func printMetricsHelp() {
    print("""
    usage: healthmd metrics [list] [--category NAME]

    Return the canonical metric catalog as JSON. Category matching is
    case-insensitive and does not claim HealthKit read authorization.
    """)
}

private func printExtractHelp() {
    print("""
    usage: healthmd extract
                    (--metric ID | --category NAME | --object NAME | --all-metrics) ...
                    (--from DATE --to DATE | --last N | --yesterday | --all)
                    [--detail summary|lossless] [--source apple_health]
                    [--field /JSON/POINTER] ... [--format json|jsonl]
                    [--timeout 5...900] [--allow-partial] [--output PATH]

    Ask the connected iPhone to acquire only the selected metrics and detail,
    then emit ordinary `healthmd.health_data` v7 documents or projections. The
    transfer/job envelope is validated and removed before stdout. Summary is the
    default and does not capture the lossless archive. `--object records` and
    other archive objects imply lossless detail. Object names include sleep,
    activity, heart, vitals, body, nutrition, mindfulness, mobility, hearing,
    reproductive-health, cycling, vitamins, minerals, symptoms, medications,
    other, workouts, archive, records, external-records, query-results, warnings.
    JSON output contains `health_data` or exact pointer `projections` plus an
    explicit receipt. JSONL writes one data item per line and writes its receipt
    to stderr, or to OUTPUT.receipt.json when --output is used.
    """)
}

private func printQueryHelp() {
    print("""
    usage: healthmd query
                    (--metric ID | --category NAME) ...
                    (--from DATE --to DATE | --last N | --yesterday | --all)
                    [--cached | --reuse-covered] [--detail summary|lossless]
                    [--all-pages] [--progress-json] [--format json|table]
                    [--timeout 5...900] [--allow-partial]
                    [--output PATH] [--iphone]

    Compatibility and derived query surface. For direct source-schema access,
    prefer `healthmd extract`, which emits canonical healthmd.health_data objects.
    This command performs request-scoped fresh iPhone acquisition, then queries
    the encrypted Mac index. Saved iPhone settings are not changed.
    --cached skips acquisition. --reuse-covered skips it only after a complete
    metric/day coverage check. --all-pages follows cursors within bounded aggregate
    byte/page ceilings; narrow scope or page manually if reached. --progress-json
    writes JSONL events to stderr; stdout remains the final JSON or opt-in table.
    Multiple metric/category flags are combined.
    """)
}

private func printSleepHelp() {
    print("""
    usage: healthmd sleep sessions
                    (--last-nights N | --from DATE --to DATE | --yesterday | --all)
                    [--window first:DURATION] [--include-naps]
                    [--physiology-metric ID] ... [--cached | --reuse-covered]
                    [--all-pages] [--progress-json] [--format json|table]
                    [--timeout 5...900] [--allow-partial]
                    [--output PATH]

    List stable sleep sessions with owner date, local timestamps/timezone,
    overnight/nap classification, observed and untracked duration, completeness,
    selected stage totals, evidence, and explicit physiology coverage. Every
    session request acquires lossless canonical stage detail and includes the
    required adjacent owner-day scope; fixed windows never apportion aggregate totals.
    """)
}

private func printTrainingHelp() {
    print("""
    usage: healthmd training align
                    (--last N | --from DATE --to DATE | --yesterday | --all)
                    [--workout ACTIVITY] [--sleep-window first:DURATION]
                    [--physiology-metric ID] ... [--include-naps]
                    [--cached | --reuse-covered] [--all-pages] [--progress-json]
                    [--format json|table] [--timeout 5...900]
                    [--allow-partial] [--output PATH]

    Deterministically align each selected workout with the nearest eligible
    preceding and following sleep sessions within 36 hours. Output includes
    stable IDs, timing gaps, requested sleep windows, physiology sample counts,
    coverage, evidence, and exclusions. It reports temporal alignment only and
    never claims that a workout caused a sleep change (or vice versa).
    """)
}

private func printWorkoutsHelp() {
    print("""
    usage: healthmd workouts
                    (--from DATE --to DATE | --last N | --yesterday | --all)
                    [--cached | --reuse-covered] [--all-pages] [--progress-json]
                    [--format json|table] [--timeout 5...900]
                    [--allow-partial] [--output PATH]

    Acquire and list selected workouts using the typed workout_listing operation.
    Results preserve stable workout identity, details, evidence, and missingness.
    """)
}

private func printCoverageHelp() {
    print("""
    usage: healthmd coverage
                    (--metric ID | --category NAME) ...
                    (--from DATE --to DATE | --last N | --yesterday | --all)
                    [--cached | --reuse-covered] [--all-pages] [--progress-json]
                    [--format json|table] [--timeout 5...900]
                    [--allow-partial] [--output PATH]

    Return factual date/metric coverage and explicit missingness without
    fabricating zero values.
    """)
}

private func printCompareHelp() {
    print("""
    usage: healthmd compare
                    --metric METRIC_ID:AGGREGATION ...
                    --first-from DATE --first-to DATE
                    --second-from DATE --second-to DATE
                    [--cached | --reuse-covered] [--all-pages] [--progress-json]
                    [--format json|table] [--timeout 5...900]
                    [--allow-partial] [--output PATH]

    Compare two exact periods using caller-selected sum, average, minimum,
    maximum, latest, count, or duration_sum semantics. Direction remains factual
    (increased/decreased/unchanged), never better or worse.
    """)
}

private func printEvidenceHelp() {
    print("""
    usage: healthmd evidence training
                    [--metric ID | --category NAME] ...
                    [--workout-detail ID] ...
                    (--from DATE --to DATE | --last N | --yesterday | --all)
                    [--cached | --reuse-covered] [--all-pages] [--progress-json]
                    [--format json|table] [--timeout 5...900]
                    [--allow-partial] [--output PATH]

    Create a factual training evidence packet. Selecting workout details requests
    lossless detail directly for this request.
    """)
}

private func printAgentHelp() {
    print("""
    usage: healthmd agent SUBCOMMAND ...

    Low-level loopback API subcommands:
      capabilities
      query    --input PATH|- | --json JSON
      evidence --input PATH|- | --json JSON
      refresh  --input PATH|- | --json JSON
      job status UUID
      job resume UUID [--timeout 5...900]
      job cancel UUID

    Requests carry their metric, source, date, and detail scope directly. Query
    and evidence responses are one bounded page; pass each returned next_cursor
    in the next request for complete traversal without a total-result cap.
    """)
}

private func printStatusHelp() {
    print("""
    usage: healthmd status [-h] [--job UUID]

    Show Mac app readiness or one durable export job as JSON
    """)
}

private func printResumeHelp() {
    print("""
    usage: healthmd resume UUID [--timeout TIMEOUT] [--output PATH] [--allow-partial]

    Resend the exact stored request and wait for its durable result. Strict raw
    responses retain digest, date-range, and schema validation.
    """)
}

private func printCancelHelp() {
    print("""
    usage: healthmd cancel UUID

    Explicitly cancel a durable export job. Disconnects and wait timeouts do not cancel jobs.
    """)
}

private func printExportHelp() {
    print("""
    usage: healthmd export [-h] [--from FROM_DATE] [--to TO_DATE] [--last LAST]
                           [--yesterday | --all] [--timeout TIMEOUT] [--raw]
                           [--metric ID | --category NAME | --all-metrics]
                           [--detail summary|lossless] [--source apple_health]
                           [--allow-partial] [--output PATH]
                           [--use-iphone-settings] [--iphone]

    options:
      -h, --help            show this help message and exit
      --from FROM_DATE      Start date, YYYY-MM-DD
      --to TO_DATE          End date, YYYY-MM-DD
      --last LAST           Export the last N complete days ending yesterday
      --yesterday           Export yesterday
      --all                 Export every available selected day from the iPhone
      --timeout TIMEOUT     Inactivity timeout, 5...900 seconds (default: 300)
      --metric ID           Request only this canonical metric (repeatable; file mode)
      --category NAME       Request only metrics in this category (repeatable; file mode)
      --all-metrics         Explicitly request the complete metric catalog
      --detail LEVEL        summary or lossless for a request-scoped file export
      --source ID           Currently apple_health for scoped canonical exports
      --raw                 Return strict canonical_source_records_v1 JSON; do not write files
      --allow-partial       Exit 0 for a raw partial_success response (diagnostics are still printed)
      --output PATH         Atomically write a raw response instead of streaming it to stdout
      --use-iphone-settings Use the iPhone app's saved export settings exactly, including roll-ups;
                            cannot be combined with request-scoped metric selection
      --iphone              Accepted for readability; connected iPhone is the only export source
    """)
}
