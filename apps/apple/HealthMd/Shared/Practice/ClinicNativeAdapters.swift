import CryptoKit
import Foundation

struct ClinicProfileApproval: Codable {
    let subjectID: String
    let deviceID: String
    let connectionID: String
    let revision: String
    let profileID: UUID
    let settings: ExportSettingsSnapshot
    let destinationIdentity: ScheduledAPIEndpointIdentity
}
struct ClinicSetupReview: Codable, Equatable {
    let clinicID: String
    let clinicName: String
    let setupID: String
    let subjectID: String
    let deviceID: String
    let connectionID: String
    let revision: String
    let name: String
    let settings: ExportSettingsSnapshot
    let endpointID: UUID
    let weekly: Bool
    let hour: Int
    let expiresAt: Date
}
private struct ClinicSetupApplication: ClinicStoredRecord {
    var storageVersion = 1
    let review: ClinicSetupReview
    var approval: ClinicProfileApproval?
}

/// Receives a fully mapped local settings snapshot, never URL configuration or credentials.
/// The authenticated enrollment mapper and review-screen presenter are deliberately not installed yet.
@MainActor
final class ClinicNativeOnboarding {
    private let profiles: ExportProfileStore
    private let schedules: ScheduledExportEntryStore
    private let store: ClinicPrivateStore
    private let destination: (UUID) -> APIExportDestinationSnapshot?
    private let enabled: () -> Bool
    private var pending: (data: Data, digest: String, identity: ScheduledAPIEndpointIdentity)?
    private(set) var reviewedEndpoint: String?
    init(profiles: ExportProfileStore, schedules: ScheduledExportEntryStore, store: ClinicPrivateStore,
         destination: @escaping (UUID) -> APIExportDestinationSnapshot?,
         enabled: @escaping () -> Bool = { PracticeFeaturePolicy.current.isEnabled }) {
        self.profiles = profiles; self.schedules = schedules; self.store = store
        self.destination = destination; self.enabled = enabled
    }
    /// No native writes. UI must show the complete snapshot/endpoint/schedule and return this exact digest on Apply.
    func preview(_ review: ClinicSetupReview, now: Date = Date()) throws -> String {
        guard enabled(), [review.clinicID, review.setupID, review.subjectID, review.deviceID, review.connectionID, review.revision].allSatisfy({ !$0.isEmpty && $0.utf8.count <= 200 && !$0.unicodeScalars.contains(where: { CharacterSet.controlCharacters.contains($0) }) }), review.expiresAt > now, (0...23).contains(review.hour),
              !review.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, !review.clinicName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              let zoneID = review.settings.calendarTimeZoneIdentifier, TimeZone(identifier: zoneID) != nil,
              let endpoint = destination(review.endpointID), Self.isBoundHTTPS(endpoint) else { throw ClinicNativeError.unavailable }
        let encoder = JSONEncoder(); encoder.outputFormatting = [.sortedKeys]
        let data = try encoder.encode(review)
        let identity = ScheduledAPIEndpointIdentity(destination: endpoint, bindingID: review.endpointID)
        let identityData = try encoder.encode(identity)
        let digest = SHA256.hash(data: data + identityData).map { String(format: "%02x", $0) }.joined()
        pending = (data, digest, identity); reviewedEndpoint = endpoint.endpointURL.absoluteString; return digest
    }
    func accept(digest: String, now: Date = Date(), authorize: (ClinicSetupReview) throws -> Void) throws -> ClinicProfileApproval {
        guard enabled(), let pending, pending.digest == digest else { throw ClinicNativeError.unavailable }
        let review = try JSONDecoder().decode(ClinicSetupReview.self, from: pending.data)
        try authorize(review)
        guard review.expiresAt > now, let endpoint = destination(review.endpointID), Self.isBoundHTTPS(endpoint),
              pending.identity.matches(endpoint, bindingID: review.endpointID)
        else { throw ClinicNativeError.unavailable }
        let key = ["setup", review.subjectID, review.deviceID, review.setupID].joined(separator: "\u{0}")
        if let previous = try store.load(ClinicSetupApplication.self, key: key) {
            guard previous.review == review else { throw ClinicNativeError.profileChanged }
            guard let approval = previous.approval else { throw ClinicNativeError.interrupted }
            return approval
        }
        guard profiles.profiles.count < 100 else { throw ClinicNativeError.capacity }
        // Reserve before modifying profile stores. A crash cannot silently create another profile on replay.
        try store.save(ClinicSetupApplication(review: review), key: key)
        self.pending = nil
        let profile = profiles.add(name: review.name, settings: review.settings, target: .apiEndpoint, apiEndpointID: review.endpointID)
        guard schedules.upsert(ScheduledExportEntry(profileID: profile.id, isEnabled: false,
                                                    frequency: review.weekly ? .weekly : .daily, preferredHour: review.hour))
        else { throw ClinicNativeError.interrupted }
        let approval = ClinicProfileApproval(subjectID: review.subjectID, deviceID: review.deviceID,
            connectionID: review.connectionID, revision: review.revision, profileID: profile.id, settings: profile.settings,
            destinationIdentity: pending.identity)
        try store.save(ClinicSetupApplication(review: review, approval: approval), key: key)
        return approval
    }
    static func isBoundHTTPS(_ endpoint: APIExportDestinationSnapshot) -> Bool {
        guard let parts = URLComponents(url: endpoint.endpointURL, resolvingAgainstBaseURL: false) else { return false }
        return parts.scheme == "https" && parts.host?.isEmpty == false && parts.user == nil && parts.password == nil
            && parts.query == nil && parts.fragment == nil && endpoint.authorizationHeaderValue?.isEmpty == false
    }
}

