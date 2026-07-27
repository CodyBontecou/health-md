#if os(iOS)
import CryptoKit
import Foundation
import HealthMdConnectionCore
import UIKit

enum IPhoneDirectFileProducerError: LocalizedError {
    case invalidRequest(String)
    case requestChanged
    case cancelled
    case invalidSpool
    case unexpectedResponse
    case healthKitNotAuthorized
    case exportLimitReached

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let message): return message
        case .requestChanged: return "A durable direct file job with this ID changed."
        case .cancelled: return "The direct file export was cancelled."
        case .invalidSpool: return "The protected direct file spool failed validation."
        case .unexpectedResponse: return "The CLI sent an unexpected direct file response."
        case .healthKitNotAuthorized: return "HealthKit access has not been authorized for this request."
        case .exportLimitReached: return "Export limit reached. Unlock Full Access on iPhone to export more."
        }
    }
}

@MainActor
final class IPhoneDirectFileExportProducer {
    static let shared = IPhoneDirectFileExportProducer()

    private let fileManager = FileManager.default
    private var cancelledJobIDs: Set<UUID> = []

    func canCancel(jobID: UUID) -> Bool {
        guard let journal = try? loadJournal(jobID: jobID) else { return false }
        return journal.state != "completed"
    }

    func cancel(jobID: UUID) {
        cancelledJobIDs.insert(jobID)
        if var journal = try? loadJournal(jobID: jobID) {
            journal.state = "cancelled"
            journal.updatedAt = Date()
            try? saveJournal(journal)
        }
    }

    func pause(jobID: UUID) {
        guard var journal = try? loadJournal(jobID: jobID),
              journal.state != "completed", journal.state != "cancelled" else { return }
        journal.state = "paused"
        journal.updatedAt = Date()
        try? saveJournal(journal)
    }

    func run(
        _ request: DirectExportRequest,
        peerBinding: DirectPeerBinding,
        negotiation: DirectTransferNegotiation,
        channel: IPhoneDirectExportConnection,
        protocolAuthority: AppleDirectProtocolAuthority,
        healthKitManager: HealthKitManager,
        externalIntegrations: ExternalIntegrationDailyRecordProviding?
    ) async throws -> Bool {
        externalIntegrations?.beginExportAction()
        var externalExportSucceeded = false
        defer { externalIntegrations?.endExportAction(succeeded: externalExportSucceeded) }
        guard request.protocolVersion == HealthMdDirectProtocol.currentVersion,
              request.createdAt <= Date().addingTimeInterval(5 * 60),
              request.createdAt.addingTimeInterval(HealthMdDirectProtocol.jobLifetime) > Date(),
              request.responseMode == .writeFiles,
              request.rawProfile == nil,
              let destination = request.destination,
              destination.rootPath.hasPrefix("/") else {
            throw IPhoneDirectFileProducerError.invalidRequest(
                "Direct file exports require an explicit absolute Mac destination."
            )
        }
        if cancelledJobIDs.contains(request.jobID) {
            throw IPhoneDirectFileProducerError.cancelled
        }
        let journal: IPhoneDirectFileJournal
        if let persisted = try? loadJournal(jobID: request.jobID) {
            guard IPhoneDirectFileJournal.isSupportedVersion(persisted.version),
                  persisted.request == request,
                  persisted.accepted.peerBinding == peerBinding,
                  persisted.session.partitionTargetBytes == negotiation.partitionTargetBytes,
                  persisted.appleExportEnginePin == persisted.settingsSnapshot.appleExportEnginePin,
                  persisted.state != "cancelled" else {
                throw IPhoneDirectFileProducerError.requestChanged
            }
            try protocolAuthority.beginOperation(
                pin: persisted.version >= IPhoneDirectFileJournal.currentVersion
                    ? persisted.appleDirectProtocolPin : nil
            )
            guard persisted.session.requestFingerprint == (try protocolAuthority.requestFingerprint(request)) else {
                throw IPhoneDirectFileProducerError.requestChanged
            }
            journal = persisted
        } else {
            let protocolPin = try protocolAuthority.pinForNewOperation()
            try protocolAuthority.beginOperation(pin: protocolPin)
            let prepared = try await prepare(
                request,
                peerBinding: peerBinding,
                negotiation: negotiation,
                protocolPin: protocolPin,
                protocolAuthority: protocolAuthority,
                healthKitManager: healthKitManager,
                connectedProviderCount: externalIntegrations?.connectedProviderCount ?? 0
            )
            try checkCancellation(request.jobID)
            journal = prepared
            try saveJournal(prepared)
        }

        try await channel.send(.exportAccepted(journal.accepted))
        var current = journal
        current.state = "preparing"
        if current.capturedDays.count < current.transferDates.count {
            current = try await captureRemaining(
                current,
                channel: channel,
                healthKitManager: healthKitManager,
                externalIntegrations: externalIntegrations
            )
        }
        if current.generatedFiles.isEmpty {
            current = try await generateFiles(current, channel: channel)
        }
        if current.partitions.isEmpty,
           current.generatedFiles.contains(where: { $0.manifest.byteCount > 0 }) {
            current.partitions = try buildPartitions(current)
            current.updatedAt = Date()
            try saveJournal(current)
        }
        current.state = "transferring"
        current.updatedAt = Date()
        try saveJournal(current)

        try await channel.send(.transferSession(current.session))
        for file in current.generatedFiles.sorted(by: { $0.manifest.relativePath < $1.manifest.relativePath }) {
            try await channel.send(.fileManifest(file.manifest))
        }
        try await transferPartitions(
            &current,
            channel: channel,
            protocolAuthority: protocolAuthority
        )
        let failedDates = current.capturedDays
            .filter { $0.isRequestedDate && !$0.succeeded }
            .map(\.sourceDateIdentifier)
        let successCount = current.requestedDates.count - failedDates.count
        let outcome = try DirectExportOutcome(
            status: failedDates.isEmpty ? "success" : "partial_success",
            successCount: successCount,
            totalCount: current.requestedDates.count,
            failedDateIdentifiers: failedDates
        )
        let finalize = try DirectTransferFinalize(
            sessionID: current.session.sessionID,
            jobID: request.jobID,
            requestFingerprint: current.session.requestFingerprint,
            totalPartitions: current.partitions.count,
            totalBytes: current.partitions.reduce(0) { $0 + $1.byteCount },
            finalPartitionSHA256: current.partitions.last?.sha256,
            outcome: outcome
        )
        try await channel.send(.transferFinalize(finalize))
        guard case .transferFinalAcknowledgement(let acknowledgement) = try await receiveMessage(
            channel,
            jobID: request.jobID
        ),
        acknowledgement.accepted,
        acknowledgement.sessionID == current.session.sessionID,
        acknowledgement.jobID == request.jobID,
        acknowledgement.totalPartitions == finalize.totalPartitions,
        acknowledgement.totalBytes == finalize.totalBytes,
        acknowledgement.finalPartitionSHA256 == finalize.finalPartitionSHA256 else {
            throw IPhoneDirectFileProducerError.unexpectedResponse
        }

        current.state = "completed"
        current.updatedAt = Date()
        let shouldRecordCompletion = !current.completionRecorded && successCount > 0
        if shouldRecordCompletion {
            try PurchaseManager.shared.recordExportUse(jobID: request.jobID)
            let result = ExportOrchestrator.ExportResult(
                successCount: successCount,
                totalCount: current.requestedDates.count,
                failedDateDetails: [],
                formatsPerDate: current.settingsSnapshot.exportFormats.count
            )
            ExportOrchestrator.recordResult(
                result,
                source: .macAgent,
                dateRangeStart: current.requestedDates.first ?? request.createdAt,
                dateRangeEnd: current.requestedDates.last ?? request.createdAt,
                targetLabel: destination.rootPath,
                fileCount: current.generatedFiles.count,
                idempotencyKey: request.jobID,
                appleExportEnginePin: current.appleExportEnginePin
            )
            current.completionRecorded = true
        }
        // Both side effects are keyed by job ID, so a crash before this journal
        // save retries them without double charging or duplicating history.
        try saveJournal(current)
        try await channel.send(.completionConfirmed(jobID: request.jobID))
        externalExportSucceeded = true
        return failedDates.isEmpty
    }

