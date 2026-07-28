package com.healthmd.export

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.APIExportEnvelopeBuilder
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.settings.decodePersistedExportSettings
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.ExactSourceIdentity
import com.healthmd.domain.model.ExactSourceTimestamp
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.MobilityData
import com.healthmd.domain.model.TimestampedSample
import com.healthmd.domain.model.VitalsData
import com.healthmd.domain.model.WorkoutData
import com.healthmd.domain.model.WorkoutType
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Test
import java.time.Instant
import java.time.LocalDate
import java.time.LocalDateTime
import java.time.ZoneId
import java.time.ZoneOffset
import kotlin.time.Duration.Companion.minutes

class CompatibilityFidelityV5Test {
    private val date = LocalDate.of(2026, 3, 8)

    @Test
    fun legacyPersistedSwitchMigratesToExplicitFrozenSwitches() {
        val migrated = decodePersistedExportSettings(
            """{"formatCustomization":{"includeAndroidCompatibilityKeys":true}}"""
        ).formatCustomization

        assertThat(migrated.includeLegacyAndroidAliases).isTrue()
        assertThat(migrated.includeAndroidNativeFields).isTrue()
        assertThat(migrated.compatibilitySchemaProfile).isEqualTo(CompatibilitySchemaProfile.IOS_V4_FROZEN)
        val output = Json.parseToJsonElement(
            JsonExporter().export(
                HealthData(date, activity = ActivityData(totalCalories = 2100.0, wheelchairPushes = 12)),
                migrated,
            )
        ).jsonObject.getValue("activity").jsonObject
        assertThat(output.containsKey("totalCalories")).isTrue()
        assertThat(output.containsKey("wheelchairPushes")).isTrue()
    }

    @Test
    fun frozenCsvBytesNeverIncludeExactOffsetAwareTimestamp() {
        val local = LocalDateTime.of(2026, 3, 8, 1, 30, 0)
        val exact = ExactSourceTimestamp.from(Instant.parse("2026-03-08T06:30:00.123456789Z"), ZoneOffset.ofHours(-5))
        val data = HealthData(
            date,
            activity = ActivityData(steps = 42, stepSamples = listOf(TimestampedSample(local, 42.0, exactTime = exact))),
        )

        val bytes = CsvExporter().export(
            data,
            decodePersistedExportSettings("{}").formatCustomization,
            includeGranularData = true,
        ).toByteArray(Charsets.UTF_8)

        assertThat(String(bytes, Charsets.UTF_8)).isEqualTo(
            "Date,Category,Metric,Value,Unit,Timestamp\n" +
                "2026-03-08,Activity,Steps,42,count,\n" +
                "2026-03-08,Activity,Steps Sample,42,count,2026-03-08T01:30:00\n",
        )
    }

    @Test
    fun newInstallAndResetDefaultsAreAnalyticalWhileLegacyMigrationStaysFrozen() {
        val reset = ExportSettings.newInstallDefaults().formatCustomization
        val migrated = decodePersistedExportSettings("{}").formatCustomization

        assertThat(reset.compatibilitySchemaProfile).isEqualTo(CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5)
        assertThat(reset.includeAndroidNativeFields).isTrue()
        assertThat(migrated.compatibilitySchemaProfile).isEqualTo(CompatibilitySchemaProfile.IOS_V4_FROZEN)
        assertThat(migrated.includeAndroidNativeFields).isFalse()
    }

    @Suppress("DEPRECATION")
    @Test
    fun deprecatedSerializedSwitchIsNotAnExporterGate() {
        val output = JsonExporter().export(
            HealthData(date, activity = ActivityData(steps = 1, totalCalories = 2000.0)),
            FormatCustomization(includeAndroidCompatibilityKeys = true),
        )
        assertThat(Json.parseToJsonElement(output).jsonObject.getValue("activity").jsonObject.containsKey("totalCalories")).isFalse()
    }

    @Test
    fun aliasesAndNativeValuesAreIndependent() {
        val data = HealthData(
            date = date,
            activity = ActivityData(steps = 10, totalCalories = 2200.0),
            mobility = MobilityData(cyclingCadenceMax = 121.0, stepsCadenceMax = 184.0),
        )
        val nativeOnly = JsonExporter().export(
            data,
            FormatCustomization(
                includeAndroidNativeFields = true,
                compatibilitySchemaProfile = CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5,
            ),
        )
        val root = Json.parseToJsonElement(nativeOnly).jsonObject
        assertThat(root.getValue("activity").jsonObject.getValue("totalCalories").jsonPrimitive.content.toDouble()).isEqualTo(2200.0)
        assertThat(root.getValue("schemaProfile").jsonPrimitive.content).isEqualTo("android-analytical-v5")
        assertThat(root.getValue("mobility").jsonObject.getValue("cyclingCadenceMax").jsonPrimitive.content.toDouble()).isEqualTo(121.0)

        val frozen = JsonExporter().export(data, FormatCustomization(includeLegacyAndroidAliases = true))
        assertThat(Json.parseToJsonElement(frozen).jsonObject.getValue("activity").jsonObject.containsKey("totalCalories")).isFalse()
    }

