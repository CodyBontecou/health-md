package com.healthmd.domain.practice

import java.nio.file.Files
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test
import org.junit.After

class ClinicRefreshTest {
    private val now = 1_000_000_000L
    private val request = ClinicRefreshRequest("request_synthetic", "subject_synthetic", "device_synthetic", "connection_synthetic",
        "profile_synthetic", "revision_synthetic", now - 172_800_000, now - 86_400_000, now + 300_000)
    private val directories = mutableListOf<java.io.File>()
    private fun journal() = ClinicRefreshJournal(Files.createTempDirectory("clinic-synthetic-").toFile().also { directories += it })
    @After fun cleanup() { directories.forEach { it.deleteRecursively() } }

    @Test fun disabledGateNeverExports() = runBlocking {
        var exports = 0
        try { ClinicForegroundRefresh(journal(), { false }).run(request, { now }, {}, {}, { exports++; "export_synthetic" }, {})
            fail("disabled") } catch (_: IllegalStateException) { }
        assertEquals(0, exports)
    }
    @Test fun receiptSurvivesRestartAndAcknowledgmentLossWithoutReexport() = runBlocking {
        val directory = Files.createTempDirectory("clinic-synthetic-").toFile()
        try {
            var exports = 0; var permission = true
            val first = ClinicForegroundRefresh(ClinicRefreshJournal(directory), { true })
            try { first.run(request, { now }, {}, { check(permission) }, { exports++; it(); "export_synthetic" }, { error("offline") })
                fail("offline") } catch (_: IllegalStateException) { }
            permission = false
            val replay = ClinicForegroundRefresh(ClinicRefreshJournal(directory), { true }).run(request, { now + 400_000 }, {},
                { error("must not ask for Health access to acknowledge") }, { error("must not reexport") }, {})
            assertEquals(ClinicRefreshRecord.State.UPLOADED, replay.state); assertEquals("export_synthetic", replay.exportId)
            assertEquals(1, exports)
        } finally { directory.deleteRecursively() }
    }
    @Test fun interruptedRequestIsTerminal() = runBlocking {
        val journal = journal(); journal.reserve(request)
        val result = ClinicForegroundRefresh(journal, { true }).run(request, { now }, {}, {}, { error("must not export") }, {})
        assertEquals(ClinicRefreshRecord.State.FAILED, result.state)
    }
    @Test fun wrongProfileOrDestinationRevisionCannotReuseRequestId() {
        val journal = journal(); journal.reserve(request)
        for (changed in listOf(request.copy(profileId = "other_synthetic"), request.copy(revision = "other_synthetic"), request.copy(endMillis = now))) {
            try { journal.load(changed); fail("changed scope") } catch (_: IllegalStateException) { }
        }
    }
    @Test fun cancellationBeforePublicationPersistsFailure() = runBlocking {
        val journal = journal(); var allowed = true
        try { ClinicForegroundRefresh(journal, { true }).run(request, { now }, {}, { check(allowed) }, {
                allowed = false; it(); "unreachable"
            }, {}); fail("revoked") } catch (_: IllegalStateException) { }
        assertEquals(ClinicRefreshRecord.State.FAILED, journal.load(request)?.state)
    }
    @Test fun corruptionNeverLooksLikeANewRequest() {
        val directory = Files.createTempDirectory("clinic-synthetic-").toFile()
        try {
            val journal = ClinicRefreshJournal(directory); journal.reserve(request)
            directory.listFiles()!!.single().writeText("corrupt_synthetic")
            try { journal.load(request); fail("corrupt") } catch (_: IllegalStateException) { }
            try { journal.reserve(request); fail("corrupt") } catch (_: IllegalStateException) { }
        } finally { directory.deleteRecursively() }
    }
    @Test fun malformedExpiredAndFutureScopesFailBeforeExport() = runBlocking {
        for (invalid in listOf(request.copy(expiresAtMillis = now), request.copy(startMillis = now), request.copy(endMillis = now + 1))) {
            try { ClinicForegroundRefresh(journal(), { true }).run(invalid, { now }, {}, {}, { error("must not export") }, {})
                fail("invalid") } catch (_: IllegalArgumentException) { }
        }
    }
    @Test fun deniedHealthGateLeavesDurablePendingRequest() = runBlocking {
        val journal = journal()
        try { ClinicForegroundRefresh(journal, { true }).run(request, { now }, {}, { error("locked") },
            { error("must not export") }, {}); fail("locked") } catch (_: IllegalStateException) { }
        assertEquals(ClinicRefreshRecord.State.REQUESTED, journal.load(request)?.state)
    }
    @Test fun clinicPaymentGateDefaultsClosedWhileConsumerAccessRemainsIndependent() {
        val gates = ClinicExportGates(request.subjectId, request.deviceId, request.connectionId, true, true, true, false, true)
        try { gates.requireFor(request); fail("store route") } catch (_: IllegalStateException) { }
        gates.copy(consumerAllowsExport = true).requireFor(request)
        try { gates.copy(consumerAllowsExport = true, sharingConsent = false).requireFor(request); fail("consent") }
        catch (_: IllegalStateException) { }
    }

    @Test fun unknownStorageVersionFailsClosed() {
        val directory = Files.createTempDirectory("clinic-synthetic-").toFile()
        try {
            val journal = ClinicRefreshJournal(directory); journal.reserve(request)
            val file = directory.listFiles()!!.single()
            java.io.RandomAccessFile(file, "rw").use { it.writeInt(2) }
            try { journal.load(request); fail("future version") } catch (_: IllegalStateException) { }
        } finally { directory.deleteRecursively() }
    }

}
