package com.healthmd.data.clinicsync

import com.healthmd.data.billing.ClinicSponsorshipManager
import com.healthmd.data.billing.ClinicSponsorshipStatus
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import timber.log.Timber
import java.security.SecureRandom
import javax.inject.Inject
import javax.inject.Singleton

sealed interface ClinicSyncState {
    data object Disabled : ClinicSyncState
    data object Updating : ClinicSyncState
    data object Enabled : ClinicSyncState
    data class Unavailable(val reason: Reason) : ClinicSyncState

    enum class Reason {
        SHARING_REQUIRED, PUSH_UNAVAILABLE, NOTIFICATIONS_DENIED, WAKE_SERVICE, CLINIC_UNREACHABLE, STORAGE
    }
}

/** Runs the clinic profile export for yesterday and today; returns whether it succeeded. */
interface ClinicSyncExportLauncher {
    suspend fun exportClinicProfile(endpoint: String): ClinicSyncExportResult
}

enum class ClinicSyncExportResult { SENT, FAILED, PROFILE_MISSING }

interface ClinicSyncNotifier {
    fun canPostNotifications(): Boolean
    fun postRequest(wakeId: String)
    fun postResult(result: ClinicSyncExportResult)
}

/**
 * Clinic sync requests (clinic-sponsorship contract, "delegated doorbell").
 *
 * When the patient separately allows it, the phone registers a `delegated-sync` doorbell with
 * the wake service and hands its key to the approved clinic endpoint. A ring arrives as an FCM
 * data message; the phone posts a fixed, localized notification, and only the patient's tap
 * runs a clinic export. The wake service never learns about the clinic.
 */
