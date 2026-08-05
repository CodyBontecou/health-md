package com.healthmd.domain.semantic

import com.healthmd.core.CoreMetricRegistrySnapshot
import com.healthmd.core.HealthMdCoreService
import com.healthmd.domain.model.ExactSourceIdentity
import com.healthmd.domain.model.ExactSourceTimestamp
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HealthDataFields
import com.healthmd.domain.model.HEALTHMD_CORE_REGISTRY_SHA256
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.TimeFormatPreference
import com.healthmd.domain.model.UnitConverter
import java.security.MessageDigest
import java.time.ZoneId
import java.time.ZoneOffset
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put

/**
 * Deterministic Android post-capture adapter for `healthmd.semantic_input` v1.
 *
 * This adapter never calls Health Connect. One already-captured [HealthData] tree is represented as
 * SDK aggregate facts and passed in coarse batches. Rust performs selection filtering; existing
 * exporters remain byte-authoritative through M4.
 */
object HealthMdSemanticInputAdapter {
    const val SEMANTIC_INPUT_VERSION: Int = 1
    const val CANONICAL_MODEL_VERSION: Int = 1
    const val REGISTRY_VERSION: Int = 1

    enum class Profile(
        val registryId: String,
        val wireId: String,
        val includeAndroidNativeFields: Boolean,
    ) {
        FROZEN_V4("android_frozen_v4", "android_frozen_v4", false),
        ANALYTICAL_V5("android_analytical_v5", "android_analytical_v5", true),
    }

    data class ExtensionLocation(
        val dayIndex: Int,
        val namespace: String,
        val recordIndex: Int,
    )

    data class EncodedBatch(
        val bytes: ByteArray,
        val nextSourceOrdinal: ULong,
        val retainedExtensionTokens: List<String>,
        /** Native side-table locations; provider payload objects never cross FFI. */
        val extensionLocations: Map<String, ExtensionLocation>,
    )

    class AdapterException(message: String) : IllegalArgumentException(message)

    fun sessionConfiguration(
        sessionId: String,
        profile: Profile,
        selection: MetricSelectionState,
        registry: CoreMetricRegistrySnapshot,
        calendarTimeZone: String,
        disabledOutputKeys: Set<String> = emptySet(),
        retainPlatformExtensions: Boolean = false,
    ): ByteArray {
        requireRegistry(profile, registry)
        validateTimeZone(calendarTimeZone)
        val selected = registry.metrics
            .filter { selection.isEnabled(it.selectionId) }
            .map { JsonPrimitive(it.selectionId) }
        if (!registry.outputs.map { it.key }.containsAll(disabledOutputKeys)) {
            throw AdapterException("disabled output keys are incompatible")
        }
        val disabledOutputs = registry.outputs.map { it.key }.filter(disabledOutputKeys::contains)
        return canonicalBytes(
            buildJsonObject {
                put("schema", "healthmd.semantic_session_config")
                put("semantic_input_version", SEMANTIC_INPUT_VERSION)
                put("canonical_model_version", CANONICAL_MODEL_VERSION)
                put("registry_version", REGISTRY_VERSION)
                put("registry_sha256", registry.registrySha256)
                put("profile_revision", registry.profileRevision.toLong())
                put("session_id", sessionId)
                put("profile", profile.wireId)
                put("calendar_time_zone", calendarTimeZone)
                put("selected_selection_ids", JsonArray(selected))
                put("disabled_output_keys", JsonArray(disabledOutputs.map(::JsonPrimitive)))
                put("retain_platform_extensions", retainPlatformExtensions)
                put("rollup_periods", JsonArray(emptyList()))
            },
        )
    }

