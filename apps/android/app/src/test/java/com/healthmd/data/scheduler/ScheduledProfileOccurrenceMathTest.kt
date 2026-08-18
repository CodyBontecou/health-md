package com.healthmd.data.scheduler

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
        zoneId = zone.id,
        lastSuccessEpochMillis = lastSuccessEpochMillis,
    )

    @Test
    fun `daily boundary with pending yesterday is due and exports exactly the uncovered dates`() {
        // Monday 2026-08-10 12:00; boundary Monday 08:00 passed, no prior success.
        val now = millisOf(LocalDate.of(2026, 8, 10), LocalTime.of(12, 0))
        val due = ScheduledProfileOccurrenceMath.dueOccurrence(entry(), now)

        assertNotNull(due)
        assertEquals(listOf(LocalDate.of(2026, 8, 9)), due!!.exportDates)
        assertEquals(millisOf(LocalDate.of(2026, 8, 10)), due.fireAtMillis)
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
        // so it is due on Monday with the same trailing week.
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
    fun `usage projection counts main runs across cadences`() {
        assertEquals(30, ScheduledProfileUsageProjection.projectedMonthlyRequests(entry()))
        assertEquals(5, ScheduledProfileUsageProjection.projectedMonthlyRequests(entry(cadenceUnit = ScheduledProfileCadenceUnit.WEEK)))
        // 30 / 14 ≈ 2.14 → ceil 3, matching the iOS usage-projection test.
        assertEquals(3, ScheduledProfileUsageProjection.projectedMonthlyRequests(entry(cadenceUnit = ScheduledProfileCadenceUnit.WEEK, cadenceValue = 2)))
        assertEquals(1, ScheduledProfileUsageProjection.projectedMonthlyRequests(entry(cadenceUnit = ScheduledProfileCadenceUnit.MONTH)))

        val entries = listOf(entry(), entry(enabled = false), entry(cadenceUnit = ScheduledProfileCadenceUnit.WEEK))
        // Disabled entries never count.
        assertEquals(35, ScheduledProfileUsageProjection.projectedMonthlyTotal(entries))
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
