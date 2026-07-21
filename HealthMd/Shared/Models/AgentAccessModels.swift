import Foundation

// MARK: - Registration and identity

/// The kind of process the user registered. This is not an authentication result.
nonisolated enum AgentClientKind: String, Codable, CaseIterable, Sendable {
    case localAgent = "local_agent"
    case remoteAgent = "remote_agent"
    case companionApplication = "companion_application"
}

nonisolated enum AgentClientRegistrationState: String, Codable, Sendable {
    case active
    case revoked
}

/// User-visible registration metadata. Authentication credentials are deliberately absent.
nonisolated struct AgentClientRegistration: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let displayName: String
    let kind: AgentClientKind
    let createdAt: Date
    var state: AgentClientRegistrationState
    var revokedAt: Date?

    init(
        id: UUID = UUID(),
        displayName: String,
        kind: AgentClientKind,
        createdAt: Date = Date(),
        state: AgentClientRegistrationState = .active,
        revokedAt: Date? = nil
    ) {
        self.id = id
        self.displayName = displayName
        self.kind = kind
        self.createdAt = createdAt
        self.state = state
        self.revokedAt = revokedAt
    }
}

/// The identity attribution available to the authorization layer.
/// The existing loopback CLI must use `legacyUnattributedLocalProcess`; it is not authenticated.
nonisolated struct AgentClientIdentity: Codable, Equatable, Sendable {
    enum Kind: String, Codable, Sendable {
        case registeredClient = "registered_client"
        case legacyUnattributedLocalProcess = "legacy_unattributed_local_process"
    }

    let kind: Kind
    let registrationID: UUID?

    static func registered(_ registrationID: UUID) -> Self {
        Self(kind: .registeredClient, registrationID: registrationID)
    }

    static let legacyUnattributedLocalProcess = Self(
        kind: .legacyUnattributedLocalProcess,
        registrationID: nil
    )
}

// MARK: - Health Context Profile and HealthKit boundaries

/// A caller-supplied snapshot of the pinned profile's current effective policy.
/// A profile is neither a client grant nor HealthKit authorization.
nonisolated struct HealthContextProfileEffectivePolicy: Codable, Equatable, Sendable {
    let reference: HealthContextProfileReference
    let operations: AgentOperationScope
    let dateScope: AgentDateScope
    let metricScope: AgentMetricScope
    let detailLevels: AgentDetailScope
    let destinationClasses: AgentDestinationScope

    init(
        reference: HealthContextProfileReference,
        operations: AgentOperationScope,
        dateScope: AgentDateScope,
        metricScope: AgentMetricScope,
        detailLevels: AgentDetailScope,
        destinationClasses: AgentDestinationScope
    ) {
        self.reference = reference
        self.operations = operations
        self.dateScope = dateScope
        self.metricScope = metricScope
        self.detailLevels = detailLevels
        self.destinationClasses = destinationClasses
    }
}

nonisolated enum AgentHealthKitAuthorizationState: String, Codable, Sendable {
    /// Cached Mac context is authorized by the pinned profile/grant and does not
    /// imply that the Mac can inspect HealthKit authorization.
    case notRequiredForCachedData = "not_required_for_cached_data"
    case authorized
    case notDetermined = "not_determined"
    case denied
}

/// A separate, short-lived view of OS-level HealthKit read authorization.
nonisolated struct AgentHealthKitAuthorizationSnapshot: Codable, Equatable, Sendable {
    let state: AgentHealthKitAuthorizationState
    let readableMetrics: AgentMetricScope
    let capturedAt: Date

    init(
        state: AgentHealthKitAuthorizationState,
        readableMetrics: AgentMetricScope,
        capturedAt: Date = Date()
    ) {
        self.state = state
        self.readableMetrics = readableMetrics
        self.capturedAt = capturedAt
    }
}

// MARK: - Access scopes

nonisolated enum AgentAccessOperation: String, Codable, CaseIterable, Hashable, Sendable {
    case readHealthData = "read_health_data"
    case exportHealthData = "export_health_data"
    case streamHealthData = "stream_health_data"
    case listAvailableMetrics = "list_available_metrics"
}

nonisolated enum AgentDetailLevel: String, Codable, CaseIterable, Hashable, Sendable {
    case summary
    case aggregates
    case individualRecords = "individual_records"
    case losslessRecords = "lossless_records"
}

/// A destination classification only. An API Endpoint URL is configuration and is never audited here.
nonisolated enum AgentDestinationClass: String, Codable, CaseIterable, Hashable, Sendable {
    case inProcessResponse = "in_process_response"
    case loopbackResponse = "loopback_response"
    case localFileExport = "local_file_export"
    case connectedDevice = "connected_device"
    case apiEndpoint = "api_endpoint"
}

