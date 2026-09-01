package com.healthmd.di

import com.healthmd.distribution.DistributionRuntime
import com.healthmd.distribution.FdroidDistributionRuntime
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.review.ReviewPrompter
import com.healthmd.review.FdroidReviewPrompter
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object DistributionModule {
    @Provides
    @Singleton
    fun provideDistributionPolicy(): DistributionPolicy = DistributionPolicy.fdroid()

    @Provides
    @Singleton
    fun provideReviewPrompter(): ReviewPrompter = FdroidReviewPrompter()

    @Provides
    @Singleton
    fun provideDistributionRuntime(): DistributionRuntime = FdroidDistributionRuntime()
}
