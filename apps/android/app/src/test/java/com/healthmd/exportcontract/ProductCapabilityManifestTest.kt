package com.healthmd.exportcontract

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

/**
 * Keeps Android product capability decisions aligned with the language-neutral
 * Apple/Android parity inventory. This is a build-time governance contract,
 * never a runtime health-data resource.
 */
class ProductCapabilityManifestTest {

    @Test
    fun androidAccountsForEveryProductCapability() {
        val inventory = Json.parseToJsonElement(manifestFile().readText()).jsonObject
        assertEquals("healthmd.product_capabilities", inventory.getValue("schema").jsonPrimitive.content)
        assertEquals(1, inventory.getValue("schema_version").jsonPrimitive.content.toInt())

        val profiles = inventory.getValue("output_profiles").jsonArray
            .map { it.jsonObject.getValue("id").jsonPrimitive.content }
            .toSet()
        assertEquals(setOf("apple-v8", "android-frozen-v4", "android-analytical-v5"), profiles)

        val capabilities = inventory.getValue("capabilities").jsonArray.map { it.jsonObject }
        val states = capabilities.associate { capability ->
            capability.getValue("id").jsonPrimitive.content to
                capability.getValue("platforms").jsonObject
                    .getValue("android").jsonObject
                    .getValue("state").jsonPrimitive.content
        }
        assertEquals("Capability IDs must be unique", capabilities.size, states.size)

        assertEquals(sharedCapabilities + androidCapabilities, idsWithState(states, "available"))
        assertEquals(appleCapabilities + "source.private-platform-database", idsWithState(states, "unavailable"))
        assertEquals(setOf("core.shared-rust-profile-engine", "export.profiles", "setup.share-portable-configuration"), idsWithState(states, "planned"))
        assertEquals(allCapabilities, states.keys)

        capabilities.forEach { capability ->
            val id = capability.getValue("id").jsonPrimitive.content
            val availability = capability.getValue("platforms").jsonObject
                .getValue("android").jsonObject
            when (availability.getValue("state").jsonPrimitive.content) {
                "unavailable" -> assertTrue(
                    "Unavailable Android capability $id must include a reason",
                    availability["reason"]?.jsonPrimitive?.content?.isNotBlank() == true,
                )
                "planned" -> assertTrue(
                    "Planned Android capability $id must include a target",
                    availability["target"]?.jsonPrimitive?.content?.isNotBlank() == true,
                )
            }
        }
    }

    private fun idsWithState(states: Map<String, String>, state: String): Set<String> =
        states.filterValues { it == state }.keys

    private fun manifestFile(): File {
        var directory: File? = File(requireNotNull(System.getProperty("user.dir"))).absoluteFile
        while (directory != null) {
            val candidate = File(directory, "packages/contracts/product-capabilities.json")
            if (candidate.isFile) return candidate
            directory = directory.parentFile
        }
        error("Could not locate packages/contracts/product-capabilities.json")
    }

    private companion object {
        val sharedCapabilities = setOf(
            "export.daily-files",
            "export.sleep-summary",
            "export.activity-basics",
            "export.cardiorespiratory-summary",
            "export.vitals-and-body",
            "export.nutrient-totals",
            "export.mindfulness-sessions",
            "export.completed-workouts",
            "export.mobility-and-performance",
            "settings.sleep-attribution",
            "core.shared-rust-metric-registry",
        )

        val appleCapabilities = setOf(
            "apple.lossless-healthkit-archive",
            "apple.medication-dose-events",
            "apple.state-of-mind",
            "apple.wrist-temperature",
            "apple.hearing-and-symptoms",
            "apple.typed-whoop-provider-section",
        )

        val androidCapabilities = setOf(
            "android.activity-intensity",
            "android.planned-workouts",
            "android.menstruation-periods",
            "android.personal-health-records",
            "android.nutrition-meals",
            "android.contextual-source-fields",
            "android.skin-temperature",
        )

        val allCapabilities = sharedCapabilities + appleCapabilities + androidCapabilities + setOf(
            "source.private-platform-database",
            "setup.share-portable-configuration",
            "core.shared-rust-profile-engine",
            "export.profiles",
        )
    }
}
