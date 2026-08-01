package com.healthmd.di

import android.content.Context
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.repository.SettingsRepository
import io.mockk.mockk
import org.junit.Test

class HealthConnectDependencyConstructionTest {
    @Test
    fun dependencyGraphConstructionDoesNotRequireAnInstalledHealthConnectProvider() {
        val context = mockk<Context>(relaxed = true)
        val settingsRepository = mockk<SettingsRepository>(relaxed = true)

        assertThat(HealthModule.provideHealthConnectManager(context)).isNotNull()
        assertThat(
            HealthModule.provideHealthConnectRawDataProvider(context, settingsRepository)
        ).isNotNull()
        assertThat(HealthModule.provideHealthConnectChangesSource(context)).isNotNull()
    }
}
