package com.healthmd.rawexport

import androidx.health.connect.client.feature.ExperimentalPersonalHealthRecordApi
import androidx.health.connect.client.records.*
import androidx.health.connect.client.records.metadata.Metadata
import androidx.health.connect.client.units.*
import com.google.common.truth.Truth.assertThat
import io.mockk.every
import io.mockk.mockk
import java.time.Duration
import java.time.Instant
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlin.reflect.KFunction
import kotlin.reflect.KParameter
import kotlin.reflect.full.primaryConstructor
import org.junit.Test

@OptIn(ExperimentalPersonalHealthRecordApi::class)
class HealthConnectRawMappingTest {
    @Test fun catalogHasMapperPermissionMetricsAndUniqueWireTypeForEveryEntry() {
        val records = HealthConnectRecordCatalog.records
        assertThat(records).hasSize(42)
        assertThat(records.map { it.recordClass }).containsNoDuplicates()
        assertThat(records.map { it.wireType }).containsNoDuplicates()
        assertThat(records.all { it.readPermission.isNotBlank() }).isTrue()
        assertThat(records.all { it.metricIds.isNotEmpty() }).isTrue()
        assertThat(records.all { it.mapper != null }).isTrue()
        assertThat(HealthConnectRecordCatalog.selected(setOf("running_power")).map { it.wireType })
            .containsAtLeast("exercise_session", "power")
        assertThat(records.map { it.rangeBehavior }.all { it == RawRangeBehavior.INSTANT || it == RawRangeBehavior.OVERLAP }).isTrue()
        assertThat(RawExportTypeCatalog.definitions).hasSize(54)
        assertThat(RawExportTypeCatalog.definitions.map { it.typeKey }).containsNoDuplicates()
    }

    @Test fun everyCatalogClassUsesARealSdkConstructorThenMapsAndTypedDecodes() {
        val failures = mutableListOf<String>()
        HealthConnectRecordCatalog.records.forEach { descriptor ->
            runCatching {
                val native = realSdkFixture(descriptor.recordClass.primaryConstructor
                    ?: error("no primary SDK constructor"))
                val mapped = checkNotNull(descriptor.mapUntyped(native))
                check(mapped.wireType == descriptor.wireType)
                check(mapped.hash.length == 64)
                val typed = RawRecordDecoder.decode(
                    RawJson.codec.parseToJsonElement(RawJson.canonicalRecord(mapped)).jsonObject,
                )
                check(typed.wireType == descriptor.wireType)
                check(typed.fields !is DecodedFields.Provider)
            }.onFailure { failures += "${descriptor.wireType}: ${it::class.simpleName}: ${it.message}" }
        }
        assertThat(failures).isEmpty()
    }

