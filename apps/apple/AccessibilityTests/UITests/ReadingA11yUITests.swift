import XCTest

/// All launches use the production-backed isolated `reading` scenario.
/// Counter assertions are component dispatch evidence, not HealthKit or pairing proof.
final class ReadingA11yUITests: A11yUITestCase {
    private struct Display {
        var size = "large"
        var theme = "light"
        var locale = "en_US"
        var width: CGFloat = 320
        var height: CGFloat = 640
    }

    private var displays: [Display] { [
        Display(),
        Display(size: "xxxLarge"),
        Display(size: "accessibility1"),
        Display(size: "accessibility5"),
        Display(size: "accessibility5", theme: "dark"),
        Display(width: 280, height: 480),
        Display(size: "accessibility5", width: 280, height: 280),
        Display(size: "accessibility5", theme: "dark", locale: "de_DE", height: 480),
        Display(size: "accessibility5", theme: "dark", locale: "ar", height: 480),
        Display(size: "accessibility5", locale: "ja_JP")
    ] }

    private func app(_ display: Display = Display()) -> XCUIApplication {
        let app = launchScenario("reading", size: display.size, theme: display.theme, locale: display.locale, width: display.width, height: display.height)
        XCTAssertTrue(app.tabBars.buttons["Metrics"].waitForExistence(timeout: 10))
        return app
    }