    private func prepare(
        _ request: DirectExportRequest,
        peerBinding: DirectPeerBinding,
        negotiation: DirectTransferNegotiation,
        protocolPin: AppleDirectProtocolPin?,
        protocolAuthority: AppleDirectProtocolAuthority,
        healthKitManager: HealthKitManager,
        connectedProviderCount: Int
    ) async throws -> IPhoneDirectFileJournal {
        let sourceTimeZone = TimeZone.current
        let resolvedSelection = try resolveSelection(request.canonicalSelection)
        let internalRequest = try makeInternalRequest(
            request,
            selection: resolvedSelection,
            sourceTimeZone: sourceTimeZone
        )
        let settings = IPhoneExportRequestSettingsResolver.settings(
            for: internalRequest,
            savedSettings: AdvancedExportSettings()
        )
        settings.exportTimeZoneOverride = sourceTimeZone
        guard healthKitManager.isAuthorized else {
            throw IPhoneDirectFileProducerError.healthKitNotAuthorized
        }
        if let resolvedSelection {
            guard try await healthKitManager.hasRecordedAuthorizationDecision(
                forMetricIDs: Set(resolvedSelection.metricIDs)
            ) else { throw IPhoneDirectFileProducerError.healthKitNotAuthorized }
        }
        let requestedDates = try await resolveDates(
            request.dateSelection,
            settings: settings,
            healthKitManager: healthKitManager,
            sourceTimeZone: sourceTimeZone
        )
        guard !requestedDates.isEmpty else {
            throw IPhoneDirectFileProducerError.invalidRequest("The direct date range is empty.")
        }
        await PurchaseManager.shared.refreshStatus()
        guard PurchaseManager.shared.canExport else {
            throw IPhoneDirectFileProducerError.exportLimitReached
        }
        let healthSubfolder = VaultManager.savedHealthSubfolder()
        let operationSurface = Self.operationSurfaceForNewGeneratedFileJob(
            request: request,
            settings: settings,
            connectedProviderCount: connectedProviderCount
        )
        let metadata = await MacExportStreamingJobBuilder.metadataForNewOperation(
            startDate: requestedDates.first ?? request.createdAt,
            endDate: requestedDates.last ?? request.createdAt,
            requestedDates: requestedDates,
            settings: settings,
            healthSubfolder: healthSubfolder,
            destinationDisplayName: request.destination.map { URL(fileURLWithPath: $0.rootPath).lastPathComponent },
            operationSurface: operationSurface
        )
        let identifiers = requestedDates.map(
            Self.sourceDateFormatter(timeZone: sourceTimeZone).string(from:)
        )
        let accepted = DirectExportAccepted(
            jobID: request.jobID,
            acceptedAt: Date(),
            peerBinding: peerBinding,
            resolvedDateIdentifiers: identifiers,
            sourceDeviceName: UIDevice.current.name,
            sourceTimeZoneIdentifier: sourceTimeZone.identifier,
            resolvedCanonicalSelection: resolvedSelection.map {
                DirectCanonicalSelection(
                    metricIDs: $0.metricIDs,
                    sourceIDs: $0.sourceIDs,
                    objectPaths: $0.objectPaths,
                    fieldPointers: $0.fieldPointers,
                    detailLevel: $0.detailLevel == .lossless ? .lossless : .summary
                )
            }
        )
        let session = try DirectTransferSession(
            sessionID: UUID(),
            jobID: request.jobID,
            requestFingerprint: try protocolAuthority.requestFingerprint(request),
            peerBinding: peerBinding,
            partitionTargetBytes: negotiation.partitionTargetBytes,
            createdAt: Date()
        )
        return IPhoneDirectFileJournal(
            version: IPhoneDirectFileJournal.currentVersion,
            request: request,
            accepted: accepted,
            session: session,
            settingsSnapshot: metadata.settingsSnapshot,
            appleExportEnginePin: metadata.settingsSnapshot.appleExportEnginePin,
            appleDirectProtocolPin: protocolPin,
            healthSubfolder: healthSubfolder,
            requestedDates: metadata.requestedDates,
            transferDates: metadata.transferDates,
            capturedDays: [],
            generatedFiles: [],
            partitions: [],
            committedPartitionCount: 0,
            committedBytes: 0,
            state: "preparing",
            completionRecorded: false,
            updatedAt: Date()
        )
    }

