package com.healthmd.direct

import android.os.Looper
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import com.healthmd.core.CoreMetricRegistryProfile
import com.healthmd.core.CoreMetricRegistrySnapshot
import com.healthmd.data.health.HealthConnectNativePlanningMetadata
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.data.settings.SettingsRepositoryImpl
import com.healthmd.direct.protocol.*
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotException
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.registry.HealthMdCoreRegistryAdapter
import java.io.IOException
import java.time.DateTimeException
import java.time.ZoneId
import java.util.Collections
import java.util.concurrent.atomic.AtomicBoolean
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.launch
import kotlinx.coroutines.Job
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking

/** Native lifecycle state, never a wire DTO or a permission issuer. Its publisher records
 * advertised capability/readiness changes in signed issuer storage before offering v4. */
internal data class AgentBridgeNativePlanningFacts(
    val availableNativeMetricIds: Set<String>,
    val deviceSettingsObjectId: String,
    val sourceCalendarTimezone: String,
    val configurationProtection: AgentBridgeDiscoveryConfigurationProtection,
    val nativeGrants: AgentBridgeDiscoveryNativeGrants,
    val entitlement: AgentBridgeDiscoveryEntitlement,
    val userStartedServiceActive: Boolean,
    val firstUnlockComplete: Boolean,
    // Android exposes actual granted-permission metadata; Apple cannot reveal per-type read grants.
    // Private observation only, not a new wire field or authorization token.
    val nativePermissionObservationSha256: String? = null,
)

/** Other arguments are cached native observations. This adapter performs no quota/settings reads;
 * permission summary is not an all-metrics grant. The full private digest fences partial changes. */
internal fun HealthConnectNativePlanningMetadata.planningFacts(deviceSettingsObjectId: String,
    sourceCalendarTimezone: String, configurationProtection: AgentBridgeDiscoveryConfigurationProtection,
    entitlement: AgentBridgeDiscoveryEntitlement, userStartedServiceActive: Boolean,
    firstUnlockComplete: Boolean): AgentBridgeNativePlanningFacts = AgentBridgeNativePlanningFacts(
        availableNativeMetricIds, deviceSettingsObjectId, sourceCalendarTimezone, configurationProtection,
        when {
            !providerAvailable -> AgentBridgeDiscoveryNativeGrants.REQUIRED
            hasAnyForegroundReadPermission == null -> AgentBridgeDiscoveryNativeGrants.UNVERIFIED
            hasAnyForegroundReadPermission -> AgentBridgeDiscoveryNativeGrants.SATISFIED
            else -> AgentBridgeDiscoveryNativeGrants.REQUIRED
        }, entitlement, userStartedServiceActive, firstUnlockComplete, grantedPermissionsSha256)

/** Actual native stores plus compiled catalog. The synchronous issuer transaction may call this
 * only from a worker: the single preferences read must never block the Android main looper.
 * Discovery/explicit requests do not collect private preferences. Selected settings/profile and
 * their pin/rebind state come from one committed DataStore image. No SDK health/provider work. */
