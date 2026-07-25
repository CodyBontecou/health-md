package com.healthmd.di

import android.content.Context
import com.healthmd.data.billing.BillingRepositoryImpl
import com.healthmd.domain.repository.BillingRepository
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object BillingModule {

    @Provides
    @Singleton
    fun provideBillingRepository(
        @ApplicationContext context: Context,
    ): BillingRepository = BillingRepositoryImpl(context)
}
