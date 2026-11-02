#if os(iOS)
import XCTest
@testable import HealthMd

final class AutomationSentenceTests: XCTestCase {
    private let values: [AutomationSentence.Token: String] = [
        .when: "Daily", .range: "yesterday", .metrics: "5 metrics",
        .where: "Vault", .formats: "CSV", .note: "update my daily note"
    ]

    private let locale = Locale(identifier: "en_US")
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    func testSegmentsKeepTextAndTokensInTemplateOrder() {
        let segments = AutomationSentence.segments(template: "{when} write {range}.", values: values)
        XCTAssertEqual(segments, [.token(.when, "Daily"), .text(" write "), .token(.range, "yesterday"), .text(".")])
    }

    func testUnknownTokenStaysVisible() {
        let segments = AutomationSentence.segments(template: "{bogus} {when}", values: values)
        XCTAssertEqual(segments, [.text("{bogus}"), .text(" "), .token(.when, "Daily")])
    }

    func testWordsKeepTrailingSpaces() {
        XCTAssertEqual(AutomationSentenceView.words("write to "), ["write ", "to "])
    }

    func testOptionalGroupsDropWhenATokenHasNoValue() {
        let template = "{when}, write {range}[’s {metrics}][ as {formats}] to {where}[ and {note}]."
        var partial = values
        partial[.metrics] = nil
        partial[.note] = nil
        XCTAssertEqual(
            AutomationSentence.resolvingOptionalGroups(template, values: partial),
            "{when}, write {range} as {formats} to {where}."
        )
        XCTAssertEqual(
            AutomationSentence.resolvingOptionalGroups(template, values: values),
            "{when}, write {range}’s {metrics} as {formats} to {where} and {note}."
        )
    }

    func testEmphasisSplitsTheValueIntoTextAndChoice() {
        let segments = AutomationSentence.segments(
            template: "{when}, write",
            values: [.when: "Every morning at 7:30"],
            emphasis: [.when: "7:30"]
        )
        XCTAssertEqual(segments, [.text("Every morning at "), .token(.when, "7:30"), .text(", write")])
    }

    func testDayPeriodsFollowTheHour() {
        XCTAssertEqual(AutomationSentence.DayPeriod(hour: 7), .morning)
        XCTAssertEqual(AutomationSentence.DayPeriod(hour: 13), .afternoon)
        XCTAssertEqual(AutomationSentence.DayPeriod(hour: 18), .evening)
        XCTAssertEqual(AutomationSentence.DayPeriod(hour: 23), .night)
        XCTAssertEqual(AutomationSentence.DayPeriod(hour: 2), .night)
    }

    func testClockTimeLeavesOutTheDayPeriod() {
        XCTAssertEqual(AutomationSentence.clockTime(hour: 7, minute: 30, locale: locale, calendar: calendar), "7:30")
        XCTAssertEqual(AutomationSentence.clockTime(hour: 23, minute: 0, locale: locale, calendar: calendar), "11:00")
    }

    // MARK: - Board sentences (AutomationsGlass, ArchiveGlassFeed, ComposeGlass)

    private func settings(
        formats: Set<ExportFormat>,
        metricCount: Int,
        note: Bool
    ) -> ExportSettingsSnapshot {
        var settings = ExportSettingsSnapshot.from(
            AdvancedExportSettings(userDefaults: ExportSettingsSnapshot.makeTemporaryUserDefaults())
        )
        settings.exportFormats = formats
        settings.metricSelection.enabledMetricIDs = Set((0..<metricCount).map { "metric.\($0)" })
        settings.dailyNoteInjection.enabled = note
        return settings
    }

    private func sentence(
        _ settings: ExportSettingsSnapshot,
        entry: ScheduledExportEntry?,
        destination: String,
        sends: Bool = false,
        style: AutomationSentence.Style
    ) -> AutomationSentence {
        .make(
            settings: settings,
            sends: sends,
            entry: entry,
            destination: destination,
            style: style,
            availableMetricCount: 225,
            locale: locale,
            calendar: calendar
        )
    }

    private var dailyEntry: ScheduledExportEntry {
        ScheduledExportEntry(profileID: UUID(), isEnabled: true, frequency: .daily, preferredHour: 7, preferredMinute: 30)
    }

    func testDailySummaryNamesYesterdaysMetricsAndTheNote() {
        let result = sentence(
            settings(formats: [.markdown, .obsidianBases], metricCount: 142, note: true),
            entry: dailyEntry, destination: "Vault/Health", style: .summary
        )
        XCTAssertEqual(result.plainText, "Every morning at 7:30, write yesterday’s 142 metrics to Vault/Health and update my daily note.")
        XCTAssertTrue(result.segments.contains(.token(.when, "7:30")))
    }

