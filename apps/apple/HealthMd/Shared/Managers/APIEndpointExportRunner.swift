import Foundation
import HealthMdCoreRust

/// Testable API Endpoint export pipeline shared by manual and scheduled exports.
/// It captures one HealthKit day at a time and performs sequential uploads
/// bounded by both calendar-day count and the exact encoded envelope size.
@MainActor
struct APIEndpointExportRunner {
    typealias HealthDataFetcher = HealthKitDailyCapture.HealthDataFetcher
    typealias ExternalDailyRecordFetcher = HealthKitDailyCapture.ExternalDailyRecordFetcher

    /// Compatibility seam used by existing tests and custom runners.
    typealias Uploader = (
        _ records: [HealthData],
        _ failedDateDetails: [FailedDateDetail],
        _ externalRecords: [ExternalDailyRecord],
        _ settings: AdvancedExportSettings,
        _ destination: APIExportDestinationSnapshot,
        _ dateRangeStart: Date,
        _ dateRangeEnd: Date
    ) async throws -> APIExportUploadResult

    struct PreparedBatch {
        let requestedDates: [Date]
        let records: [HealthData]
        let failedDateDetails: [FailedDateDetail]
        let externalRecords: [ExternalDailyRecord]
        /// Exact number of provider records encoded in bodyArtifact.
        let externalRecordPayloadCount: Int
        let dateRangeStart: Date
        let dateRangeEnd: Date
        let exportedAt: Date
        /// The exact body measured for batching and sent on the wire.
        let bodyArtifact: ExportArtifactFile

        var bodyByteCount: UInt64 { bodyArtifact.descriptor.byteCount }
        /// Compatibility materialization for preview and existing tests. Upload
        /// and commit paths consume `bodyArtifact` directly.
        var body: Data {
            do {
                return try bodyArtifact.materializedData()
            } catch {
                preconditionFailure("Prepared API artifact became unreadable before commit")
            }
        }
    }

    typealias PreparedUploader = (
        _ batch: PreparedBatch,
        _ destination: APIExportDestinationSnapshot
    ) async throws -> APIExportUploadResult

    /// Called after each requested date has been fetched (successfully or not).
    typealias ProgressHandler = (_ datesProcessed: Int, _ totalDates: Int) -> Void
    typealias EngineDiagnosticSink = @Sendable (ShadowExportDiagnostic) async -> Void

    /// Complete immutable API operation prepared before a destination can be opened. Preview and
    /// tests consume this value directly; only `commitPreparedOperation` performs HTTP effects.
    struct PreparedOperation {
        let authority: ExportEngineMode
        let identity: AppleExportOperationIdentity
        let pin: AppleExportEnginePin
        let settingsSnapshot: ExportSettingsSnapshot
        let destination: APIExportDestinationSnapshot
        /// Comparison authority for historical shadow work; successor Rust work has none.
        let nativePlan: NativeExportArtifactPlan?
        /// Present when the shared renderer completed, including shadow mode where it is never sent.
        let rustPlan: NativeExportArtifactPlan?
        let selectedPlan: NativeExportArtifactPlan
        let batches: [PreparedBatch]
        let normalizedDates: [Date]
        let failedDateDetails: [FailedDateDetail]
        let partialFailures: [ExportPartialFailure]
        let calendar: Calendar
    }

    enum PreparationResolution {
        case legacy
        case prepared(PreparedOperation)
    }

    enum EngineError: String, Error, Equatable {
        case rustPlanningFailed = "rust_planning_failed"
        case invalidPreparedPlan = "invalid_prepared_api_plan"
    }

    private static let maximumSharedCoreDateCount = 400

    /// One daily outcome with expensive JSON bytes prepared exactly once.
    /// Candidate batch sizing sums immutable fragments without re-filtering,
    /// re-encoding, or copying canonical daily records into throwaway bodies.
    private struct PreparedOutcome {
        let sourceDate: Date
        let record: HealthData?
        let recordArtifact: ExportArtifactFile?
        let failure: FailedDateDetail?
        let failureData: Data?
        let externalRecords: [ExternalDailyRecord]
        let externalRecordData: [Data]

        init(
            _ outcome: HealthKitDailyCapture.Outcome,
            settings: AdvancedExportSettings,
            artifactDirectory: URL
        ) throws {
            sourceDate = outcome.sourceDate
            record = outcome.record
            if settings.executionSleepCaptureContext?.sleepDayAttribution == .morningEnds {
                recordArtifact = nil
            } else {
                recordArtifact = try outcome.record.map {
                    // HealthKitDailyCapture already applied this exact selection.
                    // Stream compact canonical bytes once into an immutable spool.
                    try APIExportClient.makeSelectedRecordJSONArtifact(
                        $0, settings: settings, directoryURL: artifactDirectory
                    )
                }
            }
            failure = outcome.failure
            failureData = try outcome.failure.map {
                try APIExportClient.makeJSONData(from: $0)
            }
            // Keep compatibility callbacks and result counts on the complete
            // collected record set. Only the immutable wire fragments apply
            // `shouldExport`, matching APIExportClient's established payload
            // filtering behavior.
            externalRecords = outcome.externalDailyRecords
            externalRecordData = try externalRecords.filter(\.shouldExport).map {
                try APIExportClient.makeJSONData(from: $0)
            }
        }

        init(copying source: PreparedOutcome, recordArtifact: ExportArtifactFile?) {
            self.sourceDate = source.sourceDate
            self.record = source.record
            self.recordArtifact = recordArtifact
            self.failure = source.failure
            self.failureData = source.failureData
            self.externalRecords = source.externalRecords
            self.externalRecordData = source.externalRecordData
        }
    }

    private struct AccumulatingBatch {
        let exportedAt: Date
        var requestedDates: [Date] = []
        var records: [HealthData] = []
        var recordArtifacts: [ExportArtifactFile] = []
        var failedDateDetails: [FailedDateDetail] = []
        var failedDateData: [Data] = []
        var externalRecords: [ExternalDailyRecord] = []
        var externalRecordData: [Data] = []
        let connectedAppsEnabled: Bool
        let calendarTimeZone: TimeZone
        let artifactDirectory: URL
        let captureContext: AppleSleepCaptureContext?

        init(
            exportedAt: Date = Date(),
            connectedAppsEnabled: Bool,
            calendarTimeZone: TimeZone = .current,
            artifactDirectory: URL,
            captureContext: AppleSleepCaptureContext? = nil
        ) {
            self.exportedAt = exportedAt
            self.connectedAppsEnabled = connectedAppsEnabled
            self.calendarTimeZone = calendarTimeZone
            self.artifactDirectory = artifactDirectory
            self.captureContext = captureContext
        }

        mutating func append(_ outcome: PreparedOutcome) {
            requestedDates.append(outcome.sourceDate)
            if let record = outcome.record, let encodedRecord = outcome.recordArtifact {
                records.append(record)
                recordArtifacts.append(encodedRecord)
                externalRecords.append(contentsOf: outcome.externalRecords)
                externalRecordData.append(contentsOf: outcome.externalRecordData)
            } else if let failure = outcome.failure, let encodedFailure = outcome.failureData {
                failedDateDetails.append(failure)
                failedDateData.append(encodedFailure)
            }
        }

        func payloadByteCount() throws -> Int {
            guard let start = requestedDates.first, let end = requestedDates.last else {
                throw APIExportClientError.invalidPayload
            }
            return try APIExportClient.payloadByteCount(
                recordArtifacts: recordArtifacts,
                failedDateData: failedDateData,
                externalRecordData: externalRecordData,
                dateRangeStart: start,
                dateRangeEnd: end,
                exportedAt: exportedAt,
                connectedAppsEnabled: connectedAppsEnabled,
                calendarTimeZone: calendarTimeZone,
                captureContext: captureContext
            )
        }

        func prepared() throws -> PreparedBatch {
            guard let start = requestedDates.first, let end = requestedDates.last else {
                throw APIExportClientError.invalidPayload
            }
            let bodyArtifact = try APIExportClient.makePayloadArtifact(
                recordArtifacts: recordArtifacts,
                failedDateData: failedDateData,
                externalRecordData: externalRecordData,
                dateRangeStart: start,
                dateRangeEnd: end,
                exportedAt: exportedAt,
                connectedAppsEnabled: connectedAppsEnabled,
                calendarTimeZone: calendarTimeZone,
                directoryURL: artifactDirectory,
                captureContext: captureContext
            )
            return PreparedBatch(
                requestedDates: requestedDates,
                records: records,
                failedDateDetails: failedDateDetails,
                externalRecords: externalRecords,
                externalRecordPayloadCount: externalRecordData.count,
                dateRangeStart: start,
                dateRangeEnd: end,
                exportedAt: exportedAt,
                bodyArtifact: bodyArtifact
            )
        }
    }

    /// Calendar bound prevents a request from spanning an unexpectedly broad range.
    nonisolated static let defaultMaxBatchDaySpan = 7
    /// Byte target prevents granular history imports from creating unbounded HTTP
    /// bodies. A single indivisible day may exceed this target and is sent alone.
    nonisolated static let defaultMaxBatchPayloadBytes = 8 * 1_024 * 1_024

