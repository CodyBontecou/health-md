package com.healthmd.widget

import android.appwidget.AppWidgetManager
import android.appwidget.AppWidgetProviderInfo
import android.content.ComponentName
import android.content.Context
import android.os.Build
import androidx.glance.appwidget.AppWidgetId
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.healthmd.widget.data.NoBackupHealthWidgetSnapshotStore
import com.healthmd.widget.glance.ActivityGlanceWidget
import com.healthmd.widget.glance.ActivityWidgetReceiver
import com.healthmd.widget.glance.HealthSummaryGlanceWidget
import com.healthmd.widget.glance.HealthSummaryWidgetReceiver
import com.healthmd.widget.glance.HeartRangeGlanceWidget
import com.healthmd.widget.glance.HeartRangeWidgetReceiver
import com.healthmd.widget.glance.HealthWidgetEntryPoint
import com.healthmd.widget.glance.SleepGlanceWidget
import com.healthmd.widget.glance.SleepWidgetReceiver
import com.healthmd.widget.model.HealthWidgetKind
import com.healthmd.widget.model.WidgetRefreshOutcome
import dagger.hilt.android.EntryPointAccessors
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File

/** Opt-in physical-launcher smoke coverage; skips when the device has no Health.md widgets. */
@RunWith(AndroidJUnit4::class)
class HealthWidgetDeviceSmokeTest {
    @Test
    fun installedWidgetsRenderAndRemainExcludedFromKeyguard() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val manager = AppWidgetManager.getInstance(context)
        val providers = listOf(
            Provider(HealthSummaryWidgetReceiver::class.java, HealthSummaryGlanceWidget()),
            Provider(ActivityWidgetReceiver::class.java, ActivityGlanceWidget()),
            Provider(HeartRangeWidgetReceiver::class.java, HeartRangeGlanceWidget()),
            Provider(SleepWidgetReceiver::class.java, SleepGlanceWidget()),
        )
        val installed = providers.flatMap { provider ->
            manager.getAppWidgetIds(ComponentName(context, provider.receiver))
                .map { appWidgetId -> provider to appWidgetId }
        }
        assumeTrue("Add at least one Health.md widget before this physical smoke test.", installed.isNotEmpty())
        val snapshotFile = File(
            context.noBackupFilesDir,
            "health-widgets/health-widget-snapshot-v1.json",
        )
        if (snapshotFile.isFile) {
            val snapshot = NoBackupHealthWidgetSnapshotStore(context).load()
            assertNotNull(snapshot)
            InstrumentationRegistry.getArguments().getString("expectedWidgetSteps")
                ?.toIntOrNull()
                ?.let { expectedSteps ->
                    assertEquals(expectedSteps, snapshot?.days?.lastOrNull()?.steps)
                }
        }

        installed.forEach { (provider, appWidgetId) ->
            provider.widget.update(context, AppWidgetId(appWidgetId))
        }
        // Keep the instrumentation process alive long enough for the launcher host to apply
        // RemoteViews and transfer generated bitmaps.
        delay(2_000)

        installed.forEach { (_, appWidgetId) ->
            val info = requireNotNull(manager.getAppWidgetInfo(appWidgetId))
            assertEquals(context.packageName, info.provider.packageName)
            assertTrue(info.minWidth > 0)
            assertTrue(info.minHeight > 0)
            if (Build.VERSION.SDK_INT >= 36) {
                assertTrue(
                    info.widgetCategory and AppWidgetProviderInfo.WIDGET_CATEGORY_HOME_SCREEN != 0,
                )
                assertTrue(
                    info.widgetCategory and AppWidgetProviderInfo.WIDGET_CATEGORY_NOT_KEYGUARD != 0,
                )
                assertTrue(
                    info.widgetCategory and AppWidgetProviderInfo.WIDGET_CATEGORY_KEYGUARD == 0,
                )
            }
        }
    }

    @Test
    fun finalInstanceCleanupDeletesThePrivateSnapshot() = runBlocking {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val manager = AppWidgetManager.getInstance(context)
        val receivers = listOf(
            HealthSummaryWidgetReceiver::class.java,
            ActivityWidgetReceiver::class.java,
            HeartRangeWidgetReceiver::class.java,
            SleepWidgetReceiver::class.java,
        )
        assertTrue(receivers.all { receiver ->
            manager.getAppWidgetIds(ComponentName(context, receiver)).isEmpty()
        })
        val entryPoint = EntryPointAccessors.fromApplication(
            context,
            HealthWidgetEntryPoint::class.java,
        )

        entryPoint.lifecycleCoordinator().onInstancesChanged()

        val snapshotFile = File(
            context.noBackupFilesDir,
            "health-widgets/health-widget-snapshot-v1.json",
        )
        assertFalse(snapshotFile.exists())
        assertNull(entryPoint.snapshotStore().load())
    }

    @Test
    fun backgroundPulseRedactsARevokedSleepPermission() = runBlocking {
        val arguments = InstrumentationRegistry.getArguments()
        assumeTrue(arguments.getString("verifyRevokedSleep") == "true")
        val context = ApplicationProvider.getApplicationContext<Context>()
        val entryPoint = EntryPointAccessors.fromApplication(
            context,
            HealthWidgetEntryPoint::class.java,
        )
        val store = entryPoint.snapshotStore()
        val before = requireNotNull(store.load())
        assumeTrue(before.days.any { it.sleepDurationMinutes != null })
        assumeTrue(before.days.any { it.steps != null })

        entryPoint.refreshScheduler().enqueueImmediate()
        var redacted = before
        for (attempt in 0 until 20) {
            delay(250)
            redacted = store.load() ?: redacted
            if (redacted.lastAttemptOutcome == WidgetRefreshOutcome.BACKGROUND_PERMISSION_REQUIRED) {
                break
            }
        }

        // Keep the instrumentation process alive while Glance transfers updated RemoteViews.
        delay(2_000)

        assertEquals(
            WidgetRefreshOutcome.BACKGROUND_PERMISSION_REQUIRED,
            redacted.lastAttemptOutcome,
        )
        assertTrue(HealthWidgetKind.SLEEP in redacted.permissionRequiredKinds)
        assertTrue(redacted.days.all { day ->
            day.sleepDurationMinutes == null &&
                day.sleepStartEpochMillis == null &&
                day.sleepEndEpochMillis == null
        })
        assertTrue(redacted.days.any { it.steps != null })
        assertEquals(before.capturedAtEpochMillis, redacted.capturedAtEpochMillis)
    }

    private data class Provider(
        val receiver: Class<*>,
        val widget: androidx.glance.appwidget.GlanceAppWidget,
    )
}
