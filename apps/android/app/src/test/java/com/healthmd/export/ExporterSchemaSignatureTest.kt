package com.healthmd.export

import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.HealthMdExportSchema
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.model.ActivityData
import com.healthmd.domain.model.ActivityIntensityEntry
import com.healthmd.domain.model.BloodPressureSample
import com.healthmd.domain.model.BodyData
import com.healthmd.domain.model.CategoryMergeProvenance
import com.healthmd.domain.model.CompatibilityProvenance
import com.healthmd.domain.model.CompatibilitySchemaProfile
import com.healthmd.domain.model.ExactSourceIdentity
import com.healthmd.domain.model.ExactSourceTimestamp
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.HealthDataFields
import com.healthmd.domain.model.HeartData
import com.healthmd.domain.model.MedicalResourceData
import com.healthmd.domain.model.MedicalResourcesData
import com.healthmd.domain.model.MenstruationPeriodEntry
import com.healthmd.domain.model.MindfulnessData
import com.healthmd.domain.model.MindfulnessSessionEntry
import com.healthmd.domain.model.MobilityData
import com.healthmd.domain.model.NutritionData
import com.healthmd.domain.model.NutritionMealEntry
import com.healthmd.domain.model.PlannedExerciseData
import com.healthmd.domain.model.ProviderFailureProvenance
import com.healthmd.domain.model.ReproductiveHealthData
import com.healthmd.domain.model.SleepData
import com.healthmd.domain.model.SleepSessionEntry
import com.healthmd.domain.model.SleepStageEntry
import com.healthmd.domain.model.TimestampedSample
import com.healthmd.domain.model.UnitPreference
import com.healthmd.domain.model.VitalsData
import com.healthmd.domain.model.WorkoutData
import com.healthmd.domain.model.WorkoutDedupeDecisionProvenance
import com.healthmd.domain.model.WorkoutDetailSourceProvenance
import com.healthmd.domain.model.WorkoutLapData
import com.healthmd.domain.model.WorkoutRouteAccess
import com.healthmd.domain.model.WorkoutRoutePointData
import com.healthmd.domain.model.WorkoutSegmentData
import com.healthmd.domain.model.WorkoutSourceProvenance
import com.healthmd.domain.model.WorkoutSplitData
import com.healthmd.domain.model.WorkoutType
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonArray
import kotlinx.serialization.json.JsonElement
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.add
import kotlinx.serialization.json.addJsonObject
import kotlinx.serialization.json.booleanOrNull
import kotlinx.serialization.json.buildJsonArray
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import kotlinx.serialization.json.put
import kotlinx.serialization.json.putJsonArray
import kotlinx.serialization.json.putJsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.fail
import org.junit.Test
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.time.LocalDateTime
import java.time.ZoneOffset
import java.util.Locale
import kotlin.time.Duration.Companion.hours
import kotlin.time.Duration.Companion.minutes

/**
 * Guards the immutable, shipped Android compatibility-export profiles.
 *
 * These are structural signatures, not golden user-data files. They intentionally fingerprint
 * JSON paths/types, CSV labels/units/header/value types, Markdown labels/headings/tables,
 * Markdown/Bases frontmatter keys/types, and the flat-field units used by frontmatter exporters.
 * A fixture is generated only from the reviewed synthetic day below and is never rewritten by a
 * normal test run.
 */
class ExporterSchemaSignatureTest {

    @Test
    fun shippedProfileSignaturesMatchImmutableFixtures() {
        assertEquals(
            "Frozen Android compatibility exports must remain schema v4; introduce a new profile/version instead of changing v4",
            4,
            HealthMdExportSchema.VERSION,
        )

        val previousLocale = Locale.getDefault()
        Locale.setDefault(Locale.US)
        try {
            val generated = mutableListOf<File>()
            for (profile in profiles) {
                val current = snapshot(profile)
                val existing = readFixture(profile)
                if (existing == null) {
                    if (updateRequested) {
                        generated += writeCandidate(profile, current)
                        continue
                    }
                    fail(
                        "Missing immutable exporter signature fixture ${profile.resourcePath}. " +
                            "After adding an explicit new profile/version, run the documented " +
                            "UPDATE_ANDROID_EXPORTER_SIGNATURES workflow and review the candidate fixture.",
                    )
                }

                assertNotNull(existing)
                if (existing != current) {
                    val policy = if (updateRequested) {
                        "Refusing to regenerate the existing shipped fixture. Add a new explicit profile/version and fixture."
                    } else {
                        "Exporter contract drifted without a new explicit profile/version. Do not rewrite the shipped fixture."
                    }
                    assertEquals(
                        "$policy\nProfile: ${profile.id} v${profile.version}\nFixture: ${profile.resourcePath}",
                        existing,
                        current,
                    )
                }
            }

            if (generated.isNotEmpty()) {
                fail(
                    "Generated candidate exporter signature fixture(s):\n" +
                        generated.joinToString("\n") { it.absolutePath } +
                        "\nReview and copy each candidate into app/src/test/resources/export-contract/signatures/. " +
                        "The generation run fails intentionally until the new fixture is committed.",
                )
            }
        } finally {
            Locale.setDefault(previousLocale)
        }
    }

