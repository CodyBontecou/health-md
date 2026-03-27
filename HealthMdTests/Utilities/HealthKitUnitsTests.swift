//
//  HealthKitUnitsTests.swift
//  HealthMdTests
//
//  Tests for HKUnits — the single source of truth for all HKUnit constants.
//
//  WHY THESE TESTS EXIST
//  ---------------------
//  v1.7.5 shipped with `HKUnit(from: "ml/kg/min")` — an invalid string that
//  throws an NSException at runtime (bypassing Swift's do/catch), crashing every
//  export for users who had VO₂ Max data in HealthKit.
//
//  The bug was latent: because the VO₂ Max query previously returned no data,
//  HKUnit(from:) was never called, so CI and local testing never triggered it.
//
//  These tests ensure:
//  1. Every HKUnit we construct is *valid* — verified via `unitString`, which
//     HealthKit only populates for units it accepts.
//  2. The canonical string form is exactly what we expect, preventing silent
//     regressions (e.g. "ml/kg/min" instead of "ml/(kg*min)").
//  3. The VO₂ Max unit round-trips: a value written with our unit can be read
//     back with the same unit, proving the unit is self-consistent.
//

import XCTest
import HealthKit
@testable import HealthMd

final class HealthKitUnitsTests: XCTestCase {

    // MARK: - Unit string correctness

    func testCountPerMinute_unitString() {
        // Heart rate, respiratory rate, etc.
        XCTAssertEqual(HKUnits.countPerMinute.unitString, "count/min")
    }

    func testVO2Max_unitString() {
        // This is the unit that crashed v1.7.5.
        // "ml/kg/min" (two bare divisions, no parentheses) is INVALID and throws NSException.
        // The programmatic API produces "mL/min·kg" — mathematically identical to
        // mL/(kg·min) since multiplication is commutative, but written in HealthKit's
        // canonical form with capital-L litre and the Unicode middle-dot separator.
        XCTAssertEqual(HKUnits.vo2Max.unitString, "mL/min·kg")
    }

    func testMilligramsPerDeciliter_unitString() {
        XCTAssertEqual(HKUnits.milligramsPerDeciliter.unitString, "mg/dL")
    }

    func testMilligrams_unitString() {
        XCTAssertEqual(HKUnits.milligrams.unitString, "mg")
    }

    // MARK: - Round-trip value consistency

    /// A quantity written with our VO₂ Max unit must be readable with the same
    /// unit and return the original value. This proves the unit is self-consistent
    /// and not just a string that happens to parse.
    func testVO2Max_roundTrip() {
        let expectedVO2 = 42.5 // mL/(kg·min) — typical athletic value
        let quantity = HKQuantity(unit: HKUnits.vo2Max, doubleValue: expectedVO2)
        let readBack = quantity.doubleValue(for: HKUnits.vo2Max)
        XCTAssertEqual(readBack, expectedVO2, accuracy: 0.001)
    }

    func testCountPerMinute_roundTrip() {
        let bpm = 72.0
        let quantity = HKQuantity(unit: HKUnits.countPerMinute, doubleValue: bpm)
        XCTAssertEqual(quantity.doubleValue(for: HKUnits.countPerMinute), bpm, accuracy: 0.001)
    }

    func testMilligramsPerDeciliter_roundTrip() {
        let glucose = 95.0
        let quantity = HKQuantity(unit: HKUnits.milligramsPerDeciliter, doubleValue: glucose)
        XCTAssertEqual(quantity.doubleValue(for: HKUnits.milligramsPerDeciliter), glucose, accuracy: 0.001)
    }

    func testMilligrams_roundTrip() {
        let sodium = 2300.0
        let quantity = HKQuantity(unit: HKUnits.milligrams, doubleValue: sodium)
        XCTAssertEqual(quantity.doubleValue(for: HKUnits.milligrams), sodium, accuracy: 0.001)
    }

    // MARK: - Regression: the exact invalid string from v1.7.5

    /// Documents what would have happened in v1.7.5.
    /// `HKUnit(from: "ml/kg/min")` throws an ObjC NSException — it cannot be
    /// caught by Swift's `do/catch`. This test cannot safely call that initialiser,
    /// but it serves as a living reminder of the invalid form and verifies that
    /// our constant produces a *different* (correct) string.
    func testVO2Max_notTheBadString() {
        // "ml/kg/min" is the invalid string that crashed v1.7.5.
        // Our programmatic unit produces "mL/min·kg" — HealthKit's canonical form,
        // which is valid and mathematically equivalent to mL/(kg·min).
        let badString  = "ml/kg/min"
        let goodString = HKUnits.vo2Max.unitString
        XCTAssertNotEqual(goodString, badString,
            "HKUnits.vo2Max must not produce the invalid string that crashed v1.7.5")
        XCTAssertEqual(goodString, "mL/min·kg",
            "VO₂ Max unit must match HealthKit's canonical programmatic form")
    }
}
