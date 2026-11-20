package com.healthmd.presentation.schedule

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class ScheduleWarningsTest {

    private fun warnings(
        enabled: Boolean,
        exact: Boolean = true,
        backgroundFeature: Boolean = false,
        backgroundReady: Boolean = true,
        notifications: Boolean = true,
    ) = scheduleWarnings(
        scheduleEnabled = enabled,
        exactTimingAvailable = exact,
        backgroundReadFeatureAvailable = backgroundFeature,
        backgroundReadReady = backgroundReady,
        notificationsReady = notifications,
    )

    @Test
    fun `exact timing card shows iff schedule enabled and exact alarms denied`() {
        assertTrue(warnings(enabled = true, exact = false).exactTiming)
        assertFalse(warnings(enabled = true, exact = true).exactTiming)
        assertFalse(warnings(enabled = false, exact = false).exactTiming)
    }

    @Test
    fun `background read card needs the feature and a missing grant`() {
        assertTrue(warnings(enabled = true, backgroundFeature = true, backgroundReady = false).backgroundRead)
        assertFalse(warnings(enabled = true, backgroundFeature = false, backgroundReady = false).backgroundRead)
        assertFalse(warnings(enabled = true, backgroundFeature = true, backgroundReady = true).backgroundRead)
    }

    @Test
    fun `notification card shows when notifications are not ready`() {
        assertTrue(warnings(enabled = true, notifications = false).notifications)
        assertFalse(warnings(enabled = true, notifications = true).notifications)
    }

    @Test
    fun `a disabled schedule shows no warnings`() {
        assertEquals(
            ScheduleWarnings.None,
            warnings(enabled = false, exact = false, backgroundFeature = true, backgroundReady = false, notifications = false),
        )
    }
}
