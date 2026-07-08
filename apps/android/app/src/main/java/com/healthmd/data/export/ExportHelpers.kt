package com.healthmd.data.export

import java.text.NumberFormat
import java.util.Locale
import kotlin.time.Duration

object ExportHelpers {

    fun formatDuration(duration: Duration): String {
        val totalSeconds = duration.inWholeSeconds
        val hours = totalSeconds / 3600
        val minutes = (totalSeconds % 3600) / 60

        return when {
            hours > 0 && minutes > 0 -> "${hours}h ${minutes}m"
            hours > 0 -> "${hours}h"
            minutes > 0 -> "${minutes}m"
            else -> "0m"
        }
    }

    fun formatDurationShort(duration: Duration): String {
        val totalMinutes = duration.inWholeMinutes
        return when {
            totalMinutes >= 60 -> {
                val hours = totalMinutes / 60
                val mins = totalMinutes % 60
                if (mins > 0) "${hours}h ${mins}m" else "${hours}h"
            }
            else -> "${totalMinutes}m"
        }
    }

    fun formatNumber(value: Int): String =
        NumberFormat.getNumberInstance(Locale.US).format(value)

    fun formatNumber(value: Double, decimals: Int = 1): String =
        String.format(Locale.US, "%.${decimals}f", value)
}
