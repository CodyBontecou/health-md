package com.healthmd.domain.billing

import com.healthmd.data.billing.*
import java.io.File
import java.util.Base64
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.*
import org.junit.Assert.*
import org.junit.Test

class ClinicSponsorshipRecoveryTest {
    private class Storage(var value: String) : ClinicSponsorshipStorage {
        var fail = false
        override fun read() = value
        override fun write(value: String) { check(!fail); this.value = value }
    }
    private fun fixture(): JsonObject = Json.parseToJsonElement(generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }
        .map { File(it,"packages/contracts/clinic-sponsorship/v1/verification-fixtures.json") }.first { it.isFile }.readText()).jsonObject

    @Test fun lostResponseAndFailedSecureCommitRecoverAfterRestartWithoutNewInvitationOrConsent() = runTest {
        val f=fixture()
        fun text(key: String)=f.getValue(key).jsonPrimitive.content
        val storage=Storage(Json.encodeToString(ClinicSponsorshipRecord(text("installation_id"))))
        val config=ClinicLicensingConfiguration("https://licensing.clinic.example/",text("issuer"),text("audience"),
            mapOf(text("key_id") to Base64.getDecoder().decode(text("public_key_der"))))
        val token=f.getValue("cases").jsonArray.first().jsonObject.getValue("token").jsonPrimitive.content
        var calls=0
        var originalSecret: String?=null
        val api=object: ClinicLicensingAPI {
            override suspend fun redeem(code: String, installationID: String, enrollmentSecret: String): ClinicLicensingReply {
                val pending=Json.decodeFromString<ClinicSponsorshipRecord>(storage.value).pendingEnrollment!!
                assertEquals(pending.enrollmentSecret,enrollmentSecret)
                assertEquals(pending.invitationCode,code)
                if(originalSecret==null) originalSecret=enrollmentSecret else assertEquals(originalSecret,enrollmentSecret)
                calls++
                if(calls==1) throw java.io.IOException("synthetic lost response")
                if(calls==2) storage.fail=true
                return ClinicLicensingReply(token,"Synthetic clinic","synthetic-membership")
            }
            override suspend fun refresh(token: String,installationID: String): ClinicLicensingReply = error("Pending enrollment must redeem, not refresh")
            override suspend fun disconnect(token: String,installationID: String) {}
        }
        val first=ClinicSponsorshipManager(storage,config,api,backgroundScope) { 1000000 }
        try { first.enroll("c".repeat(43));fail("Expected lost response") } catch (_: java.io.IOException) {}
        assertTrue(first.status.value.enrollmentPending)
        assertFalse(first.status.value.active)
        try { first.resumeEnrollment();fail("Expected secure storage failure") } catch (_: IllegalStateException) {}
        assertNotNull(Json.decodeFromString<ClinicSponsorshipRecord>(storage.value).pendingEnrollment)
        storage.fail=false
        val restarted=ClinicSponsorshipManager(storage,config,api,backgroundScope) { 1000000 }
        restarted.refresh()
        assertEquals(3,calls)
        assertTrue(restarted.status.value.active)
        assertFalse(restarted.status.value.enrollmentPending)
        assertFalse(restarted.status.value.sharingAuthorized)
        val record=Json.decodeFromString<ClinicSponsorshipRecord>(storage.value)
        assertEquals(originalSecret,record.refreshToken)
        assertNull(record.pendingEnrollment)
    }

    @Test fun pendingEnrollmentIsDurableBeforeTransmissionAndDisconnectForgetsIt() {
        val f=fixture()
        val storage=Storage(Json.encodeToString(ClinicSponsorshipRecord(f.getValue("installation_id").jsonPrimitive.content)))
        val session=ClinicSponsorshipSession(storage,ClinicGrantVerifier("issuer","audience",emptyMap())) { 1000000 }
        storage.fail=true
        assertThrows(Exception::class.java) {session.beginEnrollment("c".repeat(43))}
        assertNull(session.pendingEnrollment)
        storage.fail=false
        val pending=session.beginEnrollment("c".repeat(43))
        assertEquals(43,pending.enrollmentSecret.length)
        assertEquals(pending,session.beginEnrollment("c".repeat(43)))
        assertThrows(Exception::class.java) {session.beginEnrollment("d".repeat(43))}
        session.disconnect()
        assertNull(session.pendingEnrollment)
        assertNull(Json.decodeFromString<ClinicSponsorshipRecord>(storage.value).pendingEnrollment)
    }
    @Test fun definitiveDenialClearsPendingProofButTransientFailureRetainsIt() = runTest {
        val f=fixture()
        fun text(key: String)=f.getValue(key).jsonPrimitive.content
        for (inactive in listOf(false, true)) {
            val storage=Storage(Json.encodeToString(ClinicSponsorshipRecord(text("installation_id"))))
            val config=ClinicLicensingConfiguration("https://licensing.clinic.example/",text("issuer"),text("audience"),
                mapOf(text("key_id") to Base64.getDecoder().decode(text("public_key_der"))))
            val api=object: ClinicLicensingAPI {
                override suspend fun redeem(code: String, installationID: String, enrollmentSecret: String): ClinicLicensingReply =
                    throw ClinicLicensingException(inactive)
                override suspend fun refresh(token: String, installationID: String): ClinicLicensingReply = error("unexpected refresh")
                override suspend fun disconnect(token: String, installationID: String) {}
            }
            val manager=ClinicSponsorshipManager(storage,config,api,backgroundScope) { 1000000 }
            try { manager.enroll("c".repeat(43)); fail("Expected denial") } catch (_: ClinicLicensingException) {}
            assertEquals(!inactive, manager.status.value.enrollmentPending)
            assertEquals(!inactive, Json.decodeFromString<ClinicSponsorshipRecord>(storage.value).pendingEnrollment != null)
            assertFalse(manager.status.value.active)
        }
    }

    @Test fun disconnectWhileRedemptionIsInFlightCannotRestoreMembershipOrConsent() = runTest {
        val f=fixture()
        fun text(key: String)=f.getValue(key).jsonPrimitive.content
        val storage=Storage(Json.encodeToString(ClinicSponsorshipRecord(text("installation_id"))))
        val config=ClinicLicensingConfiguration("https://licensing.clinic.example/",text("issuer"),text("audience"),
            mapOf(text("key_id") to Base64.getDecoder().decode(text("public_key_der"))))
        val token=f.getValue("cases").jsonArray.first().jsonObject.getValue("token").jsonPrimitive.content
        val started=kotlinx.coroutines.CompletableDeferred<Unit>()
        val release=kotlinx.coroutines.CompletableDeferred<Unit>()
        var revokedProof: String?=null
        val api=object: ClinicLicensingAPI {
            override suspend fun redeem(code: String, installationID: String, enrollmentSecret: String): ClinicLicensingReply {
                started.complete(Unit); release.await()
                return ClinicLicensingReply(token,"Synthetic clinic","synthetic-membership")
            }
            override suspend fun refresh(token: String, installationID: String): ClinicLicensingReply = error("unexpected refresh")
            override suspend fun disconnect(token: String, installationID: String) { revokedProof=token }
        }
        val manager=ClinicSponsorshipManager(storage,config,api,backgroundScope) { 1000000 }
        val enrollment=backgroundScope.launch {
            try { manager.enroll("c".repeat(43)); fail("A late response must not restore access") }
            catch (_: IllegalStateException) {}
        }
        started.await()
        val proof=Json.decodeFromString<ClinicSponsorshipRecord>(storage.value).pendingEnrollment!!.enrollmentSecret
        manager.disconnect(); release.complete(Unit); enrollment.join()
        assertEquals(proof, revokedProof)
        assertFalse(manager.status.value.active)
        assertFalse(manager.status.value.enrollmentPending)
        assertFalse(manager.status.value.sharingAuthorized)
        val restarted=ClinicSponsorshipManager(storage,config,api,backgroundScope) { 1000000 }
        assertFalse(restarted.status.value.active)
        assertNull(Json.decodeFromString<ClinicSponsorshipRecord>(storage.value).refreshToken)
    }

}
