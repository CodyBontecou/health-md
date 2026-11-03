package com.healthmd.domain.billing

import java.time.LocalDate
import java.time.ZoneOffset

/**
 * Shared access rules mirrored from the iOS PurchaseManager.
 * Trials are store-backed subscription entitlements, not a local export quota.
 * Historical counters and legacy unlock decisions remain migration-compatible.
 */
object FreemiumPolicy {
    const val FREE_EXPORT_LIMIT = 0
    private const val HISTORICAL_EXPORT_LIMIT = 5
    private const val LEGACY_FREE_EXPORT_LIMIT = 3

    /** Android equivalent of iOS' grandfather cutoff date. */
    val grandfatherCutoffDate: LocalDate = LocalDate.of(2026, 4, 26)

    private val grandfatherCutoffMillis: Long = grandfatherCutoffDate
        .atStartOfDay()
        .toInstant(ZoneOffset.UTC)
        .toEpochMilli()

    /** Only completed first and third free actions offer a next step. Never replay old milestones. */
    fun guidanceMilestone(usedCount: Int, isUnlocked: Boolean): Int? =
        null

    fun sanitizedUsedCount(count: Int): Int = count.coerceIn(0, HISTORICAL_EXPORT_LIMIT)

    fun remainingExports(usedCount: Int): Int =
        (FREE_EXPORT_LIMIT - sanitizedUsedCount(usedCount)).coerceAtLeast(0)

    fun usedCountFromLegacyRemaining(remainingCount: Int): Int =
        sanitizedUsedCount(
            LEGACY_FREE_EXPORT_LIMIT - remainingCount.coerceIn(0, LEGACY_FREE_EXPORT_LIMIT)
        )

    fun canExport(isUnlocked: Boolean, freeExportsUsed: Int): Boolean =
        isUnlocked

    fun isLegacyUnlock(firstInstallTimeMillis: Long): Boolean =
        firstInstallTimeMillis < grandfatherCutoffMillis
}
