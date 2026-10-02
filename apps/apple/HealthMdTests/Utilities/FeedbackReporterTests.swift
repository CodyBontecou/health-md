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

    private func makeReporter(opener: @escaping FeedbackReporter.Opener) -> FeedbackReporter {
        let reporter = FeedbackReporter(opener: opener)
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
