import CryptoKit
import Foundation

/// Independent contract for durable Health Context access policies. This is not
/// the Health.md export schema and changes here must not alter HealthMdExportSchema.
nonisolated enum HealthContextProfileSchema {
    static let identifier = "healthmd.health_context_profile"
    static let version = 1
}

nonisolated struct HealthContextProfileRevision: RawRepresentable, Codable, Hashable, Comparable, Sendable {
    let rawValue: Int

    init(rawValue: Int) {
        self.rawValue = rawValue
    }

    init(_ rawValue: Int) {
        self.rawValue = rawValue
    }

    static func < (lhs: Self, rhs: Self) -> Bool {
        lhs.rawValue < rhs.rawValue
    }

    init(from decoder: Decoder) throws {
        self.init(try decoder.singleValueContainer().decode(Int.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Extensible string values deliberately decode unknown future callers. The
/// resolver recognizes only the values compiled into this version and denies
/// every other value.
nonisolated struct HealthContextCaller: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let interactiveUser = Self(rawValue: "interactive_user")
    static let appIntent = Self(rawValue: "app_intent")
    static let scheduledAutomation = Self(rawValue: "scheduled_automation")
    static let commandLine = Self(rawValue: "command_line")
    static let registeredAgent = Self(rawValue: "registered_agent")
    static let externalIntegration = Self(rawValue: "external_integration")

    static let knownValues: Set<Self> = [
        .interactiveUser, .appIntent, .scheduledAutomation, .commandLine, .registeredAgent,
        .externalIntegration,
    ]

    var isKnown: Bool { Self.knownValues.contains(self) }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

/// Extensible execution surface identifier with fail-closed resolution.
nonisolated struct HealthContextSurface: RawRepresentable, Codable, Hashable, Sendable {
    let rawValue: String

    init(rawValue: String) {
        self.rawValue = rawValue
    }

    static let iOSApp = Self(rawValue: "ios_app")
    static let macOSApp = Self(rawValue: "macos_app")
    static let shortcuts = Self(rawValue: "shortcuts")
    static let commandLine = Self(rawValue: "command_line")
    static let localControlAPI = Self(rawValue: "local_control_api")
    static let mcpStdio = Self(rawValue: "mcp_stdio")

    static let knownValues: Set<Self> = [
        .iOSApp, .macOSApp, .shortcuts, .commandLine, .localControlAPI, .mcpStdio,
    ]

    var isKnown: Bool { Self.knownValues.contains(self) }

    init(from decoder: Decoder) throws {
        self.init(rawValue: try decoder.singleValueContainer().decode(String.self))
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}

nonisolated enum HealthContextMetricScope: Equatable, Sendable {
    /// Resolves against the complete supported metric catalog at execution time,
    /// so future metrics are included without revising the profile.
    case allAvailable
    /// The identifiers are an exact, frozen selection. Resolution never adds a
    /// newly supported metric to this case.
    case selected(metricIDs: [String])
}

nonisolated enum HealthContextDataSourceScope: Equatable, Sendable {
    /// Resolves against every source/provider available to the execution.
    case allAvailable
    /// Exact, frozen source/provider identifiers.
    case selected(sourceIDs: [String])
}

nonisolated enum HealthContextDetailLevel: String, Codable, Equatable, Sendable {
    case summary
    case lossless
}

nonisolated struct HealthContextBoundedDateRange: Codable, Equatable, Sendable {
    let start: Date
    let end: Date

    init(start: Date, end: Date) {
        self.start = start
        self.end = end
    }
}

nonisolated enum HealthContextDatePolicy: Equatable, Sendable {
    /// Permission and execution can cover the complete history without fake
    /// sentinel dates or pre-enumerating days.
    case allHistory
    /// A fixed, exact bounded interval stored in the profile.
    case explicit(HealthContextBoundedDateRange)
    /// Requires the caller to provide an exact bounded interval per execution.
    case callerProvided
    /// Resolves to the exact interval ending at the resolver's trusted `now`.
    /// There is intentionally no maximum duration.
    case relative(duration: TimeInterval)
}

nonisolated enum HealthContextConfirmationRequirement: String, Codable, Equatable, Sendable {
    case notRequired = "not_required"
    case required
}

nonisolated enum HealthContextDestinationBinding: Equatable, Sendable {
    /// The profile can execute against any explicitly identified destination.
    case any
    /// The execution destination must exactly match this stable identifier.
    case exact(destinationID: String)
}

nonisolated struct HealthContextProfile: Codable, Equatable, Identifiable, Sendable {
    let schemaIdentifier: String
    let schemaVersion: Int
    let id: UUID
    let revision: HealthContextProfileRevision
    let name: String
    let metricScope: HealthContextMetricScope
    let dataSourceScope: HealthContextDataSourceScope
    let detailLevel: HealthContextDetailLevel
    let datePolicy: HealthContextDatePolicy
    let allowedCallers: [HealthContextCaller]
    let allowedSurfaces: [HealthContextSurface]
    let confirmationRequirement: HealthContextConfirmationRequirement
    let expiresAt: Date?
    let destinationBinding: HealthContextDestinationBinding
    let createdAt: Date
    let updatedAt: Date

    enum CodingKeys: String, CodingKey {
        case schemaIdentifier = "schema"
        case schemaVersion = "schema_version"
        case id, revision, name
        case metricScope = "metric_scope"
        case dataSourceScope = "data_source_scope"
        case detailLevel = "detail_level"
        case datePolicy = "date_policy"
        case allowedCallers = "allowed_callers"
        case allowedSurfaces = "allowed_surfaces"
        case confirmationRequirement = "confirmation_requirement"
        case expiresAt = "expires_at"
        case destinationBinding = "destination_binding"
        case createdAt = "created_at"
        case updatedAt = "updated_at"
    }

    init(
        schemaIdentifier: String = HealthContextProfileSchema.identifier,
        schemaVersion: Int = HealthContextProfileSchema.version,
        id: UUID = UUID(),
        revision: HealthContextProfileRevision = .init(1),
        name: String,
        metricScope: HealthContextMetricScope,
        dataSourceScope: HealthContextDataSourceScope,
        detailLevel: HealthContextDetailLevel,
        datePolicy: HealthContextDatePolicy,
        allowedCallers: [HealthContextCaller],
        allowedSurfaces: [HealthContextSurface],
        confirmationRequirement: HealthContextConfirmationRequirement = .notRequired,
        expiresAt: Date? = nil,
        destinationBinding: HealthContextDestinationBinding = .any,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.schemaIdentifier = schemaIdentifier
        self.schemaVersion = schemaVersion
        self.id = id
        self.revision = revision
        self.name = name
        self.metricScope = metricScope
        self.dataSourceScope = dataSourceScope
        self.detailLevel = detailLevel
        self.datePolicy = datePolicy
        self.allowedCallers = allowedCallers
        self.allowedSurfaces = allowedSurfaces
        self.confirmationRequirement = confirmationRequirement
        self.expiresAt = expiresAt
        self.destinationBinding = destinationBinding
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }

    func validate() throws {
        guard schemaIdentifier == HealthContextProfileSchema.identifier else {
            throw HealthContextProfileValidationError.unsupportedSchemaIdentifier
        }
        guard schemaVersion == HealthContextProfileSchema.version else {
            throw HealthContextProfileValidationError.unsupportedSchemaVersion
        }
        guard revision.rawValue > 0 else {
            throw HealthContextProfileValidationError.invalidRevision
        }
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty, name.utf8.count <= 256 else {
            throw HealthContextProfileValidationError.invalidName
        }
        try Self.validate(metricScope)
        try Self.validate(dataSourceScope)
        guard !allowedCallers.isEmpty else {
            throw HealthContextProfileValidationError.missingCaller
        }
        guard Set(allowedCallers).count == allowedCallers.count else {
            throw HealthContextProfileValidationError.duplicateCaller
        }
        guard allowedCallers.allSatisfy(\.isKnown) else {
            throw HealthContextProfileValidationError.unknownCaller
        }
        guard !allowedSurfaces.isEmpty else {
            throw HealthContextProfileValidationError.missingSurface
        }
        guard Set(allowedSurfaces).count == allowedSurfaces.count else {
            throw HealthContextProfileValidationError.duplicateSurface
        }
        guard allowedSurfaces.allSatisfy(\.isKnown) else {
            throw HealthContextProfileValidationError.unknownSurface
        }
        try Self.validate(datePolicy)
        guard createdAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt.timeIntervalSinceReferenceDate.isFinite,
              updatedAt >= createdAt else {
            throw HealthContextProfileValidationError.invalidTimestamps
        }
        if let expiresAt {
            guard expiresAt.timeIntervalSinceReferenceDate.isFinite,
                  expiresAt > createdAt else {
                throw HealthContextProfileValidationError.invalidExpiration
            }
        }
        if case .exact(let destinationID) = destinationBinding {
            guard Self.isValidIdentifier(destinationID) else {
                throw HealthContextProfileValidationError.invalidDestination
            }
        }
    }

    /// SHA-256 over execution-affecting policy only. Display metadata, profile
    /// identity, timestamps, and revision are pinned separately and do not alter
    /// this digest. Every set-like array is sorted before sorted-key JSON encoding.
    func policyDigest() throws -> String {
        let payload = CanonicalPolicy(
            schemaIdentifier: schemaIdentifier,
            schemaVersion: schemaVersion,
            metricScope: metricScope.canonicalized,
            dataSourceScope: dataSourceScope.canonicalized,
            detailLevel: detailLevel,
            datePolicy: datePolicy,
            allowedCallers: allowedCallers.sorted { $0.rawValue < $1.rawValue },
            allowedSurfaces: allowedSurfaces.sorted { $0.rawValue < $1.rawValue },
            confirmationRequirement: confirmationRequirement,
            expiresAt: expiresAt,
            destinationBinding: destinationBinding
        )
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .millisecondsSince1970
        let data = try encoder.encode(payload)
        return SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    func reference() throws -> HealthContextProfileReference {
        try validate()
        return HealthContextProfileReference(
            schemaIdentifier: schemaIdentifier,
            schemaVersion: schemaVersion,
            profileID: id,
            revision: revision,
            policyDigest: try policyDigest()
        )
    }

    private static func validate(_ scope: HealthContextMetricScope) throws {
        guard case .selected(let identifiers) = scope else { return }
        guard !identifiers.isEmpty else {
            throw HealthContextProfileValidationError.emptyMetricSelection
        }
        guard identifiers.allSatisfy(isValidIdentifier) else {
            throw HealthContextProfileValidationError.invalidMetricIdentifier
        }
        guard Set(identifiers).count == identifiers.count else {
            throw HealthContextProfileValidationError.duplicateMetricIdentifier
        }
    }

    private static func validate(_ scope: HealthContextDataSourceScope) throws {
        guard case .selected(let identifiers) = scope else { return }
        guard !identifiers.isEmpty else {
            throw HealthContextProfileValidationError.emptyDataSourceSelection
        }
        guard identifiers.allSatisfy(isValidIdentifier) else {
            throw HealthContextProfileValidationError.invalidDataSourceIdentifier
        }
        guard Set(identifiers).count == identifiers.count else {
            throw HealthContextProfileValidationError.duplicateDataSourceIdentifier
        }
    }

    private static func validate(_ policy: HealthContextDatePolicy) throws {
        switch policy {
        case .allHistory, .callerProvided:
            return
        case .explicit(let range):
            guard range.start.timeIntervalSinceReferenceDate.isFinite,
                  range.end.timeIntervalSinceReferenceDate.isFinite,
                  range.start <= range.end else {
                throw HealthContextProfileValidationError.invalidDatePolicy
            }
        case .relative(let duration):
            guard duration.isFinite, duration > 0 else {
                throw HealthContextProfileValidationError.invalidDatePolicy
            }
        }
    }

    private static func isValidIdentifier(_ identifier: String) -> Bool {
        let trimmed = identifier.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && trimmed == identifier && identifier.utf8.count <= 1_024
    }

    private struct CanonicalPolicy: Codable {
        let schemaIdentifier: String
        let schemaVersion: Int
        let metricScope: HealthContextMetricScope
        let dataSourceScope: HealthContextDataSourceScope
        let detailLevel: HealthContextDetailLevel
        let datePolicy: HealthContextDatePolicy
        let allowedCallers: [HealthContextCaller]
        let allowedSurfaces: [HealthContextSurface]
        let confirmationRequirement: HealthContextConfirmationRequirement
        let expiresAt: Date?
        let destinationBinding: HealthContextDestinationBinding
    }
}

nonisolated struct HealthContextProfileReference: Codable, Equatable, Sendable {
    let schemaIdentifier: String
    let schemaVersion: Int
    let profileID: UUID
    let revision: HealthContextProfileRevision
    let policyDigest: String

    enum CodingKeys: String, CodingKey {
        case schemaIdentifier = "schema"
        case schemaVersion = "schema_version"
        case profileID = "profile_id"
        case revision
        case policyDigest = "policy_digest"
    }

    init(
        schemaIdentifier: String = HealthContextProfileSchema.identifier,
        schemaVersion: Int = HealthContextProfileSchema.version,
        profileID: UUID,
        revision: HealthContextProfileRevision,
        policyDigest: String
    ) {
        self.schemaIdentifier = schemaIdentifier
        self.schemaVersion = schemaVersion
        self.profileID = profileID
        self.revision = revision
        self.policyDigest = policyDigest
    }
}

nonisolated enum HealthContextProfileValidationError: String, Error, Codable, Equatable, LocalizedError, Sendable {
    case unsupportedSchemaIdentifier = "unsupported_schema_identifier"
    case unsupportedSchemaVersion = "unsupported_schema_version"
    case invalidRevision = "invalid_revision"
    case invalidName = "invalid_name"
    case emptyMetricSelection = "empty_metric_selection"
    case invalidMetricIdentifier = "invalid_metric_identifier"
    case duplicateMetricIdentifier = "duplicate_metric_identifier"
    case emptyDataSourceSelection = "empty_data_source_selection"
    case invalidDataSourceIdentifier = "invalid_data_source_identifier"
    case duplicateDataSourceIdentifier = "duplicate_data_source_identifier"
    case missingCaller = "missing_caller"
    case duplicateCaller = "duplicate_caller"
    case unknownCaller = "unknown_caller"
    case missingSurface = "missing_surface"
    case duplicateSurface = "duplicate_surface"
    case unknownSurface = "unknown_surface"
    case invalidDatePolicy = "invalid_date_policy"
    case invalidExpiration = "invalid_expiration"
    case invalidDestination = "invalid_destination"
    case invalidTimestamps = "invalid_timestamps"

    var errorDescription: String? { rawValue }
}

private extension HealthContextMetricScope {
    nonisolated var canonicalized: Self {
        switch self {
        case .allAvailable:
            return .allAvailable
        case .selected(let metricIDs):
            return .selected(metricIDs: metricIDs.sorted())
        }
    }
}

private extension HealthContextDataSourceScope {
    nonisolated var canonicalized: Self {
        switch self {
        case .allAvailable:
            return .allAvailable
        case .selected(let sourceIDs):
            return .selected(sourceIDs: sourceIDs.sorted())
        }
    }
}

// MARK: - Stable tagged Codable representations

extension HealthContextMetricScope: Codable {
    private enum CodingKeys: String, CodingKey { case kind, metricIDs }
    private enum Kind: String, Codable { case allAvailable = "all_available", selected }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .allAvailable:
            self = .allAvailable
        case .selected:
            self = .selected(metricIDs: try container.decode([String].self, forKey: .metricIDs))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allAvailable:
            try container.encode(Kind.allAvailable, forKey: .kind)
        case .selected(let metricIDs):
            try container.encode(Kind.selected, forKey: .kind)
            try container.encode(metricIDs, forKey: .metricIDs)
        }
    }
}

extension HealthContextDataSourceScope: Codable {
    private enum CodingKeys: String, CodingKey { case kind, sourceIDs }
    private enum Kind: String, Codable { case allAvailable = "all_available", selected }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .allAvailable:
            self = .allAvailable
        case .selected:
            self = .selected(sourceIDs: try container.decode([String].self, forKey: .sourceIDs))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allAvailable:
            try container.encode(Kind.allAvailable, forKey: .kind)
        case .selected(let sourceIDs):
            try container.encode(Kind.selected, forKey: .kind)
            try container.encode(sourceIDs, forKey: .sourceIDs)
        }
    }
}

extension HealthContextDatePolicy: Codable {
    private enum CodingKeys: String, CodingKey { case kind, range, duration }
    private enum Kind: String, Codable {
        case allHistory = "all_history"
        case explicit
        case callerProvided = "caller_provided"
        case relative
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .allHistory:
            self = .allHistory
        case .explicit:
            self = .explicit(try container.decode(HealthContextBoundedDateRange.self, forKey: .range))
        case .callerProvided:
            self = .callerProvided
        case .relative:
            self = .relative(duration: try container.decode(TimeInterval.self, forKey: .duration))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .allHistory:
            try container.encode(Kind.allHistory, forKey: .kind)
        case .explicit(let range):
            try container.encode(Kind.explicit, forKey: .kind)
            try container.encode(range, forKey: .range)
        case .callerProvided:
            try container.encode(Kind.callerProvided, forKey: .kind)
        case .relative(let duration):
            try container.encode(Kind.relative, forKey: .kind)
            try container.encode(duration, forKey: .duration)
        }
    }
}

extension HealthContextDestinationBinding: Codable {
    private enum CodingKeys: String, CodingKey { case kind, destinationID }
    private enum Kind: String, Codable { case any, exact }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        switch try container.decode(Kind.self, forKey: .kind) {
        case .any:
            self = .any
        case .exact:
            self = .exact(destinationID: try container.decode(String.self, forKey: .destinationID))
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        switch self {
        case .any:
            try container.encode(Kind.any, forKey: .kind)
        case .exact(let destinationID):
            try container.encode(Kind.exact, forKey: .kind)
            try container.encode(destinationID, forKey: .destinationID)
        }
    }
}