    static func export(
        dates: [Date],
        healthKitManager: HealthKitManager,
        settings: AdvancedExportSettings,
        destination: APIExportDestinationSnapshot,
        externalIntegrations: ExternalIntegrationDailyRecordProviding? = nil,
        policyResolver: AppleExportEnginePolicyResolver = AppleExportEnginePolicyResolver(),
        coreExecutor: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(),
        identitySource: AppleExportOperationIdentitySource = AppleExportOperationIdentitySource(),
        comparisonOptions: NativeExportComparisonOptions = NativeExportComparisonOptions(),
        diagnosticSink: @escaping EngineDiagnosticSink = ShadowExportEvidenceRecorder.productionSink,
        onProgress: ProgressHandler? = nil
    ) async -> ExportOrchestrator.ExportResult {
        let awakeActivityID = UUID()
        IdleTimerCoordinator.shared.beginActivity(awakeActivityID)
        defer { IdleTimerCoordinator.shared.endActivity(awakeActivityID) }
        let captureContext: AppleSleepCaptureContext
        do {
            captureContext = try healthKitManager.resolveSleepCaptureContext(settings: settings)
        } catch {
            return ExportOrchestrator.ExportResult(successCount: 0, totalCount: dates.count,
                failedDateDetails: dates.map { FailedDateDetail(date: $0, reason: .unknown, errorDetails: error.localizedDescription) },
                completedDates: [])
        }

        externalIntegrations?.beginExportAction()

        // Freeze process-global/provider decisions and the HealthKit calendar before any capture.
        let connectedAppsEnabled = ConnectedAppsFeature.isEnabled
        let calendarTimeZone = captureContext.timeZone
        let externalFetcher: ExternalDailyRecordFetcher?
        if connectedAppsEnabled,
           let externalIntegrations,
           externalIntegrations.connectedProviderCount > 0 {
            var providerCalendar = Calendar(identifier: .gregorian)
            providerCalendar.timeZone = calendarTimeZone
            externalFetcher = { date in
                await externalIntegrations.fetchDailyRecords(
                    for: date,
                    calendar: providerCalendar
                )
            }
        } else {
            externalFetcher = nil
        }

        let apiClient = APIExportClient()
        let result = await AppleSleepCaptureContext.pinned.withValue(captureContext) {
            await HealthKitQueryExecutionController.withController {
                await exportEngineAware(
                    dates: dates,
                    settings: settings,
                    destination: destination,
                    calendarTimeZone: calendarTimeZone,
                    connectedAppsEnabled: connectedAppsEnabled,
                    fetchHealthData: { date, detailPolicy, metricSelection in
                        try await healthKitManager.fetchHealthData(
                            for: date,
                            detailPolicy: detailPolicy,
                            metricSelection: metricSelection,
                            timeZone: calendarTimeZone,
                            captureContext: captureContext
                        )
                    },
                    fetchExternalDailyRecords: externalFetcher,
                    upload: { batch, destination in
                        try await apiClient.upload(
                            payloadArtifact: batch.bodyArtifact,
                            destination: destination
                        )
                    },
                    maxBatchDaySpan: defaultMaxBatchDaySpan,
                    maxBatchPayloadBytes: defaultMaxBatchPayloadBytes,
                    policyResolver: policyResolver,
                    coreExecutor: coreExecutor,
                    identitySource: identitySource,
                    comparisonOptions: comparisonOptions,
                    diagnosticSink: diagnosticSink,
                    onProgress: onProgress
                )
            }
        }
        externalIntegrations?.endExportAction(
            succeeded: result.didCompleteAllRequestedDates && !result.wasCancelled
        )
        return result
    }

    static func export(
        dates: [Date],
        settings: AdvancedExportSettings,
        apiSettings: APIExportSettings,
        fetchHealthData: HealthDataFetcher,
        fetchExternalDailyRecords: ExternalDailyRecordFetcher? = nil,
        upload: @escaping Uploader,
        maxBatchDaySpan: Int = APIEndpointExportRunner.defaultMaxBatchDaySpan,
        maxBatchPayloadBytes: Int = APIEndpointExportRunner.defaultMaxBatchPayloadBytes,
        onProgress: ProgressHandler? = nil
    ) async -> ExportOrchestrator.ExportResult {
        let awakeActivityID = UUID()
        IdleTimerCoordinator.shared.beginActivity(awakeActivityID)
        defer { IdleTimerCoordinator.shared.endActivity(awakeActivityID) }

        let normalizedDates = HealthKitDailyCapture.normalizedDates(dates)
        guard !normalizedDates.isEmpty else {
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: 0,
                failedDateDetails: [],
                formatsPerDate: 0,
                looseAggregateFileCount: 0,
                isFileCategoryBreakdownComplete: true,
                completedDates: []
            )
        }
        guard let destination = apiSettings.destinationSnapshot else {
            return failureResult(
                dates: normalizedDates,
                reason: .apiEndpointNotConfigured,
                message: APIExportClientError.invalidEndpoint.localizedDescription
            )
        }

