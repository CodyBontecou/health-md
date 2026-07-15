#if DEBUG
import Foundation

enum UITestHealthKitFixtures {
    static func exportPreviewHealthData(for date: Date, includeGranularData: Bool) -> HealthData {
        let calendar = Calendar.current
        let day = calendar.startOfDay(for: date)

        func time(hour: Int, minute: Int = 0, dayOffset: Int = 0) -> Date {
            let base = calendar.date(byAdding: .day, value: dayOffset, to: day) ?? day
            return calendar.date(bySettingHour: hour, minute: minute, second: 0, of: base) ?? base
        }

        var data = HealthData(date: day)

        let bedtime = time(hour: 22)
        let wake = time(hour: 6, dayOffset: 1)
        data.sleep = SleepData(
            totalDuration: 23_400,
            deepSleep: 5_400,
            remSleep: 7_200,
            coreSleep: 10_800,
            awakeTime: 1_800,
            inBedTime: 28_800,
            sessionStart: bedtime,
            sessionEnd: wake,
            stages: includeGranularData ? [
                SleepStageSample(stage: "inBed", startDate: bedtime, endDate: wake),
                SleepStageSample(stage: "deep", startDate: time(hour: 22, minute: 30), endDate: time(hour: 0, dayOffset: 1)),
                SleepStageSample(stage: "rem", startDate: time(hour: 0, minute: 10, dayOffset: 1), endDate: time(hour: 2, minute: 10, dayOffset: 1)),
                SleepStageSample(stage: "core", startDate: time(hour: 2, minute: 40, dayOffset: 1), endDate: time(hour: 5, minute: 40, dayOffset: 1))
            ] : []
        )

        data.activity = ActivityData(
            steps: 12_500,
            activeCalories: 520,
            exerciseMinutes: 45,
            flightsClimbed: 8,
            walkingRunningDistance: 9_500,
            standHours: 10,
            basalEnergyBurned: 1_800,
            cyclingDistance: 15_000,
            swimmingDistance: 1_500,
            swimmingStrokes: 450,
            pushCount: 0,
            vo2Max: 42.5
        )

        data.heart = HeartData(
            restingHeartRate: 58,
            walkingHeartRateAverage: 105,
            averageHeartRate: 72,
            hrv: 42,
            heartRateMin: 52,
            heartRateMax: 155,
            heartRateSamples: includeGranularData ? [
                TimeSample(timestamp: time(hour: 6), value: 55),
                TimeSample(timestamp: time(hour: 9), value: 72),
                TimeSample(timestamp: time(hour: 12), value: 85),
                TimeSample(timestamp: time(hour: 15), value: 68),
                TimeSample(timestamp: time(hour: 20), value: 60)
            ] : [],
            hrvSamples: includeGranularData ? [
                TimeSample(timestamp: time(hour: 6), value: 45),
                TimeSample(timestamp: time(hour: 20), value: 38)
            ] : []
        )

        data.vitals = VitalsData(
            respiratoryRateAvg: 15.5,
            respiratoryRateMin: 12.0,
            respiratoryRateMax: 20.0,
            bloodOxygenAvg: 0.97,
            bloodOxygenMin: 0.95,
            bloodOxygenMax: 0.99,
            bodyTemperatureAvg: 36.6,
            bodyTemperatureMin: 36.2,
            bodyTemperatureMax: 37.1,
            bloodPressureSystolicAvg: 120,
            bloodPressureSystolicMin: 115,
            bloodPressureSystolicMax: 130,
            bloodPressureDiastolicAvg: 80,
            bloodPressureDiastolicMin: 75,
            bloodPressureDiastolicMax: 85,
            bloodGlucoseAvg: 95,
            bloodGlucoseMin: 80,
            bloodGlucoseMax: 140,
            bloodOxygenSamples: includeGranularData ? [
                TimeSample(timestamp: time(hour: 6), value: 0.96),
                TimeSample(timestamp: time(hour: 12), value: 0.98),
                TimeSample(timestamp: time(hour: 20), value: 0.97)
            ] : [],
            bloodGlucoseSamples: includeGranularData ? [
                TimeSample(timestamp: time(hour: 9), value: 90),
                TimeSample(timestamp: time(hour: 15), value: 110)
            ] : [],
            respiratoryRateSamples: includeGranularData ? [
                TimeSample(timestamp: time(hour: 6), value: 14),
                TimeSample(timestamp: time(hour: 12), value: 16)
            ] : [],
            bloodPressureSamples: includeGranularData ? [
                BloodPressureSample(
                    systolic: 124,
                    diastolic: 81,
                    startDate: time(hour: 9),
                    endDate: time(hour: 9)
                ),
                BloodPressureSample(
                    systolic: 118,
                    diastolic: 77,
                    startDate: time(hour: 9, minute: 2),
                    endDate: time(hour: 9, minute: 2)
                )
            ] : []
        )

        data.body = BodyData(
            weight: 75.0,
            bodyFatPercentage: 0.18,
            height: 1.78,
            bmi: 23.7,
            leanBodyMass: 61.5,
            waistCircumference: 0.82
        )

        data.nutrition = NutritionData(
            dietaryEnergy: 2_100,
            protein: 120,
            carbohydrates: 250,
            fat: 70,
            fiber: 28,
            sugar: 45,
            sodium: 2_300,
            water: 2.5,
            caffeine: 200,
            cholesterol: 300,
            saturatedFat: 22
        )

        data.mindfulness = MindfulnessData(
            mindfulMinutes: 15,
            mindfulSessions: 2,
            stateOfMind: [
                StateOfMindEntry(timestamp: time(hour: 8), kind: .dailyMood, valence: 0.6, labels: ["Calm"], associations: ["Exercise"]),
                StateOfMindEntry(timestamp: time(hour: 18), kind: .momentaryEmotion, valence: 0.2, labels: ["Focused"], associations: ["Work"])
            ]
        )

        data.mobility = MobilityData(
            walkingSpeed: 1.4,
            walkingStepLength: 0.72,
            walkingDoubleSupportPercentage: 0.28,
            walkingAsymmetryPercentage: 0.08,
            stairAscentSpeed: 0.35,
            stairDescentSpeed: 0.40,
            sixMinuteWalkDistance: 520
        )

        data.hearing = HearingData(
            headphoneAudioLevel: 72,
            environmentalSoundLevel: 55
        )

        data.workouts = [
            WorkoutData(
                workoutType: .running,
                startTime: time(hour: 7),
                duration: 1_800,
                calories: 300,
                distance: 5_000,
                avgHeartRate: 142,
                maxHeartRate: 168,
                minHeartRate: 118
            )
        ]

        return data
    }
}
#endif
