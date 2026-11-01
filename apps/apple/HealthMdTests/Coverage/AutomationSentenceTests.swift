#if os(iOS)
import XCTest
@testable import HealthMd

final class AutomationSentenceTests: XCTestCase {
    private let values: [AutomationSentence.Token: String] = [
        .when: "Daily", .range: "yesterday", .metrics: "5 metrics",
        .where: "Vault", .formats: "CSV", .note: "update my daily note"
    ]

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

    /// A translation that drops a token would silently lose a user's choice.
    func testEveryLocalizedTemplateKeepsEveryToken() throws {
        let key = "{when}, write {range}: {metrics} to {where} as {formats}, and {note}."
        for locale in ["en", "de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"] {
            let path = try XCTUnwrap(Bundle.main.path(forResource: locale, ofType: "lproj"), locale)
            let bundle = try XCTUnwrap(Bundle(path: path))
            let template = bundle.localizedString(forKey: key, value: nil, table: "Localizable")
            let tokens = AutomationSentence.segments(template: template, values: values).compactMap { segment -> AutomationSentence.Token? in
                if case .token(let token, _) = segment { return token }
                return nil
            }
            XCTAssertEqual(Set(tokens), Set(AutomationSentence.Token.allCases), locale)
        }
    }
}
#endif
