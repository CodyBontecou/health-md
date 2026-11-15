package com.healthmd.presentation.paywall

import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
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
import androidx.compose.foundation.layout.width
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
import androidx.compose.material.icons.outlined.Description
import androidx.compose.material.icons.outlined.Event
import androidx.compose.material.icons.outlined.LockOpen
import androidx.compose.material.icons.outlined.Shield
import androidx.compose.material.icons.outlined.Warning
import androidx.compose.material3.Button
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.RadioButton
import androidx.compose.material3.RadioButtonDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalUriHandler
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import com.healthmd.R
import com.healthmd.domain.repository.PurchaseOffer
import com.healthmd.domain.repository.PurchasePlan
import com.healthmd.presentation.theme.GeistAdaptiveLayout
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import kotlinx.coroutines.launch

/** Plans in display order: Yearly (best value) first, then Weekly, then Lifetime. */
internal fun paywallPlanOrder(offers: List<PurchaseOffer>): List<PurchaseOffer> =
    offers.sortedBy {
        when (it.plan) {
            PurchasePlan.YEARLY -> 0
            PurchasePlan.WEEKLY -> 1
            PurchasePlan.LIFETIME -> 2
        }
    }

/** The trial slide appears only when Google Play actually offers a trial on some plan. */
internal fun paywallShowsTrialSlide(offers: List<PurchaseOffer>): Boolean = offers.any { it.hasSevenDayTrial }

private enum class PaywallSlide { BENEFIT, TRIAL, PLANS }

/**
 * The Material 3 carousel paywall: what Health.md writes, how the trial works, then the plans.
 * Only offers and trial eligibility supplied by Google Play are shown; the bottom bar keeps the
 * selected plan's terms, the purchase action, Restore, Terms and Privacy on every slide.
 * Reading layouts scroll the complete page so an expanded footer cannot crowd out the slides.
 */
