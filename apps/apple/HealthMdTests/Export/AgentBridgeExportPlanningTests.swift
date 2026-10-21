import CryptoKit
import Darwin
import Foundation
import HealthMdConnectionCore
import HealthMdCoreRust
import XCTest
#if canImport(HealthMd)
import HealthKit
@testable import HealthMd
#else
@testable import AgentBridgeRequestSettingsHarness
#endif

@MainActor
final class AgentBridgeExportPlanningTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: existing native settings/store tests retain Combine and
    // MainActor objects through process teardown on older iOS runtimes; these use the same owners.
    private static var retainedNativeConfigurationObjects: [AnyObject] = []

    private func nativeState(
        available: Set<String> = ["steps", "heart_rate_avg", "heart_rate_min", "heart_rate_max", "resting_heart_rate", "hrv"],
        zone: String = "America/Los_Angeles", protection: AgentBridgeDiscoveryConfigurationProtection = .locked,
        grants: AgentBridgeDiscoveryNativeGrants = .satisfied, entitlement: AgentBridgeDiscoveryEntitlement = .satisfied,
        foregroundAvailable: Bool = true, protectedDataAvailable: Bool = true
    ) throws -> AgentBridgeNativePlanningFacts {
        try .init(availableNativeMetricIDs: available, sourceCalendarTimezone: AgentBridgeZone(zone), configurationProtection: protection,
                  nativeGrants: grants, entitlement: entitlement, foregroundAvailable: foregroundAvailable, protectedDataAvailable: protectedDataAvailable)
    }

    private func executionRequest(_ rig: Rig, storeDecision: Bool = true, policy: AgentBridgeSettingsPolicy? = nil) throws -> AgentBridgeExecute {
        let plan = try rig.makePlan(policy: policy)
        let binding = try AgentBridgeSemantics.binding(plan)
        if storeDecision {
            try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8),
                authenticatedPeer: rig.peer, authorization: FakeNativeAuthorization(binding: binding))
        }
        let approval = AgentBridgeApproval(approvalId: try id(8), approvedAt: try AgentBridgeUTC("2026-03-09T00:00:00Z"),
            authorityId: plan.authorityReferences.native.authorityId, binding: binding, rights: [.exportExecute])
        return try AgentBridgeExecute(approval: approval, idempotencyKey: id(81), jobId: id(82), plan: plan, requestId: id(83))
    }

    func testCaptureReadKeepsFrozenSavedOutputAfterPlanningExpiryWithoutPreferenceReads() throws {
        let rig = try Rig(withSaved: true); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig, policy: .savedDeviceSettings(expectedRevision: 7))
        _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
        let original = try PropertyListDecoder().decode(AgentBridgeRequestSettingsResolution.self, from: reservation.job.nativeResolution)
        rig.clock.advance(seconds: 600)
        rig.reader.catalogRevision += 1; rig.reader.saved = nil
        rig.reader.defaults.reads = 0; rig.reader.calls = []
        let frozen = try rig.service.captureReadConfiguration(reservation, authenticatedPeer: rig.peer)
        XCTAssertEqual(frozen.settings.healthSubfolder, original.settings.healthSubfolder)
        XCTAssertEqual(frozen.selection, original.selection)
        XCTAssertEqual(frozen.predictedRelativePaths, original.predictedRelativePaths)
        XCTAssertEqual(rig.reader.defaults.reads, 0)
        XCTAssertTrue(rig.reader.calls.allSatisfy { $0 == "discovery" })
        XCTAssertEqual(try rig.store.snapshot().captureClaims, [reservation.claim])
    }

    func testCaptureReadRejectsUnavailableMetricsAndCurrentNativeAuthorityLoss() throws {
        for mode in ["metric", "permission", "entitlement", "trust", "grant", "delayed_key"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig)
            _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
            let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
            switch mode {
            case "metric": rig.reader.available.remove("steps")
            case "permission": rig.reader.grants = .required
            case "entitlement": rig.reader.entitlement = .required
            case "trust": rig.session.revoke()
            case "grant": try rig.store.revokeNativeDelegation(request.plan.authorityReferences.native, expectedGeneration: rig.store.snapshot().generation, authorization: FakeNativeAuthorization())
            default: rig.keys.onNextLoad { rig.clock.advance(seconds: 604800) }
            }
            XCTAssertThrowsError(try rig.service.captureReadConfiguration(reservation, authenticatedPeer: rig.peer))
        }
    }

    func testCaptureReadRejectsFabricatedReservationBeforeMetadataAndRechecksReadCallbacks() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
        let fake = AgentBridgeExportCaptureReservation(job: reservation.job,
            claim: .init(version: 1, claimID: try id(99), requestSHA256: reservation.claim.requestSHA256, claimedAt: reservation.claim.claimedAt))
        rig.reader.calls = []
        XCTAssertThrowsError(try rig.service.captureReadConfiguration(fake, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        XCTAssertTrue(rig.reader.calls.isEmpty)
        rig.reader.beforeReturn = { rig.reader.grants = .required }
        XCTAssertThrowsError(try rig.service.captureReadConfiguration(reservation, authenticatedPeer: rig.peer))
    }

    func testCaptureReservationRequiresAcceptanceAndCannotBeReclaimedAcrossRestart() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        XCTAssertThrowsError(try rig.service.claimCapture(request, authenticatedPeer: rig.peer))
        let accepted = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        let claim = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
        XCTAssertEqual(claim.job, accepted.job)
        XCTAssertEqual(claim.claim.requestSHA256, accepted.job.requestSHA256)
        let bytes = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        XCTAssertEqual((try JSONSerialization.jsonObject(with: bytes) as? [String: Any])?["version"] as? Int, 4)
        XCTAssertThrowsError(try rig.restartedService().claimCapture(request, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .busy)
        }
        XCTAssertFalse(try rig.restartedService().acceptExecution(request, authenticatedPeer: rig.peer).newlyAccepted)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), bytes)
    }

    func testCaptureReservationFencesStagingAndNeverReclaimsPublishedButUnreturnedClaim() throws {
        for published in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig)
            _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
            var observed = false
            if published {
                rig.publication.onPublished = { state in
                    if state.captureClaims != nil { observed = true; throw AgentBridgeValidationError.bindingChanged }
                }
            } else {
                rig.publication.onPrepared = { state in
                    if state.captureClaims != nil { observed = true; rig.clock.advance(seconds: 600) }
                }
            }
            XCTAssertThrowsError(try rig.service.claimCapture(request, authenticatedPeer: rig.peer))
            XCTAssertTrue(observed)
            rig.publication.onPrepared = nil; rig.publication.onPublished = nil
            if published {
                XCTAssertEqual(try rig.store.snapshot().captureClaims?.count, 1)
                XCTAssertThrowsError(try rig.restartedService().claimCapture(request, authenticatedPeer: rig.peer)) {
                    XCTAssertEqual($0 as? AgentBridgeValidationError, .busy)
                }
            } else { XCTAssertNil(try rig.store.snapshot().captureClaims) }
        }
    }

    func testCaptureReservationRejectsExpiredChangedAndRevokedAuthorityWithoutClaiming() throws {
        for mode in ["expired", "configuration", "trust", "grant"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig)
            _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
            switch mode {
            case "expired": rig.clock.advance(seconds: 600)
            case "configuration": rig.reader.grants = .required
            case "trust": rig.session.revoke()
            default: try rig.store.revokeNativeDelegation(request.plan.authorityReferences.native, expectedGeneration: rig.store.snapshot().generation, authorization: FakeNativeAuthorization())
            }
            XCTAssertThrowsError(try rig.service.claimCapture(request, authenticatedPeer: rig.peer))
            XCTAssertNil(try rig.store.snapshot().captureClaims)
        }
    }

    func testCaptureReservationVersionSurvivesLaterAcceptanceAndCatalogPublication() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
        let another = AgentBridgeExecute(approval: request.approval, idempotencyKey: try id(94), jobId: try id(95), plan: request.plan, requestId: try id(96))
        XCTAssertTrue(try rig.service.acceptExecution(another, authenticatedPeer: rig.peer).newlyAccepted)
        _ = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { try self.nativeState() }
        XCTAssertEqual(try rig.store.snapshot().captureClaims, [reservation.claim])
        let bytes = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        XCTAssertEqual((try JSONSerialization.jsonObject(with: bytes) as? [String: Any])?["version"] as? Int, 4)
    }

    func testDurableAcceptanceReplaysExactStoredJobAfterPlanExpiryWithoutResolvingChangedSettings() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        let first = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        XCTAssertTrue(first.newlyAccepted)
        XCTAssertEqual(try first.job.request(), request)
        XCTAssertEqual(first.job.requestSHA256.rawValue, try AgentBridgeV4Codec.digest(request))
        let bytes = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 3)
        rig.clock.advance(seconds: 600)
        rig.reader.catalogRevision += 1; rig.reader.entitlement = .required
        let reads = rig.reader.calls.count
        let retry = try rig.restartedService().acceptExecution(request, authenticatedPeer: rig.peer)
        XCTAssertFalse(retry.newlyAccepted)
        XCTAssertEqual(retry.job, first.job)
        XCTAssertEqual(rig.reader.calls.count, reads)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), bytes)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testDurableAcceptanceRejectsChangedIdempotencyBytesAndUnstoredApproval() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        for changed in [AgentBridgeExecute(approval: request.approval, idempotencyKey: try id(90), jobId: request.jobId, plan: request.plan, requestId: request.requestId),
                        AgentBridgeExecute(approval: request.approval, idempotencyKey: request.idempotencyKey, jobId: request.jobId, plan: request.plan, requestId: try id(91))] {
            XCTAssertThrowsError(try rig.service.acceptExecution(changed, authenticatedPeer: rig.peer)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
        }
        XCTAssertEqual(try rig.store.snapshot().acceptedJobs?.count, 1)
        // The contract scopes a key to (peer, job, key), not globally to the peer.
        let distinctJob = AgentBridgeExecute(approval: request.approval, idempotencyKey: request.idempotencyKey,
            jobId: try id(92), plan: request.plan, requestId: try id(93))
        XCTAssertTrue(try rig.service.acceptExecution(distinctJob, authenticatedPeer: rig.peer).newlyAccepted)
        XCTAssertEqual(try rig.store.snapshot().acceptedJobs?.count, 2)
        let unapproved = try Rig(); defer { unapproved.cleanup() }; try unapproved.enroll()
        XCTAssertThrowsError(try unapproved.service.acceptExecution(executionRequest(unapproved, storeDecision: false), authenticatedPeer: unapproved.peer))
        XCTAssertNil(try unapproved.store.snapshot().acceptedJobs)
    }

    func testDurableAcceptanceFencesStagingAndRecoversPublishedButUnreturnedJob() throws {
        for afterPublication in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig)
            var delayed = false
            let delay: (AgentBridgeExportAuthoritySnapshot) -> Void = { state in
                if !delayed, state.acceptedJobs != nil { delayed = true; rig.clock.advance(seconds: 600) }
            }
            if afterPublication { rig.publication.onPublished = delay } else { rig.publication.onPrepared = delay }
            XCTAssertThrowsError(try rig.service.acceptExecution(request, authenticatedPeer: rig.peer))
            XCTAssertTrue(delayed)
            rig.publication.onPrepared = nil; rig.publication.onPublished = nil
            if afterPublication {
                let recovered = try rig.restartedService().acceptExecution(request, authenticatedPeer: rig.peer)
                XCTAssertFalse(recovered.newlyAccepted)
                XCTAssertEqual(try recovered.job.request(), request)
            } else { XCTAssertNil(try rig.store.snapshot().acceptedJobs) }
        }
    }

    func testDurableAcceptanceRetryRejectsRevokedTrustAndExpiredJob() throws {
        for mode in ["trust", "grant", "expired"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll(expires: "2026-03-20T00:00:00Z")
            let request = try executionRequest(rig)
            _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
            if mode == "trust" { rig.session.revoke() }
            else if mode == "grant" {
                try rig.store.revokeNativeDelegation(request.plan.authorityReferences.native, expectedGeneration: rig.store.snapshot().generation, authorization: FakeNativeAuthorization())
            } else { rig.clock.advance(seconds: 604800) }
            XCTAssertThrowsError(try rig.service.acceptExecution(request, authenticatedPeer: rig.peer))
        }
    }

    func testExecutionPreparationUsesExactStoredDecisionAndResolutionWithoutMutationAcrossRestart() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        for service in [rig.service, try rig.restartedService()] {
            let prepared = try service.prepareExecution(request, authenticatedPeer: rig.peer)
            XCTAssertEqual(prepared.requestBytes, try AgentBridgeV4Codec.encode(request))
            XCTAssertEqual(prepared.requestSHA256.rawValue, try AgentBridgeV4Codec.digest(request))
            let resolution = try prepared.resolution()
            XCTAssertEqual(resolution.peer, request.plan.intent.peer)
            XCTAssertEqual(resolution.destination, request.plan.intent.destination)
            XCTAssertEqual(resolution.predictedRelativePaths, request.plan.predictedPaths.map(\.rawValue))
            XCTAssertEqual(resolution.selection.map(\.semanticID), request.plan.resolvedMetricIds.map(\.rawValue))
        }
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testExecutionPreparationRejectsUnstoredOrReplacedApprovalID() throws {
        for stored in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let original = try executionRequest(rig, storeDecision: stored)
            let approval = AgentBridgeApproval(approvalId: try id(stored ? 84 : 8), approvedAt: original.approval.approvedAt,
                authorityId: original.approval.authorityId, binding: original.approval.binding, rights: [.exportExecute])
            let request = AgentBridgeExecute(approval: approval, idempotencyKey: original.idempotencyKey,
                jobId: original.jobId, plan: original.plan, requestId: original.requestId)
            XCTAssertThrowsError(try rig.service.prepareExecution(request, authenticatedPeer: rig.peer)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .approvalRequired)
            }
        }
    }

    func testExecutionPreparationRevalidatesLiveStateAfterKeyAndConfigurationCallbacks() throws {
        for mode in ["expired_key", "revoked_key", "configuration", "missing_key"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig)
            switch mode {
            case "expired_key": rig.keys.onNextLoad { rig.clock.advance(seconds: 600) }
            case "revoked_key": rig.keys.onNextLoad { rig.session.revoke() }
            case "configuration": rig.reader.entitlement = .required
            default: break
            }
            let service = mode == "missing_key" ? AgentBridgeExportPlanningService(store: try .init(existingDirectory: rig.directory, protectedKeys: FakeProtectedKeys(key: nil)), configuration: rig.reader, clock: rig.clock) : rig.service
            XCTAssertThrowsError(try service.prepareExecution(request, authenticatedPeer: rig.peer))
        }
    }

    func testNativeConfigurationDiscoveryAndExplicitNeverReadPrivatePreferences() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let profiles = ExportProfileStore(userDefaults: rig.reader.defaults)
        Self.retainedNativeConfigurationObjects.append(profiles)
        let state = try nativeState()
        let publication = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { state }
        let reader = AgentBridgeNativeConfigurationReader(defaults: rig.reader.defaults, profiles: profiles, nativeState: { state })
        rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
        for policy in [nil, AgentBridgeSettingsPolicy.explicit(try output())] {
            let configuration = try reader.readConfiguration(for: rig.peer, policy: policy, catalogPublication: publication)
            XCTAssertNil(configuration.inputs.savedDevice)
            XCTAssertTrue(configuration.inputs.profiles.isEmpty)
        }
        XCTAssertEqual(rig.reader.defaults.reads, 0)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testNativeConfigurationPlansSupportedPoliciesAndRejectsUnsupportedSavedOutputWithoutMutation() async throws {
        for kind in ["explicit", "saved", "profile"] {
            let rig = try Rig(withSaved: true); defer { rig.cleanup() }; try rig.enroll()
            let original = try XCTUnwrap(rig.reader.saved)
            let settings = AdvancedExportSettings(snapshot: original, userDefaults: rig.reader.defaults)
            settings.apply(snapshot: original)
            try await Task.sleep(for: .milliseconds(350))
            rig.reader.defaults.set(original.healthSubfolder, forKey: "healthSubfolder")
            let profiles = ExportProfileStore(userDefaults: rig.reader.defaults)
            Self.retainedNativeConfigurationObjects.append(settings)
            Self.retainedNativeConfigurationObjects.append(profiles)
            let selected = try XCTUnwrap(profiles.add(name: "Selected", settings: original, target: .connectedMac))
            let other = try XCTUnwrap(profiles.add(name: "Active", settings: original, target: .localIPhoneFolder))
            XCTAssertTrue(profiles.activate(id: other.id))
            let revision = try XCTUnwrap(AdvancedExportSettings.nativeConfigurationRevision(defaults: SystemUserDefaults(defaults: rig.reader.defaults)))
            let state = try nativeState()
            _ = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { state }
            let reader = AgentBridgeNativeConfigurationReader(defaults: rig.reader.defaults, profiles: profiles, nativeState: { state })
            let service = AgentBridgeExportPlanningService(store: rig.store, configuration: reader, clock: rig.clock, newPlanID: { try id(6) })
            func send(_ document: AgentBridgeDocument) throws -> AgentBridgeDocument {
                try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: service.handle(
                    AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: document)), authenticatedPeer: rig.peer)).payload
            }
            let before = rig.reader.defaults.persistentDomain(forName: rig.reader.suite)
            rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
            guard case .discovery(let discovery) = try send(.discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer))) else {
                return XCTFail("Expected native discovery")
            }
            XCTAssertEqual(rig.reader.defaults.reads, 0)
            let policy: AgentBridgeSettingsPolicy
            switch kind {
            case "saved": policy = .savedDeviceSettings(expectedRevision: revision)
            case "profile": policy = .profile(profileID: try AgentBridgeUUID(selected.id.uuidString.lowercased()), expectedRevision: 1)
            default: policy = .explicit(try output())
            }
            let response = try send(.planRequest(rig.request(discovery: discovery, policy: policy)))
            if kind == "saved" {
                // Native rehydration supplies default frontmatter fields. The current strict output
                // subset cannot represent them, even for JSON: reject rather than drop output fields.
                // Full saved-settings output acceptance remains an integration requirement.
                XCTAssertEqual(try error(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: response))), .unsupportedCapability)
            } else {
                guard case .plan(let plan) = response else { return XCTFail("Expected supported native configuration plan") }
                XCTAssertEqual(try service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer), plan)
                XCTAssertEqual(plan.intent.settingsPolicy, policy)
            }
            XCTAssertEqual(profiles.activeProfileID, other.id)
            XCTAssertEqual(rig.reader.defaults.writes, 0)
            if kind == "explicit" { XCTAssertEqual(rig.reader.defaults.reads, 0) }
            XCTAssertEqual(rig.reader.defaults.persistentDomain(forName: rig.reader.suite) as NSDictionary?, before as NSDictionary?)
        }
    }

    func testNativeConfigurationRejectsStalePinsStateDriftAndRevokedPeerWithoutFallback() throws {
        for mode in ["stale_saved", "stale_profile", "drift", "revoke"] {
            let rig = try Rig(withSaved: true); defer { rig.cleanup() }
            let profiles = ExportProfileStore(userDefaults: rig.reader.defaults)
            Self.retainedNativeConfigurationObjects.append(profiles)
            let profile = try XCTUnwrap(profiles.add(name: "Selected", settings: XCTUnwrap(rig.reader.saved), target: .localIPhoneFolder))
            let initial = try nativeState()
            let publication = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { initial }
            var reads = 0
            let reader = AgentBridgeNativeConfigurationReader(defaults: rig.reader.defaults, profiles: profiles, nativeState: {
                reads += 1
                if mode == "revoke", reads == 2 { rig.session.revoke() }
                return try self.nativeState(foregroundAvailable: !(mode == "drift" && reads == 2))
            })
            let policy: AgentBridgeSettingsPolicy?
            switch mode {
            case "stale_saved": policy = .savedDeviceSettings(expectedRevision: 7)
            case "stale_profile": policy = .profile(profileID: try AgentBridgeUUID(profile.id.uuidString.lowercased()), expectedRevision: 2)
            default: policy = nil
            }
            rig.reader.defaults.writes = 0
            XCTAssertThrowsError(try reader.readConfiguration(for: rig.peer, policy: policy, catalogPublication: publication)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, mode == "revoke" ? .permissionRequired : .bindingChanged)
            }
            XCTAssertEqual(rig.reader.defaults.writes, 0)
        }
    }

    func testNativeCatalogPublicationPersistsIdempotentlyAndAdvancesAcrossReadinessABA() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let file = rig.directory.appendingPathComponent("state.json")
        let legacyBytes = try Data(contentsOf: file), original = try rig.store.snapshot()
        XCTAssertNil(original.nativeCatalog)
        _ = try rig.store.snapshot()
        XCTAssertEqual(try Data(contentsOf: file), legacyBytes) // Reading v1 never migrates or writes it.
        let ready = try nativeState(), unavailable = try nativeState(foregroundAvailable: false)
        let first = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { ready }
        XCTAssertEqual(first.revision, 1)
        let publishedBytes = try Data(contentsOf: file), generation = try rig.store.snapshot().generation
        let restarted = try AgentBridgeExportAuthorityStore(existingDirectory: rig.directory, protectedKeys: rig.keys)
        XCTAssertEqual(try restarted.snapshot().nativeCatalog, first)
        XCTAssertEqual(try restarted.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { ready }, first)
        XCTAssertEqual(try restarted.snapshot().generation, generation)
        XCTAssertEqual(try Data(contentsOf: file), publishedBytes)
        let second = try restarted.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { unavailable }
        let third = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { ready }
        XCTAssertEqual([second.revision, third.revision], [2, 3])
        XCTAssertEqual(third.factsSHA256, first.factsSHA256)
        let after = try rig.store.snapshot()
        XCTAssertEqual(after.delegations.map(\.sanitizedBytes), original.delegations.map(\.sanitizedBytes))
        XCTAssertEqual(after.delegations.map(\.revoked), original.delegations.map(\.revoked))
        XCTAssertTrue(after.plans.isEmpty); XCTAssertTrue(after.decisions.isEmpty)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])?["version"] as? Int, 2)
    }

    func testNativeCatalogMissingOrChangedPublicationRejectsWithoutWireRepairAndInvalidatesOldPlansAfterABA() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let profiles = ExportProfileStore(userDefaults: rig.reader.defaults)
        Self.retainedNativeConfigurationObjects.append(profiles)
        var facts = try nativeState(), samples = 0
        let reader = AgentBridgeNativeConfigurationReader(defaults: rig.reader.defaults, profiles: profiles, nativeState: { samples += 1; return facts })
        let service = AgentBridgeExportPlanningService(store: rig.store, configuration: reader, clock: rig.clock, newPlanID: { try id(6) })
        func send(_ document: AgentBridgeDocument) throws -> Data {
            try service.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: document)), authenticatedPeer: rig.peer)
        }
        let file = rig.directory.appendingPathComponent("state.json"), before = try Data(contentsOf: file)
        XCTAssertEqual(try error(send(.discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer)))), .bindingChanged)
        XCTAssertEqual(samples, 0); XCTAssertEqual(try Data(contentsOf: file), before)
        _ = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }
        guard case .discovery(let discovery) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self,
            from: send(.discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer)))).payload else { return XCTFail("Expected published discovery") }
        guard case .plan(let plan) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self,
            from: send(.planRequest(rig.request(discovery: discovery)))).payload else { return XCTFail("Expected published plan") }
        let accepted = try Data(contentsOf: file)
        facts = try nativeState(foregroundAvailable: false)
        XCTAssertThrowsError(try service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        XCTAssertEqual(try Data(contentsOf: file), accepted) // No reader publication or repair.
        _ = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }
        facts = try nativeState()
        _ = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }
        XCTAssertThrowsError(try service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        XCTAssertEqual(try rig.store.snapshot().plans.count, 1) // No silent replan or new consent.
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
    }

    func testNativeLifecycleRejectsPendingChangesBeforeSignedPublicationAndInvalidatesOldPlans() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let profiles = ExportProfileStore(userDefaults: rig.reader.defaults)
        Self.retainedNativeConfigurationObjects.append(profiles)
        let facts = try nativeState()
        let lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(facts)
        XCTAssertThrowsError(try lifecycle.currentFacts())
        let reader = AgentBridgeNativeConfigurationReader(defaults: rig.reader.defaults, profiles: profiles, nativeState: { try lifecycle.currentFacts() })
        let service = AgentBridgeExportPlanningService(store: rig.store, configuration: reader, clock: rig.clock, newPlanID: { try id(6) })
        let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let discoveryBytes = try service.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload:
            .discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer)))), authenticatedPeer: rig.peer)
        guard case .discovery(let discovery) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: discoveryBytes).payload else {
            return XCTFail("Expected published discovery")
        }
        let planBytes = try service.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload:
            .planRequest(rig.request(discovery: discovery)))), authenticatedPeer: rig.peer)
        guard case .plan(let plan) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: planBytes).payload else {
            return XCTFail("Expected issued plan")
        }
        _ = try service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)
        let before = try rig.store.snapshot()
        // An observed transition may coalesce before deferred SDK sampling. It must not
        // become an unchanged-publication retry or silently renew this issued plan.
        let pendingBytes = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        try lifecycle.observeNativeChange()
        try lifecycle.observe(facts) // Deferred sample has returned to the original value.
        XCTAssertThrowsError(try service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), pendingBytes)
        let changed = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertEqual(changed.factsSHA256, first.factsSHA256)
        XCTAssertEqual(changed.revision, first.revision + 1)
        let after = try rig.store.snapshot()
        XCTAssertEqual(after.generation, before.generation + 1)
        XCTAssertEqual(after.plans.count, 1)
        XCTAssertEqual(after.delegations.map(\.sanitizedBytes), before.delegations.map(\.sanitizedBytes))
        XCTAssertTrue(after.decisions.isEmpty)
        XCTAssertThrowsError(try service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        let file = rig.directory.appendingPathComponent("state.json"), committed = try Data(contentsOf: file)
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        XCTAssertEqual(try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID), changed)
        let restarted = try AgentBridgeExportAuthorityStore(existingDirectory: rig.directory, protectedKeys: rig.keys, publication: rig.publication)
        XCTAssertEqual(try restarted.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }, changed)
        XCTAssertEqual(try Data(contentsOf: file), committed)
    }

    func testNativeLifecycleDoesNotClearObservationRacingSignedPublication() throws {
        for afterSync in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }
            let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
            try lifecycle.observe(facts)
            let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            try lifecycle.observeNativeChange()
            var observed = false
            let callback: (AgentBridgeExportAuthoritySnapshot) -> Void = { _ in
                observed = true
                do { try lifecycle.observeNativeChange() }
                catch { XCTFail("Native observation unexpectedly rejected") }
            }
            if afterSync { rig.publication.onPublished = callback } else { rig.publication.onPrepared = callback }
            XCTAssertThrowsError(try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
            XCTAssertTrue(observed)
            XCTAssertThrowsError(try lifecycle.currentFacts())
            rig.publication.onPrepared = nil; rig.publication.onPublished = nil
            let next = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            XCTAssertGreaterThan(next.revision, first.revision)
            XCTAssertEqual(try lifecycle.currentFacts(), facts)
        }
    }

    func testNativeLifecycleOwnerRestartInvalidatesOldCatalogAndStopCannotRevive() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let facts = try nativeState(), firstOwner = AgentBridgeNativeCatalogLifecycle()
        try firstOwner.observe(facts)
        let first = try firstOwner.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        firstOwner.stop()
        XCTAssertThrowsError(try firstOwner.currentFacts()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertThrowsError(try firstOwner.observe(facts))
        XCTAssertThrowsError(try firstOwner.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID))
        let nextOwner = AgentBridgeNativeCatalogLifecycle()
        try nextOwner.observe(facts)
        let next = try nextOwner.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertEqual(next.revision, first.revision + 1)
        XCTAssertEqual(next.factsSHA256, first.factsSHA256)
        XCTAssertEqual(try nextOwner.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID), next)
    }

    private func nativePlanningSession(_ rig: Rig, _ lifecycle: AgentBridgeNativeCatalogLifecycle, profiles existingProfiles: ExportProfileStore? = nil, responseChannel: DirectSecureChannel? = nil, responseVersions: [Int] = [1, 3, 4]) throws -> AgentBridgeNativePlanningSession {
        let profiles = existingProfiles ?? ExportProfileStore(userDefaults: rig.reader.defaults)
        Self.retainedNativeConfigurationObjects.append(profiles)
        let reader = AgentBridgeNativeConfigurationReader(defaults: rig.reader.defaults, profiles: profiles) {
            try lifecycle.currentFacts()
        }
        return try AgentBridgeNativePlanningSession(peer: rig.peer, lifecycle: lifecycle, store: rig.store,
            configuration: reader, responseChannel: responseChannel,
            responseNegotiation: AgentBridgeNegotiation(localVersions: responseVersions, remoteVersions: [1, 3, 4], deployedBaseVersion: 1),
            clock: rig.clock, newPlanID: { try id(6) })
    }

    private func nativeDiscoveryBytes(_ rig: Rig) throws -> Data {
        try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer))))
    }

    func testNativeReceiveRoutesDiscoveryAndPreservesBaseAndBinaryFrames() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let key = SymmetricKey(data: Data(repeating: 7, count: 32)), binary = Data("HMDDIRCTsynthetic".utf8)
        let wire = NativePlanningResponsePackets(inbound: [
            try nativeResponsePacket(JSONEncoder().encode(DirectMessage.ping), sequence: 0, key: key),
            try nativeResponsePacket(nativeDiscoveryBytes(rig), sequence: 1, key: key),
            try nativeResponsePacket(binary, sequence: 2, key: key),
        ])
        let channel = DirectSecureChannel(packetConnection: wire, sessionKey: key, peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        defer { channel.cancel() }
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
        let before = try rig.store.snapshot().generation
        rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
        let base = try await planner.receiveAndHandleNext()
        XCTAssertEqual(base, .base(.ping))
        let handled = try await planner.receiveAndHandleNext()
        XCTAssertNil(handled)
        let frame = try await planner.receiveAndHandleNext()
        XCTAssertEqual(frame, .binaryTransferFrame(binary))
        XCTAssertEqual(wire.receiveCount, 3); XCTAssertEqual(wire.packets.count, 1)
        guard case .encrypted(let response) = try XCTUnwrap(wire.packets.first) else { return XCTFail("Expected owned encrypted response") }
        let plaintext = try ManualIPSyncSecurity.open(response, using: key)
        guard case .discovery(let discovery) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: Data(plaintext.dropFirst(16))).payload else { return XCTFail("Expected discovery") }
        XCTAssertEqual(discovery.peer, rig.peer.peer)
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
        XCTAssertEqual(rig.reader.defaults.reads, 0); XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testNativeReceiveRevokedOwnerCannotReturnBaseOrRevive() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let key = SymmetricKey(data: Data(repeating: 7, count: 32))
        let wire = NativePlanningResponsePackets(inbound: [try nativeResponsePacket(JSONEncoder().encode(DirectMessage.ping), sequence: 0, key: key)],
            beforeReceive: { await MainActor.run { lifecycle.stop() } })
        let channel = DirectSecureChannel(packetConnection: wire, sessionKey: key, peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
        for _ in 0..<2 {
            do { _ = try await planner.receiveAndHandleNext(); XCTFail("Stopped owner cannot return or revive") }
            catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
        }
        XCTAssertEqual(wire.receiveCount, 1); XCTAssertTrue(wire.packets.isEmpty)
        XCTAssertTrue(channel.isLocallyTerminal)
    }

    private func nativeResponsePacket(_ bytes: Data, sequence: UInt64, key: SymmetricKey) throws -> ManualIPSyncPacket {
        var plaintext = Data("HMDSC001".utf8), number = sequence.bigEndian
        withUnsafeBytes(of: &number) { plaintext.append(contentsOf: $0) }
        plaintext.append(bytes)
        return .encrypted(try ManualIPSyncSecurity.seal(plaintext, using: key))
    }

    func testNativeResponseUsesPinnedGuardedChannelWithoutIssuingAuthority() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let wire = NativePlanningResponsePackets(), key = SymmetricKey(data: Data(repeating: 7, count: 32))
        let channel = DirectSecureChannel(packetConnection: wire, sessionKey: key, peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        defer { channel.cancel() }
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
        let before = try rig.store.snapshot().generation
        rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
        let negotiation = try AgentBridgeNegotiation(localVersions: [1, 4], remoteVersions: [1, 4], deployedBaseVersion: 1)
        try await planner.handleAndSend(nativeDiscoveryBytes(rig))
        guard case .encrypted(let frame) = try XCTUnwrap(wire.packets.first) else { return XCTFail("Expected encrypted response") }
        let plaintext = try ManualIPSyncSecurity.open(frame, using: key)
        guard case .discovery(let response) = try negotiation.decode(Data(plaintext.dropFirst(16))).payload else { return XCTFail("Expected owned discovery") }
        XCTAssertEqual(response.peer, rig.peer.peer)
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
        XCTAssertEqual(rig.reader.defaults.reads, 0); XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testNativeResponseUnsupportedNegotiationDoesNotTouchIssuerOrChannel() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let wire = NativePlanningResponsePackets()
        let channel = DirectSecureChannel(packetConnection: wire, sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        defer { channel.cancel() }
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel, responseVersions: [1, 3])
        let checks = rig.session.checks
        do { try await planner.handleAndSend(Data("invalid".utf8)); XCTFail("Expected no extension") }
        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .unsupportedCapability) }
        do { _ = try await planner.receiveAndHandleNext(); XCTFail("Remote4 cannot override the owner's local hello") }
        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .unsupportedCapability) }
        XCTAssertEqual(wire.receiveCount, 0)
        XCTAssertEqual(rig.session.checks, checks)
        XCTAssertTrue(wire.packets.isEmpty); XCTAssertFalse(channel.isLocallyTerminal)
    }

    func testNativeResponseRejectsCompletedPublicationChangeBeforeAndAfterWrite() async throws {
        for afterWrite in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
            let original = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let change: @concurrent @Sendable () async throws -> Void = {
                try await MainActor.run {
                    try lifecycle.recordNativeEvent()
                    _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
                }
            }
            let wire = NativePlanningResponsePackets(beforeWrite: { if !afterWrite { try await change() } }, afterWrite: { if afterWrite { try await change() } })
            let channel = DirectSecureChannel(packetConnection: wire, sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
            let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
                do { try await planner.handleAndSend(nativeDiscoveryBytes(rig)); XCTFail("Expected original publication fence") }
            catch { XCTAssertEqual(error as? AgentBridgeValidationError, .bindingChanged) }
            XCTAssertEqual(try lifecycle.currentPublication().revision, original.revision + 1)
            XCTAssertEqual(wire.packets.count, afterWrite ? 1 : 0)
            XCTAssertTrue(channel.isLocallyTerminal)
            do { try await planner.handleAndSend(nativeDiscoveryBytes(rig)); XCTFail("Cannot revive abandoned response owner") }
            catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
        }
    }

    func testNativeResponseCancellationFromLastReturnPeerCallbackCannotSucceed() async throws {
        var finalCheckCount = 0
        for cancel in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
            _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let wire = NativePlanningResponsePackets()
            let channel = DirectSecureChannel(packetConnection: wire, sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
            defer { channel.cancel() }
            let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
                let before = rig.session.checks
            if cancel {
                let target = before + finalCheckCount
                rig.session.observeChecks { check in if check == target { withUnsafeCurrentTask { $0?.cancel() } } }
            }
            let task = Task { try await planner.handleAndSend(nativeDiscoveryBytes(rig)) }
            do {
                try await task.value
                if cancel { XCTFail("Cancellation during final validator cannot return success") }
            } catch {
                if !cancel { throw error }
                XCTAssertTrue(error is CancellationError)
                XCTAssertTrue(channel.isLocallyTerminal)
            }
            if !cancel { finalCheckCount = rig.session.checks - before; XCTAssertGreaterThan(finalCheckCount, 0) }
            else { XCTAssertEqual(rig.session.checks - before, finalCheckCount) }
        }
    }

    func testNativeResponseRechecksLiveIssuerExpiryAtActualWrite() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let wire = NativePlanningResponsePackets(beforeWrite: { await MainActor.run { rig.clock.advance(seconds: 600) } })
        let channel = DirectSecureChannel(packetConnection: wire, sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
        do { try await planner.handleAndSend(nativeDiscoveryBytes(rig)); XCTFail("Expected expiry after planning") }
        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .planExpired) }
        XCTAssertTrue(wire.packets.isEmpty); XCTAssertTrue(channel.isLocallyTerminal)
    }

    func testOwnerBoundPlannerRetainsDiscoveryThroughPlanReviewAndExactDecision() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let planner = try nativePlanningSession(rig, lifecycle)
        rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
        let before = try rig.store.snapshot().generation
        guard case .discovery(let discovery) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self,
            from: planner.handle(nativeDiscoveryBytes(rig))).payload else { return XCTFail("Expected owned discovery") }
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        let bytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(rig.request(discovery: discovery, policy: .explicit(output())))))
        guard case .plan(let plan) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: planner.handle(bytes)).payload else {
            return XCTFail("Expected plan using the same session's discovery")
        }
        XCTAssertEqual(try planner.reviewNativePlan(planID: plan.planId), plan)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
        let binding = try AgentBridgeSemantics.binding(plan)
        try planner.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8),
            authorization: FakeNativeAuthorization(binding: binding))
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 1)
        XCTAssertTrue(try planner.nativePlansAwaitingReview().isEmpty)
        XCTAssertEqual(rig.reader.defaults.reads, 0); XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testNativeReviewQueueIsReadOnlyAndRemovesConfirmedAndStalePlans() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let planner = try nativePlanningSession(rig, lifecycle)
        guard case .discovery(let discovery) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self,
            from: planner.handle(nativeDiscoveryBytes(rig))).payload else { return XCTFail("Expected discovery") }
        let bytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(rig.request(discovery: discovery, policy: .explicit(output())))))
        guard case .plan(let plan) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: planner.handle(bytes)).payload else { return XCTFail("Expected plan") }
        rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
        let before = try rig.store.snapshot().generation
        XCTAssertEqual(try planner.nativePlansAwaitingReview(), [plan])
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
        try lifecycle.recordNativeEvent()
        XCTAssertThrowsError(try planner.nativePlansAwaitingReview())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertTrue(try planner.nativePlansAwaitingReview().isEmpty)
        XCTAssertEqual(rig.reader.defaults.reads, 0); XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testNativeReviewQueueRejectsStorageLossAfterItsInitialSnapshot() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let planner = try nativePlanningSession(rig, lifecycle)
        guard case .discovery(let discovery) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self,
            from: planner.handle(nativeDiscoveryBytes(rig))).payload else { return XCTFail("Expected discovery") }
        _ = try planner.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(rig.request(discovery: discovery, policy: .explicit(output()))))))
        let removeAt = rig.session.checks + 2
        var removed = false
        rig.session.observeChecks { count in
            if count == removeAt {
                try! FileManager.default.removeItem(at: rig.directory.appendingPathComponent("state.json"))
                removed = true
            }
        }
        XCTAssertThrowsError(try planner.nativePlansAwaitingReview())
        XCTAssertTrue(removed)
    }

    func testOwnerBoundPlannerRejectsPendingAndStoppedOwnerDespiteSamePeerReplacement() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let profiles = ExportProfileStore(userDefaults: rig.reader.defaults)
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        XCTAssertThrowsError(try nativePlanningSession(rig, lifecycle, profiles: profiles))
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let planner = try nativePlanningSession(rig, lifecycle, profiles: profiles)
        try lifecycle.recordNativeEvent()
        rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
        XCTAssertThrowsError(try planner.handle(Data("invalid".utf8))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged) }
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        _ = try planner.handle(nativeDiscoveryBytes(rig))
        lifecycle.stop()
        let replacement = AgentBridgeNativeCatalogLifecycle(); try replacement.observe(nativeState())
        _ = try replacement.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertThrowsError(try planner.handle(nativeDiscoveryBytes(rig))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        let fresh = try nativePlanningSession(rig, replacement, profiles: profiles)
        _ = try fresh.handle(nativeDiscoveryBytes(rig))
        XCTAssertEqual(rig.reader.defaults.reads, 0); XCTAssertEqual(rig.reader.defaults.writes, 0)
        XCTAssertEqual(try rig.store.snapshot().delegations.count, 1)
    }

    func testOwnerBoundPlannerRejectsEventDuringFinalPeerReturnCheck() throws {
        var finalCheck = 0
        for inject in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
            _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let planner = try nativePlanningSession(rig, lifecycle)
            var fired = false
            if inject {
                rig.session.observeChecks { count in
                    if count == finalCheck { fired = true; try! lifecycle.recordNativeEvent() }
                }
                XCTAssertThrowsError(try planner.handle(nativeDiscoveryBytes(rig))) {
                    XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
                }
                XCTAssertTrue(fired)
            } else {
                _ = try planner.handle(nativeDiscoveryBytes(rig))
                finalCheck = rig.session.checks
                XCTAssertGreaterThan(finalCheck, 0)
            }
            XCTAssertTrue(try rig.store.snapshot().plans.isEmpty)
        }
    }

    func testOwnerBoundPlannerRejectsSignedStorePublicationOutsideOwner() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
        try lifecycle.observe(facts)
        let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let planner = try nativePlanningSession(rig, lifecycle)
        let next = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID,
            invalidatingObservedChange: true) { facts }
        XCTAssertEqual(next.factsSHA256, first.factsSHA256)
        XCTAssertEqual(next.revision, first.revision + 1)
        guard case .error(let failure) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self,
            from: planner.handle(nativeDiscoveryBytes(rig))).payload else { return XCTFail("Expected binding_changed for mismatched signed publication") }
        XCTAssertEqual(failure.code, .bindingChanged)
    }

    func testOwnerBoundPlannerRejectsCompletedPublicationDuringFinalPeerReturnCheck() throws {
        var finalCheck = 0
        for inject in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
            let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let planner = try nativePlanningSession(rig, lifecycle)
            var fired = false
            if inject {
                rig.session.observeChecks { count in
                    if count == finalCheck {
                        fired = true
                        try! lifecycle.recordNativeEvent()
                        _ = try! lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
                    }
                }
                XCTAssertThrowsError(try planner.handle(nativeDiscoveryBytes(rig))) {
                    XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
                }
                XCTAssertTrue(fired)
                XCTAssertEqual(try lifecycle.currentPublication().revision, first.revision + 1)
            } else {
                _ = try planner.handle(nativeDiscoveryBytes(rig)); finalCheck = rig.session.checks
                XCTAssertGreaterThan(finalCheck, 0)
            }
            XCTAssertTrue(try rig.store.snapshot().plans.isEmpty)
            XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
        }
    }

    func testNativeAuthorityGrantAndRevokeInvalidateSameOwnerAfterStoreUnlock() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
        try lifecycle.observe(facts)
        let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let relay = AgentBridgeNativeCatalogEventRelay(); relay.replace(with: lifecycle)
        let notifications = AgentBridgeNativeCatalogNotifications(names: [.healthMdAgentExportAuthorityDidChange], relay: relay)
        defer { withExtendedLifetime(notifications) {}; relay.replace(with: nil) }
        try rig.enroll()
        XCTAssertThrowsError(try lifecycle.currentFacts()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged) }
        let next = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertEqual(next.revision, first.revision + 1)
        try rig.store.revokeNativeDelegation(rig.grant().reference(), expectedGeneration: rig.store.snapshot().generation,
                                            authorization: FakeNativeAuthorization())
        XCTAssertTrue(try XCTUnwrap(rig.store.snapshot().delegations.first).revoked)
        XCTAssertThrowsError(try lifecycle.currentFacts()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged) }
        XCTAssertEqual(try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID).revision,
                       next.revision + 1)
    }

    func testNativeAuthoritySetupAndFailedAuthorizedWriteEmitButDeniedAttemptDoesNot() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
        try lifecycle.observe(facts)
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let relay = AgentBridgeNativeCatalogEventRelay(); relay.replace(with: lifecycle)
        let notifications = AgentBridgeNativeCatalogNotifications(names: [.healthMdAgentExportAuthorityDidChange], relay: relay)
        defer { withExtendedLifetime(notifications) {}; relay.replace(with: nil) }
        let other = rig.parent.appendingPathComponent("new-native-authority")
        XCTAssertThrowsError(try AgentBridgeExportAuthorityStore.createPrivateStore(at: other, protectedKeys: rig.keys,
            authorization: FakeNativeAuthorization(deny: true)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.path))
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        _ = try AgentBridgeExportAuthorityStore.createPrivateStore(at: other, protectedKeys: rig.keys, authorization: FakeNativeAuthorization())
        XCTAssertThrowsError(try lifecycle.currentFacts())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let before = try rig.store.snapshot().generation
        XCTAssertThrowsError(try rig.store.storeNativeDelegation(rig.grant(), expectedGeneration: before,
            authorization: FakeNativeAuthorization(deny: true)))
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        XCTAssertThrowsError(try rig.store.storeNativeDelegation(rig.grant(), expectedGeneration: before + 1,
            authorization: FakeNativeAuthorization()))
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertThrowsError(try lifecycle.currentFacts()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged) }
    }

    func testNativeAuthorityPublicationReadAndDetachedObserverDoNotInvalidate() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
        try lifecycle.observe(facts)
        let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let relay = AgentBridgeNativeCatalogEventRelay(); relay.replace(with: lifecycle)
        var notifications: AgentBridgeNativeCatalogNotifications? = .init(names: [.healthMdAgentExportAuthorityDidChange], relay: relay)
        try withExtendedLifetime(notifications) {
            _ = try rig.store.snapshot()
        }
        XCTAssertEqual(try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID), first)
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        notifications = nil
        try rig.enroll()
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        relay.replace(with: nil)
        NotificationCenter.default.post(name: .healthMdAgentExportAuthorityDidChange, object: nil)
        XCTAssertThrowsError(try lifecycle.currentFacts()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
    }

    func testFoundationNativeNotificationsLatchBeforeReturnAndDetachWithOwnerLifetime() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let facts = try nativeState(), lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(facts)
        let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let relay = AgentBridgeNativeCatalogEventRelay(), center = NotificationCenter()
        relay.replace(with: lifecycle)
        relay.replace(with: lifecycle) // Reattaching the same owner cannot stop or renew it.
        var notifications: AgentBridgeNativeCatalogNotifications? = .init(
            center: center, names: [.NSSystemTimeZoneDidChange], relay: relay)
        center.post(name: .init("synthetic.unrelated"), object: nil)
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        withExtendedLifetime(notifications) {
            center.post(name: .NSSystemTimeZoneDidChange, object: nil)
            center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        }
        // Both actual Foundation callbacks ran synchronously, before any deferred SDK sampling.
        XCTAssertThrowsError(try lifecycle.currentFacts()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged) }
        let next = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertEqual(next.revision, first.revision + 1)
        notifications = nil
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        XCTAssertEqual(try lifecycle.currentFacts(), facts) // Exact tokens were removed on teardown.
        relay.replace(with: nil)
        relay.observeNativeChange() // No owner means no issuer/settings/key work.
        XCTAssertThrowsError(try lifecycle.currentFacts()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
    }

    #if canImport(HealthMd)
    func testNativeConfigurationProtectionChangesInvalidateCatalogBeforeReturning() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let center = NotificationCenter()
        let manager = ConfigurationProtectionManager(userDefaults: rig.reader.defaults, nativePlanningNotifications: center)
        Self.retainedNativeConfigurationObjects.append(manager)
        let original = manager.isEnabled
        let facts = try nativeState(), lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(facts)
        let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let relay = AgentBridgeNativeCatalogEventRelay()
        relay.replace(with: lifecycle)
        var notifications: AgentBridgeNativeCatalogNotifications? = .init(
            center: center, names: [.healthMdConfigurationProtectionDidChange], relay: relay)
        try withExtendedLifetime(notifications) {
            manager.setEnabled(original)
            XCTAssertEqual(try lifecycle.currentFacts(), facts) // Identical assignments emit no event.
            manager.setEnabled(!original)
            XCTAssertEqual(manager.isEnabled, !original)
            XCTAssertThrowsError(try lifecycle.currentFacts()) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
            manager.setEnabled(original)
            XCTAssertEqual(manager.isEnabled, original)
            XCTAssertThrowsError(try lifecycle.currentFacts()) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
        }
        let next = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertEqual(next.revision, first.revision + 1)
        XCTAssertEqual(next.factsSHA256, first.factsSHA256)
        notifications = nil
        manager.setEnabled(!original)
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        relay.replace(with: nil)
        manager.setEnabled(original)
        XCTAssertThrowsError(try lifecycle.currentFacts()) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
    }

    func testNativePurchaseQuotaTransitionsInvalidatePublishedCatalogBeforeReturning() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let center = NotificationCenter(), keychain = FakeKeychainStore()
        let manager = PurchaseManager(keychain: keychain, defaults: FakeUserDefaults(), nativePlanningNotifications: center)
        Self.retainedNativeConfigurationObjects.append(manager)
        XCTAssertTrue(manager.nativePlanningCanExport)
        let facts = try nativeState(), lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(facts)
        let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let relay = AgentBridgeNativeCatalogEventRelay()
        relay.replace(with: lifecycle)
        var notifications: AgentBridgeNativeCatalogNotifications? = .init(
            center: center, names: [.healthMdNativeExportEligibilityDidChange], relay: relay)
        try withExtendedLifetime(notifications) {
            manager.setFreeExportsUsed(PurchaseManager.freeExportLimit)
            XCTAssertFalse(manager.nativePlanningCanExport)
            XCTAssertThrowsError(try lifecycle.currentFacts()) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
            manager.resetFreeExports()
            XCTAssertTrue(manager.nativePlanningCanExport)
            // Eligibility returned to its original value before any deferred sampler ran.
            XCTAssertThrowsError(try lifecycle.currentFacts()) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
        }
        let next = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertEqual(next.revision, first.revision + 1)
        XCTAssertEqual(next.factsSHA256, first.factsSHA256)
        try withExtendedLifetime(notifications) {
            // Native refresh briefly closes eligibility even if durable facts are unchanged.
            manager.refreshNativePlanningExportEligibility()
            XCTAssertTrue(manager.nativePlanningCanExport)
            XCTAssertThrowsError(try lifecycle.currentFacts()) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
        }
        let refreshed = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertEqual(refreshed.revision, next.revision + 1)
        notifications = nil
        manager.setFreeExportsUsed(PurchaseManager.freeExportLimit)
        XCTAssertEqual(try lifecycle.currentFacts(), facts) // Observer teardown removed its exact token.
        relay.replace(with: nil)
        manager.resetFreeExports()
        XCTAssertThrowsError(try lifecycle.currentFacts()) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
    }
    #endif

    #if canImport(HealthMd)
    func testHealthKitFlowEventsInvalidateSameFactsAndTeardownExactNativeObserver() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let center = NotificationCenter(), healthStore = FakeHealthStore()
        healthStore.authRequestStatus = .unnecessary
        let manager = HealthKitManager(store: healthStore, userDefaults: rig.reader.defaults,
                                       nativePlanningNotifications: center)
        manager.isAuthorized = true
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
        let relay = AgentBridgeNativeCatalogEventRelay()
        relay.replace(with: lifecycle)
        var notifications: AgentBridgeNativeCatalogNotifications? = .init(center: center,
            names: [.healthMdNativeHealthAuthorizationDidChange], relay: relay)
        try lifecycle.observe(facts)
        let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        manager.isAuthorized = true // Identical cache assignment is not a completed native flow.
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        _ = try await manager.requestAuthorization()
        XCTAssertThrowsError(try lifecycle.currentPublication())
        let second = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertEqual(second.revision, first.revision + 1)
        _ = try await manager.requestAuthorization() // Repeated flow still invalidates equal metadata.
        XCTAssertThrowsError(try lifecycle.currentFacts())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        manager.isAuthorized = false; manager.isAuthorized = true
        XCTAssertThrowsError(try lifecycle.currentFacts())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        withExtendedLifetime(notifications) { }
        notifications = nil
        manager.isAuthorized = false
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        relay.replace(with: nil)
        manager.isAuthorized = true
        XCTAssertThrowsError(try lifecycle.currentFacts())
        XCTAssertFalse(healthStore.authRequested)
        XCTAssertTrue(healthStore.quantitySampleQueries.isEmpty)
        XCTAssertTrue(healthStore.completedCanonicalQueryIdentifiers.isEmpty)
        XCTAssertTrue(healthStore.workoutRecordQueries.isEmpty)
        XCTAssertTrue(healthStore.medicationRecordQueries.isEmpty)
    }

    #endif

    func testNativeAdmissionDefersSDKUntilConfiguredAndPinsInitialDependencies() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let admission = AgentBridgeNativeCatalogAdmission(), lifecycle = AgentBridgeNativeCatalogLifecycle()
        let facts = try nativeState(), store = rig.store
        let published = expectation(description: "admitted owner published")
        var calls = 0
        var controller: AgentBridgeNativeCatalogRefresh?
        admission.replace(with: lifecycle)
        admission.configure { original in
            XCTAssertTrue(original === lifecycle)
            calls += 1
            controller = try AgentBridgeNativeCatalogRefresh(lifecycle: original) {
                _ = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: original, peer: rig.peer,
                    existingDirectory: rig.directory, sample: { facts }, loadStore: { _ in store })
                published.fulfill()
            }
        }
        admission.configure { _ in XCTFail("Native dependencies were replaced") }
        XCTAssertEqual(calls, 0, "Native admission must not run on the wire handler stack")
        await fulfillment(of: [published], timeout: 3)
        admission.replace(with: lifecycle)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        admission.replace(with: nil)
        controller?.stop()
        XCTAssertThrowsError(try lifecycle.currentPublication())
    }

    func testNativeAdmissionOwnerReplacementCancelsQueuedIdentityBeforeSampling() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let admission = AgentBridgeNativeCatalogAdmission()
        let old = AgentBridgeNativeCatalogLifecycle(), current = AgentBridgeNativeCatalogLifecycle()
        let facts = try nativeState(), store = rig.store
        let published = expectation(description: "only replacement published")
        var controller: AgentBridgeNativeCatalogRefresh?
        var calls = 0
        admission.configure { original in
            calls += 1
            XCTAssertTrue(original === current)
            controller = try AgentBridgeNativeCatalogRefresh(lifecycle: original) {
                _ = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: original, peer: rig.peer,
                    existingDirectory: rig.directory, sample: { facts }, loadStore: { _ in store })
                published.fulfill()
            }
        }
        admission.replace(with: old)
        admission.replace(with: current)
        await fulfillment(of: [published], timeout: 3)
        XCTAssertEqual(calls, 1)
        XCTAssertThrowsError(try old.beginSample())
        XCTAssertEqual(try current.currentFacts(), facts)
        admission.replace(with: nil); controller?.stop()
    }

    func testNativeAdmissionCloseAndStoppedOwnerNeverInvokeSampler() async throws {
        let admission = AgentBridgeNativeCatalogAdmission(), lifecycle = AgentBridgeNativeCatalogLifecycle()
        let unexpected = expectation(description: "closed owner cannot enter SDK"); unexpected.isInverted = true
        admission.configure { _ in unexpected.fulfill() }
        admission.replace(with: lifecycle)
        admission.replace(with: nil)
        admission.replace(with: lifecycle) // A terminal identity cannot be renewed.
        await fulfillment(of: [unexpected], timeout: 0.15)
        XCTAssertThrowsError(try lifecycle.beginSample())
        admission.replace(with: nil)
    }

    func testNativeRefreshControllerSerializesAndCoalescesEventsAcrossActualPublication() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState(), store = rig.store
        let entered = expectation(description: "initial native sample suspended")
        let published = expectation(description: "fresh follow-up published")
        let extra = expectation(description: "no duplicate follow-up"); extra.isInverted = true
        let gate = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        var calls = 0
        let controller = try AgentBridgeNativeCatalogRefresh(lifecycle: lifecycle) {
            _ = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: lifecycle, peer: rig.peer,
                existingDirectory: rig.directory, sample: {
                    calls += 1
                    if calls == 1 { entered.fulfill(); for await _ in gate.stream { break } }
                    if calls > 2 { extra.fulfill() }
                    return facts
                }, loadStore: { _ in store })
            published.fulfill()
        }
        defer { gate.continuation.finish(); controller.stop() }
        await fulfillment(of: [entered], timeout: 3)
        XCTAssertEqual(calls, 1)
        try lifecycle.recordNativeEvent(); try lifecycle.recordNativeEvent()
        XCTAssertThrowsError(try lifecycle.currentPublication())
        XCTAssertThrowsError(try lifecycle.claimRefreshEvents()) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .busy)
        }
        gate.continuation.yield(())
        await fulfillment(of: [published], timeout: 3)
        await fulfillment(of: [extra], timeout: 0.15)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        XCTAssertNotNil(try rig.store.snapshot().nativeCatalog)
    }

    func testNativeRefreshControllerFailureWaitsForNativeEventWithoutSelfRetry() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState(), store = rig.store
        try lifecycle.observe(facts)
        try lifecycle.publish(to: store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let failed = expectation(description: "native refresh failed")
        let retried = expectation(description: "external event schedules refresh")
        let early = expectation(description: "no autonomous retry"); early.isInverted = true
        var calls = 0, allowRetry = false
        let controller = try AgentBridgeNativeCatalogRefresh(lifecycle: lifecycle) {
            calls += 1
            if calls == 1 { failed.fulfill(); throw AgentBridgeValidationError.busy }
            if !allowRetry { early.fulfill() }
            _ = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: lifecycle, peer: rig.peer,
                existingDirectory: rig.directory, sample: { facts }, loadStore: { _ in store })
            retried.fulfill()
        }
        defer { controller.stop() }
        await fulfillment(of: [failed], timeout: 3)
        await fulfillment(of: [early], timeout: 0.15)
        XCTAssertEqual(calls, 1)
        XCTAssertThrowsError(try lifecycle.currentPublication())
        allowRetry = true
        try lifecycle.recordNativeEvent()
        await fulfillment(of: [retried], timeout: 3)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
    }

    func testNativeRefreshControllerStopCancelsSamplerAndPermanentlyClosesOwner() async throws {
        let lifecycle = AgentBridgeNativeCatalogLifecycle()
        let entered = expectation(description: "native sampler entered")
        let ended = expectation(description: "native sampler canceled")
        let controller = try AgentBridgeNativeCatalogRefresh(lifecycle: lifecycle) {
            defer { ended.fulfill() }
            entered.fulfill()
            try await Task.sleep(for: .seconds(30))
        }
        await fulfillment(of: [entered], timeout: 3)
        controller.stop()
        await fulfillment(of: [ended], timeout: 3)
        XCTAssertThrowsError(try lifecycle.beginSample()) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
        XCTAssertThrowsError(try lifecycle.recordNativeEvent())
        XCTAssertThrowsError(try AgentBridgeNativeCatalogRefresh(lifecycle: lifecycle) { XCTFail("Closed owner restarted") })
    }

    func testNativeRefreshComposesMetadataAndPreservesUnchangedPublication() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), store = rig.store
        let metadata = HealthKitNativePlanningMetadata(providerAvailable: true,
            availableNativeMetricIDs: ["steps"], authorizationFlowSatisfied: true)
        let facts = metadata.planningFacts(sourceCalendarTimezone: try AgentBridgeZone("UTC"),
            configurationProtection: .locked, entitlement: .required,
            foregroundAvailable: true, protectedDataAvailable: true)
        let first = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: lifecycle, peer: rig.peer,
            existingDirectory: rig.directory, sample: { await Task.yield(); return facts }, loadStore: { _ in store })
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        let next = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: lifecycle, peer: rig.peer,
            existingDirectory: rig.directory, sample: { facts }, loadStore: { _ in store })
        XCTAssertEqual(first, next)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
    }

    func testNativeRefreshFailedStaleOrRevokedSamplerCannotOpenIssuerOrReuseCache() async throws {
        for outcome in ["failed", "event", "revoked"] {
            let rig = try Rig(); defer { rig.cleanup() }
            let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState(), store = rig.store
            try lifecycle.observe(facts)
            try lifecycle.publish(to: store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
            do {
                _ = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: lifecycle, peer: rig.peer,
                    existingDirectory: rig.directory, sample: {
                        await Task.yield()
                        if outcome == "failed" { throw AgentBridgeValidationError.busy }
                        if outcome == "event" { try lifecycle.observeNativeChange() }
                        if outcome == "revoked" { rig.session.revoke() }
                        return facts
                    }, loadStore: { _ in XCTFail("Rejected sampler opened issuer storage"); return store })
                XCTFail("Rejected sampler returned a publication")
            } catch {
                XCTAssertEqual(error as? AgentBridgeValidationError,
                    outcome == "failed" ? .busy : outcome == "event" ? .bindingChanged : .permissionRequired)
            }
            XCTAssertThrowsError(try lifecycle.currentPublication())
            XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        }
    }

    func testNativeRefreshCancellationRejectsBeforeStoreAndBeforePreCancelledSampler() async throws {
        for duringSample in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }
            let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState(), store = rig.store
            try lifecycle.observe(facts)
            try lifecycle.publish(to: store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let peer = rig.peer, directory = rig.directory
            let task = Task {
                if !duringSample { withUnsafeCurrentTask { $0?.cancel() } }
                return try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: lifecycle, peer: peer,
                    existingDirectory: directory, sample: {
                        XCTAssertTrue(duringSample)
                        withUnsafeCurrentTask { $0?.cancel() }
                        return facts
                    }, loadStore: { _ in XCTFail("Canceled refresh opened issuer storage"); return store })
            }
            do { _ = try await task.value; XCTFail("Canceled refresh returned success") }
            catch { XCTAssertTrue(error is CancellationError) }
            if duringSample { XCTAssertThrowsError(try lifecycle.currentPublication()) }
            else { XCTAssertEqual(try lifecycle.currentFacts(), facts) } // No work was started.
        }
    }

    func testNativeCatalogSampleRejectsEventsAcrossSuspensionAndWorkerAdmission() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
        let initial = try lifecycle.observe(facts, sampledDuring: lifecycle.beginSample())
        let store = rig.store
        let first = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer,
            existingDirectory: rig.directory, sample: initial, loadStore: { _ in store })
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        let sampling = try lifecycle.beginSample()
        await Task.yield() // A native event may arrive while SDK metadata is suspended.
        try lifecycle.observeNativeChange()
        XCTAssertThrowsError(try lifecycle.observe(facts, sampledDuring: sampling)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        let accepted = try lifecycle.observe(facts, sampledDuring: lifecycle.beginSample())
        try lifecycle.observeNativeChange() // Event after sample acceptance, before worker admission.
        do {
            _ = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer,
                existingDirectory: rig.directory, sample: accepted, loadStore: { _ in store })
            XCTFail("Stale sampled generation returned a publication")
        } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .bindingChanged) }
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertThrowsError(try lifecycle.currentPublication())
        let fresh = try lifecycle.observe(facts, sampledDuring: lifecycle.beginSample())
        let next = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer,
            existingDirectory: rig.directory, sample: fresh, loadStore: { _ in store })
        XCTAssertGreaterThan(next.revision, first.revision)
    }

    func testNativeCatalogSampleBindsExactOwnerAndChangedFactsGeneration() throws {
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), other = AgentBridgeNativeCatalogLifecycle()
        let ticket = try lifecycle.beginSample(), facts = try nativeState()
        XCTAssertThrowsError(try other.observe(facts, sampledDuring: ticket)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        _ = try lifecycle.observe(facts, sampledDuring: ticket)
        let preceding = try lifecycle.beginSample()
        _ = try lifecycle.observe(nativeState(zone: "UTC"), sampledDuring: preceding)
        XCTAssertThrowsError(try lifecycle.observe(facts, sampledDuring: preceding)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        let stopped = try lifecycle.beginSample()
        lifecycle.stop()
        XCTAssertThrowsError(try lifecycle.observe(facts, sampledDuring: stopped)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
        XCTAssertThrowsError(try lifecycle.beginSample())
    }

    func testNativeCatalogWorkerPublishesOffMainAndPreservesUnchangedGeneration() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
        try lifecycle.observe(facts)
        let store = rig.store
        let first = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer,
            existingDirectory: rig.directory, loadStore: { _ in
                XCTAssertFalse(Thread.isMainThread)
                return store
            })
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        let next = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer,
            existingDirectory: rig.directory, loadStore: { _ in store })
        XCTAssertEqual(next, first)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
    }

    func testNativeCatalogWorkerRechecksOwnerAtPreparedAndPostFsyncBoundaries() async throws {
        for afterSync in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }
            let lifecycle = AgentBridgeNativeCatalogLifecycle()
            try lifecycle.observe(nativeState())
            let session = rig.session, store = rig.store
            if afterSync { rig.publication.onPublished = { _ in session.revoke() } }
            else { rig.publication.onPrepared = { _ in session.revoke() } }
            do {
                _ = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer,
                    existingDirectory: rig.directory, loadStore: { _ in store })
                XCTFail("Revoked native owner must suppress publication return")
            } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
            XCTAssertThrowsError(try lifecycle.currentFacts()) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
            rig.publication.onPrepared = nil; rig.publication.onPublished = nil
            XCTAssertEqual(try rig.store.snapshot().nativeCatalog != nil, afterSync)
        }
    }

    func testNativeCatalogWorkerCancellationDuringKeyReadCannotReopenPublishedCache() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
        try lifecycle.observe(facts)
        try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        rig.keys.onNextLoad { entered.signal(); release.wait() }
        let store = rig.store, peer = rig.peer, directory = rig.directory
        let task = Task { try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: peer,
            existingDirectory: directory, loadStore: { _ in store }) }
        let reached = await Task.detached { entered.wait(timeout: .now() + 5) == .success }.value
        guard reached else { release.signal(); task.cancel(); _ = try? await task.value; return XCTFail("Worker never reached key boundary") }
        task.cancel()
        release.signal()
        do { _ = try await task.value; XCTFail("Canceled worker returned publication") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertThrowsError(try lifecycle.currentFacts()) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
    }

    func testNativeCatalogWorkerCancellationDuringFinalTrustCheckRejectsReturn() async throws {
        let checkCount = try await nativePublisherCheckCount()

        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(nativeState())
        let cancel = PublicationTaskCancellation(), store = rig.store
        let finalCheck = rig.session.checks + checkCount
        rig.session.observeChecks { if $0 == finalCheck { cancel.request() } }
        let peer = rig.peer, directory = rig.directory
        let task = Task { try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: peer,
            existingDirectory: directory, loadStore: { _ in store }) }
        cancel.install(task)
        do { _ = try await task.value; XCTFail("Cancellation during final trust check returned success") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(cancel.requested)
        XCTAssertThrowsError(try lifecycle.currentFacts()) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
    }

    private func nativePublisherCheckCount() async throws -> Int {
        // Fresh stores follow the same transaction, so identify the final callback without encoding
        // the implementation's signing/fsync check count in a regression.
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(nativeState())
        let before = rig.session.checks, store = rig.store
        _ = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer,
            existingDirectory: rig.directory, loadStore: { _ in store })
        let count = rig.session.checks - before
        XCTAssertGreaterThan(count, 0)
        return count
    }

    func testNativeCatalogMetadataChangeDuringFinalTrustCheckRejectsReturn() async throws {
        let checkCount = try await nativePublisherCheckCount()
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(nativeState())
        let finalCheck = rig.session.checks + checkCount, store = rig.store
        rig.session.observeChecks { if $0 == finalCheck { try? lifecycle.observeNativeChange() } }
        do {
            _ = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer,
                existingDirectory: rig.directory, loadStore: { _ in store })
            XCTFail("Metadata changed during final trust check but stale publication was returned")
        } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .bindingChanged) }
        XCTAssertThrowsError(try lifecycle.currentFacts())
    }

    func testNativeCatalogAlreadyCancelledWorkerDoesNotLoadPrivateStore() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(nativeState())
        let store = rig.store, keys = rig.keys, peer = rig.peer, directory = rig.directory
        let before = keys.loads
        let task = Task {
            try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: peer,
                existingDirectory: directory, loadStore: { _ in
                    _ = try keys.loadExistingExportAuthorityKey()
                    return store
                })
        }
        task.cancel() // This actor has not yielded, so the async entry sees cancellation first.
        do { _ = try await task.value; XCTFail("Already canceled native task returned publication") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(keys.loads, before)
    }

    func testNativeCatalogWorkerDoesNotCreateMissingPrivateStore() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(nativeState())
        let missing = rig.parent.appendingPathComponent("missing-native-authority")
        do {
            _ = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer, existingDirectory: missing)
            XCTFail("Missing authority must not bootstrap")
        } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .bindingChanged) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertThrowsError(try lifecycle.currentFacts())
    }

    func testNativeCatalogResamplesAtStagedAndPostFsyncPublicationBoundaries() throws {
        for afterSync in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }
            var facts = try nativeState()
            let unavailable = try nativeState(foregroundAvailable: false)
            let file = rig.directory.appendingPathComponent("state.json"), before = try Data(contentsOf: file)
            var observed = false
            if afterSync { rig.publication.onPublished = { _ in observed = true; facts = unavailable } }
            else { rig.publication.onPrepared = { _ in observed = true; facts = unavailable } }
            XCTAssertThrowsError(try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
            XCTAssertTrue(observed)
            rig.publication.onPrepared = nil; rig.publication.onPublished = nil
            if afterSync {
                let retained = try XCTUnwrap(rig.store.snapshot().nativeCatalog)
                XCTAssertNotEqual(retained.factsSHA256, try facts.fingerprint(sourceInstallationID: rig.peer.peer.sourceInstallationID))
                let next = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }
                XCTAssertEqual(next.revision, 2) // Postpublication failure never rolls a counter back.
            } else { XCTAssertEqual(try Data(contentsOf: file), before) }
        }
    }

    func testNativeCatalogDoesNotRepairMissingStateOrKeyAndRejectsSourceRebinding() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let facts = try nativeState(), file = rig.directory.appendingPathComponent("state.json")
        let publication = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }
        let before = try Data(contentsOf: file)
        XCTAssertThrowsError(try rig.store.publishNativeCatalog(sourceInstallationID: id(99)) { facts }) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        let locked = try AgentBridgeExportAuthorityStore(existingDirectory: rig.directory, protectedKeys: FakeProtectedKeys(key: nil))
        var samples = 0
        XCTAssertThrowsError(try locked.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { samples += 1; return facts }) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
        XCTAssertEqual(samples, 0); XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(try rig.store.snapshot().nativeCatalog, publication)
        try FileManager.default.removeItem(at: file)
        XCTAssertThrowsError(try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { samples += 1; return facts })
        XCTAssertEqual(samples, 0); XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testExhaustedNativeCatalogAllowsExactRetryButCannotResetOrAdvance() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let facts = try nativeState()
        let first = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }
        var fixture = try rig.store.snapshot()
        fixture.nativeCatalog = .init(revision: Int64(Int32.max), sourceInstallationID: first.sourceInstallationID, factsSHA256: first.factsSHA256)
        // Independent signed boundary fixture, using the synthetic protected key and production
        // private payload grammar. No production mutation/reset or test-only writer API is added.
        let payload = try AgentBridgeV4Codec.canonicalize(JSONEncoder().encode(fixture))
        let mac = Data(HMAC<SHA256>.authenticationCode(for: Data("HealthMd.AgentBridge.NativeExportAuthorityStore.v1\0".utf8) + payload,
            using: try XCTUnwrap(rig.keys.key)))
        let signed: [String: Any] = ["version": 2, "state": try JSONSerialization.jsonObject(with: payload), "mac": mac.base64EncodedString()]
        let file = rig.directory.appendingPathComponent("state.json")
        let before = try AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: signed))
        try before.write(to: file)
        XCTAssertEqual(try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }.revision, Int64(Int32.max))
        XCTAssertThrowsError(try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID,
            invalidatingObservedChange: true) { facts }) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .busy)
        }
        XCTAssertEqual(try Data(contentsOf: file), before)
        let changed = try nativeState(foregroundAvailable: false)
        XCTAssertThrowsError(try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { changed }) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .busy)
        }
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testEveryAdvertisedNativeFactChangeAdvancesItsPublicationIdentity() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let base = try nativeState()
        let first = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { base }
        let alternatives = try [nativeState(available: ["steps"]), nativeState(zone: "UTC"), nativeState(protection: .unlockedNative),
            nativeState(grants: .required), nativeState(grants: .unverified), nativeState(entitlement: .required),
            nativeState(foregroundAvailable: false), nativeState(protectedDataAvailable: false)]
        var revision: Int64 = 1
        for changed in alternatives {
            let next = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { changed }
            revision += 1
            XCTAssertEqual(next.revision, revision)
            XCTAssertNotEqual(next.factsSHA256, first.factsSHA256)
            let restored = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { base }
            revision += 1
            XCTAssertEqual(restored.revision, revision)
            XCTAssertEqual(restored.factsSHA256, first.factsSHA256)
        }
        XCTAssertTrue(try rig.store.snapshot().delegations.isEmpty)
        XCTAssertTrue(try rig.store.snapshot().plans.isEmpty)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
    }

    func testPrivateCatalogVersionRequiresExactlyItsPublicationShape() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let facts = try nativeState()
        _ = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }
        let state = try rig.store.snapshot(), file = rig.directory.appendingPathComponent("state.json")
        for dropCatalog in [false, true] {
            var fixture = state
            if dropCatalog { fixture.nativeCatalog = nil }
            let payload = try AgentBridgeV4Codec.canonicalize(JSONEncoder().encode(fixture))
            let mac = Data(HMAC<SHA256>.authenticationCode(for: Data("HealthMd.AgentBridge.NativeExportAuthorityStore.v1\0".utf8) + payload,
                using: try XCTUnwrap(rig.keys.key)))
            let signed: [String: Any] = ["version": dropCatalog ? 2 : 1,
                "state": try JSONSerialization.jsonObject(with: payload), "mac": mac.base64EncodedString()]
            let bytes = try AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: signed))
            try bytes.write(to: file)
            var samples = 0
            XCTAssertThrowsError(try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { samples += 1; return facts }) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
            XCTAssertEqual(samples, 0); XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testDiscoveryAndPlanningKeepPolicySupportStableWhenOnlySelectedConfigurationIsLoaded() throws {
        for kind in ["explicit", "saved", "profile"] {
            let rig = try Rig(withSaved: true); defer { rig.cleanup() }; try rig.enroll()
            let discovery = try rig.discover()
            XCTAssertEqual(discovery.settingsPolicies, [.explicit, .profile, .savedDeviceSettings])
            XCTAssertEqual(rig.reader.defaults.reads, 0)
            let policy: AgentBridgeSettingsPolicy
            switch kind {
            case "saved": policy = .savedDeviceSettings(expectedRevision: 7)
            case "profile": policy = .profile(profileID: try id(50), expectedRevision: 7)
            default: policy = .explicit(output())
            }
            let response = try rig.send(.planRequest(rig.request(discovery: discovery, policy: policy)))
            guard case .plan(let plan) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: response).payload else {
                return XCTFail("The selected configuration must not change supported policy metadata")
            }
            XCTAssertEqual(plan.intent.settingsPolicy, policy)
            XCTAssertEqual(try rig.service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer), plan)
            XCTAssertEqual(rig.reader.defaults.writes, 0)
            if kind == "explicit" { XCTAssertEqual(rig.reader.defaults.reads, 0) }
            else { XCTAssertGreaterThan(rig.reader.defaults.reads, 0) }
        }
    }

    func testNativePlanReviewUsesStoredPlanWithoutIssuingConsentOrChangingPreferences() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), path = rig.directory.appendingPathComponent("state.json")
        let before = try Data(contentsOf: path), generation = try rig.store.snapshot().generation
        let reads = rig.reader.defaults.reads, writes = rig.reader.defaults.writes
        let reviewed = try rig.service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)
        XCTAssertEqual(reviewed, plan)
        XCTAssertEqual(try AgentBridgeSemantics.binding(reviewed), try AgentBridgeSemantics.binding(plan))
        XCTAssertEqual(try rig.restartedService().reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer), plan)
        XCTAssertEqual(try Data(contentsOf: path), before)
        XCTAssertEqual(try rig.store.snapshot().generation, generation)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
        XCTAssertEqual(rig.reader.defaults.reads, reads); XCTAssertEqual(rig.reader.defaults.writes, writes)
        try rig.expectError(.approvalRequired, request: .approvalRequest(.init(
            binding: AgentBridgeSemantics.binding(reviewed), planId: plan.planId, requestId: id(104))))
    }

    func testNativePlanReviewRequiresExecutionDelegationAndNativeReadiness() throws {
        for mode in ["plan_only", "permission", "entitlement"] {
            let rig = try Rig(); defer { rig.cleanup() }
            if mode == "permission" { rig.reader.grants = .required }
            if mode == "entitlement" { rig.reader.entitlement = .required }
            let grant = try rig.grant()
            let eligible = try AgentBridgeExportDelegation(authorityID: grant.authorityID, issuer: grant.issuer,
                grantRevision: grant.grantRevision, peer: grant.peer,
                rights: mode == "plan_only" ? [.discover, .plan] : grant.rights,
                expiresAt: grant.expiresAt, bounds: grant.bounds)
            try rig.store.storeNativeDelegation(eligible, expectedGeneration: 0, authorization: FakeNativeAuthorization())
            let plan = try rig.makePlan(), path = rig.directory.appendingPathComponent("state.json")
            let before = try Data(contentsOf: path)
            XCTAssertThrowsError(try rig.service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)) {
                let expected: AgentBridgeValidationError = mode == "plan_only" ? .approvalRequired :
                    (mode == "entitlement" ? .entitlementRequired : .permissionRequired)
                XCTAssertEqual($0 as? AgentBridgeValidationError, expected)
            }
            XCTAssertEqual(try Data(contentsOf: path), before)
        }
    }

    func testNativePlanReviewRechecksLiveTrustConfigurationAndExpiryBeforeReturn() throws {
        for mode in ["permission", "configuration", "expiry"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let plan = try rig.makePlan(), path = rig.directory.appendingPathComponent("state.json")
            let before = try Data(contentsOf: path)
            var reads = 0
            rig.reader.beforeReturn = {
                reads += 1
                guard reads == 2 else { return }
                switch mode {
                case "permission": rig.session.revoke()
                case "configuration": rig.reader.available.remove("steps")
                default: rig.clock.advance(seconds: 600)
                }
            }
            XCTAssertThrowsError(try rig.service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)) {
                let expected: AgentBridgeValidationError = mode == "permission" ? .permissionRequired :
                    (mode == "configuration" ? .unsupportedMetric : .planExpired)
                XCTAssertEqual($0 as? AgentBridgeValidationError, expected)
            }
            XCTAssertEqual(reads, 2)
            XCTAssertEqual(try Data(contentsOf: path), before)
            rig.reader.beforeReturn = nil
        }
    }

    func testNativePlanReviewRejectsForeignPeerAndUnknownPlanWithoutWrites() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), path = rig.directory.appendingPathComponent("state.json")
        let before = try Data(contentsOf: path)
        let source = try XCTUnwrap(UUID(uuidString: id(1).rawValue)), host = try XCTUnwrap(UUID(uuidString: id(99).rawValue))
        let session = try RevocableNativeSession(source: source, host: host)
        let foreign = try AgentBridgeExportAuthenticatedPeer(nativeSourceInstallationID: source,
            authenticatedHostInstallationID: host, currentNativeSession: session)
        XCTAssertThrowsError(try rig.service.reviewNativePlan(planID: plan.planId, authenticatedPeer: foreign)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        XCTAssertThrowsError(try rig.service.reviewNativePlan(planID: id(99), authenticatedPeer: rig.peer))
        XCTAssertEqual(try Data(contentsOf: path), before)
    }

    func testNativePlanReviewDoesNotRetainAuthorityAfterRevocationOrClockAdvance() throws {
        for revoke in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let plan = try rig.makePlan()
            let reviewed = try rig.service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)
            if revoke {
                try rig.store.revokeNativeDelegation(rig.grant().reference(), expectedGeneration: rig.store.snapshot().generation,
                    authorization: FakeNativeAuthorization())
            } else { rig.clock.advanceAfterNextSample(seconds: 600) }
            let path = rig.directory.appendingPathComponent("state.json"), before = try Data(contentsOf: path)
            XCTAssertThrowsError(try rig.service.reviewNativePlan(planID: reviewed.planId, authenticatedPeer: rig.peer)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, revoke ? .approvalRequired : .planExpired)
            }
            XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: reviewed.planId, binding: AgentBridgeSemantics.binding(reviewed),
                approvalID: id(8), authenticatedPeer: rig.peer,
                authorization: LiveExactApprovalAuthorization(planID: reviewed.planId, binding: AgentBridgeSemantics.binding(reviewed))))
            XCTAssertEqual(try Data(contentsOf: path), before)
        }
    }

    func testExactNativeApprovalRejectsConsentLostDuringKeyAndConfigurationReads() throws {
        for duringKey in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
            let path = rig.directory.appendingPathComponent("state.json")
            let before = try Data(contentsOf: path)
            let native = LiveExactApprovalAuthorization(planID: plan.planId, binding: binding)
            var observed = false
            native.onCheck = { count in
                if count == 1 {
                    let loseConsent = { observed = true; native.allowed = false }
                    if duringKey { rig.keys.onNextLoad(loseConsent) }
                    else { rig.reader.beforeReturn = loseConsent }
                }
            }
            XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer, authorization: native)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .approvalRequired)
            }
            rig.reader.beforeReturn = nil
            XCTAssertTrue(observed)
            XCTAssertEqual(try Data(contentsOf: path), before)
            XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
            XCTAssertEqual(rig.reader.defaults.writes, 0)
        }
    }

    func testExactNativeApprovalRechecksConsentAtStagingPublicationAndFinalKeyRead() throws {
        for phase in ["staging", "publication", "return_key"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
            let path = rig.directory.appendingPathComponent("state.json")
            let before = try Data(contentsOf: path)
            let native = LiveExactApprovalAuthorization(planID: plan.planId, binding: binding)
            var observed = false
            if phase == "staging" {
                rig.publication.onPrepared = { candidate in
                    XCTAssertEqual(candidate.decisions.count, 1)
                    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: rig.directory.path).contains { $0.hasPrefix("transaction-") })
                    observed = true; native.allowed = false
                }
            } else {
                rig.publication.onPublished = { candidate in
                    XCTAssertEqual(candidate.decisions.count, 1)
                    if phase == "return_key" { rig.keys.onNextLoad { observed = true; native.allowed = false } }
                    else { observed = true; native.allowed = false }
                }
            }
            XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer, authorization: native)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .approvalRequired)
            }
            XCTAssertTrue(observed)
            if phase == "staging" {
                XCTAssertEqual(try Data(contentsOf: path), before)
                XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
            } else {
                XCTAssertNotEqual(try Data(contentsOf: path), before)
                let approval = try XCTUnwrap(rig.store.snapshot().decisions.first).approval()
                XCTAssertEqual(approval.binding, binding) // Retain the already committed exact decision; never roll back.
                XCTAssertEqual(approval.approvedAt.rawValue, "2026-03-09T00:00:00Z")
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: rig.directory.path).sorted(), ["lock", "state.json"])
        }
    }

    func testExactNativeApprovalSamplesLiveExpiryAfterRepeatedNativeCheck() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        let path = rig.directory.appendingPathComponent("state.json")
        let before = try Data(contentsOf: path)
        let native = LiveExactApprovalAuthorization(planID: plan.planId, binding: binding)
        var delayed = false
        native.onCheck = { count in if count == 2 { delayed = true; rig.clock.advance(seconds: 600) } }
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer, authorization: native)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired)
        }
        XCTAssertTrue(delayed)
        XCTAssertEqual(try Data(contentsOf: path), before)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
    }

    func testMissingAuthorityNeverCreatesStoreGrantKeyOrDecision() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let missing = rig.parent.appendingPathComponent("missing")
        XCTAssertThrowsError(try AgentBridgeExportAuthorityStore(existingDirectory: missing, protectedKeys: rig.keys))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        let absentKeys = FakeProtectedKeys(key: nil)
        XCTAssertThrowsError(try AgentBridgeExportAuthorityStore.createPrivateStore(at: missing, protectedKeys: absentKeys, authorization: FakeNativeAuthorization()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        let discovery = try rig.discover()
        XCTAssertTrue(discovery.authorityReferences.isEmpty)
        XCTAssertEqual(discovery.features, [.explicitSettings, .zeroHealthPlan])
        XCTAssertEqual(discovery.queryCatalogSha256.rawValue, String(repeating: "0", count: 64))
        XCTAssertTrue(discovery.queryOperations.isEmpty)
        XCTAssertTrue(discovery.projectionProducts.isEmpty)
        let reads = rig.reader.calls.count
        try rig.expectError(.approvalRequired, request: .planRequest(rig.request(discovery: discovery)))
        XCTAssertEqual(rig.reader.calls.count, reads) // Reject missing private authority BEFORE configuration lookup.
        try rig.expectError(.bindingChanged, request: .approvalRequest(.init(binding: rig.unissuedBinding(discovery: discovery), planId: id(6), requestId: id(103))))
        let empty = try rig.store.snapshot()
        XCTAssertEqual(empty.generation, 0)
        XCTAssertEqual(empty.delegations.count + empty.plans.count + empty.decisions.count, 0)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
    }

    func testNativePreapprovedTracerUsesProductionResolverAndNormativeResponse() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        try rig.enroll()
        let discovery = try rig.discover()
        let request = try rig.request(discovery: discovery, metrics: ["hrv", "steps"])
        let response = try rig.send(.planRequest(request))
        guard case .plan(let plan) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: response).payload else { return XCTFail("plan required") }
        XCTAssertEqual(plan.planId, try id(6))
        XCTAssertEqual(plan.resolvedDates, try .exact(.init(startDate: date("2026-03-07"), endDate: date("2026-03-08"))))
        XCTAssertEqual(plan.predictedPaths.map(\.rawValue), ["2026/2026-03-07.json", "2026/2026-03-08.json"])
        XCTAssertEqual(plan.resolvedMetricIds.map(\.rawValue), ["hrv", "steps"])
        XCTAssertEqual(plan.effectiveSettings, output())
        XCTAssertEqual(plan.pathPrediction, .exactRequestedDays)
        XCTAssertTrue(plan.requiredActions.isEmpty)
        XCTAssertEqual(plan.limitations.map(\.rawValue), ["healthkit_read_authorization_unobservable"])
        XCTAssertEqual(plan.expiresAt.rawValue, "2026-03-09T00:10:00Z")
        XCTAssertEqual(plan.authorityReferences.native, try rig.grant().reference())
        XCTAssertEqual(plan.authorityReferences.host, request.hostAuthorityReference)
        XCTAssertEqual(plan.revisions, [])
        let expectedOrigins = outputPointers.map { AgentBridgeOrigin(origin: .request, pointer: "/effective_settings" + $0, revision: 0) } + capturePointers.map { .init(origin: .request, pointer: $0, revision: 0) } + [.init(origin: .request, pointer: "/calendar_timezone", revision: 0), .init(origin: .resolvedCalendar, pointer: "/resolved_dates", revision: 0)]
        XCTAssertEqual(plan.origins, expectedOrigins.sorted { $0.pointer < $1.pointer })
        // Independent literal byte oracle is constructed before any fixture comparison. The expected
        // response pins all effective/capture leaves, not just a digest or a fixture verdict.
        XCTAssertEqual(AgentBridgeV4Codec.sha256(response), Self.tracerResponseSHA256)
        XCTAssertEqual(response, try AgentBridgeV4Codec.canonicalize(response))
        let native = try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: rig.peer)
        XCTAssertEqual(native.issuer, .nativeSource)
        XCTAssertEqual(native.authorityId, plan.authorityReferences.native.authorityId)
        XCTAssertEqual(native.scopeSha256, plan.scopeSha256)
        XCTAssertEqual(native.configurationProtection, .notApplicable)
        XCTAssertEqual(native.rights, [.discover, .exportExecute, .plan])
        XCTAssertNil(native.controlReadScope)
        // Actual resolver's native SDNN mapping, not a Health Connect RMSSD alias.
        let resolved = try AgentBridgeRequestSettingsResolver.resolveWithOutput(request.intent, inputs: rig.reader.inputs, clock: rig.now, calendar: rig.calendar)
        XCTAssertEqual(resolved.native.selection.map(\.sourceSelector), ["HKQuantityTypeIdentifierHeartRateVariabilitySDNN", "HKQuantityTypeIdentifierStepCount"])
        XCTAssertEqual(resolved.native.selection.map(\.sourceReducer), ["discreteAvg", "cumulative"])
        XCTAssertEqual(resolved.native.selection.map(\.canonicalUnit), ["ms", "steps"])
        XCTAssertEqual(try rig.store.snapshot().plans.count, 1)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
        XCTAssertEqual(rig.reader.defaults.reads, 0)
        let effects = try JSONSerialization.jsonObject(with: AgentBridgeV4Codec.encode(plan.sideEffects)) as? [String: Int]
        XCTAssertEqual(effects, ["health_reads": 0, "earliest_date_reads": 0, "content_preview_reads": 0, "quota_consumed": 0, "output_writes": 0, "settings_mutations": 0, "credential_enrollments": 0, "wake_enrollments": 0])
    }

    func testExpiryDuringNativeConsentNeverPersistsALateDecision() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        var consentCompleted = false
        let native = FakeNativeAuthorization(binding: binding, afterAuthorization: {
            consentCompleted = true
            rig.clock.advance(seconds: 600) // Exact issued-plan expiry, while the real native callback runs.
        })
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                               authorization: native)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired) }
        XCTAssertTrue(consentCompleted)
        XCTAssertEqual(rig.now, ISO8601DateFormatter().date(from: "2026-03-09T00:10:00Z"))
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testApprovalRelayRequiresIndependentExactNativeDecisionAndSurvivesRestart() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan()
        let approvalRequest = AgentBridgeApprovalRequest(binding: AgentBridgeSemantics.binding(plan), planId: plan.planId, requestId: try id(103))
        let before = try rig.store.snapshot().generation
        try rig.expectError(.approvalRequired, request: .approvalRequest(approvalRequest))
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: approvalRequest.binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                               authorization: FakeNativeAuthorization(deny: true)))
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
        try rig.service.storeNativeDecision(planID: plan.planId, binding: approvalRequest.binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                            authorization: FakeNativeAuthorization(binding: approvalRequest.binding))
        let bytes = try rig.send(.approvalRequest(approvalRequest))
        let restarted = try rig.restartedService()
        rig.clock.advance(seconds: 30)
        let replay = try restarted.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .approvalRequest(approvalRequest))), authenticatedPeer: rig.peer)
        XCTAssertEqual(bytes, replay)
        guard case .approval(let approval) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes).payload else { return XCTFail("approval required") }
        XCTAssertEqual(approval.approvalId, try id(8))
        XCTAssertEqual(approval.binding, approvalRequest.binding)
        XCTAssertEqual(approval.approvedAt.rawValue, "2026-03-09T00:00:00Z")
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 1)
    }

    func testLiveClockRejectsCachedPlanAfterProtectedKeyDelay() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        _ = try rig.makePlan()
        let state = try rig.store.snapshot(), request = try state.plans[0].request()
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        let loads = rig.keys.loads
        rig.keys.onNextLoad { rig.clock.advance(seconds: 600) }
        let reply = try rig.send(.planRequest(request))
        XCTAssertEqual(try? error(reply), .planExpired)
        XCTAssertGreaterThan(rig.keys.loads, loads)
        XCTAssertEqual(rig.now, ISO8601DateFormatter().date(from: "2026-03-09T00:10:00Z"))
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 1)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testLiveClockRejectsPlanAfterConfigurationCrossesParentExpiry() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll(expires: "2026-03-09T00:01:00Z")
        let request = try rig.request(discovery: rig.discover())
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        var delayed = false
        rig.reader.beforeReturn = {
            if !delayed { delayed = true; rig.clock.advance(seconds: 60) }
        }
        let reply = try rig.send(.planRequest(request))
        XCTAssertEqual(try? error(reply), .approvalRequired)
        XCTAssertTrue(delayed)
        XCTAssertEqual(rig.now, ISO8601DateFormatter().date(from: "2026-03-09T00:01:00Z"))
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 0)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testLiveClockRejectsScopedAuthorityAtLastSessionCallback() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan()
        let start = rig.session.checks
        _ = try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: rig.peer)
        let checksPerReturn = rig.session.checks - start
        let finalCheck = rig.session.checks + checksPerReturn
        var advanced = false
        rig.session.observeChecks { count in
            if count == finalCheck { advanced = true; rig.clock.advance(seconds: 600) }
        }
        XCTAssertThrowsError(try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired)
        }
        XCTAssertTrue(advanced) // Observed callback at the last fence of an otherwise identical return.
        XCTAssertEqual(rig.session.checks, finalCheck)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
    }

    func testLiveClockRejectsCachedApprovalAtLastSessionCallback() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                            authorization: FakeNativeAuthorization(binding: binding))
        let request = AgentBridgeDocument.approvalRequest(.init(binding: binding, planId: plan.planId, requestId: try id(103)))
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), start = rig.session.checks
        _ = try rig.send(request)
        let finalCheck = rig.session.checks + (rig.session.checks - start)
        var advanced = false
        rig.session.observeChecks { count in
            if count == finalCheck { advanced = true; rig.clock.advance(seconds: 600) }
        }
        let reply = try rig.send(request)
        XCTAssertEqual(try? error(reply), .planExpired)
        XCTAssertTrue(advanced)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 1) // Not renewed/evicted.
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testPublicationClockRejectsPlanBeforeAtomicRenameAfterFsync() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try rig.request(discovery: rig.discover())
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        var prepared = false
        rig.publication.onPrepared = { candidate in
            prepared = true
            XCTAssertEqual(candidate.plans.count, 1)
            XCTAssertEqual(candidate.decisions.count, 0)
            XCTAssertEqual(candidate.generation, 2)
            let temporary = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: rig.directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("transaction-") })
            let serialized = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: temporary)) as? [String: Any])
            XCTAssertEqual((serialized["state"] as? [String: Any])?["generation"] as? Int, 2)
            rig.clock.advance(seconds: 600) // The actual private candidate is serialized and fsync'ed.
        }
        let reply = try rig.send(.planRequest(request))
        XCTAssertEqual(try? error(reply), .planExpired)
        XCTAssertTrue(prepared)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 0)
        XCTAssertEqual(try rig.store.snapshot().generation, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: rig.directory.path).sorted(), ["lock", "state.json"])
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testPublicationClockRejectsDecisionBeforeAtomicRenameAfterFsync() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        var prepared = false
        rig.publication.onPrepared = { candidate in
            prepared = true
            XCTAssertEqual(candidate.plans.count, 1)
            XCTAssertEqual(candidate.decisions.count, 1)
            XCTAssertEqual(candidate.generation, 3)
            rig.clock.advance(seconds: 600)
        }
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                               authorization: FakeNativeAuthorization(binding: binding))) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired)
        }
        XCTAssertTrue(prepared)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
        XCTAssertEqual(try rig.store.snapshot().generation, 2)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testDecisionTimestampIsPostConsentAndExactRetryNeverRenewsIt() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        var consentCompleted = false
        try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
            authorization: FakeNativeAuthorization(binding: binding, afterAuthorization: {
                consentCompleted = true; rig.clock.advance(seconds: 30)
            }))
        XCTAssertTrue(consentCompleted)
        let approval = try XCTUnwrap(rig.store.snapshot().decisions.first).approval()
        XCTAssertEqual(approval.approvedAt.rawValue, "2026-03-09T00:00:30Z")
        XCTAssertEqual(approval.binding.expiresAt, plan.expiresAt)
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        rig.clock.advance(seconds: 50)
        try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                            authorization: FakeNativeAuthorization(binding: binding))
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try rig.store.snapshot().decisions[0].approval(), approval)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testProtectedKeyDelayAfterNativeConsentCannotPublishDecision() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        var delayedKeyLoaded = false
        let native = FakeNativeAuthorization(binding: binding, afterAuthorization: {
            rig.keys.onNextLoad { delayedKeyLoaded = true; rig.clock.advance(seconds: 600) }
        })
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                               authorization: native)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired) }
        XCTAssertTrue(delayedKeyLoaded)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
    }

    func testNativeConsentCannotMaskCurrentConfigOrGrantRevocation() throws {
        for revokeGrant in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
            let before = try rig.store.snapshot().generation
            var consentCompleted = false
            let native = FakeNativeAuthorization(binding: binding, afterAuthorization: {
                consentCompleted = true
                if revokeGrant {
                    try! rig.store.revokeNativeDelegation(binding.authorityReferences.native, expectedGeneration: before, authorization: FakeNativeAuthorization())
                } else { rig.reader.grants = .required }
            })
            XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                                   authorization: native)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, revokeGrant ? .revisionConflict : .bindingChanged)
            }
            XCTAssertTrue(consentCompleted)
            let state = try rig.store.snapshot()
            XCTAssertEqual(state.decisions.count, 0)
            XCTAssertEqual(state.generation, before + (revokeGrant ? 1 : 0))
            XCTAssertEqual(state.delegations[0].revoked, revokeGrant)
            XCTAssertEqual(rig.reader.defaults.writes, 0)
        }
    }

    func testExpiryAfterPublicationSuppressesPlanAndRetainsUnusableMetadata() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try rig.request(discovery: rig.discover())
        var published = false
        rig.publication.onPublished = { current in
            published = true
            XCTAssertEqual(current.plans.count, 1)
            XCTAssertEqual(current.generation, 2)
            rig.clock.advance(seconds: 600) // Atomic rename/root fsync ALREADY succeeded.
        }
        XCTAssertEqual(try? error(rig.send(.planRequest(request))), .planExpired)
        XCTAssertTrue(published)
        let state = try rig.store.snapshot(), plan = try state.plans[0].plan()
        XCTAssertEqual(state.generation, 2)
        XCTAssertEqual(state.decisions.count, 0)
        XCTAssertEqual(plan.expiresAt.rawValue, "2026-03-09T00:10:00Z")
        let bytes = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        rig.publication.onPublished = nil
        XCTAssertThrowsError(try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: rig.peer)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired) }
        try rig.expectError(.planExpired, request: .planRequest(request))
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: AgentBridgeSemantics.binding(plan), approvalID: id(8), authenticatedPeer: rig.peer,
                                                               authorization: FakeNativeAuthorization(binding: AgentBridgeSemantics.binding(plan)))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired) }
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), bytes)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 1) // No eviction/recreation or expiry renewal.
    }

    func testExpiryAfterDecisionPublicationSuppressesReturnAndEveryLaterAuthorityUse() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        var published = false
        rig.publication.onPublished = { current in
            published = true
            XCTAssertEqual(current.decisions.count, 1)
            rig.clock.advance(seconds: 600)
        }
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                               authorization: FakeNativeAuthorization(binding: binding))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired) }
        XCTAssertTrue(published)
        let state = try rig.store.snapshot(), approval = try state.decisions[0].approval()
        XCTAssertEqual(state.generation, 3)
        XCTAssertEqual(approval.approvedAt.rawValue, "2026-03-09T00:00:00Z") // It was valid AT publication, not late consent.
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        rig.publication.onPublished = nil
        let request = AgentBridgeDocument.approvalRequest(.init(binding: binding, planId: plan.planId, requestId: try id(103)))
        XCTAssertEqual(try? error(rig.send(request)), .planExpired)
        XCTAssertEqual(try? error(rig.restartedService().handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: request)), authenticatedPeer: rig.peer)), .planExpired)
        XCTAssertThrowsError(try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: rig.peer)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired) }
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testRevocationAtPublicationRejectsBeforeRenameAndAfterPublicationSuppressesReturn() throws {
        for afterRename in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try rig.request(discovery: rig.discover())
            let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
            var revoked = false
            let revoke: (AgentBridgeExportAuthoritySnapshot) throws -> Void = { _ in revoked = true; rig.session.revoke() }
            if afterRename { rig.publication.onPublished = revoke } else { rig.publication.onPrepared = revoke }
            XCTAssertThrowsError(try rig.send(.planRequest(request))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
            XCTAssertTrue(revoked)
            let state = try rig.store.snapshot()
            XCTAssertEqual(state.plans.count, afterRename ? 1 : 0)
            XCTAssertEqual(state.decisions.count, 0)
            XCTAssertEqual(state.generation, afterRename ? 2 : 1)
            if !afterRename { XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before) }
            XCTAssertEqual(rig.reader.defaults.writes, 0)
        }
    }

    func testDiscoveryNeverReturnsParentExpiredDuringFinalSessionCallback() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll(expires: "2026-03-09T00:01:00Z")
        let start = rig.session.checks
        _ = try rig.discover()
        let finalCheck = rig.session.checks + (rig.session.checks - start)
        var advanced = false
        rig.session.observeChecks { count in
            if count == finalCheck { advanced = true; rig.clock.advance(seconds: 60) }
        }
        let bytes = try rig.send(.discoveryRequest(.init(requestID: id(104), peer: rig.peer.peer)))
        XCTAssertEqual(try? error(bytes), .approvalRequired)
        XCTAssertTrue(advanced)
        XCTAssertEqual(try rig.store.snapshot().generation, 1)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 0)
    }

    func testDiscoveryRechecksParentAfterResponseHashWork() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll(expires: "2026-03-09T00:01:00Z")
        let finalRead = rig.reader.calls.count + 2
        rig.reader.beforeReturn = {
            if rig.reader.calls.count == finalRead { rig.clock.advanceAfterNextSample(seconds: 60) }
        }
        // Final validation first samples time, then performs canonical capability hashing. Model
        // wall time advancing immediately AFTER that sample, before its last return-time sample.
        let reply = try rig.send(.discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer)))
        XCTAssertEqual(try? error(reply), .approvalRequired)
        XCTAssertEqual(rig.now, ISO8601DateFormatter().date(from: "2026-03-09T00:01:00Z"))
        XCTAssertEqual(try rig.store.snapshot().generation, 1)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testGatedActualServiceDiscoveryCandidate() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let value = try rig.discover() // Native typed constructors + REAL stored production service.
        XCTAssertEqual(value.outputSupport.settingPointers, outputPointers)
        XCTAssertEqual(value.authorityReferences, [try rig.grant().reference()])
        XCTAssertEqual(value.outputSupport.formats, [.json])
        XCTAssertEqual(value.outputProfiles, [.appleV8])
        XCTAssertEqual(value.features, [.explicitSettings, .zeroHealthPlan])
        let bytes = try AgentBridgeV4Codec.encode(value)
        XCTAssertEqual(try AgentBridgeV4Codec.decode(AgentBridgeDiscovery.self, from: bytes), value)
        let environment = ProcessInfo.processInfo.environment
        guard environment["HEALTHMD_GENERATE_AGENT_BRIDGE_V4"] == "1" else { return }
        let path = try XCTUnwrap(environment["HEALTHMD_AGENT_BRIDGE_CANDIDATES"])
        let root = "/private/tmp/healthmd-agent-bridge-20261004/evidence/swift-planning-boundaries/"
        guard path == root + "native-discovery-candidates.json" else { throw AgentBridgeValidationError.unsafePath }
        guard !FileManager.default.fileExists(atPath: path) else { throw AgentBridgeValidationError.bindingChanged }
        try bytes.write(to: URL(fileURLWithPath: path), options: .atomic) // Standalone closed discovery DTO ONLY.
        let provenance: [String: Any] = ["format": "standalone healthmd.agent_discovery/1", "producer": "Swift actual AgentBridgeExportPlanningService", "test": "AgentBridgeExportPlanningTests.testGatedActualServiceDiscoveryCandidate", "stage": "after-live-boundary-fix", "byte_count": bytes.count, "sha256": AgentBridgeV4Codec.sha256(bytes), "installed_transport_qualification": false]
        try JSONSerialization.data(withJSONObject: provenance, options: [.sortedKeys, .withoutEscapingSlashes]).write(to: URL(fileURLWithPath: path + ".provenance.json"), options: .atomic)
    }

    func testGatedActualServiceDiscoveryCompleteCandidate() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let discovery = try rig.discover()
        let intent = try rig.intent(metrics: ["heart_rate_avg", "steps"]) // Independent native literal constructors.
        let request = try AgentBridgePlanRequest(authorityId: id(7), authorityRevision: 1, capabilitySha256: discovery.capabilitySha256,
            hostAuthorityReference: .init(authorityId: id(13), grantRevision: 1, grantSha256: digest("2"), issuer: .authorizedHost),
            intent: intent, requestId: id(101))
        let response = try rig.send(.planRequest(request))
        guard case .plan(let plan) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: response).payload else { throw AgentBridgeValidationError.invalidRequest }
        XCTAssertEqual(plan.intent, intent)
        XCTAssertEqual(plan.capabilitySha256, discovery.capabilitySha256)
        XCTAssertEqual(plan.predictedPaths.map(\.rawValue), ["2026/2026-03-07.json", "2026/2026-03-08.json"])
        XCTAssertEqual(plan.resolvedMetricIds.map(\.rawValue), ["heart_rate_avg", "steps"])
        XCTAssertEqual(plan.effectiveSettings, output())
        XCTAssertEqual(discovery.outputSupport.settingPointers, outputPointers)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 1)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
        let environment = ProcessInfo.processInfo.environment
        guard environment["HEALTHMD_GENERATE_AGENT_BRIDGE_V4"] == "1" else { return }
        let path = try XCTUnwrap(environment["HEALTHMD_AGENT_BRIDGE_CANDIDATES"])
        guard path == "/private/tmp/healthmd-agent-bridge-20261004/evidence/swift-planning-boundaries/native-discovery-candidates-complete.json",
              !FileManager.default.fileExists(atPath: path) else { throw AgentBridgeValidationError.unsafePath }
        var sourceRoot = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        for _ in 0..<5 { sourceRoot.deleteLastPathComponent() }
        let sources = [
            "apps/apple/HealthMd/Shared/Export/AgentBridgeExportPlanning.swift",
            "apps/apple/HealthMd/Shared/Export/AgentBridgeExportAuthorityStore.swift",
            "apps/apple/HealthMd/Shared/Export/AgentBridgeRequestSettings.swift",
            "apps/apple/HealthMd/Shared/Core/HealthMdCoreRegistryAdapter.swift",
            "apps/apple/HealthMdTests/Export/AgentBridgeExportPlanningTests.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgeBoundary.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgeCodable.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgeDelegation.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgeDocuments.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgeIntent.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgeJSON.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgeModels.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgePaths.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgeSemantics.swift",
            "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json"
        ]
        var hashes: [String: String] = [:]
        for source in sources { hashes[source] = AgentBridgeV4Codec.sha256(try Data(contentsOf: sourceRoot.appendingPathComponent(source))) }
        // CLOSED interoperability wrapper, NOT a wire envelope or issuer permission. DTO values
        // are actual service results. Hashing is native Swift; no Python verdict/fixture forwarding.
        let candidate: [String: Any] = [
            "discovery": try JSONSerialization.jsonObject(with: AgentBridgeV4Codec.encode(discovery)),
            "intent": try JSONSerialization.jsonObject(with: AgentBridgeV4Codec.encode(intent)),
            "plan": try JSONSerialization.jsonObject(with: AgentBridgeV4Codec.encode(plan)),
            "producer": "swift_actual_service", "producer_source_sha256": hashes,
            "source_base": "3bc392c823193ab04aeea4bb71e7cbcb5747b403"
        ]
        let bytes = try AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: candidate, options: [.sortedKeys, .withoutEscapingSlashes]))
        try bytes.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    func testExactPlanRetryNeverRenewsAndChangedBytesCannotReplaceIssuedIdentity() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try rig.request(discovery: rig.discover())
        let bytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(request)))
        let first = try rig.service.handle(bytes, authenticatedPeer: rig.peer)
        let generation = try rig.store.snapshot().generation
        rig.clock.advance(seconds: 50)
        XCTAssertEqual(try rig.restartedService().handle(bytes, authenticatedPeer: rig.peer), first)
        XCTAssertEqual(try rig.store.snapshot().generation, generation)
        let whitespace = Data(" ".utf8) + bytes
        let rejection = try rig.service.handle(whitespace, authenticatedPeer: rig.peer)
        XCTAssertEqual(try error(rejection), .bindingChanged)
        for changed in [try rig.request(discovery: rig.discover(), metrics: ["heart_rate_min"]),
                        try rig.request(discovery: rig.discover(), destination: .init(bindingID: id(14), identitySHA256: digest("b"), revision: 2, hostInstallationID: rig.peer.peer.hostInstallationID)),
                        try rig.request(discovery: rig.discover(), dates: .allAvailable)] {
            try rig.expectError(.bindingChanged, request: .planRequest(changed))
        }
        rig.clock.advance(seconds: 550)
        let late = try rig.restartedService().handle(bytes, authenticatedPeer: rig.peer)
        XCTAssertEqual(try error(late), .planExpired)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 1)
    }

    func testUnknownWrongHostCopiedIssuerRevisionExpiryRevocationFailClosed() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let discovery = try rig.discover()
        let request = try rig.request(discovery: discovery)
        let foreignSource = try XCTUnwrap(UUID(uuidString: id(1).rawValue)), foreignHost = try XCTUnwrap(UUID(uuidString: id(99).rawValue))
        let foreign = try AgentBridgeExportAuthenticatedPeer(nativeSourceInstallationID: foreignSource, authenticatedHostInstallationID: foreignHost,
                                                            currentNativeSession: RevocableNativeSession(source: foreignSource, host: foreignHost))
        let wrong = try rig.service.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(request))), authenticatedPeer: foreign)
        XCTAssertEqual(try error(wrong), .bindingChanged)
        let foreignDiscovery = try rig.service.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .discoveryRequest(.init(requestID: id(100), peer: foreign.peer)))), authenticatedPeer: foreign)
        guard case .discovery(let filtered) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: foreignDiscovery).payload else { return XCTFail("discovery") }
        XCTAssertTrue(filtered.authorityReferences.isEmpty)
        let unknown = AgentBridgePlanRequest(authorityId: try id(90), authorityRevision: 1, capabilitySha256: discovery.capabilitySha256, hostAuthorityReference: request.hostAuthorityReference, intent: request.intent, requestId: try id(101))
        try rig.expectError(.approvalRequired, request: .planRequest(unknown))
        let stale = AgentBridgePlanRequest(authorityId: request.authorityId, authorityRevision: 2, capabilitySha256: discovery.capabilitySha256, hostAuthorityReference: request.hostAuthorityReference, intent: request.intent, requestId: request.requestId)
        try rig.expectError(.revisionConflict, request: .planRequest(stale))
        let copied = AgentBridgePlanRequest(authorityId: request.authorityId, authorityRevision: 1, capabilitySha256: discovery.capabilitySha256, hostAuthorityReference: discovery.authorityReferences[0], intent: request.intent, requestId: request.requestId)
        try rig.expectError(.approvalRequired, request: .planRequest(copied))
        try rig.store.revokeNativeDelegation(discovery.authorityReferences[0], expectedGeneration: rig.store.snapshot().generation, authorization: FakeNativeAuthorization())
        XCTAssertTrue(try rig.discover().authorityReferences.isEmpty)
        try rig.expectError(.approvalRequired, request: .planRequest(request))
        XCTAssertThrowsError(try rig.enroll(revision: 2)) // Revoked IDs are never recycled.
        let expired = try Rig(); defer { expired.cleanup() }; try expired.enroll(expires: "2026-03-08T23:59:59Z")
        XCTAssertTrue(try expired.discover().authorityReferences.isEmpty)
        try expired.expectError(.approvalRequired, request: .planRequest(expired.request(discovery: expired.discover())))
    }

    func testAllAvailableRemainsLogicalAndPastCompleteDaysResolveGregorianDST() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll(expires: "2026-03-09T00:04:00Z")
        let relative = try rig.makePlan(dates: .pastCompleteDays(days: 2, anchorDate: date("2026-03-09")))
        XCTAssertEqual(relative.predictedPaths.map(\.rawValue), ["2026/2026-03-07.json", "2026/2026-03-08.json"])
        XCTAssertEqual(relative.intent.calendarTimezone.rawValue, "America/Los_Angeles")
        XCTAssertEqual(relative.expiresAt.rawValue, "2026-03-09T00:04:00Z")
        let allRig = try Rig(); defer { allRig.cleanup() }; try allRig.enroll()
        let calls = allRig.reader.calls.count
        let all = try allRig.makePlan(dates: .allAvailable)
        XCTAssertEqual(all.resolvedDates, .allAvailable)
        XCTAssertEqual(all.pathPrediction, .templateOnlyAllAvailable)
        XCTAssertEqual(all.limitations.map(\.rawValue), ["healthkit_read_authorization_unobservable", "history_bounds_unresolved"])
        XCTAssertTrue(all.predictedPaths.isEmpty)
        XCTAssertEqual(allRig.reader.calls.count - calls, 7) // Issuance, pre-rename, post-sync and final-return configuration fences.
        XCTAssertEqual(allRig.reader.defaults.writes, 0)
        XCTAssertEqual(allRig.reader.defaults.reads, 0)
    }

    func testUnsupportedOutputsAndScopeRejectWithoutPreferenceReads() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let discovery = try rig.discover()
        let bad = output(format: .markdown)
        try rig.expectError(.unsupportedCapability, request: .planRequest(rig.request(discovery: discovery, policy: .explicit(bad))))
        try rig.expectError(.unsupportedMetric, request: .planRequest(rig.request(discovery: discovery, metrics: ["android.hrv_rmssd"])))
        try rig.expectError(.queryBudgetExceeded, request: .planRequest(rig.request(discovery: discovery, dates: .exact(.init(startDate: date("2025-01-01"), endDate: date("2026-03-08"))))))
        XCTAssertEqual(try rig.store.snapshot().plans.count, 0)
        XCTAssertEqual(rig.reader.defaults.reads, 0)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testSavedAndProfileRevisionsOutputAndCapabilityChangesInvalidateApproval() throws {
        for policy in [AgentBridgeSettingsPolicy.savedDeviceSettings(expectedRevision: 7), .profile(profileID: try id(50), expectedRevision: 7)] {
            let rig = try Rig(withSaved: true); defer { rig.cleanup() }; try rig.enroll()
            let plan = try rig.makePlan(policy: policy)
            XCTAssertEqual(plan.effectiveSettings.folderTemplate, "saved/{year}")
            XCTAssertEqual(plan.revisions.count, 1)
            XCTAssertEqual(plan.revisions[0].revision, 7)
            XCTAssertEqual(plan.origins.filter { $0.pointer.hasPrefix("/effective_settings/") }.map(\.revision), Array(repeating: 7, count: outputPointers.count))
            XCTAssertEqual(rig.reader.defaults.writes, 0)
            let binding = AgentBridgeSemantics.binding(plan)
            try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                authorization: FakeNativeAuthorization(binding: binding))
            let request = AgentBridgeApprovalRequest(binding: binding, planId: plan.planId, requestId: try id(103))
            var snapshot = try XCTUnwrap(rig.reader.saved)
            snapshot.folderStructure = "changed/{year}"
            rig.reader.saved = snapshot // Same revision cannot silently change frozen output.
            try rig.expectError(.bindingChanged, request: .approvalRequest(request))
        }
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan()
        let request = AgentBridgeApprovalRequest(binding: AgentBridgeSemantics.binding(plan), planId: plan.planId, requestId: try id(103))
        rig.reader.protection = .unlockedNative
        try rig.expectError(.bindingChanged, request: .approvalRequest(request))
        rig.reader.protection = .locked
        rig.reader.available = ["steps", "heart_rate_min"] // Even unchanged catalog revision is caught by frozen native reuse.
        try rig.expectError(.bindingChanged, request: .approvalRequest(request))
    }

    func testConfigurationProtectionConsentEntitlementAndAvailabilityAreIndependent() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        rig.reader.grants = .unverified
        let plan = try rig.makePlan()
        XCTAssertEqual(plan.requiredActions.map(\.rawValue), ["grant_health_access"])
        XCTAssertEqual(try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: rig.peer).nativeConsent, .required)
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: AgentBridgeSemantics.binding(plan), approvalID: id(8), authenticatedPeer: rig.peer,
                                                               authorization: FakeNativeAuthorization(binding: AgentBridgeSemantics.binding(plan)))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        let entitlementRig = try Rig(); defer { entitlementRig.cleanup() }; try entitlementRig.enroll(); entitlementRig.reader.entitlement = .required
        let blocked = try entitlementRig.makePlan()
        XCTAssertEqual(blocked.requiredActions.map(\.rawValue), ["purchase_required"])
        XCTAssertThrowsError(try entitlementRig.service.storeNativeDecision(planID: blocked.planId, binding: AgentBridgeSemantics.binding(blocked), approvalID: id(8), authenticatedPeer: entitlementRig.peer,
                                                                          authorization: FakeNativeAuthorization(binding: AgentBridgeSemantics.binding(blocked)))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .entitlementRequired) }
    }

    func testDispatchRejectsUnknownQueryControlExecutionCancelAndResume() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        for name in ["unknown", "query_request", "control_request", "execute_request", "cancel_request", "resume_request"] {
            let bytes = Data((#"{"protocol_version":4,"type":""# + name + #"","payload":{"schema":"healthmd.agent_discovery_request","schema_version":1,"request_id":"00000000-0000-4000-8000-000000000064","peer":{"source_installation_id":"00000000-0000-4000-8000-000000000001","host_installation_id":"00000000-0000-4000-8000-000000000002","platform":"apple"}}}"#).utf8)
            XCTAssertThrowsError(try rig.service.handle(bytes, authenticatedPeer: rig.peer))
        }
        // A valid known non-planning DTO also rejects, not just mismatched/malformed discriminators.
        let cancel = try AgentBridgeCancel(approvalId: id(8), authorityId: id(7), jobId: id(10), peer: rig.peer.peer, requestSha256: digest("a"))
        XCTAssertThrowsError(try rig.send(.cancel(cancel))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .unsupportedCapability) }
        XCTAssertEqual(rig.reader.calls.count, 0)
        XCTAssertEqual(try rig.store.snapshot().generation, 0)
    }

    func testFreshInBoundsScopeAndOpaqueDestinationNeedNewIssuedPlanAndDecision() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let first = try rig.makePlan()
        let firstBinding = AgentBridgeSemantics.binding(first)
        try rig.service.storeNativeDecision(planID: first.planId, binding: firstBinding, approvalID: id(8), authenticatedPeer: rig.peer,
                                            authorization: FakeNativeAuthorization(binding: firstBinding))
        let changed = try rig.request(discovery: rig.discover(), metrics: ["heart_rate_min"],
                                      destination: .init(bindingID: id(14), identitySHA256: digest("b"), revision: 2, hostInstallationID: rig.peer.peer.hostInstallationID), requestID: id(102))
        let bytes = try rig.send(.planRequest(changed))
        guard case .plan(let second) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes).payload else { return XCTFail("fresh plan required") }
        XCTAssertNotEqual(second.planId, first.planId)
        XCTAssertNotEqual(second.scopeSha256, first.scopeSha256)
        XCTAssertEqual(second.intent.destination, changed.intent.destination) // Opaque bound host reference only, NOT verified host permission.
        XCTAssertEqual(second.authorityReferences.native, first.authorityReferences.native)
        try rig.expectError(.bindingChanged, request: .approvalRequest(.init(binding: firstBinding, planId: second.planId, requestId: id(103))))
        try rig.expectError(.approvalRequired, request: .approvalRequest(.init(binding: AgentBridgeSemantics.binding(second), planId: second.planId, requestId: id(103))))
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 1)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 2)
    }

    func testRevokedNativeSessionInvalidatesCopiedIDsOnEveryPublicServiceEntry() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        let copiedContext = rig.peer // Same immutable IDs AND same revocable session, not authority.
        let requestBytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .discoveryRequest(.init(requestID: id(100), peer: copiedContext.peer))))
        let before = try rig.store.snapshot().generation, configReads = rig.reader.calls.count
        rig.session.revoke()
        XCTAssertThrowsError(try rig.service.handle(requestBytes, authenticatedPeer: copiedContext)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: copiedContext,
                                                               authorization: FakeNativeAuthorization(binding: binding))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertThrowsError(try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: copiedContext)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertEqual(rig.reader.calls.count, configReads)
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
        XCTAssertEqual(copiedContext.peer, rig.peer.peer)
    }

    func testRevocationDuringActualConfigurationReadPreventsIssuedPlanPersistence() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try rig.request(discovery: rig.discover())
        rig.reader.beforeReturn = { rig.session.revoke() }
        XCTAssertThrowsError(try rig.send(.planRequest(request))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertEqual(try rig.store.snapshot().plans.count, 0)
        XCTAssertEqual(rig.reader.calls, ["discovery", "discovery", "explicit"]) // Discovery return also rechecks configuration.
    }

    func testRevocationInsideNativeDecisionAdapterCannotCommitOrReturnApproval() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        let before = try rig.store.snapshot().generation
        let nativeDecision = FakeNativeAuthorization(binding: binding, afterAuthorization: { rig.session.revoke() })
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                               authorization: nativeDecision)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
    }

    func testConcurrentActualHandlesSerializeDiscoveryAndExactPlanCAS() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let discoveryBytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer))))
        let discoveries = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<8 { group.addTask { @MainActor in try rig.service.handle(discoveryBytes, authenticatedPeer: rig.peer) } }
            var results: [Data] = []; for try await result in group { results.append(result) }; return results
        }
        XCTAssertEqual(Set(discoveries).count, 1)
        guard case .discovery(let discovery) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: discoveries[0]).payload else { return XCTFail("discovery") }
        let requestBytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(rig.request(discovery: discovery))))
        let replies = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<8 { group.addTask { @MainActor in try rig.service.handle(requestBytes, authenticatedPeer: rig.peer) } }
            var results: [Data] = []; for try await result in group { results.append(result) }; return results
        }
        XCTAssertEqual(Set(replies).count, 1)
        XCTAssertEqual(try rig.store.snapshot().generation, 2) // One grant, one issued-plan transaction.
        XCTAssertEqual(try rig.store.snapshot().plans.count, 1)
        let changed = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(rig.request(discovery: discovery, metrics: ["heart_rate_min"]))))
        let contested = try await withThrowingTaskGroup(of: Data.self) { group in
            for bytes in [requestBytes, changed] { group.addTask { @MainActor in try rig.service.handle(bytes, authenticatedPeer: rig.peer) } }
            var results: [Data] = []; for try await result in group { results.append(result) }; return results
        }
        XCTAssertEqual(contested.filter { $0 == replies[0] }.count, 1)
        XCTAssertEqual(try contested.filter { $0 != replies[0] }.map(error), [.bindingChanged])
        XCTAssertEqual(try rig.store.snapshot().generation, 2)
    }

    func testDiscoveryLifetimeAndRestartRequireFreshDiscoveryForNewPlansOnly() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try rig.request(discovery: rig.discover())
        let bytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(request)))
        XCTAssertEqual(try error(rig.restartedService().handle(bytes, authenticatedPeer: rig.peer)), .planExpired)
        rig.clock.advance(seconds: 600)
        XCTAssertEqual(try error(rig.service.handle(bytes, authenticatedPeer: rig.peer)), .planExpired)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 0)
    }

    func testRawDuplicateKeysInvalidUTF8AndBoundsRejectBeforeConfiguration() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let valid = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer))))
        let text = String(decoding: valid, as: UTF8.self)
        for invalid in [Data(text.replacingOccurrences(of: "\"protocol_version\":4", with: "\"protocol_version\":4,\"protocol_\\u0076ersion\":4").utf8),
                        Data([0xff]) + valid,
                        Data(text.replacingOccurrences(of: "\"schema_version\":1", with: "\"schema_version\":true").utf8),
                        Data(repeating: 32, count: AgentBridgeV4Codec.maximumBytes + 1),
                        Data((String(repeating: "[", count: 26) + "0" + String(repeating: "]", count: 26)).utf8),
                        Data((#"{"a":""# + String(repeating: "x", count: 65_537) + #""}"#).utf8)] {
            XCTAssertThrowsError(try rig.service.handle(invalid, authenticatedPeer: rig.peer))
        }
        XCTAssertEqual(rig.reader.calls.count, 0)
    }

    // Independently worked 7,706-byte canonical v4 response. Updating installed policy support
    // changes only capability_sha256 and its derived plan_sha256; every other response byte is fixed.
    private static let tracerResponseSHA256 = "d072a33ec021b2d4de40a0564db00ce1f6d1690b48f1e72431aad1d90e5dda45"
}