nonisolated struct AgentExactDateRange: Codable, Equatable, Sendable {
    let start: Date
    let end: Date

    init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

/// Exact requested dates or an explicit all-history marker. No implicit lookback cap exists.
nonisolated enum AgentDateScope: Equatable, Sendable {
    case allHistory
    case exactRange(AgentExactDateRange)

    static func exact(start: Date, end: Date) -> Self {
        .exactRange(AgentExactDateRange(start: start, end: end))
    }

    func contains(_ requested: Self) -> Bool {
        switch (self, requested) {
        case (.allHistory, _):
            return true
        case (.exactRange, .allHistory):
            return false
        case let (.exactRange(allowed), .exactRange(requested)):
            return requested.start >= allowed.start && requested.end <= allowed.end
        }
    }
}

extension AgentDateScope: Codable {
    private enum CodingKeys: String, CodingKey { case mode, start, end }
    private enum Mode: String, Codable { case allHistory = "all_history", exactRange = "exact_range" }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .allHistory:
            self = .allHistory
        case .exactRange:
            self = .exactRange(AgentExactDateRange(
                start: try container.decode(Date.self, forKey: .start),
                end: try container.decode(Date.self, forKey: .end)
            ))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allHistory:
            try container.encode(Mode.allHistory, forKey: .mode)
        case let .exactRange(range):
            try container.encode(Mode.exactRange, forKey: .mode)
            try container.encode(range.start, forKey: .start)
            try container.encode(range.end, forKey: .end)
        }
    }
}

/// Exact Health.md metric identifiers or an explicit all-available marker.
nonisolated enum AgentMetricScope: Equatable, Sendable {
    case allAvailable
    case metricIDs(Set<String>)

    func contains(_ requested: Self) -> Bool {
        switch (self, requested) {
        case (.allAvailable, _): return true
        case (.metricIDs, .allAvailable): return false
        case let (.metricIDs(allowed), .metricIDs(requested)):
            return requested.isSubset(of: allowed)
        }
    }
}

extension AgentMetricScope: Codable {
    private enum CodingKeys: String, CodingKey { case mode, metricIDs = "metric_ids" }
    private enum Mode: String, Codable { case allAvailable = "all_available", selected }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .allAvailable: self = .allAvailable
        case .selected: self = .metricIDs(Set(try container.decode([String].self, forKey: .metricIDs)))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allAvailable:
            try container.encode(Mode.allAvailable, forKey: .mode)
        case let .metricIDs(ids):
            try container.encode(Mode.selected, forKey: .mode)
            try container.encode(ids.sorted(), forKey: .metricIDs)
        }
    }
}

nonisolated enum AgentOperationScope: Equatable, Sendable {
    case allOperations
    case operations(Set<AgentAccessOperation>)

    func contains(_ operation: AgentAccessOperation) -> Bool {
        switch self {
        case .allOperations: return true
        case let .operations(operations): return operations.contains(operation)
        }
    }
}

extension AgentOperationScope: Codable {
    private enum CodingKeys: String, CodingKey { case mode, operations }
    private enum Mode: String, Codable { case allOperations = "all_operations", selected }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .allOperations: self = .allOperations
        case .selected: self = .operations(Set(try container.decode([AgentAccessOperation].self, forKey: .operations)))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allOperations:
            try container.encode(Mode.allOperations, forKey: .mode)
        case let .operations(operations):
            try container.encode(Mode.selected, forKey: .mode)
            try container.encode(operations.sorted { $0.rawValue < $1.rawValue }, forKey: .operations)
        }
    }
}

nonisolated enum AgentDetailScope: Equatable, Sendable {
    case allDetailLevels
    case detailLevels(Set<AgentDetailLevel>)

    func contains(_ detailLevel: AgentDetailLevel) -> Bool {
        switch self {
        case .allDetailLevels: return true
        case let .detailLevels(levels): return levels.contains(detailLevel)
        }
    }
}

extension AgentDetailScope: Codable {
    private enum CodingKeys: String, CodingKey { case mode, detailLevels = "detail_levels" }
    private enum Mode: String, Codable { case allDetailLevels = "all_detail_levels", selected }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .allDetailLevels: self = .allDetailLevels
        case .selected: self = .detailLevels(Set(try container.decode([AgentDetailLevel].self, forKey: .detailLevels)))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allDetailLevels:
            try container.encode(Mode.allDetailLevels, forKey: .mode)
        case let .detailLevels(levels):
            try container.encode(Mode.selected, forKey: .mode)
            try container.encode(levels.sorted { $0.rawValue < $1.rawValue }, forKey: .detailLevels)
        }
    }
}

