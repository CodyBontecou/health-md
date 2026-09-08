import XCTest

final class A11yFoundationUITests: A11yUITestCase {
    private func app(size: String = "large", theme: String = "light") -> XCUIApplication {
        let app = launchScenario(size: size, theme: theme)
        XCTAssertTrue(app.staticTexts["a11y.callback-count"].waitForExistence(timeout: 10))
        return app
    }

    func testActiveButtonsHaveRealEdgeTargetsAndPreservedCallbacks() {
        let app = app()
        tapEdge(app.buttons["a11y.secondary"], in: app)
        XCTAssertEqual(app.staticTexts["a11y.callback-count"].label, "Callbacks: 1")
        tapEdge(app.buttons["a11y.destructive"], in: app)
        XCTAssertEqual(app.staticTexts["a11y.callback-count"].label, "Callbacks: 11")
        tapEdge(app.buttons["a11y.primary"], in: app)
        XCTAssertEqual(app.staticTexts["a11y.callback-count"].label, "Callbacks: 111")
        XCTAssertFalse(app.buttons["a11y.disabled"].isEnabled)
        XCTAssertFalse(app.buttons["a11y.loading"].isEnabled)
        tapEdge(app.buttons["a11y.icon"], in: app)
        XCTAssertEqual(app.staticTexts["a11y.callback-count"].label, "Callbacks: 10111")
    }

    func testLargestTextActionsRemainReachableWithFullLabels() {
        let app = app(size: "accessibility5", theme: "dark")
        let secondary = app.buttons["a11y.secondary"]
        XCTAssertEqual(secondary.label, "Choose a different destination folder")
        tapEdge(secondary, in: app)
        XCTAssertEqual(app.staticTexts["a11y.callback-count"].label, "Callbacks: 1")
        tapEdge(app.buttons["a11y.destructive"], in: app)
        XCTAssertEqual(app.staticTexts["a11y.callback-count"].label, "Callbacks: 11")
        let capture = XCTAttachment(screenshot: app.screenshot())
        capture.name = "production-buttons-accessibility5-dark"
        capture.lifetime = .keepAlways
        add(capture)
    }

    func testStatusActionsInvokeOnlyTheirOwnCallbacks() {
        let app = app()
        tapEdge(app.buttons["export.preview-file"], in: app)
        XCTAssertEqual(app.staticTexts["a11y.callback-count"].label, "Callbacks: 1000000")
        tapEdge(app.buttons["export.browse-folder"], in: app)
        XCTAssertEqual(app.staticTexts["a11y.callback-count"].label, "Callbacks: 11000000")
        tapEdge(app.buttons["Dismiss export status"], in: app)
        let dismissed = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", "Callbacks: 11100000"), object: app.staticTexts["a11y.callback-count"])
        XCTAssertEqual(XCTWaiter.wait(for: [dismissed], timeout: 3), .completed)
    }

    func testProductionRendersAtDefaultStandardAX1AX5InBothThemes() {
        for size in ["large", "xxxLarge", "accessibility1", "accessibility5"] {
            for theme in ["light", "dark"] {
                let app = app(size: size, theme: theme)
                XCTAssertTrue(app.staticTexts["a11y.heading"].isHittable)
                let attachment = XCTAttachment(screenshot: app.screenshot())
                attachment.name = "foundation-\(size)-\(theme)"
                attachment.lifetime = .keepAlways
                add(attachment)
                app.terminate()
            }
        }
    }
}