private func id(_ n: Int) throws -> AgentBridgeUUID { try AgentBridgeUUID(String(format: "00000000-0000-4000-8000-%012x", n)) }
private func date(_ value: String) throws -> AgentBridgeDate { try AgentBridgeDate(value) }
private func digest(_ char: String) throws -> AgentBridgeDigest { try AgentBridgeDigest(String(repeating: char, count: 64)) }
private func error(_ bytes: Data) throws -> AgentBridgeErrorCode {
    guard case .error(let value) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes).payload else { throw AgentBridgeValidationError.invalidRequest }
    return value.code
}
private func output(format: AgentBridgeFormat = .json, folder: String = "{year}") -> AgentBridgeOutputSettings {
    .init(formats: [format], outputProfile: .appleV8, subfolder: "", folderTemplate: folder, filenameTemplate: "{date}", writeMode: .overwrite,
          presentation: .init(displayUnits: .metric, locale: "en-US", includeMetadata: true, groupByCategory: true,
                              frontmatter: .init(enabledFieldIDs: [], customFields: [], includeUnits: true, includeCaptureDiagnostics: false),
                              markdown: .init(style: .lists, customTemplate: "", placeholderIDs: [])),
          individualEntries: .init(enabled: false, metricIDs: [], folderTemplate: "", filenameTemplate: "{metric}-{date}", categoryFolders: false),
          dailyNotes: .init(enabled: false, only: false, folderTemplate: "", filenameTemplate: "{date}", createIfMissing: false, sectionIDs: []),
          packaging: .looseFiles, dictionary: .none)
}
private let outputPointers = [
    "/daily_notes/create_if_missing", "/daily_notes/enabled", "/daily_notes/filename_template", "/daily_notes/folder_template", "/daily_notes/only", "/daily_notes/section_ids", "/dictionary/type", "/filename_template", "/folder_template", "/formats",
    "/individual_entries/category_folders", "/individual_entries/enabled", "/individual_entries/filename_template", "/individual_entries/folder_template", "/individual_entries/metric_ids", "/output_profile", "/packaging/type", "/presentation/display_units", "/presentation/frontmatter/custom_fields", "/presentation/frontmatter/enabled_field_ids", "/presentation/frontmatter/include_capture_diagnostics", "/presentation/frontmatter/include_units", "/presentation/group_by_category", "/presentation/include_metadata", "/presentation/locale", "/presentation/machine_units", "/presentation/markdown/custom_template", "/presentation/markdown/placeholder_ids", "/presentation/markdown/style", "/subfolder", "/write_mode"
]
private let capturePointers = ["/capture_scope/compatibility_detail", "/capture_scope/native_archive/type", "/capture_scope/selection/all_metrics", "/capture_scope/selection/category_ids", "/capture_scope/selection/metric_ids", "/capture_scope/selection/provider_ids", "/capture_scope/selection/source_ids"]

