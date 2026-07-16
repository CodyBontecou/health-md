package com.healthmd.rawexport

import java.nio.ByteBuffer
import java.nio.charset.CodingErrorAction
import java.nio.charset.StandardCharsets
import java.security.MessageDigest
import java.time.Instant
import java.time.ZoneOffset
import java.util.Base64
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.doubleOrNull
import kotlinx.serialization.json.intOrNull
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.longOrNull

/** Metadata Health Connect will accept on a newly inserted record. */
data class RestorableClientMetadata(
    val clientRecordId: String?,
    val clientRecordVersion: Long,
    val recordingMethod: DecodedEnum,
    val device: DecodedDevice?,
)

/** Server-owned provenance is retained for audit only and MUST NOT be used as restore input. */
data class NonRestorableMetadata(
    val serverAssignedId: String,
    val dataOriginPackageName: String,
    val serverLastModifiedTime: DecodedInstant,
)

data class DecodedMetadata(
    val restorable: RestorableClientMetadata,
    val nonRestorable: NonRestorableMetadata,
)

data class DecodedInstant(val epochSecond: Long, val nano: Int) : Comparable<DecodedInstant> {
    fun toInstant(): Instant = Instant.ofEpochSecond(epochSecond, nano.toLong())
    override fun compareTo(other: DecodedInstant): Int = compareValuesBy(this, other, { it.epochSecond }, { it.nano })
}

data class DecodedEnum(val raw: Int, val label: String)
data class DecodedDevice(val type: DecodedEnum, val manufacturer: String?, val model: String?)
data class DecodedQuantity(val number: Double, val decimal: String, val type: String, val unit: String)
data class DecodedScalar(val number: Double, val decimal: String, val unit: String)
data class DecodedTimedLong(val time: DecodedInstant, val value: Long)
data class DecodedTimedDouble(val time: DecodedInstant, val value: Double)
data class DecodedTimedQuantity(val time: DecodedInstant, val value: DecodedQuantity)

data class DecodedSleepStage(val startTime: DecodedInstant, val endTime: DecodedInstant, val stage: DecodedEnum)
data class DecodedExerciseSegment(val startTime: DecodedInstant, val endTime: DecodedInstant, val segmentType: DecodedEnum, val repetitions: Int)
data class DecodedExerciseLap(val startTime: DecodedInstant, val endTime: DecodedInstant, val length: DecodedQuantity?)
data class DecodedRouteLocation(
    val time: DecodedInstant,
    val latitude: Double,
    val longitude: Double,
    val horizontalAccuracy: DecodedQuantity?,
    val verticalAccuracy: DecodedQuantity?,
    val altitude: DecodedQuantity?,
)
data class DecodedExerciseRoute(val state: RawRouteState, val locations: List<DecodedRouteLocation>)

sealed interface DecodedCompletionGoal {
    data class Distance(val distance: DecodedQuantity) : DecodedCompletionGoal
    data class DistanceAndDuration(val distance: DecodedQuantity, val seconds: Long, val nano: Int) : DecodedCompletionGoal
    data class Steps(val steps: Long) : DecodedCompletionGoal
    data class Duration(val seconds: Long, val nano: Int) : DecodedCompletionGoal
    data class Repetitions(val repetitions: Int) : DecodedCompletionGoal
    data class TotalCalories(val totalCalories: DecodedQuantity) : DecodedCompletionGoal
    data class ActiveCalories(val activeCalories: DecodedQuantity) : DecodedCompletionGoal
    data object ManualCompletion : DecodedCompletionGoal
    data object Unknown : DecodedCompletionGoal
}

sealed interface DecodedPerformanceTarget {
    data class Power(val min: DecodedQuantity, val max: DecodedQuantity) : DecodedPerformanceTarget
    data class Speed(val min: DecodedQuantity, val max: DecodedQuantity) : DecodedPerformanceTarget
    data class Cadence(val min: Double, val max: Double) : DecodedPerformanceTarget
    data class HeartRate(val min: Double, val max: Double) : DecodedPerformanceTarget
    data class Weight(val mass: DecodedQuantity) : DecodedPerformanceTarget
    data class Rpe(val value: Int) : DecodedPerformanceTarget
    data object Amrap : DecodedPerformanceTarget
    data object Unknown : DecodedPerformanceTarget
}

data class DecodedPlannedStep(
    val exerciseType: DecodedEnum,
    val exercisePhase: DecodedEnum,
    val completionGoal: DecodedCompletionGoal,
    val performanceTargets: List<DecodedPerformanceTarget>,
    val description: String?,
)
data class DecodedPlannedBlock(val repetitions: Int, val description: String?, val steps: List<DecodedPlannedStep>)

data class DecodedFhirVersion(val major: Int, val minor: Int, val patch: Int)
data class DecodedFhirResource(val type: DecodedEnum, val id: String, val exactJson: String, val checksumSha256: String)
data class DecodedMedicalSource(
    val id: String,
    val packageName: String,
    val fhirBaseUri: String,
    val displayName: String,
    val fhirVersion: DecodedFhirVersion,
    val lastDataUpdateTime: DecodedInstant?,
)
data class DecodedMedicalPayload(
    val medicalResourceType: DecodedEnum,
    val medicalResourceDataSourceId: String,
    val fhirResourceType: DecodedEnum,
    val fhirResourceId: String,
    val dataSourceId: String,
    val fhirVersion: DecodedFhirVersion,
    val fhirResource: DecodedFhirResource,
    val source: DecodedMedicalSource?,
)

data class DecodedProviderPayload(
    val providerId: String,
    val endpointKey: String,
    val endpointIdentifier: String,
    val queryMetadata: Map<String, String>,
    val fetchedAt: DecodedInstant,
    val httpStatus: Int,
    val contentType: String?,
    val charset: String,
    val responseHeaders: Map<String, String>,
    val pageOrdinal: Int,
    val exactResponseBytes: ByteArray,
    val exactResponseText: String?,
    val responseSha256: String,
    val serverAggregation: Boolean,
) {
    override fun equals(other: Any?): Boolean = other is DecodedProviderPayload &&
        providerId == other.providerId && endpointKey == other.endpointKey && endpointIdentifier == other.endpointIdentifier &&
        queryMetadata == other.queryMetadata && fetchedAt == other.fetchedAt && httpStatus == other.httpStatus &&
        contentType == other.contentType && charset == other.charset && responseHeaders == other.responseHeaders &&
        pageOrdinal == other.pageOrdinal && exactResponseBytes.contentEquals(other.exactResponseBytes) &&
        exactResponseText == other.exactResponseText && responseSha256 == other.responseSha256 && serverAggregation == other.serverAggregation
    override fun hashCode(): Int = 31 * responseSha256.hashCode() + exactResponseBytes.contentHashCode()
}

