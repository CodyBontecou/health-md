import XCTest

/// ADDED / NOT RUN. The coordinator must register `dialogs` and this suite.
/// Keyboard checks require the actual software keyboard, not only a short host.
final class DialogsA11yUITests: A11yUITestCase {
    func testShortOverlayAndLongCopyKeepBothActionsReachableAcrossTextSizesAndThemes() {
        for size in ["large", "xxxLarge", "accessibility1", "accessibility5"] {
            for theme in ["light", "dark"] {
                for action in ["save", "cancel"] {
                    let app = open("message", size: size, theme: theme, width: 320, height: 200)
                    assertDialogBounds(in: app, maximumWidth: 320, maximumHeight: 200)
                    XCTAssertTrue(app.staticTexts["a11y.dialogs.message"].label.hasSuffix("[END]"))
                    XCTAssertEqual(app.staticTexts["geist-dialog.title"].label, "Read the Complete Synthetic Explanation")
                    saveScreenshot(app, name: "dialogs-320x200-\(size)-\(theme)-top")
                    let target = app.buttons["a11y.dialogs.\(action)"]
                    if action == "save" { XCTAssertEqual(target.label, "Keep Synthetic Explanation") }
                    revealInDialog(target, in: app)
                    saveScreenshot(app, name: "dialogs-320x200-\(size)-\(theme)-\(action)")
                    tapDialogEdge(target, in: app)
                    assertDismissed(app, counts: action == "save" ? "s1 c0 r0 d1" : "s0 c1 r0 d1",
                                    events: "\(action):true|dismiss")
                    app.terminate()
                }
            }
        }
    }

    func testLongGermanArabicAndJapaneseCopyUsesTheRealNarrowOverlay() {
        for locale in ["de_DE", "ar", "ja_JP"] {
            let app = open("message", size: "accessibility5", theme: "dark", locale: locale, width: 280, height: 280)
            assertDialogBounds(in: app, maximumWidth: 280, maximumHeight: 280)
            XCTAssertTrue(app.staticTexts["a11y.dialogs.message"].label.hasSuffix("[END]"))
            saveScreenshot(app, name: "dialogs-280x280-ax5-\(locale)-top")
            let save = app.buttons["a11y.dialogs.save"]
            revealInDialog(save, in: app)
            saveScreenshot(app, name: "dialogs-280x280-ax5-\(locale)-action")
            tapDialogEdge(save, in: app)
            assertDismissed(app, counts: "s1 c0 r0 d1", events: "save:true|dismiss")
            app.terminate()
        }
    }

