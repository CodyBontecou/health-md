#if os(iOS)
import SwiftUI

/// The tokens of an automation's sentence. The word order lives in one localized
/// template per language, so choices can sit wherever the grammar needs them.
struct AutomationSentence: Equatable {
    enum Token: String, CaseIterable {
        case when, range, metrics, `where`, formats, note
    }

    /// The composer names every choice so each can be edited; the summary on cards
    /// leaves out what the boards leave out (all metrics, note formats, an untouched note).
    enum Style: Equatable { case composer, summary }

    let values: [Token: String]
    var template: String = AutomationSentence.composerTemplate(multiDay: false)
    /// The part of a value shown as the choice, the rest reading as plain text:
    /// "Every morning at" + "7:30".
    var emphasis: [Token: String] = [:]
    /// Values for the list layout at accessibility sizes ("Every morning, 7:30", "Yesterday").
    var listValues: [Token: String] = [:]

    /// The editable sentence. Keep every `{token}` in each translation.
    static func composerTemplate(multiDay: Bool) -> String {
        multiDay
            ? String(
                localized: "{when}, write {metrics} for {range} to {where} as {formats}, and {note}.",
                comment: "Automation composer sentence for a range of several days. Keep every {token}; reorder freely for grammar."
            )
            : String(
                localized: "{when}, write {range}’s {metrics} to {where} as {formats}, and {note}.",
                comment: "Automation composer sentence for one day ({range} is yesterday or today). Keep every {token}; reorder freely for grammar."
            )
    }

    /// The read-only sentence of cards. Text in `[brackets]` is left out, brackets and all,
    /// when a token inside it has no value; keep the brackets around the same tokens.
    static func summaryTemplate(multiDay: Bool, sends: Bool) -> String {
        switch (multiDay, sends) {
        case (false, false):
            return String(
                localized: "{when}, write {range}[’s {metrics}][ as {formats}] to {where}[ and {note}].",
                comment: "Automation summary for one day. Keep every {token}; [brackets] mark optional parts and must stay around the same tokens."
            )
        case (true, false):
            return String(
                localized: "{when}, write[ {metrics} for] {range}[ as {formats}] to {where}[ and {note}].",
                comment: "Automation summary for several days. Keep every {token}; [brackets] mark optional parts and must stay around the same tokens."
            )
        case (false, true):
            return String(
                localized: "{when}, send {range}[’s {metrics}][ as {formats}] to {where}[ and {note}].",
                comment: "Automation summary for one day sent to an endpoint. Keep every {token}; [brackets] mark optional parts and must stay around the same tokens."
            )
        case (true, true):
            return String(
                localized: "{when}, send[ {metrics} for] {range}[ as {formats}] to {where}[ and {note}].",
                comment: "Automation summary for several days sent to an endpoint. Keep every {token}; [brackets] mark optional parts and must stay around the same tokens."
            )
        }
    }

    /// Every template, for translation checks.
    static var allTemplates: [String] {
        [composerTemplate(multiDay: false), composerTemplate(multiDay: true)]
            + [false, true].flatMap { multiDay in
                [false, true].map { summaryTemplate(multiDay: multiDay, sends: $0) }
            }
    }

    enum Segment: Equatable {
        case text(String)
        case token(Token, String)
    }

    var segments: [Segment] { Self.segments(template: template, values: values, emphasis: emphasis) }

    var plainText: String {
        segments.map {
            switch $0 {
            case .text(let text): return text
            case .token(_, let value): return value
            }
        }.joined()
    }

    /// Splits a template on `{token}`. Unknown names stay as text, so a bad translation
    /// shows up visibly rather than dropping a choice. Optional `[groups]` resolve first.
    static func segments(
        template: String,
        values: [Token: String],
        emphasis: [Token: String] = [:]
    ) -> [Segment] {
        var result: [Segment] = []
        var rest = Substring(resolvingOptionalGroups(template, values: values))
        while let open = rest.firstIndex(of: "{"),
              let close = rest[open...].firstIndex(of: "}") {
            let name = String(rest[rest.index(after: open)..<close])
            guard let token = Token(rawValue: name), let value = values[token] else {
                result.append(.text(String(rest[...close])))
                rest = rest[rest.index(after: close)...]
                continue
            }
            if open > rest.startIndex { result.append(.text(String(rest[..<open]))) }
            if let part = emphasis[token], !part.isEmpty, part != value, let range = value.range(of: part) {
                if range.lowerBound > value.startIndex { result.append(.text(String(value[..<range.lowerBound]))) }
                result.append(.token(token, part))
                if range.upperBound < value.endIndex { result.append(.text(String(value[range.upperBound...]))) }
            } else {
                result.append(.token(token, value))
            }
            rest = rest[rest.index(after: close)...]
        }
        if !rest.isEmpty { result.append(.text(String(rest))) }
        return result
    }

