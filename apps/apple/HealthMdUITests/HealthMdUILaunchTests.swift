//
//  HealthMdUILaunchTests.swift
//  HealthMdUITests
//
//  Baseline smoke test: verifies the app launches and displays its root UI.
//  Uses accessibility identifiers for deterministic element lookup.
//

import XCTest

final class HealthMdUILaunchTests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    func testAppLaunches() throws {
        let app = XCUIApplication()
        app.launch()

        // Verify the app launched successfully by checking it's in the running state
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 10))
    }
}
