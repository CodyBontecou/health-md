package com.healthmd.presentation.settings

import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.toggleable
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
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.presentation.common.AppSwitch
import com.healthmd.presentation.common.ConfigurationProtectionTestTags
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

/**
 * The configuration-protection setting as a list group: a heading, then one tonal row whose
 * labeled switch row is the only action, with the explanation below at the row's full width.
 */
@Composable
internal fun ConfigurationProtectionSettingsCard(
    enabled: Boolean?,
    onEnabledChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    Column(modifier.fillMaxWidth()) {
        Text(
            stringResource(R.string.configuration_protection_title),
            style = GeistType.heading14,
            color = colors.brandPrimary,
            modifier = Modifier
                .padding(start = GeistSpacing.space4, bottom = GeistSpacing.space2)
                .semantics { heading() },
        )
        Column(
            Modifier.fillMaxWidth()
                .clip(RoundedCornerShape(GeistRadii.listGroup))
                .background(colors.background200)
                .padding(start = GeistSpacing.space4, end = GeistSpacing.space4, bottom = GeistSpacing.space3),
        ) {
            Row(
                modifier = Modifier.fillMaxWidth().heightIn(min = GroupRowMinHeight)
                    .testTag(ConfigurationProtectionTestTags.TOGGLE)
                    .toggleable(
                        value = enabled == true, enabled = enabled != null,
                        role = Role.Switch, onValueChange = onEnabledChange,
                    ),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
            ) {
                Text(
                    stringResource(R.string.configuration_protection_toggle),
                    style = GeistType.label16, color = colors.primary, modifier = Modifier.weight(1f),
                )
                AppSwitch(checked = enabled == true, onCheckedChange = null, enabled = enabled != null)
            }
            Text(
                stringResource(R.string.configuration_protection_description),
                style = GeistType.copy13, color = colors.secondary,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

/**
 * A standalone Settings-style navigation row: a tonal `background-200` row whose whole surface is
 * one action. Wide layouts show the icon circle; reading layouts give its width to the text and
 * keep the chevron beside the title, so the subtitle spans the row.
 */
@Composable
internal fun SettingsNavigationCard(
    title: String,
    subtitle: String? = null,
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    external: Boolean = false,
    shape: Shape = RoundedCornerShape(GeistRadii.listGroup),
) {
    val colors = LocalGeistColors.current
    BoxWithConstraints {
        val reading = GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)
        val arrow: @Composable () -> Unit = {
            Icon(
                if (external) Icons.Outlined.ArrowOutward else Icons.AutoMirrored.Outlined.KeyboardArrowRight,
                contentDescription = null,
                tint = colors.secondary,
                modifier = Modifier.size(if (external) 18.dp else 24.dp),
            )
        }
        Row(
            modifier = modifier.fillMaxWidth()
                .clip(shape)
                .background(colors.background200)
                .clickable(role = Role.Button, onClick = onClick)
                .heightIn(min = if (subtitle != null) 72.dp else GroupRowMinHeight)
                .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
        ) {
            if (!reading) {
                Box(
                    Modifier.size(GeistSizes.control).background(colors.gray.c300, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(icon, contentDescription = null, tint = colors.secondary, modifier = Modifier.size(22.dp))
                }
            }
            Column(Modifier.weight(1f)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                ) {
                    Text(title, style = GeistType.label16, color = colors.primary, modifier = Modifier.weight(1f))
                    if (reading) arrow()
                }
                if (subtitle != null) {
                    Text(subtitle, style = GeistType.copy13, color = colors.secondary, modifier = Modifier.fillMaxWidth())
                }
            }
            if (!reading) arrow()
        }
    }
}
