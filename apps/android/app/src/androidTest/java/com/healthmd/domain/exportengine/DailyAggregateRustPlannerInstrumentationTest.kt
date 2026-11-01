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
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DailyAggregateRustPlannerInstrumentationTest {
    @Test
    fun packagedCaptureReducerRetainsFractionalSleepQuantities() = runBlocking {
        val zone = ZoneId.of("America/New_York")
        val date = LocalDate.of(2026, 11, 1)
        val context = com.healthmd.domain.model.AndroidCaptureContext(zone, com.healthmd.domain.model.SleepDayAttribution.MORNING_ENDS)
        val start = java.time.Instant.parse("2026-11-01T05:30:00.123456789Z")
        val end = java.time.Instant.parse("2026-11-01T06:30:00.987654321Z")
        val from = start.atZone(zone).toLocalDateTime()
        val to = end.atZone(zone).toLocalDateTime()
        val exactStart = com.healthmd.domain.model.ExactSourceTimestamp.from(start, java.time.ZoneOffset.of("-04:00"))
        val exactEnd = com.healthmd.domain.model.ExactSourceTimestamp.from(end, java.time.ZoneOffset.of("-05:00"))
        val sources = listOf("light", "deep").map { stage ->
            val id = "synthetic-device-precision-$stage"
            com.healthmd.data.health.SourceSession(start, end,
                com.healthmd.domain.model.SleepSessionEntry(from, to, exactStartTime = exactStart, exactEndTime = exactEnd,
                    identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = id)),
                listOf(com.healthmd.data.health.SourceStage(start, end,
                    com.healthmd.domain.model.SleepStageEntry(from, to, stage, exactStartTime = exactStart, exactEndTime = exactEnd,
                        identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "$id-stage")))))
        }
        for (granular in listOf(false, true)) {
            val sleep = com.healthmd.data.health.SleepJournalSummary.summarize(sources, listOf(date), zone, granular,
                com.healthmd.domain.model.SleepDayAttribution.MORNING_ENDS).getValue(date)
            assertEquals(kotlin.time.Duration.parse("7201.728395064s"), sleep.totalDuration)
            assertEquals(kotlin.time.Duration.parse("3600.864197532s"), sleep.lightSleep)
            val request = FrozenDailyAggregateExportRequest.capture(HealthData(date, sleep = sleep), ExportSettings(
                exportFormats = ExportFormat.entries.toSet(), includeGranularData = granular,
                metricSelection = com.healthmd.domain.model.MetricSelectionState(enabledMetrics = setOf(
                    "sleep_total", "sleep_light", "sleep_deep", "sleep_in_bed", "sleep_bedtime", "sleep_wake")),
                executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true),
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                DailyAggregateExportIds("device-sleep-precision-$granular", "device-sleep-precision-session-$granular"))
            val prepared = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("No ambient clock") }).plan(request)
            val plan = prepared.plan
            assertEquals(4, plan.items.size)
            val native = org.json.JSONObject(plan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString())
                .getJSONObject("sleep")
            assertEquals(7201.728395064, native.getDouble("totalDuration"), 0.0)
            assertEquals(7201.728395064, native.getDouble("inBedTime"), 0.0)
            assertEquals(3600.864197532, native.getDouble("deepSleep"), 0.0)
            assertEquals(3600.864197532, native.getDouble("lightSleep"), 0.0)
            verifyDurableSleepArtifacts(prepared, date)
        }
    }

    /** Actual private Android storage and sync, without provider access or production trust state. */
    private fun verifyDurableSleepArtifacts(prepared: DailyAggregateRustPlan, date: LocalDate) {
        val app = androidx.test.core.app.ApplicationProvider.getApplicationContext<android.content.Context>()
        val root = java.nio.file.Files.createTempDirectory(app.cacheDir.toPath(), "synthetic-sleep-recovery-").toFile()
        val context = object : android.content.ContextWrapper(app) {
            override fun getNoBackupFilesDir(): java.io.File = root
        }
        val reopen = { com.healthmd.direct.DirectCliJobStore(com.healthmd.direct.DirectCliTrustStore(context)) }
        try {
            val store = reopen()
            val id = java.util.UUID.randomUUID().toString()
            val fingerprint = "a".repeat(64)
            val acceptedAt = java.time.Instant.now()
            val owner = store.beginPreparation(id, fingerprint, acceptedAt.plusSeconds(3600).toString(), prepared.pin)
            val directory = store.directory(owner)
            val files = prepared.plan.items.associate { item ->
                item.artifactId to java.io.File(directory, "${item.artifactId}.synthetic").apply { writeBytes(item.content) }
            }
            val accepted = com.healthmd.direct.protocol.ExportAccepted(id, acceptedAt.toString(),
                com.healthmd.direct.protocol.PeerBinding(java.util.UUID.randomUUID().toString(), java.util.UUID.randomUUID().toString()),
                com.healthmd.direct.protocol.ProductId.GENERATED_FILES_V1,
                com.healthmd.direct.protocol.ResolvedRange(date.toString(), date.toString(), prepared.pin.ianaTimeZone),
                requestFingerprint = fingerprint)
            val manifests = prepared.plan.items.map { item ->
                com.healthmd.direct.protocol.ArtifactManifest(id, item.artifactId,
                    com.healthmd.direct.protocol.ArtifactKind.GENERATED_FILE,
                    com.healthmd.direct.protocol.ArtifactSchema("healthmd.generated-files", 1), item.mediaType,
                    item.content.size.toLong(), item.sha256, relativePath = item.relativePath,
                    writeMode = com.healthmd.direct.protocol.FileWriteMode.OVERWRITE)
            }
            val transfer = com.healthmd.direct.protocol.TransferPlanBuilder.build(accepted, manifests, files,
                createdAt = acceptedAt.toString())
            val journal = com.healthmd.direct.DirectJobJournal(requestFingerprint = fingerprint,
                expiresAt = acceptedAt.plusSeconds(3600).toString(), transfer = transfer, enginePin = prepared.pin)
            store.savePrepared(journal, owner)
            assertEquals(journal, reopen().load(id, fingerprint))
            val lease = reopen().acquireAcceptedLease(journal)
            var sends = 0
            reopen().packetSendAuthorization(lease).authorizeEnqueue { sends += 1 }
            assertEquals(1, sends)
            val journalFile = java.io.File(directory.parentFile, "job.json")
            val originalJournal = journalFile.readBytes()
            for (item in prepared.plan.items) {
                val file = files.getValue(item.artifactId)
                assertTrue(item.content.contentEquals(file.readBytes()))
                val changed = item.content.copyOf()
                changed[changed.lastIndex] = (changed.last().toInt() xor 1).toByte()
                file.writeBytes(changed)
                org.junit.Assert.assertThrows(IllegalStateException::class.java) { reopen().load(id, fingerprint) }
                org.junit.Assert.assertThrows(IllegalStateException::class.java) { reopen().acquireAcceptedLease(journal) }
                reopen().sweepExpired(acceptedAt.plusSeconds(7200))
                assertTrue(changed.contentEquals(file.readBytes()))
                assertTrue(originalJournal.contentEquals(journalFile.readBytes()))
                file.writeBytes(item.content)
            }
            assertEquals(journal, reopen().load(id, fingerprint))
        } finally {
            assertTrue(root.deleteRecursively())
        }
    }

    @Test
    fun packagedCoreKeepsCompleteSleepStageAndParentRecordsInMarkdown() = runBlocking {
        val zone = ZoneId.of("America/New_York")
        val capture = com.healthmd.domain.model.AndroidCaptureContext(zone, com.healthmd.domain.model.SleepDayAttribution.MORNING_ENDS)
        val start = java.time.Instant.parse("2026-11-01T05:30:00.123456789Z")
        val end = java.time.Instant.parse("2026-11-01T06:30:00.987654321Z")
        val from = start.atZone(zone).toLocalDateTime()
        val to = end.atZone(zone).toLocalDateTime()
        val duration = kotlin.time.Duration.parse("3600.864197532s")
        val exactStart = com.healthmd.domain.model.ExactSourceTimestamp.from(start, java.time.ZoneOffset.of("-04:00"))
        val exactEnd = com.healthmd.domain.model.ExactSourceTimestamp.from(end, java.time.ZoneOffset.of("-05:00"))
        val stage = com.healthmd.domain.model.SleepStageEntry(from, to, "light", exactStartTime = exactStart,
            exactEndTime = exactEnd, identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-device-stage"))
        val parent = com.healthmd.domain.model.SleepSessionEntry(from, to, title = "Synthetic | ` <session> &",
            notes = "quoted \"note\"", metadata = mapOf("synthetic" to "native source"),
            exactStartTime = exactStart, exactEndTime = exactEnd,
            identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-device-parent"))
        val day = HealthData(LocalDate.of(2026, 11, 1), sleep = com.healthmd.domain.model.SleepData(
            totalDuration = duration, lightSleep = duration, inBedTime = duration,
            sessionStart = from, sessionEnd = to, stages = listOf(stage), sessions = listOf(parent)))
        for (metadata in listOf(false, true)) {
            val settings = ExportSettings(exportFormats = ExportFormat.entries.toSet(), includeGranularData = true,
                includeMetadata = metadata,
                metricSelection = com.healthmd.domain.model.MetricSelectionState(enabledMetrics = setOf("sleep_total", "sleep_light", "sleep_in_bed")),
                executionSleepCaptureContext = capture, executionSleepCaptureAuthorityIsFrozen = true)
            val request = FrozenDailyAggregateExportRequest.capture(day, settings, AndroidExportProfile.android_sleep_v6,
                ExportEngineMode.rust, DailyAggregateExportIds("sleep-records-$metadata", "sleep-records-session-$metadata"))
            val plan = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("No ambient clock") }).plan(request).plan
            assertEquals(4, plan.items.size)
            val source = Json.parseToJsonElement(plan.items.single { it.relativePath.endsWith(".json") }.content.decodeToString())
                .jsonObject.getValue("sleep").jsonObject
            val markdown = plan.items.single { it.relativePath.endsWith(".md") && !it.relativePath.endsWith("-bases.md") }.content.decodeToString()
            val records = markdown.lineSequence().filter { it.contains("| `{") }.map { row ->
                val cell = row.split('|').dropLast(1).last().trim()
                check(cell.startsWith("`{") && cell.endsWith("}`"))
                Json.parseToJsonElement(cell.removeSurrounding("`")).jsonObject
            }.toList()
            assertEquals(source.getValue("sleepStages").jsonArray.toList(), records.filter { "stage" in it })
            assertEquals(source.getValue("sleepSessions").jsonArray.toList(), records.filter { "startTimeISO" in it })
        }
    }

    @Test
    fun packagedCoreKeepsFrozenMindfulnessSessionsAcrossEveryFormat() = runBlocking {
        val zone = ZoneId.of("America/New_York")
        val context = com.healthmd.domain.model.AndroidCaptureContext(zone, com.healthmd.domain.model.SleepDayAttribution.MORNING_ENDS)
        val start = java.time.Instant.parse("2026-11-01T05:30:00.123456789Z")
        val end = java.time.Instant.parse("2026-11-01T06:30:00.987654321Z")
        val session = com.healthmd.domain.model.MindfulnessSessionEntry(
            startTime = start.atZone(zone).toLocalDateTime(), endTime = end.atZone(zone).toLocalDateTime(),
            sessionType = "meditation", title = "Synthetic|session", notes = "quoted \"note\" <test>",
            exactStartTime = com.healthmd.domain.model.ExactSourceTimestamp.from(start, java.time.ZoneOffset.of("-04:00")),
            exactEndTime = com.healthmd.domain.model.ExactSourceTimestamp.from(end, java.time.ZoneOffset.of("-05:00")),
            identity = com.healthmd.domain.model.ExactSourceIdentity(nativeId = "synthetic-device-mindfulness"))
        for (owner in listOf("mindful_minutes", "mindful_sessions")) for (metadata in listOf(false, true)) {
            val facts = mutableMapOf("synthetic" to "accepted-source")
            val sessions = mutableListOf(session.copy(metadata = facts))
            val day = HealthData(date = LocalDate.of(2026, 11, 1),
                mindfulness = com.healthmd.domain.model.MindfulnessData(sessions = sessions))
            val request = FrozenDailyAggregateExportRequest.capture(day, ExportSettings(
                exportFormats = ExportFormat.entries.toSet(), includeGranularData = true, includeMetadata = metadata,
                metricSelection = com.healthmd.domain.model.MetricSelectionState(enabledMetrics = setOf(owner)),
                executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true),
                AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                DailyAggregateExportIds("device-mindfulness-$owner-$metadata", "device-mindfulness-session-$owner-$metadata"))
            facts["synthetic"] = "mutated-source"
            sessions.clear()
            val plan = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("cannot read ambient clock") }).plan(request).plan
            assertEquals(4, plan.items.size)
            for (item in plan.items) {
                val text = item.content.decodeToString()
                assertTrue(text.contains(start.toString()))
                assertTrue(text.contains(end.toString()))
                assertTrue(text.contains("synthetic-device-mindfulness"))
                assertTrue(text.contains("accepted-source"))
                assertTrue(!text.contains("mutated-source"))
                if (item.relativePath.endsWith(".csv")) assertTrue(text.contains(",Native Detail,Mindfulness Record,"))
                if (item.relativePath.endsWith("-bases.md")) assertTrue(text.contains("native_mindfulness_details:"))
                else if (item.relativePath.endsWith(".md")) {
                    assertTrue(text.contains("Mindfulness Session Details"))
                    val row = text.lineSequence().single { it.startsWith("| `{") }
                    assertTrue(row.endsWith("}` |"))
                    val sample = org.json.JSONObject(row.removePrefix("| `").removeSuffix("` |")).getJSONObject("sample")
                    assertEquals(session.notes, sample.getString("notes"))
                    assertEquals(session.title, sample.getString("title"))
                }
            }
        }
    }

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
        for (preference in listOf(com.healthmd.domain.model.UnitPreference.METRIC, com.healthmd.domain.model.UnitPreference.IMPERIAL)) {
            for (visibleOwners in listOf(true, false)) {
                val facts = mutableMapOf("synthetic" to "accepted-workout-source")
                val sampleFacts = mutableMapOf("synthetic" to "accepted-series-source")
                val sampleContext = mutableMapOf("measurement" to "accepted-context")
                val samples = mutableListOf(com.healthmd.domain.model.TimestampedSample(workout.startTime, 160.125,
                    metadata = sampleFacts, context = sampleContext, exactTime = workout.exactStartTime))
                val sourceIds = mutableListOf("accepted-correlated-source")
                val correlations = mutableMapOf<String, List<String>>("heart_rate" to sourceIds)
                val laps = mutableListOf(com.healthmd.domain.model.WorkoutLapData(workout.startTime, checkNotNull(workout.endTime),
                    exactStartTime = workout.exactStartTime, exactEndTime = workout.exactEndTime))
                val segments = mutableListOf(com.healthmd.domain.model.WorkoutSegmentData(workout.startTime, checkNotNull(workout.endTime),
                    "running", exactStartTime = workout.exactStartTime, exactEndTime = workout.exactEndTime))
                val splits = mutableListOf(com.healthmd.domain.model.WorkoutSplitData(1, workout.startTime, checkNotNull(workout.endTime),
                    workout.duration, exactStartTime = workout.exactStartTime, exactEndTime = workout.exactEndTime))
                val route = mutableListOf(com.healthmd.domain.model.WorkoutRoutePointData(workout.startTime, 0.0, 0.0,
                    exactTime = workout.exactStartTime))
                val workouts = mutableListOf(workout.copy(metadata = facts, laps = laps, segments = segments,
                    splits = splits, route = route, routeAccess = com.healthmd.domain.model.WorkoutRouteAccess.DATA,
                    correlatedSourceIds = correlations, heartRateSamples = samples, speedSamples = samples,
                    cyclingCadenceSamples = samples, stepsCadenceSamples = samples, powerSamples = samples,
                    elevationSamples = samples))
                val data = HealthData(date = LocalDate.of(2026, 11, 1), workouts = workouts)
                val fields = com.healthmd.domain.model.FrontmatterConfiguration.defaultFields.map { field ->
                    field.copy(isEnabled = visibleOwners || field.originalKey !in setOf("workout_count", "workouts", "workout_minutes"))
                }
                val request = FrozenDailyAggregateExportRequest.capture(data, ExportSettings(
                    exportFormats = ExportFormat.entries.toSet(), includeGranularData = true, includeMetadata = false,
                    formatCustomization = FormatCustomization(unitPreference = preference,
                        frontmatterConfig = com.healthmd.domain.model.FrontmatterConfiguration(fields = fields)),
                    metricSelection = com.healthmd.domain.model.MetricSelectionState(enabledMetrics = setOf("workouts")),
                    executionSleepCaptureContext = context, executionSleepCaptureAuthorityIsFrozen = true),
                    AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                    DailyAggregateExportIds("device-workout-${preference.name}-$visibleOwners", "device-workout-session-${preference.name}-$visibleOwners"))
                val planner = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("cannot borrow an ambient clock") })
                val accepted = planner.plan(request).plan.items.associate { it.relativePath to it.content.decodeToString() }
                workouts.clear(); facts.clear(); sampleFacts.clear(); sampleContext.clear(); samples.clear()
                sourceIds.clear(); correlations.clear(); laps.clear(); segments.clear(); splits.clear(); route.clear()
                val result = planner.plan(request)
                assertEquals(accepted, result.plan.items.associate { it.relativePath to it.content.decodeToString() })
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
    }

    @Test
    fun packagedRegistryThreeKeepsVersionTwoExactAndCorrectsWorkoutExtrema() {
        val service = com.healthmd.core.HealthMdCoreService()
        for (profile in listOf(com.healthmd.core.CoreMetricRegistryProfile.ANDROID_SLEEP_V6,
            com.healthmd.core.CoreMetricRegistryProfile.APPLE_HEALTH_DATA_V11)) {
            val original = service.getMetricRegistry(profile, 2u)
            val corrected = service.getMetricRegistry(profile, 3u)
            assertEquals(com.healthmd.core.HEALTHMD_SLEEP_REGISTRY_SHA256, original.registrySha256)
            assertEquals(com.healthmd.core.HEALTHMD_WORKOUT_RANGE_REGISTRY_SHA256, corrected.registrySha256)
            for ((key, rule) in listOf("workout_max_heart_rate" to "maximum", "workout_min_heart_rate" to "minimum", "workout_max_power" to "maximum")) {
                // Android v2 has no range reducer; Apple's old v2 explicitly declares sum.
                val oldRule = if (profile == com.healthmd.core.CoreMetricRegistryProfile.ANDROID_SLEEP_V6) "" else "sum"
                assertEquals(oldRule, original.outputs.single { it.key == key }.rollup)
                assertEquals(rule, corrected.outputs.single { it.key == key }.rollup)
            }
            assertEquals(original.outputs.map { it.key }, corrected.outputs.map { it.key })
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
