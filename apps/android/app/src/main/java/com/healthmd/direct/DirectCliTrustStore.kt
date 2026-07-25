package com.healthmd.direct

import android.content.Context
import android.security.keystore.KeyGenParameterSpec
import android.security.keystore.KeyProperties
import android.util.Base64
import com.healthmd.direct.protocol.AuthenticatedListener
import com.healthmd.direct.protocol.DIRECT_PORT
import com.healthmd.direct.protocol.TrustedListener
import dagger.hilt.android.qualifiers.ApplicationContext
import java.io.File
import java.security.KeyStore
import java.time.Instant
import java.util.UUID
import javax.crypto.Cipher
import javax.crypto.KeyGenerator
import javax.crypto.SecretKey
import javax.crypto.spec.GCMParameterSpec
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

@Singleton
class DirectCliTrustStore @Inject constructor(
    @ApplicationContext context: Context,
) {
    private val root = File(context.noBackupFilesDir, "direct-cli").apply {
        check(mkdirs() || isDirectory) { "Unable to create Direct CLI private storage." }
    }
    private val trustFile = File(root, "trust.enc")
    private val identityFile = File(root, "installation-id")
    private val json = Json { encodeDefaults = true; ignoreUnknownKeys = false }

    @Synchronized
    fun installationId(): String {
        identityFile.takeIf(File::isFile)?.readText()?.trim()?.let { stored ->
            runCatching { UUID.fromString(stored).toString() }.getOrNull()?.let { return it }
        }
        val created = UUID.randomUUID().toString()
        atomicWrite(identityFile, created.toByteArray(Charsets.US_ASCII))
        return created
    }

    @Synchronized
    fun load(): TrustedListener? {
        if (!trustFile.isFile) return null
        return runCatching {
            val encrypted = trustFile.readBytes()
            require(encrypted.size > NONCE_BYTES + 16)
            val nonce = encrypted.copyOfRange(0, NONCE_BYTES)
            val ciphertext = encrypted.copyOfRange(NONCE_BYTES, encrypted.size)
            val cipher = Cipher.getInstance(CIPHER)
            cipher.init(Cipher.DECRYPT_MODE, key(), GCMParameterSpec(128, nonce))
            val stored = json.decodeFromString<StoredTrust>(
                cipher.doFinal(ciphertext).toString(Charsets.UTF_8),
            )
            TrustedListener(
                installationId = UUID.fromString(stored.installationId).toString(),
                displayName = stored.displayName,
                reconnectSecret = Base64.decode(stored.reconnectSecretBase64, Base64.NO_WRAP),
                host = stored.host,
                port = stored.port,
            ).also {
                require(it.displayName.isNotBlank())
                require(it.reconnectSecret.size == 32)
                require(it.host.isNotBlank())
                require(it.port in 1..65_535)
            }
        }.getOrElse {
            trustFile.delete()
            null
        }
    }

    @Synchronized
    fun save(listener: AuthenticatedListener, host: String, port: Int = DIRECT_PORT) {
        require(host.isNotBlank() && port in 1..65_535 && listener.reconnectSecret.size == 32)
        val stored = StoredTrust(
            installationId = UUID.fromString(listener.installationId).toString(),
            displayName = listener.displayName,
            reconnectSecretBase64 = Base64.encodeToString(listener.reconnectSecret, Base64.NO_WRAP),
            host = host.trim(),
            port = port,
            pairedAt = Instant.now().toString(),
        )
        val cipher = Cipher.getInstance(CIPHER)
        cipher.init(Cipher.ENCRYPT_MODE, key())
        val ciphertext = cipher.doFinal(json.encodeToString(stored).toByteArray(Charsets.UTF_8))
        val nonce = requireNotNull(cipher.iv) { "Android Keystore did not generate an encryption IV." }
        require(nonce.size == NONCE_BYTES) { "Android Keystore generated an invalid encryption IV." }
        atomicWrite(trustFile, nonce + ciphertext)
    }

    @Synchronized
    fun updateEndpoint(host: String, port: Int) {
        val current = requireNotNull(load()) { "Pair with a CLI before changing its endpoint." }
        save(
            listener = AuthenticatedListener(
                installationId = current.installationId,
                displayName = current.displayName,
                reconnectSecret = current.reconnectSecret,
            ),
            host = host,
            port = port,
        )
    }

    @Synchronized
    fun forget() {
        if (trustFile.exists()) check(trustFile.delete()) { "Unable to remove Direct CLI trust." }
        val keyStore = keyStore()
        if (keyStore.containsAlias(KEY_ALIAS)) keyStore.deleteEntry(KEY_ALIAS)
    }

    fun rootDirectory(): File = root

    private fun key(): SecretKey {
        val keyStore = keyStore()
        (keyStore.getKey(KEY_ALIAS, null) as? SecretKey)?.let { return it }
        val generator = KeyGenerator.getInstance(KeyProperties.KEY_ALGORITHM_AES, ANDROID_KEYSTORE)
        generator.init(
            KeyGenParameterSpec.Builder(
                KEY_ALIAS,
                KeyProperties.PURPOSE_ENCRYPT or KeyProperties.PURPOSE_DECRYPT,
            )
                .setBlockModes(KeyProperties.BLOCK_MODE_GCM)
                .setEncryptionPaddings(KeyProperties.ENCRYPTION_PADDING_NONE)
                .setKeySize(256)
                .build(),
        )
        return generator.generateKey()
    }

    private fun keyStore(): KeyStore = KeyStore.getInstance(ANDROID_KEYSTORE).apply { load(null) }

    private fun atomicWrite(file: File, bytes: ByteArray) {
        val temporary = File(file.parentFile, ".${file.name}.${UUID.randomUUID()}.tmp")
        temporary.outputStream().use { output ->
            output.write(bytes)
            output.flush()
            output.fd.sync()
        }
        check(temporary.renameTo(file)) { "Unable to persist Direct CLI state atomically." }
    }

    @Serializable
    private data class StoredTrust(
        val installationId: String,
        val displayName: String,
        val reconnectSecretBase64: String,
        val host: String,
        val port: Int,
        val pairedAt: String,
    )

    companion object {
        private const val ANDROID_KEYSTORE = "AndroidKeyStore"
        private const val KEY_ALIAS = "healthmd-direct-cli-trust-v1"
        private const val CIPHER = "AES/GCM/NoPadding"
        private const val NONCE_BYTES = 12
    }
}
