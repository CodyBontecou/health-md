package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.exportengine.AndroidExportProfile
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotException
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.ExportEnginePinPlanner
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.DailyRecordSchemaProfile
import com.healthmd.domain.model.ExportDetailChoice
import com.healthmd.domain.model.ExportDetailGroup
import com.healthmd.domain.model.ExportDetailSelection
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.testing.syntheticExportEnginePin
import java.time.ZoneId
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertThrows
import org.junit.Test

/**
 * android-analytical-v7: selection rules, wire shape of the new arrays in every format, and the
 * native-writer-only engine contract. Frozen v4/v5 fixtures are guarded by
 * [ExporterSchemaSignatureTest].
 */
class AnalyticalV7ExportTest {
    private val analytical = ExportSettings(formatCustomization = FormatCustomization.analyticalDefault())
    private val data = ExportSignatureFixtures.syntheticDayV7
    private val customization = FormatCustomization.analyticalDefault()

    private fun ExportSettings.detailed(group: ExportDetailGroup) = withDetailChoice(group, ExportDetailChoice.DETAILED)

    private val v7Settings = analytical.detailed(ExportDetailGroup.ACTIVITY)
        .detailed(ExportDetailGroup.NUTRITION).detailed(ExportDetailGroup.BODY)
    private val v7Detail = v7Settings.exportDetailSelection()

    @Test
    fun explicitExpansionOverrideOnTheAnalyticalProfileSelectsV7() {
        for (group in ExportDetailSelection.ANALYTICAL_EXPANSION_GROUPS) {
            val settings = analytical.detailed(group)
            assertThat(settings.dailyRecordSchemaProfile()).isEqualTo(DailyRecordSchemaProfile.ANDROID_ANALYTICAL_V7)
            assertThat(settings.exportDetailSelection().analyticalExpansion).isTrue()
            assertThat(settings.captureDetailSelection().analyticalExpansion).isTrue()
            // Also under the uniform default: only the explicit override matters.
            assertThat(settings.copy(includeGranularData = true).dailyRecordSchemaProfile())
                .isEqualTo(DailyRecordSchemaProfile.ANDROID_ANALYTICAL_V7)
        }
    }

    @Test
    fun uniformDetailAndOtherGroupsStayV5() {
        for (granular in listOf(false, true)) {
            val settings = analytical.copy(includeGranularData = granular)
            assertThat(settings.dailyRecordSchemaProfile()).isEqualTo(DailyRecordSchemaProfile.ANDROID_ANALYTICAL_V5)
            assertThat(settings.exportDetailSelection()).isEqualTo(ExportDetailSelection.uniform(granular))
        }
        for (group in ExportDetailGroup.entries - ExportDetailSelection.ANALYTICAL_EXPANSION_GROUPS) {
            val choice = group.supportedChoices.last()
            assertThat(analytical.withDetailChoice(group, choice).dailyRecordSchemaProfile())
                .isEqualTo(DailyRecordSchemaProfile.ANDROID_ANALYTICAL_V5)
        }
        // Explicit summary for an expansion group is not a v7 request.
        assertThat(analytical.copy(includeGranularData = true)
            .withDetailChoice(ExportDetailGroup.BODY, ExportDetailChoice.SUMMARY).dailyRecordSchemaProfile())
            .isEqualTo(DailyRecordSchemaProfile.ANDROID_ANALYTICAL_V5)
    }

    @Test
    fun frozenV4NeverUpgradesAndMorningEndsStaysV6() {
        val frozen = ExportSettings().detailed(ExportDetailGroup.ACTIVITY).detailed(ExportDetailGroup.BODY)
        assertThat(frozen.dailyRecordSchemaProfile()).isEqualTo(DailyRecordSchemaProfile.ANDROID_FROZEN_V4)
        assertThat(frozen.exportDetailSelection().analyticalExpansion).isFalse()
        assertThat(frozen.captureDetailSelection().analyticalExpansion).isFalse()
        assertThat(frozen.exportDetailSelection().body).isTrue()

        val morning = v7Settings.copy(
            executionSleepCaptureContext = AndroidCaptureContext(ZoneId.of("UTC"), SleepDayAttribution.MORNING_ENDS),
        )
        assertThat(morning.dailyRecordSchemaProfile()).isEqualTo(DailyRecordSchemaProfile.ANDROID_SLEEP_V6)
        assertThat(morning.exportDetailSelection().analyticalExpansion).isFalse()
        assertThat(morning.captureDetailSelection().analyticalExpansion).isFalse()
        // The frozen API v1 writer customization never emits v7.
        assertThat(DailyRecordSchemaProfile.forWriter(customization.forFrozenApiV4(), v7Detail))
            .isEqualTo(DailyRecordSchemaProfile.ANDROID_FROZEN_V4)
    }

    private fun json(detail: ExportDetailSelection, custom: FormatCustomization = customization): JsonObject =
        Json.parseToJsonElement(JsonExporter().export(data, custom, detail = detail)).jsonObject

