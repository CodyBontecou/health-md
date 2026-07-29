import Foundation
import HealthMdCoreRust
import XCTest
@testable import HealthMd

@MainActor
final class AppleLooseDailyExportPlannerTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: VaultManager and AdvancedExportSettings own nested
    // observation state that is unsafe during test teardown on some macOS runtimes.
    // See docs/testing/lifecycle-audit.md.
    private static var retainedSettings: [AdvancedExportSettings] = []
    private static var retainedManagers: [VaultManager] = []

    func testConcreteShadowPlanAndAsyncPreviewAreTheExactNativeOraclePlan() async throws {
        let diagnostics = M6DiagnosticRecorder()
        let planner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "shadow",
                userDefaults: nil,
                environment: [:]
            ),
            identitySource: fixedIdentitySource,
            comparisonOptions: NativeExportComparisonOptions(
                includeFirstDifferingByteOffset: true
            ),
            diagnosticSink: { await diagnostics.record($0) }
        )
        let settings = makeSimpleSettings(formats: Set(ExportFormat.allCases))
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            appleExportEngineAuthorityIsFrozen: false,
            calendarTimeZoneIdentifier: "UTC"
        )

        let direct = try await planner.plan(
            healthData: ExportFixtures.partialDay,
            settingsSnapshot: snapshot,
            surface: .localVaultWithoutSideEffects
        )
        let operation = try unwrapPlanned(direct)
        XCTAssertEqual(operation.authority, .shadow)
        let nativePlan = try XCTUnwrap(operation.nativePlan)
        XCTAssertEqual(operation.selectedPlan, nativePlan)
        XCTAssertEqual(operation.pin.engine, .shadow)
        XCTAssertEqual(operation.pin.calendarTimeZoneIdentifier, "UTC")
        XCTAssertEqual(operation.identity.requestID, "m6-request")
        XCTAssertEqual(operation.identity.sessionID, "m6-session")
        XCTAssertEqual(operation.identity.capturedAt, Date(timeIntervalSince1970: 123))
        let directDiagnostics = await diagnostics.values()
        XCTAssertEqual(directDiagnostics.count, 1)
        guard case .comparisonCompleted(let directComparison) = directDiagnostics.first else {
            return XCTFail("Expected one exact shadow comparison event")
        }
        XCTAssertTrue(directComparison.matches)
        XCTAssertEqual(directComparison.mismatchCount, 0)

        var connectedSnapshot = snapshot
        connectedSnapshot.appleExportEnginePin = operation.pin
        let connected = try unwrapPlanned(try await planner.plan(
            healthData: ExportFixtures.partialDay,
            settingsSnapshot: connectedSnapshot,
            surface: .connectedReceivedFilesWithoutSideEffects
        ))
        XCTAssertEqual(connected.authority, .shadow)
        XCTAssertEqual(connected.selectedPlan, try XCTUnwrap(connected.nativePlan))
        XCTAssertEqual(connected.pin, operation.pin)

        let optionalPreview = try await AppleLooseDailyExportPreviewPlanner.artifacts(
            healthData: ExportFixtures.partialDay,
            settingsSnapshot: snapshot,
            planner: planner
        )
        let preview = try XCTUnwrap(optionalPreview)
        XCTAssertEqual(
            preview.map(\.relativePath),
            operation.artifacts.map(\.artifact.relativePath)
        )
        XCTAssertEqual(
            preview.map(\.data),
            nativePlan.artifacts.map(\.inlineData)
        )
    }

    func testConcreteShadowRangeUsesOneIdentityAndOneCompleteExactPlan() async throws {
        let planner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "shadow",
                userDefaults: nil,
                environment: [:]
            ),
            identitySource: fixedIdentitySource
        )
        let settings = makeSimpleSettings(formats: Set(ExportFormat.allCases))
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            appleExportEngineAuthorityIsFrozen: false,
            calendarTimeZoneIdentifier: "UTC"
        )
        let first = ExportFixtures.partialDay
        let secondDate = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: first.date)
        )
        var second = HealthData(date: secondDate, timeContext: ExportFixtures.timeContext)
        second.sleep = first.sleep
        second.activity = first.activity

        let operation = try unwrapPlanned(try await planner.planRange(
            healthData: [second, first],
            settingsSnapshot: snapshot,
            surface: .localVaultWithoutSideEffects
        ))

        XCTAssertEqual(operation.authority, .shadow)
        XCTAssertEqual(operation.identity.requestID, "m6-request")
        XCTAssertEqual(operation.identity.sessionID, "m6-session")
        XCTAssertEqual(operation.artifacts.count, 8)
        XCTAssertEqual(operation.selectedPlan, try XCTUnwrap(operation.nativePlan))
        XCTAssertEqual(
            Set(operation.artifacts.map { String($0.artifact.relativePath.prefix(17)) }),
            Set(["Health/2026-03-15", "Health/2026-03-16"])
        )
    }

    func testConcreteShadowRangeIncludesWeeklyRollupsInTheSameExactPlan() async throws {
        let planner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "shadow",
                userDefaults: nil,
                environment: [:]
            ),
            identitySource: fixedIdentitySource
        )
        let settings = makeSimpleSettings(formats: Set(ExportFormat.allCases))
        settings.generateWeeklyRollups = true
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            appleExportEngineAuthorityIsFrozen: false,
            calendarTimeZoneIdentifier: "UTC"
        )

        let first = ExportFixtures.partialDay
        let secondDate = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: first.date)
        )
        var second = HealthData(date: secondDate, timeContext: ExportFixtures.timeContext)
        second.sleep = first.sleep
        second.activity = first.activity
        let operation = try unwrapPlanned(try await planner.planRange(
            healthData: [first, second],
            dailyOutputOwnerDates: ["2026-03-15"],
            settingsSnapshot: snapshot,
            surface: .localVaultRangeWithoutSideEffects
        ))

        XCTAssertEqual(operation.artifacts.count, 12)
        XCTAssertEqual(operation.selectedPlan, try XCTUnwrap(operation.nativePlan))
        XCTAssertEqual(operation.artifacts.count { $0.artifact.relativePath.contains("/Rollups/") }, 8)
        XCTAssertFalse(operation.artifacts.contains {
            $0.artifact.relativePath.hasPrefix("Health/2026-03-16.")
        })
    }

    func testShadowRangeKeepsEmptySupportingOwnerDateInExactRollupCoverage() async throws {
        let diagnostics = M6DiagnosticRecorder()
        let planner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "shadow",
                userDefaults: nil,
                environment: [:]
            ),
            identitySource: fixedIdentitySource,
            diagnosticSink: { await diagnostics.record($0) }
        )
        let settings = makeSimpleSettings(formats: [.json])
        settings.generateWeeklyRollups = true
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            appleExportEngineAuthorityIsFrozen: false,
            calendarTimeZoneIdentifier: "UTC"
        )
        let first = ExportFixtures.partialDay
        let secondDate = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(byAdding: .day, value: -1, to: first.date)
        )
        let emptySupportingRecord = HealthData(
            date: secondDate,
            timeContext: ExportFixtures.timeContext
        )

        let operation = try unwrapPlanned(try await planner.planRange(
            healthData: [first, emptySupportingRecord],
            dailyOutputOwnerDates: ["2026-03-15"],
            settingsSnapshot: snapshot,
            surface: .localVaultRangeWithoutSideEffects
        ))

        XCTAssertEqual(operation.selectedPlan, try XCTUnwrap(operation.nativePlan))
        XCTAssertEqual(operation.artifacts.count, 2)
        let recordedDiagnostics = await diagnostics.values()
        XCTAssertEqual(recordedDiagnostics.count, 1)
        guard case .comparisonCompleted(let rangeComparison) = recordedDiagnostics.first else {
            return XCTFail("Expected one exact range comparison event")
        }
        XCTAssertTrue(rangeComparison.matches)
        XCTAssertEqual(rangeComparison.mismatchCount, 0)
        let rollup = try XCTUnwrap(operation.artifacts.first {
            $0.artifact.relativePath.contains("/Rollups/Weekly/")
        })
        let content = try XCTUnwrap(String(data: rollup.artifact.inlineData, encoding: .utf8))
        XCTAssertTrue(content.contains("\"days_counted\" : 2"))
    }

    func testConcreteShadowDirectRangeIncludesRollupsInOneExactPlan() async throws {
        let planner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "shadow",
                userDefaults: nil,
                environment: [:]
            ),
            identitySource: fixedIdentitySource
        )
        let settings = makeSimpleSettings(formats: Set(ExportFormat.allCases))
        settings.generateWeeklyRollups = true
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            appleExportEngineAuthorityIsFrozen: false,
            calendarTimeZoneIdentifier: "UTC"
        )
        let first = ExportFixtures.partialDay
        let secondDate = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: first.date)
        )
        var second = HealthData(date: secondDate, timeContext: ExportFixtures.timeContext)
        second.sleep = first.sleep
        second.activity = first.activity

        let persistedIdentity = AppleExportOperationIdentity(
            requestID: "direct-request",
            sessionID: "direct-session",
            capturedAt: Date(timeIntervalSince1970: 456),
            calendarTimeZoneIdentifier: "UTC"
        )
        let operation = try unwrapPlanned(try await planner.planRange(
            healthData: [first, second],
            dailyOutputOwnerDates: ["2026-03-15"],
            settingsSnapshot: snapshot,
            surface: .directGeneratedFilesWithoutSideEffects,
            operationIdentity: persistedIdentity
        ))

        XCTAssertEqual(operation.authority, .shadow)
        XCTAssertEqual(operation.identity, persistedIdentity)
        XCTAssertEqual(operation.selectedPlan, try XCTUnwrap(operation.nativePlan))
        XCTAssertEqual(operation.artifacts.count, 12)
        XCTAssertEqual(operation.artifacts.count { $0.artifact.relativePath.contains("/Rollups/") }, 8)
        XCTAssertFalse(operation.artifacts.contains {
            $0.artifact.relativePath.hasPrefix("Health/2026-03-16.")
        })
    }

    func testConcreteShadowSummaryOnlyRangeContainsNoDailyArtifacts() async throws {
        let planner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "shadow",
                userDefaults: nil,
                environment: [:]
            ),
            identitySource: fixedIdentitySource
        )
        let settings = makeSimpleSettings(formats: Set(ExportFormat.allCases))
        settings.generateMonthlyRollups = true
        settings.summaryOnlyExport = true
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            appleExportEngineAuthorityIsFrozen: false,
            calendarTimeZoneIdentifier: "UTC"
        )
        let operation = try unwrapPlanned(try await planner.planRange(
            healthData: [ExportFixtures.partialDay],
            dailyOutputOwnerDates: [],
            settingsSnapshot: snapshot,
            surface: .localVaultRangeWithoutSideEffects
        ))

        XCTAssertEqual(operation.authority, .shadow)
        XCTAssertEqual(operation.selectedPlan, try XCTUnwrap(operation.nativePlan))
        XCTAssertEqual(operation.artifacts.count, 4)
        XCTAssertTrue(operation.artifacts.allSatisfy {
            $0.artifact.relativePath.contains("/Rollups/Monthly/")
        })
    }

    func testConcreteRustSummaryOnlyRollupUsesExactRustBytesWithoutNativeRenderer() async throws {
        let planner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "rust",
                userDefaults: nil,
                environment: [:]
            ),
            identitySource: fixedIdentitySource,
            nativeRendererPreflight: {
                throw NSError(domain: "native renderer must not open", code: 1)
            }
        )
        let settings = makeSimpleSettings(formats: Set(ExportFormat.allCases))
        settings.generateMonthlyRollups = true
        settings.summaryOnlyExport = true
        let fixture = ExportFixtures.partialDay
        var record = HealthData(
            date: fixture.date,
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "GMT")
        )
        record.sleep = fixture.sleep
        record.activity = fixture.activity
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(
            settings,
            healthSubfolder: "Health",
            calendarTimeZone: try XCTUnwrap(TimeZone(identifier: "UTC")),
            surface: .localVaultRangeWithoutSideEffects,
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "rust",
                userDefaults: nil,
                environment: [:]
            )
        )
        let capturedPin = try XCTUnwrap(snapshot.appleExportEnginePin)
        XCTAssertEqual(capturedPin.engine, .rust)
        let service = HealthMdCoreService()
        XCTAssertTrue(capturedPin.isCompatible(
            buildInfo: try service.buildInfo(),
            registrySnapshot: try service.metricRegistry(profile: .appleHealthDataV7)
        ))
        XCTAssertTrue(AppleLooseDailyExportPlanner.supports(
            healthData: [record],
            settingsSnapshot: snapshot,
            surface: .localVaultRangeWithoutSideEffects
        ))
        XCTAssertTrue(ApplePureRustAuthorityAdmission.supports(
            settings: snapshot,
            surface: .localVaultRangeWithoutSideEffects
        ))

        let operation = try unwrapPlanned(try await planner.planRange(
            healthData: [record],
            dailyOutputOwnerDates: [],
            settingsSnapshot: snapshot,
            surface: .localVaultRangeWithoutSideEffects
        ))

        XCTAssertEqual(operation.authority, .rust)
        XCTAssertNil(operation.nativePlan)
        XCTAssertEqual(operation.pin.engine, .rust)
        XCTAssertEqual(operation.selectedPlan.artifacts, operation.artifacts.map(\.artifact))
        XCTAssertEqual(operation.artifacts.count, 4)
        XCTAssertTrue(operation.artifacts.allSatisfy {
            $0.artifact.relativePath.contains("/Rollups/Monthly/")
        })

        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "GMT"))
        let summaries = HealthRollupExporter.makeSummaries(
            from: [record],
            settings: settings,
            periods: [.monthly],
            generatedAt: Date(timeIntervalSince1970: 123),
            calendar: calendar
        )
        let nativeTargets = HealthRollupExporter.outputTargets(
            for: summaries,
            healthSubfolder: "Health",
            settings: settings
        )
        XCTAssertEqual(
            operation.artifacts.map(\.artifact.relativePath),
            nativeTargets.map(\.relativePath)
        )
        for target in nativeTargets {
            let artifact = try XCTUnwrap(operation.artifacts.first {
                $0.artifact.relativePath == target.relativePath
            })
            XCTAssertEqual(
                String(data: artifact.artifact.inlineData, encoding: .utf8),
                target.content
            )
        }
        for surface in [
            AppleExportOperationSurface.directGeneratedFilesWithoutSideEffects,
            .connectedReceivedRangeWithoutSideEffects,
        ] {
            let ranged = try unwrapPlanned(try await planner.planRange(
                healthData: [record],
                dailyOutputOwnerDates: [],
                settingsSnapshot: snapshot,
                surface: surface
            ))
            XCTAssertEqual(ranged.authority, .rust)
            XCTAssertNil(ranged.nativePlan)
            XCTAssertEqual(ranged.selectedPlan, operation.selectedPlan)
        }
    }

    func testConcreteRustSummaryOnlyRollupFailsClosedOnIncompleteCorePlan() async throws {
        let settings = makeSimpleSettings(formats: [.json])
        settings.generateWeeklyRollups = true
        settings.summaryOnlyExport = true
        let fixture = ExportFixtures.partialDay
        var record = HealthData(
            date: fixture.date,
            timeContext: ExportTimeContext(calendarTimeZoneIdentifier: "GMT")
        )
        record.activity = fixture.activity
        let snapshot = await ExportSettingsSnapshot.forNewAppleOperation(
            settings,
            healthSubfolder: "Health",
            calendarTimeZone: try XCTUnwrap(TimeZone(identifier: "UTC")),
            surface: .localVaultRangeWithoutSideEffects,
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "rust",
                userDefaults: nil,
                environment: [:]
            )
        )
        XCTAssertEqual(snapshot.appleExportEnginePin?.engine, .rust)
        let planner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "rust",
                userDefaults: nil,
                environment: [:]
            ),
            coreExecutor: M6DroppingRollupCoreExecutor(),
            identitySource: fixedIdentitySource,
            nativeRendererPreflight: {
                throw NSError(domain: "native renderer must not open", code: 1)
            }
        )

        do {
            _ = try await planner.planRange(
                healthData: [record],
                dailyOutputOwnerDates: [],
                settingsSnapshot: snapshot,
                surface: .localVaultRangeWithoutSideEffects
            )
            XCTFail("Incomplete selected Rust plans must fail closed")
        } catch {
            XCTAssertEqual(error as? AppleLooseDailyExportPlannerError, .rustPlanningFailed)
        }
    }

    func testConcreteShadowDirectSummaryOnlyRangeContainsNoDailyArtifacts() async throws {
        let planner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "shadow",
                userDefaults: nil,
                environment: [:]
            ),
            identitySource: fixedIdentitySource
        )
        let settings = makeSimpleSettings(formats: Set(ExportFormat.allCases))
        settings.generateMonthlyRollups = true
        settings.summaryOnlyExport = true
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            appleExportEngineAuthorityIsFrozen: false,
            calendarTimeZoneIdentifier: "UTC"
        )

        let operation = try unwrapPlanned(try await planner.planRange(
            healthData: [ExportFixtures.partialDay],
            dailyOutputOwnerDates: [],
            settingsSnapshot: snapshot,
            surface: .directGeneratedFilesWithoutSideEffects
        ))

        XCTAssertEqual(operation.authority, .shadow)
        XCTAssertEqual(operation.selectedPlan, try XCTUnwrap(operation.nativePlan))
        XCTAssertEqual(operation.artifacts.count, 4)
        XCTAssertTrue(operation.artifacts.allSatisfy {
            $0.artifact.relativePath.contains("/Rollups/Monthly/")
        })
    }

    func testVaultCommitsConcreteShadowRangeOnlyAfterCompletePlan() async throws {
        let planner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "shadow",
                userDefaults: nil,
                environment: [:]
            ),
            identitySource: fixedIdentitySource
        )
        let settings = makeSimpleSettings(formats: Set(ExportFormat.allCases))
        settings.generateWeeklyRollups = true
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            appleExportEngineAuthorityIsFrozen: false,
            calendarTimeZoneIdentifier: "UTC"
        )
        let first = ExportFixtures.partialDay
        let secondDate = try XCTUnwrap(
            Calendar(identifier: .gregorian).date(byAdding: .day, value: 1, to: first.date)
        )
        var second = HealthData(date: secondDate, timeContext: ExportFixtures.timeContext)
        second.sleep = first.sleep
        second.activity = first.activity
        let harness = makeVaultHarness(planner: planner, label: "concrete-range")

        let fileCount = try await harness.manager.exportHealthDataRange(
            [second, first],
            settingsSnapshot: snapshot,
            operationSurface: .localVaultRangeWithoutSideEffects,
            writeDataDictionary: false
        )

        XCTAssertEqual(fileCount?.totalFileCount, 16)
        XCTAssertEqual(fileCount?.rollupFileCount, 8)
        XCTAssertEqual(harness.fileSystem.writeAttempts, 16)
        XCTAssertEqual(harness.fileSystem.fileCount, 16)
    }

    func testRustPrecommitFailureThrowsWhileShadowReturnsNativeWithHealthFreeDiagnostic() async throws {
        let sensitive = "steps=987654;2026-03-15;private/path"
        let executor = M6SemanticFailingCoreExecutor(sensitiveValue: sensitive)
        let settings = makeSimpleSettings(formats: [.json])
        settings.generateWeeklyRollups = true
        settings.summaryOnlyExport = true
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            appleExportEngineAuthorityIsFrozen: false,
            calendarTimeZoneIdentifier: "UTC"
        )

        let rustPlanner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "rust",
                userDefaults: nil,
                environment: [:]
            ),
            coreExecutor: executor,
            identitySource: fixedIdentitySource
        )
        do {
            _ = try await rustPlanner.planRange(
                healthData: [ExportFixtures.partialDay],
                dailyOutputOwnerDates: [],
                settingsSnapshot: snapshot,
                surface: .localVaultRangeWithoutSideEffects
            )
            XCTFail("Expected selected Rust planning to fail")
        } catch {
            XCTAssertEqual(
                error as? AppleLooseDailyExportPlannerError,
                .rustPlanningFailed
            )
            XCTAssertFalse(String(describing: error).contains(sensitive))
        }

        let diagnostics = M6DiagnosticRecorder()
        let shadowPlanner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "shadow",
                userDefaults: nil,
                environment: [:]
            ),
            coreExecutor: executor,
            identitySource: fixedIdentitySource,
            diagnosticSink: { await diagnostics.record($0) }
        )
        let shadow = try unwrapPlanned(try await shadowPlanner.planRange(
            healthData: [ExportFixtures.partialDay],
            dailyOutputOwnerDates: [],
            settingsSnapshot: snapshot,
            surface: .localVaultRangeWithoutSideEffects
        ))
        XCTAssertEqual(shadow.authority, .shadow)
        XCTAssertEqual(shadow.selectedPlan, try XCTUnwrap(shadow.nativePlan))
        let recorded = await diagnostics.values()
        XCTAssertEqual(recorded.count, 1)
        XCTAssertTrue(recorded.allSatisfy {
            if case .rustRenderFailed = $0 { return true }
            return false
        })
        XCTAssertFalse(String(describing: recorded).contains(sensitive))
        XCTAssertFalse(String(describing: recorded).contains("987654"))
        XCTAssertFalse(String(describing: recorded).contains("2026-03-15"))
    }

    func testConnectedReceivedSnapshotWithoutPinStaysLegacyUnderCurrentRustDefault() async throws {
        let counter = M6CoreCallCounter()
        let planner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "rust",
                userDefaults: nil,
                environment: [:]
            ),
            coreExecutor: M6NeverCoreExecutor(counter: counter),
            identitySource: fixedIdentitySource
        )
        let settings = makeSimpleSettings()
        let snapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            calendarTimeZoneIdentifier: ExportFixtures.partialDay.timeContext.calendarTimeZoneIdentifier
        )

        let resolution = try await planner.plan(
            healthData: ExportFixtures.partialDay,
            settingsSnapshot: snapshot,
            surface: .connectedReceivedFilesWithoutSideEffects
        )

        XCTAssertEqual(resolution, .legacy)
        let coreCallCount = await counter.value()
        XCTAssertEqual(coreCallCount, 0)
    }

    func testFrozenLocalSnapshotWithoutPinStaysLegacyUnderCurrentRustDefault() async throws {
        let counter = M6CoreCallCounter()
        let planner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "rust",
                userDefaults: nil,
                environment: [:]
            ),
            coreExecutor: M6NeverCoreExecutor(counter: counter),
            identitySource: fixedIdentitySource
        )
        let snapshot = ExportSettingsSnapshot.from(
            makeSimpleSettings(),
            healthSubfolder: "Health",
            appleExportEngineAuthorityIsFrozen: true,
            calendarTimeZoneIdentifier: ExportFixtures.partialDay.timeContext.calendarTimeZoneIdentifier
        )

        let resolution = try await planner.plan(
            healthData: ExportFixtures.partialDay,
            settingsSnapshot: snapshot,
            surface: .localVaultWithoutSideEffects
        )

        XCTAssertEqual(resolution, .legacy)
        let coreCallCount = await counter.value()
        XCTAssertEqual(coreCallCount, 0)
    }

    func testUnsupportedPureRustDailyRequestFallsBackNewAndFailsClosedWhenPinned() async throws {
        let counter = M6CoreCallCounter()
        let planner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "rust",
                userDefaults: nil,
                environment: [:]
            ),
            coreExecutor: M6NeverCoreExecutor(counter: counter),
            identitySource: fixedIdentitySource
        )
        let settings = makeSimpleSettings(formats: [.json])
        let newSnapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: "Health",
            appleExportEngineAuthorityIsFrozen: false,
            calendarTimeZoneIdentifier: "UTC"
        )
        let newResolution = try await planner.planRange(
            healthData: [ExportFixtures.partialDay],
            dailyOutputOwnerDates: ["2026-03-15"],
            settingsSnapshot: newSnapshot,
            surface: .localVaultRangeWithoutSideEffects
        )
        XCTAssertEqual(newResolution, .legacy)

        var pinnedSnapshot = newSnapshot
        pinnedSnapshot.appleExportEngineAuthorityIsFrozen = true
        pinnedSnapshot.appleExportEnginePin = try makeSyntheticAppleExportEnginePin(
            engine: .rust,
            calendarTimeZoneIdentifier: "UTC"
        )
        do {
            _ = try await planner.planRange(
                healthData: [ExportFixtures.partialDay],
                dailyOutputOwnerDates: ["2026-03-15"],
                settingsSnapshot: pinnedSnapshot,
                surface: .localVaultRangeWithoutSideEffects
            )
            XCTFail("Expected incompatible persisted Rust authority to fail closed")
        } catch {
            XCTAssertEqual(error as? AppleLooseDailyExportPlannerError, .rustPlanningFailed)
        }
        let coreCallCount = await counter.value()
        XCTAssertEqual(coreCallCount, 0)
    }

    func testEveryUnsupportedFeatureResolvesWhollyLegacyWithoutLoadingCore() async throws {
        let counter = M6CoreCallCounter()
        let planner = AppleLooseDailyExportPlanner(
            policyResolver: AppleExportEnginePolicyResolver(
                injectedOverride: "rust",
                userDefaults: nil,
                environment: [:]
            ),
            coreExecutor: M6NeverCoreExecutor(counter: counter),
            identitySource: fixedIdentitySource
        )

        var cases: [(AdvancedExportSettings, HealthData, AppleExportOperationSurface)] = []
        let append = makeSimpleSettings(); append.writeMode = .append
        cases.append((append, ExportFixtures.partialDay, .localVaultWithoutSideEffects))
        let update = makeSimpleSettings(); update.writeMode = .update
        cases.append((update, ExportFixtures.partialDay, .localVaultWithoutSideEffects))
        let noFormats = makeSimpleSettings(formats: [])
        cases.append((noFormats, ExportFixtures.partialDay, .localVaultWithoutSideEffects))
        let archive = makeSimpleSettings(); archive.archiveExportFiles = true
        cases.append((archive, ExportFixtures.partialDay, .localVaultWithoutSideEffects))
        let lossless = makeSimpleSettings(); lossless.includeGranularData = true
        cases.append((lossless, ExportFixtures.losslessDay, .localVaultWithoutSideEffects))
        cases.append((makeSimpleSettings(), ExportFixtures.losslessDay, .localVaultWithoutSideEffects))
        let summaryOnly = makeSimpleSettings(); summaryOnly.summaryOnlyExport = true
        cases.append((summaryOnly, ExportFixtures.partialDay, .localVaultWithoutSideEffects))
        let dailyNote = makeSimpleSettings(); dailyNote.dailyNoteInjection.enabled = true
        cases.append((dailyNote, ExportFixtures.partialDay, .localVaultWithoutSideEffects))
        let individual = makeSimpleSettings(); individual.individualTracking.globalEnabled = true
        cases.append((individual, ExportFixtures.partialDay, .localVaultWithoutSideEffects))
        cases.append((makeSimpleSettings(), ExportFixtures.partialDay, .legacyOnly))

        for (settings, healthData, surface) in cases {
            let resolution = try await planner.plan(
                healthData: healthData,
                settingsSnapshot: ExportSettingsSnapshot.from(
                    settings,
                    healthSubfolder: "Health",
                    appleExportEngineAuthorityIsFrozen: false,
                    calendarTimeZoneIdentifier: healthData.timeContext.calendarTimeZoneIdentifier
                ),
                surface: surface
            )
            XCTAssertEqual(resolution, .legacy)
        }
        let coreCallCount = await counter.value()
        XCTAssertEqual(coreCallCount, 0)
    }

    func testVaultLegacyBytesUnchangedAndShadowAndRustCommitOnlySelectedAuthority() async throws {
        let healthData = ExportFixtures.partialDay
        let settings = makeSimpleSettings(formats: [.json])
        let expectedLegacy = try healthData.preparedExport(settings: settings).content(
            format: .json,
            settings: settings
        )

        let legacyHarness = makeVaultHarness(
            planner: M6StubPlanner(resolution: .legacy),
            label: "legacy"
        )
        _ = try await legacyHarness.manager.exportHealthData(
            healthData,
            settings: settings,
            writeDataDictionary: false,
            operationSurface: .localVaultWithoutSideEffects
        )
        XCTAssertEqual(legacyHarness.fileSystem.onlyFileContent, expectedLegacy)

        let shadowOperation = try makeStubOperation(
            authority: .shadow,
            nativeData: Data("native-only".utf8),
            selectedData: Data("native-only".utf8)
        )
        let shadowHarness = makeVaultHarness(
            planner: M6StubPlanner(resolution: .planned(shadowOperation)),
            label: "shadow"
        )
        _ = try await shadowHarness.manager.exportHealthData(
            healthData,
            settings: settings,
            writeDataDictionary: false,
            operationSurface: .localVaultWithoutSideEffects
        )
        XCTAssertEqual(shadowHarness.fileSystem.onlyFileContent, "native-only")

        let rustOperation = try makeStubOperation(
            authority: .rust,
            nativeData: Data("native-not-committed".utf8),
            selectedData: Data("rust-only".utf8)
        )
        let rustHarness = makeVaultHarness(
            planner: M6StubPlanner(resolution: .planned(rustOperation)),
            label: "rust"
        )
        _ = try await rustHarness.manager.exportHealthData(
            healthData,
            settings: settings,
            writeDataDictionary: false,
            operationSurface: .localVaultWithoutSideEffects
        )
        XCTAssertEqual(rustHarness.fileSystem.onlyFileContent, "rust-only")
        XCTAssertFalse(rustHarness.fileSystem.onlyFileContent?.contains("native-not-committed") == true)
    }

    func testVaultFullyPlansBeforeFirstWriteAndNeverReplansOrFallsBackAfterWriteFailure() async throws {
        let events = M6EventRecorder()
        let operation = try makeStubOperation(
            authority: .rust,
            nativeData: Data("native".utf8),
            selectedData: Data("rust".utf8)
        )
        let planner = M6StubPlanner(
            resolution: .planned(operation),
            events: events
        )
        let harness = makeVaultHarness(
            planner: planner,
            label: "write-failure",
            events: events,
            failWriteNumber: 1
        )

        do {
            _ = try await harness.manager.exportHealthData(
                ExportFixtures.partialDay,
                settings: makeSimpleSettings(formats: [.json]),
                writeDataDictionary: false,
                operationSurface: .localVaultWithoutSideEffects
            )
            XCTFail("Expected the first destination write to fail")
        } catch {
            XCTAssertEqual((error as NSError).domain, "M6RecordingFileSystem")
        }

        XCTAssertEqual(planner.callCount, 1)
        XCTAssertEqual(harness.fileSystem.writeAttempts, 1)
        XCTAssertEqual(events.values(), ["planned", "write-1"])
        XCTAssertNil(harness.fileSystem.onlyFileContent)
    }

    private var fixedIdentitySource: AppleExportOperationIdentitySource {
        AppleExportOperationIdentitySource(
            makeRequestID: { "m6-request" },
            makeSessionID: { "m6-session" },
            now: { Date(timeIntervalSince1970: 123) }
        )
    }

    private func makeSimpleSettings(
        formats: Set<ExportFormat> = [.json]
    ) -> AdvancedExportSettings {
        let suite = "AppleLooseDailyExportPlannerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        settings.exportFormats = formats
        settings.writeMode = .overwrite
        settings.archiveExportFiles = false
        settings.summaryOnlyExport = false
        settings.includeGranularData = false
        settings.generateWeeklyRollups = false
        settings.generateMonthlyRollups = false
        settings.generateYearlyRollups = false
        settings.dailyNoteInjection.enabled = false
        settings.individualTracking.globalEnabled = false
        Self.retainedSettings.append(settings)
        return settings
    }

    private func unwrapPlanned(
        _ resolution: AppleLooseDailyPlanResolution
    ) throws -> AppleLooseDailyPlannedOperation {
        guard case .planned(let operation) = resolution else {
            throw XCTSkip("The internal test authority was not available")
        }
        return operation
    }

    private struct VaultHarness {
        let manager: VaultManager
        let fileSystem: M6RecordingFileSystem
    }

    private func makeVaultHarness(
        planner: any AppleLooseDailyExportPlanning,
        label: String,
        events: M6EventRecorder? = nil,
        failWriteNumber: Int? = nil
    ) -> VaultHarness {
        let vaultURL = URL(fileURLWithPath: "/tmp/M6-\(label)-\(UUID().uuidString)")
        let defaults = FakeUserDefaults()
        defaults.storage["obsidianVaultBookmark"] = Data("bookmark".utf8)
        let resolver = FakeBookmarkResolver()
        resolver.resolvedURL = vaultURL
        resolver.accessGranted = true
        let fileSystem = M6RecordingFileSystem(
            events: events,
            failWriteNumber: failWriteNumber
        )
        let manager = VaultManager(
            defaults: defaults,
            fileSystem: fileSystem,
            bookmarkResolver: resolver,
            appleLooseDailyPlanner: planner
        )
        Self.retainedManagers.append(manager)
        return VaultHarness(manager: manager, fileSystem: fileSystem)
    }

    private func makeStubOperation(
        authority: ExportEngineMode,
        nativeData: Data,
        selectedData: Data
    ) throws -> AppleLooseDailyPlannedOperation {
        let service = HealthMdCoreService()
        let buildInfo = try service.buildInfo()
        let registry = try service.metricRegistry(profile: .appleHealthDataV7)
        let pin = try AppleExportEnginePin(
            engine: authority,
            calendarTimeZoneIdentifier: "UTC",
            buildInfo: buildInfo,
            registrySnapshot: registry
        )
        let identity = AppleExportOperationIdentity(
            requestID: "stub-request",
            sessionID: "stub-session",
            capturedAt: Date(timeIntervalSince1970: 123),
            calendarTimeZoneIdentifier: "UTC"
        )
        let path = "Health/2026-03-15.json"
        let nativePlan = try makePlan(
            data: nativeData,
            path: path,
            identity: identity,
            pin: pin
        )
        let selectedPlan = try makePlan(
            data: selectedData,
            path: path,
            identity: identity,
            pin: pin
        )
        return AppleLooseDailyPlannedOperation(
            authority: authority,
            identity: identity,
            pin: pin,
            nativePlan: nativePlan,
            selectedPlan: selectedPlan,
            artifacts: [AppleLooseDailyPlannedArtifact(
                kind: .daily,
                format: .json,
                artifact: try XCTUnwrap(selectedPlan.artifacts.first)
            )]
        )
    }

    private func makePlan(
        data: Data,
        path: String,
        identity: AppleExportOperationIdentity,
        pin: AppleExportEnginePin
    ) throws -> NativeExportArtifactPlan {
        let digest = NativeExportArtifact.sha256(of: data)
        let artifact = try NativeExportArtifact(
            role: .file,
            id: NativeExportArtifactPlan.artifactID(
                requestID: identity.requestID,
                sessionID: identity.sessionID,
                profile: .appleHealthDataV7,
                relativePath: path,
                mediaType: "application/json",
                writeMode: .overwrite,
                contentSHA256: digest
            ),
            relativePath: path,
            mediaType: "application/json",
            writeMode: .overwrite,
            inlineData: data,
            byteCount: UInt64(data.count),
            sha256: digest
        )
        return try NativeExportArtifactPlan(
            artifactPlanVersion: pin.artifactPlanVersion,
            requestID: identity.requestID,
            sessionID: identity.sessionID,
            profile: .appleHealthDataV7,
            artifacts: [artifact],
            totalByteCount: artifact.byteCount,
            pin: pin
        )
    }
}

