package com.healthmd.domain.onboarding

enum class OnboardingStep {
    WELCOME,
    HEALTH_ACCESS,
    FOLDER_SETUP,
    ACCESS,
    READY,
}

/** Closed onboarding event surface. Distribution implementations decide whether events exist. */
interface OnboardingEventSink {
    suspend fun onboardingStarted()
    suspend fun stepViewed(step: OnboardingStep)
    suspend fun healthSkipped()
    suspend fun folderSelected()
    suspend fun folderSkipped()
    suspend fun continueFreeTapped()
    suspend fun purchaseTapped()
    suspend fun onboardingCompleted()
}

object NoOpOnboardingEventSink : OnboardingEventSink {
    override suspend fun onboardingStarted() = Unit
    override suspend fun stepViewed(step: OnboardingStep) = Unit
    override suspend fun healthSkipped() = Unit
    override suspend fun folderSelected() = Unit
    override suspend fun folderSkipped() = Unit
    override suspend fun continueFreeTapped() = Unit
    override suspend fun purchaseTapped() = Unit
    override suspend fun onboardingCompleted() = Unit
}
