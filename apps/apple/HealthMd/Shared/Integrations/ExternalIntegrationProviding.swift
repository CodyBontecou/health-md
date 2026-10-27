import Foundation

nonisolated struct ExternalProviderHistoryDiscovery: Equatable, Sendable {
    let earliestDate: Date?
    let unresolvedProviderIDs: [String]

    var isComplete: Bool { unresolvedProviderIDs.isEmpty }
}

@MainActor
protocol ExternalIntegrationDailyRecordProviding: AnyObject {
    var connectedProviderCount: Int { get }
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
