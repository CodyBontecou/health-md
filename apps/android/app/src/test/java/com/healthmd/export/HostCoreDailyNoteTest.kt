package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.DailyNoteInjector
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.data.storage.ExportRepositoryImpl
import com.healthmd.data.storage.FileExportManager
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.DateFormatPreference
import com.healthmd.domain.model.WriteMode
import com.healthmd.domain.model.ExportPreviewSideEffectAction
import io.mockk.mockk
import io.mockk.every
import io.mockk.coEvery
import com.healthmd.data.export.InjectionResult
import com.healthmd.data.export.PreparedWakeDateDailyNote
import com.healthmd.domain.exportengine.DailyAggregateExportIds
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.ExportEnginePinPlanner
import com.healthmd.domain.model.ExportTarget
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

    @Test fun directNotesCarryFrozenPolicyEvenWhenMissingNotesMustNotBeCreated() = runTest {
        for (attribution in SleepDayAttribution.entries) for (sections in listOf(false, true)) {
            val capture = context.copy(sleepDayAttribution = attribution,
                exportProfileID = if (attribution == SleepDayAttribution.MORNING_ENDS) "android-sleep-v6" else null)
            val data = if (attribution == SleepDayAttribution.MORNING_ENDS) source()
                else HealthData(date, activity = ActivityData(steps = 42))
            val repository = mockk<com.healthmd.domain.repository.HealthRepository>()
            coEvery { repository.fetchHealthDataRange(any(), any(), any(), any(), any(), any()) } returns listOf(data)
            val settings = repositorySettings(sections).copy(executionSleepCaptureContext = capture,
                dailyNoteInjection = DailyNoteInjectionSettings(enabled = true, createIfMissing = false,
                    injectMarkdownSections = sections))
            val pin = ExportEnginePinPlanner().forDirectGeneratedFiles(settings, capture.zoneId)
            val producer = com.healthmd.direct.DirectGeneratedFilesProducer(repository, MarkdownExporter(),
                JsonExporter(), CsvExporter(), ObsidianBasesExporter())
            val directory = java.nio.file.Files.createTempDirectory("direct-scoped-note").toFile()
            try {
                val files = producer.produce(directory, listOf(date), settings.copy(executionEnginePin = pin,
                    executionEngineAuthorityIsFrozen = true), capture, scopedNoteVersion = 1)
                val note = files.single { it.scopedNotePolicy != null }
                val policy = requireNotNull(note.scopedNotePolicy)
                assertThat(policy.createIfMissing).isFalse()
                assertThat(policy.injectSections).isEqualTo(sections)
                assertThat(policy.ownerDate).isEqualTo(date.toString())
                assertThat(policy.calendarTimezone).isEqualTo(capture.zoneId.id)
                assertThat(note.file.readText()).contains("healthmd_injection_kind:")
                val profile = if (attribution == SleepDayAttribution.MORNING_ENDS)
                    com.healthmd.core.CoreMetricRegistryProfile.ANDROID_SLEEP_V6
                    else com.healthmd.core.CoreMetricRegistryProfile.ANDROID_FROZEN_V4
                val merged = com.healthmd.core.HealthMdCoreService().mergeScopedNote(profile,
                    "---\nprivate: preserved\n---\n# My journal\n", note.file.readText(), sections)
                assertThat(merged).contains("private: preserved")
                assertThat(merged).contains("# My journal")
            } finally { directory.deleteRecursively() }
        }
    }

    @Test fun morningExportsRetainAllNativeWriteModesAndPreviewTheirDestinationEffect() = runTest {
        for (mode in WriteMode.entries) {
            val destination = NoteDestination(null)
            val settings = repositorySettings(false).copy(writeMode = mode,
                exportFormats = ExportFormat.entries.toSet(),
                dailyNoteInjection = DailyNoteInjectionSettings(enabled = false))
            assertThat(destination.repository().exportHealthData(source(), settings)).isTrue()
            assertThat(destination.writes).hasSize(4)
            assertThat(destination.writeModes.values.toSet()).containsExactly(
                com.healthmd.data.storage.FileExportManager.WriteMode.valueOf(mode.name))
            val json = destination.writes.entries.single { it.key.endsWith(".json") }.value
            assertThat(Json.parseToJsonElement(json).jsonObject["schema_profile"]?.jsonPrimitive?.content)
                .isEqualTo("android-sleep-v6")
        }
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

    @Test fun repositoryPreviewAndWriteUseSameScopedNoteAndPreserveUserText() = runTest {
        for (sections in listOf(false, true)) {
            val original = "---\r\nnotes: |\r\n  Keep my journal\r\nsleep_deep_hours: 9 # history\r\n---\r\nMy introduction.\r\n"
            val destination = NoteDestination(original)
            val repository = destination.repository()
            val settings = repositorySettings(sections)
            val preview = repository.previewHealthData(source(), settings)
            assertThat(preview.failureReason).isNull()
            assertThat(preview.files).hasSize(1)
            assertThat(preview.sideEffects).hasSize(1)
            val effect = preview.sideEffects.single()
            assertThat(effect.action).isEqualTo(ExportPreviewSideEffectAction.UPDATE_DAILY_NOTE)
            assertThat(effect.content).contains("Keep my journal")
            assertThat(destination.writes).isEmpty()
            assertThat(repository.exportHealthData(source(), settings)).isTrue()
            assertThat(destination.writes[effect.relativePath]).isEqualTo(effect.content)
            assertThat(destination.writes[preview.files.single().relativePath]).isEqualTo(preview.files.single().content)
        }
    }

    @Test fun repositoryMissingNoteSkipCreateAndCollisionHaveExplicitOutcomes() = runTest {
        for (create in listOf(false, true)) {
            val destination = NoteDestination(null)
            val repository = destination.repository()
            val settings = repositorySettings(false).let { it.copy(dailyNoteInjection = it.dailyNoteInjection.copy(createIfMissing = create)) }
            val effect = repository.previewHealthData(source(), settings).sideEffects.single()
            assertThat(effect.action).isEqualTo(if(create) ExportPreviewSideEffectAction.CREATE_DAILY_NOTE else ExportPreviewSideEffectAction.SKIP_DAILY_NOTE)
            assertThat(repository.exportHealthData(source(), settings)).isTrue()
            assertThat(destination.writes.containsKey("Daily/2026-03-08.md")).isEqualTo(create)
        }
        val destination = NoteDestination(null)
        val repository = destination.repository()
        val collision = repositorySettings(false).copy(exportFormat = ExportFormat.MARKDOWN,
            exportFormats = setOf(ExportFormat.MARKDOWN), subfolder = "daily")
        assertThat(repository.previewHealthData(source(), collision).failureReason).isNotNull()
        assertThat(repository.exportHealthData(source(), collision)).isFalse()
        assertThat(destination.writes).isEmpty()
    }

    @Test fun repositoryRejectsUncertainNotesAndChangesDuringCommit() = runTest {
        for (baseline in listOf(FileExportManager.DurableFileInspection.Ambiguous,
            FileExportManager.DurableFileInspection.Unavailable,
            FileExportManager.DurableFileInspection.Found("note", byteArrayOf(0xff.toByte())))) {
            val destination = NoteDestination(null)
            destination.inspectionOverride = baseline
            assertThat(destination.repository().exportHealthData(source(), repositorySettings(false))).isFalse()
            assertThat(destination.writes).isEmpty()
        }
        val registered = NoteDestination("---\nschema: healthmd.health_data\n---\nOriginal export")
        assertThat(registered.repository().exportHealthData(source(),repositorySettings(false))).isFalse()
        assertThat(registered.writes).isEmpty()
        val failedAggregate = NoteDestination("My journal")
        failedAggregate.aggregateSuccess = false
        assertThat(failedAggregate.repository().exportHealthData(source(),repositorySettings(false))).isFalse()
        assertThat(failedAggregate.note).isEqualTo("My journal")
        assertThat(failedAggregate.writes.keys).doesNotContain("Daily/2026-03-08.md")
        val destination = NoteDestination("My original journal")
        destination.afterAggregate = { destination.note = "My concurrent edit" }
        assertThat(destination.repository().exportHealthData(source(), repositorySettings(false))).isFalse()
        assertThat(destination.note).isEqualTo("My concurrent edit")
        assertThat(destination.writes.keys).doesNotContain("Daily/2026-03-08.md")
        val changed = NoteDestination("Original")
        changed.afterAggregate = { changed.folder = "content://different-tree" }
        assertThat(changed.repository().exportHealthData(source(), repositorySettings(false))).isFalse()
        assertThat(changed.writes.keys).doesNotContain("Daily/2026-03-08.md")
    }

    @Test fun repositoryFreezesSelectionBeforeLookupAndRetainsRecoveredClock() = runTest {
        val metrics = mutableSetOf("steps")
        val fields = mutableListOf(CustomFrontmatterField("steps", "My steps", true))
        val destination = NoteDestination(null)
        destination.onLookup = { metrics.clear(); fields.clear() }
        val settings = repositorySettings(false).copy(metricSelection=MetricSelectionState(enabledMetrics=metrics),
            formatCustomization=FormatCustomization(frontmatterConfig=FrontmatterConfiguration(fields=fields)))
        val preview = destination.repository().previewHealthData(source(),settings)
        assertThat(preview.sideEffects.single().content).contains("My steps: 42")
        val pin = requireNotNull(ExportEnginePinPlanner().forScheduledExport(repositorySettings(false),
            ExportTarget.DEVICE_FOLDER,context.zoneId))
        val snapshot = AndroidExportSettingsSnapshot.capture(repositorySettings(false),pin,context.zoneId)
        val restored = snapshot.restoreOnto(repositorySettings(false).copy(
            executionSleepCaptureContext=AndroidCaptureContext(ZoneId.of("Asia/Tokyo"),SleepDayAttribution.NIGHT_BEGINS)))
            .copy(executionEnginePin=pin)
        val recovered = NoteDestination(null)
        assertThat(recovered.repository().exportHealthData(source(),restored)).isTrue()
        assertThat(recovered.writes["Daily/2026-03-08.md"]).contains("America/New_York")
        assertThat(recovered.writes["Daily/2026-03-08.md"]).doesNotContain("Asia/Tokyo")
        val missingPin = NoteDestination(null)
        assertThat(missingPin.repository().exportHealthData(source(),restored.copy(executionEnginePin=null))).isFalse()
        assertThat(missingPin.lookupCount).isEqualTo(0)
        assertThat(ExportEnginePinPlanner.supportsNewScheduledPin(repositorySettings(false),ExportTarget.DEVICE_FOLDER)).isTrue()
        assertThat(ExportEnginePinPlanner.supportsNewDirectGeneratedFilesPin(repositorySettings(false))).isTrue()
        assertThat(ExportEnginePinPlanner.supportsNewScheduledPin(repositorySettings(false),ExportTarget.AGENT_DATA_GATEWAY)).isTrue()
        val withoutFolder = NoteDestination(null)
        withoutFolder.folder=null
        assertThat(withoutFolder.repository().previewHealthData(source(),repositorySettings(false)).sideEffects.single().wouldWrite).isTrue()
        assertThat(withoutFolder.writes).isEmpty()
        assertThat(withoutFolder.repository().exportHealthData(source(),repositorySettings(false))).isFalse()
    }

    @Test fun scopedMorningNightMorningMatrixRetainsOnlyCurrentSelectedNativeFacts() = runTest {
        val nightContext=AndroidCaptureContext(context.zoneId,SleepDayAttribution.NIGHT_BEGINS)
        val start=Instant.parse("2026-03-08T16:00:00Z");val end=Instant.parse("2026-03-08T17:00:00.500Z")
        val localStart=start.atZone(context.zoneId).toLocalDateTime();val localEnd=end.atZone(context.zoneId).toLocalDateTime()
        fun exact(value:Instant)=ExactSourceTimestamp.from(value,context.zoneId.rules.getOffset(value))
        val nightData=HealthData(date,sleep=SleepData(totalDuration=3600.5.seconds,lightSleep=3600.5.seconds,
            stages=listOf(SleepStageEntry(localStart,localEnd,"light",exact(start),exact(end))),
            sessions=listOf(SleepSessionEntry(localStart,localEnd,notes="Synthetic Night session",exactStartTime=exact(start),exactEndTime=exact(end))),
            sessionStart=localStart,sessionEnd=localEnd),activity=ActivityData(steps=84))
        for(profile in CompatibilitySchemaProfile.entries) for(initialSections in listOf(false,true)) {
            val prepared=PreparedWakeDateDailyNote.prepare(source(),settings(initialSections),DailyAggregateExportIds("initial-$profile-$initialSections","transition-session"))
            val personal="---\r\ndate: 1999-01-01\r\nnotes: |\r\n  Personal: multiline text\r\nsleep_deep_hours: 9 # historical\r\n---\r\nMy introduction.\r\n## Journal\r\nKeep this section.\r\n"
            val morning=requireNotNull(DailyNoteInjector().injectPrepared(personal,prepared).second)
            for(sections in listOf(false,true)) for(selection in listOf("steps","sleep","both")) {
                val selected=MetricSelectionState(enabledMetrics=when(selection) {
                    "steps"->setOf("steps");"sleep"->setOf("sleep_total","sleep_light");else->setOf("steps","sleep_total","sleep_light") })
                val customization=FormatCustomization(compatibilitySchemaProfile=profile,includeAndroidNativeFields=profile==CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5)
                val injection=DailyNoteInjectionSettings(enabled=true,injectMarkdownSections=sections)
                val (result,content)=DailyNoteInjector().inject(morning,nightData,injection,customization,selected,nightContext,true)
                assertThat(result).isEqualTo(InjectionResult.UPDATED)
                val note=requireNotNull(content)
                assertThat(note).contains("notes: |\r\n  Personal: multiline text\r\n")
                assertThat(note).contains("sleep_deep_hours: 9 # historical\r\n")
                assertThat(note).contains("Keep this section.")
                assertThat(note).contains("healthmd_daily_injection_v1: null")
                val encoded=note.lineSequence().first{it.startsWith("healthmd_daily_injection_v2:")}.substringAfter(':').trim()
                val envelope=Json.parseToJsonElement(Json.decodeFromString<String>(encoded)).jsonObject
                assertThat(envelope["version"]?.jsonPrimitive?.long).isEqualTo(2)
                assertThat(envelope["record_profile"]?.jsonPrimitive?.content).isEqualTo(if(profile==CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5)"android-analytical-v5" else "android-frozen-v4")
                assertThat(envelope["time_context"]?.jsonObject?.get("calendar_timezone")?.jsonPrimitive?.content).isEqualTo("America/New_York")
                val recordText=requireNotNull(envelope["record_json"]).jsonPrimitive.content
                val expected=JsonExporter().export(nightData.filtered(selected,nightContext),customization.copy(dateFormat=DateFormatPreference.ISO8601),sections)
                assertThat(recordText).isEqualTo(expected)
                val record=Json.parseToJsonElement(recordText).jsonObject
                assertThat(record["time_context"]).isNull()
                val sleep=record["sleep"]?.jsonObject
                assertThat(sleep?.get("totalDuration")?.jsonPrimitive?.double).isEqualTo(if(selection=="steps")null else 3600.0)
                assertThat(sleep?.get("sleepStages")?.jsonArray?.size ?: 0).isEqualTo(if(sections && selection!="steps")1 else 0)
                assertThat(record["activity"]?.jsonObject?.get("steps")?.jsonPrimitive?.long).isEqualTo(if(selection=="sleep")null else 84L)
                val restored=requireNotNull(DailyNoteInjector().injectPrepared(note,prepared).second)
                assertThat(restored).contains("healthmd_daily_injection_v2: null")
                val restoredEncoded=restored.lineSequence().first{it.startsWith("healthmd_daily_injection_v1:")}.substringAfter(':').trim()
                val restoredRecord=Json.parseToJsonElement(Json.decodeFromString<String>(restoredEncoded)).jsonObject["record_json"]!!.jsonPrimitive.content
                assertThat(Json.parseToJsonElement(restoredRecord).jsonObject["sleep"]?.jsonObject?.get("totalDuration")?.jsonPrimitive?.double).isEqualTo(93600.5)
                System.getenv("HEALTHMD_ANDROID_NIGHT_TRANSITION_FIXTURE_DIR")?.let { directory ->
                    val name="${profile.name}-$initialSections-$sections-$selection"
                    File(directory).mkdirs()
                    File(directory,"night-$name.md").writeText(note);File(directory,"night-$name.json").writeText(recordText)
                    File(directory,"restored-$name.md").writeText(restored);File(directory,"restored-$name.json").writeText(restoredRecord)
                }
            }
        }
        val old=DailyNoteInjector().injectPrepared(null,PreparedWakeDateDailyNote.prepare(source(),settings(false),DailyAggregateExportIds("fail-transition","fail-session"))).second!!
        assertThat(DailyNoteInjector().inject(old,nightData,DailyNoteInjectionSettings(enabled=true)).first).isEqualTo(InjectionResult.FAILED)
        assertThat(DailyNoteInjector().inject(old.replace("daily_capture_v1","daily_capture_v99"),nightData,
            DailyNoteInjectionSettings(enabled=true),captureContext=nightContext).first).isEqualTo(InjectionResult.FAILED)
    }

    @Test fun repositoryNightTransitionWritesExactPreviewWithoutASecondLegacyMerge() = runTest {
        val prepared=PreparedWakeDateDailyNote.prepare(source(),settings(true),DailyAggregateExportIds("repository-night","repository-night-session"))
        val personal="---\r\nnotes: |\r\n  My personal journal\r\nsleep_deep_hours: 9 # history\r\n---\r\nMy introduction.\r\n"
        val morning=requireNotNull(DailyNoteInjector().injectPrepared(personal,prepared).second)
        val nightContext=AndroidCaptureContext(context.zoneId,SleepDayAttribution.NIGHT_BEGINS)
        val original=source()
        val nightData=original.copy(sleep=original.sleep!!.copy(totalDuration=3600.5.seconds,lightSleep=3600.5.seconds),activity=ActivityData(steps=84))
        for(profile in CompatibilitySchemaProfile.entries) for(mode in WriteMode.entries) {
            val destination=NoteDestination(morning)
            val repository=destination.repository()
            val settings=repositorySettings(true).copy(writeMode=mode,executionSleepCaptureContext=nightContext,
                formatCustomization=FormatCustomization(compatibilitySchemaProfile=profile))
            val preview=repository.previewHealthData(nightData,settings)
            assertThat(preview.failureReason).isNull()
            val content=preview.sideEffects.single().content
            assertThat(content).contains("notes: |\r\n  My personal journal\r\n")
            assertThat(destination.writes).isEmpty()
            assertThat(repository.exportHealthData(nightData,settings)).isTrue()
            assertThat(destination.note).isEqualTo(content)
            val encoded=content!!.lineSequence().first{it.startsWith("healthmd_daily_injection_v2:")}.substringAfter(':').trim()
            val recordText=Json.parseToJsonElement(Json.decodeFromString<String>(encoded)).jsonObject["record_json"]!!.jsonPrimitive.content
            val record=Json.parseToJsonElement(recordText).jsonObject
            System.getenv("HEALTHMD_ANDROID_NIGHT_REPOSITORY_FIXTURE_DIR")?.let { directory ->
                File(directory).mkdirs()
                File(directory,"repository-${profile.name}-${mode.name}.md").writeText(content)
                File(directory,"repository-${profile.name}-${mode.name}.json").writeText(recordText)
            }
            assertThat(record["sleep"]?.jsonObject?.get("totalDuration")?.jsonPrimitive?.double).isEqualTo(3600.0)
            // The frozen local-clock duration spans the DST jump; preserve its shipped wall-clock value.
            assertThat(record["sleep"]?.jsonObject?.get("sleepStages")?.jsonArray?.single()?.jsonObject?.get("durationSeconds")?.jsonPrimitive?.double).isEqualTo(97200.0)
        }
        val changed=NoteDestination(morning)
        changed.afterAggregate={changed.note="My concurrent Night edit"}
        val nightSettings=repositorySettings(false).copy(executionSleepCaptureContext=nightContext)
        assertThat(changed.repository().exportHealthData(nightData,nightSettings)).isFalse()
        assertThat(changed.note).isEqualTo("My concurrent Night edit")
        val collision=NoteDestination(morning)
        val collisionSettings=nightSettings.copy(exportFormat=ExportFormat.MARKDOWN,exportFormats=setOf(ExportFormat.MARKDOWN),subfolder="daily")
        assertThat(collision.repository().previewHealthData(nightData,collisionSettings).failureReason).isNotNull()
        assertThat(collision.repository().exportHealthData(nightData,collisionSettings)).isFalse()
        assertThat(collision.writes).isEmpty()
        val unavailable=NoteDestination(morning)
        unavailable.inspectionOverride=FileExportManager.DurableFileInspection.Unavailable
        assertThat(unavailable.repository().exportHealthData(nightData,nightSettings)).isFalse()
        assertThat(unavailable.writes).isEmpty()
    }

    private fun repositorySettings(sections: Boolean) = settings(sections).copy(filenameFormat="{date}",
        writeMode=WriteMode.OVERWRITE, exportFormat=ExportFormat.JSON, exportFormats=setOf(ExportFormat.JSON), subfolder="health")

    private class NoteDestination(var note: String?) {
        var folder: String? = "content://synthetic-tree"
        var onLookup: (() -> Unit)? = null
        var lookupCount = 0
        var afterAggregate: (() -> Unit)? = null
        var aggregateSuccess = true
        var inspectionOverride: FileExportManager.DurableFileInspection? = null
        val writes = linkedMapOf<String,String>()
        val writeModes = linkedMapOf<String, FileExportManager.WriteMode>()
        private val manager = mockk<FileExportManager>()
        init {
            every { manager.inspectDurableFile(any(), any()) } answers {
                inspectionOverride ?: note?.let { FileExportManager.DurableFileInspection.Found("note", it.encodeToByteArray()) }
                    ?: FileExportManager.DurableFileInspection.Missing
            }
            every { manager.readFileAtRelativePath(any(),any()) } answers {
                val path=arg<String>(1)
                if(path=="Daily/2026-03-08.md") note else writes[path]
            }
            every { manager.fileExistsAtRelativePath(any(),any()) } answers { writes.containsKey(arg<String>(1)) }
            every { manager.writeFile(any(),any(),any(),any(),any(),any()) } answers {
                val parent=arg<String?>(1)
                val path=listOfNotNull(parent?.takeIf{it.isNotBlank()},arg<String>(2)+"."+arg<String>(3)).joinToString("/")
                writes[path]=arg(4);afterAggregate?.invoke();aggregateSuccess
            }
            every { manager.writeFileAtRelativePath(any(), any(), any(), any()) } answers {
                writes[arg(1)] = arg(2); writeModes[arg(1)] = arg(3); afterAggregate?.invoke(); aggregateSuccess
            }
            every { manager.bindDurableFile(any(),any(),any(),any(),any()) } answers {
                FileExportManager.DurableBoundFile("note")
            }
            every { manager.overwriteDurableBoundFile(any(),any(),any(),any()) } answers {
                val content = arg<ByteArray>(3).decodeToString(); writes[arg(1)] = content; note = content; true
            }
        }
        fun repository(): ExportRepositoryImpl {
            val settings = mockk<SettingsRepository>()
            coEvery { settings.getExportFolderUri() } answers { lookupCount++; onLookup?.invoke(); folder }
            return ExportRepositoryImpl(manager,MarkdownExporter(),JsonExporter(),CsvExporter(),ObsidianBasesExporter(),settings)
        }
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
