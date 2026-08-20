package com.healthmd.data.drive

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.exportengine.sha256Hex
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
        coEvery {
            runner.resumeIfPresent(
                operationId = "operation-retained",
                expectedDestinationId = "destination-1",
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
        coVerify(exactly = 0) { bundleFactory.daily(any(), any(), any(), any(), any(), any()) }
    }
}
