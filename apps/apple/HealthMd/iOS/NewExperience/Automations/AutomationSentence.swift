#if os(iOS)
import SwiftUI

/// The tokens of an automation's sentence. The word order lives in one localized
/// template per language, so choices can sit wherever the grammar needs them.
struct AutomationSentence: Equatable {
    enum Token: String, CaseIterable {
        case when, range, metrics, `where`, formats, note
    }

    let values: [Token: String]

    /// Keep these `{token}` names in every translation of the template.
    static var template: String {
        String(
            localized: "{when}, write {range}: {metrics} to {where} as {formats}, and {note}.",
            comment: "Automation sentence template. Keep every {token}; reorder freely for grammar."
        )
    }

    enum Segment: Equatable {
        case text(String)
        case token(Token, String)
    }

    var segments: [Segment] { Self.segments(template: Self.template, values: values) }

    var plainText: String {
        segments.map {
            switch $0 {
            case .text(let text): return text
            case .token(_, let value): return value
            }
        }.joined()
    }

    /// Splits a template on `{token}`. Unknown names stay as text, so a bad translation
    /// shows up visibly rather than dropping a choice.
    static func segments(template: String, values: [Token: String]) -> [Segment] {
        var result: [Segment] = []
        var rest = Substring(template)
        while let open = rest.firstIndex(of: "{"),
              let close = rest[open...].firstIndex(of: "}") {
            let name = String(rest[rest.index(after: open)..<close])
            guard let token = Token(rawValue: name), let value = values[token] else {
                result.append(.text(String(rest[...close])))
                rest = rest[rest.index(after: close)...]
                continue
            }
            if open > rest.startIndex { result.append(.text(String(rest[..<open]))) }
            result.append(.token(token, value))
            rest = rest[rest.index(after: close)...]
        }
        if !rest.isEmpty { result.append(.text(String(rest))) }
        return result
    }

    static func make(
        profile: ExportProfile,
        entry: ScheduledExportEntry?,
        destination: String
    ) -> AutomationSentence {
        let formats = ExportProfileCardSummary.sortedFormats(profile.settings.exportFormats)
            .map(\.localizedDisplayName)
            .joined(separator: " + ")
        let lookback = entry?.lookbackDays ?? 1
        return AutomationSentence(values: [
            .when: whenText(entry),
            .range: lookback <= 1
                ? String(localized: "yesterday")
                : String(localized: "the last \(lookback) days"),
            .metrics: String(localized: "\(profile.settings.metricSelection.enabledMetricIDs.count) metrics"),
            .where: destination,
            .formats: formats,
            .note: profile.settings.dailyNoteInjection.enabled
                ? String(localized: "update my daily note")
                : String(localized: "leave daily notes alone")
        ])
    }

    private static func whenText(_ entry: ScheduledExportEntry?) -> String {
        guard let entry else { return String(localized: "On demand") }
        let cadence = ExportProfileCadenceSummary.from(entry)
        if let interval = cadence.customInterval, let unit = cadence.customUnit {
            return ScheduleDisplayCopy.cadence(count: interval, unit: unit, at: cadence.timeLabel)
        }
        if let weekday = cadence.weekdayIndex {
            return String(localized: "Every \(ExportProfileCadenceSummary.weekdayName(weekday)) at \(cadence.timeLabel)")
        }
        return String(localized: "Every day at \(cadence.timeLabel)")
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
                        Button { onToken(token) } label: { tokenLabel(value) }
                            .buttonStyle(.plain)
                    } else {
                        tokenLabel(value)
                    }
                }
            }
        }
        .accessibilityElement(children: onToken == nil ? .ignore : .contain)
        .accessibilityLabel(sentence.plainText)
    }

    private func tokenLabel(_ value: String) -> some View {
        Text(value)
            .glassFont(style)
            .foregroundStyle(palette.accent)
            .underline(onToken != nil, color: palette.accent.opacity(0.5))
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
