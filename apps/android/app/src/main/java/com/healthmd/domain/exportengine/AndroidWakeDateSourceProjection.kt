package com.healthmd.domain.exportengine

import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.CsvExporter
import com.healthmd.domain.model.*
import com.healthmd.domain.render.HealthMdRenderInputAdapter
import kotlinx.coroutines.ensureActive
import kotlinx.serialization.json.*
import kotlin.coroutines.coroutineContext

/** Typed captured source details remain native; shared-core summaries retain separate authority. */
internal object AndroidWakeDateSourceProjection {
    private val json = Json { prettyPrint = true }

    fun aggregate(data: HealthData): HealthData = data.copy(
        heart = data.heart.copy(samples = emptyList(), hrvSamples = emptyList()),
        vitals = data.vitals.copy(bloodOxygenSamples = emptyList(), bloodGlucoseSamples = emptyList(), respiratoryRateSamples = emptyList(),
            bloodPressureSamples = emptyList(), bodyTemperatureSamples = emptyList(), basalBodyTemperatureSamples = emptyList(),
            skinTemperatureDeltas = emptyList()),
        nutrition = data.nutrition.copy(meals = emptyList()),
        reproductiveHealth = data.reproductiveHealth.copy(menstruationPeriods = emptyList()),
        activity = data.activity.copy(stepSamples = emptyList(), activityIntensityEntries = emptyList()),
        mindfulness = data.mindfulness.copy(sessions = emptyList()),
        plannedWorkouts = emptyList(),
        medicalResources = MedicalResourcesData(),
        compatibilityProvenance = null,
    )

