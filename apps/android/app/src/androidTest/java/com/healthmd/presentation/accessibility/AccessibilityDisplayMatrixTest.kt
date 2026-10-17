package com.healthmd.presentation.accessibility

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Test

class AccessibilityDisplayMatrixTest {
    @Test
    fun absentArgumentKeepsTheCompleteLocalMatrix() {
        val displays = accessibilityDisplayCases(null)
        assertEquals(10, displays.size)
        assertEquals(displays, accessibilityDisplayCases("full"))
        assertTrue(displays.contains(AccessibilityDisplayCase(568, 280, 2f)))
        assertTrue(displays.contains(AccessibilityDisplayCase(640, 280, 2f)))
        assertTrue(displays.contains(AccessibilityDisplayCase(320, 640, 2f, language = "ja")))
    }

    @Test
    fun smokeCoversBaselineAndConstrainedLargeFontRtlDarkMode() {
        val displays = accessibilityDisplayCases("smoke")
        assertEquals(
            listOf(
                AccessibilityDisplayCase(411, 720, 1f),
                AccessibilityDisplayCase(320, 480, 2f, language = "ar", dark = true),
            ),
            displays,
        )
        assertTrue(accessibilityDisplayCases("full").containsAll(displays))
    }

    @Test
    fun unknownOrEmptyScopesCannotSilentlyReduceCoverage() {
        for (matrix in listOf("", "Smoke", "false", "none")) {
            try {
                accessibilityDisplayCases(matrix)
                fail("Expected invalid matrix '$matrix' to fail")
            } catch (expected: IllegalArgumentException) {
                assertTrue(expected.message.orEmpty().contains(ACCESSIBILITY_MATRIX_ARGUMENT))
            }
        }
    }
}
