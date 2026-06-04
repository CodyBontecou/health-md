import XCTest
@testable import HealthMd
import ExportKit

@MainActor
final class HealthExportPreviewBuilderTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: VaultManager and AdvancedExportSettings are
    // ObservableObjects with nested observable properties. Static retention avoids
    // macOS 26 / Swift 6 deinit crashes. See docs/testing/lifecycle-audit.md.
    private static var retainedManagers: [VaultManager] = []
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testHealthPreviewPlansAggregateDailyNoteIndividualEntriesAndWarnings() async throws {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        settings.exportFormats = [.markdown, .json]
        settings.folderStructure = ""
        settings.filenameFormat = "{date}"
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.createIfMissing = true
        settings.dailyNoteInjection.folderPath = ""
        settings.dailyNoteInjection.filenamePattern = "{date}"
        settings.individualTracking.globalEnabled = true
        settings.individualTracking.setTrackIndividually("weight", enabled: true)

        let vaultManager = makeVaultManager(healthSubfolder: "")
        let date = ExportFixtures.referenceDate

        let preview = try await HealthExportPreviewBuilder.buildPreview(
            dates: [date],
            vaultManager: vaultManager,
            settings: settings,
            destinationRootName: "PreviewVault",
            targetType: .connectedMac,
            fetchHealthData: { requestedDate in
                XCTAssertEqual(requestedDate, date)
                return ExportFixtures.fullDay
            }
        )

        let expectedJSONFilename = settings.filename(for: date, format: .json)
        let expectedMarkdownFilename = settings.filename(for: date, format: .markdown)
        let expectedDailyNoteFilename = settings.dailyNoteInjection.formatFilename(for: date) + ".md"
        let record = try XCTUnwrap(preview.records.first)
        XCTAssertEqual(preview.totalRecordCount, 1)
        XCTAssertEqual(preview.renderedRecordCount, 1)
        XCTAssertEqual(record.files.prefix(2).map(\.filename), [expectedJSONFilename, expectedMarkdownFilename])
        XCTAssertEqual(record.files.prefix(2).map(\.role), [
            .aggregate(formatID: ExportFormat.json.exportKitFormatID),
            .aggregate(formatID: ExportFormat.markdown.exportKitFormatID)
        ])
        XCTAssertTrue(record.files.contains { file in
            file.role == .mutation(pluginID: HealthExportPreviewBuilder.dailyNoteInjectionPluginID)
                && file.filename == expectedDailyNoteFilename
                && file.content.contains("steps:")
        })
        XCTAssertTrue(record.files.contains { file in
            file.role == .supplemental(pluginID: HealthExportPreviewBuilder.individualEntryPluginID)
                && file.relativePath.contains("entries/body_measurements")
                && file.content.contains("metric: weight")
        })
        XCTAssertTrue(preview.warnings.contains { warning in
            warning.message.contains("Daily Note Injection target conflicts")
        })
    }

    func testHealthPreviewSkipsEmptyHealthDataButKeepsTotalAndFetchAttemptCounts() async throws {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        settings.exportFormats = [.markdown]

        let vaultManager = makeVaultManager(healthSubfolder: "Health")
        let date = ExportFixtures.referenceDate

        let preview = try await HealthExportPreviewBuilder.buildPreview(
            dates: [date],
            vaultManager: vaultManager,
            settings: settings,
            destinationRootName: nil,
            targetType: .connectedMac,
            fetchHealthData: { requestedDate in
                HealthData(date: requestedDate)
            }
        )

        XCTAssertTrue(preview.records.isEmpty)
        XCTAssertEqual(preview.totalRecordCount, 1)
        XCTAssertEqual(preview.fetchAttemptCount, 1)
    }

    func testHealthPreviewUsesGenericTruncationForRenderedAggregateFiles() async throws {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        settings.exportFormats = [.json]

        let vaultManager = makeVaultManager(healthSubfolder: "Health")
        let preview = try await HealthExportPreviewBuilder.buildPreview(
            dates: [ExportFixtures.referenceDate],
            vaultManager: vaultManager,
            settings: settings,
            destinationRootName: nil,
            targetType: .connectedMac,
            fetchHealthData: { _ in ExportFixtures.fullDayGranular }
        )

        let file = try XCTUnwrap(preview.records.first?.files.first)
        let display = file.displayContent(maximumRenderedBytes: 128, headBytes: 64, tailBytes: 32)

        XCTAssertEqual(file.role, .aggregate(formatID: ExportFormat.json.exportKitFormatID))
        XCTAssertTrue(display.isTruncated)
        XCTAssertTrue(display.text.contains("Preview truncated"))
    }

    private func makeVaultManager(healthSubfolder: String) -> VaultManager {
        let manager = VaultManager(defaults: FakeUserDefaults(), fileSystem: FakeFileSystem(), bookmarkResolver: FakeBookmarkResolver())
        manager.vaultName = "TestVault"
        manager.healthSubfolder = healthSubfolder
        Self.retainedManagers.append(manager)
        return manager
    }

    private func makeSettings() -> (AdvancedExportSettings, UserDefaults, String) {
        let suiteName = "healthmd.tests.health-preview-builder.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        return (settings, defaults, suiteName)
    }
}
