import Foundation

// Closed declarations derived from the v1 schemas; runtime authority/registry gates are separate.
// No public generic JSON fields. AgentBridgeV4Codec remains the strict raw-byte boundary.

public enum AgentBridgeErrorCode: String, Codable, Sendable {
    case invalidRequest = "invalid_request"
    case unsupportedCapability = "unsupported_capability"
    case unsupportedMetric = "unsupported_metric"
    case permissionRequired = "permission_required"
    case historyUnverified = "history_unverified"
    case configurationProtected = "configuration_protected"
    case entitlementRequired = "entitlement_required"
    case nativeRebindRequired = "native_rebind_required"
    case revisionConflict = "revision_conflict"
    case approvalRequired = "approval_required"
    case bindingChanged = "binding_changed"
    case planExpired = "plan_expired"
    case unsafePath = "unsafe_path"
    case pathCollision = "path_collision"
    case queryBudgetExceeded = "query_budget_exceeded"
    case cursorInvalid = "cursor_invalid"
    case snapshotExpired = "snapshot_expired"
    case busy = "busy"
    case cancelled = "cancelled"
    case spoolMissingRestartRequired = "spool_missing_restart_required"
    case jobExpired = "job_expired"
}

public enum AgentBridgeDiscoveryConfigurationProtection: String, Codable, Sendable {
    case locked = "locked"
    case unlockedNative = "unlocked_native"
}

public enum AgentBridgeDiscoveryControlOperations: String, Codable, Sendable {
    case localRecipeList = "local_recipe.list"
    case localRecipeGet = "local_recipe.get"
    case localRecipeCreate = "local_recipe.create"
    case localRecipeUpdate = "local_recipe.update"
    case localRecipeDelete = "local_recipe.delete"
    case localRecipeRun = "local_recipe.run"
    case localRecipePlan = "local_recipe.plan"
    case nativeProfileList = "native_profile.list"
    case nativeProfileGet = "native_profile.get"
    case nativeProfileCreate = "native_profile.create"
    case nativeProfileUpdate = "native_profile.update"
    case nativeProfileActivate = "native_profile.activate"
    case nativeProfileDelete = "native_profile.delete"
    case nativeProfilePlan = "native_profile.plan"
    case hostScheduleList = "host_schedule.list"
    case hostScheduleGet = "host_schedule.get"
    case hostScheduleCreate = "host_schedule.create"
    case hostScheduleUpdate = "host_schedule.update"
    case hostSchedulePause = "host_schedule.pause"
    case hostScheduleDelete = "host_schedule.delete"
    case hostScheduleRunNow = "host_schedule.run_now"
    case hostSchedulePlan = "host_schedule.plan"
    case nativeScheduleInspect = "native_schedule.inspect"
    case nativeScheduleUpdate = "native_schedule.update"
    case nativeScheduleEnable = "native_schedule.enable"
    case nativeScheduleDisable = "native_schedule.disable"
    case nativeScheduleInspectPending = "native_schedule.inspect_pending"
    case nativeScheduleDiscardPending = "native_schedule.discard_pending"
    case nativeSchedulePlan = "native_schedule.plan"
    case nativeDestinationInspect = "native_destination.inspect"
    case nativeDestinationUpdate = "native_destination.update"
    case nativeDestinationPlan = "native_destination.plan"
}

public enum AgentBridgeDiscoveryEntitlement: String, Codable, Sendable {
    case satisfied = "satisfied"
    case required = "required"
}

public enum AgentBridgeDiscoveryFeatures: String, Codable, Sendable {
    case explicitSettings = "explicit_settings"
    case zeroHealthPlan = "zero_health_plan"
    case boundExecution = "bound_execution"
    case sourceQuery = "source_query"
    case sourceProjection = "source_projection"
    case nativeProfileControl = "native_profile_control"
    case nativeScheduleControl = "native_schedule_control"
    case nativeDestinationControl = "native_destination_control"
    case controlPlan = "control_plan"
    case zip = "zip"
    case profileDictionary = "profile_dictionary"
}

public enum AgentBridgeDiscoveryLifecycle: String, Codable, Sendable {
    case iphoneForegroundProtectedData = "iphone_foreground_protected_data"
    case androidUserStartedServiceAfterFirstUnlock = "android_user_started_service_after_first_unlock"
}

public enum AgentBridgeDiscoveryNativeGrants: String, Codable, Sendable {
    case satisfied = "satisfied"
    case required = "required"
    case unverified = "unverified"
}

public enum AgentBridgeDiscoveryOutputProfiles: String, Codable, Sendable {
    case appleV8 = "apple-v8"
    case androidFrozenV4 = "android-frozen-v4"
    case androidAnalyticalV5 = "android-analytical-v5"
}

public enum AgentBridgeDiscoveryProjectionProducts: String, Codable, Sendable {
    case androidSourceProjectionV1 = "android_source_projection_v1"
}

public enum AgentBridgeDiscoveryRequiredActions: String, Codable, Sendable {
    case openMobileApp = "open_mobile_app"
    case unlockMobile = "unlock_mobile"
    case grantHealthAccess = "grant_health_access"
    case grantHistoryAccess = "grant_history_access"
    case nativeConfigurationUnlock = "native_configuration_unlock"
    case nativeDestinationRebind = "native_destination_rebind"
    case purchaseRequired = "purchase_required"
}

public enum AgentBridgeDiscoverySettingsPolicies: String, Codable, Sendable {
    case explicit = "explicit"
    case savedDeviceSettings = "saved_device_settings"
    case profile = "profile"
}

public enum AgentBridgeAuthorityConfigurationProtection: String, Codable, Sendable {
    case notApplicable = "not_applicable"
    case unlockedNative = "unlocked_native"
    case locked = "locked"
}

public enum AgentBridgeAuthorityEntitlement: String, Codable, Sendable {
    case satisfied = "satisfied"
    case required = "required"
}

public enum AgentBridgeAuthorityIssuer: String, Codable, Sendable {
    case nativeSource = "native_source"
    case authorizedHost = "authorized_host"
}

public enum AgentBridgeAuthorityNativeConsent: String, Codable, Sendable {
    case satisfied = "satisfied"
    case required = "required"
}

public enum AgentBridgeAuthorityRights: String, Codable, Sendable {
    case discover = "discover"
    case plan = "plan"
    case querySummary = "query_summary"
    case queryEvidence = "query_evidence"
    case exportExecute = "export_execute"
    case recipeRead = "recipe_read"
    case recipeMutate = "recipe_mutate"
    case recipeRun = "recipe_run"
    case nativeConfigurationRead = "native_configuration_read"
    case nativeConfigurationMutate = "native_configuration_mutate"
    case hostScheduleRead = "host_schedule_read"
    case hostScheduleMutate = "host_schedule_mutate"
    case hostScheduleRun = "host_schedule_run"
    case nativeScheduleMutate = "native_schedule_mutate"
}

public enum AgentBridgeAuthorityReferenceIssuer: String, Codable, Sendable {
    case nativeSource = "native_source"
    case authorizedHost = "authorized_host"
}

public enum AgentBridgeApprovalRights: String, Codable, Sendable {
    case exportExecute = "export_execute"
}

public enum AgentBridgePlanPathPrediction: String, Codable, Sendable {
    case exactRequestedDays = "exact_requested_days"
    case templateOnlyAllAvailable = "template_only_all_available"
    case deferredNativeEntries = "deferred_native_entries"
}

public enum AgentBridgeExecutionReceiptStatus: String, Codable, Sendable {
    case accepted = "accepted"
    case paused = "paused"
    case complete = "complete"
    case completeEmpty = "complete_empty"
    case partial = "partial"
    case failed = "failed"
    case cancellationPending = "cancellation_pending"
    case cancelled = "cancelled"
    case expired = "expired"
}

public enum AgentBridgeArtifactManifestCaptureStatus: String, Codable, Sendable {
    case complete = "complete"
    case completeEmpty = "complete_empty"
    case partial = "partial"
    case failed = "failed"
    case cancelled = "cancelled"
}

public enum AgentBridgeCommitReceiptStatus: String, Codable, Sendable {
    case committed = "committed"
    case alreadyCommitted = "already_committed"
    case conflict = "conflict"
}

public enum AgentBridgeCommitReceiptWriteMode: String, Codable, Sendable {
    case overwrite = "overwrite"
    case append = "append"
    case mergeMarkdown = "merge_markdown"
    case mergeMarkdownPreservingPreamble = "merge_markdown_preserving_preamble"
}

public enum AgentBridgeOutputSupportCompatibilityDetail: String, Codable, Sendable {
    case summary = "summary"
    case selectedTimeSeries = "selected_time_series"
}

public enum AgentBridgeOutputSupportFormats: String, Codable, Sendable {
    case csv = "csv"
    case json = "json"
    case markdown = "markdown"
    case obsidianBases = "obsidian_bases"
}

public enum AgentBridgeOutputSupportNativeArchiveProducts: String, Codable, Sendable {
    case none = "none"
    case appleHealthkitCanonicalV1 = "apple_healthkit_canonical_v1"
    case androidProviderNativeSnapshotV1 = "android_provider_native_snapshot_v1"
}

public enum AgentBridgeOutputSupportPathTokens: String, Codable, Sendable {
    case year = "year"
    case month = "month"
    case day = "day"
    case date = "date"
    case metric = "metric"
    case category = "category"
    case recordId = "record_id"
}

public enum AgentBridgeOutputSupportWriteModes: String, Codable, Sendable {
    case overwrite = "overwrite"
    case append = "append"
    case mergeMarkdown = "merge_markdown"
    case mergeMarkdownPreservingPreamble = "merge_markdown_preserving_preamble"
}

public enum AgentBridgeQueryCatalogProviderAvailability: String, Codable, Sendable {
    case available = "available"
    case unavailable = "unavailable"
    case updateRequired = "update_required"
    case unverified = "unverified"
}

public enum AgentBridgeQueryCatalogSourceId: String, Codable, Sendable {
    case appleHealth = "apple_health"
    case healthConnect = "health_connect"
    case providerNative = "provider_native"
}

public enum AgentBridgeControlReadScopeCreateDomains: String, Codable, Sendable {
    case localRecipe = "local_recipe"
    case nativeProfile = "native_profile"
    case hostSchedule = "host_schedule"
}

public enum AgentBridgeControlReadScopeListDomains: String, Codable, Sendable {
    case localRecipe = "local_recipe"
    case nativeProfile = "native_profile"
    case hostSchedule = "host_schedule"
    case nativeSchedule = "native_schedule"
    case nativeDestination = "native_destination"
}

public enum AgentBridgeOriginOrigin: String, Codable, Sendable {
    case request = "request"
    case savedDeviceSettings = "saved_device_settings"
    case profile = "profile"
    case resolvedCalendar = "resolved_calendar"
    case catalog = "catalog"
}

