import android.content.Context
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.receivercoverage.*
import com.healthmd.data.scheduler.*
import com.healthmd.domain.model.*
import com.healthmd.domain.repository.EntitlementRepository
import java.nio.file.Files
import java.time.Instant
import java.time.LocalDate
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.serialization.json.*

/** Executes the production pending-window -> runtime/journal -> cancellation -> checkpoint seams.
 * Only the platform DataStore callback is an inert in-memory settings carrier. */
suspend fun legacyReceiverBoundary(context: Context, credentials: APIExportCredentialStore,
    access: EntitlementRepository, output: String) {
    val endpoint = "https://example.com/upload"
    val runtime = ReceiverCoverageRuntime(context, credentials, access)
    val config = ReceiverCoverageConfiguration("https://example.com/coverage", "scope-1", 0).json()
    fun day(s: String) = LocalDate.parse("2026-03-$s")
    fun missing(request: ReceiverCoverageRequest): ReceiverCoverageOutcome {
        val o = Json.parseToJsonElement(request.body().toString(Charsets.UTF_8)).jsonObject.toMutableMap()
        o["schema"] = JsonPrimitive("healthmd.receiver_coverage.response")
        o["completed_dates"] = JsonArray(emptyList())
        return ReceiverCoverageOutcome.Valid(ReceiverCoverageEvidence.parse(JsonObject(o).toString().toByteArray(), request))
    }
    val catchupNow = Instant.parse("2026-03-10T08:00:00Z")
    check(ReceiverCoverageRuntime.withinSelectionBounds(listOf(day("08"), day("09")), "UTC", catchupNow))
    val wide = (1L..31L).map { day("09").minusDays(31L - it) }
    check(!ReceiverCoverageRuntime.withinSelectionBounds(wide, "UTC", catchupNow))
    check(runtime.configurationForOccurrence("wide-catchup", "legacy", eligible = false) == null)
    // The absent/full decision is frozen even if a later retry has fewer remaining dates.
    check(runtime.configurationForOccurrence("wide-catchup", "legacy", eligible = true) == null)
    ReceiverCoverageRuntime.save(context, "legacy", ReceiverCoverageConfiguration.parse(config), endpoint, credentials)
    for (refresh in listOf(false, true)) {
        val a = "old-$refresh"; val b = "new-$refresh"
        check(runtime.configurationForOccurrence(a, "legacy", true) == config)
        check(runtime.configurationForOccurrence(b, "legacy", true) == config)
        val leaseA = runtime.resolve(a, "legacy:$a", config, endpoint, output, "UTC", listOf(day("08")), refresh,
            Instant.parse("2026-03-09T08:00:00Z"), query = ::missing, authorized = { true })
        if (refresh) runtime.acknowledge(leaseA, listOf(day("09")))
        val destination = runtime.destination(config, endpoint, output, "UTC")
        val wrapped = ReceiverCoverageSnapshot.wrap(output, config, a, destination.preflight.destinationBinding, destination.fingerprint)
        val settings = ScheduledExportPendingRequests.applyCancellationResult(
            ExportSettings(scheduleLookbackDays = 1, scheduleDateWindow = if (refresh)
                ScheduleDateWindow.PAST_COMPLETE_DAYS_THROUGH_TODAY else ScheduleDateWindow.PAST_COMPLETE_DAYS),
            listOf(day("08")), listOf(day("08")), target = ExportTarget.API_ENDPOINT,
            destinationFingerprint = destination.fingerprint, settingsSnapshotJson = wrapped, receiverPlanId = a)
        check(settings.pendingScheduledExportRequests.single().apiOperationId == null)
        check(ScheduledExportPendingRequests.receiverRefreshOwnedByAnotherPlan(settings, day("08"), destination.fingerprint, b))
        check(!ScheduledExportPendingRequests.receiverRefreshOwnedByAnotherPlan(settings, day("10"), destination.fingerprint, b))
        check(!ScheduledExportPendingRequests.receiverRefreshOwnedByAnotherPlan(settings, day("08"), destination.fingerprint, a))
        // This is the actual worker date builder, with the new admission's exact plan identity.
        val datesB = ScheduledExportPendingRequests.scheduledRunDates(settings, listOf(day("10")),
            destinationFingerprint = destination.fingerprint, settingsSnapshotJson = output, receiverPlanId = b)
        check(datesB == if (refresh) listOf(day("09"), day("10")) else listOf(day("09")))
        var queries = 0
        val leaseB = runtime.resolve(b, "legacy:$b", config, endpoint, output, "UTC", datesB.filter { it < day("10") }, refresh,
            Instant.parse("2026-03-10T08:00:00Z"), query = { queries++; missing(it) }, authorized = { true })
        check(queries == 1 && leaseB.plan.residual.map(LocalDate::parse) == datesB)
        check(leaseB.plan.today == "2026-03-10")
        val afterB = ScheduledExportPendingRequests.applyAttemptResult(settings, datesB, emptyList(),
            target = ExportTarget.API_ENDPOINT, destinationFingerprint = destination.fingerprint, receiverPlanId = b)
        check(afterB.pendingScheduledExportRequests.single().let { it.date == day("08") && it.receiverPlanId == a })
        val restoredA = runtime.resolve(a, "legacy:$a", config, endpoint, output, "UTC", emptyList(), false,
            Instant.parse("2026-03-10T08:00:00Z"), restoreOnly = true, authorized = { true })
        check(restoredA.plan.residual == listOf("2026-03-08") && restoredA.plan.today == "2026-03-09")
    }
    val operation = UUID.randomUUID(); val id = "cancel-before-registration"
    val configured = ReceiverCoverageConfiguration.parse(config)
    ReceiverCoverageRuntime.save(context, "legacy", configured, endpoint, credentials)
    check(runtime.configurationForOccurrence(id, "legacy", true) == config)
    ScheduledExportCancellationCoordinator.prepare(operation)
    check(ScheduledExportCancellationCoordinator.requestCancellation(operation))
    var pending = ExportSettings(); var queried = false; var admitted = false
    try {
        runtime.resolve(id, "legacy:$id", config, endpoint, output, "UTC", listOf(day("08")), true,
            Instant.parse("2026-03-10T08:00:00Z"), admit = { conservative ->
                check(runtime.hasPlan(id)) // Actual atomic file MUST precede receiver-tagged native rows.
                val destination = runtime.destination(config, endpoint, output, "UTC")
                val wrapped = ReceiverCoverageSnapshot.wrap(output, config, id, destination.preflight.destinationBinding, destination.fingerprint)
                pending = ScheduledExportPendingRequests.applyCancellationResult(pending, conservative.residual.map(LocalDate::parse),
                    conservative.residual.map(LocalDate::parse), target = ExportTarget.API_ENDPOINT, destinationFingerprint = destination.fingerprint,
                    settingsSnapshotJson = wrapped, receiverPlanId = id)
                admitted = true
            }, query = { request -> ScheduledExportCancellationCoordinator.run(operation) { queried = true; missing(request) } },
            authorized = { true })
        error("Notification cancellation ignored")
    } catch (_: CancellationException) { }
    finally { ScheduledExportCancellationCoordinator.finish(operation) }
    check(admitted && !queried && pending.pendingScheduledExportRequests.size == 2)
    val restarted = ReceiverCoverageRuntime(context, credentials, access)
    val frozenConfig = requireNotNull(restarted.configurationForOccurrence(id, "legacy", false, requireExisting = true))
    val recovered = restarted.resolve(id, "legacy:$id", frozenConfig, endpoint, output, "UTC", emptyList(), false,
        Instant.parse("2026-03-12T08:00:00Z"), restoreOnly = true,
        query = { error("Recovery queried receiver") }, authorized = { true })
    check(recovered.plan.residual == listOf("2026-03-08", "2026-03-10"))
    check(pending.pendingScheduledExportRequests.map { it.date } == recovered.plan.residual.map(LocalDate::parse))
    restarted.acknowledge(recovered, listOf(day("08")))
    check(restarted.resolve(id, "legacy:$id", frozenConfig, endpoint, output, "UTC", emptyList(), false,
        Instant.parse("2026-03-12T08:00:00Z"), restoreOnly = true, authorized = { true }).plan.residual == listOf("2026-03-10"))
    println("Actual legacy boundaries: isolated fresh-capture occurrences/Today, pre-registration cancellation and restart passed")
}
