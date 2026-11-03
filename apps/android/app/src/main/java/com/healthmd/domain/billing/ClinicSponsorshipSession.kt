package com.healthmd.domain.billing

import java.util.UUID
import java.security.SecureRandom
import java.util.Base64
import kotlinx.serialization.Serializable
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json

/** A single atomically persisted secure record; never export this with settings or diagnostics. */
@Serializable
data class ClinicSponsorshipRecord(
    val installationID: String,
    val grantToken: String? = null,
    val refreshToken: String? = null,
    val clinicName: String? = null,
    val consentBinding: String? = null,
    val uploadAuthorization: String? = null,
    val pendingEnrollment: ClinicPendingEnrollment? = null,
    val highestObservedMilliseconds: Long = 0,
)

@Serializable
data class ClinicPendingEnrollment(val invitationCode: String, val enrollmentSecret: String)

interface ClinicSponsorshipStorage {
    /** Failure must throw; corrupt/unavailable storage must never silently create a new identity. */
    fun read(): String?
    fun write(value: String)
}

/** Pure session authority; callers serialize mutations. Verified grant bytes are rechecked on every use. */
class ClinicSponsorshipSession(
    private val storage: ClinicSponsorshipStorage,
    private val verifier: ClinicGrantVerifier,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val json = Json { ignoreUnknownKeys = false }
    private var record = storage.read()?.let { json.decodeFromString<ClinicSponsorshipRecord>(it) }
        ?: ClinicSponsorshipRecord(UUID.randomUUID().toString()).also(::persist)

    val installationID: String get() = record.installationID
    val refreshToken: String? get() = record.refreshToken
    val clinicName: String? get() = record.clinicName
    val pendingEnrollment: ClinicPendingEnrollment? get() = record.pendingEnrollment

    fun beginEnrollment(code: String): ClinicPendingEnrollment {
        require(code.matches(Regex("[A-Za-z0-9_-]{32,128}")))
        record.pendingEnrollment?.let { require(it.invitationCode == code); return it }
        val bytes = ByteArray(32).also { SecureRandom().nextBytes(it) }
        val pending = ClinicPendingEnrollment(code, Base64.getUrlEncoder().withoutPadding().encodeToString(bytes))
        replace(record.copy(pendingEnrollment = pending))
        return pending
    }

    fun cancelEnrollment(secret: String) {
        if (record.pendingEnrollment?.enrollmentSecret == secret) replace(record.copy(pendingEnrollment = null))
    }

    private fun persist(value: ClinicSponsorshipRecord) {
        storage.write(json.encodeToString(value))
    }

    private fun replace(value: ClinicSponsorshipRecord) {
        persist(value)
        record = value
    }

    private fun now(): Long {
        val current = maxOf(clock(), record.highestObservedMilliseconds)
        require(current >= 0)
        if (current > record.highestObservedMilliseconds) replace(record.copy(highestObservedMilliseconds = current))
        return current
    }

    fun grant(): ClinicExportGrant? = record.grantToken?.let {
        verifier.verify(it, installationID, now())
    }

    fun accept(grantToken: String, refreshToken: String?, clinicName: String, completingEnrollmentSecret: String? = null) {
        require(completingEnrollmentSecret == null || record.pendingEnrollment?.enrollmentSecret == completingEnrollmentSecret)
        require(clinicName.length in 1..120 && clinicName.none { it.code < 32 })
        val verified = requireNotNull(verifier.verify(grantToken, installationID, now())) { "invalid_grant" }
        val credential = refreshToken ?: record.refreshToken
        require(credential != null && credential.matches(Regex("[A-Za-z0-9_-]{32,128}")))
        val old = grant()
        val retainedConsent = record.consentBinding.takeIf { old != null && binding(old) == binding(verified) }
        replace(record.copy(grantToken = grantToken, refreshToken = credential,
            clinicName = clinicName, consentBinding = retainedConsent,
            pendingEnrollment = if (completingEnrollmentSecret != null) null else record.pendingEnrollment,
            uploadAuthorization = record.uploadAuthorization.takeIf { old != null && binding(old) == binding(verified) }))
    }

    fun setSharingAuthorized(authorized: Boolean) {
        val binding = if (authorized) binding(requireNotNull(grant()) { "sponsorship_inactive" }) else null
        replace(record.copy(consentBinding = binding))
    }

    fun authorize(endpoint: String): ClinicExportDecision {
        val grant = grant()
        return ClinicExportAuthorization.decide(false, grant,
            ClinicExportRequest(true, grant?.clinicID, grant?.destinationID, grant?.policyVersion, endpoint,
                grant != null && record.consentBinding == binding(grant)), now())
    }

    fun setUploadAuthorization(value: String) {
        require(grant() != null && value.length <= 4096 && value.all { it.code in 32..126 })
        replace(record.copy(uploadAuthorization = value.takeIf { it.isNotEmpty() }))
    }

    fun uploadAuthorization(endpoint: String): String? =
        record.uploadAuthorization.takeIf { authorize(endpoint) == ClinicExportDecision.ALLOWED_CLINIC_DESTINATION }

    /** Local disconnection takes effect even if the network is unavailable. Identity is retained. */
    fun disconnect() = replace(ClinicSponsorshipRecord(installationID,
        highestObservedMilliseconds = record.highestObservedMilliseconds))

    private fun binding(grant: ClinicExportGrant): String = json.encodeToString(listOf(
        grant.clinicID, grant.destinationID, grant.policyVersion.toString(),
        requireNotNull(ClinicExportAuthorization.canonicalClinicEndpoint(grant.endpoint))))
}
