#if os(iOS)
import CryptoKit
import Foundation
import HealthMdConnectionCore
import UIKit

private enum IPhoneDirectExportError: LocalizedError {
    case invalidRequest(String)
    case requestInProgress
    case protectedDataUnavailable
    case healthKitNotAuthorized
    case exportLimitReached
    case requestChanged
    case cancelled
    case unexpectedResponse
    case invalidSpool

    var errorDescription: String? {
        switch self {
        case .invalidRequest(let message): return message
        case .requestInProgress: return "The iPhone is already preparing another direct export."
        case .protectedDataUnavailable: return "Unlock the iPhone before starting a direct export."
        case .healthKitNotAuthorized: return "HealthKit access has not been authorized for this request."
        case .exportLimitReached: return "Export limit reached. Unlock Full Access on iPhone to export more."
        case .requestChanged: return "A durable direct job with this ID has different immutable settings."
        case .cancelled: return "The direct export was cancelled."
        case .unexpectedResponse: return "The CLI sent an unexpected direct transfer response."
        case .invalidSpool: return "The durable direct export spool failed validation."
        }
    }
}

private struct IPhoneDirectRawDaySpool: Codable, Equatable {
    let manifest: DirectRawDayManifest
    let relativePath: String?
}

private enum IPhoneDirectJobState: String, Codable {
    case preparing
    case transferring
    case paused
    case completed
    case cancelled
}

private struct IPhoneDirectExpiryProbe: Decodable {
    struct Request: Decodable { let createdAt: Date }
    let request: Request
}

private struct IPhoneDirectExportJournal: Codable {
    static let currentVersion = 2

    let version: Int
    let request: DirectExportRequest
    let settingsSnapshot: ExportSettingsSnapshot
    let accepted: DirectExportAccepted
    let session: DirectTransferSession
    var days: [IPhoneDirectRawDaySpool]
    var partitions: [DirectTransferPartition]
    var committedPartitionCount: Int
    var committedBytes: Int64
    var state: IPhoneDirectJobState
    var completionRecorded: Bool
    var updatedAt: Date
}

/// iOS-side producer for strict raw and canonical projection requests. Every
/// captured day is protected-file spooled before transfer; resumability is at a
/// validated physical-partition checkpoint while logical days may exceed 64 MiB.
@MainActor
final class IPhoneDirectExportCoordinator {
    static let shared = IPhoneDirectExportCoordinator()

    private var activeJobID: UUID?
    private var cancelledJobIDs: Set<UUID> = []
    private let fileManager = FileManager.default

    var isExporting: Bool { activeJobID != nil }
    var currentJobID: UUID? { activeJobID }

