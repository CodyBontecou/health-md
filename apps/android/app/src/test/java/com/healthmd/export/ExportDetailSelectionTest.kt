package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.model.ExactSourceTimestamp
import com.healthmd.domain.model.ExportDetailChoice
import com.healthmd.domain.model.ExportDetailGroup
import com.healthmd.domain.model.ExportDetailOverrides
import com.healthmd.domain.model.ExportDetailSelection
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HeartData
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.domain.model.MetricTrackingConfig
import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.SleepSessionEntry
import com.healthmd.domain.model.SleepStageEntry
import com.healthmd.domain.model.TimestampedSample
import com.healthmd.domain.model.VitalsData
import com.healthmd.testing.syntheticExportEnginePin
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.minutes
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

/**
 * Per-group detail selection: legacy equivalence, mixed policies, sleep sessions independent of
 * stages, durable snapshot round-trips, and fail-closed handling of unknown overrides.
 */
class ExportDetailSelectionTest {
    private val berlin: ZoneId = ZoneId.of("Europe/Berlin")

    private fun exact(local: LocalDateTime): ExactSourceTimestamp {
        val instant = local.atZone(berlin).toInstant()
        return ExactSourceTimestamp.from(instant, berlin.rules.getOffset(instant))
    }

    /**
     * Tobias-shaped day: an afternoon nap plus an overnight session that crosses midnight and the
     * 2026-10-25 Europe/Berlin DST fall-back (03:00 CEST -> 02:00 CET).
     */
    private val napAndNight: HealthData = run {
        val napStart = LocalDateTime.of(2026, 10, 24, 14, 54)
        val napEnd = LocalDateTime.of(2026, 10, 24, 15, 40)
        val nightStart = LocalDateTime.of(2026, 10, 24, 23, 30)
        val nightEnd = LocalDateTime.of(2026, 10, 25, 7, 15)
        HealthData(
            date = LocalDate.of(2026, 10, 24),
            sleep = SleepData(
                totalDuration = 9.hours + 31.minutes,
                inBedTime = 9.hours + 31.minutes,
                deepSleep = 1.hours,
                sessionStart = napStart,
                sessionEnd = nightEnd,
                sessions = listOf(
                    SleepSessionEntry(napStart, napEnd, source = "com.example.watch",
                        exactStartTime = exact(napStart), exactEndTime = exact(napEnd)),
                    SleepSessionEntry(nightStart, nightEnd, title = "Night", source = "com.example.watch",
                        exactStartTime = exact(nightStart), exactEndTime = exact(nightEnd)),
                ),
                stages = listOf(
                    SleepStageEntry(nightStart, nightStart.plusHours(1), "deep"),
                ),
            ),
            heart = HeartData(
                averageHeartRate = 61.0,
                samples = listOf(TimestampedSample(LocalDateTime.of(2026, 10, 24, 9, 0), 58.0)),
                hrvSamples = listOf(TimestampedSample(LocalDateTime.of(2026, 10, 24, 9, 0), 41.0)),
            ),
            vitals = VitalsData(
                bloodOxygenAvg = 0.97,
                bloodOxygenSamples = listOf(TimestampedSample(LocalDateTime.of(2026, 10, 24, 9, 0), 0.97)),
            ),
        )
    }

    private val sleepDetailedOnly = ExportSettings()
        .withDetailChoice(ExportDetailGroup.SLEEP, ExportDetailChoice.DETAILED)

    private fun json(data: HealthData, detail: ExportDetailSelection) =
        Json.parseToJsonElement(JsonExporter().export(data, FormatCustomization(), detail = detail)).jsonObject

    @Test
    fun missingOverridesReproduceTheHistoricalBooleanExactly() {
        for (granular in listOf(false, true)) {
            val settings = ExportSettings(includeGranularData = granular)
            assertThat(settings.exportDetailSelection()).isEqualTo(ExportDetailSelection.uniform(granular))
            // Persisted settings from before this feature decode with no overrides.
            val decoded = Json { ignoreUnknownKeys = true }
                .decodeFromString(ExportSettings.serializer(), """{"includeGranularData":$granular}""")
            assertThat(decoded.detailOverrides).isEmpty()
            assertThat(decoded.exportDetailSelection()).isEqualTo(ExportDetailSelection.uniform(granular))
        }
    }

