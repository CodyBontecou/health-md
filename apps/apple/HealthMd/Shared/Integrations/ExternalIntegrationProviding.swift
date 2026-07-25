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
        providerIDs: Set<String>
    ) async -> [ExternalDailyRecord]
    func discoverEarliestAvailableDate(
        providerIDs: Set<String>
    ) async -> ExternalProviderHistoryDiscovery
    func endExportAction(succeeded: Bool)
}

extension ExternalIntegrationDailyRecordProviding {
    func beginExportAction() {}
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