/** Strongly typed v1 field payloads. The wire-type switch in [RawRecordDecoder] is exhaustive. */
sealed interface DecodedFields {
    data class Steps(val count: Long) : DecodedFields
    data class HeartRate(val samples: List<DecodedTimedLong>) : DecodedFields
    data class Sleep(val title: String?, val notes: String?, val stages: List<DecodedSleepStage>) : DecodedFields
    data class Exercise(
        val exerciseType: DecodedEnum,
        val title: String?,
        val notes: String?,
        val plannedExerciseSessionId: String?,
        val segments: List<DecodedExerciseSegment>,
        val laps: List<DecodedExerciseLap>,
        val route: DecodedExerciseRoute?,
    ) : DecodedFields
    data class Quantity(val fieldName: String, val value: DecodedQuantity) : DecodedFields
    data class BloodPressure(val systolic: DecodedQuantity, val diastolic: DecodedQuantity, val bodyPosition: DecodedEnum, val measurementLocation: DecodedEnum) : DecodedFields
    data class BloodGlucose(val level: DecodedQuantity, val specimenSource: DecodedEnum, val mealType: DecodedEnum, val relationToMeal: DecodedEnum) : DecodedFields
    data class Temperature(val temperature: DecodedQuantity, val measurementLocation: DecodedEnum) : DecodedFields
    data class Scalar(val fieldName: String, val value: DecodedScalar) : DecodedFields
    data class Nutrition(val name: String?, val mealType: DecodedEnum, val nutrients: Map<String, DecodedQuantity?>) : DecodedFields
    data class Floors(val floors: Double) : DecodedFields
    data class IntegerValue(val fieldName: String, val value: Long) : DecodedFields
    data class QuantitySamples(val fieldName: String, val samples: List<DecodedTimedQuantity>) : DecodedFields
    data class DoubleSamples(val fieldName: String, val samples: List<DecodedTimedDouble>) : DecodedFields
    data class Vo2Max(val value: DecodedScalar, val measurementMethod: DecodedEnum) : DecodedFields
    data class SkinTemperature(val baseline: DecodedQuantity?, val measurementLocation: DecodedEnum, val deltas: List<DecodedTimedQuantity>) : DecodedFields
    data class EnumValues(val values: Map<String, DecodedEnum>) : DecodedFields
    data object Marker : DecodedFields
    data class Mindfulness(val type: DecodedEnum, val title: String?, val notes: String?) : DecodedFields
    data class PlannedExercise(
        val hasExplicitTime: Boolean,
        val exerciseType: DecodedEnum,
        val completedExerciseSessionId: String?,
        val title: String?,
        val notes: String?,
        val blocks: List<DecodedPlannedBlock>,
    ) : DecodedFields
    data class Medical(val payload: DecodedMedicalPayload) : DecodedFields
    data class Provider(val payload: DecodedProviderPayload) : DecodedFields
}

data class DecodedRawRecord(
    val wireType: String,
    val nativeIdentity: String,
    val recordKind: RawRecordKind,
    val source: RawSourceDescriptor,
    val startTime: DecodedInstant?,
    val endTime: DecodedInstant?,
    val startZoneOffset: ZoneOffset?,
    val endZoneOffset: ZoneOffset?,
    val metadata: DecodedMetadata?,
    val fields: DecodedFields,
    val hash: String,
    /** Unknown v1 additions keyed by JSON pointer; retained, never interpreted. */
    val additiveUnknownFields: Map<String, JsonElement>,
) {
    val nonRestorableMetadata: NonRestorableMetadata? get() = metadata?.nonRestorable
}

/** Sanitized decoder failure: code and structural path only, never source values. */
class RawDecodeException(val code: String, val structuralPath: String) : Exception("$code at $structuralPath")

/**
 * Typed inverse boundary for all 42 Health Connect wire types, PHR resources, and cloud payload pages.
 * It deliberately does not construct SDK Records: constructor availability varies by installed SDK and
 * server-owned Metadata.id/dataOrigin/lastModifiedTime cannot be restored. Client metadata is separated
 * in [RestorableClientMetadata] for a future insertion adapter.
 */
object RawRecordDecoder {
    private val sha = Regex("[0-9a-f]{64}")
    private val endpointIdentifier = Regex("[a-z0-9._-]+:[0-9a-f]{24}")
    private val envelopeKeys = setOf("wireType", "nativeIdentity", "recordKind", "source", "startTime", "endTime", "startZoneOffsetSeconds", "endZoneOffsetSeconds", "metadata", "fields", "providerPayload", "hash")
    private val nutrientNames = listOf(
        "biotin", "caffeine", "calcium", "energy", "energyFromFat", "chloride", "cholesterol", "chromium", "copper",
        "dietaryFiber", "folate", "folicAcid", "iodine", "iron", "magnesium", "manganese", "molybdenum",
        "monounsaturatedFat", "niacin", "pantothenicAcid", "phosphorus", "polyunsaturatedFat", "potassium", "protein",
        "riboflavin", "saturatedFat", "selenium", "sodium", "sugar", "thiamin", "totalCarbohydrate", "totalFat",
        "transFat", "unsaturatedFat", "vitaminA", "vitaminB12", "vitaminB6", "vitaminC", "vitaminD", "vitaminE", "vitaminK", "zinc",
    )
    private val instantTypes = setOf(
        "basal_metabolic_rate", "blood_pressure", "blood_glucose", "body_fat", "body_temperature", "height", "weight",
        "oxygen_saturation", "respiratory_rate", "heart_rate_variability_rmssd", "lean_body_mass", "resting_heart_rate",
        "vo2_max", "basal_body_temperature", "body_water_mass", "bone_mass", "cervical_mucus", "intermenstrual_bleeding",
        "menstruation_flow", "ovulation_test", "sexual_activity",
    )
    private val intervalTypes = setOf(
        "steps", "heart_rate", "sleep_session", "exercise_session", "distance", "active_calories_burned", "total_calories_burned",
        "nutrition", "hydration", "floors_climbed", "speed", "elevation_gained", "wheelchair_pushes", "power", "skin_temperature",
        "menstruation_period", "cycling_pedaling_cadence", "steps_cadence", "mindfulness_session", "planned_exercise_session", "activity_intensity",
    )

