package com.healthmd.presentation.paywall

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.repository.PurchaseRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.export.MainDispatcherRule
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class PaywallViewModelTest {
    @get:Rule val mainDispatcherRule = MainDispatcherRule()

    @Test fun trialAndSubscriptionAccessAreNotPersistedAsLifetime() = runTest {
        val settings = mockk<SettingsRepository>(relaxed = true)
        val live = MutableStateFlow(true)
        val permanent = MutableStateFlow(false)
        every { settings.isPurchased } returns MutableStateFlow(false)
        val model = model(settings, live, permanent)
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.accessState.collect {} }
        advanceUntilIdle()
        assertThat(model.accessState.value).isTrue()
        coVerify(exactly = 0) { settings.setPurchased(any()) }
        live.value = false
        advanceUntilIdle()
        assertThat(model.accessState.value).isFalse()
        coVerify(exactly = 0) { settings.setPurchased(any()) }
    }

    @Test fun existingPersistedLifetimeOwnerNeverLosesAccessWhenStoreIsUnavailable() = runTest {
        val settings = mockk<SettingsRepository>(relaxed = true)
        every { settings.isPurchased } returns MutableStateFlow(true)
        val model = model(settings, MutableStateFlow(false), MutableStateFlow(false))
        backgroundScope.launch(UnconfinedTestDispatcher(testScheduler)) { model.accessState.collect {} }
        advanceUntilIdle()
        assertThat(model.accessState.value).isTrue()
    }

    @Test fun permanentPurchaseStillPersistsForExistingConsumers() = runTest {
        val settings = mockk<SettingsRepository>(relaxed = true)
        every { settings.isPurchased } returns MutableStateFlow(false)
        model(settings, MutableStateFlow(true), MutableStateFlow(true))
        advanceUntilIdle()
        coVerify(exactly = 1) { settings.setPurchased(true) }
    }

    private fun model(
        settings: SettingsRepository,
        live: MutableStateFlow<Boolean>,
        permanent: MutableStateFlow<Boolean>,
    ): PaywallViewModel {
        val entitlement = mockk<EntitlementRepository>(relaxed = true)
        every { entitlement.isUnlocked } returns live
        every { entitlement.isPermanentlyUnlocked } returns permanent
        val purchases = mockk<PurchaseRepository>(relaxed = true)
        every { purchases.isAvailable } returns true
        every { purchases.isPurchasing } returns MutableStateFlow(false)
        every { purchases.isRestoring } returns MutableStateFlow(false)
        every { purchases.purchaseError } returns MutableStateFlow(null)
        every { purchases.offer } returns MutableStateFlow(null)
        every { purchases.offers } returns MutableStateFlow(emptyList())
        return PaywallViewModel(entitlement, purchases, settings, DistributionPolicy.play())
    }
}
