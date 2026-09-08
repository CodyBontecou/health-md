import XCTest

/// ADDED / NOT RUN. Native synthetic-component tests, not proof of scheduling,
/// HealthKit, billing, live configuration protection or history deletion.
final class SchedulingA11yUITests: A11yUITestCase {
    private struct Display {
        let size: String
        let theme: String
        let locale: String
        let width: CGFloat
        let height: CGFloat
    }

    private let displays: [Display] = [
        Display(size: "large", theme: "light", locale: "en_US", width: 320, height: 640),
        Display(size: "large", theme: "dark", locale: "en_US", width: 240, height: 480),
        Display(size: "xxxLarge", theme: "light", locale: "en_US", width: 320, height: 480),
        Display(size: "accessibility1", theme: "dark", locale: "en_US", width: 320, height: 640),
        Display(size: "accessibility5", theme: "light", locale: "en_US", width: 320, height: 640),
        Display(size: "accessibility5", theme: "dark", locale: "de_DE", width: 280, height: 480),
        Display(size: "accessibility5", theme: "dark", locale: "ar", width: 280, height: 480),
        Display(size: "accessibility5", theme: "light", locale: "ja_JP", width: 320, height: 640)
    ]

    override func tearDown() {
        XCUIDevice.shared.orientation = .portrait
        super.tearDown()
    }

