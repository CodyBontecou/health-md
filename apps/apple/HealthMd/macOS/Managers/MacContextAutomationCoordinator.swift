#if os(macOS)
import Combine
import Foundation
import Security

/// Admission is synchronous; acquisition runs in a separate task so incoming
/// acceptance/chunk/finalize responses remain routable on the MainActor.
@MainActor
final class MacContextAutomationCoordinator: ObservableObject {
    let journal: AppleContextJournal
    private var tasks: [UUID: Task<Void, Never>] = [:]
    private var transferJobs: [UUID: UUID] = [:]
    private let contextReadiness: () -> AppleContextReceipt.State?

    func allowsMessage(_ message: SyncMessage, sync: SyncService, inbound: Bool = true) -> Bool {
        let jobID: UUID?
        switch message {
        case .connectedTransferStart(let start):
            jobID = start.manifest.jobID
            if journal.isKnown(start.manifest.jobID) {
                guard allows(jobID: start.manifest.jobID, sync: sync) else { return false }
                transferJobs[start.transferID] = start.manifest.jobID
            }
        case .connectedTransferChunk(let chunk): jobID = transferJobs[chunk.transferID]
        case .connectedTransferComplete(let complete): jobID = transferJobs[complete.transferID]
        case .connectedTransferAbort(let abort): jobID = abort.jobID ?? transferJobs[abort.transferID]
        case .iphoneExportRequest(let value): jobID = value.jobID
        case .iphoneExportAccepted(let value): jobID = value.jobID
        case .iphoneExportPreparationProgress(let value): jobID = value.jobID
        case .iphoneExportRejected(let value): jobID = value.jobID
        case .iphoneExportRawData(let value): jobID = value.jobID
        case .macExportRequest(let value): jobID = value.jobID
        case .macExportStreamStart(let value): jobID = value.jobID
        case .macExportResult(let value): jobID = value.jobID
        case .macExportFailed(let value): jobID = value.jobID
        case .connectedCorpusTransferOpen(let value):
            jobID = value.session.jobID
            if let record = journal.record(value.session.jobID) {
                guard let manifest = value.exportManifest, record.request.matches(manifest),
                      value.session.peerBinding == ConnectedCorpusPeerBinding(
                        sourceInstallationID: record.request.phoneInstallationID,
                        destinationInstallationID: record.request.macInstallationID) else { return false }
            }
        case .connectedCorpusTransferFinalize(let value): jobID = value.jobID
        case .connectedCorpusStatus(let value): jobID = value.jobID
        case .connectedCorpusTransferCancel(let value): jobID = value.jobID
        default: jobID = nil
        }
        guard let jobID, journal.isKnown(jobID) else { return true }
        // Context jobs can NEVER be completed by ordinary export/raw messages.
        switch message {
        case .iphoneExportRawData, .macExportRequest, .macExportStreamStart,
             .macExportResult, .macExportFailed: return !inbound && allows(jobID: jobID, sync: sync)
        default: return allows(jobID: jobID, sync: sync)
        }
    }

    init(journal: AppleContextJournal? = nil, contextReadiness: (() -> AppleContextReceipt.State?)? = nil) {
        self.journal = journal ?? AppleContextJournal(root: AppleContextJournal.productionRoot("MacContextRequests"))
        self.contextReadiness = contextReadiness ?? {
            do {
                _ = try KeychainHealthContextEncryptionKeyProvider().existingOrCreateKeyData()
                return nil
            } catch HealthContextEncryptionKeyProviderError.keychainReadFailed(let status) {
                return status == errSecInteractionNotAllowed ? .locked : .unavailable
            } catch HealthContextEncryptionKeyProviderError.keychainWriteFailed(let status) {
                return status == errSecInteractionNotAllowed ? .locked : .unavailable
            } catch { return .unavailable }
        }
    }

    func allows(jobID: UUID, sync: SyncService) -> Bool {
        guard journal.isKnown(jobID) else { return true }
        guard let record = journal.record(jobID), !journal.hasUncertainAuthority(jobID) else { return false }
        return sync.canUsePhoneContextAutomation
            && sync.authenticatedContextPeerID == record.request.phoneInstallationID
            && sync.installationID == record.request.macInstallationID
    }

