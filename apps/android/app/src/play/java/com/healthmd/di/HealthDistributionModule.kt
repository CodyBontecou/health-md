package com.healthmd.di

import android.content.Context
import com.healthmd.data.health.HealthConnectDataProvider
import com.healthmd.data.health.HealthDataProvider
import com.healthmd.data.health.HealthProviderRegistry
import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.data.health.providers.HealthProviderCatalog
import com.healthmd.data.health.providers.PlayHealthProviderDefinitions
import com.healthmd.data.health.providers.cloud.CloudHealthApiClient
import com.healthmd.data.health.providers.cloud.WhoopCloudDataProvider
import com.healthmd.rawexport.RawHealthRepository
import com.healthmd.rawexport.PlayRawHealthRepositoryRegistryFactory
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
    fun provideCloudHealthApiClient(manager: OAuthAuthorizationManager) = CloudHealthApiClient(manager)

    @Provides @Singleton fun provideWhoop(client: CloudHealthApiClient) = WhoopCloudDataProvider(client)

    @Provides
    @Singleton
    fun provideHealthProviderRegistry(
        healthConnect: HealthConnectDataProvider,
        whoop: WhoopCloudDataProvider,
    ): HealthProviderRegistry = HealthProviderRegistry(
        healthConnectDataProvider = healthConnect,
        additionalProviders = listOf<HealthDataProvider>(whoop),
    )

    @Provides
    @Singleton
    fun provideRawHealthRepositoryRegistry(
        healthConnect: RawHealthRepository,
        apiClient: CloudHealthApiClient,
        whoop: WhoopCloudDataProvider,
    ): RawHealthRepositoryRegistry = PlayRawHealthRepositoryRegistryFactory.create(
        healthConnect,
        apiClient,
        whoop,
    )

    @Provides
    @Singleton
    fun provideHealthProviderCatalog(@ApplicationContext context: Context): HealthProviderCatalog =
        HealthProviderCatalog(context, PlayHealthProviderDefinitions.all())
}