    private func open(_ page: String, display: Display? = nil) -> XCUIApplication {
        let d = display ?? displays[4]
        let app = launchScenario("scheduling", size: d.size, theme: d.theme, locale: d.locale, width: d.width, height: d.height)
        let link = app.buttons[page].firstMatch
        XCTAssertTrue(link.waitForExistence(timeout: 10))
        link.tap()
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 5))
        return app
    }

    func testAdaptiveChoicesKeepEveryNativeMenuOptionAndExactCallbacks() {
        let app = open("Choices")
        let cases: [(String, [String], String)] = [
            ("scheduling.frequency", ["Daily", "Weekly", "Custom"], "Weekly"),
            ("scheduling.refresh", ["Every 3 hours", "Every 6 hours", "Every 12 hours"], "Every 12 hours"),
            ("scheduling.writeMode", ["Overwrite", "Append", "Update"], "Append")
        ]
        for (id, options, selected) in cases {
            let menu = app.buttons[id].firstMatch
            tapEdge(menu, in: app)
            for option in options { XCTAssertTrue(app.buttons[option].exists, "Missing full native menu option: \(option)") }
            tapNativeMenuItem(selected, in: app)
            XCTAssertEqual(menu.value as? String, selected)
        }
        assertState("frequency:Weekly refresh:12 mode:Append changes:3", id: "scheduling.choices.state", in: app)
        saveScreenshot(app, name: "scheduling-full-choice-values-AX5")
    }

    func testChoiceReflowRespondsToWidthAloneAndKeepsStandardButtonCallbacks() {
        XCUIDevice.shared.orientation = .landscapeLeft
        let roomy = Display(size: "large", theme: "light", locale: "en_US", width: 568, height: 280)
        let wideApp = open("Choices", display: roomy)
        tapEdge(wideApp.buttons["Weekly"], in: wideApp)
        tapEdge(wideApp.buttons["Weekly"], in: wideApp)
        // Retain Picker semantics: tapping its current segment does not make
        // a second frequency mutation.
        assertState("frequency:Weekly refresh:3 mode:Update changes:1", id: "scheduling.choices.state", in: wideApp)
        wideApp.terminate()

        XCUIDevice.shared.orientation = .portrait
        let narrowApp = open("Choices", display: displays[1])
        let menu = narrowApp.buttons["scheduling.frequency"]
        XCTAssertEqual(menu.value as? String, "Daily")
        tapEdge(menu, in: narrowApp)
        tapNativeMenuItem("Weekly", in: narrowApp)
        assertState("frequency:Weekly refresh:3 mode:Update changes:1", id: "scheduling.choices.state", in: narrowApp)
        saveScreenshot(narrowApp, name: "scheduling-width-only-menu-default-font")
    }

    func testHourMinuteAndPeriodMenusRemainThreeIndependentActions() {
        let app = open("Time", display: displays[3])
        let hour = app.buttons["scheduling.hour"]
        let minute = app.buttons["scheduling.minute"]
        let period = app.buttons["scheduling.period"]
        XCTAssertEqual(hour.label, "Hour")
        XCTAssertEqual(minute.label, "Minute")
        XCTAssertEqual(period.label, "Period")
        tapEdge(hour, in: app)
        for value in 1...12 { XCTAssertTrue(app.buttons[String(value)].exists) }
        XCTAssertFalse(app.buttons["13"].exists)
        tapNativeMenuItem("12", in: app)
        assertState("hour:12/1 minute:55/0 period:PM/0 interval:364 lookback:1 info:0", id: "scheduling.time.state", in: app)

        tapEdge(minute, in: app)
        for value in stride(from: 0, to: 60, by: 5) { XCTAssertTrue(app.buttons[String(format: "%02d", value)].exists) }
        XCTAssertFalse(app.buttons["60"].exists)
        // Selecting the already-current minute must still invoke the legacy
        // Button callback once; it must never invoke Hour or Period.
        tapNativeMenuItem("55", in: app)
        tapEdge(period, in: app)
        XCTAssertTrue(app.buttons["AM"].exists)
        XCTAssertTrue(app.buttons["PM"].exists)
        saveScreenshot(app, name: "scheduling-native-period-menu")
        tapNativeMenuItem("AM", in: app)
        assertState("hour:12/1 minute:55/1 period:AM/1 interval:364 lookback:1 info:0", id: "scheduling.time.state", in: app)
    }

    func testNumericControlsRespectCallerBoundsAndInfoHasARealEdgeTarget() {
        let app = open("Time")
        let increment = app.buttons["scheduling.interval.increment"]
        let decrement = app.buttons["scheduling.interval.decrement"]
        tapEdge(increment, in: app)
        XCTAssertFalse(increment.isEnabled)
        XCTAssertEqual(app.staticTexts["scheduling.interval.value"].value as? String, "365")
        tapEdge(decrement, in: app)
        XCTAssertTrue(increment.isEnabled)
        let lower = app.buttons["scheduling.lookback.decrement"]
        reveal(lower, in: app)
        XCTAssertFalse(lower.isEnabled)
        tapEdge(app.buttons["schedule.todayRefresh.info"], in: app)
        assertState("hour:11/0 minute:55/0 period:PM/0 interval:364 lookback:1 info:1", id: "scheduling.time.state", in: app)
    }

    func testProfileEditEnableDeleteAndImmediateClearStayIndependentAcrossDisplays() {
        for display in displays {
            let app = open("Profiles", display: display)
            let name = app.staticTexts["scheduling.profile.name"]
            XCTAssertTrue(name.waitForExistence(timeout: 5))
            XCTAssertFalse(name.label.contains("…"))
            let edit = app.buttons["scheduling.profile.edit"]
            XCTAssertEqual(edit.label, "Edit schedule for \(name.label)")
            tapEdge(edit, in: app)
            assertState("edits:1 enables:0 enabled:true deletes:0 clears:0", id: "scheduling.profile.state", in: app)
            tapEdge(app.switches["scheduling.profile.enabled"], in: app)
            assertState("edits:1 enables:1 enabled:false deletes:0 clears:0", id: "scheduling.profile.state", in: app)
            tapEdge(app.buttons["scheduling.profile.delete"], in: app)
            assertState("edits:1 enables:1 enabled:false deletes:1 clears:0", id: "scheduling.profile.state", in: app)
            tapEdge(app.buttons["schedule.history.clear"], in: app)
            assertState("edits:1 enables:1 enabled:false deletes:1 clears:1", id: "scheduling.profile.state", in: app)
            // This verifies the heading's immediate callback, NOT a no-op
            // substitute for the screen's real guarded history deletion.
            XCTAssertFalse(app.alerts.firstMatch.exists)
            saveScreenshot(app, name: "scheduling-profile-actions-\(display.size)-\(display.locale)-\(display.width)")
            app.terminate()
        }
    }

    func testDatePresetsKeepFullLabelsExclusiveSelectionAndExactCallbacksAcrossDisplays() {
        let options = [("today", "Today"), ("yesterday", "Yesterday"), ("allTime", "All Time"), ("custom", "Custom")]
        for display in displays {
            let app = open("Dates", display: display)
            for (index, option) in options.enumerated() {
                let button = app.buttons["scheduling.date.\(option.0)"]
                XCTAssertEqual(button.label, option.1)
                // Includes the already-selected Today button: unlike a native
                // frequency Picker, a date preset dispatches on every tap.
                tapEdge(button, in: app)
                assertState("preset:\(option.0) changes:\(index + 1)", id: "scheduling.dates.state", in: app)
                for other in options {
                    XCTAssertEqual(app.buttons["scheduling.date.\(other.0)"].value as? String,
                                   other.0 == option.0 ? "Selected" : "Not selected")
                }
            }
            reveal(app.staticTexts["Start Date"].firstMatch, in: app)
            saveScreenshot(app, name: "scheduling-custom-date-labels-\(display.size)-\(display.locale)-\(display.width)")
            app.terminate()
        }
    }

    func testNativeDateAnchorsAndFullReadingValuesRemainReachable() {
        let app = open("Dates", display: displays[0])
        tapEdge(app.buttons["scheduling.date.custom"], in: app)
        for id in ["scheduling.date.start", "scheduling.date.end"] {
            let date = app.datePickers[id]
            XCTAssertTrue(date.exists)
            reveal(date, in: app)
            XCTAssertGreaterThanOrEqual(date.frame.width, 44)
            XCTAssertGreaterThanOrEqual(date.frame.height, 44)
            XCTAssertNotNil(date.value)
        }
        saveScreenshot(app, name: "scheduling-native-date-anchors")
        // Native calendar selection/dismissal, keyboard and live protected
        // binding rejection need a screen integration test, not a fake guard.
    }

    func testShortLandscapeFooterScrollsWithContentAtDefaultAndLargeText() {
        XCUIDevice.shared.orientation = .landscapeLeft
        for size in ["large", "xxxLarge", "accessibility5"] {
            let display = Display(size: size, theme: "dark", locale: "en_US", width: 568, height: 200)
            let app = open("Footer", display: display)
            let scroll = app.scrollViews.firstMatch
            XCTAssertGreaterThan(scroll.frame.height, 44, "Measured footer must not pin away the reading viewport")
            reveal(app.staticTexts["scheduling.footer.lastContent"], in: app)
            // In these short viewports the production measurement policy puts
            // the real footer in this same scroll, not behind a guessed inset.
            tapEdge(app.buttons["scheduling.footer.preview"], in: app)
            tapEdge(app.buttons["scheduling.footer.export"], in: app)
            assertState("previews:1 exports:1", id: "scheduling.footer.state", in: app)
            saveScreenshot(app, name: "scheduling-short-footer-\(size)")
            app.terminate()
        }
    }

    func testPortraitFooterReservesItsActualHeightAndKeepsIndependentActions() {
        let app = open("Footer", display: displays[0])
        let last = app.staticTexts["scheduling.footer.lastContent"]
        reveal(last, in: app)
        let preview = app.buttons["scheduling.footer.preview"]
        let export = app.buttons["scheduling.footer.export"]
        XCTAssertLessThanOrEqual(last.frame.maxY, min(preview.frame.minY, export.frame.minY))
        // Pinned footer actions are outside the scroll viewport. Use the
        // containing native window, not reveal()/the first scroll's bounds.
        tapWindowEdge(preview, in: app)
        tapWindowEdge(export, in: app)
        assertState("previews:1 exports:1", id: "scheduling.footer.state", in: app)
        saveScreenshot(app, name: "scheduling-measured-portrait-footer")
    }

    private func assertState(_ expected: String, id: String, in app: XCUIApplication) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate(format: "label == %@", expected), object: app.staticTexts[id])
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 3), .completed)
    }

    private func tapNativeMenuItem(_ label: String, in app: XCUIApplication) {
        let item = app.buttons[label].firstMatch
        XCTAssertTrue(item.waitForExistence(timeout: 3))
        let window = app.windows.containing(.button, identifier: label).firstMatch
        XCTAssertTrue(window.exists, "Use this menu's actual native owner window")
        // Menu popups have their own collection/table/scroll owner. Never
        // scroll the underlying scheduling page to reveal a popup option.
        let owners = [app.collectionViews.containing(.button, identifier: label).firstMatch,
                      app.tables.containing(.button, identifier: label).firstMatch,
                      app.menus.containing(.button, identifier: label).firstMatch,
                      app.scrollViews.containing(.button, identifier: label).firstMatch]
        let owner = owners.first(where: { $0.exists }) ?? window
        for _ in 0..<15 {
            let viewport = owner.frame.intersection(window.frame)
            if item.isHittable && viewport.contains(item.frame) { break }
            if item.frame.minY < viewport.minY { owner.swipeDown() } else { owner.swipeUp() }
        }
        XCTAssertTrue(item.isHittable)
        XCTAssertTrue(owner.frame.intersection(window.frame).contains(item.frame))
        XCTAssertEqual(item.label, label)
        XCTAssertGreaterThanOrEqual(item.frame.width, 44)
        XCTAssertGreaterThanOrEqual(item.frame.height, 44)
        item.tap()
    }

    private func tapWindowEdge(_ action: XCUIElement, in app: XCUIApplication) {
        let window = app.windows.containing(.button, identifier: action.identifier).firstMatch
        XCTAssertTrue(window.exists)
        XCTAssertTrue(action.isHittable)
        XCTAssertTrue(window.frame.contains(action.frame))
        XCTAssertGreaterThanOrEqual(action.frame.width, 44)
        XCTAssertGreaterThanOrEqual(action.frame.height, 44)
        action.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
            .withOffset(CGVector(dx: 0, dy: 3)).tap()
    }
}
