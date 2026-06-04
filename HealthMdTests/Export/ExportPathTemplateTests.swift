import XCTest
@testable import HealthMd
import ExportKit

final class ExportPathTemplateTests: XCTestCase {
    private static let testDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 27
        components.hour = 12
        components.minute = 0
        return Calendar.current.date(from: components)!
    }()

    func testExpandsDateAndAppSpecificVariables() throws {
        let template = ExportPathTemplate(
            folderTemplate: "Reports/{year}/{month}/{monthName}/{project}",
            filenameTemplate: "{recordID}-{format}-{date}-{weekday}-{quarter}",
            fileExtension: ".md"
        )
        let variables = ExportPathVariables(
            date: Self.testDate,
            values: [
                "project": "Acme",
                "recordID": "record-7",
                "format": "markdown"
            ]
        )

        let plan = try template.plan(variables: variables)

        XCTAssertEqual(
            plan.relativePath,
            "Reports/2026/03/\(Self.formatted(Self.testDate, as: "MMMM"))/Acme/record-7-markdown-2026-03-27-\(Self.formatted(Self.testDate, as: "EEEE"))-Q1.md"
        )
    }

    func testUnknownPlaceholdersRemainUnchanged() {
        let variables = ExportPathVariables(date: Self.testDate, values: ["project": "Acme"])

        XCTAssertEqual(
            variables.applying(to: "{project}-{missing}-{date}"),
            "Acme-{missing}-2026-03-27"
        )
    }

    func testPreserveCurrentBehaviorTrimsSplitsSlashesAndDropsEmptySegments() throws {
        let template = ExportPathTemplate(
            folderTemplate: "  {year}//{month}/ ",
            filenameTemplate: " nested//{date}",
            fileExtension: "md"
        )

        let plan = try template.plan(
            variables: ExportPathVariables(date: Self.testDate),
            safetyPolicy: .preserveCurrentBehavior
        )

        XCTAssertEqual(plan.components, ["2026", "03", "nested", "2026-03-27.md"])
        XCTAssertEqual(plan.relativePath, "2026/03/nested/2026-03-27.md")
    }

    func testEmptyFolderPlansRootRelativeFile() throws {
        let template = ExportPathTemplate(
            folderTemplate: "",
            filenameTemplate: "{date}",
            fileExtension: "json"
        )

        let plan = try template.plan(variables: ExportPathVariables(date: Self.testDate))

        XCTAssertEqual(plan.folderPath, "")
        XCTAssertEqual(plan.filename, "2026-03-27.json")
        XCTAssertEqual(plan.relativePath, "2026-03-27.json")
    }

    func testRejectTraversalAndAbsolutePathsPolicy() {
        let variables = ExportPathVariables(date: Self.testDate)
        let traversal = ExportPathTemplate(
            folderTemplate: "../Secrets",
            filenameTemplate: "{date}",
            fileExtension: "md"
        )
        let absolute = ExportPathTemplate(
            folderTemplate: "Reports",
            filenameTemplate: "/tmp/{date}",
            fileExtension: "md"
        )

        XCTAssertThrowsError(try traversal.plannedRelativePath(variables: variables)) { error in
            XCTAssertEqual(error as? ExportPathTemplateError, .pathTraversalNotAllowed("../Secrets"))
        }
        XCTAssertThrowsError(try absolute.plannedRelativePath(variables: variables)) { error in
            XCTAssertEqual(error as? ExportPathTemplateError, .absolutePathNotAllowed("/tmp/2026-03-27.md"))
        }
    }

    func testSanitizePolicyKeepsPathDestinationRelativeWithoutThrowing() throws {
        let template = ExportPathTemplate(
            folderTemplate: "/Reports/../Client:One",
            filenameTemplate: "{date}?summary",
            fileExtension: "md"
        )

        let plan = try template.plan(
            variables: ExportPathVariables(date: Self.testDate),
            safetyPolicy: .sanitizePathComponents
        )

        XCTAssertEqual(plan.relativePath, "Reports/Client_One/2026-03-27_summary.md")
    }

    private static func formatted(_ date: Date, as dateFormat: String) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = dateFormat
        return formatter.string(from: date)
    }
}

