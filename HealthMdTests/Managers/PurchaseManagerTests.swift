//
//  PurchaseManagerTests.swift
//  HealthMdTests
//
//  Tests for PurchaseManager state machine and business logic.
//  No StoreKit or network calls — uses injected fakes.
//

import XCTest
@testable import HealthMd

@MainActor
final class PurchaseManagerTests: XCTestCase {

    // STATIC RETENTION JUSTIFICATION: PurchaseManager is an ObservableObject.
    // Static retention avoids macOS 26 / Swift 6 deinit crash.
    // See docs/testing/lifecycle-audit.md.
    private static var retainedManagers: [PurchaseManager] = []

    private var keychain: FakeKeychainStore!
    private var defaults: FakeUserDefaults!

    override func setUp() {
        super.setUp()
        keychain = FakeKeychainStore()
        defaults = FakeUserDefaults()
    }

    private func makeManager() -> PurchaseManager {
        let manager = PurchaseManager(keychain: keychain, defaults: defaults)
        Self.retainedManagers.append(manager)
        return manager
    }

    // MARK: - Legacy Unlock Decision

    /// Build a UTC date for use in date-based assertions.
    private func date(_ year: Int, _ month: Int, _ day: Int) -> Date {
        var components = DateComponents()
        components.year = year; components.month = month; components.day = day
        components.timeZone = TimeZone(identifier: "UTC")
        return Calendar(identifier: .gregorian).date(from: components)!
    }

    func testIsLegacyUnlock_grandfathersAnyInstallBeforeCutoff() {
        // Pre-freemium paid era.
        XCTAssertTrue(PurchaseManager.isLegacyUnlock(originalPurchaseDate: date(2026, 1, 1)))
        XCTAssertTrue(PurchaseManager.isLegacyUnlock(originalPurchaseDate: date(2026, 3, 15)))
        // v1.7.x freemium era.
        XCTAssertTrue(PurchaseManager.isLegacyUnlock(originalPurchaseDate: date(2026, 3, 25)))
        // v1.8.0 / v1.8.1 leak cohort (incl. Morgan, 2026-04-14).
        XCTAssertTrue(PurchaseManager.isLegacyUnlock(originalPurchaseDate: date(2026, 4, 14)))
        XCTAssertTrue(PurchaseManager.isLegacyUnlock(originalPurchaseDate: date(2026, 5, 31)))
    }

    func testIsLegacyUnlock_doesNotGrandfatherInstallsAtOrAfterCutoff() {
        XCTAssertFalse(PurchaseManager.isLegacyUnlock(originalPurchaseDate: PurchaseManager.grandfatherCutoffDate))
        XCTAssertFalse(PurchaseManager.isLegacyUnlock(originalPurchaseDate: date(2026, 9, 1)))
        XCTAssertFalse(PurchaseManager.isLegacyUnlock(originalPurchaseDate: date(2027, 1, 15)))
    }

    func testIsLegacyUnlock_cutoffBoundaryIsStrict() {
        XCTAssertTrue(PurchaseManager.isLegacyUnlock(
            originalPurchaseDate: PurchaseManager.grandfatherCutoffDate.addingTimeInterval(-1)
        ))
        XCTAssertFalse(PurchaseManager.isLegacyUnlock(
            originalPurchaseDate: PurchaseManager.grandfatherCutoffDate
        ))
    }

    // MARK: - Free Export Quota

    func testFreeExportsRemaining_defaultIsThree() {
        let manager = makeManager()
        XCTAssertEqual(manager.freeExportsRemaining, 3)
    }

    func testRecordExportUse_decrementsRemaining() {
        let manager = makeManager()
        manager.recordExportUse()
        XCTAssertEqual(manager.freeExportsRemaining, 2)
    }

    func testRecordExportUse_stopsAtZero() {
        let manager = makeManager()
        manager.recordExportUse()
        manager.recordExportUse()
        manager.recordExportUse()
        XCTAssertEqual(manager.freeExportsRemaining, 0)

        // Extra call should not go negative
        manager.recordExportUse()
        XCTAssertEqual(manager.freeExportsRemaining, 0)
    }

    func testResetFreeExports_restoresQuota() {
        let manager = makeManager()
        manager.recordExportUse()
        manager.recordExportUse()
        XCTAssertEqual(manager.freeExportsRemaining, 1)

        manager.resetFreeExports()
        XCTAssertEqual(manager.freeExportsRemaining, 3)
    }

    // MARK: - canExport

    func testCanExport_trueWhenFreeExportsAvailable() {
        let manager = makeManager()
        XCTAssertTrue(manager.canExport)
    }

    func testCanExport_falseWhenQuotaExhaustedAndNotUnlocked() {
        let manager = makeManager()
        manager.recordExportUse()
        manager.recordExportUse()
        manager.recordExportUse()
        XCTAssertFalse(manager.canExport)
    }

    func testRecordExportUse_noOpWhenUnlocked() {
        let manager = makeManager()
        manager.recordExportUse() // use 1
        // Simulate unlock
        manager.setUnlocked(true)
        manager.recordExportUse() // should be no-op
        XCTAssertEqual(manager.freeExportsUsed, 1, "Should not increment when unlocked")
    }

    // MARK: - Keychain Migration

    func testMigration_copiesUserDefaultsToKeychain() {
        // Simulate pre-migration state: value in UserDefaults, not in keychain
        defaults.set(2, forKey: "freeExportsUsed")
        let manager = makeManager()

        XCTAssertEqual(manager.freeExportsUsed, 2, "Should migrate value from UserDefaults")
        XCTAssertTrue(defaults.bool(forKey: "freeExportsUsed_migratedToKeychain"), "Migration flag should be set")
    }

    func testMigration_doesNotRunTwice() {
        defaults.set(2, forKey: "freeExportsUsed")
        let _ = makeManager()

        // Reset keychain but keep migration flag
        keychain.storage = [:]
        let manager2 = makeManager()

        XCTAssertEqual(manager2.freeExportsUsed, 0, "Should not re-migrate since flag is set")
    }
}
