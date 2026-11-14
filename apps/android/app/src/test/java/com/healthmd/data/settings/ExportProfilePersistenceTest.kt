package com.healthmd.data.settings

import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.mutablePreferencesOf
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportTarget
import org.junit.Assert.*
import org.junit.Test

class ExportProfilePersistenceTest {
    private fun profile(id: String, target: ExportTarget = ExportTarget.DEVICE_FOLDER) = ExportProfile(
        id = id, name = id, settingsSnapshotJson = "{}", target = target,
        destinationId = "synthetic-local-destination".takeIf { target == ExportTarget.GOOGLE_DRIVE },
        createdAtEpochMillis = 1, updatedAtEpochMillis = 2,
    )

    @Test fun `lazy migration preserves legacy bytes and active id while envelope wins`() {
        val prefs = mutablePreferencesOf()
        val legacy = "  " + ExportProfilePersistence.encode(listOf(profile("legacy")), false) + "\n"
        prefs[ExportProfilePersistence.legacyProfilesKey] = legacy
        prefs[ExportProfilePersistence.legacyActiveKey] = "legacy"
        val decoded = ExportProfilePersistence.decode(prefs)
        ExportProfilePersistence.writeNative(prefs, decoded, decoded.profiles + profile("drive", ExportTarget.GOOGLE_DRIVE))
        assertEquals(legacy, prefs[ExportProfilePersistence.legacyProfilesKey])
        assertEquals("legacy", prefs[ExportProfilePersistence.legacyActiveKey])
        prefs[ExportProfilePersistence.activeKey] = "drive"
        assertEquals("drive", ExportProfilePersistence.activeId(prefs))
        assertEquals(listOf("legacy", "drive"), ExportProfilePersistence.requireTransactionProfiles(prefs).map { it.id })
    }

    @Test fun `transaction append preserves existing record bytes including escaped brackets`() {
        val first = profile("first").copy(settingsSnapshotJson = "literal ] [ \\\" bracket")
        val existingArray = "\n[  " + ExportProfilePersistence.encode(listOf(first), false).removePrefix("[").removeSuffix("]") + "  ]\n"
        for (raw in listOf(existingArray, "{\"records\":$existingArray,\"version\":2}")) {
            val added = ExportProfilePersistence.appendRecords(raw, ExportProfilePersistence.encode(listOf(profile("second")), false))
            assertTrue(added.contains(existingArray.substringBeforeLast(']')))
            val prefs = mutablePreferencesOf()
            prefs[if (raw.trim().startsWith("{")) ExportProfilePersistence.profilesKey else ExportProfilePersistence.legacyProfilesKey] = added
            assertEquals(listOf(first, profile("second")), ExportProfilePersistence.requireTransactionProfiles(prefs))
        }
    }

    @Test fun `future root and corrupt record never fall back to legacy`() {
        for (raw in listOf("{not-json", "{\"version\":3,\"records\":[]}", "{\"version\":\"2\",\"records\":[]}",
            "{\"version\":2,\"records\":[{\"target\":\"FUTURE_CLOUD\"}]}",
            "{\"version\":2,\"records\":[],\"future_authority\":true}")) {
            val prefs = mutablePreferencesOf()
            prefs[ExportProfilePersistence.legacyProfilesKey] = ExportProfilePersistence.encode(listOf(profile("legacy")), false)
            prefs[ExportProfilePersistence.profilesKey] = raw
            assertTrue(ExportProfilePersistence.decode(prefs).blocksDefaultMigration)
            assertTrue(ExportProfilePersistence.decode(prefs).profiles.isEmpty())
            assertThrows(IllegalArgumentException::class.java) { ExportProfilePersistence.requireTransactionProfiles(prefs) }
            assertEquals(raw, prefs[ExportProfilePersistence.profilesKey])
        }
    }

    @Test fun `tolerant native edits retain opaque records and duplicate identities`() {
        val prefs = mutablePreferencesOf()
        val encoded = ExportProfilePersistence.encode(listOf(profile("known")), false).removePrefix("[").removeSuffix("]")
        val opaque = "{\"target\":\"FUTURE_CLOUD\",\"kept\":true}"
        prefs[ExportProfilePersistence.profilesKey] = "{\"version\":2,\"records\":[$encoded,$opaque,$encoded]}"
        val decoded = ExportProfilePersistence.decode(prefs)
        assertEquals(1, decoded.profiles.size)
        assertTrue(decoded.blocksDefaultMigration)
        ExportProfilePersistence.writeNative(prefs, decoded, decoded.profiles + profile("new"))
        val raw = prefs[ExportProfilePersistence.profilesKey]!!
        assertTrue(raw.contains(opaque))
        assertTrue(ExportProfilePersistence.decode(prefs).blocksDefaultMigration)
        assertThrows(IllegalArgumentException::class.java) { ExportProfilePersistence.requireTransactionProfiles(prefs) }
    }

    @Test fun `unknown future fields stay opaque unrunnable and survive native edits`() {
        val prefs = mutablePreferencesOf()
        val encoded = ExportProfilePersistence.encode(listOf(profile("known")), true)
        prefs[ExportProfilePersistence.profilesKey] = encoded.replace("\"name\":\"known\"", "\"future_authority\":true,\"name\":\"known\"")
        val decoded = ExportProfilePersistence.decode(prefs)
        assertTrue(decoded.profiles.isEmpty())
        assertTrue(decoded.blocksDefaultMigration)
        assertThrows(Exception::class.java) { ExportProfilePersistence.requireTransactionProfiles(prefs) }
        ExportProfilePersistence.writeNative(prefs, decoded, listOf(profile("new")))
        assertTrue(prefs[ExportProfilePersistence.profilesKey]!!.contains("\"future_authority\":true"))
        assertEquals(listOf(profile("new")), ExportProfilePersistence.decode(prefs).profiles)
        assertTrue(ExportProfilePersistence.decode(prefs).blocksDefaultMigration)
    }

    @Test fun `wrong typed envelope presence blocks legacy fallback without erasing state`() {
        val prefs = mutablePreferencesOf()
        prefs[ExportProfilePersistence.legacyProfilesKey] = ExportProfilePersistence.encode(listOf(profile("legacy")), false)
        prefs[ExportProfilePersistence.legacyActiveKey] = "legacy"
        prefs[booleanPreferencesKey(ExportProfilePersistence.profilesKey.name)] = true
        val before = prefs.asMap().toMap()
        val decoded = ExportProfilePersistence.decode(prefs)
        assertTrue(decoded.corruptRoot)
        assertTrue(decoded.profiles.isEmpty())
        assertNull(ExportProfilePersistence.activeId(prefs))
        assertThrows(IllegalArgumentException::class.java) { ExportProfilePersistence.requireTransactionProfiles(prefs) }
        assertThrows(IllegalStateException::class.java) { ExportProfilePersistence.writeNative(prefs, decoded, listOf(profile("new"))) }
        assertEquals(before, prefs.asMap())
    }
}
