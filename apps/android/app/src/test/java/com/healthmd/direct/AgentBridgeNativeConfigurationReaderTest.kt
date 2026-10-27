package com.healthmd.direct

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.*
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.AggregateRequest
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.response.ReadRecordsResponse
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.AgentBridgeNativeCaptureFailure
import java.time.Instant
import android.os.Looper
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.*
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.data.settings.SettingsRepositoryImpl
import com.healthmd.direct.protocol.*
import com.healthmd.domain.exportengine.*
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.sharedsetup.SharedSetupV2ProfilePersistence
import io.mockk.*
import java.io.IOException
import java.net.InetAddress
import java.net.ServerSocket
import java.util.concurrent.Executors
import java.util.concurrent.ExecutionException
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference
import java.nio.file.Files
import java.time.ZoneId
import javax.crypto.Mac
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.*
import kotlinx.serialization.json.buildJsonObject
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import org.junit.*
import org.junit.rules.TemporaryFolder

/** Real private DataStore/repositories and planning service. Only Looper, SDK lifecycle facts and
 * the JNI registry load are intercepted; no installed service, device, permission or health work. */
class AgentBridgeNativeConfigurationReaderTest {
    @get:Rule val temporaryFolder = TemporaryFolder()
    private lateinit var scope: CoroutineScope
    private lateinit var backing: DataStore<Preferences>
    private lateinit var observed: DataStore<Preferences>
    private lateinit var settings: SettingsRepositoryImpl
    private lateinit var profiles: ExportProfileRepository
    private var reads = 0
    private var writes = 0
    private var onRead: (() -> Unit)? = null
    private var state = initialState()
    private lateinit var main: Looper

    @Before fun setUp() {
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val file = temporaryFolder.newFolder().resolve("native.preferences_pb")
        backing = PreferenceDataStoreFactory.create(scope = scope, produceFile = { file })
        observed = object : DataStore<Preferences> {
            override val data = backing.data.map { reads++; onRead?.invoke(); it }
            override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences {
                writes++; return backing.updateData(transform)
            }
        }
        settings = SettingsRepositoryImpl(observed, mockk<Context>(relaxed = true))
        profiles = ExportProfileRepository(observed, mockk<Context>(relaxed = true))
        mockkStatic(Looper::class)
        main = mockk()
        every { Looper.getMainLooper() } returns main
        every { Looper.myLooper() } returns null // Worker boundary only; not native thread qualification.
        state = initialState()
    }
    @After fun tearDown(): Unit = runBlocking {
        try {
            scope.cancel()
            scope.coroutineContext[Job]?.join()
        } finally {
            try {
                // MockK's global proxy handlers retain recorded calls and their mock arguments.
                // Release completed fixtures only after their coroutine work has stopped.
                clearAllMocks()
            } finally {
                unmockkStatic(Looper::class)
            }
        }
    }
    private fun reader(store: DataStore<Preferences> = observed) = AgentBridgeNativeConfigurationReader(
        store, settings, profiles, { state }, { AgentBridgeExportTestRegistry.load() })
    private fun reset() { reads = 0; writes = 0 }
    private fun AgentBridgeNativeConfigurationReader.readPublishedConfiguration(policy: AgentBridgeSettingsPolicy?) =
        readConfiguration(policy, AgentBridgeNativeCatalogPublication(1, AgentBridgeExportPlanningFixture.id(1),
            state.fingerprint(AgentBridgeExportPlanningFixture.id(1))))

