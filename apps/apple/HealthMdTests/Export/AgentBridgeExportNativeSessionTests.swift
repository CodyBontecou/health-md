// This test surface compiles the EXACT source controller factory/admission/ownership bodies
// with explicit native-controller fixture state and SDK-only UIKit interception. It does NOT
// execute/qualify the whole iOS service, installed app, UIApplication or Keychain.
#if HEALTHMD_NATIVE_CONTROLLER_SOURCE_SEAM
import CryptoKit
import Foundation
import LocalAuthentication
import Security
import XCTest
@testable import HealthMdConnectionCore
#if canImport(AgentBridgeRequestSettingsHarness)
@testable import AgentBridgeRequestSettingsHarness
#endif

@MainActor
final class AgentBridgeExportNativeSessionTests: XCTestCase {
    func testActualAuthenticatedChannelBaseHelloOwnerAndNativeTrustProduceCurrentPeer() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let peer = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
        XCTAssertEqual(peer.peer.sourceInstallationID.rawValue, fixture.handshake.source.uuidString.lowercased())
        XCTAssertEqual(peer.peer.hostInstallationID.rawValue, fixture.handshake.host.uuidString.lowercased())
        XCTAssertNoThrow(try peer.requireCurrent())
        XCTAssertGreaterThan(fixture.trust.loads, 1)
        XCTAssertEqual(fixture.handshake.store.saves, 1)
    }

    func testSameOwnerRepeatedGetterCannotRenewOriginalSnapshotOrRevokedCopies() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let held = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
        let copy = held
        let ownership = try XCTUnwrap(fixture.service.agentBridgeSession)
        let proof = try XCTUnwrap(fixture.channel.clientAuthenticatedContext)
        let sdk = fixture.trust, reader = sdk.reader, originalBytes = sdk.bytes
        let original = try XCTUnwrap(reader.loadExistingTrust(ownerInstallationID: fixture.handshake.source))
        let repeated = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: sdk.reader)
        XCTAssertEqual(repeated.peer, held.peer)
        XCTAssertNoThrow(try repeated.requireCurrent())
        XCTAssertNoThrow(try copy.requireCurrent())
        XCTAssertTrue(fixture.service.agentBridgeSession === ownership)

        let changedBytes = originalBytes + Data("\n".utf8) // VALID full record, same authenticated credential.
        sdk.replace(changedBytes)
        XCTAssertNotEqual(sdk.bytes, originalBytes)
        let changed = try XCTUnwrap(reader.loadExistingTrust(ownerInstallationID: fixture.handshake.source))
        XCTAssertNoThrow(try proof.requireCurrent(on: fixture.channel,
            sourceInstallationID: changed.ownerInstallationID,
            hostInstallationID: changed.trustedMacInstallationID, reconnectSecret: changed.reconnectSecret))
        XCTAssertNoThrow(try ownership.requireCurrent())
        XCTAssertTrue(ownership.currentOwnerIsAvailable())
        XCTAssertTrue(UIApplication.shared.applicationState == .active)
        XCTAssertTrue(UIApplication.shared.availability.read())
        // Re-enter the ACTUAL same-owner factory BEFORE any held checker observes the change.
        XCTAssertThrowsError(try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: sdk.reader)) { error in
            XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired)
            XCTAssertEqual(String(describing: error), "permission_required")
        }
        XCTAssertThrowsError(try held.requireCurrent())
        sdk.replace(originalBytes)
        XCTAssertNotNil(try reader.loadExistingTrust(ownerInstallationID: fixture.handshake.source))
        XCTAssertNoThrow(try reader.requireCurrent(original: original,
            nativeSourceInstallationID: fixture.handshake.source,
            authenticatedHostInstallationID: fixture.handshake.host,
            originalReconnectSecret: original.reconnectSecret))
        XCTAssertThrowsError(try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: sdk.reader))
        XCTAssertThrowsError(try held.requireCurrent())
        XCTAssertThrowsError(try copy.requireCurrent())
        XCTAssertThrowsError(try repeated.requireCurrent())
        XCTAssertNoThrow(try proof.requireCurrent(on: fixture.channel)) // No new network close/reconnect.

        // A genuinely NEW cryptographic handshake and admitted owner, not a marker/ID reset,
        // can capture current matching metadata; old held contexts never rebind to it.
        let nextHandshake = NativeSessionHandshakeFixture()
        let nextChannel = try await nextHandshake.authenticate()
        XCTAssertFalse(nextChannel === fixture.channel)
        sdk.replace(changedBytes)
        fixture.service.fixtureInstall(channel: nextChannel, sessionID: UUID())
        fixture.service.fixtureHello(.init(platform: .macOSCLI, installationID: nextHandshake.host))
        XCTAssertFalse(fixture.service.agentBridgeSession === ownership)
        let fresh = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: sdk.reader)
        XCTAssertEqual(fresh.peer, held.peer) // Same identities are NOT the proof of a new owner.
        XCTAssertNoThrow(try fresh.requireCurrent())
        XCTAssertNoThrow(try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: sdk.reader).requireCurrent())
        XCTAssertThrowsError(try held.requireCurrent())
        XCTAssertThrowsError(try copy.requireCurrent())
        XCTAssertThrowsError(try repeated.requireCurrent())
        XCTAssertEqual(fixture.handshake.store.saves, 1)
        XCTAssertEqual(nextHandshake.store.saves, 1)
        let defaults = fixture.defaults as! NativeSessionEnabledDefaults
        XCTAssertEqual(defaults.exportReads, 0)
        XCTAssertEqual(defaults.exportWrites, 0)
    }

    func testOrdinaryChannelPairingOnlyAndWrongBaseHelloRejectBeforeTrustLookup() async throws {
        for kind in 0..<5 {
            let fixture = try await NativeSessionControllerFixture.make()
            fixture.service.fixtureStop()
            let channel = kind == 0 ? DirectSecureChannel(packetConnection: fixture.handshake.transport, sessionKey: fixture.channel.sessionKey,
                peerInstallationID: fixture.handshake.host, peerDisplayName: "synthetic") : fixture.channel
            fixture.service.fixtureInstall(channel: channel, sessionID: fixture.sessionID)
            if kind != 1 {
                fixture.service.fixtureHello(.init(protocolVersions: kind == 2 ? [3] : [1],
                    platform: kind == 3 ? .iOS : .macOSCLI,
                    installationID: kind == 4 ? fixture.handshake.source : fixture.handshake.host))
            }
            XCTAssertThrowsError(try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)) { error in
                XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired)
            }
            XCTAssertEqual(fixture.trust.loads, 0)
        }
    }

    func testProvisionalNativePairingCannotBecomeCommittedTrustThroughFactory() async throws {
        let fixture = try await NativeSessionControllerFixture.make(pairingCode: "12345678901234567890")
        XCTAssertThrowsError(try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader))
        let state = fixture.handshake.store.loadState(ownerInstallationID: fixture.handshake.source)
        XCTAssertNil(state.trustedMac)
        XCTAssertNotNil(state.provisionalTrustedMac)
        XCTAssertEqual(fixture.handshake.store.saves, 1)
    }

    func testWrongNativeOwnerHostOrCredentialSnapshotRejectsWithNoRepair() async throws {
        for kind in 0..<3 {
            let fixture = try await NativeSessionControllerFixture.make()
            let host = kind == 1 ? fixture.handshake.source : fixture.handshake.host
            let secret = kind == 2 ? Data(repeating: 0x42, count: 32) : fixture.handshake.secret
            let record = ManualIPTrustedMac(installationID: host, displayName: "synthetic host", host: "synthetic", port: 17647,
                reconnectSecret: secret, pairedAt: Date(timeIntervalSinceReferenceDate: 12.25))
            fixture.trust.replace(try JSONEncoder().encode(ManualIPTrustState(ownerInstallationID: kind == 0 ? fixture.handshake.host : fixture.handshake.source, trustedMac: record)))
            XCTAssertThrowsError(try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader))
            XCTAssertEqual(fixture.handshake.store.saves, 1)
        }
    }

    func testNativeSDKQueriesRemainFixedPurposeAndPromptSuppressed() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let peer = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
        try peer.requireCurrent()
        for query in fixture.trust.queries {
            XCTAssertEqual(query[kSecAttrService as String] as? String, "com.codybontecou.obsidianhealth.direct-cli-ios-trust")
            XCTAssertEqual(query[kSecAttrAccount as String] as? String, "trust-state-v1")
            XCTAssertEqual(query[kSecUseDataProtectionKeychain as String] as? Bool, true)
            XCTAssertEqual((query[kSecUseAuthenticationContext as String] as? LAContext)?.interactionNotAllowed, true)
            XCTAssertEqual(query[kSecMatchLimit as String] as? Int, 2)
        }
        XCTAssertEqual(Set(fixture.trust.contextIDs).count, fixture.trust.loads)
    }

    func testObservedTeardownCopiesAndSameIDSessionRestorationNeverRebindOldPeer() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let held = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
        let copy = held
        fixture.service.fixtureStop()
        fixture.service.fixtureInstall(channel: fixture.channel, sessionID: fixture.sessionID)
        fixture.service.fixtureHello(.init(platform: .macOSCLI, installationID: fixture.handshake.host))
        XCTAssertThrowsError(try held.requireCurrent())
        XCTAssertThrowsError(try copy.requireCurrent())
        XCTAssertNoThrow(try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader).requireCurrent())
    }

    func testReplacementChannelWithSameIdentitiesCannotRenewHeldPeer() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let held = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
        let other = NativeSessionHandshakeFixture()
        let replacement = try await other.authenticate()
        fixture.service.fixtureInstall(channel: replacement, sessionID: fixture.sessionID)
        fixture.service.fixtureHello(.init(platform: .macOSCLI, installationID: fixture.handshake.host))
        XCTAssertThrowsError(try held.requireCurrent())
        XCTAssertNoThrow(try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader).requireCurrent())
    }

    func testFactoryChecksActualOwnerSessionAndChannelNotOnlyMintedMarker() async throws {
        for kind in 0..<2 {
            let fixture = try await NativeSessionControllerFixture.make()
            let held = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
            if kind == 0 { fixture.service.activeSessionID = fixture.handshake.source }
            else {
                let replacement = NativeSessionHandshakeFixture()
                fixture.service.channel = try await replacement.authenticate()
            }
            let loads = fixture.trust.loads
            XCTAssertThrowsError(try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader))
            XCTAssertEqual(fixture.trust.loads, loads)
            fixture.service.activeSessionID = fixture.sessionID; fixture.service.channel = fixture.channel
            XCTAssertThrowsError(try held.requireCurrent())
        }
    }

    func testHeldPeerReadsActualOwningSessionAndChannelWithoutFactoryOrLifecycleEvent() async throws {
        for kind in 0..<2 {
            let fixture = try await NativeSessionControllerFixture.make()
            let peer = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
            let before = fixture.trust.loads
            if kind == 0 { fixture.service.activeSessionID = fixture.handshake.source }
            else {
                let other = NativeSessionHandshakeFixture()
                fixture.service.channel = try await other.authenticate()
            }
            XCTAssertThrowsError(try peer.requireCurrent())
            XCTAssertEqual(fixture.trust.loads, before)
            fixture.service.activeSessionID = fixture.sessionID; fixture.service.channel = fixture.channel
            XCTAssertThrowsError(try peer.requireCurrent())
        }
    }

    func testNativeOwnerDisappearanceMakesHeldPeerUnusable() async throws {
        let held: AgentBridgeExportAuthenticatedPeer
        do {
            let fixture = try await NativeSessionControllerFixture.make()
            held = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
        }
        XCTAssertThrowsError(try held.requireCurrent())
    }

    func testForegroundLossRevokesEpochEvenAfterRestoredActiveFacts() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let held = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
        fixture.service.fixtureResign()
        fixture.service.appIsActive = true
        UIApplication.shared.applicationState = .active
        XCTAssertThrowsError(try held.requireCurrent())
        XCTAssertThrowsError(try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader))
    }

    func testDefaultForegroundFactoryProbeCannotBeReplacedByOwnerBoolean() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let held = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
        UIApplication.shared.applicationState = .inactive
        XCTAssertTrue(fixture.service.appIsActive)
        XCTAssertThrowsError(try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader))
        UIApplication.shared.applicationState = .active
        XCTAssertThrowsError(try held.requireCurrent())
    }

    func testCurrentProtectedDataAndEnabledFactsRejectPermanentlyAfterObservation() async throws {
        for kind in 0..<2 {
            let fixture = try await NativeSessionControllerFixture.make()
            let held = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
            if kind == 0 { UIApplication.shared.availability.set(false) }
            else { (fixture.defaults as? NativeSessionEnabledDefaults)?.setEnabled(false) }
            XCTAssertThrowsError(try held.requireCurrent())
            UIApplication.shared.availability.set(true)
            (fixture.defaults as? NativeSessionEnabledDefaults)?.setEnabled(true)
            XCTAssertThrowsError(try held.requireCurrent())
        }
    }

    func testUnavailableProtectedDataFailsFactoryBeforePrivateLookup() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        UIApplication.shared.availability.set(false)
        XCTAssertThrowsError(try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader))
        XCTAssertEqual(fixture.trust.loads, 0)
        UIApplication.shared.availability.set(true)
    }

    func testOriginalRawTrustMetadataAndByteChangesNeverRenewHeldPeer() async throws {
        for kind in 0..<4 {
            let fixture = try await NativeSessionControllerFixture.make()
            let held = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
            let original = fixture.trust.bytes
            var state = fixture.handshake.store.loadState(ownerInstallationID: fixture.handshake.source)
            let old = try XCTUnwrap(state.trustedMac)
            if kind == 3 { fixture.trust.replace(original + Data("\n".utf8)) }
            else {
                state.trustedMac = .init(installationID: old.installationID, displayName: kind == 0 ? "changed" : old.displayName,
                    host: kind == 1 ? "changed" : old.host, port: old.port, reconnectSecret: old.reconnectSecret,
                    pairedAt: kind == 2 ? old.pairedAt.addingTimeInterval(0.125) : old.pairedAt)
                fixture.trust.replace(try JSONEncoder().encode(state))
            }
            XCTAssertThrowsError(try held.requireCurrent())
            fixture.trust.replace(original)
            XCTAssertThrowsError(try held.requireCurrent())
        }
    }

    func testNativeSDKDeniedMissingAndMalformedLookupAreSanitizedAndTerminal() async throws {
        for status in [errSecInteractionNotAllowed, errSecItemNotFound, errSecDecode] {
            let fixture = try await NativeSessionControllerFixture.make()
            let held = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
            fixture.trust.setStatus(status)
            XCTAssertThrowsError(try held.requireCurrent()) { error in
                XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired)
                XCTAssertEqual(String(describing: error), "permission_required")
            }
            fixture.trust.setStatus(errSecSuccess)
            XCTAssertThrowsError(try held.requireCurrent())
        }
    }

    func testOwnerRevocationDuringSDKLookupPreventsFactoryReturn() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let ownership = try XCTUnwrap(fixture.service.agentBridgeSession)
        fixture.trust.observeNext { ownership.revoke() }
        XCTAssertThrowsError(try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader))
        XCTAssertEqual(fixture.handshake.store.saves, 1)
    }

    func testDelayedCapturedTrustLookupCannotHideCurrentBackingMutationAtReturn() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let held = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
        let sdk = fixture.trust, original = sdk.bytes
        sdk.captureBeforeCallback = true
        sdk.observeNext { sdk.replace(original + Data("\n".utf8)) }
        XCTAssertThrowsError(try held.requireCurrent())
        sdk.replace(original)
        XCTAssertThrowsError(try held.requireCurrent())
    }

    func testAvailabilitySDKCallbackRevocationOrTrustMutationCannotPassCurrentCheck() async throws {
        for kind in 0..<2 {
            let fixture = try await NativeSessionControllerFixture.make()
            let held = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
            let ownership = try XCTUnwrap(fixture.service.agentBridgeSession), sdk = fixture.trust
            let changed = sdk.bytes + Data("\n".utf8)
            UIApplication.shared.availability.observeNext {
                if kind == 0 { ownership.revoke() } else { sdk.replace(changed) }
            }
            XCTAssertThrowsError(try held.requireCurrent())
        }
    }

    func testFinalAvailabilityCallbackTrustMutationRejectsAndRestorationCannotReviveHeldCopies() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let held = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
        let copy = held
        let ownership = try XCTUnwrap(fixture.service.agentBridgeSession)
        let sdk = fixture.trust, originalBytes = sdk.bytes
        let reader = sdk.reader
        let original = try XCTUnwrap(reader.loadExistingTrust(ownerInstallationID: fixture.handshake.source))
        let availability = UIApplication.shared.availability
        let fired = NativeSessionSDKCallbackWitness()
        let changed = originalBytes + Data("\n".utf8) // Valid record, distinct FULL raw bytes.
        sdk.captureBeforeCallback = true
        // First held-use lookup arms the second. The SECOND returns captured original bytes
        // while arming the following LAST availability callback, not an earlier callback.
        sdk.observeNext {
            sdk.observeNext {
                availability.observeNext { sdk.replace(changed); fired.record() }
            }
        }
        XCTAssertThrowsError(try held.requireCurrent()) { error in
            XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired)
            XCTAssertEqual(String(describing: error), "permission_required")
        }
        XCTAssertEqual(fired.calls, 1) // No vacuous green from removing/skipping the callback.
        XCTAssertEqual(sdk.bytes, changed)
        XCTAssertNoThrow(try ownership.requireCurrent())
        XCTAssertTrue(ownership.currentOwnerIsAvailable())
        XCTAssertTrue(UIApplication.shared.applicationState == .active)
        XCTAssertTrue(availability.read())
        let proof = try XCTUnwrap(fixture.channel.clientAuthenticatedContext)
        XCTAssertNoThrow(try proof.requireCurrent(on: fixture.channel))
        // Independent unchanged-reader control: restoration is real and matching, but the
        // ORIGINAL checker/copies stay revoked; no repeated lazy getter or renewed snapshot.
        sdk.replace(originalBytes)
        XCTAssertNotNil(try reader.loadExistingTrust(ownerInstallationID: fixture.handshake.source))
        XCTAssertNoThrow(try reader.requireCurrent(original: original,
            nativeSourceInstallationID: fixture.handshake.source,
            authenticatedHostInstallationID: fixture.handshake.host,
            originalReconnectSecret: original.reconnectSecret))
        XCTAssertThrowsError(try held.requireCurrent())
        XCTAssertThrowsError(try copy.requireCurrent())
        XCTAssertEqual(fired.calls, 1)
        XCTAssertEqual(fixture.handshake.store.saves, 1)
        let defaults = fixture.defaults as! NativeSessionEnabledDefaults
        XCTAssertEqual(defaults.exportReads, 0)
        XCTAssertEqual(defaults.exportWrites, 0)
    }

    func testProtectedDataChangeDuringTrustLookupIsRecheckedAfterSDKReturns() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let held = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
        let availability = UIApplication.shared.availability
        fixture.trust.observeNext { availability.set(false) }
        XCTAssertThrowsError(try held.requireCurrent())
        availability.set(true)
        XCTAssertThrowsError(try held.requireCurrent())
    }

    func testFreshForegroundRetreatDuringNativeLookupRejectsWithoutLifecycleCallback() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let held = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
        let availability = UIApplication.shared.availability
        fixture.trust.observeNext { availability.setForeground(false) }
        XCTAssertThrowsError(try held.requireCurrent())
        XCTAssertTrue(fixture.service.appIsActive) // No lifecycle revocation/queued callback surrogate.
        availability.setForeground(true)
        XCTAssertThrowsError(try held.requireCurrent())
    }

    func testCurrentForegroundBeforeLookupRejectsWithoutQueuedLifecycleRevocation() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let peer = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
        let before = fixture.trust.loads
        UIApplication.shared.availability.setForeground(false)
        XCTAssertThrowsError(try peer.requireCurrent())
        XCTAssertEqual(fixture.trust.loads, before)
        XCTAssertTrue(fixture.service.appIsActive)
        UIApplication.shared.availability.setForeground(true)
        XCTAssertThrowsError(try peer.requireCurrent())
    }

    func testRealNativePeerCannotInitializeIssuerOrCreateRightsWithoutSeparateHumanEvidence() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let peer = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
        let directory = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("native-session-denied-" + UUID().uuidString)
        let keys = NativeSessionIntegritySDK()
        XCTAssertThrowsError(try AgentBridgeExportAuthorityStore.createPrivateStore(at: directory, protectedKeys: keys.reader,
            authorization: NativeSessionHumanEvidence(.none)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: directory.path))
        XCTAssertEqual(keys.loads, 0)
        XCTAssertNoThrow(try peer.requireCurrent()) // Identity/protection never substitutes for initialization consent.
    }

    func testActualPeerPlanningNeedsIndependentStoredDelegationAndLeavesSettingsUntouched() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let rig = try NativeSessionPlanningFixture(controller: fixture)
        let empty = try rig.discover()
        XCTAssertTrue(empty.authorityReferences.isEmpty)
        XCTAssertEqual(try rig.error(rig.send(.planRequest(rig.request(empty)))), .approvalRequired)
        XCTAssertTrue(try rig.store.snapshot().plans.isEmpty)
        let delegation = try rig.delegation()
        XCTAssertThrowsError(try rig.store.storeNativeDelegation(delegation, expectedGeneration: rig.store.snapshot().generation,
            authorization: NativeSessionHumanEvidence(.none)))
        try rig.enroll()
        let plan = try rig.plan()
        XCTAssertEqual(plan.predictedPaths.map(\.rawValue), ["2000/2000-01-01.json", "2000/2000-01-02.json"])
        XCTAssertEqual(plan.sideEffects, .init())
        XCTAssertEqual((fixture.defaults as! NativeSessionEnabledDefaults).exportReads, 0)
        XCTAssertEqual((fixture.defaults as! NativeSessionEnabledDefaults).exportWrites, 0)
        XCTAssertEqual(try rig.store.snapshot().delegations.count, 1)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
    }

    func testActualPeerApprovalRelayCannotReplaceIndependentExactNativeDecision() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let rig = try NativeSessionPlanningFixture(controller: fixture)
        try rig.enroll()
        let plan = try rig.plan(), binding = AgentBridgeSemantics.binding(plan)
        let request = AgentBridgeApprovalRequest(binding: binding, planId: plan.planId, requestId: try nsID(103))
        XCTAssertEqual(try rig.error(rig.send(.approvalRequest(request))), .approvalRequired)
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: nsID(9),
            authenticatedPeer: rig.peer, authorization: NativeSessionHumanEvidence(.none)))
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
        try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: nsID(9), authenticatedPeer: rig.peer,
            authorization: NativeSessionHumanEvidence(.decision(plan.planId, binding)))
        guard case .approval(let result) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: rig.send(.approvalRequest(request))).payload else {
            return XCTFail("Expected existing independently stored exact decision.")
        }
        XCTAssertEqual(result.binding, binding)
        XCTAssertEqual(result.approvalId, try nsID(9))
        XCTAssertEqual(result.rights, [.exportExecute])
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 1)
    }

    func testRealOwnerTeardownDuringConfigurationPreventsPlanPublication() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let rig = try NativeSessionPlanningFixture(controller: fixture)
        try rig.enroll()
        let request = try rig.request(rig.discover())
        let generation = try rig.store.snapshot().generation
        rig.configuration.beforeReturn = { fixture.service.fixtureStop() }
        XCTAssertThrowsError(try rig.send(.planRequest(request))) { error in XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertTrue(try rig.store.snapshot().plans.isEmpty)
        XCTAssertEqual(try rig.store.snapshot().generation, generation)
        XCTAssertEqual((fixture.defaults as! NativeSessionEnabledDefaults).exportWrites, 0)
    }

    func testRealOwnerRevocationDuringHumanDecisionCannotPublishOrRelayApproval() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let rig = try NativeSessionPlanningFixture(controller: fixture)
        try rig.enroll()
        let plan = try rig.plan(), binding = AgentBridgeSemantics.binding(plan)
        let ownership = try XCTUnwrap(fixture.service.agentBridgeSession)
        let generation = try rig.store.snapshot().generation
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: nsID(9), authenticatedPeer: rig.peer,
            authorization: NativeSessionHumanEvidence(.decision(plan.planId, binding), after: { ownership.revoke() })))
        XCTAssertEqual(try rig.store.snapshot().generation, generation)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
        XCTAssertThrowsError(try rig.send(.approvalRequest(.init(binding: binding, planId: plan.planId, requestId: nsID(103)))))
    }

    func testNativeTrustMutationDuringDedicatedIntegrityLookupAfterConsentCannotPublishDecision() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let rig = try NativeSessionPlanningFixture(controller: fixture)
        try rig.enroll()
        let plan = try rig.plan(), binding = AgentBridgeSemantics.binding(plan)
        let sdk = fixture.trust, keySDK = rig.keys, changed = fixture.trust.bytes + Data("\n".utf8)
        let generation = try rig.store.snapshot().generation
        let human = NativeSessionHumanEvidence(.decision(plan.planId, binding), after: {
            keySDK.observeNext { sdk.replace(changed) }
        })
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: nsID(9), authenticatedPeer: rig.peer, authorization: human))
        XCTAssertEqual(try rig.store.snapshot().generation, generation)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
    }

    func testIndependentIssuerRevocationStillOverridesAValidCurrentNativePeer() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let rig = try NativeSessionPlanningFixture(controller: fixture)
        try rig.enroll()
        let discovery = try rig.discover(), reference = try rig.delegation().reference()
        try rig.store.revokeNativeDelegation(reference, expectedGeneration: rig.store.snapshot().generation,
            authorization: NativeSessionHumanEvidence(.revocation(reference)))
        XCTAssertNoThrow(try rig.peer.requireCurrent())
        XCTAssertTrue(try rig.discover().authorityReferences.isEmpty)
        XCTAssertEqual(try rig.error(rig.send(.planRequest(rig.request(discovery)))), .approvalRequired)
        XCTAssertTrue(try rig.store.snapshot().plans.isEmpty)
    }

    func testInvalidNativeSDKPeerDeniesPlanningBeforeConfigurationOrPrivateOutputEffects() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let rig = try NativeSessionPlanningFixture(controller: fixture)
        let before = try rig.store.snapshot().generation
        fixture.trust.setStatus(errSecInteractionNotAllowed)
        XCTAssertThrowsError(try rig.discover())
        XCTAssertEqual(rig.configuration.reads, 0)
        XCTAssertEqual((fixture.defaults as! NativeSessionEnabledDefaults).exportReads, 0)
        XCTAssertEqual((fixture.defaults as! NativeSessionEnabledDefaults).exportWrites, 0)
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertTrue(try rig.store.snapshot().plans.isEmpty)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
        // Health/provider/quota/output/wake dependencies are structurally absent from these real
        // entry points; this is not a claim from unused mock counters or installed SDK behavior.
    }

    func testUnsupportedCallerExecutorRejectsWithoutSDKLookupOrActorErasure() async throws {
        let fixture = try await NativeSessionControllerFixture.make()
        let peer = try fixture.service.agentBridgeAuthenticatedPeer(nativeTrust: fixture.trust.reader)
        let before = fixture.trust.loads
        let rejected = await Task.detached { do { try peer.requireCurrent(); return false } catch { return true } }.value
        XCTAssertTrue(rejected)
        XCTAssertEqual(fixture.trust.loads, before)
        XCTAssertThrowsError(try peer.requireCurrent()) // Unsupported observed use cannot resurrect.
    }
}


