package com.healthmd.data.drive

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.sha256Hex
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.HealthRepository
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import java.time.LocalDate
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.Test

class GoogleDriveExportOrchestratorTest {
    private val healthRepository = mockk<HealthRepository>()
    private val bundleFactory = mockk<GeneratedExportBundleFactory>()
    private val runner = mockk<GoogleDriveDestinationRunner>()
    private val orchestrator = GoogleDriveExportOrchestrator(healthRepository, bundleFactory, runner)

    @Test
    fun `retained operation resumes before Health Connect capture`() = runTest {
        val date = LocalDate.parse("2026-03-15")
        val settings = ExportSettings(
            exportFormats = setOf(ExportFormat.MARKDOWN),
            exportTarget = ExportTarget.GOOGLE_DRIVE,
        )
        val snapshot = Json.encodeToString(ExportSettings.serializer(), settings)
        coEvery { runner.recoveryJournal("operation-retained") } returns GoogleDriveJournalLoad.Found(
            GoogleDriveOperationJournal(
                operationId = "operation-retained", source = "manual", ownerDates = listOf(date.toString()),
                captureEvidence = GoogleDriveCaptureEvidence(listOf(date.toString()), listOf(date.toString()), emptyList()),
                destinationId = "destination-1", destinationFingerprint = "fingerprint", bundleDigest = "digest",
                settingsSnapshotSha256 = sha256Hex(snapshot.encodeToByteArray()), rendererPin = "renderer",
                artifacts = emptyList(), createdAtEpochMillis = 1, updatedAtEpochMillis = 1,
            ),
        )
        coEvery {
            runner.resumeIfPresent(
                operationId = "operation-retained",
                expectedDestinationId = "destination-1",
                expectedOwnerDates = listOf(date),
                expectedSettingsSnapshotSha256 = sha256Hex(snapshot.encodeToByteArray()),
            )
        } returns GoogleDriveRunResult.Complete(artifactCount = 1)

        val result = orchestrator.exportDates(
            dates = listOf(date),
            settings = settings,
            destinationId = "destination-1",
            operationId = "operation-retained",
            settingsSnapshotJson = snapshot,
        )

        assertThat(result.successCount).isEqualTo(1)
        assertThat(result.artifactCount).isEqualTo(1)
        coVerify(exactly = 0) { healthRepository.isBeforeFirstUnlock() }
        coVerify(exactly = 0) { healthRepository.hasPermissions() }
        coVerify(exactly = 0) { bundleFactory.daily(any(), any(), any(), any(), any(), any(), any(), any()) }
    }
    @Test
    fun `fresh capture requires permission even when repository would accept a query`() = runTest {
        val date = LocalDate.parse("2026-03-15")
        coEvery { runner.recoveryJournal(any()) } returns GoogleDriveJournalLoad.Missing
        coEvery { healthRepository.hasPermissions() } returns false
        coEvery { healthRepository.isBeforeFirstUnlock() } returns false
        coEvery { healthRepository.fetchHealthDataRange(any(), any(), any()) } throws SecurityException("synthetic denied")
        val result = orchestrator.exportDates(listOf(date), ExportSettings(), "destination-1")
        assertThat(result.failedDateDetails.single().reason).isEqualTo(ExportFailureReason.ACCESS_DENIED)
        coVerify(exactly = 0) { healthRepository.fetchHealthDataRange(any(), any(), any()) }
        coVerify(exactly = 0) { bundleFactory.daily(any(), any(), any(), any(), any(), any(), any(), any()) }
    }

    @Test
    fun `retained replay cannot transition into residual capture without permission`() = runTest {
        val captured = LocalDate.parse("2026-03-15")
        val failed = captured.plusDays(1)
        val settings = ExportSettings(exportTarget = ExportTarget.GOOGLE_DRIVE)
        val snapshot = Json.encodeToString(ExportSettings.serializer(), settings)
        coEvery { runner.recoveryJournal(any()) } returns GoogleDriveJournalLoad.Missing
        coEvery { runner.recoveryJournal("retained") } returns GoogleDriveJournalLoad.Found(
            GoogleDriveOperationJournal(
                operationId = "retained", source = "manual", ownerDates = listOf(captured.toString()),
                captureEvidence = GoogleDriveCaptureEvidence(
                    listOf(captured.toString(), failed.toString()), listOf(captured.toString()),
                    listOf(FailedDateDetail(failed, ExportFailureReason.ACCESS_DENIED)),
                ),
                destinationId = "destination-1", destinationFingerprint = "fingerprint", bundleDigest = "digest",
                settingsSnapshotSha256 = sha256Hex(snapshot.encodeToByteArray()), rendererPin = "renderer",
                artifacts = emptyList(), createdAtEpochMillis = 1, updatedAtEpochMillis = 1,
            ),
        )
        coEvery { runner.resumeIfPresent("retained", "destination-1", listOf(captured), any()) } returns
            GoogleDriveRunResult.Complete(artifactCount = 1)
        coEvery { healthRepository.hasPermissions() } returns false
        coEvery { healthRepository.isBeforeFirstUnlock() } returns false
        coEvery { healthRepository.fetchHealthDataRange(any(), any(), any()) } throws SecurityException("synthetic denied")
        val result = orchestrator.exportDates(listOf(failed), settings, "destination-1",
            operationId = "retained", settingsSnapshotJson = snapshot)
        assertThat(result.failedDateDetails.single().reason).isEqualTo(ExportFailureReason.ACCESS_DENIED)
        coVerify(exactly = 1) { runner.resumeIfPresent("retained", "destination-1", listOf(captured), any()) }
        coVerify(exactly = 0) { healthRepository.fetchHealthDataRange(any(), any(), any()) }
    }

}
