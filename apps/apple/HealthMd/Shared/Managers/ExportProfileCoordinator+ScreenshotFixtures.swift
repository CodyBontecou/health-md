#if DEBUG && os(iOS)
import Foundation

/// App Store screenshot automations (UI tests only, never shipped).
///
/// The Archive and Automations boards show four automations: Daily, Weekly CSV, Agent feed
/// (an API endpoint with Today Refresh, `ArchiveGlassFeed`) and a paused Mac archive. Under
/// `UITEST_APPSTORE_FIXTURE_PROFILES=true` the migrated default becomes Daily and the other
/// three are added with real stores, so every screen derives them as it would for a user.
extension ExportProfileCoordinator {
    static let screenshotFixtureEnvironmentKey = "UITEST_APPSTORE_FIXTURE_PROFILES"

    static var wantsScreenshotFixtureProfiles: Bool {
        TestMode.isUITesting
            && ProcessInfo.processInfo.environment[screenshotFixtureEnvironmentKey] == "true"
    }

    /// Idempotent: does nothing once the fixture set exists or when the store holds anything
    /// other than the single migrated default.
    func seedScreenshotFixtureProfilesIfNeeded() {
        guard Self.wantsScreenshotFixtureProfiles,
              profileStore.profiles.count == 1,
              let daily = profileStore.profiles.first else { return }

        // The other automations start from the migrated settings, without daily notes. Every
        // automation uses the default metric selection, so Default metrics shows the build's
        // real default count, never a selection left over from an earlier UI-test journey.
        var base = daily.settings
        base.metricSelection = .from(MetricSelectionState())
        // ExportNowG writes daily files ("14 files · 7 days"), not a range summary.
        base.summaryOnlyExport = false
        // Only Daily updates the daily note (AutomationsGlass).
        base.dailyNoteInjection.enabled = false

        // ComposeGlass / DuoInnerComposeG: Markdown + Bases, daily notes on.
        var dailySettings = base
        dailySettings.exportFormats = [.markdown, .obsidianBases]
        dailySettings.dailyNoteInjection.enabled = true
        dailySettings.dailyNoteInjection.dailyNotesOnly = false
        _ = updateProfile(
            id: daily.id,
            name: "Daily",
            target: .localIPhoneFolder,
            // ComposeGlass / AutomationsGlass: "to Vault/Health".
            folderVaultID: screenshotFolderID(["Vault", "Health"]) ?? daily.folderVaultID,
            apiEndpointID: daily.apiEndpointID,
            settings: dailySettings
        )
        scheduledEntryStore.upsert(ScheduledExportEntry(
            profileID: daily.id,
            isEnabled: true,
            frequency: .daily,
            preferredHour: 7,
            preferredMinute: 30
        ))

        // AutomationsGlass: "write the last 7 days as CSV to Files/Exports". A real folder at
        // that path inside the app container, bound as its own destination.
        var csv = base
        csv.exportFormats = [.csv]
        guard let weekly = profileStore.add(
            name: "Weekly CSV",
            settings: csv,
            target: .localIPhoneFolder,
            folderVaultID: screenshotFolderID(["Files", "Exports"]) ?? daily.folderVaultID
        ) else { return }
        scheduledEntryStore.upsert(ScheduledExportEntry(
            profileID: weekly.id,
            isEnabled: true,
            frequency: .weekly,
            preferredHour: 8,
            preferredMinute: 0,
            weekday: 7
        ))

        var json = base
        json.exportFormats = [.json]
        let endpoint = destinationStore.upsertAPIEndpoint(
            name: "api.example.com",
            endpointURLString: "https://api.example.com/health",
            bearerToken: nil
        )
        guard let feed = profileStore.add(
            name: "Agent feed",
            settings: json,
            target: .apiEndpoint,
            apiEndpointID: endpoint.id
        ) else { return }
        scheduledEntryStore.upsert(ScheduledExportEntry(
            profileID: feed.id,
            isEnabled: true,
            frequency: .daily,
            preferredHour: 6,
            preferredMinute: 0,
            includeToday: true,
            todayRefreshEnabled: true,
            todayRefreshIntervalHours: 3
        ))

        guard let mac = profileStore.add(
            name: "Mac archive",
            settings: base,
            target: .connectedMac
        ) else { return }
        scheduledEntryStore.upsert(ScheduledExportEntry(
            profileID: mac.id,
            isEnabled: false,
            frequency: .daily,
            preferredHour: 23,
            preferredMinute: 0
        ))

        // Re-activate Daily so the app adopts its Vault/Health folder, as choosing it would.
        _ = activate(profileID: daily.id)
    }

    /// `<Documents>/<components>`, created on demand and saved as a destination named by
    /// that path (e.g. "Vault/Health"). Nil when the folder cannot be created or bookmarked.
    private func screenshotFolderID(_ components: [String]) -> UUID? {
        guard let documents = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first else {
            return nil
        }
        let folder = components.reduce(documents) { $0.appendingPathComponent($1, isDirectory: true) }
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            let bookmark = try folder.bookmarkData()
            return destinationStore.upsertVault(
                name: components.joined(separator: "/"),
                standardizedPath: folder.standardizedFileURL.path,
                bookmarkData: bookmark
            ).id
        } catch {
            return nil
        }
    }
}
#endif
