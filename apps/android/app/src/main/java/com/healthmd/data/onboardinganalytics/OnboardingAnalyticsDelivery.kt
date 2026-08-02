package com.healthmd.data.onboardinganalytics

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
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject
import javax.inject.Singleton

interface OnboardingAnalyticsWorkScheduler {
    fun enqueueUpload()
}

@Singleton
class WorkManagerOnboardingAnalyticsScheduler @Inject constructor(
    @ApplicationContext context: Context,
) : OnboardingAnalyticsWorkScheduler {
    private val workManager by lazy(LazyThreadSafetyMode.SYNCHRONIZED) {
        WorkManager.getInstance(context)
    }

    override fun enqueueUpload() {
        val request = OneTimeWorkRequestBuilder<OnboardingAnalyticsWorker>()
            .setConstraints(
                Constraints.Builder()
                    .setRequiredNetworkType(NetworkType.CONNECTED)
                    .build()
            )
            .setBackoffCriteria(BackoffPolicy.EXPONENTIAL, 30, TimeUnit.SECONDS)
            .addTag(WORK_NAME)
            .build()
        // Chain a follow-up request instead of dropping enqueues that race a running worker.
        // Each worker drains the full bounded queue, so chained requests usually become no-ops.
        workManager.enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.APPEND_OR_REPLACE, request)
    }

    companion object {
        const val WORK_NAME = "onboarding-analytics-upload"
    }
}

enum class OnboardingAnalyticsDeliveryResult {
    DELIVERED,
    NOTHING_PENDING,
    PERMANENT_FAILURE,
    RETRY,
    NOT_CONFIGURED,
}

class OnboardingAnalyticsDelivery @Inject constructor(
    private val store: OnboardingAnalyticsStore,
    private val reporter: OnboardingAnalyticsReporter,
) {
    suspend fun deliverPending(): OnboardingAnalyticsDeliveryResult {
        var deliveredAny = false
        var rejectedAny = false
        repeat(MAX_BATCHES_PER_RUN) {
            val batch = store.loadBatch(BATCH_SIZE)
                ?: return when {
                    rejectedAny -> OnboardingAnalyticsDeliveryResult.PERMANENT_FAILURE
                    deliveredAny -> OnboardingAnalyticsDeliveryResult.DELIVERED
                    else -> OnboardingAnalyticsDeliveryResult.NOTHING_PENDING
                }
            val eventIds = batch.events.mapTo(mutableSetOf(), OnboardingAnalyticsEvent::eventId)
            val result = try {
                reporter.report(OnboardingAnalyticsEnvelope(batch.installId, batch.events))
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                OnboardingAnalyticsReportResult.RetryableFailure()
            }

            when (result) {
                is OnboardingAnalyticsReportResult.Delivered -> {
                    store.remove(eventIds)
                    deliveredAny = true
                }
                is OnboardingAnalyticsReportResult.PermanentFailure -> {
                    // The endpoint rejected this exact allowlisted batch. Drop it so one bad event
                    // cannot keep the bounded queue blocked forever.
                    store.remove(eventIds)
                    rejectedAny = true
                }
                is OnboardingAnalyticsReportResult.RetryableFailure ->
                    return OnboardingAnalyticsDeliveryResult.RETRY
                OnboardingAnalyticsReportResult.NotConfigured ->
                    return OnboardingAnalyticsDeliveryResult.NOT_CONFIGURED
            }
        }
        return if (rejectedAny) {
            OnboardingAnalyticsDeliveryResult.PERMANENT_FAILURE
        } else {
            OnboardingAnalyticsDeliveryResult.DELIVERED
        }
    }

    private companion object {
        const val BATCH_SIZE = 20
        const val MAX_BATCHES_PER_RUN = 3
    }
}

@HiltWorker
class OnboardingAnalyticsWorker @AssistedInject constructor(
    @Assisted appContext: Context,
    @Assisted workerParams: WorkerParameters,
    private val delivery: OnboardingAnalyticsDelivery,
) : CoroutineWorker(appContext, workerParams) {
    override suspend fun doWork(): Result = when (delivery.deliverPending()) {
        OnboardingAnalyticsDeliveryResult.RETRY -> Result.retry()
        OnboardingAnalyticsDeliveryResult.DELIVERED,
        OnboardingAnalyticsDeliveryResult.NOTHING_PENDING,
        OnboardingAnalyticsDeliveryResult.PERMANENT_FAILURE,
        OnboardingAnalyticsDeliveryResult.NOT_CONFIGURED -> Result.success()
    }
}

/** Reschedules a durably queued event after a process restart without delaying app startup. */
@Singleton
class OnboardingAnalyticsInitializer @Inject constructor(
    private val store: OnboardingAnalyticsStore,
    private val scheduler: OnboardingAnalyticsWorkScheduler,
) {
    private val started = AtomicBoolean(false)
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    fun start() {
        if (!started.compareAndSet(false, true)) return
        scope.launch {
            try {
                if (store.hasPendingEvents()) scheduler.enqueueUpload()
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                // Analytics must never affect startup and throwable details are intentionally omitted.
            }
        }
    }
}
