package com.healthmd.di

import android.content.Context
import com.healthmd.data.health.HealthConnectDataProvider
import com.healthmd.data.health.HealthDataProvider
import com.healthmd.data.health.HealthProviderRegistry
import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.data.health.providers.HealthProviderCatalog
import com.healthmd.data.health.providers.PlayHealthProviderDefinitions
import com.healthmd.data.health.providers.cloud.CloudHealthApiClient
import com.healthmd.data.health.providers.cloud.FitbitCloudDataProvider
import com.healthmd.data.health.providers.cloud.OuraCloudDataProvider
import com.healthmd.data.health.providers.cloud.PolarCloudDataProvider
import com.healthmd.data.health.providers.cloud.WhoopCloudDataProvider
import com.healthmd.data.health.providers.cloud.WithingsCloudDataProvider
import com.healthmd.data.health.providers.direct.GarminDirectDataProvider
import com.healthmd.data.health.providers.direct.HuaweiHealthDirectDataProvider
import com.healthmd.data.health.providers.direct.SamsungHealthDirectDataProvider
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

    @Provides @Singleton fun provideSamsung() = SamsungHealthDirectDataProvider()
    @Provides @Singleton fun provideHuawei() = HuaweiHealthDirectDataProvider()
    @Provides @Singleton fun provideGarmin() = GarminDirectDataProvider()
    @Provides @Singleton fun provideFitbit(client: CloudHealthApiClient) = FitbitCloudDataProvider(client)
    @Provides @Singleton fun provideWithings(client: CloudHealthApiClient) = WithingsCloudDataProvider(client)
    @Provides @Singleton fun provideOura(client: CloudHealthApiClient) = OuraCloudDataProvider(client)
    @Provides @Singleton fun providePolar(client: CloudHealthApiClient) = PolarCloudDataProvider(client)
    @Provides @Singleton fun provideWhoop(client: CloudHealthApiClient) = WhoopCloudDataProvider(client)

    @Provides
    @Singleton
    fun provideHealthProviderRegistry(
        healthConnect: HealthConnectDataProvider,
        samsung: SamsungHealthDirectDataProvider,
        huawei: HuaweiHealthDirectDataProvider,
        fitbit: FitbitCloudDataProvider,
        garmin: GarminDirectDataProvider,
        withings: WithingsCloudDataProvider,
        oura: OuraCloudDataProvider,
        polar: PolarCloudDataProvider,
        whoop: WhoopCloudDataProvider,
    ): HealthProviderRegistry = HealthProviderRegistry(
        healthConnectDataProvider = healthConnect,
        additionalProviders = listOf<HealthDataProvider>(
            samsung,
            huawei,
            fitbit,
            garmin,
            withings,
            oura,
            polar,
            whoop,
        ),
    )

    @Provides
    @Singleton
    fun provideRawHealthRepositoryRegistry(
        healthConnect: RawHealthRepository,
        apiClient: CloudHealthApiClient,
        fitbit: FitbitCloudDataProvider,
        withings: WithingsCloudDataProvider,
        oura: OuraCloudDataProvider,
        whoop: WhoopCloudDataProvider,
    ): RawHealthRepositoryRegistry = PlayRawHealthRepositoryRegistryFactory.create(
        healthConnect,
        apiClient,
        fitbit,
        withings,
        oura,
        whoop,
    )

    @Provides
    @Singleton
    fun provideHealthProviderCatalog(@ApplicationContext context: Context): HealthProviderCatalog =
        HealthProviderCatalog(context, PlayHealthProviderDefinitions.all())
}
