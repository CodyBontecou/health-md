package com.healthmd.data.drive

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.sha256Hex
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import org.junit.Test

class GoogleDriveDestinationRunnerRecoveryTest {
    private val destinationStore = mockk<GoogleDriveDestinationStore>()
    private val managedStore = mockk<GoogleDriveManagedObjectStore>(relaxed = true)
    private val journalStore = mockk<GoogleDriveJournalStore>(relaxed = true)
    private val authorization = mockk<GoogleDriveAccessTokenProvider>()
    private val api = mockk<GoogleDriveApi>()
    private val runner = GoogleDriveDestinationRunner(
        destinationStore,
        managedStore,
        journalStore,
        authorization,
        api,
    )

    @Test
    fun `same operation resumes its retained verified journal without recapturing or recreating`() = runTest {
        val destination = destination()
        val bundle = bundle()
        val journal = journal(bundle, destination)
        coEvery { destinationStore.find(destination.id) } returns destination
        coEvery { journalStore.load(bundle.operationId) } returns GoogleDriveJournalLoad.Found(journal)
        coEvery { authorization.silentToken(destination) } returns GoogleDriveAccessTokenResult.Granted("token")
        coEvery { api.getMetadata("token", destination.folderId, any()) } returns
            DriveApiResult.Success(destinationMetadata(destination))

        assertThat(runner.run(bundle, destination.id)).isEqualTo(GoogleDriveRunResult.Complete(1))
        coVerify(exactly = 0) { journalStore.create(any(), any()) }
        coVerify(exactly = 0) { api.startResumableCreate(any(), any(), any(), any(), any(), any(), any(), any()) }
    }

    @Test
    fun `operation identity mismatch fails closed instead of replacing retained bytes`() = runTest {
        val destination = destination()
        val bundle = bundle()
        coEvery { destinationStore.find(destination.id) } returns destination
        coEvery { journalStore.load(bundle.operationId) } returns GoogleDriveJournalLoad.Found(
            journal(bundle, destination).copy(bundleDigest = "0".repeat(64)),
        )

        assertThat(runner.run(bundle, destination.id)).isEqualTo(
            GoogleDriveRunResult.Stopped(GoogleDriveErrorId.REMOTE_CONFLICT),
        )
        coVerify(exactly = 0) { authorization.silentToken(any()) }
    }

    private fun bundle(): GeneratedExportBundle {
        val bytes = "exact".encodeToByteArray()
        return GeneratedExportBundle(
            operationId = "operation-recovery",
            profileId = "profile-1",
            source = "scheduled",
            dates = listOf(LocalDate.parse("2026-03-15")),
            settingsSnapshotSha256 = sha256Hex("settings".encodeToByteArray()),
            rendererPin = "android-frozen-v4",
            artifacts = listOf(
                GeneratedExportArtifact(
                    artifactId = "artifact-1",
                    relativePath = "health-2026-03-15.md",
                    mediaType = "text/markdown; charset=utf-8",
                    writeIntent = GeneratedArtifactWriteIntent.OVERWRITE,
                    bytes = bytes,
                ),
            ),
        )
    }

    private fun journal(bundle: GeneratedExportBundle, destination: GoogleDriveDestination) =
        GoogleDriveOperationJournal(
            operationId = bundle.operationId,
            profileId = bundle.profileId,
            source = bundle.source,
            ownerDates = bundle.dates.map(LocalDate::toString),
            destinationId = destination.id,
            destinationFingerprint = destination.fingerprint,
            bundleDigest = bundle.digest,
            settingsSnapshotSha256 = bundle.settingsSnapshotSha256,
            rendererPin = bundle.rendererPin,
            artifacts = listOf(
                GoogleDriveJournalArtifact(
                    artifactId = "artifact-1",
                    relativePathHash = relativePathHash(destination.id, "health-2026-03-15.md"),
                    relativePath = "health-2026-03-15.md",
                    mediaType = "text/markdown; charset=utf-8",
                    writeIntent = GeneratedArtifactWriteIntent.OVERWRITE,
                    spoolFile = "artifact-0000.bin",
                    byteCount = 5,
                    sha256 = sha256Hex("exact".encodeToByteArray()),
                    phase = GoogleDriveArtifactPhase.HISTORY_ACKNOWLEDGED,
                    objectId = "file-1",
                    parentId = destination.folderId,
                ),
            ),
            completedArtifactCount = 1,
            historyAcknowledged = true,
            createdAtEpochMillis = 1,
            updatedAtEpochMillis = 1,
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

    private fun destinationMetadata(destination: GoogleDriveDestination) = GoogleDriveRemoteMetadata(
        id = destination.folderId,
        name = destination.folderLabel,
        mimeType = GOOGLE_DRIVE_FOLDER_MIME_TYPE,
        capabilities = GoogleDriveFolderCapabilities(canAddChildren = true, canEdit = true),
    )
}