    @Test fun everySampleCollectionRetainsNanosNativeOrderAndCanonicalUnits() {
        val metadata = Metadata.manualEntry(clientRecordId = "samples")
        val records = listOf(
            RawHealthConnectMapper.map(SpeedRecord(
                Instant.ofEpochSecond(1), null, Instant.ofEpochSecond(5), null,
                listOf(SpeedRecord.Sample(Instant.ofEpochSecond(3, 9), Velocity.metersPerSecond(2.5)), SpeedRecord.Sample(Instant.ofEpochSecond(2, 8), Velocity.metersPerSecond(1.5))), metadata,
            ), "speed"),
            RawHealthConnectMapper.map(PowerRecord(
                Instant.ofEpochSecond(1), null, Instant.ofEpochSecond(5), null,
                listOf(PowerRecord.Sample(Instant.ofEpochSecond(3, 9), Power.watts(250.0)), PowerRecord.Sample(Instant.ofEpochSecond(2, 8), Power.watts(200.0))), metadata,
            ), "power"),
            RawHealthConnectMapper.map(CyclingPedalingCadenceRecord(
                Instant.ofEpochSecond(1), null, Instant.ofEpochSecond(5), null,
                listOf(CyclingPedalingCadenceRecord.Sample(Instant.ofEpochSecond(3, 9), 91.0), CyclingPedalingCadenceRecord.Sample(Instant.ofEpochSecond(2, 8), 87.0)), metadata,
            ), "cycling_pedaling_cadence"),
            RawHealthConnectMapper.map(StepsCadenceRecord(
                Instant.ofEpochSecond(1), null, Instant.ofEpochSecond(5), null,
                listOf(StepsCadenceRecord.Sample(Instant.ofEpochSecond(3, 9), 121.0), StepsCadenceRecord.Sample(Instant.ofEpochSecond(2, 8), 115.0)), metadata,
            ), "steps_cadence"),
            RawHealthConnectMapper.map(SkinTemperatureRecord(
                startTime = Instant.ofEpochSecond(1), startZoneOffset = null,
                endTime = Instant.ofEpochSecond(5), endZoneOffset = null,
                metadata = metadata,
                deltas = listOf(SkinTemperatureRecord.Delta(Instant.ofEpochSecond(3, 9), TemperatureDelta.celsius(0.4)), SkinTemperatureRecord.Delta(Instant.ofEpochSecond(2, 8), TemperatureDelta.celsius(0.2))),
                measurementLocation = SkinTemperatureRecord.MEASUREMENT_LOCATION_WRIST,
                baseline = Temperature.celsius(33.0),
            ), "skin_temperature"),
        )
        val decoded = records.map { RawRecordDecoder.decode(RawJson.codec.parseToJsonElement(RawJson.canonicalRecord(it)).jsonObject) }
        decoded.forEach { record ->
            val times = when (val fields = record.fields) {
                is DecodedFields.QuantitySamples -> fields.samples.map { it.time }
                is DecodedFields.DoubleSamples -> fields.samples.map { it.time }
                is DecodedFields.SkinTemperature -> fields.deltas.map { it.time }
                else -> error("unexpected sample payload")
            }
            assertThat(times.map { it.nano }).containsExactly(8, 9).inOrder()
        }
        assertThat(((decoded[0].fields as DecodedFields.QuantitySamples).samples.last().value).unit).isEqualTo("m/s")
        assertThat(((decoded[1].fields as DecodedFields.QuantitySamples).samples.last().value).number).isEqualTo(250.0)
        assertThat(((decoded[4].fields as DecodedFields.SkinTemperature).deltas.last().value).type).isEqualTo("TemperatureDelta")
    }

    @Test fun sleepSessionHasExplicitIntervalTemporalDispatch() {
        val record = SleepSessionRecord(
            startTime = Instant.ofEpochSecond(10, 1),
            startZoneOffset = null,
            endTime = Instant.ofEpochSecond(20, 2),
            endZoneOffset = null,
            metadata = Metadata.manualEntry(),
            title = null,
            notes = null,
            stages = (0..7).map { raw ->
                SleepSessionRecord.Stage(Instant.ofEpochSecond(11L + raw), Instant.ofEpochSecond(12L + raw), raw)
            },
        )
        val mapped = RawHealthConnectMapper.map(record, "sleep_session")
        val decoded = RawRecordDecoder.decode(
            RawJson.codec.parseToJsonElement(RawJson.canonicalRecord(mapped)).jsonObject,
        ).fields as DecodedFields.Sleep
        assertThat(mapped.startTime).isEqualTo(RawInstant(10, 1))
        assertThat(mapped.endTime).isEqualTo(RawInstant(20, 2))
        assertThat(mapped.fields.getValue("stages").jsonArray).hasSize(8)
        assertThat(decoded.stages.map { it.stage.raw }).containsExactlyElementsIn(0..7).inOrder()
    }

