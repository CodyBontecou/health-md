import XCTest
@testable import HealthMd
import ExportAutomationKit

final class ExportTriggerSourcePolicyTests: XCTestCase {
    func testTriggerSourceRawValuesAreDomainFreeAndCodable() throws {
        XCTAssertEqual(ExportTriggerSource.manual.rawValue, "manual")
        XCTAssertEqual(ExportTriggerSource.scheduled.rawValue, "scheduled")
        XCTAssertEqual(ExportTriggerSource.shortcut.rawValue, "shortcut")
        XCTAssertEqual(ExportTriggerSource.silentPush.rawValue, "silent_push")
        XCTAssertEqual(ExportTriggerSource.backgroundTask.rawValue, "background_task")
        XCTAssertEqual(ExportTriggerSource.scheduledWake.rawValue, "scheduled_wake")
        XCTAssertEqual(ExportTriggerSource.dataSourceBackgroundDelivery.rawValue, "data_source_background_delivery")
        XCTAssertEqual(ExportTriggerSource.notificationTapRetry.rawValue, "notification_tap_retry")
        XCTAssertEqual(ExportTriggerSource.appActiveDrain.rawValue, "app_active_drain")
        XCTAssertEqual(ExportTriggerSource.connectedPeer.rawValue, "connected_peer")

        let data = try JSONEncoder().encode(ExportTriggerSource.allCases)
        let decoded = try JSONDecoder().decode([ExportTriggerSource].self, from: data)
        XCTAssertEqual(decoded, ExportTriggerSource.allCases)
    }

    func testPrimaryTriggerPoliciesDescribeHistoryDestinationQuotaAndExecution() {
        let manual = ExportTriggerSource.manual.policy()
        XCTAssertEqual(manual.sourceFamily, .manual)
        XCTAssertEqual(manual.quotaPolicy, .oncePerSuccessfulRun)
        XCTAssertEqual(manual.destinationPolicy, .appSelected)
        XCTAssertEqual(manual.executionContext, .foreground)
        XCTAssertEqual(manual.scheduleUpdatePolicy, .never)

        let scheduled = ExportTriggerSource.silentPush.policy()
        XCTAssertEqual(scheduled.sourceFamily, .scheduled)
        XCTAssertEqual(scheduled.quotaPolicy, .never)
        XCTAssertEqual(scheduled.destinationPolicy, .localDevice)
        XCTAssertEqual(scheduled.executionContext, .background)
        XCTAssertEqual(scheduled.scheduleUpdatePolicy, .afterSuccessfulRun)

        let shortcut = ExportTriggerSource.shortcut.policy()
        XCTAssertEqual(shortcut.sourceFamily, .shortcut)
        XCTAssertEqual(shortcut.quotaPolicy, .oncePerSuccessfulRun)
        XCTAssertEqual(shortcut.destinationPolicy, .localDevice)
        XCTAssertEqual(shortcut.executionContext, .foreground)
        XCTAssertEqual(shortcut.scheduleUpdatePolicy, .whenPreviousCompleteDayWasIncluded)

        let connectedPeer = ExportTriggerSource.connectedPeer.policy()
        XCTAssertEqual(connectedPeer.sourceFamily, .connectedPeer)
        XCTAssertEqual(connectedPeer.quotaPolicy, .oncePerSuccessfulRun)
        XCTAssertEqual(connectedPeer.destinationPolicy, .connectedPeer)
        XCTAssertEqual(connectedPeer.executionContext, .foreground)
        XCTAssertEqual(connectedPeer.scheduleUpdatePolicy, .never)
    }

    func testRetryPoliciesResolveToStoredPendingSourceFamily() {
        let scheduledTap = ExportTriggerSource.notificationTapRetry.policy(resolvedSourceFamily: .scheduled)
        XCTAssertEqual(scheduledTap.sourceFamily, .scheduled)
        XCTAssertEqual(scheduledTap.quotaPolicy, .never)
        XCTAssertEqual(scheduledTap.destinationPolicy, .localDevice)
        XCTAssertEqual(scheduledTap.executionContext, .foreground)
        XCTAssertEqual(scheduledTap.scheduleUpdatePolicy, .afterSuccessfulRun)

        let shortcutDrain = ExportTriggerSource.appActiveDrain.policy(resolvedSourceFamily: .shortcut)
        XCTAssertEqual(shortcutDrain.sourceFamily, .shortcut)
        XCTAssertEqual(shortcutDrain.quotaPolicy, .oncePerSuccessfulRun)
        XCTAssertEqual(shortcutDrain.destinationPolicy, .localDevice)
        XCTAssertEqual(shortcutDrain.executionContext, .foreground)
        XCTAssertEqual(shortcutDrain.scheduleUpdatePolicy, .whenPreviousCompleteDayWasIncluded)
    }

