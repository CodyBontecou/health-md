package com.healthmd.data.export

import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.SavedAPIEndpoint
import com.healthmd.domain.model.SavedAPIEndpointError
import com.healthmd.domain.model.SavedAPIEndpointRules
import java.util.UUID
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

/**
 * Encrypted persistence for saved endpoints. Production is [EncryptedAPIExportCredentialStore]
 * (one Android Keystore-backed file shared with the legacy API credentials), so the request
 * builder can resolve a saved endpoint's token from the URL it is about to send to.
 */
interface SavedAPIEndpointPersistence {
    suspend fun readSavedEndpoints(): List<SavedAPIEndpoint>
    suspend fun writeSavedEndpoints(endpoints: List<SavedAPIEndpoint>)
    /** The normalized Authorization value, or null when the endpoint has none. */
    suspend fun readSavedEndpointAuthorization(id: String): String?
    /** Stores a normalized Authorization value; null removes it. */
    suspend fun writeSavedEndpointAuthorization(id: String, authorization: String?)
}

sealed interface SavedAPIEndpointResult {
    data class Saved(val endpoint: SavedAPIEndpoint, val previousUrl: String?) : SavedAPIEndpointResult
    data class Invalid(val error: SavedAPIEndpointError) : SavedAPIEndpointResult
}

/** What to do with the stored token when an endpoint is saved. */
sealed interface TokenChange {
    data object Keep : TokenChange
    data object Remove : TokenChange
    data class Set(val raw: String) : TokenChange
}

/** The saved-endpoint list. Profile rebinding on edit/delete is [SavedAPIEndpointCoordinator]'s job. */
@Singleton
class SavedAPIEndpointStore @Inject constructor(
    private val persistence: SavedAPIEndpointPersistence,
) {
    private val mutex = Mutex()
    private val _endpoints = MutableStateFlow<List<SavedAPIEndpoint>>(emptyList())
    val endpoints: StateFlow<List<SavedAPIEndpoint>> = _endpoints.asStateFlow()
    private var loaded = false

    suspend fun load(): List<SavedAPIEndpoint> = mutex.withLock { loadLocked() }

    private suspend fun loadLocked(): List<SavedAPIEndpoint> {
        if (!loaded) {
            _endpoints.value = persistence.readSavedEndpoints()
            loaded = true
        }
        return _endpoints.value
    }

    suspend fun byId(id: String): SavedAPIEndpoint? = load().firstOrNull { it.id == id }

    suspend fun byUrl(url: String?): SavedAPIEndpoint? = SavedAPIEndpointRules.byUrl(load(), url)

    suspend fun authorization(id: String): String? = persistence.readSavedEndpointAuthorization(id)

    /** Creates ([editingId] null) or updates an endpoint. Untested endpoints may be saved. */
    suspend fun save(
        editingId: String?,
        name: String,
        url: String,
        token: TokenChange,
        now: Long = System.currentTimeMillis(),
    ): SavedAPIEndpointResult = mutex.withLock {
        val existing = loadLocked()
        val raw = (token as? TokenChange.Set)?.raw.orEmpty()
        SavedAPIEndpointRules.validate(name, url, raw, existing, editingId) { APIExportAuthorization.normalizeOrNull(it) != null }
            ?.let { return@withLock SavedAPIEndpointResult.Invalid(it) }
        val normalizedUrl = requireNotNull(APIExportEndpoint.normalizedOrNull(url))
        val previous = editingId?.let { id -> existing.firstOrNull { it.id == id } }
        if (editingId != null && previous == null) {
            return@withLock SavedAPIEndpointResult.Invalid(SavedAPIEndpointError.NOT_FOUND)
        }
        val id = previous?.id ?: UUID.randomUUID().toString()
        val hasToken = when (token) {
            TokenChange.Keep -> previous?.hasToken ?: false
            TokenChange.Remove -> false
            is TokenChange.Set -> token.raw.isNotBlank() || (previous?.hasToken ?: false)
        }
        when (token) {
            TokenChange.Keep -> Unit
            TokenChange.Remove -> persistence.writeSavedEndpointAuthorization(id, null)
            is TokenChange.Set -> if (token.raw.isNotBlank()) {
                persistence.writeSavedEndpointAuthorization(id, APIExportAuthorization.normalizeOrNull(token.raw))
            }
        }
        val endpoint = SavedAPIEndpoint(
            id = id,
            name = SavedAPIEndpointRules.normalizedName(name),
            url = normalizedUrl,
            hasToken = hasToken,
            createdAtEpochMillis = previous?.createdAtEpochMillis ?: now,
            updatedAtEpochMillis = now,
        )
        val updated = if (previous == null) existing + endpoint else existing.map { if (it.id == id) endpoint else it }
        persistence.writeSavedEndpoints(updated)
        _endpoints.value = updated
        SavedAPIEndpointResult.Saved(endpoint, previousUrl = previous?.url)
    }

    /** Removes the endpoint and its token. Returns the removed endpoint. */
    suspend fun delete(id: String): SavedAPIEndpoint? = mutex.withLock {
        val existing = loadLocked()
        val removed = existing.firstOrNull { it.id == id } ?: return@withLock null
        val updated = existing.filterNot { it.id == id }
        persistence.writeSavedEndpoints(updated)
        persistence.writeSavedEndpointAuthorization(id, null)
        _endpoints.value = updated
        removed
    }
}
