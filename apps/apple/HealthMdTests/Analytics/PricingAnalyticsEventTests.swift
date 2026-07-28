//
//  PricingAnalyticsEventTests.swift
//  HealthMdTests
//
//  Tests for the pricing analytics event model.
//  These tests intentionally cover only the local typed model; no transport is
//  involved so pricing analytics cannot block offline app flows.
//

import XCTest
@testable import HealthMd

final class PricingAnalyticsEventTests: XCTestCase {

    func testPayloadEncodesOnlyAllowlistedProperties() {
        let event = PricingAnalyticsEvent(
            name: .paywallViewed,
            properties: PricingAnalyticsProperties(
                experimentId: "pricing_activation_2026_05",
                variantId: "baseline_1499",
                appVersion: "1.8.2",
                buildNumber: "204",
                platform: .iOS,
                paywallContext: .exportQuota,
                onboardingStep: .unlock,
                freeExportsUsed: 3,
                freeExportsRemaining: 0,
                exportTargetType: .localFile,
                formatCount: 2,
                metricCountBucket: .sixToTen,
                dateRangePreset: .lastSevenDays,
                dateSpanBucket: .oneToSevenDays,
                productId: .lifetimeUnlock,
                purchaseOutcome: .failed,
                authorizationStatus: .authorized,
                errorCategory: .networkUnavailable
            )
        )

        let payload = event.encodedPayload()

        XCTAssertEqual(payload.eventName, "pricing_paywall_viewed")
        XCTAssertEqual(
            Set(payload.properties.keys),
            Set(PricingAnalyticsPropertyKey.allCases),
            "The encoded model should contain every allowlisted property and no arbitrary keys."
        )
        XCTAssertEqual(payload.properties[.experimentId], .string("pricing_activation_2026_05"))
        XCTAssertEqual(payload.properties[.variantId], .string("baseline_1499"))
        XCTAssertEqual(payload.properties[.appVersion], .string("1.8.2"))
        XCTAssertEqual(payload.properties[.buildNumber], .string("204"))
        XCTAssertEqual(payload.properties[.platform], .string("ios"))
        XCTAssertEqual(payload.properties[.paywallContext], .string("export_quota"))
        XCTAssertEqual(payload.properties[.onboardingStep], .string("unlock"))
        XCTAssertEqual(payload.properties[.freeExportsUsed], .int(3))
        XCTAssertEqual(payload.properties[.freeExportsRemaining], .int(0))
        XCTAssertEqual(payload.properties[.exportTargetType], .string("local_file"))
        XCTAssertEqual(payload.properties[.formatCount], .int(2))
        XCTAssertEqual(payload.properties[.metricCountBucket], .string("6_10"))
        XCTAssertEqual(payload.properties[.dateRangePreset], .string("last_7_days"))
        XCTAssertEqual(payload.properties[.dateSpanBucket], .string("1_7_days"))
        XCTAssertEqual(payload.properties[.productId], .string("com.codybontecou.obsidianhealth.unlock"))
        XCTAssertEqual(payload.properties[.purchaseOutcome], .string("failed"))
        XCTAssertEqual(payload.properties[.authorizationStatus], .string("authorized"))
        XCTAssertEqual(payload.properties[.errorCategory], .string("network_unavailable"))
    }

    func testProductIDsIncludeOnlyLifetimeUnlocks() {
        XCTAssertEqual(
            Set(PricingAnalyticsProductID.allCases.map(\.rawValue)),
            Set([
                "com.codybontecou.obsidianhealth.unlock",
                "com.codybontecou.obsidianhealth.unlock.family",
                "com.codybontecou.obsidianhealth.unlock.family.upgrade",
            ])
        )
    }

    func testFunnelEventNamesAreCoarseAndPricingScoped() {
        let names = Set(PricingAnalyticsEventName.allCases.map(\.rawValue))

        XCTAssertTrue(names.contains("pricing_onboarding_started"))
        XCTAssertTrue(names.contains("pricing_onboarding_step_viewed"))
        XCTAssertTrue(names.contains("pricing_onboarding_folder_selected"))
        XCTAssertTrue(names.contains("pricing_onboarding_continue_free_tapped"))
        XCTAssertTrue(names.contains("pricing_onboarding_purchase_tapped"))
        XCTAssertTrue(names.contains("pricing_onboarding_completed"))
        XCTAssertTrue(names.contains("pricing_health_authorization_completed"))
        XCTAssertTrue(names.contains("pricing_export_preview_opened"))
        XCTAssertTrue(names.contains("pricing_export_preview_generated"))
        XCTAssertTrue(names.contains("pricing_export_preview_failed"))
        XCTAssertTrue(names.contains("pricing_export_succeeded"))
        XCTAssertTrue(names.contains("pricing_free_export_used"))
        XCTAssertTrue(names.contains("pricing_paywall_shown"))
        XCTAssertTrue(names.contains("pricing_purchase_started"))
        XCTAssertTrue(names.contains("pricing_purchase_finished"))
        XCTAssertTrue(names.contains("pricing_restore_started"))
        XCTAssertTrue(names.contains("pricing_restore_finished"))
        XCTAssertTrue(names.contains("pricing_schedule_enable_blocked"))
        XCTAssertTrue(names.contains("pricing_schedule_enable_unblocked"))

        for name in names {
            XCTAssertTrue(name.hasPrefix("pricing_"))
            XCTAssertFalse(name.localizedCaseInsensitiveContains("healthkit"))
            XCTAssertFalse(name.localizedCaseInsensitiveContains("metric"))
            XCTAssertFalse(name.localizedCaseInsensitiveContains("path"))
            XCTAssertFalse(name.localizedCaseInsensitiveContains("vault"))
            XCTAssertFalse(name.localizedCaseInsensitiveContains("value"))
        }
    }

