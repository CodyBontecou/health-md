import Foundation
import HealthMdCoreRust

/// Call-site attestation for the first production Apple renderer seam. Connected receivers may use
/// their dedicated surface only after resolving one immutable job/manifest snapshot and proving the
/// whole operation has no native-only companion action.
nonisolated enum AppleExportOperationSurface: Equatable, Sendable {
    case legacyOnly
    case localVaultWithoutSideEffects
    case localVaultRangeWithoutSideEffects
    case directGeneratedFilesWithoutSideEffects
    case connectedReceivedFilesWithoutSideEffects
    case connectedReceivedRangeWithoutSideEffects
    case apiEndpoint
    case preview
}

nonisolated struct AppleExportOperationIdentity: Equatable, Sendable {
    let requestID: String
    let sessionID: String
    let capturedAt: Date
    let calendarTimeZoneIdentifier: String
}

nonisolated struct AppleExportOperationIdentitySource: Sendable {
    let makeRequestID: @Sendable () -> String
    let makeSessionID: @Sendable () -> String
    let now: @Sendable () -> Date

    init(
        makeRequestID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        makeSessionID: @escaping @Sendable () -> String = { UUID().uuidString.lowercased() },
        now: @escaping @Sendable () -> Date = Date.init
    ) {
        self.makeRequestID = makeRequestID
        self.makeSessionID = makeSessionID
        self.now = now
    }

    func capture(calendarTimeZoneIdentifier: String) -> AppleExportOperationIdentity {
        AppleExportOperationIdentity(
            requestID: makeRequestID(),
            sessionID: makeSessionID(),
            capturedAt: now(),
            calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
        )
    }
}

nonisolated struct AppleLooseDailyCoreContext: Sendable {
    let buildInfo: CoreBuildInfo
    let registry: CoreMetricRegistrySnapshot
}

/// Coarse shared-core boundary used by the application planner. Production implementations create
/// and drive every synchronous UniFFI object on a detached utility worker. Only immutable `Data`
/// buffers cross into semantic/render workers.
nonisolated protocol AppleLooseDailyCoreExecuting: Sendable {
    func loadContext() async throws -> AppleLooseDailyCoreContext
    func processSemantic(configuration: Data, batches: [Data]) async throws -> Data
    func render(
        configuration: Data,
        semanticResult: Data,
        batches: [Data]
    ) async throws -> CoreArtifactPlan
}

