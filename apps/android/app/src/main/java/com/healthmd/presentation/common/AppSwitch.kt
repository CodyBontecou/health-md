package com.healthmd.presentation.common

import androidx.compose.foundation.layout.size
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Check
import androidx.compose.material3.Icon
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import com.healthmd.presentation.theme.LocalGeistColors

/**
 * The Material 3 switch as DESIGN.md specifies it: brand track when on, with a check in the
 * thumb, and an outlined track when off. Pass a null [onCheckedChange] when the surrounding row
 * owns the toggle, so the switch never adds a second action.
 */
@Composable
fun AppSwitch(
    checked: Boolean,
    onCheckedChange: ((Boolean) -> Unit)?,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
) {
    val colors = LocalGeistColors.current
    Switch(
        checked = checked,
        onCheckedChange = onCheckedChange,
        modifier = modifier,
        enabled = enabled,
        thumbContent = if (checked) {
            { Icon(Icons.Filled.Check, contentDescription = null, modifier = Modifier.size(16.dp)) }
        } else {
            null
        },
        colors = SwitchDefaults.colors(
            checkedThumbColor = colors.brandOnPrimary,
            checkedTrackColor = colors.brandPrimary,
            checkedBorderColor = colors.brandPrimary,
            checkedIconColor = colors.brandPrimary,
            uncheckedThumbColor = colors.gray.c700,
            uncheckedTrackColor = colors.gray.c300,
            uncheckedBorderColor = colors.gray.c700,
        ),
    )
}
