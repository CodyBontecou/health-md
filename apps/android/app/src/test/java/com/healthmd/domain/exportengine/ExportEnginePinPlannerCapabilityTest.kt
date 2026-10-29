package com.healthmd.domain.exportengine

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.domain.model.WriteMode
import com.healthmd.rawexport.ExportMode
import org.junit.Test

class ExportEnginePinPlannerCapabilityTest {
    @Test
    fun folderAndDirectPinsRequireTheCompleteSimpleOverwriteOperation() {
        val supported = simpleSettings()
        val unsupported = listOf(
            supported.copy(writeMode = WriteMode.APPEND),
            supported.copy(writeMode = WriteMode.UPDATE),
            supported.copy(dailyNoteInjection = DailyNoteInjectionSettings(enabled = true)),
            supported.copy(individualTracking = IndividualTrackingSettings(globalEnabled = true)),
            supported.copy(exportMode = ExportMode.RAW_SNAPSHOT),
            supported.copy(exportFormats = emptySet()),
        )

        assertThat(
            ExportEnginePinPlanner.supportsNewScheduledPin(
                supported,
                ExportTarget.DEVICE_FOLDER,
            ),
        ).isTrue()
        assertThat(ExportEnginePinPlanner.supportsNewDirectGeneratedFilesPin(supported)).isTrue()
        unsupported.forEach { settings ->
            assertThat(
                ExportEnginePinPlanner.supportsNewScheduledPin(
                    settings,
                    ExportTarget.DEVICE_FOLDER,
                ),
            ).isFalse()
            assertThat(
                ExportEnginePinPlanner.supportsNewDirectGeneratedFilesPin(settings),
            ).isFalse()
        }
    }

    @Test
    fun gatewayPinsUseFolderCapabilitiesWithoutChangingTheDestination() {
        val gateway = simpleSettings().copy(exportTarget = ExportTarget.AGENT_DATA_GATEWAY)
        assertThat(ExportEnginePinPlanner.supportsNewScheduledPin(gateway, ExportTarget.AGENT_DATA_GATEWAY)).isTrue()
        for (unsupported in listOf(gateway.copy(writeMode = WriteMode.APPEND),
            gateway.copy(dailyNoteInjection = DailyNoteInjectionSettings(enabled = true)),
            gateway.copy(exportMode = ExportMode.RAW_SNAPSHOT))) {
            assertThat(ExportEnginePinPlanner.supportsNewScheduledPin(unsupported, ExportTarget.AGENT_DATA_GATEWAY)).isFalse()
        }
        assertThat(gateway.exportTarget).isEqualTo(ExportTarget.AGENT_DATA_GATEWAY)
    }

    @Test
    fun apiPinsRequireCompatibilityRecordsAndAtLeastOneFormatButIgnoreFileWriteMode() {
        val supported = simpleSettings().copy(writeMode = WriteMode.APPEND)

        assertThat(
            ExportEnginePinPlanner.supportsNewScheduledPin(
                supported,
                ExportTarget.API_ENDPOINT,
            ),
        ).isTrue()
        assertThat(
            ExportEnginePinPlanner.supportsNewScheduledPin(
                supported.copy(exportFormats = emptySet()),
                ExportTarget.API_ENDPOINT,
            ),
        ).isFalse()
        assertThat(
            ExportEnginePinPlanner.supportsNewScheduledPin(
                supported.copy(exportMode = ExportMode.RAW_SNAPSHOT),
                ExportTarget.API_ENDPOINT,
            ),
        ).isFalse()
    }

    private fun simpleSettings(): ExportSettings = ExportSettings(
        exportFormat = ExportFormat.JSON,
        exportFormats = setOf(ExportFormat.JSON),
        writeMode = WriteMode.OVERWRITE,
    )
}