nonisolated private final class PublicationTaskCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<AgentBridgeNativeCatalogPublication, Error>?
    private var didRequest = false
    var requested: Bool { lock.withLock { didRequest } }
    func install(_ value: Task<AgentBridgeNativeCatalogPublication, Error>) {
        lock.withLock { task = value; if didRequest { value.cancel() } }
    }
    func request() { lock.withLock { didRequest = true; task?.cancel() } }
}

nonisolated private final class RevocableNativeSession: AgentBridgeExportNativeSessionChecking, @unchecked Sendable {
    private let lock = NSLock()
    private let authenticatedPeer: AgentBridgePeer
    private var revoked = false
    private var count = 0
    private var observer: ((Int) -> Void)?
    var checks: Int { lock.lock(); defer { lock.unlock() }; return count }
    func observeChecks(_ callback: @escaping (Int) -> Void) { lock.lock(); defer { lock.unlock() }; observer = callback }
    init(source: UUID, host: UUID) throws {
        authenticatedPeer = try .init(sourceInstallationID: AgentBridgeUUID(source.uuidString.lowercased()), hostInstallationID: AgentBridgeUUID(host.uuidString.lowercased()), platform: .apple)
    }
    func requireCurrent(peer: AgentBridgePeer) throws {
        lock.lock(); count += 1; let check = count, callback = observer; lock.unlock()
        callback?(check)
        lock.lock(); defer { lock.unlock() }
        guard !revoked, peer == authenticatedPeer else { throw AgentBridgeValidationError.permissionRequired }
    }
    func revoke() { lock.lock(); defer { lock.unlock() }; revoked = true }
}

