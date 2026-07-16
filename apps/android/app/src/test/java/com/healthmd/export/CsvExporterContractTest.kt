package com.healthmd.export

import com.healthmd.data.export.CsvExporter
import com.healthmd.domain.model.*
import org.junit.Assert.*
import org.junit.Before
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import java.util.Locale

/**
 * Contract tests for [CsvExporter] against the iOS CSV schema.
 *
 * Schema contract: docs/export-contract/ios-export-contract.md (§3)
 * Gap matrix fixes:
 *   T0-11  Granular sample Timestamp → ISO 8601
 *   T1-08  Always 6-column header
 *   T1-09  Sleep `Core Sleep` label (iOS canonical, = Light Sleep value)
 *   T1-10  Activity `Flights Climbed` (was `Floors Climbed`)
 *   T1-11  `Activity,Cardio Fitness (VO2 Max)` row added
 *   T1-12  Heart `HRV` label (was `HRV (RMSSD)`)
 *   T1-13  Vitals `Blood Oxygen Sample` label (was `SpO2 Sample`)
 */
class CsvExporterContractTest {

    private lateinit var exporter: CsvExporter
    private val referenceDate: LocalDate = LocalDate.of(2026, 3, 15)
    private val t: LocalDateTime = LocalDateTime.of(2026, 3, 15, 6, 0, 0)

    @Before
    fun setUp() {
        exporter = CsvExporter()
    }

    // ── Helpers ──────────────────────────────────────────────────────────────────────────────

    private fun csv(
        data: HealthData,
        granular: Boolean = false,
        customization: FormatCustomization = FormatCustomization(),
    ): List<List<String>> {
        val raw = exporter.export(data, customization = customization, includeGranularData = granular)
        return raw.lines()
            .filter { it.isNotBlank() }
            .map { it.split(",") }
    }

    private val androidCompatibilityCustomization = FormatCustomization(includeLegacyAndroidAliases = true, includeAndroidNativeFields = true)

    private fun header(data: HealthData): List<String> = csv(data).first()

    private fun dataRows(data: HealthData, granular: Boolean = false): List<List<String>> =
        csv(data, granular).drop(1)

    private fun rowsFor(
        category: String,
        data: HealthData,
        granular: Boolean = false,
        customization: FormatCustomization = FormatCustomization(),
    ): List<List<String>> =
        csv(data, granular, customization).drop(1).filter { it.size > 1 && it[1] == category }

    private fun rowFor(
        category: String,
        metric: String,
        data: HealthData,
        granular: Boolean = false,
        customization: FormatCustomization = FormatCustomization(),
    ): List<String>? =
        csv(data, granular, customization).drop(1).firstOrNull { it.size > 2 && it[1] == category && it[2] == metric }

    // ── Header schema ─────────────────────────────────────────────────────────────────────────

    @Test
    fun header_T1_08_always6Columns() {
        // T1-08: header must always be 6 columns regardless of granular flag
        val data = HealthData(date = referenceDate)
        assertEquals(listOf("Date", "Category", "Metric", "Value", "Unit", "Timestamp"),
            header(data))
    }

    @Test
    fun header_T1_08_6columnsWithGranularFalse() {
        val data = HealthData(date = referenceDate, activity = ActivityData(steps = 1000))
        assertEquals(6, header(data).size)
    }

    @Test
    fun emptyDay_hasOnlyHeader() {
        val rows = csv(HealthData(date = referenceDate))
        assertEquals("Empty day should have only header", 1, rows.size)
    }

    @Test
    fun aggregateRows_have6Columns_emptyTimestamp() {
        val data = HealthData(date = referenceDate, activity = ActivityData(steps = 5000))
        val actRows = rowsFor("Activity", data)
        assertFalse(actRows.isEmpty())
        for (row in actRows) {
            assertEquals("Aggregate row must have 6 columns: $row", 6, row.size)
            assertEquals("Aggregate row Timestamp must be empty: $row", "", row[5])
        }
    }

