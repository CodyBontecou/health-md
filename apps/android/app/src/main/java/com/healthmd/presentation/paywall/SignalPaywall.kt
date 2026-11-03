package com.healthmd.presentation.paywall

import android.provider.Settings
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.pager.HorizontalPager
import androidx.compose.foundation.pager.rememberPagerState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Close
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.HorizontalDivider
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.ui.unit.toSize
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.PathMeasure
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.SpanStyle
import androidx.compose.ui.text.buildAnnotatedString
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.withStyle
import androidx.compose.ui.unit.dp
import com.healthmd.presentation.theme.LocalGeistColors
import androidx.compose.ui.unit.Dp
import com.healthmd.R
import com.healthmd.domain.repository.PurchaseOffer
import com.healthmd.domain.repository.PurchasePlan
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistBreakpoints
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.Spacing
import kotlinx.coroutines.launch

private enum class SignalSlide { ARCHIVE, TRIAL, PLANS }

/** Plan order on the plans slide; Yearly leads as the default "Best value" choice. */
private val signalPlanOrder = listOf(PurchasePlan.YEARLY, PurchasePlan.WEEKLY, PurchasePlan.LIFETIME)

private val signalBandHeight = 132.dp

/**
 * Purchase story told across three slides: the archive, the trial, the plans.
 * One decorative signal line runs through every slide at the same height so it
 * reads as continuous while paging. Offers and trial eligibility come from
 * Google Play; this composable owns only slide and plan selection.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun SignalPaywallCarousel(
    offers: List<PurchaseOffer>,
    onPlanPurchase: (PurchasePlan) -> Unit,
    onRestore: () -> Unit,
    onRetry: () -> Unit,
    onDismiss: (() -> Unit)?,
    isPurchasing: Boolean,
    isRestoring: Boolean,
    errorMessage: String?,
    modifier: Modifier = Modifier,
) {
    val isBusy = isPurchasing || isRestoring
    val orderedOffers = remember(offers) { signalPlanOrder.mapNotNull { plan -> offers.firstOrNull { it.plan == plan } } }
    // The trial slide promises a free week, so it appears while offers load and
    // whenever Play offers one; it hides only once Play confirms no trial.
    val slides = remember(orderedOffers) {
        if (orderedOffers.isEmpty() || orderedOffers.any { it.hasSevenDayTrial }) SignalSlide.entries.toList()
        else listOf(SignalSlide.ARCHIVE, SignalSlide.PLANS)
    }
    var selectedPlan by rememberSaveable { mutableStateOf(PurchasePlan.YEARLY) }
    val selected = orderedOffers.firstOrNull { it.plan == selectedPlan } ?: orderedOffers.firstOrNull()
    val trialOffer = selected?.takeIf { it.plan != PurchasePlan.LIFETIME }
        ?: orderedOffers.firstOrNull { it.plan != PurchasePlan.LIFETIME }

    val pagerState = rememberPagerState(pageCount = { slides.size })
    val scope = rememberCoroutineScope()
    fun goTo(page: Int) { scope.launch { pagerState.animateScrollToPage(page) } }

    BoxWithConstraints(modifier.fillMaxSize()) {
        val scrollWholePaywall = LocalDensity.current.fontScale >= GeistAdaptiveLayout.readingFontScale ||
            maxHeight.value < GeistBreakpoints.small
        val pageHeight = maxHeight
        Column(
            modifier = Modifier
                .fillMaxSize()
                .background(AppColors.bgPrimary)
                .then(if (scrollWholePaywall) Modifier.verticalScroll(rememberScrollState()) else Modifier),
        ) {
            if (onDismiss != null) {
                Row(
                    modifier = Modifier.fillMaxWidth().statusBarsPadding().padding(horizontal = Spacing.xs),
                    horizontalArrangement = Arrangement.End,
                ) {
                    IconButton(onClick = onDismiss, enabled = !isBusy) {
                        Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close), tint = AppColors.textSecondary)
                    }
                }
            } else {
                Spacer(Modifier.statusBarsPadding())
            }

            HorizontalPager(
                state = pagerState,
                modifier = (if (scrollWholePaywall) Modifier.height(pageHeight) else Modifier.weight(1f)).fillMaxWidth(),
            ) { page ->
                Column(Modifier.fillMaxSize().verticalScroll(rememberScrollState())) {
                    when (slides[page]) {
                        SignalSlide.ARCHIVE -> ArchiveSlide()
                        SignalSlide.TRIAL -> TrialSlide(trialOffer)
                        SignalSlide.PLANS -> PlansSlide(
                            offers = orderedOffers,
                            selected = selected,
                            onSelect = { selectedPlan = it },
                            enabled = !isBusy,
                        )
                    }
                }
            }

            HorizontalDivider(color = AppColors.borderSubtle)
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(AppColors.bgSecondary)
                    .navigationBarsPadding()
                    .padding(horizontal = Spacing.lg, vertical = Spacing.xs),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(Spacing.xs),
            ) {
                Row(horizontalArrangement = Arrangement.spacedBy(Spacing.xs), modifier = Modifier.fillMaxWidth()) {
                    slides.forEachIndexed { index, slide ->
                        SignalStep(
                            number = index + 1,
                            title = stringResource(slide.titleRes),
                            isReached = index <= pagerState.currentPage,
                            isCurrent = index == pagerState.currentPage,
                            onClick = { goTo(index) },
                            modifier = Modifier.weight(1f),
                        )
                    }
                }

                if (errorMessage != null) {
                    Text(errorMessage, style = GeistType.copy13, color = AppColors.error, textAlign = TextAlign.Center)
                }
                Text(
                    text = selected?.let { footerLine(it) } ?: stringResource(R.string.billing_error_product_unavailable),
                    style = GeistType.copy13,
                    color = AppColors.textSecondary,
                    textAlign = TextAlign.Center,
                )
                // Without offers the primary action retries the catalog instead of sitting disabled.
                Button(
                    onClick = { if (selected != null) onPlanPurchase(selected.plan) else onRetry() },
                    enabled = !isBusy,
                    modifier = Modifier.fillMaxWidth().heightIn(min = GeistSizes.controlLarge + Spacing.xs),
                    shape = CircleShape,
                    colors = ButtonDefaults.buttonColors(
                        containerColor = AppColors.accent,
                        contentColor = AppColors.onAccent,
                        disabledContainerColor = AppColors.borderSubtle,
                        disabledContentColor = AppColors.textSecondary,
                    ),
                ) {
                    if (isPurchasing) {
                        CircularProgressIndicator(Modifier.size(20.dp), color = AppColors.onAccent, strokeWidth = 2.dp)
                    } else {
                        Text(ctaText(selected), style = GeistType.button16, textAlign = TextAlign.Center)
                    }
                }
                val uriHandler = LocalUriHandler.current
                // The same links on every slide keep the footer from shifting between pages.
                FlowRow(horizontalArrangement = Arrangement.Center, modifier = Modifier.fillMaxWidth()) {
                    if (isRestoring) {
                        Row(Modifier.heightIn(min = GeistSizes.minimumTouchTarget), verticalAlignment = Alignment.CenterVertically) {
                            CircularProgressIndicator(Modifier.size(16.dp), color = AppColors.accent, strokeWidth = 2.dp)
                            Spacer(Modifier.size(Spacing.xs))
                            Text(stringResource(R.string.paywall_restoring), style = GeistType.button14, color = AppColors.accent)
                        }
                    } else {
                        SignalLink(stringResource(R.string.paywall_restore), enabled = !isBusy, onClick = onRestore)
                    }
                    SignalLink(stringResource(R.string.paywall_terms)) { uriHandler.openUri("https://healthmd.app/terms-of-service.html") }
                    SignalLink(stringResource(R.string.paywall_privacy)) { uriHandler.openUri("https://healthmd.app/privacy-policy.html") }
                }
            }
        }

    }

    LaunchedEffect(slides.size) {
        if (pagerState.currentPage >= slides.size) pagerState.scrollToPage(slides.lastIndex)
    }
}

private val SignalSlide.titleRes: Int
    get() = when (this) {
        SignalSlide.ARCHIVE -> R.string.paywall_signal_step_archive
        SignalSlide.TRIAL -> R.string.paywall_signal_step_trial
        SignalSlide.PLANS -> R.string.paywall_signal_step_plans
    }

@Composable
private fun priceLabel(offer: PurchaseOffer): String = when (offer.plan) {
    PurchasePlan.WEEKLY -> stringResource(R.string.paywall_weekly_price, offer.localizedPriceText)
    PurchasePlan.YEARLY -> stringResource(R.string.paywall_yearly_price, offer.localizedPriceText)
    PurchasePlan.LIFETIME -> stringResource(R.string.paywall_lifetime_price, offer.localizedPriceText)
}

@Composable
private fun footerLine(offer: PurchaseOffer): String {
    val price = priceLabel(offer)
    return if (offer.hasSevenDayTrial) stringResource(R.string.paywall_trial_then, price) else price
}

@Composable
private fun ctaText(offer: PurchaseOffer?): String = when {
    offer == null -> stringResource(R.string.paywall_retry)
    offer.plan == PurchasePlan.LIFETIME -> stringResource(R.string.paywall_signal_cta_lifetime)
    offer.hasSevenDayTrial -> stringResource(R.string.paywall_signal_cta_trial)
    else -> stringResource(R.string.paywall_signal_cta_subscribe)
}

// region Slides

@Composable
private fun SlideBody(content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier.fillMaxWidth().padding(horizontal = Spacing.lg).padding(bottom = Spacing.lg),
        verticalArrangement = Arrangement.spacedBy(Spacing.md),
        content = content,
    )
}

/** Headline area above the band; its minimum height keeps the line at one height on every page. */
@Composable
private fun SlideHeader(minHeight: Dp = signalHeaderHeight, content: @Composable ColumnScope.() -> Unit) {
    Column(
        modifier = Modifier
            .fillMaxWidth()
            .padding(horizontal = Spacing.lg)
            .padding(bottom = Spacing.md)
            .heightIn(min = minHeight),
        verticalArrangement = Arrangement.spacedBy(Spacing.sm),
        content = content,
    )
}

