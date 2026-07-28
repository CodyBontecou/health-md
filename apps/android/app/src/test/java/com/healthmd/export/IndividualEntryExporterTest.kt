package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.IndividualEntryExporter
import com.healthmd.domain.model.*
import kotlinx.serialization.json.Json
import org.junit.Test
import java.time.LocalDate
import java.time.LocalDateTime
import kotlin.time.Duration.Companion.minutes

class IndividualEntryExporterTest {
    private val exporter = IndividualEntryExporter()
    private val date = LocalDate.of(2026, 3, 15)
    private val t6 = LocalDateTime.of(2026, 3, 15, 6, 0)

    @Test
    fun legacyEnabledMetrics_migrateToPerMetricConfigsAndStillExportBloodPressure() {
        val legacyJson = """
            {
              "globalEnabled": true,
              "enabledMetrics": ["workouts", "blood_pressure", "blood_glucose", "weight"],
              "entriesFolder": "entries",
              "organizeByCategory": true,
              "filenameTemplate": "{metric}-{date}-{time}"
            }
        """.trimIndent()

        val settings = Json { ignoreUnknownKeys = true }
            .decodeFromString(IndividualTrackingSettings.serializer(), legacyJson)

        assertThat(settings.isMetricEnabled("workouts")).isTrue()
        assertThat(settings.isMetricEnabled("bp_systolic")).isTrue()
        assertThat(settings.isMetricEnabled("bp_diastolic")).isTrue()
        assertThat(settings.isMetricEnabled("blood_glucose")).isTrue()
        assertThat(settings.isMetricEnabled("weight")).isTrue()

        val data = HealthData(
            date = date,
            vitals = VitalsData(
                bloodPressureSamples = listOf(BloodPressureSample(t6, systolic = 121.0, diastolic = 79.0)),
            ),
        )

        val entries = exporter.exportEntries(data, settings)
        assertThat(entries.map { it.first }).contains("entries/vitals/blood-pressure-2026-03-15-06-00.md")
        assertThat(entries.single().second).contains("systolic: 121")
    }

    @Test
    fun pathGeneration_usesTemplateCategoryFoldersAndAvoidsDoubleEntriesPrefix() {
        val settings = IndividualTrackingSettings(
            globalEnabled = true,
            entriesFolder = "entries",
            organizeByCategory = true,
            filenameTemplate = "{category}-{metric}-{date}-{time}",
            enabledMetrics = setOf("blood_oxygen"),
            metricConfigs = mapOf(
                "blood_oxygen" to MetricTrackingConfig(
                    trackIndividually = true,
                    customFolder = "entries/custom/vitals",
                ),
            ),
        )

        val path = settings.relativePathFor(
            metricId = "blood_oxygen",
            metricSlug = "blood-oxygen",
            category = HealthMetricCategory.RESPIRATORY,
            date = date,
            time = "08-30",
        )

        assertThat(path).isEqualTo("entries/custom/vitals/respiratory-blood-oxygen-2026-03-15-08-30.md")
    }

    @Test
    fun suggestedMetrics_includeEventLevelAndroidMetrics() {
        val settings = IndividualTrackingSettings(globalEnabled = true).enableSuggested()

        assertThat(settings.isMetricEnabled("workouts")).isTrue()
        assertThat(settings.isMetricEnabled("bp_systolic")).isTrue()
        assertThat(settings.isMetricEnabled("bp_diastolic")).isTrue()
        assertThat(settings.isMetricEnabled("blood_glucose")).isTrue()
        assertThat(settings.isMetricEnabled("steps")).isTrue()
        assertThat(settings.isMetricEnabled("avg_hr")).isTrue()
        assertThat(settings.isMetricEnabled("hrv")).isTrue()
        assertThat(settings.isMetricEnabled("blood_oxygen")).isTrue()
        assertThat(settings.isMetricEnabled("respiratory_rate")).isTrue()
        assertThat(settings.isMetricEnabled("body_temp")).isTrue()
        assertThat(settings.isMetricEnabled("sleep_total")).isTrue()
        assertThat(settings.isMetricEnabled("mindful_sessions")).isTrue()
    }

