package com.healthmd.di

import android.content.Context
import com.healthmd.myselfclaim.MyselfClaimPurchaseSource
import com.healthmd.data.billing.BillingRepositoryImpl
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.repository.PurchaseRepository
import com.healthmd.domain.repository.SettingsRepository
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
        settingsRepository: SettingsRepository,
    ): BillingRepositoryImpl = BillingRepositoryImpl(
        context,
        settingsRepository,
        subscriptionVerifier = com.healthmd.data.billing.PlaySubscriptionStatusApi(),
    )

    @Provides
    fun provideMyselfClaimPurchaseSource(repository: BillingRepositoryImpl): MyselfClaimPurchaseSource =
        MyselfClaimPurchaseSource { repository.myselfClaimPurchaseToken() }

    @Provides
    @Singleton
    fun provideEntitlementRepository(
        repository: BillingRepositoryImpl,
        clinic: com.healthmd.data.billing.ClinicSponsorshipManager,
    ): EntitlementRepository = com.healthmd.data.billing.ClinicAwareEntitlementRepository(repository, clinic)

    @Provides
    fun providePurchaseRepository(
        repository: BillingRepositoryImpl,
    ): PurchaseRepository = repository
}
