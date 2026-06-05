package com.healthmd.automation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Bundle
import com.healthmd.R
import com.healthmd.data.export.ExportOrchestrator
import com.healthmd.domain.export.ExportAccountingPolicy
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSource
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import timber.log.Timber
import java.time.LocalDate
import javax.inject.Inject

/**
 * Explicit automation entrypoint for Tasker/adb/launcher shortcuts.
 *
 * Security model: this receiver is exported but intentionally has no manifest intent-filter.
 * Callers must target the component explicitly, e.g.:
 *
 * `adb shell am broadcast -n com.healthmd.android/com.healthmd.automation.AutomationReceiver \
 *   -a com.healthmd.android.action.EXPORT_YESTERDAY`
 *
 * That avoids arbitrary implicit broadcasts exporting health data.
 */
@AndroidEntryPoint
class AutomationReceiver : BroadcastReceiver() {

    @Inject lateinit var healthRepository: HealthRepository
    @Inject lateinit var exportRepository: ExportRepository
    @Inject lateinit var settingsRepository: SettingsRepository
    @Inject lateinit var exportHistoryRepository: ExportHistoryRepository

    override fun onReceive(context: Context, intent: Intent) {
        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                when (intent.action) {
                    ACTION_EXPORT_YESTERDAY -> runExport(context, listOf(LocalDate.now().minusDays(1)))
                    ACTION_EXPORT_LAST_DAYS -> {
                        val days = intent.getIntExtra(EXTRA_DAYS, 1).coerceIn(1, 365)
                        val end = LocalDate.now().minusDays(1)
                        val start = end.minusDays((days - 1).toLong())
                        runExport(context, ExportOrchestrator.dateRange(start, end))
                    }
                    ACTION_EXPORT_DATE -> {
                        val date = intent.getStringExtra(EXTRA_DATE)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                            ?: LocalDate.now().minusDays(1)
                        runExport(context, listOf(date))
                    }
                    ACTION_EXPORT_RANGE -> {
                        val start = intent.getStringExtra(EXTRA_START_DATE)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                        val end = intent.getStringExtra(EXTRA_END_DATE)?.let { runCatching { LocalDate.parse(it) }.getOrNull() }
                        if (start == null || end == null || end.isBefore(start)) {
                            publishResult(RESULT_INVALID_INPUT, "Invalid date range", Bundle.EMPTY)
                        } else {
                            runExport(context, ExportOrchestrator.dateRange(start, end))
                        }
                    }
                    ACTION_GET_LAST_STATUS -> publishLastStatus()
                    else -> publishResult(RESULT_INVALID_INPUT, "Unknown action: ${intent.action}", Bundle.EMPTY)
                }
            } catch (e: Exception) {
                Timber.e(e, "Automation intent failed")
                publishResult(RESULT_FAILURE, e.message ?: "Automation failed", Bundle.EMPTY)
            } finally {
                pendingResult.finish()
            }
        }
    }

    private suspend fun runExport(context: Context, dates: List<LocalDate>) {
        if (dates.isEmpty()) {
            publishResult(RESULT_INVALID_INPUT, "No dates requested", Bundle.EMPTY)
            return
        }

        val settings = settingsRepository.getExportSettings()
        val isPurchased = settingsRepository.isPurchased.first()
        val freeExportsRemaining = settingsRepository.getFreeExportsRemaining()
        val folderUri = settingsRepository.getExportFolderUri()

        if (!isPurchased && freeExportsRemaining <= 0) {
            val result = ExportResult(
                successCount = 0,
                totalCount = dates.size,
                failedDateDetails = dates.map { FailedDateDetail(it, ExportFailureReason.PAYWALL_REQUIRED) },
            )
            recordHistory(context, dates, result, ExportFailureReason.PAYWALL_REQUIRED, context.getString(R.string.schedule_unlock_required_short))
            publishExportResult(result, "Unlock Health.md to run automation exports")
            return
        }

        if (folderUri.isNullOrBlank()) {
            val result = ExportResult(
                successCount = 0,
                totalCount = dates.size,
                failedDateDetails = dates.map { FailedDateDetail(it, ExportFailureReason.NO_FOLDER_SELECTED) },
            )
            recordHistory(context, dates, result, ExportFailureReason.NO_FOLDER_SELECTED, "No export folder selected")
            publishExportResult(result, "No export folder selected")
            return
        }

        if (!healthRepository.hasPermissions()) {
            val result = ExportResult(
                successCount = 0,
                totalCount = dates.size,
                failedDateDetails = dates.map { FailedDateDetail(it, ExportFailureReason.ACCESS_DENIED) },
            )
            recordHistory(context, dates, result, ExportFailureReason.ACCESS_DENIED, "Health Connect permissions missing")
            publishExportResult(result, "Health Connect permissions missing")
            return
        }

        val orchestrator = ExportOrchestrator(healthRepository, exportRepository)
        val result = orchestrator.exportDates(dates, settings)
        recordHistory(context, dates, result, result.primaryFailureReason, result.warningSummary())

        if (ExportAccountingPolicy.shouldConsumeFreeExport(result, isPurchased)) {
            settingsRepository.decrementFreeExports()
        }

        publishExportResult(result, "${result.successCount}/${result.totalCount} days exported")
    }

    private suspend fun publishLastStatus() {
        val entry = exportHistoryRepository.getAllEntries().first().firstOrNull()
        if (entry == null) {
            publishResult(RESULT_SUCCESS, "No export history", Bundle.EMPTY)
            return
        }
        publishResult(
            if (entry.isFailure) RESULT_FAILURE else RESULT_SUCCESS,
            "${entry.successCount}/${entry.totalCount} days exported",
            Bundle().apply {
                putLong(EXTRA_HISTORY_ID, entry.id)
                putString(EXTRA_SOURCE, entry.source.name)
                putString(EXTRA_START_DATE, entry.dateRangeStart.toString())
                putString(EXTRA_END_DATE, entry.dateRangeEnd.toString())
                putInt(EXTRA_SUCCESS_COUNT, entry.successCount)
                putInt(EXTRA_TOTAL_COUNT, entry.totalCount)
                putString(EXTRA_FAILURE_REASON, entry.failureReason?.name)
                putString(EXTRA_WARNING, entry.warningSummary)
            },
        )
    }

    private suspend fun recordHistory(
        context: Context,
        dates: List<LocalDate>,
        result: ExportResult,
        failureReason: ExportFailureReason?,
        warning: String?,
    ) {
        val settings = settingsRepository.getExportSettings()
        exportHistoryRepository.insertEntry(
            ExportHistoryEntry(
                timestamp = System.currentTimeMillis(),
                source = ExportSource.SHORTCUT,
                dateRangeStart = dates.first(),
                dateRangeEnd = dates.last(),
                successCount = result.successCount,
                totalCount = result.totalCount,
                failureReason = failureReason,
                failedDateDetails = result.failedDateDetails,
                targetLabel = targetLabel(context, settings),
                fileCount = result.successCount * settings.selectedExportFormats.size,
                warningSummary = warning,
            )
        )
    }

    private fun targetLabel(context: Context, settings: com.healthmd.domain.model.ExportSettings): String = buildString {
        val subfolder = settings.subfolder.trim('/').takeIf { it.isNotBlank() }
        append(subfolder ?: context.getString(R.string.export_folder_root_label))
        settings.formatFolderPath(LocalDate.now().minusDays(1))?.takeIf { it.isNotBlank() }?.let {
            append("/").append(it.trim('/'))
        }
    }

    private fun ExportResult.warningSummary(): String? = when {
        isPartialSuccess -> "${failedDateDetails.size} failed date(s)"
        wasCancelled -> "Export cancelled"
        isFailure -> primaryFailureReason?.name
        else -> null
    }

    private fun publishExportResult(result: ExportResult, message: String) {
        publishResult(
            if (result.isFailure) RESULT_FAILURE else RESULT_SUCCESS,
            message,
            Bundle().apply {
                putInt(EXTRA_SUCCESS_COUNT, result.successCount)
                putInt(EXTRA_TOTAL_COUNT, result.totalCount)
                putString(EXTRA_FAILURE_REASON, result.primaryFailureReason?.name)
                putStringArray(EXTRA_FAILED_DATES, result.failedDateDetails.map { it.date.toString() }.toTypedArray())
            },
        )
    }

    private fun publishResult(code: Int, message: String, extras: Bundle) {
        resultCode = code
        resultData = message
        setResultExtras(extras)
        Timber.d("Automation result: %s (%s)", message, code)
    }

    companion object {
        const val ACTION_EXPORT_YESTERDAY = "com.healthmd.android.action.EXPORT_YESTERDAY"
        const val ACTION_EXPORT_LAST_DAYS = "com.healthmd.android.action.EXPORT_LAST_DAYS"
        const val ACTION_EXPORT_DATE = "com.healthmd.android.action.EXPORT_DATE"
        const val ACTION_EXPORT_RANGE = "com.healthmd.android.action.EXPORT_RANGE"
        const val ACTION_GET_LAST_STATUS = "com.healthmd.android.action.GET_LAST_STATUS"

        const val EXTRA_DAYS = "com.healthmd.android.extra.DAYS"
        const val EXTRA_DATE = "com.healthmd.android.extra.DATE"
        const val EXTRA_START_DATE = "com.healthmd.android.extra.START_DATE"
        const val EXTRA_END_DATE = "com.healthmd.android.extra.END_DATE"
        const val EXTRA_SUCCESS_COUNT = "com.healthmd.android.extra.SUCCESS_COUNT"
        const val EXTRA_TOTAL_COUNT = "com.healthmd.android.extra.TOTAL_COUNT"
        const val EXTRA_FAILURE_REASON = "com.healthmd.android.extra.FAILURE_REASON"
        const val EXTRA_FAILED_DATES = "com.healthmd.android.extra.FAILED_DATES"
        const val EXTRA_HISTORY_ID = "com.healthmd.android.extra.HISTORY_ID"
        const val EXTRA_SOURCE = "com.healthmd.android.extra.SOURCE"
        const val EXTRA_WARNING = "com.healthmd.android.extra.WARNING"

        const val RESULT_SUCCESS = 1
        const val RESULT_FAILURE = 2
        const val RESULT_INVALID_INPUT = 3
    }
}
