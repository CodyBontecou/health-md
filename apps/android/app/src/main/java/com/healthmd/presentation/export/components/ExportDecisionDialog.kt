package com.healthmd.presentation.export.components

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import androidx.compose.ui.window.DialogProperties
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

/** One stacked action in an [ExportDecisionDialog]. */
data class ExportDecisionAction(
    val title: String,
    val role: Role = Role.SECONDARY,
    val testTag: String? = null,
    val onClick: () -> Unit,
) {
    enum class Role { PRIMARY, SECONDARY, CANCEL }
}

/**
 * iOS GlassDecisionDialog (LargeConfirmG): a dimmed scrim with a decision card whose actions
 * stack full width, the primary one filled. Dismissing outside the card runs the cancel action.
 */
@Composable
fun ExportDecisionDialog(
    title: String,
    message: String,
    actions: List<ExportDecisionAction>,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    val cancel = actions.firstOrNull { it.role == ExportDecisionAction.Role.CANCEL } ?: actions.lastOrNull()
    Dialog(
        onDismissRequest = { cancel?.onClick?.invoke() },
        properties = DialogProperties(usePlatformDefaultWidth = false),
    ) {
        Surface(
            shape = RoundedCornerShape(GeistRadii.large),
            color = colors.gray.c200,
            modifier = modifier
                .padding(horizontal = GeistSpacing.space8 - GeistSpacing.space1)
                .widthIn(max = 420.dp)
                .fillMaxWidth(),
        ) {
            Column(
                Modifier.padding(GeistSpacing.space6 - 2.dp),
                verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
            ) {
                Text(
                    title,
                    style = GeistType.heading20,
                    color = colors.primary,
                    modifier = Modifier.semantics { heading() },
                )
                Text(message, style = GeistType.copy14, color = colors.secondary)
                Column(
                    Modifier.padding(top = GeistSpacing.space1),
                    verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                ) {
                    actions.forEach { action ->
                        val actionModifier = Modifier
                            .fillMaxWidth()
                            .heightIn(min = GeistSizes.controlLarge + GeistSpacing.space1)
                            .then(if (action.testTag != null) Modifier.testTag(action.testTag) else Modifier)
                        val shape = RoundedCornerShape(GeistRadii.full)
                        when (action.role) {
                            ExportDecisionAction.Role.PRIMARY -> Button(
                                onClick = action.onClick,
                                shape = shape,
                                colors = ButtonDefaults.buttonColors(
                                    containerColor = colors.brandPrimary,
                                    contentColor = colors.brandOnPrimary,
                                ),
                                modifier = actionModifier,
                            ) { Text(action.title, style = GeistType.button16, textAlign = TextAlign.Center) }
                            ExportDecisionAction.Role.SECONDARY -> FilledTonalButton(
                                onClick = action.onClick,
                                shape = shape,
                                colors = ButtonDefaults.filledTonalButtonColors(
                                    containerColor = colors.secondaryContainer,
                                    contentColor = colors.onSecondaryContainer,
                                ),
                                modifier = actionModifier,
                            ) { Text(action.title, style = GeistType.button16, textAlign = TextAlign.Center) }
                            ExportDecisionAction.Role.CANCEL -> TextButton(
                                onClick = action.onClick,
                                shape = shape,
                                modifier = actionModifier,
                            ) {
                                Text(action.title, style = GeistType.button16, color = colors.secondary, textAlign = TextAlign.Center)
                            }
                        }
                    }
                }
            }
        }
    }
}
