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

private val HealthMdShapes = Shapes(
    extraSmall = RoundedCornerShape(GeistRadii.extraSmall),
    small = RoundedCornerShape(GeistRadii.small),
    medium = RoundedCornerShape(GeistRadii.medium),
    large = RoundedCornerShape(GeistRadii.medium),
    extraLarge = RoundedCornerShape(GeistRadii.large),
)

private val HealthMdLightScheme = lightColorScheme(
    primary = GeistLightColors.brandPrimary,
    onPrimary = GeistLightColors.brandOnPrimary,
    primaryContainer = GeistLightColors.brandSubtle,
    onPrimaryContainer = GeistLightColors.brandOnSubtle,
    secondary = GeistLightColors.gray.c800,
    onSecondary = GeistLightColors.background100,
    secondaryContainer = GeistLightColors.secondaryContainer,
    onSecondaryContainer = GeistLightColors.onSecondaryContainer,
    tertiary = GeistLightColors.green.c900,
    onTertiary = GeistLightColors.background100,
    tertiaryContainer = GeistLightColors.green.c100,
    onTertiaryContainer = GeistLightColors.green.c1000,
    error = GeistLightColors.red.c900,
    onError = GeistLightColors.background100,
    errorContainer = GeistLightColors.red.c100,
    onErrorContainer = GeistLightColors.red.c1000,
    background = GeistLightColors.background100,
    onBackground = GeistLightColors.gray.c1000,
    surface = GeistLightColors.background100,
    onSurface = GeistLightColors.gray.c1000,
    surfaceVariant = GeistLightColors.gray.c300,
    onSurfaceVariant = GeistLightColors.gray.c900,
    outline = GeistLightColors.gray.c700,
    outlineVariant = GeistLightColors.gray.c500,
    inverseSurface = GeistLightColors.gray.c1000,
    inverseOnSurface = GeistLightColors.background100,
    inversePrimary = GeistDarkColors.brandPrimary,
    surfaceTint = Color.Transparent,
    scrim = GeistLightColors.grayAlpha.c900,
    surfaceContainerLowest = GeistLightColors.background100,
    surfaceContainerLow = GeistLightColors.background200,
    surfaceContainer = GeistLightColors.gray.c100,
    surfaceContainerHigh = GeistLightColors.gray.c200,
    surfaceContainerHighest = GeistLightColors.gray.c300,
)

private val HealthMdDarkScheme = darkColorScheme(
    primary = GeistDarkColors.brandPrimary,
    onPrimary = GeistDarkColors.brandOnPrimary,
    primaryContainer = GeistDarkColors.brandSubtle,
    onPrimaryContainer = GeistDarkColors.brandOnSubtle,
    secondary = GeistDarkColors.gray.c800,
    onSecondary = GeistDarkColors.background100,
    secondaryContainer = GeistDarkColors.secondaryContainer,
    onSecondaryContainer = GeistDarkColors.onSecondaryContainer,
    tertiary = GeistDarkColors.green.c900,
    onTertiary = GeistDarkColors.background100,
    tertiaryContainer = GeistDarkColors.green.c100,
    onTertiaryContainer = GeistDarkColors.green.c1000,
    error = GeistDarkColors.red.c900,
    onError = GeistDarkColors.background100,
    errorContainer = GeistDarkColors.red.c100,
    onErrorContainer = GeistDarkColors.red.c1000,
    background = GeistDarkColors.background100,
    onBackground = GeistDarkColors.gray.c1000,
    surface = GeistDarkColors.background100,
    onSurface = GeistDarkColors.gray.c1000,
    surfaceVariant = GeistDarkColors.gray.c300,
    onSurfaceVariant = GeistDarkColors.gray.c900,
    outline = GeistDarkColors.gray.c700,
    outlineVariant = GeistDarkColors.gray.c500,
    inverseSurface = GeistDarkColors.gray.c1000,
    inverseOnSurface = GeistDarkColors.background100,
    inversePrimary = GeistLightColors.brandPrimary,
    surfaceTint = Color.Transparent,
    scrim = GeistDarkColors.grayAlpha.c900,
    surfaceContainerLowest = GeistDarkColors.background100,
    surfaceContainerLow = GeistDarkColors.background200,
    surfaceContainer = GeistDarkColors.gray.c100,
    surfaceContainerHigh = GeistDarkColors.gray.c200,
    surfaceContainerHighest = GeistDarkColors.gray.c300,
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
            shapes = HealthMdShapes,
            content = content,
        )
    }
}
