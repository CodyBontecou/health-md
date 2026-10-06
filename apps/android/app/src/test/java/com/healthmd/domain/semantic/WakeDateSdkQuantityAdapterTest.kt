package com.healthmd.domain.semantic

import com.google.common.truth.Truth.assertThat
import com.healthmd.core.HEALTHMD_SLEEP_REGISTRY_SHA256
import com.healthmd.domain.model.*
import com.healthmd.domain.render.NativeRenderRequestFixtureTest
import java.nio.file.Files
import java.nio.file.Path
import java.time.LocalDate
import java.time.ZoneId
import kotlin.time.Duration.Companion.seconds
import kotlinx.serialization.json.*
import org.junit.Assert.assertThrows
import org.junit.Test

/** Synthetic post-capture SDK facts: these tests do not qualify SDK owner-date capture. */
class WakeDateSdkQuantityAdapterTest {
    private val context = AndroidCaptureContext(ZoneId.of("America/New_York"), SleepDayAttribution.MORNING_ENDS)
    private val profile = HealthMdSemanticInputAdapter.Profile.SLEEP_V6
    private val registry by lazy {
        var root = Path.of(System.getProperty("user.dir")).toAbsolutePath()
        while (!Files.isDirectory(root.resolve("packages/contracts"))) root = requireNotNull(root.parent)
        NativeRenderRequestFixtureTest().registry(
            Json.parseToJsonElement(Files.readAllBytes(root.resolve("packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v2.json")).decodeToString()).jsonObject,
            "android_sleep_v6", HEALTHMD_SLEEP_REGISTRY_SHA256,
        )
    }

