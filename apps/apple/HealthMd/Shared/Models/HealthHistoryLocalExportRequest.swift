import CryptoKit
import Foundation
import HealthMdConnectionCore

/// Immutable authority for one newly admitted local/API capture. This is not a
/// daily-export schema and is not emitted until the destination receipt adopts it.
/// Resume must retain the original request rather than reconstruct it from UI state.
@MainActor
struct HealthHistoryLocalExportRequest {
    enum Target: String, Encodable {
        case localFiles = "local_files"
        case apiEndpoint = "api_endpoint"
    }

    enum ValidationError: Error { case invalidRequest, mismatchedAssessment }

    let operationID: UUID
    let scope: HealthHistoryScope
    let settings: ExportSettingsSnapshot
    let captureDates: [Date]
    let sourceIDs: [String]
    let target: Target
    /// Opaque digest of the owning destination authority. Never credentials or a
    /// public absolute filesystem path. The destination still validates its grant.
    let destinationBindingSHA256: String
    let canonicalData: Data
    let requestBindingSHA256: String

    init(operationID: UUID = UUID(), scope: HealthHistoryScope,
         settings: ExportSettingsSnapshot, captureDates: [Date], sourceIDs: [String],
         target: Target, destinationBindingSHA256: String) throws {
        guard scope.rangeSemantics == .ownerDates,
              Self.validDate(scope.startDate), Self.validDate(scope.endDate), scope.startDate <= scope.endDate,
              let timeZone = TimeZone(identifier: scope.timeZoneIdentifier),
              settings.calendarTimeZoneIdentifier == scope.timeZoneIdentifier,
              settings.appleExportEngineAuthorityIsFrozen,
              !scope.metricIDs.isEmpty, scope.metricIDs.count <= 512,
              scope.metricIDs.allSatisfy(Self.validIdentifier),
              scope.metricIDs == settings.metricSelection.enabledMetricIDs,
              !captureDates.isEmpty, captureDates.count <= 100_000,
              captureDates.allSatisfy(Self.validDate), captureDates == captureDates.sorted(),
              Set(captureDates).count == captureDates.count,
              sourceIDs.count <= 512, sourceIDs.allSatisfy(Self.validIdentifier),
              sourceIDs == sourceIDs.sorted(), Set(sourceIDs).count == sourceIDs.count,
              sourceIDs.contains("apple_health"),
              destinationBindingSHA256.utf8.count == 64,
              destinationBindingSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
            throw ValidationError.invalidRequest
        }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = timeZone
        let start = calendar.startOfDay(for: scope.startDate)
        let end = calendar.startOfDay(for: scope.endDate)
        guard captureDates.allSatisfy({ calendar.startOfDay(for: $0) == $0 && $0 >= start && $0 <= end }) else {
            throw ValidationError.invalidRequest
        }
        self.operationID = operationID
        self.scope = scope
        self.settings = settings
        self.captureDates = captureDates
        self.sourceIDs = sourceIDs
        self.target = target
        self.destinationBindingSHA256 = destinationBindingSHA256
        let payload = BindingPayload(operationID: operationID.uuidString.lowercased(),
            profileID: scope.profileID?.uuidString.lowercased(),
            requestedStart: CanonicalRFC3339UTC.string(from: scope.startDate),
            requestedEnd: CanonicalRFC3339UTC.string(from: scope.endDate),
            allAvailable: scope.allAvailable, timeZoneIdentifier: scope.timeZoneIdentifier,
            captureDates: captureDates.map { CanonicalRFC3339UTC.string(from: $0) },
            sourceIDs: sourceIDs, target: target, destinationBindingSHA256: destinationBindingSHA256,
            settings: .init(snapshot: settings))
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys, .withoutEscapingSlashes]
        // Settings may gain a Date-valued field without silently inheriting a
        // platform-default epoch/precision in this independent binding.
        encoder.dateEncodingStrategy = .custom { date, encoder in
            guard Self.validDate(date) else { throw ValidationError.invalidRequest }
            var c = encoder.singleValueContainer()
            try c.encode(CanonicalRFC3339UTC.string(from: date))
        }
        let bytes = try encoder.encode(payload)
        guard bytes.count <= 4 * 1_024 * 1_024 else { throw ValidationError.invalidRequest }
        canonicalData = bytes
        requestBindingSHA256 = SHA256.hash(data: bytes).map { String(format: "%02x", $0) }.joined()
    }

    private nonisolated static func validIdentifier(_ value: String) -> Bool {
        !value.isEmpty && value.utf8.count <= 128 && value.utf8.allSatisfy {
            (48...57).contains($0) || (65...90).contains($0) || (97...122).contains($0)
                || [45, 46, 58, 95].contains($0)
        }
    }

    private nonisolated static func validDate(_ date: Date) -> Bool {
        let instant = date.timeIntervalSince1970
        return instant.isFinite && instant >= -62_135_596_800 && instant < 253_402_300_800
    }

    func observation(from assessment: HealthHistoryAssessment) throws -> ExportHistoryObservation {
        guard assessment.scope == scope else { throw ValidationError.mismatchedAssessment }
        return try assessment.exportObservation(operationID: operationID, requestBindingSHA256: requestBindingSHA256)
    }

    private struct BindingPayload: Encodable {
        let schema = "healthmd.local_export_history_request"
        let schemaVersion = 1
        let operationID: String
        let profileID: String?
        let requestedStart: String
        let requestedEnd: String
        let allAvailable: Bool
        let timeZoneIdentifier: String
        let captureDates: [String]
        let sourceIDs: [String]
        let target: Target
        let destinationBindingSHA256: String
        let settings: ExportSettingsSnapshot.HistoryBindingEncoding

        enum CodingKeys: String, CodingKey {
            case schema, settings, target
            case schemaVersion = "schema_version"
            case operationID = "operation_id"
            case profileID = "profile_id"
            case requestedStart = "requested_start"
            case requestedEnd = "requested_end"
            case allAvailable = "all_available"
            case timeZoneIdentifier = "time_zone_identifier"
            case captureDates = "capture_dates"
            case sourceIDs = "source_ids"
            case destinationBindingSHA256 = "destination_binding_sha256"
        }
    }
}
