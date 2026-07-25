package com.healthmd.rawchanges

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.changes.DeletionChange
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.request.ChangesTokenRequest
import androidx.health.connect.client.response.ChangesResponse
import com.google.common.truth.Truth.assertThat
import io.mockk.coEvery
import io.mockk.mockk
import io.mockk.slot
import kotlinx.coroutines.test.runTest
import org.junit.Test

class HealthConnectChangesSourceTest {
    @Test fun usesPinnedSdkTokenApiWithExactTypesAndOriginsThenPaginates() = runTest {
        val client = mockk<HealthConnectClient>()
        val request = slot<ChangesTokenRequest>()
        coEvery { client.getChangesToken(capture(request)) } returns "opaque-initial"
        coEvery { client.getChanges("opaque-initial") } returns ChangesResponse(
            changes = listOf(DeletionChange("deleted-id")),
            nextChangesToken = "opaque-next",
            hasMore = false,
            changesTokenExpired = false,
        )
        val source = HealthConnectChangesSource(mockk<Context>(), client)
        val token = source.createToken(RawChangesScope(setOf("steps"), setOf("origin.example")))
        val page = source.getChanges(token)

        assertThat(request.captured.recordTypes).containsExactly(StepsRecord::class)
        assertThat(request.captured.dataOriginFilters.map { it.packageName }).containsExactly("origin.example")
        assertThat(page.changes).containsExactly(NativeChange.Delete("deleted-id"))
        assertThat(page.nextToken).isEqualTo(SecretChangesToken("opaque-next"))
        assertThat(page.hasMore).isFalse()
    }

    @Test fun sdkExpiredOrInvalidTokenMapsOnlyToExplicitRebaseSignal() = runTest {
        val client = mockk<HealthConnectClient>()
        coEvery { client.getChanges("expired") } returns ChangesResponse(emptyList(), "", false, true)
        val page = HealthConnectChangesSource(mockk<Context>(), client).getChanges(SecretChangesToken("expired"))
        assertThat(page.tokenExpired).isTrue()
        assertThat(page.nextToken).isNull()
        assertThat(page.changes).isEmpty()
    }

    @Test fun providerExceptionCannotRetainTokenEchoMessageOrCause() = runTest {
        val secret = "provider-echoed-secret-token"
        val client = mockk<HealthConnectClient>()
        coEvery { client.getChanges(secret) } throws IllegalArgumentException("invalid token=$secret")
        val error = runCatching {
            HealthConnectChangesSource(mockk<Context>(), client).getChanges(SecretChangesToken(secret))
        }.exceptionOrNull()
        assertThat(error).isInstanceOf(RawChangesProviderException::class.java)
        assertThat(error!!.message).doesNotContain(secret)
        assertThat(error.cause).isNull()
    }
}
