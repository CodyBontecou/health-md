package com.healthmd.presentation.onboarding

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.*
import androidx.compose.animation.core.*
import androidx.compose.foundation.*
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.*
import androidx.compose.material.icons.rounded.*
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.presentation.common.*
import com.healthmd.presentation.paywall.PaywallScreen
import com.healthmd.presentation.paywall.PaywallViewModel
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistMotion
import com.healthmd.presentation.theme.Radii
import com.healthmd.presentation.theme.Spacing
import kotlinx.coroutines.launch
import kotlin.math.absoluteValue

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun OnboardingScreen(
    viewModel: OnboardingViewModel = hiltViewModel(),
    paywallViewModel: PaywallViewModel = hiltViewModel(),
    onComplete: () -> Unit,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val isUnlocked by paywallViewModel.isUnlocked.collectAsStateWithLifecycle()
    val isPurchasing by paywallViewModel.isPurchasing.collectAsStateWithLifecycle()
    val isRestoring by paywallViewModel.isRestoring.collectAsStateWithLifecycle()
    val purchaseError by paywallViewModel.purchaseError.collectAsStateWithLifecycle()
    val priceText by paywallViewModel.priceText.collectAsStateWithLifecycle()
    val debugUnlockOverride by paywallViewModel.debugUnlockOverride.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()
    var advanceAfterUnlock by remember { mutableStateOf(false) }

    val healthConnectManager = remember { HealthConnectManager(context) }
    val permissionContract = remember { healthConnectManager.getPermissionContract() }
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = permissionContract,
    ) { viewModel.refreshPermissions() }

    val folderPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree(),
    ) { uri -> uri?.let { viewModel.onFolderSelected(it) } }

    val pagerState = rememberPagerState(pageCount = { 5 })

    // Key auto-advance to the settled page. currentPage changes around the halfway
    // point of an animation, which would cancel this effect and leave the pager mid-swipe.
    LaunchedEffect(uiState.hasPermissions, pagerState.settledPage) {
        if (pagerState.settledPage == 1 && uiState.hasPermissions) {
            kotlinx.coroutines.delay(800)
            pagerState.animateScrollToPage(2)
        }
    }

    LaunchedEffect(uiState.folderName, pagerState.settledPage) {
        if (pagerState.settledPage == 2 && uiState.folderName != null) {
            kotlinx.coroutines.delay(800)
            pagerState.animateScrollToPage(3)
        }
    }

    // Only advance for an unlock initiated from this page. Existing purchasers
    // should still see the onboarding paywall instead of being immediately skipped.
    LaunchedEffect(isUnlocked, advanceAfterUnlock, pagerState.settledPage) {
        if (isUnlocked && advanceAfterUnlock && pagerState.settledPage == 3) {
            advanceAfterUnlock = false
            pagerState.animateScrollToPage(4)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.bgPrimary),
    ) {
        Column(
            modifier = Modifier.fillMaxSize(),
        ) {
            // Page indicators at top
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = Spacing.xxl, bottom = Spacing.lg),
                horizontalArrangement = Arrangement.Center,
            ) {
                repeat(5) { index ->
                    val selected = pagerState.currentPage == index
                    val width by animateDpAsState(
                        targetValue = if (selected) 24.dp else 8.dp,
                        animationSpec = tween(
                            durationMillis = GeistMotion.stateChange,
                            easing = GeistMotion.easing,
                        ),
                        label = "indicatorWidth",
                    )
                    Box(
                        modifier = Modifier
                            .padding(horizontal = Spacing.xxs)
                            .height(8.dp)
                            .width(width)
                            .clip(CircleShape)
                            .background(
                                if (selected) AppColors.accent
                                else AppColors.borderStrong
                            ),
                    )
                }
            }

            // Pager content
            HorizontalPager(
                state = pagerState,
                modifier = Modifier.weight(1f),
                userScrollEnabled = true,
            ) { page ->
                val pageOffset = (pagerState.currentPage - page) + pagerState.currentPageOffsetFraction

                Box(
                    modifier = Modifier
                        .fillMaxSize()
                        .graphicsLayer {
                            alpha = 1f - pageOffset.absoluteValue.coerceIn(0f, 1f) * 0.4f
                            translationX = pageOffset * 100
                        },
                ) {
                    when (page) {
                        0 -> WelcomePage()
                        1 -> HealthAccessPage(
                            hasPermissions = uiState.hasPermissions,
                            healthConnectAvailable = uiState.healthConnectAvailable,
                            healthConnectNeedsSetup = uiState.healthConnectNeedsSetup,
                            onGrantPermissions = {
                                if (!uiState.healthConnectAvailable) {
                                    context.startActivity(healthConnectManager.getInstallIntent())
                                } else if (uiState.healthConnectNeedsSetup) {
                                    context.startActivity(healthConnectManager.getOpenHealthConnectIntent())
                                } else {
                                    permissionLauncher.launch(healthConnectManager.permissions)
                                }
                            },
                        )
                        2 -> StorageSetupPage(
                            folderName = uiState.folderName,
                            onSelectFolder = { folderPickerLauncher.launch(null) },
                        )
                        3 -> PaywallScreen(
                            onPurchase = {
                                (context as? Activity)?.let { activity ->
                                    advanceAfterUnlock = !isUnlocked
                                    paywallViewModel.launchPurchaseFlow(activity)
                                }
                            },
                            onRestore = {
                                advanceAfterUnlock = !isUnlocked
                                paywallViewModel.restorePurchases()
                            },
                            onDismiss = null,
                            isPurchasing = isPurchasing,
                            isRestoring = isRestoring,
                            priceText = priceText,
                            errorMessage = purchaseError,
                            onClearError = paywallViewModel::clearError,
                            subtitle = stringResource(R.string.schedule_unlock_required_body),
                            isDebugBuild = paywallViewModel.isDebugBuild,
                            debugUnlockOverride = debugUnlockOverride,
                            onDebugToggleUnlock = {
                                advanceAfterUnlock = !isUnlocked
                                paywallViewModel.debugToggleUnlock()
                            },
                            onDebugResetState = paywallViewModel::debugResetPurchaseState,
                        )
                        4 -> ReadyPage(
                            onComplete = {
                                viewModel.completeOnboarding()
                                onComplete()
                            },
                        )
                    }
                }
            }

            // Bottom navigation
            OnboardingBottomBar(
                currentPage = pagerState.currentPage,
                canContinue = when (pagerState.currentPage) {
                    1 -> true
                    2 -> uiState.folderName != null
                    else -> true
                },
                onBack = {
                    coroutineScope.launch {
                        pagerState.animateScrollToPage(pagerState.currentPage - 1)
                    }
                },
                onContinue = {
                    coroutineScope.launch {
                        if (pagerState.currentPage < 4) {
                            pagerState.animateScrollToPage(pagerState.currentPage + 1)
                        }
                    }
                },
                onSkip = {
                    coroutineScope.launch {
                        pagerState.animateScrollToPage(pagerState.currentPage + 1)
                    }
                },
            )
        }
    }
}

