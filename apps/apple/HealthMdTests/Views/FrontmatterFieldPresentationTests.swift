import XCTest
@testable import HealthMd

nonisolated final class FrontmatterFieldPresentationTests: XCTestCase {
    private let languages = ["de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"]

    private func resources(_ language: String) throws -> Bundle {
        let path = [Bundle.main, Bundle(for: Self.self)].compactMap {
            $0.path(forResource: language, ofType: "lproj")
        }.first
        return try XCTUnwrap(path.flatMap(Bundle.init(path:)), "Missing production catalog: \(language)")
    }

    func testFieldNamesAndInterpolatedLabelsPreserveExactBytesAcrossLocalesAndStates() throws {
        let pairs = [
            ("sleep_total", "my_sleep"),
            ("Sleep", "Enabled"), // Valid catalog keys are still opaque YAML keys here.
            ("original", "  Custom\n\tValue  "),
            ("%@ %lld", "{{date}} **raw** [link](url) \\\""),
            ("é", "e\u{301}"), // Canonically equal but byte-distinct: preserve both.
            ("心拍数", "καρδιά"),
            ("date", "date"),
            ("type", "")
        ]
        for language in languages {
            let bundle = try resources(language)
            for (original, custom) in pairs {
                for enabled in [true, false] {
                    let copy = FrontmatterFieldPresentation(originalKey: original, customKey: custom,
                                                           isEnabled: enabled, bundle: bundle,
                                                           locale: Locale(identifier: language))
                    XCTAssertEqual(Array(copy.originalKey.utf8), Array(original.utf8))
                    XCTAssertEqual(Array(copy.customKey.utf8), Array(custom.utf8))
                    XCTAssertEqual(copy.renamed, custom != original && !custom.isEmpty)
                    let expectedLabel = copy.renamed
                        ? String(format: bundle.localizedString(forKey: "%@ renamed to %@", value: nil, table: nil), original, custom)
                        : original
                    XCTAssertEqual(Array(copy.accessibilityLabel.utf8), Array(expectedLabel.utf8))
                    let detailKey = copy.renamed ? "Renamed to %@" : (enabled ? "Included in frontmatter" : "Not exported")
                    let format = bundle.localizedString(forKey: detailKey, value: nil, table: nil)
                    XCTAssertEqual(copy.detail, copy.renamed ? String(format: format, custom) : format)
                    XCTAssertEqual(copy.accessibilityValue, bundle.localizedString(forKey: enabled ? "Enabled" : "Disabled", value: nil, table: nil))
                    XCTAssertEqual(copy.accessibilityHint, bundle.localizedString(forKey: enabled ? "Double tap to disable this field" : "Double tap to enable this field", value: nil, table: nil))
                }
            }
        }
    }

    func testOnlyEmptyCustomValuesReceiveLocalizedCopyAndAllOtherValuesRemainVerbatim() throws {
        let values = ["Sleep", "Empty Value", "Enabled", "  ", "\n\t", " leading\ntrailing ", "date: {{date}}", "**bold**", "%@ %lld \\\"", "é", "e\u{301}", "健康/καρδιά"]
        for language in languages {
            let bundle = try resources(language)
            for value in values {
                let actual = FrontmatterFieldPresentation.customValue(value, bundle: bundle, locale: Locale(identifier: language))
                XCTAssertEqual(Array(actual.utf8), Array(value.utf8), "Do not localize or normalize user values: \(language)")
            }
            XCTAssertEqual(FrontmatterFieldPresentation.customValue("", bundle: bundle, locale: Locale(identifier: language)),
                           bundle.localizedString(forKey: "Empty Value", value: nil, table: nil))
        }
    }

    func testCountTemplatesAndCategoryNamesResolveForEveryLocale() throws {
        let enabled = 3, total = 4, custom = 2, placeholders = 1
        for language in languages {
            let bundle = try resources(language)
            let locale = Locale(identifier: language)
            let count = String(localized: "Enabled: \(enabled) of \(total)", bundle: bundle, locale: locale)
            XCTAssertEqual(count, String(format: bundle.localizedString(forKey: "Enabled: %lld of %lld", value: nil, table: nil), enabled, total))
            let summary = String(localized: "\(enabled) of \(total) health metric fields enabled, \(custom) custom fields, \(placeholders) placeholder fields", bundle: bundle, locale: locale)
            XCTAssertEqual(summary, String(format: bundle.localizedString(forKey: "%lld of %lld health metric fields enabled, %lld custom fields, %lld placeholder fields", value: nil, table: nil), enabled, total, custom, placeholders))
            for category in ["Sleep", "Activity", "Heart", "Vitals", "Body", "Nutrition", "Mindfulness", "Mobility", "Hearing", "Workouts"] {
                XCTAssertNotEqual(bundle.localizedString(forKey: category, value: "__missing__", table: nil), "__missing__")
            }
        }
    }

    @MainActor
    func testConfigurationEncodingAndExportKeyProjectionAreUnchangedByPresentation() throws {
        let config = FrontmatterConfiguration()
        config.fields = [CustomFrontmatterField(originalKey: "sleep_total_hours", customKey: "Sleep"),
                         CustomFrontmatterField(originalKey: "steps", customKey: "  steps\nraw  ", isEnabled: false)]
        config.customFields = ["Enabled": "Empty Value", "raw_%@": "  {{date}}\n**raw**  "]
        config.placeholderFields = ["Sleep", "custom_%lld"]
        config.customDateKey = "日付"
        config.customTypeValue = "**health-data**"
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let before = try encoder.encode(config)
        let outputKeys = config.fields.map { config.outputKey(for: $0.originalKey) }
        for language in languages {
            let bundle = try resources(language)
            for field in config.fields {
                _ = FrontmatterFieldPresentation(originalKey: field.originalKey, customKey: field.customKey,
                                                  isEnabled: field.isEnabled, bundle: bundle, locale: Locale(identifier: language))
            }
            for value in config.customFields.values {
                XCTAssertEqual(Array(FrontmatterFieldPresentation.customValue(value, bundle: bundle, locale: Locale(identifier: language)).utf8), Array(value.utf8))
            }
            XCTAssertEqual(try encoder.encode(config), before)
            XCTAssertEqual(config.fields.map { config.outputKey(for: $0.originalKey) }, outputKeys)
        }
    }

    func testGermanAndJapaneseStateCopyComesFromProductionTranslations() throws {
        for (language, enabledDetail, disabledDetail, enableHint) in [
            ("de", "In Frontmatter enthalten", "Nicht exportiert", "Doppeltippen, um dieses Feld zu aktivieren"),
            ("ja", "フロントマターに含まれます", "書き出されません", "ダブルタップしてこのフィールドを有効にします")
        ] {
            let bundle = try resources(language)
            let on = FrontmatterFieldPresentation(originalKey: "Sleep", customKey: "Sleep", isEnabled: true, bundle: bundle, locale: Locale(identifier: language))
            let off = FrontmatterFieldPresentation(originalKey: "Sleep", customKey: "Sleep", isEnabled: false, bundle: bundle, locale: Locale(identifier: language))
            XCTAssertEqual(on.originalKey, "Sleep")
            XCTAssertEqual(on.accessibilityLabel, "Sleep")
            XCTAssertEqual(on.detail, enabledDetail)
            XCTAssertEqual(off.detail, disabledDetail)
            XCTAssertEqual(off.accessibilityHint, enableHint)
        }
    }
}
