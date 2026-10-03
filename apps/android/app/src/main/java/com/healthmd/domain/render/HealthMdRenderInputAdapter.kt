package com.healthmd.domain.render

import com.healthmd.core.CoreMetricRegistrySnapshot
import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HealthDataFields
import java.time.ZoneId
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put

/** Builds strict M5 render batches from one completed M4 result without repeating provider capture. */
object HealthMdRenderInputAdapter {
    class AdapterException(message: String) : IllegalArgumentException(message)

    data class ApiFailureOptions(
        val ownerDate: String,
        val timestamp: String,
        val reason: String,
        val errorDetails: String? = null,
    )

    data class ApiExternalRecordOptions(
        val ownerDate: String,
        val value: JsonObject,
    )

    data class ApiOptions(
        val envelopeVersion: Int,
        val exportedAt: String,
        val source: String,
        val dateRangeStart: String,
        val dateRangeEnd: String,
        val failedDateDetails: List<ApiFailureOptions> = emptyList(),
        val externalRecordSchema: String? = null,
        val externalRecordSchemaVersion: Int? = null,
        val externalRecords: List<ApiExternalRecordOptions> = emptyList(),
        val maxDaysPerBatch: Int = 7,
        val maxEncodedBytes: ULong = 8uL * 1024uL * 1024uL,
    )

    data class Options(
        val requestId: String,
        val formats: List<String>,
        val unitSystem: String = "metric",
        val includeMetadata: Boolean = true,
        val groupByCategory: Boolean = true,
        val includePlatformExtensions: Boolean = false,
        val includeGranularData: Boolean = false,
        val rawCaptureStatus: String = "not_requested",
        val writeMode: String = "overwrite",
        val useEmoji: Boolean = true,
        val sectionHeaderLevel: Int = 2,
        val bullet: String = "-",
        val includeSummary: Boolean = false,
        val customTemplate: String? = null,
        val includeDate: Boolean = true,
        val dateKey: String = "date",
        val includeType: Boolean = true,
        val typeKey: String = "type",
        val typeValue: String = "health-data",
        val customFrontmatter: Map<String, String> = emptyMap(),
        val placeholderFrontmatter: List<String> = emptyList(),
        val disabledFrontmatterKeys: List<String> = emptyList(),
        val baseDirectory: String = "health",
        val filenameTemplate: String = "{date}",
        val folderTemplate: String = "",
        val markdownFolder: String = "",
        val basesFolder: String = "",
        val jsonFolder: String = "",
        val csvFolder: String = "",
        val rollupDirectory: String = "rollups",
        val basesSuffix: String = "-bases",
        val api: ApiOptions? = null,
    )

    data class EncodedInput(
        val configuration: ByteArray,
        val batches: List<ByteArray>,
    )

    private val json = Json { explicitNulls = true }
    private const val MAX_BATCH_BYTES = 2 * 1024 * 1024
    private const val MAX_FACTS_PER_BATCH = 4_096
    private const val MAX_SESSION_BYTES = 32 * 1024 * 1024

