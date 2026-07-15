package com.healthmd.di

import com.healthmd.BuildConfig
import com.healthmd.data.attribution.CampaignAttributionAppInfo
import com.healthmd.data.attribution.CampaignAttributionClock
import com.healthmd.data.attribution.CampaignAttributionConfig
import com.healthmd.data.attribution.CampaignAttributionHttpClient
import com.healthmd.data.attribution.CampaignAttributionReporter
import com.healthmd.data.attribution.CampaignAttributionRetryDelay
import com.healthmd.data.attribution.CampaignAttributionStore
import com.healthmd.data.attribution.CampaignAttributionUuidGenerator
import com.healthmd.data.attribution.CampaignAttributionWorkScheduler
import com.healthmd.data.attribution.DataStoreCampaignAttributionStore
import com.healthmd.data.attribution.DefaultCampaignAttributionRetryDelay
import com.healthmd.data.attribution.InstallReferrerSource
import com.healthmd.data.attribution.OkHttpCampaignAttributionReporter
import com.healthmd.data.attribution.PlayInstallReferrerSource
import com.healthmd.data.attribution.WorkManagerCampaignAttributionScheduler
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import java.time.Instant
import java.util.UUID
import java.util.concurrent.TimeUnit
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object AttributionModule {
    @Provides
    @Singleton
    fun provideInstallReferrerSource(source: PlayInstallReferrerSource): InstallReferrerSource = source

    @Provides
    @Singleton
    fun provideCampaignAttributionStore(
        store: DataStoreCampaignAttributionStore,
    ): CampaignAttributionStore = store

    @Provides
    @Singleton
    fun provideCampaignAttributionReporter(
        reporter: OkHttpCampaignAttributionReporter,
    ): CampaignAttributionReporter = reporter

    @Provides
    @Singleton
    fun provideCampaignAttributionScheduler(
        scheduler: WorkManagerCampaignAttributionScheduler,
    ): CampaignAttributionWorkScheduler = scheduler

    @Provides
    @Singleton
    fun provideCampaignAttributionRetryDelay(
        delay: DefaultCampaignAttributionRetryDelay,
    ): CampaignAttributionRetryDelay = delay

    @Provides
    @Singleton
    fun provideCampaignAttributionUuidGenerator(): CampaignAttributionUuidGenerator =
        CampaignAttributionUuidGenerator { UUID.randomUUID().toString() }

    @Provides
    @Singleton
    fun provideCampaignAttributionClock(): CampaignAttributionClock =
        CampaignAttributionClock { Instant.now() }

    @Provides
    @Singleton
    fun provideCampaignAttributionAppInfo(): CampaignAttributionAppInfo =
        CampaignAttributionAppInfo(
            versionName = BuildConfig.VERSION_NAME,
            buildNumber = BuildConfig.VERSION_CODE.toString(),
        )

    @Provides
    @Singleton
    fun provideCampaignAttributionConfig(): CampaignAttributionConfig =
        CampaignAttributionConfig(
            endpointUrl = BuildConfig.CAMPAIGN_ATTRIBUTION_ENDPOINT_URL,
            ingestToken = BuildConfig.CAMPAIGN_ATTRIBUTION_INGEST_TOKEN.takeIf { it.isNotBlank() },
            isDebug = BuildConfig.DEBUG,
        )

    @Provides
    @Singleton
    @CampaignAttributionHttpClient
    fun provideCampaignAttributionHttpClient(): OkHttpClient = OkHttpClient.Builder()
        .connectTimeout(10, TimeUnit.SECONDS)
        .readTimeout(15, TimeUnit.SECONDS)
        .writeTimeout(15, TimeUnit.SECONDS)
        .callTimeout(20, TimeUnit.SECONDS)
        .followRedirects(false)
        .followSslRedirects(false)
        .retryOnConnectionFailure(false)
        // BridgeInterceptor adds a generic okhttp User-Agent. Remove it at the network layer so
        // campaign ingestion receives only the explicit headers in the documented contract.
        .addNetworkInterceptor { chain ->
            val request = chain.request().newBuilder()
                .removeHeader("User-Agent")
                .build()
            chain.proceed(request)
        }
        .build()
}