/// Calls the same renderer/uploader as manual API export. Complete snapshot options remain intact.
@MainActor
struct ClinicAppleExportAdapter {
    let profiles: ExportProfileStore
    let healthKit: HealthKitManager
    let destination: (UUID) -> APIExportDestinationSnapshot?
    let externalIntegrations: ExternalIntegrationDailyRecordProviding?
    var enabled: () -> Bool = { PracticeFeaturePolicy.current.isEnabled }
    var executionAllowed: (UUID) -> Bool = { !SharedSetupV2ExecutionGate().isExecutionBlocked(profileID: $0) }

    func export(request: ClinicRefreshRequest, approval: ClinicProfileApproval,
                check: @escaping @MainActor () async throws -> Void) async throws -> String {
        guard enabled() else { throw ClinicNativeError.unavailable }
        try await check()
        guard request.subjectID == approval.subjectID, request.deviceID == approval.deviceID,
              request.connectionID == approval.connectionID, request.revision == approval.revision,
              request.profileID == approval.profileID.uuidString,
              let profile = profiles.profiles.first(where: { $0.id == approval.profileID }), profile.target == .apiEndpoint,
              profile.settings == approval.settings, executionAllowed(profile.id), let endpointID = profile.apiEndpointID,
              let endpoint = destination(endpointID), ClinicNativeOnboarding.isBoundHTTPS(endpoint),
              approval.destinationIdentity.matches(endpoint, bindingID: endpointID),
              let zoneID = approval.settings.calendarTimeZoneIdentifier, TimeZone(identifier: zoneID) != nil
        else { throw ClinicNativeError.profileChanged }
        let dates = try request.ownerDates(timeZoneIdentifier: zoneID)
        let settings = approval.settings.makeAdvancedExportSettings(forNewConfiguration: true)
        let client = APIExportClient(clinicConfiguration: .ephemeral)
        let result = await APIEndpointExportRunner.export(dates: dates, healthKitManager: healthKit, settings: settings,
            destination: endpoint, externalIntegrations: externalIntegrations,
            upload: { batch, destination in try await client.upload(payloadArtifact: batch.bodyArtifact, destination: destination) },
            authorityCheck: {
                try await check()
                guard let current = profiles.profiles.first(where: { $0.id == approval.profileID }),
                      current.settings == approval.settings, current.target == .apiEndpoint, executionAllowed(current.id),
                      let id = current.apiEndpointID, let latest = destination(id),
                      approval.destinationIdentity.matches(latest, bindingID: id)
                else { throw ClinicNativeError.profileChanged }
            })
        guard result.didCompleteAllRequestedDates, !result.wasCancelled else { throw ClinicNativeError.incompleteExport }
        return "clinic-" + request.requestID
    }
}
