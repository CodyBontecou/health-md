package com.healthmd.di

import com.healthmd.myselfclaim.MyselfClaimPurchaseSource
import com.healthmd.myselfclaim.MyselfClaimException
import com.healthmd.myselfclaim.MyselfClaimFailure
import com.healthmd.data.access.FdroidAccessRepository
import com.healthmd.domain.repository.EntitlementRepository
import com.healthmd.domain.repository.PurchaseRepository
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AccessModule {
    @Provides
    @Singleton
    fun provideFdroidAccessRepository(): FdroidAccessRepository = FdroidAccessRepository()

    @Provides
    fun provideMyselfClaimPurchaseSource(): MyselfClaimPurchaseSource =
        MyselfClaimPurchaseSource { throw MyselfClaimException(MyselfClaimFailure.NO_PURCHASE) }

    @Provides
    fun provideEntitlementRepository(repository: FdroidAccessRepository): EntitlementRepository =
        repository

    @Provides
    fun providePurchaseRepository(repository: FdroidAccessRepository): PurchaseRepository =
        repository
}
