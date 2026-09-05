package com.healthmd.data.export

import com.healthmd.data.health.isLikelyHealthConnectRateLimit
import com.healthmd.data.isHealthConnectRateLimit
import com.healthmd.domain.exportengine.AndroidDailyAggregateExportPlanner
import com.healthmd.domain.exportengine.LocalDailyAggregateExportPlanner
import com.healthmd.domain.exportengine.LocalDailyAggregatePlanningResult
import com.healthmd.domain.exportengine.ProductionDailyAggregateNativePlanBuilder
import com.healthmd.domain.exportengine.ShadowExportDiagnosticSink
import com.healthmd.domain.exportengine.isFatalExportEngineFailure
import com.healthmd.domain.model.AgentDataArtifactOutcome
import com.healthmd.domain.model.AgentDataGatewayEndpoint
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
import com.healthmd.rawexport.allowsInteractiveRouteConsent
import java.time.LocalDate
import java.time.ZoneId
import javax.inject.Inject
import javax.inject.Singleton
import kotlin.coroutines.coroutineContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ensureActive

/** One provider capture call for one requested owner date (mirrors [APIExportCaptureSource]). */
interface AgentDataGatewayCaptureSource {
    fun isBeforeFirstUnlock(): Boolean

    suspend fun authorizeExerciseRouteConsent(dates: List<LocalDate>, settings: ExportSettings) = Unit

    suspend fun capture(date: LocalDate, settings: ExportSettings): HealthData
}

private class HealthRepositoryAgentDataGatewayCaptureSource(
    private val healthRepository: HealthRepository,
) : AgentDataGatewayCaptureSource {
    override fun isBeforeFirstUnlock(): Boolean = healthRepository.isBeforeFirstUnlock()

    override suspend fun authorizeExerciseRouteConsent(dates: List<LocalDate>, settings: ExportSettings) {
        val effectiveSelection = settings.effectiveDataTypeSelection()
        if (effectiveSelection.workouts) {
            healthRepository.authorizeExerciseRouteConsent(
                dates = dates,
                dataTypes = effectiveSelection,
                includeGranularData = settings.shouldFetchGranularData(),
                zoneId = settings.executionEnginePin?.ianaTimeZone?.let(ZoneId::of)
                    ?: ZoneId.systemDefault(),
            )
        }
    }

    override suspend fun capture(date: LocalDate, settings: ExportSettings): HealthData {
        val effectiveSelection = settings.effectiveDataTypeSelection()
        val captured = healthRepository.fetchHealthDataRange(
            dates = listOf(date),
            dataTypes = effectiveSelection,
            includeGranularData = settings.shouldFetchGranularData(),
        ).firstOrNull() ?: HealthData(date)
        val filtered = captured
            .filtered(effectiveSelection)
            .filtered(settings.metricSelection)
        if (filtered.hasAnyData) return filtered

        return healthRepository.fetchHealthData(date)
            .filtered(effectiveSelection)
            .filtered(settings.metricSelection)
    }
}

/**
 * Export runner for the Agent Data gateway destination (ingestion protocol v1).
 *
 * The runner produces the profile's per-day daily health-data JSON artifact EXACTLY as the
 * folder destination would — the same capture pipeline, the same local daily-aggregate
 * planner, and the same rendered bytes (including the legacy-engine fallback) — and then
 * uploads each artifact file individually to the gateway per the protocol. The bytes are
 * never re-encoded or wrapped in an envelope.
 *
 * Per-artifact outcomes are surfaced health-free (accepted / rejected-with-code /
 * upload-failed) on [ExportResult.agentDataOutcomes]. A failed upload never blocks the
 * remaining artifacts: each artifact upload is independent, and the bounded retry posture
 * lives inside [AgentDataGatewayUploadClient].
 */
