package com.healthmd.data.export

import com.healthmd.data.health.isLikelyHealthConnectRateLimit
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
        var processedDays = 0
        val effectiveSelection = settings.effectiveDataTypeSelection()

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
                    dataTypes = effectiveSelection,
                    includeGranularData = settings.shouldFetchGranularData(),
                ).associateBy { it.date }
            } catch (e: CancellationException) {
                return ExportResult(
                    successCount = successCount,
                    totalCount = totalDays,
                    failedDateDetails = failedDateDetails,
                    wasCancelled = true,
                )
            } catch (e: SecurityException) {
                val reason = classifySecurityException(e)
                if (reason == ExportFailureReason.RATE_LIMITED) {
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
                    failedDateDetails.add(FailedDateDetail(date, reason, e.message))
                }
                processedDays += chunk.size
                continue
            } catch (e: Exception) {
                val reason = if (e.isHealthConnectRateLimit() || e.isLikelyHealthConnectRateLimit()) {
                    ExportFailureReason.RATE_LIMITED
                } else {
                    classifyException(e)
                }
                if (reason == ExportFailureReason.RATE_LIMITED) {
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
                    failedDateDetails.add(FailedDateDetail(date, reason, e.message))
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
                var filteredData = healthData.filtered(effectiveSelection).filtered(settings.metricSelection)

                if (!filteredData.hasAnyData) {
                    val fallbackData = try {
                        healthRepository.fetchHealthData(date)
                    } catch (e: CancellationException) {
                        return ExportResult(
                            successCount = successCount,
                            totalCount = totalDays,
                            failedDateDetails = failedDateDetails,
                            wasCancelled = true,
                        )
                    } catch (e: SecurityException) {
                        val reason = classifySecurityException(e)
                        if (reason == ExportFailureReason.RATE_LIMITED) {
                            markRemainingRateLimited(
                                dates = dates,
                                startIndex = processedDays + index,
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
                        failedDateDetails.add(FailedDateDetail(date, reason, e.message))
                        continue
                    } catch (e: Exception) {
                        val reason = if (e.isHealthConnectRateLimit() || e.isLikelyHealthConnectRateLimit()) {
                            ExportFailureReason.RATE_LIMITED
                        } else {
                            classifyException(e)
                        }
                        if (reason == ExportFailureReason.RATE_LIMITED) {
                            markRemainingRateLimited(
                                dates = dates,
                                startIndex = processedDays + index,
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
                        failedDateDetails.add(FailedDateDetail(date, reason, e.message))
                        continue
                    }
                    filteredData = fallbackData.filtered(effectiveSelection).filtered(settings.metricSelection)
                }

                if (!filteredData.hasAnyData) {
                    failedDateDetails.add(FailedDateDetail(date, ExportFailureReason.NO_HEALTH_DATA))
                    continue
                }

                val success = exportRepository.exportHealthData(filteredData, settings)
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
                val effectiveSelection = settings.effectiveDataTypeSelection()
                val healthData = healthRepository.fetchHealthData(date)
                val filteredData = healthData.filtered(effectiveSelection).filtered(settings.metricSelection)

                if (!filteredData.hasAnyData) {
                    failedDateDetails.add(FailedDateDetail(date, ExportFailureReason.NO_HEALTH_DATA))
                    continue
                }

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
                // Health Connect permissions are missing/incomplete, or background workers
                // lack the dedicated background read permission.
                val reason = classifySecurityException(e)
                if (reason == ExportFailureReason.RATE_LIMITED) {
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
                    FailedDateDetail(date, reason, e.message)
                )
            } catch (e: Exception) {
                val reason = if (e.isHealthConnectRateLimit() || e.isLikelyHealthConnectRateLimit()) {
                    ExportFailureReason.RATE_LIMITED
                } else {
                    classifyException(e)
                }
                if (reason == ExportFailureReason.RATE_LIMITED) {
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

    suspend fun previewDates(
        dates: List<LocalDate>,
        settings: ExportSettings,
        maxPreviewDays: Int = MAX_PREVIEW_DAYS,
        onProgress: ((current: Int, total: Int, dateString: String) -> Unit)? = null,
    ): ExportPreview {
        val previewDates = dates.take(maxPreviewDays)
        val days = mutableListOf<ExportPreviewDay>()

        for ((index, date) in previewDates.withIndex()) {
            coroutineContext.ensureActive()
            onProgress?.invoke(index + 1, previewDates.size, date.toString())

            if (healthRepository.isBeforeFirstUnlock()) {
                days.add(ExportPreviewDay(date = date, failureReason = ExportFailureReason.DEVICE_LOCKED))
                continue
            }

            try {
                val effectiveSelection = settings.effectiveDataTypeSelection()
                val healthData = healthRepository.fetchHealthDataRange(
                    dates = listOf(date),
                    dataTypes = effectiveSelection,
                    includeGranularData = settings.shouldFetchGranularData(),
                ).firstOrNull() ?: HealthData(date)
                val filteredData = healthData.filtered(effectiveSelection).filtered(settings.metricSelection)

                if (!filteredData.hasAnyData) {
                    days.add(ExportPreviewDay(date = date, failureReason = ExportFailureReason.NO_HEALTH_DATA))
                } else {
                    days.add(exportRepository.previewHealthData(filteredData, settings))
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: SecurityException) {
                days.add(ExportPreviewDay(date = date, failureReason = classifySecurityException(e), warning = e.message))
            } catch (e: Exception) {
                val reason = if (e.isHealthConnectRateLimit() || e.isLikelyHealthConnectRateLimit()) {
                    ExportFailureReason.RATE_LIMITED
                } else {
                    classifyException(e)
                }
                days.add(ExportPreviewDay(date = date, failureReason = reason, warning = e.message))
            }
        }

        return ExportPreview(
            requestedDateCount = dates.size,
            previewedDateCount = previewDates.size,
            isTruncated = dates.size > previewDates.size,
            days = days,
        )
    }

    private fun chunkSize(settings: ExportSettings): Int =
        if (settings.shouldFetchGranularData()) GRANULAR_RANGE_CHUNK_DAYS else RANGE_CHUNK_DAYS

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
        const val MAX_PREVIEW_DAYS = 14

        fun dateRange(from: LocalDate, to: LocalDate): List<LocalDate> {
            val dates = mutableListOf<LocalDate>()
            var current = from
            while (!current.isAfter(to)) {
                dates.add(current)
                current = current.plusDays(1)
            }
            return dates
        }

        private fun classifySecurityException(e: SecurityException): ExportFailureReason {
            val message = e.message.orEmpty()
            return when {
                isRateLimitMessage(message) -> ExportFailureReason.RATE_LIMITED
                message.contains("background", ignoreCase = true) ->
                    ExportFailureReason.BACKGROUND_PERMISSION_DENIED
                message.contains("permission", ignoreCase = true) ||
                    message.contains("denied", ignoreCase = true) ||
                    message.contains("access", ignoreCase = true) ->
                    ExportFailureReason.ACCESS_DENIED
                else -> ExportFailureReason.DEVICE_LOCKED
            }
        }

        private fun classifyException(e: Exception): ExportFailureReason {
            val message = e.message.orEmpty()
            val className = e::class.qualifiedName.orEmpty()
            return when {
                isRateLimitMessage(message) -> ExportFailureReason.RATE_LIMITED
                message.contains("Health Connect", ignoreCase = true) ||
                    className.contains("health", ignoreCase = true) ->
                    ExportFailureReason.HEALTH_CONNECT_ERROR
                else -> ExportFailureReason.UNKNOWN
            }
        }

        private fun isRateLimitMessage(message: String): Boolean =
            listOf("rate limit", "rate-limit", "too many requests", "quota", "throttle")
                .any { message.contains(it, ignoreCase = true) }

        private fun markRemainingDates(
            dates: List<LocalDate>,
            fromIndex: Int,
            failedDateDetails: MutableList<FailedDateDetail>,
            reason: ExportFailureReason,
            errorDetails: String?,
        ) {
            for (i in fromIndex until dates.size) {
                failedDateDetails.add(FailedDateDetail(dates[i], reason, errorDetails))
            }
        }
    }
}

