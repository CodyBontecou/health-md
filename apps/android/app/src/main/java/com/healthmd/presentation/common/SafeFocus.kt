package com.healthmd.presentation.common

import androidx.compose.ui.focus.FocusManager
import timber.log.Timber

/**
 * Clears focus without crashing on Compose's inconsistent-focus-tree bug.
 *
 * In Compose UI 1.7, `clearFocus()` can throw `IllegalArgumentException("ActiveParent with no
 * focused child")` when the focused node left composition (for example a field inside a dialog or
 * dropdown that just closed). Play vitals showed this crashing the profile schedule dropdown. The
 * caller only wants the keyboard and caret gone, so a failed clear is retried with `force` and then
 * logged instead of taking the app down.
 */
fun FocusManager.clearFocusSafely() {
    try {
        clearFocus()
    } catch (error: IllegalArgumentException) {
        try {
            clearFocus(force = true)
        } catch (forced: IllegalArgumentException) {
            Timber.w("Focus could not be cleared: %s", forced.javaClass.simpleName)
        }
    }
}