    func handle(
        _ request: DirectExportRequest,
        peerBinding: DirectPeerBinding,
        negotiation: DirectTransferNegotiation,
        channel: IPhoneDirectExportConnection,
        healthKitManager: HealthKitManager,
        externalIntegrations: ExternalIntegrationDailyRecordProviding? = nil
    ) async {
        cleanupExpiredJobs()
        do {
            guard activeJobID == nil else {
                throw IPhoneDirectExportError.requestInProgress
            }
            activeJobID = request.jobID
            CLIExportActivityTracker.shared.begin(
                jobID: request.jobID,
                source: .direct,
                message: request.responseMode == .writeFiles
                    ? "Preparing files requested by the CLI…"
                    : "Preparing Apple Health data requested by the CLI…"
            )
            let completedWithoutMissingData: Bool
            if request.responseMode == .writeFiles {
                completedWithoutMissingData = try await IPhoneDirectFileExportProducer.shared.run(
                    request,
                    peerBinding: peerBinding,
                    negotiation: negotiation,
                    channel: channel,
                    healthKitManager: healthKitManager,
                    externalIntegrations: externalIntegrations
                )
            } else {
                completedWithoutMissingData = try await run(
                    request,
                    peerBinding: peerBinding,
                    negotiation: negotiation,
                    channel: channel,
                    healthKitManager: healthKitManager
                )
            }
            CLIExportActivityTracker.shared.finish(
                jobID: request.jobID,
                phase: completedWithoutMissingData ? .completed : .completedWithWarnings,
                message: completedWithoutMissingData
                    ? "The CLI export completed successfully."
                    : "The CLI export completed with missing data."
            )
        } catch {
            let failureReason = failureReason(for: error)
            var retainedForResume = false
            if request.responseMode == .writeFiles {
                IPhoneDirectFileExportProducer.shared.pause(jobID: request.jobID)
                retainedForResume = IPhoneDirectFileExportProducer.shared.canCancel(jobID: request.jobID)
            } else if var journal = try? loadJournal(jobID: request.jobID),
                      journal.state != .cancelled, journal.state != .completed {
                journal.state = .paused
                journal.updatedAt = Date()
                try? saveJournal(journal)
                retainedForResume = true
            }
            if failureReason == .cancelled {
                CLIExportActivityTracker.shared.finish(
                    jobID: request.jobID,
                    phase: .cancelled,
                    message: "The direct CLI export was cancelled."
                )
            } else if retainedForResume {
                CLIExportActivityTracker.shared.setMessage(
                    jobID: request.jobID,
                    phase: .paused,
                    message: "Direct CLI export paused. Reconnect and resume the same job."
                )
            } else {
                CLIExportActivityTracker.shared.finish(
                    jobID: request.jobID,
                    phase: .failed,
                    message: error.localizedDescription
                )
            }
            if !Task.isCancelled {
                let failure = DirectExportFailure(
                    jobID: request.jobID,
                    reason: failureReason,
                    message: error.localizedDescription
                )
                try? await channel.send(.exportRejected(failure))
            }
        }
        if activeJobID == request.jobID { activeJobID = nil }
    }

    @discardableResult
    func cancel(jobID: UUID) -> Bool {
        let rawJournal = try? loadJournal(jobID: jobID)
        let rawIsCancellable = rawJournal.map { $0.state != .completed } ?? false
        let isKnown = activeJobID == jobID
            || rawIsCancellable
            || IPhoneDirectFileExportProducer.shared.canCancel(jobID: jobID)
        guard isKnown else { return false }
        cancelledJobIDs.insert(jobID)
        CLIExportActivityTracker.shared.setMessage(
            jobID: jobID,
            message: "Cancelling the direct CLI export…"
        )
        IPhoneDirectFileExportProducer.shared.cancel(jobID: jobID)
        if var journal = rawJournal {
            journal.state = .cancelled
            journal.updatedAt = Date()
            try? saveJournal(journal)
        }
        return true
    }

