package com.healthmd.presentation.common

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.slideOutVertically
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.Lock
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors

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
                    // Match measured content even in an unbounded scrolling column.
                    .matchParentSize()
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
        val colors = LocalGeistColors.current
        val shape = RoundedCornerShape(GeistRadii.medium)
        // Snackbar-style tonal surface: the whole bar opens the setting (one accessible action);
        // the trailing text button is its visible affordance.
        Row(
            modifier = Modifier
                .fillMaxWidth()
                .testTag(ConfigurationProtectionTestTags.TOAST)
                .clip(shape)
                .background(colors.brandSubtle)
                .clickable(
                    role = Role.Button,
                    onClickLabel = stringResource(R.string.configuration_protection_open_setting),
                    onClick = onOpenSettings,
                )
                .semantics { liveRegion = LiveRegionMode.Polite }
                .heightIn(min = GeistSizes.minimumTouchTarget)
                .padding(start = GeistSpacing.space4, end = GeistSpacing.space2, top = GeistSpacing.space3, bottom = GeistSpacing.space3),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
        ) {
            Icon(
                Icons.Outlined.Lock,
                contentDescription = null,
                tint = colors.brandOnSubtle,
                modifier = Modifier.size(20.dp),
            )
            Column(modifier = Modifier.weight(1f)) {
                Text(
                    stringResource(R.string.configuration_protection_blocked_title),
                    style = GeistType.heading14,
                    color = colors.brandOnSubtle,
                )
                Text(
                    stringResource(R.string.configuration_protection_blocked_body),
                    style = GeistType.copy14,
                    color = colors.brandOnSubtle,
                )
            }
            TextButton(
                onClick = onOpenSettings,
                // The bar already exposes this action; keep one semantics node for TalkBack.
                modifier = Modifier.clearAndSetSemantics { },
            ) {
                Text(
                    stringResource(R.string.configuration_protection_open_setting),
                    style = GeistType.button14,
                    color = colors.brandPrimary,
                )
            }
        }
    }
}
