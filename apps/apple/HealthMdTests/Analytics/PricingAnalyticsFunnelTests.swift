//
//  PricingAnalyticsFunnelTests.swift
//  HealthMdTests
//
//  Regression coverage for privacy-safe pricing funnel event builders.
//

import XCTest
@testable import HealthMd

final class PricingAnalyticsFunnelTests: XCTestCase {

    func testExportMetadataBucketsCountsAndDateSpansWithoutRawInputs() {
        let metadata: PricingAnalyticsExportMetadata = PricingAnalyticsExportMetadata(
            targetType: .localFile,
            formatCount: 3,
            metricCount: 17,
            dateRangePreset: PricingAnalyticsDateRangePreset.custom,
            startDate: date(2026, 5, 1),
            endDate: date(2026, 5, 20),
            calendar: utcCalendar
        )

        XCTAssertEqual(metadata.targetType, PricingAnalyticsExportTargetType.localFile)
        XCTAssertEqual(metadata.formatCount, 3)
        XCTAssertEqual(metadata.metricCountBucket, PricingAnalyticsMetricCountBucket.elevenToTwenty)
        XCTAssertEqual(metadata.dateRangePreset, PricingAnalyticsDateRangePreset.custom)
        XCTAssertEqual(metadata.dateSpanBucket, PricingAnalyticsDateSpanBucket.eightToThirtyDays)

        let event = PricingAnalyticsEvent(
            name: .exportPreviewGenerated,
            properties: PricingAnalyticsProperties(
                exportTargetType: metadata.targetType,
                formatCount: metadata.formatCount,
                metricCountBucket: metadata.metricCountBucket,
                dateRangePreset: metadata.dateRangePreset,
                dateSpanBucket: metadata.dateSpanBucket
            )
        )
        let payload = event.encodedPayload()
        let encodedValues = payload.transportProperties.values
            .map { String(describing: $0) }
            .joined(separator: " ")

        XCTAssertEqual(payload.properties[PricingAnalyticsPropertyKey.exportTargetType], PricingAnalyticsValue.string("local_file"))
        XCTAssertEqual(payload.properties[PricingAnalyticsPropertyKey.formatCount], PricingAnalyticsValue.int(3))
        XCTAssertEqual(payload.properties[PricingAnalyticsPropertyKey.metricCountBucket], PricingAnalyticsValue.string("11_20"))
        XCTAssertEqual(payload.properties[PricingAnalyticsPropertyKey.dateRangePreset], PricingAnalyticsValue.string("custom"))
        XCTAssertEqual(payload.properties[PricingAnalyticsPropertyKey.dateSpanBucket], PricingAnalyticsValue.string("8_30_days"))
        XCTAssertFalse(encodedValues.contains("2026"))
        XCTAssertFalse(encodedValues.localizedCaseInsensitiveContains("step"))
        XCTAssertFalse(encodedValues.localizedCaseInsensitiveContains("heart"))
        XCTAssertFalse(encodedValues.localizedCaseInsensitiveContains("/"))
    }

    func testMetricCountBucketBoundaries() {
        XCTAssertEqual(PricingAnalyticsExportMetadata.metricCountBucket(for: 0), .zero)
        XCTAssertEqual(PricingAnalyticsExportMetadata.metricCountBucket(for: 1), .oneToFive)
        XCTAssertEqual(PricingAnalyticsExportMetadata.metricCountBucket(for: 5), .oneToFive)
        XCTAssertEqual(PricingAnalyticsExportMetadata.metricCountBucket(for: 6), .sixToTen)
        XCTAssertEqual(PricingAnalyticsExportMetadata.metricCountBucket(for: 10), .sixToTen)
        XCTAssertEqual(PricingAnalyticsExportMetadata.metricCountBucket(for: 11), .elevenToTwenty)
        XCTAssertEqual(PricingAnalyticsExportMetadata.metricCountBucket(for: 20), .elevenToTwenty)
        XCTAssertEqual(PricingAnalyticsExportMetadata.metricCountBucket(for: 21), .twentyOnePlus)
        XCTAssertEqual(PricingAnalyticsExportMetadata.metricCountBucket(for: 100), .twentyOnePlus)
    }

