package com.healthmd.domain.exportengine

import androidx.test.ext.junit.runners.AndroidJUnit4
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.WriteMode
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DailyAggregateRustPlannerInstrumentationTest {
    @Test
    fun packagedCorePlansEverySuccessorWorkoutFormatWithoutClockOrQuantityLoss() = runBlocking {
        val zone = ZoneId.of("America/New_York")
        val context = com.healthmd.domain.model.AndroidCaptureContext(zone, com.healthmd.domain.model.SleepDayAttribution.MORNING_ENDS)
        val start = java.time.Instant.parse("2026-11-01T05:30:00.123456789Z")
        val end = java.time.Instant.parse("2026-11-01T06:30:00.987654321Z")
        val workout = com.healthmd.domain.model.WorkoutData(
            workoutType = com.healthmd.domain.model.WorkoutType.RUNNING,
            startTime = start.atZone(zone).toLocalDateTime(), endTime = end.atZone(zone).toLocalDateTime(),
            duration = kotlin.time.Duration.parse("3600.864197532s"), distance = 5000.875, calories = 320.125,
            averageHeartRate = 160.125, stepsCadenceAvg = 178.625, powerAvg = 240.125,
            exactStartTime = com.healthmd.domain.model.ExactSourceTimestamp.from(start, java.time.ZoneOffset.of("-04:00")),
            exactEndTime = com.healthmd.domain.model.ExactSourceTimestamp.from(end, java.time.ZoneOffset.of("-05:00")),
            identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-device-workout"))
        val data = HealthData(date = LocalDate.of(2026, 11, 1), workouts = listOf(workout))
        for (preference in listOf(com.healthmd.domain.model.UnitPreference.METRIC, com.healthmd.domain.model.UnitPreference.IMPERIAL)) {
            val request = FrozenDailyAggregateExportRequest.capture(data, ExportSettings(
                exportFormats = ExportFormat.entries.toSet(), includeGranularData = true, includeMetadata = false,
                formatCustomization = FormatCustomization(unitPreference = preference),
                metricSelection = com.healthmd.domain.model.MetricSelectionState(enabledMetrics = setOf("workouts")),
                executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true),
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                DailyAggregateExportIds("device-workout-${preference.name}", "device-workout-session-${preference.name}"))
            val result = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("cannot borrow an ambient clock") }).plan(request)
            assertEquals(AndroidExportProfile.android_sleep_v6, result.pin.profile)
            assertEquals(4, result.plan.items.size)
            for (item in result.plan.items) {
                val text = item.content.decodeToString()
                assertTrue(text.contains("android-sleep-v6"))
                assertTrue(text.contains("synthetic-device-workout"))
                assertTrue(text.contains("160.125"))
                assertTrue(text.contains("178.625"))
                assertTrue(text.contains("240.125"))
                assertTrue(text.contains(start.toString()))
                assertTrue(text.contains(end.toString()))
            }
        }
    }

    @Test
    fun packagedCorePlansExactNativeBytesForBothAndroidProfiles() = runBlocking {
        val day = HealthData(
            date = LocalDate.of(2026, 7, 25),
            activity = ActivityData(steps = 1234),
        )
        val planner = HealthMdRustDailyAggregatePlanner(
            zoneIdProvider = { ZoneId.of("UTC") },
        )
        for ((profile, customization) in listOf(
            AndroidExportProfile.android_frozen_v4 to FormatCustomization(
                compatibilitySchemaProfile = CompatibilitySchemaProfile.IOS_V4_FROZEN,
            ),
            AndroidExportProfile.android_analytical_v5 to FormatCustomization.analyticalDefault(),
        )) {
            val settings = ExportSettings(
                exportFormat = ExportFormat.MARKDOWN,
                exportFormats = setOf(
                    ExportFormat.MARKDOWN,
                    ExportFormat.OBSIDIAN_BASES,
                    ExportFormat.JSON,
                    ExportFormat.CSV,
                ),
                writeMode = WriteMode.OVERWRITE,
                formatCustomization = customization,
            )
            val request = FrozenDailyAggregateExportRequest.capture(
                data = day,
                settings = settings,
                profile = profile,
                mode = ExportEngineMode.rust,
                ids = DailyAggregateExportIds(
                    requestId = "android-production-seam-${profile.name}",
                    sessionId = "android-production-session-${profile.name}",
                ),
            )

            val result = planner.plan(request)

            assertEquals(ExportEngineMode.rust, result.pin.engine)
            assertEquals(profile, result.pin.profile)
            assertEquals(request.formats.map(request::relativePath), result.plan.items.map { it.relativePath })
            assertTrue(result.plan.items.all { it.writeMode == ExportArtifactWriteMode.overwrite })
            assertEquals(
                listOf(
                    MarkdownExporter().export(
                        day,
                        settings.includeMetadata,
                        settings.groupByCategory,
                        customization,
                        settings.includeGranularData,
                    ),
                    ObsidianBasesExporter().export(day, customization),
                    JsonExporter().export(day, customization, settings.includeGranularData),
                    CsvExporter().export(day, customization, settings.includeGranularData),
                ),
                result.plan.items.map { it.content.decodeToString() },
            )
        }
    }
}
