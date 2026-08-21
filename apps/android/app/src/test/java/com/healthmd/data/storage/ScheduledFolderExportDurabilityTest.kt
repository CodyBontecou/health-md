package com.healthmd.data.storage

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.exportengine.AndroidExportProfile
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.exportengine.ExportArtifactPlan
import com.healthmd.domain.exportengine.ExportArtifactPlanItem
import com.healthmd.domain.exportengine.ExportArtifactWriteMode
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.LocalDailyAggregateExportPlanner
import com.healthmd.domain.exportengine.LocalDailyAggregatePlanningResult
import com.healthmd.domain.exportengine.artifactIdHex
import com.healthmd.domain.exportengine.sha256Hex as artifactSha256Hex
import com.healthmd.domain.exportengine.testPin
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.WriteMode
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.util.Base64
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import org.junit.Test

class ScheduledFolderExportDurabilityTest {
    @Test
    fun storeRejectsCorruptionAndCrossDayPathCollisions() = runTest {
        val directory = temporaryDirectory("folder-journal-store")
        val store = ScheduledFolderExportJournalStore(directory)
        val pin = testPin(ExportEngineMode.rust)
        val bytes = "exact".encodeToByteArray()
        val artifact = ScheduledFolderJournalArtifact(
            artifactId = "artifact-1",
            relativePath = "health/2026-03-15.json",
            stagingRelativePath = "health/.2026-03-15.json.healthmd-artifact-1.pending",
            mediaType = "application/json",
            byteCount = bytes.size,
            sha256 = sha256Hex(bytes),
            contentBase64 = Base64.getEncoder().encodeToString(bytes),
        )
        val unsignedJournal = ScheduledFolderExportJournal(
            operationId = "folder-operation",
            folderUri = FOLDER_URI,
            settingsSnapshotSha256 = sha256Hex("settings".encodeToByteArray()),
            enginePinJson = com.healthmd.domain.exportengine.ExportEnginePinCodec.encodeCanonical(pin),
            ownerDates = listOf("2026-03-15"),
            phase = ScheduledFolderJournalPhase.READY,
            days = listOf(ScheduledFolderJournalDay("2026-03-15", listOf(artifact))),
        )
        val journal = unsignedJournal.copy(
            planSha256 = scheduledFolderImmutablePlanSha256(unsignedJournal),
        )

        assertThat(store.save(journal)).isTrue()
        assertThat(store.load(journal.operationId)).isEqualTo(ScheduledFolderJournalLoad.Found(journal))

        val unsignedColliding = journal.copy(
            planSha256 = null,
            ownerDates = listOf("2026-03-15", "2026-03-16"),
            days = listOf(
                ScheduledFolderJournalDay("2026-03-15", listOf(artifact)),
                ScheduledFolderJournalDay(
                    "2026-03-16",
                    listOf(artifact.copy(artifactId = "artifact-2")),
                ),
            ),
        )
        val colliding = unsignedColliding.copy(
            planSha256 = scheduledFolderImmutablePlanSha256(unsignedColliding),
        )
        assertThat(store.save(colliding)).isFalse()
        val redirected = journal.copy(
            days = listOf(
                ScheduledFolderJournalDay(
                    "2026-03-15",
                    listOf(artifact.copy(relativePath = "health/redirected.json")),
                ),
            ),
        )
        assertThat(store.save(redirected)).isFalse()

        directory.listFiles()!!.single { it.extension == "json" }.writeText("{not-json")
        assertThat(store.load(journal.operationId)).isEqualTo(ScheduledFolderJournalLoad.Corrupt)
        directory.deleteRecursively()
    }

