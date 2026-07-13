package com.healthmd.presentation.theme

import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp

/**
 * Compose tokens for the governing Vercel Geist specifications in DESIGN.md and
 * DESIGN.dark.md. Screen code should consume these tokens instead of inventing values.
 */
@Immutable
data class GeistColorScale(
    val c100: Color,
    val c200: Color,
    val c300: Color,
    val c400: Color,
    val c500: Color,
    val c600: Color,
    val c700: Color,
    val c800: Color,
    val c900: Color,
    val c1000: Color,
)

@Immutable
data class GeistColors(
    val isDark: Boolean,
    val background100: Color,
    val background200: Color,
    val brandPrimary: Color,
    val brandHover: Color,
    val brandSubtle: Color,
    val brandBorder: Color,
    val brandOnPrimary: Color,
    val gray: GeistColorScale,
    val grayAlpha: GeistColorScale,
    val blue: GeistColorScale,
    val red: GeistColorScale,
    val amber: GeistColorScale,
    val green: GeistColorScale,
    val teal: GeistColorScale,
    val purple: GeistColorScale,
    val pink: GeistColorScale,
) {
    val primary: Color get() = gray.c1000
    val secondary: Color get() = gray.c900
    val disabled: Color get() = gray.c700
    val accent: Color get() = brandPrimary
    val accentHover: Color get() = brandHover
    val success: Color get() = green.c900
    val onSuccess: Color get() = if (isDark) background100 else Color.White
    val warning: Color get() = amber.c900
    val error: Color get() = red.c900
}

internal val GeistLightColors = GeistColors(
    isDark = false,
    background100 = Color(0xFFFFFFFF),
    background200 = Color(0xFFFAFAFA),
    brandPrimary = Color(0xFF66488F),
    brandHover = Color(0xFF463176),
    brandSubtle = Color(0xFFF4EFF7),
    brandBorder = Color(0xFFC5ADD9),
    brandOnPrimary = Color.White,
    gray = GeistColorScale(
        Color(0xFFF2F2F2), Color(0xFFEBEBEB), Color(0xFFE6E6E6), Color(0xFFEAEAEA),
        Color(0xFFC9C9C9), Color(0xFFA8A8A8), Color(0xFF8F8F8F), Color(0xFF7D7D7D),
        Color(0xFF4D4D4D), Color(0xFF171717),
    ),
    grayAlpha = GeistColorScale(
        Color(0x0D000000), Color(0x15000000), Color(0x1A000000), Color(0x14000000),
        Color(0x36000000), Color(0x3D000000), Color(0x70000000), Color(0x82000000),
        Color(0xB3000000), Color(0xE8000000),
    ),
    blue = GeistColorScale(
        Color(0xFFF0F7FF), Color(0xFFE9F4FF), Color(0xFFDFEFFF), Color(0xFFCAE7FF),
        Color(0xFF94CCFF), Color(0xFF48AEFF), Color(0xFF006BFF), Color(0xFF0059EC),
        Color(0xFF005FF2), Color(0xFF002359),
    ),
    red = GeistColorScale(
        Color(0xFFFFEEEF), Color(0xFFFFE8EA), Color(0xFFFFE3E4), Color(0xFFFFD7D6),
        Color(0xFFFFB1B3), Color(0xFFFF676D), Color(0xFFFC0035), Color(0xFFEA001D),
        Color(0xFFD8001B), Color(0xFF47000C),
    ),
    amber = GeistColorScale(
        Color(0xFFFFF6DE), Color(0xFFFFF4CF), Color(0xFFFFF1C1), Color(0xFFFFDC73),
        Color(0xFFFFC543), Color(0xFFFFA600), Color(0xFFFFAE00), Color(0xFFFF9300),
        Color(0xFFAA4D00), Color(0xFF561900),
    ),
    green = GeistColorScale(
        Color(0xFFECFDEC), Color(0xFFE5FCE7), Color(0xFFD3FAD1), Color(0xFFB9F5BC),
        Color(0xFF82EB8D), Color(0xFF4CE15E), Color(0xFF28A948), Color(0xFF279141),
        Color(0xFF107D32), Color(0xFF003A00),
    ),
    teal = GeistColorScale(
        Color(0xFFDEFFFB), Color(0xFFDDFEF6), Color(0xFFCCF9F1), Color(0xFFB1F7EC),
        Color(0xFF52F0DB), Color(0xFF00E3C4), Color(0xFF00AC96), Color(0xFF00927F),
        Color(0xFF007F70), Color(0xFF003F34),
    ),
    purple = GeistColorScale(
        Color(0xFFFAF0FF), Color(0xFFF9F0FF), Color(0xFFF6E8FF), Color(0xFFF2D9FF),
        Color(0xFFDFA7FF), Color(0xFFC979FF), Color(0xFFA000F8), Color(0xFF8500D1),
        Color(0xFF7D00CC), Color(0xFF2F004E),
    ),
    pink = GeistColorScale(
        Color(0xFFFFE8F6), Color(0xFFFFE8F3), Color(0xFFFFDFEB), Color(0xFFFFD3E1),
        Color(0xFFFDB3CC), Color(0xFFF97EA7), Color(0xFFF22782), Color(0xFFE4106E),
        Color(0xFFC41562), Color(0xFF460523),
    ),
)

