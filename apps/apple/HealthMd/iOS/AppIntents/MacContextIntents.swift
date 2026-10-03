#if os(iOS)
import AppIntents
import Foundation
import UIKit

@MainActor
final class AppleContextPhoneClient {
    static let shared = AppleContextPhoneClient()
    let journal: AppleContextJournal
    private weak var sync: SyncService?
    private let bindingRoot: URL
    private let protectedDataAvailable: () -> Bool
    private let executionBlocked: (UUID) -> Bool
    private var transferJobs: [UUID: UUID] = [:]

    init(journal: AppleContextJournal? = nil, bindingRoot: URL? = nil,
         protectedDataAvailable: (() -> Bool)? = nil, executionBlocked: ((UUID) -> Bool)? = nil) {
        self.journal = journal ?? AppleContextJournal(root: AppleContextJournal.productionRoot("PhoneContextRequests"))
        self.bindingRoot = bindingRoot ?? AppleContextJournal.productionRoot("ContextProfileBindings")
        self.protectedDataAvailable = protectedDataAvailable ?? { UIApplication.shared.isProtectedDataAvailable }
        self.executionBlocked = executionBlocked ?? { SharedSetupV2ExecutionGate().isExecutionBlocked(profileID: $0) }
    }
    func install(_ sync: SyncService) {
        self.sync = sync
        sync.contextAutomationOutboundAdmission = { [weak self, weak sync] message in
            guard let self, let sync else { return false }
            return self.allowsOutbound(message, sync: sync)
        }
    }

    private func allowsOutbound(_ message: SyncMessage, sync: SyncService) -> Bool {
        let id: UUID?
        switch message {
        case .connectedTransferStart(let value):
            id = value.manifest.jobID
            if journal.record(value.manifest.jobID) != nil { transferJobs[value.transferID] = value.manifest.jobID }
        case .connectedTransferChunk(let value): id = transferJobs[value.transferID]
        case .connectedTransferComplete(let value): id = transferJobs[value.transferID]
        case .connectedTransferAbort(let value): id = value.jobID ?? transferJobs[value.transferID]
        case .iphoneExportAccepted(let value): id = value.jobID
        case .iphoneExportPreparationProgress(let value): id = value.jobID
        case .iphoneExportRejected(let value): id = value.jobID
        case .connectedCorpusStatus(let value): id = value.jobID
        case .connectedCorpusTransferOpen(let value):
            id = value.session.jobID
            if let record = journal.record(value.session.jobID) {
                guard let manifest = value.exportManifest, record.request.matches(manifest) else { return false }
            }
        case .connectedCorpusTransferFinalize(let value): id = value.jobID
        case .connectedCorpusTransferCancel(let value): id = value.jobID
        default: id = nil
        }
        guard let id, let record = journal.record(id) else { return true }
        return sync.canUsePhoneContextAutomation
            && sync.authenticatedContextPeerID == record.request.macInstallationID
            && sync.installationID == record.request.phoneInstallationID
    }

    /// A separate, explicitly user-confirmed binding. Does not alter export
    /// profiles, Shared Setup, or the ordinary Connected Mac destination.
    func bind(profileID: UUID) throws {
        guard let sync, sync.canUsePhoneContextAutomation,
              let peer = sync.authenticatedContextPeerID else { throw ClientError.unavailable }
        try FileManager.default.createDirectory(at: bindingRoot, withIntermediateDirectories: true)
        try JSONEncoder().encode(peer).write(to: bindingRoot.appendingPathComponent(profileID.uuidString),
                                             options: [.atomic, .completeFileProtection])
    }
    func boundPeer(profileID: UUID) -> UUID? {
        guard let data = try? Data(contentsOf: bindingRoot.appendingPathComponent(profileID.uuidString)) else { return nil }
        return try? JSONDecoder().decode(UUID.self, from: data)
    }