    @Test fun exerciseRouteStatesRemainDistinctAndDataRouteRetainsExactOrderedPoints() {
        val route = ExerciseRoute(listOf(
            ExerciseRoute.Location(Instant.ofEpochSecond(12, 5), 45.25, -122.75, Length.meters(3.0), Length.meters(4.0), Length.meters(100.0)),
            ExerciseRoute.Location(Instant.ofEpochSecond(13, 6), 45.5, -122.5, null, null, null),
        ))
        val native = ExerciseSessionRecord(
            startTime = Instant.ofEpochSecond(10), startZoneOffset = null,
            endTime = Instant.ofEpochSecond(20), endZoneOffset = null,
            metadata = Metadata.manualEntry(clientRecordId = "route"),
            exerciseType = ExerciseSessionRecord.EXERCISE_TYPE_RUNNING,
            segments = listOf(ExerciseSegment(Instant.ofEpochSecond(11), Instant.ofEpochSecond(14), ExerciseSegment.EXERCISE_SEGMENT_TYPE_RUNNING, 2)),
            laps = listOf(ExerciseLap(Instant.ofEpochSecond(11), Instant.ofEpochSecond(15), Length.meters(500.0))),
            exerciseRoute = route,
        )
        val mappedObject = RawJson.codec.parseToJsonElement(
            RawJson.canonicalRecord(RawHealthConnectMapper.map(native, "exercise_session")),
        ).jsonObject
        val data = (RawRecordDecoder.decode(mappedObject).fields as DecodedFields.Exercise).route!!
        assertThat(data.state).isEqualTo(RawRouteState.DATA)
        assertThat(data.locations.map { it.time.nano }).containsExactly(5, 6).inOrder()
        assertThat(data.locations.first().altitude!!.number).isEqualTo(100.0)

        val noDataRecord = ExerciseSessionRecord(
            startTime = Instant.ofEpochSecond(10), startZoneOffset = null,
            endTime = Instant.ofEpochSecond(20), endZoneOffset = null,
            metadata = Metadata.manualEntry(clientRecordId = "no-route"),
            exerciseType = ExerciseSessionRecord.EXERCISE_TYPE_RUNNING,
        )
        val noDataObject = RawJson.codec.parseToJsonElement(
            RawJson.canonicalRecord(RawHealthConnectMapper.map(noDataRecord, "exercise_session")),
        ).jsonObject
        assertThat((RawRecordDecoder.decode(noDataObject).fields as DecodedFields.Exercise).route!!.state)
            .isEqualTo(RawRouteState.NO_DATA)

        val consentFields = JsonObject(noDataObject.getValue("fields").jsonObject + (
            "route" to JsonObject(mapOf("state" to JsonPrimitive("consent_required"), "locations" to JsonArray(emptyList())))
        ))
        val consentObject = JsonObject(noDataObject + ("fields" to consentFields))
        assertThat((RawRecordDecoder.decode(consentObject).fields as DecodedFields.Exercise).route!!.state)
            .isEqualTo(RawRouteState.CONSENT_REQUIRED)
    }

    @Test fun plannedExerciseNestedManualCompletionUsesExplicitDiscriminator() {
        val step = PlannedExerciseStep(
            exerciseType = ExerciseSessionRecord.EXERCISE_TYPE_RUNNING,
            exercisePhase = PlannedExerciseStep.EXERCISE_PHASE_ACTIVE,
            completionGoal = ExerciseCompletionGoal.ManualCompletion,
            performanceTargets = emptyList(),
            description = "Finish when form degrades",
        )
        val record = PlannedExerciseSessionRecord(
            startTime = Instant.ofEpochSecond(100, 1),
            startZoneOffset = null,
            endTime = Instant.ofEpochSecond(200, 2),
            endZoneOffset = null,
            metadata = Metadata.manualEntry(clientRecordId = "manual-plan", clientRecordVersion = 1),
            blocks = listOf(PlannedExerciseBlock(2, listOf(step), "Main set")),
            exerciseType = ExerciseSessionRecord.EXERCISE_TYPE_RUNNING,
            title = "Manual plan",
            notes = null,
        )

        val mapped = RawHealthConnectMapper.map(record, "planned_exercise_session")
        val goal = mapped.fields.getValue("blocks").jsonArray.single().jsonObject
            .getValue("steps").jsonArray.single().jsonObject
            .getValue("completionGoal").jsonObject

        assertThat(goal.keys).containsExactly("type")
        assertThat(goal.getValue("type").jsonPrimitive.content).isEqualTo("manual_completion")
    }

    @Test fun medicalResourcePreservesExactFhirAndAllowsMissingSource() {
        val exact = "{\n  \"resourceType\": \"Immunization\", \"value\": 1.00\n}"
        val resourceId = mockk<MedicalResourceId> {
            every { dataSourceId } returns "source"
            every { fhirResourceType } returns FhirResource.FHIR_RESOURCE_TYPE_IMMUNIZATION
            every { fhirResourceId } returns "fhir-id"
        }
        val version = mockk<FhirVersion> {
            every { major } returns 4
            every { minor } returns 0
            every { patch } returns 1
        }
        val fhir = mockk<FhirResource> {
            every { type } returns FhirResource.FHIR_RESOURCE_TYPE_IMMUNIZATION
            every { id } returns "fhir-id"
            every { data } returns exact
        }
        val resource = mockk<MedicalResource> {
            every { type } returns MedicalResource.MEDICAL_RESOURCE_TYPE_VACCINES
            every { id } returns resourceId
            every { dataSourceId } returns "source"
            every { fhirVersion } returns version
            every { fhirResource } returns fhir
        }
        val mapped = RawMedicalResourceMapper.map(resource, null)
        val decoded = RawRecordDecoder.decode(
            RawJson.codec.parseToJsonElement(RawJson.canonicalRecord(mapped)).jsonObject,
        )
        val medical = (decoded.fields as DecodedFields.Medical).payload
        assertThat(medical.fhirResource.exactJson).isEqualTo(exact)
        assertThat(medical.source).isNull()
        assertThat(mapped.fields.getValue("source").toString()).isEqualTo("null")
        assertThat(mapped.fields.getValue("fhirResource").jsonObject.getValue("fhirResourceJson").jsonPrimitive.content).isEqualTo(exact)
        assertThat(mapped.fields.getValue("fhirResource").jsonObject.getValue("checksumSha256").jsonPrimitive.content)
            .isEqualTo(RawJson.sha256(exact.toByteArray()))
    }