    fun decode(element: JsonObject): DecodedRawRecord {
        val unknown = linkedMapOf<String, JsonElement>()
        unknown(element, envelopeKeys, "", unknown)
        envelopeKeys.forEach { element.required(it, "/") }
        val wire = element.string("wireType", "/wireType", nonEmpty = true)
        val identity = element.string("nativeIdentity", "/nativeIdentity", nonEmpty = true)
        val kind = when (element.string("recordKind", "/recordKind")) {
            "health_connect_record" -> RawRecordKind.HEALTH_CONNECT_RECORD
            "provider_payload" -> RawRecordKind.PROVIDER_PAYLOAD
            else -> fail("enum", "/recordKind")
        }
        val source = source(element.obj("source", "/source"), unknown)
        val start = element.nullableObj("startTime", "/startTime")?.let { instant(it, "/startTime", unknown) }
        val end = element.nullableObj("endTime", "/endTime")?.let { instant(it, "/endTime", unknown) }
        val startOffset = offset(element["startZoneOffsetSeconds"], "/startZoneOffsetSeconds")
        val endOffset = offset(element["endZoneOffsetSeconds"], "/endZoneOffsetSeconds")
        val metadata = element.nullableObj("metadata", "/metadata")?.let { metadata(it, unknown) }
        val fieldsObject = element.obj("fields", "/fields")
        val providerObject = element.nullableObj("providerPayload", "/providerPayload")
        val hash = element.string("hash", "/hash").also { if (!sha.matches(it)) fail("sha256", "/hash") }

        when {
            kind == RawRecordKind.PROVIDER_PAYLOAD -> {
                if (wire != "provider_payload" || metadata != null || start != null || end != null || startOffset != null || endOffset != null || fieldsObject.isNotEmpty() || providerObject == null) {
                    fail("provider_shape", "/")
                }
            }
            wire == "medical_resource" -> {
                if (metadata != null || start != null || end != null || startOffset != null || endOffset != null || providerObject != null) fail("medical_shape", "/")
            }
            else -> {
                if (providerObject != null || metadata == null || wire !in instantTypes + intervalTypes) fail("record_shape", "/")
                if (wire in instantTypes && (start == null || end != null || endOffset != null)) fail("temporal_shape", "/")
                if (wire in intervalTypes && (start == null || end == null)) fail("temporal_shape", "/")
                if (start != null && end != null && start >= end) fail("temporal_order", "/endTime")
            }
        }

        val decodedFields = when (kind) {
            RawRecordKind.PROVIDER_PAYLOAD -> DecodedFields.Provider(provider(requireNotNull(providerObject), hash, source, identity, unknown))
            RawRecordKind.HEALTH_CONNECT_RECORD -> decodeHealthFields(wire, fieldsObject, unknown)
        }
        return DecodedRawRecord(wire, identity, kind, source, start, end, startOffset, endOffset, metadata, decodedFields, hash, unknown)
    }

    private fun decodeHealthFields(wire: String, o: JsonObject, extras: MutableMap<String, JsonElement>): DecodedFields = when (wire) {
        "steps" -> { shape(o, setOf("count"), "/fields", extras); DecodedFields.Steps(o.long("count", "/fields/count")) }
        "heart_rate" -> { shape(o, setOf("samples"), "/fields", extras); DecodedFields.HeartRate(timedLongs(o.array("samples", "/fields/samples"), "beatsPerMinute", extras)) }
        "sleep_session" -> sleep(o, extras)
        "exercise_session" -> exercise(o, extras)
        "distance" -> quantityField(o, "distance", "Length", "m", extras)
        "active_calories_burned", "total_calories_burned" -> quantityField(o, "energy", "Energy", "kcal", extras)
        "basal_metabolic_rate" -> quantityField(o, "basalMetabolicRate", "Power", "W", extras)
        "blood_pressure" -> bloodPressure(o, extras)
        "blood_glucose" -> bloodGlucose(o, extras)
        "body_fat", "oxygen_saturation" -> quantityField(o, "percentage", "Percentage", "%", extras)
        "body_temperature", "basal_body_temperature" -> temperature(o, extras)
        "height" -> quantityField(o, "height", "Length", "m", extras)
        "weight" -> quantityField(o, "weight", "Mass", "kg", extras)
        "respiratory_rate" -> scalarField(o, "rate", "breaths/min", extras)
        "heart_rate_variability_rmssd" -> scalarField(o, "heartRateVariabilityMillis", "ms", extras)
        "nutrition" -> nutrition(o, extras)
        "hydration" -> quantityField(o, "volume", "Volume", "L", extras)
        "floors_climbed" -> { shape(o, setOf("floors"), "/fields", extras); DecodedFields.Floors(o.finite("floors", "/fields/floors")) }
        "lean_body_mass", "body_water_mass", "bone_mass" -> quantityField(o, "mass", "Mass", "kg", extras)
        "resting_heart_rate" -> integerField(o, "beatsPerMinute", extras)
        "speed" -> quantitySamples(o, "speed", "Velocity", "m/s", extras)
        "vo2_max" -> vo2(o, extras)
        "elevation_gained" -> quantityField(o, "elevation", "Length", "m", extras)
        "wheelchair_pushes" -> integerField(o, "count", extras)
        "power" -> quantitySamples(o, "power", "Power", "W", extras)
        "skin_temperature" -> skin(o, extras)
        "cervical_mucus" -> enumFields(o, listOf("appearance", "sensation"), extras)
        "intermenstrual_bleeding", "menstruation_period" -> { shape(o, emptySet(), "/fields", extras); DecodedFields.Marker }
        "menstruation_flow" -> enumFields(o, listOf("flow"), extras)
        "ovulation_test" -> enumFields(o, listOf("result"), extras)
        "sexual_activity" -> enumFields(o, listOf("protectionUsed"), extras)
        "cycling_pedaling_cadence" -> doubleSamples(o, "revolutionsPerMinute", extras)
        "steps_cadence" -> doubleSamples(o, "rate", extras)
        "mindfulness_session" -> mindfulness(o, extras)
        "planned_exercise_session" -> planned(o, extras)
        "activity_intensity" -> enumFields(o, listOf("activityIntensityType"), extras)
        "medical_resource" -> DecodedFields.Medical(medical(o, extras))
        else -> fail("unsupported_wire_type", "/wireType")
    }

    private fun sleep(o: JsonObject, extras: MutableMap<String, JsonElement>): DecodedFields.Sleep {
        shape(o, setOf("title", "notes", "stages"), "/fields", extras)
        val stages = o.array("stages", "/fields/stages").mapIndexed { i, value ->
            val p = "/fields/stages/$i"; val s = value.asObject(p)
            shape(s, setOf("startTime", "endTime", "stage"), p, extras)
            DecodedSleepStage(instant(s.obj("startTime", "$p/startTime"), "$p/startTime", extras), instant(s.obj("endTime", "$p/endTime"), "$p/endTime", extras), enum(s.obj("stage", "$p/stage"), "$p/stage", extras))
        }
        ordered(stages.map { it.startTime }, "/fields/stages")
        stages.forEachIndexed { i, s -> if (s.startTime >= s.endTime) fail("temporal_order", "/fields/stages/$i") }
        return DecodedFields.Sleep(o.nullableString("title", "/fields/title"), o.nullableString("notes", "/fields/notes"), stages)
    }