nonisolated struct SystemAppleLooseDailyCoreExecutor: AppleLooseDailyCoreExecuting, Sendable {
    func loadContext() async throws -> AppleLooseDailyCoreContext {
        try await runDetached {
            let service = HealthMdCoreService()
            return AppleLooseDailyCoreContext(
                buildInfo: try service.buildInfo(),
                registry: try service.metricRegistry(profile: .appleHealthDataV7)
            )
        }
    }

    func processSemantic(configuration: Data, batches: [Data]) async throws -> Data {
        try await runDetached {
            guard !batches.isEmpty else {
                throw HealthMdSemanticInputAdapter.AdapterError.invalidSessionResult
            }
            let session = try HealthMdCoreService().semanticSession(configuration: configuration)
            var result = Data()
            do {
                for batch in batches {
                    try Task.checkCancellation()
                    result = try session.process(batch: batch)
                }
                try Task.checkCancellation()
                guard let object = try? JSONSerialization.jsonObject(with: result) as? [String: Any],
                      object["state"] as? String == "completed" else {
                    throw HealthMdSemanticInputAdapter.AdapterError.invalidSessionResult
                }
                return result
            } catch {
                session.cancel()
                throw error
            }
        }
    }

    func render(
        configuration: Data,
        semanticResult: Data,
        batches: [Data]
    ) async throws -> CoreArtifactPlan {
        try await runDetached {
            let session = try HealthMdCoreService().renderSession(
                configuration: configuration,
                semanticResult: semanticResult
            )
            do {
                for batch in batches {
                    try Task.checkCancellation()
                    _ = try session.process(batch: batch)
                }
                try Task.checkCancellation()
                return try session.finish()
            } catch {
                session.cancel()
                throw error
            }
        }
    }

    private func runDetached<Value: Sendable>(
        _ operation: @escaping @Sendable () throws -> Value
    ) async throws -> Value {
        let worker = Task.detached(priority: .utility, operation: operation)
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}

nonisolated enum AppleLooseDailyArtifactKind: String, Codable, Equatable, Sendable {
    case daily
    case rollup
}

nonisolated struct AppleLooseDailyPlannedArtifact: Equatable, Sendable {
    let kind: AppleLooseDailyArtifactKind
    let format: ExportFormat
    let artifact: NativeExportArtifact
}

nonisolated struct AppleLooseDailyPlannedOperation: Equatable, Sendable {
    let authority: ExportEngineMode
    let identity: AppleExportOperationIdentity
    let pin: AppleExportEnginePin
    let nativePlan: NativeExportArtifactPlan?
    let selectedPlan: NativeExportArtifactPlan
    let artifacts: [AppleLooseDailyPlannedArtifact]
}

nonisolated enum AppleLooseDailyPlanResolution: Equatable, Sendable {
    case legacy
    case planned(AppleLooseDailyPlannedOperation)
}

nonisolated enum AppleLooseDailyExportPlannerError: String, Error, Equatable, Sendable {
    case rustPlanningFailed = "rust_planning_failed"
}

extension AppleLooseDailyExportPlannerError: LocalizedError {
    var errorDescription: String? { rawValue }
}

@MainActor
protocol AppleLooseDailyExportPlanning {
    func plan(
        healthData: HealthData,
        settingsSnapshot: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface
    ) async throws -> AppleLooseDailyPlanResolution
}

@MainActor
protocol AppleLooseDailyRangeExportPlanning: AppleLooseDailyExportPlanning {
    func planRange(
        healthData: [HealthData],
        settingsSnapshot: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface
    ) async throws -> AppleLooseDailyPlanResolution

    func planRange(
        healthData: [HealthData],
        dailyOutputOwnerDates: Set<String>,
        settingsSnapshot: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface,
        operationIdentity: AppleExportOperationIdentity?
    ) async throws -> AppleLooseDailyPlanResolution
}

/// Capture-once application planner for one bounded loose-file operation. Shadow supports the
/// wider exact-parity surface; Rust authority is admitted only for summary-only roll-ups. The
/// planner never queries a provider, opens/reads a destination, or performs filesystem/network I/O.
@MainActor
final class AppleLooseDailyExportPlanner: AppleLooseDailyRangeExportPlanning {
    typealias DiagnosticSink = @Sendable (ShadowExportDiagnostic) async -> Void

    private let policyResolver: AppleExportEnginePolicyResolver
    private let coreExecutor: any AppleLooseDailyCoreExecuting
    private let identitySource: AppleExportOperationIdentitySource
    private let comparisonOptions: NativeExportComparisonOptions
    /// Fault-injection seam called immediately before shadow opens any native renderer.
    private let nativeRendererPreflight: @MainActor @Sendable () throws -> Void
    private let diagnosticSink: DiagnosticSink

    init(
        policyResolver: AppleExportEnginePolicyResolver = AppleExportEnginePolicyResolver(),
        coreExecutor: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(),
        identitySource: AppleExportOperationIdentitySource? = nil,
        comparisonOptions: NativeExportComparisonOptions = NativeExportComparisonOptions(),
        nativeRendererPreflight: @escaping @MainActor @Sendable () throws -> Void = {},
        diagnosticSink: @escaping DiagnosticSink = ShadowExportEvidenceRecorder.productionSink
    ) {
        self.policyResolver = policyResolver
        self.coreExecutor = coreExecutor
        self.identitySource = identitySource ?? AppleExportOperationIdentitySource()
        self.comparisonOptions = comparisonOptions
        self.nativeRendererPreflight = nativeRendererPreflight
        self.diagnosticSink = diagnosticSink
    }

    func plan(
        healthData: HealthData,
        settingsSnapshot: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface
    ) async throws -> AppleLooseDailyPlanResolution {
        try await planRange(
            healthData: [healthData],
            settingsSnapshot: settingsSnapshot,
            surface: surface
        )
    }

    func planRange(
        healthData records: [HealthData],
        settingsSnapshot: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface
    ) async throws -> AppleLooseDailyPlanResolution {
        let calendarTimeZoneIdentifier = settingsSnapshot.calendarTimeZoneIdentifier ?? ""
        let outputDates = Set(records.map {
            HealthKitDailyOwnershipMetadata.ownerDate(
                for: $0.date,
                calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
            )
        })
        return try await planRange(
            healthData: records,
            dailyOutputOwnerDates: outputDates,
            settingsSnapshot: settingsSnapshot,
            surface: surface,
            operationIdentity: nil
        )
    }

    func planRange(
        healthData records: [HealthData],
        dailyOutputOwnerDates: Set<String>,
        settingsSnapshot: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface,
        operationIdentity suppliedOperationIdentity: AppleExportOperationIdentity? = nil
    ) async throws -> AppleLooseDailyPlanResolution {
        guard !records.isEmpty else { return .legacy }
        let calendarTimeZoneIdentifier = settingsSnapshot.calendarTimeZoneIdentifier ?? ""
        let orderedRecords = records.sorted {
            HealthKitDailyOwnershipMetadata.ownerDate(
                for: $0.date,
                calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
            ) < HealthKitDailyOwnershipMetadata.ownerDate(
                for: $1.date,
                calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
            )
        }
        let ownerDates = orderedRecords.map {
            HealthKitDailyOwnershipMetadata.ownerDate(
                for: $0.date,
                calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
            )
        }
        guard Set(ownerDates).count == ownerDates.count,
              (!dailyOutputOwnerDates.isEmpty ||
                  settingsSnapshot.generateWeeklyRollups ||
                  settingsSnapshot.generateMonthlyRollups ||
                  settingsSnapshot.generateYearlyRollups),
              dailyOutputOwnerDates.isSubset(of: Set(ownerDates)) else {
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }
        let suppliedPin = settingsSnapshot.appleExportEnginePin
        let requestedMode: ExportEngineMode
        if let suppliedPin {
            requestedMode = suppliedPin.engine
        } else if settingsSnapshot.appleExportEngineAuthorityIsFrozen
                    || surface == .connectedReceivedFilesWithoutSideEffects
                    || surface == .connectedReceivedRangeWithoutSideEffects {
            // A durable snapshot is already the authority decision. A missing pin is explicit
            // legacy and must never inherit a changed process-wide rollout default on resume.
            requestedMode = .legacy
        } else {
            requestedMode = policyResolver.requestedModeForNewOperation(
                profile: .appleHealthDataV7
            )
        }
        guard requestedMode != .legacy else { return .legacy }
        guard Self.supports(
            healthData: orderedRecords,
            settingsSnapshot: settingsSnapshot,
            surface: surface
        ) else {
            if suppliedPin != nil { throw AppleLooseDailyExportPlannerError.rustPlanningFailed }
            return .legacy
        }
        if requestedMode == .rust,
           !ApplePureRustAuthorityAdmission.supports(
               settings: settingsSnapshot,
               surface: surface
           ) {
            // New unsupported Rust requests resolve wholly to legacy. A persisted Rust pin is an
            // immutable authority promise and must fail closed instead of silently changing engines.
            if suppliedPin != nil { throw AppleLooseDailyExportPlannerError.rustPlanningFailed }
            return .legacy
        }

        guard let calendarTimeZoneIdentifier = settingsSnapshot.calendarTimeZoneIdentifier,
              orderedRecords.allSatisfy({
                  calendarTimeZoneIdentifier == $0.timeContext.calendarTimeZoneIdentifier
              }),
              AppleExportEnginePin.isIANAIdentifier(calendarTimeZoneIdentifier),
              TimeZone(identifier: calendarTimeZoneIdentifier) != nil else {
            if suppliedPin != nil { throw AppleLooseDailyExportPlannerError.rustPlanningFailed }
            return .legacy
        }

        let context: AppleLooseDailyCoreContext
        do {
            context = try await coreExecutor.loadContext()
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if requestedMode == .shadow {
                await emitRustFailure(pin: nil)
                return .legacy
            }
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }

        let pin: AppleExportEnginePin
        if let suppliedPin {
            guard suppliedPin.engine == requestedMode,
                  suppliedPin.calendarTimeZoneIdentifier == calendarTimeZoneIdentifier,
                  suppliedPin.isCompatible(
                      buildInfo: context.buildInfo,
                      registrySnapshot: context.registry
                  ) else {
                throw AppleLooseDailyExportPlannerError.rustPlanningFailed
            }
            pin = suppliedPin
        } else {
            do {
                pin = try AppleExportEnginePin(
                    engine: requestedMode,
                    calendarTimeZoneIdentifier: calendarTimeZoneIdentifier,
                    buildInfo: context.buildInfo,
                    registrySnapshot: context.registry
                )
            } catch is AppleExportEnginePin.CompatibilityError {
                // Packaged-contract incompatibility is a policy gate, not a selected Rust failure.
                return .legacy
            } catch {
                return .legacy
            }
        }

        let identity = suppliedOperationIdentity ?? identitySource.capture(
            calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
        )
        guard !identity.requestID.isEmpty,
              !identity.sessionID.isEmpty,
              identity.calendarTimeZoneIdentifier == calendarTimeZoneIdentifier else {
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }
        let frozenSettings = settingsSnapshot.makeAdvancedExportSettings(
            userDefaults: UserDefaults()
        )
        frozenSettings.exportTimeZoneOverride = TimeZone(
            identifier: calendarTimeZoneIdentifier
        )
        let preparedExports = orderedRecords.map {
            $0.preparedExport(settings: frozenSettings)
        }
        guard preparedExports.contains(where: \.hasAnyData),
              zip(ownerDates, preparedExports).allSatisfy({ pair in
                  !dailyOutputOwnerDates.contains(pair.0) || pair.1.hasAnyData
              }) else {
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }
        var expectedOutputs: [ExpectedOutput] = []
        let nativePlan: NativeExportArtifactPlan?
        if requestedMode == .shadow {
            // Shadow intentionally invokes both renderers; native bytes remain authoritative.
            try nativeRendererPreflight()
            expectedOutputs = try Self.expectedOutputs(
                preparedExports: preparedExports,
                dailyOutputOwnerDates: dailyOutputOwnerDates,
                sourceHealthData: orderedRecords,
                settings: frozenSettings,
                healthSubfolder: settingsSnapshot.healthSubfolder ?? "",
                generatedAt: identity.capturedAt,
                calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
            )
            guard let planned = try? Self.makeNativePlan(
                outputs: expectedOutputs,
                identity: identity,
                pin: pin
            ) else {
                // Shadow is native-authoritative. It cannot proceed without a complete native plan.
                if suppliedPin != nil { throw AppleLooseDailyExportPlannerError.rustPlanningFailed }
                return .legacy
            }
            nativePlan = planned
        } else {
            // Rust authority must not invoke or depend on a legacy renderer.
            nativePlan = nil
        }

        let rustPlan: NativeExportArtifactPlan
        do {
            let semanticConfiguration = try HealthMdSemanticInputAdapter.sessionConfiguration(
                sessionID: identity.sessionID,
                selection: frozenSettings.metricSelection,
                registry: context.registry,
                customization: frozenSettings.formatCustomization,
                calendarTimeZoneIdentifier: calendarTimeZoneIdentifier,
                retainPlatformExtensions: false,
                rollupPeriods: frozenSettings.enabledRollupPeriods
            )
            let semanticBatches = try HealthMdSemanticInputAdapter.boundedBatches(
                sessionID: identity.sessionID,
                healthData: orderedRecords,
                registry: context.registry,
                customization: frozenSettings.formatCustomization,
                calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
            )
            let semanticResult = try await coreExecutor.processSemantic(
                configuration: semanticConfiguration,
                batches: semanticBatches.map(\.data)
            )

            var renderOptions = HealthMdRenderInputAdapter.Options(
                requestID: identity.requestID,
                formats: frozenSettings.exportFormats
                    .sorted(by: { $0.rawValue < $1.rawValue })
                    .map(Self.renderFormatIdentifier)
            )
            renderOptions.unitSystem = frozenSettings.formatCustomization.unitPreference == .imperial
                ? "imperial"
                : "metric"
            renderOptions.includeMetadata = frozenSettings.includeMetadata
            renderOptions.groupByCategory = frozenSettings.groupByCategory
            renderOptions.includePlatformExtensions = false
            let captureStatuses = Set(preparedExports.map {
                Self.rawCaptureStatusIdentifier($0.filteredData.healthKitRecordCaptureStatus)
            })
            guard captureStatuses.count == 1, let captureStatus = captureStatuses.first else {
                throw AppleLooseDailyExportPlannerError.rustPlanningFailed
            }
            renderOptions.rawCaptureStatus = captureStatus
            renderOptions.writeMode = "overwrite"
            if !frozenSettings.enabledRollupPeriods.isEmpty {
                renderOptions.rollupGeneratedAt = HealthRollupDateFormatting.timestampString(
                    identity.capturedAt
                )
            }
            renderOptions.baseDirectory = ExportPathPlanner.normalizedRelativePath(
                settingsSnapshot.healthSubfolder ?? ""
            )
            renderOptions.filenameTemplate = frozenSettings.filenameFormat
            renderOptions.folderTemplate = ExportPathPlanner.normalizedRelativePath(
                frozenSettings.folderStructure
            )
            if frozenSettings.organizeFormatsIntoFolders {
                renderOptions.markdownFolder = ExportFormat.markdown.formatFolderName
                renderOptions.basesFolder = ExportFormat.obsidianBases.formatFolderName
                renderOptions.jsonFolder = ExportFormat.json.formatFolderName
                renderOptions.csvFolder = ExportFormat.csv.formatFolderName
            }

            let presentationByOwnerDate: [String: HealthData]
            if requestedMode == .shadow {
                presentationByOwnerDate = Dictionary(
                    uniqueKeysWithValues: zip(ownerDates, preparedExports.map(\.filteredData))
                )
            } else {
                // Rust authority must not call `toMarkdown`, `toCSVThrowing`, or
                // `toJSONThrowing` through native profile-document capture.
                presentationByOwnerDate = [:]
            }
            let renderInput = try HealthMdRenderInputAdapter.encode(
                semanticResult: semanticResult,
                registry: context.registry,
                calendarTimeZoneIdentifier: calendarTimeZoneIdentifier,
                options: renderOptions,
                presentationByOwnerDate: presentationByOwnerDate,
                allowNativeProfileDocuments: requestedMode == .shadow,
                presentationCustomization: frozenSettings.formatCustomization
            )
            let corePlan = try await coreExecutor.render(
                configuration: renderInput.configuration,
                semanticResult: semanticResult,
                batches: renderInput.batches
            )
            let completeRustPlan = try CoreArtifactPlanConverter.convert(corePlan, pin: pin)
            if requestedMode == .shadow {
                rustPlan = try Self.filterPlan(
                    completeRustPlan,
                    expectedRelativePaths: Set(expectedOutputs.map(\.relativePath)),
                    pin: pin
                )
            } else {
                rustPlan = try Self.filterPureRustRollupPlan(
                    completeRustPlan,
                    healthSubfolder: settingsSnapshot.healthSubfolder ?? "",
                    pin: pin
                )
                expectedOutputs = try Self.pureRustRollupOutputs(
                    from: rustPlan,
                    semanticResult: semanticResult,
                    settings: settingsSnapshot,
                    healthSubfolder: settingsSnapshot.healthSubfolder ?? ""
                )
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if requestedMode == .shadow {
                await emitRustFailure(pin: pin)
                let shadowNativePlan = try Self.requireShadowNativePlan(nativePlan)
                return try Self.plannedOperation(
                    authority: .shadow,
                    identity: identity,
                    pin: pin,
                    nativePlan: shadowNativePlan,
                    selectedPlan: shadowNativePlan,
                    expectedOutputs: expectedOutputs
                )
            }
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }

        switch requestedMode {
        case .shadow:
            let shadowNativePlan = try Self.requireShadowNativePlan(nativePlan)
            let diagnostics = NativeExportPlanComparator.compare(
                native: shadowNativePlan,
                rust: rustPlan,
                pin: pin,
                options: comparisonOptions
            )
            await diagnosticSink(.comparisonCompleted(
                ShadowExportComparisonCompletedDiagnostic(
                    profile: AppleExportEnginePin.profileID,
                    semanticProfileRevision: pin.semanticProfileRevision,
                    renderProfileRevision: pin.renderProfileRevision,
                    matches: diagnostics.isEmpty,
                    mismatchCount: UInt32(clamping: diagnostics.count)
                )
            ))
            for diagnostic in diagnostics {
                await diagnosticSink(.planMismatch(diagnostic))
            }
            return try Self.plannedOperation(
                authority: .shadow,
                identity: identity,
                pin: pin,
                nativePlan: shadowNativePlan,
                selectedPlan: shadowNativePlan,
                expectedOutputs: expectedOutputs
            )
        case .rust:
            do {
                return try Self.plannedOperation(
                    authority: .rust,
                    identity: identity,
                    pin: pin,
                    nativePlan: nativePlan,
                    selectedPlan: rustPlan,
                    expectedOutputs: expectedOutputs
                )
            } catch {
                throw AppleLooseDailyExportPlannerError.rustPlanningFailed
            }
        case .legacy:
            return .legacy
        }
    }

    static func supports(
        healthData: HealthData,
        settingsSnapshot: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface
    ) -> Bool {
        supports(
            healthData: [healthData],
            settingsSnapshot: settingsSnapshot,
            surface: surface
        )
    }

    static func supports(
        healthData: [HealthData],
        settingsSnapshot: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface
    ) -> Bool {
        !healthData.isEmpty
            && supports(settingsSnapshot: settingsSnapshot, surface: surface)
            && healthData.allSatisfy {
                $0.healthKitRecordArchive == nil
                    && settingsSnapshot.calendarTimeZoneIdentifier
                        == $0.timeContext.calendarTimeZoneIdentifier
            }
    }

    /// Settings-only half of the strict simple-operation gate. Connected receivers use it before
    /// accepting streamed work, then repeat the complete immutable-record gate before each write.
    static func supports(
        settingsSnapshot: ExportSettingsSnapshot,
        surface: AppleExportOperationSurface
    ) -> Bool {
        let hasConfiguredRollups = settingsSnapshot.generateWeeklyRollups
            || settingsSnapshot.generateMonthlyRollups
            || settingsSnapshot.generateYearlyRollups
        let isRangeSurface = surface == .localVaultRangeWithoutSideEffects
            || surface == .directGeneratedFilesWithoutSideEffects
            || surface == .connectedReceivedRangeWithoutSideEffects
        let isSummaryOnly = settingsSnapshot.summaryOnlyExport
            && hasConfiguredRollups
            && !settingsSnapshot.exportFormats.isEmpty
        guard surface == .localVaultWithoutSideEffects
                || surface == .localVaultRangeWithoutSideEffects
                || surface == .directGeneratedFilesWithoutSideEffects
                || surface == .connectedReceivedFilesWithoutSideEffects
                || surface == .connectedReceivedRangeWithoutSideEffects
                || surface == .preview,
              settingsSnapshot.healthSubfolder != nil,
              let calendarTimeZoneIdentifier = settingsSnapshot.calendarTimeZoneIdentifier,
              AppleExportEnginePin.isIANAIdentifier(calendarTimeZoneIdentifier),
              TimeZone(identifier: calendarTimeZoneIdentifier) != nil,
              settingsSnapshot.writeMode == .overwrite,
              !settingsSnapshot.exportFormats.isEmpty,
              settingsSnapshot.exportFormats.isSubset(of: Set(ExportFormat.allCases)),
              !settingsSnapshot.archiveExportFiles,
              (!settingsSnapshot.summaryOnlyExport || (isSummaryOnly && isRangeSurface)),
              !settingsSnapshot.includeGranularData,
              (!hasConfiguredRollups || isRangeSurface),
              !settingsSnapshot.dailyNoteInjection.enabled,
              !settingsSnapshot.individualTracking.globalEnabled else {
            return false
        }
        return true
    }

    private func emitRustFailure(pin: AppleExportEnginePin?) async {
        await diagnosticSink(.rustRenderFailed(ShadowExportFailureDiagnostic(
            profile: AppleExportEnginePin.profileID,
            semanticProfileRevision: pin?.semanticProfileRevision ?? 1,
            renderProfileRevision: pin?.renderProfileRevision ?? 1,
            kind: .rustRenderFailed
        )))
    }

    private static func requireShadowNativePlan(
        _ plan: NativeExportArtifactPlan?
    ) throws -> NativeExportArtifactPlan {
        guard let plan else {
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }
        return plan
    }

    private struct ExpectedOutput {
        let kind: AppleLooseDailyArtifactKind
        let format: ExportFormat
        let relativePath: String
        /// Present only for shadow's native-authoritative plan. Rust authority carries descriptors
        /// derived from the selected Rust plan and never asks a native renderer for bytes.
        let nativeContent: String?
    }

    private static func expectedOutputs(
        preparedExports: [PreparedHealthDataExport],
        dailyOutputOwnerDates: Set<String>,
        sourceHealthData: [HealthData],
        settings: AdvancedExportSettings,
        healthSubfolder: String,
        generatedAt: Date,
        calendarTimeZoneIdentifier: String
    ) throws -> [ExpectedOutput] {
        let root = URL(fileURLWithPath: "/__HealthMdPlanningRoot__", isDirectory: true)
        let daily = try preparedExports.flatMap { preparedExport -> [ExpectedOutput] in
            let ownerDate = HealthKitDailyOwnershipMetadata.ownerDate(
                for: preparedExport.filteredData.date,
                calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
            )
            guard dailyOutputOwnerDates.contains(ownerDate) else { return [] }
            return try ExportPathPlanner.aggregateOutputTargets(
                vaultURL: root,
                healthSubfolder: healthSubfolder,
                settings: settings,
                date: preparedExport.filteredData.date
            ).map { target in
                ExpectedOutput(
                    kind: .daily,
                    format: target.format,
                    relativePath: target.relativePath,
                    nativeContent: try preparedExport.content(
                        format: target.format,
                        settings: settings
                    )
                )
            }
        }
        guard !settings.enabledRollupPeriods.isEmpty else { return daily }
        var calendar = Calendar.current
        calendar.timeZone = TimeZone(identifier: calendarTimeZoneIdentifier) ?? .gmt
        let summaries = HealthRollupExporter.makeSummaries(
            from: sourceHealthData,
            settings: settings,
            periods: settings.enabledRollupPeriods,
            generatedAt: generatedAt,
            calendar: calendar
        )
        let rollups = HealthRollupExporter.outputTargets(
            for: summaries,
            healthSubfolder: healthSubfolder,
            settings: settings
        ).map {
            ExpectedOutput(
                kind: .rollup,
                format: $0.format,
                relativePath: $0.relativePath,
                nativeContent: $0.content
            )
        }
        return daily + rollups
    }

    private static func makeNativePlan(
        outputs: [ExpectedOutput],
        identity: AppleExportOperationIdentity,
        pin: AppleExportEnginePin
    ) throws -> NativeExportArtifactPlan {
        let artifacts = try outputs.map { output in
            guard let nativeContent = output.nativeContent else {
                throw AppleLooseDailyExportPlannerError.rustPlanningFailed
            }
            let data = Data(nativeContent.utf8)
            let digest = NativeExportArtifact.sha256(of: data)
            let mediaType = mediaType(for: output.format)
            let writeMode = CoreArtifactWriteMode.overwrite
            return try NativeExportArtifact(
                role: .file,
                id: NativeExportArtifactPlan.artifactID(
                    requestID: identity.requestID,
                    sessionID: identity.sessionID,
                    profile: .appleHealthDataV7,
                    relativePath: output.relativePath,
                    mediaType: mediaType,
                    writeMode: writeMode,
                    contentSHA256: digest
                ),
                relativePath: output.relativePath,
                mediaType: mediaType,
                writeMode: writeMode,
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

    private static func filterPlan(
        _ plan: NativeExportArtifactPlan,
        expectedRelativePaths: Set<String>,
        pin: AppleExportEnginePin
    ) throws -> NativeExportArtifactPlan {
        let artifacts = plan.artifacts.filter { expectedRelativePaths.contains($0.relativePath) }
        guard artifacts.count == expectedRelativePaths.count else {
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }
        return try NativeExportArtifactPlan(
            artifactPlanVersion: plan.artifactPlanVersion,
            requestID: plan.requestID,
            sessionID: plan.sessionID,
            profile: plan.profile,
            artifacts: artifacts,
            totalByteCount: artifacts.reduce(0) { $0 + $1.byteCount },
            pin: pin
        )
    }

    private static func filterPureRustRollupPlan(
        _ plan: NativeExportArtifactPlan,
        healthSubfolder: String,
        pin: AppleExportEnginePin
    ) throws -> NativeExportArtifactPlan {
        let prefix = rollupPathPrefix(healthSubfolder: healthSubfolder)
        let artifacts = plan.artifacts.filter { $0.relativePath.hasPrefix(prefix) }
        return try NativeExportArtifactPlan(
            artifactPlanVersion: plan.artifactPlanVersion,
            requestID: plan.requestID,
            sessionID: plan.sessionID,
            profile: plan.profile,
            artifacts: artifacts,
            totalByteCount: artifacts.reduce(0) { $0 + $1.byteCount },
            pin: pin
        )
    }

    private static func pureRustRollupOutputs(
        from plan: NativeExportArtifactPlan,
        semanticResult: Data,
        settings: ExportSettingsSnapshot,
        healthSubfolder: String
    ) throws -> [ExpectedOutput] {
        guard let root = try JSONSerialization.jsonObject(with: semanticResult) as? [String: Any],
              root["schema"] as? String == "healthmd.semantic_result",
              root["state"] as? String == "completed",
              let rollups = root["rollups"] as? [[String: Any]] else {
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }
        let prefix = rollupPathPrefix(healthSubfolder: healthSubfolder)
        let formats = settings.exportFormats.sorted { $0.rawValue < $1.rawValue }
        var expectedFormatsByPath: [String: ExportFormat] = [:]
        for rollup in rollups {
            guard let period = rollup["period"] as? String,
                  let startDate = rollup["start_date"] as? String else {
                throw AppleLooseDailyExportPlannerError.rustPlanningFailed
            }
            let (periodFolder, periodIdentifier) = try pureRustPeriodPath(
                period: period,
                startDate: startDate,
                settings: settings
            )
            for format in formats {
                let formatFolder = settings.organizeFormatsIntoFolders
                    ? "\(format.formatFolderName)/"
                    : ""
                let basesSuffix = format == .obsidianBases
                    && !settings.organizeFormatsIntoFolders ? "-bases" : ""
                let path = "\(prefix)\(formatFolder)\(periodFolder)/"
                    + "\(periodIdentifier)\(basesSuffix).\(format.fileExtension)"
                guard expectedFormatsByPath.updateValue(format, forKey: path) == nil else {
                    throw AppleLooseDailyExportPlannerError.rustPlanningFailed
                }
            }
        }
        guard plan.artifacts.count == expectedFormatsByPath.count else {
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }
        return try plan.artifacts.map { artifact in
            guard artifact.role == .file,
                  let format = expectedFormatsByPath[artifact.relativePath],
                  artifact.mediaType == mediaType(for: format),
                  artifact.writeMode == .overwrite else {
                throw AppleLooseDailyExportPlannerError.rustPlanningFailed
            }
            return ExpectedOutput(
                kind: .rollup,
                format: format,
                relativePath: artifact.relativePath,
                nativeContent: nil
            )
        }
    }

    private static func pureRustPeriodPath(
        period: String,
        startDate: String,
        settings: ExportSettingsSnapshot
    ) throws -> (folder: String, identifier: String) {
        let pieces = startDate.split(separator: "-", omittingEmptySubsequences: false)
        guard pieces.count == 3,
              pieces[0].count == 4,
              pieces[1].count == 2,
              pieces[2].count == 2,
              let year = Int(pieces[0]),
              let month = Int(pieces[1]),
              let day = Int(pieces[2]) else {
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }
        var calendar = Calendar(identifier: .iso8601)
        calendar.timeZone = .gmt
        var dateComponents = DateComponents()
        dateComponents.calendar = calendar
        dateComponents.timeZone = .gmt
        dateComponents.year = year
        dateComponents.month = month
        dateComponents.day = day
        guard let date = calendar.date(from: dateComponents),
              calendar.component(.year, from: date) == year,
              calendar.component(.month, from: date) == month,
              calendar.component(.day, from: date) == day else {
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }
        switch period {
        case "iso_week":
            guard settings.generateWeeklyRollups,
                  calendar.component(.weekday, from: date) == 2 else {
                throw AppleLooseDailyExportPlannerError.rustPlanningFailed
            }
            return (
                "Weekly",
                String(
                    format: "%04d-W%02d",
                    calendar.component(.yearForWeekOfYear, from: date),
                    calendar.component(.weekOfYear, from: date)
                )
            )
        case "calendar_month":
            guard settings.generateMonthlyRollups, day == 1 else {
                throw AppleLooseDailyExportPlannerError.rustPlanningFailed
            }
            return ("Monthly", String(format: "%04d-%02d", year, month))
        case "calendar_year":
            guard settings.generateYearlyRollups, month == 1, day == 1 else {
                throw AppleLooseDailyExportPlannerError.rustPlanningFailed
            }
            return ("Yearly", String(format: "%04d", year))
        default:
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }
    }

    private static func rollupPathPrefix(healthSubfolder: String) -> String {
        let base = ExportPathPlanner.normalizedRelativePath(healthSubfolder)
        return base.isEmpty ? "Rollups/" : "\(base)/Rollups/"
    }

    private static func plannedOperation(
        authority: ExportEngineMode,
        identity: AppleExportOperationIdentity,
        pin: AppleExportEnginePin,
        nativePlan: NativeExportArtifactPlan?,
        selectedPlan: NativeExportArtifactPlan,
        expectedOutputs: [ExpectedOutput]
    ) throws -> AppleLooseDailyPlanResolution {
        guard selectedPlan.requestID == identity.requestID,
              selectedPlan.sessionID == identity.sessionID,
              selectedPlan.artifacts.count == expectedOutputs.count else {
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }

        let artifacts = try zip(expectedOutputs, selectedPlan.artifacts).map { output, artifact in
            guard artifact.role == .file,
                  artifact.relativePath == output.relativePath,
                  artifact.mediaType == mediaType(for: output.format),
                  artifact.writeMode == .overwrite else {
                throw AppleLooseDailyExportPlannerError.rustPlanningFailed
            }
            return AppleLooseDailyPlannedArtifact(
                kind: output.kind,
                format: output.format,
                artifact: artifact
            )
        }
        return .planned(AppleLooseDailyPlannedOperation(
            authority: authority,
            identity: identity,
            pin: pin,
            nativePlan: nativePlan,
            selectedPlan: selectedPlan,
            artifacts: artifacts
        ))
    }

    private static func renderFormatIdentifier(_ format: ExportFormat) -> String {
        switch format {
        case .markdown: "markdown"
        case .obsidianBases: "obsidian_bases"
        case .json: "json"
        case .csv: "csv"
        }
    }

    private static func mediaType(for format: ExportFormat) -> String {
        switch format {
        case .markdown, .obsidianBases: "text/markdown; charset=utf-8"
        case .json: "application/json"
        case .csv: "text/csv; charset=utf-8"
        }
    }

    private static func rawCaptureStatusIdentifier(
        _ status: HealthKitRecordCaptureStatus
    ) -> String {
        switch status {
        case .complete: "complete"
        case .partial: "partial"
        case .notRequested: "not_requested"
        case .legacyUnavailable: "legacy_unavailable"
        }
    }
}

nonisolated struct AppleLooseDailyPreviewArtifact: Equatable, Sendable {
    let format: ExportFormat
    let relativePath: String
    let data: Data
}

/// Async, destination-free helper used by preview UI. `nil` means the operation is deliberately
/// legacy; a Rust planning failure is thrown and never converted into a legacy preview.
@MainActor
enum AppleLooseDailyExportPreviewPlanner {
    static func artifacts(
        healthData: HealthData,
        settingsSnapshot: ExportSettingsSnapshot,
        planner: any AppleLooseDailyExportPlanning
    ) async throws -> [AppleLooseDailyPreviewArtifact]? {
        switch try await planner.plan(
            healthData: healthData,
            settingsSnapshot: settingsSnapshot,
            surface: .preview
        ) {
        case .legacy:
            return nil
        case .planned(let operation):
            return operation.artifacts.map {
                AppleLooseDailyPreviewArtifact(
                    format: $0.format,
                    relativePath: $0.artifact.relativePath,
                    data: $0.artifact.inlineData
                )
            }
        }
    }
}
