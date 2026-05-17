//
//  PricingAnalyticsClientTests.swift
//  HealthMdTests
//
//  Tests for the offline-safe pricing analytics client.
//

import XCTest
@testable import HealthMd

final class PricingAnalyticsClientTests: XCTestCase {

    func testTrackDoesNotThrowOrPropagateOfflineTransportFailures() async {
        let transport = RecordingPricingAnalyticsTransport(error: URLError(.notConnectedToInternet))
        let defaults = FakeUserDefaults()
        let client = PricingAnalyticsClient(
            transport: transport,
            defaults: defaults,
            queueKey: "pricing.analytics.test.offline",
            maxQueueSize: 3,
            isEnabled: true
        )

        client.track(Self.event(variantId: "baseline"))
        await client.flushAndWait()

        let attemptCount = await transport.attemptCountValue()
        let sentPayloads = await transport.payloadsValue()
        let queuedPayloads = await client.queuedPayloads()
        let queuedPayload = try? XCTUnwrap(queuedPayloads.first)
        XCTAssertEqual(attemptCount, 1)
        XCTAssertEqual(queuedPayloads.count, 1)
        XCTAssertNotNil(queuedPayload?.eventId)
        XCTAssertEqual(queuedPayload?.eventId, sentPayloads.first?.eventId)
        XCTAssertEqual(queuedPayload?.eventName, Self.event(variantId: "baseline").encodedPayload().eventName)
        XCTAssertEqual(queuedPayload?.properties, Self.event(variantId: "baseline").encodedPayload().properties)
    }

    func testUITestOfflineTransportHookFailsSoftlyForRegressionScenarios() async {
        let transport = PricingAnalyticsTransportFactory.makeDefaultTransport(
            environment: ["UITEST_ANALYTICS_TRANSPORT": "offline"]
        )

        do {
            try await transport.send(Self.event(variantId: "baseline").encodedPayload())
            XCTFail("Offline UI-test transport should simulate network failure.")
        } catch let error as URLError {
            XCTAssertEqual(error.code, .notConnectedToInternet)
        } catch {
            XCTFail("Unexpected error type: \(error)")
        }
    }

    func testDefaultTransportUsesDeployedCloudflareEndpointWhenOfflineHookIsAbsent() {
        let transport = PricingAnalyticsTransportFactory.makeDefaultTransport(
            environment: [:],
            defaults: FakeUserDefaults()
        )
        XCTAssertTrue(transport is CloudflarePricingAnalyticsTransport)
    }

    func testDefaultTransportUsesCloudflareWhenEndpointIsConfigured() {
        let transport = PricingAnalyticsTransportFactory.makeDefaultTransport(
            environment: ["PRICING_ANALYTICS_ENDPOINT_URL": "https://pricing.example.workers.dev"],
            defaults: FakeUserDefaults()
        )

        XCTAssertTrue(transport is CloudflarePricingAnalyticsTransport)
    }

    func testDefaultTransportFallsBackToDeployedCloudflareEndpointWhenConfigIsPlaceholder() {
        let transport = PricingAnalyticsTransportFactory.makeDefaultTransport(
            environment: ["PRICING_ANALYTICS_ENDPOINT_URL": "$(PRICING_ANALYTICS_ENDPOINT_URL)"],
            defaults: FakeUserDefaults()
        )

        XCTAssertTrue(transport is CloudflarePricingAnalyticsTransport)
    }

    func testPricingAnalyticsInstallIDIsStableAndAnonymous() {
        let defaults = FakeUserDefaults()
        let store = PricingAnalyticsInstallIDStore(defaults: defaults)

        let first = store.installID()
        let second = store.installID()

        XCTAssertEqual(first, second)
        XCTAssertNotNil(UUID(uuidString: first))
        XCTAssertFalse(first.localizedCaseInsensitiveContains("health"))
        XCTAssertFalse(first.localizedCaseInsensitiveContains("vault"))
        XCTAssertFalse(first.localizedCaseInsensitiveContains("file"))
    }