nonisolated private final class AdvancingPlanningClock: AgentBridgeExportClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value = ISO8601DateFormatter().date(from: "2026-03-09T00:00:00Z")!
    private var afterNextSample: TimeInterval?
    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        let sampled = value
        if let delay = afterNextSample { value = value.addingTimeInterval(delay); afterNextSample = nil }
        return sampled
    }
    func advanceAfterNextSample(seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; afterNextSample = seconds }
    func advance(seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value = value.addingTimeInterval(seconds) }
}

nonisolated private final class FakeProtectedKeys: AgentBridgeExportProtectedKeyReading, @unchecked Sendable {
    let key: SymmetricKey?
    private let lock = NSLock()
    private var count = 0
    private var nextLoad: (() -> Void)?
    var loads: Int { lock.lock(); defer { lock.unlock() }; return count }
    func onNextLoad(_ callback: @escaping () -> Void) { lock.lock(); defer { lock.unlock() }; nextLoad = callback }
    init(key: SymmetricKey? = SymmetricKey(data: Data(repeating: 9, count: 32))) { self.key = key }
    func loadExistingExportAuthorityKey() throws -> SymmetricKey? {
        lock.lock(); count += 1; let callback = nextLoad; nextLoad = nil; lock.unlock()
        callback?()
        return key
    }
}
nonisolated private final class LiveExactApprovalAuthorization: AgentBridgeExportNativeAuthorizing {
    private let planID: AgentBridgeUUID
    private let binding: AgentBridgeBinding
    var allowed = true
    var checks = 0
    var onCheck: ((Int) -> Void)?
    init(planID: AgentBridgeUUID, binding: AgentBridgeBinding) { self.planID = planID; self.binding = binding }
    func requireNativeAuthorization(for action: AgentBridgeExportNativeAction) throws {
        guard allowed, case .decideExport(let id, let candidate) = action, id == planID, candidate == binding else {
            throw AgentBridgeValidationError.approvalRequired
        }
        checks += 1
        onCheck?(checks)
    }
}
nonisolated private struct FakeNativeAuthorization: AgentBridgeExportNativeAuthorizing {
    var deny = false
    var binding: AgentBridgeBinding? = nil
    var afterAuthorization: (() -> Void)? = nil
    func requireNativeAuthorization(for action: AgentBridgeExportNativeAction) throws {
        guard !deny else { throw AgentBridgeValidationError.permissionRequired }
        if case .decideExport(_, let candidate) = action, candidate != binding { throw AgentBridgeValidationError.approvalRequired }
        afterAuthorization?()
    }
}
nonisolated private final class PublicationProbe: AgentBridgeExportPublicationObserving {
    var onPrepared: ((AgentBridgeExportAuthoritySnapshot) throws -> Void)?
    var onPublished: ((AgentBridgeExportAuthoritySnapshot) throws -> Void)?
    func prepared(_ state: AgentBridgeExportAuthoritySnapshot) throws { try onPrepared?(state) }
    func published(_ state: AgentBridgeExportAuthoritySnapshot) throws { try onPublished?(state) }
}

