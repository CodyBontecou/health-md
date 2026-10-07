import XCTest
@testable import HealthMd
#if os(iOS)
import SwiftUI
#endif

final class WorkoutTableToggleLocalizationTests: XCTestCase {
    private func localizedResources(_ language: String) throws -> Bundle {
        // The app host owns the production catalog. Isolated native XCTest
        // compiles that same catalog into the test bundle, without mock strings.
        let path = [Bundle.main, Bundle(for: Self.self)].compactMap {
            $0.path(forResource: language, ofType: "lproj")
        }.first
        return try XCTUnwrap(path.flatMap(Bundle.init(path:)), "Missing production resources: \(language)")
    }

    private let expected = [
        ("de", "Trainingsdetails und Metadaten",
         "Zeige diese beiden Trainingstabellen in Markdown-Exporten und täglichen Notizen. Schalte sie aus, um lesbare Trainingszusammenfassungen ohne die Tabellen zu behalten. Strukturierte Daten und Quelldatenerfassung bleiben unverändert.",
         "Details- und Metadatentabellen für Trainings einbeziehen", "Aktiviert", "Deaktiviert"),
        ("ja", "ワークアウトの詳細とメタデータ",
         "Markdownのエクスポートとデイリーノートに、この2つのワークアウトの表を表示します。オフにすると、表なしで読みやすいワークアウトの概要を残します。構造化データとソースデータの取得は変わりません。",
         "ワークアウトの詳細とメタデータの表を含める", "有効", "無効")
    ]

    func testWorkoutSettingPresentationUsesGermanAndJapaneseResourcesInBothStates() throws {
        for (language, title, subtitle, label, enabled, disabled) in expected {
            let bundle = try localizedResources(language)
            for isOn in [true, false] {
                let copy = WorkoutTableTogglePresentation(isOn: isOn, bundle: bundle, locale: Locale(identifier: language))
                XCTAssertEqual(copy.title, title)
                XCTAssertEqual(copy.subtitle, subtitle)
                XCTAssertEqual(copy.accessibilityLabel, label)
                XCTAssertEqual(copy.accessibilityHint, subtitle)
                XCTAssertEqual(copy.accessibilityValue, isOn ? enabled : disabled)
            }
        }
    }

    #if os(iOS)
    @MainActor
    func testActualWorkoutControlUsesLocalizedPresentationAndKeepsItsBinding() throws {
        for (language, title, subtitle, label, enabled, disabled) in expected {
            let bundle = try localizedResources(language)
            var value = true
            let binding = Binding(get: { value }, set: { value = $0 })
            let row = FormatWorkoutTableToggleControl(isOn: binding)
            for isOn in [true, false] {
                binding.wrappedValue = isOn
                let control = row.control(bundle: bundle, locale: Locale(identifier: language))
                XCTAssertEqual(control.title, title)
                XCTAssertEqual(control.subtitle, subtitle)
                XCTAssertEqual(control.accessibilityLabel, label)
                XCTAssertEqual(control.localizedAccessibilityHint, subtitle)
                XCTAssertEqual(control.localizedAccessibilityValue, isOn ? enabled : disabled)
                XCTAssertEqual(control.isOn, isOn)
                control.$isOn.wrappedValue = !isOn
                XCTAssertEqual(value, !isOn, "Localization must not replace the setting binding")
            }
        }
    }
    #endif
}
