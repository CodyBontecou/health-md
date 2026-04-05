//
//  ExportFixtures.swift
//  HealthMdTests
//
//  Canonical fixture datasets for export contract/golden tests.
//  All fixtures use fixed dates and values for deterministic output.
//

import Foundation
@testable import HealthMd

/// Provides canonical HealthData fixtures for export testing.
enum ExportFixtures {
    /// Fixed reference date: 2026-03-15T00:00:00Z
    static let referenceDate: Date = {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: 2026, month: 3, day: 15))!
    }()

    // MARK: - Empty Day

    /// A day with no health data at all.
    static var emptyDay: HealthData {
        HealthData(date: referenceDate)
    }

    // MARK: - Partial Day

    /// A day with only sleep and activity data (common for basic Apple Watch users).
    static var partialDay: HealthData {
        var data = HealthData(date: referenceDate)
        data.sleep = SleepData(
            totalDuration: 7.5 * 3600,
            deepSleep: 1.5 * 3600,
            remSleep: 2.0 * 3600,
            coreSleep: 4.0 * 3600
        )
        data.activity = ActivityData(
            steps: 8500,
            activeCalories: 350.0,
            exerciseMinutes: 32.0,
            flightsClimbed: 5,
            walkingRunningDistance: 6200.0
        )
        return data
    }

    // MARK: - Fully Populated Day

    /// A day with all categories populated (power user / full health tracking).
    static var fullDay: HealthData {
        var data = HealthData(date: referenceDate)
        data.sleep = SleepData(
            totalDuration: 7.75 * 3600,
            deepSleep: 1.5 * 3600,
            remSleep: 2.25 * 3600,
            coreSleep: 4.0 * 3600,
            awakeTime: 0.25 * 3600,
            inBedTime: 8.0 * 3600
        )
        data.activity = ActivityData(
            steps: 12500,
            activeCalories: 520.0,
            exerciseMinutes: 45.0,
            flightsClimbed: 8,
            walkingRunningDistance: 9500.0,
            standHours: 11,
            basalEnergyBurned: 1650.0,
            cyclingDistance: 3200.0,
            vo2Max: 42.5
        )
        data.heart = HeartData(
            restingHeartRate: 58.0,
            walkingHeartRateAverage: 105.0,
            averageHeartRate: 72.0,
            hrv: 42.0,
            heartRateMin: 52.0,
            heartRateMax: 155.0
        )
        data.vitals = VitalsData(
            respiratoryRateAvg: 15.0,
            respiratoryRateMin: 12.0,
            respiratoryRateMax: 18.0,
            bloodOxygenAvg: 0.97,
            bloodOxygenMin: 0.94,
            bloodOxygenMax: 0.99
        )
        data.body = BodyData(
            weight: 75.0,
            bodyFatPercentage: 0.18,
            height: 1.78,
            bmi: 23.7
        )
        data.nutrition = NutritionData(
            dietaryEnergy: 2100.0,
            protein: 120.0,
            carbohydrates: 250.0,
            fat: 70.0,
            fiber: 25.0,
            sugar: 45.0,
            water: 2.5,
            caffeine: 200.0
        )
        data.mindfulness = MindfulnessData(
            mindfulMinutes: 15.0,
            mindfulSessions: 2
        )
        data.mobility = MobilityData(
            walkingSpeed: 1.4,
            walkingStepLength: 0.72,
            walkingDoubleSupportPercentage: 0.28
        )
        data.hearing = HearingData(
            headphoneAudioLevel: 72.0,
            environmentalSoundLevel: 55.0
        )
        data.workouts = [
            WorkoutData(
                workoutType: .running,
                startTime: referenceDate,
                duration: 1800,
                calories: 300,
                distance: 5000
            )
        ]
        return data
    }

    // MARK: - Fully Populated Day with Granular Data

    /// Same as fullDay but with time-series sample arrays populated.
    static var fullDayGranular: HealthData {
        var data = fullDay

        // Heart rate samples spread across the day
        let cal = Calendar(identifier: .gregorian)
        let h6  = cal.date(byAdding: .hour, value: 6, to: referenceDate)!
        let h9  = cal.date(byAdding: .hour, value: 9, to: referenceDate)!
        let h12 = cal.date(byAdding: .hour, value: 12, to: referenceDate)!
        let h15 = cal.date(byAdding: .hour, value: 15, to: referenceDate)!
        let h20 = cal.date(byAdding: .hour, value: 20, to: referenceDate)!

        data.heart.heartRateSamples = [
            TimeSample(timestamp: h6,  value: 55.0),
            TimeSample(timestamp: h9,  value: 72.0),
            TimeSample(timestamp: h12, value: 85.0),
            TimeSample(timestamp: h15, value: 68.0),
            TimeSample(timestamp: h20, value: 60.0),
        ]
        data.heart.hrvSamples = [
            TimeSample(timestamp: h6,  value: 45.0),
            TimeSample(timestamp: h20, value: 38.0),
        ]

        // Sleep stage samples (night before referenceDate)
        let bedtime = cal.date(byAdding: .hour, value: -2, to: referenceDate)! // 22:00 previous day
        data.sleep.stages = [
            SleepStageSample(stage: "deep", startDate: bedtime, endDate: bedtime.addingTimeInterval(5400)),
            SleepStageSample(stage: "rem",  startDate: bedtime.addingTimeInterval(5400), endDate: bedtime.addingTimeInterval(12600)),
            SleepStageSample(stage: "core", startDate: bedtime.addingTimeInterval(12600), endDate: bedtime.addingTimeInterval(23400)),
            SleepStageSample(stage: "awake", startDate: bedtime.addingTimeInterval(23400), endDate: bedtime.addingTimeInterval(24300)),
        ]

        // Vitals samples
        data.vitals.bloodOxygenSamples = [
            TimeSample(timestamp: h6,  value: 0.96),
            TimeSample(timestamp: h12, value: 0.98),
            TimeSample(timestamp: h20, value: 0.97),
        ]
        data.vitals.bloodGlucoseSamples = [
            TimeSample(timestamp: h9,  value: 90.0),
            TimeSample(timestamp: h15, value: 110.0),
        ]
        data.vitals.respiratoryRateSamples = [
            TimeSample(timestamp: h6,  value: 14.0),
            TimeSample(timestamp: h12, value: 16.0),
        ]

        return data
    }

    // MARK: - Edge Case Day

    /// A day with edge cases: negative valence, sparse vitals, nil optionals.
    static var edgeCaseDay: HealthData {
        var data = HealthData(date: referenceDate)
        data.sleep = SleepData(
            totalDuration: 0, // no sleep recorded
            deepSleep: 0,
            remSleep: 0,
            coreSleep: 0
        )
        data.activity = ActivityData(
            steps: 0 // zero steps
        )
        data.heart = HeartData(
            restingHeartRate: nil,
            averageHeartRate: 0 // edge: zero HR
        )
        data.mindfulness = MindfulnessData(
            mindfulMinutes: nil,
            mindfulSessions: nil,
            stateOfMind: [
                StateOfMindEntry(
                    timestamp: referenceDate,
                    kind: .dailyMood,
                    valence: -0.8, // very unpleasant
                    labels: ["Anxious", "Stressed"],
                    associations: ["Work"]
                )
            ]
        )
        data.vitals = VitalsData(
            respiratoryRateAvg: nil,
            bloodOxygenAvg: nil,
            bodyTemperatureAvg: 36.5 // only temp recorded
        )
        return data
    }
}
