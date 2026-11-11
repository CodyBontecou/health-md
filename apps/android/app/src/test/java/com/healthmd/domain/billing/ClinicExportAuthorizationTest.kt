package com.healthmd.domain.billing

import java.io.File
import kotlinx.serialization.json.*
import org.junit.Assert.assertEquals
import org.junit.Test

class ClinicExportAuthorizationTest {
    private fun fixtures(): JsonObject {
        val file = generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }
            .map { File(it, "packages/contracts/clinic-sponsorship/v1/authorization-fixtures.json") }
            .first { it.isFile }
        return Json.parseToJsonElement(file.readText()).jsonObject
    }

    @Test
    fun sharedAuthorityAndDestinationCases() {
        for (entry in fixtures().getValue("cases").jsonArray) {
            val c = entry.jsonObject
            val g = c.getValue("grant").takeUnless { it is JsonNull }?.jsonObject
            val r = c.getValue("request").jsonObject
            val grant = g?.let {
                ClinicExportGrant(it.string("clinic_id")!!, it.string("destination_id")!!,
                    it.getValue("policy_version").jsonPrimitive.int, it.string("endpoint")!!,
                    it.getValue("issued_at_ms").jsonPrimitive.long,
                    it.getValue("expires_at_ms").jsonPrimitive.long,
                    it.getValue("revoked").jsonPrimitive.boolean)
            }
            val request = ClinicExportRequest(r.getValue("direct_delivery").jsonPrimitive.boolean,
                r.string("clinic_id"), r.string("destination_id"),
                r["policy_version"]?.jsonPrimitive?.intOrNull, r.string("endpoint"),
                r.getValue("sharing_authorized").jsonPrimitive.boolean)
            val decision = ClinicExportAuthorization.decide(
                c.getValue("independent_access").jsonPrimitive.boolean, grant, request,
                c.getValue("now_ms").jsonPrimitive.long)
            assertEquals(c.string("id"), c.string("expected"), decision.wireValue)
        }
    }

    @Test
    fun sharedEndpointGrammar() {
        for (entry in fixtures().getValue("endpoints").jsonArray) {
            val c = entry.jsonObject
            assertEquals(c.string("input"), c.string("expected"),
                ClinicExportAuthorization.canonicalClinicEndpoint(c.string("input")!!))
        }
    }

    private fun JsonObject.string(key: String): String? = get(key)?.jsonPrimitive?.contentOrNull
}
