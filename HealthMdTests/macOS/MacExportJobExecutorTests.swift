import XCTest
@testable import HealthMd

#if os(macOS)

private final class FailingFileSystem: FileSystemAccessing, @unchecked Sendable {
    var files: [String: String] = [:]
    var directories: Set<String> = []
    let writeError = NSError(
        domain: "FailingFileSystem",
        code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Simulated write failure"]
    )

    func fileExists(atPath path: String) -> Bool {
        files[path] != nil || directories.contains(path)
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        directories.insert(url.path)
    }

    func contentsOfFile(at url: URL) throws -> String {
        files[url.path] ?? ""
    }

    func writeString(_ string: String, to url: URL, atomically: Bool) throws {
        throw writeError
    }
}

@MainActor
final class MacExportJobExecutorTests: XCTestCase {

    private var defaults: FakeUserDefaults!
    private var fileSystem: FakeFileSystem!
    private var bookmarkResolver: FakeBookmarkResolver!

    override func setUp() {
        super.setUp()
        defaults = FakeUserDefaults()
        fileSystem = FakeFileSystem()
        bookmarkResolver = FakeBookmarkResolver()
        bookmarkResolver.accessGranted = true
    }

    func testExecute_success_writesReceivedRecordsUsingSnapshot() async throws {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let job = makeJob(records: [Self.healthData(on: date)], start: date, end: date)
        var progressEvents: [MacExportProgress] = []

        let result = await executor.execute(job, vaultManager: manager) { progress in
            progressEvents.append(progress)
        }

        guard case .success(let payload) = result else {
            return XCTFail("Expected successful payload")
        }
        XCTAssertEqual(payload.status, .success)
        XCTAssertEqual(payload.successCount, 1)
        XCTAssertEqual(payload.totalCount, 1)
        XCTAssertEqual(payload.formatsPerDate, 1)
        XCTAssertEqual(payload.totalFilesWritten, 1)
        XCTAssertEqual(fileSystem.files.count, 1)
        XCTAssertTrue(fileSystem.files.keys.first?.contains("/tmp/MacVault/Health") == true)
        XCTAssertTrue(progressEvents.contains { $0.phase == .receiving })
        XCTAssertTrue(progressEvents.contains { $0.phase == .writing })
        XCTAssertEqual(progressEvents.last?.phase, .completed)
    }

    func testExecute_markdownOutputMatchesLocalExporterForSameSnapshot() async throws {
        let settings = makeSettings(formats: [.markdown]) { settings in
            settings.filenameFormat = "health-{date}"
            settings.folderStructure = "{year}/{month}"
            settings.includeMetadata = true
            settings.groupByCategory = true
            settings.includeGranularData = true
            settings.formatCustomization.markdownTemplate.useEmoji = false
            settings.formatCustomization.frontmatterConfig.customFields = ["source": "ios"]
        }

        try await assertMacExportMatchesLocalExporter(
            records: [ExportFixtures.fullDayGranular],
            settings: settings
        )
    }

    func testExecute_multiFormatOutputMatchesLocalExporterForSameSnapshot() async throws {
        let settings = makeSettings(formats: [.markdown, .csv]) { settings in
            settings.filenameFormat = "daily-{date}"
            settings.folderStructure = "{year}"
            settings.includeMetadata = true
            settings.groupByCategory = true
            settings.includeGranularData = true
            settings.formatCustomization.unitPreference = .imperial
        }

        try await assertMacExportMatchesLocalExporter(
            records: [ExportFixtures.fullDayGranular],
            settings: settings
        )
    }

    func testExecute_noDestinationFolder_returnsStructuredFailure() async {
        let manager = makeManager()
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let job = makeJob(records: [Self.healthData(on: date)], start: date, end: date)

        let result = await executor.execute(job, vaultManager: manager)

        guard case .failure(let failure) = result else {
            return XCTFail("Expected no-folder failure")
        }
        XCTAssertEqual(failure.reason, .noMacFolderSelected)
        XCTAssertEqual(failure.jobID, job.jobID)
    }

