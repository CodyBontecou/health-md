package com.healthmd.di

import android.content.Context
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.HealthRepositoryImpl
import com.healthmd.domain.repository.HealthRepository
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
    fun provideHealthRepository(healthConnectManager: HealthConnectManager): HealthRepository =
        HealthRepositoryImpl(healthConnectManager)
}
