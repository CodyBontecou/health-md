package com.healthmd.exportcontract

import com.healthmd.rawchanges.HealthConnectChangesSource
import com.healthmd.rawexport.HealthConnectRecordCatalog
import java.io.File
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class RawChangesContractDocTest {
    private fun repoFile(path: String): File {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (directory != null) {
            File(directory, path).takeIf(File::exists)?.let { return it }
            directory = directory.parentFile
        }
        error("Could not locate $path")
    }

    @Test fun schemaAndIndependentIdentityStayPinned() {
        val schema = Json.parseToJsonElement(
            repoFile("docs/export-contract/schemas/healthmd.raw_changes.v1.schema.json").readText(),
        ).jsonObject
        assertEquals("https://health.md/schemas/healthmd.raw_changes.v1.schema.json", schema.getValue("\$id").jsonPrimitive.content)
        val header = schema.getValue("\$defs").jsonObject.getValue("header").jsonObject
        assertEquals(
            "healthmd.raw-changes",
            header.getValue("properties").jsonObject.getValue("schema").jsonObject.getValue("const").jsonPrimitive.content,
        )
        assertTrue(header.getValue("required").jsonArray.map { it.jsonPrimitive.content }.containsAll(
            listOf("archiveId", "chainId", "sequence", "previousArchiveLogicalHash", "scopeHash", "tokenSemantics"),
        ))
        assertFalse(repoFile("app/src/main/java/com/healthmd/rawexport/RawExportModels.kt").readText().contains("RAW_CHANGES"))
    }

    @Test fun docsPinPrivacyDurabilityBootstrapAndUnsupportedBoundaries() {
        val text = repoFile("docs/export-contract/raw-changes-v1.md").readText()
        listOf(
            "getChangesToken", "getChanges", "opaque changes token", "MUST NOT", "nextChangesToken` remains memory-only",
            "rebase_required", "generated before the base snapshot", "Duplicates are allowed and misses are not",
            "noBackupFilesDir", "AndroidKeyStore", "at-least-once", "unknownDeletionCount",
            "PHR/FHIR", "cloud-provider", "MUST NOT guess",
        ).forEach { phrase -> assertTrue("Missing raw changes contract phrase: $phrase", text.contains(phrase, ignoreCase = false)) }
    }

    @Test fun sdkChangesCatalogIsCompleteWithoutPhrOrCloudClaims() {
        assertEquals(
            HealthConnectRecordCatalog.records.map { it.wireType }.toSet(),
            HealthConnectChangesSource.changeEligibleTypeKeys,
        )
        assertEquals(42, HealthConnectChangesSource.changeEligibleTypeKeys.size)
        assertFalse(HealthConnectChangesSource.changeEligibleTypeKeys.contains("medical_resource"))
    }
}
