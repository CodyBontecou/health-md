import Foundation

@MainActor
protocol ExternalIntegrationDailyRecordProviding: AnyObject {
    var connectedProviderCount: Int { get }
    func beginExportAction()
    func fetchDailyRecords(for date: Date) async -> [ExternalDailyRecord]
    func endExportAction(succeeded: Bool)
}

extension ExternalIntegrationDailyRecordProviding {
    func beginExportAction() {}
    func endExportAction(succeeded: Bool) {}

    /// Compatibility convenience for export paths whose existing completion
    /// point already represents a committed destination write.
    func endExportAction() {
        endExportAction(succeeded: true)
    }
}