public enum AgentBridgeRevisionDomain: String, Codable, Sendable {
    case deviceSettings = "device_settings"
    case nativeProfile = "native_profile"
    case localRecipe = "local_recipe"
    case hostSchedule = "host_schedule"
    case nativeSchedule = "native_schedule"
    case nativeDestination = "native_destination"
    case nativeCredentialReference = "native_credential_reference"
}

public enum AgentBridgeArtifactMediaType: String, Codable, Sendable {
    case applicationJson = "application/json"
    case applicationXNdjson = "application/x-ndjson"
    case textCsv = "text/csv"
    case textMarkdown = "text/markdown"
    case applicationZip = "application/zip"
}

public enum AgentBridgeArtifactProfile: String, Codable, Sendable {
    case appleV8 = "apple-v8"
    case androidFrozenV4 = "android-frozen-v4"
    case androidAnalyticalV5 = "android-analytical-v5"
    case appleHealthkitCanonicalV1 = "apple-healthkit-canonical-v1"
    case androidProviderNativeSnapshotV1 = "android-provider-native-snapshot-v1"
    case profileDictionaryV1 = "profile-dictionary-v1"
    case zipContainerV1 = "zip-container-v1"
}

public enum AgentBridgeArtifactWriteMode: String, Codable, Sendable {
    case overwrite = "overwrite"
    case append = "append"
    case mergeMarkdown = "merge_markdown"
    case mergeMarkdownPreservingPreamble = "merge_markdown_preserving_preamble"
}

public enum AgentBridgeArtifactManifestBranchStatusesStatus: String, Codable, Sendable {
    case success = "success"
    case unsupported = "unsupported"
    case skipped = "skipped"
    case failure = "failure"
    case cancelled = "cancelled"
}

public enum AgentBridgeQueryCatalogFeatureStatusesStatus: String, Codable, Sendable {
    case available = "available"
    case unavailable = "unavailable"
    case error = "error"
    case unverified = "unverified"
}

public enum AgentBridgeCoverageStatus: String, Codable, Sendable {
    case complete = "complete"
    case completeEmpty = "complete_empty"
    case partial = "partial"
    case unavailable = "unavailable"
    case failed = "failed"
    case cancelled = "cancelled"
}

public enum AgentBridgeCatalogItemAvailability: String, Codable, Sendable {
    case planned = "planned"
    case unavailable = "unavailable"
    case supported = "supported"
    case permissionRequired = "permission_required"
    case featureUnavailable = "feature_unavailable"
    case historyUnverified = "history_unverified"
}

public enum AgentBridgeCatalogItemOwnerRule: String, Codable, Sendable {
    case civilDayAggregate = "civil_day_aggregate"
    case sourceStartCivilDay = "source_start_civil_day"
    case noonToNoonAdditiveNative = "noon_to_noon_additive_native"
    case sourceStartNoonJournal = "source_start_noon_journal"
}

public enum AgentBridgeCatalogItemRegistryEquivalence: String, Codable, Sendable {
    case platformExactOrUnavailable = "platform_exact_or_unavailable"
    case mappedAlias = "mapped_alias"
    case platformDistinct = "platform_distinct"
}

public enum AgentBridgeCatalogItemStatistics: String, Codable, Sendable {
    case sum = "sum"
    case average = "average"
    case minimum = "minimum"
    case maximum = "maximum"
    case latest = "latest"
    case count = "count"
    case durationSum = "duration_sum"
}

public enum AgentBridgeControlReadScopeObjectsDomain: String, Codable, Sendable {
    case localRecipe = "local_recipe"
    case nativeProfile = "native_profile"
    case hostSchedule = "host_schedule"
    case nativeSchedule = "native_schedule"
    case nativeDestination = "native_destination"
}

public enum AgentBridgeCoverageHistoryFeatureStatus: String, Codable, Sendable {
    case available = "available"
    case unavailable = "unavailable"
    case error = "error"
    case notApplicable = "not_applicable"
}

public enum AgentBridgeCoverageHistoryState: String, Codable, Sendable {
    case fullGranted = "full_granted"
    case bounded = "bounded"
    case unverified = "unverified"
    case notApplicable = "not_applicable"
}

public enum AgentBridgeCoverageMissingReason: String, Codable, Sendable {
    case noRecords = "no_records"
    case unsupported = "unsupported"
    case permissionRequired = "permission_required"
    case historyLimited = "history_limited"
    case historyUnverified = "history_unverified"
    case failure = "failure"
    case skipped = "skipped"
    case cancelled = "cancelled"
}

public enum AgentBridgePathRule: AgentBridgeTextRule {
    public static func validate(_ value: String) throws {
        try AgentBridgePaths.validate(value)
        guard (0...4096).contains(value.unicodeScalars.count) else { throw AgentBridgeValidationError.invalidRequest }
    }
}
public typealias AgentBridgePath = AgentBridgeText<AgentBridgePathRule>

public struct AgentBridgePlanRequest: Codable, Equatable, Sendable, BridgeValueCodable {
    public let authorityId: AgentBridgeUUID
    public let authorityRevision: Int64
    public let capabilitySha256: AgentBridgeDigest
    public let hostAuthorityReference: AgentBridgeAuthorityReference
    public let intent: AgentBridgeGeneratedIntent
    public let requestId: AgentBridgeUUID
    public init(authorityId: AgentBridgeUUID, authorityRevision: Int64, capabilitySha256: AgentBridgeDigest, hostAuthorityReference: AgentBridgeAuthorityReference, intent: AgentBridgeGeneratedIntent, requestId: AgentBridgeUUID) {
        self.authorityId = authorityId
        self.authorityRevision = authorityRevision
        self.capabilitySha256 = capabilitySha256
        self.hostAuthorityReference = hostAuthorityReference
        self.intent = intent
        self.requestId = requestId
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "request_id", "intent", "authority_id", "authority_revision", "host_authority_reference", "capability_sha256"], optional: [])
        authorityId = try o.value("authority_id")
        authorityRevision = try o.int("authority_revision", min: 1, max: 2147483647)
        capabilitySha256 = try o.value("capability_sha256")
        hostAuthorityReference = try o.value("host_authority_reference")
        intent = try o.value("intent")
        requestId = try o.value("request_id")
        try o.constant("schema", .string("healthmd.agent_plan_request"))
        try o.constant("schema_version", .int(1))
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "authority_id", value: authorityId.bridgeJSON))
        fields.append(.init(key: "authority_revision", value: .int(authorityRevision)))
        fields.append(.init(key: "capability_sha256", value: capabilitySha256.bridgeJSON))
        fields.append(.init(key: "host_authority_reference", value: hostAuthorityReference.bridgeJSON))
        fields.append(.init(key: "intent", value: intent.bridgeJSON))
        fields.append(.init(key: "request_id", value: requestId.bridgeJSON))
        fields.append(.init(key: "schema", value: .string("healthmd.agent_plan_request")))
        fields.append(.init(key: "schema_version", value: .int(1)))
        return .object(fields)
    }
}

public struct AgentBridgeApprovalRequest: Codable, Equatable, Sendable, BridgeValueCodable {
    public let binding: AgentBridgeBinding
    public let planId: AgentBridgeUUID
    public let requestId: AgentBridgeUUID
    public init(binding: AgentBridgeBinding, planId: AgentBridgeUUID, requestId: AgentBridgeUUID) {
        self.binding = binding
        self.planId = planId
        self.requestId = requestId
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "request_id", "plan_id", "binding"], optional: [])
        binding = try o.value("binding")
        planId = try o.value("plan_id")
        requestId = try o.value("request_id")
        try o.constant("schema", .string("healthmd.agent_approval_request"))
        try o.constant("schema_version", .int(1))
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "binding", value: binding.bridgeJSON))
        fields.append(.init(key: "plan_id", value: planId.bridgeJSON))
        fields.append(.init(key: "request_id", value: requestId.bridgeJSON))
        fields.append(.init(key: "schema", value: .string("healthmd.agent_approval_request")))
        fields.append(.init(key: "schema_version", value: .int(1)))
        return .object(fields)
    }
}

public struct AgentBridgeError: Codable, Equatable, Sendable, BridgeValueCodable {
    public let code: AgentBridgeErrorCode
    public let requestId: AgentBridgeUUID
    public let retryable: Bool
    public init(code: AgentBridgeErrorCode, requestId: AgentBridgeUUID, retryable: Bool) {
        self.code = code
        self.requestId = requestId
        self.retryable = retryable
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "request_id", "code", "retryable"], optional: [])
        code = try o.token("code")
        requestId = try o.value("request_id")
        retryable = try o.bool("retryable")
        try o.constant("schema", .string("healthmd.agent_error"))
        try o.constant("schema_version", .int(1))
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "code", value: .string(code.rawValue)))
        fields.append(.init(key: "request_id", value: requestId.bridgeJSON))
        fields.append(.init(key: "retryable", value: .bool(retryable)))
        fields.append(.init(key: "schema", value: .string("healthmd.agent_error")))
        fields.append(.init(key: "schema_version", value: .int(1)))
        return .object(fields)
    }
}

