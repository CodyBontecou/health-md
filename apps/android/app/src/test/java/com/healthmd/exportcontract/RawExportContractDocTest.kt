package com.healthmd.exportcontract

import com.healthmd.rawexport.HealthConnectRecordCatalog
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

class RawExportContractDocTest {
    private val json = Json { ignoreUnknownKeys = false }

    private fun repoFile(path: String): File {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (directory != null) {
            val candidate = File(directory, path)
            if (candidate.exists()) return candidate
            directory = directory.parentFile
        }
        throw AssertionError("Could not locate $path")
    }

    private fun readJson(path: String): JsonObject =
        json.parseToJsonElement(repoFile(path).readText()).jsonObject

    private fun section(text: String, heading: String): String {
        val start = text.indexOf("## $heading")
        require(start >= 0) { "Missing section $heading" }
        val tail = text.substring(start)
        val next = tail.indexOf("\n## ", 1)
        return if (next < 0) tail else tail.substring(0, next)
    }

    private fun table(section: String): List<List<String>> = section.lineSequence()
        .filter { it.startsWith("| ") }
        .filterNot { it.startsWith("|---") }
        .map { line -> line.trim().trim('|').split('|').map { it.trim() } }
        .drop(1)
        .toList()

    private fun String.unquoteCode(): String = removePrefix("`").removeSuffix("`")

    @Test
    fun schemaIdsAndStructuralExtensionPolicyStayPinned() {
        val record = readJson("docs/export-contract/schemas/healthmd.raw_record.v1.schema.json")
        val snapshot = readJson("docs/export-contract/schemas/healthmd.raw_snapshot.v1.schema.json")

        assertEquals("https://json-schema.org/draft/2020-12/schema", record.getValue("\$schema").jsonPrimitive.content)
        assertEquals("https://health.md/schemas/healthmd.raw_record.v1.schema.json", record.getValue("\$id").jsonPrimitive.content)
        assertEquals("https://health.md/schemas/healthmd.raw_snapshot.v1.schema.json", snapshot.getValue("\$id").jsonPrimitive.content)

        val recordProperties = record.getValue("properties").jsonObject
        val required = record.getValue("required").jsonArray.map { it.jsonPrimitive.content }.toSet()
        assertEquals(recordProperties.keys, required)
        assertTrue(recordProperties.getValue("fields").jsonObject.getValue("additionalProperties").jsonPrimitive.boolean)
        assertFalse(record.getValue("additionalProperties").jsonPrimitive.boolean)
        assertEquals(
            "healthmd.raw_record.v1.schema.json",
            snapshot.getValue("properties").jsonObject.getValue("records").jsonObject
                .getValue("items").jsonObject.getValue("\$ref").jsonPrimitive.content,
        )
    }

    @Test
    fun schemasDescribeCurrentV1EnvelopeKeysAndApiCompleteStatuses() {
        val snapshotSchema = readJson("docs/export-contract/schemas/healthmd.raw_snapshot.v1.schema.json")
        val fixture = readJson("app/src/test/resources/raw-export/v1/minimal-snapshot.json")
        val rootRequired = snapshotSchema.getValue("required").jsonArray.map { it.jsonPrimitive.content }.toSet()
        assertTrue(fixture.keys.containsAll(rootRequired))

        val defs = snapshotSchema.getValue("\$defs").jsonObject
        listOf("header", "manifest").forEach { name ->
            val required = defs.getValue(name).jsonObject.getValue("required").jsonArray
                .map { it.jsonPrimitive.content }.toSet()
            assertTrue("Fixture $name is missing ${required - fixture.getValue(name).jsonObject.keys}", fixture.getValue(name).jsonObject.keys.containsAll(required))
        }

        val statuses = defs.getValue("typeReport").jsonObject.getValue("properties").jsonObject
            .getValue("status").jsonObject.getValue("enum").jsonArray.map { it.jsonPrimitive.content }.toSet()
        assertEquals(
            setOf(
                "exported", "not_selected", "permission_not_granted", "feature_unavailable",
                "history_permission_missing", "read_error", "unsupported_by_provider",
            ),
            statuses,
        )
        val manifestRequired = defs.getValue("manifest").jsonObject.getValue("required").jsonArray
            .map { it.jsonPrimitive.content }.toSet()
        assertTrue("API-complete v1 requires typeReports", "typeReports" in manifestRequired)
        assertTrue("API-complete v1 requires identity collision accounting", "identityCollisionCount" in manifestRequired)
        assertTrue("API-complete v1 requires a completion instant", "completedAt" in manifestRequired)
        val manifestStatuses = defs.getValue("manifest").jsonObject.getValue("properties").jsonObject
            .getValue("status").jsonObject.getValue("enum").jsonArray.map { it.jsonPrimitive.content }.toSet()
        assertEquals(setOf("COMPLETE", "PARTIAL", "FAILED"), manifestStatuses)
        val typeReportRequired = defs.getValue("typeReport").jsonObject.getValue("required").jsonArray
            .map { it.jsonPrimitive.content }.toSet()
        assertTrue("rangeBehavior" in typeReportRequired)
    }