    suspend fun compose(request: FrozenDailyAggregateExportRequest, plan: ExportArtifactPlan, semanticResult: ByteArray): ExportArtifactPlan {
        coroutineContext.ensureActive()
        require(plan.profile == request.profile)
        val context = requireNotNull(request.captureContext)
        require(request.profile == AndroidExportProfile.android_sleep_v6 && context.sleepDayAttribution == SleepDayAttribution.MORNING_ENDS)
        val (root, details) = nativeParts(request.data, request.metricSelection, request.customization,
            request.includeGranularData, context, semanticResult) ?: return plan
        val selected = request.data.filtered(request.metricSelection, context)
        val aliases = if (request.customization.includeLegacyAndroidAliases) {
            val canonicalKeys = HealthDataFields.extractForWakeDate(selected, request.customization.unitConverter,
                request.customization.timeFormat).mapTo(mutableSetOf()) { it.key }
            HealthDataFields.extractForWakeDate(selected, request.customization.unitConverter, request.customization.timeFormat,
                includeLegacyAndroidAliases = true).filter { it.value != null && it.key !in canonicalKeys }
        } else emptyList()
        val formats = request.formats.associateBy(request::relativePath)
        val items = plan.items.map { item ->
            coroutineContext.ensureActive()
            val format = requireNotNull(formats[item.relativePath])
            val aggregate = item.content.decodeToString()
            val text = when (format) {
                ExportFormat.JSON -> {
                    json.encodeToString(JsonElement.serializer(), composeJson(Json.parseToJsonElement(aggregate).jsonObject, root))
                }
                ExportFormat.CSV -> buildString {
                    append(aggregate)
                    if (!aggregate.endsWith('\n')) append('\n')
                    for (row in details.getValue("csv_rows").jsonArray) {
                        append(listOf("date", "category", "metric", "value", "unit", "timestamp")
                            .joinToString(",") { csv(row.jsonObject.getValue(it).jsonPrimitive.content) })
                        append('\n')
                    }
                    if (request.customization.includeLegacyAndroidAliases) {
                        append(legacyCsvAliasRows(selected, request.customization))
                    }
                }
                ExportFormat.MARKDOWN -> buildString {
                    append(aggregate)
                    for (block in details.getValue("markdown_blocks").jsonArray) {
                        val value = block.jsonObject
                        append("\n").append("#".repeat(request.customization.markdownTemplate.sectionHeaderLevel))
                            .append(' ').append(value.getValue("heading").jsonPrimitive.content).append('\n')
                        for (line in value.getValue("lines").jsonArray) append(line.jsonPrimitive.content).append('\n')
                    }
                }
                ExportFormat.OBSIDIAN_BASES -> {
                    require(aggregate.startsWith("---\n"))
                    val end = aggregate.indexOf("\n---", 4)
                    require(end >= 0 && !aggregate.substring(0, end).contains("\nnative_quantity_details:"))
                    buildString {
                        append(aggregate.substring(0, end))
                        for (block in details.getValue("bases_frontmatter_blocks").jsonArray) {
                            val value = block.jsonObject
                            val key = value.getValue("key").jsonPrimitive.content
                            require(key in setOf("native_quantity_details", "sleep_stage_details", "sleep_session_details", "native_workout_details",
                                "native_correlation_details", "native_activity_details", "native_mindfulness_details",
                                "native_planned_workout_details", "native_medical_resource_details", "native_provider_provenance",
                                "native_android_record_details"))
                            require(!aggregate.substring(0, end).contains("\n$key:"))
                            append("\n").append(key).append(":\n")
                            for (line in value.getValue("lines").jsonArray) append(line.jsonPrimitive.content).append('\n')
                        }
                        append(aggregate.substring(end))
                    }
                }
            }
            val withFrontmatter = if (format == ExportFormat.OBSIDIAN_BASES ||
                (format == ExportFormat.MARKDOWN && request.includeMetadata)) {
                val fields = aliases.mapNotNull { field -> request.customization.frontmatterConfig.outputKey(field.key)
                    ?.let { Triple(it, field.value.toString(), field.unit) } }.toMutableList()
                if (format == ExportFormat.OBSIDIAN_BASES) selected.compatibilityProvenance?.let { provenance ->
                    fields += HealthMdRenderInputAdapter.provenanceFrontmatterFields(provenance).map { field ->
                        val key = field.getValue("key").jsonPrimitive.content
                        val value = if (key == "healthmd_all_connected_merge_policy") JsonPrimitive(provenance.mergePolicyId).toString()
                            else field.getValue("value").jsonPrimitive.content.replace("\n", "\\n").replace("\r", "\\r")
                        Triple(key, value, "")
                    }
                }
                appendFrontmatter(text, fields)
            } else text
            val bytes = withFrontmatter.encodeToByteArray()
            val hash = sha256Hex(bytes)
            item.copy(artifactId = artifactIdHex(plan.requestId, plan.sessionId, plan.profile, item.relativePath,
                item.mediaType, item.writeMode, hash), content = bytes, sha256 = hash)
        }
        return ExportArtifactPlan(plan.schema, plan.artifactPlanVersion, plan.requestId, plan.sessionId, plan.profile, items)
    }

    /** API and loose files share source validation and ownership; arrays never enter aggregate FFI. */
    suspend fun composeAPIRecord(data: HealthData, settings: ExportSettings, context: AndroidCaptureContext,
        semanticResult: ByteArray, aggregate: JsonObject): JsonObject {
        coroutineContext.ensureActive()
        val (root, _) = nativeParts(data, settings.metricSelection, settings.formatCustomization.copy(
            unitPreference = UnitPreference.METRIC, includeLegacyAndroidAliases = false),
            settings.includeGranularData, context, semanticResult) ?: return aggregate
        return composeJson(aggregate, root)
    }