public struct AgentBridgeDiscovery: Codable, Equatable, Sendable, BridgeValueCodable {
    public let authorityReferences: [AgentBridgeAuthorityReference]
    public let budgets: AgentBridgeBudgets
    public let capabilityRevision: Int64
    public let capabilitySha256: AgentBridgeDigest
    public let configurationProtection: AgentBridgeDiscoveryConfigurationProtection
    public let controlOperations: [AgentBridgeDiscoveryControlOperations]
    public let entitlement: AgentBridgeDiscoveryEntitlement
    public let expiresAt: AgentBridgeUTC
    public let features: [AgentBridgeDiscoveryFeatures]
    public let issuedAt: AgentBridgeUTC
    public let lifecycle: AgentBridgeDiscoveryLifecycle
    public let nativeGrants: AgentBridgeDiscoveryNativeGrants
    public let outputProfiles: [AgentBridgeDiscoveryOutputProfiles]
    public let outputSupport: AgentBridgeOutputSupport
    public let peer: AgentBridgePeer
    public let projectionCatalogSha256: AgentBridgeDigest
    public let projectionProducts: [AgentBridgeDiscoveryProjectionProducts]
    public let projectionSourceCatalog: AgentBridgeQueryCatalog?
    public let queryCatalogSha256: AgentBridgeDigest
    public let queryOperations: [AgentBridgeID]
    public let requestId: AgentBridgeUUID
    public let requiredActions: [AgentBridgeDiscoveryRequiredActions]
    public let settingsPolicies: [AgentBridgeDiscoverySettingsPolicies]
    public let sourceCalendarTimezone: AgentBridgeZone
    public init(authorityReferences: [AgentBridgeAuthorityReference], budgets: AgentBridgeBudgets, capabilityRevision: Int64, capabilitySha256: AgentBridgeDigest, configurationProtection: AgentBridgeDiscoveryConfigurationProtection, controlOperations: [AgentBridgeDiscoveryControlOperations], entitlement: AgentBridgeDiscoveryEntitlement, expiresAt: AgentBridgeUTC, features: [AgentBridgeDiscoveryFeatures], issuedAt: AgentBridgeUTC, lifecycle: AgentBridgeDiscoveryLifecycle, nativeGrants: AgentBridgeDiscoveryNativeGrants, outputProfiles: [AgentBridgeDiscoveryOutputProfiles], outputSupport: AgentBridgeOutputSupport, peer: AgentBridgePeer, projectionCatalogSha256: AgentBridgeDigest, projectionProducts: [AgentBridgeDiscoveryProjectionProducts], projectionSourceCatalog: AgentBridgeQueryCatalog? = nil, queryCatalogSha256: AgentBridgeDigest, queryOperations: [AgentBridgeID], requestId: AgentBridgeUUID, requiredActions: [AgentBridgeDiscoveryRequiredActions], settingsPolicies: [AgentBridgeDiscoverySettingsPolicies], sourceCalendarTimezone: AgentBridgeZone) {
        self.authorityReferences = authorityReferences
        self.budgets = budgets
        self.capabilityRevision = capabilityRevision
        self.capabilitySha256 = capabilitySha256
        self.configurationProtection = configurationProtection
        self.controlOperations = controlOperations
        self.entitlement = entitlement
        self.expiresAt = expiresAt
        self.features = features
        self.issuedAt = issuedAt
        self.lifecycle = lifecycle
        self.nativeGrants = nativeGrants
        self.outputProfiles = outputProfiles
        self.outputSupport = outputSupport
        self.peer = peer
        self.projectionCatalogSha256 = projectionCatalogSha256
        self.projectionProducts = projectionProducts
        self.projectionSourceCatalog = projectionSourceCatalog
        self.queryCatalogSha256 = queryCatalogSha256
        self.queryOperations = queryOperations
        self.requestId = requestId
        self.requiredActions = requiredActions
        self.settingsPolicies = settingsPolicies
        self.sourceCalendarTimezone = sourceCalendarTimezone
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "request_id", "peer", "capability_revision", "capability_sha256", "issued_at", "expires_at", "source_calendar_timezone", "features", "settings_policies", "output_profiles", "projection_products", "projection_catalog_sha256", "query_catalog_sha256", "query_operations", "budgets", "output_support", "control_operations", "authority_references", "lifecycle", "configuration_protection", "native_grants", "entitlement", "required_actions"], optional: ["projection_source_catalog"])
        authorityReferences = try o.list("authority_references", min: 0, max: 32)
        budgets = try o.value("budgets")
        capabilityRevision = try o.int("capability_revision", min: 1, max: 2147483647)
        capabilitySha256 = try o.value("capability_sha256")
        configurationProtection = try o.token("configuration_protection")
        controlOperations = try o.tokens("control_operations", min: 0, max: 64)
        try bridgeUnique(controlOperations.map(\.rawValue))
        entitlement = try o.token("entitlement")
        expiresAt = try o.value("expires_at")
        features = try o.tokens("features", min: 0, max: 11)
        try bridgeUnique(features.map(\.rawValue))
        issuedAt = try o.value("issued_at")
        lifecycle = try o.token("lifecycle")
        nativeGrants = try o.token("native_grants")
        outputProfiles = try o.tokens("output_profiles", min: 0, max: 3)
        try bridgeUnique(outputProfiles.map(\.rawValue))
        outputSupport = try o.value("output_support")
        peer = try o.value("peer")
        projectionCatalogSha256 = try o.value("projection_catalog_sha256")
        projectionProducts = try o.tokens("projection_products", min: 0, max: 1)
        try bridgeUnique(projectionProducts.map(\.rawValue))
        projectionSourceCatalog = o.has("projection_source_catalog") ? try o.value("projection_source_catalog") : nil
        queryCatalogSha256 = try o.value("query_catalog_sha256")
        queryOperations = try o.list("query_operations", min: 0, max: 9)
        try bridgeUnique(queryOperations.map(\.rawValue))
        requestId = try o.value("request_id")
        requiredActions = try o.tokens("required_actions", min: 0, max: 16)
        try bridgeUnique(requiredActions.map(\.rawValue))
        try o.constant("schema", .string("healthmd.agent_discovery"))
        try o.constant("schema_version", .int(1))
        settingsPolicies = try o.tokens("settings_policies", min: 0, max: 3)
        try bridgeUnique(settingsPolicies.map(\.rawValue))
        sourceCalendarTimezone = try o.value("source_calendar_timezone")
        try AgentBridgeSemantics.validate(self)
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "authority_references", value: .values(authorityReferences)))
        fields.append(.init(key: "budgets", value: budgets.bridgeJSON))
        fields.append(.init(key: "capability_revision", value: .int(capabilityRevision)))
        fields.append(.init(key: "capability_sha256", value: capabilitySha256.bridgeJSON))
        fields.append(.init(key: "configuration_protection", value: .string(configurationProtection.rawValue)))
        fields.append(.init(key: "control_operations", value: bridgeTokens(controlOperations)))
        fields.append(.init(key: "entitlement", value: .string(entitlement.rawValue)))
        fields.append(.init(key: "expires_at", value: expiresAt.bridgeJSON))
        fields.append(.init(key: "features", value: bridgeTokens(features)))
        fields.append(.init(key: "issued_at", value: issuedAt.bridgeJSON))
        fields.append(.init(key: "lifecycle", value: .string(lifecycle.rawValue)))
        fields.append(.init(key: "native_grants", value: .string(nativeGrants.rawValue)))
        fields.append(.init(key: "output_profiles", value: bridgeTokens(outputProfiles)))
        fields.append(.init(key: "output_support", value: outputSupport.bridgeJSON))
        fields.append(.init(key: "peer", value: peer.bridgeJSON))
        fields.append(.init(key: "projection_catalog_sha256", value: projectionCatalogSha256.bridgeJSON))
        fields.append(.init(key: "projection_products", value: bridgeTokens(projectionProducts)))
        if let projectionSourceCatalog { fields.append(.init(key: "projection_source_catalog", value: projectionSourceCatalog.bridgeJSON)) }
        fields.append(.init(key: "query_catalog_sha256", value: queryCatalogSha256.bridgeJSON))
        fields.append(.init(key: "query_operations", value: .values(queryOperations)))
        fields.append(.init(key: "request_id", value: requestId.bridgeJSON))
        fields.append(.init(key: "required_actions", value: bridgeTokens(requiredActions)))
        fields.append(.init(key: "schema", value: .string("healthmd.agent_discovery")))
        fields.append(.init(key: "schema_version", value: .int(1)))
        fields.append(.init(key: "settings_policies", value: bridgeTokens(settingsPolicies)))
        fields.append(.init(key: "source_calendar_timezone", value: sourceCalendarTimezone.bridgeJSON))
        return .object(fields)
    }
}

public struct AgentBridgeAuthority: Codable, Equatable, Sendable, BridgeValueCodable {
    public let authorityId: AgentBridgeUUID
    public let configurationProtection: AgentBridgeAuthorityConfigurationProtection
    public let controlReadScope: AgentBridgeControlReadScope?
    public let destinationBindingIds: [AgentBridgeUUID]
    public let entitlement: AgentBridgeAuthorityEntitlement
    public let expiresAt: AgentBridgeUTC
    public let grantRevision: Int64
    public let issuer: AgentBridgeAuthorityIssuer
    public let nativeConsent: AgentBridgeAuthorityNativeConsent
    public let peer: AgentBridgePeer
    public let rights: [AgentBridgeAuthorityRights]
    public let scopeSha256: AgentBridgeDigest
    public init(authorityId: AgentBridgeUUID, configurationProtection: AgentBridgeAuthorityConfigurationProtection, controlReadScope: AgentBridgeControlReadScope? = nil, destinationBindingIds: [AgentBridgeUUID], entitlement: AgentBridgeAuthorityEntitlement, expiresAt: AgentBridgeUTC, grantRevision: Int64, issuer: AgentBridgeAuthorityIssuer, nativeConsent: AgentBridgeAuthorityNativeConsent, peer: AgentBridgePeer, rights: [AgentBridgeAuthorityRights], scopeSha256: AgentBridgeDigest) {
        self.authorityId = authorityId
        self.configurationProtection = configurationProtection
        self.controlReadScope = controlReadScope
        self.destinationBindingIds = destinationBindingIds
        self.entitlement = entitlement
        self.expiresAt = expiresAt
        self.grantRevision = grantRevision
        self.issuer = issuer
        self.nativeConsent = nativeConsent
        self.peer = peer
        self.rights = rights
        self.scopeSha256 = scopeSha256
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "authority_id", "issuer", "peer", "rights", "scope_sha256", "destination_binding_ids", "expires_at", "configuration_protection", "native_consent", "entitlement", "grant_revision"], optional: ["control_read_scope"])
        authorityId = try o.value("authority_id")
        configurationProtection = try o.token("configuration_protection")
        controlReadScope = o.has("control_read_scope") ? try o.value("control_read_scope") : nil
        destinationBindingIds = try o.list("destination_binding_ids", min: 0, max: 32)
        try bridgeUnique(destinationBindingIds.map(\.rawValue))
        entitlement = try o.token("entitlement")
        expiresAt = try o.value("expires_at")
        grantRevision = try o.int("grant_revision", min: 1, max: 2147483647)
        issuer = try o.token("issuer")
        nativeConsent = try o.token("native_consent")
        peer = try o.value("peer")
        rights = try o.tokens("rights", min: 1, max: 14)
        try bridgeUnique(rights.map(\.rawValue))
        try o.constant("schema", .string("healthmd.agent_authority"))
        try o.constant("schema_version", .int(1))
        scopeSha256 = try o.value("scope_sha256")
        try AgentBridgeSemantics.validate(self)
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "authority_id", value: authorityId.bridgeJSON))
        fields.append(.init(key: "configuration_protection", value: .string(configurationProtection.rawValue)))
        if let controlReadScope { fields.append(.init(key: "control_read_scope", value: controlReadScope.bridgeJSON)) }
        fields.append(.init(key: "destination_binding_ids", value: .values(destinationBindingIds)))
        fields.append(.init(key: "entitlement", value: .string(entitlement.rawValue)))
        fields.append(.init(key: "expires_at", value: expiresAt.bridgeJSON))
        fields.append(.init(key: "grant_revision", value: .int(grantRevision)))
        fields.append(.init(key: "issuer", value: .string(issuer.rawValue)))
        fields.append(.init(key: "native_consent", value: .string(nativeConsent.rawValue)))
        fields.append(.init(key: "peer", value: peer.bridgeJSON))
        fields.append(.init(key: "rights", value: bridgeTokens(rights)))
        fields.append(.init(key: "schema", value: .string("healthmd.agent_authority")))
        fields.append(.init(key: "schema_version", value: .int(1)))
        fields.append(.init(key: "scope_sha256", value: scopeSha256.bridgeJSON))
        return .object(fields)
    }
}

