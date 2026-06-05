package com.healthmd.presentation.navigation

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.scale
import androidx.compose.ui.draw.shadow
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import com.healthmd.R
import com.healthmd.data.scheduler.ScheduledExportRecoveryBlocker
import com.healthmd.data.scheduler.ScheduledExportRecoveryRunStatus
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.presentation.paywall.PaywallViewModel
import com.healthmd.presentation.export.ExportScreen
import com.healthmd.presentation.history.HistoryScreen
import com.healthmd.presentation.metrics.MetricSelectionScreen
import com.healthmd.presentation.onboarding.OnboardingScreen
import com.healthmd.presentation.paywall.PaywallScreen
import com.healthmd.presentation.schedule.ScheduleScreen
import com.healthmd.presentation.schedule.ScheduledRecoveryUiState
import com.healthmd.presentation.schedule.ScheduledRecoveryViewModel
import com.healthmd.presentation.settings.*
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing

@Composable
fun HealthMdNavigation(
    settingsRepository: SettingsRepository,
    initialRoute: String? = null,
    scheduledRecoveryPromptRequestId: Long = 0L,
) {
    val navController = rememberNavController()
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination
    val currentRoute = currentDestination?.route

    // Check onboarding status and existing setup
    val hasCompletedOnboarding by settingsRepository.hasCompletedOnboarding.collectAsStateWithLifecycle(initialValue = null)
    val existingFolderUri by settingsRepository.exportFolderUri.collectAsStateWithLifecycle(initialValue = null)

    // Adaptive navigation: bottom pill on compact screens, navigation rail on tablets/foldables.
    val showMainNav = currentRoute in NavDestination.entries.map { it.route }
    val useNavigationRail = LocalConfiguration.current.screenWidthDp >= 600
    val showBottomNav = showMainNav && !useNavigationRail
    val showNavigationRail = showMainNav && useNavigationRail

    // Wait for onboarding check to complete
    if (hasCompletedOnboarding == null) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(AppColors.bgPrimary),
        )
        return
    }

    // Skip onboarding if already completed OR if user already has a folder set up
    // (handles existing users upgrading from pre-onboarding versions)
    val shouldSkipOnboarding = hasCompletedOnboarding == true || !existingFolderUri.isNullOrEmpty()

    val knownStartRoutes = NavDestination.entries.map { it.route } + listOf(SubRoutes.PAYWALL)
    val startDestination = if (shouldSkipOnboarding) {
        initialRoute?.takeIf { it in knownStartRoutes } ?: NavDestination.EXPORT.route
    } else {
        SubRoutes.ONBOARDING
    }

    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.bgPrimary),
    ) {
        ScheduledRecoveryHost(
            recoveryPromptRequestId = scheduledRecoveryPromptRequestId,
            onNavigateToSchedule = {
                if (shouldSkipOnboarding && currentRoute != NavDestination.SCHEDULE.route) {
                    navController.navigate(NavDestination.SCHEDULE.route) {
                        launchSingleTop = true
                    }
                }
            },
        )

        // Shared ViewModel for settings
        val settingsViewModel: SettingsViewModel = hiltViewModel()
        val settings by settingsViewModel.settings.collectAsStateWithLifecycle()

        NavHost(
            navController = navController,
            startDestination = startDestination,
            modifier = Modifier
                .fillMaxSize()
                .padding(
                    start = if (showNavigationRail) 96.dp else 0.dp,
                    bottom = if (showBottomNav) 88.dp else 0.dp,
                ),
        ) {
            // Onboarding
            composable(SubRoutes.ONBOARDING) {
                OnboardingScreen(
                    onNavigateToPaywall = { navController.navigate(SubRoutes.PAYWALL) },
                    onComplete = {
                        navController.navigate(NavDestination.EXPORT.route) {
                            popUpTo(SubRoutes.ONBOARDING) { inclusive = true }
                        }
                    },
                )
            }

            composable(NavDestination.EXPORT.route) {
                ExportScreen(
                    onNavigateToPaywall = { navController.navigate(SubRoutes.PAYWALL) },
                )
            }
            composable(NavDestination.SCHEDULE.route) {
                ScheduleScreen(onNavigateToPaywall = { navController.navigate(SubRoutes.PAYWALL) })
            }
            composable(NavDestination.HISTORY.route) { HistoryScreen() }
            composable(NavDestination.SETTINGS.route) {
                SettingsScreen(
                    viewModel = settingsViewModel,
                    onNavigateToAdvancedSettings = { navController.navigate(SubRoutes.ADVANCED_SETTINGS) },
                    onNavigateToPaywall = { navController.navigate(SubRoutes.PAYWALL) },
                )
            }

            // Sub-screens
            composable(SubRoutes.ADVANCED_SETTINGS) {
                AdvancedSettingsScreen(
                    settings = settings,
                    onNavigateToMetrics = { navController.navigate(SubRoutes.METRIC_SELECTION) },
                    onNavigateToFormatCustomization = { navController.navigate(SubRoutes.FORMAT_CUSTOMIZATION) },
                    onNavigateToDailyNoteInjection = { navController.navigate(SubRoutes.DAILY_NOTE_INJECTION) },
                    onNavigateToIndividualTracking = { navController.navigate(SubRoutes.INDIVIDUAL_TRACKING) },
                    onIncludeGranularDataChanged = { settingsViewModel.updateIncludeGranularData(it) },
                    onBack = { navController.popBackStack() },
                )
            }
            composable(SubRoutes.METRIC_SELECTION) {
                MetricSelectionScreen(
                    metricSelection = settings.metricSelection,
                    onSelectionChanged = { settingsViewModel.updateMetricSelection(it) },
                    onBack = { navController.popBackStack() },
                )
            }
            composable(SubRoutes.FORMAT_CUSTOMIZATION) {
                FormatCustomizationScreen(
                    customization = settings.formatCustomization,
                    onCustomizationChanged = { settingsViewModel.updateFormatCustomization(it) },
                    onNavigateToFrontmatter = { navController.navigate(SubRoutes.FRONTMATTER_CUSTOMIZATION) },
                    onBack = { navController.popBackStack() },
                )
            }
            composable(SubRoutes.FRONTMATTER_CUSTOMIZATION) {
                FrontmatterCustomizationScreen(
                    configuration = settings.formatCustomization.frontmatterConfig,
                    onConfigurationChanged = { config ->
                        settingsViewModel.updateFormatCustomization(
                            settings.formatCustomization.copy(frontmatterConfig = config)
                        )
                    },
                    onBack = { navController.popBackStack() },
                )
            }
            composable(SubRoutes.DAILY_NOTE_INJECTION) {
                DailyNoteInjectionScreen(
                    settings = settings.dailyNoteInjection,
                    onSettingsChanged = { settingsViewModel.updateDailyNoteInjection(it) },
                    onBack = { navController.popBackStack() },
                )
            }
            composable(SubRoutes.INDIVIDUAL_TRACKING) {
                IndividualTrackingScreen(
                    settings = settings.individualTracking,
                    onSettingsChanged = { settingsViewModel.updateIndividualTracking(it) },
                    onBack = { navController.popBackStack() },
                )
            }
            composable(SubRoutes.PAYWALL) {
                val paywallViewModel: PaywallViewModel = hiltViewModel()
                val isUnlocked by paywallViewModel.isUnlocked.collectAsStateWithLifecycle()
                val isPurchasing by paywallViewModel.isPurchasing.collectAsStateWithLifecycle()
                val isRestoring by paywallViewModel.isRestoring.collectAsStateWithLifecycle()
                val purchaseError by paywallViewModel.purchaseError.collectAsStateWithLifecycle()
                val priceText by paywallViewModel.priceText.collectAsStateWithLifecycle()
                val debugUnlockOverride by paywallViewModel.debugUnlockOverride.collectAsStateWithLifecycle()
                val context = LocalContext.current

                // Navigate back automatically if purchase is successful
                LaunchedEffect(isUnlocked) {
                    if (isUnlocked) {
                        navController.popBackStack()
                    }
                }

                PaywallScreen(
                    onPurchase = {
                        val activity = context as? android.app.Activity
                        if (activity != null) {
                            paywallViewModel.launchPurchaseFlow(activity)
                        }
                    },
                    onRestore = { paywallViewModel.restorePurchases() },
                    onDismiss = { navController.popBackStack() },
                    isPurchasing = isPurchasing,
                    isRestoring = isRestoring,
                    priceText = priceText,
                    errorMessage = purchaseError,
                    onClearError = { paywallViewModel.clearError() },
                    isDebugBuild = paywallViewModel.isDebugBuild,
                    debugUnlockOverride = debugUnlockOverride,
                    onDebugToggleUnlock = { paywallViewModel.debugToggleUnlock() },
                    onDebugResetState = { paywallViewModel.debugResetPurchaseState() },
                )
            }
        }

        // Navigation rail (main tabs on tablets/foldables)
        if (showNavigationRail) {
            AdaptiveNavigationRail(
                destinations = NavDestination.entries,
                currentRoute = currentRoute,
                onNavigate = { dest ->
                    navController.navigate(dest.route) {
                        popUpTo(navController.graph.findStartDestination().id) {
                            saveState = true
                        }
                        launchSingleTop = true
                        restoreState = true
                    }
                },
                modifier = Modifier.align(Alignment.CenterStart),
            )
        }

        // Floating Pill Navigation Bar (only on compact main tabs)
        if (showBottomNav) {
            FloatingNavBar(
                destinations = NavDestination.entries,
                currentRoute = currentRoute,
                onNavigate = { dest ->
                    navController.navigate(dest.route) {
                        popUpTo(navController.graph.findStartDestination().id) {
                            saveState = true
                        }
                        launchSingleTop = true
                        restoreState = true
                    }
                },
                modifier = Modifier
                    .align(Alignment.BottomCenter)
                    .padding(start = 40.dp, end = 40.dp, bottom = 16.dp),
            )
        }
    }
}

