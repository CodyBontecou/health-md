import Combine
import Foundation

/// History invalidation consumes execution semantics, not ObservableObject's
/// pre-change broadcast. Synchronous typed delivery preserves observed ABA
/// transitions; unchanged flushes/renames/timestamps cannot cancel a request.
/// This does not change persisted profile or engine execution authority.
@MainActor
final class HealthHistoryProfilePublicationObserver {
    private struct Input: Equatable {
        let id: UUID
        let settings: ExportSettingsSnapshot
        let target: ExportTargetSelection
        let folderVaultID: UUID?
        let apiEndpointID: UUID?
    }

    private weak var store: ExportProfileStore?
    private var subscription: AnyCancellable?
    private var initialized = false
    private var current: Input?

    func bind(_ store: ExportProfileStore, didChange: @escaping @MainActor () -> Void) {
        guard self.store !== store || subscription == nil else { return }
        self.store = store
        initialized = false
        current = nil
        subscription = store.$profiles.combineLatest(store.$activeProfileID)
            .sink { [weak self] profiles, activeID in
                guard let self else { return }
                let profile = profiles.first { $0.id == activeID }
                let input = profile.map { Input(id: $0.id, settings: $0.settings, target: $0.target,
                    folderVaultID: $0.folderVaultID, apiEndpointID: $0.apiEndpointID) }
                let changed = initialized && current != input
                initialized = true
                current = input
                if changed { didChange() }
            }
    }

    func unbind() {
        subscription?.cancel()
        subscription = nil
        store = nil
        initialized = false
        current = nil
    }
}
