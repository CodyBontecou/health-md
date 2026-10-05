package com.healthmd.domain.exportengine

import com.google.common.truth.Truth.assertThat
import com.healthmd.core.HealthMdCoreService
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.WriteMode
import java.time.LocalDate
import java.time.ZoneId
import kotlinx.coroutines.runBlocking
import org.junit.Test

/** Real post-capture production chain; no provider query, destination or network is opened. */
class HistoricalExportRecoveryTest {
    @Test
    fun frozenScheduledAndDirectSettingsResumeOriginalAuthorityWithExactNativeBytes() = runBlocking {
        val service = HealthMdCoreService()
        val readiness = service.checkReadiness()
        val native = ProductionDailyAggregateNativePlanBuilder(MarkdownExporter(), JsonExporter(), CsvExporter(), ObsidianBasesExporter())
        for (profile in AndroidExportProfile.entries) {
            for (mode in listOf(ExportEngineMode.rust, ExportEngineMode.shadow)) {
                val current = service.getMetricRegistry(profile.coreProfile)
                val original = ExportEnginePin.create(mode, profile, "UTC", readiness, current).copy(
                    registrySha256 = ExportEnginePin.HISTORICAL_REGISTRY_SHA256,
                    renderProfileRevision = 2u,
                )
                val settings = ExportSettings(
                    exportFormat = ExportFormat.JSON,
                    exportFormats = setOf(ExportFormat.JSON),
                    writeMode = WriteMode.OVERWRITE,
                ).let { it.copy(formatCustomization = it.formatCustomization.copy(
                    compatibilitySchemaProfile = if (profile == AndroidExportProfile.android_frozen_v4) CompatibilitySchemaProfile.IOS_V4_FROZEN else CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5,
                )) }
                val snapshot = AndroidExportSettingsSnapshot.capture(settings, original, ZoneId.of("UTC"))
                val restored = AndroidExportSettingsSnapshotCodec.decode(AndroidExportSettingsSnapshotCodec.encodeCanonical(snapshot)).restoreOnto(ExportSettings())
                assertThat(restored.executionEnginePin).isEqualTo(original)
                val data = HealthData(LocalDate.of(2026, 3, 15), activity = ActivityData(steps = 1234))
                val ids = DailyAggregateExportIds("historical-request", "historical-session")
                val request = FrozenDailyAggregateExportRequest.capture(data, restored, profile, mode, ids)
                val historicalPlan = HealthMdRustDailyAggregatePlanner(coreService = service).plan(request)
                assertThat(historicalPlan.pin).isEqualTo(original)
                val expected = native.plan(request)
                assertThat(historicalPlan.plan.items.single().content).isEqualTo(expected.items.single().content)
                val planner = AndroidDailyAggregateExportPlanner(nativePlanner = native, idSource = DailyAggregateExportIdSource { ids })
                val resumed = planner.plan(data, restored) as LocalDailyAggregatePlanningResult.Planned
                assertThat(resumed.mode).isEqualTo(mode)
                assertThat(resumed.plan.items.single().content).isEqualTo(expected.items.single().content)
                val unknown = restored.copy(executionEnginePin = original.copy(engine = ExportEngineMode.rust, registrySha256 = "0".repeat(64)))
                assertThat(planner.plan(data, unknown)).isEqualTo(LocalDailyAggregatePlanningResult.Failed(ExportEngineMode.rust))
            }
        }
    }
}
