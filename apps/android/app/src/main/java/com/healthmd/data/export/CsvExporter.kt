package com.healthmd.data.export

import com.healthmd.domain.model.*

class CsvExporter {

    fun export(
        data: HealthData,
        customization: FormatCustomization = FormatCustomization(),
    ): String {
        val dateString = customization.dateFormat.format(data.date)
        val converter = customization.unitConverter
        val distanceUnit = converter.distanceUnit()
        val weightUnit = converter.weightUnit()
        val tempUnit = converter.temperatureUnit()

        return buildString {
            append("Date,Category,Metric,Value,Unit\n")

            // Sleep
            if (data.sleep.hasData) {
                val s = data.sleep
                s.totalDuration.takeIf { it > kotlin.time.Duration.ZERO }?.let { append("$dateString,Sleep,Total Duration,${it.inWholeSeconds},seconds\n") }
                s.deepSleep.takeIf { it > kotlin.time.Duration.ZERO }?.let { append("$dateString,Sleep,Deep Sleep,${it.inWholeSeconds},seconds\n") }
                s.remSleep.takeIf { it > kotlin.time.Duration.ZERO }?.let { append("$dateString,Sleep,REM Sleep,${it.inWholeSeconds},seconds\n") }
                s.lightSleep.takeIf { it > kotlin.time.Duration.ZERO }?.let { append("$dateString,Sleep,Light Sleep,${it.inWholeSeconds},seconds\n") }
                s.awakeTime.takeIf { it > kotlin.time.Duration.ZERO }?.let { append("$dateString,Sleep,Awake Time,${it.inWholeSeconds},seconds\n") }
                s.inBedTime.takeIf { it > kotlin.time.Duration.ZERO }?.let { append("$dateString,Sleep,In Bed Time,${it.inWholeSeconds},seconds\n") }
            }

            // Activity
            if (data.activity.hasData) {
                val a = data.activity
                a.steps?.let { append("$dateString,Activity,Steps,$it,count\n") }
                a.activeCalories?.let { append("$dateString,Activity,Active Calories,$it,kcal\n") }
                a.basalEnergyBurned?.let { append("$dateString,Activity,Basal Energy,$it,kcal\n") }
                a.exerciseMinutes?.let { append("$dateString,Activity,Exercise Minutes,$it,minutes\n") }
                a.flightsClimbed?.let { append("$dateString,Activity,Floors Climbed,$it,count\n") }
                a.walkingRunningDistance?.let { append("$dateString,Activity,Walking Running Distance,$it,meters\n") }
                a.cyclingDistance?.let { append("$dateString,Activity,Cycling Distance,$it,meters\n") }
            }

            // Heart
            if (data.heart.hasData) {
                val h = data.heart
                h.restingHeartRate?.let { append("$dateString,Heart,Resting Heart Rate,$it,bpm\n") }
                h.averageHeartRate?.let { append("$dateString,Heart,Average Heart Rate,$it,bpm\n") }
                h.heartRateMin?.let { append("$dateString,Heart,Min Heart Rate,$it,bpm\n") }
                h.heartRateMax?.let { append("$dateString,Heart,Max Heart Rate,$it,bpm\n") }
                h.hrv?.let { append("$dateString,Heart,HRV (RMSSD),$it,ms\n") }
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
            }

            // Body
            if (data.body.hasData) {
                val b = data.body
                b.weight?.let { append("$dateString,Body,Weight,${String.format("%.1f", converter.convertWeight(it))},$weightUnit\n") }
                b.height?.let { append("$dateString,Body,Height,${String.format("%.1f", converter.convertHeight(it))},${converter.heightUnit()}\n") }
                b.bmi?.let { append("$dateString,Body,BMI,$it,\n") }
                b.bodyFatPercentage?.let { append("$dateString,Body,Body Fat Percentage,${it * 100},percent\n") }
                b.leanBodyMass?.let { append("$dateString,Body,Lean Body Mass,${String.format("%.1f", converter.convertWeight(it))},$weightUnit\n") }
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
            }

            // Workouts
            for (workout in data.workouts) {
                val timeStr = customization.timeFormat.format(workout.startTime)
                append("$dateString,Workouts,${workout.workoutType.displayName} Start Time,$timeStr,time\n")
                append("$dateString,Workouts,${workout.workoutType.displayName} Duration,${workout.duration.inWholeSeconds},seconds\n")
                workout.distance?.takeIf { it > 0 }?.let {
                    append("$dateString,Workouts,${workout.workoutType.displayName} Distance,${String.format("%.2f", converter.convertDistance(it))},$distanceUnit\n")
                }
                workout.calories?.takeIf { it > 0 }?.let {
                    append("$dateString,Workouts,${workout.workoutType.displayName} Calories,$it,kcal\n")
                }
            }
        }
    }
}
