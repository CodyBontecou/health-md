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
    /// Warnings that reduce capture completeness. Nil identifies a checkpoint
    /// written before the informational/degrading split was tracked; consumers
    /// fall back to the manifest's total so legacy checkpoints keep the
    /// behavior they were written with.
    let degradingFailureCount: Int?
    /// Same contract as the manifest-derived "day had warnings", excluding
    /// informational omissions (for example a WorkoutKit plan this device
    /// cannot decode) that do not reduce the export below full success.
    let hadDegradingWarnings: Bool?
    /// Informational-only warnings surfaced so Export History can show them as
    /// export notes without degrading the entry's status.
    let informationalFailures: [ExportPartialFailure]?

    init(
        manifest: DirectRawDayManifest,
        relativePath: String?,
        degradingFailureCount: Int? = nil,
        hadDegradingWarnings: Bool? = nil,
        informationalFailures: [ExportPartialFailure]? = nil
    ) {
        self.manifest = manifest
        self.relativePath = relativePath
        self.degradingFailureCount = degradingFailureCount.map { max($0, 0) }
        self.hadDegradingWarnings = hadDegradingWarnings
        self.informationalFailures = informationalFailures
    }

    var resolvedDegradingFailureCount: Int {
        degradingFailureCount ?? manifest.partialFailureCount
    }

    var resolvedHadDegradingWarnings: Bool {
        if let hadDegradingWarnings { return hadDegradingWarnings }
        let manifestStatuses: Set<String> = ["partial", "complete_with_warnings"]
        return manifestStatuses.contains(manifest.status)
    }
}

private enum IPhoneDirectJobState: String, Codable {
    case preparing
    case transferring
    case paused
    case completed
    case cancelled
}

private struct IPhoneDirectExportJournal: Codable {
    static let legacyProtocolVersion = 2
    static let currentVersion = 3

    var checkpoint = AppleExportJournalCheckpoint()

    private enum CodingKeys: String, CodingKey {
        case version, request, settingsSnapshot, accepted, session
        case appleDirectProtocolPin, days, partitions, committedPartitionCount, committedBytes
        case state, completionRecorded, updatedAt
    }

    let version: Int
    let request: DirectExportRequest
    let settingsSnapshot: ExportSettingsSnapshot
    let accepted: DirectExportAccepted
    let session: DirectTransferSession
    let appleDirectProtocolPin: AppleDirectProtocolPin?
    var days: [IPhoneDirectRawDaySpool]
    var partitions: [DirectTransferPartition]
    var committedPartitionCount: Int
    var committedBytes: Int64
    var state: IPhoneDirectJobState
    var completionRecorded: Bool
    var updatedAt: Date
}

nonisolated final class IPhoneDirectCancellationInvocation: @unchecked Sendable {
    let jobID: UUID
    private let lock = NSRecursiveLock()
    private var active = true
    private var cancelled = false
    private var checkpoint: AppleExportJournalCheckpoint?
    private var retainedProtocolAuthority: AppleDirectProtocolAuthority?

    init(jobID: UUID, protocolAuthority: AppleDirectProtocolAuthority? = nil) {
        self.jobID = jobID
        retainedProtocolAuthority = protocolAuthority
    }
    var cancellationProtocolAuthority: AppleDirectProtocolAuthority? {
        lock.withLock { retainedProtocolAuthority }
    }
    func bindProtocolAuthority(_ retained: AppleDirectProtocolAuthority) {
        lock.withLock { retainedProtocolAuthority = retained }
    }
    var isCancelled: Bool { lock.withLock { cancelled } }
    var ownership: AppleExportJournalCheckpoint? { lock.withLock { checkpoint } }
    func cancel() { lock.withLock { cancelled = true } }
    func finish() { lock.withLock { active = false } }
    func bind(_ ownership: AppleExportJournalCheckpoint) {
        lock.withLock { checkpoint = ownership }
    }
    func acquireAcknowledgementLease() throws -> any DirectPacketSendLease {
        lock.lock()
        guard active, cancelled else {
            lock.unlock()
            throw DirectChannelError.authenticationFailed("The cancelled preparation is no longer active.")
        }
        return IPhoneDirectCancellationEnqueueLease(lock: lock)
    }
}

nonisolated private final class IPhoneDirectCancellationEnqueueLease: DirectPacketSendLease {
    private var lock: NSRecursiveLock?
    init(lock: NSRecursiveLock) { self.lock = lock }
    func close() {
        let held = lock
        lock = nil
        held?.unlock()
    }
    deinit { close() }
}

