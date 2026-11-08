#if os(iOS)
import Foundation

/// One headline value from a day file's frontmatter, as the Archive day card shows it.
struct ArchiveDayTile: Identifiable, Equatable {
    let key: String
    let label: String
    let value: String
    let unit: String

    var id: String { key }
}

/// Picks the day card's headline values from a Markdown file's frontmatter. Only what
/// the file says is shown: no value is computed, estimated, or filled in.
enum ArchiveDayTiles {
    /// Sleep, steps, heart, HRV, energy and mindfulness lead, as on the board; other
    /// numeric fields fill any remaining places in file order.
    static let preferredKeys = [
        "steps", "sleep_total_hours", "resting_heart_rate", "hrv_ms", "active_calories", "mindful_minutes",
    ]

    static func tiles(fromMarkdown source: String, limit: Int = 6) -> [ArchiveDayTile] {
        let fields = frontmatterScalars(source)
        guard !fields.isEmpty else { return [] }
        var picked: [(key: String, value: String)] = []
        var used = Set<String>()
        for preferred in preferredKeys {
            if let field = fields.first(where: { canonicalKey($0.key) == preferred && isNumeric($0.value) }) {
                picked.append(field)
                used.insert(field.key)
            }
        }
        for field in fields where !used.contains(field.key) && isNumeric(field.value) && isKnownMetric(field.key) {
            picked.append(field)
            used.insert(field.key)
        }
        return picked.prefix(limit).map { tile(key: $0.key, value: $0.value) }
    }

    /// Top-level `key: value` pairs between the opening and closing `---`.
    static func frontmatterScalars(_ source: String) -> [(key: String, value: String)] {
        let lines = source.split(separator: "\n", omittingEmptySubsequences: false)
        guard lines.first?.trimmingCharacters(in: .whitespacesAndNewlines) == "---" else { return [] }
        var result: [(String, String)] = []
        for line in lines.dropFirst() {
            let text = String(line).trimmingCharacters(in: CharacterSet(charactersIn: "\r"))
            if text.trimmingCharacters(in: .whitespaces) == "---" { return result }
            guard let first = text.first, !first.isWhitespace, first != "#", first != "-",
                  let colon = text.firstIndex(of: ":") else { continue }
            let key = text[..<colon].trimmingCharacters(in: .whitespaces)
            var value = text[text.index(after: colon)...].trimmingCharacters(in: .whitespaces)
            if value.count >= 2, let quote = value.first, quote == "\"" || quote == "'", value.last == quote {
                value = String(value.dropFirst().dropLast())
            }
            guard !key.isEmpty, !value.isEmpty else { continue }
            result.append((key, value))
        }
        // No closing fence: not frontmatter.
        return []
    }

    static func tile(key: String, value: String) -> ArchiveDayTile {
        let canonical = canonicalKey(key)
        let metric = metric(for: canonical)
        let label = metric?.localizedDisplayName ?? key
        let rawUnit = HealthMetricDataDictionary.unit(for: canonical, converter: UnitConverter(preference: .metric)) ?? ""
        let number = Double(value)
        if canonical.hasSuffix("_hours"), canonical != "stand_hours", let hours = number {
            let minutes = Int((hours * 60).rounded())
            return ArchiveDayTile(key: key, label: label, value: "\(minutes / 60)h \(minutes % 60)m", unit: "")
        }
        let formatted: String
        if let number, number.rounded() == number, abs(number) < 1e12 {
            formatted = Int(number).formatted(.number.grouping(.automatic))
        } else {
            formatted = value
        }
        return ArchiveDayTile(key: key, label: label, value: formatted, unit: displayUnit(rawUnit))
    }

    /// `restingHeartRate` and `Resting Heart Rate` style keys map back to snake case.
    static func canonicalKey(_ key: String) -> String {
        if HealthMetricExportMapping.allKnownFrontmatterKeys.contains(key) { return key }
        var result = ""
        for character in key {
            if character == " " || character == "-" {
                result.append("_")
            } else if character.isUppercase {
                if let last = result.last, last != "_" { result.append("_") }
                result.append(contentsOf: character.lowercased())
            } else {
                result.append(character)
            }
        }
        return result
    }

    private static func isKnownMetric(_ key: String) -> Bool {
        HealthMetricExportMapping.allKnownFrontmatterKeys.contains(canonicalKey(key))
    }

    private static func isNumeric(_ value: String) -> Bool {
        Double(value) != nil
    }

    private static func metric(for canonicalKey: String) -> HealthMetricDefinition? {
        guard let id = HealthMetricExportMapping.metricIdToFrontmatterKeys
            .first(where: { $0.value.contains(canonicalKey) })?.key else { return nil }
        return HealthMetrics.all.first { $0.id == id }
    }

    private static func displayUnit(_ unit: String) -> String {
        switch unit {
        case "count", "boolean", "uuid", "datetime", "": return ""
        case "percent": return "%"
        default: return unit
        }
    }
}

/// The Archive's "Next run" line.
enum ArchiveNextRun {
    /// "tomorrow at 7:30", "today at 18:00" or "Sun 8:00".
    static func whenText(_ date: Date, now: Date, calendar: Calendar) -> String {
        let time = date.formatted(.dateTime.hour().minute())
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "today at \(time)") }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now), calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "tomorrow at \(time)")
        }
        return date.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().hour().minute())
    }
}

extension ArchiveModel {
    /// The earliest scheduled run among running automations, or the filtered automation's
    /// own next run, so the card agrees with the gaps beside it.
    func nextRun(filter: UUID? = nil) -> (profile: ArchiveProfile, date: Date)? {
        profiles.filter { filter == nil || $0.id == filter }.compactMap { profile -> (ArchiveProfile, Date)? in
            guard let entry = profile.entry, entry.isEnabled,
                  let date = ScheduleDateMath.nextAnyRunDate(
                    schedule: entry.dateMathProjection, now: now, calendar: calendar
                  ) else { return nil }
            return (profile, date)
        }
        .min { $0.1 < $1.1 }
    }

    /// The seven days of the week that holds `date`, in the calendar's own week order.
    func week(containing date: Date) -> [Date] {
        guard let start = calendar.dateInterval(of: .weekOfYear, for: date)?.start else { return [] }
        return (0..<7).compactMap { calendar.date(byAdding: .day, value: $0, to: start) }
    }

    /// The automation the day card and day page lead with: the filtered one, else the
    /// first running one, else the first.
    func leadProfile(filter: UUID?) -> ArchiveProfile? {
        if let filter, let profile = profiles.first(where: { $0.id == filter }) { return profile }
        return profiles.first { !$0.isPaused } ?? profiles.first
    }
}
#endif
