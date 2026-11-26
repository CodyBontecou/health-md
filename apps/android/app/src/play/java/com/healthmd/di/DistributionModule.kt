package com.healthmd.di

import android.content.Context
import com.healthmd.distribution.DistributionRuntime
import com.healthmd.distribution.PlayDistributionRuntime
import com.healthmd.domain.distribution.DistributionPolicy
import com.healthmd.domain.review.ReviewPrompter
import com.healthmd.review.PlayReviewPrompter
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
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
    fun provideReviewPrompter(@ApplicationContext context: Context): ReviewPrompter = PlayReviewPrompter(context)

    @Provides
    @Singleton
    fun provideDistributionRuntime(runtime: PlayDistributionRuntime): DistributionRuntime = runtime
}