    private fun snapshot(profile: Profile): JsonObject {
        val payload = payload(profile.customization)
        val fingerprint = MessageDigest.getInstance("SHA-256")
            .digest(payload.toString().toByteArray(Charsets.UTF_8))
            .joinToString("") { "%02x".format(Locale.US, it.toInt() and 0xff) }

        return buildJsonObject {
            put("profile", profile.id)
            put("profileEnum", profile.profile.name)
            put("profileVersion", profile.version)
            put("shipped", true)
            put("fingerprint", fingerprint)
            put("payload", payload)
        }
    }

    private fun payload(metricCustomization: FormatCustomization): JsonObject {
        val imperialCustomization = metricCustomization.copy(unitPreference = UnitPreference.IMPERIAL)
        val data = ExportSignatureFixtures.syntheticDay
        val jsonExporter = JsonExporter()
        val csvExporter = CsvExporter()
        val markdownExporter = MarkdownExporter()
        val basesExporter = ObsidianBasesExporter()

        fun json(customization: FormatCustomization, granular: Boolean): JsonObject =
            Json.parseToJsonElement(
                jsonExporter.export(data, customization, includeGranularData = granular),
            ).jsonObject

        fun csv(customization: FormatCustomization, granular: Boolean): String =
            csvExporter.export(data, customization, includeGranularData = granular)

        fun markdown(customization: FormatCustomization, granular: Boolean): String =
            markdownExporter.export(
                data = data,
                includeMetadata = true,
                groupByCategory = true,
                customization = customization,
                includeGranularData = granular,
            )

        val metricJson = json(metricCustomization, granular = false)
        val metricGranularJson = json(metricCustomization, granular = true)
        val imperialJson = json(imperialCustomization, granular = false)
        val metricCsv = csv(metricCustomization, granular = false)
        val metricGranularCsv = csv(metricCustomization, granular = true)
        val imperialCsv = csv(imperialCustomization, granular = false)
        val imperialGranularCsv = csv(imperialCustomization, granular = true)
        val metricMarkdown = markdown(metricCustomization, granular = false)
        val metricGranularMarkdown = markdown(metricCustomization, granular = true)
        val imperialMarkdown = markdown(imperialCustomization, granular = false)

        return buildJsonObject {
            putJsonObject("json") {
                put("metricDiscriminators", jsonDiscriminators(metricJson))
                put("imperialDiscriminators", jsonDiscriminators(imperialJson))
                put("summaryShapePaths", stringArray(jsonShapePaths(metricJson)))
                put("granularShapePaths", stringArray(jsonShapePaths(metricGranularJson)))
            }
            putJsonObject("csv") {
                put("metricHeader", stringArray(csvHeader(metricCsv)))
                put("imperialHeader", stringArray(csvHeader(imperialCsv)))
                put("metricSummaryRows", csvRowContracts(metricCsv))
                put("metricGranularRows", csvRowContracts(metricGranularCsv))
                put("imperialSummaryRows", csvRowContracts(imperialCsv))
                put("imperialGranularRows", csvRowContracts(imperialGranularCsv))
            }
            putJsonObject("markdown") {
                put("metricFrontmatter", frontmatterContracts(metricMarkdown))
                put("imperialFrontmatter", frontmatterContracts(imperialMarkdown))
                put("headings", stringArray(markdownHeadings(metricMarkdown)))
                put("metricLabels", stringArray(markdownLabels(metricMarkdown)))
                put("imperialLabels", stringArray(markdownLabels(imperialMarkdown)))
                put("metricLines", stringArray(markdownMetricLines(metricMarkdown)))
                put("imperialMetricLines", stringArray(markdownMetricLines(imperialMarkdown)))
                put("granularTableHeaders", stringArray(markdownTableHeaders(metricGranularMarkdown)))
                put("blockquoteLabels", stringArray(markdownBlockquoteLabels(metricMarkdown)))
            }
            putJsonObject("obsidianBases") {
                put(
                    "metricFrontmatter",
                    frontmatterContracts(basesExporter.export(data, metricCustomization)),
                )
                put(
                    "imperialFrontmatter",
                    frontmatterContracts(basesExporter.export(data, imperialCustomization)),
                )
            }
            putJsonObject("flatFields") {
                put("metric", flatFieldContracts(data, metricCustomization))
                put("imperial", flatFieldContracts(data, imperialCustomization))
            }
        }
    }

