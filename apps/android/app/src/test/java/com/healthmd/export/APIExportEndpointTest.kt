package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIExportDestinationFingerprint
import com.healthmd.data.export.APIExportHeaders
import com.healthmd.data.export.APIExportRequestHeader
import com.healthmd.data.export.EncryptedAPIExportCredentialStore
import com.healthmd.domain.model.APIExportEndpoint
import org.junit.Test

class APIExportEndpointTest {
    @Test
    fun acceptsHttpAndHttpsAndRedactsQueryParameters() {
        val httpsUrl = "https://api.example.com:8443/health/ingest?key=secret"
        val httpUrl = "http://localhost:8080/health/ingest?key=secret"

        assertThat(APIExportEndpoint.isConfigured(httpsUrl)).isTrue()
        assertThat(APIExportEndpoint.displayName(httpsUrl)).isEqualTo("api.example.com")
        assertThat(APIExportEndpoint.redactedDescription(httpsUrl))
            .isEqualTo("https://api.example.com:8443/health/ingest")
        assertThat(APIExportEndpoint.isConfigured(httpUrl)).isTrue()
        assertThat(APIExportEndpoint.redactedDescription(httpUrl))
            .isEqualTo("http://localhost:8080/health/ingest")
    }

    @Test
    fun rejectsUnsafeDestinations() {
        assertThat(APIExportEndpoint.isConfigured("ftp://api.example.com/health")).isFalse()
        assertThat(APIExportEndpoint.isConfigured("https://user:pass@api.example.com/health")).isFalse()
        assertThat(APIExportEndpoint.isConfigured("https://api.example.com/health#fragment")).isFalse()
        assertThat(APIExportEndpoint.isConfigured("https://api.example.com/health\r\nInjected: yes")).isFalse()
    }

    @Test
    fun parsesRawRequestHeaders() {
        val headers = APIExportHeaders.parse(
            "Authorization: Token custom-secret\nX-API-Key: another-secret\nX-Empty:"
        )

        assertThat(headers.map { it.name }).containsExactly("Authorization", "X-API-Key", "X-Empty").inOrder()
        assertThat(headers[0].value).isEqualTo("Token custom-secret")
        assertThat(headers[2].value).isEmpty()
    }

    @Test
    fun rejectsUnsafeOrAmbiguousRawRequestHeaders() {
        assertThat(runCatching { APIExportHeaders.parse("Host: attacker.example") }.exceptionOrNull())
            .isInstanceOf(IllegalArgumentException::class.java)
        assertThat(runCatching { APIExportHeaders.parse("Content-Type: text/plain") }.exceptionOrNull())
            .isInstanceOf(IllegalArgumentException::class.java)
        assertThat(runCatching { APIExportHeaders.parse("X-Key: one\nx-key: two") }.exceptionOrNull())
            .isInstanceOf(IllegalArgumentException::class.java)
        assertThat(runCatching { APIExportHeaders.parse("Invalid line") }.exceptionOrNull())
            .isInstanceOf(IllegalArgumentException::class.java)
        assertThat(runCatching { APIExportHeaders.parse("X-Key: safe\r\nInjected: yes") }.exceptionOrNull())
            .isInstanceOf(IllegalArgumentException::class.java)
        assertThat(runCatching { APIExportHeaders.parse("X-Key: café") }.exceptionOrNull())
            .isInstanceOf(IllegalArgumentException::class.java)
    }

    @Test
    fun destinationFingerprintChangesWithCredentialsAndRoutingHeaders() {
        val salt = ByteArray(32) { it.toByte() }
        val endpoint = "https://api.example.com/healthmd"
        val first = APIExportDestinationFingerprint.create(
            salt = salt,
            endpointUrl = endpoint,
            authorizationHeader = "Bearer one",
            requestHeaders = listOf(APIExportRequestHeader("X-Tenant", "alpha")),
        )
        val sameWithDifferentHeaderCase = APIExportDestinationFingerprint.create(
            salt = salt,
            endpointUrl = endpoint,
            authorizationHeader = "Bearer one",
            requestHeaders = listOf(APIExportRequestHeader("x-tenant", "alpha")),
        )
        val changedCredential = APIExportDestinationFingerprint.create(
            salt = salt,
            endpointUrl = endpoint,
            authorizationHeader = "Bearer two",
            requestHeaders = listOf(APIExportRequestHeader("X-Tenant", "alpha")),
        )
        val changedTenant = APIExportDestinationFingerprint.create(
            salt = salt,
            endpointUrl = endpoint,
            authorizationHeader = "Bearer one",
            requestHeaders = listOf(APIExportRequestHeader("X-Tenant", "beta")),
        )

        assertThat(first).isEqualTo(sameWithDifferentHeaderCase)
        assertThat(changedCredential).isNotEqualTo(first)
        assertThat(changedTenant).isNotEqualTo(first)
    }

    @Test
    fun normalizesAuthorizationValues() {
        assertThat(EncryptedAPIExportCredentialStore.normalizeAuthorization("secret"))
            .isEqualTo("Bearer secret")
        assertThat(EncryptedAPIExportCredentialStore.normalizeAuthorization("Basic abc123"))
            .isEqualTo("Basic abc123")
        assertThat(EncryptedAPIExportCredentialStore.normalizeAuthorization("Bearer abc123"))
            .isEqualTo("Bearer abc123")
        assertThat(EncryptedAPIExportCredentialStore.normalizeAuthorization("bad\nheader"))
            .isNull()
        assertThat(EncryptedAPIExportCredentialStore.normalizeAuthorization("Bearer café"))
            .isNull()
    }
}