@Composable
private fun SlideTitle(text: String) {
    Text(
        text = text,
        style = GeistType.heading32,
        color = AppColors.textPrimary,
        modifier = Modifier.semantics { heading() },
    )
}

@Composable
private fun ArchiveSlide() {
    SlideHeader {
        SlideTitle(stringResource(R.string.paywall_signal_title))
        Text(stringResource(R.string.paywall_signal_lede), style = GeistType.copy16, color = AppColors.textSecondary)
    }
    SignalBand(SignalBandKind.Archive)
    SlideBody {
        SignalExampleNote()
    }
}

@Composable
private fun TrialSlide(trialOffer: PurchaseOffer?) {
    SlideHeader {
        SlideTitle(stringResource(R.string.paywall_signal_trial_title))
    }
    SignalBand(SignalBandKind.Trial)
    SlideBody {
        SignalDayRow(1, stringResource(R.string.paywall_signal_day_today), stringResource(R.string.paywall_signal_day_today_body))
        SignalDayRow(5, stringResource(R.string.paywall_signal_day_cancel), stringResource(R.string.paywall_signal_day_cancel_body))
        SignalDayRow(
            7,
            stringResource(R.string.paywall_signal_day_end),
            trialOffer?.let { stringResource(R.string.paywall_signal_day_end_body, priceLabel(it)) }
                ?: stringResource(R.string.paywall_signal_subscription_detail),
        )
    }
}

