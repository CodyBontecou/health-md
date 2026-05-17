//
//  PricingExperimentAssignmentTests.swift
//  HealthMdTests
//
//  Regression coverage for sticky, offline-safe pricing experiment assignment.
//

import XCTest
@testable import HealthMd

final class PricingExperimentAssignmentTests: XCTestCase {

    func testAssignmentIsStableAcrossAppLaunches() throws {
        let defaults = FakeUserDefaults()
        let assignedAt = Date(timeIntervalSince1970: 1_779_000_000)
        let later = assignedAt.addingTimeInterval(86_400)

        let firstStore = PricingExperimentAssignmentStore(
            defaults: defaults,
            now: { assignedAt }
        )
        let firstAssignment = firstStore.assignment(for: .baseline)

        let relaunchedStore = PricingExperimentAssignmentStore(
            defaults: defaults,
            now: { later }
        )
        let relaunchedAssignment = relaunchedStore.assignment(for: .baseline)

        XCTAssertEqual(relaunchedAssignment, firstAssignment)
        XCTAssertEqual(relaunchedAssignment.assignedAt, assignedAt)
    }

    func testMissingConfigDefaultsToBaselineAndCurrentProduct() {
        let config = PricingExperimentConfig.resolved(from: nil)
        let assignment = PricingExperimentAssignmentStore(
            defaults: FakeUserDefaults(),
            now: { Date(timeIntervalSince1970: 1_779_000_000) }
        ).assignment(for: config)

        XCTAssertEqual(config, .baseline)
        XCTAssertEqual(assignment.experimentId, PricingExperimentConfig.currentExperimentId)
        XCTAssertEqual(assignment.variantId, PricingExperimentConfig.baselineVariantId)
        XCTAssertNil(assignment.productIdOverride)
        XCTAssertEqual(config.effectiveProductID(defaultProductID: PurchaseManager.productID), PurchaseManager.productID)
    }

    func testOfflineRemoteConfigDefaultsToBaselineAndCurrentProduct() throws {
        let overrideProductID = "com.codybontecou.obsidianhealth.unlock.1499"
        let remoteData = try JSONSerialization.data(withJSONObject: [
            "experimentId": PricingExperimentConfig.currentExperimentId,
            "variantId": PricingExperimentConfig.testVariantId,
            "productIdOverride": overrideProductID,
            "isProductIDOverrideEnabled": true
        ])

        let config = PricingExperimentConfig.resolved(
            from: remoteData,
            environment: ["UITEST_REMOTE_CONFIG": "offline"]
        )
        let assignment = PricingExperimentAssignmentStore(
            defaults: FakeUserDefaults(),
            now: { Date(timeIntervalSince1970: 1_779_000_000) }
        ).assignment(for: config)

        XCTAssertEqual(config, .baseline)
        XCTAssertEqual(assignment.variantId, PricingExperimentConfig.baselineVariantId)
        XCTAssertNil(assignment.productIdOverride)
        XCTAssertEqual(config.effectiveProductID(defaultProductID: PurchaseManager.productID), PurchaseManager.productID)
    }

    func testMalformedAndUnknownConfigFallBackToBaseline() throws {
        let malformed = Data("{".utf8)
        XCTAssertEqual(PricingExperimentConfig.resolved(from: malformed), .baseline)

        let unknown = try JSONSerialization.data(withJSONObject: [
            "experimentId": "pricing_unknown",
            "variantId": "experimental_unknown"
        ])
        XCTAssertEqual(PricingExperimentConfig.resolved(from: unknown), .baseline)

        let sensitive = try JSONSerialization.data(withJSONObject: [
            "experimentId": "pricing_lifetime_unlock",
            "variantId": "variant_with_health_steps"
        ])
        XCTAssertEqual(PricingExperimentConfig.resolved(from: sensitive), .baseline)
    }

