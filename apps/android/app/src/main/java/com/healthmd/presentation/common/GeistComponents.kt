package com.healthmd.presentation.common

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

/**
 * Standard Geist card. Hierarchy comes from its surface and border rather than
 * decorative elevation.
 */
@Composable
fun GeistCard(
    modifier: Modifier = Modifier,
    padding: Dp = GeistSpacing.space6,
    content: @Composable ColumnScope.() -> Unit,
) {
    val colors = LocalGeistColors.current
    val shape = RoundedCornerShape(GeistRadii.small)

    Column(
        modifier = modifier
            .fillMaxWidth()
            .background(colors.background100, shape)
            .border(1.dp, colors.grayAlpha.c400, shape)
            .padding(padding),
        content = content,
    )
}

@Composable
fun GeistCardClickable(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    padding: Dp = GeistSpacing.space4,
    content: @Composable RowScope.() -> Unit,
) {
    val colors = LocalGeistColors.current
    val shape = RoundedCornerShape(GeistRadii.small)

    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(colors.background100, shape)
            .border(1.dp, colors.grayAlpha.c400, shape)
            .defaultMinSize(minHeight = GeistSizes.minimumTouchTarget)
            .clickable(role = Role.Button, onClick = onClick)
            .padding(padding),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

@Composable
fun GeistBadge(
    modifier: Modifier = Modifier,
    borderColor: Color = MaterialTheme.colorScheme.outline,
    content: @Composable RowScope.() -> Unit,
) {
    val colors = LocalGeistColors.current
    val shape = RoundedCornerShape(GeistRadii.full)

    Row(
        modifier = modifier
            .background(colors.background100, shape)
            .border(1.dp, borderColor, shape)
            .padding(horizontal = GeistSpacing.space3, vertical = GeistSpacing.space2),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

@Composable
fun GeistIconCircle(
    modifier: Modifier = Modifier,
    size: Dp = GeistSizes.controlLarge,
    content: @Composable BoxScope.() -> Unit,
) {
    val colors = LocalGeistColors.current
    Box(
        modifier = modifier
            .size(size)
            .background(colors.background100, CircleShape)
            .border(1.dp, colors.grayAlpha.c400, CircleShape),
        contentAlignment = Alignment.Center,
        content = content,
    )
}

@Composable
fun SectionLabel(
    text: String,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    Text(
        text = text,
        style = GeistType.heading14,
        color = colors.secondary,
        modifier = modifier.padding(bottom = GeistSpacing.space2),
    )
}
