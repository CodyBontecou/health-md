package com.healthmd.presentation.navigation

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
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
import com.healthmd.BuildConfig
import com.healthmd.R
import com.healthmd.data.scheduler.ScheduledExportRecoveryBlocker
import com.healthmd.data.scheduler.ScheduledExportRecoveryRunStatus
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.presentation.paywall.PaywallViewModel
import com.healthmd.presentation.directcli.DirectCliScreen
import com.healthmd.presentation.clinicianreport.ClinicianReportScreen
import com.healthmd.presentation.export.ExportScreen
import com.healthmd.presentation.history.HistoryScreen
import com.healthmd.presentation.metrics.MetricSelectionScreen
import com.healthmd.presentation.common.ConfigurationProtectionToast
import com.healthmd.presentation.common.ConfigurationProtectionUi
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.onboarding.OnboardingScreen
import com.healthmd.presentation.paywall.PaywallScreen
import com.healthmd.presentation.release.AndroidReleaseNotes
import com.healthmd.presentation.release.ReleaseNotesDialog
import com.healthmd.presentation.release.ReleaseNotesGate
import com.healthmd.presentation.schedule.ScheduleScreen
import com.healthmd.presentation.schedule.ScheduledRecoveryUiState
import com.healthmd.presentation.schedule.ScheduledRecoveryViewModel
import com.healthmd.presentation.settings.*
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistBreakpoints
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import com.healthmd.presentation.theme.Spacing
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.time.LocalDate
import java.time.ZoneId
import java.util.Date

