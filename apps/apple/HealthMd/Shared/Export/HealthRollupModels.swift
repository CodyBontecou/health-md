import Foundation

// MARK: - Health Roll-up Summary Models

/// Roll-up windows understood by Apple. Calendar periods remain decodable for
/// historical v8 artifacts; newly planned summaries use only `range`.
enum HealthRollupPeriod: String, CaseIterable, Codable, Equatable {
    case weekly
    case monthly
    case yearly
    case range

    var displayName: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .range: return "Range"
        }
    }

    var localizedDisplayName: String {
        switch self {
        case .weekly: return String(localized: "Weekly")
        case .monthly: return String(localized: "Monthly")
        case .yearly: return String(localized: "Yearly")
        case .range: return String(localized: "Range")
        }
    }

    var folderName: String {
        switch self {
        case .weekly: return "Weekly"
        case .monthly: return "Monthly"
        case .yearly: return "Yearly"
        case .range: return "Range"
        }
    }

    func matchesIdentifier(_ identifier: String) -> Bool {
        switch self {
        case .weekly:
            return identifier.range(of: #"^\d{4}-W\d{2}$"#, options: .regularExpression) != nil
        case .monthly:
            return identifier.range(of: #"^\d{4}-\d{2}$"#, options: .regularExpression) != nil
        case .yearly:
            return identifier.range(of: #"^\d{4}$"#, options: .regularExpression) != nil
        case .range:
            return identifier.range(
                of: #"^\d{4}-\d{2}-\d{2}_to_\d{4}-\d{2}-\d{2}$"#,
                options: .regularExpression
            ) != nil
        }
    }
}

enum HealthRollupExportSchema {
    static let identifier = "healthmd.rollup_summary"
    static let currentVersion = 9
    static let sourceDailyVersion = 8
    static let rulesVersion = 8
}

/// Immutable authority for a newly requested range summary. Its civil bounds
/// and timezone are chosen before capture and never inferred from successful days.
struct HealthRollupRangeRequest: Equatable, Hashable, Codable {
    /// Bounded cumulative scope (~27 years) while per-batch capture/render limits remain 400 days.
    static let maximumDays = 10_000
    enum ValidationError: LocalizedError, Equatable {
        case invalidTimeZone
        case invalidBounds
        case exceedsDayLimit

        var errorDescription: String? {
            self == .exceedsDayLimit
                ? HealthRollupRangeRequest.dayLimitUnavailableMessage
                : nil
        }
    }

    static let dayLimitUnavailableMessage =
        "Range Summary is unavailable for ranges longer than 10,000 days. Daily files will continue to export without a Range Summary."

    let startDate: Date
    let endDate: Date
    let daysExpected: Int
    let calendarTimeZoneIdentifier: String

    var calendarTimeZone: TimeZone {
        // The initializer proves this identifier is valid.
        TimeZone(identifier: calendarTimeZoneIdentifier)!
    }

    var periodID: String {
        let start = HealthRollupDateFormatting.dayString(startDate, timeZone: calendarTimeZone)
        let end = HealthRollupDateFormatting.dayString(endDate, timeZone: calendarTimeZone)
        return "\(start)_to_\(end)"
    }

    init(
        ownerDateIdentifiers: Set<String>,
        calendarTimeZoneIdentifier: String
    ) throws {
        guard let first = ownerDateIdentifiers.min(), let last = ownerDateIdentifiers.max(),
              let timeZone = TimeZone(identifier: calendarTimeZoneIdentifier) else {
            throw ValidationError.invalidBounds
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        func civilDate(_ value: String) -> Date? {
            let parts = value.split(separator: "-").compactMap { Int($0) }
            guard parts.count == 3 else { return nil }
            return calendar.date(from: DateComponents(
                timeZone: timeZone,
                year: parts[0],
                month: parts[1],
                day: parts[2]
            ))
        }
        guard ownerDateIdentifiers.allSatisfy({ civilDate($0) != nil }),
              let start = civilDate(first), let end = civilDate(last) else {
            throw ValidationError.invalidBounds
        }
        try self.init(
            startDate: start,
            endDate: end,
            calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
        )
    }

    init(startDate: Date, endDate: Date, calendarTimeZoneIdentifier: String) throws {
        guard (calendarTimeZoneIdentifier == "UTC"
                || TimeZone.knownTimeZoneIdentifiers.contains(calendarTimeZoneIdentifier)),
              let timeZone = TimeZone(identifier: calendarTimeZoneIdentifier) else {
            throw ValidationError.invalidTimeZone
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let normalizedStart = calendar.startOfDay(for: startDate)
        let normalizedEnd = calendar.startOfDay(for: endDate)
        guard normalizedStart <= normalizedEnd else { throw ValidationError.invalidBounds }
        let days = (calendar.dateComponents([.day], from: normalizedStart, to: normalizedEnd).day ?? -1) + 1
        guard days > 0 else { throw ValidationError.invalidBounds }
        guard days <= Self.maximumDays else { throw ValidationError.exceedsDayLimit }
        self.startDate = normalizedStart
        self.endDate = normalizedEnd
        self.daysExpected = days
        self.calendarTimeZoneIdentifier = calendarTimeZoneIdentifier
    }
}

struct HealthRollupPeriodWindow: Hashable {
    let period: HealthRollupPeriod
    let id: String
    let startDate: Date
    let endDate: Date
    let daysExpected: Int
    let calendarTimeZone: TimeZone
    /// Preserves the exact captured IANA spelling (`UTC` must not normalize to `GMT`).
    let calendarTimeZoneIdentifier: String

    var title: String { "\(period.displayName) Health Summary — \(id)" }
}

struct HealthRollupStatistic: Equatable {
    let name: String
    let value: String
}

struct HealthRollupMetricSummary: Equatable {
    let key: String
    let canonicalKey: String
    let displayName: String
    let category: String
    let unit: String
    let rule: String
    let primaryValue: String
    let daysCounted: Int
    let statistics: [HealthRollupStatistic]
    let notes: String?
}

/// Aggregated data for a single roll-up period. Exporters render this snapshot
/// into Markdown, Obsidian Bases frontmatter, JSON, or CSV.
struct RollupDataSnapshot: Equatable {
    let window: HealthRollupPeriodWindow
    let generatedAt: Date
    let sourceDates: [Date]
    let metrics: [HealthRollupMetricSummary]

    var period: HealthRollupPeriod { window.period }
    var periodID: String { window.id }
    var daysExpected: Int { window.daysExpected }
    var daysCounted: Int { Set(sourceDates.map(dayString)).count }
    var coveragePercent: Double {
        guard daysExpected > 0 else { return 0 }
        return (Double(daysCounted) / Double(daysExpected)) * 100.0
    }

    var units: [(key: String, unit: String)] {
        metrics
            .filter { !$0.unit.isEmpty }
            .map { (key: $0.key, unit: $0.unit) }
            .sorted { $0.key < $1.key }
    }

    var categoryNames: [String] {
        Array(Set(metrics.map(\.category))).sorted()
    }

    func dayString(_ date: Date) -> String {
        HealthRollupDateFormatting.dayString(date, timeZone: window.calendarTimeZone)
    }

    /// Backward-compatible Markdown convenience used by older call sites/tests.
    func markdown() -> String {
        toRollupMarkdown()
    }
}

/// Backward-compatible name from the first roll-up implementation.
typealias HealthRollupSummary = RollupDataSnapshot

struct HealthRollupWriteResult: Equatable {
    let summary: HealthRollupSummary
    let format: ExportFormat
    let filename: String
    let relativeFolderPath: String
    let relativePath: String
    let content: String
}

enum HealthRollupDateFormatting {
    static func dayString(_ date: Date, timeZone: TimeZone) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    static func timestampString(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }
}

enum HealthRollupFormatting {
    static func numericValue(from rawValue: String) -> Double? {
        var trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.hasSuffix("%") { trimmed.removeLast() }
        trimmed = trimmed.replacingOccurrences(of: ",", with: "")
        return Double(trimmed)
    }

    static func number(_ value: Double) -> String {
        guard value.isFinite else { return "" }
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.2f", value)
    }

    static func listValues(from rawValue: String) -> [String] {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let withoutBrackets: String
        if trimmed.hasPrefix("[") && trimmed.hasSuffix("]") {
            withoutBrackets = String(trimmed.dropFirst().dropLast())
        } else {
            withoutBrackets = trimmed
        }
        return withoutBrackets
            .split(separator: ",")
            .map { item in
                item.trimmingCharacters(in: .whitespacesAndNewlines.union(CharacterSet(charactersIn: "\"'")))
            }
            .filter { !$0.isEmpty }
    }

    static func minutesFromMidnight(from rawValue: String) -> Int? {
        let trimmed = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        let formatters: [DateFormatter] = ["HH:mm", "H:mm", "h:mm a", "hh:mm a"].map { format in
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.dateFormat = format
            return formatter
        }
        for formatter in formatters {
            if let date = formatter.date(from: trimmed) {
                let components = Calendar(identifier: .gregorian).dateComponents([.hour, .minute], from: date)
                return (components.hour ?? 0) * 60 + (components.minute ?? 0)
            }
        }
        return nil
    }

    static func timeString(minutes: Int) -> String {
        let normalized = ((minutes % (24 * 60)) + (24 * 60)) % (24 * 60)
        return String(format: "%02d:%02d", normalized / 60, normalized % 60)
    }

    static func tableEscaped(_ value: String) -> String {
        let normalizedNewlines = value
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var escaped = ""
        escaped.reserveCapacity(normalizedNewlines.count)

        for scalar in normalizedNewlines.unicodeScalars {
            switch scalar.value {
            case 0x0A:
                escaped += "<br>"
            case 0x3C:
                escaped += "&lt;"
            case 0x3E:
                escaped += "&gt;"
            case 0x7C:
                escaped += "\\|"
            case 0x00...0x08, 0x0B...0x0C, 0x0E...0x1F, 0x7F...0x9F, 0x2028, 0x2029:
                escaped += String(format: "\\u%04X", scalar.value)
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }

        return escaped
    }

    static func yamlQuoted(_ value: String) -> String {
        "\"\(yamlDoubleQuotedEscaped(value))\""
    }

    private static func yamlDoubleQuotedEscaped(_ value: String) -> String {
        var escaped = ""
        escaped.reserveCapacity(value.count)

        for scalar in value.unicodeScalars {
            switch scalar.value {
            case 0x22:
                escaped += "\\\""
            case 0x5C:
                escaped += "\\\\"
            case 0x08:
                escaped += "\\b"
            case 0x09:
                escaped += "\\t"
            case 0x0A:
                escaped += "\\n"
            case 0x0C:
                escaped += "\\f"
            case 0x0D:
                escaped += "\\r"
            case 0x00...0x1F, 0x7F...0x9F, 0x2028, 0x2029:
                escaped += String(format: "\\u%04X", scalar.value)
            default:
                escaped.unicodeScalars.append(scalar)
            }
        }

        return escaped
    }
}

extension HealthRollupPeriodWindow {
    static func window(
        containing date: Date,
        period: HealthRollupPeriod,
        calendar inputCalendar: Calendar
    ) -> HealthRollupPeriodWindow {
        switch period {
        case .weekly:
            var calendar = Calendar(identifier: .iso8601)
            calendar.timeZone = inputCalendar.timeZone
            let components = calendar.dateComponents([.yearForWeekOfYear, .weekOfYear], from: date)
            let start = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                weekday: calendar.firstWeekday,
                weekOfYear: components.weekOfYear,
                yearForWeekOfYear: components.yearForWeekOfYear
            )) ?? calendar.startOfDay(for: date)
            let end = calendar.date(byAdding: .day, value: 6, to: start) ?? start
            let id = String(format: "%04d-W%02d", components.yearForWeekOfYear ?? 0, components.weekOfYear ?? 0)
            return HealthRollupPeriodWindow(
                period: period,
                id: id,
                startDate: start,
                endDate: end,
                daysExpected: 7,
                calendarTimeZone: calendar.timeZone,
                calendarTimeZoneIdentifier: calendar.timeZone.identifier
            )
        case .monthly:
            let calendar = inputCalendar
            let components = calendar.dateComponents([.year, .month], from: date)
            let start = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: components.year,
                month: components.month,
                day: 1
            )) ?? calendar.startOfDay(for: date)
            let nextMonth = calendar.date(byAdding: .month, value: 1, to: start) ?? start
            let end = calendar.date(byAdding: .day, value: -1, to: nextMonth) ?? start
            let days = calendar.dateComponents([.day], from: start, to: nextMonth).day ?? 0
            let id = String(format: "%04d-%02d", components.year ?? 0, components.month ?? 0)
            return HealthRollupPeriodWindow(
                period: period,
                id: id,
                startDate: start,
                endDate: end,
                daysExpected: days,
                calendarTimeZone: calendar.timeZone,
                calendarTimeZoneIdentifier: calendar.timeZone.identifier
            )
        case .yearly:
            let calendar = inputCalendar
            let components = calendar.dateComponents([.year], from: date)
            let start = calendar.date(from: DateComponents(
                calendar: calendar,
                timeZone: calendar.timeZone,
                year: components.year,
                month: 1,
                day: 1
            )) ?? calendar.startOfDay(for: date)
            let nextYear = calendar.date(byAdding: .year, value: 1, to: start) ?? start
            let end = calendar.date(byAdding: .day, value: -1, to: nextYear) ?? start
            let days = calendar.dateComponents([.day], from: start, to: nextYear).day ?? 0
            let id = String(format: "%04d", components.year ?? 0)
            return HealthRollupPeriodWindow(
                period: period,
                id: id,
                startDate: start,
                endDate: end,
                daysExpected: days,
                calendarTimeZone: calendar.timeZone,
                calendarTimeZoneIdentifier: calendar.timeZone.identifier
            )
        case .range:
            preconditionFailure("Range windows require an explicit HealthRollupRangeRequest")
        }
    }

    static func range(_ request: HealthRollupRangeRequest) -> HealthRollupPeriodWindow {
        HealthRollupPeriodWindow(
            period: .range,
            id: request.periodID,
            startDate: request.startDate,
            endDate: request.endDate,
            daysExpected: request.daysExpected,
            calendarTimeZone: request.calendarTimeZone,
            calendarTimeZoneIdentifier: request.calendarTimeZoneIdentifier
        )
    }
}
