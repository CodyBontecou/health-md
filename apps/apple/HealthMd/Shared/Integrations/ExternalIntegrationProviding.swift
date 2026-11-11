import Foundation

nonisolated struct ExternalProviderHistoryDiscovery: Equatable, Sendable {
    let earliestDate: Date?
    let unresolvedProviderIDs: [String]

    var isComplete: Bool { unresolvedProviderIDs.isEmpty }
}

/// Private capture authority for local journals. IDs name a grant, never its credentials.
nonisolated struct ExternalProviderCaptureAuthority: Codable, Equatable, Sendable {
    let version: Int
    let connections: [String: UUID?]

    init(connections: [String: UUID?]) {
        self.version = 1
        self.connections = connections
    }

    init(from decoder: Decoder) throws {
        let values = try decoder.container(keyedBy: CodingKeys.self)
        version = try values.decode(Int.self, forKey: .version)
        guard version == 1 else {
            throw DecodingError.dataCorruptedError(forKey: .version, in: values,
                debugDescription: "Unsupported provider capture authority")
        }
        connections = try values.decode([String: UUID?].self, forKey: .connections)
    }

    enum RecoveryError: Error, LocalizedError {
        case unavailable
        var errorDescription: String? {
            "This saved export’s provider connection is unavailable. Start a new export to choose current connections."
        }
    }
}

@MainActor
protocol ExternalIntegrationDailyRecordProviding: AnyObject {
    var connectedProviderCount: Int { get }
    /// Accept the provider/account selection once for this in-memory capture.
    func forCaptureOperation() -> any ExternalIntegrationDailyRecordProviding
    var captureAuthority: ExternalProviderCaptureAuthority? { get }
    func forCaptureOperation(authority: ExternalProviderCaptureAuthority) throws -> any ExternalIntegrationDailyRecordProviding
    func beginExportAction()
    func fetchDailyRecords(for date: Date) async -> [ExternalDailyRecord]
    func fetchDailyRecords(
        for date: Date,
        calendar: Calendar
    ) async -> [ExternalDailyRecord]
    func fetchDailyRecords(
        for date: Date,
        providerIDs: Set<String>
    ) async -> [ExternalDailyRecord]
    func fetchDailyRecords(
        for date: Date,
        providerIDs: Set<String>,
        calendar: Calendar
    ) async -> [ExternalDailyRecord]
    func fetchDailyRecords(
        for date: Date,
        calendar: Calendar,
        whoopResources: Set<WHOOPResourceName>
    ) async -> [ExternalDailyRecord]
    func fetchDailyRecords(
        for date: Date,
        providerIDs: Set<String>,
        calendar: Calendar,
        whoopResources: Set<WHOOPResourceName>
    ) async -> [ExternalDailyRecord]
    func discoverEarliestAvailableDate(
        providerIDs: Set<String>,
        whoopResources: Set<WHOOPResourceName>
    ) async -> ExternalProviderHistoryDiscovery
    func discoverEarliestAvailableDate(
        providerIDs: Set<String>
    ) async -> ExternalProviderHistoryDiscovery
    func endExportAction(succeeded: Bool)
}

extension ExternalIntegrationDailyRecordProviding {
    func forCaptureOperation() -> any ExternalIntegrationDailyRecordProviding { self }
    var captureAuthority: ExternalProviderCaptureAuthority? { nil }
    func forCaptureOperation(authority: ExternalProviderCaptureAuthority) throws -> any ExternalIntegrationDailyRecordProviding {
        throw ExternalProviderCaptureAuthority.RecoveryError.unavailable
    }

    func beginExportAction() {}

    func fetchDailyRecords(
        for date: Date,
        calendar: Calendar
    ) async -> [ExternalDailyRecord] {
        await fetchDailyRecords(for: date)
    }

    func fetchDailyRecords(
        for date: Date,
        providerIDs: Set<String>,
        calendar: Calendar
    ) async -> [ExternalDailyRecord] {
        await fetchDailyRecords(for: date, providerIDs: providerIDs)
    }
    /// Compatibility for synthetic/legacy adapters. Production adapters implement
    /// these overloads to enforce selection before any API or token request.
    func fetchDailyRecords(
        for date: Date,
        calendar: Calendar,
        whoopResources: Set<WHOOPResourceName>
    ) async -> [ExternalDailyRecord] {
        guard !whoopResources.isEmpty else { return [] }
        return await fetchDailyRecords(for: date, calendar: calendar)
            .compactMap { $0.selectingWHOOPResources(whoopResources) }
    }