    fun encode(
        semanticResult: ByteArray,
        registry: CoreMetricRegistrySnapshot,
        calendarTimeZone: String,
        options: Options,
        presentationByOwnerDate: Map<String, HealthData> = emptyMap(),
        presentationCustomization: FormatCustomization = FormatCustomization(),
        extensionPayloadsByOwnerDate: Map<String, List<JsonObject>> = emptyMap(),
        individualEntriesByOwnerDate: Map<String, List<JsonObject>> = emptyMap(),
        dailyNotesByOwnerDate: Map<String, JsonObject> = emptyMap(),
    ): EncodedInput {
        runCatching { ZoneId.of(calendarTimeZone) }
            .getOrElse { throw AdapterException("calendar timezone is invalid") }
        val root = runCatching { json.parseToJsonElement(semanticResult.decodeToString()).jsonObject }
            .getOrElse { throw AdapterException("semantic result is invalid") }
        requireValue(root, "schema", "healthmd.semantic_result")
        requireValue(root, "state", "completed")
        requireValue(root, "registry_sha256", registry.registrySha256)
        requireValue(root, "profile", registry.profileId)
        val revision = root["profile_revision"]?.jsonPrimitive?.content?.toUIntOrNull()
        if (revision != registry.profileRevision) throw AdapterException("semantic result is invalid")
        val sessionId = root["session_id"]?.jsonPrimitive?.contentOrNull
            ?: throw AdapterException("semantic result is invalid")
        val days = root["days"]?.jsonArray ?: throw AdapterException("semantic result is invalid")
        val effectiveOptions = if (presentationByOwnerDate.isEmpty()) options else options.copy(
            includeDate = presentationCustomization.frontmatterConfig.includeDate,
            dateKey = presentationCustomization.frontmatterConfig.customDateKey,
            includeType = presentationCustomization.frontmatterConfig.includeType,
            typeKey = presentationCustomization.frontmatterConfig.customTypeKey,
            typeValue = presentationCustomization.frontmatterConfig.customTypeValue,
            customFrontmatter = presentationCustomization.frontmatterConfig.customFields,
            placeholderFrontmatter = presentationCustomization.frontmatterConfig.placeholderFields,
            disabledFrontmatterKeys = registry.outputs.mapNotNull { output ->
                output.key.takeIf { presentationCustomization.frontmatterConfig.outputKey(it) == null }
            },
        )
        val configuration = configuration(registry, sessionId, calendarTimeZone, effectiveOptions)
        val renderDays = days.map { value ->
            val day = value.jsonObject
            val ownerDate = day["owner_date"]?.jsonPrimitive?.content
                ?: throw AdapterException("semantic day is invalid")
            renderDay(
                day,
                registry,
                presentationByOwnerDate[ownerDate],
                presentationCustomization,
                effectiveOptions,
                extensionPayloadsByOwnerDate[ownerDate].orEmpty(),
                individualEntriesByOwnerDate[ownerDate].orEmpty(),
                dailyNotesByOwnerDate[ownerDate],
            )
        }
        return EncodedInput(configuration, boundedBatches(renderDays, sessionId))
    }

