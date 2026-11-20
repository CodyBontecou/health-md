package com.healthmd.presentation.onboarding

import android.app.Application
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.drive.GoogleDriveAuthorizationManager
import com.healthmd.data.drive.GoogleDriveErrorId
import com.healthmd.data.drive.GoogleDriveReadiness
import com.healthmd.data.settings.SavedAPIEndpointCoordinator
import com.healthmd.domain.billing.BillingError
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.repository.PurchaseRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.export.MainDispatcherRule
import io.mockk.coEvery
import io.mockk.coVerify
import io.mockk.every
import io.mockk.mockk
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test

/** Make it daily's Restore for a returning user who reinstalled. */
@OptIn(ExperimentalCoroutinesApi::class)
class OnboardingRestoreViewModelTest {
    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    private val unlocked = MutableStateFlow(false)
    private val purchaseError = MutableStateFlow<BillingError?>(null)
    private val purchaseRepository = mockk<PurchaseRepository>(relaxed = true) {
        every { isAvailable } returns true
        every { offers } returns MutableStateFlow(emptyList())
        every { isPurchasing } returns MutableStateFlow(false)
        every { isRestoring } returns MutableStateFlow(false)
        every { purchaseError } returns this@OnboardingRestoreViewModelTest.purchaseError
    }

    private fun viewModel(policy: DistributionPolicy = DistributionPolicy.play()) = OnboardingViewModel(
        application = mockk<Application>(relaxed = true),
        settingsRepository = mockk<SettingsRepository>(relaxed = true) {
            every { exportSettings } returns MutableStateFlow(ExportSettings())
            every { exportFolderUri } returns MutableStateFlow(null)
            every { isPurchased } returns MutableStateFlow(false)
            coEvery { getExportSettings() } returns ExportSettings()
        },
        distributionPolicy = policy,
        healthRepository = mockk(relaxed = true),
        exportRepository = mockk(relaxed = true),
        profileRepository = mockk(relaxed = true),
        profileCoordinator = mockk(relaxed = true),
        entryStore = mockk(relaxed = true),
        profileScheduler = mockk(relaxed = true),
        entitlementRepository = mockk<EntitlementRepository>(relaxed = true) { every { isUnlocked } returns unlocked },
        purchaseRepository = purchaseRepository,
        endpointCoordinator = mockk<SavedAPIEndpointCoordinator>(relaxed = true) {
            every { endpoints } returns MutableStateFlow(emptyList())
        },
        driveAuthorization = mockk<GoogleDriveAuthorizationManager> {
            every { readiness() } returns GoogleDriveReadiness.Unavailable(GoogleDriveErrorId.CONFIGURATION_MISSING)
        },
        driveDestinationStore = mockk(relaxed = true),
    )

    @Test
    fun restoredPurchaseUnlocksAndSwitchesTheStepToEnable() = runTest {
        coEvery { purchaseRepository.restorePurchase() } coAnswers { unlocked.value = true; true }
        val vm = viewModel()
        advanceUntilIdle()
        vm.goTo(OnboardingStep.DAILY)
        assertThat(OnboardingFlow.dailyOffer(vm.distributionPolicy, vm.uiState.value.hasPaidAccess)).isEqualTo(DailyOffer.TRIAL)

        vm.restorePurchases()
        advanceUntilIdle()

        coVerify(exactly = 1) { purchaseRepository.restorePurchase() }
        val state = vm.uiState.value
        assertThat(state.hasPaidAccess).isTrue()
        assertThat(state.step).isEqualTo(OnboardingStep.DAILY)
        assertThat(OnboardingFlow.dailyOffer(vm.distributionPolicy, state.hasPaidAccess)).isEqualTo(DailyOffer.ENABLE)
        assertThat(OnboardingFlow.dailyErrorMessage(state.purchaseError, state.restoreAttempted)).isNull()
    }

    @Test
    fun failedRestoreShowsTheRestoreErrorAndStaysOnTheTrial() = runTest {
        coEvery { purchaseRepository.restorePurchase() } coAnswers { purchaseError.value = BillingError.RESTORE_FAILED; false }
        val vm = viewModel()
        advanceUntilIdle()

        vm.restorePurchases()
        advanceUntilIdle()

        val state = vm.uiState.value
        assertThat(state.hasPaidAccess).isFalse()
        assertThat(OnboardingFlow.dailyErrorMessage(state.purchaseError, state.restoreAttempted))
            .isEqualTo(com.healthmd.R.string.billing_error_restore_failed)
        // A later trial attempt reports trial failures again, not restore ones.
        vm.clearPurchaseError()
        assertThat(vm.uiState.value.restoreAttempted).isFalse()
    }

    @Test
    fun restoreIsANoOpWhereStorePurchasesAreUnavailable() = runTest {
        val vm = viewModel(DistributionPolicy.play().copy(purchasesAvailable = false))
        advanceUntilIdle()

        vm.restorePurchases()
        advanceUntilIdle()

        coVerify(exactly = 0) { purchaseRepository.restorePurchase() }
        assertThat(vm.uiState.value.restoreAttempted).isFalse()
    }
}
