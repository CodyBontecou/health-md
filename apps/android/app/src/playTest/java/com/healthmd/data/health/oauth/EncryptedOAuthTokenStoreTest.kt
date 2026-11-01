package com.healthmd.data.health.oauth

import android.content.Context
import android.content.SharedPreferences
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import java.util.UUID
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35], manifest = Config.NONE)
class EncryptedOAuthTokenStoreTest {
    private fun preferences(): SharedPreferences = ApplicationProvider.getApplicationContext<Context>()
        .getSharedPreferences("credential-authority-${UUID.randomUUID()}", Context.MODE_PRIVATE)

    @Test
    fun reloadAndRotationPreserveAuthorityButNewGrantAndStaleRotationDoNot() = runTest {
        val preferences = preferences()
        val first = EncryptedOAuthTokenStore(preferences)
        val other = EncryptedOAuthTokenStore(preferences)
        val original = OAuthToken("whoop", "original", "refresh")
        first.saveToken(original)
        val accepted = requireNotNull(first.getCredential("whoop"))
        assertThat(other.getCredential("whoop")).isEqualTo(accepted)
        val rotated = original.copy(accessToken = "rotated", refreshToken = "rotated-refresh")
        assertThat(other.saveRotatedToken(rotated, accepted)).isTrue()
        assertThat(first.getCredential("whoop")?.connectionId).isEqualTo(accepted.connectionId)
        assertThat(first.getToken("whoop")).isEqualTo(rotated)
        assertThat(first.saveRotatedToken(original, accepted)).isFalse()
        other.saveToken(original)
        assertThat(first.getCredential("whoop")?.connectionId).isNotEqualTo(accepted.connectionId)
        assertThat(first.saveRotatedToken(rotated, accepted)).isFalse()
        assertThat(first.getToken("whoop")).isEqualTo(original)
    }

    @Test
    fun legacyFlatTokenMigratesOnceWithoutChangingHistoricalTokenDecoder() = runTest {
        val preferences = preferences()
        val original = OAuthToken("whoop", "legacy", "refresh", extras = mapOf("scope_detail" to "read-only"))
        preferences.edit().putString("token:whoop", Json.encodeToString(original)).commit()
        val migrated = requireNotNull(EncryptedOAuthTokenStore(preferences).getCredential("whoop"))
        assertThat(migrated.token).isEqualTo(original)
        assertThat(EncryptedOAuthTokenStore(preferences).getCredential("whoop")).isEqualTo(migrated)
        val oldDecoder = Json { ignoreUnknownKeys = true }
        assertThat(oldDecoder.decodeFromString<OAuthToken>(requireNotNull(preferences.getString("token:whoop", null))))
            .isEqualTo(original)
    }

    @Test
    fun corruptOrForeignAuthorityCannotBecomeCredential() = runTest {
        val preferences = preferences()
        val store = EncryptedOAuthTokenStore(preferences)
        for (raw in listOf(
            """{"providerId":"whoop","accessToken":"test","_healthmd_connection_id":null}""",
            """{"providerId":"whoop","accessToken":"test","_healthmd_connection_id":"invalid"}""",
            """{"providerId":"oura","accessToken":"test"}""",
        )) {
            preferences.edit().putString("token:whoop", raw).commit()
            assertThat(store.getCredential("whoop")).isNull()
            assertThat(preferences.getString("token:whoop", null)).isEqualTo(raw)
        }
    }

    @Test
    fun failedCommitInvalidatesPublishedAndPriorGenerationsAcrossStoreInstances() = runTest {
        val backing = preferences()
        val failing = FailingPreferences(backing)
        val first = EncryptedOAuthTokenStore(failing)
        val other = EncryptedOAuthTokenStore(backing)
        first.saveToken(OAuthToken("whoop", "original"))
        val accepted = requireNotNull(first.getCredential("whoop"))
        failing.failCommits = 2
        assertThat(runCatching { first.saveToken(OAuthToken("whoop", "unverified")) }.isFailure).isTrue()
        assertThat(first.getCredential("whoop")).isNull()
        assertThat(other.getCredential("whoop")).isNull()
        first.saveToken(OAuthToken("whoop", "repaired"))
        assertThat(other.getToken("whoop")?.accessToken).isEqualTo("repaired")
        assertThat(other.getCredential("whoop")?.connectionId).isNotEqualTo(accepted.connectionId)
    }

    private class FailingPreferences(private val backing: SharedPreferences) : SharedPreferences by backing {
        var failCommits = 0
        override fun edit(): SharedPreferences.Editor {
            val editor = backing.edit()
            return object : SharedPreferences.Editor by editor {
                override fun putString(key: String?, value: String?): SharedPreferences.Editor {
                    editor.putString(key, value)
                    return this
                }
                override fun remove(key: String?): SharedPreferences.Editor {
                    editor.remove(key)
                    return this
                }
                override fun commit(): Boolean {
                    val actual = editor.commit()
                    if (failCommits > 0) { failCommits -= 1; return false }
                    return actual
                }
            }
        }
    }
}
