import XCTest

/// UI tests for the first-run export journey: auth -> vault -> export.
/// Uses test-mode DI hooks to simulate authorized state and vault selection.
final class ExportJourneyUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - First-Run Export Journey

    func testFirstRunExportJourney_showsExportButton_andCompletesExport() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        // Verify app launched and is on the export tab (default)
        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5), "Export button should be visible on launch")

        // Verify health badge shows connected (CompactStatusBadge is a Button)
        let healthBadge = app.buttons[UITestLaunchHelper.Export.healthBadge]
        XCTAssertTrue(healthBadge.waitForExistence(timeout: 3), "Health badge should be visible")

        // Verify vault badge shows connected
        let vaultBadge = app.buttons[UITestLaunchHelper.Export.vaultBadge]
        XCTAssertTrue(vaultBadge.waitForExistence(timeout: 3), "Vault badge should be visible")

        // Tap export button — in test mode, simulateTestExport runs immediately.
        exportButton.tap()

        // After the simulated export, the status badge should appear
        // ExportStatusBadge is a complex view — use descendants query
        let statusBadge = app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge]
        let completed = statusBadge.waitForExistence(timeout: 10)
        let diagnostic = app.staticTexts["export.synthetic.statusMessage"]
        let syntheticStatus = diagnostic.exists ? diagnostic.label : "no synthetic stage element"
        XCTAssertTrue(completed, "Export status badge should appear after export. Synthetic stage: \(syntheticStatus)")
        XCTAssertTrue(
            app.buttons["View Exported File"].exists,
            "A successful local export should offer an exact-file viewer"
        )
        XCTAssertTrue(
            app.buttons["Browse Export Folder"].exists,
            "A successful local export should offer the exact parent folder in the document picker"
        )
    }

    /// The App Review iPad lane selects this empty-device recovery journey.
    /// Use the existing synthetic export result; never read simulator health data.
    func testNoDataExport_showsGuidanceInsteadOfGenericError() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            exportResult: "no-data"
        )
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        // The no-data guidance is a Geist-designed in-app dialog (not a native alert),
        // matched by its localized title text like the other dialogs in this journey.
        let noDataDialog = app.staticTexts["No Health Data Found"]
        XCTAssertTrue(
            noDataDialog.waitForExistence(timeout: 30),
            "An empty Health store should produce a guided empty state, not a generic error"
        )
        let guidance = app.staticTexts.matching(NSPredicate(
            format: "label CONTAINS %@", "Try All Time or another date range"
        )).firstMatch
        XCTAssertTrue(guidance.waitForExistence(timeout: 5))
        XCTAssertTrue(guidance.isHittable, "Empty-device recovery guidance must be visible")
        XCTAssertTrue(app.buttons["Open Health App"].waitForExistence(timeout: 5))
        XCTAssertTrue(app.buttons["Done"].exists)
        XCTAssertFalse(app.staticTexts["Export Couldn\u{2019}t Finish"].exists)
    }

    func testFailedExport_updatesBottomCardBeforeShowingDetails() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            exportResult: "fail"
        )
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        let statusCard = app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge]
        XCTAssertTrue(statusCard.waitForExistence(timeout: 10))
        XCTAssertTrue(statusCard.label.contains("Export failed"))
        XCTAssertFalse(
            app.staticTexts["Export Couldn’t Finish"].exists,
            "A terminal failure should update the status card instead of also opening a dialog"
        )

        let detailsButton = app.buttons["Details"]
        XCTAssertTrue(detailsButton.waitForExistence(timeout: 3))
        detailsButton.tap()
        XCTAssertTrue(app.staticTexts["Export Couldn’t Finish"].waitForExistence(timeout: 5))
    }

    func testMultiFileExport_hidesCompletionUntilEntireExportFinishes() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            exportResult: "intermediate-success"
        )
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        let finishBatch = app.buttons[UITestLaunchHelper.Export.finishSimulatedBatch]
        XCTAssertTrue(
            finishBatch.waitForExistence(timeout: 5),
            "The fixture should publish its per-file result and wait before finishing the batch"
        )

        XCTAssertTrue(
            app.buttons[UITestLaunchHelper.Export.cancelExportButton].waitForExistence(timeout: 1),
            "The simulated multi-file export should still be running"
        )
        XCTAssertFalse(
            exportButton.exists,
            "The export action bar should hide while the unified bottom status card owns progress and cancellation"
        )

        let statusCard = app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge]
        XCTAssertTrue(
            statusCard.exists,
            "The bottom status card should remain visible while the export is running"
        )

        XCTAssertFalse(app.buttons["View Exported File"].exists)

        // Explicitly release the batch after every intermediate-state assertion.
        XCTAssertTrue(finishBatch.isHittable, "The fixture's completion control should remain accessible")
        finishBatch.tap()

        XCTAssertTrue(
            app.buttons[UITestLaunchHelper.Export.cancelExportButton].exists,
            "The in-progress status card should expose cancellation"
        )
        XCTAssertFalse(
            app.buttons["View Exported File"].waitForExistence(timeout: 0.8),
            "A per-file completion must not replace progress while the batch is running"
        )

        XCTAssertTrue(
            app.buttons["View Exported File"].waitForExistence(timeout: 5),
            "The same bottom status card should update with terminal export actions"
        )
        XCTAssertTrue(statusCard.exists)
        XCTAssertFalse(app.buttons[UITestLaunchHelper.Export.cancelExportButton].exists)
        XCTAssertTrue(app.buttons["Browse Export Folder"].exists)
    }

    func testSuccessfulExport_previewsExactMarkdownFileInApp() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        let previewButton = app.buttons["View Exported File"]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 10))
        previewButton.tap()

        let viewer = app.descendants(matching: .any)[UITestLaunchHelper.ExportedFile.viewer]
        XCTAssertTrue(
            viewer.waitForExistence(timeout: 5),
            "Markdown should open in Health.md’s in-app viewer"
        )
        XCTAssertTrue(app.navigationBars["2026-03-28.md"].exists)
        XCTAssertTrue(app.staticTexts["Health.md UI test export"].exists)
        XCTAssertFalse(app.otherElements["QLPreviewControllerView"].exists)

        app.buttons["Source"].tap()
        let source = app.descendants(matching: .any)[UITestLaunchHelper.ExportedFile.source]
        XCTAssertTrue(source.waitForExistence(timeout: 3))
        XCTAssertTrue(source.label.contains("# Health.md UI test export"))

        app.buttons[UITestLaunchHelper.ExportedFile.done].tap()
        XCTAssertTrue(
            app.buttons["Browse Export Folder"].waitForExistence(timeout: 5),
            "Closing the viewer should preserve the export-folder action"
        )
    }

    func testSuccessfulExport_folderBrowserRendersOnFirstPresentationAndReopens() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        // Files can browse the UI host's synthetic Documents directory, not tmp.
        app.launchEnvironment["UITEST_BROWSABLE_VAULT"] = "true"
        app.launch()
        addTeardownBlock { UITestLaunchHelper.finishSystemPresentation(in: app) }

        // Match normal setup: acquire the vault through Files before exporting.
        // An unselected app-container path can make a cold provider fall back to
        // its root even though the requested directory exists. Do not open the
        // export browser during setup; its first presentation stays under test.
        let vaultBadge = app.buttons[UITestLaunchHelper.Export.vaultBadge]
        XCTAssertTrue(vaultBadge.waitForExistence(timeout: 5))
        vaultBadge.tap()
        let openFolder = app.buttons["Open"].firstMatch
        guard openFolder.waitForExistence(timeout: 30) else {
            XCTFail("Vault setup must present the real folder picker")
            return
        }
        app.buttons["Browse"].firstMatch.tap()
        let setupFiles = app.collectionViews["File View"]
        guard setupFiles.waitForExistence(timeout: 10) else {
            XCTFail("Vault setup must render the local Files provider")
            return
        }
        let testVault = setupFiles.cells.containing(.staticText, identifier: "TestVault").firstMatch
        if !testVault.waitForExistence(timeout: 2) {
            let appContainer = setupFiles.cells.containing(.staticText, identifier: "Health.md").firstMatch
            guard appContainer.waitForExistence(timeout: 5) else {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "Synthetic vault selection hierarchy"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
                XCTFail("Files must expose the UI-test app's synthetic document container")
                return
            }
            appContainer.tap()
        }
        guard testVault.waitForExistence(timeout: 10) else {
            XCTFail("Files must expose the synthetic TestVault folder")
            return
        }
        // Tapping a filename in the provider's icon view need not enter its folder.
        // Select the cell and observe navigation before Open can select a parent.
        testVault.tap()
        // SDK27 Files exposes the current folder as an actions-menu button.
        let selectedFolderTitle = app.navigationBars.buttons["TestVault, Actions Menu"].firstMatch
        guard selectedFolderTitle.waitForExistence(timeout: 10) else {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Synthetic TestVault navigation hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Synthetic TestVault navigation"
            screenshot.lifetime = .keepAlways
            add(screenshot)
            XCTFail("Files must enter TestVault before selecting the export destination")
            return
        }
        openFolder.tap()
        let pickerDismissed = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"), object: openFolder
        )
        let dismissalResult = XCTWaiter.wait(for: [pickerDismissed], timeout: 10)
        if dismissalResult != .completed {
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = "Synthetic vault picker dismissal hierarchy"
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
            let screenshot = XCTAttachment(screenshot: app.screenshot())
            screenshot.name = "Synthetic vault picker dismissal"
            screenshot.lifetime = .keepAlways
            add(screenshot)
        }
        XCTAssertEqual(dismissalResult, .completed)
        XCTAssertTrue(vaultBadge.label.contains("TestVault"), "Files must select the synthetic vault, not its parent")

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        let browseButton = app.buttons["Browse Export Folder"]
        for opening in 0..<2 {
            XCTAssertTrue(browseButton.waitForExistence(timeout: 10))
            browseButton.tap()

            let files = app.collectionViews["File View"]
            // A fresh hosted simulator can spend over ten seconds launching Files.
            // Keep the first presentation open: reopening must not make it pass.
            let startupTimeout: TimeInterval = opening == 0 ? 30 : 10
            guard files.waitForExistence(timeout: startupTimeout) else {
                let hierarchy = XCTAttachment(string: app.debugDescription)
                hierarchy.name = "Export folder opening \(opening + 1) hierarchy"
                hierarchy.lifetime = .keepAlways
                add(hierarchy)
                let screenshot = XCTAttachment(screenshot: app.screenshot())
                screenshot.name = "Export folder opening \(opening + 1)"
                screenshot.lifetime = .keepAlways
                add(screenshot)
                XCTFail("The first opening must render the document picker instead of an empty sheet")
                return
            }
            let exportedFile = files.descendants(matching: .any).matching(
                NSPredicate(format: "label CONTAINS %@", "2026-03-28")
            ).firstMatch
            XCTAssertTrue(exportedFile.waitForExistence(timeout: 5), "The picker must render the synthetic export filename instead of an empty sheet")
            app.buttons["Cancel"].firstMatch.tap()
        }
        XCTAssertTrue(browseButton.waitForExistence(timeout: 5))
    }

    func testArchivedExport_stillUsesQuickLook() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launchEnvironment["UITEST_ARCHIVE_EXPORTS"] = "true"
        app.launch()
        addTeardownBlock { UITestLaunchHelper.finishSystemPresentation(in: app) }

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        let previewButton = app.buttons["View Exported File"]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 10))
        previewButton.tap()

        XCTAssertTrue(
            app.otherElements["QLPreviewControllerView"].waitForExistence(timeout: 5),
            "ZIP archives should continue to use Quick Look"
        )
        XCTAssertFalse(
            app.descendants(matching: .any)[UITestLaunchHelper.ExportedFile.viewer].exists
        )
    }

    func testPartialExportToast_opensHealthPermissionGuidance() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            exportResult: "partial"
        )
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        exportButton.tap()

        let statusBadge = app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge]
        XCTAssertTrue(statusBadge.waitForExistence(timeout: 10), "Partial export warning toast should appear")
        XCTAssertTrue(
            statusBadge.label.contains("Partial export: Health permissions need attention. Tap to fix."),
            "The warning should explain that permission guidance is available"
        )
        let reviewIssues = app.buttons["Review export issues"]
        XCTAssertTrue(reviewIssues.waitForExistence(timeout: 3))
        reviewIssues.tap()

        // Geist dialogs are in-tree SwiftUI overlays rather than native UIAlert instances.
        let permissionTitle = app.staticTexts["Health Permissions Needed"]
        XCTAssertTrue(permissionTitle.waitForExistence(timeout: 5), "Tapping the toast should show permission guidance")
        let dialogDisappears = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "exists == false"),
            object: permissionTitle
        )
        XCTAssertEqual(
            XCTWaiter.wait(for: [dialogDisappears], timeout: 9),
            .timedOut,
            "Permission guidance must stay open beyond the toast's eight-second expiry"
        )
        XCTAssertTrue(app.buttons["Request Access"].waitForExistence(timeout: 3))
        XCTAssertTrue(app.buttons["Open Health App"].waitForExistence(timeout: 3))
        let biologicalSexGuidance = app.staticTexts.matching(
            NSPredicate(format: "label CONTAINS %@", "Biological Sex")
        ).firstMatch
        XCTAssertTrue(biologicalSexGuidance.waitForExistence(timeout: 3))
    }

    func testExportPreview_rendersHealthKitFixtureValues() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            useHealthKitExportPreviewFixtures: true
        )
        app.launch()

        let previewButton = app.buttons[UITestLaunchHelper.Export.previewButton]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5), "Preview button should be visible on launch")
        previewButton.tap()

        let markdownRow = app.descendants(matching: .any)[UITestLaunchHelper.ExportPreview.markdownFileRow]
        XCTAssertTrue(markdownRow.waitForExistence(timeout: 10), "Lossless preview should render one representative Markdown file")

        let weeklyRollupRow = app.descendants(matching: .any)["exportPreview.fileRow.rollupSummary.Weekly.Markdown"]
        XCTAssertFalse(weeklyRollupRow.exists, "Lossless preview should omit supplemental roll-up files")
        markdownRow.tap()

        let fileContent = app.staticTexts[UITestLaunchHelper.ExportPreview.fileContent]
        XCTAssertTrue(fileContent.waitForExistence(timeout: 5), "Rendered export content should be visible")

        let renderedExport = fileContent.label
        XCTAssertTrue(
            renderedExport.split(separator: "\n").contains { $0 == "schema_version: 8" },
            "Preview should render the current export schema version"
        )
        XCTAssertTrue(renderedExport.contains("units:"), "Preview should render self-describing frontmatter units")
        XCTAssertTrue(renderedExport.contains("**Steps:** 12,500"), "Preview should render current fixture activity copy")
        XCTAssertTrue(renderedExport.contains("**Active Calories:** 520 kcal"), "Preview should render current fixture energy copy")
    }

    func testExportPreview_canStartExportFlow() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: false,
            purchaseUnlocked: true,
            useHealthKitExportPreviewFixtures: true
        )
        app.launch()
        addTeardownBlock { UITestLaunchHelper.finishSystemPresentation(in: app) }

        let previewButton = app.buttons[UITestLaunchHelper.Export.previewButton]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5))
        previewButton.tap()

        let markdownRow = app.descendants(matching: .any)[UITestLaunchHelper.ExportPreview.markdownFileRow]
        XCTAssertTrue(markdownRow.waitForExistence(timeout: 10), "Preview should finish before export is available")

        let previewExportButton = app.buttons[UITestLaunchHelper.ExportPreview.exportButton]
        XCTAssertTrue(previewExportButton.waitForExistence(timeout: 5), "Preview should offer an export action")
        XCTAssertTrue(previewExportButton.isEnabled)
        previewExportButton.tap()

        XCTAssertTrue(
            app.buttons["Browse"].waitForExistence(timeout: 5),
            "Exporting from preview should dismiss it and run the existing destination preflight"
        )
    }

    func testExportPreview_opensWhenNoFormatsAreSelected() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true
        )
        app.launchEnvironment["UITEST_NO_EXPORT_FORMATS"] = "true"
        app.launch()

        let previewButton = app.buttons[UITestLaunchHelper.Export.previewButton]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5), "Preview button should be visible")
        XCTAssertTrue(previewButton.isEnabled, "Preview should explain an empty format selection instead of ignoring taps")
        previewButton.tap()

        XCTAssertTrue(
            app.staticTexts["No data to preview"].waitForExistence(timeout: 5),
            "Preview should open its empty state when no formats are selected"
        )
    }

    func testExportPreview_availableWithAnalyticsOffline() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            useHealthKitExportPreviewFixtures: true,
            analyticsTransport: "offline",
            remoteConfig: "offline"
        )
        app.launch()

        let previewButton = app.buttons[UITestLaunchHelper.Export.previewButton]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5), "Preview button should be visible with analytics offline")
        XCTAssertTrue(previewButton.isEnabled, "Preview should remain enabled with analytics offline")
        previewButton.tap()

        let markdownRow = app.descendants(matching: .any)[UITestLaunchHelper.ExportPreview.markdownFileRow]
        XCTAssertTrue(markdownRow.waitForExistence(timeout: 10), "Preview should render with analytics offline")
    }

    func testExportPreview_promptsOnlyForMissingHealthPermission() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: false,
            vaultSelected: false,
            purchaseUnlocked: true
        )
        app.launch()

        let previewButton = app.buttons[UITestLaunchHelper.Export.previewButton]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5), "Preview button should be visible without Health permission")
        XCTAssertTrue(previewButton.isEnabled, "Preview should stay enabled so users can learn Health permission is missing")
        previewButton.tap()

        // Geist dialogs are in-tree SwiftUI overlays rather than native UIAlert instances.
        let setupPromptTitle = app.staticTexts["Finish Preview Setup"]
        XCTAssertTrue(setupPromptTitle.waitForExistence(timeout: 5), "Preview should prompt for missing Health permission")
        XCTAssertTrue(app.buttons["Connect Apple Health"].waitForExistence(timeout: 3), "Prompt should offer Health permissions")
        XCTAssertFalse(app.buttons["Choose Folder"].exists, "Preview should not require folder selection")
    }

    func testExportPreview_rendersWithoutLocalFolderSelection() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: false,
            purchaseUnlocked: true,
            useHealthKitExportPreviewFixtures: true
        )
        app.launch()

        let previewButton = app.buttons[UITestLaunchHelper.Export.previewButton]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5), "Preview button should be visible without a local folder")
        XCTAssertTrue(previewButton.isEnabled, "Preview should not require folder selection")
        previewButton.tap()

        let markdownRow = app.descendants(matching: .any)[UITestLaunchHelper.ExportPreview.markdownFileRow]
        XCTAssertTrue(markdownRow.waitForExistence(timeout: 10), "Preview should render without requiring a folder")
    }

    func testExportButton_staysEnabledWithoutHealthAuth() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: false,
            vaultSelected: true,
            purchaseUnlocked: true
        )
        app.launch()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        XCTAssertTrue(
            exportButton.isEnabled,
            "Export button should remain actionable so it can guide the user to Apple Health setup"
        )
    }

    func testExportButton_staysEnabledWithoutVault() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: false,
            purchaseUnlocked: true
        )
        app.launch()
        addTeardownBlock { UITestLaunchHelper.finishSystemPresentation(in: app) }

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))
        XCTAssertTrue(
            exportButton.isEnabled,
            "Export button should remain actionable so it can open folder setup"
        )

        exportButton.tap()
        XCTAssertTrue(
            app.buttons["Browse"].waitForExistence(timeout: 5),
            "Tapping Export Data without a local destination should open the folder picker"
        )
    }

    // MARK: - Export Target

    /// Exercises the real destination preflight and post-history admission before
    /// test-mode capture. A configured gateway must not depend on a local folder.
    func testConfiguredGateway_admitsExportWithoutLocalFolder() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: false,
            purchaseUnlocked: true
        )
        app.launch()

        let gateway = app.buttons["export.target.agentDataGateway"]
        scrollDatePresetIntoView(gateway, in: app)
        XCTAssertTrue(gateway.waitForExistence(timeout: 5))
        XCTAssertTrue(gateway.isHittable)
        gateway.tap()

        let endpoint = app.textFields["Agent Data gateway endpoint URL"]
        XCTAssertTrue(endpoint.waitForExistence(timeout: 5))
        endpoint.tap()
        endpoint.typeText("http://127.0.0.1:8791")
        XCTAssertTrue(app.staticTexts["Ready to export to the gateway"].waitForExistence(timeout: 5))
        app.navigationBars["Agent Data Gateway"].buttons["Done"].tap()
        XCTAssertTrue(gateway.waitForExistence(timeout: 5))
        XCTAssertTrue(gateway.isSelected)

        let json = app.switches["JSON"]
        scrollDatePresetIntoView(json, in: app)
        XCTAssertTrue(json.exists && json.isHittable)
        let jsonValue = json.value as? String
        if jsonValue != "1" && jsonValue != "Enabled" { json.tap() }
        let selectedJSON = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value == '1' OR value == 'Enabled'"), object: json
        )
        XCTAssertEqual(XCTWaiter.wait(for: [selectedJSON], timeout: 5), .completed)

        let export = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(export.isHittable)
        export.tap()
        let status = app.descendants(matching: .any)[UITestLaunchHelper.Status.exportStatusBadge]
        XCTAssertTrue(status.waitForExistence(timeout: 10),
                      "Configured gateway must pass production admission before synthetic capture")
        XCTAssertFalse(app.staticTexts["Export setup changed. Review the destination and settings before exporting."].exists)
    }

    func testExportTargetSelector_visible() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Export Target"].waitForExistence(timeout: 5), "Export target section should be visible")
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Export.localTargetOption].waitForExistence(timeout: 3), "Local target row should be visible")
        XCTAssertTrue(app.buttons[UITestLaunchHelper.Export.macTargetOption].waitForExistence(timeout: 3), "Mac target row should be visible")
    }

    func testMacTarget_disabledWhenDisconnected() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            syncState: "disconnected"
        )
        app.launch()

        let macTarget = app.buttons[UITestLaunchHelper.Export.macTargetOption]
        XCTAssertTrue(macTarget.waitForExistence(timeout: 5), "Mac target row should be visible")
        XCTAssertFalse(macTarget.isEnabled, "Mac target should be disabled when no Mac is connected")
        XCTAssertTrue(
            accessibilityText(of: macTarget).contains("No Mac connected")
                || accessibilityText(of: macTarget).contains("Open Health.md"),
            "Mac row should explain disconnected state"
        )
    }

    func testMacTarget_disabledWhenConnectedButNoFolderSelected() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            syncState: "connected",
            macExportStatus: "noFolder"
        )
        app.launch()

        let macTarget = app.buttons[UITestLaunchHelper.Export.macTargetOption]
        XCTAssertTrue(macTarget.waitForExistence(timeout: 5), "Mac target row should be visible")
        XCTAssertFalse(macTarget.isEnabled, "Mac target should be disabled until the Mac has a destination folder")
        XCTAssertTrue(
            accessibilityText(of: macTarget).contains("No folder selected")
                || accessibilityText(of: macTarget).contains("Choose a folder on Mac"),
            "Mac row should explain that the Mac needs a folder"
        )
    }

    func testMacTarget_enabledWhenReady() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            syncState: "connected",
            macExportStatus: "ready"
        )
        app.launch()

        let macTarget = app.buttons[UITestLaunchHelper.Export.macTargetOption]
        XCTAssertTrue(macTarget.waitForExistence(timeout: 5), "Mac target row should be visible")
        XCTAssertTrue(waitForEnabled(macTarget), "Mac target should be enabled when the connected Mac is ready")
    }

    func testPathPreview_changesForMacTarget() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: true,
            purchaseUnlocked: true,
            syncState: "connected",
            macExportStatus: "ready",
            macDestinationPath: "/tmp/ReadyMacVault"
        )
        app.launch()

        let pathPreview = app.descendants(matching: .any)[UITestLaunchHelper.Export.pathPreview]
        scrollUntilExists(pathPreview, in: app)
        XCTAssertTrue(pathPreview.exists, "Path preview should be present")
        let localPreview = waitForAccessibilityText(of: pathPreview, containing: "TestVault")
        XCTAssertTrue(localPreview.contains("TestVault"), "Local preview should mention the local test vault, got: \(localPreview)")

        let macTarget = app.buttons[UITestLaunchHelper.Export.macTargetOption]
        scrollUntilHittable(macTarget, in: app, swipingUp: false)
        XCTAssertTrue(waitForEnabled(macTarget), "Mac target should become enabled")
        macTarget.tap()

        scrollUntilExists(pathPreview, in: app)
        let macPreview = waitForAccessibilityText(of: pathPreview, containing: "Mac: /tmp/ReadyMacVault")
        XCTAssertTrue(macPreview.contains("Mac: /tmp/ReadyMacVault"), "Mac preview should mention the Mac destination, got: \(macPreview)")
        XCTAssertNotEqual(localPreview, macPreview, "Path preview should change after selecting the Mac target")
    }

    func testPreviewAvailable_withoutLocalFolderForMacTarget() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: false,
            purchaseUnlocked: true,
            syncState: "connected",
            macExportStatus: "ready"
        )
        app.launch()

        let macTarget = app.buttons[UITestLaunchHelper.Export.macTargetOption]
        XCTAssertTrue(macTarget.waitForExistence(timeout: 5), "Mac target row should be visible")
        XCTAssertTrue(waitForEnabled(macTarget), "Mac target should be enabled")
        macTarget.tap()

        let previewButton = app.buttons[UITestLaunchHelper.Export.previewButton]
        XCTAssertTrue(previewButton.waitForExistence(timeout: 5), "Preview button should be visible")
        XCTAssertTrue(previewButton.isEnabled, "Preview should remain available for Mac-only export without a local folder")
    }

    func testPaywallShown_forMacTargetWhenQuotaExhausted() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: false,
            freeExportsUsed: 10,
            syncState: "connected",
            macExportStatus: "ready"
        )
        app.launch()

        let macTarget = app.buttons[UITestLaunchHelper.Export.macTargetOption]
        XCTAssertTrue(macTarget.waitForExistence(timeout: 5), "Mac target row should be visible")
        XCTAssertTrue(waitForEnabled(macTarget), "Mac target should be enabled")
        macTarget.tap()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5), "Export button should be visible")
        XCTAssertTrue(exportButton.isEnabled, "Mac target should satisfy export readiness even without local folder")
        exportButton.tap()

        let paywallTitle = app.staticTexts[UITestLaunchHelper.Paywall.title]
        XCTAssertTrue(paywallTitle.waitForExistence(timeout: 5), "Paywall should appear before a Mac payload is prepared when quota is exhausted")
    }

    func testPaywallShown_forMacTargetWhenQuotaExhaustedWithAnalyticsOffline() throws {
        let app = UITestLaunchHelper.configuredApp(
            healthAuthorized: true,
            vaultSelected: false,
            freeExportsUsed: 10,
            syncState: "connected",
            macExportStatus: "ready",
            analyticsTransport: "offline",
            remoteConfig: "offline"
        )
        app.launch()

        let macTarget = app.buttons[UITestLaunchHelper.Export.macTargetOption]
        XCTAssertTrue(macTarget.waitForExistence(timeout: 5), "Mac target row should be visible")
        XCTAssertTrue(waitForEnabled(macTarget), "Mac target should be enabled")
        macTarget.tap()

        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5), "Export button should be visible")
        XCTAssertTrue(exportButton.isEnabled, "Mac target should satisfy export readiness even without local folder")
        exportButton.tap()

        let paywallTitle = app.staticTexts[UITestLaunchHelper.Paywall.title]
        XCTAssertTrue(paywallTitle.waitForExistence(timeout: 5), "Quota gate should beat Mac payload preparation with analytics offline")
    }

    // MARK: - Date Range Presets

    func testDateRangePresets_visibleAndCustomPickersHiddenByDefault() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        XCTAssertTrue(app.staticTexts["Date Range"].waitForExistence(timeout: 5), "Date Range section should be visible")
        let todayPreset = app.buttons[UITestLaunchHelper.Export.datePresetTodayButton]
        let yesterdayPreset = app.buttons[UITestLaunchHelper.Export.datePresetYesterdayButton]
        let allTimePreset = app.buttons[UITestLaunchHelper.Export.datePresetAllTimeButton]
        let customPreset = app.buttons[UITestLaunchHelper.Export.datePresetCustomButton]
        // The export-profile picker section sits above Date Range once profiles
        // are active, so presets render lazily below the fold; scroll to them.
        scrollUntilExists(todayPreset, in: app)
        XCTAssertTrue(todayPreset.exists, "Today preset should be reachable")
        scrollUntilExists(yesterdayPreset, in: app)
        XCTAssertTrue(yesterdayPreset.exists, "Yesterday preset should be reachable")
        scrollUntilExists(allTimePreset, in: app)
        XCTAssertTrue(allTimePreset.exists, "All Time preset should be reachable by scrolling")
        XCTAssertTrue(customPreset.exists, "Custom preset should be visible beside All Time")

        let startPicker = app.descendants(matching: .any)[UITestLaunchHelper.Export.customStartDatePicker]
        let endPicker = app.descendants(matching: .any)[UITestLaunchHelper.Export.customEndDatePicker]
        XCTAssertFalse(startPicker.exists, "Start Date picker should be hidden until Custom is selected")
        XCTAssertFalse(endPicker.exists, "End Date picker should be hidden until Custom is selected")
    }

    func testDateRangePresets_customRevealsStartAndEndPickers() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        let customPreset = app.buttons[UITestLaunchHelper.Export.datePresetCustomButton]
        scrollDatePresetIntoView(customPreset, in: app)
        XCTAssertTrue(customPreset.exists, "Custom preset should be visible")
        XCTAssertTrue(customPreset.isHittable, "Custom preset should be tappable")
        customPreset.tap()

        let startPicker = app.descendants(matching: .any)[UITestLaunchHelper.Export.customStartDatePicker]
        let endPicker = app.descendants(matching: .any)[UITestLaunchHelper.Export.customEndDatePicker]
        XCTAssertTrue(startPicker.waitForExistence(timeout: 3), "Start Date picker should appear after tapping Custom")
        XCTAssertTrue(endPicker.waitForExistence(timeout: 3), "End Date picker should appear after tapping Custom")
    }

    /// Covers the reachable inline selector, not a claimed reproduction of
    /// the reported native calendar completion flow (see investigation #168).
    func testDateRangePresets_selectedCustomRemainsEnabledAfterLeavingAndReopeningExport() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()
        let custom = app.buttons[UITestLaunchHelper.Export.datePresetCustomButton]
        scrollDatePresetIntoView(custom, in: app)
        XCTAssertTrue(custom.isEnabled)
        custom.tap()
        let start = app.descendants(matching: .any)[UITestLaunchHelper.Export.customStartDatePicker]
        let end = app.descendants(matching: .any)[UITestLaunchHelper.Export.customEndDatePicker]
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        XCTAssertTrue(end.waitForExistence(timeout: 3))
        XCTAssertEqual(custom.value as? String, "Selected")

        tabButton(in: app, identifier: UITestLaunchHelper.Tab.sync, label: "Sync").tap()
        tabButton(in: app, identifier: UITestLaunchHelper.Tab.export, label: "Export").tap()
        scrollDatePresetIntoView(custom, in: app)
        XCTAssertTrue(custom.isEnabled, "Selected Custom must not become a disabled preset on reentry")
        XCTAssertEqual(custom.value as? String, "Selected")
        custom.tap() // Deliberately do not select Today first.
        XCTAssertTrue(start.waitForExistence(timeout: 3))
        XCTAssertTrue(end.waitForExistence(timeout: 3))
        XCTAssertTrue(start.isEnabled)
        XCTAssertTrue(end.isEnabled)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Custom selector after export reentry"
        screenshot.lifetime = .keepAlways
        add(screenshot)
    }

    // MARK: - Tab Navigation

    func testTabNavigation_switchesBetweenTabs() throws {
        let app = UITestLaunchHelper.firstRunExportApp()
        app.launch()

        // Start on export tab
        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        XCTAssertTrue(exportButton.waitForExistence(timeout: 5))

        // Navigate to schedule tab
        let scheduleTab = tabButton(
            in: app,
            identifier: UITestLaunchHelper.Tab.schedule,
            label: "Schedule"
        )
        XCTAssertTrue(scheduleTab.exists, "Schedule tab should exist")
        scheduleTab.tap()

        // Schedule controls are inline on the tab — the toggle is the anchor
        let scheduleToggle = app.switches[UITestLaunchHelper.Schedule.enableToggle]
        XCTAssertTrue(scheduleToggle.waitForExistence(timeout: 3), "Schedule toggle should appear inline")

        // Navigate to sync tab
        let syncTab = tabButton(
            in: app,
            identifier: UITestLaunchHelper.Tab.sync,
            label: "Sync"
        )
        syncTab.tap()

        // Navigate back to export
        let exportTab = tabButton(
            in: app,
            identifier: UITestLaunchHelper.Tab.export,
            label: "Export"
        )
        exportTab.tap()
        XCTAssertTrue(exportButton.waitForExistence(timeout: 3))
    }

    // MARK: - Helpers

    private func tabButton(in app: XCUIApplication, identifier: String, label: String) -> XCUIElement {
        let identified = app.buttons[identifier]
        if identified.exists { return identified }
        return app.buttons[label]
    }

    private func accessibilityText(of element: XCUIElement) -> String {
        let value = element.value as? String ?? ""
        return [element.label, value].joined(separator: " ")
    }

    private func waitForEnabled(_ element: XCUIElement, timeout: TimeInterval = 5) -> Bool {
        let predicate = NSPredicate(format: "isEnabled == true")
        let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
        return XCTWaiter.wait(for: [expectation], timeout: timeout) == .completed
    }

    private func scrollUntilExists(_ element: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<6 where !element.exists {
            scrollView.swipeUp()
        }
    }

    private func scrollUntilHittable(_ element: XCUIElement, in app: XCUIApplication, swipingUp: Bool) {
        let scrollView = app.scrollViews.firstMatch
        for _ in 0..<6 where !element.isHittable {
            swipingUp ? scrollView.swipeUp() : scrollView.swipeDown()
        }
    }

    private func scrollDatePresetIntoView(_ preset: XCUIElement, in app: XCUIApplication) {
        let scrollView = app.scrollViews.firstMatch
        let tabBar = app.tabBars.firstMatch
        let exportButton = app.buttons[UITestLaunchHelper.Export.exportButton]
        // SwiftUI can report a row as hittable while its tap point is underneath
        // the floating export controls. Keep the entire row inside the clear
        // viewport, and scroll in either direction so a swipe cannot strand it
        // above the visible content.
        for _ in 0..<6 {
            let viewport = scrollView.frame.intersection(app.frame)
            var visibleBottom = viewport.maxY
            if tabBar.exists { visibleBottom = min(visibleBottom, tabBar.frame.minY) }
            if exportButton.exists { visibleBottom = min(visibleBottom, exportButton.frame.minY - 24) }
            let visibleTop = viewport.minY + 24
            if preset.exists && preset.isHittable
                && preset.frame.minY >= visibleTop && preset.frame.maxY <= visibleBottom {
                return
            }
            let above = preset.exists && preset.frame.midY < visibleTop
            // Start in the clear middle of the viewport, away from the floating
            // action bar, rather than dragging across the export button.
            scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.35 : 0.6)).press(
                forDuration: 0.05,
                thenDragTo: scrollView.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: above ? 0.6 : 0.35))
            )
        }
    }

    private func waitForAccessibilityText(
        of element: XCUIElement,
        containing expectedText: String,
        timeout: TimeInterval = 5
    ) -> String {
        let deadline = Date().addingTimeInterval(timeout)
        var text = accessibilityText(of: element)
        while Date() < deadline {
            text = accessibilityText(of: element)
            if text.contains(expectedText) { return text }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return text
    }
}
