import Foundation
import HealthMdConnectionCore

public struct DirectPairedDevice: Codable, Equatable, Sendable {
    public let installationID: UUID
    public let displayName: String
    public let pairedAt: Date
    public let lastConnectedAt: Date

    public init(_ client: ManualIPTrustedClient) {
        installationID = client.installationID
        displayName = client.displayName
        pairedAt = client.pairedAt
        lastConnectedAt = client.lastConnectedAt
    }
}

public struct DirectPairingResult: Equatable, Sendable {
    public let device: DirectPairedDevice
    public let endpoint: DirectServerEndpoint

    public init(device: DirectPairedDevice, endpoint: DirectServerEndpoint) {
        self.device = device
        self.endpoint = endpoint
    }
}

public struct DirectExportResult: Equatable, Sendable {
    public let artifact: DirectRawReceiveArtifact
    public let endpoint: DirectServerEndpoint

    public init(artifact: DirectRawReceiveArtifact, endpoint: DirectServerEndpoint) {
        self.artifact = artifact
        self.endpoint = endpoint
    }
}

public struct DirectFileExportResult: Equatable, Sendable {
    public let receipt: DirectFileExportReceipt
    public let endpoint: DirectServerEndpoint

    public init(receipt: DirectFileExportReceipt, endpoint: DirectServerEndpoint) {
        self.receipt = receipt
        self.endpoint = endpoint
    }
}

public struct DirectStatusResult: Equatable, Sendable {
    public let status: DirectIPhoneStatus
    public let peerCapabilities: DirectPeerCapabilities
    public let endpoint: DirectServerEndpoint

    public init(
        status: DirectIPhoneStatus,
        peerCapabilities: DirectPeerCapabilities,
        endpoint: DirectServerEndpoint
    ) {
        self.status = status
        self.peerCapabilities = peerCapabilities
        self.endpoint = endpoint
    }
}

public enum DirectClientControllerError: LocalizedError, Equatable {
    case deviceSelectionRequired([UUID])
    case deviceNotPaired(UUID)
    case unexpectedDevice(UUID)
    case exportRejected(DirectExportFailure)
    case unexpectedExportMessage
    case exportInterrupted(UUID)
    case cancellationPending(UUID)
    case jobNotResumable(UUID, DirectJobState)
    case invalidRawResponse(String)

    public var errorDescription: String? {
        switch self {
        case .deviceSelectionRequired:
            return "More than one iPhone is paired. Pass --device with an installation ID from `healthmd direct devices`."
        case .deviceNotPaired(let identifier):
            return "The requested direct iPhone is not paired: \(identifier.uuidString.lowercased())."
        case .unexpectedDevice(let identifier):
            return "A different paired iPhone connected: \(identifier.uuidString.lowercased())."
        case .exportRejected(let failure): return failure.message
        case .unexpectedExportMessage: return "The iPhone sent an unexpected direct export message."
        case .exportInterrupted(let jobID):
            return "Direct export \(jobID.uuidString.lowercased()) paused before completion. Run `healthmd --backend direct resume \(jobID.uuidString.lowercased())`."
        case .cancellationPending(let jobID):
            return "Cancellation for direct export \(jobID.uuidString.lowercased()) is pending. Keep Health.md open on the paired iPhone and run cancel again."
        case .jobNotResumable(let jobID, let state):
            return "Direct export \(jobID.uuidString.lowercased()) cannot resume from state \(state.rawValue)."
        case .invalidRawResponse(let message):
            return "The direct raw response failed validation: \(message)"
        }
    }
}

public final class DirectClientController: @unchecked Sendable {
    public let identity: DirectClientIdentity
    public let layout: DirectClientStorageLayout
    private let trustStore: any ManualIPTrustStoring

    public init(
        rootURL: URL? = nil,
        trustStore: (any ManualIPTrustStoring)? = nil
    ) throws {
        let layout = try DirectClientStorageLayout(rootURL: rootURL)
        self.layout = layout
        self.identity = try DirectClientIdentityStore(layout: layout).loadOrCreate()
        self.trustStore = trustStore ?? DirectClientTrustStore.make()
    }

    public func pairedDevices() -> [DirectPairedDevice] {
        trustStore.loadState(ownerInstallationID: identity.installationID)
            .trustedClients
            .map(DirectPairedDevice.init)
            .sorted { $0.displayName.localizedCaseInsensitiveCompare($1.displayName) == .orderedAscending }
    }

    public func unpair(deviceID: UUID) throws {
        var state = trustStore.loadState(ownerInstallationID: identity.installationID)
        state.trustedClients.removeAll { $0.installationID == deviceID }
        try trustStore.saveState(state)
    }

