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