    /// Selects whole-operation authority before the durable renderer pin is captured. Provider
    /// sidecars are native companion artifacts, so a request that can produce them is explicitly
    /// legacy rather than discovering the incompatibility after capture with a Rust pin.
    static func operationSurfaceForNewGeneratedFileJob(
        request: DirectExportRequest,
        settings: AdvancedExportSettings,
        connectedProviderCount: Int
    ) -> AppleExportOperationSurface {
        guard request.canonicalSelection == nil,
              connectedProviderCount > 0,
              settings.writesExternalProviderSidecars else {
            return .directGeneratedFilesWithoutSideEffects
        }
        return .legacyOnly
    }

    struct RangePlanningInput {
        let records: [HealthData]
        let dailyOutputOwnerDates: Set<String>
        let hasAnyData: Bool
    }

    /// Builds the complete destination-free range input from the durable capture spool. Empty
    /// supporting records remain present so roll-up coverage matches the native source-day set,
    /// while empty requested days do not gain daily artifacts. A missing source day would make
    /// native finalization suppress its entire roll-up window, so pinned work fails closed.
    static func rangePlanningInput(
        capturedDays: [IPhoneDirectCapturedDay],
        payloads: [ConnectedCorpusHealthDayPayload],
        settings: AdvancedExportSettings,
        settingsSnapshot: ExportSettingsSnapshot
    ) throws -> RangePlanningInput {
        guard capturedDays.count == payloads.count,
              let timeZoneIdentifier = settingsSnapshot.calendarTimeZoneIdentifier,
              AppleExportEnginePin.isIANAIdentifier(timeZoneIdentifier),
              TimeZone(identifier: timeZoneIdentifier) != nil,
              settings.generateWeeklyRollups == settingsSnapshot.generateWeeklyRollups,
              settings.generateMonthlyRollups == settingsSnapshot.generateMonthlyRollups,
              settings.generateYearlyRollups == settingsSnapshot.generateYearlyRollups,
              settings.summaryOnlyExport == settingsSnapshot.summaryOnlyExport else {
            throw IPhoneDirectFileProducerError.invalidSpool
        }
        let hasRollups = !settings.enabledRollupPeriods.isEmpty
        if hasRollups && capturedDays.contains(where: { !$0.succeeded }) {
            throw AppleLooseDailyExportPlannerError.rustPlanningFailed
        }

        var records: [HealthData] = []
        var dailyOutputOwnerDates: Set<String> = []
        var hasAnyData = false
        for (day, payload) in zip(capturedDays, payloads) {
            guard day.sourceDate == payload.sourceDate,
                  day.isRequestedDate == payload.isRequestedDate,
                  day.succeeded == (payload.record != nil) else {
                throw IPhoneDirectFileProducerError.invalidSpool
            }
            guard let record = payload.record else { continue }
            let prepared = record.preparedExport(settings: settings)
            records.append(record)
            hasAnyData = hasAnyData || prepared.hasAnyData
            if day.isRequestedDate && !settings.summaryOnlyModeEnabled && prepared.hasAnyData {
                dailyOutputOwnerDates.insert(
                    HealthKitDailyOwnershipMetadata.ownerDate(
                        for: record.date,
                        calendarTimeZoneIdentifier: timeZoneIdentifier
                    )
                )
            }
        }
        return RangePlanningInput(
            records: records,
            dailyOutputOwnerDates: dailyOutputOwnerDates,
            hasAnyData: hasAnyData
        )
    }

