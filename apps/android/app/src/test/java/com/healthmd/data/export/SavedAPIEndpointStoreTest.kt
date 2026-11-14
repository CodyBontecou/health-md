package com.healthmd.data.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.SavedAPIEndpoint
import com.healthmd.domain.model.SavedAPIEndpointError
import kotlinx.coroutines.test.runTest
import org.junit.Test

/** In-memory stand-in for the encrypted file. */
class InMemorySavedEndpointPersistence : SavedAPIEndpointPersistence {
    var endpoints = emptyList<SavedAPIEndpoint>()
    val tokens = mutableMapOf<String, String>()
    override suspend fun readSavedEndpoints() = endpoints
    override suspend fun writeSavedEndpoints(endpoints: List<SavedAPIEndpoint>) { this.endpoints = endpoints }
    override suspend fun readSavedEndpointAuthorization(id: String) = tokens[id]
    override suspend fun writeSavedEndpointAuthorization(id: String, authorization: String?) {
        if (authorization == null) tokens.remove(id) else tokens[id] = authorization
    }
}

class SavedAPIEndpointStoreTest {
    private val persistence = InMemorySavedEndpointPersistence()
    private val store = SavedAPIEndpointStore(persistence)

    private suspend fun create(name: String, url: String, token: TokenChange = TokenChange.Keep) =
        (store.save(null, name, url, token) as SavedAPIEndpointResult.Saved).endpoint

    @Test
    fun createsNormalizedEndpointWithEncryptedTokenStoredSeparately() = runTest {
        val endpoint = create(" Home server ", "https://api.example.com/health", TokenChange.Set("sk-live-123"))

        assertThat(endpoint.name).isEqualTo("Home server")
        assertThat(endpoint.url).isEqualTo("https://api.example.com/health")
        assertThat(endpoint.hasToken).isTrue()
        assertThat(persistence.tokens[endpoint.id]).isEqualTo("Bearer sk-live-123")
        assertThat(persistence.endpoints).containsExactly(endpoint)
        assertThat(store.byUrl("https://api.example.com/health")).isEqualTo(endpoint)
    }

    @Test
    fun rejectsInvalidDraftsAndDuplicateUrls() = runTest {
        create("A", "https://api.example.com/health")

        assertThat(store.save(null, " ", "https://b.example.com", TokenChange.Keep))
            .isEqualTo(SavedAPIEndpointResult.Invalid(SavedAPIEndpointError.NAME_REQUIRED))
        assertThat(store.save(null, "B", "ftp://b.example.com", TokenChange.Keep))
            .isEqualTo(SavedAPIEndpointResult.Invalid(SavedAPIEndpointError.INVALID_URL))
        assertThat(store.save(null, "B", "https://api.example.com/health", TokenChange.Keep))
            .isEqualTo(SavedAPIEndpointResult.Invalid(SavedAPIEndpointError.DUPLICATE_URL))
        assertThat(store.save(null, "B", "https://b.example.com", TokenChange.Set("bad\u0001token")))
            .isEqualTo(SavedAPIEndpointResult.Invalid(SavedAPIEndpointError.INVALID_TOKEN))
        assertThat(store.save("missing", "B", "https://b.example.com", TokenChange.Keep))
            .isEqualTo(SavedAPIEndpointResult.Invalid(SavedAPIEndpointError.NOT_FOUND))
        assertThat(persistence.endpoints).hasSize(1)
    }

    @Test
    fun editKeepsReplacesOrRemovesTheTokenAndReportsThePreviousUrl() = runTest {
        val endpoint = create("A", "https://a.example.com", TokenChange.Set("one"))

        val renamed = store.save(endpoint.id, "A2", "https://a.example.com/v2", TokenChange.Keep) as SavedAPIEndpointResult.Saved
        assertThat(renamed.previousUrl).isEqualTo("https://a.example.com")
        assertThat(renamed.endpoint.id).isEqualTo(endpoint.id)
        assertThat(persistence.tokens[endpoint.id]).isEqualTo("Bearer one")

        store.save(endpoint.id, "A2", "https://a.example.com/v2", TokenChange.Set("two"))
        assertThat(persistence.tokens[endpoint.id]).isEqualTo("Bearer two")

        val removed = store.save(endpoint.id, "A2", "https://a.example.com/v2", TokenChange.Remove) as SavedAPIEndpointResult.Saved
        assertThat(removed.endpoint.hasToken).isFalse()
        assertThat(persistence.tokens).doesNotContainKey(endpoint.id)
        // Editing may keep its own URL without tripping the duplicate check.
        assertThat(store.save(endpoint.id, "A3", "https://a.example.com/v2", TokenChange.Keep))
            .isInstanceOf(SavedAPIEndpointResult.Saved::class.java)
    }

    @Test
    fun deleteRemovesTheEndpointAndItsToken() = runTest {
        val a = create("A", "https://a.example.com", TokenChange.Set("one"))
        val b = create("B", "https://b.example.com")

        assertThat(store.delete(a.id)).isEqualTo(a)
        assertThat(persistence.endpoints).containsExactly(b)
        assertThat(persistence.tokens).doesNotContainKey(a.id)
        assertThat(store.delete(a.id)).isNull()
    }

    @Test
    fun reloadsFromPersistence() = runTest {
        create("A", "https://a.example.com")
        val fresh = SavedAPIEndpointStore(persistence)
        assertThat(fresh.load().map { it.name }).containsExactly("A")
    }
}