    @Test
    fun csv_decimalValuesAreLocaleInvariant_whenDeviceLocaleUsesCommaDecimal() {
        val previousLocale = Locale.getDefault()
        Locale.setDefault(Locale.FRANCE)
        try {
            val data = HealthData(
                date = referenceDate,
                activity = ActivityData(cyclingDistance = 1234.5),
                vitals = VitalsData(
                    bloodGlucoseAvg = 100.0,
                    bodyTemperatureAvg = 36.7,
                    bloodGlucoseSamples = listOf(TimestampedSample(t, 123.4)),
                    bodyTemperatureSamples = listOf(TimestampedSample(t.plusMinutes(5), 36.8)),
                ),
                body = BodyData(weight = 70.4),
                nutrition = NutritionData(vitaminB6 = 1.23, iron = 8.45),
            )

            val raw = exporter.export(data, includeGranularData = true)
            val lines = raw.lines().filter { it.isNotBlank() }

            assertTrue(raw.contains(",Cycling,Cycling Distance,1.23,km,"))
            assertTrue(raw.contains(",Vitals,Blood Glucose Sample,123.4,mg/dL,"))
            assertTrue(raw.contains(",Vitals,Body Temperature Avg,36.7,°C,"))
            assertTrue(raw.contains(",Body,Weight,70.4,kg,"))
            assertTrue("CSV should not contain comma decimals under fr-FR locale:\n$raw", lines.all { it.split(",").size == 6 })
        } finally {
            Locale.setDefault(previousLocale)
        }
    }

    @Test
    fun csv_cellsWithCommasOrQuotesAreEscaped() {
        val data = HealthData(
            date = referenceDate,
            nutrition = NutritionData(
                meals = listOf(
                    NutritionMealEntry(
                        startTime = t,
                        endTime = t.plusMinutes(30),
                        name = "Eggs, toast \"large\"",
                    ),
                ),
            ),
        )

        val raw = exporter.export(data)

        assertTrue(raw.contains("Nutrition,Meal Name,\"Eggs, toast \"\"large\"\"\",,"))
    }

    // ── Sleep category ────────────────────────────────────────────────────────────────────────

    @Test
    fun sleep_T1_09_coreSleepLabelPresent() {
        // T1-09: Core Sleep row must be present (iOS canonical label)
        val data = HealthData(date = referenceDate, sleep = SleepData(
            totalDuration = kotlin.time.Duration.parse("7h"),
            lightSleep = kotlin.time.Duration.parse("4h"),
        ))
        val row = rowFor("Sleep", "Core Sleep", data)
        assertNotNull("Core Sleep row missing (T1-09)", row)
        assertEquals("seconds", row!![4])
    }

    @Test
    fun sleep_androidLightSleepOmittedByDefault() {
        val data = HealthData(date = referenceDate, sleep = SleepData(
            totalDuration = kotlin.time.Duration.parse("7h"),
            lightSleep = kotlin.time.Duration.parse("4h"),
        ))
        val row = rowFor("Sleep", "Light Sleep", data)
        assertNull("Light Sleep is an Android compatibility row and should be off by default", row)
    }

    @Test
    fun sleep_androidLightSleepPresentWhenCompatibilityKeysEnabled() {
        val data = HealthData(date = referenceDate, sleep = SleepData(
            totalDuration = kotlin.time.Duration.parse("7h"),
            lightSleep = kotlin.time.Duration.parse("4h"),
        ))
        val row = rowFor("Sleep", "Light Sleep", data, customization = androidCompatibilityCustomization)
        assertNotNull("Light Sleep Android row should be available when compatibility is enabled", row)
    }

    @Test
    fun sleep_T1_09_coreLightSameValue() {
        val data = HealthData(date = referenceDate, sleep = SleepData(
            lightSleep = kotlin.time.Duration.parse("4h"),
        ))
        val coreRow = rowFor("Sleep", "Core Sleep", data)
        val lightRow = rowFor("Sleep", "Light Sleep", data, customization = androidCompatibilityCustomization)
        assertNotNull(coreRow)
        assertNotNull(lightRow)
        assertEquals("Core Sleep and Light Sleep must have same value",
            coreRow!![3], lightRow!![3])
    }

