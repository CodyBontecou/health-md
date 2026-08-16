import Foundation
import HealthMdCoreRust

/// Profile-scoped renderer authority. Runtime rollout configuration uses the tolerant
/// `persistedValue` initializer, while Codable remains strict because an engine value inside a
/// present durable pin is an immutable nonlegacy promise and must never downgrade silently.
nonisolated enum ExportEngineMode: String, CaseIterable, Codable, Sendable {
    case legacy
    case shadow
    case rust

    init(persistedValue: String?) {
        self = persistedValue.flatMap(Self.init(rawValue:)) ?? .legacy
    }
}

/// Immutable provenance required to resume an Apple export with the exact renderer contract that
/// planned it. The pin contains no health values, dates, destination paths, or credentials.
nonisolated struct AppleExportEnginePin: Codable, Equatable, Sendable {
    static let profileID = "apple_health_data_v8"
    private static let supportedCoreAPIVersion: UInt32 = 4
    private static let supportedRenderInputVersion: UInt32 = 1
    private static let supportedArtifactPlanVersion: UInt32 = 1
    private static let supportedSemanticProfileRevision: UInt32 = 1
    private static let supportedRenderProfileRevision: UInt32 = 1

    let engine: ExportEngineMode
    let profile: String
    let publicSchema: String
    let publicSchemaVersion: UInt32
    let coreAPIVersion: UInt32
    let semanticInputVersion: UInt32
    let canonicalModelVersion: UInt32
    let renderInputVersion: UInt32
    let artifactPlanVersion: UInt32
    let registryVersion: UInt32
    let registrySHA256: String
    let semanticProfileRevision: UInt32
    let renderProfileRevision: UInt32
    let coreSourceRevision: String
    let calendarTimeZoneIdentifier: String

    enum CompatibilityError: String, Error, Equatable, Sendable {
        case invalidCalendarTimeZone
        case invalidProfile
        case incompatiblePublicSchema
        case incompatibleCoreAPI
        case incompatibleSemanticInput
        case incompatibleCanonicalModel
        case incompatibleRenderInput
        case incompatibleArtifactPlan
        case incompatibleRegistry
        case incompatibleSemanticProfile
        case incompatibleRenderProfile
        case incompatibleCoreSource
    }

    /// Creates a pin only from a mutually compatible packaged core and Apple registry snapshot.
    init(
        engine: ExportEngineMode,
        calendarTimeZoneIdentifier: String,
        buildInfo: CoreBuildInfo,
        registrySnapshot: CoreMetricRegistrySnapshot
    ) throws {
        self.engine = engine
        profile = registrySnapshot.profileId
        publicSchema = registrySnapshot.publicSchema
        publicSchemaVersion = registrySnapshot.publicSchemaVersion
        coreAPIVersion = buildInfo.coreApiVersion
        semanticInputVersion = buildInfo.semanticInputVersion
        canonicalModelVersion = buildInfo.canonicalModelVersion
        renderInputVersion = buildInfo.renderInputVersion
        artifactPlanVersion = buildInfo.artifactPlanVersion
        registryVersion = registrySnapshot.registryVersion
        registrySHA256 = registrySnapshot.registrySha256
        semanticProfileRevision = registrySnapshot.profileRevision
        renderProfileRevision = buildInfo.renderProfileRevision
        coreSourceRevision = buildInfo.coreSourceRevision
        self.calendarTimeZoneIdentifier = calendarTimeZoneIdentifier

        try validateCompatibility(buildInfo: buildInfo, registrySnapshot: registrySnapshot)
    }

    /// Validates both the persisted values and agreement between the packaged build and the
    /// adapter-provided registry snapshot. Callers must resolve any failure to legacy authority.
    func validateCompatibility(
        buildInfo: CoreBuildInfo,
        registrySnapshot: CoreMetricRegistrySnapshot
    ) throws {
        guard Self.isIANAIdentifier(calendarTimeZoneIdentifier) else {
            throw CompatibilityError.invalidCalendarTimeZone
        }
        guard profile == Self.profileID,
              registrySnapshot.profileId == Self.profileID,
              registrySnapshot.publicProfileId == "apple-v8" else {
            throw CompatibilityError.invalidProfile
        }
        guard publicSchema == HealthMdExportSchema.identifier,
              publicSchemaVersion == UInt32(HealthMdExportSchema.version),
              registrySnapshot.publicSchema == publicSchema,
              registrySnapshot.publicSchemaVersion == publicSchemaVersion else {
            throw CompatibilityError.incompatiblePublicSchema
        }
        guard coreAPIVersion == Self.supportedCoreAPIVersion,
              coreAPIVersion == buildInfo.coreApiVersion else {
            throw CompatibilityError.incompatibleCoreAPI
        }
        guard semanticInputVersion == HealthMdSemanticInputAdapter.semanticInputVersion,
              semanticInputVersion == buildInfo.semanticInputVersion else {
            throw CompatibilityError.incompatibleSemanticInput
        }
        guard canonicalModelVersion == HealthMdSemanticInputAdapter.canonicalModelVersion,
              canonicalModelVersion == buildInfo.canonicalModelVersion else {
            throw CompatibilityError.incompatibleCanonicalModel
        }
        guard renderInputVersion == Self.supportedRenderInputVersion,
              renderInputVersion == buildInfo.renderInputVersion else {
            throw CompatibilityError.incompatibleRenderInput
        }
        guard artifactPlanVersion == Self.supportedArtifactPlanVersion,
              artifactPlanVersion == buildInfo.artifactPlanVersion else {
            throw CompatibilityError.incompatibleArtifactPlan
        }
        guard registryVersion == HealthMdSemanticInputAdapter.registryVersion,
              registryVersion == buildInfo.registryVersion,
              registryVersion == registrySnapshot.registryVersion,
              Self.isLowercaseSHA256(registrySHA256),
              registrySHA256 == buildInfo.registrySha256,
              registrySHA256 == registrySnapshot.registrySha256 else {
            throw CompatibilityError.incompatibleRegistry
        }
        guard semanticProfileRevision == Self.supportedSemanticProfileRevision,
              semanticProfileRevision == registrySnapshot.profileRevision else {
            throw CompatibilityError.incompatibleSemanticProfile
        }
        guard renderProfileRevision == Self.supportedRenderProfileRevision,
              renderProfileRevision == buildInfo.renderProfileRevision else {
            throw CompatibilityError.incompatibleRenderProfile
        }
        // Source revision is durable provenance, not an equality gate. A rollback release may
        // package a newer compatible core while resuming a job pinned to the same versioned
        // contracts. Behavioral incompatibility must bump one of the version/profile pins above.
        guard !coreSourceRevision.isEmpty,
              coreSourceRevision.utf8.count <= 256,
              !buildInfo.coreSourceRevision.isEmpty,
              buildInfo.coreSourceRevision.utf8.count <= 256 else {
            throw CompatibilityError.incompatibleCoreSource
        }
    }

    func isCompatible(
        buildInfo: CoreBuildInfo,
        registrySnapshot: CoreMetricRegistrySnapshot
    ) -> Bool {
        do {
            try validateCompatibility(buildInfo: buildInfo, registrySnapshot: registrySnapshot)
            return true
        } catch {
            return false
        }
    }

    static func coreIsCompatible(
        buildInfo: CoreBuildInfo,
        registrySnapshot: CoreMetricRegistrySnapshot
    ) -> Bool {
        guard let pin = try? AppleExportEnginePin(
            engine: .legacy,
            calendarTimeZoneIdentifier: "UTC",
            buildInfo: buildInfo,
            registrySnapshot: registrySnapshot
        ) else {
            return false
        }
        return pin.isCompatible(buildInfo: buildInfo, registrySnapshot: registrySnapshot)
    }

    static func isIANAIdentifier(_ value: String) -> Bool {
        value == "UTC" || TimeZone.knownTimeZoneIdentifiers.contains(value)
    }

    static func isLowercaseSHA256(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy {
            (48...57).contains($0) || (97...102).contains($0)
        }
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        engine = try container.decode(ExportEngineMode.self, forKey: .engine)
        guard engine != .legacy else {
            throw DecodingError.dataCorruptedError(
                forKey: .engine,
                in: container,
                debugDescription: "A present export-engine pin must be nonlegacy."
            )
        }
        profile = try container.decode(String.self, forKey: .profile)
        publicSchema = try container.decode(String.self, forKey: .publicSchema)
        publicSchemaVersion = try container.decode(UInt32.self, forKey: .publicSchemaVersion)
        coreAPIVersion = try container.decode(UInt32.self, forKey: .coreAPIVersion)
        semanticInputVersion = try container.decode(UInt32.self, forKey: .semanticInputVersion)
        canonicalModelVersion = try container.decode(UInt32.self, forKey: .canonicalModelVersion)
        renderInputVersion = try container.decode(UInt32.self, forKey: .renderInputVersion)
        artifactPlanVersion = try container.decode(UInt32.self, forKey: .artifactPlanVersion)
        registryVersion = try container.decode(UInt32.self, forKey: .registryVersion)
        registrySHA256 = try container.decode(String.self, forKey: .registrySHA256)
        semanticProfileRevision = try container.decode(UInt32.self, forKey: .semanticProfileRevision)
        renderProfileRevision = try container.decode(UInt32.self, forKey: .renderProfileRevision)
        coreSourceRevision = try container.decode(String.self, forKey: .coreSourceRevision)
        calendarTimeZoneIdentifier = try container.decode(
            String.self,
            forKey: .calendarTimeZoneIdentifier
        )

        guard Self.isBoundedIdentifier(profile, maximumUTF8Count: 128),
              Self.isBoundedIdentifier(publicSchema, maximumUTF8Count: 128),
              publicSchemaVersion > 0,
              coreAPIVersion > 0,
              semanticInputVersion > 0,
              canonicalModelVersion > 0,
              renderInputVersion > 0,
              artifactPlanVersion > 0,
              registryVersion > 0,
              Self.isLowercaseSHA256(registrySHA256),
              semanticProfileRevision > 0,
              renderProfileRevision > 0,
              Self.isBoundedIdentifier(coreSourceRevision, maximumUTF8Count: 256),
              Self.isIANAIdentifier(calendarTimeZoneIdentifier) else {
            throw DecodingError.dataCorruptedError(
                forKey: .engine,
                in: container,
                debugDescription: "Export-engine pin structure is invalid."
            )
        }
    }

    private static func isBoundedIdentifier(
        _ value: String,
        maximumUTF8Count: Int
    ) -> Bool {
        !value.isEmpty
            && value.utf8.count <= maximumUTF8Count
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }

    enum CodingKeys: String, CodingKey {
        case engine
        case profile
        case publicSchema = "public_schema"
        case publicSchemaVersion = "public_schema_version"
        case coreAPIVersion = "core_api_version"
        case semanticInputVersion = "semantic_input_version"
        case canonicalModelVersion = "canonical_model_version"
        case renderInputVersion = "render_input_version"
        case artifactPlanVersion = "artifact_plan_version"
        case registryVersion = "registry_version"
        case registrySHA256 = "registry_sha256"
        case semanticProfileRevision = "semantic_profile_revision"
        case renderProfileRevision = "render_profile_revision"
        case coreSourceRevision = "core_source_revision"
        case calendarTimeZoneIdentifier = "calendar_time_zone"
    }
}
