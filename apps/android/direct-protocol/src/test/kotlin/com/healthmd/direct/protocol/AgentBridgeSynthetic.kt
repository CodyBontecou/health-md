package com.healthmd.direct.protocol

import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive

/** Independent Kotlin constructors, never hydrated from conformance.json. Synthetic, not issued. */
internal object AgentBridgeSynthetic {
    fun id(n: Int): String = "00000000-0000-4000-8000-" + n.toString(16).padStart(12, '0')
    val zero = "0".repeat(64)
    val one = "1".repeat(64)
    val issued = "2000-01-03T00:00:00Z"
    val expires = "2000-01-03T00:10:00Z"
    val peer = AgentBridgePeer(id(2), AgentBridgePlatform.ANDROID, id(1))
    val destination = AgentBridgeDestination(id(3), id(2), one, 1)
    val budgets = AgentBridgeBudgets(600, 3600, 366000, 120, 1048576, 1000, 67108864)
    val native = AgentBridgeAuthorityReference(id(7), 1, "2".repeat(64), AgentBridgeIssuer.NATIVE_SOURCE)
    val host = AgentBridgeAuthorityReference(id(13), 1, "3".repeat(64), AgentBridgeIssuer.AUTHORIZED_HOST)
    val refs = AgentBridgeAuthorityReferences(host, native)
    val dates = AgentBridgeDatesExact(AgentBridgeRange("2000-01-02", "2000-01-01"), "exact")
    val selection = AgentBridgeSelection(false, emptyList(), listOf("steps"), emptyList(), listOf("health_connect"))
    val capture = AgentBridgeCapture(AgentBridgeCompatibilityDetail.SUMMARY, AgentBridgeArchiveNone("none"), selection)
    val settings = AgentBridgeOutputSettings(
        dailyNotes = AgentBridgeDailyNotes(false, false, "{date}", "notes/{year}", false, emptyList()),
        dictionary = AgentBridgeDictionaryNone("none"), filenameTemplate = "{date}", folderTemplate = "{year}",
        formats = listOf(AgentBridgeFormat.JSON),
        individualEntries = AgentBridgeIndividualEntries(false, false, "{date}-{record_id}", "entries/{year}", emptyList()),
        outputProfile = AgentBridgeOutputProfile.ANDROID_ANALYTICAL_V5, packaging = AgentBridgePackagingLooseFiles("loose_files"),
        presentation = AgentBridgePresentation(AgentBridgePresentationDisplayUnits.METRIC,
            AgentBridgeFrontmatter(emptyList(), emptyList(), true, true), true, true, "en-US", "canonical",
            AgentBridgeMarkdown("", emptyList(), AgentBridgeMarkdownStyle.TABLES)),
        subfolder = "", writeMode = AgentBridgeWriteMode.OVERWRITE,
    )
    val intent = AgentBridgeGeneratedIntent("Etc/UTC", capture, dates, destination, id(4), peer,
        AgentBridgeGeneratedIntentProduct("generated_files"), "healthmd.agent_export_intent", 1,
        AgentBridgeSettingsPolicyExplicit(settings, "explicit"), "UTC")
    val discoveryRequest = AgentBridgeDiscoveryRequest(peer, id(100), "healthmd.agent_discovery_request", 1)
    val discovery: AgentBridgeDiscovery = AgentBridgeDiscovery(
        authorityReferences = listOf(native), budgets = budgets, capabilityRevision = 1, capabilitySha256 = zero,
        configurationProtection = AgentBridgeDiscoveryConfigurationProtection.LOCKED, controlOperations = emptyList(),
        entitlement = AgentBridgeDiscoveryEntitlement.REQUIRED, expiresAt = expires,
        features = listOf(AgentBridgeDiscoveryFeaturesItem.BOUND_EXECUTION, AgentBridgeDiscoveryFeaturesItem.EXPLICIT_SETTINGS,
            AgentBridgeDiscoveryFeaturesItem.ZERO_HEALTH_PLAN), issuedAt = issued,
        lifecycle = AgentBridgeDiscoveryLifecycle.ANDROID_USER_STARTED_SERVICE_AFTER_FIRST_UNLOCK,
        nativeGrants = AgentBridgeDiscoveryNativeGrants.UNVERIFIED, outputProfiles = listOf(AgentBridgeOutputProfile.ANDROID_ANALYTICAL_V5),
        outputSupport = AgentBridgeOutputSupport(listOf(AgentBridgeCompatibilityDetail.SUMMARY), listOf(AgentBridgeFormat.JSON),
            4096, 4096, listOf(AgentBridgeOutputSupportNativeArchiveProductsItem.NONE),
            listOf(AgentBridgeOutputSupportPathTokensItem.DATE, AgentBridgeOutputSupportPathTokensItem.YEAR),
            listOf("/filename_template", "/folder_template", "/formats"), listOf(AgentBridgeWriteMode.OVERWRITE)),
        peer = peer, projectionCatalogSha256 = zero, projectionProducts = emptyList(), queryCatalogSha256 = zero,
        queryOperations = emptyList(), requestId = id(100), requiredActions = listOf(AgentBridgeDiscoveryRequiredActionsItem.GRANT_HEALTH_ACCESS),
        schema = "healthmd.agent_discovery", schemaVersion = 1,
        settingsPolicies = listOf(AgentBridgeDiscoverySettingsPoliciesItem.EXPLICIT), sourceCalendarTimezone = "Etc/UTC",
    ).let { it.copy(capabilitySha256 = AgentBridgeValidation.capabilityDigest(it)) }
    val plan: AgentBridgeGeneratedPlan = makePlan()
    val binding = AgentBridgeValidation.bindingFor(plan)
    val planRequest = AgentBridgePlanRequest(native.authorityId, 1, discovery.capabilitySha256, host, intent, id(40), "healthmd.agent_plan_request", 1)
    val approvalRequest = AgentBridgeApprovalRequest(binding, plan.planId, id(41), "healthmd.agent_approval_request", 1)
    val approval = AgentBridgeApproval(id(8), "2000-01-03T00:00:30Z", native.authorityId, binding,
        listOf(AgentBridgeApprovalRightsItem.EXPORT_EXECUTE), "healthmd.agent_approval", 1)
    val execute = AgentBridgeExecuteRequest(approval, id(9), id(10), plan, id(11), "healthmd.agent_execute_request", 1)
    val requestDigest = AgentBridgeCodec.fingerprint(execute)
    val receipt = AgentBridgeExecutionReceipt(2, binding, 2, expires, "4".repeat(64), id(10), "5".repeat(64),
        requestDigest, "healthmd.agent_execution_receipt", 1, true, AgentBridgeExecutionReceiptStatus.COMPLETE)
    val cancel = AgentBridgeCancelRequest(approval.approvalId, native.authorityId, id(10), peer,
        requestDigest, "healthmd.agent_cancel_request", 1)
    val resume = AgentBridgeResumeRequest(binding, 2, destination, receipt.frontierSha256, id(10),
        receipt.manifestSha256, peer, requestDigest, "healthmd.agent_resume_request", 1)
    val manifest = AgentBridgeArtifactManifest(listOf(AgentBridgeArtifact(id(12), 42,
        AgentBridgeArtifactMediaType.APPLICATION_JSON, AgentBridgeArtifactProfile.ANDROID_ANALYTICAL_V5,
        "2000/2000-01-01.json", one, AgentBridgeWriteMode.OVERWRITE)), binding,
        listOf(AgentBridgeArtifactManifestBranchStatusesItem(1, "steps", AgentBridgeArtifactManifestBranchStatusesItemStatus.SUCCESS)),
        AgentBridgeArtifactManifestCaptureStatus.COMPLETE, id(10), requestDigest, "healthmd.agent_artifact_manifest", 1)
    val commit = AgentBridgeCommitReceipt(one, id(12), zero, zero, destination, one, id(10), receipt.manifestSha256,
        peer, "2000/2000-01-01.json", requestDigest, "healthmd.agent_commit_receipt", 1,
        AgentBridgeCommitReceiptStatus.COMMITTED, AgentBridgeWriteMode.OVERWRITE).let { value ->
        val fields = setOf("job_id", "artifact_id", "destination", "request_sha256", "manifest_sha256",
            "relative_path", "write_mode", "input_sha256", "before_sha256", "after_sha256")
        value.copy(commitKey = AgentBridgeCodec.digest(JsonObject(AgentBridgeCodec.tree(value).filterKeys { it in fields })))
    }
    val exact = AgentBridgeExactTime(946684800L, 123456789, AgentBridgeExactTimePrecision.SOURCE_NANOSECONDS, null)
    val hcIdentity = AgentBridgeNativeIdentityHealthConnect(
        clientRecordId = "native-client", clientRecordVersion = Long.MAX_VALUE,
        identityKind = AgentBridgeNativeIdentityAppleHealthIdentityKind.NATIVE, lastModified = exact,
        metadataStatus = AgentBridgeNativeIdentityHealthConnectMetadataStatus(AgentBridgeClientIdAvailability.AVAILABLE,
            AgentBridgeMetadataAvailability.AVAILABLE, AgentBridgeMetadataAvailability.AVAILABLE),
        origin = "synthetic.origin", providerId = "health_connect", recordId = "native-id",
        recordType = "androidx.health.connect.client.records.StepsRecord", sourceId = "health_connect",
    )
    val coverage = AgentBridgeCoverage(2, 1, AgentBridgeCoverageHistory(null,
        AgentBridgeCoverageHistoryFeatureStatus.AVAILABLE, AgentBridgeCoverageHistoryState.FULL_GRANTED),
        emptyList(), 0, false, AgentBridgeCoverageStatus.COMPLETE)
    val sourceResponse = AgentBridgeQueryResponseSourceRecordListing("Etc/UTC", one, coverage, one, expires,
        listOf(AgentBridgeEvidenceItem(exact, one, hcIdentity, listOf("steps"), exact, "evidence", emptyList())),
        0, emptyList(), false, operation = "source_record_listing", peer = peer, providerId = "health_connect",
        querySha256 = one, requestId = id(50), schema = "healthmd.source_query_response", schemaVersion = 1,
        sourceDescriptorCount = 0, sourceDescriptors = emptyList(), sourceDescriptorsTruncated = false,
        sourceId = AgentBridgeQueryCatalogSourceId.HEALTH_CONNECT)
    val documents: List<AgentBridgeDocument> = listOf(discoveryRequest, discovery, intent, planRequest, plan,
        approvalRequest, approval, execute, receipt, cancel, resume, manifest, commit, sourceResponse)