@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun PaywallCarousel(
    offers: List<PurchaseOffer>,
    onPlanPurchase: (PurchasePlan) -> Unit,
    onRestore: () -> Unit,
    onRetry: () -> Unit,
    onDismiss: (() -> Unit)?,
    isPurchasing: Boolean,
    isRestoring: Boolean,
    errorMessage: String?,
    debugControls: (@Composable () -> Unit)?,
    manageSubscriptionsUrl: String = com.healthmd.domain.billing.PlaySubscriptionLinks.SUBSCRIPTION_CENTER,
) {
    val colors = LocalGeistColors.current
    val uriHandler = LocalUriHandler.current
    val scope = rememberCoroutineScope()
    val isLoading = isPurchasing || isRestoring
    val plans = paywallPlanOrder(offers)
    val slides = buildList {
        add(PaywallSlide.BENEFIT)
        if (paywallShowsTrialSlide(offers)) add(PaywallSlide.TRIAL)
        add(PaywallSlide.PLANS)
    }
    var selectedPlan by rememberSaveable { mutableStateOf<PurchasePlan?>(null) }
    val selected = plans.firstOrNull { it.plan == selectedPlan } ?: plans.firstOrNull()
    val pager = rememberPagerState(pageCount = { slides.size })
    val plansPage = slides.indexOf(PaywallSlide.PLANS)

    BoxWithConstraints(Modifier.fillMaxSize().background(colors.background100)) {
        val readingLayout = GeistAdaptiveLayout.readingFirst(
            maxWidth.value, maxHeight.value, LocalDensity.current.fontScale,
        )
        val pageScroll = rememberScrollState()
        LaunchedEffect(pager.settledPage, slides.getOrNull(pager.settledPage), readingLayout) {
            // Footer navigation should reveal the new slide rather than leave it above the viewport.
            if (readingLayout) pageScroll.scrollTo(0)
        }
        Column(
            Modifier.fillMaxSize().then(
                if (readingLayout) Modifier.verticalScroll(pageScroll) else Modifier,
            ),
        ) {
            Row(Modifier.fillMaxWidth().statusBarsPadding().heightIn(min = GeistSpacing.space16).padding(horizontal = GeistSpacing.space1)) {
                if (onDismiss != null) {
                    IconButton(onClick = onDismiss, enabled = !isLoading, modifier = Modifier.align(Alignment.CenterVertically)) {
                        Icon(Icons.Filled.Close, contentDescription = stringResource(R.string.close), tint = colors.primary)
                    }
                }
            }
            HorizontalPager(
                state = pager,
                // During a catalog refresh the pager can query an obsolete item provider
                // with the new count. Retain real slide identities without indexing past it.
                key = { index -> slides.getOrNull(index) ?: "paywall-pending-$index" },
                modifier = Modifier.fillMaxWidth().then(if (readingLayout) Modifier else Modifier.weight(1f)),
            ) { page ->
                Box(
                    if (readingLayout) Modifier.fillMaxWidth() else Modifier.fillMaxSize(),
                    contentAlignment = Alignment.TopCenter,
                ) {
                    Column(
                        modifier = Modifier
                            .widthIn(max = GeistSizes.readableContentMaxWidth)
                            .then(
                                if (readingLayout) Modifier.fillMaxWidth()
                                else Modifier.fillMaxSize().verticalScroll(rememberScrollState()),
                            )
                            .padding(horizontal = GeistSpacing.space6 - GeistSpacing.space1, vertical = GeistSpacing.space2),
                        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
                    ) {
                        when (slides.getOrNull(page)) {
                            null -> Unit // A retired page can remain in a pending layout pass.
                            PaywallSlide.BENEFIT -> BenefitSlide()
                            PaywallSlide.TRIAL -> TrialSlide(selected)
                            PaywallSlide.PLANS -> PlansSlide(
                                plans = plans,
                                selected = selected,
                                enabled = !isLoading,
                                onSelect = { selectedPlan = it },
                                onRetry = onRetry,
                                onManageSubscriptions = { uriHandler.openUri(manageSubscriptionsUrl) },
                                debugControls = debugControls,
                            )
                        }
                    }
                }
            }
            Column(
                modifier = Modifier
                    .fillMaxWidth()
                    .background(colors.gray.c100)
                    .navigationBarsPadding()
                    .padding(start = GeistSpacing.space6 - GeistSpacing.space1, end = GeistSpacing.space6 - GeistSpacing.space1, top = GeistSpacing.space2, bottom = GeistSpacing.space4),
                horizontalAlignment = Alignment.CenterHorizontally,
                verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
            ) {
                Row(Modifier.selectableGroup(), verticalAlignment = Alignment.CenterVertically) {
                    slides.indices.forEach { index ->
                        val current = pager.currentPage == index
                        val label = stringResource(R.string.paywall_slide, index + 1, slides.size)
                        Box(
                            modifier = Modifier
                                .size(GeistSizes.minimumTouchTarget)
                                .selectable(selected = current, role = Role.Tab) { scope.launch { pager.animateScrollToPage(index) } }
                                .semantics { contentDescription = label },
                            contentAlignment = Alignment.Center,
                        ) {
                            Box(
                                Modifier
                                    .height(GeistSpacing.space2)
                                    .width(if (current) GeistSpacing.space6 else GeistSpacing.space2)
                                    .background(if (current) colors.brandPrimary else colors.gray.c500, CircleShape),
                            )
                        }
                    }
                }
                if (errorMessage != null) {
                    Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2), verticalAlignment = Alignment.CenterVertically) {
                        Icon(Icons.Outlined.Warning, contentDescription = null, tint = colors.error, modifier = Modifier.size(20.dp))
                        Text(errorMessage, style = MaterialTheme.typography.bodySmall, color = colors.error)
                    }
                }
                if (selected != null) {
                    Text(planTerms(selected), style = GeistType.label14, color = colors.secondary, textAlign = TextAlign.Center)
                }
                Button(
                    onClick = { selected?.let { onPlanPurchase(it.plan) } },
                    enabled = selected != null && !isLoading,
                    modifier = Modifier.fillMaxWidth().heightIn(min = 56.dp),
                    shape = RoundedCornerShape(GeistRadii.full),
                    colors = ButtonDefaults.buttonColors(containerColor = colors.brandPrimary, contentColor = colors.brandOnPrimary),
                ) {
                    if (isPurchasing) {
                        CircularProgressIndicator(Modifier.size(20.dp), color = colors.brandOnPrimary, strokeWidth = 2.dp)
                        Spacer(Modifier.width(GeistSpacing.space2))
                    }
                    // Keep the action named while busy for accessibility and state continuity.
                    Text(selected?.let { ctaLabel(it) } ?: stringResource(R.string.paywall_cta_subscribe), style = GeistType.button16)
                }
                FlowRow(horizontalArrangement = Arrangement.Center) {
                    if (pager.currentPage != plansPage) {
                        TextButton(onClick = { scope.launch { pager.animateScrollToPage(plansPage) } }) {
                            Text(stringResource(R.string.paywall_see_all_plans), style = GeistType.button14, color = colors.brandPrimary)
                        }
                    }
                    TextButton(onClick = onRestore, enabled = !isLoading) {
                        Text(
                            stringResource(if (isRestoring) R.string.paywall_restoring else R.string.paywall_restore),
                            style = GeistType.button14,
                            color = colors.brandPrimary,
                        )
                    }
                    TextButton(onClick = { uriHandler.openUri("https://healthmd.app/terms-of-service.html") }) {
                        Text(stringResource(R.string.paywall_terms), style = GeistType.button14, color = colors.brandPrimary)
                    }
                    TextButton(onClick = { uriHandler.openUri("https://healthmd.app/privacy-policy.html") }) {
                        Text(stringResource(R.string.paywall_privacy), style = GeistType.button14, color = colors.brandPrimary)
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun BenefitSlide() {
    val colors = LocalGeistColors.current
    Column(
        modifier = Modifier.fillMaxWidth(),
        horizontalAlignment = Alignment.CenterHorizontally,
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
    ) {
        Image(
            painter = painterResource(id = R.drawable.app_icon),
            contentDescription = null,
            modifier = Modifier.size(72.dp).clip(RoundedCornerShape(GeistRadii.listGroup)),
            contentScale = ContentScale.Crop,
        )
        Text(
            stringResource(R.string.paywall_benefit_title),
            style = MaterialTheme.typography.headlineLarge,
            color = colors.primary,
            textAlign = TextAlign.Center,
            modifier = Modifier.semantics { heading() },
        )
        Text(
            stringResource(R.string.paywall_benefit_body),
            style = MaterialTheme.typography.bodyLarge,
            color = colors.secondary,
            textAlign = TextAlign.Center,
        )
        // An illustration of the file format, labeled as an example rather than the user's data.
        Column(
            Modifier
                .fillMaxWidth()
                .clip(RoundedCornerShape(GeistRadii.medium))
                .background(colors.gray.c200),
        ) {
            Row(
                Modifier.fillMaxWidth().padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
            ) {
                Icon(Icons.Outlined.Description, contentDescription = null, tint = colors.brandPrimary, modifier = Modifier.size(18.dp))
                Text("2026-11-01.md", style = GeistType.label14Mono, color = colors.primary, modifier = Modifier.weight(1f))
                Text(stringResource(R.string.paywall_example_label), style = GeistType.label12, color = colors.secondary)
            }
            Box(Modifier.fillMaxWidth().height(1.dp).background(colors.gray.c500))
            Column(Modifier.padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space3)) {
                EXAMPLE_NOTE.forEach { line ->
                    Text(line, style = GeistType.label13Mono, color = colors.secondary)
                }
            }
        }
        FlowRow(
            horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2, Alignment.CenterHorizontally),
            verticalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
        ) {
            listOf(
                stringResource(R.string.paywall_destination_obsidian),
                stringResource(R.string.paywall_destination_folder),
                stringResource(R.string.paywall_destination_cli),
                stringResource(R.string.paywall_destination_api),
            ).forEach { label ->
                Text(
                    label,
                    style = GeistType.button14,
                    color = colors.primary,
                    modifier = Modifier
                        .border(1.dp, colors.gray.c500, RoundedCornerShape(GeistRadii.small))
                        .padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space1 + 2.dp),
                )
            }
        }
    }
}

/** A labeled sample of the Markdown shape; never real or personalized values. */
private val EXAMPLE_NOTE = listOf(
    "---",
    "steps: 9412",
    "sleep: 7h 18m",
    "resting_hr: 58",
    "hrv_ms: 46",
    "---",
    "## Workouts",
    "- Run · 5.2 km · 28 min",
)

@Composable
private fun TrialSlide(selected: PurchaseOffer?) {
    val colors = LocalGeistColors.current
    Text(
        stringResource(R.string.paywall_trial_title),
        style = MaterialTheme.typography.headlineLarge,
        color = colors.primary,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().semantics { heading() },
    )
    Column {
        TrialStep(
            icon = Icons.Outlined.LockOpen,
            title = stringResource(R.string.paywall_trial_today),
            body = stringResource(R.string.paywall_trial_today_body),
            first = true,
            last = false,
        )
        TrialStep(
            icon = Icons.Outlined.Event,
            title = stringResource(R.string.paywall_trial_end_day),
            body = when {
                selected == null -> stringResource(R.string.paywall_trial_end_body_generic)
                !selected.hasSevenDayTrial -> stringResource(R.string.paywall_trial_no_trial_body)
                else -> stringResource(R.string.paywall_trial_end_body, periodPrice(selected))
            },
            first = false,
            last = true,
        )
    }
    Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
        Icon(Icons.Outlined.Shield, contentDescription = null, tint = colors.brandPrimary, modifier = Modifier.size(20.dp))
        Text(stringResource(R.string.paywall_privacy_line), style = MaterialTheme.typography.bodyMedium, color = colors.secondary)
    }
}

