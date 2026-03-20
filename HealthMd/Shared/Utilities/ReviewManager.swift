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

    private init() {}

    // MARK: - Persisted State

    private var successfulExportCount: Int {
        get { UserDefaults.standard.integer(forKey: Keys.successfulExportCount) }
        set { UserDefaults.standard.set(newValue, forKey: Keys.successfulExportCount) }
    }

    private var lastReviewRequestDate: Date? {
        get { UserDefaults.standard.object(forKey: Keys.lastReviewRequestDate) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Keys.lastReviewRequestDate) }
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
        lastReviewRequestDate = Date()
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
            let days = Calendar.current.dateComponents([.day], from: last, to: Date()).day ?? 0
            guard days >= cooldownDays else { return false }
        }

        return true
    }
}
