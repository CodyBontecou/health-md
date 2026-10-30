package com.healthmd.direct.protocol

import com.google.common.truth.Truth.assertThat
import kotlinx.serialization.json.encodeToJsonElement
import kotlinx.serialization.json.decodeFromJsonElement
import kotlinx.serialization.json.JsonPrimitive
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.buildJsonObject
import kotlinx.serialization.json.put
import org.junit.Test

class ScopedDailyNotePolicyTest {
    private fun policy() = ScopedDailyNotePolicy(version = 1, recordProfile = "apple-v11", ownerDate = "2026-03-08",
        calendarTimezone = "America/New_York", createIfMissing = false, injectSections = true)

    @Test fun policyMatchesSwiftBytesAndRejectsInvalidAuthority() {
        val encoded = DirectJson.json.encodeToJsonElement(ScopedDailyNotePolicy.serializer(), policy())
        val fixture = requireNotNull(javaClass.classLoader?.getResourceAsStream("policy.json")).use { it.readBytes() }
        assertThat(DirectJson.canonicalBytes(encoded)).isEqualTo(fixture)
        assertThat(DirectJson.json.decodeFromJsonElement(ScopedDailyNotePolicy.serializer(), encoded)).isEqualTo(policy())
        for (missing in encoded.jsonObject.keys) {
            val changed = kotlinx.serialization.json.JsonObject(encoded.jsonObject - missing)
            assertThat(runCatching { DirectJson.json.decodeFromJsonElement(ScopedDailyNotePolicy.serializer(), changed) }.isFailure).isTrue()
        }
        for ((key, value) in listOf("version" to JsonPrimitive(2), "record_profile" to JsonPrimitive("unverified"),
            "owner_date" to JsonPrimitive("2026-02-30"), "owner_date" to JsonPrimitive("0000-01-01"),
            "owner_date" to JsonPrimitive("2026-3-8"), "calendar_timezone" to JsonPrimitive("Invalid/Zone"),
            "inject_sections" to JsonPrimitive("true"), "unknown" to JsonPrimitive(true))) {
            val changed = buildJsonObject { encoded.jsonObject.forEach { (k, v) -> put(k, v) }; put(key, value) }
            assertThat(runCatching { DirectJson.json.decodeFromJsonElement(ScopedDailyNotePolicy.serializer(), changed) }.isFailure).isTrue()
        }
    }

    @Test fun negotiationRequiresBothPeersAndLegacyHelloOmitsTheExtension() {
        fun hello(versions: List<Int>?) = NegotiationHello(protocolVersions = listOf(2), platform = "android",
            installationId = "11111111-2222-4333-8444-555555555555", supportedRawProfiles = emptyList(),
            supportsDurableJobs = true, supportsCanonicalExtraction = false, transfer = TransferCapabilities(),
            scopedDailyNoteVersions = versions)
        for (local in listOf(null, emptyList(), listOf(1), listOf(2), listOf(1, 2))) {
            for (peer in listOf(null, emptyList(), listOf(1), listOf(2), listOf(1, 2))) {
                assertThat(hello(local).negotiatedScopedDailyNoteVersion(hello(peer)))
                    .isEqualTo(if (local?.contains(1) == true && peer?.contains(1) == true) 1 else null)
            }
        }
        assertThat(LegacyCodec.hello(hello(null)).decodeToString()).doesNotContain("scopedDailyNoteVersions")
        assertThat(LegacyCodec.parseHello(LegacyCodec.hello(hello(listOf(1)))).scopedDailyNoteVersions).containsExactly(1)
    }
}
