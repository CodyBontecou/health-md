package com.healthmd.data.export

import com.healthmd.domain.model.*
import kotlinx.serialization.json.*

class JsonExporter {

    fun export(
        data: HealthData,
        customization: FormatCustomization = FormatCustomization(),
    ): String {
        val dateString = customization.dateFormat.format(data.date)
        val converter = customization.unitConverter

        val json = buildJsonObject {
            put("date", dateString)
            put("type", "health-data")
            put("units", customization.unitPreference.displayName.lowercase())

            // Sleep
            if (data.sleep.hasData) {
                putJsonObject("sleep") {
                    val s = data.sleep
                    s.totalDuration.takeIf { it > kotlin.time.Duration.ZERO }?.let {
                        put("totalDuration", it.inWholeSeconds.toDouble())
                        put("totalDurationFormatted", ExportHelpers.formatDuration(it))
                    }
                    s.deepSleep.takeIf { it > kotlin.time.Duration.ZERO }?.let {
                        put("deepSleep", it.inWholeSeconds.toDouble())
                        put("deepSleepFormatted", ExportHelpers.formatDuration(it))
                    }
                    s.remSleep.takeIf { it > kotlin.time.Duration.ZERO }?.let {
                        put("remSleep", it.inWholeSeconds.toDouble())
                        put("remSleepFormatted", ExportHelpers.formatDuration(it))
                    }
                    s.lightSleep.takeIf { it > kotlin.time.Duration.ZERO }?.let {
                        put("lightSleep", it.inWholeSeconds.toDouble())
                        put("lightSleepFormatted", ExportHelpers.formatDuration(it))
                    }
                    s.awakeTime.takeIf { it > kotlin.time.Duration.ZERO }?.let {
                        put("awakeTime", it.inWholeSeconds.toDouble())
                        put("awakeTimeFormatted", ExportHelpers.formatDuration(it))
                    }
                    s.inBedTime.takeIf { it > kotlin.time.Duration.ZERO }?.let {
                        put("inBedTime", it.inWholeSeconds.toDouble())
                        put("inBedTimeFormatted", ExportHelpers.formatDuration(it))
                    }
                }
            }

            // Activity
            if (data.activity.hasData) {
                putJsonObject("activity") {
                    val a = data.activity
                    a.steps?.let { put("steps", it) }
                    a.activeCalories?.let { put("activeCalories", it) }
                    a.totalCalories?.let { put("totalCalories", it) }
                    a.basalEnergyBurned?.let { put("basalEnergyBurned", it) }
                    a.exerciseMinutes?.let { put("exerciseMinutes", it) }
                    a.flightsClimbed?.let { put("flightsClimbed", it) }
                    a.walkingRunningDistance?.let {
                        put("walkingRunningDistance", it)
                        put("walkingRunningDistanceKm", it / 1000)
                    }
                    a.cyclingDistance?.let {
                        put("cyclingDistance", it)
                        put("cyclingDistanceKm", it / 1000)
                    }
                    a.elevationGained?.let { put("elevationGained", it) }
                    a.wheelchairPushes?.let { put("wheelchairPushes", it) }
                }
            }

            // Heart
            if (data.heart.hasData) {
                putJsonObject("heart") {
                    val h = data.heart
                    h.restingHeartRate?.let { put("restingHeartRate", it) }
                    h.averageHeartRate?.let { put("averageHeartRate", it) }
                    h.heartRateMin?.let { put("heartRateMin", it) }
                    h.heartRateMax?.let { put("heartRateMax", it) }
                    h.hrv?.let { put("hrv", it) }
                }
            }

            // Vitals
            if (data.vitals.hasData) {
                putJsonObject("vitals") {
                    val v = data.vitals
                    v.respiratoryRateAvg?.let { put("respiratoryRateAvg", it) }
                    v.respiratoryRateMin?.let { put("respiratoryRateMin", it) }
                    v.respiratoryRateMax?.let { put("respiratoryRateMax", it) }
                    v.bloodOxygenAvg?.let {
                        put("bloodOxygenAvg", it)
                        put("bloodOxygenPercent", it * 100)
                    }
                    v.bloodOxygenMin?.let { put("bloodOxygenMin", it) }
                    v.bloodOxygenMax?.let { put("bloodOxygenMax", it) }
                    v.bodyTemperatureAvg?.let { put("bodyTemperatureAvg", it) }
                    v.bodyTemperatureMin?.let { put("bodyTemperatureMin", it) }
                    v.bodyTemperatureMax?.let { put("bodyTemperatureMax", it) }
                    v.bloodPressureSystolicAvg?.let { put("bloodPressureSystolicAvg", it) }
                    v.bloodPressureSystolicMin?.let { put("bloodPressureSystolicMin", it) }
                    v.bloodPressureSystolicMax?.let { put("bloodPressureSystolicMax", it) }
                    v.bloodPressureDiastolicAvg?.let { put("bloodPressureDiastolicAvg", it) }
                    v.bloodPressureDiastolicMin?.let { put("bloodPressureDiastolicMin", it) }
                    v.bloodPressureDiastolicMax?.let { put("bloodPressureDiastolicMax", it) }
                    v.bloodGlucoseAvg?.let { put("bloodGlucoseAvg", it) }
                    v.bloodGlucoseMin?.let { put("bloodGlucoseMin", it) }
                    v.bloodGlucoseMax?.let { put("bloodGlucoseMax", it) }
                    v.basalBodyTemperature?.let { put("basalBodyTemperature", it) }
                    v.skinTemperatureDelta?.let { put("skinTemperatureDelta", it) }
                }
            }

            // Body
            if (data.body.hasData) {
                putJsonObject("body") {
                    val b = data.body
                    b.weight?.let { put("weight", it) }
                    b.height?.let { put("height", it) }
                    b.bmi?.let { put("bmi", it) }
                    b.bodyFatPercentage?.let {
                        put("bodyFatPercentage", it)
                        put("bodyFatPercent", it * 100)
                    }
                    b.leanBodyMass?.let { put("leanBodyMass", it) }
                    b.bodyWaterMass?.let { put("bodyWaterMass", it) }
                    b.boneMass?.let { put("boneMass", it) }
                }
            }

            // Nutrition
            if (data.nutrition.hasData) {
                putJsonObject("nutrition") {
                    val n = data.nutrition
                    n.dietaryEnergy?.let { put("dietaryEnergy", it) }
                    n.protein?.let { put("protein", it) }
                    n.carbohydrates?.let { put("carbohydrates", it) }
                    n.fat?.let { put("fat", it) }
                    n.saturatedFat?.let { put("saturatedFat", it) }
                    n.fiber?.let { put("fiber", it) }
                    n.sugar?.let { put("sugar", it) }
                    n.sodium?.let { put("sodium", it) }
                    n.cholesterol?.let { put("cholesterol", it) }
                    n.water?.let { put("water", it) }
                    n.caffeine?.let { put("caffeine", it) }
                }
            }

            // Mobility
            if (data.mobility.hasData) {
                putJsonObject("mobility") {
                    val m = data.mobility
                    m.walkingSpeed?.let { put("walkingSpeed", it) }
                    m.vo2Max?.let { put("vo2Max", it) }
                    m.cyclingCadenceAvg?.let { put("cyclingCadenceAvg", it) }
                    m.stepsCadenceAvg?.let { put("stepsCadenceAvg", it) }
                    m.powerAvg?.let { put("powerAvg", it) }
                    m.powerMax?.let { put("powerMax", it) }
                }
            }

            // Reproductive Health
            if (data.reproductiveHealth.hasData) {
                putJsonObject("reproductiveHealth") {
                    val r = data.reproductiveHealth
                    r.menstrualFlow?.let { put("menstrualFlow", it) }
                    r.cervicalMucusAppearance?.let { put("cervicalMucusAppearance", it) }
                    r.cervicalMucusSensation?.let { put("cervicalMucusSensation", it) }
                    r.ovulationTestResult?.let { put("ovulationTestResult", it) }
                    if (r.intermenstrualBleeding) put("intermenstrualBleeding", true)
                    if (r.sexualActivityRecorded) {
                        put("sexualActivity", true)
                        r.sexualActivityProtectionUsed?.let { put("protectionUsed", it) }
                    }
                }
            }

            // Mindfulness
            if (data.mindfulness.hasData) {
                putJsonObject("mindfulness") {
                    data.mindfulness.mindfulnessMinutes?.let { put("mindfulnessMinutes", it) }
                }
            }

            // Workouts
            if (data.workouts.isNotEmpty()) {
                putJsonArray("workouts") {
                    for (workout in data.workouts) {
                        addJsonObject {
                            put("type", workout.workoutType.displayName)
                            put("startTime", customization.timeFormat.format(workout.startTime))
                            put("duration", workout.duration.inWholeSeconds.toDouble())
                            put("durationFormatted", ExportHelpers.formatDurationShort(workout.duration))
                            workout.distance?.takeIf { it > 0 }?.let {
                                put("distance", it)
                                put("distanceFormatted", converter.formatDistance(it))
                            }
                            workout.calories?.takeIf { it > 0 }?.let {
                                put("calories", it)
                            }
                        }
                    }
                }
            }
        }

        val prettyJson = Json { prettyPrint = true }
        return prettyJson.encodeToString(JsonElement.serializer(), json)
    }
}