    func testSlowTransportDoesNotBlockCallerPath() async {
        let transport = BlockingPricingAnalyticsTransport()
        let client = PricingAnalyticsClient(
            transport: transport,
            defaults: FakeUserDefaults(),
            queueKey: "pricing.analytics.test.slow",
            maxQueueSize: 3,
            isEnabled: true
        )

        let start = Date()
        client.track(Self.event(variantId: "slow_path"))
        let elapsed = Date().timeIntervalSince(start)

        XCTAssertLessThan(elapsed, 0.05, "track(_:) must return before slow network transport completes.")
        await transport.waitForAttempt()
        await transport.release()
        await client.flushAndWait()
        let queuedPayloads = await client.queuedPayloads()
        XCTAssertEqual(queuedPayloads, [])
    }

    func testQueuedPayloadsAreSanitizedBeforePersistence() async throws {
        let defaults = FakeUserDefaults()
        let client = PricingAnalyticsClient(
            transport: RecordingPricingAnalyticsTransport(error: URLError(.notConnectedToInternet)),
            defaults: defaults,
            queueKey: "pricing.analytics.test.sanitized",
            maxQueueSize: 3,
            isEnabled: true
        )

        client.track(Self.event(
            experimentId: "pricing_activation_2026_05_14",
            variantId: "variant_with_health_steps",
            appVersion: "1.2.3",
            buildNumber: "42"
        ))
        await client.flushAndWait()

        let data = try XCTUnwrap(defaults.data(forKey: "pricing.analytics.test.sanitized"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        let persisted = try XCTUnwrap(json.first)
        let properties = try XCTUnwrap(persisted["properties"] as? [String: Any])

        XCTAssertNotNil(UUID(uuidString: try XCTUnwrap(persisted["eventId"] as? String)))
        XCTAssertEqual(persisted["eventName"] as? String, "pricing_paywall_viewed")
        XCTAssertEqual(properties["appVersion"] as? String, "1.2.3")
        XCTAssertEqual(properties["buildNumber"] as? String, "42")
        XCTAssertEqual(properties["experimentId"] as? String, PricingExperimentConfig.currentExperimentId)
        XCTAssertEqual(properties["variantId"] as? String, PricingExperimentConfig.baselineVariantId)
        XCTAssertFalse(properties.values.contains { ($0 as? String) == "pricing_activation_2026_05_14" })
        XCTAssertFalse(properties.values.contains { ($0 as? String) == "variant_with_health_steps" })
        XCTAssertFalse(properties.keys.contains("healthValue"))
        XCTAssertFalse(properties.keys.contains("metricName"))
        XCTAssertFalse(properties.keys.contains("filePath"))
    }

    func testQueueIsCappedAndDropsOldestPayloads() async {
        let client = PricingAnalyticsClient(
            transport: RecordingPricingAnalyticsTransport(error: URLError(.notConnectedToInternet)),
            defaults: FakeUserDefaults(),
            queueKey: "pricing.analytics.test.cap",
            maxQueueSize: 2,
            isEnabled: true
        )

        client.track(Self.event(variantId: "first"))
        client.track(Self.event(variantId: "second"))
        client.track(Self.event(variantId: "third"))
        await client.flushAndWait()

        let queuedPayloads = await client.queuedPayloads()
        let queuedVariants = queuedPayloads.compactMap { payload -> String? in
            guard case let .string(value) = payload.properties[.variantId] else { return nil }
            return value
        }

        XCTAssertEqual(queuedVariants, ["second", "third"])
        XCTAssertTrue(queuedPayloads.allSatisfy { payload in
            guard let eventId = payload.eventId else { return false }
            return UUID(uuidString: eventId) != nil
        })
    }

    func testQueuedPayloadsRetryAfterTransientTransportFailureWithoutAdditionalTrack() async {
        let transport = FlakyPricingAnalyticsTransport(failuresBeforeSuccess: 1)
        let client = PricingAnalyticsClient(
            transport: transport,
            defaults: FakeUserDefaults(),
            queueKey: "pricing.analytics.test.retry",
            maxQueueSize: 3,
            isEnabled: true,
            retryDelayNanoseconds: 1_000_000
        )

        client.track(Self.event(variantId: "transient_retry"))

        for _ in 0..<100 {
            if await transport.attemptCountValue() >= 2 { break }
            try? await Task.sleep(nanoseconds: 10_000_000)
        }

        let attemptCount = await transport.attemptCountValue()
        let queuedPayloads = await client.queuedPayloads()
        XCTAssertEqual(attemptCount, 2)
        XCTAssertEqual(queuedPayloads, [])
    }

    func testDisabledModeRecordsNoTransportAttemptsAndDoesNotPersistQueue() async {
        let transport = RecordingPricingAnalyticsTransport()
        let defaults = FakeUserDefaults()
        let client = PricingAnalyticsClient(
            transport: transport,
            defaults: defaults,
            queueKey: "pricing.analytics.test.disabled",
            maxQueueSize: 3,
            isEnabled: false
        )

        client.track(Self.event(variantId: "disabled"))
        await client.flushAndWait()

        let attemptCount = await transport.attemptCountValue()
        let queuedPayloads = await client.queuedPayloads()
        XCTAssertEqual(attemptCount, 0)
        XCTAssertNil(defaults.data(forKey: "pricing.analytics.test.disabled"))
        XCTAssertEqual(queuedPayloads, [])
    }

    func testDefaultDebugModeIsDisabledUnlessOverridden() async {
        let transport = RecordingPricingAnalyticsTransport()
        let defaults = FakeUserDefaults()
        let client = PricingAnalyticsClient(
            transport: transport,
            defaults: defaults,
            queueKey: "pricing.analytics.test.default-debug",
            maxQueueSize: 3
        )

        client.track(Self.event(variantId: "debug_default"))
        await client.flushAndWait()

        let attemptCount = await transport.attemptCountValue()
        XCTAssertEqual(attemptCount, 0)
        XCTAssertNil(defaults.data(forKey: "pricing.analytics.test.default-debug"))
    }

    private static func event(
        experimentId: String = "pricing_activation",
        variantId: String,
        appVersion: String = "1.0",
        buildNumber: String = "1"
    ) -> PricingAnalyticsEvent {
        PricingAnalyticsEvent(
            name: .paywallViewed,
            properties: PricingAnalyticsProperties(
                experimentId: experimentId,
                variantId: variantId,
                appVersion: appVersion,
                buildNumber: buildNumber,
                platform: .iOS,
                paywallContext: .exportQuota,
                freeExportsUsed: 2,
                freeExportsRemaining: 1
            )
        )
    }
}

private actor RecordingPricingAnalyticsTransport: PricingAnalyticsTransport {
    private let error: Error?
    private(set) var payloads: [PricingAnalyticsPayload] = []
    private(set) var attemptCount = 0

    init(error: Error? = nil) {
        self.error = error
    }

    func send(_ payload: PricingAnalyticsPayload) async throws {
        attemptCount += 1
        payloads.append(payload)
        if let error {
            throw error
        }
    }

    func attemptCountValue() -> Int {
        attemptCount
    }

    func payloadsValue() -> [PricingAnalyticsPayload] {
        payloads
    }
}

private actor FlakyPricingAnalyticsTransport: PricingAnalyticsTransport {
    private var failuresRemaining: Int
    private(set) var attemptCount = 0

    init(failuresBeforeSuccess: Int) {
        self.failuresRemaining = failuresBeforeSuccess
    }

    func send(_ payload: PricingAnalyticsPayload) async throws {
        attemptCount += 1
        guard failuresRemaining > 0 else { return }

        failuresRemaining -= 1
        throw URLError(.networkConnectionLost)
    }

    func attemptCountValue() -> Int {
        attemptCount
    }
}

private actor BlockingPricingAnalyticsTransport: PricingAnalyticsTransport {
    private var attemptContinuation: CheckedContinuation<Void, Never>?
    private var releaseContinuation: CheckedContinuation<Void, Never>?
    private var hasAttempted = false
    private var isReleased = false

    func send(_ payload: PricingAnalyticsPayload) async throws {
        hasAttempted = true
        attemptContinuation?.resume()
        attemptContinuation = nil

        guard !isReleased else { return }
        await withCheckedContinuation { continuation in
            releaseContinuation = continuation
        }
    }

    func waitForAttempt() async {
        guard !hasAttempted else { return }
        await withCheckedContinuation { continuation in
            attemptContinuation = continuation
        }
    }

    func release() {
        isReleased = true
        releaseContinuation?.resume()
        releaseContinuation = nil
    }
}