    @Test
    fun jsonV7HeaderAndArraysPreserveExactRecords() {
        val root = json(v7Detail)
        assertThat(root.getValue("schemaProfile").jsonPrimitive.content).isEqualTo("android-analytical-v7")
        assertThat(root.getValue("schemaVersion").jsonPrimitive.content).isEqualTo("7")
        val activity = root.getValue("activity").jsonObject
        for (name in listOf("activeCaloriesSamples", "totalCaloriesSamples", "distanceSamples", "floorsSamples", "elevationSamples")) {
            assertThat(activity[name]).isNotNull()
        }
        val active = activity.getValue("activeCaloriesSamples").jsonArray.single().jsonObject
        assertThat(active.keys).containsAtLeast("timestamp", "value", "source", "metadata", "exactTime", "exactEndTime", "identity")
        assertThat(active.getValue("value").jsonPrimitive.content).isEqualTo("45.5")
        assertThat(active.getValue("exactTime").jsonObject.getValue("offset").jsonPrimitive.content).isEqualTo("-04:00")
        assertThat(active.getValue("exactTime").jsonObject.getValue("nano").jsonPrimitive.content).isEqualTo("123456789")
        assertThat(active.getValue("identity").jsonObject.getValue("nativeId").jsonPrimitive.content).isEqualTo("synthetic-native-id")

        val body = root.getValue("body").jsonObject
        val weight = body.getValue("weightSamples").jsonArray.single().jsonObject
        assertThat(weight.keys).doesNotContain("exactEndTime")
        assertThat(weight.getValue("value").jsonPrimitive.content).isEqualTo("75.5")
        assertThat(body.getValue("bodyFatSamples").jsonArray.single().jsonObject.getValue("value").jsonPrimitive.content)
            .isEqualTo("0.185")
        for (name in listOf("heightSamples", "leanBodyMassSamples", "boneMassSamples", "bodyWaterMassSamples")) {
            assertThat(body[name]).isNotNull()
        }
        val hydration = root.getValue("nutrition").jsonObject.getValue("hydrationSamples").jsonArray.single().jsonObject
        assertThat(hydration.getValue("value").jsonPrimitive.content).isEqualTo("0.25")
        assertThat(hydration.keys).contains("exactEndTime")
    }

    @Test
    fun v7ArraysFollowTheirGroupAndSummariesNeverChange() {
        val activityOnly = analytical.detailed(ExportDetailGroup.ACTIVITY).exportDetailSelection()
        val root = json(activityOnly)
        assertThat(root.getValue("schemaVersion").jsonPrimitive.content).isEqualTo("7")
        assertThat(root.getValue("activity").jsonObject["distanceSamples"]).isNotNull()
        assertThat(root.getValue("body").jsonObject["weightSamples"]).isNull()
        assertThat(root.getValue("nutrition").jsonObject["hydrationSamples"]).isNull()

        // Daily summary values are identical to the v5 rendering of the same day.
        val v5 = json(ExportDetailSelection.UNIFORM_DETAILED)
        assertThat(v5.getValue("schemaProfile").jsonPrimitive.content).isEqualTo("android-analytical-v5")
        val expansion = setOf(
            "activeCaloriesSamples", "totalCaloriesSamples", "distanceSamples", "floorsSamples", "elevationSamples",
            "weightSamples", "heightSamples", "bodyFatSamples", "leanBodyMassSamples", "boneMassSamples",
            "bodyWaterMassSamples", "hydrationSamples",
        )
        for (section in listOf("activity", "body", "nutrition")) {
            assertThat(v5.getValue(section).jsonObject.keys.intersect(expansion)).isEmpty()
            val v7Keys = json(ExportDetailSelection.UNIFORM_DETAILED.copy(analyticalExpansion = true)).getValue(section).jsonObject.filterKeys { it !in expansion }
            assertThat(v7Keys).isEqualTo(v5.getValue(section).jsonObject.toMap())
        }
        // Frozen v4 ignores the expansion even if detail and data request it.
        val frozen = json(v7Detail, FormatCustomization())
        assertThat(frozen["schemaVersion"]).isNull()
        assertThat(frozen.getValue("activity").jsonObject.keys.intersect(expansion)).isEmpty()
    }

    @Test
    fun csvV7RowsUseCanonicalUnitsAndExactStartTimestamps() {
        val csv = CsvExporter().export(data, customization, detail = v7Detail)
        val lines = csv.lines()
        assertThat(lines).contains("2026-03-15,Metadata,Schema Profile,android-analytical-v7,,")
        val start = "2026-03-15T06:00:00.123456789-04:00"
        assertThat(lines).containsAtLeast(
            "2026-03-15,Activity,Active Calories Sample,45.5,kcal,$start",
            "2026-03-15,Activity,Total Calories Sample,120.5,kcal,$start",
            "2026-03-15,Activity,Distance Sample,850.5,meters,$start",
            "2026-03-15,Activity,Flights Climbed Sample,2.0,count,$start",
            "2026-03-15,Activity,Elevation Gained Sample,6.5,meters,$start",
            "2026-03-15,Body,Weight Sample,75.5,kg,$start",
            "2026-03-15,Body,Height Sample,1.78,meters,$start",
            "2026-03-15,Body,Body Fat Percentage Sample,18.5,percent,$start",
            "2026-03-15,Body,Lean Body Mass Sample,60.5,kg,$start",
            "2026-03-15,Body,Bone Mass Sample,3.2,kg,$start",
            "2026-03-15,Body,Body Water Mass Sample,45.5,kg,$start",
            "2026-03-15,Nutrition,Water Sample,0.25,L,$start",
        )
        val v5 = CsvExporter().export(data, customization, includeGranularData = true)
        assertThat(v5).doesNotContain(" Sample,45.5,kcal")
        assertThat(v5).contains("Schema Profile,android-analytical-v5")
    }