    func testExecute_noFormatsSelected_returnsStructuredFailure() async {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let job = makeJob(
            records: [Self.healthData(on: date)],
            start: date,
            end: date,
            snapshot: makeSnapshot(formats: [])
        )

        let result = await executor.execute(job, vaultManager: manager)

        guard case .failure(let failure) = result else {
            return XCTFail("Expected no-formats failure")
        }
        XCTAssertEqual(failure.reason, .noFormatsSelected)
    }

    func testExecute_noRecordsReceived_returnsStructuredFailure() async {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let job = makeJob(records: [], start: date, end: date)

        let result = await executor.execute(job, vaultManager: manager)

        guard case .failure(let failure) = result else {
            return XCTFail("Expected no-records failure")
        }
        XCTAssertEqual(failure.reason, .noHealthRecordsReceived)
        XCTAssertEqual(failure.jobID, job.jobID)
    }

    func testExecute_missingDate_returnsPartialSuccess() async throws {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let start = Self.day(2026, 5, 12)
        let end = Self.day(2026, 5, 13)
        let job = makeJob(records: [Self.healthData(on: start)], start: start, end: end)

        let result = await executor.execute(job, vaultManager: manager)

        guard case .success(let payload) = result else {
            return XCTFail("Expected result payload")
        }
        XCTAssertEqual(payload.status, .partialSuccess)
        XCTAssertEqual(payload.successCount, 1)
        XCTAssertEqual(payload.totalCount, 2)
        XCTAssertEqual(payload.failedDateDetails.count, 1)
        XCTAssertEqual(payload.failedDateDetails.first?.reason, .noHealthData)
        XCTAssertEqual(fileSystem.files.count, 1)
    }

