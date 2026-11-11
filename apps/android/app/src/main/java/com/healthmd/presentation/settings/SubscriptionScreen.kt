package com.healthmd.presentation.settings

import android.content.Context
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.defaultMinSize
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.outlined.ArrowOutward
import androidx.compose.material.icons.outlined.CheckCircle
import androidx.compose.material.icons.outlined.FavoriteBorder
import androidx.compose.material.icons.outlined.Folder
import androidx.compose.material.icons.outlined.PauseCircle
import androidx.compose.material.icons.outlined.Tune
import androidx.compose.material3.ButtonDefaults
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.FilledTonalButton
import androidx.compose.material3.Icon
import androidx.compose.material3.ModalBottomSheet
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.material3.rememberModalBottomSheetState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.domain.billing.BillingError
import com.healthmd.domain.billing.SubscriptionStatus
import com.healthmd.domain.billing.YearlySwitchOffer
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.ui.platform.LocalConfiguration
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.theme.GeistRadii
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.GeistSpacing
import com.healthmd.presentation.theme.GeistType
import com.healthmd.presentation.theme.LocalGeistColors
import timber.log.Timber

/**
 * Settings › Subscription (board RF_Subscription / RF_SubEnded): the owned plan, a
 * "Manage or cancel" path through "Before you go" to Google Play, and the lapsed state.
 * Lifetime and grandfathered access show no cancel path. Prices come only from Google Play and
 * dates only from myself.md's server read of Google Play; neither is ever invented.
 */
@Composable
fun SubscriptionScreen(
    onSeePlans: () -> Unit,
    viewModel: SubscriptionViewModel = hiltViewModel(),
) {
    val status by viewModel.status.collectAsStateWithLifecycle()
    val isRestoring by viewModel.isRestoring.collectAsStateWithLifecycle()
    val error by viewModel.purchaseError.collectAsStateWithLifecycle()
    val switchOffer by viewModel.switchOffer.collectAsStateWithLifecycle()
    val isPurchasing by viewModel.isPurchasing.collectAsStateWithLifecycle()
    val context = LocalContext.current
    val locale = LocalConfiguration.current.locales[0]
    var showsBeforeYouGo by rememberSaveable { mutableStateOf(false) }

    // Returning from Google Play re-reads ownership, so a cancel shows on the way back.
    LifecycleResumeEffect(viewModel) {
        viewModel.refresh()
        onPauseOrDispose { }
    }

    val ui = subscriptionUi(status)
    val periodEnd = ui.periodEndMillis?.let { formatPeriodEnd(it, locale) }
    val openPlay = { openPlaySubscriptions(context, subscriptionManageUrl(ui, context.packageName)) }

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(horizontal = GeistSpacing.space4)
            .padding(top = GeistSpacing.space2, bottom = GeistSpacing.space6)
            .testTag("subscription.screen"),
        verticalArrangement = Arrangement.spacedBy(GeistSpacing.space6),
    ) {
        val subtitle = if (status is SubscriptionStatus.Ended) {
            stringResource(ui.status, stringResource(planTitle((status as SubscriptionStatus.Ended).previousPlan)))
        } else {
            stringResource(ui.status)
        }
        SubscriptionHeroCard(title = stringResource(ui.title), subtitle = subtitle, owned = ui.owned)

        if (ui.ended) {
            SubscriptionEndedContent(
                onSeePlans = onSeePlans,
                onPlaySubscriptions = openPlay,
            )
        } else {
            SubscriptionDetails(ui, periodEnd)
            when (ui.action) {
                SubscriptionAction.MANAGE_OR_CANCEL -> SubscriptionPrimary(
                    label = stringResource(R.string.m3_subscription_manage_or_cancel),
                    note = ui.actionNote,
                    onClick = { showsBeforeYouGo = true },
                    tag = "subscription.manage",
                )
                SubscriptionAction.MANAGE_IN_PLAY -> SubscriptionPrimary(
                    label = stringResource(R.string.m3_subscription_manage_in_play),
                    note = ui.actionNote,
                    onClick = openPlay,
                    icon = Icons.Outlined.ArrowOutward,
                    tag = "subscription.manageInPlay",
                )
                SubscriptionAction.SEE_PLANS -> SubscriptionPrimary(
                    label = stringResource(R.string.m3_subscription_see_plans),
                    note = null,
                    onClick = onSeePlans,
                    tag = "subscription.seePlans",
                )
                null -> Unit
            }
        }

        billingErrorText(error)?.let {
            Text(it, style = GeistType.copy14, color = LocalGeistColors.current.error, modifier = Modifier.padding(horizontal = GeistSpacing.space2))
        }
        SubscriptionLinks(isRestoring = isRestoring, onRestore = viewModel::restore, context = context)
    }

    if (showsBeforeYouGo) {
        BeforeYouGoSheet(
            periodEnd = periodEnd,
            switchOffer = switchOffer,
            switchEnabled = !isPurchasing,
            onSwitchToYearly = {
                showsBeforeYouGo = false
                (context as? android.app.Activity)?.let(viewModel::switchToYearly)
            },
            onContinueToCancel = {
                showsBeforeYouGo = false
                openPlay()
            },
            onKeep = { showsBeforeYouGo = false },
        )
    }
}

