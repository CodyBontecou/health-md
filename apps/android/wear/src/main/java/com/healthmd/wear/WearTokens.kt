package com.healthmd.wear

import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

/**
 * Renderer-neutral Wear token values plus Compose adapters.
 *
 * Tiles cannot consume Compose [Color], [androidx.compose.ui.unit.Dp], or
 * [androidx.compose.ui.unit.TextUnit] values, so every token also exposes its primitive ARGB,
 * dp, or sp value. Compose and ProtoLayout must both consume this one named token source.
 */
object WearSpacing {
    const val xsDp = 4f
    const val smDp = 8f
    const val mdDp = 12f
    const val lgDp = 16f
    const val xlDp = 24f

    val xs get() = xsDp.dp
    val sm get() = smDp.dp
    val md get() = mdDp.dp
    val lg get() = lgDp.dp
    val xl get() = xlDp.dp
}

object WearType {
    const val captionSp = 12f
    const val bodySp = 14f
    const val titleSp = 16f
    const val displaySp = 20f

    val caption get() = captionSp.sp
    val body get() = bodySp.sp
    val title get() = titleSp.sp
    val display get() = displaySp.sp
}

object WearShape {
    const val smDp = 6f
    const val mdDp = 12f

    val sm = RoundedCornerShape(smDp.dp)
    val md = RoundedCornerShape(mdDp.dp)
    val full = RoundedCornerShape(50)
}

/** Fixed element sizes shared by the watch app and Tiles. */
object WearSize {
    /** Metric glyph inside a row or above a Tile title. */
    const val iconDp = 24f
    /** Circular status badge (setup, phone unreachable) and the glyph inside it. */
    const val badgeDp = 32f
    const val badgeIconDp = 16f
    /** Tile progress ring stroke and its inset from the round screen edge. */
    const val progressStrokeDp = 6f
    const val progressInsetDp = 4f

    val icon get() = iconDp.dp
    val badge get() = badgeDp.dp
    val badgeIcon get() = badgeIconDp.dp
    val progressStroke get() = progressStrokeDp.dp
}

/**
 * Health.md Material 3 dark tonal roles for the watch (Wear OS boards in the M3 redesign).
 * Neutral and brand roles reuse DESIGN.dark.md steps; the background stays pure black for OLED.
 */
object WearColors {
    const val backgroundArgb = 0xFF000000L
    const val surfaceArgb = 0xFF2B2930L // gray-200: rows, chips, progress track
    const val surfaceHighArgb = 0xFF36343BL // gray-300: disabled action container
    const val outlineArgb = 0xFF49454FL // gray-500: complication track, dashed no-data outline
    const val primaryArgb = 0xFFCDB6FFL // brand-primary: titles and primary action
    const val onPrimaryArgb = 0xFF381E72L
    const val primaryContainerArgb = 0xFF4F2FA8L // brand-subtle: setup badge
    const val onPrimaryContainerArgb = 0xFFF1E8FFL // brand-on-subtle
    const val textArgb = 0xFFE6E0E9L // gray-1000
    const val mutedArgb = 0xFFCAC4D0L // gray-900
    const val successArgb = 0xFF8BF0B4L
    const val warningArgb = 0xFFFFB960L // stale age, unreachable phone
    const val errorArgb = 0xFFFFB4ABL

    // Per-metric accents from the Wear boards. Color always pairs with a text label.
    const val metricStepsArgb = 0xFF8BF0B4L
    const val metricMoveArgb = 0xFFFFB960L
    const val metricExerciseArgb = 0xFFFFB960L
    const val metricSleepArgb = 0xFF7DB4FFL
    const val metricRestingHeartArgb = 0xFFFFA184L // coverage-missing coral
    const val metricAverageHeartArgb = 0xFFFFA184L
    const val metricHrvArgb = 0xFF7FE3D2L
    const val metricOxygenArgb = 0xFF7FE3D2L

    val background get() = Color(backgroundArgb)
    val surface get() = Color(surfaceArgb)
    val surfaceHigh get() = Color(surfaceHighArgb)
    val outline get() = Color(outlineArgb)
    val primary get() = Color(primaryArgb)
    val onPrimary get() = Color(onPrimaryArgb)
    val primaryContainer get() = Color(primaryContainerArgb)
    val onPrimaryContainer get() = Color(onPrimaryContainerArgb)
    val text get() = Color(textArgb)
    val muted get() = Color(mutedArgb)
    val success get() = Color(successArgb)
    val warning get() = Color(warningArgb)
    val error get() = Color(errorArgb)

    val metricSteps get() = Color(metricStepsArgb)
    val metricMove get() = Color(metricMoveArgb)
    val metricExercise get() = Color(metricExerciseArgb)
    val metricSleep get() = Color(metricSleepArgb)
    val metricRestingHeart get() = Color(metricRestingHeartArgb)
    val metricAverageHeart get() = Color(metricAverageHeartArgb)
    val metricHrv get() = Color(metricHrvArgb)
    val metricOxygen get() = Color(metricOxygenArgb)
}
