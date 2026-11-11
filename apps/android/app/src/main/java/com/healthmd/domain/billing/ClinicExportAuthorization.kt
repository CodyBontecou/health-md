package com.healthmd.domain.billing

/** Verified by the licensing adapter (signature, audience, installation) before policy evaluation. */
data class ClinicExportGrant(
    val clinicID: String,
    val destinationID: String,
    val policyVersion: Int,
    val endpoint: String,
    val issuedAtMilliseconds: Long,
    val expiresAtMilliseconds: Long,
    val revoked: Boolean,
)

data class ClinicExportRequest(
    val isDirectClinicDelivery: Boolean,
    val clinicID: String?,
    val destinationID: String?,
    val policyVersion: Int?,
    val endpoint: String?,
    val sharingAuthorized: Boolean,
)

enum class ClinicExportDecision(val wireValue: String) {
    ALLOWED_PERSONAL("allowed_personal"),
    ALLOWED_CLINIC_DESTINATION("allowed_clinic_destination"),
    BLOCKED_ACCESS_EXPIRED("blocked_access_expired"),
    BLOCKED_DESTINATION_NOT_PERMITTED("blocked_destination_not_permitted"),
    BLOCKED_SHARING_NOT_AUTHORIZED("blocked_sharing_not_authorized");

    val isAllowed: Boolean get() = this == ALLOWED_PERSONAL || this == ALLOWED_CLINIC_DESTINATION
}

/** Licensing only; health permissions and credential destination scope are enforced separately. */
object ClinicExportAuthorization {
    const val MAXIMUM_GRANT_DURATION_MILLISECONDS = 7L * 24 * 60 * 60 * 1_000

    fun decide(
        independentAccess: Boolean,
        grant: ClinicExportGrant?,
        request: ClinicExportRequest,
        nowMilliseconds: Long,
    ): ClinicExportDecision {
        if (independentAccess) return ClinicExportDecision.ALLOWED_PERSONAL
        if (grant == null || grant.revoked || nowMilliseconds < 0 ||
            grant.issuedAtMilliseconds < 0 || grant.issuedAtMilliseconds > nowMilliseconds ||
            grant.expiresAtMilliseconds <= nowMilliseconds ||
            grant.expiresAtMilliseconds - grant.issuedAtMilliseconds > MAXIMUM_GRANT_DURATION_MILLISECONDS
        ) return ClinicExportDecision.BLOCKED_ACCESS_EXPIRED

        val approved = canonicalClinicEndpoint(grant.endpoint)
        val requested = request.endpoint?.let(::canonicalClinicEndpoint)
        if (!request.isDirectClinicDelivery || grant.clinicID.isEmpty() || grant.destinationID.isEmpty() ||
            grant.policyVersion <= 0 || request.clinicID != grant.clinicID ||
            request.destinationID != grant.destinationID || request.policyVersion != grant.policyVersion ||
            approved == null || requested == null || approved != requested
        ) return ClinicExportDecision.BLOCKED_DESTINATION_NOT_PERMITTED
        if (!request.sharingAuthorized) return ClinicExportDecision.BLOCKED_SHARING_NOT_AUTHORIZED
        return ClinicExportDecision.ALLOWED_CLINIC_DESTINATION
    }

    private val endpointPattern = Regex(
        "^https://([A-Za-z0-9](?:[A-Za-z0-9.-]*[A-Za-z0-9])?)(?::([0-9]{1,5}))?(/[A-Za-z0-9._~!\$&'()*+,;=:@/-]*)?\$",
        RegexOption.IGNORE_CASE,
    )

    /** Shared strict URL grammar; upload clients must reject redirects and bind credentials. */
    fun canonicalClinicEndpoint(value: String): String? {
        if (value.any { it.code !in 33..126 }) return null
        val match = endpointPattern.matchEntire(value) ?: return null
        val host = match.groupValues[1].lowercase(java.util.Locale.ROOT)
        val labels = host.split('.')
        if (host.length > 253 || labels.size < 2 ||
            labels.any { it.isEmpty() || it.length > 63 || it.startsWith('-') || it.endsWith('-') } ||
            labels.all { label -> label.all { it in '0'..'9' } }
        ) return null
        val port = match.groupValues[2].takeIf { it.isNotEmpty() }?.toIntOrNull() ?: 443
        if (port !in 1..65535) return null
        val path = match.groupValues[3].ifEmpty { "/" }
        if (path.split('/').any { it == "." || it == ".." } || path.contains("//")) return null
        return "https://$host${if (port == 443) "" else ":$port"}$path"
    }
}
