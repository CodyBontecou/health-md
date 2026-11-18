package com.healthmd.data.billing

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TrialReminderTest {
    private val now = 1_800_000_000_000L
    private val day = 24 * 60 * 60 * 1000L

    @Test fun aNewSevenDayTrialIsRemindedOnDayFive() {
        val end = TrialReminder.trialEndMillis(purchaseTimeMillis = now)
        assertEquals(now + 7 * day, end)
        assertEquals(now + 5 * day, TrialReminder.fireAtMillis(end, now))
    }

    @Test fun aTrialInsideTheLeadTimeIsRemindedRightAway() {
        assertEquals(now + 60_000L, TrialReminder.fireAtMillis(now + day, now))
    }

    @Test fun aTrialAboutToEndIsNotReminded() {
        assertNull(TrialReminder.fireAtMillis(now + 30 * 60 * 1000L, now))
        assertNull(TrialReminder.fireAtMillis(now - day, now))
    }
}
