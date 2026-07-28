package com.healthmd.presentation.paywall

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp

import com.healthmd.R
import com.healthmd.presentation.common.*
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Radii
import com.healthmd.presentation.theme.Spacing

/**
 * Full-screen paywall shown when user hits a premium feature gate.
 * 
 * Features:
 * - Shows live price from Google Play productDetails
 * - Purchase and restore actions, plus an optional close action for standalone use
 * - Loading states for purchase and restore operations
 * - Error message display
 * - Auto-dismiss on successful unlock (handled in navigation)
 * - Debug controls in debug builds
 */
@Composable
fun PaywallScreen(
    onPurchase: () -> Unit,
    onRestore: () -> Unit,
    onDismiss: (() -> Unit)?,
    isPurchasing: Boolean = false,
    isRestoring: Boolean = false,
    priceText: String? = null,
    errorMessage: String? = null,
    onClearError: () -> Unit = {},
    subtitle: String? = null,
    // Debug props
    isDebugBuild: Boolean = false,
    debugUnlockOverride: Boolean? = null,
    onDebugToggleUnlock: () -> Unit = {},
    onDebugResetState: () -> Unit = {},
) {
    val isLoading = isPurchasing || isRestoring
    val scrollState = rememberScrollState()

    // Clear error when user starts a new action
    LaunchedEffect(isPurchasing, isRestoring) {
        if (isPurchasing || isRestoring) {
            onClearError()
        }
    }

    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.bgPrimary)
            .verticalScroll(scrollState)
            .padding(horizontal = Spacing.md, vertical = Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        if (onDismiss != null) {
            Row(
                modifier = Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.End,
            ) {
                IconButton(
                    onClick = onDismiss,
                    enabled = !isLoading,
                ) {
                    Icon(
                        Icons.Filled.Close,
                        contentDescription = stringResource(R.string.close),
                        tint = AppColors.textMuted,
                    )
                }
            }

            Spacer(modifier = Modifier.height(Spacing.lg))
        }

        Image(
            painter = painterResource(id = R.drawable.app_icon),
            contentDescription = stringResource(R.string.app_name),
            modifier = Modifier
                .size(96.dp)
                .clip(RoundedCornerShape(Radii.card))
                .border(1.dp, AppColors.borderDefault, RoundedCornerShape(Radii.card)),
            contentScale = ContentScale.Crop,
        )

        Spacer(modifier = Modifier.height(Spacing.lg))

        Text(
            text = stringResource(R.string.paywall_title),
            style = MaterialTheme.typography.headlineLarge,
            color = AppColors.textPrimary,
        )

        Spacer(modifier = Modifier.height(Spacing.xs))

        Text(
            text = subtitle ?: stringResource(R.string.paywall_subtitle),
            style = MaterialTheme.typography.bodyLarge,
            color = AppColors.textSecondary,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(Spacing.lg))

        // Feature list
        GeistCard {
            FeatureRow(Icons.Outlined.AllInclusive, stringResource(R.string.paywall_unlimited_exports))
            Spacer(modifier = Modifier.height(Spacing.sm))
            FeatureRow(Icons.Outlined.Schedule, stringResource(R.string.paywall_scheduled_exports))
            Spacer(modifier = Modifier.height(Spacing.sm))
            FeatureRow(Icons.Outlined.AutoAwesome, stringResource(R.string.paywall_future_features))
            Spacer(modifier = Modifier.height(Spacing.sm))
            FeatureRow(Icons.Outlined.Payment, stringResource(R.string.paywall_one_time))
        }

        Spacer(modifier = Modifier.weight(1f))

        // Error message
        if (errorMessage != null) {
            GeistCard(
                modifier = Modifier.padding(bottom = Spacing.sm),
            ) {
                Row(
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
                ) {
                    Icon(
                        Icons.Outlined.Warning,
                        contentDescription = null,
                        tint = AppColors.error,
                        modifier = Modifier.size(20.dp),
                    )
                    Text(
                        text = errorMessage,
                        style = MaterialTheme.typography.bodySmall,
                        color = AppColors.error,
                    )
                }
            }
        }

        // Purchase button with live price
        val buttonText = when {
            isPurchasing -> stringResource(R.string.paywall_purchasing)
            priceText != null -> stringResource(R.string.paywall_unlock_button_price, priceText)
            else -> stringResource(R.string.paywall_unlock_button)
        }

        PrimaryButton(
            text = buttonText,
            onClick = onPurchase,
            isLoading = isPurchasing,
            enabled = !isLoading,
        )

        Spacer(modifier = Modifier.height(Spacing.sm))

        // Restore button
        if (isRestoring) {
            Row(
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
            ) {
                CircularProgressIndicator(
                    modifier = Modifier.size(16.dp),
                    color = AppColors.accent,
                    strokeWidth = 2.dp,
                )
                Text(
                    text = stringResource(R.string.paywall_restoring),
                    color = AppColors.accent,
                    style = MaterialTheme.typography.labelLarge,
                )
            }
        } else {
            TextButton(
                onClick = onRestore,
                enabled = !isLoading,
            ) {
                Text(
                    text = stringResource(R.string.paywall_restore),
                    color = if (isLoading) AppColors.textMuted else AppColors.accent,
                    style = MaterialTheme.typography.labelLarge,
                )
            }
        }

        // Debug controls (debug builds only)
        if (isDebugBuild) {
            Spacer(modifier = Modifier.height(Spacing.lg))
            DebugPurchaseControls(
                debugUnlockOverride = debugUnlockOverride,
                onToggleUnlock = onDebugToggleUnlock,
                onResetState = onDebugResetState,
            )
        }

        Spacer(modifier = Modifier.height(Spacing.md))
    }
}