@Composable
private fun TrialStep(icon: ImageVector, title: String, body: String, first: Boolean, last: Boolean) {
    val colors = LocalGeistColors.current
    Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4)) {
        Column(horizontalAlignment = Alignment.CenterHorizontally) {
            Box(
                Modifier
                    .size(GeistSizes.control)
                    .background(if (first) colors.brandPrimary else colors.secondaryContainer, CircleShape),
                contentAlignment = Alignment.Center,
            ) {
                Icon(icon, contentDescription = null, tint = if (first) colors.brandOnPrimary else colors.onSecondaryContainer, modifier = Modifier.size(20.dp))
            }
            if (!last) {
                Box(Modifier.width(2.dp).height(GeistSpacing.space10).background(colors.brandPrimary))
            }
        }
        Column(Modifier.padding(top = GeistSpacing.space2, bottom = if (last) 0.dp else GeistSpacing.space4)) {
            Text(title, style = GeistType.heading16, color = colors.primary)
            Text(body, style = MaterialTheme.typography.bodyMedium, color = colors.secondary)
        }
    }
}

@Composable
private fun PlansSlide(
    plans: List<PurchaseOffer>,
    selected: PurchaseOffer?,
    enabled: Boolean,
    onSelect: (PurchasePlan) -> Unit,
    onRetry: () -> Unit,
    onManageSubscriptions: () -> Unit,
    debugControls: (@Composable () -> Unit)?,
) {
    val colors = LocalGeistColors.current
    Text(
        stringResource(R.string.paywall_plans_title),
        style = MaterialTheme.typography.headlineLarge,
        color = colors.primary,
        textAlign = TextAlign.Center,
        modifier = Modifier.fillMaxWidth().semantics { heading() },
    )
    if (plans.isEmpty()) {
        Text(stringResource(R.string.billing_error_product_unavailable), color = colors.secondary)
        TextButton(onClick = onRetry, enabled = enabled) { Text(stringResource(R.string.paywall_retry)) }
    }
    Column(Modifier.selectableGroup(), verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3 - 2.dp)) {
        plans.forEach { offer ->
            val on = offer == selected
            val shape = RoundedCornerShape(GeistRadii.listGroup)
            Row(
                modifier = Modifier
                    .fillMaxWidth()
                    .heightIn(min = 76.dp)
                    .clip(shape)
                    .background(if (on) colors.secondaryContainer else colors.gray.c100)
                    .border(if (on) 2.dp else 1.dp, if (on) colors.brandPrimary else colors.gray.c500, shape)
                    .selectable(selected = on, enabled = enabled, role = Role.RadioButton) { onSelect(offer.plan) }
                    .padding(start = GeistSpacing.space2, end = GeistSpacing.space6 - GeistSpacing.space1, top = GeistSpacing.space3, bottom = GeistSpacing.space3),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2),
            ) {
                RadioButton(
                    selected = on,
                    onClick = null,
                    colors = RadioButtonDefaults.colors(selectedColor = colors.brandPrimary, unselectedColor = colors.gray.c700),
                    modifier = Modifier.padding(horizontal = GeistSpacing.space2),
                )
                Column(Modifier.weight(1f)) {
                    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space2)) {
                        Text(planName(offer.plan), style = GeistType.heading16, color = colors.primary)
                        if (offer.plan == PurchasePlan.YEARLY) {
                            Text(
                                stringResource(R.string.paywall_best_value),
                                style = GeistType.button12,
                                color = colors.onTertiaryContainer,
                                modifier = Modifier
                                    .background(colors.tertiaryContainer, RoundedCornerShape(GeistRadii.small))
                                    .padding(horizontal = GeistSpacing.space2, vertical = 2.dp),
                            )
                        }
                    }
                    Text(planTerms(offer), style = MaterialTheme.typography.bodyMedium, color = colors.secondary)
                }
                Text(offer.localizedPriceText, style = GeistType.heading16, color = colors.primary)
            }
        }
    }
    Text(stringResource(R.string.paywall_subscription_disclosure), style = MaterialTheme.typography.bodySmall, color = colors.secondary)
    Box(Modifier.fillMaxWidth(), contentAlignment = Alignment.Center) {
        TextButton(onClick = onManageSubscriptions) {
            Text(stringResource(R.string.paywall_manage_subscriptions), style = GeistType.button14, color = colors.brandPrimary)
        }
    }
    debugControls?.invoke()
}

