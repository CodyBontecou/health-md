package com.healthmd.presentation.onboarding

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.PagerState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.automirrored.outlined.ArrowForward
import androidx.compose.material.icons.outlined.Favorite
import androidx.compose.material.icons.outlined.FolderOpen
import androidx.compose.material.icons.outlined.RocketLaunch
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalLayoutDirection
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.unit.LayoutDirection
import com.healthmd.R
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.theme.*
import kotlin.math.absoluteValue

internal val LocalOnboardingReadingLayout = staticCompositionLocalOf { false }

internal object OnboardingTestTags {
    const val PRIMARY_ACTION = "onboarding.primaryAction"
    const val BODY = "onboarding.body"
    const val HERO = "onboarding.hero"
}

/** Explanation scrolls independently of a single, always-visible next action. */
@Composable
internal fun OnboardingLayout(
    pages: List<OnboardingPage>,
    pagerState: PagerState,
    canContinue: Boolean,
    onBack: () -> Unit,
    onContinue: () -> Unit,
    onSkip: () -> Unit,
    onGrantHealthAccess: () -> Unit,
    onSelectFolder: () -> Unit,
    onComplete: () -> Unit,
    content: @Composable (OnboardingPage) -> Unit,
) {
    val motionDirection = if (LocalLayoutDirection.current == LayoutDirection.Ltr) 1f else -1f
    val currentPage = pages[pagerState.currentPage]
    val needsSetup = !canContinue && currentPage in listOf(OnboardingPage.HEALTH_ACCESS, OnboardingPage.FOLDER_SETUP)

    BoxWithConstraints(
        modifier = Modifier.fillMaxSize().background(AppColors.bgPrimary).safeDrawingPadding(),
    ) {
        val readingLayout = GeistAdaptiveLayout.readingFirst(
            maxWidth.value, maxHeight.value, LocalDensity.current.fontScale,
        )
        CompositionLocalProvider(LocalOnboardingReadingLayout provides readingLayout) {
            Column(modifier = Modifier.fillMaxSize()) {
                Row(
                    modifier = Modifier
                        .fillMaxWidth()
                        .padding(horizontal = Spacing.md, vertical = Spacing.xs),
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(Spacing.xs),
                ) {
                    if (currentPage != OnboardingPage.WELCOME && currentPage != OnboardingPage.READY) {
                        IconButton(onClick = onBack) {
                            Icon(
                                Icons.AutoMirrored.Outlined.ArrowBack,
                                contentDescription = stringResource(R.string.onboarding_back),
                                tint = AppColors.textSecondary,
                            )
                        }
                    } else {
                        Spacer(Modifier.size(GeistSizes.minimumTouchTarget))
                    }

                    if (readingLayout) {
                        LinearProgressIndicator(
                            progress = { (pagerState.currentPage + 1f) / pages.size },
                            modifier = Modifier.weight(1f).height(Spacing.xxs),
                            color = AppColors.accent,
                            trackColor = AppColors.borderDefault,
                        )
                    } else {
                        Row(
                            modifier = Modifier.weight(1f),
                            horizontalArrangement = Arrangement.Center,
                        ) {
                            repeat(pages.size) { index ->
                                val selected = pagerState.currentPage == index
                                val width by animateDpAsState(
                                    targetValue = if (selected) Spacing.lg else Spacing.xs,
                                    animationSpec = tween(GeistMotion.stateChange, easing = GeistMotion.easing),
                                    label = "indicatorWidth",
                                )
                                Box(
                                    Modifier.padding(horizontal = Spacing.xxs)
                                        .height(Spacing.xs).width(width).clip(CircleShape)
                                        .background(if (selected) AppColors.accent else AppColors.borderStrong),
                                )
                            }
                        }
                    }

                    if (needsSetup) {
                        TextButton(onClick = onSkip) {
                            Text(stringResource(R.string.onboarding_skip), color = AppColors.textSecondary)
                        }
                    } else {
                        Spacer(Modifier.size(GeistSizes.minimumTouchTarget))
                    }
                }

                HorizontalPager(state = pagerState, modifier = Modifier.weight(1f)) { page ->
                    val pageOffset = (pagerState.currentPage - page) + pagerState.currentPageOffsetFraction
                    Box(
                        modifier = Modifier.fillMaxSize().graphicsLayer {
                            alpha = 1f - pageOffset.absoluteValue.coerceIn(0f, 1f) * 0.4f
                            translationX = pageOffset * 100f * motionDirection
                        },
                    ) {
                        content(pages[page])
                    }
                }

                HorizontalDivider(color = AppColors.borderDefault)
                Box(modifier = Modifier.fillMaxWidth().padding(Spacing.md)) {
                    val modifier = Modifier.fillMaxWidth().testTag(OnboardingTestTags.PRIMARY_ACTION)
                    when {
                        currentPage == OnboardingPage.HEALTH_ACCESS && needsSetup -> PrimaryButton(
                            text = stringResource(R.string.onboarding_health_grant_button),
                            onClick = onGrantHealthAccess,
                            icon = Icons.Outlined.Favorite,
                            modifier = modifier,
                        )
                        currentPage == OnboardingPage.FOLDER_SETUP && needsSetup -> PrimaryButton(
                            text = stringResource(R.string.onboarding_storage_select_button),
                            onClick = onSelectFolder,
                            icon = Icons.Outlined.FolderOpen,
                            modifier = modifier,
                        )
                        currentPage == OnboardingPage.READY -> PrimaryButton(
                            text = stringResource(R.string.onboarding_ready_start_button),
                            onClick = onComplete,
                            icon = Icons.Outlined.RocketLaunch,
                            modifier = modifier,
                        )
                        currentPage == OnboardingPage.PLAY_ACCESS -> SecondaryButton(
                            text = stringResource(R.string.onboarding_continue),
                            onClick = onContinue,
                            icon = Icons.AutoMirrored.Outlined.ArrowForward,
                            modifier = modifier,
                        )
                        else -> PrimaryButton(
                            text = stringResource(R.string.onboarding_continue),
                            onClick = onContinue,
                            icon = Icons.AutoMirrored.Outlined.ArrowForward,
                            modifier = modifier,
                        )
                    }
                }
            }
        }
    }
}
