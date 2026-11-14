package com.healthmd.presentation.directcli

import android.app.KeyguardManager
import android.content.Context
import android.os.UserManager
import androidx.compose.foundation.layout.*
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.*
import androidx.compose.runtime.*
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.window.Dialog
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.hilt.navigation.compose.hiltViewModel
import androidx.lifecycle.*
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import com.healthmd.R
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.data.settings.SettingsRepositoryImpl
import com.healthmd.direct.*
import com.healthmd.direct.protocol.*
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.GeistSizes
import com.healthmd.presentation.theme.Spacing
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import java.util.concurrent.atomic.AtomicBoolean
import javax.inject.Inject
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonElement

internal data class AgentNativePlanReview(val planner: AgentBridgeNativePlanningSession, val plan: AgentBridgeGeneratedPlan)

/** Created by an actual main-thread native confirmation, closed synchronously on pause/stop.
 * Workers read only the atomic lease and current OS policy; never bounce to the UI while holding
 * issuer locks. The exact decision remains bound separately by NativeConsent and the planner. */
internal class AgentNativeReviewConfirmation private constructor(private val context: Context,
    private val lifecycle: Lifecycle, private val clockNanos: () -> Long, private val confirmedAtNanos: Long) : LifecycleEventObserver, AutoCloseable {
    private val active = AtomicBoolean(true)
    override fun onStateChanged(source: LifecycleOwner, event: Lifecycle.Event) {
        if (event == Lifecycle.Event.ON_PAUSE || event == Lifecycle.Event.ON_STOP || event == Lifecycle.Event.ON_DESTROY) invalidate()
    }
    fun invalidate() { active.set(false) }
    fun requireCurrent(protected: Boolean?) {
        if (!active.get() || (clockNanos() - confirmedAtNanos) !in 0L until 30_000_000_000L || protected != false || context.isDeviceProtectedStorage ||
            context.getSystemService(UserManager::class.java)?.isUserUnlocked != true ||
            context.getSystemService(KeyguardManager::class.java)?.isKeyguardLocked != false) {
            invalidate(); throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
        }
        if (!active.get() || (clockNanos() - confirmedAtNanos) !in 0L until 30_000_000_000L) {
            invalidate(); throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
        }
    }
    // The UI owns observer removal. Worker completion may only invalidate its atomic lease.
    override fun close() { invalidate(); lifecycle.removeObserver(this) }
    companion object {
        fun fromNativeConfirmation(context: Context, lifecycle: Lifecycle, protected: Boolean,
            clockNanos: () -> Long = { android.os.SystemClock.elapsedRealtimeNanos() }): AgentNativeReviewConfirmation {
            val confirmedAt = clockNanos() // Capture at the native tap, before OS checks or worker dispatch.
            requireNativeAgentConsentPolicy(context, lifecycle, protected)
            return AgentNativeReviewConfirmation(context.applicationContext, lifecycle, clockNanos, confirmedAt).also { lifecycle.addObserver(it) }
        }
    }
}

