import XCTest

/// Pre-release QA journeys for export profiles (release 3.1.0 scope).
/// Covers: first-launch migration to the Default profile, the Settings→
/// Export Profiles management surface (duplicate/rename/delete + last-profile
/// guard), and per-profile schedules (enable toggle, cadence editor,
/// empty-schedule footer). Screenshots are written to /tmp/qa-shots for
/// manual review.
final class ExportProfilesJourneyUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = false
        try? FileManager.default.createDirectory(
            at: URL(fileURLWithPath: "/tmp/qa-shots"),
            withIntermediateDirectories: true
        )
    }

    private func snap(_ name: String) {
        let png = XCUIScreen.main.screenshot().pngRepresentation
        try? png.write(to: URL(fileURLWithPath: "/tmp/qa-shots/\(name).png"))
    }

    private func openSettingsTab(_ app: XCUIApplication) {
        let settingsTab = app.tabBars.buttons["Settings"]
        XCTAssertTrue(settingsTab.waitUntilExists(timeout: 10))
        if !settingsTab.isSelected { settingsTab.tap() }
    }

    /// Opens the Export Profiles management sheet from Settings.
    private func openProfilesManagementSheet(_ app: XCUIApplication) {
        openSettingsTab(app)
        let row = app.buttons["export.profiles.entry"]
        XCTAssertTrue(row.waitUntilExists(timeout: 10), "Export Profiles row should exist in Settings")
        row.tap()
        XCTAssertTrue(
            app.navigationBars["Export Profiles"].waitUntilExists(timeout: 10),
            "management sheet should open from Settings"
        )
    }

    /// Duplicates the migrated profile through the current detail action. The management toolbar
    /// now creates a blank profile, so it is not the duplication surface these journeys exercise.
    private func duplicateDefaultProfile(_ app: XCUIApplication) {
        let defaultRow = app.buttons["export.profiles.row.Default"]
        XCTAssertTrue(defaultRow.waitUntilExists(timeout: 5))
        defaultRow.tap()

        let duplicate = app.buttons["Duplicate"]
        for _ in 0..<6 {
            if duplicate.exists && duplicate.isHittable { break }
            app.swipeUp()
        }
        XCTAssertTrue(duplicate.waitUntilExists(timeout: 5), "profile detail should offer duplication")
        XCTAssertTrue(duplicate.isHittable, "Duplicate should be tappable")
        duplicate.tap()

        let keepDuplicate = app.buttons["Keep It"]
        if keepDuplicate.waitUntilExists(timeout: 2) {
            keepDuplicate.tap()
        }
        app.navigationBars.buttons.firstMatch.tap()
        XCTAssertTrue(app.navigationBars["Export Profiles"].waitUntilExists(timeout: 5))
    }

    // MARK: - Journey A: migration + Settings entry

    func testQA_MigrationShowsDefaultProfileInSettings() {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        // The active profile is managed inside the destination screen rather
        // than rendered as a status pill on the Settings entry row.
        openSettingsTab(app)
        let row = app.buttons["export.profiles.entry"]
        XCTAssertTrue(row.waitUntilExists(timeout: 10), "Export Profiles row should exist in Settings")
        snap("01-settings-profiles-row")
        let configuredValue = expectation(for: NSPredicate(format: "value == 'Configured'"), evaluatedWith: row)
        wait(for: [configuredValue], timeout: 10)

        openProfilesManagementSheet(app)
        XCTAssertTrue(
            app.staticTexts["Default"].firstMatch.waitUntilExists(timeout: 5),
            "management list should show the migrated Default profile"
        )
        XCTAssertFalse(
            app.buttons["export.profiles.row.Default 2"].waitUntilExists(timeout: 1),
            "the second-profile fixture must be opt-in and reset between launches"
        )
        snap("01b-management-default-profile")
    }

    // MARK: - Journey B: profile CRUD + last-profile guard

    func testQA_ManagementDuplicateRenameDeleteAndLastProfileGuard() {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()
        openProfilesManagementSheet(app)
        XCTAssertTrue(app.staticTexts["Default"].firstMatch.waitUntilExists(timeout: 5))

        // Duplicate from the profile detail action; the existing active profile remains active.
        duplicateDefaultProfile(app)
        XCTAssertTrue(
            app.staticTexts["Default 2"].waitUntilExists(timeout: 5),
            "duplicate should be created with a unique name"
        )
        snap("03-duplicated-profile-active")

        // Rename the duplicated profile from its detail actions.
        let duplicatedRow = app.buttons["export.profiles.row.Default 2"]
        XCTAssertTrue(duplicatedRow.waitUntilExists(timeout: 5))
        duplicatedRow.tap()
        let rename = app.buttons["Rename…"]
        XCTAssertTrue(rename.waitUntilExists(timeout: 5))
        rename.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitUntilExists(timeout: 5))
        field.tap()
        // The alert pre-fills the current profile name; replace only that text.
        XCTAssertEqual(field.value as? String, "Default 2")
        field.typeText(String(repeating: "\u{8}", count: "Default 2".count) + "Weekly Sleep")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(
            app.navigationBars["Weekly Sleep"].waitUntilExists(timeout: 5),
            "detail navigation title should follow the rename"
        )
        app.navigationBars.buttons.firstMatch.tap() // back to the list
        XCTAssertTrue(
            app.staticTexts["Weekly Sleep"].firstMatch.waitUntilExists(timeout: 5),
            "rename should update the management list"
        )
        snap("04-renamed-profile")

        // Duplication preserves the current active profile. Delete "Weekly Sleep" from its detail.
        let weeklyRow = app.buttons["export.profiles.row.Weekly Sleep"]
        XCTAssertTrue(weeklyRow.waitUntilExists(timeout: 5))
        weeklyRow.tap()
        let delete = app.buttons["Delete Profile…"]
        XCTAssertTrue(delete.waitUntilExists(timeout: 5))
        delete.tap()
        let confirm = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Delete '")
        ).firstMatch
        XCTAssertTrue(confirm.waitUntilExists(timeout: 5))
        confirm.tap()
        XCTAssertTrue(
            app.navigationBars["Export Profiles"].waitUntilExists(timeout: 10),
            "deleting from detail should return to the management list"
        )
        snap("05-after-delete")

        // Last-profile guard: with one profile left, Delete must be disabled.
        let defaultRow = app.buttons["export.profiles.row.Default"]
        XCTAssertTrue(defaultRow.waitUntilExists(timeout: 5))
        defaultRow.tap()
        let guardedDelete = app.buttons["Delete Profile…"]
        XCTAssertTrue(guardedDelete.waitUntilExists(timeout: 5))
        XCTAssertFalse(guardedDelete.isEnabled, "the last remaining profile must not be deletable")
        snap("06-last-profile-guard")
    }

    // MARK: - Journey C: per-profile schedules

    func testQA_ProfileSchedulesToggleCadenceAndEmptyStateFooter() {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        let scheduleTab = app.tabBars.buttons["Schedule"]
        XCTAssertTrue(scheduleTab.waitUntilExists(timeout: 10))
        scheduleTab.tap()

        // Profile Schedules card appears below the legacy schedule card.
        let card = app.staticTexts["Profile Schedules"]
        XCTAssertTrue(card.waitUntilExists(timeout: 10), "Profile Schedules card should exist")
        app.swipeUp()
        if !card.isHittable { app.swipeUp() }
        snap("07-schedule-tab-profiles")

        XCTAssertTrue(
            app.staticTexts["No profile schedules enabled."].waitUntilExists(timeout: 5),
            "empty-state footer should appear when no profile schedules are enabled"
        )
        XCTAssertTrue(
            app.staticTexts["Default"].firstMatch.waitUntilExists(timeout: 5),
            "each profile should have a schedule row"
        )

        // Enable the Default profile's schedule. The row should immediately
        // reflect its seeded daily cadence and replace the empty-state footer.
        let toggle = app.switches["Schedule Default"]
        XCTAssertTrue(toggle.waitUntilExists(timeout: 5))
        toggle.tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label BEGINSWITH 'Daily at'")
            ).firstMatch.waitUntilExists(timeout: 5),
            "enabled schedule should show its seeded daily cadence"
        )
        XCTAssertTrue(
            app.staticTexts["No profile schedules enabled."].waitForNonExistence(timeout: 5),
            "empty-state footer should disappear when a schedule is enabled"
        )
        snap("08-schedule-enabled-daily")

        // Open the cadence editor through the row's dedicated action. The
        // profile name is intentionally read-only after the accessibility split.
        let editSchedule = app.buttons["Edit schedule for Default"]
        XCTAssertTrue(editSchedule.waitUntilExists(timeout: 5))
        editSchedule.tap()
        let enabledToggle = app.switches["Enabled"]
        XCTAssertTrue(enabledToggle.waitUntilExists(timeout: 5), "cadence editor sheet should open")
        snap("09-cadence-editor")

        // The standard-width editor keeps its three native cadence buttons;
        // constrained widths use the separately covered adaptive menu fallback.
        let weekly = app.buttons["Weekly"].firstMatch
        XCTAssertTrue(weekly.waitUntilExists(timeout: 5), "weekly cadence should be available")
        weekly.tap()
        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Weekly on'")
            ).firstMatch.waitUntilExists(timeout: 5),
            "row summary should reflect the weekly cadence"
        )
        snap("10-weekly-cadence-saved")
    }

    // MARK: - Journey D: dedicated management view

    func testQA_ManageProfilesViewDetailCopyIDActivateAndRename() {
        let app = UITestLaunchHelper.firstRunExportApp(duplicateExportProfile: true)
        app.launch()
        openProfilesManagementSheet(app)
        XCTAssertTrue(app.staticTexts["Default"].firstMatch.waitUntilExists(timeout: 5))

        // Start with an inactive copy; Journey B covers the actual duplication UI.
        XCTAssertTrue(app.staticTexts["Default 2"].waitUntilExists(timeout: 5))

        // Both profiles are visible with their names.
        XCTAssertTrue(app.staticTexts["Default"].firstMatch.waitUntilExists(timeout: 5))
        XCTAssertTrue(app.staticTexts["Default 2"].firstMatch.waitUntilExists(timeout: 5))

        // Open the inactive duplicate's detail via its stable row identifier.
        let duplicateRow = app.buttons["export.profiles.row.Default 2"]
        XCTAssertTrue(duplicateRow.waitUntilExists(timeout: 5), "profile rows should expose stable identifiers")
        duplicateRow.tap()
        XCTAssertTrue(
            app.buttons["export.profiles.makeActive"].waitUntilExists(timeout: 5),
            "inactive profile detail should offer activation"
        )
        XCTAssertTrue(app.staticTexts["Profile ID"].waitUntilExists(timeout: 5), "detail should expose the profile ID card")
        XCTAssertTrue(app.staticTexts["Output"].waitUntilExists(timeout: 5), "detail should summarize the frozen output settings")
        XCTAssertTrue(app.staticTexts["Schedule"].waitUntilExists(timeout: 5), "detail should show schedule status")
        snap("12-profile-detail")

        // Copy the profile ID for CLI/automation references.
        let copy = app.buttons["export.profiles.copyID"]
        XCTAssertTrue(copy.waitUntilExists(timeout: 5))
        let copied = expectation(
            for: NSPredicate(format: "value == 'Copied'"),
            evaluatedWith: copy
        )
        copy.tap()
        wait(for: [copied], timeout: 5)

        // Activate the profile: detail pops and the active banner reflects it.
        app.buttons["export.profiles.makeActive"].tap()
        XCTAssertTrue(
            app.navigationBars["Export Profiles"].waitUntilExists(timeout: 10),
            "activating from detail should return to the management list"
        )
        app.buttons["export.profiles.row.Default 2"].tap()
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS 'Active profile'"))
                .firstMatch.waitUntilExists(timeout: 5),
            "activated profile should show the active banner"
        )
        XCTAssertFalse(
            app.buttons["export.profiles.makeActive"].exists,
            "the active profile should not offer activation"
        )
        snap("13-activated-banner")

        // Rename from the detail actions.
        app.buttons["Rename…"].tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitUntilExists(timeout: 5))
        field.tap()
        XCTAssertEqual(field.value as? String, "Default 2")
        field.typeText(String(repeating: "\u{8}", count: "Default 2".count) + "Daily Everything")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(
            app.navigationBars["Daily Everything"].waitUntilExists(timeout: 5),
            "detail navigation title should follow the rename"
        )
        app.navigationBars.buttons.firstMatch.tap() // back to the list
        XCTAssertTrue(
            app.staticTexts["Daily Everything"].firstMatch.waitUntilExists(timeout: 5),
            "list should show the renamed profile"
        )
        snap("14-renamed-in-list")
    }
}
