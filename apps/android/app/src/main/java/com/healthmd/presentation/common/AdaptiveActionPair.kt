package com.healthmd.presentation.common

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.Spacing

/** Full-width, primary-first actions when side-by-side labels would become narrow columns. */
@Composable
internal fun AdaptiveActionPair(
    primaryAction: @Composable (Modifier) -> Unit,
    secondaryAction: @Composable (Modifier) -> Unit,
    modifier: Modifier = Modifier,
) {
    BoxWithConstraints(modifier = modifier.fillMaxWidth()) {
        if (GeistAdaptiveLayout.stackActions(maxWidth.value, LocalDensity.current.fontScale)) {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                primaryAction(Modifier.fillMaxWidth())
                secondaryAction(Modifier.fillMaxWidth())
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                secondaryAction(Modifier.weight(1f))
                primaryAction(Modifier.weight(1f))
            }
        }
    }
}