    private func captureRemaining(
        _ supplied: IPhoneDirectFileJournal,
        channel: IPhoneDirectExportConnection,
        healthKitManager: HealthKitManager,
        externalIntegrations: ExternalIntegrationDailyRecordProviding?
    ) async throws -> IPhoneDirectFileJournal {
        var journal = supplied
        let settings = journal.settingsSnapshot.makeAdvancedExportSettings()
        let sourceTimeZone = TimeZone(
            identifier: journal.accepted.sourceTimeZoneIdentifier
        ) ?? .current
        settings.exportTimeZoneOverride = sourceTimeZone
        var sourceCalendar = Calendar(identifier: .gregorian)
        sourceCalendar.timeZone = sourceTimeZone
        let requestedSet = Set(journal.requestedDates.map { sourceCalendar.startOfDay(for: $0) })
        for index in journal.capturedDays.count..<journal.transferDates.count {
            try checkCancellation(journal.request.jobID)
            let date = journal.transferDates[index]
            let identifier = Self.sourceDateFormatter(timeZone: sourceTimeZone).string(from: date)
            try await sendProgress(
                DirectExportProgress(
                    jobID: journal.request.jobID,
                    processedDays: min(index, journal.requestedDates.count),
                    totalDays: journal.requestedDates.count,
                    currentDate: identifier,
                    committedPartitions: journal.committedPartitionCount,
                    committedBytes: journal.committedBytes,
                    message: "Capturing \(identifier) for CLI file export…"
                ),
                phase: .capturing,
                channel: channel
            )
            let isRequested = requestedSet.contains(sourceCalendar.startOfDay(for: date))
            let includeGranular = requestedSet.contains(
                sourceCalendar.startOfDay(for: date)
            ) && ConnectedExportGranularMode.isEnabled(for: settings)
            let shouldFetchExternal = isRequested
                && journal.request.canonicalSelection == nil
                && settings.writesExternalProviderSidecars
                && externalIntegrations != nil
            let externalFetcher: MacExportJobBuilder.ExternalDailyRecordFetcher?
            if shouldFetchExternal, let externalIntegrations {
                externalFetcher = { date in
                    await externalIntegrations.fetchDailyRecords(for: date)
                }
            } else {
                externalFetcher = nil
            }
            let outcome = try await HealthKitDailyCapture.capture(
                date: date,
                includeGranularData: includeGranular,
                metricSelection: settings.metricSelection,
                transform: .sanitizeGranular,
                emptyRecordPolicy: .retain,
                fetchExternalRecords: shouldFetchExternal,
                failurePolicy: .connectedMac,
                fetchHealthData: { date, includeGranularData, metricSelection in
                    try await healthKitManager.fetchHealthData(
                        for: date,
                        includeGranularData: includeGranularData,
                        metricSelection: metricSelection,
                        timeZone: TimeZone(
                            identifier: journal.accepted.sourceTimeZoneIdentifier
                        )
                    )
                },
                fetchExternalDailyRecords: externalFetcher
            )
            // Cancellation may arrive while HealthKit is awaiting its query.
            // Re-check before this task can overwrite the durable cancelled tombstone.
            try checkCancellation(journal.request.jobID)
            let payload = ConnectedCorpusHealthDayPayload(
                sourceDate: date,
                isRequestedDate: isRequested,
                record: outcome.record,
                externalDailyRecords: outcome.externalDailyRecords,
                failure: outcome.failure
            )
            let relativePath = String(format: "captured-%08d.json", index)
            let url = try jobDirectory(journal.request.jobID).appendingPathComponent(relativePath)
            try protectedAtomicWrite(JSONEncoder().encode(payload), to: url)
            journal.capturedDays.append(IPhoneDirectCapturedDay(
                sourceDate: date,
                sourceDateIdentifier: identifier,
                isRequestedDate: isRequested,
                relativePath: relativePath,
                succeeded: outcome.record != nil
            ))
            journal.updatedAt = Date()
            try saveJournal(journal)
        }
        return journal
    }

