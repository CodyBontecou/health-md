package com.healthmd.domain.model

import com.google.common.truth.Truth.assertThat
import com.google.common.truth.Truth.assertWithMessage
import com.healthmd.presentation.export.ExportProfileEditorDraft
import com.healthmd.rawexport.ExportMode
import com.healthmd.rawexport.RawExportFormat
import com.healthmd.rawexport.RawSnapshotScope
import com.healthmd.testing.syntheticExportEnginePin
import java.lang.reflect.Modifier
import java.time.LocalDate
import java.time.ZoneId
import org.junit.Test

/**
 * A-EXP-34: Android 3.5 "Reset to Defaults" for an automation's export configuration, with the
 * Apple 4.0 per-automation semantics (`ExportSettingsSnapshot.resettingExportConfiguration()`).
 */
class ExportConfigurationResetTest {
    /** Where and when the automation runs, plus operation-only authority. */
    private val keptFields = setOf(
        "exportTarget",
        "scheduledExportTarget",
        "apiEndpointUrl",
        "agentDataGatewayUrl",
        "subfolder",
        "scheduleEnabled",
        "scheduleCadenceValue",
        "scheduleCadenceUnit",
        "scheduleHour",
        "scheduleMinute",
        "scheduleLookbackDays",
        "scheduleDateWindow",
        "pendingScheduledRetryDates",
        "pendingScheduledExportRequests",
        "executionEnginePin",
        "executionEngineAuthorityIsFrozen",
        "executionSleepCaptureContext",
        "executionSleepCaptureAuthorityIsFrozen",
        "executionProviderCaptureAuthority",
        "executionProviderCaptureAuthorityIsFrozen",
    )

    /** What the automation exports: returns to [ExportSettings.newInstallDefaults]. */
    private val resetFields = setOf(
        "exportMode",
        "rawSnapshot",
        "dataTypes",
        "exportFormat",
        "exportFormats",
        "includeMetadata",
        "groupByCategory",
        "filenameFormat",
        "folderStructure",
        "writeMode",
        "formatCustomization",
        "metricSelection",
        "dailyNoteInjection",
        "individualTracking",
        "includeGranularData",
        "detailOverrides",
        "folderOrganization",
    )

    /** Every field differs from its new-install default. */
    private val customized = ExportSettings(
        exportMode = ExportMode.RAW_SNAPSHOT,
        rawSnapshot = RawSnapshotSettings(
            format = RawExportFormat.JSON,
            scope = RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA,
            includeExerciseRoutes = false,
        ),
        dataTypes = DataTypeSelection(sleep = false, nutrition = false),
        exportFormat = ExportFormat.CSV,
        exportFormats = setOf(ExportFormat.JSON, ExportFormat.CSV),
        includeMetadata = false,
        groupByCategory = false,
        filenameFormat = "{year}-{month}-{day} health",
        folderStructure = "{weekYear}/Week {week}",
        writeMode = WriteMode.UPDATE,
        formatCustomization = FormatCustomization(
            dateFormat = DateFormatPreference.US_SHORT,
            unitPreference = UnitPreference.IMPERIAL,
        ),
        metricSelection = MetricSelectionState(enabledMetrics = setOf("steps")),
        dailyNoteInjection = DailyNoteInjectionSettings(enabled = true, folderPath = "Journal"),
        individualTracking = IndividualTrackingSettings(globalEnabled = true, enabledMetrics = setOf("weight")),
        includeGranularData = true,
        detailOverrides = mapOf(ExportDetailGroup.SLEEP.wireId to ExportDetailChoice.DETAILED.wireId),
        exportTarget = ExportTarget.API_ENDPOINT,
        scheduledExportTarget = ExportTarget.AGENT_DATA_GATEWAY,
        apiEndpointUrl = "https://example.invalid/health",
        agentDataGatewayUrl = "https://gateway.example.invalid",
        subfolder = "vault/health-data",
        folderOrganization = FolderOrganization.BY_YEAR_MONTH,
        scheduleEnabled = true,
        scheduleCadenceValue = 3,
        scheduleCadenceUnit = ScheduleCadenceUnit.HOURS,
        scheduleHour = 21,
        scheduleMinute = 45,
        scheduleLookbackDays = 7,
        scheduleDateWindow = ScheduleDateWindow.TODAY,
        pendingScheduledRetryDates = listOf("2026-01-02"),
        pendingScheduledExportRequests = listOf(
            PendingScheduledExportRequest(date = LocalDate.of(2026, 1, 2), exportTarget = ExportTarget.API_ENDPOINT),
        ),
        executionEnginePin = syntheticExportEnginePin(),
        executionEngineAuthorityIsFrozen = true,
        executionSleepCaptureContext = AndroidCaptureContext(ZoneId.of("Europe/Berlin"), SleepDayAttribution.NIGHT_BEGINS),
        executionSleepCaptureAuthorityIsFrozen = true,
        executionProviderCaptureAuthority = HealthProviderCaptureAuthority(
            selectedProviderId = "health_connect",
            providerIds = listOf("health_connect"),
            connectionIds = emptyMap(),
        ),
        executionProviderCaptureAuthorityIsFrozen = true,
    )

