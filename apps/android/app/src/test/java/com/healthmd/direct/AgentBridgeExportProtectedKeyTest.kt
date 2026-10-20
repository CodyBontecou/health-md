package com.healthmd.direct

import android.app.KeyguardManager
import android.content.Context
import android.os.Build
import android.os.Process
import android.os.UserManager
import android.security.keystore.KeyGenParameterSpec
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
import java.security.spec.AlgorithmParameterSpec
import javax.crypto.KeyGenerator
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
    fun explicitNativeBootstrapGeneratesFixedKeyAndAuthenticatesEmptyNoBackupLedger() = withNativeKey { os ->
        AgentBridgeExportPlanningFixture().use { f -> withNativeData(os, f.parent) {
            os.selected = null
            val root = f.parent.resolve("no_backup").resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME)
            var reserved = false
            os.beforeGeneration = {
                reserved = Files.isDirectory(root) && !Files.exists(root.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))
            }
            val store = AgentBridgeExportAuthorityStore.initializeNative(os.context, f.native)
            assertThat(reserved).isTrue()
            val spec = requireNotNull(os.generatedSpec)
            assertThat(spec.keystoreAlias).isEqualTo("healthmd-agent-bridge-native-export-authority-v1")
            assertThat(spec.purposes).isEqualTo(KeyProperties.PURPOSE_SIGN)
            assertThat(spec.keySize).isEqualTo(256)
            assertThat(spec.digests.toList()).containsExactly(KeyProperties.DIGEST_SHA256)
            assertThat(spec.isUserAuthenticationRequired).isFalse()
            assertThat(spec.isUnlockedDeviceRequired).isFalse()
            store.access { tx -> assertThat(requireNotNull(tx).state.grants).isEmpty() }
            AgentBridgeExportAuthorityStore.forNoBackup(os.context).access { tx ->
                assertThat(requireNotNull(tx).state.plans).isEmpty()
                assertThat(tx.state.decisions).isEmpty()
            }
            assertThat(f.configuration.preferenceBytes()).isEqualTo(f.preferencesBefore)
            verify(exactly = 1) { os.generator.generateKey() }
        } }
    }

    @Test
    fun deniedAndBeforeFirstUnlockSetupCannotCreateIssuerOrKey() {
        for (mode in listOf("denied", "before-first-unlock")) withNativeKey { os ->
            AgentBridgeExportPlanningFixture().use { f -> withNativeData(os, f.parent) {
                os.selected = null
                if (mode == "denied") f.native.allowed = false else os.firstUnlocked = false
                f.expect(if (mode == "denied") AgentBridgeErrorCode.APPROVAL_REQUIRED else AgentBridgeErrorCode.PERMISSION_REQUIRED) {
                    AgentBridgeExportAuthorityStore.initializeNative(os.context, f.native)
                }
                assertThat(Files.exists(f.parent.resolve("no_backup").resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME))).isFalse()
                verify(exactly = 0) { os.generator.generateKey() }
                verify(exactly = 0) { os.store.getKey(any(), any()) }
            } }
        }
    }

    @Test
    fun nativeBootstrapReusesValidKeyButNeverRepairsMissingKeyForExistingLedger() = withNativeKey { os ->
        AgentBridgeExportPlanningFixture().use { f -> withNativeData(os, f.parent) {
            val store = AgentBridgeExportAuthorityStore.initializeNative(os.context, f.native)
            val ledger = f.parent.resolve("no_backup").resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME)
                .resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME)
            val before = Files.readAllBytes(ledger)
            store.access { tx -> assertThat(requireNotNull(tx).state.grants).isEmpty() }
            os.selected = null
            f.expect(AgentBridgeErrorCode.REVISION_CONFLICT) { AgentBridgeExportAuthorityStore.initializeNative(os.context, f.native) }
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { store.access { } }
            assertThat(Files.readAllBytes(ledger)).isEqualTo(before)
            verify(exactly = 0) { os.generator.generateKey() }
        } }
    }

    @Test
    fun keyGenerationFailureInvalidAliasReadbackAndChangedReservationCannotPublishLedger() {
        for (mode in listOf("invalid-alias", "sdk-denied", "changed-readback", "locked-after-generation", "moved-root")) withNativeKey { os ->
            AgentBridgeExportPlanningFixture().use { f -> withNativeData(os, f.parent) {
                val root = f.parent.resolve("no_backup").resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME)
                os.selected = if (mode == "invalid-alias") SecretKeySpec(ByteArray(16), "AES") else null
                if (mode == "sdk-denied") every { os.generator.generateKey() } throws KeyStoreException("synthetic-generation-denied")
                if (mode == "changed-readback") os.afterGeneration = { os.selected = SecretKeySpec(ByteArray(32) { 0x49 }, "HmacSHA256") }
                if (mode == "locked-after-generation") os.afterGeneration = { os.firstUnlocked = false }
                if (mode == "moved-root") os.beforeGeneration = {
                    Files.move(root, f.parent.resolve("retained"))
                    Files.createDirectory(root, PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rwx------")))
                }
                f.expect(if (mode == "moved-root") AgentBridgeErrorCode.BINDING_CHANGED else AgentBridgeErrorCode.PERMISSION_REQUIRED) {
                    AgentBridgeExportAuthorityStore.initializeNative(os.context, f.native)
                }
                assertThat(Files.exists(root.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))).isFalse()
                f.expect(AgentBridgeErrorCode.REVISION_CONFLICT) { AgentBridgeExportAuthorityStore.initializeNative(os.context, f.native) }
                verify(exactly = if (mode == "invalid-alias") 0 else 1) { os.generator.generateKey() }
            } }
        }
    }

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

    @Test
    fun nativeBootstrapCannotPublishAfterConsentIsLostDuringSdkWorkOrStaging() {
        for (stage in listOf("sdk", "publication")) withNativeKey { os ->
            AgentBridgeExportPlanningFixture().use { f -> withNativeData(os, f.parent) {
                os.selected = null
                val root = f.parent.resolve("no_backup").resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME)
                var revoked = false
                var checks = 0
                var sawStagedFile = false
                val consent = object : AgentBridgeExportNativeAuthorization() {
                    override fun requireDecision(decision: AgentBridgeExportNativeDecision) {
                        assertThat(decision).isEqualTo(AgentBridgeExportNativeDecision.InitializeStore)
                        checks++
                        if (stage == "publication" && checks == 3) {
                            sawStagedFile = Files.newDirectoryStream(root).use { files ->
                                files.any { it.fileName.toString().startsWith("pending-") }
                            }
                            revoked = true
                        }
                        if (revoked) throw com.healthmd.direct.protocol.AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
                    }
                }
                if (stage == "sdk") os.afterGeneration = { revoked = true }
                f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) {
                    AgentBridgeExportAuthorityStore.initializeNative(os.context, consent)
                }
                assertThat(Files.isDirectory(root)).isTrue()
                assertThat(Files.exists(root.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))).isFalse()
                if (stage == "publication") assertThat(sawStagedFile).isTrue()
                f.expect(AgentBridgeErrorCode.REVISION_CONFLICT) {
                    AgentBridgeExportAuthorityStore.initializeNative(os.context, f.native)
                }
                verify(exactly = 1) { os.generator.generateKey() }
            } }
        }
    }

    @Test
    fun nativeBootstrapConsentCallbackCannotDeleteOrPublishReplacementRootFiles() {
        for (checkpoint in listOf(2, 3)) for (deny in listOf(false, true)) withNativeKey { os ->
            AgentBridgeExportPlanningFixture().use { f -> withNativeData(os, f.parent) {
                os.selected = null
                val root = f.parent.resolve("no_backup").resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME)
                val retained = f.parent.resolve("retained")
                val marker = "unrelated replacement file".toByteArray()
                val untouchedTime = java.nio.file.attribute.FileTime.fromMillis(0)
                var replacementFile: Path? = null
                var checks = 0
                val consent = object : AgentBridgeExportNativeAuthorization() {
                    override fun requireDecision(decision: AgentBridgeExportNativeDecision) {
                        assertThat(decision).isEqualTo(AgentBridgeExportNativeDecision.InitializeStore)
                        checks++
                        if (checks == checkpoint) {
                            val temporary = if (checkpoint == 3) Files.newDirectoryStream(root).use { files ->
                                files.single { it.fileName.toString().startsWith("pending-") }.fileName.toString()
                            } else "pending-foreign"
                            Files.move(root, retained)
                            Files.createDirectory(root, PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rwx------")))
                            replacementFile = root.resolve(temporary)
                            Files.write(requireNotNull(replacementFile), marker)
                            if (checkpoint == 2) {
                                Files.setLastModifiedTime(root, untouchedTime)
                                Files.setLastModifiedTime(retained, untouchedTime)
                            }
                            if (deny) throw com.healthmd.direct.protocol.AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
                        }
                    }
                }
                f.expect(if (deny) AgentBridgeErrorCode.APPROVAL_REQUIRED else AgentBridgeErrorCode.BINDING_CHANGED) {
                    AgentBridgeExportAuthorityStore.initializeNative(os.context, consent)
                }
                assertThat(Files.exists(root.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))).isFalse()
                assertThat(Files.exists(retained.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))).isFalse()
                assertThat(Files.readAllBytes(requireNotNull(replacementFile))).isEqualTo(marker)
                if (checkpoint == 2) {
                    // A create+delete still changes mtime; final file absence alone is insufficient.
                    assertThat(Files.getLastModifiedTime(root)).isEqualTo(untouchedTime)
                    assertThat(Files.getLastModifiedTime(retained)).isEqualTo(untouchedTime)
                }
            } }
        }
    }

    @Test
    fun nativeSetupConsentIsScopedAndCannotAuthorizeOtherActions() {
        AgentBridgeExportPlanningFixture().use { f ->
            var escaped: AgentBridgeExportNativeAuthorization? = null
            AgentBridgeExportNativeSetupConsent.withNativeConfirmation(requireCurrentNativePolicy = {}, clockNanos = { 0L }) { consent ->
                escaped = consent
                consent.requireDecision(AgentBridgeExportNativeDecision.InitializeStore)
            }
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { requireNotNull(escaped).requireDecision(AgentBridgeExportNativeDecision.InitializeStore) }
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) {
                AgentBridgeExportNativeSetupConsent.withNativeConfirmation(requireCurrentNativePolicy = {}, clockNanos = { 0L }) { consent ->
                    f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { consent.requireDecision(AgentBridgeExportNativeDecision.Delegation("a".repeat(64), 0)) }
                    f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { consent.requireDecision(AgentBridgeExportNativeDecision.InitializeStore) }
                }
            }
            f.expect(AgentBridgeErrorCode.INVALID_REQUEST) {
                AgentBridgeExportNativeSetupConsent.withNativeConfirmation(requireCurrentNativePolicy = {}, clockNanos = { 0L }) { consent ->
                    escaped = consent
                    throw com.healthmd.direct.protocol.AgentBridgeException(AgentBridgeErrorCode.INVALID_REQUEST)
                }
            }
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { requireNotNull(escaped).requireDecision(AgentBridgeExportNativeDecision.InitializeStore) }
        }
    }

    @Test
    fun nativeSetupConsentObservedPolicyLossAndExpiryNeverRenew() {
        for (expiry in listOf(false, true)) AgentBridgeExportPlanningFixture().use { f ->
            var allowed = true
            var now = 0L
            f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) {
                AgentBridgeExportNativeSetupConsent.withNativeConfirmation(requireCurrentNativePolicy = {
                    if (!allowed) throw com.healthmd.direct.protocol.AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
                }, clockNanos = { now }) { consent ->
                    consent.requireDecision(AgentBridgeExportNativeDecision.InitializeStore)
                    if (expiry) now = 31_000_000_000 else allowed = false
                    f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { consent.requireDecision(AgentBridgeExportNativeDecision.InitializeStore) }
                    now = 0L
                    allowed = true
                    f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { consent.requireDecision(AgentBridgeExportNativeDecision.InitializeStore) }
                }
            }
        }
    }

    @Test
    fun nativeSetupConfirmationCreatesOnlyEmptyLedgerAndRejectsLatePolicyLoss() {
        for (losePolicy in listOf(false, true)) withNativeKey { os ->
            AgentBridgeExportPlanningFixture().use { f -> withNativeData(os, f.parent) {
                os.selected = null
                var allowed = true
                if (losePolicy) os.afterGeneration = { allowed = false }
                val root = f.parent.resolve("no_backup").resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME)
                val operation = {
                    AgentBridgeExportNativeSetupConsent.withNativeConfirmation(requireCurrentNativePolicy = {
                        if (!allowed) throw com.healthmd.direct.protocol.AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
                    }, clockNanos = { 0L }) { consent -> AgentBridgeExportAuthorityStore.initializeNative(os.context, consent) }
                }
                if (losePolicy) {
                    f.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { operation() }
                    assertThat(Files.exists(root.resolve(AgentBridgeExportAuthorityStore.LEDGER_NAME))).isFalse()
                } else operation().access { tx ->
                    assertThat(requireNotNull(tx).state.grants).isEmpty()
                    assertThat(tx.state.plans).isEmpty()
                    assertThat(tx.state.decisions).isEmpty()
                }
            } }
        }
    }

    @Test
    fun nativeSetupCreatesMissingNoBackupOnlyAfterConsentAndNeverRepairsExistingPaths() {
        for (mode in listOf("missing", "denied", "loose", "file", "symlink")) withNativeKey { os ->
            AgentBridgeExportPlanningFixture().use { f -> withNativeData(os, f.parent) {
                os.selected = null
                val parent = f.parent.resolve("no_backup")
                when (mode) {
                    "missing", "denied" -> Files.delete(parent)
                    "loose" -> Files.setPosixFilePermissions(parent, PosixFilePermissions.fromString("rwxrwxrwx"))
                    "file" -> { Files.delete(parent); Files.write(parent, byteArrayOf(7)) }
                    "symlink" -> {
                        Files.delete(parent)
                        val outside = Files.createDirectory(f.parent.resolve("other"))
                        Files.createSymbolicLink(parent, outside)
                    }
                }
                if (mode == "denied") f.native.allowed = false
                if (mode == "missing") {
                    AgentBridgeExportAuthorityStore.initializeNative(os.context, f.native).access { tx ->
                        assertThat(requireNotNull(tx).state.grants).isEmpty()
                    }
                    assertThat(Files.getPosixFilePermissions(parent)).isEqualTo(PosixFilePermissions.fromString("rwx------"))
                    verify(exactly = 1) { os.generator.generateKey() }
                } else {
                    f.expect(if (mode == "denied") AgentBridgeErrorCode.APPROVAL_REQUIRED else AgentBridgeErrorCode.BINDING_CHANGED) {
                        AgentBridgeExportAuthorityStore.initializeNative(os.context, f.native)
                    }
                    if (mode == "denied") assertThat(Files.exists(parent, java.nio.file.LinkOption.NOFOLLOW_LINKS)).isFalse()
                    if (mode == "loose") assertThat(Files.getPosixFilePermissions(parent)).isEqualTo(PosixFilePermissions.fromString("rwxrwxrwx"))
                    if (mode == "file") assertThat(Files.readAllBytes(parent)).isEqualTo(byteArrayOf(7))
                    if (mode == "symlink") assertThat(Files.isSymbolicLink(parent)).isTrue()
                    verify(exactly = 0) { os.generator.generateKey() }
                }
                verify(exactly = 0) { os.context.noBackupFilesDir }
            } }
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
        mockkStatic(KeyGenerator::class)
        try { block(NativeKeyBoundary()) }
        finally { unmockkStatic(KeyGenerator::class); unmockkStatic(SecretKeyFactory::class); unmockkStatic(KeyStore::class) }
    }

    private class NativeKeyBoundary {
        val context = mockk<Context>()
        val users = mockk<UserManager>()
        val store = mockk<KeyStore>()
        val factory = mockk<SecretKeyFactory>()
        val info = mockk<KeyInfo>()
        val generator = mockk<KeyGenerator>()
        var generatedSpec: KeyGenParameterSpec? = null
        var beforeGeneration: () -> Unit = {}
        var afterGeneration: () -> Unit = {}
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
            every { store.containsAlias("healthmd-agent-bridge-native-export-authority-v1") } answers { selected != null }
            every { KeyGenerator.getInstance("HmacSHA256", "AndroidKeyStore") } returns generator
            every { generator.provider } returns provider
            every { generator.init(any<AlgorithmParameterSpec>()) } answers {
                generatedSpec = firstArg<AlgorithmParameterSpec>() as KeyGenParameterSpec
            }
            every { generator.generateKey() } answers {
                beforeGeneration()
                selected = key
                afterGeneration()
                key
            }
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