@Composable
private fun ScheduledRecoveryHost(
    recoveryPromptRequestId: Long,
    onNavigateToSchedule: () -> Unit,
    viewModel: ScheduledRecoveryViewModel = hiltViewModel(),
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val lifecycleOwner = LocalLifecycleOwner.current

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                viewModel.refresh(autoPrompt = true)
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    LaunchedEffect(Unit) {
        viewModel.refresh(autoPrompt = true)
    }

    LaunchedEffect(recoveryPromptRequestId) {
        if (recoveryPromptRequestId > 0L) {
            onNavigateToSchedule()
            viewModel.requestPromptFromNotification()
        }
    }

    if (uiState.showPrompt) {
        ScheduledRecoveryDialog(
            state = uiState,
            onDismiss = viewModel::dismissPrompt,
            onRecover = viewModel::recoverNow,
        )
    }
}

@Composable
private fun ScheduledRecoveryDialog(
    state: ScheduledRecoveryUiState,
    onDismiss: () -> Unit,
    onRecover: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = { if (!state.isRunning) onDismiss() },
        title = { Text(stringResource(R.string.scheduled_recovery_title)) },
        text = {
            Text(
                text = scheduledRecoveryDialogText(state),
                style = MaterialTheme.typography.bodyMedium,
                color = AppColors.textSecondary,
            )
        },
        confirmButton = {
            if (state.canRecover) {
                TextButton(onClick = onRecover, enabled = !state.isRunning) {
                    Text(
                        if (state.isRunning) {
                            stringResource(R.string.scheduled_recovery_running_button)
                        } else {
                            stringResource(R.string.scheduled_recovery_retry_button)
                        }
                    )
                }
            }
        },
        dismissButton = {
            TextButton(onClick = onDismiss, enabled = !state.isRunning) {
                Text(stringResource(R.string.not_now))
            }
        },
    )
}