@MainActor
private final class M6StubPlanner: AppleLooseDailyExportPlanning {
    let resolution: AppleLooseDailyPlanResolution
    let events: M6EventRecorder?
    private(set) var callCount = 0

    init(
        resolution: AppleLooseDailyPlanResolution,
        events: M6EventRecorder? = nil
    ) {
        self.resolution = resolution
        self.events = events
    }

    func plan(
        healthData: HealthData,
        settingsSnapshot: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface
    ) async throws -> AppleLooseDailyPlanResolution {
        callCount += 1
        events?.record("planned")
        return resolution
    }
}

private actor M6DiagnosticRecorder {
    private var diagnostics: [ShadowExportDiagnostic] = []

    func record(_ diagnostic: ShadowExportDiagnostic) {
        diagnostics.append(diagnostic)
    }

    func values() -> [ShadowExportDiagnostic] { diagnostics }
}

nonisolated private struct M6DroppingRollupCoreExecutor: AppleLooseDailyCoreExecuting, Sendable {
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
        var items = plan.items
        guard let index = items.firstIndex(where: {
            $0.relativePath.contains("/Rollups/")
        }) else { return plan }
        let removed = items.remove(at: index)
        return CoreArtifactPlan(
            schema: plan.schema,
            artifactPlanVersion: plan.artifactPlanVersion,
            requestId: plan.requestId,
            sessionId: plan.sessionId,
            profile: plan.profile,
            items: items,
            totalByteCount: plan.totalByteCount - removed.byteCount
        )
    }
}