    private fun nativeParts(data: HealthData, selection: MetricSelectionState, customization: FormatCustomization,
        includeGranularData: Boolean, context: AndroidCaptureContext, semanticResult: ByteArray): Pair<JsonObject, JsonObject>? {
        val selected = data.filtered(selection, context)
        val source = HealthData(date = selected.date, sleep = selected.sleep, workouts = selected.workouts,
            plannedWorkouts = selected.plannedWorkouts, medicalResources = selected.medicalResources,
            compatibilityProvenance = selected.compatibilityProvenance,
            // Preserve the adapter's fail-closed admission of raw interval arrays with no selected owner.
            activity = ActivityData(stepSamples = data.activity.stepSamples, activityIntensityEntries = data.activity.activityIntensityEntries),
            mindfulness = MindfulnessData(sessions = data.mindfulness.sessions),
            heart = HeartData(samples = selected.heart.samples, hrvSamples = selected.heart.hrvSamples),
            vitals = VitalsData(bloodPressureSamples = data.vitals.bloodPressureSamples, bloodOxygenSamples = selected.vitals.bloodOxygenSamples,
                bloodGlucoseSamples = selected.vitals.bloodGlucoseSamples, respiratoryRateSamples = selected.vitals.respiratoryRateSamples,
                bodyTemperatureSamples = selected.vitals.bodyTemperatureSamples,
                basalBodyTemperatureSamples = selected.vitals.basalBodyTemperatureSamples,
                skinTemperatureDeltas = selected.vitals.skinTemperatureDeltas),
            nutrition = NutritionData(meals = selected.nutrition.meals),
            reproductiveHealth = ReproductiveHealthData(menstruationPeriods = selected.reproductiveHealth.menstruationPeriods))
        if (!source.heart.hasData && !source.vitals.hasData && !source.activity.hasData && !source.mindfulness.hasData &&
            !source.nutrition.hasData && !source.reproductiveHealth.hasData &&
            source.sleep.stages.isEmpty() && source.sleep.sessions.isEmpty() && source.workouts.isEmpty() &&
            source.plannedWorkouts.isEmpty() && !source.medicalResources.hasData &&
            source.compatibilityProvenance == null && !customization.includeLegacyAndroidAliases) return null
        val root = Json.parseToJsonElement(JsonExporter().export(source, customization, includeGranularData, context)).jsonObject
        val keys = Json.parseToJsonElement(semanticResult.decodeToString()).jsonObject.getValue("selected_output_keys").jsonArray
            .map { it.jsonPrimitive.content }
        require(keys.distinct().size == keys.size)
        // Source authority follows the frozen metric selection. Hiding summary frontmatter
        // changes presentation without revoking the selected native records.
        val sleep = root["sleep"]?.jsonObject
        val details = listOf(
            HealthMdRenderInputAdapter.quantityDetails(root, source.date.toString(), keys),
            HealthMdRenderInputAdapter.sleepDetails(sleep?.get("sleepStages")?.jsonArray ?: JsonArray(emptyList()),
                sleep?.get("sleepSessions")?.jsonArray ?: JsonArray(emptyList()), source.date.toString(), keys),
            HealthMdRenderInputAdapter.workoutDetails(root, source.date.toString(), keys),
            HealthMdRenderInputAdapter.bloodPressureDetails(root, source.date.toString(), keys),
            HealthMdRenderInputAdapter.activityDetails(root, source.date.toString(), keys),
            HealthMdRenderInputAdapter.mindfulnessDetails(root, source.date.toString(), keys),
            remainingNativeDetails(root, source.date.toString()),
            HealthMdRenderInputAdapter.plannedAndMedicalDetails(root, source.date.toString(), keys),
            provenanceDetails(root, source.date.toString()),
        ).reduce(HealthMdRenderInputAdapter::mergeDetails)
        return root to details
    }