internal val GeistDarkColors = GeistColors(
    isDark = true,
    background100 = Color(0xFF000000),
    background200 = Color(0xFF000000),
    brandPrimary = Color(0xFFC5ADD9),
    brandHover = Color(0xFFDFD5E8),
    brandSubtle = Color(0xFF241946),
    brandBorder = Color(0xFF463176),
    brandOnPrimary = Color(0xFF241946),
    gray = GeistColorScale(
        Color(0xFF1A1A1A), Color(0xFF1F1F1F), Color(0xFF292929), Color(0xFF2E2E2E),
        Color(0xFF454545), Color(0xFF878787), Color(0xFF8F8F8F), Color(0xFF7D7D7D),
        Color(0xFFA0A0A0), Color(0xFFEDEDED),
    ),
    grayAlpha = GeistColorScale(
        Color(0x12FFFFFF), Color(0x17FFFFFF), Color(0x21FFFFFF), Color(0x24FFFFFF),
        Color(0x3DFFFFFF), Color(0x82FFFFFF), Color(0x8AFFFFFF), Color(0x78FFFFFF),
        Color(0x9CFFFFFF), Color(0xEBFFFFFF),
    ),
    blue = GeistColorScale(
        Color(0xFF06193A), Color(0xFF022248), Color(0xFF002F62), Color(0xFF003674),
        Color(0xFF00418B), Color(0xFF0090FF), Color(0xFF006EFE), Color(0xFF005BE7),
        Color(0xFF47A8FF), Color(0xFFEAF6FF),
    ),
    red = GeistColorScale(
        Color(0xFF330A11), Color(0xFF440D13), Color(0xFF5D0E17), Color(0xFF6F101B),
        Color(0xFF88151F), Color(0xFFF32E40), Color(0xFFF13242), Color(0xFFE2162A),
        Color(0xFFFF565F), Color(0xFFFFE9ED),
    ),
    amber = GeistColorScale(
        Color(0xFF2A1700), Color(0xFF361900), Color(0xFF502800), Color(0xFF5B3000),
        Color(0xFF703E00), Color(0xFFED9A00), Color(0xFFFFAE00), Color(0xFFFF9300),
        Color(0xFFFF9300), Color(0xFFFFF3D5),
    ),
    green = GeistColorScale(
        Color(0xFF002608), Color(0xFF00320B), Color(0xFF003A0E), Color(0xFF004615),
        Color(0xFF006717), Color(0xFF00952D), Color(0xFF00AC3A), Color(0xFF009432),
        Color(0xFF00CA50), Color(0xFFD8FFE4),
    ),
    teal = GeistColorScale(
        Color(0xFF00231B), Color(0xFF002B22), Color(0xFF003D34), Color(0xFF004035),
        Color(0xFF006354), Color(0xFF009E86), Color(0xFF00AA95), Color(0xFF00927F),
        Color(0xFF00CFB7), Color(0xFFCBFFF5),
    ),
    purple = GeistColorScale(
        Color(0xFF290C33), Color(0xFF341142), Color(0xFF47185E), Color(0xFF541A76),
        Color(0xFF642290), Color(0xFF9440D5), Color(0xFF9440D5), Color(0xFF7D2BBA),
        Color(0xFFC472FB), Color(0xFFFBECFF),
    ),
    pink = GeistColorScale(
        Color(0xFF310D1E), Color(0xFF420C25), Color(0xFF571032), Color(0xFF5D0C34),
        Color(0xFF76063F), Color(0xFFBA0056), Color(0xFFF12B82), Color(0xFFE7006D),
        Color(0xFFFF4D8D), Color(0xFFFFE9F4),
    ),
)

