//
//  PricingAnalyticsEvent.swift
//  HealthMd
//
//  Privacy-safe event model for pricing and activation analytics.
//

import Foundation

/// Privacy contract for pricing analytics:
/// - Allowed: experiment/variant IDs, app version/build, platform, paywall
///   context, free-export counts, export target type, format count, metric/date
///   buckets, purchase product ID, purchase outcome, and coarse error category.
/// - Prohibited: health values, Apple Health identifiers, metric names,
///   medication or workout details, absolute health dates/timestamps, export
///   contents, paths, folder or vault names, peer device names, and user text.
///
/// This model is deliberately local and transport-free. Future sinks should
/// consume `encodedPayload()` and must not add keys outside
/// `PricingAnalyticsPropertyKey`.
nonisolated struct PricingAnalyticsEvent: Equatable, Sendable {
    let name: PricingAnalyticsEventName
    let properties: PricingAnalyticsProperties

    init(name: PricingAnalyticsEventName, properties: PricingAnalyticsProperties = PricingAnalyticsProperties()) {
        self.name = name
        self.properties = properties
    }

    func encodedPayload() -> PricingAnalyticsPayload {
        PricingAnalyticsPayload(
            eventName: name.rawValue,
            properties: properties.encodedProperties()
        )
    }
}

nonisolated enum PricingAnalyticsEventName: String, CaseIterable, Sendable {
    case paywallViewed = "pricing_paywall_viewed"
    case paywallCTATapped = "pricing_paywall_cta_tapped"
    case exportBlockedByQuota = "pricing_export_blocked_by_quota"
    case purchaseStarted = "pricing_purchase_started"
    case purchaseFinished = "pricing_purchase_finished"
}

nonisolated struct PricingAnalyticsPayload: Equatable, Sendable, Codable {
    let eventName: String
    let properties: [PricingAnalyticsPropertyKey: PricingAnalyticsValue]

    var transportProperties: [String: PricingAnalyticsValue] {
        Dictionary(uniqueKeysWithValues: properties.map { ($0.key.rawValue, $0.value) })
    }

    private enum CodingKeys: String, CodingKey {
        case eventName
        case properties
    }

    init(eventName: String, properties: [PricingAnalyticsPropertyKey: PricingAnalyticsValue]) {
        self.eventName = eventName
        self.properties = properties
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let eventName = try container.decode(String.self, forKey: .eventName)
        let transportProperties = try container.decode(
            [String: PricingAnalyticsValue].self,
            forKey: .properties
        )

        self.eventName = eventName
        self.properties = Dictionary(
            uniqueKeysWithValues: transportProperties.compactMap { key, value in
                guard let propertyKey = PricingAnalyticsPropertyKey(rawValue: key) else { return nil }
                return (propertyKey, value)
            }
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(eventName, forKey: .eventName)
        try container.encode(transportProperties, forKey: .properties)
    }
}

nonisolated enum PricingAnalyticsPropertyKey: String, CaseIterable, Sendable {
    case experimentId
    case variantId
    case appVersion
    case buildNumber
    case platform
    case paywallContext
    case freeExportsUsed
    case freeExportsRemaining
    case exportTargetType
    case formatCount
    case metricCountBucket
    case dateRangePreset
    case dateSpanBucket
    case productId
    case purchaseOutcome
    case errorCategory
}

nonisolated enum PricingAnalyticsValue: Equatable, Sendable, Codable {
    case string(String)
    case int(Int)

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let intValue = try? container.decode(Int.self) {
            self = .int(intValue)
            return
        }

        if let stringValue = try? container.decode(String.self) {
            self = .string(stringValue)
            return
        }

        throw DecodingError.typeMismatch(
            PricingAnalyticsValue.self,
            DecodingError.Context(
                codingPath: decoder.codingPath,
                debugDescription: "Expected pricing analytics value to be a string or integer."
            )
        )
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()

        switch self {
        case .string(let value):
            try container.encode(value)
        case .int(let value):
            try container.encode(value)
        }
    }
}

