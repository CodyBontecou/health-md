#if os(macOS)
import Combine
import Foundation

/// User-facing lifecycle controls for the encrypted query store. Retention is
/// never implicit: every deletion is an explicit, independently confirmed action.
@MainActor
final class MacEncryptedHealthContextManager: ObservableObject {
    @Published private(set) var ownerDateCount = 0
    @Published private(set) var earliestOwnerDate: String?
    @Published private(set) var latestOwnerDate: String?
    @Published private(set) var isWorking = false
    @Published private(set) var lastError: String?

    let store: EncryptedHealthContextStore

    init(store: EncryptedHealthContextStore) {
        self.store = store
    }

    func refresh() async {
        await perform {
            let dates = try await self.store.listOwnerDates()
            self.ownerDateCount = dates.count
            self.earliestOwnerDate = dates.first
            self.latestOwnerDate = dates.last
        }
    }

    func deleteAll() async {
        await perform {
            try await self.store.deleteAll()
            self.ownerDateCount = 0
            self.earliestOwnerDate = nil
            self.latestOwnerDate = nil
        }
    }

    /// Deletes every owner day strictly before the supplied canonical day. It
    /// introduces no hidden count/size/history cap and returns the exact count.
    @discardableResult
    func delete(before ownerDate: String) async -> Int {
        var removedCount = 0
        await perform {
            let removed = try await self.store.applyRetention(.delete(before: ownerDate))
            removedCount = removed.count
            let dates = try await self.store.listOwnerDates()
            self.ownerDateCount = dates.count
            self.earliestOwnerDate = dates.first
            self.latestOwnerDate = dates.last
        }
        return removedCount
    }

    private func perform(_ operation: @escaping @MainActor () async throws -> Void) async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        do {
            try await operation()
            lastError = nil
        } catch {
            lastError = error.localizedDescription
        }
    }
}
#endif
