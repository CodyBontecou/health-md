//
//  HKUnits.swift
//  HealthMd
//
//  Single source of truth for every HKUnit used in the app.
//
//  WHY THIS FILE EXISTS
//  --------------------
//  `HKUnit(from: "string")` validates the string at *runtime* by calling into
//  Objective-C, and throws an NSException when the string is invalid.
//  NSException is *not* a Swift error — it completely bypasses `do/catch` and
//  crashes the app with SIGABRT.  This is exactly what happened in v1.7.5:
//  `HKUnit(from: "ml/kg/min")` (missing parentheses) was silently harmless until
//  the VO2-Max query started returning samples, at which point every export crashed.
//
//  Using the programmatic API instead:
//  • Is resolved entirely at compile time — typos are impossible.
//  • Never throws any exception.
//  • Is unit-testable: `unitString` lets us assert the correct canonical form.
//

import HealthKit

enum HKUnits {

    // MARK: - Rate

    /// beats / respirations per minute  (heart rate, respiratory rate, respiratory rate, push count rate)
    static let countPerMinute: HKUnit = .count().unitDivided(by: .minute())

    // MARK: - Cardio Fitness

    /// mL / (kg · min)  — VO₂ Max / Cardio Fitness
    /// String form "ml/kg/min" is *invalid* (two bare divisions); the correct
    /// canonical form is "ml/(kg*min)".  Use this constant instead of any string.
    static let vo2Max: HKUnit = HKUnit.literUnit(with: .milli)
        .unitDivided(by: HKUnit.gramUnit(with: .kilo).unitMultiplied(by: .minute()))

    // MARK: - Blood

    /// mg/dL  — blood glucose
    static let milligramsPerDeciliter: HKUnit = HKUnit.gramUnit(with: .milli)
        .unitDivided(by: HKUnit.literUnit(with: .deci))

    // MARK: - Mass

    /// mg  — dietary minerals (sodium, cholesterol, caffeine)
    static let milligrams: HKUnit = .gramUnit(with: .milli)
}
