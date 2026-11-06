package com.healthmd.presentation.onboarding

import androidx.compose.foundation.Image
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.Article
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.presentation.common.*
import com.healthmd.presentation.theme.*

@Composable
internal fun WelcomePage(onUseSharedSetup: () -> Unit) {
    OnboardingPageColumn {
        OnboardingPageHeader(
            title = stringResource(R.string.onboarding_welcome_title),
            subtitle = stringResource(R.string.onboarding_welcome_subtitle),
        ) {
            Image(
                painter = painterResource(R.drawable.app_icon),
                contentDescription = null,
                modifier = Modifier.size(GeistSpacing.space24)
                    .clip(RoundedCornerShape(Radii.card))
                    .border(1.dp, AppColors.borderDefault, RoundedCornerShape(Radii.card)),
                contentScale = ContentScale.Crop,
            )
        }
        FeatureList {
            FeaturePill(Icons.AutoMirrored.Outlined.Article, stringResource(R.string.onboarding_welcome_feature_1))
            FeaturePill(Icons.Outlined.Lock, stringResource(R.string.onboarding_welcome_feature_2))
            FeaturePill(Icons.Outlined.Schedule, stringResource(R.string.onboarding_welcome_feature_3))
        }
        Spacer(Modifier.height(Spacing.md))
        SecondaryButton(
            text = stringResource(R.string.shared_setup_use),
            onClick = onUseSharedSetup,
            icon = Icons.Outlined.FileOpen,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
internal fun HealthAccessPage(
    hasPermissions: Boolean,
    actionError: HealthConnectActionError?,
    onDismissError: () -> Unit,
) {
    OnboardingPageColumn {
        OnboardingPageHeader(
            title = stringResource(R.string.onboarding_health_title),
            subtitle = stringResource(R.string.onboarding_health_subtitle),
        ) {
            HeroIcon(Icons.Rounded.Favorite, if (hasPermissions) AppColors.success else AppColors.accent)
        }
        actionError?.let { error ->
            HealthConnectErrorNotice(error = error, onDismiss = onDismissError)
            Spacer(Modifier.height(Spacing.md))
        }
        if (hasPermissions) {
            Text(
                stringResource(R.string.onboarding_health_connected),
                style = MaterialTheme.typography.labelLarge,
                color = AppColors.success,
                fontWeight = FontWeight.SemiBold,
            )
            Spacer(Modifier.height(Spacing.md))
        }
        FeatureList {
            FeaturePill(Icons.Outlined.VisibilityOff, stringResource(R.string.onboarding_health_feature_1))
            FeaturePill(Icons.Outlined.PhoneAndroid, stringResource(R.string.onboarding_health_feature_2))
            FeaturePill(Icons.Outlined.CloudOff, stringResource(R.string.onboarding_health_feature_3))
        }
    }
}

@Composable
internal fun StorageSetupPage(folderName: String?, onSelectFolder: () -> Unit) {
    val reading = LocalOnboardingReadingLayout.current
    OnboardingPageColumn {
        OnboardingPageHeader(
            title = stringResource(R.string.onboarding_storage_title),
            subtitle = stringResource(R.string.onboarding_storage_subtitle),
        ) {
            HeroIcon(
                if (folderName != null) Icons.Rounded.FolderOpen else Icons.Outlined.Folder,
                if (folderName != null) AppColors.success else AppColors.accent,
            )
        }
        if (folderName != null) {
            GeistCard(padding = if (reading) Spacing.sm else Spacing.md) {
                Text(
                    stringResource(R.string.onboarding_storage_selected, folderName),
                    color = AppColors.textPrimary,
                    style = MaterialTheme.typography.bodyMedium,
                )
                TextButton(onClick = onSelectFolder) {
                    Text(stringResource(R.string.export_folder_change), color = AppColors.accent)
                }
            }
            Spacer(Modifier.height(Spacing.md))
        }
        GeistCard(padding = if (reading) Spacing.sm else Spacing.md) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (!reading) {
                    Icon(Icons.Outlined.Lightbulb, contentDescription = null, tint = AppColors.warning)
                    Spacer(Modifier.width(Spacing.sm))
                }
                Text(
                    stringResource(R.string.onboarding_storage_hint_obsidian),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
            }
            Spacer(Modifier.height(Spacing.sm))
            Text(
                stringResource(R.string.onboarding_storage_hint_anywhere),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textSecondary,
                modifier = if (reading) Modifier else Modifier.padding(start = Spacing.xl),
            )
        }
    }
}

@Composable
internal fun IncludedAccessPage() {
    OnboardingPageColumn {
        OnboardingPageHeader(
            title = stringResource(R.string.fdroid_onboarding_access_title),
            subtitle = stringResource(R.string.fdroid_onboarding_access_body),
        ) { HeroIcon(Icons.Rounded.Verified, AppColors.success) }
        GeistCard(padding = if (LocalOnboardingReadingLayout.current) Spacing.sm else Spacing.lg) {
            IncludedAccessFeatureRow(
                Icons.Outlined.AllInclusive,
                stringResource(R.string.paywall_unlimited_exports),
                stringResource(R.string.fdroid_onboarding_no_purchase),
            )
            Spacer(Modifier.height(Spacing.sm))
            IncludedAccessFeatureRow(
                Icons.Outlined.Schedule,
                stringResource(R.string.paywall_scheduled_exports),
                stringResource(R.string.fdroid_onboarding_no_play_services),
            )
        }
    }
}

@Composable
internal fun ReadyPage() {
    OnboardingPageColumn {
        OnboardingPageHeader(
            title = stringResource(R.string.onboarding_ready_title),
            subtitle = stringResource(R.string.onboarding_ready_subtitle),
        ) { HeroIcon(Icons.Rounded.Check, AppColors.success) }
        FeatureList {
            FeaturePill(Icons.Outlined.FileUpload, stringResource(R.string.onboarding_ready_tip_1))
            FeaturePill(Icons.Outlined.Schedule, stringResource(R.string.onboarding_ready_tip_2))
            FeaturePill(Icons.Outlined.Tune, stringResource(R.string.onboarding_ready_tip_3))
        }
    }
}

@Composable
private fun OnboardingPageHeader(
    title: String,
    subtitle: String,
    hero: @Composable () -> Unit,
) {
    val reading = LocalOnboardingReadingLayout.current
    if (!reading) {
        Box(Modifier.testTag(OnboardingTestTags.HERO)) { hero() }
        Spacer(Modifier.height(Spacing.xl))
    }
    Text(
        // Let the available width choose line breaks instead of the marketing layout.
        text = if (reading) title.replace('\n', ' ') else title,
        style = MaterialTheme.typography.headlineLarge,
        color = AppColors.textPrimary,
        textAlign = if (reading) TextAlign.Start else TextAlign.Center,
        modifier = Modifier.fillMaxWidth().semantics { heading() },
    )
    Spacer(Modifier.height(Spacing.md))
    Text(
        text = subtitle,
        style = MaterialTheme.typography.bodyLarge,
        color = AppColors.textSecondary,
        textAlign = if (reading) TextAlign.Start else TextAlign.Center,
        modifier = Modifier.fillMaxWidth()
            .then(if (reading) Modifier else Modifier.padding(horizontal = Spacing.sm)),
    )
    Spacer(Modifier.height(if (reading) Spacing.md else Spacing.lg))
}

@Composable
private fun HeroIcon(icon: ImageVector, tint: Color) {
    GeistIconCircle(size = GeistSpacing.space24) {
        Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(GeistSizes.controlLarge))
    }
}

@Composable
private fun FeatureList(content: @Composable ColumnScope.() -> Unit) {
    Column(
        verticalArrangement = Arrangement.spacedBy(
            if (LocalOnboardingReadingLayout.current) Spacing.xs else Spacing.sm,
        ),
        content = content,
    )
}

@Composable
private fun FeaturePill(icon: ImageVector, text: String) {
    val reading = LocalOnboardingReadingLayout.current
    GeistCard(padding = if (reading) Spacing.sm else Spacing.md) {
        Row(verticalAlignment = Alignment.CenterVertically) {
            if (!reading) {
                Icon(icon, contentDescription = null, tint = AppColors.accent)
                Spacer(Modifier.width(Spacing.sm))
            }
            Text(text, style = MaterialTheme.typography.bodyMedium, color = AppColors.textSecondary)
        }
    }
}

@Composable
private fun IncludedAccessFeatureRow(icon: ImageVector, title: String, description: String) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        if (!LocalOnboardingReadingLayout.current) {
            Icon(icon, contentDescription = null, tint = AppColors.accent)
            Spacer(Modifier.width(Spacing.sm))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = MaterialTheme.typography.bodyLarge, color = AppColors.textPrimary,
                fontWeight = FontWeight.Medium)
            Text(description, style = MaterialTheme.typography.bodySmall, color = AppColors.textSecondary)
        }
    }
}

@Composable
private fun OnboardingPageColumn(content: @Composable ColumnScope.() -> Unit) {
    val reading = LocalOnboardingReadingLayout.current
    Column(
        modifier = Modifier.fillMaxSize()
            .testTag(OnboardingTestTags.BODY)
            .verticalScroll(rememberScrollState())
            .padding(horizontal = if (reading) Spacing.md else Spacing.lg, vertical = Spacing.md),
        horizontalAlignment = if (reading) Alignment.Start else Alignment.CenterHorizontally,
        verticalArrangement = if (reading) Arrangement.Top else Arrangement.Center,
        content = content,
    )
}