@Composable
private fun SubscriptionHeroCard(title: String, subtitle: String, owned: Boolean) {
    val colors = LocalGeistColors.current
    val content = if (owned) colors.brandOnSubtle else colors.primary
    Row(
        Modifier
            .fillMaxWidth()
            .clip(RoundedCornerShape(GeistRadii.large))
            .background(if (owned) colors.brandSubtle else colors.background200)
            .semantics(mergeDescendants = true) {}
            .padding(GeistSpacing.space4),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space4),
    ) {
        Image(
            painter = painterResource(R.drawable.app_icon),
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.size(56.dp).clip(RoundedCornerShape(GeistRadii.medium)),
        )
        Column(Modifier.weight(1f)) {
            Text(
                title,
                style = GeistType.heading20.copy(fontWeight = FontWeight.SemiBold),
                color = content,
                modifier = Modifier.semantics { heading() },
            )
            Text(subtitle, style = GeistType.copy14, color = if (owned) content else colors.secondary)
        }
    }
}

@Composable
private fun SubscriptionDetails(ui: SubscriptionUi, periodEnd: String?) {
    val rows = buildList<@Composable (androidx.compose.ui.graphics.Shape) -> Unit> {
        ui.planValue?.let { value ->
            add { shape -> SettingsValueRow(shape, stringResource(R.string.m3_subscription_row_plan), stringResource(value)) }
        }
        if (ui.showsBillingDate) {
            add { shape ->
                SettingsValueRow(
                    shape,
                    stringResource(R.string.m3_subscription_row_billing_date),
                    periodEnd ?: stringResource(R.string.m3_subscription_value_billing_date),
                )
            }
        }
        if (ui.showsAccessUntil && periodEnd != null) {
            add { shape -> SettingsValueRow(shape, stringResource(R.string.m3_subscription_row_access_until), periodEnd) }
        }
        if (ui.showsBilledBy) {
            add { shape ->
                SettingsValueRow(
                    shape,
                    stringResource(R.string.m3_subscription_row_billed_by),
                    stringResource(R.string.m3_subscription_value_google_play),
                )
            }
        }
        if (ui.showsIncludes) {
            add { shape ->
                SettingsRow(
                    shape = shape,
                    title = stringResource(R.string.m3_subscription_row_includes),
                    subtitle = stringResource(R.string.m3_subscription_value_includes),
                    icon = null,
                    onClick = null,
                )
            }
        }
    }
    if (rows.isEmpty()) return
    Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
        rows.forEachIndexed { index, row -> row(groupRowShape(index, rows.size)) }
    }
}

@Composable
private fun SubscriptionPrimary(
    label: String,
    note: Int?,
    onClick: () -> Unit,
    tag: String,
    icon: ImageVector? = null,
) {
    Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
        PrimaryButton(text = label, onClick = onClick, icon = icon, modifier = Modifier.testTag(tag))
        note?.let {
            Text(
                stringResource(it),
                style = GeistType.copy14,
                color = LocalGeistColors.current.secondary,
                modifier = Modifier.padding(horizontal = GeistSpacing.space2),
            )
        }
    }
}

