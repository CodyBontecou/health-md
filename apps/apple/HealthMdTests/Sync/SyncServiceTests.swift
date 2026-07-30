//
//  SyncServiceTests.swift
//  HealthMdTests
//
//  Tests for SyncService state machine, data handling, and payload routing.
//  No MultipeerConnectivity dependency — tests extracted pure logic.
//

import XCTest
import MultipeerConnectivity
@testable import HealthMd

// MARK: - State Machine Tests

final class SyncStateMachineTests: XCTestCase {

    // MARK: - State Transitions

    func testTransition_notConnected_setsDisconnected() {
        let (state, peerName, clearError) = SyncStateMachine.transition(for: .notConnected, peerName: "iPhone")
        XCTAssertEqual(state, .disconnected)
        XCTAssertNil(peerName)
        XCTAssertFalse(clearError)
    }

    func testTransition_connecting_setsConnecting() {
        let (state, peerName, _) = SyncStateMachine.transition(for: .connecting, peerName: "iPhone")
        XCTAssertEqual(state, .connecting)
        XCTAssertNil(peerName)
    }

    func testTransition_connected_setsConnectedWithPeer() {
        let (state, peerName, clearError) = SyncStateMachine.transition(for: .connected, peerName: "iPhone 15")
        XCTAssertEqual(state, .connected)
        XCTAssertEqual(peerName, "iPhone 15")
        XCTAssertTrue(clearError)
    }

    // MARK: - Disconnect During Sync

    func testShouldStopSyncing_trueWhenDisconnectedDuringSync() {
        XCTAssertTrue(SyncStateMachine.shouldStopSyncing(newState: .notConnected, isSyncing: true))
    }

    func testShouldStopSyncing_falseWhenNotSyncing() {
        XCTAssertFalse(SyncStateMachine.shouldStopSyncing(newState: .notConnected, isSyncing: false))
    }

    func testShouldStopSyncing_falseWhenConnected() {
        XCTAssertFalse(SyncStateMachine.shouldStopSyncing(newState: .connected, isSyncing: true))
    }

    // MARK: - Payload Size Routing

    func testShouldUseResourceTransfer_smallPayload() {
        let data = Data(repeating: 0, count: 1000)
        XCTAssertFalse(SyncStateMachine.shouldUseResourceTransfer(for: data))
    }

    func testShouldUseResourceTransfer_largePayload() {
        let data = Data(repeating: 0, count: 200_000)
        XCTAssertTrue(SyncStateMachine.shouldUseResourceTransfer(for: data))
    }

    func testShouldUseResourceTransfer_atThreshold() {
        let data = Data(repeating: 0, count: 100_000)
        XCTAssertFalse(SyncStateMachine.shouldUseResourceTransfer(for: data))
    }

    func testShouldUseResourceTransfer_justAboveThreshold() {
        let data = Data(repeating: 0, count: 100_001)
        XCTAssertTrue(SyncStateMachine.shouldUseResourceTransfer(for: data))
    }

    // MARK: - Connected Transfer Failure Mapping

    func testMacExportFailureReasonPreservesApplicationAndDecodePhases() {
        XCTAssertEqual(
            SyncStateMachine.macExportFailureReason(for: .applicationRejected),
            .exportWriteFailure
        )
        XCTAssertEqual(
            SyncStateMachine.macExportFailureReason(for: .decodeFailure),
            .payloadDecodeFailure
        )
        XCTAssertEqual(
            SyncStateMachine.macExportFailureReason(for: .cancelled),
            .cancelled
        )
    }

    // MARK: - Message Decode

    func testDecodeMessage_validData_returnsMessage() throws {
        let message = SyncMessage.requestAllData
        let data = try JSONEncoder().encode(message)

        let result = SyncStateMachine.decodeMessage(from: data)
        XCTAssertNotNil(result.message)
        XCTAssertNil(result.error)
    }

    func testDecodeMessage_invalidData_returnsError() {
        let data = Data("not valid json".utf8)

        let result = SyncStateMachine.decodeMessage(from: data)
        XCTAssertNil(result.message)
        XCTAssertNotNil(result.error)
        XCTAssertTrue(result.error!.hasPrefix("Decode error:"))
    }

