package com.healthmd.presentation.directcli

import android.app.KeyguardManager
import android.content.Context
import android.os.Looper
import android.os.UserManager
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.window.Dialog
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import com.healthmd.R
import com.healthmd.direct.*
import com.healthmd.direct.protocol.*
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.Spacing
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.ZoneOffset
import java.time.temporal.ChronoUnit

private class NativeGrantEditorContext(val trust: AgentBridgeExportNativeTrust.Snapshot) {
    val peer = AgentBridgePeer(trust.hostInstallationId, AgentBridgePlatform.ANDROID, trust.sourceInstallationId)
    fun requireOriginalPairing(context: Context) {
        val secret = trust.copyReconnectSecret()
        try { AgentBridgeExportNativeTrust(context).requireCurrent(trust, trust.sourceInstallationId, trust.hostInstallationId, secret) }
        finally { secret.fill(0) }
    }
}

internal fun requireNativeAgentConsentPolicy(context: Context, lifecycle: Lifecycle, protected: Boolean) {
    if (Looper.myLooper() != Looper.getMainLooper() || !lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) ||
        protected || context.isDeviceProtectedStorage || context.getSystemService(UserManager::class.java)?.isUserUnlocked != true ||
        context.getSystemService(KeyguardManager::class.java)?.isKeyguardLocked != false) {
        throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
    }
}

@Composable
internal fun AgentExportPermissionsManagementControls() {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val protection by rememberUpdatedState(LocalConfigurationProtection.current)
    var grants by remember { mutableStateOf(emptyList<AgentBridgeExportDelegation>()) }
    var editor by remember { mutableStateOf<NativeGrantEditorContext?>(null) }
    var revocation by remember { mutableStateOf<AgentBridgeExportDelegation?>(null) }
    var message by remember { mutableStateOf<Int?>(null) }

    fun refresh() {
        try {
            grants = AgentBridgeExportAuthorityStore.forNoBackup(context).access { tx ->
                if (tx == null) throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
                tx.state.grants.filterNot { it.revoked }.map { it.delegation() }
            }
            message = null
        } catch (_: Exception) { grants = emptyList(); message = R.string.agent_export_grant_unverified }
    }
    LaunchedEffect(context) { refresh() }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) refresh()
            if (event == Lifecycle.Event.ON_PAUSE || event == Lifecycle.Event.ON_STOP) { editor = null; revocation = null }
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        message?.let { Text(stringResource(it), color = AppColors.textMuted) }
        grants.forEach { grant ->
            Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Text(stringResource(R.string.agent_export_grant_computer), style = MaterialTheme.typography.titleSmall)
                Text(grantSummary(context, grant), style = MaterialTheme.typography.bodySmall)
                TextButton(onClick = {
                    if (protection.enabled) protection.onBlockedChange() else revocation = grant
                }, modifier = Modifier.testTag("agent_export_permissions_revoke_${grant.authorityId}")) {
                    Text(stringResource(R.string.agent_export_grant_revoke))
                }
            }
        }
        Button(onClick = {
            if (protection.enabled) protection.onBlockedChange()
            else try {
                requireNativeAgentConsentPolicy(context, lifecycle, protection.enabled)
                val trust = AgentBridgeExportNativeTrust(context).loadExisting()
                if (trust == null) message = R.string.agent_export_grant_pair_required
                else { editor = NativeGrantEditorContext(trust); message = null }
            } catch (_: Exception) { message = R.string.agent_export_grant_unverified }
        }, modifier = Modifier.testTag("agent_export_permissions_add")) { Text(stringResource(R.string.agent_export_grant_add)) }
        TextButton(onClick = ::refresh) { Text(stringResource(R.string.agent_export_grant_refresh)) }
        AgentExportPlanReviewControls()
    }
    editor?.let { review -> NativeGrantEditor(review, onDismiss = { editor = null; refresh() }) }
    revocation?.let { review ->
        AlertDialog(onDismissRequest = { revocation = null },
            title = { Text(stringResource(R.string.agent_export_grant_revoke_title)) },
            text = { Text(grantSummary(context, review)) },
            dismissButton = { TextButton(onClick = { revocation = null }) { Text(stringResource(android.R.string.cancel)) } },
            confirmButton = {
                TextButton(onClick = confirm@{
                    if (revocation?.authorityId != review.authorityId) return@confirm
                    revocation = null
                    try {
                        AgentBridgeExportNativeConsent.withNativeConfirmation(
                            AgentBridgeExportNativeDecision.Revoke(review.peer, review.authorityId, review.grantRevision),
                            requireCurrentNativePolicy = { requireNativeAgentConsentPolicy(context, lifecycle, protection.enabled) }) { consent ->
                            // Forgetting pairing must not strand an existing grant: revocation needs no pairing read.
                            AgentBridgeExportAuthorityStore.forNoBackup(context).revoke(consent, review.peer, review.authorityId, review.grantRevision)
                        }
                        refresh()
                    } catch (_: Exception) { message = R.string.agent_export_grant_unverified }
                }) { Text(stringResource(R.string.agent_export_grant_revoke)) }
            })
    }
}

