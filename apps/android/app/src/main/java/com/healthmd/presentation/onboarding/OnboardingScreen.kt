package com.healthmd.presentation.onboarding

import android.net.Uri
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
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.presentation.common.*
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Radii
import com.healthmd.presentation.theme.Spacing
import kotlinx.coroutines.launch
import kotlin.math.absoluteValue

@OptIn(ExperimentalFoundationApi::class)
@Composable
fun OnboardingScreen(
    viewModel: OnboardingViewModel = hiltViewModel(),
    onNavigateToPaywall: () -> Unit = {},
    onComplete: () -> Unit,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val coroutineScope = rememberCoroutineScope()

    val healthConnectManager = remember { HealthConnectManager(context) }
    val permissionContract = remember { healthConnectManager.getPermissionContract() }
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = permissionContract,
    ) { viewModel.refreshPermissions() }

    val folderPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree(),
    ) { uri -> uri?.let { viewModel.onFolderSelected(it) } }

    val pagerState = rememberPagerState(pageCount = { 5 })

    // Auto-advance when conditions are met
    LaunchedEffect(uiState.hasPermissions, pagerState.currentPage) {
        if (pagerState.currentPage == 1 && uiState.hasPermissions) {
            kotlinx.coroutines.delay(800)
            pagerState.animateScrollToPage(2)
        }
    }

    LaunchedEffect(uiState.folderName, pagerState.currentPage) {
        if (pagerState.currentPage == 2 && uiState.folderName != null) {
            kotlinx.coroutines.delay(800)
            pagerState.animateScrollToPage(3)
        }
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.bgPrimary),
    ) {
        // Animated background gradient orbs
        BackgroundOrbs()

        Column(
            modifier = Modifier.fillMaxSize(),
        ) {
            // Page indicators at top
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .padding(top = 60.dp, bottom = 24.dp),
                horizontalArrangement = Arrangement.Center,
            ) {
                repeat(5) { index ->
                    val selected = pagerState.currentPage == index
                    val width by animateDpAsState(
                        targetValue = if (selected) 24.dp else 8.dp,
                        animationSpec = spring(dampingRatio = 0.8f),
                        label = "indicatorWidth",
                    )
                    Box(
                        modifier = Modifier
                            .padding(horizontal = 4.dp)
                            .height(8.dp)
                            .width(width)
                            .clip(CircleShape)
                            .background(
                                if (selected) AppColors.accent
                                else AppColors.textMuted.copy(alpha = 0.3f)
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
                        3 -> UnlockEducationPage(
                            freeExportsRemaining = uiState.freeExportsRemaining,
                            isPurchased = uiState.isPurchased,
                            onNavigateToPaywall = onNavigateToPaywall,
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
private fun BackgroundOrbs() {
    val infiniteTransition = rememberInfiniteTransition(label = "orbs")

    val offset1 by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = 30f,
        animationSpec = infiniteRepeatable(
            animation = tween(8000, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "orb1",
    )

    val offset2 by infiniteTransition.animateFloat(
        initialValue = 0f,
        targetValue = -25f,
        animationSpec = infiniteRepeatable(
            animation = tween(6000, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "orb2",
    )

    Box(modifier = Modifier.fillMaxSize()) {
        // Top-right orb
        Box(
            modifier = Modifier
                .offset(x = (280 + offset1).dp, y = (100 + offset2).dp)
                .size(300.dp)
                .blur(100.dp)
                .background(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            AppColors.accent.copy(alpha = 0.25f),
                            Color.Transparent,
                        ),
                    ),
                    shape = CircleShape,
                ),
        )

        // Bottom-left orb
        Box(
            modifier = Modifier
                .offset(x = (-100 + offset2).dp, y = (500 + offset1).dp)
                .size(350.dp)
                .blur(120.dp)
                .background(
                    brush = Brush.radialGradient(
                        colors = listOf(
                            AppColors.accent.copy(alpha = 0.15f),
                            Color.Transparent,
                        ),
                    ),
                    shape = CircleShape,
                ),
        )
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
        // Animated app icon
        val scale by rememberInfiniteTransition(label = "iconPulse").animateFloat(
            initialValue = 1f,
            targetValue = 1.05f,
            animationSpec = infiniteRepeatable(
                animation = tween(2000, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "iconScale",
        )

        Box(contentAlignment = Alignment.Center) {
            // Glow
            Box(
                modifier = Modifier
                    .size(140.dp)
                    .scale(scale)
                    .blur(40.dp)
                    .background(AppColors.accent.copy(alpha = 0.4f), CircleShape),
            )
            // Icon
            Image(
                painter = painterResource(id = R.drawable.app_icon),
                contentDescription = stringResource(R.string.app_name),
                modifier = Modifier
                    .size(120.dp)
                    .scale(scale)
                    .shadow(24.dp, RoundedCornerShape(28.dp), ambientColor = AppColors.accent)
                    .clip(RoundedCornerShape(28.dp))
                    .border(2.dp, Color.White.copy(alpha = 0.3f), RoundedCornerShape(28.dp)),
                contentScale = ContentScale.Crop,
            )
        }

        Spacer(modifier = Modifier.height(Spacing.xl))

        Text(
            text = stringResource(R.string.onboarding_welcome_title),
            style = MaterialTheme.typography.displaySmall,
            fontWeight = FontWeight.Bold,
            color = AppColors.textPrimary,
            textAlign = TextAlign.Center,
            lineHeight = 42.sp,
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

        // Feature pills
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
        // Health icon with animated ring
        val ringScale by rememberInfiniteTransition(label = "ring").animateFloat(
            initialValue = 1f,
            targetValue = 1.2f,
            animationSpec = infiniteRepeatable(
                animation = tween(2000, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "ringScale",
        )

        val ringAlpha by rememberInfiniteTransition(label = "ringAlpha").animateFloat(
            initialValue = 0.4f,
            targetValue = 0.1f,
            animationSpec = infiniteRepeatable(
                animation = tween(2000, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "ringAlpha",
        )

        Box(contentAlignment = Alignment.Center) {
            // Animated ring
            Box(
                modifier = Modifier
                    .size(140.dp)
                    .scale(ringScale)
                    .alpha(ringAlpha)
                    .border(3.dp, AppColors.accent, CircleShape),
            )
            // Inner circle
            Box(
                modifier = Modifier
                    .size(100.dp)
                    .clip(CircleShape)
                    .background(AppColors.bgTertiary)
                    .border(1.dp, AppColors.glassBorder, CircleShape),
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
                        tint = Color.White,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(Spacing.xl))

        Text(
            text = stringResource(R.string.onboarding_health_title),
            style = MaterialTheme.typography.displaySmall,
            fontWeight = FontWeight.Bold,
            color = AppColors.textPrimary,
            textAlign = TextAlign.Center,
            lineHeight = 42.sp,
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
                GlassBadge(borderColor = AppColors.success.copy(alpha = 0.5f)) {
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
        // Folder icon with animated documents
        val docOffset by rememberInfiniteTransition(label = "docs").animateFloat(
            initialValue = -5f,
            targetValue = 5f,
            animationSpec = infiniteRepeatable(
                animation = tween(1500, easing = FastOutSlowInEasing),
                repeatMode = RepeatMode.Reverse,
            ),
            label = "docOffset",
        )

        Box(contentAlignment = Alignment.Center) {
            // Background glow
            Box(
                modifier = Modifier
                    .size(120.dp)
                    .blur(50.dp)
                    .background(AppColors.accent.copy(alpha = 0.3f), CircleShape),
            )
            // Main folder icon
            Box(
                modifier = Modifier
                    .size(100.dp)
                    .clip(RoundedCornerShape(24.dp))
                    .background(AppColors.bgTertiary)
                    .border(1.dp, AppColors.glassBorder, RoundedCornerShape(24.dp)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    if (folderName != null) Icons.Rounded.FolderOpen else Icons.Outlined.Folder,
                    contentDescription = null,
                    tint = if (folderName != null) AppColors.success else AppColors.accent,
                    modifier = Modifier.size(48.dp),
                )
            }
            // Floating document icons
            if (folderName == null) {
                Icon(
                    Icons.Outlined.Description,
                    contentDescription = null,
                    tint = AppColors.textMuted,
                    modifier = Modifier
                        .size(24.dp)
                        .offset(x = (-50).dp, y = docOffset.dp)
                        .alpha(0.6f),
                )
                Icon(
                    Icons.Outlined.Description,
                    contentDescription = null,
                    tint = AppColors.textMuted,
                    modifier = Modifier
                        .size(20.dp)
                        .offset(x = 55.dp, y = (-docOffset).dp)
                        .alpha(0.5f),
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
                        tint = Color.White,
                        modifier = Modifier.size(18.dp),
                    )
                }
            }
        }

        Spacer(modifier = Modifier.height(Spacing.xl))

        Text(
            text = stringResource(R.string.onboarding_storage_title),
            style = MaterialTheme.typography.displaySmall,
            fontWeight = FontWeight.Bold,
            color = AppColors.textPrimary,
            textAlign = TextAlign.Center,
            lineHeight = 42.sp,
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
        GlassCard(padding = Spacing.md) {
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
                modifier = Modifier.padding(start = 32.dp),
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
                    GlassBadge(borderColor = AppColors.success.copy(alpha = 0.5f)) {
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
private fun UnlockEducationPage(
    freeExportsRemaining: Int,
    isPurchased: Boolean,
    onNavigateToPaywall: () -> Unit,
) {
    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        GlassIconCircle(size = 120.dp) {
            Icon(
                Icons.Outlined.WorkspacePremium,
                contentDescription = null,
                tint = AppColors.accent,
                modifier = Modifier.size(60.dp),
            )
        }
        Spacer(modifier = Modifier.height(Spacing.xl))
        Text(
            stringResource(R.string.onboarding_unlock_title),
            style = MaterialTheme.typography.headlineLarge,
            fontWeight = FontWeight.Bold,
            color = AppColors.textPrimary,
            letterSpacing = 2.sp,
            lineHeight = 36.sp,
            textAlign = TextAlign.Center,
        )
        Spacer(modifier = Modifier.height(Spacing.md))
        Text(
            if (isPurchased) stringResource(R.string.onboarding_unlock_purchased_body)
            else stringResource(R.string.onboarding_unlock_body, freeExportsRemaining),
            style = MaterialTheme.typography.bodyLarge,
            color = AppColors.textSecondary,
            textAlign = TextAlign.Center,
            lineHeight = 26.sp,
        )
        Spacer(modifier = Modifier.height(Spacing.lg))
        GlassCard(padding = Spacing.md) {
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
                FeaturePill(Icons.Outlined.UploadFile, stringResource(R.string.onboarding_unlock_feature_exports))
                FeaturePill(Icons.Outlined.Schedule, stringResource(R.string.onboarding_unlock_feature_schedule))
                FeaturePill(Icons.Outlined.Lock, stringResource(R.string.onboarding_unlock_feature_privacy))
            }
        }
        if (!isPurchased) {
            Spacer(modifier = Modifier.height(Spacing.lg))
            SecondaryButton(
                text = stringResource(R.string.onboarding_unlock_cta),
                onClick = onNavigateToPaywall,
                icon = Icons.Outlined.WorkspacePremium,
                modifier = Modifier.fillMaxWidth(),
            )
        }
    }
}

@Composable
private fun ReadyPage(
    onComplete: () -> Unit,
) {
    val scale by rememberInfiniteTransition(label = "ready").animateFloat(
        initialValue = 1f,
        targetValue = 1.1f,
        animationSpec = infiniteRepeatable(
            animation = tween(1500, easing = FastOutSlowInEasing),
            repeatMode = RepeatMode.Reverse,
        ),
        label = "readyScale",
    )

    Column(
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = Spacing.lg),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        // Success checkmark with celebration effect
        Box(contentAlignment = Alignment.Center) {
            // Outer ring pulse
            Box(
                modifier = Modifier
                    .size(140.dp)
                    .scale(scale)
                    .alpha(0.3f)
                    .border(2.dp, AppColors.success, CircleShape),
            )
            // Inner glow
            Box(
                modifier = Modifier
                    .size(100.dp)
                    .blur(30.dp)
                    .background(AppColors.success.copy(alpha = 0.4f), CircleShape),
            )
            // Main circle
            Box(
                modifier = Modifier
                    .size(100.dp)
                    .clip(CircleShape)
                    .background(AppColors.success.copy(alpha = 0.2f))
                    .border(2.dp, AppColors.success, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    Icons.Rounded.Check,
                    contentDescription = null,
                    tint = AppColors.success,
                    modifier = Modifier.size(48.dp),
                )
            }
        }

        Spacer(modifier = Modifier.height(Spacing.xl))

        Text(
            text = stringResource(R.string.onboarding_ready_title),
            style = MaterialTheme.typography.displaySmall,
            fontWeight = FontWeight.Bold,
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
            .clip(RoundedCornerShape(Radii.badge))
            .background(AppColors.bgTertiary.copy(alpha = 0.6f))
            .border(1.dp, AppColors.glassBorder, RoundedCornerShape(Radii.badge))
            .padding(horizontal = Spacing.md, vertical = Spacing.sm + 4.dp),
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
                Spacer(modifier = Modifier.width(4.dp))
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