    func testDecodeMessage_emptyData_returnsError() {
        let result = SyncStateMachine.decodeMessage(from: Data())
        XCTAssertNil(result.message)
        XCTAssertNotNil(result.error)
    }
}

// MARK: - Nearby Peer Attempt Tests

final class NearbyPeerAttemptPlannerTests: XCTestCase {

    func testStalePendingPeerFailureAdvancesToAlreadyDiscoveredLivePeer() {
        var planner = NearbyPeerAttemptPlanner<String>()

        XCTAssertTrue(planner.discover("stale"))
        XCTAssertEqual(planner.nextCandidate(), "stale")
        XCTAssertTrue(planner.discover("live"))

        XCTAssertEqual(planner.failPending("stale"), "live")
        XCTAssertEqual(planner.pendingPeer, "live")
    }

    func testSettledDiscoveryPrefersMostRecentlyReportedPeer() {
        var planner = NearbyPeerAttemptPlanner<String>()

        XCTAssertTrue(planner.discover("cached-stale"))
        XCTAssertTrue(planner.discover("current-advertiser"))

        XCTAssertEqual(planner.nextCandidate(), "current-advertiser")
    }

    func testDelayedFailureCannotDisplaceNewPendingPeer() {
        var planner = NearbyPeerAttemptPlanner<String>()
        _ = planner.discover("stale")
        _ = planner.nextCandidate()
        _ = planner.discover("live")
        XCTAssertEqual(planner.failPending("stale"), "live")

        XCTAssertNil(planner.failPending("stale"))
        XCTAssertEqual(planner.pendingPeer, "live")
    }

    func testDistinctCandidatesAreAttemptedOnlyOncePerRound() {
        var planner = NearbyPeerAttemptPlanner<String>()
        _ = planner.discover("first")
        _ = planner.discover("second")

        XCTAssertEqual(planner.nextCandidate(), "second")
        XCTAssertEqual(planner.failPending("second"), "first")
        XCTAssertNil(planner.failPending("first"))
        XCTAssertNil(planner.pendingPeer)

        XCTAssertEqual(planner.beginNewRound(), "second")
    }

    func testLosingPendingPeerAdvancesWithoutRemovingOtherIdentity() {
        var planner = NearbyPeerAttemptPlanner<String>()
        _ = planner.discover("peer-id-1")
        _ = planner.discover("peer-id-2")
        XCTAssertEqual(planner.nextCandidate(), "peer-id-2")

        XCTAssertEqual(planner.lose("peer-id-2"), "peer-id-1")
        XCTAssertEqual(planner.discoveredPeers, ["peer-id-1"])
    }

    func testSameNamedMultipeerIdentitiesRemainDistinctCandidates() {
        let first = MCPeerID(displayName: "iPhone")
        let second = MCPeerID(displayName: "iPhone")
        var planner = NearbyPeerAttemptPlanner<MCPeerID>()

        XCTAssertTrue(planner.discover(first))
        XCTAssertTrue(planner.discover(second))
        XCTAssertEqual(planner.discoveredPeers.count, 2)
        XCTAssertTrue(planner.nextCandidate()?.isEqual(second) == true)
    }
}

// MARK: - Persistent Multipeer Identity Tests

final class SyncServiceMultipeerIdentityTests: XCTestCase {

    @MainActor
    func testPersistedPeerIDIsStableAcrossLoadsAndDisplayNameChanges() {
        let suiteName = "SyncServiceMultipeerIdentityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let first = SyncService.persistedMultipeerPeerID(
            displayName: "Original iPhone",
            in: defaults
        )
        let second = SyncService.persistedMultipeerPeerID(
            displayName: "Renamed iPhone",
            in: defaults
        )

        XCTAssertTrue(first.isEqual(second))
        XCTAssertEqual(second.displayName, "Original iPhone")
        XCTAssertNotNil(defaults.data(forKey: SyncService.multipeerPeerIDDefaultsKey))
    }

    @MainActor
    func testCorruptPeerIDArchiveIsReplacedWithSecureArchive() throws {
        let suiteName = "SyncServiceMultipeerIdentityTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(Data("not an archive".utf8), forKey: SyncService.multipeerPeerIDDefaultsKey)

        let peer = SyncService.persistedMultipeerPeerID(
            displayName: "Recovered iPhone",
            in: defaults
        )
        let storedData = try XCTUnwrap(
            defaults.data(forKey: SyncService.multipeerPeerIDDefaultsKey)
        )
        let decoded = try XCTUnwrap(
            NSKeyedUnarchiver.unarchivedObject(ofClass: MCPeerID.self, from: storedData)
        )

        XCTAssertTrue(peer.isEqual(decoded))
        XCTAssertEqual(decoded.displayName, "Recovered iPhone")
    }
}

