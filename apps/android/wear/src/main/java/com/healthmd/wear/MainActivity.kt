package com.healthmd.wear

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.focusable
import androidx.compose.foundation.layout.*
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.rounded.Air
import androidx.compose.material.icons.rounded.DirectionsWalk
import androidx.compose.material.icons.rounded.SsidChart
import androidx.compose.material.icons.rounded.Favorite
import androidx.compose.material.icons.rounded.LocalFireDepartment
import androidx.compose.material.icons.rounded.MonitorHeart
import androidx.compose.material.icons.rounded.Bedtime
import androidx.compose.material.icons.rounded.Timer
import androidx.compose.runtime.*
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.input.rotary.onPreRotaryScrollEvent
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.wear.compose.foundation.lazy.ScalingLazyColumn
import androidx.wear.compose.foundation.lazy.items
import androidx.wear.compose.foundation.lazy.rememberScalingLazyListState
import androidx.wear.compose.material.*
import com.healthmd.wear.surface.recoveryDay
import com.healthmd.wear.sync.WearRefreshClient
import com.healthmd.wear.sync.WearSnapshotRepository
import com.healthmd.wearable.contract.WearFreshness
import com.healthmd.wearable.contract.WearPermissionState
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.text.NumberFormat
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.Locale

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { WearTheme { Dashboard() } }
    }
}

@Composable private fun WearTheme(content: @Composable () -> Unit) {
    val geist = FontFamily(Font(R.font.geist_sans, FontWeight.Normal), Font(R.font.geist_semibold, FontWeight.SemiBold))
    MaterialTheme(
        colors = Colors(
            primary = WearColors.primary, primaryVariant = WearColors.primary, secondary = WearColors.primary,
            secondaryVariant = WearColors.primary, background = WearColors.background, surface = WearColors.surface,
            error = WearColors.error, onPrimary = WearColors.onPrimary, onSecondary = WearColors.background,
            onBackground = WearColors.text, onSurface = WearColors.text, onSurfaceVariant = WearColors.muted,
            onError = WearColors.background,
        ),
        typography = Typography(defaultFontFamily = geist),
        shapes = Shapes(small = WearShape.sm, medium = WearShape.md, large = WearShape.full),
        content = content,
    )
}

private data class MetricRow(val label: String, val value: String, val icon: ImageVector, val tint: Color)

