package com.healthmd.presentation.common

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.BorderStroke
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Radii
import com.healthmd.presentation.theme.Spacing

@Composable
fun GlassCard(
    modifier: Modifier = Modifier,
    padding: Dp = Spacing.lg,
    content: @Composable ColumnScope.() -> Unit,
) {
    val shape = RoundedCornerShape(Radii.card)

    Column(
        modifier = modifier
            .fillMaxWidth()
            .shadow(
                elevation = 6.dp,
                shape = shape,
                ambientColor = AppColors.glassShadow,
                spotColor = AppColors.glassShadow,
            )
            .clip(shape)
            .background(AppColors.bgTertiary)
            .border(
                width = 1.dp,
                color = AppColors.glassBorder,
                shape = shape,
            )
            .padding(padding),
        content = content,
    )
}

@Composable
fun GlassCardClickable(
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    padding: Dp = Spacing.md,
    content: @Composable RowScope.() -> Unit,
) {
    val shape = RoundedCornerShape(Radii.card)
    val interactionSource = remember { MutableInteractionSource() }
    val isPressed by interactionSource.collectIsPressedAsState()
    val scale by animateFloatAsState(
        targetValue = if (isPressed) 0.98f else 1f,
        animationSpec = spring(dampingRatio = 0.7f, stiffness = 300f),
        label = "cardScale",
    )

    Row(
        modifier = modifier
            .fillMaxWidth()
            .scale(scale)
            .shadow(
                elevation = 4.dp,
                shape = shape,
                ambientColor = Color.Black.copy(alpha = 0.10f),
                spotColor = Color.Black.copy(alpha = 0.10f),
            )
            .clip(shape)
            .background(AppColors.bgTertiary)
            .border(1.dp, AppColors.glassBorder, shape)
            .defaultMinSize(minHeight = 56.dp)
            .clickable(
                interactionSource = interactionSource,
                indication = null,
                role = Role.Button,
                onClick = onClick,
            )
            .padding(horizontal = padding, vertical = padding),
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

@Composable
fun GlassBadge(
    modifier: Modifier = Modifier,
    borderColor: Color = AppColors.glassBorder,
    content: @Composable RowScope.() -> Unit,
) {
    val shape = RoundedCornerShape(Radii.badge)

    Row(
        modifier = modifier
            .clip(shape)
            .background(AppColors.bgTertiary)
            .border(1.dp, borderColor, shape)
            .padding(horizontal = Spacing.md, vertical = Spacing.sm),
        horizontalArrangement = Arrangement.Center,
        verticalAlignment = Alignment.CenterVertically,
        content = content,
    )
}

@Composable
fun GlassIconCircle(
    modifier: Modifier = Modifier,
    size: Dp = 48.dp,
    content: @Composable BoxScope.() -> Unit,
) {
    Box(
        modifier = modifier
            .size(size)
            .clip(CircleShape)
            .background(AppColors.bgTertiary)
            .border(1.dp, AppColors.glassBorder, CircleShape),
        contentAlignment = Alignment.Center,
        content = content,
    )
}

@Composable
fun SectionLabel(
    text: String,
    modifier: Modifier = Modifier,
) {
    Text(
        text = text.uppercase(),
        style = MaterialTheme.typography.labelLarge,
        color = AppColors.textMuted,
        letterSpacing = 2.sp,
        modifier = modifier.padding(bottom = Spacing.sm),
    )
}
