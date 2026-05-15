package com.healthmd.data.export

import com.healthmd.data.health.isLikelyHealthConnectRateLimit
import com.healthmd.domain.model.*
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.HealthRepository
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
        if (dates.size <= 1) {
            return exportDatesOneByOne(dates, settings, onProgress)
        }

        val totalDays = dates.size
        var successCount = 0
        val failedDateDetails = mutableListOf<FailedDateDetail>()
        var processedDays = 0

        for (chunk in dates.chunked(chunkSize(settings))) {
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

            if (healthRepository.isBeforeFirstUnlock()) {
                for ((index, date) in chunk.withIndex()) {
                    onProgress?.invoke(processedDays + index + 1, totalDays, date.toString())
                    failedDateDetails.add(FailedDateDetail(date, ExportFailureReason.DEVICE_LOCKED))
                }
                processedDays += chunk.size
                continue
            }

            val healthDataByDate = try {
                healthRepository.fetchHealthDataRange(
                    dates = chunk,
                    dataTypes = settings.dataTypes,
                    includeGranularData = settings.includeGranularData,
                ).associateBy { it.date }
            } catch (e: CancellationException) {
                return ExportResult(
                    successCount = successCount,
                    totalCount = totalDays,
                    failedDateDetails = failedDateDetails,
                    wasCancelled = true,
                )
            } catch (e: SecurityException) {
                val reason = if (e.message?.contains("background", ignoreCase = true) == true) {
                    ExportFailureReason.BACKGROUND_PERMISSION_DENIED
                } else {
                    ExportFailureReason.DEVICE_LOCKED
                }
                for ((index, date) in chunk.withIndex()) {
                    onProgress?.invoke(processedDays + index + 1, totalDays, date.toString())
                    failedDateDetails.add(FailedDateDetail(date, reason, e.message))
                }
                processedDays += chunk.size
                continue
            } catch (e: Exception) {
                if (e.isLikelyHealthConnectRateLimit()) {
                    markRemainingRateLimited(
                        dates = dates,
                        startIndex = processedDays,
                        totalDays = totalDays,
                        error = e,
                        failedDateDetails = failedDateDetails,
                        onProgress = onProgress,
                    )
                    return ExportResult(
                        successCount = successCount,
                        totalCount = totalDays,
                        failedDateDetails = failedDateDetails,
                    )
                }

                for ((index, date) in chunk.withIndex()) {
                    onProgress?.invoke(processedDays + index + 1, totalDays, date.toString())
                    failedDateDetails.add(FailedDateDetail(date, ExportFailureReason.UNKNOWN, e.message))
                }
                processedDays += chunk.size
                continue
            }

            for ((index, date) in chunk.withIndex()) {
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

                onProgress?.invoke(processedDays + index + 1, totalDays, date.toString())
                val healthData = healthDataByDate[date] ?: HealthData(date)

                if (!healthData.hasAnyData) {
                    failedDateDetails.add(FailedDateDetail(date, ExportFailureReason.NO_HEALTH_DATA))
                    continue
                }

                val success = exportRepository.exportHealthData(healthData.filtered(settings.dataTypes), settings)
                if (success) {
                    successCount++
                } else {
                    failedDateDetails.add(FailedDateDetail(date, ExportFailureReason.FILE_WRITE_ERROR))
                }
            }

            processedDays += chunk.size
        }

        return ExportResult(
            successCount = successCount,
            totalCount = totalDays,
            failedDateDetails = failedDateDetails,
        )
    }

    private suspend fun exportDatesOneByOne(
        dates: List<LocalDate>,
        settings: ExportSettings,
        onProgress: ((current: Int, total: Int, dateString: String) -> Unit)?,
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
                // background workers lack the dedicated background read permission.
                val reason = if (e.message?.contains("background", ignoreCase = true) == true) {
                    ExportFailureReason.BACKGROUND_PERMISSION_DENIED
                } else {
                    ExportFailureReason.DEVICE_LOCKED
                }
                failedDateDetails.add(
                    FailedDateDetail(date, reason, e.message)
                )
            } catch (e: Exception) {
                if (e.isLikelyHealthConnectRateLimit()) {
                    markRemainingRateLimited(
                        dates = dates,
                        startIndex = index,
                        totalDays = totalDays,
                        error = e,
                        failedDateDetails = failedDateDetails,
                        onProgress = onProgress,
                    )
                    return ExportResult(
                        successCount = successCount,
                        totalCount = totalDays,
                        failedDateDetails = failedDateDetails,
                    )
                }

                failedDateDetails.add(
                    FailedDateDetail(date, ExportFailureReason.UNKNOWN, e.message)
                )
            }
        }

        return ExportResult(
            successCount = successCount,
            totalCount = totalDays,
            failedDateDetails = failedDateDetails,
        )
    }

    private fun chunkSize(settings: ExportSettings): Int =
        if (settings.includeGranularData) GRANULAR_RANGE_CHUNK_DAYS else RANGE_CHUNK_DAYS

    private fun markRemainingRateLimited(
        dates: List<LocalDate>,
        startIndex: Int,
        totalDays: Int,
        error: Exception,
        failedDateDetails: MutableList<FailedDateDetail>,
        onProgress: ((current: Int, total: Int, dateString: String) -> Unit)?,
    ) {
        for (index in startIndex until dates.size) {
            val date = dates[index]
            onProgress?.invoke(index + 1, totalDays, date.toString())
            failedDateDetails.add(
                FailedDateDetail(
                    date = date,
                    reason = ExportFailureReason.RATE_LIMITED,
                    errorDetails = error.message,
                )
            )
        }
    }

    companion object {
        private const val RANGE_CHUNK_DAYS = 30
        private const val GRANULAR_RANGE_CHUNK_DAYS = 7

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
