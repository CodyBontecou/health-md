import Foundation

/// Request-scoped connected-export mode. Summary-only jobs may retain the saved
/// Lossless Health Records toggle, but they must never fetch or transfer archives.
enum ConnectedExportGranularMode {
    static func isEnabled(for settings: AdvancedExportSettings) -> Bool {
        settings.effectiveGranularDataEnabled
    }

    static func isEnabled(for snapshot: ExportSettingsSnapshot) -> Bool {
        let hasRollups = snapshot.generateWeeklyRollups
            || snapshot.generateMonthlyRollups
            || snapshot.generateYearlyRollups
        let summaryOnlyModeEnabled = snapshot.summaryOnlyExport
            && hasRollups
            && !snapshot.exportFormats.isEmpty
        return snapshot.includeGranularData
            && !summaryOnlyModeEnabled
            && !snapshot.dailyNotesOnlyModeEnabled
    }

    nonisolated static func sanitized(
        _ record: HealthData,
        includesGranularData: Bool
    ) -> HealthData {
        guard !includesGranularData else { return record }
        var sanitized = record
        sanitized.sleep.stages = []
        sanitized.heart.heartRateSamples = []
        sanitized.heart.hrvSamples = []
        sanitized.vitals.bloodOxygenSamples = []
        sanitized.vitals.bloodGlucoseSamples = []
        sanitized.vitals.respiratoryRateSamples = []
        sanitized.vitals.bloodPressureSamples = []
        sanitized.workouts = sanitized.workouts.map(summaryOnlyWorkout)
        sanitized.healthKitRecordArchive = nil
        sanitized.healthKitRecordCaptureStatus = .notRequested
        return sanitized
    }

    nonisolated private static func summaryOnlyWorkout(_ workout: WorkoutData) -> WorkoutData {
        WorkoutData(
            id: workout.id,
            sourceUUID: workout.sourceUUID,
            workoutType: workout.workoutType,
            healthKitActivityType: workout.healthKitActivityType,
            healthKitActivityTypeRawValue: workout.healthKitActivityTypeRawValue,
            startTime: workout.startTime,
            actualEndDate: workout.actualEndDate,
            sourceRevision: workout.sourceRevision,
            device: workout.device,
            isIndoor: workout.isIndoor,
            metadata: workout.metadata,
            duration: workout.duration,
            calories: workout.calories,
            distance: workout.distance,
            avgHeartRate: workout.avgHeartRate,
            maxHeartRate: workout.maxHeartRate,
            minHeartRate: workout.minHeartRate,
            avgRunningCadence: workout.avgRunningCadence,
            avgStrideLength: workout.avgStrideLength,
            avgGroundContactTime: workout.avgGroundContactTime,
            avgVerticalOscillation: workout.avgVerticalOscillation,
            avgCyclingCadence: workout.avgCyclingCadence,
            avgPower: workout.avgPower,
            maxPower: workout.maxPower,
            elevationGainMeters: workout.elevationGainMeters,
            elevationLossMeters: workout.elevationLossMeters,
            laps: [],
            splits: [],
            route: [],
            timeSeries: .empty
        )
    }
}

/// Builds iOS-originated Mac export jobs by capturing the current export settings
/// and fetching one HealthKit record for each requested date.
@MainActor
struct MacExportJobBuilder {
    typealias HealthDataFetcher = (_ date: Date, _ includeGranularData: Bool) async throws -> HealthData
    typealias ExternalDailyRecordFetcher = (_ date: Date) async -> [ExternalDailyRecord]

