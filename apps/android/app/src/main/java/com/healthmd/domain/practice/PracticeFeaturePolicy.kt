package com.healthmd.domain.practice

import com.healthmd.BuildConfig

/**
 * Fail-closed rollout boundary for additive Health.md Practice functionality.
 *
 * Packaging future Practice code is necessary but never sufficient. A separately governed
 * qualification attestation must match [QUALIFICATION_VERSION]. No production attestation is
 * supplied today, so the existing local-first, account-free application remains unchanged.
 */
data class PracticeFeaturePolicy(
    val compiledIn: Boolean,
    val qualificationAttested: Boolean,
) {
    val isEnabled: Boolean = compiledIn && qualificationAttested

    companion object {
        const val QUALIFICATION_VERSION = "practice-v1-qualified"

        fun current(): PracticeFeaturePolicy = PracticeFeaturePolicy(
            compiledIn = BuildConfig.PRACTICE_COMPILED_IN,
            qualificationAttested = qualificationIsValid(null),
        )

        fun resolve(
            compiledInValue: String?,
            qualificationValue: String?,
        ): PracticeFeaturePolicy = PracticeFeaturePolicy(
            compiledIn = compiledInValue == "included",
            qualificationAttested = qualificationIsValid(qualificationValue),
        )

        private fun qualificationIsValid(value: String?): Boolean =
            value == QUALIFICATION_VERSION
    }
}
