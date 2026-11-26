package com.healthmd.review

import android.app.Activity
import android.content.Context
import android.os.Build
import com.google.android.play.core.review.ReviewManagerFactory
import com.healthmd.domain.review.ReviewPromptResult
import com.healthmd.domain.review.ReviewPrompter
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

/**
 * Google Play In-App Review. Available only when Google Play installed this copy: a sideloaded,
 * e2e or adb-installed Play build never asks (Play can't show the card there anyway).
 */
class PlayReviewPrompter(
    private val installedFromPlay: () -> Boolean,
) : ReviewPrompter {
    constructor(context: Context) : this({ isInstalledFromPlay(context.applicationContext) })

    override val isAvailable: Boolean get() = installedFromPlay()

    override suspend fun prompt(activity: Activity): ReviewPromptResult =
        suspendCancellableCoroutine { continuation ->
            val manager = ReviewManagerFactory.create(activity)
            manager.requestReviewFlow().addOnCompleteListener { requestTask ->
                if (!continuation.isActive) return@addOnCompleteListener
                if (!requestTask.isSuccessful) {
                    continuation.resume(ReviewPromptResult.Failed)
                    return@addOnCompleteListener
                }
                manager.launchReviewFlow(activity, requestTask.result).addOnCompleteListener { launchTask ->
                    if (!continuation.isActive) return@addOnCompleteListener
                    continuation.resume(
                        if (launchTask.isSuccessful) {
                            ReviewPromptResult.Completed
                        } else {
                            ReviewPromptResult.Failed
                        },
                    )
                }
            }
        }

    companion object {
        const val PLAY_STORE_INSTALLER = "com.android.vending"

        fun isInstalledFromPlay(context: Context): Boolean = runCatching {
            val pm = context.packageManager
            val installer = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                pm.getInstallSourceInfo(context.packageName).installingPackageName
            } else {
                @Suppress("DEPRECATION")
                pm.getInstallerPackageName(context.packageName)
            }
            installer == PLAY_STORE_INSTALLER
        }.getOrDefault(false)
    }
}
