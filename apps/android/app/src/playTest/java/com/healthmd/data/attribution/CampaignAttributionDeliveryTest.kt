package com.healthmd.data.attribution

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import org.junit.Test

class CampaignAttributionDeliveryTest {
    @Test
    fun successfulUploadMarksDeliveredAndIsNotReportedAgain() = runTest {
        val store = pendingStore()
        val reporter = FakeCampaignAttributionReporter(
            listOf(CampaignAttributionReportResult.Delivered(202))
        )
        val delivery = CampaignAttributionDelivery(store, reporter)

        assertThat(delivery.deliverPending())
            .isEqualTo(CampaignAttributionDeliveryResult.DELIVERED)
        assertThat(delivery.deliverPending())
            .isEqualTo(CampaignAttributionDeliveryResult.NOTHING_PENDING)

        assertThat(store.snapshot.processingState)
            .isEqualTo(CampaignAttributionProcessingState.DELIVERED)
        assertThat(store.snapshot.deliverySucceeded).isTrue()
        assertThat(reporter.reportedEvents).hasSize(1)
    }

    @Test
    fun retryKeepsStableEventIdUntilSuccessfulUpload() = runTest {
        val store = pendingStore()
        val reporter = FakeCampaignAttributionReporter(
            listOf(
                CampaignAttributionReportResult.RetryableFailure(),
                CampaignAttributionReportResult.Delivered(204),
            )
        )
        val delivery = CampaignAttributionDelivery(store, reporter)

        assertThat(delivery.deliverPending()).isEqualTo(CampaignAttributionDeliveryResult.RETRY)
        assertThat(store.snapshot.processingState)
            .isEqualTo(CampaignAttributionProcessingState.PENDING_DELIVERY)
        assertThat(delivery.deliverPending()).isEqualTo(CampaignAttributionDeliveryResult.DELIVERED)

        assertThat(reporter.reportedEvents.map { it.eventId })
            .containsExactly(
                "22222222-2222-4222-8222-222222222222",
                "22222222-2222-4222-8222-222222222222",
            )
            .inOrder()
    }

    @Test
    fun permanentHttpRejectionStopsRetriesWithoutMarkingDeliverySuccessful() = runTest {
        val store = pendingStore()
        val reporter = FakeCampaignAttributionReporter(
            listOf(CampaignAttributionReportResult.PermanentFailure(400))
        )

        val result = CampaignAttributionDelivery(store, reporter).deliverPending()

        assertThat(result).isEqualTo(CampaignAttributionDeliveryResult.PERMANENT_FAILURE)
        assertThat(store.snapshot.processingState)
            .isEqualTo(CampaignAttributionProcessingState.TERMINAL_REJECTED)
        assertThat(store.snapshot.deliverySucceeded).isFalse()
    }

    @Test
    fun networkAndServerFailuresRemainPendingForWorkManagerRetry() = runTest {
        val store = pendingStore()
        val reporter = FakeCampaignAttributionReporter(
            listOf(
                CampaignAttributionReportResult.RetryableFailure(),
                CampaignAttributionReportResult.RetryableFailure(503),
            )
        )
        val delivery = CampaignAttributionDelivery(store, reporter)

        assertThat(delivery.deliverPending()).isEqualTo(CampaignAttributionDeliveryResult.RETRY)
        assertThat(delivery.deliverPending()).isEqualTo(CampaignAttributionDeliveryResult.RETRY)
        assertThat(store.snapshot.processingState)
            .isEqualTo(CampaignAttributionProcessingState.PENDING_DELIVERY)
        assertThat(store.snapshot.deliverySucceeded).isFalse()
    }

    @Test
    fun missingEndpointPreservesPendingEvent() = runTest {
        val store = pendingStore()
        val originalEvent = store.snapshot.event
        val reporter = FakeCampaignAttributionReporter(
            listOf(CampaignAttributionReportResult.NotConfigured)
        )

        val result = CampaignAttributionDelivery(store, reporter).deliverPending()

        assertThat(result).isEqualTo(CampaignAttributionDeliveryResult.NOT_CONFIGURED)
        assertThat(store.snapshot.processingState)
            .isEqualTo(CampaignAttributionProcessingState.PENDING_DELIVERY)
        assertThat(store.snapshot.event).isEqualTo(originalEvent)
        assertThat(store.snapshot.deliverySucceeded).isFalse()
    }

    private fun pendingStore() = InMemoryCampaignAttributionStore(
        initialSnapshot = CampaignAttributionSnapshot(
            installId = "11111111-1111-4111-8111-111111111111",
            processingState = CampaignAttributionProcessingState.PENDING_DELIVERY,
            event = testEvent(),
            deliverySucceeded = false,
        )
    )
}
