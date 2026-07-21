import Foundation

nonisolated enum HealthContextDateRequest: Codable, Equatable, Sendable {
    case allHistory
    case bounded(HealthContextBoundedDateRange)

    private enum CodingKeys: String, CodingKey { case kind, range }
    private enum Kind: String, Codable { case allHistory = "all_history", bounded }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .allHistory:
            self = .allHistory
        case .bounded:
            self = .bounded(try container.decode(HealthContextBoundedDateRange.self, forKey: .range))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allHistory:
            try container.encode(Kind.allHistory, forKey: .kind)
        case .bounded(let range):
            try container.encode(Kind.bounded, forKey: .kind)
            try container.encode(range, forKey: .range)
        }
    }
}

nonisolated struct HealthContextProfileResolutionRequest: Equatable, Sendable {
    let caller: HealthContextCaller
    let surface: HealthContextSurface
    let destinationID: String
    let dateRequest: HealthContextDateRequest?
    let confirmationProvided: Bool

    init(
        caller: HealthContextCaller,
        surface: HealthContextSurface,
        destinationID: String,
        dateRequest: HealthContextDateRequest? = nil,
        confirmationProvided: Bool = false
    ) {
        self.caller = caller
        self.surface = surface
        self.destinationID = destinationID
        self.dateRequest = dateRequest
        self.confirmationProvided = confirmationProvided
    }
}

/// Fully resolved immutable request. Bounded dates are exact; all-history is a
/// first-class sentinel and never becomes fake distant-past/future dates.
nonisolated struct HealthContextResolvedRequest: Codable, Equatable, Sendable {
    let metricIDs: [String]
    let sourceIDs: [String]
    let detailLevel: HealthContextDetailLevel
    let dates: HealthContextDateRequest
    let destinationID: String
}

/// Authorization result that can be durably attached to an execution journal.
/// It pins profile identity, revision, digest, and the exact resolved request.
nonisolated struct HealthContextExecutionPolicy: Codable, Equatable, Sendable {
    let profileID: UUID
    let revision: HealthContextProfileRevision
    let policyDigest: String
    let caller: HealthContextCaller
    let surface: HealthContextSurface
    let resolvedAt: Date
    let request: HealthContextResolvedRequest
}

nonisolated enum HealthContextProfileResolutionError: Error, Equatable, LocalizedError, Sendable {
    case invalidProfile(HealthContextProfileValidationError)
    case unsupportedReferenceSchema
    case profileIDMismatch
    case revisionMismatch
    case policyDigestMismatch
    case expired
    case unknownCaller
    case unknownSurface
    case callerNotAllowed
    case surfaceNotAllowed
    case invalidDestination
    case destinationMismatch
    case confirmationRequired
    case noAvailableMetrics
    case noAvailableDataSources
    case invalidAvailableMetricIdentifier
    case invalidAvailableDataSourceIdentifier
    case selectedMetricUnavailable
    case selectedDataSourceUnavailable
    case dateRequestRequired
    case invalidDateRequest
    case datePolicyMismatch
    case digestFailure

    var errorDescription: String? {
        switch self {
        case .invalidProfile(let error): return "health_context_profile_\(error.rawValue)"
        case .unsupportedReferenceSchema: return "health_context_reference_unsupported_schema"
        case .profileIDMismatch: return "health_context_profile_id_mismatch"
        case .revisionMismatch: return "health_context_profile_revision_mismatch"
        case .policyDigestMismatch: return "health_context_profile_digest_mismatch"
        case .expired: return "health_context_profile_expired"
        case .unknownCaller: return "health_context_unknown_caller"
        case .unknownSurface: return "health_context_unknown_surface"
        case .callerNotAllowed: return "health_context_caller_not_allowed"
        case .surfaceNotAllowed: return "health_context_surface_not_allowed"
        case .invalidDestination: return "health_context_invalid_destination"
        case .destinationMismatch: return "health_context_destination_mismatch"
        case .confirmationRequired: return "health_context_confirmation_required"
        case .noAvailableMetrics: return "health_context_no_available_metrics"
        case .noAvailableDataSources: return "health_context_no_available_data_sources"
        case .invalidAvailableMetricIdentifier: return "health_context_invalid_available_metric"
        case .invalidAvailableDataSourceIdentifier: return "health_context_invalid_available_source"
        case .selectedMetricUnavailable: return "health_context_selected_metric_unavailable"
        case .selectedDataSourceUnavailable: return "health_context_selected_source_unavailable"
        case .dateRequestRequired: return "health_context_date_request_required"
        case .invalidDateRequest: return "health_context_invalid_date_request"
        case .datePolicyMismatch: return "health_context_date_policy_mismatch"
        case .digestFailure: return "health_context_profile_digest_failure"
        }
    }
}