    /** Encodes unfiltered daily data so Rust is the sole metric-selection filter. */
    fun batch(
        sessionId: String,
        profile: Profile,
        batchIndex: UInt,
        finalBatch: Boolean,
        healthData: List<HealthData>,
        registry: CoreMetricRegistrySnapshot,
        converter: UnitConverter,
        calendarTimeZone: String,
        timeFormat: TimeFormatPreference = TimeFormatPreference.HOUR_24,
        includeLegacyAndroidAliases: Boolean = false,
        startingSourceOrdinal: ULong = 0u,
    ): EncodedBatch {
        requireRegistry(profile, registry)
        validateTimeZone(calendarTimeZone)
        val metricBySelection = registry.metrics.associateBy { it.selectionId }
        val outputByKey = registry.outputs.associateBy { it.key }
        val bloodPressureSelectionIds = registry.metrics.map { it.selectionId }.filter {
            it.contains("systolic") || it.contains("diastolic")
        }
        var ordinal = startingSourceOrdinal
        fun advanceOrdinal() {
            if (ordinal == ULong.MAX_VALUE) {
                throw AdapterException("source ordinal exceeds limit")
            }
            ordinal += 1uL
        }
        val retainedTokens = mutableListOf<String>()
        val extensionLocations = mutableMapOf<String, ExtensionLocation>()
        val capturedDays = healthData.withIndex().sortedBy { it.value.date }
        if (capturedDays.map { it.value.date }.distinct().size != capturedDays.size) {
            throw AdapterException("owner dates must be unique")
        }
        val records = buildJsonArray {
            capturedDays.forEach { capturedDay ->
                val dayIndex = capturedDay.index
                val day = capturedDay.value
                val fields = HealthDataFields.extract(
                    data = day,
                    converter = converter,
                    timeFormat = timeFormat,
                    includeLegacyAndroidAliases = includeLegacyAndroidAliases,
                    includeAndroidNativeFields = profile.includeAndroidNativeFields,
                )
                fields.forEach { field ->
                    val value = field.value ?: return@forEach
                    val output = outputByKey[field.key] ?: return@forEach
                    val selectionId = output.selectionIds.firstOrNull() ?: return@forEach
                    val metric = metricBySelection[selectionId] ?: return@forEach
                    val attributedSelectionIds = if (
                        output.selectionIds.any {
                            it.contains("systolic") || it.contains("diastolic")
                        } && bloodPressureSelectionIds.size == 2
                    ) {
                        bloodPressureSelectionIds
                    } else {
                        output.selectionIds
                    }
                    advanceOrdinal()
                    add(
                        buildJsonObject {
                            put("record_id", "android-daily-${day.date}-${field.key}")
                            put("source_ordinal", ordinal.toString())
                            put("owner_date", day.date.toString())
                            put("semantic_id", metric.semanticId)
                            put("selection_ids", JsonArray(attributedSelectionIds.map(::JsonPrimitive)))
                            put("attribution", "direct")
                            put("kind", "sdk_aggregate")
                            put("output_key", field.key)
                            put("aggregation", "pass_through")
                            put("start", JsonNull)
                            put("end", JsonNull)
                            put("value", semanticValue(day, field.key, value, field.unit))
                            put("weight", JsonNull)
                            put("attributes", JsonObject(emptyMap()))
                            put("extensions", JsonArray(emptyList()))
                        },
                    )
                }

                fun addExtension(
                    namespace: String,
                    recordIndex: Int,
                    nativeIdentity: String,
                    selectionIds: List<String>,
                ) {
                    val recognized = selectionIds.filter(metricBySelection::containsKey).distinct().sorted()
                    val selectionId = recognized.firstOrNull() ?: return
                    val metric = metricBySelection.getValue(selectionId)
                    advanceOrdinal()
                    val token = stableToken(namespace, "${day.date}\u001f$nativeIdentity")
                    retainedTokens += token
                    extensionLocations[token] = ExtensionLocation(dayIndex, namespace, recordIndex)
                    add(
                        buildJsonObject {
                            put("record_id", "android-extension-$token")
                            put("source_ordinal", ordinal.toString())
                            put("owner_date", day.date.toString())
                            put("semantic_id", metric.semanticId)
                            put("selection_ids", JsonArray(recognized.map(::JsonPrimitive)))
                            put("attribution", "dependency")
                            put("kind", "extension_ref")
                            put("output_key", JsonNull)
                            put("aggregation", "pass_through")
                            put("start", JsonNull)
                            put("end", JsonNull)
                            put("value", JsonNull)
                            put("weight", JsonNull)
                            put("attributes", JsonObject(emptyMap()))
                            put(
                                "extensions",
                                buildJsonArray {
                                    add(buildJsonObject {
                                        put("namespace", namespace)
                                        put("version", 1)
                                        put("retention_token", token)
                                        put("selection_ids", JsonArray(recognized.map(::JsonPrimitive)))
                                    })
                                },
                            )
                        },
                    )
                }

                day.activity.stepSamples.forEachIndexed { index, sample ->
                    addExtension(
                        "android.health_connect_step",
                        index,
                        stableSourceIdentity(sample.identity, "${sample.exactTime}:${sample.time}:${sample.value}"),
                        listOf("steps"),
                    )
                }
                day.heart.samples.forEachIndexed { index, sample ->
                    addExtension(
                        "android.health_connect_heart_rate",
                        index,
                        stableSourceIdentity(sample.identity, "${sample.exactTime}:${sample.time}:${sample.value}"),
                        listOf("avg_hr", "min_hr", "max_hr", "walking_hr"),
                    )
                }
                day.heart.hrvSamples.forEachIndexed { index, sample ->
                    addExtension(
                        "android.health_connect_hrv",
                        index,
                        stableSourceIdentity(sample.identity, "${sample.exactTime}:${sample.time}:${sample.value}"),
                        listOf("hrv"),
                    )
                }
                day.vitals.bloodPressureSamples.forEachIndexed { index, sample ->
                    addExtension(
                        "android.health_connect_blood_pressure",
                        index,
                        stableSourceIdentity(sample.identity, "${sample.exactTime}:${sample.time}:${sample.systolic}:${sample.diastolic}"),
                        listOf("bp_systolic", "bp_diastolic"),
                    )
                }
                day.sleep.stages.forEachIndexed { index, stage ->
                    val selection = when (stage.stage.lowercase()) {
                        "deep" -> "sleep_deep"
                        "rem" -> "sleep_rem"
                        "light", "core", "sleeping" -> "sleep_light"
                        "awake", "wake" -> "sleep_awake"
                        else -> "sleep_total"
                    }
                    addExtension(
                        "android.health_connect_sleep_stage",
                        index,
                        stableSourceIdentity(stage.identity, "${stage.exactStartTime}:${stage.exactEndTime}:${stage.stage}"),
                        listOf(selection),
                    )
                }
                day.workouts.forEachIndexed { index, workout ->
                    addExtension("android.workout_detail", index, workout.id, listOf("workouts"))
                }
                day.plannedWorkouts.forEachIndexed { index, workout ->
                    addExtension("android.planned_workout", index, workout.id, listOf("planned_workouts"))
                }
                day.medicalResources.resources.forEachIndexed { index, resource ->
                    addExtension(
                        "android.phr_resource",
                        index,
                        "${resource.dataSourceId}:${resource.medicalResourceId}:${resource.fhirResourceId}",
                        listOf("medical_resources"),
                    )
                }
                day.compatibilityProvenance?.let { provenance ->
                    addExtension(
                        "android.provider_provenance",
                        0,
                        "${provenance.mergePolicyId}:${provenance.providerIdsAttempted.sorted().joinToString(",")}",
                        registry.metrics.map { it.selectionId },
                    )
                }
            }
        }
        val bytes = canonicalBytes(
            buildJsonObject {
                put("schema", "healthmd.semantic_input")
                put("semantic_input_version", SEMANTIC_INPUT_VERSION)
                put("session_id", sessionId)
                put("batch_index", batchIndex.toLong())
                put("final_batch", finalBatch)
                put("owner_dates", JsonArray(capturedDays.map { JsonPrimitive(it.value.date.toString()) }))
                put("records", records)
            },
        )
        return EncodedBatch(bytes, ordinal, retainedTokens, extensionLocations)
    }

