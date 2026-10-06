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
import com.healthmd.direct.protocol.AgentBridgeErrorCode
import com.healthmd.direct.protocol.AgentBridgeException
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
import java.security.Provider
import java.security.spec.InvalidKeySpecException
import javax.crypto.Cipher
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory
import javax.crypto.spec.GCMParameterSpec
import javax.crypto.spec.SecretKeySpec
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Synthetic existing native writer bytes and files, actual JCA/JSON, intercepted SDK only.
 * No actual Keystore, writer/store construction, provider, health read or app/service launch. */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AgentBridgeExportNativeTrustTest {
    @Test
    fun existingNativeWriterBytesLoadAndMatchWithoutMutation() = withNativeTrust { f ->
        val before = f.fileBytes()
        val reader = AgentBridgeExportNativeTrust(f.context)
        val loaded = requireNotNull(reader.loadExisting())
        assertThat(loaded.sourceInstallationId).isEqualTo(SOURCE)
        assertThat(loaded.hostInstallationId).isEqualTo(HOST)
        assertThat(loaded.displayName).isEqualTo("Synthetic CLI")
        assertThat(loaded.host).isEqualTo("192.168.1.2")
        assertThat(loaded.port).isEqualTo(17647)
        assertThat(loaded.pairedAt.toString()).isEqualTo("2026-01-01T00:00:00.123456789Z")
        assertThat(loaded.copyReconnectSecret()).isEqualTo(f.secret)
        reader.requireCurrent(loaded, SOURCE, HOST, f.secret)
        assertThat(f.fileBytes()).isEqualTo(before)
    }

    @Test
    fun duplicateDecodedLegacyFieldsRejectWithoutDeletingCiphertext() {
        for (name in listOf("port", "p\\u006frt")) withNativeTrust { f ->
            val payload = f.writerBytes().decodeToString().replace("\"port\":17647", "\"port\":17647,\"$name\":17647")
            f.writePayload(payload.toByteArray())
            val before = f.fileBytes()
            expectCode(AgentBridgeErrorCode.BINDING_CHANGED) { AgentBridgeExportNativeTrust(f.context).loadExisting() }
            assertThat(f.fileBytes()).isEqualTo(before)
        }
    }

    @Test
    fun limitedAndExhaustedPairingKeysRejectBeforeRealDecryption() {
        for (remaining in listOf(0, 1, 7, -2)) withNativeTrust { f ->
            f.selected = object : SecretKey {
                override fun getAlgorithm() = "AES"
                override fun getFormat() = "RAW"
                override fun getEncoded(): ByteArray = throw AssertionError("Limited key must not reach real cipher")
            }
            every { f.info.remainingUsageCount } returns remaining
            val before = f.fileBytes()
            expectCode(AgentBridgeErrorCode.PERMISSION_REQUIRED) { AgentBridgeExportNativeTrust(f.context).loadExisting() }
            assertThat(f.fileBytes()).isEqualTo(before)
        }
    }

    @Test
    fun currentCheckRejectsSameIdsAndSecretWithRawBytesOrInodeReplacement() {
        for (change in listOf("bytes", "inode")) withNativeTrust { f ->
            val reader = AgentBridgeExportNativeTrust(f.context)
            val original = requireNotNull(reader.loadExisting())
            if (change == "bytes") f.writePayload((" " + f.writerBytes().decodeToString()).toByteArray(), nonceByte = 0x12)
            else {
                val bytes = Files.readAllBytes(f.trust)
                Files.move(f.trust, f.root.resolve("synthetic-old-trust"))
                Files.createFile(f.trust, privateFile)
                Files.write(f.trust, bytes)
            }
            // Each new record is independently valid, but cannot renew this original context.
            assertThat(reader.loadExisting()).isNotNull()
            val before = f.fileBytes()
            expectCode(AgentBridgeErrorCode.BINDING_CHANGED) { reader.requireCurrent(original, SOURCE, HOST, f.secret) }
            assertThat(f.fileBytes()).isEqualTo(before)
        }
    }

    @Test
    fun snapshotSecretCopiesAndRedactedTextCannotBecomeWireOrNativeAuthority() = withNativeTrust { f ->
        val original = requireNotNull(AgentBridgeExportNativeTrust(f.context).loadExisting())
        val copy = original.copyReconnectSecret()
        copy.fill(0)
        assertThat(original.copyReconnectSecret()).isEqualTo(f.secret)
        assertThat(original.toString()).isEqualTo("AgentBridgeExportNativeTrust.Snapshot(redacted)")
        for (type in listOf(java.io.Serializable::class.java, AgentBridgeExportAuthenticatedPeer::class.java,
            AgentBridgeExportNativeAuthorization::class.java, AgentBridgeExportProtectedKeyProvider::class.java)) {
            assertThat(type.isInstance(original)).isFalse()
        }
        AgentBridgeExportPlanningFixture().use { p ->
            p.native.allowed = false
            p.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { p.store.initialize(p.native) }
            assertThat(Files.exists(p.parent.resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME))).isFalse()
            p.native.allowed = true
            p.store.initialize(p.native)
            val discovery = p.service.discover(p.peerContext, p.discoveryRequest())
            assertThat(discovery.authorityReferences).isEmpty()
            p.expect(AgentBridgeErrorCode.APPROVAL_REQUIRED) { p.service.plan(p.peerContext, p.request(discovery)) }
            assertThat(p.configuration.preferenceBytes()).isEqualTo(p.preferencesBefore)
        }
    }

    @Test
    fun reorderedLegacyJsonAndWriterUnicodeInstantBytesLoadWithoutRewriting() = withNativeTrust { f ->
        val fields = Json.parseToJsonElement(f.writerBytes().decodeToString()) as JsonObject
        val reordered = JsonObject(fields.entries.reversed().associate { it.key to it.value }).toString()
        f.writePayload(reordered.replace("Synthetic CLI", "Synthetic 🌱 CLI").toByteArray())
        val before = f.fileBytes()
        val loaded = requireNotNull(AgentBridgeExportNativeTrust(f.context).loadExisting())
        assertThat(loaded.displayName).isEqualTo("Synthetic 🌱 CLI")
        assertThat(loaded.pairedAt.nano).isEqualTo(123456789)
        assertThat(f.fileBytes()).isEqualTo(before)
    }

    @Test
    fun closedLegacyFieldsRejectUnknownMissingNullAndScalarCoercions() = withNativeTrust { f ->
        val fields = listOf("installationId", "displayName", "reconnectSecretBase64", "host", "port", "pairedAt")
        for (field in fields) for (raw in listOf(null, "null", "true", "[]", "{}")) {
            f.writePayload(f.payload(field, raw))
            rejectedUnchanged(f)
        }
        for (raw in listOf("\"17647\"", "17647.0", "1.7647e4", "17647.5", "2147483648", "0", "65536", "-1")) {
            f.writePayload(f.payload("port", raw))
            rejectedUnchanged(f)
        }
        for (field in fields.filter { it != "port" }) {
            f.writePayload(f.payload(field, "17647"))
            rejectedUnchanged(f)
        }
        f.writePayload(f.payload("unknown", "true"))
        rejectedUnchanged(f)
    }

    @Test
    fun malformedUtf8AndUnicodeScalarsRejectBeforeLegacyDecode() = withNativeTrust { f ->
        for (replacement in listOf("\\uD800", "\\uDC00", "\\uD800a", "\\uDC00\\uD800")) {
            f.writePayload(f.writerBytes().decodeToString().replace("Synthetic CLI", replacement).toByteArray())
            rejectedUnchanged(f)
        }
        val text = f.writerBytes().decodeToString()
        val prefix = text.substringBefore("Synthetic CLI").toByteArray()
        val suffix = text.substringAfter("Synthetic CLI").toByteArray()
        for (bad in listOf(byteArrayOf(0xc3.toByte(), 0x28), byteArrayOf(0xff.toByte()),
            byteArrayOf(0xed.toByte(), 0xa0.toByte(), 0x80.toByte()))) {
            f.writePayload(prefix + bad + suffix)
            rejectedUnchanged(f)
        }
    }

    @Test
    fun uuidHostSecretAndFiniteInstantValuesAreRequired() = withNativeTrust { f ->
        val controls = listOf(
            "installationId" to "\"0-0-0-0-0\"", "installationId" to "\"00000000-0000-4000-8000-000000ABCDEF\"",
            "installationId" to "\"not-an-identity\"", "displayName" to "\" \"", "host" to "\"\"",
            "host" to "\" 192.168.1.2\"", "host" to "\"192.168.1.2 \"",
            "pairedAt" to "\"NaN\"", "pairedAt" to "\"Infinity\"", "pairedAt" to "\"2026-13-01T00:00:00Z\"",
            "pairedAt" to "\"+1000000001-01-01T00:00:00Z\"", "pairedAt" to "\"\"",
            "reconnectSecretBase64" to "\"${java.util.Base64.getEncoder().encodeToString(ByteArray(31))}\"",
            "reconnectSecretBase64" to "\"${java.util.Base64.getEncoder().encodeToString(ByteArray(33))}\"",
            "reconnectSecretBase64" to "\"${java.util.Base64.getEncoder().withoutPadding().encodeToString(f.secret)}\"",
            "reconnectSecretBase64" to "\"${java.util.Base64.getEncoder().encodeToString(f.secret).dropLast(2)}B=\"",
            "reconnectSecretBase64" to "\"%invalid%\"",
        )
        for ((field, raw) in controls) {
            f.writePayload(f.payload(field, raw))
            rejectedUnchanged(f)
        }
    }

    @Test
    fun identityFileIsAnExactCanonicalUuidAndNeverGeneratedOrTrimmed() = withNativeTrust { f ->
        for (text in listOf("", "0-0-0-0-0", "$SOURCE\n", " $SOURCE", "not-an-identity",
            "00000000-0000-4000-8000-000000ABCDEF")) {
            Files.write(f.identity, text.toByteArray())
            rejectedUnchanged(f)
        }
        // Native writer normalizes UUIDs but does not require UUIDv4 for an existing identity.
        val valid = "00000000-0000-1000-8000-000000000003"
        Files.write(f.identity, valid.toByteArray())
        assertThat(requireNotNull(AgentBridgeExportNativeTrust(f.context).loadExisting()).sourceInstallationId).isEqualTo(valid)
    }

    @Test
    fun nativeFileAndStringBoundsRejectWithoutClippingOrLookup() {
        for (size in listOf(0, 1, 28, 65537)) withNativeTrust { f ->
            Files.write(f.trust, ByteArray(size))
            rejectedUnchanged(f)
            verify(exactly = 0) { f.store.getKey(any(), any()) }
        }
        withNativeTrust { f ->
            f.writePayload(f.payload("displayName", "\"${"a".repeat(4096)}\""))
            assertThat(AgentBridgeExportNativeTrust(f.context).loadExisting()).isNotNull()
            for (field in listOf("displayName", "host")) {
                f.writePayload(f.payload(field, "\"${"a".repeat(4097)}\""))
                rejectedUnchanged(f)
            }
            f.writePayload(f.payload("pairedAt", "\"${"a".repeat(65)}\""))
            rejectedUnchanged(f)
        }
    }

    @Test
    fun nonceCiphertextAndTagMutationsRejectAndRetainSyntheticBytes() {
        for (location in listOf(0, 11, 12, 40, -1)) withNativeTrust { f ->
            val encrypted = Files.readAllBytes(f.trust)
            val index = if (location == -1) encrypted.lastIndex else location
            encrypted[index] = (encrypted[index].toInt() xor 1).toByte()
            Files.write(f.trust, encrypted)
            rejectedUnchanged(f)
        }
    }

    @Test
    fun cleanMissingDirectoriesTrustAndKeyStayAbsentAndPartialIdentityRejects() {
        for (missing in listOf("data", "parent", "root", "trust", "key", "identity")) withNativeTrust { f ->
            when (missing) {
                "data" -> removeTree(f.data)
                "parent" -> removeTree(f.parent)
                "root" -> removeTree(f.root)
                "trust" -> Files.delete(f.trust)
                "key" -> f.selected = null
                "identity" -> Files.delete(f.identity)
            }
            val before = f.inventory()
            val reader = AgentBridgeExportNativeTrust(f.context)
            repeat(2) {
                if (missing == "identity") expectCode(AgentBridgeErrorCode.BINDING_CHANGED) { reader.loadExisting() }
                else assertThat(reader.loadExisting()).isNull()
            }
            assertThat(f.inventory()).isEqualTo(before)
        }
    }

    @Test
    fun firstUnlockAfterRebootIsDistinctFromOrdinaryLaterLock() = withNativeTrust { f ->
        every { f.context.getSystemService(KeyguardManager::class.java) } throws AssertionError("Not a screen unlock check")
        f.firstUnlocked = false
        rejectedUnchanged(f, AgentBridgeErrorCode.PERMISSION_REQUIRED)
        verify(exactly = 0) { KeyStore.getInstance("AndroidKeyStore") }
        f.firstUnlocked = true
        assertThat(AgentBridgeExportNativeTrust(f.context).loadExisting()).isNotNull()
        verify(exactly = 0) { f.context.getSystemService(KeyguardManager::class.java) }
    }

    @Test
    fun deviceProtectedContextRejectsBeforeCredentialProtectedFilesOrKeys() = withNativeTrust { f ->
        every { f.context.isDeviceProtectedStorage } returns true
        rejectedUnchanged(f, AgentBridgeErrorCode.PERMISSION_REQUIRED)
        verify(exactly = 0) { f.context.dataDir }
        verify(exactly = 0) { KeyStore.getInstance("AndroidKeyStore") }
    }

    @Test
    @Config(sdk = [28])
    fun api28ReadsLegacyAesWithoutInvokingAbsentApi31UsageMetadata() = withNativeTrust { f ->
        @Suppress("DEPRECATION")
        every { f.info.isInsideSecureHardware } returns false
        assertThat(AgentBridgeExportNativeTrust(f.context).loadExisting()).isNotNull()
        // API31 getters are actually absent under this SDK, not stubbed as unrestricted.
    }

    @Test
    fun sdkOwnedSoftwareBackedAesDoesNotRequireHardwareOrScreenUnlock() = withNativeTrust { f ->
        every { f.info.securityLevel } returns KeyProperties.SECURITY_LEVEL_SOFTWARE
        @Suppress("DEPRECATION")
        every { f.info.isInsideSecureHardware } returns false
        every { f.info.isUserAuthenticationRequired } returns true
        assertThat(AgentBridgeExportNativeTrust(f.context).loadExisting()).isNotNull()
    }

    @Test
    fun foreignProvidersTypesAlgorithmsAndKeyMetadataAreNotLegacyPairingKeys() {
        val foreign = object : Provider("SyntheticJvmProvider", 1.0, "Synthetic wrong provenance") {}
        val controls: List<(NativeTrustBoundary) -> Unit> = listOf(
            { every { it.store.provider } returns foreign }, { every { it.factory.provider } returns foreign },
            { it.selected = SecretKeySpec(ByteArray(32), "HmacSHA256") },
            { it.selected = object : Key {
                override fun getAlgorithm() = "AES"
                override fun getFormat(): String? = null
                override fun getEncoded(): ByteArray = throw AssertionError("Do not export wrong key type")
            } },
            { every { it.factory.getKeySpec(any(), KeyInfo::class.java) } returns SecretKeySpec(ByteArray(32), "AES") },
            { every { it.info.keystoreAlias } returns "healthmd-agent-bridge-native-export-authority-v1" },
            { every { it.info.origin } returns KeyProperties.ORIGIN_IMPORTED },
            { every { it.info.origin } returns KeyProperties.ORIGIN_UNKNOWN },
            { every { it.info.keySize } returns 128 }, { every { it.info.keySize } returns 512 },
            { every { it.info.purposes } returns KeyProperties.PURPOSE_DECRYPT },
            { every { it.info.purposes } returns KeyProperties.PURPOSE_ENCRYPT },
            { every { it.info.purposes } returns (KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT or KeyProperties.PURPOSE_SIGN) },
            { every { it.info.blockModes } returns emptyArray() }, { every { it.info.blockModes } returns arrayOf("CBC") },
            { every { it.info.blockModes } returns arrayOf("GCM", "CBC") },
            { every { it.info.encryptionPaddings } returns emptyArray() },
            { every { it.info.encryptionPaddings } returns arrayOf("PKCS7Padding") },
            { every { it.info.encryptionPaddings } returns arrayOf("NoPadding", "PKCS7Padding") },
            { every { it.info.isTrustedUserPresenceRequired } returns true },
            { every { it.info.isUserConfirmationRequired } returns true },
        )
        for (control in controls) withNativeTrust { f ->
            control(f)
            rejectedUnchanged(f, AgentBridgeErrorCode.PERMISSION_REQUIRED)
        }
    }

    @Test
    fun nativeAvailabilityMetadataAndCurrentlyInvalidatedKeysFailWithoutPromptOrRenewal() {
        val controls: List<(NativeTrustBoundary) -> Unit> = listOf(
            { every { it.context.getSystemService(UserManager::class.java) } returns null },
            { every { it.users.isUserUnlocked } throws SecurityException("synthetic-unavailable") },
            { every { it.store.load(null as KeyStore.LoadStoreParameter?) } throws IOException("synthetic-locked") },
            { every { it.store.getKey(any(), null) } throws java.security.UnrecoverableKeyException("synthetic-invalidated") },
            { every { it.factory.getKeySpec(any(), KeyInfo::class.java) } throws InvalidKeySpecException("synthetic-foreign") },
            { every { it.info.keySize } throws IllegalStateException("synthetic-metadata") },
            { every { it.info.remainingUsageCount } throws IllegalStateException("synthetic-usage") },
        )
        for (control in controls) withNativeTrust { f ->
            control(f)
            rejectedUnchanged(f, AgentBridgeErrorCode.PERMISSION_REQUIRED)
        }
        withNativeTrust { f ->
            var attempts = 0
            f.selected = object : SecretKey {
                override fun getAlgorithm() = "AES"
                override fun getFormat() = "RAW"
                override fun getEncoded(): ByteArray {
                    attempts++ // External synthetic key denies real JCA; the cipher is not mocked.
                    throw UserNotAuthenticatedException("synthetic-auth-unavailable")
                }
            }
            repeat(2) { rejectedUnchanged(f, AgentBridgeErrorCode.PERMISSION_REQUIRED) }
            assertThat(attempts).isAtLeast(2)
        }
    }

    @Test
    fun currentCheckCopiesCallerCredentialBeforeDelayingSdkBoundaries() = withNativeTrust { f ->
        val reader = AgentBridgeExportNativeTrust(f.context)
        val original = requireNotNull(reader.loadExisting())
        val supplied = f.secret.copyOf()
        every { f.factory.getKeySpec(any(), KeyInfo::class.java) } answers {
            supplied.fill(0)
            f.info
        }
        reader.requireCurrent(original, SOURCE, HOST, supplied)
        assertThat(supplied).isEqualTo(ByteArray(32))
        assertThat(original.copyReconnectSecret()).isEqualTo(f.secret)
    }

    @Test
    fun currentChecksKeepOriginalAuthenticatedIdentitiesEndpointMetadataAndCredential() {
        for (change in listOf("host-id", "source-id", "display", "endpoint", "port", "time", "secret")) withNativeTrust { f ->
            val reader = AgentBridgeExportNativeTrust(f.context)
            val original = requireNotNull(reader.loadExisting())
            when (change) {
                "source-id" -> Files.write(f.identity, "00000000-0000-4000-8000-000000000003".toByteArray())
                "host-id" -> f.writePayload(f.payload("installationId", "\"00000000-0000-4000-8000-000000000003\""))
                "display" -> f.writePayload(f.payload("displayName", "\"Changed CLI\""))
                "endpoint" -> f.writePayload(f.payload("host", "\"192.168.1.3\""))
                "port" -> f.writePayload(f.payload("port", "17648"))
                "time" -> f.writePayload(f.payload("pairedAt", "\"2026-01-02T00:00:00Z\""))
                "secret" -> f.writePayload(f.payload("reconnectSecretBase64", "\"${java.util.Base64.getEncoder().encodeToString(ByteArray(32) { 0x49 })}\""))
            }
            assertThat(reader.loadExisting()).isNotNull()
            val before = f.fileBytes()
            repeat(2) { expectCode(AgentBridgeErrorCode.BINDING_CHANGED) { reader.requireCurrent(original, SOURCE, HOST, f.secret) } }
            assertThat(f.fileBytes()).isEqualTo(before)
        }
        withNativeTrust { f ->
            val reader = AgentBridgeExportNativeTrust(f.context)
            val original = requireNotNull(reader.loadExisting())
            for ((source, host, secret) in listOf(Triple(HOST, HOST, f.secret), Triple(SOURCE, SOURCE, f.secret),
                Triple(SOURCE, HOST, ByteArray(32)), Triple(SOURCE, HOST, ByteArray(31)), Triple(SOURCE, HOST, ByteArray(65537)))) {
                expectCode(AgentBridgeErrorCode.BINDING_CHANGED) { reader.requireCurrent(original, source, host, secret) }
            }
            reader.requireCurrent(original, SOURCE, HOST, f.secret)
        }
    }

    @Test
    fun currentChecksFreshlyObserveKeyReplacementRemovalAndFileDirectoryRemoval() {
        for (change in listOf("key-missing", "key-replaced", "re-encrypted", "identity", "trust", "root", "parent")) withNativeTrust { f ->
            val reader = AgentBridgeExportNativeTrust(f.context)
            val original = requireNotNull(reader.loadExisting())
            when (change) {
                "key-missing" -> f.selected = null
                "key-replaced", "re-encrypted" -> {
                    val replacement = SecretKeySpec(ByteArray(32) { 0x49 }, "AES")
                    f.selected = replacement
                    if (change == "re-encrypted") f.writePayload(f.writerBytes(), replacement, 0x12)
                }
                "identity" -> Files.delete(f.identity)
                "trust" -> Files.delete(f.trust)
                "root" -> removeTree(f.root)
                "parent" -> removeTree(f.parent)
            }
            val before = f.inventory()
            repeat(2) { expectCode(AgentBridgeErrorCode.BINDING_CHANGED) { reader.requireCurrent(original, SOURCE, HOST, f.secret) } }
            assertThat(f.inventory()).isEqualTo(before)
        }
    }

    @Test
    fun finalNativeRechecksObserveBfuKeyMetadataFilesAndContextChanges() {
        for (change in listOf("bfu", "metadata", "key-missing", "identity", "trust", "context", "uid")) withNativeTrust { f ->
            var lookups = 0
            var expectedFiles = f.inventory()
            every { f.factory.getKeySpec(any(), KeyInfo::class.java) } answers {
                if (++lookups == 1) when (change) {
                    "bfu" -> f.firstUnlocked = false
                    "metadata" -> every { f.info.origin } returns KeyProperties.ORIGIN_IMPORTED
                    "key-missing" -> f.selected = null
                    "identity" -> Files.write(f.identity, "00000000-0000-4000-8000-000000000003".toByteArray())
                    "trust" -> f.writePayload(f.payload("host", "\"192.168.1.3\""))
                    "context" -> every { f.context.dataDir } returns f.parent.toFile()
                    "uid" -> every { Process.myUid() } returns -1
                }
                expectedFiles = f.inventory()
                f.info
            }
            expectCode(if (change == "bfu" || change == "metadata") AgentBridgeErrorCode.PERMISSION_REQUIRED else AgentBridgeErrorCode.BINDING_CHANGED) {
                AgentBridgeExportNativeTrust(f.context).loadExisting()
            }
            // Only the synthetic external callback changed these bytes; reader never repairs them.
            assertThat(f.inventory()).isEqualTo(expectedFiles)
        }
    }

    @Test
    fun native0771IsAllowedOnlyForExactSdkParentsWithTrustedUidAndGid() {
        withNativeTrust { f ->
            Files.setAttribute(f.data, "unix:mode", 505)
            Files.setAttribute(f.parent, "unix:mode", 505)
            assertThat(AgentBridgeExportNativeTrust(f.context).loadExisting()).isNotNull()
            Files.setAttribute(f.root, "unix:mode", 505)
            rejectedUnchanged(f)
        }
        for (owner in listOf("uid", "gid")) withNativeTrust { f ->
            if (owner == "uid") every { Process.myUid() } returns -1
            else every { Os.getgid() } returns -1
            rejectedUnchanged(f)
        }
        for (target in listOf("data", "parent", "root", "identity", "trust")) withNativeTrust { f ->
            val path = f.path(target)
            val base = if (target in listOf("identity", "trust")) 384 else 448
            for (mode in listOf(base or 2, base or 16, if (base == 384) 420 else 493,
                if (base == 384) 416 else 504)) {
                Files.setAttribute(path, "unix:mode", mode)
                val observedMode = (Files.getAttribute(path, "unix:mode") as Number).toInt() and 0xfff
                check(observedMode == mode) { "synthetic $target requested=$mode observed=$observedMode" }
                rejectedUnchanged(f)
            }
            // This host did not retain requested setgid bits. Special-bit rejection stays in
            // production's exact full mode check, but actual OS special-bit qualification is NOT RUN.
            // Do not mock Files or require extra JVM module opens to manufacture that evidence.
        }
    }

    @Test
    fun aliasesSymlinksHardLinksAndWrongFileTypesCannotSupplyNativeTrust() {
        for (target in listOf("parent", "root", "identity", "trust")) withNativeTrust { f ->
            val path = f.path(target)
            val moved = path.resolveSibling("synthetic-original-${path.fileName}")
            Files.move(path, moved)
            Files.createSymbolicLink(path, moved.fileName)
            rejectedUnchanged(f)
        }
        for (target in listOf("identity", "trust")) withNativeTrust { f ->
            Files.createLink(f.root.resolve("synthetic-hardlink"), f.path(target))
            rejectedUnchanged(f)
        }
        for (alias in listOf("dot", "symlink", "relative")) withNativeTrust { f ->
            val path = when (alias) {
                "dot" -> f.data.resolve(".")
                "relative" -> Path.of("synthetic-relative-data")
                else -> Files.createSymbolicLink(f.data.resolve("synthetic-alias"), f.data)
            }
            every { f.context.dataDir } returns path.toFile()
            rejectedUnchanged(f)
        }
        for (target in listOf("identity", "trust")) withNativeTrust { f ->
            Files.delete(f.path(target))
            Files.createDirectory(f.path(target), privateDirectory)
            val before = f.inventory()
            expectCode(AgentBridgeErrorCode.BINDING_CHANGED) { AgentBridgeExportNativeTrust(f.context).loadExisting() }
            assertThat(f.inventory()).isEqualTo(before)
        }
    }

    @Test
    fun originalIdentityAndDirectoryInodesCannotBeReplacedWithValidSameIdFiles() {
        for (target in listOf("identity", "root", "parent")) withNativeTrust { f ->
            val reader = AgentBridgeExportNativeTrust(f.context)
            val original = requireNotNull(reader.loadExisting())
            val path = f.path(target)
            Files.move(path, path.resolveSibling("synthetic-old-${path.fileName}"))
            if (target == "parent") Files.createDirectory(f.parent, privateDirectory)
            if (target != "identity") Files.createDirectory(f.root, privateDirectory)
            Files.createFile(f.identity, privateFile)
            Files.write(f.identity, SOURCE.toByteArray())
            if (target != "identity") {
                Files.createFile(f.trust, privateFile)
                f.writePayload(f.writerBytes())
            }
            assertThat(reader.loadExisting()).isNotNull()
            val before = f.fileBytes()
            expectCode(AgentBridgeErrorCode.BINDING_CHANGED) { reader.requireCurrent(original, SOURCE, HOST, f.secret) }
            assertThat(f.fileBytes()).isEqualTo(before)
        }
    }

    private fun rejectedUnchanged(f: NativeTrustBoundary, code: AgentBridgeErrorCode = AgentBridgeErrorCode.BINDING_CHANGED) {
        val before = f.fileBytes()
        val inventory = f.inventory()
        expectCode(code) { AgentBridgeExportNativeTrust(f.context).loadExisting() }
        assertThat(f.fileBytes()).isEqualTo(before)
        assertThat(f.inventory()).isEqualTo(inventory)
    }

    private fun expectCode(code: AgentBridgeErrorCode, block: () -> Unit) {
        val failure = runCatching(block).exceptionOrNull()
        assertThat(failure).isInstanceOf(AgentBridgeException::class.java)
        assertThat((failure as AgentBridgeException).code).isEqualTo(code)
        assertThat(failure.cause).isNull()
    }

    private fun withNativeTrust(block: (NativeTrustBoundary) -> Unit) {
        mockkStatic(Process::class)
        mockkStatic(Os::class)
        mockkStatic(KeyStore::class)
        mockkStatic(SecretKeyFactory::class)
        try { NativeTrustBoundary().use(block) }
        finally {
            unmockkStatic(SecretKeyFactory::class); unmockkStatic(KeyStore::class)
            unmockkStatic(Os::class); unmockkStatic(Process::class)
        }
    }

    private class NativeTrustBoundary : AutoCloseable {
        val data: Path = Files.createTempDirectory("synthetic-pairing-", privateDirectory)
        val parent = Files.createDirectory(data.resolve("no_backup"), privateDirectory)
        val root = Files.createDirectory(parent.resolve("direct-cli"), privateDirectory)
        val identity = root.resolve("installation-id")
        val trust = root.resolve("trust.enc")
        val context = mockk<Context>()
        val users = mockk<UserManager>()
        val store = mockk<KeyStore>()
        val factory = mockk<SecretKeyFactory>()
        val info = mockk<KeyInfo>()
        val key = SecretKeySpec(ByteArray(32) { 0x37 }, "AES")
        val secret = ByteArray(32) { 0x29 }
        var selected: Key? = key
        var firstUnlocked = true
        init {
            every { Process.myUid() } returns (Files.getAttribute(data, "unix:uid") as Number).toInt()
            every { Os.getgid() } returns (Files.getAttribute(data, "unix:gid") as Number).toInt()
            every { context.dataDir } returns data.toFile()
            every { context.noBackupFilesDir } throws AssertionError("Creating getter forbidden")
            every { context.filesDir } throws AssertionError("Creating getter forbidden")
            every { context.isDeviceProtectedStorage } returns false
            every { context.getSystemService(UserManager::class.java) } returns users
            every { users.isUserUnlocked } answers { firstUnlocked }
            val provider = object : Provider("AndroidKeyStore", 1.0, "Synthetic SDK boundary") {}
            every { KeyStore.getInstance("AndroidKeyStore") } returns store
            every { store.provider } returns provider
            every { store.load(null as KeyStore.LoadStoreParameter?) } just Runs
            every { store.getKey("healthmd-direct-cli-trust-v1", null) } answers { selected }
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
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                every { info.remainingUsageCount } returns KeyProperties.UNRESTRICTED_USAGE_COUNT
            }
            Files.createFile(identity, privateFile)
            Files.write(identity, SOURCE.toByteArray(Charsets.US_ASCII))
            Files.createFile(trust, privateFile)
            writePayload(writerBytes())
        }
        // Literal field order/types from DirectCliTrustStore.StoredTrust + Json encodeDefaults.
        // Do not construct the mutating legacy store even in this synthetic seam test.
        fun writerBytes(): ByteArray = ("{\"installationId\":\"$HOST\",\"displayName\":\"Synthetic CLI\"," +
            "\"reconnectSecretBase64\":\"${java.util.Base64.getEncoder().encodeToString(secret)}\"," +
            "\"host\":\"192.168.1.2\",\"port\":17647,\"pairedAt\":\"2026-01-01T00:00:00.123456789Z\"}").toByteArray()
        fun writePayload(bytes: ByteArray, encryptionKey: SecretKeySpec = key, nonceByte: Byte = 0x11) {
            val nonce = ByteArray(12) { nonceByte }
            val cipher = Cipher.getInstance("AES/GCM/NoPadding")
            cipher.init(Cipher.ENCRYPT_MODE, encryptionKey, GCMParameterSpec(128, nonce))
            Files.write(trust, nonce + cipher.doFinal(bytes))
        }
        fun payload(field: String, raw: String?): ByteArray {
            val fields = (Json.parseToJsonElement(writerBytes().decodeToString()) as JsonObject).toMutableMap()
            if (raw == null) fields.remove(field) else fields[field] = Json.parseToJsonElement(raw)
            return JsonObject(fields).toString().toByteArray()
        }
        fun fileBytes() = Files.readAllBytes(identity).toList() to Files.readAllBytes(trust).toList()
        fun path(target: String) = when (target) {
            "data" -> data; "parent" -> parent; "root" -> root; "identity" -> identity; else -> trust
        }
        fun inventory(): Map<String, List<Byte>?> = if (!Files.exists(data)) emptyMap() else Files.walk(data).use { paths ->
            paths.sorted().filter { it != data }.toList().associate { path ->
                data.relativize(path).toString() to if (Files.isRegularFile(path)) Files.readAllBytes(path).toList() else null
            }
        }
        override fun close() = removeTree(data)
    }

    companion object {
        private fun removeTree(path: Path) {
            if (Files.exists(path)) Files.walk(path).use { paths -> paths.sorted(Comparator.reverseOrder()).forEach { Files.delete(it) } }
        }
        private const val SOURCE = "00000000-0000-4000-8000-000000000001"
        private const val HOST = "00000000-0000-4000-8000-000000000002"
        private val privateDirectory = PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rwx------"))
        private val privateFile = PosixFilePermissions.asFileAttribute(PosixFilePermissions.fromString("rw-------"))
    }
}