    private func run(
        _ request: DirectExportRequest,
        peerBinding: DirectPeerBinding,
        negotiation: DirectTransferNegotiation,
        channel: IPhoneDirectExportConnection,
        healthKitManager: HealthKitManager
    ) async throws -> Bool {
        guard UIApplication.shared.isProtectedDataAvailable else {
            throw IPhoneDirectExportError.protectedDataUnavailable
        }
        guard request.protocolVersion == HealthMdDirectProtocol.currentVersion,
              request.createdAt <= Date().addingTimeInterval(5 * 60),
              request.createdAt.addingTimeInterval(HealthMdDirectProtocol.jobLifetime) > Date(),
              request.responseMode == .rawJSON,
              request.rawProfile != nil else {
            throw IPhoneDirectExportError.invalidRequest(
                "Direct mode currently accepts only strict raw or canonical projection requests."
            )
        }
        guard request.rawProfile != .healthDataProjection || request.canonicalSelection != nil,
              request.rawProfile != .canonicalSourceRecordsV1 || request.canonicalSelection == nil else {
            throw IPhoneDirectExportError.invalidRequest("The direct canonical selection is invalid.")
        }
        if cancelledJobIDs.contains(request.jobID) {
            throw IPhoneDirectExportError.cancelled
        }

        activeJobID = request.jobID
        let journal: IPhoneDirectExportJournal
        if let persisted = try? loadJournal(jobID: request.jobID) {
            guard persisted.version == IPhoneDirectExportJournal.currentVersion,
                  persisted.request == request else {
                throw IPhoneDirectExportError.requestChanged
            }
            guard persisted.accepted.peerBinding == peerBinding,
                  persisted.session.partitionTargetBytes == negotiation.partitionTargetBytes else {
                throw IPhoneDirectExportError.requestChanged
            }
            guard persisted.state != .cancelled else { throw IPhoneDirectExportError.cancelled }
            journal = persisted
        } else {
            let prepared = try await prepareNewJournal(
                request,
                peerBinding: peerBinding,
                negotiation: negotiation,
                healthKitManager: healthKitManager
            )
            try checkCancellation(jobID: request.jobID)
            journal = prepared
            try saveJournal(prepared)
        }

        try await channel.send(.exportAccepted(journal.accepted))
        var current = journal
        if current.days.count < current.accepted.resolvedDateIdentifiers.count {
            current = try await captureRemainingDays(
                current,
                channel: channel,
                healthKitManager: healthKitManager
            )
        }
        if current.partitions.isEmpty,
           current.days.contains(where: { $0.manifest.healthDataByteCount > 0 }) {
            current.partitions = try buildPartitions(for: current)
            current.updatedAt = Date()
            try saveJournal(current)
        }
        current.state = .transferring
        current.updatedAt = Date()
        try saveJournal(current)

        try await channel.send(.transferSession(current.session))
        for day in current.days {
            try await channel.send(.rawDayManifest(day.manifest))
        }
        try await transferPartitions(&current, channel: channel)
        let finalize = try DirectTransferFinalize(
            sessionID: current.session.sessionID,
            jobID: request.jobID,
            requestFingerprint: current.session.requestFingerprint,
            totalPartitions: current.partitions.count,
            totalBytes: current.partitions.reduce(0) { $0 + $1.byteCount },
            finalPartitionSHA256: current.partitions.last?.sha256
        )
        try await channel.send(.transferFinalize(finalize))
        let finalResponse = try await receiveMessage(channel, jobID: request.jobID)
        guard case .transferFinalAcknowledgement(let acknowledgement) = finalResponse,
              acknowledgement.accepted,
              acknowledgement.sessionID == current.session.sessionID,
              acknowledgement.jobID == request.jobID,
              acknowledgement.totalPartitions == finalize.totalPartitions,
              acknowledgement.totalBytes == finalize.totalBytes,
              acknowledgement.finalPartitionSHA256 == finalize.finalPartitionSHA256 else {
            throw IPhoneDirectExportError.unexpectedResponse
        }

        current.state = .completed
        current.updatedAt = Date()
        let successCount = current.days.filter {
            !["failed", "cancelled", "missing"].contains($0.manifest.status)
        }.count
        let shouldRecordCompletion = !current.completionRecorded && successCount > 0
        if shouldRecordCompletion {
            try PurchaseManager.shared.recordExportUse(jobID: request.jobID)
            let dates = sourceDates(
                current.accepted.resolvedDateIdentifiers,
                timeZoneIdentifier: current.accepted.sourceTimeZoneIdentifier
            )
            let result = ExportOrchestrator.ExportResult(
                successCount: successCount,
                totalCount: current.days.count,
                failedDateDetails: [],
                formatsPerDate: 0
            )
            ExportOrchestrator.recordResult(
                result,
                source: .macAgent,
                dateRangeStart: dates.first ?? request.createdAt,
                dateRangeEnd: dates.last ?? request.createdAt,
                targetLabel: "Direct CLI raw response",
                fileCount: 0,
                idempotencyKey: request.jobID
            )
            current.completionRecorded = true
        }
        // Both side effects are keyed by job ID, so a crash before this journal
        // save retries them without double charging or duplicating history.
        try saveJournal(current)
        try await channel.send(.completionConfirmed(jobID: request.jobID))
        return !current.days.contains {
            ["partial", "failed", "cancelled", "missing"].contains($0.manifest.status)
        }
    }