    private fun exercise(o: JsonObject, extras: MutableMap<String, JsonElement>): DecodedFields.Exercise {
        val required = setOf("exerciseType", "title", "notes", "plannedExerciseSessionId", "segments", "laps")
        required.forEach { o.required(it, "/fields") }
        unknown(o, required + "route", "/fields", extras)
        val segments = o.array("segments", "/fields/segments").mapIndexed { i, value ->
            val p = "/fields/segments/$i"; val s = value.asObject(p); shape(s, setOf("startTime", "endTime", "segmentType", "repetitions"), p, extras)
            DecodedExerciseSegment(instant(s.obj("startTime", "$p/startTime"), "$p/startTime", extras), instant(s.obj("endTime", "$p/endTime"), "$p/endTime", extras), enum(s.obj("segmentType", "$p/segmentType"), "$p/segmentType", extras), s.int("repetitions", "$p/repetitions"))
        }
        ordered(segments.map { it.startTime }, "/fields/segments")
        segments.forEachIndexed { i, segment -> if (segment.startTime >= segment.endTime) fail("temporal_order", "/fields/segments/$i") }
        val laps = o.array("laps", "/fields/laps").mapIndexed { i, value ->
            val p = "/fields/laps/$i"; val lap = value.asObject(p); shape(lap, setOf("startTime", "endTime", "length"), p, extras)
            DecodedExerciseLap(instant(lap.obj("startTime", "$p/startTime"), "$p/startTime", extras), instant(lap.obj("endTime", "$p/endTime"), "$p/endTime", extras), lap.nullableObj("length", "$p/length")?.let { quantity(it, "Length", "m", "$p/length", extras) })
        }
        ordered(laps.map { it.startTime }, "/fields/laps")
        laps.forEachIndexed { i, lap -> if (lap.startTime >= lap.endTime) fail("temporal_order", "/fields/laps/$i") }
        val route = o["route"]?.let { route(it.asObject("/fields/route"), extras) }
        return DecodedFields.Exercise(enum(o.obj("exerciseType", "/fields/exerciseType"), "/fields/exerciseType", extras), o.nullableString("title", "/fields/title"), o.nullableString("notes", "/fields/notes"), o.nullableString("plannedExerciseSessionId", "/fields/plannedExerciseSessionId"), segments, laps, route)
    }

    private fun route(o: JsonObject, extras: MutableMap<String, JsonElement>): DecodedExerciseRoute {
        shape(o, setOf("state", "locations"), "/fields/route", extras)
        val state = when (o.string("state", "/fields/route/state")) {
            "consent_required" -> RawRouteState.CONSENT_REQUIRED
            "no_data" -> RawRouteState.NO_DATA
            "data" -> RawRouteState.DATA
            else -> fail("enum", "/fields/route/state")
        }
        val locations = o.array("locations", "/fields/route/locations").mapIndexed { i, value ->
            val p = "/fields/route/locations/$i"; val l = value.asObject(p)
            shape(l, setOf("time", "latitude", "longitude", "horizontalAccuracy", "verticalAccuracy", "altitude"), p, extras)
            DecodedRouteLocation(
                instant(l.obj("time", "$p/time"), "$p/time", extras), l.finite("latitude", "$p/latitude"), l.finite("longitude", "$p/longitude"),
                l.nullableObj("horizontalAccuracy", "$p/horizontalAccuracy")?.let { quantity(it, "Length", "m", "$p/horizontalAccuracy", extras) },
                l.nullableObj("verticalAccuracy", "$p/verticalAccuracy")?.let { quantity(it, "Length", "m", "$p/verticalAccuracy", extras) },
                l.nullableObj("altitude", "$p/altitude")?.let { quantity(it, "Length", "m", "$p/altitude", extras) },
            )
        }
        ordered(locations.map { it.time }, "/fields/route/locations")
        if (state != RawRouteState.DATA && locations.isNotEmpty()) fail("route_state", "/fields/route/locations")
        return DecodedExerciseRoute(state, locations)
    }

    private fun bloodPressure(o: JsonObject, extras: MutableMap<String, JsonElement>): DecodedFields.BloodPressure {
        shape(o, setOf("systolic", "diastolic", "bodyPosition", "measurementLocation"), "/fields", extras)
        return DecodedFields.BloodPressure(quantity(o.obj("systolic", "/fields/systolic"), "Pressure", "mmHg", "/fields/systolic", extras), quantity(o.obj("diastolic", "/fields/diastolic"), "Pressure", "mmHg", "/fields/diastolic", extras), enum(o.obj("bodyPosition", "/fields/bodyPosition"), "/fields/bodyPosition", extras), enum(o.obj("measurementLocation", "/fields/measurementLocation"), "/fields/measurementLocation", extras))
    }

    private fun bloodGlucose(o: JsonObject, extras: MutableMap<String, JsonElement>): DecodedFields.BloodGlucose {
        shape(o, setOf("level", "specimenSource", "mealType", "relationToMeal"), "/fields", extras)
        return DecodedFields.BloodGlucose(quantity(o.obj("level", "/fields/level"), "BloodGlucose", "mmol/L", "/fields/level", extras), enum(o.obj("specimenSource", "/fields/specimenSource"), "/fields/specimenSource", extras), enum(o.obj("mealType", "/fields/mealType"), "/fields/mealType", extras), enum(o.obj("relationToMeal", "/fields/relationToMeal"), "/fields/relationToMeal", extras))
    }

    private fun temperature(o: JsonObject, extras: MutableMap<String, JsonElement>): DecodedFields.Temperature {
        shape(o, setOf("temperature", "measurementLocation"), "/fields", extras)
        return DecodedFields.Temperature(quantity(o.obj("temperature", "/fields/temperature"), "Temperature", "degC", "/fields/temperature", extras), enum(o.obj("measurementLocation", "/fields/measurementLocation"), "/fields/measurementLocation", extras))
    }

    private fun nutrition(o: JsonObject, extras: MutableMap<String, JsonElement>): DecodedFields.Nutrition {
        val keys = setOf("name", "mealType") + nutrientNames
        shape(o, keys, "/fields", extras)
        val values = nutrientNames.associateWith { name ->
            o.nullableObj(name, "/fields/$name")?.let { quantity(it, if (name == "energy" || name == "energyFromFat") "Energy" else "Mass", if (name == "energy" || name == "energyFromFat") "kcal" else "g", "/fields/$name", extras) }
        }
        return DecodedFields.Nutrition(o.nullableString("name", "/fields/name"), enum(o.obj("mealType", "/fields/mealType"), "/fields/mealType", extras), values)
    }

