package com.healthmd.data.attribution

import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.delay
import timber.log.Timber
import java.time.Instant
import javax.inject.Inject
import javax.inject.Singleton

fun interface CampaignAttributionUuidGenerator {
    fun randomUuid(): String
}

fun interface CampaignAttributionClock {
    fun now(): Instant
}

fun interface CampaignAttributionRetryDelay {
    suspend fun waitBeforeRetry(attempt: Int)
}

data class CampaignAttributionAppInfo(
    val versionName: String,
    val buildNumber: String,
)

class CampaignAttributionEventFactory @Inject constructor(
    private val appInfo: CampaignAttributionAppInfo,
    private val clock: CampaignAttributionClock,
    private val uuidGenerator: CampaignAttributionUuidGenerator,
) {
    fun create(installId: String, attribution: CampaignAttribution): CampaignInstallEvent =
        CampaignInstallEvent(
            eventId = uuidGenerator.randomUuid(),
            installId = installId,
            occurredAt = clock.now().toString(),
            appVersion = appInfo.versionName,
            buildNumber = appInfo.buildNumber,
            campaignToken = attribution.campaignToken,
            source = attribution.source,
            medium = attribution.medium,
            contentAngle = attribution.contentAngle,
            referrerClickTimestampSeconds = attribution.referrerClickTimestampSeconds,
            installBeginTimestampSeconds = attribution.installBeginTimestampSeconds,
        )
}

class DefaultCampaignAttributionRetryDelay @Inject constructor() : CampaignAttributionRetryDelay {
    override suspend fun waitBeforeRetry(attempt: Int) {
        delay(BASE_RETRY_DELAY_MILLIS * attempt.coerceAtLeast(1))
    }

    private companion object {
        const val BASE_RETRY_DELAY_MILLIS = 250L
    }
}

@Singleton
class CampaignAttributionOrchestrator @Inject constructor(
    private val source: InstallReferrerSource,
    private val parser: CampaignReferrerParser,
    private val store: CampaignAttributionStore,
    private val eventFactory: CampaignAttributionEventFactory,
    private val scheduler: CampaignAttributionWorkScheduler,
    private val retryDelay: CampaignAttributionRetryDelay,
) {
    suspend fun processStartup() {
        val installId = store.getOrCreateInstallId()
        when (store.load().processingState) {
            CampaignAttributionProcessingState.PENDING_DELIVERY -> {
                scheduler.enqueueUpload()
                return
            }

            CampaignAttributionProcessingState.DISCOVERY_PENDING -> Unit
            CampaignAttributionProcessingState.DELIVERED,
            CampaignAttributionProcessingState.TERMINAL_NO_CAMPAIGN,
            CampaignAttributionProcessingState.TERMINAL_REJECTED -> return
        }

        when (val result = retrieveWithBoundedRetry()) {
            is InstallReferrerResult.Referrer -> {
                when (
                    val parsed = parser.parse(
                        rawReferrer = result.rawReferrer,
                        referrerClickTimestampSeconds = result.referrerClickTimestampSeconds,
                        installBeginTimestampSeconds = result.installBeginTimestampSeconds,
                    )
                ) {
                    is CampaignReferrerParseResult.Valid -> {
                        val attribution = parsed.attribution
                        Timber.d(
                            "Validated campaign attribution campaign=%s source=%s medium=%s content=%s",
                            attribution.campaignToken,
                            attribution.source,
                            attribution.medium,
                            attribution.contentAngle,
                        )
                        val event = eventFactory.create(installId, attribution)
                        val persisted = store.persistPendingIfDiscoveryPending(event)
                        if (persisted != null &&
                            store.load().processingState ==
                            CampaignAttributionProcessingState.PENDING_DELIVERY
                        ) {
                            scheduler.enqueueUpload()
                        }
                    }

                    CampaignReferrerParseResult.Organic,
                    is CampaignReferrerParseResult.Invalid -> store.markDiscoveryTerminal()
                }
            }

            InstallReferrerResult.Organic,
            InstallReferrerResult.Unsupported,
            is InstallReferrerResult.PermanentFailure -> store.markDiscoveryTerminal()

            is InstallReferrerResult.TransientFailure -> Unit
        }
    }

    private suspend fun retrieveWithBoundedRetry(): InstallReferrerResult {
        var latest: InstallReferrerResult = InstallReferrerResult.TransientFailure(
            InstallReferrerFailureReason.UNKNOWN_TRANSIENT
        )
        repeat(MAX_RETRIEVAL_ATTEMPTS) { zeroBasedAttempt ->
            latest = try {
                source.retrieve()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                InstallReferrerResult.TransientFailure(
                    InstallReferrerFailureReason.UNKNOWN_TRANSIENT
                )
            }
            if (latest !is InstallReferrerResult.TransientFailure) return latest
            if (zeroBasedAttempt < MAX_RETRIEVAL_ATTEMPTS - 1) {
                retryDelay.waitBeforeRetry(zeroBasedAttempt + 1)
            }
        }
        return latest
    }

    private companion object {
        const val MAX_RETRIEVAL_ATTEMPTS = 3
    }
}
