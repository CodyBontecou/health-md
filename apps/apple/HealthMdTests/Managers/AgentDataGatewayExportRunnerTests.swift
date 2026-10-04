import XCTest
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
        let gateway = try startGateway(.accept)
        defer { gateway.stop() }
        let dates = makeDates(2)
        let settings = makeSettings(formats: [.json])
        settings.includeGranularData = false
        let healthKitManager = try makeHealthKitManager(dates: dates)

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
            XCTAssertEqual(manifest["artifact_schema_version"] as? Int, HealthMdExportSchema.version)
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
            XCTAssertEqual(document["schema_version"] as? Int, HealthMdExportSchema.version)
        }
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
