package com.healthmd

import android.app.Application
import android.app.NotificationChannel
import android.app.NotificationManager
import android.os.Build
import androidx.hilt.work.HiltWorkerFactory
import androidx.work.Configuration
import dagger.hilt.android.HiltAndroidApp
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
        createNotificationChannels()
    }

    private fun createNotificationChannels() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val exportChannel = NotificationChannel(
                EXPORT_CHANNEL_ID,
                "Export Status",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Notifications about health data export status"
            }

            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(exportChannel)
        }
    }

    companion object {
        const val EXPORT_CHANNEL_ID = "health_export_status"
    }
}
