//
//  CloudflarePricingAnalyticsTransport.swift
//  HealthMd
//
//  Production transport for privacy-safe pricing analytics ingestion.
//

import Foundation

nonisolated final class CloudflarePricingAnalyticsTransport: PricingAnalyticsTransport, @unchecked Sendable {
    private static let endpointInfoKey = "PRICING_ANALYTICS_ENDPOINT_URL"
    private static let tokenInfoKey = "PRICING_ANALYTICS_INGEST_TOKEN"
    private static let defaultProductionEndpointURLString = "https://health-md-pricing-analytics.costream.workers.dev"

    private let endpointURL: URL
    private let ingestToken: String?
    private let installIDStore: PricingAnalyticsInstallIDStore
    private let session: URLSession

    init(
        endpointURL: URL,
        ingestToken: String? = nil,
        installIDStore: PricingAnalyticsInstallIDStore = PricingAnalyticsInstallIDStore(),
        session: URLSession = .shared
    ) {
        self.endpointURL = Self.eventsURL(from: endpointURL)
        self.ingestToken = Self.sanitizedToken(ingestToken)
        self.installIDStore = installIDStore
        self.session = session
    }

    func send(_ payload: PricingAnalyticsPayload) async throws {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.timeoutInterval = 10

        if let ingestToken {
            request.setValue("Bearer \(ingestToken)", forHTTPHeaderField: "Authorization")
        }

        request.httpBody = try JSONEncoder().encode(PricingAnalyticsIngestEnvelope(
            installId: installIDStore.installID(),
            events: [payload]
        ))

        let (_, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode) else {
            throw URLError(.badServerResponse)
        }
    }

    static func configured(
        environment: [String: String] = ProcessInfo.processInfo.environment,
        bundle: Bundle = .main,
        defaults: UserDefaultsStoring = SystemUserDefaults()
    ) -> CloudflarePricingAnalyticsTransport? {
        guard let endpointURL = configuredEndpointURL(environment: environment, bundle: bundle) else {
            return nil
        }

        return CloudflarePricingAnalyticsTransport(
            endpointURL: endpointURL,
            ingestToken: configuredToken(environment: environment, bundle: bundle),
            installIDStore: PricingAnalyticsInstallIDStore(defaults: defaults)
        )
    }

    private static func configuredEndpointURL(
        environment: [String: String],
        bundle: Bundle
    ) -> URL? {
        let value = [
            environment[endpointInfoKey],
            bundle.object(forInfoDictionaryKey: endpointInfoKey) as? String,
            defaultProductionEndpointURLString
        ]
        .compactMap(sanitizedConfigValue)
        .first

        guard let value,
              let url = URL(string: value),
              let scheme = url.scheme?.lowercased(),
              ["https", "http"].contains(scheme),
              let host = url.host,
              !host.isEmpty else {
            return nil
        }

        #if DEBUG
        if scheme == "http" {
            let localHosts = ["localhost", "127.0.0.1", "::1"]
            guard localHosts.contains(host) else { return nil }
        }
        #else
        guard scheme == "https" else { return nil }
        #endif

        return url
    }

    private static func configuredToken(environment: [String: String], bundle: Bundle) -> String? {
        let rawValue = environment[tokenInfoKey]
            ?? bundle.object(forInfoDictionaryKey: tokenInfoKey) as? String
        return sanitizedToken(rawValue)
    }

    private static func eventsURL(from endpointURL: URL) -> URL {
        let normalizedPath = endpointURL.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        if normalizedPath == "v1/events" || normalizedPath.hasSuffix("/v1/events") {
            guard var components = URLComponents(url: endpointURL, resolvingAgainstBaseURL: false) else {
                return endpointURL
            }
            components.path = "/\(normalizedPath)"
            return components.url ?? endpointURL
        }

        return endpointURL
            .appendingPathComponent("v1")
            .appendingPathComponent("events")
    }

    private static func sanitizedToken(_ rawValue: String?) -> String? {
        sanitizedConfigValue(rawValue)
    }

    private static func sanitizedConfigValue(_ rawValue: String?) -> String? {
        guard let rawValue else { return nil }
        let value = rawValue.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !value.isEmpty,
              !value.contains("$("),
              !value.localizedCaseInsensitiveContains("replace_with"),
              !value.localizedCaseInsensitiveContains("your_") else {
            return nil
        }
        return value
    }
}

nonisolated final class PricingAnalyticsInstallIDStore: @unchecked Sendable {
    private static let defaultKey = "pricing.analytics.install_id.v1"

    private let defaults: UserDefaultsStoring
    private let key: String
    private let queue = DispatchQueue(label: "com.codybontecou.healthmd.pricing-analytics-install-id")

    init(
        defaults: UserDefaultsStoring = SystemUserDefaults(),
        key: String = PricingAnalyticsInstallIDStore.defaultKey
    ) {
        self.defaults = defaults
        self.key = key
    }

    func installID() -> String {
        queue.sync {
            if let existing = defaults.string(forKey: key), Self.isValidInstallID(existing) {
                return existing.lowercased()
            }

            let generated = UUID().uuidString.lowercased()
            defaults.set(generated, forKey: key)
            return generated
        }
    }

    private static func isValidInstallID(_ value: String) -> Bool {
        UUID(uuidString: value) != nil
    }
}

nonisolated private struct PricingAnalyticsIngestEnvelope: Encodable {
    let installId: String
    let events: [PricingAnalyticsPayload]
}
