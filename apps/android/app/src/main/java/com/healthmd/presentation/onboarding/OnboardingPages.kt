package com.healthmd.presentation.onboarding

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
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
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.presentation.common.*
import com.healthmd.presentation.settings.groupRowShape
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
                    .clip(RoundedCornerShape(GeistRadii.large)),
                contentScale = ContentScale.Crop,
            )
        }
        FeatureList(
            Icons.AutoMirrored.Outlined.Article to stringResource(R.string.onboarding_welcome_feature_1),
            Icons.Outlined.Lock to stringResource(R.string.onboarding_welcome_feature_2),
            Icons.Outlined.Schedule to stringResource(R.string.onboarding_welcome_feature_3),
        )
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
            HeroIcon(Icons.Rounded.Favorite, success = hasPermissions)
        }
        actionError?.let { error ->
            HealthConnectErrorNotice(error = error, onDismiss = onDismissError)
            Spacer(Modifier.height(Spacing.md))
        }
        if (hasPermissions) {
            Text(
                stringResource(R.string.onboarding_health_connected),
                style = GeistType.heading14,
                color = LocalGeistColors.current.success,
            )
            Spacer(Modifier.height(Spacing.md))
        }
        FeatureList(
            Icons.Outlined.VisibilityOff to stringResource(R.string.onboarding_health_feature_1),
            Icons.Outlined.PhoneAndroid to stringResource(R.string.onboarding_health_feature_2),
            Icons.Outlined.CloudOff to stringResource(R.string.onboarding_health_feature_3),
        )
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
                success = folderName != null,
            )
        }
        if (folderName != null) {
            GeistCard(padding = if (reading) Spacing.sm else Spacing.md) {
                Text(
                    stringResource(R.string.onboarding_storage_selected, folderName),
                    color = LocalGeistColors.current.primary,
                    style = GeistType.copy14,
                )
                TextButton(onClick = onSelectFolder) {
                    Text(
                        stringResource(R.string.export_folder_change),
                        style = GeistType.button14,
                        color = LocalGeistColors.current.brandPrimary,
                    )
                }
            }
            Spacer(Modifier.height(Spacing.md))
        }
        GeistCard(padding = if (reading) Spacing.sm else Spacing.md) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                if (!reading) {
                    Icon(Icons.Outlined.Lightbulb, contentDescription = null, tint = LocalGeistColors.current.warning)
                    Spacer(Modifier.width(Spacing.sm))
                }
                Text(
                    stringResource(R.string.onboarding_storage_hint_obsidian),
                    style = GeistType.copy14,
                    color = LocalGeistColors.current.primary,
                )
            }
            Spacer(Modifier.height(Spacing.sm))
            Text(
                stringResource(R.string.onboarding_storage_hint_anywhere),
                style = GeistType.copy13,
                color = LocalGeistColors.current.secondary,
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
        ) { HeroIcon(Icons.Rounded.Verified, success = true) }
        Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
            IncludedAccessFeatureRow(
                Icons.Outlined.AllInclusive,
                stringResource(R.string.paywall_unlimited_exports),
                stringResource(R.string.fdroid_onboarding_no_purchase),
                shape = groupRowShape(0, 2),
            )
            IncludedAccessFeatureRow(
                Icons.Outlined.Schedule,
                stringResource(R.string.paywall_scheduled_exports),
                stringResource(R.string.fdroid_onboarding_no_play_services),
                shape = groupRowShape(1, 2),
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
        ) { HeroIcon(Icons.Rounded.Check, success = true) }
        FeatureList(
            Icons.Outlined.FileUpload to stringResource(R.string.onboarding_ready_tip_1),
            Icons.Outlined.Schedule to stringResource(R.string.onboarding_ready_tip_2),
            Icons.Outlined.Tune to stringResource(R.string.onboarding_ready_tip_3),
        )
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
        style = GeistType.heading32,
        color = LocalGeistColors.current.primary,
        textAlign = if (reading) TextAlign.Start else TextAlign.Center,
        modifier = Modifier.fillMaxWidth().semantics { heading() },
    )
    Spacer(Modifier.height(Spacing.md))
    Text(
        text = subtitle,
        style = GeistType.copy16,
        color = LocalGeistColors.current.secondary,
        textAlign = if (reading) TextAlign.Start else TextAlign.Center,
        modifier = Modifier.fillMaxWidth()
            .then(if (reading) Modifier else Modifier.padding(horizontal = Spacing.sm)),
    )
    Spacer(Modifier.height(if (reading) Spacing.md else Spacing.lg))
}

/** The centered hero: a brand tonal container, or the success tone once the step is done. */
@Composable
private fun HeroIcon(icon: ImageVector, success: Boolean = false) {
    val colors = LocalGeistColors.current
    Box(
        Modifier
            .size(GeistSpacing.space24)
            .background(if (success) colors.green.c200 else colors.brandSubtle, CircleShape),
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = if (success) colors.success else colors.brandOnSubtle,
            modifier = Modifier.size(GeistSizes.controlLarge),
        )
    }
}

/** Feature points as one list group: rows 2dp apart with 20dp outer corners. */
@Composable
private fun FeatureList(vararg features: Pair<ImageVector, String>) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(2.dp)) {
        features.forEachIndexed { index, (icon, text) ->
            FeatureRow(icon, text, groupRowShape(index, features.size))
        }
    }
}

@Composable
private fun FeatureRow(icon: ImageVector, text: String, shape: Shape) {
    val reading = LocalOnboardingReadingLayout.current
    val colors = LocalGeistColors.current
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.background200)
            .heightIn(min = 56.dp)
            .padding(horizontal = if (reading) Spacing.sm else Spacing.md, vertical = Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (!reading) {
            Icon(icon, contentDescription = null, tint = colors.brandPrimary)
            Spacer(Modifier.width(Spacing.md))
        }
        Text(text, style = GeistType.copy14, color = colors.primary)
    }
}

@Composable
private fun IncludedAccessFeatureRow(icon: ImageVector, title: String, description: String, shape: Shape) {
    val reading = LocalOnboardingReadingLayout.current
    val colors = LocalGeistColors.current
    Row(
        Modifier
            .fillMaxWidth()
            .clip(shape)
            .background(colors.background200)
            .heightIn(min = 72.dp)
            .padding(horizontal = if (reading) Spacing.sm else Spacing.md, vertical = Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        if (!reading) {
            Icon(icon, contentDescription = null, tint = colors.brandPrimary)
            Spacer(Modifier.width(Spacing.md))
        }
        Column(Modifier.weight(1f)) {
            Text(title, style = GeistType.label16, color = colors.primary)
            Text(description, style = GeistType.copy14, color = colors.secondary)
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
            .padding(horizontal = Spacing.md, vertical = Spacing.md),
        horizontalAlignment = if (reading) Alignment.Start else Alignment.CenterHorizontally,
        verticalArrangement = if (reading) Arrangement.Top else Arrangement.Center,
        content = content,
    )
}
