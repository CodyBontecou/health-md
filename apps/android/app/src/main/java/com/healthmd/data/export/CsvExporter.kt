package com.healthmd.data.export

import com.healthmd.domain.model.*
import java.time.LocalDateTime
import java.time.format.DateTimeFormatter
import kotlin.math.roundToInt

/**
 * Produces CSV health data exports compatible with the iOS Health.md CSV contract.
 *
 * Schema contract: docs/export-contract/ios-export-contract.md (§3)
 * Gap matrix fixes: docs/export-contract/android-ios-gap-matrix.md (§4 Tier-0/1)
 *
 *   T0-11  All granular sample Timestamp column: TimeFormatPreference → ISO 8601
 *   T1-08  Header always 6 columns: `Date,Category,Metric,Value,Unit,Timestamp`
 *          (aggregate rows emit empty Timestamp column)
 *   T1-09  Sleep stage label: `Core Sleep` (iOS canonical, = Light Sleep value)
 *          `Light Sleep` kept as second row (Android extra)
 *   T1-10  Activity `Flights Climbed` (was `Floors Climbed`)
 *   T1-11  VO2 Max row added under `Activity,Cardio Fitness (VO2 Max)` (iOS canonical)
 *          Original `Mobility,VO2 Max` row kept as Android extra
 *   T1-12  Heart `HRV` label (was `HRV (RMSSD)`)
 *   T1-13  Vitals `Blood Oxygen Sample` label (was `SpO2 Sample`)
 *   SLEEP  Sleep Stage row aligned to iOS format: metric=`Sleep Stage`,
 *          value=`<stage> (<dur>s)`, unit=`seconds`, Timestamp=ISO 8601 start
 */
class CsvExporter {

    private val isoFormatter: DateTimeFormatter = DateTimeFormatter.ISO_LOCAL_DATE_TIME

    private fun LocalDateTime.toIso8601(): String = format(isoFormatter)

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

    /** Emit one CSV row. Aggregate rows pass an empty [timestamp]. */
    private fun row(
        date: String,
        category: String,
        metric: String,
        value: Any,
        unit: String,
        timestamp: String = "",
    ): String = "$date,$category,$metric,$value,$unit,$timestamp\n"

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
        val includeAndroidKeys = customization.includeAndroidCompatibilityKeys