    func testDisallowedPropertyKeysAreNotRepresentable() {
        let prohibitedKeys = [
            "HKQuantityTypeIdentifierStepCount",
            "steps",
            "healthValue",
            "healthDate",
            "metricName",
            "medicationName",
            "workoutTitle",
            "vaultPath",
            "filePath",
            "folderName",
            "devicePeerName",
            "exportedMarkdown",
            "healthKitIdentifier",
            "metricIdentifier",
            "absoluteDate"
        ]

        for key in prohibitedKeys {
            XCTAssertNil(
                PricingAnalyticsPropertyKey(rawValue: key),
                "\(key) must not be an encodable pricing analytics property key."
            )
        }
    }

    func testSensitiveStringExamplesAreOmittedAtEncodingBoundary() {
        let sensitiveValues = [
            "HKQuantityTypeIdentifierStepCount",
            "steps",
            "/Users/cody/Obsidian",
            "Health/2026-05-14.md",
            "2026-05-14",
            "Metformin",
            "Morning Run",
            "# Health\n- Steps: 10,000"
        ]

        for sensitiveValue in sensitiveValues {
            let event = PricingAnalyticsEvent(
                name: .paywallViewed,
                properties: PricingAnalyticsProperties(
                    experimentId: sensitiveValue,
                    variantId: sensitiveValue,
                    appVersion: sensitiveValue,
                    buildNumber: sensitiveValue
                )
            )

            let payload = event.encodedPayload()

            XCTAssertFalse(
                payload.properties.values.contains(.string(sensitiveValue)),
                "Sensitive value \(sensitiveValue) should be rejected or omitted."
            )
        }
    }

    func testRawHealthValuesAreNotAcceptedAsCountProperties() {
        let event = PricingAnalyticsEvent(
            name: .exportBlockedByQuota,
            properties: PricingAnalyticsProperties(
                freeExportsUsed: 10_000,
                freeExportsRemaining: -1,
                formatCount: 72
            )
        )

        let payload = event.encodedPayload()

        XCTAssertNil(payload.properties[.freeExportsUsed])
        XCTAssertNil(payload.properties[.freeExportsRemaining])
        XCTAssertNil(payload.properties[.formatCount])
    }

    func testDateBearingIdentifiersAreRejectedAcrossAllowedSeparators() {
        let dateBearingIdentifiers = [
            "pricing_activation_2026-05-14",
            "pricing_activation_2026_05_14",
            "pricing.activation.2026.05.14",
            "pricing_activation_20260514",
            "pricing_activation_2026_05_14_1530"
        ]

        for identifier in dateBearingIdentifiers {
            let event = PricingAnalyticsEvent(
                name: .paywallViewed,
                properties: PricingAnalyticsProperties(
                    experimentId: identifier,
                    variantId: identifier
                )
            )

            let payload = event.encodedPayload()

            XCTAssertNil(
                payload.properties[.experimentId],
                "Date-bearing experiment identifier \(identifier) should be rejected."
            )
            XCTAssertNil(
                payload.properties[.variantId],
                "Date-bearing variant identifier \(identifier) should be rejected."
            )
        }
    }

    func testModelSourceDoesNotImportHealthKitOrTransportFrameworks() throws {
        let source = try pricingAnalyticsEventSource()

        XCTAssertFalse(source.contains("import HealthKit"))
        XCTAssertFalse(source.contains("import StoreKit"))
        XCTAssertFalse(source.contains("URLSession"))
        XCTAssertFalse(source.contains("HKSample"))
        XCTAssertFalse(source.contains("HKQuantitySample"))
        XCTAssertFalse(source.contains("HKCategorySample"))
        XCTAssertFalse(source.contains("HKWorkout"))
    }

    private func pricingAnalyticsEventSource() throws -> String {
        let testFile = URL(fileURLWithPath: #filePath)
        var searchDirectory = testFile.deletingLastPathComponent()

        for _ in 0..<8 {
            let sourceURL = searchDirectory
                .appendingPathComponent("HealthMd")
                .appendingPathComponent("Shared")
                .appendingPathComponent("Analytics")
                .appendingPathComponent("PricingAnalyticsEvent.swift")

            if FileManager.default.fileExists(atPath: sourceURL.path) {
                return try String(contentsOf: sourceURL, encoding: .utf8)
            }

            searchDirectory.deleteLastPathComponent()
        }

        throw NSError(
            domain: "PricingAnalyticsEventTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate PricingAnalyticsEvent.swift from \(#filePath)."]
        )
    }
}
