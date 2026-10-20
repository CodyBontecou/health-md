package com.healthmd.data.health

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.time.TimeRangeFilter
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import androidx.test.platform.app.InstrumentationRegistry
import com.healthmd.domain.exportengine.AndroidExportProfile
import com.healthmd.domain.exportengine.DailyAggregateExportIds
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.FrozenDailyAggregateExportRequest
import com.healthmd.domain.exportengine.HealthMdRustDailyAggregatePlanner
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.SleepDayAttribution
import java.io.File
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import kotlinx.coroutines.runBlocking
import org.json.JSONArray
import org.json.JSONObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in, read-only Health Connect acceptance on an owner-prepared synthetic test phone. */
@LargeTest
@RunWith(AndroidJUnit4::class)
class LiveSleepCaptureAcceptanceTest {
    @Test
    fun actualProviderSleepKeepsWakeOwnerAndExactSourceThroughEveryFormat() = runBlocking {
        val args = InstrumentationRegistry.getArguments()
        assumeTrue("Use the isolated live-sleep acceptance runner with synthetic source dates.",
            args.getString("healthmdLiveSleepCapture") == "true")
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        check(context.packageName == "com.healthmd.android.e2e") { "Live acceptance requires the isolated application" }
        val requested = requireNotNull(args.getString("healthmdSleepDates")).split(',').map(LocalDate::parse).distinct().sorted()
        require(requested.isNotEmpty() && requested.size <= 31 && ChronoUnit.DAYS.between(requested.first(), requested.last()) <= 30)
        // Include each preceding note to catch duplicate or start-date attribution, too.
        val dates = requested.flatMap { listOf(it.minusDays(1), it) }.distinct().sorted()
        val zone = ZoneId.of(requireNotNull(args.getString("healthmdSleepZone")))
        val capture = AndroidCaptureContext(zone, SleepDayAttribution.MORNING_ENDS)
        val client = HealthConnectClient.getOrCreate(context)
        assertTrue("Sleep read permission must be granted before acceptance",
            HealthPermission.getReadPermission(SleepSessionRecord::class) in client.permissionController.getGrantedPermissions())

        // Independent SDK baseline: compare actual provider IDs and instants, not reducer output.
        val source = mutableListOf<SleepSessionRecord>()
        var token: String? = null
        var pages = 0
        do {
            check(++pages <= 100) { "Provider acceptance page bound exceeded" }
            val page = client.readRecords(ReadRecordsRequest(SleepSessionRecord::class,
                TimeRangeFilter.between(dates.first().minusDays(1).atStartOfDay(zone).toInstant(),
                    dates.last().plusDays(1).atStartOfDay(zone).toInstant()), pageSize = 100, pageToken = token))
            source += page.records
            check(source.size <= 10_000) { "Provider acceptance record bound exceeded" }
            token = page.pageToken?.takeIf(String::isNotEmpty)
        } while (token != null)
        val expected = source.filter { it.startTime < it.endTime && it.endTime.atZone(zone).toLocalDate() in requested }
        assertTrue("No synthetic overnight sleep was available on the supplied dates",
            expected.any { it.endTime.atZone(zone).toLocalDate() in requested
                && it.startTime.atZone(zone).toLocalDate() < it.endTime.atZone(zone).toLocalDate() })
        assertTrue("Native provider IDs are required", expected.all { it.metadata.id.isNotBlank() })
        assertEquals("Provider IDs must be distinct", expected.size, expected.map { it.metadata.id }.toSet().size)
        val selection = DataTypeSelection().deselectAll().copy(sleep = true)
        val days = HealthConnectManager(context, sharedClient = client).fetchHealthDataRange(
            dates, selection, includeGranularData = true, zoneId = zone, sleepDayAttribution = capture.sleepDayAttribution)
        assertEquals("Capture must return every requested owner and negative-control day", dates.size, days.size)
        assertEquals(dates.toSet(), days.map { it.date }.toSet())
        val acceptedIds = expected.map { it.metadata.id }.toSet()
        val output = File(context.cacheDir, "live-sleep-acceptance")
        check(!output.exists() && output.mkdirs()) { "Acceptance output already exists or is unavailable" }
        var artifacts = 0
        for (day in days) {
            val owned = expected.filter { it.endTime.atZone(zone).toLocalDate() == day.date }.associateBy { it.metadata.id }
            val observed = if (day.date in requested) day.sleep.sessions
                else day.sleep.sessions.filter { it.identity?.nativeId in acceptedIds }
            assertEquals("Captured source IDs must match the SDK wake-date owners",
                owned.keys, observed.map { it.identity?.nativeId }.toSet())
            // Preceding notes are negative ownership controls, not extra export scope.
            if (owned.isEmpty()) continue
            assertEquals(owned.values.sumOf { java.time.Duration.between(it.startTime, it.endTime).toMillis() },
                day.sleep.totalDuration.inWholeMilliseconds)
            for (entry in day.sleep.sessions) {
                val original = owned.getValue(requireNotNull(entry.identity?.nativeId))
                assertEquals(original.startTime.epochSecond, entry.exactStartTime?.epochSecond)
                assertEquals(original.startTime.nano, entry.exactStartTime?.nano)
                assertEquals(original.endTime.epochSecond, entry.exactEndTime?.epochSecond)
                assertEquals(original.endTime.nano, entry.exactEndTime?.nano)
            }
            for (metadata in listOf(false, true)) {
                val settings = ExportSettings(dataTypes = selection, exportFormats = ExportFormat.entries.toSet(),
                    includeGranularData = true, includeMetadata = metadata,
                    metricSelection = MetricSelectionState(enabledMetrics = setOf("sleep_total", "sleep_light", "sleep_deep",
                        "sleep_rem", "sleep_awake", "sleep_in_bed", "sleep_bedtime", "sleep_wake")),
                    executionSleepCaptureContext = capture, executionSleepCaptureAuthorityIsFrozen = true)
                val request = FrozenDailyAggregateExportRequest.capture(day, settings,
                    AndroidExportProfile.android_sleep_v6, ExportEngineMode.rust,
                    DailyAggregateExportIds("live-sleep-${day.date}-$metadata", "live-sleep-session-${day.date}-$metadata"))
                val plan = HealthMdRustDailyAggregatePlanner(zoneIdProvider = { error("No ambient capture clock") }).plan(request).plan
                assertEquals(4, plan.items.size)
                for (item in plan.items) {
                    if (item.relativePath.endsWith(".json")) {
                        val root = JSONObject(item.content.decodeToString())
                        assertEquals("android-sleep-v6", root.getString("schema_profile"))
                        assertEquals(day.date.toString(), root.getString("date"))
                        val sessions = root.getJSONObject("sleep").getJSONArray("sleepSessions")
                        assertEquals(owned.size, sessions.length())
                        for (i in 0 until sessions.length()) {
                            val exported = sessions.getJSONObject(i)
                            val original = owned.getValue(exported.getJSONObject("identity").getString("nativeId"))
                            assertEquals(original.startTime, Instant.parse(exported.getString("startTimeISO")))
                            assertEquals(original.endTime, Instant.parse(exported.getString("endTimeISO")))
                        }
                    }
                    val file = File(output, "$metadata/${item.relativePath}")
                    check(file.canonicalPath.startsWith(output.canonicalPath + File.separator))
                    check(file.parentFile!!.mkdirs() || file.parentFile!!.isDirectory)
                    file.writeBytes(item.content)
                    artifacts++
                }
            }
        }
        val baseline = JSONArray(expected.map { record -> JSONObject()
            .put("nativeId", record.metadata.id).put("startTimeISO", record.startTime.toString())
            .put("endTimeISO", record.endTime.toString()).put("ownerDate", record.endTime.atZone(zone).toLocalDate().toString()) })
        File(output, "sdk-baseline.json").writeText(baseline.toString())
        File(output, "receipt.json").writeText(JSONObject().put("provider", "Health Connect")
            .put("sourceRecords", expected.size).put("artifacts", artifacts).put("metadataVariants", 2)
            .put("productionAdmissionEnabled", false).toString())
    }
}
