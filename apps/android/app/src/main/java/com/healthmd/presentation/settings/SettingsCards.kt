package com.healthmd.presentation.settings

import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.toggleable
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowForwardIos
import androidx.compose.material.icons.outlined.ArrowOutward
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.font.FontWeight
import com.healthmd.R
import com.healthmd.presentation.common.ConfigurationProtectionTestTags
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.GeistCardClickable
import com.healthmd.presentation.common.SectionLabel
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.Spacing

/** Keep the explanation out of the switch's narrow text column; one labeled toggle target. */
@Composable
internal fun ConfigurationProtectionSettingsCard(
    enabled: Boolean?,
    onEnabledChange: (Boolean) -> Unit,
    modifier: Modifier = Modifier,
) {
    GeistCard(modifier = modifier, padding = Spacing.md) {
        SectionLabel(stringResource(R.string.configuration_protection_title))
        Row(
            modifier = Modifier.fillMaxWidth().heightIn(min = GeistSizes.minimumTouchTarget)
                .testTag(ConfigurationProtectionTestTags.TOGGLE)
                .toggleable(
                    value = enabled == true, enabled = enabled != null,
                    role = Role.Switch, onValueChange = onEnabledChange,
                ),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            Text(
                stringResource(R.string.configuration_protection_toggle),
                style = MaterialTheme.typography.bodyLarge, color = AppColors.textPrimary,
                fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f),
            )
            Switch(
                checked = enabled == true, onCheckedChange = null, enabled = enabled != null,
                colors = SwitchDefaults.colors(
                    checkedThumbColor = AppColors.onAccent,
                    checkedTrackColor = AppColors.accent,
                    uncheckedThumbColor = AppColors.textMuted,
                    uncheckedTrackColor = AppColors.bgSecondary,
                    uncheckedBorderColor = AppColors.borderDefault,
                ),
            )
        }
        Spacer(Modifier.height(Spacing.sm))
        Text(
            stringResource(R.string.configuration_protection_description),
            style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

/** Navigation stays a whole-card action; essential text never competes with decoration. */
@Composable
internal fun SettingsNavigationCard(
    title: String,
    subtitle: String? = null,
    icon: ImageVector,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    external: Boolean = false,
) {
    BoxWithConstraints {
        val reading = GeistAdaptiveLayout.stackDetailedControls(maxWidth.value, LocalDensity.current.fontScale)
        val arrow = if (external) Icons.Outlined.ArrowOutward else Icons.AutoMirrored.Outlined.ArrowForwardIos
        GeistCardClickable(onClick = onClick, modifier = modifier, padding = Spacing.md) {
            if (!reading) {
                Icon(icon, contentDescription = null, tint = AppColors.accent, modifier = Modifier.size(Spacing.lg))
                Spacer(Modifier.width(Spacing.sm))
            }
            Column(Modifier.weight(1f)) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    Text(
                        title, style = MaterialTheme.typography.bodyLarge, color = AppColors.textPrimary,
                        fontWeight = FontWeight.Medium, modifier = Modifier.weight(1f),
                    )
                    if (reading) {
                        Icon(arrow, contentDescription = null, tint = AppColors.textSecondary,
                            modifier = Modifier.size(Spacing.md))
                    }
                }
                if (subtitle != null) {
                    Text(subtitle, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary,
                        modifier = Modifier.fillMaxWidth())
                }
            }
            if (!reading) {
                Spacer(Modifier.width(Spacing.sm))
                Icon(arrow, contentDescription = null, tint = AppColors.textSecondary,
                    modifier = Modifier.size(Spacing.md))
            }
        }
    }
}
