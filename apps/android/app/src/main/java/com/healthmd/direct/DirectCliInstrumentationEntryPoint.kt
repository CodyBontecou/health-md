package com.healthmd.direct

import androidx.annotation.VisibleForTesting
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@VisibleForTesting
@EntryPoint
@InstallIn(SingletonComponent::class)
interface DirectCliInstrumentationEntryPoint {
    fun coordinator(): DirectCliCoordinator
    fun settingsRepository(): SettingsRepository
    fun trustStore(): DirectCliTrustStore
}
