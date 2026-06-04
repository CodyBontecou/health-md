//
//  ScheduleDateMathTests.swift
//  HealthMdTests
//
//  Tests for Health.md schedule compatibility and generic automation date math.
//

import XCTest
@testable import HealthMd

final class ScheduleDateMathTests: XCTestCase {

    private static let cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()

    private func date(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
        Self.cal.date(from: DateComponents(timeZone: Self.cal.timeZone, year: year, month: month, day: day, hour: hour, minute: minute))!
    }

    // MARK: - schedule bridge

    func testExportScheduleBridgesToAutomationScheduleAndBack() {
        let lastExport = date(2026, 3, 14, 8, 30)
        let timeZone = TimeZone(identifier: "Europe/Berlin")!
        let schedule = ExportSchedule(
            isEnabled: true,
            frequency: .weekly,
            preferredHour: 22,
            preferredMinute: 15,
            weekday: 3,
            lookbackDays: 14,
            lastExportDate: lastExport
        )

        let automation = schedule.automationSchedule(timeZone: timeZone)
        let roundTrip = ExportSchedule(automationSchedule: automation)

        XCTAssertEqual(automation.isEnabled, true)
        XCTAssertEqual(automation.frequency, .weekly)
        XCTAssertEqual(automation.preferredHour, 22)
        XCTAssertEqual(automation.preferredMinute, 15)
        XCTAssertEqual(automation.weekday, 3)
        XCTAssertEqual(automation.lookbackDays, 14)
        XCTAssertEqual(automation.timeZoneIdentifier, "Europe/Berlin")
        XCTAssertEqual(automation.lastExportDate, lastExport)
        XCTAssertEqual(roundTrip.frequency, schedule.frequency)
        XCTAssertEqual(roundTrip.lookbackDays, schedule.lookbackDays)
        XCTAssertEqual(roundTrip.lastExportDate, schedule.lastExportDate)
    }

    func testAutomationScheduleClampsLookbackAndUsesFrequencyDefaults() {
        let daily = AutomationSchedule(frequency: .daily)
        let weekly = AutomationSchedule(frequency: .weekly)
        let low = AutomationSchedule(lookbackDays: -4)
        let high = AutomationSchedule(lookbackDays: 999)

        XCTAssertEqual(daily.lookbackDays, 1)
        XCTAssertEqual(weekly.lookbackDays, 7)
        XCTAssertEqual(low.lookbackDays, AutomationSchedule.minimumLookbackDays)
        XCTAssertEqual(high.lookbackDays, AutomationSchedule.maximumLookbackDays)
    }

    func testPersistedAutomationConfigurationStoresExportRequestSnapshot() throws {
        let suiteName = "PersistedAutomationConfigurationTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsAutomationConfigurationStore(userDefaults: defaults)
        let snapshot = AutomationExportRequestConfigurationSnapshot(
            schemaVersion: 2,
            requestKind: "export-kit-request",
            formatIDs: ["markdown", "json"],
            destinationID: "local-phone-folder",
            encodedConfiguration: Data([1, 2, 3, 4]),
            metadata: ["profile": "scheduled"]
        )
        let configuration = PersistedAutomationConfiguration(
            schedule: AutomationSchedule(
                isEnabled: true,
                frequency: .weekly,
                preferredHour: 7,
                preferredMinute: 45,
                lookbackDays: 9,
                timeZoneIdentifier: "UTC"
            ),
            exportRequestConfiguration: snapshot
        )

        try store.save(configuration)

        let loaded = try XCTUnwrap(try store.load())
        XCTAssertEqual(loaded, configuration)
        store.clear()
        XCTAssertNil(try store.load())
    }

    func testGenericAutomationSourcesDoNotReferenceAppSpecificDomains() throws {
        let projectRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURLs = [
            projectRoot.appendingPathComponent("HealthMd/Shared/ExportAutomationKit/ExportAutomationScheduling.swift"),
            projectRoot.appendingPathComponent("HealthMd/Shared/ExportAutomationKit/AutomationPendingExports.swift")
        ]
        let forbiddenTerms = [
            "Health.md",
            "HealthKit",
            "HealthData",
            "MetricSelectionState",
            "HealthMetricsDictionary",
            "HealthMetric",
            "vaultPath",
            "filenameTemplate",
            "selectedMetrics",
            "metricValue"
        ]

        for sourceURL in sourceURLs {
            let source = try String(contentsOf: sourceURL, encoding: .utf8)
            for term in forbiddenTerms {
                XCTAssertFalse(source.contains(term), "Generic automation source \(sourceURL.lastPathComponent) should not reference \(term)")
            }
        }
    }

