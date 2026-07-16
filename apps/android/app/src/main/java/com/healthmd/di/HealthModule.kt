package com.healthmd.di

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
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
import com.healthmd.rawexport.DefaultRawHealthRepository
import com.healthmd.rawexport.HealthConnectRawDataProvider
import com.healthmd.rawexport.RawHealthRepository
import com.healthmd.rawexport.RawHealthRepositoryRegistry
import com.healthmd.rawchanges.DefaultRawChangesService
import com.healthmd.rawchanges.HealthConnectChangesSource
import com.healthmd.rawchanges.NoBackupRawChangesDestination
import com.healthmd.rawchanges.RawChangesService
import com.healthmd.rawchanges.SQLiteRawChangesStateStore
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
    fun provideHealthConnectClient(@ApplicationContext context: Context): HealthConnectClient =
        HealthConnectClient.getOrCreate(context)

    @Provides
    @Singleton
    fun provideHealthConnectManager(
        @ApplicationContext context: Context,
        client: HealthConnectClient,
    ): HealthConnectManager = HealthConnectManager(context, client)

    @Provides
    @Singleton
    fun provideHealthConnectRawDataProvider(
        @ApplicationContext context: Context,
        client: HealthConnectClient,
    ): HealthConnectRawDataProvider = HealthConnectRawDataProvider(context, client)

    @Provides
    @Singleton
    fun provideRawHealthRepository(provider: HealthConnectRawDataProvider): RawHealthRepository =
        DefaultRawHealthRepository(provider)

    @Provides
    @Singleton
    fun provideHealthConnectChangesSource(
        @ApplicationContext context: Context,
        client: HealthConnectClient,
    ): HealthConnectChangesSource = HealthConnectChangesSource(context, client)

    @Provides
    @Singleton
    internal fun provideRawChangesStateStore(
        @ApplicationContext context: Context,
    ): SQLiteRawChangesStateStore = SQLiteRawChangesStateStore(context)

    @Provides
    @Singleton
    internal fun provideRawChangesDestination(
        @ApplicationContext context: Context,
    ): NoBackupRawChangesDestination = NoBackupRawChangesDestination(context)

    @Provides
    @Singleton
    internal fun provideRawChangesService(
        @ApplicationContext context: Context,
        source: HealthConnectChangesSource,
        state: SQLiteRawChangesStateStore,
        destination: NoBackupRawChangesDestination,
    ): RawChangesService = DefaultRawChangesService(context, source, state, destination)

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
    fun provideRawHealthRepositoryRegistry(
        rawHealthRepository: RawHealthRepository,
        apiClient: CloudHealthApiClient,
        fitbit: FitbitCloudDataProvider,
        withings: WithingsCloudDataProvider,
        oura: OuraCloudDataProvider,
        whoop: WhoopCloudDataProvider,
    ): RawHealthRepositoryRegistry = RawHealthRepositoryRegistry.create(
        rawHealthRepository, apiClient, fitbit, withings, oura, whoop,
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
