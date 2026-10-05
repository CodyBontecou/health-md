import CryptoKit
import Darwin
import Foundation
import HealthMdConnectionCore
import HealthMdCoreRust
import XCTest
#if canImport(HealthMd)
@testable import HealthMd
#else
@testable import AgentBridgeRequestSettingsHarness
#endif

@MainActor
final class AgentBridgeExportPlanningTests: XCTestCase {
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
        let native = try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: rig.peer, now: rig.now)
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

    func testApprovalRelayRequiresIndependentExactNativeDecisionAndSurvivesRestart() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan()
        let approvalRequest = AgentBridgeApprovalRequest(binding: AgentBridgeSemantics.binding(plan), planId: plan.planId, requestId: try id(103))
        let before = try rig.store.snapshot().generation
        try rig.expectError(.approvalRequired, request: .approvalRequest(approvalRequest))
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: approvalRequest.binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                               now: rig.now, authorization: FakeNativeAuthorization(deny: true)))
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
        try rig.service.storeNativeDecision(planID: plan.planId, binding: approvalRequest.binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                            now: rig.now, authorization: FakeNativeAuthorization(binding: approvalRequest.binding))
        let bytes = try rig.send(.approvalRequest(approvalRequest))
        let restarted = try rig.restartedService()
        let replay = try restarted.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .approvalRequest(approvalRequest))), authenticatedPeer: rig.peer, now: rig.now.addingTimeInterval(30))
        XCTAssertEqual(bytes, replay)
        guard case .approval(let approval) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes).payload else { return XCTFail("approval required") }
        XCTAssertEqual(approval.approvalId, try id(8))
        XCTAssertEqual(approval.binding, approvalRequest.binding)
        XCTAssertEqual(approval.approvedAt.rawValue, "2026-03-09T00:00:00Z")
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 1)
    }

    func testExactPlanRetryNeverRenewsAndChangedBytesCannotReplaceIssuedIdentity() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try rig.request(discovery: rig.discover())
        let bytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(request)))
        let first = try rig.service.handle(bytes, authenticatedPeer: rig.peer, now: rig.now)
        let generation = try rig.store.snapshot().generation
        XCTAssertEqual(try rig.restartedService().handle(bytes, authenticatedPeer: rig.peer, now: rig.now.addingTimeInterval(50)), first)
        XCTAssertEqual(try rig.store.snapshot().generation, generation)
        let whitespace = Data(" ".utf8) + bytes
        let rejection = try rig.service.handle(whitespace, authenticatedPeer: rig.peer, now: rig.now)
        XCTAssertEqual(try error(rejection), .bindingChanged)
        for changed in [try rig.request(discovery: rig.discover(), metrics: ["heart_rate_min"]),
                        try rig.request(discovery: rig.discover(), destination: .init(bindingID: id(14), identitySHA256: digest("b"), revision: 2, hostInstallationID: rig.peer.peer.hostInstallationID)),
                        try rig.request(discovery: rig.discover(), dates: .allAvailable)] {
            try rig.expectError(.bindingChanged, request: .planRequest(changed))
        }
        let late = try rig.restartedService().handle(bytes, authenticatedPeer: rig.peer, now: rig.now.addingTimeInterval(600))
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
        let wrong = try rig.service.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(request))), authenticatedPeer: foreign, now: rig.now)
        XCTAssertEqual(try error(wrong), .bindingChanged)
        let foreignDiscovery = try rig.service.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .discoveryRequest(.init(requestID: id(100), peer: foreign.peer)))), authenticatedPeer: foreign, now: rig.now)
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
        XCTAssertEqual(allRig.reader.calls.count - calls, 2) // Discovery + plan use the actual configuration dependency.
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
            try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer, now: rig.now,
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
        XCTAssertEqual(try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: rig.peer, now: rig.now).nativeConsent, .required)
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: AgentBridgeSemantics.binding(plan), approvalID: id(8), authenticatedPeer: rig.peer, now: rig.now,
                                                               authorization: FakeNativeAuthorization(binding: AgentBridgeSemantics.binding(plan)))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        let entitlementRig = try Rig(); defer { entitlementRig.cleanup() }; try entitlementRig.enroll(); entitlementRig.reader.entitlement = .required
        let blocked = try entitlementRig.makePlan()
        XCTAssertEqual(blocked.requiredActions.map(\.rawValue), ["purchase_required"])
        XCTAssertThrowsError(try entitlementRig.service.storeNativeDecision(planID: blocked.planId, binding: AgentBridgeSemantics.binding(blocked), approvalID: id(8), authenticatedPeer: entitlementRig.peer, now: entitlementRig.now,
                                                                          authorization: FakeNativeAuthorization(binding: AgentBridgeSemantics.binding(blocked)))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .entitlementRequired) }
    }

    func testDispatchRejectsUnknownQueryControlExecutionCancelAndResume() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        for name in ["unknown", "query_request", "control_request", "execute_request", "cancel_request", "resume_request"] {
            let bytes = Data((#"{"protocol_version":4,"type":""# + name + #"","payload":{"schema":"healthmd.agent_discovery_request","schema_version":1,"request_id":"00000000-0000-4000-8000-000000000064","peer":{"source_installation_id":"00000000-0000-4000-8000-000000000001","host_installation_id":"00000000-0000-4000-8000-000000000002","platform":"apple"}}}"#).utf8)
            XCTAssertThrowsError(try rig.service.handle(bytes, authenticatedPeer: rig.peer, now: rig.now))
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
        try rig.service.storeNativeDecision(planID: first.planId, binding: firstBinding, approvalID: id(8), authenticatedPeer: rig.peer, now: rig.now,
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
        XCTAssertThrowsError(try rig.service.handle(requestBytes, authenticatedPeer: copiedContext, now: rig.now)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: copiedContext, now: rig.now,
                                                               authorization: FakeNativeAuthorization(binding: binding))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertThrowsError(try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: copiedContext, now: rig.now)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
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
        XCTAssertEqual(rig.reader.calls, ["discovery", "explicit"])
    }

    func testRevocationInsideNativeDecisionAdapterCannotCommitOrReturnApproval() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        let before = try rig.store.snapshot().generation
        let nativeDecision = FakeNativeAuthorization(binding: binding, afterAuthorization: { rig.session.revoke() })
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer, now: rig.now,
                                                               authorization: nativeDecision)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
    }

    func testConcurrentActualHandlesSerializeDiscoveryAndExactPlanCAS() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let discoveryBytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer))))
        let discoveries = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<8 { group.addTask { @MainActor in try rig.service.handle(discoveryBytes, authenticatedPeer: rig.peer, now: rig.now) } }
            var results: [Data] = []; for try await result in group { results.append(result) }; return results
        }
        XCTAssertEqual(Set(discoveries).count, 1)
        guard case .discovery(let discovery) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: discoveries[0]).payload else { return XCTFail("discovery") }
        let requestBytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(rig.request(discovery: discovery))))
        let replies = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<8 { group.addTask { @MainActor in try rig.service.handle(requestBytes, authenticatedPeer: rig.peer, now: rig.now) } }
            var results: [Data] = []; for try await result in group { results.append(result) }; return results
        }
        XCTAssertEqual(Set(replies).count, 1)
        XCTAssertEqual(try rig.store.snapshot().generation, 2) // One grant, one issued-plan transaction.
        XCTAssertEqual(try rig.store.snapshot().plans.count, 1)
        let changed = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(rig.request(discovery: discovery, metrics: ["heart_rate_min"]))))
        let contested = try await withThrowingTaskGroup(of: Data.self) { group in
            for bytes in [requestBytes, changed] { group.addTask { @MainActor in try rig.service.handle(bytes, authenticatedPeer: rig.peer, now: rig.now) } }
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
        XCTAssertEqual(try error(rig.restartedService().handle(bytes, authenticatedPeer: rig.peer, now: rig.now)), .planExpired)
        XCTAssertEqual(try error(rig.service.handle(bytes, authenticatedPeer: rig.peer, now: rig.now.addingTimeInterval(600))), .planExpired)
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
            XCTAssertThrowsError(try rig.service.handle(invalid, authenticatedPeer: rig.peer, now: rig.now))
        }
        XCTAssertEqual(rig.reader.calls.count, 0)
    }

    // Independently worked 7,706-byte canonical v4 response, not generated by this service.
    private static let tracerResponseSHA256 = "60acf10c969ff25cce712784a40f725d9d56cee30f90744a59e21ca0a409cd95"
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