    // MARK: - remote schedule contract

    func testRemoteDeviceRegistrationPayloadIsRoutingOnlyAndSupportsAppMetadata() throws {
        let payload = RemoteScheduleDeviceRegistrationPayload(
            userId: "install-123",
            platform: "ios",
            apnsToken: "abcdef0123456789",
            bundleId: "com.example.exporter",
            appVersion: "1.2.3",
            appBuild: "456"
        )

        let json = try encodedJSONObject(payload)
        XCTAssertEqual(Set(json.keys), ["userId", "platform", "apnsToken", "bundleId", "appVersion", "appBuild"])
        XCTAssertEqual(json["userId"] as? String, "install-123")
        XCTAssertEqual(json["platform"] as? String, "ios")
        XCTAssertEqual(json["apnsToken"] as? String, "abcdef0123456789")
        XCTAssertEqual(json["bundleId"] as? String, "com.example.exporter")
        XCTAssertEqual(json["appVersion"] as? String, "1.2.3")
        XCTAssertEqual(json["appBuild"] as? String, "456")
        try assertRemoteSchedulePayloadIsRoutingOnly(payload)
    }

    func testRemoteDeviceRegistrationPayloadOmitsOptionalMetadataForLegacyWorkerCompatibility() throws {
        let payload = RemoteScheduleDeviceRegistrationPayload(
            userId: "install-123",
            platform: "ios",
            apnsToken: "abcdef0123456789",
            bundleId: "com.example.exporter"
        )

        let json = try encodedJSONObject(payload)

        XCTAssertEqual(Set(json.keys), ["userId", "platform", "apnsToken", "bundleId"])
        XCTAssertNil(json["appVersion"])
        XCTAssertNil(json["appBuild"])
        try assertRemoteSchedulePayloadIsRoutingOnly(payload)
    }

    func testRemoteScheduleUpdatePayloadMirrorsWorkerFieldsOnly() throws {
        let schedule = AutomationSchedule(
            isEnabled: true,
            frequency: .weekly,
            preferredHour: 22,
            preferredMinute: 15,
            weekday: 4,
            lookbackDays: 14,
            timeZoneIdentifier: "America/New_York"
        )
        let payload = RemoteScheduleUpsertPayload(
            userId: "install-123",
            timezone: "America/New_York",
            schedule: RemoteSchedulePayload(schedule: schedule)
        )

        let json = try encodedJSONObject(payload)
        let scheduleJSON = try XCTUnwrap(json["schedule"] as? [String: Any])

        XCTAssertEqual(Set(json.keys), ["userId", "timezone", "schedule"])
        XCTAssertEqual(json["userId"] as? String, "install-123")
        XCTAssertEqual(json["timezone"] as? String, "America/New_York")
        XCTAssertEqual(Set(scheduleJSON.keys), ["isEnabled", "frequency", "hour", "minute", "weekday"])
        XCTAssertEqual(scheduleJSON["isEnabled"] as? Bool, true)
        XCTAssertEqual(scheduleJSON["frequency"] as? String, "weekly")
        XCTAssertEqual(scheduleJSON["hour"] as? Int, 22)
        XCTAssertEqual(scheduleJSON["minute"] as? Int, 15)
        XCTAssertEqual(scheduleJSON["weekday"] as? Int, 4)
        XCTAssertNil(json["lookbackDays"], "Remote worker schedule sync must not include local export window details.")
        try assertRemoteSchedulePayloadIsRoutingOnly(payload)
    }

    func testRemoteScheduleUnregisterPayloadUsesDisabledDailyScheduleWithoutWeekday() throws {
        let schedule = AutomationSchedule(
            isEnabled: false,
            frequency: .daily,
            preferredHour: 6,
            preferredMinute: 30,
            weekday: 5,
            timeZoneIdentifier: "UTC"
        )
        let payload = RemoteScheduleUpsertPayload(
            userId: "install-123",
            timezone: "UTC",
            schedule: RemoteSchedulePayload(schedule: schedule)
        )

        let json = try encodedJSONObject(payload)
        let scheduleJSON = try XCTUnwrap(json["schedule"] as? [String: Any])

        XCTAssertEqual(scheduleJSON["isEnabled"] as? Bool, false)
        XCTAssertEqual(scheduleJSON["frequency"] as? String, "daily")
        XCTAssertEqual(scheduleJSON["hour"] as? Int, 6)
        XCTAssertEqual(scheduleJSON["minute"] as? Int, 30)
        XCTAssertFalse(scheduleJSON.keys.contains("weekday"), "Daily unregister/update payloads should omit weekly-only weekday metadata.")
        try assertRemoteSchedulePayloadIsRoutingOnly(payload)
    }

