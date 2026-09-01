package com.healthmd.data.attribution

import com.google.common.truth.Truth.assertThat
import org.junit.Test
import java.net.URLEncoder
import java.nio.charset.StandardCharsets

class CampaignReferrerParserTest {
    private val parser = CampaignReferrerParser()

    @Test
    fun parsesValidYoutubeCsvCampaign() {
        val result = parser.parse(
            rawReferrer = validReferrer("yt_csv_001", "yt", "csv"),
            referrerClickTimestampSeconds = 1_234_567_890L,
            installBeginTimestampSeconds = 1_234_567_900L,
        ) as CampaignReferrerParseResult.Valid

        assertThat(result.attribution).isEqualTo(
            CampaignAttribution(
                campaignToken = "yt_csv_001",
                source = "yt",
                medium = "campaign_shortlink",
                contentAngle = "csv",
                referrerClickTimestampSeconds = 1_234_567_890L,
                installBeginTimestampSeconds = 1_234_567_900L,
            )
        )
    }

    @Test
    fun parsesValidPrivacyAndObsidianCampaigns() {
        val privacy = parser.parse(
            validReferrer("yt_privacy_002", "yt", "privacy")
        ) as CampaignReferrerParseResult.Valid
        val obsidian = parser.parse(
            validReferrer("yt_obsidian_003", "yt", "obsidian")
        ) as CampaignReferrerParseResult.Valid

        assertThat(privacy.attribution.contentAngle).isEqualTo("privacy")
        assertThat(obsidian.attribution.contentAngle).isEqualTo("obsidian")
    }

    @Test
    fun parsesFullyUrlEncodedReferrer() {
        val encoded = URLEncoder.encode(
            validReferrer("yt_csv_001", "yt", "csv"),
            StandardCharsets.UTF_8.name(),
        )

        val result = parser.parse(encoded) as CampaignReferrerParseResult.Valid

        assertThat(result.attribution.campaignToken).isEqualTo("yt_csv_001")
    }

    @Test
    fun rejectsMissingFields() {
        val result = parser.parse(
            "utm_source=yt&utm_medium=campaign_shortlink&utm_campaign=yt_csv_001"
        ) as CampaignReferrerParseResult.Invalid

        assertThat(result.reason).isEqualTo(CampaignReferrerInvalidReason.MISSING_FIELDS)
    }

    @Test
    fun rejectsWrongMedium() {
        val result = parser.parse(
            "utm_source=yt&utm_medium=cpc&utm_campaign=yt_csv_001&utm_content=csv"
        ) as CampaignReferrerParseResult.Invalid

        assertThat(result.reason).isEqualTo(CampaignReferrerInvalidReason.INVALID_MEDIUM)
    }

    @Test
    fun rejectsCampaignSourceMismatch() {
        val result = parser.parse(
            validReferrer("ig_csv_001", "yt", "csv")
        ) as CampaignReferrerParseResult.Invalid

        assertThat(result.reason).isEqualTo(CampaignReferrerInvalidReason.SOURCE_MISMATCH)
    }

    @Test
    fun rejectsCampaignAngleMismatch() {
        val result = parser.parse(
            validReferrer("yt_privacy_001", "yt", "csv")
        ) as CampaignReferrerParseResult.Invalid

        assertThat(result.reason).isEqualTo(CampaignReferrerInvalidReason.CONTENT_ANGLE_MISMATCH)
    }

    @Test
    fun rejectsMalformedAndOversizedReferrers() {
        val malformed = parser.parse(
            "utm_source=yt&utm_medium=campaign_shortlink&utm_campaign=yt_csv_001&utm_content=%ZZ"
        ) as CampaignReferrerParseResult.Invalid
        val oversized = parser.parse("x".repeat(CampaignReferrerParser.MAX_RAW_REFERRER_LENGTH + 1))
            as CampaignReferrerParseResult.Invalid
        val oversizedAngle = parser.parse(
            validReferrer(
                campaign = "yt_${"a".repeat(33)}_001",
                source = "yt",
                content = "a".repeat(33),
            )
        ) as CampaignReferrerParseResult.Invalid

        assertThat(malformed.reason).isEqualTo(CampaignReferrerInvalidReason.MALFORMED)
        assertThat(oversized.reason).isEqualTo(CampaignReferrerInvalidReason.OVERSIZED)
        assertThat(oversizedAngle.reason).isEqualTo(CampaignReferrerInvalidReason.OVERSIZED)
    }

    @Test
    fun rejectsUnexpectedAndDuplicateFields() {
        val unexpected = parser.parse(
            validReferrer("yt_csv_001", "yt", "csv") + "&gclid=secret"
        ) as CampaignReferrerParseResult.Invalid
        val duplicate = parser.parse(
            validReferrer("yt_csv_001", "yt", "csv") + "&utm_source=yt"
        ) as CampaignReferrerParseResult.Invalid

        assertThat(unexpected.reason).isEqualTo(CampaignReferrerInvalidReason.UNEXPECTED_FIELD)
        assertThat(duplicate.reason).isEqualTo(CampaignReferrerInvalidReason.DUPLICATE_FIELD)
    }

    @Test
    fun recognizesEmptyAndKnownOrganicInstalls() {
        assertThat(parser.parse("")).isEqualTo(CampaignReferrerParseResult.Organic)
        assertThat(parser.parse("utm_source=google-play&utm_medium=organic"))
            .isEqualTo(CampaignReferrerParseResult.Organic)
    }

    private fun validReferrer(campaign: String, source: String, content: String): String =
        "utm_source=$source&utm_medium=campaign_shortlink" +
            "&utm_campaign=$campaign&utm_content=$content"
}
