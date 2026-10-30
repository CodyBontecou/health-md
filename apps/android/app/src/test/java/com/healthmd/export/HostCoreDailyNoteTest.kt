package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.DailyNoteInjector
import com.healthmd.data.export.InjectionResult
import com.healthmd.data.export.PreparedWakeDateDailyNote
import com.healthmd.domain.exportengine.DailyAggregateExportIds
import com.healthmd.domain.exportengine.DailyAggregateRustPlanner
import com.healthmd.domain.exportengine.HealthMdRustDailyAggregatePlanner
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.CustomFrontmatterField
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.model.ExactSourceTimestamp
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.FrontmatterConfiguration
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.MarkdownTemplateConfig
import com.healthmd.domain.model.MarkdownTemplateStyle
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.SleepDayAttribution
import com.healthmd.domain.model.SleepSessionEntry
import com.healthmd.domain.model.SleepStageEntry
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.time.Duration.Companion.seconds
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.double
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.long
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Test

class HostCoreDailyNoteTest {
    private val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
    private val date = LocalDate.of(2026, 3, 8)

    @Before fun useExplicitHostLibrary() {
        val path = System.getenv("HEALTHMD_HOST_CORE_LIBRARY")
        assumeTrue("Requires a freshly built task-owned host core", !path.isNullOrBlank())
        require(File(requireNotNull(path)).isFile)
        System.setProperty("uniffi.component.healthmd_core_uniffi.libraryOverride", path)
    }

    @Test fun acceptedCaptureSurvivesMutationAndPreservesPersonalYaml() = runTest {
        for (sections in listOf(false,true)) {
            val metrics = mutableSetOf("steps","sleep_total","sleep_light")
            val fields = mutableListOf(CustomFrontmatterField("steps","My steps",false))
            val settings = settings(sections).copy(metricSelection = MetricSelectionState(enabledMetrics = metrics),
                formatCustomization = FormatCustomization(frontmatterConfig = FrontmatterConfiguration(
                    fields = fields,customFields = mapOf("My steps" to "wrong custom value")),
                    markdownTemplate = MarkdownTemplateConfig(style = MarkdownTemplateStyle.COMPACT)))
            val real = HealthMdRustDailyAggregatePlanner()
            val planner = DailyAggregateRustPlanner { request ->
                metrics.clear(); fields.clear()
                real.plan(request)
            }
            val prepared = PreparedWakeDateDailyNote.prepare(source(),settings,DailyAggregateExportIds("note-$sections","note-session-$sections"),planner=planner)
            assertThat(prepared.ownerDate).isEqualTo(date)
            assertThat(prepared.relativePath).isEqualTo("Daily/2026-03-08.md")
            val personal = "---\r\nschema: personal.journal\r\ndate: 1999-01-01\r\nsleep_deep_hours: 9 # history\r\nnotes: |\r\n  Keep my: multiline text\r\n---\r\nMy introduction.\r\n## Journal\r\nKeep this section.\r\n"
            val (result,content) = DailyNoteInjector().injectPrepared(personal,prepared)
            assertThat(result).isEqualTo(InjectionResult.UPDATED)
            val note = requireNotNull(content)
            assertThat(note).contains("schema: personal.journal\r\n")
            assertThat(note).contains("notes: |\r\n  Keep my: multiline text\r\n")
            assertThat(note).contains("sleep_deep_hours: 9 # history\r\n")
            assertThat(note).contains("My introduction.")
            assertThat(note).contains("Keep this section.")
            assertThat(note.contains("My steps: 42") || note.contains("\"My steps\": 42")).isTrue()
            assertThat(note.contains("## Activity")).isEqualTo(sections)
            val value = note.lineSequence().first { it.startsWith("healthmd_daily_injection_v1:") }.substringAfter(':').trim()
            val envelope = Json.parseToJsonElement(Json.decodeFromString<String>(value)).jsonObject
            val recordText = requireNotNull(envelope["record_json"]).jsonPrimitive.content
            val record = Json.parseToJsonElement(recordText).jsonObject
            assertThat(record["schema_profile"]?.jsonPrimitive?.content).isEqualTo("android-sleep-v6")
            assertThat(record["date"]?.jsonPrimitive?.content).isEqualTo("2026-03-08")
            val sleep = requireNotNull(record["sleep"]).jsonObject
            assertThat(sleep["totalDuration"]?.jsonPrimitive?.double).isEqualTo(93600.5)
            assertThat(sleep["lightSleep"]?.jsonPrimitive?.double).isEqualTo(93600.5)
            assertThat(sleep["coreSleep"]).isNull()
            assertThat(sleep["deepSleep"]).isNull()
            assertThat(sleep["sleepStages"]?.jsonArray?.size ?: 0).isEqualTo(if(sections) 1 else 0)
            assertThat(record["activity"]?.jsonObject?.get("steps")?.jsonPrimitive?.long).isEqualTo(42L)
            assertThat(DailyNoteInjector().injectPrepared("---\nschema: healthmd.health_data\n---\nOriginal",prepared).first)
                .isEqualTo(InjectionResult.FAILED)
            val (created, newNote) = DailyNoteInjector().injectPrepared(null,prepared)
            assertThat(created).isEqualTo(InjectionResult.CREATED)
            assertThat(newNote).contains("# 2026-03-08")
            System.getenv("HEALTHMD_ANDROID_DAILY_NOTE_FIXTURE_DIR")?.let { directory ->
                File(directory).mkdirs()
                File(directory,"android-$sections.md").writeText(note)
                File(directory,"android-$sections.json").writeText(recordText)
            }
        }
    }

