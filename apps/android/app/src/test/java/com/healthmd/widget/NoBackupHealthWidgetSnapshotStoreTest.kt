package com.healthmd.widget

import com.google.common.truth.Truth.assertThat
import com.healthmd.widget.data.NoBackupHealthWidgetSnapshotStore
import com.healthmd.widget.model.HealthWidgetDay
import com.healthmd.widget.model.HealthWidgetSnapshot
import com.healthmd.widget.model.WidgetRefreshOutcome
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import org.junit.Test
import java.io.File
import java.nio.file.Files
import java.time.Instant
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.milliseconds

class NoBackupHealthWidgetSnapshotStoreTest {
    @Test
    fun `round trips and atomically replaces a valid snapshot`() = runTest {
        val root = Files.createTempDirectory("widget-store").toFile()
        try {
            val store = store(root)
            val first = snapshot(steps = 1_234)
            val second = snapshot(steps = 9_876)

            store.save(first)
            assertThat(store.load()).isEqualTo(first)

            store.save(second)
            assertThat(store.load()).isEqualTo(second)
            assertThat(root.listFiles().orEmpty().map(File::getName))
                .containsExactly("health-widget-snapshot-v1.json")
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun `corrupt and unsupported snapshots fail closed`() = runTest {
        val root = Files.createTempDirectory("widget-store").toFile()
        try {
            val file = File(root, "health-widget-snapshot-v1.json")
            file.writeText("not-json")
            assertThat(store(root).load()).isNull()

            file.writeText(
                """{"schemaVersion":99,"capturedZoneId":"UTC","days":[],"lastAttemptOutcome":"NEVER"}"""
            )
            assertThat(store(root).load()).isNull()
        } finally {
            root.deleteRecursively()
        }
    }

    @Test
    fun `delete removes the complete no-backup widget directory`() = runTest {
        val root = Files.createTempDirectory("widget-store").toFile()
        val store = store(root)
        store.save(snapshot(steps = 500))

        store.delete()

        assertThat(root.exists()).isFalse()
    }

    @Test
    fun `freshness and display cutoff use successful capture time`() {
        val capturedAt = Instant.parse("2026-08-02T12:00:00Z")
        val snapshot = snapshot(steps = 500, capturedAt = capturedAt)

        assertThat(snapshot.isFresh(capturedAt.plusMillis(4.hours.inWholeMilliseconds))).isTrue()
        assertThat(snapshot.isFresh(capturedAt.plusMillis(4.hours.inWholeMilliseconds + 1))).isFalse()
        assertThat(snapshot.canDisplayMeasurements(capturedAt.plusMillis(24.hours.inWholeMilliseconds))).isTrue()
        assertThat(snapshot.canDisplayMeasurements(capturedAt.plusMillis(24.hours.inWholeMilliseconds + 1))).isFalse()
        assertThat(snapshot.age(capturedAt.minusMillis(1))).isNull()
        assertThat(snapshot.age(capturedAt.plusMillis(1))).isEqualTo(1.milliseconds)
    }

    private fun store(root: File) = NoBackupHealthWidgetSnapshotStore(
        root = root,
        ioDispatcher = Dispatchers.IO,
        json = Json {
            encodeDefaults = true
            ignoreUnknownKeys = true
            explicitNulls = false
        },
    )

    private fun snapshot(
        steps: Int,
        capturedAt: Instant = Instant.parse("2026-08-02T12:00:00Z"),
    ) = HealthWidgetSnapshot(
        capturedAtEpochMillis = capturedAt.toEpochMilli(),
        capturedZoneId = "UTC",
        days = listOf(HealthWidgetDay(localDate = "2026-08-02", steps = steps)),
        lastAttemptAtEpochMillis = capturedAt.toEpochMilli(),
        lastAttemptOutcome = WidgetRefreshOutcome.SUCCESS,
    )
}