    private func generateFiles(
        _ supplied: IPhoneDirectFileJournal,
        channel: IPhoneDirectExportConnection
    ) async throws -> IPhoneDirectFileJournal {
        var journal = supplied
        let staging = try stagingDirectory(journal.request.jobID)
        if fileManager.fileExists(atPath: staging.path) { try fileManager.removeItem(at: staging) }
        try fileManager.createDirectory(
            at: staging,
            withIntermediateDirectories: true,
            attributes: [
                .posixPermissions: 0o700,
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
        )
        let defaults = UserDefaults(suiteName: "HealthMd.DirectStaging.\(journal.request.jobID.uuidString)")!
        defaults.removePersistentDomain(forName: "HealthMd.DirectStaging.\(journal.request.jobID.uuidString)")
        let vault = VaultManager(
            defaults: SystemUserDefaults(defaults: defaults),
            bookmarkResolver: DirectStagingBookmarkResolver()
        )
        try vault.configureDirectTransportStagingRoot(
            staging,
            healthSubfolder: journal.healthSubfolder
        )
        let settings = journal.settingsSnapshot.makeAdvancedExportSettings()
        settings.exportTimeZoneOverride = TimeZone(
            identifier: journal.accepted.sourceTimeZoneIdentifier
        )
        let payloadURLs = try journal.capturedDays.map {
            try jobDirectory(journal.request.jobID).appendingPathComponent($0.relativePath)
        }
        // Decode the already-captured spool once before any generated-file write so the entire
        // operation can attest whether native-only provider sidecars are present. One operation
        // never mixes daily renderer authority across dates.
        let payloads = try payloadURLs.map { url in
            try JSONDecoder().decode(
                ConnectedCorpusHealthDayPayload.self,
                from: Data(contentsOf: url, options: [.mappedIfSafe])
            )
        }
        let hasProviderSidecars = payloads.contains { !$0.externalDailyRecords.isEmpty }
        let operationSurface: AppleExportOperationSurface = hasProviderSidecars
            ? .legacyOnly
            : .directGeneratedFilesWithoutSideEffects
        if journal.appleExportEnginePin != nil {
            // A renderer pin is operation-wide. Materialize every selected daily file and roll-up
            // from the immutable spool in one M4/M5 range plan before generated artifact writes
            // begin. Provider sidecars discovered after pin capture fail closed instead of
            // silently mixing native and Rust authority.
            guard operationSurface == .directGeneratedFilesWithoutSideEffects else {
                throw AppleLooseDailyExportPlannerError.rustPlanningFailed
            }
            let rangeInput = try Self.rangePlanningInput(
                capturedDays: journal.capturedDays,
                payloads: payloads,
                settings: settings,
                settingsSnapshot: journal.settingsSnapshot
            )
            if !rangeInput.records.isEmpty && rangeInput.hasAnyData {
                try checkCancellation(journal.request.jobID)
                guard try await vault.exportHealthDataRange(
                    rangeInput.records,
                    settingsSnapshot: journal.settingsSnapshot,
                    operationSurface: operationSurface,
                    dailyOutputOwnerDates: rangeInput.dailyOutputOwnerDates,
                    operationIdentity: AppleExportOperationIdentity(
                        requestID: journal.request.jobID.uuidString.lowercased(),
                        sessionID: journal.session.sessionID.uuidString.lowercased(),
                        capturedAt: journal.session.createdAt,
                        calendarTimeZoneIdentifier: journal.settingsSnapshot.calendarTimeZoneIdentifier ?? ""
                    ),
                    writeDataDictionary: true
                ) != nil else {
                    throw AppleLooseDailyExportPlannerError.rustPlanningFailed
                }
                try checkCancellation(journal.request.jobID)
            }
            for (index, day) in journal.capturedDays.enumerated() where day.isRequestedDate {
                try await sendGeneratedProgress(
                    journal: journal,
                    day: day,
                    index: index,
                    channel: channel
                )
            }
        } else {
            var wroteDictionary = false
            for (index, day) in journal.capturedDays.enumerated() where day.isRequestedDate {
                try checkCancellation(journal.request.jobID)
                let payload = payloads[index]
                guard let record = payload.record else { continue }
                do {
                    _ = try await vault.exportHealthData(
                        record,
                        settings: settings,
                        healthSubfolder: journal.healthSubfolder,
                        writeDataDictionary: !wroteDictionary,
                        operationSurface: operationSurface,
                        frozenSettingsSnapshot: journal.settingsSnapshot
                    )
                    wroteDictionary = true
                } catch ExportError.noHealthData {
                    // A successfully captured empty day is not a failed HealthKit day.
                }
                try checkCancellation(journal.request.jobID)
                _ = try await vault.exportExternalDailyRecords(
                    payload.externalDailyRecords,
                    healthSubfolder: journal.healthSubfolder
                )
                try checkCancellation(journal.request.jobID)
                try await sendGeneratedProgress(
                    journal: journal,
                    day: day,
                    index: index,
                    channel: channel
                )
            }
            var sourceCalendar = Calendar(identifier: .gregorian)
            sourceCalendar.timeZone = TimeZone(
                identifier: journal.accepted.sourceTimeZoneIdentifier
            ) ?? .current
            let unavailable = Set(journal.capturedDays.filter { !$0.succeeded }.map {
                sourceCalendar.startOfDay(for: $0.sourceDate)
            })
            _ = try await vault.finalizeCorpusDerivedOutputs(
                recordPayloadFiles: payloadURLs,
                recordSourceDates: journal.capturedDays.map(\.sourceDate),
                settings: settings,
                requestedDates: journal.requestedDates,
                startDate: journal.requestedDates.first ?? journal.request.createdAt,
                endDate: journal.requestedDates.last ?? journal.request.createdAt,
                healthSubfolder: journal.healthSubfolder,
                archiveWorkDirectoryURL: try jobDirectory(journal.request.jobID)
                    .appendingPathComponent("archive-work", isDirectory: true),
                unavailableRollupDates: unavailable,
                writeDataDictionary: !wroteDictionary,
                cancellationCheck: { [weak self] in
                    self?.cancelledJobIDs.contains(journal.request.jobID) == true
                }
            )
        }
        try checkCancellation(journal.request.jobID)
        let dailyNotePaths = Set(journal.requestedDates.map {
            ExportPathPlanner.dailyNoteRelativePath(
                settings: settings.dailyNoteInjection,
                date: $0
            )
        })
        let aggregatePaths = Set(journal.requestedDates.flatMap { date in
            settings.exportFormats.map {
                ExportPathPlanner.aggregateRelativePath(
                    healthSubfolder: journal.healthSubfolder,
                    settings: settings,
                    date: date,
                    format: $0
                )
            }
        })
        let files = try generatedRegularFiles(in: staging)
        journal.generatedFiles = try files.map { file in
            let relativePath = try generatedRelativePath(for: file, under: staging)
            let inspected = try DirectTransferFile.inspect(file)
            let writeMode: DirectExportFileWriteMode
            if settings.dailyNoteInjection.enabled && dailyNotePaths.contains(relativePath) {
                writeMode = .mergeMarkdownPreservingPreamble
            } else if aggregatePaths.contains(relativePath) {
                switch settings.writeMode {
                case .append: writeMode = .append
                case .update where file.pathExtension.lowercased() == "md": writeMode = .mergeMarkdown
                case .update, .overwrite: writeMode = .overwrite
                }
            } else {
                writeMode = .overwrite
            }
            let manifest = try DirectExportFileManifest(
                jobID: journal.request.jobID,
                fileID: UUID(),
                relativePath: relativePath,
                byteCount: inspected.totalBytes,
                sha256: inspected.sha256,
                writeMode: writeMode
            )
            return IPhoneDirectGeneratedFile(manifest: manifest, relativePath: relativePath)
        }.sorted { $0.manifest.relativePath < $1.manifest.relativePath }
        journal.updatedAt = Date()
        try saveJournal(journal)
        return journal
    }

    private func sendGeneratedProgress(
        journal: IPhoneDirectFileJournal,
        day: IPhoneDirectCapturedDay,
        index: Int,
        channel: IPhoneDirectExportConnection
    ) async throws {
        try checkCancellation(journal.request.jobID)
        try await sendProgress(
            DirectExportProgress(
                jobID: journal.request.jobID,
                processedDays: min(index + 1, journal.requestedDates.count),
                totalDays: journal.requestedDates.count,
                currentDate: day.sourceDateIdentifier,
                committedPartitions: 0,
                committedBytes: 0,
                message: "Generated export files for \(day.sourceDateIdentifier)."
            ),
            phase: .capturing,
            channel: channel
        )
    }

    private func buildPartitions(_ journal: IPhoneDirectFileJournal) throws -> [DirectTransferPartition] {
        var partitions: [DirectTransferPartition] = []
        var previous: String?
        let staging = try stagingDirectory(journal.request.jobID)
        for file in journal.generatedFiles {
            let url = try generatedFileURL(relativePath: file.relativePath, under: staging)
            var offset: Int64 = 0
            while offset < file.manifest.byteCount {
                let byteCount = min(
                    journal.session.partitionTargetBytes,
                    file.manifest.byteCount - offset
                )
                let sha = try sha256(url: url, offset: offset, byteCount: byteCount)
                let itemID = file.manifest.fileID.uuidString.lowercased()
                partitions.append(try DirectTransferPartition(
                    index: partitions.count,
                    transferID: UUID(),
                    sourceDates: [itemID],
                    byteCount: byteCount,
                    chunkCount: Int((byteCount + Int64(DirectTransferLimits.chunkBytes) - 1)
                        / Int64(DirectTransferLimits.chunkBytes)),
                    sha256: sha,
                    previousSHA256: previous,
                    itemSegment: try DirectTransferItemSegment(
                        itemID: itemID,
                        offset: offset,
                        itemByteCount: file.manifest.byteCount,
                        isFinalSegment: offset + byteCount == file.manifest.byteCount
                    )
                ))
                previous = sha
                offset += byteCount
            }
        }
        return partitions
    }

    private func transferPartitions(
        _ journal: inout IPhoneDirectFileJournal,
        channel: IPhoneDirectExportConnection,
        protocolAuthority: AppleDirectProtocolAuthority
    ) async throws {
        for descriptor in journal.partitions {
            try checkCancellation(journal.request.jobID)
            try await channel.send(.transferOpen(try DirectTransferOpen(
                session: journal.session,
                partition: descriptor
            )))
            guard case .transferDisposition(let disposition) = try await receiveMessage(
                channel,
                jobID: journal.request.jobID
            ),
            disposition.sessionID == journal.session.sessionID,
            disposition.jobID == journal.request.jobID,
            disposition.partitionIndex == descriptor.index,
            disposition.partitionSHA256 == descriptor.sha256,
            disposition.disposition != .rejected else {
                throw IPhoneDirectFileProducerError.unexpectedResponse
            }
            if disposition.disposition == .needed {
                try await sendPartition(
                    descriptor,
                    journal: journal,
                    channel: channel,
                    protocolAuthority: protocolAuthority
                )
                let complete = try DirectTransferPartitionComplete(
                    sessionID: journal.session.sessionID,
                    jobID: journal.request.jobID,
                    partitionIndex: descriptor.index,
                    transferID: descriptor.transferID,
                    partitionSHA256: descriptor.sha256
                )
                try await channel.send(.transferPartitionComplete(complete))
                guard case .transferPartitionAcknowledgement(let acknowledgement) = try await receiveMessage(
                    channel,
                    jobID: journal.request.jobID
                ), acknowledgement.accepted,
                acknowledgement.partitionIndex == descriptor.index,
                acknowledgement.transferID == descriptor.transferID,
                acknowledgement.partitionSHA256 == descriptor.sha256 else {
                    throw IPhoneDirectFileProducerError.unexpectedResponse
                }
            }
            journal.committedPartitionCount = max(journal.committedPartitionCount, descriptor.index + 1)
            journal.committedBytes = journal.partitions
                .prefix(journal.committedPartitionCount)
                .reduce(0) { $0 + $1.byteCount }
            journal.updatedAt = Date()
            try saveJournal(journal)
            try await sendProgress(
                DirectExportProgress(
                    jobID: journal.request.jobID,
                    processedDays: journal.requestedDates.count,
                    totalDays: journal.requestedDates.count,
                    currentDate: nil,
                    committedPartitions: journal.committedPartitionCount,
                    committedBytes: journal.committedBytes,
                    message: "Sent file part \(descriptor.index + 1) of \(journal.partitions.count) to the CLI."
                ),
                phase: .transferring,
                channel: channel
            )
        }
    }

    private func sendPartition(
        _ descriptor: DirectTransferPartition,
        journal: IPhoneDirectFileJournal,
        channel: IPhoneDirectExportConnection,
        protocolAuthority: AppleDirectProtocolAuthority
    ) async throws {
        guard let itemID = descriptor.itemSegment?.itemID,
              let file = journal.generatedFiles.first(where: {
                $0.manifest.fileID.uuidString.lowercased() == itemID
              }),
              let segment = descriptor.itemSegment else {
            throw IPhoneDirectFileProducerError.invalidSpool
        }
        let staging = try stagingDirectory(journal.request.jobID)
        let url = try generatedFileURL(relativePath: file.relativePath, under: staging)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(segment.offset))
        var remaining = descriptor.byteCount
        var sequence = 1
        while remaining > 0 {
            try checkCancellation(journal.request.jobID)
            let count = Int(min(Int64(DirectTransferLimits.chunkBytes), remaining))
            guard let data = try handle.read(upToCount: count), data.count == count else {
                throw IPhoneDirectFileProducerError.invalidSpool
            }
            let chunk = try DirectTransferChunk(
                transferID: descriptor.transferID,
                sequence: sequence,
                data: data,
                sha256: DirectTransferFile.sha256Hex(data)
            )
            try await channel.sendBinaryTransferFrame(
                try protocolAuthority.encodeTransferChunk(chunk)
            )
            guard case .transferChunkAcknowledgement(let acknowledgement) = try await receiveMessage(
                channel,
                jobID: journal.request.jobID
            ), acknowledgement.accepted,
            acknowledgement.transferID == chunk.transferID,
            acknowledgement.sequence == chunk.sequence,
            acknowledgement.sha256 == chunk.sha256 else {
                throw IPhoneDirectFileProducerError.unexpectedResponse
            }
            remaining -= Int64(data.count)
            sequence += 1
        }
    }

