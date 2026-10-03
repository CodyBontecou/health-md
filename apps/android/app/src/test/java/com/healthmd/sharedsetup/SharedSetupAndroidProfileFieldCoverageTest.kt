package com.healthmd.sharedsetup

import com.healthmd.data.scheduler.ScheduledProfileEntry
import com.healthmd.data.scheduler.ScheduledProfilePendingExport
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.ExportEnginePin
import com.healthmd.domain.model.CustomFrontmatterField
import com.healthmd.domain.model.DailyNoteInjectionSettings
import com.healthmd.domain.model.DataTypeSelection
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.FormatCustomization
import com.healthmd.domain.model.FrontmatterConfiguration
import com.healthmd.domain.model.IndividualTrackingSettings
import com.healthmd.domain.model.MarkdownTemplateConfig
import com.healthmd.domain.model.MetricSelectionState
import com.healthmd.domain.model.MetricTrackingConfig
import com.healthmd.domain.model.PendingScheduledExportRequest
import com.healthmd.domain.model.RawSnapshotSettings
import java.io.File
import kotlinx.serialization.ExperimentalSerializationApi
import kotlinx.serialization.descriptors.SerialDescriptor
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Build-time governance guard for Android fields that could otherwise drift into Shared Setup v2
 * without an explicit portability, native-extension, or exclusion review.
 */
@OptIn(ExperimentalSerializationApi::class)
class SharedSetupAndroidProfileFieldCoverageTest {

    @Test
    fun ledgerExactlyCoversSerializableAndSupplementalProfileFields() {
        val ledger = ledgerObject()
        assertEquals("healthmd.shared_setup.android_profile_field_coverage", ledger.getValue("schema").jsonPrimitive.content)
        assertEquals(1, ledger.getValue("schema_version").jsonPrimitive.content.toInt())

        val target = ledger.getValue("target_contract").jsonObject
        assertEquals("healthmd.shared_setup", target.getValue("schema").jsonPrimitive.content)
        assertEquals(2, target.getValue("schema_version").jsonPrimitive.content.toInt())
        assertTrue(
            "The audited Git base must be an exact lowercase commit id",
            ledger.getValue("audited_git_base").jsonPrimitive.content.matches(Regex("[0-9a-f]{40}")),
        )

        val rows = rows(ledger)
        val keys = rows.map(FieldRow::key)
        assertEquals("Coverage rows must be unique by source type and serialized field", keys.size, keys.toSet().size)

        val expectedKinds = buildMap {
            descriptorInventory().forEach { (sourceType, descriptor) ->
                repeat(descriptor.elementsCount) { index ->
                    put(FieldKey(sourceType, descriptor.getElementName(index)), DESCRIPTOR)
                }
            }
            supplementalInventory.forEach { key -> put(key, SUPPLEMENTAL) }
        }
        val actualKinds = rows.associate { it.key to it.coverageKind }

        val missing = expectedKinds.keys - actualKinds.keys
        val stale = actualKinds.keys - expectedKinds.keys
        assertTrue("Unclassified descriptor/supplemental fields: ${missing.sortedForMessage()}", missing.isEmpty())
        assertTrue("Stale ledger rows: ${stale.sortedForMessage()}", stale.isEmpty())
        assertEquals("Every row must declare the correct coverage kind", expectedKinds, actualKinds)

        val rowOrder = rows.map { it.key }
        assertEquals(
            "Ledger rows must stay deterministically sorted",
            rowOrder.sortedWith(compareBy<FieldKey>({ it.sourceType }, { it.serializedField })),
            rowOrder,
        )
    }