    /// Captures connected renderer authority before HealthKit/provider acquisition. Unsupported or
    /// native-companion operations are explicitly legacy (nil pin); persisted snapshots never pass
    /// through this helper and therefore can never be silently downgraded on resume.
    static func settingsSnapshotForNewConnectedMacOperation(
        _ settings: AdvancedExportSettings,
        healthSubfolder: String?,
        calendarTimeZone: TimeZone = .current,
        hasNativeOnlyCompanionAction: Bool,
        operationSurface: AppleExportOperationSurface = .connectedReceivedFilesWithoutSideEffects,
        policyResolver: AppleExportEnginePolicyResolver = AppleExportEnginePolicyResolver()
    ) async -> ExportSettingsSnapshot {
        let legacySnapshot = ExportSettingsSnapshot.from(
            settings,
            healthSubfolder: healthSubfolder,
            calendarTimeZoneIdentifier: calendarTimeZone.identifier
        )
        // A request-scoped execution pin means this is restored work, not a new operation. Preserve
        // it exactly so the receiver can either honor it or fail the unsupported operation safely.
        if legacySnapshot.appleExportEnginePin != nil {
            return legacySnapshot
        }
        guard !hasNativeOnlyCompanionAction,
              AppleLooseDailyExportPlanner.supports(
                  settingsSnapshot: legacySnapshot,
                  surface: operationSurface
              ) else {
            var explicitlyLegacy = legacySnapshot
            explicitlyLegacy.appleExportEnginePin = nil
            return explicitlyLegacy
        }
        return await ExportSettingsSnapshot.forNewAppleOperation(
            settings,
            healthSubfolder: healthSubfolder,
            calendarTimeZone: calendarTimeZone,
            surface: operationSurface,
            policyResolver: policyResolver
        )
    }

    static func build(
        jobID: UUID = UUID(),
        createdAt: Date = Date(),
        sourceDeviceName: String,
        startDate: Date,
        endDate: Date,
        requestedDates: [Date]? = nil,
        rollupRequestedDates: [Date]? = nil,
        settings: AdvancedExportSettings,
        healthSubfolder: String? = nil,
        destinationDisplayName: String?,
        frozenSettingsSnapshot: ExportSettingsSnapshot? = nil,
        fetchHealthData: HealthDataFetcher,
        fetchExternalDailyRecords: ExternalDailyRecordFetcher? = nil,
        onProgress: ((_ processed: Int, _ total: Int, _ date: Date) -> Void)? = nil
    ) async throws -> MacExportJob {
        let sourceTimeZone = frozenSettingsSnapshot?.calendarTimeZoneIdentifier
            .flatMap(TimeZone.init(identifier:))
            ?? settings.exportTimeZoneOverride
            ?? .current
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = sourceTimeZone
        let dates = requestedDates.map {
            Array(Set($0.map { sourceCalendar.startOfDay(for: $0) })).sorted()
        } ?? ExportOrchestrator.dateRange(from: startDate, to: endDate, calendar: sourceCalendar)
        let requestedDays = Set(dates.map { sourceCalendar.startOfDay(for: $0) })
        let immutableRollupDates = rollupRequestedDates.map {
            Array(Set($0.map { sourceCalendar.startOfDay(for: $0) })).sorted()
        } ?? dates
        let rollupDates = ExportOrchestrator.rollupSourceDates(
            for: immutableRollupDates,
            settings: settings,
            calendar: sourceCalendar
        )
        let transferDates = Array(Set(dates + rollupDates)).sorted()
        let settingsSnapshot = if let frozenSettingsSnapshot {
            frozenSettingsSnapshot
        } else {
            await settingsSnapshotForNewConnectedMacOperation(
                settings,
                healthSubfolder: healthSubfolder,
                calendarTimeZone: sourceTimeZone,
                hasNativeOnlyCompanionAction: settings.writesExternalProviderSidecars
                    && fetchExternalDailyRecords != nil
            )
        }
        let includeGranularData = ConnectedExportGranularMode.isEnabled(for: settings)
        var records: [HealthData] = []
        var externalDailyRecords: [ExternalDailyRecord] = []

        for (index, date) in transferDates.enumerated() {
            try Task.checkCancellation()
            let day = sourceCalendar.startOfDay(for: date)
            let shouldIncludeGranularData = requestedDays.contains(day) && includeGranularData
            let fetchedRecord = try await fetchHealthData(date, shouldIncludeGranularData)
            var record = ConnectedExportGranularMode.sanitized(
                fetchedRecord,
                includesGranularData: shouldIncludeGranularData
            )

            if record.hasAnyData,
               requestedDays.contains(day),
               settings.writesExternalProviderSidecars,
               let fetchExternalDailyRecords {
                let providerRecords = await fetchExternalDailyRecords(date)
                record.providers = HealthProviderSections.normalized(from: providerRecords)
                externalDailyRecords.append(contentsOf: providerRecords.filter(\.shouldExport))
            }
            records.append(record)
            onProgress?(index + 1, transferDates.count, date)
        }

        return MacExportJob(
            jobID: jobID,
            createdAt: createdAt,
            sourceDeviceName: sourceDeviceName,
            dateRangeStart: dates.first ?? Calendar.current.startOfDay(for: startDate),
            dateRangeEnd: dates.last ?? Calendar.current.startOfDay(for: endDate),
            requestedDates: dates,
            records: records,
            externalDailyRecords: externalDailyRecords,
            settingsSnapshot: settingsSnapshot,
            appleExportEnginePin: settingsSnapshot.appleExportEnginePin,
            requestedTarget: ExportTargetSnapshot(
                kind: .connectedMac,
                displayName: ExportTargetSelection.connectedMac.title,
                destinationDisplayName: destinationDisplayName
            )
        )
    }
}