@Composable
private fun scheduledRecoveryDialogText(state: ScheduledRecoveryUiState): String {
    val dateSummary = when (state.pendingDates.size) {
        0 -> ""
        1 -> state.pendingDates.first().toString()
        else -> "${state.pendingDates.first()} — ${state.pendingDates.last()}"
    }
    val body = stringResource(
        R.string.scheduled_recovery_body,
        state.pendingDates.size,
        dateSummary,
    )
    val blocker = state.blocker?.let { blocker ->
        when (blocker) {
            ScheduledExportRecoveryBlocker.PAYWALL_REQUIRED -> stringResource(R.string.scheduled_recovery_blocked_paywall)
            ScheduledExportRecoveryBlocker.NO_EXPORT_FOLDER -> stringResource(R.string.scheduled_recovery_blocked_folder)
            ScheduledExportRecoveryBlocker.DEVICE_LOCKED -> stringResource(R.string.scheduled_recovery_blocked_locked)
            ScheduledExportRecoveryBlocker.HEALTH_PERMISSIONS_REQUIRED -> stringResource(R.string.scheduled_recovery_blocked_permissions)
            ScheduledExportRecoveryBlocker.ALREADY_RUNNING -> stringResource(R.string.scheduled_recovery_blocked_running)
            ScheduledExportRecoveryBlocker.NO_PENDING_DATES -> stringResource(R.string.scheduled_recovery_no_pending)
        }
    }
    val result = state.lastResult?.let { resultMessage ->
        when (resultMessage.status) {
            ScheduledExportRecoveryRunStatus.COMPLETED -> {
                val exportResult = resultMessage.exportResult
                when {
                    exportResult == null -> null
                    exportResult.isFullSuccess -> stringResource(R.string.scheduled_recovery_result_complete)
                    else -> stringResource(
                        R.string.scheduled_recovery_result_partial,
                        exportResult.successCount,
                        exportResult.totalCount,
                        exportResult.failedDateDetails.size,
                    )
                }
            }
            ScheduledExportRecoveryRunStatus.BLOCKED -> stringResource(R.string.scheduled_recovery_result_blocked)
            ScheduledExportRecoveryRunStatus.ALREADY_RUNNING -> stringResource(R.string.scheduled_recovery_blocked_running)
        }
    }

    return listOfNotNull(body, blocker, result).joinToString("\n\n")
}

