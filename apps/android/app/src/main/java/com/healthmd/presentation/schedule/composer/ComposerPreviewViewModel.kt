package com.healthmd.presentation.schedule.composer

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.domain.model.ExportPreviewFile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.rawexport.ExportMode
import dagger.hilt.android.lifecycle.HiltViewModel
import java.time.LocalDate
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.launch

/** The composer's live file preview. */
sealed interface ComposerPreviewState {
    data object Loading : ComposerPreviewState
    /** Raw snapshots are one range artifact, so there is no day file to show. */
    data object RangeArtifactOnly : ComposerPreviewState
    data object Empty : ComposerPreviewState
    data object Failed : ComposerPreviewState
    data class File(val file: ExportPreviewFile) : ComposerPreviewState
}

/**
 * Renders the first file the draft would write for the most recent complete day, with the same
 * dry run Export now previews. It writes nothing; edits re-render after a short pause.
 */
@HiltViewModel
class ComposerPreviewViewModel @Inject constructor(
    private val healthRepository: HealthRepository,
    private val exportRepository: ExportRepository,
) : ViewModel() {
    private val requests = MutableStateFlow<ExportSettings?>(null)
    private val _state = MutableStateFlow<ComposerPreviewState>(ComposerPreviewState.Loading)
    val state: StateFlow<ComposerPreviewState> = _state.asStateFlow()

    init {
        viewModelScope.launch {
            requests.filterNotNull().distinctUntilChanged().collectLatest { settings ->
                _state.value = ComposerPreviewState.Loading
                delay(DEBOUNCE_MILLIS)
                _state.value = render(settings)
            }
        }
    }

    fun preview(settings: ExportSettings) {
        requests.value = settings
    }

    private suspend fun render(settings: ExportSettings): ComposerPreviewState {
        if (settings.exportMode == ExportMode.RAW_SNAPSHOT) return ComposerPreviewState.RangeArtifactOnly
        val date = ComposerSentence.previewDate(LocalDate.now())
        return try {
            val preview = ExportOrchestrator(healthRepository, exportRepository)
                .previewDates(listOf(date), settings, maxPreviewDays = 1)
            val day = preview.days.firstOrNull { it.date == date }
            day?.files?.firstOrNull()?.let(ComposerPreviewState::File)
                ?: if (day?.failureReason != null) ComposerPreviewState.Failed else ComposerPreviewState.Empty
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            ComposerPreviewState.Failed
        }
    }

    private companion object {
        const val DEBOUNCE_MILLIS = 400L
    }
}