    @Test
    fun sleep_granular_T0_11_stageTimestampIsIso8601() {
        // T0-11: sleep stage Timestamp must be ISO 8601
        val stage = SleepStageEntry(t, t.plusHours(2), "deep")
        val data = HealthData(date = referenceDate, sleep = SleepData(
            totalDuration = kotlin.time.Duration.parse("7h"),
            stages = listOf(stage),
        ))
        val rows = rowsFor("Sleep", data, granular = true)
        val stageRow = rows.firstOrNull { it.size > 2 && it[2] == "Sleep Stage" }
        assertNotNull("Sleep Stage row missing", stageRow)
        val ts = stageRow!![5]
        assertTrue("Sleep Stage Timestamp must be ISO 8601 (contains 'T'): $ts", ts.contains("T"))
        assertFalse("Sleep Stage Timestamp must not be empty", ts.isBlank())
    }

    @Test
    fun sleep_granular_stageMetricLabelIsSleepStage() {
        // iOS: metric label = "Sleep Stage"
        val stage = SleepStageEntry(t, t.plusHours(2), "deep")
        val data = HealthData(date = referenceDate, sleep = SleepData(
            totalDuration = kotlin.time.Duration.parse("7h"),
            stages = listOf(stage),
        ))
        val row = rowFor("Sleep", "Sleep Stage", data, granular = true)
        assertNotNull("Sleep Stage metric label missing (iOS format)", row)
    }

    @Test
    fun sleep_granular_stageValueIncludesNameAndDuration() {
        // iOS value format: "<stage> (<dur>s)"
        val stage = SleepStageEntry(t, t.plusHours(2), "deep")
        val data = HealthData(date = referenceDate, sleep = SleepData(
            totalDuration = kotlin.time.Duration.parse("7h"),
            stages = listOf(stage),
        ))
        val row = rowFor("Sleep", "Sleep Stage", data, granular = true)
        val value = row!![3]
        assertTrue("Stage value should contain 'deep': $value", value.contains("deep"))
        assertTrue("Stage value should contain duration in seconds: $value", value.contains("s)"))
    }

    // ── Activity category ─────────────────────────────────────────────────────────────────────

    @Test
    fun activity_T1_10_flightsClimbed_notFloors() {
        // T1-10: label must be "Flights Climbed" (was "Floors Climbed")
        val data = HealthData(date = referenceDate, activity = ActivityData(flightsClimbed = 8))
        val row = rowFor("Activity", "Flights Climbed", data)
        assertNotNull("Flights Climbed row missing (T1-10)", row)
        assertNull("Floors Climbed old label must not exist (T1-10)",
            rowFor("Activity", "Floors Climbed", data))
    }

    @Test
    fun activity_T1_11_vo2MaxUnderActivity() {
        // T1-11: VO2 Max must appear as Activity,Cardio Fitness (VO2 Max)
        val data = HealthData(date = referenceDate, mobility = MobilityData(vo2Max = 42.5))
        val row = rowFor("Activity", "Cardio Fitness (VO2 Max)", data)
        assertNotNull("Activity,Cardio Fitness (VO2 Max) missing (T1-11)", row)
        assertTrue("VO2 value should be ~42.5", row!![3].contains("42"))
        assertEquals("mL/kg/min", row[4])
    }

    @Test
    fun activity_T1_11_vo2MaxNotDuplicatedUnderMobilityByDefault() {
        val data = HealthData(date = referenceDate, mobility = MobilityData(vo2Max = 42.5))
        val row = rowFor("Mobility", "VO2 Max", data)
        assertNull("Mobility,VO2 Max is an Android compatibility row and should be off by default", row)
    }

    @Test
    fun activity_T1_11_vo2MaxUnderMobilityWhenCompatibilityKeysEnabled() {
        val data = HealthData(date = referenceDate, mobility = MobilityData(vo2Max = 42.5))
        val row = rowFor("Mobility", "VO2 Max", data, customization = androidCompatibilityCustomization)
        assertNotNull("Mobility,VO2 Max should be available when compatibility is enabled", row)
    }

    @Test
    fun activity_standardMetrics_present() {
        val data = HealthData(date = referenceDate, activity = ActivityData(
            steps = 12500, activeCalories = 520.0, basalEnergyBurned = 1650.0,
            exerciseMinutes = 45.0, flightsClimbed = 8,
            walkingRunningDistance = 9500.0,
        ))
        val metrics = rowsFor("Activity", data).map { it[2] }.toSet()
        assertTrue(metrics.contains("Steps"))
        assertTrue(metrics.contains("Active Calories"))
        assertTrue(metrics.contains("Basal Energy"))
        assertTrue(metrics.contains("Exercise Minutes"))
        assertTrue(metrics.contains("Flights Climbed"))
        assertTrue(metrics.contains("Walking Running Distance"))
    }