    func refresh(profileName: String?, startDate: Date, endDate: Date,
                 profiles suppliedProfiles: ExportProfileStore? = nil) throws -> MacContextRefreshEntity {
        guard protectedDataAvailable() else { throw ClientError.locked }
        let profiles = suppliedProfiles ?? ExportProfileStore()
        let profile: ExportProfile?
        if let name = profileName, !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            profile = profiles.profile(named: name)
        } else { profile = profiles.activeProfile }
        guard let profile, profile.target == .connectedMac,
              !executionBlocked(profile.id),
              let peer = boundPeer(profileID: profile.id) else { throw ClientError.profile }
        guard let sync, sync.connectionState == .connected else { throw ClientError.unavailable }
        guard sync.canUsePhoneContextAutomation else { throw ClientError.incompatible }
        guard sync.authenticatedContextPeerID == peer else { throw ClientError.profile }

        // All scope resolution is synchronous, before the intent's first await.
        // Only Apple Health is supported by this first automation adapter.
        guard profile.settings.detailPolicy == .summary || profile.settings.detailPolicy == .lossless else { throw ClientError.scope }
        let zone: TimeZone
        if let identifier = profile.settings.calendarTimeZoneIdentifier {
            guard let explicitZone = TimeZone(identifier: identifier) else { throw ClientError.scope }
            zone = explicitZone
        } else { zone = .current }
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = zone
        let start = calendar.startOfDay(for: startDate)
        let end = calendar.startOfDay(for: endDate)
        guard start <= end else { throw ClientError.scope }
        let dates = ExportOrchestrator.dateRange(from: start, to: end, calendar: calendar)
        let formatter = AppleContextRequest.formatter(zone: zone)
        let request = AppleContextRequest(phoneInstallationID: sync.installationID,
            macInstallationID: peer, profileID: profile.id,
            ownerDates: dates.map { formatter.string(from: $0) }, timeZoneIdentifier: zone.identifier,
            startDate: start, endDate: end,
            selection: CanonicalHealthDataSelection(metricIDs: Array(profile.settings.metricSelection.enabledMetricIDs),
                sourceIDs: ["apple_health"], detailLevel: profile.settings.detailPolicy.includesCanonicalArchive ? .lossless : .summary))
        try journal.admit(request) // Failure means ZERO sends, no ephemeral success.
        sync.send(.appleContext(.refresh(request)))
        return entity(for: request.id)
    }

    func status(id: UUID) throws -> MacContextRefreshEntity {
        guard let record = journal.record(id) else { throw ClientError.unknownRequest }
        if let sync, sync.canUsePhoneContextAutomation,
           sync.authenticatedContextPeerID == record.request.macInstallationID,
           sync.installationID == record.request.phoneInstallationID {
            // Full frozen scope allows recovery even when the original ack was lost.
            sync.send(.appleContext(.status(record.request)))
        }
        return entity(for: id)
    }

    func receive(_ message: AppleContextMessage) {
        guard case .receipt(let receipt) = message, let sync,
              sync.canUsePhoneContextAutomation, let peer = sync.authenticatedContextPeerID else { return }
        // Persistence failure leaves the prior receipt; never report unpersisted completion.
        _ = try? journal.accept(receipt, authenticatedPeer: peer, localID: sync.installationID, onPhone: true)
    }

    func owns(_ id: UUID) -> Bool { journal.record(id) != nil }

    func allowsAcquisition(_ request: IPhoneExportRequest, sync: SyncService) -> Bool {
        guard let record = journal.record(request.jobID) else { return true } // ordinary Mac request
        return sync.canUsePhoneContextAutomation
            && sync.authenticatedContextPeerID == record.request.macInstallationID
            && sync.installationID == record.request.phoneInstallationID
            && record.request.matches(request)
    }

    func timeZone(for request: IPhoneExportRequest) -> TimeZone? {
        journal.record(request.jobID).flatMap { TimeZone(identifier: $0.request.timeZoneIdentifier) }
    }

    func entity(for id: UUID) -> MacContextRefreshEntity {
        guard let record = journal.record(id) else {
            return MacContextRefreshEntity(id: id.uuidString, status: "unavailable")
        }
        let state: AppleContextReceipt.State
        if let receipt = record.receipt, receipt.state.isTerminal { state = receipt.state }
        else if !protectedDataAvailable() { state = .locked }
        else if sync?.connectionState != .connected { state = .unavailable }
        else if sync?.canUsePhoneContextAutomation != true { state = .incompatible }
        else if sync?.authenticatedContextPeerID != record.request.macInstallationID { state = .unavailable }
        else { state = record.receipt?.state ?? .pending }
        return MacContextRefreshEntity(id: id.uuidString, status: state.rawValue)
    }

    enum ClientError: LocalizedError {
        case locked, unavailable, incompatible, profile, scope, unknownRequest
        var errorDescription: String? {
            switch self {
            case .locked: return "Unlock iPhone before refreshing encrypted Mac context."
            case .unavailable: return "Open Health.md on the paired Mac and iPhone. This action cannot wake a sleeping Mac."
            case .incompatible: return "Use updated Health.md apps and authenticated Manual IP pairing on both devices."
            case .profile: return "Select an eligible saved Connected Mac profile and explicitly bind it to the authenticated Mac in Export Profiles."
            case .scope: return "Choose an ordered date range and a nonempty supported metric selection."
            case .unknownRequest: return "No durable context refresh request exists for this identifier."
            }
        }
    }
}

