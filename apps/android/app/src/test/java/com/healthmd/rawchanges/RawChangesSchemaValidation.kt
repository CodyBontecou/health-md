package com.healthmd.rawchanges

import com.networknt.schema.JsonSchema
import com.networknt.schema.JsonSchemaFactory
import com.networknt.schema.SpecVersion
import com.networknt.schema.resource.DisallowSchemaLoader
import java.io.File
import java.net.URI

/** Validate the published contracts, including relative refs, without fetching mutable remote bytes. */
internal class RawChangesSchemaValidation(schemaDirectory: File) {
    private val factory = JsonSchemaFactory.getInstance(SpecVersion.VersionFlag.V202012) { builder ->
        builder.schemaLoaders { loaders ->
            loaders.schemas(mapOf(
                ARCHIVE_SCHEMA_ID to File(schemaDirectory, "healthmd.raw_changes.v1.schema.json").readText(),
                RECORD_SCHEMA_ID to File(schemaDirectory, "healthmd.raw_record.v1.schema.json").readText(),
            ))
            // Returning null for an unknown URI would fall through to networknt's network loader.
            loaders.add(DisallowSchemaLoader.getInstance())
        }
    }

    fun loadSchema(): JsonSchema = factory.getSchema(URI.create(ARCHIVE_SCHEMA_ID)).also {
        // getSchema's best-effort preload suppresses resolution failures. Require complete
        // reference initialization even for archives with no events, and propagate failures.
        it.initializeValidators()
    }

    private companion object {
        const val ARCHIVE_SCHEMA_ID = "https://health.md/schemas/healthmd.raw_changes.v1.schema.json"
        const val RECORD_SCHEMA_ID = "https://health.md/schemas/healthmd.raw_record.v1.schema.json"
    }
}
