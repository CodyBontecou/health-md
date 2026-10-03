package com.healthmd.data.attribution

import kotlinx.coroutines.CancellationException
import javax.inject.Inject

class CampaignAttributionDelivery @Inject constructor(
    private val store: CampaignAttributionStore,
    private val reporter: CampaignAttributionReporter,
) {
    suspend fun deliverPending(): CampaignAttributionDeliveryResult {
        val snapshot = store.load()
        val event = snapshot.event
        if (snapshot.processingState != CampaignAttributionProcessingState.PENDING_DELIVERY ||
            event == null
        ) {
            return CampaignAttributionDeliveryResult.NOTHING_PENDING
        }

        val result = try {
            reporter.report(event)
        } catch (error: CancellationException) {
            throw error
        } catch (_: Exception) {
            CampaignAttributionReportResult.RetryableFailure()
        }

        return when (result) {
            is CampaignAttributionReportResult.Delivered -> {
                store.markDelivered(event.eventId)
                CampaignAttributionDeliveryResult.DELIVERED
            }

            is CampaignAttributionReportResult.PermanentFailure -> {
                store.markPermanentlyRejected(event.eventId)
                CampaignAttributionDeliveryResult.PERMANENT_FAILURE
            }

            is CampaignAttributionReportResult.RetryableFailure ->
                CampaignAttributionDeliveryResult.RETRY

            CampaignAttributionReportResult.NotConfigured ->
                CampaignAttributionDeliveryResult.NOT_CONFIGURED
        }
    }
}

enum class CampaignAttributionDeliveryResult {
    DELIVERED,
    NOTHING_PENDING,
    PERMANENT_FAILURE,
    RETRY,
    NOT_CONFIGURED,
}