    public func pair(
        code: String,
        transport: DirectTransportKind = .manualIP,
        port: UInt16 = HealthMdDirectProtocol.defaultManualIPPort,
        timeout: TimeInterval = 120
    ) async throws -> DirectPairingResult {
        let normalizedCode = ManualIPSyncSecurity.normalizedPairingCode(code)
        guard normalizedCode.count == 6 else {
            throw DirectChannelError.authenticationFailed("The direct pairing code must contain six digits.")
        }
        let server = makeServer(transport: transport, port: port)
        let endpoint = try await server.start()
        defer { server.stop() }
        let channel = try await server.acceptAuthenticatedClient(
            pairingCode: normalizedCode,
            pairingCodeExpiresAt: Date().addingTimeInterval(
                min(timeout, DirectPairingSecurity.pairingCodeLifetime)
            ),
            timeout: timeout
        )
        defer { channel.cancel() }
        try await channel.send(.hello(localCapabilities))
        let peerHello = try await receiveMessage(on: channel, timeout: min(10, timeout))
        guard case .hello(let capabilities) = peerHello,
              capabilities.platform == .iOS,
              capabilities.installationID == channel.peerInstallationID,
              localCapabilities.negotiatedProtocolVersion(with: capabilities) != nil else {
            throw DirectChannelError.authenticationFailed("The paired peer is not a compatible Health.md iPhone app.")
        }
        guard let client = server.trustedClients().first(where: {
            $0.installationID == channel.peerInstallationID
        }) else {
            throw DirectChannelError.authenticationFailed("The paired iPhone credential was not persisted.")
        }
        return DirectPairingResult(device: DirectPairedDevice(client), endpoint: endpoint)
    }

    public func status(
        deviceID: UUID? = nil,
        transport: DirectTransportKind = .manualIP,
        port: UInt16 = HealthMdDirectProtocol.defaultManualIPPort,
        timeout: TimeInterval = 20
    ) async throws -> DirectStatusResult {
        let devices = pairedDevices()
        let selectedID: UUID
        if let deviceID {
            guard devices.contains(where: { $0.installationID == deviceID }) else {
                throw DirectClientControllerError.deviceNotPaired(deviceID)
            }
            selectedID = deviceID
        } else if devices.count == 1, let only = devices.first {
            selectedID = only.installationID
        } else {
            throw DirectClientControllerError.deviceSelectionRequired(
                devices.map(\.installationID)
            )
        }

        let server = makeServer(transport: transport, port: port)
        let endpoint = try await server.start()
        defer { server.stop() }
        let deadline = Date().addingTimeInterval(timeout)
        while deadline > Date() {
            let remaining = deadline.timeIntervalSinceNow
            let channel = try await server.acceptAuthenticatedClient(
                timeout: remaining,
                maximumAttempts: 1
            )
            if channel.peerInstallationID != selectedID {
                channel.cancel()
                continue
            }
            defer { channel.cancel() }
            try await channel.send(.hello(localCapabilities))
            let hello = try await receiveMessage(on: channel, timeout: min(10, remaining))
            guard case .hello(let capabilities) = hello,
                  capabilities.platform == .iOS,
                  capabilities.installationID == channel.peerInstallationID,
                  localCapabilities.negotiatedProtocolVersion(with: capabilities) != nil else {
                throw DirectChannelError.authenticationFailed("The connected peer is not a compatible paired iPhone.")
            }
            try await channel.send(.statusRequest(DirectStatusRequest()))
            let response = try await receiveMessage(on: channel, timeout: min(10, remaining))
            guard case .statusResponse(let status) = response else {
                throw DirectChannelError.decodeFailed
            }
            return DirectStatusResult(
                status: status,
                peerCapabilities: capabilities,
                endpoint: endpoint
            )
        }
        throw DirectChannelError.timedOut
    }