    private fun stableSourceIdentity(identity: ExactSourceIdentity?, fallback: String): String =
        identity?.nativeId
            ?: identity?.clientRecordId
            ?: identity?.syntheticId
            ?: fallback

    private fun stableToken(namespace: String, identity: String): String =
        MessageDigest.getInstance("SHA-256")
            .digest("$namespace\u001f$identity".encodeToByteArray())
            .joinToString("") { byte -> "%02x".format(byte.toInt() and 0xff) }

    /** Splits one captured model into valid coarse batches with stable record/token identity. */
    fun boundedBatches(
        sessionId: String,
        profile: Profile,
        firstBatchIndex: UInt = 0u,
        healthData: List<HealthData>,
        registry: CoreMetricRegistrySnapshot,
        converter: UnitConverter,
        calendarTimeZone: String,
        timeFormat: TimeFormatPreference = TimeFormatPreference.HOUR_24,
        includeLegacyAndroidAliases: Boolean = false,
        startingSourceOrdinal: ULong = 0u,
    ): List<EncodedBatch> {
        val complete = batch(
            sessionId = sessionId,
            profile = profile,
            batchIndex = firstBatchIndex,
            finalBatch = false,
            healthData = healthData,
            registry = registry,
            converter = converter,
            calendarTimeZone = calendarTimeZone,
            timeFormat = timeFormat,
            includeLegacyAndroidAliases = includeLegacyAndroidAliases,
            startingSourceOrdinal = startingSourceOrdinal,
        )
        val root = Json.parseToJsonElement(complete.bytes.decodeToString()).jsonObject
        val records = root.getValue("records").jsonArray.map { it.jsonObject }
        val ownerDates = root.getValue("owner_dates").jsonArray.map { it.jsonPrimitive.content }
        if (records.size > 100_000) throw AdapterException("semantic session exceeds record limit")
        if (ownerDates.size > 400) throw AdapterException("semantic session exceeds owner-date limit")
        val totalRecordBytes = records.sumOf { record ->
            canonicalBytes(record).size.also {
                if (it > 64 * 1024) throw AdapterException("semantic record exceeds size limit")
            }.toLong()
        }
        if (totalRecordBytes > 32L * 1024 * 1024) {
            throw AdapterException("semantic session exceeds size limit")
        }

        data class Payload(val ownerDates: List<String>, val records: List<JsonObject>)
        val payloads = mutableListOf<Payload>()
        ownerDates.forEach { ownerDate ->
            val dayRecords = records.filter {
                it.getValue("owner_date").jsonPrimitive.content == ownerDate
            }
            if (dayRecords.isEmpty()) {
                payloads += Payload(listOf(ownerDate), emptyList())
            } else {
                var chunk = mutableListOf<JsonObject>()
                dayRecords.forEach { record ->
                    val candidate = chunk + record
                    if (chunk.isNotEmpty() &&
                        (candidate.size > 4_096 || canonicalBytes(
                            batchElement(sessionId, 0u, false, listOf(ownerDate), candidate),
                        ).size > 1_048_576)
                    ) {
                        payloads += Payload(listOf(ownerDate), chunk)
                        chunk = mutableListOf(record)
                    } else {
                        chunk.add(record)
                    }
                }
                if (canonicalBytes(
                        batchElement(sessionId, 0u, false, listOf(ownerDate), chunk),
                    ).size > 1_048_576
                ) {
                    throw AdapterException("semantic batch exceeds size limit")
                }
                payloads += Payload(listOf(ownerDate), chunk)
            }
        }
        if (payloads.isEmpty()) payloads += Payload(emptyList(), emptyList())

        val batches = payloads.mapIndexed { offset, payload ->
            val index = firstBatchIndex.toULong() + offset.toULong()
            if (index > UInt.MAX_VALUE.toULong()) {
                throw AdapterException("semantic batch index exceeds limit")
            }
            val tokens = payload.records.flatMap { record ->
                record.getValue("extensions").jsonArray.mapNotNull { extension ->
                    extension.jsonObject["retention_token"]?.jsonPrimitive?.content
                }
            }.sorted()
            val nextOrdinal = payload.records.maxOfOrNull {
                it.getValue("source_ordinal").jsonPrimitive.content.toULong()
            } ?: startingSourceOrdinal
            val bytes = canonicalBytes(
                batchElement(
                    sessionId,
                    index.toUInt(),
                    offset == payloads.lastIndex,
                    payload.ownerDates,
                    payload.records,
                ),
            )
            if (bytes.size > 1_048_576) {
                throw AdapterException("semantic batch exceeds size limit")
            }
            EncodedBatch(
                bytes = bytes,
                nextSourceOrdinal = nextOrdinal,
                retainedExtensionTokens = tokens,
                extensionLocations = complete.extensionLocations.filterKeys(tokens::contains),
            )
        }
        if (batches.sumOf { it.bytes.size.toLong() } > 32L * 1024 * 1024) {
            throw AdapterException("semantic session exceeds size limit")
        }
        return batches
    }

