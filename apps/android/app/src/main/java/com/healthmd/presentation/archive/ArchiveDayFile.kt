package com.healthmd.presentation.archive

import androidx.annotation.StringRes
import com.healthmd.R
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HealthDataFields
import com.healthmd.domain.model.UnitConverter
import com.healthmd.domain.model.UnitPreference
import java.text.NumberFormat
import java.time.LocalDate
import java.util.Locale
import kotlin.math.abs
import kotlin.math.roundToInt

/** Where one lane's file for a date lives: a SAF tree and the exporter's relative path. */
data class ArchiveFileRef(val folderUri: String, val relativePath: String)

/**
 * The written file for one Archive date, read from the export folder (iOS `ArchiveDayFile`).
 * [source] holds at most [MAXIMUM_BYTES]; [byteCount] is the file's full size.
 */
data class ArchiveDayFile(
    /** The SAF document URI, for Open file. */
    val documentUri: String,
    val name: String,
    val mimeType: String?,
    val source: String,
    val byteCount: Long,
) {
    /** At most [MAXIMUM_LINES]; a trailing newline is not a line of its own. */
    val lines: List<String>
        get() {
            val all = source.split('\n')
            val trimmed = if (all.lastOrNull() == "") all.dropLast(1) else all
            return trimmed.take(MAXIMUM_LINES).map { it.removeSuffix("\r") }
        }

    val isTruncated: Boolean
        get() = byteCount > MAXIMUM_BYTES || source.split('\n').size > MAXIMUM_LINES + 1

    companion object {
        /** Above this the day page shows the first lines only; Open file shows the rest. */
        const val MAXIMUM_BYTES = 512 * 1024
        const val MAXIMUM_LINES = 400
    }
}

/** A loaded file, keyed by what was asked for so a stale read is never shown. */
data class ArchiveLoadedFile(val key: ArchiveDayFileKey, val file: ArchiveDayFile?)

/** What the readable day card or day page asked to read. */
data class ArchiveDayFileKey(
    val lane: ArchiveProfile,
    val date: LocalDate,
    val ref: ArchiveFileRef,
    val status: CoverageStatus,
    /** The latest covering run, so a re-export re-reads the file. */
    val recordedAt: Long?,
)

/** One headline value from a day file's frontmatter, as the Archive day card shows it. */
data class ArchiveDayTile(
    val key: String,
    /** The metric's localized name; null shows [key] itself. */
    @StringRes val labelRes: Int?,
    val value: String,
    val unit: String,
)

/**
 * Picks the day card's headline values from a Markdown file's frontmatter (iOS
 * `ArchiveDayTiles`). Only what the file says is shown: no value is computed or filled in.
 */
object ArchiveDayTiles {
    /** Sleep, steps, heart, HRV, energy and mindfulness lead; other known metrics fill in file order. */
    val preferredKeys = listOf(
        "steps", "sleep_total_hours", "resting_heart_rate", "hrv_ms", "active_calories", "mindful_minutes",
    )

    private val knownKeys: Set<String> by lazy { HealthDataFields.allKeys.toSet() }

    /** Units as the exporter labels each key, in metric (the iOS tiles use metric too). */
    private val units: Map<String, String> by lazy {
        runCatching {
            HealthDataFields.extract(HealthData(date = LocalDate.ofEpochDay(0)), UnitConverter(UnitPreference.METRIC))
                .associate { it.key to it.unit }
        }.getOrDefault(emptyMap())
    }

    fun tiles(source: String, limit: Int = 6, locale: Locale = Locale.getDefault()): List<ArchiveDayTile> {
        val fields = frontmatterScalars(source)
        if (fields.isEmpty()) return emptyList()
        val picked = mutableListOf<Pair<String, String>>()
        val used = mutableSetOf<String>()
        for (preferred in preferredKeys) {
            fields.firstOrNull { canonicalKey(it.first) == preferred && isNumeric(it.second) }?.let {
                picked += it
                used += it.first
            }
        }
        for (field in fields) {
            if (field.first !in used && isNumeric(field.second) && canonicalKey(field.first) in knownKeys) {
                picked += field
                used += field.first
            }
        }
        return picked.take(limit).map { (key, value) -> tile(key, value, locale) }
    }

