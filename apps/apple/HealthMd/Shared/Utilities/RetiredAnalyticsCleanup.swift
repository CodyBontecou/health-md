import Foundation

/// Upgrade migration only: removes retired analytics state without creating identifiers or sending requests.
enum RetiredAnalyticsCleanup {
    static func run(defaults: UserDefaults = .standard) {
        for key in [
            "analytics.apple_ads.attribution.v1",
            "pricing.analytics.health.authorization.statuses.tracked.v1",
            "pricing.analytics.install_id.v1",
            "pricing.analytics.mac.setup.folder.selected.tracked.v1",
            "pricing.analytics.mac.setup.folder.viewed.tracked.v1",
            "pricing.analytics.mac.setup.ready.tracked.v1",
            "pricing.analytics.onboarding.folder.selected.tracked.v1",
            "pricing.analytics.onboarding.skips.tracked.v1",
            "pricing.analytics.onboarding.started.tracked.v1",
            "pricing.analytics.onboarding.steps.tracked.v1",
            "pricing.analytics.queue.v1",
            "pricing.experiment.assignment.v1",
        ] {
            defaults.removeObject(forKey: key)
        }
    }
}
