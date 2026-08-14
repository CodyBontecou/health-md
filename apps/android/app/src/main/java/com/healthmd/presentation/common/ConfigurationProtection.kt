package com.healthmd.presentation.common

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Radii
import com.healthmd.presentation.theme.Spacing

object ConfigurationProtectionTestTags {
    const val SECTION = "configuration_protection_section"
    const val TOGGLE = "configuration_protection_toggle"
    const val TOAST = "configuration_protection_toast"
    const val PROTECTED_REGION = "configuration_protection_protected_region"
}

@Immutable
data class ConfigurationProtectionUi(
    val enabled: Boolean = false,
    val onBlockedChange: () -> Unit = {},
)

val LocalConfigurationProtection = compositionLocalOf { ConfigurationProtectionUi() }

/**
 * Keeps the current configuration readable while intercepting an attempted edit. The overlay is
 * used only for user-facing configuration regions; operation buttons such as Export, Sync, Retry,
 * Stop, and Cancel remain outside it.
 */
@Composable
fun ConfigurationProtectedRegion(
    modifier: Modifier = Modifier,
    content: @Composable BoxScope.() -> Unit,
) {
    val protection = LocalConfigurationProtection.current
    val blockedTitle = stringResource(R.string.configuration_protection_blocked_title)
    val blockedAction = stringResource(R.string.configuration_protection_blocked_action)
    Box(modifier = modifier) {
        Box(
            modifier = if (protection.enabled) {
                Modifier.clearAndSetSemantics { }
            } else {
                Modifier
            },
            content = content,
        )
        if (protection.enabled) {
            Box(
                modifier = Modifier
                    .fillMaxSize()
                    .testTag(ConfigurationProtectionTestTags.PROTECTED_REGION)
                    .clickable(
                        role = Role.Button,
                        onClickLabel = blockedAction,
                        onClick = protection.onBlockedChange,
                    )
                    .semantics { contentDescription = blockedTitle },
            )
        }
    }
}

@Composable
fun ConfigurationProtectionToast(
    visible: Boolean,
    onOpenSettings: () -> Unit,
    modifier: Modifier = Modifier,
) {
    AnimatedVisibility(
        visible = visible,
        modifier = modifier,
        enter = slideInVertically { -it } + fadeIn(),
        exit = slideOutVertically { -it } + fadeOut(),
    ) {
        val shape = RoundedCornerShape(Radii.card)
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .testTag(ConfigurationProtectionTestTags.TOAST)
                .background(AppColors.bgPrimary, shape)
                .border(1.dp, AppColors.borderDefault, shape)
                .clickable(
                    role = Role.Button,
                    onClickLabel = stringResource(R.string.configuration_protection_open_setting),
                    onClick = onOpenSettings,
                )
                .semantics { liveRegion = LiveRegionMode.Polite }
                .padding(Spacing.md),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            Box(
                modifier = Modifier
                    .size(36.dp)
                    .background(AppColors.accentSubtle, RoundedCornerShape(Radii.card)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Outlined.Lock,
                    contentDescription = null,
                    tint = AppColors.accent,
                    modifier = Modifier.size(20.dp),
                )
            }
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    stringResource(R.string.configuration_protection_blocked_title),
                    style = MaterialTheme.typography.bodyLarge,
                    color = AppColors.textPrimary,
                    fontWeight = FontWeight.SemiBold,
                )
                Text(
                    stringResource(R.string.configuration_protection_blocked_body),
                    style = MaterialTheme.typography.bodySmall,
                    color = AppColors.textSecondary,
                )
            }
            Spacer(Modifier.width(Spacing.xxs))
            Text(
                stringResource(R.string.configuration_protection_open_setting),
                style = MaterialTheme.typography.labelLarge,
                color = AppColors.accent,
            )
        }
    }
}
