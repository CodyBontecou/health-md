package com.healthmd.rawchanges

import com.fasterxml.jackson.databind.ObjectMapper
import com.fasterxml.jackson.databind.node.ObjectNode
import com.google.common.truth.Truth.assertThat
import com.networknt.schema.InvalidSchemaException
import java.io.File
import java.io.FileNotFoundException
import org.junit.Assert.assertThrows
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class RawChangesSchemaValidationTest {
    @get:Rule val temporary = TemporaryFolder()

    @Test(timeout = 5_000) fun unexpectedExternalReferencesFailClosedEvenBeforeValidatingEvents() {
        val published = schemaDirectory()
        val references = listOf(
            "healthmd.raw_record.v1.schema.json?unexpected",
            "https://health.md/schemas/unrecognized.schema.json",
            "https://unavailable-schema.invalid/raw-record.schema.json",
        )
        references.forEach { reference ->
            val directory = temporary.newFolder()
            File(published, "healthmd.raw_record.v1.schema.json")
                .copyTo(File(directory, "healthmd.raw_record.v1.schema.json"))
            val root = ObjectMapper().readTree(File(published, "healthmd.raw_changes.v1.schema.json")) as ObjectNode
            (root.at("/\$defs/upsertion/properties/record") as ObjectNode).put("\$ref", reference)
            File(directory, "healthmd.raw_changes.v1.schema.json").writeText(root.toString())

            val failure = assertThrows(InvalidSchemaException::class.java) {
                RawChangesSchemaValidation(directory).loadSchema()
            }
            assertThat(failure.message).contains(reference)
        }
    }

    @Test(timeout = 5_000) fun missingPinnedRecordSchemaFailsWithoutRemoteFallback() {
        val directory = temporary.newFolder()
        File(schemaDirectory(), "healthmd.raw_changes.v1.schema.json")
            .copyTo(File(directory, "healthmd.raw_changes.v1.schema.json"))

        assertThrows(FileNotFoundException::class.java) {
            RawChangesSchemaValidation(directory).loadSchema()
        }
    }

    private fun schemaDirectory(): File {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (directory != null) {
            File(directory, "docs/export-contract/schemas").takeIf(File::isDirectory)?.let { return it }
            directory = directory.parentFile
        }
        error("Could not locate the published raw-changes schemas")
    }
}
