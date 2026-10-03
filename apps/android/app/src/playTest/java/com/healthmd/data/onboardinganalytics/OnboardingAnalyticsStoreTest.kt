package com.healthmd.data.onboardinganalytics

import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.test.runTest
import org.junit.Test

class OnboardingAnalyticsStoreTest {
    @Test
    fun installAndQueuedEventIdsRemainStableAcrossStoreRecreation() = runTest {
        val persistence = InMemoryStatePersistence()
        val store = store(persistence)
        val event = event(1)

        assertThat(store.getOrCreateInstallId()).isEqualTo(INSTALL_ID)
        assertThat(store.enqueue(event, milestone(PricingOnboardingEventName.STARTED))).isTrue()

        val recreated = store(persistence)
        assertThat(recreated.getOrCreateInstallId()).isEqualTo(INSTALL_ID)
        assertThat(recreated.loadBatch(20)?.events?.single()?.eventId).isEqualTo(event.eventId)
    }

    @Test
    fun queueIsDurablyCappedAtFiftyNewestAllowlistedEvents() = runTest {
        val allEvents = (1..60).map(::event)
        val persistence = InMemoryStatePersistence(
            OnboardingAnalyticsStateCodec.encode(
                PersistedOnboardingAnalyticsState(
                    installId = INSTALL_ID,
                    events = allEvents,
                )
            )
        )

        val batch = store(persistence).loadBatch(DurableOnboardingAnalyticsStore.MAX_QUEUE_SIZE)
        val recreatedBatch = store(persistence).loadBatch(DurableOnboardingAnalyticsStore.MAX_QUEUE_SIZE)

        assertThat(batch?.events).hasSize(50)
        assertThat(batch?.events?.first()?.eventId).isEqualTo(event(11).eventId)
        assertThat(recreatedBatch?.events).isEqualTo(batch?.events)
    }

    @Test
    fun milestoneDedupeSurvivesStoreRecreation() = runTest {
        val persistence = InMemoryStatePersistence()
        val key = milestone(PricingOnboardingEventName.STEP_VIEWED)

        assertThat(store(persistence).enqueue(event(1), key)).isTrue()
        assertThat(store(persistence).enqueue(event(2), key)).isFalse()

        assertThat(store(persistence).loadBatch(20)?.events?.map { it.eventId })
            .containsExactly(event(1).eventId)
    }

    private fun store(persistence: InMemoryStatePersistence) = DurableOnboardingAnalyticsStore(
        persistence = persistence,
        uuidGenerator = OnboardingAnalyticsUuidGenerator { INSTALL_ID },
    )

    private fun milestone(
        eventName: PricingOnboardingEventName,
    ) = DurableOnboardingAnalyticsStore.milestoneKey(
        eventName,
        OnboardingAnalyticsStep.WELCOME,
    )

    private fun event(index: Int) = OnboardingAnalyticsEvent(
        eventId = uuid(index),
        eventName = PricingOnboardingEventName.STEP_VIEWED.wireName,
        properties = OnboardingAnalyticsProperties(
            appVersion = "1.5.4",
            buildNumber = "25",
            onboardingStep = OnboardingAnalyticsStep.WELCOME.wireName,
        ),
    )

    private fun uuid(index: Int): String =
        "%08x-0000-4000-8000-%012x".format(index, index)

    private class InMemoryStatePersistence(
        private var encoded: String? = null,
    ) : OnboardingAnalyticsStatePersistence {
        private val mutex = Mutex()

        override suspend fun read(): PersistedOnboardingAnalyticsState = mutex.withLock {
            OnboardingAnalyticsStateCodec.decode(encoded)
        }

        override suspend fun update(
            transform: (PersistedOnboardingAnalyticsState) -> PersistedOnboardingAnalyticsState,
        ): PersistedOnboardingAnalyticsState = mutex.withLock {
            transform(OnboardingAnalyticsStateCodec.decode(encoded)).also {
                encoded = OnboardingAnalyticsStateCodec.encode(it)
            }
        }
    }

    private companion object {
        const val INSTALL_ID = "11111111-1111-4111-8111-111111111111"
    }
}
