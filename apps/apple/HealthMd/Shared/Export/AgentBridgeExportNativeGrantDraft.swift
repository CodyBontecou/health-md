import Foundation
import HealthMdConnectionCore

/// Native review model only. Construction validates a description; it never enrolls a grant.
nonisolated enum AgentBridgeExportNativeGrantDraft {
    // The callable source planner currently supports these reviewed summary metrics and JSON only.
    static let metricIDs = ["heart_rate_avg", "heart_rate_max", "heart_rate_min", "hrv", "resting_heart_rate", "steps"]

    static func make(peer: AgentBridgePeer, metrics: Set<String>, start: String, end: String,
                     timezone: String, expiresAt: Date, now: Date,
                     id: UUID = UUID()) throws -> AgentBridgeExportDelegation {
        guard peer.platform == .apple, !metrics.isEmpty, metrics.isSubset(of: Set(metricIDs)),
              expiresAt > now else { throw AgentBridgeValidationError.invalidRequest }
        let first = try AgentBridgeDate(start), last = try AgentBridgeDate(end)
        let parser = ISO8601DateFormatter()
        guard let firstDate = parser.date(from: start + "T00:00:00Z"),
              let lastDate = parser.date(from: end + "T00:00:00Z") else { throw AgentBridgeValidationError.invalidRequest }
        let days = Int64(lastDate.timeIntervalSince(firstDate) / 86_400) + 1
        guard start <= end, (1...366_000).contains(days) else { throw AgentBridgeValidationError.invalidRequest }
        let canonicalExpiry = parser.string(from: expiresAt)
        guard let encodedExpiry = parser.date(from: canonicalExpiry), encodedExpiry > now else {
            throw AgentBridgeValidationError.invalidRequest
        }
        let value = try AgentBridgeExportDelegation(authorityID: AgentBridgeUUID(id.uuidString.lowercased()),
            issuer: .nativeSource, grantRevision: 1, peer: peer, rights: [.discover, .exportExecute, .plan],
            expiresAt: AgentBridgeUTC(canonicalExpiry),
            bounds: .init(products: [.generatedFiles], projectionDetails: [], projectionObjectIDs: [], projectionFieldIDs: [],
                metricIDs: metrics.sorted().map { try AgentBridgeID($0) }, calendarTimezones: [AgentBridgeZone(timezone)],
                datePolicy: .boundedExact(range: .init(startDate: first, endDate: last), maxDays: days),
                formats: [.json], outputProfiles: [.appleV8], writeModes: [.overwrite], compatibilityDetail: [.summary],
                nativeArchiveProducts: [.none], destinationPolicy: .authenticatedHostBindings))
        // Strict native/source codec validation, including real dates and sorted bounds.
        return try AgentBridgeV4Codec.decode(AgentBridgeExportDelegation.self, from: AgentBridgeV4Codec.encode(value))
    }
}