nonisolated struct IPhoneDirectCancellationReceipt: Sendable {
    let jobID: UUID
    private let owner: Owner
    private let retainedProtocolAuthority: AppleDirectProtocolAuthority?
    var durableOwnership: AppleExportJournalCheckpoint? {
        if case .durable(let checkpoint) = owner { return checkpoint }
        return nil
    }
    private enum Owner: Sendable {
        case preparation(IPhoneDirectCancellationInvocation)
        case durable(AppleExportJournalCheckpoint)
    }
    init(invocation: IPhoneDirectCancellationInvocation) {
        jobID = invocation.jobID
        owner = .preparation(invocation)
        retainedProtocolAuthority = invocation.cancellationProtocolAuthority
    }
    init(jobID: UUID, ownership: AppleExportJournalCheckpoint,
         protocolAuthority: AppleDirectProtocolAuthority? = nil) {
        self.jobID = jobID
        owner = .durable(ownership)
        retainedProtocolAuthority = protocolAuthority
    }
    private var acknowledgementAuthorization: DirectPacketSendAuthorization {
        switch owner {
        case .preparation(let invocation):
            return DirectPacketSendAuthorization { try invocation.acquireAcknowledgementLease() }
        case .durable(let checkpoint):
            return DirectPacketSendAuthorization {
                let lease = try checkpoint.acquireEnqueueLease()
                do {
                    try checkpoint.withCheckpointOwnership {}
                    return lease
                } catch {
                    lease.close()
                    throw error
                }
            }
        }
    }
    func sendAcknowledgement(on channel: DirectSecureChannel) async throws {
        if let retainedProtocolAuthority {
            try await channel.send(.cancelAcknowledged(jobID: jobID), authorization: acknowledgementAuthorization,
                messageCanonicalizer: retainedProtocolAuthority)
        } else {
            try await channel.send(.cancelAcknowledged(jobID: jobID), authorization: acknowledgementAuthorization)
        }
    }
}

nonisolated enum IPhoneDirectCancellationScope {
    @TaskLocal static var current: IPhoneDirectCancellationInvocation?
    static func isCancelled(jobID: UUID) -> Bool {
        current?.jobID == jobID && current?.isCancelled == true
    }
}

/// iOS-side producer for strict raw and canonical projection requests. Every
/// captured day is protected-file spooled before transfer; resumability is at a
/// validated physical-partition checkpoint while logical days may exceed 64 MiB.
@MainActor
final class IPhoneDirectExportCoordinator {
    static let shared = IPhoneDirectExportCoordinator()

    private var activeJobID: UUID?
    private var activeCancellation: IPhoneDirectCancellationInvocation?
    private struct AcceptedQueryController {
        let ownership: AppleExportJournalCheckpoint
        let controller: HealthKitQueryExecutionController
    }
    private var queryExecutionControllers: [UUID: AcceptedQueryController] = [:]
    private let fileManager = FileManager.default

    var isExporting: Bool { activeJobID != nil }
    var currentJobID: UUID? { activeJobID }

    func handle(
        _ request: DirectExportRequest,
        peerBinding: DirectPeerBinding,
        negotiation: DirectTransferNegotiation,
        channel: IPhoneDirectExportConnection,
        protocolAuthority: AppleDirectProtocolAuthority,
        healthKitManager: HealthKitManager,
        externalIntegrations: ExternalIntegrationDailyRecordProviding? = nil
    ) async {
        guard activeJobID == nil else {
            if !Task.isCancelled {
                try? await channel.send(.exportRejected(DirectExportFailure(
                    jobID: request.jobID,
                    reason: .requestInProgress,
                    message: IPhoneDirectExportError.requestInProgress.localizedDescription
                )))
            }
            return
        }
        let invocation = IPhoneDirectCancellationInvocation(jobID: request.jobID,
            protocolAuthority: protocolAuthority.frozenForCurrentOperation())
        activeJobID = request.jobID
        activeCancellation = invocation
        defer {
            invocation.finish()
            if activeCancellation === invocation { activeCancellation = nil }
            if activeJobID == request.jobID { activeJobID = nil }
        }
        await IPhoneDirectCancellationScope.$current.withValue(invocation) {
            await handleAdmitted(request, peerBinding: peerBinding, negotiation: negotiation,
                channel: channel, protocolAuthority: protocolAuthority,
                healthKitManager: healthKitManager, externalIntegrations: externalIntegrations)
        }
    }

