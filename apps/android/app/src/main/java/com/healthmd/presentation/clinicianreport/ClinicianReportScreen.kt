package com.healthmd.presentation.clinicianreport

import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.toggleable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Save
import androidx.compose.material.icons.outlined.Share
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.annotation.StringRes
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.domain.clinicianreport.*
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.common.SectionLabel
import com.healthmd.presentation.theme.*
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneOffset
import java.time.format.DateTimeFormatter
import java.time.format.FormatStyle

internal enum class ClinicianReportBusyAction(@StringRes val descriptionResource: Int) {
    PREVIEW(R.string.clinician_report_preparing),
    GENERATE(R.string.clinician_report_generating),
}

@StringRes
internal fun clinicianReportBusyDescription(
    action: ClinicianReportBusyAction,
    isBusy: Boolean,
): Int? = action.descriptionResource.takeIf { isBusy }

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun ClinicianReportScreen(
    onBack: () -> Unit,
    viewModel: ClinicianReportViewModel = hiltViewModel(),
) {
    val state by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val protection = LocalConfigurationProtection.current
    val attemptConfigurationChange: (() -> Unit) -> Unit = { action ->
        if (protection.enabled) protection.onBlockedChange() else action()
    }
    var pickingStart by remember { mutableStateOf(false) }
    var pickingEnd by remember { mutableStateOf(false) }
    val saveLauncher = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("application/pdf")) { uri ->
        uri?.let(viewModel::savePdf)
    }

    if (pickingStart || pickingEnd) {
        val initial = if (pickingStart) state.configuration.dateRange.startDate else state.configuration.dateRange.endDate
        val pickerState = rememberDatePickerState(initialSelectedDateMillis = initial.atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(
            onDismissRequest = { pickingStart = false; pickingEnd = false },
            confirmButton = {
                TextButton(onClick = {
                    pickerState.selectedDateMillis?.let { millis ->
                        val selected = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
                        val range = state.configuration.dateRange
                        attemptConfigurationChange {
                            if (pickingStart) viewModel.setCustomRange(selected, range.endDate)
                            else viewModel.setCustomRange(range.startDate, selected)
                        }
                    }
                    pickingStart = false; pickingEnd = false
                }) { Text(stringResource(R.string.clinician_report_select_date)) }
            },
            dismissButton = { TextButton(onClick = { pickingStart = false; pickingEnd = false }) { Text(stringResource(R.string.cancel)) } },
        ) { DatePicker(state = pickerState) }
    }

    Scaffold(
        containerColor = AppColors.bgPrimary,
        topBar = {
            TopAppBar(
                title = { Text(stringResource(R.string.clinician_report_title), style = GeistType.heading20) },
                navigationIcon = {
                    IconButton(onClick = { viewModel.cancel(); onBack() }) {
                        Icon(Icons.AutoMirrored.Outlined.ArrowBack, contentDescription = stringResource(R.string.back))
                    }
                },
                colors = TopAppBarDefaults.topAppBarColors(containerColor = AppColors.bgPrimary, titleContentColor = AppColors.textPrimary),
            )
        },
    ) { padding ->
        Column(
            modifier = Modifier.fillMaxSize().padding(padding).verticalScroll(rememberScrollState()).padding(Spacing.md),
            verticalArrangement = Arrangement.spacedBy(Spacing.md),
        ) {
            Text(stringResource(R.string.clinician_report_intro), style = GeistType.copy14, color = AppColors.textSecondary)

            SectionLabel(stringResource(R.string.clinician_report_period))
            GeistCard {
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs), modifier = Modifier.fillMaxWidth()) {
                    listOf(
                        ReportDateRangePreset.DAYS_7 to stringResource(R.string.clinician_report_7_days),
                        ReportDateRangePreset.DAYS_30 to stringResource(R.string.clinician_report_30_days),
                        ReportDateRangePreset.DAYS_90 to stringResource(R.string.clinician_report_90_days),
                        ReportDateRangePreset.CUSTOM to stringResource(R.string.clinician_report_custom),
                    ).forEach { (preset, label) ->
                        FilterChip(
                            selected = state.selectedPreset == preset,
                            onClick = {
                                attemptConfigurationChange { viewModel.selectPreset(preset) }
                            },
                            label = { Text(label) },
                            modifier = Modifier.weight(1f).testTag("clinician_report_preset_${preset.name.lowercase()}"),
                            colors = FilterChipDefaults.filterChipColors(selectedContainerColor = AppColors.accentSubtle, selectedLabelColor = AppColors.accent),
                        )
                    }
                }
                if (state.selectedPreset == ReportDateRangePreset.CUSTOM) {
                    Spacer(Modifier.height(Spacing.sm))
                    DateRangeButton(stringResource(R.string.clinician_report_start_date), state.configuration.dateRange.startDate) {
                        attemptConfigurationChange { pickingStart = true }
                    }
                    Spacer(Modifier.height(Spacing.xs))
                    DateRangeButton(stringResource(R.string.clinician_report_end_date), state.configuration.dateRange.endDate) {
                        attemptConfigurationChange { pickingEnd = true }
                    }
                }
            }

            SectionLabel(stringResource(R.string.clinician_report_metrics))
            GeistCard {
                ReportMetric.entries.forEach { metric ->
                    Row(
                        modifier = Modifier.fillMaxWidth().toggleable(
                            value = metric in state.configuration.selectedMetrics,
                            role = Role.Switch,
                            onValueChange = {
                                attemptConfigurationChange { viewModel.toggleMetric(metric) }
                            },
                        ).padding(vertical = Spacing.xs).testTag("clinician_report_metric_${metric.name.lowercase()}"),
                        verticalAlignment = Alignment.CenterVertically,
                    ) {
                        Text(stringResource(metric.labelResource()), style = GeistType.copy14, color = AppColors.textPrimary, modifier = Modifier.weight(1f))
                        Switch(
                            checked = metric in state.configuration.selectedMetrics,
                            onCheckedChange = null,
                            colors = SwitchDefaults.colors(checkedTrackColor = AppColors.accent, checkedThumbColor = AppColors.onAccent),
                        )
                    }
                }
            }

            SectionLabel(stringResource(R.string.clinician_report_detail))
            GeistCard {
                DetailRow(stringResource(R.string.clinician_report_summary_only), state.configuration.detailLevel == ReportDetailLevel.SUMMARY) {
                    attemptConfigurationChange {
                        viewModel.setDetailLevel(ReportDetailLevel.SUMMARY)
                    }
                }
                DetailRow(stringResource(R.string.clinician_report_summary_readings), state.configuration.detailLevel == ReportDetailLevel.SUMMARY_AND_READINGS) {
                    attemptConfigurationChange {
                        viewModel.setDetailLevel(ReportDetailLevel.SUMMARY_AND_READINGS)
                    }
                }
            }

            OutlinedTextField(
                value = state.configuration.displayName,
                onValueChange = { value ->
                    attemptConfigurationChange { viewModel.setDisplayName(value) }
                },
                modifier = Modifier.fillMaxWidth(),
                label = { Text(stringResource(R.string.clinician_report_display_name)) },
                supportingText = { Text(stringResource(R.string.clinician_report_display_name_hint)) },
                singleLine = true,
                colors = OutlinedTextFieldDefaults.colors(focusedBorderColor = AppColors.accent, unfocusedBorderColor = AppColors.borderDefault),
                shape = RoundedCornerShape(Radii.card),
            )

            state.errorMessage?.let { StatusCard(it, AppColors.errorSubtle, AppColors.error) }
            state.savedMessage?.let { StatusCard(it, AppColors.successSubtle, AppColors.success) }

            val previewBusyDescription = clinicianReportBusyDescription(
                ClinicianReportBusyAction.PREVIEW,
                state.isLoading,
            )?.let { stringResource(it) }
            PrimaryButton(
                text = stringResource(R.string.clinician_report_preview),
                onClick = viewModel::preview,
                enabled = state.canPreview,
                isLoading = state.isLoading,
                icon = Icons.Outlined.Description,
                modifier = Modifier
                    .testTag("clinician_report_preview")
                    .then(previewBusyDescription?.let(::busyStateSemantics) ?: Modifier),
            )
            if (state.configuration.selectedMetrics.isEmpty()) {
                Text(stringResource(R.string.clinician_report_select_metric), style = GeistType.copy13, color = AppColors.error)
            }

            state.report?.let { report ->
                ReportPreview(report)
                val generateBusyDescription = clinicianReportBusyDescription(
                    ClinicianReportBusyAction.GENERATE,
                    state.isRendering,
                )?.let { stringResource(it) }
                PrimaryButton(
                    text = stringResource(R.string.clinician_report_generate_pdf),
                    onClick = viewModel::generatePdf,
                    isLoading = state.isRendering,
                    icon = Icons.Outlined.Description,
                    modifier = Modifier
                        .testTag("clinician_report_generate")
                        .then(generateBusyDescription?.let(::busyStateSemantics) ?: Modifier),
                )
            }

            state.pdfFile?.let { file ->
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), modifier = Modifier.fillMaxWidth()) {
                    SecondaryButton(
                        text = stringResource(R.string.clinician_report_share_pdf),
                        onClick = {
                            viewModel.shareIntent()?.let { context.startActivity(Intent.createChooser(it, context.getString(R.string.clinician_report_share_pdf))) }
                        },
                        icon = Icons.Outlined.Share,
                        modifier = Modifier.weight(1f).testTag("clinician_report_share"),
                    )
                    SecondaryButton(
                        text = stringResource(R.string.clinician_report_save_pdf),
                        onClick = { saveLauncher.launch(file.name) },
                        icon = Icons.Outlined.Save,
                        modifier = Modifier.weight(1f).testTag("clinician_report_save"),
                    )
                }
            }
            Spacer(Modifier.height(Spacing.xl))
        }
    }
}