    func testRemoteScheduledExportAPNsPayloadIsSilentAndRoutingOnly() throws {
        let payload = RemoteScheduledExportAPNsPayload(scheduledFireDate: "2026-06-04T08:00:00Z")

        let json = try encodedJSONObject(payload)
        let aps = try XCTUnwrap(json["aps"] as? [String: Any])

        XCTAssertEqual(Set(json.keys), ["aps", "type", "scheduledFireDate"])
        XCTAssertEqual(Set(aps.keys), ["content-available"])
        XCTAssertEqual(aps["content-available"] as? Int, 1)
        XCTAssertEqual(json["type"] as? String, "scheduled-export")
        XCTAssertEqual(json["scheduledFireDate"] as? String, "2026-06-04T08:00:00Z")
        XCTAssertNil(aps["alert"])
        XCTAssertNil(aps["sound"])
        XCTAssertNil(aps["badge"])
        try assertRemoteSchedulePayloadIsRoutingOnly(payload)
    }

    func testRemoteScheduleRetryPolicyRetriesOnlyTransientFailures() {
        let policy = RemoteScheduleRetryPolicy(maxAttempts: 3)

        XCTAssertTrue(policy.shouldRetry(URLError(.timedOut)))
        XCTAssertTrue(policy.shouldRetry(RemoteScheduleClientError.unsuccessfulStatusCode(429)))
        XCTAssertTrue(policy.shouldRetry(RemoteScheduleClientError.unsuccessfulStatusCode(503)))
        XCTAssertFalse(policy.shouldRetry(RemoteScheduleClientError.unsuccessfulStatusCode(400)))
        XCTAssertFalse(policy.shouldRetry(RemoteScheduleClientError.invalidHTTPResponse))
    }

    // MARK: - background runner

    @MainActor
    func testAutomationBackgroundRunnerPreparesPendingWorkBeforeExportAndReturnsSuccess() async {
        let fireDate = date(2026, 5, 18, 8)
        let schedule = AutomationSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 8,
            lookbackDays: 1,
            timeZoneIdentifier: "UTC"
        )
        let runner = AutomationScheduledBackgroundRunner(calendar: Self.cal)
        var events: [String] = []

        let outcome = await runner.runScheduledExport(
            trigger: .silentPush,
            schedule: schedule,
            requestedFireDate: fireDate,
            now: date(2026, 5, 18, 9),
            preparePendingWork: { context in
                events.append("prepare")
                XCTAssertEqual(context.trigger, .silentPush)
                XCTAssertEqual(context.resolvedFireDate, fireDate)
                return AutomationPreparedScheduledBackgroundWork(
                    request: "pending-1",
                    dates: AutomationScheduleDateMath.scheduledExportDates(
                        schedule: schedule,
                        fireDate: context.resolvedFireDate,
                        calendar: Self.cal
                    ),
                    scheduledFireDate: context.resolvedFireDate
                )
            },
            cancelPendingFallback: { pendingWork in
                events.append("cancel:\(pendingWork?.request ?? "nil")")
            },
            beforeExport: { prepared in
                events.append("before:\(prepared.dates.count)")
            },
            export: { dates, _ in
                events.append("export:\(dates.count)")
                return ("exported", AutomationBackgroundExportResult.success(count: dates.count))
            }
        )

