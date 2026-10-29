#if os(macOS)
import Foundation
import XCTest

/// Host-only resource boundary. This verifies the actual compiled strings tables,
/// not visual layout, source reachability, or locale-specific UI interaction.
nonisolated final class CompiledCatalogCoverageTests: XCTestCase {
    func testEveryDirectTranslationIsPresentInTheCompiledLocaleBundle() throws {
        let appleRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let catalogURL = appleRoot.appendingPathComponent("HealthMd/Localizable.xcstrings")
        let catalog = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: catalogURL)) as? [String: Any])
        let strings = try XCTUnwrap(catalog["strings"] as? [String: [String: Any]])
        let languages = ["de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"]
        var checked = 0
        for language in languages {
            let path = [Bundle.main, Bundle(for: Self.self)].compactMap { $0.path(forResource: language, ofType: "lproj") }.first
            let bundle = try XCTUnwrap(path.flatMap(Bundle.init(path:)), "Missing compiled locale: \(language)")
            for (key, entry) in strings {
                guard let locales = entry["localizations"] as? [String: [String: Any]],
                      let unit = locales[language]?["stringUnit"] as? [String: String],
                      let expected = unit["value"] else { continue }
                let actual = bundle.localizedString(forKey: key, value: "__MISSING_LOCALIZATION__", table: nil)
                XCTAssertEqual(actual, expected, "\(language): \(key)")
                checked += 1
            }
        }
        XCTAssertGreaterThan(checked, 20_000, "Expected the full production catalog, not a reduced test fixture")
    }
}
#endif
