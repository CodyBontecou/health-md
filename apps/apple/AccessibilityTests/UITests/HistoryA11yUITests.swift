import XCTest

@objc(HistoryA11yUITests)
final class HistoryA11yUITests: A11yUITestCase {
    /// SwiftUI AX nodes are virtual: in-process UIView enumeration cannot inspect
    /// their identifiers. Preserve the original exact assertions at the native
    /// accessibility-server seam, including the real action and preview/execution split.
    func testProductionHistoryContainerRetainsDistinctMessageAndRealActionIdentifiers() {
        for (size, theme) in [("large", "light"), ("accessibility5", "dark")] {
            let app = launchScenario("history", size: size, theme: theme, width: 320)
            let card = app.descendants(matching: .any).matching(identifier: "export.historyWarning")
            XCTAssertTrue(card.firstMatch.waitForExistence(timeout: 5))
            XCTAssertEqual(card.count, 1, "One container owns its ID, without overwriting child IDs")
            let message = app.staticTexts["export.historyWarning.message"]
            XCTAssertTrue(message.exists)
            XCTAssertTrue(message.label.contains("Empty data and completed queries do not prove full history"))
            let review = app.buttons["export.historyWarning.reviewAccess"]
            XCTAssertTrue(review.exists)
            XCTAssertTrue(app.buttons["export.historyWarning.details"].exists)
            XCTAssertFalse(app.staticTexts["export.historyWarning.execution"].exists, "Preview remains distinct from execution")
            reveal(review, in: app)
            // AX subtracts global CGRect coordinates; nominal 44pt measured
            // 43.99999999999997. Permit only floating-point round-off, not pixels.
            XCTAssertGreaterThanOrEqual(review.frame.height + 0.000_001, 44)
            tapEdge(review, in: app)
            XCTAssertEqual(app.staticTexts["a11y.history.reviews"].label, "Reviews: 1")
            let details = app.buttons["export.historyWarning.details"]
            reveal(details, in: app)
            details.tap()
            XCTAssertTrue(app.staticTexts.matching(NSPredicate(format: "label CONTAINS %@", "Selected metrics: steps"))
                .firstMatch.waitForExistence(timeout: 5))
            saveScreenshot(app, name: "history-distinct-identifiers-\(size)-\(theme)")
            app.terminate()
        }
    }

    func testExecutionDisclosureIsIndependentlyAccessibleAndDoesNotClaimFullHistory() {
        let app = launchScenario("history", width: 320)
        let show = app.buttons["a11y.history.showExecution"]
        XCTAssertTrue(show.waitForExistence(timeout: 5))
        show.tap()
        let execution = app.staticTexts["export.historyWarning.execution"]
        XCTAssertTrue(execution.waitForExistence(timeout: 5))
        XCTAssertTrue(execution.label.contains("Query completion is not proof of full history"))
        XCTAssertTrue(app.staticTexts["export.historyWarning.message"].exists)
        XCTAssertTrue(app.buttons["export.historyWarning.reviewAccess"].exists)
        XCTAssertTrue(app.buttons["export.historyWarning.details"].exists)
        XCTAssertEqual(app.descendants(matching: .any).matching(identifier: "export.historyWarning").count, 1)
    }
}