        XCTAssertEqual(events, ["prepare", "cancel:pending-1", "before:1", "export:1"])
        XCTAssertEqual(outcome.pendingWork?.request, "pending-1")
        XCTAssertEqual(outcome.dates, [date(2026, 5, 17)])
        XCTAssertEqual(outcome.dateRange, AutomationBackgroundDateRange(
            start: date(2026, 5, 17),
            end: date(2026, 5, 17),
            totalCount: 1
        ))
        XCTAssertEqual(outcome.exportResult, "exported")
        XCTAssertTrue(outcome.shouldUpdateLastExport)
    }

    @MainActor
    func testAutomationBackgroundRunnerSkipsDisabledSchedulesWithoutPreparingWork() async {
        let schedule = AutomationSchedule(isEnabled: false, timeZoneIdentifier: "UTC")
        let runner = AutomationScheduledBackgroundRunner(calendar: Self.cal)
        var didPrepare = false

        let outcome: AutomationScheduledBackgroundRunOutcome<String, String> = await runner.runScheduledExport(
            trigger: .backgroundTask,
            schedule: schedule,
            now: date(2026, 5, 18, 9),
            preparePendingWork: { _ in
                didPrepare = true
                return nil
            },
            cancelPendingFallback: { _ in
                XCTFail("Disabled schedules should not cancel fallback notifications")
            },
            export: { _, _ in
                XCTFail("Disabled schedules should not export")
                return ("unexpected", AutomationBackgroundExportResult.success(count: 1))
            }
        )

        XCTAssertFalse(didPrepare)
        XCTAssertEqual(outcome.skipReason, .scheduleDisabled)
        XCTAssertNil(outcome.exportResult)
        XCTAssertFalse(outcome.shouldUpdateLastExport)
    }

    func testAutomationBackgroundExportResultCoversBackgroundFailureTaxonomy() {
        let cases: [(AutomationBackgroundExportResult, AutomationBackgroundExportFailureReason?, Bool)] = [
            (.success(count: 2), nil, true),
            (.failure(totalCount: 2, reason: .noDestination), .noDestination, false),
            (.failure(totalCount: 0, reason: .quotaBlocked), .quotaBlocked, false),
            (.failure(totalCount: 2, reason: .protectedDataUnavailable), .protectedDataUnavailable, false),
            (.failure(totalCount: 2, reason: .noData), .noData, false),
            (.failure(totalCount: 2, reason: .cancelled, wasCancelled: true), .cancelled, false),
            (.timedOut(totalCount: 2), .timeLimitExceeded, false)
        ]

        for (result, reason, shouldUpdateLastExport) in cases {
            XCTAssertEqual(result.primaryFailureReason, reason)
            XCTAssertEqual(result.shouldUpdateLastExport, shouldUpdateLastExport)
        }
    }

    func testAutomationPendingCompletionPolicyMapsRetryReasons() {
        let policy = AutomationPendingExportCompletionPolicy()

        XCTAssertEqual(policy.completion(for: .success(count: 1)), .clearedAfterSuccess)
        XCTAssertEqual(
            policy.pendingReason(for: .failure(totalCount: 2, reason: .protectedDataUnavailable)),
            .protectedDataUnavailable
        )
        XCTAssertEqual(
            policy.pendingReason(for: .failure(totalCount: 2, reason: .noDestination)),
            .destinationAccessDenied
        )
        XCTAssertEqual(
            policy.pendingReason(for: .failure(totalCount: 0, reason: .quotaBlocked)),
            .quotaBlocked
        )
        XCTAssertEqual(
            policy.pendingReason(for: .failure(totalCount: 2, reason: .noData)),
            .noData
        )
        XCTAssertNil(policy.pendingReason(for: AutomationBackgroundExportResult(successCount: 0, totalCount: 0)))
    }

    // MARK: - calculateNextRunDate

    func testNextRunDate_daily_beforePreferredTime_returnsToday() {
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 14, preferredMinute: 0)
        let now = date(2026, 3, 15, 10, 0) // 10:00, preferred is 14:00

        let next = ScheduleDateMath.calculateNextRunDate(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertNotNil(next)
        let comps = Self.cal.dateComponents([.year, .month, .day, .hour], from: next!)
        XCTAssertEqual(comps.day, 15, "Should return today since preferred time hasn't passed")
        XCTAssertEqual(comps.hour, 14)
    }

    func testNextRunDate_daily_afterPreferredTime_returnsTomorrow() {
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8, preferredMinute: 0)
        let now = date(2026, 3, 15, 10, 0) // 10:00, preferred is 08:00

        let next = ScheduleDateMath.calculateNextRunDate(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertNotNil(next)
        let comps = Self.cal.dateComponents([.day], from: next!)
        XCTAssertEqual(comps.day, 16, "Should return tomorrow since preferred time has passed")
    }

    func testNextRunDate_weekly_afterPreferredTime_returnsNextWeek() {
        let schedule = ExportSchedule(isEnabled: true, frequency: .weekly, preferredHour: 8, preferredMinute: 0, weekday: 1)
        let now = date(2026, 3, 15, 10, 0) // 10:00 Sunday

        let next = ScheduleDateMath.calculateNextRunDate(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertNotNil(next)
        let comps = Self.cal.dateComponents([.day], from: next!)
        XCTAssertEqual(comps.day, 22, "Should return 7 days later for weekly, preserving current weekday-agnostic behavior")
    }

    func testNextRunDate_usesScheduleTimezoneWhenCalendarOmitted() throws {
        let schedule = AutomationSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 23,
            preferredMinute: 45,
            timeZoneIdentifier: "Pacific/Honolulu"
        )
        let now = date(2026, 3, 15, 9, 30) // Mar 14 23:30 in Honolulu

        let next = try XCTUnwrap(AutomationScheduleDateMath.calculateNextRunDate(schedule: schedule, now: now))

        XCTAssertEqual(next, date(2026, 3, 15, 9, 45)) // Mar 14 23:45 in Honolulu
    }

    // MARK: - catchUpDatesNeeded

    func testCatchUpDates_daily_noLastExport_returnsYesterday() {
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8)
        let now = date(2026, 3, 15, 10, 0)

        let dates = ScheduleDateMath.catchUpDatesNeeded(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertEqual(dates, [date(2026, 3, 14)])
    }

    func testCatchUpDates_daily_lastExportToday_returnsEmpty() {
        let todayExportRun = date(2026, 3, 15, 9, 0)
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8, lastExportDate: todayExportRun)
        let now = date(2026, 3, 15, 10, 0)

        let dates = ScheduleDateMath.catchUpDatesNeeded(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertTrue(dates.isEmpty, "Today's export already covered yesterday's data")
    }

    func testCatchUpDates_daily_lastExportYesterdayStillExportsYesterday() {
        let yesterdayExportRun = date(2026, 3, 14, 9, 0)
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8, lastExportDate: yesterdayExportRun)
        let now = date(2026, 3, 15, 10, 0)

        let dates = ScheduleDateMath.catchUpDatesNeeded(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertEqual(dates, [date(2026, 3, 14)], "An export that ran yesterday covered the day before, so yesterday remains due")
    }

    func testCatchUpDates_daily_missedDays_clippedToYesterday() {
        let threeDaysAgo = date(2026, 3, 11, 9, 0)
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8, lastExportDate: threeDaysAgo)
        let now = date(2026, 3, 15, 10, 0)

        let dates = ScheduleDateMath.catchUpDatesNeeded(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertEqual(dates, [date(2026, 3, 14)], "Daily default lookback clips catch-up to yesterday only")
    }

    func testCatchUpDates_dailyCustomLookback_returnsConfiguredWindow() {
        let schedule = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8, lookbackDays: 3)
        let now = date(2026, 3, 15, 10, 0)

        let dates = ScheduleDateMath.catchUpDatesNeeded(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertEqual(dates, [
            date(2026, 3, 12),
            date(2026, 3, 13),
            date(2026, 3, 14)
        ])
    }

    func testCatchUpDates_weekly_lastExportBehaviorReturnsRunDayThroughYesterday() {
        let fiveDaysAgoExportRun = date(2026, 3, 10, 9, 0)
        let schedule = ExportSchedule(isEnabled: true, frequency: .weekly, preferredHour: 8, lastExportDate: fiveDaysAgoExportRun)
        let now = date(2026, 3, 15, 10, 0)

        let dates = ScheduleDateMath.catchUpDatesNeeded(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertEqual(dates, [
            date(2026, 3, 10),
            date(2026, 3, 11),
            date(2026, 3, 12),
            date(2026, 3, 13),
            date(2026, 3, 14)
        ])
    }

    func testCatchUpDates_weekly_boundedBySeven() {
        let schedule = ExportSchedule(isEnabled: true, frequency: .weekly, preferredHour: 8)
        let now = date(2026, 3, 15, 10, 0)

        let dates = ScheduleDateMath.catchUpDatesNeeded(schedule: schedule, now: now, calendar: Self.cal)

        XCTAssertEqual(dates.count, 7, "Weekly default lookback should not go back more than 7 days")
        XCTAssertEqual(dates.first, date(2026, 3, 8))
        XCTAssertEqual(dates.last, date(2026, 3, 14))
    }

    // MARK: - scheduled windows and occurrence keys

    func testScheduledExportDates_clampsLookbackToThirtyAndEndsYesterday() {
        let schedule = ExportSchedule(isEnabled: true, frequency: .weekly, preferredHour: 8, lookbackDays: 999)
        let fireDate = date(2026, 5, 18, 8)

        let dates = ScheduleDateMath.scheduledExportDates(schedule: schedule, fireDate: fireDate, calendar: Self.cal)

        XCTAssertEqual(dates.count, 30)
        XCTAssertEqual(dates.first, date(2026, 4, 18))
        XCTAssertEqual(dates.last, date(2026, 5, 17))
    }

    func testPendingExportDateWindowMatchesScheduledOccurrenceDates() {
        let schedule = AutomationSchedule(
            isEnabled: true,
            frequency: .weekly,
            preferredHour: 8,
            lookbackDays: 5,
            timeZoneIdentifier: "UTC"
        )
        let fireDate = date(2026, 5, 18, 8)

        let window = AutomationScheduleDateMath.pendingExportDateWindow(
            schedule: schedule,
            fireDate: fireDate,
            calendar: Self.cal
        )

        XCTAssertEqual(window.fireDate, fireDate)
        XCTAssertEqual(window.totalCount, 5)
        XCTAssertEqual(window.startDate, date(2026, 5, 13))
        XCTAssertEqual(window.endDate, date(2026, 5, 17))
        XCTAssertEqual(window.dates, [
            date(2026, 5, 13),
            date(2026, 5, 14),
            date(2026, 5, 15),
            date(2026, 5, 16),
            date(2026, 5, 17)
        ])
    }

    func testScheduledExportDates_useScheduleTimezoneWhenCalendarOmitted() {
        let schedule = AutomationSchedule(
            isEnabled: true,
            frequency: .daily,
            preferredHour: 23,
            preferredMinute: 45,
            lookbackDays: 2,
            timeZoneIdentifier: "Pacific/Honolulu"
        )
        let fireDate = date(2026, 3, 15, 9, 45) // Mar 14 23:45 in Honolulu
        let localCalendar = schedule.defaultCalendar()

        let dates = AutomationScheduleDateMath.scheduledExportDates(schedule: schedule, fireDate: fireDate)

        XCTAssertEqual(dates.count, 2)
        XCTAssertEqual(localCalendar.component(.day, from: dates[0]), 12)
        XCTAssertEqual(localCalendar.component(.day, from: dates[1]), 13)
    }

    func testLatestScheduledOccurrenceDate_beforePreferredTimeReturnsPreviousInterval() {
        let daily = ExportSchedule(isEnabled: true, frequency: .daily, preferredHour: 8, preferredMinute: 0)
        let weekly = ExportSchedule(isEnabled: true, frequency: .weekly, preferredHour: 8, preferredMinute: 0)
        let now = date(2026, 3, 15, 7, 30)

        let latestDaily = ScheduleDateMath.latestScheduledOccurrenceDate(schedule: daily, now: now, calendar: Self.cal)
        let latestWeekly = ScheduleDateMath.latestScheduledOccurrenceDate(schedule: weekly, now: now, calendar: Self.cal)

        XCTAssertEqual(latestDaily, date(2026, 3, 14, 8, 0))
        XCTAssertEqual(latestWeekly, date(2026, 3, 8, 8, 0))
    }

    private func encodedJSONObject<T: Encodable>(_ value: T) throws -> [String: Any] {
        let data = try JSONEncoder().encode(value)
        let object = try JSONSerialization.jsonObject(with: data)
        return try XCTUnwrap(object as? [String: Any])
    }

    private func encodedJSONString<T: Encodable>(_ value: T) throws -> String {
        let data = try JSONEncoder().encode(value)
        return try XCTUnwrap(String(data: data, encoding: .utf8))
    }

    private func assertRemoteSchedulePayloadIsRoutingOnly<T: Encodable>(_ value: T) throws {
        let encoded = try encodedJSONString(value)
        let forbiddenTerms = [
            "HealthData",
            "HealthKit",
            "healthData",
            "exportedFileContents",
            "exportedContent",
            "vaultPath",
            "vaultURL",
            "filenameTemplate",
            "selectedMetrics",
            "metricNames",
            "metricValues",
            "MetricSelectionState",
            "HealthMetricsDictionary"
        ]

        for term in forbiddenTerms {
            XCTAssertFalse(encoded.contains(term), "Remote schedule payload must not include \(term): \(encoded)")
        }
    }
}
