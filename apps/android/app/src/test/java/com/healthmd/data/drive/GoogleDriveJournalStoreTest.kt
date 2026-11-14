package com.healthmd.data.drive

import android.content.Context
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.sha256Hex
import java.io.File
import java.time.LocalDate
import java.util.UUID
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class GoogleDriveJournalStoreTest {
    private lateinit var context: Context
    private lateinit var root: File
    private lateinit var store: GoogleDriveJournalStore

    @Before
    fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        root = File(context.noBackupFilesDir, "google-drive-operations")
        root.deleteRecursively()
        store = GoogleDriveJournalStore(context)
    }

    @After
    fun tearDown() {
        root.deleteRecursively()
    }

    @Test
    fun `final byte replacement switches journal to a new immutable spool name`() = runTest {
        val operationId = "operation-${UUID.randomUUID()}"
        val created = store.create(bundle(operationId, "fragment".encodeToByteArray()), destination())
        val oldSpool = created.artifacts.single().spoolFile

        val replaced = store.replaceFinalBytes(created, 0, "complete-final".encodeToByteArray())

        assertThat(replaced.artifacts.single().spoolFile).isNotEqualTo(oldSpool)
        assertThat(replaced.artifacts.single().spoolFile).contains("-final-")
        assertThat(store.readArtifact(operationId, replaced.artifacts.single()))
            .isEqualTo("complete-final".encodeToByteArray())
        val loaded = store.load(operationId) as GoogleDriveJournalLoad.Found
        assertThat(loaded.journal.artifacts.single().spoolFile)
            .isEqualTo(replaced.artifacts.single().spoolFile)
    }

    @Test
    fun `pruning deletes only history acknowledged journals`() = runTest {
        val unresolvedId = "unresolved-${UUID.randomUUID()}"
        val acknowledgedId = "acknowledged-${UUID.randomUUID()}"
        store.create(bundle(unresolvedId, "pending".encodeToByteArray()), destination())
        val created = store.create(bundle(acknowledgedId, "done".encodeToByteArray()), destination())
        val acknowledged = created.copy(
            historyAcknowledged = true,
            completedArtifactCount = 1,
            artifacts = created.artifacts.map {
                it.copy(phase = GoogleDriveArtifactPhase.HISTORY_ACKNOWLEDGED)
            },
        )
        store.save(acknowledged)

        store.pruneAcknowledged(keep = 0)

        assertThat(store.load(unresolvedId)).isInstanceOf(GoogleDriveJournalLoad.Found::class.java)
        assertThat(store.load(acknowledgedId)).isEqualTo(GoogleDriveJournalLoad.Missing)
    }

    private fun bundle(operationId: String, bytes: ByteArray) = GeneratedExportBundle(
        operationId = operationId,
        profileId = null,
        source = "manual",
        dates = listOf(LocalDate.parse("2026-03-15")),
        settingsSnapshotSha256 = sha256Hex("settings".encodeToByteArray()),
        rendererPin = "android-frozen-v4:legacy",
        artifacts = listOf(
            GeneratedExportArtifact(
                artifactId = "artifact-1",
                relativePath = "health.md",
                mediaType = "text/markdown; charset=utf-8",
                writeIntent = GeneratedArtifactWriteIntent.OVERWRITE,
                bytes = bytes,
            ),
        ),
    )

    private fun destination() = GoogleDriveDestination(
        id = "destination-1",
        accountReferenceId = "account-1",
        permissionId = "permission-1",
        folderId = "folder-1",
        accountLabel = "Google account",
        folderLabel = "Exports",
        capabilities = GoogleDriveFolderCapabilities(canAddChildren = true, canEdit = true),
        lastValidatedAtEpochMillis = 1,
    )
}
