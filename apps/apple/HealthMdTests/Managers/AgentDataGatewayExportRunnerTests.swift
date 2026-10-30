import XCTest
import HealthKit
import Testing
@testable import HealthMd

/// End-to-end and seam tests for `AgentDataGatewayExportRunner`:
/// materialization through the real folder-destination engine into the
/// ephemeral staging root, deterministic artifact classification, and the
/// per-artifact upload outcome surface (a failed upload never blocks the
/// remaining artifacts).
final class AgentDataGatewayExportRunnerTests: XCTestCase {

    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings is an
    // ObservableObject with nested observable properties. Static retention
    // avoids the macOS 26 / Swift 6 deinit crash. See
    // docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []

    private func makeIsolatedDefaults() -> UserDefaults {
        let suite = "AgentDataGatewayExportRunnerTests-\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        return defaults
    }

    @MainActor
    private func makeSettings(
        formats: Set<ExportFormat>
    ) -> AdvancedExportSettings {
        let settings = AdvancedExportSettings(userDefaults: makeIsolatedDefaults())
        settings.exportFormats = formats
        settings.generateRangeSummary = false
        settings.exportTimeZoneOverride = TimeZone(identifier: "UTC")!
        Self.retainedSettings.append(settings)
        return settings
    }

    private func makeDates(_ count: Int) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return (0..<count).compactMap {
            calendar.date(byAdding: .day, value: $0, to: HealthKitFixtures.referenceDate)
        }
    }

    private func makeHealthKitManager(dates: [Date]) throws -> HealthKitManager {
        let store = FakeHealthStore()
        for date in dates {
            try HealthKitFixtures.populateAllCategories(store, date: date)
        }
        return HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
    }

    private func makeDestination() throws -> AgentDataGatewayDestinationSnapshot {
        try XCTUnwrap(
            AgentDataGatewayDestinationSnapshot(endpointURLString: "https://gateway.example.com")
        )
    }

    // MARK: - End-to-end with the real engine + a real loopback gateway

    /// The real folder-destination engine materializes artifacts into the
    /// staging root; the runner uploads each day's JSON document exactly and
    /// byte-identically with a correct v1 manifest.
    @MainActor
    func testRealEngineArtifactsUploadByteIdentically() async throws {
        try await assertRealEngineArtifactsUploadByteIdentically(attribution: .nightBegins)
    }

    @MainActor
    func testRealMorningEngineArtifactsAdvertiseV11OverLoopback() async throws {
        try await assertRealEngineArtifactsUploadByteIdentically(attribution: .morningEnds)
    }

    @MainActor
    private func assertRealEngineArtifactsUploadByteIdentically(attribution: SleepDayAttribution) async throws {
        let gateway = try startGateway(.accept)
        defer { gateway.stop() }
        let dates = makeDates(2)
        let settings = makeSettings(formats: [.json])
        settings.includeGranularData = false
        let healthKitManager = try makeHealthKitManager(dates: dates)
        healthKitManager.setSleepDayAttribution(attribution)
        let expectedVersion = attribution == .morningEnds ? 11 : HealthMdExportSchema.version

        let outcome = await AgentDataGatewayExportRunner.export(
            dates: dates,
            healthKitManager: healthKitManager,
            settings: settings,
            destination: try XCTUnwrap(
                AgentDataGatewayDestinationSnapshot(endpointURLString: gateway.url)
            ),
            client: AgentDataIngestClient(
                maximumAttempts: 2,
                initialRetryDelay: 0.01,
                sleep: { _ in }
            )
        )

        XCTAssertTrue(outcome.export.didCompleteAllRequestedDates, "failed: \(outcome.export.failedDateDetails)")
        XCTAssertEqual(outcome.uploads.eligibleCount, 2)
        XCTAssertTrue(outcome.uploads.didUploadAllEligibleArtifacts)
        XCTAssertTrue(
            outcome.uploads.outcomes.allSatisfy { $0.kindLabel == "Daily export" }
        )
        XCTAssertEqual(
            Set(outcome.uploads.outcomes.map(\.ownerDate)),
            ["2026-03-15", "2026-03-16"]
        )

        // Wire truth: two requests, each carrying one exact daily JSON
        // artifact with a manifest that describes those exact bytes.
        XCTAssertEqual(gateway.capturedRequests.count, 2)
        let manifests = try gateway.capturedRequests.map { request -> [String: Any] in
            try XCTUnwrap(JSONSerialization.jsonObject(with: Data(request.manifestLine.utf8)) as? [String: Any])
        }
        XCTAssertEqual(Set(manifests.map { $0["owner_date"] as? String }), ["2026-03-15", "2026-03-16"])
        for (request, manifest) in zip(gateway.capturedRequests, manifests) {
            XCTAssertEqual(manifest["schema"] as? String, "healthmd.agent_data_ingest")
            XCTAssertEqual(manifest["schema_version"] as? Int, 1)
            XCTAssertEqual(manifest["artifact_kind"] as? String, "health_data_daily")
            XCTAssertEqual(manifest["platform"] as? String, "apple")
            XCTAssertEqual(manifest["artifact_schema"] as? String, HealthMdExportSchema.identifier)
            XCTAssertEqual(manifest["artifact_schema_version"] as? Int, expectedVersion)
            XCTAssertEqual(manifest["physical_format"] as? String, "json")
            XCTAssertEqual(manifest["media_type"] as? String, "application/json")
            XCTAssertEqual((manifest["completeness"] as? [String: Any])?["type"] as? String, "complete")
            XCTAssertNil(manifest["record_count"])

            let bytes = request.artifactBytes
            XCTAssertEqual(manifest["byte_count"] as? Int, bytes.count)
            XCTAssertEqual(
                manifest["sha256"] as? String,
                AgentDataIngestManifest.sha256(of: bytes)
            )
            // The uploaded bytes are the engine's exact daily document:
            // schema-identical with the folder destination's JSON output.
            let document = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
            XCTAssertEqual(document["schema"] as? String, HealthMdExportSchema.identifier)
            XCTAssertEqual(document["schema_version"] as? Int, expectedVersion)
        }
    }

    @MainActor
    func testMorningEngineKeepsWholeSleepAndAcceptedPathsAfterCallerSettingsChange() async throws {
        try await assertAcceptedSleepAndPaths(attribution: .morningEnds, recovered: false, includeMetadata: true)
        try await assertAcceptedSleepAndPaths(attribution: .morningEnds, recovered: false, includeMetadata: false)
    }

    @MainActor
    func testHistoricalGatewayKeepsAcceptedPathsAndAttributionAfterCallerChanges() async throws {
        try await assertAcceptedSleepAndPaths(attribution: .nightBegins, recovered: false, includeMetadata: true)
    }

    @MainActor
    func testRecoveredMorningGatewayKeepsItsProfileAfterPreferenceChange() async throws {
        try await assertAcceptedSleepAndPaths(attribution: .morningEnds, recovered: true, includeMetadata: false)
    }

    @MainActor
    private func assertAcceptedSleepAndPaths(attribution: SleepDayAttribution, recovered: Bool, includeMetadata: Bool) async throws {
        let dates = makeDates(2)
        let configured = makeSettings(formats: [.json, .markdown])
        configured.detailPolicy = .detailedTimeSeries
        configured.summaryOnlyExport = false
        configured.includeMetadata = includeMetadata
        configured.metricSelection.enabledMetrics = ["sleep_total", "sleep_core", "sleep_in_bed", "sleep_bedtime", "sleep_wake"]
        let acceptedZone = try XCTUnwrap(configured.exportTimeZoneOverride)
        let context = AppleSleepCaptureContext(timeZone: acceptedZone, sleepDayAttribution: attribution)
        let settings: AdvancedExportSettings
        if recovered {
            configured.executionSleepCaptureContext = context
            configured.executionExternalProviderCaptureAuthority = .init(connections: [:])
            let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(configured, healthSubfolder: "Health",
                calendarTimeZone: acceptedZone, surface: .localVaultRangeWithoutSideEffects)
            settings = snapshot.makeAdvancedExportSettings()
            Self.retainedSettings.append(settings)
        } else { settings = configured }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = acceptedZone
        let store = FakeHealthStore()
        store.categorySampleResults[HKCategoryTypeIdentifier.sleepAnalysis.rawValue] = dates.flatMap { owner in
            let wake = calendar.startOfDay(for: owner).addingTimeInterval(14 * 3600)
            let start = wake.addingTimeInterval(-16 * 3600)
            return [
                CategorySampleValue(value: HKCategoryValueSleepAnalysis.inBed.rawValue, startDate: start, endDate: wake),
                CategorySampleValue(value: HKCategoryValueSleepAnalysis.asleepCore.rawValue, startDate: start, endDate: wake),
            ]
        }
        let manager = HealthKitManager(store: store, userDefaults: makeIsolatedDefaults())
        manager.setSleepDayAttribution(recovered ? .nightBegins : attribution)
        let baseline = try await manager.fetchHealthData(for: dates[0], detailPolicy: .detailedTimeSeries,
            metricSelection: settings.metricSelection, timeZone: acceptedZone,
            captureContext: context)
        XCTAssertEqual(baseline.sleep.stages.count, attribution == .morningEnds ? 2 : 4)
        var didMutate = false
        var uploaded: [String] = []
        let result = await AgentDataGatewayExportRunner.export(
            dates: dates, healthKitManager: manager, settings: settings, destination: try makeDestination(),
            uploader: { manifest, file, _ in
                do {
                    let bytes = try Data(contentsOf: file)
                    let root = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                    XCTAssertEqual(manifest.artifactSchemaVersion, attribution == .morningEnds ? 11 : HealthMdExportSchema.version)
                    XCTAssertEqual(manifest.sha256, AgentDataIngestManifest.sha256(of: bytes))
                    XCTAssertEqual(Int(manifest.byteCount), bytes.count)
                    let sleep = try XCTUnwrap(root["sleep"] as? [String: Any])
                    let expectedSeconds: Double = attribution == .morningEnds || manifest.ownerDate == "2026-03-15" ? 16 * 3600 : 2 * 3600
                    XCTAssertEqual(sleep["totalDuration"] as? Double, expectedSeconds)
                    XCTAssertEqual(sleep["inBedTime"] as? Double, expectedSeconds)
                    if attribution == .morningEnds {
                        XCTAssertEqual(root["schema_profile"] as? String, "apple-v11")
                        let context = try XCTUnwrap(root["time_context"] as? [String: Any])
                        XCTAssertEqual(context["sleep_day_attribution"] as? String, "morning_ends")
                        XCTAssertEqual(context["calendar_timezone"] as? String, acceptedZone.identifier)
                        XCTAssertEqual((sleep["sleepStages"] as? [[String: Any]])?.count, 2)
                        if let directory = ProcessInfo.processInfo.environment["HEALTHMD_WAKE_DATE_CONSUMER_FIXTURE_DIR"], !directory.isEmpty {
                            let output = URL(fileURLWithPath: directory, isDirectory: true)
                                .appendingPathComponent("apple-v11-gateway-\(includeMetadata)-\(recovered)", isDirectory: true)
                            try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
                            try bytes.write(to: output.appendingPathComponent("\(manifest.ownerDate).json"))
                            try manifest.encodedLine().write(to: output.appendingPathComponent("\(manifest.ownerDate)-manifest.json"))
                        }
                    } else { XCTAssertFalse(String(decoding: bytes, as: UTF8.self).contains("morning_ends")) }
                    uploaded.append(manifest.ownerDate)
                    return AgentDataIngestUploadOutcome(result: .accepted, attempts: 1, byteCount: manifest.byteCount)
                } catch {
                    XCTFail("Synthetic gateway artifact must remain readable: \(error)")
                    return AgentDataIngestUploadOutcome(result: .rejected(.manifestIncomplete), attempts: 1, byteCount: manifest.byteCount)
                }
            },
            onProgress: { progress in
                guard case .materializing = progress, !didMutate else { return }
                didMutate = true
                settings.filenameFormat = "'changed-'yyyy-MM-dd"
                settings.exportTimeZoneOverride = TimeZone(identifier: "Asia/Tokyo")!
                settings.metricSelection.enabledMetrics = ["steps"]
                manager.setSleepDayAttribution(attribution == .morningEnds ? .nightBegins : .morningEnds)
            }
        )
        XCTAssertTrue(didMutate)
        XCTAssertTrue(result.export.didCompleteAllRequestedDates, "\(result.export.failedDateDetails)")
        XCTAssertEqual(result.uploads.eligibleCount, 2)
        XCTAssertTrue(result.uploads.didUploadAllEligibleArtifacts)
        XCTAssertEqual(Set(uploaded), ["2026-03-15", "2026-03-16"])
        XCTAssertGreaterThanOrEqual(result.uploads.ineligibleStagedFileCount, 2)
    }

    // MARK: - Outcome surface through seams

    @MainActor
    func testFailedUploadDoesNotBlockRemainingArtifacts() async throws {
        let dates = makeDates(2)
        let settings = makeSettings(formats: [.json])
        settings.includeGranularData = false
        let healthKitManager = try makeHealthKitManager(dates: dates)

        let destination = try makeDestination()
        var uploadedOwnerDates: [String] = []
        let outcome = await AgentDataGatewayExportRunner.export(
            dates: dates,
            healthKitManager: healthKitManager,
            settings: settings,
            destination: destination,
            materialize: { materializationDates, stagingVault, stagingSettings, _ in
                // Engine double: writes the daily artifacts at the writer's
                // own expected paths inside the staging root, then reports a
                // complete materialization.
                try Self.writeDailyJSONArtifacts(
                    into: try XCTUnwrap(stagingVault.vaultURL),
                    dates: materializationDates,
                    settings: stagingSettings
                )
                return ExportOrchestrator.ExportResult(
                    successCount: materializationDates.count,
                    totalCount: materializationDates.count,
                    failedDateDetails: [],
                    formatsPerDate: 1,
                    looseAggregateFileCount: materializationDates.count,
                    isFileCategoryBreakdownComplete: true,
                    completedDates: materializationDates
                )
            },
            uploader: { manifest, _, _ in
                uploadedOwnerDates.append(manifest.ownerDate)
                // The first artifact is rejected with a fix-and-reupload
                // code; the second must still be attempted.
                if uploadedOwnerDates.count == 1 {
                    return AgentDataIngestUploadOutcome(
                        result: .rejected(.checksumInvalid),
                        attempts: 1,
                        byteCount: manifest.byteCount
                    )
                }
                return AgentDataIngestUploadOutcome(
                    result: .accepted,
                    attempts: 1,
                    byteCount: manifest.byteCount
                )
            }
        )

        // Both artifacts were attempted despite the first failing.
        XCTAssertEqual(uploadedOwnerDates.count, 2)
        XCTAssertEqual(outcome.uploads.acceptedCount, 1)
        XCTAssertEqual(outcome.uploads.rejectedCount, 1)
        XCTAssertFalse(outcome.export.didCompleteAllRequestedDates)
        // The failed day surfaces as a health-free failed-date detail so
        // residual scheduled retries keep the day retryable.
        XCTAssertEqual(outcome.export.failedDateDetails.count, 1)
        XCTAssertEqual(
            outcome.export.failedDateDetails.first?.errorDetails,
            "The Agent Data gateway reported a checksum mismatch for 2026-03-15."
        )
        XCTAssertEqual(outcome.export.successCount, 1)
    }

    @MainActor
    func testProviderSidecarsAreClassifiedAndUploaded() async throws {
        let dates = makeDates(1)
        let settings = makeSettings(formats: [.json])
        settings.includeGranularData = false
        let healthKitManager = try makeHealthKitManager(dates: dates)

        var capturedKinds: [AgentDataIngestArtifactKind] = []
        let outcome = await AgentDataGatewayExportRunner.export(
            dates: dates,
            healthKitManager: healthKitManager,
            settings: settings,
            destination: try makeDestination(),
            materialize: { materializationDates, stagingVault, stagingSettings, _ in
                try Self.writeDailyJSONArtifacts(
                    into: try XCTUnwrap(stagingVault.vaultURL),
                    dates: materializationDates,
                    settings: stagingSettings
                )
                // One provider sidecar in the engine's integrations subtree.
                let sidecarFolder = try XCTUnwrap(stagingVault.vaultURL)
                    .appendingPathComponent("Health/integrations/whoop", isDirectory: true)
                try FileManager.default.createDirectory(
                    at: sidecarFolder,
                    withIntermediateDirectories: true
                )
                try Data("{\"provider\":\"whoop\"}".utf8).write(
                    to: sidecarFolder.appendingPathComponent("2026-03-15.json")
                )
                return ExportOrchestrator.ExportResult(
                    successCount: materializationDates.count,
                    totalCount: materializationDates.count,
                    failedDateDetails: [],
                    formatsPerDate: 1,
                    looseAggregateFileCount: materializationDates.count,
                    isFileCategoryBreakdownComplete: true,
                    completedDates: materializationDates
                )
            },
            uploader: { manifest, _, _ in
                capturedKinds.append(manifest.artifactKind)
                return AgentDataIngestUploadOutcome(
                    result: .accepted,
                    attempts: 1,
                    byteCount: manifest.byteCount
                )
            }
        )

        XCTAssertEqual(
            Set(capturedKinds),
            [.healthDataDaily, .externalProviderDaily]
        )
        XCTAssertEqual(outcome.uploads.eligibleCount, 2)
        XCTAssertTrue(
            outcome.uploads.outcomes.contains {
                $0.kindLabel == "Provider sidecar" && $0.ownerDate == "2026-03-15"
            }
        )
    }

    @MainActor
    func testMarkdownOutputsAreStagedButNeverUploaded() async throws {
        let dates = makeDates(2)
        let settings = makeSettings(formats: [.json, .markdown])
        settings.includeGranularData = false
        let healthKitManager = try makeHealthKitManager(dates: dates)

        let outcome = await AgentDataGatewayExportRunner.export(
            dates: dates,
            healthKitManager: healthKitManager,
            settings: settings,
            destination: try makeDestination(),
            materialize: { materializationDates, stagingVault, stagingSettings, _ in
                try Self.writeDailyJSONArtifacts(
                    into: try XCTUnwrap(stagingVault.vaultURL),
                    dates: materializationDates,
                    settings: stagingSettings
                )
                // Markdown twins at the writer's own expected paths.
                for date in materializationDates {
                    let url = ExportPathPlanner.aggregateFileURL(
                        vaultURL: try XCTUnwrap(stagingVault.vaultURL),
                        healthSubfolder: stagingVault.healthSubfolder,
                        settings: stagingSettings,
                        date: date,
                        format: .markdown
                    )
                    try FileManager.default.createDirectory(
                        at: url.deletingLastPathComponent(),
                        withIntermediateDirectories: true
                    )
                    try Data("# markdown\n".utf8).write(to: url)
                }
                return ExportOrchestrator.ExportResult(
                    successCount: materializationDates.count,
                    totalCount: materializationDates.count,
                    failedDateDetails: [],
                    formatsPerDate: 2,
                    looseAggregateFileCount: materializationDates.count * 2,
                    isFileCategoryBreakdownComplete: true,
                    completedDates: materializationDates
                )
            },
            uploader: { manifest, _, _ in
                AgentDataIngestUploadOutcome(
                    result: .accepted,
                    attempts: 1,
                    byteCount: manifest.byteCount
                )
            }
        )

        // Only the JSON daily documents are eligible; markdown outputs are
        // counted as ineligible and never fabricated into an upload.
        XCTAssertEqual(outcome.uploads.eligibleCount, 2)
        XCTAssertGreaterThanOrEqual(outcome.uploads.ineligibleStagedFileCount, 2)
        XCTAssertTrue(
            outcome.uploads.outcomes.allSatisfy { $0.kindLabel == "Daily export" }
        )
    }

    // MARK: - Preflight gates

    @MainActor
    func testDailyNotesOnlyIsRejectedHealthFree() async throws {
        let dates = makeDates(1)
        let settings = makeSettings(formats: [.json])
        settings.dailyNoteInjection.dailyNotesOnly = true
        settings.dailyNoteInjection.enabled = true
        let healthKitManager = try makeHealthKitManager(dates: dates)

        let outcome = await AgentDataGatewayExportRunner.export(
            dates: dates,
            healthKitManager: healthKitManager,
            settings: settings,
            destination: try makeDestination(),
            uploader: { _, _, _ in
                XCTFail("no upload may happen for a rejected preflight")
                return AgentDataIngestUploadOutcome(
                    result: .uploadFailed(description: "unreachable"),
                    attempts: 0,
                    byteCount: 0
                )
            }
        )

        XCTAssertTrue(outcome.export.isFailure)
        XCTAssertEqual(
            outcome.export.failedDateDetails.first?.errorDetails,
            "Daily Notes Only requires a filesystem destination and cannot export to an Agent Data gateway."
        )
        XCTAssertEqual(outcome.uploads.eligibleCount, 0)
    }

    @MainActor
    func testMissingJSONFormatIsRejectedHealthFree() async throws {
        let dates = makeDates(1)
        let settings = makeSettings(formats: [.markdown])
        let healthKitManager = try makeHealthKitManager(dates: dates)

        let outcome = await AgentDataGatewayExportRunner.export(
            dates: dates,
            healthKitManager: healthKitManager,
            settings: settings,
            destination: try makeDestination(),
            uploader: { _, _, _ in
                XCTFail("no upload may happen for a rejected preflight")
                return AgentDataIngestUploadOutcome(
                    result: .uploadFailed(description: "unreachable"),
                    attempts: 0,
                    byteCount: 0
                )
            }
        )

        XCTAssertTrue(outcome.export.isFailure)
        XCTAssertEqual(
            outcome.export.failedDateDetails.first?.errorDetails,
            "Select the JSON format before exporting to an Agent Data gateway."
        )
    }

    // MARK: - Helpers

    private func startGateway(_ behavior: GatewayBehavior) throws -> LoopbackGateway {
        let gateway = try LoopbackGateway(behavior: behavior)
        try gateway.start()
        return gateway
    }

    /// Writes daily JSON artifacts at the writer's own expected paths using
    /// the engine's path planner truth.
    @MainActor
    private static func writeDailyJSONArtifacts(
        into stagingRoot: URL,
        dates: [Date],
        settings: AdvancedExportSettings
    ) throws {
        for date in dates {
            let url = ExportPathPlanner.aggregateFileURL(
                vaultURL: stagingRoot,
                healthSubfolder: "Health",
                settings: settings,
                date: date,
                format: .json
            )
            try FileManager.default.createDirectory(
                at: url.deletingLastPathComponent(),
                withIntermediateDirectories: true
            )
            let document: [String: Any] = [
                "schema": HealthMdExportSchema.identifier,
                "schema_version": HealthMdExportSchema.version,
                "date": APIExportClient.dayString(
                    from: date,
                    timeZone: settings.exportTimeZoneOverride ?? .current
                ),
            ]
            try JSONSerialization.data(withJSONObject: document, options: [.sortedKeys])
                .write(to: url)
        }
    }
}

