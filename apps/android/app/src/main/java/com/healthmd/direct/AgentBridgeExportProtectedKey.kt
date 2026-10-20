package com.healthmd.direct

import android.content.Context
import android.os.Build
import android.os.UserManager
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyInfo
import android.security.keystore.KeyProperties
import java.security.KeyStore
import javax.crypto.KeyGenerator
import javax.crypto.Mac
import javax.crypto.SecretKey
import javax.crypto.SecretKeyFactory

/** Load-only native issuer integrity key, never authority/health/configuration/entitlement consent.
 * Provisioning is a separate native human action. No caller-selected alias, credential cache,
 * generation, import, repair, legacy-key reuse or plaintext/provider-independent fallback. */
internal class AgentBridgeExportProtectedKey(private val context: Context) : AgentBridgeExportProtectedKeyProvider {
    override fun loadExisting(): SecretKey? {
        return try {
            if (context.isDeviceProtectedStorage) return null
            val users = context.getSystemService(UserManager::class.java) ?: return null
            // First unlock after reboot, NOT the screen/keyguard state. A surviving user-started
            // service may use integrity state during ordinary later locking. This starts no service.
            if (!users.isUserUnlocked) return null
            val store = KeyStore.getInstance(KEYSTORE)
            if (store.provider.name != KEYSTORE) return null
            store.load(null)
            val key = store.getKey(ISSUER_ALIAS, null) as? SecretKey ?: return null
            if (key.algorithm != ALGORITHM) return null
            val factory = SecretKeyFactory.getInstance(ALGORITHM, KEYSTORE)
            if (factory.provider.name != KEYSTORE) return null
            val info = factory.getKeySpec(key, KeyInfo::class.java) as? KeyInfo ?: return null
            // The SDK factory rejects foreign keys and establishes native handle provenance.
            // SDK-owned software-backed Keystore keys are valid too; hardware is not a grant.
            if (info.keystoreAlias != ISSUER_ALIAS || info.origin != KeyProperties.ORIGIN_GENERATED ||
                info.keySize != 256 || info.purposes != KeyProperties.PURPOSE_SIGN ||
                !info.digests.contentEquals(arrayOf(KeyProperties.DIGEST_SHA256)) ||
                info.isTrustedUserPresenceRequired || info.isUserConfirmationRequired) return null
            // Probing and ledger MACs consume limited-use keys. Reject BEFORE starting a MAC;
            // this dedicated integrity key must be unrestricted. This API exists only on 31+.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S &&
                info.remainingUsageCount != KeyProperties.UNRESTRICTED_USAGE_COUNT) return null
            // Keep the native nonexportable key. Only JCA's compatible native MAC engine may
            // use it; never inspect encoded bytes. No authentication UI or token renewal.
            val mac = Mac.getInstance(ALGORITHM)
            mac.init(key)
            if (mac.doFinal().size != 32 || !users.isUserUnlocked) return null
            key
        } catch (_: Exception) { null } // Fixed absence; unchanged store maps to permission_required.
    }

    internal companion object {
        const val KEYSTORE = "AndroidKeyStore"
        const val ISSUER_ALIAS = "healthmd-agent-bridge-native-export-authority-v1"
        const val ALGORITHM = KeyProperties.KEY_ALGORITHM_HMAC_SHA256
    }
}


/** Used only after explicit native authorization reserves a new issuer directory. This writer is
 * never a planning dependency. Existing unreadable aliases are not replaced; failures leave the
 * reserved issuer unavailable, not a repaired/reset ledger. Ordinary later screen locking remains
 * compatible with the user-started service's AFU policy; this integrity key grants no export rights. */
internal class AgentBridgeExportProtectedKeyProvisioner(private val context: Context) {
    val reader = AgentBridgeExportProtectedKey(context)

    fun requireAvailable() {
        if (context.isDeviceProtectedStorage ||
            context.getSystemService(UserManager::class.java)?.isUserUnlocked != true) {
            throw com.healthmd.direct.protocol.AgentBridgeException(
                com.healthmd.direct.protocol.AgentBridgeErrorCode.PERMISSION_REQUIRED)
        }
    }

    fun loadOrCreateForNewPrivateStore(): SecretKey {
        reader.loadExisting()?.let { return it }
        try {
            require(!context.isDeviceProtectedStorage)
            val users = requireNotNull(context.getSystemService(UserManager::class.java))
            require(users.isUserUnlocked)
            val store = KeyStore.getInstance(AgentBridgeExportProtectedKey.KEYSTORE)
            require(store.provider.name == AgentBridgeExportProtectedKey.KEYSTORE)
            store.load(null)
            // The exclusive new-directory reservation serializes cooperating native bootstrap
            // processes. KeyGenerator can overwrite an alias, so never generate over ANY item.
            require(!store.containsAlias(AgentBridgeExportProtectedKey.ISSUER_ALIAS))
            val generator = KeyGenerator.getInstance(AgentBridgeExportProtectedKey.ALGORITHM,
                AgentBridgeExportProtectedKey.KEYSTORE)
            require(generator.provider.name == AgentBridgeExportProtectedKey.KEYSTORE)
            generator.init(KeyGenParameterSpec.Builder(AgentBridgeExportProtectedKey.ISSUER_ALIAS,
                KeyProperties.PURPOSE_SIGN).setKeySize(256).setDigests(KeyProperties.DIGEST_SHA256)
                .setUserAuthenticationRequired(false).setUnlockedDeviceRequired(false).build())
            require(users.isUserUnlocked)
            val generated = generator.generateKey()
            val current = requireNotNull(reader.loadExisting())
            val challenge = "HealthMd.AgentBridge.NativeExportKey.Readback.v1".toByteArray(Charsets.UTF_8)
            val expected = Mac.getInstance(AgentBridgeExportProtectedKey.ALGORITHM).run {
                init(generated); doFinal(challenge)
            }
            val observed = Mac.getInstance(AgentBridgeExportProtectedKey.ALGORITHM).run {
                init(current); doFinal(challenge)
            }
            require(java.security.MessageDigest.isEqual(expected, observed) && users.isUserUnlocked)
            return current
        } catch (_: Exception) {
            throw com.healthmd.direct.protocol.AgentBridgeException(
                com.healthmd.direct.protocol.AgentBridgeErrorCode.PERMISSION_REQUIRED)
        }
    }
}
