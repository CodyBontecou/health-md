package com.healthmd.presentation.clinicianreport

import android.content.Intent
import android.net.Uri
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.clinicianreport.ClinicianReportDataSource
import com.healthmd.data.clinicianreport.ClinicianReportFileStore
import com.healthmd.domain.clinicianreport.*
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.io.File
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale
import javax.inject.Inject

data class ClinicianReportUiState(
    val configuration: ReportConfiguration = ReportConfiguration(),
    val selectedPreset: ReportDateRangePreset = ReportDateRangePreset.DAYS_30,
    val report: ClinicianReportData? = null,
    val pdfFile: File? = null,
    val isLoading: Boolean = false,
    val isRendering: Boolean = false,
    val errorMessage: String? = null,
    val savedMessage: String? = null,
) {
    val canPreview: Boolean get() = configuration.selectedMetrics.isNotEmpty() && !isLoading && !isRendering
}

@HiltViewModel
class ClinicianReportViewModel @Inject constructor(
    private val dataSource: ClinicianReportDataSource,
    private val fileStore: ClinicianReportFileStore,
    private val settingsRepository: SettingsRepository,
    private val vocabularyFactory: ClinicianReportVocabularyFactory,
) : ViewModel() {
    private val _uiState = MutableStateFlow(ClinicianReportUiState())
    val uiState: StateFlow<ClinicianReportUiState> = _uiState.asStateFlow()
    private var activeJob: Job? = null
    private var externallySharedPdf: File? = null
    @Volatile private var requestGeneration = 0L

    init {
        viewModelScope.launch {
            val unit = settingsRepository.getExportSettings().formatCustomization.unitPreference
            updateConfiguration { it.copy(unitPreference = unit) }
        }
    }

    fun selectPreset(preset: ReportDateRangePreset, today: LocalDate = LocalDate.now()) {
        if (preset == ReportDateRangePreset.CUSTOM) {
            invalidateActiveRequest()
            clearPublishedPdf()
            _uiState.update { it.copy(selectedPreset = preset, report = null, pdfFile = null, isLoading = false, isRendering = false) }
        } else {
            updateConfiguration { it.copy(dateRange = ReportDateRange.preset(preset, today)) }
            _uiState.update { it.copy(selectedPreset = preset) }
        }
    }

    fun setCustomRange(start: LocalDate, end: LocalDate, today: LocalDate = LocalDate.now()) {
        updateConfiguration { it.copy(dateRange = ReportDateRange.normalized(start, end, today)) }
        _uiState.update { it.copy(selectedPreset = ReportDateRangePreset.CUSTOM) }
    }

    fun toggleMetric(metric: ReportMetric) = updateConfiguration { config ->
        config.copy(selectedMetrics = if (metric in config.selectedMetrics) config.selectedMetrics - metric else config.selectedMetrics + metric)
    }

    fun setDetailLevel(level: ReportDetailLevel) = updateConfiguration { it.copy(detailLevel = level) }
    fun setDisplayName(name: String) = updateConfiguration { it.copy(displayName = name) }

    fun preview() {
        val state = _uiState.value
        if (!state.canPreview) return
        val configuration = state.configuration
        val zoneId = ZoneId.systemDefault()
        val vocabulary = vocabularyFactory.current()
        val request = beginRequest()
        clearPublishedPdf()
        _uiState.update { it.copy(isLoading = true, isRendering = false, errorMessage = null, savedMessage = null, report = null, pdfFile = null) }
        activeJob = viewModelScope.launch {
            try {
                val input = dataSource.load(configuration, zoneId)
                val report = withContext(Dispatchers.Default) { ClinicianReportGenerator(vocabulary).generate(input) }
                // Publish the normalized effective range as the configuration source of truth so
                // the later PDF filename uses exactly the range represented by the report.
                publish(request) {
                    it.copy(isLoading = false, configuration = input.configuration, report = report)
                }
            } catch (cancelled: CancellationException) {
                publish(request) { it.copy(isLoading = false) }
                throw cancelled
            } catch (_: Exception) {
                publish(request) { it.copy(isLoading = false, errorMessage = vocabulary.text(ClinicianReportText.ERROR_PREPARE_ANDROID)) }
            }
        }
    }

    fun generatePdf() {
        val state = _uiState.value
        val report = state.report ?: return
        val range = state.configuration.dateRange
        val request = beginRequest()
        clearPublishedPdf()
        // A later generation is the cleanup boundary for an earlier shared file.
        // Do not delete it merely because the chooser or this screen was dismissed.
        externallySharedPdf = null
        _uiState.update { it.copy(isRendering = true, isLoading = false, errorMessage = null, savedMessage = null, pdfFile = null) }
        activeJob = viewModelScope.launch {
            try {
                val file = withContext(Dispatchers.IO) {
                    val generated = fileStore.generate(report, range.startDate, range.endDate) { request == requestGeneration }
                    if (request != requestGeneration) {
                        fileStore.delete(generated)
                        throw CancellationException("Report request was superseded")
                    }
                    generated
                }
                publish(request) { it.copy(isRendering = false, pdfFile = file) }
            } catch (cancelled: CancellationException) {
                publish(request) { it.copy(isRendering = false) }
                throw cancelled
            } catch (_: Exception) {
                publish(request) { it.copy(isRendering = false, errorMessage = vocabularyFor(report).text(ClinicianReportText.ERROR_PDF)) }
            }
        }
    }

    fun savePdf(uri: Uri) {
        val file = _uiState.value.pdfFile ?: return
        viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) { fileStore.copyTo(file, uri) }
                _uiState.update { it.copy(savedMessage = vocabularyForReport().text(ClinicianReportText.SAVED), errorMessage = null) }
            } catch (_: Exception) {
                _uiState.update { it.copy(errorMessage = vocabularyForReport().text(ClinicianReportText.ERROR_SAVE)) }
            }
        }
    }

    fun shareIntent(intentFactory: (File) -> Intent = fileStore::shareIntent) =
        _uiState.value.pdfFile?.let { file ->
            // The target app may not open the granted URI until after this screen changes
            // or is destroyed. Retain the cache file until a later generation cleans it.
            externallySharedPdf = file
            intentFactory(file)
        }
    fun clearMessage() = _uiState.update { it.copy(errorMessage = null, savedMessage = null) }
    fun cancel() {
        invalidateActiveRequest()
        _uiState.update { it.copy(isLoading = false, isRendering = false) }
    }

    private fun updateConfiguration(transform: (ReportConfiguration) -> ReportConfiguration) {
        invalidateActiveRequest()
        clearPublishedPdf()
        _uiState.update {
            it.copy(
                configuration = transform(it.configuration),
                report = null,
                pdfFile = null,
                isLoading = false,
                isRendering = false,
                errorMessage = null,
                savedMessage = null,
            )
        }
    }

    private fun beginRequest(): Long {
        invalidateActiveRequest()
        return requestGeneration
    }

    private fun invalidateActiveRequest() {
        requestGeneration += 1
        activeJob?.cancel()
        activeJob = null
    }

    private fun publish(request: Long, transform: (ClinicianReportUiState) -> ClinicianReportUiState) {
        if (request == requestGeneration) _uiState.update(transform)
    }

    private fun vocabularyFor(report: ClinicianReportData): ClinicianReportVocabulary =
        vocabularyFactory.forLocale(Locale.forLanguageTag(report.languageTag))

    private fun vocabularyForReport(): ClinicianReportVocabulary =
        _uiState.value.report?.let(::vocabularyFor) ?: vocabularyFactory.current()

    private fun clearPublishedPdf() {
        _uiState.value.pdfFile
            ?.takeUnless { it == externallySharedPdf }
            ?.let(fileStore::delete)
    }

    override fun onCleared() {
        invalidateActiveRequest()
        clearPublishedPdf()
        super.onCleared()
    }
}
