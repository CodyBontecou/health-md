import Foundation

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
    expectedDates: [String]
) throws -> [String] {
    let accumulator = StreamingStrictRawAccumulator(expectedDates: expectedDates)
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
    private var responseStatus: String?
    private var rawSchema: String?
    private var rawSchemaVersion: Int?
    private var rawProfile: String?
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

    init(expectedDates: [String]) {
        self.expectedDates = expectedDates
    }

    func wantsScalar(at path: [StreamingJSONPathComponent]) -> Bool {
        if path == [.key("status")] { return true }
        if path.count == 2, path[0] == .key("raw_result") {
            return [
                "schema", "schema_version", "profile", "created_at",
                "source_device_name", "total_requested_days"
            ].contains(path.key(at: 1))
        }
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
        if rawProfile != "canonical_source_records_v1" { issues.append("raw_result_profile_mismatch") }
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
                if !day.hasArchive { issues.append("canonical_archive_missing:\(date)") }
                if day.archiveSchema != "healthmd.healthkit_records" {
                    issues.append("canonical_archive_schema_mismatch:\(date)")
                }
                if day.archiveSchemaVersion != 1 {
                    issues.append("canonical_archive_schema_version_mismatch:\(date)")
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
    func didStartArray(at path: [StreamingJSONPathComponent])
    func didReadScalar(_ scalar: StreamingJSONScalar, at path: [StreamingJSONPathComponent])
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
        try expect(0x7b)
        visitor?.didStartObject(at: path)
        try skipWhitespace()
        if try consumeIf(0x7d) { return }
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
            if try consumeIf(0x7d) { return }
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
                "schema", "schema_version", "profile", "created_at", "source_device_name",
                "date_range", "total_requested_days", "days", "capture_summary", "missing_dates"
            ].contains(key)
        }
        if path == [.key("raw_result"), .key("date_range")] {
            return key == "start" || key == "end"
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
    var baseURL = defaultBaseURL
    var command: Command
}

enum Command {
    case status(jobID: UUID?)
    case export(ExportOptions)
    case resume(UUID, ResumeOptions)
    case cancel(UUID)
    case help
    case noOp
}

struct ResumeOptions {
    var timeout: Double = 300
    var outputPath: String?
    var allowPartial = false
}

struct ExportOptions {
    var fromDate: String?
    var toDate: String?
    var lastDays: Int?
    var yesterday = false
    var timeout: Double = 300
    var raw = false
    var allowPartial = false
    var useIPhoneSettings = false
    var outputPath: String?
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
            try emitDownloadedResponse(downloaded.fileURL, outputPath: nil)
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
            try emitDownloadedResponse(downloaded.fileURL, outputPath: options.outputPath)
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
    case .export(let options):
        let range = try resolveDateRange(options)
        var body = makeExportRequestBody(
            options: options,
            startDate: range.start,
            endDate: range.end
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
                let expectedDates = requestedISODateRange(startDate: range.start, endDate: range.end)
                guard downloaded.bodyDigestIsValid else {
                    printJSON(["error": "response_digest_mismatch"])
                    return 1
                }
                guard downloaded.matchesRequestedRange(
                    start: range.start,
                    end: range.end,
                    totalDays: expectedDates.count
                ) else {
                    printJSON(["error": "raw_response_date_range_mismatch"])
                    return 1
                }
                do {
                    let issues = try streamingStrictRawValidationIssues(
                        fileURL: downloaded.fileURL,
                        expectedDates: expectedDates
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
                let expectedDates = requestedISODateRange(startDate: range.start, endDate: range.end)
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

private func emitDataResponse(_ data: Data, outputPath: String) throws {
    let destination = URL(fileURLWithPath: outputPath).standardizedFileURL
    try data.write(to: destination, options: .atomic)
    try? FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: destination.path)
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

    if args.first == "--base-url" {
        guard args.count >= 2 else { throw CLIError.usage("--base-url requires a value") }
        baseURL = args[1]
        args.removeFirst(2)
    } else if let first = args.first, first.hasPrefix("--base-url=") {
        baseURL = String(first.dropFirst("--base-url=".count))
        args.removeFirst()
    }

    guard let command = args.first else { return ParsedCommand(baseURL: baseURL, command: .help) }
    args.removeFirst()

    switch command {
    case "status":
        if args.contains("-h") || args.contains("--help") {
            printStatusHelp()
            return ParsedCommand(baseURL: baseURL, command: .noOp)
        }
        if args.isEmpty { return ParsedCommand(baseURL: baseURL, command: .status(jobID: nil)) }
        guard args.count == 2, args[0] == "--job", let jobID = UUID(uuidString: args[1]) else {
            throw CLIError.usage("status accepts only --job UUID")
        }
        return ParsedCommand(baseURL: baseURL, command: .status(jobID: jobID))
    case "export":
        if args.contains("-h") || args.contains("--help") {
            printExportHelp()
            return ParsedCommand(baseURL: baseURL, command: .noOp)
        }
        return ParsedCommand(baseURL: baseURL, command: .export(try parseExportOptions(args)))
    case "resume":
        if args.contains("-h") || args.contains("--help") {
            printResumeHelp()
            return ParsedCommand(baseURL: baseURL, command: .noOp)
        }
        guard let value = args.first, let jobID = UUID(uuidString: value) else {
            throw CLIError.usage("resume requires a job UUID")
        }
        return ParsedCommand(
            baseURL: baseURL,
            command: .resume(jobID, try parseResumeOptions(Array(args.dropFirst())))
        )
    case "cancel":
        if args.contains("-h") || args.contains("--help") {
            printCancelHelp()
            return ParsedCommand(baseURL: baseURL, command: .noOp)
        }
        guard args.count == 1, let jobID = UUID(uuidString: args[0]) else {
            throw CLIError.usage("cancel requires exactly one job UUID")
        }
        return ParsedCommand(baseURL: baseURL, command: .cancel(jobID))
    default:
        throw CLIError.usage("unknown command '\(command)'\n\nRun 'healthmd --help' for usage.")
    }
}

func parseExportOptions(_ args: [String]) throws -> ExportOptions {
    var options = ExportOptions()
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
            options.raw = true
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
    startDate: String,
    endDate: String
) -> [String: Any] {
    var body: [String: Any] = [
        "source": "connected_iphone",
        "date_range": [
            "start": startDate,
            "end": endDate
        ],
        "settings_policy": options.useIPhoneSettings ? "current_iphone_settings" : "requested_dates_only",
        "response_mode": options.raw ? "raw_json" : "write_files",
        "wait_timeout_seconds": options.timeout
    ]
    if options.raw {
        body["raw_profile"] = "canonical_source_records_v1"
    }
    return body
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
        throw CLIError.usage("export requires --from/--to, --last, or --yesterday")
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
    usage: healthmd [-h] [--base-url BASE_URL] {status,export,resume,cancel} ...

    Control the running Health.md Mac app

    positional arguments:
      {status,export,resume,cancel}
        status         Show readiness, or inspect one durable job with --job UUID
        export         Ask the connected/open iPhone to export to this Mac
        resume         Resume and wait for a durable export job
        cancel         Explicitly cancel a durable export job

    options:
      -h, --help       show this help message and exit
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
                           [--yesterday] [--timeout TIMEOUT] [--raw]
                           [--allow-partial] [--output PATH]
                           [--use-iphone-settings] [--iphone]

    options:
      -h, --help            show this help message and exit
      --from FROM_DATE      Start date, YYYY-MM-DD
      --to TO_DATE          End date, YYYY-MM-DD
      --last LAST           Export the last N complete days ending yesterday
      --yesterday           Export yesterday
      --timeout TIMEOUT     Inactivity timeout, 5...900 seconds (default: 300)
      --raw                 Return strict canonical_source_records_v1 JSON; do not write files
      --allow-partial       Exit 0 for a raw partial_success response (diagnostics are still printed)
      --output PATH         Atomically write a raw response instead of streaming it to stdout
      --use-iphone-settings Use the iPhone app's saved export settings exactly, including roll-ups
      --iphone              Accepted for readability; connected iPhone is the only export source
    """)
}
