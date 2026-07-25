package com.healthmd.data.attribution

import android.content.Context
import androidx.hilt.work.HiltWorker
import androidx.work.BackoffPolicy
import androidx.work.Constraints
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.NetworkType
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import dagger.assisted.Assisted
import dagger.assisted.AssistedInject
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.concurrent.TimeUnit
import javax.inject.Inject
import javax.inject.Singleton

interface CampaignAttributionWorkScheduler {
    fun enqueueUpload()
}

@Singleton
class WorkManagerCampaignAttributionScheduler @Inject constructor(
    @ApplicationContext context: Context,
) : CampaignAttributionWorkScheduler {
    private val workManager by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        WorkManager.getInstance(context)
    }

    override fun enqueueUpload() {
        val request = OneTimeWorkRequestBuilder<CampaignAttributionWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .addTag(WORK_NAME)
            .build()
        workManager.enqueueUniqueWork(
            WORK_NAME,
            ExistingWorkPolicy.KEEP,
            request,
        )
    }

    companion object {
        const val WORK_NAME = "campaign-attribution-upload"
    }
}

@HiltWorker
class CampaignAttributionWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val delivery: CampaignAttributionDelivery,
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): Result = when (delivery.deliverPending()) {
        CampaignAttributionDeliveryResult.RETRY -> Result.retry()
        CampaignAttributionDeliveryResult.PERMANENT_FAILURE -> Result.failure()
        CampaignAttributionDeliveryResult.DELIVERED,
        CampaignAttributionDeliveryResult.NOTHING_PENDING,
        CampaignAttributionDeliveryResult.NOT_CONFIGURED -> Result.success()
    }
}
