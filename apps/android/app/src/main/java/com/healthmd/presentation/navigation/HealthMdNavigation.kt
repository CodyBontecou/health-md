package com.healthmd.presentation.navigation

import com.healthmd.presentation.diagnostics.DiagnosticsScreen

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.FileUpload
import androidx.compose.runtime.*
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.pluralStringResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLifecycleOwner
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.dialog
import androidx.compose.ui.window.DialogProperties
import com.healthmd.presentation.export.ExportNowSheet
import com.healthmd.presentation.export.ExportProfileSelector
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
import com.healthmd.presentation.export.ExportProfilesScreen
import com.healthmd.presentation.export.ExportScreen
import com.healthmd.presentation.history.HistoryScreen
import com.healthmd.presentation.archive.ArchiveScreen
import com.healthmd.presentation.archive.DayPageScreen
import com.healthmd.presentation.export.ExportProfilesViewModel
import com.healthmd.presentation.schedule.AutomationsScreen
import com.healthmd.presentation.schedule.AutomationDetailPane
import com.healthmd.presentation.schedule.composer.AutomationComposerScreen
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.metrics.MetricSelectionScreen
import com.healthmd.presentation.common.ConfigurationProtectionToast
import com.healthmd.presentation.common.ConfigurationProtectionUi
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.LocalFloatingActionClearance
import com.healthmd.presentation.common.LocalUsesNavigationRail
import com.healthmd.presentation.onboarding.OnboardingScreen
import com.healthmd.presentation.paywall.PaywallScreen
import com.healthmd.presentation.release.AndroidReleaseNotes
import com.healthmd.presentation.release.ReleaseNotesDialog
import com.healthmd.presentation.release.ReleaseNotesGate
import com.healthmd.presentation.schedule.ScheduleScreen
import com.healthmd.presentation.schedule.ScheduledRecoveryUiState
import com.healthmd.presentation.schedule.ScheduledRecoveryViewModel
import com.healthmd.presentation.settings.*
import com.healthmd.sharedsetup.SharedSetupCoordinator
import com.healthmd.sharedsetup.SharedSetupScreen
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistBreakpoints
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import com.healthmd.presentation.theme.Spacing
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import java.time.LocalDate
import java.time.ZoneId
import java.util.Date