/** What still works and what is paused after a lapse, then a way back without nagging. */
@Composable
private fun SubscriptionEndedContent(onSeePlans: () -> Unit, onPlaySubscriptions: () -> Unit) {
    val colors = LocalGeistColors.current
    SubscriptionSection(title = stringResource(R.string.m3_subscription_still_works)) {
        val items = listOf(
            Triple(Icons.Outlined.Folder, R.string.m3_subscription_works_files_title, R.string.m3_subscription_works_files_body),
            Triple(Icons.Outlined.Tune, R.string.m3_subscription_works_setup_title, R.string.m3_subscription_works_setup_body),
            Triple(
                Icons.Outlined.FavoriteBorder,
                R.string.m3_subscription_works_health_connect_title,
                R.string.m3_subscription_works_health_connect_body,
            ),
        )
        Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
            items.forEachIndexed { index, (icon, title, body) ->
                SettingsRow(
                    shape = groupRowShape(index, items.size),
                    title = stringResource(title),
                    subtitle = stringResource(body),
                    icon = icon,
                    onClick = null,
                )
            }
        }
    }
    SubscriptionSection(title = stringResource(R.string.m3_subscription_paused_heading)) {
        Text(
            stringResource(R.string.m3_subscription_paused_body),
            style = GeistType.copy14,
            color = colors.secondary,
            modifier = Modifier.padding(horizontal = GeistSpacing.space4),
        )
        Text(
            stringResource(R.string.m3_subscription_paused_schedule_note),
            style = GeistType.copy14,
            color = colors.secondary,
            modifier = Modifier.padding(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
        )
    }
    Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
        PrimaryButton(
            text = stringResource(R.string.m3_subscription_see_plans),
            onClick = onSeePlans,
            modifier = Modifier.testTag("subscription.seePlans"),
        )
        TonalActionButton(
            text = stringResource(R.string.m3_subscription_play_subscriptions),
            onClick = onPlaySubscriptions,
            icon = Icons.Outlined.ArrowOutward,
            modifier = Modifier.testTag("subscription.playSubscriptions"),
        )
    }
}