nonisolated private final class RevocableNativeSession: AgentBridgeExportNativeSessionChecking, @unchecked Sendable {
    private let lock = NSLock()
    private let authenticatedPeer: AgentBridgePeer
    private var revoked = false
    init(source: UUID, host: UUID) throws {
        authenticatedPeer = try .init(sourceInstallationID: AgentBridgeUUID(source.uuidString.lowercased()), hostInstallationID: AgentBridgeUUID(host.uuidString.lowercased()), platform: .apple)
    }
    func requireCurrent(peer: AgentBridgePeer) throws {
        lock.lock(); defer { lock.unlock() }
        guard !revoked, peer == authenticatedPeer else { throw AgentBridgeValidationError.permissionRequired }
    }
    func revoke() { lock.lock(); defer { lock.unlock() }; revoked = true }
}

nonisolated private final class FakeProtectedKeys: AgentBridgeExportProtectedKeyReading, @unchecked Sendable {
    let key: SymmetricKey?
    init(key: SymmetricKey? = SymmetricKey(data: Data(repeating: 9, count: 32))) { self.key = key }
    func loadExistingExportAuthorityKey() throws -> SymmetricKey? { key }
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
    func readConfiguration(for peer: AgentBridgeExportAuthenticatedPeer, policy: AgentBridgeSettingsPolicy?) throws -> AgentBridgeExportPlanningConfiguration {
        let kind: String
        switch policy { case nil: kind = "discovery"; case .explicit: kind = "explicit"; case .savedDeviceSettings: kind = "saved"; case .profile: kind = "profile" }
        calls.append(kind)
        if kind == "saved" || kind == "profile" { _ = defaults.string(forKey: "sentinel") }
        beforeReturn?()
        return try .init(inputs: inputs, deviceSettingsObjectID: id(5), sourceCalendarTimezone: AgentBridgeZone("America/Los_Angeles"), configurationProtection: protection,
                         nativeGrants: grants, entitlement: entitlement, foregroundAvailable: true, protectedDataAvailable: true)
    }
}
@MainActor
private final class Rig {
    let parent: URL
    let directory: URL
    let keys = FakeProtectedKeys()
    let reader: ConfigurationProbe
    let store: AgentBridgeExportAuthorityStore
    let service: AgentBridgeExportPlanningService
    let peer: AgentBridgeExportAuthenticatedPeer
    let session: RevocableNativeSession
    let now = ISO8601DateFormatter().date(from: "2026-03-09T00:00:00Z")!
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }
    init(withSaved: Bool = false) throws {
        parent = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("healthmd-native-planning-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        directory = parent.appendingPathComponent("authority")
        let source = try XCTUnwrap(UUID(uuidString: id(1).rawValue)), host = try XCTUnwrap(UUID(uuidString: id(2).rawValue))
        session = try RevocableNativeSession(source: source, host: host)
        peer = try .init(nativeSourceInstallationID: source, authenticatedHostInstallationID: host, currentNativeSession: session)
        reader = try ConfigurationProbe()
        store = try AgentBridgeExportAuthorityStore.createPrivateStore(at: directory, protectedKeys: keys, authorization: FakeNativeAuthorization())
        var nextPlanID = 6
        service = AgentBridgeExportPlanningService(store: store, configuration: reader, newPlanID: {
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
    func send(_ document: AgentBridgeDocument) throws -> Data { try service.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: document)), authenticatedPeer: peer, now: now) }
    func expectError(_ wanted: AgentBridgeErrorCode, request: AgentBridgeDocument) throws { XCTAssertEqual(try error(send(request)), wanted) }
    func restartedService() throws -> AgentBridgeExportPlanningService { AgentBridgeExportPlanningService(store: try .init(existingDirectory: directory, protectedKeys: keys), configuration: reader, newPlanID: { throw AgentBridgeValidationError.invalidRequest }) }
}