public struct AgentBridgeAuthorityReference: Codable, Equatable, Sendable, BridgeValueCodable {
    public let authorityId: AgentBridgeUUID
    public let grantRevision: Int64
    public let grantSha256: AgentBridgeDigest
    public let issuer: AgentBridgeAuthorityReferenceIssuer
    public init(authorityId: AgentBridgeUUID, grantRevision: Int64, grantSha256: AgentBridgeDigest, issuer: AgentBridgeAuthorityReferenceIssuer) {
        self.authorityId = authorityId
        self.grantRevision = grantRevision
        self.grantSha256 = grantSha256
        self.issuer = issuer
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["authority_id", "issuer", "grant_revision", "grant_sha256"], optional: [])
        authorityId = try o.value("authority_id")
        grantRevision = try o.int("grant_revision", min: 1, max: 2147483647)
        grantSha256 = try o.value("grant_sha256")
        issuer = try o.token("issuer")
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "authority_id", value: authorityId.bridgeJSON))
        fields.append(.init(key: "grant_revision", value: .int(grantRevision)))
        fields.append(.init(key: "grant_sha256", value: grantSha256.bridgeJSON))
        fields.append(.init(key: "issuer", value: .string(issuer.rawValue)))
        return .object(fields)
    }
}

public struct AgentBridgeAuthorityReferences: Codable, Equatable, Sendable, BridgeValueCodable {
    public let host: AgentBridgeAuthorityReference
    public let native: AgentBridgeAuthorityReference
    public init(host: AgentBridgeAuthorityReference, native: AgentBridgeAuthorityReference) {
        self.host = host
        self.native = native
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["native", "host"], optional: [])
        host = try o.value("host")
        native = try o.value("native")
        try AgentBridgeSemantics.validate(self)
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "host", value: host.bridgeJSON))
        fields.append(.init(key: "native", value: native.bridgeJSON))
        return .object(fields)
    }
}

public struct AgentBridgeApproval: Codable, Equatable, Sendable, BridgeValueCodable {
    public let approvalId: AgentBridgeUUID
    public let approvedAt: AgentBridgeUTC
    public let authorityId: AgentBridgeUUID
    public let binding: AgentBridgeBinding
    public let rights: [AgentBridgeApprovalRights]
    public init(approvalId: AgentBridgeUUID, approvedAt: AgentBridgeUTC, authorityId: AgentBridgeUUID, binding: AgentBridgeBinding, rights: [AgentBridgeApprovalRights]) {
        self.approvalId = approvalId
        self.approvedAt = approvedAt
        self.authorityId = authorityId
        self.binding = binding
        self.rights = rights
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "approval_id", "authority_id", "binding", "rights", "approved_at"], optional: [])
        approvalId = try o.value("approval_id")
        approvedAt = try o.value("approved_at")
        authorityId = try o.value("authority_id")
        binding = try o.value("binding")
        rights = try o.tokens("rights", min: 1, max: 1)
        try bridgeUnique(rights.map(\.rawValue))
        try o.constant("schema", .string("healthmd.agent_approval"))
        try o.constant("schema_version", .int(1))
        try AgentBridgeSemantics.validate(self)
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "approval_id", value: approvalId.bridgeJSON))
        fields.append(.init(key: "approved_at", value: approvedAt.bridgeJSON))
        fields.append(.init(key: "authority_id", value: authorityId.bridgeJSON))
        fields.append(.init(key: "binding", value: binding.bridgeJSON))
        fields.append(.init(key: "rights", value: bridgeTokens(rights)))
        fields.append(.init(key: "schema", value: .string("healthmd.agent_approval")))
        fields.append(.init(key: "schema_version", value: .int(1)))
        return .object(fields)
    }
}

public struct AgentBridgePlan: Codable, Equatable, Sendable, BridgeValueCodable {
    public let authorityReferences: AgentBridgeAuthorityReferences
    public let capabilitySha256: AgentBridgeDigest
    public let effectiveSettings: AgentBridgeOutputSettings
    public let expiresAt: AgentBridgeUTC
    public let intent: AgentBridgeGeneratedIntent
    public let issuedAt: AgentBridgeUTC
    public let limitations: [AgentBridgeID]
    public let origins: [AgentBridgeOrigin]
    public let pathPrediction: AgentBridgePlanPathPrediction
    public let planId: AgentBridgeUUID
    public let planSha256: AgentBridgeDigest
    public let predictedPaths: [AgentBridgePath]
    public let requiredActions: [AgentBridgeID]
    public let resolvedDates: AgentBridgeDates
    public let resolvedMetricIds: [AgentBridgeID]
    public let revisions: [AgentBridgeRevision]
    public let scopeSha256: AgentBridgeDigest
    public let settingsSha256: AgentBridgeDigest
    public let sideEffects: AgentBridgeZeroEffects
    public init(authorityReferences: AgentBridgeAuthorityReferences, capabilitySha256: AgentBridgeDigest, effectiveSettings: AgentBridgeOutputSettings, expiresAt: AgentBridgeUTC, intent: AgentBridgeGeneratedIntent, issuedAt: AgentBridgeUTC, limitations: [AgentBridgeID], origins: [AgentBridgeOrigin], pathPrediction: AgentBridgePlanPathPrediction, planId: AgentBridgeUUID, planSha256: AgentBridgeDigest, predictedPaths: [AgentBridgePath], requiredActions: [AgentBridgeID], resolvedDates: AgentBridgeDates, resolvedMetricIds: [AgentBridgeID], revisions: [AgentBridgeRevision], scopeSha256: AgentBridgeDigest, settingsSha256: AgentBridgeDigest, sideEffects: AgentBridgeZeroEffects) {
        self.authorityReferences = authorityReferences
        self.capabilitySha256 = capabilitySha256
        self.effectiveSettings = effectiveSettings
        self.expiresAt = expiresAt
        self.intent = intent
        self.issuedAt = issuedAt
        self.limitations = limitations
        self.origins = origins
        self.pathPrediction = pathPrediction
        self.planId = planId
        self.planSha256 = planSha256
        self.predictedPaths = predictedPaths
        self.requiredActions = requiredActions
        self.resolvedDates = resolvedDates
        self.resolvedMetricIds = resolvedMetricIds
        self.revisions = revisions
        self.scopeSha256 = scopeSha256
        self.settingsSha256 = settingsSha256
        self.sideEffects = sideEffects
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "plan_id", "resolved_dates", "resolved_metric_ids", "authority_references", "origins", "revisions", "settings_sha256", "scope_sha256", "capability_sha256", "plan_sha256", "issued_at", "expires_at", "predicted_paths", "path_prediction", "required_actions", "limitations", "side_effects", "intent", "effective_settings"], optional: [])
        authorityReferences = try o.value("authority_references")
        capabilitySha256 = try o.value("capability_sha256")
        effectiveSettings = try o.value("effective_settings")
        expiresAt = try o.value("expires_at")
        intent = try o.value("intent")
        issuedAt = try o.value("issued_at")
        limitations = try o.list("limitations", min: 0, max: 64)
        try bridgeUnique(limitations.map(\.rawValue))
        origins = try o.list("origins", min: 1, max: 512)
        pathPrediction = try o.token("path_prediction")
        planId = try o.value("plan_id")
        planSha256 = try o.value("plan_sha256")
        predictedPaths = try o.list("predicted_paths", min: 0, max: 4096)
        try bridgeUnique(predictedPaths.map(\.rawValue))
        requiredActions = try o.list("required_actions", min: 0, max: 16)
        try bridgeUnique(requiredActions.map(\.rawValue))
        resolvedDates = try o.value("resolved_dates")
        resolvedMetricIds = try o.list("resolved_metric_ids", min: 1, max: 256)
        try bridgeUnique(resolvedMetricIds.map(\.rawValue))
        revisions = try o.list("revisions", min: 0, max: 16)
        try o.constant("schema", .string("healthmd.agent_export_plan"))
        try o.constant("schema_version", .int(1))
        scopeSha256 = try o.value("scope_sha256")
        settingsSha256 = try o.value("settings_sha256")
        sideEffects = try o.value("side_effects")
        try AgentBridgeSemantics.validate(self)
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "authority_references", value: authorityReferences.bridgeJSON))
        fields.append(.init(key: "capability_sha256", value: capabilitySha256.bridgeJSON))
        fields.append(.init(key: "effective_settings", value: effectiveSettings.bridgeJSON))
        fields.append(.init(key: "expires_at", value: expiresAt.bridgeJSON))
        fields.append(.init(key: "intent", value: intent.bridgeJSON))
        fields.append(.init(key: "issued_at", value: issuedAt.bridgeJSON))
        fields.append(.init(key: "limitations", value: .values(limitations)))
        fields.append(.init(key: "origins", value: .values(origins)))
        fields.append(.init(key: "path_prediction", value: .string(pathPrediction.rawValue)))
        fields.append(.init(key: "plan_id", value: planId.bridgeJSON))
        fields.append(.init(key: "plan_sha256", value: planSha256.bridgeJSON))
        fields.append(.init(key: "predicted_paths", value: .values(predictedPaths)))
        fields.append(.init(key: "required_actions", value: .values(requiredActions)))
        fields.append(.init(key: "resolved_dates", value: resolvedDates.bridgeJSON))
        fields.append(.init(key: "resolved_metric_ids", value: .values(resolvedMetricIds)))
        fields.append(.init(key: "revisions", value: .values(revisions)))
        fields.append(.init(key: "schema", value: .string("healthmd.agent_export_plan")))
        fields.append(.init(key: "schema_version", value: .int(1)))
        fields.append(.init(key: "scope_sha256", value: scopeSha256.bridgeJSON))
        fields.append(.init(key: "settings_sha256", value: settingsSha256.bridgeJSON))
        fields.append(.init(key: "side_effects", value: sideEffects.bridgeJSON))
        return .object(fields)
    }
}

