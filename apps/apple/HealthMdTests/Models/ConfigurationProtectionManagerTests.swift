import SwiftUI
import XCTest
@testable import HealthMd

final class ConfigurationProtectionManagerTests: XCTestCase {
    func testPreferencePersistsAcrossManagerInstances() async {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        await MainActor.run {
            let first = ConfigurationProtectionManager(userDefaults: defaults)
            XCTAssertFalse(first.isEnabled)

            first.setEnabled(true)
            XCTAssertTrue(first.isEnabled)

            let restored = ConfigurationProtectionManager(userDefaults: defaults)
            XCTAssertTrue(restored.isEnabled)

            restored.setEnabled(false)
            XCTAssertFalse(ConfigurationProtectionManager(userDefaults: defaults).isEnabled)
        }
    }

    func testBlockedMutationPresentsToastWithoutRunningChange() async {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        await MainActor.run {
            let manager = ConfigurationProtectionManager(userDefaults: defaults)
            manager.setEnabled(true)
            var mutationCount = 0

            XCTAssertFalse(manager.performConfigurationChange { mutationCount += 1 })
            XCTAssertEqual(mutationCount, 0)
            XCTAssertNotNil(manager.blockedChangeToastID)

            manager.openProtectionSettingFromToast()
            XCTAssertNil(manager.blockedChangeToastID)
            let requestID = manager.settingsNavigationRequestID
            XCTAssertNotNil(requestID)

            if let requestID {
                manager.consumeSettingsNavigationRequest(requestID)
            }
            XCTAssertNil(manager.settingsNavigationRequestID)
        }
    }

    func testUnprotectedMutationRunsNormally() async {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        await MainActor.run {
            let manager = ConfigurationProtectionManager(userDefaults: defaults)
            var mutationCount = 0

            XCTAssertTrue(manager.performConfigurationChange { mutationCount += 1 })
            XCTAssertEqual(mutationCount, 1)
            XCTAssertNil(manager.blockedChangeToastID)
        }
    }

    func testProtectedBindingRejectsChangesUntilProtectionIsDisabled() async {
        let defaults = makeDefaults()
        defer { defaults.removePersistentDomain(forName: defaultsSuiteName(defaults)) }

        await MainActor.run {
            let manager = ConfigurationProtectionManager(userDefaults: defaults)
            var value = "original"
            let source = Binding(get: { value }, set: { value = $0 })
            let protected = manager.protecting(source)

            manager.setEnabled(true)
            protected.wrappedValue = "blocked"
            XCTAssertEqual(value, "original")
            XCTAssertNotNil(manager.blockedChangeToastID)

            manager.setEnabled(false)
            protected.wrappedValue = "updated"
            XCTAssertEqual(value, "updated")
        }
    }

    private func makeDefaults() -> UserDefaults {
        let suite = "ConfigurationProtectionManagerTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(suite, forKey: "tests.suiteName")
        return defaults
    }

    private func defaultsSuiteName(_ defaults: UserDefaults) -> String {
        defaults.string(forKey: "tests.suiteName")!
    }
}
