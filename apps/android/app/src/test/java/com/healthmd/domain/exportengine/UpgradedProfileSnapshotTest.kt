package com.healthmd.domain.exportengine

import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

/**
 * #329: profiles saved by Android 3.5.0 must still run after upgrading. 3.5.2 added
 * metricSelection.nativeDetailMetricIds, so re-encoding a 3.5.0 snapshot no longer matched its
 * stored bytes, decodeOrNull rejected it, and every scheduled run failed and paused the automation.
 * The fixture is the Default profile snapshot a fresh 3.5.0 install wrote on an emulator.
 */
class UpgradedProfileSnapshotTest {
    private val stored = javaClass.classLoader!!
        .getResource("upgrade/android-3.5.0-default-profile-snapshot.json")!!.readText()

    @Test
    fun `a 3_5_0 snapshot decodes and keeps its settings`() {
        assertFalse("fixture predates the new field", stored.contains("nativeDetailMetricIds"))
        val decoded = AndroidExportSettingsSnapshotCodec.decodeOrNull(stored)
        assertNotNull("3.5.0 snapshot must decode", decoded)
        // Re-encoding only adds the missing default; every stored value is unchanged.
        val canonical = Json.parseToJsonElement(AndroidExportSettingsSnapshotCodec.encodeCanonical(decoded!!)).jsonObject
        val original = Json.parseToJsonElement(stored).jsonObject
        assertEquals(original.keys, canonical.keys)
        for (key in original.keys - "metricSelection") assertEquals(key, original[key], canonical[key])
        val metrics = canonical["metricSelection"]!!.jsonObject
        assertEquals(original["metricSelection"]!!.jsonObject["enabledMetrics"], metrics["enabledMetrics"])
        assertEquals("[]", metrics["nativeDetailMetricIds"].toString())
    }

    @Test
    fun `current snapshots still round-trip exactly`() {
        val decoded = AndroidExportSettingsSnapshotCodec.decodeOrNull(stored)!!
        val canonical = AndroidExportSettingsSnapshotCodec.encodeCanonical(decoded)
        assertNotNull(AndroidExportSettingsSnapshotCodec.decodeOrNull(canonical))
    }

    @Test
    fun `other non-canonical encodings still fail closed`() {
        val obj = Json.parseToJsonElement(stored).jsonObject
        val reordered = JsonObject(obj.entries.reversed().associate { it.key to it.value }).toString()
        assertNull("reordered keys", AndroidExportSettingsSnapshotCodec.decodeOrNull(reordered))
        assertNull("whitespace", AndroidExportSettingsSnapshotCodec.decodeOrNull(stored.replaceFirst(",", ", ")))
        val extra = JsonObject(obj + ("unexpectedField" to JsonPrimitive(true))).toString()
        assertNull("unknown key", AndroidExportSettingsSnapshotCodec.decodeOrNull(extra))
    }

    @Test
    fun `older encoding means only missing fields`() {
        val codec = AndroidExportSettingsSnapshotCodec
        fun j(s: String) = Json.parseToJsonElement(s)
        assertTrue(codec.isOlderEncodingOf(j("""{"a":1,"m":{"x":[1]}}"""), j("""{"a":1,"m":{"x":[1],"y":[]}}""")))
        assertFalse(codec.isOlderEncodingOf(j("""{"a":2}"""), j("""{"a":1}""")))
        assertFalse(codec.isOlderEncodingOf(j("""{"b":1,"a":1}"""), j("""{"a":1,"b":1}""")))
        assertFalse(codec.isOlderEncodingOf(j("""{"a":1,"z":1}"""), j("""{"a":1}""")))
        assertFalse(codec.isOlderEncodingOf(j("""{"x":[1]}"""), j("""{"x":[1,2]}""")))
    }
}
