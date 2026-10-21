import Foundation
import HealthMdConnectionCore

/// A native lifecycle/controller samples these facts and publishes their revision in signed issuer
/// storage when readiness/configuration changes. This value cannot be decoded from a wire request.
/// HealthKit's satisfied flag is authorization-flow evidence, never proof of per-type read grants.
nonisolated struct AgentBridgeNativePlanningFacts: Equatable, Sendable {
    let availableNativeMetricIDs: Set<String>
    let sourceCalendarTimezone: AgentBridgeZone
    let configurationProtection: AgentBridgeDiscoveryConfigurationProtection
    let nativeGrants: AgentBridgeDiscoveryNativeGrants
    let entitlement: AgentBridgeDiscoveryEntitlement
    let foregroundAvailable: Bool
    let protectedDataAvailable: Bool
}

extension HealthKitNativePlanningMetadata {
    /// Other values are already-observed native readiness, not wire inputs. This adapter cannot
    /// read quota/settings/credentials. HealthKit flow evidence is never per-type read-grant proof.
    nonisolated func planningFacts(sourceCalendarTimezone: AgentBridgeZone,
        configurationProtection: AgentBridgeDiscoveryConfigurationProtection,
        entitlement: AgentBridgeDiscoveryEntitlement, foregroundAvailable: Bool,
        protectedDataAvailable: Bool) -> AgentBridgeNativePlanningFacts {
        .init(availableNativeMetricIDs: availableNativeMetricIDs, sourceCalendarTimezone: sourceCalendarTimezone,
              configurationProtection: configurationProtection,
              nativeGrants: providerAvailable && authorizationFlowSatisfied ? .satisfied : .required,
              entitlement: entitlement, foregroundAvailable: foregroundAvailable,
              protectedDataAvailable: protectedDataAvailable)
    }
}

/// Selects actual native output configuration without active/default-profile or live-setting
/// fallback. Metadata publication and installed transport/approval wiring remain separate owners.
@MainActor
final class AgentBridgeNativeConfigurationReader: AgentBridgeExportPlanningConfigurationReading {
    private let defaults: UserDefaults
    private let profiles: ExportProfileStore
    private let nativeState: () throws -> AgentBridgeNativePlanningFacts

    init(defaults: UserDefaults, profiles: ExportProfileStore,
         nativeState: @escaping () throws -> AgentBridgeNativePlanningFacts) {
        self.defaults = defaults
        self.profiles = profiles
        self.nativeState = nativeState
    }

    func readConfiguration(for peer: AgentBridgeExportAuthenticatedPeer, policy: AgentBridgeSettingsPolicy?,
                           catalogPublication: AgentBridgeNativeCatalogPublication?) throws -> AgentBridgeExportPlanningConfiguration {
        try peer.requireCurrent()
        guard let publication = catalogPublication else { throw AgentBridgeValidationError.bindingChanged }
        try publication.validate()
        let state = try nativeState()
        guard publication.sourceInstallationID == peer.peer.sourceInstallationID,
              publication.factsSHA256 == (try state.fingerprint(sourceInstallationID: peer.peer.sourceInstallationID)) else {
            throw AgentBridgeValidationError.bindingChanged
        }
        let catalog = try AgentBridgeRequestSettingsCatalog(
            registry: HealthMdCoreRegistryAdapter.appleSnapshot(),
            availableNativeMetricIDs: state.availableNativeMetricIDs, revision: publication.revision)
        var saved: AgentBridgeRequestSettingsSnapshot?
        var selectedProfiles: [AgentBridgeRequestSettingsProfile] = []
        switch policy {
        case .savedDeviceSettings(let expected):
            guard let snapshot = VaultManager.readSavedExportConfiguration(defaults: defaults, expectedRevision: expected) else {
                throw AgentBridgeValidationError.bindingChanged
            }
            saved = .init(revision: snapshot.revision, settings: snapshot.settings)
        case .profile(let id, let expected):
            guard let uuid = UUID(uuidString: id.rawValue),
                  let snapshot = profiles.readConfigurationProfile(id: uuid, expectedRevision: expected) else {
                throw AgentBridgeValidationError.bindingChanged
            }
            selectedProfiles = [.init(profileID: id, snapshot: .init(revision: snapshot.revision, settings: snapshot.settings),
                                      executionBlocked: snapshot.executionBlocked)]
        default: break // Discovery and explicit policy never load saved settings or profiles.
        }
        let currentState = try nativeState()
        try peer.requireCurrent()
        guard currentState == state else { throw AgentBridgeValidationError.bindingChanged }
        return .init(inputs: .init(catalog: catalog, savedDevice: saved, profiles: selectedProfiles),
                     deviceSettingsObjectID: peer.peer.sourceInstallationID, sourceCalendarTimezone: state.sourceCalendarTimezone,
                     configurationProtection: state.configurationProtection, nativeGrants: state.nativeGrants,
                     entitlement: state.entitlement, foregroundAvailable: state.foregroundAvailable,
                     protectedDataAvailable: state.protectedDataAvailable)
    }
}


