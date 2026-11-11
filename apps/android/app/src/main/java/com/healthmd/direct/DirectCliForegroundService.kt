package com.healthmd.direct

import android.annotation.SuppressLint
import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.content.res.Configuration
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.healthmd.R
import com.healthmd.presentation.MainActivity
import com.healthmd.presentation.navigation.NavDestination
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

@AndroidEntryPoint
class DirectCliForegroundService : Service() {
    @Inject lateinit var coordinator: DirectCliCoordinator

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var operation: Job? = null
    @Volatile private var stopRequested = false
    private val notificationLock = Any()

    override fun onCreate() {
        super.onCreate()
        coordinator.resetSession()
        createNotificationChannel(this)
        startDirectForeground(
            notification(
                getString(R.string.direct_cli_notification_waiting),
                indeterminate = true,
            ),
        )
        scope.launch {
            coordinator.state.collectLatest(::updateNotification)
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            stopRequested = true
            coordinator.cancelActive()
            operation?.cancel()
            coordinator.reportDisconnected()
            removeDirectForegroundNotification()
            stopSelf(startId)
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_FORGET) {
            stopRequested = true
            coordinator.cancelActive()
            operation?.cancel()
            removeDirectForegroundNotification()
            operation = scope.launch {
                try {
                    coordinator.forget()
                } finally {
                    stopSelf(startId)
                }
            }
            return START_NOT_STICKY
        }
        if (operation?.isActive == true) {
            val state = coordinator.state.value
            if (state is DirectCliConnectionState.Completed || state is DirectCliConnectionState.Failed) {
                operation?.cancel()
            } else {
                return START_NOT_STICKY
            }
        }
        stopRequested = false
        operation = scope.launch {
            try {
                when (intent?.action) {
                    ACTION_PAIR -> coordinator.pair(
                        host = intent.getStringExtra(EXTRA_HOST).orEmpty(),
                        port = intent.getIntExtra(EXTRA_PORT, com.healthmd.direct.protocol.DIRECT_PORT),
                        pairingCode = intent.getStringExtra(EXTRA_PAIRING_CODE).orEmpty(),
                    )
                    ACTION_CONNECT -> coordinator.connectAndServe()
                }
            } catch (error: CancellationException) {
                if (!stopRequested) throw error
                coordinator.reportDisconnected()
            } catch (_: Throwable) {
                if (stopRequested) {
                    coordinator.reportDisconnected()
                } else {
                    val failure = if (intent?.action == ACTION_PAIR) {
                        DirectCliFailure.PAIRING_FAILED
                    } else {
                        DirectCliFailure.CONNECTION_FAILED
                    }
                    coordinator.reportFailure(failure)
                    updateNotification(DirectCliConnectionState.Failed(failure))
                }
            } finally {
                stopSelf(startId)
            }
        }
        return START_NOT_STICKY
    }