    @Test
    fun partialCommitResumesExactBytesWithoutHealthCaptureOrRendering() = runTest {
        val directory = temporaryDirectory("folder-journal-resume")
        val store = ScheduledFolderExportJournalStore(directory)
        val timeline = mutableListOf<String>()
        val destination = InMemoryDurableDestination(
            failFirstWriteFor = "health/2026-03-16.json",
            events = timeline,
        )
        val manager = destination.manager
        val settingsRepository = settingsRepository()
        val pin = testPin(ExportEngineMode.rust)
        val settings = durableSettings(pin)
        val snapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(
                settings = settings,
                pin = pin,
                zone = ZoneId.of(pin.ianaTimeZone),
            ),
        )
        val dates = listOf(
            LocalDate.of(2026, 3, 15),
            LocalDate.of(2026, 3, 16),
            LocalDate.of(2026, 3, 17),
        )
        var readyBeforeFirstBind = false
        destination.onBind = {
            readyBeforeFirstBind = kotlinx.coroutines.runBlocking {
                val loaded = store.load(OPERATION_ID)
                loaded is ScheduledFolderJournalLoad.Found &&
                    loaded.journal.phase == ScheduledFolderJournalPhase.READY
            }
        }
        val planner = LocalDailyAggregateExportPlanner { data, _ ->
            timeline += "plan:${data.date}"
            plannedDay(data.date)
        }
        val repository = repository(manager, settingsRepository, store, planner)
        val health = healthRepository(dates)

        val first = ExportOrchestrator(health, repository).exportDatesDurably(
            dates = dates,
            settings = settings,
            durableFolderOperationId = OPERATION_ID,
            durableSettingsSnapshotJson = snapshotJson,
        )

        assertThat(first.successCount).isEqualTo(1)
        assertThat(first.retryFolderOperationIds).containsExactly(
            dates[1], OPERATION_ID,
            dates[2], OPERATION_ID,
        )
        assertThat(timeline.take(3)).containsExactly(
            "plan:2026-03-15",
            "plan:2026-03-16",
            "plan:2026-03-17",
        ).inOrder()
        assertThat(timeline[3]).startsWith("bind:health/.2026-03-15.json.healthmd-")
        assertThat(timeline[4]).startsWith("write:health/.2026-03-15.json.healthmd-")
        assertThat(readyBeforeFirstBind).isTrue()
        assertThat(repository.hasResumableDurableScheduledFolderOperation(
            OPERATION_ID,
            listOf(dates[1]),
            settings,
            snapshotJson,
        )).isFalse()
        assertThat(repository.hasResumableDurableScheduledFolderOperation(
            OPERATION_ID,
            dates.drop(1),
            settings,
            snapshotJson,
        )).isTrue()

        destination.failFirstWriteFor = null
        val restartedPlanner = LocalDailyAggregateExportPlanner { _, _ ->
            error("resume must not render")
        }
        val restartedRepository = repository(manager, settingsRepository, store, restartedPlanner)
        val unavailableHealth = mockk<HealthRepository>()
        every { unavailableHealth.isBeforeFirstUnlock() } answers { error("resume must not read lock state") }
        coEvery { unavailableHealth.fetchHealthDataRange(any(), any(), any()) } answers {
            error("resume must not capture")
        }

        val resumed = ExportOrchestrator(unavailableHealth, restartedRepository).exportDatesDurably(
            dates = dates.drop(1),
            settings = settings,
            durableFolderOperationId = OPERATION_ID,
            durableSettingsSnapshotJson = snapshotJson,
        )