@Composable private fun Dashboard() {
    val context = LocalContext.current
    val lifecycle = androidx.lifecycle.compose.LocalLifecycleOwner.current.lifecycle
    val cachedSnapshot by WearSnapshotRepository.snapshots.collectAsState()
    val versionMismatch by WearSnapshotRepository.versionMismatch.collectAsState()
    val orderingCorrupt by WearSnapshotRepository.orderingCorrupt.collectAsState()
    val snapshot = cachedSnapshot
    var syncing by remember { mutableStateOf(false) }
    var refreshFailed by remember { mutableStateOf(false) }
    var now by remember { mutableLongStateOf(System.currentTimeMillis()) }
    var lifecycleResumed by remember { mutableStateOf(lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED)) }
    val scope = rememberCoroutineScope()
    val listState = rememberScalingLazyListState()
    val focusRequester = remember { FocusRequester() }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            when (event) {
                Lifecycle.Event.ON_RESUME -> {
                    lifecycleResumed = true
                    now = System.currentTimeMillis()
                    WearSnapshotRepository.reload(context)
                }
                Lifecycle.Event.ON_PAUSE -> lifecycleResumed = false
                else -> Unit
            }
        }
        lifecycle.addObserver(observer); onDispose { lifecycle.removeObserver(observer) }
    }
    LaunchedEffect(Unit) {
        // Wait until the focus target has entered the composition before claiming the crown.
        // Without this yield, rotary events can remain unhandled after a cold launch.
        delay(1)
        focusRequester.requestFocus()
    }

    val freshness = snapshot?.freshness(now)
    val zone = snapshot?.capturedZoneId?.let { runCatching { ZoneId.of(it) }.getOrNull() }
    LaunchedEffect(snapshot?.sequence, snapshot?.capturedAtEpochMillis, zone, lifecycleResumed, now) {
        if (lifecycleResumed && snapshot != null && zone != null) {
            delay((dashboardNextUpdate(snapshot, now, zone) - now).coerceAtLeast(1L))
            now = System.currentTimeMillis()
        }
    }
    val today = snapshot?.days?.firstOrNull {
        it.localDate == zone?.let { capturedZone -> Instant.ofEpochMilli(now).atZone(capturedZone).toLocalDate() }?.toString()
    }
    val recovery = snapshot?.recoveryDay(now)
    val nf = remember { NumberFormat.getNumberInstance(Locale.getDefault()) }
    LaunchedEffect(snapshot?.sequence) {
        if (snapshot != null && !syncing) refreshFailed = false
    }
    val metrics = listOfNotNull(
        today?.steps?.let { MetricRow(stringResource(R.string.wear_steps), nf.format(it), Icons.Rounded.DirectionsWalk, WearColors.metricSteps) },
        today?.moveKilocalories?.let { MetricRow(stringResource(R.string.wear_move), stringResource(R.string.wear_value_kcal, nf.format(it.toInt())), Icons.Rounded.LocalFireDepartment, WearColors.metricMove) },
        today?.exerciseMinutes?.let { MetricRow(stringResource(R.string.wear_exercise), stringResource(R.string.wear_value_minutes, nf.format(it.toInt())), Icons.Rounded.Timer, WearColors.metricExercise) },
        recovery?.sleepMinutes?.let { MetricRow(stringResource(R.string.wear_sleep), stringResource(R.string.wear_value_hours, nf.format(it / 60)), Icons.Rounded.Bedtime, WearColors.metricSleep) },
        today?.restingHeartRateBpm?.let { MetricRow(stringResource(R.string.wear_resting_hr), stringResource(R.string.wear_value_bpm, nf.format(it.toInt())), Icons.Rounded.Favorite, WearColors.metricRestingHeart) },
        today?.averageHeartRateBpm?.let { MetricRow(stringResource(R.string.wear_average_hr), stringResource(R.string.wear_value_bpm, nf.format(it.toInt())), Icons.Rounded.MonitorHeart, WearColors.metricAverageHeart) },
        recovery?.hrvRmssdMillis?.let { MetricRow(stringResource(R.string.wear_hrv), stringResource(R.string.wear_value_ms, nf.format(it.toInt())), Icons.Rounded.SsidChart, WearColors.metricHrv) },
        today?.bloodOxygenPercent?.let { MetricRow(stringResource(R.string.wear_blood_oxygen), stringResource(R.string.wear_value_percent, nf.format(it.toInt())), Icons.Rounded.Air, WearColors.metricOxygen) },
    )
    ScalingLazyColumn(
        state = listState,
        modifier = Modifier
            .fillMaxSize()
            .padding(horizontal = WearSpacing.sm)
            .onPreRotaryScrollEvent { event ->
                // Consume only when the list can move in the requested direction, preserving
                // standard boundary propagation for the system and accessibility services.
                val delta = -event.verticalScrollPixels
                val canMove = if (delta < 0f) listState.canScrollForward else listState.canScrollBackward
                canMove && listState.dispatchRawDelta(delta) != 0f
            }
            .focusRequester(focusRequester)
            .focusable(),
        verticalArrangement = Arrangement.spacedBy(WearSpacing.sm),
        contentPadding = PaddingValues(vertical = WearSpacing.lg),
    ) {
        item { ListHeader { Text(stringResource(R.string.wear_dashboard_title), fontSize = WearType.title) } }
        if (snapshot?.permissionState == WearPermissionState.PERMISSION_REQUIRED) {
            item { StatusText(R.string.wear_permissions, WearColors.warning) }
        }
        when {
            versionMismatch || orderingCorrupt -> item { StatusText(R.string.wear_version_mismatch, WearColors.warning) }
            snapshot == null -> item { StatusText(R.string.wear_setup) }
            snapshot?.permissionState == WearPermissionState.HEALTH_CONNECT_UNAVAILABLE -> item { StatusText(R.string.wear_health_connect_unavailable, WearColors.warning) }
            freshness == WearFreshness.EXPIRED -> item { StatusText(R.string.wear_expired, WearColors.warning) }
            freshness == WearFreshness.VERSION_MISMATCH -> item { StatusText(R.string.wear_version_mismatch, WearColors.warning) }
            metrics.isEmpty() -> item { StatusText(R.string.wear_no_data) }
            else -> {
                if (freshness == WearFreshness.STALE) item { Text(relativeAge(context, snapshot!!.capturedAtEpochMillis, now), color = WearColors.warning, fontSize = WearType.caption) }
                items(metrics) { metric -> MetricRowCard(metric) }
                item { Text(stringResource(R.string.wear_not_realtime), color = WearColors.muted, fontSize = WearType.caption) }
            }
        }
        if (refreshFailed) item { StatusText(R.string.wear_unreachable, WearColors.warning) }
        item { Button(onClick = {
            syncing = true; refreshFailed = false
            scope.launch { refreshFailed = !WearRefreshClient(context).requestRefresh(); syncing = false }
        }, enabled = !syncing) { Text(if (syncing) stringResource(R.string.wear_syncing) else stringResource(R.string.wear_sync), fontSize = WearType.caption) } }
    }
}

