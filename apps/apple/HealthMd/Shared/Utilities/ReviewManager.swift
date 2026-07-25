import Foundation

/// Determines when to prompt users for an App Store review.
///
/// Strategy:
/// - Trigger after the **3rd full successful export** (first milestone)
/// - Then every **30 successful exports** thereafter
/// - Enforce a **14-day cooldown** between prompts so we never feel spammy
/// - Only count *full* successes — partial exports and failures don't qualify
final class ReviewManager {
    static let shared = ReviewManager()

    private enum Keys {
        static let successfulExportCount = "reviewManager.successfulExportCount"
        static let lastReviewRequestDate = "reviewManager.lastReviewRequestDate"
    }

    private let firstMilestone = 3
    private let repeatInterval = 30
    private let cooldownDays = 14

    private let defaults: UserDefaultsStoring
    private let now: () -> Date

    private init() {
        self.defaults = SystemUserDefaults()
        self.now = { Date() }
    }

    init(defaults: UserDefaultsStoring, now: @escaping () -> Date = { Date() }) {
        self.defaults = defaults
        self.now = now
    }

    // MARK: - Persisted State

    private var successfulExportCount: Int {
        get { defaults.integer(forKey: Keys.successfulExportCount) }
        set { defaults.set(newValue, forKey: Keys.successfulExportCount) }
    }

    private var lastReviewRequestDate: Date? {
        get { defaults.data(forKey: Keys.lastReviewRequestDate).flatMap { try? JSONDecoder().decode(Date.self, from: $0) } }
        set {
            if let date = newValue, let data = try? JSONEncoder().encode(date) {
                defaults.set(data, forKey: Keys.lastReviewRequestDate)
            } else {
                defaults.removeObject(forKey: Keys.lastReviewRequestDate)
            }
        }
    }

    // MARK: - Public API

    /// Call after every full successful export.
    /// Returns `true` if the app should now request a review.
    func recordSuccessfulExport() -> Bool {
        successfulExportCount += 1
        return shouldRequest()
    }

    /// Call immediately after showing the review prompt so the cooldown clock starts.
    func didRequestReview() {
        lastReviewRequestDate = now()
    }

    // MARK: - Private

    private func shouldRequest() -> Bool {
        let count = successfulExportCount

        // Must land on a milestone
        let isFirstMilestone = (count == firstMilestone)
        let isRepeatMilestone = count > firstMilestone && ((count - firstMilestone) % repeatInterval == 0)
        guard isFirstMilestone || isRepeatMilestone else { return false }

        // Respect the cooldown between prompts
        if let last = lastReviewRequestDate {
            let days = Calendar.current.dateComponents([.day], from: last, to: now()).day ?? 0
            guard days >= cooldownDays else { return false }
        }

        return true
    }
}