    func fetchDailyRecords(
        for date: Date,
        providerIDs: Set<String>,
        calendar: Calendar,
        whoopResources: Set<WHOOPResourceName>
    ) async -> [ExternalDailyRecord] {
        let selectedIDs = whoopResources.isEmpty ? providerIDs.subtracting(["whoop"]) : providerIDs
        guard !selectedIDs.isEmpty else { return [] }
        return await fetchDailyRecords(for: date, providerIDs: selectedIDs, calendar: calendar)
            .compactMap { $0.selectingWHOOPResources(whoopResources) }
    }

    func discoverEarliestAvailableDate(
        providerIDs: Set<String>,
        whoopResources: Set<WHOOPResourceName>
    ) async -> ExternalProviderHistoryDiscovery {
        let selectedIDs = whoopResources.isEmpty ? providerIDs.subtracting(["whoop"]) : providerIDs
        guard !selectedIDs.isEmpty else {
            return ExternalProviderHistoryDiscovery(earliestDate: nil, unresolvedProviderIDs: [])
        }
        return await discoverEarliestAvailableDate(providerIDs: selectedIDs)
    }

    func endExportAction(succeeded: Bool) {}

    func discoverEarliestAvailableDate(
        providerIDs: Set<String>
    ) async -> ExternalProviderHistoryDiscovery {
        ExternalProviderHistoryDiscovery(
            earliestDate: nil,
            unresolvedProviderIDs: providerIDs.sorted()
        )
    }

    /// Compatibility convenience for export paths whose existing completion
    /// point already represents a committed destination write.
    func endExportAction() {
        endExportAction(succeeded: true)
    }
}

/// Accept file settings and account identity synchronously, before provider callbacks
/// or renderer qualification can change the caller's observable configuration.
@MainActor
struct AcceptedExternalProviderFileCapture {
    var snapshot: ExportSettingsSnapshot
    let providers: (any ExternalIntegrationDailyRecordProviding)?

    init(settings: AdvancedExportSettings, context: AppleSleepCaptureContext,
         healthSubfolder: String? = nil,
         includesProviders: Bool? = nil,
         providers: (any ExternalIntegrationDailyRecordProviding)?) throws {
        var snapshot = ExportSettingsSnapshot.from(settings, healthSubfolder: healthSubfolder,
            appleExportEngineAuthorityIsFrozen: false,
            calendarTimeZoneIdentifier: context.calendarTimeZoneIdentifier)
        snapshot.sleepCaptureContext = context
        let frozenAuthority = settings.executionExternalProviderCaptureAuthorityIsFrozen
        if !frozenAuthority, snapshot.appleExportEnginePin == nil {
            snapshot.metricSelection.enabledWHOOPResources.formIntersection(WHOOPExportResourceSelection.stored())
        }
        let accepted: (any ExternalIntegrationDailyRecordProviding)?
        if !(includesProviders ?? settings.writesExternalProviderSidecars) {
            accepted = nil
            if !frozenAuthority { snapshot.externalProviderCaptureAuthority = .init(connections: [:]) }
        } else if let authority = snapshot.externalProviderCaptureAuthority {
            if authority.connections.isEmpty { accepted = nil }
            else {
                guard let providers else { throw ExternalProviderCaptureAuthority.RecoveryError.unavailable }
                let restored = try providers.forCaptureOperation(authority: authority)
                guard restored.captureAuthority == authority else {
                    throw ExternalProviderCaptureAuthority.RecoveryError.unavailable
                }
                accepted = restored
            }
        } else if frozenAuthority && context.sleepDayAttribution == .morningEnds {
            throw ExternalProviderCaptureAuthority.RecoveryError.unavailable
        } else {
            let selected = ConnectedAppsFeature.isEnabled ? providers?.forCaptureOperation() : nil
            let count = selected?.connectedProviderCount ?? 0
            accepted = count > 0 ? selected : nil
            let authority = selected?.captureAuthority
            if let authority { snapshot.externalProviderCaptureAuthority = authority }
            else if count == 0 {
                snapshot.externalProviderCaptureAuthority = .init(connections: [:])
            }
            if context.sleepDayAttribution == .morningEnds && snapshot.externalProviderCaptureAuthority == nil {
                throw ExternalProviderCaptureAuthority.RecoveryError.unavailable
            }
        }
        self.snapshot = snapshot
        self.providers = accepted
    }
}
