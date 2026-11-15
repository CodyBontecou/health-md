import CryptoKit
import Foundation
import HealthMdConnectionCore

/// Private signed issuer metadata, not a wire capability, permission or consent token.
nonisolated struct AgentBridgeNativeCatalogPublication: Codable, Equatable, Sendable {
    let revision: Int64
    let sourceInstallationID: AgentBridgeUUID
    let factsSHA256: AgentBridgeDigest

    func validate() throws {
        guard (1...Int64(Int32.max)).contains(revision) else { throw AgentBridgeValidationError.bindingChanged }
    }
}

extension AgentBridgeNativePlanningFacts {
    /// Native configuration/readiness facts only. The SDK/controller must not query health,
    /// provider, credentials, previews or output paths while sampling this value.
    nonisolated func fingerprint(sourceInstallationID: AgentBridgeUUID) throws -> AgentBridgeDigest {
        let object: [String: Any] = [
            // Advance this support revision when the installed planner dialect changes.
            "planning_support_revision": 1, "registry_sha256": HealthMetrics.registrySHA256,
            "platform": "apple", "source_installation_id": sourceInstallationID.rawValue,
            "available_native_metric_ids": availableNativeMetricIDs.sorted(),
            "source_calendar_timezone": sourceCalendarTimezone.rawValue,
            "configuration_protection": configurationProtection.rawValue,
            "native_grants": nativeGrants.rawValue, "entitlement": entitlement.rawValue,
            "execution_available": foregroundAvailable, "data_available": protectedDataAvailable,
        ]
        let bytes = try AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: object))
        return try AgentBridgeDigest(SHA256.hash(data: Data("HealthMd.NativePlanningFacts.v1\0".utf8) + bytes)
            .map { String(format: "%02x", $0) }.joined())
    }
}
