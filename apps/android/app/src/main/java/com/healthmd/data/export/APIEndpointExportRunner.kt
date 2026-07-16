package com.healthmd.data.export

import com.healthmd.data.isHealthConnectRateLimit
import com.healthmd.data.health.isLikelyHealthConnectRateLimit
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportPreview
import com.healthmd.domain.model.ExportPreviewDay
import com.healthmd.domain.model.ExportPreviewFile
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.repository.HealthRepository
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive
import java.time.LocalDate
import javax.inject.Inject
import kotlin.coroutines.coroutineContext

class APIEndpointExportRunner @Inject constructor(
    private val healthRepository: HealthRepository,
    private val envelopeBuilder: APIExportEnvelopeBuilder,
    private val jsonExporter: JsonExporter,
    private val uploader: APIExportUploader,
    private val credentialStore: APIExportCredentialStore,
) {
    suspend fun exportDates(
        dates: List<LocalDate>,
        settings: ExportSettings,
        onProgress: ((current: Int, total: Int, dateString: String) -> Unit)? = null,
        expectedDestinationFingerprint: String? = null,
    ): ExportResult {
        val normalizedDates = dates.distinct().sorted()
        if (normalizedDates.isEmpty()) {
            return ExportResult(0, 0, target = ExportTarget.API_ENDPOINT)
        }
        if (settings.selectedExportFormats.isEmpty()) {
            return configurationFailure(
                normalizedDates,
                ExportFailureReason.UNKNOWN,
                "Select at least one export format before exporting to an API endpoint.",
            )
        }
        val endpoint = APIExportEndpoint.normalizedOrNull(settings.apiEndpointUrl)
            ?: return configurationFailure(
                normalizedDates,
                ExportFailureReason.INVALID_API_ENDPOINT,
                "Configure a valid HTTP or HTTPS API endpoint before exporting.",
            )
        // Capture endpoint credentials and headers atomically at action start. Manual and
        // scheduled exports therefore cannot mix old and new configuration mid-collection.
        val requestConfiguration = credentialStore.requestConfiguration(endpoint)
            ?: return configurationFailure(
                normalizedDates,
                ExportFailureReason.INVALID_API_ENDPOINT,
                "API endpoint request configuration is unavailable.",
            )
        if (expectedDestinationFingerprint != null &&
            requestConfiguration.destinationFingerprint != expectedDestinationFingerprint
        ) {
            return configurationFailure(
                normalizedDates,
                ExportFailureReason.INVALID_API_ENDPOINT,
                "API endpoint or request headers changed before export started.",
            )
        }

        val records = mutableListOf<HealthData>()
        val failedDateDetails = mutableListOf<FailedDateDetail>()

        for ((index, date) in normalizedDates.withIndex()) {
            try {
                coroutineContext.ensureActive()
            } catch (_: CancellationException) {
                return ExportResult(
                    successCount = 0,
                    totalCount = normalizedDates.size,
                    failedDateDetails = failedDateDetails,
                    wasCancelled = true,
                    target = ExportTarget.API_ENDPOINT,
                )
            }

            onProgress?.invoke(index + 1, normalizedDates.size, date.toString())
            if (healthRepository.isBeforeFirstUnlock()) {
                failedDateDetails += FailedDateDetail(date, ExportFailureReason.DEVICE_LOCKED)
                continue
            }

            try {
                val record = fetchFilteredRecord(date, settings)
                if (record.hasAnyData) {
                    records += record
                } else {
                    failedDateDetails += FailedDateDetail(date, ExportFailureReason.NO_HEALTH_DATA)
                }
            } catch (error: CancellationException) {
                return ExportResult(
                    successCount = 0,
                    totalCount = normalizedDates.size,
                    failedDateDetails = failedDateDetails,
                    wasCancelled = true,
                    target = ExportTarget.API_ENDPOINT,
                )
            } catch (error: SecurityException) {
                failedDateDetails += FailedDateDetail(date, classifySecurityException(error), error.message)
            } catch (error: Exception) {
                failedDateDetails += FailedDateDetail(date, classifyException(error), error.message)
            }
        }

        if (records.isEmpty()) {
            return ExportResult(
                successCount = 0,
                totalCount = normalizedDates.size,
                failedDateDetails = failedDateDetails.ifEmpty {
                    listOf(FailedDateDetail(normalizedDates.first(), ExportFailureReason.NO_HEALTH_DATA))
                },
                target = ExportTarget.API_ENDPOINT,
            )
        }

        try {
            coroutineContext.ensureActive()
            val payload = envelopeBuilder.build(
                records = records,
                failedDateDetails = failedDateDetails,
                settings = settings,
                dateRangeStart = normalizedDates.first(),
                dateRangeEnd = normalizedDates.last(),
            )
            val uploadResult = uploader.upload(
                endpointUrl = requestConfiguration.endpointUrl,
                payload = payload,
                authorizationHeader = requestConfiguration.authorizationHeader,
                requestHeaders = requestConfiguration.requestHeaders,
            )
            return ExportResult(
                successCount = records.size,
                totalCount = normalizedDates.size,
                failedDateDetails = failedDateDetails,
                target = ExportTarget.API_ENDPOINT,
                httpStatusCode = uploadResult.statusCode,
            )
        } catch (_: CancellationException) {
            return ExportResult(
                successCount = 0,
                totalCount = normalizedDates.size,
                failedDateDetails = failedDateDetails,
                wasCancelled = true,
                target = ExportTarget.API_ENDPOINT,
            )
        } catch (error: APIExportClientException) {
            val safeDetails = error.statusCode?.let { "HTTP $it" }
                ?: when (error.failureReason) {
                    ExportFailureReason.NETWORK_ERROR -> "Connection failed"
                    ExportFailureReason.INVALID_API_ENDPOINT -> "Invalid API endpoint"
                    else -> null
                }
            return uploadFailure(normalizedDates, error.failureReason, safeDetails, error.statusCode)
        } catch (_: Exception) {
            return uploadFailure(normalizedDates, ExportFailureReason.NETWORK_ERROR, "Connection failed")
        }
    }

    suspend fun previewDates(
        dates: List<LocalDate>,
        settings: ExportSettings,
        maxPreviewDays: Int = ExportOrchestrator.MAX_PREVIEW_DAYS,
        onProgress: ((current: Int, total: Int, dateString: String) -> Unit)? = null,
    ): ExportPreview {
        val normalizedDates = dates.distinct().sortedDescending()
        val previewCandidates = normalizedDates.take(ExportOrchestrator.MAX_PREVIEW_FETCH_ATTEMPTS)
        val days = mutableListOf<ExportPreviewDay>()
        var attemptedDateCount = 0

        for (date in previewCandidates) {
            if (days.count { it.hasOutput } >= maxPreviewDays) break
            coroutineContext.ensureActive()
            attemptedDateCount++
            onProgress?.invoke(attemptedDateCount, previewCandidates.size, date.toString())
            val previewDay = if (healthRepository.isBeforeFirstUnlock()) {
                ExportPreviewDay(date = date, failureReason = ExportFailureReason.DEVICE_LOCKED)
            } else {
                try {
                    val record = fetchFilteredRecord(date, settings)
                    if (!record.hasAnyData) {
                        ExportPreviewDay(date = date, failureReason = ExportFailureReason.NO_HEALTH_DATA)
                    } else {
                        val content = jsonExporter.export(
                            data = record,
                            customization = settings.formatCustomization,
                            includeGranularData = settings.includeGranularData,
                        )
                        ExportPreviewDay(
                            date = date,
                            files = listOf(
                                ExportPreviewFile(
                                    format = ExportFormat.JSON,
                                    relativePath = "POST/${date}.json",
                                    byteCount = content.toByteArray(Charsets.UTF_8).size,
                                    content = content,
                                )
                            ),
                        )
                    }
                } catch (error: SecurityException) {
                    ExportPreviewDay(date = date, failureReason = classifySecurityException(error), warning = error.message)
                } catch (error: CancellationException) {
                    throw error
                } catch (error: Exception) {
                    ExportPreviewDay(date = date, failureReason = classifyException(error), warning = error.message)
                }
            }
            if (previewDay.failureReason != ExportFailureReason.NO_HEALTH_DATA) {
                days.add(previewDay)
            }
        }
        return ExportPreview(
            requestedDateCount = normalizedDates.size,
            previewedDateCount = days.count { it.hasOutput },
            isTruncated = normalizedDates.size > attemptedDateCount,
            days = days,
        )
    }

    private suspend fun fetchFilteredRecord(date: LocalDate, settings: ExportSettings): HealthData {
        val effectiveSelection = settings.effectiveDataTypeSelection()
        val ranged = healthRepository.fetchHealthDataRange(
            dates = listOf(date),
            dataTypes = effectiveSelection,
            includeGranularData = settings.shouldFetchGranularData(),
        ).firstOrNull() ?: HealthData(date)
        var filtered = ranged.filtered(effectiveSelection).filtered(settings.metricSelection)
        if (!filtered.hasAnyData) {
            filtered = healthRepository.fetchHealthData(date)
                .filtered(effectiveSelection)
                .filtered(settings.metricSelection)
        }
        return filtered
    }

    private fun configurationFailure(
        dates: List<LocalDate>,
        reason: ExportFailureReason,
        message: String,
    ): ExportResult = ExportResult(
        successCount = 0,
        totalCount = dates.size,
        failedDateDetails = dates.map { FailedDateDetail(it, reason, message) },
        target = ExportTarget.API_ENDPOINT,
    )

    private fun uploadFailure(
        dates: List<LocalDate>,
        reason: ExportFailureReason,
        details: String?,
        statusCode: Int? = null,
    ): ExportResult = ExportResult(
        successCount = 0,
        totalCount = dates.size,
        failedDateDetails = dates.map { FailedDateDetail(it, reason, details) },
        target = ExportTarget.API_ENDPOINT,
        httpStatusCode = statusCode,
    )

    private fun classifySecurityException(error: SecurityException): ExportFailureReason {
        val message = error.message.orEmpty()
        return when {
            message.contains("rate limit", ignoreCase = true) ||
                message.contains("too many requests", ignoreCase = true) ||
                message.contains("quota", ignoreCase = true) -> ExportFailureReason.RATE_LIMITED
            message.contains("background", ignoreCase = true) -> ExportFailureReason.BACKGROUND_PERMISSION_DENIED
            message.contains("permission", ignoreCase = true) ||
                message.contains("denied", ignoreCase = true) ||
                message.contains("access", ignoreCase = true) -> ExportFailureReason.ACCESS_DENIED
            else -> ExportFailureReason.DEVICE_LOCKED
        }
    }

    private fun classifyException(error: Exception): ExportFailureReason = when {
        error.isHealthConnectRateLimit() || error.isLikelyHealthConnectRateLimit() -> ExportFailureReason.RATE_LIMITED
        error.message.orEmpty().contains("Health Connect", ignoreCase = true) -> ExportFailureReason.HEALTH_CONNECT_ERROR
        else -> ExportFailureReason.UNKNOWN
    }
}