    private fun batchElement(
        sessionId: String,
        batchIndex: UInt,
        finalBatch: Boolean,
        ownerDates: List<String>,
        records: List<JsonObject>,
    ): JsonObject = buildJsonObject {
        put("schema", "healthmd.semantic_input")
        put("semantic_input_version", SEMANTIC_INPUT_VERSION)
        put("session_id", sessionId)
        put("batch_index", batchIndex.toLong())
        put("final_batch", finalBatch)
        put("owner_dates", JsonArray(ownerDates.map(::JsonPrimitive)))
        put("records", JsonArray(records))
    }

    /** Maps [ExactSourceTimestamp] without reconstructing or inferring a source offset. */
    fun exactTimestamp(
        timestamp: ExactSourceTimestamp,
        calendarUtcOffsetSeconds: Int,
    ): JsonObject = buildJsonObject {
        put("epoch_seconds", timestamp.epochSecond.toString())
        put("nanoseconds", timestamp.nano)
        put(
            "source_utc_offset_seconds",
            timestamp.offset?.let { JsonPrimitive(ZoneOffset.of(it).totalSeconds) } ?: JsonNull,
        )
        put("calendar_utc_offset_seconds", calendarUtcOffsetSeconds)
    }

    fun binary64(value: Double, unitId: String): JsonObject {
        if (!value.isFinite()) throw AdapterException("semantic number must be finite")
        val bits = java.lang.Double.doubleToRawLongBits(value)
        return buildJsonObject {
            put("value_type", "number")
            put(
                "number",
                buildJsonObject {
                    put("representation", "binary64")
                    put("bits", bits.toULong().toString(16).padStart(16, '0'))
                },
            )
            put("unit", buildJsonObject { put("id", unitId) })
        }
    }