nonisolated enum AgentDestinationScope: Equatable, Sendable {
    case allDestinationClasses
    case destinationClasses(Set<AgentDestinationClass>)

    func contains(_ destinationClass: AgentDestinationClass) -> Bool {
        switch self {
        case .allDestinationClasses: return true
        case let .destinationClasses(classes): return classes.contains(destinationClass)
        }
    }
}

extension AgentDestinationScope: Codable {
    private enum CodingKeys: String, CodingKey { case mode, destinationClasses = "destination_classes" }
    private enum Mode: String, Codable { case allDestinationClasses = "all_destination_classes", selected }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Mode.self, forKey: .mode) {
        case .allDestinationClasses: self = .allDestinationClasses
        case .selected: self = .destinationClasses(Set(try container.decode([AgentDestinationClass].self, forKey: .destinationClasses)))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allDestinationClasses:
            try container.encode(Mode.allDestinationClasses, forKey: .mode)
        case let .destinationClasses(classes):
            try container.encode(Mode.selected, forKey: .mode)
            try container.encode(classes.sorted { $0.rawValue < $1.rawValue }, forKey: .destinationClasses)
        }
    }
}

/// Per-page/chunk safety only. These values must be paired with continuation semantics;
/// they never limit the total number of authorized records or total authorized history.
nonisolated struct AgentResourceControls: Codable, Equatable, Sendable {
    let maxRecordsPerPage: Int?
    let maxBytesPerPage: Int?
    let maxBytesPerStreamChunk: Int?

    init(
        maxRecordsPerPage: Int? = nil,
        maxBytesPerPage: Int? = nil,
        maxBytesPerStreamChunk: Int? = nil
    ) {
        self.maxRecordsPerPage = maxRecordsPerPage
        self.maxBytesPerPage = maxBytesPerPage
        self.maxBytesPerStreamChunk = maxBytesPerStreamChunk
    }
}

// MARK: - Grant and request

nonisolated enum AgentGrantConfirmationState: String, Codable, Sendable {
    case pending
    case userConfirmed = "user_confirmed"
}

nonisolated enum AgentAccessGrantStatus: String, Codable, Sendable {
    case pendingConfirmation = "pending_confirmation"
    case active
    case paused
    case expired
    case revoked
}

nonisolated struct AgentAccessGrant: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let clientRegistrationID: UUID
    let profileReference: HealthContextProfileReference
    let createdAt: Date
    var confirmationState: AgentGrantConfirmationState
    var confirmedAt: Date?
    let operations: AgentOperationScope
    let dateScope: AgentDateScope
    let metricScope: AgentMetricScope
    let detailLevels: AgentDetailScope
    let destinationClasses: AgentDestinationScope
    let resourceControls: AgentResourceControls?
    var expiresAt: Date?
    var pausedAt: Date?
    var expiredAt: Date?
    var revokedAt: Date?

    init(
        id: UUID = UUID(),
        clientRegistrationID: UUID,
        profileReference: HealthContextProfileReference,
        createdAt: Date = Date(),
        confirmationState: AgentGrantConfirmationState = .pending,
        confirmedAt: Date? = nil,
        operations: AgentOperationScope,
        dateScope: AgentDateScope,
        metricScope: AgentMetricScope,
        detailLevels: AgentDetailScope,
        destinationClasses: AgentDestinationScope,
        resourceControls: AgentResourceControls? = nil,
        expiresAt: Date? = nil,
        pausedAt: Date? = nil,
        expiredAt: Date? = nil,
        revokedAt: Date? = nil
    ) {
        self.id = id
        self.clientRegistrationID = clientRegistrationID
        self.profileReference = profileReference
        self.createdAt = createdAt
        self.confirmationState = confirmationState
        self.confirmedAt = confirmedAt
        self.operations = operations
        self.dateScope = dateScope
        self.metricScope = metricScope
        self.detailLevels = detailLevels
        self.destinationClasses = destinationClasses
        self.resourceControls = resourceControls
        self.expiresAt = expiresAt
        self.pausedAt = pausedAt
        self.expiredAt = expiredAt
        self.revokedAt = revokedAt
    }

    func status(at date: Date) -> AgentAccessGrantStatus {
        if revokedAt != nil { return .revoked }
        if expiredAt != nil || expiresAt.map({ $0 <= date }) == true { return .expired }
        if pausedAt != nil { return .paused }
        guard confirmationState == .userConfirmed, confirmedAt != nil else { return .pendingConfirmation }
        return .active
    }
}

