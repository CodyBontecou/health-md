import XCTest

/// Real local recovery UI/pasteboard, with only the external handoff rejected synthetically.
/// These journeys neither submit feedback nor qualify configured Mail/VoiceOver behavior.
final class FeedbackJourneyUITests: XCTestCase {
    private var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        if testRun?.hasSucceeded == false, let app {
            let tree = XCTAttachment(string: app.debugDescription)
            tree.name = "feedback-failure-hierarchy"
            tree.lifetime = .keepAlways
            add(tree)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "feedback-failure-screen"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        app?.terminate()
        app = nil
    }

    func testRejectedGitHubHandoffCanEditCopyAndPasteExactReport() {
        launchSupport(scenario: "rejected-handoffs")
        openSupportAction("feedback.reportBug")
        exerciseLocalRecovery(title: "Couldn’t open GitHub", destination: "GitHub: https://github.com/", supportAction: "feedback.reportBug")
    }

    func testRejectedEmailHandoffCanEditCopyAndPasteExactReport() {
        launchSupport(scenario: "rejected-handoffs")
        openSupportAction("feedback.sendFeedback")
        exerciseLocalRecovery(title: "Couldn’t open Mail", destination: "To: cody@isolated.tech", supportAction: "feedback.sendFeedback")
    }

    func testSyntheticMailFailurePresentsFallbackAfterSheetDismissal() {
        launchSupport(scenario: "failed-mail-sheet")
        openSupportAction("feedback.sendFeedback")
        let completion = app.buttons["feedback.simulateMailFailure"]
        XCTAssertTrue(completion.waitForExistence(timeout: 5))
        XCTAssertFalse(app.textViews["feedback.reportText"].exists)
        completion.tap()
        XCTAssertTrue(app.staticTexts["Mail couldn’t send"].waitForExistence(timeout: 5))
        XCTAssertFalse(completion.exists, "The synthetic composer must be dismissed before recovery")
        assertFailureExplanation(containing: "Text entered in Mail is not available to Health.md; re-enter it below if needed.")
        XCTAssertTrue(app.textViews["feedback.reportText"].exists)
        app.buttons["feedback.close"].tap()
        assertReturnedToSupport(action: "feedback.sendFeedback")
    }

    private func launchSupport(scenario: String) {
        app = UITestLaunchHelper.configuredApp()
        app.launchEnvironment["UITEST_FEEDBACK_SCENARIO"] = scenario
        app.launchArguments += ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        UITestLaunchHelper.openSettingsTab(in: app)
    }

    private func openSupportAction(_ identifier: String) {
        let action = app.buttons[identifier]
        for _ in 0..<6 {
            if action.exists && action.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(action.exists && action.isHittable, "Feedback action must be reachable from support")
        action.tap()
    }

    private func assertFailureExplanation(containing expected: String) {
        let explanation = app.staticTexts["feedback.failureMessage"]
        XCTAssertTrue(explanation.waitForExistence(timeout: 5))
        XCTAssertTrue(explanation.label.contains(expected), "Show the failure-specific recovery instructions")
    }

    private func exerciseLocalRecovery(title: String, destination: String, supportAction: String) {
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        assertFailureExplanation(containing: "You can write and copy a report here")
        let editor = app.textViews["feedback.reportText"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let template = editor.value as? String ?? ""
        XCTAssertTrue(template.contains(destination))
        XCTAssertTrue(template.contains("Problem:"))

        let addition = "\nSynthetic QA report 169\nExpected: local recovery.\nSteps: edit, copy, paste.\n"
        editor.tap()
        editor.typeText(addition)
        let firstEdit = editor.value as? String ?? ""
        XCTAssertTrue(firstEdit.contains(addition))
        XCTAssertTrue(firstEdit.contains(destination))
        XCTAssertNotEqual(firstEdit, template)
        let copy = app.buttons["feedback.copyReport"]
        XCTAssertTrue(copy.isHittable)
        copy.tap()
        XCTAssertTrue(app.staticTexts["Report copied"].waitForExistence(timeout: 5))

        // Editing must invalidate the persistent visible/accessibility confirmation.
        let secondAddition = "\nSynthetic edit after copy.\n"
        editor.typeText(secondAddition)
        let report = editor.value as? String ?? ""
        XCTAssertTrue(report.contains(addition))
        XCTAssertTrue(report.contains(secondAddition))
        XCTAssertTrue(report.contains(destination))
        XCTAssertNotEqual(report, firstEdit)
        let noConfirmation = expectation(
            for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Report copied"]
        )
        wait(for: [noConfirmation], timeout: 5)
        XCTAssertFalse(app.staticTexts["Copied"].exists)
        copy.tap()
        XCTAssertTrue(app.staticTexts["Report copied"].waitForExistence(timeout: 5))
        app.buttons["feedback.close"].tap()
        assertReturnedToSupport(action: supportAction)

        openSupportAction("feedback.openPasteCheck")
        let pasteEditor = app.textViews["feedback.pasteCheckText"]
        XCTAssertTrue(pasteEditor.waitForExistence(timeout: 5))
        XCTAssertEqual(pasteEditor.value as? String, "", "Paste destination must start empty")

        // Use the native edit menu, not a test-process clipboard read or injected paste action.
        pasteEditor.tap()
        pasteEditor.press(forDuration: 1)
        let paste = menuAction("Paste")
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        let pasted = expectation(for: NSPredicate(format: "value == %@", report), evaluatedWith: pasteEditor)
        wait(for: [pasted], timeout: 5)
        XCTAssertEqual(pasteEditor.value as? String, report, "Production Copy must preserve exact multiline editor text")
        app.buttons["feedback.closePasteCheck"].tap()
        let pasteCheckDismissed = expectation(
            for: NSPredicate(format: "exists == false"), evaluatedWith: pasteEditor
        )
        wait(for: [pasteCheckDismissed], timeout: 5)
        assertReturnedToSupport(action: supportAction)
    }

    private func assertReturnedToSupport(action: String) {
        let dismissed = expectation(
            for: NSPredicate(format: "exists == false"), evaluatedWith: app.textViews["feedback.reportText"]
        )
        let supportAvailable = expectation(
            for: NSPredicate(format: "exists == true AND isHittable == true"), evaluatedWith: app.buttons[action]
        )
        wait(for: [dismissed, supportAvailable], timeout: 5)
    }

    private func menuAction(_ title: String) -> XCUIElement {
        app.menuItems[title].exists ? app.menuItems[title] : app.buttons[title]
    }
}