    private fun jsonDiscriminators(root: JsonObject): JsonObject = buildJsonObject {
        for (key in listOf("type", "units", "schemaProfile", "schemaVersion")) {
            root[key]?.let { put(key, it) }
        }
    }

    private fun jsonShapePaths(root: JsonObject): List<String> =
        jsonShapePaths(root, "$", includeSelf = false).distinct().sorted()

    private fun jsonShapePaths(
        value: JsonElement,
        path: String,
        includeSelf: Boolean = true,
    ): List<String> {
        val paths = mutableListOf<String>()
        when (value) {
            JsonNull -> if (includeSelf) paths += "$path:null"
            is JsonObject -> {
                if (includeSelf) paths += "$path:object"
                if (isDynamicMap(path)) {
                    for (child in value.values) {
                        paths += jsonShapePaths(child, "$path.*")
                    }
                } else {
                    for ((key, child) in value.toSortedMap()) {
                        paths += jsonShapePaths(child, "$path.$key")
                    }
                }
            }
            is JsonArray -> {
                if (includeSelf) paths += "$path:array"
                if (value.isEmpty()) {
                    paths += "$path[]:empty"
                } else {
                    for (child in value) paths += jsonShapePaths(child, "$path[]")
                }
            }
            is JsonPrimitive -> paths += "$path:${jsonPrimitiveType(value)}"
        }
        return paths.distinct()
    }

    private fun isDynamicMap(path: String): Boolean {
        if (path == "$.metadata") return false
        return path.substringAfterLast('.') in setOf(
            "context",
            "metadata",
            "countsByType",
            "sourceIdsByDetail",
            "correlatedSourceIds",
        )
    }

    private fun jsonPrimitiveType(value: JsonPrimitive): String = when {
        value.isString -> "string"
        value.booleanOrNull != null -> "boolean"
        else -> "number"
    }

    private fun csvHeader(csv: String): List<String> = parseCsv(csv).firstOrNull().orEmpty()

    private fun csvRowContracts(csv: String): JsonArray {
        val contracts = parseCsv(csv).drop(1).map { columns ->
            val value = columns.getOrElse(3) { "" }
            val timestamp = columns.getOrElse(5) { "" }
            buildJsonObject {
                put("category", columns.getOrElse(1) { "" })
                put("metric", columns.getOrElse(2) { "" })
                put("unit", columns.getOrElse(4) { "" })
                put("valueType", scalarType(value))
                put("timestampType", timestampType(timestamp))
                if (columns.getOrElse(1) { "" } == "Metadata") put("metadataValue", value)
            }
        }.distinctBy(JsonObject::toString).sortedBy(JsonObject::toString)
        return buildJsonArray { contracts.forEach { add(it) } }
    }

    /** Minimal RFC 4180 parser sufficient for deterministic exporter rows, including quoted commas. */
    private fun parseCsv(csv: String): List<List<String>> {
        val rows = mutableListOf<List<String>>()
        var row = mutableListOf<String>()
        val cell = StringBuilder()
        var quoted = false
        var index = 0
        while (index < csv.length) {
            val character = csv[index]
            when {
                character == '"' && quoted && index + 1 < csv.length && csv[index + 1] == '"' -> {
                    cell.append('"')
                    index++
                }
                character == '"' -> quoted = !quoted
                character == ',' && !quoted -> {
                    row += cell.toString()
                    cell.setLength(0)
                }
                character == '\n' && !quoted -> {
                    row += cell.toString().trimEnd('\r')
                    cell.setLength(0)
                    if (row.any(String::isNotEmpty)) rows += row
                    row = mutableListOf()
                }
                else -> cell.append(character)
            }
            index++
        }
        if (cell.isNotEmpty() || row.isNotEmpty()) {
            row += cell.toString()
            if (row.any(String::isNotEmpty)) rows += row
        }
        return rows
    }