    @Test
    fun exportEntries_writesRepresentativeTimestampedEntriesForSupportedCategories() {
        val settings = IndividualTrackingSettings(globalEnabled = true)
            .enableAll(
                listOf(
                    "workouts",
                    "sleep_total",
                    "steps",
                    "avg_hr",
                    "hrv",
                    "bp_systolic",
                    "bp_diastolic",
                    "blood_glucose",
                    "blood_oxygen",
                    "respiratory_rate",
                    "body_temp",
                    "mindful_sessions",
                    "weight",
                )
            )

        val data = HealthData(
            date = date,
            sleep = SleepData(
                stages = listOf(SleepStageEntry(t6.minusHours(1), t6, "deep")),
            ),
            activity = ActivityData(
                stepSamples = listOf(TimestampedSample(t6, 500.0)),
            ),
            heart = HeartData(
                samples = listOf(TimestampedSample(t6.plusHours(1), 72.0)),
                hrvSamples = listOf(TimestampedSample(t6.plusHours(2), 41.5)),
            ),
            vitals = VitalsData(
                bloodPressureSamples = listOf(BloodPressureSample(t6.plusMinutes(5), 120.0, 80.0)),
                bloodGlucoseSamples = listOf(TimestampedSample(t6.plusMinutes(10), 95.0)),
                bloodOxygenSamples = listOf(TimestampedSample(t6.plusMinutes(15), 0.98)),
                respiratoryRateSamples = listOf(TimestampedSample(t6.plusMinutes(20), 14.0)),
                bodyTemperatureSamples = listOf(TimestampedSample(t6.plusMinutes(25), 36.7)),
            ),
            body = BodyData(weight = 75.0),
            mindfulness = MindfulnessData(
                mindfulnessMinutes = 10.0,
                mindfulSessions = 1,
                sessions = listOf(MindfulnessSessionEntry(t6.plusHours(3), t6.plusHours(3).plusMinutes(10))),
            ),
            workouts = listOf(
                WorkoutData(
                    workoutType = WorkoutType.RUNNING,
                    startTime = t6.plusHours(4),
                    endTime = t6.plusHours(4).plusMinutes(30),
                    isIndoor = false,
                    metadata = mapOf("title" to "Morning run"),
                    duration = 30.minutes,
                    calories = 300.0,
                    distance = 5_000.0,
                    elevationLoss = 25.0,
                    splits = listOf(
                        WorkoutSplitData(
                            index = 1,
                            startTime = t6.plusHours(4),
                            endTime = t6.plusHours(4).plusMinutes(5),
                            duration = 5.minutes,
                            distance = 1_000.0,
                            averageHeartRate = 140.0,
                        ),
                    ),
                    routeAccess = WorkoutRouteAccess.CONSENT_REQUIRED,
                )
            ),
        )

        val entries = exporter.exportEntries(data, settings)
        val paths = entries.map { it.first }

        assertThat(paths).contains("entries/sleep/sleep-deep-2026-03-15-05-00.md")
        assertThat(paths).contains("entries/activity/steps-2026-03-15-06-00.md")
        assertThat(paths).contains("entries/heart/heart-rate-2026-03-15-07-00.md")
        assertThat(paths).contains("entries/heart/hrv-2026-03-15-08-00.md")
        assertThat(paths).contains("entries/vitals/blood-pressure-2026-03-15-06-05.md")
        assertThat(paths).contains("entries/vitals/blood-glucose-2026-03-15-06-10.md")
        assertThat(paths).contains("entries/respiratory/blood-oxygen-2026-03-15-06-15.md")
        assertThat(paths).contains("entries/respiratory/respiratory-rate-2026-03-15-06-20.md")
        assertThat(paths).contains("entries/vitals/body-temperature-2026-03-15-06-25.md")
        assertThat(paths).contains("entries/body/weight-2026-03-15-00-00.md")
        assertThat(paths).contains("entries/mindfulness/mindful-session-2026-03-15-09-00.md")
        assertThat(paths).contains("entries/workouts/running-2026-03-15-10-00.md")

        val bloodPressureContent = entries.single { it.first.contains("blood-pressure") }.second
        assertThat(bloodPressureContent).contains("metric: blood_pressure")
        assertThat(bloodPressureContent).contains("systolic: 120")
        assertThat(bloodPressureContent).contains("# Blood Pressure")

        val workoutContent = entries.single { it.first.contains("running") }.second
        assertThat(workoutContent).contains("duration_minutes: 30")
        assertThat(workoutContent).contains("is_indoor: false")
        assertThat(workoutContent).contains("route_access: \"consent_required\"")
        assertThat(workoutContent).contains("splits: 1")
        assertThat(workoutContent).contains("- **Distance:** 5.00 km")
        assertThat(workoutContent).contains("- **Elevation loss:** 25 m")
    }
}
