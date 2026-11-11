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

    private func exerciseLocalRecovery(title: String, destination: String, supportAction: String) {
        XCTAssertTrue(app.staticTexts[title].waitForExistence(timeout: 5))
        let editor = app.textViews["feedback.reportText"]
        XCTAssertTrue(editor.waitForExistence(timeout: 5))
        let template = editor.value as? String ?? ""
        XCTAssertTrue(template.contains(destination))
        XCTAssertTrue(template.contains("Problem:"))

        let report = "Synthetic QA report 169\nExpected: local recovery.\nSteps: edit, copy, paste."
        replaceText(in: editor, with: report)
        XCTAssertEqual(editor.value as? String, report)
        let copy = app.buttons["feedback.copyReport"]
        XCTAssertTrue(copy.isHittable)
        copy.tap()
        XCTAssertTrue(app.staticTexts["Report copied"].waitForExistence(timeout: 5))

        // Editing must invalidate the persistent visible/accessibility confirmation.
        replaceText(in: editor, with: "")
        let noConfirmation = expectation(
            for: NSPredicate(format: "exists == false"), evaluatedWith: app.staticTexts["Report copied"]
        )
        wait(for: [noConfirmation], timeout: 5)
        XCTAssertFalse(app.staticTexts["Copied"].exists)

        // Use the native edit menu, not a test-process clipboard read or injected paste action.
        editor.press(forDuration: 1)
        let paste = menuAction("Paste")
        XCTAssertTrue(paste.waitForExistence(timeout: 5))
        paste.tap()
        let pasted = expectation(for: NSPredicate(format: "value == %@", report), evaluatedWith: editor)
        wait(for: [pasted], timeout: 5)
        XCTAssertEqual(editor.value as? String, report, "Production Copy must preserve exact multiline editor text")
        XCTAssertFalse(app.staticTexts["Report copied"].exists, "Pasting is another edit, not a copy")
        copy.tap()
        XCTAssertTrue(app.staticTexts["Report copied"].waitForExistence(timeout: 5))
        app.buttons["feedback.close"].tap()
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

    private func replaceText(in editor: XCUIElement, with text: String) {
        editor.tap()
        editor.press(forDuration: 1)
        let selectAll = menuAction("Select All")
        XCTAssertTrue(selectAll.waitForExistence(timeout: 5))
        selectAll.tap()
        editor.typeText(text.isEmpty ? XCUIKeyboardKey.delete.rawValue : text)
    }

    private func menuAction(_ title: String) -> XCUIElement {
        app.menuItems[title].exists ? app.menuItems[title] : app.buttons[title]
    }
}
