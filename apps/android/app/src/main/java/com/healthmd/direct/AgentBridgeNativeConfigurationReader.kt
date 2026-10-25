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
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.job
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

/** Owns only immutable derived mappings. The default factory is the compiled Rust profile;
 * a hermetic factory can exercise the same cache without loading a host-native library. */
internal class AgentBridgeNativeCompiledCatalog(
    private val registry: () -> CoreMetricRegistrySnapshot = {
        HealthMdCoreRegistryAdapter.snapshot(CoreMetricRegistryProfile.ANDROID_FROZEN_V4)
    },
) {
    private val lock = Any()
    private var cached: Pair<AgentBridgeNativeCatalogPublication, AgentBridgeRequestSettingsCatalog>? = null
    fun read(availableNativeMetricIds: Set<String>, publication: AgentBridgeNativeCatalogPublication): AgentBridgeRequestSettingsCatalog = synchronized(lock) {
        cached?.takeIf { it.first == publication }?.second ?: AgentBridgeRequestSettingsCatalog(
            registry(), availableNativeMetricIds, publication.revision,
        ).also { cached = publication to it }
    }
}

/** Actual native stores plus compiled catalog. The synchronous issuer transaction may call this
 * only from a worker: the single preferences read must never block the Android main looper.
 * Discovery/explicit requests do not collect private preferences. Selected settings/profile and
 * their pin/rebind state come from one committed DataStore image. No SDK health/provider work. */
