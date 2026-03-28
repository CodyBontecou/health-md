//
//  SleepCalculationTests.swift
//  HealthMdTests
//
//  Unit tests for HealthKitManager's sleep-duration calculation logic.
//
//  The key contract being verified: exported "Total" must match Apple Health's
//  "TIME ASLEEP" display, which differs from a naive sum of stage intervals.
//

import XCTest
@testable import HealthMd

final class SleepCalculationTests: XCTestCase {

    // MARK: - Helpers

    private func date(_ h: Double, base: Date = .distantPast) -> Date {
        base.addingTimeInterval(h * 3600)
    }

    private typealias Interval = (start: Date, end: Date)

    // MARK: - mergeIntervals

    func testMergeIntervals_emptyInput() {
        let result = HealthKitManager.mergeIntervals([])
        XCTAssertTrue(result.isEmpty)
    }

    func testMergeIntervals_singleInterval() {
        let intervals: [Interval] = [(date(0), date(1))]
        let result = HealthKitManager.mergeIntervals(intervals)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].start, date(0))
        XCTAssertEqual(result[0].end, date(1))
    }

    func testMergeIntervals_nonOverlapping() {
        let intervals: [Interval] = [(date(0), date(1)), (date(2), date(3))]
        let result = HealthKitManager.mergeIntervals(intervals)
        XCTAssertEqual(result.count, 2)
    }

    func testMergeIntervals_overlapping() {
        let intervals: [Interval] = [(date(0), date(2)), (date(1), date(3))]
        let result = HealthKitManager.mergeIntervals(intervals)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].end, date(3))
    }

    func testMergeIntervals_adjacent() {
        // End of first == start of second → should merge
        let intervals: [Interval] = [(date(0), date(1)), (date(1), date(2))]
        let result = HealthKitManager.mergeIntervals(intervals)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].end, date(2))
    }

    func testMergeIntervals_largeEncompassesSmall() {
        let intervals: [Interval] = [(date(0), date(10)), (date(2), date(4)), (date(5), date(7))]
        let result = HealthKitManager.mergeIntervals(intervals)
        XCTAssertEqual(result.count, 1)
        XCTAssertEqual(result[0].start, date(0))
        XCTAssertEqual(result[0].end, date(10))
    }

    // MARK: - totalDuration

    func testTotalDuration_empty() {
        XCTAssertEqual(HealthKitManager.totalDuration(of: []), 0)
    }

    func testTotalDuration_singleInterval() {
        let intervals: [Interval] = [(date(0), date(2))]
        XCTAssertEqual(HealthKitManager.totalDuration(of: intervals), 2 * 3600, accuracy: 1)
    }

    func testTotalDuration_overlappingIntervals_deduplicates() {
        // Two overlapping 1-hour intervals should give 1.5 h, not 2 h
        let intervals: [Interval] = [(date(0), date(1)), (date(0.5), date(1.5))]
        XCTAssertEqual(HealthKitManager.totalDuration(of: intervals), 1.5 * 3600, accuracy: 1)
    }

    // MARK: - computeTotalSleepDuration — Apple Watch pattern (InBed present)

    /// Reproduces the exact bug reported:
    /// Apple Watch records Core(4h40m) + Deep(28m) + REM(2h6m) + Awake(19m) = 7h33m of
    /// stage samples, but the InBed session spans 9h17m.
    /// Expected total = InBed(9h17m) − Awake(19m) = 8h58m  (matches Apple Health).
    func testAppleWatchPattern_totalMatchesAppleHealth() {
        let sessionStart = date(0)   // 10:30 pm (relative)
        let sessionEnd   = date(9.283) // 7:28 am  (+9h17m ≈ 9.283h)

        // InBed = one interval for the whole session
        let inBed: [Interval] = [(sessionStart, sessionEnd)]

        // Awake = 19 min within the session
        let awake: [Interval] = [(date(4), date(4 + 19.0/60))]

        // Stage samples (Core + Deep + REM together = 7h14m, not covering full InBed window)
        let core: [Interval] = [
            (date(0.5), date(1.5)),   // 1 h
            (date(2.5), date(5.5)),   // 3 h
        ]  // ≈ 4h total core (simplified)
        let deep: [Interval] = [(date(1.5), date(2)),]    // 30 min
        let rem:  [Interval] = [(date(5.5), date(7.5)),]  // 2 h

        let total = HealthKitManager.computeTotalSleepDuration(
            deepIntervals: deep,
            remIntervals: rem,
            coreIntervals: core,
            unspecifiedIntervals: [],
            awakeIntervals: awake,
            inBedIntervals: inBed
        )

        // Expected: inBed(9h17m) - awake(19m) = 8h58m
        let expected = (9.0 * 3600 + 17.0 * 60) - 19.0 * 60
        XCTAssertEqual(total, expected, accuracy: 60) // within 1 minute
    }

    /// When InBed is present, the result must be ≥ the union of stage intervals alone.
    func testAppleWatchPattern_totalExceedsStageUnion() {
        let inBed: [Interval] = [(date(0), date(9))]          // 9-hour session
        let awake: [Interval] = [(date(4), date(4.25))]       // 15 min awake

        // Stages cover only 7 hours within the session (2-hour unlabelled gap)
        let core: [Interval] = [(date(1), date(5))]           // 4 h
        let rem:  [Interval] = [(date(5), date(7))]           // 2 h
        let deep: [Interval] = [(date(7), date(8))]           // 1 h

        let total = HealthKitManager.computeTotalSleepDuration(
            deepIntervals: deep,
            remIntervals: rem,
            coreIntervals: core,
            unspecifiedIntervals: [],
            awakeIntervals: awake,
            inBedIntervals: inBed
        )

        let stageUnion = HealthKitManager.totalDuration(of: core + rem + deep)
        XCTAssertGreaterThan(total, stageUnion,
            "InBed-based total should exceed the raw stage union when there are unlabelled gaps")

        // Expected: 9h − 15min = 8h45m
        XCTAssertEqual(total, (9 - 0.25) * 3600, accuracy: 1)
    }

    // MARK: - computeTotalSleepDuration — no InBed (fallback to asleep union)

    func testNoInBed_usesAsleepUnion() {
        let core: [Interval] = [(date(0), date(4))]    // 4 h
        let rem:  [Interval] = [(date(4), date(6))]    // 2 h
        let deep: [Interval] = [(date(2), date(2.5))]  // 30 min (overlaps core)

        let total = HealthKitManager.computeTotalSleepDuration(
            deepIntervals: deep,
            remIntervals: rem,
            coreIntervals: core,
            unspecifiedIntervals: [],
            awakeIntervals: [],
            inBedIntervals: []
        )

        // Union: 0→6 = 6 h
        XCTAssertEqual(total, 6 * 3600, accuracy: 1)
    }

    func testNoInBed_unspecifiedIntervalsAreIncluded() {
        let unspecified: [Interval] = [(date(0), date(8))]  // 8 h

        let total = HealthKitManager.computeTotalSleepDuration(
            deepIntervals: [],
            remIntervals: [],
            coreIntervals: [],
            unspecifiedIntervals: unspecified,
            awakeIntervals: [],
            inBedIntervals: []
        )

        XCTAssertEqual(total, 8 * 3600, accuracy: 1)
    }

    /// Non-overlapping unspecified intervals (e.g. from iPhone Sleep) should
    /// extend the total even when stage data from Apple Watch is also present —
    /// as long as no InBed interval is provided.
    func testNoInBed_nonOverlappingUnspecifiedAddsToStages() {
        let core: [Interval] = [(date(1), date(5))]               // 4 h (stages from Watch)
        let unspecified: [Interval] = [(date(7), date(8))]        // 1 h gap (separate source)

        let total = HealthKitManager.computeTotalSleepDuration(
            deepIntervals: [],
            remIntervals: [],
            coreIntervals: core,
            unspecifiedIntervals: unspecified,
            awakeIntervals: [],
            inBedIntervals: []
        )

        // Union = 4h (core) + 1h (unspecified, non-overlapping) = 5 h
        XCTAssertEqual(total, 5 * 3600, accuracy: 1)
    }

    // MARK: - Edge cases

    func testAwakeExceedsInBed_clampedToZero() {
        // Defensive: awake > inBed should never happen in practice but mustn't crash
        let inBed: [Interval] = [(date(0), date(1))]   // 1 h
        let awake: [Interval] = [(date(0), date(2))]   // 2 h (wrong data)

        let total = HealthKitManager.computeTotalSleepDuration(
            deepIntervals: [],
            remIntervals: [],
            coreIntervals: [],
            unspecifiedIntervals: [],
            awakeIntervals: awake,
            inBedIntervals: inBed
        )

        XCTAssertEqual(total, 0)
    }
}
