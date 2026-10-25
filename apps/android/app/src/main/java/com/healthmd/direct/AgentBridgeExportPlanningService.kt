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
    // Null is metadata-only discovery. Explicit requests must not load saved settings/profiles;
    // saved/profile reads select only that exact policy. Later boundaries use issuer-owned plans.
    fun readConfiguration(policy: AgentBridgeSettingsPolicy?, catalogPublication: AgentBridgeNativeCatalogPublication?): AgentBridgeExportPlanningConfiguration
    fun readConfiguration(policy: AgentBridgeSettingsPolicy?): AgentBridgeExportPlanningConfiguration = readConfiguration(policy, null)
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
        if (responsePeer != null) recheckReturn(authenticated, responsePeer, response.payload, nativeDecision = null)
        return encoded
    }

    /** New-job preflight only, not capture authority or durable acceptance. A future adapter must
     * persist these exact bytes/fingerprint before reads and revalidate native authority at read
     * boundaries. Resume must use its immutable journal rather than rerunning this preflight. */
    fun prepareExecution(authenticated: AgentBridgeExportAuthenticatedPeer,
        supplied: AgentBridgeExecuteRequest): AgentBridgeExportExecutionPreparation {
        val bytes = AgentBridgeCodec.encode(supplied)
        val request = AgentBridgeCodec.decode(bytes) as? AgentBridgeExecuteRequest
            ?: throw AgentBridgeException(AgentBridgeErrorCode.INVALID_REQUEST)
        val plan = request.plan as? AgentBridgeGeneratedPlan
            ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val expected = authenticated.requireCurrent()
        var resolution: String? = null
        access(authenticated, expected) { transaction ->
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val record = tx.plan(expected, plan.planId)
            require(record.plan() == request.plan, AgentBridgeErrorCode.BINDING_CHANGED)
            require(tx.decision(plan.planId) == request.approval, AgentBridgeErrorCode.APPROVAL_REQUIRED)
            json.decodeFromString<AgentBridgeRequestSettingsResolution>(record.resolutionCanonical)
            resolution = record.resolutionCanonical
            request.approval // Existing full live approval/configuration/grant/expiry return fences.
        }
        return AgentBridgeExportExecutionPreparation(bytes.decodeToString(),
            AgentBridgeCodec.sha256(bytes), requireNotNull(resolution))
    }

    /** Durably accept a pending job; replay returns stored metadata, never capture permission.
     * Capture still needs a separate atomic claim and live read-boundary authority checks. */
    fun acceptExecution(authenticated: AgentBridgeExportAuthenticatedPeer,
        supplied: AgentBridgeExecuteRequest): AgentBridgeExportJobAcceptance {
        val bytes = AgentBridgeCodec.encode(supplied)
        val request = AgentBridgeCodec.decode(bytes) as AgentBridgeExecuteRequest
        val plan = request.plan as? AgentBridgeGeneratedPlan ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val expected = peer(authenticated, plan.intent.peer)
        var selected: AgentBridgeExportJobAcceptance? = null
        return store.access(fence = { transaction ->
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val result = selected ?: throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
            peer(authenticated, expected)
            if (result.newlyAccepted) {
                validateBoundary(authenticated, expected, tx, request.approval, nativeDecision = null)
            } else {
                // Metadata only: no re-resolution of changed preferences or expired plan approval.
                val ref = plan.authorityReferences.native
                tx.grant(expected, ref.authorityId, ref.grantRevision, now())
            }
            require(now() >= Instant.parse(result.job.acceptedAt) && now() < Instant.parse(result.job.expiresAt), AgentBridgeErrorCode.PLAN_EXPIRED)
        }) { transaction ->
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val jobs = tx.state.acceptedJobs.orEmpty()
            val old = jobs.singleOrNull { it.request().let { r -> (r.plan as AgentBridgeGeneratedPlan).intent.peer == expected && r.jobId == request.jobId } }
            if (old != null) {
                require(old.requestCanonical == bytes.decodeToString(), AgentBridgeErrorCode.BINDING_CHANGED)
                AgentBridgeExportJobAcceptance(old, false).also { selected = it }
            } else {
                require(jobs.size < 16, AgentBridgeErrorCode.BUSY)
                val stored = tx.plan(expected, plan.planId)
                require(stored.plan() == plan, AgentBridgeErrorCode.BINDING_CHANGED)
                require(tx.decision(plan.planId) == request.approval, AgentBridgeErrorCode.APPROVAL_REQUIRED)
                validateBoundary(authenticated, expected, tx, request.approval, nativeDecision = null)
                val accepted = now()
                val job = AgentBridgeExportAcceptedJob(1, bytes.decodeToString(), AgentBridgeCodec.sha256(bytes),
                    stored.resolutionCanonical, accepted.toString(), accepted.plusSeconds(604800).toString())
                job.validate()
                tx.state = tx.state.copy(version = if (tx.state.cancellationIntents != null) 5 else if (tx.state.captureClaims == null) 3 else 4, acceptedJobs = jobs + job)
                AgentBridgeExportJobAcceptance(job, true).also { selected = it }
            }
        }
    }

    /** Exact accepted-job stop authority only. An expired planning approval/revoked read grant
     * does not prevent its authenticated peer requesting a stop. No terminal receipt is implied. */
    fun requestCancellation(authenticated: AgentBridgeExportAuthenticatedPeer,
        supplied: AgentBridgeCancelRequest): AgentBridgeExportCancellationIntent {
        val bytes = AgentBridgeCodec.encode(supplied)
        val request = AgentBridgeCodec.decode(bytes) as AgentBridgeCancelRequest
        val expected = peer(authenticated, request.peer)
        var selected: Pair<AgentBridgeExportAcceptedJob, AgentBridgeExportCancellationIntent>? = null
        return store.access(fence = { transaction ->
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val result = selected ?: throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
            require(result.first in tx.state.acceptedJobs.orEmpty() && result.second in tx.state.cancellationIntents.orEmpty(), AgentBridgeErrorCode.BINDING_CHANGED)
            validateCancellation(authenticated, expected, request, result.first, result.second)
        }) { transaction ->
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val job = tx.state.acceptedJobs?.singleOrNull { it.requestSha256 == request.requestSha256 }
                ?: throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
            val intents = tx.state.cancellationIntents.orEmpty()
            val previous = intents.singleOrNull { it.request().requestSha256 == job.requestSha256 }
            val intent = previous ?: AgentBridgeExportCancellationIntent(1, bytes.decodeToString(), now().toString())
            validateCancellation(authenticated, expected, request, job, intent)
            if (previous == null) {
                require(intents.size < 16, AgentBridgeErrorCode.BUSY)
                tx.state = tx.state.copy(version = 5, cancellationIntents = intents + intent)
            }
            selected = job to intent
            intent
        }
    }

    /** Confirm only an issuer-locked absence of capture reservation and spool. Captured jobs
     * remain pending until retained-spool handling can prove their actual frontier/completion. */
    fun finalizeUnclaimedCancellation(authenticated: AgentBridgeExportAuthenticatedPeer,
        supplied: AgentBridgeCancelRequest): AgentBridgeExecutionReceipt {
        val request = AgentBridgeCodec.decode(AgentBridgeCodec.encode(supplied)) as AgentBridgeCancelRequest
        val expected = peer(authenticated, request.peer)
        var selected: Pair<AgentBridgeExportAcceptedJob, AgentBridgeExportCancellationIntent>? = null
        fun unclaimed(tx: AgentBridgeExportAuthorityTransaction, job: AgentBridgeExportAcceptedJob) {
            require(tx.state.captureClaims.orEmpty().none { it.requestSha256 == job.requestSha256 }, AgentBridgeErrorCode.BUSY)
            store.requireNoCaptureSpool(job)
        }
        val terminal = store.access(fence = { transaction ->
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val result = selected ?: throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
            require(result.first in tx.state.acceptedJobs.orEmpty() && result.second in tx.state.cancellationIntents.orEmpty(), AgentBridgeErrorCode.BINDING_CHANGED)
            validateCancellation(authenticated, expected, request, result.first, result.second)
            unclaimed(tx, result.first) // Recheck local absence AFTER delaying native callbacks.
        }) { transaction ->
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val job = tx.state.acceptedJobs?.singleOrNull { it.requestSha256 == request.requestSha256 }
                ?: throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
            val intents = tx.state.cancellationIntents.orEmpty()
            val index = intents.indexOfFirst { it.request() == request }
            require(index >= 0, AgentBridgeErrorCode.BINDING_CHANGED)
            val previous = intents[index]
            validateCancellation(authenticated, expected, request, job, previous)
            unclaimed(tx, job)
            val result = if (previous.version == 2) previous else previous.copy(version = 2,
                terminalReceiptCanonical = AgentBridgeCodec.encode(job.unclaimedCancellationReceipt()).decodeToString(), confirmedAt = now().toString())
            validateCancellation(authenticated, expected, request, job, result)
            if (result != previous) tx.state = tx.state.copy(cancellationIntents = intents.mapIndexed { i, value -> if (i == index) result else value })
            selected = job to result
            result
        }
        return terminal.terminalReceipt() ?: throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
    }

    private fun validateCancellation(authenticated: AgentBridgeExportAuthenticatedPeer, expected: AgentBridgePeer,
        request: AgentBridgeCancelRequest, job: AgentBridgeExportAcceptedJob, intent: AgentBridgeExportCancellationIntent) {
        peer(authenticated, expected)
        val instant = now()
        require(instant >= Instant.parse(job.acceptedAt) && instant < Instant.parse(job.expiresAt), AgentBridgeErrorCode.PLAN_EXPIRED)
        intent.validate(job)
        require(intent.request() == request, AgentBridgeErrorCode.BINDING_CHANGED)
    }

    /** Single durable reservation; not SDK read authority, a preserved spool or capture completion.
     * A published claim is never released/reissued after an ambiguous return or process restart. */
    fun claimCapture(authenticated: AgentBridgeExportAuthenticatedPeer,
        supplied: AgentBridgeExecuteRequest): AgentBridgeExportCaptureReservation {
        val bytes = AgentBridgeCodec.encode(supplied)
        val request = AgentBridgeCodec.decode(bytes) as AgentBridgeExecuteRequest
        val plan = request.plan as? AgentBridgeGeneratedPlan ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val expected = peer(authenticated, plan.intent.peer)
        var selected: AgentBridgeExportCaptureReservation? = null
        return store.access(fence = { transaction ->
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val result = selected ?: throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
            peer(authenticated, expected)
            require(result.claim in tx.state.captureClaims.orEmpty(), AgentBridgeErrorCode.BINDING_CHANGED)
            validateBoundary(authenticated, expected, tx, request.approval, nativeDecision = null)
            require(now() >= Instant.parse(result.job.acceptedAt) && now() < Instant.parse(result.job.expiresAt) &&
                now() >= Instant.parse(result.claim.claimedAt), AgentBridgeErrorCode.PLAN_EXPIRED)
        }) { transaction ->
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val job = tx.state.acceptedJobs?.singleOrNull { it.requestCanonical == bytes.decodeToString() }
                ?: throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
            val claims = tx.state.captureClaims.orEmpty()
            require(tx.state.cancellationIntents.orEmpty().none { it.request().requestSha256 == job.requestSha256 }, AgentBridgeErrorCode.PERMISSION_REQUIRED)
            require(claims.none { it.requestSha256 == job.requestSha256 }, AgentBridgeErrorCode.BUSY)
            require(claims.size < 16, AgentBridgeErrorCode.BUSY)
            validateBoundary(authenticated, expected, tx, request.approval, nativeDecision = null)
            val claim = AgentBridgeExportStoredCaptureClaim(1, UUID.randomUUID().toString(), job.requestSha256, now().toString())
            tx.state = tx.state.copy(version = if (tx.state.cancellationIntents != null) 5 else 4, captureClaims = claims + claim)
            AgentBridgeExportCaptureReservation(job, claim).also { selected = it }
        }
    }

    /** Pre-read validation only, not claim/reclaim/resume. Frozen output survives changed current
     * preferences/planning expiry; native grant/trust/readiness/availability and job expiry remain live. */
    fun captureReadConfiguration(authenticated: AgentBridgeExportAuthenticatedPeer,
        reservation: AgentBridgeExportCaptureReservation): AgentBridgeRequestSettingsResolution {
        val request = reservation.job.request()
        val plan = request.plan as? AgentBridgeGeneratedPlan ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val expected = peer(authenticated, plan.intent.peer)
        fun validate(transaction: AgentBridgeExportAuthorityTransaction?): AgentBridgeRequestSettingsResolution {
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            peer(authenticated, expected)
            // Pending stop intent fences reads, not proof of terminal source cancellation.
            require(tx.state.cancellationIntents.orEmpty().none { it.request().requestSha256 == reservation.job.requestSha256 }, AgentBridgeErrorCode.PERMISSION_REQUIRED)
            require(reservation.job in tx.state.acceptedJobs.orEmpty() && reservation.claim in tx.state.captureClaims.orEmpty() &&
                reservation.claim.requestSha256 == reservation.job.requestSha256, AgentBridgeErrorCode.BINDING_CHANGED)
            val snapshot = readConfiguration(null, tx, expected) // No saved/profile preference read.
            val frozen = json.decodeFromString<AgentBridgeRequestSettingsResolution>(reservation.job.resolutionCanonical)
            require(frozen.selection.all { snapshot.settings.catalog.metrics[it.semanticId] == it }, AgentBridgeErrorCode.PERMISSION_REQUIRED)
            requirePresence(snapshot)
            require(snapshot.entitlement == AgentBridgeDiscoveryEntitlement.SATISFIED, AgentBridgeErrorCode.ENTITLEMENT_REQUIRED)
            require(snapshot.nativeGrants == AgentBridgeDiscoveryNativeGrants.SATISFIED, AgentBridgeErrorCode.PERMISSION_REQUIRED)
            peer(authenticated, expected)
            val instant = now()
            val ref = plan.authorityReferences.native
            val parent = tx.grant(expected, ref.authorityId, ref.grantRevision, instant)
            require(AgentBridgeExportAuthorityStore.reference(parent) == ref, AgentBridgeErrorCode.APPROVAL_REQUIRED)
            // Exact parent reference retains the scope proven at acceptance, without renewing it.
            require(AgentBridgeExportDelegationRightsItem.EXPORT_EXECUTE in parent.rights, AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val finalInstant = now()
            require(finalInstant >= Instant.parse(reservation.claim.claimedAt) && finalInstant < Instant.parse(reservation.job.expiresAt) &&
                finalInstant < Instant.parse(parent.expiresAt), AgentBridgeErrorCode.PLAN_EXPIRED)
            return frozen
        }
        return store.access(fence = { validate(it) }) { validate(it) }
    }

    fun discover(authenticated: AgentBridgeExportAuthenticatedPeer, value: AgentBridgeDiscoveryRequest): AgentBridgeDiscovery {
        val request = AgentBridgeCodec.decode(AgentBridgeCodec.encode(value)) as AgentBridgeDiscoveryRequest
        val peer = peer(authenticated, request.peer)
        return access(authenticated, peer) { tx -> discovery(request.requestId, peer, readConfiguration(null, tx, peer), tx, now()) }
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
                val snapshot = readConfiguration(existing.plan().intent.settingsPolicy, tx, peer)
                validateCurrent(existing, tx, snapshot, peer, now())
                return@access existing.plan() // Never slide expiry, replace settings or create a new plan on retry.
            }
            val snapshot = readConfiguration(intent.settingsPolicy, tx, peer)
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

    /** Queue preflight only. IO/key/configuration/trust failures are outside stale classification;
     * only pure validation against verified issuer state may exclude an obsolete request. */
    fun nativePlanIsReviewable(authenticated: AgentBridgeExportAuthenticatedPeer, planId: String): Boolean {
        val expected = peer(authenticated, authenticated.requireCurrent())
        return store.access(fence = { peer(authenticated, expected) }) { transaction ->
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val record = tx.plan(expected, planId)
            val snapshot = readConfiguration(record.plan().intent.settingsPolicy, tx, expected)
            peer(authenticated, expected)
            try {
                validateCurrent(record, tx, snapshot, expected, now(), AgentBridgeExportDelegationRightsItem.EXPORT_EXECUTE)
                true
            } catch (failure: AgentBridgeException) {
                if (failure.code in setOf(AgentBridgeErrorCode.PLAN_EXPIRED, AgentBridgeErrorCode.BINDING_CHANGED,
                        AgentBridgeErrorCode.REVISION_CONFLICT, AgentBridgeErrorCode.APPROVAL_REQUIRED)) false
                else throw failure
            }
        }
    }

    /** Native presentation read only. Issuer-owned bytes supply the review, not host display text.
     * No native decision, grant, approval or health capture is created by returning this plan. */
    fun reviewNativePlan(authenticated: AgentBridgeExportAuthenticatedPeer, planId: String): AgentBridgeGeneratedPlan {
        val expected = peer(authenticated, authenticated.requireCurrent())
        return access(authenticated, expected, nativePlanReview = true) { transaction ->
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val record = tx.plan(expected, planId)
            val snapshot = readConfiguration(record.plan().intent.settingsPolicy, tx, expected)
            peer(authenticated, expected)
            validateCurrent(record, tx, snapshot, expected, now(), AgentBridgeExportDelegationRightsItem.EXPORT_EXECUTE)
            val plan = record.plan()
            requireReady(snapshot, plan)
            plan // Decoded from the private canonical record; callers do not hold its stored state.
        }
    }

    fun approval(authenticated: AgentBridgeExportAuthenticatedPeer, value: AgentBridgeApprovalRequest): AgentBridgeApproval {
        val request = AgentBridgeCodec.decode(AgentBridgeCodec.encode(value)) as AgentBridgeApprovalRequest
        val peer = peer(authenticated, request.binding.peer)
        return access(authenticated, peer) { transaction ->
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val record = tx.plan(peer, request.planId)
            AgentBridgeValidation.validateApprovalBinding(request, record.plan())
            val snapshot = readConfiguration(record.plan().intent.settingsPolicy, tx, peer)
            validateCurrent(record, tx, snapshot, peer, now(), AgentBridgeExportDelegationRightsItem.EXPORT_EXECUTE)
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
        val nativeDecision = NativeDecisionFence(native, AgentBridgeExportNativeDecision.ExactApproval(planId, frozenBinding))
        return access(authenticated, peer, nativeDecision) { transaction ->
            val tx = transaction ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val record = tx.plan(peer, planId)
            require(frozenBinding == AgentBridgeValidation.bindingFor(record.plan()), AgentBridgeErrorCode.BINDING_CHANGED)
            val snapshot = readConfiguration(record.plan().intent.settingsPolicy, tx, peer)
            val approved = now()
            validateCurrent(record, tx, snapshot, peer, approved, AgentBridgeExportDelegationRightsItem.EXPORT_EXECUTE)
            requireReady(snapshot, record.plan())
            val parent = tx.grant(peer, frozenBinding.authorityReferences.native.authorityId, frozenBinding.authorityReferences.native.grantRevision, approved)
            require(AgentBridgeExportDelegationRightsItem.EXPORT_EXECUTE in parent.rights, AgentBridgeErrorCode.APPROVAL_REQUIRED)
            tx.decision(planId)?.let { return@access it }
            peer(authenticated, peer) // A native session can revoke/change live trust during a decision.
            nativeDecision.requireCurrent()
            val current = readConfiguration(record.plan().intent.settingsPolicy, tx, peer)
            peer(authenticated, peer) // This callback can delay: sample time only AFTER current trust.
            val decided = now()
            validateCurrent(record, tx, current, peer, decided, AgentBridgeExportDelegationRightsItem.EXPORT_EXECUTE)
            requireReady(current, record.plan())
            val currentParent = tx.grant(peer, parent.authorityId, parent.grantRevision, decided)
            require(AgentBridgeExportDelegationRightsItem.EXPORT_EXECUTE in currentParent.rights, AgentBridgeErrorCode.APPROVAL_REQUIRED)
            val approval = AgentBridgeApproval(UUID.randomUUID().toString(), decided.toString(), currentParent.authorityId, frozenBinding,
                listOf(AgentBridgeApprovalRightsItem.EXPORT_EXECUTE), "healthmd.agent_approval", 1)
            tx.decide(planId, approval)
            approval
        }
    }

    private fun validateCurrent(record: AgentBridgeExportIssuedPlanRecord, tx: AgentBridgeExportAuthorityTransaction,
        snapshot: AgentBridgeExportPlanningConfiguration, peer: AgentBridgePeer, instant: Instant,
        right: AgentBridgeExportDelegationRightsItem = AgentBridgeExportDelegationRightsItem.PLAN) {
        val plan = record.plan()
        require(instant >= Instant.parse(plan.issuedAt) && instant < Instant.parse(plan.expiresAt), AgentBridgeErrorCode.PLAN_EXPIRED)
        val ref = plan.authorityReferences.native
        val parent = tx.grant(peer, ref.authorityId, ref.grantRevision, instant)
        require(ref == AgentBridgeExportAuthorityStore.reference(parent) && right in parent.rights, AgentBridgeErrorCode.APPROVAL_REQUIRED)
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
                    AgentBridgeOutputSupportPathTokensItem.YEAR), leaves(json.encodeToJsonElement(DEFAULT_OUTPUT), "").sorted(), listOf(AgentBridgeWriteMode.OVERWRITE)),
            peer, ZERO, emptyList(), queryCatalogSha256 = ZERO, queryOperations = emptyList(), requestId = requestId,
            requiredActions = actions(snapshot).map { token -> actionEnum(token) }, schema = "healthmd.agent_discovery", schemaVersion = 1,
            settingsPolicies = listOf(AgentBridgeDiscoverySettingsPoliciesItem.EXPLICIT, AgentBridgeDiscoverySettingsPoliciesItem.PROFILE,
                AgentBridgeDiscoverySettingsPoliciesItem.SAVED_DEVICE_SETTINGS), sourceCalendarTimezone = snapshot.sourceCalendarTimezone)
        val response = draft.copy(capabilitySha256 = AgentBridgeValidation.capabilityDigest(draft))
        return AgentBridgeCodec.decode(AgentBridgeCodec.encode(response)) as AgentBridgeDiscovery
    }
    /** Only native mutation callers supply this exact, non-wire review. No new prompt is performed. */
    private class NativeDecisionFence(private val native: AgentBridgeExportNativeAuthorization,
        private val decision: AgentBridgeExportNativeDecision.ExactApproval) {
        fun requireCurrent() = native.requireDecision(decision)
    }

    private fun <T : AgentBridgeDocument> access(authenticated: AgentBridgeExportAuthenticatedPeer, expected: AgentBridgePeer,
        nativeDecision: NativeDecisionFence? = null, nativePlanReview: Boolean = false, block: (AgentBridgeExportAuthorityTransaction?) -> T): T {
        var candidate: T? = null
        val result = store.access(fence = { tx ->
            candidate?.let { validateBoundary(authenticated, expected, tx, it, nativeDecision, nativePlanReview) } ?: peer(authenticated, expected)
        }) { tx -> block(tx).also { candidate = it } }
        return recheckReturn(authenticated, expected, result, nativeDecision, nativePlanReview)
    }

    /** Full live issuer/configuration/expiry fence for each actual response transmission boundary. */
    fun requireCurrentForTransmission(message: AgentBridgeMessage, authenticated: AgentBridgeExportAuthenticatedPeer) {
        val expected = authenticated.requireCurrent()
        if (message.type == "rejected" && message.payload is AgentBridgeError) {
            peer(authenticated, expected) // Fixed-code rejection conveys no private authority.
            return
        }
        when (message.payload) {
            is AgentBridgeDiscovery, is AgentBridgeGeneratedPlan, is AgentBridgeApproval ->
                recheckReturn(authenticated, expected, message.payload, nativeDecision = null)
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
    }

    private fun <T : AgentBridgeDocument> recheckReturn(authenticated: AgentBridgeExportAuthenticatedPeer,
        expected: AgentBridgePeer, value: T, nativeDecision: NativeDecisionFence?, nativePlanReview: Boolean = false): T {
        // Trust may delay or revoke a parent AFTER the previous transaction released its lock.
        // Reload issuer-owned state after that callback; cached transaction data is not permission.
        peer(authenticated, expected)
        return store.access(fence = { tx -> validateBoundary(authenticated, expected, tx, value, nativeDecision, nativePlanReview) }) { value }
    }

    private fun validateBoundary(authenticated: AgentBridgeExportAuthenticatedPeer, expected: AgentBridgePeer,
        tx: AgentBridgeExportAuthorityTransaction?, value: AgentBridgeDocument, nativeDecision: NativeDecisionFence?, nativePlanReview: Boolean = false) {
        peer(authenticated, expected)
        // Derive the policy from the issuer's locked record, never host-provided review text or
        // defaults. Approval responses carry a binding, not a settings policy.
        val policy = when (value) {
            is AgentBridgeDiscovery -> null
            is AgentBridgeGeneratedPlan -> (tx ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED))
                .plan(expected, value.planId).plan().intent.settingsPolicy
            is AgentBridgeApproval -> (tx ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED))
                .planForApproval(expected, value).plan().intent.settingsPolicy
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
        val snapshot = readConfiguration(policy, tx, expected) // Fresh configuration AFTER the publication/return trust callback.
        peer(authenticated, expected)
        if (nativeDecision != null) {
            nativeDecision.requireCurrent() // Same review after key/config reads and at publication/return.
            peer(authenticated, expected)
        }
        val instant = now() // Sample live expiry AFTER all native and current-trust callbacks.
        when (value) {
            is AgentBridgeDiscovery -> {
                require(instant >= Instant.parse(value.issuedAt) && instant < Instant.parse(value.expiresAt), AgentBridgeErrorCode.PLAN_EXPIRED)
                for (ref in value.authorityReferences) {
                    val parent = (tx ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED))
                        .grant(expected, ref.authorityId, ref.grantRevision, instant)
                    require(ref == AgentBridgeExportAuthorityStore.reference(parent) && AgentBridgeExportDelegationRightsItem.DISCOVER in parent.rights,
                        AgentBridgeErrorCode.APPROVAL_REQUIRED)
                }
                require(discovery(value.requestId, expected, snapshot, tx, instant).capabilitySha256 == value.capabilitySha256,
                    AgentBridgeErrorCode.BINDING_CHANGED)
                require(now() < Instant.parse(value.expiresAt), AgentBridgeErrorCode.PLAN_EXPIRED)
                value.authorityReferences.forEach { ref -> requireNotNull(tx).grant(expected, ref.authorityId, ref.grantRevision, now()) }
            }
            is AgentBridgeGeneratedPlan, is AgentBridgeApproval -> {
                val current = tx ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
                val record = if (value is AgentBridgeGeneratedPlan) current.plan(expected, value.planId)
                    else current.planForApproval(expected, value as AgentBridgeApproval)
                val plan = record.plan()
                val right = if (value is AgentBridgeApproval || nativePlanReview) AgentBridgeExportDelegationRightsItem.EXPORT_EXECUTE else AgentBridgeExportDelegationRightsItem.PLAN
                validateCurrent(record, current, snapshot, expected, instant, right)
                if (value is AgentBridgeGeneratedPlan) require(value == plan, AgentBridgeErrorCode.BINDING_CHANGED)
                if (value is AgentBridgeApproval || nativePlanReview) requireReady(snapshot, plan)
                if (value is AgentBridgeApproval) {
                    require(current.decision(plan.planId) == value && value.binding == AgentBridgeValidation.bindingFor(plan), AgentBridgeErrorCode.APPROVAL_REQUIRED)
                    require(Instant.parse(value.approvedAt) <= instant, AgentBridgeErrorCode.PLAN_EXPIRED)
                }
                // Bounded parsing/derivation takes time too; it cannot renew or retarget the candidate.
                val finalInstant = now()
                require(finalInstant >= Instant.parse(plan.issuedAt) && finalInstant < Instant.parse(plan.expiresAt), AgentBridgeErrorCode.PLAN_EXPIRED)
                current.grant(expected, plan.authorityReferences.native.authorityId, plan.authorityReferences.native.grantRevision, finalInstant)
            }
            else -> throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        }
    }

    private fun readConfiguration(policy: AgentBridgeSettingsPolicy?, tx: AgentBridgeExportAuthorityTransaction?, peer: AgentBridgePeer): AgentBridgeExportPlanningConfiguration {
        val publication = tx?.state?.nativeCatalog
        if (publication != null && publication.sourceInstallationId != peer.sourceInstallationId) throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
        // Kotlin wire models contain List values that may have mutable backing collections.
        // A native reader receives its own decoded policy, never aliases of an in-flight intent.
        val detached = policy?.let {
            json.decodeFromJsonElement(AgentBridgeSettingsPolicySerializer,
                json.encodeToJsonElement(AgentBridgeSettingsPolicySerializer, it))
        }
        return configuration.readConfiguration(detached, publication)
    }

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
        // Support names mean the DTO leaf is understood, including its fixed/disabled value; they
        // do NOT promise arbitrary customization. The actual resolver still rejects nondefaults.
        private val DEFAULT_OUTPUT = AgentBridgeOutputSettings(
            AgentBridgeDailyNotes(false, false, "{date}", "", false, emptyList()), AgentBridgeDictionaryNone("none"),
            "{date}", "{year}", listOf(AgentBridgeFormat.JSON),
            AgentBridgeIndividualEntries(false, false, "{metric}-{date}", "", emptyList()),
            AgentBridgeOutputProfile.ANDROID_FROZEN_V4, AgentBridgePackagingLooseFiles("loose_files"),
            AgentBridgePresentation(AgentBridgePresentationDisplayUnits.METRIC,
                AgentBridgeFrontmatter(emptyList(), emptyList(), false, true), true, true, "en-US", "canonical",
                AgentBridgeMarkdown("", emptyList(), AgentBridgeMarkdownStyle.LISTS)), "", AgentBridgeWriteMode.OVERWRITE)
    }
}


/** Immutable journal inputs, not an execution permit. Getters decode detached values so mutable
 * lists in wire/native DTOs cannot alter the accepted request or resolution through aliases. */
internal class AgentBridgeExportExecutionPreparation internal constructor(
    private val requestCanonical: String,
    val requestSha256: String,
    private val resolutionCanonical: String,
) {
    fun requestBytes(): ByteArray = requestCanonical.toByteArray(Charsets.UTF_8)
    fun resolution(): AgentBridgeRequestSettingsResolution =
        Json { encodeDefaults = true; ignoreUnknownKeys = false }.decodeFromString(resolutionCanonical)
}
