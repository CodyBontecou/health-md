package com.healthmd.data.attribution

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Test
import timber.log.Timber
import java.time.Instant

class CampaignAttributionOrchestratorTest {
    @After
    fun tearDown() {
        Timber.uprootAll()
    }

    @Test
    fun unsupportedInstallReferrerIsTerminalAndNonfatal() = runTest {
        val source = FakeInstallReferrerSource(listOf(InstallReferrerResult.Unsupported))
        val store = InMemoryCampaignAttributionStore()
        val scheduler = FakeCampaignAttributionScheduler()

        orchestrator(source, store, scheduler).processStartup()

        assertThat(store.snapshot.processingState)
            .isEqualTo(CampaignAttributionProcessingState.TERMINAL_NO_CAMPAIGN)
        assertThat(store.snapshot.event).isNull()
        assertThat(scheduler.enqueueCount).isEqualTo(0)
    }

    @Test
    fun organicInstallCreatesNoCampaignEvent() = runTest {
        val source = FakeInstallReferrerSource(listOf(InstallReferrerResult.Organic))
        val store = InMemoryCampaignAttributionStore()

        orchestrator(source, store).processStartup()

        assertThat(store.snapshot.processingState)
            .isEqualTo(CampaignAttributionProcessingState.TERMINAL_NO_CAMPAIGN)
        assertThat(store.snapshot.installId).isNotNull()
        assertThat(store.snapshot.event).isNull()
    }

    @Test
    fun transientRetrievalIsRetriedWithinBoundAndThenPersisted() = runTest {
        val source = FakeInstallReferrerSource(
            listOf(
                InstallReferrerResult.TransientFailure(
                    InstallReferrerFailureReason.SERVICE_UNAVAILABLE
                ),
                InstallReferrerResult.TransientFailure(
                    InstallReferrerFailureReason.SERVICE_DISCONNECTED
                ),
                validReferrerResult(),
            )
        )
        val store = InMemoryCampaignAttributionStore()
        val scheduler = FakeCampaignAttributionScheduler()

        orchestrator(source, store, scheduler).processStartup()

        assertThat(source.retrievalCount).isEqualTo(3)
        assertThat(store.snapshot.processingState)
            .isEqualTo(CampaignAttributionProcessingState.PENDING_DELIVERY)
        assertThat(store.snapshot.event?.eventId)
            .isEqualTo("22222222-2222-4222-8222-222222222222")
        assertThat(scheduler.enqueueCount).isEqualTo(1)
    }

    @Test
    fun exhaustedTransientRetriesRemainDiscoverableOnNextLaunch() = runTest {
        val source = FakeInstallReferrerSource(
            List(3) {
                InstallReferrerResult.TransientFailure(
                    InstallReferrerFailureReason.SERVICE_UNAVAILABLE
                )
            }
        )
        val store = InMemoryCampaignAttributionStore()

        orchestrator(source, store).processStartup()

        assertThat(source.retrievalCount).isEqualTo(3)
        assertThat(store.snapshot.processingState)
            .isEqualTo(CampaignAttributionProcessingState.DISCOVERY_PENDING)
        assertThat(store.snapshot.event).isNull()
    }

    @Test
    fun repeatedStartupKeepsOneEventIdAndAvoidsReferrerReprocessing() = runTest {
        val source = FakeInstallReferrerSource(listOf(validReferrerResult()))
        val store = InMemoryCampaignAttributionStore()
        val scheduler = FakeCampaignAttributionScheduler()
        val orchestrator = orchestrator(source, store, scheduler)

        orchestrator.processStartup()
        val firstEvent = store.snapshot.event
        orchestrator.processStartup()

        assertThat(source.retrievalCount).isEqualTo(1)
        assertThat(store.snapshot.event).isEqualTo(firstEvent)
        assertThat(store.snapshot.event?.eventId)
            .isEqualTo("22222222-2222-4222-8222-222222222222")
        assertThat(scheduler.enqueueCount).isEqualTo(2)
    }

    @Test
    fun rawReferrerIsNeverWrittenToLogsOrPersistedPayload() = runTest {
        val rawMarker = "SENSITIVE_RAW_REFERRER_MARKER"
        val logs = mutableListOf<String>()
        Timber.plant(object : Timber.Tree() {
            override fun log(priority: Int, tag: String?, message: String, t: Throwable?) {
                logs += message
                t?.message?.let(logs::add)
            }
        })
        val source = FakeInstallReferrerSource(
            listOf(
                InstallReferrerResult.Referrer(
                    rawReferrer =
                        "utm_source=yt&utm_medium=campaign_shortlink" +
                            "&utm_campaign=yt_csv_001&utm_content=csv&extra=$rawMarker",
                    referrerClickTimestampSeconds = null,
                    installBeginTimestampSeconds = null,
                )
            )
        )
        val store = InMemoryCampaignAttributionStore()

        orchestrator(source, store).processStartup()

        assertThat(logs.joinToString("\n")).doesNotContain(rawMarker)
        assertThat(logs.joinToString("\n")).doesNotContain("utm_")
        assertThat(store.snapshot.event).isNull()
    }

    private fun orchestrator(
        source: InstallReferrerSource,
        store: CampaignAttributionStore,
        scheduler: CampaignAttributionWorkScheduler = FakeCampaignAttributionScheduler(),
    ): CampaignAttributionOrchestrator = CampaignAttributionOrchestrator(
        source = source,
        parser = CampaignReferrerParser(),
        store = store,
        eventFactory = CampaignAttributionEventFactory(
            appInfo = CampaignAttributionAppInfo("1.5.1", "19"),
            clock = CampaignAttributionClock { Instant.parse("2026-07-14T12:00:00Z") },
            uuidGenerator = CampaignAttributionUuidGenerator {
                "22222222-2222-4222-8222-222222222222"
            },
        ),
        scheduler = scheduler,
        retryDelay = CampaignAttributionRetryDelay { },
    )

    private fun validReferrerResult() = InstallReferrerResult.Referrer(
        rawReferrer =
            "utm_source=yt&utm_medium=campaign_shortlink" +
                "&utm_campaign=yt_csv_001&utm_content=csv",
        referrerClickTimestampSeconds = 1_234_567_890L,
        installBeginTimestampSeconds = 1_234_567_900L,
    )
}