    private fun composeJson(aggregate: JsonObject, root: JsonObject): JsonObject {
        val sourceArrays = listOf("heart" to "heartRateSamples", "heart" to "hrvSamples", "vitals" to "bloodOxygenSamples",
            "vitals" to "bloodGlucoseSamples", "vitals" to "respiratoryRateSamples",
            "sleep" to "sleepStages", "sleep" to "sleepSessions", "vitals" to "bloodPressureSamples",
            "activity" to "stepSamples", "activity" to "activityIntensity", "mindfulness" to "sessions",
            "vitals" to "bodyTemperatureSamples", "vitals" to "basalBodyTemperatureSamples",
            "vitals" to "skinTemperatureDeltas", "nutrition" to "meals",
            "reproductiveHealth" to "menstruationPeriods")
        val result = aggregate.toMutableMap()
        for ((category, field) in sourceArrays) {
            val samples = root[category]?.jsonObject?.get(field) ?: continue
            val values = result[category]?.jsonObject?.toMutableMap() ?: mutableMapOf()
            require(field !in values)
            values[field] = samples
            result[category] = JsonObject(values)
        }
        for (key in listOf("workouts", "plannedWorkouts", "medicalResources")) {
            root[key]?.let { value ->
                require(key !in result)
                result[key] = value
            }
        }
        root["metadata"]?.jsonObject?.get("provenance")?.let { provenance ->
            val metadata = result["metadata"]?.jsonObject?.toMutableMap() ?: mutableMapOf()
            require("provenance" !in metadata)
            metadata["provenance"] = provenance
            result["metadata"] = JsonObject(metadata)
        }
        return JsonObject(result)
    }

    /** Preserve already-captured Android records without extending shared quantity identities. */
    private fun remainingNativeDetails(root: JsonObject, ownerDate: String): JsonObject {
        val definitions = listOf(
            Triple("vitals", "bodyTemperatureSamples", "Body Temperature Sample"),
            Triple("vitals", "basalBodyTemperatureSamples", "Basal Body Temperature Sample"),
            Triple("vitals", "skinTemperatureDeltas", "Skin Temperature Delta"),
            Triple("nutrition", "meals", "Meal"),
            Triple("reproductiveHealth", "menstruationPeriods", "Menstruation Period"),
        )
        val rows = mutableListOf<JsonObject>()
        val lines = mutableListOf("| Native Record (JSON) |", "|---|")
        val yaml = mutableListOf<String>()
        for ((category, field, label) in definitions) {
            val records = root[category]?.jsonObject?.get(field)?.jsonArray ?: continue
            for (element in records) {
                val record = buildJsonObject { put("metric", field); put("record", element) }.toString()
                val value = element.jsonObject
                val timestamp = value["exactTime"]?.jsonObject?.get("iso8601")?.jsonPrimitive?.contentOrNull
                    ?: value["timestamp"]?.jsonPrimitive?.contentOrNull
                    ?: value["startTimeISO"]?.jsonPrimitive?.contentOrNull
                    ?: throw HealthMdRenderInputAdapter.AdapterException("wake-date native detail clock is missing")
                if (runCatching { java.time.Instant.parse(timestamp) }.isFailure) {
                    throw HealthMdRenderInputAdapter.AdapterException("wake-date native detail clock is incompatible")
                }
                rows += buildJsonObject {
                    put("date", ownerDate); put("category", "Native Detail"); put("metric", label)
                    put("value", record); put("unit", "json"); put("timestamp", timestamp); put("ordinal", rows.size)
                }
                lines += "| ${nativeJsonCodeCell(record)} |"
                yaml += "  - $record"
            }
        }
        return buildJsonObject {
            put("output_keys", JsonArray(emptyList()))
            put("csv_rows", JsonArray(rows))
            put("markdown_blocks", buildJsonArray {
                if (rows.isNotEmpty()) add(buildJsonObject {
                    put("heading", "Android Native Record Details")
                    put("lines", JsonArray(lines.map(::JsonPrimitive))); put("ordinal", 0)
                })
            })
            put("bases_frontmatter_blocks", buildJsonArray {
                if (yaml.isNotEmpty()) add(buildJsonObject {
                    put("key", "native_android_record_details")
                    put("lines", JsonArray(yaml.map(::JsonPrimitive))); put("ordinal", 0)
                })
            })
        }
    }

    private fun nativeJsonCodeCell(encoded: String): String = "`" +
        encoded.replace("|", "\\u007c").replace("`", "\\u0060") + "`"

