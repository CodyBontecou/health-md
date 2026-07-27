import Foundation
import HealthMdCoreRust
import XCTest
@testable import HealthMd

@MainActor
final class APIEndpointExportEngineTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings owns nested observation state that
    // is unsafe during test teardown on some macOS runtimes. See docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testShadowCapturesEachOwnerOnceAndCompletesEveryPlanBeforeUpload() async throws {
        let dates = days(count: 8)
        let settings = makeSettings()
        let events = APIEngineEventRecorder()
        var captureCounts: [Date: Int] = [:]
        var uploadBodies: [Data] = []

        let operation = try await preparedOperation(
            mode: .shadow,
            dates: dates,
            settings: settings,
            maxBatchDaySpan: 3,
            fetchHealthData: { date, _, _ in
                captureCounts[date, default: 0] += 1
                await events.record("capture")
                return self.record(date: date, steps: 1_000)
            },
            coreExecutor: APIRecordingCoreExecutor(events: events)
        )

        XCTAssertEqual(captureCounts.count, dates.count)
        XCTAssertTrue(captureCounts.values.allSatisfy { $0 == 1 })
        XCTAssertEqual(operation.batches.map(\.requestedDates.count), [3, 3, 2])
        XCTAssertEqual(operation.nativePlan, operation.rustPlan)
        XCTAssertEqual(operation.selectedPlan, operation.nativePlan)
        XCTAssertEqual(Set(operation.batches.map(\.exportedAt)), [fixedExportedAt])
        let eventsBeforeCommit = await events.values()
        XCTAssertFalse(eventsBeforeCommit.contains("upload"))

        _ = await APIEndpointExportRunner.commitPreparedOperation(operation) { batch, _ in
            await events.record("upload")
            uploadBodies.append(batch.body)
            return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
        }

        XCTAssertEqual(uploadBodies, operation.nativePlan.artifacts.map(\.inlineData))
        let values = await events.values()
        let firstUpload = try XCTUnwrap(values.firstIndex(of: "upload"))
        XCTAssertFalse(values[firstUpload...].contains("capture"))
        XCTAssertFalse(values[firstUpload...].contains("semantic"))
        XCTAssertFalse(values[firstUpload...].contains("render"))
    }

    func testExactV1NativeAndRustFixtureIncludesFailureOnlyDayAndFullRange() async throws {
        let dates = days(count: 2)
        let settings = makeSettings()
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: dates,
            settings: settings,
            connectedAppsEnabled: false,
            fetchHealthData: { date, _, _ in
                if date == dates[1] {
                    return HealthData(
                        date: date,
                        timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC")
                    )
                }
                return self.record(date: date, steps: 1_234)
            }
        )

        let rustPlan = try XCTUnwrap(operation.rustPlan)
        XCTAssertEqual(rustPlan, operation.nativePlan)
        XCTAssertEqual(operation.batches.count, 1)
        let batch = try XCTUnwrap(operation.batches.first)
        let frozenSettings = operation.settingsSnapshot.makeAdvancedExportSettings()
        let expected = try APIExportClient.makePayload(
            records: batch.records,
            failedDateDetails: batch.failedDateDetails,
            settings: frozenSettings,
            dateRangeStart: dates[0],
            dateRangeEnd: dates[1],
            exportedAt: fixedExportedAt,
            connectedAppsEnabled: false
        )
        XCTAssertEqual(batch.body, expected)

        let envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: batch.body) as? [String: Any]
        )
        XCTAssertEqual(envelope["schema_version"] as? Int, 1)
        XCTAssertEqual(envelope["record_count"] as? Int, 1)
        XCTAssertEqual((envelope["failed_date_details"] as? [Any])?.count, 1)
        XCTAssertEqual((envelope["date_range"] as? [String: String]), [
            "start": "2026-07-01",
            "end": "2026-07-02",
        ])
    }

    func testExactV2NativeAndRustFixtureIncludesExternalJSONAndUnescapedSlashes() async throws {
        let dates = days(count: 2)
        let settings = makeSettings()
        let external = externalRecord(ownerDate: "2026-07-01")
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: dates,
            settings: settings,
            connectedAppsEnabled: true,
            fetchHealthData: { date, _, _ in
                if date == dates[1] {
                    return HealthData(
                        date: date,
                        timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC")
                    )
                }
                return self.record(date: date, steps: 9_876)
            },
            fetchExternalDailyRecords: { date in
                date == dates[0] ? [external] : []
            }
        )

        XCTAssertEqual(operation.nativePlan, operation.rustPlan)
        let batch = try XCTUnwrap(operation.batches.first)
        let frozenSettings = operation.settingsSnapshot.makeAdvancedExportSettings()
        let expected = try APIExportClient.makePayload(
            records: batch.records,
            failedDateDetails: batch.failedDateDetails,
            externalRecords: batch.externalRecords,
            settings: frozenSettings,
            dateRangeStart: dates[0],
            dateRangeEnd: dates[1],
            exportedAt: fixedExportedAt,
            connectedAppsEnabled: true
        )
        XCTAssertEqual(batch.body, expected)
        let text = String(decoding: batch.body, as: UTF8.self)
        XCTAssertTrue(text.contains("https://api.example.com/provider/path"))
        XCTAssertFalse(text.contains(#"https:\/\/api.example.com"#))

        let envelope = try XCTUnwrap(
            JSONSerialization.jsonObject(with: batch.body) as? [String: Any]
        )
        XCTAssertEqual(envelope["schema_version"] as? Int, 2)
        XCTAssertEqual(envelope["external_record_count"] as? Int, 1)
        XCTAssertEqual((envelope["failed_date_details"] as? [Any])?.count, 1)
    }

    func testShadowCommitsNativeOnlyAndNeverCommitsMismatchingRustCandidate() async throws {
        let diagnostics = APIEngineDiagnosticRecorder()
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: days(count: 1),
            settings: makeSettings(),
            fetchHealthData: { date, _, _ in self.record(date: date, steps: 42) },
            coreExecutor: APIMutatingCoreExecutor(),
            diagnosticSink: { await diagnostics.record($0) }
        )
        let rustPlan = try XCTUnwrap(operation.rustPlan)
        XCTAssertNotEqual(operation.nativePlan, rustPlan)
        XCTAssertEqual(operation.selectedPlan, operation.nativePlan)

        var uploaded: [Data] = []
        _ = await APIEndpointExportRunner.commitPreparedOperation(operation) { batch, _ in
            uploaded.append(batch.body)
            return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
        }
        XCTAssertEqual(uploaded, operation.nativePlan.artifacts.map(\.inlineData))
        XCTAssertFalse(uploaded.contains(rustPlan.artifacts[0].inlineData))

        let recorded = await diagnostics.values()
        XCTAssertTrue(recorded.contains {
            if case .planMismatch = $0 { return true }
            return false
        })
    }

    func testUnsupportedRustAPIFallsBackBeforeCaptureAndPersistedPinFailsClosed() async throws {
        let dates = days(count: 2)
        var captures = 0
        let resolver = AppleExportEnginePolicyResolver(
            injectedOverride: "rust",
            userDefaults: nil,
            environment: [:]
        )
        let newResolution = try await APIEndpointExportRunner.prepare(
            dates: dates,
            settings: makeSettings(),
            destination: destination,
            calendarTimeZone: TimeZone(identifier: "UTC")!,
            connectedAppsEnabled: false,
            fetchHealthData: { date, _, _ in
                captures += 1
                return self.record(date: date, steps: 77)
            },
            policyResolver: resolver,
            coreExecutor: APIFailingCoreExecutor(sensitiveValue: "must-not-load")
        )
        guard case .legacy = newResolution else {
            return XCTFail("Unsupported new Rust API work must resolve wholly to legacy")
        }
        XCTAssertEqual(captures, 0)

        let pin = try makeSyntheticAppleExportEnginePin(
            engine: .rust,
            calendarTimeZoneIdentifier: "UTC"
        )
        let pinnedSettings = ExportSettingsSnapshot.from(
            makeSettings(),
            appleExportEnginePin: pin,
            appleExportEngineAuthorityIsFrozen: true,
            calendarTimeZoneIdentifier: "UTC"
        ).makeAdvancedExportSettings()
        do {
            _ = try await APIEndpointExportRunner.prepare(
                dates: dates,
                settings: pinnedSettings,
                destination: destination,
                calendarTimeZone: TimeZone(identifier: "UTC")!,
                connectedAppsEnabled: false,
                fetchHealthData: { date, _, _ in
                    captures += 1
                    return self.record(date: date, steps: 77)
                },
                policyResolver: resolver,
                coreExecutor: APIFailingCoreExecutor(sensitiveValue: "must-not-load")
            )
            XCTFail("Persisted unsupported Rust API authority must fail closed")
        } catch {
            XCTAssertEqual(error as? APIEndpointExportRunner.EngineError, .rustPlanningFailed)
        }
        XCTAssertEqual(captures, 0)
    }

    func testEncodedLimitPlansSingletonsIncludingFailureOnlyDays() async throws {
        let dates = days(count: 3)
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: dates,
            settings: makeSettings(),
            maxBatchPayloadBytes: 1,
            fetchHealthData: { date, _, _ in
                if date == dates[1] {
                    return HealthData(
                        date: date,
                        timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC")
                    )
                }
                return self.record(date: date, steps: 500)
            }
        )

        XCTAssertEqual(operation.nativePlan, operation.rustPlan)
        XCTAssertEqual(operation.batches.map(\.requestedDates.count), [1, 1, 1])
        XCTAssertEqual(operation.batches.map(\.records.count), [1, 0, 1])
        XCTAssertTrue(operation.batches.allSatisfy { $0.body.count > 1 })
    }

    func testPreparedRetryReusesExactBodiesWithoutCaptureOrRerender() async throws {
        let events = APIEngineEventRecorder()
        var captures = 0
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: days(count: 2),
            settings: makeSettings(),
            maxBatchDaySpan: 1,
            fetchHealthData: { date, _, _ in
                captures += 1
                return self.record(date: date, steps: 321)
            },
            coreExecutor: APIRecordingCoreExecutor(events: events)
        )
        var firstAttempt: [Data] = []
        let firstResult = await APIEndpointExportRunner.commitPreparedOperation(operation) { batch, _ in
            firstAttempt.append(batch.body)
            throw APIExportClientError.serverRejected(statusCode: 503, body: "private")
        }
        XCTAssertEqual(firstResult.successCount, 0)

        var retry: [Data] = []
        let retryResult = await APIEndpointExportRunner.commitPreparedOperation(operation) { batch, _ in
            retry.append(batch.body)
            return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
        }
        XCTAssertEqual(retryResult.successCount, 2)
        XCTAssertEqual(firstAttempt[0], retry[0])
        XCTAssertEqual(retry, operation.selectedPlan.artifacts.map(\.inlineData))
        XCTAssertEqual(captures, 2)
        let recordedEvents = await events.values()
        XCTAssertEqual(recordedEvents.filter { $0 == "semantic" }.count, 1)
        XCTAssertEqual(recordedEvents.filter { $0 == "render" }.count, 1)
    }

    func testCommitBarrierLocksBeforeFirstUploadAndFailureCannotFallback() async throws {
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: days(count: 1),
            settings: makeSettings(),
            fetchHealthData: { date, _, _ in self.record(date: date, steps: 808) },
            coreExecutor: APIMutatingCoreExecutor()
        )
        let barrier = ExportCommitBarrier()
        var bodies: [Data] = []
        let result = await APIEndpointExportRunner.commitPreparedOperation(
            operation,
            upload: { batch, _ in
                let stateDuringUpload = await barrier.state
                XCTAssertEqual(stateDuringUpload, .committing)
                bodies.append(batch.body)
                throw APIExportClientError.serverRejected(statusCode: 500, body: "private")
            },
            barrier: barrier
        )

        let finalBarrierState = await barrier.state
        XCTAssertEqual(finalBarrierState, .failed)
        XCTAssertEqual(bodies, operation.selectedPlan.artifacts.map(\.inlineData))
        XCTAssertEqual(bodies, operation.nativePlan.artifacts.map(\.inlineData))
        XCTAssertNotEqual(bodies, try XCTUnwrap(operation.rustPlan).artifacts.map(\.inlineData))
        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.failedDateDetails.first?.reason, .fileWriteError)
    }

    func testShadowFailureDiagnosticIsTypedAndHealthFree() async throws {
        let sensitive = "steps=654321;2026-07-01;https://private.example/path;Bearer secret"
        let diagnostics = APIEngineDiagnosticRecorder()
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: days(count: 1),
            settings: makeSettings(),
            fetchHealthData: { date, _, _ in self.record(date: date, steps: 654_321) },
            coreExecutor: APIFailingCoreExecutor(sensitiveValue: sensitive),
            diagnosticSink: { await diagnostics.record($0) }
        )

        XCTAssertEqual(operation.selectedPlan, operation.nativePlan)
        XCTAssertNil(operation.rustPlan)
        let recorded = await diagnostics.values()
        XCTAssertEqual(recorded.count, 1)
        guard case .rustRenderFailed(let diagnostic) = try XCTUnwrap(recorded.first) else {
            return XCTFail("Expected typed Rust failure")
        }
        XCTAssertEqual(diagnostic.kind, .rustRenderFailed)
        let description = String(describing: recorded)
        for forbidden in ["654321", "2026-07-01", "private.example", "Bearer", "secret"] {
            XCTAssertFalse(description.contains(forbidden))
        }
    }

    func testSettingsTimezoneClockAndDestinationAreFrozenOnce() async throws {
        let dates = days(count: 2)
        let settings = makeSettings()
        let originalDestination = destination
        var seenSelections: [Set<String>] = []
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: dates,
            settings: settings,
            fetchHealthData: { date, _, selection in
                seenSelections.append(selection.enabledMetrics)
                if date == dates[0] {
                    settings.metricSelection.enabledMetrics = []
                    settings.exportTimeZoneOverride = TimeZone(identifier: "America/New_York")
                }
                return self.record(date: date, steps: 100)
            }
        )

        XCTAssertEqual(seenSelections, [Set(["steps"]), Set(["steps"])])
        XCTAssertEqual(operation.destination, originalDestination)
        XCTAssertEqual(operation.pin.calendarTimeZoneIdentifier, "UTC")
        XCTAssertEqual(operation.settingsSnapshot.calendarTimeZoneIdentifier, "UTC")
        XCTAssertEqual(Set(operation.batches.map(\.exportedAt)), [fixedExportedAt])
    }

    func testFrozenLegacySnapshotDoesNotInheritCurrentRustDefaultOrCapture() async throws {
        let frozenLegacy = ExportSettingsSnapshot.from(
            makeSettings(),
            appleExportEngineAuthorityIsFrozen: true,
            calendarTimeZoneIdentifier: "UTC"
        ).makeAdvancedExportSettings()
        var captureCount = 0

        let resolution = try await APIEndpointExportRunner.prepare(
            dates: days(count: 1),
            settings: frozenLegacy,
            destination: destination,
            calendarTimeZone: TimeZone(identifier: "UTC")!,
            connectedAppsEnabled: false,
            fetchHealthData: { date, _, _ in
                captureCount += 1
                return self.record(date: date, steps: 10)
            },
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "rust",
                userDefaults: nil,
                environment: [:]
            ),
            coreExecutor: APIFailingCoreExecutor(sensitiveValue: "must-not-load")
        )

        guard case .legacy = resolution else {
            return XCTFail("Frozen nil authority must remain legacy")
        }
        XCTAssertEqual(captureCount, 0)
    }

    func testPreparedPreviewReusesCapturedRecordsAndExactAuthoritativeBodySizes() async throws {
        let dates = days(count: 3)
        let records = dates.enumerated().map { index, date in
            record(date: date, steps: 1_000 + index)
        }
        var externalFetches: [Date] = []
        let preparedPreview = try await APIEndpointExportRunner.preparePreview(
            records: Array(records.reversed()),
            settings: makeSettings(),
            destination: destination,
            calendarTimeZone: TimeZone(identifier: "UTC")!,
            connectedAppsEnabled: true,
            fetchExternalDailyRecords: { date in
                externalFetches.append(date)
                return date == dates[0]
                    ? [self.externalRecord(ownerDate: "2026-07-01")]
                    : []
            },
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "shadow",
                userDefaults: nil,
                environment: [:]
            ),
            identitySource: identitySource
        )
        let operation = try XCTUnwrap(preparedPreview)

        XCTAssertEqual(operation.authority, ExportEngineMode.shadow)
        XCTAssertEqual(operation.normalizedDates, dates)
        XCTAssertEqual(externalFetches, dates)
        XCTAssertEqual(operation.selectedPlan, operation.nativePlan)
        XCTAssertEqual(operation.selectedPlan, try XCTUnwrap(operation.rustPlan))
        let samples = ExportPreviewView.apiPayloadSizeSamples(operation)
        XCTAssertEqual(samples.count, dates.count)
        XCTAssertEqual(
            samples.reduce(0) { $0 + $1.aggregateByteCount },
            operation.batches.reduce(0) { $0 + $1.body.count }
        )
    }

    func testPreparedPreviewExplicitLegacyDoesNotFetchProvidersOrLoadCore() async throws {
        let settings = ExportSettingsSnapshot.from(
            makeSettings(),
            appleExportEngineAuthorityIsFrozen: true,
            calendarTimeZoneIdentifier: "UTC"
        ).makeAdvancedExportSettings()
        var externalFetchCount = 0
        let operation = try await APIEndpointExportRunner.preparePreview(
            records: [record(date: days(count: 1)[0], steps: 10)],
            settings: settings,
            destination: destination,
            calendarTimeZone: TimeZone(identifier: "UTC")!,
            connectedAppsEnabled: true,
            fetchExternalDailyRecords: { _ in
                externalFetchCount += 1
                return []
            },
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "rust",
                userDefaults: nil,
                environment: [:]
            ),
            coreExecutor: APIFailingCoreExecutor(sensitiveValue: "must-not-load")
        )

        XCTAssertNil(operation)
        XCTAssertEqual(externalFetchCount, 0)
    }

    func testPreparePathPerformsNoUploadAndAllEmptyPlanRemainsDestinationFree() async throws {
        let dates = days(count: 2)
        let operation = try await preparedOperation(
            mode: .shadow,
            dates: dates,
            settings: makeSettings(),
            fetchHealthData: { date, _, _ in
                HealthData(
                    date: date,
                    timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC")
                )
            }
        )
        XCTAssertEqual(operation.nativePlan, operation.rustPlan)
        XCTAssertEqual(operation.batches.count, 1)
        XCTAssertTrue(operation.batches[0].records.isEmpty)

        var uploadCount = 0
        let result = await APIEndpointExportRunner.commitPreparedOperation(operation) { _, _ in
            uploadCount += 1
            return APIExportUploadResult(statusCode: 202, responseBodyPreview: nil)
        }
        XCTAssertEqual(uploadCount, 0)
        XCTAssertEqual(result.successCount, 0)
        XCTAssertEqual(result.failedDateDetails.count, 2)
    }

    private var destination: APIExportDestinationSnapshot {
        APIExportDestinationSnapshot(
            endpointURL: URL(string: "https://api.example.com/healthmd")!,
            authorizationHeaderValue: "Bearer frozen-token",
            displayName: "api.example.com",
            redactedEndpointDescription: "https://api.example.com/healthmd"
        )
    }

    private var fixedExportedAt: Date {
        Date(timeIntervalSince1970: 1_751_328_000.125)
    }

    private var identitySource: AppleExportOperationIdentitySource {
        AppleExportOperationIdentitySource(
            makeRequestID: { "api-m6-request" },
            makeSessionID: { "api-m6-session" },
            now: { Date(timeIntervalSince1970: 1_751_328_000.125) }
        )
    }

    private func preparedOperation(
        mode: ExportEngineMode,
        dates: [Date],
        settings: AdvancedExportSettings,
        connectedAppsEnabled: Bool = false,
        maxBatchDaySpan: Int = APIEndpointExportRunner.defaultMaxBatchDaySpan,
        maxBatchPayloadBytes: Int = APIEndpointExportRunner.defaultMaxBatchPayloadBytes,
        fetchHealthData: @escaping APIEndpointExportRunner.HealthDataFetcher,
        fetchExternalDailyRecords: APIEndpointExportRunner.ExternalDailyRecordFetcher? = nil,
        coreExecutor: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(),
        diagnosticSink: @escaping APIEndpointExportRunner.EngineDiagnosticSink = { _ in }
    ) async throws -> APIEndpointExportRunner.PreparedOperation {
        let resolution = try await APIEndpointExportRunner.prepare(
            dates: dates,
            settings: settings,
            destination: destination,
            calendarTimeZone: TimeZone(identifier: "UTC")!,
            connectedAppsEnabled: connectedAppsEnabled,
            fetchHealthData: fetchHealthData,
            fetchExternalDailyRecords: fetchExternalDailyRecords,
            maxBatchDaySpan: maxBatchDaySpan,
            maxBatchPayloadBytes: maxBatchPayloadBytes,
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: mode.rawValue,
                userDefaults: nil,
                environment: [:]
            ),
            coreExecutor: coreExecutor,
            identitySource: identitySource,
            comparisonOptions: NativeExportComparisonOptions(
                includeFirstDifferingByteOffset: false
            ),
            diagnosticSink: diagnosticSink
        )
        guard case .prepared(let operation) = resolution else {
            throw XCTSkip("Internal engine override is unavailable")
        }
        return operation
    }

    private func makeSettings() -> AdvancedExportSettings {
        let suite = "APIEndpointExportEngineTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = [.json]
        settings.includeGranularData = false
        settings.metricSelection.enabledMetrics = ["steps"]
        settings.exportTimeZoneOverride = TimeZone(identifier: "UTC")
        Self.retainedSettings.append(settings)
        return settings
    }

    private func days(count: Int) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 7, day: 1))!
        return (0..<count).map { calendar.date(byAdding: .day, value: $0, to: start)! }
    }

    private func record(date: Date, steps: Int) -> HealthData {
        HealthData(
            date: date,
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "UTC"),
            activity: ActivityData(steps: steps)
        )
    }

    private func externalRecord(ownerDate: String) -> ExternalDailyRecord {
        ExternalDailyRecord(
            provider: .whoop,
            date: ownerDate,
            payloads: [ExternalProviderPayload(
                name: "fixture",
                endpoint: "https://api.example.com/provider/path",
                statusCode: 200,
                data: .object([
                    "source_url": .string("https://api.example.com/provider/path"),
                    "records": .array([.object(["id": .number(1)])]),
                ])
            )]
        )
    }
}

