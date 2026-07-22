#if os(macOS)
import Combine
import Foundation
import Security

nonisolated enum HealthContextProfileAgentPolicyMappingError: String, Error, Equatable, LocalizedError, Sendable {
    case invalidProfile = "invalid_profile"
    case registeredAgentNotAllowed = "registered_agent_not_allowed"
    case unsupportedDataSourceRestriction = "unsupported_data_source_restriction"
    case unsupportedDatePolicy = "unsupported_date_policy"
    case unsupportedDestinationBinding = "unsupported_destination_binding"
    case unsupportedSurface = "unsupported_surface"
    case noMappedOperations = "no_mapped_operations"

    var errorDescription: String? { rawValue }
}

/// Converts a pinned canonical profile into the access-core policy used by a
/// registered local client. Every conversion is exact. A canonical restriction
/// that the access model cannot express is rejected rather than widened.
nonisolated enum HealthContextProfileAgentPolicyMapper {
    static func effectivePolicy(
        profile: HealthContextProfile,
        reference: HealthContextProfileReference
    ) throws -> HealthContextProfileEffectivePolicy {
        do {
            try profile.validate()
        } catch {
            throw HealthContextProfileAgentPolicyMappingError.invalidProfile
        }

        let canonicalReference: HealthContextProfileReference
        do {
            canonicalReference = try profile.reference()
        } catch {
            throw HealthContextProfileAgentPolicyMappingError.invalidProfile
        }
        guard canonicalReference == reference else {
            throw HealthContextProfileAgentPolicyMappingError.invalidProfile
        }
        guard profile.allowedCallers.contains(.registeredAgent) else {
            throw HealthContextProfileAgentPolicyMappingError.registeredAgentNotAllowed
        }

        // Provider/source scope remains part of the exact profile digest and is
        // enforced by profile resolution plus query/acquisition services. A
        // grant cannot outlive or widen that pinned policy.

        let dateScope: AgentDateScope
        switch profile.datePolicy {
        case .allHistory:
            dateScope = .allHistory
        case .explicit(let range):
            dateScope = .exact(start: range.start, end: range.end)
        case .callerProvided, .relative:
            // The exact per-execution bound is resolved by the profile resolver.
            // The grant stores an outer ceiling and cannot bypass the pinned digest.
            dateScope = .allHistory
        }

        let metricScope: AgentMetricScope
        switch profile.metricScope {
        case .allAvailable:
            metricScope = .allAvailable
        case .selected(let metricIDs):
            metricScope = .metricIDs(Set(metricIDs))
        }

        let detailLevels: AgentDetailScope
        switch profile.detailLevel {
        case .summary:
            detailLevels = .detailLevels([.summary, .aggregates])
        case .lossless:
            // Lossless is a ceiling: callers may request a less detailed view,
            // individual records, or the complete canonical source records.
            detailLevels = .allDetailLevels
        }

        var mappedOperations = Set<AgentAccessOperation>()
        for surface in profile.allowedSurfaces {
            mappedOperations.formUnion(try operations(for: surface))
        }
        guard !mappedOperations.isEmpty else {
            throw HealthContextProfileAgentPolicyMappingError.noMappedOperations
        }

        let destinationClasses: AgentDestinationScope
        switch profile.destinationBinding {
        case .any:
            // `any` is explicitly dynamic across destinations. Restricting it to
            // destinations used by today's UI would silently narrow the profile.
            destinationClasses = .allDestinationClasses
        case .exact:
            // A stable ID cannot be reduced to a destination class. The profile
            // resolver performs the exact ID check at execution; this remains
            // only the outer grant ceiling.
            destinationClasses = .allDestinationClasses
        }

        return HealthContextProfileEffectivePolicy(
            reference: canonicalReference,
            operations: mappedOperations == Set(AgentAccessOperation.allCases)
                ? .allOperations
                : .operations(mappedOperations),
            dateScope: dateScope,
            metricScope: metricScope,
            detailLevels: detailLevels,
            destinationClasses: destinationClasses
        )
    }

    private static func operations(
        for surface: HealthContextSurface
    ) throws -> Set<AgentAccessOperation> {
        switch surface {
        case .commandLine, .localControlAPI, .mcpStdio, .macOSApp:
            // These registered-client surfaces all use the same access service.
            // The requested operation remains independently checked by the grant.
            return Set(AgentAccessOperation.allCases)
        case .iOSApp, .shortcuts:
            // These surfaces cannot be authenticated as a registered local Mac
            // client by this runtime and must not be silently treated as one.
            throw HealthContextProfileAgentPolicyMappingError.unsupportedSurface
        default:
            throw HealthContextProfileAgentPolicyMappingError.unsupportedSurface
        }
    }
}

