package com.healthmd.domain.model

import kotlinx.serialization.Serializable

/**
 * A reusable API destination: a display name and a normalized HTTPS URL. Its optional
 * Authorization value lives encrypted beside it and never appears in this model.
 *
 * Automations bind an endpoint by URL ([ExportProfile.apiEndpointUrl]); URLs are unique among
 * saved endpoints, so the binding is unambiguous and the export profile schema is unchanged.
 */
@Serializable
data class SavedAPIEndpoint(
    val id: String,
    val name: String,
    val url: String,
    val hasToken: Boolean = false,
    val createdAtEpochMillis: Long = 0,
    val updatedAtEpochMillis: Long = 0,
)

enum class SavedAPIEndpointError { NAME_REQUIRED, INVALID_URL, DUPLICATE_URL, INVALID_TOKEN, NOT_FOUND }

/** Pure rules shared by the store, the sheet and the tests. */
object SavedAPIEndpointRules {
    const val DEFAULT_NAME = "My API"
    const val MAX_NAME_LENGTH = 60

    /**
     * Validates a draft. [token] blank means "no token" (or "keep" when editing). Saving is
     * allowed whether or not a connection test passed; only the draft itself is checked.
     */
    fun validate(
        name: String,
        url: String,
        token: String,
        existing: List<SavedAPIEndpoint>,
        editingId: String? = null,
        tokenValidator: (String) -> Boolean,
    ): SavedAPIEndpointError? {
        if (name.trim().isEmpty()) return SavedAPIEndpointError.NAME_REQUIRED
        val normalized = APIExportEndpoint.normalizedOrNull(url) ?: return SavedAPIEndpointError.INVALID_URL
        if (existing.any { it.id != editingId && it.url == normalized }) return SavedAPIEndpointError.DUPLICATE_URL
        if (token.isNotBlank() && !tokenValidator(token)) return SavedAPIEndpointError.INVALID_TOKEN
        return null
    }

    fun normalizedName(name: String): String = name.trim().take(MAX_NAME_LENGTH)

    /** True when [profile] sends to [endpoint]. */
    fun uses(profile: ExportProfile, endpoint: SavedAPIEndpoint): Boolean =
        profile.target == ExportTarget.API_ENDPOINT &&
            profile.apiEndpointUrl?.let(APIExportEndpoint::normalizedOrNull) == endpoint.url

    fun profilesUsing(endpoint: SavedAPIEndpoint, profiles: List<ExportProfile>): List<ExportProfile> =
        profiles.filter { uses(it, endpoint) }

    fun byUrl(endpoints: List<SavedAPIEndpoint>, url: String?): SavedAPIEndpoint? {
        val normalized = url?.let(APIExportEndpoint::normalizedOrNull) ?: return null
        return endpoints.firstOrNull { it.url == normalized }
    }

    /** "api.example.com/health": host and path, never query strings or credentials. */
    fun displayUrl(url: String): String = APIExportEndpoint.redactedDescription(url)
        .removePrefix("https://").removePrefix("http://").trimEnd('/')
}
