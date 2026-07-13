package com.healthmd.data.scheduler

import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.PendingScheduledExportRequest
import com.healthmd.domain.model.ScheduleDateWindow
import com.healthmd.domain.model.ExportTarget
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
        val byDestinationAndDate = linkedMapOf<Triple<ExportTarget, LocalDate, String?>, PendingScheduledExportRequest>()

        settings.pendingScheduledExportRequests.forEach { request ->
            val normalized = request.copy(
                firstFailedAtMillis = request.firstFailedAtMillis.coerceAtLeast(0L),
                lastAttemptAtMillis = request.lastAttemptAtMillis.coerceAtLeast(0L),
                attemptCount = request.attemptCount.coerceAtLeast(0),
            )
            val key = Triple(request.exportTarget, request.date, request.destinationFingerprint)
            byDestinationAndDate[key] = combine(byDestinationAndDate[key], normalized) ?: normalized
        }

        settings.pendingScheduledRetryDates.mapNotNull { raw ->
            runCatching { LocalDate.parse(raw) }.getOrNull()
        }.forEach { date ->
            val legacyRequest = PendingScheduledExportRequest(
                date = date,
                exportTarget = ExportTarget.DEVICE_FOLDER,
                firstFailedAtMillis = 0L,
                lastAttemptAtMillis = 0L,
                lastFailureReason = null,
                attemptCount = 0,
            )
            val key = Triple(ExportTarget.DEVICE_FOLDER, date, null)
            byDestinationAndDate[key] = combine(byDestinationAndDate[key], legacyRequest) ?: legacyRequest
        }

        return byDestinationAndDate.values
            .map { request ->
                if (request.firstFailedAtMillis == 0L && request.lastAttemptAtMillis > 0L) {
                    request.copy(firstFailedAtMillis = request.lastAttemptAtMillis)
                } else if (request.lastAttemptAtMillis == 0L && request.firstFailedAtMillis > 0L) {
                    request.copy(lastAttemptAtMillis = request.firstFailedAtMillis)
                } else {
                    request
                }
            }
            .sortedWith(compareBy<PendingScheduledExportRequest> { it.date }.thenBy { it.exportTarget.name })
    }

    fun pendingDates(
        settings: ExportSettings,
        cutoffInclusive: LocalDate = LocalDate.now().minusDays(1),
        target: ExportTarget? = null,
        destinationFingerprint: String? = null,
    ): List<LocalDate> = pendingRequests(settings)
        .filter { target == null || it.exportTarget == target }
        .filter { target != ExportTarget.API_ENDPOINT || it.destinationFingerprint == destinationFingerprint }
        .map { it.date }
        .filter { !it.isAfter(cutoffInclusive) }
        .distinct()
        .sorted()

    fun scheduledRunDates(
        settings: ExportSettings,
        today: LocalDate = LocalDate.now(),
        destinationFingerprint: String? = settings.scheduledExportTarget.destinationFingerprint(settings),
    ): List<LocalDate> {
        val yesterday = today.minusDays(1)
        val datesForThisRun = when (settings.scheduleDateWindow) {
            ScheduleDateWindow.PAST_COMPLETE_DAYS -> {
                val lookbackDays = settings.scheduleLookbackDays.coerceAtLeast(1)
                (lookbackDays - 1 downTo 0).map { yesterday.minusDays(it.toLong()) }
            }
            ScheduleDateWindow.TODAY -> listOf(today)
        }
        return (
            pendingDates(
                settings,
                cutoffInclusive = yesterday,
                target = settings.scheduledExportTarget,
                destinationFingerprint = destinationFingerprint,
            ) +
                datesForThisRun
            ).distinct().sorted()
    }

    fun recordFailedDates(
        settings: ExportSettings,
        dates: List<LocalDate>,
        reason: ExportFailureReason = ExportFailureReason.UNKNOWN,
        nowMillis: Long = System.currentTimeMillis(),
        target: ExportTarget = settings.scheduledExportTarget,
        destinationFingerprint: String? = target.destinationFingerprint(settings),
    ): ExportSettings = applyAttemptResult(
        settings = settings,
        attemptedDates = dates,
        failedDateDetails = dates.distinct().map { FailedDateDetail(it, reason) },
        nowMillis = nowMillis,
        target = target,
        destinationFingerprint = destinationFingerprint,
    )

    fun applyAttemptResult(
        settings: ExportSettings,
        attemptedDates: List<LocalDate>,
        failedDateDetails: List<FailedDateDetail>,
        nowMillis: Long = System.currentTimeMillis(),
        target: ExportTarget = settings.scheduledExportTarget,
        destinationFingerprint: String? = target.destinationFingerprint(settings),
    ): ExportSettings {
        val attempted = attemptedDates.toSet()
        if (attempted.isEmpty()) return settings.withPendingRequests(pendingRequests(settings, nowMillis))

        val existingByKey = pendingRequests(settings, nowMillis).associateBy {
            Triple(it.exportTarget, it.date, it.destinationFingerprint)
        }
        val retained = existingByKey.values
            .filterNot {
                it.exportTarget == target && it.date in attempted &&
                    (target != ExportTarget.API_ENDPOINT || it.destinationFingerprint == destinationFingerprint)
            }
            .toMutableList()
        val failedByDate = failedDateDetails.associateBy { it.date }

        failedByDate.values
            .filter { it.date in attempted }
            .forEach { failure ->
                val existing = existingByKey[Triple(target, failure.date, destinationFingerprint)]
                retained.add(
                    PendingScheduledExportRequest(
                        date = failure.date,
                        exportTarget = target,
                        destinationFingerprint = existing?.destinationFingerprint ?: destinationFingerprint,
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
            .groupBy { Triple(it.exportTarget, it.date, it.destinationFingerprint) }
            .map { (_, sameRequest) -> sameRequest.reduce { acc, request -> combine(acc, request) ?: acc } }
            .sortedWith(compareBy<PendingScheduledExportRequest> { it.date }.thenBy { it.exportTarget.name })

        return copy(
            pendingScheduledRetryDates = normalized
                .filter { it.exportTarget == ExportTarget.DEVICE_FOLDER }
                .map { it.date.toString() },
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
            destinationFingerprint = existing.destinationFingerprint ?: incoming.destinationFingerprint,
        )
    }

    private fun ExportTarget.destinationFingerprint(settings: ExportSettings): String? =
        if (this == ExportTarget.API_ENDPOINT) APIExportEndpoint.fingerprint(settings.apiEndpointUrl) else null
}