nonisolated struct AgentCredentialReveal: Equatable, Sendable {
    let registrationID: UUID
    let credential: String
    let isRotation: Bool
}

@MainActor
final class MacAgentAccessManager: ObservableObject {
    typealias CredentialGenerator = (_ byteCount: Int) throws -> Data

    @Published private(set) var registrations: [AgentClientRegistration] = []
    @Published private(set) var grants: [AgentAccessGrant] = []
    @Published private(set) var activity: [AgentActivityRecord] = []
    @Published private(set) var credentialReveal: AgentCredentialReveal?
    @Published private(set) var isLoaded = false
    @Published private(set) var isWorking = false
    @Published private(set) var lastError: String?

    private let accessManager: AgentAccessManager
    private let credentialGenerator: CredentialGenerator

    convenience init() {
        self.init(
            accessManager: AgentAccessManager(
                credentialStore: SystemAgentCredentialStore()
            )
        )
    }

    init(
        accessManager: AgentAccessManager,
        credentialGenerator: @escaping CredentialGenerator = MacAgentAccessManager.secureRandomBytes
    ) {
        self.accessManager = accessManager
        self.credentialGenerator = credentialGenerator
    }

    func load() async {
        isWorking = true
        async let loadedRegistrations = accessManager.registrations()
        async let loadedGrants = accessManager.grants()
        async let loadedActivity = accessManager.activityHistory()
        async let loadedAccessStatus = accessManager.accessStoreStatus()
        async let loadedActivityStatus = accessManager.activityStoreStatus()
        registrations = await loadedRegistrations
        grants = await loadedGrants
        activity = await loadedActivity
        let accessStatus = await loadedAccessStatus
        let activityStatus = await loadedActivityStatus
        lastError = Self.storeError(accessStatus: accessStatus, activityStatus: activityStatus)
        isLoaded = true
        isWorking = false
    }

    @discardableResult
    func registerLocalAgent(displayName: String) async throws -> AgentClientRegistration {
        let name = displayName.trimmingCharacters(in: .whitespacesAndNewlines)
        let secret = try issueCredentialSecret()
        return try await performMutation {
            let registration = try await accessManager.registerClient(
                displayName: name,
                kind: .localAgent
            )
            do {
                try await accessManager.storeCredential(Data(secret.utf8), for: registration.id)
            } catch {
                _ = try? await accessManager.revokeRegistration(registration.id)
                throw error
            }
            credentialReveal = AgentCredentialReveal(
                registrationID: registration.id,
                credential: Self.externalCredential(
                    registrationID: registration.id,
                    secret: secret
                ),
                isRotation: false
            )
            return registration
        }
    }

    func rotateCredential(for registrationID: UUID) async throws {
        guard registrations.contains(where: {
            $0.id == registrationID && $0.state == .active
        }) else {
            throw AgentAccessManagerError(.invalidStateTransition)
        }
        let secret = try issueCredentialSecret()
        _ = try await performMutation {
            try await accessManager.storeCredential(Data(secret.utf8), for: registrationID)
            credentialReveal = AgentCredentialReveal(
                registrationID: registrationID,
                credential: Self.externalCredential(
                    registrationID: registrationID,
                    secret: secret
                ),
                isRotation: true
            )
        }
    }

