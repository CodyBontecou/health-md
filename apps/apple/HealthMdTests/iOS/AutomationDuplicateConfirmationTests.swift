#if os(iOS)
import XCTest
@testable import HealthMd

/// Duplicate on an automation's detail page confirms the copy with a light haptic and
/// "Duplicated as “<name>”" (Android: a tick and a snackbar).
@MainActor
final class AutomationDuplicateConfirmationTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings uses Combine subscriptions and
    // MainActor-isolated deinits that abort on older simulator runtimes; retain for the
    // process lifetime like the other profile-store tests.
    private static var retainedInstances: [AnyObject] = []

    private func makeStore() -> (ExportProfileStore, ExportSettingsSnapshot) {
        let suite = "AutomationDuplicateConfirmationTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        let store = ExportProfileStore(userDefaults: defaults)
        Self.retainedInstances.append(settings)
        Self.retainedInstances.append(store)
        return (store, ExportSettingsSnapshot.from(settings, appleExportEngineAuthorityIsFrozen: false))
    }

    func testConfirmationNamesTheCopyTheStoreCreated() throws {
        let (store, settings) = makeStore()
        let source = store.add(name: "Default", settings: settings, target: .localIPhoneFolder)
        let copy = try XCTUnwrap(store.duplicate(id: source.id))

        let confirmation = AutomationDuplicateConfirmation(copy: copy)

        XCTAssertEqual(copy.name, "Default 2")
        XCTAssertEqual(confirmation.copyID, copy.id)
        XCTAssertEqual(confirmation.copyName, "Default 2")
        XCTAssertEqual(confirmation.message, String(localized: "Duplicated as “\("Default 2")”"))
        XCTAssertTrue(confirmation.message.contains("Default 2"))
    }

    func testEachDuplicateIsANewConfirmationSoTheHapticFiresAgain() throws {
        let (store, settings) = makeStore()
        let source = store.add(name: "Weekly", settings: settings, target: .localIPhoneFolder)
        let first = AutomationDuplicateConfirmation(copy: try XCTUnwrap(store.duplicate(id: source.id)))
        let second = AutomationDuplicateConfirmation(copy: try XCTUnwrap(store.duplicate(id: source.id)))

        XCTAssertNotEqual(first.id, second.id)
        XCTAssertEqual([first.copyName, second.copyName], ["Weekly 2", "Weekly 3"])
    }

    func testConfirmationHidesItselfAfterABriefPause() {
        XCTAssertGreaterThanOrEqual(AutomationDuplicateConfirmation.visibleDuration, .seconds(3))
        XCTAssertLessThanOrEqual(AutomationDuplicateConfirmation.visibleDuration, .seconds(6))
    }
}
#endif
