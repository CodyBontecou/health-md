package com.healthmd.domain.model

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * Cross-platform contract tests for the Android export-profile rules. Every rule here mirrors
 * `ExportProfileStoreTests` on iOS so the two implementations cannot drift silently.
 */
class ExportProfileRulesTest {

    private fun profile(
        id: String,
        name: String,
        target: ExportTarget = ExportTarget.DEVICE_FOLDER,
    ) = ExportProfile(
        id = id,
        name = name,
        settingsSnapshotJson = "{\"exportFormats\":[\"MARKDOWN\"]}",
        target = target,
        createdAtEpochMillis = 1_800_000_000_000,
        updatedAtEpochMillis = 1_800_000_000_000,
    )

    @Test
    fun `uniquifyName trims and suffixes case-insensitively`() {
        // Uniqueness is evaluated against OTHER profiles: renaming a profile to
        // its own trimmed name keeps it (callers pass others, mirroring iOS).
        val others = listOf(profile("b", "Weekly 2"))
        assertEquals("Weekly", ExportProfileRules.uniquifyName("  Weekly ", others))

        val existing = listOf(profile("a", "Weekly"), profile("b", "Weekly 2"))
        // The trimmed input casing is preserved, exactly like iOS.
        assertEquals("weekly 3", ExportProfileRules.uniquifyName("weekly", existing))
        assertEquals("Profile", ExportProfileRules.uniquifyName("   ", existing))
    }

    @Test
    fun `byName matches trimmed and case-insensitive`() {
        val weekly = profile("a", "Weekly Sleep")
        val found = ExportProfileRules.byName(listOf(weekly), "  WEEKLY sleep ")
        assertNotNull(found)
        assertEquals("a", found!!.id)
        assertNull(ExportProfileRules.byName(listOf(weekly), "Weekly"))
        assertNull(ExportProfileRules.byName(listOf(weekly), "   "))
    }

    @Test
    fun `resolve fails closed for unknown references and never falls back`() {
        val daily = profile("a", "Daily")
        val profiles = listOf(daily)
        assertTrue(ExportProfileRules.resolve(profiles, id = "missing", name = null) is ExportProfileResolution.NotFound)
        assertTrue(ExportProfileRules.resolve(profiles, id = null, name = "Ghost") is ExportProfileResolution.NotFound)
    }

    @Test
    fun `resolve with no reference uses the active profile`() {
        val daily = profile("a", "Daily")
        val weekly = profile("b", "Weekly")
        val resolution = ExportProfileRules.resolve(listOf(daily, weekly), id = "b", name = null)
        assertTrue(resolution is ExportProfileResolution.Resolved)
        assertEquals("b", (resolution as ExportProfileResolution.Resolved).profile.id)

        // No active pointer: the first profile wins (repository guarantees one is active).
        val fallback = ExportProfileRules.resolve(listOf(daily, weekly), id = null, name = null)
        assertEquals("a", (fallback as ExportProfileResolution.Resolved).profile.id)
    }

    @Test
    fun `empty profile list keeps legacy live settings`() {
        assertEquals(
            ExportProfileResolution.LegacySettings,
            ExportProfileRules.resolve(emptyList(), id = "any", name = null),
        )
    }

    @Test
    fun `last profile can never be deleted`() {
        assertFalse(ExportProfileRules.canDelete(listOf(profile("a", "Only"))))
        assertTrue(ExportProfileRules.canDelete(listOf(profile("a", "A"), profile("b", "B"))))
    }

    @Test
    fun `migration creates exactly one default bound to the current target`() {
        val first = ExportProfileRules.migrateDefault(
            existing = emptyList(),
            snapshotJson = "{\"frozen\":true}",
            target = ExportTarget.API_ENDPOINT,
            nowEpochMillis = 42L,
            newId = { "generated" },
        )
        assertNotNull(first)
        assertEquals("Default", first!!.name)
        assertTrue(first.isMigrationDefault)
        assertEquals(ExportTarget.API_ENDPOINT, first.target)
        assertEquals("{\"frozen\":true}", first.settingsSnapshotJson)

        // Idempotent once any profile exists.
        assertNull(
            ExportProfileRules.migrateDefault(
                existing = listOf(first),
                snapshotJson = "{}",
                target = ExportTarget.DEVICE_FOLDER,
                nowEpochMillis = 43L,
                newId = { "other" },
            ),
        )
    }

    @Test
    fun `decodeSnapshot tolerates arbitrary canonical json`() {
        val p = profile("a", "Daily").copy(
            settingsSnapshotJson = "{\"exportFormats\":[\"JSON\",\"CSV\"],\"filenameFormat\":\"x-{date}\"}",
        )
        val view = ExportProfileRules.decodeSnapshot(p)
        assertNotNull(view)
        assertEquals(setOf("JSON", "CSV"), view!!.exportFormats)
        assertEquals("x-{date}", view.filenameFormat)

        assertNull(ExportProfileRules.decodeSnapshot(profile("b", "Broken").copy(settingsSnapshotJson = "not json")))
    }
}