    @Test
    fun uniformSelectionRendersByteIdenticalToTheHistoricalBoolean() {
        for (granular in listOf(false, true)) {
            val detail = ExportSettings(includeGranularData = granular).exportDetailSelection()
            assertThat(JsonExporter().export(napAndNight, FormatCustomization(), detail = detail))
                .isEqualTo(JsonExporter().export(napAndNight, FormatCustomization(), granular))
            assertThat(CsvExporter().export(napAndNight, FormatCustomization(), detail = detail))
                .isEqualTo(CsvExporter().export(napAndNight, FormatCustomization(), granular))
            assertThat(MarkdownExporter().export(napAndNight, detail = detail))
                .isEqualTo(MarkdownExporter().export(napAndNight, includeGranularData = granular))
        }
    }

    @Test
    fun detailedSleepWithSummarizedHeartAndVitals() {
        val root = json(napAndNight, sleepDetailedOnly.exportDetailSelection())
        val sleep = root.getValue("sleep").jsonObject
        assertThat(sleep.getValue("sleepSessions").jsonArray).hasSize(2)
        assertThat(sleep.getValue("sleepStages").jsonArray).hasSize(1)
        val heart = root.getValue("heart").jsonObject
        assertThat(heart.keys).containsNoneOf("heartRateSamples", "hrvSamples")
        assertThat(root.getValue("vitals").jsonObject.keys).doesNotContain("bloodOxygenSamples")

        val csv = CsvExporter().export(napAndNight, FormatCustomization(), detail = sleepDetailedOnly.exportDetailSelection())
        assertThat(csv).contains("Sleep Stage")
        assertThat(csv).doesNotContain("Heart Rate Sample")
        assertThat(csv).doesNotContain("Blood Oxygen Sample")
    }

    @Test
    fun sleepSessionsWithoutStagesOrOtherDetail() {
        val settings = ExportSettings().withDetailChoice(ExportDetailGroup.SLEEP, ExportDetailChoice.SESSIONS)
        val detail = settings.exportDetailSelection()
        assertThat(detail.sleepSessions).isTrue()
        assertThat(detail.sleepStages).isFalse()
        assertThat(detail.copy(sleepSessions = false, sleepSessionList = false)).isEqualTo(ExportDetailSelection.SUMMARY)

        val sleep = json(napAndNight, detail).getValue("sleep").jsonObject
        assertThat(sleep.getValue("sleepSessions").jsonArray.map {
            it.jsonObject.getValue("startTimeISO").jsonPrimitive.content
        }).containsExactly("2026-10-24T14:54:00", "2026-10-24T23:30:00").inOrder()
        assertThat(sleep.keys).doesNotContain("sleepStages")
    }

    @Test
    fun summaryValuesDoNotChangeWithDetailSelection() {
        fun summaryOnly(detail: ExportDetailSelection) = json(napAndNight, detail).mapValues { (_, section) ->
            (section as? JsonObject)?.filterKeys { !it.endsWith("Samples") && it !in setOf("sleepSessions", "sleepStages") }
                ?: section
        }
        val baseline = summaryOnly(ExportDetailSelection.SUMMARY)
        assertThat(summaryOnly(sleepDetailedOnly.exportDetailSelection())).isEqualTo(baseline)
        assertThat(summaryOnly(ExportDetailSelection.UNIFORM_DETAILED)).isEqualTo(baseline)
    }

