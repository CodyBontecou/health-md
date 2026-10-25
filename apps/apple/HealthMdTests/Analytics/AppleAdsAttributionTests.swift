import Foundation
import Testing
@testable import HealthMd

nonisolated struct AppleAdsAttributionTests {
    private static let matched = Data(#"{"attribution":true,"orgId":22465240,"campaignId":2144165887,"adGroupId":42,"keywordId":43,"claimType":"Click","conversionType":"Download","clickDate":"2026-10-24T01:00:00Z","countryOrRegion":"US"}"#.utf8)

    @Test func responseDropsUnnecessaryData() throws {
        let attribution = try AppleAdsAttribution.parse(Self.matched)
        #expect(attribution.campaignID == 2144165887)
        #expect(attribution.properties[.appleAdsClaimType] == .string("Click"))
        let stored = String(decoding: try JSONEncoder().encode(attribution), as: UTF8.self)
        #expect(!stored.contains("clickDate"))
        #expect(!stored.contains("countryOrRegion"))
        #expect(!stored.contains("2026-10-24"))
    }

    @Test @MainActor func tokenExchangeUsesOnlyAppleAndPlainText() async throws {
        ExternalIntegrationURLProtocolStub.reset()
        defer { ExternalIntegrationURLProtocolStub.reset() }
        ExternalIntegrationURLProtocolStub.setHandler { request in
            #expect(request.url?.absoluteString == "https://api-adservices.apple.com/api/v1/")
            #expect(request.httpMethod == "POST")
            #expect(request.value(forHTTPHeaderField: "Content-Type") == "text/plain")
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(String(decoding: try request.externalIntegrationHTTPBody(), as: UTF8.self) == "ephemeral-token")
            let url = try #require(request.url)
            let response = try #require(HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: nil))
            return (response, Self.matched)
        }
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ExternalIntegrationURLProtocolStub.self]
        let data = try await AppleAdsAttributionCollector.exchangeToken("ephemeral-token", session: URLSession(configuration: config))
        #expect(try AppleAdsAttribution.parse(data).matched)
    }

    @Test func unmatchedIsNotAnUnknownFailure() throws {
        let attribution = try AppleAdsAttribution.parse(Data(#"{"attribution":false}"#.utf8))
        #expect(!attribution.matched)
        #expect(attribution.campaignID == nil)
        #expect(throws: (any Error).self) { try AppleAdsAttribution.parse(Data("{}".utf8)) }
        #expect(throws: (any Error).self) {
            try AppleAdsAttribution.parse(Data(#"{"attribution":true,"orgId":1234567890,"campaignId":1234567890}"#.utf8))
        }
    }

    @Test func redactedDimensionsAndMissingClaimRemainUnknown() throws {
        let attribution = try AppleAdsAttribution.parse(Data(#"{"attribution":true,"orgId":22465240,"campaignId":-1,"keywordId":-1}"#.utf8))
        #expect(attribution.matched)
        #expect(attribution.campaignID == nil)
        #expect(attribution.keywordID == nil)
        #expect(attribution.claimType == "unknown")
    }

    @Test func resolutionPersistsAndReplaysThroughOfflineQueue() async throws {
        let defaults = FakeUserDefaults()
        let client = PricingAnalyticsClient(transport: OfflinePricingAnalyticsTransport(), defaults: defaults,
                                           isEnabled: true, retryDelayNanoseconds: 0)
        let collector = AppleAdsAttributionCollector(defaults: defaults, token: { "ephemeral-token" },
                                                     exchange: { _ in Self.matched }, pause: {})
        await collector.collect { client.trackAppleAdsAttribution($0) }
        await collector.collect { client.trackAppleAdsAttribution($0) }
        await client.flushAndWait()
        let queued = await client.queuedPayloads()
        #expect(queued.count == 1)
        #expect(queued.first?.properties[.appleAdsCampaignId] == .int(2144165887))
        let replay = AppleAdsAttributionCollector(defaults: defaults, token: { throw URLError(.unknown) })
        await replay.collect { client.trackAppleAdsAttribution($0) }
        await client.flushAndWait()
        #expect(await client.queuedPayloads().count == 2) // Worker deduplicates these by install.
        let data = try JSONEncoder().encode(await client.queuedPayloads())
        #expect(!String(decoding: data, as: UTF8.self).contains("ephemeral-token"))
    }

    @Test func failureDoesNotCacheUnmatchedAndCanRecoverOnNextLaunch() async {
        let defaults = FakeUserDefaults()
        let client = PricingAnalyticsClient(transport: OfflinePricingAnalyticsTransport(), defaults: defaults,
                                           isEnabled: true, retryDelayNanoseconds: 0)
        let failures = AttributionExchangeProbe()
        let collector = AppleAdsAttributionCollector(defaults: defaults, token: { "token" },
            exchange: { _ in try await failures.fail() }, pause: {})
        await collector.collect { client.trackAppleAdsAttribution($0) }
        #expect(await failures.attempts == 3)
        #expect(await client.queuedPayloads().isEmpty)
        let retry = AppleAdsAttributionCollector(defaults: defaults, token: { "fresh-token" },
                                                 exchange: { _ in Self.matched }, pause: {})
        await retry.collect { client.trackAppleAdsAttribution($0) }
        #expect(await client.queuedPayloads().count == 1)
    }
}

private actor AttributionExchangeProbe {
    var attempts = 0
    func fail() throws -> Data { attempts += 1; throw URLError(.notConnectedToInternet) }
}