    private fun ownedPlanner(f: AgentBridgeExportPlanningFixture, lifecycle: AgentBridgeNativeCatalogLifecycle, channel: DirectSecureChannel? = null, negotiation: AgentBridgeNegotiation = nativeNegotiation(), transferNegotiation: TransferNegotiation? = TransferCapabilities().negotiatedWith(TransferCapabilities()), peerTransferCapabilities: TransferCapabilities? = TransferCapabilities(), beforeNativeRead: () -> Unit = {}) =
        AgentBridgeNativePlanningSession(f.peerContext, lifecycle, f.store,
            AgentBridgeNativeConfigurationReader(observed, settings, profiles, { beforeNativeRead(); lifecycle.currentFacts() },
                { AgentBridgeExportTestRegistry.load() }), f.clock, responseChannel = channel, responseNegotiation = negotiation, responseTransferNegotiation = transferNegotiation, responsePeerTransferCapabilities = peerTransferCapabilities)
    @Test fun `native accepted receipt precedes capture and replays original bytes`() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            val receipts = mutableListOf<ByteArray>()
            every { channel.sendAgentBridge(any(), any(), any()) } answers {
                val fence = thirdArg<() -> Unit>(); fence()
                val message = firstArg<AgentBridgeMessage>()
                assertThat(message.type).isEqualTo("execution_receipt")
                receipts += AgentBridgeCodec.encode(message.payload)
                fence()
            }
            val planner = ownedPlanner(f, lifecycle, channel)
            val request = nativeCaptureRequest(f, planner)
            planner.withCaptureContext(request) { context ->
                assertThat(receipts.size).isEqualTo(1)
                context.begin()
            }
            val job = f.store.access { it!!.state.acceptedJobs!!.single() }
            try { planner.withCaptureContext(request) { error("Retry must not recapture") }; throw AssertionError("Expected existing job") }
            catch (failure: AgentBridgeException) { assertThat(failure.code).isEqualTo(AgentBridgeErrorCode.BUSY) }
            assertThat(receipts.size).isEqualTo(2)
            assertThat(receipts[0]).isEqualTo(receipts[1])
            val receipt = AgentBridgeCodec.decode(receipts[0]) as AgentBridgeExecutionReceipt
            assertThat(receipt).isEqualTo(job.acceptedReceipt())
            assertThat(receipt.requestSha256).isEqualTo(AgentBridgeCodec.sha256(AgentBridgeCodec.encode(request)))
            assertThat(receipt.expiresAt).isEqualTo(job.expiresAt)
            assertThat(receipt.status).isEqualTo(AgentBridgeExecutionReceiptStatus.ACCEPTED)
            assertThat(receipt.manifestSha256).isEqualTo("0".repeat(64)); assertThat(receipt.frontierSha256).isEqualTo("0".repeat(64))
            assertThat(receipt.sourceAcknowledged).isFalse()
            assertThat(receipt.artifactCount).isEqualTo(0); assertThat(receipt.committedPartitionCount).isEqualTo(0)
            assertThat(f.store.access { it!!.state.captureClaims!!.size }).isEqualTo(1)
        }
    }

    private fun preparationPlanner(f: AgentBridgeExportPlanningFixture, channel: DirectSecureChannel): Pair<AgentBridgeNativePlanningSession, AgentBridgeExecuteRequest> {
        f.enrolled()
        val lifecycle = AgentBridgeNativeCatalogLifecycle()
        lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
        val planner = ownedPlanner(f, lifecycle, channel)
        return planner to nativeCaptureRequest(f, planner, listOf("steps"),
            AgentBridgeDatesExact(AgentBridgeRange("2026-03-08", "2026-03-08"), "exact"))
    }

    @Test fun `native Stop during preparation waits for worker cleanup before acknowledging`() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            val (planner, request) = preparationPlanner(f, channel)
            val stop = stopRequest(request)
            val entered = java.util.concurrent.CountDownLatch(1)
            val cleanupEntered = CompletableDeferred<Unit>()
            val releaseCleanup = CompletableDeferred<Unit>()
            val cleanupExited = java.util.concurrent.atomic.AtomicBoolean(false)
            val acknowledged = java.util.concurrent.atomic.AtomicBoolean(false)
            every { channel.receiveAllowingAgentBridge(any(), any()) } answers {
                check(entered.await(10, TimeUnit.SECONDS))
                secondArg<() -> Unit>().invoke()
                ReceivedAgentBridgePayload.Agent(AgentBridgeMessage("cancel_request", stop))
            }
            every { channel.sendAgentBridge(any(), any(), any()) } answers {
                val message = firstArg<AgentBridgeMessage>()
                val receipt = message.payload as? AgentBridgeExecutionReceipt
                thirdArg<() -> Unit>().invoke()
                if (receipt?.sourceAcknowledged == true) {
                    assertThat(cleanupExited.get()).isTrue()
                    assertThat(receipt.status).isEqualTo(AgentBridgeExecutionReceiptStatus.CANCELLED)
                    acknowledged.set(true)
                }
            }
            val export = async(Dispatchers.IO) {
                try {
                    planner.transmitTransfer(request, retained = false) { context ->
                        context.begin(); entered.countDown()
                        try {
                            // Synthetic in-flight SDK work returns only after Stop has been stored.
                            while (f.store.access { transaction ->
                                transaction!!.state.cancellationIntents.orEmpty().none { it.request().jobId == request.jobId }
                            }) delay(10)
                            cleanupEntered.complete(Unit)
                            releaseCleanup.await()
                            throw AgentBridgeException(AgentBridgeErrorCode.CANCELLED)
                        } finally { cleanupExited.set(true) }
                    }
                    throw AssertionError("Confirmed Stop must terminate this transfer as cancelled")
                } catch (failure: AgentBridgeException) {
                    assertThat(failure.code).isEqualTo(AgentBridgeErrorCode.CANCELLED)
                    assertThat(acknowledged.get()).isTrue()
                }
            }
            try {
                withContext(Dispatchers.IO) { check(entered.await(10, TimeUnit.SECONDS)) }
                withTimeout(10_000) { cleanupEntered.await() }
                assertThat(acknowledged.get()).isFalse()
                releaseCleanup.complete(Unit)
                withTimeout(10_000) { export.await() }
                assertThat(acknowledged.get()).isTrue()
                assertThat(f.store.access { it!!.state.cancellationIntents!!.single().terminalReceipt()!!.sourceAcknowledged }).isTrue()
                verify(exactly = 1) { channel.receiveAllowingAgentBridge(any(), any()) }
                verify(exactly = 0) { channel.close() }
            } finally { releaseCleanup.complete(Unit); export.cancelAndJoin() }
        }
    }

    @Test fun `native preparation failure closes and joins its blocked reader without terminal proof`() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            val (planner, request) = preparationPlanner(f, channel)
            val readerEntered = java.util.concurrent.CountDownLatch(1)
            val closed = java.util.concurrent.CountDownLatch(1)
            val readerExited = java.util.concurrent.atomic.AtomicBoolean(false)
            every { channel.close() } answers { closed.countDown() }
            every { channel.receiveAllowingAgentBridge(any(), any()) } answers {
                secondArg<() -> Unit>().invoke(); readerEntered.countDown()
                try { check(closed.await(10, TimeUnit.SECONDS)); throw IOException("Synthetic closed channel") }
                finally { readerExited.set(true) }
            }
            try {
                withTimeout(10_000) {
                    planner.transmitTransfer(request, false) { context ->
                        context.begin()
                        withContext(Dispatchers.IO) { check(readerEntered.await(10, TimeUnit.SECONDS)) }
                        throw AgentBridgeException(AgentBridgeErrorCode.INVALID_REQUEST)
                    }
                }
                throw AssertionError("Preparation failure returned success")
            } catch (failure: AgentBridgeException) { assertThat(failure.code).isEqualTo(AgentBridgeErrorCode.INVALID_REQUEST) }
            assertThat(readerExited.get()).isTrue()
            assertThat(f.store.access { it!!.state.cancellationIntents.orEmpty() }).isEmpty()
            verify(atLeast = 1) { channel.close() }
            verify(exactly = 0) { channel.sendAgentBridge(match { (it.payload as? AgentBridgeExecutionReceipt)?.sourceAcknowledged == true }, any(), any()) }
        }
    }

    @Test fun `native invalid preparation controls close promptly and join worker cleanup without acknowledgement`() = runBlocking {
        for (mode in listOf("foreign-job", "foreign-binding", "unexpected-frame", "read-failure")) AgentBridgeExportPlanningFixture().use { f ->
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            val (planner, request) = preparationPlanner(f, channel)
            val entered = java.util.concurrent.CountDownLatch(1)
            val releaseCleanup = CompletableDeferred<Unit>()
            val closed = CompletableDeferred<Unit>()
            val cleanupExited = java.util.concurrent.atomic.AtomicBoolean(false)
            every { channel.close() } answers { closed.complete(Unit); Unit }
            every { channel.receiveAllowingAgentBridge(any(), any()) } answers {
                check(entered.await(10, TimeUnit.SECONDS)); secondArg<() -> Unit>().invoke()
                when (mode) {
                    "read-failure" -> throw IOException("Synthetic inbound failure")
                    "unexpected-frame" -> ReceivedAgentBridgePayload.Base(V2Codec.decode(V2Codec.encode("status_request", JsonObject.serializer(), JsonObject(emptyMap()))))
                    else -> ReceivedAgentBridgePayload.Agent(AgentBridgeMessage("cancel_request", stopRequest(request).let {
                        if (mode == "foreign-job") it.copy(jobId = AgentBridgeExportPlanningFixture.id(99)) else it.copy(requestSha256 = "0".repeat(64))
                    }))
                }
            }
            val export = async(Dispatchers.IO) {
                try {
                    planner.transmitTransfer(request, false) { context ->
                        context.begin(); entered.countDown()
                        try { withContext(NonCancellable) { releaseCleanup.await() }; throw AgentBridgeException(AgentBridgeErrorCode.CANCELLED) }
                        finally { cleanupExited.set(true) }
                    }
                    throw AssertionError("Invalid control returned success")
                } catch (failure: Exception) { failure }
            }
            try {
                withTimeout(10_000) { closed.await() }
                assertThat(export.isCompleted).isFalse()
                releaseCleanup.complete(Unit)
                val failure = withTimeout(10_000) { export.await() }
                if (mode == "read-failure") assertThat(failure).isInstanceOf(IOException::class.java)
                else assertThat((failure as AgentBridgeException).code).isEqualTo(AgentBridgeErrorCode.BINDING_CHANGED)
                assertThat(cleanupExited.get()).isTrue()
                assertThat(f.store.access { it!!.state.cancellationIntents.orEmpty() }).isEmpty()
                verify(exactly = 0) { channel.sendAgentBridge(match { (it.payload as? AgentBridgeExecutionReceipt)?.sourceAcknowledged == true }, any(), any()) }
            } finally { releaseCleanup.complete(Unit); export.cancelAndJoin() }
        }
    }

    @Test fun `native preparation caller cancellation closes promptly and joins SDK and reader cleanup`() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            val (planner, request) = preparationPlanner(f, channel)
            val entered = java.util.concurrent.CountDownLatch(1)
            val readClosed = java.util.concurrent.CountDownLatch(1)
            val readerEntered = java.util.concurrent.CountDownLatch(1)
            val closed = CompletableDeferred<Unit>()
            val releaseCleanup = CompletableDeferred<Unit>()
            val cleanupExited = java.util.concurrent.atomic.AtomicBoolean(false)
            val readerExited = java.util.concurrent.atomic.AtomicBoolean(false)
            every { channel.close() } answers { readClosed.countDown(); closed.complete(Unit); Unit }
            every { channel.receiveAllowingAgentBridge(any(), any()) } answers {
                secondArg<() -> Unit>().invoke(); readerEntered.countDown()
                try { check(readClosed.await(10, TimeUnit.SECONDS)); throw IOException("Synthetic closed channel") }
                finally { readerExited.set(true) }
            }
            val export = async(Dispatchers.IO) {
                planner.transmitTransfer(request, false) { context ->
                    context.begin(); entered.countDown()
                    try { withContext(NonCancellable) { releaseCleanup.await() }; throw AgentBridgeException(AgentBridgeErrorCode.CANCELLED) }
                    finally { cleanupExited.set(true) }
                }
            }
            try {
                withContext(Dispatchers.IO) {
                    check(entered.await(10, TimeUnit.SECONDS))
                    check(readerEntered.await(10, TimeUnit.SECONDS))
                }
                export.cancel()
                withTimeout(10_000) { closed.await() }
                assertThat(export.isCompleted).isFalse()
                releaseCleanup.complete(Unit)
                withTimeout(10_000) { export.join() }
                assertThat(export.isCancelled).isTrue()
                assertThat(cleanupExited.get()).isTrue(); assertThat(readerExited.get()).isTrue()
                assertThat(f.store.access { it!!.state.cancellationIntents.orEmpty() }).isEmpty()
                verify(exactly = 0) { channel.sendAgentBridge(match { (it.payload as? AgentBridgeExecutionReceipt)?.sourceAcknowledged == true }, any(), any()) }
            } finally { releaseCleanup.complete(Unit); export.cancelAndJoin() }
        }
    }

    @Test fun `native accepted receipt failure or revocation prevents capture claim`() = runBlocking {
        for (revoke in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            every { channel.sendAgentBridge(any(), any(), any()) } answers {
                assertThat(f.store.access { it!!.state.acceptedJobs!!.size }).isEqualTo(1)
                assertThat(f.store.access { it!!.state.captureClaims.orEmpty() }).isEmpty()
                if (revoke) { lifecycle.stop(); thirdArg<() -> Unit>()() }
                throw java.io.IOException("synthetic interrupted acceptance")
            }
            val planner = ownedPlanner(f, lifecycle, channel)
            val request = nativeCaptureRequest(f, planner)
            try { planner.withCaptureContext(request) { error("No SDK callback before accepted receipt") }; throw AssertionError("Expected denial") }
            catch (failure: Exception) { if (revoke) assertThat(failure).isInstanceOf(AgentBridgeException::class.java) }
            assertThat(f.store.access { it!!.state.acceptedJobs!!.size }).isEqualTo(1)
            assertThat(f.store.access { it!!.state.captureClaims.orEmpty() }).isEmpty()
            verify(exactly = 1) { channel.close() }
        }
    }

    private fun nativeNegotiation() = AgentBridgeNegotiation.negotiate(AgentBridgePlatform.ANDROID, listOf(2, 4), listOf(2, 4))
    private fun ownedDiscoveryBytes(f: AgentBridgeExportPlanningFixture) = AgentBridgeCodec.encodeEnvelope(
        AgentBridgeMessage("discovery_request", f.discoveryRequest()), nativeNegotiation())

    private fun nativeCaptureRequest(f: AgentBridgeExportPlanningFixture, planner: AgentBridgeNativePlanningSession, metrics: List<String> = listOf("heart_rate_avg", "steps"), dates: AgentBridgeDates = AgentBridgeDatesExact(AgentBridgeRange("2026-03-08", "2026-03-07"), "exact")): AgentBridgeExecuteRequest {
        fun send(message: AgentBridgeMessage) = AgentBridgeCodec.decodeEnvelope(planner.handleEnvelope(
            AgentBridgeCodec.encodeEnvelope(message, nativeNegotiation()), nativeNegotiation()), nativeNegotiation()).payload
        val discovery = send(AgentBridgeMessage("discovery_request", f.discoveryRequest())) as AgentBridgeDiscovery
        val plan = send(AgentBridgeMessage("plan_request", f.request(discovery, f.intent(metrics = metrics, dates = dates)))) as AgentBridgeGeneratedPlan
        val approval = planner.authorizeExactApproval(f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
        return AgentBridgeExecuteRequest(approval, AgentBridgeExportPlanningFixture.id(81), AgentBridgeExportPlanningFixture.id(82), plan,
            AgentBridgeExportPlanningFixture.id(83), "healthmd.agent_execute_request", 1)
    }

    private suspend fun withNativeSDKCapture(metrics: List<String>, afterCapture: (suspend (AgentBridgeExportPlanningFixture, AgentBridgeNativePlanningSession, AgentBridgeExecuteRequest, HealthConnectClient, HealthConnectManager, Throwable?) -> Unit)? = null, operation: suspend (AgentBridgeExportPlanningFixture, AgentBridgeNativeCaptureContext, HealthConnectClient, HealthConnectManager) -> Unit) {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val planner = ownedPlanner(f, lifecycle, mockk<DirectSecureChannel>(relaxed = true))
            val request = nativeCaptureRequest(f, planner, metrics)
            val client = mockk<HealthConnectClient>(relaxed = true)
            coEvery { client.permissionController.getGrantedPermissions() } returns setOf(
                HealthPermission.getReadPermission(StepsRecord::class), HealthPermission.getReadPermission(HeartRateRecord::class),
                HealthPermission.getReadPermission(RestingHeartRateRecord::class), HealthPermission.getReadPermission(HeartRateVariabilityRmssdRecord::class))
            val manager = HealthConnectManager(mockk<Context>(relaxed = true), client)
            val preferenceReads = reads; val preferenceWrites = writes
            try {
                var originalFailure: Throwable? = null
                try {
                    planner.withCaptureContext(request) { context ->
                        context.begin()
                        operation(f, context, client, manager)
                    }
                } catch (failure: Throwable) { originalFailure = failure }
                afterCapture?.invoke(f, planner, request, client, manager, originalFailure)
                originalFailure?.let { throw it }
            } finally {
                assertThat(f.store.access { it!!.state.captureClaims!!.size }).isEqualTo(1)
                assertThat(reads).isEqualTo(preferenceReads); assertThat(writes).isEqualTo(preferenceWrites)
            }
        }
    }

    private suspend fun withNativeExportPreparation(transferNegotiation: TransferNegotiation? = TransferCapabilities().negotiatedWith(TransferCapabilities()), peerTransferCapabilities: TransferCapabilities? = TransferCapabilities(), dates: AgentBridgeDates = AgentBridgeDatesExact(AgentBridgeRange("2026-03-08", "2026-03-07"), "exact"), operation: suspend (AgentBridgeExportPlanningFixture, AgentBridgeNativePlanningSession, AgentBridgeExecuteRequest, HealthConnectClient, HealthConnectManager) -> Unit) {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val planner = ownedPlanner(f, lifecycle, mockk<DirectSecureChannel>(relaxed = true), transferNegotiation = transferNegotiation, peerTransferCapabilities = peerTransferCapabilities)
            val request = nativeCaptureRequest(f, planner, listOf("steps"), dates)
            val client = mockk<HealthConnectClient>(relaxed = true)
            coEvery { client.permissionController.getGrantedPermissions() } returns setOf(HealthPermission.getReadPermission(StepsRecord::class))
            val manager = HealthConnectManager(mockk<Context>(relaxed = true), client)
            val preferenceReads = reads; val preferenceWrites = writes
            try { operation(f, planner, request, client, manager) }
            finally {
                try {
                    assertThat(f.store.access { it!!.state.captureClaims!!.size }).isEqualTo(1)
                    assertThat(reads).isEqualTo(preferenceReads); assertThat(writes).isEqualTo(preferenceWrites)
                } finally {
                    // Each mode owns a complete fixture, including its mock call graph.
                    // Restore the same class-scoped worker-boundary answers after cleanup.
                    clearAllMocks()
                    every { Looper.getMainLooper() } returns main
                    every { Looper.myLooper() } returns null
                }
            }
        }
    }

    private fun transferReconnect(f: AgentBridgeExportPlanningFixture, capabilities: TransferCapabilities): AgentBridgeNativePlanningSession {
        val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
        return ownedPlanner(f, lifecycle, mockk<DirectSecureChannel>(relaxed = true),
            transferNegotiation = TransferCapabilities().negotiatedWith(capabilities), peerTransferCapabilities = capabilities)
    }

    @Test fun `retained transfer allows changed preference and detached peer lists`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val original = planner.prepareTransferExport(request, manager, journalRenderer(resolution))
            val job = f.store.access { it!!.state.acceptedJobs!!.single() }
            val path = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(job.requestSha256)
            val progress = Files.readAllBytes(path.resolve("progress.json"))
            val protocols = mutableListOf(1); val frames = mutableListOf(1)
            val caps = TransferCapabilities(protocolVersions = protocols, binaryFrameVersions = frames, preferredPartitionBytes = MAXIMUM_PARTITION_BYTES, maximumInFlightChunks = 8)
            assertThat(TransferCapabilities().negotiatedWith(caps)!!.partitionTargetBytes).isNotEqualTo(original.session.partitionTargetBytes)
            val reconnect = transferReconnect(f, caps)
            protocols.clear(); frames.clear() // The owner captured immutable original hello facts.
            coEvery { client.aggregate(any()) } throws IllegalStateException("Must not query")
            val forbidden = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { error("Must not render") }, pinLoader = { error("Must not load current core") })
            val restored = reconnect.prepareRetainedTransferExport(request, manager, forbidden)
            assertThat(restored.session).isEqualTo(original.session); assertThat(restored.partitions).isEqualTo(original.partitions)
            assertThat(restored.checkpointCanonical).isEqualTo(original.checkpointCanonical)
            assertThat(Files.readAllBytes(path.resolve("progress.json"))).isEqualTo(progress)
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }

    @Test fun `retained transfer rejects unsupported original target or window without mutation`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val original = planner.prepareTransferExport(request, manager, journalRenderer(resolution))
            val job = f.store.access { it!!.state.acceptedJobs!!.single() }
            val path = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(job.requestSha256)
            val progress = Files.readAllBytes(path.resolve("progress.json"))
            coEvery { client.aggregate(any()) } throws IllegalStateException("Must not query")
            val forbidden = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { error("Must not render") }, pinLoader = { error("Must not load current core") })
            for (caps in listOf(TransferCapabilities(maximumInFlightChunks = 2), TransferCapabilities(minimumPartitionBytes = MAXIMUM_PARTITION_BYTES, preferredPartitionBytes = MAXIMUM_PARTITION_BYTES))) {
                val reconnect = transferReconnect(f, caps)
                try { reconnect.prepareRetainedTransferExport(request, manager, forbidden); throw AssertionError("Original limits must remain supported") }
                catch (failure: AgentBridgeException) { assertThat(failure.code).isEqualTo(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) }
                assertThat(Files.readAllBytes(path.resolve("progress.json"))).isEqualTo(progress)
                assertThat(Files.readAllBytes(path.resolve("transfer.json"))).isEqualTo(original.checkpointCanonical)
            }
            coVerify(exactly = 2) { client.aggregate(any()) }
            val restored = transferReconnect(f, TransferCapabilities()).prepareRetainedTransferExport(request, manager, forbidden)
            assertThat(restored.checkpointCanonical).isEqualTo(original.checkpointCanonical)
        }
    }

    @Test fun `native transfer requires current peer capabilities before SDK`() = runBlocking {
        withNativeExportPreparation(peerTransferCapabilities = null) { _, planner, request, client, manager ->
            try { planner.prepareTransferExport(request, manager); throw AssertionError("A selected value cannot replace peer support") }
            catch (failure: AgentBridgeException) { assertThat(failure.code).isEqualTo(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) }
            coVerify(exactly = 0) { client.aggregate(any()) }
        }
    }

    @Test fun `native transfer support rejects invalid or unnegotiated capabilities`() {
        val selected = requireNotNull(TransferCapabilities().negotiatedWith(TransferCapabilities()))
        for (caps in listOf(TransferCapabilities(protocolVersions = listOf(2)), TransferCapabilities(binaryFrameVersions = listOf(2)),
            TransferCapabilities(preferredPartitionBytes = 1), TransferCapabilities(maximumInFlightChunks = 0))) {
            try { AgentBridgeNativeTransferCheckpoint.requireSupported(selected, caps); throw AssertionError("Invalid support must reject") }
            catch (failure: AgentBridgeException) { assertThat(failure.code).isEqualTo(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) }
        }
        try { AgentBridgeNativeTransferCheckpoint.requireSupported(selected.copy(maximumInFlightChunks = 8), TransferCapabilities(maximumInFlightChunks = 8)); throw AssertionError("Local bounds must still hold") }
        catch (failure: AgentBridgeException) { assertThat(failure.code).isEqualTo(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) }
        AgentBridgeNativeTransferCheckpoint.requireSupported(selected.copy(maximumInFlightChunks = 2), TransferCapabilities())
    }

    @Test fun `native export producer prepares every approved day and recovers exact set`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val result = planner.prepareExport(request, manager, journalRenderer(resolution))
            val job = f.store.access { it!!.state.acceptedJobs!!.single() }
            assertThat(result.requestSha256).isEqualTo(job.requestSha256)
            assertThat(result.days.map { it.day }).isEqualTo(resolution.requestedDays)
            assertThat(result.days.map { it.artifact.relativePath }).isEqualTo(resolution.predictedRelativePaths)
            assertThat(result.days.size).isEqualTo(2)
            assertThat(result.publicArtifactIDs.keys).isEqualTo(resolution.requestedDays.toSet())
            assertThat(result.publicArtifactIDs.values.toSet()).hasSize(2)
            result.publicArtifactIDs.values.forEach { id ->
                val parsed = java.util.UUID.fromString(id)
                assertThat(parsed.version()).isEqualTo(4); assertThat(parsed.variant()).isEqualTo(2)
                assertThat(parsed.toString()).isEqualTo(id)
            }
            try { (result.publicArtifactIDs as MutableMap<String, String>).clear(); throw AssertionError("Identity map must be immutable") }
            catch (_: UnsupportedOperationException) { }
            val progressPath = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(job.requestSha256).resolve("progress.json")
            val progressBefore = Files.readAllBytes(progressPath)
            val manifest = AgentBridgeCodec.decode(result.manifestCanonical) as AgentBridgeArtifactManifest
            assertThat(AgentBridgeCodec.encode(manifest)).isEqualTo(result.manifestCanonical)
            assertThat(manifest.jobId).isEqualTo(request.jobId)
            assertThat(manifest.requestSha256).isEqualTo(result.requestSha256)
            assertThat(manifest.binding).isEqualTo(AgentBridgeValidation.bindingFor(request.plan))
            assertThat(manifest.captureStatus).isEqualTo(AgentBridgeArtifactManifestCaptureStatus.COMPLETE)
            assertThat(manifest.branchStatuses.map { it.selectorId }).containsExactly("steps")
            assertThat(manifest.branchStatuses.map { it.recordCount }).containsExactly(2)
            assertThat(manifest.artifacts).hasSize(result.days.size)
            manifest.artifacts.zip(result.days).forEach { (artifact, day) ->
                assertThat(artifact.artifactId).isEqualTo(result.publicArtifactIDs[day.day])
                assertThat(artifact.relativePath).isEqualTo(day.artifact.relativePath)
                assertThat(artifact.sha256).isEqualTo(day.artifact.sha256)
                assertThat(artifact.byteCount).isEqualTo(day.artifact.byteCount.toLong())
                assertThat(artifact.profile).isEqualTo(AgentBridgeArtifactProfile.ANDROID_FROZEN_V4)
                assertThat(artifact.writeMode).isEqualTo(AgentBridgeWriteMode.OVERWRITE)
            }
            assertThat(result.baseFiles).hasSize(manifest.artifacts.size)
            result.baseFiles.zip(manifest.artifacts).forEach { (file, artifact) ->
                val base = file.manifest
                assertThat(base.jobId).isEqualTo(request.jobId); assertThat(base.artifactId).isEqualTo(artifact.artifactId)
                assertThat(base.kind).isEqualTo(ArtifactKind.GENERATED_FILE)
                assertThat(base.schema).isEqualTo(ArtifactSchema("healthmd.generated-files", 1))
                assertThat(base.relativePath).isEqualTo(artifact.relativePath); assertThat(base.byteCount).isEqualTo(artifact.byteCount)
                assertThat(base.sha256).isEqualTo(artifact.sha256); assertThat(base.writeMode).isEqualTo(FileWriteMode.OVERWRITE)
                assertThat(base.mediaType).isEqualTo("application/json")
                assertThat(AgentBridgeCodec.sha256(file.content)).isEqualTo(base.sha256)
                val copy = file.content; copy.fill(0)
                assertThat(AgentBridgeCodec.sha256(file.content)).isEqualTo(base.sha256)
                assertThat(Json.decodeFromString(ArtifactManifest.serializer(), Json.encodeToString(ArtifactManifest.serializer(), base))).isEqualTo(base)
            }
            try { (result.baseFiles as MutableList<AgentBridgeNativePreparedFile>).clear(); throw AssertionError("Base files must be immutable") }
            catch (_: UnsupportedOperationException) { }
            val callerCopy = result.manifestCanonical; callerCopy.fill(0)
            assertThat(result.manifestCanonical).isEqualTo(AgentBridgeCodec.encode(manifest))
            assertThat(result.totalByteCount).isEqualTo(result.days.fold(0uL) { n, day -> n + day.artifact.byteCount })
            try { planner.prepareExport(request, manager, journalRenderer(resolution)); throw AssertionError("New execution must not replay capture") }
            catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.BUSY) }
            coEvery { client.aggregate(any()) } throws IllegalStateException("Must not query")
            val before = Files.readAllBytes(f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))
            val forbidden = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { error("Must not render") }, pinLoader = { error("Must not load current core") })
            val restored = planner.prepareRetainedExport(request, manager, forbidden)
            assertThat(restored.requestSha256).isEqualTo(result.requestSha256)
            assertThat(restored.totalByteCount).isEqualTo(result.totalByteCount)
            assertThat(restored.publicArtifactIDs).isEqualTo(result.publicArtifactIDs)
            assertThat(restored.manifestCanonical).isEqualTo(result.manifestCanonical)
            assertThat(restored.baseFiles.map { it.manifest }).isEqualTo(result.baseFiles.map { it.manifest })
            restored.baseFiles.zip(result.baseFiles).forEach { (actual, expected) -> assertThat(actual.content).isEqualTo(expected.content) }
            assertThat(Files.readAllBytes(progressPath)).isEqualTo(progressBefore)
            assertThat(restored.days.map { it.day }).isEqualTo(result.days.map { it.day })
            restored.days.zip(result.days).forEach { (actual, expected) ->
                assertThat(actual.artifact.artifactId).isEqualTo(expected.artifact.artifactId)
                assertThat(actual.artifact.content).isEqualTo(expected.artifact.content)
                assertThat(actual.artifact.relativePath).isEqualTo(expected.artifact.relativePath)
                assertThat(actual.pin).isEqualTo(expected.pin)
            }
            coVerify(exactly = 2) { client.aggregate(any()) }
            assertThat(Files.readAllBytes(f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))).isEqualTo(before)
        }
    }

    @Test fun `native base manifest adapter rejects metadata and whole set drift`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val result = planner.prepareExport(request, manager, journalRenderer(resolution))
            val objectValue = Json.parseToJsonElement(result.manifestCanonical.decodeToString()).jsonObject
            val changes = mapOf("artifact_id" to JsonPrimitive(java.util.UUID.randomUUID().toString()),
                "relative_path" to JsonPrimitive("different.json"), "byte_count" to JsonPrimitive(1),
                "sha256" to JsonPrimitive("0".repeat(64)), "write_mode" to JsonPrimitive("append"),
                "profile" to JsonPrimitive("apple-v8"), "media_type" to JsonPrimitive("text/csv"))
            fun reject(bytes: ByteArray, days: List<AgentBridgeNativeRenderedDay> = result.days, total: ULong = result.totalByteCount) {
                try { AgentBridgeNativePreparedExport.make(request, days, total, result.publicArtifactIDs, bytes)
                    throw AssertionError("Changed base/v4 binding must reject")
                } catch (_: AgentBridgeNativeRenderException) { } catch (_: AgentBridgeException) { }
            }
            changes.forEach { (key, value) ->
                val artifacts = objectValue.getValue("artifacts").jsonArray.toMutableList()
                artifacts[0] = JsonObject(artifacts[0].jsonObject.toMutableMap().also { it[key] = value })
                reject(AgentBridgeCodec.canonicalize(JsonObject(objectValue.toMutableMap().also { it["artifacts"] = JsonArray(artifacts) }).toString().toByteArray()))
            }
            reject(result.manifestCanonical, days = result.days.dropLast(1))
            reject(result.manifestCanonical, total = result.totalByteCount + 1uL)
            reject(AgentBridgeCodec.canonicalize(JsonObject(objectValue.toMutableMap().also { it["request_sha256"] = JsonPrimitive("0".repeat(64)) }).toString().toByteArray()))
            val artifacts = objectValue.getValue("artifacts").jsonArray
            val partial = AgentBridgeCodec.canonicalize(JsonObject(objectValue.toMutableMap().also {
                it["artifacts"] = JsonArray(artifacts.dropLast(1)) }).toString().toByteArray())
            try {
                AgentBridgeNativePreparedExport.make(request, result.days.dropLast(1), result.days.first().artifact.byteCount,
                    result.publicArtifactIDs.filterKeys { it == result.days.first().day }, partial)
                throw AssertionError("Coordinated truncation must not narrow the approved plan")
            } catch (_: AgentBridgeNativeRenderException) { } catch (_: AgentBridgeException) { }
            reject(AgentBridgeCodec.canonicalize(JsonObject(objectValue.toMutableMap().also {
                it["artifacts"] = JsonArray(artifacts.reversed()) }).toString().toByteArray()), days = result.days.reversed())
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }

    @Test fun `native base adapter rejects coordinated malformed interior day`() = runBlocking {
        withNativeExportPreparation(dates = AgentBridgeDatesExact(AgentBridgeRange("2026-03-09", "2026-03-07"), "exact")) { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val result = planner.prepareExport(request, manager, journalRenderer(resolution))
            assertThat(result.days).hasSize(3)
            val middle = result.days[1]
            val changedDay = middle.day + "x"
            val days = result.days.toMutableList().also { it[1] = AgentBridgeNativeRenderedDay(changedDay, middle.artifact, middle.pin) }
            val ids = result.publicArtifactIDs.toMutableMap().also { it[changedDay] = it.remove(middle.day)!! }
            try {
                AgentBridgeNativePreparedExport.make(request, days, result.totalByteCount, ids, result.manifestCanonical)
                throw AssertionError("Malformed interior day cannot satisfy original approved range")
            } catch (_: AgentBridgeNativeRenderException) { }
            coVerify(exactly = 3) { client.aggregate(any()) }
        }
    }

    private fun resumeRequest(request: AgentBridgeExecuteRequest, transfer: AgentBridgeNativePreparedTransfer,
        frontier: AgentBridgeTransferFrontier): AgentBridgeResumeRequest {
        val plan = request.plan as AgentBridgeGeneratedPlan
        return AgentBridgeResumeRequest(AgentBridgeValidation.bindingFor(request.plan), frontier.committedPartitionCount.toInt(),
            plan.intent.destination, frontier.sha256, request.jobId, AgentBridgeCodec.sha256(transfer.export.manifestCanonical),
            plan.intent.peer, transfer.export.requestSha256, "healthmd.agent_resume_request", 1)
    }

    @Test fun `native Resume rejects final admission callback evidence damage`() = runBlocking {
        for (filename in listOf("manifest.json", "progress.json")) withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val transfer = planner.prepareTransferExport(request, manager, journalRenderer(resolution))
            val frontier = planner.withRetainedCaptureContext(request) { context -> context.begin(); context.preserveTransferFrontier() }
            val resume = resumeRequest(request, transfer, frontier)
            val path = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(transfer.export.requestSha256).resolve(filename)
            var reads = 0; var admissionReads = 0; var target = 0
            fun reconnect(): AgentBridgeNativePlanningSession {
                val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
                return ownedPlanner(f, lifecycle, mockk<DirectSecureChannel>(relaxed = true), beforeNativeRead = {
                    reads++
                    if (reads == target) {
                        if (filename == "manifest.json") Files.delete(path) else Files.write(path, "corrupt".toByteArray())
                    }
                })
            }
            reconnect().withResumedCaptureContext(resume) { _, context -> admissionReads = reads; context.begin() }
            assertThat(admissionReads).isGreaterThan(0)
            reads = 0; target = admissionReads
            coEvery { client.aggregate(any()) } throws IllegalStateException("Resume cannot query SDK")
            var admitted = false
            try {
                reconnect().withResumedCaptureContext(resume) { _, context -> admitted = true; context.begin() }
                throw AssertionError("Expected final admission rejection")
            } catch (_: AgentBridgeException) { }
            assertThat(admitted).isFalse()
            assertThat(reads).isAtLeast(target)
            if (filename == "manifest.json") assertThat(Files.exists(path)).isFalse()
            else assertThat(Files.readAllBytes(path)).isEqualTo("corrupt".toByteArray())
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }

    @Test fun `native Resume reopens original job on fresh owner without SDK or rewrite`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val transfer = planner.prepareTransferExport(request, manager, journalRenderer(resolution))
            val frontier = planner.withRetainedCaptureContext(request) { context ->
                context.begin(); context.preserveTransferFrontier(); context.recordAcknowledgedTransferPartition(0)
            }
            val issuer = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME)
            val directory = issuer.resolve("captures").resolve(transfer.export.requestSha256)
            val progress = Files.readAllBytes(directory.resolve("progress.json"))
            val acceptedBeforeReconnect = f.store.access { it!!.state.acceptedJobs }
            val reconnect = transferReconnect(f, TransferCapabilities())
            assertThat(f.store.access { it!!.state.acceptedJobs }).isEqualTo(acceptedBeforeReconnect)
            val stateBytes = Files.readAllBytes(issuer.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))
            coEvery { client.aggregate(any()) } throws IllegalStateException("Resume cannot query SDK")
            reconnect.withResumedCaptureContext(resumeRequest(request, transfer, frontier)) { recovered, context ->
                assertThat(AgentBridgeCodec.encode(recovered)).isEqualTo(AgentBridgeCodec.encode(request))
                context.begin()
                assertThat(context.preserveTransferFrontier().sha256).isEqualTo(frontier.sha256)
                assertThat(context.preserveManifest()).isEqualTo(transfer.export.manifestCanonical)
                assertThat(context.preserveTransferPlan()).isEqualTo(transfer.checkpointCanonical)
            }
            assertThat(Files.readAllBytes(directory.resolve("progress.json"))).isEqualTo(progress)
            assertThat(Files.readAllBytes(issuer.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))).isEqualTo(stateBytes)
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }

    @Test fun `native Resume rejects mismatched and missing original evidence without repair`() = runBlocking {
        for (mode in listOf("Job", "Peer", "Destination", "Binding", "Request", "Manifest", "Count", "Frontier", "Uninitialized", "MissingManifest")) {
            withNativeExportPreparation { f, planner, request, client, manager ->
                val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
                coEvery { client.aggregate(any()) } returns values
                val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
                val transfer = planner.prepareTransferExport(request, manager, journalRenderer(resolution))
                val frontier = if (mode == "Uninitialized") AgentBridgeTransferFrontier.start(request.jobId, transfer.export.requestSha256,
                    AgentBridgeCodec.sha256(transfer.export.manifestCanonical), transfer.session.sessionId)
                    else planner.withRetainedCaptureContext(request) { context -> context.begin(); context.preserveTransferFrontier() }
                val original = resumeRequest(request, transfer, frontier)
                val resume = when (mode) {
                    "Job" -> original.copy(jobId = java.util.UUID.randomUUID().toString())
                    "Peer" -> {
                        val changed = original.peer.copy(sourceInstallationId = java.util.UUID.randomUUID().toString())
                        original.copy(peer = changed, binding = original.binding.copy(peer = changed))
                    }
                    "Destination" -> {
                        val changed = original.destination.copy(revision = 200)
                        original.copy(destination = changed, binding = original.binding.copy(destination = changed))
                    }
                    "Binding" -> original.copy(binding = original.binding.copy(settingsSha256 = "0".repeat(64)))
                    "Request" -> original.copy(requestSha256 = "0".repeat(64))
                    "Manifest" -> original.copy(manifestSha256 = "0".repeat(64))
                    "Count" -> original.copy(committedPartitionCount = 1)
                    "Frontier" -> original.copy(frontierSha256 = "0".repeat(64))
                    else -> original
                }
                val issuer = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME)
                val directory = issuer.resolve("captures").resolve(transfer.export.requestSha256)
                if (mode == "MissingManifest") Files.delete(directory.resolve("manifest.json"))
                val progress = Files.readAllBytes(directory.resolve("progress.json"))
                val acceptedBeforeReconnect = f.store.access { it!!.state.acceptedJobs }
                val reconnect = transferReconnect(f, TransferCapabilities())
                assertThat(f.store.access { it!!.state.acceptedJobs }).isEqualTo(acceptedBeforeReconnect)
                val stateBytes = Files.readAllBytes(issuer.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))
                coEvery { client.aggregate(any()) } throws IllegalStateException("Rejected Resume cannot query SDK")
                try {
                    reconnect.transmitResumedTransfer(resume) { _, _ -> throw AssertionError("Invalid Resume reached native callback") }
                    throw AssertionError("Expected rejected Resume: $mode")
                } catch (_: AgentBridgeException) { }
                assertThat(Files.readAllBytes(directory.resolve("progress.json"))).isEqualTo(progress)
                assertThat(Files.readAllBytes(issuer.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))).isEqualTo(stateBytes)
                if (mode == "MissingManifest") assertThat(Files.exists(directory.resolve("manifest.json"))).isFalse()
                coVerify(exactly = 2) { client.aggregate(any()) }
            }
        }
    }

    @Test fun `native Resume ACK advances exact pending prefix and replays without rewrite`() = runBlocking { checkNativeResumeAcknowledgement("valid") }
    @Test fun `native Resume ACK rejects mismatch and missing evidence without advancement`() = runBlocking {
        for (mode in listOf("manifest", "frontier", "count", "session", "unprepared", "corrupt", "uninitialized", "rejected")) checkNativeResumeAcknowledgement(mode)
    }
    @Test fun `native Resume ACK rejects manifest deletion before publication without advancement`() = runBlocking { checkNativeResumeAcknowledgement("publication") }

    @Test fun `native standalone ACK rejects manifest deletion before publication without advancement`() = runBlocking { checkNativeResumeAcknowledgement("standalone_publication") }

    private suspend fun checkNativeResumeAcknowledgement(mode: String) {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val transfer = planner.prepareTransferExport(request, manager, journalRenderer(resolution))
            val partition = transfer.partitions.first()
            val seed = AgentBridgeTransferFrontier.start(request.jobId, transfer.export.requestSha256,
                AgentBridgeCodec.sha256(transfer.export.manifestCanonical), transfer.session.sessionId)
            val expected = seed.appending(AgentBridgeTransferFrontierPartition(0, partition.transferId,
                transfer.export.baseFiles.first().manifest.artifactId, 0, partition.byteCount, partition.chunkCount.toLong(), partition.sha256))
            planner.withRetainedCaptureContext(request) { context ->
                context.begin()
                if (mode != "uninitialized") context.preserveTransferFrontier()
                if (mode !in listOf("unprepared", "uninitialized")) context.preserveAwaitingPartitionAcknowledgement(0)
            }
            val original = resumeRequest(request, transfer, expected)
            val resume = when(mode) {
                "manifest" -> original.copy(manifestSha256 = "0".repeat(64))
                "frontier" -> original.copy(frontierSha256 = seed.sha256)
                "count" -> original.copy(committedPartitionCount = 0)
                else -> original
            }
            val ack = TransferPartitionAcknowledgement(if(mode == "session") java.util.UUID.randomUUID().toString() else transfer.session.sessionId,
                transfer.session.jobId, partition.index, partition.transferId, partition.sha256, mode != "rejected")
            val issuer = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME)
            val directory = issuer.resolve("captures").resolve(transfer.export.requestSha256)
            val pendingPath = directory.resolve("partition-awaiting-ack.json")
            if (mode == "corrupt") Files.write(pendingPath, "corrupt".toByteArray())
            val pending = if (Files.exists(pendingPath)) Files.readAllBytes(pendingPath) else null
            val before = Files.readAllBytes(directory.resolve("progress.json"))
            val accepted = f.store.access { it!!.state.acceptedJobs }
            var damaged = false
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val reconnect = ownedPlanner(f, lifecycle, mockk<DirectSecureChannel>(relaxed = true), beforeNativeRead = {
                if (mode in listOf("publication", "standalone_publication") && !damaged) {
                    val staged = Files.newDirectoryStream(directory).use { stream -> stream.filter { it.fileName.toString().startsWith("pending-") }.toList() }
                    for (path in staged) {
                        val count = runCatching {
                            val signed = Json.parseToJsonElement(Files.readAllBytes(path).decodeToString()).jsonObject
                            val bytes = java.util.Base64.getDecoder().decode(signed.getValue("record").jsonObject.getValue("payload").jsonPrimitive.content)
                            Json.parseToJsonElement(bytes.decodeToString()).jsonObject["committedPartitionCount"]?.jsonPrimitive?.long
                        }.getOrNull()
                        if (count == 1L) { damaged = true; Files.delete(directory.resolve("manifest.json")); break }
                    }
                }
            })
            val issuerBytes = Files.readAllBytes(issuer.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))
            coEvery { client.aggregate(any()) } throws IllegalStateException("ACK Resume must not query SDK")
            var admitted = false
            try {
                if (mode == "standalone_publication") {
                    reconnect.withRetainedCaptureContext(request) { context ->
                        context.begin(); context.reconcilePartitionAcknowledgement(ack); admitted = true
                    }
                } else {
                    reconnect.withResumedCaptureContext(resume, ack) { recovered, context ->
                        admitted = true; assertThat(AgentBridgeCodec.encode(recovered)).isEqualTo(AgentBridgeCodec.encode(request))
                        context.begin(); assertThat(context.preserveTransferFrontier().sha256).isEqualTo(expected.sha256)
                    }
                }
                if (mode != "valid") throw AssertionError("Invalid ACK/Resume admitted: $mode")
            } catch (error: AgentBridgeException) { if (mode == "valid") throw error }
            if (mode == "valid") {
                assertThat(admitted).isTrue()
                val committed = Files.readAllBytes(directory.resolve("progress.json")); assertThat(committed).isNotEqualTo(before)
                reconnect.withResumedCaptureContext(resume, ack) { _, context -> context.begin(); assertThat(context.preserveTransferFrontier().sha256).isEqualTo(expected.sha256) }
                assertThat(Files.readAllBytes(directory.resolve("progress.json"))).isEqualTo(committed)
            } else {
                assertThat(admitted).isFalse(); assertThat(Files.readAllBytes(directory.resolve("progress.json"))).isEqualTo(before)
            }
            if (mode in listOf("publication", "standalone_publication")) { assertThat(damaged).isTrue(); assertThat(Files.exists(directory.resolve("manifest.json"))).isFalse() }
            assertThat(if (Files.exists(pendingPath)) Files.readAllBytes(pendingPath) else null).isEqualTo(pending)
            assertThat(Files.readAllBytes(directory.resolve("transfer.json"))).isEqualTo(transfer.checkpointCanonical)
            assertThat(f.store.access { it!!.state.acceptedJobs }).isEqualTo(accepted)
            assertThat(Files.readAllBytes(issuer.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))).isEqualTo(issuerBytes)
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }

    @Test fun `native pending ACK reopens exact lost acknowledgement without SDK or duplicate publication`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val transfer = planner.prepareTransferExport(request, manager, journalRenderer(resolution))
            val partition = transfer.partitions.first()
            val ack = TransferPartitionAcknowledgement(transfer.session.sessionId, transfer.session.jobId, partition.index, partition.transferId, partition.sha256, true)
            val directory = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(transfer.export.requestSha256)
            planner.withRetainedCaptureContext(request) { context ->
                context.begin(); context.preserveTransferFrontier(); context.preserveAwaitingPartitionAcknowledgement(0)
                assertThat(context.preserveTransferFrontier().committedPartitionCount).isEqualTo(0L)
            }
            val pending = Files.readAllBytes(directory.resolve("partition-awaiting-ack.json"))
            coEvery { client.aggregate(any()) } throws IllegalStateException("No SDK on lost ACK recovery")
            planner.withRetainedCaptureContext(request) { context ->
                context.begin(); assertThat(context.reconcilePartitionAcknowledgement(ack).committedPartitionCount).isEqualTo(1L)
            }
            val progress = Files.readAllBytes(directory.resolve("progress.json"))
            planner.withRetainedCaptureContext(request) { context ->
                context.begin(); assertThat(context.reconcilePartitionAcknowledgement(ack).committedPartitionCount).isEqualTo(1L)
            }
            assertThat(Files.readAllBytes(directory.resolve("progress.json"))).isEqualTo(progress)
            assertThat(Files.readAllBytes(directory.resolve("partition-awaiting-ack.json"))).isEqualTo(pending)
            assertThat(Files.readAllBytes(directory.resolve("transfer.json"))).isEqualTo(transfer.checkpointCanonical)
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }
    @Test fun `native pending ACK rejects unproven changed and older acknowledgement without repair`() = runBlocking {
        for (mode in listOf("unprepared", "deleted", "corrupt", "session", "job", "transfer", "hash", "ahead", "rejected", "older")) {
            withNativeExportPreparation { f, planner, request, client, manager ->
                val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
                coEvery { client.aggregate(any()) } returns values
                val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
                val transfer = planner.prepareTransferExport(request, manager, journalRenderer(resolution))
                fun ack(index: Int): TransferPartitionAcknowledgement {
                    val partition = transfer.partitions[index]
                    return TransferPartitionAcknowledgement(if (mode == "session") java.util.UUID.randomUUID().toString() else transfer.session.sessionId,
                        if (mode == "job") java.util.UUID.randomUUID().toString() else transfer.session.jobId,
                        if (mode == "ahead") 1 else partition.index, if (mode == "transfer") java.util.UUID.randomUUID().toString() else partition.transferId,
                        if (mode == "hash") "0".repeat(64) else partition.sha256, mode != "rejected")
                }
                val directory = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(transfer.export.requestSha256)
                val pending = directory.resolve("partition-awaiting-ack.json")
                planner.withRetainedCaptureContext(request) { context ->
                    context.begin(); context.preserveTransferFrontier()
                    if (mode != "unprepared") context.preserveAwaitingPartitionAcknowledgement(0)
                    if (mode == "older") { context.reconcilePartitionAcknowledgement(ack(0)); context.preserveAwaitingPartitionAcknowledgement(1); context.reconcilePartitionAcknowledgement(ack(1)) }
                }
                if (mode == "deleted") Files.delete(pending)
                if (mode == "corrupt") Files.write(pending, "corrupt".toByteArray())
                val original = if (Files.exists(pending)) Files.readAllBytes(pending) else null
                val progress = Files.readAllBytes(directory.resolve("progress.json"))
                coEvery { client.aggregate(any()) } throws IllegalStateException("No SDK for rejected ACK")
                try {
                    planner.withRetainedCaptureContext(request) { context -> context.begin(); context.reconcilePartitionAcknowledgement(ack(0)) }
                    throw AssertionError("Invalid pending ACK returned: $mode")
                } catch (_: AgentBridgeException) { }
                assertThat(if (Files.exists(pending)) Files.readAllBytes(pending) else null).isEqualTo(original)
                assertThat(Files.readAllBytes(directory.resolve("progress.json"))).isEqualTo(progress)
                coVerify(exactly = 2) { client.aggregate(any()) }
            }
        }
    }

    @Test fun `native transfer frontier migrates v5 and recovers exact prefix without SDK or rewrite`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val transfer = planner.prepareTransferExport(request, manager, journalRenderer(resolution))
            val directory = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(transfer.export.requestSha256)
            val path = directory.resolve("progress.json"); val old = Files.readAllBytes(path)
            var prefix: AgentBridgeTransferFrontier? = null
            planner.withRetainedCaptureContext(request) { context ->
                context.begin(); assertThat(context.preserveTransferFrontier().committedPartitionCount).isEqualTo(0L)
                prefix = context.recordAcknowledgedTransferPartition(0)
                assertThat(prefix!!.committedPartitionCount).isEqualTo(1L)
            }
            val retained = Files.readAllBytes(path); assertThat(retained).isNotEqualTo(old)
            coEvery { client.aggregate(any()) } throws IllegalStateException("No SDK on frontier recovery")
            planner.withRetainedCaptureContext(request) { context ->
                context.begin()
                assertThat(context.preserveTransferFrontier().sha256).isEqualTo(prefix!!.sha256)
                assertThat(context.recordAcknowledgedTransferPartition(0).sha256).isEqualTo(prefix!!.sha256)
            }
            assertThat(Files.readAllBytes(path)).isEqualTo(retained)
            assertThat(Files.readAllBytes(directory.resolve("transfer.json"))).isEqualTo(transfer.checkpointCanonical)
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }
    @Test fun `native transfer frontier rejects skipped index without advancing`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val transfer = planner.prepareTransferExport(request, manager, journalRenderer(resolution))
            val path = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(transfer.export.requestSha256).resolve("progress.json")
            var before = byteArrayOf()
            try {
                planner.withRetainedCaptureContext(request) { context ->
                    context.begin(); context.preserveTransferFrontier(); before = Files.readAllBytes(path)
                    context.recordAcknowledgedTransferPartition(1); throw AssertionError("Skipped ack cannot advance")
                }
            } catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.BINDING_CHANGED) }
            assertThat(Files.readAllBytes(path)).isEqualTo(before)
        }
    }
    @Test fun `native transfer frontier rejects signed inconsistent or partial progress without repair`() = runBlocking {
        for (mode in listOf("digest", "count", "partial", "old-with-frontier")) withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val transfer = planner.prepareTransferExport(request, manager, journalRenderer(resolution))
            val path = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(transfer.export.requestSha256).resolve("progress.json")
            planner.withRetainedCaptureContext(request) { context -> context.begin(); context.preserveTransferFrontier() }
            val signed = Json.parseToJsonElement(Files.readAllBytes(path).decodeToString()).jsonObject.toMutableMap()
            val record = signed.getValue("record").jsonObject.toMutableMap()
            val payload = Json.parseToJsonElement(String(java.util.Base64.getDecoder().decode(record.getValue("payload").jsonPrimitive.content))).jsonObject.toMutableMap()
            when (mode) {
                "digest" -> payload["frontierSHA256"] = JsonPrimitive("f".repeat(64))
                "count" -> payload["committedPartitionCount"] = JsonPrimitive(3)
                "partial" -> payload.remove("frontierSHA256")
                "old-with-frontier" -> payload["version"] = JsonPrimitive(5)
            }
            record["payload"] = JsonPrimitive(java.util.Base64.getEncoder().encodeToString(AgentBridgeCodec.canonicalize(JsonObject(payload).toString().toByteArray())))
            val body = AgentBridgeCodec.canonicalize(JsonObject(record).toString().toByteArray())
            val signer = javax.crypto.Mac.getInstance("HmacSHA256"); signer.init(requireNotNull(f.keys.key))
            signer.update("HealthMd.AgentBridge.AndroidCaptureSpool.v1\u0000".toByteArray())
            signed["record"] = JsonObject(record)
            signed["mac"] = JsonPrimitive(signer.doFinal(body).joinToString("") { "%02x".format(it) })
            val damaged = AgentBridgeCodec.canonicalize(JsonObject(signed).toString().toByteArray())
            Files.write(path, damaged, java.nio.file.StandardOpenOption.TRUNCATE_EXISTING)
            val forbidden = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { error("No render") }, pinLoader = { error("No core") })
            try { planner.prepareRetainedTransferExport(request, manager, forbidden); throw AssertionError("Invalid signed prefix cannot repair") }
            catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED) }
            assertThat(Files.readAllBytes(path)).isEqualTo(damaged)
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }

    @Test fun `native transfer sender handles needed then already committed with historical pending marker`() = runBlocking { checkNativeTransferSender("mixed") }
    @Test fun `native transfer sender carries original bytes without completion claim`() = runBlocking { checkNativeTransferSender("needed") }
    @Test fun `native transfer sender rejects competing readers without abandoning owner`() = runBlocking { checkNativeTransferSender("contended") }
    @Test fun `native transfer sender skips already committed bytes`() = runBlocking { checkNativeTransferSender("already") }
    @Test fun `native transfer sender rejects wrong acknowledgements and abandons owner`() = runBlocking {
        for (mode in listOf("bad-disposition", "bad-chunk", "bad-partition", "bad-final")) checkNativeTransferSender(mode)
    }
    @Test fun `native transfer sender checks owner after receive before further writes`() = runBlocking { checkNativeTransferSender("revoke") }

    @Test fun `native transfer sender consumes keepalives before every ACK and host commit`() = runBlocking { checkNativeTransferSender("complete-keepalive") }
    @Test fun `native transfer keepalive receive cannot bypass owner revocation`() = runBlocking { checkNativeTransferSender("keepalive-revoke") }
    @Test fun `native transfer rejects nonempty keepalive payloads`() = runBlocking { for (type in listOf("ping", "pong")) checkNativeTransferSender("bad-keepalive-$type") }
    @Test fun `native transfer pong write cannot bypass owner revocation`() = runBlocking { checkNativeTransferSender("keepalive-write-revoke") }

    @Test fun `native transfer confirms source stop at each ACK and host commit without another reader`() = runBlocking {
        for (stage in listOf("disposition", "chunk", "partition", "final", "host")) checkNativeTransferSender("stop-$stage")
    }
    @Test fun `native transfer source stop survives unavailable read configuration`() = runBlocking { checkNativeTransferSender("stop-read-revoked") }
    @Test fun `native resumed transfer confirms exact retained source stop`() = runBlocking { checkNativeTransferSender("stop-resume") }
    @Test fun `native transfer source stop preserves existing completion`() = runBlocking { checkNativeTransferSender("stop-complete") }
    @Test fun `native transfer source stop rejects a foreign job and abandons owner`() = runBlocking { checkNativeTransferSender("stop-foreign") }
    @Test fun `native transfer ordinary cancelled errors cannot impersonate a confirmed source stop`() = runBlocking {
        for (taskError in listOf(false, true)) withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            planner.prepareTransferExport(request, manager, journalRenderer(resolution))
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            val closed = java.util.concurrent.CountDownLatch(1)
            every { channel.close() } answers { closed.countDown() }
            every { channel.receiveAllowingAgentBridge(any(), any()) } answers {
                secondArg<() -> Unit>().invoke()
                check(closed.await(10, TimeUnit.SECONDS))
                throw IOException("Synthetic idle channel closed")
            }
            val reconnect = ownedPlanner(f, lifecycle, channel)
            try {
                reconnect.transmitTransfer(request, true) { context ->
                    context.begin()
                    if (taskError) throw kotlinx.coroutines.CancellationException("synthetic caller error")
                    throw AgentBridgeException(AgentBridgeErrorCode.CANCELLED)
                }
                throw AssertionError("Ordinary cancellation returned success")
            } catch (failure: Throwable) {
                if (taskError) assertThat(failure).isInstanceOf(kotlinx.coroutines.CancellationException::class.java)
                else assertThat((failure as AgentBridgeException).code).isEqualTo(AgentBridgeErrorCode.CANCELLED)
            }
            verify(atLeast = 1) { channel.close() }
            verify(exactly = 0) { channel.sendAgentBridge(any(), any(), any()) }
            assertThat(currentCoroutineContext().job.isActive).isTrue()
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }
    @Test fun `native transfer source stop write failure abandons owner without confirmed proof`() = runBlocking { checkNativeTransferSender("stop-write-failure") }

    @Test fun `native transfer sender resumes exact prefix without replaying bytes`() = runBlocking { checkNativeTransferSender("resume") }
    @Test fun `native transfer sender rejects host rewind of recorded prefix`() = runBlocking { checkNativeTransferSender("rewind") }
    @Test fun `native stop during SDK read discards late value and journals invalidated owner`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val plan = request.plan as AgentBridgeGeneratedPlan
            val cancel = AgentBridgeCancelRequest(request.approval.approvalId, plan.authorityReferences.native.authorityId,
                request.jobId, plan.intent.peer, AgentBridgeCodec.sha256(AgentBridgeCodec.encode(request)), "healthmd.agent_cancel_request", 1)
            val value = mockk<AggregationResult>(); every { value[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } coAnswers {
                f.service.requestCancellation(f.peerContext, cancel)
                value
            }
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            try { planner.prepareExport(request, manager, journalRenderer(resolution)); throw AssertionError("Late SDK value must not escape") }
            catch (failure: AgentBridgeException) { assertThat(failure.code).isEqualTo(AgentBridgeErrorCode.PERMISSION_REQUIRED) }
            val job = f.store.access { it!!.state.acceptedJobs!!.single() }
            val directory = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(job.requestSha256)
            val names = Files.list(directory).use { paths -> paths.map { it.fileName.toString() }.toList() }
            assertThat(names).contains("capture-stop.json"); assertThat(names.none { it.startsWith("day-") }).isTrue()
            coVerify(exactly = 1) { client.aggregate(any()) }
            val receipt = f.restart().finalizeCapturedCancellation(f.peerContext, cancel)
            assertThat(receipt.status).isEqualTo(AgentBridgeExecutionReceiptStatus.CANCELLED)
            assertThat(receipt.sourceAcknowledged).isTrue(); assertThat(receipt.artifactCount).isEqualTo(0)
            coVerify(exactly = 1) { client.aggregate(any()) }
        }
    }

    @Test fun `native captured cancellation refuses manifest without retained frontier`() = runBlocking { checkNativeTransferSender("cancel-no-frontier") }

    @Test fun `native transfer sender publication failure prevents next partition and finalize`() = runBlocking { checkNativeTransferSender("publication") }

    @Test fun `native completion persists exact host receipts and source confirmation`() = runBlocking { checkNativeTransferSender("complete") }
    @Test fun `native Resume carries retained prefix and confirms original completion without capture`() = runBlocking { checkNativeTransferSender("complete-resume") }
    @Test fun `native completion rejects changed input with valid commit key`() = runBlocking { checkNativeTransferSender("complete-bad-input") }
    @Test fun `native completion rejects reordered receipts`() = runBlocking { checkNativeTransferSender("complete-order") }
    @Test fun `native completion rejects missing receipt`() = runBlocking { checkNativeTransferSender("complete-missing") }
    @Test fun `native completion rejects receipt corruption at final send`() = runBlocking { checkNativeTransferSender("complete-corrupt") }
    @Test fun `native completion rejects revocation at final send`() = runBlocking { checkNativeTransferSender("complete-revoke") }

    private fun nativeHostCommit(artifact: AgentBridgeArtifact, request: AgentBridgeExecuteRequest, manifest: ByteArray, badInput: Boolean): AgentBridgeCommitReceipt {
        val plan = request.plan as AgentBridgeGeneratedPlan
        val input = if (badInput) "1".repeat(64) else artifact.sha256
        val provisional = AgentBridgeCommitReceipt(afterSha256=input, artifactId=artifact.artifactId, beforeSha256="0".repeat(64), commitKey="0".repeat(64),
            destination=plan.intent.destination,inputSha256=input,jobId=request.jobId,manifestSha256=AgentBridgeCodec.sha256(manifest),peer=plan.intent.peer,
            relativePath=artifact.relativePath,requestSha256=AgentBridgeCodec.sha256(AgentBridgeCodec.encode(request)),schema="healthmd.agent_commit_receipt",schemaVersion=1,
            status=AgentBridgeCommitReceiptStatus.COMMITTED,writeMode=artifact.writeMode)
        val tree=Json.encodeToJsonElement(AgentBridgeCommitReceipt.serializer(),provisional).jsonObject
        val fields=setOf("job_id","artifact_id","destination","request_sha256","manifest_sha256","relative_path","write_mode","input_sha256","before_sha256","after_sha256")
        return provisional.copy(commitKey=AgentBridgeCodec.sha256(AgentBridgeCodec.canonicalize(JsonObject(tree.filterKeys { it in fields }).toString().toByteArray())))
    }

    private suspend fun checkNativeTransferSender(mode: String) {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val original = planner.prepareTransferExport(request, manager, journalRenderer(resolution))
            if (mode == "cancel-no-frontier") {
                val job = f.store.access { it!!.state.acceptedJobs!!.single() }
                val root = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME)
                val directory = root.resolve("captures").resolve(job.requestSha256)
                val plan = request.plan as AgentBridgeGeneratedPlan
                val cancel = AgentBridgeCancelRequest(request.approval.approvalId, plan.authorityReferences.native.authorityId,
                    request.jobId, plan.intent.peer, job.requestSha256, "healthmd.agent_cancel_request", 1)
                assertThat(Files.exists(directory.resolve("manifest.json"))).isTrue()
                val state = Json.parseToJsonElement(Files.readAllBytes(directory.resolve("progress.json")).decodeToString()).jsonObject.getValue("record").jsonObject
                val progress = Json.parseToJsonElement(String(java.util.Base64.getDecoder().decode(state.getValue("payload").jsonPrimitive.content))).jsonObject
                assertThat(progress.getValue("version").jsonPrimitive.int).isEqualTo(5)
                f.service.requestCancellation(f.peerContext, cancel)
                val ledger = Files.readAllBytes(root.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))
                f.expect(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED) { f.restart().finalizeCapturedCancellation(f.peerContext, cancel) }
                assertThat(Files.readAllBytes(root.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))).isEqualTo(ledger)
                coVerify(exactly = 2) { client.aggregate(any()) }
                return@withNativeExportPreparation
            }
            val stopTransfer = mode.startsWith("stop-")
            val keepalive = mode.contains("keepalive")
            val completion=mode.startsWith("complete") || mode == "stop-host"
            val resumedPrefix = mode == "resume" || mode == "complete-resume" || mode == "stop-resume"
            var resumeEnvelope: AgentBridgeResumeRequest? = null
            val manifest=AgentBridgeCodec.decode(original.export.manifestCanonical) as AgentBridgeArtifactManifest
            val hostReceipts=manifest.artifacts.map { nativeHostCommit(it,request,original.export.manifestCanonical,mode=="complete-bad-input") }.toMutableList()
            if(mode=="complete-order")hostReceipts.reverse()
            if(mode=="complete-missing")hostReceipts.removeAt(hostReceipts.lastIndex)
            var completionDirectory:java.nio.file.Path?=null
            val acceptedBeforeResume = f.store.access { it!!.state.acceptedJobs }

            if (resumedPrefix || mode == "rewind") planner.withRetainedCaptureContext(request) { context ->
                context.begin(); context.preserveTransferFrontier(); context.recordAcknowledgedTransferPartition(0)
                if (mode == "complete-resume" || mode == "stop-resume") resumeEnvelope = resumeRequest(request, original, context.preserveTransferFrontier())
            }
            var priorCompletion: AgentBridgeExecutionReceipt? = null
            if (mode == "stop-complete") planner.withRetainedCaptureContext(request) { context ->
                context.begin(); context.preserveTransferFrontier()
                original.partitions.forEach { context.recordAcknowledgedTransferPartition(it.index) }
                hostReceipts.forEach { context.recordHostCommit(it) }
                priorCompletion = context.preserveCompletion()
            }
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            val agent = mutableListOf<AgentBridgeMessage>(); val base = mutableListOf<ReceivedEnvelope>()
            val chunks = mutableListOf<Pair<String, ByteArray>>()
            val responses = java.util.ArrayDeque<ReceivedAgentBridgePayload>()
            // A host reply becomes available only after its first outbound challenge.
            // The native reader can already be waiting while preparation is in flight.
            val responseReady = java.util.concurrent.CountDownLatch(1)
            every { channel.close() } answers { responseReady.countDown() }
            fun keepalives() {
                if (keepalive) for (type in listOf("ping", "pong")) responses.add(
                    ReceivedAgentBridgePayload.Base(V2Codec.decode(V2Codec.encode(type, JsonObject.serializer(), buildJsonObject { if (mode == "bad-keepalive-$type") put("unexpected", 1) }))))
            }
            fun <T> response(type: String, serializer: kotlinx.serialization.SerializationStrategy<T>, payload: T) {
                keepalives()
                responses.add(ReceivedAgentBridgePayload.Base(V2Codec.decode(V2Codec.encode(type, serializer, payload))))
            }
            original.partitions.forEach { partition ->
                val already = mode == "already" || (resumedPrefix && partition.index == 0L) || (mode == "mixed" && partition.index > 0L)
                response("transfer_disposition", TransferDisposition.serializer(), TransferDisposition(original.session.sessionId,
                    if (mode == "bad-disposition") java.util.UUID.randomUUID().toString() else original.session.jobId,
                    partition.index, partition.sha256, if (already) TransferDispositionKind.ALREADY_COMMITTED else TransferDispositionKind.NEEDED))
                if (!already) {
                    response("transfer_chunk_acknowledgement", TransferChunkAcknowledgement.serializer(), TransferChunkAcknowledgement(
                        partition.transferId, if (mode == "bad-chunk") 2 else 1, true, partition.sha256))
                    response("transfer_partition_acknowledgement", TransferPartitionAcknowledgement.serializer(), TransferPartitionAcknowledgement(
                        original.session.sessionId, if (mode == "bad-partition") java.util.UUID.randomUUID().toString() else original.session.jobId,
                        partition.index, partition.transferId, partition.sha256, true))
                }
            }
            response("transfer_final_acknowledgement", TransferFinalAcknowledgement.serializer(), TransferFinalAcknowledgement(
                original.session.sessionId, original.session.jobId, true, original.partitions.size.toLong(),
                original.export.totalByteCount.toLong() + if (mode == "bad-final") 1 else 0, original.partitions.last().sha256))
            if(completion)hostReceipts.forEach { keepalives(); responses += ReceivedAgentBridgePayload.Agent(AgentBridgeMessage("commit_receipt",it)) }
            val expectedPongs = if (keepalive) responses.count { (it as? ReceivedAgentBridgePayload.Base)?.envelope?.type == "ping" } else 0
            val plan = request.plan as AgentBridgeGeneratedPlan
            val stopRequest = AgentBridgeCancelRequest(request.approval.approvalId, plan.authorityReferences.native.authorityId,
                if (mode == "stop-foreign") java.util.UUID.randomUUID().toString() else request.jobId, plan.intent.peer,
                original.export.requestSha256, "healthmd.agent_cancel_request", 1)
            if (stopTransfer) {
                val target = when (mode) {
                    "stop-chunk" -> "transfer_chunk_acknowledgement"
                    "stop-partition" -> "transfer_partition_acknowledgement"
                    "stop-final" -> "transfer_final_acknowledgement"
                    "stop-host" -> "commit_receipt"
                    else -> "transfer_disposition"
                }
                val pending = responses.toMutableList()
                val index = pending.indexOfFirst { when (it) {
                    is ReceivedAgentBridgePayload.Base -> it.envelope.type == target
                    is ReceivedAgentBridgePayload.Agent -> it.message.type == target
                    else -> false
                } }
                check(index >= 0)
                pending.add(index, ReceivedAgentBridgePayload.Agent(AgentBridgeMessage("cancel_request", stopRequest)))
                responses.clear(); responses.addAll(pending)
            }
            var stopReceived = false
            var finalNativeRead: (() -> Unit)? = null
            every { channel.sendAgentBridge(any(), any(), any()) } answers {
                thirdArg<() -> Unit>()()
                if (mode == "stop-write-failure" && firstArg<AgentBridgeMessage>().type == "execution_receipt") throw java.io.IOException("synthetic stop write failure")
                agent += firstArg<AgentBridgeMessage>(); thirdArg<() -> Unit>()()
            }
            every { channel.sendV2ForAgentBridge(any(), any<kotlinx.serialization.SerializationStrategy<Any>>(), any<Any>(), any(), any()) } answers {
                if (mode == "keepalive-write-revoke" && firstArg<String>() == "pong") lifecycle.stop()
                if(firstArg<String>()=="completion_confirmed") {
                    if(mode=="complete-revoke")lifecycle.stop()
                    if(mode=="complete-corrupt")Files.write(requireNotNull(completionDirectory).resolve("host-commit-${manifest.artifacts.first().artifactId}.json"),"corrupt".toByteArray())
                }

                lastArg<() -> Unit>()()
                base += V2Codec.decode(V2Codec.encode(firstArg(), secondArg<kotlinx.serialization.SerializationStrategy<Any>>(), thirdArg()))
                lastArg<() -> Unit>()()
                if (firstArg<String>() == "transfer_open") responseReady.countDown()
            }
            every { channel.sendTransferChunkForAgentBridge(any(), any(), any(), any(), any()) } answers {
                lastArg<() -> Unit>()(); assertThat(secondArg<Int>()).isEqualTo(1)
                // Exercise the deployed frame encoder as well as the native owner callback.
                // A permissive mock must not accept invalid sequence/size/identifier values.
                val frame = BinaryTransferFrame.encode(firstArg(), secondArg(), thirdArg())
                assertThat(frame.size).isEqualTo(66 + thirdArg<ByteArray>().size)
                chunks += firstArg<String>() to thirdArg<ByteArray>().copyOf(); lastArg<() -> Unit>()()
            }
            every { channel.receiveAllowingAgentBridge(any(), any()) } answers {
                // Socket reads wait for a peer response or close; preparation has no
                // ten-second deadline. The runner bounds the whole test command.
                responseReady.await()
                secondArg<() -> Unit>()()
                val result = responses.pollFirst() ?: throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
                if (mode == "revoke" || mode == "keepalive-revoke") lifecycle.stop()
                if ((result as? ReceivedAgentBridgePayload.Agent)?.message?.type == "cancel_request") stopReceived = true
                secondArg<() -> Unit>()(); result
            }
            val reconnect = ownedPlanner(f, lifecycle, channel, beforeNativeRead = {
                if (mode == "stop-read-revoked" && stopReceived) throw AssertionError("Source stop reentered unavailable read configuration")
                finalNativeRead?.invoke()
            })
            val job = f.store.access { it!!.state.acceptedJobs!!.single() }
            val directory = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(job.requestSha256)
            completionDirectory=directory
            coEvery { client.aggregate(any()) } throws IllegalStateException("No SDK on immutable carriage")
            val forbidden = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { error("No render") }, pinLoader = { error("No core load") })
            var publicationInterrupted = false
            if (mode == "publication") f.peerContext.onCheck = {
                val count = runCatching {
                    val signed = Json.parseToJsonElement(Files.readAllBytes(directory.resolve("progress.json")).decodeToString()).jsonObject
                    val payload = java.util.Base64.getDecoder().decode(signed.getValue("record").jsonObject.getValue("payload").jsonPrimitive.content)
                    Json.parseToJsonElement(payload.decodeToString()).jsonObject["committedPartitionCount"]?.jsonPrimitive?.long
                }.getOrNull()
                if (!publicationInterrupted && count == 1L) {
                    publicationInterrupted = true; throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
                }
            }
            if (stopTransfer) {
                var stopped = false
                var failure: Throwable? = null
                try {
                    if (mode == "stop-resume") reconnect.sendResumedExecutionExport(requireNotNull(resumeEnvelope), manager, renderer = forbidden)
                    else if (completion) reconnect.sendExecutionExport(request, manager, true, forbidden)
                    else reconnect.sendTransferExport(request, manager, true, forbidden)
                } catch (caught: Throwable) { failure = caught; stopped = (caught as? AgentBridgeException)?.code == AgentBridgeErrorCode.CANCELLED }
                assertThat(stopReceived).isTrue()
                val unsafe = mode == "stop-foreign" || mode == "stop-write-failure"
                if (unsafe) {
                    assertThat(failure).isNotNull(); verify(atLeast = 1) { channel.close() }
                    assertThat(agent.none { it.type == "execution_receipt" }).isTrue()
                    val writes = agent.size + base.size + chunks.size
                    try { reconnect.sendTransferExport(request, manager, true, forbidden); throw AssertionError("Abandoned owner revived") }
                    catch (_: AgentBridgeException) { assertThat(agent.size + base.size + chunks.size).isEqualTo(writes) }
                    if (mode == "stop-foreign") assertThat(f.store.access { it!!.state.cancellationIntents.orEmpty() }).isEmpty()
                } else {
                    if (mode == "stop-complete") { assertThat(failure).isNull(); assertThat(stopped).isFalse() }
                    else { assertThat(stopped).isTrue(); assertThat(currentCoroutineContext().job.isActive).isTrue() }
                    val receipt = agent.last().payload as AgentBridgeExecutionReceipt
                    assertThat(receipt.sourceAcknowledged).isTrue()
                    assertThat(receipt.requestSha256).isEqualTo(original.export.requestSha256)
                    assertThat(receipt.status).isEqualTo(if (priorCompletion != null) priorCompletion!!.status else AgentBridgeExecutionReceiptStatus.CANCELLED)
                    val expectedCount = if (mode == "stop-resume") 1 else if (mode in listOf("stop-complete", "stop-final", "stop-host")) original.partitions.size else 0
                    assertThat(receipt.committedPartitionCount).isEqualTo(expectedCount)
                    if (priorCompletion != null) assertThat(receipt).isEqualTo(priorCompletion)
                    verify(exactly = 0) { channel.close() }
                    val stateFile = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
                    val beforeReplay = Files.readAllBytes(stateFile)
                    val pendingReads = responses.size
                    reconnect.handleAndSend(AgentBridgeCodec.encodeEnvelope(AgentBridgeMessage("cancel_request", stopRequest), nativeNegotiation()), currentCoroutineContext().job)
                    assertThat(agent.last().payload).isEqualTo(receipt)
                    assertThat(Files.readAllBytes(stateFile)).isEqualTo(beforeReplay)
                    assertThat(responses.size).isEqualTo(pendingReads)
                }
                coVerify(exactly = 2) { client.aggregate(any()) }
                return@withNativeExportPreparation
            }
            val fails = (completion && mode !in setOf("complete", "complete-resume", "complete-keepalive")) || mode.startsWith("bad-") || mode in listOf("revoke", "rewind", "publication", "keepalive-revoke", "keepalive-write-revoke")
            try {
                if (mode == "contended") {
                    reconnect.transmitTransfer(request, true) { context ->
                        context.begin()
                        val caller = currentCoroutineContext().job
                        try { reconnect.receiveAndHandleNext(caller); throw AssertionError("Competing reader must reject") }
                        catch (failure: AgentBridgeException) { assertThat(failure.code).isEqualTo(AgentBridgeErrorCode.BUSY) }
                        try { reconnect.handleAndSend(ownedDiscoveryBytes(f), caller); throw AssertionError("Competing response must reject") }
                        catch (failure: AgentBridgeException) { assertThat(failure.code).isEqualTo(AgentBridgeErrorCode.BUSY) }
                        try { reconnect.withRetainedCaptureContext(request) { error("Competing capture must reject") }; throw AssertionError("Expected busy") }
                        catch (failure: AgentBridgeException) { assertThat(failure.code).isEqualTo(AgentBridgeErrorCode.BUSY) }
                        original
                    }
                } else if (mode == "complete-resume") reconnect.sendResumedExecutionExport(requireNotNull(resumeEnvelope), manager, renderer = forbidden)
                else if(completion)reconnect.sendExecutionExport(request,manager,true,forbidden)
                else reconnect.sendTransferExport(request, manager, true, forbidden)
                if (fails) throw AssertionError("Expected acknowledgement/owner rejection")
            } catch (failure: AgentBridgeException) {
                if (!fails) throw failure
                val count = base.size + chunks.size + agent.size
                try { reconnect.sendTransferExport(request, manager, true, forbidden); throw AssertionError("No owner revival") }
                catch (_: AgentBridgeException) { assertThat(base.size + chunks.size + agent.size).isEqualTo(count) }
                verify(atLeast = 1) { channel.close() }
            }
            f.peerContext.onCheck = null
            if (keepalive) {
                assertThat(base.count { it.type == "pong" }).isEqualTo(if (mode == "bad-keepalive-pong") 1 else if (fails) 0 else expectedPongs)
                if (!fails) { assertThat(responses).isEmpty(); verify(exactly = 0) { channel.close() } }
            }
            if (mode == "complete-resume") {
                assertThat(f.store.access { it!!.state.acceptedJobs }).isEqualTo(acceptedBeforeResume)
            }
            if (mode == "mixed") reconnect.withRetainedCaptureContext(request) { context ->
                context.begin(); assertThat(context.preserveTransferFrontier().committedPartitionCount).isEqualTo(original.partitions.size.toLong())
            }
            assertThat(agent.map { it.type }).containsExactlyElementsIn(if(completion && !fails)listOf("artifact_manifest","execution_receipt")else listOf("artifact_manifest")).inOrder()
            assertThat(AgentBridgeCodec.encode(agent.first().payload)).isEqualTo(original.export.manifestCanonical)
            assertThat(V2Codec.decodePayload(base.first(), TransferSession.serializer())).isEqualTo(original.session)
            val files = base.filter { it.type == "artifact_manifest" }.map { V2Codec.decodePayload(it, ArtifactManifest.serializer()) }
            assertThat(files).containsExactlyElementsIn(original.export.baseFiles.map { it.manifest }).inOrder()
            assertThat(base.count { it.type == "completion_confirmed" }).isEqualTo(if(completion && !fails)1 else 0)
            if(completion && !fails) {
                val receipt=agent.last().payload as AgentBridgeExecutionReceipt
                assertThat(receipt.sourceAcknowledged).isTrue();assertThat(receipt.status).isEqualTo(AgentBridgeExecutionReceiptStatus.COMPLETE)
                val before=Files.readAllBytes(directory.resolve("completion.json"))
                reconnect.withRetainedCaptureContext(request) { context -> context.begin();hostReceipts.forEach { context.recordHostCommit(it) };assertThat(context.preserveCompletion()).isEqualTo(receipt) }
                assertThat(Files.readAllBytes(directory.resolve("completion.json"))).isEqualTo(before)
                val state = f.store.access { it!!.state }
                val reservation = AgentBridgeExportCaptureReservation(state.acceptedJobs!!.first { it.requestSha256 == receipt.requestSha256 },
                    state.captureClaims!!.first { it.requestSha256 == receipt.requestSha256 })
                f.store.openCaptureSpool(reservation, false) { }.use { stopped ->
                    val checkpoint = stopped.inspectCancellationCheckpoint()
                    assertThat(checkpoint.completion).isEqualTo(receipt)
                    assertThat(checkpoint.manifestSha256).isEqualTo(receipt.manifestSha256)
                    assertThat(checkpoint.frontierSha256).isEqualTo(receipt.frontierSha256)
                    stopped.requireCancellationCheckpoint(checkpoint)
                    assertThat(Files.readAllBytes(directory.resolve("completion.json"))).isEqualTo(before)
                }
                var removedAtNativeCallback = false
                try { reconnect.withRetainedCaptureContext(request) { context ->
                    context.begin()
                    val retained = context.preserveCompletion()
                    finalNativeRead = {
                        if (!removedAtNativeCallback) {
                            removedAtNativeCallback = true
                            Files.delete(directory.resolve("completion.json"))
                        }
                    }
                    try {
                        context.requirePreservedCompletion(retained)
                        throw AssertionError("Final native callback must not erase durable evidence")
                    } catch (_: AgentBridgeException) { }
                    finally { finalNativeRead = null }
                }; throw AssertionError("An invalidated capture owner must not return success") }
                catch (failure: AgentBridgeException) { assertThat(failure.code).isEqualTo(AgentBridgeErrorCode.PERMISSION_REQUIRED) }
                assertThat(removedAtNativeCallback).isTrue()
                assertThat(Files.exists(directory.resolve("completion.json"))).isFalse()
                // Restore the original synthetic signed completion after the corruption check.
                // A fresh stop-only owner must replay completion rather than overwrite it.
                Files.write(directory.resolve("completion.json"), before)
                Files.setPosixFilePermissions(directory.resolve("completion.json"), java.nio.file.attribute.PosixFilePermissions.fromString("rw-------"))
                val cancelledPlan = request.plan as AgentBridgeGeneratedPlan
                val cancel = AgentBridgeCancelRequest(request.approval.approvalId, cancelledPlan.authorityReferences.native.authorityId,
                    request.jobId, cancelledPlan.intent.peer, original.export.requestSha256, "healthmd.agent_cancel_request", 1)
                f.service.requestCancellation(f.peerContext, cancel)
                assertThat(f.restart().finalizeCapturedCancellation(f.peerContext, cancel)).isEqualTo(receipt)
                assertThat(Files.readAllBytes(directory.resolve("completion.json"))).isEqualTo(before)
            }
            if (!fails) {
                assertThat(chunks.size).isEqualTo(if (mode == "already") 0 else original.partitions.size - if (resumedPrefix || mode == "mixed") 1 else 0)
                chunks.zip(original.export.baseFiles.drop(if (resumedPrefix) 1 else 0)).forEach { (chunk, file) -> assertThat(chunk.second).isEqualTo(file.content) }
                assertThat(responses).isEmpty()
            }
            if (mode == "revoke") assertThat(base.size).isEqualTo(2 + original.export.baseFiles.size)
            if (mode == "rewind") assertThat(chunks).isEmpty()
            if (mode == "publication") {
                assertThat(publicationInterrupted).isTrue(); assertThat(chunks).hasSize(1)
                assertThat(base.filter { it.type == "transfer_open" }).hasSize(1)
                assertThat(base.none { it.type == "transfer_finalize" }).isTrue()
            }
            val record = Json.parseToJsonElement(Files.readAllBytes(directory.resolve("progress.json")).decodeToString()).jsonObject.getValue("record").jsonObject
            val progress = Json.parseToJsonElement(String(java.util.Base64.getDecoder().decode(record.getValue("payload").jsonPrimitive.content))).jsonObject
            val count = if (!fails || mode == "bad-final" || completion) original.partitions.size else if (mode in listOf("rewind", "publication")) 1 else 0
            var expected = AgentBridgeTransferFrontier.start(request.jobId, original.export.requestSha256,
                AgentBridgeCodec.sha256(original.export.manifestCanonical), original.session.sessionId)
            original.partitions.take(count).forEachIndexed { index, partition ->
                expected = expected.appending(AgentBridgeTransferFrontierPartition(index.toLong(), partition.transferId,
                    original.export.baseFiles[index].manifest.artifactId, 0, partition.byteCount, partition.chunkCount, partition.sha256))
            }
            assertThat(progress.getValue("version").jsonPrimitive.int).isEqualTo(6)
            assertThat(progress.getValue("committedPartitionCount").jsonPrimitive.long).isEqualTo(count.toLong())
            assertThat(progress.getValue("frontierSHA256").jsonPrimitive.content).isEqualTo(expected.sha256)
            assertThat(Files.readAllBytes(directory.resolve("transfer.json"))).isEqualTo(original.checkpointCanonical)
            if (mode == "publication") {
                fun snapshot() = Files.list(directory).use { paths -> paths.toList().associate { it.fileName.toString() to AgentBridgeCodec.sha256(Files.readAllBytes(it)) } }
                val before = snapshot(); val plan = request.plan as AgentBridgeGeneratedPlan
                val cancel = AgentBridgeCancelRequest(request.approval.approvalId, plan.authorityReferences.native.authorityId,
                    request.jobId, plan.intent.peer, job.requestSha256, "healthmd.agent_cancel_request", 1)
                f.service.requestCancellation(f.peerContext, cancel)
                val receipt = f.restart().finalizeCapturedCancellation(f.peerContext, cancel)
                assertThat(receipt.status).isEqualTo(AgentBridgeExecutionReceiptStatus.CANCELLED); assertThat(receipt.sourceAcknowledged).isTrue()
                assertThat(receipt.artifactCount).isEqualTo(manifest.artifacts.size)
                assertThat(receipt.manifestSha256).isEqualTo(AgentBridgeCodec.sha256(original.export.manifestCanonical))
                assertThat(receipt.committedPartitionCount).isEqualTo(1); assertThat(receipt.frontierSha256).isEqualTo(expected.sha256)
                assertThat(snapshot()).isEqualTo(before)
            }
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }

    @Test fun `native transfer plan retains original session partitions and bytes`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val result = planner.prepareTransferExport(request, manager, journalRenderer(resolution))
            val job = f.store.access { it!!.state.acceptedJobs!!.single() }
            val checkpoint = AgentBridgeNativeTransferCheckpoint.decode(result.checkpointCanonical)
            assertThat(checkpoint.requestContract).isEqualTo("healthmd.agent_execute_request/1")
            assertThat(checkpoint.requestSHA256).isEqualTo(job.requestSha256)
            assertThat(checkpoint.manifestSHA256).isEqualTo(AgentBridgeCodec.sha256(result.export.manifestCanonical))
            assertThat(checkpoint.createdAt).isEqualTo(job.acceptedAt); assertThat(checkpoint.expiresAt).isEqualTo(job.expiresAt)
            assertThat(result.session.jobId).isEqualTo(request.jobId); assertThat(result.session.sessionId).isEqualTo(checkpoint.sessionID)
            assertThat(result.session.requestFingerprint).isEqualTo(job.requestSha256)
            assertThat(result.session.peerBinding).isEqualTo(PeerBinding(f.peer.sourceInstallationId, f.peer.hostInstallationId))
            assertThat(result.maximumInFlightChunks).isEqualTo(4)
            assertThat(result.partitions).hasSize(result.export.baseFiles.size)
            var previous: String? = null
            result.partitions.zip(result.export.baseFiles).forEachIndexed { index, (partition, file) ->
                assertThat(partition.index).isEqualTo(index.toLong()); assertThat(partition.previousSha256).isEqualTo(previous)
                assertThat(partition.artifactId).isEqualTo(file.manifest.artifactId); assertThat(partition.artifactOffset).isEqualTo(0)
                assertThat(partition.byteCount).isEqualTo(file.manifest.byteCount); assertThat(partition.chunkCount).isEqualTo(1)
                assertThat(partition.sha256).isEqualTo(AgentBridgeCodec.sha256(file.content)); previous = partition.sha256
            }
            val directory = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(job.requestSha256)
            val progress = Files.readAllBytes(directory.resolve("progress.json"))
            coEvery { client.aggregate(any()) } throws IllegalStateException("Must not query")
            val forbidden = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { error("Must not render") }, pinLoader = { error("Must not load core") })
            val restored = planner.prepareRetainedTransferExport(request, manager, forbidden)
            assertThat(restored.session).isEqualTo(result.session); assertThat(restored.partitions).isEqualTo(result.partitions)
            assertThat(restored.checkpointCanonical).isEqualTo(result.checkpointCanonical)
            assertThat(restored.export.manifestCanonical).isEqualTo(result.export.manifestCanonical)
            assertThat(Files.readAllBytes(directory.resolve("progress.json"))).isEqualTo(progress)
            assertThat(Files.readAllBytes(directory.resolve("transfer.json"))).isEqualTo(result.checkpointCanonical)
            val copy = result.checkpointCanonical; copy.fill(0)
            assertThat(result.checkpointCanonical).isEqualTo(restored.checkpointCanonical)
            try { (result.partitions as MutableList<TransferPartition>).clear(); throw AssertionError("Partitions must be immutable") }
            catch (_: UnsupportedOperationException) { }
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }
    @Test fun `native transfer plan requires original negotiation before SDK read`() = runBlocking {
        withNativeExportPreparation(transferNegotiation = null) { f, planner, request, client, manager ->
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            try { planner.prepareTransferExport(request, manager, journalRenderer(resolution)); throw AssertionError("Missing original negotiation cannot default") }
            catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) }
            coVerify(exactly = 0) { client.aggregate(any()) }
        }
    }
    @Test fun `missing native transfer plan never remints on recovery`() = runBlocking { checkNativeTransferDamage(false) }
    @Test fun `corrupt native transfer plan never remints on recovery`() = runBlocking { checkNativeTransferDamage(true) }
    private suspend fun checkNativeTransferDamage(corrupt: Boolean) {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val result = planner.prepareTransferExport(request, manager, journalRenderer(resolution))
            val path = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(result.export.requestSha256).resolve("transfer.json")
            if (corrupt) Files.write(path, "{}".toByteArray(), java.nio.file.StandardOpenOption.TRUNCATE_EXISTING) else Files.delete(path)
            val forbidden = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { error("Must not render") }, pinLoader = { error("Must not load core") })
            try { planner.prepareRetainedTransferExport(request, manager, forbidden); throw AssertionError("Pinned transfer metadata cannot remint") }
            catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED) }
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }
    @Test fun `interrupted native transfer plan cannot regenerate after owner restored`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val fingerprint = AgentBridgeCodec.sha256(AgentBridgeCodec.encode(request))
            val directory = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(fingerprint)
            var interrupted = false
            f.peerContext.onCheck = {
                val version = runCatching {
                    val signed = Json.parseToJsonElement(Files.readAllBytes(directory.resolve("progress.json")).decodeToString()).jsonObject
                    val payload = java.util.Base64.getDecoder().decode(signed.getValue("record").jsonObject.getValue("payload").jsonPrimitive.content)
                    Json.parseToJsonElement(payload.decodeToString()).jsonObject.getValue("version").jsonPrimitive.int
                }.getOrNull()
                if (!interrupted && version == 5) {
                    interrupted = true; assertThat(Files.exists(directory.resolve("transfer.json"))).isFalse()
                    throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
                }
            }
            try { planner.prepareTransferExport(request, manager, journalRenderer(resolution)); throw AssertionError("Interrupted transfer plan cannot return success") }
            catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.BINDING_CHANGED) }
            finally { f.peerContext.onCheck = null }
            assertThat(interrupted).isTrue()
            val forbidden = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { error("Must not render") }, pinLoader = { error("Must not load core") })
            try { planner.prepareRetainedTransferExport(request, manager, forbidden); throw AssertionError("Missing pinned plan cannot regenerate") }
            catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED) }
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }
    @Test fun `manifest only progress v4 gains transfer without changing artifacts`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val original = planner.prepareExport(request, manager, journalRenderer(resolution))
            val directory = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(original.requestSha256)
            val signed = Json.parseToJsonElement(Files.readAllBytes(directory.resolve("progress.json")).decodeToString()).jsonObject
            val payload = java.util.Base64.getDecoder().decode(signed.getValue("record").jsonObject.getValue("payload").jsonPrimitive.content)
            val state = Json.parseToJsonElement(payload.decodeToString()).jsonObject
            assertThat(state.getValue("version").jsonPrimitive.int).isEqualTo(4)
            assertThat(state.keys).containsExactly("version", "captures", "artifacts", "engine", "publicArtifactIDs", "manifestSHA256", "manifestByteCount")
            val forbidden = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { error("Must not render") }, pinLoader = { error("Must not load core") })
            val transfer = planner.prepareRetainedTransferExport(request, manager, forbidden)
            assertThat(transfer.export.publicArtifactIDs).isEqualTo(original.publicArtifactIDs)
            assertThat(transfer.export.manifestCanonical).isEqualTo(original.manifestCanonical)
            assertThat(transfer.export.baseFiles.map { it.manifest }).isEqualTo(original.baseFiles.map { it.manifest })
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }
    @Test fun `native transfer checkpoint fits maximum artifact set`() {
        val checkpoint = AgentBridgeNativeTransferCheckpoint.create("a".repeat(64), "b".repeat(64), "2026-05-29T00:00:00Z", "2026-06-05T00:00:00Z",
            4096, TransferCapabilities().negotiatedWith(TransferCapabilities())!!)
        val bytes = checkpoint.canonical(); assertThat(bytes.size).isAtMost(AgentBridgeNativeTransferCheckpoint.MAXIMUM_BYTES)
        val ids = (0 until 4096).map { java.util.UUID.randomUUID().toString() }
        assertThat(AgentBridgeNativeTransferCheckpoint.decode(bytes).validate(checkpoint.requestSHA256, checkpoint.manifestSHA256,
            checkpoint.createdAt, checkpoint.expiresAt, ids)).hasSize(4096)
    }
    @Test fun `native transfer plan owner revocation after publication suppresses return`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val fingerprint = AgentBridgeCodec.sha256(AgentBridgeCodec.encode(request))
            val path = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(fingerprint).resolve("transfer.json")
            var revoked = false
            f.peerContext.onCheck = { if (Files.exists(path)) { revoked = true; f.peerContext.trusted = false } }
            try { planner.prepareTransferExport(request, manager, journalRenderer(resolution)); throw AssertionError("Final native revocation cannot return transfer plan") }
            catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.PERMISSION_REQUIRED) }
            finally { f.peerContext.onCheck = null }
            assertThat(revoked).isTrue(); coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }

    @Test fun `public artifact identity cannot bind before complete approved set`() = runBlocking {
        withNativeExportPreparation { _, planner, request, client, _ ->
            try {
                planner.withCaptureContext(request) { context ->
                    context.begin()
                    try { context.bindPublicArtifactIDs(); throw AssertionError("Incomplete set must not issue identities") }
                    catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED) }
                    try { context.configurationForRead(); throw AssertionError("Caught failure must close context") }
                    catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.PERMISSION_REQUIRED) }
                }
                throw AssertionError("A caught incomplete-set failure must invalidate the owner")
            } catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.PERMISSION_REQUIRED) }
            coVerify(exactly = 0) { client.aggregate(any()) }
        }
    }

    @Test fun `missing public artifact identity progress cannot remint on recovery`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val prepared = planner.prepareExport(request, manager, journalRenderer(resolution))
            assertThat(prepared.publicArtifactIDs).hasSize(2)
            val directory = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(prepared.requestSha256)
            Files.delete(directory.resolve("progress.json"))
            val forbidden = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { error("Must not render") }, pinLoader = { error("Must not load current core") })
            try { planner.prepareRetainedExport(request, manager, forbidden); throw AssertionError("Missing identity progress must require fresh approval") }
            catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED) }
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }

    @Test fun `identity only progress v3 gains manifest without losing original UUIDs`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val ids = planner.withCaptureContext(request) { context ->
                val resolution = context.begin()
                val renderer = journalRenderer(resolution)
                resolution.requestedDays.forEach { renderer.capture(it, manager, context) }
                context.bindPublicArtifactIDs()
            }
            val fingerprint = AgentBridgeCodec.sha256(AgentBridgeCodec.encode(request))
            val path = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(fingerprint).resolve("progress.json")
            val signed = Json.parseToJsonElement(Files.readAllBytes(path).decodeToString()).jsonObject
            val payload = java.util.Base64.getDecoder().decode(signed.getValue("record").jsonObject.getValue("payload").jsonPrimitive.content)
            val state = Json.parseToJsonElement(payload.decodeToString()).jsonObject
            assertThat(state.getValue("version").jsonPrimitive.int).isEqualTo(3)
            assertThat(state.keys).containsExactly("version", "captures", "artifacts", "engine", "publicArtifactIDs")
            val forbidden = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { error("Must not render") }, pinLoader = { error("Must not load core") })
            val prepared = planner.prepareRetainedExport(request, manager, forbidden)
            assertThat(prepared.publicArtifactIDs).isEqualTo(ids)
            val manifest = AgentBridgeCodec.decode(prepared.manifestCanonical) as AgentBridgeArtifactManifest
            assertThat(manifest.artifacts.map { it.artifactId }.toSet()).isEqualTo(ids.values.toSet())
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }

    @Test fun `native manifest counts absent summary observations`() = runBlocking {
        assertNativeManifestObservationCount(null, 0)
    }
    @Test fun `native manifest counts meaningful zero summary observations`() = runBlocking {
        assertNativeManifestObservationCount(0L, 2)
    }
    private suspend fun assertNativeManifestObservationCount(steps: Long?, expected: Int) {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns steps
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val prepared = planner.prepareExport(request, manager, journalRenderer(resolution))
            val manifest = AgentBridgeCodec.decode(prepared.manifestCanonical) as AgentBridgeArtifactManifest
            assertThat(manifest.branchStatuses).hasSize(1)
            assertThat(manifest.branchStatuses.single().recordCount).isEqualTo(expected)
            assertThat(manifest.branchStatuses.single().status).isEqualTo(AgentBridgeArtifactManifestBranchStatusesItemStatus.SUCCESS)
            assertThat(manifest.captureStatus).isEqualTo(AgentBridgeArtifactManifestCaptureStatus.COMPLETE)
            assertThat(manifest.artifacts).hasSize(2)
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }
    @Test fun `missing native manifest never rebuilds on recovery`() = runBlocking { assertNativeManifestRecoveryRejects("missing") }
    @Test fun `corrupt native manifest never rebuilds on recovery`() = runBlocking { assertNativeManifestRecoveryRejects("corrupt") }
    private suspend fun assertNativeManifestRecoveryRejects(mode: String) {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val prepared = planner.prepareExport(request, manager, journalRenderer(resolution))
            val path = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(prepared.requestSha256).resolve("manifest.json")
            if (mode == "missing") Files.delete(path) else Files.write(path, "corrupt".toByteArray())
            val forbidden = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { error("Must not render") }, pinLoader = { error("Must not load core") })
            try { planner.prepareRetainedExport(request, manager, forbidden); throw AssertionError("Original missing or corrupt manifest cannot be rebuilt") }
            catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED) }
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }
    @Test fun `interrupted native manifest publication cannot regenerate after owner restored`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            coEvery { client.aggregate(any()) } returns values
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            val fingerprint = AgentBridgeCodec.sha256(AgentBridgeCodec.encode(request))
            val directory = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures").resolve(fingerprint)
            var interrupted = false
            f.peerContext.onCheck = {
                val version = runCatching {
                    val signed = Json.parseToJsonElement(Files.readAllBytes(directory.resolve("progress.json")).decodeToString()).jsonObject
                    val payload = java.util.Base64.getDecoder().decode(signed.getValue("record").jsonObject.getValue("payload").jsonPrimitive.content)
                    Json.parseToJsonElement(payload.decodeToString()).jsonObject.getValue("version").jsonPrimitive.int
                }.getOrNull()
                if (!interrupted && version == 4) {
                    interrupted = true
                    assertThat(Files.exists(directory.resolve("manifest.json"))).isFalse()
                    throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
                }
            }
            try { planner.prepareExport(request, manager, journalRenderer(resolution)); throw AssertionError("Interrupted manifest cannot return success") }
            catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.BINDING_CHANGED) }
            finally { f.peerContext.onCheck = null }
            assertThat(interrupted).isTrue()
            val forbidden = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { error("Must not render") }, pinLoader = { error("Must not load core") })
            try { planner.prepareRetainedExport(request, manager, forbidden); throw AssertionError("Pinned missing manifest cannot regenerate") }
            catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED) }
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }

    @Test fun `native export producer never returns partial set after later SDK failure`() = runBlocking {
        withNativeExportPreparation { f, planner, request, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 1L
            var reads = 0
            coEvery { client.aggregate(any()) } coAnswers {
                if (++reads == 2) throw IllegalStateException("Synthetic SDK failure")
                values
            }
            val resolution = Json.decodeFromString<AgentBridgeRequestSettingsResolution>(f.store.access { it!!.state.plans.single().resolutionCanonical })
            try { planner.prepareExport(request, manager, journalRenderer(resolution)); throw AssertionError("A successful partial export must never return") }
            catch (e: AgentBridgeNativeRenderException) { assertThat(e.code).isEqualTo(AgentBridgeNativeRenderFailure.RENDER_FAILED); assertThat(reads).isEqualTo(2) }
            val forbidden = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { error("Must not render") }, pinLoader = { error("Must not load current core") })
            try { planner.prepareRetainedExport(request, manager, forbidden); throw AssertionError("Ambiguous later SDK day must not be retried") }
            catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED) }
            coVerify(exactly = 2) { client.aggregate(any()) }
        }
    }

    @Test fun `bridge rendering binds exact request scope paths and frozen profile`() = runBlocking {
        withNativeSDKCapture(listOf("steps")) { _, context, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 0L
            coEvery { client.aggregate(any()) } returns values
            val captured = manager.captureAgentBridgeDay("2026-03-08", context)
            val resolution = context.configurationForRead()
            var calls = 0
            val renderer = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { request ->
                calls++
                assertThat(request.data.activity.steps).isEqualTo(captured.activity.steps)
                assertThat(request.data.heart.averageHeartRate).isNull()
                assertThat(request.metricSelection.enabledMetrics).containsExactly("steps")
                assertThat(request.profile).isEqualTo(AndroidExportProfile.android_frozen_v4)
                assertThat(request.mode).isEqualTo(ExportEngineMode.rust)
                bridgeRenderedPlan(request, resolution)
            })
            val rendered = renderer.render("2026-03-08", captured, resolution, "a".repeat(64))
            assertThat(rendered.artifact.relativePath).isEqualTo(resolution.predictedRelativePaths.last())
            assertThat(calls).isEqualTo(1)
            coVerify(exactly = 1) { client.aggregate(any()) }
        }
    }

    @Test fun `bridge rendering rejects core profile path and relabeled schema bytes`() = runBlocking {
        withNativeSDKCapture(listOf("steps")) { _, context, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 1L
            coEvery { client.aggregate(any()) } returns values
            val captured = manager.captureAgentBridgeDay("2026-03-08", context)
            val resolution = context.configurationForRead()
            for (mode in listOf("profile", "path", "body", "ids", "extra", "pin", "cancel")) {
                val renderer = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { request ->
                    val result = bridgeRenderedPlan(request, resolution, mode)
                    if (mode == "cancel") currentCoroutineContext().cancel()
                    result
                })
                supervisorScope {
                    val child = async { renderer.render("2026-03-08", captured, resolution, "a".repeat(64)) }
                    try { child.await(); throw AssertionError("Invalid artifact returned: $mode") }
                    catch (failure: AgentBridgeNativeRenderException) {
                        assertThat(failure.code).isEqualTo(if (mode == "pin") AgentBridgeNativeRenderFailure.INCOMPATIBLE_CORE else AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
                    } catch (failure: CancellationException) { assertThat(mode).isEqualTo("cancel") }
                }
            }
        }
    }

    @Test fun `native artifact producer binds accepted fingerprint and terminal failures`() = runBlocking {
        for (mode in listOf("normal", "profile", "owner")) {
            try {
                withNativeSDKCapture(listOf("steps"), afterCapture = { _, _, _, _, _, failure ->
                    assertThat(failure == null).isEqualTo(mode == "normal")
                }) { f, context, client, manager ->
                    val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
                    coEvery { client.aggregate(any()) } returns values
                    val resolution = context.configurationForRead()
                    val fingerprint = f.store.access { it!!.state.acceptedJobs!!.single().requestSha256 }
                    val renderer = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { request ->
                        assertThat(request.ids.requestId).isEqualTo(fingerprint)
                        assertThat(request.ids.sessionId).isEqualTo("$fingerprint-2026-03-08")
                        val result = bridgeRenderedPlan(request, resolution, mode)
                        if (mode == "owner") f.peerContext.trusted = false
                        result
                    }, pinLoader = { testPin(ExportEngineMode.rust).copy(registrySha256 = resolution.registrySha256) })
                    try {
                        val result = renderer.capture("2026-03-08", manager, context)
                        assertThat(mode).isEqualTo("normal")
                        assertThat(result.artifact.relativePath).isEqualTo(resolution.predictedRelativePaths.last())
                    } catch (failure: Exception) {
                        try { context.configurationForRead(); throw AssertionError("Failed producer owner remained usable") }
                        catch (_: AgentBridgeException) { }
                        if (mode == "profile") assertThat((failure as AgentBridgeNativeRenderException).code).isEqualTo(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT)
                        // Catching the failure must not let the outer native owner succeed.
                    } finally { coVerify(exactly = 1) { client.aggregate(any()) } }
                }
            } catch (failure: AgentBridgeException) {
                assertThat(mode).isNotEqualTo("normal")
                assertThat(failure.code).isEqualTo(AgentBridgeErrorCode.PERMISSION_REQUIRED)
            }
        }
    }

    private fun journalRenderer(resolution: AgentBridgeRequestSettingsResolution, mode: String = "normal") =
        AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { request -> bridgeRenderedPlan(request, resolution, mode) },
            pinLoader = { testPin(ExportEngineMode.rust).copy(registrySha256 = resolution.registrySha256,
                coreSourceRevision = if (mode == "engine-changed") "other-source" else testPin(ExportEngineMode.rust).coreSourceRevision) })

    @Test fun `retained artifacts return exact bytes without SDK or current core`() = runBlocking {
        var original: AgentBridgeNativeRenderedDay? = null
        withNativeSDKCapture(listOf("steps"), afterCapture = { f, planner, request, client, manager, failure ->
            assertThat(failure).isNull()
            val before = f.store.access { it!!.state }
            coEvery { client.aggregate(any()) } throws AssertionError("Retained artifact must not query SDK")
            planner.withRetainedCaptureContext(request) { context ->
                context.begin()
                val renderer = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { throw AssertionError("Must not render") },
                    pinLoader = { throw AssertionError("Must not load current core") })
                val result = renderer.capture("2026-03-08", manager, context)
                assertThat(result.artifact).isEqualTo(original!!.artifact)
                assertThat(result.pin).isEqualTo(original!!.pin)
            }
            coVerify(exactly = 1) { client.aggregate(any()) }
            assertThat(f.store.access { it!!.state }).isEqualTo(before)
        }) { _, context, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 0L
            coEvery { client.aggregate(any()) } returns values
            original = journalRenderer(context.configurationForRead()).capture("2026-03-08", manager, context)
        }
    }

    @Test fun `missing corrupt and ambiguous artifacts never regenerate`() = runBlocking {
        for (mode in listOf("missing", "both", "corrupt", "engine", "interrupted")) {
            try {
                withNativeSDKCapture(listOf("steps"), afterCapture = { f, planner, request, client, manager, failure ->
                    assertThat(failure != null).isEqualTo(mode == "interrupted")
                    val captures = Files.walk(f.parent).use { paths -> paths.filter { it.fileName.toString() == "captures" }.findFirst().get() }
                    val directory = Files.newDirectoryStream(captures).use { it.first() }
                    val artifact = directory.resolve("artifact-2026-03-08.json")
                    when (mode) {
                        "missing", "both" -> { Files.delete(artifact); if (mode == "both") Files.delete(directory.resolve("artifact-started-2026-03-08.json")) }
                        "corrupt" -> Files.write(artifact, "corrupt".toByteArray())
                        "engine" -> Files.write(directory.resolve("progress.json"), "corrupt".toByteArray())
                    }
                    try {
                        planner.withRetainedCaptureContext(request) { context ->
                            context.begin()
                            AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { throw AssertionError("Must not render") },
                                pinLoader = { throw AssertionError("Must not load current core") }).capture("2026-03-08", manager, context)
                        }
                        throw AssertionError("Invalid artifact returned")
                    } catch (error: AgentBridgeException) { assertThat(error.code).isEqualTo(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED) }
                    coVerify(exactly = 1) { client.aggregate(any()) }
                }) { _, context, client, manager ->
                    val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 1L
                    coEvery { client.aggregate(any()) } returns values
                    journalRenderer(context.configurationForRead(), if (mode == "interrupted") "profile" else "normal").capture("2026-03-08", manager, context)
                }
            } catch (error: AgentBridgeNativeRenderException) { assertThat(mode).isEqualTo("interrupted"); assertThat(error.code).isEqualTo(AgentBridgeNativeRenderFailure.INVALID_ARTIFACT) }
        }
    }

    @Test fun `artifact recovery completes only unstarted day and preserves both`() = runBlocking {
        withNativeSDKCapture(listOf("steps"), afterCapture = { _, planner, request, client, manager, failure ->
            assertThat(failure).isNull()
            val digests = mutableMapOf<String, String>()
            planner.withRetainedCaptureContext(request) { context ->
                context.begin()
                val renderer = journalRenderer(context.configurationForRead())
                val first = renderer.capture("2026-03-08", manager, context)
                val second = renderer.capture("2026-03-07", manager, context)
                digests[first.day] = first.artifact.sha256; digests[second.day] = second.artifact.sha256
                assertThat(first.artifact.artifactId).isNotEqualTo(second.artifact.artifactId)
            }
            planner.withRetainedCaptureContext(request) { context ->
                context.begin()
                val forbidden = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { throw AssertionError("Must not render") },
                    pinLoader = { throw AssertionError("Must not load current core") })
                for (day in listOf("2026-03-07", "2026-03-08")) assertThat(forbidden.capture(day, manager, context).artifact.sha256).isEqualTo(digests[day])
            }
            coVerify(exactly = 2) { client.aggregate(any()) }
        }) { _, context, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 1L
            coEvery { client.aggregate(any()) } returns values
            journalRenderer(context.configurationForRead()).capture("2026-03-08", manager, context)
        }
    }

    @Test fun `concurrent artifact days preserve signed frontiers and reopen`() = runBlocking {
        withNativeSDKCapture(listOf("steps"), afterCapture = { _, planner, request, client, manager, failure ->
            assertThat(failure).isNull()
            planner.withRetainedCaptureContext(request) { context ->
                context.begin()
                val forbidden = AgentBridgeNativeDayRenderer(DailyAggregateRustPlanner { throw AssertionError("Must not render") },
                    pinLoader = { throw AssertionError("Must not load current core") })
                for (day in listOf("2026-03-07", "2026-03-08")) assertThat(forbidden.capture(day, manager, context).day).isEqualTo(day)
            }
            coVerify(exactly = 2) { client.aggregate(any()) }
        }) { _, context, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 1L
            coEvery { client.aggregate(any()) } coAnswers { yield(); values }
            val renderer = journalRenderer(context.configurationForRead())
            coroutineScope {
                val a = async(Dispatchers.Default) { renderer.capture("2026-03-07", manager, context) }
                val b = async(Dispatchers.Default) { renderer.capture("2026-03-08", manager, context) }
                assertThat(a.await().artifact.relativePath).isNotEqualTo(b.await().artifact.relativePath)
            }
        }
    }

    @Test fun `artifact engine mismatch rejects unstarted day before SDK`() = runBlocking {
        try {
            withNativeSDKCapture(listOf("steps"), afterCapture = { _, _, _, client, _, failure ->
                assertThat((failure as AgentBridgeException).code).isEqualTo(AgentBridgeErrorCode.BINDING_CHANGED)
                coVerify(exactly = 1) { client.aggregate(any()) }
            }) { _, context, client, manager ->
                val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 1L
                coEvery { client.aggregate(any()) } returns values
                val resolution = context.configurationForRead()
                journalRenderer(resolution).capture("2026-03-08", manager, context)
                journalRenderer(resolution, "engine-changed").capture("2026-03-07", manager, context)
            }
        } catch (error: AgentBridgeException) { assertThat(error.code).isEqualTo(AgentBridgeErrorCode.BINDING_CHANGED) }
    }

    /** Separate host JNI qualification. Default JVM runs report this native-dependent case skipped;
     * the local qualification command supplies a freshly source-built compatible host library. */
    @Test fun `bridge captured days render through actual host UniFFI frozen v4`() = runBlocking {
        val library = System.getenv("HEALTHMD_BRIDGE_HOST_CORE_DIRECTORY")
        Assume.assumeTrue("Host native-core qualification requires its explicit library directory", !library.isNullOrBlank())
        System.setProperty("jna.library.path", library!!)
        for (value in listOf<Long?>(null, 0L, 123L)) withNativeSDKCapture(listOf("steps")) { _, context, client, manager ->
            val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns value
            coEvery { client.aggregate(any()) } returns values
            val captured = manager.captureAgentBridgeDay("2026-03-08", context).let {
                it.copy(heart = it.heart.copy(averageHeartRate = 99.0))
            }
            val rendered = AgentBridgeNativeDayRenderer().render("2026-03-08", captured,
                context.configurationForRead(), "a".repeat(64))
            val json = Json.parseToJsonElement(rendered.artifact.content.decodeToString()).jsonObject
            assertThat(json["schema_version"]).isNull()
            assertThat(json["units"]!!.jsonPrimitive.content).isEqualTo("metric")
            assertThat(json["activity"]?.jsonObject?.get("steps")?.jsonPrimitive?.intOrNull).isEqualTo(value?.toInt())
            assertThat(json["heart"]).isNull()
            assertThat(rendered.pin.ianaTimeZone).isEqualTo("America/Los_Angeles")
            coVerify(exactly = 1) { client.aggregate(any()) }
        }
        withNativeSDKCapture(listOf("steps", "heart_rate_avg", "heart_rate_min", "heart_rate_max", "resting_heart_rate", "android.hrv_rmssd")) { _, context, client, manager ->
            val values = mockk<AggregationResult>()
            every { values[StepsRecord.COUNT_TOTAL] } returns 123L
            every { values[HeartRateRecord.BPM_AVG] } returns 72L
            every { values[HeartRateRecord.BPM_MIN] } returns 40L
            every { values[HeartRateRecord.BPM_MAX] } returns 150L
            coEvery { client.aggregate(any()) } returns values
            val time = Instant.parse("2026-03-08T12:00:00Z")
            coEvery { client.readRecords(any<ReadRecordsRequest<androidx.health.connect.client.records.Record>>()) } coAnswers {
                val request = firstArg<ReadRecordsRequest<androidx.health.connect.client.records.Record>>()
                when (request.recordType) {
                    RestingHeartRateRecord::class -> ReadRecordsResponse<androidx.health.connect.client.records.Record>(listOf(RestingHeartRateRecord(time, null, 55, Metadata.manualEntry())), null)
                    HeartRateVariabilityRmssdRecord::class -> ReadRecordsResponse<androidx.health.connect.client.records.Record>(listOf(HeartRateVariabilityRmssdRecord(time, null, 31.0, Metadata.manualEntry())), null)
                    else -> error("Unselected record family")
                }
            }
            val rendered = AgentBridgeNativeDayRenderer().capture("2026-03-08", manager, context)
            val heart = Json.parseToJsonElement(rendered.artifact.content.decodeToString()).jsonObject.getValue("heart").jsonObject
            assertThat(heart.keys).containsExactly("averageHeartRate", "heartRateMin", "heartRateMax", "restingHeartRate", "hrv")
            mapOf("averageHeartRate" to 72.0, "heartRateMin" to 40.0, "heartRateMax" to 150.0, "restingHeartRate" to 55.0, "hrv" to 31.0).forEach { (key, value) ->
                assertThat(heart.getValue(key).jsonPrimitive.double).isEqualTo(value)
            }
        }
    }

    private fun bridgeRenderedPlan(request: FrozenDailyAggregateExportRequest, resolution: AgentBridgeRequestSettingsResolution,
        mode: String = "normal"): DailyAggregateRustPlan {
        val profile = if (mode == "profile") AndroidExportProfile.android_analytical_v5 else request.profile
        val path = if (mode == "path") "unapproved.json" else request.relativePath(com.healthmd.domain.model.ExportFormat.JSON)
        val bytes = Json.encodeToString(buildJsonObject {
            if (mode == "body") put("schema_version", 5)
            put("date", request.data.date.toString()); put("type", "health-data"); put("units", "metric")
        }).toByteArray()
        val session = if (mode == "ids") "other-session" else request.ids.sessionId
        val item = testArtifact(path = path, content = bytes, requestId = request.ids.requestId, sessionId = session, profile = profile)
        val items = if (mode == "extra") listOf(item, testArtifact(path = "extra.json", content = bytes,
            requestId = request.ids.requestId, sessionId = session, profile = profile)) else listOf(item)
        val plan = ExportArtifactPlan(ExportArtifactPlan.SCHEMA, ExportArtifactPlan.VERSION, request.ids.requestId, session, profile, items)
        val pin = testPin(ExportEngineMode.rust).copy(registrySha256 = resolution.registrySha256,
            publicSchemaVersion = if (mode == "pin") 5u else 4u)
        return DailyAggregateRustPlan(pin, plan)
    }

    @Test fun `retained SDK capture reopens immutable signed zero empty and populated days without SDK`() = runBlocking {
        for (value in listOf<Long?>(null, 0L, 123L)) withNativeSDKCapture(listOf("steps"), afterCapture = { f, planner, request, client, manager, failure ->
            assertThat(failure).isNull()
            val before = f.store.access { it!!.state }
            coEvery { client.aggregate(any()) } throws IOException("must-not-query")
            repeat(3) {
                planner.withRetainedCaptureContext(request) { context ->
                    context.begin()
                    assertThat(manager.captureAgentBridgeDay("2026-03-08", context).activity.steps).isEqualTo(value?.toInt())
                }
            }
            coVerify(exactly = 1) { client.aggregate(any()) }
            assertThat(f.store.access { it!!.state }).isEqualTo(before)
        }) { _, context, client, manager ->
            val result = mockk<AggregationResult>()
            every { result[StepsRecord.COUNT_TOTAL] } returns value
            coEvery { client.aggregate(any()) } returns result
            manager.captureAgentBridgeDay("2026-03-08", context)
        }
    }

    @Test fun `retained capture reuses completed day and queries only unstarted day`() = runBlocking {
        withNativeSDKCapture(listOf("steps"), afterCapture = { _, planner, request, client, manager, _ ->
            planner.withRetainedCaptureContext(request) { context ->
                context.begin()
                assertThat(manager.captureAgentBridgeDay("2026-03-08", context).activity.steps).isEqualTo(10)
                assertThat(manager.captureAgentBridgeDay("2026-03-07", context).activity.steps).isEqualTo(20)
            }
            coVerify(exactly = 2) { client.aggregate(any()) }
        }) { _, context, client, manager ->
            val first = mockk<AggregationResult>(); every { first[StepsRecord.COUNT_TOTAL] } returns 10L
            val second = mockk<AggregationResult>(); every { second[StepsRecord.COUNT_TOTAL] } returns 20L
            coEvery { client.aggregate(any()) } returnsMany listOf(first, second)
            manager.captureAgentBridgeDay("2026-03-08", context)
        }
    }

    @Test fun `retained capture cannot acquire active original job lock`() = runBlocking {
        withNativeSDKCapture(listOf("steps")) { f, context, client, manager ->
            // The direct spool handle exercises the same job lock without changing the owner.
            val reservation = f.store.access { AgentBridgeExportCaptureReservation(it!!.state.acceptedJobs!!.single(), it.state.captureClaims!!.single()) }
            f.expect(AgentBridgeErrorCode.BUSY) { f.store.openCaptureSpool(reservation, false) { } }
            val result = mockk<AggregationResult>(); every { result[StepsRecord.COUNT_TOTAL] } returns 12L
            coEvery { client.aggregate(any()) } returns result
            assertThat(manager.captureAgentBridgeDay("2026-03-08", context).activity.steps).isEqualTo(12)
        }
    }

    @Test fun `retained SDK capture rejects missing corrupt and ambiguous files before SDK`() = runBlocking {
        for (mode in listOf("header", "progress", "payload", "both", "corrupt", "extra", "permissions", "symlink", "hardlink", "started")) {
            withNativeSDKCapture(listOf("steps"), afterCapture = { f, planner, request, client, manager, failure ->
                assertThat(failure).isNull()
                val captures = Files.walk(f.parent).use { paths -> paths.filter { it.fileName.toString() == "captures" }.findFirst().get() }
                val directory = Files.newDirectoryStream(captures).use { it.first() }
                val payload = directory.resolve("day-2026-03-08.json")
                when (mode) {
                    "header" -> Files.delete(directory.resolve("header.json"))
                    "progress" -> Files.delete(directory.resolve("progress.json"))
                    "payload", "both" -> {
                        Files.delete(payload)
                        if (mode == "both") Files.delete(directory.resolve("started-2026-03-08.json"))
                    }
                    "corrupt" -> Files.write(payload, "corrupt".toByteArray())
                    "extra" -> Files.createFile(directory.resolve("unknown"))
                    "permissions" -> Files.setPosixFilePermissions(payload, java.nio.file.attribute.PosixFilePermissions.fromString("rw-r--r--"))
                    "symlink" -> {
                        val moved = f.parent.resolve("saved-payload"); Files.move(payload, moved)
                        Files.createSymbolicLink(payload, moved)
                    }
                    "hardlink" -> Files.createLink(f.parent.resolve("saved-payload"), payload)
                }
                try {
                    planner.withRetainedCaptureContext(request) { context ->
                        context.begin(); manager.captureAgentBridgeDay("2026-03-08", context)
                    }
                    throw AssertionError("Invalid retained capture returned: $mode")
                } catch (failure: AgentBridgeException) { assertThat(failure.code).isAnyOf(AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED, AgentBridgeErrorCode.BINDING_CHANGED) }
                coVerify(exactly = if (mode == "started") 0 else 1) { client.aggregate(any()) }
            }) { _, context, client, manager ->
                if (mode == "started") context.claimDay("2026-03-08")
                else {
                    val result = mockk<AggregationResult>(); every { result[StepsRecord.COUNT_TOTAL] } returns 0L
                    coEvery { client.aggregate(any()) } returns result
                    manager.captureAgentBridgeDay("2026-03-08", context)
                }
            }
        }
    }

    @Test fun `native SDK capture reads only approved metrics over exact DST day`() = runBlocking {
        withNativeSDKCapture(listOf("steps", "heart_rate_avg")) { _, context, client, manager ->
            val requests = mutableListOf<AggregateRequest>()
            val values = mockk<AggregationResult>()
            every { values[StepsRecord.COUNT_TOTAL] } returns 0L
            every { values[HeartRateRecord.BPM_AVG] } returns 72L
            coEvery { client.aggregate(capture(requests)) } returns values
            val result = manager.captureAgentBridgeDay("2026-03-08", context)
            assertThat(result.activity.steps).isEqualTo(0)
            assertThat(result.heart.averageHeartRate).isEqualTo(72.0)
            assertThat(result.heart.heartRateMin).isNull(); assertThat(result.heart.heartRateMax).isNull()
            assertThat(result.heart.hrv).isNull(); assertThat(result.heart.restingHeartRate).isNull()
            assertThat(requests.map { request -> AggregateRequest::class.java.getDeclaredField("metrics").apply { isAccessible = true }.get(request) }).containsExactly(setOf(StepsRecord.COUNT_TOTAL), setOf(HeartRateRecord.BPM_AVG)).inOrder()
            for (request in requests) {
                val range = AggregateRequest::class.java.getDeclaredField("timeRangeFilter").apply { isAccessible = true }.get(request) as androidx.health.connect.client.time.TimeRangeFilter
                assertThat(range.startTime).isEqualTo(Instant.parse("2026-03-08T08:00:00Z"))
                assertThat(range.endTime).isEqualTo(Instant.parse("2026-03-09T07:00:00Z"))
            }
            coVerify(exactly = 0) { client.readRecords(any<ReadRecordsRequest<androidx.health.connect.client.records.Record>>()) }
        }
    }

    @Test fun `native SDK capture keeps native reducers and bounded latest records without inventing empty values`() = runBlocking {
        for (populated in listOf(false, true)) withNativeSDKCapture(listOf("steps", "heart_rate_avg", "heart_rate_min", "heart_rate_max", "resting_heart_rate", "android.hrv_rmssd")) { _, context, client, manager ->
            val values = mockk<AggregationResult>()
            every { values[StepsRecord.COUNT_TOTAL] } returns if (populated) 123L else null
            every { values[HeartRateRecord.BPM_AVG] } returns if (populated) 72L else null
            every { values[HeartRateRecord.BPM_MIN] } returns if (populated) 40L else null
            every { values[HeartRateRecord.BPM_MAX] } returns if (populated) 150L else null
            coEvery { client.aggregate(any()) } returns values
            val time = Instant.parse("2026-03-08T12:00:00Z")
            coEvery { client.readRecords(any<ReadRecordsRequest<androidx.health.connect.client.records.Record>>()) } coAnswers {
                val request = firstArg<ReadRecordsRequest<androidx.health.connect.client.records.Record>>()
                assertThat(request.pageSize).isEqualTo(1); assertThat(request.ascendingOrder).isFalse()
                when (request.recordType) {
                    RestingHeartRateRecord::class -> ReadRecordsResponse<androidx.health.connect.client.records.Record>(if (populated) listOf(RestingHeartRateRecord(time, null, 55, Metadata.manualEntry())) else emptyList(), null)
                    HeartRateVariabilityRmssdRecord::class -> ReadRecordsResponse<androidx.health.connect.client.records.Record>(if (populated) listOf(HeartRateVariabilityRmssdRecord(time, null, 31.0, Metadata.manualEntry())) else emptyList(), null)
                    else -> error("Unselected record family")
                }
            }
            val result = manager.captureAgentBridgeDay("2026-03-08", context)
            assertThat(result.activity.steps).isEqualTo(if (populated) 123 else null)
            assertThat(result.heart.averageHeartRate).isEqualTo(if (populated) 72.0 else null)
            assertThat(result.heart.heartRateMin).isEqualTo(if (populated) 40.0 else null)
            assertThat(result.heart.heartRateMax).isEqualTo(if (populated) 150.0 else null)
            assertThat(result.heart.restingHeartRate).isEqualTo(if (populated) 55.0 else null)
            assertThat(result.heart.hrv).isEqualTo(if (populated) 31.0 else null)
        }
    }

    @Test fun `native SDK capture rejects unapproved day missing permission and native failures before fallback`() = runBlocking {
        for (mode in listOf("day", "permission", "sdk", "invalid")) {
            try {
                withNativeSDKCapture(listOf("steps")) { _, context, client, manager ->
                    if (mode == "permission") coEvery { client.permissionController.getGrantedPermissions() } returns emptySet()
                    if (mode == "invalid") {
                        val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns Long.MAX_VALUE
                        coEvery { client.aggregate(any()) } returns values
                    } else coEvery { client.aggregate(any()) } throws IllegalStateException("synthetic SDK body")
                    try { manager.captureAgentBridgeDay(if (mode == "day") "2026-03-06" else "2026-03-08", context) }
                    finally { coVerify(exactly = if (mode in listOf("day", "permission")) 0 else 1) { client.aggregate(any()) } }
                }
                throw AssertionError("Expected capture failure")
            } catch (e: AgentBridgeException) {
                assertThat(e.code).isEqualTo(if (mode == "day") AgentBridgeErrorCode.INVALID_REQUEST else AgentBridgeErrorCode.PERMISSION_REQUIRED)
            } catch (e: AgentBridgeNativeCaptureFailure) {
                assertThat(mode).isAnyOf("sdk", "invalid"); assertThat(e.cause).isNull(); assertThat(e.message).isEqualTo("native_capture_failed")
            }
        }
    }

    @Test fun `native SDK failure cannot be caught to retry or return success`() = runBlocking {
        try {
            withNativeSDKCapture(listOf("steps")) { _, context, client, manager ->
                coEvery { client.aggregate(any()) } throws IllegalStateException("synthetic SDK body")
                try { manager.captureAgentBridgeDay("2026-03-08", context); throw AssertionError("Expected SDK failure") }
                catch (_: AgentBridgeNativeCaptureFailure) { }
                val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
                coEvery { client.aggregate(any()) } returns values
                try { manager.captureAgentBridgeDay("2026-03-08", context); throw AssertionError("Cannot retry failed capture") }
                catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.PERMISSION_REQUIRED) }
                coVerify(exactly = 1) { client.aggregate(any()) }
                // Deliberately swallow SDK error and return; enclosing operation must reject.
            }
            throw AssertionError("Cannot return success after SDK failure")
        } catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.PERMISSION_REQUIRED) }
    }

    @Test fun `native SDK cannot capture successful day twice even when duplicate caught`() = runBlocking {
        try {
            withNativeSDKCapture(listOf("steps")) { _, context, client, manager ->
                val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
                coEvery { client.aggregate(any()) } returns values
                manager.captureAgentBridgeDay("2026-03-08", context)
                manager.captureAgentBridgeDay("2026-03-07", context)
                try { manager.captureAgentBridgeDay("2026-03-08", context); throw AssertionError("Cannot recapture successful day") }
                catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.BUSY) }
                coVerify(exactly = 2) { client.aggregate(any()) }
            }
            throw AssertionError("Duplicate attempt permanently invalidates operation")
        } catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.PERMISSION_REQUIRED) }
    }

    @Test fun `native SDK latest reads continue empty pages until value or terminal token`() = runBlocking {
        for (populated in listOf(false, true)) withNativeSDKCapture(listOf("resting_heart_rate", "android.hrv_rmssd")) { _, context, client, manager ->
            val requests = mutableListOf<ReadRecordsRequest<androidx.health.connect.client.records.Record>>()
            val time = Instant.parse("2026-03-08T12:00:00Z")
            coEvery { client.readRecords(any<ReadRecordsRequest<androidx.health.connect.client.records.Record>>()) } coAnswers {
                val request = firstArg<ReadRecordsRequest<androidx.health.connect.client.records.Record>>()
                requests += request
                assertThat(request.ascendingOrder).isFalse(); assertThat(request.pageSize).isEqualTo(1)
                if (request.pageToken == null) ReadRecordsResponse(emptyList(), "next")
                else {
                    assertThat(request.pageToken).isEqualTo("next")
                    val record = when (request.recordType) {
                        RestingHeartRateRecord::class -> RestingHeartRateRecord(time, null, 55, Metadata.manualEntry())
                        HeartRateVariabilityRmssdRecord::class -> HeartRateVariabilityRmssdRecord(time, null, 31.0, Metadata.manualEntry())
                        else -> error("Unselected native record")
                    }
                    ReadRecordsResponse(if (populated) listOf(record) else emptyList(), if (populated) "older-not-needed" else "")
                }
            }
            val result = manager.captureAgentBridgeDay("2026-03-08", context)
            assertThat(result.heart.restingHeartRate).isEqualTo(if (populated) 55.0 else null)
            assertThat(result.heart.hrv).isEqualTo(if (populated) 31.0 else null)
            assertThat(requests).hasSize(4)
            coVerify(exactly = 0) { client.aggregate(any()) }
        }
    }

    @Test fun `native SDK latest reads reject token cycles budget exhaustion and cancellation between pages`() = runBlocking {
        for (mode in listOf("cycle", "budget", "cancel")) supervisorScope {
            var reads = 0
            val child = async {
                withNativeSDKCapture(listOf("resting_heart_rate")) { _, context, client, manager ->
                    coEvery { client.readRecords(any<ReadRecordsRequest<androidx.health.connect.client.records.Record>>()) } coAnswers {
                        reads++
                        yield()
                        if (mode == "cancel") currentCoroutineContext().job.cancel()
                        ReadRecordsResponse<androidx.health.connect.client.records.Record>(emptyList(), if (mode == "budget") "page-$reads" else "next")
                    }
                    manager.captureAgentBridgeDay("2026-03-08", context)
                }
            }
            try { child.await(); throw AssertionError("Cannot return empty from unfinished pagination") }
            catch (e: AgentBridgeException) { assertThat(mode).isEqualTo("budget"); assertThat(e.code).isEqualTo(AgentBridgeErrorCode.QUERY_BUDGET_EXCEEDED) }
            catch (_: AgentBridgeNativeCaptureFailure) { assertThat(mode).isEqualTo("cycle") }
            catch (_: CancellationException) { assertThat(mode).isEqualTo("cancel") }
            when (mode) {
                "cycle" -> assertThat(reads).isEqualTo(2)
                "budget" -> { assertThat(reads).isGreaterThan(1); assertThat(reads).isAtMost(64) }
                else -> assertThat(reads).isEqualTo(1)
            }
        }
    }

    @Test fun `native SDK capture rechecks original authority after native suspension`() = runBlocking {
        try {
            withNativeSDKCapture(listOf("steps", "heart_rate_avg")) { f, context, client, manager ->
                var reads = 0
                val values = mockk<AggregationResult>(); every { values[StepsRecord.COUNT_TOTAL] } returns 123L
                coEvery { client.aggregate(any()) } coAnswers { reads++; yield(); f.peerContext.trusted = false; values }
                try { manager.captureAgentBridgeDay("2026-03-08", context) }
                finally { assertThat(reads).isEqualTo(1) }
            }
            throw AssertionError("Cannot return SDK value after revocation")
        } catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.PERMISSION_REQUIRED) }
    }

    @Test fun `native capture context owns one claim and escaped context expires`() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            val planner = ownedPlanner(f, lifecycle, channel); val request = nativeCaptureRequest(f, planner)
            val unsupported = ownedPlanner(f, lifecycle, channel, AgentBridgeNegotiation.negotiate(AgentBridgePlatform.ANDROID, listOf(2), listOf(2, 4)))
            val revision = f.store.access { it!!.state.revision }; val checks = f.peerContext.checks
            try { unsupported.withCaptureContext(request) { error("Must not call unsupported callback") }; throw AssertionError("Expected unsupported") }
            catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) }
            assertThat(f.peerContext.checks).isEqualTo(checks)
            assertThat(f.store.access { it!!.state.revision }).isEqualTo(revision)
            var escaped: AgentBridgeNativeCaptureContext? = null
            val result = planner.withCaptureContext(request) { context ->
                escaped = context
                assertThat(context.begin().selection.map { it.semanticId }).isEqualTo((request.plan as AgentBridgeGeneratedPlan).resolvedMetricIds)
                context.configurationForRead()
                "synthetic capture callback"
            }
            assertThat(result).isEqualTo("synthetic capture callback")
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { escaped!!.configurationForRead() }
            try { planner.withCaptureContext(request) { error("No second callback") }; throw AssertionError("Expected existing job") }
            catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.BUSY) }
            assertThat(f.store.access { it!!.state.acceptedJobs!!.size }).isEqualTo(1)
            assertThat(f.store.access { it!!.state.captureClaims!!.size }).isEqualTo(1)
        }
    }

    @Test fun `native capture context cannot begin twice or revive stopped owner`() = runBlocking {
        for (stop in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val planner = ownedPlanner(f, lifecycle, mockk<DirectSecureChannel>(relaxed = true)); val request = nativeCaptureRequest(f, planner)
            try {
                planner.withCaptureContext(request) { context ->
                    context.begin()
                    if (stop) lifecycle.stop() else f.expect(AgentBridgeErrorCode.BUSY) { context.begin() }
                    f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { context.configurationForRead() }
                    false
                }
                throw AssertionError("Cannot return from closed context")
            } catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.PERMISSION_REQUIRED) }
            assertThat(f.store.access { it!!.state.captureClaims!!.size }).isEqualTo(1)
        }
    }

    @Test fun `native capture context rejects configuration when read reentrantly closes context`() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val planner = ownedPlanner(f, lifecycle, mockk<DirectSecureChannel>(relaxed = true)); val request = nativeCaptureRequest(f, planner)
            var attempted = false
            var rejectedDuplicate = false
            try {
                planner.withCaptureContext(request) { context ->
                    context.begin()
                    f.peerContext.onCheck = {
                        if (!attempted) {
                            attempted = true
                            try { context.begin() }
                            catch (e: AgentBridgeException) { rejectedDuplicate = e.code == AgentBridgeErrorCode.BUSY }
                        }
                    }
                    f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { context.configurationForRead() }
                    false
                }
                throw AssertionError("Cannot return from reentrantly closed context")
            } catch (e: AgentBridgeException) { assertThat(e.code).isEqualTo(AgentBridgeErrorCode.PERMISSION_REQUIRED) }
            assertThat(attempted).isTrue()
            assertThat(rejectedDuplicate).isTrue()
            assertThat(f.store.access { it!!.state.captureClaims!!.size }).isEqualTo(1)
        }
    }

    @Test fun `native capture context retains original cancelled coroutine across fresh caller`() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val planner = ownedPlanner(f, lifecycle, mockk<DirectSecureChannel>(relaxed = true)); val request = nativeCaptureRequest(f, planner)
            val ready = CompletableDeferred<AgentBridgeNativeCaptureContext>(); val release = CompletableDeferred<Unit>()
            val child = async {
                planner.withCaptureContext(request) { context ->
                    context.begin(); ready.complete(context)
                    withContext(NonCancellable) { release.await() }
                    "ignored cancellation callback"
                }
            }
            try {
                val context = withTimeout(5000) { ready.await() }
                child.cancel()
                try { context.configurationForRead(); throw AssertionError("Original caller cancelled") }
                catch (_: CancellationException) { }
                release.complete(Unit); child.join()
                assertThat(child.isCancelled).isTrue()
                assertThat(f.store.access { it!!.state.captureClaims!!.size }).isEqualTo(1)
            } finally { release.complete(Unit); child.cancelAndJoin() }
        }
    }

    @Test fun `native receive cancellation interrupts a blocked real socket`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            ServerSocket(0, 1, InetAddress.getByName("127.0.0.1")).use { listener ->
                listener.soTimeout = 5_000
                val packet = DirectPacketConnection.connect(requireNotNull(listener.inetAddress.hostAddress), listener.localPort, 5_000)
                try {
                    listener.accept().use { remote ->
                        remote.soTimeout = 2_000
                        // Kotlin internal constructor is reflectively entered only in this test.
                        // Ordinary crypto channel + synthetic native peer, never authentication proof.
                        val channel = DirectSecureChannel::class.java.getDeclaredConstructor(
                            DirectPacketConnection::class.java, ByteArray::class.java, String::class.java,
                            String::class.java, DirectProtocolDeterministicCore::class.java,
                        ).newInstance(packet, ByteArray(32) { 7 }, f.peer.hostInstallationId,
                            "Synthetic", NativeDirectProtocolDeterministicCore)
                        val planner = ownedPlanner(f, lifecycle, channel)
                        val caller = Job()
                        val worker = AtomicReference<Thread>()
                        val executor = Executors.newSingleThreadExecutor { action -> Thread(action, "native-bridge-blocked-read").also(worker::set) }
                        try {
                            val future = executor.submit<ReceivedAgentBridgePayload?> { planner.receiveAndHandleNext(caller) }
                            val deadline = System.nanoTime() + TimeUnit.SECONDS.toNanos(3)
                            var blockedInNativeRead = false
                            while (System.nanoTime() < deadline && !future.isDone) {
                                blockedInNativeRead = worker.get()?.stackTrace?.any {
                                    it.className == "sun.nio.ch.NioSocketImpl" && it.methodName in setOf("read", "timedRead", "park")
                                } == true
                                if (blockedInNativeRead) break
                                Thread.sleep(10)
                            }
                            Assert.assertTrue("Actual socket read must be suspended before cancellation", blockedInNativeRead)
                            caller.cancel()
                            Assert.assertThrows(ExecutionException::class.java) { future.get(2, TimeUnit.SECONDS) }
                            assertThat(remote.getInputStream().read()).isEqualTo(-1)
                            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { planner.requireCurrent() }
                        } finally {
                            caller.cancel(); channel.close(); executor.shutdownNow()
                            Assert.assertTrue("Owned socket worker terminated", executor.awaitTermination(2, TimeUnit.SECONDS))
                        }
                    }
                } finally { packet.close() }
            }
        }
    }

    private fun acceptedStopExecution(f: AgentBridgeExportPlanningFixture): AgentBridgeExecuteRequest {
        val plan = f.service.plan(f.peerContext, f.request(f.enrolled()))
        val approval = f.service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
        val request = AgentBridgeExecuteRequest(approval, AgentBridgeExportPlanningFixture.id(81), AgentBridgeExportPlanningFixture.id(82),
            plan, AgentBridgeExportPlanningFixture.id(83), "healthmd.agent_execute_request", 1)
        f.service.acceptExecution(f.peerContext, request)
        return request
    }
    private fun stopRequest(request: AgentBridgeExecuteRequest): AgentBridgeCancelRequest {
        val plan = request.plan as AgentBridgeGeneratedPlan
        return AgentBridgeCancelRequest(request.approval.approvalId, plan.authorityReferences.native.authorityId,
            request.jobId, plan.intent.peer, AgentBridgeCodec.sha256(AgentBridgeCodec.encode(request)), "healthmd.agent_cancel_request", 1)
    }

    @Test fun `native receive cancels original retained jobs without catalog or read permission and replays exact receipt`() {
        for (captured in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            val request = acceptedStopExecution(f); val stop = stopRequest(request)
            if (captured) {
                val reservation = f.service.claimCapture(f.peerContext, request)
                f.store.openCaptureSpool(reservation, true) { f.service.captureReadConfiguration(f.peerContext, reservation) }.close()
            }
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            every { channel.receiveAllowingAgentBridge(any(), any()) } answers {
                val fence = secondArg<() -> Unit>(); fence()
                val incoming = ReceivedAgentBridgePayload.Agent(AgentBridgeMessage("cancel_request", stop)); fence(); incoming
            }
            val receipts = mutableListOf<AgentBridgeExecutionReceipt>()
            every { channel.sendAgentBridge(any(), any(), any()) } answers {
                val fence = thirdArg<() -> Unit>(); fence()
                assertThat(firstArg<AgentBridgeMessage>().type).isEqualTo("execution_receipt")
                receipts += firstArg<AgentBridgeMessage>().payload as AgentBridgeExecutionReceipt; fence()
            }
            val planner = ownedPlanner(f, lifecycle, channel, beforeNativeRead = { error("Stop must not read configuration") })
            lifecycle.observeNativeChange() // Pending settings metadata is not restored to answer Stop.
            f.configuration.grants = AgentBridgeDiscoveryNativeGrants.REQUIRED
            f.configuration.calls = 0; f.configuration.onRead = { error("Stop must not restore read authority") }; reset()
            val caller = Job()
            try {
                assertThat(planner.receiveAndHandleNext(channel, caller)).isNull()
                val original = Files.readAllBytes(f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))
                assertThat(planner.receiveAndHandleNext(channel, caller)).isNull()
                assertThat(receipts).hasSize(2); assertThat(receipts[1]).isEqualTo(receipts[0])
                assertThat(receipts[0].status).isEqualTo(AgentBridgeExecutionReceiptStatus.CANCELLED)
                assertThat(receipts[0].sourceAcknowledged).isTrue(); assertThat(receipts[0].artifactCount).isEqualTo(0)
                assertThat(receipts[0].requestSha256).isEqualTo(stop.requestSha256)
                assertThat(Files.readAllBytes(f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))).isEqualTo(original)
                verify(exactly = 0) { channel.close() }
                assertThat(f.configuration.calls).isEqualTo(0); assertThat(reads).isEqualTo(0); assertThat(writes).isEqualTo(0)
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { planner.requireCurrent() }
            } finally { caller.complete() }
        }
    }

    @Test fun `native receive cannot acknowledge foreign expired stopped busy or missing retained cancellation`() {
        for (mode in listOf("foreign", "expired", "stopped", "busy", "missing")) AgentBridgeExportPlanningFixture().use { f ->
            val request = acceptedStopExecution(f)
            val stop = stopRequest(request).let { if (mode == "foreign") it.copy(jobId = AgentBridgeExportPlanningFixture.id(99)) else it }
            var held: AgentBridgeNativeCaptureSpool? = null
            if (mode in listOf("busy", "missing")) {
                val reservation = f.service.claimCapture(f.peerContext, request)
                if (mode == "busy") held = f.store.openCaptureSpool(reservation, true) { f.service.captureReadConfiguration(f.peerContext, reservation) }
            }
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            every { channel.receiveAllowingAgentBridge(any(), any()) } answers {
                val fence = secondArg<() -> Unit>(); fence()
                val incoming = ReceivedAgentBridgePayload.Agent(AgentBridgeMessage("cancel_request", stop)); fence(); incoming
            }
            val planner = ownedPlanner(f, lifecycle, channel, beforeNativeRead = { error("Stop must not read configuration") })
            if (mode == "expired") f.clock.now = f.clock.now.plusSeconds(604800)
            if (mode == "stopped") lifecycle.stop()
            val caller = Job()
            try {
                val expected = when (mode) {
                    "foreign" -> AgentBridgeErrorCode.BINDING_CHANGED
                    "expired" -> AgentBridgeErrorCode.PLAN_EXPIRED
                    "stopped" -> AgentBridgeErrorCode.PERMISSION_REQUIRED
                    "busy" -> AgentBridgeErrorCode.BUSY
                    else -> AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED
                }
                f.expect(expected) { planner.receiveAndHandleNext(channel, caller) }
                verify(exactly = 0) { channel.sendAgentBridge(any(), any(), any()) }
                verify(atLeast = 1) { channel.close() }
                assertThat(f.store.access { it!!.state.cancellationIntents.orEmpty().all { row -> row.terminalReceipt() == null } }).isTrue()
            } finally { held?.close(); caller.complete() }
        }
    }

    @Test fun `native cancellation receipt rechecks trust expiry owner and retained files at guarded write and return`() {
        for (afterWrite in listOf(false, true)) for (mode in listOf("trust", "expiry", "owner", "files")) AgentBridgeExportPlanningFixture().use { f ->
            val request = acceptedStopExecution(f); val stop = stopRequest(request)
            val reservation = f.service.claimCapture(f.peerContext, request)
            f.store.openCaptureSpool(reservation, true) { f.service.captureReadConfiguration(f.peerContext, reservation) }.close()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            every { channel.receiveAllowingAgentBridge(any(), any()) } answers {
                val fence = secondArg<() -> Unit>(); fence()
                val incoming = ReceivedAgentBridgePayload.Agent(AgentBridgeMessage("cancel_request", stop)); fence(); incoming
            }
            fun mutate() {
                when (mode) {
                    "trust" -> f.peerContext.trusted = false
                    "expiry" -> f.clock.now = f.clock.now.plusSeconds(604800)
                    "owner" -> lifecycle.stop()
                    else -> Files.write(f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve("captures")
                        .resolve(stop.requestSha256).resolve("header.json"), "changed".toByteArray())
                }
            }
            var emitted = 0
            every { channel.sendAgentBridge(any(), any(), any()) } answers {
                val fence = thirdArg<() -> Unit>()
                if (!afterWrite) mutate()
                fence(); emitted++
                if (afterWrite) mutate()
                fence()
            }
            val planner = ownedPlanner(f, lifecycle, channel, beforeNativeRead = { error("Stop cannot read configuration") })
            val caller = Job()
            try {
                val expected = when (mode) { "expiry" -> AgentBridgeErrorCode.PLAN_EXPIRED; "files" -> AgentBridgeErrorCode.SPOOL_MISSING_RESTART_REQUIRED; else -> AgentBridgeErrorCode.PERMISSION_REQUIRED }
                f.expect(expected) { planner.receiveAndHandleNext(channel, caller) }
                assertThat(emitted).isEqualTo(if (afterWrite) 1 else 0) // An already emitted frame cannot be recalled.
                verify(atLeast = 1) { channel.close() }
            } finally { caller.complete() }
        }
    }

    @Test fun `native receive routes discovery and preserves base and binary payloads`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            val base = ReceivedAgentBridgePayload.Base(V2Codec.decode(V2Codec.encode("ping", JsonObject.serializer(), buildJsonObject {})))
            val binary = ReceivedAgentBridgePayload.Binary("HMDDIRCTsynthetic".toByteArray())
            val incoming = ArrayDeque<ReceivedAgentBridgePayload>(listOf(base,
                ReceivedAgentBridgePayload.Agent(AgentBridgeMessage("discovery_request", f.discoveryRequest())), binary))
            every { channel.receiveAllowingAgentBridge(any(), any()) } answers {
                val fence = secondArg<() -> Unit>(); fence(); val message = incoming.removeFirst(); fence(); message
            }
            var sent: AgentBridgeMessage? = null
            every { channel.sendAgentBridge(any(), any(), any()) } answers {
                val fence = thirdArg<() -> Unit>(); fence(); sent = firstArg(); fence()
            }
            val planner = ownedPlanner(f, lifecycle, channel); val caller = Job()
            val before = f.store.access { it!!.state.revision }; reset()
            assertThat(planner.receiveAndHandleNext(channel, caller)).isSameInstanceAs(base)
            assertThat(planner.receiveAndHandleNext(channel, caller)).isNull()
            assertThat(planner.receiveAndHandleNext(channel, caller)).isSameInstanceAs(binary)
            assertThat((sent!!.payload as AgentBridgeDiscovery).peer).isEqualTo(f.peer)
            assertThat(f.store.access { it!!.state.revision }).isEqualTo(before)
            assertThat(f.store.access { it!!.state.decisions }).isEmpty()
            assertThat(reads).isEqualTo(0); assertThat(writes).isEqualTo(0)
            caller.complete()
        }
    }

    @Test fun `native receive rejects a different channel before reading or authority access`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            val other = mockk<DirectSecureChannel>(relaxed = true)
            val planner = ownedPlanner(f, lifecycle, channel)
            val before = f.store.access { it!!.state.revision }; val checks = f.peerContext.checks
            reset()
            val caller = Job()
            try {
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { planner.receiveAndHandleNext(other, caller) }
                verify { channel wasNot Called; other wasNot Called }
                assertThat(f.peerContext.checks).isEqualTo(checks)
                assertThat(f.store.access { it!!.state.revision }).isEqualTo(before)
                assertThat(reads).isEqualTo(0); assertThat(writes).isEqualTo(0)
            } finally { caller.complete() }
        }
    }

    @Test fun `native receive revoked owner cannot return base or revive`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            var receives = 0
            every { channel.receiveAllowingAgentBridge(any(), any()) } answers {
                val fence = secondArg<() -> Unit>(); fence(); receives++
                lifecycle.stop(); fence()
                ReceivedAgentBridgePayload.Binary(byteArrayOf())
            }
            val planner = ownedPlanner(f, lifecycle, channel)
            repeat(2) { f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { planner.receiveAndHandleNext(Job()) } }
            assertThat(receives).isEqualTo(1)
            verify(atLeast = 1) { channel.close() }
            verify(exactly = 0) { channel.sendAgentBridge(any(), any(), any()) }
        }
    }

    @Test fun `native response uses pinned guarded channel without issuing authority`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            // Transport crypto/framing is covered by real loopback protocol tests; this boundary
            // records the actual signed planner response and invokes its real owner/issuer fences.
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            var sent: AgentBridgeMessage? = null
            every { channel.sendAgentBridge(any(), any(), any()) } answers {
                val fence = thirdArg<() -> Unit>(); fence(); sent = firstArg(); fence()
            }
            val planner = ownedPlanner(f, lifecycle, channel)
            val before = f.store.access { it!!.state.revision }; reset()
            val caller = Job()
            planner.handleAndSend(ownedDiscoveryBytes(f), caller)
            caller.complete()
            assertThat((sent!!.payload as AgentBridgeDiscovery).peer).isEqualTo(f.peer)
            assertThat(f.store.access { it!!.state.revision }).isEqualTo(before)
            assertThat(f.store.access { it!!.state.decisions }).isEmpty()
            assertThat(reads).isEqualTo(0); assertThat(writes).isEqualTo(0)
        }
    }

    @Test fun `native response unsupported negotiation does not touch issuer or channel`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            val negotiation = AgentBridgeNegotiation.negotiate(AgentBridgePlatform.ANDROID, ANDROID_NATIVE_APPLICATION_VERSIONS, listOf(2, 4))
            val planner = ownedPlanner(f, lifecycle, channel, negotiation); val checks = f.peerContext.checks
            f.expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { planner.handleAndSend(byteArrayOf(0), Job()) }
            f.expect(AgentBridgeErrorCode.UNSUPPORTED_CAPABILITY) { planner.receiveAndHandleNext(Job()) }
            assertThat(f.peerContext.checks).isEqualTo(checks)
            verify { channel wasNot Called }
        }
    }

    @Test fun `native response rejects completed publication change before and after write`() {
        for (afterWrite in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state)
            val original = lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            var writes = 0
            every { channel.sendAgentBridge(any(), any(), any()) } answers {
                val fence = thirdArg<() -> Unit>()
                if (afterWrite) { fence(); writes++ }
                lifecycle.recordNativeEvent(); lifecycle.publish(f.store, f.peer.sourceInstallationId)
                fence()
                if (!afterWrite) writes++
            }
            val planner = ownedPlanner(f, lifecycle, channel)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { planner.handleAndSend(ownedDiscoveryBytes(f), Job()) }
            assertThat(lifecycle.currentPublication().revision).isEqualTo(original.revision + 1)
            assertThat(writes).isEqualTo(if (afterWrite) 1 else 0)
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { planner.handleAndSend(ownedDiscoveryBytes(f), Job()) }
            verify(atLeast = 1) { channel.close() }
        }
    }

    @Test fun `native response cancellation in final validator cannot admit write or success`() {
        for (duringWriteFence in listOf(true, false)) {
            var checksToCancellation = 0
            for (cancel in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
                f.enrolled()
                val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
                val channel = mockk<DirectSecureChannel>(relaxed = true)
                val caller = Job()
                var writes = 0
                every { channel.sendAgentBridge(any(), any(), any()) } answers {
                    val before = f.peerContext.checks
                    if (cancel && duringWriteFence) {
                        val target = before + checksToCancellation
                        f.peerContext.onCheck = { if (f.peerContext.checks == target) caller.cancel() }
                    }
                    thirdArg<() -> Unit>()()
                    if (!cancel && duringWriteFence) checksToCancellation = f.peerContext.checks - before
                    writes++
                }
                val planner = ownedPlanner(f, lifecycle, channel)
                val before = f.peerContext.checks
                if (cancel && !duringWriteFence) {
                    val target = before + checksToCancellation
                    f.peerContext.onCheck = { if (f.peerContext.checks == target) caller.cancel() }
                }
                try {
                    planner.handleAndSend(ownedDiscoveryBytes(f), caller)
                    if (cancel) Assert.fail("Canceled final validator cannot admit another write or return success")
                } catch (failure: CancellationException) {
                    if (!cancel) throw failure
                    if (duringWriteFence) assertThat(writes).isEqualTo(0)
                    verify(atLeast = 1) { channel.close() }
                }
                if (!cancel && !duringWriteFence) checksToCancellation = f.peerContext.checks - before
                if (!cancel) { assertThat(checksToCancellation).isGreaterThan(0); caller.complete() }
                else assertThat(caller.isCancelled).isTrue()
            }
        }
    }

    @Test fun `native response rechecks live issuer expiry at actual write`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state); lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val channel = mockk<DirectSecureChannel>(relaxed = true)
            every { channel.sendAgentBridge(any(), any(), any()) } answers {
                f.clock.now = f.clock.now.plusSeconds(600)
                thirdArg<() -> Unit>()()
                Assert.fail("Expired discovery cannot reach native write")
            }
            val planner = ownedPlanner(f, lifecycle, channel)
            f.expect(AgentBridgeErrorCode.PLAN_EXPIRED) { planner.handleAndSend(ownedDiscoveryBytes(f), Job()) }
            verify { channel.close() }
        }
    }

    @Test fun `owned planner retains discovery through plan review and exact approval`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state)
            lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val planner = ownedPlanner(f, lifecycle); val negotiation = nativeNegotiation()
            reset()
            val before = f.store.access { it!!.state.revision }
            val discovery = AgentBridgeCodec.decodeEnvelope(planner.handleEnvelope(ownedDiscoveryBytes(f), negotiation), negotiation).payload as AgentBridgeDiscovery
            assertThat(f.store.access { it!!.state.revision }).isEqualTo(before)
            val bytes = AgentBridgeCodec.encodeEnvelope(AgentBridgeMessage("plan_request", f.request(discovery)), negotiation)
            val plan = AgentBridgeCodec.decodeEnvelope(planner.handleEnvelope(bytes, negotiation), negotiation).payload as AgentBridgeGeneratedPlan
            assertThat(planner.reviewNativePlan(plan.planId)).isEqualTo(plan)
            assertThat(f.store.access { it!!.state.decisions }).isEmpty()
            assertThat(planner.authorizeExactApproval(f.native, plan.planId, AgentBridgeValidation.bindingFor(plan)).binding)
                .isEqualTo(AgentBridgeValidation.bindingFor(plan))
            assertThat(f.store.access { it!!.state.decisions }).hasSize(1)
            assertThat(planner.nativePlansAwaitingReview()).isEmpty()
            assertThat(reads).isEqualTo(0); assertThat(writes).isEqualTo(0)
        }
    }

    @Test fun `native review queue is read only and removes stale plans`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state)
            lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val planner = ownedPlanner(f, lifecycle); val negotiation = nativeNegotiation()
            val discovery = AgentBridgeCodec.decodeEnvelope(planner.handleEnvelope(ownedDiscoveryBytes(f), negotiation), negotiation).payload as AgentBridgeDiscovery
            val bytes = AgentBridgeCodec.encodeEnvelope(AgentBridgeMessage("plan_request", f.request(discovery)), negotiation)
            val plan = AgentBridgeCodec.decodeEnvelope(planner.handleEnvelope(bytes, negotiation), negotiation).payload as AgentBridgeGeneratedPlan
            reset()
            val before = f.store.access { it!!.state.revision }
            assertThat(planner.nativePlansAwaitingReview()).containsExactly(plan)
            assertThat(f.store.access { it!!.state.revision }).isEqualTo(before)
            assertThat(f.store.access { it!!.state.decisions }).isEmpty()
            lifecycle.recordNativeEvent()
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { planner.nativePlansAwaitingReview() }
            lifecycle.publish(f.store, f.peer.sourceInstallationId)
            assertThat(planner.nativePlansAwaitingReview()).isEmpty()
            assertThat(reads).isEqualTo(0); assertThat(writes).isEqualTo(0)
        }
    }

    @Test fun `native review queue rejects storage loss after initial snapshot`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state)
            lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val planner = ownedPlanner(f, lifecycle); val negotiation = nativeNegotiation()
            val discovery = AgentBridgeCodec.decodeEnvelope(planner.handleEnvelope(ownedDiscoveryBytes(f), negotiation), negotiation).payload as AgentBridgeDiscovery
            planner.handleEnvelope(AgentBridgeCodec.encodeEnvelope(AgentBridgeMessage("plan_request", f.request(discovery)), negotiation), negotiation)
            val removeAt = f.peerContext.checks + 3
            var removed = false
            f.peerContext.onCheck = {
                if (f.peerContext.checks == removeAt) {
                    Files.delete(f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))
                    removed = true
                }
            }
            try { planner.nativePlansAwaitingReview(); Assert.fail("Expected verification failure, never an empty verified queue") }
            catch (_: AgentBridgeException) { }
            assertThat(removed).isTrue()
        }
    }

    @Test fun `owned planner rejects pending and stopped identity despite same peer replacement`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { ownedPlanner(f, lifecycle) }
            lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val planner = ownedPlanner(f, lifecycle); val negotiation = nativeNegotiation()
            lifecycle.recordNativeEvent(); reset()
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { planner.handleEnvelope(byteArrayOf(0), negotiation) }
            lifecycle.publish(f.store, f.peer.sourceInstallationId)
            planner.handleEnvelope(ownedDiscoveryBytes(f), negotiation)
            lifecycle.stop()
            val fresh = AgentBridgeNativeCatalogLifecycle(); fresh.observe(state)
            fresh.publish(f.store, f.peer.sourceInstallationId)
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { planner.handleEnvelope(ownedDiscoveryBytes(f), negotiation) }
            ownedPlanner(f, fresh).handleEnvelope(ownedDiscoveryBytes(f), negotiation)
            assertThat(reads).isEqualTo(0); assertThat(writes).isEqualTo(0)
            assertThat(f.store.access { it!!.state.grants }).hasSize(1)
        }
    }

    @Test fun `owned planner rejects native event in final peer return check`() {
        var finalCheck = 0
        for (inject in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state)
            lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val planner = ownedPlanner(f, lifecycle); val negotiation = nativeNegotiation()
            var fired = false
            if (inject) {
                f.peerContext.onCheck = {
                    if (f.peerContext.checks == finalCheck) { fired = true; lifecycle.recordNativeEvent() }
                }
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { planner.handleEnvelope(ownedDiscoveryBytes(f), negotiation) }
                assertThat(fired).isTrue()
            } else {
                planner.handleEnvelope(ownedDiscoveryBytes(f), negotiation)
                finalCheck = f.peerContext.checks
                assertThat(finalCheck).isGreaterThan(0)
            }
            assertThat(f.store.access { it!!.state.plans }).isEmpty()
        }
    }

    @Test fun `owned planner rejects signed store publication outside owner`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state)
            val first = lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val planner = ownedPlanner(f, lifecycle); val negotiation = nativeNegotiation()
            val next = f.store.publishNativeCatalog(f.peer.sourceInstallationId, invalidatingObservedChange = true) { state }
            assertThat(next.factsSha256).isEqualTo(first.factsSha256)
            assertThat(next.revision).isEqualTo(first.revision + 1)
            val result = AgentBridgeCodec.decodeEnvelope(planner.handleEnvelope(ownedDiscoveryBytes(f), negotiation), negotiation).payload
            assertThat(result).isInstanceOf(AgentBridgeError::class.java)
            assertThat((result as AgentBridgeError).code).isEqualTo(AgentBridgeErrorCode.BINDING_CHANGED)
        }
    }

    @Test fun `owned planner rejects completed publication in final peer return check`() {
        var finalCheck = 0
        for (inject in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle(); lifecycle.observe(state)
            val first = lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val planner = ownedPlanner(f, lifecycle); val negotiation = nativeNegotiation()
            var fired = false
            if (inject) {
                f.peerContext.onCheck = {
                    if (f.peerContext.checks == finalCheck) {
                        fired = true; lifecycle.recordNativeEvent()
                        lifecycle.publish(f.store, f.peer.sourceInstallationId)
                    }
                }
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { planner.handleEnvelope(ownedDiscoveryBytes(f), negotiation) }
                assertThat(fired).isTrue()
                assertThat(lifecycle.currentPublication().revision).isEqualTo(first.revision + 1)
            } else {
                planner.handleEnvelope(ownedDiscoveryBytes(f), negotiation); finalCheck = f.peerContext.checks
                assertThat(finalCheck).isGreaterThan(0)
            }
            assertThat(f.store.access { it!!.state.plans }).isEmpty()
            assertThat(f.store.access { it!!.state.decisions }).isEmpty()
        }
    }

    @Test fun `production catalog reuse retains live return fence and publication identity`() {
        var facts = state; var samples = 0; var revokeAtReturn = false
        val reader = AgentBridgeNativeConfigurationReader(observed, settings, profiles, {
            samples++
            if (revokeAtReturn && samples % 2 == 0) facts = facts.copy(nativeGrants = AgentBridgeDiscoveryNativeGrants.REQUIRED)
            facts
        }, compiledCatalog = AgentBridgeNativeCompiledCatalog { AgentBridgeExportTestRegistry.load() })
        fun publication(revision: Int) = AgentBridgeNativeCatalogPublication(revision, AgentBridgeExportPlanningFixture.id(1),
            facts.fingerprint(AgentBridgeExportPlanningFixture.id(1)))
        val first = publication(1)
        reset()
        val initial = reader.readConfiguration(null, first)
        reader.readConfiguration(null, first)
        assertThat(samples).isEqualTo(4)
        revokeAtReturn = true
        try { reader.readConfiguration(null, first); throw AssertionError("Cached mapping cannot bypass final native fact revocation") }
        catch (failure: AgentBridgeException) { assertThat(failure.code).isEqualTo(AgentBridgeErrorCode.BINDING_CHANGED) }
        revokeAtReturn = false
        val next = publication(2)
        val current = reader.readConfiguration(null, next)
        assertThat(current.nativeGrants).isEqualTo(AgentBridgeDiscoveryNativeGrants.REQUIRED)
        assertThat(current.settings.catalog.revision).isEqualTo(2)
        assertThat(current.settings.catalog.configurationSha256).isNotEqualTo(initial.settings.catalog.configurationSha256)
        try { reader.readConfiguration(null, first); throw AssertionError("Stale publication must reject") }
        catch (failure: AgentBridgeException) { assertThat(failure.code).isEqualTo(AgentBridgeErrorCode.BINDING_CHANGED) }
        assertThat(reads).isEqualTo(0); assertThat(writes).isEqualTo(0)
    }

    @Test fun `discovery and explicit never read private preferences`() {
        val reader = reader()
        for (policy in listOf(null, AgentBridgeSettingsPolicyExplicit(AgentBridgeExportPlanningFixture.output(), "explicit"))) {
            val configuration = reader.readPublishedConfiguration(policy)
            assertThat(configuration.settings.savedDevice).isNull()
            assertThat(configuration.settings.profiles).isEmpty()
        }
        assertThat(reads).isEqualTo(0); assertThat(writes).isEqualTo(0)
    }

    @Test fun `actual saved and nonactive profile policies reach real planner and native review without mutation`() = runBlocking {
        AgentBridgeExportPlanningFixture().use { f ->
            val native = AgentBridgeRequestSettingsResolver.resolve(f.intent(), f.configuration.readConfiguration(f.intent().settingsPolicy).settings, f.clock)
                .exporterSettings().copy(apiEndpointUrl = "https://synthetic.invalid/never-contact", scheduleEnabled = true,
                    exportTarget = ExportTarget.API_ENDPOINT, scheduledExportTarget = ExportTarget.API_ENDPOINT)
            settings.updateExportSettings(native)
            val snapshot = AndroidExportSettingsSnapshotCodec.encodeCanonical(AndroidExportSettingsSnapshot.capture(native, null, ZoneId.of("UTC")))
            val selected = profiles.add("Selected", snapshot, ExportTarget.API_ENDPOINT)
            val other = profiles.add("Active", snapshot, ExportTarget.DEVICE_FOLDER)
            profiles.activate(other.id)
            val before = backing.data.first().asMap()
            f.enrolled()
            f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            val service = AgentBridgeExportPlanningService(f.store, reader(), f.clock)
            val discovery = service.discover(f.peerContext, f.discoveryRequest())
            val policies = listOf(AgentBridgeSettingsPolicyExplicit(AgentBridgeExportPlanningFixture.output(), "explicit"),
                AgentBridgeSettingsPolicySavedDeviceSettings(2, "saved_device_settings"), AgentBridgeSettingsPolicyProfile(1, selected.id, "profile"))
            for ((index, policy) in policies.withIndex()) {
                reset()
                val configuration = reader().readPublishedConfiguration(policy)
                assertThat(reads).isEqualTo(if (index == 0) 0 else 1)
                val actual = configuration.settings.savedDevice?.settings ?: configuration.settings.profiles.singleOrNull()?.snapshot?.settings
                if (actual != null) {
                    assertThat(actual.apiEndpointUrl).isEmpty()
                    assertThat(actual.scheduleEnabled).isFalse()
                    assertThat(actual.exportTarget).isEqualTo(ExportTarget.DEVICE_FOLDER)
                }
                val plan = service.plan(f.peerContext, f.request(discovery, f.intent(policy = policy), AgentBridgeExportPlanningFixture.id(70 + index)))
                assertThat(plan.effectiveSettings).isEqualTo(AgentBridgeExportPlanningFixture.output())
                assertThat(service.reviewNativePlan(f.peerContext, plan.planId)).isEqualTo(plan)
                assertThat(writes).isEqualTo(0)
            }
            assertThat(backing.data.first().asMap()).isEqualTo(before)
            assertThat(profiles.getActiveProfileId()).isEqualTo(other.id)
        }
    }

    @Test fun `stale malformed and blocked selected state never falls back`() = runBlocking {
        settings.updateExportSettings(ExportSettings())
        val snapshot = AndroidExportSettingsSnapshotCodec.encodeCanonical(AndroidExportSettingsSnapshot.capture(ExportSettings(), null, ZoneId.of("UTC")))
        val selected = profiles.add("Selected", snapshot, ExportTarget.DEVICE_FOLDER)
        backing.edit { it[SharedSetupV2ProfilePersistence.blockedProfileIdsKey] = setOf(selected.id) }
        val reader = reader()
        assertThat(reader.readPublishedConfiguration(AgentBridgeSettingsPolicyProfile(1, selected.id, "profile")).settings.profiles.single().executionBlocked).isTrue()
        AgentBridgeExportPlanningFixture().use { f ->
            for (policy in listOf(AgentBridgeSettingsPolicySavedDeviceSettings(1, "saved_device_settings"),
                AgentBridgeSettingsPolicyProfile(2, selected.id, "profile"), AgentBridgeSettingsPolicyProfile(1, AgentBridgeExportPlanningFixture.id(99), "profile"))) {
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { reader.readPublishedConfiguration(policy) }
            }
            backing.edit { it[intPreferencesKey("export_profiles")] = 7 }
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { reader.readPublishedConfiguration(AgentBridgeSettingsPolicyProfile(1, selected.id, "profile")) }
        }
    }

    @Test fun `main looper rejects before native state or preferences access`() {
        every { Looper.myLooper() } returns main
        var calls = 0
        val reader = AgentBridgeNativeConfigurationReader(observed, settings, profiles, { calls++; state }, { error("must not load") })
        AgentBridgeExportPlanningFixture().use { f -> f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { reader.readPublishedConfiguration(null) } }
        assertThat(calls).isEqualTo(0); assertThat(reads).isEqualTo(0)
    }

    @Test fun `catalog publication rejects main looper before facts keys or storage access`() {
        every { Looper.myLooper() } returns main
        var samples = 0
        AgentBridgeExportPlanningFixture().use { f ->
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) {
                f.store.publishNativeCatalog(f.peer.sourceInstallationId) { samples++; state }
            }
            assertThat(samples).isEqualTo(0)
            assertThat(f.keys.calls).isEqualTo(0)
            assertThat(Files.exists(f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME))).isFalse()
        }
    }

    @Test fun `native metadata drift and mutable availability aliases invalidate exact read`() = runBlocking {
        settings.updateExportSettings(ExportSettings())
        val available = state.availableNativeMetricIds.toMutableSet()
        state = state.copy(availableNativeMetricIds = available)
        onRead = { available.remove("steps") }
        AgentBridgeExportPlanningFixture().use { f ->
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { reader().readPublishedConfiguration(AgentBridgeSettingsPolicySavedDeviceSettings(2, "saved_device_settings")) }
        }
    }

    @Test fun `storage failures and malformed native timezone return fixed errors`() = runBlocking {
        val unavailable = object : DataStore<Preferences> {
            override val data: Flow<Preferences> = flow { throw IOException("synthetic private path must not escape") }
            override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences = error("must not write")
        }
        AgentBridgeExportPlanningFixture().use { f ->
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { reader(unavailable).readPublishedConfiguration(AgentBridgeSettingsPolicySavedDeviceSettings(2, "saved_device_settings")) }
            settings.updateExportSettings(ExportSettings())
            state = state.copy(sourceCalendarTimezone = "invalid-zone")
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { reader().readPublishedConfiguration(AgentBridgeSettingsPolicySavedDeviceSettings(2, "saved_device_settings")) }
        }
    }

    @Test fun `signed catalog survives restart and unchanged publication while readiness ABA advances revisions`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val legacy = Files.readAllBytes(file)
            val before = f.store.access { requireNotNull(it).state }
            assertThat(before.nativeCatalog).isNull()
            assertThat(Files.readAllBytes(file)).isEqualTo(legacy)
            val first = f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            assertThat(first.revision).isEqualTo(1)
            val bytes = Files.readAllBytes(file)
            val generation = f.store.access { requireNotNull(it).state.revision }
            val restarted = AgentBridgeExportAuthorityStore.inPrivateDirectory(f.parent, f.keys)
            assertThat(restarted.access { requireNotNull(it).state.nativeCatalog }).isEqualTo(first)
            assertThat(restarted.publishNativeCatalog(f.peer.sourceInstallationId) { state }).isEqualTo(first)
            assertThat(restarted.access { requireNotNull(it).state.revision }).isEqualTo(generation)
            assertThat(Files.readAllBytes(file)).isEqualTo(bytes)
            state = state.copy(userStartedServiceActive = false)
            val second = restarted.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            state = state.copy(userStartedServiceActive = true)
            val third = f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            assertThat(listOf(second.revision, third.revision)).containsExactly(2, 3).inOrder()
            assertThat(third.factsSha256).isEqualTo(first.factsSha256)
            val after = restarted.access { requireNotNull(it).state }
            assertThat(after.version).isEqualTo(2)
            assertThat(after.grants).isEqualTo(before.grants)
            assertThat(after.plans).isEmpty(); assertThat(after.decisions).isEmpty()
        }
    }

    @Test fun `wire planning cannot publish missing or stale catalog and readiness ABA invalidates old plans`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(file)
            val service = AgentBridgeExportPlanningService(f.store, reader(), f.clock)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { service.discover(f.peerContext, f.discoveryRequest()) }
            assertThat(Files.readAllBytes(file)).isEqualTo(before)
            f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            val discovery = service.discover(f.peerContext, f.discoveryRequest())
            val plan = service.plan(f.peerContext, f.request(discovery))
            val accepted = Files.readAllBytes(file)
            state = state.copy(userStartedServiceActive = false)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { service.reviewNativePlan(f.peerContext, plan.planId) }
            assertThat(Files.readAllBytes(file)).isEqualTo(accepted)
            f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            state = state.copy(userStartedServiceActive = true)
            f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { service.reviewNativePlan(f.peerContext, plan.planId) }
            f.store.access { tx ->
                assertThat(requireNotNull(tx).state.plans).hasSize(1)
                assertThat(tx.state.decisions).isEmpty()
            }
        }
    }

    @Test fun `native lifecycle rejects pending changes before publication and invalidates old plans`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.enrolled()
            val lifecycle = AgentBridgeNativeCatalogLifecycle()
            lifecycle.observe(state)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentFacts() }
            val liveReader = AgentBridgeNativeConfigurationReader(observed, settings, profiles, lifecycle::currentFacts, { AgentBridgeExportTestRegistry.load() })
            val service = AgentBridgeExportPlanningService(f.store, liveReader, f.clock)
            val first = lifecycle.publish(f.store, f.peer.sourceInstallationId)
            val discovery = service.discover(f.peerContext, f.discoveryRequest())
            val plan = service.plan(f.peerContext, f.request(discovery))
            service.reviewNativePlan(f.peerContext, plan.planId)
            val before = f.store.access { requireNotNull(it).state }
            val pendingFile = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val pendingBytes = Files.readAllBytes(pendingFile)
            lifecycle.observeNativeChange()
            lifecycle.observe(state)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { service.reviewNativePlan(f.peerContext, plan.planId) }
            assertThat(Files.readAllBytes(pendingFile)).isEqualTo(pendingBytes)
            val changed = lifecycle.publish(f.store, f.peer.sourceInstallationId)
            assertThat(changed.factsSha256).isEqualTo(first.factsSha256)
            assertThat(changed.revision).isEqualTo(first.revision + 1)
            val after = f.store.access { requireNotNull(it).state }
            assertThat(after.revision).isEqualTo(before.revision + 1)
            assertThat(after.plans).hasSize(1); assertThat(after.decisions).isEmpty()
            assertThat(after.grants).isEqualTo(before.grants)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { service.reviewNativePlan(f.peerContext, plan.planId) }
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val committed = Files.readAllBytes(file)
            assertThat(lifecycle.currentFacts()).isEqualTo(state)
            assertThat(lifecycle.publish(f.store, f.peer.sourceInstallationId)).isEqualTo(changed)
            val restarted = AgentBridgeExportAuthorityStore.inPrivateDirectory(f.parent, f.keys)
            assertThat(restarted.publishNativeCatalog(f.peer.sourceInstallationId) { state }).isEqualTo(changed)
            assertThat(Files.readAllBytes(file)).isEqualTo(committed)
        }
    }

    @Test fun `native lifecycle does not clear observation racing protected key delay`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val lifecycle = AgentBridgeNativeCatalogLifecycle()
            lifecycle.observe(state)
            val first = lifecycle.publish(f.store, f.peer.sourceInstallationId)
            lifecycle.observeNativeChange()
            var observedChange = false
            f.keys.onEncode = {
                if (!observedChange) { observedChange = true; lifecycle.observeNativeChange() }
            }
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.publish(f.store, f.peer.sourceInstallationId) }
            assertThat(observedChange).isTrue()
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentFacts() }
            f.keys.onEncode = null
            val next = lifecycle.publish(f.store, f.peer.sourceInstallationId)
            assertThat(next.revision).isGreaterThan(first.revision)
            assertThat(lifecycle.currentFacts()).isEqualTo(state)
        }
    }

    @Test fun `native lifecycle detaches metadata and fresh owner invalidates while stopped owner cannot revive`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val metrics = state.availableNativeMetricIds.toMutableSet()
            val lifecycle = AgentBridgeNativeCatalogLifecycle()
            lifecycle.observe(state.copy(availableNativeMetricIds = metrics))
            metrics.clear()
            val first = lifecycle.publish(f.store, f.peer.sourceInstallationId)
            assertThat(lifecycle.currentFacts()).isEqualTo(state)
            (lifecycle.currentFacts().availableNativeMetricIds as MutableSet).clear()
            assertThat(lifecycle.currentFacts()).isEqualTo(state)
            lifecycle.stop()
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { lifecycle.currentFacts() }
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { lifecycle.observe(state) }
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { lifecycle.publish(f.store, f.peer.sourceInstallationId) }
            val nextOwner = AgentBridgeNativeCatalogLifecycle()
            nextOwner.observe(state)
            val next = nextOwner.publish(f.store, f.peer.sourceInstallationId)
            assertThat(next.revision).isEqualTo(first.revision + 1)
            assertThat(next.factsSha256).isEqualTo(first.factsSha256)
            assertThat(nextOwner.publish(f.store, f.peer.sourceInstallationId)).isEqualTo(next)
        }
    }

    @Test fun `publisher never initializes missing state repairs keys or rebinds a source`() {
        AgentBridgeExportPlanningFixture().use { f ->
            var samples = 0
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) {
                f.store.publishNativeCatalog(f.peer.sourceInstallationId) { samples++; state }
            }
            assertThat(samples).isEqualTo(0)
            assertThat(Files.exists(f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME))).isFalse()
            f.enrolled()
            val first = f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(file)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.store.publishNativeCatalog(AgentBridgeExportPlanningFixture.id(99)) { state } }
            val key = f.keys.key
            f.keys.key = null
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { f.store.publishNativeCatalog(f.peer.sourceInstallationId) { samples++; state } }
            assertThat(samples).isEqualTo(0); assertThat(Files.readAllBytes(file)).isEqualTo(before)
            f.keys.key = key
            assertThat(f.store.access { requireNotNull(it).state.nativeCatalog }).isEqualTo(first)
            Files.delete(file)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.store.publishNativeCatalog(f.peer.sourceInstallationId) { samples++; state } }
            assertThat(samples).isEqualTo(0); assertThat(Files.exists(file)).isFalse()
        }
    }

    @Test fun `native facts are rechecked after signing staging and root fsync without rolling publication back`() {
        for (boundary in listOf("signing", "staging", "return")) AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            state = initialState()
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(file)
            var observed = false
            var sampled = false
            // Install the protected-key wrapper before key loading. Arm it only after the first
            // facts sample, so the injected change occurs during publication signing, not reading.
            f.keys.onEncode = {
                if (sampled && !observed && boundary == "signing") {
                    observed = true; state = state.copy(userStartedServiceActive = false)
                }
            }
            // File observations are test-only boundary interception, not production SDK work.
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) {
                f.store.publishNativeCatalog(f.peer.sourceInstallationId) {
                    sampled = true
                    if (!observed && boundary == "staging") Files.newDirectoryStream(file.parent).use { paths ->
                        if (paths.any { it.fileName.toString().startsWith("pending-") }) {
                            observed = true; state = state.copy(userStartedServiceActive = false)
                        }
                    }
                    if (!observed && boundary == "return" && !Files.readAllBytes(file).contentEquals(before)) {
                        observed = true; state = state.copy(userStartedServiceActive = false)
                    }
                    state
                }
            }
            f.keys.onEncode = null
            assertThat(observed).isTrue()
            if (boundary == "return") {
                val retained = f.store.access { requireNotNull(it).state.nativeCatalog }
                assertThat(requireNotNull(retained).factsSha256).isNotEqualTo(state.fingerprint(f.peer.sourceInstallationId))
                assertThat(f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }.revision).isEqualTo(2)
            } else { assertThat(Files.readAllBytes(file)).isEqualTo(before) }
        }
    }

    @Test fun `exhausted catalog accepts exact retry and rejects a changed publication without reset`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val first = f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            // Populate a valid signed boundary fixture through the real internal issuer writer.
            f.store.access { tx ->
                val current = requireNotNull(tx)
                current.state = current.state.copy(nativeCatalog = first.copy(revision = Int.MAX_VALUE))
            }
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(file)
            assertThat(f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }.revision).isEqualTo(Int.MAX_VALUE)
            f.expect(AgentBridgeErrorCode.BUSY) {
                f.store.publishNativeCatalog(f.peer.sourceInstallationId, invalidatingObservedChange = true) { state }
            }
            assertThat(Files.readAllBytes(file)).isEqualTo(before)
            state = state.copy(userStartedServiceActive = false)
            f.expect(AgentBridgeErrorCode.BUSY) { f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state } }
            assertThat(Files.readAllBytes(file)).isEqualTo(before)
        }
    }

    @Test fun `each advertised native fact changes catalog identity without creating authority`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val base = initialState()
            val first = f.store.publishNativeCatalog(f.peer.sourceInstallationId) { base }
            val alternatives = listOf(base.copy(availableNativeMetricIds = setOf("steps")),
                base.copy(nativePermissionObservationSha256 = "a".repeat(64)),
                base.copy(deviceSettingsObjectId = AgentBridgeExportPlanningFixture.id(99)), base.copy(sourceCalendarTimezone = "UTC"),
                base.copy(configurationProtection = AgentBridgeDiscoveryConfigurationProtection.UNLOCKED_NATIVE),
                base.copy(nativeGrants = AgentBridgeDiscoveryNativeGrants.REQUIRED), base.copy(nativeGrants = AgentBridgeDiscoveryNativeGrants.UNVERIFIED),
                base.copy(entitlement = AgentBridgeDiscoveryEntitlement.REQUIRED), base.copy(userStartedServiceActive = false), base.copy(firstUnlockComplete = false))
            var revision = 1
            for (changed in alternatives) {
                val next = f.store.publishNativeCatalog(f.peer.sourceInstallationId) { changed }
                assertThat(next.revision).isEqualTo(++revision)
                assertThat(next.factsSha256).isNotEqualTo(first.factsSha256)
                val restored = f.store.publishNativeCatalog(f.peer.sourceInstallationId) { base }
                assertThat(restored.revision).isEqualTo(++revision)
                assertThat(restored.factsSha256).isEqualTo(first.factsSha256)
            }
            f.store.access { tx ->
                assertThat(requireNotNull(tx).state.grants).isEmpty()
                assertThat(tx.state.plans).isEmpty(); assertThat(tx.state.decisions).isEmpty()
            }
        }
    }

    @Test fun `private catalog version and publication shape must agree even with a valid fixture MAC`() {
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            f.store.publishNativeCatalog(f.peer.sourceInstallationId) { state }
            val valid = f.store.access { requireNotNull(it).state }
            val file = f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME).resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val json = Json { encodeDefaults = true }
            for (dropCatalog in listOf(false, true)) {
                val fixture = if (dropCatalog) valid.copy(nativeCatalog = null) else valid.copy(version = 1)
                val payload = AgentBridgeCodec.canonicalize(json.encodeToString(fixture).toByteArray())
                val signer = Mac.getInstance("HmacSHA256")
                signer.init(requireNotNull(f.keys.key))
                signer.update("HealthMd.AgentBridge.AndroidExportAuthorityStore.v1\u0000".toByteArray())
                val mac = signer.doFinal(payload).joinToString("") { "%02x".format(it) }
                val bytes = AgentBridgeCodec.canonicalize(json.encodeToString(AgentBridgeExportLedgerFile(fixture, mac)).toByteArray())
                Files.write(file, bytes)
                var samples = 0
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { f.store.publishNativeCatalog(f.peer.sourceInstallationId) { samples++; state } }
                assertThat(samples).isEqualTo(0); assertThat(Files.readAllBytes(file)).isEqualTo(bytes)
            }
        }
    }

    private fun initialState() = AgentBridgeNativePlanningFacts(setOf("steps", "avg_hr", "min_hr", "max_hr", "resting_hr", "hrv"),
        AgentBridgeExportPlanningFixture.id(2), "America/Los_Angeles", AgentBridgeDiscoveryConfigurationProtection.LOCKED,
        AgentBridgeDiscoveryNativeGrants.SATISFIED, AgentBridgeDiscoveryEntitlement.SATISFIED, true, true)
}