    @Test
    fun activity_T0_11_stepSampleTimestampIsIso8601() {
        val a = ActivityData(
            steps = 5000,
            stepSamples = listOf(TimestampedSample(t, 500.0)),
        )
        val data = HealthData(date = referenceDate, activity = a)
        val sampleRow = rowFor("Activity", "Steps Sample", data, granular = true)
        assertNotNull("Steps Sample row missing", sampleRow)
        val ts = sampleRow!![5]
        assertTrue("Steps Sample Timestamp must be ISO 8601: $ts", ts.contains("T"))
    }

    // ── Heart category ────────────────────────────────────────────────────────────────────────

    @Test
    fun heart_T1_12_hrvLabelIsHrv() {
        // T1-12: HRV row must use label "HRV" (was "HRV (RMSSD)")
        val data = HealthData(date = referenceDate, heart = HeartData(
            restingHeartRate = 58.0, hrv = 42.0,
        ))
        val row = rowFor("Heart", "HRV", data)
        assertNotNull("HRV row missing (T1-12)", row)
        assertEquals("ms", row!![4])
        assertNull("HRV (RMSSD) old label must not exist (T1-12)",
            rowFor("Heart", "HRV (RMSSD)", data))
    }

    @Test
    fun heart_standardMetrics_present() {
        val data = HealthData(date = referenceDate, heart = HeartData(
            restingHeartRate = 58.0, averageHeartRate = 72.0,
            heartRateMin = 52.0, heartRateMax = 155.0, hrv = 42.0,
        ))
        val metrics = rowsFor("Heart", data).map { it[2] }.toSet()
        for (m in listOf("Resting Heart Rate", "Average Heart Rate", "Min Heart Rate", "Max Heart Rate", "HRV")) {
            assertTrue("Heart missing metric: $m", metrics.contains(m))
        }
    }

    @Test
    fun heart_T0_11_hrSampleTimestampIsIso8601() {
        // T0-11: heart rate sample Timestamp must be ISO 8601
        val h = HeartData(
            restingHeartRate = 58.0,
            samples = listOf(TimestampedSample(t, 72.0)),
        )
        val data = HealthData(date = referenceDate, heart = h)
        val row = rowFor("Heart", "Heart Rate Sample", data, granular = true)
        assertNotNull("Heart Rate Sample row missing", row)
        val ts = row!![5]
        assertTrue("Heart Rate Sample Timestamp must be ISO 8601: $ts", ts.contains("T"))
        assertFalse("Timestamp must not be empty", ts.isBlank())
    }

    @Test
    fun heart_T0_11_hrvSampleTimestampIsIso8601() {
        val h = HeartData(
            hrv = 42.0,
            hrvSamples = listOf(TimestampedSample(t, 40.0)),
        )
        val data = HealthData(date = referenceDate, heart = h)
        val row = rowFor("Heart", "HRV Sample", data, granular = true)
        assertNotNull("HRV Sample row missing", row)
        val ts = row!![5]
        assertTrue("HRV Sample Timestamp must be ISO 8601: $ts", ts.contains("T"))
    }

    // ── Vitals category ───────────────────────────────────────────────────────────────────────

    @Test
    fun vitals_T1_13_bloodOxygenSampleLabel() {
        // T1-13: label must be "Blood Oxygen Sample" (was "SpO2 Sample")
        val v = VitalsData(
            bloodOxygenAvg = 0.97,
            bloodOxygenSamples = listOf(TimestampedSample(t, 0.96)),
        )
        val data = HealthData(date = referenceDate, vitals = v)
        val row = rowFor("Vitals", "Blood Oxygen Sample", data, granular = true)
        assertNotNull("Blood Oxygen Sample row missing (T1-13)", row)
        assertNull("SpO2 Sample old label must not exist (T1-13)",
            rowFor("Vitals", "SpO2 Sample", data, granular = true))
    }

