package com.healthmd.data.export

import com.healthmd.domain.model.*
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.data.isHealthConnectRateLimit
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import java.time.LocalDate
import kotlin.coroutines.coroutineContext

class ExportOrchestrator(
    private val healthRepository: HealthRepository,
    private val exportRepository: ExportRepository,
) {
    suspend fun exportDates(
        dates: List<LocalDate>,
        settings: ExportSettings,
        onProgress: ((current: Int, total: Int, dateString: String) -> Unit)? = null,
    ): ExportResult {
        val totalDays = dates.size
        var successCount = 0
        val failedDateDetails = mutableListOf<FailedDateDetail>()

        for ((index, date) in dates.withIndex()) {
            // Check for cancellation
            try {
                coroutineContext.ensureActive()
            } catch (_: CancellationException) {
                return ExportResult(
                    successCount = successCount,
                    totalCount = totalDays,
                    failedDateDetails = failedDateDetails,
                    wasCancelled = true,
                )
            }

            onProgress?.invoke(index + 1, totalDays, date.toString())

            // Check for Before First Unlock (BFU) state — i.e. the phone was rebooted
            // and the user has never entered their PIN this session. In BFU, Health
            // Connect's credential-encrypted storage is not mounted and reads silently
            // return empty data. Surface DEVICE_LOCKED so the worker can retry later.
            // NOTE: A locked *screen* (AFU) does NOT block Health Connect — CE keys
            // remain in memory after the first unlock, so night-time exports work fine.
            if (healthRepository.isBeforeFirstUnlock()) {
                failedDateDetails.add(FailedDateDetail(date, ExportFailureReason.DEVICE_LOCKED))
                continue
            }

            try {
                val healthData = healthRepository.fetchHealthData(date)

                if (!healthData.hasAnyData) {
                    failedDateDetails.add(FailedDateDetail(date, ExportFailureReason.NO_HEALTH_DATA))
                    continue
                }

                val filteredData = healthData.filtered(settings.dataTypes)
                val success = exportRepository.exportHealthData(filteredData, settings)

                if (success) {
                    successCount++
                } else {
                    failedDateDetails.add(FailedDateDetail(date, ExportFailureReason.FILE_WRITE_ERROR))
                }
            } catch (e: CancellationException) {
                return ExportResult(
                    successCount = successCount,
                    totalCount = totalDays,
                    failedDateDetails = failedDateDetails,
                    wasCancelled = true,
                )
            } catch (e: SecurityException) {
                // Health Connect throws SecurityException when the device is locked or when
                // Health Connect permissions are missing or incomplete.
                val reason = e.toExportSecurityFailureReason()
                failedDateDetails.add(
                    FailedDateDetail(date, reason, e.message)
                )
            } catch (e: Exception) {
                val reason = if (e.isHealthConnectRateLimit()) {
                    ExportFailureReason.RATE_LIMITED
                } else {
                    ExportFailureReason.UNKNOWN
                }
                failedDateDetails.add(
                    FailedDateDetail(date, reason, e.message)
                )
            }
        }

        return ExportResult(
            successCount = successCount,
            totalCount = totalDays,
            failedDateDetails = failedDateDetails,
        )
    }

    companion object {
        fun dateRange(from: LocalDate, to: LocalDate): List<LocalDate> {
            val dates = mutableListOf<LocalDate>()
            var current = from
            while (!current.isAfter(to)) {
                dates.add(current)
                current = current.plusDays(1)
            }
            return dates
        }
    }
}

private fun SecurityException.toExportSecurityFailureReason(): ExportFailureReason {
    val message = message.orEmpty()
    return when {
        message.contains("background", ignoreCase = true) ->
            ExportFailureReason.BACKGROUND_PERMISSION_DENIED
        message.contains("history", ignoreCase = true) ||
            message.contains("permission", ignoreCase = true) ||
            message.contains("access", ignoreCase = true) ->
            ExportFailureReason.ACCESS_DENIED
        message.contains("lock", ignoreCase = true) ||
            message.contains("credential", ignoreCase = true) ->
            ExportFailureReason.DEVICE_LOCKED
        else -> ExportFailureReason.DEVICE_LOCKED
    }
}