public struct AgentBridgeExecute: Codable, Equatable, Sendable, BridgeValueCodable {
    public let approval: AgentBridgeApproval
    public let idempotencyKey: AgentBridgeUUID
    public let jobId: AgentBridgeUUID
    public let plan: AgentBridgePlan
    public let requestId: AgentBridgeUUID
    public init(approval: AgentBridgeApproval, idempotencyKey: AgentBridgeUUID, jobId: AgentBridgeUUID, plan: AgentBridgePlan, requestId: AgentBridgeUUID) {
        self.approval = approval
        self.idempotencyKey = idempotencyKey
        self.jobId = jobId
        self.plan = plan
        self.requestId = requestId
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "request_id", "job_id", "idempotency_key", "plan", "approval"], optional: [])
        approval = try o.value("approval")
        idempotencyKey = try o.value("idempotency_key")
        jobId = try o.value("job_id")
        plan = try o.value("plan")
        requestId = try o.value("request_id")
        try o.constant("schema", .string("healthmd.agent_execute_request"))
        try o.constant("schema_version", .int(1))
        try AgentBridgeSemantics.validate(self)
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "approval", value: approval.bridgeJSON))
        fields.append(.init(key: "idempotency_key", value: idempotencyKey.bridgeJSON))
        fields.append(.init(key: "job_id", value: jobId.bridgeJSON))
        fields.append(.init(key: "plan", value: plan.bridgeJSON))
        fields.append(.init(key: "request_id", value: requestId.bridgeJSON))
        fields.append(.init(key: "schema", value: .string("healthmd.agent_execute_request")))
        fields.append(.init(key: "schema_version", value: .int(1)))
        return .object(fields)
    }
}

public struct AgentBridgeExecutionReceipt: Codable, Equatable, Sendable, BridgeValueCodable {
    public let artifactCount: Int64
    public let binding: AgentBridgeBinding
    public let committedPartitionCount: Int64
    public let expiresAt: AgentBridgeUTC
    public let frontierSha256: AgentBridgeDigest
    public let jobId: AgentBridgeUUID
    public let manifestSha256: AgentBridgeDigest
    public let requestSha256: AgentBridgeDigest
    public let sourceAcknowledged: Bool
    public let status: AgentBridgeExecutionReceiptStatus
    public init(artifactCount: Int64, binding: AgentBridgeBinding, committedPartitionCount: Int64, expiresAt: AgentBridgeUTC, frontierSha256: AgentBridgeDigest, jobId: AgentBridgeUUID, manifestSha256: AgentBridgeDigest, requestSha256: AgentBridgeDigest, sourceAcknowledged: Bool, status: AgentBridgeExecutionReceiptStatus) {
        self.artifactCount = artifactCount
        self.binding = binding
        self.committedPartitionCount = committedPartitionCount
        self.expiresAt = expiresAt
        self.frontierSha256 = frontierSha256
        self.jobId = jobId
        self.manifestSha256 = manifestSha256
        self.requestSha256 = requestSha256
        self.sourceAcknowledged = sourceAcknowledged
        self.status = status
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "job_id", "binding", "request_sha256", "manifest_sha256", "status", "source_acknowledged", "artifact_count", "committed_partition_count", "frontier_sha256", "expires_at"], optional: [])
        artifactCount = try o.int("artifact_count", min: 0, max: 4096)
        binding = try o.value("binding")
        committedPartitionCount = try o.int("committed_partition_count", min: 0, max: 2147483647)
        expiresAt = try o.value("expires_at")
        frontierSha256 = try o.value("frontier_sha256")
        jobId = try o.value("job_id")
        manifestSha256 = try o.value("manifest_sha256")
        requestSha256 = try o.value("request_sha256")
        try o.constant("schema", .string("healthmd.agent_execution_receipt"))
        try o.constant("schema_version", .int(1))
        sourceAcknowledged = try o.bool("source_acknowledged")
        status = try o.token("status")
        try AgentBridgeSemantics.validate(self)
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "artifact_count", value: .int(artifactCount)))
        fields.append(.init(key: "binding", value: binding.bridgeJSON))
        fields.append(.init(key: "committed_partition_count", value: .int(committedPartitionCount)))
        fields.append(.init(key: "expires_at", value: expiresAt.bridgeJSON))
        fields.append(.init(key: "frontier_sha256", value: frontierSha256.bridgeJSON))
        fields.append(.init(key: "job_id", value: jobId.bridgeJSON))
        fields.append(.init(key: "manifest_sha256", value: manifestSha256.bridgeJSON))
        fields.append(.init(key: "request_sha256", value: requestSha256.bridgeJSON))
        fields.append(.init(key: "schema", value: .string("healthmd.agent_execution_receipt")))
        fields.append(.init(key: "schema_version", value: .int(1)))
        fields.append(.init(key: "source_acknowledged", value: .bool(sourceAcknowledged)))
        fields.append(.init(key: "status", value: .string(status.rawValue)))
        return .object(fields)
    }
}

public struct AgentBridgeResume: Codable, Equatable, Sendable, BridgeValueCodable {
    public let binding: AgentBridgeBinding
    public let committedPartitionCount: Int64
    public let destination: AgentBridgeDestination
    public let frontierSha256: AgentBridgeDigest
    public let jobId: AgentBridgeUUID
    public let manifestSha256: AgentBridgeDigest
    public let peer: AgentBridgePeer
    public let requestSha256: AgentBridgeDigest
    public init(binding: AgentBridgeBinding, committedPartitionCount: Int64, destination: AgentBridgeDestination, frontierSha256: AgentBridgeDigest, jobId: AgentBridgeUUID, manifestSha256: AgentBridgeDigest, peer: AgentBridgePeer, requestSha256: AgentBridgeDigest) {
        self.binding = binding
        self.committedPartitionCount = committedPartitionCount
        self.destination = destination
        self.frontierSha256 = frontierSha256
        self.jobId = jobId
        self.manifestSha256 = manifestSha256
        self.peer = peer
        self.requestSha256 = requestSha256
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "job_id", "peer", "destination", "binding", "request_sha256", "manifest_sha256", "committed_partition_count", "frontier_sha256"], optional: [])
        binding = try o.value("binding")
        committedPartitionCount = try o.int("committed_partition_count", min: 0, max: 2147483647)
        destination = try o.value("destination")
        frontierSha256 = try o.value("frontier_sha256")
        jobId = try o.value("job_id")
        manifestSha256 = try o.value("manifest_sha256")
        peer = try o.value("peer")
        requestSha256 = try o.value("request_sha256")
        try o.constant("schema", .string("healthmd.agent_resume_request"))
        try o.constant("schema_version", .int(1))
        try AgentBridgeSemantics.validate(self)
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "binding", value: binding.bridgeJSON))
        fields.append(.init(key: "committed_partition_count", value: .int(committedPartitionCount)))
        fields.append(.init(key: "destination", value: destination.bridgeJSON))
        fields.append(.init(key: "frontier_sha256", value: frontierSha256.bridgeJSON))
        fields.append(.init(key: "job_id", value: jobId.bridgeJSON))
        fields.append(.init(key: "manifest_sha256", value: manifestSha256.bridgeJSON))
        fields.append(.init(key: "peer", value: peer.bridgeJSON))
        fields.append(.init(key: "request_sha256", value: requestSha256.bridgeJSON))
        fields.append(.init(key: "schema", value: .string("healthmd.agent_resume_request")))
        fields.append(.init(key: "schema_version", value: .int(1)))
        return .object(fields)
    }
}

public struct AgentBridgeCancel: Codable, Equatable, Sendable, BridgeValueCodable {
    public let approvalId: AgentBridgeUUID
    public let authorityId: AgentBridgeUUID
    public let jobId: AgentBridgeUUID
    public let peer: AgentBridgePeer
    public let requestSha256: AgentBridgeDigest
    public init(approvalId: AgentBridgeUUID, authorityId: AgentBridgeUUID, jobId: AgentBridgeUUID, peer: AgentBridgePeer, requestSha256: AgentBridgeDigest) {
        self.approvalId = approvalId
        self.authorityId = authorityId
        self.jobId = jobId
        self.peer = peer
        self.requestSha256 = requestSha256
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "job_id", "peer", "request_sha256", "authority_id", "approval_id"], optional: [])
        approvalId = try o.value("approval_id")
        authorityId = try o.value("authority_id")
        jobId = try o.value("job_id")
        peer = try o.value("peer")
        requestSha256 = try o.value("request_sha256")
        try o.constant("schema", .string("healthmd.agent_cancel_request"))
        try o.constant("schema_version", .int(1))
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "approval_id", value: approvalId.bridgeJSON))
        fields.append(.init(key: "authority_id", value: authorityId.bridgeJSON))
        fields.append(.init(key: "job_id", value: jobId.bridgeJSON))
        fields.append(.init(key: "peer", value: peer.bridgeJSON))
        fields.append(.init(key: "request_sha256", value: requestSha256.bridgeJSON))
        fields.append(.init(key: "schema", value: .string("healthmd.agent_cancel_request")))
        fields.append(.init(key: "schema_version", value: .int(1)))
        return .object(fields)
    }
}

public struct AgentBridgeArtifactManifest: Codable, Equatable, Sendable, BridgeValueCodable {
    public let artifacts: [AgentBridgeArtifact]
    public let binding: AgentBridgeBinding
    public let branchStatuses: [AgentBridgeArtifactManifestBranchStatuses]
    public let captureStatus: AgentBridgeArtifactManifestCaptureStatus
    public let jobId: AgentBridgeUUID
    public let requestSha256: AgentBridgeDigest
    public init(artifacts: [AgentBridgeArtifact], binding: AgentBridgeBinding, branchStatuses: [AgentBridgeArtifactManifestBranchStatuses], captureStatus: AgentBridgeArtifactManifestCaptureStatus, jobId: AgentBridgeUUID, requestSha256: AgentBridgeDigest) {
        self.artifacts = artifacts
        self.binding = binding
        self.branchStatuses = branchStatuses
        self.captureStatus = captureStatus
        self.jobId = jobId
        self.requestSha256 = requestSha256
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "job_id", "request_sha256", "binding", "artifacts", "capture_status", "branch_statuses"], optional: [])
        artifacts = try o.list("artifacts", min: 0, max: 4096)
        binding = try o.value("binding")
        branchStatuses = try o.list("branch_statuses", min: 0, max: 256)
        captureStatus = try o.token("capture_status")
        jobId = try o.value("job_id")
        requestSha256 = try o.value("request_sha256")
        try o.constant("schema", .string("healthmd.agent_artifact_manifest"))
        try o.constant("schema_version", .int(1))
        try AgentBridgeSemantics.validate(self)
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "artifacts", value: .values(artifacts)))
        fields.append(.init(key: "binding", value: binding.bridgeJSON))
        fields.append(.init(key: "branch_statuses", value: .values(branchStatuses)))
        fields.append(.init(key: "capture_status", value: .string(captureStatus.rawValue)))
        fields.append(.init(key: "job_id", value: jobId.bridgeJSON))
        fields.append(.init(key: "request_sha256", value: requestSha256.bridgeJSON))
        fields.append(.init(key: "schema", value: .string("healthmd.agent_artifact_manifest")))
        fields.append(.init(key: "schema_version", value: .int(1)))
        return .object(fields)
    }
}

