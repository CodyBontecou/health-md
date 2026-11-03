package com.healthmd.domain.practice

import java.nio.file.Files
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.async
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
            java.io.RandomAccessFile(file, "rw").use { it.writeInt(99) }
            try { journal.load(request); fail("future version") } catch (_: IllegalStateException) { }
        } finally { directory.deleteRecursively() }
    }

    @Test fun concurrentCoordinatorsShareLiveSuccessAndFailure() = runBlocking {
        for (fails in listOf(false, true)) {
            val directory = Files.createTempDirectory("clinic-synthetic-").toFile().also { directories += it }
            val first = ClinicForegroundRefresh(ClinicRefreshJournal(directory), { true })
            val retry = ClinicForegroundRefresh(ClinicRefreshJournal(directory), { true })
            val release = CompletableDeferred<Unit>()
            var exports = 0; val reports = mutableListOf<ClinicRefreshRecord.State>()
            val owner = async(start = CoroutineStart.UNDISPATCHED) {
                runCatching { first.run(request, { now }, {}, {}, { check ->
                    exports++; release.await(); check()
                    check(!fails) { "synthetic_failure" }; "export_synthetic"
                }, { reports += it.state }) }
            }
            val duplicate = async(start = CoroutineStart.UNDISPATCHED) {
                runCatching { retry.run(request, { now }, {}, {}, { error("duplicate export") }, { error("duplicate report") }) }
            }
            assertTrue(reports.isEmpty()); assertFalse(duplicate.isCompleted)
            val changed = request.copy(revision = "changed_synthetic")
            assertTrue(runCatching { retry.run(changed, { now }, {}, {}, { error("changed scope") }, {}) }.isFailure)
            release.complete(Unit)
            val original = owner.await(); val joined = duplicate.await()
            assertEquals(original.getOrNull(), joined.getOrNull()); assertEquals(fails, joined.isFailure)
            assertEquals(listOf(if (fails) ClinicRefreshRecord.State.FAILED else ClinicRefreshRecord.State.UPLOADED), reports)
            assertEquals(1, exports)
        }
    }
    @Test fun revocationWhileExportSuspendsStopsPublicationAndRetry() = runBlocking {
        val journal = journal(); val release = CompletableDeferred<Unit>()
        val coordinator = ClinicForegroundRefresh(journal, { true })
        var allowed = true; var publications = 0
        val operation = async(start = CoroutineStart.UNDISPATCHED) {
            runCatching { coordinator.run(request, { now }, {}, { check(allowed) }, { authority ->
                release.await(); authority(); publications++; "unreachable"
            }, { assertEquals(ClinicRefreshRecord.State.FAILED, it.state) }) }
        }
        allowed = false; release.complete(Unit); assertTrue(operation.await().isFailure)
        val retry = coordinator.run(request, { now }, {}, {}, { error("must not retry revoked export") }, {})
        assertEquals(ClinicRefreshRecord.State.FAILED, retry.state); assertEquals(0, publications)
    }

    @Test fun currentDayOwnerScopeIsExplicitAndNeverRoundsTimestampConsent() {
        val clock = java.time.Instant.parse("2026-11-03T12:34:56Z").toEpochMilli()
        val zone = java.time.ZoneId.of("UTC"); val date = java.time.LocalDate.parse("2026-11-03")
        val start = date.atStartOfDay(zone).toInstant().toEpochMilli()
        val end = date.plusDays(1).atStartOfDay(zone).toInstant().toEpochMilli()
        val approved = request.copy(startMillis = start, endMillis = end, expiresAtMillis = clock + 300_000, ownerDayZone = zone.id)
        assertEquals(listOf(date), approved.ownerDates(zone, clock))
        assertTrue(runCatching { approved.copy(ownerDayZone = null).validate(clock) }.isFailure)
        val exact = approved.copy(ownerDayZone = null, endMillis = clock)
        exact.validate(clock)
        assertTrue(runCatching { exact.ownerDates(zone, clock) }.isFailure)
        assertTrue(runCatching { approved.ownerDates(java.time.ZoneId.of("America/New_York"), clock) }.isFailure)
        assertTrue(runCatching { approved.copy(endMillis = end + 86_400_000).validate(clock) }.isFailure)
        val journal = journal(); journal.save(ClinicRefreshRecord(approved, ClinicRefreshRecord.State.REQUESTED))
        assertEquals(approved, journal.load(approved)?.request)
        assertTrue(runCatching { journal.load(approved.copy(ownerDayZone = "GMT")) }.isFailure)
    }
    @Test fun ownerDayScopeKeepsDSTBoundary() {
        val start = java.time.Instant.parse("2026-11-01T04:00:00Z").toEpochMilli()
        val end = java.time.Instant.parse("2026-11-02T05:00:00Z").toEpochMilli()
        val clock = java.time.Instant.parse("2026-11-01T17:00:00Z").toEpochMilli()
        val approved = request.copy(startMillis = start, endMillis = end, expiresAtMillis = clock + 300_000, ownerDayZone = "America/New_York")
        assertEquals(listOf(java.time.LocalDate.parse("2026-11-01")), approved.ownerDates(java.time.ZoneId.of(approved.ownerDayZone), clock))
        assertEquals(25 * 3_600_000L, end - start)
    }

    @Test fun versionOneTimestampJournalIsReadWithoutLosingTerminalEvidence() {
        val directory = Files.createTempDirectory("clinic-synthetic-").toFile().also { directories += it }
        val journal = ClinicRefreshJournal(directory)
        journal.save(ClinicRefreshRecord(request, ClinicRefreshRecord.State.UPLOADED, "export_synthetic", now))
        val file = directory.listFiles()!!.single()
        val bytes = file.readBytes()
        val input = java.io.DataInputStream(bytes.inputStream())
        input.readInt(); repeat(6) { input.readUTF() }; repeat(3) { input.readLong() }
        val zoneOffset = bytes.size - input.available()
        assertEquals("", input.readUTF())
        val legacy = bytes.copyOfRange(0, zoneOffset) + bytes.copyOfRange(zoneOffset + 2, bytes.size)
        java.nio.ByteBuffer.wrap(legacy).putInt(1); file.writeBytes(legacy)
        val restored = journal.load(request)
        assertEquals(ClinicRefreshRecord.State.UPLOADED, restored?.state)
        assertEquals("export_synthetic", restored?.exportId); assertNull(restored?.request?.ownerDayZone)
    }

}