    private val defaults = ExportSettings.newInstallDefaults()

    private val fields = ExportSettings::class.java.declaredFields
        .filterNot { Modifier.isStatic(it.modifiers) }
        .onEach { it.isAccessible = true }

    @Test
    fun everySettingIsClassifiedAsResetOrKept() {
        // A new ExportSettings field must decide whether Reset Export Configuration clears it.
        assertThat(keptFields intersect resetFields).isEmpty()
        assertThat(fields.map { it.name }).containsExactlyElementsIn(keptFields + resetFields)
    }

    @Test
    fun theFixtureChangesEveryField() {
        fields.forEach { field ->
            assertWithMessage("fixture value of ${field.name}")
                .that(field.get(customized))
                .isNotEqualTo(field.get(defaults))
        }
    }

    @Test
    fun exportChoicesReturnToTheNewInstallDefaults() {
        val reset = customized.resettingExportConfiguration()
        fields.filter { it.name in resetFields }.forEach { field ->
            assertWithMessage("reset ${field.name}").that(field.get(reset)).isEqualTo(field.get(defaults))
        }
        assertThat(reset.exportMode).isEqualTo(ExportMode.COMPATIBILITY)
        assertThat(reset.exportFormats).containsExactly(ExportFormat.MARKDOWN)
        assertThat(reset.includeMetadata).isTrue()
        assertThat(reset.groupByCategory).isTrue()
        assertThat(reset.filenameFormat).isEqualTo(ExportSettings.DEFAULT_FILENAME_FORMAT)
        assertThat(reset.folderStructure).isEmpty()
        assertThat(reset.folderOrganization).isEqualTo(FolderOrganization.FLAT)
        assertThat(reset.writeMode).isEqualTo(WriteMode.OVERWRITE)
        assertThat(reset.formatCustomization).isEqualTo(FormatCustomization.analyticalDefault())
        assertThat(reset.metricSelection).isEqualTo(MetricSelectionState())
        assertThat(reset.dailyNoteInjection).isEqualTo(DailyNoteInjectionSettings())
        assertThat(reset.individualTracking).isEqualTo(IndividualTrackingSettings())
        assertThat(reset.includeGranularData).isFalse()
        assertThat(reset.detailOverrides).isEmpty()
    }

    @Test
    fun destinationSubfolderScheduleAndAuthorityStay() {
        val reset = customized.resettingExportConfiguration()
        fields.filter { it.name in keptFields }.forEach { field ->
            assertWithMessage("kept ${field.name}").that(field.get(reset)).isEqualTo(field.get(customized))
        }
    }

    @Test
    fun resettingDefaultsChangesNothing() {
        assertThat(defaults.resettingExportConfiguration()).isEqualTo(defaults)
    }

    @Test
    fun anAutomationKeepsItsNameAndDestinationBindings() {
        val draft = ExportProfileEditorDraft(
            name = "Evening vault",
            target = ExportTarget.DEVICE_FOLDER,
            folderUri = "content://tree/primary%3AVault",
            folderDisplayName = "Vault",
            destinationId = "drive-destination",
            apiEndpointUrl = "https://example.invalid/health",
            agentDataGatewayUrl = "https://gateway.example.invalid",
            settings = customized,
        )
        val reset = draft.resettingExportConfiguration()
        assertThat(reset).isEqualTo(draft.copy(settings = customized.resettingExportConfiguration()))
        assertThat(reset.name).isEqualTo("Evening vault")
        assertThat(reset.folderUri).isEqualTo("content://tree/primary%3AVault")
        assertThat(reset.destinationId).isEqualTo("drive-destination")
    }
}