@Composable
private fun PlansSlide(
    offers: List<PurchaseOffer>,
    selected: PurchaseOffer?,
    onSelect: (PurchasePlan) -> Unit,
    enabled: Boolean,
) {
    val colors = signalBandColors()
    val time = rememberSignalTime()
    // Without Play offers the three plans still hold their places, so the fork and layout stay intact.
    val displayedPlans = if (offers.isEmpty()) signalPlanOrder else offers.map { it.plan }
    val selectedIndex = selected?.let { displayedPlans.indexOf(it.plan) } ?: -1
    // Root positions, read only while drawing, so paging redraws without recomposing.
    var origin by remember { mutableStateOf(Offset.Zero) }
    val cards = remember { mutableStateMapOf<Int, Rect>() }
    LaunchedEffect(displayedPlans.size) { cards.keys.filter { it >= displayedPlans.size }.forEach(cards::remove) }

    Column(
        Modifier
            .fillMaxWidth()
            .onGloballyPositioned { origin = it.positionInRoot() }
            .drawBehind {
                drawPlanBranches(
                    lineY = signalLineY.toPx(),
                    cards = cards.entries.sortedBy { it.key }.map { it.value.translate(-origin) },
                    selected = selectedIndex,
                    colors = colors,
                    time = time,
                )
            },
    ) {
        SlideHeader(minHeight = signalPlansHeaderHeight) {
            SlideTitle(stringResource(R.string.paywall_signal_plans_title))
        }
        SlideBody {
            Column(
                Modifier.selectableGroup().padding(start = signalCardInset),
                verticalArrangement = Arrangement.spacedBy(Spacing.sm),
            ) {
                displayedPlans.forEachIndexed { index, plan ->
                    val offer = offers.firstOrNull { it.plan == plan }
                    SignalPlanCard(
                        plan = plan,
                        offer = offer,
                        isSelected = offer != null && offer == selected,
                        enabled = enabled,
                        onClick = { onSelect(plan) },
                        modifier = Modifier.onGloballyPositioned { cards[index] = it.rootRect() },
                    )
                }
            }
            Text(stringResource(R.string.paywall_subscription_disclosure), style = GeistType.copy13, color = AppColors.textSecondary)
            val uriHandler = LocalUriHandler.current
            SignalLink(stringResource(R.string.paywall_manage_subscriptions)) {
                uriHandler.openUri("https://play.google.com/store/account/subscriptions")
            }
        }
    }
}