    @Test
    fun ledgerRejectsInvalidDispositionAndContractPathCombinations() {
        val ledger = ledgerObject()
        val allowed = ledger.getValue("allowed_dispositions").jsonArray
            .map { it.jsonPrimitive.content }
            .toSet()
        assertEquals(ALLOWED_DISPOSITIONS, allowed)

        rows(ledger).forEach { row ->
            assertTrue("${row.key} has an unknown disposition", row.disposition in allowed)
            assertTrue("${row.key} requires non-empty evidence", row.evidence.isNotBlank())

            when (row.disposition) {
                PORTABLE -> {
                    assertNotNull("${row.key} portable fields require a v2 path", row.contractPath)
                    assertTrue(
                        "${row.key} has a non-portable common path: ${row.contractPath}",
                        PORTABLE_ROOTS.any { root ->
                            row.contractPath == root || row.contractPath!!.startsWith("$root.")
                        },
                    )
                }
                PLATFORM_EXTENSION -> {
                    assertNotNull("${row.key} extension fields require a v2 path", row.contractPath)
                    assertTrue(
                        "${row.key} must target the typed Android extension",
                        row.contractPath!!.startsWith(ANDROID_EXTENSION_PREFIX),
                    )
                }
                DESTINATION_INTENT -> {
                    assertNotNull("${row.key} destination intent requires a v2 path", row.contractPath)
                    assertTrue(
                        "${row.key} must target inert destination intent",
                        row.contractPath!!.startsWith(DESTINATION_PREFIX),
                    )
                }
                SCHEDULE_INTENT -> {
                    assertNotNull("${row.key} schedule intent requires a v2 path", row.contractPath)
                    assertTrue(
                        "${row.key} must target declarative schedule intent",
                        row.contractPath!!.startsWith(SCHEDULE_PREFIX),
                    )
                }
                DERIVED_OR_LEGACY, LOCAL_ONLY, PROHIBITED ->
                    assertNull("${row.key} ${row.disposition} fields cannot have a contract path", row.contractPath)
            }

            row.contractPath?.let { path ->
                assertTrue("${row.key} must target a profile-scoped v2 path", path.startsWith("profiles[]."))
                assertFalse("${row.key} must never target the Apple extension", path.contains(".apple."))
            }
        }
    }

    @Test
    fun prohibitedFieldsNeverReceiveAContractPath() {
        val prohibited = rows(ledgerObject()).filter { it.disposition == PROHIBITED }
        assertTrue("The audit must explicitly account for prohibited native state", prohibited.isNotEmpty())
        prohibited.forEach { row ->
            assertNull("Prohibited field ${row.key} was assigned a contract path", row.contractPath)
        }
    }

    private fun rows(ledger: kotlinx.serialization.json.JsonObject): List<FieldRow> =
        ledger.getValue("fields").jsonArray.map { element ->
            val value = element.jsonObject
            assertEquals(
                "Coverage row keys changed without updating the executable reader",
                setOf("source_type", "serialized_field", "coverage_kind", "disposition", "contract_path", "evidence"),
                value.keys,
            )
            FieldRow(
                sourceType = value.getValue("source_type").jsonPrimitive.content,
                serializedField = value.getValue("serialized_field").jsonPrimitive.content,
                coverageKind = value.getValue("coverage_kind").jsonPrimitive.content,
                disposition = value.getValue("disposition").jsonPrimitive.content,
                contractPath = value.getValue("contract_path").let { path ->
                    if (path is JsonNull) null else path.jsonPrimitive.content
                },
                evidence = value.getValue("evidence").jsonPrimitive.content,
            )
        }

    private fun ledgerObject() = Json.parseToJsonElement(ledgerFile().readText()).jsonObject

    /** Mirrors the established Android root-fixture lookup used by Shared Setup contract tests. */
    private fun ledgerFile(): File {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (directory != null) {
            val candidate = File(
                directory,
                "packages/contracts/shared-setup/v2/android-profile-field-coverage.json",
            )
            if (candidate.isFile) return candidate
            directory = directory.parentFile
        }
        error("Could not locate the Android Shared Setup v2 profile-field coverage ledger")
    }