    @Test
    fun apiV1ForcesFrozenDailyV4ForNewAnalyticalSettings() {
        val settings = ExportSettings(
            formatCustomization = FormatCustomization.analyticalDefault(),
        )
        val payload = APIExportEnvelopeBuilder(JsonExporter()).build(
            records = listOf(HealthData(
                date,
                activity = ActivityData(steps = 10, totalCalories = 2200.0),
                vitals = VitalsData(skinTemperatureDelta = 0.4, skinTemperatureBaseline = 33.1),
            )),
            failedDateDetails = emptyList(),
            settings = settings,
            dateRangeStart = date,
            dateRangeEnd = date,
        )
        val record = Json.parseToJsonElement(payload).jsonObject.getValue("records").jsonArray.single().jsonObject
        assertThat(record.getValue("schema_version").jsonPrimitive.content.toInt()).isEqualTo(4)
        assertThat(record.containsKey("schemaProfile")).isFalse()
        assertThat(record.getValue("activity").jsonObject.containsKey("totalCalories")).isFalse()
        assertThat(record.containsKey("vitals")).isFalse()
    }

    @Test
    fun detailedJsonAndCsvPreserveNanosNullAndNonHourOffsetsAcrossDstDate() {
        val instant = Instant.ofEpochSecond(1_773_000_000L, 987_654_321L)
        val offset = ZoneOffset.ofHoursMinutes(5, 45)
        val exact = ExactSourceTimestamp.from(instant, offset)
        assertThat(exact.offset).isEqualTo("+05:45")
        val identity = ExactSourceIdentity(
            nativeId = "native-1",
            clientRecordId = "client-1",
            clientRecordVersion = 7,
            origin = "com.example.health",
        )
        val local = LocalDateTime.ofInstant(instant, ZoneId.of("America/New_York"))
        val sample = TimestampedSample(local, 42.0, exactTime = exact, identity = identity)
        val data = HealthData(date, activity = ActivityData(steps = 42, stepSamples = listOf(sample)))
        val customization = FormatCustomization(
            includeAndroidNativeFields = true,
            compatibilitySchemaProfile = CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5,
        )

        val root = Json.parseToJsonElement(JsonExporter().export(data, customization, includeGranularData = true)).jsonObject
        val emittedSample = root.getValue("activity").jsonObject.getValue("stepSamples").jsonArray.single().jsonObject
        val emitted = emittedSample.getValue("exactTime").jsonObject
        assertThat(emitted.getValue("epochSecond").jsonPrimitive.content.toLong()).isEqualTo(instant.epochSecond)
        assertThat(emitted.getValue("nano").jsonPrimitive.content.toInt()).isEqualTo(987_654_321)
        assertThat(emitted.getValue("offset").jsonPrimitive.content).isEqualTo("+05:45")
        assertThat(emitted.getValue("iso8601").jsonPrimitive.content).isEqualTo(exact.toIso8601())
        val emittedIdentity = emittedSample.getValue("identity").jsonObject
        assertThat(emittedIdentity.getValue("nativeId").jsonPrimitive.content).isEqualTo("native-1")
        assertThat(emittedIdentity.getValue("clientRecordVersion").jsonPrimitive.content.toLong()).isEqualTo(7L)
        assertThat(emittedIdentity.getValue("origin").jsonPrimitive.content).isEqualTo("com.example.health")
        assertThat(JsonExporter().export(data.copy(activity = data.activity.copy(stepSamples = listOf(sample.copy(exactTime = exact.copy(offset = null))))), customization, true))
            .contains("\"offset\": null")
        assertThat(emitted.toString()).doesNotContain("America/New_York")

        val csv = CsvExporter().export(data, customization, includeGranularData = true)
        assertThat(csv).contains(exact.toIso8601())
    }

