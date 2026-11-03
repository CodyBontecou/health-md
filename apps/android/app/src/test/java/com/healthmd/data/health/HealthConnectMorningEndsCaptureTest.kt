package com.healthmd.data.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.records.SleepSessionRecord
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.response.ReadRecordsResponse
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.JsonExporter
import com.healthmd.domain.model.AndroidCaptureContext
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.SleepDayAttribution
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.mockk
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test

/** Real native capture adapter and exporter, with only the Health Connect IPC boundary substituted. */
class HealthConnectMorningEndsCaptureTest {
    private val zone = ZoneId.of("America/New_York")
    private val wakeDate = LocalDate.of(2026, 11, 1)

    @Test
    fun wakeDateCapturePreservesTheDstNightAndSourceClocksWithoutInventingLightStages() = runTest {
        val start = Instant.parse("2026-11-01T02:00:00.123456789Z")
        val end = Instant.parse("2026-11-01T12:00:00.123456789Z")
        val foldStart = Instant.parse("2026-11-01T05:30:00.123456789Z")
        val foldEnd = Instant.parse("2026-11-01T06:30:00.123456789Z")
        val source = SleepSessionRecord(
            startTime = start, startZoneOffset = ZoneOffset.of("-04:00"),
            endTime = end, endZoneOffset = ZoneOffset.of("-05:00"),
            metadata = Metadata.manualEntry(clientRecordId = "synthetic-night"),
            stages = listOf(
                SleepSessionRecord.Stage(start, Instant.parse("2026-11-01T04:00:00.123456789Z"), SleepSessionRecord.STAGE_TYPE_SLEEPING),
                SleepSessionRecord.Stage(foldStart, foldEnd, SleepSessionRecord.STAGE_TYPE_LIGHT),
            ),
        )
        val requests = mutableListOf<ReadRecordsRequest<SleepSessionRecord>>()
        val client = mockk<HealthConnectClient>()
        coEvery { client.readRecords(capture(requests)) } returns ReadRecordsResponse(listOf(source), null)
        val manager = HealthConnectManager(mockk<Context>(relaxed = true), client)
        val days = manager.fetchHealthDataRange(
            listOf(wakeDate.minusDays(1), wakeDate, wakeDate.plusDays(1)),
            DataTypeSelection().deselectAll().copy(sleep = true), true, zone,
            sleepDayAttribution = SleepDayAttribution.MORNING_ENDS,
        )

        assertThat(days[0].sleep.hasData).isFalse()
        assertThat(days[2].sleep.hasData).isFalse()
        val sleep = days[1].sleep
        assertThat(sleep.totalDuration.inWholeSeconds).isEqualTo(36000)
        assertThat(sleep.lightSleep.inWholeSeconds).isEqualTo(3600)
        assertThat(sleep.sessions).hasSize(1)
        val captured = sleep.sessions.single()
        assertThat(captured.exactStartTime!!.instant()).isEqualTo(start)
        assertThat(captured.exactEndTime!!.instant()).isEqualTo(end)
        assertThat(captured.exactStartTime!!.offset).isEqualTo("-04:00")
        assertThat(captured.exactEndTime!!.offset).isEqualTo("-05:00")
        assertThat(captured.identity!!.clientRecordId).isEqualTo("synthetic-night")
        assertThat(sleep.stages.map { it.stage }).containsExactly("sleeping", "light").inOrder()
        assertThat(sleep.stages.last().exactStartTime!!.instant()).isEqualTo(foldStart)
        assertThat(sleep.stages.last().exactEndTime!!.instant()).isEqualTo(foldEnd)
        // Fold clocks are identical locally, but the machine instants remain an hour apart.
        assertThat(sleep.stages.last().startTime).isEqualTo(sleep.stages.last().endTime)
        assertThat(requests).hasSize(1)
        assertThat(requests.single().timeRangeFilter.startTime).isEqualTo(Instant.parse("2026-10-30T16:00:00Z"))
        assertThat(requests.single().timeRangeFilter.endTime).isEqualTo(Instant.parse("2026-11-03T17:00:00Z"))
        coVerify(exactly = 1) { client.readRecords(any<ReadRecordsRequest<SleepSessionRecord>>()) }

        val root = Json.parseToJsonElement(JsonExporter().export(days[1], includeGranularData = true,
            captureContext = AndroidCaptureContext(zone, SleepDayAttribution.MORNING_ENDS))).jsonObject
        assertThat(root.getValue("schema_profile").jsonPrimitive.content).isEqualTo("android-sleep-v6")
        val exported = root.getValue("sleep").jsonObject
        assertThat(exported.getValue("bedtimeISO").jsonPrimitive.content).isEqualTo("2026-11-01T02:00:00.123456789Z")
        assertThat(exported.getValue("wakeTimeISO").jsonPrimitive.content).isEqualTo("2026-11-01T12:00:00.123456789Z")
        assertThat(exported.getValue("lightSleep").jsonPrimitive.content.toDouble()).isEqualTo(3600.0)
        assertThat(exported.getValue("sleepStages").jsonArray.last().jsonObject.getValue("startDate").jsonPrimitive.content)
            .isEqualTo("2026-11-01T05:30:00.123456789Z")

        // Same SDK inputs keep the historical default's owner date and Light alias calculation.
        val night = manager.fetchHealthDataRange(listOf(wakeDate.minusDays(1)),
            DataTypeSelection().deselectAll().copy(sleep = true), true, zone).single()
        assertThat(night.sleep.totalDuration.inWholeSeconds).isEqualTo(36000)
        assertThat(night.sleep.lightSleep.inWholeSeconds).isEqualTo(10800)
        val historical = Json.parseToJsonElement(JsonExporter().export(night)).jsonObject
        assertThat(historical.containsKey("schema_profile")).isFalse()
        assertThat(historical.getValue("sleep").jsonObject.getValue("coreSleep").jsonPrimitive.content.toDouble()).isEqualTo(10800.0)
    }