    private fun frontmatterContracts(output: String): JsonArray {
        val lines = output.lines()
        if (lines.firstOrNull() != "---") return JsonArray(emptyList())
        val contracts = mutableListOf<JsonObject>()
        for (line in lines.drop(1)) {
            if (line == "---") break
            if (line.startsWith(" ")) continue
            val separator = line.indexOf(':')
            if (separator < 0) continue
            val key = line.substring(0, separator)
            val value = line.substring(separator + 1).trim()
            contracts += buildJsonObject {
                put("key", key)
                put("valueType", scalarType(value))
            }
        }
        return buildJsonArray {
            contracts.distinctBy(JsonObject::toString)
                .sortedBy { it["key"]!!.jsonPrimitive.content }
                .forEach { add(it) }
        }
    }

    private fun flatFieldContracts(
        data: HealthData,
        customization: FormatCustomization,
    ): JsonArray {
        val fields = HealthDataFields.extract(
            data = data,
            converter = customization.unitConverter,
            timeFormat = customization.timeFormat,
            includeLegacyAndroidAliases = customization.includeLegacyAndroidAliases,
            includeAndroidNativeFields = customization.includeAndroidNativeFields,
        ).filter { it.value != null }
            .map { field ->
                buildJsonObject {
                    put("key", field.key)
                    put("valueType", kotlinValueType(field.value!!))
                    put("unit", field.unit)
                }
            }
            .sortedBy { it["key"]!!.jsonPrimitive.content }
        return buildJsonArray { fields.forEach { add(it) } }
    }

    private fun markdownHeadings(markdown: String): List<String> = markdown.lines()
        .filter { it.matches(Regex("^#{1,6} .+")) }
        .map { line -> line.replace(ExportFixtures.referenceDate.toString(), "<date>") }
        .distinct()
        .sorted()

    private fun markdownLabels(markdown: String): List<String> {
        val label = Regex("\\*\\*(.+?):\\*\\*")
        return markdown.lines().mapNotNull { line -> label.find(line)?.groupValues?.get(1) }
            .distinct()
            .sorted()
    }

    /** Full deterministic metric lines preserve Markdown labels, formatting, and rendered units. */
    private fun markdownMetricLines(markdown: String): List<String> = markdown.lines()
        .filter { it.contains("**") }
        .map(String::trim)
        .distinct()
        .sorted()

    private fun markdownTableHeaders(markdown: String): List<String> {
        val lines = markdown.lines()
        return lines.indices.mapNotNull { index ->
            val line = lines[index].trim()
            val separator = lines.getOrNull(index + 1)?.trim().orEmpty()
            if (!line.startsWith("|") || !separator.startsWith("|")) return@mapNotNull null
            val separatorCells = separator.trim('|').split('|').map(String::trim)
            if (separatorCells.isEmpty() || separatorCells.any { !it.matches(Regex(":?-+:?")) }) {
                return@mapNotNull null
            }
            line.trim('|').split('|').joinToString("|") { it.trim() }
        }.distinct().sorted()
    }

    private fun markdownBlockquoteLabels(markdown: String): List<String> = markdown.lines()
        .filter { it.startsWith("> ") }
        .map { it.removePrefix("> ").substringBefore(':').substringBefore('=').trim() }
        .distinct()
        .sorted()

    private fun scalarType(value: String): String = when {
        value.isEmpty() -> "empty"
        value.matches(Regex("\\d{4}-\\d{2}-\\d{2}")) -> "date"
        value.matches(Regex("\\d{2}:\\d{2}(:\\d{2})?")) -> "time"
        value == "true" || value == "false" -> "boolean"
        value.toLongOrNull() != null -> "integer"
        value.toDoubleOrNull() != null -> "number"
        value.startsWith("[") && value.endsWith("]") -> "list"
        else -> "string"
    }

    private fun kotlinValueType(value: Any): String = when (value) {
        is Byte, is Short, is Int, is Long -> "integer"
        is Float, is Double -> "number"
        is Boolean -> "boolean"
        is String -> scalarType(value)
        else -> "string"
    }

    private fun timestampType(value: String): String = when {
        value.isEmpty() -> "empty"
        value.matches(Regex(".*T.*(Z|[+-]\\d{2}:\\d{2})$")) -> "offset-date-time"
        value.contains('T') -> "local-date-time"
        else -> scalarType(value)
    }

    private fun stringArray(values: List<String>): JsonArray = buildJsonArray {
        values.forEach { add(it) }
    }

