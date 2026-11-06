package com.healthmd.presentation.common

import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp

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