@MainActor
private final class ConfigurationProbe: AgentBridgeExportPlanningConfigurationReading {
    let suite = "AgentBridgeExportPlanningTests." + UUID().uuidString
    let defaults: AgentBridgeRequestSettingsDefaultsProbe
    var calls: [String] = []
    var beforeReturn: (() -> Void)?
    var available: Set<String> = ["steps", "heart_rate_avg", "heart_rate_min", "heart_rate_max", "resting_heart_rate", "hrv"]
    var catalogRevision: Int64 = 3
    var saved: ExportSettingsSnapshot?
    var savedRevision: Int64 = 7
    var protection: AgentBridgeDiscoveryConfigurationProtection = .locked
    var grants: AgentBridgeDiscoveryNativeGrants = .satisfied
    var entitlement: AgentBridgeDiscoveryEntitlement = .satisfied
    init() throws { defaults = try XCTUnwrap(AgentBridgeRequestSettingsDefaultsProbe(suiteName: suite)); defaults.reads = 0; defaults.writes = 0 }
    var inputs: AgentBridgeRequestSettingsInputs {
        get throws {
            let snapshot = saved.map { AgentBridgeRequestSettingsSnapshot(revision: savedRevision, settings: $0) }
            return try .init(catalog: .init(registry: HealthMdCoreRegistryAdapter.appleSnapshot(), availableNativeMetricIDs: available, revision: catalogRevision),
                             savedDevice: snapshot, profiles: snapshot.map { [.init(profileID: try! id(50), snapshot: $0, executionBlocked: false)] } ?? [])
        }
    }
    func readConfiguration(for peer: AgentBridgeExportAuthenticatedPeer, policy: AgentBridgeSettingsPolicy?, catalogPublication: AgentBridgeNativeCatalogPublication?) throws -> AgentBridgeExportPlanningConfiguration {
        let kind: String
        switch policy { case nil: kind = "discovery"; case .explicit: kind = "explicit"; case .savedDeviceSettings: kind = "saved"; case .profile: kind = "profile" }
        calls.append(kind)
        if kind == "saved" || kind == "profile" { _ = defaults.string(forKey: "sentinel") }
        beforeReturn?()
        let selectedSaved: AgentBridgeRequestSettingsSnapshot?
        let selectedProfiles: [AgentBridgeRequestSettingsProfile]
        switch policy {
        case .savedDeviceSettings:
            selectedSaved = saved.map { .init(revision: savedRevision, settings: $0) }
            selectedProfiles = []
        case .profile(let requestedID, _):
            selectedSaved = nil
            let knownID = try id(50)
            selectedProfiles = saved.map {
                requestedID == knownID ? [.init(profileID: requestedID, snapshot: .init(revision: savedRevision, settings: $0), executionBlocked: false)] : []
            } ?? []
        default:
            selectedSaved = nil
            selectedProfiles = []
        }
        let selectedInputs = try AgentBridgeRequestSettingsInputs(
            catalog: .init(registry: HealthMdCoreRegistryAdapter.appleSnapshot(), availableNativeMetricIDs: available, revision: catalogRevision),
            savedDevice: selectedSaved, profiles: selectedProfiles)
        return try .init(inputs: selectedInputs, deviceSettingsObjectID: id(5), sourceCalendarTimezone: AgentBridgeZone("America/Los_Angeles"), configurationProtection: protection,
                         nativeGrants: grants, entitlement: entitlement, foregroundAvailable: true, protectedDataAvailable: true)
    }
}
@MainActor
private final class Rig {
    let parent: URL
    let directory: URL
    let keys = FakeProtectedKeys()
    let publication = PublicationProbe()
    let reader: ConfigurationProbe
    let store: AgentBridgeExportAuthorityStore
    let service: AgentBridgeExportPlanningService
    let peer: AgentBridgeExportAuthenticatedPeer
    let session: RevocableNativeSession
    let clock = AdvancingPlanningClock()
    var now: Date { clock.now() }
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }
    init(withSaved: Bool = false) throws {
        parent = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("healthmd-native-planning-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        directory = parent.appendingPathComponent("authority")
        let source = try XCTUnwrap(UUID(uuidString: id(1).rawValue)), host = try XCTUnwrap(UUID(uuidString: id(2).rawValue))
        session = try RevocableNativeSession(source: source, host: host)
        peer = try .init(nativeSourceInstallationID: source, authenticatedHostInstallationID: host, currentNativeSession: session)
        reader = try ConfigurationProbe()
        store = try AgentBridgeExportAuthorityStore.createPrivateStore(at: directory, protectedKeys: keys, authorization: FakeNativeAuthorization(), publication: publication)
        var nextPlanID = 6
        service = AgentBridgeExportPlanningService(store: store, configuration: reader, clock: clock, newPlanID: {
            let chosen = nextPlanID; nextPlanID += 10; return try id(chosen)
        })
        if withSaved {
            let request = try intent(policy: .explicit(output(folder: "saved/{year}")))
            reader.saved = try AgentBridgeRequestSettingsResolver.resolve(request, inputs: reader.inputs, clock: now, calendar: calendar).settings
            reader.defaults.set("synthetic", forKey: "sentinel"); reader.defaults.reads = 0; reader.defaults.writes = 0
        }
    }
    func cleanup() { reader.defaults.removePersistentDomain(forName: reader.suite); try? FileManager.default.removeItem(at: parent) }
    func grant(revision: Int64 = 1, expires: String = "2026-03-09T01:00:00Z") throws -> AgentBridgeExportDelegation {
        try .init(authorityID: id(7), issuer: .nativeSource, grantRevision: revision, peer: peer.peer, rights: [.discover, .exportExecute, .plan], expiresAt: AgentBridgeUTC(expires),
                  bounds: .init(products: [.generatedFiles], projectionDetails: [], projectionObjectIDs: [], projectionFieldIDs: [],
                                metricIDs: ["heart_rate_avg", "heart_rate_max", "heart_rate_min", "hrv", "resting_heart_rate", "steps"].map(AgentBridgeID.init),
                                calendarTimezones: [AgentBridgeZone("America/Los_Angeles"), AgentBridgeZone("UTC")], datePolicy: .authorizedHistory(maxDays: 366, allowAllAvailable: true),
                                formats: [.json], outputProfiles: [.appleV8], writeModes: [.overwrite], compatibilityDetail: [.summary], nativeArchiveProducts: [.none], destinationPolicy: .authenticatedHostBindings))
    }
    func enroll(revision: Int64 = 1, expires: String = "2026-03-09T01:00:00Z") throws {
        try store.storeNativeDelegation(grant(revision: revision, expires: expires), expectedGeneration: store.snapshot().generation, authorization: FakeNativeAuthorization())
    }
    func intent(metrics: [String] = ["steps"], dates: AgentBridgeDates? = nil, destination: AgentBridgeDestination? = nil, policy: AgentBridgeSettingsPolicy? = nil) throws -> AgentBridgeGeneratedIntent {
        try .init(intentID: id(4), peer: peer.peer, destination: destination ?? .init(bindingID: id(3), identitySHA256: digest("1"), revision: 1, hostInstallationID: peer.peer.hostInstallationID),
                  dates: dates ?? .exact(.init(startDate: date("2026-03-07"), endDate: date("2026-03-08"))), calendarTimezone: AgentBridgeZone("America/Los_Angeles"),
                  captureScope: .init(selection: .init(metricIDs: metrics.map(AgentBridgeID.init).sorted { $0.rawValue < $1.rawValue }, categoryIDs: [], sourceIDs: [AgentBridgeID("apple_health")], providerIDs: [], allMetrics: false), compatibilityDetail: .summary, nativeArchive: .none),
                  settingsPolicy: policy ?? .explicit(output()))
    }
    func discover() throws -> AgentBridgeDiscovery {
        let bytes = try send(.discoveryRequest(.init(requestID: id(100), peer: peer.peer)))
        guard case .discovery(let value) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes).payload else { throw AgentBridgeValidationError.invalidRequest }
        return value
    }
    func request(discovery: AgentBridgeDiscovery, metrics: [String] = ["steps"], dates: AgentBridgeDates? = nil, destination: AgentBridgeDestination? = nil, policy: AgentBridgeSettingsPolicy? = nil, requestID: AgentBridgeUUID? = nil) throws -> AgentBridgePlanRequest {
        try .init(authorityId: id(7), authorityRevision: 1, capabilitySha256: discovery.capabilitySha256,
                  hostAuthorityReference: .init(authorityId: id(13), grantRevision: 1, grantSha256: digest("2"), issuer: .authorizedHost),
                  intent: intent(metrics: metrics, dates: dates, destination: destination, policy: policy), requestId: requestID ?? id(101))
    }
    func makePlan(dates: AgentBridgeDates? = nil, policy: AgentBridgeSettingsPolicy? = nil) throws -> AgentBridgePlan {
        let bytes = try send(.planRequest(request(discovery: discover(), dates: dates, policy: policy)))
        guard case .plan(let value) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes).payload else { throw AgentBridgeValidationError.invalidRequest }
        return value
    }
    func unissuedBinding(discovery: AgentBridgeDiscovery) throws -> AgentBridgeBinding {
        try .init(authorityReferences: .init(host: .init(authorityId: id(13), grantRevision: 1, grantSha256: digest("2"), issuer: .authorizedHost), native: grant().reference()),
                  capabilitySha256: discovery.capabilitySha256, destination: intent().destination, expiresAt: AgentBridgeUTC("2026-03-09T00:10:00Z"), peer: peer.peer,
                  planSha256: digest("0"), revisions: [], scopeSha256: digest("0"), settingsSha256: digest("0"))
    }
    func send(_ document: AgentBridgeDocument) throws -> Data { try service.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: document)), authenticatedPeer: peer) }
    func expectError(_ wanted: AgentBridgeErrorCode, request: AgentBridgeDocument) throws { XCTAssertEqual(try error(send(request)), wanted) }
    func restartedService() throws -> AgentBridgeExportPlanningService { AgentBridgeExportPlanningService(store: try .init(existingDirectory: directory, protectedKeys: keys), configuration: reader, clock: clock, newPlanID: { throw AgentBridgeValidationError.invalidRequest }) }
}