nonisolated private struct M6SensitiveError: Error, Sendable {
    let value: String
}

nonisolated private struct M6SemanticFailingCoreExecutor: AppleLooseDailyCoreExecuting, Sendable {
    let sensitiveValue: String
    private let base = SystemAppleLooseDailyCoreExecutor()

    func loadContext() async throws -> AppleLooseDailyCoreContext {
        try await base.loadContext()
    }

    func processSemantic(configuration: Data, batches: [Data]) async throws -> Data {
        throw M6SensitiveError(value: sensitiveValue)
    }

    func render(
        configuration: Data,
        semanticResult: Data,
        batches: [Data]
    ) async throws -> CoreArtifactPlan {
        throw M6SensitiveError(value: sensitiveValue)
    }
}

private actor M6CoreCallCounter {
    private var count = 0
    func increment() { count += 1 }
    func value() -> Int { count }
}

nonisolated private struct M6NeverCoreExecutor: AppleLooseDailyCoreExecuting, Sendable {
    let counter: M6CoreCallCounter

    func loadContext() async throws -> AppleLooseDailyCoreContext {
        await counter.increment()
        throw M6SensitiveError(value: "core must not load")
    }

    func processSemantic(configuration: Data, batches: [Data]) async throws -> Data {
        await counter.increment()
        throw M6SensitiveError(value: "semantic must not run")
    }

    func render(
        configuration: Data,
        semanticResult: Data,
        batches: [Data]
    ) async throws -> CoreArtifactPlan {
        await counter.increment()
        throw M6SensitiveError(value: "render must not run")
    }
}