@MainActor
private final class NativeSessionControllerFixture {
    let handshake: NativeSessionHandshakeFixture
    let channel: DirectSecureChannel
    let trust: NativeSessionTrustSDK
    let defaults: UserDefaults
    let service: IPhoneDirectCLIService
    let sessionID = UUID(uuidString: "00000000-0000-4000-8000-000000000011")!
    private init(handshake: NativeSessionHandshakeFixture, channel: DirectSecureChannel) throws {
        self.handshake = handshake; self.channel = channel
        // Private in-memory defaults boundary: no user suite/settings/credential mutation.
        defaults = NativeSessionEnabledDefaults()
        trust = try NativeSessionTrustSDK(state: handshake.store.loadState(ownerInstallationID: handshake.source))
        service = IPhoneDirectCLIService(defaults: defaults, installationID: handshake.source)
        UIApplication.shared.applicationState = .active
        UIApplication.shared.availability.set(true)
        service.fixtureInstall(channel: channel, sessionID: sessionID)
        service.fixtureHello(.init(platform: .macOSCLI, installationID: handshake.host))
    }
    static func make(pairingCode: String? = nil) async throws -> NativeSessionControllerFixture {
        let handshake = NativeSessionHandshakeFixture(pairingCode: pairingCode)
        return try await .init(handshake: handshake, channel: handshake.authenticate(pairingCode: pairingCode))
    }
}