    @Test fun nutritionRealConstructorRoundTripsEveryNullableNutrientAsPresentValues() {
        val descriptor = HealthConnectRecordCatalog.records.single { it.wireType == "nutrition" }
        val native = realSdkFixture(requireNotNull(descriptor.recordClass.primaryConstructor), fillNullableValues = true)
        val decoded = RawRecordDecoder.decode(
            RawJson.codec.parseToJsonElement(RawJson.canonicalRecord(requireNotNull(descriptor.mapUntyped(native)))).jsonObject,
        )
        val nutrition = decoded.fields as DecodedFields.Nutrition
        assertThat(nutrition.nutrients).hasSize(42)
        assertThat(nutrition.nutrients.values).doesNotContain(null)
    }

    @Test fun plannedExerciseAllGoalAndTargetVariantsRetainProviderOrderAndUnits() {
        val goals = listOf<ExerciseCompletionGoal>(
            ExerciseCompletionGoal.DistanceGoal(Length.meters(100.0)),
            ExerciseCompletionGoal.DistanceAndDurationGoal(Length.meters(200.0), Duration.ofSeconds(60, 7)),
            ExerciseCompletionGoal.StepsGoal(300),
            ExerciseCompletionGoal.DurationGoal(Duration.ofSeconds(30, 8)),
            ExerciseCompletionGoal.RepetitionsGoal(4),
            ExerciseCompletionGoal.TotalCaloriesBurnedGoal(Energy.kilocalories(5.0)),
            ExerciseCompletionGoal.ActiveCaloriesBurnedGoal(Energy.kilocalories(6.0)),
            ExerciseCompletionGoal.ManualCompletion,
            ExerciseCompletionGoal.UnknownGoal,
        )
        val targets = listOf<ExercisePerformanceTarget>(
            ExercisePerformanceTarget.PowerTarget(Power.watts(10.0), Power.watts(20.0)),
            ExercisePerformanceTarget.SpeedTarget(Velocity.metersPerSecond(1.0), Velocity.metersPerSecond(2.0)),
            ExercisePerformanceTarget.CadenceTarget(70.0, 90.0),
            ExercisePerformanceTarget.HeartRateTarget(100.0, 150.0),
            ExercisePerformanceTarget.WeightTarget(Mass.kilograms(12.0)),
            ExercisePerformanceTarget.RateOfPerceivedExertionTarget(7),
            ExercisePerformanceTarget.AmrapTarget,
            ExercisePerformanceTarget.UnknownTarget,
        )
        val steps = goals.mapIndexed { index, goal ->
            PlannedExerciseStep(
                exerciseType = ExerciseSessionRecord.EXERCISE_TYPE_RUNNING,
                exercisePhase = PlannedExerciseStep.EXERCISE_PHASE_ACTIVE,
                completionGoal = goal,
                performanceTargets = if (index == 0) targets else emptyList(),
                description = "step-$index",
            )
        }
        val native = PlannedExerciseSessionRecord(
            startTime = Instant.ofEpochSecond(100, 1), startZoneOffset = null,
            endTime = Instant.ofEpochSecond(200, 2), endZoneOffset = null,
            metadata = Metadata.manualEntry(clientRecordId = "all-plan-variants", clientRecordVersion = 2),
            blocks = listOf(PlannedExerciseBlock(2, steps, "ordered")),
            exerciseType = ExerciseSessionRecord.EXERCISE_TYPE_RUNNING,
            title = "Plan", notes = "Exact",
        )
        val decoded = RawRecordDecoder.decode(
            RawJson.codec.parseToJsonElement(RawJson.canonicalRecord(RawHealthConnectMapper.map(native, "planned_exercise_session"))).jsonObject,
        ).fields as DecodedFields.PlannedExercise
        assertThat(decoded.blocks.single().steps.map { it.completionGoal::class.simpleName }).containsExactly(
            "Distance", "DistanceAndDuration", "Steps", "Duration", "Repetitions", "TotalCalories", "ActiveCalories", "ManualCompletion", "Unknown",
        ).inOrder()
        assertThat(decoded.blocks.single().steps.first().performanceTargets.map { it::class.simpleName }).containsExactly(
            "Power", "Speed", "Cadence", "HeartRate", "Weight", "Rpe", "Amrap", "Unknown",
        ).inOrder()
    }