@MainActor
struct GatewaySourceAuthorityTests {
    // STATIC RETENTION JUSTIFICATION: Observation teardown workaround documented
    // in docs/testing/lifecycle-audit.md; these objects use only synthetic stores.
    private static var retained: [AnyObject] = []

    @Test(arguments: ["unchanged", "replaced", "empty"])
    func productionGatewayKeepsAcceptedSourceAndSettings(change: String) async throws {
        try #require(ConnectedAppsFeature.isEnabled)
        let suite = "GatewaySourceAuthority-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.json]; settings.generateRangeSummary = false
        settings.archiveExportFiles = false; settings.summaryOnlyExport = false
        settings.includeDataDictionary = false; settings.dailyNoteInjection.enabled = false
        settings.individualTracking.globalEnabled = false; settings.detailPolicy = .summary
        settings.metricSelection.enabledMetrics = ["steps"]
        settings.exportTimeZoneOverride = .gmt
        let store = FakeHealthStore()
        store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 42
        let manager = HealthKitManager(store: store, userDefaults: defaults)
        manager.setSleepDayAttribution(.morningEnds)
        Self.retained += [settings, manager]
        let providers = Provider()
        if change == "empty" { providers.currentID = nil }
        let acceptedID = providers.currentID
        providers.beforeAcceptance = {
            settings.exportFormats = [.csv]
            settings.metricSelection.enabledMetrics = []
            settings.exportTimeZoneOverride = TimeZone(identifier: "Asia/Tokyo")!
            manager.setSleepDayAttribution(.nightBegins)
        }
        let dates = [Date(timeIntervalSince1970: 1_777_766_400), Date(timeIntervalSince1970: 1_777_852_800)]
        var uploads: [AgentDataIngestArtifactKind] = []
        let result = await AgentDataGatewayExportRunner.export(dates: dates, healthKitManager: manager,
            settings: settings,
            destination: try #require(AgentDataGatewayDestinationSnapshot(endpointURLString: "https://synthetic.invalid")),
            externalIntegrations: providers,
            uploader: { manifest, file, _ in
                do {
                let bytes = try Data(contentsOf: file)
                #expect(manifest.sha256 == AgentDataIngestManifest.sha256(of: bytes))
                #expect(!String(decoding: bytes, as: UTF8.self).contains(acceptedID?.uuidString ?? "never-a-grant"))
                if manifest.artifactKind == .healthDataDaily {
                    #expect(manifest.artifactSchemaVersion == 11)
                    let document = try #require(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                    #expect((document["activity"] as? [String: Any])?["steps"] as? Int == 42)
                }
                uploads.append(manifest.artifactKind)
                return AgentDataIngestUploadOutcome(result: .accepted, attempts: 1, byteCount: manifest.byteCount)
                } catch {
                    Issue.record(error)
                    return AgentDataIngestUploadOutcome(result: .rejected(.manifestIncomplete), attempts: 1, byteCount: manifest.byteCount)
                }
            }, onProgress: { _ in
                if change == "replaced" || change == "empty" { providers.currentID = UUID() }
            })
        #expect(result.export.didCompleteAllRequestedDates, "\(result.export.failedDateDetails)")
        #expect(result.uploads.didUploadAllEligibleArtifacts)
        #expect(uploads.filter { $0 == .healthDataDaily }.count == 2)
        #expect(providers.acceptanceCalls == 1)
        #expect(providers.expectedIDs == (change == "empty" ? [] : [acceptedID, acceptedID]))
        #expect(providers.successfulFetches == (change == "unchanged" ? 2 : change == "replaced" ? 1 : 0))
    }