    private fun makePlan(): AgentBridgeGeneratedPlan {
        val settingLeaves = listOf(
            "daily_notes/create_if_missing", "daily_notes/enabled", "daily_notes/filename_template", "daily_notes/folder_template",
            "daily_notes/only", "daily_notes/section_ids", "dictionary/type", "filename_template", "folder_template", "formats",
            "individual_entries/category_folders", "individual_entries/enabled", "individual_entries/filename_template",
            "individual_entries/folder_template", "individual_entries/metric_ids", "output_profile", "packaging/type",
            "presentation/display_units", "presentation/frontmatter/custom_fields", "presentation/frontmatter/enabled_field_ids",
            "presentation/frontmatter/include_capture_diagnostics", "presentation/frontmatter/include_units", "presentation/group_by_category",
            "presentation/include_metadata", "presentation/locale", "presentation/machine_units", "presentation/markdown/custom_template",
            "presentation/markdown/placeholder_ids", "presentation/markdown/style", "subfolder", "write_mode",
        ).map { "/effective_settings/$it" }
        val captureLeaves = listOf("compatibility_detail", "native_archive/type", "selection/all_metrics", "selection/category_ids",
            "selection/metric_ids", "selection/provider_ids", "selection/source_ids").map { "/capture_scope/$it" }
        val origins = (settingLeaves + captureLeaves + "/calendar_timezone" + "/resolved_dates").sorted().map {
            AgentBridgeOrigin(if (it == "/resolved_dates") AgentBridgeOriginOrigin.RESOLVED_CALENDAR else AgentBridgeOriginOrigin.REQUEST, it, 0)
        }
        val scope = JsonObject(mapOf("dates" to AgentBridgeCodec.tree(AgentBridgeDatesSerializer, dates),
            "calendar_timezone" to JsonPrimitive("Etc/UTC"), "capture_scope" to AgentBridgeCodec.tree(AgentBridgeCapture.serializer(), capture),
            "metric_ids" to JsonArray(listOf(JsonPrimitive("steps"))), "product" to AgentBridgeCodec.tree(AgentBridgeGeneratedIntentProduct.serializer(), intent.product)))
        return AgentBridgeGeneratedPlan(refs, discovery.capabilitySha256, settings, expires, intent, issued,
            emptyList(), origins, AgentBridgeGeneratedPlanPathPrediction.EXACT_REQUESTED_DAYS, id(5), zero,
            listOf("2000/2000-01-01.json", "2000/2000-01-02.json"), emptyList(), dates, listOf("steps"), emptyList(),
            "healthmd.agent_export_plan", 1, AgentBridgeCodec.digest(scope),
            AgentBridgeCodec.digest(AgentBridgeCodec.tree(AgentBridgeOutputSettings.serializer(), settings)),
            AgentBridgeZeroControlEffects(0, 0, 0, 0, 0, 0, 0, 0)).let { it.copy(planSha256 = AgentBridgeValidation.planDigest(it)) }
    }
}
