import XCTest

/// Pre-release QA journeys for export profiles (release 3.1.0 scope).
/// Covers: first-launch migration to the Default profile, the Export-tab
/// picker (duplicate/rename/delete + last-profile guard), and per-profile
/// schedules (enable toggle, cadence editor, projected-usage footer).
/// Screenshots are written to /tmp/qa-shots for manual review.
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

    private func openExportTab(_ app: XCUIApplication) {
        let exportTab = app.tabBars.buttons["Export"]
        XCTAssertTrue(exportTab.waitForExistence(timeout: 10))
        exportTab.tap()
    }

    // MARK: - Journey A: migration + picker

    func testQA_MigrationShowsDefaultProfilePicker() {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        openExportTab(app)

        // Migration synthesizes the Default profile on first UI appearance.
        let section = app.staticTexts["Export Profile"]
        XCTAssertTrue(section.waitForExistence(timeout: 10), "profile section should appear after migration")
        XCTAssertTrue(app.staticTexts["Default"].waitForExistence(timeout: 5), "migrated Default profile should be active")

        let picker = app.buttons["Export profile picker"].firstMatch
        XCTAssertTrue(picker.waitForExistence(timeout: 5), "profile picker capsule should be reachable")
        snap("01-export-tab-default-profile")

        // Notice copy explains switching + last-profile protection.
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS 'last remaining profile'"))
                .firstMatch.exists,
            "profile notice should explain the deletion guard"
        )
    }

    // MARK: - Journey B: profile CRUD + last-profile guard

    func testQA_PickerDuplicateRenameDeleteAndLastProfileGuard() {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()
        openExportTab(app)
        XCTAssertTrue(app.staticTexts["Default"].waitForExistence(timeout: 10))

        // Open the picker menu.
        let pickerButton = app.buttons["Export profile picker"].firstMatch
        XCTAssertTrue(pickerButton.waitForExistence(timeout: 5), "profile picker menu not reachable")
        pickerButton.tap()
        snap("02-picker-menu-open")

        // Duplicate the active profile.
        let duplicate = app.buttons["New Profile From Current"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5))
        duplicate.tap()
        XCTAssertTrue(
            app.staticTexts["Default 2"].waitForExistence(timeout: 5),
            "duplicate should be created with a unique name and activated"
        )
        snap("03-duplicated-profile-active")

        // Rename the active profile.
        app.buttons["Export profile picker"].firstMatch.tap()
        let rename = app.buttons["Rename…"]
        XCTAssertTrue(rename.waitForExistence(timeout: 5))
        rename.tap()
        let field = app.alerts.textFields.firstMatch
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        // The alert pre-fills the current profile name; replace it wholesale.
        field.typeText(String(repeating: "\u{8}", count: 40))
        field.typeText("Weekly Sleep")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(
            app.staticTexts["Weekly Sleep"].waitForExistence(timeout: 5),
            "rename should update the picker label"
        )
        snap("04-renamed-profile")

        // Switch back to Default via the menu.
        app.buttons["Export profile picker"].firstMatch.tap()
        let defaultItem = app.buttons["Default"].firstMatch
        XCTAssertTrue(defaultItem.waitForExistence(timeout: 5))
        defaultItem.tap()
        XCTAssertTrue(app.staticTexts["Default"].waitForExistence(timeout: 5))

        // Delete "Weekly Sleep": switch to it, then delete.
        app.buttons["Export profile picker"].firstMatch.tap()
        app.buttons["Weekly Sleep"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["Weekly Sleep"].waitForExistence(timeout: 5))
        app.buttons["Export profile picker"].firstMatch.tap()
        let delete = app.buttons["Delete Profile…"]
        XCTAssertTrue(delete.waitForExistence(timeout: 5))
        delete.tap()
        let confirm = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Delete '")
        ).firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(
            app.staticTexts["Default"].waitForExistence(timeout: 5),
            "deleting the active profile should fall back to the remaining profile"
        )
        snap("05-after-delete")

        // Last-profile guard: with one profile left, Delete must be disabled.
        app.buttons["Export profile picker"].firstMatch.tap()
        let guardedDelete = app.buttons["Delete Profile…"]
        XCTAssertTrue(guardedDelete.waitForExistence(timeout: 5))
        XCTAssertFalse(guardedDelete.isEnabled, "the last remaining profile must not be deletable")
        snap("06-last-profile-guard")
        // Leave the menu open; the test ends here.
    }

    // MARK: - Journey C: per-profile schedules

    func testQA_ProfileSchedulesToggleCadenceAndUsageFooter() {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        let scheduleTab = app.tabBars.buttons["Schedule"]
        XCTAssertTrue(scheduleTab.waitForExistence(timeout: 10))
        scheduleTab.tap()

        // Profile Schedules card appears below the legacy schedule card.
        let card = app.staticTexts["Profile Schedules"]
        XCTAssertTrue(card.waitForExistence(timeout: 10), "Profile Schedules card should exist")
        app.swipeUp()
        if !card.isHittable { app.swipeUp() }
        snap("07-schedule-tab-profiles")

        XCTAssertTrue(
            app.staticTexts["No profile schedules enabled."].waitForExistence(timeout: 5),
            "usage footer should start empty"
        )
        XCTAssertTrue(
            app.staticTexts["Default"].firstMatch.waitForExistence(timeout: 5),
            "each profile should have a schedule row"
        )

        // Enable the Default profile's schedule.
        let toggle = app.switches["Schedule Default"]
        XCTAssertTrue(toggle.waitForExistence(timeout: 5))
        toggle.tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'about 30 export actions per month across 1 scheduled profile'")
            ).firstMatch.waitForExistence(timeout: 5),
            "daily cadence should project 30 actions/month"
        )
        snap("08-schedule-enabled-usage")

        // Open the cadence editor by tapping the row.
        app.staticTexts["Default"].firstMatch.tap()
        let enabledToggle = app.switches["Enabled"]
        XCTAssertTrue(enabledToggle.waitForExistence(timeout: 5), "cadence editor sheet should open")
        snap("09-cadence-editor")

        // Frequency is a menu-style picker: open it on the current value
        // ("Daily"), then pick Weekly from the menu it presents.
        let frequencyButton = app.buttons.matching(
            NSPredicate(format: "label BEGINSWITH 'Frequency'")
        ).firstMatch
        XCTAssertTrue(frequencyButton.waitForExistence(timeout: 5))
        frequencyButton.tap()
        let weekly = app.buttons["Weekly"].firstMatch
        XCTAssertTrue(weekly.waitForExistence(timeout: 5), "weekly option should appear in the frequency menu")
        weekly.tap()
        app.buttons["Save"].firstMatch.tap()
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'Weekly on'")
            ).firstMatch.waitForExistence(timeout: 5),
            "row summary should reflect the weekly cadence"
        )
        // Weekly projects ceil(30/7) = 5 actions/month.
        XCTAssertTrue(
            app.staticTexts.matching(
                NSPredicate(format: "label CONTAINS 'about 5 export actions per month'")
            ).firstMatch.waitForExistence(timeout: 5),
            "weekly cadence should project 5 actions/month"
        )
        snap("10-weekly-cadence-saved")
    }

    // MARK: - Journey D: dedicated management view

    func testQA_ManageProfilesViewDetailCopyIDActivateAndRename() {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()
        openExportTab(app)
        XCTAssertTrue(app.staticTexts["Default"].waitForExistence(timeout: 10))

        // Create a second profile so activation switching is observable.
        let pickerButton = app.buttons["Export profile picker"].firstMatch
        XCTAssertTrue(pickerButton.waitForExistence(timeout: 5))
        pickerButton.tap()
        let duplicate = app.buttons["New Profile From Current"]
        XCTAssertTrue(duplicate.waitForExistence(timeout: 5))
        duplicate.tap()
        XCTAssertTrue(app.staticTexts["Default 2"].waitForExistence(timeout: 5))

        // Open the management view from the picker menu.
        pickerButton.tap()
        let manage = app.buttons["Manage Profiles…"]
        XCTAssertTrue(manage.waitForExistence(timeout: 5), "Manage Profiles entry should exist in the picker menu")
        manage.tap()
        XCTAssertTrue(
            app.navigationBars["Export Profiles"].waitForExistence(timeout: 10),
            "management view should push within the Export tab"
        )
        snap("11-manage-profiles-list")

        // Both profiles are visible with their names.
        XCTAssertTrue(app.staticTexts["Default"].firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.staticTexts["Default 2"].firstMatch.waitForExistence(timeout: 5))

        // Open the inactive profile's detail via its stable row identifier.
        let defaultRow = app.buttons["export.profiles.row.Default"]
        XCTAssertTrue(defaultRow.waitForExistence(timeout: 5), "profile rows should expose stable identifiers")
        defaultRow.tap()
        XCTAssertTrue(
            app.buttons["export.profiles.makeActive"].waitForExistence(timeout: 5),
            "inactive profile detail should offer activation"
        )
        XCTAssertTrue(app.staticTexts["Profile ID"].waitForExistence(timeout: 5), "detail should expose the profile ID card")
        XCTAssertTrue(app.staticTexts["Output"].waitForExistence(timeout: 5), "detail should summarize the frozen output settings")
        XCTAssertTrue(app.staticTexts["Schedule"].waitForExistence(timeout: 5), "detail should show schedule status")
        snap("12-profile-detail")

        // Copy the profile ID for CLI/automation references.
        let copy = app.buttons["export.profiles.copyID"]
        XCTAssertTrue(copy.waitForExistence(timeout: 5))
        copy.tap()
        XCTAssertTrue(app.staticTexts["Copied"].waitForExistence(timeout: 5), "copy should confirm")

        // Activate the profile: detail pops and the active banner reflects it.
        app.buttons["export.profiles.makeActive"].tap()
        XCTAssertTrue(
            app.navigationBars["Export Profiles"].waitForExistence(timeout: 10),
            "activating from detail should return to the management list"
        )
        app.buttons["export.profiles.row.Default"].tap()
        XCTAssertTrue(
            app.staticTexts
                .matching(NSPredicate(format: "label CONTAINS 'Active profile'"))
                .firstMatch.waitForExistence(timeout: 5),
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
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(String(repeating: "\u{8}", count: 40))
        field.typeText("Daily Everything")
        app.alerts.buttons["Save"].tap()
        XCTAssertTrue(
            app.navigationBars["Daily Everything"].waitForExistence(timeout: 5),
            "detail navigation title should follow the rename"
        )
        app.navigationBars.buttons.firstMatch.tap() // back to the list
        XCTAssertTrue(
            app.staticTexts["Daily Everything"].firstMatch.waitForExistence(timeout: 5),
            "list should show the renamed profile"
        )
        snap("14-renamed-in-list")
    }
}