internal class AgentBridgeNativeConfigurationReader(
    private val dataStore: DataStore<Preferences>,
    private val settings: SettingsRepositoryImpl,
    private val profiles: ExportProfileRepository,
    private val nativeState: () -> AgentBridgeNativePlanningFacts,
    private val registry: () -> CoreMetricRegistrySnapshot = {
        HealthMdCoreRegistryAdapter.snapshot(CoreMetricRegistryProfile.ANDROID_FROZEN_V4)
    },
) : AgentBridgeExportPlanningConfigurationReader {
    override fun readConfiguration(policy: AgentBridgeSettingsPolicy?, catalogPublication: AgentBridgeNativeCatalogPublication?): AgentBridgeExportPlanningConfiguration {
        if (Looper.myLooper() == Looper.getMainLooper()) fail(AgentBridgeErrorCode.PERMISSION_REQUIRED)
        val publication = catalogPublication ?: fail(AgentBridgeErrorCode.BINDING_CHANGED)
        publication.validate()
        return try { readSelectedConfiguration(policy, publication) }
        catch (_: AndroidExportSettingsSnapshotException) { fail(AgentBridgeErrorCode.BINDING_CHANGED) }
        catch (_: DateTimeException) { fail(AgentBridgeErrorCode.BINDING_CHANGED) }
    }

    private fun readSelectedConfiguration(policy: AgentBridgeSettingsPolicy?, publication: AgentBridgeNativeCatalogPublication): AgentBridgeExportPlanningConfiguration {
        val state = detachedState()
        if (state.fingerprint(publication.sourceInstallationId) != publication.factsSha256) fail(AgentBridgeErrorCode.BINDING_CHANGED)
        val catalog = AgentBridgeRequestSettingsCatalog(registry(), state.availableNativeMetricIds, publication.revision)
        var saved: AgentBridgeRequestSettingsSnapshot? = null
        var selectedProfiles: List<AgentBridgeRequestSettingsProfile> = emptyList()
        if (policy is AgentBridgeSettingsPolicySavedDeviceSettings || policy is AgentBridgeSettingsPolicyProfile) {
            val prefs = try {
                runBlocking(Dispatchers.IO) { dataStore.data.first() }
            } catch (_: IOException) { fail(AgentBridgeErrorCode.BINDING_CHANGED) }
            when (policy) {
                is AgentBridgeSettingsPolicySavedDeviceSettings -> {
                    val snapshot = settings.readSavedExportConfiguration(prefs, policy.expectedRevision)
                        ?: fail(AgentBridgeErrorCode.BINDING_CHANGED)
                    // Discard installation plumbing, credentials/recovery metadata and any native
                    // renderer authority. Only output choices enter the independent host request.
                    val outputOnly = snapshot.settings.copy(exportTarget = ExportTarget.DEVICE_FOLDER,
                        scheduledExportTarget = ExportTarget.DEVICE_FOLDER, apiEndpointUrl = "", executionEnginePin = null)
                    val frozen = AndroidExportSettingsSnapshot.capture(outputOnly, null, ZoneId.of(state.sourceCalendarTimezone))
                    saved = AgentBridgeRequestSettingsSnapshot(snapshot.revision, frozen.restoreOnto(ExportSettings()))
                }
                is AgentBridgeSettingsPolicyProfile -> {
                    val snapshot = profiles.readConfigurationProfile(prefs, policy.profileId, policy.expectedRevision)
                        ?: fail(AgentBridgeErrorCode.BINDING_CHANGED)
                    val outputOnly = snapshot.settings.copy(exportTarget = ExportTarget.DEVICE_FOLDER,
                        scheduledExportTarget = ExportTarget.DEVICE_FOLDER, apiEndpointIdentitySha256 = null, enginePin = null)
                    selectedProfiles = listOf(AgentBridgeRequestSettingsProfile(policy.profileId,
                        AgentBridgeRequestSettingsSnapshot(snapshot.revision, outputOnly.restoreOnto(ExportSettings())), snapshot.executionBlocked))
                }
                else -> error("Selected native policy changed type")
            }
        }
        if (detachedState() != state) fail(AgentBridgeErrorCode.BINDING_CHANGED)
        return AgentBridgeExportPlanningConfiguration(AgentBridgeRequestSettingsInputs(catalog, saved, selectedProfiles),
            state.deviceSettingsObjectId, state.sourceCalendarTimezone, state.configurationProtection,
            state.nativeGrants, state.entitlement, state.userStartedServiceActive, state.firstUnlockComplete)
    }

    private fun detachedState(): AgentBridgeNativePlanningFacts {
        val value = nativeState()
        return value.copy(availableNativeMetricIds = Collections.unmodifiableSet(value.availableNativeMetricIds.toSortedSet()))
    }

    private fun fail(code: AgentBridgeErrorCode): Nothing = throw AgentBridgeException(code)
}


/** One accepted native owner, one private planner and original peer. Request callers cannot
 * substitute peer authority. All calls remain worker-only and fence pending/stopped lifecycle
 * state before work and before return. This neither advertises nor installs a wire route. */