    /// Returns the currently revealed credential exactly once for clipboard use
    /// and immediately removes it from observable state.
    func takeCredentialForCopy() -> String? {
        guard let reveal = credentialReveal else { return nil }
        credentialReveal = nil
        return reveal.credential
    }

    func dismissCredentialReveal() {
        credentialReveal = nil
    }

    func revokeRegistration(_ registrationID: UUID) async throws {
        _ = try await performMutation {
            _ = try await accessManager.revokeRegistration(registrationID)
            if credentialReveal?.registrationID == registrationID {
                credentialReveal = nil
            }
        }
    }

    @discardableResult
    func createGrant(
        for registrationID: UUID,
        profile: HealthContextProfile
    ) async throws -> AgentAccessGrant {
        let reference = try profile.reference()
        let policy = try HealthContextProfileAgentPolicyMapper.effectivePolicy(
            profile: profile,
            reference: reference
        )
        let grant = AgentAccessGrant(
            clientRegistrationID: registrationID,
            profileReference: policy.reference,
            operations: policy.operations,
            dateScope: policy.dateScope,
            metricScope: policy.metricScope,
            detailLevels: policy.detailLevels,
            destinationClasses: policy.destinationClasses,
            // Resource safety is enforced per page/chunk by query and transfer
            // contracts. This grant introduces no total metric/date/record cap.
            resourceControls: nil,
            expiresAt: profile.expiresAt
        )
        return try await performMutation {
            try await accessManager.saveGrant(grant)
        }
    }

    func requiresBroadScopeConfirmation(_ grant: AgentAccessGrant) -> Bool {
        if grant.dateScope == .allHistory || grant.metricScope == .allAvailable {
            return true
        }
        if grant.detailLevels.contains(.losslessRecords) {
            return true
        }
        if case .allOperations = grant.operations { return true }
        if case .allDestinationClasses = grant.destinationClasses { return true }
        return false
    }

    func confirmGrant(_ grantID: UUID, broadScopeAcknowledged: Bool) async throws {
        guard let grant = grants.first(where: { $0.id == grantID }) else {
            throw AgentAccessManagerError(.grantNotFound)
        }
        guard !requiresBroadScopeConfirmation(grant) || broadScopeAcknowledged else {
            throw AgentAccessManagerError(.invalidStateTransition)
        }
        _ = try await performMutation {
            _ = try await accessManager.confirmGrant(grantID)
        }
    }

    func pauseGrant(_ grantID: UUID) async throws {
        _ = try await performMutation { _ = try await accessManager.pauseGrant(grantID) }
    }

    func resumeGrant(_ grantID: UUID) async throws {
        _ = try await performMutation { _ = try await accessManager.resumeGrant(grantID) }
    }

    func revokeGrant(_ grantID: UUID) async throws {
        _ = try await performMutation { _ = try await accessManager.revokeGrant(grantID) }
    }

    func clearActivityHistory() async throws {
        _ = try await performMutation { try await accessManager.clearActivityHistory() }
    }

    func grants(for registrationID: UUID) -> [AgentAccessGrant] {
        grants.filter { $0.clientRegistrationID == registrationID }
    }

    func registrationName(for identity: AgentClientIdentity) -> String {
        guard identity.kind == .registeredClient,
              let id = identity.registrationID,
              let registration = registrations.first(where: { $0.id == id }) else {
            return "Unattributed local process"
        }
        return registration.displayName
    }

    /// Authenticates one bearer credential without scanning other registrations.
    /// The UUID prefix selects the Keychain account; secret comparison is constant-time.
    func authenticateExternalCredential(
        _ externalCredential: String
    ) async -> AgentClientRegistration? {
        guard let parsed = Self.parseExternalCredential(externalCredential),
              let registration = await accessManager.registration(id: parsed.registrationID),
              registration.state == .active,
              let saved = try? await accessManager.credential(for: parsed.registrationID),
              Self.constantTimeEqual(saved, Data(parsed.secret.utf8)) else {
            return nil
        }
        return registration
    }

