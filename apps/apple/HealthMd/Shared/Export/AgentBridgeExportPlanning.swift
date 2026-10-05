import Foundation
import HealthMdConnectionCore

/// Trusted, non-wire live time source. Native adapters inject this dependency, never request dates
/// or a request-wide timestamp. The production default samples wall time at each actual boundary.
nonisolated protocol AgentBridgeExportClock: Sendable {
    func now() -> Date
}
nonisolated struct AgentBridgeExportSystemClock: AgentBridgeExportClock {
    func now() -> Date { Date() }
}

/// Non-wire native session/trust boundary. Implementers recheck current trust/revocation and the
/// authenticated channel's exact installations; immutable copied IDs alone are never sufficient.
nonisolated protocol AgentBridgeExportNativeSessionChecking: Sendable {
    func requireCurrent(peer: AgentBridgePeer) throws
}

/// Constructed ONLY by a native authenticated-channel adapter, not decoded from a request.
/// Pairing proves identities, not export rights. Copies retain the SAME revocable native session.
nonisolated struct AgentBridgeExportAuthenticatedPeer: Sendable {
    let peer: AgentBridgePeer
    private let session: any AgentBridgeExportNativeSessionChecking
    init(nativeSourceInstallationID: UUID, authenticatedHostInstallationID: UUID,
         currentNativeSession: any AgentBridgeExportNativeSessionChecking) throws {
        peer = try .init(sourceInstallationID: AgentBridgeUUID(nativeSourceInstallationID.uuidString.lowercased()),
                         hostInstallationID: AgentBridgeUUID(authenticatedHostInstallationID.uuidString.lowercased()), platform: .apple)
        session = currentNativeSession
    }
    func requireCurrent() throws {
        do { try session.requireCurrent(peer: peer) }
        catch { throw AgentBridgeValidationError.permissionRequired }
    }
}

/// Fences the separate native decision adapter as well as its service entry/return. A native
/// authorizer cannot revoke the session during consent and still commit through copied identities.
nonisolated private struct AgentBridgeExportSessionBoundAuthorization: AgentBridgeExportNativeAuthorizing {
    let peer: AgentBridgeExportAuthenticatedPeer
    let native: any AgentBridgeExportNativeAuthorizing
    func requireNativeAuthorization(for action: AgentBridgeExportNativeAction) throws {
        try peer.requireCurrent()
        try native.requireNativeAuthorization(for: action)
        try peer.requireCurrent()
    }
}

/// Trusted configuration/readiness inputs. Selection availability is NOT native consent.
/// Configuration Protection is independent of export consent, protected data and entitlements.
struct AgentBridgeExportPlanningConfiguration {
    let inputs: AgentBridgeRequestSettingsInputs
    let deviceSettingsObjectID: AgentBridgeUUID
    let sourceCalendarTimezone: AgentBridgeZone
    let configurationProtection: AgentBridgeDiscoveryConfigurationProtection
    // Native opt-in/authorization-flow evidence only. HealthKit read denial may be indistinguishable
    // from empty: `satisfied` NEVER proves per-type read permission from selection availability.
    let nativeGrants: AgentBridgeDiscoveryNativeGrants
    let entitlement: AgentBridgeDiscoveryEntitlement
    let foregroundAvailable: Bool
    let protectedDataAvailable: Bool
}

/// Configuration-only native dependency. Implementers must return immutable snapshots and advance
/// catalog.revision on advertised capability/readiness changes. No health/provider/earliest/preview,
/// output/quota, unlock, credential or wake dependency is accepted by this source service.
@MainActor
protocol AgentBridgeExportPlanningConfigurationReading {
    func readConfiguration(for peer: AgentBridgeExportAuthenticatedPeer, policy: AgentBridgeSettingsPolicy?) throws -> AgentBridgeExportPlanningConfiguration
}

