import XCTest
@testable import HealthMd
#if os(iOS)
import MessageUI
#endif

@MainActor
final class FeedbackReporterTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: Match the ObservableObject test policy for
    // macOS 26 / Swift 6 deinit crashes (docs/testing/lifecycle-audit.md).
    private static var retainedReporters: [FeedbackReporter] = []

    private func makeReporter(strings: FeedbackFallbackCopy = .init(), opener: @escaping FeedbackReporter.Opener) -> FeedbackReporter {
        let reporter = FeedbackReporter(opener: opener, strings: strings)
        Self.retainedReporters.append(reporter)
        return reporter
    }

    func testRejectedGitHubHandoffProvidesLocalTemplateWithoutRetrying() throws {
        var openedURLs: [URL] = []
        let reporter = makeReporter { url, completion in
            openedURLs.append(url)
            completion(false)
        }
        reporter.open(.github)

        XCTAssertEqual(openedURLs.count, 1, "Fallback must not depend on another handoff")
        let url = try XCTUnwrap(openedURLs.first)
        XCTAssertEqual(url.host, "github.com")
        XCTAssertEqual(url.path, "/CodyBontecou/health-md/issues/new")
        let body = URLComponents(url: url, resolvingAgainstBaseURL: false)?
            .queryItems?.first { $0.name == "body" }?.value
        XCTAssertEqual(body, FeedbackHelper.issueBody, "Preserve the pre-filled template")
        let failure = try XCTUnwrap(reporter.failure)
        XCTAssertTrue(failure.message.contains("No issue was submitted"))
        XCTAssertTrue(failure.reportText.contains(FeedbackHelper.issueBody))
        XCTAssertTrue(failure.reportText.contains("To: cody@isolated.tech"))
        XCTAssertTrue(failure.reportText.contains("https://github.com/CodyBontecou/health-md/issues/new"))
    }

    func testRejectedEmailHandoffProvidesAddressAndDiagnosticsWithoutRetrying() throws {
        var attempts = 0
        let reporter = makeReporter { url, completion in
            attempts += 1
            XCTAssertEqual(url.scheme, "mailto")
            XCTAssertEqual(url.path, FeedbackHelper.supportEmail)
            completion(false)
        }
        reporter.open(.email)

        let failure = try XCTUnwrap(reporter.failure)
        XCTAssertTrue(failure.message.contains("could not open your email app"))
        XCTAssertTrue(failure.reportText.contains(FeedbackHelper.supportEmail))
        XCTAssertTrue(failure.reportText.contains(FeedbackHelper.diagnosticsBlock))
        XCTAssertEqual(attempts, 1)
    }

    func testAsynchronousOpenerResultControlsFailurePresentation() throws {
        var completion: FeedbackReporter.Completion?
        let reporter = makeReporter { _, callback in completion = callback }
        reporter.open(.github)
        XCTAssertNil(reporter.failure)
        try XCTUnwrap(completion)(false)
        XCTAssertNotNil(reporter.failure)
    }

    func testSuccessfulHandoffsDoNotClaimSubmissionOrDelivery() {
        let reporter = makeReporter { _, completion in completion(true) }
        reporter.open(.github)
        XCTAssertNil(reporter.failure)
        reporter.open(.email)
        XCTAssertNil(reporter.failure)
    }

    func testEditingAfterCopyClearsVisibleAndAccessibleConfirmationUntilRecopied() {
        var draft = FeedbackReportDraft(reportText: "Synthetic template")
        var pasteboard = ""
        let write: (String) -> Bool = { text in
            pasteboard = text
            return true
        }

        XCTAssertEqual(draft.copyConfirmation, "")
        XCTAssertEqual(draft.copyAccessibilityLabel, "")
        draft.copy(using: write)
        XCTAssertEqual(pasteboard, "Synthetic template")
        XCTAssertEqual(draft.copyConfirmation, String(localized: "Copied"))
        XCTAssertEqual(draft.copyAccessibilityLabel, String(localized: "Report copied"))

        draft.reportText = "Synthetic edited report"
        XCTAssertFalse(draft.copied)
        XCTAssertEqual(draft.copyConfirmation, "", "Do not claim the edited report was copied")
        XCTAssertEqual(draft.copyAccessibilityLabel, "", "Accessibility must clear too")
        XCTAssertEqual(pasteboard, "Synthetic template", "Editing must not write the clipboard")

        draft.copy(using: write)
        XCTAssertEqual(pasteboard, "Synthetic edited report")
        XCTAssertEqual(draft.copyConfirmation, String(localized: "Copied"))
        XCTAssertEqual(draft.copyAccessibilityLabel, String(localized: "Report copied"))
    }

    func testUnchangedEditorTextKeepsConfirmationButFailedCopyClearsIt() {
        var draft = FeedbackReportDraft(reportText: "Synthetic report")
        draft.copy { _ in true }
        draft.reportText = "Synthetic report"
        XCTAssertTrue(draft.copied, "An unchanged editor update is not an edit")
        draft.copy { _ in false }
        XCTAssertFalse(draft.copied)
        XCTAssertEqual(draft.copyConfirmation, "")
        XCTAssertEqual(draft.copyAccessibilityLabel, "")
    }

    private func localizedResources(_ language: String) throws -> Bundle {
        // App-hosted XCTest uses the production app bundle. The isolated native
        // runner compiles the same catalog into this test bundle, without mocks.
        let path = [Bundle.main, Bundle(for: Self.self)].compactMap {
            $0.path(forResource: language, ofType: "lproj")
        }.first
        return try XCTUnwrap(path.flatMap(Bundle.init(path:)), "Missing production resources: \(language)")
    }

    func testFallbackSheetAndHandoffMessagesUseEverySupportedLanguage() throws {
        let english = FeedbackFallbackCopy(bundle: try localizedResources("en"), locale: Locale(identifier: "en"))
        func fallbackValues(_ copy: FeedbackFallbackCopy) -> [String] {
            [copy.mailQueueFailure, copy.emailHandoffFailure, copy.githubHandoffFailure,
             copy.title, copy.instructions, copy.reportLabel, copy.copyReport, copy.reportCopied]
        }
        for language in ["de", "es", "fr", "it", "ja", "ko", "nl", "pt-BR", "zh-Hans"] {
            let copy = FeedbackFallbackCopy(bundle: try localizedResources(language), locale: Locale(identifier: language))
            let reporter = makeReporter(strings: copy) { _, completion in completion(false) }
            reporter.open(.github)
            let githubFailure = try XCTUnwrap(reporter.failure)
            XCTAssertEqual(githubFailure.message, copy.githubHandoffFailure)
            reporter.open(.email)
            XCTAssertEqual(reporter.failure?.message, copy.emailHandoffFailure)
            let sheet = FeedbackFailureView(failure: githubFailure, strings: copy)
            for (actual, source) in zip(fallbackValues(sheet.strings), fallbackValues(english)) {
                XCTAssertFalse(actual.isEmpty, language)
                XCTAssertNotEqual(actual, source, "\(language) must not fall back to English recovery copy")
            }
        }
    }

    func testGermanAndJapaneseRecoveryInstructionsAndCopyConfirmation() throws {
        let expected = [
            ("de", "Feedback konnte nicht gesendet werden",
             "Bearbeite den Bericht und kopiere ihn vor dem Schließen. Nichts wird automatisch gesendet. Vermeide private Gesundheitsdaten.",
             "Feedback-Bericht", "Bericht kopieren", "Kopiert", "Bericht kopiert"),
            ("ja", "フィードバックを送信できませんでした",
             "レポートを編集し、閉じる前にコピーしてください。自動的に送信されることはありません。個人の健康データを含めないでください。",
             "フィードバックのレポート", "レポートをコピー", "コピーされました", "レポートをコピーしました")
        ]
        for (language, title, instructions, reportLabel, copyReport, copied, reportCopied) in expected {
            let copy = FeedbackFallbackCopy(bundle: try localizedResources(language), locale: Locale(identifier: language))
            XCTAssertEqual(copy.title, title)
            XCTAssertEqual(copy.instructions, instructions)
            XCTAssertEqual(copy.reportLabel, reportLabel)
            XCTAssertEqual(copy.copyReport, copyReport)
            var draft = FeedbackReportDraft(reportText: "Synthetic report", strings: copy)
            draft.copy { _ in true }
            XCTAssertEqual(draft.copyConfirmation, copied)
            XCTAssertEqual(draft.copyAccessibilityLabel, reportCopied)
            draft.reportText = "Synthetic edited report"
            XCTAssertEqual(draft.copyConfirmation, "")
            XCTAssertEqual(draft.copyAccessibilityLabel, "")
            draft.copy { _ in true }
            XCTAssertEqual(draft.copyConfirmation, copied)
            XCTAssertEqual(draft.copyAccessibilityLabel, reportCopied)
        }
    }

    #if os(iOS)
    func testFailedMailWaitsForSheetDismissalThenOffersLocalFallback() throws {
        let reporter = makeReporter { _, _ in XCTFail("Mail failure must not open another app") }
        reporter.completeMail(result: .failed, error: nil)
        XCTAssertNil(reporter.failure, "Do not present two sheets at once")
        reporter.mailSheetDismissed()
        let failure = try XCTUnwrap(reporter.failure)
        XCTAssertTrue(failure.message.contains("Mail could not queue your feedback"))
        XCTAssertTrue(failure.reportText.contains(FeedbackHelper.supportEmail))
        XCTAssertTrue(failure.reportText.contains(FeedbackHelper.diagnosticsBlock))
        reporter.failure = nil
        reporter.mailSheetDismissed()
        XCTAssertNil(reporter.failure, "Consume pending completion exactly once")
    }

    func testMailErrorIsFailureEvenWithNonFailedResultAndIsNotExposed() throws {
        let reporter = makeReporter { _, _ in XCTFail("No external fallback") }
        let error = NSError(domain: "test", code: 1, userInfo: [NSLocalizedDescriptionKey: "SECRET_ERROR_TEXT"])
        reporter.completeMail(result: .sent, error: error)
        reporter.mailSheetDismissed()
        let failure = try XCTUnwrap(reporter.failure)
        XCTAssertFalse(failure.message.contains("SECRET_ERROR_TEXT"))
        XCTAssertFalse(failure.reportText.contains("SECRET_ERROR_TEXT"))
    }

    func testSentCancelledAndSavedMailDoNotProduceFailure() {
        for result in [MFMailComposeResult.sent, .cancelled, .saved] {
            let reporter = makeReporter { _, _ in XCTFail("No external fallback") }
            reporter.completeMail(result: result, error: nil)
            reporter.mailSheetDismissed()
            XCTAssertNil(reporter.failure)
        }
    }

    func testCancelledSheetWithoutCompletionDoesNotProduceFailure() {
        let reporter = makeReporter { _, _ in XCTFail("No external fallback") }
        reporter.mailSheetDismissed()
        XCTAssertNil(reporter.failure)
    }
    #endif
}
