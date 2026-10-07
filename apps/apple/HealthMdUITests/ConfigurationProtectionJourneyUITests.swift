import XCTest

final class ConfigurationProtectionJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// The export-profile picker section sits above Date Range once profiles
    /// are active, so preset buttons render lazily below the fold; scroll to
    /// them before asserting or tapping.
    private func scrollUntilExists(_ element: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<6 where !element.exists {
            scrollView.swipeUp()
        }
    }

    /// The sheet-local toast is duplicated by the app-level one behind the
    /// sheet. Poll the live query and return the same tappable instance that
    /// callers will interact with, rather than selecting a stale/fallback
    /// element and querying again after the presentation animation.
    private func waitForHittableToast(
        in app: XCUIApplication,
        timeout: TimeInterval = 10
    ) -> XCUIElement? {
        let deadline = Date().addingTimeInterval(timeout)
        let predicate = NSPredicate(format: "identifier == %@", UITestLaunchHelper.ConfigurationProtection.toast)

        repeat {
            let toastQuery = app.buttons.matching(predicate)
            if let toast = toastQuery.allElementsBoundByIndex.last(where: { $0.exists && $0.isHittable }) {
                return toast
            }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        } while Date() < deadline

        return nil
    }

    /// Waits until an element both exists and is hittable, so taps land even
    /// while sheet presentation or navigation-push animations are settling.
    /// Generous by default: loaded CI runners can take several seconds for
    /// sheet content to settle into a hittable state.
    @discardableResult
    private func waitHittable(_ element: XCUIElement, timeout: TimeInterval = 10) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Preserve the hosted-only failure state without changing the tap or its wait.
    /// A missing toast can mean the preset tap missed, protection was off, or the
    /// accessibility query omitted the toast; the text log alone cannot distinguish them.
    private func attachProtectionToastFailureDiagnostics(
        in app: XCUIApplication,
        preset: XCUIElement,
        scrollView: XCUIElement
    ) {
        func describe(_ element: XCUIElement) -> String {
            guard element.exists else { return "exists=false" }
            return "exists=true, enabled=\(element.isEnabled), hittable=\(element.isHittable), "
                + "label=\(element.label), value=\(String(describing: element.value)), frame=\(element.frame)"
        }

        let toastPredicate = NSPredicate(
            format: "identifier == %@",
            UITestLaunchHelper.ConfigurationProtection.toast
        )
        let protectedRegions = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@",
                UITestLaunchHelper.ConfigurationProtection.protectedRegion
            )
        )
        let presetFrame = preset.exists ? preset.frame : .null
        let viewportFrame = scrollView.exists ? scrollView.frame : .null
        let presetCenter = CGPoint(x: presetFrame.midX, y: presetFrame.midY)
        let state = XCTAttachment(string: """
        State captured after the original toast wait failed:
        Protection overlay button count: \(protectedRegions.count)
        Toast button count: \(app.buttons.matching(toastPredicate).count)
        Toast any-element count: \(app.descendants(matching: .any).matching(toastPredicate).count)
        Yesterday preset: \(describe(preset))
        Today preset: \(describe(app.buttons[UITestLaunchHelper.Export.datePresetTodayButton]))
        Export button: \(describe(app.buttons[UITestLaunchHelper.Export.exportButton]))
        Scroll viewport: \(describe(scrollView))
        Preset center inside scroll frame: \(viewportFrame.contains(presetCenter))
        The overlay count is observable UI evidence, not a direct manager-state read.
        Frames describe the failure snapshot; the screenshot shows footer or tab-bar occlusion.
        """)
        state.name = "Protection toast failure state"
        state.lifetime = .keepAlways
        add(state)

        let hierarchy = XCTAttachment(string: app.debugDescription)
        hierarchy.name = "Protection toast failure hierarchy"
        hierarchy.lifetime = .keepAlways
        add(hierarchy)

        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Protection toast failure screenshot"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    func testBlockedChangeToastNavigatesToProtectionToggle() {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            configurationProtectionEnabled: true
        )
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        XCTAssertTrue(exportButton.isHittable, "Manual export must remain available while configuration is protected")

        let protectedControl = app.buttons[UITestLaunchHelper.Export.datePresetYesterdayButton]
        scrollUntilExists(protectedControl, in: app)
        XCTAssertTrue(protectedControl.waitForExistence(timeout: 5))
        // The preset row can be only partially exposed above the tab bar while XCUITest still
        // reports the button as hittable. Move it a bounded distance before tapping.
        let scrollView = app.scrollViews.firstMatch
        scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75)).press(
            forDuration: 0.05,
            thenDragTo: scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.6))
        )
        XCTAssertTrue(waitHittable(protectedControl))
        protectedControl.tap()

        guard let toast = waitForHittableToast(in: app) else {
            attachProtectionToastFailureDiagnostics(
                in: app,
                preset: protectedControl,
                scrollView: scrollView
            )
            XCTFail("The visible configuration-protection toast should be tappable")
            return
        }
        toast.tap()

        let toggle = app.switches[UITestLaunchHelper.ConfigurationProtection.toggle]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5), "Tapping the toast should navigate to the protection setting")
        let value = toggle.value as? String
        XCTAssertTrue(value == "1" || value == "On" || value == "Enabled")
    }

    func testManualExportAndPreviewRemainUsableWhileProtected() {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            configurationProtectionEnabled: true,
            useHealthKitExportPreviewFixtures: true
        )
        app.launch()

        let previewButton = app.buttons[UITestLaunchHelper.Export.previewButton]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5))
        previewButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[UITestLaunchHelper.ExportPreview.markdownFileRow]
                .waitForExistence(timeout: 10),
            "Preview must remain operational while configuration changes are protected"
        )
        app.buttons["Done"].tap()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()
        XCTAssertTrue(
            app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge]
                .waitForExistence(timeout: 10),
            "Manual export must complete while configuration changes are protected"
        )
        XCTAssertFalse(app.buttons[UITestLaunchHelper.ConfigurationProtection.toast].exists)
    }

    func testProtectedOutputEditorBlocksSaveAndRoutesToSetting() {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            configurationProtectionEnabled: true
        )
        app.launch()

        let filenameEditor = app.buttons[UITestLaunchHelper.Export.filenameEditorButton]
        for _ in 0..<10 where !filenameEditor.exists {
            app.swipeUp()
        }
        XCTAssertTrue(filenameEditor.waitForExistence(timeout: 3), "Protected users should still be able to inspect an output editor")
        filenameEditor.tap()

        let save = app.buttons[UITestLaunchHelper.Export.outputEditorSaveButton]
        XCTAssertTrue(save.waitForExistence(timeout: 5))
        save.tap()

        let toastQuery = app.buttons.matching(
            NSPredicate(
                format: "identifier == %@",
                UITestLaunchHelper.ConfigurationProtection.toast
            )
        )
        XCTAssertTrue(toastQuery.firstMatch.waitForExistence(timeout: 3), "Saving an already-open editor must be rejected")
        let toast = toastQuery.allElementsBoundByIndex.last(where: { $0.isHittable }) ?? toastQuery.firstMatch
        XCTAssertTrue(toast.isHittable, "The sheet-local protection toast must be tappable")
        toast.tap()

        XCTAssertTrue(
            app.switches[UITestLaunchHelper.ConfigurationProtection.toggle]
                .waitForExistence(timeout: 5),
            "The editor toast should dismiss the sheet and route to the protection toggle"
        )
    }

    func testTurningProtectionOffRestoresConfigurationControls() {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            configurationProtectionEnabled: true
        )
        app.launch()

        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        let toggle = app.switches[UITestLaunchHelper.ConfigurationProtection.toggle]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()

        let exportTab = app.tabBars.buttons["Export"]
        XCTAssertTrue(exportTab.waitForExistence(timeout: 5))
        exportTab.tap()

        let yesterday = app.buttons[UITestLaunchHelper.Export.datePresetYesterdayButton]
        scrollUntilExists(yesterday, in: app)
        XCTAssertTrue(yesterday.waitForExistence(timeout: 5))
        XCTAssertTrue(yesterday.isEnabled, "Configuration controls should be enabled after protection is turned off")
        XCTAssertFalse(app.buttons[UITestLaunchHelper.ConfigurationProtection.protectedRegion].firstMatch.exists)
        yesterday.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(app.buttons[UITestLaunchHelper.ConfigurationProtection.toast].waitForExistence(timeout: 1))
    }
}