/// Shared helpers for the chunked iPhone → Mac export stream prototype.
///
/// v1 intentionally uses a small fixed chunk size so each Multipeer transfer is
/// bounded while the Mac-side executor is still evolving. Sequence numbers are
/// 1-based and chunks preserve the same transfer-date ordering used by the
/// whole-job fallback builder.
@MainActor
struct MacExportStreamingJobBuilder {
    /// Fixed number of transfer days per stream chunk for the first protocol version.
    nonisolated static let transferDaysPerChunk = 7
    nonisolated static let chunkStrategyVersion = 1

    struct Metadata {
        let requestedDates: [Date]
        let requestedDays: Set<Date>
        let transferDates: [Date]
        let settingsSnapshot: ExportSettingsSnapshot
        let requestedTarget: ExportTargetSnapshot

        var dateRangeStart: Date { requestedDates.first ?? Date() }
        var dateRangeEnd: Date { requestedDates.last ?? dateRangeStart }
        var totalRequestedDays: Int { requestedDates.count }
        var totalTransferDays: Int { transferDates.count }
    }

    struct Chunk {
        let sequence: Int
        let dates: [Date]
    }

    nonisolated static func connectedOperationSurface(
        protocolVersion: Int
    ) -> AppleExportOperationSurface {
        protocolVersion >= ConnectedCorpusTransferCapabilities.rangePlanProtocolVersion
            ? .connectedReceivedRangeWithoutSideEffects
            : .connectedReceivedFilesWithoutSideEffects
    }

    static func metadataForNewOperation(
        startDate: Date,
        endDate: Date,
        requestedDates: [Date]? = nil,
        rollupRequestedDates: [Date]? = nil,
        settings: AdvancedExportSettings,
        healthSubfolder: String? = nil,
        destinationDisplayName: String?,
        operationSurface: AppleExportOperationSurface = .legacyOnly,
        enforceConnectedOperationGate: Bool = false,
        connectedOperationSurface: AppleExportOperationSurface = .connectedReceivedFilesWithoutSideEffects,
        hasNativeOnlyCompanionAction: Bool = false
    ) async -> Metadata {
        let calendarTimeZone = settings.exportTimeZoneOverride ?? .current
        let snapshot: ExportSettingsSnapshot
        if enforceConnectedOperationGate {
            snapshot = await MacExportJobBuilder.settingsSnapshotForNewConnectedMacOperation(
                settings,
                healthSubfolder: healthSubfolder,
                calendarTimeZone: calendarTimeZone,
                hasNativeOnlyCompanionAction: hasNativeOnlyCompanionAction,
                operationSurface: connectedOperationSurface
            )
        } else {
            // Preserve non-connected/direct callers of this shared date/chunk helper unchanged.
            snapshot = await ExportSettingsSnapshot.forNewAppleOperation(
                settings,
                healthSubfolder: healthSubfolder,
                calendarTimeZone: calendarTimeZone,
                surface: operationSurface,
                hasNativeOnlyCompanionAction: hasNativeOnlyCompanionAction
            )
        }
        return metadata(
            startDate: startDate,
            endDate: endDate,
            requestedDates: requestedDates,
            rollupRequestedDates: rollupRequestedDates,
            settings: settings,
            healthSubfolder: healthSubfolder,
            destinationDisplayName: destinationDisplayName,
            frozenSettingsSnapshot: snapshot
        )
    }

