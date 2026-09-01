package com.healthmd.di

import android.content.Context
import com.healthmd.data.health.HealthConnectDataProvider
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.HealthProviderRegistry
import com.healthmd.data.health.HealthRepositoryImpl
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.rawexport.DefaultRawHealthRepository
import com.healthmd.rawexport.ExerciseRouteConsentCoordinator
import com.healthmd.rawexport.HealthConnectRawDataProvider
import com.healthmd.rawexport.RawHealthRepository
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
    fun provideHealthConnectManager(
        @ApplicationContext context: Context,
        routeConsentCoordinator: ExerciseRouteConsentCoordinator,
    ): HealthConnectManager = HealthConnectManager(context, routeConsentGateway = routeConsentCoordinator)

    @Provides
    @Singleton
    fun provideHealthConnectRawDataProvider(
        @ApplicationContext context: Context,
        settingsRepository: SettingsRepository,
        routeConsentCoordinator: ExerciseRouteConsentCoordinator,
    ): HealthConnectRawDataProvider = HealthConnectRawDataProvider(
        context = context,
        historyAccessBoundary = com.healthmd.rawexport.HistoryAccessBoundary {
            settingsRepository.getFirstHealthPermissionGrantDate()
        },
        routeConsentGateway = routeConsentCoordinator,
    )

    @Provides
    @Singleton
    fun provideRawHealthRepository(provider: HealthConnectRawDataProvider): RawHealthRepository =
        DefaultRawHealthRepository(provider)

    @Provides
    @Singleton
    fun provideHealthConnectChangesSource(
        @ApplicationContext context: Context,
    ): HealthConnectChangesSource = HealthConnectChangesSource(context)

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
    fun provideHealthRepository(
        providerRegistry: HealthProviderRegistry,
        settingsRepository: SettingsRepository,
    ): HealthRepository =
        HealthRepositoryImpl(providerRegistry, settingsRepository)
}
