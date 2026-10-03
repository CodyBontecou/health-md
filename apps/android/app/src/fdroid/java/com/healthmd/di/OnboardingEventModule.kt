package com.healthmd.di

import com.healthmd.domain.onboarding.NoOpOnboardingEventSink
import com.healthmd.domain.onboarding.OnboardingEventSink
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent

@Module
@InstallIn(SingletonComponent::class)
object OnboardingEventModule {
    @Provides
    fun provideOnboardingEventSink(): OnboardingEventSink = NoOpOnboardingEventSink
}