private actor APIEngineDiagnosticRecorder {
    private var diagnostics: [ShadowExportDiagnostic] = []
    func record(_ diagnostic: ShadowExportDiagnostic) { diagnostics.append(diagnostic) }
    func values() -> [ShadowExportDiagnostic] { diagnostics }
}

private actor APIEngineEventRecorder {
    private var events: [String] = []
    func record(_ event: String) { events.append(event) }
    func values() -> [String] { events }
}

nonisolated private struct APIRecordingCoreExecutor: AppleLooseDailyCoreExecuting, Sendable {
    let events: APIEngineEventRecorder
    private let base = SystemAppleLooseDailyCoreExecutor()

    func loadContext() async throws -> AppleLooseDailyCoreContext {
        await events.record("context")
        return try await base.loadContext()
    }

    func processSemantic(configuration: Data, batches: [Data]) async throws -> Data {
        await events.record("semantic")
        return try await base.processSemantic(configuration: configuration, batches: batches)
    }

    func render(
        configuration: Data,
        semanticResult: Data,
        batches: [Data]
    ) async throws -> CoreArtifactPlan {
        await events.record("render")
        return try await base.render(
            configuration: configuration,
            semanticResult: semanticResult,
            batches: batches
        )
    }
}

nonisolated private struct APIMutatingCoreExecutor: AppleLooseDailyCoreExecuting, Sendable {
    private let base = SystemAppleLooseDailyCoreExecutor()

    func loadContext() async throws -> AppleLooseDailyCoreContext {
        try await base.loadContext()
    }

    func processSemantic(configuration: Data, batches: [Data]) async throws -> Data {
        try await base.processSemantic(configuration: configuration, batches: batches)
    }

    func render(
        configuration: Data,
        semanticResult: Data,
        batches: [Data]
    ) async throws -> CoreArtifactPlan {
        let plan = try await base.render(
            configuration: configuration,
            semanticResult: semanticResult,
            batches: batches
        )
        guard let changedIndex = plan.items.firstIndex(where: { $0.writeMode == .apiPost }) else {
            return plan
        }
        let first = plan.items[changedIndex]
        let changed = first.content + Data(" ".utf8)
        let digest = NativeExportArtifact.sha256(of: changed)
        let replacement = CoreArtifactPlanItem(
            artifactId: NativeExportArtifactPlan.artifactID(
                requestID: plan.requestId,
                sessionID: plan.sessionId,
                profile: plan.profile,
                relativePath: first.relativePath,
                mediaType: first.mediaType,
                writeMode: first.writeMode,
                contentSHA256: digest
            ),
            relativePath: first.relativePath,
            mediaType: first.mediaType,
            writeMode: first.writeMode,
            content: changed,
            byteCount: UInt64(changed.count),
            sha256: digest
        )
        var items = plan.items
        items[changedIndex] = replacement
        return CoreArtifactPlan(
            schema: plan.schema,
            artifactPlanVersion: plan.artifactPlanVersion,
            requestId: plan.requestId,
            sessionId: plan.sessionId,
            profile: plan.profile,
            items: items,
            totalByteCount: plan.totalByteCount + 1
        )
    }
}

nonisolated private struct APIEngineSensitiveError: Error, Sendable {
    let value: String
}

nonisolated private struct APIFailingCoreExecutor: AppleLooseDailyCoreExecuting, Sendable {
    let sensitiveValue: String
    private let base = SystemAppleLooseDailyCoreExecutor()

    func loadContext() async throws -> AppleLooseDailyCoreContext {
        try await base.loadContext()
    }

    func processSemantic(configuration: Data, batches: [Data]) async throws -> Data {
        throw APIEngineSensitiveError(value: sensitiveValue)
    }

    func render(
        configuration: Data,
        semanticResult: Data,
        batches: [Data]
    ) async throws -> CoreArtifactPlan {
        throw APIEngineSensitiveError(value: sensitiveValue)
    }
}