        assertThat(resumed.isFullSuccess).isTrue()
        assertThat(resumed.totalCount).isEqualTo(2)
        assertThat(resumed.retryFolderOperationIds).isEmpty()
        assertThat(destination.successfulWriteCount("health/2026-03-15.json")).isEqualTo(1)
        assertThat(destination.successfulWriteCount("health/2026-03-16.json")).isEqualTo(1)
        assertThat(destination.successfulWriteCount("health/2026-03-17.json")).isEqualTo(1)
        verify(exactly = 0) { unavailableHealth.isBeforeFirstUnlock() }
        directory.deleteRecursively()
    }

    @Test
    fun stagingIntentRecoversCreateBeforeCheckpointWithoutRecapture() = runTest {
        val directory = temporaryDirectory("folder-journal-create-crash")
        val store = ScheduledFolderExportJournalStore(directory)
        val destination = InMemoryDurableDestination(
            failAfterCreateFor = "health/2026-03-15.json",
        )
        val pin = testPin(ExportEngineMode.rust)
        val settings = durableSettings(pin)
        val snapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(settings, pin, ZoneId.of(pin.ianaTimeZone)),
        )
        val date = LocalDate.of(2026, 3, 15)
        val repository = repository(
            destination.manager,
            settingsRepository(),
            store,
            LocalDailyAggregateExportPlanner { data, _ -> plannedDay(data.date) },
        )
        val first = ExportOrchestrator(healthRepository(listOf(date)), repository)
            .exportDatesDurably(listOf(date), settings, OPERATION_ID, snapshotJson)
        assertThat(first.isFailure).isTrue()
        assertThat(first.retryFolderOperationIds).containsExactly(date, OPERATION_ID)
        assertThat(destination.totalSuccessfulWrites()).isEqualTo(0)

        destination.failAfterCreateFor = null
        val restarted = repository(
            destination.manager,
            settingsRepository(),
            store,
            LocalDailyAggregateExportPlanner { _, _ -> error("must not render") },
        )
        val unavailableHealth = mockk<HealthRepository>()
        every { unavailableHealth.isBeforeFirstUnlock() } answers { error("must not capture") }
        val resumed = ExportOrchestrator(unavailableHealth, restarted).exportDatesDurably(
            dates = listOf(date),
            settings = settings,
            durableFolderOperationId = OPERATION_ID,
            durableSettingsSnapshotJson = snapshotJson,
            requireExistingJournal = true,
        )

        assertThat(resumed.isFullSuccess).isTrue()
        assertThat(destination.successfulWriteCount("health/2026-03-15.json")).isEqualTo(1)
        verify(exactly = 0) { unavailableHealth.isBeforeFirstUnlock() }
        directory.deleteRecursively()
    }

    @Test
    fun missingKnownJournalFailsClosedWithoutCaptureRenderOrWrite() = runTest {
        val directory = temporaryDirectory("folder-journal-missing")
        val store = ScheduledFolderExportJournalStore(directory)
        val destination = InMemoryDurableDestination(
            failFirstWriteFor = "health/2026-03-16.json",
        )
        val pin = testPin(ExportEngineMode.rust)
        val settings = durableSettings(pin)
        val snapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(settings, pin, ZoneId.of(pin.ianaTimeZone)),
        )
        val dates = listOf(LocalDate.of(2026, 3, 15), LocalDate.of(2026, 3, 16))
        val firstRepository = repository(
            destination.manager,
            settingsRepository(),
            store,
            LocalDailyAggregateExportPlanner { data, _ -> plannedDay(data.date) },
        )
        val first = ExportOrchestrator(healthRepository(dates), firstRepository)
            .exportDatesDurably(dates, settings, OPERATION_ID, snapshotJson)
        assertThat(first.retryFolderOperationIds).containsKey(dates[1])
        store.discard(OPERATION_ID)
        val writesBeforeResume = destination.totalSuccessfulWrites()

        val restartedRepository = repository(
            destination.manager,
            settingsRepository(),
            store,
            LocalDailyAggregateExportPlanner { _, _ -> error("must not render") },
        )
        val unavailableHealth = mockk<HealthRepository>()
        every { unavailableHealth.isBeforeFirstUnlock() } answers { error("must not query health") }
        coEvery { unavailableHealth.fetchHealthDataRange(any(), any(), any()) } answers {
            error("must not capture")
        }
        val resumed = ExportOrchestrator(unavailableHealth, restartedRepository)
            .exportDatesDurably(
                dates = listOf(dates[1]),
                settings = settings,
                durableFolderOperationId = OPERATION_ID,
                durableSettingsSnapshotJson = snapshotJson,
                requireExistingJournal = true,
            )

        assertThat(resumed.isFailure).isTrue()
        assertThat(resumed.retryFolderOperationIds).containsExactly(dates[1], OPERATION_ID)
        assertThat(destination.totalSuccessfulWrites()).isEqualTo(writesBeforeResume)
        verify(exactly = 0) { unavailableHealth.isBeforeFirstUnlock() }
        coVerify(exactly = 0) { unavailableHealth.fetchHealthDataRange(any(), any(), any()) }
        directory.deleteRecursively()
    }

    @Test
    fun cancellationBeforeCommitWritesNothingAndDetachesJournalIdentity() = runTest {
        val directory = temporaryDirectory("folder-journal-cancel")
        val store = ScheduledFolderExportJournalStore(directory)
        val destination = InMemoryDurableDestination()
        val pin = testPin(ExportEngineMode.rust)
        val settings = durableSettings(pin)
        val snapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(settings, pin, ZoneId.of(pin.ianaTimeZone)),
        )
        val date = LocalDate.of(2026, 3, 15)
        val repository = repository(
            destination.manager,
            settingsRepository(),
            store,
            LocalDailyAggregateExportPlanner { _, _ -> error("must not render") },
        )
        val health = mockk<HealthRepository>()
        every { health.isBeforeFirstUnlock() } returns false
        coEvery { health.resolveCaptureContext(any(), any()) } answers {
            AndroidCaptureContext(firstArg(), SleepDayAttribution.NIGHT_BEGINS)
        }
        coEvery { health.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } throws
            kotlinx.coroutines.CancellationException("cancel before plan")

        val result = ExportOrchestrator(health, repository).exportDatesDurably(
            dates = listOf(date),
            settings = settings,
            durableFolderOperationId = OPERATION_ID,
            durableSettingsSnapshotJson = snapshotJson,
        )

        assertThat(result.wasCancelled).isTrue()
        assertThat(result.successCount).isEqualTo(0)
        assertThat(result.retryFolderOperationIds).isEmpty()
        assertThat(result.freshCaptureRetryDates).containsExactly(date)
        assertThat(destination.events).isEmpty()
        assertThat(store.load(OPERATION_ID)).isEqualTo(ScheduledFolderJournalLoad.Missing)
        directory.deleteRecursively()
    }

    @Test
    fun cancellationDuringCommitFinishesExactFrontierForLaterResume() = runTest {
        val directory = temporaryDirectory("folder-journal-commit-cancel")
        val store = ScheduledFolderExportJournalStore(directory)
        val destination = InMemoryDurableDestination()
        val pin = testPin(ExportEngineMode.rust)
        val settings = durableSettings(pin)
        val snapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(settings, pin, ZoneId.of(pin.ianaTimeZone)),
        )
        val date = LocalDate.of(2026, 3, 15)
        val repository = repository(
            destination.manager,
            settingsRepository(),
            store,
            LocalDailyAggregateExportPlanner { data, _ -> plannedDay(data.date) },
        )
        lateinit var exportJob: kotlinx.coroutines.Job
        destination.onWrite = { exportJob.cancel() }
        exportJob = launch {
            ExportOrchestrator(healthRepository(listOf(date)), repository).exportDatesDurably(
                dates = listOf(date),
                settings = settings,
                durableFolderOperationId = OPERATION_ID,
                durableSettingsSnapshotJson = snapshotJson,
            )
        }
        exportJob.join()
        assertThat(exportJob.isCancelled).isTrue()
        assertThat(destination.successfulWriteCount("health/2026-03-15.json")).isEqualTo(1)

        val restarted = repository(
            destination.manager,
            settingsRepository(),
            store,
            LocalDailyAggregateExportPlanner { _, _ -> error("must not render") },
        )
        val unavailableHealth = mockk<HealthRepository>()
        every { unavailableHealth.isBeforeFirstUnlock() } answers { error("must not capture") }
        val resumed = ExportOrchestrator(unavailableHealth, restarted).exportDatesDurably(
            dates = listOf(date),
            settings = settings,
            durableFolderOperationId = OPERATION_ID,
            durableSettingsSnapshotJson = snapshotJson,
            requireExistingJournal = true,
        )
        assertThat(resumed.isFullSuccess).isTrue()
        assertThat(destination.successfulWriteCount("health/2026-03-15.json")).isEqualTo(1)
        directory.deleteRecursively()
    }

    @Test
    fun acknowledgedArtifactMismatchOrRenameFailsClosedWithoutRewrite() = runTest {
        for (mutation in listOf("mismatch", "rename", "identity")) {
            val directory = temporaryDirectory("folder-journal-$mutation")
            val store = ScheduledFolderExportJournalStore(directory)
            val destination = InMemoryDurableDestination()
            val pin = testPin(ExportEngineMode.rust)
            val settings = durableSettings(pin)
            val snapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(
                AndroidExportSettingsSnapshot.capture(settings, pin, ZoneId.of(pin.ianaTimeZone)),
            )
            val date = LocalDate.of(2026, 3, 15)
            val repository = repository(
                destination.manager,
                settingsRepository(),
                store,
                LocalDailyAggregateExportPlanner { data, _ -> plannedDay(data.date) },
            )
            val first = ExportOrchestrator(healthRepository(listOf(date)), repository)
                .exportDatesDurably(listOf(date), settings, OPERATION_ID, snapshotJson)
            assertThat(first.isFullSuccess).isTrue()
            when (mutation) {
                "mismatch" -> destination.replaceContent("health/2026-03-15.json", "changed".encodeToByteArray())
                "rename" -> destination.rename("health/2026-03-15.json", "health/renamed.json")
                "identity" -> destination.replaceIdentity("health/2026-03-15.json")
            }

            val writesBeforeResume = destination.totalSuccessfulWrites()
            val restarted = repository(
                destination.manager,
                settingsRepository(),
                store,
                LocalDailyAggregateExportPlanner { _, _ -> error("must not render") },
            )
            val result = ExportOrchestrator(mockk(relaxed = true), restarted)
                .exportDatesDurably(listOf(date), settings, OPERATION_ID, snapshotJson)

            assertThat(result.isFailure).isTrue()
            assertThat(result.retryFolderOperationIds).containsExactly(date, OPERATION_ID)
            assertThat(result.artifactCount).isEqualTo(0)
            assertThat(destination.totalSuccessfulWrites()).isEqualTo(writesBeforeResume)
            directory.deleteRecursively()
        }
    }

    @Test
    fun changedFolderBindingFailsClosedBeforeCapture() = runTest {
        val directory = temporaryDirectory("folder-journal-binding")
        val store = ScheduledFolderExportJournalStore(directory)
        val destination = InMemoryDurableDestination()
        val pin = testPin(ExportEngineMode.rust)
        val settings = durableSettings(pin)
        val snapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(settings, pin, ZoneId.of(pin.ianaTimeZone)),
        )
        val date = LocalDate.of(2026, 3, 15)
        val firstSettingsRepository = settingsRepository(FOLDER_URI)
        val firstRepository = repository(
            destination.manager,
            firstSettingsRepository,
            store,
            LocalDailyAggregateExportPlanner { data, _ -> plannedDay(data.date) },
        )
        val first = ExportOrchestrator(healthRepository(listOf(date)), firstRepository)
            .exportDatesDurably(listOf(date), settings, OPERATION_ID, snapshotJson)
        assertThat(first.isFullSuccess).isTrue()

        val changedRepository = repository(
            destination.manager,
            settingsRepository("content://different-folder"),
            store,
            LocalDailyAggregateExportPlanner { _, _ -> error("must not render") },
        )
        val unavailableHealth = mockk<HealthRepository>()
        every { unavailableHealth.isBeforeFirstUnlock() } answers {
            error("changed binding must fail before lock state")
        }
        coEvery { unavailableHealth.fetchHealthDataRange(any(), any(), any()) } answers {
            error("changed binding must fail before capture")
        }
        val resumed = ExportOrchestrator(unavailableHealth, changedRepository)
            .exportDatesDurably(listOf(date), settings, OPERATION_ID, snapshotJson)

        assertThat(resumed.isFailure).isTrue()
        assertThat(resumed.retryFolderOperationIds).containsExactly(date, OPERATION_ID)
        verify(exactly = 0) { unavailableHealth.isBeforeFirstUnlock() }
        coVerify(exactly = 0) { unavailableHealth.fetchHealthDataRange(any(), any(), any()) }
        directory.deleteRecursively()
    }

    private fun repository(
        manager: FileExportManager,
        settingsRepository: SettingsRepository,
        store: ScheduledFolderExportJournalStore,
        planner: LocalDailyAggregateExportPlanner,
    ): ExportRepositoryImpl = ExportRepositoryImpl(
        fileExportManager = manager,
        markdownExporter = MarkdownExporter(),
        jsonExporter = JsonExporter(),
        csvExporter = CsvExporter(),
        obsidianBasesExporter = ObsidianBasesExporter(),
        settingsRepository = settingsRepository,
        scheduledFolderJournalStore = store,
        dailyAggregatePlanner = planner,
    )

    private fun settingsRepository(folderUri: String = FOLDER_URI): SettingsRepository =
        mockk<SettingsRepository>().also { repository ->
            coEvery { repository.getExportFolderUri() } returns folderUri
        }

    private fun healthRepository(dates: List<LocalDate>): HealthRepository =
        mockk<HealthRepository>().also { repository ->
            every { repository.isBeforeFirstUnlock() } returns false
            coEvery { repository.resolveCaptureContext(any(), any()) } answers {
                AndroidCaptureContext(firstArg(), SleepDayAttribution.NIGHT_BEGINS)
            }
            coEvery { repository.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } answers {
                firstArg<List<LocalDate>>().map { date ->
                    HealthData(date = date, activity = ActivityData(steps = 1_234))
                }
            }
        }

    private fun durableSettings(pin: com.healthmd.domain.exportengine.ExportEnginePin): ExportSettings =
        ExportSettings(
            exportFormat = ExportFormat.JSON,
            exportFormats = setOf(ExportFormat.JSON),
            writeMode = WriteMode.OVERWRITE,
            exportTarget = ExportTarget.DEVICE_FOLDER,
            scheduledExportTarget = ExportTarget.DEVICE_FOLDER,
            executionEnginePin = pin,
            executionEngineAuthorityIsFrozen = true,
        )

    private fun plannedDay(date: LocalDate): LocalDailyAggregatePlanningResult.Planned {
        val requestId = "request-${date.toString().replace("-", "")}"
        val sessionId = "session-${date.toString().replace("-", "")}"
        val path = "health/$date.json"
        val content = "{\"date\":\"$date\"}".encodeToByteArray()
        val hash = artifactSha256Hex(content)
        val item = ExportArtifactPlanItem(
            artifactId = artifactIdHex(
                requestId = requestId,
                sessionId = sessionId,
                profile = AndroidExportProfile.android_frozen_v4,
                relativePath = path,
                mediaType = "application/json",
                writeMode = ExportArtifactWriteMode.overwrite,
                contentSha256 = hash,
            ),
            relativePath = path,
            mediaType = "application/json",
            writeMode = ExportArtifactWriteMode.overwrite,
            content = content,
        )
        return LocalDailyAggregatePlanningResult.Planned(
            mode = ExportEngineMode.rust,
            plan = ExportArtifactPlan(
                schema = ExportArtifactPlan.SCHEMA,
                artifactPlanVersion = ExportArtifactPlan.VERSION,
                requestId = requestId,
                sessionId = sessionId,
                profile = AndroidExportProfile.android_frozen_v4,
                items = listOf(item),
            ),
            formats = listOf(ExportFormat.JSON),
        )
    }

    private fun temporaryDirectory(prefix: String): File =
        kotlin.io.path.createTempDirectory(prefix).toFile()

    private class InMemoryDurableDestination(
        var failFirstWriteFor: String? = null,
        var failAfterCreateFor: String? = null,
        val events: MutableList<String> = mutableListOf(),
    ) {
        private data class Document(val id: String, var content: ByteArray)

        private val documents = linkedMapOf<String, Document>()
        private val successfulWrites = mutableMapOf<String, Int>()
        private val failedOnce = mutableSetOf<String>()
        private val failedAfterCreateOnce = mutableSetOf<String>()
        var onBind: (() -> Unit)? = null
        var onWrite: (() -> Unit)? = null
        val manager: FileExportManager = mockk(relaxed = true)

        init {
            every { manager.bindDurableFile(any(), any(), any(), any(), any()) } answers {
                val path = secondArg<String>()
                onBind?.invoke()
                onBind = null
                events += "bind:$path"
                val expectedDocumentId = arg<String?>(3)
                val requireMissing = arg<Boolean>(4)
                val existing = documents[path]
                if (requireMissing && existing != null) return@answers null
                if (expectedDocumentId != null && existing?.id != expectedDocumentId) {
                    return@answers null
                }
                val document = existing ?: Document(
                    "document-${documents.size + 1}",
                    byteArrayOf(),
                ).also { documents[path] = it }
                val createFailure = failAfterCreateFor
                if (existing == null && createFailure != null &&
                    matchesConfiguredPath(path, createFailure) &&
                    failedAfterCreateOnce.add(createFailure)
                ) {
                    return@answers null
                }
                FileExportManager.DurableBoundFile(document.id)
            }
            every { manager.inspectDurableFile(any(), any()) } answers {
                val path = secondArg<String>()
                val document = documents[path]
                if (document == null) {
                    FileExportManager.DurableFileInspection.Missing
                } else {
                    FileExportManager.DurableFileInspection.Found(
                        documentId = document.id,
                        content = document.content.copyOf(),
                    )
                }
            }
            every { manager.overwriteDurableBoundFile(any(), any(), any(), any()) } answers {
                val path = secondArg<String>()
                events += "write:$path"
                onWrite?.invoke()
                onWrite = null
                val configuredFailure = failFirstWriteFor
                val matchesFailure = configuredFailure != null &&
                    matchesConfiguredPath(path, configuredFailure)
                if (matchesFailure && failedOnce.add(configuredFailure!!)) {
                    false
                } else {
                    val document = checkNotNull(documents[path])
                    if (document.id != thirdArg<String>()) return@answers false
                    document.content = arg<ByteArray>(3).copyOf()
                    successfulWrites[path] = successfulWrites.getOrDefault(path, 0) + 1
                    true
                }
            }
            every { manager.renameDurableBoundFile(any(), any(), any(), any()) } answers {
                val stagingPath = secondArg<String>()
                val finalPath = thirdArg<String>()
                val expectedId = arg<String>(3)
                events += "rename:$stagingPath->$finalPath"
                val document = documents[stagingPath] ?: return@answers null
                if (document.id != expectedId || documents.containsKey(finalPath)) {
                    return@answers null
                }
                documents.remove(stagingPath)
                documents[finalPath] = document
                successfulWrites.remove(stagingPath)?.let { count ->
                    successfulWrites[finalPath] = successfulWrites.getOrDefault(finalPath, 0) + count
                }
                FileExportManager.DurableBoundFile(document.id)
            }
        }

        private fun matchesConfiguredPath(actual: String, configured: String): Boolean =
            actual == configured ||
                actual.substringBeforeLast('/', "") == configured.substringBeforeLast('/', "") &&
                actual.substringAfterLast('/').startsWith(
                    ".${configured.substringAfterLast('/')}.healthmd-",
                )

        fun successfulWriteCount(path: String): Int = successfulWrites.getOrDefault(path, 0)

        fun totalSuccessfulWrites(): Int = successfulWrites.values.sum()

        fun replaceContent(path: String, content: ByteArray) {
            checkNotNull(documents[path]).content = content.copyOf()
        }

        fun rename(from: String, to: String) {
            documents[to] = checkNotNull(documents.remove(from))
        }

        fun replaceIdentity(path: String) {
            val existing = checkNotNull(documents[path])
            documents[path] = Document("replacement-document", existing.content.copyOf())
        }
    }

    companion object {
        private const val FOLDER_URI = "content://exports/tree/root"
        private const val OPERATION_ID = "folder-operation-1"
    }
}
