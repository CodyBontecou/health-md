package com.healthmd.domain.distribution

enum class DistributionChannel(val wireName: String) {
    GOOGLE_PLAY("play"),
    FDROID("fdroid"),
}

/**
 * Immutable product policy supplied by the active distribution flavor.
 *
 * Common product code consumes capabilities instead of inspecting BuildConfig, installer names,
 * package signatures, or Google-specific types.
 */
data class DistributionPolicy(
    val channel: DistributionChannel,
    val purchasesAvailable: Boolean,
    val fullAccessIncluded: Boolean,
    val reviewPromptAvailable: Boolean,
    val campaignAttributionEnabled: Boolean,
    val onboardingAnalyticsEnabled: Boolean,
    val wearSyncAvailable: Boolean,
    val directCloudProvidersAvailable: Boolean,
) {
    companion object {
        fun play(): DistributionPolicy = DistributionPolicy(
            channel = DistributionChannel.GOOGLE_PLAY,
            purchasesAvailable = true,
            fullAccessIncluded = false,
            reviewPromptAvailable = true,
            campaignAttributionEnabled = true,
            onboardingAnalyticsEnabled = true,
            wearSyncAvailable = true,
            directCloudProvidersAvailable = true,
        )

        fun fdroid(): DistributionPolicy = DistributionPolicy(
            channel = DistributionChannel.FDROID,
            purchasesAvailable = false,
            fullAccessIncluded = true,
            reviewPromptAvailable = false,
            campaignAttributionEnabled = false,
            onboardingAnalyticsEnabled = false,
            wearSyncAvailable = false,
            directCloudProvidersAvailable = false,
        )
    }
}
