package com.healthmd.presentation.common

import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButtonDefaults
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.OutlinedIconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.unit.dp
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

/** Geist large primary action: one high-contrast action per view. */
@Composable
fun PrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    enabled: Boolean = true,
    isLoading: Boolean = false,
) {
    val colors = LocalGeistColors.current
    Button(
        onClick = onClick,
        enabled = enabled && !isLoading,
        modifier = modifier
            .fillMaxWidth()
            .defaultMinSize(minHeight = GeistSizes.controlLarge),
        shape = RoundedCornerShape(GeistRadii.small),
        colors = ButtonDefaults.buttonColors(
            containerColor = colors.gray.c1000,
            contentColor = colors.background100,
            disabledContainerColor = colors.gray.c100,
            disabledContentColor = colors.gray.c700,
        ),
        elevation = ButtonDefaults.buttonElevation(defaultElevation = 0.dp),
        contentPadding = ButtonDefaults.ContentPadding,
    ) {
        if (isLoading) {
            CircularProgressIndicator(
                modifier = Modifier.size(20.dp),
                color = colors.background100,
                strokeWidth = 2.dp,
            )
        } else {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(8.dp),
            ) {
                icon?.let {
                    Icon(it, contentDescription = null, modifier = Modifier.size(18.dp))
                }
                Text(text = text, style = GeistType.button16)
            }
        }
    }
}

/** Geist bordered secondary action. */
@Composable
fun SecondaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
    enabled: Boolean = true,
) {
    val colors = LocalGeistColors.current
    OutlinedButton(
        onClick = onClick,
        enabled = enabled,
        modifier = modifier.defaultMinSize(minHeight = GeistSizes.controlLarge),
        shape = RoundedCornerShape(GeistRadii.small),
        colors = ButtonDefaults.outlinedButtonColors(
            containerColor = colors.background100,
            contentColor = colors.gray.c1000,
            disabledContainerColor = colors.gray.c100,
            disabledContentColor = colors.gray.c700,
        ),
        border = BorderStroke(1.dp, if (enabled) colors.grayAlpha.c400 else colors.grayAlpha.c200),
        contentPadding = ButtonDefaults.ContentPadding,
    ) {
        Row(
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            icon?.let {
                Icon(it, contentDescription = null, modifier = Modifier.size(18.dp))
            }
            Text(text = text, style = GeistType.button14)
        }
    }
}

/** Circular icon control; full radius is reserved for controls like this. */
@Composable
fun GeistIconButton(
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    size: Int = 48,
    tint: Color = MaterialTheme.colorScheme.onSurfaceVariant,
    contentDescription: String? = null,
) {
    val colors = LocalGeistColors.current
    OutlinedIconButton(
        onClick = onClick,
        modifier = modifier.size(size.dp),
        shape = CircleShape,
        colors = IconButtonDefaults.outlinedIconButtonColors(
            containerColor = colors.background100,
            contentColor = tint,
        ),
        border = BorderStroke(1.dp, colors.grayAlpha.c400),
    ) {
        Icon(
            imageVector = icon,
            contentDescription = contentDescription,
            modifier = Modifier.size(18.dp),
        )
    }
}
