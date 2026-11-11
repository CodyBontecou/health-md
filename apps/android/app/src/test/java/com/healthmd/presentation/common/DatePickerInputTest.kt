package com.healthmd.presentation.common

import java.time.LocalDate
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DatePickerInputTest {
    private val years = 1900..2100

    @Test
    fun `impossible days are rejected instead of being changed to the last day of the month`() {
        listOf("2026-02-31", "2026-02-29", "2024-04-31", "2026-13-01", "2026-01-00").forEach {
            assertNull(it, parseDatePickerInput(it, years))
        }
    }

    @Test
    fun `real dates including leap days and range boundaries retain their exact day`() {
        listOf("2024-02-29", "2026-02-28", "1900-01-01", "2100-12-31").forEach {
            assertEquals(LocalDate.parse(it), parseDatePickerInput(it, years))
        }
    }

    @Test
    fun `partial malformed and out of range input cannot be confirmed`() {
        listOf("", " ", "2026-02-", "2026-2-03", "02/03/2026", "2026-02-03junk", "1899-12-31", "2101-01-01").forEach {
            assertNull(it, parseDatePickerInput(it, years))
        }
    }
}