internal class AgentBridgeNativeConfigurationReader(
    private val dataStore: DataStore<Preferences>,
    private val settings: SettingsRepositoryImpl,
    private val profiles: ExportProfileRepository,
    private val nativeState: () -> AgentBridgeNativePlanningFacts,
    private val registry: (() -> CoreMetricRegistrySnapshot)? = null,
    private val compiledCatalog: AgentBridgeNativeCompiledCatalog = AgentBridgeNativeCompiledCatalog(),
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
        // Injected registry overrides remain dynamic; only the compiled production source is cached.
        val catalog = registry?.let { AgentBridgeRequestSettingsCatalog(it(), state.availableNativeMetricIds, publication.revision) }
            ?: compiledCatalog.read(state.availableNativeMetricIds, publication)
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
    private val responseTransferNegotiation: TransferNegotiation? = null,
    responsePeerTransferCapabilities: TransferCapabilities? = null,
) {
    private val responsePeerTransferCapabilities = AgentBridgeNativeTransferCheckpoint.detachPeerCapabilities(responsePeerTransferCapabilities)
    private val service: AgentBridgeExportPlanningService
    @Volatile private var wireAbandoned = false
    private val wireOperationActive = AtomicBoolean(false)
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
        if (!wireOperationActive.compareAndSet(false, true)) throw AgentBridgeException(AgentBridgeErrorCode.BUSY)
        try { handleAndSendOwned(bytes, caller) } finally { wireOperationActive.set(false) }
    }
    private fun handleAndSendOwned(bytes: ByteArray, caller: Job) {
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
        if (!wireOperationActive.compareAndSet(false, true)) throw AgentBridgeException(AgentBridgeErrorCode.BUSY)
        return try { receiveAndHandleNextOwned(caller) } finally { wireOperationActive.set(false) }
    }

    /** Installed controller ingress must retain the original encrypted channel, not a
     * freshly supplied peer or another channel with matching identity fields. */
    fun receiveAndHandleNext(channel: DirectSecureChannel, caller: Job): ReceivedAgentBridgePayload? {
        if (responseChannel !== channel) throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
        return receiveAndHandleNext(caller)
    }
    private fun receiveAndHandleNextOwned(caller: Job): ReceivedAgentBridgePayload? {
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
                    handleAndSendOwned(AgentBridgeCodec.encodeEnvelope(received.message, negotiation), caller)
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

    /** Own the whole native capture operation. Caller identity is captured once from the actual
     * coroutine; no request, later read or escaped context can replace it with a fresh Job. */
    suspend fun <T> withCaptureContext(request: AgentBridgeExecuteRequest,
        operation: suspend (AgentBridgeNativeCaptureContext) -> T): T = captureContext(request, false, operation)

    /** Explicit retained-spool recovery only; never a failed-new-request fallback, new acceptance,
     * missing-spool initialization or permission to repeat an ambiguous started SDK day. */
    suspend fun <T> withRetainedCaptureContext(request: AgentBridgeExecuteRequest,
        operation: suspend (AgentBridgeNativeCaptureContext) -> T): T = captureContext(request, true, operation)

    /** Select the original Execute only from protected native storage. Resume supplies no new
     * plan, acceptance or authority; all fields must match the existing signed job and frontier. */
    suspend fun <T> withResumedCaptureContext(resume: AgentBridgeResumeRequest,
        acknowledgement: TransferPartitionAcknowledgement? = null, operation: suspend (AgentBridgeExecuteRequest, AgentBridgeNativeCaptureContext) -> T): T {
        currentCoroutineContext().ensureActive(); requireCurrent()
        val authenticated = peer.requireCurrent()
        if (resume.peer != authenticated) throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
        val request = store.access { transaction ->
            val job = transaction?.state?.acceptedJobs?.singleOrNull {
                val original = it.request()
                original.jobId == resume.jobId && (original.plan as? AgentBridgeGeneratedPlan)?.intent?.peer == authenticated
            } ?: throw AgentBridgeException(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED)
            job.request()
        }
        requireCurrent(); currentCoroutineContext().ensureActive()
        return withRetainedCaptureContext(request) { context ->
            context.requireResumeBeforeBegin(resume, acknowledgement)
            currentCoroutineContext().ensureActive()
            operation(request, context)
        }
    }

    private suspend fun <T> captureContext(request: AgentBridgeExecuteRequest, retained: Boolean,
        operation: suspend (AgentBridgeNativeCaptureContext) -> T): T {
        if (!wireOperationActive.compareAndSet(false, true)) throw AgentBridgeException(AgentBridgeErrorCode.BUSY)
        return try { captureContextOwned(request, retained, operation) } finally { wireOperationActive.set(false) }
    }
    private suspend fun <T> captureContextOwned(request: AgentBridgeExecuteRequest, retained: Boolean,
        operation: suspend (AgentBridgeNativeCaptureContext) -> T): T {
        val negotiation = responseNegotiation ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        if (negotiation.baseApplication != 2 || !negotiation.agentExtension || negotiation.appleQueryExtension || responseChannel == null)
            throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val caller = currentCoroutineContext().job
        try {
            caller.ensureActive()
            val publication = requireCurrent()
            val reservation = if (retained) {
                val bytes = AgentBridgeCodec.encode(request).decodeToString()
                store.access { transaction ->
                    val expected = (request.plan as? AgentBridgeGeneratedPlan)?.intent?.peer
                        ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
                    val job = transaction?.state?.acceptedJobs?.singleOrNull {
                        val prior = it.request()
                        prior.jobId == request.jobId && (prior.plan as? AgentBridgeGeneratedPlan)?.intent?.peer == expected
                    } ?: throw AgentBridgeException(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED)
                    if (job.requestCanonical != bytes) throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
                    val claim = transaction.state.captureClaims?.singleOrNull { it.requestSha256 == job.requestSha256 }
                        ?: throw AgentBridgeException(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED)
                    AgentBridgeExportCaptureReservation(job, claim)
                }.also { captureReadConfiguration(it, caller) }
            } else {
                val accepted = service.acceptExecution(peer, request)
                caller.ensureActive()
                sendAcceptedExecution(accepted.job, request, publication, caller)
                if (!accepted.newlyAccepted) throw AgentBridgeException(AgentBridgeErrorCode.BUSY)
                service.claimCapture(peer, request)
            }
            caller.ensureActive()
            if (wireAbandoned || lifecycle.currentPublication() != publication) throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
            val validate = {
                try {
                    caller.ensureActive()
                    captureReadConfiguration(reservation, caller).also { caller.ensureActive() }
                } catch (failure: Throwable) { caller.ensureActive(); throw failure }
            }
            val spool = store.openCaptureSpool(reservation, !retained) { validate(); Unit }
            val context = AgentBridgeNativeCaptureContext(spool, responseTransferNegotiation, responsePeerTransferCapabilities, validate)
            return try {
                val result = operation(context)
                caller.ensureActive()
                context.configurationForRead()
                result
            } finally { context.close() }
        } catch (failure: Throwable) { caller.ensureActive(); throw failure }
    }

    /** Keep preparation and byte carriage inside the original capture owner. No prepared value
     * can escape as authority, and base byte acknowledgements never declare v4 completion. */
    suspend fun transmitTransfer(request: AgentBridgeExecuteRequest, retained: Boolean, confirmCompletion: Boolean = false,
        prepare: suspend (AgentBridgeNativeCaptureContext) -> AgentBridgeNativePreparedTransfer) {
        val operation: suspend (AgentBridgeNativeCaptureContext) -> Unit = { context ->
            try {
                val supplied = prepare(context)
                if (supplied.export.requestSha256 != context.requestFingerprintForRead() ||
                    !supplied.export.manifestCanonical.contentEquals(context.preserveManifest()) ||
                    !supplied.checkpointCanonical.contentEquals(context.preserveTransferPlan()))
                    throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
                val export = AgentBridgeNativePreparedExport.make(request, supplied.export.days,
                    supplied.export.totalByteCount, supplied.export.publicArtifactIDs, supplied.export.manifestCanonical)
                val transfer = AgentBridgeNativePreparedTransfer.make(request, export, supplied.checkpointCanonical)
                val channel = responseChannel ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
                val caller = currentCoroutineContext().job
                withTransportCancellation(caller, channel) { sendTransferBytes(transfer, context, confirmCompletion) }
                context.configurationForRead()
                Unit
            } catch (failure: Throwable) {
                context.invalidate(); wireAbandoned = true; runCatching { responseChannel?.close() }; throw failure
            }
        }
        if (retained) withRetainedCaptureContext(request, operation) else withCaptureContext(request, operation)
    }

    private fun sendTransferBytes(transfer: AgentBridgeNativePreparedTransfer, context: AgentBridgeNativeCaptureContext, confirmCompletion: Boolean) {
        val channel = responseChannel ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val negotiation = responseNegotiation ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val validate = { context.configurationForRead(); Unit }
        fun invalid(): Nothing = throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
        fun <T> send(type: String, serializer: kotlinx.serialization.SerializationStrategy<T>, payload: T) =
            channel.sendV2ForAgentBridge(type, serializer, payload, negotiation, validate)
        fun <T> receive(type: String, serializer: kotlinx.serialization.DeserializationStrategy<T>): T {
            val envelope = (channel.receiveAllowingAgentBridge(negotiation, validate) as? ReceivedAgentBridgePayload.Base)?.envelope ?: invalid()
            if (envelope.type != type) invalid()
            return V2Codec.decodePayload(envelope, serializer)
        }
        var frontier = context.preserveTransferFrontier()
        val manifest = AgentBridgeCodec.decode(transfer.export.manifestCanonical) as? AgentBridgeArtifactManifest ?: invalid()
        channel.sendAgentBridge(AgentBridgeMessage("artifact_manifest", manifest), negotiation, validate)
        send("transfer_session", TransferSession.serializer(), transfer.session)
        transfer.export.baseFiles.forEach { send("artifact_manifest", ArtifactManifest.serializer(), it.manifest) }
        transfer.partitions.zip(transfer.export.baseFiles).forEach { (partition, file) ->
            send("transfer_open", TransferOpen.serializer(), TransferOpen(transfer.session, partition))
            val disposition = receive("transfer_disposition", TransferDisposition.serializer())
            if (disposition.sessionId != transfer.session.sessionId || disposition.jobId != transfer.session.jobId ||
                disposition.partitionIndex != partition.index || disposition.partitionSha256 != partition.sha256 ||
                disposition.disposition == TransferDispositionKind.REJECTED) invalid()
            if (disposition.disposition == TransferDispositionKind.NEEDED) {
                if (partition.index < frontier.committedPartitionCount) invalid()
                // One reviewed bounded chunk per daily artifact; stop-and-wait respects every
                // admitted original window and uses one receiver for the entire operation.
                channel.sendTransferChunkForAgentBridge(partition.transferId, 1, file.content, negotiation, validate)
                val chunk = receive("transfer_chunk_acknowledgement", TransferChunkAcknowledgement.serializer())
                if (!chunk.accepted || chunk.transferId != partition.transferId || chunk.sequence != 1 || chunk.sha256 != partition.sha256) invalid()
                context.preserveAwaitingPartitionAcknowledgement(partition.index)
                send("transfer_partition_complete", TransferPartitionComplete.serializer(), TransferPartitionComplete(
                    transfer.session.sessionId, transfer.session.jobId, partition.index, partition.transferId, partition.sha256))
                val ack = receive("transfer_partition_acknowledgement", TransferPartitionAcknowledgement.serializer())
                if (!ack.accepted || ack.sessionId != transfer.session.sessionId || ack.jobId != transfer.session.jobId ||
                    ack.partitionIndex != partition.index || ack.transferId != partition.transferId || ack.partitionSha256 != partition.sha256) invalid()
                frontier = context.reconcilePartitionAcknowledgement(ack)
            } else {
                frontier = context.recordAcknowledgedTransferPartition(partition.index)
            }
        }
        if (frontier.committedPartitionCount != transfer.partitions.size.toLong()) invalid()
        val finalize = TransferFinalize(transfer.session.sessionId, transfer.session.jobId, transfer.session.requestFingerprint,
            transfer.partitions.size.toLong(), transfer.export.totalByteCount.toLong(), transfer.partitions.lastOrNull()?.sha256)
        send("transfer_finalize", TransferFinalize.serializer(), finalize)
        val ack = receive("transfer_final_acknowledgement", TransferFinalAcknowledgement.serializer())
        if (!ack.accepted || ack.sessionId != finalize.sessionId || ack.jobId != finalize.jobId ||
            ack.totalPartitions != finalize.totalPartitions || ack.totalBytes != finalize.totalBytes ||
            ack.finalPartitionSha256 != finalize.finalPartitionSha256) invalid()
        context.configurationForRead()
        if (confirmCompletion) confirmTransferCompletion(transfer, context)
    }

    private fun confirmTransferCompletion(transfer: AgentBridgeNativePreparedTransfer, context: AgentBridgeNativeCaptureContext) {
        val channel = responseChannel ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val negotiation = responseNegotiation ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val validate = { context.configurationForRead(); Unit }
        val manifest = AgentBridgeCodec.decode(transfer.export.manifestCanonical) as? AgentBridgeArtifactManifest
            ?: throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
        for (artifact in manifest.artifacts) {
            val message = (channel.receiveAllowingAgentBridge(negotiation, validate) as? ReceivedAgentBridgePayload.Agent)?.message
                ?: throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
            val receipt = message.payload as? AgentBridgeCommitReceipt ?: throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
            if (message.type != "commit_receipt" || receipt.artifactId != artifact.artifactId) throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
            context.recordHostCommit(receipt)
        }
        val receipt = context.preserveCompletion()
        val finalFence = {
            context.requirePreservedCompletion(receipt)
        }
        channel.sendV2ForAgentBridge("completion_confirmed", JobPayload.serializer(), JobPayload(transfer.session.jobId), negotiation, finalFence)
        channel.sendAgentBridge(AgentBridgeMessage("execution_receipt", receipt), negotiation, finalFence)
        finalFence()
    }

    /** Send durable original acceptance before any capture claim or SDK read. Exact retry replays
     * original receipt bytes without renewing the job or granting another capture. */
    private fun sendAcceptedExecution(job: AgentBridgeExportAcceptedJob, request: AgentBridgeExecuteRequest,
        publication: AgentBridgeNativeCatalogPublication, caller: Job) {
        val channel = responseChannel ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        val negotiation = responseNegotiation ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
        try {
            withTransportCancellation(caller, channel) {
                val validate = {
                    caller.ensureActive()
                    requireSamePublication(publication)
                    if (service.acceptExecution(peer, request).job != job || wireAbandoned || lifecycle.currentPublication() != publication)
                        throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
                    caller.ensureActive()
                }
                val response = AgentBridgeMessage("execution_receipt", job.acceptedReceipt())
                validate()
                channel.sendAgentBridge(response, negotiation, validate)
                validate()
            }
        } catch (failure: Throwable) {
            wireAbandoned = true
            runCatching { channel.close() }
            caller.ensureActive()
            throw failure
        }
    }

    /** Original-owner native producer boundary. No SDK reads, claim renewal or installed route. */
    fun captureReadConfiguration(reservation: AgentBridgeExportCaptureReservation, caller: Job): AgentBridgeRequestSettingsResolution {
        caller.ensureActive()
        val publication = requireCurrent()
        val result = service.captureReadConfiguration(peer, reservation)
        // Local-only tail after the service's final live expiry check.
        if (wireAbandoned) throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
        if (lifecycle.currentPublication() != publication) throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
        caller.ensureActive()
        return result
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


/** Native-only operation lease. It cannot be decoded as permission or reused after its callback. */
internal class AgentBridgeNativeCaptureContext internal constructor(private val spool: AgentBridgeNativeCaptureSpool, private val transferNegotiation: TransferNegotiation?, private val peerTransferCapabilities: TransferCapabilities?, read: () -> AgentBridgeRequestSettingsResolution) {
    private val lock = Any()
    private var started = false
    private var closed = false
    private val claimedDays = mutableSetOf<String>()
    private var read: (() -> AgentBridgeRequestSettingsResolution)? = read
    fun requireResumeBeforeBegin(resume: AgentBridgeResumeRequest, acknowledgement: TransferPartitionAcknowledgement? = null) {
        try {
            val callback = synchronized(lock) {
                if (started || closed) throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
                read ?: throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
            }
            callback(); spool.requireResume(resume, acknowledgement); callback()
            spool.requirePreservedResume(resume)
            synchronized(lock) { if (closed) throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED) }
        } catch (failure: Throwable) { invalidate(); throw failure }
    }
    fun begin(): AgentBridgeRequestSettingsResolution {
        synchronized(lock) {
            if (started || closed) { closed = true; read = null; throw AgentBridgeException(AgentBridgeErrorCode.BUSY) }
            started = true
        }
        return configurationForRead()
    }
    /** One in-memory attempt per approved day; not a durable frontier or resume journal. */
    fun claimDay(day: String): AgentBridgeNativeCaptureDayInput {
        try {
            val resolution = configurationForRead()
            if (day !in resolution.requestedDays) throw AgentBridgeException(AgentBridgeErrorCode.INVALID_REQUEST)
            synchronized(lock) {
                if (closed) throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
                if (!claimedDays.add(day)) throw AgentBridgeException(AgentBridgeErrorCode.BUSY)
            }
            return AgentBridgeNativeCaptureDayInput(resolution, spool.loadOrBegin(day))
        } catch (failure: Throwable) { close(); throw failure }
    }
    fun commitDay(day: String, payload: ByteArray) {
        try {
            configurationForRead()
            synchronized(lock) { if (day !in claimedDays) throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED) }
            spool.commit(day, payload)
            configurationForRead()
        } catch (failure: Throwable) { close(); throw failure }
    }
    fun retainedArtifact(day: String): AgentBridgeNativeCaptureSpool.ArtifactCheckpoint? {
        try {
            if (day !in configurationForRead().requestedDays) throw AgentBridgeException(AgentBridgeErrorCode.INVALID_REQUEST)
            val result = spool.retainedArtifact(day)
            configurationForRead(); return result
        } catch (failure: Throwable) { invalidate(); throw failure }
    }
    fun beginArtifact(day: String, engine: ByteArray) {
        try {
            if (day !in configurationForRead().requestedDays) throw AgentBridgeException(AgentBridgeErrorCode.INVALID_REQUEST)
            spool.beginArtifact(day, engine); configurationForRead()
        } catch (failure: Throwable) { invalidate(); throw failure }
    }
    fun commitArtifact(day: String, engine: ByteArray, payload: ByteArray) {
        try {
            if (day !in configurationForRead().requestedDays) throw AgentBridgeException(AgentBridgeErrorCode.INVALID_REQUEST)
            spool.commitArtifact(day, engine, payload); configurationForRead()
        } catch (failure: Throwable) { invalidate(); throw failure }
    }
    fun bindPublicArtifactIDs(): Map<String, String> {
        try {
            val resolution = configurationForRead()
            val result = spool.bindPublicArtifactIDs(resolution.requestedDays)
            configurationForRead(); return result
        } catch (failure: Throwable) { invalidate(); throw failure }
    }
    fun preserveManifest(): ByteArray {
        try {
            configurationForRead()
            val result = spool.preserveManifest()
            configurationForRead(); return result
        } catch (failure: Throwable) { invalidate(); throw failure }
    }
    fun transferNegotiationForRead(): TransferNegotiation {
        try {
            configurationForRead()
            val value = transferNegotiation ?: throw AgentBridgeException(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY)
            AgentBridgeNativeTransferCheckpoint.requireSupported(value, peerTransferCapabilities)
            spool.retainedTransferPlan()?.let { bytes ->
                AgentBridgeNativeTransferCheckpoint.requireSupported(AgentBridgeNativeTransferCheckpoint.decode(bytes).negotiation(), peerTransferCapabilities)
            }
            configurationForRead(); return value
        } catch (failure: Throwable) { invalidate(); throw failure }
    }
    fun preserveTransferPlan(): ByteArray {
        try {
            val result = spool.preserveTransferPlan(transferNegotiationForRead())
            AgentBridgeNativeTransferCheckpoint.requireSupported(AgentBridgeNativeTransferCheckpoint.decode(result).negotiation(), peerTransferCapabilities)
            configurationForRead(); return result
        } catch (failure: Throwable) { invalidate(); throw failure }
    }
    fun preserveTransferFrontier(): AgentBridgeTransferFrontier {
        try {
            configurationForRead()
            val result = spool.preserveTransferFrontier()
            configurationForRead(); return result
        } catch (failure: Throwable) { invalidate(); throw failure }
    }
    fun preserveAwaitingPartitionAcknowledgement(index: Long) {
        try { configurationForRead(); spool.preserveAwaitingPartitionAcknowledgement(index); configurationForRead() }
        catch (failure: Throwable) { invalidate(); throw failure }
    }
    fun reconcilePartitionAcknowledgement(ack: TransferPartitionAcknowledgement): AgentBridgeTransferFrontier {
        try { configurationForRead(); val result = spool.reconcilePartitionAcknowledgement(ack); configurationForRead(); return result }
        catch (failure: Throwable) { invalidate(); throw failure }
    }
    fun recordAcknowledgedTransferPartition(index: Long): AgentBridgeTransferFrontier {
        try {
            configurationForRead()
            val result = spool.recordAcknowledgedTransferPartition(index)
            configurationForRead(); return result
        } catch (failure: Throwable) { invalidate(); throw failure }
    }
    fun recordHostCommit(receipt: AgentBridgeCommitReceipt) {
        try { configurationForRead(); spool.recordHostCommit(receipt); configurationForRead() }
        catch (failure: Throwable) { invalidate(); throw failure }
    }
    fun requirePreservedCompletion(receipt: AgentBridgeExecutionReceipt) {
        try { configurationForRead(); spool.requirePreservedCompletion(receipt) }
        catch (error: Exception) { invalidate(); throw error }
    }
    fun preserveCompletion(): AgentBridgeExecutionReceipt {
        try { configurationForRead(); val result = spool.preserveCompletion(); configurationForRead(); spool.requirePreservedCompletion(result); return result }
        catch (failure: Throwable) { invalidate(); throw failure }
    }
    /** Names the original accepted bytes; a fingerprint is never capture permission. */
    fun requestFingerprintForRead(): String {
        configurationForRead()
        return spool.acceptedRequestSha256
    }
    /** Monotonic denial so catching an SDK/result failure cannot revive the operation. */
    internal fun invalidate() { close() }
    fun configurationForRead(): AgentBridgeRequestSettingsResolution {
        val callback = synchronized(lock) {
            if (!started || closed) throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
            read ?: throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
        }
        return try {
            val result = callback()
            synchronized(lock) { if (closed) throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED) }
            spool.requireCompletionIfPreserved()
            result
        } catch (failure: Throwable) { close(); throw failure }
    }
    internal fun close() { synchronized(lock) { closed = true; read = null; claimedDays.clear(); spool.close() } }
}

internal class AgentBridgeNativeCaptureDayInput(val resolution: AgentBridgeRequestSettingsResolution, val retainedPayload: ByteArray?)
