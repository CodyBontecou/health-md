package com.healthmd.domain.billing

import java.time.LocalDate
import java.time.ZoneOffset

/**
 * Shared freemium rules mirrored from the iOS PurchaseManager.
 *
 * A free user gets three export actions. Each successful user-triggered export
 * consumes one action regardless of the number of days/files written. Unlocking
 * the lifetime purchase resets accumulated free usage.
 */
object FreemiumPolicy {
    const val FREE_EXPORT_LIMIT = 3

    /** Android equivalent of iOS' grandfather cutoff date. */
    val grandfatherCutoffDate: LocalDate = LocalDate.of(2026, 4, 26)

    private val grandfatherCutoffMillis: Long = grandfatherCutoffDate
        .atStartOfDay()
        .toInstant(ZoneOffset.UTC)
        .toEpochMilli()

    fun sanitizedUsedCount(count: Int): Int = count.coerceIn(0, FREE_EXPORT_LIMIT)

    fun remainingExports(usedCount: Int): Int =
        (FREE_EXPORT_LIMIT - sanitizedUsedCount(usedCount)).coerceAtLeast(0)

    fun usedCountFromLegacyRemaining(remainingCount: Int): Int =
        sanitizedUsedCount(FREE_EXPORT_LIMIT - remainingCount.coerceIn(0, FREE_EXPORT_LIMIT))

    fun canExport(isUnlocked: Boolean, freeExportsUsed: Int): Boolean =
        isUnlocked || remainingExports(freeExportsUsed) > 0

    fun isLegacyUnlock(firstInstallTimeMillis: Long): Boolean =
        firstInstallTimeMillis < grandfatherCutoffMillis
}
