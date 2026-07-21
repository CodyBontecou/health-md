#if os(macOS)
import Combine
import Foundation

/// Main-actor bridge between SwiftUI/local control surfaces and the atomic
/// profile store. Profile creation is explicit; Health.md never creates a broad
/// policy merely because HealthKit or an export setting is enabled.
@MainActor
final class HealthContextProfileManager: ObservableObject {
    @Published private(set) var profiles: [HealthContextProfile] = []
    @Published private(set) var isLoaded = false
    @Published private(set) var lastError: String?

    private let store: HealthContextProfileStore

    init(store: HealthContextProfileStore = HealthContextProfileStore()) {
        self.store = store
    }

    func load() async {
        do {
            profiles = try await store.loadProfiles().sorted(by: Self.sortProfiles)
            lastError = nil
        } catch {
            profiles = []
            lastError = error.localizedDescription
        }
        isLoaded = true
    }

    /// Creates the broadest representable policy only after a user-facing
    /// confirmation. Dynamic scopes include future supported metrics/providers;
    /// all-history remains unbounded rather than becoming a sentinel date.
    @discardableResult
    func createFullAccessProfile(
        name: String = "All Health Data",
        now: Date = Date()
    ) async throws -> HealthContextProfile {
        let uniqueName = uniqueProfileName(preferred: name)
        let profile = HealthContextProfile(
            name: uniqueName,
            metricScope: .allAvailable,
            dataSourceScope: .allAvailable,
            detailLevel: .lossless,
            datePolicy: .allHistory,
            allowedCallers: [.registeredAgent, .commandLine],
            allowedSurfaces: [.localControlAPI, .commandLine, .mcpStdio],
            confirmationRequirement: .notRequired,
            destinationBinding: .any,
            createdAt: now,
            updatedAt: now
        )
        try await store.upsert(profile)
        await load()
        return profile
    }

    func upsert(_ profile: HealthContextProfile) async throws {
        try await store.upsert(profile)
        await load()
    }

    func remove(profileID: UUID) async throws {
        try await store.remove(profileID: profileID)
        await load()
    }

    func profile(id: UUID) -> HealthContextProfile? {
        profiles.first { $0.id == id }
    }

    private func uniqueProfileName(preferred: String) -> String {
        let names = Set(profiles.map(\.name))
        guard names.contains(preferred) else { return preferred }
        var suffix = 2
        while names.contains("\(preferred) \(suffix)") { suffix += 1 }
        return "\(preferred) \(suffix)"
    }

    private static func sortProfiles(_ lhs: HealthContextProfile, _ rhs: HealthContextProfile) -> Bool {
        if lhs.name.localizedCaseInsensitiveCompare(rhs.name) != .orderedSame {
            return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
        }
        return lhs.id.uuidString < rhs.id.uuidString
    }
}
#endif