nonisolated private final class NativeSessionEnabledDefaults: UserDefaults, @unchecked Sendable {
    private let lock = NSLock()
    private var enabled = true
    private var reads = 0
    private var writes = 0
    var exportReads: Int { lock.withLock { reads } }
    var exportWrites: Int { lock.withLock { writes } }
    override func object(forKey defaultName: String) -> Any? { lock.withLock { reads += 1; return nil } }
    override func set(_ value: Any?, forKey defaultName: String) { lock.withLock { writes += 1 }; XCTFail("Unexpected settings SDK mutation.") }
    override func removeObject(forKey defaultName: String) { lock.withLock { writes += 1 }; XCTFail("Unexpected settings SDK mutation.") }
    override func bool(forKey defaultName: String) -> Bool { lock.withLock { defaultName == "directCLIEnabled" && enabled } }
    func setEnabled(_ value: Bool) { lock.withLock { enabled = value } }
}

nonisolated private final class NativeSessionSDKCallbackWitness: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    var calls: Int { lock.withLock { count } }
    func record() { lock.withLock { count += 1 } }
}

nonisolated private final class NativeSessionTrustSDK: @unchecked Sendable {
    private let lock = NSLock()
    private var raw: Data
    private var count = 0
    private var observer: (@Sendable () -> Void)?
    private var status: OSStatus = errSecSuccess
    private var captured = false
    private var recorded: [[String: Any]] = []
    var queries: [[String: Any]] { lock.withLock { recorded } }
    var contextIDs: [ObjectIdentifier] { queries.compactMap { ($0[kSecUseAuthenticationContext as String] as? LAContext).map(ObjectIdentifier.init) } }
    var bytes: Data { lock.withLock { raw } }
    var captureBeforeCallback: Bool { get { lock.withLock { captured } } set { lock.withLock { captured = newValue } } }
    func setStatus(_ value: OSStatus) { lock.withLock { status = value } }
    var loads: Int { lock.withLock { count } }
    var reader: AgentBridgeExportNativeTrust { AgentBridgeExportNativeTrust(copyMatching: { [self] in copyMatching($0, $1) }) }
    init(state: ManualIPTrustState) throws { raw = try JSONEncoder().encode(state) }
    func replace(_ data: Data) { lock.withLock { raw = data } }
    func observeNext(_ callback: @escaping @Sendable () -> Void) { lock.withLock { observer = callback } }
    private func copyMatching(_ query: CFDictionary, _ result: UnsafeMutablePointer<CFTypeRef?>?) -> OSStatus {
        let (callback, before, useCaptured, outcome) = lock.withLock {
            count += 1; recorded.append(query as! [String: Any]); let pending = observer; observer = nil
            return (pending, raw, captured, status)
        }
        callback?()
        if outcome != errSecSuccess { result?.pointee = nil; return outcome }
        let bytes = useCaptured ? before : lock.withLock { raw }
        result?.pointee = [[
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.codybontecou.obsidianhealth.direct-cli-ios-trust",
            kSecAttrAccount as String: "trust-state-v1",
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: bytes
        ]] as CFArray
        return errSecSuccess
    }
}

