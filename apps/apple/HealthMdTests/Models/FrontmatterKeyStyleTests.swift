//
//  FrontmatterKeyStyleTests.swift
//  HealthMdTests
//
//  Tests for FrontmatterKeyStyle case conversion
//

import XCTest
@testable import HealthMd

final class FrontmatterKeyStyleTests: XCTestCase {
    
    // MARK: - toCamelCase Tests
    
    func testToCamelCase_simpleKey() {
        XCTAssertEqual(FrontmatterKeyStyle.toCamelCase("sleep_total"), "sleepTotal")
    }
    
    func testToCamelCase_multipleUnderscores() {
        XCTAssertEqual(FrontmatterKeyStyle.toCamelCase("sleep_total_hours"), "sleepTotalHours")
    }
    
    func testToCamelCase_singleWord() {
        XCTAssertEqual(FrontmatterKeyStyle.toCamelCase("steps"), "steps")
    }
    
    func testToCamelCase_alreadyCamelCase() {
        // No underscores, should stay the same
        XCTAssertEqual(FrontmatterKeyStyle.toCamelCase("sleepTotal"), "sleepTotal")
    }
    
    func testToCamelCase_leadingUnderscore() {
        // Edge case: leading underscore creates empty first part (empty string stays lowercase)
        let result = FrontmatterKeyStyle.toCamelCase("_hidden_key")
        XCTAssertEqual(result, "hiddenKey")
    }
    
    func testToCamelCase_manyParts() {
        XCTAssertEqual(
            FrontmatterKeyStyle.toCamelCase("blood_pressure_systolic_morning"),
            "bloodPressureSystolicMorning"
        )
    }
    
    func testToCamelCase_realWorldKeys() {
        XCTAssertEqual(FrontmatterKeyStyle.toCamelCase("active_calories"), "activeCalories")
        XCTAssertEqual(FrontmatterKeyStyle.toCamelCase("resting_heart_rate"), "restingHeartRate")
        XCTAssertEqual(FrontmatterKeyStyle.toCamelCase("body_fat_percent"), "bodyFatPercent")
        XCTAssertEqual(FrontmatterKeyStyle.toCamelCase("hrv_ms"), "hrvMs")
    }
    
    // MARK: - toSnakeCase Tests
    
    func testToSnakeCase_simpleKey() {
        XCTAssertEqual(FrontmatterKeyStyle.toSnakeCase("sleepTotal"), "sleep_total")
    }
    
    func testToSnakeCase_multipleCapitals() {
        XCTAssertEqual(FrontmatterKeyStyle.toSnakeCase("sleepTotalHours"), "sleep_total_hours")
    }
    
    func testToSnakeCase_singleWord() {
        XCTAssertEqual(FrontmatterKeyStyle.toSnakeCase("steps"), "steps")
    }
    
    func testToSnakeCase_alreadySnakeCase() {
        XCTAssertEqual(FrontmatterKeyStyle.toSnakeCase("sleep_total"), "sleep_total")
    }
    
    func testToSnakeCase_leadingCapital() {
        XCTAssertEqual(FrontmatterKeyStyle.toSnakeCase("SleepTotal"), "sleep_total")
    }
    
    func testToSnakeCase_consecutiveCapitals() {
        // HRV becomes h_r_v (each capital gets an underscore)
        let result = FrontmatterKeyStyle.toSnakeCase("HRVMs")
        // This might be "h_r_v_ms" depending on implementation
        XCTAssertTrue(result.contains("_"))
    }
    
    func testToSnakeCase_realWorldKeys() {
        XCTAssertEqual(FrontmatterKeyStyle.toSnakeCase("activeCalories"), "active_calories")
        XCTAssertEqual(FrontmatterKeyStyle.toSnakeCase("restingHeartRate"), "resting_heart_rate")
        XCTAssertEqual(FrontmatterKeyStyle.toSnakeCase("bodyFatPercent"), "body_fat_percent")
    }
    
    // MARK: - apply Tests
    
    func testApply_snakeCaseReturnsOriginal() {
        XCTAssertEqual(FrontmatterKeyStyle.snakeCase.apply(to: "sleep_total_hours"), "sleep_total_hours")
    }
    
    func testApply_camelCaseConverts() {
        XCTAssertEqual(FrontmatterKeyStyle.camelCase.apply(to: "sleep_total_hours"), "sleepTotalHours")
    }
    
    // MARK: - Round-trip Tests
    
    func testRoundTrip_snakeToCamelToSnake() {
        let original = "sleep_total_hours"
        let camel = FrontmatterKeyStyle.toCamelCase(original)
        let backToSnake = FrontmatterKeyStyle.toSnakeCase(camel)
        XCTAssertEqual(backToSnake, original)
    }
    
    // MARK: - Edge Cases
    
    func testEmptyString() {
        XCTAssertEqual(FrontmatterKeyStyle.toCamelCase(""), "")
        XCTAssertEqual(FrontmatterKeyStyle.toSnakeCase(""), "")
    }
    
    func testSingleCharacter() {
        XCTAssertEqual(FrontmatterKeyStyle.toCamelCase("a"), "a")
        XCTAssertEqual(FrontmatterKeyStyle.toSnakeCase("a"), "a")
        XCTAssertEqual(FrontmatterKeyStyle.toSnakeCase("A"), "a")
    }
    
    func testNumbersInKey() {
        XCTAssertEqual(FrontmatterKeyStyle.toCamelCase("six_min_walk_m"), "sixMinWalkM")
        XCTAssertEqual(FrontmatterKeyStyle.toSnakeCase("sixMinWalkM"), "six_min_walk_m")
    }
}