/** Unclipped bounds in root coordinates; pager pages off screen still report true positions. */
private fun LayoutCoordinates.rootRect(): Rect = Rect(positionInRoot(), size.toSize())

// endregion

// region Components

@Composable
private fun SignalExampleNote() {
    val accent = AppColors.accent
    val secondary = AppColors.textSecondary
    val fields = listOf("resting_heart_rate" to "58", "hrv_ms" to "46.2", "steps" to "9412", "sleep_total_hours" to "7.3")
    val shape = RoundedCornerShape(GeistRadii.medium)
    Column(
        Modifier
            .fillMaxWidth()
            .background(AppColors.bgPrimary, shape)
            .border(1.dp, AppColors.borderDefault, shape),
    ) {
        Row(Modifier.fillMaxWidth().padding(Spacing.sm), verticalAlignment = Alignment.CenterVertically) {
            Text(
                "Obsidian › Health › 2026-11-01.md",
                style = GeistType.label12Mono,
                color = AppColors.textSecondary,
                modifier = Modifier.weight(1f),
            )
            Text(stringResource(R.string.paywall_signal_example), style = GeistType.label12, color = AppColors.textSecondary)
        }
        HorizontalDivider(color = AppColors.borderSubtle)
        Text(
            text = buildAnnotatedString {
                withStyle(SpanStyle(color = secondary)) { append("---\n") }
                fields.forEach { (key, value) ->
                    withStyle(SpanStyle(color = accent)) { append("$key:") }
                    append(" $value\n")
                }
                withStyle(SpanStyle(color = secondary)) { append("---") }
            },
            style = GeistType.copy14Mono,
            color = AppColors.textPrimary,
            modifier = Modifier.padding(Spacing.sm),
        )
    }
}