    @Test
    fun markdownListsSeparateSessionsWithFullDateTimeOffsetAndDstSafeDuration() {
        val settings = ExportSettings().withDetailChoice(ExportDetailGroup.SLEEP, ExportDetailChoice.SESSIONS)
        val markdown = MarkdownExporter().export(napAndNight, detail = settings.exportDetailSelection())
        assertThat(markdown).contains("| Session start | Session end | Duration | Source |")
        assertThat(markdown).contains("| 2026-10-24 14:54 (UTC+02:00) | 2026-10-24 15:40 (UTC+02:00) |")
        // The overnight session ends on the next date and after the DST fall-back.
        assertThat(markdown).contains("| 2026-10-24 23:30 (UTC+02:00) | 2026-10-25 07:15 (UTC+01:00) |")
        // 23:30 CEST -> 07:15 CET is 8h45m elapsed, not the 7h45m local wall-clock difference.
        assertThat(markdown).contains("8h 45m")
        assertThat(markdown).contains("Night · com.example.watch")
        // Sessions-only never renders the stage table.
        assertThat(markdown).doesNotContain("| Start | End | Stage |")
    }

    @Test
    fun globalDetailKeepsHistoricalMarkdownWithoutSessionList() {
        val markdown = MarkdownExporter().export(napAndNight, detail = ExportSettings(includeGranularData = true).exportDetailSelection())
        assertThat(markdown).doesNotContain("Session start")
        assertThat(markdown).contains("| Start | End | Stage |")
    }

    @Test
    fun explicitSummaryOverrideSuppressesOneGroupUnderGlobalDetail() {
        val settings = ExportSettings(includeGranularData = true)
            .withDetailChoice(ExportDetailGroup.HEART, ExportDetailChoice.SUMMARY)
        val root = json(napAndNight, settings.exportDetailSelection())
        assertThat(root.getValue("heart").jsonObject.keys).containsNoneOf("heartRateSamples", "hrvSamples")
        assertThat(root.getValue("vitals").jsonObject.keys).contains("bloodOxygenSamples")
        assertThat(root.getValue("sleep").jsonObject.keys).containsAtLeast("sleepSessions", "sleepStages")
    }

    @Test
    fun explicitChoicesSurviveDefaultChanges() {
        val settings = ExportSettings()
            .withDetailChoice(ExportDetailGroup.SLEEP, ExportDetailChoice.DETAILED)
            .copy(includeGranularData = true)
            .copy(includeGranularData = false)
        assertThat(settings.exportDetailSelection().sleepStages).isTrue()
        assertThat(settings.exportDetailSelection().heart).isFalse()
        assertThat(settings.withDetailChoice(ExportDetailGroup.SLEEP, null).detailOverrides).isEmpty()
    }

    @Test
    fun unsupportedChoicesAreRejected() {
        assertThat(ExportDetailOverrides.validated(mapOf("heart" to "sessions"))).isNull()
        assertThat(ExportDetailOverrides.validated(mapOf("steps" to "detailed"))).isNull()
        assertThat(ExportDetailOverrides.validated(mapOf("sleep" to "verbose"))).isNull()
        assertThat(ExportDetailOverrides.validated(mapOf("sleep" to "sessions")))
            .containsExactly(ExportDetailGroup.SLEEP, ExportDetailChoice.SESSIONS)
        // A live preference written by a newer build keeps only entries this build understands.
        val settings = ExportSettings(detailOverrides = mapOf("sleep" to "sessions", "future_group" to "detailed"))
        assertThat(settings.typedDetailOverrides()).containsExactly(ExportDetailGroup.SLEEP, ExportDetailChoice.SESSIONS)
    }

    @Test
    fun captureReadsTrackingDetailWithoutExportingIt() {
        val tracking = IndividualTrackingSettings(
            globalEnabled = true,
            metricConfigs = mapOf("avg_hr" to MetricTrackingConfig(trackIndividually = true)),
        )
        val settings = sleepDetailedOnly.copy(individualTracking = tracking)
        assertThat(settings.exportDetailSelection().heart).isFalse()
        assertThat(settings.captureDetailSelection().heart).isTrue()
        assertThat(settings.captureDetailSelection().vitals).isFalse()
        assertThat(settings.captureDetailSelection().workouts).isFalse()
        assertThat(settings.shouldFetchGranularData()).isTrue()
        // Summary everywhere and no tracking requests no detail reads at all.
        assertThat(ExportSettings().captureDetailSelection()).isEqualTo(ExportDetailSelection.SUMMARY)
    }