    func testDateSpanBucketBoundariesUseOnlySpanLength() {
        XCTAssertEqual(
            PricingAnalyticsExportMetadata.dateSpanBucket(
                startDate: date(2026, 5, 1),
                endDate: date(2026, 5, 1),
                calendar: utcCalendar
            ),
            .sameDay
        )
        XCTAssertEqual(
            PricingAnalyticsExportMetadata.dateSpanBucket(
                startDate: date(2026, 5, 1),
                endDate: date(2026, 5, 7),
                calendar: utcCalendar
            ),
            .oneToSevenDays
        )
        XCTAssertEqual(
            PricingAnalyticsExportMetadata.dateSpanBucket(
                startDate: date(2026, 5, 1),
                endDate: date(2026, 5, 8),
                calendar: utcCalendar
            ),
            .eightToThirtyDays
        )
        XCTAssertEqual(
            PricingAnalyticsExportMetadata.dateSpanBucket(
                startDate: date(2026, 5, 1),
                endDate: date(2026, 5, 30),
                calendar: utcCalendar
            ),
            .eightToThirtyDays
        )
        XCTAssertEqual(
            PricingAnalyticsExportMetadata.dateSpanBucket(
                startDate: date(2026, 5, 1),
                endDate: date(2026, 7, 29),
                calendar: utcCalendar
            ),
            .thirtyOneToNinetyDays
        )
        XCTAssertEqual(
            PricingAnalyticsExportMetadata.dateSpanBucket(
                startDate: date(2026, 5, 1),
                endDate: date(2026, 7, 31),
                calendar: utcCalendar
            ),
            .ninetyOnePlusDays
        )
    }

