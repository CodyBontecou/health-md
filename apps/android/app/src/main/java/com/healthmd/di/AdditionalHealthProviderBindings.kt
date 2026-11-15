package com.healthmd.di

import com.healthmd.data.health.HealthDataProvider
import dagger.Module
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import dagger.multibindings.Multibinds
import javax.inject.Named

/** Optional source adapters. Ordinary builds contribute none; E2E can substitute only an SDK source. */
@Module
@InstallIn(SingletonComponent::class)
abstract class AdditionalHealthProviderBindings {
    @Multibinds
    @Named("additional_runtime_health_providers")
    abstract fun providers(): Set<HealthDataProvider>
}
