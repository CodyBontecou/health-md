import XCTest
@testable import HealthMd

/// Local derivations behind FolderDestG, MacDestG, CLIDestG and AttentionG copy.
@MainActor
final class GlassSettingsDerivationsTests: XCTestCase {
    // MARK: FolderDestG location line

    private func location(_ path: String) -> String? {
        FolderLocationDescription.parentLocation(
            of: URL(fileURLWithPath: path),
            iCloudDriveTitle: "iCloud Drive",
            onDeviceTitle: "On My iPhone"
        )
    }

    func testICloudAppFolderReadsAsTheAppName() {
        XCTAssertEqual(
            location("/private/var/mobile/Library/Mobile Documents/iCloud~md~obsidian/Documents/Vault"),
            "iCloud Drive › Obsidian"
        )
    }

    func testICloudDriveFolderKeepsItsParents() {
        XCTAssertEqual(
            location("/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Notes/Vault"),
            "iCloud Drive › Notes"
        )
        XCTAssertEqual(
            location("/private/var/mobile/Library/Mobile Documents/com~apple~CloudDocs/Vault"),
            "iCloud Drive"
        )
    }

    func testOnDeviceFoldersUseTheDeviceTitle() {
        XCTAssertEqual(
            location("/private/var/mobile/Containers/Shared/AppGroup/ABC/File Provider Storage/Obsidian/Vault"),
            "On My iPhone › Obsidian"
        )
        XCTAssertEqual(
            location("/private/var/mobile/Containers/Data/Application/1234-ABCD/Documents/Vault"),
            "On My iPhone"
        )
    }

    func testUnknownLocationsFallBackToTheParentFolder() {
        XCTAssertEqual(location("/Volumes/Drive/Health/Vault"), "Health")
    }

    func testDefaultDestinationPreferenceIsOffUntilChosen() throws {
        let suite = "GlassSettingsDerivationsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        XCTAssertFalse(NewAutomationDestinationPreference.usesDefaultFolder(defaults))
        defaults.set(true, forKey: NewAutomationDestinationPreference.key)
        XCTAssertTrue(NewAutomationDestinationPreference.usesDefaultFolder(defaults))
    }

    // MARK: MacDestG range

    func testMacExportRangeUsesTheBoardShape() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        let start = calendar.date(from: DateComponents(year: 2026, month: 10, day: 24))!
        let end = calendar.date(from: DateComponents(year: 2026, month: 10, day: 30))!
        let text = MacExportRequestRange.rangeText(
            start: start, end: end, locale: Locale(identifier: "en_US"), timeZone: calendar.timeZone
        )
        XCTAssertTrue(text.contains("Oct"), text)
        XCTAssertTrue(text.contains("24") && text.contains("30"), text)
        XCTAssertFalse(text.contains("2026"), "Same-year ranges leave the year out")
    }

    func testMacExportRangeBelongsOnlyToTheJobThisIPhoneStarted() {
        let store = MacExportRequestRange()
        let job = UUID()
        store.update(jobID: job, startDate: Date(timeIntervalSince1970: 0), endDate: Date(timeIntervalSince1970: 86_400))
        XCTAssertNotNil(store.rangeText(for: job))
        XCTAssertNil(store.rangeText(for: UUID()), "A Mac-started job shows no dates")
        store.update(jobID: nil, startDate: nil, endDate: nil)
        XCTAssertNil(store.rangeText(for: job))
    }

    // MARK: CLIDestG pairing method

    func testPairingMethodBindsToTheNextPairingOnly() throws {
        let suite = "GlassSettingsDerivationsTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = DirectCLIPairingMethodStore(defaults: defaults)
        let attempt = Date(timeIntervalSince1970: 1_000)

        XCTAssertNil(store.method(forPairingAt: Date(timeIntervalSince1970: 500)), "No guess for older pairings")
        store.noteAttempt(.qr, at: attempt)
        XCTAssertNil(store.method(forPairingAt: Date(timeIntervalSince1970: 900)), "Pairing predates the attempt")
        let paired = Date(timeIntervalSince1970: 1_010)
        XCTAssertEqual(store.method(forPairingAt: paired), .qr)

        // A later typed-code attempt that never completes does not relabel the pairing.
        store.noteAttempt(.code, at: Date(timeIntervalSince1970: 2_000))
        XCTAssertEqual(store.method(forPairingAt: paired), .qr)
        XCTAssertEqual(DirectCLIPairingMethodStore(defaults: defaults).method(forPairingAt: paired), .qr)

        store.forget()
        XCTAssertNil(store.method(forPairingAt: paired))
    }

    // MARK: AttentionG counts

    func testSmallCountsAreSpelledOut() {
        let english = Locale(identifier: "en_US")
        XCTAssertEqual(AttentionCountText.spelled(3, locale: english), "three")
        XCTAssertEqual(AttentionCountText.spelled(10, locale: english), "ten")
        XCTAssertEqual(AttentionCountText.spelled(12, locale: english), "12")
        XCTAssertEqual(AttentionCountText.spelled(3, locale: Locale(identifier: "de_DE")), "drei")
    }
}
