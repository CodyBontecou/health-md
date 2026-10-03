package com.healthmd.data.scheduler

import com.healthmd.domain.model.ExportTarget
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.time.DayOfWeek
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.LocalTime
import java.time.ZoneId
import java.time.ZonedDateTime

/** Occurrence math for per-profile scheduled entries, mirroring the iOS evaluator semantics. */
class ScheduledProfileOccurrenceMathTest {

    private val zone = ZoneId.of("UTC")

    private fun millisOf(date: LocalDate, time: LocalTime = LocalTime.of(8, 0)): Long =
        ZonedDateTime.of(date, time, zone).toInstant().toEpochMilli()

    private fun entry(
        enabled: Boolean = true,
        hour: Int = 8,
        minute: Int = 0,
        cadenceUnit: ScheduledProfileCadenceUnit = ScheduledProfileCadenceUnit.DAY,
        cadenceValue: Int = 1,
        weekdayIso: Int = 1,
        lookbackDays: Int = 1,
        anchorEpochDay: Long = LocalDate.of(2026, 7, 1).toEpochDay(),
        lastSuccessEpochMillis: Long? = null,
        todayRefreshEnabled: Boolean = false,
        todayRefreshIntervalHours: Int = ScheduledProfileEntry.DEFAULT_TODAY_REFRESH_INTERVAL_HOURS,
        lastRefreshSuccessEpochMillis: Long? = null,
    ) = ScheduledProfileEntry(
        profileId = "profile-1",
        isEnabled = enabled,
        anchorEpochDay = anchorEpochDay,
        weekdayIso = weekdayIso,
        hour = hour,
        minute = minute,
        cadenceValue = cadenceValue,
        cadenceUnit = cadenceUnit,
        lookbackDays = lookbackDays,
        todayRefreshEnabled = todayRefreshEnabled,
        todayRefreshIntervalHours = todayRefreshIntervalHours,
        zoneId = zone.id,
        lastSuccessEpochMillis = lastSuccessEpochMillis,
        lastRefreshSuccessEpochMillis = lastRefreshSuccessEpochMillis,
    )

    @Test
    fun `first daily boundary exports its configured completed-day window`() {
        // Monday 2026-08-10 12:00; boundary Monday 08:00 passed, no prior success.
        val now = millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(12, 0))
        val due = ScheduledProfileOccurrenceMath.dueOccurrence(entry(), now)

