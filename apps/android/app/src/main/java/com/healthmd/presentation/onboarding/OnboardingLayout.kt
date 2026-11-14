package com.healthmd.presentation.onboarding

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.automirrored.outlined.ArrowBack
import androidx.compose.material.icons.outlined.Bedtime
import androidx.compose.material.icons.outlined.Bolt
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.MonitorWeight
import androidx.compose.material.icons.outlined.Restaurant
import androidx.compose.material.icons.outlined.SelfImprovement
import androidx.compose.material.icons.outlined.WaterDrop
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.onboarding.HealthPack
import com.healthmd.presentation.theme.*

/** True at large font scales or small windows: no decorative illustrations, start-aligned text. */
internal val LocalOnboardingReadingLayout = staticCompositionLocalOf { false }

internal object OnboardingTestTags {
    const val PRIMARY_ACTION = "onboarding.primaryAction"
    const val SECONDARY_ACTION = "onboarding.secondaryAction"
    const val BODY = "onboarding.body"
    const val HERO = "onboarding.hero"
    const val PACK = "onboarding.pack"
    const val SELECT_ALL = "onboarding.selectAll"
    const val DESTINATION = "onboarding.destination"
    const val DAY = "onboarding.day"
    const val RAW_TOGGLE = "onboarding.rawToggle"
    const val RAW_FILE = "onboarding.rawFile"
    const val SAMPLE_NOTICE = "onboarding.sampleNotice"
    const val DRIVE_CHANGE = "onboarding.driveChange"
    const val DRIVE_ERROR = "onboarding.driveError"
}

/**
 * One onboarding step: a header (Back, progress, optional Skip), a body that scrolls on its own,
 * and footer actions that always stay visible (DESIGN.md text-scaling rules).
 */
@Composable
internal fun OnboardingStepScaffold(
    step: OnboardingStep,
    onBack: (() -> Unit)?,
    onSkip: (() -> Unit)? = null,
    footer: @Composable ColumnScope.() -> Unit,
    body: @Composable ColumnScope.() -> Unit,
) {
    BoxWithConstraints(Modifier.fillMaxSize().background(AppColors.bgPrimary).safeDrawingPadding()) {
        val reading = GeistAdaptiveLayout.readingFirst(maxWidth.value, maxHeight.value, LocalDensity.current.fontScale)
        CompositionLocalProvider(LocalOnboardingReadingLayout provides reading) {
            Column(Modifier.fillMaxSize()) {
                OnboardingHeader(step, onBack, onSkip)
                Column(
                    modifier = Modifier
                        .weight(1f)
                        .fillMaxWidth()
                        .testTag(OnboardingTestTags.BODY)
                        .verticalScroll(rememberScrollState())
                        .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
                    verticalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
                    content = body,
                )
                Column(
                    modifier = Modifier.fillMaxWidth().padding(
                        start = GeistSpacing.space4,
                        end = GeistSpacing.space4,
                        top = GeistSpacing.space2,
                        bottom = GeistSpacing.space4,
                    ),
                    verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
                    horizontalAlignment = Alignment.CenterHorizontally,
                    content = footer,
                )
            }
        }
    }
}

@Composable
private fun OnboardingHeader(step: OnboardingStep, onBack: (() -> Unit)?, onSkip: (() -> Unit)?) {
    val progress = OnboardingFlow.progressIndex(step)
    if (onBack == null && onSkip == null && progress == null) {
        Spacer(Modifier.height(GeistSpacing.space8))
        return
    }
    Row(
        Modifier.fillMaxWidth().heightIn(min = GeistSizes.minimumTouchTarget).padding(horizontal = GeistSpacing.space1),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Box(Modifier.widthIn(min = GeistSizes.minimumTouchTarget)) {
            if (onBack != null) {
                IconButton(onClick = onBack) {
                    Icon(
                        Icons.AutoMirrored.Outlined.ArrowBack,
                        contentDescription = stringResource(R.string.onboarding_back),
                        tint = AppColors.textPrimary,
                    )
                }
            }
        }
        Box(Modifier.weight(1f), contentAlignment = Alignment.Center) {
            if (progress != null) ProgressDots(progress, OnboardingFlow.PROGRESS_STEPS)
        }
        Box(Modifier.widthIn(min = GeistSizes.minimumTouchTarget), contentAlignment = Alignment.CenterEnd) {
            if (onSkip != null) {
                TextButton(onClick = onSkip) {
                    Text(stringResource(R.string.onboarding_skip), style = GeistType.button14, color = AppColors.accent)
                }
            }
        }
    }
}

