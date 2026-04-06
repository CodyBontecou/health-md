import Foundation

/// Canonical export snapshot built once per export operation.
///
/// All format exporters (Markdown/JSON/CSV/Obsidian) should read metric data
/// from this structure so metric extraction lives in one place.
struct ExportDataSnapshot {

    struct Sleep {
        let totalDurationSeconds: TimeInterval
        let deepSleepSeconds: TimeInterval
        let remSleepSeconds: TimeInterval
        let coreSleepSeconds: TimeInterval
        let awakeSeconds: TimeInterval
        let inBedSeconds: TimeInterval
        let bedtime: Date?
        let wakeTime: Date?
        let stages: [SleepStageSample]

        var hasData: Bool {
            totalDurationSeconds > 0 || deepSleepSeconds > 0 || remSleepSeconds > 0 ||
            coreSleepSeconds > 0 || awakeSeconds > 0 || inBedSeconds > 0
        }
    }

    struct Activity {
        let steps: Int?
        let activeCalories: Double?
        let basalEnergyBurned: Double?
        let exerciseMinutes: Double?
        let standHours: Int?
        let flightsClimbed: Int?
        let walkingRunningDistanceMeters: Double?
        let cyclingDistanceMeters: Double?
        let swimmingDistanceMeters: Double?
        let swimmingStrokes: Int?
        let wheelchairPushes: Int?
        let vo2Max: Double?

        var hasData: Bool {
            steps != nil || activeCalories != nil || basalEnergyBurned != nil ||
            exerciseMinutes != nil || standHours != nil || flightsClimbed != nil ||
            walkingRunningDistanceMeters != nil || cyclingDistanceMeters != nil ||
            swimmingDistanceMeters != nil || swimmingStrokes != nil ||
            wheelchairPushes != nil || vo2Max != nil
        }
    }

    struct Heart {
        let restingHeartRate: Double?
        let walkingHeartRateAverage: Double?
        let averageHeartRate: Double?
        let minHeartRate: Double?
        let maxHeartRate: Double?
        let hrvMilliseconds: Double?
        let heartRateSamples: [TimeSample]
        let hrvSamples: [TimeSample]

        var hasData: Bool {
            restingHeartRate != nil || walkingHeartRateAverage != nil ||
            averageHeartRate != nil || minHeartRate != nil ||
            maxHeartRate != nil || hrvMilliseconds != nil
        }
    }

    struct Vitals {
        let respiratoryRateAvg: Double?
        let respiratoryRateMin: Double?
        let respiratoryRateMax: Double?

        let bloodOxygenAvg: Double?
        let bloodOxygenMin: Double?
        let bloodOxygenMax: Double?

        let bodyTemperatureAvgCelsius: Double?
        let bodyTemperatureMinCelsius: Double?
        let bodyTemperatureMaxCelsius: Double?

        let bloodPressureSystolicAvg: Double?
        let bloodPressureSystolicMin: Double?
        let bloodPressureSystolicMax: Double?

        let bloodPressureDiastolicAvg: Double?
        let bloodPressureDiastolicMin: Double?
        let bloodPressureDiastolicMax: Double?

        let bloodGlucoseAvg: Double?
        let bloodGlucoseMin: Double?
        let bloodGlucoseMax: Double?

        let bloodOxygenSamples: [TimeSample]
        let bloodGlucoseSamples: [TimeSample]
        let respiratoryRateSamples: [TimeSample]

        var hasData: Bool {
            respiratoryRateAvg != nil || bloodOxygenAvg != nil ||
            bodyTemperatureAvgCelsius != nil || bloodPressureSystolicAvg != nil ||
            bloodPressureDiastolicAvg != nil || bloodGlucoseAvg != nil
        }
    }

    struct Body {
        let weightKg: Double?
        let heightMeters: Double?
        let bmi: Double?
        let bodyFatRatio: Double?
        let leanBodyMassKg: Double?
        let waistCircumferenceMeters: Double?

        var hasData: Bool {
            weightKg != nil || heightMeters != nil || bmi != nil || bodyFatRatio != nil ||
            leanBodyMassKg != nil || waistCircumferenceMeters != nil
        }
    }

    struct Nutrition {
        let dietaryEnergyKcal: Double?
        let proteinGrams: Double?
        let carbohydratesGrams: Double?
        let fatGrams: Double?
        let saturatedFatGrams: Double?
        let fiberGrams: Double?
        let sugarGrams: Double?
        let sodiumMg: Double?
        let cholesterolMg: Double?
        let waterLiters: Double?
        let caffeineMg: Double?

