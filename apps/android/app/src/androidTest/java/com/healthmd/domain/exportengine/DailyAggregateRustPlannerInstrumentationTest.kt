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
