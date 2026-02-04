import XCTest

final class HealthMdUITests2: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        setupSnapshot(app)
        app.launchArguments.append("-UITestingMode")
        app.launch()
    }

    override func tearDownWithError() throws {
        app = nil
    }

    func testTakeScreenshots() throws {
        // Give the app time to load and animate
        sleep(3)

        // Screenshot 1: Main Dashboard - Clean, centered UI
        // This shows the health and vault status badges, export button
        snapshot("01-MainDashboard")
        sleep(1)

        // Screenshot 2: Export Modal
        // Tap the main export button to show the export options
        let exportButton = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Export Health Data'")).firstMatch
        if exportButton.exists {
            exportButton.tap()
            sleep(2)
            snapshot("02-ExportOptions")

            // Dismiss the modal
            let cancelButton = app.buttons["Cancel"]
            if cancelButton.exists {
                cancelButton.tap()
                sleep(1)
            }
        }

        // Screenshot 3: Schedule Settings
        // Show the scheduling feature with time picker
        let scheduleButton = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Schedule'")).firstMatch
        if scheduleButton.exists {
            scheduleButton.tap()
            sleep(2)
            snapshot("03-ScheduleSettings")

            // Dismiss the modal by swiping down
            app.swipeDown()
            sleep(1)
        }

        // Screenshot 4: Advanced Settings
        // Display data type selection and format options
        let advancedButton = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Advanced Settings'")).firstMatch
        if advancedButton.exists {
            advancedButton.tap()
            sleep(2)
            snapshot("04-AdvancedSettings")

            // Dismiss the modal
            app.swipeDown()
            sleep(1)
        }

        // Screenshot 5: Vault Connection Flow
        // Show the folder picker for vault selection
        let vaultButton = app.buttons.containing(NSPredicate(format: "label CONTAINS[c] 'Vault'")).firstMatch
        if vaultButton.exists {
            vaultButton.tap()
            sleep(2)
            snapshot("05-VaultSelection")
        }
    }
}