    func testComposerNamesEveryChoice() {
        let result = sentence(
            settings(formats: [.markdown, .obsidianBases], metricCount: 142, note: true),
            entry: dailyEntry, destination: "Vault/Health", style: .composer
        )
        let formats = ExportProfileCardSummary.sortedFormats([.markdown, .obsidianBases])
            .map(\.localizedDisplayName).joined(separator: " + ")
        XCTAssertEqual(
            result.plainText,
            "Every morning at 7:30, write yesterday’s 142 metrics to Vault/Health as \(formats), and update my daily note."
        )
        XCTAssertEqual(result.listValues[.when], "Every morning, 7:30")
        XCTAssertEqual(result.listValues[.range], "Yesterday")
        XCTAssertEqual(result.listValues[.note], "Update it")
    }

    func testWeeklySummaryOfEveryMetricLeavesOutTheCountAndNote() {
        let entry = ScheduledExportEntry(
            profileID: UUID(), isEnabled: true, frequency: .weekly,
            preferredHour: 8, preferredMinute: 0, weekday: 7, lookbackDays: 7
        )
        let result = sentence(
            settings(formats: [.csv], metricCount: 225, note: false),
            entry: entry, destination: "Files/Exports", style: .summary
        )
        // Time formats may put a narrow no-break space before AM/PM.
        let plain = result.plainText.replacingOccurrences(of: "\u{202F}", with: " ")
        XCTAssertEqual(plain, "Every Sunday at 8:00 AM, write the last 7 days as CSV to Files/Exports.")
    }

    func testRefreshSummarySendsToday() {
        let entry = ScheduledExportEntry(
            profileID: UUID(), isEnabled: true, frequency: .daily,
            todayRefreshEnabled: true, todayRefreshIntervalHours: 6
        )
        let result = sentence(
            settings(formats: [.json], metricCount: 225, note: false),
            entry: entry, destination: "api.example.com", sends: true, style: .summary
        )
        XCTAssertEqual(result.plainText, "Every 6 hours, send today as JSON to api.example.com.")
        XCTAssertTrue(result.segments.contains(.token(.when, "6 hours")))
    }

    func testMultiDayComposerAvoidsThePossessive() {
        let entry = ScheduledExportEntry(profileID: UUID(), isEnabled: true, preferredHour: 19, lookbackDays: 3)
        let result = sentence(
            settings(formats: [.markdown], metricCount: 10, note: false),
            entry: entry, destination: "Vault", style: .composer
        )
        XCTAssertTrue(result.plainText.hasPrefix("Every evening at 7:00, write 10 metrics for the last 3 days to Vault"))
        XCTAssertTrue(result.plainText.hasSuffix(", and leave daily notes alone."))
        XCTAssertEqual(result.listValues[.range], "The last 3 days")
    }

    // MARK: - Drafts

    func testComposerDraftUnstagesAChoiceToggledBack() {
        let saved = settings(formats: [.markdown], metricCount: 3, note: false)
        var draft = ComposerDraft()
        draft.toggleNote(saved: saved)
        XCTAssertEqual(draft.note, true)
        XCTAssertTrue(draft.settings(from: saved).dailyNoteInjection.enabled)
        draft.toggleNote(saved: saved)
        XCTAssertTrue(draft.isEmpty)
        XCTAssertEqual(draft.settings(from: saved), saved)
    }

    /// A translation that drops a token would silently lose a user's choice.
    func testEveryLocalizedTemplateKeepsEveryToken() throws {
        for locale in ["en", "de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: locale, ofType: "lproj"), locale)
            let bundle = try XCTUnwrap(Bundle(path: path))
            for key in AutomationSentence.allTemplates {
                let template = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
                let resolved = AutomationSentence.resolvingOptionalGroups(template, values: values)
                let tokens = AutomationSentence.segments(template: resolved, values: values).compactMap { segment -> AutomationSentence.Token? in
                    if case .token(let token, _) = segment { return token }
                    return nil
                }
                XCTAssertEqual(Set(tokens), Set(AutomationSentence.Token.allCases), "\(locale): \(key)")
                // The choices every summary names stay outside the optional groups.
                let required = AutomationSentence.resolvingOptionalGroups(template, values: [:])
                for token in [AutomationSentence.Token.when, .range, .where] {
                    XCTAssertTrue(required.contains("{\(token.rawValue)}"), "\(locale): \(key) must keep {\(token.rawValue)}")
                }
            }
        }
    }
}
#endif