    private func handleAdmitted(
        _ request: DirectExportRequest,
        peerBinding: DirectPeerBinding,
        negotiation: DirectTransferNegotiation,
        channel: IPhoneDirectExportConnection,
        protocolAuthority: AppleDirectProtocolAuthority,
        healthKitManager: HealthKitManager,
        externalIntegrations: ExternalIntegrationDailyRecordProviding?
    ) async {
        cleanupExpiredJobs()
        #if DEBUG
        let rawPerformanceSpan = request.responseMode == .writeFiles
            ? nil
            : ExportPerformanceInstrumentation.beginSpan(
                pipeline: "direct-raw",
                phase: "job"
            )
        var rawPerformanceOutcome = ExportPerformanceSpanOutcome.failure
        defer { rawPerformanceSpan?.finish(outcome: rawPerformanceOutcome) }
        #endif
        defer { protocolAuthority.endOperation() }
        var executionController: HealthKitQueryExecutionController?
        var executionOwnership: AppleExportJournalCheckpoint?
        do {
            // Preparation has no durable generation yet. Retained controller
            // state is selected only after the producer acquires its journal.
            let queryController = HealthKitQueryExecutionController()
            CLIExportActivityTracker.shared.begin(
                jobID: request.jobID,
                source: .direct,
                targetLabel: activityTargetLabel(for: request),
                message: request.responseMode == .writeFiles
                    ? "Preparing files requested by the CLI…"
                    : "Preparing Apple Health data requested by the CLI…"
            )
            let completedWithoutMissingData = try await HealthKitQueryExecutionController
                .withController(queryController) {
                    if request.responseMode == .writeFiles {
                        return try await IPhoneDirectFileExportProducer.shared.run(
                            request,
                            peerBinding: peerBinding,
                            negotiation: negotiation,
                            channel: channel,
                            protocolAuthority: protocolAuthority,
                            healthKitManager: healthKitManager,
                            externalIntegrations: externalIntegrations,
                            didAcquireOwnership: { ownership in
                                executionOwnership = ownership
                                IPhoneDirectCancellationScope.current?.bind(ownership)
                                let acceptedController = try queryControllerForAcceptedGeneration(
                                    jobID: request.jobID, ownership: ownership, fallback: queryController)
                                executionController = acceptedController
                                return acceptedController
                            }
                        )
                    }
                    return try await run(
                        request,
                        peerBinding: peerBinding,
                        negotiation: negotiation,
                        channel: channel,
                        protocolAuthority: protocolAuthority,
                        healthKitManager: healthKitManager,
                        didAcquireOwnership: { ownership in
                            executionOwnership = ownership
                            IPhoneDirectCancellationScope.current?.bind(ownership)
                            let acceptedController = try queryControllerForAcceptedGeneration(
                                jobID: request.jobID, ownership: ownership, fallback: queryController)
                            executionController = acceptedController
                            return acceptedController
                        }
                    )
                }
            if let executionController {
                releaseQueryController(jobID: request.jobID, controller: executionController)
            }
            publishActivityOutcome(
                jobID: request.jobID,
                ownership: executionOwnership,
                phase: completedWithoutMissingData ? .completed : .completedWithWarnings,
                message: completedWithoutMissingData
                    ? "The CLI export completed successfully."
                    : "The CLI export completed with missing data."
            )
            #if DEBUG
            rawPerformanceOutcome = .success
            #endif
        } catch {
            let failureReason = failureReason(for: error)
            #if DEBUG
            if failureReason == .cancelled {
                rawPerformanceOutcome = .cancelled
            }
            #endif
            let checkpointConflict: Bool
            switch error {
            case IPhoneDirectExportError.requestChanged, IPhoneDirectFileProducerError.requestChanged:
                checkpointConflict = true
            default:
                checkpointConflict = false
            }
            var retainedForResume = false
            if !checkpointConflict, let executionOwnership {
                if request.responseMode == .writeFiles {
                    retainedForResume = IPhoneDirectFileExportProducer.shared.pause(
                        jobID: request.jobID, ownership: executionOwnership
                    )
                } else {
                    retainedForResume = (try? executionOwnership.withGenerationOwnership {
                        guard var journal = try loadJournal(jobID: request.jobID),
                              journal.state != .cancelled, journal.state != .completed else { return false }
                        journal.state = .paused
                        journal.updatedAt = Date()
                        try saveJournal(&journal)
                        return true
                    }) ?? false
                }
            }
            if let executionController,
               (failureReason == .cancelled || !retainedForResume) {
                releaseQueryController(jobID: request.jobID, controller: executionController)
            }
            if failureReason == .cancelled {
                publishActivityOutcome(
                    jobID: request.jobID,
                    ownership: executionOwnership,
                    phase: .cancelled,
                    message: "The direct CLI export was cancelled."
                )
            } else if retainedForResume {
                publishActivityOutcome(
                    jobID: request.jobID,
                    ownership: executionOwnership,
                    phase: .paused,
                    message: "Direct CLI export paused. Reconnect and resume the same job."
                )
            } else {
                publishActivityOutcome(
                    jobID: request.jobID,
                    ownership: executionOwnership,
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
                if let executionOwnership {
                    // A still-owned cancellation failure may report its terminal outcome.
                    try? await executionOwnership.continueWhileOwned {
                        try await channel.send(.exportRejected(failure), ownership: executionOwnership)
                    }
                } else {
                    try? await channel.send(.exportRejected(failure))
                }
            }
        }
    }

    private func activityTargetLabel(for request: DirectExportRequest) -> String {
        guard request.responseMode == .writeFiles else {
            return request.rawProfile == .healthDataProjection ? "Canonical JSON" : "Raw JSON"
        }
        guard let rootPath = request.destination?.rootPath else {
            return "Selected folder"
        }
        let component = rootPath
            .split(whereSeparator: { $0 == "/" || $0 == "\\" })
            .last
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        guard let component, !component.isEmpty else { return "Selected folder" }
        return component
    }

    func queryControllerForAcceptedGeneration(
        jobID: UUID,
        ownership: AppleExportJournalCheckpoint,
        fallback: HealthKitQueryExecutionController
    ) throws -> HealthKitQueryExecutionController {
        try ownership.withGenerationOwnership {
            if let retained = queryExecutionControllers[jobID],
               retained.ownership.generation == ownership.generation,
               retained.ownership.completionIdentity == ownership.completionIdentity,
               retained.ownership.journalURL == ownership.journalURL,
               retained.ownership.publicationLockURL == ownership.publicationLockURL {
                return retained.controller
            }
            queryExecutionControllers[jobID] = AcceptedQueryController(
                ownership: ownership, controller: fallback)
            return fallback
        }
    }

    func releaseQueryController(jobID: UUID, controller: HealthKitQueryExecutionController) {
        guard queryExecutionControllers[jobID]?.controller === controller else { return }
        queryExecutionControllers.removeValue(forKey: jobID)
    }

    @discardableResult
    func publishActivityOutcome(
        jobID: UUID,
        ownership: AppleExportJournalCheckpoint?,
        phase: CLIExportActivityTracker.Phase,
        message: String
    ) -> Bool {
        let publish = {
            if phase.isTerminal {
                CLIExportActivityTracker.shared.finish(jobID: jobID, phase: phase, message: message)
            } else {
                CLIExportActivityTracker.shared.setMessage(jobID: jobID, phase: phase, message: message)
            }
        }
        if let ownership {
            do {
                try ownership.withGenerationOwnership { publish() }
            } catch {
                return false
            }
        } else {
            publish()
        }
        return true
    }

    @discardableResult
    func cancel(jobID: UUID) -> Bool {
        cancelWithReceipt(jobID: jobID) != nil
    }

    func cancelWithReceipt(jobID: UUID,
                           protocolAuthority: AppleDirectProtocolAuthority = .shared) -> IPhoneDirectCancellationReceipt? {
        let invocation = activeCancellation?.jobID == jobID ? activeCancellation : nil
        let expected = invocation?.ownership
        let configuration = invocation?.cancellationProtocolAuthority ?? protocolAuthority
        do {
            let directory = try jobDirectory(jobID)
            let support = try fileManager.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true)
            let transaction = try AtomicFileWriter.beginPublicationTransaction(
                at: support.appendingPathComponent("Health.md/DirectCLIOutbound/.v1.journal.lock"))
            defer { transaction.close() }
            try expected?.validateGeneration()
            // File jobs own a child namespace. Only that exact layout may bypass
            // raw recovery; any raw journal, ownership marker or spool still fails
            // closed through the raw loader. Keep inspection and cancellation in
            // one publication transaction so a cooperating writer cannot race it.
            let entries = try fileManager.contentsOfDirectory(atPath: directory.path)
            let fileOnly: Bool
            if entries == ["files"] {
                fileOnly = try fileManager.attributesOfItem(atPath:
                    directory.appendingPathComponent("files").path)[.type] as? FileAttributeType == .typeDirectory
            } else {
                fileOnly = false
            }
            let rawJournal = fileOnly ? nil : try loadJournal(jobID: jobID)
            var rawReceipt: IPhoneDirectCancellationReceipt?
            if var journal = rawJournal, journal.state != .completed,
               expected == nil || sameOwnership(expected, journal.checkpoint) {
                let cancellationAuthority = configuration.makeSessionAuthority()
                try cancellationAuthority.beginOperation(pin: journal.version >= IPhoneDirectExportJournal.currentVersion
                    ? journal.appleDirectProtocolPin : nil)
                let owner = journal.checkpoint
                try owner.commitCancellation(operation: {
                    journal.state = .cancelled
                    journal.updatedAt = Date()
                    try saveJournal(&journal)
                }, onCommitted: {})
                rawReceipt = IPhoneDirectCancellationReceipt(jobID: jobID, ownership: journal.checkpoint,
                    protocolAuthority: cancellationAuthority.frozenForCurrentOperation())
            }
            let fileReceipt = try IPhoneDirectFileExportProducer.shared.cancel(
                jobID: jobID, expectedOwnership: expected, protocolAuthority: configuration)
            let receipt = rawReceipt ?? fileReceipt
            let committed = receipt?.durableOwnership
            guard committed != nil || (invocation != nil && expected == nil) else { return nil }
            let signal = {
                invocation?.cancel()
                self.queryExecutionControllers.removeValue(forKey: jobID)
                CLIExportActivityTracker.shared.setMessage(
                    jobID: jobID, message: "Cancelling the direct CLI export…")
            }
            if let committed {
                try committed.withGenerationOwnership { signal() }
            } else {
                signal()
            }
            if committed != nil {
                return receipt
            }
            return invocation.map(IPhoneDirectCancellationReceipt.init(invocation:))
        } catch {
            return nil
        }
    }

