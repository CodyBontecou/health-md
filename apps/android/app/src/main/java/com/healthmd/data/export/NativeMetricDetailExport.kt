package com.healthmd.data.export

import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.rawexport.ExportMode
import com.healthmd.rawexport.RawSnapshotScope
import java.time.LocalDate
import kotlinx.coroutines.CancellationException

/**
 * Native detail is an independently versioned companion snapshot, never extra fields in frozen
 * daily v4/v5 records. Reuse the paginated, explicitly mapped native exporter and its completeness
 * manifest. A failed companion prevents its owning day from being reported as fully exported.
 */
internal suspend fun ExportResult.withNativeMetricDetails(
    dates: List<LocalDate>,
    settings: ExportSettings,
    service: RawSnapshotService?,
    expectedDestinationFingerprint: String? = null,
): ExportResult {
    val selected = settings.metricSelection.effectiveNativeDetailMetricIds
    if (settings.exportMode != ExportMode.COMPATIBILITY || selected.isEmpty() || wasCancelled) return this
    val failed = failedDateDetails.mapTo(mutableSetOf()) { it.date }
    val succeeded = dates.distinct().sorted().filter { it !in failed && it !in remainingDates }
    if (succeeded.isEmpty()) return this
    val detailSettings = settings.copy(
        exportMode = ExportMode.RAW_SNAPSHOT,
        rawSnapshot = settings.rawSnapshot.copy(scope = RawSnapshotScope.SELECTED_RECORD_TYPES),
        metricSelection = settings.metricSelection.copy(enabledMetrics = selected, nativeDetailMetricIds = emptySet()),
    )
    val detailFailures = mutableListOf<FailedDateDetail>()
    var artifacts = artifactCount
    val outcomes = agentDataOutcomes.toMutableList()
    for ((index, date) in succeeded.withIndex()) {
        val detail = try {
            service?.exportRange(date, date, detailSettings, target, expectedDestinationFingerprint)
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            null
        }
        artifacts += detail?.artifactCount ?: 0
        outcomes += detail?.agentDataOutcomes.orEmpty()
        if (detail?.isFullSuccess != true) {
            val unresolved = if (detail?.wasCancelled == true) succeeded.drop(index) else listOf(date)
            detailFailures += unresolved.map {
                FailedDateDetail(it, detail?.primaryFailureReason ?: ExportFailureReason.HEALTH_CONNECT_ERROR,
                    "Native record detail did not complete; daily summaries may already exist.")
            }
            if (detail?.wasCancelled == true) {
                return copy(
                    successCount = (successCount - detailFailures.size).coerceAtLeast(0),
                    failedDateDetails = failedDateDetails + detailFailures,
                    wasCancelled = true,
                    remainingDates = remainingDates + unresolved,
                    artifactCount = artifacts,
                    agentDataOutcomes = outcomes,
                    freshCaptureRetryDates = freshCaptureRetryDates + detailFailures.map { it.date },
                )
            }
        }
    }
    return copy(
        successCount = (successCount - detailFailures.size).coerceAtLeast(0),
        failedDateDetails = failedDateDetails + detailFailures,
        artifactCount = artifacts,
        agentDataOutcomes = outcomes,
        freshCaptureRetryDates = freshCaptureRetryDates + detailFailures.map { it.date },
    )
}