struct MacContextRefreshEntity: AppEntity {
    static var typeDisplayRepresentation: TypeDisplayRepresentation = "Mac Context Refresh"
    static var defaultQuery = MacContextRefreshQuery()
    var id: String
    @Property(title: "Status") var status: String
    init(id: String, status: String) {
        self.id = id
        self.status = status
    }
    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(title: "Context refresh", subtitle: "\(status)")
    }
}

struct MacContextRefreshQuery: EntityQuery {
    @MainActor
    func entities(for identifiers: [String]) async throws -> [MacContextRefreshEntity] {
        identifiers.compactMap { UUID(uuidString: $0) }.filter {
            AppleContextPhoneClient.shared.journal.record($0) != nil
        }.map { AppleContextPhoneClient.shared.entity(for: $0) }
    }
    @MainActor
    func suggestedEntities() async throws -> [MacContextRefreshEntity] {
        AppleContextPhoneClient.shared.journal.allRecords.map { AppleContextPhoneClient.shared.entity(for: $0.request.id) }
    }
}

struct RefreshMacHealthContextIntent: AppIntent {
    static var title: LocalizedStringResource = "Refresh Mac Health Context"
    static var description = IntentDescription("Refresh explicit owner dates in the paired Mac's encrypted context, without export files or file quota. Requires open, authenticated apps.", categoryName: "Health")
    static var openAppWhenRun = false
    @Parameter(title: "Profile", description: "Saved Connected Mac profile name. Empty selects the active saved profile; no live-settings fallback.")
    var profile: String?
    @Parameter(title: "Start Date") var startDate: Date
    @Parameter(title: "End Date") var endDate: Date
    static var parameterSummary: some ParameterSummary {
        Summary("Refresh Mac context from \(\.$startDate) to \(\.$endDate)")
    }
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<MacContextRefreshEntity> & ProvidesDialog {
        let entity = try AppleContextPhoneClient.shared.refresh(profileName: profile, startDate: startDate, endDate: endDate)
        return .result(value: entity, dialog: "Request saved; context refresh is pending. Use Get Mac Context Refresh Status with this request.")
    }
}

struct GetMacContextRefreshStatusIntent: AppIntent {
    static var title: LocalizedStringResource = "Get Mac Context Refresh Status"
    static var description = IntentDescription("Read a saved context refresh receipt and request an updated status from its original authenticated Mac. Disconnection is not completion.", categoryName: "Health")
    static var openAppWhenRun = false
    @Parameter(title: "Refresh Request") var request: MacContextRefreshEntity
    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<MacContextRefreshEntity> & ProvidesDialog {
        guard let id = UUID(uuidString: request.id) else { throw AppleContextPhoneClient.ClientError.unknownRequest }
        let entity = try AppleContextPhoneClient.shared.status(id: id)
        return .result(value: entity, dialog: IntentDialog(stringLiteral: "Context refresh: \(entity.status). Request: \(entity.id)."))
    }
}
#endif
