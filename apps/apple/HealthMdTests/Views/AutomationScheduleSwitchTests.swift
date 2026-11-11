#if os(iOS)
import XCTest
@testable import HealthMd

/// The former master switch's rule, now carried by each automation's switch.
final class AutomationScheduleSwitchTests: XCTestCase {
    private func entry(_ isEnabled: Bool) -> ScheduledExportEntry {
        ScheduledExportEntry(profileID: UUID(), isEnabled: isEnabled)
    }

    func testLegacyScheduleStopsWhenTheLastAutomationIsSwitchedOff() {
        XCTAssertTrue(AutomationScheduleSwitch.shouldDisableLegacySchedule(
            entries: [entry(false), entry(false)],
            legacyEnabled: true
        ))
        XCTAssertTrue(AutomationScheduleSwitch.shouldDisableLegacySchedule(entries: [], legacyEnabled: true))
    }

    func testLegacyScheduleKeepsRunningWhileAnotherAutomationRuns() {
        XCTAssertFalse(AutomationScheduleSwitch.shouldDisableLegacySchedule(
            entries: [entry(false), entry(true)],
            legacyEnabled: true
        ))
    }

    func testNothingToStopWhenTheLegacyScheduleIsOff() {
        XCTAssertFalse(AutomationScheduleSwitch.shouldDisableLegacySchedule(
            entries: [entry(false)],
            legacyEnabled: false
        ))
    }
}
#endif
