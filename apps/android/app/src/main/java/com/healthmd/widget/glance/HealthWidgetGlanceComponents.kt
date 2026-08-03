package com.healthmd.widget.glance

import android.appwidget.AppWidgetManager
import android.content.BroadcastReceiver
import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.os.UserManager
import androidx.glance.GlanceId
import androidx.glance.LocalSize
import androidx.glance.appwidget.GlanceAppWidget
import androidx.glance.appwidget.GlanceAppWidgetReceiver
import androidx.glance.appwidget.SizeMode
import androidx.glance.appwidget.provideContent
import androidx.glance.appwidget.updateAll
import androidx.glance.color.ColorProvider
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import com.healthmd.presentation.theme.GeistDarkColors
import com.healthmd.presentation.theme.GeistLightColors
import com.healthmd.widget.data.HealthWidgetSnapshotStore
import com.healthmd.widget.model.HealthWidgetKind
import com.healthmd.widget.model.HealthWidgetSnapshot
import com.healthmd.widget.model.WidgetRefreshOutcome
import com.healthmd.widget.refresh.HealthWidgetInstanceRegistry
import com.healthmd.widget.refresh.HealthWidgetLifecycleCoordinator
import com.healthmd.widget.refresh.HealthWidgetRefreshScheduler
import com.healthmd.widget.refresh.HealthWidgetUpdater
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import java.time.Instant
import java.time.ZoneId
import javax.inject.Inject
import javax.inject.Singleton
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock

object HealthWidgetSizes {
    val Compact = DpSize(110.dp, 110.dp)
    val Wide = DpSize(250.dp, 110.dp)
    val Medium = DpSize(250.dp, 250.dp)
    val Large = DpSize(250.dp, 400.dp)
}

abstract class BaseHealthGlanceWidget(
    internal val kind: HealthWidgetKind,
    supportedSizes: Set<DpSize>,
) : GlanceAppWidget() {
    final override val sizeMode: SizeMode = SizeMode.Responsive(supportedSizes)

    final override suspend fun provideGlance(context: Context, id: GlanceId) {
        val entryPoint = context.healthWidgetEntryPoint()
        val now = Instant.now()
        val userManager = context.getSystemService(UserManager::class.java)
        val snapshot = if (userManager?.isUserUnlocked == false) {
            HealthWidgetSnapshot(
                lastAttemptAtEpochMillis = now.toEpochMilli(),
                lastAttemptOutcome = WidgetRefreshOutcome.BEFORE_FIRST_UNLOCK,
            )
        } else {
            runCatching { entryPoint.snapshotStore().load() }.getOrNull()
        }
        val artwork = WidgetArtworkRenderer().render(context, snapshot, kind)
        val zoneId = ZoneId.systemDefault()

        provideContent {
            HealthWidgetContent(
                kind = kind,
                snapshot = snapshot,
                now = now,
                zoneId = zoneId,
                size = LocalSize.current,
                artwork = artwork,
            )
        }
    }
}

class HealthSummaryGlanceWidget : BaseHealthGlanceWidget(
    kind = HealthWidgetKind.SUMMARY,
    supportedSizes = setOf(
        HealthWidgetSizes.Compact,
        HealthWidgetSizes.Wide,
        HealthWidgetSizes.Medium,
        HealthWidgetSizes.Large,
    ),
)

class ActivityGlanceWidget : BaseHealthGlanceWidget(
    kind = HealthWidgetKind.ACTIVITY,
    supportedSizes = setOf(HealthWidgetSizes.Compact, HealthWidgetSizes.Wide),
)

class HeartRangeGlanceWidget : BaseHealthGlanceWidget(
    kind = HealthWidgetKind.HEART_RANGE,
    supportedSizes = setOf(
        HealthWidgetSizes.Wide,
        HealthWidgetSizes.Medium,
        HealthWidgetSizes.Large,
    ),
)

class SleepGlanceWidget : BaseHealthGlanceWidget(
    kind = HealthWidgetKind.SLEEP,
    supportedSizes = setOf(
        HealthWidgetSizes.Compact,
        HealthWidgetSizes.Wide,
        HealthWidgetSizes.Medium,
        HealthWidgetSizes.Large,
    ),
)

abstract class BaseHealthWidgetReceiver : GlanceAppWidgetReceiver() {
    final override fun onEnabled(context: Context) {
        super.onEnabled(context)
        context.healthWidgetEntryPoint().refreshScheduler().enqueueImmediate()
    }