@OptIn(ExperimentalMaterial3Api::class)
@Composable
private fun NativeGrantEditor(reviewContext: NativeGrantEditorContext, onDismiss: () -> Unit) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val protection by rememberUpdatedState(LocalConfigurationProtection.current)
    val zone = remember { ZoneId.systemDefault() }
    var metrics by remember { mutableStateOf(emptySet<String>()) }
    var start by remember { mutableStateOf(LocalDate.now(zone)) }
    var end by remember { mutableStateOf(LocalDate.now(zone)) }
    var hours by remember { mutableIntStateOf(1) }
    var pickingStart by remember { mutableStateOf<Boolean?>(null) }
    var candidate by remember { mutableStateOf<AgentBridgeExportDelegation?>(null) }
    var failed by remember { mutableStateOf(false) }
    var invalid by remember { mutableStateOf(false) }

    Dialog(onDismissRequest = onDismiss) {
        Surface(shape = MaterialTheme.shapes.large, color = AppColors.bgPrimary,
            modifier = Modifier.fillMaxWidth().fillMaxHeight(GeistSizes.dialogMaxHeightFraction)) {
            Column(Modifier.padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                Text(stringResource(R.string.agent_export_grant_add), style = MaterialTheme.typography.titleLarge)
                Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    Text(reviewContext.trust.displayName)
                    Text(reviewContext.peer.hostInstallationId, style = MaterialTheme.typography.bodySmall)
                    Text(stringResource(R.string.agent_export_grant_metrics), style = MaterialTheme.typography.titleMedium)
                    AgentBridgeExportNativeGrantDraft.metricIds.forEach { id ->
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                            Checkbox(checked = id in metrics, onCheckedChange = { checked -> metrics = if (checked) metrics + id else metrics - id })
                            Text(context.getString(metricLabel(id)))
                        }
                    }
                    Text(stringResource(R.string.agent_export_grant_scope), style = MaterialTheme.typography.titleMedium)
                    OutlinedButton(onClick = { pickingStart = true }) { Text(stringResource(R.string.agent_export_grant_start) + ": " + start) }
                    OutlinedButton(onClick = { pickingStart = false }) { Text(stringResource(R.string.agent_export_grant_end) + ": " + end) }
                    Text(stringResource(R.string.agent_export_grant_timezone) + ": " + zone.id)
                    Text(stringResource(R.string.agent_export_grant_format) + ": JSON")
                    Text(stringResource(R.string.agent_export_grant_expiry), style = MaterialTheme.typography.titleMedium)
                    listOf(1 to R.string.agent_export_grant_hour, 24 to R.string.agent_export_grant_day, 168 to R.string.agent_export_grant_week).forEach { (value, label) ->
                        Row(horizontalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                            RadioButton(selected = hours == value, onClick = { hours = value })
                            Text(stringResource(label))
                        }
                    }
                    Text(stringResource(R.string.agent_export_grant_warning), style = MaterialTheme.typography.bodySmall)
                    if (invalid) Text(stringResource(R.string.agent_export_grant_invalid))
                    if (failed) Text(stringResource(R.string.agent_export_grant_unverified))
                }
                Button(enabled = metrics.isNotEmpty() && !failed && candidate == null, onClick = {
                    if (protection.enabled) protection.onBlockedChange()
                    else try {
                        requireNativeAgentConsentPolicy(context, lifecycle, protection.enabled)
                        reviewContext.requireOriginalPairing(context)
                        val now = Instant.now()
                        candidate = AgentBridgeExportNativeGrantDraft.make(reviewContext.peer, metrics, start, end, zone.id, now.plus(hours.toLong(), ChronoUnit.HOURS), now)
                        invalid = false
                    } catch (_: Exception) { invalid = true }
                }, modifier = Modifier.fillMaxWidth().testTag("agent_export_permissions_review")) { Text(stringResource(R.string.agent_export_grant_review)) }
                TextButton(onClick = onDismiss) { Text(stringResource(android.R.string.cancel)) }
            }
        }
    }
    pickingStart?.let { isStart ->
        val state = rememberDatePickerState(initialSelectedDateMillis = (if (isStart) start else end).atStartOfDay(ZoneOffset.UTC).toInstant().toEpochMilli())
        DatePickerDialog(onDismissRequest = { pickingStart = null },
            confirmButton = { TextButton(onClick = {
                state.selectedDateMillis?.let { millis ->
                    val date = Instant.ofEpochMilli(millis).atZone(ZoneOffset.UTC).toLocalDate()
                    if (isStart) start = date else end = date
                }
                pickingStart = null
            }) { Text(stringResource(android.R.string.ok)) } },
            dismissButton = { TextButton(onClick = { pickingStart = null }) { Text(stringResource(android.R.string.cancel)) } }) { DatePicker(state = state) }
    }
    candidate?.let { review ->
        AlertDialog(onDismissRequest = { candidate = null },
            title = { Text(stringResource(R.string.agent_export_grant_allow_title)) },
            text = { Text(reviewContext.trust.displayName + "\n" + grantSummary(context, review)) },
            dismissButton = { TextButton(onClick = { candidate = null }) { Text(stringResource(android.R.string.cancel)) } },
            confirmButton = { TextButton(onClick = confirm@{
                if (candidate?.authorityId != review.authorityId) return@confirm
                candidate = null
                try {
                    val sha = AgentBridgeCodec.fingerprint(review)
                    AgentBridgeExportNativeConsent.withNativeConfirmation(AgentBridgeExportNativeDecision.Delegation(sha, 0),
                        requireCurrentNativePolicy = {
                            requireNativeAgentConsentPolicy(context, lifecycle, protection.enabled)
                            reviewContext.requireOriginalPairing(context)
                            if (!Instant.parse(review.expiresAt).isAfter(Instant.now())) throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
                        }) { consent -> AgentBridgeExportAuthorityStore.forNoBackup(context).putDelegation(consent, review, 0) }
                    onDismiss()
                } catch (_: Exception) { failed = true }
            }, modifier = Modifier.testTag("agent_export_permissions_allow")) { Text(stringResource(R.string.agent_export_grant_allow)) } })
    }
}