    /** Top-level `key: value` pairs between the opening and closing `---`; none without a closing fence. */
    fun frontmatterScalars(source: String): List<Pair<String, String>> {
        val lines = source.split('\n')
        if (lines.firstOrNull()?.trim() != "---") return emptyList()
        val result = mutableListOf<Pair<String, String>>()
        for (raw in lines.drop(1)) {
            val text = raw.trimEnd('\r')
            if (text.trim() == "---") return result
            val first = text.firstOrNull() ?: continue
            if (first.isWhitespace() || first == '#' || first == '-') continue
            val colon = text.indexOf(':').takeIf { it >= 0 } ?: continue
            val key = text.substring(0, colon).trim()
            var value = text.substring(colon + 1).trim()
            if (value.length >= 2 && (value.first() == '"' || value.first() == '\'') && value.last() == value.first()) {
                value = value.substring(1, value.length - 1)
            }
            if (key.isEmpty() || value.isEmpty()) continue
            result += key to value
        }
        return emptyList()
    }

    fun tile(key: String, value: String, locale: Locale = Locale.getDefault()): ArchiveDayTile {
        val canonical = canonicalKey(key)
        val label = labelRes(canonical)
        val number = value.toDoubleOrNull()
        if (canonical.endsWith("_hours") && canonical != "stand_hours" && number != null) {
            val minutes = (number * 60).roundToInt()
            return ArchiveDayTile(key, label, "${minutes / 60}h ${minutes % 60}m", "")
        }
        val formatted = if (number != null && number == Math.rint(number) && abs(number) < 1e12) {
            NumberFormat.getIntegerInstance(locale).format(number.toLong())
        } else {
            value
        }
        return ArchiveDayTile(key, label, formatted, displayUnit(units[canonical].orEmpty()))
    }

    /** `restingHeartRate` and `Resting Heart Rate` style keys map back to snake case. */
    fun canonicalKey(key: String): String {
        if (key in knownKeys) return key
        val result = StringBuilder()
        for (character in key) {
            when {
                character == ' ' || character == '-' -> result.append('_')
                character.isUpperCase() -> {
                    if (result.isNotEmpty() && result.last() != '_') result.append('_')
                    result.append(character.lowercaseChar())
                }
                else -> result.append(character)
            }
        }
        return result.toString()
    }

    private fun isNumeric(value: String): Boolean = value.toDoubleOrNull()?.isFinite() == true

    private fun displayUnit(unit: String): String = when (unit) {
        "count", "boolean", "uuid", "datetime", "time", "hours", "" -> ""
        "percent" -> "%"
        "minutes" -> "min"
        else -> unit
    }

    @StringRes
    private fun labelRes(canonical: String): Int? = when (canonical) {
        "sleep_total_hours" -> R.string.metric_name_sleep_total
        "sleep_deep_hours" -> R.string.metric_name_sleep_deep
        "sleep_rem_hours" -> R.string.metric_name_sleep_rem
        "sleep_light_hours", "sleep_core_hours" -> R.string.metric_name_sleep_light
        "sleep_awake_hours" -> R.string.metric_name_sleep_awake
        "sleep_in_bed_hours" -> R.string.metric_name_sleep_in_bed
        "steps" -> R.string.metric_name_steps
        "active_calories" -> R.string.metric_name_active_calories
        "total_calories" -> R.string.metric_name_total_calories
        "basal_calories" -> R.string.metric_name_basal_calories
        "exercise_minutes" -> R.string.metric_name_exercise_minutes
        "flights_climbed" -> R.string.metric_name_flights_climbed
        "walking_running_km" -> R.string.metric_name_distance
        "cycling_km" -> R.string.metric_name_cycling_distance
        "elevation_gained_m" -> R.string.metric_name_elevation_gained
        "resting_heart_rate" -> R.string.metric_name_resting_hr
        "average_heart_rate" -> R.string.metric_name_avg_hr
        "walking_heart_rate" -> R.string.metric_name_walking_hr
        "heart_rate_min" -> R.string.metric_name_min_hr
        "heart_rate_max" -> R.string.metric_name_max_hr
        "hrv_ms" -> R.string.metric_name_hrv
        "respiratory_rate", "respiratory_rate_avg" -> R.string.metric_name_respiratory_rate
        "blood_oxygen", "blood_oxygen_avg" -> R.string.metric_name_blood_oxygen
        "weight_kg" -> R.string.metric_name_weight
        "body_fat_percent" -> R.string.metric_name_body_fat
        "vo2_max" -> R.string.metric_name_vo2_max
        "mindful_minutes" -> R.string.metric_name_mindful_minutes
        "mindful_sessions" -> R.string.metric_name_mindful_sessions
        "water_l" -> R.string.metric_name_water
        "dietary_calories" -> R.string.metric_name_dietary_energy
        else -> null
    }
}
