package com.healthmd.data.drive

import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.hilt.work.HiltWorker
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.healthmd.HealthMdApplication
import com.healthmd.R
import com.healthmd.presentation.MainActivity
import com.healthmd.presentation.navigation.NavDestination
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject

@HiltWorker
class GoogleDriveRecoveryWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted params: WorkerParameters,
    private val runner: GoogleDriveDestinationRunner,
) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val operationId = inputData.getString(INPUT_OPERATION_ID) ?: return Result.failure()
        return when (val result = runner.resume(operationId)) {
            is GoogleDriveRunResult.Complete -> Result.success()
            is GoogleDriveRunResult.Stopped -> when {
                result.error == GoogleDriveErrorId.REAUTHORIZATION_REQUIRED -> {
                    notifyReauthorization(operationId)
                    Result.failure(workDataOf(OUTPUT_ERROR_ID to result.error.serialId))
                }
                result.retryable && runAttemptCount < MAX_ATTEMPTS -> Result.retry()
                else -> Result.failure(workDataOf(OUTPUT_ERROR_ID to result.error.serialId))
            }
        }
    }

    private fun notifyReauthorization(operationId: String) {
        val manager = applicationContext.getSystemService(NotificationManager::class.java)
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    applicationContext.getString(R.string.google_drive_reauthorization_title),
                    NotificationManager.IMPORTANCE_DEFAULT,
                ),
            )
        }
        val intent = Intent(applicationContext, MainActivity::class.java).apply {
            flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            putExtra(MainActivity.EXTRA_START_ROUTE, NavDestination.SETTINGS.route)
            putExtra(MainActivity.EXTRA_GOOGLE_DRIVE_OPERATION_ID, operationId)
        }
        val pendingIntent = PendingIntent.getActivity(
            applicationContext,
            operationId.hashCode(),
            intent,
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val notification = NotificationCompat.Builder(applicationContext, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_menu_upload)
            .setContentTitle(applicationContext.getString(R.string.google_drive_reauthorization_title))
            .setContentText(applicationContext.getString(R.string.google_drive_reauthorization_message))
            .setContentIntent(pendingIntent)
            .setAutoCancel(true)
            .build()
        manager.notify(operationId.hashCode(), notification)
    }

    companion object {
        const val INPUT_OPERATION_ID = "google_drive_operation_id"
        const val OUTPUT_ERROR_ID = "google_drive_error_id"
        private const val CHANNEL_ID = "google_drive_reauthorization"
        private const val MAX_ATTEMPTS = 5

        fun enqueue(context: Context, operationId: String) {
            val request = OneTimeWorkRequestBuilder<GoogleDriveRecoveryWorker>()
                .setInputData(workDataOf(INPUT_OPERATION_ID to operationId))
                .setConstraints(
                    Constraints.Builder().setRequiredNetworkType(NetworkType.CONNECTED).build(),
                )
                .build()
            WorkManager.getInstance(context).enqueueUniqueWork(
                "google-drive-operation-$operationId",
                ExistingWorkPolicy.KEEP,
                request,
            )
        }
    }
}