    fun canonicalBytes(element: JsonElement): ByteArray =
        JSON.encodeToString(JsonElement.serializer(), canonicalElement(element)).encodeToByteArray()

    private fun validateTimeZone(value: String) {
        if (value !in ZoneId.getAvailableZoneIds()) {
            throw AdapterException("calendar timezone is invalid")
        }
    }

    private fun requireRegistry(profile: Profile, registry: CoreMetricRegistrySnapshot) {
        val expectedPublicProfile = when (profile) {
            Profile.FROZEN_V4 -> "android-frozen-v4"
            Profile.ANALYTICAL_V5 -> "android-analytical-v5"
        }
        val expectedSchemaVersion = when (profile) {
            Profile.FROZEN_V4 -> 4u
            Profile.ANALYTICAL_V5 -> 5u
        }
        if (registry.profileId != profile.registryId ||
            registry.publicProfileId != expectedPublicProfile ||
            registry.publicSchemaVersion != expectedSchemaVersion ||
            registry.profileRevision != 1u ||
            registry.registryVersion != REGISTRY_VERSION.toUInt() ||
            registry.registrySha256 != HEALTHMD_CORE_REGISTRY_SHA256 ||
            registry.publicSchema != "healthmd.health_data"
        ) {
            throw AdapterException("shared-core registry metadata is incompatible")
        }
    }