/// Production bounded source seam for a LATER IPhoneDirectCLIService adapter. Strict request bytes
/// enter only after authentication/independent v4 negotiation by that adapter. It remains unwired;
/// no hello advertising, TCP dispatch, UI enrollment, capture, execution, resume or cancel here.
/// Explicit actor isolation serializes the synchronous service and discovery cache regardless of
/// the surrounding target's default isolation; no mutable state relies on an inferred build flag.
@MainActor
final class AgentBridgeExportPlanningService {
    private let store: AgentBridgeExportAuthorityStore
    private let configuration: any AgentBridgeExportPlanningConfigurationReading
    private let clock: any AgentBridgeExportClock
    private let newPlanID: () throws -> AgentBridgeUUID
    // Transient issued discovery evidence; read-only discovery never mutates the private store.
    // Restart requires a fresh discovery for NEW plans, not for exact persisted-plan retries.
    private var issuedDiscoveries: [String: AgentBridgeDiscovery] = [:]
    init(store: AgentBridgeExportAuthorityStore, configuration: any AgentBridgeExportPlanningConfigurationReading,
         clock: any AgentBridgeExportClock = AgentBridgeExportSystemClock(),
         newPlanID: @escaping () throws -> AgentBridgeUUID = { try AgentBridgeUUID(UUID().uuidString.lowercased()) }) {
        self.store = store; self.configuration = configuration; self.clock = clock; self.newPlanID = newPlanID
    }