@HiltViewModel
internal class AgentExportPlanReviewViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val coordinator: DirectCliCoordinator,
    private val dataStore: DataStore<Preferences>,
    private val settings: SettingsRepository,
    private val profiles: ExportProfileRepository,
) : ViewModel() {
    private val _requests = MutableStateFlow<List<AgentNativePlanReview>>(emptyList())
    val requests = _requests.asStateFlow()
    private val _failed = MutableStateFlow(false)
    val failed = _failed.asStateFlow()
    private val _busy = MutableStateFlow(false)
    val busy = _busy.asStateFlow()
    private var work: Job? = null
    private var generation = 0L

    fun refresh() {
        cancel()
        val acceptedGeneration = generation
        _busy.value = true; _failed.value = false; _requests.value = emptyList()
        work = viewModelScope.launch {
            try {
                _requests.value = withContext(Dispatchers.IO) {
                    val nativeSettings = settings as? SettingsRepositoryImpl ?: throw AgentBridgeException(AgentBridgeErrorCode.PERMISSION_REQUIRED)
                    val planner = coordinator.agentBridgeNativePlanningSession(context, dataStore, nativeSettings, profiles)
                    planner.nativePlansAwaitingReview().map { AgentNativePlanReview(planner, it) }
                }
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { if (generation == acceptedGeneration) _failed.value = true }
            finally { if (generation == acceptedGeneration) _busy.value = false }
        }
    }
    fun cancel() { generation++; work?.cancel(); work = null; _busy.value = false; _requests.value = emptyList() }
    fun approve(review: AgentNativePlanReview, confirmation: AgentNativeReviewConfirmation, completed: () -> Unit) {
        cancel(); val acceptedGeneration = generation
        _busy.value = true; _failed.value = false
        work = viewModelScope.launch {
            try {
                withContext(Dispatchers.IO) {
                    val operation = currentCoroutineContext()
                    val binding = AgentBridgeValidation.bindingFor(review.plan)
                    AgentBridgeExportNativeConsent.withNativeConfirmation(
                        AgentBridgeExportNativeDecision.ExactApproval(review.plan.planId, binding),
                        requireCurrentNativePolicy = {
                            operation.ensureActive()
                            confirmation.requireCurrent(coordinator.agentBridgeNativeConfigurationProtected())
                            review.planner.requireCurrent()
                        }) { consent -> review.planner.authorizeExactApproval(consent, review.plan.planId, binding) }
                }
                _requests.value = emptyList()
            } catch (cancelled: CancellationException) { throw cancelled }
            catch (_: Exception) { if (generation == acceptedGeneration) _failed.value = true }
            finally {
                confirmation.invalidate()
                if (generation == acceptedGeneration) { _busy.value = false; completed() }
            }
        }
    }
}

@Composable
internal fun AgentExportPlanReviewControls(viewModel: AgentExportPlanReviewViewModel = hiltViewModel()) {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val protection = LocalConfigurationProtection.current
    val requests by viewModel.requests.collectAsStateWithLifecycle()
    val failed by viewModel.failed.collectAsStateWithLifecycle()
    val busy by viewModel.busy.collectAsStateWithLifecycle()
    var selected by remember { mutableStateOf<AgentNativePlanReview?>(null) }
    var confirming by remember { mutableStateOf(false) }
    var checked by remember { mutableStateOf(false) }
    var confirmation by remember { mutableStateOf<AgentNativeReviewConfirmation?>(null) }
    fun dismissReview() { confirmation?.close(); confirmation = null; confirming = false; selected = null; viewModel.cancel() }
    DisposableEffect(lifecycle, viewModel) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_PAUSE || event == Lifecycle.Event.ON_STOP || event == Lifecycle.Event.ON_DESTROY) dismissReview()
        }
        lifecycle.addObserver(observer)
        onDispose { dismissReview(); lifecycle.removeObserver(observer) }
    }
    SideEffect { if (protection.enabled) confirmation?.invalidate() }
    Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
        Text(stringResource(R.string.agent_export_review_requests), style = MaterialTheme.typography.titleSmall)
        TextButton(enabled = !busy, onClick = { dismissReview(); checked = true; viewModel.refresh() },
            modifier = Modifier.testTag("agent_export_requests_refresh")) { Text(stringResource(R.string.agent_export_review_refresh)) }
        if (busy) CircularProgressIndicator()
        if (failed) Text(stringResource(R.string.agent_export_review_failed), color = AppColors.textMuted)
        else if (checked && !busy && requests.isEmpty()) Text(stringResource(R.string.agent_export_review_empty), color = AppColors.textMuted)
        requests.forEach { review ->
            OutlinedButton(enabled = !busy, onClick = { selected = review },
                modifier = Modifier.fillMaxWidth().testTag("agent_export_requests_review_${review.plan.planId}")) {
                Column { Text(reviewDates(review.plan)); Text(review.plan.intent.peer.hostInstallationId, style = MaterialTheme.typography.bodySmall) }
            }
        }
    }
    selected?.let { review ->
        Dialog(onDismissRequest = ::dismissReview) {
            Surface(shape = MaterialTheme.shapes.large, color = AppColors.bgPrimary,
                modifier = Modifier.fillMaxWidth().fillMaxHeight(GeistSizes.dialogMaxHeightFraction)) {
                Column(Modifier.padding(Spacing.md), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                    Text(stringResource(R.string.agent_export_review_title), style = MaterialTheme.typography.titleLarge)
                    Column(Modifier.weight(1f).verticalScroll(rememberScrollState()), verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
                        ReviewValue(R.string.agent_export_grant_computer, review.plan.intent.peer.hostInstallationId)
                        ReviewValue(R.string.agent_export_grant_scope, reviewDates(review.plan))
                        ReviewValue(R.string.agent_export_grant_timezone, review.plan.intent.calendarTimezone)
                        ReviewValue(R.string.agent_export_grant_metrics, review.plan.resolvedMetricIds.joinToString(", "))
                        ReviewValue(R.string.agent_export_grant_expiry, review.plan.expiresAt)
                        ReviewValue(R.string.agent_export_grant_format, review.plan.effectiveSettings.formats.joinToString(", "))
                        ReviewValue(R.string.agent_export_review_write_mode, review.plan.effectiveSettings.writeMode.toString())
                        ReviewValue(R.string.agent_export_review_folder, review.plan.effectiveSettings.folderTemplate)
                        ReviewValue(R.string.agent_export_review_filename, review.plan.effectiveSettings.filenameTemplate)
                        ReviewValue(R.string.agent_export_review_subfolder, review.plan.effectiveSettings.subfolder)
                        ReviewValue(R.string.agent_export_review_destination, review.plan.intent.destination.bindingId + "\n" + review.plan.intent.destination.identitySha256)
                        Text(stringResource(R.string.agent_export_review_destination_note), style = MaterialTheme.typography.bodySmall)
                        ReviewValue(R.string.agent_export_review_paths, review.plan.predictedPaths.joinToString("\n"))
                        var expanded by remember(review.plan.planId) { mutableStateOf(false) }
                        TextButton(onClick = { expanded = !expanded }) { Text(stringResource(R.string.agent_export_review_details)) }
                        if (expanded) SelectionContainer { Text(reviewDetails(review.plan), style = MaterialTheme.typography.bodySmall) }
                        Text(stringResource(R.string.agent_export_review_scope_note), style = MaterialTheme.typography.bodySmall)
                    }
                    Button(enabled = !busy, onClick = {
                        if (protection.enabled) protection.onBlockedChange() else confirming = true
                    }, modifier = Modifier.fillMaxWidth().testTag("agent_export_requests_allow")) { Text(stringResource(R.string.agent_export_review_allow)) }
                    TextButton(onClick = ::dismissReview) { Text(stringResource(R.string.cancel)) }
                }
            }
            if (confirming) AlertDialog(onDismissRequest = { confirming = false },
                title = { Text(stringResource(R.string.agent_export_review_confirm)) },
                text = { Text(reviewDates(review.plan) + "\n" + review.plan.intent.peer.hostInstallationId + "\n" + review.plan.intent.destination.bindingId) },
                dismissButton = { TextButton(onClick = { confirming = false }) { Text(stringResource(R.string.cancel)) } },
                confirmButton = { TextButton(onClick = {
                    if (selected !== review || busy) return@TextButton
                    confirming = false
                    try {
                        val lease = AgentNativeReviewConfirmation.fromNativeConfirmation(context, lifecycle, protection.enabled)
                        confirmation = lease
                        viewModel.approve(review, lease) { lease.close(); confirmation = null; selected = null }
                    } catch (_: Exception) { dismissReview() }
                }) { Text(stringResource(R.string.agent_export_review_allow)) } })
        }
    }
}

@Composable private fun ReviewValue(label: Int, value: String) {
    Column { Text(stringResource(label), style = MaterialTheme.typography.labelLarge); SelectionContainer { Text(value, style = MaterialTheme.typography.bodySmall) } }
}
private fun reviewDates(plan: AgentBridgeGeneratedPlan): String = when (val dates = plan.resolvedDates) {
    is AgentBridgeDatesExact -> dates.range.startDate + " – " + dates.range.endDate
    is AgentBridgeDatesPastCompleteDays -> dates.days.toString() + " / " + dates.anchorDate
    is AgentBridgeDatesAllAvailable -> "all_available"
}
private fun reviewDetails(plan: AgentBridgeGeneratedPlan): String {
    val pretty = Json { prettyPrint = true }
    val value = Json.parseToJsonElement(AgentBridgeCodec.encode(plan).decodeToString())
    return pretty.encodeToString(JsonElement.serializer(), value)
}
