package com.healthmd.widget.glance

import android.content.Context
import android.content.res.Configuration
import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Path
import android.graphics.RectF
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import androidx.core.graphics.createBitmap
import com.healthmd.presentation.theme.GeistDarkColors
import com.healthmd.presentation.theme.GeistLightColors
import com.healthmd.widget.model.HealthWidgetDay
import com.healthmd.widget.model.HealthWidgetGoals
import com.healthmd.widget.model.HealthWidgetKind
import com.healthmd.widget.model.HealthWidgetSnapshot
import java.time.LocalDate
import java.time.ZoneId
import kotlin.math.max

internal data class HealthWidgetArtwork(
    val activityRings: Bitmap?,
    val heartRange: Bitmap?,
)

internal class WidgetArtworkRenderer {
    fun render(
        context: Context,
        snapshot: HealthWidgetSnapshot?,
        kind: HealthWidgetKind,
    ): HealthWidgetArtwork {
        val dark = context.resources.configuration.uiMode and Configuration.UI_MODE_NIGHT_MASK ==
            Configuration.UI_MODE_NIGHT_YES
        val colors = if (dark) GeistDarkColors else GeistLightColors
        val today = LocalDate.now(ZoneId.systemDefault())
        val displayDay = snapshot?.dayFor(kind, today)
        return HealthWidgetArtwork(
            activityRings = displayDay
                ?.takeIf { kind == HealthWidgetKind.SUMMARY || kind == HealthWidgetKind.ACTIVITY }
                ?.let {
                    renderActivityRings(
                        day = it,
                        activeColor = colors.amber.c900,
                        exerciseColor = colors.green.c900,
                        stepsColor = colors.teal.c900,
                    )
                },
            heartRange = snapshot
                ?.takeIf { kind == HealthWidgetKind.SUMMARY || kind == HealthWidgetKind.HEART_RANGE }
                ?.recentDays()
                ?.let { days -> renderHeartRange(days, colors.red.c900) },
        )
    }

    internal fun renderActivityRings(
        day: HealthWidgetDay,
        activeColor: Color,
        exerciseColor: Color,
        stepsColor: Color,
        sizePx: Int = ACTIVITY_BITMAP_SIZE,
    ): Bitmap {
        val boundedSize = sizePx.coerceIn(MIN_BITMAP_SIZE, MAX_BITMAP_SIZE)
        val bitmap = createBitmap(boundedSize, boundedSize)
        val canvas = Canvas(bitmap)
        val strokeWidth = boundedSize * 0.075f
        val gap = strokeWidth * 1.45f
        drawRing(
            canvas,
            inset = strokeWidth / 2f,
            strokeWidth = strokeWidth,
            progress = progress(day.activeCaloriesKilocalories, HealthWidgetGoals.ACTIVE_CALORIES_KILOCALORIES),
            color = activeColor.toArgb(),
        )
        drawRing(
            canvas,
            inset = strokeWidth / 2f + gap,
            strokeWidth = strokeWidth,
            progress = progress(day.exerciseMinutes, HealthWidgetGoals.EXERCISE_MINUTES),
            color = exerciseColor.toArgb(),
        )
        drawRing(
            canvas,
            inset = strokeWidth / 2f + gap * 2f,
            strokeWidth = strokeWidth,
            progress = progress(day.steps?.toDouble(), HealthWidgetGoals.STEPS),
            color = stepsColor.toArgb(),
        )
        return bitmap
    }