    @Test
    fun markdownV7FrontmatterAndRecordTables() {
        val markdown = MarkdownExporter().export(data, customization = customization, detail = v7Detail)
        assertThat(markdown).contains("healthmd_schema_profile: android-analytical-v7\n")
        for (header in listOf(
            "| Time | Active Calories (kcal) |", "| Time | Total Calories (kcal) |", "| Time | Distance (m) |",
            "| Time | Flights Climbed |", "| Time | Elevation Gained (m) |", "| Time | Weight (kg) |",
            "| Time | Height (m) |", "| Time | Body Fat (%) |", "| Time | Lean Body Mass (kg) |",
            "| Time | Bone Mass (kg) |", "| Time | Body Water Mass (kg) |", "| Time | Water (L) |",
        )) {
            assertThat(markdown).contains(header)
        }
        assertThat(markdown).contains("| 18.5 |")
        assertThat(markdown).contains("| 0.25 |")
        val v5 = MarkdownExporter().export(data, customization = customization, includeGranularData = true)
        assertThat(v5).contains("healthmd_schema_profile: android-analytical-v5\n")
        assertThat(v5).doesNotContain("Active Calories (kcal) |")
        // Bases carries no record arrays and keeps the v5 identity, like daily notes.
        assertThat(ObsidianBasesExporter().export(data, customization)).contains("healthmd_schema_profile: android-analytical-v5")
    }

    @Test
    fun deselectedMetricsDropTheirRecordArrays() {
        val selection = MetricSelectionState(enabledMetrics = setOf("steps", "weight"))
        val filtered = data.filtered(selection)
        assertThat(filtered.body.weightSamples).hasSize(1)
        assertThat(filtered.body.heightSamples).isEmpty()
        assertThat(filtered.activity.hasDetailExpansion).isFalse()
        assertThat(filtered.nutrition.hydrationSamples).isEmpty()
    }

    @Test
    fun v7IsNativeWriterOnlyForPinsAndDurableSnapshots() {
        val zone = ZoneId.of("UTC")
        val planner = ExportEnginePinPlanner()
        assertThat(planner.forScheduledExport(v7Settings, ExportTarget.DEVICE_FOLDER, zone)).isNull()
        assertThat(planner.forDirectGeneratedFiles(v7Settings, zone)).isNull()
        val rustPin = syntheticExportEnginePin(ExportEngineMode.rust, AndroidExportProfile.android_analytical_v5, "UTC")
        assertThat(planner.persistedPinAppliesToScheduledExport(v7Settings, ExportTarget.DEVICE_FOLDER, rustPin)).isFalse()
        assertThat(planner.persistedPinAppliesToScheduledExport(v7Settings, ExportTarget.DEVICE_FOLDER, null)).isTrue()

        // A snapshot cannot pair v7 with a Rust pin; without a pin it round-trips and stays v7.
        assertThrows(AndroidExportSettingsSnapshotException::class.java) {
            AndroidExportSettingsSnapshot.capture(v7Settings, rustPin, zone)
        }
        val v5Bytes = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(analytical.copy(includeGranularData = true), rustPin, zone),
        )
        // Tampering a pinned v5 snapshot into a v7 request is rejected on decode.
        val tampered = v5Bytes.replace("\"includeGranularData\":true", "\"detailOverrides\":{\"body\":\"detailed\"},\"includeGranularData\":true")
        assertThat(tampered).isNotEqualTo(v5Bytes)
        assertThat(AndroidExportSettingsSnapshotCodec.decodeOrNull(tampered)).isNull()
        val legacy = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(v7Settings, null, zone),
        )
        assertThat(legacy).contains("\"body\":\"detailed\"")
        val restored = AndroidExportSettingsSnapshotCodec.decode(legacy).restoreOnto(ExportSettings())
        assertThat(restored.dailyRecordSchemaProfile()).isEqualTo(DailyRecordSchemaProfile.ANDROID_ANALYTICAL_V7)
        assertThat(restored.exportDetailSelection()).isEqualTo(v7Detail)
        // v5 snapshots with a Rust pin remain valid.
        val v5Pinned = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(analytical.copy(includeGranularData = true), rustPin, zone),
        )
        assertThat(AndroidExportSettingsSnapshotCodec.decodeOrNull(v5Pinned)).isNotNull()
        assertThat(CompatibilitySchemaProfile.entries).hasSize(2)
    }
}