    func testExecute_folderAccessDenied_returnsStructuredPreflightFailure() async {
        let manager = makeManagerWithVault()
        bookmarkResolver.accessGranted = false
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let job = makeJob(records: [Self.healthData(on: date)], start: date, end: date)

        let result = await executor.execute(job, vaultManager: manager)

        guard case .failure(let failure) = result else {
            return XCTFail("Expected folder-access failure")
        }
        XCTAssertEqual(failure.reason, .macFolderAccessDenied)
        XCTAssertEqual(failure.jobID, job.jobID)
        XCTAssertTrue(failure.message.contains("Re-select"))
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    func testExecute_fileWriteFailure_returnsFailureResultWithFailedDate() async {
        let failingFileSystem = FailingFileSystem()
        let manager = makeManagerWithVault(
            defaults: FakeUserDefaults(),
            fileSystem: failingFileSystem,
            bookmarkResolver: makeAccessGrantedBookmarkResolver()
        )
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let job = makeJob(records: [Self.healthData(on: date)], start: date, end: date)

        let result = await executor.execute(job, vaultManager: manager)

        guard case .success(let payload) = result else {
            return XCTFail("Expected final result payload")
        }
        XCTAssertEqual(payload.status, .failure)
        XCTAssertEqual(payload.failedDateDetails.first?.reason, .fileWriteError)
        XCTAssertTrue(failingFileSystem.files.isEmpty)
    }

    func testExecute_cancelledBeforeValidation_returnsCancelledResult() async {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let job = makeJob(records: [Self.healthData(on: date)], start: date, end: date)

        executor.cancel(jobID: job.jobID)
        let result = await executor.execute(job, vaultManager: manager)

        guard case .success(let payload) = result else {
            return XCTFail("Expected cancelled result payload")
        }
        XCTAssertEqual(payload.status, .cancelled)
        XCTAssertEqual(payload.successCount, 0)
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    private func makeManager(
        defaults: FakeUserDefaults? = nil,
        fileSystem: FileSystemAccessing? = nil,
        bookmarkResolver: FakeBookmarkResolver? = nil
    ) -> VaultManager {
        let manager = VaultManager(
            defaults: defaults ?? self.defaults,
            fileSystem: fileSystem ?? self.fileSystem,
            bookmarkResolver: bookmarkResolver ?? self.bookmarkResolver
        )
        return LifecycleHarness.retain(manager)
    }

    private func makeManagerWithVault(
        defaults: FakeUserDefaults? = nil,
        fileSystem: FileSystemAccessing? = nil,
        bookmarkResolver: FakeBookmarkResolver? = nil,
        vaultPath: String = "/tmp/MacVault"
    ) -> VaultManager {
        let manager = makeManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver
        )
        manager.setVaultFolder(URL(fileURLWithPath: vaultPath))
        return manager
    }

    private func makeJob(
        records: [HealthData],
        start: Date,
        end: Date,
        snapshot: ExportSettingsSnapshot? = nil
    ) -> MacExportJob {
        MacExportJob(
            jobID: UUID(),
            createdAt: Date(),
            sourceDeviceName: "Test iPhone",
            dateRangeStart: start,
            dateRangeEnd: end,
            records: records,
            settingsSnapshot: snapshot ?? makeSnapshot(),
            requestedTarget: ExportTargetSnapshot(
                kind: .connectedMac,
                displayName: "Connected Mac",
                destinationDisplayName: "MacVault"
            )
        )
    }

    private func makeSnapshot(formats: Set<ExportFormat> = [.markdown]) -> ExportSettingsSnapshot {
        .from(makeSettings(formats: formats))
    }

    private func makeSettings(
        formats: Set<ExportFormat> = [.markdown],
        configure: ((AdvancedExportSettings) -> Void)? = nil
    ) -> AdvancedExportSettings {
        let suiteName = "MacExportJobExecutorTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = formats
        settings.filenameFormat = "{date}"
        settings.folderStructure = ""
        settings.writeMode = .overwrite
        settings.includeGranularData = true
        configure?(settings)
        return LifecycleHarness.retain(settings)
    }

    private func assertMacExportMatchesLocalExporter(
        records: [HealthData],
        settings: AdvancedExportSettings,
        file: StaticString = #filePath,
        line: UInt = #line
    ) async throws {
        let vaultPath = "/tmp/ParityVault"
        let localFileSystem = FakeFileSystem()
        let macFileSystem = FakeFileSystem()
        let localResolver = makeAccessGrantedBookmarkResolver()
        let macResolver = makeAccessGrantedBookmarkResolver()

        let localManager = makeManagerWithVault(
            defaults: FakeUserDefaults(),
            fileSystem: localFileSystem,
            bookmarkResolver: localResolver,
            vaultPath: vaultPath
        )
        let macManager = makeManagerWithVault(
            defaults: FakeUserDefaults(),
            fileSystem: macFileSystem,
            bookmarkResolver: macResolver,
            vaultPath: vaultPath
        )
        localManager.healthSubfolder = "Health"
        macManager.healthSubfolder = "Health"

        for record in records {
            try await localManager.exportHealthData(record, settings: settings)
        }

        let sortedDates = records.map(\.date).sorted()
        let job = makeJob(
            records: records,
            start: sortedDates.first ?? Date(),
            end: sortedDates.last ?? Date(),
            snapshot: .from(settings)
        )

        let result = await MacExportJobExecutor().execute(job, vaultManager: macManager)
        guard case .success(let payload) = result else {
            return XCTFail("Expected successful Mac export result", file: file, line: line)
        }
        XCTAssertEqual(payload.status, .success, file: file, line: line)

        XCTAssertEqual(
            Set(macFileSystem.files.keys),
            Set(localFileSystem.files.keys),
            "Mac agent should write the same files as local export",
            file: file,
            line: line
        )

        for path in localFileSystem.files.keys.sorted() {
            guard let localContent = localFileSystem.files[path],
                  let macContent = macFileSystem.files[path] else {
                return XCTFail("Missing parity file at \(path)", file: file, line: line)
            }
            assertGoldenMatch(
                normalizeExportOutput(macContent),
                expected: normalizeExportOutput(localContent),
                file: file,
                line: line
            )
        }
    }

    private func makeAccessGrantedBookmarkResolver() -> FakeBookmarkResolver {
        let resolver = FakeBookmarkResolver()
        resolver.accessGranted = true
        return resolver
    }

    private static func healthData(on date: Date) -> HealthData {
        var data = HealthData(date: date)
        data.activity.steps = 4_321
        return data
    }

    private static func day(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.hour = 12
        return Calendar.current.date(from: components)!
    }
}

#endif