    func testPricingEventsIncludeAssignmentWithoutIdentityOrHealthData() async {
        let transport = AssignmentRecordingPricingAnalyticsTransport()
        let client = PricingAnalyticsClient(
            transport: transport,
            defaults: FakeUserDefaults(),
            queueKey: "pricing.analytics.test.assignment.\(UUID().uuidString)",
            maxQueueSize: 5,
            isEnabled: true,
            assignmentStore: PricingExperimentAssignmentStore(
                defaults: FakeUserDefaults(),
                now: { Date(timeIntervalSince1970: 1_779_000_000) }
            )
        )

        client.trackPaywallShown(
            context: .exportQuota,
            quotaState: PricingAnalyticsQuotaState(freeExportsUsed: 3, freeExportsRemaining: 0)
        )
        await client.flushAndWait()

        let payload = await transport.firstPayload()
        XCTAssertEqual(payload?.properties[.experimentId], .string(PricingExperimentConfig.currentExperimentId))
        XCTAssertEqual(payload?.properties[.variantId], .string(PricingExperimentConfig.baselineVariantId))
        XCTAssertNil(payload?.transportProperties["assignedAt"])
        XCTAssertNil(payload?.transportProperties["installId"])
        XCTAssertNil(payload?.transportProperties["userId"])
        XCTAssertNil(payload?.transportProperties["healthValue"])
        XCTAssertNil(payload?.transportProperties["metricName"])
        XCTAssertNil(payload?.transportProperties["filePath"])
    }

    func testProductIDOverrideIsIgnoredUnlessExplicitlyEnabled() throws {
        let overrideProductID = "com.codybontecou.obsidianhealth.unlock.1499"
        let disabledData = try JSONSerialization.data(withJSONObject: [
            "experimentId": PricingExperimentConfig.currentExperimentId,
            "variantId": PricingExperimentConfig.testVariantId,
            "productIdOverride": overrideProductID
        ])
        let enabledData = try JSONSerialization.data(withJSONObject: [
            "experimentId": PricingExperimentConfig.currentExperimentId,
            "variantId": PricingExperimentConfig.testVariantId,
            "productIdOverride": overrideProductID,
            "isProductIDOverrideEnabled": true
        ])
        let disabledConfig = PricingExperimentConfig.resolved(from: disabledData)
        let enabledConfig = PricingExperimentConfig.resolved(from: enabledData)

        XCTAssertEqual(disabledConfig.variantId, PricingExperimentConfig.testVariantId)
        XCTAssertNil(disabledConfig.productIdOverride)
        XCTAssertEqual(
            disabledConfig.effectiveProductID(defaultProductID: PurchaseManager.productID),
            PurchaseManager.productID
        )
        XCTAssertEqual(
            enabledConfig.effectiveProductID(defaultProductID: PurchaseManager.productID),
            overrideProductID
        )
    }

    func testInvalidProductIDOverrideDoesNotRejectConfigWhenOverrideIsDisabled() throws {
        let disabledData = try JSONSerialization.data(withJSONObject: [
            "experimentId": PricingExperimentConfig.currentExperimentId,
            "variantId": PricingExperimentConfig.testVariantId,
            "productIdOverride": "typoed product id with spaces"
        ])
        let enabledData = try JSONSerialization.data(withJSONObject: [
            "experimentId": PricingExperimentConfig.currentExperimentId,
            "variantId": PricingExperimentConfig.testVariantId,
            "productIdOverride": "typoed product id with spaces",
            "isProductIDOverrideEnabled": true
        ])

        let disabledConfig = PricingExperimentConfig.resolved(from: disabledData)
        let enabledConfig = PricingExperimentConfig.resolved(from: enabledData)

        XCTAssertEqual(disabledConfig.experimentId, PricingExperimentConfig.currentExperimentId)
        XCTAssertEqual(disabledConfig.variantId, PricingExperimentConfig.testVariantId)
        XCTAssertNil(disabledConfig.productIdOverride)
        XCTAssertEqual(
            disabledConfig.effectiveProductID(defaultProductID: PurchaseManager.productID),
            PurchaseManager.productID
        )
        XCTAssertEqual(enabledConfig, .baseline)
    }
}

private actor AssignmentRecordingPricingAnalyticsTransport: PricingAnalyticsTransport {
    private var payloads: [PricingAnalyticsPayload] = []

    func send(_ payload: PricingAnalyticsPayload) async throws {
        payloads.append(payload)
    }

    func firstPayload() -> PricingAnalyticsPayload? {
        payloads.first
    }
}