        return await HealthKitQueryExecutionController.withController {
            await exportLegacyPrepared(
                dates: normalizedDates,
                settings: settings,
                destination: destination,
                fetchHealthData: fetchHealthData,
                fetchExternalDailyRecords: fetchExternalDailyRecords,
                upload: { batch, destination in
                    try await upload(
                        batch.records,
                        batch.failedDateDetails,
                        batch.externalRecords,
                        settings,
                        destination,
                        batch.dateRangeStart,
                        batch.dateRangeEnd
                    )
                },
                maxBatchDaySpan: maxBatchDaySpan,
                maxBatchPayloadBytes: maxBatchPayloadBytes,
                onProgress: onProgress
            )
        }
    }

    /// Settings-only gate used before a durable scheduled operation captures a nonlegacy pin.
    /// Date contiguity, destination, provider, and encoded-size checks remain request-level gates.
    /// A persisted pin that later fails one of those checks must fail closed rather than downgrade.
    static func supportsNewEnginePin(settingsSnapshot: ExportSettingsSnapshot) -> Bool {
        guard let calendarTimeZoneIdentifier = settingsSnapshot.calendarTimeZoneIdentifier else {
            return false
        }
        return AppleExportEnginePin.isIANAIdentifier(calendarTimeZoneIdentifier)
            && TimeZone(identifier: calendarTimeZoneIdentifier) != nil
            && !settingsSnapshot.dailyNotesOnlyModeEnabled
            && !settingsSnapshot.exportFormats.isEmpty
    }

    private static func requestedMode(
        settings: AdvancedExportSettings,
        policyResolver: AppleExportEnginePolicyResolver
    ) -> ExportEngineMode {
        if let pin = settings.executionAppleExportEnginePin {
            return pin.engine
        }
        if settings.executionAppleExportEngineAuthorityIsFrozen {
            return .legacy
        }
        if (settings.executionSleepCaptureContext ?? AppleSleepCaptureContext.pinned.wrappedValue)?.sleepDayAttribution == .morningEnds {
            return .rust
        }
        return policyResolver.requestedModeForNewOperation(profile: .appleHealthDataV8)
    }

    /// Destination-free preparation seam used by API preview and focused engine tests. A legacy
    /// resolution intentionally performs no capture: the established streaming path remains its
    /// own authority and is invoked only by `exportEngineAware`.
    static func prepare(
        dates: [Date],
        settings: AdvancedExportSettings,
        destination: APIExportDestinationSnapshot,
        calendarTimeZone: TimeZone? = nil,
        connectedAppsEnabled: Bool? = nil,
        fetchHealthData: HealthDataFetcher,
        fetchExternalDailyRecords: ExternalDailyRecordFetcher? = nil,
        maxBatchDaySpan: Int = APIEndpointExportRunner.defaultMaxBatchDaySpan,
        maxBatchPayloadBytes: Int = APIEndpointExportRunner.defaultMaxBatchPayloadBytes,
        policyResolver: AppleExportEnginePolicyResolver = AppleExportEnginePolicyResolver(),
        coreExecutor: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(),
        identitySource: AppleExportOperationIdentitySource = AppleExportOperationIdentitySource(),
        comparisonOptions: NativeExportComparisonOptions = NativeExportComparisonOptions(),
        diagnosticSink: @escaping EngineDiagnosticSink = ShadowExportEvidenceRecorder.productionSink,
        onProgress: ProgressHandler? = nil
    ) async throws -> PreparationResolution {
        let captureContext = settings.executionSleepCaptureContext ?? AppleSleepCaptureContext.pinned.wrappedValue
        let wakeDate = captureContext?.sleepDayAttribution == .morningEnds
        let requestedMode: ExportEngineMode = fetchExternalDailyRecords == nil || wakeDate
            ? requestedMode(settings: settings, policyResolver: policyResolver)
            : .legacy
        guard requestedMode != .legacy else {
            if wakeDate { throw EngineError.rustPlanningFailed }
            return .legacy
        }
        return try await prepareNonLegacy(
            dates: dates,
            settings: settings,
            destination: destination,
            calendarTimeZone: calendarTimeZone ?? settings.exportTimeZoneOverride ?? .current,
            connectedAppsEnabled: connectedAppsEnabled ?? ConnectedAppsFeature.isEnabled,
            fetchHealthData: fetchHealthData,
            fetchExternalDailyRecords: fetchExternalDailyRecords,
            maxBatchDaySpan: maxBatchDaySpan,
            maxBatchPayloadBytes: maxBatchPayloadBytes,
            requestedMode: requestedMode,
            coreExecutor: coreExecutor,
            identitySource: identitySource,
            comparisonOptions: comparisonOptions,
            diagnosticSink: diagnosticSink,
            onProgress: onProgress
        )
    }

    /// Reuses already-captured preview records so opening Export Preview never repeats HealthKit
    /// reads. A nonlegacy result contains the same immutable request bodies that production would
    /// commit; `nil` is explicit legacy authority and performs no upload or other external effect.
    static func preparePreview(
        records: [HealthData],
        settings: AdvancedExportSettings,
        destination: APIExportDestinationSnapshot,
        calendarTimeZone: TimeZone,
        connectedAppsEnabled: Bool,
        fetchExternalDailyRecords: ExternalDailyRecordFetcher? = nil,
        policyResolver: AppleExportEnginePolicyResolver = AppleExportEnginePolicyResolver(),
        coreExecutor: any AppleLooseDailyCoreExecuting = SystemAppleLooseDailyCoreExecutor(),
        identitySource: AppleExportOperationIdentitySource = AppleExportOperationIdentitySource(),
        comparisonOptions: NativeExportComparisonOptions = NativeExportComparisonOptions(),
        diagnosticSink: @escaping EngineDiagnosticSink = ShadowExportEvidenceRecorder.productionSink
    ) async throws -> PreparedOperation? {
        guard !records.isEmpty else { return nil }
        let timeZoneIdentifier = calendarTimeZone.identifier
        var recordsByOwnerDate: [String: HealthData] = [:]
        for record in records {
            let ownerDate = HealthKitDailyOwnershipMetadata.ownerDate(
                for: record.date,
                calendarTimeZoneIdentifier: timeZoneIdentifier
            )
            guard recordsByOwnerDate.updateValue(record, forKey: ownerDate) == nil else {
                throw EngineError.invalidPreparedPlan
            }
        }

        let resolution = try await prepare(
            dates: records.map(\.date),
            settings: settings,
            destination: destination,
            calendarTimeZone: calendarTimeZone,
            connectedAppsEnabled: connectedAppsEnabled,
            fetchHealthData: { date, _, _ in
                let ownerDate = HealthKitDailyOwnershipMetadata.ownerDate(
                    for: date,
                    calendarTimeZoneIdentifier: timeZoneIdentifier
                )
                guard let record = recordsByOwnerDate[ownerDate] else {
                    throw EngineError.invalidPreparedPlan
                }
                return record
            },
            fetchExternalDailyRecords: fetchExternalDailyRecords,
            policyResolver: policyResolver,
            coreExecutor: coreExecutor,
            identitySource: identitySource,
            comparisonOptions: comparisonOptions,
            diagnosticSink: diagnosticSink
        )
        switch resolution {
        case .legacy:
            return nil
        case .prepared(let operation):
            return operation
        }
    }

    static func exportEngineAware(
        dates: [Date],
        settings: AdvancedExportSettings,
        destination: APIExportDestinationSnapshot,
        calendarTimeZone: TimeZone,
        connectedAppsEnabled: Bool,
        fetchHealthData: HealthDataFetcher,
        fetchExternalDailyRecords: ExternalDailyRecordFetcher?,
        upload: @escaping PreparedUploader,
        maxBatchDaySpan: Int,
        maxBatchPayloadBytes: Int,
        policyResolver: AppleExportEnginePolicyResolver,
        coreExecutor: any AppleLooseDailyCoreExecuting,
        identitySource: AppleExportOperationIdentitySource,
        comparisonOptions: NativeExportComparisonOptions,
        diagnosticSink: @escaping EngineDiagnosticSink,
        onProgress: ProgressHandler?
    ) async -> ExportOrchestrator.ExportResult {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = calendarTimeZone
        let normalizedDates = HealthKitDailyCapture.normalizedDates(dates, calendar: calendar)
        guard !normalizedDates.isEmpty else {
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: 0,
                failedDateDetails: [],
                formatsPerDate: 0,
                looseAggregateFileCount: 0,
                isFileCategoryBreakdownComplete: true,
                completedDates: []
            )
        }
        guard !settings.dailyNotesOnlyModeEnabled else {
            return failureResult(
                dates: normalizedDates,
                reason: .unknown,
                message: "Daily Notes Only requires a filesystem destination and cannot export to an API endpoint."
            )
        }
        guard !settings.exportFormats.isEmpty else {
            return failureResult(
                dates: normalizedDates,
                reason: .unknown,
                message: "Select at least one export format before exporting to an API endpoint."
            )
        }

        // This is the only authority read for the operation and occurs before either HealthKit or
        // a provider can be called. Persisted pins, including explicit nil/legacy authority, take
        // precedence over current rollout defaults. Provider-bearing v8 days remain
        // native-authoritative so the typed section cannot be dropped by an older path.
        let wakeDate = (settings.executionSleepCaptureContext ?? AppleSleepCaptureContext.pinned.wrappedValue)?.sleepDayAttribution == .morningEnds
            || settings.executionAppleExportEnginePin?.isWakeDate == true
        let requestedMode: ExportEngineMode = fetchExternalDailyRecords == nil || wakeDate
            ? requestedMode(settings: settings, policyResolver: policyResolver)
            : .legacy
        guard requestedMode != .legacy else {
            if wakeDate { return failureResult(dates: normalizedDates, reason: .unknown, message: EngineError.rustPlanningFailed.rawValue) }
            return await exportLegacyPrepared(
                dates: dates,
                settings: settings,
                destination: destination,
                fetchHealthData: fetchHealthData,
                fetchExternalDailyRecords: fetchExternalDailyRecords,
                upload: upload,
                maxBatchDaySpan: maxBatchDaySpan,
                maxBatchPayloadBytes: maxBatchPayloadBytes,
                onProgress: onProgress
            )
        }

        do {
            switch try await prepareNonLegacy(
                dates: dates,
                settings: settings,
                destination: destination,
                calendarTimeZone: calendarTimeZone,
                connectedAppsEnabled: connectedAppsEnabled,
                fetchHealthData: fetchHealthData,
                fetchExternalDailyRecords: fetchExternalDailyRecords,
                maxBatchDaySpan: maxBatchDaySpan,
                maxBatchPayloadBytes: maxBatchPayloadBytes,
                requestedMode: requestedMode,
                coreExecutor: coreExecutor,
                identitySource: identitySource,
                comparisonOptions: comparisonOptions,
                diagnosticSink: diagnosticSink,
                onProgress: onProgress
            ) {
            case .legacy:
                // Compatibility and unsupported-operation gates resolve before capture, so this is
                // the only safe point at which the established legacy authority may be selected.
                return await exportLegacyPrepared(
                    dates: dates,
                    settings: settings,
                    destination: destination,
                    fetchHealthData: fetchHealthData,
                    fetchExternalDailyRecords: fetchExternalDailyRecords,
                    upload: upload,
                    maxBatchDaySpan: maxBatchDaySpan,
                    maxBatchPayloadBytes: maxBatchPayloadBytes,
                    onProgress: onProgress
                )
            case .prepared(let operation):
                return await commitPreparedOperation(operation, upload: upload)
            }
        } catch is CancellationError {
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: normalizedDates.count,
                failedDateDetails: [],
                formatsPerDate: 0,
                looseAggregateFileCount: 0,
                isFileCategoryBreakdownComplete: true,
                wasCancelled: true,
                completedDates: []
            )
        } catch let error as EngineError {
            return failureResult(
                dates: normalizedDates,
                reason: .unknown,
                message: error.rawValue
            )
        } catch {
            return failureResult(
                dates: normalizedDates,
                reason: .unknown,
                message: APIExportClientError.invalidPayload.localizedDescription
            )
        }
    }

    private static func prepareNonLegacy(
        dates: [Date],
        settings: AdvancedExportSettings,
        destination: APIExportDestinationSnapshot,
        calendarTimeZone: TimeZone,
        connectedAppsEnabled: Bool,
        fetchHealthData: HealthDataFetcher,
        fetchExternalDailyRecords: ExternalDailyRecordFetcher?,
        maxBatchDaySpan: Int,
        maxBatchPayloadBytes: Int,
        requestedMode: ExportEngineMode,
        coreExecutor: any AppleLooseDailyCoreExecuting,
        identitySource: AppleExportOperationIdentitySource,
        comparisonOptions: NativeExportComparisonOptions,
        diagnosticSink: @escaping EngineDiagnosticSink,
        onProgress: ProgressHandler?
    ) async throws -> PreparationResolution {
        let suppliedPin = settings.executionAppleExportEnginePin
        let captureContext = settings.executionSleepCaptureContext ?? AppleSleepCaptureContext.pinned.wrappedValue
        let wakeDate = captureContext?.sleepDayAttribution == .morningEnds || suppliedPin?.isWakeDate == true
        // Historical API v8 normalized GMT to UTC. Successor work keeps the exact
        // captured IANA authority used by its data and pin, including GMT aliases.
        let calendarTimeZoneIdentifier = wakeDate
            ? captureContext?.calendarTimeZoneIdentifier ?? suppliedPin?.calendarTimeZoneIdentifier ?? engineTimeZoneIdentifier(calendarTimeZone)
            : engineTimeZoneIdentifier(calendarTimeZone)
        if wakeDate {
            guard requestedMode == .rust, let captureContext,
                  captureContext.sleepDayAttribution == .morningEnds, captureContext.exportProfileID == "apple-v11",
                  captureContext.calendarTimeZoneIdentifier == calendarTimeZoneIdentifier,
                  captureContext.timeZone.identifier == calendarTimeZone.identifier,
                  !settings.executionAppleExportEngineAuthorityIsFrozen || suppliedPin != nil,
                  suppliedPin == nil || suppliedPin?.hasExplicitWakeDateContracts == true else {
                throw EngineError.rustPlanningFailed
            }
        }
        guard requestedMode == .shadow || requestedMode == .rust,
              AppleExportEnginePin.isIANAIdentifier(calendarTimeZoneIdentifier) else {
            if suppliedPin != nil || wakeDate { throw EngineError.rustPlanningFailed }
            return .legacy
        }
        if let suppliedPin,
           suppliedPin.calendarTimeZoneIdentifier != calendarTimeZoneIdentifier {
            throw EngineError.rustPlanningFailed
        }
        if requestedMode == .rust && !wakeDate {
            // Apple-v8 API records still require native profile-document serialization for exact
            // shipped bytes. New Rust requests resolve wholly to legacy before capture/core work;
            // an already-persisted Rust promise fails closed instead of changing authority.
            if suppliedPin != nil || wakeDate { throw EngineError.rustPlanningFailed }
            return .legacy
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = calendarTimeZone
        let normalizedDates = HealthKitDailyCapture.normalizedDates(dates, calendar: calendar)
        guard !normalizedDates.isEmpty else { return .legacy }

        let dayLimit = max(1, maxBatchDaySpan)
        let byteLimit = max(1, maxBatchPayloadBytes)
        guard dayLimit <= defaultMaxBatchDaySpan,
              normalizedDates.count <= maximumSharedCoreDateCount,
              areContiguous(normalizedDates, calendar: calendar),
              UInt64(exactly: byteLimit) != nil else {
            // The packaged API renderer's bounded input contract is an operation-level gate. Never
            // mix native and Rust batches to work around it. Pinned work fails rather than changing
            // authority during resume.
            if suppliedPin != nil || wakeDate { throw EngineError.rustPlanningFailed }
            return .legacy
        }

        var settingsSnapshot = ExportSettingsSnapshot.from(
            settings,
            calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
        )
        settingsSnapshot.sleepCaptureContext = captureContext
        let frozenSettings = settingsSnapshot.makeAdvancedExportSettings()
        frozenSettings.exportTimeZoneOverride = calendarTimeZone
        let identity = identitySource.capture(
            calendarTimeZoneIdentifier: calendarTimeZoneIdentifier
        )
        let artifactDirectory = apiArtifactDirectory(identity.requestID)

        let context: AppleLooseDailyCoreContext
        do {
            if let suppliedPin {
                context = try await coreExecutor.loadContext(pin: suppliedPin)
            } else if wakeDate {
                context = try await coreExecutor.loadContext(profile: .appleHealthDataV11,
                    expectedRegistryVersion: HealthMdSleepProfileContract.registryVersion)
            } else {
                context = try await coreExecutor.loadContext()
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if requestedMode == .shadow {
                await emitRustFailure(pin: nil, diagnosticSink: diagnosticSink)
                return .legacy
            }
            throw EngineError.rustPlanningFailed
        }

        let pin: AppleExportEnginePin
        if let suppliedPin {
            guard suppliedPin.engine == requestedMode,
                  suppliedPin.isCompatible(
                      buildInfo: context.buildInfo,
                      registrySnapshot: context.registry
                  ) else {
                throw EngineError.rustPlanningFailed
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
            } catch {
                if wakeDate { throw EngineError.rustPlanningFailed }
                return .legacy
            }
        }

        var outcomes: [HealthKitDailyCapture.Outcome] = []
        outcomes.reserveCapacity(normalizedDates.count)
        for (index, date) in normalizedDates.enumerated() {
            try Task.checkCancellation()
            let outcome = try await HealthKitDailyCapture.capture(
                date: date,
                detailPolicy: frozenSettings.effectiveDetailPolicy,
                metricSelection: frozenSettings.metricSelection,
                transform: .filterToSelection,
                emptyRecordPolicy: .reportNoData,
                fetchExternalRecords: fetchExternalDailyRecords != nil,
                filterExternalRecords: false,
                failurePolicy: .apiEndpoint,
                fetchHealthData: fetchHealthData,
                fetchExternalDailyRecords: fetchExternalDailyRecords
            )
            outcomes.append(outcome)
            onProgress?(index + 1, normalizedDates.count)
        }
        try Task.checkCancellation()

        // From this point on every capture/provider outcome is immutable. Both renderers consume
        // the same values, failures, external JSON, settings, time zone, IDs, and clock.
        let preparedOutcomes = try outcomes.map {
            try PreparedOutcome(
                $0,
                settings: frozenSettings,
                artifactDirectory: artifactDirectory
            )
        }
        let nativeBatches: [PreparedBatch]
        let nativePlan: NativeExportArtifactPlan?
        if requestedMode == .shadow {
            nativeBatches = try makePreparedBatches(
                outcomes: preparedOutcomes,
                exportedAt: identity.capturedAt,
                connectedAppsEnabled: connectedAppsEnabled,
                calendarTimeZone: calendarTimeZone,
                maxBatchDaySpan: dayLimit,
                maxBatchPayloadBytes: byteLimit,
                artifactDirectory: artifactDirectory
            )
            nativePlan = try makeNativePlan(batches: nativeBatches, identity: identity, pin: pin)
        } else {
            nativeBatches = []
            nativePlan = nil
        }

        let rustPlan: NativeExportArtifactPlan?
        var sourceComposedBatches: [PreparedBatch]?
        do {
            let aggregatePlan = try await makeRustPlan(
                outcomes: preparedOutcomes,
                normalizedDates: normalizedDates,
                settings: frozenSettings,
                connectedAppsEnabled: connectedAppsEnabled,
                calendarTimeZone: calendarTimeZone,
                maxBatchDaySpan: dayLimit,
                maxBatchPayloadBytes: byteLimit,
                identity: identity,
                pin: pin,
                context: context,
                coreExecutor: coreExecutor
            )
            if pin.isWakeDate, preparedOutcomes.contains(where: {
                $0.record?.healthKitRecordArchive != nil || $0.record?.partialFailures.isEmpty == false
            }) {
                guard let wakeContext = captureContext else { throw EngineError.invalidPreparedPlan }
                let boundedBatches = try materializeBatches(plan: aggregatePlan, outcomes: preparedOutcomes,
                    normalizedDates: normalizedDates, exportedAt: identity.capturedAt,
                    connectedAppsEnabled: connectedAppsEnabled, calendarTimeZone: calendarTimeZone,
                    requestID: identity.requestID)
                let composed = try await composeWakeDateSources(boundedBatches: boundedBatches,
                    outcomes: preparedOutcomes, identity: identity, pin: pin,
                    connectedAppsEnabled: connectedAppsEnabled, calendarTimeZone: calendarTimeZone,
                    maxBatchDaySpan: dayLimit, maxBatchPayloadBytes: byteLimit, artifactDirectory: artifactDirectory,
                    captureContext: wakeContext)
                rustPlan = composed.plan
                sourceComposedBatches = composed.batches
            } else {
                rustPlan = aggregatePlan
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch {
            if requestedMode == .shadow {
                await emitRustFailure(pin: pin, diagnosticSink: diagnosticSink)
                rustPlan = nil
            } else {
                throw EngineError.rustPlanningFailed
            }
        }

        let selectedPlan: NativeExportArtifactPlan
        let selectedBatches: [PreparedBatch]
        switch requestedMode {
        case .shadow:
            guard let nativePlan else { throw EngineError.invalidPreparedPlan }
            if let rustPlan {
                let diagnostics = NativeExportPlanComparator.compare(
                    native: nativePlan,
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
            }
            selectedPlan = nativePlan
            selectedBatches = nativeBatches
        case .rust:
            guard let rustPlan else { throw EngineError.rustPlanningFailed }
            selectedPlan = rustPlan
            do {
                selectedBatches = try sourceComposedBatches ?? materializeBatches(
                    plan: rustPlan,
                    outcomes: preparedOutcomes,
                    normalizedDates: normalizedDates,
                    exportedAt: identity.capturedAt,
                    connectedAppsEnabled: connectedAppsEnabled,
                    calendarTimeZone: calendarTimeZone,
                    requestID: identity.requestID
                )
            } catch {
                throw EngineError.rustPlanningFailed
            }
        case .legacy:
            return .legacy
        }

        var pinnedSnapshot = settingsSnapshot
        pinnedSnapshot.appleExportEnginePin = pin
        if wakeDate { pinnedSnapshot.appleExportEngineAuthorityIsFrozen = true }
        return .prepared(PreparedOperation(
            authority: requestedMode,
            identity: identity,
            pin: pin,
            settingsSnapshot: pinnedSnapshot,
            destination: destination,
            nativePlan: nativePlan,
            rustPlan: rustPlan,
            selectedPlan: selectedPlan,
            batches: selectedBatches,
            normalizedDates: normalizedDates,
            failedDateDetails: outcomes.compactMap(\.failure),
            partialFailures: outcomes.flatMap(\.partialFailures),
            calendar: calendar
        ))
    }

    private static func makePreparedBatches(
        outcomes: [PreparedOutcome],
        exportedAt: Date,
        connectedAppsEnabled: Bool,
        calendarTimeZone: TimeZone,
        maxBatchDaySpan: Int,
        maxBatchPayloadBytes: Int,
        artifactDirectory: URL,
        captureContext: AppleSleepCaptureContext? = nil
    ) throws -> [PreparedBatch] {
        var batches: [PreparedBatch] = []
        var current: AccumulatingBatch?
        for outcome in outcomes {
            var candidate = current ?? AccumulatingBatch(
                exportedAt: exportedAt,
                connectedAppsEnabled: connectedAppsEnabled,
                calendarTimeZone: calendarTimeZone,
                artifactDirectory: artifactDirectory,
                captureContext: captureContext
            )
            candidate.append(outcome)
            let exceedsDayLimit = candidate.requestedDates.count > maxBatchDaySpan
            let exceedsByteLimit = try candidate.payloadByteCount() > maxBatchPayloadBytes
            if current != nil, exceedsDayLimit || exceedsByteLimit {
                batches.append(try current!.prepared())
                var singleton = AccumulatingBatch(
                    exportedAt: exportedAt,
                    connectedAppsEnabled: connectedAppsEnabled,
                    calendarTimeZone: calendarTimeZone,
                    artifactDirectory: artifactDirectory,
                    captureContext: captureContext
                )
                singleton.append(outcome)
                current = singleton
            } else {
                current = candidate
            }
        }
        if let current { batches.append(try current.prepared()) }
        return batches
    }

    private static func makeNativePlan(
        batches: [PreparedBatch],
        identity: AppleExportOperationIdentity,
        pin: AppleExportEnginePin
    ) throws -> NativeExportArtifactPlan {
        let profile: CoreMetricRegistryProfile = pin.isWakeDate ? .appleHealthDataV11 : .appleHealthDataV8
        let artifacts = try batches.enumerated().map { index, batch in
            let path = apiArtifactPath(requestID: identity.requestID, index: index)
            let digest = batch.bodyArtifact.descriptor.sha256
            return try NativeExportArtifact(
                role: .apiRequest,
                id: NativeExportArtifactPlan.artifactID(
                    requestID: identity.requestID,
                    sessionID: identity.sessionID,
                    profile: profile,
                    relativePath: path,
                    mediaType: "application/json",
                    writeMode: .apiPost,
                    contentSHA256: digest
                ),
                relativePath: path,
                mediaType: "application/json",
                writeMode: .apiPost,
                file: batch.bodyArtifact,
                byteCount: batch.bodyArtifact.descriptor.byteCount,
                sha256: digest
            )
        }
        let total = try artifacts.reduce(UInt64(0)) { sum, artifact in
            let next = sum.addingReportingOverflow(artifact.byteCount)
            guard !next.overflow else { throw EngineError.invalidPreparedPlan }
            return next.partialValue
        }
        return try NativeExportArtifactPlan(
            artifactPlanVersion: pin.artifactPlanVersion,
            requestID: identity.requestID,
            sessionID: identity.sessionID,
            profile: profile,
            artifacts: artifacts,
            totalByteCount: total,
            pin: pin
        )
    }

    private static func makeRustPlan(
        outcomes: [PreparedOutcome],
        normalizedDates: [Date],
        settings: AdvancedExportSettings,
        connectedAppsEnabled: Bool,
        calendarTimeZone: TimeZone,
        maxBatchDaySpan: Int,
        maxBatchPayloadBytes: Int,
        identity: AppleExportOperationIdentity,
        pin: AppleExportEnginePin,
        context: AppleLooseDailyCoreContext,
        coreExecutor: any AppleLooseDailyCoreExecuting
    ) async throws -> NativeExportArtifactPlan {
        let records = outcomes.compactMap(\.record)
        let captureContext = settings.executionSleepCaptureContext
        let customization = settings.formatCustomization
        if pin.isWakeDate { customization.unitPreference = .metric }
        let semanticConfiguration = try HealthMdSemanticInputAdapter.sessionConfiguration(
            sessionID: identity.sessionID,
            selection: settings.metricSelection,
            registry: context.registry,
            customization: customization,
            calendarTimeZoneIdentifier: pin.calendarTimeZoneIdentifier,
            retainPlatformExtensions: false,
            rollupPeriods: [],
            captureContext: captureContext
        )
        let semanticBatches = try HealthMdSemanticInputAdapter.boundedBatches(
            sessionID: identity.sessionID,
            healthData: records,
            registry: context.registry,
            customization: customization,
            calendarTimeZoneIdentifier: pin.calendarTimeZoneIdentifier,
            captureContext: captureContext,
            includeArchiveExtensions: !pin.isWakeDate
        )
        let semanticResult = try await coreExecutor.processSemantic(
            configuration: semanticConfiguration,
            batches: semanticBatches.map(\.data)
        )

        let failureOptions = try outcomes.compactMap { outcome -> HealthMdRenderInputAdapter.APIFailureOptions? in
            guard let failure = outcome.failure,
                  let failureData = outcome.failureData,
                  let object = try JSONSerialization.jsonObject(with: failureData) as? [String: Any],
                  let timestamp = object["date"] as? String,
                  let reason = object["reason"] as? String else {
                if outcome.failure == nil { return nil }
                throw EngineError.invalidPreparedPlan
            }
            return HealthMdRenderInputAdapter.APIFailureOptions(
                ownerDate: APIExportClient.dayString(
                    from: outcome.sourceDate,
                    timeZone: calendarTimeZone
                ),
                timestamp: timestamp,
                reason: reason,
                errorDetails: object["errorDetails"] as? String ?? failure.errorDetails
            )
        }
        let externalOptions = outcomes.flatMap { outcome in
            let ownerDate = APIExportClient.dayString(
                from: outcome.sourceDate,
                timeZone: calendarTimeZone
            )
            return outcome.externalRecordData.map {
                HealthMdRenderInputAdapter.APIExternalRecordOptions(
                    ownerDate: ownerDate,
                    json: $0
                )
            }
        }

        // Render configuration requires one format. The destination-free daily JSON artifact is
        // discarded below; only the complete ordered API request plan crosses this seam.
        var renderOptions = HealthMdRenderInputAdapter.Options(
            requestID: identity.requestID,
            formats: ["json"]
        )
        renderOptions.unitSystem = customization.unitPreference == .imperial
            ? "imperial"
            : "metric"
        renderOptions.includeMetadata = settings.includeMetadata
        renderOptions.groupByCategory = settings.groupByCategory
        renderOptions.includePlatformExtensions = false
        renderOptions.rawCaptureStatus = "not_requested"
        renderOptions.writeMode = "overwrite"
        renderOptions.api = HealthMdRenderInputAdapter.APIOptions(
            envelopeVersion: connectedAppsEnabled ? 2 : 1,
            exportedAt: APIExportClient.timestampString(from: identity.capturedAt),
            source: "ios",
            dateRangeStart: APIExportClient.dayString(
                from: normalizedDates[0],
                timeZone: calendarTimeZone
            ),
            dateRangeEnd: APIExportClient.dayString(
                from: normalizedDates[normalizedDates.count - 1],
                timeZone: calendarTimeZone
            ),
            failedDateDetails: failureOptions,
            externalRecordSchema: connectedAppsEnabled ? ExternalDailyRecord.schema : nil,
            externalRecordSchemaVersion: connectedAppsEnabled ? ExternalDailyRecord.schemaVersion : nil,
            externalRecords: externalOptions,
            maxDaysPerBatch: maxBatchDaySpan,
            maxEncodedBytes: UInt64(maxBatchPayloadBytes)
        )
        let presentationByOwnerDate = Dictionary(uniqueKeysWithValues: records.map { record in
            var aggregate = record
            if pin.isWakeDate {
                aggregate.healthKitRecordArchive = nil
                aggregate.partialFailures = []
            }
            return (APIExportClient.dayString(from: record.date, timeZone: calendarTimeZone), aggregate)
        })
        let renderInput = try HealthMdRenderInputAdapter.encode(
            semanticResult: semanticResult,
            registry: context.registry,
            calendarTimeZoneIdentifier: pin.calendarTimeZoneIdentifier,
            options: renderOptions,
            presentationByOwnerDate: presentationByOwnerDate,
            presentationCustomization: customization,
            captureContext: captureContext
        )
        let corePlan = try await coreExecutor.render(
            configuration: renderInput.configuration,
            semanticResult: semanticResult,
            batches: renderInput.batches
        )
        let completePlan = try CoreArtifactPlanConverter.convert(corePlan, pin: pin)
        let artifacts = completePlan.artifacts.filter { $0.role == .apiRequest }
        guard !artifacts.isEmpty,
              artifacts.allSatisfy({
                  $0.writeMode == .apiPost && $0.mediaType == "application/json"
              }) else {
            throw EngineError.invalidPreparedPlan
        }
        return try NativeExportArtifactPlan(
            artifactPlanVersion: pin.artifactPlanVersion,
            requestID: identity.requestID,
            sessionID: identity.sessionID,
            profile: pin.coreProfile,
            artifacts: artifacts,
            totalByteCount: artifacts.reduce(0) { $0 + $1.byteCount },
            pin: pin
        )
    }

    private static func composeWakeDateSources(boundedBatches: [PreparedBatch], outcomes: [PreparedOutcome],
        identity: AppleExportOperationIdentity, pin: AppleExportEnginePin, connectedAppsEnabled: Bool,
        calendarTimeZone: TimeZone, maxBatchDaySpan: Int, maxBatchPayloadBytes: Int,
        artifactDirectory: URL, captureContext: AppleSleepCaptureContext
    ) async throws -> (plan: NativeExportArtifactPlan, batches: [PreparedBatch]) {
        var aggregates: [String: Data] = [:]
        for batch in boundedBatches {
            guard let root = try JSONSerialization.jsonObject(with: batch.body) as? [String: Any],
                  let records = root["records"] as? [[String: Any]] else { throw EngineError.invalidPreparedPlan }
            for record in records {
                guard let owner = record["date"] as? String,
                      aggregates.updateValue(try JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]),
                        forKey: owner) == nil else { throw EngineError.invalidPreparedPlan }
            }
        }
        let sources = try outcomes.compactMap { outcome -> AppleWakeDateAPIRecordComposer.Source? in
            guard let record = outcome.record else { return nil }
            let owner = APIExportClient.dayString(from: outcome.sourceDate, timeZone: calendarTimeZone)
            guard let aggregate = aggregates[owner] else { throw EngineError.invalidPreparedPlan }
            return AppleWakeDateAPIRecordComposer.Source(ownerDate: owner, aggregate: aggregate,
                archive: record.healthKitRecordArchive, partialFailures: record.partialFailures,
                captureStatus: HealthKitRecordArchiveSerializer.captureStatusString(record.healthKitRecordCaptureStatus))
        }
        guard sources.count == aggregates.count else { throw EngineError.invalidPreparedPlan }
        let files = try await AppleWakeDateAPIRecordComposer.compose(sources: sources,
            calendarTimeZoneIdentifier: calendarTimeZone.identifier, directory: artifactDirectory)
        let prepared = outcomes.map { outcome in
            PreparedOutcome(copying: outcome, recordArtifact: files[APIExportClient.dayString(from: outcome.sourceDate,
                timeZone: calendarTimeZone)])
        }
        let batches = try makePreparedBatches(outcomes: prepared, exportedAt: identity.capturedAt,
            connectedAppsEnabled: connectedAppsEnabled, calendarTimeZone: calendarTimeZone,
            maxBatchDaySpan: maxBatchDaySpan, maxBatchPayloadBytes: maxBatchPayloadBytes,
            artifactDirectory: artifactDirectory, captureContext: captureContext)
        return (try makeNativePlan(batches: batches, identity: identity, pin: pin), batches)
    }

    private static func materializeBatches(
        plan: NativeExportArtifactPlan,
        outcomes: [PreparedOutcome],
        normalizedDates: [Date],
        exportedAt: Date,
        connectedAppsEnabled: Bool,
        calendarTimeZone: TimeZone,
        requestID: String
    ) throws -> [PreparedBatch] {
        guard outcomes.count == normalizedDates.count else {
            throw EngineError.invalidPreparedPlan
        }
        let ownerDates = normalizedDates.map {
            APIExportClient.dayString(from: $0, timeZone: calendarTimeZone)
        }
        var cursor = 0
        var batches: [PreparedBatch] = []
        for (index, artifact) in plan.artifacts.enumerated() {
            guard cursor < ownerDates.count,
                  artifact.relativePath == apiArtifactPath(requestID: requestID, index: index),
                  let object = try JSONSerialization.jsonObject(with: artifact.inlineData) as? [String: Any],
                  object["schema"] as? String == "healthmd.api_export",
                  object["schema_version"] as? Int == (connectedAppsEnabled ? 2 : 1),
                  object["source"] as? String == "ios",
                  object["exported_at"] as? String == APIExportClient.timestampString(from: exportedAt),
                  let range = object["date_range"] as? [String: Any],
                  let start = range["start"] as? String,
                  let end = range["end"] as? String,
                  start == ownerDates[cursor],
                  let endIndex = ownerDates[cursor...].firstIndex(of: end),
                  let recordCount = object["record_count"] as? Int,
                  let failures = object["failed_date_details"] as? [Any] else {
                throw EngineError.invalidPreparedPlan
            }
            if plan.profile == .appleHealthDataV11 {
                let expectedContext: [String: String] = ["calendar_timezone": calendarTimeZone.identifier,
                    "timestamp_timezone": "UTC", "sleep_day_attribution": "morning_ends",
                    "sleep_owner_day_rule": "session_end_date", "sleep_interval_clipping": "none"]
                guard object["daily_record_schema"] as? String == "healthmd.health_data",
                      object["daily_record_schema_version"] as? Int == 11,
                      object["daily_record_schema_profile"] as? String == "apple-v11",
                      object["daily_record_time_context"] as? [String: String] == expectedContext,
                      let dailyRecords = object["records"] as? [[String: Any]],
                      dailyRecords.allSatisfy({ $0["schema"] as? String == "healthmd.health_data"
                          && $0["unit_system"] as? String == "metric"
                          && $0["schema_version"] as? Int == 11
                          && $0["schema_profile"] as? String == "apple-v11"
                          && $0["time_context"] as? [String: String] == expectedContext }) else {
                    throw EngineError.invalidPreparedPlan
                }
            }
            let slice = outcomes[cursor...endIndex]
            let records = slice.compactMap(\.record)
            let failureDetails = slice.compactMap(\.failure)
            guard recordCount == records.count,
                  failures.count == failureDetails.count else {
                throw EngineError.invalidPreparedPlan
            }
            if connectedAppsEnabled {
                let wireExternalCount = slice.reduce(0) { $0 + $1.externalRecordData.count }
                guard object["external_record_count"] as? Int == wireExternalCount else {
                    throw EngineError.invalidPreparedPlan
                }
            }
            let bodyArtifact: ExportArtifactFile
            if let file = artifact.fileArtifact {
                bodyArtifact = file
            } else {
                bodyArtifact = try ExportArtifactIO.renderTemporary(
                    in: apiArtifactDirectory(requestID),
                    prefix: "api-rust-envelope",
                    mediaType: "application/json"
                ) { sink in
                    try sink.write(artifact.inlineData)
                }
            }
            batches.append(PreparedBatch(
                requestedDates: Array(normalizedDates[cursor...endIndex]),
                records: records,
                failedDateDetails: failureDetails,
                externalRecords: slice.flatMap(\.externalRecords),
                externalRecordPayloadCount: slice.reduce(0) { $0 + $1.externalRecordData.count },
                dateRangeStart: normalizedDates[cursor],
                dateRangeEnd: normalizedDates[endIndex],
                exportedAt: exportedAt,
                bodyArtifact: bodyArtifact
            ))
            cursor = endIndex + 1
        }
        guard cursor == ownerDates.count else { throw EngineError.invalidPreparedPlan }
        return batches
    }

    static func commitPreparedOperation(
        _ operation: PreparedOperation,
        upload: @escaping PreparedUploader,
        barrier: ExportCommitBarrier = ExportCommitBarrier()
    ) async -> ExportOrchestrator.ExportResult {
        var totalSuccessCount = 0
        var completedDates: Set<Date> = []
        var totalExternalRecordCount = 0
        var commitStarted = false
        try? await barrier.transition(to: .materialized)

        // Preserve the established all-empty behavior even though both complete plans retain the
        // failure-only artifacts for exact shadow evidence and destination-free preview.
        guard operation.batches.contains(where: { !$0.records.isEmpty }) else {
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: operation.normalizedDates.count,
                failedDateDetails: operation.failedDateDetails,
                partialFailures: operation.partialFailures,
                formatsPerDate: 0,
                looseAggregateFileCount: 0,
                isFileCategoryBreakdownComplete: true,
                completedDates: []
            )
        }

        for (index, batch) in operation.batches.enumerated() {
            if Task.isCancelled {
                try? await barrier.transition(to: .failed)
                return ExportOrchestrator.ExportResult(
                    successCount: totalSuccessCount,
                    totalCount: operation.normalizedDates.count,
                    failedDateDetails: operation.failedDateDetails,
                    partialFailures: operation.partialFailures,
                    formatsPerDate: 0,
                    looseAggregateFileCount: 0,
                    externalRecordPayloadCount: totalExternalRecordCount,
                    isFileCategoryBreakdownComplete: true,
                    wasCancelled: true,
                    completedDates: Array(completedDates)
                )
            }
            do {
                if !commitStarted {
                    guard operation.selectedPlan.artifacts.count == operation.batches.count else {
                        throw EngineError.invalidPreparedPlan
                    }
                    for (batchIndex, candidate) in operation.batches.enumerated() {
                        let artifact = operation.selectedPlan.artifacts[batchIndex]
                        guard artifact.role == .apiRequest,
                              artifact.relativePath == apiArtifactPath(requestID: operation.identity.requestID, index: batchIndex),
                              artifact.sha256 == candidate.bodyArtifact.descriptor.sha256,
                              artifact.byteCount == candidate.bodyByteCount else { throw EngineError.invalidPreparedPlan }
                        try candidate.bodyArtifact.validateIntegrity()
                    }
                    // This is deliberately adjacent to the first uploader call: no authority read,
                    // fallback, or rerender is possible after the one-way transition.
                    try await barrier.transition(to: .committing)
                    commitStarted = true
                }
                if index > 0 { try batch.bodyArtifact.validateIntegrity() }
                _ = try await upload(batch, operation.destination)
                totalSuccessCount += batch.records.count
                completedDates.formUnion(batch.records.map {
                    operation.calendar.startOfDay(for: $0.date)
                })
                completedDates.formUnion(terminalCompletedDates(
                    in: batch.failedDateDetails,
                    calendar: operation.calendar
                ))
                totalExternalRecordCount += batch.externalRecordPayloadCount
            } catch {
                try? await barrier.transition(to: .failed)
                let futureDates = operation.batches
                    .dropFirst(index + 1)
                    .flatMap(\.requestedDates)
                let futureSet = Set(futureDates.map {
                    operation.calendar.startOfDay(for: $0)
                })
                let knownFailures = operation.failedDateDetails.filter {
                    !futureSet.contains(operation.calendar.startOfDay(for: $0.date))
                }
                return uploadFailureResult(
                    error: error,
                    failedBatchStart: batch.dateRangeStart,
                    failedBatchEnd: batch.dateRangeEnd,
                    undeliveredRecordDates: batch.records.map(\.date),
                    notAttemptedDates: futureDates,
                    successCount: totalSuccessCount,
                    completedDates: completedDates,
                    totalCount: operation.normalizedDates.count,
                    failedDateDetails: knownFailures,
                    partialFailures: operation.partialFailures,
                    externalRecordCount: totalExternalRecordCount
                )
            }
        }
        if commitStarted { try? await barrier.transition(to: .completed) }
        return ExportOrchestrator.ExportResult(
            successCount: totalSuccessCount,
            totalCount: operation.normalizedDates.count,
            failedDateDetails: operation.failedDateDetails,
            partialFailures: operation.partialFailures,
            formatsPerDate: 0,
            looseAggregateFileCount: 0,
            externalRecordPayloadCount: totalExternalRecordCount,
            isFileCategoryBreakdownComplete: true,
            completedDates: Array(completedDates)
        )
    }

    private static func emitRustFailure(
        pin: AppleExportEnginePin?,
        diagnosticSink: EngineDiagnosticSink
    ) async {
        await diagnosticSink(.rustRenderFailed(ShadowExportFailureDiagnostic(
            profile: AppleExportEnginePin.profileID,
            semanticProfileRevision: pin?.semanticProfileRevision ?? 1,
            renderProfileRevision: pin?.renderProfileRevision ?? 2,
            kind: .rustRenderFailed
        )))
    }

    private static func areContiguous(_ dates: [Date], calendar: Calendar) -> Bool {
        zip(dates, dates.dropFirst()).allSatisfy { previous, next in
            calendar.date(byAdding: .day, value: 1, to: previous) == next
        }
    }

    private static func apiArtifactDirectory(_ operationID: String) -> URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(
            "healthmd-api-artifacts-\(operationID)-\(UUID().uuidString)",
            isDirectory: true
        )
    }

    private static func apiArtifactPath(requestID: String, index: Int) -> String {
        "api/\(requestID)-\(String(format: "%04d", index)).json"
    }

    private static func engineTimeZoneIdentifier(_ timeZone: TimeZone) -> String {
        timeZone.identifier == "GMT" ? "UTC" : timeZone.identifier
    }

    private static func exportLegacyPrepared(
        dates: [Date],
        settings: AdvancedExportSettings,
        destination: APIExportDestinationSnapshot,
        fetchHealthData: HealthDataFetcher,
        fetchExternalDailyRecords: ExternalDailyRecordFetcher?,
        upload: @escaping PreparedUploader,
        maxBatchDaySpan: Int,
        maxBatchPayloadBytes: Int,
        onProgress: ProgressHandler?
    ) async -> ExportOrchestrator.ExportResult {
        #if DEBUG
        let performanceTimer = ExportPerformanceTimer()
        var uploadRequestCount = 0
        defer {
            ExportPerformanceInstrumentation.completed(
                pipeline: "api-endpoint",
                phase: "capture-batch-upload",
                timer: performanceTimer,
                itemCount: uploadRequestCount
            )
        }
        #endif
        let normalizedDates = HealthKitDailyCapture.normalizedDates(dates)
        guard let dateRangeStart = normalizedDates.first else {
            return ExportOrchestrator.ExportResult(
                successCount: 0,
                totalCount: 0,
                failedDateDetails: [],
                formatsPerDate: 0,
                looseAggregateFileCount: 0,
                isFileCategoryBreakdownComplete: true
            )
        }

        guard !settings.dailyNotesOnlyModeEnabled else {
            return failureResult(
                dates: normalizedDates,
                reason: .unknown,
                message: "Daily Notes Only requires a filesystem destination and cannot export to an API endpoint."
            )
        }
        guard !settings.exportFormats.isEmpty else {
            return failureResult(
                dates: normalizedDates,
                reason: .unknown,
                message: "Select at least one export format before exporting to an API endpoint."
            )
        }

        let dayLimit = max(1, maxBatchDaySpan)
        let byteLimit = max(1, maxBatchPayloadBytes)
        let connectedAppsEnabled = ConnectedAppsFeature.isEnabled
        var totalSuccessCount = 0
        var completedDates: Set<Date> = []
        var allFailedDateDetails: [FailedDateDetail] = []
        var allPartialFailures: [ExportPartialFailure] = []
        var totalExternalRecordCount = 0
        var datesProcessed = 0
        var currentBatch: AccumulatingBatch?
        var queuedFailureOnlyBatches: [PreparedBatch] = []
        let artifactDirectory = apiArtifactDirectory(UUID().uuidString)

        func cancelledResult() -> ExportOrchestrator.ExportResult {
            ExportOrchestrator.ExportResult(
                successCount: totalSuccessCount,
                totalCount: normalizedDates.count,
                failedDateDetails: allFailedDateDetails,
                partialFailures: allPartialFailures,
                formatsPerDate: 0,
                looseAggregateFileCount: 0,
                externalRecordPayloadCount: totalExternalRecordCount,
                isFileCategoryBreakdownComplete: true,
                wasCancelled: true,
                completedDates: Array(completedDates)
            )
        }

        /// Commits one fully prepared batch. Failure-only batches are retained
        /// until at least one record exists, preserving all-empty no-request behavior.
        func commit(
            _ batch: PreparedBatch,
            futureDates: [Date]
        ) async -> ExportOrchestrator.ExportResult? {
            if batch.records.isEmpty {
                guard totalSuccessCount > 0 else {
                    queuedFailureOnlyBatches.append(batch)
                    return nil
                }
                do {
                    #if DEBUG
                    uploadRequestCount += 1
                    #endif
                    _ = try await upload(batch, destination)
                    completedDates.formUnion(terminalCompletedDates(in: batch.failedDateDetails))
                    return nil
                } catch {
                    return uploadFailureResult(
                        error: error,
                        failedBatchStart: batch.dateRangeStart,
                        failedBatchEnd: batch.dateRangeEnd,
                        undeliveredRecordDates: [],
                        notAttemptedDates: futureDates,
                        successCount: totalSuccessCount,
                        completedDates: completedDates,
                        totalCount: normalizedDates.count,
                        failedDateDetails: allFailedDateDetails,
                        partialFailures: allPartialFailures,
                        externalRecordCount: totalExternalRecordCount
                    )
                }
            }

            for failureOnlyBatch in queuedFailureOnlyBatches {
                do {
                    #if DEBUG
                    uploadRequestCount += 1
                    #endif
                    _ = try await upload(failureOnlyBatch, destination)
                    completedDates.formUnion(
                        terminalCompletedDates(in: failureOnlyBatch.failedDateDetails)
                    )
                } catch {
                    return uploadFailureResult(
                        error: error,
                        failedBatchStart: failureOnlyBatch.dateRangeStart,
                        failedBatchEnd: failureOnlyBatch.dateRangeEnd,
                        undeliveredRecordDates: [],
                        notAttemptedDates: batch.requestedDates + futureDates,
                        successCount: totalSuccessCount,
                        completedDates: completedDates,
                        totalCount: normalizedDates.count,
                        failedDateDetails: allFailedDateDetails,
                        partialFailures: allPartialFailures,
                        externalRecordCount: totalExternalRecordCount
                    )
                }
            }
            queuedFailureOnlyBatches.removeAll()

            do {
                #if DEBUG
                uploadRequestCount += 1
                #endif
                _ = try await upload(batch, destination)
                totalSuccessCount += batch.records.count
                completedDates.formUnion(batch.records.map {
                    Calendar.current.startOfDay(for: $0.date)
                })
                completedDates.formUnion(terminalCompletedDates(in: batch.failedDateDetails))
                totalExternalRecordCount += batch.externalRecordPayloadCount
                return nil
            } catch {
                return uploadFailureResult(
                    error: error,
                    failedBatchStart: batch.dateRangeStart,
                    failedBatchEnd: batch.dateRangeEnd,
                    undeliveredRecordDates: batch.records.map(\.date),
                    notAttemptedDates: futureDates,
                    successCount: totalSuccessCount,
                    completedDates: completedDates,
                    totalCount: normalizedDates.count,
                    failedDateDetails: allFailedDateDetails,
                    partialFailures: allPartialFailures,
                    externalRecordCount: totalExternalRecordCount
                )
            }
        }

        for (index, date) in normalizedDates.enumerated() {
            if Task.isCancelled { return cancelledResult() }

            // The day-count boundary is known before the next HealthKit read.
            // Commit it now so cancellation during that read cannot erase a
            // fully prepared earlier batch.
            if let batch = currentBatch,
               batch.requestedDates.count >= dayLimit {
                do {
                    if let failure = await commit(
                        try batch.prepared(),
                        futureDates: Array(normalizedDates.dropFirst(index))
                    ) {
                        return failure
                    }
                    currentBatch = nil
                } catch {
                    return uploadFailureResult(
                        error: error,
                        failedBatchStart: batch.requestedDates.first ?? date,
                        failedBatchEnd: batch.requestedDates.last ?? date,
                        undeliveredRecordDates: batch.records.map(\.date),
                        notAttemptedDates: Array(normalizedDates.dropFirst(index)),
                        successCount: totalSuccessCount,
                        completedDates: completedDates,
                        totalCount: normalizedDates.count,
                        failedDateDetails: allFailedDateDetails,
                        partialFailures: allPartialFailures,
                        externalRecordCount: totalExternalRecordCount
                    )
                }
            }

            let outcome: HealthKitDailyCapture.Outcome
            do {
                outcome = try await HealthKitDailyCapture.capture(
                    date: date,
                    detailPolicy: settings.effectiveDetailPolicy,
                    metricSelection: settings.metricSelection,
                    transform: .filterToSelection,
                    emptyRecordPolicy: .reportNoData,
                    fetchExternalRecords: fetchExternalDailyRecords != nil,
                    filterExternalRecords: false,
                    failurePolicy: .apiEndpoint,
                    fetchHealthData: fetchHealthData,
                    fetchExternalDailyRecords: fetchExternalDailyRecords
                )
            } catch is CancellationError {
                return cancelledResult()
            } catch {
                return uploadFailureResult(
                    error: APIExportClientError.invalidPayload,
                    failedBatchStart: date,
                    failedBatchEnd: date,
                    undeliveredRecordDates: [date],
                    notAttemptedDates: Array(normalizedDates.dropFirst(index + 1)),
                    successCount: totalSuccessCount,
                    completedDates: completedDates,
                    totalCount: normalizedDates.count,
                    failedDateDetails: allFailedDateDetails,
                    partialFailures: allPartialFailures,
                    externalRecordCount: totalExternalRecordCount
                )
            }

            datesProcessed += 1
            onProgress?(datesProcessed, normalizedDates.count)
            if Task.isCancelled { return cancelledResult() }

            let preparedOutcome: PreparedOutcome
            do {
                preparedOutcome = try PreparedOutcome(
                    outcome,
                    settings: settings,
                    artifactDirectory: artifactDirectory
                )
            } catch {
                return uploadFailureResult(
                    error: error,
                    failedBatchStart: date,
                    failedBatchEnd: date,
                    undeliveredRecordDates: outcome.record.map { [$0.date] } ?? [],
                    notAttemptedDates: Array(normalizedDates.dropFirst(index + 1)),
                    successCount: totalSuccessCount,
                    completedDates: completedDates,
                    totalCount: normalizedDates.count,
                    failedDateDetails: allFailedDateDetails,
                    partialFailures: allPartialFailures,
                    externalRecordCount: totalExternalRecordCount
                )
            }

            var candidate = currentBatch ?? AccumulatingBatch(
                connectedAppsEnabled: connectedAppsEnabled,
                artifactDirectory: artifactDirectory
            )
            candidate.append(preparedOutcome)
            let candidatePayloadBytes: Int
            do {
                candidatePayloadBytes = try candidate.payloadByteCount()
            } catch {
                return uploadFailureResult(
                    error: error,
                    failedBatchStart: candidate.requestedDates.first ?? date,
                    failedBatchEnd: candidate.requestedDates.last ?? date,
                    undeliveredRecordDates: candidate.records.map(\.date),
                    notAttemptedDates: Array(normalizedDates.dropFirst(index + 1)),
                    successCount: totalSuccessCount,
                    completedDates: completedDates,
                    totalCount: normalizedDates.count,
                    failedDateDetails: allFailedDateDetails,
                    partialFailures: allPartialFailures,
                    externalRecordCount: totalExternalRecordCount
                )
            }

            let exceedsDayLimit = candidate.requestedDates.count > dayLimit
            let exceedsByteLimit = candidatePayloadBytes > byteLimit
            if currentBatch != nil, exceedsDayLimit || exceedsByteLimit {
                do {
                    let preparedCurrent = try currentBatch!.prepared()
                    let futureDates = Array(normalizedDates.dropFirst(index))
                    if let failure = await commit(preparedCurrent, futureDates: futureDates) {
                        return failure
                    }
                } catch {
                    let dates = currentBatch?.requestedDates ?? [date]
                    return uploadFailureResult(
                        error: error,
                        failedBatchStart: dates.first ?? date,
                        failedBatchEnd: dates.last ?? date,
                        undeliveredRecordDates: currentBatch?.records.map(\.date) ?? [],
                        notAttemptedDates: Array(normalizedDates.dropFirst(index)),
                        successCount: totalSuccessCount,
                        completedDates: completedDates,
                        totalCount: normalizedDates.count,
                        failedDateDetails: allFailedDateDetails,
                        partialFailures: allPartialFailures,
                        externalRecordCount: totalExternalRecordCount
                    )
                }
                var singleton = AccumulatingBatch(
                    connectedAppsEnabled: connectedAppsEnabled,
                    artifactDirectory: artifactDirectory
                )
                singleton.append(preparedOutcome)
                currentBatch = singleton
            } else {
                currentBatch = candidate
            }

            allPartialFailures.append(contentsOf: outcome.partialFailures)
            if let failure = outcome.failure {
                allFailedDateDetails.append(failure)
            }
        }

        if let currentBatch {
            do {
                if let failure = await commit(
                    try currentBatch.prepared(),
                    futureDates: []
                ) {
                    return failure
                }
            } catch {
                return uploadFailureResult(
                    error: error,
                    failedBatchStart: currentBatch.requestedDates.first ?? dateRangeStart,
                    failedBatchEnd: currentBatch.requestedDates.last ?? dateRangeStart,
                    undeliveredRecordDates: currentBatch.records.map(\.date),
                    notAttemptedDates: [],
                    successCount: totalSuccessCount,
                    completedDates: completedDates,
                    totalCount: normalizedDates.count,
                    failedDateDetails: allFailedDateDetails,
                    partialFailures: allPartialFailures,
                    externalRecordCount: totalExternalRecordCount
                )
            }
        }

        if totalSuccessCount == 0 && allFailedDateDetails.isEmpty {
            allFailedDateDetails = [FailedDateDetail(date: dateRangeStart, reason: .noHealthData)]
        }

        return ExportOrchestrator.ExportResult(
            successCount: totalSuccessCount,
            totalCount: normalizedDates.count,
            failedDateDetails: allFailedDateDetails,
            partialFailures: allPartialFailures,
            formatsPerDate: 0,
            looseAggregateFileCount: 0,
            externalRecordPayloadCount: totalExternalRecordCount,
            isFileCategoryBreakdownComplete: true,
            completedDates: Array(completedDates)
        )
    }

    private static func uploadFailureResult(
        error: Error,
        failedBatchStart: Date,
        failedBatchEnd: Date,
        undeliveredRecordDates: [Date],
        notAttemptedDates: [Date],
        successCount: Int,
        completedDates: Set<Date>,
        totalCount: Int,
        failedDateDetails: [FailedDateDetail],
        partialFailures: [ExportPartialFailure],
        externalRecordCount: Int
    ) -> ExportOrchestrator.ExportResult {
        let failedRange = rangeDescription(start: failedBatchStart, end: failedBatchEnd)
        let failureMessage = "Batch upload failed for \(failedRange): \(safeUploadFailureDescription(for: error))"
        let uploadFailureDates = undeliveredRecordDates.isEmpty
            ? [failedBatchStart]
            : undeliveredRecordDates
        let uploadFailures = uploadFailureDates.map {
            FailedDateDetail(
                date: $0,
                reason: .apiUploadFailed,
                errorDetails: failureMessage
            )
        }
        let notAttempted = notAttemptedDates.map {
            FailedDateDetail(
                date: $0,
                reason: .unknown,
                errorDetails: "Not attempted: an earlier batch upload failed for \(failedRange)."
            )
        }

        var seenDates: Set<Date> = []
        let orderedFailures = (uploadFailures + failedDateDetails + notAttempted).filter {
            seenDates.insert(Calendar.current.startOfDay(for: $0.date)).inserted
        }

        return ExportOrchestrator.ExportResult(
            successCount: successCount,
            totalCount: totalCount,
            failedDateDetails: orderedFailures,
            partialFailures: partialFailures,
            formatsPerDate: 0,
            looseAggregateFileCount: 0,
            externalRecordPayloadCount: externalRecordCount,
            isFileCategoryBreakdownComplete: true,
            wasCancelled: Task.isCancelled || error is CancellationError,
            completedDates: Array(completedDates)
        )
    }

    private static func terminalCompletedDates(
        in details: [FailedDateDetail],
        calendar: Calendar = .current
    ) -> Set<Date> {
        Set(details.compactMap { detail in
            guard detail.reason == .noHealthData else { return nil }
            return calendar.startOfDay(for: detail.date)
        })
    }

    private static func safeUploadFailureDescription(for error: Error) -> String {
        if let apiError = error as? APIExportClientError {
            return apiError.localizedDescription
        }
        if let urlError = error as? URLError {
            return "Network request failed (code \(urlError.code.rawValue))."
        }
        if error is CancellationError {
            return "The API upload was cancelled."
        }
        return "The API endpoint upload failed."
    }

    private static func failureResult(
        dates: [Date],
        reason: ExportFailureReason,
        message: String
    ) -> ExportOrchestrator.ExportResult {
        let failedDates = dates.isEmpty ? [Date()] : dates
        return ExportOrchestrator.ExportResult(
            successCount: 0,
            totalCount: dates.count,
            failedDateDetails: failedDates.map {
                FailedDateDetail(date: $0, reason: reason, errorDetails: message)
            },
            formatsPerDate: 0,
            looseAggregateFileCount: 0,
            isFileCategoryBreakdownComplete: true
        )
    }

    private static func rangeDescription(start: Date, end: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyy-MM-dd"
        return "\(formatter.string(from: start)) to \(formatter.string(from: end))"
    }
}