@Composable
private fun ProgressDots(current: Int, total: Int) {
    val colors = LocalGeistColors.current
    val label = stringResource(R.string.onboarding_progress, current + 1, total)
    Row(
        Modifier.clearAndSetSemantics { contentDescription = label },
        horizontalArrangement = Arrangement.spacedBy(6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        repeat(total) { index ->
            val selected = index == current
            val width by animateDpAsState(
                targetValue = if (selected) GeistSpacing.space6 else 6.dp,
                animationSpec = tween(GeistMotion.stateChange, easing = GeistMotion.easing),
                label = "onboardingDot",
            )
            Box(
                Modifier.height(6.dp).width(width).clip(CircleShape)
                    .background(if (selected) colors.brandPrimary else colors.gray.c500),
            )
        }
    }
}

/** Two-tone headline: primary lead, brand-coloured accent ("What goes in your daily note?"). */
@Composable
internal fun OnboardingTitle(lead: String, accent: String, large: Boolean = false) {
    val colors = LocalGeistColors.current
    Text(
        text = buildAnnotatedString {
            append(lead)
            append(if (large) "\n" else " ")
            withStyle(SpanStyle(color = colors.brandPrimary)) { append(accent) }
        },
        style = if (large) GeistType.heading40 else GeistType.heading32,
        color = colors.primary,
        modifier = Modifier.fillMaxWidth().semantics { heading() },
    )
}

@Composable
internal fun OnboardingBodyText(text: String) {
    Text(text, style = GeistType.copy16, color = LocalGeistColors.current.secondary, modifier = Modifier.fillMaxWidth())
}

/** The step's single 48dp pill primary action, in the inverse (primary text) tone of the design. */
@Composable
internal fun OnboardingPrimaryButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    isLoading: Boolean = false,
    leadingIcon: ImageVector? = null,
    trailingIcon: ImageVector? = null,
) {
    val colors = LocalGeistColors.current
    Button(
        onClick = onClick,
        enabled = enabled && !isLoading,
        modifier = modifier.fillMaxWidth().defaultMinSize(minHeight = GeistSizes.controlLarge)
            .testTag(OnboardingTestTags.PRIMARY_ACTION),
        shape = RoundedCornerShape(GeistRadii.full),
        colors = ButtonDefaults.buttonColors(
            containerColor = colors.primary,
            contentColor = colors.background100,
            disabledContainerColor = colors.gray.c300,
            disabledContentColor = colors.gray.c700,
        ),
        elevation = ButtonDefaults.buttonElevation(defaultElevation = 0.dp),
    ) {
        if (isLoading) {
            CircularProgressIndicator(Modifier.size(20.dp), color = colors.background100, strokeWidth = 2.dp)
        } else {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                leadingIcon?.let { Icon(it, contentDescription = null, modifier = Modifier.size(18.dp)) }
                Text(text, style = GeistType.button14)
                trailingIcon?.let { Icon(it, contentDescription = null, modifier = Modifier.size(18.dp)) }
            }
        }
    }
}

@Composable
internal fun OnboardingSecondaryButton(text: String, onClick: () -> Unit, enabled: Boolean = true) {
    TextButton(
        onClick = onClick,
        enabled = enabled,
        modifier = Modifier.fillMaxWidth().defaultMinSize(minHeight = GeistSizes.minimumTouchTarget)
            .testTag(OnboardingTestTags.SECONDARY_ACTION),
    ) {
        Text(text, style = GeistType.button14, color = LocalGeistColors.current.secondary)
    }
}

@Composable
internal fun OnboardingFootnote(text: String, icon: ImageVector? = null) {
    val colors = LocalGeistColors.current
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        icon?.let { Icon(it, contentDescription = null, tint = colors.secondary, modifier = Modifier.size(14.dp)) }
        Text(text, style = GeistType.copy13, color = colors.secondary)
    }
}

/** Pack identity tones from the documented automation/chart ramps. */
internal data class PackTone(val container: Color, val content: Color)

@Composable
internal fun HealthPack.tone(): PackTone {
    val colors = LocalGeistColors.current
    val ramp = when (this) {
        HealthPack.SLEEP -> colors.blue
        HealthPack.ACTIVITY -> colors.amber
        HealthPack.HEART -> colors.red
        HealthPack.BODY -> colors.teal
        HealthPack.MIND -> colors.purple
        HealthPack.NUTRITION -> colors.green
        HealthPack.CYCLE -> colors.pink
    }
    return PackTone(ramp.c200, ramp.c900)
}

internal val HealthPack.icon: ImageVector
    get() = when (this) {
        HealthPack.SLEEP -> Icons.Outlined.Bedtime
        HealthPack.ACTIVITY -> Icons.Outlined.Bolt
        HealthPack.HEART -> Icons.Outlined.FavoriteBorder
        HealthPack.BODY -> Icons.Outlined.MonitorWeight
        HealthPack.MIND -> Icons.Outlined.SelfImprovement
        HealthPack.NUTRITION -> Icons.Outlined.Restaurant
        HealthPack.CYCLE -> Icons.Outlined.WaterDrop
    }

internal val HealthPack.nameRes: Int
    get() = when (this) {
        HealthPack.SLEEP -> R.string.onboarding_pack_sleep
        HealthPack.ACTIVITY -> R.string.onboarding_pack_activity
        HealthPack.HEART -> R.string.onboarding_pack_heart
        HealthPack.BODY -> R.string.onboarding_pack_body
        HealthPack.MIND -> R.string.onboarding_pack_mind
        HealthPack.NUTRITION -> R.string.onboarding_pack_nutrition
        HealthPack.CYCLE -> R.string.onboarding_pack_cycle
    }

internal val HealthPack.detailRes: Int
    get() = when (this) {
        HealthPack.SLEEP -> R.string.onboarding_pack_sleep_detail
        HealthPack.ACTIVITY -> R.string.onboarding_pack_activity_detail
        HealthPack.HEART -> R.string.onboarding_pack_heart_detail
        HealthPack.BODY -> R.string.onboarding_pack_body_detail
        HealthPack.MIND -> R.string.onboarding_pack_mind_detail
        HealthPack.NUTRITION -> R.string.onboarding_pack_nutrition_detail
        HealthPack.CYCLE -> R.string.onboarding_pack_cycle_detail
    }

/** Rounded icon tile in a pack's tone. */
@Composable
internal fun PackIconTile(pack: HealthPack, size: androidx.compose.ui.unit.Dp = GeistSizes.control) {
    val tone = pack.tone()
    Box(
        Modifier.size(size).background(tone.container, RoundedCornerShape(GeistSpacing.space3)),
        contentAlignment = Alignment.Center,
    ) {
        Icon(pack.icon, contentDescription = null, tint = tone.content, modifier = Modifier.size(size / 2))
    }
}
