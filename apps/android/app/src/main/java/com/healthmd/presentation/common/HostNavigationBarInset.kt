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