nonisolated private func nsID(_ n: Int) throws -> AgentBridgeUUID {
    try AgentBridgeUUID(String(format: "00000000-0000-4000-8000-%012x", n))
}
nonisolated private struct NativeSessionPlanningClock: AgentBridgeExportClock {
    func now() -> Date { Date(timeIntervalSince1970: 946857600) } // Fixed synthetic configuration time, not health data.
}
nonisolated private struct NativeSessionHumanEvidence: AgentBridgeExportNativeAuthorizing {
    enum Evidence {
        case none, initialization, enrollment(AgentBridgeExportDelegation), revocation(AgentBridgeAuthorityReference)
        case decision(AgentBridgeUUID, AgentBridgeBinding)
    }
    let evidence: Evidence
    let after: (@Sendable () -> Void)?
    init(_ evidence: Evidence, after: (@Sendable () -> Void)? = nil) { self.evidence = evidence; self.after = after }
    func requireNativeAuthorization(for action: AgentBridgeExportNativeAction) throws {
        switch (evidence, action) {
        case (.initialization, .createPrivateStore): break
        case (.enrollment(let expected), .storeDelegation(let actual)) where expected == actual: break
        case (.revocation(let expected), .revokeDelegation(let actual)) where expected == actual: break
        case (.decision(let expectedID, let expected), .decideExport(let actualID, let actual)) where expectedID == actualID && expected == actual: break
        default: throw AgentBridgeValidationError.permissionRequired
        }
        after?() // Separate native human evidence; no wire request/annotation can supply it.
    }
}

