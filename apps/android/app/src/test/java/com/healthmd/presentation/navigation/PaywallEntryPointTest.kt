package com.healthmd.presentation.navigation

import com.google.common.truth.Truth.assertThat
import com.healthmd.R
import org.junit.Test

class PaywallEntryPointTest {

    @Test
    fun `entry points use unique routes`() {
        assertThat(PaywallEntryPoint.entries.map { it.route }).containsNoDuplicates()
    }

    @Test
    fun `entry points select context specific subtitles`() {
        assertThat(PaywallEntryPoint.UPGRADE.subtitleResource)
            .isEqualTo(R.string.settings_upgrade_subtitle)
        assertThat(PaywallEntryPoint.EXPORT_LIMIT.subtitleResource)
            .isEqualTo(R.string.paywall_subtitle)
        assertThat(PaywallEntryPoint.SCHEDULE.subtitleResource)
            .isEqualTo(R.string.schedule_unlock_required_body)
    }
}