nonisolated struct PricingAnalyticsProperties: Equatable, Sendable {
    private let experimentId: String?
    private let variantId: String?
    private let appVersion: String?
    private let buildNumber: String?
    private let platform: PricingAnalyticsPlatform?
    private let paywallContext: PricingAnalyticsPaywallContext?
    private let freeExportsUsed: Int?
    private let freeExportsRemaining: Int?
    private let exportTargetType: PricingAnalyticsExportTargetType?
    private let formatCount: Int?
    private let metricCountBucket: PricingAnalyticsMetricCountBucket?
    private let dateRangePreset: PricingAnalyticsDateRangePreset?
    private let dateSpanBucket: PricingAnalyticsDateSpanBucket?
    private let productId: PricingAnalyticsProductID?
    private let purchaseOutcome: PricingAnalyticsPurchaseOutcome?
    private let errorCategory: PricingAnalyticsErrorCategory?

    init(
        experimentId: String? = nil,
        variantId: String? = nil,
        appVersion: String? = nil,
        buildNumber: String? = nil,
        platform: PricingAnalyticsPlatform? = nil,
        paywallContext: PricingAnalyticsPaywallContext? = nil,
        freeExportsUsed: Int? = nil,
        freeExportsRemaining: Int? = nil,
        exportTargetType: PricingAnalyticsExportTargetType? = nil,
        formatCount: Int? = nil,
        metricCountBucket: PricingAnalyticsMetricCountBucket? = nil,
        dateRangePreset: PricingAnalyticsDateRangePreset? = nil,
        dateSpanBucket: PricingAnalyticsDateSpanBucket? = nil,
        productId: PricingAnalyticsProductID? = nil,
        purchaseOutcome: PricingAnalyticsPurchaseOutcome? = nil,
        errorCategory: PricingAnalyticsErrorCategory? = nil
    ) {
        self.experimentId = PricingAnalyticsSanitizer.sanitizedIdentifier(experimentId)
        self.variantId = PricingAnalyticsSanitizer.sanitizedIdentifier(variantId)
        self.appVersion = PricingAnalyticsSanitizer.sanitizedAppVersion(appVersion)
        self.buildNumber = PricingAnalyticsSanitizer.sanitizedBuildNumber(buildNumber)
        self.platform = platform
        self.paywallContext = paywallContext
        self.freeExportsUsed = PricingAnalyticsSanitizer.sanitizedCount(
            freeExportsUsed,
            in: PricingAnalyticsLimits.freeExportCountRange
        )
        self.freeExportsRemaining = PricingAnalyticsSanitizer.sanitizedCount(
            freeExportsRemaining,
            in: PricingAnalyticsLimits.freeExportCountRange
        )
        self.exportTargetType = exportTargetType
        self.formatCount = PricingAnalyticsSanitizer.sanitizedCount(
            formatCount,
            in: PricingAnalyticsLimits.formatCountRange
        )
        self.metricCountBucket = metricCountBucket
        self.dateRangePreset = dateRangePreset
        self.dateSpanBucket = dateSpanBucket
        self.productId = productId
        self.purchaseOutcome = purchaseOutcome
        self.errorCategory = errorCategory
    }

    func encodedProperties() -> [PricingAnalyticsPropertyKey: PricingAnalyticsValue] {
        var encoded: [PricingAnalyticsPropertyKey: PricingAnalyticsValue] = [:]

        encode(experimentId, for: .experimentId, into: &encoded)
        encode(variantId, for: .variantId, into: &encoded)
        encode(appVersion, for: .appVersion, into: &encoded)
        encode(buildNumber, for: .buildNumber, into: &encoded)
        encode(platform?.rawValue, for: .platform, into: &encoded)
        encode(paywallContext?.rawValue, for: .paywallContext, into: &encoded)
        encode(freeExportsUsed, for: .freeExportsUsed, into: &encoded)
        encode(freeExportsRemaining, for: .freeExportsRemaining, into: &encoded)
        encode(exportTargetType?.rawValue, for: .exportTargetType, into: &encoded)
        encode(formatCount, for: .formatCount, into: &encoded)
        encode(metricCountBucket?.rawValue, for: .metricCountBucket, into: &encoded)
        encode(dateRangePreset?.rawValue, for: .dateRangePreset, into: &encoded)
        encode(dateSpanBucket?.rawValue, for: .dateSpanBucket, into: &encoded)
        encode(productId?.rawValue, for: .productId, into: &encoded)
        encode(purchaseOutcome?.rawValue, for: .purchaseOutcome, into: &encoded)
        encode(errorCategory?.rawValue, for: .errorCategory, into: &encoded)

        return encoded
    }

    private func encode(
        _ value: String?,
        for key: PricingAnalyticsPropertyKey,
        into encoded: inout [PricingAnalyticsPropertyKey: PricingAnalyticsValue]
    ) {
        guard let value else { return }
        encoded[key] = .string(value)
    }

    private func encode(
        _ value: Int?,
        for key: PricingAnalyticsPropertyKey,
        into encoded: inout [PricingAnalyticsPropertyKey: PricingAnalyticsValue]
    ) {
        guard let value else { return }
        encoded[key] = .int(value)
    }
}

nonisolated enum PricingAnalyticsPlatform: String, CaseIterable, Sendable {
    case iOS = "ios"
    case macOS = "macos"
}

nonisolated enum PricingAnalyticsPaywallContext: String, CaseIterable, Sendable {
    case onboarding
    case exportQuota = "export_quota"
    case settings
    case restore
}

nonisolated enum PricingAnalyticsExportTargetType: String, CaseIterable, Sendable {
    case localFile = "local_file"
    case connectedMac = "connected_mac"
    case previewOnly = "preview_only"
}

