package com.healthmd.direct

import com.google.common.truth.Truth.assertThat
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Test

class DistributionDirectRawRequestPolicyTest {
    private val policy = DistributionDirectRawRequestPolicy()

    @Test
    fun fitbitRequiresAnExplicitRangeOfAtMost366Days() {
        val allAvailable = buildJsonObject { put("type", "all_available") }
        val tooLarge = exactRange("2024-01-01", "2025-01-01")
        val bounded = exactRange("2024-01-01", "2024-12-31")

        assertThat(policy.validationError("fitbit", allAvailable)).isNotNull()
        assertThat(policy.validationError("fitbit", tooLarge)).isNotNull()
        assertThat(policy.validationError("fitbit", bounded)).isNull()
    }

    @Test
    fun otherProvidersHaveNoFitbitSpecificLimit() {
        assertThat(
            policy.validationError(
                "health_connect",
                buildJsonObject { put("type", "all_available") },
            ),
        ).isNull()
    }

    private fun exactRange(start: String, end: String) = buildJsonObject {
        put("type", "exact")
        put("start_date", start)
        put("end_date", end)
    }
}