    @Test
    fun frozenDetailedExportsKeepCanonicalFractionsAndDoNotLeakSkinTemperature() {
        val sample = TimestampedSample(LocalDateTime.of(2026, 3, 8, 9, 0), 0.975)
        val data = HealthData(
            date,
            vitals = VitalsData(
                bloodOxygenAvg = 0.975,
                bloodOxygenSamples = listOf(sample),
                skinTemperatureDelta = 0.4,
                skinTemperatureBaseline = 33.1,
                skinTemperatureDeltas = listOf(TimestampedSample(sample.time, 0.4)),
            ),
        )

        val json = Json.parseToJsonElement(JsonExporter().export(data, includeGranularData = true)).jsonObject
        val vitals = json.getValue("vitals").jsonObject
        assertThat(vitals.getValue("bloodOxygenSamples").jsonArray.single().jsonObject.getValue("value").jsonPrimitive.content.toDouble())
            .isEqualTo(0.975)
        assertThat(vitals.containsKey("skinTemperatureDelta")).isFalse()
        assertThat(vitals.containsKey("skinTemperatureBaseline")).isFalse()
        assertThat(vitals.containsKey("skinTemperatureDeltas")).isFalse()
        assertThat(CsvExporter().export(data, includeGranularData = true)).contains("Blood Oxygen Sample,97.5,percent")
        assertThat(com.healthmd.data.export.MarkdownExporter().export(data, includeGranularData = true)).contains("| 09:00 | 97.5 |")

        val analytical = Json.parseToJsonElement(
            JsonExporter().export(data, FormatCustomization.analyticalDefault(), includeGranularData = true)
        ).jsonObject.getValue("vitals").jsonObject
        assertThat(analytical.containsKey("skinTemperatureDelta")).isTrue()
        assertThat(analytical.containsKey("skinTemperatureBaseline")).isTrue()
        assertThat(analytical.containsKey("skinTemperatureDeltas")).isTrue()
    }

    @Test
    fun analyticalCadenceSeriesAreTypedByDistinctCanonicalKeysWhileFrozenAliasRemains() {
        val time = LocalDateTime.of(2026, 3, 8, 10, 0)
        val workout = WorkoutData(
            WorkoutType.CYCLING,
            time,
            duration = 30.minutes,
            cyclingCadenceSamples = listOf(TimestampedSample(time, 90.0)),
            stepsCadenceSamples = listOf(TimestampedSample(time.plusMinutes(1), 170.0)),
        )
        val data = HealthData(date, workouts = listOf(workout))

        val frozenSeries = Json.parseToJsonElement(JsonExporter().export(data, includeGranularData = true)).jsonObject
            .getValue("workouts").jsonArray.single().jsonObject.getValue("timeSeries").jsonObject
        assertThat(frozenSeries.getValue("cadence").jsonArray).hasSize(2)
        assertThat(frozenSeries.containsKey("cyclingCadence")).isFalse()
        assertThat(frozenSeries.containsKey("stepsCadence")).isFalse()

        val analyticalSeries = Json.parseToJsonElement(
            JsonExporter().export(data, FormatCustomization.analyticalDefault(), includeGranularData = true)
        ).jsonObject.getValue("workouts").jsonArray.single().jsonObject.getValue("timeSeries").jsonObject
        assertThat(analyticalSeries.containsKey("cadence")).isFalse()
        assertThat(analyticalSeries.getValue("cyclingCadence").jsonArray).hasSize(1)
        assertThat(analyticalSeries.getValue("stepsCadence").jsonArray).hasSize(1)
    }

    @Test
    fun exactInstantsDisambiguateRepeatedLocalTimeAtDstFallBack() {
        val zone = ZoneId.of("America/New_York")
        val firstInstant = Instant.parse("2026-11-01T05:30:00.000000001Z")
        val secondInstant = Instant.parse("2026-11-01T06:30:00.000000001Z")
        val firstLocal = LocalDateTime.ofInstant(firstInstant, zone)
        val secondLocal = LocalDateTime.ofInstant(secondInstant, zone)
        assertThat(firstLocal).isEqualTo(secondLocal)

        val first = ExactSourceTimestamp.from(firstInstant, ZoneOffset.ofHours(-4))
        val second = ExactSourceTimestamp.from(secondInstant, ZoneOffset.ofHours(-5))
        assertThat(first.toIso8601()).isNotEqualTo(second.toIso8601())
        assertThat(first.nano).isEqualTo(1)
        assertThat(second.nano).isEqualTo(1)
    }

    @Test
    fun syntheticIdentityIsStableAndExplicit() {
        val first = ExactSourceIdentity(syntheticId = "stable-derived-id", isSynthetic = true)
        val second = first.copy()
        assertThat(second).isEqualTo(first)
        assertThat(first.isSynthetic).isTrue()
        assertThat(first.nativeId).isNull()
    }
}
