import XCTest
@testable import HealthMd

nonisolated final class IndividualTrackingPresentationTests: XCTestCase {
    private let languages = ["en", "de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"]

    private func resources(_ language: String) throws -> Bundle {
        let path = [Bundle.main, Bundle(for: Self.self)].compactMap { $0.path(forResource: language, ofType: "lproj") }.first
        return try XCTUnwrap(path.flatMap(Bundle.init(path:)), "Missing production resources: \(language)")
    }

    private func localized(_ key: String, bundle: Bundle, arguments: [CVarArg] = []) -> String {
        let format = bundle.localizedString(forKey: key, value: nil, table: nil)
        return arguments.isEmpty ? format : String(format: format, arguments: arguments)
    }

    func testHeaderStatesAndCountsZeroOneTwoSeveral() throws {
        for language in languages {
            let bundle = try resources(language)
            let copy = IndividualTrackingPresentation(bundle: bundle, locale: Locale(identifier: language))
            for enabled in [false, true] {
                for count in [0, 1, 2, 7] {
                    let state = enabled ? (count == 0 ? localized("Needs Metrics", bundle: bundle) : localized("%lld Tracked", bundle: bundle, arguments: [count])) : localized("Disabled", bundle: bundle)
                    XCTAssertEqual(copy.headerState(isEnabled: enabled, count: count), state)
                    XCTAssertEqual(copy.headerLabel(state), localized("Individual Entry Tracking, %@", bundle: bundle, arguments: [state]))
                    XCTAssertEqual(copy.trackedTitle(count), localized("%lld Tracked", bundle: bundle, arguments: [count]))
                }
            }
        }
    }

    func testBulkSubtitleAndEmptySelectionGuardPrecedence() throws {
        for language in languages {
            let bundle = try resources(language)
            let copy = IndividualTrackingPresentation(bundle: bundle, locale: Locale(identifier: language))
            for all in [false, true] {
                XCTAssertEqual(copy.bulkSubtitle(total: 0, tracked: 0, tracksAll: all), localized("Enable metrics in Health Metrics before choosing individual entries.", bundle: bundle))
                XCTAssertEqual(copy.bulkHint(hasMetrics: false, tracksAll: all), localized("Enable metrics in Health Metrics first.", bundle: bundle))
            }
            for total in [1, 2, 7] {
                XCTAssertEqual(copy.bulkSubtitle(total: total, tracked: 0, tracksAll: false), localized("Metrics currently enabled in Health Metrics: %lld.", bundle: bundle, arguments: [total]))
                XCTAssertEqual(copy.bulkSubtitle(total: total, tracked: total, tracksAll: true), localized("Switch off to disable individual tracking for all enabled Health Metrics.", bundle: bundle))
                XCTAssertEqual(copy.bulkSubtitle(total: total, tracked: 1, tracksAll: false), copy.trackedSummary(tracked: 1, total: total))
            }
        }
    }

    func testWholeActionHintsValuesAndExpansionInBothStates() throws {
        for language in languages {
            let bundle = try resources(language)
            let copy = IndividualTrackingPresentation(bundle: bundle, locale: Locale(identifier: language))
            if language == "pt-BR" {
                // One metric: retain singular agreement, not the category's plural status.
                XCTAssertEqual(copy.metricValue(isTracked: true), "Monitorada")
                XCTAssertEqual(copy.metricValue(isTracked: false), "Não monitorada")
            }
            for value in [false, true] {
                let comparisons = [
                    (copy.status(isEnabled: value), value ? "Enabled" : "Disabled"),
                    (copy.toggleHint(isEnabled: value), value ? "Double tap to disable individual entry tracking" : "Double tap to enable individual entry tracking"),
                    (copy.bulkHint(hasMetrics: true, tracksAll: value), value ? "Double tap to disable all individual tracking." : "Double tap to track all enabled metrics individually."),
                    (copy.bulkValue(tracksAll: value), value ? "All tracked" : "Not all tracked"),
                    (copy.metricValue(isTracked: value), value ? "Tracked" : "Not tracked"),
                    (copy.expansionHint(isExpanded: value), value ? "Double tap to collapse this category" : "Double tap to expand this category")
                ]
                for (actual, key) in comparisons {
                    XCTAssertEqual(actual, localized(key, bundle: bundle))
                    if language != "en" { XCTAssertNotEqual(actual, key, "\(language): \(key)") }
                }
            }
        }
    }

    func testDisplayNameArgumentsStayVerbatimAndAreNeverRelocalizedOrFormatted() throws {
        for language in languages {
            let bundle = try resources(language)
            let copy = IndividualTrackingPresentation(bundle: bundle, locale: Locale(identifier: language))
            for name in ["Enabled", "Schlaf", "健康", "e\u{301}", "**name**/%@/%lld/{metric}\nraw", "  label  "] {
                let label = copy.categoryLabel(name, tracked: 1, total: 7)
                XCTAssertEqual(Array(label.utf8), Array(localized("%@, tracked: %lld of %lld", bundle: bundle, arguments: [name, 1, 7]).utf8))
                for tracked in [false, true] {
                    let key = tracked ? "Double tap to stop tracking individual entry files for %@" : "Double tap to track individual entry files for %@"
                    let hint = copy.metricHint(isTracked: tracked, displayName: name)
                    XCTAssertEqual(Array(hint.utf8), Array(localized(key, bundle: bundle, arguments: [name]).utf8))
                    XCTAssertTrue(hint.contains(name))
                }
            }
        }
    }

    func testLabelStyleCountGrammarAndArgumentOrder() throws {
        let expected = [
            "en": "Tracked: 1 of 7", "de": "Erfasst: 1 von 7", "es": "Registro: 1 de 7",
            "fr": "Suivi : 1 sur 7", "it": "Monitoraggio: 1 su 7", "ja": "追跡中：1／7",
            "ko": "추적: 1 / 7", "nl": "Bijgehouden: 1 van 7", "pt-BR": "Monitoramento: 1 de 7",
            "zh-Hans": "已跟踪：1，共 7"
        ]
        for language in languages {
            let bundle = try resources(language)
            let copy = IndividualTrackingPresentation(bundle: bundle, locale: Locale(identifier: language))
            XCTAssertEqual(copy.trackedSummary(tracked: 1, total: 7), try XCTUnwrap(expected[language]))
            for total in [0, 1, 2, 7] {
                for tracked in [0, 1, 2, 7] {
                    XCTAssertEqual(copy.trackedSummary(tracked: tracked, total: total), localized("Tracked: %lld of %lld", bundle: bundle, arguments: [tracked, total]))
                }
            }
        }
    }

    func testCompiledStaticAccessibilityAndAggregationCopyExistsInEveryTargetLanguage() throws {
        let keys = [
            "Daily: sum", "Daily: average", "Daily: minimum", "Daily: maximum", "Daily: latest", "Daily: total time", "Daily: count",
            "Suggested", "Disables individual tracking for every metric.", "Enter the folder path for individual entry files.",
            "Enter the filename template for individual entry files.", "Enable individual entry tracking", "Entries folder",
            "Filename template", "Example individual entry frontmatter", "Organize individual entries by category", "Track all enabled metrics"
        ]
        for language in languages where language != "en" {
            let bundle = try resources(language)
            for key in keys {
                let value = localized(key, bundle: bundle)
                XCTAssertFalse(value.isEmpty)
                XCTAssertNotEqual(value, key, "\(language): \(key)")
            }
        }
    }
}
