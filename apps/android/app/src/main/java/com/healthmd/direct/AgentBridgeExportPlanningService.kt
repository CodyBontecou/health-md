package com.healthmd.direct

import com.healthmd.direct.protocol.*
import java.time.Clock
import java.time.Instant
import java.time.ZoneOffset
import java.util.UUID
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*

/** A native adapter must return an atomic configuration/readiness snapshot only. It must NOT perform
 * Health Connect/earliest-date/preview/provider/quota/output/wake/credential work. Catalog revision
 * changes track installed configuration support. Saved/profile snapshots are exact IDs, never defaults.
 * This service structurally has no capture, provider, quota, exporter writer, settings writer or wake
 * dependency. That is source-service qualification, NOT instrumentation of an installed TCP route. */
internal fun interface AgentBridgeExportPlanningConfigurationReader {
    fun readConfiguration(): AgentBridgeExportPlanningConfiguration
}
internal data class AgentBridgeExportPlanningConfiguration(
    val settings: AgentBridgeRequestSettingsInputs,
    val deviceSettingsObjectId: String,
    val sourceCalendarTimezone: String,
    val configurationProtection: AgentBridgeDiscoveryConfigurationProtection,
    val nativeGrants: AgentBridgeDiscoveryNativeGrants,
    val entitlement: AgentBridgeDiscoveryEntitlement,
    val userStartedServiceActive: Boolean,
    val firstUnlockComplete: Boolean,
)

/** Production callable v4 source planning seam. Intentionally NOT wired to DirectCliCoordinator,
 * hello/TCP/FGS/native UI. No permission issuance from descriptions, no generic JSON/control dispatcher,
 * no v4 advertisement, capture, execute/query/cancel/resume or host root/authority verification.
 * The host independently checks its OWN registered root and grant; this source only pins that opaque
 * reference/destination and verifies its OWN native record. Persist before returning any issued plan. */
