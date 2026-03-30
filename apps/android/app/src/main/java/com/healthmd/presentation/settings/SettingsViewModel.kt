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

    fun updateFormat(format: ExportFormat) = update { it.copy(exportFormat = format) }
    fun updateWriteMode(mode: WriteMode) = update { it.copy(writeMode = mode) }
    fun updateFilenameFormat(format: String) = update { it.copy(filenameFormat = format) }
    fun updateFolderStructure(structure: String) = update { it.copy(folderStructure = structure) }
    fun updateIncludeMetadata(include: Boolean) = update { it.copy(includeMetadata = include) }
    fun updateGroupByCategory(group: Boolean) = update { it.copy(groupByCategory = group) }

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
