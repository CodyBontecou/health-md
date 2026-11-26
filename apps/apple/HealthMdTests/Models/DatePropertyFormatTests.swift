import XCTest
@testable import HealthMd

/// The frontmatter/JSON/CSV `date` value: the EU Dash preset, custom placeholder
/// patterns, their safe fallback, and decoding of settings saved before either existed (#452).
final class DatePropertyFormatTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: FormatCustomization and AdvancedExportSettings hold
    // Combine subscriptions; other model tests retain them to avoid teardown crashes.
    private static var retained: [AnyObject] = []

    private let utc = TimeZone(secondsFromGMT: 0)!

    private func date(_ year: Int, _ month: Int, _ day: Int) throws -> Date {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        return try XCTUnwrap(calendar.date(from: DateComponents(year: year, month: month, day: day, hour: 12)))
    }

    private func customization(_ format: DateFormatPreference, pattern: String = "") -> FormatCustomization {
        let value = FormatCustomization()
        value.dateFormat = format
        value.customDatePattern = pattern
        Self.retained.append(value)
        return value
    }

    // MARK: - Formatting

    func testDefaultStaysISO8601() throws {
        XCTAssertEqual(FormatCustomization().formatDate(try date(2026, 1, 13), timeZone: utc), "2026-01-13")
    }

    func testEUDashPreset() throws {
        XCTAssertEqual(DateFormatPreference.euDash.rawValue, "dd-MM-yyyy")
        for (y, m, d, expected) in [(2026, 1, 13, "13-01-2026"), (2024, 2, 29, "29-02-2024"), (2026, 1, 1, "01-01-2026")] {
            XCTAssertEqual(customization(.euDash).formatDate(try date(y, m, d), timeZone: utc), expected)
        }
    }

    func testCustomPatternUsesFilenamePlaceholders() throws {
        let day = try date(2026, 1, 13)
        XCTAssertEqual(customization(.custom, pattern: "{day}-{month}-{year}").formatDate(day, timeZone: utc), "13-01-2026")
        XCTAssertEqual(customization(.custom, pattern: "{YR}.{month}.{day}").formatDate(day, timeZone: utc), "26.01.13")
        XCTAssertEqual(customization(.custom, pattern: "{weekYear}-W{week}").formatDate(day, timeZone: utc), "2026-W03")
        XCTAssertEqual(customization(.custom, pattern: "{year} {quarter}").formatDate(day, timeZone: utc), "2026 Q1")
        XCTAssertEqual(customization(.custom, pattern: "{date}").formatDate(day, timeZone: utc), "2026-01-13")
    }

    func testCustomPatternHonorsCalendarTimeZone() throws {
        // 23:30 UTC on Jan 13 is already Jan 14 in UTC+2.
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = utc
        let late = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 1, day: 13, hour: 23, minute: 30)))
        let plusTwo = try XCTUnwrap(TimeZone(secondsFromGMT: 7_200))
        XCTAssertEqual(customization(.custom, pattern: "{day}-{month}-{year}").formatDate(late, timeZone: plusTwo), "14-01-2026")
    }

    func testInvalidOrEmptyCustomPatternFallsBackToISO8601() throws {
        let day = try date(2026, 1, 13)
        for pattern in [
            "",                         // empty
            "DD-MM-YYYY",               // no placeholder (Obsidian tokens are not supported)
            "{dd}-{MM}",                // unknown placeholders
            "{day}-{month",             // unclosed brace
            "{day}: {month}",           // YAML key separator
            "{day} #{month}",           // YAML comment
            "\"{day}\"",                // quote
            "- {day}",                  // YAML sequence at start
            "{day}\n{month}",           // newline
            "{day} ",                   // trailing space
            "{day}%{month}",            // percent
            String(repeating: "{day}", count: 20) // longer than 64 characters
        ] {
            XCTAssertFalse(CustomDatePattern.isValid(pattern), pattern)
            XCTAssertEqual(customization(.custom, pattern: pattern).formatDate(day, timeZone: utc), "2026-01-13", pattern)
        }
    }

    func testValidPatternGrammar() {
        for pattern in ["{day}-{month}-{year}", "{day}/{month}/{year}", "Week {week}, {weekYear}", "{monthName} {day} {year}", "{day}_{month}.{year}"] {
            XCTAssertTrue(CustomDatePattern.isValid(pattern), pattern)
        }
    }

    func testPresetIgnoresStoredCustomPattern() throws {
        XCTAssertEqual(customization(.euDot, pattern: "{year}").formatDate(try date(2026, 1, 13), timeZone: utc), "13.01.2026")
    }

    func testFrontmatterDatePropertyUsesCustomPattern() throws {
        let format = customization(.custom, pattern: "{day}-{month}-{year}")
        let data = HealthData(date: try date(2026, 1, 13))
        let snapshot = data.exportSnapshot(customization: format)
        XCTAssertEqual(snapshot.dateString, DateFormatPreference.custom.format(
            date: data.date, timeZone: snapshot.calendarTimeZone, customPattern: "{day}-{month}-{year}"
        ))
        XCTAssertTrue(snapshot.dateString.range(of: #"^\d{2}-\d{2}-\d{4}$"#, options: .regularExpression) != nil)
    }

    // MARK: - Decoding and persistence

    func testLegacyFormatCustomizationDecodesUnchanged() throws {
        let legacy = #"{"dateFormat":"dd.MM.yyyy","timeFormat":"HH:mm","unitPreference":"Metric"}"#
        let decoded = try JSONDecoder().decode(FormatCustomization.self, from: Data(legacy.utf8))
        Self.retained.append(decoded)
        XCTAssertEqual(decoded.dateFormat, .euDot)
        XCTAssertEqual(decoded.customDatePattern, "")
        let reencoded = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(decoded)) as? [String: Any])
        XCTAssertNil(reencoded["customDatePattern"], "An unused pattern must not change saved bytes")
    }

    func testUnknownStoredDateFormatFallsBackInsteadOfFailing() throws {
        let future = #"{"dateFormat":"some-future-preset","timeFormat":"HH:mm"}"#
        let decoded = try JSONDecoder().decode(FormatCustomization.self, from: Data(future.utf8))
        Self.retained.append(decoded)
        XCTAssertEqual(decoded.dateFormat, .iso8601)
        XCTAssertEqual(decoded.timeFormat, .hour24)
    }

    func testLegacySnapshotDecodesAndReencodesWithoutPatternKey() throws {
        let original = FormatCustomizationSnapshot.from(customization(.euShort))
        XCTAssertNil(original.customDatePattern)
        let encoded = try JSONEncoder().encode(original)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any])
        XCTAssertNil(object["customDatePattern"], "Existing durable fingerprints must not change")
        XCTAssertEqual(try JSONDecoder().decode(FormatCustomizationSnapshot.self, from: encoded), original)
    }

    func testCustomPatternRoundTripsThroughFrozenProfile() throws {
        let settings = AdvancedExportSettings()
        Self.retained.append(settings)
        settings.formatCustomization.dateFormat = .custom
        settings.formatCustomization.customDatePattern = "{day}-{month}-{year}"
        let snapshot = ExportSettingsSnapshot.from(settings)
        let profile = ExportProfile(name: "Custom date", settings: snapshot, target: .localIPhoneFolder)
        let decoded = try JSONDecoder().decode(ExportProfile.self, from: JSONEncoder().encode(profile))
        let restored = decoded.settings.makeAdvancedExportSettings()
        Self.retained.append(restored)
        XCTAssertEqual(restored.formatCustomization.dateFormat, .custom)
        XCTAssertEqual(restored.formatCustomization.customDatePattern, "{day}-{month}-{year}")
        XCTAssertEqual(restored.formatCustomization.formatDate(try date(2026, 1, 13), timeZone: utc), "13-01-2026")
    }

    func testCustomPatternPersistsAcrossSettingsReloadAndResetClearsIt() throws {
        let suiteName = "DatePropertyFormatTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retained.append(settings)
        settings.formatCustomization.dateFormat = .custom
        settings.formatCustomization.customDatePattern = "{day}-{month}-{year}"
        let deadline = Date(timeIntervalSinceNow: 2)
        repeat {
            RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.01))
            if let bytes = defaults.data(forKey: "advancedExportSettings.formatCustomization"),
               let stored = try? JSONDecoder().decode(FormatCustomizationSnapshot.self, from: bytes),
               stored.customDatePattern == "{day}-{month}-{year}" {
                break
            }
        } while Date() < deadline
        let reloaded = AdvancedExportSettings(userDefaults: defaults)
        Self.retained.append(reloaded)
        XCTAssertEqual(reloaded.formatCustomization.dateFormat, .custom)
        XCTAssertEqual(reloaded.formatCustomization.customDatePattern, "{day}-{month}-{year}")
        reloaded.formatCustomization.reset()
        XCTAssertEqual(reloaded.formatCustomization.dateFormat, .iso8601)
        XCTAssertEqual(reloaded.formatCustomization.customDatePattern, "")
    }
}