@Composable
private fun FeatureRow(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(
            icon,
            contentDescription = null,
            tint = AppColors.accent,
            modifier = Modifier.size(24.dp),
        )
        Spacer(modifier = Modifier.width(Spacing.sm))
        Text(
            text = text,
            style = MaterialTheme.typography.bodyLarge,
            color = AppColors.textPrimary,
        )
    }
}

/**
 * Debug controls for testing purchase states.
 * Only shown in debug builds.
 */
@Composable
private fun DebugPurchaseControls(
    debugUnlockOverride: Boolean?,
    onToggleUnlock: () -> Unit,
    onResetState: () -> Unit,
) {
    GeistCard {
        Row(
            modifier = Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Icon(
                Icons.Outlined.BugReport,
                contentDescription = null,
                tint = AppColors.warning,
                modifier = Modifier.size(20.dp),
            )
            Spacer(modifier = Modifier.width(Spacing.sm))
            Text(
                text = stringResource(R.string.debug_purchase_title),
                style = MaterialTheme.typography.titleSmall,
                fontWeight = FontWeight.SemiBold,
                color = AppColors.warning,
            )
        }
        
        Spacer(modifier = Modifier.height(Spacing.sm))
        HorizontalDivider(color = AppColors.borderDefault)
        Spacer(modifier = Modifier.height(Spacing.sm))

        // Current debug state
        val stateText = when (debugUnlockOverride) {
            true -> stringResource(R.string.debug_state_unlocked)
            false -> stringResource(R.string.debug_state_locked)
            null -> stringResource(R.string.debug_state_normal)
        }
        Text(
            text = stringResource(R.string.debug_current_state, stateText),
            style = MaterialTheme.typography.bodySmall,
            color = AppColors.textSecondary,
        )

        Spacer(modifier = Modifier.height(Spacing.sm))

        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
        ) {
            SecondaryButton(
                text = stringResource(R.string.debug_toggle_unlock),
                onClick = onToggleUnlock,
                modifier = Modifier.weight(1f),
            )
            SecondaryButton(
                text = stringResource(R.string.debug_reset_state),
                onClick = onResetState,
                modifier = Modifier.weight(1f),
            )
        }
    }
}
