package com.healthmd.di

import com.healthmd.distribution.DistributionRuntime
import com.healthmd.distribution.PlayDistributionRuntime
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.review.ReviewPrompter
import com.healthmd.review.PlayReviewPrompter
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
    fun provideDistributionPolicy(): DistributionPolicy = DistributionPolicy.play()

    @Provides
    @Singleton
    fun provideReviewPrompter(): ReviewPrompter = PlayReviewPrompter()

    @Provides
    @Singleton
    fun provideDistributionRuntime(runtime: PlayDistributionRuntime): DistributionRuntime = runtime
}
