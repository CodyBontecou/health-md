package com.healthmd.data.onboardinganalytics

import com.google.common.truth.Truth.assertThat
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Test

class OnboardingAnalyticsPayloadTest {
    @Test
    fun serializationContainsOnlyEnvelopeEventAndPropertyAllowlists() {
        val event = OnboardingAnalyticsEventFactory(
            appInfo = OnboardingAnalyticsAppInfo("1.5.4", "25"),
            uuidGenerator = OnboardingAnalyticsUuidGenerator {
                "22222222-2222-4222-8222-222222222222"
            },
        ).create(
            eventName = PricingOnboardingEventName.PURCHASE_TAPPED,
            step = OnboardingAnalyticsStep.UNLOCK,
            productId = OnboardingAnalyticsProductId.PREMIUM_LIFETIME,
            freeExportsUsed = 2,
            freeExportsRemaining = 8,
        )
        val payload = OnboardingAnalyticsPayloadSerializer.serialize(
            OnboardingAnalyticsEnvelope(
                installId = "11111111-1111-4111-8111-111111111111",
                events = listOf(event),
            )
        )
        val root = Json.parseToJsonElement(payload).jsonObject
        val serializedEvent = root.getValue("events").jsonArray.single().jsonObject
        val properties = serializedEvent.getValue("properties").jsonObject

        assertThat(root.keys).containsExactly("installId", "events")
        assertThat(serializedEvent.keys).containsExactly("eventId", "eventName", "properties")
        assertThat(properties.keys).containsExactly(
            "appVersion",
            "buildNumber",
            "platform",
            "onboardingStep",
            "paywallContext",
            "freeExportsUsed",
            "freeExportsRemaining",
            "productId",
        )
        assertThat(properties.getValue("freeExportsUsed").toString()).isEqualTo("2")
        assertThat(properties.getValue("freeExportsRemaining").toString()).isEqualTo("8")
        assertThat(payload).doesNotContain("healthData")
        assertThat(payload).doesNotContain("healthPermissions")
        assertThat(payload).doesNotContain("permissionStatus")
        assertThat(payload).doesNotContain("folderUri")
        assertThat(payload).doesNotContain("folderName")
        assertThat(payload).doesNotContain("path")
        assertThat(payload).doesNotContain("timestamp")
        assertThat(payload).doesNotContain("referrer")
        assertThat(payload).doesNotContain("price")
        assertThat(payload).doesNotContain("error")
        assertThat(payload).doesNotContain("androidId")
    }

    @Test
    fun invalidFreeExportCountPairsAreRejected() {
        val event = OnboardingAnalyticsEventFactory(
            OnboardingAnalyticsAppInfo("1.5.4", "25"),
            OnboardingAnalyticsUuidGenerator { "22222222-2222-4222-8222-222222222222" },
        ).create(
            eventName = PricingOnboardingEventName.STEP_VIEWED,
            step = OnboardingAnalyticsStep.WELCOME,
            freeExportsUsed = 2,
            freeExportsRemaining = 9,
        )

        assertThat(OnboardingAnalyticsPrivacyValidator.isValid(event)).isFalse()
    }

    @Test
    fun nonPurchaseEventsOmitProductId() {
        val event = OnboardingAnalyticsEventFactory(
            OnboardingAnalyticsAppInfo("1.5.4", "25"),
            OnboardingAnalyticsUuidGenerator { "22222222-2222-4222-8222-222222222222" },
        ).create(
            PricingOnboardingEventName.STEP_VIEWED,
            OnboardingAnalyticsStep.HEALTH_ACCESS,
        )

        val payload = OnboardingAnalyticsPayloadSerializer.serialize(
            OnboardingAnalyticsEnvelope(
                "11111111-1111-4111-8111-111111111111",
                listOf(event),
            )
        )
        val properties = Json.parseToJsonElement(payload).jsonObject
            .getValue("events").jsonArray.single().jsonObject
            .getValue("properties").jsonObject

        assertThat(properties.keys).doesNotContain("productId")
    }
}
