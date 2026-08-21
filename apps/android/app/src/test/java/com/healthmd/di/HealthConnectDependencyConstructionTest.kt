package com.healthmd.di

import android.content.Context
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.rawexport.ExerciseRouteConsentCoordinator
import io.mockk.mockk
import org.junit.Test

class HealthConnectDependencyConstructionTest {
    @Test
    fun dependencyGraphConstructionDoesNotRequireAnInstalledHealthConnectProvider() {
        val context = mockk<Context>(relaxed = true)
        val settingsRepository = mockk<SettingsRepository>(relaxed = true)
        val routeConsentCoordinator = ExerciseRouteConsentCoordinator()

        assertThat(HealthModule.provideHealthConnectManager(context, routeConsentCoordinator)).isNotNull()
        assertThat(
            HealthModule.provideHealthConnectRawDataProvider(context, settingsRepository, routeConsentCoordinator)
        ).isNotNull()
        assertThat(HealthModule.provideHealthConnectChangesSource(context)).isNotNull()
    }
}