    private func sameOwnership(_ left: AppleExportJournalCheckpoint?, _ right: AppleExportJournalCheckpoint) -> Bool {
        left?.generation == right.generation && left?.completionIdentity == right.completionIdentity
            && left?.journalURL == right.journalURL && left?.publicationLockURL == right.publicationLockURL
    }

    private func run(
        _ request: DirectExportRequest,
        peerBinding: DirectPeerBinding,
        negotiation: DirectTransferNegotiation,
        channel: IPhoneDirectExportConnection,
        protocolAuthority: AppleDirectProtocolAuthority,
        healthKitManager: HealthKitManager,
        didAcquireOwnership: (AppleExportJournalCheckpoint) throws -> HealthKitQueryExecutionController
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
        if IPhoneDirectCancellationScope.isCancelled(jobID: request.jobID) {
            throw IPhoneDirectExportError.cancelled
        }

        activeJobID = request.jobID
        let operationAuthority: AppleDirectProtocolAuthority
        let journal: IPhoneDirectExportJournal
        if let persisted = try loadJournal(jobID: request.jobID) {
            guard persisted.version == IPhoneDirectExportJournal.legacyProtocolVersion
                    || persisted.version == IPhoneDirectExportJournal.currentVersion,
                  persisted.request == request else {
                throw IPhoneDirectExportError.requestChanged
            }
            try protocolAuthority.beginOperation(
                pin: persisted.version >= IPhoneDirectExportJournal.currentVersion
                    ? persisted.appleDirectProtocolPin : nil
            )
            operationAuthority = protocolAuthority.frozenForCurrentOperation()
            IPhoneDirectCancellationScope.current?.bindProtocolAuthority(operationAuthority)
            guard persisted.session.requestFingerprint == (try operationAuthority.requestFingerprint(request)),
                  persisted.accepted.peerBinding == peerBinding,
                  persisted.session.partitionTargetBytes == negotiation.partitionTargetBytes else {
                throw IPhoneDirectExportError.requestChanged
            }
            guard persisted.state != .cancelled else { throw IPhoneDirectExportError.cancelled }
            journal = persisted
        } else {
            let protocolPin = try protocolAuthority.pinForNewOperation()
            try protocolAuthority.beginOperation(pin: protocolPin)
            operationAuthority = protocolAuthority.frozenForCurrentOperation()
            IPhoneDirectCancellationScope.current?.bindProtocolAuthority(operationAuthority)
            var prepared = try await prepareNewJournal(
                request,
                peerBinding: peerBinding,
                negotiation: negotiation,
                protocolPin: protocolPin,
                protocolAuthority: operationAuthority,
                healthKitManager: healthKitManager
            )
            try checkCancellation(jobID: request.jobID)
            _ = try Self.recoveredCaptureContext(
                settingsSnapshot: prepared.settingsSnapshot,
                sourceTimeZoneIdentifier: prepared.accepted.sourceTimeZoneIdentifier
            )
            try saveJournal(&prepared, freshAdmission: true)
            journal = prepared
        }

        let channel = channel.retainingProtocolAuthority(operationAuthority)
        let queryController = try didAcquireOwnership(journal.checkpoint)
        return try await HealthKitQueryExecutionController.withController(queryController) {

            // Already-spooled historical jobs may transfer their exact bytes without
            // acquiring new capture authority. Partial jobs must agree before acceptance.
            if journal.days.count < journal.accepted.resolvedDateIdentifiers.count {
                _ = try Self.recoveredCaptureContext(
                    settingsSnapshot: journal.settingsSnapshot,
                    sourceTimeZoneIdentifier: journal.accepted.sourceTimeZoneIdentifier
                )
            }
            try await sendMessage(.exportAccepted(journal.accepted), journal: journal, channel: channel)
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
                try saveJournal(&current)
            }
            current.state = .transferring
            current.updatedAt = Date()
            try saveJournal(&current)

            try await sendMessage(.transferSession(current.session), journal: current, channel: channel)
            for day in current.days {
                try await sendMessage(.rawDayManifest(day.manifest), journal: current, channel: channel)
            }
            try await transferPartitions(
                &current,
                channel: channel,
                protocolAuthority: operationAuthority
            )
            let finalize = try DirectTransferFinalize(
                sessionID: current.session.sessionID,
                jobID: request.jobID,
                requestFingerprint: current.session.requestFingerprint,
                totalPartitions: current.partitions.count,
                totalBytes: current.partitions.reduce(0) { $0 + $1.byteCount },
                finalPartitionSHA256: current.partitions.last?.sha256
            )
            try await sendMessage(.transferFinalize(finalize), journal: current, channel: channel)
            let finalResponse = try await receiveMessage(channel, jobID: request.jobID, checkpoint: current.checkpoint)
            guard case .transferFinalAcknowledgement(let acknowledgement) = finalResponse,
                  acknowledgement.accepted,
                  acknowledgement.sessionID == current.session.sessionID,
                  acknowledgement.jobID == request.jobID,
                  acknowledgement.totalPartitions == finalize.totalPartitions,
                  acknowledgement.totalBytes == finalize.totalBytes,
                  acknowledgement.finalPartitionSHA256 == finalize.finalPartitionSHA256 else {
                throw IPhoneDirectExportError.unexpectedResponse
            }

            let completionOwnership = current.checkpoint
            guard let completionIdentity = completionOwnership.completionIdentity else {
                throw IPhoneDirectExportError.requestChanged
            }
            do {
                try completionOwnership.withCheckpointOwnership {
                    current.state = .completed
                    current.updatedAt = Date()
                    let successCount = current.days.filter {
                        !["failed", "cancelled", "missing"].contains($0.manifest.status)
                    }.count
                    let shouldRecordCompletion = !current.completionRecorded
                    if shouldRecordCompletion {
                        if successCount > 0 {
                            try PurchaseManager.shared.recordExportUse(jobID: completionIdentity)
                        }
                        let dates = sourceDates(
                            current.accepted.resolvedDateIdentifiers,
                            timeZoneIdentifier: current.accepted.sourceTimeZoneIdentifier
                        )
                        let failedStatuses = Set(["failed", "cancelled", "missing"])
                        let failedDateDetails = current.days.compactMap { day -> FailedDateDetail? in
                            guard failedStatuses.contains(day.manifest.status),
                                  let date = sourceDates(
                                    [day.manifest.date],
                                    timeZoneIdentifier: current.accepted.sourceTimeZoneIdentifier
                                  ).first else { return nil }
                            let reason = day.manifest.failureCode
                                .flatMap(ExportFailureReason.init(rawValue:)) ?? .healthKitError
                            return FailedDateDetail(date: date, reason: reason)
                        }
                        // Day-level informational notes ride in the recorded result so
                        // Export History shows them as export notes while the status stays
                        // a full success (they never degrade it).
                        var recordedPartialFailures: [ExportPartialFailure] = []
                        for day in current.days {
                            for note in day.informationalFailures ?? [] where !recordedPartialFailures.contains(note) {
                                recordedPartialFailures.append(note)
                            }
                        }
                        let result = ExportOrchestrator.ExportResult(
                            successCount: successCount,
                            totalCount: current.days.count,
                            failedDateDetails: failedDateDetails,
                            partialFailures: recordedPartialFailures,
                            formatsPerDate: 0
                        )
                        ExportOrchestrator.recordResult(
                            result,
                            source: .macAgent,
                            dateRangeStart: dates.first ?? request.createdAt,
                            dateRangeEnd: dates.last ?? request.createdAt,
                            targetLabel: "Health.md CLI",
                            fileCount: 0,
                            idempotencyKey: completionIdentity,
                            operationDetails: historyOperationDetails(for: current)
                        )
                        current.completionRecorded = true
                    }
                    // Both side effects use the retained completion identity, so a crash before this journal
                    // save retries them without double charging or duplicating history.
                    try saveJournal(&current)
                }
            } catch let error as POSIXError where error.code == .EAGAIN {
                throw IPhoneDirectExportError.requestChanged
            }
            try await sendMessage(.completionConfirmed(jobID: request.jobID), journal: current, channel: channel)
            // Informational day notes (for example a WorkoutKit plan this device
            // cannot decode) surface as wire day statuses the CLI must keep seeing,
            // but they do not reduce the job below full success for the activity
            // summary the user reads on this device.
            return !current.days.contains {
                ["failed", "cancelled", "missing"].contains($0.manifest.status) ||
                    $0.resolvedHadDegradingWarnings
            }
        }
    }

    private func prepareNewJournal(
        _ request: DirectExportRequest,
        peerBinding: DirectPeerBinding,
        negotiation: DirectTransferNegotiation,
        protocolPin: AppleDirectProtocolPin?,
        protocolAuthority: AppleDirectProtocolAuthority,
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
        settings.executionSleepCaptureContext = try healthKitManager.resolveSleepCaptureContext(settings: settings)
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
            requestFingerprint: try protocolAuthority.requestFingerprint(request),
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
            appleDirectProtocolPin: protocolPin,
            days: [],
            partitions: [],
            committedPartitionCount: 0,
            committedBytes: 0,
            state: .preparing,
            completionRecorded: false,
            updatedAt: Date()
        )
    }

    /// Recover raw-capture authority independently of mutable preferences.
    static func recoveredCaptureContext(
        settingsSnapshot: ExportSettingsSnapshot,
        sourceTimeZoneIdentifier: String
    ) throws -> AppleSleepCaptureContext {
        let context = try settingsSnapshot.recoveredSleepCaptureContext()
        guard TimeZone(identifier: sourceTimeZoneIdentifier)?.identifier == context.calendarTimeZoneIdentifier else {
            throw AppleSleepCaptureContext.AvailabilityError.incompatibleDurableAuthority
        }
        return context
    }

    private func captureRemainingDays(
        _ supplied: IPhoneDirectExportJournal,
        channel: IPhoneDirectExportConnection,
        healthKitManager: HealthKitManager
    ) async throws -> IPhoneDirectExportJournal {
        var journal = supplied
        let settings = journal.settingsSnapshot.makeAdvancedExportSettings()
        let captureContext = try Self.recoveredCaptureContext(
            settingsSnapshot: journal.settingsSnapshot,
            sourceTimeZoneIdentifier: journal.accepted.sourceTimeZoneIdentifier
        )
        settings.exportTimeZoneOverride = captureContext.timeZone
        let dates = sourceDates(
            journal.accepted.resolvedDateIdentifiers,
            timeZoneIdentifier: journal.accepted.sourceTimeZoneIdentifier
        )
        guard dates.count == journal.accepted.resolvedDateIdentifiers.count else {
            throw IPhoneDirectExportError.invalidSpool
        }
        for index in journal.days.count..<dates.count {
            try checkCancellation(journal: journal)
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
                journal: journal,
                channel: channel
            )
            let detailPolicy = settings.effectiveDetailPolicy
            let expectsLosslessArchive = detailPolicy.includesCanonicalArchive
            let outcome = try await HealthKitDailyCapture.capture(
                date: date,
                detailPolicy: detailPolicy,
                metricSelection: settings.metricSelection,
                transform: .sanitizeGranularAndFilter,
                emptyRecordPolicy: .retain,
                fetchExternalRecords: false,
                failurePolicy: .connectedMac,
                fetchHealthData: { date, detailPolicy, metricSelection in
                    try await healthKitManager.fetchHealthData(
                        for: date,
                        detailPolicy: detailPolicy,
                        metricSelection: metricSelection,
                        timeZone: TimeZone(
                            identifier: journal.accepted.sourceTimeZoneIdentifier
                        ),
                        captureContext: captureContext
                    )
                },
                fetchExternalDailyRecords: nil
            )
            // Cancellation may arrive while HealthKit is awaiting its query.
            // Re-check before this task can overwrite the durable cancelled tombstone.
            try checkCancellation(journal: journal)
            let result: CanonicalRawDayResult
            // Informational omissions (a WorkoutKit plan this device cannot
            // decode) count toward the wire manifest's day-warning totals but
            // must not degrade history status, so the degrading split is
            // captured beside the manifest while the wire payload stays
            // unchanged.
            let capturedPartialFailures = outcome.record?.partialFailures ?? []
            let degradingFailureCount = capturedPartialFailures
                .filter(\.degradesSuccess)
                .count
            let informationalFailures = capturedPartialFailures
                .filter { $0.isInformational == true }
            let recordArchive = outcome.record?.healthKitRecordArchive
            let hasDegradingIncompleteQuery = recordArchive?.queryResults.contains {
                $0.status != .success && !$0.isInformationalWorkoutPlanOmission
            } ?? false
            let hadDegradingWarnings = degradingFailureCount > 0
                || !(recordArchive?.integrityWarnings.isEmpty ?? true)
                || hasDegradingIncompleteQuery
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
            let spool = try spool(
                result,
                jobID: journal.request.jobID,
                dayIndex: index,
                degradingFailureCount: degradingFailureCount,
                hadDegradingWarnings: hadDegradingWarnings,
                informationalFailures: informationalFailures.isEmpty ? nil : informationalFailures
            )
            journal.days.append(spool)
            journal.updatedAt = Date()
            try saveJournal(&journal)
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
                journal: journal,
                channel: channel
            )
        }
        return journal
    }

    private func spool(
        _ day: CanonicalRawDayResult,
        jobID: UUID,
        dayIndex: Int,
        degradingFailureCount: Int? = nil,
        hadDegradingWarnings: Bool? = nil,
        informationalFailures: [ExportPartialFailure]? = nil
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
        return IPhoneDirectRawDaySpool(
            manifest: manifest,
            relativePath: relativePath,
            degradingFailureCount: degradingFailureCount,
            hadDegradingWarnings: hadDegradingWarnings,
            informationalFailures: informationalFailures
        )
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
        channel: IPhoneDirectExportConnection,
        protocolAuthority: AppleDirectProtocolAuthority
    ) async throws {
        for descriptor in journal.partitions {
            try checkCancellation(journal: journal)
            let open = try DirectTransferOpen(session: journal.session, partition: descriptor)
            try await sendMessage(.transferOpen(open), journal: journal, channel: channel)
            let response = try await receiveMessage(channel, jobID: journal.request.jobID, checkpoint: journal.checkpoint)
            guard case .transferDisposition(let disposition) = response,
                  disposition.sessionID == journal.session.sessionID,
                  disposition.jobID == journal.request.jobID,
                  disposition.partitionIndex == descriptor.index,
                  disposition.partitionSHA256 == descriptor.sha256,
                  disposition.disposition != .rejected else {
                throw IPhoneDirectExportError.unexpectedResponse
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
                try await sendMessage(.transferPartitionComplete(complete), journal: journal, channel: channel)
                let completionResponse = try await receiveMessage(channel, jobID: journal.request.jobID, checkpoint: journal.checkpoint)
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
            try saveJournal(&journal)
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
                journal: journal,
                channel: channel
            )
        }
    }

    private func sendPartition(
        _ descriptor: DirectTransferPartition,
        journal: IPhoneDirectExportJournal,
        channel: IPhoneDirectExportConnection,
        protocolAuthority: AppleDirectProtocolAuthority
    ) async throws {
        guard let segment = descriptor.itemSegment,
              let day = journal.days.first(where: { $0.manifest.date == segment.itemID }),
              let relativePath = day.relativePath else {
            throw IPhoneDirectExportError.invalidSpool
        }
        try checkCancellation(journal: journal)
        let url = try jobDirectory(journal.request.jobID).appendingPathComponent(relativePath)
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        try handle.seek(toOffset: UInt64(segment.offset))
        var remaining = descriptor.byteCount
        var sequence = 1
        while remaining > 0 {
            try checkCancellation(journal: journal)
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
            try await sendWhileOwned(jobID: journal.request.jobID, checkpoint: journal.checkpoint) {
                try await channel.sendBinaryTransferFrame(
                    try protocolAuthority.encodeTransferChunk(chunk), ownership: journal.checkpoint
                )
            }
            let response = try await receiveMessage(channel, jobID: journal.request.jobID, checkpoint: journal.checkpoint)
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

    private func sendMessage(
        _ message: DirectMessage,
        journal: IPhoneDirectExportJournal,
        channel: IPhoneDirectExportConnection
    ) async throws {
        try await sendWhileOwned(jobID: journal.request.jobID, checkpoint: journal.checkpoint) {
            try await channel.send(message, ownership: journal.checkpoint)
        }
    }

    private func sendWhileOwned(
        jobID: UUID,
        checkpoint: AppleExportJournalCheckpoint,
        operation: @MainActor () async throws -> Void
    ) async throws {
        do {
            try await checkpoint.continueWhileOwned {
                try checkCancellation(jobID: jobID)
                try await operation()
                try checkCancellation(jobID: jobID)
            }
        } catch AppleExportJournalCheckpoint.ContinuationError.superseded {
            throw IPhoneDirectExportError.requestChanged
        }
    }

    private func sendProgress(
        _ progress: DirectExportProgress,
        phase: CLIExportActivityTracker.Phase,
        journal: IPhoneDirectExportJournal,
        channel: IPhoneDirectExportConnection
    ) async throws {
        guard progress.jobID == journal.request.jobID else {
            throw IPhoneDirectExportError.requestChanged
        }
        do {
            try journal.checkpoint.withGenerationOwnership {
                try checkCancellation(jobID: progress.jobID)
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
            }
        } catch let error as POSIXError where error.code == .EAGAIN {
            throw IPhoneDirectExportError.requestChanged
        }
        try await sendMessage(.exportProgress(progress), journal: journal, channel: channel)
    }

    private func receiveMessage(
        _ channel: IPhoneDirectExportConnection,
        jobID: UUID,
        checkpoint: AppleExportJournalCheckpoint
    ) async throws -> DirectMessage {
        let message: DirectMessage
        do {
            message = try await checkpoint.continueWhileOwned {
                try checkCancellation(jobID: jobID)
                let response = try await channel.receive()
                try checkCancellation(jobID: jobID)
                return response
            }
        } catch AppleExportJournalCheckpoint.ContinuationError.superseded {
            throw IPhoneDirectExportError.requestChanged
        }
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
        let catalog = HealthMetrics.availableInCurrentBuild
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

    private func historyOperationDetails(
        for journal: IPhoneDirectExportJournal
    ) -> ExportHistoryOperationDetails {
        let manifests = journal.days.map(\.manifest)
        let selection = journal.accepted.resolvedCanonicalSelection
        let kind: ExportHistoryOperationDetails.Kind = journal.request.rawProfile == .healthDataProjection
            ? .canonicalExtraction
            : .rawExport
        let dateSelection: String
        switch journal.request.dateSelection {
        case .exact: dateSelection = "exact_range"
        case .allAvailable: dateSelection = "all_available"
        }
        let failedStatuses = Set(["failed", "cancelled", "missing"])

        return ExportHistoryOperationDetails(
            kind: kind,
            requestID: journal.request.jobID,
            dateSelection: dateSelection,
            settingsPolicy: journal.request.settingsPolicy.rawValue,
            profile: journal.request.rawProfile?.rawValue,
            detailLevel: selection?.detailLevel.rawValue ??
                (journal.request.rawProfile == .canonicalSourceRecordsV1 ? "lossless" : nil),
            metricIDs: Array(journal.settingsSnapshot.metricSelection.enabledMetricIDs),
            categoryIDs: Array(journal.settingsSnapshot.metricSelection.enabledCategoryIDs),
            sourceIDs: selection?.sourceIDs ?? ["apple_health"],
            objectPaths: selection?.objectPaths ?? [],
            fieldPointers: selection?.fieldPointers ?? [],
            partitionCount: journal.partitions.count,
            transferredBytes: journal.partitions.reduce(0) { $0 + $1.byteCount },
            sampleCount: manifests.reduce(0) { $0 + $1.sampleCount },
            recordCount: manifests.reduce(0) { $0 + $1.recordCount },
            warningDayCount: journal.days.filter(\.resolvedHadDegradingWarnings).count,
            failedDayCount: manifests.filter { failedStatuses.contains($0.status) }.count,
            integrityWarningCount: manifests.reduce(0) { $0 + $1.integrityWarningCount },
            partialFailureCount: journal.days.reduce(0) {
                $0 + $1.resolvedDegradingFailureCount
            }
        )
    }

    private func validateGeneration(_ checkpoint: AppleExportJournalCheckpoint) throws {
        do { try checkpoint.validateGeneration(fileManager: fileManager) }
        catch { throw IPhoneDirectExportError.requestChanged }
    }

    private func checkCancellation(journal: IPhoneDirectExportJournal) throws {
        try validateGeneration(journal.checkpoint)
        try checkCancellation(jobID: journal.request.jobID)
    }

    private func checkCancellation(jobID: UUID) throws {
        if Task.isCancelled || IPhoneDirectCancellationScope.isCancelled(jobID: jobID) {
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
              let support = try? fileManager.url(for: .applicationSupportDirectory,
                in: .userDomainMask, appropriateFor: nil, create: true) else { return }
        _ = try? AppleExportJournalRecovery.cleanupExpiredDirectJobs(at: root,
            lockURL: root.deletingLastPathComponent().appendingPathComponent(".v1.journal.lock"),
            durabilityRoot: support, now: now, lifetime: HealthMdDirectProtocol.jobLifetime,
            fileManager: fileManager)
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

    private func saveJournal(_ journal: inout IPhoneDirectExportJournal, freshAdmission: Bool = false) throws {
        let encoder = JSONEncoder()
        encoder.userInfo[ExportSettingsSnapshot.durableSleepContextEncoding] = true
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        let destination = try jobDirectory(journal.request.jobID).appendingPathComponent("journal.json")
        let support = try fileManager.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        let data = try encoder.encode(journal)
        do {
            try journal.checkpoint.publish(data, to: destination,
                freshAdmission: freshAdmission,
                lockURL: support.appendingPathComponent("Health.md/DirectCLIOutbound/.v1.journal.lock"),
                durabilityRoot: support, fileManager: fileManager,
                attributes: [.posixPermissions: 0o600,
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication])
        } catch let error as POSIXError where error.code == .EAGAIN || (freshAdmission && error.code == .EEXIST) {
            throw IPhoneDirectExportError.requestChanged
        }
    }

    private func loadJournal(jobID: UUID) throws -> IPhoneDirectExportJournal? {
        let support = try fileManager.url(for: .applicationSupportDirectory,
            in: .userDomainMask, appropriateFor: nil, create: true)
        let saved: (journal: IPhoneDirectExportJournal, checkpoint: AppleExportJournalCheckpoint)? =
            try AppleExportJournalRecovery.loadOwned(
                at: try jobDirectory(jobID).appendingPathComponent("journal.json"),
                lockURL: support.appendingPathComponent("Health.md/DirectCLIOutbound/.v1.journal.lock"),
                durabilityRoot: support, fileManager: fileManager,
                attributes: [.posixPermissions: 0o600,
                    .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
                legacyCompletionIdentity: { $0.request.jobID },
                isSupported: { journal in journal.request.jobID == jobID && (journal.version == IPhoneDirectExportJournal.legacyProtocolVersion || journal.version == IPhoneDirectExportJournal.currentVersion) })
        guard var saved else { return nil }
        saved.journal.checkpoint = saved.checkpoint
        return saved.journal
    }

    private func protectedAtomicWrite(_ data: Data, to destination: URL) throws {
        try AtomicFileWriter.writeData(data, to: destination, fileManager: fileManager,
            attributes: [.posixPermissions: 0o600,
                .protectionKey: FileProtectionType.completeUntilFirstUserAuthentication],
            commitPolicy: .replaceExisting,
            directoryDurability: .required(upTo: try fileManager.url(
                for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true)))
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
