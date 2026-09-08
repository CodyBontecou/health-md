#if os(iOS)
import XCTest
@testable import HealthMd

@MainActor
final class HealthInsightsModelTests: XCTestCase {
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/New_York")!
        return calendar
    }
    private var now: Date { calendar.date(from: DateComponents(year: 2026, month: 3, day: 9, hour: 12))! }

    func testFeedReadsSevenCalendarDaysWithOnlyItsMetricsAcrossDST() async {
        var queried: [Date] = []
        let model = HealthInsightsModel { date, selection, timeZone in
            queried.append(date)
            XCTAssertEqual(selection.enabledMetrics, ["steps", "active_energy", "exercise_time", "sleep_total",
                                                      "sleep_core", "sleep_rem", "sleep_deep",
                                                      "resting_heart_rate", "hrv", "respiratory_rate"])
            XCTAssertEqual(timeZone, self.calendar.timeZone)
            var data = HealthData(date: date)
            data.activity.steps = 0
            return data
        }
        await model.load(authorized: true, now: now, calendar: calendar)
        XCTAssertEqual(queried.count, 7)
        XCTAssertEqual(queried.map { calendar.component(.day, from: $0) }, [3, 4, 5, 6, 7, 8, 9])
        XCTAssertEqual(model.days.last?.values[.steps], 0, "A recorded zero stays a zero")
        XCTAssertNil(model.days.last?.values[.sleep], "No sleep record must not become zero hours")
        XCTAssertNil(model.days.last?.values[.restingHeartRate])
        await model.load(authorized: true, now: now, calendar: calendar)
        XCTAssertEqual(queried.count, 7, "Returning to Home should reuse its short-lived in-memory result")
        await model.load(authorized: true, force: true, now: now, calendar: calendar)
        XCTAssertEqual(queried.count, 14, "Pull to refresh must bypass the cache")
    }

    func testReadFailureLeavesAnExplicitGapAndOtherDaysRemainVisible() async {
        let model = HealthInsightsModel { date, _, _ in
            if self.calendar.component(.day, from: date) == 5 { throw CocoaError(.fileReadNoPermission) }
            var data = HealthData(date: date)
            data.heart.restingHeartRate = 58
            data.sleep.totalDuration = 23_400
            return data
        }
        await model.load(authorized: true, now: now, calendar: calendar)
        XCTAssertEqual(model.days.count, 7)
        XCTAssertEqual(model.failedDayCount, 1)
        XCTAssertTrue(model.days[2].values.isEmpty)
        XCTAssertEqual(model.days[0].values[.sleep], 6.5)
        XCTAssertEqual(model.days[0].values[.restingHeartRate], 58)
        XCTAssertFalse(model.isLoading)
    }

    func testUnconfiguredHealthDoesNotQueryAndClearsPreviousResults() async {
        var reads = 0
        let model = HealthInsightsModel { date, _, _ in reads += 1; return HealthData(date: date) }
        await model.load(authorized: false, now: now, calendar: calendar)
        XCTAssertEqual(reads, 0)
        await model.load(authorized: true, now: now, calendar: calendar)
        XCTAssertEqual(model.days.count, 7)
        await model.load(authorized: false, now: now, calendar: calendar)
        XCTAssertTrue(model.days.isEmpty)
    }

    func testExportChartCountsRunsByLocalDayWithoutInventingFileCounts() {
        let today = calendar.startOfDay(for: now)
        func run(_ offset: Int, success: Bool) -> ExportHistoryEntry {
            let date = calendar.date(byAdding: .day, value: offset, to: today)!
            return ExportHistoryEntry(timestamp: date, source: .manual, success: success,
                dateRangeStart: date, dateRangeEnd: date, successCount: success ? 1 : 0, totalCount: 1,
                fileCount: nil)
        }
        let days = ExportActivityDay.recent([run(-7, success: true), run(-1, success: false),
                                            run(0, success: true), run(0, success: true)], now: now, calendar: calendar)
        XCTAssertEqual(days.count, 7)
        XCTAssertEqual(days.reduce(0) { $0 + $1.completed }, 2)
        XCTAssertEqual(days.reduce(0) { $0 + $1.needsAttention }, 1)
        XCTAssertEqual(days.last?.completed, 2)
        XCTAssertEqual(days[5].needsAttention, 1)
        XCTAssertEqual(days.first?.completed, 0)
    }

    func testAdditionalMetricsKeepDailyStatisticsAndUnits() async {
        let model = HealthInsightsModel { date, _, _ in
            var data = HealthData(date: date)
            data.activity.activeCalories = 520
            data.activity.exerciseMinutes = 45
            data.heart.hrv = 56
            data.vitals.respiratoryRateAvg = 14.4
            data.sleep = SleepData(totalDuration: 23_400, deepSleep: 4_320, remSleep: 5_760, coreSleep: 13_320)
            return data
        }
        await model.load(authorized: true, now: now, calendar: calendar)
        let day = model.days.last!
        XCTAssertEqual(day.values[.activeEnergy], 520)
        XCTAssertEqual(day.values[.exercise], 45)
        XCTAssertEqual(day.values[.hrv], 56)
        XCTAssertEqual(day.values[.respiratoryRate], 14.4)
        XCTAssertEqual(day.sleepComposition?.portions.count, 3)
        XCTAssertEqual(day.sleepComposition?.total, 23_400)
    }

    func testSleepCompositionPreservesUnspecifiedTimeAndRejectsOverlappingTotals() {
        let partial = SleepComposition(sleep: SleepData(totalDuration: 3_600, deepSleep: 600, remSleep: 900))!
        XCTAssertEqual(partial.portions.first { $0.stage == .unspecified }?.seconds, 2_100)
        XCTAssertEqual(partial.portions.reduce(0) { $0 + $1.seconds }, partial.total)
        XCTAssertNil(SleepComposition(sleep: SleepData()), "Missing sleep does not become zero sleep")
        XCTAssertNil(SleepComposition(sleep: SleepData(totalDuration: 3_600, deepSleep: 3_000, remSleep: 2_000)),
                     "Overlapping source stage totals must not be normalized into a made-up composition")
        XCTAssertNil(SleepComposition(sleep: SleepData(totalDuration: .infinity)))
        XCTAssertNil(SleepComposition(sleep: SleepData(totalDuration: 3_600, deepSleep: .nan)))
        let unstaged = SleepComposition(sleep: SleepData(totalDuration: 3_600))!
        XCTAssertFalse(unstaged.hasStages)
        XCTAssertEqual(unstaged.portions.first?.stage, .unspecified)
    }

    func testChartAverageExcludesMissingReadingsAndPreservesRecordedZero() {
        let dates = (0..<3).map { calendar.date(byAdding: .day, value: $0, to: now)! }
        let days = [HealthInsightDay(date: dates[0], values: [.exercise: 0]),
                    HealthInsightDay(date: dates[1], values: [:]),
                    HealthInsightDay(date: dates[2], values: [.exercise: 60])]
        let stats = InsightStatistics(days: days, metric: .exercise)
        XCTAssertEqual(stats.average, 30)
        XCTAssertEqual(stats.values.count, 2)
        XCTAssertEqual(stats.range, 0...60)
        XCTAssertNil(InsightStatistics(days: days, metric: .hrv).average)
        var invalid = HealthData(date: now)
        invalid.vitals.respiratoryRateAvg = .nan
        invalid.heart.hrv = -1
        XCTAssertNil(HealthInsightMetric.respiratoryRate.value(in: invalid))
        XCTAssertNil(HealthInsightMetric.hrv.value(in: invalid))
    }
    func testDateRangesStayBoundedAndShiftByCalendarDaysAcrossDST() {
        let range = InsightDateRange(ending: now, days: 7, now: now, calendar: calendar)
        let previous = range.shifted(by: -1, now: now)
        XCTAssertEqual(previous.end, calendar.date(byAdding: .day, value: -1, to: range.start))
        XCTAssertEqual(previous.shifted(by: 1, now: now), range)
        XCTAssertEqual(range.shifted(by: 1, now: now), range, "Navigation must not enter future days")
        XCTAssertTrue(zip(range.dates, range.dates.dropFirst()).contains { $1.timeIntervalSince($0) == 23 * 3_600 })
        let future = calendar.date(byAdding: .year, value: 1, to: now)!
        let bounded = InsightDateRange(ending: future, days: 10_000, now: now, calendar: calendar)
        XCTAssertEqual(bounded.dayCount, 90)
        XCTAssertEqual(bounded.end, calendar.startOfDay(for: now))
        XCTAssertEqual(Set(bounded.dates.map(insightDayKey)).count, 90, "Repeated weekdays remain separate chart columns")
        let single = InsightDateRange(ending: now, days: 0, now: now, calendar: calendar)
        XCTAssertEqual(single.dates, [calendar.startOfDay(for: now)])
    }

    func testSelectionFollowsTodayUntilAnExplicitHistoricalRangeIsChosen() {
        var selection = InsightDateSelection()
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: now)!
        XCTAssertNotEqual(selection.range(now: now, calendar: calendar), selection.range(now: tomorrow, calendar: calendar))
        let custom = InsightDateRange(ending: now, days: 12, now: now, calendar: calendar)
        selection.apply(custom)
        XCTAssertEqual(selection.range(now: tomorrow, calendar: calendar), custom)
        var west = calendar
        west.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        selection.rebase(from: calendar, to: west)
        XCTAssertEqual(west.component(.day, from: selection.end!), calendar.component(.day, from: custom.end),
                       "Changing time zones must not move an explicitly selected calendar date")
        selection.end = nil
        XCTAssertEqual(selection.range(now: tomorrow, calendar: calendar).dayCount, 12)
        XCTAssertEqual(selection.range(now: tomorrow, calendar: calendar).end, calendar.startOfDay(for: tomorrow))
    }

    func testCacheUsesTheSelectedRangeAndCalendarTimeZone() async {
        var queried: [Date] = []
        let model = HealthInsightsModel { date, _, _ in queried.append(date); return HealthData(date: date) }
        let month = InsightDateRange(ending: now, days: 30, now: now, calendar: calendar)
        await model.load(authorized: true, range: month, now: now)
        XCTAssertEqual(queried, month.dates)
        await model.load(authorized: true, range: month, now: now)
        XCTAssertEqual(queried.count, 30)
        let earlier = month.shifted(by: -1, now: now)
        await model.load(authorized: true, range: earlier, now: now)
        XCTAssertEqual(model.days.map(\.date), earlier.dates)
        XCTAssertEqual(queried.count, 60, "A cached month must not stand in for another month")
        var west = calendar
        west.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        let otherZone = InsightDateRange(ending: earlier.end, days: 30, now: now, calendar: west)
        await model.load(authorized: true, range: otherZone, now: now)
        XCTAssertEqual(queried.count, 90)
        XCTAssertEqual(model.loadedRange, otherZone)
        await model.load(authorized: true, range: otherZone, force: true, now: now)
        XCTAssertEqual(queried.count, 120)
    }

    func testSupersededReadCannotOverwriteTheNewRange() async {
        let started = expectation(description: "First day is suspended")
        var continuation: CheckedContinuation<HealthData, Never>?
        var suspendNext = true
        let model = HealthInsightsModel { date, _, _ in
            if suspendNext {
                suspendNext = false
                return await withCheckedContinuation {
                    continuation = $0
                    started.fulfill()
                }
            }
            return HealthData(date: date)
        }
        let old = InsightDateRange(ending: now, days: 30, now: now, calendar: calendar)
        let new = old.shifted(by: -1, now: now)
        let task = Task { await model.load(authorized: true, range: old, now: now) }
        await fulfillment(of: [started], timeout: 5)
        XCTAssertTrue(model.days.isEmpty)
        XCTAssertNil(model.loadedRange, "Old values cannot appear under a new date label")
        await model.load(authorized: true, range: new, now: now)
        continuation?.resume(returning: HealthData(date: old.start))
        await task.value
        XCTAssertEqual(model.loadedRange, new)
        XCTAssertEqual(model.days.map(\.date), new.dates)
        XCTAssertFalse(model.isLoading)
    }

    func testHistoricalExportChartUsesTheSameInclusiveDatesAsHealthCharts() {
        let range = InsightDateRange(ending: calendar.date(byAdding: .day, value: -20, to: now)!,
                                     days: 3, now: now, calendar: calendar)
        let after = calendar.date(byAdding: .day, value: 1, to: range.end)!
        let entries = [range.start, range.end, after].map { date in
            ExportHistoryEntry(timestamp: date, source: .manual, success: true,
                               dateRangeStart: now, dateRangeEnd: now, successCount: 1, totalCount: 1, fileCount: nil)
        }
        let days = ExportActivityDay.recent(entries, range: range, now: now)
        XCTAssertEqual(days.map(\.date), range.dates)
        XCTAssertEqual(days.map(\.completed), [1, 0, 1], "Bucket by run time, not the run's exported dates")
    }

}
#endif
