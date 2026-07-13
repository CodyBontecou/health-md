package com.healthmd.presentation.theme

import androidx.compose.foundation.isSystemInDarkTheme
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Shapes
import androidx.compose.material3.darkColorScheme
import androidx.compose.material3.lightColorScheme
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.graphics.Color

private val GeistShapes = Shapes(
    extraSmall = RoundedCornerShape(GeistRadii.small),
    small = RoundedCornerShape(GeistRadii.small),
    medium = RoundedCornerShape(GeistRadii.medium),
    large = RoundedCornerShape(GeistRadii.medium),
    extraLarge = RoundedCornerShape(GeistRadii.large),
)

private val HealthMdLightScheme = lightColorScheme(
    primary = GeistLightColors.brandPrimary,
    onPrimary = GeistLightColors.brandOnPrimary,
    primaryContainer = GeistLightColors.brandSubtle,
    onPrimaryContainer = GeistLightColors.brandHover,
    secondary = GeistLightColors.gray.c1000,
    onSecondary = GeistLightColors.background100,
    secondaryContainer = GeistLightColors.gray.c100,
    onSecondaryContainer = GeistLightColors.gray.c1000,
    tertiary = GeistLightColors.green.c700,
    onTertiary = Color.White,
    tertiaryContainer = GeistLightColors.green.c100,
    onTertiaryContainer = GeistLightColors.green.c1000,
    error = GeistLightColors.red.c800,
    onError = Color.White,
    errorContainer = GeistLightColors.red.c100,
    onErrorContainer = GeistLightColors.red.c1000,
    background = GeistLightColors.background100,
    onBackground = GeistLightColors.gray.c1000,
    surface = GeistLightColors.background100,
    onSurface = GeistLightColors.gray.c1000,
    surfaceVariant = GeistLightColors.background200,
    onSurfaceVariant = GeistLightColors.gray.c900,
    outline = GeistLightColors.grayAlpha.c400,
    outlineVariant = GeistLightColors.grayAlpha.c200,
    inverseSurface = GeistLightColors.gray.c1000,
    inverseOnSurface = GeistLightColors.background100,
    inversePrimary = GeistDarkColors.brandPrimary,
    surfaceTint = Color.Transparent,
    scrim = GeistLightColors.grayAlpha.c900,
    surfaceContainerLowest = GeistLightColors.background100,
    surfaceContainerLow = GeistLightColors.background200,
    surfaceContainer = GeistLightColors.background200,
    surfaceContainerHigh = GeistLightColors.gray.c100,
    surfaceContainerHighest = GeistLightColors.gray.c200,
)

private val HealthMdDarkScheme = darkColorScheme(
    primary = GeistDarkColors.brandPrimary,
    onPrimary = GeistDarkColors.brandOnPrimary,
    primaryContainer = GeistDarkColors.brandSubtle,
    onPrimaryContainer = GeistDarkColors.brandPrimary,
    secondary = GeistDarkColors.gray.c1000,
    onSecondary = GeistDarkColors.background100,
    secondaryContainer = GeistDarkColors.gray.c100,
    onSecondaryContainer = GeistDarkColors.gray.c1000,
    tertiary = GeistDarkColors.green.c700,
    onTertiary = GeistDarkColors.background100,
    tertiaryContainer = GeistDarkColors.green.c100,
    onTertiaryContainer = GeistDarkColors.green.c1000,
    error = GeistDarkColors.red.c800,
    onError = Color.White,
    errorContainer = GeistDarkColors.red.c100,
    onErrorContainer = GeistDarkColors.red.c1000,
    background = GeistDarkColors.background100,
    onBackground = GeistDarkColors.gray.c1000,
    surface = GeistDarkColors.background100,
    onSurface = GeistDarkColors.gray.c1000,
    surfaceVariant = GeistDarkColors.background200,
    onSurfaceVariant = GeistDarkColors.gray.c900,
    outline = GeistDarkColors.grayAlpha.c400,
    outlineVariant = GeistDarkColors.grayAlpha.c200,
    inverseSurface = GeistDarkColors.gray.c1000,
    inverseOnSurface = GeistDarkColors.background100,
    inversePrimary = GeistLightColors.brandPrimary,
    surfaceTint = Color.Transparent,
    scrim = GeistDarkColors.grayAlpha.c900,
    surfaceContainerLowest = GeistDarkColors.background100,
    surfaceContainerLow = GeistDarkColors.background200,
    surfaceContainer = GeistDarkColors.background200,
    surfaceContainerHigh = GeistDarkColors.gray.c100,
    surfaceContainerHighest = GeistDarkColors.gray.c200,
)

@Composable
fun HealthMdTheme(
    darkTheme: Boolean = isSystemInDarkTheme(),
    content: @Composable () -> Unit,
) {
    val colors = if (darkTheme) GeistDarkColors else GeistLightColors
    val colorScheme = if (darkTheme) HealthMdDarkScheme else HealthMdLightScheme

    CompositionLocalProvider(LocalGeistColors provides colors) {
        MaterialTheme(
            colorScheme = colorScheme,
            typography = Typography,
            shapes = GeistShapes,
            content = content,
        )
    }
}
