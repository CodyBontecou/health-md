package com.healthmd.domain.billing

import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneOffset

class FreemiumPolicyTest {

    @Test
    fun remainingExportsUsesThreeExportLimit() {
        assertThat(FreemiumPolicy.remainingExports(0)).isEqualTo(3)
        assertThat(FreemiumPolicy.remainingExports(1)).isEqualTo(2)
        assertThat(FreemiumPolicy.remainingExports(3)).isEqualTo(0)
        assertThat(FreemiumPolicy.remainingExports(4)).isEqualTo(0)
    }

    @Test
    fun canExportAllowsUnlockedOrUsersWithRemainingQuota() {
        assertThat(FreemiumPolicy.canExport(isUnlocked = false, freeExportsUsed = 0)).isTrue()
        assertThat(FreemiumPolicy.canExport(isUnlocked = false, freeExportsUsed = 3)).isFalse()
        assertThat(FreemiumPolicy.canExport(isUnlocked = true, freeExportsUsed = 3)).isTrue()
    }

    @Test
    fun legacyRemainingMigratesToUsedCount() {
        assertThat(FreemiumPolicy.usedCountFromLegacyRemaining(3)).isEqualTo(0)
        assertThat(FreemiumPolicy.usedCountFromLegacyRemaining(2)).isEqualTo(1)
        assertThat(FreemiumPolicy.usedCountFromLegacyRemaining(0)).isEqualTo(3)
    }

    @Test
    fun legacyUnlockCutoffIsStrict() {
        val cutoffMillis = FreemiumPolicy.grandfatherCutoffDate
            .atStartOfDay()
            .toInstant(ZoneOffset.UTC)
            .toEpochMilli()
        val april14Millis = LocalDate.of(2026, 4, 14)
            .atStartOfDay()
            .toInstant(ZoneOffset.UTC)
            .toEpochMilli()

        assertThat(FreemiumPolicy.isLegacyUnlock(april14Millis)).isTrue()
        assertThat(FreemiumPolicy.isLegacyUnlock(cutoffMillis - 1)).isTrue()
        assertThat(FreemiumPolicy.isLegacyUnlock(cutoffMillis)).isFalse()
    }
}
