import XCTest
@testable import HealthMd

@MainActor
final class ClinicAccessStoreTests: XCTestCase {
    private var suite = ""
    private var defaults: UserDefaults!
    private var keychain: FakeKeychainStore!

    override func setUp() {
        super.setUp()
        suite = "ClinicAccessStoreTests.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)
        keychain = FakeKeychainStore()
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testChoicesPersistAcrossInstances() throws {
        let store = ClinicAccessStore(defaults: defaults, keychain: keychain)
        XCTAssertFalse(store.isSharingEnabled)
        let profileID = UUID()
        store.setSharingEnabled(true)
        store.setClinicDestinationProfile(profileID)
        try store.saveUploadToken("  token-1 ")

        let reloaded = ClinicAccessStore(defaults: defaults, keychain: keychain)
        XCTAssertTrue(reloaded.isSharingEnabled)
        XCTAssertEqual(reloaded.clinicDestinationProfileID, profileID)
        XCTAssertTrue(reloaded.usesClinicDestination)
        XCTAssertTrue(reloaded.hasUploadToken)
        XCTAssertEqual(keychain.stringStorage[ClinicAccessStore.Key.uploadToken], "token-1")
        XCTAssertNil(defaults.object(forKey: ClinicAccessStore.Key.uploadToken), "Tokens never go to UserDefaults")
    }

    func testChoosingNoAutomationClearsTheClinicDestination() {
        let store = ClinicAccessStore(defaults: defaults, keychain: keychain)
        store.setClinicDestinationProfile(UUID())
        store.setClinicDestinationProfile(nil)
        XCTAssertFalse(ClinicAccessStore(defaults: defaults, keychain: keychain).usesClinicDestination)
    }

    func testEmptyTokenRemovesKeychainItem() throws {
        let store = ClinicAccessStore(defaults: defaults, keychain: keychain)
        try store.saveUploadToken("token")
        try store.saveUploadToken("   ")
        XCTAssertFalse(store.hasUploadToken)
        XCTAssertNil(keychain.stringStorage[ClinicAccessStore.Key.uploadToken])
    }

    func testRefreshReloadsAndStampsTime() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let store = ClinicAccessStore(defaults: defaults, keychain: keychain, now: { now })
        defaults.set(true, forKey: ClinicAccessStore.Key.sharing)
        store.refresh()
        XCTAssertTrue(store.isSharingEnabled)
        XCTAssertEqual(store.lastRefreshedAt, now)
    }

    func testDisconnectClearsEverything() throws {
        let store = ClinicAccessStore(defaults: defaults, keychain: keychain)
        defaults.set("Clinic", forKey: ClinicAccessStore.Key.clinicName)
        store.refresh()
        store.setSharingEnabled(true)
        store.setClinicDestinationProfile(UUID())
        try store.saveUploadToken("token")

        try store.disconnect()

        XCTAssertNil(store.clinicName)
        XCTAssertFalse(store.isSharingEnabled)
        XCTAssertFalse(store.usesClinicDestination)
        XCTAssertNil(defaults.object(forKey: ClinicAccessStore.Key.clinicDestinationProfileID))
        XCTAssertFalse(store.hasUploadToken)
        XCTAssertNil(store.lastRefreshedAt)
        XCTAssertTrue(keychain.stringStorage.isEmpty)
    }

    func testFailedKeychainRemovalKeepsStateIntact() {
        let store = ClinicAccessStore(defaults: defaults, keychain: keychain)
        store.setSharingEnabled(true)
        keychain.nextRemoveError = SystemKeychainStoreError.deleteFailed(-1)
        XCTAssertThrowsError(try store.disconnect())
        XCTAssertTrue(store.isSharingEnabled, "Nothing is half-cleared when Keychain refuses")
    }
}
