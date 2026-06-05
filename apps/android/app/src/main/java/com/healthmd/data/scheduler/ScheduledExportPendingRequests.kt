package com.healthmd.data.scheduler

import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.PendingScheduledExportRequest
import java.time.LocalDate

/**
 * Compatibility helpers for scheduled-export retry state.
 *
 * Android originally persisted pending scheduled work as a date-only string list
 * ([ExportSettings.pendingScheduledRetryDates]). The explicit request list keeps the exact date
 * plus failure metadata so app-open/notification recovery can deterministically retry and clear
 * only the dates that were successfully recovered.
 */
object ScheduledExportPendingRequests {

    fun pendingRequests(
        settings: ExportSettings,
        nowMillis: Long = System.currentTimeMillis(),
    ): List<PendingScheduledExportRequest> {
        val byDate = linkedMapOf<LocalDate, PendingScheduledExportRequest>()

        settings.pendingScheduledExportRequests.forEach { request ->
            val normalized = request.copy(
                firstFailedAtMillis = request.firstFailedAtMillis.coerceAtLeast(0L),
                lastAttemptAtMillis = request.lastAttemptAtMillis.coerceAtLeast(0L),
                attemptCount = request.attemptCount.coerceAtLeast(0),
            )
            byDate[request.date] = combine(byDate[request.date], normalized) ?: normalized
        }

        settings.pendingScheduledRetryDates.mapNotNull { raw ->
            runCatching { LocalDate.parse(raw) }.getOrNull()
        }.forEach { date ->
            val legacyRequest = PendingScheduledExportRequest(
                date = date,
                firstFailedAtMillis = 0L,
                lastAttemptAtMillis = 0L,
                lastFailureReason = null,
                attemptCount = 0,
            )
            byDate[date] = combine(byDate[date], legacyRequest) ?: legacyRequest
        }

        return byDate.values
            .map { request ->
                if (request.firstFailedAtMillis == 0L && request.lastAttemptAtMillis > 0L) {
                    request.copy(firstFailedAtMillis = request.lastAttemptAtMillis)
                } else if (request.lastAttemptAtMillis == 0L && request.firstFailedAtMillis > 0L) {
                    request.copy(lastAttemptAtMillis = request.firstFailedAtMillis)
                } else {
                    request
                }
            }
            .sortedBy { it.date }
    }

    fun pendingDates(
        settings: ExportSettings,
        cutoffInclusive: LocalDate = LocalDate.now().minusDays(1),
    ): List<LocalDate> = pendingRequests(settings)
        .map { it.date }
        .filter { !it.isAfter(cutoffInclusive) }
        .distinct()
        .sorted()

    fun scheduledRunDates(
        settings: ExportSettings,
        today: LocalDate = LocalDate.now(),
    ): List<LocalDate> {
        val yesterday = today.minusDays(1)
        val lookbackDays = settings.scheduleLookbackDays.coerceAtLeast(1)
        val lookbackDates = (lookbackDays - 1 downTo 0).map { yesterday.minusDays(it.toLong()) }
        return (pendingDates(settings, yesterday) + lookbackDates).distinct().sorted()
    }

    fun recordFailedDates(
        settings: ExportSettings,
        dates: List<LocalDate>,
        reason: ExportFailureReason = ExportFailureReason.UNKNOWN,
        nowMillis: Long = System.currentTimeMillis(),
    ): ExportSettings = applyAttemptResult(
        settings = settings,
        attemptedDates = dates,
        failedDateDetails = dates.distinct().map { FailedDateDetail(it, reason) },
        nowMillis = nowMillis,
    )

    fun applyAttemptResult(
        settings: ExportSettings,
        attemptedDates: List<LocalDate>,
        failedDateDetails: List<FailedDateDetail>,
        nowMillis: Long = System.currentTimeMillis(),
    ): ExportSettings {
        val attempted = attemptedDates.toSet()
        if (attempted.isEmpty()) return settings.withPendingRequests(pendingRequests(settings, nowMillis))

        val existingByDate = pendingRequests(settings, nowMillis).associateBy { it.date }
        val retained = existingByDate.values.filterNot { it.date in attempted }.toMutableList()
        val failedByDate = failedDateDetails.associateBy { it.date }

        failedByDate.values
            .filter { it.date in attempted }
            .forEach { failure ->
                val existing = existingByDate[failure.date]
                retained.add(
                    PendingScheduledExportRequest(
                        date = failure.date,
                        firstFailedAtMillis = existing?.firstFailedAtMillis?.takeIf { it > 0L } ?: nowMillis,
                        lastAttemptAtMillis = nowMillis,
                        lastFailureReason = failure.reason,
                        attemptCount = (existing?.attemptCount ?: 0) + 1,
                    )
                )
            }

        return settings.withPendingRequests(retained.sortedBy { it.date })
    }

    fun clearDates(
        settings: ExportSettings,
        dates: List<LocalDate>,
    ): ExportSettings {
        val dateSet = dates.toSet()
        return settings.withPendingRequests(pendingRequests(settings).filterNot { it.date in dateSet })
    }

    private fun ExportSettings.withPendingRequests(
        requests: List<PendingScheduledExportRequest>,
    ): ExportSettings {
        val normalized = requests
            .groupBy { it.date }
            .map { (_, sameDate) -> sameDate.reduce { acc, request -> combine(acc, request) ?: acc } }
            .sortedBy { it.date }

        return copy(
            pendingScheduledRetryDates = normalized.map { it.date.toString() },
            pendingScheduledExportRequests = normalized,
        )
    }

    private fun combine(
        existing: PendingScheduledExportRequest?,
        incoming: PendingScheduledExportRequest,
    ): PendingScheduledExportRequest? {
        if (existing == null) return incoming

        val firstFailedAt = listOf(existing.firstFailedAtMillis, incoming.firstFailedAtMillis)
            .filter { it > 0L }
            .minOrNull() ?: 0L
        val mostRecent = listOf(existing, incoming).maxBy { it.lastAttemptAtMillis }

        return existing.copy(
            firstFailedAtMillis = firstFailedAt,
            lastAttemptAtMillis = maxOf(existing.lastAttemptAtMillis, incoming.lastAttemptAtMillis),
            lastFailureReason = mostRecent.lastFailureReason ?: existing.lastFailureReason ?: incoming.lastFailureReason,
            attemptCount = maxOf(existing.attemptCount, incoming.attemptCount),
        )
    }
}
