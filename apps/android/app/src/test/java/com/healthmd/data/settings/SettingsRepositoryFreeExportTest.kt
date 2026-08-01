package com.healthmd.data.settings

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.billing.FreemiumPolicy
import org.junit.Test

class SettingsRepositoryFreeExportTest {

    @Test
    fun freshInstallStartsWithAllFreeExports() {
        val used = resolveFreeExportsUsed(currentUsed = null, legacyRemaining = null)

        assertThat(used).isEqualTo(0)
        assertThat(FreemiumPolicy.remainingExports(used))
            .isEqualTo(FreemiumPolicy.FREE_EXPORT_LIMIT)
    }

    @Test
    fun currentUsedCounterTakesPrecedenceAndIsSanitized() {
        assertThat(resolveFreeExportsUsed(currentUsed = 4, legacyRemaining = 0)).isEqualTo(4)
        assertThat(resolveFreeExportsUsed(currentUsed = -1, legacyRemaining = 0)).isEqualTo(0)
        assertThat(resolveFreeExportsUsed(currentUsed = 99, legacyRemaining = 3))
            .isEqualTo(FreemiumPolicy.FREE_EXPORT_LIMIT)
    }

    @Test
    fun exhaustedLegacyThreeExportQuotaReceivesOnlyTheNewAllowance() {
        val used = resolveFreeExportsUsed(currentUsed = null, legacyRemaining = 0)

        assertThat(used).isEqualTo(3)
        assertThat(FreemiumPolicy.remainingExports(used)).isEqualTo(7)
    }
}