    internal fun renderHeartRange(
        days: List<HealthWidgetDay>,
        color: Color,
        widthPx: Int = HEART_BITMAP_WIDTH,
        heightPx: Int = HEART_BITMAP_HEIGHT,
    ): Bitmap? {
        val boundedWidth = widthPx.coerceIn(MIN_BITMAP_SIZE, MAX_BITMAP_WIDTH)
        val boundedHeight = heightPx.coerceIn(MIN_BITMAP_SIZE, MAX_BITMAP_HEIGHT)
        val points = days.mapIndexedNotNull { index, day ->
            val average = day.averageHeartRateBpm ?: return@mapIndexedNotNull null
            HeartPoint(
                index = index,
                minimum = day.minimumHeartRateBpm ?: average,
                average = average,
                maximum = day.maximumHeartRateBpm ?: average,
            )
        }
        if (points.isEmpty()) return null

        val bitmap = createBitmap(boundedWidth, boundedHeight)
        val canvas = Canvas(bitmap)
        val minimumValue = max(0.0, points.minOf(HeartPoint::minimum) - 12.0)
        val maximumValue = points.maxOf(HeartPoint::maximum) + 12.0
        val valueRange = max(1.0, maximumValue - minimumValue)
        val left = boundedWidth * 0.03f
        val top = boundedHeight * 0.06f
        val right = boundedWidth * 0.97f
        val bottom = boundedHeight * 0.92f
        val slotCount = max(days.size - 1, 1)

        fun x(index: Int): Float = left + (index.toFloat() / slotCount.toFloat()) * (right - left)
        fun y(value: Double): Float =
            bottom - (((value - minimumValue) / valueRange).toFloat() * (bottom - top))

        val rangePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color.toArgb()
            alpha = 72
            strokeWidth = boundedWidth * 0.018f
            strokeCap = Paint.Cap.ROUND
        }
        val linePaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color.toArgb()
            strokeWidth = boundedHeight * 0.025f
            strokeCap = Paint.Cap.ROUND
            strokeJoin = Paint.Join.ROUND
            style = Paint.Style.STROKE
        }
        val dotPaint = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color.toArgb()
            style = Paint.Style.FILL
        }
        val path = Path()
        points.forEachIndexed { pointIndex, point ->
            val pointX = x(point.index)
            canvas.drawLine(pointX, y(point.maximum), pointX, y(point.minimum), rangePaint)
            val averageY = y(point.average)
            if (pointIndex == 0) path.moveTo(pointX, averageY) else path.lineTo(pointX, averageY)
            canvas.drawCircle(pointX, averageY, boundedHeight * 0.035f, dotPaint)
        }
        canvas.drawPath(path, linePaint)
        return bitmap
    }

    private fun drawRing(
        canvas: Canvas,
        inset: Float,
        strokeWidth: Float,
        progress: Double,
        color: Int,
    ) {
        val bounds = RectF(inset, inset, canvas.width - inset, canvas.height - inset)
        val track = Paint(Paint.ANTI_ALIAS_FLAG).apply {
            this.color = color
            alpha = 40
            style = Paint.Style.STROKE
            this.strokeWidth = strokeWidth
            strokeCap = Paint.Cap.ROUND
        }
        val foreground = Paint(track).apply { alpha = 255 }
        canvas.drawArc(bounds, -90f, 360f, false, track)
        canvas.drawArc(bounds, -90f, (progress.coerceIn(0.0, 1.0) * 360.0).toFloat(), false, foreground)
        if (progress > 1.0) {
            foreground.alpha = 112
            canvas.drawArc(
                bounds,
                -90f,
                ((progress - 1.0).coerceIn(0.0, 1.0) * 360.0).toFloat(),
                false,
                foreground,
            )
        }
    }

    private fun progress(value: Double?, goal: Double): Double =
        if (value == null || !value.isFinite() || goal <= 0.0) 0.0 else max(0.0, value / goal)

    private data class HeartPoint(
        val index: Int,
        val minimum: Double,
        val average: Double,
        val maximum: Double,
    )

    private companion object {
        const val ACTIVITY_BITMAP_SIZE = 256
        const val HEART_BITMAP_WIDTH = 600
        const val HEART_BITMAP_HEIGHT = 180
        const val MIN_BITMAP_SIZE = 32
        const val MAX_BITMAP_SIZE = 512
        const val MAX_BITMAP_WIDTH = 960
        const val MAX_BITMAP_HEIGHT = 320
    }
}