nonisolated private final class NativeSessionIntegritySDK: @unchecked Sendable {
    private let lock = NSLock()
    private var count = 0
    private var next: (@Sendable () -> Void)?
    var loads: Int { lock.withLock { count } }
    var reader: AgentBridgeExportProtectedKey { AgentBridgeExportProtectedKey(copyMatching: { [self] _, result in
        let callback = lock.withLock { count += 1; let pending = next; next = nil; return pending }
        callback?()
        result?.pointee = [[
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: "com.codybontecou.obsidianhealth.agent-bridge.native-export-authority",
            kSecAttrAccount as String: "integrity-key-v1",
            kSecAttrAccessible as String: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
            kSecAttrSynchronizable as String: false,
            kSecValueData as String: Data(repeating: 0x7e, count: 32)
        ]] as CFArray
        return errSecSuccess
    }) }
    func observeNext(_ callback: @escaping @Sendable () -> Void) { lock.withLock { next = callback } }
}

@MainActor
private final class NativeSessionPlanningConfiguration: AgentBridgeExportPlanningConfigurationReading {
    var beforeReturn: (() -> Void)?
    var reads = 0
    func readConfiguration(for peer: AgentBridgeExportAuthenticatedPeer, policy: AgentBridgeSettingsPolicy?) throws -> AgentBridgeExportPlanningConfiguration {
        reads += 1; beforeReturn?()
        // Synthetic external native configuration input. Real resolver/registry/store/planner run.
        return try .init(inputs: .init(catalog: .init(registry: HealthMdCoreRegistryAdapter.appleSnapshot(), availableNativeMetricIDs: ["steps"], revision: 1), savedDevice: nil, profiles: []),
            deviceSettingsObjectID: nsID(5), sourceCalendarTimezone: AgentBridgeZone("UTC"), configurationProtection: .locked,
            nativeGrants: .satisfied, entitlement: .satisfied, foregroundAvailable: true, protectedDataAvailable: true)
    }
}

