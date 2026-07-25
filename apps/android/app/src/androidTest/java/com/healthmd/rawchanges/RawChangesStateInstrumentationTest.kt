package com.healthmd.rawchanges

import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import java.io.File
import java.util.UUID
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertThrows
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
    fun archiveAndParentDirectoryCanBeForcedDurableOnAndroid() {
        File(context.noBackupFilesDir, "raw-changes").deleteRecursively()
        val destination = NoBackupRawChangesDestination(context)
        val artifact = destination.finalFile("durability-probe").apply { writeText("probe") }

        destination.makeFileAndParentDurable(artifact)

        assertTrue(artifact.isFile)
    }

    @Test
    fun sqliteSequenceOneCommitAtomicallyReplacesScopeIdentities() {
        File(context.noBackupFilesDir, "raw-changes").deleteRecursively()
        val alias = "healthmd.raw-changes.test.${UUID.randomUUID()}".also(aliases::add)
        SQLiteRawChangesStateStore(context, InstallationBoundTokenCipher(alias)).use { state ->
            val scope = "scope"
            val oldPending = stage(state, pending(scope, "old-chain"), SecretChangesToken("old-initial"))
            state.commit(
                oldPending,
                "{\"recordTypeKeys\":[\"steps\"],\"dataOriginPackageNames\":[]}",
                SecretChangesToken("old-token"),
                2,
                0,
                sequenceOf(IdentityMutation.Upsert(identity("old"))),
            )
            assertTrue(state.identity(scope, "old") != null)

            val newPending = stage(
                state,
                pending(scope, "new-chain", expected = state.load(scope)),
                SecretChangesToken("new-initial"),
            )
            state.commit(
                newPending,
                "{\"recordTypeKeys\":[\"steps\"],\"dataOriginPackageNames\":[]}",
                SecretChangesToken("new-token"),
                3,
                0,
                sequenceOf(IdentityMutation.Upsert(identity("new"))),
            )

            assertNull(state.identity(scope, "old"))
            assertTrue(state.identity(scope, "new") != null)
            assertEquals("new-chain", state.load(scope)?.chainId)
        }
    }

    @Test
    fun sqlitePendingInsertAndPhaseUpdatesRejectCrossWiredRuns() {
        File(context.noBackupFilesDir, "raw-changes").deleteRecursively()
        val alias = "healthmd.raw-changes.test.${UUID.randomUUID()}".also(aliases::add)
        SQLiteRawChangesStateStore(context, InstallationBoundTokenCipher(alias)).use { state ->
            val first = pending("scope", "chain")
            state.beginPending(first, SecretChangesToken("first"))
            assertThrows(RawChangesStateConflictException::class.java) {
                state.beginPending(first.copy(archiveId = "other"), SecretChangesToken("second"))
            }
            assertThrows(RawChangesStateConflictException::class.java) {
                state.prepared(first.copy(sequence = 2), "artifact", "a".repeat(64), "b".repeat(64))
            }
            assertEquals(first.archiveId, state.pending("scope")?.archiveId)
            assertEquals(PendingPhase.READING, state.pending("scope")?.phase)
        }
    }

    private fun stage(
        state: SQLiteRawChangesStateStore,
        pending: PendingArchive,
        initialToken: SecretChangesToken,
    ): PendingArchive {
        state.beginPending(pending, initialToken)
        state.prepared(pending, "artifact", "a".repeat(64), "b".repeat(64))
        state.markPromoted(pending)
        state.markSidecarDurable(pending, "sidecar")
        return requireNotNull(state.pending(pending.scopeHash))
    }

    private fun pending(scope: String, chain: String, expected: RawChangesChainState? = null) = PendingArchive(
        scopeHash = scope,
        archiveId = UUID.randomUUID().toString(),
        chainId = chain,
        sequence = 1,
        previousLogicalHash = null,
        expectedChainId = expected?.chainId,
        expectedSequence = expected?.sequence,
        expectedLogicalHash = expected?.previousLogicalHash,
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
