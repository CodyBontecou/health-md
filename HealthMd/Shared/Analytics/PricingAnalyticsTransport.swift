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

nonisolated struct NoOpPricingAnalyticsTransport: PricingAnalyticsTransport {
    func send(_ payload: PricingAnalyticsPayload) async throws {}
}