    @Test fun skipMissingNotesAndRejectUnsafePathsBeforeRendering() = runTest {
        val prepared = PreparedWakeDateDailyNote.prepare(source(),settings(false).copy(
            dailyNoteInjection = DailyNoteInjectionSettings(enabled=true,createIfMissing=false)),DailyAggregateExportIds("skip-note","skip-session"))
        assertThat(DailyNoteInjector().injectPrepared(null,prepared)).isEqualTo(InjectionResult.SKIPPED to null)
        var calls = 0
        val never = DailyAggregateRustPlanner { calls++; error("must not render") }
        for (injection in listOf(DailyNoteInjectionSettings(enabled=true,folderPath="../escape"),
            DailyNoteInjectionSettings(enabled=true,filenamePattern="../{date}"))) {
            var rejected = false
            try { PreparedWakeDateDailyNote.prepare(source(),settings(false).copy(dailyNoteInjection=injection),
                DailyAggregateExportIds("bad-path","bad-session"),planner=never) }
            catch (_: IllegalArgumentException) { rejected = true }
            assertThat(rejected).isTrue()
        }
        assertThat(calls).isEqualTo(0)
    }

    @Test fun missingDurablePinAndChangedRendererClockCannotAcquireAuthority() = runTest {
        var rejected = false
        try { PreparedWakeDateDailyNote.prepare(source(),settings(false).copy(executionEngineAuthorityIsFrozen=true),
            DailyAggregateExportIds("missing-pin","missing-session")) }
        catch (_: IllegalArgumentException) { rejected = true }
        assertThat(rejected).isTrue()
        val real = HealthMdRustDailyAggregatePlanner()
        val changed = DailyAggregateRustPlanner { request ->
            val rendered = real.plan(request)
            rendered.copy(pin = rendered.pin.copy(ianaTimeZone="UTC"))
        }
        rejected = false
        try { PreparedWakeDateDailyNote.prepare(source(),settings(false),DailyAggregateExportIds("wrong-clock","wrong-clock-session"),planner=changed) }
        catch (_: IllegalArgumentException) { rejected = true }
        assertThat(rejected).isTrue()
    }

    private fun settings(sections: Boolean) = ExportSettings(groupByCategory=false,filenameFormat="../irrelevant-aggregate",
        includeGranularData=true,dailyNoteInjection=DailyNoteInjectionSettings(enabled=true,injectMarkdownSections=sections),
        metricSelection=MetricSelectionState(enabledMetrics=setOf("steps","sleep_total","sleep_light")),
        executionSleepCaptureContext=context,executionSleepCaptureAuthorityIsFrozen=true)

    private fun source(): HealthData {
        val start=Instant.parse("2026-03-07T15:00:00Z"); val end=Instant.parse("2026-03-08T17:00:00.500Z")
        fun exact(value:Instant)=ExactSourceTimestamp.from(value,context.zoneId.rules.getOffset(value))
        val localStart=start.atZone(context.zoneId).toLocalDateTime(); val localEnd=end.atZone(context.zoneId).toLocalDateTime()
        return HealthData(date,sleep=SleepData(totalDuration=93600.5.seconds,lightSleep=93600.5.seconds,
            stages=listOf(SleepStageEntry(localStart,localEnd,"light",exact(start),exact(end))),
            sessions=listOf(SleepSessionEntry(localStart,localEnd,notes="Synthetic complete session",exactStartTime=exact(start),exactEndTime=exact(end))),
            sessionStart=localStart,sessionEnd=localEnd),activity=ActivityData(steps=42))
    }
}
