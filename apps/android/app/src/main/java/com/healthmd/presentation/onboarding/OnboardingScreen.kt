package com.healthmd.presentation.onboarding

import android.app.Activity
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.runtime.*
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.health.HealthConnectIntentLauncher
import com.healthmd.data.health.HealthConnectLaunchResult
import com.healthmd.data.health.HealthConnectManager
import com.healthmd.data.health.HealthConnectPermissionPolicy
import com.healthmd.data.health.grantedAnyRequestedHealthPermission
import com.healthmd.data.health.tryLaunchHealthConnectPermissions
import com.healthmd.presentation.common.HealthConnectActionError
import com.healthmd.presentation.paywall.PaywallScreen
import com.healthmd.presentation.paywall.PaywallViewModel
import kotlinx.coroutines.launch

@Composable
fun OnboardingScreen(
    viewModel: OnboardingViewModel = hiltViewModel(),
    paywallViewModel: PaywallViewModel = hiltViewModel(),
    onComplete: () -> Unit,
    onUseSharedSetup: () -> Unit = {},
    initialPage: Int = 0,
    allowAutomaticAdvance: Boolean = true,
) {
    val uiState by viewModel.uiState.collectAsStateWithLifecycle()
    val pages = viewModel.pages
    val distributionPolicy = viewModel.distributionPolicy
    val healthPageIndex = pages.indexOf(OnboardingPage.HEALTH_ACCESS)
    val folderPageIndex = pages.indexOf(OnboardingPage.FOLDER_SETUP)
    val accessPageIndex = pages.indexOfFirst {
        it == OnboardingPage.PLAY_ACCESS || it == OnboardingPage.INCLUDED_ACCESS
    }
    val readyPageIndex = pages.indexOf(OnboardingPage.READY)
    val isUnlocked by paywallViewModel.isUnlocked.collectAsStateWithLifecycle()
    val isPurchasing by paywallViewModel.isPurchasing.collectAsStateWithLifecycle()
    val isRestoring by paywallViewModel.isRestoring.collectAsStateWithLifecycle()
    val purchaseError by paywallViewModel.purchaseError.collectAsStateWithLifecycle()
    val priceText by paywallViewModel.priceText.collectAsStateWithLifecycle()
    val debugUnlockOverride by paywallViewModel.debugUnlockOverride.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val lifecycleOwner = LocalLifecycleOwner.current
    val coroutineScope = rememberCoroutineScope()
    var advanceAfterUnlock by remember { mutableStateOf(false) }
    val selectedFolderFallback = stringResource(R.string.onboarding_storage_selected_folder_fallback)
    val folderDisplayName = uiState.folderUri?.let { uiState.folderName ?: selectedFolderFallback }

    val healthConnectManager = remember { HealthConnectManager(context) }
    val healthConnectIntentLauncher = remember { HealthConnectIntentLauncher(context) }
    var capabilityRefreshGeneration by remember { mutableIntStateOf(0) }
    var dismissedFeatureErrorGeneration by remember { mutableIntStateOf(-1) }
    var pendingPermissionRequest by remember { mutableStateOf<Set<String>>(emptySet()) }
    val permissionContract = remember { healthConnectManager.getPermissionContract() }
    val permissionLauncher = rememberLauncherForActivityResult(
        contract = permissionContract,
    ) { grantedPermissions ->
        capabilityRefreshGeneration++
        if (
            pendingPermissionRequest.isNotEmpty() &&
            !grantedAnyRequestedHealthPermission(pendingPermissionRequest, grantedPermissions)
        ) {
            viewModel.reportHealthConnectActionError(HealthConnectActionError.PERMISSION_DENIED)
        }
        pendingPermissionRequest = emptySet()
        viewModel.refreshPermissions()
    }

    val folderPickerLauncher = rememberLauncherForActivityResult(
        contract = ActivityResultContracts.OpenDocumentTree(),
    ) { uri -> uri?.let { viewModel.onFolderSelected(it) } }

    val permissionPlan = remember(
        capabilityRefreshGeneration,
        uiState.healthConnectAvailable,
    ) {
        if (uiState.healthConnectAvailable) {
            healthConnectManager.permissionPlan()
        } else {
            HealthConnectPermissionPolicy.create { false }
        }
    }

    val healthConnectError = uiState.healthConnectActionError ?: if (
        permissionPlan.featureStatusCheckFailed &&
        dismissedFeatureErrorGeneration != capabilityRefreshGeneration
    ) {
        HealthConnectActionError.ACCESS_CHECK_FAILED
    } else {
        null
    }

    DisposableEffect(lifecycleOwner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) {
                capabilityRefreshGeneration++
                viewModel.refreshPermissions()
            }
        }
        lifecycleOwner.lifecycle.addObserver(observer)
        onDispose { lifecycleOwner.lifecycle.removeObserver(observer) }
    }

    val pagerState = rememberPagerState(
        initialPage = initialPage.coerceIn(0, pages.lastIndex),
        pageCount = { pages.size },
    )

    LaunchedEffect(Unit) {
        viewModel.recordInitialOnboarding()
    }

    // Only settled pages are milestones; transient pages crossed during a fling are not recorded.
    // Welcome is recorded sequentially after the start event so cohort ordering is deterministic.
    LaunchedEffect(pagerState.settledPage) {
        if (pagerState.settledPage != 0) {
            viewModel.recordSettledPage(pages[pagerState.settledPage])
        }
    }

    // Key auto-advance to the settled page. currentPage changes around the halfway
    // point of an animation, which would cancel this effect and leave the pager mid-swipe.
    LaunchedEffect(uiState.hasPermissions, pagerState.settledPage, allowAutomaticAdvance) {
        if (allowAutomaticAdvance && pagerState.settledPage == healthPageIndex && uiState.hasPermissions) {
            kotlinx.coroutines.delay(800)
            pagerState.animateScrollToPage(folderPageIndex)
        }
    }

    LaunchedEffect(uiState.folderUri, pagerState.settledPage, allowAutomaticAdvance) {
        if (allowAutomaticAdvance && pagerState.settledPage == folderPageIndex && uiState.folderUri != null) {
            kotlinx.coroutines.delay(800)
            pagerState.animateScrollToPage(accessPageIndex)
        }
    }

    // Only advance for an unlock initiated from this page. Existing purchasers
    // should still see the onboarding paywall instead of being immediately skipped.
    LaunchedEffect(isUnlocked, advanceAfterUnlock, pagerState.settledPage) {
        if (isUnlocked && advanceAfterUnlock && pagerState.settledPage == accessPageIndex) {
            advanceAfterUnlock = false
            pagerState.animateScrollToPage(readyPageIndex)
        }
    }

    OnboardingLayout(
        pages = pages,
        pagerState = pagerState,
        canContinue = when (pages[pagerState.currentPage]) {
            OnboardingPage.HEALTH_ACCESS -> uiState.hasPermissions
            OnboardingPage.FOLDER_SETUP -> uiState.folderUri != null
            else -> true
        },
        onBack = {
            coroutineScope.launch {
                pagerState.animateScrollToPage(pagerState.currentPage - 1)
            }
        },
        onContinue = {
            if (pages[pagerState.currentPage] == OnboardingPage.PLAY_ACCESS && !isUnlocked) {
                viewModel.recordContinueFreeTapped()
            }
            coroutineScope.launch {
                if (pagerState.currentPage < pages.lastIndex) {
                    pagerState.animateScrollToPage(pagerState.currentPage + 1)
                }
            }
        },
        onSkip = {
            when (pages[pagerState.currentPage]) {
                OnboardingPage.HEALTH_ACCESS -> viewModel.recordHealthSkipped()
                OnboardingPage.FOLDER_SETUP -> viewModel.recordFolderSkipped()
                else -> Unit
            }
            coroutineScope.launch {
                pagerState.animateScrollToPage(pagerState.currentPage + 1)
            }
        },
        onGrantHealthAccess = {
            viewModel.clearHealthConnectActionError()
            when {
                !uiState.healthConnectAvailable -> {
                    if (healthConnectIntentLauncher.openInstallOrUpdate() == HealthConnectLaunchResult.FAILED) {
                        viewModel.reportHealthConnectActionError(HealthConnectActionError.INSTALL_LAUNCH_FAILED)
                    }
                }
                uiState.healthConnectNeedsSetup -> {
                    if (healthConnectIntentLauncher.openSettings() == HealthConnectLaunchResult.FAILED) {
                        viewModel.reportHealthConnectActionError(HealthConnectActionError.SETTINGS_LAUNCH_FAILED)
                    }
                }
                else -> {
                    pendingPermissionRequest = permissionPlan.foregroundPermissions
                    if (!tryLaunchHealthConnectPermissions(pendingPermissionRequest, permissionLauncher::launch)) {
                        pendingPermissionRequest = emptySet()
                        viewModel.reportHealthConnectActionError(HealthConnectActionError.PERMISSION_REQUEST_FAILED)
                    }
                }
            }
        },
        onSelectFolder = { folderPickerLauncher.launch(null) },
        onComplete = { viewModel.completeOnboarding(onComplete) },
    ) { page ->
        when (page) {
            OnboardingPage.WELCOME -> WelcomePage(onUseSharedSetup = onUseSharedSetup)
            OnboardingPage.HEALTH_ACCESS -> HealthAccessPage(
                hasPermissions = uiState.hasPermissions,
                actionError = healthConnectError,
                onDismissError = {
                    dismissedFeatureErrorGeneration = capabilityRefreshGeneration
                    viewModel.clearHealthConnectActionError()
                },
            )
            OnboardingPage.FOLDER_SETUP -> StorageSetupPage(
                folderName = folderDisplayName,
                onSelectFolder = { folderPickerLauncher.launch(null) },
            )
            OnboardingPage.PLAY_ACCESS -> PaywallScreen(
                onPurchase = {
                    viewModel.recordPurchaseTapped()
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
                purchaseError = purchaseError,
                onClearError = paywallViewModel::clearError,
                subtitle = stringResource(R.string.schedule_unlock_required_body),
                isDebugBuild = paywallViewModel.isDebugBuild,
                debugUnlockOverride = debugUnlockOverride,
                onDebugToggleUnlock = {
                    advanceAfterUnlock = !isUnlocked
                    paywallViewModel.debugToggleUnlock()
                },
                onDebugResetState = paywallViewModel::debugResetPurchaseState,
                purchasesAvailable = paywallViewModel.purchasesAvailable,
                fullAccessIncluded = distributionPolicy.fullAccessIncluded,
            )
            OnboardingPage.INCLUDED_ACCESS -> IncludedAccessPage()
            OnboardingPage.READY -> ReadyPage()
        }
    }
}