    private func sendProgress(
        _ progress: DirectExportProgress,
        phase: CLIExportActivityTracker.Phase,
        channel: IPhoneDirectExportConnection
    ) async throws {
        CLIExportActivityTracker.shared.update(
            jobID: progress.jobID,
            source: .direct,
            phase: phase,
            processedDays: progress.processedDays,
            totalDays: progress.totalDays,
            currentDate: progress.currentDate,
            committedPartitions: progress.committedPartitions,
            committedBytes: progress.committedBytes,
            message: progress.message
        )
        try await channel.send(.exportProgress(progress))
    }

    private func receiveMessage(
        _ channel: IPhoneDirectExportConnection,
        jobID: UUID
    ) async throws -> DirectMessage {
        try checkCancellation(jobID)
        let message = try await channel.receive()
        if case .cancel(let cancelledID) = message, cancelledID == jobID {
            throw IPhoneDirectFileProducerError.cancelled
        }
        return message
    }

    private func resolveSelection(
        _ selection: DirectCanonicalSelection?
    ) throws -> CanonicalHealthDataSelection? {
        guard let selection else { return nil }
        guard selection.sourceIDs == ["apple_health"] else {
            throw IPhoneDirectFileProducerError.invalidRequest(
                "Direct file selection supports only apple_health."
            )
        }
        let catalog = HealthMetrics.all
        let catalogIDs = Set(catalog.map(\.id))
        let categories = Set(selection.categories.map { $0.lowercased() })
        var metricIDs = Set(selection.metricIDs)
        if selection.allMetrics { metricIDs.formUnion(catalogIDs) }
        metricIDs.formUnion(catalog.filter {
            categories.contains($0.category.rawValue.lowercased())
        }.map(\.id))
        guard !metricIDs.isEmpty, metricIDs.isSubset(of: catalogIDs) else {
            throw IPhoneDirectFileProducerError.invalidRequest("The file metric selection is invalid.")
        }
        return CanonicalHealthDataSelection(
            metricIDs: Array(metricIDs),
            sourceIDs: selection.sourceIDs,
            detailLevel: selection.detailLevel == .lossless ? .lossless : .summary,
            objectPaths: selection.objectPaths,
            fieldPointers: selection.fieldPointers
        )
    }

