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

    // MARK: - Version Comparison (static pure functions)

    func testVersionIsLessThan_basic() {
        XCTAssertTrue(PurchaseManager.versionIsLessThan("1.6.3", "1.7.0"))
        XCTAssertFalse(PurchaseManager.versionIsLessThan("1.7.0", "1.7.0"))
        XCTAssertFalse(PurchaseManager.versionIsLessThan("1.7.1", "1.7.0"))
    }

    func testVersionIsLessThan_differentLengths() {
        XCTAssertTrue(PurchaseManager.versionIsLessThan("1.6", "1.7.0"))
        XCTAssertFalse(PurchaseManager.versionIsLessThan("2.0", "1.7.0"))
    }

    func testVersionIsLessThan_buildNumbers() {
        XCTAssertTrue(PurchaseManager.versionIsLessThan("202603202036", "202603221949"))
        XCTAssertFalse(PurchaseManager.versionIsLessThan("202603221949", "202603221949"))
        XCTAssertFalse(PurchaseManager.versionIsLessThan("202603231000", "202603221949"))
    }

    // MARK: - Build Number Detection

    func testIsBuildNumber_numericOnly() {
        XCTAssertTrue(PurchaseManager.isBuildNumber("202603221949"))
        XCTAssertTrue(PurchaseManager.isBuildNumber("5"))
        XCTAssertTrue(PurchaseManager.isBuildNumber("3"))
    }

    func testIsBuildNumber_marketingVersion() {
        XCTAssertFalse(PurchaseManager.isBuildNumber("1.6.3"))
        XCTAssertFalse(PurchaseManager.isBuildNumber("1.7.0"))
    }

    func testIsBuildNumber_empty() {
        XCTAssertFalse(PurchaseManager.isBuildNumber(""))
    }

    // MARK: - Legacy Version Detection

    func testIsLegacyVersion_macOS_prePaid() {
        XCTAssertTrue(PurchaseManager.isLegacyVersion("1.6.3"))
        XCTAssertTrue(PurchaseManager.isLegacyVersion("1.0.0"))
    }

    func testIsLegacyVersion_macOS_freemium() {
        XCTAssertFalse(PurchaseManager.isLegacyVersion("1.7.0"))
        XCTAssertFalse(PurchaseManager.isLegacyVersion("2.0.0"))
    }

    func testIsLegacyVersion_iOS_prePaidBuildNumber() {
        XCTAssertTrue(PurchaseManager.isLegacyVersion("202603202036"))
        XCTAssertTrue(PurchaseManager.isLegacyVersion("5"))
    }

    func testIsLegacyVersion_iOS_freemiumBuildNumber() {
        XCTAssertFalse(PurchaseManager.isLegacyVersion("202603221949"))
        XCTAssertFalse(PurchaseManager.isLegacyVersion("202603231000"))
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
