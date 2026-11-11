package com.healthmd.domain.model

import com.google.common.truth.Truth.assertThat
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Test

class HealthProviderCaptureAuthorityTest {
    private val grant = "00000000-0000-4000-8000-000000000201"
    private val accepted = HealthProviderCaptureAuthority(selectedProviderId = "whoop", providerIds = listOf("whoop"),
        connectionIds = mapOf("whoop" to grant))

    @Test
    fun missingUnavailableEntryIsDifferentFromExplicitNull() {
        assertThat(accepted.copy(connectionIds = mapOf("whoop" to null)).validatedCopy().connectionIds)
            .containsEntry("whoop", null)
        assertInvalid(accepted.copy(connectionIds = emptyMap()))
        assertInvalid(accepted.copy(connectionIds = mapOf("whoop" to grant, "oura" to null)))
    }

    @Test
    fun malformedAndUnknownVersionsCannotGainAuthority() {
        listOf(accepted.copy(version = 2), accepted.copy(selectedProviderId = "health_connect"),
            accepted.copy(providerIds = listOf("whoop", "whoop")),
            accepted.copy(providerIds = listOf("../whoop")),
            accepted.copy(connectionIds = mapOf("whoop" to "secret-token")),
            accepted.copy(connectionIds = mapOf("whoop" to "00000000-0000-4000-8000-00000000020A")))
            .forEach(::assertInvalid)
        val unsupported = Json.decodeFromString<HealthProviderCaptureAuthority>(
            Json.encodeToString(accepted).replace("\"version\":1", "\"version\":2"))
        assertInvalid(unsupported)
        assertThat(runCatching {
            Json.decodeFromString<HealthProviderCaptureAuthority>(Json.encodeToString(accepted).replace("\"version\":1,", ""))
        }.isFailure).isTrue()
    }

    @Test
    fun acceptedCollectionsDoNotFollowCallerMutation() {
        val ids = mutableListOf("whoop")
        val grants = mutableMapOf<String, String?>("whoop" to grant)
        val frozen = accepted.copy(providerIds = ids, connectionIds = grants).validatedCopy()
        ids.clear()
        grants["whoop"] = null
        assertThat(frozen.providerIds).containsExactly("whoop")
        assertThat(frozen.connectionIds).containsEntry("whoop", grant)
        assertThat(Json.decodeFromString<HealthProviderCaptureAuthority>(Json.encodeToString(frozen)).validatedCopy())
            .isEqualTo(frozen)
    }

    private fun assertInvalid(value: HealthProviderCaptureAuthority) {
        assertThat(runCatching { value.validatedCopy() }.exceptionOrNull()).isInstanceOf(IllegalArgumentException::class.java)
    }
}