/// One accepted native owner holds this session across discovery/plan/review calls. The peer and
/// service never escape or come from request JSON. Pending catalog events fence both admission
/// and return; pairing alone still cannot create a grant, decision, capture or wire capability.
@MainActor
final class AgentBridgeNativePlanningSession {
    private let peer: AgentBridgeExportAuthenticatedPeer
    private let lifecycle: AgentBridgeNativeCatalogLifecycle
    private let service: AgentBridgeExportPlanningService
    private let store: AgentBridgeExportAuthorityStore
    private let responseChannel: DirectSecureChannel?
    private let responseNegotiation: AgentBridgeNegotiation?
    private var wireAbandoned = false

    /// The issuer transaction and lifecycle must agree on the exact signed publication, including
    /// revision. Equal facts alone cannot identify an event that returned to the same state.
    private struct OwnerBoundConfiguration: AgentBridgeExportPlanningConfigurationReading {
        let peer: AgentBridgeExportAuthenticatedPeer
        let lifecycle: AgentBridgeNativeCatalogLifecycle
        let base: any AgentBridgeExportPlanningConfigurationReading

        func readConfiguration(for caller: AgentBridgeExportAuthenticatedPeer, policy: AgentBridgeSettingsPolicy?,
                               catalogPublication: AgentBridgeNativeCatalogPublication?) throws -> AgentBridgeExportPlanningConfiguration {
            try requirePublication(catalogPublication)
            let result = try base.readConfiguration(for: peer, policy: policy, catalogPublication: catalogPublication)
            try requirePublication(catalogPublication)
            return result
        }

        private func requirePublication(_ publication: AgentBridgeNativeCatalogPublication?) throws {
            try peer.requireCurrent()
            guard let publication, publication == (try lifecycle.currentPublication()) else {
                throw AgentBridgeValidationError.bindingChanged
            }
        }
    }

    init(peer: AgentBridgeExportAuthenticatedPeer, lifecycle: AgentBridgeNativeCatalogLifecycle,
         store: AgentBridgeExportAuthorityStore, configuration: any AgentBridgeExportPlanningConfigurationReading,
         responseChannel: DirectSecureChannel? = nil,
         responseNegotiation: AgentBridgeNegotiation? = nil,
         clock: any AgentBridgeExportClock = AgentBridgeExportSystemClock(),
         newPlanID: @escaping () throws -> AgentBridgeUUID = { try AgentBridgeUUID(UUID().uuidString.lowercased()) }) throws {
        try peer.requireCurrent()
        let publication = try lifecycle.currentPublication()
        self.peer = peer; self.lifecycle = lifecycle; self.store = store; self.responseChannel = responseChannel; self.responseNegotiation = responseNegotiation
        service = AgentBridgeExportPlanningService(store: store,
            configuration: OwnerBoundConfiguration(peer: peer, lifecycle: lifecycle, base: configuration),
            clock: clock, newPlanID: newPlanID)
        guard try requireCurrent() == publication else { throw AgentBridgeValidationError.bindingChanged }
    }

    @discardableResult
    func requireCurrent() throws -> AgentBridgeNativeCatalogPublication {
        guard !wireAbandoned else { throw AgentBridgeValidationError.permissionRequired }
        try peer.requireCurrent()
        return try lifecycle.currentPublication()
    }

    func handle(_ bytes: Data) throws -> Data {
        let publication = try requireCurrent()
        let result = try service.handle(bytes, authenticatedPeer: peer)
        guard try requireCurrent() == publication else { throw AgentBridgeValidationError.bindingChanged }
        return result
    }