/// Actual channel encryption/gates with a synthetic native write boundary. No pairing or consent proof.
nonisolated private final class NativePlanningResponsePackets: DirectGuardedPacketTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ManualIPSyncPacket] = []
    private var inbound: [ManualIPSyncPacket]
    private var receives = 0
    private let beforeReceive: @concurrent @Sendable () async throws -> Void
    private let beforeWrite: @concurrent @Sendable () async throws -> Void
    private let afterWrite: @concurrent @Sendable () async throws -> Void
    var receiveCount: Int { lock.withLock { receives } }
    var packets: [ManualIPSyncPacket] { lock.withLock { stored } }
    init(beforeWrite: @escaping @concurrent @Sendable () async throws -> Void = {}, afterWrite: @escaping @concurrent @Sendable () async throws -> Void = {},
         inbound: [ManualIPSyncPacket] = [], beforeReceive: @escaping @concurrent @Sendable () async throws -> Void = {}) {
        self.beforeWrite = beforeWrite; self.afterWrite = afterWrite; self.inbound = inbound; self.beforeReceive = beforeReceive
    }
    @concurrent func sendGuarded(_ packet: ManualIPSyncPacket, authorize: @escaping @concurrent @Sendable () async throws -> Void) async throws {
        try await beforeWrite()
        try await authorize()
        lock.withLock { stored.append(packet) }
        try await afterWrite()
        try await authorize()
    }
    @concurrent func send(_ packet: ManualIPSyncPacket) async throws { throw AgentBridgeValidationError.unsupportedCapability }
    @concurrent func receive() async throws -> ManualIPSyncPacket {
        try await beforeReceive()
        return try lock.withLock {
            guard !inbound.isEmpty else { throw DirectChannelError.connectionClosed }
            receives += 1
            return inbound.removeFirst()
        }
    }
    func cancel() {}
}