    /// Keeps a `[group]` without its brackets when every known token inside has a value,
    /// and drops it otherwise. Unknown names never drop a group, so typos stay visible.
    static func resolvingOptionalGroups(_ template: String, values: [Token: String]) -> String {
        var result = ""
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "["),
              let close = rest[open...].firstIndex(of: "]") {
            result += rest[..<open]
            let inner = rest[rest.index(after: open)..<close]
            if groupTokens(inner).allSatisfy({ values[$0] != nil }) { result += inner }
            rest = rest[rest.index(after: close)...]
        }
        return result + rest
    }

    private static func groupTokens(_ text: Substring) -> [Token] {
        var tokens: [Token] = []
        var rest = text
        while let open = rest.firstIndex(of: "{"), let close = rest[open...].firstIndex(of: "}") {
            if let token = Token(rawValue: String(rest[rest.index(after: open)..<close])) { tokens.append(token) }
            rest = rest[rest.index(after: close)...]
        }
        return tokens
    }

    /// Metrics the current build can export, so a profile with all of them reads "write yesterday".
    static var availableMetricCount: Int {
        HealthMetrics.availableInCurrentBuild
            .filter { !$0.isPendingAppleApproval && $0.availability.isAvailableOnCurrentPlatform }
            .count
    }

    static func make(
        profile: ExportProfile,
        entry: ScheduledExportEntry?,
        destination: String,
        style: Style = .summary,
        availableMetricCount: Int = AutomationSentence.availableMetricCount,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> AutomationSentence {
        make(
            settings: profile.settings,
            sends: profile.target == .apiEndpoint || profile.target == .agentDataGateway,
            entry: entry,
            destination: destination,
            style: style,
            availableMetricCount: availableMetricCount,
            locale: locale,
            calendar: calendar
        )
    }

    static func make(
        settings: ExportSettingsSnapshot,
        sends: Bool,
        entry: ScheduledExportEntry?,
        destination: String,
        style: Style,
        availableMetricCount: Int,
        locale: Locale = .current,
        calendar: Calendar = .current
    ) -> AutomationSentence {
        let sortedFormats = ExportProfileCardSummary.sortedFormats(settings.exportFormats)
        // "Markdown + Bases" (AutomationsGlass): Bases is the Obsidian product name, as in the
        // Automations list; the other formats keep their localized names.
        let formats = sortedFormats.map { $0 == .obsidianBases ? "Bases" : $0.localizedDisplayName }
            .joined(separator: " + ")
        let metricCount = settings.metricSelection.enabledMetricIDs.count
        let metrics = String(localized: "\(metricCount) metrics")
        let noteEnabled = settings.dailyNoteInjection.enabled
        let when = When.make(entry, style: style, locale: locale, calendar: calendar)
        let range = DateRange.make(entry, style: style)

        var values: [Token: String] = [.when: when.text, .range: range.text, .where: destination]
        var template: String
        switch style {
        case .composer:
            values[.metrics] = metrics
            values[.formats] = formats
            values[.note] = noteEnabled
                ? String(localized: "update my daily note")
                : String(localized: "leave daily notes alone")
            template = composerTemplate(multiDay: range.isMultiDay)
        case .summary:
            // "write the last 7 days" already means every metric.
            if metricCount < availableMetricCount { values[.metrics] = metrics }
            // Notes are the default; other formats are named.
            let notesOnly = sortedFormats.contains(.markdown)
                && sortedFormats.allSatisfy { $0 == .markdown || $0 == .obsidianBases }
            if !notesOnly, !formats.isEmpty { values[.formats] = formats }
            if noteEnabled { values[.note] = String(localized: "update my daily note") }
            template = summaryTemplate(multiDay: range.isMultiDay, sends: sends)
        }

        var listValues = values
        listValues[.when] = when.listText
        listValues[.range] = range.listText
        listValues[.note] = noteEnabled ? String(localized: "Update it") : String(localized: "Leave it alone")
        listValues[.metrics] = metrics
        listValues[.formats] = formats

        return AutomationSentence(
            values: values,
            template: template,
            emphasis: when.emphasis.map { [.when: $0] } ?? [:],
            listValues: listValues
        )
    }

    // MARK: - When

    /// The time of day a daily run names: "Every morning at 7:30".
    enum DayPeriod: Equatable {
        case morning, afternoon, evening, night

        init(hour: Int) {
            switch hour {
            case 5..<12: self = .morning
            case 12..<17: self = .afternoon
            case 17..<21: self = .evening
            default: self = .night
            }
        }
    }

    struct When: Equatable {
        let text: String
        let emphasis: String?
        let listText: String

        static func make(_ entry: ScheduledExportEntry?, style: Style, locale: Locale, calendar: Calendar) -> When {
            let when = scheduled(entry, style: style, locale: locale, calendar: calendar)
            // A paused card keeps its cadence but must not read as if it still runs.
            guard style == .summary, let entry, !entry.isEnabled else { return when }
            let paused = String(localized: "Paused")
            return When(
                text: String(localized: "Paused · \(when.text)"),
                emphasis: paused,
                listText: String(localized: "Paused · \(when.listText)")
            )
        }

        private static func scheduled(
            _ entry: ScheduledExportEntry?,
            style: Style,
            locale: Locale,
            calendar: Calendar
        ) -> When {
            guard let entry else {
                let text = String(localized: "On demand")
                return When(text: text, emphasis: nil, listText: text)
            }
            // A Today Refresh card leads with its refresh cadence: "Every 2 hours, send today".
            if style == .summary, entry.todayRefreshEnabled {
                let text = ExportSchedule.todayRefreshLabel(entry.todayRefreshMinutes)
                let emphasis = text.firstIndex(where: \.isNumber).map { String(text[$0...]) }
                return When(text: text, emphasis: emphasis, listText: text)
            }
            let cadence = ExportProfileCadenceSummary.from(entry, locale: locale, calendar: calendar)
            if let interval = cadence.customInterval, let unit = cadence.customUnit {
                let text = ScheduleDisplayCopy.cadence(count: interval, unit: unit, at: cadence.timeLabel)
                return When(text: text, emphasis: cadence.timeLabel, listText: text)
            }
            if let weekday = cadence.weekdayIndex {
                let name = ExportProfileCadenceSummary.weekdayName(weekday, locale: locale)
                let text = String(localized: "Every \(name) at \(cadence.timeLabel)")
                return When(text: text, emphasis: name, listText: text)
            }
            let clock = AutomationSentence.clockTime(
                hour: entry.preferredHour, minute: entry.preferredMinute, locale: locale, calendar: calendar
            )
            let text: String
            let listText: String
            switch DayPeriod(hour: entry.preferredHour) {
            case .morning:
                text = String(localized: "Every morning at \(clock)")
                listText = String(localized: "Every morning, \(clock)")
            case .afternoon:
                text = String(localized: "Every afternoon at \(clock)")
                listText = String(localized: "Every afternoon, \(clock)")
            case .evening:
                text = String(localized: "Every evening at \(clock)")
                listText = String(localized: "Every evening, \(clock)")
            case .night:
                text = String(localized: "Every night at \(clock)")
                listText = String(localized: "Every night, \(clock)")
            }
            return When(text: text, emphasis: clock, listText: listText)
        }
    }

    /// "7:30" without AM/PM: the period word ("morning", "night") already says which.
    /// 24-hour locales keep their own digits.
    static func clockTime(hour: Int, minute: Int, locale: Locale = .current, calendar: Calendar = .current) -> String {
        let date = calendar.date(
            bySettingHour: max(0, min(23, hour)),
            minute: max(0, min(59, minute)),
            second: 0,
            of: Date()
        ) ?? Date()
        // The locale's own hour pattern ("h:mm a", "HH:mm", "a h:mm"), minus the AM/PM field.
        // `.defaultDigits(amPM: .omitted)` switches some platforms to a 24-hour clock instead.
        let pattern = DateFormatter.dateFormat(fromTemplate: "jmm", options: 0, locale: locale) ?? "HH:mm"
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.calendar = calendar
        formatter.timeZone = calendar.timeZone
        formatter.dateFormat = pattern
            .replacingOccurrences(of: "a", with: "")
            .trimmingCharacters(in: .whitespaces.union(CharacterSet(charactersIn: "\u{202F}\u{00A0}")))
        return formatter.string(from: date)
    }

    // MARK: - Range

    struct DateRange: Equatable {
        let text: String
        let listText: String
        let isMultiDay: Bool

        static func make(_ entry: ScheduledExportEntry?, style: Style) -> DateRange {
            // Include Today adds today to the look-back days.
            let lookback = (entry?.lookbackDays ?? 1) + (entry?.includeToday == true ? 1 : 0)
            if style == .summary && entry?.todayRefreshEnabled == true {
                return DateRange(text: String(localized: "today"), listText: String(localized: "Today"), isMultiDay: false)
            }
            if lookback <= 1 {
                return DateRange(text: String(localized: "yesterday"), listText: String(localized: "Yesterday"), isMultiDay: false)
            }
            let text = String(localized: "the last \(lookback) days")
            return DateRange(text: text, listText: text.prefix(1).uppercased() + text.dropFirst(), isMultiDay: true)
        }
    }
}