    private fun descriptorInventory(): Map<String, SerialDescriptor> {
        val snapshot = AndroidExportSettingsSnapshot.serializer().descriptor
        val compactFormat = snapshot.child("formatCustomization")
        val compactFrontmatter = compactFormat.child("f")
        val compactMarkdown = compactFormat.child("m")

        return linkedMapOf(
            "AndroidExportSettingsSnapshot" to snapshot,
            "CustomFrontmatterField" to CustomFrontmatterField.serializer().descriptor,
            "DataTypeSelection" to DataTypeSelection.serializer().descriptor,
            "DailyNoteInjectionSettings" to DailyNoteInjectionSettings.serializer().descriptor,
            "ExportEnginePin" to ExportEnginePin.serializer().descriptor,
            "ExportProfile" to ExportProfile.serializer().descriptor,
            "ExportSettings" to ExportSettings.serializer().descriptor,
            "FormatCustomization" to FormatCustomization.serializer().descriptor,
            "FrontmatterConfiguration" to FrontmatterConfiguration.serializer().descriptor,
            "IndividualTrackingSettings" to IndividualTrackingSettings.serializer().descriptor,
            "MarkdownTemplateConfig" to MarkdownTemplateConfig.serializer().descriptor,
            "MetricSelectionState" to MetricSelectionState.serializer().descriptor,
            "MetricTrackingConfig" to MetricTrackingConfig.serializer().descriptor,
            "PendingScheduledExportRequest" to PendingScheduledExportRequest.serializer().descriptor,
            "RawSnapshotSettings" to RawSnapshotSettings.serializer().descriptor,
            "ScheduledProfileEntry" to ScheduledProfileEntry.serializer().descriptor,
            "ScheduledProfilePendingExport" to ScheduledProfilePendingExport.serializer().descriptor,
            "SnapshotFormatCustomizationPayload" to compactFormat,
            "SnapshotFrontmatterPayload" to compactFrontmatter,
            "SnapshotMarkdownPayload" to compactMarkdown,
        )
    }

    private fun SerialDescriptor.child(serializedField: String): SerialDescriptor {
        val index = getElementIndex(serializedField)
        require(index >= 0) { "$serialName has no serialized field $serializedField" }
        return getElementDescriptor(index)
    }

    private data class FieldKey(
        val sourceType: String,
        val serializedField: String,
    ) {
        override fun toString(): String = "$sourceType.$serializedField"
    }

    private data class FieldRow(
        val sourceType: String,
        val serializedField: String,
        val coverageKind: String,
        val disposition: String,
        val contractPath: String?,
        val evidence: String,
    ) {
        val key: FieldKey get() = FieldKey(sourceType, serializedField)
    }

    private companion object {
        const val DESCRIPTOR = "descriptor"
        const val SUPPLEMENTAL = "supplemental"

        const val PORTABLE = "portable"
        const val PLATFORM_EXTENSION = "platform_extension"
        const val DESTINATION_INTENT = "destination_intent"
        const val SCHEDULE_INTENT = "schedule_intent"
        const val DERIVED_OR_LEGACY = "derived_or_legacy"
        const val LOCAL_ONLY = "local_only"
        const val PROHIBITED = "prohibited"

        val ALLOWED_DISPOSITIONS = setOf(
            PORTABLE,
            PLATFORM_EXTENSION,
            DESTINATION_INTENT,
            SCHEDULE_INTENT,
            DERIVED_OR_LEGACY,
            LOCAL_ONLY,
            PROHIBITED,
        )

        val PORTABLE_ROOTS = listOf(
            "profiles[].name",
            "profiles[].export",
            "profiles[].metrics",
            "profiles[].presentation",
            "profiles[].individual_entries",
            "profiles[].daily_notes",
        )
        const val ANDROID_EXTENSION_PREFIX = "profiles[].platform_extensions.android."
        const val DESTINATION_PREFIX = "profiles[].destination."
        const val SCHEDULE_PREFIX = "profiles[].schedule."

        val supplementalInventory = setOf(
            FieldKey("CustomFrontmatterField", "outputKey"),
            FieldKey("DataTypeSelection", "enabledCount"),
            FieldKey("DataTypeSelection", "hasAnySelected"),
            FieldKey("ExportSettings", "executionEngineAuthorityIsFrozen"),
            FieldKey("ExportSettings", "executionEnginePin"),
            FieldKey("ExportSettings", "selectedExportFormats"),
            FieldKey("FormatCustomization", "unitConverter"),
            FieldKey("IndividualTrackingSettings", "rawTrackedMetricIds"),
            FieldKey("IndividualTrackingSettings", "requiresGranularData"),
            FieldKey("IndividualTrackingSettings", "trackedMetricCount"),
            FieldKey("IndividualTrackingSettings", "trackedMetricIds"),
            FieldKey("MetricSelectionState", "enabledCount"),
            FieldKey("ScheduledProfileEntry", "zone"),
            FieldKey("ScheduledProfilePendingExport", "ownerDates"),
        )

        fun Collection<FieldKey>.sortedForMessage(): List<String> =
            sortedWith(compareBy<FieldKey>({ it.sourceType }, { it.serializedField })).map(FieldKey::toString)
    }
}
