import Foundation

/// Which WHOOP resources the user exports (ConnectedAppsG snapshot chips). Deselected
/// resources are neither fetched nor planned in the typed provider section, so they get
/// no `resources[]` row (provider-sections v1: every *planned* resource has one row).
/// Persisted on the device that holds the WHOOP connection; defaults to everything.
nonisolated enum WHOOPExportResourceSelection {
    static let defaultsKey = "whoopExportResources"
    static let all = Set(WHOOPResourceName.allCases)

    static func stored(in defaults: UserDefaults = .standard) -> Set<WHOOPResourceName> {
        guard let raw = defaults.array(forKey: defaultsKey) as? [String] else { return all }
        let selection = Set(raw.compactMap(WHOOPResourceName.init(rawValue:)))
        return selection.isEmpty ? all : selection
    }

    static func store(_ selection: Set<WHOOPResourceName>, in defaults: UserDefaults = .standard) {
        guard !selection.isEmpty else { return }
        if selection == all {
            defaults.removeObject(forKey: defaultsKey)
        } else {
            defaults.set(selection.map(\.rawValue).sorted(), forKey: defaultsKey)
        }
    }

    /// Toggles one resource; the last selected resource stays on (disconnect stops WHOOP).
    static func toggled(_ resource: WHOOPResourceName, in selection: Set<WHOOPResourceName>) -> Set<WHOOPResourceName> {
        var next = selection
        if next.contains(resource) {
            guard next.count > 1 else { return selection }
            next.remove(resource)
        } else {
            next.insert(resource)
        }
        return next
    }
}
