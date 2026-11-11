package com.healthmd.data.clinicsync

import android.content.Context
import androidx.security.crypto.EncryptedSharedPreferences
import androidx.security.crypto.MasterKey
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.RequestBody.Companion.toRequestBody
import java.io.IOException
import java.security.MessageDigest
import java.util.Base64
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

/** A delegated sync doorbell this phone holds (clinic-sponsorship contract, "Clinic sync requests"). */
@Serializable
data class ClinicSyncDoorbell(
    val wakeId: String,
    /** Raw 32-byte doorbell key, base64url without padding. */
    val wakeKey: String,
    /** Canonical clinic endpoint the key was delivered to; any binding change revokes it. */
    val endpoint: String,
    /** FCM token registered with the wake service, for rotation. */
    val deviceToken: String,
)

object ClinicSyncDoorbellMessages {
    const val MESSAGE_TYPE = "clinic-sync-doorbell.v1"
    const val WAKE_SERVICE = "https://healthmd-wake.costream.workers.dev"
    const val REQUEST_KIND = "delegated-sync-request"

    fun enroll(wakeId: String, wakeKey: String): String = buildJsonObject {
        put("type", "healthmd.clinic_sync_doorbell")
        put("version", 1)
        put("action", "enroll")
        put("wakeService", WAKE_SERVICE)
        put("wakeId", wakeId)
        put("wakeKey", wakeKey)
    }.toString()

    fun revoke(wakeId: String): String = buildJsonObject {
        put("type", "healthmd.clinic_sync_doorbell")
        put("version", 1)
        put("action", "revoke")
        put("wakeId", wakeId)
    }.toString()

    fun base64url(bytes: ByteArray): String = Base64.getUrlEncoder().withoutPadding().encodeToString(bytes)

    fun verificationHash(wakeKey: String): String =
        MessageDigest.getInstance("SHA-256").digest(Base64.getUrlDecoder().decode(wakeKey))
            .joinToString("") { "%02x".format(it) }

    /** The wake id of a clinic sync request push, or null for any other data message. */
    fun requestedWakeId(data: Map<String, String>): String? =
        data["wakeId"]?.takeIf { data["kind"] == REQUEST_KIND && it.isNotEmpty() }
}

interface ClinicSyncDoorbellStorage {
    fun load(): ClinicSyncDoorbell?
    fun save(doorbell: ClinicSyncDoorbell)
    fun clear()
    /** Doorbell whose wake-service revocation failed and must be retried. */
    var pendingRevocation: String?
    /** Stable, random wake-service install id; unrelated to the licensing installation id. */
    val wakeUserId: String
}

@Singleton
class EncryptedClinicSyncDoorbellStorage @Inject constructor(
    @ApplicationContext context: Context,
) : ClinicSyncDoorbellStorage {
    private val preferences by lazy {
        val key = MasterKey.Builder(context).setKeyScheme(MasterKey.KeyScheme.AES256_GCM).build()
        EncryptedSharedPreferences.create(context, "clinic_sync_doorbell_secure_v1", key,
            EncryptedSharedPreferences.PrefKeyEncryptionScheme.AES256_SIV,
            EncryptedSharedPreferences.PrefValueEncryptionScheme.AES256_GCM)
    }

    override fun load(): ClinicSyncDoorbell? = preferences.getString("doorbell", null)?.let {
        runCatching { Json.decodeFromString(ClinicSyncDoorbell.serializer(), it) }.getOrNull()
    }

    override fun save(doorbell: ClinicSyncDoorbell) {
        check(preferences.edit().putString("doorbell", Json.encodeToString(ClinicSyncDoorbell.serializer(), doorbell))
            .commit()) { "secure_storage_unavailable" }
    }

    override fun clear() {
        preferences.edit().remove("doorbell").commit()
    }

    override var pendingRevocation: String?
        get() = preferences.getString("pendingRevocation", null)
        set(value) { preferences.edit().putString("pendingRevocation", value).commit() }

    override val wakeUserId: String
        get() = preferences.getString("wakeUserId", null) ?: UUID.randomUUID().toString().also {
            preferences.edit().putString("wakeUserId", it).commit()
        }
}

interface ClinicSyncWakeService {
    /** Registers (or, with [existingWakeId], rotates) a delegated sync doorbell; returns its wake id. */
    suspend fun register(userId: String, fcmToken: String, verificationHash: String, existingWakeId: String?): String
    suspend fun unregister(userId: String, wakeId: String)
}

/** Wake-service client. The worker receives only the install id, FCM token and key hash. */
class OkHttpClinicSyncWakeService @Inject constructor() : ClinicSyncWakeService {
    private val client = OkHttpClient.Builder()
        .followRedirects(false).followSslRedirects(false)
        .callTimeout(10, TimeUnit.SECONDS)
        .build()

    override suspend fun register(userId: String, fcmToken: String, verificationHash: String, existingWakeId: String?): String {
        val body = buildJsonObject {
            put("userId", userId)
            put("deviceToken", fcmToken)
            put("wakeKeyVerificationHash", verificationHash)
            put("platform", "fcm")
            put("purpose", "delegated-sync")
            existingWakeId?.let { put("wakeId", it) }
        }.toString()
        val response = send("POST", body)
        val wakeId = Json.parseToJsonElement(response).jsonObject["wakeId"]?.jsonPrimitive?.content
        if (wakeId == null || wakeId.toByteArray().size !in 1..128) throw IOException("invalid_wake_response")
        return wakeId
    }

    override suspend fun unregister(userId: String, wakeId: String) {
        send("DELETE", buildJsonObject { put("userId", userId); put("wakeId", wakeId) }.toString())
    }

    private suspend fun send(method: String, body: String): String = withContext(Dispatchers.IO) {
        val request = Request.Builder()
            .url("${ClinicSyncDoorbellMessages.WAKE_SERVICE}/wake/register")
            .method(method, body.toRequestBody("application/json".toMediaType()))
            .build()
        client.newCall(request).execute().use { response ->
            if (!response.isSuccessful) throw IOException("wake_status_${response.code}")
            response.body?.string().orEmpty()
        }
    }
}

/** Push transport for clinic sync requests: FCM on Play builds, unavailable elsewhere. */
interface ClinicSyncPushTransport {
    val available: Boolean
    suspend fun token(): String?
}

interface ClinicSyncControlSender {
    suspend fun send(endpoint: String, body: String)
}

class APIExportClinicControlSender @Inject constructor(
    private val client: com.healthmd.data.export.APIExportClient,
) : ClinicSyncControlSender {
    override suspend fun send(endpoint: String, body: String) =
        client.sendClinicControlMessage(endpoint, ClinicSyncDoorbellMessages.MESSAGE_TYPE, body)
}
