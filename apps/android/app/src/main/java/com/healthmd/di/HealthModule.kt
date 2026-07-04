package com.healthmd.di

import android.content.Context
import com.healthmd.data.health.HealthConnectDataProvider
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.HealthProviderRegistry
import com.healthmd.data.health.HealthRepositoryImpl
import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.data.health.providers.HealthProviderCatalog
import com.healthmd.data.health.providers.cloud.CloudHealthApiClient
import com.healthmd.data.health.providers.cloud.FitbitCloudDataProvider
import com.healthmd.data.health.providers.cloud.OuraCloudDataProvider
import com.healthmd.data.health.providers.cloud.PolarCloudDataProvider
import com.healthmd.data.health.providers.cloud.WhoopCloudDataProvider
import com.healthmd.data.health.providers.cloud.WithingsCloudDataProvider
import com.healthmd.data.health.providers.direct.GarminDirectDataProvider
import com.healthmd.data.health.providers.direct.HuaweiHealthDirectDataProvider
import com.healthmd.data.health.providers.direct.SamsungHealthDirectDataProvider
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object HealthModule {

    @Provides
    @Singleton
    fun provideHealthConnectManager(@ApplicationContext context: Context): HealthConnectManager =
        HealthConnectManager(context)

    @Provides
    @Singleton
    fun provideHealthConnectDataProvider(healthConnectManager: HealthConnectManager): HealthConnectDataProvider =
        HealthConnectDataProvider(healthConnectManager)

    @Provides
    @Singleton
    fun provideCloudHealthApiClient(oauthAuthorizationManager: OAuthAuthorizationManager): CloudHealthApiClient =
        CloudHealthApiClient(oauthAuthorizationManager)

    @Provides
    @Singleton
    fun provideSamsungHealthDirectDataProvider(): SamsungHealthDirectDataProvider =
        SamsungHealthDirectDataProvider()

    @Provides
    @Singleton
    fun provideHuaweiHealthDirectDataProvider(): HuaweiHealthDirectDataProvider =
        HuaweiHealthDirectDataProvider()

    @Provides
    @Singleton
    fun provideGarminDirectDataProvider(): GarminDirectDataProvider =
        GarminDirectDataProvider()

    @Provides
    @Singleton
    fun provideFitbitCloudDataProvider(apiClient: CloudHealthApiClient): FitbitCloudDataProvider =
        FitbitCloudDataProvider(apiClient)

    @Provides
    @Singleton
    fun provideWithingsCloudDataProvider(apiClient: CloudHealthApiClient): WithingsCloudDataProvider =
        WithingsCloudDataProvider(apiClient)

    @Provides
    @Singleton
    fun provideOuraCloudDataProvider(apiClient: CloudHealthApiClient): OuraCloudDataProvider =
        OuraCloudDataProvider(apiClient)

    @Provides
    @Singleton
    fun providePolarCloudDataProvider(apiClient: CloudHealthApiClient): PolarCloudDataProvider =
        PolarCloudDataProvider(apiClient)

    @Provides
    @Singleton
    fun provideWhoopCloudDataProvider(apiClient: CloudHealthApiClient): WhoopCloudDataProvider =
        WhoopCloudDataProvider(apiClient)

    @Provides
    @Singleton
    fun provideHealthProviderRegistry(
        healthConnectDataProvider: HealthConnectDataProvider,
        samsungHealthDirectDataProvider: SamsungHealthDirectDataProvider,
        huaweiHealthDirectDataProvider: HuaweiHealthDirectDataProvider,
        fitbitCloudDataProvider: FitbitCloudDataProvider,
        garminDirectDataProvider: GarminDirectDataProvider,
        withingsCloudDataProvider: WithingsCloudDataProvider,
        ouraCloudDataProvider: OuraCloudDataProvider,
        polarCloudDataProvider: PolarCloudDataProvider,
        whoopCloudDataProvider: WhoopCloudDataProvider,
    ): HealthProviderRegistry = HealthProviderRegistry(
        healthConnectDataProvider = healthConnectDataProvider,
        samsungHealthDirectDataProvider = samsungHealthDirectDataProvider,
        huaweiHealthDirectDataProvider = huaweiHealthDirectDataProvider,
        fitbitCloudDataProvider = fitbitCloudDataProvider,
        garminDirectDataProvider = garminDirectDataProvider,
        withingsCloudDataProvider = withingsCloudDataProvider,
        ouraCloudDataProvider = ouraCloudDataProvider,
        polarCloudDataProvider = polarCloudDataProvider,
        whoopCloudDataProvider = whoopCloudDataProvider,
    )

    @Provides
    @Singleton
    fun provideHealthProviderCatalog(@ApplicationContext context: Context): HealthProviderCatalog =
        HealthProviderCatalog(context)

    @Provides
    @Singleton
    fun provideHealthRepository(
        providerRegistry: HealthProviderRegistry,
        settingsRepository: SettingsRepository,
    ): HealthRepository =
        HealthRepositoryImpl(providerRegistry, settingsRepository)
}
