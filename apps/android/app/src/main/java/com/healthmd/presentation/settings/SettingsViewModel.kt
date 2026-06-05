package com.healthmd.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.domain.model.*
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.*
import kotlinx.coroutines.launch
import javax.inject.Inject

@HiltViewModel
class SettingsViewModel @Inject constructor(
    private val settingsRepository: SettingsRepository,
) : ViewModel() {

    val settings: StateFlow<ExportSettings> = settingsRepository.exportSettings
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), ExportSettings())

    val isPurchased: StateFlow<Boolean> = settingsRepository.isPurchased
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5000), false)

    fun updateFormat(format: ExportFormat) = update { it.copy(exportFormat = format, exportFormats = setOf(format)) }
    fun toggleExportFormat(format: ExportFormat) = update { settings ->
        val newFormats = if (format in settings.selectedExportFormats) {
            settings.selectedExportFormats - format
        } else {
            settings.selectedExportFormats + format
        }
        settings.copy(
            exportFormats = newFormats,
            exportFormat = newFormats.firstOrNull() ?: settings.exportFormat,
        )
    }
    fun updateWriteMode(mode: WriteMode) = update { it.copy(writeMode = mode) }
    fun updateFilenameFormat(format: String) = update { it.copy(filenameFormat = format) }
    fun updateFolderStructure(structure: String) = update { it.copy(folderStructure = structure) }
    fun updateIncludeMetadata(include: Boolean) = update { it.copy(includeMetadata = include) }
    fun updateGroupByCategory(group: Boolean) = update { it.copy(groupByCategory = group) }
    fun updateSubfolder(subfolder: String) = update { it.copy(subfolder = subfolder) }
    fun updateFolderOrganization(org: FolderOrganization) = update { it.copy(folderOrganization = org) }
    fun updateIncludeGranularData(include: Boolean) = update { it.copy(includeGranularData = include) }

    fun updateMetricSelection(selection: MetricSelectionState) = update { it.copy(metricSelection = selection) }
    fun updateDailyNoteInjection(settings: DailyNoteInjectionSettings) = update { it.copy(dailyNoteInjection = settings) }
    fun updateIndividualTracking(settings: IndividualTrackingSettings) = update { it.copy(individualTracking = settings) }
    fun updateFormatCustomization(customization: FormatCustomization) = update { it.copy(formatCustomization = customization) }

    fun updateScheduleHour(hour: Int) = update { it.copy(scheduleHour = hour) }
    fun updateScheduleMinute(minute: Int) = update { it.copy(scheduleMinute = minute) }

    fun updateDateFormat(format: DateFormatPreference) = updateCustomization {
        it.copy(dateFormat = format)
    }

    fun updateTimeFormat(format: TimeFormatPreference) = updateCustomization {
        it.copy(timeFormat = format)
    }

    fun updateUnitPreference(pref: UnitPreference) = updateCustomization {
        it.copy(unitPreference = pref)
    }

    fun updateBulletStyle(style: BulletStyle) = updateCustomization {
        it.copy(markdownTemplate = it.markdownTemplate.copy(bulletStyle = style))
    }

    fun updateUseEmoji(use: Boolean) = updateCustomization {
        it.copy(markdownTemplate = it.markdownTemplate.copy(useEmoji = use))
    }

    fun updateHeaderLevel(level: Int) = updateCustomization {
        it.copy(markdownTemplate = it.markdownTemplate.copy(sectionHeaderLevel = level))
    }

    fun updateFrontmatterKeyStyle(style: FrontmatterKeyStyle) = updateCustomization {
        it.copy(frontmatterConfig = it.frontmatterConfig.withKeyStyle(style))
    }

    fun resetSettings() {
        viewModelScope.launch {
            settingsRepository.updateExportSettings(ExportSettings())
        }
    }

    private fun update(transform: (ExportSettings) -> ExportSettings) {
        viewModelScope.launch {
            val current = settingsRepository.getExportSettings()
            settingsRepository.updateExportSettings(transform(current))
        }
    }

    private fun updateCustomization(transform: (FormatCustomization) -> FormatCustomization) {
        update { it.copy(formatCustomization = transform(it.formatCustomization)) }
    }
}
