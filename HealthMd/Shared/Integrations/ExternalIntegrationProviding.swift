import Foundation

@MainActor
protocol ExternalIntegrationDailyRecordProviding: AnyObject {
    var connectedProviderCount: Int { get }
    func fetchDailyRecords(for date: Date) async -> [ExternalDailyRecord]
}