@Composable
fun HealthMdNavigation(
    settingsRepository: SettingsRepository,
    sharedSetupCoordinator: SharedSetupCoordinator,
    initialRoute: String? = null,
    myselfClaimRequestId: Long = 0L,
    scheduledRecoveryPromptRequestId: Long = 0L,
) {
    // Root boundary, outside NavHost: Back/deep links cannot expose tracking
    // without a store entitlement. F-Droid keeps its included-access policy.
    val accessViewModel: PaywallViewModel = hiltViewModel()
    val clinicAccessViewModel: com.healthmd.presentation.clinic.ClinicAccessViewModel = hiltViewModel()
    val clinicStatus by clinicAccessViewModel.status.collectAsStateWithLifecycle()
    var showClinicEnrollment by remember { mutableStateOf(false) }
    if (showClinicEnrollment) {
        com.healthmd.presentation.clinic.ClinicAccessScreen(
            onDone = { showClinicEnrollment = false }, viewModel = clinicAccessViewModel)
        return
    }

    val accessUnlocked by accessViewModel.accessState.collectAsStateWithLifecycle()
    val personalAccess by accessViewModel.isUnlocked.collectAsStateWithLifecycle()
    val accessOwner = LocalLifecycleOwner.current
    DisposableEffect(accessOwner, accessViewModel) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) { accessViewModel.refreshAccess(); clinicAccessViewModel.refresh() }
        }
        accessOwner.lifecycle.addObserver(observer)
        onDispose { accessOwner.lifecycle.removeObserver(observer) }
    }
    if (accessViewModel.purchasesAvailable && accessUnlocked == null) {
        Box(Modifier.fillMaxSize().background(AppColors.bgPrimary), contentAlignment = Alignment.Center) {
            CircularProgressIndicator(color = AppColors.accent)
        }
        return
    }
    if (accessViewModel.purchasesAvailable && accessUnlocked != true) {
        val offers by accessViewModel.offers.collectAsStateWithLifecycle()
        val purchasing by accessViewModel.isPurchasing.collectAsStateWithLifecycle()
        val restoring by accessViewModel.isRestoring.collectAsStateWithLifecycle()
        val error by accessViewModel.purchaseError.collectAsStateWithLifecycle()
        val context = LocalContext.current
        Scaffold(containerColor = AppColors.bgPrimary, bottomBar = {
            if (clinicStatus.configured) {
                TextButton(onClick = { showClinicEnrollment = true },
                    modifier = Modifier.fillMaxWidth().navigationBarsPadding()) {
                    Text("Have a clinic invitation?")
                }
            }
        }) { padding ->
            Box(Modifier.fillMaxSize().padding(padding)) {
        PaywallScreen(
            onPurchase = {},
            onPlanPurchase = { plan ->
                (context as? android.app.Activity)?.let { accessViewModel.launchPurchaseFlow(it, plan) }
            },
            offers = offers,
            onRetry = accessViewModel::refreshAccess,
            onRestore = accessViewModel::restorePurchases,
            onDismiss = null,
            subtitle = stringResource(R.string.paywall_access_subtitle),
            isPurchasing = purchasing,
            isRestoring = restoring,
            purchaseError = error,
            onClearError = accessViewModel::clearError,
        )
            }
        }
        return
    }

    val navController = rememberNavController()
    val coroutineScope = rememberCoroutineScope()
    val appContext = LocalContext.current
    val navBackStackEntry by navController.currentBackStackEntryAsState()
    val currentDestination = navBackStackEntry?.destination
    // Export now is a sheet over the screen it opened from; navigation follows that screen.
    val currentRoute = currentDestination?.route.let { route ->
        if (route in EXPORT_SHEET_ROUTES) navController.previousBackStackEntry?.destination?.route else route
    }

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
    LaunchedEffect(sharedSetupCoordinator) {
        sharedSetupCoordinator.imports.filterNotNull().collect {
            // A StateFlow resumes a suspended collector undispatched on the publisher's
            // thread, so this body can run wherever the import was published from.
            // Pin navigation to the main thread: mutating NavController from a
            // background thread half-applies a back-stack entry that later crashes
            // activity destroy ("State must be at least CREATED to move to DESTROYED").
            withContext(Dispatchers.Main.immediate) {
                // A retained import StateFlow can emit before NavHost installs its graph on a
                // cold launch. Wait for the first graph-backed entry before navigating.
                navController.currentBackStackEntryFlow.first()
                // Reuse a retained Shared Setup back-stack entry instead of pushing a second
                // ViewModel. The coordinator keeps the request until Finish/Cancel, so an inactive
                // entry cannot consume a warm ACTION_VIEW before navigation observes it.
                if (navController.currentDestination?.route != SubRoutes.SHARED_SETUP) {
                    val revealedExisting = navController.popBackStack(
                        route = SubRoutes.SHARED_SETUP,
                        inclusive = false,
                    )
                    if (!revealedExisting) {
                        navController.navigate(SubRoutes.SHARED_SETUP) { launchSingleTop = true }
                    }
                }
            }
        }
    }
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

    val settingsViewModel: SettingsViewModel = hiltViewModel()
    LaunchedEffect(myselfClaimRequestId) {
        if (BuildConfig.MYSELF_CLAIM_ENABLED && myselfClaimRequestId > 0 && settingsViewModel.distributionPolicy.purchasesAvailable) {
            navController.currentBackStackEntryFlow.first()
            navController.navigate(SubRoutes.MYSELF_CLAIM) { launchSingleTop = true }
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
            SubRoutes.SHARED_SETUP,
            SubRoutes.DIAGNOSTICS,
            SubRoutes.EXPORT_PROFILES,
        )
    } else {
        emptyList()
    }
    val paywallStartRoutes = if (settingsViewModel.distributionPolicy.purchasesAvailable) {
        listOf(PaywallEntryPoint.UPGRADE.route)
    } else {
        emptyList()
    }
    val knownStartRoutes = NavDestination.entries.map { it.route } +
        listOf(SubRoutes.EXPORT_NOW, SubRoutes.HISTORY) + paywallStartRoutes + debugStartRoutes
    val requestedStart = initialRoute?.takeIf { it in knownStartRoutes }
    // A dialog destination cannot start the graph: open the Archive, then the Export now sheet.
    val startDestination = if (shouldSkipOnboarding) {
        requestedStart?.takeIf { it !in EXPORT_SHEET_ROUTES } ?: NavDestination.ARCHIVE.route
    } else {
        SubRoutes.ONBOARDING
    }
    LaunchedEffect(shouldSkipOnboarding, requestedStart) {
        if (shouldSkipOnboarding && requestedStart in EXPORT_SHEET_ROUTES) {
            navController.currentBackStackEntryFlow.first()
            navController.navigate(SubRoutes.EXPORT_NOW) { launchSingleTop = true }
        }
    }

    // One graph-scoped owner exposes the device-local protection preference, toast, and
    // navigation request to every in-app configuration surface.
    val settings by settingsViewModel.settings.collectAsStateWithLifecycle()
    val sleepDayAttribution by settingsViewModel.sleepDayAttribution.collectAsStateWithLifecycle()
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

        AppNavigationLayout(
            destinations = if (showMainNav) NavDestination.entries else emptyList(),
            currentRoute = currentRoute,
            onExportNow = if (showMainNav) {
                { navController.navigate(SubRoutes.EXPORT_NOW) { launchSingleTop = true } }
            } else {
                null
            },
            // The rail keeps Export now on every destination; the phone's floating button
            // leaves Settings, as on the board.
            showFloatingExportNow = currentRoute != NavDestination.SETTINGS.route,
            onNavigate = { dest ->
                navController.navigate(dest.route) {
                    popUpTo(navController.graph.findStartDestination().id) {
                        saveState = true
                    }
                    launchSingleTop = true
                    restoreState = true
                }
            },
        ) { contentModifier ->
        NavHost(
            navController = navController,
            startDestination = startDestination,
            modifier = contentModifier,
        ) {
            // Onboarding
            composable(SubRoutes.ONBOARDING) {
                val isDebugMarketingCapture = BuildConfig.DEBUG && initialRoute == SubRoutes.ONBOARDING
                OnboardingScreen(
                    onComplete = {
                        navController.navigate(NavDestination.ARCHIVE.route) {
                            popUpTo(SubRoutes.ONBOARDING) { inclusive = true }
                        }
                    },
                    onUseSharedSetup = { navController.navigate(SubRoutes.SHARED_SETUP) },
                    initialPage = if (isDebugMarketingCapture) 1 else 0,
                    allowAutomaticAdvance = !isDebugMarketingCapture,
                )
            }

            composable(NavDestination.ARCHIVE.route) {
                ArchiveScreen(
                    onExportNow = { navController.navigate(SubRoutes.EXPORT_NOW) { launchSingleTop = true } },
                    onOpenHistory = { navController.navigate(SubRoutes.HISTORY) { launchSingleTop = true } },
                    onBackfill = { date -> navController.navigate(SubRoutes.exportBackfill(date)) },
                    onOpenDay = { date -> navController.navigate(SubRoutes.archiveDay(date)) { launchSingleTop = true } },
                    onOpenAutomations = {
                        navController.navigate(NavDestination.AUTOMATIONS.route) {
                            popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                            launchSingleTop = true
                            restoreState = true
                        }
                    },
                )
            }
            composable(SubRoutes.ARCHIVE_DAY) {
                DayPageScreen(
                    onBack = { navController.popBackStack() },
                    onReexport = { date -> navController.navigate(SubRoutes.exportBackfill(date)) },
                )
            }
            // Backfill shares Export now; its route carries the one date to preset.
            listOf(SubRoutes.EXPORT_NOW, SubRoutes.EXPORT_BACKFILL).forEach { route ->
                dialog(
                    route = route,
                    dialogProperties = DialogProperties(usePlatformDefaultWidth = false, decorFitsSystemWindows = false),
                ) { entry ->
                    val closeSheet: () -> Unit = {
                        if (!navController.popBackStack()) {
                            navController.navigate(NavDestination.ARCHIVE.route) { launchSingleTop = true }
                        }
                    }
                    ExportNowSheet(onDismiss = closeSheet) {
                    ExportScreen(
                        asSheet = true,
                        profileSelector = { ExportProfileSelector() },
                        backfillDate = entry.arguments?.getString("date")
                            ?.let { runCatching { LocalDate.parse(it) }.getOrNull() },
                        onBack = closeSheet,
                        onSeeInArchive = {
                            // Close the sheet onto the Archive: back to it when it is below, else open it.
                            if (!navController.popBackStack(NavDestination.ARCHIVE.route, inclusive = false)) {
                                navController.navigate(NavDestination.ARCHIVE.route) {
                                    popUpTo(navController.graph.findStartDestination().id)
                                    launchSingleTop = true
                                }
                            }
                        },
                        sleepDayAttribution = sleepDayAttribution,
                        onNavigateToPaywall = {
                            if (settingsViewModel.distributionPolicy.purchasesAvailable) {
                                navController.navigate(PaywallEntryPoint.EXPORT_LIMIT.route) { popUpTo(route) { inclusive = true } }
                            }
                        },
                        onNavigateToAdvancedSettings = { navController.navigate(SubRoutes.ADVANCED_SETTINGS) { popUpTo(route) { inclusive = true } } },
                        onNavigateToSchedule = { navController.navigate(NavDestination.SCHEDULE.route) {
                            popUpTo(route) { inclusive = true }
                            launchSingleTop = true
                        } },
                        onNavigateToUpgrade = {
                            if (settingsViewModel.distributionPolicy.purchasesAvailable) {
                                navController.navigate(PaywallEntryPoint.UPGRADE.route) { popUpTo(route) { inclusive = true } }
                            }
                        },
                    )
                    }
                }
            }
            composable(NavDestination.SCHEDULE.route) {
                var selectedAutomation by rememberSaveable { mutableStateOf<String?>(null) }
                val automationsProfiles: ExportProfilesViewModel = hiltViewModel()
                BoxWithConstraints(Modifier.fillMaxSize()) {
                    // Same split point as the Archive, so an unfolded foldable in landscape
                    // (about 760 dp beside the rail) shows list and detail together.
                    val twoPane = LocalUsesNavigationRail.current || maxWidth >= GeistBreakpoints.medium.dp
                    val openPaywall = {
                        if (settingsViewModel.distributionPolicy.purchasesAvailable) {
                            navController.navigate(PaywallEntryPoint.SCHEDULE.route)
                        }
                    }
                    val runNow: (String) -> Unit = { id ->
                        runAutomationNow(id, automationsProfiles, protectionEnabled != false, settingsViewModel::showBlockedChangeToast) {
                            navController.navigate(SubRoutes.EXPORT_NOW) { launchSingleTop = true }
                        }
                    }
                    val schedule: @Composable () -> Unit = {
                        AutomationsScreen(
                            onOpenAutomation = { id ->
                                if (twoPane) {
                                    selectedAutomation = id
                                } else {
                                    navController.navigate(SubRoutes.automationDetail(id)) { launchSingleTop = true }
                                }
                            },
                            onEditAutomation = { id ->
                                navController.navigate(SubRoutes.automationCompose(id)) { launchSingleTop = true }
                            },
                            onRunNow = runNow,
                            onOpenScheduleSettings = {
                                navController.navigate(SubRoutes.SCHEDULE_SETTINGS) { launchSingleTop = true }
                            },
                            onNavigateToPaywall = openPaywall,
                            selectedAutomationId = selectedAutomation.takeIf { twoPane },
                        )
                    }
                    if (twoPane) {
                        // List and detail side by side on tablets and unfolded foldables.
                        Row(Modifier.fillMaxSize()) {
                            Box(Modifier.weight(1f)) { schedule() }
                            Box(Modifier.weight(1f).padding(Spacing.md)) {
                                GeistCard(padding = Spacing.xxs) {
                                    AutomationDetailPane(
                                        profileId = selectedAutomation,
                                        onEditProfile = { id -> navController.navigate(SubRoutes.exportProfile(id)) },
                                        onCompose = { id -> navController.navigate(SubRoutes.automationCompose(id)) { launchSingleTop = true } },
                                        onRunNow = runNow,
                                        onDeleted = { selectedAutomation = null },
                                    )
                                }
                            }
                        }
                    } else {
                        ReadableWidth { schedule() }
                    }
                }
            }
            composable(SubRoutes.HISTORY) {
                SubScreenFrame(
                    title = stringResource(R.string.nav_history),
                    onBack = { navController.popBackStack() },
                ) { HistoryScreen() }
            }
            composable(SubRoutes.CLINIC_ACCESS) {
                com.healthmd.presentation.clinic.ClinicAccessScreen(
                    onDone = { navController.popBackStack() }, viewModel = clinicAccessViewModel)
            }
            composable(NavDestination.SETTINGS.route) {
                var settingsDetail by rememberSaveable { mutableStateOf<String?>(null) }
                BoxWithConstraints(Modifier.fillMaxSize()) {
                    // Beside the rail (from `md`) the list and the open entry share the screen.
                    val twoPane = LocalUsesNavigationRail.current
                    // On wide layouts sub-screens open beside Settings instead of over it.
                    val open: (String) -> Unit = { route ->
                        if (twoPane) settingsDetail = route else navController.navigate(route) { launchSingleTop = true }
                    }
                    val list: @Composable () -> Unit = {
                        SettingsScreen(
                            viewModel = settingsViewModel,
                            protectionSettingsRequestId = protectionSettingsRequestId,
                            clinicAccessAvailable = clinicStatus.configured,
                            onNavigateToClinicAccess = { open(SubRoutes.CLINIC_ACCESS) },
                            onNavigateToPaywall = {
                                if (settingsViewModel.distributionPolicy.purchasesAvailable) {
                                    navController.navigate(PaywallEntryPoint.UPGRADE.route)
                                }
                            },
                            onNavigateToMyselfClaim = {
                                if (BuildConfig.MYSELF_CLAIM_ENABLED && settingsViewModel.distributionPolicy.purchasesAvailable) {
                                    navController.navigate(SubRoutes.MYSELF_CLAIM) { launchSingleTop = true }
                                }
                            },
                            onNavigateToExportProfiles = { open(SubRoutes.EXPORT_PROFILES) },
                            onNavigateToClinicianReport = { open(SubRoutes.CLINICIAN_REPORT) },
                            onNavigateToDirectCli = { open(SubRoutes.DIRECT_CLI) },
                            onNavigateToSharedSetup = { navController.navigate(SubRoutes.SHARED_SETUP) },
                            onNavigateToDiagnostics = { open(SubRoutes.DIAGNOSTICS) },
                            onNavigateToFolderDestination = { open(SubRoutes.FOLDER_DESTINATION) },
                            onNavigateToAutomations = {
                                navController.navigate(NavDestination.AUTOMATIONS.route) {
                                    popUpTo(navController.graph.findStartDestination().id) { saveState = true }
                                    launchSingleTop = true
                                    restoreState = true
                                }
                            },
                            // Endpoint and gateway setup lives with the scheduled export target.
                            onNavigateToScheduleSettings = {
                                navController.navigate(SubRoutes.SCHEDULE_SETTINGS) { launchSingleTop = true }
                            },
                            onNavigateToMetrics = { navController.navigate(SubRoutes.METRIC_SELECTION) { launchSingleTop = true } },
                            selectedEntry = if (!twoPane) {
                                null
                            } else {
                                when (settingsDetail) {
                                    SubRoutes.EXPORT_PROFILES -> SettingsEntry.EXPORT_PROFILES
                                    SubRoutes.CLINIC_ACCESS -> SettingsEntry.CLINIC_ACCESS
                                    SubRoutes.CLINICIAN_REPORT -> SettingsEntry.CLINICIAN_REPORT
                                    SubRoutes.DIRECT_CLI -> SettingsEntry.DIRECT_CLI
                                    SubRoutes.DIAGNOSTICS -> SettingsEntry.DIAGNOSTICS
                                    else -> SettingsEntry.FOLDER
                                }
                            },
                        )
                    }
                    if (twoPane) {
                        // The board's list column: 320dp on foldables and small tablets, 420dp wider.
                        val listWidth = if (maxWidth >= SETTINGS_WIDE_LIST_MIN_WIDTH) 420.dp else 320.dp
                        Row(Modifier.fillMaxSize()) {
                            Box(Modifier.width(listWidth)) { list() }
                            Box(Modifier.weight(1f).padding(Spacing.md)) {
                                GeistCard(padding = Spacing.xxs) {
                                    val close = { settingsDetail = null }
                                    when (settingsDetail) {
                                        SubRoutes.EXPORT_PROFILES -> ExportProfilesScreen(onBack = close)
                                        SubRoutes.CLINICIAN_REPORT -> if (personalAccess) {
                                            ClinicianReportScreen(onBack = close)
                                        } else {
                                            Text("Your own Health.md access is required to save or share a report.",
                                                modifier = Modifier.padding(com.healthmd.presentation.theme.Spacing.md))
                                        }
                                        SubRoutes.DIRECT_CLI -> DirectCliScreen(onBack = close)
                                        SubRoutes.DIAGNOSTICS -> DiagnosticsScreen(onBack = close)
                                        SubRoutes.CLINIC_ACCESS -> com.healthmd.presentation.clinic.ClinicAccessScreen(
                                            onDone = close, viewModel = clinicAccessViewModel)
                                        else -> FolderDestinationScreen()
                                    }
                                }
                            }
                        }
                    } else {
                        ReadableWidth { list() }
                    }
                }
            }
            composable(SubRoutes.FOLDER_DESTINATION) {
                SubScreenFrame(
                    title = stringResource(R.string.settings_destination_folder_title),
                    onBack = { navController.popBackStack() },
                ) { ReadableWidth { FolderDestinationScreen() } }
            }

            if (BuildConfig.MYSELF_CLAIM_ENABLED && settingsViewModel.distributionPolicy.purchasesAvailable) {
                composable(SubRoutes.MYSELF_CLAIM) {
                    com.healthmd.myselfclaim.MyselfClaimScreen(onBack = { navController.popBackStack() })
                }
            }

            // Sub-screens
            composable(SubRoutes.DIAGNOSTICS) {
                DiagnosticsScreen(onBack = { navController.popBackStack() })
            }
            composable(SubRoutes.EXPORT_PROFILES) {
                ExportProfilesScreen(onBack = { navController.popBackStack() })
            }
            composable(SubRoutes.EXPORT_PROFILE) { entry ->
                ExportProfilesScreen(
                    onBack = { navController.popBackStack() },
                    initialDetailProfileId = entry.arguments?.getString("profileId"),
                )
            }
            composable(SubRoutes.AUTOMATION_DETAIL) { entry ->
                val profileId = entry.arguments?.getString("profileId")
                SubScreenFrame(
                    title = stringResource(R.string.nav_automations),
                    onBack = { navController.popBackStack() },
                ) {
                    ReadableWidth {
                        val profiles: ExportProfilesViewModel = hiltViewModel()
                        AutomationDetailPane(
                            profileId = profileId,
                            onEditProfile = { id -> navController.navigate(SubRoutes.exportProfile(id)) },
                            onCompose = { id -> navController.navigate(SubRoutes.automationCompose(id)) { launchSingleTop = true } },
                            onRunNow = { id ->
                                runAutomationNow(id, profiles, protectionEnabled != false, settingsViewModel::showBlockedChangeToast) {
                                    navController.navigate(SubRoutes.EXPORT_NOW) { launchSingleTop = true }
                                }
                            },
                            onDeleted = { navController.popBackStack() },
                            profilesViewModel = profiles,
                        )
                    }
                }
            }
            composable(SubRoutes.SCHEDULE_SETTINGS) {
                SubScreenFrame(
                    title = stringResource(R.string.automations_schedule_settings_title),
                    onBack = { navController.popBackStack() },
                ) {
                    ReadableWidth {
                        ScheduleScreen(
                            onNavigateToPaywall = {
                                if (settingsViewModel.distributionPolicy.purchasesAvailable) {
                                    navController.navigate(PaywallEntryPoint.SCHEDULE.route)
                                }
                            },
                        )
                    }
                }
            }
            composable(SubRoutes.AUTOMATION_COMPOSE) { entry ->
                val profileId = entry.arguments?.getString("profileId")
                if (profileId != null) {
                    AutomationComposerScreen(profileId = profileId, onBack = { navController.popBackStack() })
                }
            }
            composable(SubRoutes.DIRECT_CLI) {
                DirectCliScreen(onBack = { navController.popBackStack() })
            }
            composable(SubRoutes.SHARED_SETUP) {
                SharedSetupScreen(
                    onBack = { navController.popBackStack() },
                    onFinishSetup = {
                        if (!navController.popBackStack()) {
                            navController.navigate(NavDestination.SETTINGS.route) { launchSingleTop = true }
                        }
                    },
                )
            }
            composable(SubRoutes.CLINICIAN_REPORT) {
                if (personalAccess) {
                    ClinicianReportScreen(onBack = { navController.popBackStack() })
                } else {
                    Text("Your own Health.md access is required to save or share a report.",
                        modifier = Modifier.padding(com.healthmd.presentation.theme.Spacing.md))
                }
            }
            composable(SubRoutes.ADVANCED_SETTINGS) {
                AdvancedSettingsScreen(
                    settings = settings,
                    sleepDayAttribution = sleepDayAttribution,
                    onNavigateToMetrics = { navController.navigate(SubRoutes.METRIC_SELECTION) },
                    onNavigateToFormatCustomization = { navController.navigate(SubRoutes.FORMAT_CUSTOMIZATION) },
                    onNavigateToDailyNoteInjection = { navController.navigate(SubRoutes.DAILY_NOTE_INJECTION) },
                    onNavigateToIndividualTracking = { navController.navigate(SubRoutes.INDIVIDUAL_TRACKING) },
                    onIncludeGranularDataChanged = {
                        settingsViewModel.performConfigurationChange {
                            settingsViewModel.updateIncludeGranularData(it)
                        }
                    },
                    onSleepDayAttributionChanged = {
                        settingsViewModel.performConfigurationChange {
                            settingsViewModel.updateSleepDayAttribution(it)
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
            if (settingsViewModel.distributionPolicy.purchasesAvailable) {
                PaywallEntryPoint.entries.forEach { entryPoint ->
                    composable(entryPoint.route) {
                        val paywallViewModel: PaywallViewModel = hiltViewModel()
                        val isUnlocked by paywallViewModel.isUnlocked.collectAsStateWithLifecycle()
                        val isPurchasing by paywallViewModel.isPurchasing.collectAsStateWithLifecycle()
                        val isRestoring by paywallViewModel.isRestoring.collectAsStateWithLifecycle()
                        val purchaseError by paywallViewModel.purchaseError.collectAsStateWithLifecycle()
                        val priceText by paywallViewModel.priceText.collectAsStateWithLifecycle()
                        val offers by paywallViewModel.offers.collectAsStateWithLifecycle()
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
                            offers = offers,
                            onPlanPurchase = { plan ->
                                (context as? android.app.Activity)?.let { paywallViewModel.launchPurchaseFlow(it, plan) }
                            },
                            onRetry = paywallViewModel::refreshAccess,
                            onRestore = { paywallViewModel.restorePurchases() },
                            onDismiss = { navController.popBackStack() },
                            subtitle = stringResource(R.string.paywall_access_subtitle),
                            isPurchasing = isPurchasing,
                            isRestoring = isRestoring,
                            priceText = priceText,
                            purchaseError = purchaseError,
                            onClearError = { paywallViewModel.clearError() },
                            isDebugBuild = paywallViewModel.isDebugBuild,
                            debugUnlockOverride = debugUnlockOverride,
                            onDebugToggleUnlock = { paywallViewModel.debugToggleUnlock() },
                            onDebugResetState = { paywallViewModel.debugResetPurchaseState() },
                            purchasesAvailable = paywallViewModel.purchasesAvailable,
                            fullAccessIncluded = paywallViewModel.distributionPolicy.fullAccessIncluded,
                        )
                    }
                }
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
                settingsViewModel.dismissBlockedChangeToast()
                val settingsRoute = NavDestination.SETTINGS.route
                if (navController.currentDestination?.route != settingsRoute) {
                    val revealedExisting = navController.popBackStack(
                        route = settingsRoute,
                        inclusive = false,
                    )
                    if (!revealedExisting) {
                        // This is an explicit settings deep-link, not ordinary tab navigation:
                        // never restore the nested Export Profiles route we are leaving.
                        navController.navigate(settingsRoute) {
                            popUpTo(navController.graph.findStartDestination().id) {
                                saveState = false
                            }
                            launchSingleTop = true
                            restoreState = false
                        }
                    }
                }
                // StateFlow retains the request until Settings composes, then scrolls the
                // protection section into view.
                settingsViewModel.openProtectionSetting()
            },
            modifier = Modifier
                .align(Alignment.TopCenter)
                .statusBarsPadding()
                .padding(horizontal = Spacing.md, vertical = Spacing.sm),
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

/**
 * Run now uses the existing manual path: the automation becomes the active profile and Export
 * now opens on it, with its progress, result and limits. Switching profiles is a configuration
 * change, so a locked configuration only runs the automation that is already active.
 */
private fun runAutomationNow(
    profileId: String,
    profiles: ExportProfilesViewModel,
    configurationLocked: Boolean,
    onBlocked: () -> Unit,
    openExportNow: () -> Unit,
) {
    val active = profiles.uiState.value.rows.firstOrNull { it.profile.id == profileId }?.isActive == true
    if (!active) {
        if (configurationLocked) {
            onBlocked()
            return
        }
        profiles.activate(profileId)
    }
    openExportNow()
}

/** Export now routes shown as a sheet over the current screen. */
private val EXPORT_SHEET_ROUTES = setOf(SubRoutes.EXPORT_NOW, SubRoutes.EXPORT_BACKFILL)

/** Material 3 FAB container height and its margin above the bottom bar. */
private val FLOATING_ACTION_MIN_HEIGHT = 56.dp
private val FLOATING_ACTION_MARGIN = 16.dp

/** Content width from which the Settings list column widens to 420dp. */
private val SETTINGS_WIDE_LIST_MIN_WIDTH = 900.dp

/** Window width below which the navigation rail takes the board's compact 80dp. */
private val COMPACT_RAIL_BREAKPOINT = 1000.dp

/** Reserve the measured navigation size, including wrapped labels, rather than a fixed inset. */
@Composable
internal fun AppNavigationLayout(
    destinations: List<NavDestination>,
    currentRoute: String?,
    onNavigate: (NavDestination) -> Unit,
    onExportNow: (() -> Unit)? = null,
    showFloatingExportNow: Boolean = true,
    content: @Composable (Modifier) -> Unit,
) {
    BoxWithConstraints(
        modifier = Modifier.fillMaxSize().safeDrawingPadding(),
    ) {
        val useNavigationRail = maxWidth >= GeistBreakpoints.medium.dp
        val showsFloatingAction = onExportNow != null && !useNavigationRail && showFloatingExportNow
        // The board's compact rail (below 1000dp) is 80dp; wider windows use 96dp.
        val railWidth = if (maxWidth < COMPACT_RAIL_BREAKPOINT) 80.dp else 96.dp
        val density = LocalDensity.current
        var floatingActionHeight by remember { mutableStateOf(FLOATING_ACTION_MIN_HEIGHT) }
        Row(modifier = Modifier.fillMaxSize()) {
            if (destinations.isNotEmpty() && useNavigationRail) {
                AdaptiveNavigationRail(
                    destinations = destinations,
                    currentRoute = currentRoute,
                    onNavigate = onNavigate,
                    onExportNow = onExportNow,
                    width = railWidth,
                )
            }
            Scaffold(
                modifier = Modifier.weight(1f),
                containerColor = AppColors.bgPrimary,
                // The outer layout consumes system bars/cutouts for all routes.
                contentWindowInsets = WindowInsets(0, 0, 0, 0),
                bottomBar = {
                    if (destinations.isNotEmpty() && !useNavigationRail) {
                        FloatingNavBar(
                            destinations = destinations,
                            currentRoute = currentRoute,
                            onNavigate = onNavigate,
                        )
                    }
                },
                floatingActionButton = {
                    if (onExportNow != null && showsFloatingAction) {
                        // Measured so large font scales still clear the button.
                        Box(
                            Modifier.onSizeChanged {
                                floatingActionHeight = maxOf(with(density) { it.height.toDp() }, FLOATING_ACTION_MIN_HEIGHT)
                            },
                        ) {
                            ExportNowButton(onClick = onExportNow, expanded = true)
                        }
                    }
                },
            ) { padding ->
                val clearance = if (showsFloatingAction) {
                    floatingActionHeight + FLOATING_ACTION_MARGIN + GeistSpacing.space6
                } else {
                    0.dp
                }
                CompositionLocalProvider(
                    LocalFloatingActionClearance provides clearance,
                    LocalUsesNavigationRail provides (destinations.isNotEmpty() && useNavigationRail),
                ) {
                    content(Modifier.fillMaxSize().padding(padding).consumeWindowInsets(padding))
                }
            }
        }
    }
}

@Composable
private fun AdaptiveNavigationRail(
    destinations: List<NavDestination>,
    currentRoute: String?,
    onNavigate: (NavDestination) -> Unit,
    onExportNow: (() -> Unit)?,
    width: androidx.compose.ui.unit.Dp,
    modifier: Modifier = Modifier,
) {
    val colors = LocalGeistColors.current
    NavigationRail(
        modifier = modifier
            .fillMaxHeight()
            .width(width)
            .verticalScroll(rememberScrollState()),
        containerColor = colors.background100,
        contentColor = colors.primary,
        header = if (onExportNow != null) {
            { ExportNowButton(onClick = onExportNow, expanded = false) }
        } else {
            null
        },
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
                    selectedIconColor = colors.onSecondaryContainer,
                    selectedTextColor = colors.primary,
                    indicatorColor = colors.secondaryContainer,
                    unselectedIconColor = colors.secondary,
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
    BoxWithConstraints(
        modifier = modifier
            .fillMaxWidth()
            .background(colors.gray.c100)
            .navigationBarsPadding()
            .heightIn(min = 80.dp)
            .padding(horizontal = Spacing.xs, vertical = Spacing.sm),
    ) {
        val wrapTabs = GeistAdaptiveLayout.wrapNavigation(
            maxWidth.value, LocalDensity.current.fontScale, destinations.size,
        )
        // Widen the reading/touch area instead of turning each label into a narrow
        // stack of syllables. Scaffold still measures the resulting bar height.
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.xs)) {
            val rows = if (wrapTabs) destinations.chunked(2) else listOf(destinations)
            rows.forEach { row ->
                Row(
                    modifier = Modifier.fillMaxWidth().height(IntrinsicSize.Min),
                    horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
                ) {
                    row.forEach { destination ->
                        NavBarTab(
                            destination = destination,
                            selected = currentRoute == destination.route,
                            onClick = { onNavigate(destination) },
                            modifier = Modifier.weight(1f),
                            textOnly = wrapTabs,
                        )
                    }
                    if (wrapTabs && row.size == 1) Spacer(Modifier.weight(1f))
                }
            }
        }
    }
}

@Composable
private fun NavBarTab(
    destination: NavDestination,
    selected: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    textOnly: Boolean = false,
) {
    val colors = LocalGeistColors.current
    val contentColor = if (selected) colors.primary else colors.secondary
    val indicator = if (selected) colors.secondaryContainer else Color.Transparent
    val label = stringResource(destination.label)

    Column(
        modifier = modifier
            .fillMaxHeight()
            .heightIn(min = GeistSizes.minimumTouchTarget)
            .selectable(
                selected = selected,
                onClick = onClick,
                role = Role.Tab,
            )
            .padding(vertical = Spacing.xxs),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.Center,
    ) {
        if (!textOnly) {
            Box(
                modifier = Modifier
                    .size(width = 64.dp, height = 32.dp)
                    .background(indicator, RoundedCornerShape(GeistRadii.full)),
                contentAlignment = Alignment.Center,
            ) {
                Icon(
                    destination.icon,
                    contentDescription = null,
                    tint = if (selected) colors.onSecondaryContainer else contentColor,
                    modifier = Modifier.size(24.dp),
                )
            }
            Spacer(modifier = Modifier.height(Spacing.xxs))
        }
        Text(
            label,
            color = contentColor,
            style = if (selected) GeistType.button12 else GeistType.label12,
            textAlign = androidx.compose.ui.text.style.TextAlign.Center,
            modifier = if (textOnly) {
                Modifier
                    .background(indicator, RoundedCornerShape(GeistRadii.full))
                    .padding(horizontal = Spacing.sm, vertical = Spacing.xxs)
            } else {
                Modifier
            },
        )
    }
}

/** The global Export now action: extended on compact layouts, an icon FAB atop the rail. */
@Composable
private fun ExportNowButton(onClick: () -> Unit, expanded: Boolean) {
    val colors = LocalGeistColors.current
    val label = stringResource(R.string.export_now_title)
    if (expanded) {
        ExtendedFloatingActionButton(
            onClick = onClick,
            icon = { Icon(Icons.Outlined.FileUpload, contentDescription = null) },
            text = { Text(label, style = GeistType.button14) },
            containerColor = colors.brandSubtle,
            contentColor = colors.brandOnSubtle,
            shape = RoundedCornerShape(GeistRadii.medium),
        )
    } else {
        FloatingActionButton(
            onClick = onClick,
            containerColor = colors.brandSubtle,
            contentColor = colors.brandOnSubtle,
            shape = RoundedCornerShape(GeistRadii.medium),
        ) {
            Icon(Icons.Outlined.FileUpload, contentDescription = label)
        }
    }
}

/** A sub-screen with Back and a title above content that has no header of its own. */
@Composable
private fun SubScreenFrame(
    title: String,
    onBack: () -> Unit,
    content: @Composable () -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        Row(
            modifier = Modifier.fillMaxWidth().padding(horizontal = Spacing.xxs, vertical = Spacing.xs),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            IconButton(onClick = onBack) {
                Icon(
                    Icons.AutoMirrored.Outlined.ArrowBack,
                    contentDescription = stringResource(R.string.back),
                    tint = AppColors.textPrimary,
                )
            }
            Text(title, style = MaterialTheme.typography.headlineSmall, color = AppColors.textPrimary)
        }
        Box(Modifier.weight(1f)) { content() }
    }
}

/** Centers single-column screens at a readable width on tablets and unfolded foldables. */
@Composable
private fun ReadableWidth(content: @Composable () -> Unit) {
    Box(Modifier.fillMaxSize(), contentAlignment = Alignment.TopCenter) {
        Box(Modifier.widthIn(max = GeistSizes.readableContentMaxWidth).fillMaxSize()) { content() }
    }
}
