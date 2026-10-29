package com.healthmd.domain.exportengine

import com.healthmd.data.export.JsonExporter
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
        vitals = data.vitals.copy(bloodOxygenSamples = emptyList(), bloodGlucoseSamples = emptyList(), respiratoryRateSamples = emptyList(), bloodPressureSamples = emptyList()),
        activity = data.activity.copy(stepSamples = emptyList(), activityIntensityEntries = emptyList()),
        mindfulness = data.mindfulness.copy(sessions = emptyList()),
    )

    suspend fun compose(request: FrozenDailyAggregateExportRequest, plan: ExportArtifactPlan, semanticResult: ByteArray): ExportArtifactPlan {
        coroutineContext.ensureActive()
        require(plan.profile == request.profile)
        val context = requireNotNull(request.captureContext)
        require(request.profile == AndroidExportProfile.android_sleep_v6 && context.sleepDayAttribution == SleepDayAttribution.MORNING_ENDS)
        val selected = request.data.filtered(request.metricSelection, context)
        val source = HealthData(date = selected.date, sleep = selected.sleep, workouts = selected.workouts,
            // Preserve the adapter's fail-closed admission of raw interval arrays with no selected owner.
            activity = ActivityData(stepSamples = request.data.activity.stepSamples, activityIntensityEntries = request.data.activity.activityIntensityEntries),
            mindfulness = MindfulnessData(sessions = request.data.mindfulness.sessions),
            heart = HeartData(samples = selected.heart.samples, hrvSamples = selected.heart.hrvSamples),
            vitals = VitalsData(bloodPressureSamples = request.data.vitals.bloodPressureSamples, bloodOxygenSamples = selected.vitals.bloodOxygenSamples,
                bloodGlucoseSamples = selected.vitals.bloodGlucoseSamples, respiratoryRateSamples = selected.vitals.respiratoryRateSamples))
        if (!source.heart.hasData && !source.vitals.hasData && !source.activity.hasData && !source.mindfulness.hasData &&
            source.sleep.stages.isEmpty() && source.sleep.sessions.isEmpty() && source.workouts.isEmpty()) return plan
        val root = Json.parseToJsonElement(JsonExporter().export(source, request.customization, request.includeGranularData, context)).jsonObject
        val keys = Json.parseToJsonElement(semanticResult.decodeToString()).jsonObject.getValue("selected_output_keys").jsonArray
            .map { it.jsonPrimitive.content }
        require(keys.distinct().size == keys.size)
        // Reuse native unit, clock, numeric and frozen-output-owner validation.
        val enabledKeys = keys.filter { request.customization.frontmatterConfig.outputKey(it) != null }
        val sleep = root["sleep"]?.jsonObject
        val details = listOf(
            HealthMdRenderInputAdapter.quantityDetails(root, source.date.toString(), enabledKeys),
            HealthMdRenderInputAdapter.sleepDetails(sleep?.get("sleepStages")?.jsonArray ?: JsonArray(emptyList()),
                sleep?.get("sleepSessions")?.jsonArray ?: JsonArray(emptyList()), source.date.toString(), enabledKeys),
            HealthMdRenderInputAdapter.workoutDetails(root, source.date.toString(), enabledKeys),
            HealthMdRenderInputAdapter.bloodPressureDetails(root, source.date.toString(), enabledKeys),
            HealthMdRenderInputAdapter.activityDetails(root, source.date.toString(), enabledKeys),
            HealthMdRenderInputAdapter.mindfulnessDetails(root, source.date.toString(), enabledKeys),
        ).reduce(HealthMdRenderInputAdapter::mergeDetails)
        val sourceArrays = listOf("heart" to "heartRateSamples", "heart" to "hrvSamples", "vitals" to "bloodOxygenSamples",
            "vitals" to "bloodGlucoseSamples", "vitals" to "respiratoryRateSamples",
            "sleep" to "sleepStages", "sleep" to "sleepSessions", "vitals" to "bloodPressureSamples",
            "activity" to "stepSamples", "activity" to "activityIntensity", "mindfulness" to "sessions")
        val formats = request.formats.associateBy(request::relativePath)
        val items = plan.items.map { item ->
            coroutineContext.ensureActive()
            val format = requireNotNull(formats[item.relativePath])
            val aggregate = item.content.decodeToString()
            val text = when (format) {
                ExportFormat.JSON -> {
                    val result = Json.parseToJsonElement(aggregate).jsonObject.toMutableMap()
                    for ((category, field) in sourceArrays) {
                        val samples = root[category]?.jsonObject?.get(field) ?: continue
                        val values = result[category]?.jsonObject?.toMutableMap() ?: mutableMapOf()
                        require(field !in values)
                        values[field] = samples
                        result[category] = JsonObject(values)
                    }
                    root["workouts"]?.let { workouts ->
                        require("workouts" !in result)
                        result["workouts"] = workouts
                    }
                    json.encodeToString(JsonElement.serializer(), JsonObject(result))
                }
                ExportFormat.CSV -> buildString {
                    append(aggregate)
                    if (!aggregate.endsWith('\n')) append('\n')
                    for (row in details.getValue("csv_rows").jsonArray) {
                        append(listOf("date", "category", "metric", "value", "unit", "timestamp")
                            .joinToString(",") { csv(row.jsonObject.getValue(it).jsonPrimitive.content) })
                        append('\n')
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
                                "native_correlation_details", "native_activity_details", "native_mindfulness_details"))
                            require(!aggregate.substring(0, end).contains("\n$key:"))
                            append("\n").append(key).append(":\n")
                            for (line in value.getValue("lines").jsonArray) append(line.jsonPrimitive.content).append('\n')
                        }
                        append(aggregate.substring(end))
                    }
                }
            }
            val bytes = text.encodeToByteArray()
            val hash = sha256Hex(bytes)
            item.copy(artifactId = artifactIdHex(plan.requestId, plan.sessionId, plan.profile, item.relativePath,
                item.mediaType, item.writeMode, hash), content = bytes, sha256 = hash)
        }
        return ExportArtifactPlan(plan.schema, plan.artifactPlanVersion, plan.requestId, plan.sessionId, plan.profile, items)
    }

    private fun csv(value: String): String = if (value.any { it == ',' || it == '"' || it == '\n' || it == '\r' }) {
        "\"${value.replace("\"", "\"\"")}\""
    } else value
}