nonisolated struct AgentAccessRequest: Codable, Equatable, Sendable {
    let clientIdentity: AgentClientIdentity
    let profileReference: HealthContextProfileReference
    let operation: AgentAccessOperation
    let dateScope: AgentDateScope
    let metricScope: AgentMetricScope
    let detailLevel: AgentDetailLevel
    let destinationClass: AgentDestinationClass
    /// Opaque request linkage. UUID typing prevents callers from placing prompts or PHI here.
    let correlationID: UUID

    init(
        clientIdentity: AgentClientIdentity,
        profileReference: HealthContextProfileReference,
        operation: AgentAccessOperation,
        dateScope: AgentDateScope,
        metricScope: AgentMetricScope,
        detailLevel: AgentDetailLevel,
        destinationClass: AgentDestinationClass,
        correlationID: UUID = UUID()
    ) {
        self.clientIdentity = clientIdentity
        self.profileReference = profileReference
        self.operation = operation
        self.dateScope = dateScope
        self.metricScope = metricScope
        self.detailLevel = detailLevel
        self.destinationClass = destinationClass
        self.correlationID = correlationID
    }
}

nonisolated struct AgentAuthorizationContext: Equatable, Sendable {
    let request: AgentAccessRequest
    let grantID: UUID
    let profilePolicy: HealthContextProfileEffectivePolicy
    let healthKitAuthorization: AgentHealthKitAuthorizationSnapshot

    init(
        request: AgentAccessRequest,
        grantID: UUID,
        profilePolicy: HealthContextProfileEffectivePolicy,
        healthKitAuthorization: AgentHealthKitAuthorizationSnapshot
    ) {
        self.request = request
        self.grantID = grantID
        self.profilePolicy = profilePolicy
        self.healthKitAuthorization = healthKitAuthorization
    }
}

// MARK: - Stable decisions, outcomes, and activity

nonisolated enum AgentAccessReasonCode: String, Codable, Sendable {
    case allowed
    case invalidRequest = "invalid_request"
    case legacyUnattributedClient = "legacy_unattributed_client"
    case clientNotRegistered = "client_not_registered"
    case clientRegistrationRevoked = "client_registration_revoked"
    case grantNotFound = "grant_not_found"
    case grantClientMismatch = "grant_client_mismatch"
    case grantNotConfirmed = "grant_not_confirmed"
    case grantPaused = "grant_paused"
    case grantExpired = "grant_expired"
    case grantRevoked = "grant_revoked"
    case profileReferenceMismatch = "profile_reference_mismatch"
    case profileRevisionMismatch = "profile_revision_mismatch"
    case profilePolicyDigestMismatch = "profile_policy_digest_mismatch"
    case operationNotGranted = "operation_not_granted"
    case dateScopeNotGranted = "date_scope_not_granted"
    case metricScopeNotGranted = "metric_scope_not_granted"
    case detailLevelNotGranted = "detail_level_not_granted"
    case destinationClassNotGranted = "destination_class_not_granted"
    case profileOperationDenied = "profile_operation_denied"
    case profileDateScopeDenied = "profile_date_scope_denied"
    case profileMetricScopeDenied = "profile_metric_scope_denied"
    case profileDetailLevelDenied = "profile_detail_level_denied"
    case profileDestinationClassDenied = "profile_destination_class_denied"
    case healthKitAuthorizationNotDetermined = "healthkit_authorization_not_determined"
    case healthKitAuthorizationDenied = "healthkit_authorization_denied"
    case healthKitMetricNotAuthorized = "healthkit_metric_not_authorized"
    case accessStoreCorrupt = "access_store_corrupt"
    case unsupportedStoreVersion = "unsupported_store_version"
    case activityHistoryUnavailable = "activity_history_unavailable"
}

nonisolated struct AgentAuthorizationDecision: Equatable, Sendable {
    let isAuthorized: Bool
    let reasonCode: AgentAccessReasonCode
    let grantID: UUID?
    let request: AgentAccessRequest
    let resourceControls: AgentResourceControls?

    static func allow(
        request: AgentAccessRequest,
        grantID: UUID,
        resourceControls: AgentResourceControls?
    ) -> Self {
        Self(
            isAuthorized: true,
            reasonCode: .allowed,
            grantID: grantID,
            request: request,
            resourceControls: resourceControls
        )
    }

    static func deny(
        request: AgentAccessRequest,
        reasonCode: AgentAccessReasonCode,
        grantID: UUID? = nil
    ) -> Self {
        Self(
            isAuthorized: false,
            reasonCode: reasonCode,
            grantID: grantID,
            request: request,
            resourceControls: nil
        )
    }
}

