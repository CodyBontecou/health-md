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
                freeExportsUsed: 10,
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
        XCTAssertEqual(payload.properties[.freeExportsUsed], .int(10))
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
        XCTAssertTrue(names.contains("pricing_onboarding_health_skipped"))
        XCTAssertTrue(names.contains("pricing_onboarding_folder_selected"))
        XCTAssertTrue(names.contains("pricing_onboarding_folder_skipped"))
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
            "credential",
            "accessToken",
            "refreshToken",
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
            "Bearer secret-token",
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

    func testLatestAppStoreMetadataDisclosesProductAnalyticsWithoutAbsoluteNoAnalyticsClaims() throws {
        let metadataRoot = try latestAppStoreMetadataDirectory()
        let metadataFiles = try FileManager.default.contentsOfDirectory(
            at: metadataRoot,
            includingPropertiesForKeys: nil
        )
        .filter { $0.pathExtension == "json" }

        XCTAssertEqual(metadataFiles.count, 10)

        let prohibitedClaims = [
            "no analytics",
            "keine analyse",
            "sin analíticas",
            "aucune analyse",
            "nessun tracciamento",
            "分析もなし",
            "분석도 없습니다",
            "geen tracking",
            "sem análises",
            "没有数据分析",
            "turn it off",
            "deaktivier",
            "desactiv",
            "désactiv",
            "disattiv",
            "無効に",
            "끌 수",
            "uitschakel",
            "desativ",
            "关闭"
        ]

        for file in metadataFiles {
            let data = try Data(contentsOf: file)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
            let description = try XCTUnwrap(object["description"] as? String)
            for claim in prohibitedClaims {
                XCTAssertFalse(
                    description.localizedCaseInsensitiveContains(claim),
                    "\(file.lastPathComponent) still contains the absolute claim: \(claim)"
                )
            }
        }

        let englishData = try Data(contentsOf: metadataRoot.appendingPathComponent("en-US.json"))
        let englishObject = try XCTUnwrap(JSONSerialization.jsonObject(with: englishData) as? [String: Any])
        let englishDescription = try XCTUnwrap(englishObject["description"] as? String)
        XCTAssertTrue(englishDescription.contains("automatically collects limited pseudonymous product events"))
        XCTAssertTrue(englishDescription.contains("never include health values, metric names, health dates, or exported files"))
        XCTAssertTrue(englishDescription.contains("not used for advertising or cross-app tracking"))
    }

    func testPrivacyManifestDeclaresPseudonymousProductAnalyticsWithoutTracking() throws {
        let data = try Data(contentsOf: try privacyManifestURL())
        let manifest = try XCTUnwrap(
            PropertyListSerialization.propertyList(from: data, options: [], format: nil) as? [String: Any]
        )
        XCTAssertEqual(manifest["NSPrivacyTracking"] as? Bool, false)
        XCTAssertEqual(manifest["NSPrivacyTrackingDomains"] as? [String], [])

        let collectedTypes = try XCTUnwrap(manifest["NSPrivacyCollectedDataTypes"] as? [[String: Any]])
        let analyticsTypes = collectedTypes.filter { entry in
            let purposes = entry["NSPrivacyCollectedDataTypePurposes"] as? [String] ?? []
            return purposes.contains("NSPrivacyCollectedDataTypePurposeAnalytics")
        }
        let declaredTypeNames = Set(analyticsTypes.compactMap { $0["NSPrivacyCollectedDataType"] as? String })

        XCTAssertTrue(declaredTypeNames.contains("NSPrivacyCollectedDataTypeDeviceID"))
        XCTAssertTrue(declaredTypeNames.contains("NSPrivacyCollectedDataTypeProductInteraction"))
        XCTAssertTrue(declaredTypeNames.contains("NSPrivacyCollectedDataTypePurchaseHistory"))
        XCTAssertTrue(declaredTypeNames.contains("NSPrivacyCollectedDataTypeOtherUsageData"))
        XCTAssertTrue(analyticsTypes.allSatisfy { ($0["NSPrivacyCollectedDataTypeTracking"] as? Bool) == false })
        XCTAssertTrue(analyticsTypes.allSatisfy { ($0["NSPrivacyCollectedDataTypeLinked"] as? Bool) == false })
    }

    func testAnalyticsModuleCannotReadHealthKitSamples() throws {
        let prohibitedSourceTokens = [
            "import HealthKit",
            "HKHealthStore",
            "HKSample",
            "HKQuantitySample",
            "HKCategorySample",
            "HKCorrelation",
            "HKWorkout",
            "HKClinicalRecord",
            "HealthKitManager",
            "HealthDataStore"
        ]

        for sourceURL in try pricingAnalyticsSourceURLs() {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            for token in prohibitedSourceTokens {
                XCTAssertFalse(
                    source.contains(token),
                    "\(sourceURL.lastPathComponent) must not access health records through \(token)."
                )
            }
        }
    }

    func testAnalyticsModuleHasNoUserOptOutOrIdentifierResetAPI() throws {
        let prohibitedSourceTokens = [
            "setCollectionEnabled",
            "isCollectionEnabled",
            "resetInstallIdentifier",
            "pricing.analytics.collection.enabled"
        ]

        for sourceURL in try pricingAnalyticsSourceURLs() {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            for token in prohibitedSourceTokens {
                XCTAssertFalse(
                    source.contains(token),
                    "\(sourceURL.lastPathComponent) unexpectedly exposes optional analytics via \(token)."
                )
            }
        }
    }

    func testEventModelSourceDoesNotImportTransportOrPurchaseFrameworks() throws {
        let source = try pricingAnalyticsEventSource()

        XCTAssertFalse(source.contains("import StoreKit"))
        XCTAssertFalse(source.contains("URLSession"))
    }

    private func privacyManifestURL() throws -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        var searchDirectory = testFile.deletingLastPathComponent()

        for _ in 0..<8 {
            let manifestURL = searchDirectory
                .appendingPathComponent("HealthMd")
                .appendingPathComponent("PrivacyInfo.xcprivacy")
            if FileManager.default.fileExists(atPath: manifestURL.path) {
                return manifestURL
            }
            searchDirectory.deleteLastPathComponent()
        }

        throw NSError(
            domain: "PricingAnalyticsEventTests",
            code: 3,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate PrivacyInfo.xcprivacy from \(#filePath)."]
        )
    }

    private func latestAppStoreMetadataDirectory() throws -> URL {
        let testFile = URL(fileURLWithPath: #filePath)
        var searchDirectory = testFile.deletingLastPathComponent()

        for _ in 0..<8 {
            let versionsURL = searchDirectory
                .appendingPathComponent("metadata")
                .appendingPathComponent("version")
            if FileManager.default.fileExists(atPath: versionsURL.path) {
                let directories = try FileManager.default.contentsOfDirectory(
                    at: versionsURL,
                    includingPropertiesForKeys: [.isDirectoryKey]
                )
                .filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
                .sorted { $0.lastPathComponent.compare($1.lastPathComponent, options: .numeric) == .orderedAscending }

                return try XCTUnwrap(directories.last)
            }

            searchDirectory.deleteLastPathComponent()
        }

        throw NSError(
            domain: "PricingAnalyticsEventTests",
            code: 2,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate App Store version metadata from \(#filePath)."]
        )
    }

    private func pricingAnalyticsSourceURLs() throws -> [URL] {
        let testFile = URL(fileURLWithPath: #filePath)
        var searchDirectory = testFile.deletingLastPathComponent()

        for _ in 0..<8 {
            let analyticsDirectory = searchDirectory
                .appendingPathComponent("HealthMd")
                .appendingPathComponent("Shared")
                .appendingPathComponent("Analytics")
            if FileManager.default.fileExists(atPath: analyticsDirectory.path) {
                return try FileManager.default.contentsOfDirectory(
                    at: analyticsDirectory,
                    includingPropertiesForKeys: nil
                )
                .filter { $0.pathExtension == "swift" }
            }
            searchDirectory.deleteLastPathComponent()
        }

        throw NSError(
            domain: "PricingAnalyticsEventTests",
            code: 1,
            userInfo: [NSLocalizedDescriptionKey: "Could not locate analytics sources from \(#filePath)."]
        )
    }

    private func pricingAnalyticsEventSource() throws -> String {
        let eventSourceURL = try XCTUnwrap(
            pricingAnalyticsSourceURLs().first { $0.lastPathComponent == "PricingAnalyticsEvent.swift" }
        )
        return try String(contentsOf: eventSourceURL, encoding: .utf8)
    }
}
