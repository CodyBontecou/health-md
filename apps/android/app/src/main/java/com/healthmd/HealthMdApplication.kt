package com.healthmd

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import com.healthmd.R
import dagger.hilt.android.HiltAndroidApp
import timber.log.Timber
import javax.inject.Inject

@HiltAndroidApp
class HealthMdApplication : Application(), Configuration.Provider {

    @Inject
    lateinit var workerFactory: HiltWorkerFactory

    override val workManagerConfiguration: Configuration
        get() = Configuration.Builder()
            .setWorkerFactory(workerFactory)
            .build()

    override fun onCreate() {
        super.onCreate()
        initializeLogging()
        createNotificationChannels()
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
    }

    companion object {
        const val EXPORT_CHANNEL_ID = "health_scheduled_exports"
    }
}