@Composable
private fun planName(plan: PurchasePlan): String = stringResource(
    when (plan) {
        PurchasePlan.WEEKLY -> R.string.paywall_plan_weekly
        PurchasePlan.YEARLY -> R.string.paywall_plan_yearly
        PurchasePlan.LIFETIME -> R.string.paywall_plan_lifetime
    },
)

@Composable
private fun periodPrice(offer: PurchaseOffer): String = when (offer.plan) {
    PurchasePlan.WEEKLY -> stringResource(R.string.paywall_weekly_price, offer.localizedPriceText)
    PurchasePlan.YEARLY -> stringResource(R.string.paywall_yearly_price, offer.localizedPriceText)
    PurchasePlan.LIFETIME -> stringResource(R.string.paywall_lifetime_price, offer.localizedPriceText)
}

@Composable
private fun planTerms(offer: PurchaseOffer): String = when {
    offer.plan == PurchasePlan.LIFETIME -> stringResource(R.string.paywall_lifetime_terms)
    offer.hasSevenDayTrial -> stringResource(R.string.paywall_trial_then, periodPrice(offer))
    else -> periodPrice(offer)
}

@Composable
private fun ctaLabel(offer: PurchaseOffer): String = stringResource(
    when {
        offer.plan == PurchasePlan.LIFETIME -> R.string.paywall_cta_lifetime
        offer.hasSevenDayTrial -> R.string.paywall_cta_trial
        else -> R.string.paywall_cta_subscribe
    },
)
