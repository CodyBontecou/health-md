package com.healthmd.direct

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.app.Service
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.os.Build
import android.os.IBinder
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import com.healthmd.R
import com.healthmd.presentation.MainActivity
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

    override fun onCreate() {
        super.onCreate()
        coordinator.resetSession()
        createNotificationChannel()
        startDirectForeground(notification("Waiting for Health.md CLI", indeterminate = true))
        scope.launch {
            coordinator.state.collectLatest { state ->
                updateNotification(state)
                if (state is DirectCliConnectionState.Completed || state is DirectCliConnectionState.Failed) {
                    stopSelf()
                }
            }
        }
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_STOP) {
            coordinator.cancelActive()
            operation?.cancel()
            stopSelf()
            return START_NOT_STICKY
        }
        if (intent?.action == ACTION_FORGET) {
            coordinator.cancelActive()
            operation?.cancel()
            operation = scope.launch {
                coordinator.forget()
                stopSelf()
            }
            return START_NOT_STICKY
        }
        if (operation?.isActive == true) return START_NOT_STICKY
        operation = scope.launch {
            try {
                when (intent?.action) {
                    ACTION_PAIR -> coordinator.pair(
                        host = intent.getStringExtra(EXTRA_HOST).orEmpty(),
                        port = intent.getIntExtra(EXTRA_PORT, com.healthmd.direct.protocol.DIRECT_PORT),
                        pairingCode = intent.getStringExtra(EXTRA_PAIRING_CODE).orEmpty(),
                    )
                    ACTION_CONNECT -> coordinator.connectAndServe()
                    else -> stopSelf()
                }
            } catch (_: CancellationException) {
                throw CancellationException()
            } catch (_: Throwable) {
                val message = "Could not connect to the Health.md CLI. Confirm it is listening and try again."
                coordinator.reportFailure(message)
                updateNotification(DirectCliConnectionState.Failed(message))
                stopSelf()
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

    override fun onTimeout(startId: Int, fgsType: Int) {
        coordinator.cancelActive()
        operation?.cancel()
        coordinator.reportFailure("The Direct CLI session reached Android's time limit.")
        stopSelf(startId)
    }

    private fun updateNotification(state: DirectCliConnectionState) {
        val notification = when (state) {
            DirectCliConnectionState.Idle -> notification("Direct CLI is idle")
            DirectCliConnectionState.Pairing -> notification("Pairing with Health.md CLI", true)
            DirectCliConnectionState.WaitingForCli -> notification("Connecting to Health.md CLI", true)
            is DirectCliConnectionState.Connected -> notification("Connected to ${state.listenerName}", true)
            is DirectCliConnectionState.Transferring -> {
                val progress = if (state.totalBytes > 0) {
                    ((state.completedBytes * 100) / state.totalBytes).toInt().coerceIn(0, 100)
                } else {
                    0
                }
                notification("Transferring Android health export", progress = progress)
            }
            is DirectCliConnectionState.Completed -> notification(state.message)
            is DirectCliConnectionState.Failed -> notification(state.message)
        }
        getSystemService(NotificationManager::class.java).notify(NOTIFICATION_ID, notification)
    }

    private fun notification(
        text: String,
        indeterminate: Boolean = false,
        progress: Int? = null,
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
            .setContentTitle("Health.md Direct CLI")
            .setContentText(text)
            .setContentIntent(openApp)
            .setOngoing(true)
            .setOnlyAlertOnce(true)
            .addAction(0, "Disconnect", stop)
            .apply {
                when {
                    progress != null -> setProgress(100, progress, false)
                    indeterminate -> setProgress(0, 0, true)
                }
            }
            .build()
    }

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

    private fun createNotificationChannel() {
        val channel = NotificationChannel(
            CHANNEL_ID,
            "Direct CLI exports",
            NotificationManager.IMPORTANCE_LOW,
        ).apply {
            description = "Encrypted direct export connection and transfer progress"
        }
        getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    companion object {
        private const val CHANNEL_ID = "healthmd_direct_cli"
        private const val NOTIFICATION_ID = 2_647
        private const val ACTION_PAIR = "com.healthmd.direct.PAIR"
        private const val ACTION_CONNECT = "com.healthmd.direct.CONNECT"
        private const val ACTION_STOP = "com.healthmd.direct.STOP"
        private const val ACTION_FORGET = "com.healthmd.direct.FORGET"
        private const val EXTRA_HOST = "host"
        private const val EXTRA_PORT = "port"
        private const val EXTRA_PAIRING_CODE = "pairing_code"

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
