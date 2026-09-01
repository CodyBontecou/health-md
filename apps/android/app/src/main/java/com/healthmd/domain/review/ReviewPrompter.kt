package com.healthmd.domain.review

import android.app.Activity

sealed interface ReviewPromptResult {
    data object Completed : ReviewPromptResult
    data object Unavailable : ReviewPromptResult
    data object Failed : ReviewPromptResult
}

/** Distribution-owned review integration. Common export code never references a store SDK. */
interface ReviewPrompter {
    val isAvailable: Boolean
    suspend fun prompt(activity: Activity): ReviewPromptResult
}