    override fun onDestroy() {
        coordinator.cancelActive()
        operation?.cancel()
        coordinator.reportDisconnected()
        scope.cancel()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onConfigurationChanged(newConfig: Configuration) {
        super.onConfigurationChanged(newConfig)
        createNotificationChannel(this)
        updateNotification(coordinator.state.value)
    }

    override fun onTimeout(startId: Int, fgsType: Int) {
        coordinator.cancelActive()
        operation?.cancel()
        coordinator.reportFailure(DirectCliFailure.SESSION_TIMEOUT)
        stopSelf(startId)
    }

    private fun updateNotification(state: DirectCliConnectionState) {
        synchronized(notificationLock) {
            val manager = getSystemService(NotificationManager::class.java)
            if (stopRequested) return@synchronized
            val notification = when (state) {
                DirectCliConnectionState.Idle -> notification(
                    getString(R.string.direct_cli_notification_idle),
                )
                DirectCliConnectionState.Pairing -> notification(
                    getString(R.string.direct_cli_notification_pairing),
                    true,
                )
                DirectCliConnectionState.WaitingForCli -> notification(
                    getString(R.string.direct_cli_notification_connecting),
                    true,
                )
                is DirectCliConnectionState.Connected -> notification(
                    getString(R.string.direct_cli_status_connected, state.listenerName),
                    true,
                )
                is DirectCliConnectionState.Transferring -> {
                    val progress = DirectCliOngoingPresentation.percent(state)
                    notification(
                        getString(R.string.direct_cli_notification_transferring),
                        progress = progress,
                    )
                }
                is DirectCliConnectionState.Completed -> notification(
                    completionText(state.outcome),
                    finished = state.outcome == DirectCliCompletion.ExportCompleted,
                )
                is DirectCliConnectionState.Failed -> notification(failureText(state.reason))
            }
            manager.notify(NOTIFICATION_ID, promoteOngoing(notification, state))
        }
    }

    private fun removeDirectForegroundNotification() {
        // A publication already in progress must retire before final removal.
        // Queued state emissions cannot recreate the notification after stop.
        synchronized(notificationLock) {
            stopRequested = true
            stopForeground(STOP_FOREGROUND_REMOVE)
            getSystemService(NotificationManager::class.java).cancel(NOTIFICATION_ID)
        }
    }

    private fun notification(
        text: String,
        indeterminate: Boolean = false,
        progress: Int? = null,
        finished: Boolean = false,
    ): Notification {
        val openApp = PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val stop = PendingIntent.getService(
            this,
            1,
            Intent(this, DirectCliForegroundService::class.java).setAction(ACTION_STOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        return NotificationCompat.Builder(this, CHANNEL_ID)
            .setSmallIcon(R.drawable.ic_launcher_foreground)
            .setContentTitle(getString(R.string.direct_cli_notification_title))
            .setContentText(text)
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .apply {
                if (finished) {
                    // A finished export leads to the Archive, where the new days now show.
                    val openArchive = PendingIntent.getActivity(
                        this@DirectCliForegroundService,
                        2,
                        Intent(this@DirectCliForegroundService, MainActivity::class.java)
                            .addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP)
                            .putExtra(MainActivity.EXTRA_START_ROUTE, NavDestination.ARCHIVE.route),
                        PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
                    )
                    addAction(0, getString(R.string.notification_open_archive), openArchive)
                }
            }
            // Disconnect stays available in every state so the session can always be ended.
            .addAction(0, getString(R.string.direct_cli_disconnect), stop)
            .apply {
                when {
                    progress != null -> setProgress(100, progress, false)
                    indeterminate -> setProgress(0, 0, true)
                }
            }
            .build()
    }

    private fun completionText(outcome: DirectCliCompletion): String = when (outcome) {
        is DirectCliCompletion.Paired -> getString(
            R.string.direct_cli_status_paired,
            outcome.listenerName,
        )
        DirectCliCompletion.SessionFinished -> getString(
            R.string.direct_cli_status_session_finished,
        )
        DirectCliCompletion.ExportCompleted -> getString(
            R.string.direct_cli_status_export_completed,
        )
        DirectCliCompletion.ExportCancelled -> getString(
            R.string.direct_cli_status_export_cancelled,
        )
    }

    private fun failureText(reason: DirectCliFailure): String = when (reason) {
        DirectCliFailure.PAIRING_FAILED,
        DirectCliFailure.CONNECTION_FAILED -> getString(R.string.direct_cli_failure_connection)
        DirectCliFailure.SESSION_TIMEOUT -> getString(R.string.direct_cli_failure_timeout)
        DirectCliFailure.QUOTA_EXHAUSTED -> getString(R.string.direct_cli_failure_quota)
        DirectCliFailure.PROVIDER_RANGE_REQUIRED -> getString(
            R.string.direct_cli_failure_provider_range,
        )
        DirectCliFailure.PROFILE_NOT_FOUND -> getString(
            R.string.direct_cli_failure_profile_not_found,
        )
        DirectCliFailure.SOURCE_UNAVAILABLE -> getString(
            R.string.direct_cli_failure_source_unavailable,
        )
        DirectCliFailure.HEALTH_ACCESS_REQUIRED -> getString(
            R.string.direct_cli_failure_health_access,
        )
        DirectCliFailure.DEVICE_LOCKED -> getString(R.string.direct_cli_failure_device_locked)
        DirectCliFailure.HISTORICAL_ACCESS_REQUIRED -> getString(
            R.string.direct_cli_failure_historical_access,
        )
        DirectCliFailure.GENERATED_FILE_LIMIT -> getString(
            R.string.direct_cli_failure_file_limit,
        )
        DirectCliFailure.SPOOL_MISSING -> getString(R.string.direct_cli_failure_spool_missing)
        DirectCliFailure.EXPORT_FAILED -> getString(R.string.direct_cli_failure_export)
    }

    /**
     * On Android 16+, requests a promoted ongoing notification so the status bar shows a chip:
     * CLI while connecting, the transfer percentage, then Done. Earlier versions are unchanged.
     */
    private fun promoteOngoing(notification: Notification, state: DirectCliConnectionState): Notification {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.BAKLAVA) return notification
        val chip = when (DirectCliOngoingPresentation.stage(state)) {
            DirectCliOngoingStage.CONNECTING -> getString(R.string.direct_cli_chip_connecting)
            DirectCliOngoingStage.TRANSFERRING -> java.text.NumberFormat.getPercentInstance(
                resources.configuration.locales[0],
            ).format(DirectCliOngoingPresentation.percent(state as DirectCliConnectionState.Transferring) / 100.0)
            DirectCliOngoingStage.COMPLETED -> getString(R.string.direct_cli_chip_done)
            DirectCliOngoingStage.IDLE, DirectCliOngoingStage.FAILED -> return notification
        }
        return Notification.Builder.recoverBuilder(this, notification)
            .setShortCriticalText(chip)
            .addExtras(android.os.Bundle().apply { putBoolean(EXTRA_REQUEST_PROMOTED_ONGOING, true) })
            .build()
    }

    // Declared as dataSync on DirectCliForegroundService in the shared manifest.
    @SuppressLint("ForegroundServiceType")
    private fun startDirectForeground(notification: Notification) {
        ServiceCompat.startForeground(
            this,
            NOTIFICATION_ID,
            notification,
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC
            } else {
                0
            },
        )
    }

