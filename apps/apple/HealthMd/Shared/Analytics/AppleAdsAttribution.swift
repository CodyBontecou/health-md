import Foundation
#if os(iOS) && canImport(AdServices)
import AdServices
#endif

/// Only campaign dimensions leave the Apple response. Tokens, location and click
/// timestamps never enter the analytics queue or local storage.
nonisolated struct AppleAdsAttribution: Codable, Equatable, Sendable {
    let matched: Bool
    let campaignID: Int?
    let adGroupID: Int?
    let keywordID: Int?
    let claimType: String
    let conversionType: String

    static func parse(_ data: Data) throws -> Self {
        let response = try JSONDecoder().decode(Response.self, from: data)
        guard response.attribution else {
            return Self(matched: false, campaignID: nil, adGroupID: nil, keywordID: nil,
                        claimType: "unknown", conversionType: "unknown")
        }
        // Developer Mode returns synthetic attribution. Never mix it or another
        // advertiser's response into production acquisition counts.
        guard response.orgId == 22465240 else { throw URLError(.cannotParseResponse) }
        return Self(matched: true, campaignID: validID(response.campaignId),
                    adGroupID: validID(response.adGroupId), keywordID: validID(response.keywordId),
                    claimType: ["Click", "Impression"].contains(response.claimType ?? "") ? (response.claimType ?? "unknown") : "unknown",
                    conversionType: ["Download", "Redownload"].contains(response.conversionType ?? "") ? (response.conversionType ?? "unknown") : "unknown")
    }

    private static func validID(_ value: Int?) -> Int? {
        guard let value, (1...9_007_199_254_740_991).contains(value) else { return nil }
        return value
    }

    var properties: [PricingAnalyticsPropertyKey: PricingAnalyticsValue] {
        var result: [PricingAnalyticsPropertyKey: PricingAnalyticsValue] = [
            .appleAdsStatus: .string(matched ? "matched" : "unmatched"),
            .appleAdsClaimType: .string(claimType),
            .appleAdsConversionType: .string(conversionType),
            .platform: .string("ios")
        ]
        if let campaignID { result[.appleAdsCampaignId] = .int(campaignID) }
        if let adGroupID { result[.appleAdsAdGroupId] = .int(adGroupID) }
        if let keywordID { result[.appleAdsKeywordId] = .int(keywordID) }
        return result
    }

    nonisolated private struct Response: Decodable {
        let attribution: Bool
        let orgId: Int?
        let campaignId: Int?
        let adGroupId: Int?
        let keywordId: Int?
        let claimType: String?
        let conversionType: String?
    }
}

/// One bounded, asynchronous resolution per process. Failed resolutions retry on
/// a later launch. A cached result is re-enqueued on launch, so a full offline
/// queue cannot permanently lose it; ingestion deduplicates by installation.
actor AppleAdsAttributionCollector {
    typealias TokenProvider = @Sendable () throws -> String
    typealias Exchange = @Sendable (String) async throws -> Data
    private let defaults: UserDefaultsStoring
    private let token: TokenProvider
    private let exchange: Exchange
    private let pause: @Sendable () async throws -> Void
    private var started = false
    private static let cacheKey = "analytics.apple_ads.attribution.v1"

    init(defaults: UserDefaultsStoring = SystemUserDefaults(),
         token: @escaping TokenProvider,
         exchange: @escaping Exchange = { try await AppleAdsAttributionCollector.exchangeToken($0) },
         pause: @escaping @Sendable () async throws -> Void = { try await Task.sleep(for: .seconds(5)) }) {
        self.defaults = defaults
        self.token = token
        self.exchange = exchange
        self.pause = pause
    }

    func collect(report: @Sendable (AppleAdsAttribution) -> Void) async {
        guard !started else { return }
        started = true
        if let data = defaults.data(forKey: Self.cacheKey),
           let cached = try? JSONDecoder().decode(AppleAdsAttribution.self, from: data) {
            report(cached)
            return
        }
        guard let token = try? token() else { return }
        for attempt in 0..<3 {
            do {
                try Task.checkCancellation()
                let result = try AppleAdsAttribution.parse(await exchange(token))
                defaults.set(try JSONEncoder().encode(result), forKey: Self.cacheKey)
                report(result)
                return
            } catch is CancellationError {
                return
            } catch {
                // No result is unknown, never organic/unmatched. No raw errors,
                // Apple response or token are logged or persisted.
                if attempt < 2 {
                    do { try await pause() } catch { return }
                }
            }
        }
    }

    nonisolated static func startProduction(start: @Sendable () -> Void, report: @escaping @Sendable (AppleAdsAttribution) -> Void) {
        #if os(iOS) && !targetEnvironment(simulator) && !DEBUG && canImport(AdServices)
        start()
        Task { await production.collect(report: report) }
        #endif
    }

    #if os(iOS) && !targetEnvironment(simulator) && !DEBUG && canImport(AdServices)
    private static let production = AppleAdsAttributionCollector(token: { try AAAttribution.attributionToken() })
    #endif

    nonisolated static func exchangeToken(_ token: String, session suppliedSession: URLSession? = nil) async throws -> Data {
        var request = URLRequest(url: URL(string: "https://api-adservices.apple.com/api/v1/")!)
        request.httpMethod = "POST"
        request.setValue("text/plain", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data(token.utf8)
        request.timeoutInterval = 10
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        let session = suppliedSession ?? URLSession(configuration: configuration)
        defer { session.invalidateAndCancel() }
        let (data, response) = try await session.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200, data.count <= 16_384 else {
            throw URLError(.badServerResponse)
        }
        return data
    }
}