    private fun configuration(
        registry: CoreMetricRegistrySnapshot,
        sessionId: String,
        timeZone: String,
        options: Options,
    ): ByteArray = encodeJson(buildJsonObject {
        put("schema", "healthmd.render_session_config")
        put("render_input_version", 1)
        put("artifact_plan_version", 1)
        put("canonical_model_version", 1)
        put("registry_version", registry.registryVersion.toInt())
        put("registry_sha256", registry.registrySha256)
        put("profile_revision", registry.profileRevision.toInt())
        put("render_profile_revision", 2)
        put("request_id", options.requestId)
        put("session_id", sessionId)
        put("profile", registry.profileId)
        put("calendar_time_zone", timeZone)
        put("locale", "en-US")
        put("formats", JsonArray(options.formats.map(::JsonPrimitive)))
        put("unit_system", options.unitSystem)
        put("include_metadata", options.includeMetadata)
        put("group_by_category", options.groupByCategory)
        put("include_platform_extensions", options.includePlatformExtensions)
        put("raw_capture_status", options.rawCaptureStatus)
        put("write_mode", options.writeMode)
        put("markdown", buildJsonObject {
            put("use_emoji", options.useEmoji)
            put("section_header_level", options.sectionHeaderLevel)
            put("bullet", options.bullet)
            put("include_summary", options.includeSummary)
            put("custom_template", options.customTemplate?.let(::JsonPrimitive) ?: JsonNull)
        })
        put("frontmatter", buildJsonObject {
            put("include_date", options.includeDate)
            put("date_key", options.dateKey)
            put("include_type", options.includeType)
            put("type_key", options.typeKey)
            put("type_value", options.typeValue)
        })
        put("custom_frontmatter", JsonObject(options.customFrontmatter.toSortedMap().mapValues { JsonPrimitive(it.value) }))
        put("placeholder_frontmatter", JsonArray(options.placeholderFrontmatter.sorted().map(::JsonPrimitive)))
        put("disabled_frontmatter_keys", JsonArray(options.disabledFrontmatterKeys.sorted().map(::JsonPrimitive)))
        put("paths", buildJsonObject {
            put("base_directory", options.baseDirectory)
            put("filename_template", options.filenameTemplate)
            put("folder_template", options.folderTemplate)
            put("format_folders", buildJsonObject {
                put("markdown", options.markdownFolder)
                put("obsidian_bases", options.basesFolder)
                put("json", options.jsonFolder)
                put("csv", options.csvFolder)
            })
            put("rollup_directory", options.rollupDirectory)
            put("bases_suffix", options.basesSuffix)
        })
        put("rollups", JsonNull)
        put("api", options.api?.let { api ->
            buildJsonObject {
                put("enabled", true)
                put("envelope_version", api.envelopeVersion)
                put("exported_at", api.exportedAt)
                put("source", api.source)
                put("date_range_start", api.dateRangeStart)
                put("date_range_end", api.dateRangeEnd)
                put("failed_date_details", buildJsonArray {
                    api.failedDateDetails.forEach { failure ->
                        add(buildJsonObject {
                            put("owner_date", failure.ownerDate)
                            put("timestamp", failure.timestamp)
                            put("reason", failure.reason)
                            put("error_details", failure.errorDetails?.let(::JsonPrimitive) ?: JsonNull)
                        })
                    }
                })
                put("external_record_schema", api.externalRecordSchema?.let(::JsonPrimitive) ?: JsonNull)
                put("external_record_schema_version", api.externalRecordSchemaVersion?.let(::JsonPrimitive) ?: JsonNull)
                put("external_records", buildJsonArray {
                    api.externalRecords.forEach { record ->
                        add(buildJsonObject {
                            put("owner_date", record.ownerDate)
                            put("value", record.value)
                        })
                    }
                })
                put("max_days_per_batch", api.maxDaysPerBatch)
                put("max_encoded_bytes", Json.parseToJsonElement(api.maxEncodedBytes.toString()))
            }
        } ?: JsonNull)
    })

    private fun renderDay(
        day: JsonObject,
        registry: CoreMetricRegistrySnapshot,
        presentationData: HealthData?,
        presentationCustomization: FormatCustomization,
        options: Options,
        extensionPayloads: List<JsonObject>,
        individualEntries: List<JsonObject>,
        dailyNote: JsonObject?,
    ): JsonObject {
        val ownerDate = day.getValue("owner_date").jsonPrimitive.content
        val outputs = registry.outputs.associateBy { it.key }
        val metricsBySelection = registry.metrics.associateBy { it.selectionId }
        val selectedOutputKeys = day.getValue("values").jsonArray
            .map { it.jsonObject.getValue("output_key").jsonPrimitive.content }
        val presentationFields = presentationData?.let { data ->
            HealthDataFields.extract(
                data,
                presentationCustomization.unitConverter,
                presentationCustomization.timeFormat,
                presentationCustomization.includeLegacyAndroidAliases,
                presentationCustomization.includeAndroidNativeFields,
            ).associateBy { it.key }
        }.orEmpty()
        val metrics = day.getValue("values").jsonArray.mapIndexed { ordinal, element ->
            val value = element.jsonObject
            val outputKey = value.getValue("output_key").jsonPrimitive.content
            val output = outputs[outputKey] ?: throw AdapterException("registry output is invalid")
            val metric = output.selectionIds.firstNotNullOfOrNull(metricsBySelection::get)
                ?: throw AdapterException("registry output is invalid")
            val semanticValue = value.getValue("value").jsonObject
            val public = publicValue(semanticValue)
            val presentationField = presentationFields[outputKey]
            val unit = presentationField?.unit?.takeIf(String::isNotEmpty) ?: output.unit.ifEmpty {
                semanticValue["unit"]?.jsonObject?.get("id")?.jsonPrimitive?.content ?: "unitless"
            }
            val frontmatterKey = presentationCustomization.frontmatterConfig.outputKey(outputKey) ?: outputKey
            buildJsonObject {
                put("output_key", outputKey)
                put("category_id", categoryIdentifier(metric.categoryId))
                put("category_label", metric.categoryId)
                put("label", metric.referenceName)
                put("frontmatter_key", frontmatterKey)
                put("json_path", buildJsonArray { add(JsonPrimitive(categoryIdentifier(metric.categoryId))); add(JsonPrimitive(outputKey)) })
                put("public_value", public)
                put("display_value", presentationField?.value?.toString() ?: displayValue(public))
                put("unit", unit)
                put("timestamp", JsonNull)
                put("ordinal", ordinal)
            }
        }
        val basesFrontmatterFields = presentationData?.compatibilityProvenance?.let(::provenanceFrontmatterFields).orEmpty()
        return buildJsonObject {
            put("owner_date", ownerDate)
            put("title", ownerDate)
            put("archive_diagnostics", JsonNull)
            put("bases_frontmatter_fields", JsonArray(basesFrontmatterFields))
            put("bases_frontmatter_blocks", buildJsonArray {})
            put("metrics", JsonArray(metrics))
            put("extensions", JsonArray(extensionPayloads))
            put("individual_entries", JsonArray(individualEntries))
            put("daily_note", dailyNote ?: JsonNull)
            put(
                "profile_documents",
                profileDocuments(
                    presentationData,
                    presentationCustomization,
                    options,
                    selectedOutputKeys,
                ),
            )
        }
    }