    private fun appendFrontmatter(text: String, fields: List<Triple<String, String, String>>): String {
        if (fields.isEmpty()) return text
        require(text.startsWith("---\n"))
        val end = text.indexOf("\n---", 4)
        require(end >= 0)
        var head = text.substring(0, end)
        fun yamlKey(key: String): String = if (key.matches(Regex("[A-Za-z_][A-Za-z0-9_-]*"))) key else JsonPrimitive(key).toString()
        val seen = mutableSetOf<String>()
        for ((key, value, _) in fields) {
            val encodedKey = yamlKey(key)
            require(seen.add(key) && head.lineSequence().none { it.startsWith("$key:") || it.startsWith("$encodedKey:") }) {
                "Native frontmatter fields conflict."
            }
            head += "\n$encodedKey: $value"
        }
        val units = fields.filter { it.third.isNotBlank() }.joinToString("\n") { (key, _, unit) ->
            val encodedKey = yamlKey(key)
            require(head.lineSequence().none { it.startsWith("  $key:") || it.startsWith("  $encodedKey:") }) {
                "Native alias units conflict."
            }
            "  $encodedKey: ${JsonPrimitive(unit)}"
        }
        if (units.isNotEmpty()) head = if ("\nunits:\n" in head) head.replaceFirst("\nunits:\n", "\nunits:\n$units\n")
            else "$head\nunits:\n$units"
        return head + text.substring(end)
    }

    /** Reuse only the existing alias row delta, with no historical sleep projection or file header. */
    private fun legacyCsvAliasRows(data: HealthData, customization: FormatCustomization): String {
        val source = data.copy(sleep = SleepData(), plannedWorkouts = emptyList(), medicalResources = MedicalResourcesData(),
            compatibilityProvenance = null)
        val native = customization.copy(unitPreference = UnitPreference.METRIC, dateFormat = DateFormatPreference.ISO8601,
            compatibilitySchemaProfile = CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5)
        val exporter = CsvExporter()
        val baseline = exporter.export(source, native.copy(includeLegacyAndroidAliases = false), false)
            .lineSequence().groupingBy { it }.eachCount().toMutableMap()
        return buildString {
            for (line in exporter.export(source, native.copy(includeLegacyAndroidAliases = true), false).lineSequence()) {
                val count = baseline[line] ?: 0
                if (count > 0) baseline[line] = count - 1 else if (line.isNotEmpty()) append(line).append('\n')
            }
        }
    }

    private fun provenanceDetails(root: JsonObject, date: String): JsonObject {
        val value = root["metadata"]?.jsonObject?.get("provenance")
        val encoded = value?.toString()
        val code = encoded?.replace("|", "\\u007c")?.replace("`", "\\u0060")
            ?.replace("<", "\\u003c")?.replace(">", "\\u003e")?.replace("&", "\\u0026")
        return buildJsonObject {
            put("output_keys", JsonArray(emptyList()))
            put("csv_rows", buildJsonArray { if (encoded != null) add(buildJsonObject {
                put("date", date); put("category", "Metadata"); put("metric", "Provider Provenance")
                put("value", encoded); put("unit", "json"); put("timestamp", ""); put("ordinal", 0)
            }) })
            put("markdown_blocks", buildJsonArray { if (encoded != null) add(buildJsonObject {
                put("heading", "Provider Provenance"); put("lines", buildJsonArray { add("`$code`") }); put("ordinal", 0)
            }) })
            put("bases_frontmatter_blocks", buildJsonArray { if (encoded != null) add(buildJsonObject {
                put("key", "native_provider_provenance"); put("lines", buildJsonArray { add("  - $encoded") }); put("ordinal", 0)
            }) })
        }
    }

    private fun csv(value: String): String = if (value.any { it == ',' || it == '"' || it == '\n' || it == '\r' }) {
        "\"${value.replace("\"", "\"\"")}\""
    } else value
}
