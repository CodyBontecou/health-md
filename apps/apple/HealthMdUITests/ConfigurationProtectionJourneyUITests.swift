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
        timeout: TimeInterval = 3
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
    @discardableResult
    private func waitHittable(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let expectation = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "isHittable == true"),
            object: element
        )
        return XCTWaiter().wait(for: [expectation], timeout: timeout) == .completed
    }

    /// Scrolls the first scroll view until an element is hittable; detail
    /// actions render lazily below the fold.
    @discardableResult
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        for _ in 0..<maxSwipes where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    private func openProfilesManagementSheet(_ app: XCUIApplication) {
        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitForExistence(timeout: 5))
        settingsTab.tap()

        let profilesRow = app.buttons["export.profiles.entry"]
        XCTAssertTrue(profilesRow.waitForExistence(timeout: 5), "Export Profiles row should exist in Settings")
        profilesRow.tap()

        XCTAssertTrue(
            app.navigationBars["Export Profiles"].waitForExistence(timeout: 5),
            "Profile management stays inspectable while configuration is protected"
        )
        XCTAssertTrue(
            app.buttons["export.profiles.row.Default"].waitForExistence(timeout: 5),
            "The migrated Default profile should remain readable"
        )
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

    func testProtectedProfileManagementBlocksCreationAndRoutesToSetting() {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            configurationProtectionEnabled: true
        )
        app.launch()

        openProfilesManagementSheet(app)

        let newProfileButton = app.buttons["New profile"]
        XCTAssertTrue(newProfileButton.waitForExistence(timeout: 3))
        XCTAssertTrue(waitHittable(newProfileButton), "The New profile action should be tappable")
        newProfileButton.tap()

        XCTAssertFalse(
            app.navigationBars["New Profile"].waitForExistence(timeout: 1),
            "The profile editor must not open while protected"
        )

        guard let toast = waitForHittableToast(in: app) else {
            XCTFail("Creating a profile must show a tappable protection toast")
            return
        }
        toast.tap()
        XCTAssertTrue(
            app.switches[UITestLaunchHelper.ConfigurationProtection.toggle]
                .waitForExistence(timeout: 5),
            "The profiles-sheet toast should dismiss the sheet and route to the protection toggle"
        )
    }

    func testProtectedProfileDetailActionsAreBlocked() {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            configurationProtectionEnabled: true
        )
        app.launch()

        openProfilesManagementSheet(app)
        let defaultRow = app.buttons["export.profiles.row.Default"]
        XCTAssertTrue(waitHittable(defaultRow), "The Default profile row should be tappable")
        defaultRow.tap()
        XCTAssertTrue(
            app.buttons["export.profiles.edit.button"].waitForExistence(timeout: 5),
            "Profile detail should stay inspectable while protected"
        )

        // Editing the frozen snapshot is rejected with the shared toast.
        let editButton = app.buttons["export.profiles.edit.button"]
        XCTAssertTrue(waitHittable(editButton))
        editButton.tap()
        XCTAssertNotNil(waitForHittableToast(in: app))
        XCTAssertFalse(app.navigationBars["Edit Profile"].waitForExistence(timeout: 1))

        // Schedule editing never opens the cadence sheet.
        let editSchedule = app.buttons["Edit Schedule…"]
        XCTAssertTrue(waitHittable(editSchedule))
        editSchedule.tap()
        XCTAssertNotNil(waitForHittableToast(in: app))
        XCTAssertFalse(app.switches["Enabled"].waitForExistence(timeout: 1))

        // Duplicating is rejected without creating a copy.
        let duplicate = app.buttons["Duplicate"]
        XCTAssertTrue(scrollUntilHittable(duplicate, in: app), "The Duplicate action should be reachable")
        duplicate.tap()
        XCTAssertNotNil(waitForHittableToast(in: app))
        XCTAssertFalse(app.buttons["export.profiles.row.Default 2"].waitForExistence(timeout: 1))

        // Renaming never presents the rename alert.
        let rename = app.buttons["Rename…"]
        XCTAssertTrue(scrollUntilHittable(rename, in: app), "The Rename action should be reachable")
        rename.tap()
        XCTAssertNotNil(waitForHittableToast(in: app))
        XCTAssertFalse(app.alerts.firstMatch.waitForExistence(timeout: 1))

        // With the migrated single Default profile, Delete is additionally
        // disabled by the last-profile guard, so tapping it must present
        // neither the confirmation dialog nor mutate anything.
        let delete = app.buttons["Delete Profile…"]
        XCTAssertTrue(scrollUntilHittable(delete, in: app), "The Delete action should be reachable")
        XCTAssertFalse(delete.isEnabled, "The last remaining profile must not be deletable")
        delete.tap()
        XCTAssertFalse(app.staticTexts["Delete this profile?"].waitForExistence(timeout: 1))
    }

    func testProtectedProfileSchedulesCardIsLockedOnScheduleTab() {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            configurationProtectionEnabled: true
        )
        app.launch()

        let scheduleTab = app.tabBars.buttons["Schedule"]
        XCTAssertTrue(scheduleTab.waitForExistence(timeout: 5))
        scheduleTab.tap()

        let card = app.staticTexts["Profile Schedules"]
        XCTAssertTrue(card.waitForExistence(timeout: 5), "Profile Schedules card should exist")

        let protectedRegion = app.buttons[UITestLaunchHelper.ConfigurationProtection.protectedRegion]
            .firstMatch
        XCTAssertTrue(
            protectedRegion.waitForExistence(timeout: 3),
            "The per-profile schedules card must sit inside the shared lock"
        )
        protectedRegion.tap()
        XCTAssertTrue(
            app.buttons[UITestLaunchHelper.ConfigurationProtection.toast]
                .waitForExistence(timeout: 3),
            "Tapping a profile schedule row must surface the blocked-change toast"
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
