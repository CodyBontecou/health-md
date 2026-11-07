package com.healthmd.presentation.common

import android.os.Build
import android.view.ViewGroup
import android.view.WindowManager
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.DialogWindowProvider
import androidx.core.view.WindowCompat

/**
 * The activity window's navigation bar height. A full-height dialog window can report no
 * navigation bar inset on edge-to-edge Android, which put dialog actions under the gesture handle.
 */
val LocalHostNavigationBarInset = compositionLocalOf<Dp> { 0.dp }

/**
 * Bottom space a scrolling screen leaves so its last row clears the floating Export now
 * button: the button, its margin and a gap. Zero where no floating button is shown (rail).
 */
val LocalFloatingActionClearance = compositionLocalOf<Dp> { 0.dp }

/**
 * True from the `md` breakpoint (601dp of window width), where a navigation rail replaces the
 * bottom bar. List/detail screens read this rather than their own width, which the rail narrows.
 */
val LocalUsesNavigationRail = compositionLocalOf { false }

/** Measures the activity's navigation bar once, outside any dialog, for the dialogs below it. */
@Composable
fun ProvideHostNavigationBarInset(content: @Composable () -> Unit) {
    val inset = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding()
    CompositionLocalProvider(LocalHostNavigationBarInset provides inset, content = content)
}

/** `navigationBarsPadding()` that also holds inside a dialog window. */
fun Modifier.dialogNavigationBarsPadding(): Modifier = composed {
    windowInsetsPadding(
        WindowInsets.navigationBars.union(WindowInsets(bottom = LocalHostNavigationBarInset.current)),
    )
}

/**
 * Makes the enclosing full-screen dialog window edge-to-edge. Compose sizes a
 * `decorFitsSystemWindows = false` dialog to the whole display, but newer Android versions still
 * fit the window between the system bars and below the camera cutout, so content laid out for the full height (a bottom
 * sheet's action) ran off the bottom of the screen. Clearing the fitting lets the window cover the
 * display and report the real navigation bar inset to `dialogNavigationBarsPadding`.
 */
@Composable
fun EdgeToEdgeDialogWindow() {
    val window = (LocalView.current.parent as? DialogWindowProvider)?.window ?: return
    DisposableEffect(window) {
        WindowCompat.setDecorFitsSystemWindows(window, false)
        window.setLayout(ViewGroup.LayoutParams.MATCH_PARENT, ViewGroup.LayoutParams.MATCH_PARENT)
        window.attributes = window.attributes.apply {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                fitInsetsTypes = 0
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_ALWAYS
            } else if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                layoutInDisplayCutoutMode = WindowManager.LayoutParams.LAYOUT_IN_DISPLAY_CUTOUT_MODE_SHORT_EDGES
            }
        }
        onDispose {}
    }
}
