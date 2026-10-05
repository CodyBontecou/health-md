import Foundation

/// Pure document integrity and cross-field checks only. A successful check does NOT establish
/// issued authority/approval, registry support, current permission, entitlement, or native root safety.
public enum AgentBridgeSemantics {
    public static func capabilityDigest(_ discovery: AgentBridgeDiscovery) throws -> AgentBridgeDigest {
        try digest(discovery.bridgeJSON.removing(["capability_sha256", "request_id", "issued_at", "expires_at"]))
    }
    public static func planDigest(_ plan: AgentBridgePlan) throws -> AgentBridgeDigest {
        try digest(plan.bridgeJSON.removing(["plan_sha256"]))
    }
    public static func scopeDigest(intent: AgentBridgeGeneratedIntent, resolvedDates: AgentBridgeDates, metricIDs: [AgentBridgeID]) throws -> AgentBridgeDigest {
        try digest(.object([("dates", resolvedDates.bridgeJSON), ("calendar_timezone", intent.calendarTimezone.bridgeJSON), ("capture_scope", intent.captureScope.bridgeJSON), ("metric_ids", .values(metricIDs)), ("product", .object([("type", .string("generated_files"))]))]))
    }
    public static func commitKey(_ receipt: AgentBridgeCommitReceipt) throws -> AgentBridgeDigest {
        try digest(receipt.bridgeJSON.removing(["schema", "schema_version", "peer", "status", "commit_key"]))
    }
    public static func binding(_ plan: AgentBridgePlan) -> AgentBridgeBinding {
        .init(authorityReferences: plan.authorityReferences, capabilitySha256: plan.capabilitySha256, destination: plan.intent.destination, expiresAt: plan.expiresAt, peer: plan.intent.peer, planSha256: plan.planSha256, revisions: plan.revisions, scopeSha256: plan.scopeSha256, settingsSha256: plan.settingsSha256)
    }
    static func digest(_ value: BridgeJSON) throws -> AgentBridgeDigest {
        let bytes = try value.canonicalBytes()
        _ = try BridgeJSON.parse(bytes)
        return try AgentBridgeDigest(AgentBridgeV4Codec.sha256(bytes))
    }
    static func duration(issued: AgentBridgeUTC, expires: AgentBridgeUTC) throws {
        guard let start = bridgeInstant(issued.rawValue), let end = bridgeInstant(expires.rawValue), (0...600).contains(end.timeIntervalSince(start)), start < end else { throw AgentBridgeValidationError.planExpired }
    }
    public static func validate(_ value: AgentBridgeDiscovery) throws {
        try duration(issued: value.issuedAt, expires: value.expiresAt)
        guard try capabilityDigest(value) == value.capabilitySha256 else { throw AgentBridgeValidationError.bindingChanged }
        for list in [value.features.map(\.rawValue), value.settingsPolicies.map(\.rawValue), value.outputProfiles.map(\.rawValue), value.queryOperations.map(\.rawValue), value.controlOperations.map(\.rawValue), value.projectionProducts.map(\.rawValue), value.outputSupport.formats.map(\.rawValue), value.outputSupport.writeModes.map(\.rawValue), value.outputSupport.compatibilityDetail.map(\.rawValue), value.outputSupport.nativeArchiveProducts.map(\.rawValue), value.outputSupport.settingPointers, value.outputSupport.pathTokens.map(\.rawValue)] { try bridgeSortedUnique(list) }
        guard value.authorityReferences.allSatisfy({ $0.issuer == .nativeSource }) else { throw AgentBridgeValidationError.invalidRequest }
        try bridgeUnique(value.authorityReferences.map { $0.authorityId.rawValue })
        let hasProjection = !value.projectionProducts.isEmpty
        guard hasProjection == value.features.contains(.sourceProjection) else { throw AgentBridgeValidationError.invalidRequest }
        if hasProjection {
            // Catalog grammar can be carried, but this lane has no reviewed projection-catalog pin
            // or projection producer. Do not accept an advertised projection capability as usable.
            throw AgentBridgeValidationError.unsupportedCapability
        }
        guard value.projectionCatalogSha256.rawValue == String(repeating: "0", count: 64), value.projectionSourceCatalog == nil else { throw AgentBridgeValidationError.invalidRequest }
    }
    public static func validate(_ value: AgentBridgeAuthorityReferences) throws {
        guard value.native.issuer == .nativeSource, value.host.issuer == .authorizedHost, value.native.authorityId != value.host.authorityId else { throw AgentBridgeValidationError.invalidRequest }
    }
    public static func validate(_ value: AgentBridgeAuthority) throws {
        if let scope = value.controlReadScope {
            guard value.scopeSha256 == (try digest(scope.bridgeJSON)) else { throw AgentBridgeValidationError.bindingChanged }
            try bridgeUnique(scope.objects.map { $0.domain.rawValue + "/" + $0.objectId.rawValue })
        }
    }
    public static func validate(_ value: AgentBridgeApproval) throws {
        guard value.authorityId == value.binding.authorityReferences.native.authorityId,
              value.approvedAt.rawValue <= value.binding.expiresAt.rawValue else { throw AgentBridgeValidationError.bindingChanged }
    }
    public static func validate(_ value: AgentBridgePlan) throws {
        let intent = value.intent
        let selection = intent.captureScope.selection
        // Resolution against the shared registry, categories and all-metric expansion is not
        // implemented here. Fail closed instead of interpreting IDs using a guessed mapping.
        guard !selection.allMetrics, selection.categoryIDs.isEmpty, !selection.metricIDs.isEmpty else { throw AgentBridgeValidationError.unsupportedCapability }
        try bridgeSortedUnique(value.resolvedMetricIds.map(\.rawValue))
        guard value.resolvedMetricIds == selection.metricIDs, value.resolvedDates == (try intent.dates.resolved()),
              value.settingsSha256 == (try digest(value.effectiveSettings.bridgeJSON)),
              value.scopeSha256 == (try scopeDigest(intent: intent, resolvedDates: value.resolvedDates, metricIDs: value.resolvedMetricIds)),
              value.planSha256 == (try planDigest(value)) else { throw AgentBridgeValidationError.bindingChanged }
        try duration(issued: value.issuedAt, expires: value.expiresAt)
        let settings = value.effectiveSettings
        guard (settings.outputProfile == .appleV8) == (intent.peer.platform == .apple) else { throw AgentBridgeValidationError.unsupportedCapability }
        if settings.individualEntries.enabled {
            guard !settings.individualEntries.metricIDs.isEmpty, Set(settings.individualEntries.metricIDs).isSubset(of: Set(value.resolvedMetricIds)) else { throw AgentBridgeValidationError.bindingChanged }
            guard intent.captureScope.nativeArchive != .none else { throw AgentBridgeValidationError.unsupportedCapability }
        }
        guard value.predictedPaths.map(\.rawValue) == (try AgentBridgePaths.predictedPaths(dates: intent.dates, settings: settings)) else { throw AgentBridgeValidationError.bindingChanged }
        switch value.resolvedDates {
        case .allAvailable:
            guard value.pathPrediction == .templateOnlyAllAvailable, value.limitations.contains(where: { $0.rawValue == "history_bounds_unresolved" }) else { throw AgentBridgeValidationError.bindingChanged }
        default:
            if settings.individualEntries.enabled {
                guard value.pathPrediction == .deferredNativeEntries, value.limitations.contains(where: { $0.rawValue == "entry_paths_unresolved" }) else { throw AgentBridgeValidationError.bindingChanged }
            } else if value.pathPrediction != .exactRequestedDays { throw AgentBridgeValidationError.bindingChanged }
        }
        let origin: String
        let revision: Int64
        switch intent.settingsPolicy {
        case .explicit(let explicit):
            guard try explicit.bridgeJSON.canonicalBytes() == settings.bridgeJSON.canonicalBytes() else { throw AgentBridgeValidationError.bindingChanged }
            origin = "request"; revision = 0
        case .savedDeviceSettings(let expected):
            let pins = value.revisions.filter { $0.domain == .deviceSettings }
            guard pins.count == 1, pins[0].revision == expected else { throw AgentBridgeValidationError.revisionConflict }
            origin = "saved_device_settings"; revision = expected
        case .profile(let profileID, let expected):
            let pins = value.revisions.filter { $0.domain == .nativeProfile }
            guard pins.count == 1, pins[0].revision == expected, pins[0].objectId == profileID else { throw AgentBridgeValidationError.revisionConflict }
            origin = "profile"; revision = expected
        }
        try bridgeUnique(value.revisions.map { $0.domain.rawValue + "/" + $0.objectId.rawValue })
        let expected = Set(leaves(settings.bridgeJSON, "/effective_settings") + leaves(intent.captureScope.bridgeJSON, "/capture_scope") + ["/resolved_dates", "/calendar_timezone"])
        try bridgeUnique(value.origins.map(\.pointer))
        guard Set(value.origins.map(\.pointer)) == expected else { throw AgentBridgeValidationError.invalidRequest }
        for item in value.origins {
            let wanted = item.pointer.hasPrefix("/effective_settings/") ? origin : item.pointer == "/resolved_dates" ? "resolved_calendar" : "request"
            guard item.origin.rawValue == wanted else { throw AgentBridgeValidationError.bindingChanged }
            if wanted == "saved_device_settings" || wanted == "profile" {
                guard item.revision == revision else { throw AgentBridgeValidationError.revisionConflict }
            } else if item.revision != 0 { throw AgentBridgeValidationError.bindingChanged }
        }
    }
    public static func validate(_ value: AgentBridgeExecute) throws {
        guard value.approval.binding == binding(value.plan), value.approval.approvedAt.rawValue >= value.plan.issuedAt.rawValue else { throw AgentBridgeValidationError.bindingChanged }
    }
    public static func validate(_ value: AgentBridgeExecutionReceipt) throws {
        if [.complete, .completeEmpty, .cancelled].contains(value.status), !value.sourceAcknowledged { throw AgentBridgeValidationError.invalidRequest }
        if value.status == .completeEmpty, value.artifactCount != 0 { throw AgentBridgeValidationError.invalidRequest }
    }
    public static func validate(_ value: AgentBridgeResume) throws {
        guard value.peer == value.binding.peer, value.destination == value.binding.destination else { throw AgentBridgeValidationError.bindingChanged }
    }
    /// Caller must load journalResume from a trusted local journal, not the incoming request.
    public static func validateResume(_ value: AgentBridgeResume, journalResume: AgentBridgeResume) throws {
        guard try value.bridgeJSON.canonicalBytes() == journalResume.bridgeJSON.canonicalBytes() else { throw AgentBridgeValidationError.bindingChanged }
    }
    public static func validate(_ value: AgentBridgeArtifactManifest) throws {
        try AgentBridgePaths.validateCollisions(value.artifacts.map { $0.relativePath.rawValue })
        try bridgeUnique(value.artifacts.map { $0.artifactId.rawValue })
        try bridgeUnique(value.branchStatuses.map { $0.selectorId.rawValue })
        if [.complete, .completeEmpty].contains(value.captureStatus), value.branchStatuses.contains(where: { $0.status != .success }) { throw AgentBridgeValidationError.invalidRequest }
        if value.captureStatus == .completeEmpty, !value.artifacts.isEmpty { throw AgentBridgeValidationError.invalidRequest }
    }
    public static func validate(_ value: AgentBridgeCommitReceipt) throws {
        guard value.destination.hostInstallationID == value.peer.hostInstallationID, !value.relativePath.rawValue.isEmpty,
              value.commitKey == (try commitKey(value)) else { throw AgentBridgeValidationError.bindingChanged }
    }
    /// Pure replay identity comparison; not evidence that an append/merge was durably performed.
    public static func validateCommitReplay(_ value: AgentBridgeCommitReceipt, persisted: AgentBridgeCommitReceipt) throws {
        guard value.commitKey == persisted.commitKey, value.peer == persisted.peer,
              try value.bridgeJSON.removing(["status"]).canonicalBytes() == persisted.bridgeJSON.removing(["status"]).canonicalBytes() else { throw AgentBridgeValidationError.bindingChanged }
    }
    static func leaves(_ value: BridgeJSON, _ prefix: String) -> [String] {
        guard case .object(let members) = value else { return [prefix] }
        return members.flatMap { leaves($0.value, prefix + "/" + $0.key) }
    }
}
