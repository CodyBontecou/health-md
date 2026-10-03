import Darwin
import Foundation
import HealthMdConnectionCore
@testable import HealthMdDirectClientCore
import XCTest

final class HealthMdDirectClientCoreTests: XCTestCase {
    func testExactRequestRequiresAcceptedDatesToMatchInclusiveRange() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let controller = try DirectClientController(rootURL: root)
        let jobID = UUID()
        let request = DirectExportRequest(
            jobID: jobID,
            createdAt: Date(),
            dateSelection: .exact(start: "2026-07-01", end: "2026-07-03"),
            responseMode: .rawJSON,
            rawProfile: .canonicalSourceRecordsV1
        )
        let binding = DirectPeerBinding(
            sourceInstallationID: UUID(),
            destinationInstallationID: controller.identity.installationID
        )
        let matching = DirectExportAccepted(
            jobID: jobID,
            acceptedAt: Date(),
            peerBinding: binding,
            resolvedDateIdentifiers: ["2026-07-01", "2026-07-02", "2026-07-03"]
        )
        let missingDay = DirectExportAccepted(
            jobID: jobID,
            acceptedAt: Date(),
            peerBinding: binding,
            resolvedDateIdentifiers: ["2026-07-01", "2026-07-03"]
        )
        XCTAssertTrue(controller.acceptedDatesMatchRequest(matching, request: request))
        XCTAssertFalse(controller.acceptedDatesMatchRequest(missingDay, request: request))
    }

    func testNearbyServerPairsAndExchangesAuthenticatedDirectMessages() async throws {
        let serverTrust = InMemoryManualIPTrustStore()
        let clientTrust = InMemoryManualIPTrustStore()
        let serverID = UUID()
        let clientID = UUID()
        let server = DirectNearbyServer(
            installationID: serverID,
            displayName: "Nearby Test CLI",
            trustStore: serverTrust
        )
        let endpoint = try server.start()
        defer { server.stop() }
        XCTAssertEqual(endpoint.serviceType, HealthMdDirectProtocol.serviceType)
        let client = DirectNearbyClient(
            installationID: clientID,
            displayName: "Nearby Test iPhone",
            trustStore: clientTrust
        )
        async let accepted = server.acceptAuthenticatedClient(
            pairingCode: "654321",
            pairingCodeExpiresAt: Date().addingTimeInterval(30),
            timeout: 20,
            maximumAttempts: 1
        )
        let clientTask = Task {
            try await client.connect(pairingCode: "654321", timeout: 20)
        }
        let serverChannel = try await accepted
        let clientChannel = try await clientTask.value
        defer {
            clientChannel.cancel()
            serverChannel.cancel()
        }
        XCTAssertEqual(clientChannel.peerInstallationID, serverID)
        XCTAssertEqual(serverChannel.peerInstallationID, clientID)
        XCTAssertNil(client.savedServer())
        let hello = DirectMessage.hello(DirectPeerCapabilities(
            platform: .iOS,
            installationID: clientID
        ))
        try await clientChannel.send(hello)
        let receivedHello = try await serverChannel.receive()
        XCTAssertEqual(receivedHello, .message(hello))
        try client.commitProvisionalServer()
        XCTAssertEqual(server.trustedClients().map(\.installationID), [clientID])
        XCTAssertEqual(client.savedServer()?.installationID, serverID)

        clientChannel.cancel()
        serverChannel.cancel()
        async let reaccepted = server.acceptAuthenticatedClient(
            timeout: 20,
            maximumAttempts: 1
        )
        let reconnectTask = Task { try await client.connect(timeout: 20) }
        let reconnectedServer = try await reaccepted
        let reconnectedClient = try await reconnectTask.value
        XCTAssertEqual(reconnectedServer.peerInstallationID, clientID)
        XCTAssertEqual(reconnectedClient.peerInstallationID, serverID)
        reconnectedServer.cancel()
        reconnectedClient.cancel()
    }

    func testManualIPServerPairsAndExchangesAuthenticatedDirectMessages() async throws {
        let serverTrust = InMemoryManualIPTrustStore()
        let clientTrust = InMemoryManualIPTrustStore()
        let serverID = UUID()
        let clientID = UUID()
        let port = try unusedLoopbackPort()
        let server = DirectManualIPServer(
            installationID: serverID,
            displayName: "Test CLI",
            port: port,
            trustStore: serverTrust
        )
        _ = try await server.start()
        defer { server.stop() }
        let client = DirectManualIPClient(
            installationID: clientID,
            displayName: "Test iPhone",
            trustStore: clientTrust
        )

        async let accepted = server.acceptAuthenticatedClient(
            pairingCode: "123456",
            pairingCodeExpiresAt: Date().addingTimeInterval(60),
            timeout: 10,
            maximumAttempts: 1
        )
        let clientChannel = try await client.connect(
            host: "127.0.0.1",
            port: port,
            pairingCode: "123456",
            timeout: 10
        )
        let serverChannel = try await accepted
        defer {
            clientChannel.cancel()
            serverChannel.cancel()
        }
        XCTAssertEqual(clientChannel.peerInstallationID, serverID)
        XCTAssertEqual(serverChannel.peerInstallationID, clientID)
        XCTAssertNil(client.savedServer())

        let capabilities = DirectPeerCapabilities(platform: .iOS, installationID: clientID)
        try await clientChannel.send(.hello(capabilities))
        let received = try await serverChannel.receive()
        XCTAssertEqual(received, .message(.hello(capabilities)))
        try client.commitProvisionalServer()

        try await serverChannel.send(.statusRequest(DirectStatusRequest(
            requestedAt: Date(timeIntervalSince1970: 1_700_000_000)
        )))
        guard case .message(.statusRequest(let request)) = try await clientChannel.receive() else {
            return XCTFail("Expected authenticated status request")
        }
        XCTAssertEqual(request.requestedAt, Date(timeIntervalSince1970: 1_700_000_000))
        XCTAssertEqual(server.trustedClients().map(\.installationID), [clientID])
        XCTAssertEqual(client.savedServer()?.installationID, serverID)

        clientChannel.cancel()
        serverChannel.cancel()
        server.stop()
        let reconnectPort = try unusedLoopbackPort()
        let reconnectServer = DirectManualIPServer(
            installationID: serverID,
            displayName: "Test CLI",
            port: reconnectPort,
            trustStore: serverTrust
        )
        _ = try await reconnectServer.start()
        defer { reconnectServer.stop() }
        async let reaccepted = reconnectServer.acceptAuthenticatedClient(
            timeout: 10,
            maximumAttempts: 1
        )
        let reconnectedClient = try await client.connect(
            host: "127.0.0.1",
            port: reconnectPort,
            timeout: 10
        )
        let reconnectedServer = try await reaccepted
        XCTAssertEqual(reconnectedClient.peerInstallationID, serverID)
        XCTAssertEqual(reconnectedServer.peerInstallationID, clientID)
        reconnectedClient.cancel()
        reconnectedServer.cancel()
    }

    func testIdentityIsStableAndFilesAreRestricted() throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = try DirectClientStorageLayout(rootURL: root)
        let store = DirectClientIdentityStore(layout: layout)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        let first = try store.loadOrCreate(now: now)
        let second = try store.loadOrCreate(now: now.addingTimeInterval(10))
        XCTAssertEqual(first, second)
        XCTAssertEqual(first.createdAt, now)
        XCTAssertEqual(posixPermissions(at: root), 0o700)
        XCTAssertEqual(posixPermissions(at: layout.identityURL), 0o600)
    }

    func testResumeRejectsDeviceDifferentFromPersistedPeerBinding() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let trust = InMemoryManualIPTrustStore()
        let controller = try DirectClientController(rootURL: root, trustStore: trust)
        let pinnedID = UUID()
        let otherID = UUID()
        let now = Date()
        try trust.saveState(ManualIPTrustState(
            ownerInstallationID: controller.identity.installationID,
            trustedClients: [pinnedID, otherID].map {
                ManualIPTrustedClient(
                    installationID: $0,
                    displayName: $0 == pinnedID ? "Pinned" : "Other",
                    reconnectSecret: Data(repeating: 0x4d, count: 32),
                    pairedAt: now,
                    lastConnectedAt: now
                )
            }
        ))
        let request = DirectExportRequest(
            jobID: UUID(),
            createdAt: now,
            dateSelection: .exact(start: "2026-07-01", end: "2026-07-01"),
            responseMode: .rawJSON,
            rawProfile: .canonicalSourceRecordsV1
        )
        var record = try DirectJobRecord(request: request, createdAt: request.createdAt)
        record.state = .paused
        record.peerBinding = DirectPeerBinding(
            sourceInstallationID: pinnedID,
            destinationInstallationID: controller.identity.installationID
        )
        try await DirectJobStore(layout: controller.layout).save(record)
        do {
            _ = try await controller.resume(
                jobID: request.jobID,
                deviceID: otherID,
                port: try unusedLoopbackPort(),
                timeout: 1
            )
            XCTFail("Expected persisted peer mismatch")
        } catch DirectClientControllerError.unexpectedDevice(let identifier) {
            XCTAssertEqual(identifier, otherID)
        }
    }

    func testCancelRoutesThroughAlreadyActiveExportListener() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let serverTrust = InMemoryManualIPTrustStore()
        let clientTrust = InMemoryManualIPTrustStore()
        let controller = try DirectClientController(rootURL: root, trustStore: serverTrust)
        let clientID = UUID()
        let secret = Data(repeating: 0x6c, count: 32)
        let now = Date()
        let port = try unusedLoopbackPort()
        try serverTrust.saveState(ManualIPTrustState(
            ownerInstallationID: controller.identity.installationID,
            trustedClients: [ManualIPTrustedClient(
                installationID: clientID,
                displayName: "Cancellation iPhone",
                reconnectSecret: secret,
                pairedAt: now,
                lastConnectedAt: now
            )]
        ))
        try clientTrust.saveState(ManualIPTrustState(
            ownerInstallationID: clientID,
            trustedMac: ManualIPTrustedMac(
                installationID: controller.identity.installationID,
                displayName: "Cancellation CLI",
                host: "127.0.0.1",
                port: port,
                reconnectSecret: secret,
                pairedAt: now
            )
        ))
        let request = DirectExportRequest(
            jobID: UUID(),
            createdAt: now,
            dateSelection: .exact(start: "2026-07-01", end: "2026-07-01"),
            responseMode: .rawJSON,
            rawProfile: .canonicalSourceRecordsV1
        )
        let phone = DirectManualIPClient(
            installationID: clientID,
            displayName: "Cancellation iPhone",
            trustStore: clientTrust
        )
        let producer = Task {
            try await Task.sleep(nanoseconds: 100_000_000)
            let channel = try await phone.connect(host: "127.0.0.1", port: port, timeout: 10)
            defer { channel.cancel() }
            try await channel.send(.hello(DirectPeerCapabilities(
                platform: .iOS,
                installationID: clientID
            )))
            guard case .message(.hello) = try await channel.receive(),
                  case .message(.exportRequest(let received)) = try await channel.receive(),
                  received == request else {
                throw DirectClientControllerError.unexpectedExportMessage
            }
            try await channel.send(.exportAccepted(DirectExportAccepted(
                jobID: request.jobID,
                acceptedAt: now,
                peerBinding: DirectPeerBinding(
                    sourceInstallationID: clientID,
                    destinationInstallationID: controller.identity.installationID
                ),
                resolvedDateIdentifiers: ["2026-07-01"]
            )))
            guard case .message(.cancel(let cancelledID)) = try await channel.receive(),
                  cancelledID == request.jobID else {
                throw DirectClientControllerError.unexpectedExportMessage
            }
            try await channel.send(.cancelAcknowledged(jobID: request.jobID))
        }
        let exporting = Task {
            try await controller.export(
                request,
                deviceID: clientID,
                port: port,
                timeout: 10
            )
        }
        try await Task.sleep(nanoseconds: 400_000_000)
        try await controller.cancel(
            jobID: request.jobID,
            deviceID: clientID,
            port: port,
            timeout: 5
        )
        try await producer.value
        do {
            _ = try await exporting.value
            XCTFail("Expected active export cancellation")
        } catch DirectRawReceiverError.cancelled {
            // Expected.
        }
        let cancelledRecord = try await controller.jobRecord(jobID: request.jobID)
        XCTAssertEqual(cancelledRecord.state, .cancelled)
    }

    func testControllerReceivesAuthenticatedRawExportEndToEnd() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let serverTrust = InMemoryManualIPTrustStore()
        let clientTrust = InMemoryManualIPTrustStore()
        let controller = try DirectClientController(rootURL: root, trustStore: serverTrust)
        let clientID = UUID()
        let secret = Data(repeating: 0x5a, count: 32)
        let now = Date(timeIntervalSince1970: 1_700_000_000)
        try serverTrust.saveState(ManualIPTrustState(
            ownerInstallationID: controller.identity.installationID,
            trustedClients: [ManualIPTrustedClient(
                installationID: clientID,
                displayName: "Integration iPhone",
                reconnectSecret: secret,
                pairedAt: now,
                lastConnectedAt: now
            )]
        ))
        let port = try unusedLoopbackPort()
        try clientTrust.saveState(ManualIPTrustState(
            ownerInstallationID: clientID,
            trustedMac: ManualIPTrustedMac(
                installationID: controller.identity.installationID,
                displayName: "Integration CLI",
                host: "127.0.0.1",
                port: port,
                reconnectSecret: secret,
                pairedAt: now
            )
        ))
        let request = DirectExportRequest(
            jobID: UUID(),
            createdAt: Date(),
            dateSelection: .exact(start: "2026-07-01", end: "2026-07-01"),
            responseMode: .rawJSON,
            rawProfile: .canonicalSourceRecordsV1
        )
        let healthData = try JSONSerialization.data(withJSONObject: [
            "schema": "healthmd.health_data",
            "schema_version": 7,
            "time_context": ["calendar_time_zone_identifier": "UTC"],
            "healthkit_record_archive": [
                "schema": "healthmd.healthkit_records",
                "schema_version": 1
            ]
        ], options: [.sortedKeys])
        let phone = DirectManualIPClient(
            installationID: clientID,
            displayName: "Integration iPhone",
            trustStore: clientTrust
        )
        let producer = Task {
            try await Task.sleep(nanoseconds: 100_000_000)
            let channel = try await phone.connect(host: "127.0.0.1", port: port, timeout: 10)
            defer { channel.cancel() }
            let capabilities = DirectPeerCapabilities(platform: .iOS, installationID: clientID)
            try await channel.send(.hello(capabilities))
            guard case .message(.hello) = try await channel.receive(),
                  case .message(.exportRequest(let receivedRequest)) = try await channel.receive(),
                  receivedRequest == request else {
                throw DirectClientControllerError.unexpectedExportMessage
            }
            let binding = DirectPeerBinding(
                sourceInstallationID: clientID,
                destinationInstallationID: controller.identity.installationID
            )
            let accepted = DirectExportAccepted(
                jobID: request.jobID,
                acceptedAt: Date(),
                peerBinding: binding,
                resolvedDateIdentifiers: ["2026-07-01"],
                sourceDeviceName: "Integration iPhone",
                sourceTimeZoneIdentifier: "UTC"
            )
            let session = try DirectTransferSession(
                sessionID: UUID(),
                jobID: request.jobID,
                requestFingerprint: try DirectRequestFingerprint.make(for: receivedRequest),
                peerBinding: binding,
                partitionTargetBytes: DirectTransferLimits.preferredPartitionBytes,
                createdAt: Date()
            )
            let manifest = try DirectRawDayManifest(
                jobID: request.jobID,
                date: "2026-07-01",
                status: "complete",
                captureStatus: "complete",
                sampleCount: 1,
                recordCount: 1,
                queryStatusCounts: ["success": 1],
                integrityWarningCount: 0,
                integrityWarningCodes: [],
                partialFailureCount: 0,
                partialFailureTypes: [],
                healthDataByteCount: Int64(healthData.count),
                healthDataSHA256: DirectTransferFile.sha256Hex(healthData)
            )
            let descriptor = try DirectTransferPartition(
                index: 0,
                transferID: UUID(),
                sourceDates: [manifest.date],
                byteCount: Int64(healthData.count),
                chunkCount: 1,
                sha256: DirectTransferFile.sha256Hex(healthData),
                previousSHA256: nil,
                itemSegment: try DirectTransferItemSegment(
                    itemID: manifest.date,
                    offset: 0,
                    itemByteCount: Int64(healthData.count),
                    isFinalSegment: true
                )
            )
            try await channel.send(.exportAccepted(accepted))
            try await channel.send(.transferSession(session))
            try await channel.send(.rawDayManifest(manifest))
            try await channel.send(.transferOpen(try DirectTransferOpen(
                session: session,
                partition: descriptor
            )))
            guard case .message(.transferDisposition(let disposition)) = try await channel.receive(),
                  disposition.disposition == .needed else {
                throw DirectClientControllerError.unexpectedExportMessage
            }
            let chunk = try DirectTransferChunk(
                transferID: descriptor.transferID,
                sequence: 1,
                data: healthData,
                sha256: DirectTransferFile.sha256Hex(healthData)
            )
            try await channel.sendBinaryTransferFrame(try DirectTransferBinaryFrame.encode(chunk))
            guard case .message(.transferChunkAcknowledgement(let chunkAck)) = try await channel.receive(),
                  chunkAck.accepted else {
                throw DirectClientControllerError.unexpectedExportMessage
            }
            try await channel.send(.transferPartitionComplete(try DirectTransferPartitionComplete(
                sessionID: session.sessionID,
                jobID: request.jobID,
                partitionIndex: 0,
                transferID: descriptor.transferID,
                partitionSHA256: descriptor.sha256
            )))
            guard case .message(.transferPartitionAcknowledgement(let partitionAck)) = try await channel.receive(),
                  partitionAck.accepted else {
                throw DirectClientControllerError.unexpectedExportMessage
            }
            try await channel.send(.transferFinalize(try DirectTransferFinalize(
                sessionID: session.sessionID,
                jobID: request.jobID,
                requestFingerprint: session.requestFingerprint,
                totalPartitions: 1,
                totalBytes: Int64(healthData.count),
                finalPartitionSHA256: descriptor.sha256
            )))
            guard case .message(.transferFinalAcknowledgement(let finalAck)) = try await channel.receive(),
                  finalAck.accepted else {
                throw DirectClientControllerError.unexpectedExportMessage
            }
            try await channel.send(.completionConfirmed(jobID: request.jobID))
        }
        let result = try await controller.export(
            request,
            deviceID: clientID,
            port: port,
            timeout: 15
        )
        try await producer.value
        XCTAssertEqual(result.artifact.status, "success")
        XCTAssertEqual(result.artifact.totalDays, 1)
        XCTAssertTrue(FileManager.default.fileExists(atPath: result.artifact.fileURL.path))
        let completedRecord = try await controller.jobRecord(jobID: request.jobID)
        XCTAssertEqual(completedRecord.state, .completed)
    }

    func testControllerReceivesAuthenticatedGeneratedFileEndToEnd() async throws {
        let root = temporaryRoot()
        let destination = temporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let serverTrust = InMemoryManualIPTrustStore()
        let clientTrust = InMemoryManualIPTrustStore()
        let controller = try DirectClientController(rootURL: root, trustStore: serverTrust)
        let clientID = UUID()
        let secret = Data(repeating: 0x2b, count: 32)
        let now = Date()
        try serverTrust.saveState(ManualIPTrustState(
            ownerInstallationID: controller.identity.installationID,
            trustedClients: [ManualIPTrustedClient(
                installationID: clientID,
                displayName: "File iPhone",
                reconnectSecret: secret,
                pairedAt: now,
                lastConnectedAt: now
            )]
        ))
        let port = try unusedLoopbackPort()
        try clientTrust.saveState(ManualIPTrustState(
            ownerInstallationID: clientID,
            trustedMac: ManualIPTrustedMac(
                installationID: controller.identity.installationID,
                displayName: "File CLI",
                host: "127.0.0.1",
                port: port,
                reconnectSecret: secret,
                pairedAt: now
            )
        ))
        let request = DirectExportRequest(
            jobID: UUID(),
            createdAt: now,
            dateSelection: .exact(start: "2026-07-01", end: "2026-07-01"),
            responseMode: .writeFiles,
            destination: DirectExportDestination(rootPath: destination.path)
        )
        let content = Data("{\"schema\":\"healthmd.health_data\",\"schema_version\":7}\n".utf8)
        let phone = DirectManualIPClient(
            installationID: clientID,
            displayName: "File iPhone",
            trustStore: clientTrust
        )
        let producer = Task {
            try await Task.sleep(nanoseconds: 100_000_000)
            let channel = try await phone.connect(host: "127.0.0.1", port: port, timeout: 10)
            defer { channel.cancel() }
            try await channel.send(.hello(DirectPeerCapabilities(
                platform: .iOS,
                installationID: clientID
            )))
            guard case .message(.hello) = try await channel.receive(),
                  case .message(.exportRequest(let received)) = try await channel.receive(),
                  received == request else {
                throw DirectClientControllerError.unexpectedExportMessage
            }
            let binding = DirectPeerBinding(
                sourceInstallationID: clientID,
                destinationInstallationID: controller.identity.installationID
            )
            let accepted = DirectExportAccepted(
                jobID: request.jobID,
                acceptedAt: now,
                peerBinding: binding,
                resolvedDateIdentifiers: ["2026-07-01"]
            )
            let session = try DirectTransferSession(
                sessionID: UUID(),
                jobID: request.jobID,
                requestFingerprint: try DirectRequestFingerprint.make(for: request),
                peerBinding: binding,
                partitionTargetBytes: DirectTransferLimits.preferredPartitionBytes,
                createdAt: now
            )
            let manifest = try DirectExportFileManifest(
                jobID: request.jobID,
                fileID: UUID(),
                relativePath: "Health/2026-07-01.json",
                byteCount: Int64(content.count),
                sha256: DirectTransferFile.sha256Hex(content),
                writeMode: .overwrite
            )
            let itemID = manifest.fileID.uuidString.lowercased()
            let descriptor = try DirectTransferPartition(
                index: 0,
                transferID: UUID(),
                sourceDates: [itemID],
                byteCount: Int64(content.count),
                chunkCount: 1,
                sha256: manifest.sha256,
                previousSHA256: nil,
                itemSegment: try DirectTransferItemSegment(
                    itemID: itemID,
                    offset: 0,
                    itemByteCount: Int64(content.count),
                    isFinalSegment: true
                )
            )
            try await channel.send(.exportAccepted(accepted))
            try await channel.send(.transferSession(session))
            try await channel.send(.fileManifest(manifest))
            try await channel.send(.transferOpen(try DirectTransferOpen(
                session: session,
                partition: descriptor
            )))
            guard case .message(.transferDisposition(let disposition)) = try await channel.receive(),
                  disposition.disposition == .needed else {
                throw DirectClientControllerError.unexpectedExportMessage
            }
            let chunk = try DirectTransferChunk(
                transferID: descriptor.transferID,
                sequence: 1,
                data: content,
                sha256: manifest.sha256
            )
            try await channel.sendBinaryTransferFrame(try DirectTransferBinaryFrame.encode(chunk))
            guard case .message(.transferChunkAcknowledgement(let chunkAck)) = try await channel.receive(),
                  chunkAck.accepted else {
                throw DirectClientControllerError.unexpectedExportMessage
            }
            try await channel.send(.transferPartitionComplete(try DirectTransferPartitionComplete(
                sessionID: session.sessionID,
                jobID: request.jobID,
                partitionIndex: 0,
                transferID: descriptor.transferID,
                partitionSHA256: descriptor.sha256
            )))
            guard case .message(.transferPartitionAcknowledgement(let partitionAck)) = try await channel.receive(),
                  partitionAck.accepted else {
                throw DirectClientControllerError.unexpectedExportMessage
            }
            try await channel.send(.transferFinalize(try DirectTransferFinalize(
                sessionID: session.sessionID,
                jobID: request.jobID,
                requestFingerprint: session.requestFingerprint,
                totalPartitions: 1,
                totalBytes: Int64(content.count),
                finalPartitionSHA256: descriptor.sha256,
                outcome: try DirectExportOutcome(
                    status: "success",
                    successCount: 1,
                    totalCount: 1
                )
            )))
            guard case .message(.transferFinalAcknowledgement(let finalAck)) = try await channel.receive(),
                  finalAck.accepted else {
                throw DirectClientControllerError.unexpectedExportMessage
            }
            try await channel.send(.completionConfirmed(jobID: request.jobID))
        }
        let result = try await controller.exportFiles(
            request,
            deviceID: clientID,
            port: port,
            timeout: 15
        )
        try await producer.value
        XCTAssertEqual(result.receipt.filesWritten, 1)
        XCTAssertEqual(result.receipt.destinationPath, destination.path)
        XCTAssertEqual(
            try Data(contentsOf: destination.appendingPathComponent("Health/2026-07-01.json")),
            content
        )
    }

    func testDirectFileReceiverAppliesAppendExactlyOnceAndRejectsTraversal() async throws {
        let root = temporaryRoot()
        let destination = temporaryRoot()
        defer {
            try? FileManager.default.removeItem(at: root)
            try? FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let existingFolder = destination.appendingPathComponent("Health", isDirectory: true)
        try FileManager.default.createDirectory(at: existingFolder, withIntermediateDirectories: true)
        let output = existingFolder.appendingPathComponent("daily.md")
        try Data("old".utf8).write(to: output)

        let layout = try DirectClientStorageLayout(rootURL: root)
        let store = try DirectJobStore(layout: layout)
        let request = DirectExportRequest(
            jobID: UUID(),
            createdAt: Date(),
            dateSelection: .exact(start: "2026-07-01", end: "2026-07-01"),
            responseMode: .writeFiles,
            destination: DirectExportDestination(rootPath: destination.standardizedFileURL.path)
        )
        try await store.save(try DirectJobRecord(request: request, createdAt: request.createdAt))
        let binding = DirectPeerBinding(sourceInstallationID: UUID(), destinationInstallationID: UUID())
        let accepted = DirectExportAccepted(
            jobID: request.jobID,
            acceptedAt: Date(),
            peerBinding: binding,
            resolvedDateIdentifiers: ["2026-07-01"]
        )
        let session = try DirectTransferSession(
            sessionID: UUID(),
            jobID: request.jobID,
            requestFingerprint: try DirectRequestFingerprint.make(for: request),
            peerBinding: binding,
            partitionTargetBytes: DirectTransferLimits.minimumPartitionBytes,
            createdAt: Date()
        )
        let content = Data("new".utf8)
        let manifest = try DirectExportFileManifest(
            jobID: request.jobID,
            fileID: UUID(),
            relativePath: "Health/daily.md",
            byteCount: Int64(content.count),
            sha256: DirectTransferFile.sha256Hex(content),
            writeMode: .append
        )
        let descriptor = try DirectTransferPartition(
            index: 0,
            transferID: UUID(),
            sourceDates: [manifest.fileID.uuidString.lowercased()],
            byteCount: Int64(content.count),
            chunkCount: 1,
            sha256: manifest.sha256,
            previousSHA256: nil,
            itemSegment: try DirectTransferItemSegment(
                itemID: manifest.fileID.uuidString.lowercased(),
                offset: 0,
                itemByteCount: Int64(content.count),
                isFinalSegment: true
            )
        )
        let receiver = DirectFileReceiver(layout: layout, jobStore: store)
        try await receiver.prepare(request: request, accepted: accepted, session: session)
        try await receiver.store(manifest: manifest)
        _ = try await receiver.disposition(for: DirectTransferOpen(session: session, partition: descriptor))
        _ = try await receiver.receive(try DirectTransferChunk(
            transferID: descriptor.transferID,
            sequence: 1,
            data: content,
            sha256: manifest.sha256
        ))
        _ = try await receiver.commit(try DirectTransferPartitionComplete(
            sessionID: session.sessionID,
            jobID: request.jobID,
            partitionIndex: 0,
            transferID: descriptor.transferID,
            partitionSHA256: descriptor.sha256
        ))
        let resumedReceiver = DirectFileReceiver(layout: layout, jobStore: store)
        try await resumedReceiver.prepare(request: request, accepted: accepted, session: session)
        try await resumedReceiver.store(manifest: manifest)
        let replayDisposition = try await resumedReceiver.disposition(
            for: DirectTransferOpen(session: session, partition: descriptor)
        )
        XCTAssertEqual(replayDisposition.disposition, .alreadyCommitted)

        let finalization = try DirectTransferFinalize(
            sessionID: session.sessionID,
            jobID: request.jobID,
            requestFingerprint: session.requestFingerprint,
            totalPartitions: 1,
            totalBytes: Int64(content.count),
            finalPartitionSHA256: descriptor.sha256,
            outcome: try DirectExportOutcome(status: "success", successCount: 1, totalCount: 1)
        )
        let receipt = try await resumedReceiver.finalize(finalization)
        XCTAssertEqual(receipt.filesWritten, 1)
        XCTAssertEqual(String(data: try Data(contentsOf: output), encoding: .utf8), "old\n\nnew")
        _ = try await resumedReceiver.finalize(finalization)
        XCTAssertEqual(String(data: try Data(contentsOf: output), encoding: .utf8), "old\n\nnew")

        let unsafe = try DirectExportFileManifest(
            jobID: request.jobID,
            fileID: UUID(),
            relativePath: "../escape.json",
            byteCount: 0,
            sha256: DirectTransferFile.sha256Hex(Data()),
            writeMode: .overwrite
        )
        do {
            try await receiver.store(manifest: unsafe)
            XCTFail("Expected traversal rejection")
        } catch DirectFileReceiverError.unsafeRelativePath {
            // Expected.
        }

        let outside = root.appendingPathComponent("outside.md")
        try Data("outside".utf8).write(to: outside)
        try FileManager.default.removeItem(at: output)
        try FileManager.default.createSymbolicLink(at: output, withDestinationURL: outside)
        let symlinkRequest = DirectExportRequest(
            jobID: UUID(),
            createdAt: Date(),
            dateSelection: .exact(start: "2026-07-01", end: "2026-07-01"),
            responseMode: .writeFiles,
            destination: DirectExportDestination(rootPath: destination.standardizedFileURL.path)
        )
        try await store.save(try DirectJobRecord(
            request: symlinkRequest,
            createdAt: symlinkRequest.createdAt
        ))
        let symlinkAccepted = DirectExportAccepted(
            jobID: symlinkRequest.jobID,
            acceptedAt: Date(),
            peerBinding: binding,
            resolvedDateIdentifiers: ["2026-07-01"]
        )
        let symlinkSession = try DirectTransferSession(
            sessionID: UUID(),
            jobID: symlinkRequest.jobID,
            requestFingerprint: try DirectRequestFingerprint.make(for: symlinkRequest),
            peerBinding: binding,
            partitionTargetBytes: DirectTransferLimits.minimumPartitionBytes,
            createdAt: Date()
        )
        let symlinkManifest = try DirectExportFileManifest(
            jobID: symlinkRequest.jobID,
            fileID: UUID(),
            relativePath: "Health/daily.md",
            byteCount: Int64(content.count),
            sha256: DirectTransferFile.sha256Hex(content),
            writeMode: .overwrite
        )
        let symlinkReceiver = DirectFileReceiver(layout: layout, jobStore: store)
        try await symlinkReceiver.prepare(
            request: symlinkRequest,
            accepted: symlinkAccepted,
            session: symlinkSession
        )
        try await symlinkReceiver.store(manifest: symlinkManifest)
        let symlinkItemID = symlinkManifest.fileID.uuidString.lowercased()
        let symlinkPartition = try DirectTransferPartition(
            index: 0,
            transferID: UUID(),
            sourceDates: [symlinkItemID],
            byteCount: Int64(content.count),
            chunkCount: 1,
            sha256: DirectTransferFile.sha256Hex(content),
            previousSHA256: nil,
            itemSegment: try DirectTransferItemSegment(
                itemID: symlinkItemID,
                offset: 0,
                itemByteCount: Int64(content.count),
                isFinalSegment: true
            )
        )
        _ = try await symlinkReceiver.disposition(for: DirectTransferOpen(
            session: symlinkSession,
            partition: symlinkPartition
        ))
        _ = try await symlinkReceiver.receive(try DirectTransferChunk(
            transferID: symlinkPartition.transferID,
            sequence: 1,
            data: content,
            sha256: symlinkPartition.sha256
        ))
        _ = try await symlinkReceiver.commit(try DirectTransferPartitionComplete(
            sessionID: symlinkSession.sessionID,
            jobID: symlinkRequest.jobID,
            partitionIndex: 0,
            transferID: symlinkPartition.transferID,
            partitionSHA256: symlinkPartition.sha256
        ))
        do {
            _ = try await symlinkReceiver.finalize(try DirectTransferFinalize(
                sessionID: symlinkSession.sessionID,
                jobID: symlinkRequest.jobID,
                requestFingerprint: symlinkSession.requestFingerprint,
                totalPartitions: 1,
                totalBytes: Int64(content.count),
                finalPartitionSHA256: symlinkPartition.sha256,
                outcome: try DirectExportOutcome(
                    status: "success",
                    successCount: 1,
                    totalCount: 1
                )
            ))
            XCTFail("Expected existing symlink rejection")
        } catch DirectFileReceiverError.destinationConflict {
            // Expected: existing destination entries are opened relative to the root with O_NOFOLLOW.
        }
        XCTAssertEqual(String(data: try Data(contentsOf: outside), encoding: .utf8), "outside")

        try FileManager.default.removeItem(at: destination)
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        do {
            try await DirectFileReceiver(layout: layout, jobStore: store).prepare(
                request: request,
                accepted: accepted,
                session: session
            )
            XCTFail("Expected replacement destination identity rejection")
        } catch DirectFileReceiverError.requestChanged {
            // Expected.
        }
    }

    func testDirectFileReceiverMergesMarkdownExactlyOnceAndRejectsAmbiguousYAML() async throws {
        let preserving = try await preparedMarkdownTransfer(
            existing: "---\ndate: old\ntags:\n  - daily-notes\n---\nUser body without final newline",
            generated: "---\ndate: new\nsteps: 42\n---\n",
            writeMode: .mergeMarkdownPreservingPreamble
        )
        defer {
            try? FileManager.default.removeItem(at: preserving.storageRoot)
            try? FileManager.default.removeItem(at: preserving.destinationRoot)
        }
        let preservingReceipt = try await preserving.receiver.finalize(preserving.finalization)
        XCTAssertEqual(preservingReceipt.filesWritten, 1)
        let preservingExpected = "---\ndate: new\ntags:\n  - daily-notes\nsteps: 42\n---\nUser body without final newline"
        XCTAssertEqual(try String(contentsOf: preserving.output, encoding: .utf8), preservingExpected)
        _ = try await preserving.receiver.finalize(preserving.finalization)
        XCTAssertEqual(try String(contentsOf: preserving.output, encoding: .utf8), preservingExpected)

        let updating = try await preparedMarkdownTransfer(
            existing: "---\nnotes: \"first\nsteps: literal\"\nkeep: unchanged\n---\n# Old title",
            generated: "---\nsteps: 42\n---\n# New title",
            writeMode: .mergeMarkdown
        )
        defer {
            try? FileManager.default.removeItem(at: updating.storageRoot)
            try? FileManager.default.removeItem(at: updating.destinationRoot)
        }
        _ = try await updating.receiver.finalize(updating.finalization)
        XCTAssertEqual(
            try String(contentsOf: updating.output, encoding: .utf8),
            "---\nnotes: \"first\nsteps: literal\"\nkeep: unchanged\nsteps: 42\n---\n# New title"
        )

        let rejectedExisting = "---\n? \"steps\"\n: 100\nkeep: unchanged\n---\nBody"
        let rejected = try await preparedMarkdownTransfer(
            existing: rejectedExisting,
            generated: "---\nsteps: 42\n---\n",
            writeMode: .mergeMarkdownPreservingPreamble
        )
        defer {
            try? FileManager.default.removeItem(at: rejected.storageRoot)
            try? FileManager.default.removeItem(at: rejected.destinationRoot)
        }
        do {
            _ = try await rejected.receiver.finalize(rejected.finalization)
            XCTFail("Expected ambiguous YAML rejection")
        } catch DirectFileReceiverError.destinationConflict(let path) {
            XCTAssertEqual(path, "Health/daily.md")
        }
        XCTAssertEqual(try String(contentsOf: rejected.output, encoding: .utf8), rejectedExisting)
    }

    func testDirectRawReceiverCommitsResumesAndAssemblesWithoutCorpusMemory() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = try DirectClientStorageLayout(rootURL: root)
        let store = try DirectJobStore(layout: layout)
        let sourceID = UUID()
        let destinationID = UUID()
        let request = DirectExportRequest(
            jobID: UUID(),
            createdAt: Date(),
            dateSelection: .exact(start: "2026-07-01", end: "2026-07-01"),
            responseMode: .rawJSON,
            rawProfile: .canonicalSourceRecordsV1
        )
        try await store.save(try DirectJobRecord(request: request, createdAt: request.createdAt))
        let binding = DirectPeerBinding(
            sourceInstallationID: sourceID,
            destinationInstallationID: destinationID
        )
        let accepted = DirectExportAccepted(
            jobID: request.jobID,
            acceptedAt: request.createdAt,
            peerBinding: binding,
            resolvedDateIdentifiers: ["2026-07-01"],
            sourceDeviceName: "Test iPhone",
            sourceTimeZoneIdentifier: "UTC"
        )
        let session = try DirectTransferSession(
            sessionID: UUID(),
            jobID: request.jobID,
            requestFingerprint: try DirectRequestFingerprint.make(for: request),
            peerBinding: binding,
            partitionTargetBytes: DirectTransferLimits.minimumPartitionBytes,
            createdAt: request.createdAt
        )
        let healthData = try JSONSerialization.data(withJSONObject: [
            "schema": "healthmd.health_data",
            "schema_version": 7,
            "time_context": ["calendar_time_zone_identifier": "UTC"],
            "healthkit_record_archive": [
                "schema": "healthmd.healthkit_records",
                "schema_version": 1
            ]
        ], options: [.sortedKeys])
        let manifest = try DirectRawDayManifest(
            jobID: request.jobID,
            date: "2026-07-01",
            status: "complete",
            captureStatus: "complete",
            sampleCount: 1,
            recordCount: 1,
            queryStatusCounts: [
                "success": 1, "failure": 0, "unsupported": 0,
                "skipped": 0, "cancelled": 0
            ],
            integrityWarningCount: 0,
            integrityWarningCodes: [],
            partialFailureCount: 0,
            partialFailureTypes: [],
            healthDataByteCount: Int64(healthData.count),
            healthDataSHA256: DirectTransferFile.sha256Hex(healthData)
        )
        let descriptor = try DirectTransferPartition(
            index: 0,
            transferID: UUID(),
            sourceDates: [manifest.date],
            byteCount: Int64(healthData.count),
            chunkCount: 1,
            sha256: DirectTransferFile.sha256Hex(healthData),
            previousSHA256: nil,
            itemSegment: try DirectTransferItemSegment(
                itemID: manifest.date,
                offset: 0,
                itemByteCount: Int64(healthData.count),
                isFinalSegment: true
            )
        )
        let open = try DirectTransferOpen(session: session, partition: descriptor)
        let receiver = DirectRawReceiver(layout: layout, jobStore: store)
        try await receiver.prepare(request: request, accepted: accepted, session: session)
        try await receiver.store(manifest: manifest)
        let needed = try await receiver.disposition(for: open)
        XCTAssertEqual(needed.disposition, .needed)
        let chunk = try DirectTransferChunk(
            transferID: descriptor.transferID,
            sequence: 1,
            data: healthData,
            sha256: DirectTransferFile.sha256Hex(healthData)
        )
        let chunkAcknowledgement = try await receiver.receive(chunk)
        XCTAssertTrue(chunkAcknowledgement.accepted)
        let completed = try DirectTransferPartitionComplete(
            sessionID: session.sessionID,
            jobID: request.jobID,
            partitionIndex: 0,
            transferID: descriptor.transferID,
            partitionSHA256: descriptor.sha256
        )
        let partitionAcknowledgement = try await receiver.commit(completed)
        XCTAssertTrue(partitionAcknowledgement.accepted)

        let resumed = DirectRawReceiver(layout: layout, jobStore: store)
        try await resumed.prepare(request: request, accepted: accepted, session: session)
        try await resumed.store(manifest: manifest)
        let resumedDisposition = try await resumed.disposition(for: open)
        XCTAssertEqual(resumedDisposition.disposition, .alreadyCommitted)
        let artifact = try await resumed.finalize(try DirectTransferFinalize(
            sessionID: session.sessionID,
            jobID: request.jobID,
            requestFingerprint: session.requestFingerprint,
            totalPartitions: 1,
            totalBytes: Int64(healthData.count),
            finalPartitionSHA256: descriptor.sha256
        ))
        XCTAssertEqual(artifact.status, "success")
        XCTAssertEqual(artifact.totalDays, 1)
        XCTAssertEqual(try DirectTransferFile.inspect(artifact.fileURL).sha256, artifact.sha256)
        let response = try XCTUnwrap(
            try JSONSerialization.jsonObject(with: Data(contentsOf: artifact.fileURL)) as? [String: Any]
        )
        let raw = try XCTUnwrap(response["raw_result"] as? [String: Any])
        let days = try XCTUnwrap(raw["days"] as? [[String: Any]])
        XCTAssertEqual(days.first?["date"] as? String, "2026-07-01")
        XCTAssertNotNil(days.first?["health_data"] as? [String: Any])
        XCTAssertEqual(posixPermissions(at: artifact.fileURL), 0o600)
        let awaitingRecord = try await store.load(jobID: request.jobID)
        XCTAssertEqual(awaitingRecord.state, .awaitingPeerAcknowledgement)
        try await resumed.acknowledgePeerCompletion(jobID: request.jobID)
        let acknowledgedRecord = try await store.load(jobID: request.jobID)
        XCTAssertEqual(acknowledgedRecord.state, .completed)
    }

    func testDirectRawReceiverRejectsTamperedChunksBeforeCommit() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = try DirectClientStorageLayout(rootURL: root)
        let store = try DirectJobStore(layout: layout)
        let request = DirectExportRequest(
            jobID: UUID(),
            createdAt: Date(),
            dateSelection: .exact(start: "2026-07-01", end: "2026-07-01"),
            responseMode: .rawJSON,
            rawProfile: .canonicalSourceRecordsV1
        )
        try await store.save(try DirectJobRecord(request: request, createdAt: request.createdAt))
        let binding = DirectPeerBinding(sourceInstallationID: UUID(), destinationInstallationID: UUID())
        let accepted = DirectExportAccepted(
            jobID: request.jobID,
            acceptedAt: Date(),
            peerBinding: binding,
            resolvedDateIdentifiers: ["2026-07-01"]
        )
        let session = try DirectTransferSession(
            sessionID: UUID(),
            jobID: request.jobID,
            requestFingerprint: try DirectRequestFingerprint.make(for: request),
            peerBinding: binding,
            partitionTargetBytes: DirectTransferLimits.minimumPartitionBytes,
            createdAt: Date()
        )
        let expected = Data("{}".utf8)
        let manifest = try DirectRawDayManifest(
            jobID: request.jobID,
            date: "2026-07-01",
            status: "complete",
            sampleCount: 0,
            recordCount: 0,
            queryStatusCounts: [:],
            integrityWarningCount: 0,
            integrityWarningCodes: [],
            partialFailureCount: 0,
            partialFailureTypes: [],
            healthDataByteCount: Int64(expected.count),
            healthDataSHA256: DirectTransferFile.sha256Hex(expected)
        )
        let descriptor = try DirectTransferPartition(
            index: 0,
            transferID: UUID(),
            sourceDates: [manifest.date],
            byteCount: Int64(expected.count),
            chunkCount: 1,
            sha256: DirectTransferFile.sha256Hex(expected),
            previousSHA256: nil,
            itemSegment: try DirectTransferItemSegment(
                itemID: manifest.date,
                offset: 0,
                itemByteCount: Int64(expected.count),
                isFinalSegment: true
            )
        )
        let receiver = DirectRawReceiver(layout: layout, jobStore: store)
        try await receiver.prepare(request: request, accepted: accepted, session: session)
        try await receiver.store(manifest: manifest)
        _ = try await receiver.disposition(for: DirectTransferOpen(session: session, partition: descriptor))
        let tampered = try DirectTransferChunk(
            transferID: descriptor.transferID,
            sequence: 1,
            data: Data("[]".utf8),
            sha256: DirectTransferFile.sha256Hex(expected)
        )
        do {
            _ = try await receiver.receive(tampered)
            XCTFail("Expected chunk digest rejection")
        } catch DirectRawReceiverError.invalidChunk {
            // Expected.
        }
    }

    func testExpiredJobLoadDeletesDurableSpools() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = try DirectClientStorageLayout(rootURL: root)
        let store = try DirectJobStore(layout: layout)
        let createdAt = Date().addingTimeInterval(-HealthMdDirectProtocol.jobLifetime - 1)
        let request = DirectExportRequest(
            jobID: UUID(),
            createdAt: createdAt,
            dateSelection: .exact(start: "2026-07-01", end: "2026-07-01"),
            responseMode: .rawJSON,
            rawProfile: .canonicalSourceRecordsV1
        )
        try await store.save(try DirectJobRecord(
            request: request,
            createdAt: request.createdAt
        ))
        let corpus = layout.corpusSessionsURL.appendingPathComponent(
            request.jobID.uuidString.lowercased(),
            isDirectory: true
        )
        let response = layout.responseSpoolsURL.appendingPathComponent(
            request.jobID.uuidString.lowercased(),
            isDirectory: true
        )
        try FileManager.default.createDirectory(at: corpus, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: response, withIntermediateDirectories: true)
        do {
            _ = try await store.load(jobID: request.jobID)
            XCTFail("Expected fixed expiry enforcement")
        } catch DirectClientStorageError.jobExpired {
            // Expected.
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: corpus.path))
        XCTAssertFalse(FileManager.default.fileExists(atPath: response.path))
    }

    func testDurableJobKeepsFixedExpiryAndRoundTrips() async throws {
        let root = temporaryRoot()
        defer { try? FileManager.default.removeItem(at: root) }
        let layout = try DirectClientStorageLayout(rootURL: root)
        let store = try DirectJobStore(layout: layout)
        let createdAt = Date(timeIntervalSince1970: floor(Date().timeIntervalSince1970))
        let request = DirectExportRequest(
            jobID: UUID(),
            createdAt: createdAt,
            dateSelection: .exact(start: "2026-07-01", end: "2026-07-07"),
            responseMode: .rawJSON,
            rawProfile: .canonicalSourceRecordsV1
        )
        var record = try DirectJobRecord(request: request, createdAt: createdAt)
        record.state = .transferring
        record.updatedAt = createdAt.addingTimeInterval(1_000)
        record.committedPartitions = 2
        record.committedBytes = 96 * 1_024 * 1_024
        try await store.save(record)

        let restored = try await store.load(jobID: request.jobID)
        XCTAssertEqual(restored, record)
        XCTAssertEqual(
            restored.expiresAt,
            createdAt.addingTimeInterval(HealthMdDirectProtocol.jobLifetime)
        )
        XCTAssertEqual(
            posixPermissions(
                at: layout.jobsURL
                    .appendingPathComponent(request.jobID.uuidString.lowercased())
                    .appendingPathComponent("record.json")
            ),
            0o600
        )

        let notYetExpired = try await store.removeExpired(
            now: restored.expiresAt.addingTimeInterval(-1)
        )
        XCTAssertEqual(notYetExpired, [])
        let expired = try await store.removeExpired(now: restored.expiresAt)
        XCTAssertEqual(expired, [request.jobID])
        do {
            _ = try await store.load(jobID: request.jobID)
            XCTFail("Expected removed job")
        } catch DirectClientStorageError.jobNotFound {
            // Expected.
        }
    }

    private struct PreparedMarkdownTransfer {
        let storageRoot: URL
        let destinationRoot: URL
        let output: URL
        let receiver: DirectFileReceiver
        let finalization: DirectTransferFinalize
    }

    private func preparedMarkdownTransfer(
        existing: String,
        generated: String,
        writeMode: DirectExportFileWriteMode
    ) async throws -> PreparedMarkdownTransfer {
        let storageRoot = temporaryRoot()
        let destinationRoot = temporaryRoot()
        try FileManager.default.createDirectory(at: destinationRoot, withIntermediateDirectories: true)
        let healthFolder = destinationRoot.appendingPathComponent("Health", isDirectory: true)
        try FileManager.default.createDirectory(at: healthFolder, withIntermediateDirectories: true)
        let output = healthFolder.appendingPathComponent("daily.md")
        try Data(existing.utf8).write(to: output)

        let layout = try DirectClientStorageLayout(rootURL: storageRoot)
        let store = try DirectJobStore(layout: layout)
        let request = DirectExportRequest(
            jobID: UUID(),
            createdAt: Date(),
            dateSelection: .exact(start: "2026-07-01", end: "2026-07-01"),
            responseMode: .writeFiles,
            destination: DirectExportDestination(rootPath: destinationRoot.standardizedFileURL.path)
        )
        try await store.save(try DirectJobRecord(request: request, createdAt: request.createdAt))
        let binding = DirectPeerBinding(
            sourceInstallationID: UUID(),
            destinationInstallationID: UUID()
        )
        let accepted = DirectExportAccepted(
            jobID: request.jobID,
            acceptedAt: request.createdAt,
            peerBinding: binding,
            resolvedDateIdentifiers: ["2026-07-01"]
        )
        let session = try DirectTransferSession(
            sessionID: UUID(),
            jobID: request.jobID,
            requestFingerprint: try DirectRequestFingerprint.make(for: request),
            peerBinding: binding,
            partitionTargetBytes: DirectTransferLimits.minimumPartitionBytes,
            createdAt: request.createdAt
        )
        let content = Data(generated.utf8)
        let manifest = try DirectExportFileManifest(
            jobID: request.jobID,
            fileID: UUID(),
            relativePath: "Health/daily.md",
            byteCount: Int64(content.count),
            sha256: DirectTransferFile.sha256Hex(content),
            writeMode: writeMode
        )
        let itemID = manifest.fileID.uuidString.lowercased()
        let descriptor = try DirectTransferPartition(
            index: 0,
            transferID: UUID(),
            sourceDates: [itemID],
            byteCount: Int64(content.count),
            chunkCount: 1,
            sha256: manifest.sha256,
            previousSHA256: nil,
            itemSegment: try DirectTransferItemSegment(
                itemID: itemID,
                offset: 0,
                itemByteCount: Int64(content.count),
                isFinalSegment: true
            )
        )
        let receiver = DirectFileReceiver(layout: layout, jobStore: store)
        try await receiver.prepare(request: request, accepted: accepted, session: session)
        try await receiver.store(manifest: manifest)
        _ = try await receiver.disposition(for: DirectTransferOpen(session: session, partition: descriptor))
        _ = try await receiver.receive(try DirectTransferChunk(
            transferID: descriptor.transferID,
            sequence: 1,
            data: content,
            sha256: descriptor.sha256
        ))
        _ = try await receiver.commit(try DirectTransferPartitionComplete(
            sessionID: session.sessionID,
            jobID: request.jobID,
            partitionIndex: 0,
            transferID: descriptor.transferID,
            partitionSHA256: descriptor.sha256
        ))
        let finalization = try DirectTransferFinalize(
            sessionID: session.sessionID,
            jobID: request.jobID,
            requestFingerprint: session.requestFingerprint,
            totalPartitions: 1,
            totalBytes: Int64(content.count),
            finalPartitionSHA256: descriptor.sha256,
            outcome: try DirectExportOutcome(status: "success", successCount: 1, totalCount: 1)
        )
        return PreparedMarkdownTransfer(
            storageRoot: storageRoot,
            destinationRoot: destinationRoot,
            output: output,
            receiver: receiver,
            finalization: finalization
        )
    }

    private func unusedLoopbackPort() throws -> UInt16 {
        let descriptor = socket(AF_INET, SOCK_STREAM, 0)
        guard descriptor >= 0 else { throw POSIXError(.EIO) }
        defer { close(descriptor) }
        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let result = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(descriptor, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard result == 0 else { throw POSIXError(.EADDRINUSE) }
        var bound = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let readResult = withUnsafeMutablePointer(to: &bound) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(descriptor, $0, &length)
            }
        }
        guard readResult == 0 else { throw POSIXError(.EIO) }
        return UInt16(bigEndian: bound.sin_port)
    }

    private func temporaryRoot() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("healthmd-direct-store-tests-\(UUID().uuidString)", isDirectory: true)
    }

    private func posixPermissions(at url: URL) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue
    }
}

private final class InMemoryManualIPTrustStore: ManualIPTrustStoring {
    private let lock = NSLock()
    private var state: ManualIPTrustState?

    func loadState(ownerInstallationID: UUID) -> ManualIPTrustState {
        lock.lock()
        defer { lock.unlock() }
        guard let state, state.ownerInstallationID == ownerInstallationID else {
            return ManualIPTrustState(ownerInstallationID: ownerInstallationID)
        }
        return state
    }

    func saveState(_ state: ManualIPTrustState) throws {
        lock.lock()
        self.state = state
        lock.unlock()
    }
}
