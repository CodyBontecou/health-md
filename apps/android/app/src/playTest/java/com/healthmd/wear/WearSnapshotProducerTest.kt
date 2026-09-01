package com.healthmd.wear

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.records.SleepSessionRecord
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.VitalsData
import com.healthmd.widget.data.WidgetHealthDataSource
import com.healthmd.wearable.contract.WearPermissionState
import io.mockk.coEvery
import io.mockk.mockk
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import kotlin.time.Duration.Companion.minutes
import kotlinx.coroutines.test.runTest
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class WearSnapshotProducerTest {
    @Test
    fun `producer preserves partial permission state and maps asleep stages and oxygen once`() = runTest {
        val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<Context>()
        context.getSharedPreferences("wear-sync-private", Context.MODE_PRIVATE).edit().clear().commit()
        val client = mockk<HealthConnectClient>()
        val permissions = mockk<PermissionController>()
        coEvery { client.permissionController } returns permissions
        coEvery { permissions.getGrantedPermissions() } returns setOf(
            HealthPermission.getReadPermission(SleepSessionRecord::class),
            HealthPermission.getReadPermission(OxygenSaturationRecord::class),
        )
        val day = LocalDate.parse("2026-08-02")
        val source = object : WidgetHealthDataSource {
            var selection: com.healthmd.data.health.HealthConnectWidgetReadSelection? = null
            var zone: ZoneId? = null
            override suspend fun readRecentDays(
                today: LocalDate,
                selection: com.healthmd.data.health.HealthConnectWidgetReadSelection,
                dayCount: Int,
                zoneId: ZoneId,
            ): List<HealthData> {
                this.selection = selection
                this.zone = zoneId
                return listOf(HealthData(
                    date = day,
                    sleep = SleepData(
                        totalDuration = 540.minutes,
                        deepSleep = 90.minutes,
                        remSleep = 120.minutes,
                        lightSleep = 240.minutes,
                        awakeTime = 90.minutes,
                    ),
                    vitals = VitalsData(bloodOxygenAvg = 0.97),
                ))
            }
            override suspend fun isAvailable() = true
            override fun isBeforeFirstUnlock() = false
        }
        val producer = WearSnapshotProducer(context, HealthConnectManager(context, client), source)

        val snapshot = producer.produce(
            now = Instant.parse("2026-08-02T12:00:00Z"),
            zone = ZoneId.of("UTC"),
        )

        assertThat(source.selection?.sleepSessions).isTrue()
        assertThat(source.zone).isEqualTo(ZoneId.of("UTC"))
        assertThat(source.selection?.oxygenSaturation).isTrue()
        assertThat(source.selection?.steps).isFalse()
        assertThat(snapshot.permissionState).isEqualTo(WearPermissionState.PERMISSION_REQUIRED)
        assertThat(snapshot.days.single().sleepMinutes).isWithin(0.001).of(450.0)
        assertThat(snapshot.days.single().bloodOxygenPercent).isWithin(0.001).of(97.0)
    }

    @Test
    fun `publication recheck strips aggregates after full permission revocation`() = runTest {
        val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<Context>()
        val client = mockk<HealthConnectClient>()
        val permissions = mockk<PermissionController>()
        coEvery { client.permissionController } returns permissions
        coEvery { permissions.getGrantedPermissions() } returns emptySet()
        val producer = WearSnapshotProducer(context, HealthConnectManager(context, client), mockk())
        val aggregate = com.healthmd.wearable.contract.WearHealthSnapshot(
            sequence = 9,
            capturedAtEpochMillis = 100,
            capturedZoneId = "UTC",
            days = listOf(com.healthmd.wearable.contract.WearHealthDay("2026-08-13", steps = 10)),
            permissionState = WearPermissionState.READY,
        )

        val redacted = producer.redactRevokedFields(aggregate)

        assertThat(redacted.days).isEmpty()
        assertThat(redacted.permissionState).isEqualTo(WearPermissionState.PERMISSION_REQUIRED)
    }

    @Test
    fun `publication recheck strips only categories whose grants were revoked`() = runTest {
        val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<Context>()
        val client = mockk<HealthConnectClient>()
        val permissions = mockk<PermissionController>()
        coEvery { client.permissionController } returns permissions
        coEvery { permissions.getGrantedPermissions() } returns setOf(
            HealthPermission.getReadPermission(StepsRecord::class),
        )
        val producer = WearSnapshotProducer(context, HealthConnectManager(context, client), mockk())
        val aggregate = com.healthmd.wearable.contract.WearHealthSnapshot(
            sequence = 9,
            capturedAtEpochMillis = 100,
            capturedZoneId = "UTC",
            days = listOf(com.healthmd.wearable.contract.WearHealthDay(
                "2026-08-13",
                steps = 10,
                bloodOxygenPercent = 97.0,
            )),
            permissionState = WearPermissionState.READY,
        )

        val redacted = producer.redactRevokedFields(aggregate)

        assertThat(redacted.days.single().steps).isEqualTo(10)
        assertThat(redacted.days.single().bloodOxygenPercent).isNull()
        assertThat(redacted.permissionState).isEqualTo(WearPermissionState.PERMISSION_REQUIRED)
    }

    @Test
    fun `reserved clear barrier remains newer across clock rollback`() = runTest {
        val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<Context>()
        context.getSharedPreferences("wear-sync-private", Context.MODE_PRIVATE).edit().clear().commit()
        val source = mockk<WidgetHealthDataSource>()
        coEvery { source.isAvailable() } returns false
        val producer = WearSnapshotProducer(context, mockk(relaxed = true), source)
        val snapshot = producer.produce(Instant.ofEpochMilli(10_000), ZoneId.of("UTC"))
        val clearBarrier = producer.reserveSequence(clock = 1_000)
        assertThat(clearBarrier).isGreaterThan(snapshot.sequence)
    }

    @Test
    fun `producer sequence remains monotonic across clock rollback`() = runTest {
        val context = androidx.test.core.app.ApplicationProvider.getApplicationContext<Context>()
        context.getSharedPreferences("wear-sync-private", Context.MODE_PRIVATE).edit().clear().commit()
        val source = mockk<WidgetHealthDataSource>()
        coEvery { source.isAvailable() } returns false
        val producer = WearSnapshotProducer(context, mockk(relaxed = true), source)
        val first = producer.produce(Instant.ofEpochMilli(10_000), ZoneId.of("UTC"))
        val second = producer.produce(Instant.ofEpochMilli(1_000), ZoneId.of("UTC"))
        assertThat(second.sequence).isGreaterThan(first.sequence)
    }
}
