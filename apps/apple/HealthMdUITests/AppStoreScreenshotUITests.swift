import XCTest

/// Captures the raw screens behind the App Store boards (`docs/design/liquid-glass/screens/AS_*`).
/// Runs only when `APPSTORE_SCREENSHOT_DIR` is set; files are named `<device>-<screen>.png`, where
/// `<device>` is `APPSTORE_DEVICE` or, by default, `iphone`/`ipad` from the running idiom.
/// `APPSTORE_DEVICE=duo` (a real iPhone Duo) captures the display it runs on: `duo-outer` when
/// folded, `duo-inner-archive` and `duo-inner-automation` when unfolded.
///
/// The fixtures are deterministic: the four automations of the boards
/// (`UITEST_APPSTORE_FIXTURE_PROFILES`) and a coverage month keyed to day numbers
/// (`UITEST_SEED_COVERAGE`, `CoverageScreenshotFixture`) in the month before the current one,
/// which every Archive capture opens, so the result does not depend on today's date.
///
/// Every lookup uses an accessibility identifier (or fixture data such as an automation name),
/// never localized copy, so the same run captures any simulator language.
///
/// The boards show the dark glass UI, so the simulator is switched to dark appearance; iPad runs in
/// landscape. `scripts/app-store-screenshots/compose.swift` places these captures into the boards;
/// `screenshots/macos/README.md` is the runbook (simulators, status bar, command sequence).
final class AppStoreScreenshotUITests: XCTestCase {
    private var directory: String? { ProcessInfo.processInfo.environment["APPSTORE_SCREENSHOT_DIR"] }
    private var isPad: Bool { UIDevice.current.userInterfaceIdiom == .pad }
    private var deviceName: String {
        ProcessInfo.processInfo.environment["APPSTORE_DEVICE"] ?? (isPad ? "ipad" : "iphone")
    }

    override func setUp() {
        super.setUp()
        guard directory != nil else { return }
        XCUIDevice.shared.appearance = .dark
        if isPad { XCUIDevice.shared.orientation = .landscapeLeft }
    }

    override func tearDown() {
        if directory != nil {
            XCUIDevice.shared.appearance = .unspecified
            if isPad { XCUIDevice.shared.orientation = .portrait }
        }
        super.tearDown()
    }

    private func save(_ name: String) {
        guard let directory else { return }
        let url = URL(fileURLWithPath: directory).appendingPathComponent("\(deviceName)-\(name).png")
        try? XCUIScreen.main.screenshot().pngRepresentation.write(to: url)
    }

