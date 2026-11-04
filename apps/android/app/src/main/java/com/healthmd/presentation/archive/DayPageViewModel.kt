package com.healthmd.presentation.archive

import androidx.lifecycle.SavedStateHandle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.domain.model.ExportPreviewFile
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.rawexport.ExportMode
import dagger.hilt.android.lifecycle.HiltViewModel
import java.time.LocalDate
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** What the day page can show for one date. */
sealed interface DayPageContent {
    data object Loading : DayPageContent
    /** Raw snapshots are one range artifact, so no single day file exists. */
    data object RangeArtifactOnly : DayPageContent
    /** The current settings would write nothing for this date. */
    data object Empty : DayPageContent
    data object Failed : DayPageContent
    data class Files(val files: List<ExportPreviewFile>) : DayPageContent
}

data class DayPageUiState(
    val date: LocalDate,
    val content: DayPageContent = DayPageContent.Loading,
    val selectedIndex: Int = 0,
) {
    val selectedFile: ExportPreviewFile?
        get() = (content as? DayPageContent.Files)?.files?.getOrNull(selectedIndex)
}

/**
 * The day page renders the file itself: the same dry run Export now previews, for one date,
 * with the current export settings. It writes nothing and records no history.
 */
@HiltViewModel
class DayPageViewModel @Inject constructor(
    savedStateHandle: SavedStateHandle,
    private val healthRepository: HealthRepository,
    private val exportRepository: ExportRepository,
    private val settingsRepository: SettingsRepository,
) : ViewModel() {
    private val date: LocalDate = savedStateHandle.get<String>(DATE_ARGUMENT)
        ?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
        ?: LocalDate.now()

    private val _uiState = MutableStateFlow(DayPageUiState(date = date))
    val uiState: StateFlow<DayPageUiState> = _uiState.asStateFlow()

    init {
        load()
    }

    fun load() {
        _uiState.update { it.copy(content = DayPageContent.Loading) }
        viewModelScope.launch {
            val content = try {
                val settings = settingsRepository.getExportSettings()
                if (settings.exportMode == ExportMode.RAW_SNAPSHOT) {
                    DayPageContent.RangeArtifactOnly
                } else {
                    val preview = ExportOrchestrator(healthRepository, exportRepository)
                        .previewDates(listOf(date), settings, maxPreviewDays = 1)
                    dayPageContent(preview.days.firstOrNull { it.date == date }?.files.orEmpty(), preview.days.any { it.failureReason != null })
                }
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                DayPageContent.Failed
            }
            _uiState.update { it.copy(content = content, selectedIndex = 0) }
        }
    }

    fun selectFile(index: Int) {
        _uiState.update { it.copy(selectedIndex = index) }
    }

    companion object {
        const val DATE_ARGUMENT = "date"

        internal fun dayPageContent(files: List<ExportPreviewFile>, failed: Boolean): DayPageContent = when {
            files.isNotEmpty() -> DayPageContent.Files(files)
            failed -> DayPageContent.Failed
            else -> DayPageContent.Empty
        }
    }
}
