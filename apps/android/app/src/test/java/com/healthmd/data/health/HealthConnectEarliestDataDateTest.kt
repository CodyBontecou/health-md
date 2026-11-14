package com.healthmd.data.health

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.*
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.request.ReadRecordsRequest
import androidx.health.connect.client.response.ReadRecordsResponse
import androidx.health.connect.client.units.Mass
import com.google.common.truth.Truth.assertThat
import io.mockk.*
import java.time.Instant
import java.time.ZoneId
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.test.runTest
import org.junit.Test

class HealthConnectEarliestDataDateTest {
    private val client = mockk<HealthConnectClient>()
    private val permissions = mockk<PermissionController>()
    private val manager = HealthConnectManager(mockk<Context>(relaxed = true), client)

    private fun grant(vararg types: kotlin.reflect.KClass<out Record>) {
        every { client.permissionController } returns permissions
        coEvery { permissions.getGrantedPermissions() } returns types.map { HealthPermission.getReadPermission(it) }.toSet()
    }

    @Test
    fun `all time discovers older non-step interval and instant records`() = runTest {
        grant(StepsRecord::class, SleepSessionRecord::class, WeightRecord::class)
        val steps = Instant.parse("2026-08-03T12:00:00Z")
        val sleep = steps.minusSeconds(86400)
        val weight = sleep.minusSeconds(86400)
        val requests = mutableListOf<ReadRecordsRequest<Record>>()
        coEvery { client.readRecords(capture(requests)) } answers {
            val records = when (firstArg<ReadRecordsRequest<Record>>().recordType) {
                StepsRecord::class -> listOf(StepsRecord(steps, null, steps.plusSeconds(60), null, 100, Metadata.manualEntry()))
                SleepSessionRecord::class -> listOf(SleepSessionRecord(sleep, null, sleep.plusSeconds(3600), null, metadata = Metadata.manualEntry()))
                WeightRecord::class -> listOf(WeightRecord(weight, null, Mass.kilograms(70.0), Metadata.manualEntry()))
                StepsCadenceRecord::class -> emptyList()
                else -> error("Unpermitted type queried")
            }
            ReadRecordsResponse(records, null)
        }
        assertThat(manager.getEarliestDataDate()).isEqualTo(weight.atZone(ZoneId.systemDefault()).toLocalDate())
        assertThat(requests.map { it.recordType }).containsExactly(
            StepsRecord::class, StepsCadenceRecord::class, SleepSessionRecord::class, WeightRecord::class,
        )
        assertThat(requests.all { it.ascendingOrder && it.pageSize == 1 }).isTrue()
    }

    @Test
    fun `sleep only permission discovers all time without steps`() = runTest {
        grant(SleepSessionRecord::class)
        val start = Instant.parse("2020-08-03T12:00:00Z")
        coEvery { client.readRecords(any<ReadRecordsRequest<SleepSessionRecord>>()) } returns ReadRecordsResponse(
            listOf(SleepSessionRecord(start, null, start.plusSeconds(3600), null, metadata = Metadata.manualEntry())), null,
        )
        assertThat(manager.getEarliestDataDate()).isEqualTo(start.atZone(ZoneId.systemDefault()).toLocalDate())
        coVerify(exactly = 1) { client.readRecords(any<ReadRecordsRequest<Record>>()) }
    }

    @Test
    fun `empty permitted records return no discovered date`() = runTest {
        grant(StepsRecord::class)
        coEvery { client.readRecords(any<ReadRecordsRequest<StepsRecord>>()) } returns ReadRecordsResponse(emptyList(), null)
        assertThat(manager.getEarliestDataDate()).isNull()
    }

    @Test
    fun `permission discovery failure keeps best effort fallback`() = runTest {
        grant(StepsRecord::class)
        coEvery { permissions.getGrantedPermissions() } throws IllegalStateException("unavailable")
        assertThat(manager.getEarliestDataDate()).isNull()
        coVerify(exactly = 0) { client.readRecords(any<ReadRecordsRequest<Record>>()) }
    }

    @Test
    fun `actionable discovery failures do not become empty data`() = runTest {
        grant(StepsRecord::class)
        for (error in listOf(CancellationException("cancelled"), SecurityException("Historical access required"),
            IllegalStateException("Health Connect rate limit exceeded"))) {
            coEvery { client.readRecords(any<ReadRecordsRequest<StepsRecord>>()) } throws error
            val actual = try { manager.getEarliestDataDate(); null } catch (caught: Exception) { caught }
            assertThat(actual).isSameInstanceAs(error)
        }
    }
}
