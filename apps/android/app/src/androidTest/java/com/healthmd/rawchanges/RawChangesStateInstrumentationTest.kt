package com.healthmd.rawchanges

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class RawChangesStateInstrumentationTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    private val aliases = mutableListOf<String>()

    @After
    fun cleanUp() {
        File(context.noBackupFilesDir, "raw-changes").deleteRecursively()
        val store = java.security.KeyStore.getInstance("AndroidKeyStore").apply { load(null) }
        aliases.forEach { if (store.containsAlias(it)) store.deleteEntry(it) }
    }

    @Test
    fun installationBoundCipherRoundTripsWithoutPlaintext() {
        val alias = "healthmd.raw-changes.test.${UUID.randomUUID()}".also(aliases::add)
        val cipher = InstallationBoundTokenCipher(alias)
        val secret = SecretChangesToken("instrumentation-secret-token")

        val encrypted = cipher.encrypt(secret)

        assertFalse(String(encrypted, Charsets.ISO_8859_1).contains("instrumentation-secret-token"))
        assertEquals(secret, cipher.decrypt(encrypted))
    }

    @Test
    fun sqliteSequenceOneCommitAtomicallyReplacesScopeIdentities() {
        File(context.noBackupFilesDir, "raw-changes").deleteRecursively()
        val alias = "healthmd.raw-changes.test.${UUID.randomUUID()}".also(aliases::add)
        SQLiteRawChangesStateStore(context, InstallationBoundTokenCipher(alias)).use { state ->
            val scope = "scope"
            state.commit(
                pending(scope, "old-chain"),
                "{\"recordTypeKeys\":[\"steps\"],\"dataOriginPackageNames\":[]}",
                SecretChangesToken("old-token"),
                sequenceOf(IdentityMutation.Upsert(identity("old"))),
            )
            assertTrue(state.identity(scope, "old") != null)

            state.commit(
                pending(scope, "new-chain"),
                "{\"recordTypeKeys\":[\"steps\"],\"dataOriginPackageNames\":[]}",
                SecretChangesToken("new-token"),
                sequenceOf(IdentityMutation.Upsert(identity("new"))),
            )

            assertNull(state.identity(scope, "old"))
            assertTrue(state.identity(scope, "new") != null)
            assertEquals("new-chain", state.load(scope)?.chainId)
        }
    }

    private fun pending(scope: String, chain: String) = PendingArchive(
        scopeHash = scope,
        archiveId = UUID.randomUUID().toString(),
        chainId = chain,
        sequence = 1,
        previousLogicalHash = null,
        createdEpochSecond = 1,
        createdNano = 0,
        workDatabasePath = File(context.cacheDir, "$chain.db").absolutePath,
        artifactPath = null,
        logicalHash = "a".repeat(64),
        artifactHash = "b".repeat(64),
        sidecarPath = null,
        phase = PendingPhase.SIDECAR_DURABLE,
        tokenGeneratedAtEpochSecond = 1,
        tokenGeneratedAtNano = 0,
        tokenGeneratedBeforeBase = true,
    )

    private fun identity(id: String) = RawNativeIdentity(
        nativeRecordId = id,
        typeKey = "steps",
        wireType = "steps",
        dataOriginPackageName = "example.health",
        lastKnownRecordHash = "c".repeat(64),
    )
}