@Composable
private fun WelcomePage() {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Image(
            painter = painterResource(id = R.drawable.app_icon),
            contentDescription = stringResource(R.string.app_name),
            modifier = Modifier
                .size(96.dp)
                .clip(RoundedCornerShape(Radii.card))
                .border(1.dp, AppColors.borderDefault, RoundedCornerShape(Radii.card)),
            contentScale = ContentScale.Crop,
        )

        Spacer(modifier = Modifier.height(Spacing.xl))

        Text(
            text = stringResource(R.string.onboarding_welcome_title),
            style = MaterialTheme.typography.headlineLarge,
            color = AppColors.textPrimary,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(Spacing.md))

        Text(
            text = stringResource(R.string.onboarding_welcome_subtitle),
            style = MaterialTheme.typography.bodyLarge,
            color = AppColors.textSecondary,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = Spacing.md),
        )

        Spacer(modifier = Modifier.height(Spacing.xl))

        // Feature rows
        FeaturePill(
            icon = Icons.Outlined.Article,
            text = stringResource(R.string.onboarding_welcome_feature_1),
        )
        Spacer(modifier = Modifier.height(Spacing.sm))
        FeaturePill(
            icon = Icons.Outlined.Lock,
            text = stringResource(R.string.onboarding_welcome_feature_2),
        )
        Spacer(modifier = Modifier.height(Spacing.sm))
        FeaturePill(
            icon = Icons.Outlined.Schedule,
            text = stringResource(R.string.onboarding_welcome_feature_3),
        )
    }
}