        var hasData: Bool {
            dietaryEnergyKcal != nil || proteinGrams != nil || carbohydratesGrams != nil ||
            fatGrams != nil || saturatedFatGrams != nil || fiberGrams != nil ||
            sugarGrams != nil || sodiumMg != nil || cholesterolMg != nil ||
            waterLiters != nil || caffeineMg != nil
        }
    }

    struct Mindfulness {
        let mindfulMinutes: Double?
        let mindfulSessions: Int?
        let stateOfMindEntries: [StateOfMindEntry]

        let averageValence: Double?
        let averageValencePercent: Int?

        let dailyMoods: [StateOfMindEntry]
        let momentaryEmotions: [StateOfMindEntry]

        let averageDailyMoodValence: Double?
        let emotionLabels: [String]
        let associations: [String]

        var hasData: Bool {
            mindfulMinutes != nil || mindfulSessions != nil || !stateOfMindEntries.isEmpty
        }
    }

    struct Mobility {
        let walkingSpeedMps: Double?
        let walkingStepLengthMeters: Double?
        let walkingDoubleSupportRatio: Double?
        let walkingAsymmetryRatio: Double?
        let stairAscentSpeedMps: Double?
        let stairDescentSpeedMps: Double?
        let sixMinuteWalkDistanceMeters: Double?

        var hasData: Bool {
            walkingSpeedMps != nil || walkingStepLengthMeters != nil ||
            walkingDoubleSupportRatio != nil || walkingAsymmetryRatio != nil ||
            stairAscentSpeedMps != nil || stairDescentSpeedMps != nil ||
            sixMinuteWalkDistanceMeters != nil
        }
    }

    struct Hearing {
        let headphoneAudioLevelDb: Double?
        let environmentalSoundLevelDb: Double?

        var hasData: Bool {
            headphoneAudioLevelDb != nil || environmentalSoundLevelDb != nil
        }
    }

    let date: Date
    let dateString: String
    let unitPreference: UnitPreference
    let converter: UnitConverter
    let timeFormat: TimeFormatPreference

    /// Canonical frontmatter metric values keyed by original snake_case key.
    let frontmatterMetrics: [String: String]

    let sleep: Sleep
    let activity: Activity
    let heart: Heart
    let vitals: Vitals
    let body: Body
    let nutrition: Nutrition
    let mindfulness: Mindfulness
    let mobility: Mobility
    let hearing: Hearing
    let workouts: [WorkoutData]
}