public struct AgentBridgeCommitReceipt: Codable, Equatable, Sendable, BridgeValueCodable {
    public let afterSha256: AgentBridgeDigest
    public let artifactId: AgentBridgeUUID
    public let beforeSha256: AgentBridgeDigest
    public let commitKey: AgentBridgeDigest
    public let destination: AgentBridgeDestination
    public let inputSha256: AgentBridgeDigest
    public let jobId: AgentBridgeUUID
    public let manifestSha256: AgentBridgeDigest
    public let peer: AgentBridgePeer
    public let relativePath: AgentBridgePath
    public let requestSha256: AgentBridgeDigest
    public let status: AgentBridgeCommitReceiptStatus
    public let writeMode: AgentBridgeCommitReceiptWriteMode
    public init(afterSha256: AgentBridgeDigest, artifactId: AgentBridgeUUID, beforeSha256: AgentBridgeDigest, commitKey: AgentBridgeDigest, destination: AgentBridgeDestination, inputSha256: AgentBridgeDigest, jobId: AgentBridgeUUID, manifestSha256: AgentBridgeDigest, peer: AgentBridgePeer, relativePath: AgentBridgePath, requestSha256: AgentBridgeDigest, status: AgentBridgeCommitReceiptStatus, writeMode: AgentBridgeCommitReceiptWriteMode) {
        self.afterSha256 = afterSha256
        self.artifactId = artifactId
        self.beforeSha256 = beforeSha256
        self.commitKey = commitKey
        self.destination = destination
        self.inputSha256 = inputSha256
        self.jobId = jobId
        self.manifestSha256 = manifestSha256
        self.peer = peer
        self.relativePath = relativePath
        self.requestSha256 = requestSha256
        self.status = status
        self.writeMode = writeMode
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "job_id", "artifact_id", "peer", "destination", "request_sha256", "manifest_sha256", "relative_path", "write_mode", "input_sha256", "before_sha256", "after_sha256", "commit_key", "status"], optional: [])
        afterSha256 = try o.value("after_sha256")
        artifactId = try o.value("artifact_id")
        beforeSha256 = try o.value("before_sha256")
        commitKey = try o.value("commit_key")
        destination = try o.value("destination")
        inputSha256 = try o.value("input_sha256")
        jobId = try o.value("job_id")
        manifestSha256 = try o.value("manifest_sha256")
        peer = try o.value("peer")
        relativePath = try o.value("relative_path")
        requestSha256 = try o.value("request_sha256")
        try o.constant("schema", .string("healthmd.agent_commit_receipt"))
        try o.constant("schema_version", .int(1))
        status = try o.token("status")
        writeMode = try o.token("write_mode")
        try AgentBridgeSemantics.validate(self)
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "after_sha256", value: afterSha256.bridgeJSON))
        fields.append(.init(key: "artifact_id", value: artifactId.bridgeJSON))
        fields.append(.init(key: "before_sha256", value: beforeSha256.bridgeJSON))
        fields.append(.init(key: "commit_key", value: commitKey.bridgeJSON))
        fields.append(.init(key: "destination", value: destination.bridgeJSON))
        fields.append(.init(key: "input_sha256", value: inputSha256.bridgeJSON))
        fields.append(.init(key: "job_id", value: jobId.bridgeJSON))
        fields.append(.init(key: "manifest_sha256", value: manifestSha256.bridgeJSON))
        fields.append(.init(key: "peer", value: peer.bridgeJSON))
        fields.append(.init(key: "relative_path", value: relativePath.bridgeJSON))
        fields.append(.init(key: "request_sha256", value: requestSha256.bridgeJSON))
        fields.append(.init(key: "schema", value: .string("healthmd.agent_commit_receipt")))
        fields.append(.init(key: "schema_version", value: .int(1)))
        fields.append(.init(key: "status", value: .string(status.rawValue)))
        fields.append(.init(key: "write_mode", value: .string(writeMode.rawValue)))
        return .object(fields)
    }
}

public struct AgentBridgeBinding: Codable, Equatable, Sendable, BridgeValueCodable {
    public let authorityReferences: AgentBridgeAuthorityReferences
    public let capabilitySha256: AgentBridgeDigest
    public let destination: AgentBridgeDestination
    public let expiresAt: AgentBridgeUTC
    public let peer: AgentBridgePeer
    public let planSha256: AgentBridgeDigest
    public let revisions: [AgentBridgeRevision]
    public let scopeSha256: AgentBridgeDigest
    public let settingsSha256: AgentBridgeDigest
    public init(authorityReferences: AgentBridgeAuthorityReferences, capabilitySha256: AgentBridgeDigest, destination: AgentBridgeDestination, expiresAt: AgentBridgeUTC, peer: AgentBridgePeer, planSha256: AgentBridgeDigest, revisions: [AgentBridgeRevision], scopeSha256: AgentBridgeDigest, settingsSha256: AgentBridgeDigest) {
        self.authorityReferences = authorityReferences
        self.capabilitySha256 = capabilitySha256
        self.destination = destination
        self.expiresAt = expiresAt
        self.peer = peer
        self.planSha256 = planSha256
        self.revisions = revisions
        self.scopeSha256 = scopeSha256
        self.settingsSha256 = settingsSha256
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["peer", "destination", "authority_references", "plan_sha256", "settings_sha256", "scope_sha256", "capability_sha256", "revisions", "expires_at"], optional: [])
        authorityReferences = try o.value("authority_references")
        capabilitySha256 = try o.value("capability_sha256")
        destination = try o.value("destination")
        expiresAt = try o.value("expires_at")
        peer = try o.value("peer")
        planSha256 = try o.value("plan_sha256")
        revisions = try o.list("revisions", min: 0, max: 16)
        scopeSha256 = try o.value("scope_sha256")
        settingsSha256 = try o.value("settings_sha256")
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "authority_references", value: authorityReferences.bridgeJSON))
        fields.append(.init(key: "capability_sha256", value: capabilitySha256.bridgeJSON))
        fields.append(.init(key: "destination", value: destination.bridgeJSON))
        fields.append(.init(key: "expires_at", value: expiresAt.bridgeJSON))
        fields.append(.init(key: "peer", value: peer.bridgeJSON))
        fields.append(.init(key: "plan_sha256", value: planSha256.bridgeJSON))
        fields.append(.init(key: "revisions", value: .values(revisions)))
        fields.append(.init(key: "scope_sha256", value: scopeSha256.bridgeJSON))
        fields.append(.init(key: "settings_sha256", value: settingsSha256.bridgeJSON))
        return .object(fields)
    }
}

public struct AgentBridgeBudgets: Codable, Equatable, Sendable, BridgeValueCodable {
    public let cursorIdleSeconds: Int64
    public let cursorLifetimeSeconds: Int64
    public let maxCalendarDays: Int64
    public let maxCaptureSeconds: Int64
    public let maxPageBytes: Int64
    public let maxPageItems: Int64
    public let maxSnapshotBytes: Int64
    public init(cursorIdleSeconds: Int64, cursorLifetimeSeconds: Int64, maxCalendarDays: Int64, maxCaptureSeconds: Int64, maxPageBytes: Int64, maxPageItems: Int64, maxSnapshotBytes: Int64) {
        self.cursorIdleSeconds = cursorIdleSeconds
        self.cursorLifetimeSeconds = cursorLifetimeSeconds
        self.maxCalendarDays = maxCalendarDays
        self.maxCaptureSeconds = maxCaptureSeconds
        self.maxPageBytes = maxPageBytes
        self.maxPageItems = maxPageItems
        self.maxSnapshotBytes = maxSnapshotBytes
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["max_page_items", "max_page_bytes", "max_snapshot_bytes", "max_capture_seconds", "max_calendar_days", "cursor_idle_seconds", "cursor_lifetime_seconds"], optional: [])
        cursorIdleSeconds = try o.int("cursor_idle_seconds", min: 1, max: 600)
        cursorLifetimeSeconds = try o.int("cursor_lifetime_seconds", min: 1, max: 3600)
        maxCalendarDays = try o.int("max_calendar_days", min: 1, max: 366000)
        maxCaptureSeconds = try o.int("max_capture_seconds", min: 1, max: 120)
        maxPageBytes = try o.int("max_page_bytes", min: 1024, max: 1048576)
        maxPageItems = try o.int("max_page_items", min: 1, max: 1000)
        maxSnapshotBytes = try o.int("max_snapshot_bytes", min: 1024, max: 67108864)
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "cursor_idle_seconds", value: .int(cursorIdleSeconds)))
        fields.append(.init(key: "cursor_lifetime_seconds", value: .int(cursorLifetimeSeconds)))
        fields.append(.init(key: "max_calendar_days", value: .int(maxCalendarDays)))
        fields.append(.init(key: "max_capture_seconds", value: .int(maxCaptureSeconds)))
        fields.append(.init(key: "max_page_bytes", value: .int(maxPageBytes)))
        fields.append(.init(key: "max_page_items", value: .int(maxPageItems)))
        fields.append(.init(key: "max_snapshot_bytes", value: .int(maxSnapshotBytes)))
        return .object(fields)
    }
}