@Composable
private fun HealthAccessPage(
    hasPermissions: Boolean,
    healthConnectAvailable: Boolean,
    healthConnectNeedsSetup: Boolean,
    onGrantPermissions: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Box(
                modifier = Modifier
                    .size(100.dp)
                    .clip(CircleShape)
                    .background(AppColors.bgTertiary)
                    .border(1.dp, AppColors.borderDefault, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Rounded.Favorite,
                    contentDescription = null,
                    tint = if (hasPermissions) AppColors.success else AppColors.accent,
                    modifier = Modifier.size(48.dp),
                )
            }
            // Checkmark overlay when connected
            if (hasPermissions) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .offset(x = 8.dp, y = 8.dp)
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(AppColors.success)
                        .border(2.dp, AppColors.bgPrimary, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Rounded.Check,
                        contentDescription = null,
                        tint = AppColors.onSuccess,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(Spacing.xl))

        Text(
            text = stringResource(R.string.onboarding_health_title),
            style = MaterialTheme.typography.headlineLarge,
            color = AppColors.textPrimary,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(Spacing.md))

        Text(
            text = stringResource(R.string.onboarding_health_subtitle),
            style = MaterialTheme.typography.bodyLarge,
            color = AppColors.textSecondary,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = Spacing.sm),
        )

        Spacer(modifier = Modifier.height(Spacing.lg))

        // Privacy features
        FeaturePill(
            icon = Icons.Outlined.VisibilityOff,
            text = stringResource(R.string.onboarding_health_feature_1),
        )
        Spacer(modifier = Modifier.height(Spacing.sm))
        FeaturePill(
            icon = Icons.Outlined.PhoneAndroid,
            text = stringResource(R.string.onboarding_health_feature_2),
        )
        Spacer(modifier = Modifier.height(Spacing.sm))
        FeaturePill(
            icon = Icons.Outlined.CloudOff,
            text = stringResource(R.string.onboarding_health_feature_3),
        )

        Spacer(modifier = Modifier.height(Spacing.xl))

        // Action button or status
        AnimatedContent(
            targetState = hasPermissions,
            transitionSpec = {
                fadeIn(animationSpec = tween(300)) togetherWith
                    fadeOut(animationSpec = tween(300))
            },
            label = "permissionState",
        ) { connected ->
            if (connected) {
                GeistBadge(borderColor = AppColors.successBorder) {
                    Icon(
                        Icons.Rounded.CheckCircle,
                        contentDescription = null,
                        tint = AppColors.success,
                        modifier = Modifier.size(18.dp),
                    )
                    Spacer(modifier = Modifier.width(Spacing.sm))
                    Text(
                        stringResource(R.string.onboarding_health_connected),
                        color = AppColors.success,
                        style = MaterialTheme.typography.labelLarge,
                        fontWeight = FontWeight.SemiBold,
                    )
                }
            } else {
                PrimaryButton(
                    text = stringResource(R.string.onboarding_health_grant_button),
                    onClick = onGrantPermissions,
                    icon = Icons.Outlined.Favorite,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@Composable
private fun StorageSetupPage(
    folderName: String?,
    onSelectFolder: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Box(contentAlignment = Alignment.Center) {
            Box(
                modifier = Modifier
                    .size(96.dp)
                    .clip(RoundedCornerShape(Radii.card))
                    .background(AppColors.bgTertiary)
                    .border(1.dp, AppColors.borderDefault, RoundedCornerShape(Radii.card)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (folderName != null) Icons.Rounded.FolderOpen else Icons.Outlined.Folder,
                    contentDescription = null,
                    tint = if (folderName != null) AppColors.success else AppColors.accent,
                    modifier = Modifier.size(48.dp),
                )
            }
            // Checkmark when selected
            if (folderName != null) {
                Box(
                    modifier = Modifier
                        .align(Alignment.BottomEnd)
                        .offset(x = 8.dp, y = 8.dp)
                        .size(32.dp)
                        .clip(CircleShape)
                        .background(AppColors.success)
                        .border(2.dp, AppColors.bgPrimary, CircleShape),
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        Icons.Rounded.Check,
                        contentDescription = null,
                        tint = AppColors.onSuccess,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(Spacing.xl))

        Text(
            text = stringResource(R.string.onboarding_storage_title),
            style = MaterialTheme.typography.headlineLarge,
            color = AppColors.textPrimary,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(Spacing.md))

        Text(
            text = stringResource(R.string.onboarding_storage_subtitle),
            style = MaterialTheme.typography.bodyLarge,
            color = AppColors.textSecondary,
            textAlign = TextAlign.Center,
            modifier = Modifier.padding(horizontal = Spacing.sm),
        )

        Spacer(modifier = Modifier.height(Spacing.lg))

        // Hints
        GeistCard(padding = Spacing.md) {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Icon(
                    Icons.Outlined.Lightbulb,
                    contentDescription = null,
                    tint = AppColors.warning,
                    modifier = Modifier.size(20.dp),
                )
                Spacer(modifier = Modifier.width(Spacing.sm))
                Text(
                    stringResource(R.string.onboarding_storage_hint_obsidian),
                    style = MaterialTheme.typography.bodyMedium,
                    color = AppColors.textSecondary,
                )
            }
            Spacer(modifier = Modifier.height(Spacing.sm))
            Text(
                stringResource(R.string.onboarding_storage_hint_anywhere),
                style = MaterialTheme.typography.bodySmall,
                color = AppColors.textMuted,
                modifier = Modifier.padding(start = Spacing.xl),
            )
        }

        Spacer(modifier = Modifier.height(Spacing.lg))

        // Action button or status
        AnimatedContent(
            targetState = folderName,
            transitionSpec = {
                fadeIn(animationSpec = tween(300)) togetherWith
                    fadeOut(animationSpec = tween(300))
            },
            label = "folderState",
        ) { name ->
            if (name != null) {
                Column(horizontalAlignment = Alignment.CenterHorizontally) {
                    GeistBadge(borderColor = AppColors.successBorder) {
                        Icon(
                            Icons.Rounded.Folder,
                            contentDescription = null,
                            tint = AppColors.success,
                            modifier = Modifier.size(18.dp),
                        )
                        Spacer(modifier = Modifier.width(Spacing.sm))
                        Text(
                            stringResource(R.string.onboarding_storage_selected, name),
                            color = AppColors.textPrimary,
                            style = MaterialTheme.typography.labelLarge,
                        )
                    }
                    Spacer(modifier = Modifier.height(Spacing.sm))
                    TextButton(onClick = onSelectFolder) {
                        Text(
                            stringResource(R.string.export_folder_change),
                            color = AppColors.accent,
                        )
                    }
                }
            } else {
                PrimaryButton(
                    text = stringResource(R.string.onboarding_storage_select_button),
                    onClick = onSelectFolder,
                    icon = Icons.Outlined.FolderOpen,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
    }
}

@Composable
private fun ReadyPage(
    onComplete: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        GeistIconCircle(size = 96.dp) {
            Icon(
                Icons.Rounded.Check,
                contentDescription = null,
                tint = AppColors.success,
                modifier = Modifier.size(40.dp),
            )
        }

        Spacer(modifier = Modifier.height(Spacing.xl))

        Text(
            text = stringResource(R.string.onboarding_ready_title),
            style = MaterialTheme.typography.headlineLarge,
            color = AppColors.textPrimary,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(Spacing.md))

        Text(
            text = stringResource(R.string.onboarding_ready_subtitle),
            style = MaterialTheme.typography.bodyLarge,
            color = AppColors.textSecondary,
            textAlign = TextAlign.Center,
        )

        Spacer(modifier = Modifier.height(Spacing.xl))

        // Tips
        FeaturePill(
            icon = Icons.Outlined.FileUpload,
            text = stringResource(R.string.onboarding_ready_tip_1),
        )
        Spacer(modifier = Modifier.height(Spacing.sm))
        FeaturePill(
            icon = Icons.Outlined.Schedule,
            text = stringResource(R.string.onboarding_ready_tip_2),
        )
        Spacer(modifier = Modifier.height(Spacing.sm))
        FeaturePill(
            icon = Icons.Outlined.Tune,
            text = stringResource(R.string.onboarding_ready_tip_3),
        )

        Spacer(modifier = Modifier.height(Spacing.xl))

        PrimaryButton(
            text = stringResource(R.string.onboarding_ready_start_button),
            onClick = onComplete,
            icon = Icons.Outlined.RocketLaunch,
            modifier = Modifier.fillMaxWidth(),
        )
    }
}

@Composable
private fun FeaturePill(
    icon: ImageVector,
    text: String,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(Radii.card))
            .background(AppColors.bgTertiary)
            .border(1.dp, AppColors.borderDefault, RoundedCornerShape(Radii.card))
            .padding(horizontal = Spacing.md, vertical = Spacing.sm),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Icon(
            icon,
            contentDescription = null,
            tint = AppColors.accent,
            modifier = Modifier.size(20.dp),
        )
        Spacer(modifier = Modifier.width(Spacing.sm))
        Text(
            text,
            style = MaterialTheme.typography.bodyMedium,
            color = AppColors.textSecondary,
        )
    }
}

@Composable
private fun OnboardingBottomBar(
    currentPage: Int,
    canContinue: Boolean,
    onBack: () -> Unit,
    onContinue: () -> Unit,
    onSkip: () -> Unit,
) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = Spacing.lg, vertical = Spacing.lg)
            .padding(bottom = Spacing.md),
        horizontalArrangement = Arrangement.SpaceBetween,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        // Back button
        AnimatedVisibility(
            visible = currentPage > 0 && currentPage < 4,
            enter = fadeIn() + slideInHorizontally { -it },
            exit = fadeOut() + slideOutHorizontally { -it },
        ) {
            TextButton(onClick = onBack) {
                Icon(
                    Icons.Outlined.ArrowBack,
                    contentDescription = null,
                    tint = AppColors.textMuted,
                    modifier = Modifier.size(18.dp),
                )
                Spacer(modifier = Modifier.width(Spacing.xxs))
                Text(
                    stringResource(R.string.onboarding_back),
                    color = AppColors.textMuted,
                )
            }
        }

        // Spacer when back is hidden
        if (currentPage == 0 || currentPage == 4) {
            Spacer(modifier = Modifier.width(1.dp))
        }

        // Continue / Skip
        AnimatedVisibility(
            visible = currentPage < 4,
            enter = fadeIn() + slideInHorizontally { it },
            exit = fadeOut() + slideOutHorizontally { it },
        ) {
            Row {
                // Skip button for permission/storage pages
                if ((currentPage == 1 && !canContinue) || (currentPage == 2 && !canContinue)) {
                    TextButton(onClick = onSkip) {
                        Text(
                            stringResource(R.string.onboarding_skip),
                            color = AppColors.textMuted,
                        )
                    }
                    Spacer(modifier = Modifier.width(Spacing.sm))
                }

                SecondaryButton(
                    text = stringResource(R.string.onboarding_continue),
                    onClick = onContinue,
                    icon = Icons.Outlined.ArrowForward,
                )
            }
        }
    }
}
