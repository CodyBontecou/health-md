package com.healthmd.presentation

import android.content.Intent
import android.net.Uri
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class CloudRepairLinkTest {
    @Test fun acceptsOnlyStaticLinkFromViewIntent() {
        assertThat(CloudRepairLink.matches(Intent(Intent.ACTION_VIEW, Uri.parse(CloudRepairLink.URI)))).isTrue()
        assertThat(CloudRepairLink.matches(Intent(Intent.ACTION_SEND, Uri.parse(CloudRepairLink.URI)))).isFalse()
        assertThat(CloudRepairLink.matches(null)).isFalse()
        listOf(
            "HEALTHMD://cloud/requests", "healthmd://Cloud/requests",
            "healthmd://cloud/requests/", "healthmd://cloud/%72equests",
            "healthmd://cloud/requests?date=2026-04-01",
            "healthmd://cloud/requests#token", "healthmd://user@cloud/requests",
            "healthmd://cloud:443/requests", "https://account.healthmd.app/repair",
            " healthmd://cloud/requests", "healthmd://cloud/requests\n",
        ).forEach { raw ->
            assertThat(CloudRepairLink.matches(Intent(Intent.ACTION_VIEW, Uri.parse(raw)))).isFalse()
        }
    }
}