/// Wraps its children like text, line by line.
struct SentenceFlowLayout: Layout {
    var lineSpacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let lines = lines(width: proposal.width ?? .infinity, subviews: subviews)
        let height = lines.reduce(0) { $0 + $1.height } + lineSpacing * CGFloat(max(lines.count - 1, 0))
        return CGSize(width: lines.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in lines(width: bounds.width, subviews: subviews) {
            var x = bounds.minX
            for index in line.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(
                    at: CGPoint(x: x, y: y + (line.height - size.height) / 2),
                    proposal: ProposedViewSize(size)
                )
                x += size.width
            }
            y += line.height + lineSpacing
        }
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func lines(width: CGFloat, subviews: Subviews) -> [Line] {
        var lines: [Line] = [Line()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if lines[lines.count - 1].width + size.width > width, !lines[lines.count - 1].indices.isEmpty {
                lines.append(Line())
            }
            lines[lines.count - 1].indices.append(index)
            lines[lines.count - 1].width += size.width
            lines[lines.count - 1].height = max(lines[lines.count - 1].height, size.height)
        }
        return lines
    }
}

/// The sentence with its choices as buttons. Accessibility sizes use the list layout.
struct AutomationSentenceView: View {
    let sentence: AutomationSentence
    var style: GlassTextStyle = .sentence
    var onToken: ((AutomationSentence.Token) -> Void)?