@Singleton
class ClinicSyncDoorbellManager internal constructor(
    private val clinicStatus: () -> ClinicSponsorshipStatus,
    private val storage: ClinicSyncDoorbellStorage,
    private val wake: ClinicSyncWakeService,
    private val sender: ClinicSyncControlSender,
    private val push: ClinicSyncPushTransport,
    private val exporter: ClinicSyncExportLauncher,
    private val notifier: ClinicSyncNotifier,
    private val randomKey: () -> ByteArray = { ByteArray(32).also { SecureRandom().nextBytes(it) } },
) {
    @Inject constructor(
        clinic: ClinicSponsorshipManager,
        storage: EncryptedClinicSyncDoorbellStorage,
        wake: OkHttpClinicSyncWakeService,
        sender: APIExportClinicControlSender,
        push: ClinicSyncPushTransport,
        exporter: ClinicSyncExportLauncher,
        notifier: ClinicSyncNotifier,
    ) : this({ clinic.status.value }, storage, wake, sender, push, exporter, notifier)

    private val mutex = Mutex()
    private val mutableState = MutableStateFlow<ClinicSyncState>(
        if (runCatching { storage.load() }.getOrNull() != null) ClinicSyncState.Enabled else ClinicSyncState.Disabled,
    )
    val state = mutableState.asStateFlow()

    val pushAvailable: Boolean get() = push.available

    fun canEnable(status: ClinicSponsorshipStatus = clinicStatus()): Boolean =
        push.available && status.active && status.sharingAuthorized && status.endpoint != null

    suspend fun enable() = mutex.withLock {
        if (storage.load() != null) { mutableState.value = ClinicSyncState.Enabled; return@withLock }
        val status = clinicStatus()
        val endpoint = status.endpoint
        if (!status.active || !status.sharingAuthorized || endpoint == null) {
            return@withLock unavailable(ClinicSyncState.Reason.SHARING_REQUIRED)
        }
        if (!push.available) return@withLock unavailable(ClinicSyncState.Reason.PUSH_UNAVAILABLE)
        if (!notifier.canPostNotifications()) return@withLock unavailable(ClinicSyncState.Reason.NOTIFICATIONS_DENIED)
        mutableState.value = ClinicSyncState.Updating

        val token = guarded { push.token() } ?: return@withLock unavailable(ClinicSyncState.Reason.PUSH_UNAVAILABLE)
        val key = ClinicSyncDoorbellMessages.base64url(randomKey())
        val wakeId = guarded {
            wake.register(storage.wakeUserId, token, ClinicSyncDoorbellMessages.verificationHash(key), null)
        } ?: return@withLock unavailable(ClinicSyncState.Reason.WAKE_SERVICE)

        if (guarded { sender.send(endpoint, ClinicSyncDoorbellMessages.enroll(wakeId, key)) } == null) {
            // The clinic never received the key: leave no doorbell behind.
            guarded { wake.unregister(storage.wakeUserId, wakeId) }
            return@withLock unavailable(ClinicSyncState.Reason.CLINIC_UNREACHABLE)
        }
        if (guarded { storage.save(ClinicSyncDoorbell(wakeId, key, endpoint, token)) } == null) {
            guarded { wake.unregister(storage.wakeUserId, wakeId) }
            return@withLock unavailable(ClinicSyncState.Reason.STORAGE)
        }
        mutableState.value = ClinicSyncState.Enabled
    }

    suspend fun disable() = mutex.withLock { disableLocked() }

    /** Keeps the doorbell bound to the current clinic consent and FCM token. */
    suspend fun reconcile(status: ClinicSponsorshipStatus = clinicStatus()) = mutex.withLock {
        storage.pendingRevocation?.let { pending ->
            if (guarded { wake.unregister(storage.wakeUserId, pending) } != null) storage.pendingRevocation = null
        }
        val doorbell = runCatching { storage.load() }.getOrNull()
        if (doorbell == null) {
            if (mutableState.value == ClinicSyncState.Enabled) mutableState.value = ClinicSyncState.Disabled
            return@withLock
        }
        if (!status.active || !status.sharingAuthorized || status.endpoint != doorbell.endpoint) {
            return@withLock disableLocked()
        }
        val token = guarded { push.token() }
        if (token != null && token != doorbell.deviceToken) {
            guarded {
                wake.register(storage.wakeUserId, token, ClinicSyncDoorbellMessages.verificationHash(doorbell.wakeKey),
                    doorbell.wakeId)
                storage.save(doorbell.copy(deviceToken = token))
            } ?: Timber.w("Clinic sync doorbell token rotation failed; retrying later")
        }
        mutableState.value = ClinicSyncState.Enabled
    }

    /** A ring for a doorbell this phone no longer holds is dropped without a notification. */
    fun onSyncRequestReceived(wakeId: String) {
        if (runCatching { storage.load() }.getOrNull()?.wakeId == wakeId) notifier.postRequest(wakeId)
    }

    suspend fun handleSyncRequestTap(wakeId: String) {
        val doorbell = runCatching { storage.load() }.getOrNull()
        if (doorbell?.wakeId != wakeId) return
        val status = clinicStatus()
        if (!status.active || !status.sharingAuthorized || status.endpoint != doorbell.endpoint) {
            disable()
            notifier.postResult(ClinicSyncExportResult.FAILED)
            return
        }
        notifier.postResult(exporter.exportClinicProfile(doorbell.endpoint))
    }

    private suspend fun disableLocked() {
        val doorbell = runCatching { storage.load() }.getOrNull()
        if (doorbell != null) {
            mutableState.value = ClinicSyncState.Updating
            if (guarded { wake.unregister(storage.wakeUserId, doorbell.wakeId) } == null) {
                storage.pendingRevocation = doorbell.wakeId
            }
            guarded { sender.send(doorbell.endpoint, ClinicSyncDoorbellMessages.revoke(doorbell.wakeId)) }
            storage.clear()
        }
        mutableState.value = ClinicSyncState.Disabled
    }

    private fun unavailable(reason: ClinicSyncState.Reason) {
        mutableState.value = ClinicSyncState.Unavailable(reason)
    }

    private suspend fun <T> guarded(block: suspend () -> T): T? = try {
        block()
    } catch (cancelled: CancellationException) {
        throw cancelled
    } catch (error: Exception) {
        Timber.w("Clinic sync doorbell step failed: %s", error.javaClass.simpleName)
        null
    }
}
