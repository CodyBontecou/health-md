package com.healthmd.data.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HeartData
import com.healthmd.domain.model.TimestampedSample
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.model.WorkoutData
import com.healthmd.domain.model.WorkoutType
import com.healthmd.export.ExportFixtures
import java.io.ByteArrayOutputStream
import java.time.LocalDateTime
import kotlin.time.Duration.Companion.minutes
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import org.junit.Test

/**
 * The folder writer streams legacy JSON instead of materializing one String. The streamed bytes
 * must equal the historical `export(...)` String encoded as UTF-8, for every representative
 * fixture/customization (pretty-print, key order, escaping, no trailing newline).
 */
class JsonExporterStreamingTest {

    private val exporter = JsonExporter()

    private val customizations = listOf(
        FormatCustomization(),
        FormatCustomization(unitPreference = UnitPreference.IMPERIAL),
        FormatCustomization(includeLegacyAndroidAliases = true, includeAndroidNativeFields = true),
        FormatCustomization(compatibilitySchemaProfile = CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5),
    )

    private val unicodeDay = HealthData(
        date = ExportFixtures.referenceDate,
        heart = HeartData(
            averageHeartRate = 61.5,
            samples = listOf(
                TimestampedSample(
                    time = ExportFixtures.referenceDateTime.plusHours(1),
                    value = 60.0,
                    // Quotes, backslash, control characters, BMP and non-BMP text, and malformed
                    // UTF-16 (lone high and low surrogates) all have to encode identically.
                    source = "Strap \"Ω\" \\ tab\t nl\n \u0001 🏃‍♀️ lone\uD83C end \uDC00",
                    metadata = mapOf("note" to "café 日本 😀", "z" to "\uD83C"),
                ),
            ),
        ),
    )

    @Test
    fun streamedLegacyTreeIsByteIdenticalToTheHistoricalString() {
        val fixtures = listOf(
            ExportFixtures.emptyDay,
            ExportFixtures.partialDay,
            ExportFixtures.fullDay,
            ExportFixtures.fullDayGranular,
            ExportFixtures.edgeCaseDay,
            unicodeDay,
        )
        var compared = 0
        for (data in fixtures) for (customization in customizations) for (granular in listOf(false, true)) {
            val expected = exporter.export(data, customization, granular).toByteArray(Charsets.UTF_8)
            val streamed = ByteArrayOutputStream().also { output ->
                exporter.encodeLegacyTree(exporter.exportLegacyTree(data, customization, granular), output)
            }.toByteArray()
            assertThat(streamed).isEqualTo(expected)
            compared++
        }
        assertThat(compared).isEqualTo(fixtures.size * customizations.size * 2)
    }

    @Test
    fun nonFiniteMetricValuesAreOmittedLikeMissingValuesInsteadOfFailingEncoding() {
        val start = LocalDateTime.of(2026, 3, 15, 7, 0)
        val data = HealthData(
            date = ExportFixtures.referenceDate,
            activity = ActivityData(steps = 1234, activeCalories = Double.NaN),
            heart = HeartData(
                restingHeartRate = 55.0,
                averageHeartRate = Double.NaN,
                hrv = Double.POSITIVE_INFINITY,
                samples = listOf(
                    TimestampedSample(time = start, value = Double.NaN),
                    TimestampedSample(time = start.plusMinutes(1), value = 70.0),
                ),
            ),
            workouts = listOf(
                WorkoutData(
                    workoutType = WorkoutType.RUNNING,
                    startTime = start,
                    duration = 30.minutes,
                    // A zero speed derives an infinite pace; NaN heart rate cannot be rounded.
                    averageSpeed = 0.0,
                    averageHeartRate = Double.NaN,
                    heartRateMax = Double.NEGATIVE_INFINITY,
                ),
            ),
        )
        val finiteTwin = data.copy(
            activity = data.activity.copy(activeCalories = null),
            heart = data.heart.copy(averageHeartRate = null, hrv = null),
        )

        for (customization in customizations) for (granular in listOf(false, true)) {
            val text = exporter.export(data, customization, granular)
            assertThat(text).doesNotContain("NaN")
            assertThat(text).doesNotContain("Infinity")
            val root = Json.parseToJsonElement(text).jsonObject
            assertThat(root.containsKeyDeep("activeCalories")).isFalse()
            assertThat(root.containsKeyDeep("hrv")).isFalse()
            // A NaN measurement is represented exactly like an absent one at the top level.
            val finite = Json.parseToJsonElement(exporter.export(finiteTwin, customization, granular)).jsonObject
            assertThat(root["activity"]).isEqualTo(finite["activity"])
            assertThat(root.keys).isEqualTo(finite.keys)
            val workout = root.getValue("workouts").jsonArray.single().jsonObject
            assertThat(workout).doesNotContainKey("averagePaceSecondsPerKm")
            assertThat(workout).doesNotContainKey("avgHeartRate")
            assertThat(workout).doesNotContainKey("maxHeartRate")

            val streamed = ByteArrayOutputStream().also { output ->
                exporter.encodeLegacyTree(exporter.exportLegacyTree(data, customization, granular), output)
            }.toByteArray()
            assertThat(streamed).isEqualTo(text.toByteArray(Charsets.UTF_8))
        }
    }

    private fun kotlinx.serialization.json.JsonElement.containsKeyDeep(key: String): Boolean = when (this) {
        is JsonObject -> containsKey(key) || values.any { it.containsKeyDeep(key) }
        is kotlinx.serialization.json.JsonArray -> any { it.containsKeyDeep(key) }
        else -> false
    }
}