    @Test
    fun healthConnectLedgerMatchesEveryCatalogDescriptorAndMetricMapping() {
        val ledger = repoFile("docs/export-contract/health-connect-raw-record-ledger.md").readText()
        val rows = table(section(ledger, "2. HealthConnectRecordCatalog descriptors"))
        val byType = rows.associateBy { it[0].unquoteCode() }
        val catalog = HealthConnectRecordCatalog.records.associateBy { it.wireType }

        assertEquals(42, rows.size)
        assertEquals(catalog.keys, byType.keys)
        rows.forEach { row ->
            assertEquals("Ledger row width for ${row[0]}", 10, row.size)
            val descriptor = catalog.getValue(row[0].unquoteCode())
            val metricIds = row[4].split(',').map(String::trim).filter(String::isNotBlank).toSet()
            assertEquals("Metric aliases differ for ${descriptor.wireType}", descriptor.metricIds, metricIds)
            assertTrue("Missing permission for ${descriptor.wireType}", row[2].contains("READ_"))
            assertTrue("Missing range behavior for ${descriptor.wireType}", row[5].contains("[s,e)"))
            assertTrue("Missing mapper decision for ${descriptor.wireType}", row[6].contains("explicit"))
            assertTrue("Missing nested-risk note for ${descriptor.wireType}", row[7].isNotBlank())
            assertTrue("Missing unit decision for ${descriptor.wireType}", row[8].isNotBlank())
            assertEquals(if (descriptor.changeEligible) "yes" else "no", row[9])
        }
        assertEquals("explicit", byType.getValue("sleep_session")[6])
    }

    @Test
    fun ledgerContainsEveryMedicalCategoryAndRecordFieldInventory() {
        val ledger = repoFile("docs/export-contract/health-connect-raw-record-ledger.md").readText()
        val medicalRows = table(section(ledger, "3. Personal Health Record medical categories"))
        val medicalKeys = medicalRows.map { it[0].unquoteCode() }.toSet()
        assertEquals(
            setOf(
                "medical_resource/allergies_intolerances", "medical_resource/conditions",
                "medical_resource/laboratory_results", "medical_resource/medications",
                "medical_resource/personal_details", "medical_resource/practitioner_details",
                "medical_resource/pregnancy", "medical_resource/procedures",
                "medical_resource/social_history", "medical_resource/vaccines",
                "medical_resource/visits", "medical_resource/vital_signs",
            ),
            medicalKeys,
        )
        medicalRows.forEach { row ->
            assertEquals("Medical ledger row width for ${row[0]}", 10, row.size)
            assertEquals("FEATURE_PERSONAL_HEALTH_RECORD", row[3])
            assertEquals("medical_resources", row[4])
            assertEquals("unbounded_non_temporal", row[5])
            assertEquals("explicit", row[6])
            assertEquals("no", row[9])
        }

        val recordDoc = repoFile("docs/export-contract/raw-record-v1.md").readText()
        val fieldRows = table(section(recordDoc, "6. Native field inventory"))
        val fieldTypes = fieldRows.map { it[0].unquoteCode() }.toSet()
        assertEquals(HealthConnectRecordCatalog.records.map { it.wireType }.toSet() + "medical_resource", fieldTypes)
    }

    @Test
    fun normativeContractPhrasesCannotDriftOut() {
        val snapshot = repoFile("docs/export-contract/raw-snapshot-v1.md").readText()
        val record = repoFile("docs/export-contract/raw-record-v1.md").readText()
        val ledger = repoFile("docs/export-contract/health-connect-raw-record-ledger.md").readText()

        listOf(
            "[startInclusive,endExclusive)",
            "non_transactional",
            "No final NDJSON manifest means incomplete.",
            "SELECTED_RECORD_TYPES",
            "ALL_AUTHORIZED_SUPPORTED_DATA",
            "permission_not_granted",
            "history_permission_missing",
            "unsupported_by_provider",
            "manifestChecksumSha256",
            "Cancellation MUST abort/delete partial output",
            "Per-type `typeReports` | Implemented",
        ).forEach { phrase -> assertTrue("Missing snapshot contract phrase: $phrase", snapshot.contains(phrase)) }

        listOf(
            "## 2. Null versus absent",
            "Preserve exact FHIR string.",
            "`fhirResourceJson` MUST equal the SDK-provided string character-for-character",
            "unknown_<raw>",
            "preservesSourceUnits=false",
            "Additive fields are allowed",
        ).forEach { phrase -> assertTrue("Missing record contract phrase: $phrase", record.contains(phrase)) }

        assertTrue(ledger.contains("All 42 descriptors currently set `changeEligible=true`"))
        assertTrue(ledger.contains("SleepSessionRecord"))
        assertTrue(ledger.contains("exact FHIR string"))
        assertTrue(ledger.contains("normalized cloud API values are not equivalent"))
    }
}
