import Foundation

enum WatchHealthSnapshotStore {
    private static let suiteName = "group.com.codybontecou.obsidianhealth.watch"
    private static let key = "watchHealthSnapshot.v1"

    static func load() -> WatchHealthSnapshot? {
        guard let data = defaults.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(WatchHealthSnapshot.self, from: data)
    }

    static func save(_ snapshot: WatchHealthSnapshot) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        defaults.set(data, forKey: key)
    }

    static func loadIfFresh(maxAge: TimeInterval = 60 * 60 * 4, now: Date = .now) -> WatchHealthSnapshot? {
        guard let snapshot = load() else { return nil }
        return now.timeIntervalSince(snapshot.lastUpdated) <= maxAge ? snapshot : nil
    }

    private static var defaults: UserDefaults {
        UserDefaults(suiteName: suiteName) ?? .standard
    }
}