    private fun skin(o: JsonObject, extras: MutableMap<String, JsonElement>): DecodedFields.SkinTemperature {
        shape(o, setOf("baseline", "measurementLocation", "deltas"), "/fields", extras)
        val deltas = o.array("deltas", "/fields/deltas").mapIndexed { i, value ->
            val p = "/fields/deltas/$i"; val d = value.asObject(p); shape(d, setOf("time", "delta"), p, extras)
            DecodedTimedQuantity(instant(d.obj("time", "$p/time"), "$p/time", extras), quantity(d.obj("delta", "$p/delta"), "TemperatureDelta", "degC", "$p/delta", extras))
        }
        ordered(deltas.map { it.time }, "/fields/deltas")
        return DecodedFields.SkinTemperature(o.nullableObj("baseline", "/fields/baseline")?.let { quantity(it, "Temperature", "degC", "/fields/baseline", extras) }, enum(o.obj("measurementLocation", "/fields/measurementLocation"), "/fields/measurementLocation", extras), deltas)
    }

    private fun mindfulness(o: JsonObject, extras: MutableMap<String, JsonElement>): DecodedFields.Mindfulness {
        shape(o, setOf("mindfulnessSessionType", "title", "notes"), "/fields", extras)
        return DecodedFields.Mindfulness(enum(o.obj("mindfulnessSessionType", "/fields/mindfulnessSessionType"), "/fields/mindfulnessSessionType", extras), o.nullableString("title", "/fields/title"), o.nullableString("notes", "/fields/notes"))
    }

    private fun planned(o: JsonObject, extras: MutableMap<String, JsonElement>): DecodedFields.PlannedExercise {
        shape(o, setOf("hasExplicitTime", "exerciseType", "completedExerciseSessionId", "title", "notes", "blocks"), "/fields", extras)
        val blocks = o.array("blocks", "/fields/blocks").mapIndexed { bi, value ->
            val bp = "/fields/blocks/$bi"; val b = value.asObject(bp); shape(b, setOf("repetitions", "description", "steps"), bp, extras)
            val steps = b.array("steps", "$bp/steps").mapIndexed { si, stepValue ->
                val sp = "$bp/steps/$si"; val s = stepValue.asObject(sp); shape(s, setOf("exerciseType", "exercisePhase", "completionGoal", "performanceTargets", "description"), sp, extras)
                DecodedPlannedStep(enum(s.obj("exerciseType", "$sp/exerciseType"), "$sp/exerciseType", extras), enum(s.obj("exercisePhase", "$sp/exercisePhase"), "$sp/exercisePhase", extras), goal(s.obj("completionGoal", "$sp/completionGoal"), "$sp/completionGoal", extras), s.array("performanceTargets", "$sp/performanceTargets").mapIndexed { ti, t -> target(t.asObject("$sp/performanceTargets/$ti"), "$sp/performanceTargets/$ti", extras) }, s.nullableString("description", "$sp/description"))
            }
            DecodedPlannedBlock(b.int("repetitions", "$bp/repetitions"), b.nullableString("description", "$bp/description"), steps)
        }
        return DecodedFields.PlannedExercise(o.bool("hasExplicitTime", "/fields/hasExplicitTime"), enum(o.obj("exerciseType", "/fields/exerciseType"), "/fields/exerciseType", extras), o.nullableString("completedExerciseSessionId", "/fields/completedExerciseSessionId"), o.nullableString("title", "/fields/title"), o.nullableString("notes", "/fields/notes"), blocks)
    }

    private fun goal(o: JsonObject, p: String, extras: MutableMap<String, JsonElement>): DecodedCompletionGoal {
        val type = o.string("type", "$p/type")
        fun duration(key: String): Pair<Long, Int> { val d = o.obj(key, "$p/$key"); shape(d, setOf("seconds", "nano"), "$p/$key", extras); val n = d.int("nano", "$p/$key/nano"); if (n !in 0..999_999_999) fail("nano", "$p/$key/nano"); return d.long("seconds", "$p/$key/seconds") to n }
        return when (type) {
            "distance" -> { shape(o, setOf("type", "distance"), p, extras); DecodedCompletionGoal.Distance(quantity(o.obj("distance", "$p/distance"), "Length", "m", "$p/distance", extras)) }
            "distance_and_duration" -> { shape(o, setOf("type", "distance", "duration"), p, extras); val d = duration("duration"); DecodedCompletionGoal.DistanceAndDuration(quantity(o.obj("distance", "$p/distance"), "Length", "m", "$p/distance", extras), d.first, d.second) }
            "steps" -> { shape(o, setOf("type", "steps"), p, extras); DecodedCompletionGoal.Steps(o.long("steps", "$p/steps")) }
            "duration" -> { shape(o, setOf("type", "duration"), p, extras); val d = duration("duration"); DecodedCompletionGoal.Duration(d.first, d.second) }
            "repetitions" -> { shape(o, setOf("type", "repetitions"), p, extras); DecodedCompletionGoal.Repetitions(o.int("repetitions", "$p/repetitions")) }
            "total_calories" -> { shape(o, setOf("type", "totalCalories"), p, extras); DecodedCompletionGoal.TotalCalories(quantity(o.obj("totalCalories", "$p/totalCalories"), "Energy", "kcal", "$p/totalCalories", extras)) }
            "active_calories" -> { shape(o, setOf("type", "activeCalories"), p, extras); DecodedCompletionGoal.ActiveCalories(quantity(o.obj("activeCalories", "$p/activeCalories"), "Energy", "kcal", "$p/activeCalories", extras)) }
            "manual_completion" -> { shape(o, setOf("type"), p, extras); DecodedCompletionGoal.ManualCompletion }
            "unknown" -> { shape(o, setOf("type"), p, extras); DecodedCompletionGoal.Unknown }
            else -> fail("goal_variant", "$p/type")
        }
    }