    private func makeInternalRequest(
        _ request: DirectExportRequest,
        selection: CanonicalHealthDataSelection?,
        sourceTimeZone: TimeZone
    ) throws -> IPhoneExportRequest {
        let range: (Date, Date)
        switch request.dateSelection {
        case .exact(let start, let end):
            let formatter = Self.sourceDateFormatter(timeZone: sourceTimeZone)
            guard let startDate = formatter.date(from: start),
                  let endDate = formatter.date(from: end),
                  startDate <= endDate else {
                throw IPhoneDirectFileProducerError.invalidRequest("The direct date range is invalid.")
            }
            range = (startDate, endDate)
        case .allAvailable:
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = sourceTimeZone
            let today = calendar.startOfDay(for: Date())
            range = (today, today)
        }
        return IPhoneExportRequest(
            jobID: request.jobID,
            createdAt: request.createdAt,
            dateSelection: request.dateSelection.isAllAvailable ? .allAvailable : .explicitRange,
            dateRangeStart: range.0,
            dateRangeEnd: range.1,
            requestedBy: .cli,
            settingsPolicy: request.settingsPolicy == .requestedDatesOnly
                ? .requestedDatesOnly : .currentIPhoneSettings,
            responseMode: .writeFiles,
            canonicalSelection: selection
        )
    }