/// Pure access-policy authorization. The caller supplies the complete runtime
/// metric/source catalogs explicitly; export preferences and HealthKit
/// authorization state are intentionally not dependencies.
nonisolated enum HealthContextProfileResolver {
    static func resolve(
        profile: HealthContextProfile,
        reference: HealthContextProfileReference,
        request: HealthContextProfileResolutionRequest,
        availableMetricIDs: some Sequence<String>,
        availableSourceIDs: some Sequence<String>,
        now: Date
    ) throws -> HealthContextExecutionPolicy {
        do {
            try profile.validate()
        } catch let error as HealthContextProfileValidationError {
            throw HealthContextProfileResolutionError.invalidProfile(error)
        } catch {
            throw HealthContextProfileResolutionError.digestFailure
        }

        guard reference.schemaIdentifier == HealthContextProfileSchema.identifier,
              reference.schemaVersion == HealthContextProfileSchema.version else {
            throw HealthContextProfileResolutionError.unsupportedReferenceSchema
        }
        guard reference.profileID == profile.id else {
            throw HealthContextProfileResolutionError.profileIDMismatch
        }
        guard reference.revision == profile.revision else {
            throw HealthContextProfileResolutionError.revisionMismatch
        }
        let currentDigest: String
        do {
            currentDigest = try profile.policyDigest()
        } catch {
            throw HealthContextProfileResolutionError.digestFailure
        }
        guard reference.policyDigest == currentDigest else {
            throw HealthContextProfileResolutionError.policyDigestMismatch
        }
        guard profile.expiresAt.map({ $0 > now }) ?? true else {
            throw HealthContextProfileResolutionError.expired
        }
        guard request.caller.isKnown else {
            throw HealthContextProfileResolutionError.unknownCaller
        }
        guard request.surface.isKnown else {
            throw HealthContextProfileResolutionError.unknownSurface
        }
        guard profile.allowedCallers.contains(request.caller) else {
            throw HealthContextProfileResolutionError.callerNotAllowed
        }
        guard profile.allowedSurfaces.contains(request.surface) else {
            throw HealthContextProfileResolutionError.surfaceNotAllowed
        }
        guard isValidIdentifier(request.destinationID) else {
            throw HealthContextProfileResolutionError.invalidDestination
        }
        if case .exact(let expectedDestinationID) = profile.destinationBinding {
            guard request.destinationID == expectedDestinationID else {
                throw HealthContextProfileResolutionError.destinationMismatch
            }
        }
        if profile.confirmationRequirement == .required, !request.confirmationProvided {
            throw HealthContextProfileResolutionError.confirmationRequired
        }

        let availableMetricList = Array(availableMetricIDs)
        let availableSourceList = Array(availableSourceIDs)
        guard availableMetricList.allSatisfy(isValidIdentifier) else {
            throw HealthContextProfileResolutionError.invalidAvailableMetricIdentifier
        }
        guard availableSourceList.allSatisfy(isValidIdentifier) else {
            throw HealthContextProfileResolutionError.invalidAvailableDataSourceIdentifier
        }
        let availableMetrics = Set(availableMetricList)
        let availableSources = Set(availableSourceList)
        let resolvedMetrics: [String]
        switch profile.metricScope {
        case .allAvailable:
            guard !availableMetrics.isEmpty else {
                throw HealthContextProfileResolutionError.noAvailableMetrics
            }
            resolvedMetrics = availableMetrics.sorted()
        case .selected(let metricIDs):
            guard metricIDs.allSatisfy(availableMetrics.contains) else {
                throw HealthContextProfileResolutionError.selectedMetricUnavailable
            }
            // Exact selected profiles remain frozen even when the runtime
            // catalog gains additional metrics.
            resolvedMetrics = metricIDs.sorted()
        }

        let resolvedSources: [String]
        switch profile.dataSourceScope {
        case .allAvailable:
            guard !availableSources.isEmpty else {
                throw HealthContextProfileResolutionError.noAvailableDataSources
            }
            resolvedSources = availableSources.sorted()
        case .selected(let sourceIDs):
            guard sourceIDs.allSatisfy(availableSources.contains) else {
                throw HealthContextProfileResolutionError.selectedDataSourceUnavailable
            }
            resolvedSources = sourceIDs.sorted()
        }

        let resolvedDates = try resolveDates(
            policy: profile.datePolicy,
            request: request.dateRequest,
            now: now
        )
        return HealthContextExecutionPolicy(
            profileID: profile.id,
            revision: profile.revision,
            policyDigest: currentDigest,
            caller: request.caller,
            surface: request.surface,
            resolvedAt: now,
            request: HealthContextResolvedRequest(
                metricIDs: resolvedMetrics,
                sourceIDs: resolvedSources,
                detailLevel: profile.detailLevel,
                dates: resolvedDates,
                destinationID: request.destinationID
            )
        )
    }

    private static func resolveDates(
        policy: HealthContextDatePolicy,
        request: HealthContextDateRequest?,
        now: Date
    ) throws -> HealthContextDateRequest {
        switch policy {
        case .allHistory:
            switch request {
            case nil, .allHistory?:
                return .allHistory
            case .bounded(let range)?:
                try validate(range)
                return .bounded(range)
            }
        case .explicit(let exactRange):
            try validate(exactRange)
            switch request {
            case nil:
                return .bounded(exactRange)
            case .bounded(let requestedRange)? where requestedRange == exactRange:
                return .bounded(exactRange)
            case .allHistory?, .bounded(_)?:
                throw HealthContextProfileResolutionError.datePolicyMismatch
            }
        case .callerProvided:
            guard case .bounded(let range)? = request else {
                if request == nil {
                    throw HealthContextProfileResolutionError.dateRequestRequired
                }
                throw HealthContextProfileResolutionError.datePolicyMismatch
            }
            try validate(range)
            return .bounded(range)
        case .relative(let duration):
            guard request == nil else {
                throw HealthContextProfileResolutionError.datePolicyMismatch
            }
            let range = HealthContextBoundedDateRange(
                start: now.addingTimeInterval(-duration),
                end: now
            )
            try validate(range)
            return .bounded(range)
        }
    }

    private static func validate(_ range: HealthContextBoundedDateRange) throws {
        guard range.start.timeIntervalSinceReferenceDate.isFinite,
              range.end.timeIntervalSinceReferenceDate.isFinite,
              range.start <= range.end else {
            throw HealthContextProfileResolutionError.invalidDateRequest
        }
    }

    private static func isValidIdentifier(_ identifier: String) -> Bool {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == identifier && identifier.utf8.count <= 1_024
    }
}