    func handle(_ message: AppleContextMessage, sync: SyncService,
                jobs: MacIPhoneExportRequestCoordinator, destination: MacDestinationStatus) {
        let request: AppleContextRequest
        switch message {
        case .refresh(let value), .status(let value): request = value
        case .receipt: return // a phone can never assert context completion
        }
        guard sync.canUsePhoneContextAutomation,
              sync.authenticatedContextPeerID == request.phoneInstallationID,
              sync.installationID == request.macInstallationID, request.isValid else { return }
        if let existing = jobs.contextRequest(jobID: request.id), !request.matches(existing) { return }
        let repaired: Bool
        do {
            if case .status = message {
                repaired = try journal.retryDurability(request.id, expectedRequest: request)
            } else { repaired = false }
            try journal.admit(request)
        } catch { return } // no ack/acquisition without proven durable mapping
        let response = jobs.jobResponse(jobID: request.id)
        if response.failureReason != "job_not_found" {
            publish(request, response: response, sync: sync)
            if repaired && response.durableState == "sent" {
                // A receipt/mark-admitted failure can suppress the first native
                // dispatch. Release ONLY this automation waiter, then resume the
                // same persisted job; never create a replacement or block ingress.
                let previous = tasks[request.id]
                jobs.cancelRequestForDisconnectedClient(jobID: request.id)
                Task { @MainActor [weak self] in
                    await previous?.value
                    guard let self, self.tasks[request.id] == nil,
                          self.allows(jobID: request.id, sync: sync) else { return }
                    self.tasks[request.id] = Task { @MainActor in
                        defer { self.tasks.removeValue(forKey: request.id) }
                        let resumed = await jobs.resumeExport(jobID: request.id, waitTimeoutSeconds: 30,
                            syncService: sync, destinationStatus: destination)
                        self.publish(request, response: resumed, sync: sync)
                    }
                }
            }
            return
        }
        if journal.record(request.id)?.jobWasAdmitted == true {
            // Expired/missing native jobs are not silently recreated as new work.
            publishState(request, state: .unavailable, sync: sync)
            return
        }
        if let state = contextReadiness() {
            publishState(request, state: state, sync: sync)
            return
        }
        guard tasks[request.id] == nil else { return }
        tasks[request.id] = Task { @MainActor [weak self] in
            guard let self else { return }
            defer { self.tasks.removeValue(forKey: request.id) }
            guard self.allows(jobID: request.id, sync: sync) else { return }
            let response = await jobs.requestExport(.init(
                jobID: request.id, startDate: request.startDate, endDate: request.endDate,
                requestedDateIdentifiers: request.ownerDates, requestedBy: .cli,
                settingsPolicy: .requestedDatesOnly, responseMode: .contextStore,
                rawProfile: nil, canonicalSelection: request.selection, waitTimeoutSeconds: 30
            ), syncService: sync, destinationStatus: destination, onDurableAdmission: {
                // The context job has ALSO been persisted; only now acknowledge.
                self.publish(request, response: jobs.jobResponse(jobID: request.id), sync: sync)
            })
            self.publish(request, response: response, sync: sync)
        }
    }

    private func publish(_ request: AppleContextRequest,
                         response: MacIPhoneExportRequestCoordinator.ExportResponse, sync: SyncService) {
        guard allows(jobID: request.id, sync: sync) else { return }
        let state: AppleContextReceipt.State
        switch response.status {
        case .success: state = .completed
        case .partialSuccess: state = .partial
        case .failure, .cancelled:
            state = .failed
        case .unavailable:
            // Busy is a durable request-level availability response, not a job
            // acceptance. A native persistence failure still emits NO ack/send.
            if response.failureReason == "export_in_progress" {
                publishState(request, state: .unavailable, sync: sync)
                return
            }
            guard response.durable == true else { return }
            state = .unavailable
        case .accepted, .preparing, .timedOut: state = .pending
        }
        guard response.durable == true else { return }
        do { try journal.markJobAdmitted(request.id) } catch { return }
        publishState(request, state: state, sync: sync)
    }

    private func publishState(_ request: AppleContextRequest, state: AppleContextReceipt.State, sync: SyncService) {
        guard allows(jobID: request.id, sync: sync) else { return }
        let previous = journal.record(request.id)?.receipt
        if let previous, previous.state.isTerminal {
            sync.send(.appleContext(.receipt(previous)))
            return
        }
        let receipt = AppleContextReceipt(request: request, revision: (previous?.revision ?? 0) + 1, state: state)
        do {
            guard let peer = sync.authenticatedContextPeerID,
                  try journal.accept(receipt, authenticatedPeer: peer, localID: sync.installationID, onPhone: false) else { return }
            sync.send(.appleContext(.receipt(receipt)))
        } catch { /* status recovery retries against the durable context job */ }
    }
}
#endif