@Composable
private fun SubscriptionSection(title: String, content: @Composable ColumnScope.() -> Unit) {
    Column {
        Text(
            title,
            style = GeistType.heading14,
            color = LocalGeistColors.current.brandPrimary,
            modifier = Modifier
                .padding(start = GeistSpacing.space4, bottom = GeistSpacing.space2)
                .semantics { heading() },
        )
        content()
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun SubscriptionLinks(isRestoring: Boolean, onRestore: () -> Unit, context: Context) {
    val colors = LocalGeistColors.current
    FlowRow(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space1)) {
        TextButton(onClick = onRestore, enabled = !isRestoring, modifier = Modifier.testTag("subscription.restore")) {
            if (isRestoring) {
                CircularProgressIndicator(Modifier.size(16.dp), color = colors.brandPrimary, strokeWidth = 2.dp)
                Spacer(Modifier.size(GeistSpacing.space2))
                Text(stringResource(R.string.paywall_restoring), style = GeistType.button14)
            } else {
                Text(stringResource(R.string.paywall_restore), style = GeistType.button14, color = colors.brandPrimary)
            }
        }
        TextButton(onClick = { openExternalUrl(context, TERMS_URL) }) {
            Text(stringResource(R.string.paywall_terms), style = GeistType.button14, color = colors.brandPrimary)
        }
        TextButton(onClick = { openExternalUrl(context, PRIVACY_URL) }) {
            Text(stringResource(R.string.paywall_privacy), style = GeistType.button14, color = colors.brandPrimary)
        }
    }
}

/**
 * "Before you go" (boards RF_BeforeYouGo / RF_BeforeYouGoOffer): what stops, what you keep, an
 * optional Weekly -> Yearly card, and two equally prominent actions. The card never replaces or
 * demotes Continue to cancel.
 */
@OptIn(ExperimentalMaterial3Api::class)
@Composable
internal fun BeforeYouGoSheet(
    onContinueToCancel: () -> Unit,
    onKeep: () -> Unit,
    periodEnd: String? = null,
    switchOffer: YearlySwitchOffer? = null,
    switchEnabled: Boolean = true,
    onSwitchToYearly: () -> Unit = {},
) {
    val colors = LocalGeistColors.current
    val sheetState = rememberModalBottomSheetState(skipPartiallyExpanded = true)
    ModalBottomSheet(
        onDismissRequest = onKeep,
        sheetState = sheetState,
        containerColor = colors.background100,
    ) {
        BeforeYouGoContent(
            onContinueToCancel = onContinueToCancel,
            onKeep = onKeep,
            periodEnd = periodEnd,
            switchOffer = switchOffer,
            switchEnabled = switchEnabled,
            onSwitchToYearly = onSwitchToYearly,
        )
    }
}

/**
 * The sheet body. Only the lists scroll; both actions and the footnote are a pinned footer, so
 * Keep and Continue to cancel are on screen as soon as the sheet opens, even with long
 * translations or a large font scale.
 */
@Composable
internal fun BeforeYouGoContent(
    onContinueToCancel: () -> Unit,
    onKeep: () -> Unit,
    periodEnd: String? = null,
    switchOffer: YearlySwitchOffer? = null,
    switchEnabled: Boolean = true,
    onSwitchToYearly: () -> Unit = {},
) {
    val colors = LocalGeistColors.current
    Column(
        Modifier
            .fillMaxWidth()
            .navigationBarsPadding()
            .testTag("subscription.beforeYouGo"),
    ) {
        Column(
            Modifier
                .weight(1f, fill = false)
                .verticalScroll(rememberScrollState())
                .padding(horizontal = GeistSpacing.space6),
        ) {
            Text(
                stringResource(R.string.m3_subscription_sheet_title),
                style = GeistType.heading24,
                color = colors.primary,
                modifier = Modifier.semantics { heading() },
            )
            Text(
                periodEnd?.let { stringResource(R.string.m3_subscription_sheet_body_dated, it) }
                    ?: stringResource(R.string.m3_subscription_sheet_body),
                style = GeistType.copy14,
                color = colors.secondary,
                modifier = Modifier.padding(top = GeistSpacing.space2),
            )
            SheetList(
                heading = stringResource(R.string.m3_subscription_stops_heading),
                icon = Icons.Outlined.PauseCircle,
                tint = colors.secondary,
                items = listOf(
                    R.string.m3_subscription_stops_exports,
                    R.string.m3_subscription_stops_automations,
                    R.string.m3_subscription_stops_reports,
                ),
            )
            SheetList(
                heading = stringResource(R.string.m3_subscription_keep_heading),
                icon = Icons.Outlined.CheckCircle,
                tint = colors.success,
                items = listOf(R.string.m3_subscription_keep_files, R.string.m3_subscription_keep_setup),
            )
            switchOffer?.let { SwitchToYearlyCard(it, enabled = switchEnabled, onSwitch = onSwitchToYearly) }
        }
        Column(
            Modifier
                .padding(horizontal = GeistSpacing.space6)
                .padding(top = GeistSpacing.space4, bottom = GeistSpacing.space6),
        ) {
            // Equal size and weight: neither choice is visually demoted.
            Column(
                verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3),
            ) {
                PrimaryButton(
                    text = stringResource(R.string.m3_subscription_continue_to_cancel),
                    onClick = onContinueToCancel,
                    icon = Icons.Outlined.ArrowOutward,
                    modifier = Modifier.testTag("subscription.continueToCancel"),
                )
                TonalActionButton(
                    text = stringResource(R.string.m3_subscription_keep_subscription),
                    onClick = onKeep,
                    modifier = Modifier.testTag("subscription.keep"),
                )
            }
            Text(
                stringResource(R.string.m3_subscription_sheet_footnote),
                style = GeistType.copy13,
                color = colors.secondary,
                modifier = Modifier.padding(top = GeistSpacing.space3, start = GeistSpacing.space1, end = GeistSpacing.space1),
            )
        }
    }
}

