package com.healthmd

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.content.res.Configuration as AndroidConfiguration
import android.os.Build
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import com.healthmd.R
import com.healthmd.data.attribution.CampaignAttributionInitializer
import com.healthmd.data.export.ExportAwakeCoordinator
import com.healthmd.data.onboardinganalytics.OnboardingAnalyticsInitializer
import com.healthmd.data.scheduler.ExportWorker
import com.healthmd.direct.DirectCliForegroundService
import com.healthmd.direct.DirectCliJobStore
import com.healthmd.widget.glance.HealthWidgetLocaleRefresher
import dagger.hilt.android.HiltAndroidApp
import javax.inject.Inject
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import timber.log.Timber

@HiltAndroidApp
class HealthMdApplication : Application(), Configuration.Provider {

    private val configurationRefreshScope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private var configurationRefreshJob: Job? = null
    private var resourceLocaleTags: String = ""
    private var resourceNightMode: Int = AndroidConfiguration.UI_MODE_NIGHT_UNDEFINED

    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    @Inject
    lateinit var campaignAttributionInitializer: CampaignAttributionInitializer

    @Inject
    lateinit var onboardingAnalyticsInitializer: OnboardingAnalyticsInitializer

    @Inject
    lateinit var directCliJobStore: DirectCliJobStore

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()

    override fun onCreate() {
        super.onCreate()
        resourceLocaleTags = resources.configuration.locales.toLanguageTags()
        resourceNightMode = resources.configuration.uiMode and
            AndroidConfiguration.UI_MODE_NIGHT_MASK
        initializeLogging()
        ExportAwakeCoordinator.shared.initialize(this)
        createNotificationChannels()
        campaignAttributionInitializer.start()
        onboardingAnalyticsInitializer.start()
        directCliJobStore.sweepExpired()
    }

    override fun onConfigurationChanged(newConfig: AndroidConfiguration) {
        super.onConfigurationChanged(newConfig)
        val newLocaleTags = resources.configuration.locales.toLanguageTags()
        val newNightMode = newConfig.uiMode and AndroidConfiguration.UI_MODE_NIGHT_MASK
        val localeChanged = newLocaleTags != resourceLocaleTags
        val appearanceChanged = newNightMode != resourceNightMode
        if (!localeChanged && !appearanceChanged) return
        resourceLocaleTags = newLocaleTags
        resourceNightMode = newNightMode

        if (localeChanged) {
            // Existing channels keep their IDs and behavior while their display copy is refreshed.
            createNotificationChannels()
            // Completed notifications cannot be reconstructed safely; remove stale-locale copy.
            ExportWorker.clearLocalizedResultNotifications(this)
        }
        configurationRefreshJob?.cancel()
        configurationRefreshJob = configurationRefreshScope.launch {
            runCatching {
                if (localeChanged) {
                    HealthWidgetLocaleRefresher.rerenderForCurrentLocale(this@HealthMdApplication)
                } else {
                    HealthWidgetLocaleRefresher.rerenderAll(this@HealthMdApplication)
                }
            }.onFailure { error ->
                Timber.w(error, "Unable to rerender health widgets after a configuration change")
            }
        }
    }

    private fun initializeLogging() {
        try {
            val buildConfigClass = Class.forName("com.healthmd.BuildConfig")
            val debugField = buildConfigClass.getField("DEBUG")
            val isDebug = debugField.getBoolean(null)
            if (isDebug) {
                Timber.plant(Timber.DebugTree())
            }
        } catch (e: Exception) {
            // If BuildConfig isn't available, still plant the tree
            Timber.plant(Timber.DebugTree())
        }
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val exportChannel = NotificationChannel(
                EXPORT_CHANNEL_ID,
                getString(R.string.notification_channel_scheduled_exports_name),
                NotificationManager.IMPORTANCE_DEFAULT,
            ).apply {
                description = getString(R.string.notification_channel_scheduled_exports_description)
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(exportChannel)
        }
        DirectCliForegroundService.createNotificationChannel(this)
    }

    companion object {
        const val EXPORT_CHANNEL_ID = "health_scheduled_exports"
    }
}