    func handle(_ bytes: Data, authenticatedPeer: AgentBridgeExportAuthenticatedPeer) throws -> Data {
        try authenticatedPeer.requireCurrent()
        let envelope = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes)
        let requestID: AgentBridgeUUID
        switch envelope.payload {
        case .discoveryRequest(let request): requestID = request.requestID
        case .planRequest(let request): requestID = request.requestId
        case .approvalRequest(let request): requestID = request.requestId
        default: throw AgentBridgeValidationError.unsupportedCapability
        }
        do {
            let response: AgentBridgeDocument
            switch envelope.payload {
            case .discoveryRequest(let request):
                try requirePeer(request.peer, authenticatedPeer)
                let state = try store.snapshot()
                let config = try configuration.readConfiguration(for: authenticatedPeer, policy: nil)
                try authenticatedPeer.requireCurrent()
                let value = try discovery(requestID: requestID, peer: authenticatedPeer, config: config, state: state, now: clock.now())
                response = .discovery(value)
            case .planRequest(let request):
                try requirePeer(request.intent.peer, authenticatedPeer)
                response = .plan(try plan(request, exactRequestBytes: bytes, peer: authenticatedPeer))
            case .approvalRequest(let request):
                try requirePeer(request.binding.peer, authenticatedPeer)
                response = .approval(try relayApproval(request, peer: authenticatedPeer))
            default: throw AgentBridgeValidationError.unsupportedCapability
            }
            let responseBytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: response))
            // Serialization, protected-key/configuration reads and the LAST session callback must
            // all finish BEFORE the return-time check. Even exact cached responses pass this fence.
            try validateResponse(response, peer: authenticatedPeer)
            if case .discovery(let value) = response {
                let key = peerKey(authenticatedPeer)
                guard issuedDiscoveries[key] != nil || issuedDiscoveries.count < 32 else { throw AgentBridgeValidationError.busy }
                issuedDiscoveries[key] = value // No stale discovery is published into the cache.
            }
            return responseBytes
        } catch let error as AgentBridgeValidationError {
            try authenticatedPeer.requireCurrent()
            // Fixed code only: no rejected path, identity, date, settings, parser text or secret.
            let responseBytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .error(.init(
                code: AgentBridgeErrorCode(rawValue: error.rawValue) ?? .invalidRequest,
                requestId: requestID, retryable: error == .busy || error == .revisionConflict))))
            try authenticatedPeer.requireCurrent()
            return responseBytes
        } catch {
            try authenticatedPeer.requireCurrent()
            let responseBytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .error(.init(code: .bindingChanged, requestId: requestID, retryable: false))))
            try authenticatedPeer.requireCurrent()
            return responseBytes
        }
    }

    /// Separate local-native exact decision. NOT reachable from handle(), JSON or an MCP annotation.
    /// The native authorizer must independently approve this complete issued binding, never a flag.
    func storeNativeDecision(planID: AgentBridgeUUID, binding: AgentBridgeBinding, approvalID: AgentBridgeUUID,
                             authenticatedPeer: AgentBridgeExportAuthenticatedPeer,
                             authorization: any AgentBridgeExportNativeAuthorizing) throws {
        try authenticatedPeer.requireCurrent()
        try requirePeer(binding.peer, authenticatedPeer)
        let state = try store.snapshot()
        let current = try currentPlan(in: state, planID: planID, peer: authenticatedPeer, right: .exportExecute, requireReadiness: true)
        guard binding == AgentBridgeSemantics.binding(current.plan) else { throw AgentBridgeValidationError.bindingChanged }
        try store.persistNativeDecision(planID: planID, binding: binding, expectedGeneration: state.generation,
            authorization: AgentBridgeExportSessionBoundAuthorization(peer: authenticatedPeer, native: authorization),
            makeDecision: { currentState in
                // Consent AND protected-key lookup have completed. Use the locked transaction's
                // real state, refreshed configuration and live time, not pre-consent captured records.
                let checked = try self.currentPlan(in: currentState, planID: planID, peer: authenticatedPeer, right: .exportExecute, requireReadiness: true)
                guard binding == AgentBridgeSemantics.binding(checked.plan) else { throw AgentBridgeValidationError.bindingChanged }
                if let previous = currentState.decisions.first(where: { $0.planID == planID }) {
                    let approval = try previous.approval()
                    guard approval.approvalId == approvalID, approval.binding == binding else { throw AgentBridgeValidationError.bindingChanged }
                    return previous // Exact decision retry never changes approved_at or expiry.
                }
                let approval = AgentBridgeApproval(approvalId: approvalID, approvedAt: try self.utc(checked.now),
                    authorityId: checked.plan.authorityReferences.native.authorityId, binding: binding, rights: [.exportExecute])
                return try .init(planID: planID, approvalBytes: AgentBridgeV4Codec.encode(approval))
            }, requireCurrentAuthority: { currentState in
                _ = try self.currentDecision(in: currentState, planID: planID, peer: authenticatedPeer)
            })
        // A post-publication delay can suppress return but cannot roll back committed private
        // metadata. Every later relay/scope/retry independently rejects expired/revoked records.
        try store.inspectCurrent { currentState in
            _ = try self.currentDecision(in: currentState, planID: planID, peer: authenticatedPeer)
        }
    }

    /// Source-derived sanitized scope for a later adapter. The HOST must independently derive and
    /// verify its own authority/root; neither its wire reference nor this value establishes host rights.
    func nativeScopedAuthority(planID: AgentBridgeUUID, authenticatedPeer: AgentBridgeExportAuthenticatedPeer) throws -> AgentBridgeAuthority {
        try authenticatedPeer.requireCurrent()
        return try store.inspectCurrent { state in
            let checked = try self.currentPlan(in: state, planID: planID, peer: authenticatedPeer, right: .plan)
            let parent = try self.currentParent(for: checked.plan, state: state, peer: authenticatedPeer, now: checked.now)
            let authority = try self.scopedNativeAuthority(parent: parent, plan: checked.plan, config: checked.config)
            try self.requireLifetime(checked.plan, state: state, peer: authenticatedPeer, now: self.clock.now())
            return authority
        }
    }

    private func plan(_ request: AgentBridgePlanRequest, exactRequestBytes: Data, peer: AgentBridgeExportAuthenticatedPeer) throws -> AgentBridgePlan {
        let state = try store.snapshot()
        let existing = try state.plans.first { try $0.request().requestId == request.requestId && $0.request().intent.peer == peer.peer }
        if let existing, existing.requestBytes != exactRequestBytes { throw AgentBridgeValidationError.bindingChanged }
        let parent = try state.delegation(id: request.authorityId, revision: request.authorityRevision, peer: peer.peer, now: utc(clock.now()))
        guard request.hostAuthorityReference.issuer == .authorizedHost, request.hostAuthorityReference.authorityId != parent.authorityID else { throw AgentBridgeValidationError.approvalRequired }
        let config = try configuration.readConfiguration(for: peer, policy: request.intent.settingsPolicy)
        try peer.requireCurrent()
        let now = clock.now()
        _ = try state.delegation(id: request.authorityId, revision: request.authorityRevision, peer: peer.peer, now: utc(now))
        let current = try discovery(requestID: request.requestId, peer: peer, config: config, state: state, now: now)
        guard current.capabilitySha256 == request.capabilitySha256 else { throw AgentBridgeValidationError.bindingChanged }
        guard current.authorityReferences.contains(try parent.reference()) else { throw AgentBridgeValidationError.approvalRequired }
        if let existing { return try revalidate(existing, state: state, config: config, peer: peer, now: now, right: .plan) }
        guard let advertised = issuedDiscoveries[peerKey(peer)], advertised.capabilitySha256 == request.capabilitySha256,
              advertised.issuedAt.rawValue <= (try utc(now)).rawValue, advertised.expiresAt.rawValue > (try utc(now)).rawValue else { throw AgentBridgeValidationError.planExpired }
        let resolution = try resolve(request.intent, config: config, now: now)
        let native = resolution.native, output = resolution.effectiveOutput
        let metrics = try native.selection.map { try AgentBridgeID($0.semanticID) }
        try AgentBridgeDelegationSemantics.requireGeneratedScope(parent, intent: request.intent, effective: output, resolvedDates: native.dates,
                                                                metricIDs: metrics, now: utc(now), right: .plan)
        let expiration = min(try instant(parent.expiresAt), wholeSecond(now).addingTimeInterval(600))
        guard expiration > wholeSecond(now) else { throw AgentBridgeValidationError.planExpired }
        let revision = native.settingsRevision ?? 0
        let outputOrigin = AgentBridgeOriginOrigin(rawValue: native.settingsOrigin.rawValue)!
        var origins = try leafPointers(output, prefix: "/effective_settings").map { AgentBridgeOrigin(origin: outputOrigin, pointer: $0, revision: revision) }
        origins += try leafPointers(request.intent.captureScope, prefix: "/capture_scope").map { .init(origin: .request, pointer: $0, revision: 0) }
        origins += [.init(origin: .resolvedCalendar, pointer: "/resolved_dates", revision: 0), .init(origin: .request, pointer: "/calendar_timezone", revision: 0)]
        let settingsDigest = try AgentBridgeDigest(AgentBridgeV4Codec.digest(output))
        let revisions: [AgentBridgeRevision]
        switch request.intent.settingsPolicy {
        case .explicit: revisions = []
        case .savedDeviceSettings: revisions = [.init(domain: .deviceSettings, objectId: config.deviceSettingsObjectID, revision: revision, sha256: settingsDigest)]
        case .profile(let id, _): revisions = [.init(domain: .nativeProfile, objectId: id, revision: revision, sha256: settingsDigest)]
        }
        let id = try newPlanID()
        let unresolved = native.dates == .allAvailable
        func candidate(_ digest: AgentBridgeDigest) throws -> AgentBridgePlan {
            try .init(authorityReferences: .init(host: request.hostAuthorityReference, native: parent.reference()), capabilitySha256: current.capabilitySha256,
                      effectiveSettings: output, expiresAt: utc(expiration), intent: request.intent, issuedAt: utc(now),
                      limitations: [AgentBridgeID("healthkit_read_authorization_unobservable")] + (unresolved ? [AgentBridgeID("history_bounds_unresolved")] : []), origins: origins.sorted { $0.pointer < $1.pointer },
                      pathPrediction: unresolved ? .templateOnlyAllAvailable : .exactRequestedDays, planId: id, planSha256: digest,
                      predictedPaths: native.predictedRelativePaths.map(AgentBridgePath.init), requiredActions: current.requiredActions.map { try AgentBridgeID($0.rawValue) },
                      resolvedDates: native.dates, resolvedMetricIds: metrics, revisions: revisions,
                      scopeSha256: AgentBridgeSemantics.scopeDigest(intent: request.intent, resolvedDates: native.dates, metricIDs: metrics),
                      settingsSha256: settingsDigest, sideEffects: .init())
        }
        let issued = try candidate(AgentBridgeSemantics.planDigest(candidate(zeroDigest())))
        let record = try AgentBridgeExportIssuedPlan(version: 1, requestBytes: exactRequestBytes, planBytes: AgentBridgeV4Codec.encode(issued),
                                                     nativeResolution: PropertyListEncoder().encode(native),
                                                     nativeAuthorityBytes: AgentBridgeV4Codec.encode(scopedNativeAuthority(parent: parent, plan: issued, config: config)))
        // Explicit MainActor serialization covers the entire synchronous service in BOTH ordinary
        // and default-MainActor builds. Independent issuer-store handles still require bounded CAS.
        return try store.persistIssuedPlan(record, expectedGeneration: state.generation, requireCurrentAuthority: { currentState in
            let checked = try self.currentPlan(in: currentState, planID: id, peer: peer, right: .plan)
            guard advertised.issuedAt.rawValue <= (try self.utc(checked.now)).rawValue,
                  advertised.expiresAt.rawValue > (try self.utc(checked.now)).rawValue else { throw AgentBridgeValidationError.planExpired }
        }).plan()
    }

    private func relayApproval(_ request: AgentBridgeApprovalRequest, peer: AgentBridgeExportAuthenticatedPeer) throws -> AgentBridgeApproval {
        try store.inspectCurrent { state in
            let record = try state.issued(id: request.planId, peer: peer.peer)
            guard try request.binding == AgentBridgeSemantics.binding(record.plan()) else { throw AgentBridgeValidationError.bindingChanged }
            return try self.currentDecision(in: state, planID: request.planId, peer: peer)
        } // No decision issuance/persistence from an approval_request.
    }

    private func validateResponse(_ response: AgentBridgeDocument, peer: AgentBridgeExportAuthenticatedPeer) throws {
        try store.inspectCurrent { state in
            switch response {
            case .discovery(let value):
                let config = try self.configuration.readConfiguration(for: peer, policy: nil)
                try peer.requireCurrent()
                let now = self.clock.now()
                guard value.issuedAt.rawValue <= (try self.utc(now)).rawValue, value.expiresAt.rawValue > (try self.utc(now)).rawValue else { throw AgentBridgeValidationError.planExpired }
                let current = try self.discovery(requestID: value.requestId, peer: peer, config: config, state: state, now: now)
                guard current.authorityReferences == value.authorityReferences else { throw AgentBridgeValidationError.approvalRequired }
                guard current.capabilitySha256 == value.capabilitySha256 else { throw AgentBridgeValidationError.bindingChanged }
                let finalNow = try self.utc(self.clock.now())
                guard value.expiresAt.rawValue > finalNow.rawValue else { throw AgentBridgeValidationError.planExpired }
                guard try state.references(peer: peer.peer, now: finalNow) == value.authorityReferences else { throw AgentBridgeValidationError.approvalRequired }
            case .plan(let value):
                let checked = try self.currentPlan(in: state, planID: value.planId, peer: peer, right: .plan)
                guard checked.plan == value else { throw AgentBridgeValidationError.bindingChanged }
            case .approval(let value):
                let record = try state.plans.first { try $0.plan().planSha256 == value.binding.planSha256 && $0.plan().intent.peer == peer.peer }
                guard let record, try self.currentDecision(in: state, planID: record.plan().planId, peer: peer) == value else { throw AgentBridgeValidationError.approvalRequired }
            default: throw AgentBridgeValidationError.unsupportedCapability
            }
        }
    }

    private func currentDecision(in state: AgentBridgeExportAuthoritySnapshot, planID: AgentBridgeUUID, peer: AgentBridgeExportAuthenticatedPeer) throws -> AgentBridgeApproval {
        let checked = try currentPlan(in: state, planID: planID, peer: peer, right: .exportExecute, requireReadiness: true)
        guard let decision = state.decisions.first(where: { $0.planID == planID }) else { throw AgentBridgeValidationError.approvalRequired }
        let approval = try decision.approval()
        guard approval.binding == AgentBridgeSemantics.binding(checked.plan), approval.authorityId == checked.plan.authorityReferences.native.authorityId,
              approval.approvedAt.rawValue >= checked.plan.issuedAt.rawValue, approval.approvedAt.rawValue < checked.plan.expiresAt.rawValue,
              approval.approvedAt.rawValue <= (try utc(checked.now)).rawValue else { throw AgentBridgeValidationError.approvalRequired }
        try requireLifetime(checked.plan, state: state, peer: peer, now: clock.now())
        return approval
    }

    private func currentParent(for plan: AgentBridgePlan, state: AgentBridgeExportAuthoritySnapshot, peer: AgentBridgeExportAuthenticatedPeer, now: Date) throws -> AgentBridgeExportDelegation {
        let ref = plan.authorityReferences.native
        let parent = try state.delegation(id: ref.authorityId, revision: ref.grantRevision, peer: peer.peer, now: utc(now))
        guard try parent.reference() == ref else { throw AgentBridgeValidationError.approvalRequired }
        return parent
    }

    private func requireLifetime(_ plan: AgentBridgePlan, state: AgentBridgeExportAuthoritySnapshot, peer: AgentBridgeExportAuthenticatedPeer, now: Date) throws {
        guard plan.issuedAt.rawValue <= (try utc(now)).rawValue, plan.expiresAt.rawValue > (try utc(now)).rawValue else { throw AgentBridgeValidationError.planExpired }
        _ = try currentParent(for: plan, state: state, peer: peer, now: now)
    }

    private func currentPlan(in state: AgentBridgeExportAuthoritySnapshot, planID: AgentBridgeUUID, peer: AgentBridgeExportAuthenticatedPeer,
                             right: AgentBridgeDelegationRight, requireReadiness: Bool = false) throws -> (plan: AgentBridgePlan, config: AgentBridgeExportPlanningConfiguration, now: Date) {
        let record = try state.issued(id: planID, peer: peer.peer)
        let config = try configuration.readConfiguration(for: peer, policy: record.request().intent.settingsPolicy)
        try peer.requireCurrent() // The LAST potentially delaying session callback precedes live time.
        let now = clock.now()
        let plan = try revalidate(record, state: state, config: config, peer: peer, now: now, right: right)
        if requireReadiness { try requireNativeReadiness(config) }
        let finalNow = clock.now() // Also fence pure decoding/hash/resolver work after the callbacks.
        try requireLifetime(plan, state: state, peer: peer, now: finalNow)
        return (plan, config, finalNow)
    }

    private func revalidate(_ record: AgentBridgeExportIssuedPlan, state: AgentBridgeExportAuthoritySnapshot, config: AgentBridgeExportPlanningConfiguration,
                            peer: AgentBridgeExportAuthenticatedPeer, now: Date, right: AgentBridgeDelegationRight) throws -> AgentBridgePlan {
        let issued = try record.plan(), request = try record.request()
        try requirePeer(issued.intent.peer, peer)
        guard issued.issuedAt.rawValue <= (try utc(now)).rawValue, issued.expiresAt.rawValue > (try utc(now)).rawValue else { throw AgentBridgeValidationError.planExpired }
        let parent = try state.delegation(id: issued.authorityReferences.native.authorityId, revision: issued.authorityReferences.native.grantRevision,
                                          peer: peer.peer, now: utc(now))
        guard try parent.reference() == issued.authorityReferences.native else { throw AgentBridgeValidationError.approvalRequired }
        let current = try discovery(requestID: request.requestId, peer: peer, config: config, state: state, now: now)
        guard current.capabilitySha256 == issued.capabilitySha256 else { throw AgentBridgeValidationError.bindingChanged }
        let frozen: AgentBridgeRequestSettingsResolution
        do { frozen = try PropertyListDecoder().decode(AgentBridgeRequestSettingsResolution.self, from: record.nativeResolution) }
        catch { throw AgentBridgeValidationError.bindingChanged }
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: issued.intent.calendarTimezone.rawValue)!
        try AgentBridgeRequestSettingsResolver.validateForReuse(frozen, intent: issued.intent, inputs: config.inputs, calendar: calendar)
        let output = try AgentBridgeRequestSettingsResolver.resolveWithOutput(issued.intent, inputs: config.inputs, clock: frozen.resolvedAt, calendar: calendar)
        guard output.effectiveOutput == issued.effectiveSettings, frozen.dates == issued.resolvedDates,
              frozen.predictedRelativePaths == issued.predictedPaths.map(\.rawValue), frozen.requestedDays.count <= 366 else { throw AgentBridgeValidationError.bindingChanged }
        try AgentBridgeDelegationSemantics.requireGeneratedScope(parent, intent: issued.intent, effective: issued.effectiveSettings, resolvedDates: issued.resolvedDates,
                                                                metricIDs: issued.resolvedMetricIds, now: utc(now), right: right)
        guard try AgentBridgeV4Codec.encode(scopedNativeAuthority(parent: parent, plan: issued, config: config)) == record.nativeAuthorityBytes else { throw AgentBridgeValidationError.bindingChanged }
        return issued
    }

    private func resolve(_ intent: AgentBridgeGeneratedIntent, config: AgentBridgeExportPlanningConfiguration, now: Date) throws -> AgentBridgeRequestSettingsOutputResolution {
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = TimeZone(identifier: intent.calendarTimezone.rawValue)!
        let result = try AgentBridgeRequestSettingsResolver.resolveWithOutput(intent, inputs: config.inputs, clock: wholeSecond(now), calendar: calendar)
        guard result.native.requestedDays.count <= 366 else { throw AgentBridgeValidationError.queryBudgetExceeded }
        return result
    }

    private func scopedNativeAuthority(parent: AgentBridgeExportDelegation, plan: AgentBridgePlan, config: AgentBridgeExportPlanningConfiguration) throws -> AgentBridgeAuthority {
        guard parent.issuer == .nativeSource, parent.peer == plan.intent.peer, parent.expiresAt.rawValue >= plan.expiresAt.rawValue else { throw AgentBridgeValidationError.approvalRequired }
        return .init(authorityId: parent.authorityID, configurationProtection: .notApplicable,
                     destinationBindingIds: [plan.intent.destination.bindingID], entitlement: config.entitlement == .satisfied ? .satisfied : .required,
                     expiresAt: plan.expiresAt, grantRevision: parent.grantRevision, issuer: .nativeSource,
                     nativeConsent: config.nativeGrants == .satisfied ? .satisfied : .required, peer: parent.peer,
                     rights: parent.rights.map { AgentBridgeAuthorityRights(rawValue: $0.rawValue)! }, scopeSha256: plan.scopeSha256)
    }

    private func discovery(requestID: AgentBridgeUUID, peer: AgentBridgeExportAuthenticatedPeer, config: AgentBridgeExportPlanningConfiguration,
                           state: AgentBridgeExportAuthoritySnapshot, now: Date) throws -> AgentBridgeDiscovery {
        let refs = try state.references(peer: peer.peer, now: utc(now))
        var actions: [AgentBridgeDiscoveryRequiredActions] = []
        if !config.foregroundAvailable { actions.append(.openMobileApp) }
        if !config.protectedDataAvailable { actions.append(.unlockMobile) }
        if config.nativeGrants != .satisfied { actions.append(.grantHealthAccess) }
        if config.entitlement != .satisfied { actions.append(.purchaseRequired) }
        var policies: [AgentBridgeDiscoverySettingsPolicies] = [.explicit]
        if !config.inputs.profiles.isEmpty { policies.append(.profile) }
        if config.inputs.savedDevice != nil { policies.append(.savedDeviceSettings) }
        let support = try AgentBridgeOutputSupport(compatibilityDetail: [.summary], formats: [.json], maxArtifacts: 366, maxPathBytes: 4096,
                                                  nativeArchiveProducts: [.none], pathTokens: [.date, .day, .month, .year],
                                                  settingPointers: leafPointers(Self.defaultOutput, prefix: ""), writeModes: [.overwrite])
        func value(_ digest: AgentBridgeDigest) throws -> AgentBridgeDiscovery {
            try .init(authorityReferences: refs, budgets: .init(cursorIdleSeconds: 1, cursorLifetimeSeconds: 1, maxCalendarDays: 366,
                                                               maxCaptureSeconds: 1, maxPageBytes: 1024, maxPageItems: 1, maxSnapshotBytes: 1024),
                      capabilityRevision: config.inputs.catalog.revision, capabilitySha256: digest, configurationProtection: config.configurationProtection,
                      controlOperations: [], entitlement: config.entitlement, expiresAt: utc(wholeSecond(now).addingTimeInterval(600)),
                      features: [.explicitSettings, .zeroHealthPlan], issuedAt: utc(now), lifecycle: .iphoneForegroundProtectedData,
                      nativeGrants: config.nativeGrants, outputProfiles: [.appleV8], outputSupport: support, peer: peer.peer,
                      projectionCatalogSha256: zeroDigest(), projectionProducts: [], queryCatalogSha256: zeroDigest(), queryOperations: [], requestId: requestID,
                      requiredActions: actions.sorted { $0.rawValue < $1.rawValue }, settingsPolicies: policies, sourceCalendarTimezone: config.sourceCalendarTimezone)
        }
        return try value(AgentBridgeSemantics.capabilityDigest(value(zeroDigest())))
    }

    private func requireNativeReadiness(_ config: AgentBridgeExportPlanningConfiguration) throws {
        guard config.foregroundAvailable, config.protectedDataAvailable, config.nativeGrants == .satisfied else { throw AgentBridgeValidationError.permissionRequired }
        guard config.entitlement == .satisfied else { throw AgentBridgeValidationError.entitlementRequired }
        // Locked Configuration Protection does not upgrade to unlocked and does not block read-only
        // planning/export delegation. No configuration mutation right exists at this seam.
    }
    private func peerKey(_ context: AgentBridgeExportAuthenticatedPeer) -> String {
        context.peer.sourceInstallationID.rawValue + "/" + context.peer.hostInstallationID.rawValue
    }
    private func requirePeer(_ value: AgentBridgePeer, _ context: AgentBridgeExportAuthenticatedPeer) throws {
        guard value == context.peer else { throw AgentBridgeValidationError.bindingChanged }
    }
    private func wholeSecond(_ date: Date) -> Date { Date(timeIntervalSince1970: floor(date.timeIntervalSince1970)) }
    private func utc(_ date: Date) throws -> AgentBridgeUTC {
        guard date.timeIntervalSince1970.isFinite, (-62_135_596_800...253_402_300_199).contains(date.timeIntervalSince1970) else { throw AgentBridgeValidationError.invalidRequest }
        let formatter = ISO8601DateFormatter(); formatter.timeZone = TimeZone(secondsFromGMT: 0)
        return try AgentBridgeUTC(formatter.string(from: wholeSecond(date)))
    }
    private func instant(_ date: AgentBridgeUTC) throws -> Date {
        guard let value = ISO8601DateFormatter().date(from: date.rawValue) else { throw AgentBridgeValidationError.invalidRequest }
        return value
    }
    private func zeroDigest() throws -> AgentBridgeDigest { try AgentBridgeDigest(String(repeating: "0", count: 64)) }

    /// Typed configuration only; arrays (including ordered presentation) are one origin each.
    private func leafPointers<T: Encodable>(_ value: T, prefix: String) throws -> [String] {
        let json = try JSONSerialization.jsonObject(with: AgentBridgeV4Codec.encode(value))
        func walk(_ object: Any, _ pointer: String) -> [String] {
            guard let fields = object as? [String: Any] else { return [pointer] }
            return fields.keys.sorted().flatMap { walk(fields[$0]!, pointer + "/" + $0) }
        }
        return walk(json, prefix).sorted()
    }
    static let defaultOutput = AgentBridgeOutputSettings(
        formats: [.json], outputProfile: .appleV8, subfolder: "", folderTemplate: "{year}", filenameTemplate: "{date}", writeMode: .overwrite,
        presentation: .init(displayUnits: .metric, locale: "en-US", includeMetadata: true, groupByCategory: true,
                            frontmatter: .init(enabledFieldIDs: [], customFields: [], includeUnits: true, includeCaptureDiagnostics: false),
                            markdown: .init(style: .lists, customTemplate: "", placeholderIDs: [])),
        individualEntries: .init(enabled: false, metricIDs: [], folderTemplate: "", filenameTemplate: "{metric}-{date}", categoryFolders: false),
        dailyNotes: .init(enabled: false, only: false, folderTemplate: "", filenameTemplate: "{date}", createIfMissing: false, sectionIDs: []),
        packaging: .looseFiles, dictionary: .none)
}