public struct AgentBridgeOutputSupport: Codable, Equatable, Sendable, BridgeValueCodable {
    public let compatibilityDetail: [AgentBridgeOutputSupportCompatibilityDetail]
    public let formats: [AgentBridgeOutputSupportFormats]
    public let maxArtifacts: Int64
    public let maxPathBytes: Int64
    public let nativeArchiveProducts: [AgentBridgeOutputSupportNativeArchiveProducts]
    public let pathTokens: [AgentBridgeOutputSupportPathTokens]
    public let settingPointers: [String]
    public let writeModes: [AgentBridgeOutputSupportWriteModes]
    public init(compatibilityDetail: [AgentBridgeOutputSupportCompatibilityDetail], formats: [AgentBridgeOutputSupportFormats], maxArtifacts: Int64, maxPathBytes: Int64, nativeArchiveProducts: [AgentBridgeOutputSupportNativeArchiveProducts], pathTokens: [AgentBridgeOutputSupportPathTokens], settingPointers: [String], writeModes: [AgentBridgeOutputSupportWriteModes]) {
        self.compatibilityDetail = compatibilityDetail
        self.formats = formats
        self.maxArtifacts = maxArtifacts
        self.maxPathBytes = maxPathBytes
        self.nativeArchiveProducts = nativeArchiveProducts
        self.pathTokens = pathTokens
        self.settingPointers = settingPointers
        self.writeModes = writeModes
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["formats", "write_modes", "compatibility_detail", "native_archive_products", "setting_pointers", "path_tokens", "max_artifacts", "max_path_bytes"], optional: [])
        compatibilityDetail = try o.tokens("compatibility_detail", min: 0, max: 2)
        try bridgeUnique(compatibilityDetail.map(\.rawValue))
        formats = try o.tokens("formats", min: 0, max: 4)
        try bridgeUnique(formats.map(\.rawValue))
        maxArtifacts = try o.int("max_artifacts", min: 1, max: 4096)
        maxPathBytes = try o.int("max_path_bytes", min: 1, max: 4096)
        nativeArchiveProducts = try o.tokens("native_archive_products", min: 0, max: 3)
        try bridgeUnique(nativeArchiveProducts.map(\.rawValue))
        pathTokens = try o.tokens("path_tokens", min: 0, max: 7)
        try bridgeUnique(pathTokens.map(\.rawValue))
        settingPointers = try o.strings("setting_pointers", min: 0, max: 512, minLength: 1, maxLength: 256)
        try bridgeUnique(settingPointers)
        for value in settingPointers { try bridgePattern(value, "\\A(?:/[a-z0-9_/]+)\\z", max: 256) }
        writeModes = try o.tokens("write_modes", min: 0, max: 4)
        try bridgeUnique(writeModes.map(\.rawValue))
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "compatibility_detail", value: bridgeTokens(compatibilityDetail)))
        fields.append(.init(key: "formats", value: bridgeTokens(formats)))
        fields.append(.init(key: "max_artifacts", value: .int(maxArtifacts)))
        fields.append(.init(key: "max_path_bytes", value: .int(maxPathBytes)))
        fields.append(.init(key: "native_archive_products", value: bridgeTokens(nativeArchiveProducts)))
        fields.append(.init(key: "path_tokens", value: bridgeTokens(pathTokens)))
        fields.append(.init(key: "setting_pointers", value: .strings(settingPointers)))
        fields.append(.init(key: "write_modes", value: bridgeTokens(writeModes)))
        return .object(fields)
    }
}

public struct AgentBridgeQueryCatalog: Codable, Equatable, Sendable, BridgeValueCodable {
    public let budgets: AgentBridgeBudgets
    public let featureStatuses: [AgentBridgeQueryCatalogFeatureStatuses]
    public let history: AgentBridgeCoverage
    public let metrics: [AgentBridgeCatalogItem]
    public let operations: [AgentBridgeID]
    public let peer: AgentBridgePeer
    public let providerAvailability: AgentBridgeQueryCatalogProviderAvailability
    public let providerId: AgentBridgeID
    public let providerVersion: String
    public let sdkVersion: String
    public let sourceId: AgentBridgeQueryCatalogSourceId
    public init(budgets: AgentBridgeBudgets, featureStatuses: [AgentBridgeQueryCatalogFeatureStatuses], history: AgentBridgeCoverage, metrics: [AgentBridgeCatalogItem], operations: [AgentBridgeID], peer: AgentBridgePeer, providerAvailability: AgentBridgeQueryCatalogProviderAvailability, providerId: AgentBridgeID, providerVersion: String, sdkVersion: String, sourceId: AgentBridgeQueryCatalogSourceId) {
        self.budgets = budgets
        self.featureStatuses = featureStatuses
        self.history = history
        self.metrics = metrics
        self.operations = operations
        self.peer = peer
        self.providerAvailability = providerAvailability
        self.providerId = providerId
        self.providerVersion = providerVersion
        self.sdkVersion = sdkVersion
        self.sourceId = sourceId
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["schema", "schema_version", "peer", "source_id", "provider_id", "sdk_version", "provider_version", "provider_availability", "feature_statuses", "metrics", "operations", "budgets", "history"], optional: [])
        budgets = try o.value("budgets")
        featureStatuses = try o.list("feature_statuses", min: 0, max: 32)
        history = try o.value("history")
        metrics = try o.list("metrics", min: 0, max: 256)
        operations = try o.list("operations", min: 0, max: 9)
        try bridgeUnique(operations.map(\.rawValue))
        peer = try o.value("peer")
        providerAvailability = try o.token("provider_availability")
        providerId = try o.value("provider_id")
        providerVersion = try o.text("provider_version", min: 1, max: 128)
        try o.constant("schema", .string("healthmd.source_query_catalog"))
        try o.constant("schema_version", .int(1))
        sdkVersion = try o.text("sdk_version", min: 1, max: 64)
        sourceId = try o.token("source_id")
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "budgets", value: budgets.bridgeJSON))
        fields.append(.init(key: "feature_statuses", value: .values(featureStatuses)))
        fields.append(.init(key: "history", value: history.bridgeJSON))
        fields.append(.init(key: "metrics", value: .values(metrics)))
        fields.append(.init(key: "operations", value: .values(operations)))
        fields.append(.init(key: "peer", value: peer.bridgeJSON))
        fields.append(.init(key: "provider_availability", value: .string(providerAvailability.rawValue)))
        fields.append(.init(key: "provider_id", value: providerId.bridgeJSON))
        fields.append(.init(key: "provider_version", value: .string(providerVersion)))
        fields.append(.init(key: "schema", value: .string("healthmd.source_query_catalog")))
        fields.append(.init(key: "schema_version", value: .int(1)))
        fields.append(.init(key: "sdk_version", value: .string(sdkVersion)))
        fields.append(.init(key: "source_id", value: .string(sourceId.rawValue)))
        return .object(fields)
    }
}

public struct AgentBridgeControlReadScope: Codable, Equatable, Sendable, BridgeValueCodable {
    public let createDomains: [AgentBridgeControlReadScopeCreateDomains]
    public let listDomains: [AgentBridgeControlReadScopeListDomains]
    public let objects: [AgentBridgeControlReadScopeObjects]
    public init(createDomains: [AgentBridgeControlReadScopeCreateDomains], listDomains: [AgentBridgeControlReadScopeListDomains], objects: [AgentBridgeControlReadScopeObjects]) {
        self.createDomains = createDomains
        self.listDomains = listDomains
        self.objects = objects
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["objects", "list_domains", "create_domains"], optional: [])
        createDomains = try o.tokens("create_domains", min: 0, max: 3)
        try bridgeUnique(createDomains.map(\.rawValue))
        listDomains = try o.tokens("list_domains", min: 0, max: 5)
        try bridgeUnique(listDomains.map(\.rawValue))
        objects = try o.list("objects", min: 0, max: 256)
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "create_domains", value: bridgeTokens(createDomains)))
        fields.append(.init(key: "list_domains", value: bridgeTokens(listDomains)))
        fields.append(.init(key: "objects", value: .values(objects)))
        return .object(fields)
    }
}

public struct AgentBridgeOrigin: Codable, Equatable, Sendable, BridgeValueCodable {
    public let origin: AgentBridgeOriginOrigin
    public let pointer: String
    public let revision: Int64
    public init(origin: AgentBridgeOriginOrigin, pointer: String, revision: Int64) {
        self.origin = origin
        self.pointer = pointer
        self.revision = revision
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["pointer", "origin", "revision"], optional: [])
        origin = try o.token("origin")
        pointer = try o.text("pointer", min: 1, max: 256)
        revision = try o.int("revision", min: 0, max: 2147483647)
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "origin", value: .string(origin.rawValue)))
        fields.append(.init(key: "pointer", value: .string(pointer)))
        fields.append(.init(key: "revision", value: .int(revision)))
        return .object(fields)
    }
}

public struct AgentBridgeRevision: Codable, Equatable, Sendable, BridgeValueCodable {
    public let domain: AgentBridgeRevisionDomain
    public let objectId: AgentBridgeUUID
    public let revision: Int64
    public let sha256: AgentBridgeDigest
    public init(domain: AgentBridgeRevisionDomain, objectId: AgentBridgeUUID, revision: Int64, sha256: AgentBridgeDigest) {
        self.domain = domain
        self.objectId = objectId
        self.revision = revision
        self.sha256 = sha256
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["domain", "object_id", "revision", "sha256"], optional: [])
        domain = try o.token("domain")
        objectId = try o.value("object_id")
        revision = try o.int("revision", min: 1, max: 2147483647)
        sha256 = try o.value("sha256")
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "domain", value: .string(domain.rawValue)))
        fields.append(.init(key: "object_id", value: objectId.bridgeJSON))
        fields.append(.init(key: "revision", value: .int(revision)))
        fields.append(.init(key: "sha256", value: sha256.bridgeJSON))
        return .object(fields)
    }
}

public struct AgentBridgeZeroEffects: Codable, Equatable, Sendable, BridgeValueCodable {
    public init() {
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["health_reads", "earliest_date_reads", "content_preview_reads", "output_writes", "quota_consumed", "settings_mutations", "credential_enrollments", "wake_enrollments"], optional: [])
        try o.constant("content_preview_reads", .int(0))
        try o.constant("credential_enrollments", .int(0))
        try o.constant("earliest_date_reads", .int(0))
        try o.constant("health_reads", .int(0))
        try o.constant("output_writes", .int(0))
        try o.constant("quota_consumed", .int(0))
        try o.constant("settings_mutations", .int(0))
        try o.constant("wake_enrollments", .int(0))
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "content_preview_reads", value: .int(0)))
        fields.append(.init(key: "credential_enrollments", value: .int(0)))
        fields.append(.init(key: "earliest_date_reads", value: .int(0)))
        fields.append(.init(key: "health_reads", value: .int(0)))
        fields.append(.init(key: "output_writes", value: .int(0)))
        fields.append(.init(key: "quota_consumed", value: .int(0)))
        fields.append(.init(key: "settings_mutations", value: .int(0)))
        fields.append(.init(key: "wake_enrollments", value: .int(0)))
        return .object(fields)
    }
}

