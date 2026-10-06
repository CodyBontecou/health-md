package com.healthmd.direct

import android.content.Context
import android.os.Build
import android.os.Process
import android.os.UserManager
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.system.Os
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.*
import com.healthmd.data.scheduler.ScheduledProfileSnapshotFactory
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.direct.protocol.*
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.exportengine.ExportEnginePinPlanner
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.rawexport.RawHealthRepository
import com.healthmd.rawexport.RawHealthRepositoryRegistry
import io.mockk.*
import java.io.DataInputStream
import java.io.DataOutputStream
import java.net.InetAddress
import java.net.ServerSocket
import java.net.Socket
import java.nio.ByteBuffer
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermissions
import java.security.KeyStore
import java.security.Provider
import java.util.Base64
import java.util.concurrent.CompletableFuture
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import javax.crypto.Cipher
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlinx.coroutines.*
import kotlinx.serialization.json.*
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Real reconnect, encrypted base2 admission, coordinator owner, native reader/private files/JCA.
 * SDK Context/UserManager/key/UID/GID/provider facts only are intercepted. Service entry bodies are
 * compiled-only; successful foreground admission/explicit CONNECT/stop are represented through
 * the SAME production non-wire lifecycle-event seam, never a raw active Boolean or Service launch. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AgentBridgeExportNativeSessionTest {
    @Test
    fun actualOwningReconnectBaseHelloAndExplicitServingEpochCaptureNativePeer() = withSession { f ->
        f.start()
        val before = f.inventory()
        val peer = f.coordinator.agentBridgeExportNativeSession(f.context)
        assertThat(peer.requireCurrent()).isEqualTo(AgentBridgePeer(HOST, AgentBridgePlatform.ANDROID, SOURCE))
        assertThat(f.inventory()).isEqualTo(before)
        assertThat(peer.toString()).isEqualTo("AgentBridgeExportNativeSession(redacted)")
        assertThat(peer).isNotInstanceOf(java.io.Serializable::class.java)
        f.assertNoEffects()
    }

    @Test
    fun repeatedLazyGetterCannotRenewOriginalSnapshotOrRevokedCopies() = withSession { f ->
        f.start()
        val peer = f.coordinator.agentBridgeExportNativeSession(f.context)
        val copy = peer.copy()
        val original = Files.readAllBytes(f.trust)
        f.writeTrust(prefix = " ", nonceByte = 0x12)
        denied { f.coordinator.agentBridgeExportNativeSession(f.context) }
        denied { peer.requireCurrent() }
        Files.write(f.trust, original)
        denied { copy.requireCurrent() }
        denied { f.coordinator.agentBridgeExportNativeSession(f.context) }
        f.assertNoEffects()
    }

    @Test
    fun missingOwnerAndLegacyServeWithoutGenuineEpochRejectBeforePrivateLookup() {
        withSession { f ->
            clearMocks(f.store, answers = false)
            denied { f.coordinator.agentBridgeExportNativeSession(f.context) }
            verify(exactly = 0) { f.store.getKey(any(), any()) }
            f.startLegacyWithoutEpoch()
            clearMocks(f.store, answers = false)
            denied { f.coordinator.agentBridgeExportNativeSession(f.context) }
            verify(exactly = 0) { f.store.getKey(any(), any()) }
            f.assertNoEffects()
        }
    }

    @Test
    fun foregroundAdmissionAloneAndPairNullWakeStopEventsNeverMintServingOwnership() = withSession { f ->
        assertThat(f.lifecycle.beginConnectOperation()).isNull() // No successful foreground admission.
        f.lifecycle.foregroundAdmitted()
        f.lifecycle.revokeOperation() // Pair/null/recreated/wake event branch used by the Service.
        denied { f.coordinator.agentBridgeExportNativeSession(f.context) }
        val epoch = requireNotNull(f.lifecycle.beginConnectOperation())
        epoch.requireCurrent(f.coordinator) // Typed explicit CONNECT, not paired/consent authority.
        f.lifecycle.operationEnded(epoch)
        denied { epoch.requireCurrent(f.coordinator) }
        val next = requireNotNull(f.lifecycle.beginConnectOperation())
        f.lifecycle.operationEnded(epoch) // Late old operation exit cannot revoke a newer epoch.
        next.requireCurrent(f.coordinator)
        f.lifecycle.stopped()
        denied { next.requireCurrent(f.coordinator) }
        assertThat(f.lifecycle.beginConnectOperation()).isNull()
        f.assertNoEffects()
    }

    @Test
    fun actualRoleIdentityBaseTwoUnknownFieldAndTransferAdmissionCannotBeForgedByHello() {
        for (fault in listOf("role", "identity", "base", "unknown", "transfer")) withSession(fault) { f ->
            f.startRejectedHello()
            clearMocks(f.store, answers = false)
            denied { f.coordinator.agentBridgeExportNativeSession(f.context) }
            verify(exactly = 0) { f.store.getKey(any(), any()) }
            f.assertNoEffects()
        }
    }

    @Test
    fun actualPairingOperationWithMatchingHelloStillCannotProduceServingBridgePeer() = withSession("pair") { f ->
        f.startPair()
        clearMocks(f.store, answers = false)
        denied { f.coordinator.agentBridgeExportNativeSession(f.context) }
        verify(exactly = 0) { f.store.getKey(any(), any()) }
        f.assertNoEffects()
    }

    @Test
    fun firstUnlockCredentialContextAndCurrentUserManagerAreMandatoryButLaterLockIsNotBfu() {
        for (gate in listOf("bfu", "device", "manager", "data")) withSession { f ->
            f.start()
            val peer = f.coordinator.agentBridgeExportNativeSession(f.context)
            val copy = peer.copy()
            when (gate) {
                "bfu" -> f.unlocked = false
                "device" -> every { f.context.isDeviceProtectedStorage } returns true
                "manager" -> {
                    val replaced = mockk<UserManager>(); every { replaced.isUserUnlocked } returns true
                    every { f.context.getSystemService(UserManager::class.java) } returns replaced
                }
                else -> every { f.context.dataDir } returns f.parent.toFile()
            }
            denied { peer.requireCurrent() }
            f.unlocked = true
            every { f.context.isDeviceProtectedStorage } returns false
            every { f.context.getSystemService(UserManager::class.java) } returns f.users
            every { f.context.dataDir } returns f.data.toFile()
            denied { copy.requireCurrent() }
        }
        withSession { f ->
            f.start()
            // No KeyguardManager or screen-unlocked callback exists in the adapter.
            every { f.context.getSystemService(android.app.KeyguardManager::class.java) } throws AssertionError("Ordinary screen lock is not BFU")
            val peer = f.coordinator.agentBridgeExportNativeSession(f.context)
            assertThat(peer.requireCurrent().sourceInstallationId).isEqualTo(SOURCE)
            f.assertNoEffects()
        }
    }

    @Test
    fun originalTrustIdsAndCredentialMustMatchActualHandshakeAtFirstLazyCapture() {
        for (mutation in listOf("source", "host", "secret", "absent", "malformed")) withSession { f ->
            f.start()
            when (mutation) {
                "source" -> f.writeTrust(source = HOST)
                "host" -> f.writeTrust(host = SOURCE)
                "secret" -> f.writeTrust(secret = ByteArray(32) { 0x30 })
                "absent" -> Files.delete(f.trust)
                else -> Files.write(f.trust, ByteArray(29))
            }
            val before = f.inventory()
            denied { f.coordinator.agentBridgeExportNativeSession(f.context) }
            assertThat(f.inventory()).isEqualTo(before)
            f.assertNoEffects()
        }
    }

    @Test
    fun heldPeerRetainsOriginalFullRawCiphertextMetadataAndInodesWithoutRenewal() {
        for (mutation in listOf("bytes", "metadata", "inode", "identity-inode", "directory")) withSession { f ->
            f.start()
            val peer = f.coordinator.agentBridgeExportNativeSession(f.context)
            when (mutation) {
                "bytes" -> f.writeTrust(prefix = " ", nonceByte = 0x12)
                "metadata" -> f.writeTrust(displayName = "Synthetic replacement")
                "inode", "identity-inode" -> {
                    val path = if (mutation == "inode") f.trust else f.identity
                    val bytes = Files.readAllBytes(path)
                    Files.move(path, path.resolveSibling("synthetic-old-${path.fileName}"))
                    Files.createFile(path, privateFile); Files.write(path, bytes)
                }
                else -> {
                    val identity = Files.readAllBytes(f.identity); val bytes = Files.readAllBytes(f.trust)
                    Files.move(f.root, f.parent.resolve("synthetic-old-root")); Files.createDirectory(f.root, privateDirectory)
                    Files.createFile(f.identity, privateFile); Files.write(f.identity, identity)
                    Files.createFile(f.trust, privateFile); Files.write(f.trust, bytes)
                }
            }
            assertThat(AgentBridgeExportNativeTrust(f.context).loadExisting()).isNotNull() // Replacement is independently valid.
            val before = f.inventory()
            denied { peer.requireCurrent() }
            denied { f.coordinator.agentBridgeExportNativeSession(f.context) }
            assertThat(f.inventory()).isEqualTo(before)
            f.assertNoEffects()
        }
    }

    @Test
    fun observedServiceOperationExitStopReplacementAndOwnerCancelRevokeCopiesPermanently() {
        for (event in listOf("exit", "stop", "replacement", "cancel", "reset")) withSession { f ->
            f.start()
            val peer = f.coordinator.agentBridgeExportNativeSession(f.context)
            val copy = peer.copy()
            when (event) {
                "exit" -> f.lifecycle.operationEnded(requireNotNull(f.epoch))
                "stop" -> f.lifecycle.stopped() // Same stop/forget/timeout/destroy event seam.
                "replacement" -> f.lifecycle.beginConnectOperation()
                "cancel" -> f.coordinator.cancelActive()
                else -> f.coordinator.resetSession()
            }
            denied { peer.requireCurrent() }; denied { copy.requireCurrent() }
            val restarted = AgentBridgeExportServingLifecycle(f.coordinator)
            restarted.foregroundAdmitted(); requireNotNull(restarted.beginConnectOperation()).requireCurrent(f.coordinator)
            denied { peer.requireCurrent() }; denied { f.coordinator.agentBridgeExportNativeSession(f.context) }
            restarted.stopped()
        }
    }

    @Test
    fun nativeKeyLookupDelayObservesEpochOwnerFirstUnlockContextAndTrustMutation() {
        for (change in listOf("epoch", "owner", "bfu", "context", "trust")) withSession { f ->
            f.start()
            val peer = f.coordinator.agentBridgeExportNativeSession(f.context)
            f.onLookup = {
                f.onLookup = null
                when (change) {
                    "epoch" -> f.lifecycle.stopped()
                    "owner" -> f.coordinator.cancelActive()
                    "bfu" -> f.unlocked = false
                    "context" -> every { f.context.dataDir } returns f.parent.toFile()
                    else -> f.writeTrust(prefix = " ", nonceByte = 0x12)
                }
            }
            denied { peer.requireCurrent() }
            f.unlocked = true
            every { f.context.dataDir } returns f.data.toFile()
            denied { peer.copy().requireCurrent() }
            f.assertNoEffects()
        }
    }

    @Test
    fun sdkAvailabilityDelayCannotReturnAfterOwnerChangeOrPerformPrivateLookupWhenUnsupported() = withSession { f ->
        f.start()
        val peer = f.coordinator.agentBridgeExportNativeSession(f.context)
        clearMocks(f.store, answers = false)
        every { f.users.isUserUnlocked } answers { f.coordinator.cancelActive(); true }
        denied { peer.requireCurrent() }
        verify(exactly = 0) { f.store.getKey(any(), any()) }
        f.assertNoEffects()
    }

    @Test
    fun factoryCaptureBracketsLookupDelayWithoutRepairOrPersistedEffects() = withSession { f ->
        f.start()
        val before = f.inventory()
        f.onLookup = { f.onLookup = null; f.lifecycle.stopped() }
        denied { f.coordinator.agentBridgeExportNativeSession(f.context) }
        assertThat(f.inventory()).isEqualTo(before)
        f.assertNoEffects()
    }

    @Test
    fun validNativePeerStillRequiresIndependentIssuerDelegationAndExactNativeDecision() = withSession { f ->
        f.start()
        val peer = f.coordinator.agentBridgeExportNativeSession(f.context)
        AgentBridgeExportPlanningFixture().use { p ->
            val nativePair = peer.requireCurrent()
            val discoveryRequest = p.discoveryRequest().copy(peer = nativePair)
            val discovery = p.service.discover(peer, discoveryRequest)
            assertThat(discovery.authorityReferences).isEmpty()
            val intent = p.intent().copy(peer = nativePair, destination = p.intent().destination.copy(hostInstallationId = HOST))
            p.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { p.service.plan(peer, p.request(discovery, intent)) }
            p.native.allowed = false
            p.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { p.store.initialize(p.native) }
            p.native.allowed = true
            p.store.initialize(p.native)
            p.store.putDelegation(p.native, p.delegation().copy(peer = nativePair), 0)
            val enrolled = p.service.discover(peer, discoveryRequest)
            val plan = p.service.plan(peer, p.request(enrolled, intent))
            assertThat(plan.sideEffects).isEqualTo(AgentBridgeZeroControlEffects(0, 0, 0, 0, 0, 0, 0, 0))
            p.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { p.service.approval(peer, p.approvalRequest(plan)) }
            p.native.allowed = false
            p.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { p.service.authorizeExactApproval(peer, p.native, plan.planId, AgentBridgeValidation.bindingFor(plan)) }
            p.native.allowed = true
            val approval = p.service.authorizeExactApproval(peer, p.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
            assertThat(p.service.approval(peer, p.approvalRequest(plan))).isEqualTo(approval)
            assertThat(p.configuration.preferenceBytes()).isEqualTo(p.preferencesBefore)
        }
        f.assertNoEffects()
    }

    @Test
    fun postTrustSdkCallbackCannotReturnChangedBackingTrustOrReviveRestoredOriginal() = withSession { f ->
        f.start()
        val peer = f.coordinator.agentBridgeExportNativeSession(f.context)
        val copy = peer.copy()
        var keyLookups = 0
        var lookupsAfterKey = 0
        var removed = false
        val moved = f.root.resolve("synthetic-original-record")
        f.onLookup = { keyLookups++ }
        every { f.context.getSystemService(UserManager::class.java) } answers {
            // Native reader performs two key lookups, then ONE final available() SDK lookup,
            // followed by its original-file rereads. The NEXT SDK lookup belongs to the adapter's
            // post-trust sample; removing here is strictly AFTER that original-record read.
            if (keyLookups == 2 && ++lookupsAfterKey == 2 && !removed) {
                removed = true
                Files.move(f.trust, moved)
            }
            f.users
        }
        val result = runCatching { peer.requireCurrent() }
        assertThat(removed).isTrue() // Distinguish wrong callback/oracle preparation from product red.
        assertThat(f.unlocked).isTrue()
        denied { result.getOrThrow() }
        Files.move(moved, f.trust) // Restore exact ORIGINAL bytes/inode/mtime; not a fresh pairing.
        f.onLookup = null
        every { f.context.getSystemService(UserManager::class.java) } returns f.users
        assertThat(AgentBridgeExportNativeTrust(f.context).loadExisting()).isNotNull()
        denied { copy.requireCurrent() }
        denied { f.coordinator.agentBridgeExportNativeSession(f.context) }
        f.assertNoEffects()
    }

    @Test
    fun oldPeerCannotRebindAutomaticReconnectWithSameEpochIdsAndOriginalNativeRecord() = withSession("reconnect") { f ->
        f.start()
        val peer = f.coordinator.agentBridgeExportNativeSession(f.context)
        val copy = peer.copy()
        val originalPair = peer.requireCurrent()
        val before = f.inventory()
        f.server.dropFirstConnection()
        f.server.reconnected.get(10, TimeUnit.SECONDS)
        f.awaitConnected()
        assertThat(f.coordinator.agentBridgeExportNativeSession(f.context).requireCurrent()).isEqualTo(originalPair)
        denied { peer.requireCurrent() }; denied { copy.requireCurrent() }
        assertThat(f.inventory()).isEqualTo(before)
        f.assertNoEffects()
    }

    @Test
    fun canceledOwningCoroutineCannotUseStillAdmittedForegroundEpoch() = withSession { f ->
        f.start()
        val peer = f.coordinator.agentBridgeExportNativeSession(f.context)
        f.cancelOwningOperation()
        requireNotNull(f.epoch).requireCurrent(f.coordinator) // Isolate job, not an epoch stop event.
        denied { peer.requireCurrent() }
        f.assertNoEffects()
    }

    @Test
    fun externalNativeKeyDelayDuringRealJcaDecryptCannotReturnAfterOwnerRevocation() = withSession { f ->
        var delay: (() -> Unit)? = null
        val nativeKey = object : javax.crypto.SecretKey {
            override fun getAlgorithm() = "AES"
            override fun getFormat() = "RAW"
            override fun getEncoded(): ByteArray {
                val callback = delay
                delay = null
                callback?.invoke()
                return f.key.encoded
            }
        }
        // Synthetic external native key handle; Cipher/bytes/reader are REAL, never mocked.
        every { f.store.getKey("healthmd-direct-cli-trust-v1", null) } returns nativeKey
        f.start()
        val peer = f.coordinator.agentBridgeExportNativeSession(f.context)
        var invoked = false
        delay = { invoked = true; f.lifecycle.stopped() }
        denied { peer.requireCurrent() }
        assertThat(invoked).isTrue()
        denied { peer.copy().requireCurrent() }
        f.assertNoEffects()
    }

    @Test
    @Config(sdk = [28])
    fun minSdkFirstUnlockAndTypedServingEpochCanCaptureWithoutAndroidTwelveKeyInfoApi() = withSession { f ->
        assertThat(Build.VERSION.SDK_INT).isEqualTo(28)
        f.start()
        assertThat(f.coordinator.agentBridgeExportNativeSession(f.context).requireCurrent().hostInstallationId).isEqualTo(HOST)
        f.assertNoEffects()
    }

    private fun withSession(helloFault: String = "none", block: (NativeSessionBoundary) -> Unit) {
        mockkStatic(Process::class); mockkStatic(Os::class)
        mockkStatic(KeyStore::class); mockkStatic(SecretKeyFactory::class)
        try { NativeSessionBoundary(helloFault).use(block) }
        finally {
            unmockkStatic(SecretKeyFactory::class); unmockkStatic(KeyStore::class)
            unmockkStatic(Os::class); unmockkStatic(Process::class)
        }
    }
    private fun denied(block: () -> Any?) {
        val failure = runCatching(block).exceptionOrNull()
        assertThat(failure).isInstanceOf(AgentBridgeException::class.java)
        assertThat((failure as AgentBridgeException).code).isEqualTo(AgentBridgeErrorCode.PERMISSION_REQUIRED)
        assertThat(failure.message).isEqualTo("permission_required")
        assertThat(failure.cause).isNull()
    }

    private class NativeSessionBoundary(helloFault: String) : AutoCloseable {
        val data = Files.createTempDirectory("synthetic-session-", privateDirectory).toRealPath()
        val parent = Files.createDirectory(data.resolve("no_backup"), privateDirectory)
        val root = Files.createDirectory(parent.resolve("direct-cli"), privateDirectory)
        val identity = Files.createFile(root.resolve("installation-id"), privateFile)
        val trust = Files.createFile(root.resolve("trust.enc"), privateFile)
        val context = mockk<Context>()
        val users = mockk<UserManager>()
        val store = mockk<KeyStore>()
        val factory = mockk<SecretKeyFactory>()
        val info = mockk<KeyInfo>()
        val key = SecretKeySpec(ByteArray(32) { 0x37 }, "AES")
        var unlocked = true
        var onLookup: (() -> Unit)? = null
        val health = mockk<HealthRepository>()
        val settings = mockk<SettingsRepository>()
        val entitlements = mockk<EntitlementRepository>()
        val profiles = mockk<ExportProfileRepository>()
        val raw = mockk<RawHealthRepository>()
        private val repositories = RawHealthRepositoryRegistry.healthConnectOnly(raw)
        val server = NativeSessionListener(helloFault)
        val coordinator: DirectCliCoordinator
        val lifecycle: AgentBridgeExportServingLifecycle
        private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        var operation: Job? = null
        var epoch: AgentBridgeExportServingEpoch? = null
        init {
            // ACTUAL sandbox SDK input, not installed platform/KeyStore/lifecycle qualification.
            println("native-session-sdk-input=${Build.VERSION.SDK_INT}|${org.robolectric.RuntimeEnvironment.getAndroidFrameworkJarPath().toUri()}")
            every { Process.myUid() } returns (Files.getAttribute(data, "unix:uid") as Number).toInt()
            every { Os.getgid() } returns (Files.getAttribute(data, "unix:gid") as Number).toInt()
            every { context.dataDir } returns data.toFile()
            // Legacy coordinator construction is authorized only in this fixture setup. The NEW
            // factory/checker never receives permission to call these creating getters.
            every { context.noBackupFilesDir } returns parent.toFile()
            every { context.isDeviceProtectedStorage } returns false
            every { context.getSystemService(UserManager::class.java) } returns users
            every { users.isUserUnlocked } answers { unlocked }
            val provider = object : Provider("AndroidKeyStore", 1.0, "Synthetic SDK facts") {}
            every { KeyStore.getInstance("AndroidKeyStore") } returns store
            every { store.provider } returns provider
            every { store.load(null as KeyStore.LoadStoreParameter?) } just Runs
            every { store.getKey("healthmd-direct-cli-trust-v1", null) } answers { onLookup?.invoke(); key }
            every { SecretKeyFactory.getInstance("AES", "AndroidKeyStore") } returns factory
            every { factory.provider } returns provider
            every { factory.getKeySpec(any(), KeyInfo::class.java) } returns info
            every { info.keystoreAlias } returns "healthmd-direct-cli-trust-v1"
            every { info.origin } returns KeyProperties.ORIGIN_GENERATED
            every { info.keySize } returns 256
            every { info.purposes } returns (KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT)
            every { info.blockModes } returns arrayOf(KeyProperties.BLOCK_MODE_GCM)
            every { info.encryptionPaddings } returns arrayOf(KeyProperties.ENCRYPTION_PADDING_NONE)
            every { info.isTrustedUserPresenceRequired } returns false
            every { info.isUserConfirmationRequired } returns false
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) every { info.remainingUsageCount } returns KeyProperties.UNRESTRICTED_USAGE_COUNT
            coEvery { settings.getConnectedHealthProviderIds() } returns emptySet()
            Files.write(identity, SOURCE.toByteArray())
            writeTrust()
            val legacy = DirectCliTrustStore(context)
            val planner = ExportEnginePinPlanner()
            coordinator = DirectCliCoordinator(legacy, DirectCliJobStore(legacy), DirectRawSnapshotProducer(repositories),
                DirectGeneratedFilesProducer(health, MarkdownExporter(), JsonExporter(), CsvExporter(), ObsidianBasesExporter()),
                repositories, health, settings, entitlements, DistributionPolicy.fdroid(), DistributionDirectRawRequestPolicy(),
                planner, AndroidDirectProtocolAuthority(AndroidDirectProtocolEngineMode.legacy, lazy { error("No JNI context needed") }),
                profiles, ScheduledProfileSnapshotFactory(planner))
            lifecycle = AgentBridgeExportServingLifecycle(coordinator)
            every { context.noBackupFilesDir } throws AssertionError("Creating getter forbidden after setup")
            every { context.filesDir } throws AssertionError("Creating getter forbidden")
            every { context.startService(any()) } throws AssertionError("No service start")
            every { context.startForegroundService(any()) } throws AssertionError("No foreground service start")
            clearMocks(context, answers = false) // Effects counted only AFTER the authorized legacy setup.
        }
        fun start() {
            lifecycle.foregroundAdmitted()
            epoch = lifecycle.beginConnectOperation()
            operation = scope.launch { coordinator.connectAndServe(requireNotNull(epoch)) }
            awaitReady()
        }
        fun startLegacyWithoutEpoch() {
            operation = scope.launch { coordinator.connectAndServe() }
            awaitReady()
        }
        fun startRejectedHello() {
            lifecycle.foregroundAdmitted()
            epoch = lifecycle.beginConnectOperation()
            operation = scope.launch { coordinator.connectAndServe(requireNotNull(epoch)) }
            server.finished.get(10, TimeUnit.SECONDS)
        }
        fun startPair() {
            operation = scope.launch { coordinator.pair("127.0.0.1", server.port, "12345678901234567890") }
            server.ready.get(10, TimeUnit.SECONDS)
            runBlocking { withTimeout(5000) { while (coordinator.state.value !is DirectCliConnectionState.Completed) delay(5) } }
        }
        private fun awaitReady() {
            server.ready.get(10, TimeUnit.SECONDS)
            awaitConnected()
        }
        fun awaitConnected() {
            // State is used ONLY as test synchronization; production factory never accepts labels.
            runBlocking { withTimeout(5000) { while (coordinator.state.value !is DirectCliConnectionState.Connected) delay(5) } }
        }
        fun cancelOwningOperation() { operation?.cancel() }
        fun writeTrust(secret: ByteArray = SECRET, source: String = SOURCE, host: String = HOST, prefix: String = "", nonceByte: Byte = 0x11, displayName: String = "Synthetic CLI") {
            Files.write(identity, source.toByteArray())
            val plaintext = (prefix + "{\"installationId\":\"$host\",\"displayName\":\"$displayName\",\"reconnectSecretBase64\":\"${base(secret)}\",\"host\":\"127.0.0.1\",\"port\":${server.port},\"pairedAt\":\"2026-01-01T00:00:00.123456789Z\"}").toByteArray()
            val nonce = ByteArray(12) { nonceByte }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding").apply { init(Cipher.ENCRYPT_MODE, key, GCMParameterSpec(128, nonce)) }
            Files.write(trust, nonce + cipher.doFinal(plaintext))
        }
        fun inventory() = Files.walk(data).use { paths -> paths.sorted().filter(Files::isRegularFile).toList()
            .associate { data.relativize(it).toString() to Files.readAllBytes(it).toList() } }
        fun assertNoEffects() {
            verify { health wasNot Called; raw wasNot Called; entitlements wasNot Called; profiles wasNot Called }
            coVerify(exactly = 0) { settings.getFreeExportsUsed() }
            verify(exactly = 0) { context.startService(any()); context.startForegroundService(any()); context.noBackupFilesDir; context.filesDir }
        }
        override fun close() {
            lifecycle.stopped(); coordinator.cancelActive(); operation?.cancel(); server.close()
            runBlocking { operation?.join() }; scope.cancel()
            // Delete ONLY these synthetic temp fixtures; no evidence/build/cache cleanup.
            Files.walk(data).use { paths -> paths.sorted(Comparator.reverseOrder()).forEach(Files::delete) }
        }
    }

    private class NativeSessionListener(private val fault: String) : AutoCloseable {
        private val listener = ServerSocket(0, 1, InetAddress.getLoopbackAddress()).apply { soTimeout = 10000 }
        val port get() = listener.localPort
        val ready = CompletableFuture<Unit>()
        val finished = CompletableFuture<Unit>()
        val reconnected = CompletableFuture<Unit>()
        private val released = listOf(CountDownLatch(1), CountDownLatch(1))
        private var socket: Socket? = null
        fun dropFirstConnection() { released[0].countDown() }
        private val thread = Thread {
            try {
                repeat(if (fault == "reconnect") 2 else 1) { connection -> listener.accept().use { accepted ->
                    socket = accepted; accepted.soTimeout = 10000
                    val input = DataInputStream(accepted.getInputStream()); val output = DataOutputStream(accepted.getOutputStream())
                    val request = DirectJson.json.parseToJsonElement(read(input).decodeToString()).jsonObject.getValue("pairingRequest").jsonObject.getValue("_0").jsonObject
                    val source = request.getValue("clientInstallationID").jsonPrimitive.content.lowercase()
                    val pub = unbase(request, "clientPublicKey"); val nonce = unbase(request, "clientNonce")
                    val selector = if (fault == "pair") 3 else 2
                    check(request.getValue("protocolVersion").jsonPrimitive.int == selector)
                    val clientProof = if (selector == 3) DirectCrypto.sharedPairingVerifier("12345678901234567890", source, pub, nonce)
                        else DirectCrypto.trustedClientVerifier(SECRET, source, pub, nonce)
                    check(DirectCrypto.constantTimeEquals(unbase(request, if (selector == 3) "codeVerifier" else "trustedVerifier"), clientProof))
                    val keys = DirectCrypto.ephemeralKeyPair(); val serverNonce = DirectCrypto.randomBytes(32)
                    val session = DirectCrypto.sessionKey(DirectCrypto.sharedSecret(keys.privateKey, pub), nonce, serverNonce)
                    val sealed = DirectCrypto.seal(SECRET, session)
                    val proof = if (selector == 3) DirectCrypto.sharedPairingServerVerifier("12345678901234567890", source, pub, nonce, HOST, keys.publicKey, serverNonce, sealed)
                        else DirectCrypto.trustedServerVerifier(SECRET, source, pub, nonce, HOST, keys.publicKey, serverNonce)
                    write(output, DirectJson.canonicalBytes(buildJsonObject { put("pairingResponse", buildJsonObject { put("_0", buildJsonObject {
                        put("protocolVersion", selector); put("macName", "Synthetic CLI"); put("macInstallationID", HOST.uppercase())
                        put("serverPublicKey", base(keys.publicKey)); put("serverNonce", base(serverNonce)); put("authenticationVerifier", base(proof))
                        put("sealedReconnectSecret", buildJsonObject { put("nonce", base(sealed.nonce)); put("ciphertext", base(sealed.ciphertext)); put("tag", base(sealed.tag)) })
                    }) }) }))
                    val hello = open(read(input), session, 0)
                    val sourceHello = LegacyCodec.parseHello(hello)
                    check(sourceHello.protocolVersions == listOf(2) && sourceHello.platform == "android" && sourceHello.installationId == SOURCE)
                    val helloBytes = LegacyCodec.hello(NegotiationHello(if (fault == "base") listOf(1, 4) else listOf(1, 2),
                        if (fault == "role") "android" else "macos_cli", if (fault == "identity") SOURCE else HOST,
                        emptyList(), true, false, if (fault == "transfer") TransferCapabilities(protocolVersions = listOf(9)) else TransferCapabilities()))
                    val transmitted = if (fault == "unknown") helloBytes.decodeToString().replace("\"platform\":", "\"agentBridge\":true,\"platform\":").toByteArray() else helloBytes
                    write(output, encrypted(0, transmitted, session))
                    val sourceEnvelope = V2Codec.decode(open(read(input), session, 1))
                    check(sourceEnvelope.type == "source_hello")
                    V2Codec.decodePayload(sourceEnvelope, SourceHello.serializer())
                    (if (connection == 0) ready else reconnected).complete(Unit)
                    released[connection].await(30, TimeUnit.SECONDS)
                } }
            } catch (error: Throwable) { ready.completeExceptionally(error); reconnected.completeExceptionally(error) }
            finally { finished.complete(Unit) }
        }.apply { isDaemon = true; name = "synthetic-native-owner"; start() }
        override fun close() { released.forEach { it.countDown() }; socket?.close(); listener.close(); thread.join(5000) }
    }
    companion object {
        const val SOURCE = "00000000-0000-4000-8000-000000000001"
        const val HOST = "00000000-0000-4000-8000-000000000002"
        val SECRET = ByteArray(32) { 0x29 }
        val privateDirectory = PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rwx------"))
        val privateFile = PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------"))
        fun base(b: ByteArray) = Base64.getEncoder().encodeToString(b)
        fun unbase(j: JsonObject, n: String) = Base64.getDecoder().decode(j.getValue(n).jsonPrimitive.content)
        fun read(input: DataInputStream): ByteArray { val n = input.readLong(); require(n in 1..MAXIMUM_PACKET_BYTES); return ByteArray(n.toInt()).also(input::readFully) }
        fun write(output: DataOutputStream, bytes: ByteArray) { output.writeLong(bytes.size.toLong()); output.write(bytes); output.flush() }
        fun open(packet: ByteArray, key: ByteArray, seq: Long): ByteArray {
            val envelope = DirectCrypto.open(LegacyCodec.encryptedFrame(packet), key)
            check(envelope.copyOfRange(0, 8).contentEquals("HMDSC001".toByteArray()) && ByteBuffer.wrap(envelope, 8, 8).long == seq)
            return envelope.copyOfRange(16, envelope.size)
        }
        fun encrypted(seq: Long, bytes: ByteArray, key: ByteArray) = LegacyCodec.encrypted(DirectCrypto.seal(ByteBuffer.allocate(16 + bytes.size)
            .put("HMDSC001".toByteArray()).putLong(seq).put(bytes).array(), key))
    }
}