@Composable private fun MetricRowCard(metric: MetricRow) {
    Row(
        modifier = Modifier
            .fillMaxWidth()
            .background(WearColors.surface, WearShape.md)
            .padding(horizontal = WearSpacing.sm, vertical = WearSpacing.sm),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(WearSpacing.sm),
    ) {
        Icon(metric.icon, contentDescription = null, tint = metric.tint, modifier = Modifier.size(WearSpacing.xl))
        Text(metric.label, color = WearColors.muted, fontSize = WearType.body, modifier = Modifier.weight(1f), maxLines = 1)
        // Semibold tabular figures keep values aligned and emphasized, mirroring the watchOS row.
        Text(
            metric.value,
            color = WearColors.text,
            fontSize = WearType.body,
            fontWeight = FontWeight.SemiBold,
            style = LocalTextStyle.current.copy(fontFeatureSettings = "tnum"),
            textAlign = TextAlign.End,
            maxLines = 1,
        )
    }
}

@Composable private fun StatusText(id: Int, color: Color = WearColors.muted) = Text(stringResource(id), color = color, fontSize = WearType.body)

internal fun dashboardNextUpdate(snapshot: com.healthmd.wearable.contract.WearHealthSnapshot, now: Long, zone: ZoneId): Long {
    val stale = snapshot.capturedAtEpochMillis + com.healthmd.wearable.contract.WearHealthSnapshot.CURRENT_MILLIS + 1L
    val expired = snapshot.capturedAtEpochMillis + com.healthmd.wearable.contract.WearHealthSnapshot.MAX_DISPLAY_MILLIS + 1L
    val midnight = Instant.ofEpochMilli(now).atZone(zone).toLocalDate().plusDays(1)
        .atStartOfDay(zone).toInstant().toEpochMilli()
    val age = (now - snapshot.capturedAtEpochMillis).coerceAtLeast(0L)
    val nextVisibleAge = if (age >= com.healthmd.wearable.contract.WearHealthSnapshot.CURRENT_MILLIS) {
        snapshot.capturedAtEpochMillis + ((age / 3_600_000L) + 1L) * 3_600_000L
    } else Long.MAX_VALUE
    return listOf(stale, expired, midnight, nextVisibleAge).filter { it > now }.minOrNull() ?: now + 3_600_000L
}

internal fun relativeAge(context: android.content.Context, captured: Long, now: Long): String {
    val minutes = ((now - captured).coerceAtLeast(0) / 60_000).toInt()
    return if (minutes < 60) {
        context.resources.getQuantityString(R.plurals.wear_updated_minutes, minutes, minutes)
    } else {
        val hours = minutes / 60
        context.resources.getQuantityString(R.plurals.wear_updated_hours, hours, hours)
    }
}