    companion object {
        private const val CHANNEL_ID = "healthmd_direct_cli"
        /** Notification.EXTRA_REQUEST_PROMOTED_ONGOING (API 36); not yet in the compile SDK stubs. */
        private const val EXTRA_REQUEST_PROMOTED_ONGOING = "android.requestPromotedOngoing"
        private const val NOTIFICATION_ID = 2_647
        private const val ACTION_PAIR = "com.healthmd.direct.PAIR"
        private const val ACTION_CONNECT = "com.healthmd.direct.CONNECT"
        private const val ACTION_STOP = "com.healthmd.direct.STOP"
        private const val ACTION_FORGET = "com.healthmd.direct.FORGET"
        private const val EXTRA_HOST = "host"
        private const val EXTRA_PORT = "port"
        private const val EXTRA_PAIRING_CODE = "pairing_code"

        fun createNotificationChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val channel = NotificationChannel(
                CHANNEL_ID,
                context.getString(R.string.direct_cli_notification_channel_name),
                NotificationManager.IMPORTANCE_LOW,
            ).apply {
                description = context.getString(R.string.direct_cli_notification_channel_description)
            }
            context.getSystemService(NotificationManager::class.java)
                .createNotificationChannel(channel)
        }

        fun pair(context: Context, host: String, port: Int, pairingCode: String) {
            val intent = Intent(context, DirectCliForegroundService::class.java)
                .setAction(ACTION_PAIR)
                .putExtra(EXTRA_HOST, host)
                .putExtra(EXTRA_PORT, port)
                .putExtra(EXTRA_PAIRING_CODE, pairingCode)
            context.startForegroundService(intent)
        }

        fun connect(context: Context) {
            context.startForegroundService(
                Intent(context, DirectCliForegroundService::class.java).setAction(ACTION_CONNECT),
            )
        }

        fun stop(context: Context) {
            context.startService(
                Intent(context, DirectCliForegroundService::class.java).setAction(ACTION_STOP),
            )
        }

        fun forget(context: Context) {
            context.startForegroundService(
                Intent(context, DirectCliForegroundService::class.java).setAction(ACTION_FORGET),
            )
        }
    }
}