    private fun realSdkFixture(constructor: KFunction<Record>, fillNullableValues: Boolean = false): Record {
        val arguments = linkedMapOf<KParameter, Any?>()
        constructor.parameters.forEach { parameter ->
            val name = parameter.name.orEmpty()
            val classifier = parameter.type.classifier
            val value: Any? = when {
                name == "metadata" -> Metadata.manualEntry(clientRecordId = "real-${constructor.returnType}", clientRecordVersion = 1)
                name == "time" || name == "startTime" -> Instant.ofEpochSecond(10, 123)
                name == "endTime" -> Instant.ofEpochSecond(20, 456)
                name.endsWith("ZoneOffset") || name == "zoneOffset" -> null
                parameter.type.isMarkedNullable && !fillNullableValues -> null
                classifier == List::class -> emptyList<Any>()
                classifier == Long::class -> 1L
                classifier == Int::class -> 0
                classifier == Double::class -> 1.0
                classifier == Boolean::class -> true
                classifier == String::class -> "fixture"
                classifier == Length::class -> Length.meters(1.0)
                classifier == Energy::class -> Energy.kilocalories(1.0)
                classifier == Power::class -> Power.watts(1.0)
                classifier == Pressure::class -> Pressure.millimetersOfMercury(100.0)
                classifier == BloodGlucose::class -> BloodGlucose.millimolesPerLiter(1.0)
                classifier == Percentage::class -> Percentage(50.0)
                classifier == Temperature::class -> Temperature.celsius(37.0)
                classifier == TemperatureDelta::class -> TemperatureDelta.celsius(1.0)
                classifier == Mass::class -> if (fillNullableValues) Mass.grams(1.0) else Mass.kilograms(1.0)
                classifier == Volume::class -> Volume.liters(1.0)
                classifier == Velocity::class -> Velocity.metersPerSecond(1.0)
                parameter.isOptional -> return@forEach
                else -> error("unsupported constructor parameter $name: ${parameter.type}")
            }
            arguments[parameter] = value
        }
        return constructor.callBy(arguments)
    }

    @Test fun heartRateMappingPreservesNanosNullOffsetsSamplesAndDeterministicIdentity() {
        val start = Instant.ofEpochSecond(100, 123_456_789)
        val end = Instant.ofEpochSecond(101, 987_654_321)
        val record = HeartRateRecord(
            startTime = start,
            startZoneOffset = null,
            endTime = end,
            endZoneOffset = null,
            samples = listOf(
                HeartRateRecord.Sample(Instant.ofEpochSecond(100, 999), 61),
                HeartRateRecord.Sample(Instant.ofEpochSecond(100, 12), 60),
            ),
            metadata = Metadata.manualEntry(clientRecordId = "client-heart", clientRecordVersion = 4),
        )
        val mapped = RawHealthConnectMapper.map(record, "heart_rate")
        assertThat(mapped.startTime).isEqualTo(RawInstant(100, 123_456_789))
        assertThat(mapped.endTime).isEqualTo(RawInstant(101, 987_654_321))
        assertThat(mapped.startZoneOffsetSeconds).isNull()
        assertThat(mapped.endZoneOffsetSeconds).isNull()
        assertThat(mapped.nativeIdentity).isEqualTo("client::client-heart:4")
        assertThat(mapped.hash).hasLength(64)
        val samples = mapped.fields.getValue("samples").jsonArray
        assertThat(samples[0].jsonObject.getValue("beatsPerMinute").jsonPrimitive.content.toLong()).isEqualTo(60)
        assertThat(samples[1].jsonObject.getValue("beatsPerMinute").jsonPrimitive.content.toLong()).isEqualTo(61)
        assertThat(RawJson.canonicalRecord(mapped)).doesNotContain("HeartRateRecord(")
    }
}
