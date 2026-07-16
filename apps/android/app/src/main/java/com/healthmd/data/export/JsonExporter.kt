package com.healthmd.data.export

import com.healthmd.domain.model.*
import kotlinx.serialization.json.*
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import kotlin.math.pow
import kotlin.math.round
import kotlin.math.roundToInt

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

    private fun Double.roundedTo(decimals: Int): Double {
        val scale = 10.0.pow(decimals)
        return round(this * scale) / scale
    }

    private fun NutritionData.hasVitaminData(): Boolean =
        vitaminA != null || vitaminB6 != null || vitaminB12 != null || vitaminC != null ||
            vitaminD != null || vitaminE != null || vitaminK != null || thiamin != null ||
            riboflavin != null || niacin != null || folate != null || biotin != null ||
            pantothenicAcid != null

    private fun NutritionData.hasMineralData(): Boolean =
        calcium != null || iron != null || potassium != null || magnesium != null ||
            phosphorus != null || zinc != null || selenium != null || copper != null ||
            manganese != null || chromium != null || molybdenum != null || chloride != null ||
            iodine != null

    private fun JsonObjectBuilder.putMetadataObject(name: String, metadata: Map<String, String>) {
        if (metadata.isEmpty()) return
        putJsonObject(name) {
            for ((key, value) in metadata.toSortedMap()) put(key, value)
        }
    }

    private fun JsonObjectBuilder.putExactTimestamp(name: String, timestamp: ExactSourceTimestamp?) {
        if (timestamp == null) return
        putJsonObject(name) {
            put("iso8601", timestamp.toIso8601())
            put("epochSecond", timestamp.epochSecond)
            put("nano", timestamp.nano)
            if (timestamp.offset != null) put("offset", timestamp.offset) else put("offset", JsonNull)
        }
    }

    private fun JsonObjectBuilder.putExactIdentity(identity: ExactSourceIdentity?) {
        if (identity == null) return
        putJsonObject("identity") {
            identity.nativeId?.let { put("nativeId", it) }
            identity.clientRecordId?.let { put("clientRecordId", it) }
            identity.clientRecordVersion?.let { put("clientRecordVersion", it) }
            identity.origin?.let { put("origin", it) }
            put("isSynthetic", identity.isSynthetic)
            identity.syntheticId?.let { put("syntheticId", it) }
            putExactTimestamp("lastModified", identity.lastModified)
        }
    }

    private fun JsonObjectBuilder.putExactInterval(
        start: ExactSourceTimestamp?,
        end: ExactSourceTimestamp?,
        identity: ExactSourceIdentity?,
    ) {
        putExactTimestamp("exactStartTime", start)
        putExactTimestamp("exactEndTime", end)
        putExactIdentity(identity)
    }

    private fun JsonObjectBuilder.putSampleContext(sample: TimestampedSample, includeExact: Boolean = false) {
        sample.source?.let { put("source", it) }
        if (sample.context.isNotEmpty()) {
            putJsonObject("context") {
                for ((key, value) in sample.context.toSortedMap()) put(key, value)
            }
        }
        putMetadataObject("metadata", sample.metadata)
        if (includeExact) {
            putExactTimestamp("exactTime", sample.exactTime)
            putExactTimestamp("exactEndTime", sample.exactEndTime)
            putExactIdentity(sample.identity)
        }
    }

    private fun JsonObjectBuilder.putWorkoutSamples(name: String, samples: List<TimestampedSample>, includeExact: Boolean) {
        if (samples.isEmpty()) return
        putJsonArray(name) {
            for (sample in samples) {
                addJsonObject {
                    put("timestamp", sample.time.toIso8601())
                    put("value", sample.value)
                    putSampleContext(sample, includeExact)
                }
            }
        }
    }

    fun export(
        data: HealthData,
        customization: FormatCustomization = FormatCustomization(),
        includeGranularData: Boolean = false,
    ): String {
        val dateString = customization.dateFormat.format(data.date)
        val converter = customization.unitConverter
        val includeLegacyAliases = customization.includeLegacyAndroidAliases
        val includeAndroidNativeFields = customization.includeAndroidNativeFields
        val analyticalV5 = customization.compatibilitySchemaProfile == CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5
        val emitAndroidNativeFields = includeAndroidNativeFields || analyticalV5

        val json = buildJsonObject {
            put("date", dateString)
            put("type", "health-data")
            put("units", customization.unitPreference.name.lowercase())
            if (analyticalV5) {
                put("schemaProfile", "android-analytical-v5")
                put("schemaVersion", 5)
            }
            data.compatibilityProvenance?.let { provenance ->
                putJsonObject("metadata") {
                    putJsonObject("provenance") {
                        put("mergePolicyId", provenance.mergePolicyId)
                        putJsonArray("providerIdsAttempted") { provenance.providerIdsAttempted.forEach(::add) }
                        putJsonArray("providerIdsSucceeded") { provenance.providerIdsSucceeded.forEach(::add) }
                        putJsonArray("providerFailures") {
                            provenance.providerFailures.forEach { failure ->
                                addJsonObject {
                                    put("providerId", failure.providerId)
                                    put("operation", failure.operation)
                                    put("errorType", failure.errorType)
                                    failure.message?.let { put("message", it) }
                                }
                            }
                        }
                        putJsonArray("categorySelections") {
                            provenance.categorySelections.forEach { selection ->
                                addJsonObject {
                                    put("category", selection.category)
                                    selection.chosenProviderId?.let { put("chosenProviderId", it) }
                                    putJsonArray("omittedOverlappingProviderIds") {
                                        selection.omittedOverlappingProviderIds.forEach(::add)
                                    }
                                }
                            }
                        }
                        putJsonArray("workoutDetailSources") {
                            provenance.workoutDetailSources.forEach { workout ->
                                addJsonObject {
                                    put("workoutId", workout.workoutId)
                                    putJsonObject("sourceIdsByDetail") {
                                        workout.sourceIdsByDetail.toSortedMap().forEach { (detail, ids) ->
                                            putJsonArray(detail) { ids.sorted().forEach(::add) }
                                        }
                                    }
                                }
                            }
                        }
                        putJsonArray("workoutSources") {
                            provenance.workoutSources.forEach { workout ->
                                addJsonObject {
                                    put("workoutId", workout.workoutId)
                                    put("providerId", workout.providerId)
                                    put("providerWorkoutId", workout.providerWorkoutId)
                                }
                            }
                        }
                        putJsonArray("workoutDedupeDecisions") {
                            provenance.workoutDedupeDecisions.forEach { decision ->
                                addJsonObject {
                                    put("keptProviderId", decision.keptProviderId)
                                    put("keptWorkoutId", decision.keptWorkoutId)
                                    put("omittedProviderId", decision.omittedProviderId)
                                    put("omittedWorkoutId", decision.omittedWorkoutId)
                                    put("reason", decision.reason)
                                }
                            }
                        }
                    }
                }
            }

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
                        if (includeLegacyAliases) {
                            put("lightSleep", it.inWholeSeconds.toDouble())
                            put("lightSleepFormatted", ExportHelpers.formatDuration(it))
                        }
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
                                    if (analyticalV5) putExactInterval(stage.exactStartTime, stage.exactEndTime, stage.identity)
                                }
                            }
                        }
                    }
                    if (includeGranularData && s.sessions.isNotEmpty()) {
                        putJsonArray("sleepSessions") {
                            for (session in s.sessions) {
                                addJsonObject {
                                    put("startTimeISO", session.startTime.toIso8601())
                                    put("endTimeISO", session.endTime.toIso8601())
                                    session.title?.let { put("title", it) }
                                    session.notes?.let { put("notes", it) }
                                    session.source?.let { put("source", it) }
                                    putMetadataObject("metadata", session.metadata)
                                    if (analyticalV5) putExactInterval(session.exactStartTime, session.exactEndTime, session.identity)
                                }
                            }
                        }
                    }
                }
            }

            // ── Activity ───────────────────────────────────────────────────────────────────────
            val activityHasIosKeys = with(data.activity) {
                steps != null || activeCalories != null || basalEnergyBurned != null ||
                    exerciseMinutes != null || flightsClimbed != null || walkingRunningDistance != null ||
                    cyclingDistance != null || wheelchairPushes != null || swimmingDistance != null ||
                    swimmingStrokes != null || wheelchairDistance != null ||
                    downhillSnowSportsDistance != null
            } || data.mobility.vo2Max != null ||
                (includeGranularData && data.mobility.vo2MaxMeasurementMethod != null) ||
                (includeGranularData && (data.activity.stepSamples.isNotEmpty() || data.activity.activityIntensityEntries.isNotEmpty()))
            if (activityHasIosKeys || (includeAndroidNativeFields && data.activity.hasData)) {
                putJsonObject("activity") {
                    val a = data.activity
                    a.steps?.let { put("steps", it) }
                    a.activeCalories?.let { put("activeCalories", it) }
                    if (includeAndroidNativeFields) a.totalCalories?.let { put("totalCalories", it) }
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
                    if (includeAndroidNativeFields) a.elevationGained?.let { put("elevationGained", it) }
                    // T1-04: pushCount (iOS canonical) + wheelchairPushes (Android extra)
                    a.wheelchairPushes?.let {
                        put("pushCount", it)
                        if (includeLegacyAliases) put("wheelchairPushes", it)
                    }
                    a.swimmingDistance?.let {
                        put("swimmingDistance", it)
                        if (includeLegacyAliases) put("swimmingDistanceKm", it / 1000)
                    }
                    a.swimmingStrokes?.let { put("swimmingStrokes", it) }
                    a.wheelchairDistance?.let {
                        if (includeLegacyAliases) put("wheelchairDistance", it)
                        put("wheelchairDistanceKm", it / 1000)
                    }
                    a.downhillSnowSportsDistance?.let {
                        if (includeLegacyAliases) put("downhillSnowSportsDistance", it)
                        put("downhillSnowSportsDistanceKm", it / 1000)
                    }
                    a.activityIntensityMinutes?.let { put("activityIntensityMinutes", it) }
                    a.moderateActivityMinutes?.let { put("moderateActivityMinutes", it) }
                    a.vigorousActivityMinutes?.let { put("vigorousActivityMinutes", it) }
                    // T0-10: vo2Max under activity (iOS canonical placement)
                    data.mobility.vo2Max?.let { put("vo2Max", it) }
                    if (includeGranularData) {
                        data.mobility.vo2MaxMeasurementMethod?.let { put("vo2MaxMeasurementMethod", it) }
                    }

                    if (includeGranularData && a.stepSamples.isNotEmpty()) {
                        putJsonArray("stepSamples") {
                            for (sample in a.stepSamples) {
                                addJsonObject {
                                    // T0-04: ISO 8601 timestamp
                                    put("timestamp", sample.time.toIso8601())
                                    put("value", sample.value.toInt())
                                    putSampleContext(sample, analyticalV5)
                                }
                            }
                        }
                    }
                    if (includeGranularData && a.activityIntensityEntries.isNotEmpty()) {
                        putJsonArray("activityIntensity") {
                            for (entry in a.activityIntensityEntries) {
                                addJsonObject {
                                    put("startTimeISO", entry.startTime.toIso8601())
                                    put("endTimeISO", entry.endTime.toIso8601())
                                    put("duration", entry.duration.inWholeSeconds)
                                    put("intensity", entry.intensity)
                                    entry.source?.let { put("source", it) }
                                    putMetadataObject("metadata", entry.metadata)
                                    if (analyticalV5) putExactInterval(entry.exactStartTime, entry.exactEndTime, entry.identity)
                                }
                            }
                        }
                    }
                }
            }

            // ── Cycling Performance (iOS canonical category for Android-backed cycling data) ──
            if (data.activity.cyclingDistance != null ||
                data.mobility.cyclingCadenceAvg != null ||
                data.mobility.powerAvg != null
            ) {
                putJsonObject("cyclingPerformance") {
                    data.activity.cyclingDistance?.let { put("cycling_km", (it / 1000).roundedTo(2)) }
                    data.mobility.cyclingCadenceAvg?.let { put("cycling_cadence_rpm", it.roundedTo(0)) }
                    data.mobility.powerAvg?.let { put("cycling_power_w", it.roundedTo(0)) }
                }
            }

            // ── Heart ──────────────────────────────────────────────────────────────────────────
            val heartHasSummary = with(data.heart) {
                restingHeartRate != null || averageHeartRate != null || walkingHeartRateAverage != null ||
                    hrv != null || heartRateMin != null || heartRateMax != null
            }
            if (heartHasSummary || (includeGranularData && (data.heart.samples.isNotEmpty() || data.heart.hrvSamples.isNotEmpty()))) {
                putJsonObject("heart") {
                    val h = data.heart
                    h.restingHeartRate?.let { put("restingHeartRate", it) }
                    h.averageHeartRate?.let { put("averageHeartRate", it) }
                    h.walkingHeartRateAverage?.let { put("walkingHeartRateAverage", it) }
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
                                    putSampleContext(sample, analyticalV5)
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
                                    putSampleContext(sample, analyticalV5)
                                }
                            }
                        }
                    }
                }
            }

            // ── Vitals ─────────────────────────────────────────────────────────────────────────
            val vitalsHasSummary = with(data.vitals) {
                respiratoryRateAvg != null || respiratoryRateMin != null || respiratoryRateMax != null ||
                    bloodOxygenAvg != null || bloodOxygenMin != null || bloodOxygenMax != null ||
                    bodyTemperatureAvg != null || bodyTemperatureMin != null || bodyTemperatureMax != null ||
                    bloodPressureSystolicAvg != null || bloodPressureSystolicMin != null || bloodPressureSystolicMax != null ||
                    bloodPressureDiastolicAvg != null || bloodPressureDiastolicMin != null || bloodPressureDiastolicMax != null ||
                    bloodGlucoseAvg != null || bloodGlucoseMin != null || bloodGlucoseMax != null ||
                    basalBodyTemperature != null || (emitAndroidNativeFields && (skinTemperatureDelta != null || skinTemperatureBaseline != null))
            }
            val vitalsHasSamples = with(data.vitals) {
                bloodOxygenSamples.isNotEmpty() || bloodPressureSamples.isNotEmpty() ||
                    bloodGlucoseSamples.isNotEmpty() || respiratoryRateSamples.isNotEmpty() ||
                    bodyTemperatureSamples.isNotEmpty() || basalBodyTemperatureSamples.isNotEmpty() ||
                    (emitAndroidNativeFields && skinTemperatureDeltas.isNotEmpty())
            }
            if (vitalsHasSummary || (includeGranularData && vitalsHasSamples)) {
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
                    if (emitAndroidNativeFields) {
                        v.skinTemperatureDelta?.let { put("skinTemperatureDelta", it) }
                        v.skinTemperatureBaseline?.let { put("skinTemperatureBaseline", it) }
                    }

                    if (includeGranularData) {
                        fun JsonObjectBuilder.putTimestampedSamples(name: String, samples: List<TimestampedSample>) {
                            if (samples.isEmpty()) return
                            putJsonArray(name) {
                                for (sample in samples) {
                                    addJsonObject {
                                        put("timestamp", sample.time.toIso8601())
                                        put("value", sample.value)
                                        putSampleContext(sample, analyticalV5)
                                    }
                                }
                            }
                        }

                        putTimestampedSamples("bloodOxygenSamples", v.bloodOxygenSamples)
                        if (v.bloodPressureSamples.isNotEmpty()) {
                            putJsonArray("bloodPressureSamples") {
                                for (sample in v.bloodPressureSamples) {
                                    addJsonObject {
                                        put("timestamp", sample.time.toIso8601())
                                        put("systolic", sample.systolic)
                                        put("diastolic", sample.diastolic)
                                        sample.measurementLocation?.let { put("measurementLocation", it) }
                                        sample.bodyPosition?.let { put("bodyPosition", it) }
                                        sample.source?.let { put("source", it) }
                                        putMetadataObject("metadata", sample.metadata)
                                        if (analyticalV5) {
                                            putExactTimestamp("exactTime", sample.exactTime)
                                            putExactIdentity(sample.identity)
                                        }
                                    }
                                }
                            }
                        }
                        putTimestampedSamples("bloodGlucoseSamples", v.bloodGlucoseSamples)
                        putTimestampedSamples("respiratoryRateSamples", v.respiratoryRateSamples)
                        putTimestampedSamples("bodyTemperatureSamples", v.bodyTemperatureSamples)
                        putTimestampedSamples("basalBodyTemperatureSamples", v.basalBodyTemperatureSamples)
                        if (emitAndroidNativeFields) {
                            putTimestampedSamples("skinTemperatureDeltas", v.skinTemperatureDeltas)
                        }
                    }
                }
            }

            // ── Body ───────────────────────────────────────────────────────────────────────────
            val bodyHasIosKeys = with(data.body) {
                weight != null || height != null || bmi != null || bodyFatPercentage != null || leanBodyMass != null
            }
            if (bodyHasIosKeys || (includeAndroidNativeFields && data.body.hasData)) {
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
                    if (includeAndroidNativeFields) {
                        b.bodyWaterMass?.let { put("bodyWaterMass", it) }
                        b.boneMass?.let { put("boneMass", it) }
                    }
                }
            }

            // ── Nutrition ──────────────────────────────────────────────────────────────────────
            val nutritionHasIosKeys = with(data.nutrition) {
                dietaryEnergy != null || protein != null || carbohydrates != null || fat != null ||
                    saturatedFat != null || monounsaturatedFat != null || polyunsaturatedFat != null ||
                    fiber != null || sugar != null || sodium != null || cholesterol != null ||
                    water != null || caffeine != null
            }
            if (nutritionHasIosKeys || (includeGranularData && data.nutrition.meals.isNotEmpty()) ||
                (includeAndroidNativeFields && data.nutrition.hasData)
            ) {
                putJsonObject("nutrition") {
                    val n = data.nutrition
                    n.dietaryEnergy?.let { put("dietaryEnergy", it) }
                    n.energyFromFat?.let { put("energyFromFat", it) }
                    n.protein?.let { put("protein", it) }
                    n.carbohydrates?.let { put("carbohydrates", it) }
                    n.fat?.let { put("fat", it) }
                    n.saturatedFat?.let { put("saturatedFat", it) }
                    n.monounsaturatedFat?.let { put("monounsaturatedFat", it) }
                    n.polyunsaturatedFat?.let { put("polyunsaturatedFat", it) }
                    if (includeAndroidNativeFields) {
                        n.unsaturatedFat?.let { put("unsaturatedFat", it) }
                        n.transFat?.let { put("transFat", it) }
                    }
                    n.fiber?.let { put("fiber", it) }
                    n.sugar?.let { put("sugar", it) }
                    n.sodium?.let { put("sodium", it) }
                    if (includeAndroidNativeFields) {
                        n.potassium?.let { put("potassium", it) }
                        n.calcium?.let { put("calcium", it) }
                        n.iron?.let { put("iron", it) }
                        n.magnesium?.let { put("magnesium", it) }
                        n.zinc?.let { put("zinc", it) }
                        n.phosphorus?.let { put("phosphorus", it) }
                        n.iodine?.let { put("iodine", it) }
                        n.selenium?.let { put("selenium", it) }
                        n.copper?.let { put("copper", it) }
                        n.manganese?.let { put("manganese", it) }
                        n.chromium?.let { put("chromium", it) }
                        n.molybdenum?.let { put("molybdenum", it) }
                        n.chloride?.let { put("chloride", it) }
                        n.vitaminA?.let { put("vitaminA", it) }
                        n.vitaminB6?.let { put("vitaminB6", it) }
                        n.vitaminB12?.let { put("vitaminB12", it) }
                        n.vitaminC?.let { put("vitaminC", it) }
                        n.vitaminD?.let { put("vitaminD", it) }
                        n.vitaminE?.let { put("vitaminE", it) }
                        n.vitaminK?.let { put("vitaminK", it) }
                        n.thiamin?.let { put("thiamin", it) }
                        n.riboflavin?.let { put("riboflavin", it) }
                        n.niacin?.let { put("niacin", it) }
                        n.folate?.let { put("folate", it) }
                        n.folicAcid?.let { put("folicAcid", it) }
                        n.pantothenicAcid?.let { put("pantothenicAcid", it) }
                        n.biotin?.let { put("biotin", it) }
                    }
                    n.cholesterol?.let { put("cholesterol", it) }
                    n.water?.let { put("water", it) }
                    n.caffeine?.let { put("caffeine", it) }
                    if (includeGranularData && n.meals.isNotEmpty()) {
                        putJsonArray("meals") {
                            for (meal in n.meals) {
                                addJsonObject {
                                    put("startTimeISO", meal.startTime.toIso8601())
                                    put("endTimeISO", meal.endTime.toIso8601())
                                    meal.name?.let { put("name", it) }
                                    meal.mealType?.let { put("mealType", it) }
                                    meal.dietaryEnergy?.let { put("dietaryEnergy", it) }
                                    meal.energyFromFat?.let { put("energyFromFat", it) }
                                    meal.protein?.let { put("protein", it) }
                                    meal.carbohydrates?.let { put("carbohydrates", it) }
                                    meal.fat?.let { put("fat", it) }
                                    meal.source?.let { put("source", it) }
                                    putMetadataObject("metadata", meal.metadata)
                                    if (analyticalV5) putExactInterval(meal.exactStartTime, meal.exactEndTime, meal.identity)
                                }
                            }
                        }
                    }
                }
            }

            // ── Vitamins / Minerals (iOS canonical top-level categories) ──────────────────────
            if (data.nutrition.hasVitaminData()) {
                putJsonObject("vitamins") {
                    val n = data.nutrition
                    n.vitaminA?.let { put("vitamin_a_ug", it.roundedTo(1)) }
                    n.vitaminB6?.let { put("vitamin_b6_mg", it.roundedTo(2)) }
                    n.vitaminB12?.let { put("vitamin_b12_ug", it.roundedTo(2)) }
                    n.vitaminC?.let { put("vitamin_c_mg", it.roundedTo(1)) }
                    n.vitaminD?.let { put("vitamin_d_ug", it.roundedTo(1)) }
                    n.vitaminE?.let { put("vitamin_e_mg", it.roundedTo(2)) }
                    n.vitaminK?.let { put("vitamin_k_ug", it.roundedTo(1)) }
                    n.thiamin?.let { put("thiamin_mg", it.roundedTo(2)) }
                    n.riboflavin?.let { put("riboflavin_mg", it.roundedTo(2)) }
                    n.niacin?.let { put("niacin_mg", it.roundedTo(1)) }
                    n.folate?.let { put("folate_ug", it.roundedTo(1)) }
                    n.biotin?.let { put("biotin_ug", it.roundedTo(1)) }
                    n.pantothenicAcid?.let { put("pantothenic_acid_mg", it.roundedTo(2)) }
                }
            }

            if (data.nutrition.hasMineralData()) {
                putJsonObject("minerals") {
                    val n = data.nutrition
                    n.calcium?.let { put("calcium_mg", it.roundedTo(1)) }
                    n.iron?.let { put("iron_mg", it.roundedTo(2)) }
                    n.potassium?.let { put("potassium_mg", it.roundedTo(1)) }
                    n.magnesium?.let { put("magnesium_mg", it.roundedTo(1)) }
                    n.phosphorus?.let { put("phosphorus_mg", it.roundedTo(1)) }
                    n.zinc?.let { put("zinc_mg", it.roundedTo(2)) }
                    n.selenium?.let { put("selenium_ug", it.roundedTo(1)) }
                    n.copper?.let { put("copper_mg", it.roundedTo(3)) }
                    n.manganese?.let { put("manganese_mg", it.roundedTo(2)) }
                    n.chromium?.let { put("chromium_ug", it.roundedTo(1)) }
                    n.molybdenum?.let { put("molybdenum_ug", it.roundedTo(1)) }
                    n.chloride?.let { put("chloride_mg", it.roundedTo(1)) }
                    n.iodine?.let { put("iodine_ug", it.roundedTo(1)) }
                }
            }

            // ── Mobility ──────────────────────────────────────────────────────────────────────
            val mobilityHasIosKeys = data.mobility.walkingSpeed != null ||
                data.mobility.runningSpeed != null ||
                data.mobility.runningPowerAvg != null ||
                (includeGranularData && data.mobility.vo2MaxMeasurementMethod != null)
            if (mobilityHasIosKeys || ((includeLegacyAliases || includeAndroidNativeFields) && data.mobility.hasData)) {
                putJsonObject("mobility") {
                    val m = data.mobility
                    m.walkingSpeed?.let { put("walkingSpeed", it) }
                    if (includeLegacyAliases) {
                        m.vo2Max?.let { put("vo2Max", it) }
                        m.cyclingCadenceAvg?.let { put("cyclingCadenceAvg", it) }
                        m.powerAvg?.let { put("powerAvg", it) }
                    }
                    if (includeAndroidNativeFields) {
                        m.cyclingCadenceMax?.let { put("cyclingCadenceMax", it) }
                        m.stepsCadenceAvg?.let { put("stepsCadenceAvg", it) }
                        m.stepsCadenceMax?.let { put("stepsCadenceMax", it) }
                        m.powerMax?.let { put("powerMax", it) }
                    }
                    m.runningSpeed?.let { put("runningSpeed", it) }
                    m.runningPowerAvg?.let {
                        put("runningPowerW", it) // iOS canonical key
                        if (includeLegacyAliases) put("runningPowerAvg", it)
                    }
                    if (includeAndroidNativeFields) m.runningPowerMax?.let { put("runningPowerMax", it) }
                    if (includeGranularData) {
                        m.vo2MaxMeasurementMethod?.let { put("vo2MaxMeasurementMethod", it) }
                    }
                }
            }

            // ── Reproductive Health ────────────────────────────────────────────────────────────
            if (data.reproductiveHealth.hasData) {
                putJsonObject("reproductiveHealth") {
                    val r = data.reproductiveHealth
                    r.menstrualFlow?.let {
                        put("menstrual_flow", it) // iOS canonical key
                        if (includeLegacyAliases) put("menstrualFlow", it) // Android legacy key
                    }
                    (r.cervicalMucusAppearance ?: r.cervicalMucusSensation)?.let {
                        put("cervical_mucus", it) // iOS canonical key
                    }
                    if (includeAndroidNativeFields) {
                        r.cervicalMucusAppearance?.let { put("cervicalMucusAppearance", it) }
                        r.cervicalMucusSensation?.let { put("cervicalMucusSensation", it) }
                    }
                    r.ovulationTestResult?.let {
                        put("ovulation_test", it) // iOS canonical key
                        if (includeLegacyAliases) put("ovulationTestResult", it) // Android legacy key
                    }
                    if (r.intermenstrualBleeding) {
                        put("intermenstrual_bleeding", true) // iOS canonical key (boolean on Android)
                        if (includeLegacyAliases) put("intermenstrualBleeding", true)
                    }
                    if (r.sexualActivityRecorded) {
                        put("sexual_activity", true) // iOS canonical key (boolean on Android)
                        if (includeLegacyAliases) put("sexualActivity", true)
                        if (includeAndroidNativeFields) r.sexualActivityProtectionUsed?.let { put("protectionUsed", it) }
                    }
                    r.menstruationPeriodCount?.let { put("menstruationPeriodCount", it) }
                    r.menstruationPeriodDuration.takeIf { it > kotlin.time.Duration.ZERO }?.let {
                        put("menstruationPeriodDuration", it.inWholeSeconds)
                        put("menstruationPeriodDays", it.inWholeHours / 24.0)
                    }
                    if (includeGranularData && r.menstruationPeriods.isNotEmpty()) {
                        putJsonArray("menstruationPeriods") {
                            for (period in r.menstruationPeriods) {
                                addJsonObject {
                                    put("startTimeISO", period.startTime.toIso8601())
                                    put("endTimeISO", period.endTime.toIso8601())
                                    put("duration", period.duration.inWholeSeconds)
                                    period.source?.let { put("source", it) }
                                    putMetadataObject("metadata", period.metadata)
                                    if (analyticalV5) putExactInterval(period.exactStartTime, period.exactEndTime, period.identity)
                                }
                            }
                        }
                    }
                }
            }

            // ── Mindfulness ────────────────────────────────────────────────────────────────────
            if (data.mindfulness.hasData) {
                putJsonObject("mindfulness") {
                    // T1-03: renamed from `mindfulnessMinutes` to match iOS `mindfulMinutes`
                    data.mindfulness.mindfulnessMinutes?.let { put("mindfulMinutes", it) }
                    data.mindfulness.mindfulSessions?.let { put("mindfulSessions", it) }
                    if (includeGranularData && data.mindfulness.sessions.isNotEmpty()) {
                        putJsonArray("sessions") {
                            for (session in data.mindfulness.sessions) {
                                addJsonObject {
                                    put("startTimeISO", session.startTime.toIso8601())
                                    put("endTimeISO", session.endTime.toIso8601())
                                    session.sessionType?.let { put("sessionType", it) }
                                    session.title?.let { put("title", it) }
                                    session.notes?.let { put("notes", it) }
                                    session.source?.let { put("source", it) }
                                    putMetadataObject("metadata", session.metadata)
                                    if (analyticalV5) putExactInterval(session.exactStartTime, session.exactEndTime, session.identity)
                                }
                            }
                        }
                    }
                }
            }

            // ── Planned Workouts ───────────────────────────────────────────────────────────────
            if (data.plannedWorkouts.isNotEmpty()) {
                putJsonArray("plannedWorkouts") {
                    for (plan in data.plannedWorkouts) {
                        addJsonObject {
                            put("type", plan.workoutType.displayName())
                            put("startTimeISO", plan.startTime.toIso8601())
                            put("endTimeISO", plan.endTime.toIso8601())
                            put("duration", plan.duration.inWholeSeconds)
                            put("hasExplicitTime", plan.hasExplicitTime)
                            put("exerciseTypeRaw", plan.exerciseTypeRaw)
                            plan.completedExerciseSessionId?.let { put("completedExerciseSessionId", it) }
                            plan.title?.let { put("title", it) }
                            plan.notes?.let { put("notes", it) }
                            put("blockCount", plan.blockCount)
                            put("stepCount", plan.stepCount)
                            if (plan.blockDescriptions.isNotEmpty()) putJsonArray("blockDescriptions") { plan.blockDescriptions.forEach { add(it) } }
                            putMetadataObject("metadata", plan.metadata)
                            if (analyticalV5 && includeGranularData) putExactInterval(plan.exactStartTime, plan.exactEndTime, plan.identity)
                        }
                    }
                }
            }

            // ── Personal Health Record / FHIR ─────────────────────────────────────────────────
            if (data.medicalResources.hasData) {
                putJsonObject("medicalResources") {
                    put("count", data.medicalResources.resources.size)
                    putJsonObject("countsByType") {
                        for ((type, count) in data.medicalResources.countsByType.toSortedMap()) put(type, count)
                    }
                    putJsonArray("resources") {
                        for (resource in data.medicalResources.resources) {
                            addJsonObject {
                                put("type", resource.type)
                                put("typeRaw", resource.typeRaw)
                                put("dataSourceId", resource.dataSourceId)
                                put("medicalResourceId", resource.medicalResourceId)
                                put("fhirVersion", resource.fhirVersion)
                                put("fhirResourceType", resource.fhirResourceType)
                                put("fhirResourceTypeRaw", resource.fhirResourceTypeRaw)
                                put("fhirResourceId", resource.fhirResourceId)
                                put("fhirResourceJson", resource.fhirResourceJson)
                            }
                        }
                    }
                }
            }

            // ── Workouts ───────────────────────────────────────────────────────────────────────
            if (data.workouts.isNotEmpty()) {
                putJsonArray("workouts") {
                    for (workout in data.workouts) {
                        addJsonObject {
                            put("type", workout.workoutType.displayName())
                            put("startTime", customization.timeFormat.format(workout.startTime))
                            put("startTimeISO", workout.startTime.toIso8601())
                            workout.endTime?.let {
                                if (includeLegacyAliases) put("endTime", customization.timeFormat.format(it))
                                put("endTimeISO", it.toIso8601())
                            }
                            workout.isIndoor?.let {
                                put("isIndoor", it)
                                put("locationType", if (it) "indoor" else "outdoor")
                            }
                            if (workout.isIndoor == null && workout.route.isNotEmpty()) {
                                put("locationType", "outdoor")
                            }
                            if (workout.endTime == null) {
                                put("endTimeISO", workout.startTime.plusSeconds(workout.duration.inWholeSeconds).toIso8601())
                            }
                            if (workout.metadata.isNotEmpty()) {
                                putJsonObject("metadata") {
                                    for ((key, value) in workout.metadata.toSortedMap()) {
                                        put(key, value)
                                    }
                                }
                            }
                            if (analyticalV5 && includeGranularData) {
                                putExactInterval(workout.exactStartTime, workout.exactEndTime, workout.identity)
                                if (workout.correlatedSourceIds.isNotEmpty()) {
                                    putJsonObject("correlatedSourceIds") {
                                        workout.correlatedSourceIds.toSortedMap().forEach { (kind, ids) ->
                                            putJsonArray(kind) { ids.sorted().forEach(::add) }
                                        }
                                    }
                                }
                            }
                            if (includeAndroidNativeFields) {
                                put("routeAccess", workout.routeAccess.name.lowercase())
                                if (workout.route.isNotEmpty()) put("routePointCount", workout.route.size)
                            }
                            workout.metadata["title"]?.let { put("title", it) }
                            workout.metadata["notes"]?.let { put("notes", it) }
                            put("duration", workout.duration.inWholeSeconds.toDouble())
                            put("durationFormatted", ExportHelpers.formatDurationShort(workout.duration))
                            workout.distance?.takeIf { it > 0 }?.let {
                                put("distance", it)
                                put("distanceFormatted", converter.formatDistance(it))
                            }
                            workout.calories?.takeIf { it > 0 }?.let {
                                put("calories", it)
                            }
                            workout.elevationGained?.takeIf { it > 0 }?.let {
                                if (includeLegacyAliases) put("elevationGained", it)
                                put("elevationGainMeters", it) // iOS canonical key
                            }
                            workout.elevationLoss?.takeIf { it > 0 }?.let {
                                if (includeLegacyAliases) put("elevationLoss", it)
                                put("elevationLossMeters", it) // iOS canonical key
                            }
                            workout.averageHeartRate?.let {
                                if (includeLegacyAliases) put("averageHeartRate", it)
                                put("avgHeartRate", it.roundToInt()) // iOS canonical key
                            }
                            workout.heartRateMin?.let {
                                if (includeLegacyAliases) put("heartRateMin", it)
                                put("minHeartRate", it.roundToInt()) // iOS canonical key
                            }
                            workout.heartRateMax?.let {
                                if (includeLegacyAliases) put("heartRateMax", it)
                                put("maxHeartRate", it.roundToInt()) // iOS canonical key
                            }
                            if (includeAndroidNativeFields) {
                                workout.averageSpeed?.let {
                                    put("averageSpeed", it)
                                    put("averagePaceSecondsPerKm", workout.averagePaceSecondsPerKm ?: (1000.0 / it))
                                }
                                workout.maxSpeed?.let { put("maxSpeed", it) }
                            }
                            workout.cyclingCadenceAvg?.let {
                                if (includeLegacyAliases) put("cyclingCadenceAvg", it)
                                put("avgCyclingCadence", it.roundToInt()) // iOS canonical key
                            }
                            if (includeAndroidNativeFields) workout.cyclingCadenceMax?.let { put("maxCyclingCadence", it.roundToInt()) }
                            workout.stepsCadenceAvg?.let {
                                if (includeLegacyAliases) put("stepsCadenceAvg", it)
                                if (workout.workoutType == WorkoutType.RUNNING) {
                                    put("avgRunningCadence", it.roundToInt()) // iOS canonical key
                                }
                            }
                            if (includeAndroidNativeFields) workout.stepsCadenceMax?.let { put("maxStepsCadence", it.roundToInt()) }
                            workout.powerAvg?.let {
                                if (includeLegacyAliases) put("powerAvg", it)
                                put("avgPower", it.roundToInt()) // iOS canonical key
                            }
                            workout.powerMax?.let {
                                if (includeLegacyAliases) put("powerMax", it)
                                put("maxPower", it.roundToInt()) // iOS canonical key
                            }
                            if (workout.laps.isNotEmpty()) {
                                putJsonArray("laps") {
                                    for ((index, lap) in workout.laps.withIndex()) {
                                        addJsonObject {
                                            put("index", index + 1)
                                            if (includeLegacyAliases) put("startTime", lap.startTime.toIso8601())
                                            put("startTimeISO", lap.startTime.toIso8601())
                                            if (includeLegacyAliases) put("endTime", lap.endTime.toIso8601())
                                            put("endTimeISO", lap.endTime.toIso8601())
                                            val durationSeconds = java.time.Duration.between(lap.startTime, lap.endTime).seconds.toDouble()
                                            if (includeLegacyAliases) put("durationSeconds", durationSeconds)
                                            put("duration", durationSeconds)
                                            lap.length?.let {
                                                if (includeLegacyAliases) put("length", it)
                                                put("distance", it)
                                            }
                                            if (analyticalV5 && includeGranularData) putExactInterval(lap.exactStartTime, lap.exactEndTime, lap.identity)
                                        }
                                    }
                                }
                            }
                            if (workout.splits.isNotEmpty()) {
                                putJsonArray("splits") {
                                    for (split in workout.splits) {
                                        addJsonObject {
                                            put("index", split.index)
                                            if (includeLegacyAliases) put("startTime", split.startTime.toIso8601())
                                            put("startTimeISO", split.startTime.toIso8601())
                                            if (includeLegacyAliases) put("endTime", split.endTime.toIso8601())
                                            put("endTimeISO", split.endTime.toIso8601())
                                            put("duration", split.duration.inWholeSeconds.toDouble())
                                            split.distance?.let { put("distance", it) }
                                            split.averageHeartRate?.let {
                                                if (includeLegacyAliases) put("averageHeartRate", it)
                                                put("avgHeartRate", it.roundToInt())
                                            }
                                            if (analyticalV5 && includeGranularData) putExactInterval(split.exactStartTime, split.exactEndTime, split.identity)
                                        }
                                    }
                                }
                            }
                            if (workout.segments.isNotEmpty()) {
                                putJsonArray("segments") {
                                    for (segment in workout.segments) {
                                        addJsonObject {
                                            put("startTime", segment.startTime.toIso8601())
                                            put("endTime", segment.endTime.toIso8601())
                                            put(
                                                "durationSeconds",
                                                java.time.Duration.between(segment.startTime, segment.endTime).seconds.toDouble(),
                                            )
                                            put("type", segment.type)
                                            segment.repetitions?.let { put("repetitions", it) }
                                            if (analyticalV5 && includeGranularData) putExactInterval(segment.exactStartTime, segment.exactEndTime, segment.identity)
                                        }
                                    }
                                }
                            }
                            if (includeGranularData && workout.route.isNotEmpty()) {
                                putJsonArray("route") {
                                    for (point in workout.route) {
                                        addJsonObject {
                                            put("timestamp", point.time.toIso8601())
                                            put("latitude", point.latitude)
                                            put("longitude", point.longitude)
                                            point.altitude?.let { put("altitude", it) }
                                            point.horizontalAccuracy?.let { put("horizontalAccuracy", it) }
                                            point.verticalAccuracy?.let { put("verticalAccuracy", it) }
                                            if (analyticalV5) {
                                                putExactTimestamp("exactTime", point.exactTime)
                                                putExactIdentity(point.identity)
                                            }
                                        }
                                    }
                                }
                            }
                            if (includeGranularData) {
                                val legacyCadenceSamples = (workout.cyclingCadenceSamples + workout.stepsCadenceSamples)
                                    .sortedBy { it.time }
                                val hasCadenceSeries = if (analyticalV5) {
                                    workout.cyclingCadenceSamples.isNotEmpty() || workout.stepsCadenceSamples.isNotEmpty()
                                } else legacyCadenceSamples.isNotEmpty()
                                val hasTimeSeries = workout.heartRateSamples.isNotEmpty() ||
                                    workout.speedSamples.isNotEmpty() ||
                                    workout.powerSamples.isNotEmpty() ||
                                    hasCadenceSeries || workout.elevationSamples.isNotEmpty()
                                if (hasTimeSeries) {
                                    putJsonObject("timeSeries") {
                                        putWorkoutSamples("heartRate", workout.heartRateSamples, analyticalV5)
                                        putWorkoutSamples("speed", workout.speedSamples, analyticalV5)
                                        putWorkoutSamples("power", workout.powerSamples, analyticalV5)
                                        if (analyticalV5) {
                                            putWorkoutSamples("cyclingCadence", workout.cyclingCadenceSamples, includeExact = true)
                                            putWorkoutSamples("stepsCadence", workout.stepsCadenceSamples, includeExact = true)
                                        } else {
                                            // Frozen v4 retains its historical ambiguous alias byte shape.
                                            putWorkoutSamples("cadence", legacyCadenceSamples, includeExact = false)
                                        }
                                        putWorkoutSamples("altitude", workout.elevationSamples, analyticalV5)
                                    }
                                }

                                if (includeLegacyAliases) {
                                    putWorkoutSamples("heartRateSamples", workout.heartRateSamples, analyticalV5)
                                    putWorkoutSamples("speedSamples", workout.speedSamples, analyticalV5)
                                    putWorkoutSamples("cyclingCadenceSamples", workout.cyclingCadenceSamples, analyticalV5)
                                    putWorkoutSamples("stepsCadenceSamples", workout.stepsCadenceSamples, analyticalV5)
                                    putWorkoutSamples("powerSamples", workout.powerSamples, analyticalV5)
                                    putWorkoutSamples("elevationSamples", workout.elevationSamples, analyticalV5)
                                }
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
