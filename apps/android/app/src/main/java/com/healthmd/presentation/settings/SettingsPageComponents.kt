package com.healthmd.presentation.settings

import android.text.format.DateUtils
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Info
import androidx.compose.material.icons.outlined.WarningAmber
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

/** A read-only "label · value" row for a destination's Activity and Status sections. */
@Composable
internal fun SettingsValueRow(shape: Shape, title: String, value: String, mono: Boolean = false) {
    val colors = LocalGeistColors.current
    BoxWithConstraints(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.background200)
            .semantics(mergeDescendants = true) {}
            .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space4),
    ) {
        val stacked = GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)
        if (stacked) {
            Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space1)) {
                Text(title, style = GeistType.label16, color = colors.primary)
                Text(value, style = if (mono) GeistType.label14Mono else GeistType.label14, color = colors.secondary)
            }
        } else {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
            ) {
                Text(title, style = GeistType.label16, color = colors.primary, modifier = Modifier.weight(1f))
                Text(
                    value,
                    style = if (mono) GeistType.label14Mono else GeistType.label14,
                    color = colors.secondary,
                    textAlign = TextAlign.End,
                    modifier = Modifier.weight(1f),
                )
            }
        }
    }
}

/** Explanatory text under a group, at the group's inset. */
@Composable
internal fun SettingsFootnote(text: String, modifier: Modifier = Modifier) {
    Text(
        text,
        style = GeistType.copy13,
        color = LocalGeistColors.current.secondary,
        modifier = modifier.fillMaxWidth().padding(start = GeistSpacing.space4, end = GeistSpacing.space4, top = GeistSpacing.space2),
    )
}

/** iOS's trust and warning notes: an outlined tonal card with a leading symbol. */
@Composable
internal fun SettingsNoticeCard(text: String, warning: Boolean = false, modifier: Modifier = Modifier) {
    val colors = LocalGeistColors.current
    val tint = if (warning) colors.warning else colors.brandPrimary
    Row(
        modifier
            .fillMaxWidth()
            .padding(top = GeistSpacing.space6)
            .clip(RoundedCornerShape(GeistRadii.listGroup))
            .background(colors.background200)
            .border(1.dp, tint.copy(alpha = 0.6f), RoundedCornerShape(GeistRadii.listGroup))
            .semantics(mergeDescendants = true) {}
            .padding(GeistSpacing.space4),
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
    ) {
        Icon(
            if (warning) Icons.Outlined.WarningAmber else Icons.Outlined.Info,
            contentDescription = null,
            tint = tint,
            modifier = Modifier.size(20.dp),
        )
        Text(text, style = GeistType.copy14, color = colors.secondary, modifier = Modifier.weight(1f))
    }
}

/** One destructive action in its own group, as iOS's "Remove endpoint". */
@Composable
internal fun SettingsDestructiveRow(title: String, onClick: () -> Unit, modifier: Modifier = Modifier) {
    val colors = LocalGeistColors.current
    Column(Modifier.padding(top = GeistSpacing.space6)) {
        TextButton(
            onClick = onClick,
            shape = RoundedCornerShape(GeistRadii.listGroup),
            modifier = modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(GeistRadii.listGroup))
                .background(colors.background200),
        ) {
            Text(title, style = GeistType.label16, color = colors.error, modifier = Modifier.fillMaxWidth())
        }
    }
}

/** A small single-field editor, as iOS's subfolder alert. */
@Composable
internal fun SettingsTextFieldDialog(
    title: String,
    initialValue: String,
    onSave: (String) -> Unit,
    onDismiss: () -> Unit,
    keyboardType: KeyboardType = KeyboardType.Text,
) {
    val colors = LocalGeistColors.current
    var value by remember { mutableStateOf(initialValue) }
    AlertDialog(
        onDismissRequest = onDismiss,
        containerColor = colors.gray.c200,
        shape = RoundedCornerShape(GeistRadii.large),
        title = { Text(title, style = GeistType.heading20, color = colors.primary) },
        text = {
            OutlinedTextField(
                value = value,
                onValueChange = { value = it },
                singleLine = true,
                textStyle = GeistType.copy14Mono,
                keyboardOptions = KeyboardOptions(keyboardType = keyboardType, autoCorrectEnabled = false),
                modifier = Modifier.fillMaxWidth(),
            )
        },
        confirmButton = {
            TextButton(onClick = { onSave(value) }) {
                Text(stringResource(R.string.settings_save), style = GeistType.button14, color = colors.brandPrimary)
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss) { Text(stringResource(R.string.cancel), style = GeistType.button14) }
        },
    )
}

/** "Today, 2:00 PM", "Yesterday, 9:12 AM", or a dated time for older writes. */
@Composable
internal fun settingsTimestampText(epochMillis: Long): String {
    val context = LocalContext.current
    return DateUtils.getRelativeDateTimeString(
        context,
        epochMillis,
        DateUtils.DAY_IN_MILLIS,
        DateUtils.WEEK_IN_MILLIS,
        DateUtils.FORMAT_SHOW_TIME,
    ).toString()
}
