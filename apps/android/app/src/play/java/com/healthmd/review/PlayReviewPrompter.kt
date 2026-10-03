package com.healthmd.review

import android.app.Activity
import com.google.android.play.core.review.ReviewManagerFactory
import com.healthmd.domain.review.ReviewPromptResult
import com.healthmd.domain.review.ReviewPrompter
import kotlin.coroutines.resume
import kotlinx.coroutines.suspendCancellableCoroutine

class PlayReviewPrompter : ReviewPrompter {
    override val isAvailable: Boolean = true

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
}