    public func export(
        _ request: DirectExportRequest,
        deviceID: UUID? = nil,
        transport: DirectTransportKind = .manualIP,
        port: UInt16 = HealthMdDirectProtocol.defaultManualIPPort,
        timeout: TimeInterval = 300,
        validateArtifact: (@Sendable (DirectRawReceiveArtifact) throws -> Void)? = nil
    ) async throws -> DirectExportResult {
        guard request.responseMode == .rawJSON, request.rawProfile != nil else {
            throw DirectClientControllerError.unexpectedExportMessage
        }
        guard request.createdAt.addingTimeInterval(HealthMdDirectProtocol.jobLifetime) > Date() else {
            throw DirectClientStorageError.jobExpired
        }
        let selectedID = try selectedDeviceID(deviceID)
        let store = try DirectJobStore(layout: layout)
        try await store.removeExpired()
        do {
            let existing = try await store.load(jobID: request.jobID)
            guard existing.request == request else {
                throw DirectRawReceiverError.requestChanged
            }
            if existing.state == .completed {
                let receiver = DirectRawReceiver(layout: layout, jobStore: store)
                return DirectExportResult(
                    artifact: try await receiver.artifact(jobID: request.jobID),
                    endpoint: DirectServerEndpoint(
                        transport: transport,
                        port: transport == .manualIP ? port : nil,
                        serviceType: transport == .nearby ? HealthMdDirectProtocol.serviceType : nil
                    )
                )
            }
        } catch DirectClientStorageError.jobNotFound {
            let record = try DirectJobRecord(request: request, createdAt: request.createdAt)
            try await store.save(record)
        }

        var record = try await store.load(jobID: request.jobID)
        guard record.state != .cancelled,
              record.state != .cancellationPending,
              record.state != .failed,
              !(await store.cancellationRequested(jobID: request.jobID)) else {
            throw DirectClientControllerError.jobNotResumable(request.jobID, record.state)
        }
        let intendedBinding = DirectPeerBinding(
            sourceInstallationID: selectedID,
            destinationInstallationID: identity.installationID
        )
        if let persistedBinding = record.peerBinding {
            guard persistedBinding == intendedBinding else {
                throw DirectClientControllerError.unexpectedDevice(selectedID)
            }
        } else {
            record.peerBinding = intendedBinding
        }
        record.state = .connecting
        record.updatedAt = Date()
        record.message = "Waiting for the paired iPhone to connect."
        try await store.save(record)

        let server = makeServer(transport: transport, port: port)
        let endpoint = try await server.start()
        defer { server.stop() }
        let receiver = DirectRawReceiver(layout: layout, jobStore: store)
        let deadline = Date().addingTimeInterval(timeout)
        do {
            while deadline > Date() {
                let remaining = max(0.1, deadline.timeIntervalSinceNow)
                let channel = try await server.acceptAuthenticatedClient(
                    timeout: remaining,
                    maximumAttempts: 1
                )
                if channel.peerInstallationID != selectedID {
                    channel.cancel()
                    continue
                }
                defer { channel.cancel() }
                let cancellationMonitor = cancellationMonitor(
                    jobID: request.jobID,
                    store: store,
                    channel: channel
                )
                defer { cancellationMonitor.cancel() }
                try await channel.send(.hello(localCapabilities))
                let helloPayload = try await receivePayload(on: channel, timeout: min(10, remaining))
                guard case .message(.hello(let peerCapabilities)) = helloPayload,
                      peerCapabilities.platform == .iOS,
                      peerCapabilities.installationID == channel.peerInstallationID,
                      localCapabilities.negotiatedProtocolVersion(with: peerCapabilities) != nil,
                      let negotiation = localCapabilities.transfer.negotiated(with: peerCapabilities.transfer) else {
                    throw DirectChannelError.authenticationFailed(
                        "The connected peer cannot negotiate direct corpus transfer."
                    )
                }
                try await channel.send(.exportRequest(request))
                var accepted: DirectExportAccepted?
                while deadline > Date() {
                    let payload = try await receivePayload(
                        on: channel,
                        timeout: max(0.1, deadline.timeIntervalSinceNow)
                    )
                    switch payload {
                    case .binaryTransferFrame(let frame):
                        let (_, chunk) = try DirectTransferBinaryFrame.decode(frame)
                        let acknowledgement = try await receiver.receive(chunk)
                        try await channel.send(.transferChunkAcknowledgement(acknowledgement))
                    case .message(let message):
                        switch message {
                        case .exportAccepted(let value):
                            guard value.jobID == request.jobID,
                                  value.peerBinding == DirectPeerBinding(
                                    sourceInstallationID: peerCapabilities.installationID,
                                    destinationInstallationID: identity.installationID
                                  ),
                                  acceptedDatesMatchRequest(value, request: request),
                                  !value.resolvedDateIdentifiers.isEmpty else {
                                throw DirectClientControllerError.unexpectedExportMessage
                            }
                            accepted = value
                            var acceptedRecord = try await store.load(jobID: request.jobID)
                            acceptedRecord.state = .accepted
                            acceptedRecord.updatedAt = Date()
                            acceptedRecord.peerBinding = value.peerBinding
                            acceptedRecord.totalDays = value.resolvedDateIdentifiers.count
                            acceptedRecord.message = "iPhone accepted the direct export."
                            try await store.save(acceptedRecord)
                        case .transferSession(let session):
                            guard let accepted,
                                  session.partitionTargetBytes == negotiation.partitionTargetBytes else {
                                throw DirectClientControllerError.unexpectedExportMessage
                            }
                            try await receiver.prepare(
                                request: request,
                                accepted: accepted,
                                session: session
                            )
                        case .rawDayManifest(let manifest):
                            try await receiver.store(manifest: manifest)
                        case .fileManifest:
                            throw DirectClientControllerError.unexpectedExportMessage
                        case .exportProgress(let progress):
                            guard progress.jobID == request.jobID else {
                                throw DirectClientControllerError.unexpectedExportMessage
                            }
                            var progressRecord = try await store.load(jobID: request.jobID)
                            progressRecord.state = progress.committedPartitions > 0 ? .transferring : .preparing
                            progressRecord.updatedAt = Date()
                            progressRecord.processedDays = progress.processedDays
                            progressRecord.totalDays = progress.totalDays
                            progressRecord.committedPartitions = progress.committedPartitions
                            progressRecord.committedBytes = progress.committedBytes
                            progressRecord.message = progress.message
                            try await store.save(progressRecord)
                        case .transferOpen(let open):
                            let disposition = try await receiver.disposition(for: open)
                            try await channel.send(.transferDisposition(disposition))
                        case .transferPartitionComplete(let complete):
                            let acknowledgement = try await receiver.commit(complete)
                            try await channel.send(.transferPartitionAcknowledgement(acknowledgement))
                        case .transferFinalize(let finalize):
                            let artifact = try await receiver.finalize(finalize)
                            do {
                                try validateArtifact?(artifact)
                            } catch {
                                try? await channel.send(.transferFinalAcknowledgement(
                                    try DirectTransferFinalAcknowledgement(
                                        sessionID: finalize.sessionID,
                                        jobID: finalize.jobID,
                                        accepted: false,
                                        totalPartitions: finalize.totalPartitions,
                                        totalBytes: finalize.totalBytes,
                                        finalPartitionSHA256: finalize.finalPartitionSHA256,
                                        message: "CLI rejected the assembled raw response before acknowledgement."
                                    )
                                ))
                                var failed = try await store.load(jobID: request.jobID)
                                failed.state = .failed
                                failed.updatedAt = Date()
                                failed.failure = DirectExportFailure(
                                    jobID: request.jobID,
                                    reason: .invalidRequest,
                                    message: error.localizedDescription
                                )
                                failed.message = error.localizedDescription
                                try await store.save(failed)
                                throw DirectClientControllerError.invalidRawResponse(
                                    error.localizedDescription
                                )
                            }
                            let acknowledgement = try DirectTransferFinalAcknowledgement(
                                sessionID: finalize.sessionID,
                                jobID: finalize.jobID,
                                accepted: true,
                                totalPartitions: finalize.totalPartitions,
                                totalBytes: finalize.totalBytes,
                                finalPartitionSHA256: finalize.finalPartitionSHA256,
                                responseByteCount: artifact.byteCount,
                                responseSHA256: artifact.sha256,
                                message: "CLI durably validated and assembled the strict raw response."
                            )
                            try await channel.send(.transferFinalAcknowledgement(acknowledgement))
                            guard case .message(.completionConfirmed(let confirmedID)) = try await receivePayload(
                                on: channel,
                                timeout: max(0.1, deadline.timeIntervalSinceNow)
                            ), confirmedID == request.jobID else {
                                throw DirectChannelError.connectionClosed
                            }
                            try await receiver.acknowledgePeerCompletion(jobID: request.jobID)
                            return DirectExportResult(artifact: artifact, endpoint: endpoint)
                        case .exportRejected(let failure):
                            var failed = try await store.load(jobID: request.jobID)
                            failed.state = failure.reason == .cancelled ? .cancelled : .failed
                            failed.updatedAt = Date()
                            failed.failure = failure
                            failed.message = failure.message
                            try await store.save(failed)
                            throw DirectClientControllerError.exportRejected(failure)
                        case .ping:
                            try await channel.send(.pong)
                        case .cancelAcknowledged(let jobID) where jobID == request.jobID:
                            try await receiver.cancel(jobID: jobID)
                            await store.clearCancellationRequest(jobID: jobID)
                            throw DirectRawReceiverError.cancelled
                        case .hello, .statusRequest, .statusResponse, .exportRequest,
                             .transferDisposition, .transferChunk,
                             .transferChunkAcknowledgement,
                             .transferPartitionAcknowledgement,
                             .transferFinalAcknowledgement, .completionConfirmed,
                             .cancel, .pong, .cancelAcknowledged:
                            break
                        }
                    }
                }
                throw DirectChannelError.timedOut
            }
            throw DirectChannelError.timedOut
        } catch {
            var paused = try await store.load(jobID: request.jobID)
            if !paused.state.isTerminal,
               paused.state != .awaitingPeerAcknowledgement {
                paused.state = .paused
                paused.updatedAt = Date()
                paused.message = error.localizedDescription
                try await store.save(paused)
            }
            if error is DirectClientControllerError || error is DirectRawReceiverError {
                throw error
            }
            throw DirectClientControllerError.exportInterrupted(request.jobID)
        }
    }