    private fun target(o: JsonObject, p: String, extras: MutableMap<String, JsonElement>): DecodedPerformanceTarget = when (o.string("type", "$p/type")) {
        "power" -> { shape(o, setOf("type", "minPower", "maxPower"), p, extras); DecodedPerformanceTarget.Power(quantity(o.obj("minPower", "$p/minPower"), "Power", "W", "$p/minPower", extras), quantity(o.obj("maxPower", "$p/maxPower"), "Power", "W", "$p/maxPower", extras)) }
        "speed" -> { shape(o, setOf("type", "minSpeed", "maxSpeed"), p, extras); DecodedPerformanceTarget.Speed(quantity(o.obj("minSpeed", "$p/minSpeed"), "Velocity", "m/s", "$p/minSpeed", extras), quantity(o.obj("maxSpeed", "$p/maxSpeed"), "Velocity", "m/s", "$p/maxSpeed", extras)) }
        "cadence" -> { shape(o, setOf("type", "minCadence", "maxCadence"), p, extras); DecodedPerformanceTarget.Cadence(o.finite("minCadence", "$p/minCadence"), o.finite("maxCadence", "$p/maxCadence")) }
        "heart_rate" -> { shape(o, setOf("type", "minHeartRate", "maxHeartRate"), p, extras); DecodedPerformanceTarget.HeartRate(o.finite("minHeartRate", "$p/minHeartRate"), o.finite("maxHeartRate", "$p/maxHeartRate")) }
        "weight" -> { shape(o, setOf("type", "mass"), p, extras); DecodedPerformanceTarget.Weight(quantity(o.obj("mass", "$p/mass"), "Mass", "kg", "$p/mass", extras)) }
        "rpe" -> { shape(o, setOf("type", "rpe"), p, extras); DecodedPerformanceTarget.Rpe(o.int("rpe", "$p/rpe")) }
        "amrap" -> { shape(o, setOf("type"), p, extras); DecodedPerformanceTarget.Amrap }
        "unknown" -> { shape(o, setOf("type"), p, extras); DecodedPerformanceTarget.Unknown }
        else -> fail("target_variant", "$p/type")
    }

    private fun medical(o: JsonObject, extras: MutableMap<String, JsonElement>): DecodedMedicalPayload {
        shape(o, setOf("medicalResourceType", "medicalResourceId", "dataSourceId", "fhirVersion", "fhirResource", "source"), "/fields", extras)
        val id = o.obj("medicalResourceId", "/fields/medicalResourceId"); shape(id, setOf("dataSourceId", "fhirResourceType", "fhirResourceId"), "/fields/medicalResourceId", extras)
        val fhir = o.obj("fhirResource", "/fields/fhirResource"); shape(fhir, setOf("type", "id", "fhirResourceJson", "checksumSha256"), "/fields/fhirResource", extras)
        val exact = fhir.string("fhirResourceJson", "/fields/fhirResource/fhirResourceJson")
        val checksum = fhir.string("checksumSha256", "/fields/fhirResource/checksumSha256")
        if (!sha.matches(checksum) || digest(exact.toByteArray(StandardCharsets.UTF_8)) != checksum) fail("fhir_checksum", "/fields/fhirResource/checksumSha256")
        val source = o.nullableObj("source", "/fields/source")?.let { s ->
            shape(s, setOf("id", "packageName", "fhirBaseUri", "displayName", "fhirVersion", "lastDataUpdateTime"), "/fields/source", extras)
            DecodedMedicalSource(s.string("id", "/fields/source/id"), s.string("packageName", "/fields/source/packageName"), s.string("fhirBaseUri", "/fields/source/fhirBaseUri"), s.string("displayName", "/fields/source/displayName"), version(s.obj("fhirVersion", "/fields/source/fhirVersion"), "/fields/source/fhirVersion", extras), s.nullableObj("lastDataUpdateTime", "/fields/source/lastDataUpdateTime")?.let { instant(it, "/fields/source/lastDataUpdateTime", extras) })
        }
        val medicalResourceType = enum(o.obj("medicalResourceType", "/fields/medicalResourceType"), "/fields/medicalResourceType", extras)
        val medicalDataSourceId = id.string("dataSourceId", "/fields/medicalResourceId/dataSourceId")
        val resourceType = enum(id.obj("fhirResourceType", "/fields/medicalResourceId/fhirResourceType"), "/fields/medicalResourceId/fhirResourceType", extras)
        val resourceId = id.string("fhirResourceId", "/fields/medicalResourceId/fhirResourceId")
        val dataSourceId = o.string("dataSourceId", "/fields/dataSourceId")
        val fhirVersion = version(o.obj("fhirVersion", "/fields/fhirVersion"), "/fields/fhirVersion", extras)
        val fhirResource = DecodedFhirResource(
            enum(fhir.obj("type", "/fields/fhirResource/type"), "/fields/fhirResource/type", extras),
            fhir.string("id", "/fields/fhirResource/id"),
            exact,
            checksum,
        )
        if (medicalDataSourceId != dataSourceId || source?.id?.let { it != dataSourceId } == true) {
            fail("medical_data_source", "/fields/dataSourceId")
        }
        if (resourceType != fhirResource.type) fail("medical_resource_type", "/fields/fhirResource/type")
        if (resourceId != fhirResource.id) fail("medical_resource_id", "/fields/fhirResource/id")
        if (source != null && source.fhirVersion != fhirVersion) fail("medical_fhir_version", "/fields/source/fhirVersion")
        return DecodedMedicalPayload(medicalResourceType, medicalDataSourceId, resourceType, resourceId, dataSourceId, fhirVersion, fhirResource, source)
    }

    private fun provider(o: JsonObject, recordHash: String, source: RawSourceDescriptor, identity: String, extras: MutableMap<String, JsonElement>): DecodedProviderPayload {
        val keys = setOf("providerId", "endpointKey", "endpointIdentifier", "queryMetadata", "fetchedAt", "httpStatus", "contentType", "charset", "responseHeaders", "pageOrdinal", "responseBytesBase64", "responseText", "responseSha256", "serverAggregation")
        shape(o, keys, "/providerPayload", extras)
        val providerId = o.string("providerId", "/providerPayload/providerId", true)
        val endpointKey = o.string("endpointKey", "/providerPayload/endpointKey", true)
        if (source.providerId != providerId || source.endpointKey != endpointKey) fail("provider_source", "/source")
        val bytes = try { Base64.getDecoder().decode(o.string("responseBytesBase64", "/providerPayload/responseBytesBase64")) } catch (_: IllegalArgumentException) { fail("base64", "/providerPayload/responseBytesBase64") }
        val checksum = o.string("responseSha256", "/providerPayload/responseSha256")
        if (!sha.matches(checksum) || digest(bytes) != checksum || recordHash != checksum) fail("provider_checksum", "/providerPayload/responseSha256")
        val charsetName = o.string("charset", "/providerPayload/charset", true)
        val decoded = try {
            val charset = java.nio.charset.Charset.forName(charsetName)
            charset.newDecoder().onMalformedInput(CodingErrorAction.REPORT).onUnmappableCharacter(CodingErrorAction.REPORT).decode(ByteBuffer.wrap(bytes)).toString()
        } catch (_: Exception) {
            null
        }
        val text = o.nullableString("responseText", "/providerPayload/responseText")
        if (decoded == null) {
            // Exact bytes remain authoritative even when the provider's declared charset cannot
            // strictly decode them. Any non-null text would make a contradictory fidelity claim.
            if (text != null) fail("provider_text", "/providerPayload/responseText")
        } else {
            val validJson = runCatching { RawJson.codec.parseToJsonElement(decoded) }.isSuccess
            if (validJson && text != decoded) fail("provider_text", "/providerPayload/responseText")
            if (!validJson && text != null) fail("provider_text", "/providerPayload/responseText")
        }
        val page = o.int("pageOrdinal", "/providerPayload/pageOrdinal"); if (page < 1) fail("range", "/providerPayload/pageOrdinal")
        val status = o.int("httpStatus", "/providerPayload/httpStatus"); if (status !in 200..299) fail("range", "/providerPayload/httpStatus")
        val expectedIdentity = "cloud:$providerId:$endpointKey:$page:$checksum"; if (identity != expectedIdentity) fail("provider_identity", "/nativeIdentity")
        val endpoint = o.string("endpointIdentifier", "/providerPayload/endpointIdentifier", true)
        if (!endpointIdentifier.matches(endpoint)) fail("endpoint_identifier", "/providerPayload/endpointIdentifier")
        return DecodedProviderPayload(providerId, endpointKey, endpoint, stringMap(o.obj("queryMetadata", "/providerPayload/queryMetadata"), "/providerPayload/queryMetadata"), instant(o.obj("fetchedAt", "/providerPayload/fetchedAt"), "/providerPayload/fetchedAt", extras), status, o.nullableString("contentType", "/providerPayload/contentType"), charsetName, stringMap(o.obj("responseHeaders", "/providerPayload/responseHeaders"), "/providerPayload/responseHeaders"), page, bytes, text, checksum, o.bool("serverAggregation", "/providerPayload/serverAggregation"))
    }

