package com.healthmd.data.export

import com.healthmd.domain.model.*

class CsvExporter {

    fun export(
        data: HealthData,
        customization: FormatCustomization = FormatCustomization(),
        includeGranularData: Boolean = false,
    ): String {
        val dateString = customization.dateFormat.format(data.date)
        val converter = customization.unitConverter
        val distanceUnit = converter.distanceUnit()
        val weightUnit = converter.weightUnit()
        val tempUnit = converter.temperatureUnit()

        return buildString {
            if (includeGranularData) {
                append("Date,Category,Metric,Value,Unit,Timestamp\n")
            } else {
                append("Date,Category,Metric,Value,Unit\n")
            }

            // Sleep
            if (data.sleep.hasData) {
                val s = data.sleep
                s.totalDuration.takeIf { it > kotlin.time.Duration.ZERO }?.let { append("$dateString,Sleep,Total Duration,${it.inWholeSeconds},seconds\n") }
                s.deepSleep.takeIf { it > kotlin.time.Duration.ZERO }?.let { append("$dateString,Sleep,Deep Sleep,${it.inWholeSeconds},seconds\n") }
                s.remSleep.takeIf { it > kotlin.time.Duration.ZERO }?.let { append("$dateString,Sleep,REM Sleep,${it.inWholeSeconds},seconds\n") }
                s.lightSleep.takeIf { it > kotlin.time.Duration.ZERO }?.let { append("$dateString,Sleep,Light Sleep,${it.inWholeSeconds},seconds\n") }
                s.awakeTime.takeIf { it > kotlin.time.Duration.ZERO }?.let { append("$dateString,Sleep,Awake Time,${it.inWholeSeconds},seconds\n") }
                s.inBedTime.takeIf { it > kotlin.time.Duration.ZERO }?.let { append("$dateString,Sleep,In Bed Time,${it.inWholeSeconds},seconds\n") }
                if (includeGranularData) {
                    for (stage in s.stages) {
                        val startStr = customization.timeFormat.format(stage.startTime)
                        val endStr = customization.timeFormat.format(stage.endTime)
                        append("$dateString,Sleep,Stage ${stage.stage},$startStr - $endStr,time range\n")
                    }
                }
            }

            // Activity
            if (data.activity.hasData) {
                val a = data.activity
                a.steps?.let { append("$dateString,Activity,Steps,$it,count\n") }
                a.activeCalories?.let { append("$dateString,Activity,Active Calories,$it,kcal\n") }
                a.totalCalories?.let { append("$dateString,Activity,Total Calories,$it,kcal\n") }
                a.basalEnergyBurned?.let { append("$dateString,Activity,Basal Energy,$it,kcal\n") }
                a.exerciseMinutes?.let { append("$dateString,Activity,Exercise Minutes,$it,minutes\n") }
                a.flightsClimbed?.let { append("$dateString,Activity,Floors Climbed,$it,count\n") }
                a.walkingRunningDistance?.let { append("$dateString,Activity,Walking Running Distance,$it,meters\n") }
                a.cyclingDistance?.let { append("$dateString,Activity,Cycling Distance,$it,meters\n") }
                a.elevationGained?.let { append("$dateString,Activity,Elevation Gained,$it,meters\n") }
                a.wheelchairPushes?.let { append("$dateString,Activity,Wheelchair Pushes,$it,count\n") }
                if (includeGranularData) {
                    for (sample in a.stepSamples) {
                        val timeStr = customization.timeFormat.format(sample.time)
                        append("$dateString,Activity,Steps Sample,${sample.value.toInt()},count,$timeStr\n")
                    }
                }
            }

            // Heart
            if (data.heart.hasData) {
                val h = data.heart
                h.restingHeartRate?.let { append("$dateString,Heart,Resting Heart Rate,$it,bpm\n") }
                h.averageHeartRate?.let { append("$dateString,Heart,Average Heart Rate,$it,bpm\n") }
                h.heartRateMin?.let { append("$dateString,Heart,Min Heart Rate,$it,bpm\n") }
                h.heartRateMax?.let { append("$dateString,Heart,Max Heart Rate,$it,bpm\n") }
                h.hrv?.let { append("$dateString,Heart,HRV (RMSSD),$it,ms\n") }
                if (includeGranularData) {
                    for (sample in h.samples) {
                        val timeStr = customization.timeFormat.format(sample.time)
                        append("$dateString,Heart,Heart Rate Sample,${sample.value.toInt()},bpm,$timeStr\n")
                    }
                    for (sample in h.hrvSamples) {
                        val timeStr = customization.timeFormat.format(sample.time)
                        append("$dateString,Heart,HRV Sample,${String.format("%.1f", sample.value)},ms,$timeStr\n")
                    }
                }
            }

            // Vitals
            if (data.vitals.hasData) {
                val v = data.vitals
                v.respiratoryRateAvg?.let { append("$dateString,Vitals,Respiratory Rate Avg,$it,breaths/min\n") }
                v.respiratoryRateMin?.let { append("$dateString,Vitals,Respiratory Rate Min,$it,breaths/min\n") }
                v.respiratoryRateMax?.let { append("$dateString,Vitals,Respiratory Rate Max,$it,breaths/min\n") }
                v.bloodOxygenAvg?.let { append("$dateString,Vitals,Blood Oxygen Avg,${it * 100},percent\n") }
                v.bloodOxygenMin?.let { append("$dateString,Vitals,Blood Oxygen Min,${it * 100},percent\n") }
                v.bloodOxygenMax?.let { append("$dateString,Vitals,Blood Oxygen Max,${it * 100},percent\n") }
                v.bodyTemperatureAvg?.let { append("$dateString,Vitals,Body Temperature Avg,${String.format("%.1f", converter.convertTemperature(it))},$tempUnit\n") }
                v.bodyTemperatureMin?.let { append("$dateString,Vitals,Body Temperature Min,${String.format("%.1f", converter.convertTemperature(it))},$tempUnit\n") }
                v.bodyTemperatureMax?.let { append("$dateString,Vitals,Body Temperature Max,${String.format("%.1f", converter.convertTemperature(it))},$tempUnit\n") }
                v.bloodPressureSystolicAvg?.let { append("$dateString,Vitals,Blood Pressure Systolic Avg,$it,mmHg\n") }
                v.bloodPressureSystolicMin?.let { append("$dateString,Vitals,Blood Pressure Systolic Min,$it,mmHg\n") }
                v.bloodPressureSystolicMax?.let { append("$dateString,Vitals,Blood Pressure Systolic Max,$it,mmHg\n") }
                v.bloodPressureDiastolicAvg?.let { append("$dateString,Vitals,Blood Pressure Diastolic Avg,$it,mmHg\n") }
                v.bloodPressureDiastolicMin?.let { append("$dateString,Vitals,Blood Pressure Diastolic Min,$it,mmHg\n") }
                v.bloodPressureDiastolicMax?.let { append("$dateString,Vitals,Blood Pressure Diastolic Max,$it,mmHg\n") }
                v.bloodGlucoseAvg?.let { append("$dateString,Vitals,Blood Glucose Avg,$it,mg/dL\n") }
                v.bloodGlucoseMin?.let { append("$dateString,Vitals,Blood Glucose Min,$it,mg/dL\n") }
                v.bloodGlucoseMax?.let { append("$dateString,Vitals,Blood Glucose Max,$it,mg/dL\n") }
                v.basalBodyTemperature?.let { append("$dateString,Vitals,Basal Body Temperature,${String.format("%.1f", converter.convertTemperature(it))},$tempUnit\n") }
                v.skinTemperatureDelta?.let { append("$dateString,Vitals,Skin Temperature Delta,${String.format("%.2f", it)},\u00B0C\n") }
                if (includeGranularData) {
                    for (sample in v.bloodOxygenSamples) {
                        val timeStr = customization.timeFormat.format(sample.time)
                        append("$dateString,Vitals,SpO2 Sample,${sample.value},percent,$timeStr\n")
                    }
                    for (sample in v.bloodPressureSamples) {
                        val timeStr = customization.timeFormat.format(sample.time)
                        append("$dateString,Vitals,Blood Pressure Sample,${sample.systolic.toInt()}/${sample.diastolic.toInt()},mmHg,$timeStr\n")
                    }
                    for (sample in v.bloodGlucoseSamples) {
                        val timeStr = customization.timeFormat.format(sample.time)
                        append("$dateString,Vitals,Blood Glucose Sample,${String.format("%.1f", sample.value)},mg/dL,$timeStr\n")
                    }
                    for (sample in v.respiratoryRateSamples) {
                        val timeStr = customization.timeFormat.format(sample.time)
                        append("$dateString,Vitals,Respiratory Rate Sample,${String.format("%.1f", sample.value)},breaths/min,$timeStr\n")
                    }
                    for (sample in v.bodyTemperatureSamples) {
                        val timeStr = customization.timeFormat.format(sample.time)
                        append("$dateString,Vitals,Body Temperature Sample,${String.format("%.1f", converter.convertTemperature(sample.value))},$tempUnit,$timeStr\n")
                    }
                }
            }

            // Body
            if (data.body.hasData) {
                val b = data.body
                b.weight?.let { append("$dateString,Body,Weight,${String.format("%.1f", converter.convertWeight(it))},$weightUnit\n") }
                b.height?.let { append("$dateString,Body,Height,${String.format("%.1f", converter.convertHeight(it))},${converter.heightUnit()}\n") }
                b.bmi?.let { append("$dateString,Body,BMI,$it,\n") }
                b.bodyFatPercentage?.let { append("$dateString,Body,Body Fat Percentage,${it * 100},percent\n") }
                b.leanBodyMass?.let { append("$dateString,Body,Lean Body Mass,${String.format("%.1f", converter.convertWeight(it))},$weightUnit\n") }
                b.bodyWaterMass?.let { append("$dateString,Body,Body Water Mass,${String.format("%.1f", converter.convertWeight(it))},$weightUnit\n") }
                b.boneMass?.let { append("$dateString,Body,Bone Mass,${String.format("%.1f", converter.convertWeight(it))},$weightUnit\n") }
            }

            // Nutrition
            if (data.nutrition.hasData) {
                val n = data.nutrition
                n.dietaryEnergy?.let { append("$dateString,Nutrition,Dietary Energy,$it,kcal\n") }
                n.protein?.let { append("$dateString,Nutrition,Protein,$it,g\n") }
                n.carbohydrates?.let { append("$dateString,Nutrition,Carbohydrates,$it,g\n") }
                n.fat?.let { append("$dateString,Nutrition,Fat,$it,g\n") }
                n.saturatedFat?.let { append("$dateString,Nutrition,Saturated Fat,$it,g\n") }
                n.fiber?.let { append("$dateString,Nutrition,Fiber,$it,g\n") }
                n.sugar?.let { append("$dateString,Nutrition,Sugar,$it,g\n") }
                n.sodium?.let { append("$dateString,Nutrition,Sodium,$it,mg\n") }
                n.cholesterol?.let { append("$dateString,Nutrition,Cholesterol,$it,mg\n") }
                n.water?.let { append("$dateString,Nutrition,Water,$it,L\n") }
                n.caffeine?.let { append("$dateString,Nutrition,Caffeine,$it,mg\n") }
            }

            // Mobility
            if (data.mobility.hasData) {
                val m = data.mobility
                m.walkingSpeed?.let { append("$dateString,Mobility,Walking Speed,$it,m/s\n") }
                m.vo2Max?.let { append("$dateString,Mobility,VO2 Max,$it,mL/kg/min\n") }
                m.cyclingCadenceAvg?.let { append("$dateString,Mobility,Cycling Cadence,$it,rpm\n") }
                m.stepsCadenceAvg?.let { append("$dateString,Mobility,Steps Cadence,$it,steps/min\n") }
                m.powerAvg?.let { append("$dateString,Mobility,Average Power,$it,W\n") }
                m.powerMax?.let { append("$dateString,Mobility,Max Power,$it,W\n") }
            }

            // Reproductive Health
            if (data.reproductiveHealth.hasData) {
                val r = data.reproductiveHealth
                r.menstrualFlow?.let { append("$dateString,Reproductive Health,Menstrual Flow,$it,\n") }
                r.cervicalMucusAppearance?.let { append("$dateString,Reproductive Health,Cervical Mucus Appearance,$it,\n") }
                r.cervicalMucusSensation?.let { append("$dateString,Reproductive Health,Cervical Mucus Sensation,$it,\n") }
                r.ovulationTestResult?.let { append("$dateString,Reproductive Health,Ovulation Test,$it,\n") }
                if (r.intermenstrualBleeding) append("$dateString,Reproductive Health,Intermenstrual Bleeding,true,\n")
                if (r.sexualActivityRecorded) {
                    append("$dateString,Reproductive Health,Sexual Activity,true,\n")
                    r.sexualActivityProtectionUsed?.let { append("$dateString,Reproductive Health,Protection Used,$it,\n") }
                }
            }

            // Mindfulness
            if (data.mindfulness.hasData) {
                data.mindfulness.mindfulnessMinutes?.let { append("$dateString,Mindfulness,Mindful Minutes,$it,minutes\n") }
            }

            // Workouts
            for (workout in data.workouts) {
                val timeStr = customization.timeFormat.format(workout.startTime)
                val workoutName = workout.workoutType.displayName()
                append("$dateString,Workouts,${workoutName} Start Time,$timeStr,time\n")
                append("$dateString,Workouts,${workoutName} Duration,${workout.duration.inWholeSeconds},seconds\n")
                workout.distance?.takeIf { it > 0 }?.let {
                    append("$dateString,Workouts,${workoutName} Distance,${String.format("%.2f", converter.convertDistance(it))},$distanceUnit\n")
                }
                workout.calories?.takeIf { it > 0 }?.let {
                    append("$dateString,Workouts,${workoutName} Calories,$it,kcal\n")
                }
            }
        }
    }
}