    private fun readFixture(profile: Profile): JsonObject? {
        val stream = javaClass.classLoader?.getResourceAsStream(profile.resourcePath) ?: return null
        return stream.bufferedReader(Charsets.UTF_8).use { reader ->
            Json.parseToJsonElement(reader.readText()).jsonObject
        }
    }

    private fun writeCandidate(profile: Profile, snapshot: JsonObject): File {
        val directory = File(System.getProperty("java.io.tmpdir"), "healthmd-android-exporter-signatures")
        directory.mkdirs()
        val output = File(directory, profile.fileName)
        val pretty = Json { prettyPrint = true }
        output.writeText(
            pretty.encodeToString(JsonElement.serializer(), snapshot) + "\n",
            Charsets.UTF_8,
        )
        return output
    }

    private data class Profile(
        val id: String,
        val version: Int,
        val profile: CompatibilitySchemaProfile,
        val customization: FormatCustomization,
    ) {
        val fileName: String = "exporter_signature_${id.replace('-', '_')}.json"
        val resourcePath: String = "export-contract/signatures/$fileName"
    }

    private companion object {
        val updateRequested: Boolean =
            System.getenv("UPDATE_ANDROID_EXPORTER_SIGNATURES") == "1"

        val profiles: List<Profile> = listOf(
            Profile(
                id = "ios-v4-frozen",
                version = 4,
                profile = CompatibilitySchemaProfile.IOS_V4_FROZEN,
                customization = FormatCustomization(
                    compatibilitySchemaProfile = CompatibilitySchemaProfile.IOS_V4_FROZEN,
                ),
            ),
            Profile(
                id = "android-analytical-v5",
                version = 5,
                profile = CompatibilitySchemaProfile.ANDROID_ANALYTICAL_V5,
                customization = FormatCustomization.analyticalDefault(),
            ),
        )
    }
}

/** A fully populated, deterministic extension of the existing canonical Android fixture. */
internal object ExportSignatureFixtures {
    private val t: LocalDateTime = ExportFixtures.referenceDateTime.plusHours(6)
    private val exactStart = ExactSourceTimestamp.from(
        Instant.parse("2026-03-15T10:00:00.123456789Z"),
        ZoneOffset.ofHours(-4),
    )
    private val exactEnd = ExactSourceTimestamp.from(
        Instant.parse("2026-03-15T11:00:00.987654321Z"),
        ZoneOffset.ofHours(-4),
    )
    private val exactWithoutOffset = ExactSourceTimestamp.from(
        Instant.parse("2026-03-15T12:00:00.000000007Z"),
    )
    private val identity = ExactSourceIdentity(
        nativeId = "synthetic-native-id",
        clientRecordId = "synthetic-client-id",
        clientRecordVersion = 0,
        origin = "com.healthmd.synthetic",
        lastModified = exactWithoutOffset,
        syntheticId = "synthetic-derived-id",
        isSynthetic = true,
    )

    private fun sample(time: LocalDateTime = t, value: Double = 42.25): TimestampedSample =
        TimestampedSample(
            time = time,
            value = value,
            source = "Synthetic Source",
            metadata = mapOf("synthetic-metadata" to "value"),
            context = mapOf("synthetic-context" to "value"),
            exactTime = exactStart,
            exactEndTime = exactEnd,
            identity = identity,
        )

