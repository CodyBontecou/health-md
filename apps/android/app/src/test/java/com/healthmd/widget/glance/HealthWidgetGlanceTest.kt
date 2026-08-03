package com.healthmd.widget.glance

import android.content.Context
import android.content.res.Configuration
import androidx.glance.testing.unit.assertHasStartActivityClickAction
import androidx.glance.appwidget.testing.unit.runGlanceAppWidgetUnitTest
import androidx.glance.testing.unit.hasTestTag
import androidx.glance.testing.unit.hasText
import androidx.test.core.app.ApplicationProvider
import com.healthmd.presentation.MainActivity
import com.healthmd.widget.model.HealthWidgetDay
import com.healthmd.widget.model.HealthWidgetKind
import com.healthmd.widget.model.HealthWidgetSnapshot
import com.healthmd.widget.model.WidgetRefreshOutcome
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config
import java.time.Duration
import java.time.Instant
import java.time.ZoneId

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class HealthWidgetGlanceTest {
    private val now = Instant.parse("2026-08-02T12:00:00Z")
    private val snapshot = HealthWidgetSnapshot(
        capturedAtEpochMillis = now.toEpochMilli(),
        capturedZoneId = "UTC",
        days = listOf(
            HealthWidgetDay(
                localDate = "2026-08-02",
                steps = 8_742,
                activeCaloriesKilocalories = 421.0,
                exerciseMinutes = 37.0,
                sleepDurationMinutes = 450.0,
                restingHeartRateBpm = 58.0,
                averageHeartRateBpm = 72.0,
                minimumHeartRateBpm = 47.0,
                maximumHeartRateBpm = 151.0,
                hrvRmssdMillis = 46.0,
            )
        ),
        lastAttemptAtEpochMillis = now.toEpochMilli(),
        lastAttemptOutcome = WidgetRefreshOutcome.SUCCESS,
    )

    @Test
    fun `compact summary renders current steps and opens the app`() = runGlanceAppWidgetUnitTest {
        setContext(ApplicationProvider.getApplicationContext())
        setAppWidgetSize(HealthWidgetSizes.Compact)
        provideComposable {
            HealthWidgetContent(
                kind = HealthWidgetKind.SUMMARY,
                snapshot = snapshot,
                now = now,
                zoneId = ZoneId.of("UTC"),
                size = HealthWidgetSizes.Compact,
                artwork = HealthWidgetArtwork(activityRings = null, heartRange = null),
            )
        }

        onNode(hasText("8,742")).assertExists()
        onNode(hasTestTag("widget-root"))
            .assertHasStartActivityClickAction<MainActivity>()
    }

    @Test
    fun `large font compact summary prioritizes steps and stale status without clipping extras`() =
        runGlanceAppWidgetUnitTest {
            setContext(contextWithFontScale(1.3f))
            setAppWidgetSize(HealthWidgetSizes.Compact)
            provideComposable {
                HealthWidgetContent(
                    kind = HealthWidgetKind.SUMMARY,
                    snapshot = snapshot,
                    now = now.plus(Duration.ofHours(5)),
                    zoneId = ZoneId.of("UTC"),
                    size = HealthWidgetSizes.Compact,
                    artwork = HealthWidgetArtwork(activityRings = null, heartRange = null),
                )
            }

            onNode(hasText("8.7K")).assertExists()
            onNode(hasText("Sleep")).assertDoesNotExist()
            onNode(hasText("Updated 5 hours ago")).assertExists()
        }

    @Test
    fun `large font compact activity switches to three textual metric lines`() =
        runGlanceAppWidgetUnitTest {
            setContext(contextWithFontScale(1.3f))
            setAppWidgetSize(HealthWidgetSizes.Compact)
            provideComposable {
                HealthWidgetContent(
                    kind = HealthWidgetKind.ACTIVITY,
                    snapshot = snapshot,
                    now = now,
                    zoneId = ZoneId.of("UTC"),
                    size = HealthWidgetSizes.Compact,
                    artwork = HealthWidgetArtwork(activityRings = null, heartRange = null),
                )
            }

            onNode(hasText("Move")).assertExists()
            onNode(hasText("Exercise")).assertExists()
            onNode(hasText("Steps")).assertExists()
            onNode(hasText("8.7K")).assertExists()
        }

    @Test
    fun `medium summary keeps activity sleep and heart sections`() = runGlanceAppWidgetUnitTest {
        setContext(ApplicationProvider.getApplicationContext())
        setAppWidgetSize(HealthWidgetSizes.Medium)
        provideComposable {
            HealthWidgetContent(
                kind = HealthWidgetKind.SUMMARY,
                snapshot = snapshot,
                now = now,
                zoneId = ZoneId.of("UTC"),
                size = HealthWidgetSizes.Medium,
                artwork = HealthWidgetArtwork(activityRings = null, heartRange = null),
            )
        }

        onAllNodes(hasText("Steps")).assertCountEquals(2)
        onNode(hasText("7-day sleep")).assertExists()
        onNode(hasText("Heart Range")).assertExists()
    }

    @Test
    fun `wide activity layout keeps textual labels beside ring artwork`() = runGlanceAppWidgetUnitTest {
        setContext(ApplicationProvider.getApplicationContext())
        setAppWidgetSize(HealthWidgetSizes.Wide)
        provideComposable {
            HealthWidgetContent(
                kind = HealthWidgetKind.ACTIVITY,
                snapshot = snapshot,
                now = now,
                zoneId = ZoneId.of("UTC"),
                size = HealthWidgetSizes.Wide,
                artwork = HealthWidgetArtwork(activityRings = null, heartRange = null),
            )
        }

        onNode(hasText("Move")).assertExists()
        onNode(hasText("Exercise")).assertExists()
        onAllNodes(hasText("Steps")).assertCountEquals(2)
    }

    @Test
    fun `tall sleep layout renders summary and timing labels`() = runGlanceAppWidgetUnitTest {
        setContext(ApplicationProvider.getApplicationContext())
        setAppWidgetSize(HealthWidgetSizes.Large)
        provideComposable {
            HealthWidgetContent(
                kind = HealthWidgetKind.SLEEP,
                snapshot = snapshot,
                now = now,
                zoneId = ZoneId.of("UTC"),
                size = HealthWidgetSizes.Large,
                artwork = HealthWidgetArtwork(activityRings = null, heartRange = null),
            )
        }

        onNode(hasText("Last night")).assertExists()
        onNode(hasText("7-day average")).assertExists()
        onNode(hasText("Bedtime")).assertExists()
        onNode(hasText("Wake")).assertExists()
    }

    @Test
    fun `wide heart layout keeps minimum and maximum word order resource controlled`() = runGlanceAppWidgetUnitTest {
        setContext(ApplicationProvider.getApplicationContext())
        setAppWidgetSize(HealthWidgetSizes.Wide)
        provideComposable {
            HealthWidgetContent(
                kind = HealthWidgetKind.HEART_RANGE,
                snapshot = snapshot,
                now = now,
                zoneId = ZoneId.of("UTC"),
                size = HealthWidgetSizes.Wide,
                artwork = HealthWidgetArtwork(activityRings = null, heartRange = null),
            )
        }

        onNode(hasText("Min 47")).assertExists()
        onNode(hasText("Max 151")).assertExists()
    }

    @Test
    fun `large heart layout renders RMSSD value`() = runGlanceAppWidgetUnitTest {
        setContext(ApplicationProvider.getApplicationContext())
        setAppWidgetSize(HealthWidgetSizes.Large)
        provideComposable {
            HealthWidgetContent(
                kind = HealthWidgetKind.HEART_RANGE,
                snapshot = snapshot,
                now = now,
                zoneId = ZoneId.of("UTC"),
                size = HealthWidgetSizes.Large,
                artwork = HealthWidgetArtwork(activityRings = null, heartRange = null),
            )
        }

        onNode(hasText("46 ms")).assertExists()
    }

    @Test
    fun `stale measurements retain values and show their age`() = runGlanceAppWidgetUnitTest {
        setContext(ApplicationProvider.getApplicationContext())
        setAppWidgetSize(HealthWidgetSizes.Compact)
        provideComposable {
            HealthWidgetContent(
                kind = HealthWidgetKind.SUMMARY,
                snapshot = snapshot,
                now = now.plus(Duration.ofHours(5)),
                zoneId = ZoneId.of("UTC"),
                size = HealthWidgetSizes.Compact,
                artwork = HealthWidgetArtwork(activityRings = null, heartRange = null),
            )
        }

        onNode(hasText("8,742")).assertExists()
        onNode(hasText("Sleep")).assertDoesNotExist()
        onNode(hasText("Updated 5 hours ago")).assertExists()
    }

    @Test
    fun `measurements older than cutoff are hidden`() = runGlanceAppWidgetUnitTest {
        setContext(ApplicationProvider.getApplicationContext())
        setAppWidgetSize(HealthWidgetSizes.Compact)
        provideComposable {
            HealthWidgetContent(
                kind = HealthWidgetKind.SUMMARY,
                snapshot = snapshot,
                now = now.plus(Duration.ofHours(25)),
                zoneId = ZoneId.of("UTC"),
                size = HealthWidgetSizes.Compact,
                artwork = HealthWidgetArtwork(activityRings = null, heartRange = null),
            )
        }

        onNode(hasText("8,742")).assertDoesNotExist()
        onNode(hasText("Open Health.md to refresh this widget.")).assertExists()
    }

    @Test
    fun `revoked kind hides cached measurements`() = runGlanceAppWidgetUnitTest {
        setContext(ApplicationProvider.getApplicationContext())
        setAppWidgetSize(HealthWidgetSizes.Wide)
        provideComposable {
            HealthWidgetContent(
                kind = HealthWidgetKind.SLEEP,
                snapshot = snapshot.copy(permissionRequiredKinds = setOf(HealthWidgetKind.SLEEP)),
                now = now,
                zoneId = ZoneId.of("UTC"),
                size = HealthWidgetSizes.Wide,
                artwork = HealthWidgetArtwork(activityRings = null, heartRange = null),
            )
        }

        onNode(hasText("Open Health.md to allow Health Connect access.")).assertExists()
        onNode(hasText("7.5 hr")).assertDoesNotExist()
    }

    @Test
    fun `before-first-unlock state contains no measurements`() = runGlanceAppWidgetUnitTest {
        setContext(ApplicationProvider.getApplicationContext())
        setAppWidgetSize(HealthWidgetSizes.Wide)
        provideComposable {
            HealthWidgetContent(
                kind = HealthWidgetKind.HEART_RANGE,
                snapshot = HealthWidgetSnapshot(
                    lastAttemptAtEpochMillis = now.toEpochMilli(),
                    lastAttemptOutcome = WidgetRefreshOutcome.BEFORE_FIRST_UNLOCK,
                ),
                now = now,
                zoneId = ZoneId.of("UTC"),
                size = HealthWidgetSizes.Wide,
                artwork = HealthWidgetArtwork(activityRings = null, heartRange = null),
            )
        }

        onNode(hasText("Unlock your phone to refresh Health.md.")).assertExists()
        onNode(hasText("72 bpm")).assertDoesNotExist()
    }

    private fun contextWithFontScale(fontScale: Float): Context {
        val base = ApplicationProvider.getApplicationContext<Context>()
        val configuration = Configuration(base.resources.configuration).apply {
            this.fontScale = fontScale
        }
        return base.createConfigurationContext(configuration)
    }

    @Test
    fun `missing snapshot renders loading state`() = runGlanceAppWidgetUnitTest {
        setContext(ApplicationProvider.getApplicationContext())
        setAppWidgetSize(HealthWidgetSizes.Wide)
        provideComposable {
            HealthWidgetContent(
                kind = HealthWidgetKind.HEART_RANGE,
                snapshot = null,
                now = now,
                zoneId = ZoneId.of("UTC"),
                size = HealthWidgetSizes.Wide,
                artwork = HealthWidgetArtwork(activityRings = null, heartRange = null),
            )
        }

        onNode(hasText("Loading health data…")).assertExists()
    }
}