    func testTypedPaywallTrackingBuildsQuotaContextPayload() async {
        let transport = RecordingPricingAnalyticsTransport()
        let client = PricingAnalyticsClient(
            transport: transport,
            defaults: FakeUserDefaults(),
            queueKey: "pricing.analytics.test.paywall-typed",
            maxQueueSize: 5,
            isEnabled: true
        )

        client.trackPaywallShown(
            context: .settings,
            quotaState: PricingAnalyticsQuotaState(freeExportsUsed: 2, freeExportsRemaining: 8)
        )
        await client.flushAndWait()

        let payloads = await transport.payloadsValue()
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads.first?.eventName, "pricing_paywall_shown")
        XCTAssertEqual(payloads.first?.properties[.paywallContext], .string("settings"))
        XCTAssertEqual(payloads.first?.properties[.freeExportsUsed], .int(2))
        XCTAssertEqual(payloads.first?.properties[.freeExportsRemaining], .int(8))
    }

    func testTypedOnboardingTrackingBuildsStepPayloads() async {
        let transport = RecordingPricingAnalyticsTransport()
        let client = PricingAnalyticsClient(
            transport: transport,
            defaults: FakeUserDefaults(),
            queueKey: "pricing.analytics.test.onboarding-typed",
            maxQueueSize: 12,
            isEnabled: true
        )
        let quota = PricingAnalyticsQuotaState(freeExportsUsed: 0, freeExportsRemaining: 10)

        client.trackOnboardingStarted(quotaState: quota)
        client.trackOnboardingStepViewed(.healthAccess, quotaState: quota)
        client.trackOnboardingStepViewed(.sampleExport, quotaState: quota)
        client.trackOnboardingStepViewed(.obsidianPlugin, quotaState: quota)
        client.trackOnboardingHealthSkipped(quotaState: quota)
        client.trackOnboardingFolderSelected(quotaState: quota)
        client.trackOnboardingFolderSkipped(quotaState: quota)
        client.trackOnboardingPurchaseTapped(productId: .familyLifetimeUnlock, quotaState: quota)
        client.trackOnboardingContinueFreeTapped(quotaState: quota)
        client.trackOnboardingCompleted(quotaState: quota)
        await client.flushAndWait()

        let payloads = await transport.payloadsValue()
        XCTAssertEqual(
            payloads.map(\.eventName),
            [
                "pricing_onboarding_started",
                "pricing_onboarding_step_viewed",
                "pricing_onboarding_step_viewed",
                "pricing_onboarding_step_viewed",
                "pricing_onboarding_health_skipped",
                "pricing_onboarding_folder_selected",
                "pricing_onboarding_folder_skipped",
                "pricing_onboarding_purchase_tapped",
                "pricing_onboarding_continue_free_tapped",
                "pricing_onboarding_completed"
            ]
        )
        XCTAssertEqual(payloads[0].properties[.onboardingStep], .string("welcome"))
        XCTAssertEqual(payloads[1].properties[.onboardingStep], .string("health_access"))
        XCTAssertEqual(payloads[2].properties[.onboardingStep], .string("sample_export"))
        XCTAssertEqual(payloads[3].properties[.onboardingStep], .string("obsidian_plugin"))
        XCTAssertEqual(payloads[4].properties[.onboardingStep], .string("health_access"))
        XCTAssertEqual(payloads[5].properties[.onboardingStep], .string("folder_setup"))
        XCTAssertEqual(payloads[6].properties[.onboardingStep], .string("folder_setup"))
        XCTAssertEqual(payloads[7].properties[.onboardingStep], .string("unlock"))
        XCTAssertEqual(payloads[7].properties[.paywallContext], .string("onboarding"))
        XCTAssertEqual(
            payloads[7].properties[.productId],
            .string("com.codybontecou.obsidianhealth.unlock.family")
        )
        XCTAssertEqual(payloads[8].properties[.onboardingStep], .string("unlock"))
        XCTAssertEqual(payloads[8].properties[.paywallContext], .string("onboarding"))
        XCTAssertEqual(payloads[9].properties[.onboardingStep], .string("ready"))
    }

    func testMacOnboardingStepsOmitIrrelevantQuotaState() async {
        let transport = RecordingPricingAnalyticsTransport()
        let client = PricingAnalyticsClient(
            transport: transport,
            defaults: FakeUserDefaults(),
            queueKey: "pricing.analytics.test.mac-onboarding",
            maxQueueSize: 5,
            isEnabled: true
        )

        client.trackOnboardingStarted()
        client.trackOnboardingStepViewed(.macHowItWorks)
        client.trackOnboardingStepViewed(.macIPhoneApp)
        client.trackOnboardingStepViewed(.macConnect)
        client.trackOnboardingCompleted()
        await client.flushAndWait()

        let payloads = await transport.payloadsValue()
        XCTAssertEqual(payloads.map(\.eventName), [
            "pricing_onboarding_started",
            "pricing_onboarding_step_viewed",
            "pricing_onboarding_step_viewed",
            "pricing_onboarding_step_viewed",
            "pricing_onboarding_completed",
        ])
        XCTAssertEqual(
            payloads.compactMap { payload -> String? in
                guard case let .string(value) = payload.properties[.onboardingStep] else { return nil }
                return value
            },
            ["welcome", "mac_how_it_works", "mac_iphone_app", "mac_connect", "ready"]
        )
        XCTAssertTrue(payloads.allSatisfy { payload in
            payload.properties[.freeExportsUsed] == nil &&
                payload.properties[.freeExportsRemaining] == nil
        })
    }

    func testPurchaseAndRestoreLifecycleRetainSourceContext() async {
        let transport = RecordingPricingAnalyticsTransport()
        let client = PricingAnalyticsClient(
            transport: transport,
            defaults: FakeUserDefaults(),
            queueKey: "pricing.analytics.test.purchase-source",
            maxQueueSize: 6,
            isEnabled: true
        )
        let quota = PricingAnalyticsQuotaState(freeExportsUsed: 0, freeExportsRemaining: 10)

        client.trackPaywallCTATapped(
            context: .onboarding,
            productId: .lifetimeUnlock,
            quotaState: quota
        )
        client.trackPurchaseStarted(
            quotaState: quota,
            source: .onboardingUnlock
        )
        client.trackPurchaseFinished(
            outcome: .succeeded,
            quotaState: quota,
            source: .onboardingUnlock
        )
        client.trackRestoreStarted(
            quotaState: quota,
            source: .paywall(.settings)
        )
        client.trackRestoreFinished(
            outcome: .failed,
            quotaState: quota,
            source: .paywall(.settings)
        )
        await client.flushAndWait()

        let payloads = await transport.payloadsValue()
        XCTAssertEqual(payloads.map(\.eventName), [
            "pricing_paywall_cta_tapped",
            "pricing_purchase_started",
            "pricing_purchase_finished",
            "pricing_restore_started",
            "pricing_restore_finished",
        ])
        for payload in payloads[1...2] {
            XCTAssertEqual(payload.properties[.paywallContext], .string("onboarding"))
            XCTAssertEqual(payload.properties[.onboardingStep], .string("unlock"))
        }
        for payload in payloads[3...4] {
            XCTAssertEqual(payload.properties[.paywallContext], .string("settings"))
            XCTAssertNil(payload.properties[.onboardingStep])
        }
    }

    private var utcCalendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year
        components.month = month
        components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }
}

private actor RecordingPricingAnalyticsTransport: PricingAnalyticsTransport {
    private(set) var payloads: [PricingAnalyticsPayload] = []

    func send(_ payload: PricingAnalyticsPayload) async throws {
        payloads.append(payload)
    }

    func payloadsValue() -> [PricingAnalyticsPayload] {
        payloads
    }
}