    private fun semanticValue(day: HealthData, key: String, value: Any, unit: String): JsonElement {
        val sourceTime = when (key) {
            "sleep_bedtime" -> day.sleep.sessionStart
                ?: day.sleep.stages.minByOrNull { it.startTime }?.startTime
            "sleep_wake" -> day.sleep.sessionEnd
                ?: day.sleep.stages.maxByOrNull { it.endTime }?.endTime
            else -> null
        }
        if (sourceTime != null) {
            return binary64(
                (sourceTime.hour * 60 + sourceTime.minute).toDouble(),
                "time_of_day_minute",
            )
        }
        // Preserve provider fractions until Rust performs the reviewed ratio-to-percent conversion.
        if (key.startsWith("blood_oxygen")) {
            val source = when {
                key.endsWith("_min") -> day.vitals.bloodOxygenMin
                key.endsWith("_max") -> day.vitals.bloodOxygenMax
                else -> day.vitals.bloodOxygenAvg
            }
            if (source != null) return binary64(source, "ratio_0_1")
        }
        if (key == "body_fat_percent" && day.body.bodyFatPercentage != null) {
            return binary64(day.body.bodyFatPercentage, "ratio_0_1")
        }
        return when (value) {
            is Byte, is Short, is Int, is Long ->
                integerValue((value as Number).toLong(), internalUnitId(unit))
            is UByte -> unsignedValue(value.toULong(), internalUnitId(unit))
            is UShort -> unsignedValue(value.toULong(), internalUnitId(unit))
            is UInt -> unsignedValue(value.toULong(), internalUnitId(unit))
            is ULong -> unsignedValue(value, internalUnitId(unit))
            is Boolean -> buildJsonObject {
                put("value_type", "boolean")
                put("boolean", value)
            }
            is Float -> binary64(value.toDouble(), internalUnitId(unit))
            is Double -> binary64(value, internalUnitId(unit))
            is String -> semanticString(value, internalUnitId(unit))
            else -> textOrList(value.toString())
        }
    }

    private fun semanticString(value: String, unitId: String): JsonElement {
        value.toULongOrNull()?.takeIf { it.toString() == value }?.let {
            return unsignedValue(it, unitId)
        }
        value.toLongOrNull()?.takeIf { it.toString() == value }?.let {
            return integerValue(it, unitId)
        }
        return value.toDoubleOrNull()?.let { binary64(it, unitId) } ?: textOrList(value)
    }

    private fun integerValue(value: Long, unitId: String): JsonObject = buildJsonObject {
        put("value_type", "number")
        put("number", buildJsonObject {
            put("representation", "signed_integer")
            put("decimal", value.toString())
        })
        put("unit", buildJsonObject { put("id", unitId) })
    }

    private fun unsignedValue(value: ULong, unitId: String): JsonObject = buildJsonObject {
        put("value_type", "number")
        put("number", buildJsonObject {
            put("representation", "unsigned_integer")
            put("decimal", value.toString())
        })
        put("unit", buildJsonObject { put("id", unitId) })
    }

    private fun textOrList(value: String): JsonElement {
        val trimmed = value.trim()
        if (trimmed.startsWith('[') && trimmed.endsWith(']')) {
            val items = trimmed.removePrefix("[").removeSuffix("]")
                .split(',').map(String::trim).filter(String::isNotEmpty).distinct().sorted()
            return buildJsonObject {
                put("value_type", "text_list")
                put("items", JsonArray(items.map(::JsonPrimitive)))
            }
        }
        return buildJsonObject {
            put("value_type", "text")
            put("text", value)
        }
    }

    private fun internalUnitId(unit: String): String = when (unit.lowercase()) {
        "steps", "count", "entries", "drinks", "events", "falls", "floors", "pushes",
        "sessions", "strokes", "uses" -> "count"
        "sec", "second", "seconds" -> "second"
        "min", "minute", "minutes" -> "minute"
        "hour", "hours" -> "hour"
        "m" -> "meter"
        "km" -> "kilometer"
        "mi" -> "mile"
        "m/s" -> "meter_per_second"
        "km/h" -> "kilometer_per_hour"
        "mph" -> "mile_per_hour"
        "cm" -> "centimeter"
        "ft/in", "in" -> "inch"
        "kg" -> "kilogram"
        "lbs", "lb" -> "pound"
        "kg/m²" -> "kilogram_per_square_meter"
        "g" -> "gram"
        "mg" -> "milligram"
        "µg", "mcg" -> "microgram"
        "l" -> "liter"
        "oz", "fl oz" -> "fluid_ounce"
        "kcal" -> "kilocalorie"
        "kcal/hr/kg" -> "kilocalorie_per_hour_kilogram"
        "bpm" -> "beat_per_minute"
        "breaths/min" -> "breath_per_minute"
        "ms" -> "millisecond"
        "%", "percent" -> "percent_0_100"
        "°c", "c" -> "degree_celsius"
        "°f", "f" -> "degree_fahrenheit"
        "mmhg" -> "millimeter_hg"
        "mg/dl" -> "milligram_per_deciliter"
        "iu" -> "international_unit"
        "w" -> "watt"
        "rpm" -> "revolution_per_minute"
        "spm", "steps/min" -> "step_per_minute"
        "db" -> "decibel"
        "µs" -> "microsiemens"
        "l/min" -> "liter_per_minute"
        "ml/kg/min" -> "milliliter_per_kilogram_minute"
        else -> "unitless"
    }

