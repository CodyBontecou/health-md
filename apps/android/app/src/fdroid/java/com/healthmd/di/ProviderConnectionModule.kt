package com.healthmd.di

import com.healthmd.data.health.providers.FdroidHealthProviderConnectionManager
import com.healthmd.data.health.providers.HealthProviderConnectionManager
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object ProviderConnectionModule {
    @Provides
    @Singleton
    fun provideHealthProviderConnectionManager(
        manager: FdroidHealthProviderConnectionManager,
    ): HealthProviderConnectionManager = manager
}