private fun busyStateSemantics(description: String): Modifier = Modifier.semantics {
    contentDescription = description
    stateDescription = description
    liveRegion = LiveRegionMode.Polite
}

@Composable
private fun DateRangeButton(label: String, date: LocalDate, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = Spacing.sm),
        horizontalArrangement = Arrangement.SpaceBetween,
    ) {
        Text(label, style = GeistType.copy14, color = AppColors.textSecondary)
        Text(date.format(DateTimeFormatter.ofLocalizedDate(FormatStyle.MEDIUM)), style = GeistType.copy14Mono, color = AppColors.textPrimary)
    }
}

@Composable
private fun DetailRow(label: String, selected: Boolean, onClick: () -> Unit) {
    Row(
        modifier = Modifier.fillMaxWidth().selectable(selected = selected, role = Role.RadioButton, onClick = onClick).padding(vertical = Spacing.xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        RadioButton(selected = selected, onClick = null, colors = RadioButtonDefaults.colors(selectedColor = AppColors.accent))
        Text(label, style = GeistType.copy14, color = AppColors.textPrimary)
    }
}

@Composable
private fun StatusCard(text: String, background: androidx.compose.ui.graphics.Color, foreground: androidx.compose.ui.graphics.Color) {
    Text(text, style = GeistType.copy13, color = foreground, modifier = Modifier.fillMaxWidth().background(background, RoundedCornerShape(Radii.card)).padding(Spacing.sm))
}

@Composable
private fun ReportPreview(report: ClinicianReportData) {
    SectionLabel(stringResource(R.string.clinician_report_preview_heading))
    GeistCard(modifier = Modifier.testTag("clinician_report_preview_content")) {
        Text(report.title, style = GeistType.heading24, color = AppColors.textPrimary, modifier = Modifier.semantics { heading() })
        Text(report.dateRangeLabel, style = GeistType.copy14Mono, color = AppColors.textSecondary)
        report.displayName?.let { Text(it, style = GeistType.copy14, color = AppColors.textSecondary) }
        report.warnings.forEach { Text(it, style = GeistType.copy13, color = AppColors.warning) }
        report.sections.forEach { section ->
            Spacer(Modifier.height(Spacing.md))
            Text(section.localizedTitle, style = GeistType.heading16, color = AppColors.accent, modifier = Modifier.semantics { heading() })
            section.noDataMessage?.let { Text(it, style = GeistType.copy13, color = AppColors.textSecondary) }
            section.facts.forEach { fact ->
                Row(Modifier.fillMaxWidth().padding(top = Spacing.xs)) {
                    Text(fact.label, style = GeistType.copy13, fontWeight = FontWeight.Medium, color = AppColors.textPrimary, modifier = Modifier.weight(1f))
                    Text(fact.value, style = GeistType.copy13Mono, color = AppColors.textPrimary, modifier = Modifier.weight(1.4f))
                }
            }
            section.coverageDisclosure?.let { Text(it, style = GeistType.copy13, color = AppColors.textSecondary, modifier = Modifier.padding(top = Spacing.xs)) }
            section.sourcesDisclosure?.let { Text(it, style = GeistType.copy13, color = AppColors.textSecondary) }
            section.detailReadingsDescription?.let {
                Text(it, style = GeistType.copy13, color = AppColors.textSecondary, modifier = Modifier.padding(top = Spacing.xs))
            }
        }
        Spacer(Modifier.height(Spacing.md))
        Text(report.disclaimer, style = GeistType.copy13, color = AppColors.textSecondary)
    }
}

@StringRes
private fun ReportMetric.labelResource(): Int = when (this) {
    ReportMetric.BLOOD_PRESSURE -> R.string.clinician_report_metric_blood_pressure
    ReportMetric.RESTING_HEART_RATE -> R.string.clinician_report_metric_resting_heart_rate
    ReportMetric.HEART_RATE -> R.string.clinician_report_metric_heart_rate
    ReportMetric.WEIGHT -> R.string.clinician_report_metric_weight
    ReportMetric.BLOOD_GLUCOSE -> R.string.clinician_report_metric_blood_glucose
    ReportMetric.OXYGEN_SATURATION -> R.string.clinician_report_metric_oxygen_saturation
    ReportMetric.RESPIRATORY_RATE -> R.string.clinician_report_metric_respiratory_rate
    ReportMetric.BODY_TEMPERATURE -> R.string.clinician_report_metric_body_temperature
    ReportMetric.SLEEP_DURATION -> R.string.clinician_report_metric_sleep_duration
    ReportMetric.STEPS -> R.string.clinician_report_metric_steps
    ReportMetric.WORKOUTS -> R.string.clinician_report_metric_workouts
}