    private fun canonicalElement(element: JsonElement): JsonElement = when (element) {
        is JsonObject -> JsonObject(
            element.entries.sortedBy { it.key }
                .associate { (key, value) -> key to canonicalElement(value) },
        )
        is JsonArray -> JsonArray(element.map(::canonicalElement))
        else -> element
    }

    private val JSON = Json {
        encodeDefaults = true
        explicitNulls = true
    }
}

/** Runs blocking coarse FFI work on Default and propagates cancellation between batches. */
object HealthMdSemanticSessionRunner {
    suspend fun process(
        configurationBytes: ByteArray,
        batches: List<ByteArray>,
        service: HealthMdCoreService = HealthMdCoreService(),
    ): ByteArray = suspendCancellableCoroutine { continuation ->
        if (batches.isEmpty()) {
            continuation.resumeWith(
                Result.failure(HealthMdSemanticInputAdapter.AdapterException("semantic batches are empty")),
            )
            return@suspendCancellableCoroutine
        }
        val session = try {
            service.createSemanticSession(configurationBytes)
        } catch (error: Throwable) {
            continuation.resumeWith(Result.failure(error))
            return@suspendCancellableCoroutine
        }
        continuation.invokeOnCancellation { session.cancel() }
        Dispatchers.Default.dispatch(continuation.context) {
            try {
                var result = ByteArray(0)
                batches.forEach { batch ->
                    continuation.context.ensureActive()
                    result = session.processBatch(batch)
                    val state = Json.parseToJsonElement(result.decodeToString())
                        .jsonObject["state"]?.jsonPrimitive?.content
                    if (state == "cancelled") throw CancellationException("semantic session cancelled")
                }
                val state = Json.parseToJsonElement(result.decodeToString())
                    .jsonObject["state"]?.jsonPrimitive?.content
                if (state != "completed") {
                    throw HealthMdSemanticInputAdapter.AdapterException(
                        "semantic session did not complete",
                    )
                }
                if (continuation.isActive) {
                    continuation.resumeWith(Result.success(result))
                }
            } catch (cancelled: CancellationException) {
                session.cancel()
                if (continuation.isActive) {
                    continuation.resumeWith(Result.failure(cancelled))
                }
            } catch (error: Throwable) {
                if (continuation.isActive) {
                    continuation.resumeWith(Result.failure(error))
                }
            } finally {
                session.close()
            }
        }
    }
}

/** Health-free JSON-pointer differences for test/internal semantic shadow runs. */
object HealthMdSemanticShadowComparator {
    fun differences(legacyBytes: ByteArray, rustBytes: ByteArray): List<String> {
        val legacy = runCatching { Json.parseToJsonElement(legacyBytes.decodeToString()) }.getOrNull()
            ?: return listOf("/result/invalid_legacy_json")
        val rust = runCatching { Json.parseToJsonElement(rustBytes.decodeToString()) }.getOrNull()
            ?: return listOf("/result/invalid_rust_json")
        return differences(legacy, rust, "")
    }

    private fun differences(left: JsonElement, right: JsonElement, path: String): List<String> {
        if (left is JsonObject && right is JsonObject) {
            return (left.keys + right.keys).sorted().distinct().flatMap { key ->
                val leftValue = left[key]
                val rightValue = right[key]
                if (leftValue == null || rightValue == null) listOf("$path/$key")
                else differences(leftValue, rightValue, "$path/$key")
            }
        }
        if (left is JsonArray && right is JsonArray) {
            val count = if (left.size == right.size) emptyList() else listOf("$path/count")
            return count + (0 until minOf(left.size, right.size)).flatMap { index ->
                differences(left[index], right[index], "$path/$index")
            }
        }
        return if (left == right) emptyList() else listOf(path.ifEmpty { "/" })
    }
}