    public func exportFiles(
        _ request: DirectExportRequest,
        deviceID: UUID? = nil,
        transport: DirectTransportKind = .manualIP,
        port: UInt16 = HealthMdDirectProtocol.defaultManualIPPort,
        timeout: TimeInterval = 300
    ) async throws -> DirectFileExportResult {
        guard request.responseMode == .writeFiles,
              request.rawProfile == nil,
              request.destination != nil else {
            throw DirectClientControllerError.unexpectedExportMessage
        }
        guard request.createdAt.addingTimeInterval(HealthMdDirectProtocol.jobLifetime) > Date() else {
            throw DirectClientStorageError.jobExpired
        }
        let selectedID = try selectedDeviceID(deviceID)
        let store = try DirectJobStore(layout: layout)
        try await store.removeExpired()
        do {
            let existing = try await store.load(jobID: request.jobID)
            guard existing.request == request else { throw DirectFileReceiverError.requestChanged }
            if existing.state == .completed {
                return DirectFileExportResult(
                    receipt: try await DirectFileReceiver(
                        layout: layout,
                        jobStore: store
                    ).receipt(jobID: request.jobID),
                    endpoint: DirectServerEndpoint(
                        transport: transport,
                        port: transport == .manualIP ? port : nil,
                        serviceType: transport == .nearby ? HealthMdDirectProtocol.serviceType : nil
                    )
                )
            }
        } catch DirectClientStorageError.jobNotFound {
            try await store.save(try DirectJobRecord(request: request, createdAt: request.createdAt))
        }
        var record = try await store.load(jobID: request.jobID)
        guard record.state != .cancelled,
              record.state != .cancellationPending,
              record.state != .failed,
              !(await store.cancellationRequested(jobID: request.jobID)) else {
            throw DirectClientControllerError.jobNotResumable(request.jobID, record.state)
        }
        let intendedBinding = DirectPeerBinding(
            sourceInstallationID: selectedID,
            destinationInstallationID: identity.installationID
        )
        if let persistedBinding = record.peerBinding {
            guard persistedBinding == intendedBinding else {
                throw DirectClientControllerError.unexpectedDevice(selectedID)
            }
        } else {
            record.peerBinding = intendedBinding
        }
        record.state = .connecting
        record.updatedAt = Date()
        record.message = "Waiting for the paired iPhone to connect."
        try await store.save(record)

        let server = makeServer(transport: transport, port: port)
        let endpoint = try await server.start()
        defer { server.stop() }
        let receiver = DirectFileReceiver(layout: layout, jobStore: store)
        let deadline = Date().addingTimeInterval(timeout)
        do {
            while deadline > Date() {
                let remaining = max(0.1, deadline.timeIntervalSinceNow)
                let channel = try await server.acceptAuthenticatedClient(
                    timeout: remaining,
                    maximumAttempts: 1
                )
                if channel.peerInstallationID != selectedID {
                    channel.cancel()
                    continue
                }
                defer { channel.cancel() }
                let cancellationMonitor = cancellationMonitor(
                    jobID: request.jobID,
                    store: store,
                    channel: channel
                )
                defer { cancellationMonitor.cancel() }
                try await channel.send(.hello(localCapabilities))
                guard case .message(.hello(let peerCapabilities)) = try await receivePayload(
                    on: channel,
                    timeout: min(10, remaining)
                ),
                peerCapabilities.platform == .iOS,
                peerCapabilities.installationID == channel.peerInstallationID,
                localCapabilities.negotiatedProtocolVersion(with: peerCapabilities) != nil,
                let negotiation = localCapabilities.transfer.negotiated(with: peerCapabilities.transfer) else {
                    throw DirectChannelError.authenticationFailed(
                        "The connected peer cannot negotiate direct file transfer."
                    )
                }
                try await channel.send(.exportRequest(request))
                var accepted: DirectExportAccepted?
                while deadline > Date() {
                    let payload = try await receivePayload(
                        on: channel,
                        timeout: max(0.1, deadline.timeIntervalSinceNow)
                    )
                    switch payload {
                    case .binaryTransferFrame(let frame):
                        let (_, chunk) = try DirectTransferBinaryFrame.decode(frame)
                        try await channel.send(.transferChunkAcknowledgement(
                            try await receiver.receive(chunk)
                        ))
                    case .message(let message):
                        switch message {
                        case .exportAccepted(let value):
                            guard value.jobID == request.jobID,
                                  value.peerBinding == DirectPeerBinding(
                                    sourceInstallationID: peerCapabilities.installationID,
                                    destinationInstallationID: identity.installationID
                                  ),
                                  acceptedDatesMatchRequest(value, request: request),
                                  !value.resolvedDateIdentifiers.isEmpty else {
                                throw DirectClientControllerError.unexpectedExportMessage
                            }
                            accepted = value
                            var acceptedRecord = try await store.load(jobID: request.jobID)
                            acceptedRecord.state = .accepted
                            acceptedRecord.updatedAt = Date()
                            acceptedRecord.peerBinding = value.peerBinding
                            acceptedRecord.totalDays = value.resolvedDateIdentifiers.count
                            acceptedRecord.message = "iPhone accepted the direct file export."
                            try await store.save(acceptedRecord)
                        case .transferSession(let session):
                            guard let accepted,
                                  session.partitionTargetBytes == negotiation.partitionTargetBytes else {
                                throw DirectClientControllerError.unexpectedExportMessage
                            }
                            try await receiver.prepare(
                                request: request,
                                accepted: accepted,
                                session: session
                            )
                        case .fileManifest(let manifest):
                            try await receiver.store(manifest: manifest)
                        case .rawDayManifest:
                            throw DirectClientControllerError.unexpectedExportMessage
                        case .exportProgress(let progress):
                            guard progress.jobID == request.jobID else {
                                throw DirectClientControllerError.unexpectedExportMessage
                            }
                            var progressRecord = try await store.load(jobID: request.jobID)
                            progressRecord.state = progress.committedPartitions > 0 ? .transferring : .preparing
                            progressRecord.updatedAt = Date()
                            progressRecord.processedDays = progress.processedDays
                            progressRecord.totalDays = progress.totalDays
                            progressRecord.committedPartitions = progress.committedPartitions
                            progressRecord.committedBytes = progress.committedBytes
                            progressRecord.message = progress.message
                            try await store.save(progressRecord)
                        case .transferOpen(let open):
                            try await channel.send(.transferDisposition(
                                try await receiver.disposition(for: open)
                            ))
                        case .transferPartitionComplete(let complete):
                            try await channel.send(.transferPartitionAcknowledgement(
                                try await receiver.commit(complete)
                            ))
                        case .transferFinalize(let finalize):
                            let receipt = try await receiver.finalize(finalize)
                            try await channel.send(.transferFinalAcknowledgement(
                                try DirectTransferFinalAcknowledgement(
                                    sessionID: finalize.sessionID,
                                    jobID: finalize.jobID,
                                    accepted: true,
                                    totalPartitions: finalize.totalPartitions,
                                    totalBytes: finalize.totalBytes,
                                    finalPartitionSHA256: finalize.finalPartitionSHA256,
                                    responseByteCount: receipt.responseByteCount,
                                    responseSHA256: receipt.responseSHA256,
                                    message: "CLI committed generated files to the explicit destination."
                                )
                            ))
                            guard case .message(.completionConfirmed(let confirmedID)) = try await receivePayload(
                                on: channel,
                                timeout: max(0.1, deadline.timeIntervalSinceNow)
                            ), confirmedID == request.jobID else {
                                throw DirectChannelError.connectionClosed
                            }
                            try await receiver.acknowledgePeerCompletion(jobID: request.jobID)
                            return DirectFileExportResult(receipt: receipt, endpoint: endpoint)
                        case .exportRejected(let failure):
                            var failed = try await store.load(jobID: request.jobID)
                            failed.state = failure.reason == .cancelled ? .cancelled : .failed
                            failed.updatedAt = Date()
                            failed.failure = failure
                            failed.message = failure.message
                            try await store.save(failed)
                            throw DirectClientControllerError.exportRejected(failure)
                        case .ping:
                            try await channel.send(.pong)
                        case .cancelAcknowledged(let jobID) where jobID == request.jobID:
                            try await receiver.cancel(jobID: jobID)
                            await store.clearCancellationRequest(jobID: jobID)
                            throw DirectRawReceiverError.cancelled
                        case .hello, .statusRequest, .statusResponse, .exportRequest,
                             .transferDisposition, .transferChunk,
                             .transferChunkAcknowledgement,
                             .transferPartitionAcknowledgement,
                             .transferFinalAcknowledgement, .completionConfirmed,
                             .cancel, .pong, .cancelAcknowledged:
                            break
                        }
                    }
                }
                throw DirectChannelError.timedOut
            }
            throw DirectChannelError.timedOut
        } catch {
            var paused = try await store.load(jobID: request.jobID)
            if !paused.state.isTerminal,
               paused.state != .awaitingPeerAcknowledgement {
                paused.state = .paused
                paused.updatedAt = Date()
                paused.message = error.localizedDescription
                try await store.save(paused)
            }
            if error is DirectClientControllerError
                || error is DirectFileReceiverError
                || error is DirectRawReceiverError {
                throw error
            }
            throw DirectClientControllerError.exportInterrupted(request.jobID)
        }
    }

