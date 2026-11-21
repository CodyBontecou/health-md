//
//  ReviewManagerTests.swift
//  HealthMdTests
//
//  Tests for the App Store review request policy: a threshold of full successes
//  on distinct days, and a 120-day plus new-version cooldown after each request.
//

import XCTest
@testable import HealthMd

@MainActor
final class ReviewManagerTests: XCTestCase {

    // STATIC RETENTION JUSTIFICATION: avoids the macOS 26 / Swift 6 deinit crash
    // seen with per-test manager instances. See docs/testing/lifecycle-audit.md.
    private static var retainedManagers: [ReviewManager] = []

    private var defaults: FakeUserDefaults!

    override func setUp() {
        super.setUp()
        defaults = FakeUserDefaults()
    }

    // Fixed date: 2026-03-15T12:00:00Z
    nonisolated private static let fixedNow: Date = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12))!
    }()

    nonisolated private static let utc: Calendar = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal
    }()

    /// A manager whose clock is `days` after the fixed date, on `version`.
    private func manager(day days: Double = 0, version: String = "4.1.0") -> ReviewManager {
        let date = Self.fixedNow.addingTimeInterval(days * 86_400)
        let manager = ReviewManager(defaults: defaults, now: { date }, calendar: Self.utc, appVersion: { version })
        Self.retainedManagers.append(manager)
        return manager
    }

    /// Three full successes over two days: the minimum eligible usage.
    private func establishUsage() {
        manager(day: 0).recordSuccessfulExport()
        manager(day: 0).recordSuccessfulExport()
        manager(day: 1).recordSuccessfulExport()
    }

    // MARK: - Threshold

    func testFreshInstall_isNotEligible() {
        XCTAssertFalse(manager().isEligibleForReviewRequest)
    }

    func testThreeSuccessesOnOneDay_isNotEligible() {
        for _ in 1...3 { manager().recordSuccessfulExport() }
        XCTAssertFalse(manager().isEligibleForReviewRequest, "Needs a second day of use")
    }

    func testTwoSuccessesOnTwoDays_isNotEligible() {
        manager(day: 0).recordSuccessfulExport()
        manager(day: 1).recordSuccessfulExport()
        XCTAssertFalse(manager(day: 1).isEligibleForReviewRequest, "Needs three full successes")
    }

    func testThreeSuccessesOnTwoDays_isEligible() {
        establishUsage()
        XCTAssertTrue(manager(day: 1).isEligibleForReviewRequest)
    }

    func testThresholdIsNotAnExactCount() {
        for day in 0..<10 { manager(day: Double(day)).recordSuccessfulExport() }
        XCTAssertTrue(manager(day: 9).isEligibleForReviewRequest, "Later successes stay eligible")
    }

    func testSameCalendarDayCountsOnce() {
        manager(day: 0).recordSuccessfulExport()
        manager(day: 0.4).recordSuccessfulExport() // 21:36 UTC, same day
        manager(day: 0.45).recordSuccessfulExport()
        XCTAssertFalse(manager(day: 0.45).isEligibleForReviewRequest)
    }

    func testCountsRecordedBeforeDayTrackingCountAsOneEarlierDay() {
        // An upgrade from the exact-count policy leaves only the export count.
        defaults.set(5, forKey: "reviewManager.successfulExportCount")
        XCTAssertFalse(manager().isEligibleForReviewRequest)
        manager().recordSuccessfulExport()
        XCTAssertTrue(manager().isEligibleForReviewRequest)
    }

    // MARK: - Cooldown and version

    func testConsideringEligibilityDoesNotStartCooldown() {
        establishUsage()
        XCTAssertTrue(manager(day: 1).isEligibleForReviewRequest)
        XCTAssertTrue(manager(day: 1).isEligibleForReviewRequest, "Only a real request starts the cooldown")
    }

    func testRequestBlocksForCooldownEvenOnNewVersion() {
        establishUsage()
        manager(day: 1).didRequestReview()
        XCTAssertFalse(manager(day: 1).isEligibleForReviewRequest)
        XCTAssertFalse(manager(day: 120, version: "4.2.0").isEligibleForReviewRequest)
        XCTAssertTrue(manager(day: 121, version: "4.2.0").isEligibleForReviewRequest)
    }

    func testRequestBlocksSameVersionAfterCooldown() {
        establishUsage()
        manager(day: 1, version: "4.1.0").didRequestReview()
        XCTAssertFalse(manager(day: 400, version: "4.1.0").isEligibleForReviewRequest)
        XCTAssertTrue(manager(day: 400, version: "4.1.1").isEligibleForReviewRequest)
    }

    func testLegacyIntroductionDateStillCoolsDown() {
        establishUsage()
        let shown = try! JSONEncoder().encode(Self.fixedNow)
        defaults.set(shown, forKey: "reviewManager.lastIntroductionDate")
        XCTAssertFalse(manager(day: 1).isEligibleForReviewRequest)
        XCTAssertTrue(manager(day: 120).isEligibleForReviewRequest)
    }

    func testClockRollbackDoesNotBypassCooldown() {
        establishUsage()
        manager(day: 1).didRequestReview()
        XCTAssertFalse(manager(day: -1, version: "9.0").isEligibleForReviewRequest)
    }

    #if DEBUG
    func testDebugSeedMakesNextRequestEligible() {
        manager().seedEligibleForTesting()
        XCTAssertTrue(manager().isEligibleForReviewRequest)
        manager().didRequestReview()
        XCTAssertFalse(manager().isEligibleForReviewRequest)
        manager().seedEligibleForTesting()
        XCTAssertTrue(manager().isEligibleForReviewRequest)
    }
    #endif

    // MARK: - Release notes

    func testReleaseNotesSkipPatchesAndAllowMinorAndMajorUpdates() {
        XCTAssertFalse(ReviewManager.shouldPresentReleaseNotes(current: "3.4.4", lastSeen: "3.4.3"))
        XCTAssertFalse(ReviewManager.shouldPresentReleaseNotes(current: "3.4.4", lastSeen: "3.4.4"))
        XCTAssertTrue(ReviewManager.shouldPresentReleaseNotes(current: "3.5.0", lastSeen: "3.4.4"))
        XCTAssertTrue(ReviewManager.shouldPresentReleaseNotes(current: "4.0.0", lastSeen: "3.5.0"))
        XCTAssertTrue(ReviewManager.shouldPresentReleaseNotes(current: "3.5.0", lastSeen: nil))
    }

    func testInvalidReleaseFamilies() {
        for version in ["", "3", "3..0", "3.a.0", "-3.5.0", "3.5.0.1"] {
            XCTAssertNil(ReviewManager.releaseFamily(version), version)
        }
        XCTAssertEqual(ReviewManager.releaseFamily("3.5.2"), "3.5")
    }
}
