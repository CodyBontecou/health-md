//
//  ExportHelpersTests.swift
//  HealthMdTests
//
//  TDD tests for ExportHelpers formatting utilities on HealthData.
//

import XCTest
@testable import HealthMd

final class ExportHelpersTests: XCTestCase {

    private let data = HealthData(date: Date())

    // MARK: - formatDuration

    func testFormatDuration_hoursAndMinutes() {
        // 2h 30m
        XCTAssertEqual(data.formatDuration(2 * 3600 + 30 * 60), "2h 30m")
    }

    func testFormatDuration_hoursOnly() {
        // Exactly 3 hours
        XCTAssertEqual(data.formatDuration(3 * 3600), "3h 0m")
    }

    func testFormatDuration_minutesOnly() {
        // Under an hour: 45 minutes
        XCTAssertEqual(data.formatDuration(45 * 60), "45m")
    }

    func testFormatDuration_zeroSeconds() {
        XCTAssertEqual(data.formatDuration(0), "0m")
    }

    func testFormatDuration_oneMinute() {
        XCTAssertEqual(data.formatDuration(60), "1m")
    }

    func testFormatDuration_largeValue() {
        // 24 hours
        XCTAssertEqual(data.formatDuration(24 * 3600), "24h 0m")
    }

    func testFormatDuration_truncatesSeconds() {
        // 1h 30m 45s → should still be "1h 30m" (seconds are truncated)
        XCTAssertEqual(data.formatDuration(3600 + 30 * 60 + 45), "1h 30m")
    }

    // MARK: - formatDurationShort

    func testFormatDurationShort_matchesFormatDuration() {
        // formatDurationShort has the same logic as formatDuration
        let intervals: [TimeInterval] = [0, 60, 3600, 7200 + 900, 45 * 60]
        for interval in intervals {
            XCTAssertEqual(
                data.formatDurationShort(interval),
                data.formatDuration(interval),
                "formatDurationShort should match formatDuration for \(interval)"
            )
        }
    }

    // MARK: - formatNumber

    func testFormatNumber_small() {
        XCTAssertEqual(data.formatNumber(42), "42")
    }

    func testFormatNumber_thousands() {
        XCTAssertEqual(data.formatNumber(10_432), "10,432")
    }

    func testFormatNumber_millions() {
        XCTAssertEqual(data.formatNumber(1_000_000), "1,000,000")
    }

    func testFormatNumber_zero() {
        XCTAssertEqual(data.formatNumber(0), "0")
    }

    func testFormatNumber_negative() {
        XCTAssertEqual(data.formatNumber(-1500), "-1,500")
    }

    // MARK: - formatDistance

    func testFormatDistance_kilometers() {
        // 7500 meters → "7.5 km"
        XCTAssertEqual(data.formatDistance(7500), "7.5 km")
    }

    func testFormatDistance_exactKilometer() {
        XCTAssertEqual(data.formatDistance(1000), "1.0 km")
    }

    func testFormatDistance_metersUnderThreshold() {
        // 999 meters → "999 m"
        XCTAssertEqual(data.formatDistance(999), "999 m")
    }

    func testFormatDistance_zeroMeters() {
        XCTAssertEqual(data.formatDistance(0), "0 m")
    }

    func testFormatDistance_largeDistance() {
        // Marathon: ~42195 meters → "42.2 km"
        XCTAssertEqual(data.formatDistance(42195), "42.2 km")
    }

    // MARK: - valenceDescription

    func testValenceDescription_veryUnpleasant() {
        XCTAssertEqual(data.valenceDescription(-1.0), "Very Unpleasant")
        XCTAssertEqual(data.valenceDescription(-0.8), "Very Unpleasant")
    }

    func testValenceDescription_unpleasant() {
        XCTAssertEqual(data.valenceDescription(-0.5), "Unpleasant")
        XCTAssertEqual(data.valenceDescription(-0.3), "Unpleasant")
    }

    func testValenceDescription_neutral() {
        XCTAssertEqual(data.valenceDescription(0.0), "Neutral")
        XCTAssertEqual(data.valenceDescription(-0.1), "Neutral")
        XCTAssertEqual(data.valenceDescription(0.1), "Neutral")
    }

    func testValenceDescription_pleasant() {
        XCTAssertEqual(data.valenceDescription(0.3), "Pleasant")
        XCTAssertEqual(data.valenceDescription(0.5), "Pleasant")
    }

    func testValenceDescription_veryPleasant() {
        XCTAssertEqual(data.valenceDescription(0.7), "Very Pleasant")
        XCTAssertEqual(data.valenceDescription(1.0), "Very Pleasant")
    }

    func testValenceDescription_outOfRange() {
        XCTAssertEqual(data.valenceDescription(-1.5), "Unknown")
        XCTAssertEqual(data.valenceDescription(1.5), "Unknown")
    }

    // MARK: - Boundary Values

    func testValenceDescription_exactBoundaries() {
        // Test exact boundary values between ranges
        XCTAssertEqual(data.valenceDescription(-0.6), "Unpleasant")  // -0.6 is start of Unpleasant
        XCTAssertEqual(data.valenceDescription(-0.2), "Neutral")     // -0.2 is start of Neutral
        XCTAssertEqual(data.valenceDescription(0.2), "Pleasant")     // 0.2 is start of Pleasant
        XCTAssertEqual(data.valenceDescription(0.6), "Very Pleasant") // 0.6 is start of Very Pleasant
    }
}
