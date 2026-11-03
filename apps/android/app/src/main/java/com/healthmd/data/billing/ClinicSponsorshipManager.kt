package com.healthmd.data.billing

import com.healthmd.BuildConfig
import com.healthmd.domain.billing.*
import java.util.Base64
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.*
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

data class ClinicSponsorshipStatus(
    val configured: Boolean = false,
    val active: Boolean = false,
    val clinicName: String? = null,
    val endpoint: String? = null,
    val sharingAuthorized: Boolean = false,
    val storageUnavailable: Boolean = false,
    val enrollmentPending: Boolean = false,
)

@Singleton
class ClinicSponsorshipManager internal constructor(
    private val storage: ClinicSponsorshipStorage,
    private val configuration: ClinicLicensingConfiguration?,
    private val client: ClinicLicensingAPI? = configuration?.let { ClinicLicensingClient(it) },
    private val scope: CoroutineScope = CoroutineScope(SupervisorJob() + Dispatchers.Default),
    private val sessionClock: () -> Long = System::currentTimeMillis,
) {
    @Inject constructor(storage: EncryptedClinicSponsorshipStorage) : this(storage, bundledConfiguration())

    companion object {
        private fun bundledConfiguration() = runCatching {
            if (BuildConfig.CLINIC_LICENSING_URL.isEmpty()) null else ClinicLicensingConfiguration(
                BuildConfig.CLINIC_LICENSING_URL,
                BuildConfig.CLINIC_LICENSING_ISSUER,
                "healthmd-clinic-access",
                if (BuildConfig.CLINIC_LICENSING_TRUSTED_KEYS_JSON.isNotEmpty()) {
                    Json.parseToJsonElement(BuildConfig.CLINIC_LICENSING_TRUSTED_KEYS_JSON).jsonObject
                        .also { require(it.size in 1..4) }
                        .mapValues { Base64.getDecoder().decode(it.value.jsonPrimitive.content) }
                } else mapOf(BuildConfig.CLINIC_LICENSING_KEY_ID to
                    Base64.getDecoder().decode(BuildConfig.CLINIC_LICENSING_PUBLIC_KEY_DER)))
        }.getOrNull()
    }

    private val lock = Any()
    private var revision = 0L
    private var disconnectPending = false
    private val refreshMutex = Mutex()
    private var session = configuration?.let { runCatching { ClinicSponsorshipSession(storage, it.verifier(), sessionClock) }.getOrNull() }
    private val mutableStatus = MutableStateFlow(ClinicSponsorshipStatus(configured = configuration != null))
    val status = mutableStatus.asStateFlow()

    init {
        synchronized(lock) { publish() }
        scope.launch { while (isActive) { delay(30_000); synchronized(lock) { publish() } } }
    }

    private fun recoverStorage() {
        if (disconnectPending) {
            try { session?.disconnect(); disconnectPending = false } catch (_: Exception) { return }
        }
        if (session == null) session = configuration?.let {
            runCatching { ClinicSponsorshipSession(storage, it.verifier(), sessionClock) }.getOrNull()
        }
    }

    private fun publish() {
        if (disconnectPending) {
            mutableStatus.value = ClinicSponsorshipStatus(configured = configuration != null, storageUnavailable = true)
            return
        }
        val current = session
        val grant = runCatching { current?.grant() }.getOrElse {
            mutableStatus.value = ClinicSponsorshipStatus(configured = true, storageUnavailable = true)
            return
        }
        mutableStatus.value = ClinicSponsorshipStatus(configuration != null, grant != null,
            current?.clinicName, grant?.endpoint,
            grant != null && current?.authorize(grant.endpoint)?.isAllowed == true,
            configuration != null && current == null, current?.pendingEnrollment != null)
    }

    suspend fun enroll(code: String) {
        synchronized(lock) {
            recoverStorage()
            check(!disconnectPending)
            checkNotNull(session).beginEnrollment(code)
            ++revision
            publish()
        }
        resumeEnrollment()
    }

    suspend fun resumeEnrollment() {
        val pending = synchronized(lock) {
            if (disconnectPending) return
            val current = session ?: return
            val enrollment = current.pendingEnrollment ?: return
            Triple(enrollment, current.installationID, revision)
        }
        try {
            val reply = checkNotNull(client).redeem(pending.first.invitationCode, pending.second,
                pending.first.enrollmentSecret)
            synchronized(lock) {
                check(pending.third == revision) { "enrollment_cancelled" }
                session?.accept(reply.grant, pending.first.enrollmentSecret, reply.clinicName,
                    pending.first.enrollmentSecret)
                publish()
            }
        } catch (error: Exception) {
            if (error is CancellationException) throw error
            synchronized(lock) {
                if (pending.third == revision && error is ClinicLicensingException && error.inactive) {
                    session?.cancelEnrollment(pending.first.enrollmentSecret)
                    publish()
                }
            }
            throw error
        }
    }

    suspend fun refresh() = refreshMutex.withLock { performRefresh() }

    private suspend fun performRefresh() {
        val recovering = synchronized(lock) { recoverStorage(); publish(); session?.pendingEnrollment != null }
        if (recovering) {
            try { resumeEnrollment() } catch (error: Exception) { if (error is CancellationException) throw error }
            return
        }
        val pending = synchronized(lock) {
            recoverStorage()
            publish()
            if (disconnectPending) return
            val current = session ?: return
            val token = current.refreshToken ?: return
            Triple(token, current.installationID, revision)
        }
        try {
            val reply = checkNotNull(client).refresh(pending.first, pending.second)
            synchronized(lock) {
                if (pending.third != revision) return
                session?.accept(reply.grant, null, reply.clinicName)
                publish()
            }
        } catch (error: Exception) {
            if (error is kotlinx.coroutines.CancellationException) throw error
            synchronized(lock) {
                if (pending.third != revision) return
                if (error is ClinicLicensingException && error.inactive) {
                    ++revision
                    try { session?.disconnect() } catch (_: Exception) { disconnectPending = true }
                }
                publish()
            }
        }
    }

    fun setSharingAuthorized(authorized: Boolean) = synchronized(lock) {
        checkNotNull(session).setSharingAuthorized(authorized)
        publish()
    }

    fun setUploadAuthorization(value: String) = synchronized(lock) {
        checkNotNull(session).setUploadAuthorization(value)
    }

    fun uploadAuthorization(endpoint: String): String? = synchronized(lock) {
        if (disconnectPending) null else runCatching { session?.uploadAuthorization(endpoint) }.getOrNull()
    }

    fun authorizeCached(endpoint: String): ClinicExportDecision = synchronized(lock) {
        if (disconnectPending) return ClinicExportDecision.BLOCKED_ACCESS_EXPIRED
        try {
            val decision = session?.authorize(endpoint) ?: ClinicExportDecision.BLOCKED_ACCESS_EXPIRED
            publish()
            decision
        } catch (_: Exception) { ClinicExportDecision.BLOCKED_ACCESS_EXPIRED }
    }

    suspend fun disconnect() {
        val pending = synchronized(lock) {
            val current = session ?: return
            val credential = listOfNotNull(current.refreshToken, current.pendingEnrollment?.enrollmentSecret).distinct() to current.installationID
            ++revision
            try { current.disconnect() }
            catch (error: Exception) { disconnectPending = true; publish(); throw error }
            publish()
            credential
        }
        pending.first.forEach { token ->
            try { client?.disconnect(token, pending.second) }
            catch (error: Exception) { if (error is kotlinx.coroutines.CancellationException) throw error }
        }
    }
}
