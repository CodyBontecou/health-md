import Foundation

// MARK: - Health Roll-up Summary Models

/// The roll-up period Health.md summarizes from daily health aggregate
/// snapshots. A single `range` reduction covers exactly the requested export
/// range, first day through last day.
enum HealthRollupPeriod: String, CaseIterable, Codable, Equatable {
    case range

    var displayName: String {
        switch self {
        case .range: return "Range"
        }
    }

    /// Localized UI label. Keep `displayName` and `folderName` stable because they
    /// participate in exported content and destination paths.
    var localizedDisplayName: String {
        switch self {
        case .range: return String(localized: "Range")
        }
    }

    var folderName: String {
        switch self {
        case .range: return "Range"
        }
    }

    func matchesIdentifier(_ identifier: String) -> Bool {
        switch self {
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
}

struct HealthRollupPeriodWindow: Hashable {
    let period: HealthRollupPeriod
    let id: String
    let startDate: Date
    let endDate: Date
    let daysExpected: Int
    let calendarTimeZone: TimeZone

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
    static func dayString(_ date: Date, timeZone: TimeZone = Calendar.current.timeZone) -> String {
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
    /// The range summary window covering the requested export range, first day
    /// through last day. `daysExpected` is the inclusive day span of the range so
    /// coverage reflects the selection instead of a calendar expectation.
    static func rangeWindow(
        from startDate: Date,
        to endDate: Date,
        calendar inputCalendar: Calendar
    ) -> HealthRollupPeriodWindow {
        let calendar = inputCalendar
        let start = calendar.startOfDay(for: startDate)
        let lastDayStart = calendar.startOfDay(for: max(startDate, endDate))
        // Inclusive end-of-day so any timestamp within the last selected day
        // belongs to the window.
        let end = calendar.date(
            byAdding: DateComponents(day: 1, second: -1),
            to: lastDayStart
        ) ?? lastDayStart
        let daySpan = calendar.dateComponents([.day], from: start, to: lastDayStart).day ?? 0
        let id = "\(HealthRollupDateFormatting.dayString(start, timeZone: calendar.timeZone))"
            + "_to_"
            + "\(HealthRollupDateFormatting.dayString(lastDayStart, timeZone: calendar.timeZone))"
        return HealthRollupPeriodWindow(
            period: .range,
            id: id,
            startDate: start,
            endDate: end,
            daysExpected: daySpan + 1,
            calendarTimeZone: calendar.timeZone
        )
    }
}