    @Test
    fun vitals_T0_11_bloodOxygenSampleTimestampIsIso8601() {
        val v = VitalsData(
            bloodOxygenAvg = 0.97,
            bloodOxygenSamples = listOf(TimestampedSample(t, 0.96)),
        )
        val data = HealthData(date = referenceDate, vitals = v)
        val row = rowFor("Vitals", "Blood Oxygen Sample", data, granular = true)
        val ts = row!![5]
        assertTrue("Blood Oxygen Sample Timestamp must be ISO 8601: $ts", ts.contains("T"))
    }

    @Test
    fun vitals_T0_11_bloodGlucoseSampleTimestampIsIso8601() {
        val v = VitalsData(
            bloodGlucoseAvg = 95.0,
            bloodGlucoseSamples = listOf(TimestampedSample(t, 90.0)),
        )
        val data = HealthData(date = referenceDate, vitals = v)
        val row = rowFor("Vitals", "Blood Glucose Sample", data, granular = true)
        assertNotNull("Blood Glucose Sample row missing", row)
        val ts = row!![5]
        assertTrue("Blood Glucose Sample Timestamp must be ISO 8601: $ts", ts.contains("T"))
    }

    @Test
    fun vitals_T0_11_respiratoryRateSampleTimestampIsIso8601() {
        val v = VitalsData(
            respiratoryRateAvg = 15.0,
            respiratoryRateSamples = listOf(TimestampedSample(t, 14.0)),
        )
        val data = HealthData(date = referenceDate, vitals = v)
        val row = rowFor("Vitals", "Respiratory Rate Sample", data, granular = true)
        assertNotNull("Respiratory Rate Sample row missing", row)
        val ts = row!![5]
        assertTrue("Respiratory Rate Sample Timestamp must be ISO 8601: $ts", ts.contains("T"))
    }

    @Test
    fun vitals_aggregateMetrics_present() {
        val v = VitalsData(
            respiratoryRateAvg = 15.0, respiratoryRateMin = 12.0, respiratoryRateMax = 18.0,
            bloodOxygenAvg = 0.97, bloodOxygenMin = 0.94, bloodOxygenMax = 0.99,
            bloodPressureSystolicAvg = 120.0, bloodPressureDiastolicAvg = 80.0,
            bloodGlucoseAvg = 95.0,
        )
        val data = HealthData(date = referenceDate, vitals = v)
        val metrics = rowsFor("Vitals", data).map { it[2] }.toSet()
        for (m in listOf(
            "Respiratory Rate Avg", "Respiratory Rate Min", "Respiratory Rate Max",
            "Blood Oxygen Avg", "Blood Oxygen Min", "Blood Oxygen Max",
            "Blood Pressure Systolic Avg", "Blood Pressure Diastolic Avg",
            "Blood Glucose Avg",
        )) {
            assertTrue("Vitals missing metric: $m", metrics.contains(m))
        }
    }

    // ── Cycling / micronutrients ─────────────────────────────────────────────────────────────

    @Test
    fun cycling_androidBackedMetricsUseIosCategoryRows() {
        val data = HealthData(
            date = referenceDate,
            activity = ActivityData(cyclingDistance = 3_200.0),
            mobility = MobilityData(cyclingCadenceAvg = 87.4, powerAvg = 210.2),
        )
        assertNotNull("Cycling Distance row missing", rowFor("Cycling", "Cycling Distance", data))
        assertNotNull("Cycling Cadence row missing", rowFor("Cycling", "Cycling Cadence", data))
        assertNotNull("Cycling Power row missing", rowFor("Cycling", "Cycling Power", data))
    }

    @Test
    fun vitaminsAndMinerals_androidBackedMetricsUseIosCategoryRows() {
        val data = HealthData(date = referenceDate, nutrition = NutritionData(
            vitaminA = 900.0,
            vitaminB12 = 2.4,
            folate = 400.0,
            biotin = 30.0,
            calcium = 1_000.0,
            selenium = 55.0,
            chromium = 35.0,
            iodine = 150.0,
        ))
        assertNotNull("Vitamins,Vitamin A row missing", rowFor("Vitamins", "Vitamin A", data))
        assertNotNull("Vitamins,Vitamin B12 row missing", rowFor("Vitamins", "Vitamin B12", data))
        assertNotNull("Vitamins,Folate row missing", rowFor("Vitamins", "Folate", data))
        assertNotNull("Vitamins,Biotin row missing", rowFor("Vitamins", "Biotin", data))
        assertNotNull("Minerals,Calcium row missing", rowFor("Minerals", "Calcium", data))
        assertNotNull("Minerals,Selenium row missing", rowFor("Minerals", "Selenium", data))
        assertNotNull("Minerals,Chromium row missing", rowFor("Minerals", "Chromium", data))
        assertNotNull("Minerals,Iodine row missing", rowFor("Minerals", "Iodine", data))
    }

