package com.healthmd.data.billing

import android.Manifest
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
import android.content.Context
import android.content.Intent
import android.content.pm.PackageManager
import android.os.Build
import androidx.core.app.NotificationCompat
import androidx.core.app.NotificationManagerCompat
import androidx.core.content.ContextCompat
import androidx.work.CoroutineWorker
import androidx.work.ExistingWorkPolicy
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import androidx.work.WorkerParameters
import androidx.work.workDataOf
import com.healthmd.R
import com.healthmd.presentation.MainActivity
import timber.log.Timber
import java.text.DateFormat
import java.util.Date
import java.util.concurrent.TimeUnit

/**
 * The reminder onboarding promises in its trial timeline ("Day 5 · Reminder before you're
 * charged"). It fires two days before a seven-day free trial ends. Play Billing does not report
 * trial dates on the device, so the trial is anchored to the purchase time of a trial offer.
 * Scheduling replaces any pending reminder; a snapshot that no longer renews cancels it.
 */
object TrialReminder {
    const val TRIAL_DAYS = 7
    private const val DAY_MILLIS = 24 * 60 * 60 * 1000L
    const val LEAD_MILLIS = 2 * DAY_MILLIS
    private const val WORK_NAME = "healthmd-trial-billing-reminder"
    const val CHANNEL_ID = "healthmd_subscription_reminders"
    private const val NOTIFICATION_ID = 0x7417
    internal const val KEY_TRIAL_END = "trial_end_millis"
    internal const val KEY_PRICE = "price_text"

    fun trialEndMillis(purchaseTimeMillis: Long): Long = purchaseTimeMillis + TRIAL_DAYS * DAY_MILLIS

    /**
     * When the reminder fires, or null when the trial is about to end anyway. A trial already
     * inside the lead time is reminded within a minute.
     */
    fun fireAtMillis(trialEndMillis: Long, nowMillis: Long): Long? {
        if (trialEndMillis <= nowMillis + 60 * 60 * 1000L) return null
        return maxOf(trialEndMillis - LEAD_MILLIS, nowMillis + 60 * 1000L)
    }

    fun schedule(context: Context, purchaseTimeMillis: Long, priceText: String?, nowMillis: Long = System.currentTimeMillis()) {
        val end = trialEndMillis(purchaseTimeMillis)
        val fireAt = fireAtMillis(end, nowMillis) ?: return cancel(context)
        val request = OneTimeWorkRequestBuilder<TrialReminderWorker>()
            .setInitialDelay(fireAt - nowMillis, TimeUnit.MILLISECONDS)
            .setInputData(workDataOf(KEY_TRIAL_END to end, KEY_PRICE to priceText))
            .build()
        WorkManager.getInstance(context).enqueueUniqueWork(WORK_NAME, ExistingWorkPolicy.REPLACE, request)
    }

    fun cancel(context: Context) {
        WorkManager.getInstance(context).cancelUniqueWork(WORK_NAME)
    }

    fun body(context: Context, trialEndMillis: Long, priceText: String?): String {
        val date = DateFormat.getDateInstance(DateFormat.MEDIUM).format(Date(trialEndMillis))
        return if (priceText.isNullOrBlank()) {
            context.getString(R.string.trial_reminder_body_no_price, date)
        } else {
            context.getString(R.string.trial_reminder_body, date, priceText)
        }
    }

    fun ensureChannel(context: Context) {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
        val channel = NotificationChannel(
            CHANNEL_ID,
            context.getString(R.string.trial_reminder_channel_name),
            NotificationManager.IMPORTANCE_DEFAULT,
        ).apply { description = context.getString(R.string.trial_reminder_channel_description) }
        context.getSystemService(NotificationManager::class.java).createNotificationChannel(channel)
    }

    internal fun post(context: Context, trialEndMillis: Long, priceText: String?) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU &&
            ContextCompat.checkSelfPermission(context, Manifest.permission.POST_NOTIFICATIONS) != PackageManager.PERMISSION_GRANTED
        ) {
            return
        }
        ensureChannel(context)
        val open = PendingIntent.getActivity(
            context,
            NOTIFICATION_ID,
            Intent(context, MainActivity::class.java).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP),
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )
        val text = body(context, trialEndMillis, priceText)
        val notification = NotificationCompat.Builder(context, CHANNEL_ID)
            .setSmallIcon(android.R.drawable.ic_popup_reminder)
            .setContentTitle(context.getString(R.string.trial_reminder_title))
            .setContentText(text)
            .setStyle(NotificationCompat.BigTextStyle().bigText(text))
            .setContentIntent(open)
            .setAutoCancel(true)
            .build()
        runCatching { NotificationManagerCompat.from(context).notify(NOTIFICATION_ID, notification) }
    }
}

/** Seam for the billing repository, so store tests never touch WorkManager. */
interface TrialReminderScheduler {
    fun schedule(purchaseTimeMillis: Long, priceText: String?)
    fun cancel()
}

class WorkManagerTrialReminders(private val context: Context) : TrialReminderScheduler {
    // A reminder must never fail a purchase or an entitlement refresh.
    override fun schedule(purchaseTimeMillis: Long, priceText: String?) {
        runCatching { TrialReminder.schedule(context, purchaseTimeMillis, priceText) }
            .onFailure { Timber.w(it, "Trial reminder not scheduled") }
    }

    override fun cancel() {
        runCatching { TrialReminder.cancel(context) }
            .onFailure { Timber.w(it, "Trial reminder not cancelled") }
    }
}

class TrialReminderWorker(appContext: Context, params: WorkerParameters) : CoroutineWorker(appContext, params) {
    override suspend fun doWork(): Result {
        val end = inputData.getLong(TrialReminder.KEY_TRIAL_END, 0L)
        if (end <= System.currentTimeMillis()) return Result.success()
        TrialReminder.post(applicationContext, end, inputData.getString(TrialReminder.KEY_PRICE))
        return Result.success()
    }
}