    /// Native response composition only; does not advertise or install the extension route.
    /// The owner supplies its channel ONCE at construction, never from a request/call argument.
    /// Keep the publication admitted before planning across every bounded native write and return.
    func handleAndSend(_ bytes: Data) async throws {
        guard let negotiation = responseNegotiation, negotiation.baseVersion == 1, negotiation.agentBridgeV4, let responseChannel else {
            throw AgentBridgeValidationError.unsupportedCapability
        }
        do {
            try Task.checkCancellation()
            let publication = try requireCurrent()
            let response = try negotiation.decode(handle(bytes))
            try await responseChannel.sendAgentBridge(response, negotiation: negotiation) { [self] in
                try Task.checkCancellation()
                try await MainActor.run {
                    guard try requireCurrent() == publication else { throw AgentBridgeValidationError.bindingChanged }
                    try service.requireCurrentForTransmission(response, peer: peer)
                    // Local lifecycle check only after the full issuer fence: no new SDK callback.
                    guard try lifecycle.currentPublication() == publication else { throw AgentBridgeValidationError.bindingChanged }
                }
                try Task.checkCancellation()
            }
            try Task.checkCancellation()
            guard try requireCurrent() == publication else { throw AgentBridgeValidationError.bindingChanged }
            try service.requireCurrentForTransmission(response, peer: peer)
            guard try lifecycle.currentPublication() == publication else { throw AgentBridgeValidationError.bindingChanged }
            try Task.checkCancellation()
        } catch {
            wireAbandoned = true
            responseChannel.cancel()
            throw error
        }
    }

    /// One native receive iteration. Bridge requests use this SAME original planner; deployed
    /// base messages and binary frames are returned intact to the existing native controller.
    /// The controller must not run another channel reader concurrently. This adds no advertisement.
    func receiveAndHandleNext() async throws -> AgentBridgeSecurePayload? {
        guard let negotiation = responseNegotiation, negotiation.baseVersion == 1, negotiation.agentBridgeV4,
              let responseChannel else { throw AgentBridgeValidationError.unsupportedCapability }
        do {
            let received = try await responseChannel.receiveAllowingAgentBridge(negotiation: negotiation) { [self] in
                try Task.checkCancellation()
                try await MainActor.run { _ = try requireCurrent() }
                try Task.checkCancellation()
            }
            if case .agent(let request) = received {
                try await handleAndSend(negotiation.encode(request))
                return nil
            }
            _ = try requireCurrent()
            try Task.checkCancellation()
            return received
        } catch {
            wireAbandoned = true
            responseChannel.cancel()
            throw error
        }
    }

    /// Native presentation only: signed issuer records for the original peer, excluding decisions
    /// already made. Stale/expired/revoked requests are omitted; storage and owner failures reject.
    func nativePlansAwaitingReview() throws -> [AgentBridgePlan] {
        let publication = try requireCurrent()
        let state = try store.snapshot()
        guard state.nativeCatalog == publication else { throw AgentBridgeValidationError.bindingChanged }
        let decided = Set(state.decisions.map(\.planID))
        var result: [AgentBridgePlan] = []
        for record in state.plans {
            let plan = try record.plan()
            guard plan.intent.peer == peer.peer, !decided.contains(plan.planId) else { continue }
            if try service.nativePlanIsReviewable(planID: plan.planId, authenticatedPeer: peer) {
                result.append(try service.reviewNativePlan(planID: plan.planId, authenticatedPeer: peer))
            }
        }
        guard try requireCurrent() == publication else { throw AgentBridgeValidationError.bindingChanged }
        return result.sorted { $0.issuedAt.rawValue == $1.issuedAt.rawValue ? $0.planId.rawValue < $1.planId.rawValue : $0.issuedAt.rawValue > $1.issuedAt.rawValue }
    }

    /// Own the whole native capture operation, never an escaping permission token. Only the
    /// original negotiated session may accept/claim once; a retry must inspect/resume its job.
    func withCaptureContext<T>(_ request: AgentBridgeExecute,
                               operation: (AgentBridgeNativeCaptureContext) async throws -> T) async throws -> T {
        guard let negotiation = responseNegotiation, negotiation.baseVersion == 1,
              negotiation.agentBridgeV4, responseChannel != nil else { throw AgentBridgeValidationError.unsupportedCapability }
        let cancellation = AgentBridgeCaptureCancellation()
        return try await withTaskCancellationHandler {
            do {
                try cancellation.requireActive(); try Task.checkCancellation()
                let publication = try requireCurrent()
                let accepted = try service.acceptExecution(request, authenticatedPeer: peer)
                try cancellation.requireActive(); try Task.checkCancellation()
                guard accepted.newlyAccepted else { throw AgentBridgeValidationError.busy }
                let reservation = try service.claimCapture(request, authenticatedPeer: peer)
                try cancellation.requireActive(); try Task.checkCancellation()
                guard !wireAbandoned, try lifecycle.currentPublication() == publication else { throw AgentBridgeValidationError.bindingChanged }
                let context = AgentBridgeNativeCaptureContext { [self] in
                    try cancellation.requireActive(); try Task.checkCancellation()
                    let result = try captureReadConfiguration(reservation)
                    try cancellation.requireActive(); try Task.checkCancellation()
                    return result
                }
                defer { context.close() }
                let result = try await operation(context)
                try cancellation.requireActive(); try Task.checkCancellation()
                _ = try context.configurationForRead() // Full native fence after suspended capture too.
                return result
            } catch {
                try cancellation.requireActive(); try Task.checkCancellation()
                throw error
            }
        } onCancel: { cancellation.cancel() }
    }

