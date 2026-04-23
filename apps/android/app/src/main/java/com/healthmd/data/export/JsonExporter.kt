package com.healthmd.data.export

import com.healthmd.domain.model.*
import kotlinx.serialization.json.*
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter

/**
 * Produces JSON health data exports compatible with the iOS Health.md JSON contract.
 *
 * Schema contract: docs/export-contract/ios-export-contract.md
 * Gap matrix:      docs/export-contract/android-ios-gap-matrix.md
 *
 * P0/P1 parity changes applied (see gap matrix §4 Tier-0 / Tier-1):
 *   T0-01  sleep granular array key:  `stages`           → `sleepStages`
 *   T0-02  stage item timestamp keys: `startTime/endTime`→ `startDate/endDate` (ISO 8601)
 *   T0-03  stage item duration:       add `durationSeconds`
 *   T0-04  all sample timestamps:     TimeFormatPreference → ISO 8601
 *   T0-05  heart HR sample value key: `bpm`              → `value`
 *   T0-06  heart HRV sample value key:`ms`               → `value`
 *   T0-07  vitals SpO2 sample key:    `percent`          → `value`
 *   T0-08  vitals glucose sample key: `mgPerDl`          → `value`
 *   T0-09  vitals respRate sample key:`breathsPerMin`    → `value`
 *   T0-10  vo2Max placement:          add to `activity` (kept in `mobility` as Android extra)
 *   T1-01  sleep parity alias:        add `coreSleep`/`coreSleepFormatted` (= lightSleep)
 *   T1-02  sleep bedtime/wake:        add `bedtime`/`bedtimeISO`/`wakeTime`/`wakeTimeISO`
 *   T1-03  mindfulness key:           `mindfulnessMinutes` → `mindfulMinutes`
 *   T1-04  activity push count alias: add `pushCount` (= wheelchairPushes; keep original too)
 *   T1-05  vitals backward-compat:    add `respiratoryRate`, `bloodOxygen`, `bodyTemperature`,
 *                                     `bloodPressureSystolic`, `bloodPressureDiastolic`,
 *                                     `bloodGlucose` aliases
 */
class JsonExporter {

    private val isoFormatter: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE_TIME

    private fun LocalDateTime.toIso8601(): String = format(isoFormatter)

