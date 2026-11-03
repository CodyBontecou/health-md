package com.healthmd.domain.billing

import java.io.File
import java.util.Base64
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class ClinicSponsorshipSessionTest {
    private class Storage(var value: String? = null) : ClinicSponsorshipStorage {
        var fail = false
        override fun read() = value
        override fun write(value: String) { check(!fail); this.value = value }
    }

    private fun fixture(): JsonObject {
        val file = generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }
            .map { File(it, "packages/contracts/clinic-sponsorship/v1/verification-fixtures.json") }.first { it.isFile }
        return Json.parseToJsonElement(file.readText()).jsonObject
    }

    @Test
    fun consentClockRollbackRestartAndDisconnectNeverBroadenAccess() {
        val f = fixture()
        fun s(key: String) = f.getValue(key).jsonPrimitive.content
        val verifier = ClinicGrantVerifier(s("issuer"), s("audience"),
            mapOf(s("key_id") to Base64.getDecoder().decode(s("public_key_der"))))
        val token = f.getValue("cases").jsonArray.first().jsonObject.getValue("token").jsonPrimitive.content
        val storage = Storage(Json.encodeToString(ClinicSponsorshipRecord(s("installation_id"))))
        var now = 1000000L
        var session = ClinicSponsorshipSession(storage, verifier) { now }
        session.accept(token, "x".repeat(43), "Fictional clinic")
        assertEquals(ClinicExportDecision.BLOCKED_SHARING_NOT_AUTHORIZED, session.authorize("https://intake.clinic.example/upload"))
        session.setSharingAuthorized(true)
        assertEquals(ClinicExportDecision.ALLOWED_CLINIC_DESTINATION, session.authorize("https://intake.clinic.example/upload"))
        assertEquals(ClinicExportDecision.BLOCKED_DESTINATION_NOT_PERMITTED, session.authorize("https://other.example/upload"))
        session.setUploadAuthorization("Bearer synthetic-upload-token")
        assertEquals("Bearer synthetic-upload-token", session.uploadAuthorization("https://intake.clinic.example/upload"))
        assertNull(session.uploadAuthorization("https://other.example/upload"))
        session.setSharingAuthorized(false)
        assertNull(session.uploadAuthorization("https://intake.clinic.example/upload"))
        session.setSharingAuthorized(true)
        session = ClinicSponsorshipSession(storage, verifier) { now }
        assertEquals(ClinicExportDecision.ALLOWED_CLINIC_DESTINATION, session.authorize("https://intake.clinic.example/upload"))
        now = 1600000L
        assertNull(session.grant())
        now = 1000000L
        session = ClinicSponsorshipSession(storage, verifier) { now }
        assertNull(session.grant())
        session.disconnect()
        assertNull(session.refreshToken)
        assertNull(ClinicSponsorshipSession(storage, verifier) { now }.grant())
    }

    @Test
    fun corruptOrUnavailableSecureStorageCannotCreateNewIdentity() {
        val f = fixture()
        fun s(key: String) = f.getValue(key).jsonPrimitive.content
        val verifier = ClinicGrantVerifier(s("issuer"), s("audience"), emptyMap())
        assertThrows(Exception::class.java) { ClinicSponsorshipSession(Storage("corrupt"), verifier) }
        assertThrows(Exception::class.java) { ClinicSponsorshipSession(Storage().also { it.fail = true }, verifier) }
    }
}