    public func resume(
        jobID: UUID,
        deviceID: UUID? = nil,
        transport: DirectTransportKind = .manualIP,
        port: UInt16 = HealthMdDirectProtocol.defaultManualIPPort,
        timeout: TimeInterval = 300,
        validateArtifact: (@Sendable (DirectRawReceiveArtifact) throws -> Void)? = nil
    ) async throws -> DirectExportResult {
        let store = try DirectJobStore(layout: layout)
        let record = try await store.load(jobID: jobID)
        guard record.state != .cancelled,
              record.state != .cancellationPending,
              record.state != .failed,
              !(await store.cancellationRequested(jobID: jobID)) else {
            throw DirectClientControllerError.jobNotResumable(jobID, record.state)
        }
        let pinnedDeviceID = try pinnedDeviceID(for: record, requested: deviceID)
        return try await export(
            record.request,
            deviceID: pinnedDeviceID,
            transport: transport,
            port: port,
            timeout: timeout,
            validateArtifact: validateArtifact
        )
    }

    public func resumeFiles(
        jobID: UUID,
        deviceID: UUID? = nil,
        transport: DirectTransportKind = .manualIP,
        port: UInt16 = HealthMdDirectProtocol.defaultManualIPPort,
        timeout: TimeInterval = 300
    ) async throws -> DirectFileExportResult {
        let store = try DirectJobStore(layout: layout)
        let record = try await store.load(jobID: jobID)
        guard record.state != .cancelled,
              record.state != .cancellationPending,
              record.state != .failed,
              !(await store.cancellationRequested(jobID: jobID)) else {
            throw DirectClientControllerError.jobNotResumable(jobID, record.state)
        }
        let pinnedDeviceID = try pinnedDeviceID(for: record, requested: deviceID)
        return try await exportFiles(
            record.request,
            deviceID: pinnedDeviceID,
            transport: transport,
            port: port,
            timeout: timeout
        )
    }