    fun export(
        data: HealthData,
        customization: FormatCustomization = FormatCustomization(),
        includeGranularData: Boolean = false,
    ): String {
        val dateString = customization.dateFormat.format(data.date)
        val converter = customization.unitConverter

        val json = buildJsonObject {
            put("date", dateString)
            put("type", "health-data")
            put("units", customization.unitPreference.name.lowercase())

            // ── Sleep ──────────────────────────────────────────────────────────────────────────
            if (data.sleep.hasData) {
                putJsonObject("sleep") {
                    val s = data.sleep
                    s.totalDuration.takeIf { it > kotlin.time.Duration.ZERO }?.let {
                        put("totalDuration", it.inWholeSeconds.toDouble())
                        put("totalDurationFormatted", ExportHelpers.formatDuration(it))
                    }

                    // Bedtime / wake (T1-02): from sessionStart/End if provided by the reader
                    s.sessionStart?.let { start ->
                        put("bedtime", customization.timeFormat.format(start))
                        put("bedtimeISO", start.toIso8601())
                    }
                    s.sessionEnd?.let { end ->
                        put("wakeTime", customization.timeFormat.format(end))
                        put("wakeTimeISO", end.toIso8601())
                    }
                    // If no explicit sessionStart/End but stages present, derive from stages
                    if (s.sessionStart == null && s.stages.isNotEmpty()) {
                        val earliest = s.stages.minByOrNull { it.startTime }?.startTime
                        val latest = s.stages.maxByOrNull { it.endTime }?.endTime
                        earliest?.let {
                            put("bedtime", customization.timeFormat.format(it))
                            put("bedtimeISO", it.toIso8601())
                        }
                        latest?.let {
                            put("wakeTime", customization.timeFormat.format(it))
                            put("wakeTimeISO", it.toIso8601())
                        }
                    }

                    s.deepSleep.takeIf { it > kotlin.time.Duration.ZERO }?.let {
                        put("deepSleep", it.inWholeSeconds.toDouble())
                        put("deepSleepFormatted", ExportHelpers.formatDuration(it))
                    }
                    s.remSleep.takeIf { it > kotlin.time.Duration.ZERO }?.let {
                        put("remSleep", it.inWholeSeconds.toDouble())
                        put("remSleepFormatted", ExportHelpers.formatDuration(it))
                    }
                    // T1-01: coreSleep = lightSleep (Health Connect "light" ≈ iOS "core" for viz)
                    s.lightSleep.takeIf { it > kotlin.time.Duration.ZERO }?.let {
                        put("coreSleep", it.inWholeSeconds.toDouble())
                        put("coreSleepFormatted", ExportHelpers.formatDuration(it))
                        // Keep Android-native key as well
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

                    // T0-01/02/03/04: renamed array + ISO timestamps + durationSeconds
                    if (includeGranularData && s.stages.isNotEmpty()) {
                        putJsonArray("sleepStages") {
                            for (stage in s.stages) {
                                addJsonObject {
                                    put("stage", stage.stage)
                                    put("startDate", stage.startTime.toIso8601())
                                    put("endDate", stage.endTime.toIso8601())
                                    put(
                                        "durationSeconds",
                                        java.time.Duration.between(stage.startTime, stage.endTime)
                                            .seconds.toDouble(),
                                    )
                                }
                            }
                        }
                    }
                }
            }

            // ── Activity ───────────────────────────────────────────────────────────────────────
            if (data.activity.hasData || data.mobility.vo2Max != null) {
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
                    // T1-04: pushCount (iOS canonical) + wheelchairPushes (Android extra)
                    a.wheelchairPushes?.let {
                        put("pushCount", it)
                        put("wheelchairPushes", it)
                    }
                    // T0-10: vo2Max under activity (iOS canonical placement)
                    data.mobility.vo2Max?.let { put("vo2Max", it) }

                    if (includeGranularData && a.stepSamples.isNotEmpty()) {
                        putJsonArray("stepSamples") {
                            for (sample in a.stepSamples) {
                                addJsonObject {
                                    // T0-04: ISO 8601 timestamp
                                    put("timestamp", sample.time.toIso8601())
                                    put("value", sample.value.toInt())
                                }
                            }
                        }
                    }
                }
            }

            // ── Heart ──────────────────────────────────────────────────────────────────────────
            if (data.heart.hasData) {
                putJsonObject("heart") {
                    val h = data.heart
                    h.restingHeartRate?.let { put("restingHeartRate", it) }
                    h.averageHeartRate?.let { put("averageHeartRate", it) }
                    h.heartRateMin?.let { put("heartRateMin", it) }
                    h.heartRateMax?.let { put("heartRateMax", it) }
                    h.hrv?.let { put("hrv", it) }

                    if (includeGranularData && h.samples.isNotEmpty()) {
                        putJsonArray("heartRateSamples") {
                            for (sample in h.samples) {
                                addJsonObject {
                                    // T0-04: ISO 8601; T0-05: `value` (was `bpm`)
                                    put("timestamp", sample.time.toIso8601())
                                    put("value", sample.value.toInt())
                                }
                            }
                        }
                    }
                    if (includeGranularData && h.hrvSamples.isNotEmpty()) {
                        putJsonArray("hrvSamples") {
                            for (sample in h.hrvSamples) {
                                addJsonObject {
                                    // T0-04: ISO 8601; T0-06: `value` (was `ms`)
                                    put("timestamp", sample.time.toIso8601())
                                    put("value", sample.value)
                                }
                            }
                        }
                    }
                }
            }

            // ── Vitals ─────────────────────────────────────────────────────────────────────────
            if (data.vitals.hasData) {
                putJsonObject("vitals") {
                    val v = data.vitals

                    // Respiratory Rate
                    v.respiratoryRateAvg?.let {
                        put("respiratoryRateAvg", it)
                        // T1-05: backward-compat alias used by plugin summary-card.ts
                        put("respiratoryRate", it)
                    }
                    v.respiratoryRateMin?.let { put("respiratoryRateMin", it) }
                    v.respiratoryRateMax?.let { put("respiratoryRateMax", it) }

                    // Blood Oxygen / SpO2
                    v.bloodOxygenAvg?.let {
                        put("bloodOxygenAvg", it)
                        // T1-05: backward-compat alias
                        put("bloodOxygen", it)
                        put("bloodOxygenPercent", it * 100)
                    }
                    v.bloodOxygenMin?.let {
                        put("bloodOxygenMin", it)
                        put("bloodOxygenMinPercent", it * 100)
                    }
                    v.bloodOxygenMax?.let {
                        put("bloodOxygenMax", it)
                        put("bloodOxygenMaxPercent", it * 100)
                    }

                    // Body Temperature
                    v.bodyTemperatureAvg?.let {
                        put("bodyTemperatureAvg", it)
                        // T1-05: backward-compat alias
                        put("bodyTemperature", it)
                    }
                    v.bodyTemperatureMin?.let { put("bodyTemperatureMin", it) }
                    v.bodyTemperatureMax?.let { put("bodyTemperatureMax", it) }

                    // Blood Pressure
                    v.bloodPressureSystolicAvg?.let {
                        put("bloodPressureSystolicAvg", it)
                        // T1-05: backward-compat alias
                        put("bloodPressureSystolic", it)
                    }
                    v.bloodPressureSystolicMin?.let { put("bloodPressureSystolicMin", it) }
                    v.bloodPressureSystolicMax?.let { put("bloodPressureSystolicMax", it) }
                    v.bloodPressureDiastolicAvg?.let {
                        put("bloodPressureDiastolicAvg", it)
                        // T1-05: backward-compat alias
                        put("bloodPressureDiastolic", it)
                    }
                    v.bloodPressureDiastolicMin?.let { put("bloodPressureDiastolicMin", it) }
                    v.bloodPressureDiastolicMax?.let { put("bloodPressureDiastolicMax", it) }

                    // Blood Glucose
                    v.bloodGlucoseAvg?.let {
                        put("bloodGlucoseAvg", it)
                        // T1-05: backward-compat alias
                        put("bloodGlucose", it)
                    }
                    v.bloodGlucoseMin?.let { put("bloodGlucoseMin", it) }
                    v.bloodGlucoseMax?.let { put("bloodGlucoseMax", it) }

                    v.basalBodyTemperature?.let { put("basalBodyTemperature", it) }
                    v.skinTemperatureDelta?.let { put("skinTemperatureDelta", it) }

                    if (includeGranularData) {
                        if (v.bloodOxygenSamples.isNotEmpty()) {
                            putJsonArray("bloodOxygenSamples") {
                                for (sample in v.bloodOxygenSamples) {
                                    addJsonObject {
                                        // T0-04: ISO 8601; T0-07: `value` (was `percent`)
                                        put("timestamp", sample.time.toIso8601())
                                        put("value", sample.value)
                                    }
                                }
                            }
                        }
                        if (v.bloodPressureSamples.isNotEmpty()) {
                            putJsonArray("bloodPressureSamples") {
                                for (sample in v.bloodPressureSamples) {
                                    addJsonObject {
                                        put("timestamp", sample.time.toIso8601())
                                        put("systolic", sample.systolic)
                                        put("diastolic", sample.diastolic)
                                    }
                                }
                            }
                        }
                        if (v.bloodGlucoseSamples.isNotEmpty()) {
                            putJsonArray("bloodGlucoseSamples") {
                                for (sample in v.bloodGlucoseSamples) {
                                    addJsonObject {
                                        // T0-04: ISO 8601; T0-08: `value` (was `mgPerDl`)
                                        put("timestamp", sample.time.toIso8601())
                                        put("value", sample.value)
                                    }
                                }
                            }
                        }
                        if (v.respiratoryRateSamples.isNotEmpty()) {
                            putJsonArray("respiratoryRateSamples") {
                                for (sample in v.respiratoryRateSamples) {
                                    addJsonObject {
                                        // T0-04: ISO 8601; T0-09: `value` (was `breathsPerMin`)
                                        put("timestamp", sample.time.toIso8601())
                                        put("value", sample.value)
                                    }
                                }
                            }
                        }
                        if (v.bodyTemperatureSamples.isNotEmpty()) {
                            putJsonArray("bodyTemperatureSamples") {
                                for (sample in v.bodyTemperatureSamples) {
                                    addJsonObject {
                                        put("timestamp", sample.time.toIso8601())
                                        put("value", sample.value)
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── Body ───────────────────────────────────────────────────────────────────────────
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

            // ── Nutrition ──────────────────────────────────────────────────────────────────────
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

            // ── Mobility (Android extra + vo2Max kept here for backwards compat) ───────────────
            if (data.mobility.hasData) {
                putJsonObject("mobility") {
                    val m = data.mobility
                    m.walkingSpeed?.let { put("walkingSpeed", it) }
                    // Keep vo2Max here as Android extra (also emitted under activity per T0-10)
                    m.vo2Max?.let { put("vo2Max", it) }
                    m.cyclingCadenceAvg?.let { put("cyclingCadenceAvg", it) }
                    m.stepsCadenceAvg?.let { put("stepsCadenceAvg", it) }
                    m.powerAvg?.let { put("powerAvg", it) }
                    m.powerMax?.let { put("powerMax", it) }
                }
            }

            // ── Reproductive Health ────────────────────────────────────────────────────────────
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

            // ── Mindfulness ────────────────────────────────────────────────────────────────────
            if (data.mindfulness.hasData) {
                putJsonObject("mindfulness") {
                    // T1-03: renamed from `mindfulnessMinutes` to match iOS `mindfulMinutes`
                    data.mindfulness.mindfulnessMinutes?.let { put("mindfulMinutes", it) }
                }
            }

            // ── Workouts ───────────────────────────────────────────────────────────────────────
            if (data.workouts.isNotEmpty()) {
                putJsonArray("workouts") {
                    for (workout in data.workouts) {
                        addJsonObject {
                            put("type", workout.workoutType.displayName())
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