    private func launch() -> XCUIApplication {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            syncState: "connected",
            scheduleEnabled: true,
            useHealthKitExportPreviewFixtures: true,
            macExportStatus: "ready"
        )
        app.launchEnvironment["UITEST_APPSTORE_FIXTURE_PROFILES"] = "true"
        // ComposeGlass: the Daily automation writes Markdown + Bases.
        app.launchEnvironment["UITEST_HEALTHKIT_EXPORT_PREVIEW_FORMATS"] = "markdown+bases"
        app.launchEnvironment["UITEST_SEED_COVERAGE"] = "true"
        if deviceName == "duo" {
            // DuoOuterG's unfold invitation appears once this phone has shown its unfolded
            // layout, so either capture order works. Argument domain: nothing is persisted.
            app.launchArguments += ["-glass.hasSeenUnfoldedLayout", "YES"]
        } else {
            // CLIDestG / SettingsGlass / iPadSettingsG: a paired "Studio Mac" (display only, no
            // Keychain or network) with Direct CLI access on, and a listed WHOOP connection
            // (shown only in builds with CONNECTED_APPS_WHOOP_ENABLED=YES).
            app.launchEnvironment["UITEST_APPSTORE_PAIRED_CLI"] = "true"
            app.launchEnvironment["UITEST_APPSTORE_CONNECTED_WHOOP"] = "true"
            app.launchArguments += ["-directCLIEnabled", "YES"]
        }
        app.launch()
        return app
    }

    private func openTab(_ app: XCUIApplication, _ tab: String) {
        let button = app.buttons["glass.tab.\(tab)"]
        XCTAssertTrue(button.waitForExistence(timeout: 10), "Missing tab \(tab)")
        button.tap()
    }

    /// Opens the first automation and, optionally, one of its pages by its
    /// `glass.automation.<row>` identifier.
    private func openAutomation(_ app: XCUIApplication, row: String?) {
        openTab(app, "automations")
        let card = app.buttons["glass.automation.card"].firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 5))
        card.tap()
        guard let row else { return }
        let target = app.buttons["glass.automation.\(row)"].firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5), "Missing row \(row)")
        target.tap()
    }

    /// Opens the first automation's composer (ComposeGlass) through "Edit sentence →".
    private func openComposer(_ app: XCUIApplication) {
        openAutomation(app, row: nil)
        let edit = app.buttons["glass.automation.editSentence"].firstMatch
        XCTAssertTrue(edit.waitForExistence(timeout: 5), "Missing Edit sentence")
        edit.tap()
    }

    /// Opens a Settings row by its `glass.settings.*` identifier and waits for the destination.
    private func openSettingsRow(_ app: XCUIApplication, _ row: String, expecting screen: String) {
        openTab(app, "settings")
        XCTAssertTrue(app.descendants(matching: .any)["glass.settings"].waitForExistence(timeout: 5))
        let button = app.buttons["glass.settings.\(row)"]
        XCTAssertTrue(button.waitForExistence(timeout: 5), "Missing settings row \(row)")
        button.tap()
        XCTAssertTrue(app.descendants(matching: .any)[screen].waitForExistence(timeout: 5), "Missing \(screen)")
    }

    /// Opens the seeded month (the one before the current month), optionally filters it to
    /// one automation, and selects the board's day: the 19th for All (a gap), the 15th for
    /// Agent feed (no refresh sent).
    private func showSeededMonth(_ app: XCUIApplication, profile: String? = nil) {
        XCTAssertTrue(app.descendants(matching: .any)["glass.archive"].waitForExistence(timeout: 10))
        let previous = app.buttons["glass.archive.previousMonth"].firstMatch
        XCTAssertTrue(previous.waitForExistence(timeout: 5), "Missing Previous month")
        previous.tap()
        if let profile {
            // Automation names are fixture data, identical in every language.
            let chip = app.buttons[profile].firstMatch
            XCTAssertTrue(chip.waitForExistence(timeout: 5), "Missing archive chip \(profile)")
            chip.tap()
        }
        selectSeededDay(app, profile == nil ? 19 : 15)
    }

    /// Taps a day tile of the shown month by its `glass.calendar.day.<n>` identifier.
    private func selectSeededDay(_ app: XCUIApplication, _ day: Int) {
        let tile = app.buttons["glass.calendar.day.\(day)"].firstMatch
        XCTAssertTrue(tile.waitForExistence(timeout: 5), "Missing day tile \(day)")
        tile.tap()
    }

    /// Taps a Dates segment of the Export now sheet by position (Yesterday, 7 days, 30 days,
    /// Custom), without localized copy: in the sheet, above its confirm button, the range row is
    /// the lowest selected control, below the selected automation chip.
    private func selectExportNowRange(_ app: XCUIApplication, index: Int) {
        let confirmTop = app.buttons["glass.exportNow.confirm"].frame.minY
        let inSheet = NSPredicate(format: "NOT (identifier BEGINSWITH 'glass.tab.')")
        let selected = app.buttons.matching(inSheet)
            .matching(NSPredicate(format: "isSelected == true")).allElementsBoundByIndex
            .filter { $0.frame.maxY < confirmTop }
        guard let current = selected.max(by: { $0.frame.minY < $1.frame.minY }) else {
            XCTFail("Missing selected Dates segment")
            return
        }
        let row = app.buttons.matching(inSheet).allElementsBoundByIndex
            .filter { abs($0.frame.midY - current.frame.midY) < 2 && $0.frame.height > 0 }
            .sorted { $0.frame.minX < $1.frame.minX }
        XCTAssertGreaterThan(row.count, index, "Missing Dates segment \(index)")
        guard row.count > index else { return }
        row[index].tap()
    }

    private func switchOn(_ app: XCUIApplication, _ identifier: String) {
        let toggle = app.switches[identifier].firstMatch
        XCTAssertTrue(toggle.waitForExistence(timeout: 3), "Missing switch \(identifier)")
        guard toggle.exists else { return }
        if (toggle.value as? String) != "1" { toggle.switches.firstMatch.exists ? toggle.switches.firstMatch.tap() : toggle.tap() }
    }

    private func capture(_ name: String, _ steps: (XCUIApplication) -> Void) {
        let app = launch()
        steps(app)
        sleep(2)
        save(name)
        app.terminate()
    }

    func testCaptureAppStoreScreens() throws {
        guard directory != nil else { throw XCTSkip("Set APPSTORE_SCREENSHOT_DIR to capture App Store screens.") }
        continueAfterFailure = true
        if deviceName == "duo" { captureDuoScreens() } else if isPad { captureIPadScreens() } else { captureIPhoneScreens() }
    }

    /// iPhone 6.9″ boards AS_iPhone_1…9.
    private func captureIPhoneScreens() {
        capture("archive") { app in showSeededMonth(app) }                         // AS_iPhone_1
        capture("automation") { app in openComposer(app) }                         // AS_iPhone_2
        capture("archive-profile") { app in                                        // AS_iPhone_3
            // ArchiveGlassFeed: the API automation with Today Refresh, filtered on its own.
            showSeededMonth(app, profile: "Agent feed")
        }
        capture("metrics") { app in openAutomation(app, row: "metrics") }          // AS_iPhone_4
        capture("formats") { app in                                                // AS_iPhone_5
            openAutomation(app, row: "formats")
            // Unsaved: shows every format switched on, as on the slide.
            for format in ["obsidianBases", "json", "csv"] { switchOn(app, "glass.formats.format.\(format)") }
        }
        capture("export-now") { app in                                             // AS_iPhone_6
            let button = app.buttons["glass.exportNow"]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
            XCTAssertTrue(app.buttons["glass.exportNow.confirm"].waitForExistence(timeout: 5))
            // ExportNowG shows the Daily automation over 7 days.
            selectExportNowRange(app, index: 1)
        }
        capture("automations") { app in                                            // AS_iPhone_7
            openTab(app, "automations")
            XCTAssertTrue(app.descendants(matching: .any)["glass.automations"].waitForExistence(timeout: 5))
        }
        capture("settings") { app in                                               // AS_iPhone_8
            openTab(app, "settings")
            XCTAssertTrue(app.descendants(matching: .any)["glass.settings"].waitForExistence(timeout: 5))
        }
        capture("cli") { app in openSettingsRow(app, "cli", expecting: "glass.cliDestination") } // AS_iPhone_9

        // Not on a board today; kept for the website and future slides.
        capture("export-preview") { app in
            let button = app.buttons["glass.exportNow"]
            XCTAssertTrue(button.waitForExistence(timeout: 10))
            button.tap()
            let preview = app.buttons["glass.exportNow.preview"]
            XCTAssertTrue(preview.waitForExistence(timeout: 5))
            preview.tap()
            XCTAssertTrue(
                app.descendants(matching: .any)[UITestLaunchHelper.ExportPreview.markdownFileRow]
                    .waitForExistence(timeout: 15)
            )
        }
        capture("daily-notes") { app in
            openAutomation(app, row: "dailyNotes")
            switchOn(app, "glass.dailyNotes.merge")
        }
        capture("customize-format") { app in openAutomation(app, row: "formatCustom") }
        capture("entries") { app in
            openAutomation(app, row: "entries")
            switchOn(app, "glass.entries.enabled")
        }
        capture("schedule") { app in openAutomation(app, row: "schedule") }
        capture("mac") { app in openSettingsRow(app, "mac", expecting: "glass.macDestination") }
    }

    /// iPad 13″ landscape boards AS_iPad_1…3. Each board frames an 1180 × 820 pt window, so run on
    /// an 11-inch iPad Air simulator in landscape for an exact fit.
    private func captureIPadScreens() {
        capture("archive") { app in showSeededMonth(app) }                         // AS_iPad_1
        capture("automations") { app in                                            // AS_iPad_2
            // Regular width: the list beside the selected automation's composer.
            openTab(app, "automations")
            let card = app.buttons["glass.automation.card"].firstMatch
            XCTAssertTrue(card.waitForExistence(timeout: 5))
            card.tap()
        }
        capture("settings-cli") { app in                                           // AS_iPad_3
            openSettingsRow(app, "cli", expecting: "glass.cliDestination")
        }
    }

    /// iPhone Duo boards AS_Duo_1…3, on a real device (no simulator models either display).
    /// Run once folded and once unfolded. The window's short side tells the displays apart
    /// (outer 466 pt, inner 669 pt) in either orientation.
    private func captureDuoScreens() {
        let probe = launch()
        let frame = probe.windows.firstMatch.frame
        let isInner = min(frame.width, frame.height) > 560
        probe.terminate()
        if isInner {
            capture("inner-archive") { app in showSeededMonth(app) }                // DuoInnerArchiveG
            capture("inner-automation") { app in                                    // DuoInnerComposeG
                // An unfolded phone keeps the column, so the composer opens from the detail.
                openComposer(app)
            }
        } else {
            capture("outer") { app in showSeededMonth(app) }                        // DuoOuterG
        }
    }
}