    /// Native producer pre-read boundary only; does not reserve again or install an SDK route.
    func captureReadConfiguration(_ reservation: AgentBridgeExportCaptureReservation) throws -> AgentBridgeRequestSettingsResolution {
        try Task.checkCancellation()
        let publication = try requireCurrent()
        let result = try service.captureReadConfiguration(reservation, authenticatedPeer: peer)
        // Local-only tail after the service's final live expiry check; no delaying SDK callback.
        guard !wireAbandoned else { throw AgentBridgeValidationError.permissionRequired }
        guard try lifecycle.currentPublication() == publication else { throw AgentBridgeValidationError.bindingChanged }
        try Task.checkCancellation()
        return result
    }

    func reviewNativePlan(planID: AgentBridgeUUID) throws -> AgentBridgePlan {
        let publication = try requireCurrent()
        let result = try service.reviewNativePlan(planID: planID, authenticatedPeer: peer)
        guard try requireCurrent() == publication else { throw AgentBridgeValidationError.bindingChanged }
        return result
    }

    func storeNativeDecision(planID: AgentBridgeUUID, binding: AgentBridgeBinding, approvalID: AgentBridgeUUID,
                             authorization: any AgentBridgeExportNativeAuthorizing) throws {
        let publication = try requireCurrent()
        try service.storeNativeDecision(planID: planID, binding: binding, approvalID: approvalID,
                                        authenticatedPeer: peer, authorization: authorization)
        guard try requireCurrent() == publication else { throw AgentBridgeValidationError.bindingChanged }
    }
}


/// Native-only, non-Codable operation lease. Begin once; check before/after actual SDK reads.
/// Escaping the callback does not retain usable authority or the original owner callback.
@MainActor
final class AgentBridgeNativeCaptureContext {
    private var started = false
    private var closed = false
    private var claimedDays: Set<String> = []
    private var read: (() throws -> AgentBridgeRequestSettingsResolution)?
    fileprivate init(read: @escaping () throws -> AgentBridgeRequestSettingsResolution) { self.read = read }
    func begin() throws -> AgentBridgeRequestSettingsResolution {
        guard !started, !closed else { close(); throw AgentBridgeValidationError.busy }
        started = true
        return try configurationForRead()
    }
    /// One attempt per approved day inside this single capture operation. This is not a
    /// durable frontier; missing spool after interruption still requires explicit recovery.
    func claimDay(_ day: AgentBridgeDate) throws -> AgentBridgeRequestSettingsResolution {
        let resolution = try configurationForRead()
        guard resolution.requestedDays.contains(day) else { close(); throw AgentBridgeValidationError.invalidRequest }
        guard claimedDays.insert(day.rawValue).inserted else { close(); throw AgentBridgeValidationError.busy }
        return resolution
    }
    /// Monotonic denial only: a caught SDK/result failure cannot revive the operation.
    func invalidate() { close() }
    func configurationForRead() throws -> AgentBridgeRequestSettingsResolution {
        guard started, !closed, let read else { throw AgentBridgeValidationError.permissionRequired }
        do {
            let result = try read()
            guard !closed else { throw AgentBridgeValidationError.permissionRequired }
            return result
        } catch { close(); throw error }
    }
    fileprivate func close() { closed = true; read = nil; claimedDays.removeAll() }
}
nonisolated private final class AgentBridgeCaptureCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var cancelled = false
    func cancel() { lock.lock(); cancelled = true; lock.unlock() }
    func requireActive() throws {
        lock.lock(); let value = cancelled; lock.unlock()
        if value { throw CancellationError() }
    }
}
