package com.healthmd.data.drive

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.sha256Hex
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import io.mockk.slot
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
        coEvery { managedStore.isMutationSafe() } returns true
        coEvery { api.getMetadata("token", destination.folderId, any()) } returns
            DriveApiResult.Success(destinationMetadata(destination))

        assertThat(runner.run(bundle, destination.id)).isEqualTo(GoogleDriveRunResult.Complete(1))
        coVerify(exactly = 0) { journalStore.create(any(), any()) }
        coVerify(exactly = 0) { api.startResumableCreate(any(), any(), any(), any(), any(), any(), any(), any()) }
        coVerify(exactly = 0) { journalStore.pruneAcknowledged(any()) }
    }

    @Test
    fun `resume if present returns missing without authorization or capture`() = runTest {
        coEvery { journalStore.load("operation-missing") } returns GoogleDriveJournalLoad.Missing

        assertThat(runner.resumeIfPresent("operation-missing")).isNull()
        coVerify(exactly = 0) { authorization.silentToken(any()) }
        coVerify(exactly = 0) { journalStore.create(any(), any()) }
    }

    @Test
    fun `session crash after server commit reconciles final bytes before old baseline`() = runTest {
        val destination = destination()
        val bundle = bundle()
        val retained = journal(bundle, destination).copy(
            historyAcknowledged = false,
            artifacts = journal(bundle, destination).artifacts.map {
                it.copy(
                    phase = GoogleDriveArtifactPhase.SESSION_STARTED,
                    baselineVersion = "1",
                    baselineSize = 3,
                    baselineMd5 = md5Hex("old".encodeToByteArray()),
                    resumableSessionUri = "https://www.googleapis.com/upload/session/1",
                )
            },
        )
        val committed = fileMetadata(destination, version = "2", bytes = "exact".encodeToByteArray())
        coEvery { journalStore.load(bundle.operationId) } returns GoogleDriveJournalLoad.Found(retained)
        coEvery { destinationStore.find(destination.id) } returns destination
        coEvery { authorization.silentToken(destination) } returns GoogleDriveAccessTokenResult.Granted("token")
        coEvery { managedStore.isMutationSafe() } returns true
        coEvery { journalStore.readArtifact(bundle.operationId, any()) } returns "exact".encodeToByteArray()
        coEvery { api.getMetadata("token", destination.folderId, any()) } returns
            DriveApiResult.Success(destinationMetadata(destination))
        coEvery { api.getMetadata("token", "file-1", any()) } returns DriveApiResult.Success(committed)

        assertThat(runner.resume(bundle.operationId)).isEqualTo(GoogleDriveRunResult.Complete(1))
        coVerify(exactly = 0) { api.queryUpload(any(), any(), any()) }
        coVerify(exactly = 0) { api.upload(any(), any(), any(), any()) }
    }

    @Test
    fun `history acknowledgement is explicit and only then permits pruning`() = runTest {
        val destination = destination()
        val retained = journal(bundle(), destination)
        val saved = slot<GoogleDriveOperationJournal>()
        coEvery { journalStore.load(retained.operationId) } returns GoogleDriveJournalLoad.Found(retained)
        coEvery { journalStore.save(capture(saved)) } returns Unit

        assertThat(runner.acknowledgeAfterHistory(retained.operationId)).isTrue()
        assertThat(saved.captured.historyAcknowledged).isTrue()
        assertThat(saved.captured.artifacts.map { it.phase }).containsExactly(
            GoogleDriveArtifactPhase.HISTORY_ACKNOWLEDGED,
        )
        coVerify(exactly = 1) { journalStore.pruneAcknowledged() }
    }

    @Test
    fun `partial completion retains actionable reauthorization cause`() = runTest {
        val destination = destination()
        val retained = journal(bundle(), destination).copy(
            artifacts = listOf(
                journal(bundle(), destination).artifacts.single(),
                journal(bundle(), destination).artifacts.single().copy(
                    artifactId = "artifact-2",
                    relativePath = "second.md",
                    relativePathHash = relativePathHash(destination.id, "second.md"),
                    phase = GoogleDriveArtifactPhase.PREPARED,
                ),
            ),
        )
        coEvery { journalStore.load(retained.operationId) } returns GoogleDriveJournalLoad.Found(retained)
        coEvery { destinationStore.find(destination.id) } returns destination
        coEvery { authorization.silentToken(destination) } returns GoogleDriveAccessTokenResult.ResolutionRequired

        assertThat(runner.resume(retained.operationId)).isEqualTo(
            GoogleDriveRunResult.Stopped(
                error = GoogleDriveErrorId.REAUTHORIZATION_REQUIRED,
                completedArtifactCount = 1,
                partialCompletion = true,
            ),
        )
    }

    @Test
    fun `missing destination folder remains folder unavailable`() = runTest {
        val destination = destination()
        val retained = journal(bundle(), destination).copy(
            artifacts = journal(bundle(), destination).artifacts.map {
                it.copy(phase = GoogleDriveArtifactPhase.PREPARED)
            },
            completedArtifactCount = 0,
        )
        coEvery { journalStore.load(retained.operationId) } returns GoogleDriveJournalLoad.Found(retained)
        coEvery { destinationStore.find(destination.id) } returns destination
        coEvery { authorization.silentToken(destination) } returns GoogleDriveAccessTokenResult.Granted("token")
        coEvery { api.getMetadata("token", destination.folderId, any()) } returns
            DriveApiResult.Failure(GoogleDriveErrorId.FOLDER_UNAVAILABLE)

        assertThat(runner.resume(retained.operationId)).isEqualTo(
            GoogleDriveRunResult.Stopped(GoogleDriveErrorId.FOLDER_UNAVAILABLE),
        )
    }

    @Test
    fun `missing exact managed file is remote conflict not destination folder failure`() = runTest {
        val destination = destination()
        val retained = journal(bundle(), destination).copy(
            artifacts = journal(bundle(), destination).artifacts.map {
                it.copy(phase = GoogleDriveArtifactPhase.PREPARED)
            },
        )
        val binding = GoogleDriveManagedObject(
            destinationId = destination.id,
            relativePathHash = retained.artifacts.single().relativePathHash,
            objectId = "file-1",
            parentId = destination.folderId,
            expectedName = "health-2026-03-15.md",
            mimeType = "text/markdown; charset=utf-8",
        )
        coEvery { journalStore.load(retained.operationId) } returns GoogleDriveJournalLoad.Found(retained)
        coEvery { destinationStore.find(destination.id) } returns destination
        coEvery { authorization.silentToken(destination) } returns GoogleDriveAccessTokenResult.Granted("token")
        coEvery { managedStore.isMutationSafe() } returns true
        coEvery { managedStore.lookup(destination.id, retained.artifacts.single().relativePathHash) } returns
            GoogleDriveManagedObjectLookup.Found(binding)
        coEvery { api.getMetadata("token", destination.folderId, any()) } returns
            DriveApiResult.Success(destinationMetadata(destination))
        coEvery { api.getMetadata("token", binding.objectId, any()) } returns
            DriveApiResult.Failure(GoogleDriveErrorId.FOLDER_UNAVAILABLE)

        assertThat(runner.resume(retained.operationId)).isEqualTo(
            GoogleDriveRunResult.Stopped(GoogleDriveErrorId.REMOTE_CONFLICT),
        )
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
                    phase = GoogleDriveArtifactPhase.VERIFIED,
                    objectId = "file-1",
                    parentId = destination.folderId,
                ),
            ),
            completedArtifactCount = 1,
            historyAcknowledged = false,
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

    private fun fileMetadata(
        destination: GoogleDriveDestination,
        version: String,
        bytes: ByteArray,
    ) = GoogleDriveRemoteMetadata(
        id = "file-1",
        name = "health-2026-03-15.md",
        mimeType = "text/markdown",
        parents = listOf(destination.folderId),
        version = version,
        size = bytes.size.toLong(),
        sha256Checksum = sha256Hex(bytes),
    )

    private fun destinationMetadata(destination: GoogleDriveDestination) = GoogleDriveRemoteMetadata(
        id = destination.folderId,
        name = destination.folderLabel,
        mimeType = GOOGLE_DRIVE_FOLDER_MIME_TYPE,
        capabilities = GoogleDriveFolderCapabilities(canAddChildren = true, canEdit = true),
    )
}
