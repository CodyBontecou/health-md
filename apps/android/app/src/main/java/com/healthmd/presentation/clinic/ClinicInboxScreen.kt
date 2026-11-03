package com.healthmd.presentation.clinic

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawingPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.selection.toggleable
import androidx.activity.compose.BackHandler
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Checkbox
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.tooling.preview.Preview
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.domain.practice.*
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.PrimaryButton
import com.healthmd.presentation.common.SecondaryButton
import com.healthmd.presentation.theme.HealthMdTheme
import com.healthmd.presentation.theme.Spacing
import kotlinx.coroutines.launch

/** Qualified callers inject the feature-local controller. No production transport or app route is installed. */
@Composable
fun ClinicInboxScreen(controller: ClinicInboxController = remember { ClinicInboxController() }) {
    val state by controller.state.collectAsStateWithLifecycle()
    val scope = rememberCoroutineScope()
    BackHandler(enabled = state.review != null) { if (!state.busy) controller.dismissReview() }
    val owner = LocalLifecycleOwner.current
    var revoke by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(controller) { controller.load() }
    DisposableEffect(controller, owner) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_STOP) { revoke = null; controller.clear() }
            if (event == Lifecycle.Event.ON_START) scope.launch { controller.load() }
        }
        owner.lifecycle.addObserver(observer)
        onDispose { owner.lifecycle.removeObserver(observer); controller.clear() }
    }
    Column(Modifier.fillMaxSize().safeDrawingPadding().verticalScroll(rememberScrollState()).padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.md)) {
        Text(stringResource(R.string.clinic_sharing), style = MaterialTheme.typography.headlineMedium, modifier = Modifier.semantics { heading() })
        if (state.snapshot.synthetic) Text(stringResource(R.string.clinic_synthetic))
        Text(stringResource(R.string.clinic_intro))
        if (state.loading || state.busy) CircularProgressIndicator()
        if (state.unavailable) Text(stringResource(R.string.clinic_unavailable))
        if (state.error) Text(stringResource(R.string.clinic_error), modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
        SecondaryButton(text = stringResource(R.string.clinic_reload), onClick = { scope.launch { controller.load() } }, enabled = !state.busy)
        val review = state.review
        if (review != null) {
            GeistCard(padding = Spacing.sm) {
                Text(stringResource(R.string.clinic_review), style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
                Text(review.clinic); Text(review.profile); Text(review.destination)
                Text(stringResource(R.string.clinic_metrics), style = MaterialTheme.typography.titleMedium)
                review.metrics.forEach { Text(it) }
                Text(stringResource(R.string.clinic_options), style = MaterialTheme.typography.titleMedium)
                review.options.forEach { Text(stringResource(R.string.clinic_fact, it.label, it.value)) }
                Text(review.schedule); Text(stringResource(R.string.clinic_paused_schedule))
                Text(stringResource(when (review.access) {
                    ClinicInboxAccess.CLINIC_COVERED -> R.string.clinic_covered
                    ClinicInboxAccess.CONSUMER -> R.string.clinic_consumer
                    ClinicInboxAccess.UNAVAILABLE -> R.string.clinic_access_unavailable
                }))
                Text(stringResource(R.string.clinic_permissions))
                Text(stringResource(R.string.clinic_expires, java.text.DateFormat.getDateTimeInstance().format(java.util.Date(review.expiresAtMillis))))
                // A whole-row check target keeps the consent label reachable at large font sizes.
                androidx.compose.foundation.layout.Row(modifier = Modifier.fillMaxWidth().toggleable(value = state.consent, role = Role.Checkbox, enabled = !state.busy, onValueChange = controller::setConsent), verticalAlignment = androidx.compose.ui.Alignment.CenterVertically) {
                    Checkbox(checked = state.consent, onCheckedChange = null)
                    Text(stringResource(R.string.clinic_consent))
                }
                PrimaryButton(text = stringResource(R.string.clinic_apply), onClick = { scope.launch { controller.apply() } }, enabled = controller.canApply)
                SecondaryButton(text = stringResource(R.string.clinic_cancel_review), onClick = controller::dismissReview, enabled = !state.busy)
            }
        } else {
            Text(stringResource(R.string.clinic_setups), style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
            if (state.snapshot.reviews.isEmpty() && !state.loading) Text(stringResource(R.string.clinic_no_setups))
            state.snapshot.reviews.forEach { item ->
                GeistCard(padding = Spacing.sm) {
                    Text(item.clinic, style = MaterialTheme.typography.titleMedium); Text(item.profile)
                    SecondaryButton(text = stringResource(R.string.clinic_review), onClick = { controller.openReview(item.id) }, enabled = !state.busy)
                }
            }
            Text(stringResource(R.string.clinic_requests), style = MaterialTheme.typography.titleLarge, modifier = Modifier.semantics { heading() })
            if (state.snapshot.refreshes.isEmpty() && !state.loading) Text(stringResource(R.string.clinic_no_requests))
            state.snapshot.refreshes.forEach { item ->
                GeistCard(padding = Spacing.sm) {
                    Text(item.clinic, style = MaterialTheme.typography.titleMedium)
                    Text(item.profile); Text(item.destination); Text(item.scope); Text(item.metrics.joinToString(", "))
                    Text(stringResource(statusResource(item.status)), modifier = Modifier.semantics { liveRegion = LiveRegionMode.Polite })
                    if (item.receiptPending) {
                        Text(stringResource(R.string.clinic_receipt_pending))
                        SecondaryButton(text = stringResource(R.string.clinic_report), onClick = { scope.launch { controller.reportReceipt(item.id) } }, enabled = !state.busy && !state.error && state.controls.isEmpty())
                    }
                    if (item.status == ClinicInboxStatus.REQUESTED && item.sharingActive) PrimaryButton(text = stringResource(R.string.clinic_export), onClick = { scope.launch { controller.export(item.id) } }, enabled = !state.busy && !state.error && state.controls.isEmpty())
                    if (item.status in listOf(ClinicInboxStatus.REQUESTED, ClinicInboxStatus.RUNNING)) SecondaryButton(text = stringResource(R.string.clinic_cancel_work), onClick = { scope.launch { controller.cancel(item.id) } }, enabled = "cancel:${item.id}" !in state.controls)
                    if (!item.sharingActive && item.status != ClinicInboxStatus.REVOKED) Text(stringResource(R.string.clinic_revoked))
                    if (item.sharingActive) SecondaryButton(text = stringResource(R.string.clinic_stop), onClick = { revoke = item.connectionId }, enabled = "revoke:${item.connectionId}" !in state.controls)
                }
            }
        }
    }
    if (revoke != null) AlertDialog(
        onDismissRequest = { revoke = null }, title = { Text(stringResource(R.string.clinic_stop_title)) },
        text = { Text(stringResource(R.string.clinic_stop_description)) },
        confirmButton = { TextButton(onClick = { val id = revoke; revoke = null; if (id != null) scope.launch { controller.revoke(id) } }) { Text(stringResource(R.string.clinic_stop)) } },
        dismissButton = { TextButton(onClick = { revoke = null }) { Text(stringResource(R.string.clinic_cancel_review)) } },
    )
}

private fun statusResource(value: ClinicInboxStatus): Int = when (value) {
    ClinicInboxStatus.REQUESTED -> R.string.clinic_requested
    ClinicInboxStatus.RUNNING -> R.string.clinic_running
    ClinicInboxStatus.UPLOADED -> R.string.clinic_uploaded
    ClinicInboxStatus.PROCESSED -> R.string.clinic_processed
    ClinicInboxStatus.FAILED -> R.string.clinic_failed
    ClinicInboxStatus.CANCELLED -> R.string.clinic_cancelled
    ClinicInboxStatus.EXPIRED -> R.string.clinic_expired
    ClinicInboxStatus.REVOKED -> R.string.clinic_revoked
}

@Preview
@Composable
private fun SyntheticClinicInboxPreview() {
    HealthMdTheme { ClinicInboxScreen(remember { ClinicInboxController(SyntheticClinicInboxTransport(), { true }) }) }
}
