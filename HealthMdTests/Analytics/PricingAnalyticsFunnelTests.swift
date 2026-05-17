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
            quotaState: PricingAnalyticsQuotaState(freeExportsUsed: 2, freeExportsRemaining: 1)
        )
        await client.flushAndWait()

        let payloads = await transport.payloadsValue()
        XCTAssertEqual(payloads.count, 1)
        XCTAssertEqual(payloads.first?.eventName, "pricing_paywall_shown")
        XCTAssertEqual(payloads.first?.properties[.paywallContext], .string("settings"))
        XCTAssertEqual(payloads.first?.properties[.freeExportsUsed], .int(2))
        XCTAssertEqual(payloads.first?.properties[.freeExportsRemaining], .int(1))
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
