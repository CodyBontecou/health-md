package com.healthmd.data.scheduler

import android.content.Context
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.RawSnapshotService
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportPreview
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.rawexport.ExportMode
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.PendingScheduledExportRequest
import com.healthmd.export.FakeExportHistoryRepository
import com.healthmd.export.FakeExportRepository
import com.healthmd.export.FakeHealthRepository
import com.healthmd.export.FakeSettingsRepository
import com.healthmd.testing.syntheticExportEnginePin
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.test.runTest
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneId

class ScheduledExportRecoveryManagerTest {

    @Test
    fun inspectPendingRecovery_returnsReadyWhenAppOpenPrerequisitesAreMet() = runTest {
        val pendingDate = LocalDate.now().minusDays(1)
        val manager = manager(
            settingsRepository = FakeSettingsRepository(
                initialSettings = settingsWithPending(pendingDate),
                initialFolderUri = "content://exports",
                initialPurchased = true,
            ),
            healthRepository = FakeHealthRepository().apply {
                permissionsGranted = true
                beforeFirstUnlock = false
            },
        )

        val status = manager.inspectPendingRecovery()

        assertThat(status.canRecover).isTrue()
        assertThat(status.pendingDates).containsExactly(pendingDate)
        assertThat(status.blocker).isNull()
    }

    @Test
    fun inspectAllowsStoredApiBodyResumeWithoutHealthAccess() = runTest {
        val pendingDate = LocalDate.now().minusDays(1)
        val fingerprint = "a".repeat(64)
        val credentials = object : APIExportCredentialStore {
            override suspend fun authorizationHeader(): String? = null
            override suspend fun hasAuthorization(): Boolean = false
            override suspend fun saveAuthorization(value: String) = Unit
            override suspend fun clearAuthorization() = Unit
            override suspend fun destinationFingerprint(endpointUrl: String): String = fingerprint
        }
        val manager = manager(
            settingsRepository = FakeSettingsRepository(
                initialSettings = ExportSettings(
                    scheduledExportTarget = ExportTarget.API_ENDPOINT,
                    apiEndpointUrl = "https://api.example.com/ingest",
                    pendingScheduledExportRequests = listOf(
                        PendingScheduledExportRequest(
                            date = pendingDate,
                            exportTarget = ExportTarget.API_ENDPOINT,
                            destinationFingerprint = fingerprint,
                            apiOperationId = "11111111-2222-3333-4444-555555555555",
                        ),
                    ),
                ),
                initialPurchased = true,
            ),
            healthRepository = FakeHealthRepository().apply {
                permissionsGranted = false
                beforeFirstUnlock = true
            },
            apiCredentialStore = credentials,
        )

        val status = manager.inspectPendingRecovery()

        assertThat(status.canRecover).isTrue()
        assertThat(status.blocker).isNull()
    }

    @Test
    fun inspectAllowsStoredFolderPlanResumeWithoutHealthAccess() = runTest {
        val pendingDate = LocalDate.now().minusDays(1)
        val pin = syntheticExportEnginePin(mode = ExportEngineMode.rust)
        val frozenSettings = ExportSettings(
            exportFormat = ExportFormat.JSON,
            exportFormats = setOf(ExportFormat.JSON),
            exportTarget = ExportTarget.DEVICE_FOLDER,
            scheduledExportTarget = ExportTarget.DEVICE_FOLDER,
        )
        val snapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(
                frozenSettings,
                pin,
                ZoneId.of(pin.ianaTimeZone),
            ),
        )
        val operationId = "folder-operation-1"
        val exportRepository = FakeExportRepository().apply {
            resumableFolderOperationIds += operationId
        }
        val manager = manager(
            settingsRepository = FakeSettingsRepository(
                initialSettings = frozenSettings.copy(
                    pendingScheduledExportRequests = listOf(
                        PendingScheduledExportRequest(
                            date = pendingDate,
                            enginePin = pin,
                            settingsSnapshotJson = snapshotJson,
                            folderOperationId = operationId,
                        ),
                    ),
                ),
                initialFolderUri = "content://exports",
                initialPurchased = true,
            ),
            healthRepository = FakeHealthRepository().apply {
                permissionsGranted = false
                beforeFirstUnlock = true
            },
            exportRepository = exportRepository,
        )

        val status = manager.inspectPendingRecovery()

