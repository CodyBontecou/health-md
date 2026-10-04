package com.healthmd.data.drive

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.work.ListenableWorker
import androidx.work.WorkerFactory
import androidx.work.WorkerParameters
import androidx.work.testing.TestListenableWorkerBuilder
import androidx.work.workDataOf
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.exportengine.sha256Hex
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.exportengine.ExportEnginePinPlanner
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.data.scheduler.ScheduledExportPendingRequests
import com.healthmd.data.scheduler.ScheduledExportRecoveryManager
import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfileEntryStore
import com.healthmd.data.scheduler.ScheduledProfileExportWorker
import com.healthmd.data.scheduler.ScheduledProfileSnapshotFactory
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.PendingScheduledExportRequest
import com.healthmd.export.FakeSettingsRepository
import com.healthmd.export.FakeExportRepository
import com.healthmd.export.FakeExportHistoryRepository
import com.healthmd.export.FakeBillingRepository
import com.healthmd.presentation.history.HistoryViewModel
import dagger.Lazy
import io.mockk.mockk
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FolderOrganization
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.WriteMode
import com.healthmd.export.FakeHealthRepository
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.test.runTest
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.setMain
import kotlinx.coroutines.test.resetMain
import kotlinx.coroutines.flow.first
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/** Actual capture -> renderer -> protected journal -> runner, with only SDK/Drive boundaries fake. */
@OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class GoogleDrivePartialCaptureRecoveryTest {
    @get:Rule val temporaryFolder = TemporaryFolder()
    private lateinit var scope: CoroutineScope
    private lateinit var context: Context
    private lateinit var destinations: GoogleDriveDestinationStore
    private lateinit var managed: GoogleDriveManagedObjectStore
    private lateinit var journals: GoogleDriveJournalStore
    private lateinit var preferences: DataStore<Preferences>
    private val health = FakeHealthRepository()
    private val api = SyntheticDrive()
    private val first = LocalDate.parse("2026-03-15")
    private val second = first.plusDays(1)
    private val destination = GoogleDriveDestination(
        id = "destination", accountReferenceId = "account", permissionId = "permission", folderId = "folder",
        accountLabel = "Synthetic", folderLabel = "Synthetic",
        capabilities = GoogleDriveFolderCapabilities(canAddChildren = true), lastValidatedAtEpochMillis = 1,
    )
    private val settings = ExportSettings(
        exportFormats = setOf(ExportFormat.JSON), exportTarget = ExportTarget.GOOGLE_DRIVE,
        scheduledExportTarget = ExportTarget.GOOGLE_DRIVE, writeMode = WriteMode.APPEND,
        subfolder = "", folderOrganization = FolderOrganization.FLAT,
    )
    private val factory = GeneratedExportBundleFactory(MarkdownExporter(), JsonExporter(), CsvExporter(), ObsidianBasesExporter())

    @Before fun setUp() {
        context = ApplicationProvider.getApplicationContext()
        File(context.noBackupFilesDir, "google-drive-operations").deleteRecursively()
        scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val file = temporaryFolder.newFolder().resolve("drive.preferences_pb")
        preferences = PreferenceDataStoreFactory.create(scope = scope, produceFile = { file })
        destinations = GoogleDriveDestinationStore(preferences, object : GoogleDriveAccountAuthorityStore {
            override suspend fun save(referenceId: String, accountName: String) = Unit
            override suspend fun accountName(referenceId: String): String = "synthetic-account"
            override suspend fun remove(referenceId: String) = Unit
        })
        managed = GoogleDriveManagedObjectStore(preferences)
        journals = GoogleDriveJournalStore(context)
    }

    @After fun tearDown() {
        scope.cancel()
        Dispatchers.resetMain()
        File(context.noBackupFilesDir, "google-drive-operations").deleteRecursively()
    }

    private fun runner() = GoogleDriveDestinationRunner(
        destinations, managed, GoogleDriveJournalStore(context),
        object : GoogleDriveAccessTokenProvider {
            override suspend fun silentToken(destination: GoogleDriveDestination) = GoogleDriveAccessTokenResult.Granted("synthetic-token")
        }, api,
    )
    private fun orchestrator() = GoogleDriveExportOrchestrator(health, factory, runner())
    private fun data(date: LocalDate) = HealthData(date, activity = ActivityData(steps = if (date == first) 100 else 200))

    @Test fun `restart retries uncaptured residual date without reappending completed owner`() = runTest {
        seed()
        health.fetchBehavior = { date -> if (date == second) error("synthetic capture failure") else data(date) }
        val initial = orchestrator().exportDates(listOf(first, second), settings, destination.id, operationId = "partial")
        assertThat(initial.successCount).isEqualTo(1)
        val firstBytes = api.bytes("$first.json")
        assertThat(api.commits["$first.json"]).isEqualTo(1)
        health.fetchBehavior = ::data

        // New orchestrator/runner/store objects simulate restart. The stable logical request ID
        // must not project A's retained upload completion onto B's residual scope.
        val residual = orchestrator().exportDates(listOf(second), settings, destination.id, operationId = "partial")
        assertThat(residual.successCount).isEqualTo(1)
        assertThat(health.fetchedDates).containsExactly(first, second, second).inOrder()
        assertThat(api.commits["$second.json"]).isEqualTo(1)
        assertThat(api.bytes("$first.json")).isEqualTo(firstBytes)
        assertThat(api.commits["$first.json"]).isEqualTo(1)
    }

    @Test fun `interrupted upload resume keeps capture failure and exact append bytes`() = runTest {
        seed()
        health.fetchBehavior = { date -> if (date == second) error("synthetic capture failure") else data(date) }
        api.interruptNextUpload = true
        val initial = orchestrator().exportDates(listOf(first, second), settings, destination.id, operationId = "interrupted")
        assertThat(initial.successCount).isEqualTo(0)
        val staged = api.attempts.single().copyOf()
        health.fetchBehavior = { error("resume must not capture") }

        val resumed = orchestrator().exportDates(listOf(first, second), settings, destination.id, operationId = "interrupted")
        assertThat(resumed.successCount).isEqualTo(1)
        assertThat(resumed.failedDateDetails.map { it.date }).containsExactly(second)
        assertThat(resumed.freshCaptureRetryDates).containsExactly(second)
        assertThat(health.fetchedDates).containsExactly(first, second).inOrder()
        assertThat(api.attempts).hasSize(2)
        assertThat(api.attempts.last()).isEqualTo(staged)
        assertThat(api.bytes("$first.json")).isEqualTo(staged)
        assertThat(api.commits["$first.json"]).isEqualTo(1)
    }

    @Test fun `history retries failed capture through frozen journal destination and settings`() = runTest {
        Dispatchers.setMain(UnconfinedTestDispatcher(testScheduler))
        seed()
        health.fetchBehavior = { date -> if (date == second) error("synthetic capture failure") else data(date) }
        val initial = orchestrator().exportDates(listOf(first, second), settings, destination.id, operationId = "history")
        val firstBytes = api.bytes("$first.json")
        val history = FakeExportHistoryRepository()
        val selection = GoogleDriveSelectionStore(preferences)
        selection.select("unrelated-selection")
        health.fetchBehavior = ::data
        val viewModel = HistoryViewModel(
            history, health, FakeExportRepository(),
            FakeSettingsRepository(settings.copy(filenameFormat = "edited-{date}")), mockk(),
            googleDriveDestinationRunner = runner(), googleDriveSelectionStore = selection,
            googleDriveExportOrchestrator = orchestrator(),
        )
        viewModel.retry(ExportHistoryEntry(
            timestamp = 1, source = ExportSource.MANUAL, dateRangeStart = first, dateRangeEnd = second,
            successCount = initial.successCount, totalCount = 2, failedDateDetails = initial.failedDateDetails,
            target = ExportTarget.GOOGLE_DRIVE, driveOperationId = "history",
        ))
        viewModel.uiState.first { !it.isRetrying && it.retryMessage != null }
        assertThat(history.entries.single().isFullSuccess).isTrue()
        assertThat(health.fetchedDates).containsExactly(first, second, second).inOrder()
        assertThat(api.commits["$second.json"]).isEqualTo(1)
        assertThat(api.bytes("$first.json")).isEqualTo(firstBytes)
        assertThat(api.commits["$first.json"]).isEqualTo(1)
        assertThat(selection.get()).isEqualTo("unrelated-selection")
    }

    @Test fun `legacy pending recovery rejects completed upload as authority for uncaptured date`() = runTest {
        seed()
        val snapshot = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(settings, null, ZoneId.of("UTC")),
        )
        health.fetchBehavior = { date -> if (date == second) error("synthetic capture failure") else data(date) }
        val initial = orchestrator().exportDates(listOf(first, second), settings, destination.id,
            operationId = "legacy", source = "scheduled", settingsSnapshotJson = snapshot)
        val reconciled = ScheduledExportPendingRequests.applyAttemptResult(
            settings, listOf(first, second), initial.failedDateDetails,
            target = ExportTarget.GOOGLE_DRIVE, destinationFingerprint = destination.fingerprint,
            settingsSnapshotJson = snapshot, driveOperationIds = initial.retryDriveOperationIds,
            freshCaptureRetryDates = initial.freshCaptureRetryDates,
        )
        assertThat(reconciled.pendingScheduledExportRequests.single().date).isEqualTo(second)
        assertThat(reconciled.pendingScheduledExportRequests.single().driveOperationId).isNull()
        // Exercise historical pending metadata that still associates B with A's operation.
        val current = FakeSettingsRepository(settings.copy(filenameFormat = "edited-{date}",
            pendingScheduledExportRequests = listOf(PendingScheduledExportRequest(
                date = second, exportTarget = ExportTarget.GOOGLE_DRIVE,
                destinationFingerprint = destination.fingerprint, settingsSnapshotJson = snapshot,
                driveOperationId = "legacy",
            ))), initialPurchased = true)
        val selection = GoogleDriveSelectionStore(preferences)
        selection.select(destination.id)
        health.fetchBehavior = ::data
        val history = FakeExportHistoryRepository()
        val recovered = ScheduledExportRecoveryManager(
            context, health, FakeExportRepository(), current, history,
            googleDriveExportOrchestrator = orchestrator(), googleDriveDestinationRunner = runner(),
            googleDriveSelectionStore = selection, googleDriveDestinationStore = destinations,
            entitlementRepository = FakeBillingRepository(true), distributionPolicy = DistributionPolicy.play(),
        ).recoverPendingDates()
        assertThat(recovered.exportResult?.successCount).isEqualTo(1)
        assertThat(current.getExportSettings().pendingScheduledExportRequests).isEmpty()
        assertThat(history.entries.single().isFullSuccess).isTrue()
        assertThat(health.fetchedDates).containsExactly(first, second, second).inOrder()
        assertThat(api.commits["$first.json"]).isEqualTo(1)
        assertThat(api.commits["$second.json"]).isEqualTo(1)
    }

    @Test fun `profile partial attempt checkpoints only fresh residual and completes it after restart`() = runTest {
        seed()
        val snapshots = ScheduledProfileSnapshotFactory(ExportEnginePinPlanner())
        val snapshot = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(settings, null, ZoneId.of("UTC")),
        )
        val profiles = ExportProfileRepository(preferences, context)
        val profile = profiles.add("Synthetic Drive", snapshot, ExportTarget.GOOGLE_DRIVE, destinationId = destination.id)
        val entries = ScheduledProfileEntryStore(preferences, context)
        val fireAt = second.plusDays(1).atStartOfDay(ZoneId.of("UTC")).toInstant().toEpochMilli()
        entries.upsert(ScheduledProfileEntry(profileId = profile.id, isEnabled = true, anchorEpochDay = first.toEpochDay(),
            lookbackDays = 2, pendingExports = listOf(com.healthmd.data.scheduler.ScheduledProfilePendingExport(
                "initial", listOf(first.toEpochDay(), second.toEpochDay()), fireAt, snapshot, ExportTarget.GOOGLE_DRIVE,
                profile.name, durableOperationId = "profile-initial", destinationId = destination.id,
            ))))
        val current = FakeSettingsRepository(settings, initialPurchased = true)
        val history = FakeExportHistoryRepository()
        fun worker(): ScheduledProfileExportWorker = TestListenableWorkerBuilder<ScheduledProfileExportWorker>(context)
            .setInputData(workDataOf(ScheduledProfileExportWorker.INPUT_PROFILE_ID to profile.id))
            .setWorkerFactory(object : WorkerFactory() {
                override fun createWorker(appContext: Context, workerClassName: String, workerParameters: WorkerParameters): ListenableWorker =
                    ScheduledProfileExportWorker(appContext, workerParameters, current, health, FakeExportRepository(), history,
                        mockk(), profiles, entries, snapshots, mockk(), Lazy { mockk(relaxed = true) }, orchestrator(), mockk(),
                        FakeBillingRepository(true), DistributionPolicy.play())
            }).build()
        health.fetchBehavior = { date -> if (date == second) error("synthetic capture failure") else data(date) }
        worker().doWork()
        val residual = checkNotNull(entries.entry(profile.id)).pendingExports.single()
        assertThat(residual.ownerDates).containsExactly(second)
        assertThat(residual.durableOperationId).isNull()
        assertThat(residual.destinationId).isEqualTo(destination.id)
        assertThat(residual.settingsSnapshotJson).isEqualTo(snapshot)
        health.fetchBehavior = ::data
        assertThat(worker().doWork()).isEqualTo(ListenableWorker.Result.success())
        assertThat(checkNotNull(entries.entry(profile.id)).pendingExports).isEmpty()
        assertThat(health.fetchedDates).containsExactly(first, second, second).inOrder()
        assertThat(api.commits["$first.json"]).isEqualTo(1)
        assertThat(api.commits["$second.json"]).isEqualTo(1)
    }

    @Test fun `historical journals without capture evidence fail closed without recapture or rewrite`() = runTest {
        seed()
        health.fetchBehavior = ::data
        orchestrator().exportDates(listOf(first), settings, destination.id, operationId = "historical")
        val file = File(context.noBackupFilesDir, "google-drive-operations/historical/journal.json")
        val original = kotlinx.serialization.json.Json.parseToJsonElement(file.readText()) as kotlinx.serialization.json.JsonObject
        listOf(1, 2, 99).forEach { version ->
            val unknown = kotlinx.serialization.json.JsonObject(original.filterKeys { it != "captureEvidence" } +
                ("version" to kotlinx.serialization.json.JsonPrimitive(version))).toString()
            file.writeText(unknown)
            val result = orchestrator().exportDates(listOf(first), settings, destination.id, operationId = "historical")
            assertThat(result.successCount).isEqualTo(0)
            assertThat(file.readText()).isEqualTo(unknown)
            assertThat(journals.load("historical")).isEqualTo(GoogleDriveJournalLoad.Corrupt)
        }
        assertThat(health.fetchedDates).containsExactly(first)
        assertThat(api.commits["$first.json"]).isEqualTo(1)
    }

    private suspend fun seed() {
        destinations.save(destination, "synthetic-account")
        listOf(first, second).forEach { date ->
            val name = "$date.json"
            val id = "file-$date"
            api.seed(id, name, "baseline-$date".encodeToByteArray())
            managed.put(GoogleDriveManagedObject(
                destinationId = destination.id, relativePathHash = relativePathHash(destination.id, name),
                objectId = id, parentId = destination.folderId, expectedName = name, mimeType = "application/json",
            ))
        }
    }

    private class SyntheticDrive : GoogleDriveApi {
        private val files = mutableMapOf<String, Pair<GoogleDriveRemoteMetadata, ByteArray>>()
        private val sessions = mutableMapOf<String, String>()
        val commits = mutableMapOf<String, Int>()
        val attempts = mutableListOf<ByteArray>()
        var interruptNextUpload = false
        fun seed(id: String, name: String, bytes: ByteArray) {
            files[id] = GoogleDriveRemoteMetadata(id, name, "application/json", parents = listOf("folder"),
                version = "1", size = bytes.size.toLong(), sha256Checksum = sha256Hex(bytes)) to bytes.copyOf()
        }
        fun bytes(name: String): ByteArray = files.values.single { it.first.name == name }.second.copyOf()
        override suspend fun about(accessToken: String) = DriveApiResult.Success(GoogleDriveAbout("permission"))
        override suspend fun getMetadata(accessToken: String, fileId: String, resourceKeys: Map<String, String>): DriveApiResult<GoogleDriveRemoteMetadata> =
            if (fileId == "folder") DriveApiResult.Success(GoogleDriveRemoteMetadata("folder", "Synthetic", GOOGLE_DRIVE_FOLDER_MIME_TYPE,
                capabilities = GoogleDriveFolderCapabilities(canAddChildren = true)))
            else files[fileId]?.first?.let { DriveApiResult.Success(it) } ?: DriveApiResult.Failure(GoogleDriveErrorId.FOLDER_UNAVAILABLE)
        override suspend fun findChildren(accessToken: String, parentId: String, name: String, resourceKeys: Map<String, String>) =
            DriveApiResult.Success(files.values.map { it.first }.filter { it.name == name && it.parents == listOf(parentId) })
        override suspend fun generateId(accessToken: String): DriveApiResult<String> = error("all synthetic files are bound")
        override suspend fun createFolder(accessToken: String, id: String, parentId: String, name: String, resourceKeys: Map<String, String>): DriveApiResult<GoogleDriveRemoteMetadata> = error("flat paths")
        override suspend fun download(accessToken: String, fileId: String, resourceKeys: Map<String, String>) = DriveApiResult.Success(checkNotNull(files[fileId]).second.copyOf())
        override suspend fun startResumableCreate(accessToken: String, id: String, parentId: String, name: String, mediaType: String, size: Long, appProperties: Map<String, String>, resourceKeys: Map<String, String>): DriveApiResult<GoogleDriveUploadSession> = error("all synthetic files are bound")
        override suspend fun startResumableUpdate(accessToken: String, fileId: String, mediaType: String, size: Long, appProperties: Map<String, String>, resourceKeys: Map<String, String>): DriveApiResult<GoogleDriveUploadSession> {
            val uri = "https://www.googleapis.com/upload/$fileId"
            sessions[uri] = fileId
            return DriveApiResult.Success(GoogleDriveUploadSession(uri))
        }
        override suspend fun queryUpload(accessToken: String, sessionUri: String, totalSize: Long) = DriveApiResult.Success(GoogleDriveUploadStatus(0, false))
        override suspend fun upload(accessToken: String, sessionUri: String, bytes: ByteArray, offset: Long): DriveApiResult<GoogleDriveUploadStatus> {
            attempts += bytes.copyOf()
            if (interruptNextUpload) {
                interruptNextUpload = false
                return DriveApiResult.Failure(GoogleDriveErrorId.AMBIGUOUS_COMMIT, retryable = true)
            }
            val id = checkNotNull(sessions[sessionUri])
            val old = checkNotNull(files[id]).first
            files[id] = old.copy(version = (checkNotNull(old.version).toInt() + 1).toString(),
                size = bytes.size.toLong(), sha256Checksum = sha256Hex(bytes)) to bytes.copyOf()
            commits[old.name] = (commits[old.name] ?: 0) + 1
            return DriveApiResult.Success(GoogleDriveUploadStatus(bytes.size.toLong(), true))
        }
    }
}
