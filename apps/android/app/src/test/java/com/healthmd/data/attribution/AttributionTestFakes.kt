package com.healthmd.data.attribution

internal class FakeInstallReferrerSource(
    results: List<InstallReferrerResult>,
) : InstallReferrerSource {
    private val queuedResults = ArrayDeque(results)
    var retrievalCount: Int = 0
        private set

    override suspend fun retrieve(): InstallReferrerResult {
        retrievalCount++
        return queuedResults.removeFirstOrNull()
            ?: InstallReferrerResult.TransientFailure(
                InstallReferrerFailureReason.SERVICE_UNAVAILABLE
            )
    }
}

internal class InMemoryCampaignAttributionStore(
    private val generatedInstallId: String = "11111111-1111-4111-8111-111111111111",
    initialSnapshot: CampaignAttributionSnapshot = CampaignAttributionSnapshot(
        installId = null,
        processingState = CampaignAttributionProcessingState.DISCOVERY_PENDING,
        event = null,
        deliverySucceeded = false,
    ),
) : CampaignAttributionStore {
    var snapshot: CampaignAttributionSnapshot = initialSnapshot
        private set

    override suspend fun load(): CampaignAttributionSnapshot = snapshot

    override suspend fun getOrCreateInstallId(): String {
        val installId = snapshot.installId ?: generatedInstallId
        snapshot = snapshot.copy(installId = installId)
        return installId
    }

    override suspend fun persistPendingIfDiscoveryPending(
        event: CampaignInstallEvent,
    ): CampaignInstallEvent? {
        if (snapshot.processingState == CampaignAttributionProcessingState.DISCOVERY_PENDING) {
            snapshot = snapshot.copy(
                installId = snapshot.installId ?: event.installId,
                processingState = CampaignAttributionProcessingState.PENDING_DELIVERY,
                event = event,
                deliverySucceeded = false,
            )
        }
        return snapshot.event
    }

    override suspend fun markDiscoveryTerminal() {
        if (snapshot.processingState == CampaignAttributionProcessingState.DISCOVERY_PENDING) {
            snapshot = snapshot.copy(
                processingState = CampaignAttributionProcessingState.TERMINAL_NO_CAMPAIGN,
                event = null,
                deliverySucceeded = false,
            )
        }
    }

    override suspend fun markDelivered(eventId: String) {
        if (snapshot.processingState == CampaignAttributionProcessingState.PENDING_DELIVERY &&
            snapshot.event?.eventId == eventId
        ) {
            snapshot = snapshot.copy(
                processingState = CampaignAttributionProcessingState.DELIVERED,
                deliverySucceeded = true,
            )
        }
    }

    override suspend fun markPermanentlyRejected(eventId: String) {
        if (snapshot.processingState == CampaignAttributionProcessingState.PENDING_DELIVERY &&
            snapshot.event?.eventId == eventId
        ) {
            snapshot = snapshot.copy(
                processingState = CampaignAttributionProcessingState.TERMINAL_REJECTED,
                deliverySucceeded = false,
            )
        }
    }
}

internal class FakeCampaignAttributionScheduler : CampaignAttributionWorkScheduler {
    var enqueueCount: Int = 0
        private set

    override fun enqueueUpload() {
        enqueueCount++
    }
}

internal class FakeCampaignAttributionReporter(
    results: List<CampaignAttributionReportResult>,
) : CampaignAttributionReporter {
    private val queuedResults = ArrayDeque(results)
    val reportedEvents = mutableListOf<CampaignInstallEvent>()

    override suspend fun report(event: CampaignInstallEvent): CampaignAttributionReportResult {
        reportedEvents += event
        return queuedResults.removeFirstOrNull()
            ?: CampaignAttributionReportResult.RetryableFailure()
    }
}

internal fun testEvent(
    eventId: String = "22222222-2222-4222-8222-222222222222",
    installId: String = "11111111-1111-4111-8111-111111111111",
): CampaignInstallEvent = CampaignInstallEvent(
    eventId = eventId,
    installId = installId,
    occurredAt = "2026-07-14T12:00:00Z",
    appVersion = "1.5.1",
    buildNumber = "19",
    campaignToken = "yt_csv_001",
    source = "yt",
    medium = "campaign_shortlink",
    contentAngle = "csv",
    referrerClickTimestampSeconds = 1_234_567_890L,
    installBeginTimestampSeconds = 1_234_567_900L,
)