internal class AgentBridgeExportPlanningService(
    private val store: AgentBridgeExportAuthorityStore,
    private val configuration: AgentBridgeExportPlanningConfigurationReader,
    private val clock: Clock,
) {
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = false }

    fun handleEnvelope(bytes: ByteArray, authenticated: AgentBridgeExportAuthenticatedPeer,
        negotiation: AgentBridgeNegotiation): ByteArray {
        require(negotiation.baseApplication == 2 && !negotiation.appleQueryExtension, AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val message = AgentBridgeCodec.decodeEnvelope(bytes, negotiation)
        // Remote identities/descriptions are not native context. Canonical bytes are the replay identity.
        require(bytes.contentEquals(AgentBridgeCodec.encodeEnvelope(message, negotiation)), AgentBridgeErrorCode.INVALID_REQUEST)
        val response = try {
            when (message.type) {
                "discovery_request" -> AgentBridgeMessage("discovery_response", discover(authenticated, message.payload as AgentBridgeDiscoveryRequest))
                "plan_request" -> AgentBridgeMessage("plan_response", plan(authenticated, message.payload as AgentBridgePlanRequest))
                "approval_request" -> AgentBridgeMessage("approval_response", approval(authenticated, message.payload as AgentBridgeApprovalRequest))
                else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
            }
        } catch (failure: AgentBridgeException) {
            val id = json.encodeToJsonElement(AgentBridgeDocumentSerializer, message.payload).jsonObject["request_id"]?.jsonPrimitive?.content
                ?: throw failure
            AgentBridgeMessage("rejected", AgentBridgeError(failure.code, id, failure.code == AgentBridgeErrorCode.BUSY,
                "healthmd.agent_error", 1))
        }
        val encoded = AgentBridgeCodec.encodeEnvelope(response, negotiation)
        val responsePeer = when (val payload = response.payload) {
            is AgentBridgeDiscovery -> payload.peer
            is AgentBridgeGeneratedPlan -> payload.intent.peer
            is AgentBridgeApproval -> payload.binding.peer
            else -> null // Fixed rejection conveys no private authority/configuration.
        }
        if (responsePeer != null) peer(authenticated, responsePeer)
        return encoded
    }

    fun discover(authenticated: AgentBridgeExportAuthenticatedPeer, value: AgentBridgeDiscoveryRequest): AgentBridgeDiscovery {
        val request = AgentBridgeCodec.decode(AgentBridgeCodec.encode(value)) as AgentBridgeDiscoveryRequest
        val peer = peer(authenticated, request.peer)
        return access(authenticated, peer) { tx -> discovery(request.requestId, peer, configuration.readConfiguration(), tx, now()) }
    }

    fun plan(authenticated: AgentBridgeExportAuthenticatedPeer, value: AgentBridgePlanRequest): AgentBridgeGeneratedPlan {
        val requestBytes = AgentBridgeCodec.encode(value)
        val request = AgentBridgeCodec.decode(requestBytes) as AgentBridgePlanRequest
        val intent = request.intent as? AgentBridgeGeneratedIntent ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val peer = peer(authenticated, intent.peer)
        return access(authenticated, peer) { transaction ->
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val parent = tx.grant(peer, request.authorityId, request.authorityRevision, now())
            val existing = tx.issuedFor(peer, request.requestId)
            if (existing != null) {
                require(existing.requestCanonical == requestBytes.decodeToString(), AgentBridgeErrorCode.BINDING_CHANGED)
                val snapshot = configuration.readConfiguration()
                validateCurrent(existing, tx, snapshot, peer, now())
                return@access existing.plan() // Never slide expiry, replace settings or create a new plan on retry.
            }
            val snapshot = configuration.readConfiguration()
            requirePresence(snapshot)
            val issued = now()
            val capabilities = discovery(request.requestId, peer, snapshot, tx, issued)
            require(request.capabilitySha256 == capabilities.capabilitySha256, AgentBridgeErrorCode.BINDING_CHANGED)
            val result = AgentBridgeRequestSettingsResolver.resolveWithOutput(intent, snapshot.settings, Clock.fixed(issued, ZoneOffset.UTC))
            val resolution = result.resolution
            require(resolution.predictedRelativePaths.size <= MAX_ARTIFACTS, AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED)
            val expires = minOf(issued.plusSeconds(600), Instant.parse(parent.expiresAt))
            require(expires > issued, AgentBridgeErrorCode.PLAN_EXPIRED)
            val refs = AgentBridgeAuthorityReferences(request.hostAuthorityReference, AgentBridgeExportAuthorityStore.reference(parent))
            val settingsTree = json.encodeToJsonElement(result.effectiveOutput)
            val settingsSha256 = digest(settingsTree)
            val outputOrigin = when (resolution.settingsOrigin) {
                AgentBridgeRequestSettingsOrigin.REQUEST -> AgentBridgeOriginOrigin.REQUEST
                AgentBridgeRequestSettingsOrigin.PROFILE -> AgentBridgeOriginOrigin.PROFILE
                AgentBridgeRequestSettingsOrigin.SAVED_DEVICE_SETTINGS -> AgentBridgeOriginOrigin.SAVED_DEVICE_SETTINGS
            }
            val pins = when (resolution.settingsOrigin) {
                AgentBridgeRequestSettingsOrigin.REQUEST -> emptyList()
                AgentBridgeRequestSettingsOrigin.PROFILE -> listOf(AgentBridgeRevision(AgentBridgeRevisionDomain.NATIVE_PROFILE,
                    requireNotNull(resolution.profileId), requireNotNull(resolution.settingsRevision), settingsSha256))
                AgentBridgeRequestSettingsOrigin.SAVED_DEVICE_SETTINGS -> listOf(AgentBridgeRevision(AgentBridgeRevisionDomain.DEVICE_SETTINGS,
                    snapshot.deviceSettingsObjectId, requireNotNull(resolution.settingsRevision), settingsSha256))
            }
            val origins = leaves(settingsTree, "/effective_settings").map { AgentBridgeOrigin(outputOrigin, it, resolution.settingsRevision ?: 0) } +
                leaves(json.encodeToJsonElement(intent.captureScope), "/capture_scope").map { AgentBridgeOrigin(AgentBridgeOriginOrigin.REQUEST, it, 0) } +
                listOf(AgentBridgeOrigin(AgentBridgeOriginOrigin.REQUEST, "/calendar_timezone", 0),
                    AgentBridgeOrigin(AgentBridgeOriginOrigin.RESOLVED_CALENDAR, "/resolved_dates", 0))
            val logical = resolution.dates is AgentBridgeDatesAllAvailable
            val draft = AgentBridgeGeneratedPlan(refs, capabilities.capabilitySha256, result.effectiveOutput, expires.toString(), intent,
                issued.toString(), if (logical) listOf("history_bounds_unresolved") else emptyList(), origins.sortedBy { it.pointer },
                if (logical) AgentBridgeGeneratedPlanPathPrediction.TEMPLATE_ONLY_ALL_AVAILABLE else AgentBridgeGeneratedPlanPathPrediction.EXACT_REQUESTED_DAYS,
                UUID.randomUUID().toString(), ZERO, resolution.predictedRelativePaths, actions(snapshot), resolution.dates,
                resolution.selection.map { it.semanticId }, pins, "healthmd.agent_export_plan", 1,
                scopeDigest(intent, resolution), settingsSha256, AgentBridgeZeroControlEffects(0, 0, 0, 0, 0, 0, 0, 0))
            val plan = draft.copy(planSha256 = AgentBridgeValidation.planDigest(draft))
            val nativeScope = AgentBridgeValidation.deriveExportAuthority(parent, plan, issued, consent(snapshot), snapshot.entitlement)
            // The supplied host reference is pinned, NOT verified/issued by this source.
            tx.issue(AgentBridgeExportIssuedPlanRecord(requestBytes.decodeToString(), AgentBridgeCodec.encode(plan).decodeToString(),
                canonical(json.encodeToString(resolution)).decodeToString(), AgentBridgeCodec.encode(nativeScope).decodeToString(), configurationDigest(snapshot)))
            plan
        }
    }

    fun approval(authenticated: AgentBridgeExportAuthenticatedPeer, value: AgentBridgeApprovalRequest): AgentBridgeApproval {
        val request = AgentBridgeCodec.decode(AgentBridgeCodec.encode(value)) as AgentBridgeApprovalRequest
        val peer = peer(authenticated, request.binding.peer)
        return access(authenticated, peer) { transaction ->
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val record = tx.plan(peer, request.planId)
            AgentBridgeValidation.validateApprovalBinding(request, record.plan())
            val snapshot = configuration.readConfiguration()
            validateCurrent(record, tx, snapshot, peer, now())
            requireReady(snapshot, record.plan())
            tx.decision(request.planId) ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
        }
    }

    /** Local native/human API ONLY; no dispatcher case can invoke it. Exact independently approved
     * decision is required even with paired trust and a valid issued binding. Does not authorize host
     * writes, register roots, change mobile settings or create export/query/configuration grants. */
    fun authorizeExactApproval(authenticated: AgentBridgeExportAuthenticatedPeer, native: AgentBridgeExportNativeAuthorization,
        planId: String, binding: AgentBridgeBinding): AgentBridgeApproval {
        val frozenBinding = (AgentBridgeCodec.decode(AgentBridgeCodec.encode(AgentBridgeApprovalRequest(binding, planId,
            UUID.randomUUID().toString(), "healthmd.agent_approval_request", 1))) as AgentBridgeApprovalRequest).binding
        val peer = peer(authenticated, frozenBinding.peer)
        return access(authenticated, peer) { transaction ->
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val record = tx.plan(peer, planId)
            require(frozenBinding == AgentBridgeValidation.bindingFor(record.plan()), AgentBridgeErrorCode.BINDING_CHANGED)
            val snapshot = configuration.readConfiguration()
            val approved = now()
            validateCurrent(record, tx, snapshot, peer, approved)
            requireReady(snapshot, record.plan())
            val parent = tx.grant(peer, frozenBinding.authorityReferences.native.authorityId, frozenBinding.authorityReferences.native.grantRevision, approved)
            require(AgentBridgeExportDelegationRightsItem.EXPORT_EXECUTE in parent.rights, AgentBridgeErrorCode.APPROVAL_REQUIRED)
            tx.decision(planId)?.let { return@access it }
            peer(authenticated, peer) // A native session can revoke/change live trust during a decision.
            native.requireDecision(AgentBridgeExportNativeDecision.ExactApproval(planId, frozenBinding))
            peer(authenticated, peer)
            val approval = AgentBridgeApproval(UUID.randomUUID().toString(), approved.toString(), parent.authorityId, frozenBinding,
                listOf(AgentBridgeApprovalRightsItem.EXPORT_EXECUTE), "healthmd.agent_approval", 1)
            tx.decide(planId, approval)
            approval
        }
    }

    private fun validateCurrent(record: AgentBridgeExportIssuedPlanRecord, tx: AgentBridgeExportAuthorityTransaction,
        snapshot: AgentBridgeExportPlanningConfiguration, peer: AgentBridgePeer, instant: Instant) {
        val plan = record.plan()
        require(instant >= Instant.parse(plan.issuedAt) && instant < Instant.parse(plan.expiresAt), AgentBridgeErrorCode.PLAN_EXPIRED)
        val ref = plan.authorityReferences.native
        val parent = tx.grant(peer, ref.authorityId, ref.grantRevision, instant)
        require(ref == AgentBridgeExportAuthorityStore.reference(parent), AgentBridgeErrorCode.APPROVAL_REQUIRED)
        requirePresence(snapshot)
        require(configurationDigest(snapshot) == record.configurationSha256, AgentBridgeErrorCode.BINDING_CHANGED)
        require(discovery(record.request().requestId, peer, snapshot, tx, instant).capabilitySha256 == plan.capabilitySha256,
            AgentBridgeErrorCode.BINDING_CHANGED)
        val resolution = json.decodeFromString<AgentBridgeRequestSettingsResolution>(record.resolutionCanonical)
        AgentBridgeRequestSettingsResolver.validateForReuse(resolution, plan.intent, snapshot.settings)
        val derived = AgentBridgeValidation.deriveExportAuthority(parent, plan, instant, consent(snapshot), snapshot.entitlement)
        require(AgentBridgeCodec.encode(derived).decodeToString() == record.nativeAuthorityCanonical, AgentBridgeErrorCode.BINDING_CHANGED)
    }

    private fun discovery(requestId: String, peer: AgentBridgePeer, snapshot: AgentBridgeExportPlanningConfiguration,
        tx: AgentBridgeExportAuthorityTransaction?, issued: Instant): AgentBridgeDiscovery {
        val draft = AgentBridgeDiscovery(tx?.references(peer, issued) ?: emptyList(), AgentBridgeBudgets(600, 3600, MAX_ARTIFACTS, 120,
            1048576, 1000, 67108864), snapshot.settings.catalog.revision, ZERO, snapshot.configurationProtection, emptyList(), snapshot.entitlement,
            issued.plusSeconds(600).toString(), listOf(AgentBridgeDiscoveryFeaturesItem.EXPLICIT_SETTINGS, AgentBridgeDiscoveryFeaturesItem.ZERO_HEALTH_PLAN),
            issued.toString(), AgentBridgeDiscoveryLifecycle.ANDROID_USER_STARTED_SERVICE_AFTER_FIRST_UNLOCK, snapshot.nativeGrants,
            listOf(AgentBridgeOutputProfile.ANDROID_FROZEN_V4), AgentBridgeOutputSupport(listOf(AgentBridgeCompatibilityDetail.SUMMARY),
                listOf(AgentBridgeFormat.JSON), MAX_ARTIFACTS, 4096, listOf(AgentBridgeOutputSupportNativeArchiveProductsItem.NONE),
                listOf(AgentBridgeOutputSupportPathTokensItem.DATE, AgentBridgeOutputSupportPathTokensItem.DAY, AgentBridgeOutputSupportPathTokensItem.MONTH,
                    AgentBridgeOutputSupportPathTokensItem.YEAR), listOf("/filename_template", "/folder_template", "/subfolder"), listOf(AgentBridgeWriteMode.OVERWRITE)),
            peer, ZERO, emptyList(), queryCatalogSha256 = ZERO, queryOperations = emptyList(), requestId = requestId,
            requiredActions = actions(snapshot).map { token -> actionEnum(token) }, schema = "healthmd.agent_discovery", schemaVersion = 1,
            settingsPolicies = listOf(AgentBridgeDiscoverySettingsPoliciesItem.EXPLICIT, AgentBridgeDiscoverySettingsPoliciesItem.PROFILE,
                AgentBridgeDiscoverySettingsPoliciesItem.SAVED_DEVICE_SETTINGS), sourceCalendarTimezone = snapshot.sourceCalendarTimezone)
        val response = draft.copy(capabilitySha256 = AgentBridgeValidation.capabilityDigest(draft))
        return AgentBridgeCodec.decode(AgentBridgeCodec.encode(response)) as AgentBridgeDiscovery
    }
    private fun <T> access(authenticated: AgentBridgeExportAuthenticatedPeer, expected: AgentBridgePeer,
        block: (AgentBridgeExportAuthorityTransaction?) -> T): T =
        store.access(fence = { peer(authenticated, expected) }, block = block).also { peer(authenticated, expected) }

    private fun peer(authenticated: AgentBridgeExportAuthenticatedPeer, wire: AgentBridgePeer): AgentBridgePeer {
        val current = authenticated.requireCurrent()
        require(current == wire, AgentBridgeErrorCode.PERMISSION_REQUIRED)
        require(current.platform == AgentBridgePlatform.ANDROID, AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        return current
    }
    private fun requirePresence(snapshot: AgentBridgeExportPlanningConfiguration) {
        require(snapshot.userStartedServiceActive && snapshot.firstUnlockComplete, AgentBridgeErrorCode.PERMISSION_REQUIRED)
    }
    private fun requireReady(configuration: AgentBridgeExportPlanningConfiguration, plan: AgentBridgeGeneratedPlan) {
        requirePresence(configuration)
        require(configuration.entitlement == AgentBridgeDiscoveryEntitlement.SATISFIED, AgentBridgeErrorCode.ENTITLEMENT_REQUIRED)
        require(configuration.nativeGrants == AgentBridgeDiscoveryNativeGrants.SATISFIED, AgentBridgeErrorCode.PERMISSION_REQUIRED)
        require(plan.requiredActions.isEmpty(), AgentBridgeErrorCode.PERMISSION_REQUIRED)
    }
    private fun actions(snapshot: AgentBridgeExportPlanningConfiguration): List<String> = buildList {
        if (!snapshot.userStartedServiceActive) add("open_mobile_app")
        if (!snapshot.firstUnlockComplete) add("unlock_mobile")
        if (snapshot.nativeGrants != AgentBridgeDiscoveryNativeGrants.SATISFIED) add("grant_health_access")
        if (snapshot.entitlement != AgentBridgeDiscoveryEntitlement.SATISFIED) add("purchase_required")
    }.sorted()
    private fun actionEnum(token: String) = when (token) {
        "open_mobile_app" -> AgentBridgeDiscoveryRequiredActionsItem.OPEN_MOBILE_APP
        "unlock_mobile" -> AgentBridgeDiscoveryRequiredActionsItem.UNLOCK_MOBILE
        "grant_health_access" -> AgentBridgeDiscoveryRequiredActionsItem.GRANT_HEALTH_ACCESS
        "purchase_required" -> AgentBridgeDiscoveryRequiredActionsItem.PURCHASE_REQUIRED
        else -> throw AgentBridgeException(AgentBridgeErrorCode.INVALID_REQUEST)
    }
    private fun consent(snapshot: AgentBridgeExportPlanningConfiguration) = if (snapshot.nativeGrants == AgentBridgeDiscoveryNativeGrants.SATISFIED)
        AgentBridgeDiscoveryEntitlement.SATISFIED else AgentBridgeDiscoveryEntitlement.REQUIRED
    private fun configurationDigest(snapshot: AgentBridgeExportPlanningConfiguration) = digest(buildJsonObject {
        put("catalog_sha256", snapshot.settings.catalog.configurationSha256)
        put("registry_sha256", snapshot.settings.catalog.registrySha256)
        put("device_settings_object_id", snapshot.deviceSettingsObjectId)
        put("source_calendar_timezone", snapshot.sourceCalendarTimezone)
        put("configuration_protection", json.encodeToJsonElement(snapshot.configurationProtection))
        put("native_grants", json.encodeToJsonElement(snapshot.nativeGrants))
        put("entitlement", json.encodeToJsonElement(snapshot.entitlement))
        put("user_started_service_active", snapshot.userStartedServiceActive)
        put("first_unlock_complete", snapshot.firstUnlockComplete)
    })
    private fun scopeDigest(intent: AgentBridgeGeneratedIntent, resolution: AgentBridgeRequestSettingsResolution) = digest(buildJsonObject {
        put("dates", json.encodeToJsonElement(AgentBridgeDatesSerializer, resolution.dates))
        put("calendar_timezone", intent.calendarTimezone)
        put("capture_scope", json.encodeToJsonElement(intent.captureScope))
        put("metric_ids", JsonArray(resolution.selection.map { JsonPrimitive(it.semanticId) }))
        put("product", json.encodeToJsonElement(intent.product))
    })
    private fun leaves(tree: JsonElement, pointer: String): List<String> = if (tree is JsonObject)
        tree.flatMap { (key, child) -> leaves(child, "$pointer/$key") } else listOf(pointer)
    private fun digest(tree: JsonElement) = AgentBridgeCodec.sha256(canonical(tree.toString()))
    private fun canonical(text: String) = AgentBridgeCodec.canonicalize(text.toByteArray())
    private fun now() = Instant.ofEpochSecond(clock.instant().epochSecond)
    private fun require(value: Boolean, code: AgentBridgeErrorCode) { if (!value) throw AgentBridgeException(code) }

    companion object {
        const val MAX_ARTIFACTS = 128 // Smaller installed planning ledger limit, not a capture quota.
        private val ZERO = "0".repeat(64)
    }
}
