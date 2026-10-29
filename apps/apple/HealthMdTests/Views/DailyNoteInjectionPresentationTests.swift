import XCTest
@testable import HealthMd

nonisolated final class DailyNoteInjectionPresentationTests: XCTestCase {
    private let languages = ["de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"]

    private func resources(_ language: String) throws -> Bundle {
        let path = [Bundle.main, Bundle(for: Self.self)].compactMap { $0.path(forResource: language, ofType: "lproj") }.first
        return try XCTUnwrap(path.flatMap(Bundle.init(path:)), "Missing production catalog: \(language)")
    }

    func testCompiledPluralResourcesSelectZeroOneTwoAndSeveralForEveryLanguage() throws {
        let expected = [
            ("en", "1 metric", "2 metrics", "1 metric enabled", "2 metrics enabled"),
            ("de", "1 Metrik", "2 Metriken", "1 Metrik aktiviert", "2 Metriken aktiviert"),
            ("es", "1 métrica", "2 métricas", "1 métrica activada", "2 métricas activadas"),
            ("fr", "1 indicateur", "2 indicateurs", "1 mesure activée", "2 mesures activées"),
            ("it", "1 metrica", "2 metriche", "1 metrica attivata", "2 metriche attivate"),
            ("ja", "1指標", "2指標", "指標1個が有効", "指標2個が有効"),
            ("ko", "1개 항목", "2개 항목", "항목 1개 활성화됨", "항목 2개 활성화됨"),
            ("nl", "1 meetwaarde", "2 meetwaarden", "1 meetwaarde ingeschakeld", "2 meetwaarden ingeschakeld"),
            ("pt-BR", "1 métrica", "2 métricas", "1 métrica ativada", "2 métricas ativadas"),
            ("zh-Hans", "1个指标", "2个指标", "已启用 1 个指标", "已启用 2 个指标")
        ]
        for (language, one, two, oneEnabled, twoEnabled) in expected {
            let bundle = try resources(language)
            for enabled in [true, false] {
                for only in [true, false] {
                    for count in [0, 1, 2, 7] {
                        let copy = DailyNoteInjectionPresentation(isEnabled: enabled, dailyNotesOnly: only, metricCount: count, bundle: bundle, locale: Locale(identifier: language))
                        let title = count == 0 ? bundle.localizedString(forKey: "No Metrics", value: nil, table: nil) : (count == 1 ? one : two.replacingOccurrences(of: "2", with: String(count)))
                        let value = count == 0 ? bundle.localizedString(forKey: "No metrics enabled", value: nil, table: nil) : (count == 1 ? oneEnabled : twoEnabled.replacingOccurrences(of: "2", with: String(count)))
                        XCTAssertEqual(copy.metricsTitle, title, "\(language)/\(count)")
                        XCTAssertEqual(copy.metricsAccessibilityValue, value, "\(language)/\(count)")
                    }
                }
            }
        }
    }

    func testStatesModesAndHeaderUseLocalizedCopyWithoutEnglishVerbFragments() throws {
        for language in languages {
            let bundle = try resources(language)
            for enabled in [true, false] {
                for only in [true, false] {
                    let copy = DailyNoteInjectionPresentation(isEnabled: enabled, dailyNotesOnly: only, metricCount: 2, bundle: bundle, locale: Locale(identifier: language))
                    let state = bundle.localizedString(forKey: enabled ? "Enabled" : "Disabled", value: nil, table: nil)
                    XCTAssertEqual(copy.statusTitle, state)
                    XCTAssertEqual(copy.headerLabel, String(format: bundle.localizedString(forKey: "Daily Note Injection, %@", value: nil, table: nil), state))
                    let hint = enabled ? "Double tap to disable daily note injection" : "Double tap to enable daily note injection"
                    XCTAssertEqual(copy.toggleHint, bundle.localizedString(forKey: hint, value: nil, table: nil))
                    XCTAssertNotEqual(copy.toggleHint, hint)
                    let mode = only ? "Exports update only your daily notes. Other generated files stay configured but are skipped." : "Exports update YAML frontmatter in the daily notes you already keep, while normal export files still follow your selected formats."
                    XCTAssertEqual(copy.modeExplanation, bundle.localizedString(forKey: mode, value: nil, table: nil))
                }
            }
        }
    }

    func testWarningPreservesEveryRawPathByteWithoutLocalizationOrNormalization() throws {
        let paths = ["Health", "Enabled", "Daily Note Injection", "  Folder  ", "Journal/Daily", "{date}/{YR}/%@/%lld", "**raw**\\folder\nline", "é", "e\u{301}", "健康/καρδιά", ""]
        let key = "With Folder set to Daily, notes are written to Daily/… at the vault root, not %@/Daily/…."
        for language in languages {
            let bundle = try resources(language)
            for path in paths {
                let warning = DailyNoteInjectionPresentation.vaultRootWarning(path, bundle: bundle, locale: Locale(identifier: language))
                let expected = String(format: bundle.localizedString(forKey: key, value: nil, table: nil), path)
                XCTAssertEqual(Array(warning.utf8), Array(expected.utf8))
                XCTAssertTrue(warning.contains(path + "/Daily/…"))
                XCTAssertTrue(warning.contains("Daily/…"))
            }
        }
    }

    @MainActor
    func testSettingsFilenameTokensAndActualPreviewPathBytesDoNotChangeWithCopyLocale() throws {
        let settings = DailyNoteInjectionSettings()
        settings.enabled = true
        settings.dailyNotesOnly = true
        settings.createIfMissing = true
        settings.injectMarkdownSections = true
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        let date = try XCTUnwrap(ISO8601DateFormatter().date(from: "2026-03-25T12:00:00Z"))
        let zone = try XCTUnwrap(TimeZone(secondsFromGMT: 0))
        for folder in ["", "Daily", "Journal/Daily", "  Daily  ", "e\u{301}/健康"] {
            for pattern in ["{date}", "{year}/{month}/{day}", "{YR}-{weekday}-{monthName}-{quarter}", "Enabled_%@_{date}_{custom}"] {
                settings.folderPath = folder
                settings.filenamePattern = pattern
                let before = try encoder.encode(settings)
                let filename = settings.formatFilename(for: date, timeZone: zone)
                let preview = settings.previewPath(for: date, timeZone: zone)
                for language in languages {
                    let bundle = try resources(language)
                    _ = DailyNoteInjectionPresentation(isEnabled: settings.enabled, dailyNotesOnly: settings.dailyNotesOnly, metricCount: 2, bundle: bundle, locale: Locale(identifier: language))
                    _ = DailyNoteInjectionPresentation.vaultRootWarning(folder, bundle: bundle, locale: Locale(identifier: language))
                    XCTAssertEqual(try encoder.encode(settings), before)
                    XCTAssertEqual(Array(settings.folderPath.utf8), Array(folder.utf8))
                    XCTAssertEqual(Array(settings.filenamePattern.utf8), Array(pattern.utf8))
                    XCTAssertEqual(Array(settings.formatFilename(for: date, timeZone: zone).utf8), Array(filename.utf8))
                    XCTAssertEqual(Array(settings.previewPath(for: date, timeZone: zone).utf8), Array(preview.utf8))
                }
            }
        }
        settings.folderPath = "Daily"
        settings.filenamePattern = "{date}"
        XCTAssertEqual(settings.previewPath(for: date, healthSubfolder: "Health", timeZone: zone), "Daily/2026-03-25.md")
        XCTAssertEqual(settings.previewPath(for: date, healthSubfolder: "Different", timeZone: zone), "Daily/2026-03-25.md")
    }
}