        return buildString {
            // T1-08: always 6 columns
            append("Date,Category,Metric,Value,Unit,Timestamp\n")

            // ── Sleep ─────────────────────────────────────────────────────────────────────────
            if (data.sleep.hasData) {
                val s = data.sleep
                s.totalDuration.takeIf { it > kotlin.time.Duration.ZERO }
                    ?.let { append(row(dateString, "Sleep", "Total Duration", it.inWholeSeconds, "seconds")) }
                s.deepSleep.takeIf { it > kotlin.time.Duration.ZERO }
                    ?.let { append(row(dateString, "Sleep", "Deep Sleep", it.inWholeSeconds, "seconds")) }
                s.remSleep.takeIf { it > kotlin.time.Duration.ZERO }
                    ?.let { append(row(dateString, "Sleep", "REM Sleep", it.inWholeSeconds, "seconds")) }
                // T1-09: emit Core Sleep (iOS canonical) = lightSleep value
                s.lightSleep.takeIf { it > kotlin.time.Duration.ZERO }?.let {
                    append(row(dateString, "Sleep", "Core Sleep", it.inWholeSeconds, "seconds"))
                    if (includeAndroidKeys) {
                        append(row(dateString, "Sleep", "Light Sleep", it.inWholeSeconds, "seconds"))
                    }
                }
                s.awakeTime.takeIf { it > kotlin.time.Duration.ZERO }
                    ?.let { append(row(dateString, "Sleep", "Awake Time", it.inWholeSeconds, "seconds")) }
                s.inBedTime.takeIf { it > kotlin.time.Duration.ZERO }
                    ?.let { append(row(dateString, "Sleep", "In Bed Time", it.inWholeSeconds, "seconds")) }

                // Bedtime / wake from sessionStart/End or stage boundaries
                val bedtime = s.sessionStart ?: s.stages.minByOrNull { it.startTime }?.startTime
                val wakeTime = s.sessionEnd ?: s.stages.maxByOrNull { it.endTime }?.endTime
                bedtime?.let { append(row(dateString, "Sleep", "Bedtime", customization.timeFormat.format(it), "time")) }
                wakeTime?.let { append(row(dateString, "Sleep", "Wake Time", customization.timeFormat.format(it), "time")) }

                if (includeGranularData) {
                    for (stage in s.stages) {
                        // T0-11 + SLEEP: iOS-aligned format
                        val durSec = java.time.Duration.between(stage.startTime, stage.endTime).seconds
                        val isoStart = stage.startTime.toIso8601()
                        append(row(dateString, "Sleep", "Sleep Stage",
                            "${stage.stage} (${durSec}s)", "seconds", isoStart))
                    }
                }
            }

            // ── Activity ──────────────────────────────────────────────────────────────────────
            if (data.activity.hasData || data.mobility.vo2Max != null) {
                val a = data.activity
                a.steps?.let { append(row(dateString, "Activity", "Steps", it, "count")) }
                a.activeCalories?.let { append(row(dateString, "Activity", "Active Calories", it, "kcal")) }
                if (includeAndroidKeys) a.totalCalories?.let { append(row(dateString, "Activity", "Total Calories", it, "kcal")) }
                a.basalEnergyBurned?.let { append(row(dateString, "Activity", "Basal Energy", it, "kcal")) }
                a.exerciseMinutes?.let { append(row(dateString, "Activity", "Exercise Minutes", it, "minutes")) }
                // T1-10: Flights Climbed (was Floors Climbed)
                a.flightsClimbed?.let { append(row(dateString, "Activity", "Flights Climbed", it, "count")) }
                a.walkingRunningDistance?.let { append(row(dateString, "Activity", "Walking Running Distance", it, "meters")) }
                a.cyclingDistance?.let { append(row(dateString, "Activity", "Cycling Distance", it, "meters")) }
                if (includeAndroidKeys) a.elevationGained?.let { append(row(dateString, "Activity", "Elevation Gained", it, "meters")) }
                a.wheelchairPushes?.let { append(row(dateString, "Activity", "Wheelchair Pushes", it, "count")) }
                a.swimmingDistance?.let { append(row(dateString, "Activity", "Swimming Distance", it, "meters")) }
                a.swimmingStrokes?.let { append(row(dateString, "Activity", "Swimming Strokes", it, "count")) }
                a.wheelchairDistance?.let { append(row(dateString, "Activity", "Wheelchair Distance", it, "meters")) }
                a.downhillSnowSportsDistance?.let { append(row(dateString, "Activity", "Downhill Snow Sports Distance", it, "meters")) }
                a.activityIntensityMinutes?.let { append(row(dateString, "Activity", "Activity Intensity Minutes", it, "minutes")) }
                a.moderateActivityMinutes?.let { append(row(dateString, "Activity", "Moderate Activity", it, "minutes")) }
                a.vigorousActivityMinutes?.let { append(row(dateString, "Activity", "Vigorous Activity", it, "minutes")) }
                // T1-11: VO2 under Activity (iOS canonical label)
                data.mobility.vo2Max?.let {
                    append(row(dateString, "Activity", "Cardio Fitness (VO2 Max)",
                        String.format("%.1f", it), "mL/kg/min"))
                }
                if (includeGranularData) {
                    for (sample in a.stepSamples) {
                        // T0-11: ISO 8601 timestamp
                        append(row(dateString, "Activity", "Steps Sample",
                            sample.value.toInt(), "count", sample.time.toIso8601()))
                    }
                    for (entry in a.activityIntensityEntries) {
                        append(row(dateString, "Activity", "${entry.intensity.replaceFirstChar { it.titlecase() }} Activity", entry.duration.inWholeMinutes, "minutes", entry.startTime.toIso8601()))
                    }
                }
            }

            // ── Cycling Performance (iOS canonical category rows) ───────────────────────────
            if (data.activity.cyclingDistance != null || data.mobility.cyclingCadenceAvg != null || data.mobility.powerAvg != null) {
                data.activity.cyclingDistance?.let {
                    append(row(dateString, "Cycling", "Cycling Distance", String.format("%.2f", it / 1000), "km"))
                }
                data.mobility.cyclingCadenceAvg?.let {
                    append(row(dateString, "Cycling", "Cycling Cadence", String.format("%.0f", it), "rpm"))
                }
                data.mobility.powerAvg?.let {
                    append(row(dateString, "Cycling", "Cycling Power", String.format("%.0f", it), "W"))
                }
            }

            // ── Heart ─────────────────────────────────────────────────────────────────────────
            if (data.heart.hasData) {
                val h = data.heart
                h.restingHeartRate?.let { append(row(dateString, "Heart", "Resting Heart Rate", it, "bpm")) }
                h.averageHeartRate?.let { append(row(dateString, "Heart", "Average Heart Rate", it, "bpm")) }
                h.walkingHeartRateAverage?.let { append(row(dateString, "Heart", "Walking Heart Rate Average", it, "bpm")) }
                h.heartRateMin?.let { append(row(dateString, "Heart", "Min Heart Rate", it, "bpm")) }
                h.heartRateMax?.let { append(row(dateString, "Heart", "Max Heart Rate", it, "bpm")) }
                // T1-12: HRV (was HRV (RMSSD))
                h.hrv?.let { append(row(dateString, "Heart", "HRV", it, "ms")) }
                if (includeGranularData) {
                    for (sample in h.samples) {
                        // T0-11: ISO 8601
                        append(row(dateString, "Heart", "Heart Rate Sample",
                            sample.value.toInt(), "bpm", sample.time.toIso8601()))
                    }
                    for (sample in h.hrvSamples) {
                        append(row(dateString, "Heart", "HRV Sample",
                            String.format("%.1f", sample.value), "ms", sample.time.toIso8601()))
                    }
                }
            }

            // ── Vitals ────────────────────────────────────────────────────────────────────────
            if (data.vitals.hasData) {
                val v = data.vitals
                v.respiratoryRateAvg?.let { append(row(dateString, "Vitals", "Respiratory Rate Avg", it, "breaths/min")) }
                v.respiratoryRateMin?.let { append(row(dateString, "Vitals", "Respiratory Rate Min", it, "breaths/min")) }
                v.respiratoryRateMax?.let { append(row(dateString, "Vitals", "Respiratory Rate Max", it, "breaths/min")) }
                v.bloodOxygenAvg?.let { append(row(dateString, "Vitals", "Blood Oxygen Avg", it * 100, "percent")) }
                v.bloodOxygenMin?.let { append(row(dateString, "Vitals", "Blood Oxygen Min", it * 100, "percent")) }
                v.bloodOxygenMax?.let { append(row(dateString, "Vitals", "Blood Oxygen Max", it * 100, "percent")) }
                v.bodyTemperatureAvg?.let {
                    append(row(dateString, "Vitals", "Body Temperature Avg",
                        String.format("%.1f", converter.convertTemperature(it)), tempUnit))
                }
                v.bodyTemperatureMin?.let {
                    append(row(dateString, "Vitals", "Body Temperature Min",
                        String.format("%.1f", converter.convertTemperature(it)), tempUnit))
                }
                v.bodyTemperatureMax?.let {
                    append(row(dateString, "Vitals", "Body Temperature Max",
                        String.format("%.1f", converter.convertTemperature(it)), tempUnit))
                }
                v.bloodPressureSystolicAvg?.let { append(row(dateString, "Vitals", "Blood Pressure Systolic Avg", it, "mmHg")) }
                v.bloodPressureSystolicMin?.let { append(row(dateString, "Vitals", "Blood Pressure Systolic Min", it, "mmHg")) }
                v.bloodPressureSystolicMax?.let { append(row(dateString, "Vitals", "Blood Pressure Systolic Max", it, "mmHg")) }
                v.bloodPressureDiastolicAvg?.let { append(row(dateString, "Vitals", "Blood Pressure Diastolic Avg", it, "mmHg")) }
                v.bloodPressureDiastolicMin?.let { append(row(dateString, "Vitals", "Blood Pressure Diastolic Min", it, "mmHg")) }
                v.bloodPressureDiastolicMax?.let { append(row(dateString, "Vitals", "Blood Pressure Diastolic Max", it, "mmHg")) }
                v.bloodGlucoseAvg?.let { append(row(dateString, "Vitals", "Blood Glucose Avg", it, "mg/dL")) }
                v.bloodGlucoseMin?.let { append(row(dateString, "Vitals", "Blood Glucose Min", it, "mg/dL")) }
                v.bloodGlucoseMax?.let { append(row(dateString, "Vitals", "Blood Glucose Max", it, "mg/dL")) }
                v.basalBodyTemperature?.let {
                    append(row(dateString, "Vitals", "Basal Body Temperature",
                        String.format("%.1f", converter.convertTemperature(it)), tempUnit))
                }
                v.skinTemperatureDelta?.let {
                    append(row(dateString, "Vitals", "Skin Temperature Delta",
                        String.format("%.2f", it), "\u00B0C"))
                }
                if (includeGranularData) {
                    for (sample in v.bloodOxygenSamples) {
                        // T0-11: ISO 8601; T1-13: `Blood Oxygen Sample` (was `SpO2 Sample`)
                        append(row(dateString, "Vitals", "Blood Oxygen Sample",
                            sample.value, "percent", sample.time.toIso8601()))
                    }
                    for (sample in v.bloodPressureSamples) {
                        append(row(dateString, "Vitals", "Blood Pressure Sample",
                            "${sample.systolic.toInt()}/${sample.diastolic.toInt()}", "mmHg",
                            sample.time.toIso8601()))
                    }
                    for (sample in v.bloodGlucoseSamples) {
                        append(row(dateString, "Vitals", "Blood Glucose Sample",
                            String.format("%.1f", sample.value), "mg/dL", sample.time.toIso8601()))
                    }
                    for (sample in v.respiratoryRateSamples) {
                        append(row(dateString, "Vitals", "Respiratory Rate Sample",
                            String.format("%.1f", sample.value), "breaths/min", sample.time.toIso8601()))
                    }
                    for (sample in v.bodyTemperatureSamples) {
                        append(row(dateString, "Vitals", "Body Temperature Sample",
                            String.format("%.1f", converter.convertTemperature(sample.value)), tempUnit,
                            sample.time.toIso8601()))
                    }
                }
            }

            // ── Body ──────────────────────────────────────────────────────────────────────────
            if (data.body.hasData) {
                val b = data.body
                b.weight?.let { append(row(dateString, "Body", "Weight", String.format("%.1f", converter.convertWeight(it)), weightUnit)) }
                b.height?.let { append(row(dateString, "Body", "Height", String.format("%.1f", converter.convertHeight(it)), converter.heightUnit())) }
                b.bmi?.let { append(row(dateString, "Body", "BMI", it, "")) }
                b.bodyFatPercentage?.let { append(row(dateString, "Body", "Body Fat Percentage", it * 100, "percent")) }
                b.leanBodyMass?.let { append(row(dateString, "Body", "Lean Body Mass", String.format("%.1f", converter.convertWeight(it)), weightUnit)) }
                if (includeAndroidKeys) {
                    b.bodyWaterMass?.let { append(row(dateString, "Body", "Body Water Mass", String.format("%.1f", converter.convertWeight(it)), weightUnit)) }
                    b.boneMass?.let { append(row(dateString, "Body", "Bone Mass", String.format("%.1f", converter.convertWeight(it)), weightUnit)) }
                }
            }

            // ── Nutrition ─────────────────────────────────────────────────────────────────────
            if (data.nutrition.hasData) {
                val n = data.nutrition
                n.dietaryEnergy?.let { append(row(dateString, "Nutrition", "Dietary Energy", it, "kcal")) }
                n.energyFromFat?.let { append(row(dateString, "Nutrition", "Energy From Fat", it, "kcal")) }
                n.protein?.let { append(row(dateString, "Nutrition", "Protein", it, "g")) }
                n.carbohydrates?.let { append(row(dateString, "Nutrition", "Carbohydrates", it, "g")) }
                n.fat?.let { append(row(dateString, "Nutrition", "Fat", it, "g")) }
                n.saturatedFat?.let { append(row(dateString, "Nutrition", "Saturated Fat", it, "g")) }
                n.monounsaturatedFat?.let { append(row(dateString, "Nutrition", "Monounsaturated Fat", it, "g")) }
                n.polyunsaturatedFat?.let { append(row(dateString, "Nutrition", "Polyunsaturated Fat", it, "g")) }
                if (includeAndroidKeys) {
                    n.unsaturatedFat?.let { append(row(dateString, "Nutrition", "Unsaturated Fat", it, "g")) }
                    n.transFat?.let { append(row(dateString, "Nutrition", "Trans Fat", it, "g")) }
                }
                n.fiber?.let { append(row(dateString, "Nutrition", "Fiber", it, "g")) }
                n.sugar?.let { append(row(dateString, "Nutrition", "Sugar", it, "g")) }
                n.sodium?.let { append(row(dateString, "Nutrition", "Sodium", it, "mg")) }
                if (includeAndroidKeys) {
                    n.potassium?.let { append(row(dateString, "Nutrition", "Potassium", it, "mg")) }
                    n.calcium?.let { append(row(dateString, "Nutrition", "Calcium", it, "mg")) }
                    n.iron?.let { append(row(dateString, "Nutrition", "Iron", it, "mg")) }
                    n.magnesium?.let { append(row(dateString, "Nutrition", "Magnesium", it, "mg")) }
                    n.zinc?.let { append(row(dateString, "Nutrition", "Zinc", it, "mg")) }
                    n.phosphorus?.let { append(row(dateString, "Nutrition", "Phosphorus", it, "mg")) }
                    n.iodine?.let { append(row(dateString, "Nutrition", "Iodine", it, "mcg")) }
                    n.selenium?.let { append(row(dateString, "Nutrition", "Selenium", it, "mcg")) }
                    n.copper?.let { append(row(dateString, "Nutrition", "Copper", it, "mg")) }
                    n.manganese?.let { append(row(dateString, "Nutrition", "Manganese", it, "mg")) }
                    n.chromium?.let { append(row(dateString, "Nutrition", "Chromium", it, "mcg")) }
                    n.molybdenum?.let { append(row(dateString, "Nutrition", "Molybdenum", it, "mcg")) }
                    n.chloride?.let { append(row(dateString, "Nutrition", "Chloride", it, "mg")) }
                    n.vitaminA?.let { append(row(dateString, "Nutrition", "Vitamin A", it, "mcg")) }
                    n.vitaminB6?.let { append(row(dateString, "Nutrition", "Vitamin B6", it, "mg")) }
                    n.vitaminB12?.let { append(row(dateString, "Nutrition", "Vitamin B12", it, "mcg")) }
                    n.vitaminC?.let { append(row(dateString, "Nutrition", "Vitamin C", it, "mg")) }
                    n.vitaminD?.let { append(row(dateString, "Nutrition", "Vitamin D", it, "mcg")) }
                    n.vitaminE?.let { append(row(dateString, "Nutrition", "Vitamin E", it, "mg")) }
                    n.vitaminK?.let { append(row(dateString, "Nutrition", "Vitamin K", it, "mcg")) }
                    n.thiamin?.let { append(row(dateString, "Nutrition", "Thiamin", it, "mg")) }
                    n.riboflavin?.let { append(row(dateString, "Nutrition", "Riboflavin", it, "mg")) }
                    n.niacin?.let { append(row(dateString, "Nutrition", "Niacin", it, "mg")) }
                    n.folate?.let { append(row(dateString, "Nutrition", "Folate", it, "mcg")) }
                    n.folicAcid?.let { append(row(dateString, "Nutrition", "Folic Acid", it, "mcg")) }
                    n.pantothenicAcid?.let { append(row(dateString, "Nutrition", "Pantothenic Acid", it, "mg")) }
                    n.biotin?.let { append(row(dateString, "Nutrition", "Biotin", it, "mcg")) }
                }
                n.cholesterol?.let { append(row(dateString, "Nutrition", "Cholesterol", it, "mg")) }
                n.water?.let { append(row(dateString, "Nutrition", "Water", it, "L")) }
                n.caffeine?.let { append(row(dateString, "Nutrition", "Caffeine", it, "mg")) }
                n.meals.forEach { meal ->
                    meal.name?.let { append(row(dateString, "Nutrition", "Meal Name", it, "", meal.startTime.toIso8601())) }
                    meal.mealType?.let { append(row(dateString, "Nutrition", "Meal Type", it, "", meal.startTime.toIso8601())) }
                    meal.energyFromFat?.let { append(row(dateString, "Nutrition", "Meal Energy From Fat", it, "kcal", meal.startTime.toIso8601())) }
                }
            }

            // ── Vitamins / Minerals (iOS canonical category rows) ────────────────────────────
            if (data.nutrition.hasVitaminData()) {
                val n = data.nutrition
                n.vitaminA?.let { append(row(dateString, "Vitamins", "Vitamin A", String.format("%.1f", it), "µg")) }
                n.vitaminB6?.let { append(row(dateString, "Vitamins", "Vitamin B6", String.format("%.2f", it), "mg")) }
                n.vitaminB12?.let { append(row(dateString, "Vitamins", "Vitamin B12", String.format("%.2f", it), "µg")) }
                n.vitaminC?.let { append(row(dateString, "Vitamins", "Vitamin C", String.format("%.1f", it), "mg")) }
                n.vitaminD?.let { append(row(dateString, "Vitamins", "Vitamin D", String.format("%.1f", it), "µg")) }
                n.vitaminE?.let { append(row(dateString, "Vitamins", "Vitamin E", String.format("%.2f", it), "mg")) }
                n.vitaminK?.let { append(row(dateString, "Vitamins", "Vitamin K", String.format("%.1f", it), "µg")) }
                n.thiamin?.let { append(row(dateString, "Vitamins", "Thiamin", String.format("%.2f", it), "mg")) }
                n.riboflavin?.let { append(row(dateString, "Vitamins", "Riboflavin", String.format("%.2f", it), "mg")) }
                n.niacin?.let { append(row(dateString, "Vitamins", "Niacin", String.format("%.1f", it), "mg")) }
                n.folate?.let { append(row(dateString, "Vitamins", "Folate", String.format("%.1f", it), "µg")) }
                n.biotin?.let { append(row(dateString, "Vitamins", "Biotin", String.format("%.1f", it), "µg")) }
                n.pantothenicAcid?.let { append(row(dateString, "Vitamins", "Pantothenic Acid", String.format("%.2f", it), "mg")) }
            }

            if (data.nutrition.hasMineralData()) {
                val n = data.nutrition
                n.calcium?.let { append(row(dateString, "Minerals", "Calcium", String.format("%.1f", it), "mg")) }
                n.iron?.let { append(row(dateString, "Minerals", "Iron", String.format("%.2f", it), "mg")) }
                n.potassium?.let { append(row(dateString, "Minerals", "Potassium", String.format("%.1f", it), "mg")) }
                n.magnesium?.let { append(row(dateString, "Minerals", "Magnesium", String.format("%.1f", it), "mg")) }
                n.phosphorus?.let { append(row(dateString, "Minerals", "Phosphorus", String.format("%.1f", it), "mg")) }
                n.zinc?.let { append(row(dateString, "Minerals", "Zinc", String.format("%.2f", it), "mg")) }
                n.selenium?.let { append(row(dateString, "Minerals", "Selenium", String.format("%.1f", it), "µg")) }
                n.copper?.let { append(row(dateString, "Minerals", "Copper", String.format("%.3f", it), "mg")) }
                n.manganese?.let { append(row(dateString, "Minerals", "Manganese", String.format("%.2f", it), "mg")) }
                n.chromium?.let { append(row(dateString, "Minerals", "Chromium", String.format("%.1f", it), "µg")) }
                n.molybdenum?.let { append(row(dateString, "Minerals", "Molybdenum", String.format("%.1f", it), "µg")) }
                n.chloride?.let { append(row(dateString, "Minerals", "Chloride", String.format("%.1f", it), "mg")) }
                n.iodine?.let { append(row(dateString, "Minerals", "Iodine", String.format("%.1f", it), "µg")) }
            }

            // ── Mobility ──────────────────────────────────────────────────────────────────────
            val mobilityHasIosRows = data.mobility.walkingSpeed != null ||
                data.mobility.runningSpeed != null ||
                data.mobility.runningPowerAvg != null
            if (mobilityHasIosRows || (includeAndroidKeys && data.mobility.hasData)) {
                val m = data.mobility
                m.walkingSpeed?.let { append(row(dateString, "Mobility", "Walking Speed", it, "m/s")) }
                if (includeAndroidKeys) {
                    m.vo2Max?.let { append(row(dateString, "Mobility", "VO2 Max", String.format("%.1f", it), "mL/kg/min")) }
                    m.cyclingCadenceAvg?.let { append(row(dateString, "Mobility", "Cycling Cadence", it, "rpm")) }
                    m.stepsCadenceAvg?.let { append(row(dateString, "Mobility", "Steps Cadence", it, "steps/min")) }
                    m.powerAvg?.let { append(row(dateString, "Mobility", "Average Power", it, "W")) }
                    m.powerMax?.let { append(row(dateString, "Mobility", "Max Power", it, "W")) }
                }
                m.runningSpeed?.let { append(row(dateString, "Mobility", "Running Speed", it, "m/s")) }
                m.runningPowerAvg?.let {
                    append(row(dateString, "Mobility", "Running Power", String.format("%.0f", it), "W")) // iOS label
                    if (includeAndroidKeys) append(row(dateString, "Mobility", "Running Power Avg", it, "W")) // Android legacy label
                }
                if (includeAndroidKeys) m.runningPowerMax?.let { append(row(dateString, "Mobility", "Running Power Max", it, "W")) }
            }

            // ── Reproductive Health ───────────────────────────────────────────────────────────
            if (data.reproductiveHealth.hasData) {
                val r = data.reproductiveHealth
                r.menstrualFlow?.let { append(row(dateString, "Reproductive Health", "Menstrual Flow", it, "")) }
                (r.cervicalMucusAppearance ?: r.cervicalMucusSensation)?.let {
                    append(row(dateString, "Reproductive Health", "Cervical Mucus", it, "")) // iOS label
                }
                if (includeAndroidKeys) {
                    r.cervicalMucusAppearance?.let { append(row(dateString, "Reproductive Health", "Cervical Mucus Appearance", it, "")) }
                    r.cervicalMucusSensation?.let { append(row(dateString, "Reproductive Health", "Cervical Mucus Sensation", it, "")) }
                }
                r.ovulationTestResult?.let { append(row(dateString, "Reproductive Health", "Ovulation Test", it, "")) }
                r.menstruationPeriodCount?.let { append(row(dateString, "Reproductive Health", "Menstruation Periods", it, "count")) }
                r.menstruationPeriodDuration.takeIf { it > kotlin.time.Duration.ZERO }?.let {
                    append(row(dateString, "Reproductive Health", "Menstruation Period Days", String.format("%.2f", it.inWholeHours / 24.0), "days"))
                }
                if (r.intermenstrualBleeding) append(row(dateString, "Reproductive Health", "Intermenstrual Bleeding", "true", ""))
                if (r.sexualActivityRecorded) {
                    append(row(dateString, "Reproductive Health", "Sexual Activity", "true", ""))
                    if (includeAndroidKeys) r.sexualActivityProtectionUsed?.let { append(row(dateString, "Reproductive Health", "Protection Used", it, "")) }
                }
            }

            // ── Mindfulness ───────────────────────────────────────────────────────────────────
            if (data.mindfulness.hasData) {
                data.mindfulness.mindfulnessMinutes?.let { append(row(dateString, "Mindfulness", "Mindful Minutes", it, "minutes")) }
                data.mindfulness.mindfulSessions?.let { append(row(dateString, "Mindfulness", "Mindful Sessions", it, "count")) }
                if (includeGranularData) {
                    for (session in data.mindfulness.sessions) {
                        session.sessionType?.let { append(row(dateString, "Mindfulness", "Session Type", it, "", session.startTime.toIso8601())) }
                        session.title?.let { append(row(dateString, "Mindfulness", "Session Title", it, "", session.startTime.toIso8601())) }
                        session.notes?.let { append(row(dateString, "Mindfulness", "Session Notes", it, "", session.startTime.toIso8601())) }
                    }
                }
            }

            // ── Planned Workouts ──────────────────────────────────────────────────────────────
            for (plan in data.plannedWorkouts) {
                append(row(dateString, "Planned Workouts", "${plan.workoutType.displayName()} Start Time", customization.timeFormat.format(plan.startTime), "time"))
                append(row(dateString, "Planned Workouts", "${plan.workoutType.displayName()} Duration", plan.duration.inWholeSeconds, "seconds"))
                append(row(dateString, "Planned Workouts", "${plan.workoutType.displayName()} Has Explicit Time", plan.hasExplicitTime, "boolean"))
                plan.title?.let { append(row(dateString, "Planned Workouts", "${plan.workoutType.displayName()} Title", it, "text")) }
                plan.notes?.let { append(row(dateString, "Planned Workouts", "${plan.workoutType.displayName()} Notes", it, "text")) }
                append(row(dateString, "Planned Workouts", "${plan.workoutType.displayName()} Blocks", plan.blockCount, "count"))
            }

            if (data.medicalResources.hasData) {
                append(row(dateString, "Medical Resources", "Resource Count", data.medicalResources.resources.size, "count"))
                data.medicalResources.countsByType.toSortedMap().forEach { (type, count) ->
                    append(row(dateString, "Medical Resources", type, count, "count"))
                }
            }

            // ── Workouts ──────────────────────────────────────────────────────────────────────
            for (workout in data.workouts) {
                val timeStr = customization.timeFormat.format(workout.startTime)
                val name = workout.workoutType.displayName()
                append(row(dateString, "Workouts", "$name Start Time", timeStr, "time"))
                workout.endTime?.let { append(row(dateString, "Workouts", "$name End Time", customization.timeFormat.format(it), "time")) }
                workout.isIndoor?.let { append(row(dateString, "Workouts", "$name Indoor", it, "boolean")) }
                workout.metadata["title"]?.let { append(row(dateString, "Workouts", "$name Title", it, "text")) }
                workout.metadata["notes"]?.let { append(row(dateString, "Workouts", "$name Notes", it, "text")) }
                append(row(dateString, "Workouts", "$name Duration", workout.duration.inWholeSeconds, "seconds"))
                workout.distance?.takeIf { it > 0 }?.let {
                    append(row(dateString, "Workouts", "$name Distance",
                        String.format("%.2f", converter.convertDistance(it)), distanceUnit))
                }
                workout.calories?.takeIf { it > 0 }?.let {
                    append(row(dateString, "Workouts", "$name Calories", it, "kcal"))
                }
                workout.elevationGained?.takeIf { it > 0 }?.let {
                    append(row(dateString, "Workouts", "$name Elevation Gain", it, "meters")) // iOS label
                    if (includeAndroidKeys) append(row(dateString, "Workouts", "$name Elevation Gained", it, "meters")) // Android legacy label
                }
                workout.elevationLoss?.takeIf { it > 0 }?.let { append(row(dateString, "Workouts", "$name Elevation Loss", it, "meters")) }
                workout.averageHeartRate?.let {
                    append(row(dateString, "Workouts", "$name Avg Heart Rate", it.roundToInt(), "bpm")) // iOS label
                    if (includeAndroidKeys) append(row(dateString, "Workouts", "$name Average Heart Rate", it, "bpm")) // Android legacy label
                }
                workout.heartRateMin?.let { append(row(dateString, "Workouts", "$name Min Heart Rate", it.roundToInt(), "bpm")) }
                workout.heartRateMax?.let { append(row(dateString, "Workouts", "$name Max Heart Rate", it.roundToInt(), "bpm")) }
                if (includeAndroidKeys) {
                    workout.averageSpeed?.let { append(row(dateString, "Workouts", "$name Average Speed", it, "m/s")) }
                    workout.averagePaceSecondsPerKm?.let { append(row(dateString, "Workouts", "$name Average Pace", it, "sec/km")) }
                    workout.maxSpeed?.let { append(row(dateString, "Workouts", "$name Max Speed", it, "m/s")) }
                }
                workout.cyclingCadenceAvg?.let {
                    append(row(dateString, "Workouts", "$name Avg Cadence", it.roundToInt(), "rpm")) // iOS label
                    if (includeAndroidKeys) append(row(dateString, "Workouts", "$name Cycling Cadence", it, "rpm")) // Android legacy label
                }
                workout.stepsCadenceAvg?.let {
                    append(row(dateString, "Workouts", "$name Avg Cadence", it.roundToInt(), "spm")) // iOS label for running cadence
                    if (includeAndroidKeys) append(row(dateString, "Workouts", "$name Steps Cadence", it, "steps/min")) // Android legacy label
                }
                workout.powerAvg?.let {
                    append(row(dateString, "Workouts", "$name Avg Power", it.roundToInt(), "W")) // iOS label
                    if (includeAndroidKeys) append(row(dateString, "Workouts", "$name Average Power", it, "W")) // Android legacy label
                }
                workout.powerMax?.let { append(row(dateString, "Workouts", "$name Max Power", it.roundToInt(), "W")) }
                if (includeAndroidKeys) {
                    append(row(dateString, "Workouts", "$name Route Access", workout.routeAccess.name.lowercase(), ""))
                    if (workout.route.isNotEmpty()) append(row(dateString, "Workouts", "$name Route Points", workout.route.size, "count"))
                }
                for ((index, lap) in workout.laps.withIndex()) {
                    append(row(dateString, "Workouts", "$name Lap ${index + 1} Duration", java.time.Duration.between(lap.startTime, lap.endTime).seconds, "seconds", lap.startTime.toIso8601()))
                    lap.length?.let { append(row(dateString, "Workouts", "$name Lap ${index + 1} Distance", it, "meters", lap.startTime.toIso8601())) }
                }
                for (split in workout.splits) {
                    append(row(dateString, "Workouts", "$name Split ${split.index} Duration", split.duration.inWholeSeconds, "seconds", split.startTime.toIso8601()))
                    split.distance?.let { append(row(dateString, "Workouts", "$name Split ${split.index} Distance", it, "meters", split.startTime.toIso8601())) }
                    split.averageHeartRate?.let { append(row(dateString, "Workouts", "$name Split ${split.index} Average Heart Rate", it, "bpm", split.startTime.toIso8601())) }
                }
                for (segment in workout.segments) {
                    segment.repetitions?.let { append(row(dateString, "Workouts", "$name ${segment.type} Repetitions", it, "count", segment.startTime.toIso8601())) }
                }
                if (includeGranularData) {
                    for (point in workout.route) {
                        append(row(dateString, "Workouts", "$name Route Point", "${point.latitude};${point.longitude}", "lat;lon", point.time.toIso8601()))
                        point.altitude?.let { append(row(dateString, "Workouts", "$name Route Altitude", it, "meters", point.time.toIso8601())) }
                    }
                    for (sample in workout.heartRateSamples) append(row(dateString, "Workouts", "$name Heart Rate Sample", sample.value, "bpm", sample.time.toIso8601()))
                    for (sample in workout.speedSamples) append(row(dateString, "Workouts", "$name Speed Sample", sample.value, "m/s", sample.time.toIso8601()))
                    for (sample in workout.cyclingCadenceSamples) append(row(dateString, "Workouts", "$name Cycling Cadence Sample", sample.value, "rpm", sample.time.toIso8601()))
                    for (sample in workout.stepsCadenceSamples) append(row(dateString, "Workouts", "$name Steps Cadence Sample", sample.value, "steps/min", sample.time.toIso8601()))
                    for (sample in workout.powerSamples) append(row(dateString, "Workouts", "$name Power Sample", sample.value, "W", sample.time.toIso8601()))
                    for (sample in workout.elevationSamples) append(row(dateString, "Workouts", "$name Elevation Sample", sample.value, "meters", sample.time.toIso8601()))
                }
            }
        }
    }
}
