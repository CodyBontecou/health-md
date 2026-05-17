//
//  PricingAnalyticsTransport.swift
//  HealthMd
//
//  Transport seam for offline-safe pricing analytics.
//

import Foundation

nonisolated protocol PricingAnalyticsTransport: Sendable {
    func send(_ payload: PricingAnalyticsPayload) async throws
}

nonisolated enum PricingAnalyticsTransportFactory {
    static func makeDefaultTransport(
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PricingAnalyticsTransport {
        #if DEBUG
        if environment["UITEST_ANALYTICS_TRANSPORT"] == "offline" {
            return OfflinePricingAnalyticsTransport()
        }
        #endif

        return NoOpPricingAnalyticsTransport()
    }
}

nonisolated struct NoOpPricingAnalyticsTransport: PricingAnalyticsTransport {
    func send(_ payload: PricingAnalyticsPayload) async throws {}
}

nonisolated struct OfflinePricingAnalyticsTransport: PricingAnalyticsTransport {
    func send(_ payload: PricingAnalyticsPayload) async throws {
        throw URLError(.notConnectedToInternet)
    }
}
