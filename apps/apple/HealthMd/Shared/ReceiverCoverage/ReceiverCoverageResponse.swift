import Foundation

/// Immutable new-occurrence context. Persist this context before preflight; retries must restore
/// the original plan rather than manufacture a new request from today's date/current settings.
nonisolated struct ReceiverCoverageRequest: Sendable {
    let body: Data
    let destinationBinding: String
    fileprivate let expected: [String: String]
    fileprivate let today: String
    let url: URL
    let headers: [String: String]

    fileprivate init(preflight: ReceiverCoveragePreflight, requestID: String, candidates: [String], now: Date) throws {
        body = try preflight.requestBody(requestID: requestID, candidates: candidates, now: now)
        let wire = try JSONSerialization.jsonObject(with: body) as! [String: Any]
        expected = ["schema": "healthmd.receiver_coverage.response", "request_id": requestID,
                    "scope_id": preflight.scopeID, "calendar_timezone": preflight.calendarTimeZoneIdentifier,
                    "start": wire["start"] as! String, "end_exclusive": wire["end_exclusive"] as! String]
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = preflight.calendarTimeZone
        let parts = calendar.dateComponents([.year, .month, .day], from: now)
        today = String(format: "%04d-%02d-%02d", parts.year!, parts.month!, parts.day!)
        destinationBinding = preflight.destinationBinding
        url = preflight.preflightURL
        headers = preflight.headers
    }
}

extension ReceiverCoveragePreflight {
    func freezeRequest(requestID: String, candidates: [String], now: Date) throws -> ReceiverCoverageRequest {
        try ReceiverCoverageRequest(preflight: self, requestID: requestID, candidates: candidates, now: now)
    }
}

nonisolated enum ReceiverCoverageOutcome: Sendable {
    case valid(ReceiverCoverageEvidence)
    /// New-occurrence failure only. Never use this to repair an unreadable saved plan.
    case fallbackFull
}

nonisolated struct ReceiverCoverageEvidence: Sendable {
    let completedDates: [String]
    /// Only validated, normalized response fields, suitable for the future frozen plan.
    let normalizedResponse: Data

    private init(completedDates: [String], normalizedResponse: Data) {
        self.completedDates = completedDates
        self.normalizedResponse = normalizedResponse
    }

    static func parse(_ body: Data, for request: ReceiverCoverageRequest) throws -> Self {
        var reader = CoverageJSONReader(body)
        let (fields, dates) = try reader.response()
        guard fields == request.expected, dates == Array(Set(dates)).sorted() else {
            throw ReceiverCoveragePreflight.BoundaryError.invalidResponse
        }
        for day in dates {
            let bytes = Array(day.utf8)
            guard bytes.count == 10, bytes[4] == 45, bytes[7] == 45,
                  bytes.enumerated().allSatisfy({ $0.offset == 4 || $0.offset == 7 || (48...57).contains($0.element) }),
                  let year = Int(day.prefix(4)), year >= 1,
                  let month = Int(day.dropFirst(5).prefix(2)), let date = Int(day.suffix(2)),
                  (1...12).contains(month) else { throw ReceiverCoveragePreflight.BoundaryError.invalidResponse }
            let leap = year % 4 == 0 && (year % 100 != 0 || year % 400 == 0)
            let lengths = [31, leap ? 29 : 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]
            guard (1...lengths[month - 1]).contains(date), day >= request.expected["start"]!,
                  day < request.expected["end_exclusive"]!, day < request.today else {
                throw ReceiverCoveragePreflight.BoundaryError.invalidResponse
            }
        }
        var normalized: [String: Any] = fields
        normalized["schema_version"] = 1
        normalized["completed_dates"] = dates
        return try Self(completedDates: dates, normalizedResponse: JSONSerialization.data(
            withJSONObject: normalized, options: [.sortedKeys, .withoutEscapingSlashes]))
    }
}

/// Schema-specific, nonrecursive JSON reader. Unlike dictionary decoders, it rejects duplicate
/// keys (including escaped spellings), unknown fields, noninteger versions and nested payloads.
private nonisolated struct CoverageJSONReader {
    let bytes: [UInt8]
    var offset = 0
    init(_ data: Data) { bytes = Array(data) }
    private var invalid: ReceiverCoveragePreflight.BoundaryError { .invalidResponse }

    mutating func response() throws -> ([String: String], [String]) {
        guard bytes.count <= ReceiverCoveragePreflight.maximumResponseBytes else { throw invalid }
        try consume(123)
        var seen = Set<String>()
        var fields: [String: String] = [:]
        var days: [String] = []
        let names: Set<String> = ["schema", "request_id", "scope_id", "calendar_timezone", "start", "end_exclusive"]
        while true {
            let key = try string()
            guard seen.insert(key).inserted else { throw invalid }
            try consume(58)
            if names.contains(key) {
                fields[key] = try string()
            } else if key == "schema_version" {
                // The following delimiter check rejects 1.0, 1e0 and 10 as well as true.
                try consume(49)
            } else if key == "completed_dates" {
                try consume(91)
                if !take(93) {
                    while true {
                        guard days.count < 30 else { throw invalid }
                        days.append(try string())
                        if take(93) { break }
                        try consume(44)
                    }
                }
            } else { throw invalid }
            if take(125) { break }
            try consume(44)
        }
        whitespace()
        guard offset == bytes.count, seen == names.union(["schema_version", "completed_dates"]) else { throw invalid }
        return (fields, days)
    }

    mutating func whitespace() {
        while offset < bytes.count && [9, 10, 13, 32].contains(bytes[offset]) { offset += 1 }
    }
    mutating func take(_ byte: UInt8) -> Bool {
        whitespace()
        guard offset < bytes.count && bytes[offset] == byte else { return false }
        offset += 1
        return true
    }
    mutating func consume(_ byte: UInt8) throws { guard take(byte) else { throw invalid } }
    mutating func string() throws -> String {
        whitespace()
        let start = offset
        try consume(34)
        while offset < bytes.count {
            let byte = bytes[offset]
            offset += 1
            if byte == 34 {
                do { return try JSONDecoder().decode(String.self, from: Data(bytes[start..<offset])) }
                catch { throw invalid }
            }
            if byte == 92 { offset += 1 } // JSONDecoder validates escapes, UTF-8 and surrogates.
        }
        throw invalid
    }
}
