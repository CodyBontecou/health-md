package com.healthmd.presentation.settings

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.KeyboardArrowRight
import androidx.compose.material.icons.outlined.ArrowOutward
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

/**
 * A Settings list group (DESIGN.md `list-group`): a heading, then rows 2dp apart whose first
 * and last rows take 20dp outer corners and the rest 4dp corners, on `background-200`.
 */
@Composable
internal fun SettingsGroup(
    title: String,
    rows: List<@Composable (Shape) -> Unit>,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    Column(modifier.fillMaxWidth()) {
        Text(
            text = title,
            style = GeistType.heading14,
            color = colors.brandPrimary,
            modifier = Modifier
                .padding(start = GeistSpacing.space4, top = GeistSpacing.space6, bottom = GeistSpacing.space2)
                .semantics { heading() },
        )
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            rows.forEachIndexed { index, row -> row(groupRowShape(index, rows.size)) }
        }
    }
}

/** 20dp outer corners on the group's first and last rows, 4dp between rows. */
internal fun groupRowShape(index: Int, count: Int): Shape {
    val outer = GeistRadii.listGroup
    val inner = GeistRadii.extraSmall
    val top = if (index == 0) outer else inner
    val bottom = if (index == count - 1) outer else inner
    return RoundedCornerShape(topStart = top, topEnd = top, bottomStart = bottom, bottomEnd = bottom)
}

/** Trailing status tone: positive states read in the success color, others in secondary text. */
internal enum class SettingsTrailingTone { NEUTRAL, POSITIVE }

/**
 * One Settings row: a 40dp icon circle, title and optional subtitle, a trailing status value,
 * and a chevron (or an outward arrow for external links). The whole row is one action.
 */
@Composable
internal fun SettingsRow(
    shape: Shape,
    title: String,
    icon: ImageVector,
    onClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
    subtitle: String? = null,
    trailing: String? = null,
    trailingTone: SettingsTrailingTone = SettingsTrailingTone.NEUTRAL,
    external: Boolean = false,
    selected: Boolean = false,
    trailingContent: (@Composable () -> Unit)? = null,
    below: (@Composable ColumnScope.() -> Unit)? = null,
) {
    val colors = LocalGeistColors.current
    val container = if (selected) colors.secondaryContainer else colors.background200
    Column(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(container)
            .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            // Only the entry open beside the list reports selection; phones have none.
            .then(if (selected) Modifier.semantics { this.selected = true } else Modifier)
            .heightIn(min = if (subtitle != null) 72.dp else 56.dp)
            .padding(start = GeistSpacing.space4, end = GeistSpacing.space6 - GeistSpacing.space1, top = GeistSpacing.space2, bottom = GeistSpacing.space2),
        verticalArrangement = Arrangement.Center,
    ) {
        androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxWidth()) {
            // Reading-first below 336dp per font scale: the icon gives its width to the text.
            val reading = GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
            ) {
                if (!reading) {
                    Box(
                        Modifier
                            .size(GeistSizes.control)
                            .background(if (selected) colors.brandPrimary else colors.gray.c300, CircleShape),
                        contentAlignment = Alignment.Center,
                    ) {
                        Icon(
                            icon,
                            contentDescription = null,
                            tint = if (selected) colors.brandOnPrimary else colors.secondary,
                            modifier = Modifier.size(22.dp),
                        )
                    }
                }
                Column(Modifier.weight(1f)) {
                    Text(title, style = GeistType.label16, color = if (selected) colors.onSecondaryContainer else colors.primary)
                    subtitle?.let {
                        Text(it, style = GeistType.copy14, color = if (selected) colors.onSecondaryContainer else colors.secondary)
                    }
                }
                trailing?.let {
                    Text(
                        it,
                        style = GeistType.label14,
                        color = if (trailingTone == SettingsTrailingTone.POSITIVE) colors.success else colors.secondary,
                    )
                }
                if (trailingContent != null) {
                    trailingContent()
                } else if (onClick != null) {
                    Icon(
                        if (external) Icons.Outlined.ArrowOutward else Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                        contentDescription = null,
                        tint = colors.secondary,
                        modifier = Modifier.size(if (external) 18.dp else 24.dp),
                    )
                }
            }
        }
        below?.invoke(this)
    }
}

/** The board's plan card: the app icon on the primary container, the plan, restore or manage. */
@Composable
internal fun SettingsPlanCard(
    plan: String,
    onClick: (() -> Unit)?,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    Row(
        modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.large))
            .background(colors.brandSubtle)
            .then(if (onClick != null) Modifier.clickable(role = Role.Button, onClick = onClick) else Modifier)
            .padding(GeistSpacing.space4),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
    ) {
        Image(
            painter = painterResource(R.drawable.app_icon),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(56.dp).clip(RoundedCornerShape(GeistRadii.medium)),
        )
        Column(Modifier.weight(1f)) {
            Text(stringResource(R.string.app_name), style = GeistType.label18.copy(fontWeight = androidx.compose.ui.text.font.FontWeight.SemiBold), color = colors.brandOnSubtle)
            Text(plan, style = GeistType.copy14, color = colors.brandOnSubtle)
        }
        if (onClick != null) {
            Icon(Icons.AutoMirrored.Outlined.KeyboardArrowRight, contentDescription = null, tint = colors.brandOnSubtle)
        }
    }
}
