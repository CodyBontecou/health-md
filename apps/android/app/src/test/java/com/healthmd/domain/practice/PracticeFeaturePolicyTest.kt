package com.healthmd.domain.practice

import com.google.common.truth.Truth.assertThat
import org.junit.Test

class PracticeFeaturePolicyTest {
    @Test
    fun currentProductionPolicyMatchesCompiledVariantAndRemainsDisabled() {
        val expectedCompiledIn =
            System.getProperty("healthmd.practice.expectedCompiledIn")
                ?.toBooleanStrictOrNull()
                ?: false
        val current = PracticeFeaturePolicy.current()

        assertThat(current.compiledIn).isEqualTo(expectedCompiledIn)
        assertThat(current.isEnabled).isFalse()
    }

    @Test
    fun missingUnknownAndPartialGateInputsFailClosed() {
        val inputs = listOf(
            null to null,
            "included" to null,
            null to PracticeFeaturePolicy.QUALIFICATION_VERSION,
            "true" to PracticeFeaturePolicy.QUALIFICATION_VERSION,
            "included" to "approved",
            "INCLUDED" to PracticeFeaturePolicy.QUALIFICATION_VERSION,
        )

        inputs.forEach { (compiled, qualification) ->
            assertThat(
                PracticeFeaturePolicy.resolve(compiled, qualification).isEnabled,
            ).isFalse()
        }
    }

    @Test
    fun bothExactGatesAreRequired() {
        assertThat(
            PracticeFeaturePolicy.resolve(
                compiledInValue = "included",
                qualificationValue = PracticeFeaturePolicy.QUALIFICATION_VERSION,
            ).isEnabled,
        ).isTrue()
    }
}
