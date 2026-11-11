import Foundation

/// Determines when to prompt users for an App Store review.
///
/// Strategy:
/// - Trigger after the **3rd full successful export** (first milestone)
/// - Then every **30 successful exports** thereafter
/// - Enforce a **120-day cooldown** between introductions or native request attempts
/// - Only count *full* successes — partial exports and failures don't qualify
final class ReviewManager {
    static let shared = ReviewManager()

    private enum Keys {
        static let successfulExportCount = "reviewManager.successfulExportCount"
        static let lastReviewRequestDate = "reviewManager.lastReviewRequestDate"
        static let lastIntroductionDate = "reviewManager.lastIntroductionDate"
        static let lastIntroductionRelease = "reviewManager.lastIntroductionRelease"
    }

    private let firstMilestone = 3
    private let repeatInterval = 30
    private let cooldown: TimeInterval = 120 * 24 * 60 * 60

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

    /// Records an attempt, never proof that StoreKit displayed UI or a review was submitted.
    func didRequestReview() {
        lastReviewRequestDate = now()
    }

    /// Reserves one presentation across roots/windows and survives dismissal or restart.
    /// A release-triggered introduction is limited to one per major/minor release.
    func claimIntroduction(forRelease version: String? = nil) -> Bool {
        guard successfulExportCount >= firstMilestone, isOutsideCooldown else { return false }
        if let version {
            guard let family = Self.releaseFamily(version),
                  defaults.string(forKey: Keys.lastIntroductionRelease) != family else { return false }
            defaults.set(family, forKey: Keys.lastIntroductionRelease)
        }
        guard let data = try? JSONEncoder().encode(now()) else { return false }
        defaults.set(data, forKey: Keys.lastIntroductionDate)
        return true
    }

    static func releaseFamily(_ version: String) -> String? {
        let parts = version.split(separator: ".", omittingEmptySubsequences: false)
        guard (2...3).contains(parts.count),
              parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) && Int($0) != nil }) else { return nil }
        return "\(parts[0]).\(parts[1])"
    }

    static func shouldPresentReleaseNotes(current: String, lastSeen: String?) -> Bool {
        guard let family = releaseFamily(current) else { return false }
        guard let lastSeen else { return true }
        return family != releaseFamily(lastSeen)
    }

    private var isOutsideCooldown: Bool {
        let introductionDate = defaults.data(forKey: Keys.lastIntroductionDate)
            .flatMap { try? JSONDecoder().decode(Date.self, from: $0) }
        return [lastReviewRequestDate, introductionDate].compactMap { $0 }.allSatisfy {
            now().timeIntervalSince($0) >= cooldown
        }
    }

    // MARK: - Private

    private func shouldRequest() -> Bool {
        let count = successfulExportCount

        // Must land on a milestone
        let isFirstMilestone = (count == firstMilestone)
        let isRepeatMilestone = count > firstMilestone && ((count - firstMilestone) % repeatInterval == 0)
        guard isFirstMilestone || isRepeatMilestone else { return false }

        return isOutsideCooldown
    }
}
