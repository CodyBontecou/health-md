package com.healthmd.domain.billing

import java.io.File
import java.util.Base64
import kotlinx.serialization.json.*
import org.junit.Assert.assertEquals
import org.junit.Test

class ClinicGrantVerifierTest {
    @Test
    fun signedAuthorityFixtures() {
        val file = generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }
            .map { File(it, "packages/contracts/clinic-sponsorship/v1/verification-fixtures.json") }
            .first { it.isFile }
        val f = Json.parseToJsonElement(file.readText()).jsonObject
        fun string(key: String) = f.getValue(key).jsonPrimitive.content
        val verifier = ClinicGrantVerifier(string("issuer"), string("audience"),
            mapOf(string("key_id") to Base64.getDecoder().decode(string("public_key_der"))))
        for (entry in f.getValue("cases").jsonArray) {
            val c = entry.jsonObject
            val actual = verifier.verify(c.getValue("token").jsonPrimitive.content,
                string("installation_id"), f.getValue("now_ms").jsonPrimitive.long)
            assertEquals(c.getValue("id").jsonPrimitive.content,
                c.getValue("expected").jsonPrimitive.boolean, actual != null)
        }
    }
}