@MainActor
private final class NativeSessionPlanningFixture {
    let controller: NativeSessionControllerFixture
    let peer: AgentBridgeExportAuthenticatedPeer
    let keys = NativeSessionIntegritySDK()
    let store: AgentBridgeExportAuthorityStore
    let configuration = NativeSessionPlanningConfiguration()
    let service: AgentBridgeExportPlanningService
    init(controller: NativeSessionControllerFixture) throws {
        self.controller = controller
        peer = try controller.service.agentBridgeAuthenticatedPeer(nativeTrust: controller.trust.reader)
        let parent = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("native-session-private-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        store = try AgentBridgeExportAuthorityStore.createPrivateStore(at: parent.appendingPathComponent("authority"), protectedKeys: keys.reader,
            authorization: NativeSessionHumanEvidence(.initialization))
        service = AgentBridgeExportPlanningService(store: store, configuration: configuration, clock: NativeSessionPlanningClock(), newPlanID: { try nsID(6) })
    }
    func delegation() throws -> AgentBridgeExportDelegation {
        try .init(authorityID: nsID(7), issuer: .nativeSource, grantRevision: 1, peer: peer.peer,
            rights: [.discover, .exportExecute, .plan], expiresAt: AgentBridgeUTC("2000-01-03T02:00:00Z"),
            bounds: .init(products: [.generatedFiles], projectionDetails: [], projectionObjectIDs: [], projectionFieldIDs: [], metricIDs: [AgentBridgeID("steps")],
                calendarTimezones: [AgentBridgeZone("UTC")], datePolicy: .authorizedHistory(maxDays: 366, allowAllAvailable: true), formats: [.json], outputProfiles: [.appleV8],
                writeModes: [.overwrite], compatibilityDetail: [.summary], nativeArchiveProducts: [.none], destinationPolicy: .authenticatedHostBindings))
    }
    func enroll() throws {
        let value = try delegation()
        try store.storeNativeDelegation(value, expectedGeneration: store.snapshot().generation, authorization: NativeSessionHumanEvidence(.enrollment(value)))
    }
    func send(_ document: AgentBridgeDocument) throws -> Data {
        try service.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: document)), authenticatedPeer: peer)
    }
    func error(_ bytes: Data) throws -> AgentBridgeErrorCode {
        guard case .error(let result) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes).payload else { throw AgentBridgeValidationError.invalidRequest }
        return result.code
    }
    func discover() throws -> AgentBridgeDiscovery {
        guard case .discovery(let result) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: send(.discoveryRequest(.init(requestID: nsID(100), peer: peer.peer)))).payload else {
            throw AgentBridgeValidationError.invalidRequest
        }
        return result
    }
    func request(_ discovery: AgentBridgeDiscovery) throws -> AgentBridgePlanRequest {
        let destination = try AgentBridgeDestination(bindingID: nsID(3), identitySHA256: AgentBridgeDigest(String(repeating: "1", count: 64)), revision: 1, hostInstallationID: peer.peer.hostInstallationID)
        let intent = try AgentBridgeGeneratedIntent(intentID: nsID(4), peer: peer.peer, destination: destination,
            dates: .exact(.init(startDate: AgentBridgeDate("2000-01-01"), endDate: AgentBridgeDate("2000-01-02"))), calendarTimezone: AgentBridgeZone("UTC"),
            captureScope: .init(selection: .init(metricIDs: [AgentBridgeID("steps")], categoryIDs: [], sourceIDs: [AgentBridgeID("apple_health")], providerIDs: [], allMetrics: false), compatibilityDetail: .summary, nativeArchive: .none),
            settingsPolicy: .explicit(AgentBridgeExportPlanningService.defaultOutput))
        return try .init(authorityId: nsID(7), authorityRevision: 1, capabilitySha256: discovery.capabilitySha256,
            hostAuthorityReference: .init(authorityId: nsID(13), grantRevision: 1, grantSha256: AgentBridgeDigest(String(repeating: "2", count: 64)), issuer: .authorizedHost), intent: intent, requestId: nsID(101))
    }
    func plan() throws -> AgentBridgePlan {
        guard case .plan(let result) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: send(.planRequest(request(discover())))).payload else {
            throw AgentBridgeValidationError.invalidRequest
        }
        return result
    }
}
#endif
