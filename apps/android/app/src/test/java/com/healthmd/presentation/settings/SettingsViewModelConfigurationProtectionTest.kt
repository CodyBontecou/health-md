package com.healthmd.presentation.settings

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.health.HealthProviderDiagnosticsReporter
import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.data.health.providers.HealthProviderCatalog
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.export.MainDispatcherRule
import io.mockk.coEvery
import io.mockk.every
import io.mockk.mockk
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Rule
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class SettingsViewModelConfigurationProtectionTest {
    @get:Rule
    val mainDispatcherRule = MainDispatcherRule()

    @Test
    fun failedDisableRemainsProtectedUntilPersistenceSucceeds() =
        runTest(mainDispatcherRule.testDispatcher) {
            val persistedProtection = MutableStateFlow(true)
            val releaseFailedWrite = CompletableDeferred<Unit>()
            val repository = mockk<SettingsRepository>(relaxed = true) {
                every { preventAccidentalChanges } returns persistedProtection
            }
            coEvery { repository.setPreventAccidentalChanges(false) } coAnswers {
                releaseFailedWrite.await()
                error("DataStore write failed")
            }
            val viewModel = SettingsViewModel(
                repository,
                mockk<HealthProviderCatalog>(relaxed = true),
                mockk<OAuthAuthorizationManager>(relaxed = true),
                mockk<HealthProviderDiagnosticsReporter>(relaxed = true),
            )
            advanceUntilIdle()
            assertThat(viewModel.preventAccidentalChanges.value).isTrue()

            viewModel.setPreventAccidentalChanges(false)
            runCurrent()
            assertThat(viewModel.preventAccidentalChanges.value).isTrue()

            val mutationCount = AtomicInteger(0)
            viewModel.performConfigurationChange { mutationCount.incrementAndGet() }
            assertThat(mutationCount.get()).isEqualTo(0)
            assertThat(viewModel.blockedChangeToastId.value).isNotNull()

            releaseFailedWrite.complete(Unit)
            advanceUntilIdle()
            assertThat(viewModel.preventAccidentalChanges.value).isTrue()
        }
}