    func authorizationDecision(
        _ context: AgentAuthorizationContext,
        recordingActivity: Bool = true
    ) async throws -> AgentAuthorizationDecision {
        if recordingActivity {
            let decision = try await accessManager.authorize(context)
            activity = await accessManager.activityHistory()
            return decision
        }
        return await accessManager.checkAuthorization(context)
    }

    @discardableResult
    func recordActivity(
        for request: AgentAccessRequest,
        grantID: UUID?,
        resultRecordCount: Int,
        resultByteCount: Int,
        outcome: AgentActivityOutcome,
        reasonCode: AgentAccessReasonCode = .allowed
    ) async throws -> AgentActivityRecord {
        let record = try await accessManager.recordActivity(
            for: request,
            grantID: grantID,
            resultRecordCount: resultRecordCount,
            resultByteCount: resultByteCount,
            outcome: outcome,
            reasonCode: reasonCode
        )
        activity = await accessManager.activityHistory()
        return record
    }

    nonisolated private static func constantTimeEqual(_ lhs: Data, _ rhs: Data) -> Bool {
        guard lhs.count == rhs.count else { return false }
        var difference: UInt8 = 0
        for index in lhs.indices { difference |= lhs[index] ^ rhs[index] }
        return difference == 0
    }

    private func issueCredentialSecret() throws -> String {
        let bytes = try credentialGenerator(32)
        guard bytes.count == 32 else {
            throw AgentAccessManagerError(.credentialStorageFailed)
        }
        return "healthmd_agent_" + bytes.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }

    nonisolated static func externalCredential(
        registrationID: UUID,
        secret: String
    ) -> String {
        "\(registrationID.uuidString.lowercased()).\(secret)"
    }

    nonisolated static func parseExternalCredential(
        _ credential: String
    ) -> (registrationID: UUID, secret: String)? {
        let components = credential.split(separator: ".", omittingEmptySubsequences: false)
        guard components.count == 2,
              let registrationID = UUID(uuidString: String(components[0])),
              components[0] == Substring(registrationID.uuidString.lowercased()),
              components[1].hasPrefix("healthmd_agent_"),
              components[1].count > "healthmd_agent_".count else { return nil }
        return (registrationID, String(components[1]))
    }

    private func performMutation<T>(_ mutation: () async throws -> T) async throws -> T {
        isWorking = true
        defer { isWorking = false }
        do {
            let result = try await mutation()
            registrations = await accessManager.registrations()
            grants = await accessManager.grants()
            activity = await accessManager.activityHistory()
            lastError = nil
            return result
        } catch {
            lastError = Self.safeErrorDescription(error)
            throw error
        }
    }

    nonisolated private static func secureRandomBytes(count: Int) throws -> Data {
        var data = Data(count: count)
        let status = data.withUnsafeMutableBytes { buffer in
            SecRandomCopyBytes(kSecRandomDefault, count, buffer.baseAddress!)
        }
        guard status == errSecSuccess else {
            throw AgentAccessManagerError(.credentialStorageFailed)
        }
        return data
    }

    nonisolated private static func safeErrorDescription(_ error: Error) -> String {
        if let managerError = error as? AgentAccessManagerError {
            return managerError.code.rawValue
        }
        if let mappingError = error as? HealthContextProfileAgentPolicyMappingError {
            return mappingError.rawValue
        }
        return "agent_access_operation_failed"
    }

    nonisolated private static func storeError(
        accessStatus: AgentAccessStoreStatus,
        activityStatus: AgentAccessStoreStatus
    ) -> String? {
        switch accessStatus {
        case .ready: break
        case .corrupt: return "agent_access_store_corrupt"
        case .unsupportedVersion(let version): return "agent_access_store_unsupported_v\(version)"
        }
        switch activityStatus {
        case .ready: return nil
        case .corrupt: return "agent_activity_store_corrupt"
        case .unsupportedVersion(let version): return "agent_activity_store_unsupported_v\(version)"
        }
    }
}
#endif
