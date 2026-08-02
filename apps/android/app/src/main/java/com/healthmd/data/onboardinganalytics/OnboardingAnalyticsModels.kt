package com.healthmd.data.onboardinganalytics

import com.healthmd.domain.billing.FreemiumPolicy
import kotlinx.serialization.Serializable

/** The complete allowlist for first-party onboarding analytics event names. */
enum class PricingOnboardingEventName(val wireName: String) {
    STARTED("pricing_onboarding_started"),
    STEP_VIEWED("pricing_onboarding_step_viewed"),
    HEALTH_SKIPPED("pricing_onboarding_health_skipped"),
    FOLDER_SELECTED("pricing_onboarding_folder_selected"),
    FOLDER_SKIPPED("pricing_onboarding_folder_skipped"),
    CONTINUE_FREE_TAPPED("pricing_onboarding_continue_free_tapped"),
    PURCHASE_TAPPED("pricing_onboarding_purchase_tapped"),
    COMPLETED("pricing_onboarding_completed"),
}

enum class OnboardingAnalyticsStep(val wireName: String) {
    WELCOME("welcome"),
    HEALTH_ACCESS("health_access"),
    FOLDER_SETUP("folder_setup"),
    UNLOCK("unlock"),
    READY("ready"),
}

enum class OnboardingAnalyticsProductId(val wireName: String) {
    PREMIUM_LIFETIME("health_md_premium_lifetime"),
}

/**
 * A closed property model prevents callers from attaching health, permission, folder, device,
 * account, price, timestamp, referrer, error, or free-text values.
 */
@Serializable
data class OnboardingAnalyticsProperties(
    val appVersion: String,
    val buildNumber: String,
    val platform: String = PLATFORM,
    val onboardingStep: String,
    val paywallContext: String = PAYWALL_CONTEXT,
    val freeExportsUsed: Int? = null,
    val freeExportsRemaining: Int? = null,
    val productId: String? = null,
) {
    companion object {
        const val PLATFORM = "android"
        const val PAYWALL_CONTEXT = "onboarding"
    }
}

@Serializable
data class OnboardingAnalyticsEvent(
    val eventId: String,
    val eventName: String,
    val properties: OnboardingAnalyticsProperties,
)

@Serializable
data class OnboardingAnalyticsEnvelope(
    val installId: String,
    val events: List<OnboardingAnalyticsEvent>,
)

data class OnboardingAnalyticsAppInfo(
    val appVersion: String,
    val buildNumber: String,
)

fun interface OnboardingAnalyticsUuidGenerator {
    fun randomUuid(): String
}

internal object OnboardingAnalyticsPrivacyValidator {
    private val uuidPattern = Regex(
        "^[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[1-5][0-9a-fA-F]{3}-[89abAB][0-9a-fA-F]{3}-[0-9a-fA-F]{12}$"
    )
    private val appVersionPattern = Regex("^\\d+(?:\\.\\d+){0,3}$")
    private val buildNumberPattern = Regex("^[0-9]{1,12}$")
    private val eventNames = PricingOnboardingEventName.entries.mapTo(hashSetOf()) { it.wireName }
    private val steps = OnboardingAnalyticsStep.entries.mapTo(hashSetOf()) { it.wireName }
    private val productIds = OnboardingAnalyticsProductId.entries.mapTo(hashSetOf()) { it.wireName }

    fun isUuid(value: String): Boolean = uuidPattern.matches(value)

    fun isValid(event: OnboardingAnalyticsEvent): Boolean =
        isUuid(event.eventId) &&
            event.eventName in eventNames &&
            appVersionPattern.matches(event.properties.appVersion) &&
            buildNumberPattern.matches(event.properties.buildNumber) &&
            event.properties.platform == OnboardingAnalyticsProperties.PLATFORM &&
            event.properties.onboardingStep in steps &&
            event.properties.paywallContext == OnboardingAnalyticsProperties.PAYWALL_CONTEXT &&
            validFreeExportCounts(event.properties) &&
            (event.properties.productId == null || event.properties.productId in productIds) &&
            (event.eventName == PricingOnboardingEventName.PURCHASE_TAPPED.wireName ||
                event.properties.productId == null)

    private fun validFreeExportCounts(properties: OnboardingAnalyticsProperties): Boolean {
        val used = properties.freeExportsUsed
        val remaining = properties.freeExportsRemaining
        return (used == null && remaining == null) ||
            (used != null && remaining != null &&
                used in 0..FreemiumPolicy.FREE_EXPORT_LIMIT &&
                remaining in 0..FreemiumPolicy.FREE_EXPORT_LIMIT &&
                used + remaining == FreemiumPolicy.FREE_EXPORT_LIMIT)
    }

    fun isValid(envelope: OnboardingAnalyticsEnvelope): Boolean =
        isUuid(envelope.installId) &&
            envelope.events.isNotEmpty() &&
            envelope.events.size <= DurableOnboardingAnalyticsStore.MAX_QUEUE_SIZE &&
            envelope.events.all(::isValid)
}

class OnboardingAnalyticsEventFactory(
    private val appInfo: OnboardingAnalyticsAppInfo,
    private val uuidGenerator: OnboardingAnalyticsUuidGenerator,
) {
    fun create(
        eventName: PricingOnboardingEventName,
        step: OnboardingAnalyticsStep,
        productId: OnboardingAnalyticsProductId? = null,
        freeExportsUsed: Int? = null,
        freeExportsRemaining: Int? = null,
    ): OnboardingAnalyticsEvent = OnboardingAnalyticsEvent(
        eventId = uuidGenerator.randomUuid(),
        eventName = eventName.wireName,
        properties = OnboardingAnalyticsProperties(
            appVersion = appInfo.appVersion,
            buildNumber = appInfo.buildNumber,
            onboardingStep = step.wireName,
            freeExportsUsed = freeExportsUsed,
            freeExportsRemaining = freeExportsRemaining,
            productId = productId?.wireName,
        ),
    )
}