@Composable
private fun SignalDayRow(day: Int, title: String, detail: String) {
    Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm), modifier = Modifier.semantics(mergeDescendants = true) {}) {
        Text(
            "D$day",
            style = GeistType.label13Mono,
            color = AppColors.accent,
            modifier = Modifier.widthIn(min = 28.dp).clearAndSetSemantics {},
        )
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.xxs)) {
            Text(title, style = GeistType.heading16, color = AppColors.textPrimary)
            Text(detail, style = GeistType.copy14, color = AppColors.textSecondary)
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SignalPlanCard(
    plan: PurchasePlan,
    /** Null until Play returns this plan; the card then holds its place, disabled. */
    offer: PurchaseOffer?,
    isSelected: Boolean,
    enabled: Boolean,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val shape = RoundedCornerShape(GeistRadii.medium)
    val name = when (plan) {
        PurchasePlan.WEEKLY -> stringResource(R.string.paywall_signal_plan_weekly)
        PurchasePlan.YEARLY -> stringResource(R.string.paywall_signal_plan_yearly)
        PurchasePlan.LIFETIME -> stringResource(R.string.paywall_signal_plan_lifetime)
    }
    // Placeholders carry only the plan name; terms appear once Play returns the offer.
    val detail = when {
        offer == null -> null
        plan == PurchasePlan.LIFETIME -> stringResource(R.string.paywall_signal_lifetime_detail)
        offer?.hasSevenDayTrial == true -> stringResource(R.string.paywall_signal_free_week)
        else -> stringResource(R.string.paywall_signal_subscription_detail)
    }
    Row(
        modifier = modifier
            .fillMaxWidth()
            .heightIn(min = 72.dp)
            .background(if (isSelected) AppColors.accentSubtle else AppColors.bgPrimary, shape)
            .border(if (isSelected) 2.dp else 1.dp, if (isSelected) AppColors.accent else AppColors.borderDefault, shape)
            .selectable(selected = isSelected, enabled = enabled && offer != null, role = Role.RadioButton, onClick = onClick)
            .padding(Spacing.md),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Spacing.sm),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Spacing.xxs)) {
            FlowRow(horizontalArrangement = Arrangement.spacedBy(Spacing.xs), verticalArrangement = Arrangement.Center) {
                Text(name, style = GeistType.heading16, color = AppColors.textPrimary)
                if (plan == PurchasePlan.YEARLY) {
                    Text(
                        stringResource(R.string.paywall_signal_best_value),
                        style = GeistType.label12,
                        color = AppColors.onAccent,
                        modifier = Modifier
                            .background(AppColors.accent, CircleShape)
                            .padding(horizontal = Spacing.xs, vertical = Spacing.xxs),
                    )
                }
            }
            if (detail != null) Text(detail, style = GeistType.copy13, color = AppColors.textSecondary)
        }
        Text(
            // The card already names the plan and says it is paid once.
            text = when {
                offer == null -> "—"
                plan == PurchasePlan.LIFETIME -> offer.localizedPriceText
                else -> priceLabel(offer)
            },
            style = GeistType.label14Mono,
            color = if (offer != null) AppColors.textPrimary else AppColors.textSecondary,
            textAlign = TextAlign.End,
        )
    }
}

@Composable
private fun SignalStep(number: Int, title: String, isReached: Boolean, isCurrent: Boolean, onClick: () -> Unit, modifier: Modifier = Modifier) {
    Column(
        modifier = modifier
            .heightIn(min = GeistSizes.minimumTouchTarget)
            .selectable(selected = isCurrent, role = Role.Tab, onClick = onClick)
            .padding(vertical = Spacing.xs),
        verticalArrangement = Arrangement.spacedBy(Spacing.xs, Alignment.CenterVertically),
    ) {
        Box(
            Modifier
                .fillMaxWidth()
                .height(3.dp)
                .background(if (isReached) AppColors.accent else AppColors.borderDefault, CircleShape),
        )
        Text(
            text = "%02d %s".format(number, title.uppercase()),
            style = GeistType.label12Mono,
            color = if (isCurrent) AppColors.textPrimary else AppColors.textSecondary,
        )
    }
}

@Composable
private fun SignalLink(text: String, enabled: Boolean = true, onClick: () -> Unit) {
    TextButton(onClick = onClick, enabled = enabled, modifier = Modifier.heightIn(min = GeistSizes.minimumTouchTarget)) {
        Text(text, style = GeistType.button14, color = if (enabled) AppColors.accent else AppColors.textSecondary)
    }
}

// endregion

// region Signal band

private sealed interface SignalBandKind {
    data object Archive : SignalBandKind
    data object Trial : SignalBandKind
}

/**
 * Decorative trace. Every kind meets both edges at mid-height so adjacent
 * pages join into one line while swiping. Static when animations are off.
 */