    public func jobRecord(jobID: UUID) async throws -> DirectJobRecord {
        let store = try DirectJobStore(layout: layout)
        var record = try await store.load(jobID: jobID)
        if await store.cancellationRequested(jobID: jobID), !record.state.isTerminal {
            record.state = .cancellationPending
            record.message = "Cancellation is pending delivery to the paired iPhone."
        }
        return record
    }

    public func completedArtifact(jobID: UUID) async throws -> DirectRawReceiveArtifact {
        let store = try DirectJobStore(layout: layout)
        return try await DirectRawReceiver(layout: layout, jobStore: store).artifact(jobID: jobID)
    }

    public func completedFileReceipt(jobID: UUID) async throws -> DirectFileExportReceipt {
        let store = try DirectJobStore(layout: layout)
        return try await DirectFileReceiver(layout: layout, jobStore: store).receipt(jobID: jobID)
    }

    public func cancel(
        jobID: UUID,
        deviceID: UUID? = nil,
        transport: DirectTransportKind = .manualIP,
        port: UInt16 = HealthMdDirectProtocol.defaultManualIPPort,
        timeout: TimeInterval = 20
    ) async throws {
        let store = try DirectJobStore(layout: layout)
        let record = try await store.load(jobID: jobID)
        if record.state == .completed || record.state == .failed || record.state == .cancelled { return }
        let selectedID = try pinnedDeviceID(for: record, requested: deviceID)
        try await store.requestCancellation(jobID: jobID)
        var pending = try await store.load(jobID: jobID)
        pending.state = .cancellationPending
        pending.updatedAt = Date()
        pending.message = "Cancellation is pending delivery to the paired iPhone."
        try await store.save(pending)

        let server = makeServer(transport: transport, port: port)
        let cancellationDeadline = Date().addingTimeInterval(timeout)
        do {
            _ = try await server.start()
            defer { server.stop() }
            let channel = try await server.acceptAuthenticatedClient(
                timeout: max(0.1, cancellationDeadline.timeIntervalSinceNow),
                maximumAttempts: 1
            )
            guard channel.peerInstallationID == selectedID else {
                channel.cancel()
                throw DirectClientControllerError.unexpectedDevice(channel.peerInstallationID)
            }
            defer { channel.cancel() }
            try await channel.send(.hello(localCapabilities))
            guard case .message(.hello) = try await receivePayload(on: channel, timeout: min(10, timeout)) else {
                throw DirectChannelError.decodeFailed
            }
            try await channel.send(.cancel(jobID: jobID))
            guard case .message(.cancelAcknowledged(let acknowledgedID)) = try await receivePayload(
                on: channel,
                timeout: timeout
            ), acknowledgedID == jobID else {
                throw DirectChannelError.decodeFailed
            }
            try await DirectRawReceiver(layout: layout, jobStore: store).cancel(jobID: jobID)
            await store.clearCancellationRequest(jobID: jobID)
        } catch {
            while !Task.isCancelled, cancellationDeadline > Date() {
                if let current = try? await store.load(jobID: jobID), current.state == .cancelled {
                    await store.clearCancellationRequest(jobID: jobID)
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            throw DirectClientControllerError.cancellationPending(jobID)
        }
    }

    public var localCapabilities: DirectPeerCapabilities {
        DirectPeerCapabilities(
            platform: .macOSCLI,
            installationID: identity.installationID
        )
    }

    private func cancellationMonitor(
        jobID: UUID,
        store: DirectJobStore,
        channel: DirectSecureChannel
    ) -> Task<Void, Never> {
        Task {
            while !Task.isCancelled {
                if await store.cancellationRequested(jobID: jobID) {
                    try? await channel.send(.cancel(jobID: jobID))
                    return
                }
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
        }
    }

    func acceptedDatesMatchRequest(
        _ accepted: DirectExportAccepted,
        request: DirectExportRequest
    ) -> Bool {
        guard case .exact(let start, let end) = request.dateSelection else { return true }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone(secondsFromGMT: 0)
        formatter.dateFormat = "yyyy-MM-dd"
        formatter.isLenient = false
        guard let startDate = formatter.date(from: start),
              let endDate = formatter.date(from: end),
              startDate <= endDate else { return false }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        var current = startDate
        for identifier in accepted.resolvedDateIdentifiers {
            guard current <= endDate,
                  identifier == formatter.string(from: current),
                  let next = calendar.date(byAdding: .day, value: 1, to: current) else {
                return false
            }
            current = next
        }
        return current > endDate
    }

    private func pinnedDeviceID(
        for record: DirectJobRecord,
        requested: UUID?
    ) throws -> UUID {
        guard let binding = record.peerBinding,
              binding.destinationInstallationID == identity.installationID else {
            throw DirectClientControllerError.jobNotResumable(record.request.jobID, record.state)
        }
        if let requested, requested != binding.sourceInstallationID {
            throw DirectClientControllerError.unexpectedDevice(requested)
        }
        guard pairedDevices().contains(where: {
            $0.installationID == binding.sourceInstallationID
        }) else {
            throw DirectClientControllerError.deviceNotPaired(binding.sourceInstallationID)
        }
        return binding.sourceInstallationID
    }

    private func selectedDeviceID(_ requested: UUID?) throws -> UUID {
        let devices = pairedDevices()
        if let requested {
            guard devices.contains(where: { $0.installationID == requested }) else {
                throw DirectClientControllerError.deviceNotPaired(requested)
            }
            return requested
        }
        guard devices.count == 1, let only = devices.first else {
            throw DirectClientControllerError.deviceSelectionRequired(devices.map(\.installationID))
        }
        return only.installationID
    }

    private func makeServer(
        transport: DirectTransportKind,
        port: UInt16
    ) -> DirectServerListener {
        switch transport {
        case .manualIP:
            return .manualIP(DirectManualIPServer(
                installationID: identity.installationID,
                port: port,
                trustStore: trustStore
            ))
        case .nearby:
            return .nearby(DirectNearbyServer(
                installationID: identity.installationID,
                trustStore: trustStore
            ))
        }
    }

    private func receivePayload(
        on channel: DirectSecureChannel,
        timeout: TimeInterval
    ) async throws -> DirectSecurePayload {
        try await withThrowingTaskGroup(of: DirectSecurePayload.self) { group in
            group.addTask { try await channel.receive() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                channel.cancel()
                throw DirectChannelError.timedOut
            }
            guard let first = try await group.next() else {
                throw DirectChannelError.connectionClosed
            }
            group.cancelAll()
            return first
        }
    }

    private func receiveMessage(
        on channel: DirectSecureChannel,
        timeout: TimeInterval
    ) async throws -> DirectMessage {
        try await withThrowingTaskGroup(of: DirectSecurePayload.self) { group in
            group.addTask { try await channel.receive() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(max(0, timeout) * 1_000_000_000))
                channel.cancel()
                throw DirectChannelError.timedOut
            }
            guard let first = try await group.next() else {
                throw DirectChannelError.connectionClosed
            }
            group.cancelAll()
            guard case .message(let message) = first else {
                throw DirectChannelError.decodeFailed
            }
            return message
        }
    }
}
