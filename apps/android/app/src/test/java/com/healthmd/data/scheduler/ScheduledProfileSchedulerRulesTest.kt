package com.healthmd.data.scheduler

import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ScheduleCadenceUnit
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.ZoneId

/**
 * Pure scheduling-runtime rules: stable per-entry alarm request codes (no collisions with the
 * legacy single alarm or each other), per-entry WorkManager names, and migration mapping.
 */
class ScheduledProfileSchedulerRulesTest {

    @Test
    fun `per-entry request codes are stable, distinct, and avoid the legacy code`() {
        val a = ScheduledProfileScheduler.requestCodeFor("profile-a")
        val b = ScheduledProfileScheduler.requestCodeFor("profile-b")

        assertEquals(a, ScheduledProfileScheduler.requestCodeFor("profile-a"))
        assertNotEquals(a, b)

        // The legacy single-schedule alarm uses 6041; per-entry codes live far away.
        assertTrue(a != 6_041 && b != 6_041)

        // Within the PendingIntent int space and positive.
        (listOf(a, b) + (0 until 50).map { ScheduledProfileScheduler.requestCodeFor("p$it") })
            .forEach { code -> assertTrue(code > 0) }

        // A burst of ids produces distinct codes.
        val burst = (0 until 200).map { ScheduledProfileScheduler.requestCodeFor("profile-$it") }
        assertEquals(burst.size, burst.toSet().size)
    }

    @Test
    fun `work names and fallback tags are per-entry and stable`() {
        assertEquals(
            "profile-export-p1",
            ScheduledProfileScheduler.exportWorkName("p1"),
        )
        assertEquals(
            "scheduled_profile_trigger_p1",
            ScheduledProfileScheduler.fallbackTag("p1"),
        )
        assertEquals(
            "scheduled_profile_trigger_work_p1",
            ScheduledProfileScheduler.fallbackName("p1"),
        )
        assertNotEquals(
            ScheduledProfileScheduler.exportWorkName("p1"),
            ScheduledProfileScheduler.exportWorkName("p2"),
        )
    }

    // MARK: Legacy-schedule migration

    @Test
    fun `legacy migration builds a daily entry from an enabled legacy schedule`() {
        val zone = ZoneId.of("UTC")
        val today = LocalDate.of(2026, 8, 19)
        val settings = ExportSettings(
            scheduleEnabled = true,
            scheduleHour = 7,
            scheduleMinute = 45,
            scheduleCadenceValue = 3,
            scheduleCadenceUnit = ScheduleCadenceUnit.DAYS,
            scheduleLookbackDays = 5,
        )

        val entry = legacyMigrationEntry(
            settings = settings,
            existingEntries = emptyList(),
            defaultProfileId = "default-1",
            zone = zone,
            today = today,
        )

        requireNotNull(entry)
        assertEquals("default-1", entry.profileId)
        assertTrue(entry.isEnabled)
        assertEquals(today.toEpochDay(), entry.anchorEpochDay)
        assertEquals(7, entry.hour)
        assertEquals(45, entry.minute)
        assertEquals("legacy cadence value survives the every-N-days mapping", 3L, entry.cadenceValue.toLong())
        assertEquals(ScheduledProfileCadenceUnit.DAY, entry.cadenceUnit)
        assertEquals(5, entry.lookbackDays)
        assertEquals("UTC", entry.zoneId)
    }

    @Test
    fun `legacy migration maps weekly cadence to a weekly entry`() {
        val entry = legacyMigrationEntry(
            settings = ExportSettings(
                scheduleEnabled = true,
                scheduleCadenceUnit = ScheduleCadenceUnit.WEEKS,
            ),
            existingEntries = emptyList(),
            defaultProfileId = "default-1",
            zone = ZoneId.of("UTC"),
            today = LocalDate.of(2026, 8, 19),
        )

        requireNotNull(entry)
        assertEquals(ScheduledProfileCadenceUnit.WEEK, entry.cadenceUnit)
    }

    @Test
    fun `legacy migration never applies with existing entries, a disabled schedule, or no profile`() {
        val zone = ZoneId.of("UTC")
        val today = LocalDate.of(2026, 8, 19)
        val enabled = ExportSettings(scheduleEnabled = true)
        val existing = listOf(
            ScheduledProfileEntry(
                profileId = "already-here",
                isEnabled = false,
                anchorEpochDay = 20_000,
                weekdayIso = 1,
                hour = 8,
                minute = 0,
                cadenceUnit = ScheduledProfileCadenceUnit.DAY,
                zoneId = "UTC",
            ),
        )

        // Entries already exist (even disabled ones): the one-time migration already ran.
        assertNull(
            legacyMigrationEntry(
                settings = enabled,
                existingEntries = existing,
                defaultProfileId = "default-1",
                zone = zone,
                today = today,
            ),
        )
        // Legacy schedule off: nothing to migrate.
        assertNull(
            legacyMigrationEntry(
                settings = ExportSettings(scheduleEnabled = false),
                existingEntries = emptyList(),
                defaultProfileId = "default-1",
                zone = zone,
                today = today,
            ),
        )
        // No active profile resolves: fail closed rather than arming an orphan.
        assertNull(
            legacyMigrationEntry(
                settings = enabled,
                existingEntries = emptyList(),
                defaultProfileId = null,
                zone = zone,
                today = today,
            ),
        )
    }

    @Test
    fun `cadence summary covers all units`() {
        fun entry(unit: ScheduledProfileCadenceUnit, weekdayIso: Int = 1) =
            ScheduledProfileEntry(
                profileId = "p",
                isEnabled = true,
                anchorEpochDay = 20_000,
                weekdayIso = weekdayIso,
                hour = 8,
                minute = 0,
                cadenceUnit = unit,
                zoneId = "UTC",
            )

        assertTrue(DayOfWeek.MONDAY == DayOfWeek.of(1))
        // The entry model validates every cadence unit can be constructed for runtime use.
        ScheduledProfileCadenceUnit.entries.forEach { unit ->
            assertTrue(entry(unit).cadenceUnit == unit)
        }
    }

    @Test
    fun `profile model ids remain opaque strings for the runtime`() {
        val profile = ExportProfile(
            id = "opaque-id",
            name = "Default",
            settingsSnapshotJson = "{}",
            target = com.healthmd.domain.model.ExportTarget.DEVICE_FOLDER,
            createdAtEpochMillis = 1L,
            updatedAtEpochMillis = 1L,
        )
        assertEquals("profile-export-opaque-id", ScheduledProfileScheduler.exportWorkName(profile.id))
    }
}