#if os(macOS)
@MainActor
final class MacConnectedCorpusAwakeCoordinatorTests: XCTestCase {
    func testPausedStatusReleasesPreparationButNotActiveTransfer() {
        let now = Date(timeIntervalSince1970: 1_000)
        var activeActivityIDs: Set<UUID> = []
        let coordinator = MacConnectedCorpusAwakeCoordinator(
            now: { now },
            beginActivity: { activeActivityIDs.insert($0) },
            endActivity: { activeActivityIDs.remove($0) }
        )
        let jobID = UUID()
        let sessionID = UUID()
        let fingerprint = ConnectedCorpusRequestFingerprint(
            sha256: String(repeating: "a", count: 64)
        )

        XCTAssertEqual(
            coordinator.handle(snapshot(
                jobID: jobID,
                sessionID: sessionID,
                fingerprint: fingerprint,
                state: .preparing,
                updatedAt: now
            )),
            .active
        )
        coordinator.beginTransfer(jobID: jobID, transferID: UUID())
        XCTAssertEqual(activeActivityIDs.count, 2)

        XCTAssertEqual(
            coordinator.handle(snapshot(
                jobID: jobID,
                sessionID: sessionID,
                fingerprint: fingerprint,
                state: .paused,
                updatedAt: now.addingTimeInterval(1)
            )),
            .inactive
        )
        XCTAssertEqual(activeActivityIDs.count, 1)

        XCTAssertTrue(coordinator.endTransfer(jobID: jobID))
        XCTAssertTrue(activeActivityIDs.isEmpty)
    }

    func testStaleAndPostTerminalStatusesCannotReactivateAssertion() {
        let now = Date(timeIntervalSince1970: 2_000)
        var activeActivityIDs: Set<UUID> = []
        let coordinator = MacConnectedCorpusAwakeCoordinator(
            now: { now },
            beginActivity: { activeActivityIDs.insert($0) },
            endActivity: { activeActivityIDs.remove($0) }
        )
        let jobID = UUID()
        let sessionID = UUID()
        let fingerprint = ConnectedCorpusRequestFingerprint(
            sha256: String(repeating: "b", count: 64)
        )

        _ = coordinator.handle(snapshot(
            jobID: jobID,
            sessionID: sessionID,
            fingerprint: fingerprint,
            state: .preparing,
            updatedAt: now
        ))
        _ = coordinator.handle(snapshot(
            jobID: jobID,
            sessionID: sessionID,
            fingerprint: fingerprint,
            state: .completed,
            updatedAt: now.addingTimeInterval(2)
        ))
        XCTAssertTrue(activeActivityIDs.isEmpty)

        XCTAssertEqual(
            coordinator.handle(snapshot(
                jobID: jobID,
                sessionID: sessionID,
                fingerprint: fingerprint,
                state: .transferring,
                updatedAt: now.addingTimeInterval(3)
            )),
            .ignored
        )
        XCTAssertTrue(activeActivityIDs.isEmpty)
    }

    private func snapshot(
        jobID: UUID,
        sessionID: UUID,
        fingerprint: ConnectedCorpusRequestFingerprint,
        state: ConnectedCorpusJobState,
        updatedAt: Date
    ) -> ConnectedCorpusProgressSnapshot {
        ConnectedCorpusProgressSnapshot(
            jobID: jobID,
            sessionID: sessionID,
            requestFingerprint: fingerprint,
            state: state,
            processedDays: 0,
            totalDays: 30,
            committedPartitionCount: 0,
            committedBytes: 0,
            currentDate: nil,
            message: nil,
            updatedAt: updatedAt,
            expiresAt: Date(timeIntervalSince1970: 10_000)
        )
    }
}
#endif