    @Test(arguments: ["empty", "missing", "mismatched"])
    func savedSelectionCannotAdoptCurrentProvider(mode: String) throws {
        let suite = "GatewaySavedAuthority-\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retained.append(settings)
        settings.executionExternalProviderCaptureAuthorityIsFrozen = true
        let providers = Provider()
        if mode == "empty" { settings.executionExternalProviderCaptureAuthority = .init(connections: [:]) }
        if mode == "mismatched" {
            settings.executionExternalProviderCaptureAuthority = .init(connections: ["whoop": UUID()])
            providers.ignoreRestoredAuthority = true
        }
        let context = AppleSleepCaptureContext.resolve(timeZone: .gmt, attribution: .morningEnds)
        if mode == "empty" {
            let capture = try AcceptedExternalProviderFileCapture(settings: settings, context: context, providers: providers)
            #expect(capture.providers == nil)
            #expect(capture.snapshot.externalProviderCaptureAuthority?.connections.isEmpty == true)
        } else {
            #expect(throws: ExternalProviderCaptureAuthority.RecoveryError.self) {
                try AcceptedExternalProviderFileCapture(settings: settings, context: context, providers: providers)
            }
        }
        #expect(providers.acceptanceCalls == 0)
        #expect(providers.expectedIDs.isEmpty)
    }

    @MainActor private final class Provider: ExternalIntegrationDailyRecordProviding {
        var currentID: UUID? = UUID()
        var beforeAcceptance: (() -> Void)?
        var acceptanceCalls = 0
        var expectedIDs: [UUID?] = []
        var successfulFetches = 0
        var ignoreRestoredAuthority = false
        var connectedProviderCount: Int { currentID == nil ? 0 : 1 }
        func forCaptureOperation() -> any ExternalIntegrationDailyRecordProviding {
            acceptanceCalls += 1
            let authority = ExternalProviderCaptureAuthority(connections: currentID == nil ? [:] : ["whoop": currentID])
            beforeAcceptance?()
            return Scope(root: self, authority: authority)
        }
        func forCaptureOperation(authority: ExternalProviderCaptureAuthority) throws -> any ExternalIntegrationDailyRecordProviding {
            Scope(root: self, authority: ignoreRestoredAuthority ? .init(connections: ["whoop": currentID]) : authority)
        }
        func fetchDailyRecords(for date: Date) async -> [ExternalDailyRecord] { [] }
        func fetchDailyRecords(for date: Date, providerIDs: Set<String>) async -> [ExternalDailyRecord] { [] }
    }
    @MainActor private final class Scope: ExternalIntegrationDailyRecordProviding {
        let root: Provider
        let authority: ExternalProviderCaptureAuthority
        init(root: Provider, authority: ExternalProviderCaptureAuthority) { self.root = root; self.authority = authority }
        var captureAuthority: ExternalProviderCaptureAuthority? { authority }
        var connectedProviderCount: Int { authority.connections.count }
        func forCaptureOperation(authority: ExternalProviderCaptureAuthority) throws -> any ExternalIntegrationDailyRecordProviding {
            guard authority == self.authority else { throw ExternalProviderCaptureAuthority.RecoveryError.unavailable }
            return self
        }
        func fetchDailyRecords(for date: Date) async -> [ExternalDailyRecord] {
            let expected = authority.connections["whoop"] ?? nil
            root.expectedIDs.append(expected)
            let available = expected != nil && expected == root.currentID
            if available { root.successfulFetches += 1 }
            return [.init(provider: .whoop, date: APIExportClient.dayString(from: date, timeZone: .gmt),
                payloads: available ? [.init(name: "cycles", endpoint: "https://synthetic.invalid", statusCode: 200,
                    data: .object(["synthetic": .string("accepted-source")]))] : [],
                warnings: available ? [] : ["Unavailable saved connection"])]
        }
        func fetchDailyRecords(for date: Date, providerIDs: Set<String>) async -> [ExternalDailyRecord] {
            await fetchDailyRecords(for: date)
        }
    }
}