internal class AgentBridgeNativePlanningSession(
    private val peer: AgentBridgeExportAuthenticatedPeer,
    private val lifecycle: AgentBridgeNativeCatalogLifecycle,
    private val store: AgentBridgeExportAuthorityStore,
    configuration: AgentBridgeExportPlanningConfigurationReader,
    clock: java.time.Clock = java.time.Clock.systemUTC(),
    private val responseChannel: DirectSecureChannel? = null,
    private val responseNegotiation: AgentBridgeNegotiation? = null,
) {
    private val service: AgentBridgeExportPlanningService
    @Volatile private var wireAbandoned = false
    init {
        val publication = requireCurrent()
        // Compare the issuer transaction's exact revision, not only its facts fingerprint.
        val ownedConfiguration = AgentBridgeExportPlanningConfigurationReader { policy, signedPublication ->
            requirePublication(signedPublication)
            val result = configuration.readConfiguration(policy, signedPublication)
            requirePublication(signedPublication)
            result
        }
        service = AgentBridgeExportPlanningService(store, ownedConfiguration, clock)
        requireSamePublication(publication)
    }
    fun requireCurrent(): AgentBridgeNativeCatalogPublication {
        if (wireAbandoned) throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
        if (Looper.myLooper() == Looper.getMainLooper()) throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
        peer.requireCurrent()
        return lifecycle.currentPublication()
    }
    private fun requirePublication(publication: AgentBridgeNativeCatalogPublication?) {
        val current = requireCurrent()
        if (publication == null || current != publication) throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
    }
    private fun requireSamePublication(publication: AgentBridgeNativeCatalogPublication) = requirePublication(publication)

    fun handleEnvelope(bytes: ByteArray, negotiation: AgentBridgeNegotiation): ByteArray {
        val publication = requireCurrent()
        val result = service.handleEnvelope(bytes, peer, negotiation)
        requireSamePublication(publication)
        return result
    }
    /** Native composition only. The accepted owner pins its channel at construction. A caller
     * supplies its live operation Job; pure cancellation checks run after issuer callbacks.
     * No wire identity or fresh peer can retarget this response. The coordinator also closes its active channel on explicit cancelActive. */
    fun handleAndSend(bytes: ByteArray, caller: Job) {
        val negotiation = responseNegotiation ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        if (negotiation.baseApplication != 2 || !negotiation.agentExtension || negotiation.appleQueryExtension)
            throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val channel = responseChannel ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        try {
            withTransportCancellation(caller, channel) {
                caller.ensureActive()
                val publication = requireCurrent()
                val response = AgentBridgeCodec.decodeEnvelope(handleEnvelope(bytes, negotiation), negotiation)
                channel.sendAgentBridge(response, negotiation) {
                    caller.ensureActive()
                    requireSamePublication(publication)
                    caller.ensureActive()
                    service.requireCurrentForTransmission(response, peer)
                    // Local lifecycle only after issuer validation, never a fresh SDK callback.
                    if (lifecycle.currentPublication() != publication) throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
                    caller.ensureActive()
                }
                caller.ensureActive()
                requireSamePublication(publication)
                caller.ensureActive()
                service.requireCurrentForTransmission(response, peer)
                if (lifecycle.currentPublication() != publication) throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
                caller.ensureActive()
            }
        } catch (failure: Throwable) {
            wireAbandoned = true
            runCatching { channel.close() }
            caller.ensureActive()
            throw failure
        }
    }


    /** One native receive iteration. This exact original planner handles bridge requests; base
     * envelopes and binary frames return intact to the existing controller. No concurrent reader
     * may consume the same channel. Native advertisement/dispatcher remain unchanged. */
    fun receiveAndHandleNext(caller: Job): ReceivedAgentBridgePayload? {
        val negotiation = responseNegotiation ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        if (negotiation.baseApplication != 2 || !negotiation.agentExtension || negotiation.appleQueryExtension)
            throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val channel = responseChannel ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        try {
            return withTransportCancellation(caller, channel) {
                val received = channel.receiveAllowingAgentBridge(negotiation) {
                    caller.ensureActive(); requireCurrent(); caller.ensureActive()
                }
                if (received is ReceivedAgentBridgePayload.Agent) {
                    handleAndSend(AgentBridgeCodec.encodeEnvelope(received.message, negotiation), caller)
                    null
                } else {
                    requireCurrent(); caller.ensureActive()
                    received
                }
            }
        } catch (failure: Throwable) {
            wireAbandoned = true
            runCatching { channel.close() }
            caller.ensureActive()
            throw failure
        }
    }

    /** Child of the actual caller Job, armed before native I/O. Unconfined resumption performs
     * only local abandonment/socket close on cancellation, even while its parent's thread blocks.
     * It never does SDK/issuer/UI work and is canceled/disposed on every normal or failing exit. */
    private fun <T> withTransportCancellation(caller: Job, channel: DirectSecureChannel, operation: () -> T): T {
        caller.ensureActive()
        val finished = AtomicBoolean(false)
        val cancellation = CoroutineScope(caller + Dispatchers.Unconfined).launch(start = CoroutineStart.UNDISPATCHED) {
            try { awaitCancellation() }
            finally {
                if (!finished.get()) {
                    wireAbandoned = true
                    runCatching { channel.close() }
                }
            }
        }
        try { caller.ensureActive(); return operation() }
        finally { finished.set(true); cancellation.cancel() }
    }

    /** Native signed-record queue, never host display text. Listing creates no decision. */
    fun nativePlansAwaitingReview(): List<AgentBridgeGeneratedPlan> {
        val publication = requireCurrent()
        val expected = peer.requireCurrent()
        val candidates = store.access { transaction ->
            val state = transaction?.state ?: throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
            if (state.nativeCatalog != publication) throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
            val decided = state.decisions.map { it.planId }.toSet()
            state.plans.map { it.plan() }.filter { it.intent.peer == expected && it.planId !in decided }
        }
        val results = candidates.mapNotNull { plan ->
            if (service.nativePlanIsReviewable(peer, plan.planId)) service.reviewNativePlan(peer, plan.planId) else null
        }
        requireSamePublication(publication)
        return results.sortedWith(compareByDescending<AgentBridgeGeneratedPlan> { it.issuedAt }.thenBy { it.planId })
    }

    fun reviewNativePlan(planId: String): AgentBridgeGeneratedPlan {
        val publication = requireCurrent()
        val result = service.reviewNativePlan(peer, planId)
        requireSamePublication(publication)
        return result
    }
    fun authorizeExactApproval(native: AgentBridgeExportNativeAuthorization, planId: String,
        binding: AgentBridgeBinding): AgentBridgeApproval {
        val publication = requireCurrent()
        val result = service.authorizeExactApproval(peer, native, planId, binding)
        requireSamePublication(publication)
        return result
    }
}