private fun metricLabel(id: String): Int = when (id) {
    "steps" -> R.string.metric_name_steps
    "heart_rate_avg" -> R.string.metric_name_avg_hr
    "heart_rate_min" -> R.string.metric_name_min_hr
    "heart_rate_max" -> R.string.metric_name_max_hr
    "resting_heart_rate" -> R.string.metric_name_resting_hr
    else -> R.string.metric_name_hrv
}
private fun grantSummary(context: Context, grant: AgentBridgeExportDelegation): String {
    val dates = when (val policy = grant.bounds.datePolicy) {
        is AgentBridgeExportDelegationBoundsDatePolicyBoundedExact -> policy.range.startDate + " – " + policy.range.endDate
        is AgentBridgeExportDelegationBoundsDatePolicyAuthorizedHistory -> context.getString(R.string.agent_export_grant_day_limit) + ": " + policy.maxDays
    }
    return listOf(grant.peer.hostInstallationId, dates,
        grant.bounds.metricIds.joinToString(", ") { if (it in AgentBridgeExportNativeGrantDraft.metricIds) context.getString(metricLabel(it)) else it },
        grant.bounds.calendarTimezones.joinToString(", "), grant.bounds.formats.joinToString(", ") { it.name },
        context.getString(R.string.agent_export_grant_expiry) + ": " + grant.expiresAt,
        context.getString(R.string.agent_export_grant_warning)).joinToString("\n")
}
