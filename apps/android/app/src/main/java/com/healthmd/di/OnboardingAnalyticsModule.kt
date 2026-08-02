package com.healthmd.di

import com.healthmd.BuildConfig
import com.healthmd.data.onboardinganalytics.DataStoreOnboardingAnalyticsStatePersistence
import com.healthmd.data.onboardinganalytics.DurableOnboardingAnalyticsStore
import com.healthmd.data.onboardinganalytics.OkHttpOnboardingAnalyticsReporter
import com.healthmd.data.onboardinganalytics.OnboardingAnalyticsAppInfo
import com.healthmd.data.onboardinganalytics.OnboardingAnalyticsConfig
import com.healthmd.data.onboardinganalytics.OnboardingAnalyticsEventFactory
import com.healthmd.data.onboardinganalytics.OnboardingAnalyticsHttpClient
import com.healthmd.data.onboardinganalytics.OnboardingAnalyticsReporter
import com.healthmd.data.onboardinganalytics.OnboardingAnalyticsStatePersistence
import com.healthmd.data.onboardinganalytics.OnboardingAnalyticsStore
import com.healthmd.data.onboardinganalytics.OnboardingAnalyticsUuidGenerator
import com.healthmd.data.onboardinganalytics.OnboardingAnalyticsWorkScheduler
import com.healthmd.data.onboardinganalytics.WorkManagerOnboardingAnalyticsScheduler
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object OnboardingAnalyticsModule {
    @Provides
    @Singleton
    internal fun provideOnboardingAnalyticsPersistence(
        persistence: DataStoreOnboardingAnalyticsStatePersistence,
    ): OnboardingAnalyticsStatePersistence = persistence

    @Provides
    @Singleton
    fun provideOnboardingAnalyticsStore(
        store: DurableOnboardingAnalyticsStore,
    ): OnboardingAnalyticsStore = store

    @Provides
    @Singleton
    fun provideOnboardingAnalyticsReporter(
        reporter: OkHttpOnboardingAnalyticsReporter,
    ): OnboardingAnalyticsReporter = reporter

    @Provides
    @Singleton
    fun provideOnboardingAnalyticsScheduler(
        scheduler: WorkManagerOnboardingAnalyticsScheduler,
    ): OnboardingAnalyticsWorkScheduler = scheduler

    @Provides
    @Singleton
    fun provideOnboardingAnalyticsUuidGenerator(): OnboardingAnalyticsUuidGenerator =
        OnboardingAnalyticsUuidGenerator { UUID.randomUUID().toString() }

    @Provides
    @Singleton
    fun provideOnboardingAnalyticsEventFactory(
        uuidGenerator: OnboardingAnalyticsUuidGenerator,
    ): OnboardingAnalyticsEventFactory = OnboardingAnalyticsEventFactory(
        appInfo = OnboardingAnalyticsAppInfo(
            appVersion = BuildConfig.VERSION_NAME,
            buildNumber = BuildConfig.VERSION_CODE.toString(),
        ),
        uuidGenerator = uuidGenerator,
    )

    @Provides
    @Singleton
    fun provideOnboardingAnalyticsConfig(): OnboardingAnalyticsConfig =
        OnboardingAnalyticsConfig(
            endpointUrl = BuildConfig.ONBOARDING_ANALYTICS_ENDPOINT_URL,
            isDebug = BuildConfig.DEBUG,
        )

    @Provides
    @Singleton
    @OnboardingAnalyticsHttpClient
    fun provideOnboardingAnalyticsHttpClient(): OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .callTimeout(20, TimeUnit.SECONDS)
        .followRedirects(false)
        .followSslRedirects(false)
        .retryOnConnectionFailure(false)
        .addNetworkInterceptor { chain ->
            chain.proceed(chain.request().newBuilder().removeHeader("User-Agent").build())
        }
        .build()
}