    private fun source(o: JsonObject, extras: MutableMap<String, JsonElement>): RawSourceDescriptor {
        shape(o, setOf("providerId", "fidelityLevel", "endpointKey"), "/source", extras)
        val fidelity = runCatching { RawProviderFidelity.valueOf(o.string("fidelityLevel", "/source/fidelityLevel").uppercase()) }.getOrElse { fail("enum", "/source/fidelityLevel") }
        return RawSourceDescriptor(o.string("providerId", "/source/providerId", true), fidelity, o.nullableString("endpointKey", "/source/endpointKey"))
    }

    private fun metadata(o: JsonObject, extras: MutableMap<String, JsonElement>): DecodedMetadata {
        shape(o, setOf("id", "clientRecordId", "clientRecordVersion", "clientRecordVersionExact", "lastModifiedTime", "dataOriginPackageName", "recordingMethod", "device"), "/metadata", extras)
        val version = o.long("clientRecordVersion", "/metadata/clientRecordVersion")
        if (o.string("clientRecordVersionExact", "/metadata/clientRecordVersionExact") != version.toString()) fail("exact_integer", "/metadata/clientRecordVersionExact")
        val device = o.nullableObj("device", "/metadata/device")?.let { d -> shape(d, setOf("type", "manufacturer", "model"), "/metadata/device", extras); DecodedDevice(enum(d.obj("type", "/metadata/device/type"), "/metadata/device/type", extras), d.nullableString("manufacturer", "/metadata/device/manufacturer"), d.nullableString("model", "/metadata/device/model")) }
        return DecodedMetadata(RestorableClientMetadata(o.nullableString("clientRecordId", "/metadata/clientRecordId"), version, enum(o.obj("recordingMethod", "/metadata/recordingMethod"), "/metadata/recordingMethod", extras), device), NonRestorableMetadata(o.string("id", "/metadata/id"), o.string("dataOriginPackageName", "/metadata/dataOriginPackageName"), instant(o.obj("lastModifiedTime", "/metadata/lastModifiedTime"), "/metadata/lastModifiedTime", extras)))
    }

    private fun instant(o: JsonObject, p: String, extras: MutableMap<String, JsonElement>): DecodedInstant {
        shape(o, setOf("epochSecond", "nano", "epochSecondExact"), p, extras)
        val second = o.long("epochSecond", "$p/epochSecond"); val nano = o.int("nano", "$p/nano")
        if (nano !in 0..999_999_999) fail("nano", "$p/nano")
        if (o.string("epochSecondExact", "$p/epochSecondExact") != second.toString()) fail("exact_integer", "$p/epochSecondExact")
        return DecodedInstant(second, nano)
    }

    private fun enum(o: JsonObject, p: String, extras: MutableMap<String, JsonElement>): DecodedEnum {
        shape(o, setOf("raw", "label"), p, extras)
        return DecodedEnum(o.int("raw", "$p/raw"), o.string("label", "$p/label", true))
    }

    private fun quantity(o: JsonObject, type: String, unit: String, p: String, extras: MutableMap<String, JsonElement>): DecodedQuantity {
        shape(o, setOf("number", "decimal", "type", "unit"), p, extras)
        val number = o.finite("number", "$p/number"); val decimal = o.string("decimal", "$p/decimal")
        val parsed = decimal.toDoubleOrNull()
        if (parsed == null || !parsed.isFinite() || parsed.toRawBits() != number.toRawBits()) fail("quantity_round_trip", "$p/decimal")
        if (o.string("type", "$p/type") != type || o.string("unit", "$p/unit") != unit) fail("quantity_unit", p)
        return DecodedQuantity(number, decimal, type, unit)
    }

    private fun scalar(o: JsonObject, unit: String, p: String, extras: MutableMap<String, JsonElement>): DecodedScalar {
        shape(o, setOf("number", "decimal", "unit"), p, extras)
        val n = o.finite("number", "$p/number"); val d = o.string("decimal", "$p/decimal"); val parsed = d.toDoubleOrNull()
        if (parsed == null || !parsed.isFinite() || parsed.toRawBits() != n.toRawBits() || o.string("unit", "$p/unit") != unit) fail("scalar_round_trip", p)
        return DecodedScalar(n, d, unit)
    }

