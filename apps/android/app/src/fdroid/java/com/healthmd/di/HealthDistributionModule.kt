package com.healthmd.di

import android.content.Context
import com.healthmd.data.health.HealthConnectDataProvider
import com.healthmd.data.health.HealthProviderRegistry
import com.healthmd.data.health.providers.HealthProviderCatalog
import com.healthmd.rawexport.RawHealthRepository
import com.healthmd.rawexport.RawHealthRepositoryRegistry
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object HealthDistributionModule {
    @Provides
    @Singleton
    fun provideHealthProviderRegistry(
        healthConnect: HealthConnectDataProvider,
    ): HealthProviderRegistry = HealthProviderRegistry(healthConnect)

    @Provides
    @Singleton
    fun provideRawHealthRepositoryRegistry(
        healthConnect: RawHealthRepository,
    ): RawHealthRepositoryRegistry = RawHealthRepositoryRegistry.healthConnectOnly(healthConnect)

    @Provides
    @Singleton
    fun provideHealthProviderCatalog(@ApplicationContext context: Context): HealthProviderCatalog =
        HealthProviderCatalog(context, listOf(HealthProviderCatalog.healthConnectDefinition()))
}