    private func assertCount(_ id: String, _ expected: Int, in app: XCUIApplication) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", String(expected)), object: app.staticTexts[id])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed, id)
    }

    func testMetricLabelAndSwitchDispatchOnceAndExpansionNeverSelects() {
        let app = app()
        let metric = app.switches["reading.metric"]
        XCTAssertEqual(app.switches.matching(identifier: "reading.metric").count, 1)
        XCTAssertEqual(metric.label, "Heart Rate Variability During Walking, SDNN · ms")
        XCTAssertEqual(metric.value as? String, "Disabled")
        XCTAssertGreaterThan(metric.frame.width, 200, "The native switch includes its visible name, not just a thumb")
        tapReadingEdge(metric, in: app)
        assertCount("reading.metric-calls", 1, in: app)
        assertCount("reading.metric-attempts", 1, in: app)
        XCTAssertEqual(metric.value as? String, "Enabled")
        exposeEdge(metric, bottom: false, in: app)
        metric.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        assertCount("reading.metric-calls", 2, in: app)
        XCTAssertEqual(metric.value as? String, "Disabled")

        let category = app.buttons["reading.category"]
        XCTAssertEqual(category.descendants(matching: .switch).count, 0, "The status pill is not a bulk checkbox")
        tapReadingEdge(category, in: app)
        assertCount("reading.expansion-calls", 1, in: app)
        assertCount("reading.metric-calls", 2, in: app)
        XCTAssertEqual(category.value as? String, "Collapsed")
        XCTAssertFalse(metric.exists)
        tapReadingEdge(category, in: app)
        assertCount("reading.expansion-calls", 2, in: app)
        XCTAssertEqual(category.value as? String, "Expanded")
        XCTAssertFalse(app.switches["reading.metric.unavailable"].isEnabled)
        assertCount("reading.metric-attempts", 2, in: app)
    }

    func testLongMetricAndCategoryCopyAcrossTextViewportThemeAndLocaleMatrix() {
        for display in displays {
            let app = app(display)
            let category = app.buttons["reading.category"]
            XCTAssertEqual(category.value as? String, "Expanded")
            captureReadingSlices(category, name: "category-\(display.size)-\(display.locale)-\(display.theme)-\(display.width)x\(display.height)", in: app)
            let metric = app.switches["reading.metric"]
            XCTAssertTrue(metric.label.contains("SDNN · ms"))
            XCTAssertFalse(metric.label.contains("…"))
            captureReadingSlices(metric, name: "metric-\(display.size)-\(display.locale)-\(display.theme)-\(display.width)x\(display.height)", in: app)
            tapReadingEdge(metric, in: app)
            assertCount("reading.metric-calls", 1, in: app)
            assertCount("reading.expansion-calls", 0, in: app)
            app.terminate()
        }
    }

    func testSettingsDescriptionUsesFullInnerWidthAcrossDisplayMatrix() {
        for display in displays {
            let app = app(display)
            app.tabBars.buttons["Settings"].tap()
            let description = app.staticTexts["reading.settings.probe.description"]
            captureReadingSlices(description, name: "settings-copy-\(display.size)-\(display.locale)-\(display.theme)-\(display.width)x\(display.height)", in: app)
            XCTAssertTrue(description.label.hasSuffix("It is not used for advertising or cross-app tracking."))
            assertFullWidthReading(description, reference: app.staticTexts["reading.settings.description-reference"], in: app)
            let protectionDescription = app.staticTexts["reading.protection.description"]
            captureReadingSlices(protectionDescription, name: "protection-copy-\(display.size)-\(display.locale)-\(display.theme)", in: app)
            assertFullWidthReading(protectionDescription, reference: app.staticTexts["reading.protection.description-reference"], in: app)
            XCTAssertEqual(app.switches.matching(identifier: "configurationProtection.toggle").count, 1)
            app.terminate()
        }
    }

    func testSettingsActionRetainsFullExplanationAndOneCallback() {
        let app = app()
        app.tabBars.buttons["Settings"].tap()
        let row = app.buttons["reading.settings.action"]
        XCTAssertTrue(row.label.hasPrefix("Privacy Policy, Analytics never includes"))
        XCTAssertTrue(row.label.hasSuffix("It is not used for advertising or cross-app tracking."))
        XCTAssertEqual(row.value as? String, "Configured")
        tapReadingEdge(row, in: app)
        assertCount("reading.setting-calls", 1, in: app)
        assertCount("reading.protection-calls", 0, in: app)
    }

    func testRealProtectionManagerBlocksSyntheticMutationsButNotExpansion() {
        let app = app(Display(size: "accessibility1"))
        app.tabBars.buttons["Settings"].tap()
        let lock = app.switches["configurationProtection.toggle"]
        XCTAssertEqual(lock.label, "Prevent Accidental Changes")
        tapReadingEdge(lock, in: app)
        assertCount("reading.protection-calls", 1, in: app)
        XCTAssertEqual(lock.value as? String, "On")
        let protectedRegion = app.buttons["configurationProtection.protectedRegion"]
        tapReadingEdge(protectedRegion, in: app)
        assertCount("reading.blocked-calls", 1, in: app)
        assertCount("reading.setting-calls", 0, in: app)

        app.tabBars.buttons["Metrics"].tap()
        tapReadingEdge(app.switches["reading.metric"], in: app)
        assertCount("reading.metric-attempts", 1, in: app)
        assertCount("reading.metric-calls", 0, in: app)
        XCTAssertEqual(app.switches["reading.metric"].value as? String, "Disabled")
        tapReadingEdge(app.buttons["reading.category"], in: app)
        assertCount("reading.expansion-calls", 1, in: app)

        app.tabBars.buttons["Settings"].tap()
        tapReadingEdge(lock, in: app)
        assertCount("reading.protection-calls", 2, in: app)
        XCTAssertEqual(lock.value as? String, "Off")
        XCTAssertFalse(protectedRegion.exists)
        tapReadingEdge(app.buttons["reading.settings.action"], in: app)
        assertCount("reading.setting-calls", 1, in: app)
        app.tabBars.buttons["Metrics"].tap()
        tapReadingEdge(app.buttons["reading.category"], in: app)
        tapReadingEdge(app.switches["reading.metric"], in: app)
        assertCount("reading.metric-calls", 1, in: app)
        assertCount("reading.metric-attempts", 2, in: app)
    }

    func testHostPortAndSeparateActionsAcrossDisplayMatrix() {
        for display in displays {
            let app = app(display)
            app.tabBars.buttons["Connection"].tap()
            for (id, value) in [("reading.host", "synthetic-mac-with-a-long-name.example.invalid"), ("reading.port", "65535")] {
                let field = app.textFields[id]
                exposeEdge(field, bottom: false, in: app)
                XCTAssertGreaterThanOrEqual(field.frame.width, 44)
                XCTAssertGreaterThanOrEqual(field.frame.height, 44)
                XCTAssertEqual(field.frame.width, (owningScroll(field, in: app)?.frame.width ?? 0) - 32, accuracy: 2)
                XCTAssertEqual(field.value as? String, value)
                XCTAssertLessThanOrEqual(app.staticTexts["\(id).label"].frame.maxY, field.frame.minY)
                let readingValue = app.staticTexts["\(id).value"]
                XCTAssertEqual(readingValue.label, value)
                captureReadingSlices(readingValue, name: "\(id)-\(display.size)-\(display.locale)-\(display.theme)-\(display.width)x\(display.height)", in: app)
            }
            tapReadingEdge(app.buttons["reading.connection.primary"], in: app)
            assertCount("reading.connect-calls", 1, in: app)
            assertCount("reading.disconnect-calls", 0, in: app)
            tapReadingEdge(app.buttons["reading.connection.secondary"], in: app)
            assertCount("reading.disconnect-calls", 1, in: app)
            assertCount("reading.connect-calls", 1, in: app)
            XCTAssertFalse(app.buttons["reading.connection.disabled.primary"].isEnabled)
            app.terminate()
        }
    }

    func testNativeKeyboardEditingKeepsCompleteReadbackAndReachableAction() {
        let app = app()
        app.tabBars.buttons["Connection"].tap()
        let host = app.textFields["reading.host"]
        tapReadingEdge(host, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        // Send keys to the CURRENT native responder. Naming a field in typeText
        // must not repair a failed padded-edge focus tap behind this assertion.
        app.typeText("qa")
        let keyboardVisible = XCTNSPredicateExpectation(predicate: NSPredicate { [self] _, _ in
            app.keyboards.allElementsBoundByIndex.contains { keyboard in
                let visible = keyboard.frame.intersection(owningWindow(keyboard, in: app).frame)
                return visible.width >= 44 && visible.height >= 44
            }
        }, object: app)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardVisible], timeout: 5), .completed)
        let editedHost = host.value as? String
        XCTAssertTrue(editedHost?.contains("qa") == true)
        XCTAssertEqual(app.staticTexts["reading.host.value"].label, editedHost)
        saveScreenshot(app, name: "reading-host-native-keyboard")

        // Remaining space is bounded by the actual native keyboard, not by a
        // guessed IME height or the synthetic container's first scroll alone.
        let port = app.textFields["reading.port"]
        let originalPort = port.value as? String
        tapReadingEdge(port, in: app)
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        app.typeText("7")
        XCTAssertNotEqual(port.value as? String, originalPort)
        XCTAssertEqual((port.value as? String)?.count, (originalPort?.count ?? 0) + 1)
        XCTAssertEqual(host.value as? String, editedHost)
        XCTAssertEqual(app.staticTexts["reading.port.value"].label, port.value as? String)
        assertCount("reading.connect-calls", 0, in: app)
        assertCount("reading.disconnect-calls", 0, in: app)
        tapReadingEdge(app.buttons["reading.connection.primary"], in: app)
        assertCount("reading.connect-calls", 1, in: app)
        let keyboardGone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [keyboardGone], timeout: 5), .completed)
        saveScreenshot(app, name: "reading-connection-after-keyboard-dismissal")
    }

    func testLargestTextConnectionActionsAreFullWidthAndOrdered() {
        let app = app(Display(size: "accessibility5", theme: "dark", width: 280, height: 280))
        app.tabBars.buttons["Connection"].tap()
        let primary = app.buttons["reading.connection.primary"]
        let secondary = app.buttons["reading.connection.secondary"]
        exposeEdge(primary, bottom: false, in: app)
        XCTAssertEqual(primary.label, "Connect to the selected Mac")
        XCTAssertEqual(secondary.label, "Disconnect from the selected Mac")
        XCTAssertEqual(primary.frame.width, secondary.frame.width, accuracy: 1)
        XCTAssertGreaterThanOrEqual(secondary.frame.minY - primary.frame.maxY, 7)
        tapReadingEdge(primary, in: app)
        tapReadingEdge(secondary, in: app)
        assertCount("reading.connect-calls", 1, in: app)
        assertCount("reading.disconnect-calls", 1, in: app)
    }

    private func assertFullWidthReading(_ text: XCUIElement, reference: XCUIElement, in app: XCUIApplication) {
        XCTAssertEqual(text.label, reference.label)
        // AX gives glyph bounds, not allocated width. Compare real full-width
        // native text at the same font, locale and parent width instead of
        // requiring the last glyph to fill an arbitrary percentage of a row.
        XCTAssertEqual(text.frame.width, reference.frame.width, accuracy: 1)
        XCTAssertEqual(text.frame.height, reference.frame.height, accuracy: 1)
        XCTAssertLessThanOrEqual(text.frame.width, (owningScroll(text, in: app)?.frame.width ?? 0) - 64 + 1)
    }

    // Tall reading rows legitimately span a short viewport. Inspect/capture both
    // ends using their actual ancestor, measured allocation and keyboard chrome.

    private func exposeEdge(_ element: XCUIElement, bottom: Bool, in app: XCUIApplication) {
        XCTAssertTrue(element.waitForExistence(timeout: 5))
        guard let scroll = owningScroll(element, in: app) else { XCTFail("No actual reading scroll owner"); return }
        var previousFrame: CGRect?
        var stalledDrags = 0
        for _ in 0..<80 {
            let viewport = readingViewport(scroll, in: app)
            let frame = element.frame
            let y = bottom ? frame.maxY - 4 : frame.minY + 4
            if viewport.contains(CGPoint(x: frame.midX, y: y)) && element.isHittable {
                XCTAssertGreaterThan(frame.width, 0)
                XCTAssertGreaterThan(frame.height, 0)
                XCTAssertGreaterThanOrEqual(frame.minX, viewport.minX - 1)
                XCTAssertLessThanOrEqual(frame.maxX, viewport.maxX + 1)
                return
            }
            XCTAssertGreaterThan(viewport.height, 44, "Not enough native reading space")
            stalledDrags = previousFrame == frame ? stalledDrags + 1 : 0
            previousFrame = frame
            let downward = y < viewport.minY
            let remaining = downward ? viewport.minY - y : y - viewport.maxY
            dragPage(scroll, viewport: viewport, downward: downward,
                     distance: max(0, remaining) + min(CGFloat(stalledDrags) * 20, 100))
        }
        XCTFail("Reading edge not reachable inside the real scroll/keyboard viewport: \(element)")
    }

    private func tapReadingEdge(_ element: XCUIElement, in app: XCUIApplication) {
        reveal(element, in: app)
        XCTAssertGreaterThanOrEqual(element.frame.width, 44)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
        // A rounded native button's bounding-box corner is not its painted
        // edge. Tap the real top edge, as the other native action suites do.
        element.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 3)).tap()
    }

    private func captureReadingSlices(_ element: XCUIElement, name: String, in app: XCUIApplication) {
        exposeEdge(element, bottom: false, in: app)
        saveScreenshot(app, name: "\(name)-start")
        exposeEdge(element, bottom: true, in: app)
        saveScreenshot(app, name: "\(name)-end")
    }
}
