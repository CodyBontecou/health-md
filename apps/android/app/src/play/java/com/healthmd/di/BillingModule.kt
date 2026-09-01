package com.healthmd.di

import android.content.Context
import com.healthmd.data.billing.BillingRepositoryImpl
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.repository.PurchaseRepository
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
    ): BillingRepositoryImpl = BillingRepositoryImpl(context)

    @Provides
    fun provideEntitlementRepository(
        repository: BillingRepositoryImpl,
    ): EntitlementRepository = repository

    @Provides
    fun providePurchaseRepository(
        repository: BillingRepositoryImpl,
    ): PurchaseRepository = repository
}
