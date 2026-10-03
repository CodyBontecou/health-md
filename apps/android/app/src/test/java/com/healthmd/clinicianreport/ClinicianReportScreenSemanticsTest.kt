package com.healthmd.clinicianreport

import com.google.common.truth.Truth.assertThat
import com.healthmd.R
import com.healthmd.presentation.clinicianreport.ClinicianReportBusyAction
import com.healthmd.presentation.clinicianreport.ClinicianReportUiState
import com.healthmd.presentation.clinicianreport.clinicianReportBusyDescription
import com.healthmd.presentation.clinicianreport.clinicianReportConfigurationControlsEnabled
import org.junit.Test

class ClinicianReportScreenSemanticsTest {
    @Test fun configurationControlsAreEnabledOnlyAfterInitializationAndOutsideBusyPhases() {
        assertThat(
            clinicianReportConfigurationControlsEnabled(ClinicianReportUiState())
        ).isFalse()
        assertThat(
            clinicianReportConfigurationControlsEnabled(
                ClinicianReportUiState(isConfigurationReady = true, isLoading = true)
            )
        ).isFalse()
        assertThat(
            clinicianReportConfigurationControlsEnabled(
                ClinicianReportUiState(isConfigurationReady = true, isRendering = true)
            )
        ).isFalse()
        assertThat(
            clinicianReportConfigurationControlsEnabled(
                ClinicianReportUiState(isConfigurationReady = true)
            )
        ).isTrue()
    }

    @Test fun busyActionsSelectLocalizedPreparingAndGeneratingResourcesOnlyWhileBusy() {
        assertThat(
            clinicianReportBusyDescription(ClinicianReportBusyAction.PREVIEW, isBusy = true)
        ).isEqualTo(R.string.clinician_report_preparing)
        assertThat(
            clinicianReportBusyDescription(ClinicianReportBusyAction.GENERATE, isBusy = true)
        ).isEqualTo(R.string.clinician_report_generating)
        assertThat(
            clinicianReportBusyDescription(ClinicianReportBusyAction.PREVIEW, isBusy = false)
        ).isNull()
        assertThat(
            clinicianReportBusyDescription(ClinicianReportBusyAction.GENERATE, isBusy = false)
        ).isNull()
    }
}
