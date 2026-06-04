import XCTest
@testable import HealthMd
import ExportKit

@MainActor
final class HealthExportPluginTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings owns nested
    // ObservableObject settings; retaining avoids macOS 26 / Swift 6 deinit
    // instability documented in docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testDailyNotePluginValidationRejectsAggregateCollision() throws {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        settings.exportFormats = [.markdown]
        settings.folderStructure = "Daily"
        settings.filenameFormat = "{date}"
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.createIfMissing = false
        settings.dailyNoteInjection.folderPath = "Daily"
        settings.dailyNoteInjection.filenamePattern = "{date}"

        let record = HealthExportRecord(healthData: ExportFixtures.fullDay)
        let aggregateFiles = HealthExportPluginAdapter.aggregateFiles(
            healthSubfolder: "",
            settings: settings,
            date: ExportFixtures.referenceDate
        )
        let runner = ExportPluginRunner(plugins: HealthExportPluginAdapter.makePlugins(
            settings: settings,
            healthSubfolder: ""
        ))
        let context = ExportPluginContext(
            record: record,
            operation: .validation,
            destination: ExportDestination(rootURL: URL(fileURLWithPath: "/tmp/TestVault")),
            aggregateFiles: aggregateFiles,
            writeMode: .overwrite
        )

        let expectedPath = settings.dailyNoteInjection.previewPath(for: ExportFixtures.referenceDate)
        XCTAssertThrowsError(try runner.validate(record: record, context: context)) { error in
            XCTAssertEqual(error as? HealthExportPluginError, .dailyNotePathConflict(path: expectedPath))
        }
    }

    func testIndividualEntryPluginWritesOnceForMultiFormatAggregateExport() throws {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        settings.exportFormats = [.markdown, .json]
        settings.individualTracking.globalEnabled = true
        settings.individualTracking.setTrackIndividually("weight", enabled: true)

        let fakeFileSystem = FakeFileSystem()
        let fileWriter = ExportFileWriter(fileSystem: FileSystemAccessingExportAdapter(fakeFileSystem))
        let record = HealthExportRecord(healthData: ExportFixtures.fullDay)
        let aggregateFiles = HealthExportPluginAdapter.aggregateFiles(
            healthSubfolder: "Health",
            settings: settings,
            date: ExportFixtures.referenceDate
        )
        let runner = ExportPluginRunner(plugins: HealthExportPluginAdapter.makePlugins(
            settings: settings,
            healthSubfolder: "Health",
            fileWriter: fileWriter
        ))
        let context = ExportPluginContext(
            record: record,
            operation: .write,
            destination: ExportDestination(rootURL: URL(fileURLWithPath: "/tmp/TestVault")),
            aggregateFiles: aggregateFiles,
            writeMode: .overwrite
        )

        let results = try runner.performSideEffects(record: record, context: context)
        let summary = HealthExportPluginSideEffectSummary.make(from: results)

        XCTAssertEqual(summary.individualEntriesCount, 1)
        let entryPaths = fakeFileSystem.files.keys.filter { $0.contains("/entries/body_measurements/") }
        XCTAssertEqual(entryPaths.count, 1)
        XCTAssertTrue(entryPaths.first?.contains("weight") == true)
        XCTAssertTrue(fakeFileSystem.files[entryPaths[0]]?.contains("metric: weight") == true)
    }

    func testDailyNotePluginPreviewUsesExistingContentAndReportsCollisions() throws {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        settings.exportFormats = [.markdown]
        settings.folderStructure = "Daily"
        settings.filenameFormat = "{date}"
        settings.dailyNoteInjection.enabled = true
        settings.dailyNoteInjection.folderPath = "Daily"
        settings.dailyNoteInjection.filenamePattern = "{date}"

        let record = HealthExportRecord(healthData: ExportFixtures.fullDay)
        let aggregateFiles = HealthExportPluginAdapter.aggregateFiles(
            healthSubfolder: "",
            settings: settings,
            date: ExportFixtures.referenceDate
        )
        let plugin = HealthDailyNoteInjectionPlugin(
            settings: settings.dailyNoteInjection,
            customization: settings.formatCustomization,
            metricSelection: settings.metricSelection,
            previewBaseResolver: { _ in .resolved(.existingContent("---\ntitle: My Day\n---\n\n# Journal\n")) }
        )
        let context = ExportPluginContext(
            record: record,
            operation: .preview,
            aggregateFiles: aggregateFiles,
            writeMode: .overwrite
        )

        let plan = try plugin.planFiles(record: record, context: context)

        XCTAssertEqual(plan.files.first?.role, .mutation(pluginID: HealthExportPluginIDs.dailyNoteInjection))
        XCTAssertTrue(plan.files.first?.content.contains("title: My Day") == true)
        XCTAssertTrue(plan.files.first?.content.contains("# Journal") == true)
        XCTAssertTrue(plan.files.first?.content.contains("steps:") == true)
        XCTAssertTrue(plan.warnings.contains { $0.message.contains("Daily Note Injection target conflicts") })
    }

    private func makeSettings() -> (AdvancedExportSettings, UserDefaults, String) {
        let suiteName = "healthmd.tests.health-export-plugins.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        return (settings, defaults, suiteName)
    }
}
