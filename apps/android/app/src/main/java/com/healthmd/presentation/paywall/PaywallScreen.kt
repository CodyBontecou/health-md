package com.healthmd.presentation.paywall

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material.icons.outlined.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.healthmd.R
import com.healthmd.presentation.common.*
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import androidx.compose.ui.res.stringResource

@Composable
fun PaywallScreen(
    onPurchase: () -> Unit,
    onRestore: () -> Unit,
    onDismiss: () -> Unit,
    isLoading: Boolean = false,
    errorMessage: String? = null,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.bgPrimary)
            .padding(horizontal = Spacing.md, vertical = Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        // Dismiss button
        Row(
            modifier = Modifier.fillMaxWidth(),
            horizontalArrangement = Arrangement.End,
        ) {
            IconButton(onClick = onDismiss) {
                Icon(Icons.Filled.Close, stringResource(R.string.close), tint = AppColors.textMuted)
            }
        }

        Spacer(modifier = Modifier.height(Spacing.lg))

        // App icon with glow
        Box(contentAlignment = Alignment.Center) {
            Box(
                modifier = Modifier
                    .size(120.dp)
                    .clip(RoundedCornerShape(30.dp))
                    .background(AppColors.accent.copy(alpha = 0.25f)),
            )
            Image(
                painter = painterResource(id = R.drawable.app_icon),
                contentDescription = stringResource(R.string.app_name),
                modifier = Modifier
                    .size(110.dp)
                    .shadow(16.dp, RoundedCornerShape(26.dp), ambientColor = AppColors.accent.copy(alpha = 0.4f))
                    .clip(RoundedCornerShape(26.dp))
                    .border(1.dp, Color.White.copy(alpha = 0.30f), RoundedCornerShape(26.dp)),
                contentScale = ContentScale.Crop,
            )
        }

        Spacer(modifier = Modifier.height(Spacing.lg))

        Text(
            stringResource(R.string.paywall_title),
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.Bold,
            color = AppColors.textPrimary,
            letterSpacing = 2.sp,
        )

        Spacer(modifier = Modifier.height(Spacing.xs))

        Text(
            stringResource(R.string.paywall_subtitle),
            style = MaterialTheme.typography.bodyLarge,
            color = AppColors.textSecondary,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(Spacing.lg))

        // Feature list
        GlassCard {
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
        errorMessage?.let {
            Text(
                it,
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.error,
                textAlign = TextAlign.Center,
                modifier = Modifier.padding(bottom = Spacing.sm),
            )
        }

        // Purchase button
        PrimaryButton(
            text = stringResource(R.string.paywall_unlock_button),
            onClick = onPurchase,
            isLoading = isLoading,
            enabled = !isLoading,
        )

        Spacer(modifier = Modifier.height(Spacing.sm))

        // Restore button
        TextButton(onClick = onRestore) {
            Text(
                stringResource(R.string.paywall_restore),
                color = AppColors.accent,
                style = MaterialTheme.typography.labelLarge,
            )
        }

        Spacer(modifier = Modifier.height(Spacing.md))
    }
}

@Composable
private fun FeatureRow(icon: ImageVector, text: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Icon(icon, contentDescription = null, tint = AppColors.accent, modifier = Modifier.size(24.dp))
        Spacer(modifier = Modifier.width(Spacing.sm))
        Text(text, style = MaterialTheme.typography.bodyLarge, color = AppColors.textPrimary)
    }
}