@Composable
fun HealthMdNavigation(
    settingsRepository: SettingsRepository,
    initialRoute: String? = null,
    scheduledRecoveryPromptRequestId: Long = 0L,
) {
    val navController = rememberNavController()
    val coroutineScope = rememberCoroutineScope()
    val appContext = LocalContext.current
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination
    val currentRoute = currentDestination?.route

    // Resolve the initial route once. A folder selected during onboarding is persisted to
    // settings, but must not turn into a live signal that rebuilds the navigation graph.
    var initialShouldSkipOnboarding by rememberSaveable { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(settingsRepository) {
        if (initialShouldSkipOnboarding == null) {
            initialShouldSkipOnboarding = settingsRepository.resolveOnboardingCompletion()
        }
    }

    val hasCompletedOnboarding by settingsRepository.hasCompletedOnboarding.collectAsStateWithLifecycle(initialValue = null)

    // Adaptive navigation: bottom bar on compact screens, navigation rail on larger layouts.
    val showMainNav = currentRoute in NavDestination.entries.map { it.route }
    val useNavigationRail = LocalConfiguration.current.screenWidthDp >= GeistBreakpoints.medium
    val showBottomNav = showMainNav && !useNavigationRail
    val showNavigationRail = showMainNav && useNavigationRail

    // Wait until the explicit completion state has loaded or the legacy-folder state has been
    // migrated. The saved decision survives activity recreation and remains stable for this entry.
    if (initialShouldSkipOnboarding == null) {
        Box(
            modifier = Modifier
                .fillMaxSize()
                .background(AppColors.bgPrimary),
        )
        return
    }

    // Existing users with a pre-onboarding folder still skip setup, but later folder updates
    // cannot eject a new user from an active onboarding flow.
    val shouldSkipOnboarding = requireNotNull(initialShouldSkipOnboarding)
    val hasCompletedSetup = hasCompletedOnboarding == true
    val releaseNotes = remember(appContext) { AndroidReleaseNotes.current(appContext) }
    var releaseNotesDismissed by remember(releaseNotes?.versionKey) { mutableStateOf(false) }
    val lastPresentedReleaseVersion by settingsRepository.lastPresentedReleaseVersion.collectAsStateWithLifecycle(initialValue = null)
    val suppressReleaseNotes = BuildConfig.DEBUG || initialRoute != null
    val shouldShowReleaseNotes = !releaseNotesDismissed && ReleaseNotesGate.shouldPresent(
        currentVersionKey = releaseNotes?.versionKey,
        lastPresentedVersionKey = lastPresentedReleaseVersion,
        hasCompletedSetup = hasCompletedSetup,
        suppressForAutomationOrDebug = suppressReleaseNotes,
    )
    val markReleaseNotesSeen: () -> Unit = {
        releaseNotesDismissed = true
        releaseNotes?.let { notes ->
            coroutineScope.launch {
                settingsRepository.setLastPresentedReleaseVersion(notes.versionKey)
            }
        }
    }

    val debugStartRoutes = if (BuildConfig.DEBUG) {
        listOf(
            SubRoutes.ONBOARDING,
            SubRoutes.METRIC_SELECTION,
            SubRoutes.FORMAT_CUSTOMIZATION,
            SubRoutes.FRONTMATTER_CUSTOMIZATION,
            SubRoutes.DAILY_NOTE_INJECTION,
            SubRoutes.INDIVIDUAL_TRACKING,
            SubRoutes.ADVANCED_SETTINGS,
            SubRoutes.CLINICIAN_REPORT,
            SubRoutes.DIRECT_CLI,
        )
    } else {
        emptyList()
    }
    val knownStartRoutes = NavDestination.entries.map { it.route } + PaywallEntryPoint.UPGRADE.route + debugStartRoutes
    val startDestination = if (shouldSkipOnboarding) {
        initialRoute?.takeIf { it in knownStartRoutes } ?: NavDestination.EXPORT.route
    } else {
        SubRoutes.ONBOARDING
    }

    // One graph-scoped owner exposes the device-local protection preference, toast, and
    // navigation request to every in-app configuration surface.
    val settingsViewModel: SettingsViewModel = hiltViewModel()
    val settings by settingsViewModel.settings.collectAsStateWithLifecycle()
    val protectionEnabled by settingsViewModel.preventAccidentalChanges.collectAsStateWithLifecycle()
    val blockedChangeToastId by settingsViewModel.blockedChangeToastId.collectAsStateWithLifecycle()
    val protectionSettingsRequestId by settingsViewModel.protectionSettingsRequestId.collectAsStateWithLifecycle()

    LaunchedEffect(blockedChangeToastId) {
        val toastId = blockedChangeToastId ?: return@LaunchedEffect
        delay(4_000)
        if (settingsViewModel.blockedChangeToastId.value == toastId) {
            settingsViewModel.dismissBlockedChangeToast()
        }
    }

    CompositionLocalProvider(
        LocalConfigurationProtection provides ConfigurationProtectionUi(
            // Fail closed during the brief DataStore-loading state.
            enabled = protectionEnabled != false,
            onBlockedChange = settingsViewModel::showBlockedChangeToast,
        ),
    ) {
    Box(
        modifier = Modifier
            .fillMaxSize()
            .background(AppColors.bgPrimary),
    ) {
        ScheduledRecoveryHost(
            recoveryPromptRequestId = scheduledRecoveryPromptRequestId,
            onNavigateToSchedule = {
                if (hasCompletedSetup && currentRoute != NavDestination.SCHEDULE.route) {
                    navController.navigate(NavDestination.SCHEDULE.route) {
                        launchSingleTop = true
                    }
                }
            },
        )

        NavHost(
            navController = navController,
            startDestination = startDestination,
            modifier = Modifier
                .fillMaxSize()
                .padding(
                    start = if (showNavigationRail) 80.dp else 0.dp,
                    bottom = if (showBottomNav) 88.dp else 0.dp,
                ),
        ) {
            // Onboarding
            composable(SubRoutes.ONBOARDING) {
                val isDebugMarketingCapture = BuildConfig.DEBUG && initialRoute == SubRoutes.ONBOARDING
                OnboardingScreen(
                    onComplete = {
                        navController.navigate(NavDestination.EXPORT.route) {
                            popUpTo(SubRoutes.ONBOARDING) { inclusive = true }
                        }
                    },
                    initialPage = if (isDebugMarketingCapture) 1 else 0,
                    allowAutomaticAdvance = !isDebugMarketingCapture,
                )
            }

            composable(NavDestination.EXPORT.route) {
                ExportScreen(
                    onNavigateToPaywall = {
                        navController.navigate(PaywallEntryPoint.EXPORT_LIMIT.route)
                    },
                    onNavigateToAdvancedSettings = { navController.navigate(SubRoutes.ADVANCED_SETTINGS) },
                    onNavigateToClinicianReport = { navController.navigate(SubRoutes.CLINICIAN_REPORT) },
                )
            }
            composable(NavDestination.SCHEDULE.route) {
                ScheduleScreen(
                    onNavigateToPaywall = {
                        navController.navigate(PaywallEntryPoint.SCHEDULE.route)
                    },
                )
            }
            composable(NavDestination.HISTORY.route) { HistoryScreen() }
            composable(NavDestination.SETTINGS.route) {
                SettingsScreen(
                    viewModel = settingsViewModel,
                    protectionSettingsRequestId = protectionSettingsRequestId,
                    onNavigateToPaywall = {
                        navController.navigate(PaywallEntryPoint.UPGRADE.route)
                    },
                    onNavigateToDirectCli = { navController.navigate(SubRoutes.DIRECT_CLI) },
                )
            }

            // Sub-screens
            composable(SubRoutes.DIRECT_CLI) {
                DirectCliScreen(onBack = { navController.popBackStack() })
            }
            composable(SubRoutes.CLINICIAN_REPORT) {
                ClinicianReportScreen(onBack = { navController.popBackStack() })
            }
            composable(SubRoutes.ADVANCED_SETTINGS) {
                AdvancedSettingsScreen(
                    settings = settings,
                    onNavigateToMetrics = { navController.navigate(SubRoutes.METRIC_SELECTION) },
                    onNavigateToFormatCustomization = { navController.navigate(SubRoutes.FORMAT_CUSTOMIZATION) },
                    onNavigateToDailyNoteInjection = { navController.navigate(SubRoutes.DAILY_NOTE_INJECTION) },
                    onNavigateToIndividualTracking = { navController.navigate(SubRoutes.INDIVIDUAL_TRACKING) },
                    onIncludeGranularDataChanged = {
                        settingsViewModel.performConfigurationChange {
                            settingsViewModel.updateIncludeGranularData(it)
                        }
                    },
                    onBack = { navController.popBackStack() },
                )
            }
            composable(SubRoutes.METRIC_SELECTION) {
                MetricSelectionScreen(
                    metricSelection = settings.metricSelection,
                    onSelectionChanged = {
                        settingsViewModel.performConfigurationChange {
                            settingsViewModel.updateMetricSelection(it)
                        }
                    },
                    onBack = { navController.popBackStack() },
                )
            }
            composable(SubRoutes.FORMAT_CUSTOMIZATION) {
                FormatCustomizationScreen(
                    customization = settings.formatCustomization,
                    onCustomizationChanged = {
                        settingsViewModel.performConfigurationChange {
                            settingsViewModel.updateFormatCustomization(it)
                        }
                    },
                    onNavigateToFrontmatter = { navController.navigate(SubRoutes.FRONTMATTER_CUSTOMIZATION) },
                    onBack = { navController.popBackStack() },
                )
            }
            composable(SubRoutes.FRONTMATTER_CUSTOMIZATION) {
                FrontmatterCustomizationScreen(
                    configuration = settings.formatCustomization.frontmatterConfig,
                    onConfigurationChanged = { config ->
                        settingsViewModel.performConfigurationChange {
                            settingsViewModel.updateFormatCustomization(
                                settings.formatCustomization.copy(frontmatterConfig = config)
                            )
                        }
                    },
                    onBack = { navController.popBackStack() },
                )
            }
            composable(SubRoutes.DAILY_NOTE_INJECTION) {
                DailyNoteInjectionScreen(
                    settings = settings.dailyNoteInjection,
                    onSettingsChanged = {
                        settingsViewModel.performConfigurationChange {
                            settingsViewModel.updateDailyNoteInjection(it)
                        }
                    },
                    onBack = { navController.popBackStack() },
                )
            }
            composable(SubRoutes.INDIVIDUAL_TRACKING) {
                IndividualTrackingScreen(
                    settings = settings.individualTracking,
                    onSettingsChanged = {
                        settingsViewModel.performConfigurationChange {
                            settingsViewModel.updateIndividualTracking(it)
                        }
                    },
                    onBack = { navController.popBackStack() },
                )
            }
            PaywallEntryPoint.entries.forEach { entryPoint ->
                composable(entryPoint.route) {
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
                        subtitle = stringResource(entryPoint.subtitleResource),
                        isPurchasing = isPurchasing,
                        isRestoring = isRestoring,
                        priceText = priceText,
                        purchaseError = purchaseError,
                        onClearError = { paywallViewModel.clearError() },
                        isDebugBuild = paywallViewModel.isDebugBuild,
                        debugUnlockOverride = debugUnlockOverride,
                        onDebugToggleUnlock = { paywallViewModel.debugToggleUnlock() },
                        onDebugResetState = { paywallViewModel.debugResetPurchaseState() },
                    )
                }
            }
        }

        if (shouldShowReleaseNotes && releaseNotes != null) {
            ReleaseNotesDialog(
                notes = releaseNotes,
                onDismiss = markReleaseNotesSeen,
                onOpenSettings = {
                    markReleaseNotesSeen()
                    navController.navigate(NavDestination.SETTINGS.route) {
                        launchSingleTop = true
                    }
                },
            )
        }

        ConfigurationProtectionToast(
            visible = blockedChangeToastId != null,
            onOpenSettings = {
                settingsViewModel.openProtectionSetting()
                navController.navigate(NavDestination.SETTINGS.route) {
                    popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                    launchSingleTop = true
                    restoreState = true
                }
            },
            modifier = Modifier
                .align(Alignment.TopCenter)
                .statusBarsPadding()
                .padding(horizontal = Spacing.md, vertical = Spacing.sm),
        )

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

        // Bottom navigation bar (only on compact main tabs)
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
                modifier = Modifier.align(Alignment.BottomCenter),
            )
        }
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
        1 -> localizedRecoveryDate(state.pendingDates.first())
        else -> stringResource(
            R.string.history_date_range,
            localizedRecoveryDate(state.pendingDates.first()),
            localizedRecoveryDate(state.pendingDates.last()),
        )
    }
    val body = pluralStringResource(
        R.plurals.scheduled_recovery_body,
        state.pendingDates.size,
        state.pendingDates.size,
        dateSummary,
    )
    val blocker = state.blocker?.let { blocker ->
        when (blocker) {
            ScheduledExportRecoveryBlocker.PAYWALL_REQUIRED -> stringResource(R.string.scheduled_recovery_blocked_paywall)
            ScheduledExportRecoveryBlocker.NO_EXPORT_FOLDER -> stringResource(R.string.scheduled_recovery_blocked_folder)
            ScheduledExportRecoveryBlocker.API_ENDPOINT_NOT_CONFIGURED -> stringResource(R.string.scheduled_recovery_blocked_api)
            ScheduledExportRecoveryBlocker.API_ENDPOINT_CHANGED -> stringResource(R.string.scheduled_recovery_blocked_api_changed)
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
                        R.string.scheduled_recovery_result_summary,
                        pluralStringResource(
                            R.plurals.scheduled_recovery_result_exported_dates,
                            exportResult.totalCount,
                            exportResult.successCount,
                            exportResult.totalCount,
                        ),
                        pluralStringResource(
                            R.plurals.scheduled_recovery_result_pending_dates,
                            exportResult.failedDateDetails.size,
                            exportResult.failedDateDetails.size,
                        ),
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
private fun localizedRecoveryDate(date: LocalDate): String {
    val instant = date.atStartOfDay(ZoneId.systemDefault()).toInstant()
    return android.text.format.DateFormat.getMediumDateFormat(LocalContext.current)
        .format(Date.from(instant))
}

@Composable
private fun AdaptiveNavigationRail(
    destinations: List<NavDestination>,
    currentRoute: String?,
    onNavigate: (NavDestination) -> Unit,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    NavigationRail(
        modifier = modifier
            .fillMaxHeight()
            .width(80.dp)
            .background(colors.background100)
            .border(width = 1.dp, color = colors.grayAlpha.c400),
        containerColor = colors.background100,
        contentColor = colors.primary,
    ) {
        Spacer(modifier = Modifier.height(Spacing.lg))
        destinations.forEach { destination ->
            val selected = currentRoute == destination.route
            val label = stringResource(destination.label)
            NavigationRailItem(
                selected = selected,
                onClick = { onNavigate(destination) },
                icon = {
                    Icon(
                        destination.icon,
                        contentDescription = label,
                    )
                },
                label = { Text(label, style = GeistType.button12) },
                colors = NavigationRailItemDefaults.colors(
                    selectedIconColor = colors.accent,
                    selectedTextColor = colors.primary,
                    indicatorColor = colors.gray.c100,
                    unselectedIconColor = colors.disabled,
                    unselectedTextColor = colors.secondary,
                ),
            )
            Spacer(modifier = Modifier.height(Spacing.xs))
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
    val colors = LocalGeistColors.current
    Row(
        modifier = modifier
            .fillMaxWidth()
            .background(colors.background100)
            .border(width = 1.dp, color = colors.grayAlpha.c400)
            .navigationBarsPadding()
            .heightIn(min = 64.dp)
            .padding(horizontal = Spacing.xs, vertical = Spacing.xs),
        horizontalArrangement = Arrangement.SpaceEvenly,
    ) {
        destinations.forEach { destination ->
            NavBarTab(
                destination = destination,
                selected = currentRoute == destination.route,
                onClick = { onNavigate(destination) },
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
    val colors = LocalGeistColors.current
    val contentColor = if (selected) colors.primary else colors.secondary
    val background = if (selected) colors.gray.c100 else Color.Transparent
    val label = stringResource(destination.label)

    Column(
        modifier = modifier
            .height(48.dp)
            .background(background, RoundedCornerShape(GeistRadii.small))
            .selectable(
                selected = selected,
                onClick = onClick,
                role = Role.Tab,
            ),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        Icon(
            destination.icon,
            contentDescription = label,
            tint = if (selected) colors.accent else contentColor,
            modifier = Modifier.size(20.dp),
        )
        Spacer(modifier = Modifier.height(Spacing.xxs))
        Text(label, color = contentColor, style = GeistType.button12)
    }
}