    final override fun onUpdate(
        context: Context,
        appWidgetManager: AppWidgetManager,
        appWidgetIds: IntArray,
    ) {
        super.onUpdate(context, appWidgetManager, appWidgetIds)
        context.healthWidgetEntryPoint().refreshScheduler().enqueueImmediate()
    }

    final override fun onDeleted(context: Context, appWidgetIds: IntArray) {
        super.onDeleted(context, appWidgetIds)
        reconcileInstances(context, deletedAppWidgetIds = appWidgetIds.toSet())
    }

    final override fun onDisabled(context: Context) {
        super.onDisabled(context)
        // Some launchers dispatch onDisabled before AppWidgetManager drops its final binding.
        // onDeleted handles the normal path immediately. This settled cleanup-only follow-up never
        // treats a lingering ID as permission to restart health reads or periodic work.
        reconcileInstances(
            context,
            settleDelayMillis = 1_000,
            scheduleIfWidgetsRemain = false,
        )
    }

    private fun reconcileInstances(
        context: Context,
        deletedAppWidgetIds: Set<Int> = emptySet(),
        settleDelayMillis: Long = 0,
        scheduleIfWidgetsRemain: Boolean = true,
    ) {
        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                if (settleDelayMillis > 0) delay(settleDelayMillis)
                runCatching {
                    context.healthWidgetEntryPoint()
                        .lifecycleCoordinator()
                        .onInstancesChanged(
                            deletedAppWidgetIds = deletedAppWidgetIds,
                            scheduleIfWidgetsRemain = scheduleIfWidgetsRemain,
                        )
                }
            } finally {
                pendingResult.finish()
            }
        }
    }
}

class HealthSummaryWidgetReceiver : BaseHealthWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = HealthSummaryGlanceWidget()
}

class ActivityWidgetReceiver : BaseHealthWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = ActivityGlanceWidget()
}

class HeartRangeWidgetReceiver : BaseHealthWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = HeartRangeGlanceWidget()
}

class SleepWidgetReceiver : BaseHealthWidgetReceiver() {
    override val glanceAppWidget: GlanceAppWidget = SleepGlanceWidget()
}

/**
 * Process-dead locale changes require a manifest receiver; clock/date changes also rerender age,
 * day, and timezone-sensitive content without reading Health Connect.
 */
class HealthWidgetLocaleChangeReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val localeChanged = intent.action == Intent.ACTION_LOCALE_CHANGED ||
            intent.action == ACTION_APPLICATION_LOCALE_CHANGED
        val clockChanged = intent.action == Intent.ACTION_TIME_CHANGED ||
            intent.action == Intent.ACTION_DATE_CHANGED ||
            intent.action == Intent.ACTION_TIMEZONE_CHANGED
        if (!localeChanged && !clockChanged) return

        val pendingResult = goAsync()
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            try {
                runCatching {
                    if (localeChanged) {
                        HealthWidgetLocaleRefresher.rerenderForCurrentLocale(context.applicationContext)
                    } else {
                        HealthWidgetLocaleRefresher.rerenderAll(context.applicationContext)
                    }
                }
            } finally {
                pendingResult.finish()
            }
        }
    }

    private companion object {
        // Literal keeps this receiver safe on API 28 while matching the API 33+ protected action.
        const val ACTION_APPLICATION_LOCALE_CHANGED =
            "android.intent.action.APPLICATION_LOCALE_CHANGED"
    }
}

object HealthWidgetLocaleRefresher {
    private val localeRefreshLock = Mutex()
    private var lastRenderedLocaleTags: String? = null

    suspend fun rerenderForCurrentLocale(context: Context) {
        localeRefreshLock.withLock {
            val localeTags = context.resources.configuration.locales.toLanguageTags()
            if (localeTags == lastRenderedLocaleTags) return@withLock
            rerenderAll(context)
            lastRenderedLocaleTags = localeTags
        }
    }

    suspend fun rerenderAll(context: Context) {
        HealthSummaryGlanceWidget().updateAll(context)
        ActivityGlanceWidget().updateAll(context)
        HeartRangeGlanceWidget().updateAll(context)
        SleepGlanceWidget().updateAll(context)
    }
}