@Composable
private fun SignalBand(kind: SignalBandKind, modifier: Modifier = Modifier) {
    val time = rememberSignalTime()
    val measurer = rememberTextMeasurer()
    val density = LocalDensity.current
    val colors = signalBandColors()
    val labelStyle = GeistType.label12Mono
    val fontScale = density.fontScale

    Canvas(
        modifier
            .fillMaxWidth()
            .height(signalBandHeight)
            .clearAndSetSemantics {},
    ) {
        drawGrid(colors)
        val mid = size.height / 2
        when (kind) {
            SignalBandKind.Archive -> {
                val peaks = drawArchiveTrace(mid, colors, time)
                // Decorative readouts; omitted at large text scales to avoid overlap.
                if (fontScale < 1.3f) {
                    listOf("06:12 · 58 bpm" to peaks[0], "hrv · 46 ms" to peaks[2]).forEach { (text, peak) ->
                        val layout = measurer.measure(text, labelStyle.copy(color = colors.ink))
                        val pad = 6.dp.toPx()
                        val topLeft = Offset(peak.x - 12.dp.toPx(), peak.y - 14.dp.toPx() - layout.size.height - pad * 2)
                        val chip = Size(layout.size.width + pad * 2, layout.size.height + pad)
                        drawLine(colors.muted, Offset(peak.x, peak.y - 14.dp.toPx()), peak, 1.dp.toPx())
                        drawRoundRect(colors.surface, topLeft, chip, CornerRadius(6.dp.toPx()))
                        drawRoundRect(colors.grid, topLeft, chip, CornerRadius(6.dp.toPx()), style = Stroke(1.dp.toPx()))
                        drawText(layout, topLeft = topLeft + Offset(pad, pad / 2))
                        drawCircle(colors.ink, 3.dp.toPx(), peak)
                    }
                }
            }
            SignalBandKind.Trial -> {
                drawTrace(Path().apply { moveTo(0f, mid); lineTo(size.width, mid) }, colors, time)
                val inset = 32.dp.toPx()
                val step = (size.width - inset * 2) / 6
                for (day in 0 until 7) {
                    val point = Offset(inset + step * day, mid)
                    when (day) {
                        0 -> drawPulse(point, 7.dp.toPx(), colors, time)
                        4, 6 -> {
                            drawCircle(colors.surface, 6.dp.toPx(), point)
                            drawCircle(if (day == 6) colors.ink else colors.accent, 6.dp.toPx(), point, style = Stroke(2.dp.toPx()))
                        }
                        else -> drawCircle(colors.node, 3.dp.toPx(), point)
                    }
                    val strong = day == 0 || day == 4 || day == 6
                    val layout = measurer.measure("D${day + 1}", labelStyle.copy(color = if (strong) colors.ink else colors.secondary))
                    drawText(layout, topLeft = Offset(point.x - layout.size.width / 2f, mid - 18.dp.toPx() - layout.size.height))
                }
            }
        }
    }
}

@Composable
private fun signalBandColors() = SignalBandColors(
    glint = if (LocalGeistColors.current.isDark) AppColors.textPrimary else AppColors.bgPrimary,
    accent = AppColors.accent,
    ink = AppColors.textPrimary,
    secondary = AppColors.textSecondary,
    grid = AppColors.borderSubtle,
    muted = AppColors.borderDefault,
    node = AppColors.borderStrong,
    surface = AppColors.bgPrimary,
)

/** Shared comet and pulse phases; negative (static) when animations are off. */
@Composable
private fun rememberSignalTime(): SignalTime {
    val context = LocalContext.current
    val reduceMotion = remember {
        Settings.Global.getFloat(context.contentResolver, Settings.Global.ANIMATOR_DURATION_SCALE, 1f) == 0f
    }
    val transition = rememberInfiniteTransition(label = "signal")
    val comet by transition.animateFloat(0f, 1f, infiniteRepeatable(tween(4800, easing = LinearEasing), RepeatMode.Restart), label = "comet")
    val pulse by transition.animateFloat(0f, 1f, infiniteRepeatable(tween(2000, easing = LinearEasing), RepeatMode.Restart), label = "pulse")
    return SignalTime(comet = if (reduceMotion) -1f else comet, pulse = if (reduceMotion) -1f else pulse)
}

/** Leading room the plan cards leave for the fork. */
private val signalCardInset = 20.dp

/** Headline area above the band on the archive and trial pages. */
private val signalHeaderHeight = 176.dp

/** Line height from the top of a page: header, its bottom gap, then half the band. */
private val signalLineY = signalHeaderHeight + Spacing.md + signalBandHeight / 2

private val signalCardHeight = 72.dp

/** Plans header height that centers the middle of three cards on the line. */
private val signalPlansHeaderHeight = signalLineY - Spacing.md - (signalCardHeight * 1.5f + Spacing.sm)

/**
 * Picks up the trace where the previous page leaves it and forks it into
 * every plan card: the selected plan's branch is lit, the rest are dashed.
 */