    private func resolveDates(
        _ selection: DirectDateSelection,
        settings: AdvancedExportSettings,
        healthKitManager: HealthKitManager,
        sourceTimeZone: TimeZone
    ) async throws -> [Date] {
        switch selection {
        case .exact(let start, let end):
            let formatter = Self.sourceDateFormatter(timeZone: sourceTimeZone)
            guard let startDate = formatter.date(from: start),
                  let endDate = formatter.date(from: end) else {
                throw IPhoneDirectFileProducerError.invalidRequest("The direct date range is invalid.")
            }
            return sourceDateRange(from: startDate, to: endDate, timeZone: sourceTimeZone)
        case .allAvailable:
            let discovery = await healthKitManager.discoverEarliestHealthDataDate(
                enabledMetricIDs: settings.metricSelection.enabledMetrics,
                timeZone: sourceTimeZone
            )
            guard discovery.isComplete else {
                throw IPhoneDirectFileProducerError.invalidRequest(
                    "The iPhone could not prove complete earliest-date coverage."
                )
            }
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = sourceTimeZone
            let end = calendar.startOfDay(for: Date())
            let start = discovery.earliestDate.map { calendar.startOfDay(for: $0) } ?? end
            return sourceDateRange(from: start, to: end, timeZone: sourceTimeZone)
        }
    }

    private func sourceDateRange(
        from startDate: Date,
        to endDate: Date,
        timeZone: TimeZone
    ) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        var dates: [Date] = []
        var current = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        while current <= end {
            dates.append(current)
            guard let next = calendar.date(byAdding: .day, value: 1, to: current) else { break }
            current = next
        }
        return dates
    }

    private func generatedRegularFiles(in root: URL) throws -> [URL] {
        guard let enumerator = fileManager.enumerator(
            at: root,
            includingPropertiesForKeys: [.isRegularFileKey, .isSymbolicLinkKey],
            options: [.skipsHiddenFiles]
        ) else { return [] }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: [.isRegularFileKey, .isSymbolicLinkKey])
            if values.isRegularFile == true, values.isSymbolicLink != true { files.append(url) }
        }
        return files.sorted { $0.path < $1.path }
    }

    private func generatedRelativePath(for file: URL, under root: URL) throws -> String {
        let rootPath = root.standardizedFileURL.path
        let filePath = file.standardizedFileURL.path
        let prefix = rootPath.hasSuffix("/") ? rootPath : rootPath + "/"
        guard filePath.hasPrefix(prefix) else {
            throw IPhoneDirectFileProducerError.invalidSpool
        }
        let relativePath = String(filePath.dropFirst(prefix.count))
        guard !relativePath.isEmpty else {
            throw IPhoneDirectFileProducerError.invalidSpool
        }
        return relativePath
    }

    private func generatedFileURL(relativePath: String, under root: URL) throws -> URL {
        let candidate = root.appendingPathComponent(relativePath).standardizedFileURL
        guard try generatedRelativePath(for: candidate, under: root) == relativePath else {
            throw IPhoneDirectFileProducerError.invalidSpool
        }
        return candidate
    }

    private func checkCancellation(_ jobID: UUID) throws {
        if Task.isCancelled || cancelledJobIDs.contains(jobID) {
            throw IPhoneDirectFileProducerError.cancelled
        }
    }

    private func jobDirectory(_ jobID: UUID) throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let directory = applicationSupport
            .appendingPathComponent("Health.md", isDirectory: true)
            .appendingPathComponent("DirectCLIOutbound", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
            .appendingPathComponent(jobID.uuidString.lowercased(), isDirectory: true)
            .appendingPathComponent("files", isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [
                .posixPermissions: 0o700,
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
        )
        return directory
    }

    private func stagingDirectory(_ jobID: UUID) throws -> URL {
        try jobDirectory(jobID).appendingPathComponent("generated", isDirectory: true)
    }

    private func saveJournal(_ journal: IPhoneDirectFileJournal) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try protectedAtomicWrite(
            encoder.encode(journal),
            to: try jobDirectory(journal.request.jobID).appendingPathComponent("journal.json")
        )
    }

    private func loadJournal(jobID: UUID) throws -> IPhoneDirectFileJournal {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            IPhoneDirectFileJournal.self,
            from: Data(contentsOf: try jobDirectory(jobID).appendingPathComponent("journal.json"))
        )
    }

    private func protectedAtomicWrite(_ data: Data, to destination: URL) throws {
        let temporary = destination.deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).tmp")
        try data.write(to: temporary, options: .atomic)
        try fileManager.setAttributes([
            .posixPermissions: 0o600,
            .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
        ], ofItemAtPath: temporary.path)
        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: temporary)
        } else {
            try fileManager.moveItem(at: temporary, to: destination)
        }
    }

    private func sha256(url: URL, offset: Int64, byteCount: Int64) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(offset))
        var remaining = byteCount
        var hasher = SHA256()
        while remaining > 0 {
            guard let data = try handle.read(upToCount: Int(min(1_048_576, remaining))),
                  !data.isEmpty else {
                throw IPhoneDirectFileProducerError.invalidSpool
            }
            hasher.update(data: data)
            remaining -= Int64(data.count)
        }
        return Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()
    }

    private static func sourceDateFormatter(timeZone: TimeZone) -> DateFormatter {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = timeZone
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return formatter
    }
}

private extension DirectDateSelection {
    var isAllAvailable: Bool {
        if case .allAvailable = self { return true }
        return false
    }
}

private final class DirectStagingBookmarkResolver: BookmarkResolving {
    func resolveBookmark(data: Data) throws -> (url: URL, isStale: Bool) {
        guard let path = String(data: data, encoding: .utf8) else {
            throw CocoaError(.fileReadCorruptFile)
        }
        return (URL(fileURLWithPath: path), false)
    }

    func createBookmarkData(for url: URL) throws -> Data { Data(url.path.utf8) }
    func startAccessing(_ url: URL) -> Bool { true }
    func stopAccessing(_ url: URL) {}
}
#endif
