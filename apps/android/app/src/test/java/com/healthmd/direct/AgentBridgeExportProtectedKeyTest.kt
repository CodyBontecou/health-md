package com.healthmd.direct

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.Process
import android.os.UserManager
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import android.security.keystore.UserNotAuthenticatedException
import android.system.Os
import com.google.common.truth.Truth.assertThat
import com.healthmd.direct.protocol.AgentBridgeDiscoveryConfigurationProtection
import com.healthmd.direct.protocol.AgentBridgeDiscoveryEntitlement
import com.healthmd.direct.protocol.AgentBridgeDiscoveryNativeGrants
import com.healthmd.direct.protocol.AgentBridgeErrorCode
import com.healthmd.direct.protocol.AgentBridgeValidation
import io.mockk.Runs
import io.mockk.every
import io.mockk.just
import io.mockk.mockk
import io.mockk.mockkStatic
import io.mockk.unmockkStatic
import io.mockk.verify
import java.io.IOException
import java.nio.file.Files
import java.nio.file.Path
import java.nio.file.attribute.PosixFilePermissions
import java.security.Key
import java.security.KeyStore
import java.security.KeyStoreException
import java.security.NoSuchAlgorithmException
import java.security.Provider
import java.security.UnrecoverableKeyException
import java.security.spec.InvalidKeySpecException
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.SecretKeySpec
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Intercepted OS SDK boundaries and synthetic keys only, NEVER an actual Keystore lookup.
 * Store/codec/validators/JCA MAC are real. Native Keystore/SELinux/no-backup protection is NOT RUN. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AgentBridgeExportProtectedKeyTest {
    @Test
    fun existingDedicatedNativeSigningKeyIsRetainedForRealMac() = withNativeKey { os ->
        val loaded = AgentBridgeExportProtectedKey(os.context).loadExisting()
        assertThat(loaded).isSameInstanceAs(os.key)
        val mac = Mac.getInstance("HmacSHA256").apply { init(loaded) }
        assertThat(mac.doFinal("synthetic-integrity".toByteArray()).joinToString("") { "%02x".format(it) })
            .isEqualTo("d83a68adfc74def780e8f3e36594ff82f8ea09d9f5385a2a1f3a5f5f5a9c60fc")
    }

    @Test
    fun foreignOrWrongPurposeMetadataIsNotAnIssuerKey() {
        val invalidMetadata: List<(NativeKeyBoundary) -> Unit> = listOf(
            { every { it.info.keystoreAlias } returns "healthmd-direct-cli-trust-v1" },
            { every { it.info.origin } returns KeyProperties.ORIGIN_IMPORTED },
            { every { it.info.origin } returns KeyProperties.ORIGIN_SECURELY_IMPORTED },
            { every { it.info.origin } returns KeyProperties.ORIGIN_UNKNOWN },
            { every { it.info.keySize } returns 128 },
            { every { it.info.keySize } returns 512 },
            { every { it.info.purposes } returns KeyProperties.PURPOSE_VERIFY },
            { every { it.info.purposes } returns (KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_VERIFY) },
            { every { it.info.purposes } returns (KeyProperties.PURPOSE_SIGN or KeyProperties.PURPOSE_ENCRYPT) },
            { every { it.info.digests } returns arrayOf(KeyProperties.DIGEST_SHA512) },
            { every { it.info.digests } returns emptyArray() },
            { every { it.info.digests } returns arrayOf(KeyProperties.DIGEST_SHA256, KeyProperties.DIGEST_SHA512) },
            { every { it.info.isTrustedUserPresenceRequired } returns true },
            { every { it.info.isUserConfirmationRequired } returns true },
        )
        for (invalid in invalidMetadata) withNativeKey { os ->
            invalid(os)
            assertThat(AgentBridgeExportProtectedKey(os.context).loadExisting()).isNull()
        }
    }

    @Test
    fun firstUnlockAvailabilityIsNotOrdinaryScreenUnlock() = withNativeKey { os ->
        val reader = AgentBridgeExportProtectedKey(os.context)
        every { os.context.getSystemService(KeyguardManager::class.java) } throws AssertionError("Screen lock is not BFU")
        os.firstUnlocked = false
        assertThat(reader.loadExisting()).isNull()
        verify(exactly = 0) { KeyStore.getInstance("AndroidKeyStore") }
        // The keyguard remains unavailable/locked, but the native first-unlock boundary now affirms AFU.
        os.firstUnlocked = true
        assertThat(reader.loadExisting()).isSameInstanceAs(os.key)
        every { os.users.isUserUnlocked } throws IllegalStateException("synthetic-user-state-unavailable")
        assertThat(reader.loadExisting()).isNull()
    }

    @Test
    fun limitedOrExhaustedKeyIsRejectedBeforeRealMacCanConsumeIt() {
        for (remaining in listOf(0, 1, 7, -2)) withNativeKey { os ->
            // Only the external synthetic key boundary is replaced. If real JCA reaches the
            // probe it needs bytes in this JVM; AssertionError escapes the reader's safe catch.
            os.selected = object : SecretKey {
                override fun getAlgorithm() = "HmacSHA256"
                override fun getFormat() = "RAW"
                override fun getEncoded(): ByteArray = throw AssertionError("Limited key must not reach real MAC")
            }
            every { os.info.remainingUsageCount } returns remaining
            assertThat(AgentBridgeExportProtectedKey(os.context).loadExisting()).isNull()
        }
    }

    @Test
    fun noBackupDefaultReaderAuthenticatesRealLedgerAfterSeparateNativeDecision() = withNativeKey { os ->
        AgentBridgeExportPlanningFixture().use { f ->
            withNativeData(os, f.parent) {
                val store = AgentBridgeExportAuthorityStore.forNoBackup(os.context)
                store.initialize(f.native)
                store.putDelegation(f.native, f.delegation(), 0)
                // Fresh default reader/store must authenticate actual persisted canonical bytes.
                val reopened = AgentBridgeExportAuthorityStore.forNoBackup(os.context)
                val service = AgentBridgeExportPlanningService(reopened, f.configuration, f.clock)
                assertThat(service.discover(f.peerContext, f.discoveryRequest()).authorityReferences.single().authorityId)
                    .isEqualTo(f.delegation().authorityId)
                assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
                assertThat(f.keys.calls).isEqualTo(0) // Explicit fixture provider is NOT the production default.
            }
        }
    }

    @Test
    fun missingWrongTypeAndWrongAlgorithmKeysHaveNoFallback() = withNativeKey { os ->
        val reader = AgentBridgeExportProtectedKey(os.context)
        val wrongType = object : Key {
            override fun getAlgorithm() = "HmacSHA256"
            override fun getFormat(): String? = null
            override fun getEncoded(): ByteArray = throw AssertionError("Wrong type must not be exported")
        }
        for (selected in listOf(null, wrongType, SecretKeySpec(ByteArray(32), "AES"),
            SecretKeySpec(ByteArray(32), "HmacSHA512"))) {
            os.selected = selected
            assertThat(reader.loadExisting()).isNull()
        }
        // No lookup of a legacy alias or any metadata/crypto fallback for these rejected keys.
        verify(exactly = 4) { os.store.getKey("healthmd-agent-bridge-native-export-authority-v1", null) }
        verify(exactly = 0) { SecretKeyFactory.getInstance(any<String>(), any<String>()) }
    }

    @Test
    fun nativeSdkStorageAndMetadataFailuresAreFixedPermissionRejections() {
        val failures: List<(NativeKeyBoundary) -> Unit> = listOf(
            { every { it.context.getSystemService(UserManager::class.java) } returns null },
            { every { it.users.isUserUnlocked } throws SecurityException("synthetic-user-access") },
            { every { KeyStore.getInstance("AndroidKeyStore") } throws KeyStoreException("synthetic-store-unavailable") },
            { every { it.store.load(null as KeyStore.LoadStoreParameter?) } throws IOException("synthetic-locked-storage") },
            { every { it.store.getKey(any(), null) } throws UnrecoverableKeyException("synthetic-revocation") },
            { every { SecretKeyFactory.getInstance("HmacSHA256", "AndroidKeyStore") } throws NoSuchAlgorithmException("synthetic-factory") },
            { every { it.factory.getKeySpec(any(), KeyInfo::class.java) } throws InvalidKeySpecException("synthetic-foreign-key") },
            { every { it.factory.getKeySpec(any(), KeyInfo::class.java) } returns SecretKeySpec(ByteArray(32), "HmacSHA256") },
            { every { it.info.keySize } throws IllegalStateException("synthetic-metadata-unavailable") },
            { every { it.info.remainingUsageCount } throws IllegalStateException("synthetic-usage-unavailable") },
        )
        for (failure in failures) withNativeKey { os ->
            failure(os)
            AgentBridgeExportPlanningFixture().use { f ->
                val reader = AgentBridgeExportProtectedKey(os.context)
                assertThat(reader.loadExisting()).isNull()
                val store = AgentBridgeExportAuthorityStore.inPrivateDirectory(f.parent, reader)
                f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { store.initialize(f.native) }
                assertThat(Files.exists(f.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME))).isFalse()
            }
        }
    }

    @Test
    fun sdkOwnedSoftwareBackedKeyHasTheSameIntegrityAvailability() = withNativeKey { os ->
        every { os.info.securityLevel } returns KeyProperties.SECURITY_LEVEL_SOFTWARE
        @Suppress("DEPRECATION")
        every { os.info.isInsideSecureHardware } returns false
        assertThat(AgentBridgeExportProtectedKey(os.context).loadExisting()).isSameInstanceAs(os.key)
    }

    @Test
    @Config(sdk = [28])
    fun api28NativeSoftwareKeyDoesNotInvokeApi31UsageMetadata() = withNativeKey { os ->
        @Suppress("DEPRECATION")
        every { os.info.isInsideSecureHardware } returns false
        // KeyInfo's API31 methods are absent in this SDK, not faked as available/unrestricted.
        assertThat(AgentBridgeExportProtectedKey(os.context).loadExisting()).isSameInstanceAs(os.key)
    }

    @Test
    fun foreignJcaProviderCannotSupplyNativeKeystoreProvenance() {
        val foreign = object : Provider("SyntheticJvmProvider", 1.0, "Synthetic foreign boundary") {}
        for (boundary in listOf("store", "factory")) withNativeKey { os ->
            if (boundary == "store") every { os.store.provider } returns foreign
            else every { os.factory.provider } returns foreign
            assertThat(AgentBridgeExportProtectedKey(os.context).loadExisting()).isNull()
        }
    }

    @Test
    fun currentlyUnusableAuthenticationKeyFailsRealMacWithoutPromptOrRenewal() = withNativeKey { os ->
        val reader = AgentBridgeExportProtectedKey(os.context)
        every { os.info.isUserAuthenticationRequired } returns true
        // Authentication metadata alone neither grants usability nor demands a screen unlock.
        assertThat(reader.loadExisting()).isSameInstanceAs(os.key)
        var attempts = 0
        os.selected = object : SecretKey {
            override fun getAlgorithm() = "HmacSHA256"
            override fun getFormat() = "RAW"
            override fun getEncoded(): ByteArray {
                attempts++ // External synthetic key denies JCA, not a mocked MAC/validator.
                throw UserNotAuthenticatedException("synthetic-auth-unavailable")
            }
        }
        assertThat(reader.loadExisting()).isNull()
        assertThat(reader.loadExisting()).isNull()
        assertThat(attempts).isAtLeast(2)
    }

    @Test
    fun everyLookupObservesRemovalMetadataChangeAndCurrentFirstUnlockAvailability() = withNativeKey { os ->
        val reader = AgentBridgeExportProtectedKey(os.context)
        assertThat(reader.loadExisting()).isSameInstanceAs(os.key)
        os.selected = null
        assertThat(reader.loadExisting()).isNull()
        assertThat(reader.loadExisting()).isNull()
        verify(exactly = 3) { os.store.getKey("healthmd-agent-bridge-native-export-authority-v1", null) }
        os.selected = os.key // Synthetic boundary changes only; reader cannot restore/provision it.
        every { os.info.origin } returns KeyProperties.ORIGIN_IMPORTED
        assertThat(reader.loadExisting()).isNull()
        every { os.info.origin } returns KeyProperties.ORIGIN_GENERATED
        every { os.factory.getKeySpec(any(), KeyInfo::class.java) } answers {
            os.firstUnlocked = false
            os.info
        }
        assertThat(reader.loadExisting()).isNull()
    }

    @Test
    fun noBackupDefaultStoreObservesRevokedAndReplacedKeyWithoutRepairingLedger() = withNativeKey { os ->
        AgentBridgeExportPlanningFixture().use { f ->
            withNativeData(os, f.parent) {
                val store = AgentBridgeExportAuthorityStore.forNoBackup(os.context)
                store.initialize(f.native)
                store.putDelegation(f.native, f.delegation(), 0)
                val service = AgentBridgeExportPlanningService(store, f.configuration, f.clock)
                assertThat(service.discover(f.peerContext, f.discoveryRequest()).authorityReferences).hasSize(1)
                val ledger = f.parent.resolve("no_backup").resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME)
                    .resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
                val before = Files.readAllBytes(ledger)
                os.selected = null
                repeat(2) { f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { service.discover(f.peerContext, f.discoveryRequest()) } }
                os.selected = SecretKeySpec(ByteArray(32) { 0x49 }, "HmacSHA256")
                f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { service.discover(f.peerContext, f.discoveryRequest()) }
                assertThat(Files.readAllBytes(ledger)).isEqualTo(before)
                assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
            }
        }
    }

    @Test
    fun nativeDefaultInitializationRejectsMissingBfuAndInvalidKeyBeforeCreatingLeaf() {
        for (state in listOf("missing", "bfu", "invalid", "limited")) withNativeKey { os ->
            AgentBridgeExportPlanningFixture().use { f ->
                withNativeData(os, f.parent) {
                    when (state) {
                        "missing" -> os.selected = null
                        "bfu" -> os.firstUnlocked = false
                        "invalid" -> every { os.info.purposes } returns KeyProperties.PURPOSE_VERIFY
                        "limited" -> every { os.info.remainingUsageCount } returns 1
                    }
                    val store = AgentBridgeExportAuthorityStore.forNoBackup(os.context)
                    // Constructing the default reader/factory itself does not touch credentials.
                    verify(exactly = 0) { KeyStore.getInstance("AndroidKeyStore") }
                    repeat(2) { f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { store.initialize(f.native) } }
                    assertThat(Files.exists(f.parent.resolve("no_backup").resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME))).isFalse()
                    assertThat(f.keys.calls).isEqualTo(0)
                }
            }
        }
    }

    @Test
    fun integrityKeyCannotGrantDelegationExactConsentHealthEntitlementOrServiceAvailability() = withNativeKey { os ->
        AgentBridgeExportPlanningFixture().use { f ->
            withNativeData(os, f.parent) {
                val reader = AgentBridgeExportProtectedKey(os.context)
                val store = AgentBridgeExportAuthorityStore.forNoBackup(os.context)
                val leaf = f.parent.resolve("no_backup").resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME)
                assertThat(reader.loadExisting()).isSameInstanceAs(os.key)
                f.native.allowed = false
                f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { store.initialize(f.native) }
                assertThat(Files.exists(leaf)).isFalse()
                f.native.allowed = true
                store.initialize(f.native)
                val service = AgentBridgeExportPlanningService(store, f.configuration, f.clock)
                val empty = service.discover(f.peerContext, f.discoveryRequest())
                assertThat(empty.authorityReferences).isEmpty()
                f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { service.plan(f.peerContext, f.request(empty)) }
                store.putDelegation(f.native, f.delegation(), 0)
                val ledger = leaf.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
                for ((index, gate) in listOf("health", "entitlement", "service", "first-unlock").withIndex()) {
                    f.configuration.grants = if (gate == "health") AgentBridgeDiscoveryNativeGrants.REQUIRED else AgentBridgeDiscoveryNativeGrants.SATISFIED
                    f.configuration.entitlement = if (gate == "entitlement") AgentBridgeDiscoveryEntitlement.REQUIRED else AgentBridgeDiscoveryEntitlement.SATISFIED
                    f.configuration.active = gate != "service"
                    f.configuration.unlocked = gate != "first-unlock"
                    val discovery = service.discover(f.peerContext, f.discoveryRequest())
                    assertThat(discovery.configurationProtection).isEqualTo(AgentBridgeDiscoveryConfigurationProtection.LOCKED)
                    val request = f.request(discovery, requestId = AgentBridgeExportPlanningFixture.id(40 + index))
                    if (gate == "health" || gate == "entitlement") {
                        // Configuration-only planning may disclose required actions. It does NOT
                        // satisfy them or permit the separate native exact-approval operation.
                        val blockedPlan = service.plan(f.peerContext, request)
                        assertThat(blockedPlan.requiredActions).contains(if (gate == "health") "grant_health_access" else "purchase_required")
                        val afterPlan = Files.readAllBytes(ledger)
                        f.expect(if (gate == "entitlement") AgentBridgeErrorCode.ENTITLEMENT_REQUIRED else AgentBridgeErrorCode.PERMISSION_REQUIRED) {
                            service.authorizeExactApproval(f.peerContext, f.native, blockedPlan.planId, AgentBridgeValidation.bindingFor(blockedPlan))
                        }
                        assertThat(Files.readAllBytes(ledger)).isEqualTo(afterPlan)
                    } else {
                        val beforeBlockedPlan = Files.readAllBytes(ledger)
                        f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { service.plan(f.peerContext, request) }
                        assertThat(Files.readAllBytes(ledger)).isEqualTo(beforeBlockedPlan)
                    }
                }
                f.configuration.unlocked = true
                val plan = service.plan(f.peerContext, f.request(service.discover(f.peerContext, f.discoveryRequest())))
                f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { service.approval(f.peerContext, f.approvalRequest(plan)) }
                f.native.allowed = false
                f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) {
                    service.authorizeExactApproval(f.peerContext, f.native, plan.planId, AgentBridgeValidation.bindingFor(plan))
                }
                assertThat(f.native.decisions).hasSize(2) // Separate initialize + delegation, no exact decision.
                assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
            }
        }
    }

    @Test
    fun deviceProtectedContextCannotAccessCredentialProtectedIssuerKey() = withNativeKey { os ->
        every { os.context.isDeviceProtectedStorage } returns true
        assertThat(AgentBridgeExportProtectedKey(os.context).loadExisting()).isNull()
        verify(exactly = 0) { os.context.getSystemService(UserManager::class.java) }
        verify(exactly = 0) { KeyStore.getInstance("AndroidKeyStore") }
        AgentBridgeExportPlanningFixture().use { f ->
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { AgentBridgeExportAuthorityStore.forNoBackup(os.context) }
        }
    }

    private fun withNativeData(os: NativeKeyBoundary, data: Path, block: () -> Unit) {
        Files.createDirectory(data.resolve("no_backup"),
            PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rwx------")))
        mockkStatic(Process::class)
        mockkStatic(Os::class)
        try {
            every { Process.myUid() } returns (Files.getAttribute(data, "unix:uid") as Number).toInt()
            every { Os.getgid() } returns (Files.getAttribute(data, "unix:gid") as Number).toInt()
            every { os.context.dataDir } returns data.toFile()
            every { os.context.noBackupFilesDir } throws AssertionError("Creating getter is forbidden")
            every { os.context.filesDir } throws AssertionError("Creating getter is forbidden")
            block()
        } finally { unmockkStatic(Os::class); unmockkStatic(Process::class) }
    }

    private fun withNativeKey(block: (NativeKeyBoundary) -> Unit) {
        mockkStatic(KeyStore::class)
        mockkStatic(SecretKeyFactory::class)
        try { block(NativeKeyBoundary()) }
        finally { unmockkStatic(SecretKeyFactory::class); unmockkStatic(KeyStore::class) }
    }

    private class NativeKeyBoundary {
        val context = mockk<Context>()
        val users = mockk<UserManager>()
        val store = mockk<KeyStore>()
        val factory = mockk<SecretKeyFactory>()
        val info = mockk<KeyInfo>()
        val key = SecretKeySpec(ByteArray(32) { 0x37 }, "HmacSHA256")
        var selected: Key? = key
        var firstUnlocked = true
        init {
            val provider = object : Provider("AndroidKeyStore", 1.0, "Synthetic OS boundary only") {}
            every { context.isDeviceProtectedStorage } returns false
            every { context.getSystemService(UserManager::class.java) } returns users
            every { users.isUserUnlocked } answers { firstUnlocked }
            every { KeyStore.getInstance("AndroidKeyStore") } returns store
            every { store.provider } returns provider
            every { store.load(null as KeyStore.LoadStoreParameter?) } just Runs
            every { store.getKey("healthmd-agent-bridge-native-export-authority-v1", null) } answers { selected }
            every { SecretKeyFactory.getInstance("HmacSHA256", "AndroidKeyStore") } returns factory
            every { factory.provider } returns provider
            every { factory.getKeySpec(any(), KeyInfo::class.java) } returns info
            every { info.keystoreAlias } returns "healthmd-agent-bridge-native-export-authority-v1"
            every { info.origin } returns KeyProperties.ORIGIN_GENERATED
            every { info.keySize } returns 256
            every { info.purposes } returns KeyProperties.PURPOSE_SIGN
            every { info.digests } returns arrayOf(KeyProperties.DIGEST_SHA256)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                every { info.securityLevel } returns KeyProperties.SECURITY_LEVEL_TRUSTED_ENVIRONMENT
                every { info.remainingUsageCount } returns KeyProperties.UNRESTRICTED_USAGE_COUNT
            }
            @Suppress("DEPRECATION")
            every { info.isInsideSecureHardware } returns true
            every { info.isTrustedUserPresenceRequired } returns false
            every { info.isUserConfirmationRequired } returns false
        }
    }
}
