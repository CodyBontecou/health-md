import HealthMdCoreRust
import XCTest
@testable import HealthMd

#if os(macOS)

nonisolated private final class FailingFileSystem: FileSystemAccessing, @unchecked Sendable {
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

    func contentsOfDirectory(at url: URL) throws -> [URL] {
        []
    }

    func removeItem(at url: URL) throws { }
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

    func testExecute_connectedLegacyUsesExactSnapshotAndLegacySurface() async throws {
        let planner = ConnectedMacPlannerProbe()
        let manager = makeManagerWithVault(planner: planner)
        let date = Self.day(2026, 5, 12)
        let record = Self.healthData(on: date)
        let settings = makeConnectedSimpleSettings()
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            calendarTimeZoneIdentifier: record.timeContext.calendarTimeZoneIdentifier
        )
        let job = makeJob(
            records: [record],
            start: date,
            end: date,
            snapshot: snapshot
        )

        guard case .success(let payload) = await MacExportJobExecutor().execute(
            job,
            vaultManager: manager
        ) else {
            return XCTFail("Expected connected legacy export to succeed")
        }

        XCTAssertEqual(payload.status, .success)
        XCTAssertEqual(planner.calls.count, 1)
        XCTAssertEqual(planner.calls.first?.surface, .legacyOnly)
        XCTAssertEqual(planner.calls.first?.settingsSnapshot, snapshot)
        XCTAssertNotNil(fileSystem.files["/tmp/MacVault/Health/2026-05-12.json"])
    }

    func testResolveRejectsPresentLegacyPinInsteadOfEnteringNativeWriterPath() throws {
        let record = Self.healthData(on: Self.day(2026, 5, 12))
        let service = HealthMdCoreService()
        let buildInfo = try service.buildInfo()
        let registry = try HealthMdCoreRegistryAdapter.appleSnapshot(service: service)
        let pin = try AppleExportEnginePin(
            engine: .legacy,
            calendarTimeZoneIdentifier: record.timeContext.calendarTimeZoneIdentifier,
            buildInfo: buildInfo,
            registrySnapshot: registry
        )
        let snapshot = ExportSettingsSnapshot.from(
            makeConnectedSimpleSettings(),
            healthSubfolder: "Health",
            appleExportEnginePin: pin,
            calendarTimeZoneIdentifier: record.timeContext.calendarTimeZoneIdentifier
        )

        XCTAssertThrowsError(
            try ConnectedMacDailyExportOperation.resolve(
                settingsSnapshot: snapshot,
                declaredPin: pin,
                records: [record]
            )
        ) { error in
            XCTAssertEqual(
                error as? ConnectedMacDailyExportOperation.ResolutionError,
                .mismatchedPin
            )
        }
    }

    func testExecute_connectedShadowCommitsNativePlanOnly() async throws {
        let planner = ConnectedMacPlannerProbe()
        let manager = makeManagerWithVault(planner: planner)
        let date = Self.day(2026, 5, 12)
        let record = Self.healthData(on: date)
        let settings = makeConnectedSimpleSettings()
        let snapshot = try await makePinnedSnapshot(
            engine: .shadow,
            settings: settings,
            record: record
        )
        let job = makeJob(records: [record], start: date, end: date, snapshot: snapshot)

        guard case .success(let payload) = await MacExportJobExecutor().execute(
            job,
            vaultManager: manager
        ) else {
            return XCTFail("Expected connected shadow export to succeed")
        }

        XCTAssertEqual(payload.status, .success)
        XCTAssertEqual(planner.calls.map(\.surface), [.connectedReceivedFilesWithoutSideEffects])
        XCTAssertEqual(planner.calls.first?.settingsSnapshot, snapshot)
        XCTAssertEqual(
            fileSystem.files["/tmp/MacVault/Health/2026-05-12.json"],
            "shadow-native-only"
        )
    }

    func testExecute_connectedRustCommitsRustAuthorityOnly() async throws {
        let planner = ConnectedMacPlannerProbe()
        let manager = makeManagerWithVault(planner: planner)
        let date = Self.day(2026, 5, 12)
        let record = Self.healthData(on: date)
        let settings = makeConnectedSimpleSettings()
        let snapshot = try await makePinnedSnapshot(
            engine: .rust,
            settings: settings,
            record: record
        )
        let job = makeJob(records: [record], start: date, end: date, snapshot: snapshot)

        guard case .success(let payload) = await MacExportJobExecutor().execute(
            job,
            vaultManager: manager
        ) else {
            return XCTFail("Expected connected Rust export to succeed")
        }

        XCTAssertEqual(payload.status, .success)
        XCTAssertEqual(planner.calls.map(\.surface), [.connectedReceivedFilesWithoutSideEffects])
        XCTAssertEqual(
            fileSystem.files["/tmp/MacVault/Health/2026-05-12.json"],
            "rust-authority-only"
        )
        XCTAssertFalse(fileSystem.files.values.contains("native-not-committed"))
    }

    func testExecute_persistedUnsupportedDailyRustPinFailsWhileCurrentDefaultIsLegacy() async throws {
        let date = Self.day(2026, 5, 12)
        let record = Self.healthData(on: date)
        let settings = makeConnectedSimpleSettings()
        let snapshot = try await makePinnedSnapshot(
            engine: .rust,
            settings: settings,
            record: record
        )
        let planner = AppleLooseDailyExportPlanner(policyResolver: AppleExportEnginePolicyResolver(
            injectedOverride: "legacy",
            userDefaults: nil,
            environment: [:]
        ))
        let manager = makeManagerWithVault(planner: planner)
        let job = makeJob(records: [record], start: date, end: date, snapshot: snapshot)

        guard case .success(let payload) = await MacExportJobExecutor().execute(
            job,
            vaultManager: manager
        ) else {
            return XCTFail("Expected a structured terminal response for the rejected operation")
        }

        XCTAssertEqual(payload.status, .failure)
        XCTAssertEqual(payload.failedDateDetails.first?.reason, .fileWriteError)
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    func testExecute_nonLegacyPinWithUnsupportedSettingsFailsBeforePlanningOrWriting() async throws {
        let planner = ConnectedMacPlannerProbe()
        let manager = makeManagerWithVault(planner: planner)
        let date = Self.day(2026, 5, 12)
        let record = Self.healthData(on: date)
        let settings = makeConnectedSimpleSettings()
        settings.generateWeeklyRollups = true
        let snapshot = try await makePinnedSnapshot(
            engine: .rust,
            settings: settings,
            record: record
        )
        let job = makeJob(records: [record], start: date, end: date, snapshot: snapshot)

        guard case .failure(let failure) = await MacExportJobExecutor().execute(
            job,
            vaultManager: manager
        ) else {
            return XCTFail("Expected unsupported pinned operation to fail")
        }

        XCTAssertEqual(failure.reason, .exportWriteFailure)
        XCTAssertTrue(planner.calls.isEmpty)
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    func testExecute_mismatchedManifestAndSnapshotPinsFailBeforePlanningOrWriting() async throws {
        let planner = ConnectedMacPlannerProbe()
        let manager = makeManagerWithVault(planner: planner)
        let date = Self.day(2026, 5, 12)
        let record = Self.healthData(on: date)
        let settings = makeConnectedSimpleSettings()
        let rustSnapshot = try await makePinnedSnapshot(
            engine: .rust,
            settings: settings,
            record: record
        )
        let shadowSnapshot = try await makePinnedSnapshot(
            engine: .shadow,
            settings: settings,
            record: record
        )
        let job = MacExportJob(
            jobID: UUID(),
            createdAt: Date(),
            sourceDeviceName: "Test iPhone",
            dateRangeStart: date,
            dateRangeEnd: date,
            requestedDates: [date],
            records: [record],
            settingsSnapshot: rustSnapshot,
            appleExportEnginePin: try XCTUnwrap(shadowSnapshot.appleExportEnginePin),
            requestedTarget: ExportTargetSnapshot(
                kind: .connectedMac,
                displayName: "Connected Mac",
                destinationDisplayName: "MacVault"
            )
        )

        guard case .failure(let failure) = await MacExportJobExecutor().execute(
            job,
            vaultManager: manager
        ) else {
            return XCTFail("Expected mismatched renderer pins to fail")
        }

        XCTAssertEqual(failure.reason, .exportWriteFailure)
        XCTAssertTrue(failure.message.contains("inconsistent"))
        XCTAssertTrue(planner.calls.isEmpty)
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    func testExecute_providerSidecarGatesWholeOperationToLegacy() async throws {
        let planner = ConnectedMacPlannerProbe()
        let manager = makeManagerWithVault(planner: planner)
        let first = Self.day(2026, 5, 12)
        let second = Self.day(2026, 5, 13)
        let settings = makeConnectedSimpleSettings()
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            calendarTimeZoneIdentifier: Self.healthData(on: first).timeContext.calendarTimeZoneIdentifier
        )
        let sidecar = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-05-13",
            payloads: [ExternalProviderPayload(
                name: "recovery",
                endpoint: "https://api.prod.whoop.com/developer/v2/recovery",
                statusCode: 200,
                data: .object(["score": .number(95)])
            )]
        )
        let job = makeJob(
            records: [Self.healthData(on: first), Self.healthData(on: second)],
            externalDailyRecords: [sidecar],
            start: first,
            end: second,
            snapshot: snapshot
        )

        guard case .success(let payload) = await MacExportJobExecutor().execute(
            job,
            vaultManager: manager
        ) else {
            return XCTFail("Expected legacy provider-sidecar operation to succeed")
        }

        XCTAssertEqual(payload.status, .success)
        XCTAssertEqual(planner.calls.count, 2)
        XCTAssertTrue(planner.calls.allSatisfy { $0.surface == .legacyOnly })
        XCTAssertNotNil(fileSystem.files["/tmp/MacVault/Health/2026-05-12.json"])
        XCTAssertNotNil(fileSystem.files["/tmp/MacVault/Health/2026-05-13.json"])
        XCTAssertNotNil(fileSystem.files["/tmp/MacVault/Health/integrations/whoop/2026-05-13.json"])
    }

    func testExecute_nonLegacyPinWithProviderSidecarFailsBeforeFirstDayWrite() async throws {
        let planner = ConnectedMacPlannerProbe()
        let manager = makeManagerWithVault(planner: planner)
        let first = Self.day(2026, 5, 12)
        let second = Self.day(2026, 5, 13)
        let firstRecord = Self.healthData(on: first)
        let settings = makeConnectedSimpleSettings()
        let snapshot = try await makePinnedSnapshot(
            engine: .rust,
            settings: settings,
            record: firstRecord
        )
        let sidecar = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-05-13",
            payloads: [ExternalProviderPayload(
                name: "recovery",
                endpoint: "https://api.prod.whoop.com/developer/v2/recovery",
                statusCode: 200,
                data: .object(["score": .number(95)])
            )]
        )
        let job = makeJob(
            records: [firstRecord, Self.healthData(on: second)],
            externalDailyRecords: [sidecar],
            start: first,
            end: second,
            snapshot: snapshot
        )

        guard case .failure(let failure) = await MacExportJobExecutor().execute(
            job,
            vaultManager: manager
        ) else {
            return XCTFail("Expected pinned provider-sidecar operation to fail")
        }

        XCTAssertEqual(failure.reason, .exportWriteFailure)
        XCTAssertTrue(planner.calls.isEmpty)
        XCTAssertTrue(fileSystem.files.isEmpty)
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
        XCTAssertEqual(payload.totalFilesWritten, 4)
        XCTAssertEqual(payload.completedDates, [Calendar.current.startOfDay(for: date)])
        XCTAssertEqual(fileSystem.files.count, 5, "Export writes the requested file, three roll-up summaries, and the schema data dictionary")
        XCTAssertNotNil(fileSystem.files["/tmp/MacVault/2026-05-12.md"])
        XCTAssertFalse(fileSystem.files.keys.contains { $0.contains("/tmp/MacVault/Health/") })
        XCTAssertTrue(progressEvents.contains { $0.phase == .receiving })
        XCTAssertTrue(progressEvents.contains { $0.phase == .writing })
        XCTAssertEqual(progressEvents.last?.phase, .completed)
    }

    func testExecute_preservesSourceDeviceRequestedDateAcrossTimeZones() async throws {
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let sourceDate = sourceCalendar.date(from: DateComponents(
            year: 2026,
            month: 5,
            day: 12
        ))!
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let job = makeJob(
            records: [Self.healthData(on: sourceDate)],
            start: sourceDate,
            end: sourceDate,
            requestedDates: [sourceDate]
        )

        let result = await executor.execute(job, vaultManager: manager)

        guard case .success(let payload) = result else {
            return XCTFail("Expected successful payload")
        }
        XCTAssertEqual(payload.completedDates, [sourceDate])
    }

    func testArchiveBearingJobSpoolEncodeDecodeAndExecutorPreserveCanonicalArchive() async throws {
        let manager = makeManagerWithVault()
        let date = Self.day(2026, 5, 12)
        let startOfDay = Calendar.current.startOfDay(for: date)
        let archive = HealthKitRecordArchive(
            captureStatus: .complete,
            dailyOwnership: HealthKitDailyOwnershipMetadata(
                ownerDate: "2026-05-12",
                intervalStart: startOfDay,
                intervalEnd: Calendar.current.date(byAdding: .day, value: 1, to: startOfDay)!,
                calendarTimeZoneIdentifier: TimeZone.current.identifier
            )
        )
        var record = HealthData(
            date: date,
            healthKitRecordArchive: archive,
            healthKitRecordCaptureStatus: .complete
        )
        record.activity.steps = 4_321
        let settings = makeSettings(formats: [.json]) { settings in
            settings.includeGranularData = true
            settings.generateWeeklyRollups = false
            settings.generateMonthlyRollups = false
            settings.generateYearlyRollups = false
        }
        let job = makeJob(
            records: [record],
            start: date,
            end: date,
            snapshot: makeSnapshot(from: settings)
        )

        let prepared = try ConnectedTransferFile.encode(job)
        defer { prepared.remove() }
        let decoded = try JSONDecoder().decode(
            MacExportJob.self,
            from: Data(contentsOf: prepared.url, options: [.mappedIfSafe])
        )
        XCTAssertEqual(
            decoded.records.first?.healthKitRecordArchive?.recordSchemaVersion,
            HealthKitRecordArchive.currentRecordSchemaVersion
        )
        XCTAssertEqual(
            decoded.records.first?.healthKitRecordArchive?.schemaIdentifier,
            HealthKitRecordArchive.canonicalSchemaIdentifier
        )

        guard case .success(let payload) = await MacExportJobExecutor().execute(
            decoded,
            vaultManager: manager
        ) else {
            return XCTFail("Expected decoded archive-bearing job to execute")
        }
        XCTAssertEqual(payload.status, .success)
        let exportedJSON = try XCTUnwrap(fileSystem.files.first { path, _ in
            path.hasSuffix("/2026-05-12.json")
        }?.value)
        let daily = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(exportedJSON.utf8)) as? [String: Any]
        )
        XCTAssertEqual(daily["schema_version"] as? Int, HealthMdExportSchema.version)
        let exportedArchive = try XCTUnwrap(daily["healthkit_record_archive"] as? [String: Any])
        XCTAssertEqual(exportedArchive["schema"] as? String, HealthKitRecordArchive.canonicalSchemaIdentifier)
        XCTAssertEqual(
            exportedArchive["schema_version"] as? Int,
            HealthKitRecordArchive.currentRecordSchemaVersion
        )
    }

    func testExecute_usesIPhoneSubfolderInsteadOfMacLocalSubfolder() async throws {
        let manager = makeManagerWithVault()
        manager.healthSubfolder = "MacOnly"
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let settings = makeSettings { settings in
            settings.folderStructure = "AHD/{year}/{month}"
            settings.generateWeeklyRollups = false
            settings.generateMonthlyRollups = false
            settings.generateYearlyRollups = false
        }
        let job = makeJob(
            records: [Self.healthData(on: date)],
            start: date,
            end: date,
            snapshot: .from(settings, healthSubfolder: "2. Areas/Health")
        )

        guard case .success(let payload) = await executor.execute(job, vaultManager: manager) else {
            return XCTFail("Expected successful payload")
        }

        XCTAssertEqual(payload.status, .success)
        XCTAssertNotNil(fileSystem.files["/tmp/MacVault/2. Areas/Health/AHD/2026/05/2026-05-12.md"])
        XCTAssertNotNil(fileSystem.files["/tmp/MacVault/2. Areas/Health/_healthmd_data_dictionary.json"])
        XCTAssertFalse(fileSystem.files.keys.contains { $0.contains("/MacOnly/") })
    }

    func testExecute_honorsIPhoneDictionarySuppressionWithoutDroppingMarkdown() async throws {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let settings = makeSettings { settings in
            settings.exportFormats = [.markdown]
            settings.includeDataDictionary = false
            settings.generateWeeklyRollups = false
            settings.generateMonthlyRollups = false
            settings.generateYearlyRollups = false
        }
        let job = makeJob(
            records: [Self.healthData(on: date)],
            start: date,
            end: date,
            snapshot: .from(settings, healthSubfolder: "Health")
        )

        guard case .success(let payload) = await executor.execute(job, vaultManager: manager) else {
            return XCTFail("Expected successful payload")
        }

        XCTAssertEqual(payload.status, .success)
        XCTAssertNotNil(fileSystem.files["/tmp/MacVault/Health/2026-05-12.md"])
        XCTAssertNil(fileSystem.files[
            "/tmp/MacVault/Health/\(HealthMdExportSchema.dataDictionaryFilename)"
        ])
    }

    func testStream_usesIPhoneSubfolderInsteadOfMacLocalSubfolder() async throws {
        let manager = makeManagerWithVault()
        manager.healthSubfolder = "MacOnly"
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let jobID = UUID()
        let settings = makeSettings { settings in
            settings.folderStructure = "AHD/{year}/{month}"
            settings.generateWeeklyRollups = false
            settings.generateMonthlyRollups = false
            settings.generateYearlyRollups = false
        }
        let start = makeStreamStart(
            jobID: jobID,
            start: date,
            end: date,
            totalTransferDays: 1,
            snapshot: .from(settings, healthSubfolder: "2. Areas/Health")
        )
        _ = executor.startStream(start, vaultManager: manager)
        _ = await executor.receiveChunk(MacExportStreamChunk(
            jobID: jobID,
            sequence: 1,
            records: [Self.healthData(on: date)],
            externalDailyRecords: [],
            processedTransferDays: 1,
            totalTransferDays: 1
        ), vaultManager: manager)

        guard case .success(let payload) = await executor.completeStream(
            MacExportStreamComplete(jobID: jobID, totalChunks: 1, iphoneFailedDateDetails: []),
            vaultManager: manager
        ) else {
            return XCTFail("Expected successful payload")
        }

        XCTAssertEqual(payload.status, .success)
        XCTAssertNotNil(fileSystem.files["/tmp/MacVault/2. Areas/Health/AHD/2026/05/2026-05-12.md"])
        XCTAssertNotNil(fileSystem.files["/tmp/MacVault/2. Areas/Health/_healthmd_data_dictionary.json"])
        XCTAssertFalse(fileSystem.files.keys.contains { $0.contains("/MacOnly/") })
    }

    func testPinnedStreamBuffersUntilWholeOperationProviderGatePasses() async throws {
        let planner = ConnectedMacPlannerProbe()
        let manager = makeManagerWithVault(planner: planner)
        let executor = MacExportJobExecutor()
        let first = Self.day(2026, 5, 12)
        let second = Self.day(2026, 5, 13)
        let firstRecord = Self.healthData(on: first)
        let snapshot = try await makePinnedSnapshot(
            engine: .rust,
            settings: makeConnectedSimpleSettings(),
            record: firstRecord
        )
        let jobID = UUID()
        let start = makeStreamStart(
            jobID: jobID,
            start: first,
            end: second,
            totalTransferDays: 2,
            snapshot: snapshot
        )
        guard case .success = executor.startStream(start, vaultManager: manager) else {
            return XCTFail("Expected pinned stream start")
        }
        guard case .success = await executor.receiveChunk(
            MacExportStreamChunk(
                jobID: jobID,
                sequence: 1,
                records: [firstRecord],
                externalDailyRecords: [],
                processedTransferDays: 1,
                totalTransferDays: 2
            ),
            vaultManager: manager
        ) else {
            return XCTFail("Expected first pinned chunk")
        }
        XCTAssertTrue(planner.calls.isEmpty)
        XCTAssertTrue(fileSystem.files.isEmpty)

        let sidecar = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-05-13",
            payloads: [ExternalProviderPayload(
                name: "recovery",
                endpoint: "https://api.prod.whoop.com/developer/v2/recovery",
                statusCode: 200,
                data: .object(["score": .number(95)])
            )]
        )
        guard case .success = await executor.receiveChunk(
            MacExportStreamChunk(
                jobID: jobID,
                sequence: 2,
                records: [Self.healthData(on: second)],
                externalDailyRecords: [sidecar],
                processedTransferDays: 2,
                totalTransferDays: 2
            ),
            vaultManager: manager
        ) else {
            return XCTFail("Expected second pinned chunk")
        }
        guard case .failure(let failure) = await executor.completeStream(
            MacExportStreamComplete(jobID: jobID, totalChunks: 2, iphoneFailedDateDetails: []),
            vaultManager: manager
        ) else {
            return XCTFail("Expected whole pinned stream provider gate failure")
        }
        XCTAssertEqual(failure.reason, .exportWriteFailure)
        XCTAssertTrue(planner.calls.isEmpty)
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    func testStream_startChunksComplete_writesReceivedRecords() async throws {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let jobID = UUID()
        let start = makeStreamStart(jobID: jobID, start: date, end: date, totalTransferDays: 1)

        guard case .success(let startAck) = executor.startStream(start, vaultManager: manager) else {
            return XCTFail("Expected stream start ack")
        }
        XCTAssertTrue(startAck.accepted)
        XCTAssertEqual(startAck.sequence, -1)
        XCTAssertEqual(executor.currentJobID, jobID)

        let chunk = MacExportStreamChunk(
            jobID: jobID,
            sequence: 1,
            records: [Self.healthData(on: date)],
            externalDailyRecords: [],
            processedTransferDays: 1,
            totalTransferDays: 1
        )
        guard case .success(let chunkAck) = await executor.receiveChunk(chunk, vaultManager: manager) else {
            return XCTFail("Expected chunk ack")
        }
        XCTAssertTrue(chunkAck.accepted)
        XCTAssertEqual(chunkAck.processedDays, 1)

        let complete = MacExportStreamComplete(jobID: jobID, totalChunks: 1, iphoneFailedDateDetails: [])
        guard case .success(let payload) = await executor.completeStream(complete, vaultManager: manager) else {
            return XCTFail("Expected stream result")
        }
        XCTAssertEqual(payload.status, .success)
        XCTAssertEqual(payload.successCount, 1)
        XCTAssertEqual(payload.totalFilesWritten, 4)
        XCTAssertNil(executor.currentJobID)
    }

    func testStream_dailyNotesOnlyWritesNoAdditionalFiles() async throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacExecutorDailyNotesOnlyStream-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let manager = makeManagerWithVault(
            fileSystem: SystemFileSystem(),
            bookmarkResolver: makeAccessGrantedBookmarkResolver(),
            vaultPath: vaultURL.path
        )
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let jobID = UUID()
        let settings = makeSettings(formats: []) { settings in
            settings.archiveExportFiles = true
            settings.dailyNoteInjection.enabled = true
            settings.dailyNoteInjection.dailyNotesOnly = true
            settings.dailyNoteInjection.createIfMissing = true
        }
        let start = makeStreamStart(
            jobID: jobID,
            start: date,
            end: date,
            totalTransferDays: 1,
            snapshot: makeSnapshot(from: settings)
        )

        guard case .success = executor.startStream(start, vaultManager: manager) else {
            return XCTFail("Expected stream start")
        }
        guard case .success = await executor.receiveChunk(MacExportStreamChunk(
            jobID: jobID,
            sequence: 1,
            records: [Self.healthData(on: date)],
            externalDailyRecords: [],
            processedTransferDays: 1,
            totalTransferDays: 1
        ), vaultManager: manager) else {
            return XCTFail("Expected chunk acceptance")
        }
        guard case .success(let payload) = await executor.completeStream(
            MacExportStreamComplete(jobID: jobID, totalChunks: 1, iphoneFailedDateDetails: []),
            vaultManager: manager
        ) else {
            return XCTFail("Expected stream completion")
        }

        XCTAssertEqual(payload.status, .success)
        XCTAssertEqual(payload.totalFilesWritten, 0)
        XCTAssertEqual(payload.dailyNoteUpdateCount, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vaultURL.path), ["Daily"])
    }

    func testStream_archiveRetainsEachWHOOPSidecarOncePerChunk() async throws {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let first = Self.day(2026, 5, 12)
        let second = Self.day(2026, 5, 13)
        let jobID = UUID()
        let settings = makeSettings { settings in
            settings.archiveExportFiles = true
            settings.generateWeeklyRollups = false
            settings.generateMonthlyRollups = false
            settings.generateYearlyRollups = false
        }
        let start = makeStreamStart(
            jobID: jobID,
            start: first,
            end: second,
            totalTransferDays: 2,
            snapshot: makeSnapshot(from: settings)
        )
        _ = executor.startStream(start, vaultManager: manager)

        let sidecars = [first, second].map { date in
            ExternalDailyRecord(
                provider: .whoop,
                date: ExternalProviderAPIClient.dayString(date),
                payloads: [ExternalProviderPayload(
                    name: "cycles",
                    endpoint: "https://api.prod.whoop.com/developer/v2/cycle",
                    statusCode: 200,
                    data: .object(["records": .array([.object(["id": .number(1)])])])
                )]
            )
        }
        let chunk = MacExportStreamChunk(
            jobID: jobID,
            sequence: 1,
            records: [Self.healthData(on: first), Self.healthData(on: second)],
            externalDailyRecords: sidecars,
            processedTransferDays: 2,
            totalTransferDays: 2
        )
        _ = await executor.receiveChunk(chunk, vaultManager: manager)

        guard case .success(let payload) = await executor.completeStream(
            MacExportStreamComplete(jobID: jobID, totalChunks: 1, iphoneFailedDateDetails: []),
            vaultManager: manager
        ) else {
            return XCTFail("Expected stream result")
        }

        XCTAssertEqual(payload.externalRecordFileCount, 2)
        XCTAssertNotNil(fileSystem.files["/tmp/MacVault/integrations/whoop/2026-05-12.json"])
        XCTAssertNotNil(fileSystem.files["/tmp/MacVault/integrations/whoop/2026-05-13.json"])
    }

    func testStream_outOfOrderChunkRejectedWithoutAdvancingSequence() async throws {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let jobID = UUID()
        let start = makeStreamStart(jobID: jobID, start: date, end: date, totalTransferDays: 1)
        _ = executor.startStream(start, vaultManager: manager)

        let outOfOrder = MacExportStreamChunk(
            jobID: jobID,
            sequence: 2,
            records: [Self.healthData(on: date)],
            externalDailyRecords: [],
            processedTransferDays: 1,
            totalTransferDays: 1
        )
        guard case .success(let rejectedAck) = await executor.receiveChunk(outOfOrder, vaultManager: manager) else {
            return XCTFail("Expected rejected ack")
        }
        XCTAssertFalse(rejectedAck.accepted)
        XCTAssertEqual(rejectedAck.processedDays, 0)
        XCTAssertTrue(fileSystem.files.isEmpty)

        let expected = MacExportStreamChunk(
            jobID: jobID,
            sequence: 1,
            records: [Self.healthData(on: date)],
            externalDailyRecords: [],
            processedTransferDays: 1,
            totalTransferDays: 1
        )
        guard case .success(let acceptedAck) = await executor.receiveChunk(expected, vaultManager: manager) else {
            return XCTFail("Expected accepted retry ack")
        }
        XCTAssertTrue(acceptedAck.accepted)
    }

    func testStream_duplicateChunkReplaysPriorAckWithoutRewriting() async throws {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let jobID = UUID()
        let settings = makeSettings { settings in
            settings.generateWeeklyRollups = false
            settings.generateMonthlyRollups = false
            settings.generateYearlyRollups = false
        }
        let start = makeStreamStart(
            jobID: jobID,
            start: date,
            end: date,
            totalTransferDays: 1,
            snapshot: makeSnapshot(from: settings)
        )
        _ = executor.startStream(start, vaultManager: manager)
        let chunk = MacExportStreamChunk(
            jobID: jobID,
            sequence: 1,
            records: [Self.healthData(on: date)],
            externalDailyRecords: [],
            processedTransferDays: 1,
            totalTransferDays: 1
        )
        guard case .success(let firstAck) = await executor.receiveChunk(chunk, vaultManager: manager),
              case .success(let replayedAck) = await executor.receiveChunk(chunk, vaultManager: manager) else {
            return XCTFail("Expected duplicate ACK replay")
        }
        XCTAssertEqual(replayedAck, firstAck)
        XCTAssertEqual(replayedAck.processedDays, 1)
        XCTAssertEqual(fileSystem.files.keys.filter { $0 == "/tmp/MacVault/2026-05-12.md" }.count, 1)
    }

    func testStream_rollupExpansionDatesNeverWriteOrdinaryDailyFiles() async throws {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let requestedDate = Self.day(2026, 5, 12)
        let settings = makeSettings { settings in
            settings.generateWeeklyRollups = true
            settings.generateMonthlyRollups = false
            settings.generateYearlyRollups = false
        }
        let rollupDates = ExportOrchestrator.rollupSourceDates(
            for: [requestedDate],
            periods: [.weekly],
            latestAllowedDate: Self.day(2026, 12, 31)
        )
        let jobID = UUID()
        let start = makeStreamStart(
            jobID: jobID,
            start: requestedDate,
            end: requestedDate,
            totalTransferDays: rollupDates.count,
            snapshot: makeSnapshot(from: settings)
        )
        _ = executor.startStream(start, vaultManager: manager)
        _ = await executor.receiveChunk(MacExportStreamChunk(
            jobID: jobID,
            sequence: 1,
            records: rollupDates.map { Self.healthData(on: $0) },
            externalDailyRecords: [],
            processedTransferDays: rollupDates.count,
            totalTransferDays: rollupDates.count
        ), vaultManager: manager)
        guard case .success(let result) = await executor.completeStream(
            MacExportStreamComplete(jobID: jobID, totalChunks: 1, iphoneFailedDateDetails: []),
            vaultManager: manager
        ) else { return XCTFail("Expected stream result") }

        XCTAssertEqual(result.successCount, 1)
        XCTAssertNotNil(fileSystem.files["/tmp/MacVault/2026-05-12.md"])
        for expansionDate in rollupDates where !Calendar.current.isDate(expansionDate, inSameDayAs: requestedDate) {
            let name = Self.dateString(expansionDate)
            XCTAssertNil(
                fileSystem.files["/tmp/MacVault/\(name).md"],
                "Roll-up source \(name) must not be written as an ordinary daily export"
            )
        }
        XCTAssertNotNil(fileSystem.files.first { $0.key.contains("/Rollups/Weekly/") })
    }

    func testStream_abortClearsBusyState() async {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let jobID = UUID()
        let start = makeStreamStart(jobID: jobID, start: date, end: date, totalTransferDays: 1)
        _ = executor.startStream(start, vaultManager: manager)
        XCTAssertEqual(executor.currentJobID, jobID)

        executor.abortStream(MacExportStreamAbort(jobID: jobID, reason: .cancelled, message: "test abort"))

        XCTAssertNil(executor.currentJobID)
        XCTAssertFalse(executor.isBusy)
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

    func testExecute_dailyNotesOnlyAcceptsNoFormatsAndWritesNoAdditionalFiles() async throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacExecutorDailyNotesOnly-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let manager = makeManagerWithVault(
            fileSystem: SystemFileSystem(),
            bookmarkResolver: makeAccessGrantedBookmarkResolver(),
            vaultPath: vaultURL.path
        )
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let settings = makeSettings(formats: []) { settings in
            settings.archiveExportFiles = true
            settings.generateWeeklyRollups = true
            settings.individualTracking.globalEnabled = true
            settings.individualTracking.setTrackIndividually("steps", enabled: true)
            settings.dailyNoteInjection.enabled = true
            settings.dailyNoteInjection.dailyNotesOnly = true
            settings.dailyNoteInjection.createIfMissing = true
            settings.dailyNoteInjection.folderPath = "Daily"
        }
        let job = makeJob(
            records: [Self.healthData(on: date)],
            start: date,
            end: date,
            snapshot: makeSnapshot(from: settings)
        )

        guard case .success(let payload) = await executor.execute(job, vaultManager: manager) else {
            return XCTFail("Expected Daily Notes Only job to succeed")
        }

        XCTAssertEqual(payload.status, .success)
        XCTAssertEqual(payload.formatsPerDate, 0)
        XCTAssertEqual(payload.totalFilesWritten, 0)
        XCTAssertEqual(payload.dailyNoteUpdateCount, 1)
        XCTAssertEqual(payload.dailyNoteSkipCount, 0)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: vaultURL.path), ["Daily"])
    }

    func testExecute_dailyNotesOnlyMissingNoteIsTerminalPartialSuccess() async throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacExecutorDailyNotesOnlySkip-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let manager = makeManagerWithVault(
            fileSystem: SystemFileSystem(),
            bookmarkResolver: makeAccessGrantedBookmarkResolver(),
            vaultPath: vaultURL.path
        )
        let date = Self.day(2026, 5, 12)
        let settings = makeSettings(formats: []) { settings in
            settings.dailyNoteInjection.enabled = true
            settings.dailyNoteInjection.dailyNotesOnly = true
            settings.dailyNoteInjection.createIfMissing = false
            settings.dailyNoteInjection.folderPath = "Daily"
        }
        let job = makeJob(
            records: [Self.healthData(on: date)],
            start: date,
            end: date,
            snapshot: makeSnapshot(from: settings)
        )

        guard case .success(let payload) = await MacExportJobExecutor().execute(job, vaultManager: manager) else {
            return XCTFail("Expected a terminal Daily Notes Only skip result")
        }

        XCTAssertEqual(payload.status, .partialSuccess)
        XCTAssertEqual(payload.successCount, 0)
        XCTAssertEqual(payload.dailyNoteSkipCount, 1)
        XCTAssertEqual(payload.completedDates?.count, 1)
        XCTAssertTrue(payload.completedDates.map { Calendar.current.isDate($0[0], inSameDayAs: date) } ?? false)
        XCTAssertEqual(payload.totalFilesWritten, 0)
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: vaultURL.path).isEmpty)
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
        XCTAssertEqual(
            Set(payload.completedDates ?? []),
            Set([start, end].map { Calendar.current.startOfDay(for: $0) })
        )
        XCTAssertEqual(fileSystem.files.count, 5, "Successful dates write the requested file, three roll-up summaries, and the schema data dictionary")
    }

    func testExecute_writesExternalProviderSidecarsFromJob() async throws {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let settings = makeSettings { settings in
            settings.generateWeeklyRollups = false
            settings.generateMonthlyRollups = false
            settings.generateYearlyRollups = false
        }
        let externalRecord = ExternalDailyRecord(
            provider: .whoop,
            date: "2026-05-12",
            payloads: [ExternalProviderPayload(
                name: "recovery",
                endpoint: "https://api.prod.whoop.com/developer/v2/recovery?start=2026-05-12T00:00:00Z",
                statusCode: 200,
                data: .object(["records": .array([.object(["recovery_score": .number(95)])])])
            )]
        )
        let job = makeJob(
            records: [Self.healthData(on: date)],
            externalDailyRecords: [externalRecord],
            start: date,
            end: date,
            snapshot: makeSnapshot(from: settings)
        )

        let result = await executor.execute(job, vaultManager: manager)

        guard case .success(let payload) = result else {
            return XCTFail("Expected result payload")
        }
        XCTAssertEqual(payload.status, .success)
        XCTAssertEqual(payload.successCount, 1)
        XCTAssertEqual(payload.totalFilesWritten, 2)
        XCTAssertEqual(payload.externalRecordFileCount, 1)

        let sidecarPath = "/tmp/MacVault/integrations/whoop/2026-05-12.json"
        let sidecar = try XCTUnwrap(fileSystem.files[sidecarPath])
        XCTAssertTrue(sidecar.contains("healthmd.external_provider_daily"))
        XCTAssertTrue(sidecar.contains("recovery"))
        XCTAssertNil(fileSystem.files.first { path, _ in
            path.contains("/integrations/") && path != sidecarPath
        })
    }

    func testExecute_rollupsUseFullWindowRecordsReceivedFromIPhone() async throws {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let start = Self.day(2026, 5, 12)
        let end = Self.day(2026, 5, 13)
        let weekRecords = ExportOrchestrator.rollupSourceDates(
            for: [start, end],
            periods: [.weekly],
            latestAllowedDate: Self.day(2026, 12, 31)
        ).map { Self.healthData(on: $0) }
        let settings = makeSettings { settings in
            settings.generateWeeklyRollups = true
            settings.generateMonthlyRollups = false
            settings.generateYearlyRollups = false
        }
        let job = makeJob(
            records: weekRecords,
            start: start,
            end: end,
            snapshot: makeSnapshot(from: settings)
        )

        let result = await executor.execute(job, vaultManager: manager)

        guard case .success(let payload) = result else {
            return XCTFail("Expected result payload")
        }
        XCTAssertEqual(payload.status, .success)
        XCTAssertEqual(payload.successCount, 2)
        XCTAssertEqual(payload.totalCount, 2)
        XCTAssertEqual(payload.totalFilesWritten, 3)
        let weeklyRollup = try XCTUnwrap(
            fileSystem.files["/tmp/MacVault/Rollups/Weekly/2026-W20.md"]
        )
        XCTAssertTrue(weeklyRollup.contains("days_counted: 7"))
        XCTAssertTrue(weeklyRollup.contains("| Steps | `steps` | 30,247 | steps | 7/7 | sum |"))
    }

    func testExecute_summaryOnlyWritesRollupsWithoutDailyRecords() async throws {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let weekRecords = ExportOrchestrator.rollupSourceDates(
            for: [date],
            periods: [.weekly],
            latestAllowedDate: Self.day(2026, 12, 31)
        ).map { Self.healthData(on: $0) }
        let settings = makeSettings { settings in
            settings.generateWeeklyRollups = true
            settings.generateMonthlyRollups = false
            settings.generateYearlyRollups = false
            settings.summaryOnlyExport = true
        }
        let job = makeJob(
            records: weekRecords,
            start: date,
            end: date,
            snapshot: makeSnapshot(from: settings)
        )

        let result = await executor.execute(job, vaultManager: manager)

        guard case .success(let payload) = result else {
            return XCTFail("Expected result payload")
        }
        XCTAssertEqual(payload.status, .success)
        XCTAssertEqual(payload.successCount, 1)
        XCTAssertEqual(payload.formatsPerDate, 0)
        XCTAssertEqual(payload.totalFilesWritten, 1)
        XCTAssertNil(
            fileSystem.files["/tmp/MacVault/2026-05-12.md"],
            "Summary-only mode must not write daily records on Mac"
        )
        XCTAssertNotNil(fileSystem.files["/tmp/MacVault/Rollups/Weekly/2026-W20.md"])
        XCTAssertNotNil(fileSystem.files["/tmp/MacVault/_healthmd_data_dictionary.json"])
    }

    func testExecute_archiveModeWritesZipArchiveContainingRollups() async throws {
        let vaultURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("MacExportArchiveTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: vaultURL, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: vaultURL) }

        let manager = makeManagerWithVault(
            defaults: FakeUserDefaults(),
            fileSystem: SystemFileSystem(),
            bookmarkResolver: makeAccessGrantedBookmarkResolver(),
            vaultPath: vaultURL.path
        )
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let weekRecords = ExportOrchestrator.rollupSourceDates(
            for: [date],
            periods: [.weekly],
            latestAllowedDate: Self.day(2026, 12, 31)
        ).map { Self.healthData(on: $0) }
        let settings = makeSettings(formats: [.markdown, .json]) { settings in
            settings.archiveExportFiles = true
            settings.generateWeeklyRollups = true
            settings.generateMonthlyRollups = false
            settings.generateYearlyRollups = false
        }
        let job = makeJob(
            records: weekRecords,
            start: date,
            end: date,
            snapshot: makeSnapshot(from: settings)
        )

        let result = await executor.execute(job, vaultManager: manager)

        guard case .success(let payload) = result else {
            return XCTFail("Expected result payload")
        }
        XCTAssertEqual(payload.status, .success)
        XCTAssertEqual(payload.successCount, 1)
        XCTAssertEqual(payload.totalCount, 1)
        XCTAssertEqual(payload.formatsPerDate, 0)
        XCTAssertEqual(payload.totalFilesWritten, 1)

        let archiveURL = vaultURL.appendingPathComponent("Health.md Export 2026-05-12.zip")
        XCTAssertTrue(FileManager.default.fileExists(atPath: archiveURL.path))
        let archiveData = try Data(contentsOf: archiveURL)
        XCTAssertNotNil(archiveData.range(of: Data("2026-05-12.md".utf8)))
        XCTAssertNotNil(archiveData.range(of: Data("2026-05-12.json".utf8)))
        XCTAssertNotNil(archiveData.range(of: Data("Rollups/Weekly/2026-W20.md".utf8)))
        XCTAssertNotNil(archiveData.range(of: Data("Rollups/Weekly/2026-W20.json".utf8)))
        XCTAssertNotNil(archiveData.range(of: Data("days_counted: 7".utf8)))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vaultURL.appendingPathComponent("Rollups/Weekly/2026-W20.md").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vaultURL.appendingPathComponent("Rollups/Weekly/2026-W20.json").path
        ))
        XCTAssertFalse(FileManager.default.fileExists(
            atPath: vaultURL.appendingPathComponent("2026-05-12.md").path
        ))
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
        XCTAssertEqual(payload.completedDates, [])
        XCTAssertTrue(failingFileSystem.files.isEmpty)
    }

    func testExecute_archiveWriteFailureLeavesPreparedDatesIncomplete() async {
        let manager = makeManagerWithVault(
            defaults: FakeUserDefaults(),
            fileSystem: FakeFileSystem(),
            bookmarkResolver: makeAccessGrantedBookmarkResolver(),
            vaultPath: "/dev/null"
        )
        let settings = makeSettings { settings in
            settings.archiveExportFiles = true
            settings.generateWeeklyRollups = false
            settings.generateMonthlyRollups = false
            settings.generateYearlyRollups = false
        }
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let job = makeJob(
            records: [Self.healthData(on: date)],
            start: date,
            end: date,
            snapshot: makeSnapshot(from: settings)
        )

        let result = await executor.execute(job, vaultManager: manager)

        guard case .success(let payload) = result else {
            return XCTFail("Expected final result payload")
        }
        XCTAssertEqual(payload.status, .partialSuccess)
        XCTAssertEqual(payload.completedDates, [])
        XCTAssertTrue(payload.failedDateDetails.contains { $0.reason == .fileWriteError })
    }

    func testExecute_rejectsDuplicateRequestedDatesBeforeWriting() async {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let job = makeJob(
            records: [Self.healthData(on: date)],
            start: date,
            end: date,
            requestedDates: [date, date]
        )

        let result = await executor.execute(job, vaultManager: manager)

        guard case .failure(let failure) = result else {
            return XCTFail("Expected malformed requested dates to be rejected")
        }
        XCTAssertEqual(failure.reason, .payloadDecodeFailure)
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    func testStartStream_rejectsRequestedDateCountMismatch() {
        let manager = makeManagerWithVault()
        let executor = MacExportJobExecutor()
        let date = Self.day(2026, 5, 12)
        let start = MacExportStreamStart(
            jobID: UUID(),
            createdAt: Date(),
            sourceDeviceName: "Test iPhone",
            dateRangeStart: date,
            dateRangeEnd: date,
            requestedDates: [date],
            totalRequestedDays: 2,
            totalTransferDays: 2,
            settingsSnapshot: makeSnapshot(),
            requestedTarget: nil,
            chunkStrategyVersion: 1
        )

        let result = executor.startStream(start, vaultManager: manager)

        guard case .failure(let failure) = result else {
            return XCTFail("Expected inconsistent stream counters to be rejected")
        }
        XCTAssertEqual(failure.reason, .payloadDecodeFailure)
        XCTAssertFalse(executor.isBusy)
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
        XCTAssertEqual(payload.completedDates, [])
        XCTAssertTrue(fileSystem.files.isEmpty)
    }

    private func makeManager(
        defaults: FakeUserDefaults? = nil,
        fileSystem: FileSystemAccessing? = nil,
        bookmarkResolver: FakeBookmarkResolver? = nil,
        planner: (any AppleLooseDailyExportPlanning)? = nil
    ) -> VaultManager {
        let manager = VaultManager(
            defaults: defaults ?? self.defaults,
            fileSystem: fileSystem ?? self.fileSystem,
            bookmarkResolver: bookmarkResolver ?? self.bookmarkResolver,
            appleLooseDailyPlanner: planner
        )
        return LifecycleHarness.retain(manager)
    }

    private func makeManagerWithVault(
        defaults: FakeUserDefaults? = nil,
        fileSystem: FileSystemAccessing? = nil,
        bookmarkResolver: FakeBookmarkResolver? = nil,
        vaultPath: String = "/tmp/MacVault",
        planner: (any AppleLooseDailyExportPlanning)? = nil
    ) -> VaultManager {
        let manager = makeManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: bookmarkResolver,
            planner: planner
        )
        manager.setVaultFolder(URL(fileURLWithPath: vaultPath))
        return manager
    }

    private func makeJob(
        records: [HealthData],
        externalDailyRecords: [ExternalDailyRecord] = [],
        start: Date,
        end: Date,
        requestedDates: [Date]? = nil,
        snapshot: ExportSettingsSnapshot? = nil
    ) -> MacExportJob {
        MacExportJob(
            jobID: UUID(),
            createdAt: Date(),
            sourceDeviceName: "Test iPhone",
            dateRangeStart: start,
            dateRangeEnd: end,
            requestedDates: requestedDates ?? ExportOrchestrator.dateRange(from: start, to: end),
            records: records,
            externalDailyRecords: externalDailyRecords,
            settingsSnapshot: snapshot ?? makeSnapshot(),
            requestedTarget: ExportTargetSnapshot(
                kind: .connectedMac,
                displayName: "Connected Mac",
                destinationDisplayName: "MacVault"
            )
        )
    }

    private func makeSnapshot(formats: Set<ExportFormat> = [.markdown]) -> ExportSettingsSnapshot {
        makeSnapshot(from: makeSettings(formats: formats))
    }

    private func makeSnapshot(from settings: AdvancedExportSettings) -> ExportSettingsSnapshot {
        makeSnapshot(from: settings, healthSubfolder: VaultManager.defaultHealthSubfolder)
    }

    private func makeSnapshot(
        from settings: AdvancedExportSettings,
        healthSubfolder: String
    ) -> ExportSettingsSnapshot {
        .from(settings, healthSubfolder: healthSubfolder)
    }

    private func makeStreamStart(
        jobID: UUID,
        start: Date,
        end: Date,
        totalTransferDays: Int,
        snapshot: ExportSettingsSnapshot? = nil
    ) -> MacExportStreamStart {
        MacExportStreamStart(
            jobID: jobID,
            createdAt: Date(),
            sourceDeviceName: "Test iPhone",
            dateRangeStart: start,
            dateRangeEnd: end,
            requestedDates: ExportOrchestrator.dateRange(from: start, to: end),
            totalRequestedDays: ExportOrchestrator.dateRange(from: start, to: end).count,
            totalTransferDays: totalTransferDays,
            settingsSnapshot: snapshot ?? makeSnapshot(),
            requestedTarget: ExportTargetSnapshot(
                kind: .connectedMac,
                displayName: "Connected Mac",
                destinationDisplayName: "MacVault"
            ),
            chunkStrategyVersion: 1
        )
    }

    private func makeConnectedSimpleSettings() -> AdvancedExportSettings {
        makeSettings(formats: [.json]) { settings in
            settings.includeGranularData = false
            settings.generateWeeklyRollups = false
            settings.generateMonthlyRollups = false
            settings.generateYearlyRollups = false
            settings.archiveExportFiles = false
            settings.summaryOnlyExport = false
            settings.dailyNoteInjection.enabled = false
            settings.individualTracking.globalEnabled = false
        }
    }

    private func makePinnedSnapshot(
        engine: ExportEngineMode,
        settings: AdvancedExportSettings,
        record: HealthData
    ) async throws -> ExportSettingsSnapshot {
        let calendarTimeZoneIdentifier = record.timeContext.calendarTimeZoneIdentifier
        let pin = await AppleExportEnginePolicyResolver(
            injectedOverride: engine.rawValue,
            userDefaults: nil,
            environment: [:]
        ).pinForNewOperation(calendarTimeZoneIdentifier: calendarTimeZoneIdentifier)
        let unwrappedPin = try XCTUnwrap(pin)
        return ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            appleExportEnginePin: unwrappedPin,
            calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
        )
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
        settings.generateWeeklyRollups = true
        settings.generateMonthlyRollups = true
        settings.generateYearlyRollups = true
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
        _ = try localManager.exportRollupSummaries(from: records, settings: settings)

        let sortedDates = records.map(\.date).sorted()
        let job = makeJob(
            records: records,
            start: sortedDates.first ?? Date(),
            end: sortedDates.last ?? Date(),
            snapshot: makeSnapshot(from: settings, healthSubfolder: "Health")
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

    private static func dateString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
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

@MainActor
final class ConnectedMacPlannerProbe: AppleLooseDailyExportPlanning {
    struct Call {
        let date: Date
        let settingsSnapshot: ExportSettingsSnapshot
        let surface: AppleExportOperationSurface
    }

    private(set) var calls: [Call] = []

    func plan(
        healthData: HealthData,
        settingsSnapshot: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface
    ) async throws -> AppleLooseDailyPlanResolution {
        calls.append(Call(
            date: healthData.date,
            settingsSnapshot: settingsSnapshot,
            surface: surface
        ))
        guard surface == .connectedReceivedFilesWithoutSideEffects,
              let pin = settingsSnapshot.appleExportEnginePin,
              pin.engine == .shadow || pin.engine == .rust else {
            return .legacy
        }

        let identity = AppleExportOperationIdentity(
            requestID: UUID().uuidString.lowercased(),
            sessionID: UUID().uuidString.lowercased(),
            capturedAt: Date(timeIntervalSince1970: 123),
            calendarTimeZoneIdentifier: pin.calendarTimeZoneIdentifier
        )
        let settings = settingsSnapshot.makeAdvancedExportSettings()
        let root = URL(fileURLWithPath: "/__ConnectedMacPlannerProbe__", isDirectory: true)
        let targets = ExportPathPlanner.aggregateOutputTargets(
            vaultURL: root,
            healthSubfolder: settingsSnapshot.healthSubfolder ?? "",
            settings: settings,
            date: healthData.date
        )
        let nativeData = Data(
            (pin.engine == .shadow ? "shadow-native-only" : "native-not-committed").utf8
        )
        let selectedData = pin.engine == .rust
            ? Data("rust-authority-only".utf8)
            : nativeData
        let nativePlan = try makePlan(
            targets: targets,
            data: nativeData,
            identity: identity,
            pin: pin
        )
        let selectedPlan = try makePlan(
            targets: targets,
            data: selectedData,
            identity: identity,
            pin: pin
        )
        let artifacts = zip(targets, selectedPlan.artifacts).map {
            AppleLooseDailyPlannedArtifact(kind: .daily, format: $0.format, artifact: $1)
        }
        return .planned(AppleLooseDailyPlannedOperation(
            authority: pin.engine,
            identity: identity,
            pin: pin,
            nativePlan: nativePlan,
            selectedPlan: selectedPlan,
            artifacts: artifacts
        ))
    }

    private func makePlan(
        targets: [ExportPathPlanner.AggregateOutputTarget],
        data: Data,
        identity: AppleExportOperationIdentity,
        pin: AppleExportEnginePin
    ) throws -> NativeExportArtifactPlan {
        let artifacts = try targets.map { target in
            let digest = NativeExportArtifact.sha256(of: data)
            let mediaType: String = switch target.format {
            case .markdown, .obsidianBases: "text/markdown; charset=utf-8"
            case .json: "application/json"
            case .csv: "text/csv; charset=utf-8"
            }
            return try NativeExportArtifact(
                role: .file,
                id: NativeExportArtifactPlan.artifactID(
                    requestID: identity.requestID,
                    sessionID: identity.sessionID,
                    profile: .appleHealthDataV7,
                    relativePath: target.relativePath,
                    mediaType: mediaType,
                    writeMode: .overwrite,
                    contentSHA256: digest
                ),
                relativePath: target.relativePath,
                mediaType: mediaType,
                writeMode: .overwrite,
                inlineData: data,
                byteCount: UInt64(data.count),
                sha256: digest
            )
        }
        return try NativeExportArtifactPlan(
            artifactPlanVersion: pin.artifactPlanVersion,
            requestID: identity.requestID,
            sessionID: identity.sessionID,
            profile: .appleHealthDataV7,
            artifacts: artifacts,
            totalByteCount: artifacts.reduce(0) { $0 + $1.byteCount },
            pin: pin
        )
    }
}

#endif
