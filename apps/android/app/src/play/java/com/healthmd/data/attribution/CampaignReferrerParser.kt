package com.healthmd.data.attribution

import java.net.URLDecoder
import java.nio.charset.StandardCharsets
import javax.inject.Inject

sealed interface CampaignReferrerParseResult {
    data class Valid(val attribution: CampaignAttribution) : CampaignReferrerParseResult
    data object Organic : CampaignReferrerParseResult
    data class Invalid(val reason: CampaignReferrerInvalidReason) : CampaignReferrerParseResult
}

enum class CampaignReferrerInvalidReason {
    OVERSIZED,
    MALFORMED,
    MISSING_FIELDS,
    UNEXPECTED_FIELD,
    DUPLICATE_FIELD,
    INVALID_CAMPAIGN_TOKEN,
    INVALID_SOURCE,
    INVALID_MEDIUM,
    INVALID_CONTENT_ANGLE,
    SOURCE_MISMATCH,
    CONTENT_ANGLE_MISMATCH,
}

class CampaignReferrerParser @Inject constructor() {
    fun parse(
        rawReferrer: String,
        referrerClickTimestampSeconds: Long? = null,
        installBeginTimestampSeconds: Long? = null,
    ): CampaignReferrerParseResult {
        if (rawReferrer.isBlank()) return CampaignReferrerParseResult.Organic
        if (rawReferrer.length > MAX_RAW_REFERRER_LENGTH) {
            return CampaignReferrerParseResult.Invalid(CampaignReferrerInvalidReason.OVERSIZED)
        }

        val query = decodeWholeQueryIfNecessary(rawReferrer.trim())
            ?: return CampaignReferrerParseResult.Invalid(CampaignReferrerInvalidReason.MALFORMED)
        if (query.equals("organic", ignoreCase = true)) return CampaignReferrerParseResult.Organic

        val entries = query.removePrefix("?").split('&')
        if (entries.any { it.isBlank() }) {
            return CampaignReferrerParseResult.Invalid(CampaignReferrerInvalidReason.MALFORMED)
        }

        val values = linkedMapOf<String, String>()
        for (entry in entries) {
            val separator = entry.indexOf('=')
            if (separator <= 0) {
                return CampaignReferrerParseResult.Invalid(CampaignReferrerInvalidReason.MALFORMED)
            }
            val key = decodeComponent(entry.substring(0, separator))
                ?: return CampaignReferrerParseResult.Invalid(CampaignReferrerInvalidReason.MALFORMED)
            val value = decodeComponent(entry.substring(separator + 1))
                ?: return CampaignReferrerParseResult.Invalid(CampaignReferrerInvalidReason.MALFORMED)
            if (key !in ALLOWED_FIELDS) {
                return CampaignReferrerParseResult.Invalid(CampaignReferrerInvalidReason.UNEXPECTED_FIELD)
            }
            if (values.put(key, value) != null) {
                return CampaignReferrerParseResult.Invalid(CampaignReferrerInvalidReason.DUPLICATE_FIELD)
            }
        }

        if (isKnownOrganic(values)) return CampaignReferrerParseResult.Organic
        if (values.keys != ALLOWED_FIELDS) {
            return CampaignReferrerParseResult.Invalid(CampaignReferrerInvalidReason.MISSING_FIELDS)
        }

        val source = values.getValue(UTM_SOURCE)
        val medium = values.getValue(UTM_MEDIUM)
        val campaignToken = values.getValue(UTM_CAMPAIGN)
        val contentAngle = values.getValue(UTM_CONTENT)

        if (campaignToken.length > MAX_CAMPAIGN_TOKEN_LENGTH ||
            source.length > MAX_SOURCE_LENGTH ||
            medium.length > MAX_MEDIUM_LENGTH ||
            contentAngle.length > MAX_CONTENT_ANGLE_LENGTH
        ) {
            return CampaignReferrerParseResult.Invalid(CampaignReferrerInvalidReason.OVERSIZED)
        }
        if (!CAMPAIGN_TOKEN_REGEX.matches(campaignToken)) {
            return CampaignReferrerParseResult.Invalid(CampaignReferrerInvalidReason.INVALID_CAMPAIGN_TOKEN)
        }
        if (!SOURCE_REGEX.matches(source)) {
            return CampaignReferrerParseResult.Invalid(CampaignReferrerInvalidReason.INVALID_SOURCE)
        }
        if (medium != REQUIRED_MEDIUM) {
            return CampaignReferrerParseResult.Invalid(CampaignReferrerInvalidReason.INVALID_MEDIUM)
        }
        if (!CONTENT_ANGLE_REGEX.matches(contentAngle)) {
            return CampaignReferrerParseResult.Invalid(CampaignReferrerInvalidReason.INVALID_CONTENT_ANGLE)
        }

        val campaignParts = campaignToken.split('_')
        if (campaignParts[0] != source) {
            return CampaignReferrerParseResult.Invalid(CampaignReferrerInvalidReason.SOURCE_MISMATCH)
        }
        if (campaignParts[1] != contentAngle) {
            return CampaignReferrerParseResult.Invalid(CampaignReferrerInvalidReason.CONTENT_ANGLE_MISMATCH)
        }

        return CampaignReferrerParseResult.Valid(
            CampaignAttribution(
                campaignToken = campaignToken,
                source = source,
                medium = medium,
                contentAngle = contentAngle,
                referrerClickTimestampSeconds = referrerClickTimestampSeconds?.takeIf { it > 0L },
                installBeginTimestampSeconds = installBeginTimestampSeconds?.takeIf { it > 0L },
            )
        )
    }

    private fun decodeWholeQueryIfNecessary(raw: String): String? {
        if ('=' in raw) return raw
        if (!raw.contains("%3D", ignoreCase = true)) return raw
        return decodeComponent(raw)
    }

    private fun decodeComponent(value: String): String? = try {
        URLDecoder.decode(value, StandardCharsets.UTF_8.name())
    } catch (_: IllegalArgumentException) {
        null
    }

    private fun isKnownOrganic(values: Map<String, String>): Boolean =
        values[UTM_MEDIUM].equals("organic", ignoreCase = true) &&
            UTM_CAMPAIGN !in values && UTM_CONTENT !in values

    companion object {
        const val REQUIRED_MEDIUM = "campaign_shortlink"
        const val MAX_RAW_REFERRER_LENGTH = 2_048
        const val MAX_CAMPAIGN_TOKEN_LENGTH = 64
        const val MAX_SOURCE_LENGTH = 4
        const val MAX_MEDIUM_LENGTH = 32
        const val MAX_CONTENT_ANGLE_LENGTH = 32

        private const val UTM_SOURCE = "utm_source"
        private const val UTM_MEDIUM = "utm_medium"
        private const val UTM_CAMPAIGN = "utm_campaign"
        private const val UTM_CONTENT = "utm_content"
        private val ALLOWED_FIELDS = setOf(UTM_SOURCE, UTM_MEDIUM, UTM_CAMPAIGN, UTM_CONTENT)
        private val CAMPAIGN_TOKEN_REGEX = Regex("^[a-z]{1,4}_[a-z0-9]+_[0-9]{3}$")
        private val SOURCE_REGEX = Regex("^[a-z]{1,4}$")
        private val CONTENT_ANGLE_REGEX = Regex("^[a-z0-9]+$")
    }
}
