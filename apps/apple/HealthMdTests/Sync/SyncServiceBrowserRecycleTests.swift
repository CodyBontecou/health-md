//
//  SyncServiceBrowserRecycleTests.swift
//  HealthMdTests
//
//  After an unanswered invitation, a dropped iPhone or a resumed receiver, the Mac replaces its
//  nearby browser and (while idle) its peer ID: MultipeerConnectivity could replay an already
//  timed-out invitation to the re-advertising iPhone, which then ignored that Mac peer until the
//  Mac app was relaunched.
//

import XCTest
@testable import HealthMd

final class NearbyBrowserReplacementPlannerTests: XCTestCase {

    func testAbandonedInvitationDoesNotStartAnotherOne() {
        var planner = NearbyPeerAttemptPlanner<String>()
        _ = planner.discover("first")
        _ = planner.discover("second")
        XCTAssertEqual(planner.nextCandidate(), "second")

        XCTAssertTrue(planner.abandonPending("second"))
        XCTAssertNil(planner.pendingPeer, "the replacement browser chooses the next peer")
        XCTAssertFalse(planner.abandonPending("second"), "a late callback is ignored")
    }

    func testReplacedBrowserKeepsFailedPeerBehindOtherCandidates() {
        var planner = NearbyPeerAttemptPlanner<String>()
        _ = planner.discover("other")
        _ = planner.discover("failed")
        XCTAssertEqual(planner.nextCandidate(), "failed")
        XCTAssertTrue(planner.abandonPending("failed"))

        planner.browserReplaced()
        XCTAssertTrue(planner.discoveredPeers.isEmpty)

        // The new browser reports both again, the failed peer last.
        XCTAssertTrue(planner.discover("other"))
        XCTAssertTrue(planner.discover("failed"))
        XCTAssertEqual(planner.nextCandidate(), "other")
    }

    func testDisconnectedActivePeerWaitsForNextRound() {
        var planner = NearbyPeerAttemptPlanner<String>()
        _ = planner.discover("iphone")
        _ = planner.nextCandidate()
        planner.connected("iphone")

        planner.activePeerDisconnected("iphone")
        planner.browserReplaced()
        XCTAssertTrue(planner.discover("iphone"))

        XCTAssertNil(planner.nextCandidate(), "retried by the backoff round, not immediately")
        XCTAssertEqual(planner.beginNewRound(), "iphone")
    }
}

@MainActor
final class SyncServiceBrowserRecycleTests: XCTestCase {

    func testRecycleReplacesBrowserAndForgetsItsPeers() {
        let sync = SyncService()
        sync.startBrowsing()
        defer { sync.stopBrowsing() }
        let generation = sync.nearbyBrowserGeneration

        sync.recycleNearbyBrowser(reason: "test")

        XCTAssertEqual(sync.nearbyBrowserGeneration, generation + 1)
        XCTAssertTrue(sync.discoveredPeers.isEmpty)
        #if os(macOS)
        XCTAssertEqual(sync.nearbyIdentityGeneration, 1, "an idle Mac also takes a fresh peer ID")
        #endif
    }

    #if os(macOS)
    func testResumedBrowsingUsesFreshIdentity() {
        let sync = SyncService()
        sync.startBrowsing()
        XCTAssertEqual(sync.nearbyIdentityGeneration, 0, "the first browse keeps the launch identity")

        sync.stopBrowsing()
        sync.startBrowsing()
        defer { sync.stopBrowsing() }

        XCTAssertEqual(sync.nearbyIdentityGeneration, 1)
    }
    #endif

    func testRecycleIsNoOpWhenNotBrowsing() {
        let sync = SyncService()
        let generation = sync.nearbyBrowserGeneration

        sync.recycleNearbyBrowser(reason: "test")

        XCTAssertEqual(sync.nearbyBrowserGeneration, generation)
    }
}
