import XCTest

/// Shared by isolated production-component UI suites. All targets use synthetic
/// state; this does not launch the shipping Health.md app or change OS settings.
class A11yUITestCase: XCTestCase {
    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    /// Use the real software keyboard's AX key spelling (iOS 26 uses "next",
    /// identifier "Next:"). Dismiss only its known first-run typing tutorial.
    func keyboardKey(_ label: String, in app: XCUIApplication) -> XCUIElement {
        let introduction = app.otherElements["UIContinuousPathIntroductionView"]
        if introduction.exists {
            let continuation = introduction.buttons["Continue"]
            XCTAssertTrue(continuation.isHittable)
            continuation.tap()
        }
        let key = app.keyboards.buttons.matching(NSPredicate(format: "label ==[c] %@", label)).firstMatch
        XCTAssertTrue(key.waitForExistence(timeout: 5))
        return key
    }

    func assertKeyboardTarget(_ key: XCUIElement, in app: XCUIApplication) {
        let keyboard = app.keyboards.firstMatch
        guard let window = app.windows.allElementsBoundByIndex.first(where: { $0.keyboards.firstMatch.exists }) else {
            XCTFail("No native keyboard owner window")
            return
        }
        // Native bottom-row AX hit slop extends 7pt below the SE window on iOS
        // 26.5. Require an actual visible >=44pt target, not the offscreen slop.
        let visible = key.frame.intersection(keyboard.frame).intersection(window.frame)
        XCTAssertGreaterThanOrEqual(visible.width, 44)
        XCTAssertGreaterThanOrEqual(visible.height, 44)
        XCTAssertTrue(key.isHittable)
    }

    func launchScenario(
        _ scenario: String = "foundation",
        size: String = "large",
        theme: String = "light",
        locale: String = "en_US",
        width: CGFloat? = nil,
        height: CGFloat? = nil
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["A11Y_SCENARIO"] = scenario
        app.launchEnvironment["A11Y_SIZE"] = size
        app.launchEnvironment["A11Y_THEME"] = theme
        app.launchEnvironment["A11Y_LOCALE"] = locale
        if let width { app.launchEnvironment["A11Y_WIDTH"] = String(describing: width) }
        if let height { app.launchEnvironment["A11Y_HEIGHT"] = String(describing: height) }
        app.launch()
        return app
    }

    func reveal(_ element: XCUIElement, in app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<30 {
            let viewport = scroll.frame.intersection(app.windows.firstMatch.frame).insetBy(dx: 0, dy: 4)
            if element.isHittable && viewport.contains(element.frame) { return }
            // Window bounds alone are insufficient: a row can be behind chrome.
            let downward = element.frame.minY < viewport.minY
            // Drag the outer gutter: its center may be a native wheel/editor
            // that correctly consumes gestures instead of scrolling the page.
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: downward ? 0.7 : 0.3))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Target not fully reachable in scroll viewport: \(element)")
    }

    func tapEdge(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 3)).tap()
    }

    func saveScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
