import Foundation
import ExportAutomationKit

typealias PendingExportSource = AutomationPendingExportSource
typealias PendingExportReason = AutomationPendingExportReason
typealias PendingExportRequest = AutomationPendingExportRequest

protocol PendingExportStoring: AutomationPendingExportStoring {}

struct PendingExportStore: PendingExportStoring {
    static let storageKey = AutomationPendingExportStore.storageKey

    private let store: AutomationPendingExportStore

    init(
        userDefaults: UserDefaults = .standard,
        encoder: JSONEncoder = JSONEncoder(),
        decoder: JSONDecoder = JSONDecoder()
    ) {
        self.store = AutomationPendingExportStore(
            storageKey: Self.storageKey,
            userDefaults: userDefaults,
            encoder: encoder,
            decoder: decoder,
            notificationIdentifierFactory: ExportNotificationIdentifiers.identifierFactory
        )
    }

    func loadAll() throws -> [PendingExportRequest] {
        try store.loadAll()
    }

    func upsert(_ request: PendingExportRequest) throws {
        try store.upsert(request)
    }

    func remove(id: PendingExportRequest.ID) throws {
        try store.remove(id: id)
    }

    func clearCompletedRequests(ids: Set<PendingExportRequest.ID>) throws {
        try store.clearCompletedRequests(ids: ids)
    }

    func notificationIdentifier(for request: PendingExportRequest) -> String {
        store.notificationIdentifier(for: request)
    }
}