    @Environment(\.glassPalette) private var palette

    var body: some View {
        SentenceFlowLayout {
            ForEach(Array(sentence.segments.enumerated()), id: \.offset) { _, segment in
                switch segment {
                case .text(let text):
                    ForEach(Array(Self.words(text).enumerated()), id: \.offset) { _, word in
                        Text(verbatim: word).glassFont(style).foregroundStyle(palette.sec)
                    }
                case .token(let token, let value):
                    if let onToken {
                        Button { onToken(token) } label: { tokenPill(token, value) }
                            .buttonStyle(.plain)
                    } else {
                        tokenLabel(token, value)
                    }
                }
            }
        }
        .accessibilityElement(children: onToken == nil ? .ignore : .contain)
        .accessibilityLabel(sentence.plainText)
    }

    /// Paths and hosts read as code, as on the boards.
    static func isPathLike(_ token: AutomationSentence.Token, _ value: String) -> Bool {
        token == .where && (value.contains("/") || value.contains("."))
    }

    @ViewBuilder private func tokenText(_ token: AutomationSentence.Token, _ value: String) -> some View {
        if Self.isPathLike(token, value) {
            Text(verbatim: value)
                .fontDesign(.monospaced)
                .fontWeight(.medium)
                .glassFont(style)
        } else {
            Text(value).fontWeight(.semibold).glassFont(style)
        }
    }

    /// Read-only sentences emphasise their choices in the primary text colour.
    private func tokenLabel(_ token: AutomationSentence.Token, _ value: String) -> some View {
        tokenText(token, value).foregroundStyle(palette.text)
    }

    /// Editable choices are tinted pills.
    private func tokenPill(_ token: AutomationSentence.Token, _ value: String) -> some View {
        tokenText(token, value)
            .foregroundStyle(palette.text)
            .padding(.horizontal, 12)
            .padding(.vertical, 2)
            .background(Capsule().fill(palette.tint))
            .overlay(Capsule().strokeBorder(palette.edge, lineWidth: 1))
            .contentShape(Capsule())
    }

    /// Keeps trailing spaces so wrapped words read naturally.
    static func words(_ text: String) -> [String] {
        var words: [String] = []
        var current = ""
        for character in text {
            current.append(character)
            if character == " " {
                words.append(current)
                current = ""
            }
        }
        if !current.isEmpty { words.append(current) }
        return words
    }
}
#endif