    val syntheticDay: HealthData = ExportFixtures.fullDayGranular.copy(
        sleep = SleepData(
            totalDuration = 8.hours,
            deepSleep = 2.hours,
            remSleep = 2.hours,
            lightSleep = 3.hours + 30.minutes,
            awakeTime = 30.minutes,
            inBedTime = 8.hours + 30.minutes,
            stages = listOf(
                SleepStageEntry(
                    startTime = t.minusHours(8),
                    endTime = t.minusHours(6),
                    stage = "deep",
                    exactStartTime = exactStart,
                    exactEndTime = exactEnd,
                    identity = identity,
                ),
            ),
            sessions = listOf(
                SleepSessionEntry(
                    startTime = t.minusHours(8),
                    endTime = t,
                    title = "Synthetic Sleep",
                    notes = "Synthetic notes",
                    source = "Synthetic Source",
                    metadata = mapOf("synthetic-metadata" to "value"),
                    exactStartTime = exactStart,
                    exactEndTime = exactEnd,
                    identity = identity,
                ),
            ),
            sessionStart = t.minusHours(8),
            sessionEnd = t,
        ),
        activity = ActivityData(
            steps = 12_345,
            activeCalories = 500.5,
            totalCalories = 2_100.5,
            exerciseMinutes = 45.5,
            flightsClimbed = 8,
            walkingRunningDistance = 9_500.5,
            basalEnergyBurned = 1_600.5,
            cyclingDistance = 3_200.5,
            elevationGained = 123.4,
            wheelchairPushes = 12,
            swimmingDistance = 1_000.5,
            swimmingStrokes = 400,
            wheelchairDistance = 2_000.5,
            downhillSnowSportsDistance = 5_000.5,
            moderateActivityMinutes = 30.5,
            vigorousActivityMinutes = 15.5,
            activityIntensityMinutes = 46,
            stepSamples = listOf(sample(value = 1_234.0)),
            activityIntensityEntries = listOf(
                ActivityIntensityEntry(
                    startTime = t,
                    endTime = t.plusMinutes(30),
                    duration = 30.minutes,
                    intensity = "moderate",
                    source = "Synthetic Source",
                    metadata = mapOf("synthetic-metadata" to "value"),
                    exactStartTime = exactStart,
                    exactEndTime = exactEnd,
                    identity = identity,
                ),
            ),
        ),
        heart = HeartData(
            restingHeartRate = 58.5,
            averageHeartRate = 72.5,
            walkingHeartRateAverage = 80.5,
            hrv = 42.5,
            heartRateMin = 50.5,
            heartRateMax = 160.5,
            samples = listOf(sample(value = 72.0)),
            hrvSamples = listOf(sample(t.plusMinutes(1), 42.5)),
        ),
        vitals = VitalsData(
            respiratoryRateAvg = 15.5,
            respiratoryRateMin = 12.5,
            respiratoryRateMax = 18.5,
            bloodOxygenAvg = 0.975,
            bloodOxygenMin = 0.94,
            bloodOxygenMax = 0.99,
            bodyTemperatureAvg = 36.8,
            bodyTemperatureMin = 36.5,
            bodyTemperatureMax = 37.1,
            bloodPressureSystolicAvg = 120.5,
            bloodPressureSystolicMin = 110.5,
            bloodPressureSystolicMax = 130.5,
            bloodPressureDiastolicAvg = 80.5,
            bloodPressureDiastolicMin = 70.5,
            bloodPressureDiastolicMax = 90.5,
            bloodGlucoseAvg = 95.5,
            bloodGlucoseMin = 80.5,
            bloodGlucoseMax = 120.5,
            basalBodyTemperature = 36.6,
            skinTemperatureDelta = 0.45,
            skinTemperatureBaseline = 33.1,
            bloodOxygenSamples = listOf(sample(value = 0.975)),
            bloodPressureSamples = listOf(
                BloodPressureSample(
                    time = t,
                    systolic = 120.5,
                    diastolic = 80.5,
                    measurementLocation = "left_upper_arm",
                    bodyPosition = "sitting",
                    source = "Synthetic Source",
                    metadata = mapOf("synthetic-metadata" to "value"),
                    exactTime = exactStart,
                    identity = identity,
                ),
            ),
            bloodGlucoseSamples = listOf(sample(value = 95.5)),
            respiratoryRateSamples = listOf(sample(value = 15.5)),
            bodyTemperatureSamples = listOf(sample(value = 36.8)),
            basalBodyTemperatureSamples = listOf(sample(value = 36.6)),
            skinTemperatureDeltas = listOf(sample(value = 0.45)),
        ),
        body = BodyData(
            weight = 75.5,
            bodyFatPercentage = 0.185,
            height = 1.78,
            bmi = 23.8,
            leanBodyMass = 60.5,
            bodyWaterMass = 45.5,
            boneMass = 3.2,
        ),
        nutrition = NutritionData(
            dietaryEnergy = 2_100.5,
            protein = 120.5,
            carbohydrates = 250.5,
            fat = 70.5,
            fiber = 25.5,
            sugar = 45.5,
            sodium = 2_000.5,
            water = 2.5,
            caffeine = 200.5,
            cholesterol = 250.5,
            saturatedFat = 20.5,
            monounsaturatedFat = 25.5,
            polyunsaturatedFat = 15.5,
            unsaturatedFat = 40.5,
            transFat = 1.5,
            potassium = 3_500.5,
            calcium = 1_000.5,
            iron = 18.5,
            magnesium = 400.5,
            zinc = 11.5,
            phosphorus = 700.5,
            iodine = 150.5,
            selenium = 55.5,
            copper = 0.9,
            manganese = 2.3,
            chromium = 35.5,
            molybdenum = 45.5,
            chloride = 2_300.5,
            vitaminA = 900.5,
            vitaminB6 = 1.7,
            vitaminB12 = 2.4,
            vitaminC = 90.5,
            vitaminD = 20.5,
            vitaminE = 15.5,
            vitaminK = 120.5,
            thiamin = 1.2,
            riboflavin = 1.3,
            niacin = 16.5,
            folate = 400.5,
            folicAcid = 200.5,
            pantothenicAcid = 5.5,
            biotin = 30.5,
            energyFromFat = 600.5,
            meals = listOf(
                NutritionMealEntry(
                    startTime = t,
                    endTime = t.plusMinutes(30),
                    name = "Synthetic Meal",
                    mealType = "breakfast",
                    dietaryEnergy = 500.5,
                    energyFromFat = 100.5,
                    protein = 25.5,
                    carbohydrates = 50.5,
                    fat = 20.5,
                    source = "Synthetic Source",
                    metadata = mapOf("synthetic-metadata" to "value"),
                    exactStartTime = exactStart,
                    exactEndTime = exactEnd,
                    identity = identity,
                ),
            ),
        ),
        mobility = MobilityData(
            walkingSpeed = 1.4,
            vo2Max = 42.5,
            cyclingCadenceAvg = 88.5,
            cyclingCadenceMax = 120.5,
            stepsCadenceAvg = 170.5,
            stepsCadenceMax = 190.5,
            powerAvg = 210.5,
            powerMax = 650.5,
            runningSpeed = 3.5,
            runningPowerAvg = 275.5,
            runningPowerMax = 450.5,
            vo2MaxMeasurementMethod = "metabolic_cart",
        ),
        reproductiveHealth = ReproductiveHealthData(
            menstrualFlow = "medium",
            cervicalMucusAppearance = "egg_white",
            cervicalMucusSensation = "wet",
            ovulationTestResult = "positive",
            intermenstrualBleeding = true,
            sexualActivityRecorded = true,
            sexualActivityProtectionUsed = "protected",
            menstruationPeriodCount = 1,
            menstruationPeriodDuration = 48.hours,
            menstruationPeriods = listOf(
                MenstruationPeriodEntry(
                    startTime = t,
                    endTime = t.plusHours(48),
                    duration = 48.hours,
                    source = "Synthetic Source",
                    metadata = mapOf("synthetic-metadata" to "value"),
                    exactStartTime = exactStart,
                    exactEndTime = exactEnd,
                    identity = identity,
                ),
            ),
        ),
        mindfulness = MindfulnessData(
            mindfulnessMinutes = 15.5,
            mindfulSessions = 1,
            sessions = listOf(
                MindfulnessSessionEntry(
                    startTime = t,
                    endTime = t.plusMinutes(15),
                    sessionType = "meditation",
                    title = "Synthetic Mindfulness",
                    notes = "Synthetic notes",
                    source = "Synthetic Source",
                    metadata = mapOf("synthetic-metadata" to "value"),
                    exactStartTime = exactStart,
                    exactEndTime = exactEnd,
                    identity = identity,
                ),
            ),
        ),
        workouts = listOf(
            fullWorkout(WorkoutType.RUNNING, t),
            fullWorkout(WorkoutType.CYCLING, t.plusHours(2)),
        ),
        plannedWorkouts = listOf(
            PlannedExerciseData(
                workoutType = WorkoutType.RUNNING,
                startTime = t.plusHours(4),
                endTime = t.plusHours(5),
                duration = 1.hours,
                hasExplicitTime = true,
                exerciseTypeRaw = 56,
                completedExerciseSessionId = "completed-session-id",
                title = "Synthetic Plan",
                notes = "Synthetic notes",
                blockCount = 2,
                stepCount = 4,
                blockDescriptions = listOf("Warm up", "Run"),
                metadata = mapOf("synthetic-metadata" to "value"),
                exactStartTime = exactStart,
                exactEndTime = exactEnd,
                identity = identity,
            ),
        ),
        medicalResources = MedicalResourcesData(
            resources = listOf(
                MedicalResourceData(
                    type = "allergy",
                    typeRaw = 1,
                    dataSourceId = "synthetic-data-source",
                    medicalResourceId = "synthetic-medical-resource",
                    fhirVersion = "4.0.1",
                    fhirResourceType = "AllergyIntolerance",
                    fhirResourceTypeRaw = 2,
                    fhirResourceId = "synthetic-fhir-resource",
                    fhirResourceJson = "{\"resourceType\":\"AllergyIntolerance\"}",
                ),
            ),
            countsByType = mapOf("allergy" to 1),
        ),
        compatibilityProvenance = CompatibilityProvenance(
            providerIdsAttempted = listOf("health-connect", "synthetic-cloud"),
            providerIdsSucceeded = listOf("health-connect"),
            providerFailures = listOf(
                ProviderFailureProvenance(
                    providerId = "synthetic-cloud",
                    operation = "read",
                    errorType = "synthetic_failure",
                    message = "Synthetic failure",
                ),
            ),
            categorySelections = listOf(
                CategoryMergeProvenance(
                    category = "activity",
                    chosenProviderId = "health-connect",
                    omittedOverlappingProviderIds = listOf("synthetic-cloud"),
                ),
            ),
            workoutDetailSources = listOf(
                WorkoutDetailSourceProvenance(
                    workoutId = "synthetic-running-workout",
                    sourceIdsByDetail = mapOf("route" to listOf("health-connect:route")),
                ),
            ),
            workoutSources = listOf(
                WorkoutSourceProvenance(
                    workoutId = "synthetic-running-workout",
                    providerId = "health-connect",
                    providerWorkoutId = "native-workout-id",
                ),
            ),
            workoutDedupeDecisions = listOf(
                WorkoutDedupeDecisionProvenance(
                    keptProviderId = "health-connect",
                    keptWorkoutId = "native-workout-id",
                    omittedProviderId = "synthetic-cloud",
                    omittedWorkoutId = "cloud-workout-id",
                    reason = "cross_provider_semantic_fingerprint",
                ),
            ),
            mergePolicyId = "source-preferred-v1",
        ),
    )

