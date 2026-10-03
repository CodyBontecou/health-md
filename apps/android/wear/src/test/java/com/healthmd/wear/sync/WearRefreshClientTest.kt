package com.healthmd.wear.sync

import androidx.test.core.app.ApplicationProvider
import com.google.android.gms.tasks.Tasks
import com.google.android.gms.wearable.CapabilityClient
import com.google.android.gms.wearable.CapabilityInfo
import com.google.android.gms.wearable.MessageClient
import com.google.android.gms.wearable.Node
import com.google.common.truth.Truth.assertThat
import com.healthmd.wearable.contract.WearDataPaths
import com.healthmd.wearable.contract.WearHealthSnapshot
import io.mockk.every
import io.mockk.mockk
import io.mockk.verify
import kotlinx.coroutines.async
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner

@RunWith(RobolectricTestRunner::class)
class WearRefreshClientTest {
    private val context = ApplicationProvider.getApplicationContext<android.content.Context>()
    private val capabilityClient = mockk<CapabilityClient>()
    private val messageClient = mockk<MessageClient>()

    @Test fun `refresh queries reachable phones and prefers nearby node`() = runBlocking {
        val remote = node("remote", nearby = false)
        val nearby = node("nearby", nearby = true)
        val info = mockk<CapabilityInfo> { every { nodes } returns linkedSetOf(remote, nearby) }
        every { capabilityClient.getCapability(WearDataPaths.CAPABILITY_PHONE, CapabilityClient.FILTER_REACHABLE) } returns Tasks.forResult(info)
        every { messageClient.sendMessage("nearby", WearDataPaths.REFRESH, any()) } returns Tasks.forResult(7)

        WearSnapshotRepository.clear(context)
        val refresh = async { WearRefreshClient(context, capabilityClient, messageClient).requestRefresh(timeoutMillis = 1_000) }
        yield()
        WearSnapshotRepository.apply(context, snapshot(sequence = 1))
        assertThat(refresh.await()).isTrue()
        verify(exactly = 1) { capabilityClient.getCapability(WearDataPaths.CAPABILITY_PHONE, CapabilityClient.FILTER_REACHABLE) }
        verify(exactly = 1) { messageClient.sendMessage("nearby", WearDataPaths.REFRESH, match { it.isEmpty() }) }
    }

    @Test fun `no reachable phone fails without sending`() = runBlocking {
        val info = mockk<CapabilityInfo> { every { nodes } returns emptySet() }
        every { capabilityClient.getCapability(WearDataPaths.CAPABILITY_PHONE, CapabilityClient.FILTER_REACHABLE) } returns Tasks.forResult(info)

        assertThat(WearRefreshClient(context, capabilityClient, messageClient).requestRefresh(timeoutMillis = 1)).isFalse()
        verify(exactly = 0) { messageClient.sendMessage(any(), any(), any()) }
    }

    @Test fun `capability or message failure reports refresh failure`() = runBlocking {
        every { capabilityClient.getCapability(WearDataPaths.CAPABILITY_PHONE, CapabilityClient.FILTER_REACHABLE) } returns
            Tasks.forException(IllegalStateException("offline"))
        assertThat(WearRefreshClient(context, capabilityClient, messageClient).requestRefresh(timeoutMillis = 1)).isFalse()

        val phone = node("phone", nearby = true)
        val info = mockk<CapabilityInfo> { every { nodes } returns setOf(phone) }
        every { capabilityClient.getCapability(WearDataPaths.CAPABILITY_PHONE, CapabilityClient.FILTER_REACHABLE) } returns Tasks.forResult(info)
        every { messageClient.sendMessage("phone", WearDataPaths.REFRESH, any()) } returns
            Tasks.forException(IllegalStateException("disconnected"))
        assertThat(WearRefreshClient(context, capabilityClient, messageClient).requestRefresh(timeoutMillis = 1)).isFalse()
    }

    @Test fun `canceled capability and message tasks report failure without canceling caller`() = runBlocking {
        every { capabilityClient.getCapability(WearDataPaths.CAPABILITY_PHONE, CapabilityClient.FILTER_REACHABLE) } returns
            Tasks.forCanceled()
        assertThat(WearRefreshClient(context, capabilityClient, messageClient).requestRefresh(timeoutMillis = 1)).isFalse()

        val phone = node("phone", nearby = true)
        val info = mockk<CapabilityInfo> { every { nodes } returns setOf(phone) }
        every { capabilityClient.getCapability(WearDataPaths.CAPABILITY_PHONE, CapabilityClient.FILTER_REACHABLE) } returns
            Tasks.forResult(info)
        every { messageClient.sendMessage("phone", WearDataPaths.REFRESH, any()) } returns Tasks.forCanceled()
        assertThat(WearRefreshClient(context, capabilityClient, messageClient).requestRefresh(timeoutMillis = 1)).isFalse()
        assertThat(kotlin.coroutines.coroutineContext[kotlinx.coroutines.Job]?.isActive).isTrue()
    }

    @Test fun `message transport success without newer snapshot times out`() = runBlocking {
        WearSnapshotRepository.clear(context)
        WearSnapshotRepository.apply(context, snapshot(sequence = 5))
        val phone = node("phone", nearby = true)
        val info = mockk<CapabilityInfo> { every { nodes } returns setOf(phone) }
        every { capabilityClient.getCapability(WearDataPaths.CAPABILITY_PHONE, CapabilityClient.FILTER_REACHABLE) } returns Tasks.forResult(info)
        every { messageClient.sendMessage("phone", WearDataPaths.REFRESH, any()) } returns Tasks.forResult(9)

        assertThat(WearRefreshClient(context, capabilityClient, messageClient).requestRefresh(timeoutMillis = 1)).isFalse()
        assertThat(WearSnapshotRepository.snapshots.value?.sequence).isEqualTo(5)
    }

    private fun snapshot(sequence: Long) = WearHealthSnapshot(
        sequence = sequence,
        capturedAtEpochMillis = System.currentTimeMillis(),
        capturedZoneId = "UTC",
        days = emptyList(),
    )

    private fun node(id: String, nearby: Boolean) = mockk<Node> {
        every { this@mockk.id } returns id
        every { isNearby } returns nearby
    }
}
