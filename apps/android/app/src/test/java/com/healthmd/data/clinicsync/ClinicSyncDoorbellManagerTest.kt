package com.healthmd.data.clinicsync

import com.healthmd.data.billing.ClinicSponsorshipStatus
import java.io.File
import java.security.MessageDigest
import java.util.Base64
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ClinicSyncDoorbellManagerTest {
    private val endpoint = "https://intake.clinic.example/upload"
    private var status = ClinicSponsorshipStatus(configured = true, active = true, clinicName = "Example clinic",
        endpoint = endpoint, sharingAuthorized = true)

    private class Storage : ClinicSyncDoorbellStorage {
        var doorbell: ClinicSyncDoorbell? = null
        override fun load() = doorbell
        override fun save(doorbell: ClinicSyncDoorbell) { this.doorbell = doorbell }
        override fun clear() { doorbell = null }
        override var pendingRevocation: String? = null
        override val wakeUserId = "wake-user-0123456789"
    }

    private class Wake : ClinicSyncWakeService {
        val registrations = mutableListOf<Triple<String, String, String?>>()
        val unregistered = mutableListOf<String>()
        var failUnregister = false
        override suspend fun register(userId: String, fcmToken: String, verificationHash: String, existingWakeId: String?): String {
            registrations += Triple(fcmToken, verificationHash, existingWakeId)
            return existingWakeId ?: "wake-0123456789abcdef"
        }
        override suspend fun unregister(userId: String, wakeId: String) {
            if (failUnregister) throw java.io.IOException("offline")
            unregistered += wakeId
        }
    }

    private class Sender : ClinicSyncControlSender {
        val sent = mutableListOf<Pair<String, JsonObject>>()
        var fail = false
        override suspend fun send(endpoint: String, body: String) {
            if (fail) throw java.io.IOException("unreachable")
            sent += endpoint to Json.parseToJsonElement(body).jsonObject
        }
    }

    private class Push(var token: String? = "fcm-token-1", override val available: Boolean = true) : ClinicSyncPushTransport {
        override suspend fun token() = token
    }

    private class Notifier(var allowed: Boolean = true) : ClinicSyncNotifier {
        val requests = mutableListOf<String>()
        val results = mutableListOf<ClinicSyncExportResult>()
        override fun canPostNotifications() = allowed
        override fun postRequest(wakeId: String) { requests += wakeId }
        override fun postResult(result: ClinicSyncExportResult) { results += result }
    }

    private val storage = Storage()
    private val wake = Wake()
    private val sender = Sender()
    private val push = Push()
    private val notifier = Notifier()
    private val exports = mutableListOf<String>()

    private fun manager(available: Boolean = true) = ClinicSyncDoorbellManager(
        { status }, storage, wake, sender, if (available) push else Push(available = false),
        object : ClinicSyncExportLauncher {
            override suspend fun exportClinicProfile(endpoint: String): ClinicSyncExportResult {
                exports += endpoint
                return ClinicSyncExportResult.SENT
            }
        }, notifier,
        { ByteArray(32) { 9 } },
    )

    private fun fixture(): JsonObject = Json.parseToJsonElement(
        generateSequence(File(requireNotNull(System.getProperty("user.dir")))) { it.parentFile }
            .map { File(it, "packages/contracts/clinic-sponsorship/v1/sync-doorbell-fixtures.json") }
            .first { it.isFile }.readText(),
    ).jsonObject

    @Test fun enableRequiresSharingAndContactsNothing() = runTest {
        status = status.copy(sharingAuthorized = false)
        val manager = manager()
        manager.enable()
        assertEquals(ClinicSyncState.Unavailable(ClinicSyncState.Reason.SHARING_REQUIRED), manager.state.value)
        assertTrue(wake.registrations.isEmpty())
        assertTrue(sender.sent.isEmpty())
    }

    @Test fun unavailablePushOrDeniedNotificationsNeverRegister() = runTest {
        manager(available = false).enable()
        notifier.allowed = false
        manager().enable()
        assertTrue(wake.registrations.isEmpty())
        assertNull(storage.doorbell)
    }

    @Test fun enableRegistersHashAndDeliversKeyOnlyToTheClinicEndpoint() = runTest {
        val manager = manager()
        manager.enable()
        assertEquals(ClinicSyncState.Enabled, manager.state.value)
        val doorbell = storage.doorbell!!
        assertEquals(endpoint, doorbell.endpoint)
        assertEquals("fcm-token-1", doorbell.deviceToken)
        val expectedHash = MessageDigest.getInstance("SHA-256").digest(ByteArray(32) { 9 })
            .joinToString("") { "%02x".format(it) }
        assertEquals(Triple("fcm-token-1", expectedHash, null), wake.registrations.single())
        val (sentTo, body) = sender.sent.single()
        assertEquals(endpoint, sentTo)
        assertEquals("enroll", body.getValue("action").jsonPrimitive.content)
        assertEquals(doorbell.wakeKey, body.getValue("wakeKey").jsonPrimitive.content)
    }

    @Test fun unreachableClinicLeavesNoDoorbellBehind() = runTest {
        sender.fail = true
        val manager = manager()
        manager.enable()
        assertEquals(listOf("wake-0123456789abcdef"), wake.unregistered)
        assertNull(storage.doorbell)
        assertEquals(ClinicSyncState.Unavailable(ClinicSyncState.Reason.CLINIC_UNREACHABLE), manager.state.value)
    }

    @Test fun changedBindingRevokesAndRetriesAFailedRevocation() = runTest {
        val manager = manager()
        manager.enable()
        wake.failUnregister = true
        manager.reconcile(status.copy(endpoint = "https://other.clinic.example/upload"))
        assertNull(storage.doorbell)
        assertEquals("wake-0123456789abcdef", storage.pendingRevocation)
        assertEquals("revoke", sender.sent.last().second.getValue("action").jsonPrimitive.content)
        assertFalse(sender.sent.last().second.containsKey("wakeKey"))

        wake.failUnregister = false
        manager.reconcile()
        assertEquals(listOf("wake-0123456789abcdef"), wake.unregistered)
        assertNull(storage.pendingRevocation)
    }

    @Test fun tokenRotationReRegistersTheSameDoorbellWithoutResendingTheKey() = runTest {
        val manager = manager()
        manager.enable()
        push.token = "fcm-token-2"
        manager.reconcile()
        assertEquals("wake-0123456789abcdef", wake.registrations.last().third)
        assertEquals("fcm-token-2", storage.doorbell!!.deviceToken)
        assertEquals(1, sender.sent.size)
    }

    @Test fun onlyTheHeldDoorbellNotifiesAndExports() = runTest {
        val manager = manager()
        manager.enable()
        manager.onSyncRequestReceived("someone-elses-doorbell")
        manager.handleSyncRequestTap("someone-elses-doorbell")
        assertTrue(notifier.requests.isEmpty())
        assertTrue(exports.isEmpty())

        manager.onSyncRequestReceived("wake-0123456789abcdef")
        manager.handleSyncRequestTap("wake-0123456789abcdef")
        assertEquals(listOf("wake-0123456789abcdef"), notifier.requests)
        assertEquals(listOf(endpoint), exports)
        assertEquals(listOf(ClinicSyncExportResult.SENT), notifier.results)
    }

    @Test fun tapAfterSharingWasRevokedSendsNothing() = runTest {
        val manager = manager()
        manager.enable()
        status = status.copy(sharingAuthorized = false)
        manager.handleSyncRequestTap("wake-0123456789abcdef")
        assertTrue(exports.isEmpty())
        assertNull(storage.doorbell)
    }

    @Test fun messagesAndPushDataMatchTheSharedContractFixture() {
        val f = fixture()
        val enroll = f.getValue("enrollMessage").jsonObject.getValue("body").jsonObject
        val revoke = f.getValue("revokeMessage").jsonObject.getValue("body").jsonObject
        val wakeId = enroll.getValue("wakeId").jsonPrimitive.content
        val key = ClinicSyncDoorbellMessages.base64url(ByteArray(32) { 9 })
        assertEquals(enroll, Json.parseToJsonElement(ClinicSyncDoorbellMessages.enroll(wakeId, key)))
        assertEquals(revoke, Json.parseToJsonElement(ClinicSyncDoorbellMessages.revoke(wakeId)))
        assertEquals(f.getValue("wakeRequest").jsonObject.getValue("wakeKeyVerificationHash").jsonPrimitive.content,
            ClinicSyncDoorbellMessages.verificationHash(key))
        val data = f.getValue("notification").jsonObject.getValue("fcmData").jsonObject
            .mapValues { it.value.jsonPrimitive.content }
        assertEquals(wakeId, ClinicSyncDoorbellMessages.requestedWakeId(data))
        assertNull(ClinicSyncDoorbellMessages.requestedWakeId(mapOf("kind" to "other", "wakeId" to wakeId)))
        assertEquals(key, Base64.getUrlEncoder().withoutPadding().encodeToString(ByteArray(32) { 9 }))
    }
}