public struct AgentBridgeArtifact: Codable, Equatable, Sendable, BridgeValueCodable {
    public let artifactId: AgentBridgeUUID
    public let byteCount: Int64
    public let mediaType: AgentBridgeArtifactMediaType
    public let profile: AgentBridgeArtifactProfile
    public let relativePath: AgentBridgePath
    public let sha256: AgentBridgeDigest
    public let writeMode: AgentBridgeArtifactWriteMode
    public init(artifactId: AgentBridgeUUID, byteCount: Int64, mediaType: AgentBridgeArtifactMediaType, profile: AgentBridgeArtifactProfile, relativePath: AgentBridgePath, sha256: AgentBridgeDigest, writeMode: AgentBridgeArtifactWriteMode) {
        self.artifactId = artifactId
        self.byteCount = byteCount
        self.mediaType = mediaType
        self.profile = profile
        self.relativePath = relativePath
        self.sha256 = sha256
        self.writeMode = writeMode
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["artifact_id", "relative_path", "byte_count", "sha256", "write_mode", "media_type", "profile"], optional: [])
        artifactId = try o.value("artifact_id")
        byteCount = try o.int("byte_count", min: 0, max: 1099511627776)
        mediaType = try o.token("media_type")
        profile = try o.token("profile")
        relativePath = try o.value("relative_path")
        sha256 = try o.value("sha256")
        writeMode = try o.token("write_mode")
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "artifact_id", value: artifactId.bridgeJSON))
        fields.append(.init(key: "byte_count", value: .int(byteCount)))
        fields.append(.init(key: "media_type", value: .string(mediaType.rawValue)))
        fields.append(.init(key: "profile", value: .string(profile.rawValue)))
        fields.append(.init(key: "relative_path", value: relativePath.bridgeJSON))
        fields.append(.init(key: "sha256", value: sha256.bridgeJSON))
        fields.append(.init(key: "write_mode", value: .string(writeMode.rawValue)))
        return .object(fields)
    }
}

public struct AgentBridgeArtifactManifestBranchStatuses: Codable, Equatable, Sendable, BridgeValueCodable {
    public let recordCount: Int64
    public let selectorId: AgentBridgeID
    public let status: AgentBridgeArtifactManifestBranchStatusesStatus
    public init(recordCount: Int64, selectorId: AgentBridgeID, status: AgentBridgeArtifactManifestBranchStatusesStatus) {
        self.recordCount = recordCount
        self.selectorId = selectorId
        self.status = status
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["selector_id", "status", "record_count"], optional: [])
        recordCount = try o.int("record_count", min: 0, max: 2147483647)
        selectorId = try o.value("selector_id")
        status = try o.token("status")
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "record_count", value: .int(recordCount)))
        fields.append(.init(key: "selector_id", value: selectorId.bridgeJSON))
        fields.append(.init(key: "status", value: .string(status.rawValue)))
        return .object(fields)
    }
}

public struct AgentBridgeQueryCatalogFeatureStatuses: Codable, Equatable, Sendable, BridgeValueCodable {
    public let feature: AgentBridgeID
    public let status: AgentBridgeQueryCatalogFeatureStatusesStatus
    public init(feature: AgentBridgeID, status: AgentBridgeQueryCatalogFeatureStatusesStatus) {
        self.feature = feature
        self.status = status
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["feature", "status"], optional: [])
        feature = try o.value("feature")
        status = try o.token("status")
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "feature", value: feature.bridgeJSON))
        fields.append(.init(key: "status", value: .string(status.rawValue)))
        return .object(fields)
    }
}

public struct AgentBridgeCoverage: Codable, Equatable, Sendable, BridgeValueCodable {
    public let daysConsidered: Int64
    public let daysWithValues: Int64
    public let history: AgentBridgeCoverageHistory
    public let missing: [AgentBridgeCoverageMissing]
    public let missingCount: Int64
    public let missingTruncated: Bool
    public let status: AgentBridgeCoverageStatus
    public init(daysConsidered: Int64, daysWithValues: Int64, history: AgentBridgeCoverageHistory, missing: [AgentBridgeCoverageMissing], missingCount: Int64, missingTruncated: Bool, status: AgentBridgeCoverageStatus) {
        self.daysConsidered = daysConsidered
        self.daysWithValues = daysWithValues
        self.history = history
        self.missing = missing
        self.missingCount = missingCount
        self.missingTruncated = missingTruncated
        self.status = status
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["status", "days_considered", "days_with_values", "missing_count", "missing_truncated", "missing", "history"], optional: [])
        daysConsidered = try o.int("days_considered", min: 0, max: 366000)
        daysWithValues = try o.int("days_with_values", min: 0, max: 366000)
        history = try o.value("history")
        missing = try o.list("missing", min: 0, max: 64)
        missingCount = try o.int("missing_count", min: 0, max: 2147483647)
        missingTruncated = try o.bool("missing_truncated")
        status = try o.token("status")
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "days_considered", value: .int(daysConsidered)))
        fields.append(.init(key: "days_with_values", value: .int(daysWithValues)))
        fields.append(.init(key: "history", value: history.bridgeJSON))
        fields.append(.init(key: "missing", value: .values(missing)))
        fields.append(.init(key: "missing_count", value: .int(missingCount)))
        fields.append(.init(key: "missing_truncated", value: .bool(missingTruncated)))
        fields.append(.init(key: "status", value: .string(status.rawValue)))
        return .object(fields)
    }
}

public struct AgentBridgeCatalogItem: Codable, Equatable, Sendable, BridgeValueCodable {
    public let availability: AgentBridgeCatalogItemAvailability
    public let evidenceValueSupport: Bool
    public let featureGate: String
    public let metricId: AgentBridgeID
    public let nativeRecordType: AgentBridgeNativeType?
    public let ownerRule: AgentBridgeCatalogItemOwnerRule
    public let registryEquivalence: AgentBridgeCatalogItemRegistryEquivalence
    public let sourceStatistic: String
    public let statistics: [AgentBridgeCatalogItemStatistics]
    public let targetOrReason: String
    public let unit: String
    public init(availability: AgentBridgeCatalogItemAvailability, evidenceValueSupport: Bool, featureGate: String, metricId: AgentBridgeID, nativeRecordType: AgentBridgeNativeType? = nil, ownerRule: AgentBridgeCatalogItemOwnerRule, registryEquivalence: AgentBridgeCatalogItemRegistryEquivalence, sourceStatistic: String, statistics: [AgentBridgeCatalogItemStatistics], targetOrReason: String, unit: String) {
        self.availability = availability
        self.evidenceValueSupport = evidenceValueSupport
        self.featureGate = featureGate
        self.metricId = metricId
        self.nativeRecordType = nativeRecordType
        self.ownerRule = ownerRule
        self.registryEquivalence = registryEquivalence
        self.sourceStatistic = sourceStatistic
        self.statistics = statistics
        self.targetOrReason = targetOrReason
        self.unit = unit
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["type", "metric_id", "registry_equivalence", "unit", "statistics", "source_statistic", "owner_rule", "availability", "target_or_reason", "feature_gate", "evidence_value_support"], optional: ["native_record_type"])
        availability = try o.token("availability")
        evidenceValueSupport = try o.bool("evidence_value_support")
        featureGate = try o.text("feature_gate", min: 0, max: 128)
        metricId = try o.value("metric_id")
        nativeRecordType = o.has("native_record_type") ? try o.value("native_record_type") : nil
        ownerRule = try o.token("owner_rule")
        registryEquivalence = try o.token("registry_equivalence")
        sourceStatistic = try o.text("source_statistic", min: 1, max: 128)
        statistics = try o.tokens("statistics", min: 1, max: 7)
        try bridgeUnique(statistics.map(\.rawValue))
        targetOrReason = try o.text("target_or_reason", min: 1, max: 256)
        try o.constant("type", .string("catalog_metric"))
        unit = try o.text("unit", min: 1, max: 32)
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "availability", value: .string(availability.rawValue)))
        fields.append(.init(key: "evidence_value_support", value: .bool(evidenceValueSupport)))
        fields.append(.init(key: "feature_gate", value: .string(featureGate)))
        fields.append(.init(key: "metric_id", value: metricId.bridgeJSON))
        if let nativeRecordType { fields.append(.init(key: "native_record_type", value: nativeRecordType.bridgeJSON)) }
        fields.append(.init(key: "owner_rule", value: .string(ownerRule.rawValue)))
        fields.append(.init(key: "registry_equivalence", value: .string(registryEquivalence.rawValue)))
        fields.append(.init(key: "source_statistic", value: .string(sourceStatistic)))
        fields.append(.init(key: "statistics", value: bridgeTokens(statistics)))
        fields.append(.init(key: "target_or_reason", value: .string(targetOrReason)))
        fields.append(.init(key: "type", value: .string("catalog_metric")))
        fields.append(.init(key: "unit", value: .string(unit)))
        return .object(fields)
    }
}

public struct AgentBridgeControlReadScopeObjects: Codable, Equatable, Sendable, BridgeValueCodable {
    public let domain: AgentBridgeControlReadScopeObjectsDomain
    public let objectId: AgentBridgeUUID
    public init(domain: AgentBridgeControlReadScopeObjectsDomain, objectId: AgentBridgeUUID) {
        self.domain = domain
        self.objectId = objectId
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["domain", "object_id"], optional: [])
        domain = try o.token("domain")
        objectId = try o.value("object_id")
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "domain", value: .string(domain.rawValue)))
        fields.append(.init(key: "object_id", value: objectId.bridgeJSON))
        return .object(fields)
    }
}

public struct AgentBridgeCoverageHistory: Codable, Equatable, Sendable, BridgeValueCodable {
    public let boundary: AgentBridgeDate?
    public let featureStatus: AgentBridgeCoverageHistoryFeatureStatus
    public let state: AgentBridgeCoverageHistoryState
    public init(boundary: AgentBridgeDate? = nil, featureStatus: AgentBridgeCoverageHistoryFeatureStatus, state: AgentBridgeCoverageHistoryState) {
        self.boundary = boundary
        self.featureStatus = featureStatus
        self.state = state
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["state", "feature_status"], optional: ["boundary"])
        boundary = o.has("boundary") ? try o.value("boundary") : nil
        featureStatus = try o.token("feature_status")
        state = try o.token("state")
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        if let boundary { fields.append(.init(key: "boundary", value: boundary.bridgeJSON)) }
        fields.append(.init(key: "feature_status", value: .string(featureStatus.rawValue)))
        fields.append(.init(key: "state", value: .string(state.rawValue)))
        return .object(fields)
    }
}

public struct AgentBridgeCoverageMissing: Codable, Equatable, Sendable, BridgeValueCodable {
    public let metricId: AgentBridgeID
    public let range: AgentBridgeDateRange
    public let reason: AgentBridgeCoverageMissingReason
    public init(metricId: AgentBridgeID, range: AgentBridgeDateRange, reason: AgentBridgeCoverageMissingReason) {
        self.metricId = metricId
        self.range = range
        self.reason = reason
    }
    init(bridgeJSON: BridgeJSON) throws {
        let o = try BridgeObject(bridgeJSON, ["range", "metric_id", "reason"], optional: [])
        metricId = try o.value("metric_id")
        range = try o.value("range")
        reason = try o.token("reason")
    }
    var bridgeJSON: BridgeJSON {
        var fields: [BridgeJSON.Member] = []
        fields.append(.init(key: "metric_id", value: metricId.bridgeJSON))
        fields.append(.init(key: "range", value: range.bridgeJSON))
        fields.append(.init(key: "reason", value: .string(reason.rawValue)))
        return .object(fields)
    }
}