    func testQuotaPolicyCountsOncePerSuccessfulEligibleRun() {
        let manual = ExportTriggerSource.manual.policy()
        XCTAssertTrue(manual.shouldRecordQuota(successCount: 3))
        XCTAssertFalse(manual.shouldRecordQuota(successCount: 0))
        XCTAssertFalse(manual.shouldRecordQuota(successCount: 3, alreadyRecorded: true))

        let shortcut = ExportTriggerSource.shortcut.policy()
        XCTAssertTrue(shortcut.shouldRecordQuota(successCount: 2))

        let connectedPeer = ExportTriggerSource.connectedPeer.policy()
        XCTAssertTrue(connectedPeer.shouldRecordQuota(successCount: 1))
        XCTAssertFalse(connectedPeer.shouldRecordQuota(successCount: 1, alreadyRecorded: true))

        let backgroundScheduled = ExportTriggerSource.backgroundTask.policy()
        XCTAssertFalse(backgroundScheduled.shouldRecordQuota(successCount: 1))
    }

    func testScheduleUpdatePolicyPreservesScheduledAndShortcutSemantics() {
        let calendar = Self.calendar
        let now = date(2026, 5, 18, hour: 9)
        let yesterday = date(2026, 5, 17)
        let olderDay = date(2026, 5, 10)

        let scheduled = ExportTriggerSource.backgroundTask.policy()
        XCTAssertTrue(scheduled.shouldUpdateLastExport(successCount: 1, exportedDates: [], now: now, calendar: calendar))
        XCTAssertFalse(scheduled.shouldUpdateLastExport(successCount: 0, exportedDates: [yesterday], now: now, calendar: calendar))

        let shortcut = ExportTriggerSource.shortcut.policy()
        XCTAssertTrue(shortcut.shouldUpdateLastExport(successCount: 1, exportedDates: [olderDay, yesterday], now: now, calendar: calendar))
        XCTAssertFalse(shortcut.shouldUpdateLastExport(successCount: 1, exportedDates: [olderDay], now: now, calendar: calendar))
        XCTAssertFalse(shortcut.shouldUpdateLastExport(successCount: 0, exportedDates: [yesterday], now: now, calendar: calendar))
    }

    func testExistingAutomationSourcesBridgeIntoTriggerSources() {
        XCTAssertEqual(AutomationBackgroundTrigger.silentPush.exportTriggerSource, .silentPush)
        XCTAssertEqual(AutomationBackgroundTrigger.backgroundTask.exportTriggerSource, .backgroundTask)
        XCTAssertEqual(AutomationBackgroundTrigger.scheduledWake.exportTriggerSource, .scheduledWake)
        XCTAssertEqual(AutomationBackgroundTrigger.dataSourceBackgroundDelivery.exportTriggerSource, .dataSourceBackgroundDelivery)

        XCTAssertEqual(AutomationPendingExportRetryTrigger.notificationTap.exportTriggerSource, .notificationTapRetry)
        XCTAssertEqual(AutomationPendingExportRetryTrigger.appActiveDrain.exportTriggerSource, .appActiveDrain)

        XCTAssertEqual(PendingExportSource.scheduled.exportTriggerSource, .scheduled)
        XCTAssertEqual(PendingExportSource.scheduled.exportTriggerSourceFamily, .scheduled)
        XCTAssertEqual(PendingExportSource.shortcut.exportTriggerSource, .shortcut)
        XCTAssertEqual(PendingExportSource.shortcut.exportTriggerSourceFamily, .shortcut)
    }

    func testHealthHistorySourceMappingPreservesExistingLabels() {
        XCTAssertEqual(ExportSource(triggerSource: .manual), .manual)
        XCTAssertEqual(ExportSource(triggerSource: .scheduled), .scheduled)
        XCTAssertEqual(ExportSource(triggerSource: .silentPush), .scheduled)
        XCTAssertEqual(ExportSource(triggerSource: .backgroundTask), .scheduled)
        XCTAssertEqual(ExportSource(triggerSource: .dataSourceBackgroundDelivery), .scheduled)
        XCTAssertEqual(ExportSource(triggerSource: .notificationTapRetry, resolvedSourceFamily: .scheduled), .scheduled)
        XCTAssertEqual(ExportSource(triggerSource: .notificationTapRetry, resolvedSourceFamily: .shortcut), .shortcut)
        XCTAssertEqual(ExportSource(triggerSource: .shortcut), .shortcut)
        XCTAssertEqual(ExportSource(triggerSource: .connectedPeer), .macAgent)
        XCTAssertEqual(ExportSource(triggerSource: .connectedPeer).rawValue, "iPhone → Mac")
    }

    private static var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        return calendar
    }

    private func date(_ year: Int, _ month: Int, _ day: Int, hour: Int = 0) -> Date {
        Self.calendar.date(from: DateComponents(
            timeZone: Self.calendar.timeZone,
            year: year,
            month: month,
            day: day,
            hour: hour
        ))!
    }
}