    private fun profileDocuments(
        data: HealthData?,
        customization: FormatCustomization,
        options: Options,
        semanticOutputKeys: List<String>,
    ): JsonObject {
        if (data == null) {
            return buildJsonObject {
                put("semantic_output_keys", buildJsonArray {})
                put("markdown_body", JsonNull)
                put("csv_rows", JsonNull)
                put("json_root", JsonNull)
            }
        }
        val markdown = if ("markdown" in options.formats) {
            val rendered = MarkdownExporter().export(
                data = data,
                includeMetadata = options.includeMetadata,
                groupByCategory = options.groupByCategory,
                customization = customization,
                includeGranularData = options.includeGranularData,
            )
            val body = if (options.includeMetadata && rendered.startsWith("---\n")) {
                val delimiter = rendered.indexOf("\n---\n\n", startIndex = 4)
                if (delimiter < 0) throw AdapterException("markdown presentation is invalid")
                rendered.substring(delimiter + 6)
            } else {
                rendered
            }
            lineDocument(body)
        } else {
            JsonNull
        }
        val rows = if ("csv" in options.formats) {
            val parsed = parseCsv(CsvExporter().export(data, customization, options.includeGranularData))
            if (parsed.firstOrNull() != listOf("Date", "Category", "Metric", "Value", "Unit", "Timestamp")) {
                throw AdapterException("CSV presentation is invalid")
            }
            buildJsonArray {
                parsed.drop(1).forEach { row ->
                    add(buildJsonObject {
                        put("cells", JsonArray(row.map(::JsonPrimitive)))
                    })
                }
            }
        } else {
            JsonNull
        }
        val jsonRoot = if ("json" in options.formats || options.api != null) {
            val rendered = JsonExporter().export(data, customization, options.includeGranularData)
            orderedJson(json.parseToJsonElement(rendered))
        } else {
            JsonNull
        }
        return buildJsonObject {
            put("semantic_output_keys", JsonArray(semanticOutputKeys.sorted().map(::JsonPrimitive)))
            put("markdown_body", markdown)
            put("csv_rows", rows)
            put("json_root", jsonRoot)
        }
    }