nonisolated enum PricingAnalyticsMetricCountBucket: String, CaseIterable, Sendable {
    case zero = "0"
    case oneToFive = "1_5"
    case sixToTen = "6_10"
    case elevenToTwenty = "11_20"
    case twentyOnePlus = "21_plus"
}

nonisolated enum PricingAnalyticsDateRangePreset: String, CaseIterable, Sendable {
    case today
    case yesterday
    case lastSevenDays = "last_7_days"
    case lastThirtyDays = "last_30_days"
    case custom
}

nonisolated enum PricingAnalyticsDateSpanBucket: String, CaseIterable, Sendable {
    case sameDay = "same_day"
    case oneToSevenDays = "1_7_days"
    case eightToThirtyDays = "8_30_days"
    case thirtyOneToNinetyDays = "31_90_days"
    case ninetyOnePlusDays = "91_plus_days"
}

nonisolated enum PricingAnalyticsProductID: String, CaseIterable, Sendable {
    case lifetimeUnlock = "com.codybontecou.obsidianhealth.unlock"
}

nonisolated enum PricingAnalyticsPurchaseOutcome: String, CaseIterable, Sendable {
    case started
    case succeeded
    case failed
    case cancelled
    case pending
}

nonisolated enum PricingAnalyticsErrorCategory: String, CaseIterable, Sendable {
    case networkUnavailable = "network_unavailable"
    case storeUnavailable = "store_unavailable"
    case userCancelled = "user_cancelled"
    case paymentNotAllowed = "payment_not_allowed"
    case verificationFailed = "verification_failed"
    case unknown
}

nonisolated private enum PricingAnalyticsLimits {
    static let freeExportCountRange = 0...3
    static let formatCountRange = 1...4
}

nonisolated private enum PricingAnalyticsSanitizer {
    private static let identifierCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-"
    )
    private static let digitCharacters = CharacterSet(charactersIn: "0123456789")
    private static let versionCharacters = CharacterSet(charactersIn: "0123456789.")
    private static let sensitiveTokens = [
        "hkquantity",
        "hkcategory",
        "hkcorrelation",
        "hksample",
        "step",
        "heart",
        "blood",
        "sleep",
        "workout",
        "medication",
        "medicine",
        "metformin",
        "insulin",
        "dose",
        "health",
        "calorie",
        "energy",
        "distance",
        "weight",
        "body",
        "mindful",
        "respiratory",
        "vault",
        "folder",
        "file",
        "obsidian",
        "documents",
        "desktop",
        "downloads",
        "icloud"
    ]

    static func sanitizedIdentifier(_ rawValue: String?) -> String? {
        guard let value = trimmed(rawValue), value.count <= 80 else { return nil }
        guard value == value.lowercased() else { return nil }
        guard containsOnly(value, characters: identifierCharacters) else { return nil }
        guard !containsRawDate(value) else { return nil }
        guard !containsSensitiveToken(value) else { return nil }
        return value
    }

    static func sanitizedAppVersion(_ rawValue: String?) -> String? {
        guard let value = trimmed(rawValue), value.count <= 20 else { return nil }
        guard containsOnly(value, characters: versionCharacters) else { return nil }
        let parts = value.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...4).contains(parts.count) else { return nil }
        guard parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return nil }
        return value
    }

    static func sanitizedBuildNumber(_ rawValue: String?) -> String? {
        guard let value = trimmed(rawValue), (1...12).contains(value.count) else { return nil }
        guard containsOnly(value, characters: digitCharacters) else { return nil }
        return value
    }

    static func sanitizedCount(_ value: Int?, in range: ClosedRange<Int>) -> Int? {
        guard let value, range.contains(value) else { return nil }
        return value
    }

    private static func trimmed(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        return value.isEmpty ? nil : value
    }

    private static func containsOnly(_ value: String, characters: CharacterSet) -> Bool {
        value.unicodeScalars.allSatisfy { characters.contains($0) }
    }

    private static func containsRawDate(_ value: String) -> Bool {
        let datePatterns = [
            #"(?:^|[^0-9])(?:19|20)\d{2}[-_.](?:0[1-9]|1[0-2])[-_.](?:0[1-9]|[12]\d|3[01])(?:$|[^0-9])"#,
            #"(?:^|[^0-9])(?:19|20)\d{2}(?:0[1-9]|1[0-2])(?:0[1-9]|[12]\d|3[01])(?:$|[^0-9])"#
        ]

        return datePatterns.contains { pattern in
            value.range(of: pattern, options: .regularExpression) != nil
        }
    }

    private static func containsSensitiveToken(_ value: String) -> Bool {
        let normalized = value
            .replacingOccurrences(of: ".", with: "_")
            .replacingOccurrences(of: "-", with: "_")
            .lowercased()

        return sensitiveTokens.contains { normalized.contains($0) }
    }
}
