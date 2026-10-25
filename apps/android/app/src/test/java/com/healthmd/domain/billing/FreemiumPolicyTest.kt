package com.healthmd.domain.billing

import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.time.LocalDate
import java.time.ZoneOffset

class FreemiumPolicyTest {

    @Test
    fun remainingExportsUsesFiveExportLimit() {
        assertThat(FreemiumPolicy.remainingExports(0)).isEqualTo(5)
        assertThat(FreemiumPolicy.remainingExports(1)).isEqualTo(4)
        assertThat(FreemiumPolicy.remainingExports(10)).isEqualTo(0)
        assertThat(FreemiumPolicy.remainingExports(11)).isEqualTo(0)
    }

    @Test
    fun canExportAllowsUnlockedOrUsersWithRemainingQuota() {
        assertThat(FreemiumPolicy.canExport(isUnlocked = false, freeExportsUsed = 4)).isTrue()
        assertThat(FreemiumPolicy.canExport(isUnlocked = false, freeExportsUsed = 10)).isFalse()
        assertThat(FreemiumPolicy.canExport(isUnlocked = true, freeExportsUsed = 10)).isTrue()
    }

    @Test
    fun legacyThreeExportRemainingMigratesToUsedCount() {
        assertThat(FreemiumPolicy.usedCountFromLegacyRemaining(3)).isEqualTo(0)
        assertThat(FreemiumPolicy.usedCountFromLegacyRemaining(2)).isEqualTo(1)
        assertThat(FreemiumPolicy.usedCountFromLegacyRemaining(0)).isEqualTo(3)
        assertThat(FreemiumPolicy.remainingExports(
            FreemiumPolicy.usedCountFromLegacyRemaining(0)
        )).isEqualTo(2)
    }

    @Test
    fun guidanceOnlyFollowsFirstAndThirdFreeExports() {
        assertThat(FreemiumPolicy.guidanceMilestone(1, false)).isEqualTo(1)
        assertThat(FreemiumPolicy.guidanceMilestone(3, false)).isEqualTo(3)
        for (used in listOf(0, 2, 4, 5, 7, 10)) {
            assertThat(FreemiumPolicy.guidanceMilestone(used, false)).isNull()
        }
        assertThat(FreemiumPolicy.guidanceMilestone(1, true)).isNull()
        assertThat(FreemiumPolicy.guidanceMilestone(3, true)).isNull()
    }

    @Test
    fun previousTenActionUsageDoesNotReceiveAFreshAllowance() {
        for (used in 5..10) {
            assertThat(FreemiumPolicy.remainingExports(used)).isEqualTo(0)
            assertThat(FreemiumPolicy.canExport(false, used)).isFalse()
            assertThat(FreemiumPolicy.canExport(true, used)).isTrue()
        }
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
