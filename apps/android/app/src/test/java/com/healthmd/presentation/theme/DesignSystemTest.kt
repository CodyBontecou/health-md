package com.healthmd.presentation.theme

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Test

class DesignSystemTest {
    @Test
    fun `light theme uses governing Geist tokens`() {
        assertEquals(Color(0xFFFFFFFF), GeistLightColors.background100)
        assertEquals(Color(0xFFFAFAFA), GeistLightColors.background200)
        assertEquals(Color(0xFF171717), GeistLightColors.primary)
        assertEquals(Color(0xFF4D4D4D), GeistLightColors.secondary)
        assertEquals(Color(0xFF66488F), GeistLightColors.accent)
        assertEquals(Color(0xFF463176), GeistLightColors.accentHover)
        assertEquals(Color(0xFFF4EFF7), GeistLightColors.brandSubtle)
        assertEquals(Color(0xFFC5ADD9), GeistLightColors.brandBorder)
        assertEquals(Color.White, GeistLightColors.brandOnPrimary)
        assertEquals(Color(0xFF107D32), GeistLightColors.success)
        assertEquals(Color.White, GeistLightColors.onSuccess)
        assertEquals(Color(0x14000000), GeistLightColors.grayAlpha.c400)
    }

    @Test
    fun `dark theme uses governing Geist tokens`() {
        assertEquals(Color(0xFF000000), GeistDarkColors.background100)
        assertEquals(Color(0xFFEDEDED), GeistDarkColors.primary)
        assertEquals(Color(0xFFA0A0A0), GeistDarkColors.secondary)
        assertEquals(Color(0xFFC5ADD9), GeistDarkColors.accent)
        assertEquals(Color(0xFFDFD5E8), GeistDarkColors.accentHover)
        assertEquals(Color(0xFF241946), GeistDarkColors.brandSubtle)
        assertEquals(Color(0xFF463176), GeistDarkColors.brandBorder)
        assertEquals(Color(0xFF241946), GeistDarkColors.brandOnPrimary)
        assertEquals(Color(0xFF00CA50), GeistDarkColors.success)
        assertEquals(Color.Black, GeistDarkColors.onSuccess)
        assertEquals(Color(0x24FFFFFF), GeistDarkColors.grayAlpha.c400)
    }

    @Test
    fun `spacing and radius use the documented four pixel scale`() {
        assertEquals(4.dp, GeistSpacing.space1)
        assertEquals(8.dp, GeistSpacing.space2)
        assertEquals(12.dp, GeistSpacing.space3)
        assertEquals(16.dp, GeistSpacing.space4)
        assertEquals(24.dp, GeistSpacing.space6)
        assertEquals(32.dp, GeistSpacing.space8)
        assertEquals(40.dp, GeistSpacing.space10)
        assertEquals(64.dp, GeistSpacing.space16)
        assertEquals(96.dp, GeistSpacing.space24)
        assertEquals(6.dp, GeistRadii.small)
        assertEquals(12.dp, GeistRadii.medium)
        assertEquals(16.dp, GeistRadii.large)
    }
}
