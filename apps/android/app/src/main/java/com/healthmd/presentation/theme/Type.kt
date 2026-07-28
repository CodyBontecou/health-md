package com.healthmd.presentation.theme

import androidx.compose.material3.Typography
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.Font
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.sp
import com.healthmd.R

val GeistSans = FontFamily(
    Font(R.font.geist_regular, FontWeight.Normal),
    Font(R.font.geist_medium, FontWeight.Medium),
    Font(R.font.geist_semibold, FontWeight.SemiBold),
)

val GeistMono = FontFamily(
    Font(R.font.geist_mono_regular, FontWeight.Normal),
    Font(R.font.geist_mono_medium, FontWeight.Medium),
)

private fun geistSans(
    size: Int,
    lineHeight: Int,
    weight: FontWeight = FontWeight.Normal,
    letterSpacing: Float = 0f,
) = TextStyle(
    fontFamily = GeistSans,
    fontSize = size.sp,
    fontWeight = weight,
    lineHeight = lineHeight.sp,
    letterSpacing = letterSpacing.sp,
)

private fun geistMono(
    size: Int,
    lineHeight: Int,
) = TextStyle(
    fontFamily = GeistMono,
    fontSize = size.sp,
    fontWeight = FontWeight.Normal,
    lineHeight = lineHeight.sp,
    fontFeatureSettings = "tnum",
)

/** Exact reusable typography tokens from DESIGN.md and DESIGN.dark.md. */
object GeistType {
    val heading72 = geistSans(72, 72, FontWeight.SemiBold, -4.32f)
    val heading64 = geistSans(64, 64, FontWeight.SemiBold, -3.84f)
    val heading56 = geistSans(56, 56, FontWeight.SemiBold, -3.36f)
    val heading48 = geistSans(48, 56, FontWeight.SemiBold, -2.88f)
    val heading40 = geistSans(40, 48, FontWeight.SemiBold, -2.4f)
    val heading32 = geistSans(32, 40, FontWeight.SemiBold, -1.28f)
    val heading24 = geistSans(24, 32, FontWeight.SemiBold, -0.96f)
    val heading20 = geistSans(20, 26, FontWeight.SemiBold, -0.4f)
    val heading16 = geistSans(16, 24, FontWeight.SemiBold, -0.32f)
    val heading14 = geistSans(14, 20, FontWeight.SemiBold, -0.28f)

    val button16 = geistSans(16, 20, FontWeight.Medium)
    val button14 = geistSans(14, 20, FontWeight.Medium)
    val button12 = geistSans(12, 16, FontWeight.Medium)

    val label20 = geistSans(20, 32)
    val label18 = geistSans(18, 20)
    val label16 = geistSans(16, 20)
    val label14 = geistSans(14, 20)
    val label13 = geistSans(13, 16)
    val label12 = geistSans(12, 16)
    val label14Mono = geistMono(14, 20)
    val label13Mono = geistMono(13, 20)
    val label12Mono = geistMono(12, 16)

    val copy24 = geistSans(24, 36)
    val copy20 = geistSans(20, 36)
    val copy18 = geistSans(18, 28)
    val copy16 = geistSans(16, 24)
    val copy14 = geistSans(14, 20)
    val copy13 = geistSans(13, 18)
    val copy14Mono = geistMono(14, 20)
    val copy13Mono = geistMono(13, 18)
}

/** Material role mapping used by existing screens; every role resolves to a Geist token. */
val Typography = Typography(
    displayLarge = GeistType.heading56,
    displayMedium = GeistType.heading48,
    displaySmall = GeistType.heading40,
    headlineLarge = GeistType.heading32,
    headlineMedium = GeistType.heading24,
    headlineSmall = GeistType.heading20,
    titleLarge = GeistType.heading20,
    titleMedium = GeistType.heading16,
    titleSmall = GeistType.heading14,
    bodyLarge = GeistType.copy16,
    bodyMedium = GeistType.copy14,
    bodySmall = GeistType.copy13,
    labelLarge = GeistType.button14,
    labelMedium = GeistType.label13,
    labelSmall = GeistType.label12,
)
