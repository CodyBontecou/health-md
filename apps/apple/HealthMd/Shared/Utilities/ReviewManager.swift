import Foundation

/// Decides when Health.md may ask StoreKit for an App Store rating.
///
/// Policy (mirrored by Android's `ReviewPromptPolicy`):
/// - Every **full** successful export counts, whatever started it: manual, Google
///   Drive, API, gateway, Mac, scheduled, background or Shortcut. Partial, failed
///   and cancelled exports never count.
/// - Eligible once there are at least **3 full successes** on at least **2 distinct
///   days**.
/// - After a request, wait at least **120 days** *and* a new app version before the
///   next one. Apple shows the system prompt at most three times a year anyway.
/// - The cooldown starts only when the system request is actually made
///   (`didRequestReview()`), never when a prompt was merely considered.
///
/// This type only keeps the counters. The iOS UI decides *where* it may ask
/// (foreground, nothing else presented) and calls StoreKit directly; there is no
/// custom pre-prompt (App Store Review Guideline 5.6.1).
final class ReviewManager {
    static let shared = ReviewManager()

    static let minimumSuccessfulExports = 3
    static let minimumDistinctSuccessDays = 2
    static let cooldown: TimeInterval = 120 * 24 * 60 * 60

    private enum Keys {
        static let successfulExportCount = "reviewManager.successfulExportCount"
        static let successDayCount = "reviewManager.successDayCount"
        static let lastSuccessDay = "reviewManager.lastSuccessDay"
        static let lastReviewRequestDate = "reviewManager.lastReviewRequestDate"
        static let lastReviewRequestVersion = "reviewManager.lastReviewRequestVersion"
        /// Written by the retired custom introduction screen. Still honoured as a
        /// cooldown so people who just saw it are not asked again straight away.
        static let legacyIntroductionDate = "reviewManager.lastIntroductionDate"
    }

    private let defaults: UserDefaultsStoring
    private let now: () -> Date
    private let calendar: Calendar
    private let appVersion: () -> String?

    private init() {
        self.defaults = SystemUserDefaults()
        self.now = { Date() }
        self.calendar = .current
        self.appVersion = { Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String }
    }

    init(
        defaults: UserDefaultsStoring,
        now: @escaping () -> Date = { Date() },
        calendar: Calendar = .current,
        appVersion: @escaping () -> String? = { "1.0" }
    ) {
        self.defaults = defaults
        self.now = now
        self.calendar = calendar
        self.appVersion = appVersion
    }

    // MARK: - Recording

    /// Call after every full successful export, from any source.
    /// Counting never presents anything.
    func recordSuccessfulExport() {
        let previousCount = defaults.integer(forKey: Keys.successfulExportCount)
        defaults.set(previousCount + 1, forKey: Keys.successfulExportCount)

        let today = dayKey(for: now())
        let lastDay = defaults.string(forKey: Keys.lastSuccessDay)
        guard lastDay != today else { return }
        var days = defaults.integer(forKey: Keys.successDayCount)
        if lastDay == nil, previousCount > 0 {
            // Counted before days were tracked: that earlier use is one day.
            days = max(days, 1)
        }
        defaults.set(days + 1, forKey: Keys.successDayCount)
        defaults.set(today, forKey: Keys.lastSuccessDay)
    }

    /// Records that the system review request was made. StoreKit decides whether it
    /// shows anything, so this is an attempt, not proof of a rating.
    func didRequestReview() {
        if let data = try? JSONEncoder().encode(now()) {
            defaults.set(data, forKey: Keys.lastReviewRequestDate)
        }
        if let version = appVersion() {
            defaults.set(version, forKey: Keys.lastReviewRequestVersion)
        }
    }

    // MARK: - Eligibility

    /// True when the usage threshold is met and the previous request (if any) is at
    /// least 120 days old and was made on a different app version.
    var isEligibleForReviewRequest: Bool {
        guard defaults.integer(forKey: Keys.successfulExportCount) >= Self.minimumSuccessfulExports,
              defaults.integer(forKey: Keys.successDayCount) >= Self.minimumDistinctSuccessDays else { return false }

        let current = now()
        let previousAttempts = [Keys.lastReviewRequestDate, Keys.legacyIntroductionDate].compactMap(date(forKey:))
        // A date in the future (clock rollback) also blocks.
        guard previousAttempts.allSatisfy({ current.timeIntervalSince($0) >= Self.cooldown }) else { return false }

        if defaults.data(forKey: Keys.lastReviewRequestDate) != nil,
           let lastVersion = defaults.string(forKey: Keys.lastReviewRequestVersion),
           lastVersion == appVersion() {
            return false
        }
        return true
    }

    #if DEBUG
    /// Debug-only setup for device QA: meets the usage threshold and clears any
    /// earlier request, so the next foreground success asks StoreKit.
    func seedEligibleForTesting() {
        defaults.set(Self.minimumSuccessfulExports, forKey: Keys.successfulExportCount)
        defaults.set(Self.minimumDistinctSuccessDays, forKey: Keys.successDayCount)
        defaults.set(dayKey(for: now()), forKey: Keys.lastSuccessDay)
        defaults.removeObject(forKey: Keys.lastReviewRequestDate)
        defaults.removeObject(forKey: Keys.lastReviewRequestVersion)
        defaults.removeObject(forKey: Keys.legacyIntroductionDate)
    }
    #endif

    // MARK: - Release notes

    // Release-family helpers used by What's New; they predate this type's review role.

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

    // MARK: - Private

    private func date(forKey key: String) -> Date? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(Date.self, from: $0) }
    }

    private func dayKey(for date: Date) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}
