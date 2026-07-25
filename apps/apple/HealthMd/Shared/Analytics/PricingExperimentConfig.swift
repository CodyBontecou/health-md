//
//  PricingExperimentConfig.swift
//  HealthMd
//
//  Offline-safe pricing experiment configuration.
//

import Foundation

nonisolated struct PricingExperimentConfig: Equatable, Sendable {
    static let currentExperimentId = "pricing_lifetime_offers"
    static let baselineVariantId = "baseline_lifetime_only"
    static let testVariantId = "lifetime_offer_mix"

    static let baseline = PricingExperimentConfig(
        validatedExperimentId: currentExperimentId,
        variantId: baselineVariantId,
        productIdOverride: nil,
        isProductIDOverrideEnabled: false
    )

    let experimentId: String
    let variantId: String
    let productIdOverride: String?
    let isProductIDOverrideEnabled: Bool

    init?(
        experimentId: String,
        variantId: String,
        productIdOverride: String? = nil,
        isProductIDOverrideEnabled: Bool = false
    ) {
        guard Self.knownExperimentIds.contains(experimentId),
              Self.knownVariantIds.contains(variantId),
              PricingExperimentIdentifierValidator.isSafeIdentifier(experimentId),
              PricingExperimentIdentifierValidator.isSafeIdentifier(variantId) else {
            return nil
        }

        let validatedProductIdOverride: String?
        if isProductIDOverrideEnabled {
            if let productIdOverride {
                guard Self.isValidProductID(productIdOverride) else { return nil }
                validatedProductIdOverride = productIdOverride
            } else {
                validatedProductIdOverride = nil
            }
        } else {
            validatedProductIdOverride = nil
        }

        self.init(
            validatedExperimentId: experimentId,
            variantId: variantId,
            productIdOverride: validatedProductIdOverride,
            isProductIDOverrideEnabled: isProductIDOverrideEnabled
        )
    }

    static func resolved(
        from data: Data?,
        environment: [String: String] = ProcessInfo.processInfo.environment
    ) -> PricingExperimentConfig {
        #if DEBUG
        if environment["UITEST_REMOTE_CONFIG"] == "offline" {
            return .baseline
        }
        #endif

        guard let data else { return .baseline }

        let decoder = JSONDecoder()
        guard let rawConfig = try? decoder.decode(RawPricingExperimentConfig.self, from: data),
              let experimentId = rawConfig.experimentId,
              let variantId = rawConfig.variantId,
              let config = PricingExperimentConfig(
                experimentId: experimentId,
                variantId: variantId,
                productIdOverride: rawConfig.productIdOverride,
                isProductIDOverrideEnabled: rawConfig.isProductIDOverrideEnabled
              ) else {
            return .baseline
        }

        return config
    }

    /// Product switching is intentionally opt-in. True randomized price tests
    /// require distinct App Store Connect products mapped to the same entitlement;
    /// the first sequential price test should keep using the current product ID.
    func effectiveProductID(defaultProductID: String) -> String {
        guard isProductIDOverrideEnabled,
              let productIdOverride else {
            return defaultProductID
        }

        return productIdOverride
    }

    private init(
        validatedExperimentId experimentId: String,
        variantId: String,
        productIdOverride: String?,
        isProductIDOverrideEnabled: Bool
    ) {
        self.experimentId = experimentId
        self.variantId = variantId
        self.productIdOverride = productIdOverride
        self.isProductIDOverrideEnabled = isProductIDOverrideEnabled
    }

    private static let knownExperimentIds: Set<String> = [
        currentExperimentId
    ]

    private static let knownVariantIds: Set<String> = [
        baselineVariantId,
        testVariantId
    ]

    static func isValidProductID(_ value: String) -> Bool {
        let trimmedValue = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard trimmedValue == value,
              (1...120).contains(value.count),
              value.contains("."),
              !value.contains("..") else {
            return false
        }

        let allowedCharacters = CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._-")
        return value.unicodeScalars.allSatisfy { allowedCharacters.contains($0) }
    }
}

nonisolated private struct RawPricingExperimentConfig: Decodable {
    let experimentId: String?
    let variantId: String?
    let productIdOverride: String?
    let isProductIDOverrideEnabled: Bool

    private enum CodingKeys: String, CodingKey {
        case experimentId
        case variantId
        case productIdOverride
        case productIDOverride
        case isProductIDOverrideEnabled
        case isProductIdOverrideEnabled
        case productIDOverrideEnabled
        case productIdOverrideEnabled
        case productSelectionEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.experimentId = try container.decodeIfPresent(String.self, forKey: .experimentId)
        self.variantId = try container.decodeIfPresent(String.self, forKey: .variantId)

        if let productIdOverride = try container.decodeIfPresent(String.self, forKey: .productIdOverride) {
            self.productIdOverride = productIdOverride
        } else {
            self.productIdOverride = try container.decodeIfPresent(String.self, forKey: .productIDOverride)
        }

        let enabledValues = [
            try container.decodeIfPresent(Bool.self, forKey: .isProductIDOverrideEnabled),
            try container.decodeIfPresent(Bool.self, forKey: .isProductIdOverrideEnabled),
            try container.decodeIfPresent(Bool.self, forKey: .productIDOverrideEnabled),
            try container.decodeIfPresent(Bool.self, forKey: .productIdOverrideEnabled),
            try container.decodeIfPresent(Bool.self, forKey: .productSelectionEnabled)
        ]
        self.isProductIDOverrideEnabled = enabledValues.compactMap { $0 }.first ?? false
    }
}

nonisolated private enum PricingExperimentIdentifierValidator {
    private static let identifierCharacters = CharacterSet(
        charactersIn: "abcdefghijklmnopqrstuvwxyz0123456789._-"
    )
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

    static func isSafeIdentifier(_ rawValue: String) -> Bool {
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard value == rawValue,
              !value.isEmpty,
              value.count <= 80,
              value == value.lowercased(),
              value.unicodeScalars.allSatisfy({ identifierCharacters.contains($0) }),
              !containsRawDate(value),
              !containsSensitiveToken(value) else {
            return false
        }

        return true
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