    @Test
    fun snapshotWithoutOverridesKeepsHistoricalCanonicalBytes() {
        val pin = syntheticExportEnginePin(zoneId = "UTC")
        val canonical = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(ExportSettings(includeGranularData = true), pin, ZoneId.of("UTC")),
        )
        assertThat(canonical).doesNotContain("detailOverrides")
        val restored = AndroidExportSettingsSnapshotCodec.decode(canonical).restoreOnto(ExportSettings())
        assertThat(restored.exportDetailSelection()).isEqualTo(ExportDetailSelection.UNIFORM_DETAILED)
    }

    @Test
    fun snapshotRoundTripsOverridesForScheduledRetriesAndProfiles() {
        val pin = syntheticExportEnginePin(zoneId = "UTC")
        val settings = ExportSettings()
            .withDetailChoice(ExportDetailGroup.SLEEP, ExportDetailChoice.SESSIONS)
            .withDetailChoice(ExportDetailGroup.HEART, ExportDetailChoice.SUMMARY) // explicit, kept
        val canonical = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(settings, pin, ZoneId.of("UTC")),
        )
        assertThat(canonical).contains("\"detailOverrides\":{\"heart\":\"summary\",\"sleep\":\"sessions\"}")
        // Recovery applies the frozen choice even if the live preference later changes.
        val restored = AndroidExportSettingsSnapshotCodec.decode(canonical)
            .restoreOnto(ExportSettings(includeGranularData = true))
        assertThat(restored.exportDetailSelection()).isEqualTo(settings.exportDetailSelection())
    }

    @Test
    fun explicitSleepDetailUnderGlobalDetailKeepsSessionListThroughRetries() {
        // Equal to the default, yet it carries the Markdown session-list request.
        val settings = ExportSettings(includeGranularData = true)
            .withDetailChoice(ExportDetailGroup.SLEEP, ExportDetailChoice.DETAILED)
        assertThat(settings.exportDetailSelection().sleepSessionList).isTrue()
        val canonical = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(settings, syntheticExportEnginePin(zoneId = "UTC"), ZoneId.of("UTC")),
        )
        val restored = AndroidExportSettingsSnapshotCodec.decode(canonical).restoreOnto(ExportSettings())
        assertThat(restored.exportDetailSelection()).isEqualTo(settings.exportDetailSelection())
        assertThat(MarkdownExporter().export(napAndNight, detail = restored.exportDetailSelection()))
            .isEqualTo(MarkdownExporter().export(napAndNight, detail = settings.exportDetailSelection()))
    }

    @Test
    fun corruptOrUnknownSnapshotOverridesFailClosed() {
        val pin = syntheticExportEnginePin(zoneId = "UTC")
        val canonical = AndroidExportSettingsSnapshotCodec.encodeCanonical(
            AndroidExportSettingsSnapshot.capture(
                ExportSettings().withDetailChoice(ExportDetailGroup.SLEEP, ExportDetailChoice.SESSIONS), pin, ZoneId.of("UTC"),
            ),
        )
        for (tampered in listOf(
            canonical.replace("\"sleep\":\"sessions\"", "\"heart\":\"sessions\""),
            canonical.replace("\"sleep\":\"sessions\"", "\"future\":\"detailed\""),
            canonical.replace("{\"sleep\":\"sessions\"}", "{}"),
        )) {
            assertThat(AndroidExportSettingsSnapshotCodec.decodeOrNull(tampered)).isNull()
        }
    }

    @Test
    fun uniformDetailedRequiresEveryGroup() {
        assertThat(ExportDetailSelection.uniform(true).isUniformDetailed).isTrue()
        assertThat(sleepDetailedOnly.exportDetailSelection().isUniformDetailed).isFalse()
        assertThat(ExportDetailSelection.resolve(true, emptyMap())).isEqualTo(ExportDetailSelection.UNIFORM_DETAILED)
        assertThat(ExportDetailSelection.resolve(false, emptyMap())).isEqualTo(ExportDetailSelection.SUMMARY)
        assertThat(ZoneOffset.UTC.id).isEqualTo("Z")
    }
}
