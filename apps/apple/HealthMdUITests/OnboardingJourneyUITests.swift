import XCTest

final class OnboardingJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testReadyCTACompletesOnboardingAndOpensFirstExportPreview() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            showOnboarding: true,
            showReleaseNotes: true,
            useHealthKitExportPreviewFixtures: true,
            analyticsTransport: "offline"
        )
        app.launch()

        tapButton("Start Setup", in: app)

        // Health, sample export, and Obsidian plugin screens.
        tapButton("Continue Setup", in: app)
        tapButton("Continue Setup", in: app)
        tapButton("Continue Setup", in: app)

        // Keep folder setup optional and verify the explicit skip path remains usable.
        tapButton("Skip for Now", in: app)
        tapButton("Try 10 Free Exports", in: app)
        tapButton("Create My First Export", in: app)

        let markdownRow = app.descendants(matching: .any)[
            UITestLaunchHelper.ExportPreview.markdownFileRow
        ]
        XCTAssertTrue(
            markdownRow.waitForExistence(timeout: 15),
            "Completing onboarding should open the preconfigured first-export preview instead of unseen release notes."
        )
        XCTAssertFalse(
            app.staticTexts["Clearer, more reliable exports"].exists,
            "Release notes should not replace the first-export preview after initial onboarding."
        )
    }

    func testReleaseNotesStillAppearForReturningUsers() throws {
        let app = UITestLaunchHelper.configuredApp(showReleaseNotes: true)
        app.launch()

        XCTAssertTrue(
            app.staticTexts["Clearer, more reliable exports"].waitForExistence(timeout: 8),
            "Returning users should still receive release notes for an unseen app version."
        )
    }

    func testSetupActionsArePrimaryAndReadyOffersRepairs() throws {
        let app = UITestLaunchHelper.configuredApp(
            showOnboarding: true,
            analyticsTransport: "offline"
        )
        app.launch()

        tapButton("Start Setup", in: app)
        XCTAssertTrue(app.buttons["Connect Apple Health"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Skip for Now"].exists)
        tapButton("Skip for Now", in: app)

        tapButton("Continue Setup", in: app)
        tapButton("Continue Setup", in: app)

        XCTAssertTrue(app.buttons["Select Export Folder"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Skip for Now"].exists)
        tapButton("Skip for Now", in: app)
        tapButton("Try 10 Free Exports", in: app)

        XCTAssertTrue(app.buttons["Connect"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Choose Folder"].exists)
        XCTAssertTrue(app.buttons["Create My First Export"].exists)

        tapButton("Create My First Export", in: app)
        let setupAlert = app.alerts["Finish Preview Setup"]
        XCTAssertTrue(setupAlert.waitForExistence(timeout: 8))
        XCTAssertTrue(setupAlert.buttons["Connect Apple Health"].exists)
    }

    private func tapButton(_ label: String, in app: XCUIApplication) {
        let button = app.buttons[label]
        XCTAssertTrue(button.waitForExistence(timeout: 8), "Expected onboarding button: \(label)")
        XCTAssertTrue(button.isHittable, "Onboarding button should be tappable: \(label)")
        button.tap()
    }
}