    private fun fullWorkout(type: WorkoutType, start: LocalDateTime): WorkoutData = WorkoutData(
        workoutType = type,
        startTime = start,
        endTime = start.plusHours(1),
        isIndoor = false,
        metadata = mapOf(
            "title" to "Synthetic ${type.name}",
            "notes" to "Synthetic notes",
            "synthetic-metadata" to "value",
        ),
        duration = 1.hours,
        id = "synthetic-${type.name.lowercase()}-workout",
        calories = 500.5,
        distance = 10_000.5,
        elevationGained = 100.5,
        elevationLoss = 90.5,
        averageHeartRate = 145.5,
        heartRateMin = 100.5,
        heartRateMax = 180.5,
        averageSpeed = 3.5,
        maxSpeed = 5.5,
        averagePaceSecondsPerKm = 285.5,
        cyclingCadenceAvg = 88.5,
        cyclingCadenceMax = 120.5,
        stepsCadenceAvg = 170.5,
        stepsCadenceMax = 190.5,
        powerAvg = 275.5,
        powerMax = 650.5,
        laps = listOf(
            WorkoutLapData(
                startTime = start,
                endTime = start.plusMinutes(10),
                length = 1_000.5,
                exactStartTime = exactStart,
                exactEndTime = exactEnd,
                identity = identity,
            ),
        ),
        segments = listOf(
            WorkoutSegmentData(
                startTime = start,
                endTime = start.plusMinutes(5),
                type = "repetition",
                repetitions = 10,
                exactStartTime = exactStart,
                exactEndTime = exactEnd,
                identity = identity,
            ),
        ),
        splits = listOf(
            WorkoutSplitData(
                index = 1,
                startTime = start,
                endTime = start.plusMinutes(6),
                duration = 6.minutes,
                distance = 1_000.0,
                averageHeartRate = 140.5,
                exactStartTime = exactStart,
                exactEndTime = exactEnd,
                identity = identity,
            ),
        ),
        routeAccess = WorkoutRouteAccess.DATA,
        route = listOf(
            WorkoutRoutePointData(
                time = start,
                latitude = 45.5,
                longitude = -122.5,
                altitude = 100.5,
                horizontalAccuracy = 3.5,
                verticalAccuracy = 5.5,
                exactTime = exactStart,
                identity = identity,
            ),
        ),
        heartRateSamples = listOf(sample(start, 145.5)),
        speedSamples = listOf(sample(start.plusMinutes(1), 3.5)),
        cyclingCadenceSamples = listOf(sample(start.plusMinutes(2), 88.5)),
        stepsCadenceSamples = listOf(sample(start.plusMinutes(3), 170.5)),
        powerSamples = listOf(sample(start.plusMinutes(4), 275.5)),
        elevationSamples = listOf(sample(start.plusMinutes(5), 100.5)),
        exactStartTime = exactStart,
        exactEndTime = exactEnd,
        identity = identity,
        correlatedSourceIds = mapOf("route" to listOf("health-connect:route")),
    )
}
