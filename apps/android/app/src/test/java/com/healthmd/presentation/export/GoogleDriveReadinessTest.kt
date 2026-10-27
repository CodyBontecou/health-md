package com.healthmd.presentation.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import org.junit.Test

class GoogleDriveReadinessTest {
    @Test
    fun `manual export requires both build configuration and persisted destination`() {
        val driveSettings = ExportSettings(exportTarget = ExportTarget.GOOGLE_DRIVE)

        assertThat(
            ExportUiState(
                settings = driveSettings,
                googleDriveDestinationId = "destination-1",
                googleDriveConfigurationAvailable = false,
            ).destinationReady,
        ).isFalse()
        assertThat(
            ExportUiState(
                settings = driveSettings,
                googleDriveDestinationId = null,
                googleDriveConfigurationAvailable = true,
            ).destinationReady,
        ).isFalse()
        assertThat(
            ExportUiState(
                settings = driveSettings,
                googleDriveDestinationId = "destination-1",
                googleDriveConfigurationAvailable = true,
            ).destinationReady,
        ).isTrue()
    }

    @Test
    fun `profile creation binds the connected local Drive destination`() {
        val draft = ExportProfilesViewModel.initialCreationDraft(
            rows = emptyList(),
            currentSettings = ExportSettings(scheduledExportTarget = ExportTarget.GOOGLE_DRIVE),
            connectedGoogleDriveDestinationId = "destination-1",
        )

        assertThat(draft.target).isEqualTo(ExportTarget.GOOGLE_DRIVE)
        assertThat(draft.destinationId).isEqualTo("destination-1")
    }
}