extension HealthData {
    func exportSnapshot(customization: FormatCustomization) -> ExportDataSnapshot {
        let converter = customization.unitConverter
        let dateString = customization.dateFormat.format(date: date)

        let mindfulnessDerivation = ExportFrontmatterMetricBuilder.deriveMindfulness(from: mindfulness)

        return ExportDataSnapshot(
            date: date,
            dateString: dateString,
            unitPreference: customization.unitPreference,
            converter: converter,
            timeFormat: customization.timeFormat,
            frontmatterMetrics: ExportFrontmatterMetricBuilder.build(
                from: self,
                converter: converter,
                timeFormat: customization.timeFormat,
                mindfulness: mindfulnessDerivation
            ),
            sleep: .init(
                totalDurationSeconds: sleep.totalDuration,
                deepSleepSeconds: sleep.deepSleep,
                remSleepSeconds: sleep.remSleep,
                coreSleepSeconds: sleep.coreSleep,
                awakeSeconds: sleep.awakeTime,
                inBedSeconds: sleep.inBedTime,
                bedtime: sleep.sessionStart,
                wakeTime: sleep.sessionEnd,
                stages: sleep.stages
            ),
            activity: .init(
                steps: activity.steps,
                activeCalories: activity.activeCalories,
                basalEnergyBurned: activity.basalEnergyBurned,
                exerciseMinutes: activity.exerciseMinutes,
                standHours: activity.standHours,
                flightsClimbed: activity.flightsClimbed,
                walkingRunningDistanceMeters: activity.walkingRunningDistance,
                cyclingDistanceMeters: activity.cyclingDistance,
                swimmingDistanceMeters: activity.swimmingDistance,
                swimmingStrokes: activity.swimmingStrokes,
                wheelchairPushes: activity.pushCount,
                vo2Max: activity.vo2Max
            ),
            heart: .init(
                restingHeartRate: heart.restingHeartRate,
                walkingHeartRateAverage: heart.walkingHeartRateAverage,
                averageHeartRate: heart.averageHeartRate,
                minHeartRate: heart.heartRateMin,
                maxHeartRate: heart.heartRateMax,
                hrvMilliseconds: heart.hrv,
                heartRateSamples: heart.heartRateSamples,
                hrvSamples: heart.hrvSamples
            ),
            vitals: .init(
                respiratoryRateAvg: vitals.respiratoryRateAvg,
                respiratoryRateMin: vitals.respiratoryRateMin,
                respiratoryRateMax: vitals.respiratoryRateMax,
                bloodOxygenAvg: vitals.bloodOxygenAvg,
                bloodOxygenMin: vitals.bloodOxygenMin,
                bloodOxygenMax: vitals.bloodOxygenMax,
                bodyTemperatureAvgCelsius: vitals.bodyTemperatureAvg,
                bodyTemperatureMinCelsius: vitals.bodyTemperatureMin,
                bodyTemperatureMaxCelsius: vitals.bodyTemperatureMax,
                bloodPressureSystolicAvg: vitals.bloodPressureSystolicAvg,
                bloodPressureSystolicMin: vitals.bloodPressureSystolicMin,
                bloodPressureSystolicMax: vitals.bloodPressureSystolicMax,
                bloodPressureDiastolicAvg: vitals.bloodPressureDiastolicAvg,
                bloodPressureDiastolicMin: vitals.bloodPressureDiastolicMin,
                bloodPressureDiastolicMax: vitals.bloodPressureDiastolicMax,
                bloodGlucoseAvg: vitals.bloodGlucoseAvg,
                bloodGlucoseMin: vitals.bloodGlucoseMin,
                bloodGlucoseMax: vitals.bloodGlucoseMax,
                bloodOxygenSamples: vitals.bloodOxygenSamples,
                bloodGlucoseSamples: vitals.bloodGlucoseSamples,
                respiratoryRateSamples: vitals.respiratoryRateSamples
            ),
            body: .init(
                weightKg: body.weight,
                heightMeters: body.height,
                bmi: body.bmi,
                bodyFatRatio: body.bodyFatPercentage,
                leanBodyMassKg: body.leanBodyMass,
                waistCircumferenceMeters: body.waistCircumference
            ),
            nutrition: .init(
                dietaryEnergyKcal: nutrition.dietaryEnergy,
                proteinGrams: nutrition.protein,
                carbohydratesGrams: nutrition.carbohydrates,
                fatGrams: nutrition.fat,
                saturatedFatGrams: nutrition.saturatedFat,
                fiberGrams: nutrition.fiber,
                sugarGrams: nutrition.sugar,
                sodiumMg: nutrition.sodium,
                cholesterolMg: nutrition.cholesterol,
                waterLiters: nutrition.water,
                caffeineMg: nutrition.caffeine
            ),
            mindfulness: .init(
                mindfulMinutes: mindfulness.mindfulMinutes,
                mindfulSessions: mindfulness.mindfulSessions,
                stateOfMindEntries: mindfulnessDerivation.entries,
                averageValence: mindfulnessDerivation.averageValence,
                averageValencePercent: mindfulnessDerivation.averageValencePercent,
                dailyMoods: mindfulnessDerivation.dailyMoods,
                momentaryEmotions: mindfulnessDerivation.momentaryEmotions,
                averageDailyMoodValence: mindfulnessDerivation.averageDailyMoodValence,
                emotionLabels: mindfulnessDerivation.labels,
                associations: mindfulnessDerivation.associations
            ),
            mobility: .init(
                walkingSpeedMps: mobility.walkingSpeed,
                walkingStepLengthMeters: mobility.walkingStepLength,
                walkingDoubleSupportRatio: mobility.walkingDoubleSupportPercentage,
                walkingAsymmetryRatio: mobility.walkingAsymmetryPercentage,
                stairAscentSpeedMps: mobility.stairAscentSpeed,
                stairDescentSpeedMps: mobility.stairDescentSpeed,
                sixMinuteWalkDistanceMeters: mobility.sixMinuteWalkDistance
            ),
            hearing: .init(
                headphoneAudioLevelDb: hearing.headphoneAudioLevel,
                environmentalSoundLevelDb: hearing.environmentalSoundLevel
            ),
            workouts: workouts
        )
    }
}