    // ── Mindfulness ───────────────────────────────────────────────────────────────────────────

    @Test
    fun mindfulness_sessionsRow_whenPresent() {
        val data = HealthData(date = referenceDate,
            mindfulness = MindfulnessData(mindfulnessMinutes = 15.0, mindfulSessions = 2))
        val row = rowFor("Mindfulness", "Mindful Sessions", data)
        assertNotNull("Mindful Sessions row missing", row)
        assertEquals("2", row!![3])
        assertEquals("count", row[4])
    }

    // ── Workouts ──────────────────────────────────────────────────────────────────────────────

    @Test
    fun workouts_iosWorkoutLabels_presentForAndroidBackedMetrics() {
        val data = HealthData(date = referenceDate, workouts = listOf(
            WorkoutData(
                workoutType = WorkoutType.CYCLING,
                startTime = t,
                duration = kotlin.time.Duration.parse("45m"),
                averageHeartRate = 142.4,
                heartRateMin = 100.0,
                heartRateMax = 168.0,
                cyclingCadenceAvg = 86.7,
                powerAvg = 205.3,
                powerMax = 650.0,
                elevationGained = 120.0,
                elevationLoss = 110.0,
            ),
        ))
        assertNotNull(rowFor("Workouts", "Cycling Avg Heart Rate", data))
        assertNotNull(rowFor("Workouts", "Cycling Max Heart Rate", data))
        assertNotNull(rowFor("Workouts", "Cycling Min Heart Rate", data))
        assertNotNull(rowFor("Workouts", "Cycling Avg Cadence", data))
        assertNotNull(rowFor("Workouts", "Cycling Avg Power", data))
        assertNotNull(rowFor("Workouts", "Cycling Max Power", data))
        assertNotNull(rowFor("Workouts", "Cycling Elevation Gain", data))
        assertNotNull(rowFor("Workouts", "Cycling Elevation Loss", data))
    }

    @Test
    fun workouts_standardRows_present() {
        val data = HealthData(date = referenceDate, workouts = listOf(
            WorkoutData(
                workoutType = WorkoutType.RUNNING,
                startTime = t,
                duration = kotlin.time.Duration.parse("30m"),
                calories = 300.0,
                distance = 5000.0,
            ),
        ))
        val rows = rowsFor("Workouts", data)
        val metrics = rows.map { it[2] }.toSet()
        assertTrue(metrics.any { it.contains("Start Time") })
        assertTrue(metrics.any { it.contains("Duration") })
        assertTrue(metrics.any { it.contains("Distance") })
        assertTrue(metrics.any { it.contains("Calories") })
    }

    // ── Row consistency ───────────────────────────────────────────────────────────────────────

    @Test
    fun allAggregateRows_have6Columns() {
        // Every non-sample row must have exactly 6 columns (Timestamp = empty)
        val data = HealthData(
            date = referenceDate,
            sleep = SleepData(totalDuration = kotlin.time.Duration.parse("7h"),
                lightSleep = kotlin.time.Duration.parse("4h")),
            activity = ActivityData(steps = 5000, flightsClimbed = 8),
            heart = HeartData(restingHeartRate = 58.0, hrv = 42.0),
            vitals = VitalsData(respiratoryRateAvg = 15.0, bloodOxygenAvg = 0.97),
            body = BodyData(weight = 75.0),
            nutrition = NutritionData(dietaryEnergy = 2100.0),
        )
        val rows = dataRows(data)
        for (row in rows) {
            assertEquals("Row must have 6 columns: $row", 6, row.size)
            assertEquals("Aggregate Timestamp must be empty: $row", "", row[5])
        }
    }
}