    @Test
    fun sdkScalarMatrixDoesNotRoundOrConvertThroughPresentationPreferences() {
        val data = HealthData(
            date = LocalDate.of(2026, 11, 1),
            sleep = SleepData(totalDuration = 450.seconds, lightSleep = 225.seconds, deepSleep = 450.seconds,
                remSleep = 450.seconds, awakeTime = 450.seconds, inBedTime = 450.seconds),
            activity = ActivityData(steps = Int.MAX_VALUE, activeCalories = 3.125, totalCalories = 3.125,
                exerciseMinutes = 3.125, flightsClimbed = 7, walkingRunningDistance = 3.125,
                basalEnergyBurned = 3.125, cyclingDistance = 3.125, elevationGained = 3.125,
                wheelchairPushes = 7, swimmingDistance = 3.125, swimmingStrokes = 7, wheelchairDistance = 3.125,
                downhillSnowSportsDistance = 3.125, moderateActivityMinutes = 3.125, vigorousActivityMinutes = 3.125,
                activityIntensityMinutes = 7),
            heart = HeartData(restingHeartRate = 3.125, averageHeartRate = 3.125, walkingHeartRateAverage = 3.125,
                hrv = 3.125, heartRateMin = 3.125, heartRateMax = 3.125),
            vitals = VitalsData(respiratoryRateAvg = 3.125, respiratoryRateMin = 3.125, respiratoryRateMax = 3.125,
                bloodOxygenAvg = 0.96875, bloodOxygenMin = 0.96875, bloodOxygenMax = 0.96875,
                bodyTemperatureAvg = 3.125, bodyTemperatureMin = 3.125, bodyTemperatureMax = 3.125,
                bloodPressureSystolicAvg = 3.125, bloodPressureSystolicMin = 3.125, bloodPressureSystolicMax = 3.125,
                bloodPressureDiastolicAvg = 3.125, bloodPressureDiastolicMin = 3.125, bloodPressureDiastolicMax = 3.125,
                bloodGlucoseAvg = 3.125, bloodGlucoseMin = 3.125, bloodGlucoseMax = 3.125,
                basalBodyTemperature = 3.125, skinTemperatureDelta = 3.125),
            body = BodyData(weight = 3.125, height = 3.125, bmi = 3.125, bodyFatPercentage = 0.21875,
                leanBodyMass = 3.125, bodyWaterMass = 3.125, boneMass = 3.125),
            nutrition = NutritionData(dietaryEnergy = 3.125, protein = 3.125, carbohydrates = 3.125, fat = 3.125,
                fiber = 3.125, sugar = 3.125, sodium = 3.125, water = 3.125, caffeine = 3.125, cholesterol = 3.125,
                saturatedFat = 3.125, monounsaturatedFat = 3.125, polyunsaturatedFat = 3.125, unsaturatedFat = 3.125,
                transFat = 3.125, potassium = 3.125, calcium = 3.125, iron = 3.125, magnesium = 3.125, zinc = 3.125,
                phosphorus = 3.125, iodine = 3.125, selenium = 3.125, copper = 3.125, manganese = 3.125,
                chromium = 3.125, molybdenum = 3.125, chloride = 3.125, vitaminA = 3.125, vitaminB6 = 3.125,
                vitaminB12 = 3.125, vitaminC = 3.125, vitaminD = 3.125, vitaminE = 3.125, vitaminK = 3.125,
                thiamin = 3.125, riboflavin = 3.125, niacin = 3.125, folate = 3.125, folicAcid = 3.125,
                pantothenicAcid = 3.125, biotin = 3.125, energyFromFat = 3.125),
            mobility = MobilityData(walkingSpeed = 3.125, vo2Max = 3.125, cyclingCadenceAvg = 3.125,
                cyclingCadenceMax = 3.125, stepsCadenceAvg = 3.125, stepsCadenceMax = 3.125, powerAvg = 3.125,
                powerMax = 3.125, runningSpeed = 3.125, runningPowerAvg = 3.125, runningPowerMax = 3.125),
            mindfulness = MindfulnessData(mindfulnessMinutes = 3.125, mindfulSessions = 7),
        )
        val metric = batch(data, UnitPreference.METRIC)
        assertThat(batch(data, UnitPreference.IMPERIAL)).isEqualTo(metric)
        val records = metric.getValue("records").jsonArray.associate {
            it.jsonObject.getValue("output_key").jsonPrimitive.content to it.jsonObject.getValue("value").jsonObject
        }
        val expectedDecimals = """
            sleep_total_hours sleep_deep_hours sleep_rem_hours sleep_awake_hours sleep_in_bed_hours
            active_calories total_calories basal_calories exercise_minutes walking_running_km cycling_km
            cycling_cadence_rpm cycling_power_w elevation_gained_m swimming_m wheelchair_km downhill_snow_km
            moderate_activity_minutes vigorous_activity_minutes resting_heart_rate average_heart_rate walking_heart_rate
            heart_rate_min heart_rate_max hrv_ms respiratory_rate respiratory_rate_avg respiratory_rate_min respiratory_rate_max
            body_temperature body_temperature_avg body_temperature_min body_temperature_max blood_pressure_systolic
            blood_pressure_systolic_avg blood_pressure_systolic_min blood_pressure_systolic_max blood_pressure_diastolic
            blood_pressure_diastolic_avg blood_pressure_diastolic_min blood_pressure_diastolic_max blood_glucose
            blood_glucose_avg blood_glucose_min blood_glucose_max basal_body_temperature skin_temperature_delta
            weight_kg height_m bmi lean_body_mass_kg body_water_mass_kg bone_mass_kg dietary_calories protein_g
            carbohydrates_g fat_g saturated_fat_g monounsaturated_fat_g polyunsaturated_fat_g unsaturated_fat_g
            trans_fat_g fiber_g sugar_g sodium_mg potassium_mg calcium_mg iron_mg magnesium_mg zinc_mg phosphorus_mg
            iodine_ug selenium_ug copper_mg manganese_mg chromium_ug molybdenum_ug chloride_mg vitamin_a_ug
            vitamin_b6_mg vitamin_b12_ug vitamin_c_mg vitamin_d_ug vitamin_e_mg vitamin_k_ug thiamin_mg riboflavin_mg
            niacin_mg folate_ug folic_acid_mcg pantothenic_acid_mg biotin_ug cholesterol_mg water_l caffeine_mg
            energy_from_fat_kcal walking_speed vo2_max cycling_cadence cycling_cadence_max steps_cadence steps_cadence_max
            power_max running_speed running_power_w running_power_max mindful_minutes
        """.trimIndent().split(Regex("\\s+")).toSet()
        for (key in expectedDecimals) {
            val expected = if (key.startsWith("sleep_")) 0.125 else 3.125
            assertThat(bits(records.getValue(key))).isEqualTo(expected.toBits())
        }
        assertThat(bits(records.getValue("sleep_light_hours"))).isEqualTo(0.0625.toBits())
        for (key in listOf("blood_oxygen", "blood_oxygen_avg", "blood_oxygen_min", "blood_oxygen_max")) {
            assertThat(bits(records.getValue(key))).isEqualTo(0.96875.toBits())
            assertThat(records.getValue(key).getValue("unit").jsonObject.getValue("id").jsonPrimitive.content).isEqualTo("ratio_0_1")
        }
        assertThat(bits(records.getValue("body_fat_percent"))).isEqualTo(0.21875.toBits())
        val expectedCounts = mapOf("steps" to Int.MAX_VALUE, "flights_climbed" to 7, "wheelchair_pushes" to 7,
            "swimming_strokes" to 7, "activity_intensity_minutes" to 7, "mindful_sessions" to 7)
        for ((key, count) in expectedCounts) {
            val number = records.getValue(key).getValue("number").jsonObject
            assertThat(number.getValue("representation").jsonPrimitive.content).isEqualTo("signed_integer")
            assertThat(number.getValue("decimal").jsonPrimitive.content).isEqualTo(count.toString())
        }
        assertThat(records.keys).containsExactlyElementsIn(expectedDecimals + expectedCounts.keys +
            setOf("sleep_light_hours", "body_fat_percent", "blood_oxygen", "blood_oxygen_avg", "blood_oxygen_min", "blood_oxygen_max"))
        assertThat(records.getValue("height_m").getValue("unit").jsonObject.getValue("id").jsonPrimitive.content).isEqualTo("meter")
        assertThat(records.getValue("water_l").getValue("unit").jsonObject.getValue("id").jsonPrimitive.content).isEqualTo("liter")
    }

    @Test
    fun emptyAndNonFiniteSdkQuantitiesDoNotBecomeRoundedSuccessorFacts() {
        val empty = HealthData(LocalDate.of(2026, 11, 1))
        assertThat(batch(empty, UnitPreference.METRIC).getValue("records").jsonArray).isEmpty()
        for (invalid in listOf(Double.NaN, Double.POSITIVE_INFINITY, Double.NEGATIVE_INFINITY)) {
            assertThrows(HealthMdSemanticInputAdapter.AdapterException::class.java) {
                batch(empty.copy(body = BodyData(weight = invalid)), UnitPreference.METRIC)
            }
        }
    }

    private fun batch(data: HealthData, units: UnitPreference): JsonObject = Json.parseToJsonElement(
        HealthMdSemanticInputAdapter.batch("native-sdk-quantity", profile, 0u, true, listOf(data), registry,
            UnitConverter(units), context.zoneId.id, captureContext = context).bytes.decodeToString(),
    ).jsonObject

    private fun bits(value: JsonObject): Long {
        val number = value.getValue("number").jsonObject
        assertThat(number.getValue("representation").jsonPrimitive.content).isEqualTo("binary64")
        return number.getValue("bits").jsonPrimitive.content.toULong(16).toLong()
    }
}
