package com.healthmd.effecthostcandidate

import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test

class NativeProbeAdmissionTest {
    private fun valid() = JSONObject().put("schema", "healthmd.candidate_host_probe").put("version", 1)
        .put("case_id", "queue_backpressure").put("sequence", 0)
    @Test fun exactMultibyteBoundaryAndMalformedSurrogate() {
        assertEquals("frame_limit", ProbeAdmission.rejectFrame("é".repeat(32768) + "a"))
        assertEquals("schema_invalid", ProbeAdmission.rejectFrame("é".repeat(32768)))
        assertEquals("schema_invalid", ProbeAdmission.rejectFrame("\uD800"))
        assertEquals("schema_invalid", ProbeAdmission.rejectFrame("\uDC00"))
    }
    @Test fun strictTypesKeysAndSchemaBeforeAcquisition() {
        assertNull(ProbeAdmission.rejectFrame(valid().toString()))
        val invalid = listOf(valid().put("version", true), valid().put("sequence", false), valid().put("version", "1"),
            valid().put("sequence", "0"), valid().put("sequence", 0.5), valid().put("version", 1.5),
            valid().put("schema", 1), valid().put("case_id", true), valid().put("payload", "untrusted"),
            valid().put("schema", "wrong"), valid().put("version", 2), valid().put("sequence", 1))
        for (frame in invalid) assertEquals("schema_invalid", ProbeAdmission.rejectFrame(frame.toString()))
        for (frame in listOf("{", "[]", "null", "true", "1")) assertEquals("schema_invalid", ProbeAdmission.rejectFrame(frame))
        assertEquals("schema_invalid", ProbeAdmission.rejectFrame(valid().toString() + "{}"))
        assertEquals("schema_invalid", ProbeAdmission.rejectFrame(valid().toString().replace('"', '\'')))
    }
    @Test fun rawPrecisionAndExponentVectorsRejectBeforeAnyConversion() {
        val prefix = "{\"schema\":\"healthmd.candidate_host_probe\",\"case_id\":\"queue_backpressure\","
        for (suffix in listOf("\"version\":1,\"sequence\":1e-999}",
            "\"version\":1.00000000000000000001,\"sequence\":0}",
            "\"version\":1e999999999999999999999,\"sequence\":0}",
            "\"version\":1.0,\"sequence\":0}", "\"version\":1,\"sequence\":0.0}")) {
            assertEquals("schema_invalid", ProbeAdmission.rejectFrame(prefix + suffix))
        }
        // These literal raw tokens are independently specified by the private fixture profile.
        assertNull(ProbeAdmission.rejectFrame(prefix + "\"version\":1,\"sequence\":0}"))
    }
    @Test fun unknownDuplicateAndEscapedEquivalentKeysReject() {
        val canonical = "{\"schema\":\"healthmd.candidate_host_probe\",\"version\":1,\"case_id\":\"queue_backpressure\",\"sequence\":0}"
        assertEquals("schema_invalid", ProbeAdmission.rejectFrame(canonical.replace("\"schema\"", "\"\\u0073chema\"")))
        assertEquals("schema_invalid", ProbeAdmission.rejectFrame(canonical.replace("\"sequence\":0", "\"version\":1")))
        assertEquals("schema_invalid", ProbeAdmission.rejectFrame(canonical.dropLast(1) + ",\"\\u0073chema\":\"healthmd.candidate_host_probe\"}"))
    }
    @Test fun boundedLongestStringIncompleteEscapeAndGiantPrimitive() {
        val prefix = "{\"schema\":\""
        val suffix = "\",\"version\":1,\"case_id\":\"queue_backpressure\",\"sequence\":0}"
        val longest = prefix + "x".repeat(65536 - prefix.length - suffix.length) + suffix
        assertEquals(65536, longest.length)
        assertEquals("schema_invalid", ProbeAdmission.rejectFrame(longest))
        val incomplete = prefix + "x".repeat(65536 - prefix.length - 1) + "\\"
        assertEquals(65536, incomplete.length)
        assertEquals("schema_invalid", ProbeAdmission.rejectFrame(incomplete))
        assertEquals("frame_limit", ProbeAdmission.rejectFrame("1".repeat(1_000_000)))
    }
}