private fun DrawScope.drawPlanBranches(lineY: Float, cards: List<Rect>, selected: Int, colors: SignalBandColors, time: SignalTime) {
    // Dotted grid strip, matching the band on the other pages.
    val step = 16.dp.toPx()
    val half = signalBandHeight.toPx() / 2
    var x = step / 2
    while (x < size.width) {
        var y = lineY - half + step / 2
        while (y < lineY + half) {
            drawCircle(colors.grid, 0.75.dp.toPx(), Offset(x, y))
            y += step
        }
        x += step
    }
    if (cards.isEmpty()) return

    val fork = Offset(8.dp.toPx(), lineY)
    fun branch(card: Rect) = Path().apply {
        moveTo(fork.x, fork.y)
        cubicTo(fork.x + 20.dp.toPx(), fork.y, card.left - 22.dp.toPx(), card.center.y, card.left, card.center.y)
    }
    cards.forEachIndexed { index, card ->
        if (index == selected) return@forEachIndexed
        drawPath(
            branch(card),
            colors.muted,
            style = Stroke(1.25.dp.toPx(), cap = StrokeCap.Round, pathEffect = PathEffect.dashPathEffect(floatArrayOf(3.dp.toPx(), 4.dp.toPx()))),
        )
        drawCircle(colors.node, 3.dp.toPx(), Offset(card.left, card.center.y))
    }

    val target = cards.getOrNull(selected)
    val lit = Path().apply {
        moveTo(0f, lineY)
        lineTo(fork.x, fork.y)
        if (target != null) addPath(branch(target))
    }
    drawTrace(lit, colors, time)
    drawPulse(target?.let { Offset(it.left, it.center.y) } ?: fork, 5.dp.toPx(), colors, time)
}

private data class SignalBandColors(
    /** Bright core of the travelling comet. */
    val glint: Color,
    val accent: Color,
    val ink: Color,
    val secondary: Color,
    val grid: Color,
    val muted: Color,
    val node: Color,
    val surface: Color,
)

/** Animation phases in 0..1; negative when motion is reduced. */
private data class SignalTime(val comet: Float, val pulse: Float)

private fun DrawScope.drawGrid(colors: SignalBandColors) {
    val step = 16.dp.toPx()
    var x = step / 2
    while (x < size.width) {
        var y = step / 2
        while (y < size.height) {
            drawCircle(colors.grid, 0.75.dp.toPx(), Offset(x, y))
            y += step
        }
        x += step
    }
}

private fun DrawScope.drawTrace(path: Path, colors: SignalBandColors, time: SignalTime) {
    drawPath(path, colors.accent.copy(alpha = 0.25f), style = Stroke(6.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    drawPath(path, colors.accent, style = Stroke(2.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
    if (time.comet < 0f) return
    // A short bright comet travels the trace every few seconds.
    val measure = PathMeasure().apply { setPath(path, false) }
    val head = measure.length * time.comet
    val segment = Path()
    measure.getSegment((head - measure.length * 0.05f).coerceAtLeast(0f), head, segment, true)
    drawPath(segment, colors.glint, style = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round))
}

private fun DrawScope.drawPulse(point: Offset, radius: Float, colors: SignalBandColors, time: SignalTime) {
    if (time.pulse >= 0f) {
        drawCircle(colors.accent.copy(alpha = 0.5f * (1 - time.pulse)), radius + time.pulse * radius * 2.2f, point)
    }
    drawCircle(colors.accent, radius, point)
}

private fun DrawScope.drawArchiveTrace(mid: Float, colors: SignalBandColors, time: SignalTime): List<Offset> {
    val baseline = mid + 14.dp.toPx()
    val u = 1.dp.toPx()
    val peaks = mutableListOf<Offset>()
    val path = Path().apply {
        moveTo(0f, mid)
        lineTo(size.width * 0.03f, baseline)
        listOf(0.06f, 0.31f, 0.56f, 0.80f).forEach { fraction ->
            val x = size.width * fraction
            lineTo(x, baseline)
            quadraticTo(x + 6 * u, baseline - 8 * u, x + 12 * u, baseline)
            lineTo(x + 18 * u, baseline)
            lineTo(x + 21 * u, baseline + 6 * u)
            lineTo(x + 26 * u, baseline - 48 * u)
            peaks += Offset(x + 26 * u, baseline - 48 * u)
            lineTo(x + 31 * u, baseline + 22 * u)
            lineTo(x + 35 * u, baseline)
            lineTo(x + 45 * u, baseline)
            quadraticTo(x + 54 * u, baseline - 16 * u, x + 63 * u, baseline)
        }
        lineTo(size.width * 0.97f, baseline)
        lineTo(size.width, mid)
    }
    drawTrace(path, colors, time)
    return peaks
}

// endregion
