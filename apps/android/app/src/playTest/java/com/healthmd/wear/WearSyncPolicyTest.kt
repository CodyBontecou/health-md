package com.healthmd.wear

import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.OxygenSaturationRecord
import androidx.health.connect.client.records.StepsRecord
import androidx.test.core.app.ApplicationProvider
import androidx.work.ExistingPeriodicWorkPolicy
import androidx.work.ExistingWorkPolicy
import androidx.work.ListenableWorker
import androidx.work.OneTimeWorkRequest
import androidx.work.Operation
import androidx.work.PeriodicWorkRequest
import androidx.work.WorkManager
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.DataClient
import com.google.android.gms.wearable.DataItem
import com.google.android.gms.wearable.DataMap
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.PutDataRequest
import com.google.common.truth.Truth.assertThat
import com.google.common.util.concurrent.Futures
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.wearable.contract.WearAckReason
import com.healthmd.wearable.contract.WearHealthDay
import com.healthmd.wearable.contract.WearHealthSnapshotCodec
import com.healthmd.wearable.contract.WearSnapshotAck
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import io.mockk.slot
import io.mockk.verify
import org.junit.Test
import java.time.Instant
import java.time.ZoneId
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class WearSyncPolicyTest {
    @Test fun `background eligibility requires watch background and any data permission`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val scheduler = WearPhoneSyncScheduler(context, mockk<HealthConnectManager>(), WearSyncStatusStore(context))
        assertThat(scheduler.eligibility(true, true, true)).isEqualTo(WearPhoneSyncScheduler.Eligibility.ELIGIBLE)
        assertThat(scheduler.eligibility(false, true, true)).isEqualTo(WearPhoneSyncScheduler.Eligibility.INELIGIBLE)
        assertThat(scheduler.eligibility(true, false, true)).isEqualTo(WearPhoneSyncScheduler.Eligibility.INELIGIBLE)
        assertThat(scheduler.eligibility(true, true, false)).isEqualTo(WearPhoneSyncScheduler.Eligibility.PERMISSION_REVOKED)
        assertThat(scheduler.eligibility(false, false, false)).isEqualTo(WearPhoneSyncScheduler.Eligibility.PERMISSION_REVOKED)
        assertThat(scheduler.eligibility(true, true, true, retainedStateNeedsRedaction = true))
            .isEqualTo(WearPhoneSyncScheduler.Eligibility.PERMISSION_REVOKED)
    }

    @Test fun `permission redaction is a dedicated worker mode rather than manual sync`() {
        assertThat(WearPhoneSyncWorker.PERMISSION_REDACTION).isNotEqualTo(WearPhoneSyncWorker.USER_INITIATED)
        assertThat(WearPhoneSyncWorker.PERMISSION_REDACTION).contains("permission-redaction")

        val capabilitySecurityFailure = SecurityException("capability denied")
        val dataItemSecurityFailure = SecurityException("putDataItem denied")
        assertThat(syncFailureResult(redactRetainedState = true, capabilitySecurityFailure))
            .isEqualTo(WearPhoneSyncResult.RETRY)
        assertThat(syncFailureResult(redactRetainedState = true, dataItemSecurityFailure))
            .isEqualTo(WearPhoneSyncResult.RETRY)
        assertThat(syncFailureResult(redactRetainedState = true, IllegalStateException("Play services")))
            .isEqualTo(WearPhoneSyncResult.RETRY)
        assertThat(syncFailureResult(redactRetainedState = false, capabilitySecurityFailure))
            .isEqualTo(WearPhoneSyncResult.PERMISSION_REQUIRED)

        assertThat(workerResult(WearPhoneSyncResult.RETRY))
            .isInstanceOf(ListenableWorker.Result.Retry::class.java)
        assertThat(workerResult(WearPhoneSyncResult.PERMISSION_REQUIRED))
            .isInstanceOf(ListenableWorker.Result.Success::class.java)
    }

    @Test fun `permission redaction worker path retries transport failure and reconciles periodic work`() = kotlinx.coroutines.runBlocking {
        val sync = mockk<WearPhoneSync>()
        val scheduler = mockk<WearPhoneSyncScheduler>()
        coEvery { sync.sync(redactRetainedState = true) } returns WearPhoneSyncResult.RETRY
        coEvery { scheduler.reconcile(WearPhoneSyncScheduler.Eligibility.INELIGIBLE) } returns Unit

        val result = runPermissionRedaction(sync, scheduler)

        assertThat(result).isInstanceOf(ListenableWorker.Result.Retry::class.java)
        coVerify(exactly = 1) { sync.sync(redactRetainedState = true) }
        coVerify(exactly = 1) { scheduler.reconcile(WearPhoneSyncScheduler.Eligibility.INELIGIBLE) }
    }

    @Test fun `successful permission redaction re-evaluates still-granted background eligibility`() = kotlinx.coroutines.runBlocking {
        val sync = mockk<WearPhoneSync>()
        val scheduler = mockk<WearPhoneSyncScheduler>()
        coEvery { sync.sync(redactRetainedState = true) } returns WearPhoneSyncResult.QUEUED
        coEvery { scheduler.reconcile() } returns Unit

        val result = runPermissionRedaction(sync, scheduler)

        assertThat(result).isInstanceOf(ListenableWorker.Result.Success::class.java)
        coVerify(exactly = 1) { scheduler.reconcile() }
        coVerify(exactly = 0) { scheduler.reconcile(WearPhoneSyncScheduler.Eligibility.INELIGIBLE) }
    }

    @Test fun `permission audit redacts on revoked grant and retries unknown grant state`() = kotlinx.coroutines.runBlocking {
        val sync = mockk<WearPhoneSync>()
        val scheduler = mockk<WearPhoneSyncScheduler>()
        coEvery { scheduler.permissionAuditEligibility() } returns WearPhoneSyncScheduler.Eligibility.PERMISSION_REVOKED
        coEvery { sync.sync(redactRetainedState = true) } returns WearPhoneSyncResult.QUEUED
        coEvery { scheduler.reconcile() } returns Unit

        assertThat(runPermissionAudit(sync, scheduler)).isInstanceOf(ListenableWorker.Result.Success::class.java)
        coVerify(exactly = 1) { sync.sync(redactRetainedState = true) }

        coEvery { scheduler.permissionAuditEligibility() } returns WearPhoneSyncScheduler.Eligibility.UNKNOWN
        assertThat(runPermissionAudit(sync, scheduler)).isInstanceOf(ListenableWorker.Result.Retry::class.java)
        coVerify(exactly = 1) { sync.sync(redactRetainedState = true) }
    }

    @Test fun `non-revoked permission audit performs fresh full eligibility reconciliation`() = kotlinx.coroutines.runBlocking {
        val sync = mockk<WearPhoneSync>()
        val scheduler = mockk<WearPhoneSyncScheduler>()
        coEvery { scheduler.permissionAuditEligibility() } returns WearPhoneSyncScheduler.Eligibility.INELIGIBLE
        coEvery { scheduler.reconcile() } returns Unit

        assertThat(runPermissionAudit(sync, scheduler)).isInstanceOf(ListenableWorker.Result.Success::class.java)

        coVerify(exactly = 1) { scheduler.reconcile() }
        coVerify(exactly = 0) { scheduler.reconcile(WearPhoneSyncScheduler.Eligibility.INELIGIBLE) }
        coVerify(exactly = 0) { sync.sync(any(), any()) }
    }

    @Test fun `zero-node permission redaction still publishes aggregate-free durable state`() = kotlinx.coroutines.runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val capabilityClient = mockk<CapabilityClient>()
        val dataClient = mockk<DataClient>()
        val messageClient = mockk<MessageClient>()
        val emptyCapability = mockk<CapabilityInfo> { every { nodes } returns emptySet() }
        every { capabilityClient.getCapability(any(), CapabilityClient.FILTER_ALL) } returns Tasks.forResult(emptyCapability)
        every { capabilityClient.getCapability(any(), CapabilityClient.FILTER_REACHABLE) } returns Tasks.forResult(emptyCapability)
        val request = slot<PutDataRequest>()
        every { dataClient.putDataItem(capture(request)) } returns Tasks.forResult(mockk<DataItem>())
        every { dataClient.deleteDataItems(UriBuilder.tombstone(), DataClient.FILTER_LITERAL) } returns Tasks.forResult(0)
        val producer = mockk<WearSnapshotProducer>()
        val produced = com.healthmd.wearable.contract.WearHealthSnapshot(
            sequence = 42,
            capturedAtEpochMillis = 100,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay(localDate = "2026-08-13", steps = 9_999)),
            permissionState = com.healthmd.wearable.contract.WearPermissionState.READY,
        )
        coEvery { producer.grantedDataPermissions() } returns emptySet()
        every { producer.producePermissionRedaction(any<Instant>(), any<ZoneId>()) } returns produced.copy(
            days = emptyList(),
            permissionState = com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED,
        )

        val sync = WearPhoneSync(context, producer, WearSyncStatusStore(context)).apply {
            capabilityClientFactory = { capabilityClient }
            dataClientFactory = { dataClient }
            messageClientFactory = { messageClient }
        }
        val result = sync.sync(redactRetainedState = true)

        assertThat(result).isEqualTo(WearPhoneSyncResult.QUEUED)
        assertThat(request.captured.uri.path).isEqualTo(com.healthmd.wearable.contract.WearDataPaths.SNAPSHOT)
        val published = WearHealthSnapshotCodec.decode(
            DataMap.fromByteArray(requireNotNull(request.captured.data)).getByteArray("snapshot")!!,
        )!!
        assertThat(published.days).isEmpty()
        assertThat(published.permissionState)
            .isEqualTo(com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED)
        verify(exactly = 1) { dataClient.putDataItem(any()) }
        verify(exactly = 1) { dataClient.deleteDataItems(UriBuilder.tombstone(), DataClient.FILTER_LITERAL) }
    }

    @Test fun `permission redaction publishes without a reachability-only capability query`() = kotlinx.coroutines.runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val capabilityClient = mockk<CapabilityClient>()
        val dataClient = mockk<DataClient>()
        val node = mockk<com.google.android.gms.wearable.Node> { every { id } returns "watch" }
        val installed = mockk<CapabilityInfo> { every { nodes } returns setOf(node) }
        every { capabilityClient.getCapability(any(), CapabilityClient.FILTER_ALL) } returns Tasks.forResult(installed)
        every { capabilityClient.getCapability(any(), CapabilityClient.FILTER_REACHABLE) } returns
            Tasks.forException(SecurityException("reachability unavailable"))
        every { dataClient.putDataItem(any()) } returns Tasks.forResult(mockk<DataItem>())
        every { dataClient.deleteDataItems(UriBuilder.tombstone(), DataClient.FILTER_LITERAL) } returns Tasks.forResult(0)
        val producer = mockk<WearSnapshotProducer>()
        every { producer.producePermissionRedaction(any<Instant>(), any<ZoneId>()) } returns
            com.healthmd.wearable.contract.WearHealthSnapshot(
                sequence = 42,
                capturedAtEpochMillis = 100,
                capturedZoneId = "UTC",
                days = emptyList(),
                permissionState = com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED,
            )
        val sync = WearPhoneSync(context, producer, WearSyncStatusStore(context)).apply {
            capabilityClientFactory = { capabilityClient }
            dataClientFactory = { dataClient }
            messageClientFactory = { mockk() }
        }

        assertThat(sync.sync(redactRetainedState = true)).isEqualTo(WearPhoneSyncResult.QUEUED)
        verify(exactly = 1) { capabilityClient.getCapability(any(), CapabilityClient.FILTER_ALL) }
        verify(exactly = 0) { capabilityClient.getCapability(any(), CapabilityClient.FILTER_REACHABLE) }
        verify(exactly = 1) { dataClient.putDataItem(any()) }
    }

    @Test fun `read-time permission failure publishes aggregate-free replacement in same sync`() = kotlinx.coroutines.runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val status = WearSyncStatusStore(context)
        status.recordSource(com.healthmd.wearable.contract.WearHealthSnapshot(
            sequence = 40,
            capturedAtEpochMillis = 100,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay("2026-08-13", steps = 10)),
            permissionState = com.healthmd.wearable.contract.WearPermissionState.READY,
        ))
        val capabilityClient = mockk<CapabilityClient>()
        val dataClient = mockk<DataClient>()
        val node = mockk<com.google.android.gms.wearable.Node> { every { id } returns "watch" }
        val capability = mockk<CapabilityInfo> { every { nodes } returns setOf(node) }
        every { capabilityClient.getCapability(any(), any()) } returns Tasks.forResult(capability)
        val request = slot<PutDataRequest>()
        every { dataClient.putDataItem(capture(request)) } returns Tasks.forResult(mockk<DataItem>())
        every { dataClient.deleteDataItems(any(), any()) } returns Tasks.forResult(0)
        val producer = mockk<WearSnapshotProducer>()
        coEvery { producer.grantedDataPermissions() } returns WearDataPermissionPolicy.all
        coEvery { producer.produce(any<Instant>(), any<ZoneId>()) } throws SecurityException("revoked during read")
        every { producer.producePermissionRedaction(any<Instant>(), any<ZoneId>()) } returns
            com.healthmd.wearable.contract.WearHealthSnapshot(
                sequence = 41,
                capturedAtEpochMillis = 100,
                capturedZoneId = "UTC",
                days = emptyList(),
                permissionState = com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED,
            )
        val sync = WearPhoneSync(context, producer, status).apply {
            capabilityClientFactory = { capabilityClient }
            dataClientFactory = { dataClient }
            messageClientFactory = { mockk() }
        }

        assertThat(sync.sync()).isEqualTo(WearPhoneSyncResult.PERMISSION_REQUIRED)
        val published = WearHealthSnapshotCodec.decode(
            DataMap.fromByteArray(requireNotNull(request.captured.data)).getByteArray("snapshot")!!,
        )!!
        assertThat(published.days).isEmpty()
    }

    @Test fun `ordinary sync fail closes to aggregate-free publication when retained category was revoked`() = kotlinx.coroutines.runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val status = WearSyncStatusStore(context)
        status.recordSource(com.healthmd.wearable.contract.WearHealthSnapshot(
            sequence = 41,
            capturedAtEpochMillis = 100,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay("2026-08-13", steps = 10, bloodOxygenPercent = 97.0)),
            permissionState = com.healthmd.wearable.contract.WearPermissionState.READY,
        ))
        val capabilityClient = mockk<CapabilityClient>()
        val dataClient = mockk<DataClient>()
        val capability = mockk<CapabilityInfo> { every { nodes } returns emptySet() }
        every { capabilityClient.getCapability(any(), any()) } returns Tasks.forResult(capability)
        val request = slot<PutDataRequest>()
        every { dataClient.putDataItem(capture(request)) } returns Tasks.forResult(mockk<DataItem>())
        every { dataClient.deleteDataItems(any(), any()) } returns Tasks.forResult(0)
        val producer = mockk<WearSnapshotProducer>()
        coEvery { producer.grantedDataPermissions() } returns setOf(
            HealthPermission.getReadPermission(StepsRecord::class),
        )
        every { producer.producePermissionRedaction(any<Instant>(), any<ZoneId>()) } returns
            com.healthmd.wearable.contract.WearHealthSnapshot(
                sequence = 42,
                capturedAtEpochMillis = 100,
                capturedZoneId = "UTC",
                days = emptyList(),
                permissionState = com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED,
            )
        val sync = WearPhoneSync(context, producer, status).apply {
            capabilityClientFactory = { capabilityClient }
            dataClientFactory = { dataClient }
            messageClientFactory = { mockk() }
        }

        val result = sync.sync()

        assertThat(result).isEqualTo(WearPhoneSyncResult.QUEUED)
        val published = WearHealthSnapshotCodec.decode(
            DataMap.fromByteArray(requireNotNull(request.captured.data)).getByteArray("snapshot")!!,
        )!!
        assertThat(published.days).isEmpty()
        assertThat(published.permissionState)
            .isEqualTo(com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED)
        coVerify(exactly = 0) { producer.produce(any(), any()) }
    }

    @Test fun `redaction capability failure is retryable before publication`() = kotlinx.coroutines.runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val capabilityClient = mockk<CapabilityClient>()
        every { capabilityClient.getCapability(any(), CapabilityClient.FILTER_ALL) } returns
            Tasks.forException(SecurityException("capability denied"))
        val dataClient = mockk<DataClient>()
        val sync = WearPhoneSync(context, mockk(), WearSyncStatusStore(context)).apply {
            capabilityClientFactory = { capabilityClient }
            dataClientFactory = { dataClient }
            messageClientFactory = { mockk() }
        }

        val result = sync.sync(redactRetainedState = true)

        assertThat(result).isEqualTo(WearPhoneSyncResult.RETRY)
        assertThat(workerResult(result)).isInstanceOf(ListenableWorker.Result.Retry::class.java)
        verify(exactly = 0) { dataClient.putDataItem(any()) }
    }

    @Test fun `redaction canceled capability task is retryable rather than canceling worker`() = kotlinx.coroutines.runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val capabilityClient = mockk<CapabilityClient>()
        every { capabilityClient.getCapability(any(), CapabilityClient.FILTER_ALL) } returns
            Tasks.forCanceled()
        val sync = WearPhoneSync(context, mockk(), WearSyncStatusStore(context)).apply {
            capabilityClientFactory = { capabilityClient }
            dataClientFactory = { mockk() }
            messageClientFactory = { mockk() }
        }

        assertThat(sync.sync(redactRetainedState = true)).isEqualTo(WearPhoneSyncResult.RETRY)
    }

    @Test fun `failed aggregate-free publication retains conservative represented state`() = kotlinx.coroutines.runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val status = WearSyncStatusStore(context)
        status.recordSource(com.healthmd.wearable.contract.WearHealthSnapshot(
            sequence = 41,
            capturedAtEpochMillis = 100,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay("2026-08-13", steps = 10, bloodOxygenPercent = 97.0)),
            permissionState = com.healthmd.wearable.contract.WearPermissionState.READY,
        ))
        val capabilityClient = mockk<CapabilityClient>()
        val dataClient = mockk<DataClient>()
        val emptyCapability = mockk<CapabilityInfo> { every { nodes } returns emptySet() }
        every { capabilityClient.getCapability(any(), any()) } returns Tasks.forResult(emptyCapability)
        every { dataClient.putDataItem(any()) } returns Tasks.forException(IllegalStateException("offline"))
        val producer = mockk<WearSnapshotProducer>()
        coEvery { producer.grantedDataPermissions() } returns emptySet()
        every { producer.producePermissionRedaction(any<Instant>(), any<ZoneId>()) } returns
            com.healthmd.wearable.contract.WearHealthSnapshot(
                sequence = 42,
                capturedAtEpochMillis = 100,
                capturedZoneId = "UTC",
                days = emptyList(),
                permissionState = com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED,
            )
        val sync = WearPhoneSync(context, producer, status).apply {
            capabilityClientFactory = { capabilityClient }
            dataClientFactory = { dataClient }
            messageClientFactory = { mockk() }
        }

        assertThat(sync.sync()).isEqualTo(WearPhoneSyncResult.RETRY)
        assertThat(WearSyncStatusStore(context).sourceNeedsPermissionRedaction(emptySet())).isTrue()
    }

    @Test fun `failed aggregate-free publication preserves ambiguous legacy source state`() = kotlinx.coroutines.runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear()
            .putString("sourceState", com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED.name)
            .commit()
        val capabilityClient = mockk<CapabilityClient>()
        val dataClient = mockk<DataClient>()
        val emptyCapability = mockk<CapabilityInfo> { every { nodes } returns emptySet() }
        every { capabilityClient.getCapability(any(), any()) } returns Tasks.forResult(emptyCapability)
        every { dataClient.putDataItem(any()) } returns Tasks.forException(IllegalStateException("offline"))
        val producer = mockk<WearSnapshotProducer>()
        coEvery { producer.grantedDataPermissions() } returns emptySet()
        every { producer.producePermissionRedaction(any<Instant>(), any<ZoneId>()) } returns
            com.healthmd.wearable.contract.WearHealthSnapshot(
                sequence = 42,
                capturedAtEpochMillis = 100,
                capturedZoneId = "UTC",
                days = emptyList(),
                permissionState = com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED,
            )
        val sync = WearPhoneSync(context, producer, WearSyncStatusStore(context)).apply {
            capabilityClientFactory = { capabilityClient }
            dataClientFactory = { dataClient }
            messageClientFactory = { mockk() }
        }

        assertThat(sync.sync()).isEqualTo(WearPhoneSyncResult.RETRY)
        val reloaded = WearSyncStatusStore(context)
        assertThat(reloaded.sourceNeedsPermissionRedaction(emptySet())).isTrue()
        assertThat(reloaded.sourceMayContainAggregates()).isTrue()
    }

    @Test fun `redaction DataItem security failure is retryable and does not report completion`() = kotlinx.coroutines.runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val capabilityClient = mockk<CapabilityClient>()
        val dataClient = mockk<DataClient>()
        val emptyCapability = mockk<CapabilityInfo> { every { nodes } returns emptySet() }
        every { capabilityClient.getCapability(any(), any()) } returns Tasks.forResult(emptyCapability)
        every { dataClient.putDataItem(any()) } returns Tasks.forException(SecurityException("put denied"))
        val producer = mockk<WearSnapshotProducer>()
        coEvery { producer.grantedDataPermissions() } returns emptySet()
        every { producer.producePermissionRedaction(any<Instant>(), any<ZoneId>()) } returns com.healthmd.wearable.contract.WearHealthSnapshot(
            sequence = 43,
            capturedAtEpochMillis = 100,
            capturedZoneId = "UTC",
            days = emptyList(),
            permissionState = com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED,
        )

        val sync = WearPhoneSync(context, producer, WearSyncStatusStore(context)).apply {
            capabilityClientFactory = { capabilityClient }
            dataClientFactory = { dataClient }
            messageClientFactory = { mockk() }
        }
        val result = sync.sync(redactRetainedState = true)

        assertThat(result).isEqualTo(WearPhoneSyncResult.RETRY)
        assertThat(workerResult(result)).isInstanceOf(ListenableWorker.Result.Retry::class.java)
        verify(exactly = 0) { dataClient.deleteDataItems(any(), any()) }
    }

    @Test fun `redaction canceled DataItem task is retryable rather than canceling worker`() = kotlinx.coroutines.runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val capabilityClient = mockk<CapabilityClient>()
        val dataClient = mockk<DataClient>()
        val emptyCapability = mockk<CapabilityInfo> { every { nodes } returns emptySet() }
        every { capabilityClient.getCapability(any(), any()) } returns Tasks.forResult(emptyCapability)
        every { dataClient.putDataItem(any()) } returns Tasks.forCanceled()
        val producer = mockk<WearSnapshotProducer>()
        coEvery { producer.grantedDataPermissions() } returns emptySet()
        every { producer.producePermissionRedaction(any<Instant>(), any<ZoneId>()) } returns com.healthmd.wearable.contract.WearHealthSnapshot(
            sequence = 44,
            capturedAtEpochMillis = 100,
            capturedZoneId = "UTC",
            days = emptyList(),
            permissionState = com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED,
        )
        val sync = WearPhoneSync(context, producer, WearSyncStatusStore(context)).apply {
            capabilityClientFactory = { capabilityClient }
            dataClientFactory = { dataClient }
            messageClientFactory = { mockk() }
        }

        assertThat(sync.sync(redactRetainedState = true)).isEqualTo(WearPhoneSyncResult.RETRY)
    }

    @Test fun `permission audit checks represented grants without background permission`() = kotlinx.coroutines.runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val status = WearSyncStatusStore(context)
        status.recordSource(com.healthmd.wearable.contract.WearHealthSnapshot(
            sequence = 7,
            capturedAtEpochMillis = 100,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay("2026-08-13", steps = 10)),
            permissionState = com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED,
        ))
        val healthConnect = mockk<HealthConnectManager>()
        coEvery { healthConnect.getGrantedPermissions() } returns setOf(WearDataPermissionPolicy.steps)
        val scheduler = WearPhoneSyncScheduler(context, healthConnect, status)

        assertThat(scheduler.permissionAuditEligibility())
            .isEqualTo(WearPhoneSyncScheduler.Eligibility.INELIGIBLE)
        coEvery { healthConnect.getGrantedPermissions() } returns emptySet()
        assertThat(scheduler.permissionAuditEligibility())
            .isEqualTo(WearPhoneSyncScheduler.Eligibility.PERMISSION_REVOKED)
        coVerify(exactly = 0) { healthConnect.permissionPlan() }
    }

    @Test fun `ineligible aggregate source retains permission-only periodic audit`() = kotlinx.coroutines.runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val status = WearSyncStatusStore(context)
        status.recordSource(com.healthmd.wearable.contract.WearHealthSnapshot(
            sequence = 7,
            capturedAtEpochMillis = 100,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay("2026-08-13", steps = 10)),
            permissionState = com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED,
        ))
        val workManager = relaxedWorkManager()
        val scheduler = WearPhoneSyncScheduler(context, mockk(), status).apply {
            workManagerOverride = workManager
        }
        val request = slot<PeriodicWorkRequest>()

        scheduler.reconcile(WearPhoneSyncScheduler.Eligibility.INELIGIBLE)

        verify(exactly = 1) {
            workManager.enqueueUniquePeriodicWork(
                WearPhoneSyncScheduler.PERMISSION_AUDIT_WORK_NAME,
                ExistingPeriodicWorkPolicy.KEEP,
                capture(request),
            )
        }
        assertThat(request.captured.workSpec.input.getBoolean(WearPhoneSyncWorker.PERMISSION_AUDIT, false)).isTrue()
        verify { workManager.cancelUniqueWork(WearPhoneSyncScheduler.PERIODIC_WORK_NAME) }
    }

    @Test fun `aggregate-free source cancels permission-only periodic audit`() = kotlinx.coroutines.runBlocking {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val status = WearSyncStatusStore(context)
        status.recordSource(com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED, hasAggregates = false)
        val workManager = relaxedWorkManager()
        val scheduler = WearPhoneSyncScheduler(context, mockk(), status).apply {
            workManagerOverride = workManager
        }

        scheduler.reconcile(WearPhoneSyncScheduler.Eligibility.INELIGIBLE)

        verify { workManager.cancelUniqueWork(WearPhoneSyncScheduler.PERMISSION_AUDIT_WORK_NAME) }
        verify(exactly = 0) {
            workManager.enqueueUniquePeriodicWork(
                WearPhoneSyncScheduler.PERMISSION_AUDIT_WORK_NAME,
                any(),
                any(),
            )
        }
    }

    @Test fun `manual sync is owned by a durable unique worker`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val workManager = relaxedWorkManager()
        val scheduler = WearPhoneSyncScheduler(context, mockk(), WearSyncStatusStore(context)).apply {
            workManagerOverride = workManager
        }
        val request = slot<OneTimeWorkRequest>()

        scheduler.enqueueManual()

        verify(exactly = 1) {
            workManager.enqueueUniqueWork(
                WearPhoneSyncScheduler.MANUAL_WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                capture(request),
            )
        }
        assertThat(request.captured.workSpec.input.getBoolean(WearPhoneSyncWorker.USER_INITIATED, false)).isTrue()
    }

    @Test fun `clear request is owned by a durable unique worker before transaction start`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        val workManager = relaxedWorkManager()
        val scheduler = WearPhoneSyncScheduler(context, mockk(), WearSyncStatusStore(context)).apply {
            workManagerOverride = workManager
        }
        val request = slot<OneTimeWorkRequest>()

        scheduler.enqueueClear()

        verify(exactly = 1) {
            workManager.enqueueUniqueWork(
                WearPhoneSyncScheduler.CLEAR_WORK_NAME,
                ExistingWorkPolicy.REPLACE,
                capture(request),
            )
        }
        assertThat(request.captured.workSpec.input.getBoolean(WearPhoneSyncWorker.CLEAR_REQUEST, false)).isTrue()
        assertThat(request.captured.workSpec.input.getString(WearPhoneSyncWorker.CLEAR_REQUEST_ID)).isNotEmpty()
        assertThat(request.captured.workSpec.input.getBoolean(WearPhoneSyncWorker.CLEAR_RECOVERY, false)).isFalse()
    }

    @Test fun `wildcard durable state uris address all originating nodes`() {
        assertThat(UriBuilder.snapshot().toString()).isEqualTo("wear://*/healthmd/wear/snapshot/v1")
        assertThat(UriBuilder.tombstone().toString()).isEqualTo("wear://*/healthmd/wear/tombstone/v1")
    }

    @Test fun `ack is monotonic while clear requires tombstone at or above target`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordSent(10, WearDeliveryState.REACHABLE, at = 100)
        store.recordAck(WearSnapshotAck(10, true, WearAckReason.APPLIED))
        store.recordAck(WearSnapshotAck(9, false, WearAckReason.OUT_OF_ORDER))
        assertThat(store.status().ackReason).isEqualTo(WearAckReason.APPLIED)
        store.recordClearRequested(sequence = 10, at = 200, targetNodeIds = setOf("watch"))
        assertThat(store.status().deliveryState).isEqualTo(WearDeliveryState.CLEAR_REQUESTED)
        store.recordAck(WearSnapshotAck(7, true, WearAckReason.DELETED))
        assertThat(store.status().ackReason).isEqualTo(WearAckReason.APPLIED)
        store.recordAck("watch", WearSnapshotAck(10, true, WearAckReason.DELETED))
        assertThat(store.status().ackReason).isEqualTo(WearAckReason.APPLIED)
        assertThat(store.status().deliveryState).isEqualTo(WearDeliveryState.CLEAR_REQUESTED)
        store.completeClear(clearedThroughSequence = 10)
        assertThat(store.status().deliveryState).isNull()
        store.recordAck(WearSnapshotAck(10, false, WearAckReason.INVALID))
        assertThat(store.status().ackReason).isEqualTo(WearAckReason.DELETED)
        store.recordAck(WearSnapshotAck(10, true, WearAckReason.APPLIED))
        assertThat(store.status().acknowledgedSequence).isEqualTo(10)

        store.recordSent(11, WearDeliveryState.REACHABLE, at = 300)
        store.recordAck(WearSnapshotAck(11, true, WearAckReason.APPLIED))
        assertThat(store.status().acknowledgedSequence).isEqualTo(11)
        assertThat(store.status().ackReason).isEqualTo(WearAckReason.APPLIED)
        assertThat(store.status().deliveryState).isEqualTo(WearDeliveryState.REACHABLE)
    }

    @Test fun `same-sequence multi-watch status uses conservative precedence independent of arrival`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordSent(4, WearDeliveryState.REACHABLE, at = 100, targetNodeIds = setOf("watch-a", "watch-b"))
        store.recordAck("watch-a", WearSnapshotAck(4, true, WearAckReason.APPLIED))
        store.recordAck("watch-b", WearSnapshotAck(4, false, WearAckReason.VERSION_MISMATCH))
        assertThat(store.status().ackReason).isEqualTo(WearAckReason.VERSION_MISMATCH)
        store.recordAck("watch-a", WearSnapshotAck(4, true, WearAckReason.APPLIED))
        assertThat(store.status().ackReason).isEqualTo(WearAckReason.VERSION_MISMATCH)
    }

    @Test fun `persisted conservative ack survives process-local aggregation reset`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        WearSyncStatusStore(context).apply {
            recordSent(4, WearDeliveryState.REACHABLE, at = 100, targetNodeIds = setOf("watch-a", "watch-b"))
            recordAck("watch-a", WearSnapshotAck(4, false, WearAckReason.VERSION_MISMATCH))
        }
        val reloaded = WearSyncStatusStore(context)
        reloaded.recordAck("watch-b", WearSnapshotAck(4, true, WearAckReason.APPLIED))
        assertThat(reloaded.status().ackReason).isEqualTo(WearAckReason.VERSION_MISMATCH)
    }

    @Test fun `normal sync tracks only targeted watch acknowledgements`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordSent(
            4,
            WearDeliveryState.REACHABLE,
            at = 100,
            targetNodeIds = linkedSetOf("watch-a", "watch-b"),
        )
        store.recordAck("unexpected-watch", WearSnapshotAck(4, false, WearAckReason.VERSION_MISMATCH))
        assertThat(store.status().ackReason).isNull()
        assertThat(store.status().acknowledgedWatchCount).isEqualTo(0)

        store.recordAck("watch-a", WearSnapshotAck(4, true, WearAckReason.APPLIED))
        assertThat(store.status().targetedWatchCount).isEqualTo(2)
        assertThat(store.status().acknowledgedWatchCount).isEqualTo(1)
        store.recordAck("watch-b", WearSnapshotAck(4, false, WearAckReason.VERSION_MISMATCH))
        assertThat(store.status().acknowledgedWatchCount).isEqualTo(2)
        assertThat(store.status().ackReason).isEqualTo(WearAckReason.VERSION_MISMATCH)

        val reloaded = WearSyncStatusStore(context)
        assertThat(reloaded.status().targetedWatchCount).isEqualTo(2)
        assertThat(reloaded.status().acknowledgedWatchCount).isEqualTo(2)
    }

    @Test fun `delayed ordinary ack must match current sequence and target`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordSent(8, WearDeliveryState.REACHABLE, at = 100, targetNodeIds = setOf("watch-a"))
        store.recordAck("watch-b", WearSnapshotAck(7, false, WearAckReason.VERSION_MISMATCH))
        store.recordAck("watch-a", WearSnapshotAck(7, false, WearAckReason.VERSION_MISMATCH))
        assertThat(store.status().ackReason).isNull()
        assertThat(store.status().acknowledgedWatchCount).isEqualTo(0)
    }

    @Test fun `ack arriving between begin and complete send is retained`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.beginSend(8, linkedSetOf("watch-a"))
        store.recordAck("watch-a", WearSnapshotAck(8, true, WearAckReason.APPLIED))
        store.completeSend(8, WearDeliveryState.REACHABLE, at = 100)

        assertThat(store.status().ackReason).isEqualTo(WearAckReason.APPLIED)
        assertThat(store.status().acknowledgedWatchCount).isEqualTo(1)
        assertThat(store.status().deliveryState).isEqualTo(WearDeliveryState.REACHABLE)
    }

    @Test fun `clear request seeds prior target inventory before capability discovery`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordSent(4, WearDeliveryState.REACHABLE, targetNodeIds = setOf("watch-a"))
        store.recordClearRequested(5, targetNodeIds = store.lastSentTargetNodeIds())
        store.completeClear(5)

        val recreated = WearSyncStatusStore(context)
        recreated.recordAck("watch-a", WearSnapshotAck(5, true, WearAckReason.DELETED))
        assertThat(recreated.status().deliveryState).isNull()
        assertThat(recreated.status().ackReason).isEqualTo(WearAckReason.DELETED)
    }

    @Test fun `clear status uses clear targets and never reuses deleted snapshot counts`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordSent(4, WearDeliveryState.REACHABLE, targetNodeIds = setOf("watch-a", "watch-b"))
        store.recordAck("watch-a", WearSnapshotAck(4, true, WearAckReason.APPLIED))
        assertThat(store.status().acknowledgedWatchCount).isEqualTo(1)

        store.recordClearRequested(5, targetNodeIds = store.lastSentTargetNodeIds())
        assertThat(store.status().targetedWatchCount).isEqualTo(2)
        assertThat(store.status().acknowledgedWatchCount).isEqualTo(0)
        store.recordAck("watch-a", WearSnapshotAck(5, true, WearAckReason.DELETED))
        assertThat(store.status().acknowledgedWatchCount).isEqualTo(1)
        assertThat(store.completeClear(5)).isFalse()
        assertThat(store.status().targetedWatchCount).isEqualTo(2)
        assertThat(store.status().acknowledgedWatchCount).isEqualTo(1)

        store.recordAck("watch-b", WearSnapshotAck(5, true, WearAckReason.DELETED))
        assertThat(store.status().deliveryState).isNull()
        assertThat(store.status().targetedWatchCount).isEqualTo(0)
        assertThat(store.status().acknowledgedWatchCount).isEqualTo(0)
    }

    @Test fun `completed clear work request is idempotently recognized after process death`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordClearRequested(5, workRequestId = "request-a")
        assertThat(store.completeClear(5)).isFalse()

        val recreated = WearSyncStatusStore(context)
        assertThat(recreated.clearWorkRequestCompleted("request-a")).isTrue()
        assertThat(recreated.completedClearResult()).isEqualTo(WearPhoneSyncResult.QUEUED)
        assertThat(recreated.clearWorkRequestCompleted("request-b")).isFalse()
    }

    @Test fun `requested clear remains resumable after cancellation boundary`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordSent(4, WearDeliveryState.REACHABLE, at = 100)
        store.recordClearRequested(5, at = 200)
        // Cancellation no longer discards the request; process recreation must retain intent.
        assertThat(WearSyncStatusStore(context).pendingClear())
            .isEqualTo(WearPendingClear(5, WearClearPhase.REQUESTED))
        assertThat(WearSyncStatusStore(context).status().deliveryState)
            .isEqualTo(WearDeliveryState.CLEAR_REQUESTED)
    }

    @Test fun `delayed clear acknowledgement resolves persisted unconfirmed status`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        WearSyncStatusStore(context).apply {
            recordClearRequested(5, at = 100, targetNodeIds = setOf("watch-a"))
            completeClear(5)
        }
        val recreated = WearSyncStatusStore(context)
        assertThat(recreated.status().deliveryState).isEqualTo(WearDeliveryState.CLEAR_REQUESTED)
        recreated.recordAck("watch-a", WearSnapshotAck(5, true, WearAckReason.DELETED))
        assertThat(recreated.status().deliveryState).isNull()
        assertThat(recreated.status().ackReason).isEqualTo(WearAckReason.DELETED)
    }

    @Test fun `late clear acknowledgement cannot regress a newer snapshot transaction`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordClearRequested(5, at = 100, targetNodeIds = setOf("watch-a"))
        assertThat(store.completeClear(5)).isFalse()

        store.recordSent(6, WearDeliveryState.REACHABLE, at = 200, targetNodeIds = setOf("watch-a"))
        store.recordAck("watch-a", WearSnapshotAck(6, true, WearAckReason.APPLIED))
        store.recordAck("watch-a", WearSnapshotAck(5, true, WearAckReason.DELETED))

        val current = store.status()
        assertThat(current.sentSequence).isEqualTo(6)
        assertThat(current.deliveryState).isEqualTo(WearDeliveryState.REACHABLE)
        assertThat(current.acknowledgedSequence).isEqualTo(6)
        assertThat(current.ackReason).isEqualTo(WearAckReason.APPLIED)
        assertThat(current.targetedWatchCount).isEqualTo(1)
        assertThat(current.acknowledgedWatchCount).isEqualTo(1)
    }

    @Test fun `unexpected node cannot acknowledge an active clear`() = kotlinx.coroutines.test.runTest {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordClearRequested(4, targetNodeIds = setOf("watch-a"))
        store.beginClearAcknowledgements()
        store.recordAck("unexpected-watch", WearSnapshotAck(4, true, WearAckReason.DELETED))
        assertThat(store.awaitClearAcknowledgements(setOf("watch-a"), 4, timeoutMillis = 1)).isNull()
        assertThat(store.status().ackReason).isNull()
        assertThat(store.status().deliveryState).isEqualTo(WearDeliveryState.CLEAR_REQUESTED)
    }

    @Test fun `clear acknowledgement captured before wait is retained`() = kotlinx.coroutines.test.runTest {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordClearRequested(4, targetNodeIds = setOf("watch-a"))
        store.beginClearAcknowledgements()
        store.recordAck("watch-a", WearSnapshotAck(4, true, WearAckReason.DELETED))
        assertThat(store.awaitClearAcknowledgements(setOf("watch-a"), 4, timeoutMillis = 1)).isEqualTo(4)
    }

    @Test fun `all connected watch acknowledgements are required for clear completion`() = kotlinx.coroutines.test.runTest {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordClearRequested(4, targetNodeIds = setOf("watch-a", "watch-b"))
        store.beginClearAcknowledgements()
        store.recordAck("watch-a", WearSnapshotAck(4, true, WearAckReason.DELETED))
        assertThat(store.awaitClearAcknowledgements(setOf("watch-a", "watch-b"), 4, timeoutMillis = 1)).isNull()
        store.recordAck("watch-b", WearSnapshotAck(5, true, WearAckReason.DELETED))
        assertThat(store.awaitClearAcknowledgements(setOf("watch-a", "watch-b"), 4, timeoutMillis = 1)).isEqualTo(5)
    }

    @Test fun `reachable subset cannot confirm clear while capable watch is offline`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordClearRequested(4, targetNodeIds = setOf("watch-online", "watch-offline"))
        store.recordAck("watch-online", WearSnapshotAck(4, true, WearAckReason.DELETED))
        store.completeClear(4)

        assertThat(store.status().deliveryState).isEqualTo(WearDeliveryState.CLEAR_REQUESTED)
        assertThat(store.status().ackReason).isNull()
        store.recordAck("watch-offline", WearSnapshotAck(4, true, WearAckReason.DELETED))
        assertThat(store.status().deliveryState).isNull()
        assertThat(store.status().ackReason).isEqualTo(WearAckReason.DELETED)
    }

    @Test fun `durable clear without watch acknowledgement remains visibly unconfirmed`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordSent(4, WearDeliveryState.QUEUED, at = 100)
        store.recordClearRequested(4, at = 200)
        store.completeClear(clearedThroughSequence = 4)
        assertThat(store.status().deliveryState).isEqualTo(WearDeliveryState.CLEAR_REQUESTED)
        assertThat(store.status().ackReason).isNull()
    }

    @Test fun `partial permission snapshot still requires aggregate-free full-revocation redaction`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordSource(com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED, hasAggregates = true)
        assertThat(store.sourceNeedsPermissionRedaction()).isTrue()
        store.recordSource(com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED, hasAggregates = false)
        assertThat(store.sourceNeedsPermissionRedaction()).isFalse()
    }

    @Test fun `partial revocation of a represented category redacts retained state fail closed`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordSource(com.healthmd.wearable.contract.WearHealthSnapshot(
            sequence = 7,
            capturedAtEpochMillis = 100,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay("2026-08-13", steps = 10, bloodOxygenPercent = 97.0)),
            permissionState = com.healthmd.wearable.contract.WearPermissionState.READY,
        ))
        val steps = HealthPermission.getReadPermission(StepsRecord::class)
        val oxygen = HealthPermission.getReadPermission(OxygenSaturationRecord::class)

        assertThat(store.sourceNeedsPermissionRedaction(setOf(steps, oxygen))).isFalse()
        assertThat(store.sourceNeedsPermissionRedaction(setOf(steps))).isTrue()
    }

    @Test fun `fresh status with no prior publication does not invent retained health data`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        assertThat(WearSyncStatusStore(context).sourceNeedsPermissionRedaction(emptySet())).isFalse()
    }

    @Test fun `legacy permission-required state without aggregate marker redacts fail closed`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear()
            .putString("sourceState", com.healthmd.wearable.contract.WearPermissionState.PERMISSION_REQUIRED.name)
            .commit()
        assertThat(WearSyncStatusStore(context).sourceNeedsPermissionRedaction()).isTrue()
    }

    @Test fun `requested clear remains pending after transient failure`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordSent(4, WearDeliveryState.QUEUED, at = 100)
        store.recordClearRequested(5, at = 200)
        store.recordAttempt(WearPhoneSyncResult.RETRY, at = 300)
        assertThat(WearSyncStatusStore(context).pendingClear())
            .isEqualTo(WearPendingClear(5, WearClearPhase.REQUESTED))
        assertThat(WearSyncStatusStore(context).status().deliveryState)
            .isEqualTo(WearDeliveryState.CLEAR_REQUESTED)
    }

    @Test fun `durable clear phase survives process recreation and cannot restore stale delivery`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        WearSyncStatusStore(context).apply {
            recordSent(4, WearDeliveryState.QUEUED, at = 100)
            recordClearRequested(5, at = 200)
            recordClearTombstoneStored()
            recordAttempt(WearPhoneSyncResult.RETRY, at = 300)
        }

        val reloaded = WearSyncStatusStore(context)
        assertThat(reloaded.pendingClear()).isEqualTo(WearPendingClear(5, WearClearPhase.TOMBSTONE_STORED))
        assertThat(reloaded.status().deliveryState).isEqualTo(WearDeliveryState.CLEAR_REQUESTED)
        reloaded.recordClearSnapshotRemoved()
        assertThat(WearSyncStatusStore(context).pendingClear())
            .isEqualTo(WearPendingClear(5, WearClearPhase.SNAPSHOT_REMOVED))
        reloaded.completeClear(5)
        assertThat(reloaded.pendingClear()).isNull()
        assertThat(reloaded.status().deliveryState).isEqualTo(WearDeliveryState.CLEAR_REQUESTED)
    }

    @Test fun `successful clear removes retained aggregate audit state`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordSource(com.healthmd.wearable.contract.WearHealthSnapshot(
            sequence = 7,
            capturedAtEpochMillis = 100,
            capturedZoneId = "UTC",
            days = listOf(WearHealthDay("2026-08-13", steps = 10)),
        ))
        assertThat(store.sourceMayContainAggregates()).isTrue()
        store.recordSourceRemoved()
        assertThat(store.sourceMayContainAggregates()).isFalse()
        assertThat(store.sourceNeedsPermissionRedaction(emptySet())).isFalse()
    }

    @Test fun `status flow publishes background updates`() {
        val context = ApplicationProvider.getApplicationContext<android.content.Context>()
        context.getSharedPreferences("wear-sync-private", 0).edit().clear().commit()
        val store = WearSyncStatusStore(context)
        store.recordSent(7, WearDeliveryState.REACHABLE, at = 100, targetNodeIds = setOf("watch-a"))
        assertThat(store.statuses.value.sentSequence).isEqualTo(7)
        store.recordAck("watch-a", WearSnapshotAck(7, true, WearAckReason.APPLIED))
        assertThat(store.statuses.value.ackReason).isEqualTo(WearAckReason.APPLIED)
    }

    private fun relaxedWorkManager(): WorkManager = mockk(relaxed = true) {
        every {
            enqueueUniqueWork(
                any<String>(),
                any<ExistingWorkPolicy>(),
                any<OneTimeWorkRequest>(),
            )
        } returns mockk<Operation>(relaxed = true)
        every {
            enqueueUniquePeriodicWork(
                any<String>(),
                any<ExistingPeriodicWorkPolicy>(),
                any<PeriodicWorkRequest>(),
            )
        } returns mockk<Operation>(relaxed = true)
        every { cancelUniqueWork(any<String>()) } returns mockk<Operation>(relaxed = true) {
            every { result } returns Futures.immediateFuture(Operation.SUCCESS)
        }
    }
}