@Singleton
class AndroidHealthWidgetInstanceRegistry @Inject constructor(
    @ApplicationContext private val context: Context,
) : HealthWidgetInstanceRegistry {
    private val appWidgetManager: AppWidgetManager
        get() = AppWidgetManager.getInstance(context)

    override fun installedKinds(): Set<HealthWidgetKind> = providerComponents()
        .mapNotNullTo(linkedSetOf()) { (kind, component) ->
            kind.takeIf { appWidgetManager.getAppWidgetIds(component).isNotEmpty() }
        }

    override fun installedWidgetCount(): Int = providerComponents().values.sumOf { component ->
        appWidgetManager.getAppWidgetIds(component).size
    }

    override fun hasWidgetsExcluding(appWidgetIds: Set<Int>): Boolean = providerComponents().values
        .asSequence()
        .flatMap { component -> appWidgetManager.getAppWidgetIds(component).asSequence() }
        .any { it !in appWidgetIds }

    override fun kindForAppWidgetId(appWidgetId: Int): HealthWidgetKind? {
        if (appWidgetId == AppWidgetManager.INVALID_APPWIDGET_ID) return null
        val providerClassName = appWidgetManager.getAppWidgetInfo(appWidgetId)
            ?.provider
            ?.className
            ?: return null
        return providerComponents().entries
            .firstOrNull { (_, component) -> component.className == providerClassName }
            ?.key
    }

    fun appWidgetIds(kind: HealthWidgetKind): IntArray =
        providerComponents()[kind]?.let(appWidgetManager::getAppWidgetIds) ?: intArrayOf()

    private fun providerComponents(): Map<HealthWidgetKind, ComponentName> = linkedMapOf(
        HealthWidgetKind.SUMMARY to ComponentName(context, HealthSummaryWidgetReceiver::class.java),
        HealthWidgetKind.ACTIVITY to ComponentName(context, ActivityWidgetReceiver::class.java),
        HealthWidgetKind.HEART_RANGE to ComponentName(context, HeartRangeWidgetReceiver::class.java),
        HealthWidgetKind.SLEEP to ComponentName(context, SleepWidgetReceiver::class.java),
    )
}

@Singleton
class GlanceHealthWidgetUpdater @Inject constructor(
    @ApplicationContext private val context: Context,
) : HealthWidgetUpdater {
    override suspend fun updateAll() {
        HealthWidgetLocaleRefresher.rerenderAll(context)
    }
}

@EntryPoint
@InstallIn(SingletonComponent::class)
interface HealthWidgetEntryPoint {
    fun snapshotStore(): HealthWidgetSnapshotStore
    fun refreshScheduler(): HealthWidgetRefreshScheduler
    fun lifecycleCoordinator(): HealthWidgetLifecycleCoordinator
}

private fun Context.healthWidgetEntryPoint(): HealthWidgetEntryPoint =
    EntryPointAccessors.fromApplication(
        applicationContext,
        HealthWidgetEntryPoint::class.java,
    )

/** Shared day/night providers sourced from the governing Geist token values. */
internal object HealthWidgetColors {
    val Background = ColorProvider(
        day = GeistLightColors.background100,
        night = GeistDarkColors.background100,
    )
    val Surface = ColorProvider(
        day = GeistLightColors.background200,
        night = GeistDarkColors.gray.c100,
    )
    val Primary = ColorProvider(day = GeistLightColors.primary, night = GeistDarkColors.primary)
    val Secondary = ColorProvider(day = GeistLightColors.secondary, night = GeistDarkColors.secondary)
    // Widget captions are small; c900 keeps them above 4.5:1 in both themes.
    val Muted = ColorProvider(day = GeistLightColors.gray.c900, night = GeistDarkColors.gray.c900)
    val Brand = ColorProvider(day = GeistLightColors.brandPrimary, night = GeistDarkColors.brandPrimary)
    val Activity = ColorProvider(day = GeistLightColors.amber.c900, night = GeistDarkColors.amber.c900)
    val Exercise = ColorProvider(day = GeistLightColors.green.c900, night = GeistDarkColors.green.c900)
    val Steps = ColorProvider(day = GeistLightColors.teal.c900, night = GeistDarkColors.teal.c900)
    val Heart = ColorProvider(day = GeistLightColors.red.c900, night = GeistDarkColors.red.c900)
    val Sleep = ColorProvider(day = GeistLightColors.purple.c900, night = GeistDarkColors.purple.c900)
}