@MainActor
final class HealthExportPathAdapterTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: VaultManager and AdvancedExportSettings are
    // ObservableObjects with nested observable properties. Static retention avoids
    // macOS 26 / Swift 6 deinit crashes. See docs/testing/lifecycle-audit.md.
    private static var retainedManagers: [VaultManager] = []
    private static var retainedSettings: [AdvancedExportSettings] = []

    private static let testDate: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 3
        components.day = 27
        components.hour = 12
        components.minute = 0
        return Calendar.current.date(from: components)!
    }()

    func testAggregateRelativePathsPreserveNestedFoldersEmptySubfolderAndCollisionSuffixes() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        settings.exportFormats = [.markdown, .obsidianBases]
        settings.folderStructure = "{year}//{month}"
        settings.filenameFormat = "daily/{date}"

        XCTAssertEqual(
            ExportPathPlanner.aggregateRelativePath(
                healthSubfolder: "",
                settings: settings,
                date: Self.testDate,
                format: .markdown
            ),
            "2026/03/daily/2026-03-27.md"
        )
        XCTAssertEqual(
            ExportPathPlanner.aggregateRelativePath(
                healthSubfolder: "",
                settings: settings,
                date: Self.testDate,
                format: .obsidianBases
            ),
            "2026/03/daily/2026-03-27-bases.md"
        )
    }

    func testDailyNoteInjectionPathStaysVaultRootRelative() throws {
        let settings = DailyNoteInjectionSettings()
        settings.folderPath = "Daily//Journal"
        settings.filenamePattern = "note-{date}"
        LifecycleHarness.retain(settings)

        XCTAssertEqual(
            try ExportPathPlanner.safeDailyNoteRelativePath(settings: settings, date: Self.testDate),
            "Daily/Journal/note-2026-03-27.md"
        )
    }

    func testHealthPathValidationRejectsAggregateAndDailyNoteTraversal() {
        let (settings, defaults, suiteName) = makeSettings()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        settings.folderStructure = "../Outside"

        XCTAssertThrowsError(
            try ExportPathPlanner.validateAggregatePaths(
                healthSubfolder: "Health",
                settings: settings,
                date: Self.testDate
            )
        ) { error in
            XCTAssertEqual(error as? ExportPathTemplateError, .pathTraversalNotAllowed("../Outside"))
        }

        settings.folderStructure = ""
        settings.filenameFormat = "../{date}"
        XCTAssertThrowsError(
            try ExportPathPlanner.validateAggregatePaths(
                healthSubfolder: "Health",
                settings: settings,
                date: Self.testDate
            )
        ) { error in
            XCTAssertEqual(error as? ExportPathTemplateError, .pathTraversalNotAllowed("../2026-03-27.md"))
        }

        settings.dailyNoteInjection.folderPath = "../Daily"
        XCTAssertThrowsError(
            try ExportPathPlanner.validateDailyNotePath(
                settings: settings.dailyNoteInjection,
                date: Self.testDate
            )
        ) { error in
            XCTAssertEqual(error as? ExportPathTemplateError, .pathTraversalNotAllowed("../Daily"))
        }
    }

    func testBackgroundExportRejectsTraversalWithoutWritingOutsideDestination() {
        let defaults = FakeUserDefaults()
        let fileSystem = FakeFileSystem()
        let bookmarkResolver = FakeBookmarkResolver()
        let vaultURL = URL(fileURLWithPath: "/tmp/HealthMdSafeVault", isDirectory: true)
        defaults.storage["obsidianVaultBookmark"] = Data("bm".utf8)
        bookmarkResolver.resolvedURL = vaultURL

        let manager = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver
        )
        Self.retainedManagers.append(manager)
        manager.healthSubfolder = "Health"

        let (settings, settingsDefaults, suiteName) = makeSettings()
        defer { settingsDefaults.removePersistentDomain(forName: suiteName) }
        settings.folderStructure = "../Outside"

        let result = manager.exportHealthData(
            ExportFixtures.fullDay,
            for: ExportFixtures.referenceDate,
            settings: settings
        )

        XCTAssertFalse(result)
        XCTAssertTrue(fileSystem.files.isEmpty)
        XCTAssertTrue(manager.lastExportStatus?.contains("traversal") == true)
    }

    private func makeSettings() -> (AdvancedExportSettings, UserDefaults, String) {
        let suiteName = "healthmd.tests.export-path-adapter.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suiteName) else {
            fatalError("Failed to create isolated UserDefaults suite")
        }
        defaults.removePersistentDomain(forName: suiteName)

        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        return (settings, defaults, suiteName)
    }
}