nonisolated private final class M6EventRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String] = []

    func record(_ value: String) {
        lock.withLock { storage.append(value) }
    }

    func values() -> [String] {
        lock.withLock { storage }
    }
}

nonisolated private final class M6RecordingFileSystem: FileSystemAccessing, @unchecked Sendable {
    private let lock = NSLock()
    private var files: [String: String] = [:]
    private var directories: Set<String> = []
    private var attempts = 0
    private let events: M6EventRecorder?
    private let failWriteNumber: Int?

    init(events: M6EventRecorder?, failWriteNumber: Int?) {
        self.events = events
        self.failWriteNumber = failWriteNumber
    }

    var writeAttempts: Int { lock.withLock { attempts } }
    var fileCount: Int { lock.withLock { files.count } }
    var onlyFileContent: String? { lock.withLock { files.values.first } }

    func fileExists(atPath path: String) -> Bool {
        lock.withLock { files[path] != nil || directories.contains(path) }
    }

    func createDirectory(at url: URL, withIntermediateDirectories: Bool) throws {
        lock.withLock { _ = directories.insert(url.path) }
    }

    func contentsOfFile(at url: URL) throws -> String {
        try lock.withLock {
            guard let value = files[url.path] else { throw CocoaError(.fileReadNoSuchFile) }
            return value
        }
    }

    func writeString(_ string: String, to url: URL, atomically: Bool) throws {
        let attempt = lock.withLock { () -> Int in
            attempts += 1
            return attempts
        }
        events?.record("write-\(attempt)")
        if attempt == failWriteNumber {
            throw NSError(domain: "M6RecordingFileSystem", code: attempt)
        }
        lock.withLock { files[url.path] = string }
    }

    func contentsOfDirectory(at url: URL) throws -> [URL] { [] }

    func removeItem(at url: URL) throws {
        lock.withLock {
            files.removeValue(forKey: url.path)
            directories.remove(url.path)
        }
    }
}
