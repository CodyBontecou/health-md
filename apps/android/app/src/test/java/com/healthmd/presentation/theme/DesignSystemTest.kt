package com.healthmd.presentation.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Test

class DesignSystemTest {
    @Test
    fun `light theme uses governing Material 3 tokens`() {
        assertEquals(Color(0xFFFEF7FF), GeistLightColors.background100)
        assertEquals(Color(0xFFF8F1FA), GeistLightColors.background200)
        assertEquals(Color(0xFF1D1B20), GeistLightColors.primary)
        assertEquals(Color(0xFF49454F), GeistLightColors.secondary)
        assertEquals(Color(0xFF7A757F), GeistLightColors.disabled)
        assertEquals(Color(0xFF6A3FE0), GeistLightColors.accent)
        assertEquals(Color(0xFF4F2FA8), GeistLightColors.accentHover)
        assertEquals(Color(0xFFE9DDFF), GeistLightColors.brandSubtle)
        assertEquals(Color(0xFF23005C), GeistLightColors.brandOnSubtle)
        assertEquals(Color(0xFFCDB6FF), GeistLightColors.brandBorder)
        assertEquals(Color(0xFFFFFFFF), GeistLightColors.brandOnPrimary)
        assertEquals(Color(0xFFE8DEF8), GeistLightColors.secondaryContainer)
        assertEquals(Color(0xFF1D192B), GeistLightColors.onSecondaryContainer)
        assertEquals(Color(0xFFDCCFFA), GeistLightColors.coverageComplete)
        assertEquals(Color(0xFF2D1F4F), GeistLightColors.onCoverageComplete)
        assertEquals(Color(0xFFB93C0A), GeistLightColors.coverageMissing)
        assertEquals(Color(0xFF15803D), GeistLightColors.coverageNoGaps)
        assertEquals(Color(0xFF107D32), GeistLightColors.success)
        assertEquals(Color.White, GeistLightColors.onSuccess)
        assertEquals(Color(0x14000000), GeistLightColors.grayAlpha.c400)
    }

    @Test
    fun `dark theme uses governing Material 3 tokens`() {
        assertEquals(Color(0xFF141218), GeistDarkColors.background100)
        assertEquals(Color(0xFF1D1B20), GeistDarkColors.background200)
        assertEquals(Color(0xFFE6E0E9), GeistDarkColors.primary)
        assertEquals(Color(0xFFCAC4D0), GeistDarkColors.secondary)
        assertEquals(Color(0xFF948F99), GeistDarkColors.disabled)
        assertEquals(Color(0xFFCDB6FF), GeistDarkColors.accent)
        assertEquals(Color(0xFFE9DDFF), GeistDarkColors.accentHover)
        assertEquals(Color(0xFF4F2FA8), GeistDarkColors.brandSubtle)
        assertEquals(Color(0xFFF1E8FF), GeistDarkColors.brandOnSubtle)
        assertEquals(Color(0xFF6A3FE0), GeistDarkColors.brandBorder)
        assertEquals(Color(0xFF2A1260), GeistDarkColors.brandOnPrimary)
        assertEquals(Color(0xFF4A4458), GeistDarkColors.secondaryContainer)
        assertEquals(Color(0xFFE8DEF8), GeistDarkColors.onSecondaryContainer)
        assertEquals(Color(0xFF3B3058), GeistDarkColors.coverageComplete)
        assertEquals(Color(0xFFFFFFFF), GeistDarkColors.onCoverageComplete)
        assertEquals(Color(0xFFFFA184), GeistDarkColors.coverageMissing)
        assertEquals(Color(0xFF8BF0B4), GeistDarkColors.coverageNoGaps)
        assertEquals(Color(0xFF00CA50), GeistDarkColors.success)
        assertEquals(Color(0xFF141218), GeistDarkColors.onSuccess)
        assertEquals(Color(0x24FFFFFF), GeistDarkColors.grayAlpha.c400)
    }

    @Test
    fun `spacing and radius use the documented scales`() {
        assertEquals(4.dp, GeistSpacing.space1)
        assertEquals(8.dp, GeistSpacing.space2)
        assertEquals(12.dp, GeistSpacing.space3)
        assertEquals(16.dp, GeistSpacing.space4)
        assertEquals(24.dp, GeistSpacing.space6)
        assertEquals(32.dp, GeistSpacing.space8)
        assertEquals(40.dp, GeistSpacing.space10)
        assertEquals(64.dp, GeistSpacing.space16)
        assertEquals(96.dp, GeistSpacing.space24)
        assertEquals(4.dp, GeistRadii.extraSmall)
        assertEquals(8.dp, GeistRadii.small)
        assertEquals(16.dp, GeistRadii.medium)
        assertEquals(28.dp, GeistRadii.large)
        assertEquals(20.dp, GeistRadii.listGroup)
    }
}