        assertThat(status.canRecover).isTrue()
        assertThat(status.blocker).isNull()
    }

    @Test
    fun knownFolderJournalWithMissingPinAndSnapshotFailsClosedWithoutExportOrDeletion() = runTest {
        val pendingDate = LocalDate.now().minusDays(1)
        val operationId = "folder-operation-legacy-metadata"
        val exportRepository = FakeExportRepository()
        val settingsRepository = FakeSettingsRepository(
            initialSettings = ExportSettings(
                scheduledExportTarget = ExportTarget.DEVICE_FOLDER,
                pendingScheduledExportRequests = listOf(
                    PendingScheduledExportRequest(
                        date = pendingDate,
                        folderOperationId = operationId,
                    ),
                ),
            ),
            initialFolderUri = "content://exports",
            initialPurchased = true,
        )
        val manager = manager(
            settingsRepository = settingsRepository,
            healthRepository = FakeHealthRepository().apply {
                permissionsGranted = true
                beforeFirstUnlock = false
                putData(HealthData(pendingDate, activity = ActivityData(steps = 100)))
            },
            exportRepository = exportRepository,
        )

        val result = manager.recoverPendingDates()

        assertThat(result.exportResult?.isFailure).isTrue()
        assertThat(exportRepository.exportedDates).isEmpty()
        assertThat(exportRepository.discardedFolderOperationIds).isEmpty()
        val pending = ScheduledExportPendingRequests.pendingRequests(
            settingsRepository.getExportSettings(),
        ).single()
        assertThat(pending.folderOperationId).isEqualTo(operationId)
    }

    @Test
    fun inspectPendingRecovery_blocksWithoutExportFolder() = runTest {
        val pendingDate = LocalDate.now().minusDays(1)
        val manager = manager(
            settingsRepository = FakeSettingsRepository(
                initialSettings = settingsWithPending(pendingDate),
                initialFolderUri = null,
                initialPurchased = true,
            ),
        )

        val status = manager.inspectPendingRecovery()

        assertThat(status.canRecover).isFalse()
        assertThat(status.blocker).isEqualTo(ScheduledExportRecoveryBlocker.NO_EXPORT_FOLDER)
    }

    @Test
    fun recoverPendingDates_suppressesDuplicateRuns() = runTest {
        val pendingDate = LocalDate.now().minusDays(1)
        val healthRepository = FakeHealthRepository().apply {
            putData(HealthData(date = pendingDate, activity = ActivityData(steps = 42)))
        }
        val exportStarted = CompletableDeferred<Unit>()
        val releaseExport = CompletableDeferred<Unit>()
        val exportRepository = FakeExportRepository().apply {
            exportBehavior = { _, _ ->
                exportStarted.complete(Unit)
                releaseExport.await()
                true
            }
        }
        val manager = manager(
            healthRepository = healthRepository,
            exportRepository = exportRepository,
            settingsRepository = FakeSettingsRepository(
                initialSettings = settingsWithPending(pendingDate),
                initialFolderUri = "content://exports",
                initialPurchased = true,
            ),
        )

        val firstRun = async { manager.recoverPendingDates() }
        exportStarted.await()

        val duplicateRun = manager.recoverPendingDates()

        assertThat(duplicateRun.status).isEqualTo(ScheduledExportRecoveryRunStatus.ALREADY_RUNNING)
        releaseExport.complete(Unit)
        assertThat(firstRun.await().status).isEqualTo(ScheduledExportRecoveryRunStatus.COMPLETED)
    }

    @Test
    fun recoverPendingDates_preservesSettingsChangedWhileExportRuns() = runTest {
        val pendingDate = LocalDate.now().minusDays(1)
        val healthRepository = FakeHealthRepository().apply {
            putData(HealthData(date = pendingDate, activity = ActivityData(steps = 42)))
        }
        val exportStarted = CompletableDeferred<Unit>()
        val releaseExport = CompletableDeferred<Unit>()
        val exportRepository = FakeExportRepository().apply {
            exportBehavior = { _, _ ->
                exportStarted.complete(Unit)
                releaseExport.await()
                true
            }
        }
        val settingsRepository = FakeSettingsRepository(
            initialSettings = settingsWithPending(pendingDate),
            initialFolderUri = "content://exports",
            initialPurchased = true,
        )
        val manager = manager(
            healthRepository = healthRepository,
            exportRepository = exportRepository,
            settingsRepository = settingsRepository,
        )

        val recovery = async { manager.recoverPendingDates() }
        exportStarted.await()
        val edited = settingsRepository.getExportSettings().copy(
            apiEndpointUrl = "https://new.example.com/ingest",
            scheduleHour = 17,
        )
        settingsRepository.updateExportSettings(edited)
        releaseExport.complete(Unit)
        recovery.await()

        val finalSettings = settingsRepository.getExportSettings()
        assertThat(finalSettings.apiEndpointUrl).isEqualTo("https://new.example.com/ingest")
        assertThat(finalSettings.scheduleHour).isEqualTo(17)
        assertThat(ScheduledExportPendingRequests.pendingDates(finalSettings)).isEmpty()
    }

    @Test
    fun recoverPendingDates_clearsOnlySuccessfullyExportedPendingDates() = runTest {
        val successDate = LocalDate.now().minusDays(2)
        val failedDate = LocalDate.now().minusDays(1)
        val healthRepository = FakeHealthRepository().apply {
            putData(HealthData(date = successDate, activity = ActivityData(steps = 10)))
            putData(HealthData(date = failedDate, activity = ActivityData(steps = 20)))
        }
        val exportRepository = FakeExportRepository().apply {
            resultsByDate[successDate] = true
            resultsByDate[failedDate] = false
        }
        val settingsRepository = FakeSettingsRepository(
            initialSettings = ExportSettings(
                pendingScheduledExportRequests = listOf(
                    PendingScheduledExportRequest(date = successDate, firstFailedAtMillis = 100L, attemptCount = 1),
                    PendingScheduledExportRequest(date = failedDate, firstFailedAtMillis = 100L, attemptCount = 1),
                ),
            ),
            initialFolderUri = "content://exports",
            initialPurchased = true,
        )
        val historyRepository = FakeExportHistoryRepository()
        val manager = manager(
            healthRepository = healthRepository,
            exportRepository = exportRepository,
            settingsRepository = settingsRepository,
            historyRepository = historyRepository,
        )

        val result = manager.recoverPendingDates()

        assertThat(result.status).isEqualTo(ScheduledExportRecoveryRunStatus.COMPLETED)
        assertThat(result.exportResult?.successCount).isEqualTo(1)
        assertThat(ScheduledExportPendingRequests.pendingDates(settingsRepository.getExportSettings()))
            .containsExactly(failedDate)
        assertThat(historyRepository.entries).hasSize(1)
        assertThat(historyRepository.entries.single().source.name).isEqualTo("SCHEDULED")
    }

    @Test
    fun recoveryUsesAcceptedSnapshotAfterOutputSettingsWereEdited() = runTest {
        val pendingDate = LocalDate.now().minusDays(1)
        val acceptedSettings = ExportSettings(
            exportFormats = setOf(ExportFormat.CSV),
            filenameFormat = "accepted-{date}",
            folderStructure = "accepted/{year}",
            includeMetadata = false,
        )
        val snapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(
                acceptedSettings,
                pin = null,
                zone = ZoneId.of("UTC"),
            ),
        )
        val currentSettings = acceptedSettings.copy(
            exportFormats = setOf(ExportFormat.JSON),
            filenameFormat = "current-{date}",
            folderStructure = "current",
            includeMetadata = true,
            pendingScheduledExportRequests = listOf(
                PendingScheduledExportRequest(
                    date = pendingDate,
                    settingsSnapshotJson = snapshotJson,
                    firstFailedAtMillis = 100L,
                    attemptCount = 1,
                ),
            ),
        )
        val healthRepository = FakeHealthRepository().apply {
            putData(HealthData(date = pendingDate, activity = ActivityData(steps = 42)))
        }
        val exportRepository = FakeExportRepository()
        val settingsRepository = FakeSettingsRepository(
            initialSettings = currentSettings,
            initialFolderUri = "content://exports",
            initialPurchased = true,
        )

        val result = manager(
            healthRepository = healthRepository,
            exportRepository = exportRepository,
            settingsRepository = settingsRepository,
        ).recoverPendingDates()

        assertThat(result.status).isEqualTo(ScheduledExportRecoveryRunStatus.COMPLETED)
        val executed = exportRepository.exportSettings.single()
        assertThat(executed.exportFormats).containsExactly(ExportFormat.CSV)
        assertThat(executed.filenameFormat).isEqualTo("accepted-{date}")
        assertThat(executed.folderStructure).isEqualTo("accepted/{year}")
        assertThat(executed.includeMetadata).isFalse()
    }

    @Test
    fun corruptOrPinMismatchedSnapshotFailsWithoutProviderReadsAndRemainsPending() = runTest {
        val corruptDate = LocalDate.now().minusDays(2)
        val mismatchedDate = LocalDate.now().minusDays(1)
        val rustPin = syntheticExportEnginePin(mode = ExportEngineMode.rust)
        val shadowPin = syntheticExportEnginePin(mode = ExportEngineMode.shadow)
        val validSnapshotJson = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(
                ExportSettings(),
                rustPin,
                ZoneId.of("America/Los_Angeles"),
            ),
        )
        val settingsRepository = FakeSettingsRepository(
            initialSettings = ExportSettings(
                pendingScheduledExportRequests = listOf(
                    PendingScheduledExportRequest(
                        date = corruptDate,
                        settingsSnapshotJson = "{corrupt",
                        firstFailedAtMillis = 100L,
                        attemptCount = 1,
                    ),
                    PendingScheduledExportRequest(
                        date = mismatchedDate,
                        enginePin = shadowPin,
                        settingsSnapshotJson = validSnapshotJson,
                        firstFailedAtMillis = 100L,
                        attemptCount = 1,
                    ),
                ),
            ),
            initialFolderUri = "content://exports",
            initialPurchased = true,
        )
        val healthRepository = FakeHealthRepository()
        val exportRepository = FakeExportRepository()

        val result = manager(
            healthRepository = healthRepository,
            exportRepository = exportRepository,
            settingsRepository = settingsRepository,
        ).recoverPendingDates()

        assertThat(result.exportResult?.successCount).isEqualTo(0)
        assertThat(result.exportResult?.failedDateDetails?.map { it.date })
            .containsExactly(corruptDate, mismatchedDate)
        assertThat(healthRepository.fetchedDates).isEmpty()
        assertThat(exportRepository.exportedDates).isEmpty()
        val retained = ScheduledExportPendingRequests.pendingRequests(
            settingsRepository.getExportSettings(),
        )
        assertThat(retained.map { it.date }).containsExactly(corruptDate, mismatchedDate)
        assertThat(retained.first { it.date == corruptDate }.settingsSnapshotJson)
            .isEqualTo("{corrupt")
        assertThat(retained.first { it.date == mismatchedDate }.settingsSnapshotJson)
            .isEqualTo(validSnapshotJson)
    }

    @Test
    fun recoverMultiDayPartialRawResultKeepsEveryAttemptedDatePending() = runTest {
        val dates = listOf(LocalDate.now().minusDays(3), LocalDate.now().minusDays(2), LocalDate.now().minusDays(1))
        val settingsRepository = FakeSettingsRepository(
            initialSettings = ExportSettings(
                exportMode = ExportMode.RAW_SNAPSHOT,
                pendingScheduledExportRequests = dates.map {
                    PendingScheduledExportRequest(date = it, firstFailedAtMillis = 100L, attemptCount = 1)
                },
            ),
            initialFolderUri = "content://exports",
            initialPurchased = true,
        )
        val partialRawService = object : RawSnapshotService {
            override suspend fun exportRange(
                startDate: LocalDate,
                endDate: LocalDate,
                settings: ExportSettings,
                target: ExportTarget,
                expectedDestinationFingerprint: String?,
                allowInteractiveRouteConsent: Boolean,
            ) = ExportResult(
                successCount = 1,
                totalCount = 2,
                failedDateDetails = listOf(FailedDateDetail(startDate, ExportFailureReason.RAW_PARTIAL, "fitbit incomplete")),
                target = target,
                exportMode = ExportMode.RAW_SNAPSHOT,
                artifactCount = 1,
            )

            override suspend fun previewRange(
                startDate: LocalDate,
                endDate: LocalDate,
                settings: ExportSettings,
                allowInteractiveRouteConsent: Boolean,
            ): ExportPreview = error("Preview is not used by scheduled recovery")
        }
        val manager = manager(
            settingsRepository = settingsRepository,
            rawSnapshotService = partialRawService,
        )

        manager.recoverPendingDates()

        assertThat(ScheduledExportPendingRequests.pendingDates(settingsRepository.getExportSettings()))
            .containsExactlyElementsIn(dates)
    }

    private fun settingsWithPending(date: LocalDate): ExportSettings = ExportSettings(
        pendingScheduledExportRequests = listOf(
            PendingScheduledExportRequest(date = date, firstFailedAtMillis = 100L, attemptCount = 1)
        ),
    )

    private fun manager(
        healthRepository: FakeHealthRepository = FakeHealthRepository(),
        exportRepository: FakeExportRepository = FakeExportRepository(),
        settingsRepository: FakeSettingsRepository = FakeSettingsRepository(initialPurchased = true),
        historyRepository: FakeExportHistoryRepository = FakeExportHistoryRepository(),
        rawSnapshotService: RawSnapshotService? = null,
        apiCredentialStore: APIExportCredentialStore? = null,
    ): ScheduledExportRecoveryManager = ScheduledExportRecoveryManager(
        applicationContext = mockk<Context>(relaxed = true) {
            every { resources } returns mockk(relaxed = true)
        },
        healthRepository = healthRepository,
        exportRepository = exportRepository,
        settingsRepository = settingsRepository,
        exportHistoryRepository = historyRepository,
        rawSnapshotService = rawSnapshotService,
        apiCredentialStore = apiCredentialStore,
    )
}