    private fun lineDocument(value: String): JsonObject {
        val trailing = value.endsWith('\n')
        val body = if (trailing) value.dropLast(1) else value
        val lines = if (body.isEmpty()) emptyList() else body.split('\n')
        return buildJsonObject {
            put("lines", JsonArray(lines.map(::JsonPrimitive)))
            put("trailing_newline", trailing)
        }
    }

    private fun parseCsv(value: String): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        val row = mutableListOf<String>()
        val cell = StringBuilder()
        var quoted = false
        var index = 0
        while (index < value.length) {
            val character = value[index]
            when {
                character == '"' && quoted && index + 1 < value.length && value[index + 1] == '"' -> {
                    cell.append('"')
                    index += 1
                }
                character == '"' -> quoted = !quoted
                character == ',' && !quoted -> {
                    row += cell.toString()
                    cell.clear()
                }
                character == '\n' && !quoted -> {
                    row += cell.toString()
                    cell.clear()
                    rows += row.toList()
                    row.clear()
                }
                character != '\r' || quoted -> cell.append(character)
            }
            index += 1
        }
        if (quoted) throw AdapterException("CSV presentation is invalid")
        if (cell.isNotEmpty() || row.isNotEmpty()) {
            row += cell.toString()
            rows += row.toList()
        }
        if (rows.any { it.size != 6 }) throw AdapterException("CSV presentation is invalid")
        return rows
    }

    private fun orderedJson(value: JsonElement): JsonObject = when (value) {
        JsonNull -> buildJsonObject { put("value_type", "null") }
        is JsonArray -> buildJsonObject {
            put("value_type", "array")
            put("items", JsonArray(value.map(::orderedJson)))
        }
        is JsonObject -> buildJsonObject {
            put("value_type", "object")
            put("entries", buildJsonArray {
                value.forEach { (key, child) ->
                    add(buildJsonObject {
                        put("key", key)
                        put("value", orderedJson(child))
                    })
                }
            })
        }
        is JsonPrimitive -> when {
            value.isString -> buildJsonObject {
                put("value_type", "string")
                put("value", value.content)
            }
            value.booleanOrNull != null -> buildJsonObject {
                put("value_type", "boolean")
                put("value", value.booleanOrNull!!)
            }
            else -> buildJsonObject {
                put("value_type", "number")
                put("decimal", value.content)
            }
        }
        else -> throw AdapterException("JSON presentation is invalid")
    }

    private fun provenanceFrontmatterFields(
        provenance: com.healthmd.domain.model.CompatibilityProvenance,
    ): List<JsonObject> {
        fun yamlList(values: List<String>): String = values.joinToString(prefix = "[", postfix = "]") {
            "\"${it.replace("\\", "\\\\").replace("\"", "\\\"")}\""
        }
        val values = listOf(
            "healthmd_all_connected_merge_policy" to provenance.mergePolicyId,
            "healthmd_all_connected_providers_attempted" to yamlList(provenance.providerIdsAttempted),
            "healthmd_all_connected_providers_succeeded" to yamlList(provenance.providerIdsSucceeded),
            "healthmd_all_connected_providers_failed" to yamlList(provenance.providerFailures.map { "${it.providerId}:${it.errorType}" }),
            "healthmd_all_connected_category_selections" to yamlList(provenance.categorySelections.map {
                "${it.category}=${it.chosenProviderId ?: "none"};omitted=${it.omittedOverlappingProviderIds.joinToString("|")}"
            }),
            "healthmd_all_connected_workout_sources" to yamlList(provenance.workoutSources.map {
                "${it.workoutId}=${it.providerId}:${it.providerWorkoutId}"
            }),
            "healthmd_all_connected_workout_detail_sources" to yamlList(provenance.workoutDetailSources.flatMap { workout ->
                workout.sourceIdsByDetail.toSortedMap().map { (detail, ids) ->
                    "${workout.workoutId}:$detail=${ids.joinToString("|")}"
                }
            }),
            "healthmd_all_connected_workout_dedupe_decisions" to yamlList(provenance.workoutDedupeDecisions.map {
                "keep=${it.keptProviderId}:${it.keptWorkoutId};omit=${it.omittedProviderId}:${it.omittedWorkoutId};reason=${it.reason}"
            }),
        )
        return values.mapIndexed { ordinal, (key, value) ->
            buildJsonObject {
                put("key", key)
                put("value", value)
                put("ordinal", ordinal)
            }
        }
    }

    private fun publicValue(value: JsonObject): JsonElement = when (value.getValue("value_type").jsonPrimitive.content) {
        "number" -> {
            val number = value.getValue("number").jsonObject
            when (number.getValue("representation").jsonPrimitive.content) {
                "binary64" -> {
                    val bits = number.getValue("bits").jsonPrimitive.content.toULong(16).toLong()
                    val result = Double.fromBits(bits)
                    if (!result.isFinite()) throw AdapterException("semantic value is invalid")
                    JsonPrimitive(result)
                }
                "signed_integer", "unsigned_integer" -> Json.parseToJsonElement(number.getValue("decimal").jsonPrimitive.content)
                else -> throw AdapterException("semantic value is invalid")
            }
        }
        "text" -> value.getValue("text")
        "boolean" -> value.getValue("boolean")
        "text_list" -> value.getValue("items")
        else -> throw AdapterException("semantic value is invalid")
    }

    private fun displayValue(value: JsonElement): String = when (value) {
        is JsonPrimitive -> value.content
        is JsonArray -> value.joinToString(", ") { it.jsonPrimitive.content }
        else -> value.toString()
    }

    private fun boundedBatches(days: List<JsonObject>, sessionId: String): List<ByteArray> {
        val partitions = mutableListOf<List<JsonObject>>()
        var current = mutableListOf<JsonObject>()
        for (day in days) {
            val facts = day.getValue("metrics").jsonArray.size + day.getValue("extensions").jsonArray.size
            if (facts > MAX_FACTS_PER_BATCH) throw AdapterException("render input exceeds a limit")
            val candidate = current + day
            val candidateFacts = candidate.sumOf { it.getValue("metrics").jsonArray.size + it.getValue("extensions").jsonArray.size }
            if (current.isNotEmpty() && (candidateFacts > MAX_FACTS_PER_BATCH || batch(candidate, sessionId, partitions.size, false).size > MAX_BATCH_BYTES)) {
                partitions += current.toList()
                current = mutableListOf(day)
            } else {
                current = candidate.toMutableList()
            }
            if (batch(current, sessionId, partitions.size, false).size > MAX_BATCH_BYTES) throw AdapterException("render input exceeds a limit")
        }
        if (current.isNotEmpty() || days.isEmpty()) partitions += current.toList()
        var totalBytes = 0
        return partitions.mapIndexed { index, partition ->
            val bytes = batch(partition, sessionId, index, index == partitions.lastIndex)
            totalBytes += bytes.size
            if (totalBytes > MAX_SESSION_BYTES) throw AdapterException("render input exceeds a limit")
            bytes
        }
    }

    private fun batch(days: List<JsonObject>, sessionId: String, index: Int, final: Boolean): ByteArray = encodeJson(buildJsonObject {
        put("schema", "healthmd.render_input")
        put("render_input_version", 1)
        put("session_id", sessionId)
        put("batch_index", index)
        put("final_batch", final)
        put("days", JsonArray(days))
    })

    private fun encodeJson(value: JsonObject): ByteArray = json.encodeToString(JsonObject.serializer(), value).encodeToByteArray()

    private fun requireValue(root: JsonObject, key: String, expected: String) {
        if (root[key]?.jsonPrimitive?.contentOrNull != expected) throw AdapterException("semantic result is invalid")
    }

    private fun categoryIdentifier(value: String): String = when (value) {
        "Body Measurements" -> "body"
        "Reproductive", "Reproductive Health" -> "reproductive_health"
        else -> value.lowercase().replace(Regex("[^a-z0-9]+"), "_").trim('_')
    }
}
