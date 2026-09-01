package com.healthmd.data.attribution

import kotlinx.serialization.Serializable

/** Sanitized campaign metadata. Raw Play Install Referrer values never enter this model. */
@Serializable
data class CampaignAttribution(
    val campaignToken: String,
    val source: String,
    val medium: String,
    val contentAngle: String,
    val referrerClickTimestampSeconds: Long? = null,
    val installBeginTimestampSeconds: Long? = null,
)

/** The complete, allowlisted first-party ingestion payload. */
@Serializable
data class CampaignInstallEvent(
    val schemaVersion: Int = SCHEMA_VERSION,
    val eventId: String,
    val installId: String,
    val eventName: String = EVENT_NAME,
    val occurredAt: String,
    val platform: String = PLATFORM,
    val appVersion: String,
    val buildNumber: String,
    val campaignToken: String,
    val source: String,
    val medium: String,
    val contentAngle: String,
    val referrerClickTimestampSeconds: Long? = null,
    val installBeginTimestampSeconds: Long? = null,
) {
    companion object {
        const val SCHEMA_VERSION = 1
        const val EVENT_NAME = "campaign_install_attributed"
        const val PLATFORM = "android"
    }
}

@Serializable
enum class CampaignAttributionProcessingState {
    DISCOVERY_PENDING,
    PENDING_DELIVERY,
    DELIVERED,
    TERMINAL_NO_CAMPAIGN,
    TERMINAL_REJECTED,
}

data class CampaignAttributionSnapshot(
    val installId: String?,
    val processingState: CampaignAttributionProcessingState,
    val event: CampaignInstallEvent?,
    val deliverySucceeded: Boolean,
)
