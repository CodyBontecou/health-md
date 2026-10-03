package com.healthmd.presentation.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class AdaptiveLayoutTest {
    @Test
    fun `reading layout responds to text size or a constrained viewport`() {
        assertFalse(GeistAdaptiveLayout.readingFirst(411f, 720f, 1f))
        assertFalse(GeistAdaptiveLayout.readingFirst(401f, 401f, 1.29f))
        assertTrue(GeistAdaptiveLayout.readingFirst(411f, 720f, 1.3f))
        assertTrue(GeistAdaptiveLayout.readingFirst(320f, 640f, 1f))
        assertTrue(GeistAdaptiveLayout.readingFirst(640f, 280f, 1f))
    }

    @Test
    fun `paired actions get enough reading width at the selected text scale`() {
        assertFalse(GeistAdaptiveLayout.stackActions(360f, 1f))
        assertFalse(GeistAdaptiveLayout.stackActions(512f, 2f))
        assertFalse(GeistAdaptiveLayout.stackActions(520f, 2f)) // short, wide landscape
        assertTrue(GeistAdaptiveLayout.stackActions(304f, 1.3f))
        assertTrue(GeistAdaptiveLayout.stackActions(240f, 1f))
        assertTrue(GeistAdaptiveLayout.stackActions(360f, 2f))
    }

    @Test
    fun `navigation wraps before four tabs become narrow text columns`() {
        assertFalse(GeistAdaptiveLayout.wrapNavigation(395f, 1f, 4))
        assertFalse(GeistAdaptiveLayout.wrapNavigation(512f, 2f, 4))
        assertTrue(GeistAdaptiveLayout.wrapNavigation(304f, 1.3f, 4))
        assertTrue(GeistAdaptiveLayout.wrapNavigation(395f, 2f, 4))
    }

    @Test
    fun `detailed controls keep long values out of narrow columns`() {
        assertFalse(GeistAdaptiveLayout.stackDetailedControls(336f, 1f))
        assertFalse(GeistAdaptiveLayout.stackDetailedControls(672f, 2f))
        assertTrue(GeistAdaptiveLayout.stackDetailedControls(335f, 1f))
        assertTrue(GeistAdaptiveLayout.stackDetailedControls(347f, 1.3f))
        assertTrue(GeistAdaptiveLayout.stackDetailedControls(600f, 2f))
    }

    @Test
    fun `readable secondary copy meets AA contrast in both themes`() {
        listOf(GeistLightColors, GeistDarkColors).forEach { colors ->
            assertTrue(contrast(colors.secondary, colors.background100) >= 4.5)
        }
    }

    private fun contrast(first: Color, second: Color): Double {
        val brighter = maxOf(first.luminance(), second.luminance())
        val darker = minOf(first.luminance(), second.luminance())
        return (brighter + 0.05) / (darker + 0.05)
    }
}