nonisolated enum AgentActivityOutcome: String, Codable, Sendable {
    case authorized
    case succeeded
    case denied
    case failed
    case cancelled
}

/// PHI-minimized access history. It records scope and counts, never health values or delivery details.
nonisolated struct AgentActivityRecord: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let timestamp: Date
    let clientIdentity: AgentClientIdentity
    let grantID: UUID?
    let profileReference: HealthContextProfileReference
    let operation: AgentAccessOperation
    let dateScope: AgentDateScope
    let metricScope: AgentMetricScope
    let detailLevel: AgentDetailLevel
    let destinationClass: AgentDestinationClass
    let resultRecordCount: Int
    let resultByteCount: Int
    let outcome: AgentActivityOutcome
    let reasonCode: AgentAccessReasonCode
    let correlationID: UUID

    init(
        id: UUID = UUID(),
        timestamp: Date = Date(),
        request: AgentAccessRequest,
        grantID: UUID?,
        resultRecordCount: Int,
        resultByteCount: Int,
        outcome: AgentActivityOutcome,
        reasonCode: AgentAccessReasonCode
    ) {
        self.id = id
        self.timestamp = timestamp
        self.clientIdentity = request.clientIdentity
        self.grantID = grantID
        self.profileReference = request.profileReference
        self.operation = request.operation
        self.dateScope = request.dateScope
        self.metricScope = request.metricScope
        self.detailLevel = request.detailLevel
        self.destinationClass = request.destinationClass
        self.resultRecordCount = resultRecordCount
        self.resultByteCount = resultByteCount
        self.outcome = outcome
        self.reasonCode = reasonCode
        self.correlationID = request.correlationID
    }
}

// MARK: - Versioned persistence envelopes

nonisolated struct AgentAccessStoreEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let createdAt: Date
    var updatedAt: Date
    var registrations: [AgentClientRegistration]
    var grants: [AgentAccessGrant]

    init(
        version: Int = Self.currentVersion,
        createdAt: Date,
        updatedAt: Date,
        registrations: [AgentClientRegistration] = [],
        grants: [AgentAccessGrant] = []
    ) {
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.registrations = registrations
        self.grants = grants
    }
}

nonisolated struct AgentActivityStoreEnvelope: Codable, Equatable, Sendable {
    static let currentVersion = 1

    let version: Int
    let createdAt: Date
    var updatedAt: Date
    var records: [AgentActivityRecord]

    init(
        version: Int = Self.currentVersion,
        createdAt: Date,
        updatedAt: Date,
        records: [AgentActivityRecord] = []
    ) {
        self.version = version
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.records = records
    }
}

nonisolated enum AgentAccessStoreStatus: Equatable, Sendable {
    case ready
    case corrupt
    case unsupportedVersion(Int)
}

nonisolated enum AgentAccessManagerErrorCode: String, Codable, Sendable {
    case invalidRegistration = "invalid_registration"
    case invalidGrant = "invalid_grant"
    case invalidActivity = "invalid_activity"
    case registrationNotFound = "registration_not_found"
    case grantNotFound = "grant_not_found"
    case invalidStateTransition = "invalid_state_transition"
    case accessStoreUnavailable = "access_store_unavailable"
    case activityStoreUnavailable = "activity_store_unavailable"
    case persistenceFailed = "persistence_failed"
    case credentialStorageFailed = "credential_storage_failed"
}

nonisolated struct AgentAccessManagerError: Error, Equatable, Sendable {
    let code: AgentAccessManagerErrorCode

    init(_ code: AgentAccessManagerErrorCode) {
        self.code = code
    }
}

/// Keychain seam. Credential bytes cross this hook only and are never members of Codable models.
nonisolated protocol AgentCredentialStoring: Sendable {
    func credential(for registrationID: UUID) throws -> Data?
    func storeCredential(_ credential: Data, for registrationID: UUID) throws
    func removeCredential(for registrationID: UUID) throws
}

nonisolated struct AgentActivityRetentionPolicy: Equatable, Sendable {
    let maximumAge: TimeInterval
    let maximumRecordCount: Int
    let maximumStorageBytes: Int

    init(
        maximumAge: TimeInterval = 90 * 24 * 60 * 60,
        maximumRecordCount: Int = 10_000,
        maximumStorageBytes: Int = 10 * 1_024 * 1_024
    ) {
        self.maximumAge = maximumAge
        self.maximumRecordCount = maximumRecordCount
        self.maximumStorageBytes = maximumStorageBytes
    }
}