    private fun quantityField(o: JsonObject, key: String, type: String, unit: String, extras: MutableMap<String, JsonElement>): DecodedFields.Quantity { shape(o, setOf(key), "/fields", extras); return DecodedFields.Quantity(key, quantity(o.obj(key, "/fields/$key"), type, unit, "/fields/$key", extras)) }
    private fun scalarField(o: JsonObject, key: String, unit: String, extras: MutableMap<String, JsonElement>): DecodedFields.Scalar { shape(o, setOf(key), "/fields", extras); return DecodedFields.Scalar(key, scalar(o.obj(key, "/fields/$key"), unit, "/fields/$key", extras)) }
    private fun integerField(o: JsonObject, key: String, extras: MutableMap<String, JsonElement>): DecodedFields.IntegerValue { shape(o, setOf(key), "/fields", extras); return DecodedFields.IntegerValue(key, o.long(key, "/fields/$key")) }
    private fun enumFields(o: JsonObject, keys: List<String>, extras: MutableMap<String, JsonElement>): DecodedFields.EnumValues { shape(o, keys.toSet(), "/fields", extras); return DecodedFields.EnumValues(keys.associateWith { enum(o.obj(it, "/fields/$it"), "/fields/$it", extras) }) }
    private fun quantitySamples(o: JsonObject, key: String, type: String, unit: String, extras: MutableMap<String, JsonElement>): DecodedFields.QuantitySamples { shape(o, setOf("samples"), "/fields", extras); val samples = o.array("samples", "/fields/samples").mapIndexed { i, e -> val p = "/fields/samples/$i"; val s = e.asObject(p); shape(s, setOf("time", key), p, extras); DecodedTimedQuantity(instant(s.obj("time", "$p/time"), "$p/time", extras), quantity(s.obj(key, "$p/$key"), type, unit, "$p/$key", extras)) }; ordered(samples.map { it.time }, "/fields/samples"); return DecodedFields.QuantitySamples(key, samples) }
    private fun doubleSamples(o: JsonObject, key: String, extras: MutableMap<String, JsonElement>): DecodedFields.DoubleSamples { shape(o, setOf("samples"), "/fields", extras); val samples = o.array("samples", "/fields/samples").mapIndexed { i, e -> val p = "/fields/samples/$i"; val s = e.asObject(p); shape(s, setOf("time", key), p, extras); DecodedTimedDouble(instant(s.obj("time", "$p/time"), "$p/time", extras), s.finite(key, "$p/$key")) }; ordered(samples.map { it.time }, "/fields/samples"); return DecodedFields.DoubleSamples(key, samples) }
    private fun timedLongs(a: JsonArray, key: String, extras: MutableMap<String, JsonElement>): List<DecodedTimedLong> { val samples = a.mapIndexed { i, e -> val p = "/fields/samples/$i"; val s = e.asObject(p); shape(s, setOf("time", key), p, extras); DecodedTimedLong(instant(s.obj("time", "$p/time"), "$p/time", extras), s.long(key, "$p/$key")) }; ordered(samples.map { it.time }, "/fields/samples"); return samples }
    private fun vo2(o: JsonObject, extras: MutableMap<String, JsonElement>): DecodedFields.Vo2Max { shape(o, setOf("vo2MillilitersPerMinuteKilogram", "measurementMethod"), "/fields", extras); return DecodedFields.Vo2Max(scalar(o.obj("vo2MillilitersPerMinuteKilogram", "/fields/vo2MillilitersPerMinuteKilogram"), "mL/(min*kg)", "/fields/vo2MillilitersPerMinuteKilogram", extras), enum(o.obj("measurementMethod", "/fields/measurementMethod"), "/fields/measurementMethod", extras)) }
    private fun version(o: JsonObject, p: String, extras: MutableMap<String, JsonElement>): DecodedFhirVersion { shape(o, setOf("major", "minor", "patch"), p, extras); return DecodedFhirVersion(o.int("major", "$p/major"), o.int("minor", "$p/minor"), o.int("patch", "$p/patch")) }

    private fun offset(e: JsonElement?, p: String): ZoneOffset? { if (e == null) fail("missing", p); if (e === JsonNull) return null; val value = (e as? JsonPrimitive)?.intOrNull ?: fail("integer", p); if (value !in -64_800..64_800) fail("offset", p); return try { ZoneOffset.ofTotalSeconds(value) } catch (_: Exception) { fail("offset", p) } }
    private fun stringMap(o: JsonObject, p: String): Map<String, String> = o.mapValues { (key, value) -> (value as? JsonPrimitive)?.takeIf { it.isString }?.content ?: fail("string", "$p/$key") }.toSortedMap()
    private fun shape(o: JsonObject, keys: Set<String>, p: String, extras: MutableMap<String, JsonElement>) { keys.forEach { o.required(it, p) }; unknown(o, keys, p, extras) }
    private fun unknown(o: JsonObject, keys: Set<String>, p: String, extras: MutableMap<String, JsonElement>) { o.filterKeys { it !in keys }.forEach { (key, value) -> extras["${if (p == "/") "" else p}/$key"] = value } }
    private fun ordered(values: List<DecodedInstant>, p: String) { if (values.zipWithNext().any { (a, b) -> a > b }) fail("nested_order", p) }
    private fun digest(bytes: ByteArray): String = MessageDigest.getInstance("SHA-256").digest(bytes).joinToString("") { "%02x".format(it) }

    private fun JsonObject.required(key: String, p: String): JsonElement = this[key] ?: fail("missing", "${if (p == "/") "" else p}/$key")
    private fun JsonObject.string(key: String, p: String, nonEmpty: Boolean = false): String { val primitive = this[key] as? JsonPrimitive ?: fail("string", p); if (!primitive.isString) fail("string", p); return primitive.content.also { if (nonEmpty && it.isEmpty()) fail("empty", p) } }
    private fun JsonObject.nullableString(key: String, p: String): String? { val e = required(key, p.substringBeforeLast('/').ifEmpty { "/" }); if (e === JsonNull) return null; val primitive = e as? JsonPrimitive ?: fail("string", p); if (!primitive.isString) fail("string", p); return primitive.content }
    private fun JsonObject.obj(key: String, p: String): JsonObject = (this[key] ?: fail("missing", p)) as? JsonObject ?: fail("object", p)
    private fun JsonObject.nullableObj(key: String, p: String): JsonObject? { val e = this[key] ?: fail("missing", p); return if (e === JsonNull) null else e as? JsonObject ?: fail("object", p) }
    private fun JsonObject.array(key: String, p: String): JsonArray = (this[key] ?: fail("missing", p)) as? JsonArray ?: fail("array", p)
    private fun JsonObject.long(key: String, p: String): Long = (this[key] as? JsonPrimitive)?.longOrNull ?: fail("integer", p)
    private fun JsonObject.int(key: String, p: String): Int = (this[key] as? JsonPrimitive)?.intOrNull ?: fail("integer", p)
    private fun JsonObject.finite(key: String, p: String): Double = ((this[key] as? JsonPrimitive)?.doubleOrNull ?: fail("number", p)).also { if (!it.isFinite()) fail("finite", p) }
    private fun JsonObject.bool(key: String, p: String): Boolean = (this[key] as? JsonPrimitive)?.booleanOrNull ?: fail("boolean", p)
    private fun JsonElement.asObject(p: String): JsonObject = this as? JsonObject ?: fail("object", p)
    private fun fail(code: String, path: String): Nothing = throw RawDecodeException(code, path)
}
