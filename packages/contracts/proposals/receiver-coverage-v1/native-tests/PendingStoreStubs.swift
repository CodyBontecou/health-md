// Inert SDK type seams for compiling the actual PendingExportRequest/PendingExportStore.
// No queue, date reduction, atomic write or recovery logic is replaced here.
import Foundation
struct ScheduledAPIEndpointIdentity: Codable, Equatable {}
struct AppleSleepCaptureContext: Codable, Equatable {
    enum Attribution: String, Codable { case morningEnds, nightBegins }
    enum AvailabilityError: Error { case missingDurableAttribution }
    var sleepDayAttribution: Attribution = .nightBegins
    static func recovered(_ value: Self?) throws -> Self { value ?? Self() }
}
struct Pin: Codable, Equatable { let profile: String }
enum AppleExportEnginePin { static let profileID = "legacy" }
struct ExportSettingsSnapshot: Codable, Equatable {
    static let durableSleepContextEncoding = CodingUserInfoKey(rawValue:"durable")!
    var calendarTimeZoneIdentifier: String? = "UTC"
    var sleepCaptureContext: AppleSleepCaptureContext? = nil
    var externalProviderCaptureAuthority: String? = nil
    var appleExportEnginePin: Pin? = nil
    func recoveredSleepCaptureContext(captureContext: AppleSleepCaptureContext?) throws -> AppleSleepCaptureContext { try .recovered(captureContext) }
}
enum ScheduledExportKind: String, Codable { case completedDay, todayRefresh }
enum ExportTargetSelection: String, Codable { case apiEndpoint }
enum ExportNotificationIdentifiers { static func pendingExport(for request: PendingExportRequest) -> String {request.id.uuidString} }
@MainActor enum ReceiverCoverageSettings { static let directory = FileManager.default.temporaryDirectory }