    private func prepareNewJournal(
        _ request: DirectExportRequest,
        peerBinding: DirectPeerBinding,
        negotiation: DirectTransferNegotiation,
        healthKitManager: HealthKitManager
    ) async throws -> IPhoneDirectExportJournal {
        let resolvedSelection = try resolveSelection(request.canonicalSelection)
        let sourceTimeZone = TimeZone.current
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
            throw IPhoneDirectExportError.healthKitNotAuthorized
        }
        if let resolvedSelection {
            let authorized = try await healthKitManager.hasRecordedAuthorizationDecision(
                forMetricIDs: Set(resolvedSelection.metricIDs)
            )
            guard authorized else { throw IPhoneDirectExportError.healthKitNotAuthorized }
        }
        let dates = try await resolveDates(
            request.dateSelection,
            settings: settings,
            healthKitManager: healthKitManager,
            sourceTimeZone: sourceTimeZone
        )
        guard !dates.isEmpty else {
            throw IPhoneDirectExportError.invalidRequest("The requested source date range is empty.")
        }
        await PurchaseManager.shared.refreshStatus()
        guard PurchaseManager.shared.canExport else {
            throw IPhoneDirectExportError.exportLimitReached
        }

        let identifiers = dates.map(Self.sourceDateFormatter(timeZone: sourceTimeZone).string(from:))
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
            requestFingerprint: try DirectRequestFingerprint.make(for: request),
            peerBinding: peerBinding,
            partitionTargetBytes: negotiation.partitionTargetBytes,
            createdAt: Date()
        )
        return IPhoneDirectExportJournal(
            version: IPhoneDirectExportJournal.currentVersion,
            request: request,
            settingsSnapshot: ExportSettingsSnapshot.from(settings),
            accepted: accepted,
            session: session,
            days: [],
            partitions: [],
            committedPartitionCount: 0,
            committedBytes: 0,
            state: .preparing,
            completionRecorded: false,
            updatedAt: Date()
        )
    }

    private func captureRemainingDays(
        _ supplied: IPhoneDirectExportJournal,
        channel: IPhoneDirectExportConnection,
        healthKitManager: HealthKitManager
    ) async throws -> IPhoneDirectExportJournal {
        var journal = supplied
        let settings = journal.settingsSnapshot.makeAdvancedExportSettings()
        settings.exportTimeZoneOverride = TimeZone(
            identifier: journal.accepted.sourceTimeZoneIdentifier
        )
        let dates = sourceDates(
            journal.accepted.resolvedDateIdentifiers,
            timeZoneIdentifier: journal.accepted.sourceTimeZoneIdentifier
        )
        guard dates.count == journal.accepted.resolvedDateIdentifiers.count else {
            throw IPhoneDirectExportError.invalidSpool
        }
        for index in journal.days.count..<dates.count {
            try checkCancellation(jobID: journal.request.jobID)
            let date = dates[index]
            let identifier = journal.accepted.resolvedDateIdentifiers[index]
            try await sendProgress(
                DirectExportProgress(
                    jobID: journal.request.jobID,
                    processedDays: index,
                    totalDays: dates.count,
                    currentDate: identifier,
                    committedPartitions: journal.committedPartitionCount,
                    committedBytes: journal.committedBytes,
                    message: "Capturing \(identifier) from HealthKit…"
                ),
                phase: .capturing,
                channel: channel
            )
            let expectsLosslessArchive = settings.includeGranularData
            let outcome = try await HealthKitDailyCapture.capture(
                date: date,
                includeGranularData: expectsLosslessArchive,
                metricSelection: settings.metricSelection,
                transform: .sanitizeGranularAndFilter,
                emptyRecordPolicy: .retain,
                fetchExternalRecords: false,
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
                fetchExternalDailyRecords: nil
            )
            // Cancellation may arrive while HealthKit is awaiting its query.
            // Re-check before this task can overwrite the durable cancelled tombstone.
            try checkCancellation(jobID: journal.request.jobID)
            let result: CanonicalRawDayResult
            if let record = outcome.record {
                do {
                    result = try CanonicalRawDayResult.captured(
                        record,
                        customization: settings.formatCustomization,
                        expectsLosslessArchive: expectsLosslessArchive
                    )
                } catch {
                    result = .failed(date: identifier, code: "healthkit_error")
                }
            } else {
                result = .failed(
                    date: identifier,
                    code: outcome.failure?.reason.rawValue ?? "healthkit_error"
                )
            }
            let spool = try spool(result, jobID: journal.request.jobID, dayIndex: index)
            journal.days.append(spool)
            journal.updatedAt = Date()
            try saveJournal(journal)
            try await sendProgress(
                DirectExportProgress(
                    jobID: journal.request.jobID,
                    processedDays: index + 1,
                    totalDays: dates.count,
                    currentDate: identifier,
                    committedPartitions: journal.committedPartitionCount,
                    committedBytes: journal.committedBytes,
                    message: "Prepared \(identifier) for transfer to the CLI."
                ),
                phase: .capturing,
                channel: channel
            )
        }
        return journal
    }

    private func spool(
        _ day: CanonicalRawDayResult,
        jobID: UUID,
        dayIndex: Int
    ) throws -> IPhoneDirectRawDaySpool {
        let data = day.canonicalDailyJSON.map { Data($0.utf8) }
        let relativePath: String?
        if let data {
            relativePath = String(format: "day-%08d.json", dayIndex)
            try protectedAtomicWrite(data, to: try jobDirectory(jobID).appendingPathComponent(relativePath!))
        } else {
            relativePath = nil
        }
        let manifest = try DirectRawDayManifest(
            jobID: jobID,
            date: day.date,
            status: day.status.rawValue,
            captureStatus: day.captureStatus.map(HealthKitRecordArchiveSerializer.captureStatusString),
            sampleCount: day.sampleCount,
            recordCount: day.recordCount,
            queryStatusCounts: [
                "success": day.queryStatusCounts.success,
                "failure": day.queryStatusCounts.failure,
                "unsupported": day.queryStatusCounts.unsupported,
                "skipped": day.queryStatusCounts.skipped,
                "cancelled": day.queryStatusCounts.cancelled
            ],
            integrityWarningCount: day.integrityWarningCount,
            integrityWarningCodes: day.integrityWarningCodes,
            partialFailureCount: day.partialFailureCount,
            partialFailureTypes: day.partialFailureTypes,
            failureCode: day.failureCode,
            healthDataByteCount: Int64(data?.count ?? 0),
            healthDataSHA256: data.map(DirectTransferFile.sha256Hex)
        )
        return IPhoneDirectRawDaySpool(manifest: manifest, relativePath: relativePath)
    }

    private func buildPartitions(
        for journal: IPhoneDirectExportJournal
    ) throws -> [DirectTransferPartition] {
        var result: [DirectTransferPartition] = []
        var previousSHA: String?
        for day in journal.days {
            guard let relativePath = day.relativePath else { continue }
            let url = try jobDirectory(journal.request.jobID).appendingPathComponent(relativePath)
            var offset: Int64 = 0
            while offset < day.manifest.healthDataByteCount {
                let byteCount = min(
                    journal.session.partitionTargetBytes,
                    day.manifest.healthDataByteCount - offset
                )
                let sha = try sha256(url: url, offset: offset, byteCount: byteCount)
                let descriptor = try DirectTransferPartition(
                    index: result.count,
                    transferID: UUID(),
                    sourceDates: [day.manifest.date],
                    byteCount: byteCount,
                    chunkCount: Int((byteCount + Int64(DirectTransferLimits.chunkBytes) - 1)
                        / Int64(DirectTransferLimits.chunkBytes)),
                    sha256: sha,
                    previousSHA256: previousSHA,
                    itemSegment: try DirectTransferItemSegment(
                        itemID: day.manifest.date,
                        offset: offset,
                        itemByteCount: day.manifest.healthDataByteCount,
                        isFinalSegment: offset + byteCount == day.manifest.healthDataByteCount
                    )
                )
                result.append(descriptor)
                previousSHA = sha
                offset += byteCount
            }
        }
        return result
    }

    private func transferPartitions(
        _ journal: inout IPhoneDirectExportJournal,
        channel: IPhoneDirectExportConnection
    ) async throws {
        for descriptor in journal.partitions {
            try checkCancellation(jobID: journal.request.jobID)
            let open = try DirectTransferOpen(session: journal.session, partition: descriptor)
            try await channel.send(.transferOpen(open))
            let response = try await receiveMessage(channel, jobID: journal.request.jobID)
            guard case .transferDisposition(let disposition) = response,
                  disposition.sessionID == journal.session.sessionID,
                  disposition.jobID == journal.request.jobID,
                  disposition.partitionIndex == descriptor.index,
                  disposition.partitionSHA256 == descriptor.sha256,
                  disposition.disposition != .rejected else {
                throw IPhoneDirectExportError.unexpectedResponse
            }
            if disposition.disposition == .needed {
                try await sendPartition(descriptor, journal: journal, channel: channel)
                let complete = try DirectTransferPartitionComplete(
                    sessionID: journal.session.sessionID,
                    jobID: journal.request.jobID,
                    partitionIndex: descriptor.index,
                    transferID: descriptor.transferID,
                    partitionSHA256: descriptor.sha256
                )
                try await channel.send(.transferPartitionComplete(complete))
                let completionResponse = try await receiveMessage(channel, jobID: journal.request.jobID)
                guard case .transferPartitionAcknowledgement(let acknowledgement) = completionResponse,
                      acknowledgement.accepted,
                      acknowledgement.sessionID == journal.session.sessionID,
                      acknowledgement.jobID == journal.request.jobID,
                      acknowledgement.partitionIndex == descriptor.index,
                      acknowledgement.transferID == descriptor.transferID,
                      acknowledgement.partitionSHA256 == descriptor.sha256 else {
                    throw IPhoneDirectExportError.unexpectedResponse
                }
            }
            journal.committedPartitionCount = max(
                journal.committedPartitionCount,
                descriptor.index + 1
            )
            journal.committedBytes = journal.partitions
                .prefix(journal.committedPartitionCount)
                .reduce(0) { $0 + $1.byteCount }
            journal.updatedAt = Date()
            try saveJournal(journal)
            try await sendProgress(
                DirectExportProgress(
                    jobID: journal.request.jobID,
                    processedDays: completedDayCount(journal),
                    totalDays: journal.days.count,
                    currentDate: descriptor.itemSegment?.itemID,
                    committedPartitions: journal.committedPartitionCount,
                    committedBytes: journal.committedBytes,
                    message: "Sent transfer part \(descriptor.index + 1) of \(journal.partitions.count) to the CLI."
                ),
                phase: .transferring,
                channel: channel
            )
        }
    }

    private func sendPartition(
        _ descriptor: DirectTransferPartition,
        journal: IPhoneDirectExportJournal,
        channel: IPhoneDirectExportConnection
    ) async throws {
        guard let segment = descriptor.itemSegment,
              let day = journal.days.first(where: { $0.manifest.date == segment.itemID }),
              let relativePath = day.relativePath else {
            throw IPhoneDirectExportError.invalidSpool
        }
        let url = try jobDirectory(journal.request.jobID).appendingPathComponent(relativePath)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(segment.offset))
        var remaining = descriptor.byteCount
        var sequence = 1
        while remaining > 0 {
            try checkCancellation(jobID: journal.request.jobID)
            let count = Int(min(Int64(DirectTransferLimits.chunkBytes), remaining))
            guard let data = try handle.read(upToCount: count), data.count == count else {
                throw IPhoneDirectExportError.invalidSpool
            }
            let chunk = try DirectTransferChunk(
                transferID: descriptor.transferID,
                sequence: sequence,
                data: data,
                sha256: DirectTransferFile.sha256Hex(data)
            )
            try await channel.sendBinaryTransferFrame(try DirectTransferBinaryFrame.encode(chunk))
            let response = try await receiveMessage(channel, jobID: journal.request.jobID)
            guard case .transferChunkAcknowledgement(let acknowledgement) = response,
                  acknowledgement.accepted,
                  acknowledgement.transferID == chunk.transferID,
                  acknowledgement.sequence == chunk.sequence,
                  acknowledgement.sha256 == chunk.sha256 else {
                throw IPhoneDirectExportError.unexpectedResponse
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
        try checkCancellation(jobID: jobID)
        let message = try await channel.receive()
        if case .cancel(let cancelledID) = message, cancelledID == jobID {
            throw IPhoneDirectExportError.cancelled
        }
        return message
    }

    private func resolveSelection(
        _ selection: DirectCanonicalSelection?
    ) throws -> CanonicalHealthDataSelection? {
        guard let selection else { return nil }
        guard selection.sourceIDs == ["apple_health"] else {
            throw IPhoneDirectExportError.invalidRequest(
                "Direct canonical extraction currently supports only the apple_health source."
            )
        }
        let catalog = HealthMetrics.all
        let catalogIDs = Set(catalog.map(\.id))
        let requestedCategories = Set(selection.categories.map {
            $0.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        })
        var metricIDs = Set(selection.metricIDs)
        if selection.allMetrics { metricIDs.formUnion(catalogIDs) }
        if !requestedCategories.isEmpty {
            metricIDs.formUnion(catalog.filter {
                requestedCategories.contains($0.category.rawValue.lowercased())
            }.map(\.id))
        }
        guard !metricIDs.isEmpty,
              metricIDs.isSubset(of: catalogIDs) else {
            throw IPhoneDirectExportError.invalidRequest(
                "The direct canonical selection contains unknown or empty metric scope."
            )
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
        let dates: (Date, Date)
        switch request.dateSelection {
        case .exact(let start, let end):
            let formatter = Self.sourceDateFormatter(timeZone: sourceTimeZone)
            guard let startDate = formatter.date(from: start),
                  let endDate = formatter.date(from: end),
                  startDate <= endDate else {
                throw IPhoneDirectExportError.invalidRequest("The direct date range is invalid.")
            }
            dates = (startDate, endDate)
        case .allAvailable:
            var calendar = Calendar(identifier: .gregorian)
            calendar.timeZone = sourceTimeZone
            let today = calendar.startOfDay(for: Date())
            dates = (today, today)
        }
        return IPhoneExportRequest(
            jobID: request.jobID,
            createdAt: request.createdAt,
            dateSelection: request.dateSelection.isAllAvailable ? .allAvailable : .explicitRange,
            dateRangeStart: dates.0,
            dateRangeEnd: dates.1,
            requestedDateIdentifiers: nil,
            requestedBy: .cli,
            settingsPolicy: request.settingsPolicy == .requestedDatesOnly
                ? .requestedDatesOnly : .currentIPhoneSettings,
            responseMode: .rawJSON,
            rawProfile: request.rawProfile == .healthDataProjection
                ? .healthDataProjection : .canonicalSourceRecordsV1,
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
                  let endDate = formatter.date(from: end),
                  startDate <= endDate else {
                throw IPhoneDirectExportError.invalidRequest("The direct date range is invalid.")
            }
            return sourceDateRange(from: startDate, to: endDate, timeZone: sourceTimeZone)
        case .allAvailable:
            let discovery = await healthKitManager.discoverEarliestHealthDataDate(
                enabledMetricIDs: settings.metricSelection.enabledMetrics,
                timeZone: sourceTimeZone
            )
            guard discovery.isComplete else {
                let missing = discovery.unresolvedMetricIDs + discovery.failedTypeIdentifiers
                throw IPhoneDirectExportError.invalidRequest(
                    "The iPhone could not prove complete earliest-date coverage for: \(missing.joined(separator: ", "))."
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

    private func completedDayCount(_ journal: IPhoneDirectExportJournal) -> Int {
        let completed = Set(journal.partitions
            .prefix(journal.committedPartitionCount)
            .compactMap { $0.itemSegment?.isFinalSegment == true ? $0.itemSegment?.itemID : nil })
        let empty = Set(journal.days.filter { $0.manifest.healthDataByteCount == 0 }.map { $0.manifest.date })
        return completed.union(empty).count
    }

    private func checkCancellation(jobID: UUID) throws {
        if Task.isCancelled || cancelledJobIDs.contains(jobID) {
            throw IPhoneDirectExportError.cancelled
        }
    }

    private func failureReason(for error: Error) -> DirectExportFailureReason {
        switch error {
        case IPhoneDirectExportError.requestInProgress: return .requestInProgress
        case IPhoneDirectExportError.protectedDataUnavailable: return .protectedDataUnavailable
        case IPhoneDirectExportError.healthKitNotAuthorized: return .healthKitNotAuthorized
        case IPhoneDirectExportError.exportLimitReached: return .exportLimitReached
        case IPhoneDirectExportError.cancelled,
             IPhoneDirectFileProducerError.cancelled:
            return .cancelled
        case IPhoneDirectExportError.invalidRequest(_), IPhoneDirectExportError.requestChanged,
             IPhoneDirectFileProducerError.invalidRequest(_),
             IPhoneDirectFileProducerError.requestChanged:
            return .invalidRequest
        case IPhoneDirectFileProducerError.healthKitNotAuthorized:
            return .healthKitNotAuthorized
        case IPhoneDirectFileProducerError.exportLimitReached:
            return .exportLimitReached
        default: return .internalFailure
        }
    }

    func cleanupExpiredJobs(now: Date = Date()) {
        guard let root = try? jobsRootDirectory(),
              let directories = try? fileManager.contentsOfDirectory(
                at: root,
                includingPropertiesForKeys: [.isDirectoryKey, .creationDateKey, .contentModificationDateKey],
                options: [.skipsHiddenFiles]
              ) else { return }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        for directory in directories {
            let candidates = [
                directory.appendingPathComponent("journal.json"),
                directory.appendingPathComponent("files/journal.json")
            ]
            let journalURL = candidates.first(where: { fileManager.fileExists(atPath: $0.path) })
            let probe = journalURL
                .flatMap { try? Data(contentsOf: $0) }
                .flatMap { try? decoder.decode(IPhoneDirectExpiryProbe.self, from: $0) }
            let shouldRemove: Bool
            if let probe {
                shouldRemove = probe.request.createdAt
                    .addingTimeInterval(HealthMdDirectProtocol.jobLifetime) <= now
            } else {
                let values = try? directory.resourceValues(
                    forKeys: [.creationDateKey, .contentModificationDateKey]
                )
                let oldestSafeReference = values?.creationDate ?? values?.contentModificationDate
                shouldRemove = oldestSafeReference.map {
                    $0.addingTimeInterval(HealthMdDirectProtocol.jobLifetime) <= now
                } ?? false
            }
            if shouldRemove { try? fileManager.removeItem(at: directory) }
        }
    }

    private func jobsRootDirectory() throws -> URL {
        let applicationSupport = try fileManager.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        let root = applicationSupport
            .appendingPathComponent("Health.md", isDirectory: true)
            .appendingPathComponent("DirectCLIOutbound", isDirectory: true)
            .appendingPathComponent("v1", isDirectory: true)
        try fileManager.createDirectory(
            at: root,
            withIntermediateDirectories: true,
            attributes: [
                .posixPermissions: 0o700,
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableRoot = root
        try? mutableRoot.setResourceValues(values)
        return root
    }

    private func jobDirectory(_ jobID: UUID) throws -> URL {
        let directory = try jobsRootDirectory()
            .appendingPathComponent(jobID.uuidString.lowercased(), isDirectory: true)
        try fileManager.createDirectory(
            at: directory,
            withIntermediateDirectories: true,
            attributes: [
                .posixPermissions: 0o700,
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication
            ]
        )
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        var mutableDirectory = directory
        try? mutableDirectory.setResourceValues(values)
        return directory
    }

    private func saveJournal(_ journal: IPhoneDirectExportJournal) throws {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        try protectedAtomicWrite(
            encoder.encode(journal),
            to: try jobDirectory(journal.request.jobID).appendingPathComponent("journal.json")
        )
    }

    private func loadJournal(jobID: UUID) throws -> IPhoneDirectExportJournal {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(
            IPhoneDirectExportJournal.self,
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
            let count = Int(min(1_048_576, remaining))
            guard let data = try handle.read(upToCount: count), !data.isEmpty else {
                throw IPhoneDirectExportError.invalidSpool
            }
            hasher.update(data: data)
            remaining -= Int64(data.count)
        }
        return Data(hasher.finalize()).map { String(format: "%02x", $0) }.joined()
    }

    private func sourceDates(
        _ identifiers: [String],
        timeZoneIdentifier: String
    ) -> [Date] {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(identifier: timeZoneIdentifier)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        return identifiers.compactMap(formatter.date(from:))
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
#endif