    func testFirstFieldIsInitiallyFocusedAndNextDoneDoNotSubmitEarly() {
        let app = open("fields", width: 320)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5), "A real keyboard is required")
        // Type into the actual initial responder, without tapping either field first.
        app.typeText("alpha")
        XCTAssertEqual(app.textFields["geist-dialog.field.0"].value as? String, "alpha")
        XCTAssertNotEqual(app.textFields["geist-dialog.field.1"].value as? String, "alpha")
        let next = app.keyboards.buttons["Next"]
        XCTAssertTrue(next.exists)
        next.tap()
        XCTAssertTrue(dialogScroll(in: app).exists, "Next must not submit/dismiss")
        app.typeText("beta")
        XCTAssertEqual(app.textFields["geist-dialog.field.0"].value as? String, "alpha")
        XCTAssertEqual(app.textFields["geist-dialog.field.1"].value as? String, "beta")
        assertAboveKeyboard(app.textFields["geist-dialog.field.1"], in: app)
        app.keyboards.buttons["Done"].tap()
        assertDismissed(app, counts: "s1 c0 r0 d1", events: "save:true|dismiss")
        XCTAssertEqual(app.staticTexts["a11y.dialogs.first-value"].label, "First: alpha")
        XCTAssertEqual(app.staticTexts["a11y.dialogs.second-value"].label, "Second: beta")
    }

    func testEachPaddedFieldEdgeFocusesOnlyItsOwnNativeInput() {
        let app = open("fields", size: "accessibility1", width: 320)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("alpha")
        let first = app.textFields["geist-dialog.field.0"]
        let second = app.textFields["geist-dialog.field.1"]
        XCTAssertEqual(first.label, "Field Name With a Complete External Label")
        XCTAssertEqual(second.label, "Field Value With a Different External Label")
        let secondLabel = app.staticTexts["geist-dialog.field-label.1"]
        revealInDialog(secondLabel, in: app)
        XCTAssertEqual(secondLabel.label, second.label)
        XCTAssertLessThanOrEqual(secondLabel.frame.maxY, second.frame.minY)
        XCTAssertGreaterThan(secondLabel.frame.height, 44, "Long external label must wrap at accessibility size")
        tapDialogEdge(second, in: app)
        app.typeText("beta")
        XCTAssertEqual(first.value as? String, "alpha")
        XCTAssertEqual(second.value as? String, "beta")
        tapDialogEdge(first, in: app)
        app.typeText("1")
        XCTAssertEqual(first.value as? String, "alpha1")
        XCTAssertEqual(second.value as? String, "beta")
        tapDialogEdge(app.buttons["a11y.dialogs.cancel"], in: app)
        assertDismissed(app, counts: "s0 c1 r0 d1", events: "cancel:true|dismiss")
        XCTAssertEqual(app.staticTexts["a11y.dialogs.first-value"].label, "First: alpha1")
        XCTAssertEqual(app.staticTexts["a11y.dialogs.second-value"].label, "Second: beta")
    }

    func testSaveAndCancelStayReachableWhileTheRealKeyboardIsOpen() {
        let cases: [(CGFloat?, String)] = [(nil, "save"), (nil, "cancel"), (200, "save"), (200, "cancel")]
        for (height, action) in cases {
            let app = open("fields", size: "accessibility5", theme: "dark", width: 320, height: height)
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            app.typeText("alpha")
            app.keyboards.buttons["Next"].tap()
            app.typeText("beta")
            let target = app.buttons["a11y.dialogs.\(action)"]
            revealInDialog(target, in: app)
            XCTAssertTrue(app.keyboards.firstMatch.exists, "Do not substitute a keyboard-dismissed test")
            assertAboveKeyboard(target, in: app)
            assertDialogBounds(in: app, maximumWidth: 320, maximumHeight: height)
            saveScreenshot(app, name: "dialogs-real-keyboard-ax5-\(height.map { String(Int($0)) } ?? "native")-\(action)")
            tapDialogEdge(target, in: app)
            assertDismissed(app, counts: action == "save" ? "s1 c0 r0 d1" : "s0 c1 r0 d1",
                            events: "\(action):true|dismiss")
            XCTAssertEqual(app.staticTexts["a11y.dialogs.first-value"].label, "First: alpha")
            XCTAssertEqual(app.staticTexts["a11y.dialogs.second-value"].label, "Second: beta")
            app.terminate()
        }
    }

    func testSingleFieldDoneRetainsImmediateSubmission() {
        let app = open("single", width: 320)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("synthetic")
        XCTAssertTrue(app.keyboards.buttons["Done"].exists)
        app.keyboards.buttons["Done"].tap()
        assertDismissed(app, counts: "s1 c0 r0 d1", events: "save:true|dismiss")
        XCTAssertEqual(app.staticTexts["a11y.dialogs.first-value"].label, "First: synthetic")
    }

    func testFinalDoneWithoutPrimaryKeepsDialogAndDraftsUntilCancel() {
        let app = open("secondary-fields", width: 320)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("alpha")
        app.keyboards.buttons["Next"].tap()
        app.typeText("beta")
        app.keyboards.buttons["Done"].tap()
        XCTAssertTrue(dialogScroll(in: app).exists)
        XCTAssertEqual(app.textFields["geist-dialog.field.1"].value as? String, "beta")
        tapDialogEdge(app.buttons["a11y.dialogs.cancel"], in: app)
        assertDismissed(app, counts: "s0 c1 r0 d1", events: "cancel:true|dismiss")
    }

    func testInteractiveKeyboardDismissalDoesNotDismissDialogOrChangeDrafts() {
        let app = open("fields", width: 320)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        app.typeText("alpha")
        app.keyboards.buttons["Next"].tap()
        app.typeText("beta")
        for _ in 0..<8 where app.keyboards.firstMatch.exists {
            let viewport = dialogViewport(in: app)
            let owner = dialogScroll(in: app)
            let start = owner.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: viewport.midX - owner.frame.minX, dy: viewport.maxY - owner.frame.minY - 8))
            // Track from the real scroll owner through the native keyboard's own
            // bounds, rather than treating a shorter host as keyboard evidence.
            let end = app.keyboards.firstMatch.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 1))
                .withOffset(CGVector(dx: 0, dy: -3))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTAssertFalse(app.keyboards.firstMatch.exists, "Exercise actual interactive keyboard dismissal")
        XCTAssertTrue(dialogScroll(in: app).exists)
        XCTAssertEqual(app.textFields["geist-dialog.field.0"].value as? String, "alpha")
        XCTAssertEqual(app.textFields["geist-dialog.field.1"].value as? String, "beta")
        tapDialogEdge(app.buttons["a11y.dialogs.cancel"], in: app)
        assertDismissed(app, counts: "s0 c1 r0 d1", events: "cancel:true|dismiss")
    }

    func testLongUnbrokenDraftHasFullReadingCopyWithoutChangingBoundText() {
        let app = open("fields", size: "accessibility1", width: 320)
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let raw = " synthetic_identifier_that_must_not_be_trimmed_or_truncated "
        app.typeText(raw)
        XCTAssertEqual(app.textFields["geist-dialog.field.0"].value as? String, raw)
        app.keyboards.buttons["Next"].tap()
        app.typeText("value")
        // The reading surface is intentionally hidden from AX to avoid repeating the
        // editable value. Native hierarchy screenshots, not AX metadata, cover its look.
        revealInDialog(app.staticTexts["geist-dialog.field-label.0"], in: app)
        saveScreenshot(app, name: "dialogs-long-draft-reading-copy")
        tapDialogEdge(app.buttons["a11y.dialogs.save"], in: app)
        assertDismissed(app, counts: "s1 c0 r0 d1", events: "save:true|dismiss")
        XCTAssertEqual(app.staticTexts["a11y.dialogs.first-value"].label, "First: \(raw)")
    }

    func testStackedIndependentActionsDispatchOnlyTheirOwnCallbacksInShortViewport() {
        for (action, counts, event) in [
            ("cancel", "s0 c1 r0 d1", "cancel"),
            ("other-cancel", "s0 c10 r0 d1", "other-cancel"),
            ("save", "s1 c0 r0 d1", "save"),
            ("remove", "s0 c0 r1 d1", "remove")
        ] {
            let app = open("many", size: "accessibility1", width: 568, height: 200)
            assertDialogBounds(in: app, maximumWidth: 568, maximumHeight: 200)
            tapDialogEdge(app.buttons["a11y.dialogs.\(action)"], in: app)
            assertDismissed(app, counts: counts, events: "\(event):true|dismiss")
            app.terminate()
        }
    }

    func testScrimUsesFirstSecondaryAndOtherwiseOnlyDismisses() {
        for variant in ["many", "no-cancel"] {
            let app = open(variant, width: 320, height: 200)
            let overlay = app.otherElements["geist-dialog.overlay"]
            let point = CGPoint(x: overlay.frame.minX + 2, y: overlay.frame.minY + 2)
            XCTAssertFalse(app.otherElements["geist-dialog.card"].frame.contains(point))
            overlay.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: 2, dy: 2)).tap()
            assertDismissed(app, counts: variant == "many" ? "s0 c1 r0 d1" : "s0 c0 r0 d1",
                            events: variant == "many" ? "cancel:true|dismiss" : "dismiss")
            app.terminate()
        }
    }

    func testModalHidesBackgroundAccessibilityAndRestoresItAfterDismissal() {
        let app = open("message", width: 320, height: 280)
        XCTAssertFalse(app.buttons["a11y.dialogs.open-fields"].exists, "Background must not be traversable while modal")
        XCTAssertFalse(app.staticTexts["a11y.dialogs.counts"].exists)
        tapDialogEdge(app.buttons["a11y.dialogs.cancel"], in: app)
        assertDismissed(app, counts: "s0 c1 r0 d1", events: "cancel:true|dismiss")
        XCTAssertTrue(app.buttons["a11y.dialogs.open-fields"].exists)
    }

    func testNativeReducedMotionPresentationWhenTheSystemSettingIsEnabled() throws {
        let app = launchScenario("dialogs", size: "accessibility5", theme: "dark", width: 320, height: 280)
        XCTAssertTrue(app.staticTexts["a11y.dialogs.motion"].waitForExistence(timeout: 5))
        guard app.staticTexts["a11y.dialogs.motion"].label == "Reduced motion: on" else {
            throw XCTSkip("Needs an isolated runner with the real Reduce Motion setting enabled; no read-only environment override")
        }
        let opener = app.buttons["a11y.dialogs.open-message"]
        reveal(opener, in: app)
        opener.tap()
        XCTAssertTrue(dialogScroll(in: app).waitForExistence(timeout: 5))
        assertDialogBounds(in: app, maximumWidth: 320, maximumHeight: 280)
        tapDialogEdge(app.buttons["a11y.dialogs.cancel"], in: app)
        assertDismissed(app, counts: "s0 c1 r0 d1", events: "cancel:true|dismiss")
    }

    private func open(_ variant: String, size: String = "large", theme: String = "light", locale: String = "en_US",
                      width: CGFloat? = nil, height: CGFloat? = nil) -> XCUIApplication {
        let app = launchScenario("dialogs", size: size, theme: theme, locale: locale, width: width, height: height)
        let opener = app.buttons["a11y.dialogs.open-\(variant)"]
        XCTAssertTrue(opener.waitForExistence(timeout: 5))
        reveal(opener, in: app)
        opener.tap()
        XCTAssertTrue(dialogScroll(in: app).waitForExistence(timeout: 5))
        return app
    }

    private func dialogScroll(in app: XCUIApplication) -> XCUIElement {
        app.scrollViews["geist-dialog.scroll"]
    }

    /// The modal's own scroll and native owner window, never the background scroll.
    private func dialogViewport(in app: XCUIApplication) -> CGRect {
        let scroll = dialogScroll(in: app)
        let window = app.windows.containing(.scrollView, identifier: "geist-dialog.scroll").firstMatch
        var viewport = scroll.frame.intersection(window.frame)
            .intersection(app.otherElements["geist-dialog.card"].frame)
        let keyboard = app.keyboards.firstMatch
        if keyboard.exists && keyboard.frame.intersects(viewport) {
            viewport.size.height = max(0, keyboard.frame.minY - viewport.minY)
        }
        return viewport.insetBy(dx: 0, dy: 1)
    }

    private func revealInDialog(_ target: XCUIElement, in app: XCUIApplication) {
        let scroll = dialogScroll(in: app)
        for _ in 0..<100 {
            let viewport = dialogViewport(in: app)
            if target.isHittable && viewport.insetBy(dx: -1, dy: -1).contains(target.frame) { return }
            guard viewport.height > 16 else { XCTFail("No actual modal reading viewport: \(viewport)"); return }
            let moveDown = target.frame.minY < viewport.minY
            let start = scroll.coordinate(withNormalizedOffset: .zero).withOffset(
                CGVector(dx: viewport.midX - scroll.frame.minX,
                         dy: viewport.minY - scroll.frame.minY + viewport.height * (moveDown ? 0.2 : 0.8)))
            start.press(forDuration: 0.05, thenDragTo: start.withOffset(
                CGVector(dx: 0, dy: viewport.height * (moveDown ? 0.6 : -0.6))))
        }
        XCTFail("Target not fully reachable in its actual modal/keyboard viewport: \(target)")
    }

    private func tapDialogEdge(_ target: XCUIElement, in app: XCUIApplication) {
        revealInDialog(target, in: app)
        XCTAssertGreaterThanOrEqual(target.frame.width, 44)
        XCTAssertGreaterThanOrEqual(target.frame.height, 44)
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0)).withOffset(CGVector(dx: 0, dy: 3)).tap()
    }

    private func assertAboveKeyboard(_ target: XCUIElement, in app: XCUIApplication) {
        XCTAssertTrue(app.keyboards.firstMatch.exists)
        XCTAssertTrue(dialogViewport(in: app).insetBy(dx: -1, dy: -1).contains(target.frame))
        XCTAssertFalse(target.frame.intersects(app.keyboards.firstMatch.frame))
    }

    private func assertDialogBounds(in app: XCUIApplication, maximumWidth: CGFloat, maximumHeight: CGFloat? = nil) {
        let overlay = app.otherElements["geist-dialog.overlay"]
        let card = app.otherElements["geist-dialog.card"]
        XCTAssertTrue(overlay.exists)
        XCTAssertTrue(card.exists)
        XCTAssertLessThanOrEqual(overlay.frame.width, maximumWidth + 1)
        if let maximumHeight { XCTAssertLessThanOrEqual(overlay.frame.height, maximumHeight + 1) }
        XCTAssertTrue(overlay.frame.insetBy(dx: -1, dy: -1).contains(card.frame))
        XCTAssertLessThanOrEqual(card.frame.width, 420)
        XCTAssertGreaterThan(card.frame.height, 0)
        if app.keyboards.firstMatch.exists { XCTAssertFalse(card.frame.intersects(app.keyboards.firstMatch.frame)) }
    }

    private func assertDismissed(_ app: XCUIApplication, counts: String, events: String) {
        let gone = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: dialogScroll(in: app))
        XCTAssertEqual(XCTWaiter.wait(for: [gone], timeout: 5), .completed)
        XCTAssertEqual(app.staticTexts["a11y.dialogs.counts"].label, counts)
        XCTAssertEqual(app.staticTexts["a11y.dialogs.events"].label, events)
    }
}
