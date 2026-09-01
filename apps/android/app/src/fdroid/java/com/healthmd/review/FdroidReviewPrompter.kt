package com.healthmd.review

import android.app.Activity
import com.healthmd.domain.review.ReviewPromptResult
import com.healthmd.domain.review.ReviewPrompter

class FdroidReviewPrompter : ReviewPrompter {
    override val isAvailable: Boolean = false
    override suspend fun prompt(activity: Activity): ReviewPromptResult =
        ReviewPromptResult.Unavailable
}
