import Foundation
import XCTest
@testable import HealthMd

nonisolated final class ScheduleDisplayCopyTests: XCTestCase {
    private let languages = ["en", "de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"]

    private func bundle(_ language: String) throws -> Bundle {
        let path = [Bundle.main, Bundle(for: Self.self)].compactMap { $0.path(forResource: language, ofType: "lproj") }.first
        return try XCTUnwrap(path.flatMap(Bundle.init(path:)), "Missing compiled locale: \(language)")
    }

    private func key(_ unit: ScheduleIntervalUnit, count: Int, suffix: String = "") -> String {
        switch unit {
        case .day: return (count == 1 ? "Every day" : "Every %lld days") + suffix
        case .week: return (count == 1 ? "Every week" : "Every %lld weeks") + suffix
        case .month: return (count == 1 ? "Every month" : "Every %lld months") + suffix
        }
    }

    private func expected(_ key: String, bundle: Bundle, args: [CVarArg]) -> String {
        String(format: bundle.localizedString(forKey: key, value: nil, table: nil), arguments: args)
    }

    func testCadencesUseCompleteUnitSpecificSingularAndPluralSentences() throws {
        for language in languages {
            let resource = try bundle(language)
            for unit in ScheduleIntervalUnit.allCases {
                for count in [1, 2, 7, 365] {
                    let actual = ScheduleDisplayCopy.cadence(count: count, unit: unit, bundle: resource, locale: Locale(identifier: language))
                    XCTAssertEqual(actual, expected(key(unit, count: count), bundle: resource, args: count == 1 ? [] : [count]))
                    if language != "en" { XCTAssertNotEqual(actual, key(unit, count: count)) }
                }
            }
        }
    }

    func testFormattedTimesAndDatesAreInterpolatedWithoutReformattingOrRelocalization() throws {
        for language in languages {
            let resource = try bundle(language)
            for unit in ScheduleIntervalUnit.allCases {
                for count in [1, 2, 7] {
                    for raw in ["09:01", "Enabled", "  e\u{301}/%@/{date}\nraw  ", "日曜 １３:００"] {
                        let actual = ScheduleDisplayCopy.cadence(count: count, unit: unit, at: raw, bundle: resource, locale: Locale(identifier: language))
                        let format = key(unit, count: count, suffix: " at %@")
                        let args: [CVarArg] = count == 1 ? [raw] : [count, raw]
                        XCTAssertEqual(Array(actual.utf8), Array(expected(format, bundle: resource, args: args).utf8))
                        XCTAssertTrue(actual.contains(raw))
                        let starting = ScheduleDisplayCopy.cadenceStartingSummary(count: count, unit: unit, starting: raw, bundle: resource, locale: Locale(identifier: language))
                        let startingKey = key(unit, count: count, suffix: " starting %@. Monthly schedules use the last day when a month is shorter.")
                        XCTAssertEqual(Array(starting.utf8), Array(expected(startingKey, bundle: resource, args: args).utf8))
                    }
                }
            }
        }
    }

    func testDisplayUnitLabelsDoNotChangeStoredIdentityOrNominalCalendarValues() throws {
        let original = ScheduleIntervalUnit.allCases.map { ($0.rawValue, $0.nominalDayCount) }
        for language in languages {
            let resource = try bundle(language)
            for unit in ScheduleIntervalUnit.allCases {
                let title: String
                switch unit {
                case .day: title = "Days"
                case .week: title = "Weeks"
                case .month: title = "Months"
                }
                XCTAssertEqual(ScheduleDisplayCopy.unitChoiceLabel(unit, bundle: resource, locale: Locale(identifier: language)), resource.localizedString(forKey: title, value: nil, table: nil))
            }
        }
        XCTAssertEqual(ScheduleIntervalUnit.allCases.map(\.rawValue), original.map(\.0))
        XCTAssertEqual(ScheduleIntervalUnit.allCases.map(\.nominalDayCount), original.map(\.1))
        XCTAssertEqual(original.map(\.0), ["day", "week", "month"])
        XCTAssertEqual(original.map(\.1), [1, 7, 30])
    }
}