    /// Synchronous reconstruction for an already frozen snapshot. Callers planning new durable
    /// work use `metadataForNewOperation` so any UniFFI compatibility check stays off MainActor.
    static func metadata(
        startDate: Date,
        endDate: Date,
        requestedDates suppliedRequestedDates: [Date]? = nil,
        rollupRequestedDates suppliedRollupRequestedDates: [Date]? = nil,
        settings: AdvancedExportSettings,
        healthSubfolder: String? = nil,
        destinationDisplayName: String?,
        frozenSettingsSnapshot: ExportSettingsSnapshot? = nil
    ) -> Metadata {
        let sourceTimeZone = frozenSettingsSnapshot?.calendarTimeZoneIdentifier
            .flatMap(TimeZone.init(identifier:))
            ?? settings.exportTimeZoneOverride
            ?? .current
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = sourceTimeZone
        let requestedDates = suppliedRequestedDates.map {
            Array(Set($0.map { sourceCalendar.startOfDay(for: $0) })).sorted()
        } ?? ExportOrchestrator.dateRange(from: startDate, to: endDate, calendar: sourceCalendar)
        let requestedDays = Set(requestedDates.map { sourceCalendar.startOfDay(for: $0) })
        let immutableRollupDates = suppliedRollupRequestedDates.map {
            Array(Set($0.map { sourceCalendar.startOfDay(for: $0) })).sorted()
        } ?? requestedDates
        let rollupDates = ExportOrchestrator.rollupSourceDates(
            for: immutableRollupDates,
            settings: settings,
            calendar: sourceCalendar
        )
        let transferDates = Array(Set(requestedDates + rollupDates)).sorted()

        return Metadata(
            requestedDates: requestedDates,
            requestedDays: requestedDays,
            transferDates: transferDates,
            settingsSnapshot: frozenSettingsSnapshot ?? ExportSettingsSnapshot.from(
                settings,
                healthSubfolder: healthSubfolder,
                calendarTimeZoneIdentifier: sourceTimeZone.identifier
            ),
            requestedTarget: ExportTargetSnapshot(
                kind: .connectedMac,
                displayName: ExportTargetSelection.connectedMac.title,
                destinationDisplayName: destinationDisplayName
            )
        )
    }

    static func chunks(for transferDates: [Date], chunkSize: Int = transferDaysPerChunk) -> [Chunk] {
        guard chunkSize > 0, !transferDates.isEmpty else { return [] }
        return stride(from: 0, to: transferDates.count, by: chunkSize).enumerated().map { index, start in
            let end = min(start + chunkSize, transferDates.count)
            return Chunk(sequence: index + 1, dates: Array(transferDates[start..<end]))
        }
    }

    static func shouldIncludeGranularData(
        for date: Date,
        metadata: Metadata,
        settings: AdvancedExportSettings
    ) -> Bool {
        let sourceTimeZone = metadata.settingsSnapshot.calendarTimeZoneIdentifier
            .flatMap(TimeZone.init(identifier:))
            ?? settings.exportTimeZoneOverride
            ?? .current
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = sourceTimeZone
        let day = sourceCalendar.startOfDay(for: date)
        return metadata.requestedDays.contains(day)
            && ConnectedExportGranularMode.isEnabled(for: settings)
    }
}