    @Test
    fun nativeWakeDateCaptureOwnsMidnightEndsAndWholeNoonSpanningNapsExactlyOnce() = runTest {
        fun source(id: String, start: String, end: String) = SleepSessionRecord(
            startTime = Instant.parse(start), startZoneOffset = null,
            endTime = Instant.parse(end), endZoneOffset = null,
            metadata = Metadata.manualEntry(clientRecordId = id),
        )
        val records = listOf(
            source("midnight-first", "2026-11-01T03:00:00Z", "2026-11-01T04:00:00Z"),
            source("noon-spanning-nap", "2026-11-01T16:00:00Z", "2026-11-01T18:00:00Z"),
            source("midnight-next", "2026-11-02T04:00:00Z", "2026-11-02T05:00:00Z"),
        )
        val client = mockk<HealthConnectClient>()
        coEvery { client.readRecords(any<ReadRecordsRequest<SleepSessionRecord>>()) } returns ReadRecordsResponse(records, null)
        val manager = HealthConnectManager(mockk<Context>(relaxed = true), client)
        val days = manager.fetchHealthDataRange(listOf(wakeDate.minusDays(1), wakeDate, wakeDate.plusDays(1)),
            DataTypeSelection().deselectAll().copy(sleep = true), true, zone,
            sleepDayAttribution = SleepDayAttribution.MORNING_ENDS)

        assertThat(days[0].sleep.hasData).isFalse()
        assertThat(days[1].sleep.totalDuration.inWholeSeconds).isEqualTo(10800)
        assertThat(days[2].sleep.totalDuration.inWholeSeconds).isEqualTo(3600)
        assertThat(days[1].sleep.sessions.map { it.identity!!.clientRecordId })
            .containsExactly("midnight-first", "noon-spanning-nap").inOrder()
        assertThat(days[2].sleep.sessions.single().identity!!.clientRecordId).isEqualTo("midnight-next")
        assertThat(days.flatMap { it.sleep.sessions }.map { it.identity!!.clientRecordId }.toSet()).hasSize(3)
        val context = AndroidCaptureContext(zone, SleepDayAttribution.MORNING_ENDS)
        val expectedStarts = listOf(listOf("2026-11-01T03:00:00Z", "2026-11-01T16:00:00Z"), listOf("2026-11-02T04:00:00Z"))
        val expectedEnds = listOf(listOf("2026-11-01T04:00:00Z", "2026-11-01T18:00:00Z"), listOf("2026-11-02T05:00:00Z"))
        for ((index, day) in days.drop(1).withIndex()) {
            val root = Json.parseToJsonElement(JsonExporter().export(day, includeGranularData = true, captureContext = context)).jsonObject
            val sessions = root.getValue("sleep").jsonObject.getValue("sleepSessions").jsonArray
            assertThat(sessions.map { it.jsonObject.getValue("startTimeISO").jsonPrimitive.content })
                .containsExactlyElementsIn(expectedStarts[index]).inOrder()
            assertThat(sessions.map { it.jsonObject.getValue("endTimeISO").jsonPrimitive.content })
                .containsExactlyElementsIn(expectedEnds[index]).inOrder()
        }
    }
}
