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

object WearColors {
    const val backgroundArgb = 0xFF000000L
    const val surfaceArgb = 0xFF1A1A1AL
    const val primaryArgb = 0xFFC5ADD9L
    const val onPrimaryArgb = 0xFF241946L
    const val textArgb = 0xFFEDEDEDL
    const val mutedArgb = 0xFFA0A0A0L
    const val successArgb = 0xFF00CA50L
    const val warningArgb = 0xFFFF9300L
    const val errorArgb = 0xFFFF565FL

    // Per-metric icon tints referencing the DESIGN.dark.md accent scales (dark-900/700 steps).
    // They reuse existing named hex values and are documented in the Wear OS surfaces section.
    const val metricStepsArgb = 0xFF00CA50L // green-900
    const val metricMoveArgb = 0xFFFF9300L // amber-900
    const val metricExerciseArgb = 0xFFFFAE00L // amber-700
    const val metricSleepArgb = 0xFFC472FBL // purple-900
    const val metricRestingHeartArgb = 0xFFFF565FL // red-900
    const val metricAverageHeartArgb = 0xFFF13242L // red-700
    const val metricHrvArgb = 0xFF00CFB7L // teal-900
    const val metricOxygenArgb = 0xFF00AA95L // teal-700

    val background get() = Color(backgroundArgb)
    val surface get() = Color(surfaceArgb)
    val primary get() = Color(primaryArgb)
    val onPrimary get() = Color(onPrimaryArgb)
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