/** Board RF_BeforeYouGoOffer: both prices are Play's ProductDetails phases of `switch-yearly-1y`. */
@Composable
private fun SwitchToYearlyCard(offer: YearlySwitchOffer, enabled: Boolean, onSwitch: () -> Unit) {
    val colors = LocalGeistColors.current
    Surface(
        color = colors.brandSubtle,
        shape = RoundedCornerShape(GeistRadii.large),
        modifier = Modifier
            .fillMaxWidth()
            .padding(top = GeistSpacing.space6)
            .testTag("subscription.switchOffer"),
    ) {
        Column(Modifier.padding(GeistSpacing.space4)) {
            Text(
                stringResource(R.string.m3_subscription_offer_eyebrow),
                style = GeistType.label13,
                color = colors.brandOnSubtle,
            )
            Text(
                stringResource(R.string.m3_subscription_offer_title, offer.introductoryFormattedPrice),
                style = GeistType.heading16,
                color = colors.brandOnSubtle,
                modifier = Modifier.padding(top = GeistSpacing.space1).semantics { heading() },
            )
            Text(
                stringResource(R.string.m3_subscription_offer_detail, offer.recurringFormattedPrice),
                style = GeistType.copy14,
                color = colors.brandOnSubtle,
                modifier = Modifier.padding(top = GeistSpacing.space1, bottom = GeistSpacing.space3),
            )
            // Outlined and smaller than the footer actions, so the offer never outranks cancelling.
            OutlinedButton(
                onClick = onSwitch,
                enabled = enabled,
                shape = RoundedCornerShape(GeistRadii.full),
                contentPadding = PaddingValues(horizontal = GeistSpacing.space4, vertical = GeistSpacing.space2),
                modifier = Modifier.testTag("subscription.switchToYearly"),
            ) {
                Text(stringResource(R.string.m3_subscription_offer_action), style = GeistType.button14, color = colors.brandOnSubtle)
            }
        }
    }
}

@Composable
private fun SheetList(heading: String, icon: ImageVector, tint: androidx.compose.ui.graphics.Color, items: List<Int>) {
    val colors = LocalGeistColors.current
    Text(
        heading,
        style = GeistType.heading14,
        color = colors.brandPrimary,
        modifier = Modifier
            .padding(top = GeistSpacing.space6, bottom = GeistSpacing.space2)
            .semantics { heading() },
    )
    Column(verticalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
        items.forEach { item ->
            Row(horizontalArrangement = Arrangement.spacedBy(GeistSpacing.space3)) {
                Icon(icon, contentDescription = null, tint = tint, modifier = Modifier.size(20.dp))
                Text(stringResource(item), style = GeistType.copy14, color = colors.primary, modifier = Modifier.weight(1f))
            }
        }
    }
}

/** A filled tonal pill the same size as [PrimaryButton], for an equally weighted alternative. */
@Composable
private fun TonalActionButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    icon: ImageVector? = null,
) {
    val colors = LocalGeistColors.current
    FilledTonalButton(
        onClick = onClick,
        modifier = modifier.fillMaxWidth().defaultMinSize(minHeight = GeistSizes.controlLarge),
        shape = RoundedCornerShape(GeistRadii.full),
        colors = ButtonDefaults.filledTonalButtonColors(
            containerColor = colors.secondaryContainer,
            contentColor = colors.onSecondaryContainer,
        ),
        elevation = ButtonDefaults.buttonElevation(defaultElevation = 0.dp),
    ) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
            icon?.let { Icon(it, contentDescription = null, modifier = Modifier.size(18.dp)) }
            Text(text, style = GeistType.button16)
        }
    }
}

@Composable
private fun billingErrorText(error: BillingError?): String? = when (error) {
    BillingError.PRODUCT_UNAVAILABLE -> stringResource(R.string.billing_error_product_unavailable)
    BillingError.SERVICE_UNAVAILABLE -> stringResource(R.string.billing_error_service_unavailable)
    BillingError.PURCHASE_FAILED -> stringResource(R.string.billing_error_purchase_failed)
    BillingError.NO_PREVIOUS_PURCHASE -> stringResource(R.string.billing_error_no_previous_purchase)
    BillingError.RESTORE_FAILED -> stringResource(R.string.billing_error_restore_failed)
    null -> null
}

private fun openPlaySubscriptions(context: Context, url: String) {
    Timber.i("Opening Google Play subscriptions: %s", url)
    openExternalUrl(context, url)
}

private const val TERMS_URL = "https://healthmd.app/terms-of-service.html"
private const val PRIVACY_URL = "https://healthmd.app/privacy-policy.html"
