import Foundation

/// Owns registration, grants, authorization decisions, and PHI-minimized activity history.
/// Actor isolation serializes in-memory mutations; each committed mutation uses an atomic file replace.
actor AgentAccessManager {
    nonisolated static let accessStoreFilename = "agent-access-v1.json"
    nonisolated static let activityStoreFilename = "agent-activity-v1.json"

    private let directoryURL: URL
    private let accessStoreURL: URL
    private let activityStoreURL: URL
    private let clock: @Sendable () -> Date
    private let fileManager: FileManager
    private let credentialStore: (any AgentCredentialStoring)?
    private let retentionPolicy: AgentActivityRetentionPolicy

    private var accessEnvelope: AgentAccessStoreEnvelope
    private var activityEnvelope: AgentActivityStoreEnvelope
    private var accessStatus: AgentAccessStoreStatus
    private var activityStatus: AgentAccessStoreStatus

    init(
        directoryURL: URL? = nil,
        clock: @escaping @Sendable () -> Date = { Date() },
        fileManager: FileManager = .default,
        credentialStore: (any AgentCredentialStoring)? = nil,
        retentionPolicy: AgentActivityRetentionPolicy = AgentActivityRetentionPolicy()
    ) {
        let resolvedDirectory = directoryURL ?? Self.defaultApplicationSupportDirectory(fileManager: fileManager)
        let accessURL = resolvedDirectory.appendingPathComponent(Self.accessStoreFilename, isDirectory: false)
        let activityURL = resolvedDirectory.appendingPathComponent(Self.activityStoreFilename, isDirectory: false)
        let now = clock()

        self.directoryURL = resolvedDirectory
        self.accessStoreURL = accessURL
        self.activityStoreURL = activityURL
        self.clock = clock
        self.fileManager = fileManager
        self.credentialStore = credentialStore
        self.retentionPolicy = retentionPolicy

        let loadedAccess: (AgentAccessStoreEnvelope, AgentAccessStoreStatus) = Self.loadEnvelope(
            AgentAccessStoreEnvelope.self,
            at: accessURL,
            currentVersion: AgentAccessStoreEnvelope.currentVersion,
            fallback: AgentAccessStoreEnvelope(createdAt: now, updatedAt: now),
            fileManager: fileManager
        )
        let loadedActivity: (AgentActivityStoreEnvelope, AgentAccessStoreStatus) = Self.loadEnvelope(
            AgentActivityStoreEnvelope.self,
            at: activityURL,
            currentVersion: AgentActivityStoreEnvelope.currentVersion,
            fallback: AgentActivityStoreEnvelope(createdAt: now, updatedAt: now),
            fileManager: fileManager
        )
        self.accessEnvelope = loadedAccess.0
        self.accessStatus = loadedAccess.1
        self.activityEnvelope = loadedActivity.0
        self.activityStatus = loadedActivity.1
    }

    // MARK: - Store state and snapshots

    func accessStoreStatus() -> AgentAccessStoreStatus { accessStatus }
    func activityStoreStatus() -> AgentAccessStoreStatus { activityStatus }

    func registrations() -> [AgentClientRegistration] {
        accessEnvelope.registrations.sorted { $0.createdAt < $1.createdAt }
    }

    func registration(id: UUID) -> AgentClientRegistration? {
        accessEnvelope.registrations.first { $0.id == id }
    }

    func grants(for registrationID: UUID? = nil) -> [AgentAccessGrant] {
        accessEnvelope.grants
            .filter { registrationID == nil || $0.clientRegistrationID == registrationID }
            .sorted { $0.createdAt < $1.createdAt }
    }

    func grant(id: UUID) -> AgentAccessGrant? {
        accessEnvelope.grants.first { $0.id == id }
    }

    func activityHistory() -> [AgentActivityRecord] {
        activityEnvelope.records.sorted { $0.timestamp > $1.timestamp }
    }

    // MARK: - Registration

    @discardableResult
    func registerClient(
        displayName: String,
        kind: AgentClientKind,
        credential: Data? = nil
    ) throws -> AgentClientRegistration {
        try requireWritableAccessStore()
        let now = clock()
        let registration = AgentClientRegistration(
            displayName: displayName,
            kind: kind,
            createdAt: now
        )
        guard Self.isValid(registration) else {
            throw AgentAccessManagerError(.invalidRegistration)
        }

        if let credential {
            guard !credential.isEmpty, let credentialStore else {
                throw AgentAccessManagerError(.credentialStorageFailed)
            }
            do {
                try credentialStore.storeCredential(credential, for: registration.id)
            } catch {
                throw AgentAccessManagerError(.credentialStorageFailed)
            }
        }

        var next = accessEnvelope
        next.updatedAt = now
        next.registrations.append(registration)
        do {
            try persistAccess(next)
            accessEnvelope = next
            return registration
        } catch {
            if credential != nil {
                try? credentialStore?.removeCredential(for: registration.id)
            }
            throw error
        }
    }

    @discardableResult
    func revokeRegistration(_ registrationID: UUID) throws -> AgentClientRegistration {
        try requireWritableAccessStore()
        guard let index = accessEnvelope.registrations.firstIndex(where: { $0.id == registrationID }) else {
            throw AgentAccessManagerError(.registrationNotFound)
        }
        var next = accessEnvelope
        let now = clock()
        next.updatedAt = now
        next.registrations[index].state = .revoked
        next.registrations[index].revokedAt = now
        try persistAccess(next)
        accessEnvelope = next
        try? credentialStore?.removeCredential(for: registrationID)
        return next.registrations[index]
    }

    // MARK: - Credential hooks

    func credential(for registrationID: UUID) throws -> Data? {
        guard let credentialStore else {
            throw AgentAccessManagerError(.credentialStorageFailed)
        }
        do {
            return try credentialStore.credential(for: registrationID)
        } catch {
            throw AgentAccessManagerError(.credentialStorageFailed)
        }
    }

    func storeCredential(_ credential: Data, for registrationID: UUID) throws {
        guard !credential.isEmpty,
              accessEnvelope.registrations.contains(where: { $0.id == registrationID }),
              let credentialStore else {
            throw AgentAccessManagerError(.credentialStorageFailed)
        }
        do {
            try credentialStore.storeCredential(credential, for: registrationID)
        } catch {
            throw AgentAccessManagerError(.credentialStorageFailed)
        }
    }

    func removeCredential(for registrationID: UUID) throws {
        guard let credentialStore else {
            throw AgentAccessManagerError(.credentialStorageFailed)
        }
        do {
            try credentialStore.removeCredential(for: registrationID)
        } catch {
            throw AgentAccessManagerError(.credentialStorageFailed)
        }
    }

    // MARK: - Grants

    /// Persists a complete grant exactly as the user approved. This method never narrows its scopes.
    @discardableResult
    func saveGrant(_ grant: AgentAccessGrant) throws -> AgentAccessGrant {
        try requireWritableAccessStore()
        guard Self.isValid(grant),
              accessEnvelope.registrations.contains(where: {
                  $0.id == grant.clientRegistrationID && $0.state == .active
              }) else {
            throw AgentAccessManagerError(.invalidGrant)
        }

        guard !accessEnvelope.grants.contains(where: { $0.id == grant.id }) else {
            // Scope and terminal lifecycle fields are immutable. A changed approval is a new grant.
            throw AgentAccessManagerError(.invalidStateTransition)
        }
        var next = accessEnvelope
        next.updatedAt = clock()
        next.grants.append(grant)
        try persistAccess(next)
        accessEnvelope = next
        return grant
    }

    @discardableResult
    func confirmGrant(_ grantID: UUID) throws -> AgentAccessGrant {
        try mutateGrant(grantID) { grant, now in
            guard grant.revokedAt == nil, grant.expiredAt == nil else {
                throw AgentAccessManagerError(.invalidStateTransition)
            }
            grant.confirmationState = .userConfirmed
            grant.confirmedAt = now
        }
    }

    @discardableResult
    func pauseGrant(_ grantID: UUID) throws -> AgentAccessGrant {
        try mutateGrant(grantID) { grant, now in
            guard grant.status(at: now) == .active else {
                throw AgentAccessManagerError(.invalidStateTransition)
            }
            grant.pausedAt = now
        }
    }

    @discardableResult
    func resumeGrant(_ grantID: UUID) throws -> AgentAccessGrant {
        try mutateGrant(grantID) { grant, now in
            guard grant.pausedAt != nil,
                  grant.revokedAt == nil,
                  grant.expiredAt == nil,
                  grant.expiresAt.map({ $0 > now }) != false else {
                throw AgentAccessManagerError(.invalidStateTransition)
            }
            grant.pausedAt = nil
        }
    }

    @discardableResult
    func revokeGrant(_ grantID: UUID) throws -> AgentAccessGrant {
        try mutateGrant(grantID) { grant, now in
            guard grant.revokedAt == nil else {
                throw AgentAccessManagerError(.invalidStateTransition)
            }
            grant.revokedAt = now
            grant.pausedAt = nil
        }
    }

    @discardableResult
    func expireGrant(_ grantID: UUID) throws -> AgentAccessGrant {
        try mutateGrant(grantID) { grant, now in
            guard grant.revokedAt == nil, grant.expiredAt == nil else {
                throw AgentAccessManagerError(.invalidStateTransition)
            }
            grant.expiredAt = now
            grant.pausedAt = nil
        }
    }

    /// Materializes time-based expiry for every eligible grant. Authorization also checks `expiresAt`
    /// directly, so a grant cannot remain usable merely because this maintenance API has not run.
    @discardableResult
    func expireEligibleGrants() throws -> [UUID] {
        try requireWritableAccessStore()
        let now = clock()
        var next = accessEnvelope
        var expired: [UUID] = []
        for index in next.grants.indices where
            next.grants[index].revokedAt == nil &&
            next.grants[index].expiredAt == nil &&
            next.grants[index].expiresAt.map({ $0 <= now }) == true {
            next.grants[index].expiredAt = now
            next.grants[index].pausedAt = nil
            expired.append(next.grants[index].id)
        }
        guard !expired.isEmpty else { return [] }
        next.updatedAt = now
        try persistAccess(next)
        accessEnvelope = next
        return expired
    }

    // MARK: - Authorization

    /// Side-effect-free authorization check. Every requested scope must fit both the grant and
    /// supplied profile policy; the request is never silently rewritten to a smaller scope.
    func checkAuthorization(_ context: AgentAuthorizationContext) -> AgentAuthorizationDecision {
        evaluate(context)
    }

    /// Checks authorization and atomically records the authorization outcome in local history.
    /// If activity history is corrupt, execution is denied rather than proceeding without an audit.
    func authorize(_ context: AgentAuthorizationContext) throws -> AgentAuthorizationDecision {
        guard activityStatus == .ready else {
            return .deny(request: context.request, reasonCode: .activityHistoryUnavailable, grantID: context.grantID)
        }
        let decision = evaluate(context)
        _ = try appendActivity(
            request: context.request,
            grantID: decision.grantID,
            resultRecordCount: 0,
            resultByteCount: 0,
            outcome: decision.isAuthorized ? .authorized : .denied,
            reasonCode: decision.reasonCode
        )
        return decision
    }

    private func evaluate(_ context: AgentAuthorizationContext) -> AgentAuthorizationDecision {
        let request = context.request
        guard accessStatus == .ready else {
            let code: AgentAccessReasonCode
            switch accessStatus {
            case .unsupportedVersion: code = .unsupportedStoreVersion
            case .ready: code = .allowed
            case .corrupt: code = .accessStoreCorrupt
            }
            return .deny(request: request, reasonCode: code, grantID: context.grantID)
        }
        guard Self.isValid(request) else {
            return .deny(request: request, reasonCode: .invalidRequest, grantID: context.grantID)
        }
        guard request.clientIdentity.kind == .registeredClient,
              let registrationID = request.clientIdentity.registrationID else {
            return .deny(request: request, reasonCode: .legacyUnattributedClient, grantID: context.grantID)
        }
        guard let registration = accessEnvelope.registrations.first(where: { $0.id == registrationID }) else {
            return .deny(request: request, reasonCode: .clientNotRegistered, grantID: context.grantID)
        }
        guard registration.state == .active else {
            return .deny(request: request, reasonCode: .clientRegistrationRevoked, grantID: context.grantID)
        }
        guard let grant = accessEnvelope.grants.first(where: { $0.id == context.grantID }) else {
            return .deny(request: request, reasonCode: .grantNotFound, grantID: context.grantID)
        }
        guard grant.clientRegistrationID == registrationID else {
            return .deny(request: request, reasonCode: .grantClientMismatch, grantID: grant.id)
        }

        switch grant.status(at: clock()) {
        case .pendingConfirmation:
            return .deny(request: request, reasonCode: .grantNotConfirmed, grantID: grant.id)
        case .paused:
            return .deny(request: request, reasonCode: .grantPaused, grantID: grant.id)
        case .expired:
            return .deny(request: request, reasonCode: .grantExpired, grantID: grant.id)
        case .revoked:
            return .deny(request: request, reasonCode: .grantRevoked, grantID: grant.id)
        case .active:
            break
        }

        if request.profileReference.schemaIdentifier != grant.profileReference.schemaIdentifier ||
            request.profileReference.schemaVersion != grant.profileReference.schemaVersion ||
            request.profileReference.profileID != grant.profileReference.profileID {
            return .deny(request: request, reasonCode: .profileReferenceMismatch, grantID: grant.id)
        }
        if request.profileReference.revision != grant.profileReference.revision {
            return .deny(request: request, reasonCode: .profileRevisionMismatch, grantID: grant.id)
        }
        if request.profileReference.policyDigest != grant.profileReference.policyDigest {
            return .deny(request: request, reasonCode: .profilePolicyDigestMismatch, grantID: grant.id)
        }
        if context.profilePolicy.reference.schemaIdentifier != grant.profileReference.schemaIdentifier ||
            context.profilePolicy.reference.schemaVersion != grant.profileReference.schemaVersion ||
            context.profilePolicy.reference.profileID != grant.profileReference.profileID {
            return .deny(request: request, reasonCode: .profileReferenceMismatch, grantID: grant.id)
        }
        if context.profilePolicy.reference.revision != grant.profileReference.revision {
            return .deny(request: request, reasonCode: .profileRevisionMismatch, grantID: grant.id)
        }
        if context.profilePolicy.reference.policyDigest != grant.profileReference.policyDigest {
            return .deny(request: request, reasonCode: .profilePolicyDigestMismatch, grantID: grant.id)
        }

        guard grant.operations.contains(request.operation) else {
            return .deny(request: request, reasonCode: .operationNotGranted, grantID: grant.id)
        }
        guard grant.dateScope.contains(request.dateScope) else {
            return .deny(request: request, reasonCode: .dateScopeNotGranted, grantID: grant.id)
        }
        guard grant.metricScope.contains(request.metricScope) else {
            return .deny(request: request, reasonCode: .metricScopeNotGranted, grantID: grant.id)
        }
        guard grant.detailLevels.contains(request.detailLevel) else {
            return .deny(request: request, reasonCode: .detailLevelNotGranted, grantID: grant.id)
        }
        guard grant.destinationClasses.contains(request.destinationClass) else {
            return .deny(request: request, reasonCode: .destinationClassNotGranted, grantID: grant.id)
        }

        guard context.profilePolicy.operations.contains(request.operation) else {
            return .deny(request: request, reasonCode: .profileOperationDenied, grantID: grant.id)
        }
        guard context.profilePolicy.dateScope.contains(request.dateScope) else {
            return .deny(request: request, reasonCode: .profileDateScopeDenied, grantID: grant.id)
        }
        guard context.profilePolicy.metricScope.contains(request.metricScope) else {
            return .deny(request: request, reasonCode: .profileMetricScopeDenied, grantID: grant.id)
        }
        guard context.profilePolicy.detailLevels.contains(request.detailLevel) else {
            return .deny(request: request, reasonCode: .profileDetailLevelDenied, grantID: grant.id)
        }
        guard context.profilePolicy.destinationClasses.contains(request.destinationClass) else {
            return .deny(request: request, reasonCode: .profileDestinationClassDenied, grantID: grant.id)
        }

        switch context.healthKitAuthorization.state {
        case .notRequiredForCachedData:
            break
        case .notDetermined:
            return .deny(request: request, reasonCode: .healthKitAuthorizationNotDetermined, grantID: grant.id)
        case .denied:
            return .deny(request: request, reasonCode: .healthKitAuthorizationDenied, grantID: grant.id)
        case .authorized:
            guard context.healthKitAuthorization.readableMetrics.contains(request.metricScope) else {
                return .deny(request: request, reasonCode: .healthKitMetricNotAuthorized, grantID: grant.id)
            }
        }

        return .allow(request: request, grantID: grant.id, resourceControls: grant.resourceControls)
    }

    // MARK: - Activity history

    @discardableResult
    func recordActivity(
        for request: AgentAccessRequest,
        grantID: UUID?,
        resultRecordCount: Int,
        resultByteCount: Int,
        outcome: AgentActivityOutcome,
        reasonCode: AgentAccessReasonCode = .allowed
    ) throws -> AgentActivityRecord {
        try appendActivity(
            request: request,
            grantID: grantID,
            resultRecordCount: resultRecordCount,
            resultByteCount: resultByteCount,
            outcome: outcome,
            reasonCode: reasonCode
        )
    }

    /// Clears only access activity. Registrations, grants, revocations, and Keychain items are untouched.
    func clearActivityHistory() throws {
        let now = clock()
        let next = AgentActivityStoreEnvelope(createdAt: now, updatedAt: now)
        try persistActivity(next)
        activityEnvelope = next
        activityStatus = .ready
    }

    private func appendActivity(
        request: AgentAccessRequest,
        grantID: UUID?,
        resultRecordCount: Int,
        resultByteCount: Int,
        outcome: AgentActivityOutcome,
        reasonCode: AgentAccessReasonCode
    ) throws -> AgentActivityRecord {
        guard activityStatus == .ready else {
            throw AgentAccessManagerError(.activityStoreUnavailable)
        }
        guard resultRecordCount >= 0, resultByteCount >= 0 else {
            throw AgentAccessManagerError(.invalidActivity)
        }
        let now = clock()
        let record = AgentActivityRecord(
            timestamp: now,
            request: request,
            grantID: grantID,
            resultRecordCount: resultRecordCount,
            resultByteCount: resultByteCount,
            outcome: outcome,
            reasonCode: reasonCode
        )
        var next = activityEnvelope
        next.updatedAt = now
        next.records.insert(record, at: 0)
        next = prune(next, now: now)
        try persistActivity(next)
        activityEnvelope = next
        return record
    }

    private func prune(_ envelope: AgentActivityStoreEnvelope, now: Date) -> AgentActivityStoreEnvelope {
        var result = envelope
        let oldestAllowed = now.addingTimeInterval(-retentionPolicy.maximumAge)
        result.records = result.records
            .filter { $0.timestamp >= oldestAllowed }
            .sorted { $0.timestamp > $1.timestamp }
        if result.records.count > retentionPolicy.maximumRecordCount {
            result.records = Array(result.records.prefix(retentionPolicy.maximumRecordCount))
        }

        let encoder = Self.makeEncoder()
        while !result.records.isEmpty,
              (try? encoder.encode(result).count) ?? Int.max > retentionPolicy.maximumStorageBytes {
            result.records.removeLast()
        }
        return result
    }

    // MARK: - Mutation and persistence helpers

    private func mutateGrant(
        _ grantID: UUID,
        mutation: (inout AgentAccessGrant, Date) throws -> Void
    ) throws -> AgentAccessGrant {
        try requireWritableAccessStore()
        guard let index = accessEnvelope.grants.firstIndex(where: { $0.id == grantID }) else {
            throw AgentAccessManagerError(.grantNotFound)
        }
        let now = clock()
        var next = accessEnvelope
        try mutation(&next.grants[index], now)
        next.updatedAt = now
        try persistAccess(next)
        accessEnvelope = next
        return next.grants[index]
    }

    private func requireWritableAccessStore() throws {
        guard accessStatus == .ready else {
            throw AgentAccessManagerError(.accessStoreUnavailable)
        }
    }

    private func persistAccess(_ envelope: AgentAccessStoreEnvelope) throws {
        do {
            try Self.persist(envelope, to: accessStoreURL, directoryURL: directoryURL, fileManager: fileManager)
        } catch let error as AgentAccessManagerError {
            throw error
        } catch {
            throw AgentAccessManagerError(.persistenceFailed)
        }
    }

    private func persistActivity(_ envelope: AgentActivityStoreEnvelope) throws {
        do {
            try Self.persist(envelope, to: activityStoreURL, directoryURL: directoryURL, fileManager: fileManager)
        } catch let error as AgentAccessManagerError {
            throw error
        } catch {
            throw AgentAccessManagerError(.persistenceFailed)
        }
    }

    private nonisolated static func persist<T: Encodable>(
        _ value: T,
        to url: URL,
        directoryURL: URL,
        fileManager: FileManager
    ) throws {
        try fileManager.createDirectory(
            at: directoryURL,
            withIntermediateDirectories: true,
            attributes: protectedAttributes(permissions: 0o700)
        )
        try? fileManager.setAttributes(
            protectedAttributes(permissions: 0o700),
            ofItemAtPath: directoryURL.path
        )
        var mutableDirectory = directoryURL
        var resourceValues = URLResourceValues()
        resourceValues.isExcludedFromBackup = true
        try? mutableDirectory.setResourceValues(resourceValues)

        let data = try makeEncoder().encode(value)
        try AtomicFileWriter.writeData(
            data,
            to: url,
            fileManager: fileManager,
            attributes: protectedAttributes(permissions: 0o600)
        )
        try fileManager.setAttributes(
            protectedAttributes(permissions: 0o600),
            ofItemAtPath: url.path
        )
    }

    private nonisolated static func protectedAttributes(permissions: Int) -> [FileAttributeKey: Any] {
        var attributes: [FileAttributeKey: Any] = [.posixPermissions: permissions]
        #if os(iOS)
        attributes[.protectionKey] = FileProtectionType.complete
        #endif
        return attributes
    }

    private nonisolated static func loadEnvelope<T: Decodable>(
        _ type: T.Type,
        at url: URL,
        currentVersion: Int,
        fallback: T,
        fileManager: FileManager
    ) -> (T, AgentAccessStoreStatus) {
        guard fileManager.fileExists(atPath: url.path) else { return (fallback, .ready) }
        do {
            let data = try Data(contentsOf: url)
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any]
            guard let version = json?["version"] as? Int else { return (fallback, .corrupt) }
            guard version == currentVersion else { return (fallback, .unsupportedVersion(version)) }
            return (try makeDecoder().decode(type, from: data), .ready)
        } catch {
            return (fallback, .corrupt)
        }
    }

    private nonisolated static func makeEncoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        // Foundation's deferred Date representation round-trips subsecond request bounds.
        encoder.dateEncodingStrategy = .deferredToDate
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private nonisolated static func makeDecoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .deferredToDate
        return decoder
    }

    private nonisolated static func defaultApplicationSupportDirectory(fileManager: FileManager) -> URL {
        let root = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? URL(fileURLWithPath: NSHomeDirectory()).appendingPathComponent("Library/Application Support", isDirectory: true)
        return root
            .appendingPathComponent("Health.md", isDirectory: true)
            .appendingPathComponent("AgentAccess", isDirectory: true)
    }

    private nonisolated static func isValid(_ registration: AgentClientRegistration) -> Bool {
        !registration.displayName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
        ((registration.state == .active && registration.revokedAt == nil) ||
         (registration.state == .revoked && registration.revokedAt != nil))
    }

    private nonisolated static func isValid(_ request: AgentAccessRequest) -> Bool {
        guard isValid(request.profileReference),
              isValid(request.dateScope),
              isValid(request.metricScope) else { return false }
        switch request.clientIdentity.kind {
        case .registeredClient: return request.clientIdentity.registrationID != nil
        case .legacyUnattributedLocalProcess: return request.clientIdentity.registrationID == nil
        }
    }

    private nonisolated static func isValid(_ grant: AgentAccessGrant) -> Bool {
        guard isValid(grant.profileReference),
              isValid(grant.dateScope),
              isValid(grant.metricScope),
              isValid(grant.operations),
              isValid(grant.detailLevels),
              isValid(grant.destinationClasses),
              isValid(grant.resourceControls) else { return false }
        if grant.confirmationState == .userConfirmed && grant.confirmedAt == nil { return false }
        if grant.confirmationState == .pending && grant.confirmedAt != nil { return false }
        if let expiresAt = grant.expiresAt, expiresAt <= grant.createdAt { return false }
        return true
    }

    private nonisolated static func isValid(_ reference: HealthContextProfileReference) -> Bool {
        reference.schemaIdentifier == HealthContextProfileSchema.identifier &&
        reference.schemaVersion == HealthContextProfileSchema.version &&
        reference.revision.rawValue > 0 &&
        reference.policyDigest.count == 64 &&
        reference.policyDigest.utf8.allSatisfy { byte in
            (48...57).contains(byte) || (97...102).contains(byte)
        }
    }

    private nonisolated static func isValid(_ scope: AgentDateScope) -> Bool {
        switch scope {
        case .allHistory: return true
        case let .exactRange(range): return range.start <= range.end
        }
    }

    private nonisolated static func isValid(_ scope: AgentMetricScope) -> Bool {
        switch scope {
        case .allAvailable: return true
        case let .metricIDs(ids):
            return !ids.isEmpty && ids.allSatisfy {
                !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            }
        }
    }

    private nonisolated static func isValid(_ scope: AgentOperationScope) -> Bool {
        switch scope {
        case .allOperations: return true
        case let .operations(values): return !values.isEmpty
        }
    }

    private nonisolated static func isValid(_ scope: AgentDetailScope) -> Bool {
        switch scope {
        case .allDetailLevels: return true
        case let .detailLevels(values): return !values.isEmpty
        }
    }

    private nonisolated static func isValid(_ scope: AgentDestinationScope) -> Bool {
        switch scope {
        case .allDestinationClasses: return true
        case let .destinationClasses(values): return !values.isEmpty
        }
    }

    private nonisolated static func isValid(_ controls: AgentResourceControls?) -> Bool {
        guard let controls else { return true }
        return [controls.maxRecordsPerPage, controls.maxBytesPerPage, controls.maxBytesPerStreamChunk]
            .compactMap { $0 }
            .allSatisfy { $0 > 0 }
    }
}
