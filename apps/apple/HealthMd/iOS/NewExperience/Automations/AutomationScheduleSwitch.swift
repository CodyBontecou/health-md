#if os(iOS)
import Foundation

/// The former "Enable Scheduled Exports" master switch, carried by each automation's own
/// switch: the AutomationsGlass card switch, AutomationDetailG's Pause/Resume, and
/// ScheduleG's "Run on a schedule". Turning one on asks for notification permission, as
/// the master switch did; turning off the last running automation also turns off a
/// legacy single schedule left from before profiles, so nothing keeps running unseen.
enum AutomationScheduleSwitch {
    /// Whether the legacy schedule should stop: it is still on, and no automation runs.
    static func shouldDisableLegacySchedule(
        entries: [ScheduledExportEntry],
        legacyEnabled: Bool
    ) -> Bool {
        legacyEnabled && !entries.contains(where: \.isEnabled)
    }

    /// Call after an automation's schedule was switched and saved.
    @MainActor
    static func didSwitch(
        isEnabled: Bool,
        entries: [ScheduledExportEntry],
        schedulingManager: SchedulingManager
    ) {
        if isEnabled {
            Task { @MainActor in
                _ = await schedulingManager.requestNotificationPermissions()
            }
        } else if shouldDisableLegacySchedule(
            entries: entries,
            legacyEnabled: schedulingManager.schedule.isEnabled
        ) {
            var updated = schedulingManager.schedule
            updated.isEnabled = false
            // The schedule's didSet saves it and refreshes the scheduled automation.
            schedulingManager.schedule = updated
        }
        schedulingManager.refreshScheduledAutomation()
    }
}
#endif