@Singleton
class AgentDataGatewayExportRunner private constructor(
    private val captureSource: AgentDataGatewayCaptureSource,
    private val gatewayClient: AgentDataGatewayUploadClient,
    private val jsonExporter: JsonExporter,
    private val dailyAggregatePlanner: LocalDailyAggregateExportPlanner,
) {

    /** Production/Dagger constructor builds the shared folder-parity planner. */
    @Inject
    constructor(
        healthRepository: HealthRepository,
        gatewayClient: AgentDataGatewayUploadClient,
        jsonExporter: JsonExporter,
        markdownExporter: MarkdownExporter,
        csvExporter: CsvExporter,
        obsidianBasesExporter: ObsidianBasesExporter,
        diagnosticSink: ShadowExportDiagnosticSink = ShadowExportDiagnosticSink { },
    ) : this(
        captureSource = HealthRepositoryAgentDataGatewayCaptureSource(healthRepository),
        gatewayClient = gatewayClient,
        jsonExporter = jsonExporter,
        dailyAggregatePlanner = AndroidDailyAggregateExportPlanner(
            nativePlanner = ProductionDailyAggregateNativePlanBuilder(
                markdownExporter = markdownExporter,
                jsonExporter = jsonExporter,
                csvExporter = csvExporter,
                obsidianBasesExporter = obsidianBasesExporter,
            ),
            diagnosticSink = diagnosticSink,
        ),
    )

    /** Focused JVM-test seam with an injected capture source and planner. */
    internal constructor(
        captureSource: AgentDataGatewayCaptureSource,
        gatewayClient: AgentDataGatewayUploadClient,
        jsonExporter: JsonExporter,
        dailyAggregatePlanner: LocalDailyAggregateExportPlanner,
        @Suppress("UNUSED_PARAMETER") testSeam: Unit = Unit,
    ) : this(
        captureSource = captureSource,
        gatewayClient = gatewayClient,
        jsonExporter = jsonExporter,
        dailyAggregatePlanner = dailyAggregatePlanner,
    )

    suspend fun exportDates(
        dates: List<LocalDate>,
        settings: ExportSettings,
        onProgress: ((current: Int, total: Int, dateString: String) -> Unit)? = null,
        expectedDestinationFingerprint: String? = null,
    ): ExportResult {
        val normalizedDates = dates.distinct().sorted()
        if (normalizedDates.isEmpty()) {
            return ExportResult(0, 0, target = ExportTarget.AGENT_DATA_GATEWAY)
        }
        val endpoint = AgentDataGatewayEndpoint.normalizedOrNull(settings.agentDataGatewayUrl)
            ?: return configurationFailure(normalizedDates, ExportFailureReason.INVALID_API_ENDPOINT)
        if (expectedDestinationFingerprint != null &&
            AgentDataGatewayEndpoint.fingerprint(settings.agentDataGatewayUrl) != expectedDestinationFingerprint
        ) {
            return configurationFailure(normalizedDates, ExportFailureReason.INVALID_API_ENDPOINT)
        }

        var successCount = 0
        val failures = mutableListOf<FailedDateDetail>()
        val outcomes = mutableListOf<AgentDataArtifactOutcome>()
        var lastStatusCode: Int? = null

        if (coroutineContext.allowsInteractiveRouteConsent() && !captureSource.isBeforeFirstUnlock()) {
            try {
                captureSource.authorizeExerciseRouteConsent(normalizedDates, settings)
            } catch (_: CancellationException) {
                return cancelledResult(normalizedDates, outcomes)
            } catch (_: Exception) {
                // Consent is optional; preserve the established capture and failure behavior.
            }
        }

        for ((index, date) in normalizedDates.withIndex()) {
            try {
                coroutineContext.ensureActive()
            } catch (_: CancellationException) {
                val attempted = normalizedDates.subList(0, index + 1)
                return cancelledResult(attempted, outcomes, successCount, failures)
            }
            onProgress?.invoke(index + 1, normalizedDates.size, date.toString())

            if (captureSource.isBeforeFirstUnlock()) {
                failures += FailedDateDetail(date, ExportFailureReason.DEVICE_LOCKED)
                continue
            }

            val data = try {
                captureSource.capture(date, settings)
            } catch (error: CancellationException) {
                throw error
            } catch (error: SecurityException) {
                failures += FailedDateDetail(date, classifySecurityException(error), error.message)
                continue
            } catch (error: Exception) {
                failures += FailedDateDetail(date, classifyException(error), error.message)
                continue
            }

            if (!data.hasAnyData) {
                failures += FailedDateDetail(date, ExportFailureReason.NO_HEALTH_DATA)
                continue
            }

            val artifacts = try {
                renderDailyJsonArtifacts(data, settings)
            } catch (error: Throwable) {
                if (error is CancellationException) throw error
                if (error.isFatalExportEngineFailure()) throw error
                failures += FailedDateDetail(date, ExportFailureReason.UNKNOWN)
                continue
            }
            if (artifacts.isEmpty()) {
                failures += FailedDateDetail(date, ExportFailureReason.GATEWAY_FORMAT_UNSUPPORTED)
                continue
            }

            var daySucceeded = true
            for (artifact in artifacts) {
                try {
                    coroutineContext.ensureActive()
                } catch (_: CancellationException) {
                    val attempted = normalizedDates.subList(0, index + 1)
                    return cancelledResult(attempted, outcomes, successCount, failures)
                }
                val outcome = try {
                    val receipt = gatewayClient.upload(endpoint, artifact.manifest, artifact.bytes)
                    lastStatusCode = receipt.httpStatusCode
                    when (receipt) {
                        is AgentDataUploadReceipt.Accepted -> AgentDataArtifactOutcome(
                            ownerDate = date,
                            relativePath = artifact.outcome.relativePath,
                            state = AgentDataArtifactOutcome.State.ACCEPTED,
                        )
                        is AgentDataUploadReceipt.Rejected -> AgentDataArtifactOutcome(
                            ownerDate = date,
                            relativePath = artifact.outcome.relativePath,
                            state = AgentDataArtifactOutcome.State.REJECTED,
                            rejectionCode = receipt.code,
                        )
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: AgentDataGatewayException) {
                    // A failed upload never blocks the remaining artifacts.
                    daySucceeded = false
                    AgentDataArtifactOutcome(
                        ownerDate = date,
                        relativePath = artifact.outcome.relativePath,
                        state = AgentDataArtifactOutcome.State.UPLOAD_FAILED,
                    )
                } catch (error: Throwable) {
                    if (error.isFatalExportEngineFailure()) throw error
                    daySucceeded = false
                    AgentDataArtifactOutcome(
                        ownerDate = date,
                        relativePath = artifact.outcome.relativePath,
                        state = AgentDataArtifactOutcome.State.UPLOAD_FAILED,
                    )
                }
                outcomes += outcome
                when (outcome.state) {
                    AgentDataArtifactOutcome.State.ACCEPTED -> Unit
                    AgentDataArtifactOutcome.State.REJECTED -> failures += FailedDateDetail(
                        date = date,
                        reason = ExportFailureReason.API_REJECTED,
                        errorDetails = outcome.rejectionCode,
                    )
                    AgentDataArtifactOutcome.State.UPLOAD_FAILED -> failures += FailedDateDetail(
                        date = date,
                        reason = ExportFailureReason.NETWORK_ERROR,
                    )
                }
            }
            if (daySucceeded) successCount += 1
        }

        return ExportResult(
            successCount = successCount,
            totalCount = normalizedDates.size,
            failedDateDetails = failures,
            target = ExportTarget.AGENT_DATA_GATEWAY,
            httpStatusCode = lastStatusCode,
            agentDataOutcomes = outcomes.toList(),
        )
    }

    /** Render-only preview mirroring the runner's artifact pipeline; never contacts the gateway. */
    suspend fun previewDates(
        dates: List<LocalDate>,
        settings: ExportSettings,
        maxPreviewDays: Int = ExportOrchestrator.MAX_PREVIEW_DAYS,
        onProgress: ((current: Int, total: Int, dateString: String) -> Unit)? = null,
    ): ExportPreview {
        val normalizedDates = dates.distinct().sortedDescending()
        val previewCandidates = normalizedDates.take(ExportOrchestrator.MAX_PREVIEW_FETCH_ATTEMPTS)
        if (previewCandidates.isEmpty()) {
            return ExportPreview(0, 0, false, emptyList())
        }
        val days = mutableListOf<ExportPreviewDay>()
        var attemptedDateCount = 0
        for (date in previewCandidates) {
            if (days.count { it.hasOutput } >= maxPreviewDays) break
            coroutineContext.ensureActive()
            attemptedDateCount++
            onProgress?.invoke(attemptedDateCount, previewCandidates.size, date.toString())

            val previewDay = if (captureSource.isBeforeFirstUnlock()) {
                ExportPreviewDay(date = date, failureReason = ExportFailureReason.DEVICE_LOCKED)
            } else {
                try {
                    val data = captureSource.capture(date, settings)
                    if (!data.hasAnyData) {
                        ExportPreviewDay(date = date, failureReason = ExportFailureReason.NO_HEALTH_DATA)
                    } else {
                        val artifacts = renderDailyJsonArtifacts(data, settings)
                        if (artifacts.isEmpty()) {
                            ExportPreviewDay(
                                date = date,
                                failureReason = ExportFailureReason.GATEWAY_FORMAT_UNSUPPORTED,
                            )
                        } else {
                            ExportPreviewDay(
                                date = date,
                                files = artifacts.map { artifact ->
                                    ExportPreviewFile(
                                        format = ExportFormat.JSON,
                                        relativePath = artifact.outcome.relativePath,
                                        byteCount = artifact.bytes.size,
                                        content = artifact.bytes.decodeToString(),
                                    )
                                },
                            )
                        }
                    }
                } catch (error: CancellationException) {
                    throw error
                } catch (error: SecurityException) {
                    ExportPreviewDay(date = date, failureReason = classifySecurityException(error))
                } catch (_: Exception) {
                    ExportPreviewDay(date = date, failureReason = ExportFailureReason.UNKNOWN)
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

    /**
     * Renders the per-day JSON artifact(s) the folder destination would write, using the same
     * planner and the same legacy fallback. Only the protocol-uploadable daily health-data
     * JSON artifact is returned; other selected formats remain folder-destination output.
     */
    private suspend fun renderDailyJsonArtifacts(
        data: HealthData,
        settings: ExportSettings,
    ): List<AgentDataPreparedArtifact> {
        val ownerDate = data.date
        return when (val selection = dailyAggregatePlanner.plan(data, settings)) {
            LocalDailyAggregatePlanningResult.Legacy ->
                legacyDailyJsonArtifact(data, settings, ownerDate)?.let { listOf(it) }.orEmpty()
            is LocalDailyAggregatePlanningResult.Failed -> emptyList()
            is LocalDailyAggregatePlanningResult.Planned ->
                selection.plan.items.asSequence()
                    .zip(selection.formats.asSequence())
                    .filter { (_, format) -> format == ExportFormat.JSON }
                    .map { (item, _) ->
                        AgentDataPreparedArtifact(
                            manifest = AgentDataIngestManifestBuilder.dailyHealthData(
                                ownerDate = ownerDate,
                                artifactBytes = item.content,
                            ),
                            bytes = item.content,
                            outcome = AgentDataArtifactOutcome(
                                ownerDate = ownerDate,
                                relativePath = item.relativePath,
                                state = AgentDataArtifactOutcome.State.ACCEPTED,
                            ),
                        )
                    }
                    .toList()
        }
    }

    /** Legacy-engine fallback mirroring the folder destination's per-format aggregate file. */
    private fun legacyDailyJsonArtifact(
        data: HealthData,
        settings: ExportSettings,
        ownerDate: LocalDate,
    ): AgentDataPreparedArtifact? {
        if (ExportFormat.JSON !in settings.selectedExportFormats) return null
        val bytes = jsonExporter.export(
            data = data,
            customization = settings.formatCustomization,
            includeGranularData = settings.includeGranularData,
        ).encodeToByteArray()
        val relativePath = settings.aggregateRelativePath(ownerDate, ExportFormat.JSON)
        return AgentDataPreparedArtifact(
            manifest = AgentDataIngestManifestBuilder.dailyHealthData(
                ownerDate = ownerDate,
                artifactBytes = bytes,
            ),
            bytes = bytes,
            outcome = AgentDataArtifactOutcome(
                ownerDate = ownerDate,
                relativePath = relativePath,
                state = AgentDataArtifactOutcome.State.ACCEPTED,
            ),
        )
    }

    private fun configurationFailure(
        dates: List<LocalDate>,
        reason: ExportFailureReason,
    ): ExportResult = ExportResult(
        successCount = 0,
        totalCount = dates.size,
        failedDateDetails = dates.map { FailedDateDetail(it, reason) },
        target = ExportTarget.AGENT_DATA_GATEWAY,
    )

    private fun cancelledResult(
        dates: List<LocalDate>,
        outcomes: List<AgentDataArtifactOutcome>,
        successCount: Int = 0,
        failures: List<FailedDateDetail> = emptyList(),
    ): ExportResult = ExportResult(
        successCount = successCount,
        totalCount = dates.size,
        failedDateDetails = failures,
        wasCancelled = true,
        target = ExportTarget.AGENT_DATA_GATEWAY,
        remainingDates = dates.toSet(),
        agentDataOutcomes = outcomes.toList(),
    )

    private fun classifySecurityException(error: SecurityException): ExportFailureReason {
        val message = error.message.orEmpty()
        return when {
            message.contains("rate limit", ignoreCase = true) ||
                message.contains("too many requests", ignoreCase = true) ||
                message.contains("quota", ignoreCase = true) -> ExportFailureReason.RATE_LIMITED
            message.contains("background", ignoreCase = true) ->
                ExportFailureReason.BACKGROUND_PERMISSION_DENIED
            message.contains("permission", ignoreCase = true) ||
                message.contains("denied", ignoreCase = true) ||
                message.contains("access", ignoreCase = true) -> ExportFailureReason.ACCESS_DENIED
            else -> ExportFailureReason.DEVICE_LOCKED
        }
    }

    private fun classifyException(error: Exception): ExportFailureReason = when {
        error.isHealthConnectRateLimit() || error.isLikelyHealthConnectRateLimit() ->
            ExportFailureReason.RATE_LIMITED
        error.message.orEmpty().contains("Health Connect", ignoreCase = true) ->
            ExportFailureReason.HEALTH_CONNECT_ERROR
        else -> ExportFailureReason.UNKNOWN
    }
}
