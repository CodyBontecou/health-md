import XCTest

final class ConfigurationProtectionJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
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
        XCTAssertTrue(protectedControl.waitForExistence(timeout: 5))
        protectedControl.tap()

        let toast = app.buttons[UITestLaunchHelper.ConfigurationProtection.toast]
        XCTAssertTrue(toast.waitForExistence(timeout: 3))
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
        XCTAssertTrue(yesterday.waitForExistence(timeout: 5))
        XCTAssertTrue(yesterday.isEnabled, "Configuration controls should be enabled after protection is turned off")
        XCTAssertFalse(app.buttons[UITestLaunchHelper.ConfigurationProtection.protectedRegion].firstMatch.exists)
        yesterday.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(app.buttons[UITestLaunchHelper.ConfigurationProtection.toast].waitForExistence(timeout: 1))
    }
}