val LocalGeistColors = staticCompositionLocalOf { GeistLightColors }

object GeistSpacing {
    val space1 = 4.dp
    val space2 = 8.dp
    val space3 = 12.dp
    val space4 = 16.dp
    val space6 = 24.dp
    val space8 = 32.dp
    val space10 = 40.dp
    val space16 = 64.dp
    val space24 = 96.dp
}

object GeistRadii {
    val small = 6.dp
    val medium = 12.dp
    val large = 16.dp
    val full = 9999.dp
}

object GeistSizes {
    val controlSmall = 32.dp
    val control = 40.dp
    val controlLarge = 48.dp
    val minimumTouchTarget = 48.dp
    const val dialogMaxHeightFraction = 0.9f
}

object GeistElevation {
    val raisedCard
        @Composable get() = if (LocalGeistColors.current.isDark) 1.dp else 2.dp
}

object GeistBreakpoints {
    const val small = 401
    const val medium = 601
    const val large = 961
    const val extraLarge = 1200
    const val extraExtraLarge = 1400
}

object GeistMotion {
    const val instant = 0
    const val stateChange = 150
    const val popover = 200
    const val overlay = 300
    val easing = CubicBezierEasing(0.175f, 0.885f, 0.32f, 1.1f)
}

/** Compatibility names while every screen is migrated to the Geist primitives. */
object Spacing {
    val xxs = GeistSpacing.space1
    val xs = GeistSpacing.space2
    val sm = GeistSpacing.space3
    val md = GeistSpacing.space4
    val lg = GeistSpacing.space6
    val xl = GeistSpacing.space8
    val section = GeistSpacing.space10
    val xxl = GeistSpacing.space16
}

object Radii {
    val card = GeistRadii.small
    val button = GeistRadii.small
    val badge = GeistRadii.full
    val navBar = GeistRadii.medium
    val icon = GeistRadii.full
}

/**
 * Semantic compatibility facade. Values are theme-aware and come only from the
 * current DESIGN.md / DESIGN.dark.md token set.
 */
object AppColors {
    val bgPrimary: Color @Composable get() = LocalGeistColors.current.background100
    val bgSecondary: Color @Composable get() = LocalGeistColors.current.background200
    val bgTertiary: Color @Composable get() = LocalGeistColors.current.background100

    val borderSubtle: Color @Composable get() = LocalGeistColors.current.grayAlpha.c200
    val borderDefault: Color @Composable get() = LocalGeistColors.current.grayAlpha.c400
    val borderStrong: Color @Composable get() = LocalGeistColors.current.grayAlpha.c500

    val textPrimary: Color @Composable get() = LocalGeistColors.current.primary
    val textSecondary: Color @Composable get() = LocalGeistColors.current.secondary
    val textMuted: Color @Composable get() = LocalGeistColors.current.disabled

    val accent: Color @Composable get() = LocalGeistColors.current.accent
    val accentHover: Color @Composable get() = LocalGeistColors.current.accentHover
    val accentSubtle: Color @Composable get() = LocalGeistColors.current.brandSubtle
    val accentBorder: Color @Composable get() = LocalGeistColors.current.brandBorder
    val onAccent: Color @Composable get() = LocalGeistColors.current.brandOnPrimary

    val success: Color @Composable get() = LocalGeistColors.current.success
    val onSuccess: Color @Composable get() = LocalGeistColors.current.onSuccess
    val successSubtle: Color @Composable get() = LocalGeistColors.current.green.c100
    val successBorder: Color @Composable get() = LocalGeistColors.current.green.c400
    val error: Color @Composable get() = LocalGeistColors.current.error
    val errorSubtle: Color @Composable get() = LocalGeistColors.current.red.c100
    val errorBorder: Color @Composable get() = LocalGeistColors.current.red.c400
    val warning: Color @Composable get() = LocalGeistColors.current.warning
    val warningSubtle: Color @Composable get() = LocalGeistColors.current.amber.c100
    val warningBorder: Color @Composable get() = LocalGeistColors.current.amber.c400

}
