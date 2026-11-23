package com.healthmd.presentation.review

import android.app.Activity
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.ui.platform.LocalContext
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.delay

@HiltViewModel
class ScheduledReviewPromptViewModel @Inject constructor(
    val moment: ScheduledReviewMoment,
) : ViewModel()

/** Lets the UI settle after launch or return before any review card can appear. */
internal const val SCHEDULED_REVIEW_SETTLE_MILLIS = 1_500L

/**
 * Each time the hosting screen resumes, waits [SCHEDULED_REVIEW_SETTLE_MILLIS] and offers
 * [ScheduledReviewMoment] a chance to ask. Pausing cancels the wait; a Compose dialog,
 * bottom sheet or another window takes window focus, so nothing is shown over them.
 */
@Composable
fun ScheduledReviewPromptEffect(viewModel: ScheduledReviewPromptViewModel = hiltViewModel()) {
    val activity = LocalContext.current as? Activity ?: return
    val lifecycleOwner = LocalLifecycleOwner.current
    LaunchedEffect(lifecycleOwner, activity) {
        lifecycleOwner.repeatOnLifecycle(Lifecycle.State.RESUMED) {
            delay(SCHEDULED_REVIEW_SETTLE_MILLIS)
            viewModel.moment.maybePrompt(activity) {
                lifecycleOwner.lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) &&
                    activity.hasWindowFocus() && !activity.isFinishing
            }
        }
    }
}
