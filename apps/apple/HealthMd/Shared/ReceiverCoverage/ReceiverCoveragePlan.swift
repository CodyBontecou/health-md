import Foundation

/// The proposal's recovery-plan v2, independent of native admission metadata. Restoration is
/// deliberately throwing: invalid evidence must preserve the original journal, never reselect.
nonisolated struct ReceiverCoveragePlan: Equatable, Sendable {
    private struct Request: Codable, Equatable, Sendable {
        let request_id: String
        let scope_id: String
        let calendar_timezone: String
        let candidates: [String]
        let today: String
    }
    private struct Wire: Codable, Equatable, Sendable {
        let schema: String
        let schema_version: Int
        let destination_binding: String
        let request: Request
        let policy: String
        let refresh_recent_days: Int
        let today_refresh: Bool
        let selected: [String]
        var residual: [String]
        let coverage_status: String
        let coverage_response: String?
        // Explicit null is part of the v2 grammar.
        func encode(to encoder: any Encoder) throws {
            var c = encoder.container(keyedBy: Keys.self)
            try c.encode(schema, forKey: .schema); try c.encode(schema_version, forKey: .schema_version)
            try c.encode(destination_binding, forKey: .destination_binding); try c.encode(request, forKey: .request)
            try c.encode(policy, forKey: .policy); try c.encode(refresh_recent_days, forKey: .refresh_recent_days)
            try c.encode(today_refresh, forKey: .today_refresh); try c.encode(selected, forKey: .selected)
            try c.encode(residual, forKey: .residual); try c.encode(coverage_status, forKey: .coverage_status)
            try c.encode(coverage_response, forKey: .coverage_response)
        }
        enum Keys: String, CodingKey { case schema, schema_version, destination_binding, request, policy,
            refresh_recent_days, today_refresh, selected, residual, coverage_status, coverage_response }
    }
    private var wire: Wire
    var selected: [String] { wire.selected }
    var residual: [String] { wire.residual }
    var candidates: [String] { wire.request.candidates }
    var today: String { wire.request.today }
    var calendarTimezone: String { wire.request.calendar_timezone }
    var destinationBinding: String { wire.destination_binding }
    var status: String { wire.coverage_status }
    private static var invalid: ReceiverCoveragePreflight.BoundaryError { .invalidOccurrence }

    static func select(requestID: String, scopeID: String, zone: String, candidates: [String], today: String,
                       binding: String, refreshRecentDays: Int, todayRefresh: Bool,
                       outcome: ReceiverCoverageOutcome) throws -> Self {
        let request = Request(request_id: requestID, scope_id: scopeID, calendar_timezone: zone, candidates: candidates, today: today)
        let evidence: String?
        let status: String
        switch outcome {
        case .valid(let value): evidence = String(decoding: value.normalizedResponse, as: UTF8.self); status = "valid"
        case .fallbackFull: evidence = nil; status = "fallback_full"
        }
        let selected = try selection(request, refresh: refreshRecentDays, todayRefresh: todayRefresh, evidence: evidence)
        let plan = Self(wire: Wire(schema: "healthmd.receiver_coverage.plan", schema_version: 2,
            destination_binding: binding, request: request, policy: "missing_days", refresh_recent_days: refreshRecentDays,
            today_refresh: todayRefresh, selected: selected, residual: selected, coverage_status: status, coverage_response: evidence))
        try plan.validate()
        return plan
    }

    func json() throws -> String {
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        return String(decoding: try encoder.encode(wire), as: UTF8.self)
    }
    static func restore(_ json: String, binding: String) throws -> Self {
        guard json.utf8.count <= 96 * 1024 else { throw invalid }
        let wire = try JSONDecoder().decode(Wire.self, from: Data(json.utf8))
        let plan = Self(wire: wire)
        // Native journals use canonical JSON. Exact re-encoding rejects duplicate/unknown fields,
        // numeric coercion and missing nulls before any state can be used or rewritten.
        guard try plan.json() == json, wire.destination_binding == binding else { throw invalid }
        try plan.validate()
        return plan
    }
    func acknowledging(_ dates: [String]) throws -> Self {
        guard Set(dates).isSubset(of: Set(selected)) else { throw Self.invalid }
        var copy = self
        copy.wire.residual.removeAll { dates.contains($0) }
        try copy.validate()
        return copy
    }
    private func validate() throws {
        guard wire.schema == "healthmd.receiver_coverage.plan", wire.schema_version == 2,
              wire.destination_binding.range(of: "^[a-f0-9]{64}$", options: .regularExpression) != nil,
              ["full_lookback", "missing_days"].contains(wire.policy),
              (0...30).contains(wire.refresh_recent_days),
              ["not_requested", "valid", "fallback_full"].contains(wire.coverage_status),
              (wire.policy == "full_lookback") == (wire.coverage_status == "not_requested"),
              (wire.coverage_status == "valid") == (wire.coverage_response != nil),
              wire.residual == Array(Set(wire.residual)).sorted(), Set(wire.residual).isSubset(of: Set(wire.selected)),
              wire.selected == (try Self.selection(wire.request, refresh: wire.refresh_recent_days,
                  todayRefresh: wire.today_refresh, evidence: wire.coverage_response)) else { throw Self.invalid }
    }
    private static func selection(_ request: Request, refresh: Int, todayRefresh: Bool, evidence: String?) throws -> [String] {
        for id in [request.request_id, request.scope_id] {
            guard id.range(of: "^[A-Za-z0-9_-]{1,128}$", options: .regularExpression) != nil else { throw invalid }
        }
        guard TimeZone(identifier: request.calendar_timezone) != nil, (0...30).contains(refresh),
              (1...30).contains(request.candidates.count), request.candidates == Array(Set(request.candidates)).sorted() else { throw invalid }
        let today = try civil(request.today)
        let days = try request.candidates.map(civil)
        guard let first = days.first, let last = days.last, last < today,
              utc.dateComponents([.day], from: first, to: last).day! < 30 else { throw invalid }
        let end = label(utc.date(byAdding: .day, value: 1, to: last)!)
        var selected = Set(request.candidates)
        if let evidence {
            let context = ["schema": "healthmd.receiver_coverage.response", "request_id": request.request_id,
                "scope_id": request.scope_id, "calendar_timezone": request.calendar_timezone,
                "start": request.candidates[0], "end_exclusive": end]
            selected.subtract(try ReceiverCoverageEvidence.parse(Data(evidence.utf8), expected: context, today: request.today).completedDates)
        }
        if refresh > 0 {
            let cutoff = utc.date(byAdding: .day, value: 1 - refresh, to: last)!
            selected.formUnion(zip(request.candidates, days).filter { $0.1 >= cutoff }.map(\.0))
        }
        if todayRefresh { selected.insert(request.today) }
        return selected.sorted()
    }
    private static var utc: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(secondsFromGMT: 0)!; return c }
    static func civil(_ text: String) throws -> Date {
        guard text.range(of: "^[0-9]{4}-[0-9]{2}-[0-9]{2}$", options: .regularExpression) != nil else { throw invalid }
        let p = text.split(separator: "-").compactMap { Int($0) }
        guard p.count == 3, p[0] > 0, let date = utc.date(from: DateComponents(year: p[0], month: p[1], day: p[2])), label(date) == text else { throw invalid }
        return date
    }
    static func label(_ date: Date, zone: TimeZone = TimeZone(secondsFromGMT: 0)!) -> String {
        var c = utc; c.timeZone = zone
        let p = c.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", p.year!, p.month!, p.day!)
    }
}