        assertNotNull(due)
        assertEquals(listOf(LocalDate.of(2026, 8, 9)), due!!.exportDates)
        assertEquals(millisOf(LocalDate.of(2026, 8, 10)), due.fireAtMillis)
    }

    @Test
    fun `daily occurrence reexports all fourteen days after yesterday succeeded`() {
        val today = LocalDate.of(2026, 8, 10)
        val configured = entry(lookbackDays = 14, lastSuccessEpochMillis = millisOf(today.minusDays(1)))
        assertNull(ScheduledProfileOccurrenceMath.dueOccurrence(configured, millisOf(today, LocalTime.of(7, 0))))

        val due = ScheduledProfileOccurrenceMath.dueOccurrence(configured, millisOf(today))
        assertNotNull(due)
        assertEquals((14L downTo 1L).map(today::minusDays), due!!.exportDates)
        val succeeded = configured.copy(lastSuccessEpochMillis = due.fireAtMillis)
        assertNull(ScheduledProfileOccurrenceMath.dueOccurrence(succeeded, millisOf(today, LocalTime.NOON)))
        assertEquals(
            (14L downTo 1L).map(today.plusDays(1)::minusDays),
            ScheduledProfileOccurrenceMath.dueOccurrence(succeeded, millisOf(today.plusDays(1)))?.exportDates,
        )
    }

    @Test
    fun `today refresh does not replace the rolling lookback after a previous success`() {
        val today = LocalDate.of(2026, 8, 10)
        val configured = entry(
            lookbackDays = 14,
            lastSuccessEpochMillis = millisOf(today.minusDays(1)),
            todayRefreshEnabled = true,
        )
        val due = ScheduledProfileOccurrenceMath.dueOccurrence(configured, millisOf(today))
        assertEquals((14L downTo 0L).map(today::minusDays), due?.exportDates)
        assertEquals(millisOf(today), due?.refreshSlotMillis)

        val succeeded = configured.copy(
            lastSuccessEpochMillis = millisOf(today),
            lastRefreshSuccessEpochMillis = millisOf(today),
        )
        val refresh = ScheduledProfileOccurrenceMath.dueOccurrence(succeeded, millisOf(today, LocalTime.of(11, 0)))
        assertEquals(listOf(today), refresh?.exportDates)
    }

    @Test
    fun `delayed weekly occurrence keeps the full window ending before its fire day`() {
        val monday = LocalDate.of(2026, 8, 10)
        val configured = entry(
            cadenceUnit = ScheduledProfileCadenceUnit.WEEK,
            lookbackDays = 14,
            lastSuccessEpochMillis = millisOf(monday.minusWeeks(1)),
        )
        val now = millisOf(monday.plusDays(2))
        val due = ScheduledProfileOccurrenceMath.dueOccurrence(configured, now)
        assertNotNull(due)
        assertEquals(millisOf(monday), due!!.fireAtMillis)
        assertEquals((14L downTo 1L).map(monday::minusDays), due.exportDates)
        assertNull(ScheduledProfileOccurrenceMath.dueOccurrence(configured.copy(lastSuccessEpochMillis = due.fireAtMillis), now))
    }

    @Test
    fun `multi-week and multi-month cadences do not resend lookback between boundaries`() {
        val monday = LocalDate.of(2026, 8, 10)
        val biweekly = entry(
            cadenceUnit = ScheduledProfileCadenceUnit.WEEK,
            cadenceValue = 2,
            anchorEpochDay = monday.toEpochDay(),
            lookbackDays = 14,
            lastSuccessEpochMillis = millisOf(monday),
        )
        assertNull(ScheduledProfileOccurrenceMath.dueOccurrence(biweekly, millisOf(monday.plusWeeks(1))))
        assertEquals(
            millisOf(monday.plusWeeks(2)),
            ScheduledProfileOccurrenceMath.nextOccurrence(biweekly, millisOf(monday.plusWeeks(1)))?.toEpochMilli(),
        )
        assertEquals(14, ScheduledProfileOccurrenceMath.dueOccurrence(biweekly, millisOf(monday.plusWeeks(2)))?.exportDates?.size)

        val january31 = LocalDate.of(2026, 1, 31)
        val bimonthly = entry(
            cadenceUnit = ScheduledProfileCadenceUnit.MONTH,
            cadenceValue = 2,
            anchorEpochDay = january31.toEpochDay(),
            lookbackDays = 14,
            lastSuccessEpochMillis = millisOf(january31),
        )
        assertNull(ScheduledProfileOccurrenceMath.dueOccurrence(bimonthly, millisOf(LocalDate.of(2026, 2, 28))))
        assertEquals(
            millisOf(LocalDate.of(2026, 3, 31)),
            ScheduledProfileOccurrenceMath.nextOccurrence(bimonthly, millisOf(LocalDate.of(2026, 2, 28)))?.toEpochMilli(),
        )
        assertEquals(14, ScheduledProfileOccurrenceMath.dueOccurrence(bimonthly, millisOf(LocalDate.of(2026, 3, 31)))?.exportDates?.size)
    }

    @Test
    fun `lookback preserves local calendar dates across daylight saving time`() {
        val localZone = ZoneId.of("America/New_York")
        val today = LocalDate.of(2026, 3, 10)
        fun localMillis(day: LocalDate) = day.atTime(8, 0).atZone(localZone).toInstant().toEpochMilli()
        val configured = entry(
            anchorEpochDay = LocalDate.of(2026, 2, 1).toEpochDay(),
            lookbackDays = 14,
            lastSuccessEpochMillis = localMillis(today.minusDays(1)),
        ).copy(zoneId = localZone.id)
        val due = ScheduledProfileOccurrenceMath.dueOccurrence(configured, localMillis(today))
        assertEquals((14L downTo 1L).map(today::minusDays), due?.exportDates)
    }

    @Test
    fun `frozen cancellation residual is prioritized over a newer occurrence window`() {
        val now = millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(12, 0))
        val residualDate = LocalDate.of(2026, 8, 2)
        val residual = ScheduledProfilePendingExport(
            id = "residual-1",
            ownerEpochDays = listOf(residualDate.toEpochDay()),
            fireAtMillis = millisOf(LocalDate.of(2026, 8, 3)),
            settingsSnapshotJson = "frozen-settings",
            target = ExportTarget.DEVICE_FOLDER,
            profileName = "Morning",
        )

        val due = ScheduledProfileOccurrenceMath.dueOccurrence(
            entry(lookbackDays = 14, lastSuccessEpochMillis = millisOf(LocalDate.of(2026, 8, 9))).copy(
                pendingExports = listOf(residual),
            ),
            now,
        )

        assertNotNull(due)
        assertEquals(listOf(residualDate), due!!.exportDates)
        assertEquals(residual.fireAtMillis, due.fireAtMillis)
        assertEquals(residual, due.pendingExport)
    }

    @Test
    fun `boundary already covered by the last success is not due`() {
        val now = millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(12, 0))
        // Success at today's 08:00 boundary covered yesterday already.
        val due = ScheduledProfileOccurrenceMath.dueOccurrence(
            entry(lastSuccessEpochMillis = millisOf(LocalDate.of(2026, 8, 10))),
            now,
        )
        assertNull(due)
    }

    @Test
    fun `weekly entry fires only on its weekday and covers the full trailing week`() {
        // 2026-08-10 is Monday. Weekly Monday entry: boundary passed.
        val now = millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(9, 0))
        val mondayEntry = entry(
            cadenceUnit = ScheduledProfileCadenceUnit.WEEK,
            weekdayIso = 1,
            lookbackDays = 7,
        )
        val due = ScheduledProfileOccurrenceMath.dueOccurrence(mondayEntry, now)
        assertNotNull(due)
        assertEquals(7, due!!.exportDates.size)
        assertEquals(LocalDate.of(2026, 8, 3), due.exportDates.first())
        assertEquals(LocalDate.of(2026, 8, 9), due.exportDates.last())

        // A Sunday entry's most recent boundary (yesterday) has already passed,
        // so it is due on Monday with the window ending before Sunday's fire day.
        val sundayEntry = mondayEntry.copy(weekdayIso = 7)
        val sundayDue = ScheduledProfileOccurrenceMath.dueOccurrence(sundayEntry, now)
        assertNotNull(sundayDue)
        assertEquals(7, sundayDue!!.exportDates.size)

        // A Tuesday entry's previous boundary is Aug 4 (the prior Tuesday), and
        // its trailing week is still pending, so it is also due on Monday —
        // with fire time pinned to the Tuesday boundary, not today.
        val tuesdayEntry = mondayEntry.copy(weekdayIso = 2)
        val tuesdayDue = ScheduledProfileOccurrenceMath.dueOccurrence(tuesdayEntry, now)
        assertNotNull(tuesdayDue)
        assertEquals(
            millisOf(LocalDate.of(2026, 8, 4)),
            tuesdayDue!!.fireAtMillis,
        )
    }

    @Test
    fun `every-other-day cadence skips unmatched boundaries`() {
        // Anchor Monday 2026-08-10; every 2 days → boundaries Aug 10, 12, 14 …
        val now = millisOf(LocalDate.of(2026, 8, 11), LocalTime.of(9, 0))
        val entry = entry(cadenceValue = 2, anchorEpochDay = LocalDate.of(2026, 8, 10).toEpochDay())
        // The previous boundary is Aug 10 (on-cadence), so it is due.
        assertNotNull(ScheduledProfileOccurrenceMath.dueOccurrence(entry, now))

        // Success at Aug 10 08:00 covered Aug 9; next on-cadence boundary is Aug 12, not yet due.
        val afterSuccess = entry.copy(lastSuccessEpochMillis = millisOf(LocalDate.of(2026, 8, 10)))
        assertNull(ScheduledProfileOccurrenceMath.dueOccurrence(afterSuccess, now))
        assertEquals(
            millisOf(LocalDate.of(2026, 8, 12)),
            ScheduledProfileOccurrenceMath.nextOccurrence(afterSuccess, now)?.toEpochMilli(),
        )
    }

    @Test
    fun `future anchors do not invent completed-day occurrences before opt-in`() {
        val anchor = LocalDate.of(2026, 8, 10)
        val now = millisOf(anchor.minusDays(1), LocalTime.NOON)
        for (unit in ScheduledProfileCadenceUnit.entries) {
            val configured = entry(cadenceUnit = unit, anchorEpochDay = anchor.toEpochDay(), lookbackDays = 14)
            assertNull(ScheduledProfileOccurrenceMath.dueOccurrence(configured, now))
            assertEquals(millisOf(anchor), ScheduledProfileOccurrenceMath.nextOccurrence(configured, now)?.toEpochMilli())
        }
    }

    @Test
    fun `disabled entries never surface occurrences`() {
        val now = millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(12, 0))
        assertNull(ScheduledProfileOccurrenceMath.dueOccurrence(entry(enabled = false), now))
    }

    @Test
    fun `nextOccurrence is strictly in the future and respects cadence`() {
        val now = millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(12, 0))
        val daily = ScheduledProfileOccurrenceMath.nextOccurrence(entry(), now)
        assertEquals(
            LocalDateTime.of(LocalDate.of(2026, 8, 11), LocalTime.of(8, 0)).atZone(zone).toInstant(),
            daily,
        )

        val weeklyMonday = ScheduledProfileOccurrenceMath.nextOccurrence(
            entry(cadenceUnit = ScheduledProfileCadenceUnit.WEEK, weekdayIso = 1),
            now,
        )
        assertEquals(
            LocalDateTime.of(LocalDate.of(2026, 8, 17), LocalTime.of(8, 0)).atZone(zone).toInstant(),
            weeklyMonday,
        )
    }

    @Test
    fun `monthly anchor day clamps calendar-naturally across month lengths`() {
        // iOS parity: an anchor on the 31st fires on the 31st in 31-day months and the last
        // day of shorter months (Jan 31 → Feb 28 → Mar 31), never a flat day-28.
        val anchor31 = entry(
            cadenceUnit = ScheduledProfileCadenceUnit.MONTH,
            anchorEpochDay = LocalDate.of(2026, 1, 31).toEpochDay(),
        )

        // January: the 31st stays the 31st.
        val midJanuary = millisOf(LocalDate.of(2026, 1, 10), LocalTime.of(12, 0))
        assertEquals(
            LocalDateTime.of(LocalDate.of(2026, 1, 31), LocalTime.of(8, 0)).atZone(zone).toInstant(),
            ScheduledProfileOccurrenceMath.nextOccurrence(anchor31, midJanuary),
        )

        // After Jan 31: next occurrence is Feb 28 (clamped to the shorter month).
        val februaryFirst = millisOf(LocalDate.of(2026, 2, 1), LocalTime.of(12, 0))
        assertEquals(
            LocalDateTime.of(LocalDate.of(2026, 2, 28), LocalTime.of(8, 0)).atZone(zone).toInstant(),
            ScheduledProfileOccurrenceMath.nextOccurrence(anchor31, februaryFirst),
        )

        // After Feb 28: March fires on the 31st again (clamping is per-month, not sticky).
        val marchFirst = millisOf(LocalDate.of(2026, 3, 1), LocalTime.of(12, 0))
        assertEquals(
            LocalDateTime.of(LocalDate.of(2026, 3, 31), LocalTime.of(8, 0)).atZone(zone).toInstant(),
            ScheduledProfileOccurrenceMath.nextOccurrence(anchor31, marchFirst),
        )
    }

    @Test
    fun `monthly previous boundary follows the same natural clamp`() {
        val anchor31 = entry(
            cadenceUnit = ScheduledProfileCadenceUnit.MONTH,
            anchorEpochDay = LocalDate.of(2026, 1, 31).toEpochDay(),
        )

        // Standing on March 10 with no success yet: the previous boundary is Feb 28.
        val marchTenth = millisOf(LocalDate.of(2026, 3, 10), LocalTime.of(12, 0))
        val due = ScheduledProfileOccurrenceMath.dueOccurrence(anchor31, marchTenth)
        assertNotNull(due)
        assertEquals(
            LocalDateTime.of(LocalDate.of(2026, 2, 28), LocalTime.of(8, 0)).atZone(zone).toInstant().toEpochMilli(),
            due!!.fireAtMillis,
        )
    }

    @Test
    fun `worker coalescing picks the earliest enabled preferred time`() {
        val entries = listOf(entry(hour = 20), entry(hour = 6, minute = 30))
        assertEquals(6 to 30, ScheduledProfileWorkerCoalescing.earliestPreferred(entries, legacyHour = null, legacyMinute = null))
        // Legacy competes when enabled.
        assertEquals(5 to 0, ScheduledProfileWorkerCoalescing.earliestPreferred(entries, legacyHour = 5, legacyMinute = 0))
        // Nothing enabled, no legacy.
        assertNull(ScheduledProfileWorkerCoalescing.earliestPreferred(entries.map { it.copy(isEnabled = false) }, legacyHour = null, legacyMinute = null))
    }

    @Test
    fun `entry validation rejects out-of-range fields`() {
        assertThrows<IllegalArgumentException> { entry(lookbackDays = 0) }
        assertThrows<IllegalArgumentException> { entry(lookbackDays = 31) }
        assertThrows<IllegalArgumentException> { entry(hour = 24) }
        assertThrows<IllegalArgumentException> { entry(weekdayIso = 0) }
        assertThrows<IllegalArgumentException> { entry(cadenceValue = 0) }
    }

    @Test
    fun `weekly monday boundary math stays stable across DST-free week`() {
        // Sanity: previousBoundary lands on Monday even mid-week.
        val now = millisOf(LocalDate.of(2026, 8, 12), LocalTime.of(15, 0)) // Wednesday
        val entry = entry(cadenceUnit = ScheduledProfileCadenceUnit.WEEK, weekdayIso = 1, lookbackDays = 7)
        val due = ScheduledProfileOccurrenceMath.dueOccurrence(entry, now)
        assertNotNull(due)
        assertEquals(
            LocalDate.of(2026, 8, 10).atTime(LocalTime.of(8, 0)).atZone(zone).toInstant().toEpochMilli(),
            due!!.fireAtMillis,
        )
        assertTrue(DayOfWeek.MONDAY == LocalDate.of(2026, 8, 10).dayOfWeek)
    }

    // MARK: Today Refresh (iOS parity)

    @Test
    fun `refresh-only occurrence is due after the preferred slot and exports only today`() {
        // Monday 2026-08-10 10:00, preferred 08:00, interval 3h; yesterday already covered.
        val now = millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(10, 0))
        val due = ScheduledProfileOccurrenceMath.dueOccurrence(
            entry(
                lastSuccessEpochMillis = millisOf(LocalDate.of(2026, 8, 10)),
                todayRefreshEnabled = true,
            ),
            now,
        )

        assertNotNull(due)
        assertEquals(listOf(LocalDate.of(2026, 8, 10)), due!!.exportDates)
        assertEquals(millisOf(LocalDate.of(2026, 8, 10)), due.fireAtMillis)
        assertEquals(millisOf(LocalDate.of(2026, 8, 10)), due.refreshSlotMillis)
        assertNull(due.pendingExport)
    }

    @Test
    fun `satisfied refresh slot is not due again until the next slot`() {
        // 09:00 with the 08:00 slot already recorded as successful: the next due slot is 11:00.
        val now = millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(9, 0))
        val due = ScheduledProfileOccurrenceMath.dueOccurrence(
            entry(
                lastSuccessEpochMillis = millisOf(LocalDate.of(2026, 8, 10)),
                todayRefreshEnabled = true,
                lastRefreshSuccessEpochMillis = millisOf(LocalDate.of(2026, 8, 10)),
            ),
            now,
        )
        assertNull(due)

        val next = ScheduledProfileOccurrenceMath.nextRefreshOccurrence(
            entry(
                todayRefreshEnabled = true,
                lastRefreshSuccessEpochMillis = millisOf(LocalDate.of(2026, 8, 10)),
            ),
            now,
        )
        assertEquals(millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(11, 0)), next?.toEpochMilli())
    }

    @Test
    fun `merged occurrence exports full lookback plus today and keeps the cadence boundary`() {
        // No prior success: yesterday is pending, and the 08:00 refresh slot passed at 09:30.
        val now = millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(9, 30))
        val due = ScheduledProfileOccurrenceMath.dueOccurrence(
            entry(todayRefreshEnabled = true, lookbackDays = 2),
            now,
        )

        assertNotNull(due)
        assertEquals(
            listOf(LocalDate.of(2026, 8, 8), LocalDate.of(2026, 8, 9), LocalDate.of(2026, 8, 10)),
            due!!.exportDates,
        )
        assertEquals(millisOf(LocalDate.of(2026, 8, 10)), due.fireAtMillis)
        assertEquals(millisOf(LocalDate.of(2026, 8, 10)), due.refreshSlotMillis)
    }

    @Test
    fun `no refresh slot is due before the preferred time and the day rolls over after the last slot`() {
        // 07:00 before an 08:00 preferred time: nothing due, next slot is today 08:00.
        val early = millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(7, 0))
        assertNull(
            ScheduledProfileOccurrenceMath.dueRefreshSlotMillis(
                entry(
                    lastSuccessEpochMillis = millisOf(LocalDate.of(2026, 8, 10)),
                    todayRefreshEnabled = true,
                ),
                early,
            ),
        )
        assertEquals(
            millisOf(LocalDate.of(2026, 8, 10)),
            ScheduledProfileOccurrenceMath.nextRefreshOccurrence(
                entry(todayRefreshEnabled = true),
                early,
            )?.toEpochMilli(),
        )

        // 23:30 with 3h interval: slots were 08/11/14/17/20/23; the last passed, so next is tomorrow 08:00.
        val late = millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(23, 30))
        assertEquals(
            millisOf(LocalDate.of(2026, 8, 11)),
            ScheduledProfileOccurrenceMath.nextRefreshOccurrence(
                entry(todayRefreshEnabled = true),
                late,
            )?.toEpochMilli(),
        )
        // The 23:00 slot itself is still due when unsatisfied.
        assertEquals(
            millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(23, 0)),
            ScheduledProfileOccurrenceMath.dueRefreshSlotMillis(entry(todayRefreshEnabled = true), late),
        )
    }

    @Test
    fun `refresh slots from a previous day never count as due`() {
        // Last refresh success was yesterday 20:00; today at 09:00 only today's 08:00 slot is due.
        val now = millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(9, 0))
        val slot = ScheduledProfileOccurrenceMath.dueRefreshSlotMillis(
            entry(
                todayRefreshEnabled = true,
                lastRefreshSuccessEpochMillis = millisOf(LocalDate.of(2026, 8, 9), LocalTime.of(20, 0)),
            ),
            now,
        )
        assertEquals(millisOf(LocalDate.of(2026, 8, 10)), slot)
    }

    @Test
    fun `next occurrence arms the earlier of the cadence boundary and refresh slot`() {
        // Daily 08:00 entry with 3h refresh; at 10:00 the next boundary would be tomorrow 08:00,
        // but the next refresh slot is today 11:00 — arming must pick 11:00.
        val now = millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(10, 0))
        val next = ScheduledProfileOccurrenceMath.nextOccurrence(
            entry(
                lastSuccessEpochMillis = millisOf(LocalDate.of(2026, 8, 10)),
                todayRefreshEnabled = true,
            ),
            now,
        )
        assertEquals(millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(11, 0)), next?.toEpochMilli())

        // Without refresh, the same moment arms tomorrow's 08:00 boundary.
        val cadenceOnly = ScheduledProfileOccurrenceMath.nextOccurrence(
            entry(lastSuccessEpochMillis = millisOf(LocalDate.of(2026, 8, 10))),
            now,
        )
        assertEquals(millisOf(LocalDate.of(2026, 8, 11)), cadenceOnly?.toEpochMilli())
    }

    @Test
    fun `residual group is returned without merging a due refresh slot`() {
        val now = millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(12, 0))
        val residualDate = LocalDate.of(2026, 8, 2)
        val residual = ScheduledProfilePendingExport(
            id = "residual-1",
            ownerEpochDays = listOf(residualDate.toEpochDay()),
            fireAtMillis = millisOf(LocalDate.of(2026, 8, 3)),
            settingsSnapshotJson = "frozen-settings",
            target = ExportTarget.DEVICE_FOLDER,
            profileName = "Morning",
        )

        val due = ScheduledProfileOccurrenceMath.dueOccurrence(
            entry(
                lastSuccessEpochMillis = millisOf(LocalDate.of(2026, 8, 9)),
                todayRefreshEnabled = true,
            ).copy(pendingExports = listOf(residual)),
            now,
        )

        assertNotNull(due)
        assertEquals(listOf(residualDate), due!!.exportDates)
        assertNull(due.refreshSlotMillis)
        assertEquals(residual, due.pendingExport)
    }

    @Test
    fun `interval options reject unsupported values`() {
        assertThrows<IllegalArgumentException> {
            entry(todayRefreshEnabled = true, todayRefreshIntervalHours = 4)
        }
        assertEquals(3, ScheduledProfileEntry.clampTodayRefreshInterval(4))
        assertEquals(6, ScheduledProfileEntry.clampTodayRefreshInterval(5))
        assertEquals(12, ScheduledProfileEntry.clampTodayRefreshInterval(99))
    }

    private inline fun <reified T : Throwable> assertThrows(block: () -> Unit) {
        try {
            block()
            error("Expected ${T::class.simpleName} was not thrown.")
        } catch (expected: Throwable) {
            // Kotlin init blocks wrap IllegalArgumentException directly; match the reified type.
            if (!T::class.isInstance(expected)) {
                throw AssertionError("Expected ${T::class.simpleName} but got ${expected::class.simpleName}: ${expected.message}")
            }
        }
    }
}