@Composable
private fun AdaptiveNavigationRail(
    destinations: List<NavDestination>,
    currentRoute: String?,
    onNavigate: (NavDestination) -> Unit,
    modifier: Modifier = Modifier,
) {
    NavigationRail(
        modifier = modifier
            .fillMaxHeight()
            .width(88.dp)
            .background(AppColors.bgSecondary.copy(alpha = 0.95f))
            .border(width = 1.dp, color = AppColors.navBarBorder),
        containerColor = AppColors.bgSecondary.copy(alpha = 0.95f),
        contentColor = AppColors.textPrimary,
    ) {
        Spacer(modifier = Modifier.height(Spacing.lg))
        destinations.forEach { dest ->
            val selected = currentRoute == dest.route
            val label = stringResource(dest.label)
            NavigationRailItem(
                selected = selected,
                onClick = { onNavigate(dest) },
                icon = {
                    Icon(
                        dest.icon,
                        contentDescription = label,
                        tint = if (selected) AppColors.textPrimary else AppColors.textMuted,
                    )
                },
                label = {
                    Text(
                        label,
                        color = if (selected) AppColors.textPrimary else AppColors.textMuted,
                        fontSize = 11.sp,
                        fontWeight = FontWeight.Medium,
                    )
                },
                colors = NavigationRailItemDefaults.colors(
                    selectedIconColor = AppColors.textPrimary,
                    selectedTextColor = AppColors.textPrimary,
                    indicatorColor = Color.White.copy(alpha = 0.15f),
                    unselectedIconColor = AppColors.textMuted,
                    unselectedTextColor = AppColors.textMuted,
                ),
            )
            Spacer(modifier = Modifier.height(Spacing.sm))
        }
    }
}

@Composable
private fun FloatingNavBar(
    destinations: List<NavDestination>,
    currentRoute: String?,
    onNavigate: (NavDestination) -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(100.dp)

    Row(
        modifier = modifier
            .fillMaxWidth()
            .shadow(
                elevation = 20.dp,
                shape = shape,
                ambientColor = Color.Black.copy(alpha = 0.30f),
                spotColor = Color.Black.copy(alpha = 0.30f),
            )
            .clip(shape)
            .background(AppColors.bgSecondary.copy(alpha = 0.95f))
            .border(1.dp, AppColors.navBarBorder, shape)
            .padding(8.dp),
        horizontalArrangement = Arrangement.SpaceEvenly,
    ) {
        destinations.forEach { dest ->
            val selected = currentRoute == dest.route
            NavBarTab(
                destination = dest,
                selected = selected,
                onClick = { onNavigate(dest) },
                modifier = Modifier.weight(1f),
            )
        }
    }
}

@Composable
private fun NavBarTab(
    destination: NavDestination,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val scale by animateFloatAsState(
        targetValue = if (selected) 1f else 1f,
        animationSpec = spring(dampingRatio = 0.7f, stiffness = 300f),
        label = "tabScale",
    )
    val bgColor by animateColorAsState(
        targetValue = if (selected) Color.White.copy(alpha = 0.15f) else Color.Transparent,
        label = "tabBg",
    )
    val contentColor = if (selected) AppColors.textPrimary else AppColors.textMuted
    val shape = RoundedCornerShape(100.dp)

    Column(
        modifier = modifier
            .scale(scale)
            .height(56.dp)
            .clip(shape)
            .background(bgColor)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick,
            ),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        val label = stringResource(destination.label)
        Icon(
            destination.icon,
            contentDescription = label,
            tint = contentColor,
            modifier = Modifier.size(22.dp),
        )
        Spacer(modifier = Modifier.height(4.dp))
        Text(
            label,
            color = contentColor,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
        )
    }
}

@Composable
private fun animateColorAsState(
    targetValue: Color,
    label: String,
): State<Color> {
    val animatedAlpha by animateFloatAsState(
        targetValue = targetValue.alpha,
        animationSpec = spring(dampingRatio = 0.7f, stiffness = 300f),
        label = label,
    )
    return remember(targetValue, animatedAlpha) {
        mutableStateOf(targetValue.copy(alpha = animatedAlpha))
    }
}
