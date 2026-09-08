#if os(iOS)
import XCTest

/// ADDED / NOT RUN in the source-only lane. These exercise production components
/// with synthetic bindings, never the shipping screen's configuration protection.
final class FormatA11yUITests: A11yUITestCase {
    private let original = "synthetic_original_output_key_with_a_long_unbroken_identifier"
    private let renamed = "synthetic_renamed_output_key_preserved_without_truncation"
    private let customKey = "synthetic_custom_metadata_key_for_accessibility"
    private let placeholderKey = "synthetic_placeholder_key_for_manual_review"

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
    }

    func testClosedMenuValuesHaveNativeCapturesAcrossTextSizesWidthsAndThemes() {
        for size in ["large", "xxxLarge", "accessibility1", "accessibility5"] {
            for theme in ["light", "dark"] {
                for width in [CGFloat(288), 320] {
                    let app = launchScenario("format", size: size, theme: theme, width: width)
                    let menu = app.buttons["format.selection.Date Format"]
                    XCTAssertTrue(menu.waitForExistence(timeout: 10))
                    reveal(menu, in: app)
                    XCTAssertEqual(menu.label, "Date Format")
                    XCTAssertEqual(menu.value as? String, "ISO 8601 (2026-01-13)")
                    assertMinimumTarget(menu)
                    // Visual full-value evidence comes from this native capture plus the
                    // production-label wrapping measurements, not accessibilityValue alone.
                    saveScreenshot(app, name: "format-closed-\(size)-\(theme)-\(Int(width))")
                    app.terminate()
                }
            }
        }
    }

    func testNativeMenuSelectionsChangeOnlyTheirOwnValueOnce() {
        for size in ["large", "xxxLarge", "accessibility1", "accessibility5"] {
            let app = launchScenario("format", size: size, width: 320)
            choose("Friendly (Mon, Jan 13, 2026)", in: "Date Format", app: app)
            XCTAssertEqual(app.staticTexts["a11y.format.events"].label, "Selections: 1; Toggles: 0")
            choose("12-hour with seconds (2:30:45 PM)", in: "Time Format", app: app)
            XCTAssertEqual(app.staticTexts["a11y.format.events"].label, "Selections: 2; Toggles: 0")
            XCTAssertEqual(app.buttons["format.selection.Date Format"].value as? String, "Friendly (Mon, Jan 13, 2026)")
            choose("Imperial", in: "Unit System", app: app)
            XCTAssertEqual(app.staticTexts["a11y.format.events"].label, "Selections: 3; Toggles: 0")
            XCTAssertEqual(app.buttons["format.selection.Time Format"].value as? String, "12-hour with seconds (2:30:45 PM)")
            // Existing behavior reapplies even the current selection.
            choose("Imperial", in: "Unit System", app: app)
            XCTAssertEqual(app.staticTexts["a11y.format.events"].label, "Selections: 4; Toggles: 0")
            app.terminate()
        }
    }

    func testFormatToggleIsOneNamedNativeActionWithOneCallbackPerEdgeTap() {
        for size in ["large", "xxxLarge", "accessibility1", "accessibility5"] {
            let app = launchScenario("format", size: size, theme: "dark", width: 320)
            let toggles = app.switches.matching(identifier: "Use emoji in section headers")
            XCTAssertEqual(toggles.count, 1)
            let toggle = toggles.firstMatch
            tapEdge(toggle, in: app)
            XCTAssertEqual(app.staticTexts["a11y.format.events"].label, "Selections: 0; Toggles: 1")
            XCTAssertTrue(["1", "On", "Enabled"].contains(toggle.value as? String ?? ""))
            tapEdge(toggle, in: app)
            XCTAssertEqual(app.staticTexts["a11y.format.events"].label, "Selections: 0; Toggles: 2")
            XCTAssertTrue(["0", "Off", "Disabled"].contains(toggle.value as? String ?? ""))
            app.terminate()
        }
    }

    func testLongFieldToggleRenameAddAndDeleteRemainIndependentAndContextual() {
        for size in ["large", "xxxLarge", "accessibility1", "accessibility5"] {
            let app = openFrontmatter(size: size)
            let toggle = app.switches["format.field.toggle.\(original)"]
            XCTAssertEqual(app.switches.matching(identifier: "format.field.toggle.\(original)").count, 1)
            XCTAssertEqual(toggle.label, "\(original) renamed to \(renamed)")
            tapEdge(toggle, in: app)
            assertFrontmatterEvents(app, toggle: 1, rename: 0, delete: 0, add: 0)
            let rename = app.buttons["a11y.format.rename"]
            XCTAssertEqual(rename.label, "Rename \(original)")
            tapEdge(rename, in: app)
            assertFrontmatterEvents(app, toggle: 1, rename: 1, delete: 0, add: 0)
            XCTAssertTrue(["0", "Off", "Disabled"].contains(toggle.value as? String ?? ""))
            saveScreenshot(app, name: "format-renamed-\(size)")

            let deleteCustom = app.buttons["Delete custom field \(customKey)"]
            tapEdge(deleteCustom, in: app)
            assertFrontmatterEvents(app, toggle: 1, rename: 1, delete: 1, add: 0)
            XCTAssertFalse(deleteCustom.exists)
            XCTAssertTrue(app.buttons["Delete placeholder field \(placeholderKey)"].exists)
            tapEdge(app.buttons["a11y.format.add-custom"], in: app)
            assertFrontmatterEvents(app, toggle: 1, rename: 1, delete: 1, add: 1)
            tapEdge(app.buttons["Delete placeholder field \(placeholderKey)"], in: app)
            assertFrontmatterEvents(app, toggle: 1, rename: 1, delete: 2, add: 1)
            tapEdge(app.buttons["a11y.format.add-placeholder"], in: app)
            assertFrontmatterEvents(app, toggle: 1, rename: 1, delete: 2, add: 2)
            // These Add/Rename callbacks intentionally do not claim dialog acceptance,
            // persistence, normalization or protection. Full-host checks remain required.
            app.terminate()
        }
    }

    func testInputsKeepExactSpacesAndDismissTheNativeKeyboardWithoutOtherCallbacks() {
        for size in ["large", "accessibility5"] {
            let app = openFrontmatter(size: size)
            let input = app.textFields["format.input.Date Field Name"]
            reveal(input, in: app)
            assertMinimumTarget(input)
            input.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            let exact = "  synthetic_date  "
            input.typeText(exact)
            XCTAssertEqual(input.value as? String, exact)
            let done = app.keyboards.buttons.matching(NSPredicate(format: "label IN %@", ["Done", "done"] as NSArray)).firstMatch
            XCTAssertTrue(done.waitForExistence(timeout: 5))
            // Keyboard keys belong to the keyboard window, not the page scroll view.
            assertInsideOwningWindow(done, app: app)
            done.tap()
            waitForKeyboardDismissal(app)
            XCTAssertEqual(input.value as? String, exact)
            assertFrontmatterEvents(app, toggle: 0, rename: 0, delete: 0, add: 0)

            let fullValue = "  synthetic_long_type_value_preserved_with_its_original_spaces_and_identifier  "
            let valueInput = app.textFields["format.input.Type Field Value"]
            reveal(valueInput, in: app)
            XCTAssertEqual(valueInput.value as? String, fullValue)
            let readingValue = app.staticTexts.matching(NSPredicate(format: "label == %@", fullValue)).firstMatch
            reveal(readingValue, in: app)
            XCTAssertGreaterThanOrEqual(readingValue.frame.width, valueInput.frame.width - 17)
            saveScreenshot(app, name: "format-input-full-value-\(size)")
            app.terminate()
        }
    }

    func testTemplateKeyboardInShortViewportKeepsEditorHelpAndRawTextReachable() {
        for size in ["large", "xxxLarge", "accessibility1", "accessibility5"] {
            let app = launchScenario("format", size: size, theme: "dark", width: 320, height: 340)
            tapEdge(app.buttons["a11y.format.template"], in: app)
            let editor = app.textViews["format.template.editor"]
            XCTAssertTrue(editor.waitForExistence(timeout: 5))
            reveal(editor, in: app)
            assertMinimumTarget(editor)
            XCTAssertLessThanOrEqual(editor.frame.height, app.scrollViews.firstMatch.frame.height / 2 + 1)
            editor.tap()
            XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
            // Verify the actual resized scroll/keyboard geometry, not only window bounds.
            revealAboveKeyboard(editor, app: app)
            editor.typeText("\nsynthetic_keyboard_tail")
            XCTAssertTrue((editor.value as? String ?? "").contains("synthetic_keyboard_tail"))
            let fullText = editor.value as? String
            let dismiss = app.buttons["format.template.dismiss-keyboard"]
            XCTAssertTrue(dismiss.waitForExistence(timeout: 5))
            assertMinimumTarget(dismiss)
            assertInsideOwningWindow(dismiss, app: app)
            dismiss.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0))
                .withOffset(CGVector(dx: 0, dy: 3)).tap()
            waitForKeyboardDismissal(app)
            XCTAssertEqual(editor.value as? String, fullText)
            let help = app.staticTexts["Available Placeholders"]
            reveal(help, in: app)
            XCTAssertTrue(app.staticTexts["{{date}}, {{#section}}...{{/section}}, {{metrics}}"].exists)
            saveScreenshot(app, name: "format-template-short-\(size)")
            app.terminate()
        }
    }

    func testTemplateSupportsInteractiveKeyboardDismissalWithoutAWrite() {
        let app = launchScenario("format", size: "accessibility5", width: 320)
        tapEdge(app.buttons["a11y.format.template"], in: app)
        let editor = app.textViews["format.template.editor"]
        reveal(editor, in: app)
        let originalText = editor.value as? String
        editor.tap()
        XCTAssertTrue(app.keyboards.firstMatch.waitForExistence(timeout: 5))
        let scroll = app.scrollViews.firstMatch
        // Drag in the outer scroll gutter, not the TextEditor's nested scroll region.
        let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.2))
        let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.9))
        start.press(forDuration: 0.05, thenDragTo: end)
        waitForKeyboardDismissal(app)
        XCTAssertEqual(editor.value as? String, originalText)
    }

    func testLongLocaleAndRTLNativeValueCaptures() {
        for locale in ["de_DE", "ar", "ja_JP"] {
            let app = launchScenario("format", size: "accessibility5", theme: "dark", locale: locale, width: 288)
            let menu = app.buttons["format.selection.Date Format"]
            reveal(menu, in: app)
            assertMinimumTarget(menu)
            XCTAssertEqual(menu.value as? String, "ISO 8601 (2026-01-13)")
            saveScreenshot(app, name: "format-locale-\(locale)")
            app.terminate()
        }
    }

    private func openFrontmatter(size: String) -> XCUIApplication {
        let app = launchScenario("format", size: size, width: 320)
        tapEdge(app.buttons["a11y.format.frontmatter"], in: app)
        XCTAssertTrue(app.staticTexts["a11y.format.frontmatter.events"].waitForExistence(timeout: 5))
        return app
    }

    private func assertFrontmatterEvents(_ app: XCUIApplication, toggle: Int, rename: Int, delete: Int, add: Int) {
        XCTAssertEqual(app.staticTexts["a11y.format.frontmatter.events"].label,
                       "Toggle: \(toggle); Rename: \(rename); Delete: \(delete); Add: \(add)")
    }

    private func choose(_ value: String, in title: String, app: XCUIApplication) {
        let menu = app.buttons["format.selection.\(title)"]
        tapEdge(menu, in: app)
        let option = app.buttons.matching(NSPredicate(format: "label == %@", value)).firstMatch
        XCTAssertTrue(option.waitForExistence(timeout: 5))
        // Native popups can be outside the embedded page. Only scroll a native
        // owner containing this option; never blindly scroll the page behind it.
        let ownerScroll = app.scrollViews.allElementsBoundByIndex
            .filter { $0.buttons.matching(NSPredicate(format: "label == %@", value)).count > 0 }
            .min { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }
        for _ in 0..<12 {
            let viewport = ownerScroll?.frame ?? owningWindowFrame(of: option, app: app)
            if option.isHittable && viewport.contains(option.frame) { break }
            guard let ownerScroll else { break }
            if option.frame.minY < ownerScroll.frame.minY { ownerScroll.swipeDown() } else { ownerScroll.swipeUp() }
        }
        XCTAssertTrue(option.isHittable)
        assertInsideOwningWindow(option, app: app)
        if let ownerScroll { XCTAssertTrue(ownerScroll.frame.contains(option.frame)) }
        saveScreenshot(app, name: "format-native-menu-\(title)-\(value)")
        option.tap()
        XCTAssertEqual(menu.value as? String, value)
    }

    private func assertMinimumTarget(_ element: XCUIElement) {
        XCTAssertGreaterThanOrEqual(element.frame.width, 44)
        XCTAssertGreaterThanOrEqual(element.frame.height, 44)
    }

    private func assertInsideOwningWindow(_ element: XCUIElement, app: XCUIApplication) {
        XCTAssertTrue(owningWindowFrame(of: element, app: app).contains(element.frame),
                      "Native control must fit its actual owning window: \(element)")
    }

    private func owningWindowFrame(of element: XCUIElement, app: XCUIApplication) -> CGRect {
        let match = NSPredicate(format: "identifier == %@ AND label == %@", element.identifier, element.label)
        // Locate the hierarchy owner instead of assuming the first application window.
        guard let window = app.windows.allElementsBoundByIndex
            .filter({ $0.descendants(matching: element.elementType).matching(match).count > 0 })
            .min(by: { $0.frame.width * $0.frame.height < $1.frame.width * $1.frame.height }) else {
            XCTFail("No native window owns \(element)")
            return .zero
        }
        return window.frame
    }

    private func revealAboveKeyboard(_ element: XCUIElement, app: XCUIApplication) {
        let scroll = app.scrollViews.firstMatch
        for _ in 0..<20 {
            var viewport = scroll.frame
            let keyboard = app.keyboards.firstMatch.frame
            if keyboard.intersects(viewport) {
                viewport.size.height = max(0, keyboard.minY - viewport.minY)
            }
            if element.isHittable && viewport.insetBy(dx: 0, dy: 1).contains(element.frame) { return }
            let towardTop = element.frame.minY < viewport.minY
            let start = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: 0.5))
            let end = scroll.coordinate(withNormalizedOffset: CGVector(dx: 0.01, dy: towardTop ? 0.75 : 0.25))
            start.press(forDuration: 0.05, thenDragTo: end)
        }
        XCTFail("Editor is not reachable above the actual keyboard")
    }

    private func waitForKeyboardDismissal(_ app: XCUIApplication) {
        let hidden = XCTNSPredicateExpectation(predicate: NSPredicate(format: "exists == false"), object: app.keyboards.firstMatch)
        XCTAssertEqual(XCTWaiter.wait(for: [hidden], timeout: 5), .completed)
    }
}
#endif
