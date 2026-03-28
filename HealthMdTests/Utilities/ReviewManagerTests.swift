//
//  ReviewManagerTests.swift
//  HealthMdTests
//
//  Tests for ReviewManager milestone triggers and cooldown enforcement.
//

import XCTest
@testable import HealthMd

@MainActor
final class ReviewManagerTests: XCTestCase {

    // STATIC RETENTION JUSTIFICATION: ReviewManager is an ObservableObject.
    // Static retention avoids macOS 26 / Swift 6 deinit crash.
    // See docs/testing/lifecycle-audit.md.
    private static var retainedManagers: [ReviewManager] = []

    private var defaults: FakeUserDefaults!

    override func setUp() {
        super.setUp()
        defaults = FakeUserDefaults()
    }

    // Fixed date: 2026-03-15T12:00:00Z
    private static let fixedNow: Date = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2026, month: 3, day: 15, hour: 12))!
    }()

    private func makeManager(now: @escaping () -> Date = { ReviewManagerTests.fixedNow }) -> ReviewManager {
        let manager = ReviewManager(defaults: defaults, now: now)
        Self.retainedManagers.append(manager)
        return manager
    }

    // MARK: - First Milestone (3rd export)

    func testFirstMilestone_triggersAtThirdExport() {
        let manager = makeManager()
        XCTAssertFalse(manager.recordSuccessfulExport()) // 1
        XCTAssertFalse(manager.recordSuccessfulExport()) // 2
        XCTAssertTrue(manager.recordSuccessfulExport())  // 3 = milestone
    }

    func testSecondExport_doesNotTrigger() {
        let manager = makeManager()
        _ = manager.recordSuccessfulExport() // 1
        XCTAssertFalse(manager.recordSuccessfulExport()) // 2
    }

    // MARK: - Repeat Milestones (every 30 after first)

    func testRepeatMilestone_triggersAt33() {
        // Use advancing time: start at fixedNow, advance 15 days after first milestone
        let manager = makeManager()
        for _ in 1...3 { _ = manager.recordSuccessfulExport() }
        manager.didRequestReview()

        // Create a new manager with time advanced past 14-day cooldown
        let laterDate = Calendar.current.date(byAdding: .day, value: 15, to: Self.fixedNow)!
        let laterManager = makeManager(now: { laterDate })

        for i in 4...33 {
            let result = laterManager.recordSuccessfulExport()
            if i == 33 {
                XCTAssertTrue(result, "Should trigger at 33rd export (3 + 30)")
            } else {
                XCTAssertFalse(result, "Should not trigger at export \(i)")
            }
        }
    }

    func testRepeatMilestone_triggersAt63() {
        let manager = makeManager()
        for _ in 1...3 { _ = manager.recordSuccessfulExport() }
        manager.didRequestReview()

        // Advance past cooldown for milestone 33
        let day15 = Calendar.current.date(byAdding: .day, value: 15, to: Self.fixedNow)!
        let mgr33 = makeManager(now: { day15 })
        for _ in 4...33 { _ = mgr33.recordSuccessfulExport() }
        mgr33.didRequestReview()

        // Advance past cooldown for milestone 63
        let day30 = Calendar.current.date(byAdding: .day, value: 30, to: Self.fixedNow)!
        let mgr63 = makeManager(now: { day30 })
        for i in 34...63 {
            let result = mgr63.recordSuccessfulExport()
            if i == 63 {
                XCTAssertTrue(result, "Should trigger at 63rd export (3 + 30 + 30)")
            }
        }
    }

    // MARK: - Cooldown Enforcement

    func testCooldown_blocksIfTooSoon() {
        let manager = makeManager()
        _ = manager.recordSuccessfulExport() // 1
        _ = manager.recordSuccessfulExport() // 2
        XCTAssertTrue(manager.recordSuccessfulExport()) // 3 = triggers
        manager.didRequestReview()

        // Only 5 days later (within 14-day cooldown)
        let fiveDaysLater = Calendar.current.date(byAdding: .day, value: 5, to: Self.fixedNow)!
        let cooldownManager = makeManager(now: { fiveDaysLater })

        // Reach next milestone (export 33) — should be blocked by cooldown
        for i in 4...33 {
            let result = cooldownManager.recordSuccessfulExport()
            if i == 33 {
                XCTAssertFalse(result, "Should be blocked by cooldown")
            }
        }
    }

    func testCooldown_allowsAfterCooldownExpires() {
        let manager = makeManager()
        _ = manager.recordSuccessfulExport() // 1
        _ = manager.recordSuccessfulExport() // 2
        XCTAssertTrue(manager.recordSuccessfulExport()) // 3 = triggers
        manager.didRequestReview()

        // 15 days later (past 14-day cooldown)
        let fifteenDaysLater = Calendar.current.date(byAdding: .day, value: 15, to: Self.fixedNow)!
        let laterManager = makeManager(now: { fifteenDaysLater })

        for i in 4...33 {
            let result = laterManager.recordSuccessfulExport()
            if i == 33 {
                XCTAssertTrue(result, "Should trigger after cooldown expires")
            }
        }
    }

    // MARK: - Non-milestones

    func testNonMilestone_doesNotTrigger() {
        let manager = makeManager()
        for _ in 1...3 { _ = manager.recordSuccessfulExport() }
        manager.didRequestReview()

        let laterDate = Calendar.current.date(byAdding: .day, value: 15, to: Self.fixedNow)!
        let laterManager = makeManager(now: { laterDate })

        for i in 4...32 {
            XCTAssertFalse(laterManager.recordSuccessfulExport(), "Export \(i) should not trigger review")
        }
    }
}
