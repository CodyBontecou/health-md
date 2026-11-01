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

    /// XCUITest can report a partly exposed preset as hittable while its tap
    /// point is covered by the floating export actions. Scroll only inside the
    /// unobscured content and require the whole preset to clear those actions.
    private func scrollPresetAboveExportActions(_ preset: XCUIElement, in app: XCUIApplication) -> Bool {
        let scrollView = app.scrollViews.firstMatch
        for attempt in 0...6 {
            let viewport = scrollView.frame.intersection(app.frame)
            let actionTop = [
                app.buttons[UITestLaunchHelper.Export.previewButton],
                app.buttons[UITestLaunchHelper.Export.exportButton]
            ].filter { $0.exists }.map { $0.frame.minY }.min() ?? viewport.maxY
            let visible = CGRect(
                x: viewport.minX, y: viewport.minY,
                width: viewport.width, height: max(0, min(viewport.maxY, actionTop) - viewport.minY)
            ).insetBy(dx: 0, dy: 8)
            guard !visible.isEmpty else { return false }
            if preset.exists && !preset.frame.isEmpty && visible.contains(preset.frame) && preset.isHittable {
                return true
            }
            guard attempt < 6 else { return false }
            let origin = app.coordinate(withNormalizedOffset: .zero)
            origin.withOffset(CGVector(dx: visible.midX, dy: visible.minY + visible.height * 0.8)).press(
                forDuration: 0.05,
                thenDragTo: origin.withOffset(CGVector(dx: visible.midX, dy: visible.minY + visible.height * 0.3))
            )
        }
        return false
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

    /// Scrolls the first scroll view until an element is hittable; detail
    /// actions render lazily below the fold.
    @discardableResult
    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        for _ in 0..<maxSwipes where !(element.exists && element.isHittable) {
            app.swipeUp()
        }
        return element.exists && element.isHittable
    }

    /// Disabled controls have no hit point, but must still be visible for guard assertions.
    private func scrollUntilVisible(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        func isVisible() -> Bool {
            element.exists && !element.frame.isEmpty && app.frame.contains(element.frame)
        }
        for _ in 0..<maxSwipes where !isVisible() {
            app.swipeUp()
        }
        return isVisible()
    }

    private func openProfilesManagementSheet(_ app: XCUIApplication) {
        UITestLaunchHelper.openSettingsTab(in: app)

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

    func testManualExportAndPreviewRemainUsableWhileProtected() {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            configurationProtectionEnabled: true,
            useHealthKitExportPreviewFixtures: true
        )
        app.launchArguments += ["-UITestOpenClassicExport", "YES"]
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
        app.launchArguments += ["-UITestOpenClassicExport", "YES"]
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
        XCTAssertTrue(
            scrollUntilHittable(editSchedule, in: app),
            "The Edit Schedule action should be reachable in the scrollable profile detail"
        )
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
        XCTAssertTrue(scrollUntilVisible(delete, in: app), "The disabled Delete action should be visible")
        XCTAssertFalse(delete.isEnabled, "The last remaining profile must not be deletable")
        delete.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
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

        guard UITestLaunchHelper.openScheduleTab(in: app) else { return }

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

        UITestLaunchHelper.openSettingsTab(in: app)

        let toggle = app.switches[UITestLaunchHelper.ConfigurationProtection.toggle]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()

        UITestLaunchHelper.openClassicExport(in: app)

        let yesterday = app.buttons[UITestLaunchHelper.Export.datePresetYesterdayButton]
        scrollUntilExists(yesterday, in: app)
        XCTAssertTrue(yesterday.waitForExistence(timeout: 5))
        XCTAssertTrue(yesterday.isEnabled, "Configuration controls should be enabled after protection is turned off")
        XCTAssertFalse(app.buttons[UITestLaunchHelper.ConfigurationProtection.protectedRegion].firstMatch.exists)
        yesterday.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertFalse(app.buttons[UITestLaunchHelper.ConfigurationProtection.toast].waitForExistence(timeout: 1))
    }
}
