package com.healthmd.receiverqa

import android.os.Bundle
import android.widget.Button
import android.widget.LinearLayout
import android.widget.ScrollView
import android.widget.TextView
import androidx.activity.ComponentActivity
import androidx.work.WorkInfo
import androidx.work.WorkManager
import com.healthmd.BuildConfig
import com.healthmd.R
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.receivercoverage.ReceiverCoverageConfiguration
import com.healthmd.data.scheduler.*
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.domain.model.*
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.AndroidEntryPoint
import java.nio.file.Files
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.util.UUID
import javax.inject.Inject
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.first
import kotlinx.serialization.json.*

/** E2E-only controller. It delivers real armed occurrences; it never manufactures admission,
 * selection, ACKs, pending rows or journal bytes. Only the SDK source and receiver are synthetic.
 *
 * Emulator only: `./gradlew :app:installFdroidE2e`, then
 * `adb shell am start -n com.healthmd.android.e2e/com.healthmd.receiverqa.ReceiverCoverageQaActivity`.
 * The `*_partial` cases need a batching API engine, because the default `legacy` engine sends one
 * all-or-nothing request and can never be partially acknowledged. Build them with
 * `-PEXPORT_ENGINE_API_V1_FROZEN_V4=shadow` (or `rust`). */
@AndroidEntryPoint
class ReceiverCoverageQaActivity : ComponentActivity() {
    @Inject lateinit var settings: SettingsRepository
    @Inject lateinit var sourceRegistry: com.healthmd.data.health.HealthProviderRegistry
    @Inject lateinit var credentials: APIExportCredentialStore
    @Inject lateinit var history: ExportHistoryRepository
    @Inject lateinit var scheduler: ExportScheduler
    @Inject lateinit var stateStore: ScheduledExportStateStore
    @Inject lateinit var recovery: ScheduledExportRecoveryManager
    @Inject lateinit var profiles: ExportProfileRepository
    @Inject lateinit var entries: ScheduledProfileEntryStore
    @Inject lateinit var profileScheduler: ScheduledProfileScheduler
    @Inject lateinit var snapshots: ScheduledProfileSnapshotFactory
    @Inject lateinit var workManager: WorkManager
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main.immediate)
    private lateinit var output: TextView
    private lateinit var state: ReceiverQaState
    private var running = false
    /** Last state seen for every fixture-tracked request. WorkManager deletes a finished request
     * when a later alarm enqueues the same unique work, so final evidence uses what was observed. */
    private val observedStates = mutableMapOf<UUID, WorkInfo.State>()
    companion object {
        private var receiver: LocalReceiver? = null
        private val cases = listOf("legacy_success", "profile_success", "legacy_empty", "profile_empty", "profile_today",
            "legacy_partial", "profile_partial", "legacy_wide_window", "legacy_today", "legacy_cancel", "profile_cancel",
            "legacy_rebound", "profile_rebound")
    }
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        check(packageName.endsWith(".e2e") && BuildConfig.DISTRIBUTION_CHANNEL == "fdroid")
        check(android.os.Build.HARDWARE in listOf("ranchu", "goldfish") || android.os.Build.FINGERPRINT.contains("generic")) {
            "Receiver QA is emulator-only"
        }
        state = ReceiverQaState(this)
        output = TextView(this).apply { id = R.id.receiver_qa_status; text = "QA READY synthetic receiver only" }
        val layout = LinearLayout(this).apply { orientation = LinearLayout.VERTICAL; addView(output) }
        for (case in cases) layout.addView(Button(this).apply {
            text = case; setOnClickListener { execute(case) }
        })
        setContentView(ScrollView(this).apply { addView(layout) })
    }
    private fun execute(case: String) {
        if (running) return
        running = true
        output.text = "QA RUNNING $case"
        scope.launch {
            try {
                val result = withContext(Dispatchers.IO) { runCase(case) }
                output.text = "QA PASS $case\n$result"
            } catch (error: Exception) {
                output.text = "QA FAIL $case\n${error.javaClass.simpleName}: ${error.message}"
            } finally { running = false }
        }
    }
    private suspend fun runCase(case: String): String = withTimeout(120_000) {
        require(case in cases)
        if (case.endsWith("_partial")) {
            check(BuildConfig.EXPORT_ENGINE_API_V1_FROZEN_V4 != "legacy") {
                "Partial ACK needs batched uploads: rebuild with -PEXPORT_ENGINE_API_V1_FROZEN_V4=shadow"
            }
        }
        synchronized(observedStates) { observedStates.clear() }
        check(profiles.getProfiles().all { it.name.startsWith("Receiver QA") }) { "Fixture refuses non-QA profiles" }
        scheduler.cancel()
        for (entry in entries.getEntries()) profileScheduler.removeEntry(entry.profileId)
        workManager.cancelAllWork().result.get(10, java.util.concurrent.TimeUnit.SECONDS)
        awaitCondition { workManager.getWorkInfosByTag(ExportScheduler.EXPORT_OCCURRENCE_TAG).get(10, java.util.concurrent.TimeUnit.SECONDS).none { it.state == WorkInfo.State.RUNNING } }
        history.clearAll()
        state.reset()
        if (receiver == null) receiver = LocalReceiver(applicationContext).also { it.start() }
        val endpoint = requireNotNull(receiver).endpoint
        val profileMode = case.startsWith("profile_")
        val wide = case == "legacy_wide_window"
        val partial = case.endsWith("_partial")
        val cancelled = case.endsWith("_cancel")
        val empty = case.endsWith("_empty")
        val today = case.endsWith("_today")
        // The scope is already bound to another output profile (an app update changed the engine
        // pin, a provider reconnected, ...). A new occurrence must run the full lookback, not stall.
        val rebound = case.endsWith("_rebound")
        val lookback = if (wide) 31 else if (partial) 30 else 3
        state.update(mapOf("coverage_mode" to if (empty || today) "all" else if (partial) "holes" else "one_hole",
            "fail_upload_after" to if (partial) "1" else "disabled", "case" to case))
        settings.setPurchased(true)
        settings.setOnboardingCompleted(true)
        settings.setSelectedHealthProviderId("receiver_qa")
        check(settings.getSelectedHealthProviderId() == "receiver_qa" &&
            sourceRegistry.providerFor("receiver_qa") is SyntheticReceiverProvider) {
            "Synthetic SDK source must be selected before admitting any work"
        }
        settings.setSleepDayAttribution(SleepDayAttribution.NIGHT_BEGINS)
        credentials.saveAuthorization("receiver-coverage-synthetic")
        val now = Instant.now().atZone(ZoneId.systemDefault())
        val configured = settings.updateExportSettingsAtomically {
            ExportSettings(exportTarget = ExportTarget.API_ENDPOINT, scheduledExportTarget = ExportTarget.API_ENDPOINT,
                apiEndpointUrl = endpoint, exportFormat = ExportFormat.JSON, exportFormats = setOf(ExportFormat.JSON),
                scheduleEnabled = !profileMode, scheduleCadenceValue = 1, scheduleCadenceUnit = ScheduleCadenceUnit.MINUTES,
                scheduleHour = now.hour, scheduleMinute = now.minute, scheduleLookbackDays = lookback,
                scheduleDateWindow = if (today && !profileMode) ScheduleDateWindow.PAST_COMPLETE_DAYS_THROUGH_TODAY
                    else ScheduleDateWindow.PAST_COMPLETE_DAYS,
                pendingScheduledExportRequests = emptyList(), pendingScheduledRetryDates = emptyList())
        }
        val config = ReceiverCoverageConfiguration(endpoint.replace("/upload", "/coverage"), "qa-${UUID.randomUUID()}", 0)
        val previousPlans = planFiles().keys
        val workIdsBefore = allWork().map { it.id }.toSet()
        var profileId: String? = null
        if (profileMode) {
            val template = ExportProfile("template", "Receiver QA", "", ExportTarget.API_ENDPOINT,
                apiEndpointUrl = endpoint, createdAtEpochMillis = 1, updatedAtEpochMillis = 1)
            val frozen = snapshots.capture(template, configured)
            val olderProfiles = profiles.getProfiles()
            val profile = profiles.add("Receiver QA $case", frozen, ExportTarget.API_ENDPOINT, apiEndpointUrl = endpoint)
            for (older in olderProfiles) check(profiles.delete(older.id))
            profileId = profile.id
            ReceiverCoverageRuntime.save(this@ReceiverCoverageQaActivity, profile.id, config, endpoint, credentials)
            if (rebound) bindScopeElsewhere(config.scopeId)
            val fired = now.minusMinutes(1)
            check(entries.upsert(ScheduledProfileEntry(profile.id, isEnabled = true,
                anchorEpochDay = fired.toLocalDate().toEpochDay(), hour = fired.hour, minute = fired.minute,
                lookbackDays = lookback, todayRefreshEnabled = today, zoneId = ZoneId.systemDefault().id)))
            profileScheduler.handleAlarm(profile.id) // Production alarm delivery, enqueue and admission.
        } else {
            ReceiverCoverageRuntime.save(this@ReceiverCoverageQaActivity, "legacy", config, endpoint, credentials)
            if (rebound) bindScopeElsewhere(config.scopeId)
            scheduler.reconcile()
            val armed = requireNotNull(stateStore.load())
            check(scheduler.handleOccurrence(armed, expedited = true)) // Actual armed occurrence, no fabricated WorkData/admission.
        }
        awaitCondition { allWork().any { it.id !in workIdsBefore } }
        var ids = allWork().filter { it.id !in workIdsBefore }.map { it.id }.toSet()
        val fixtureStoppedBackoffIds = mutableSetOf<UUID>()
        if (cancelled) {
            awaitCondition { allWork().filter { it.id in ids }.all { it.state.isFinished } }
            check(count("cancel_action") == 1 && count("coverage") == 1)
            check(count("capture") == 0 && count("upload") == 0 && history.getAllEntries().first().isEmpty()) {
                "Cancelled preflight must not capture/upload or fabricate history"
            }
            val beforeRecovery = planFiles().filterKeys { it !in previousPlans }.values.single().second
            check(beforeRecovery.getValue("coverage_status").jsonPrimitive.content == "fallback_full")
            check(beforeRecovery.getValue("residual").jsonArray.isNotEmpty())
            // Normal future configuration edits cannot rewrite this accepted recovery plan.
            val changed = ReceiverCoverageConfiguration(config.preflightUrl, "new-${UUID.randomUUID()}", 30)
            ReceiverCoverageRuntime.save(this@ReceiverCoverageQaActivity, profileId ?: "legacy", changed, endpoint, credentials)
            settings.updateExportSettingsAtomically { it.copy(filenameFormat = "changed-{date}", scheduleLookbackDays = 1) }
            state.update(mapOf("coverage_mode" to "all")) // A requery would now return a different answer.
            if (profileMode) {
                entries.update(requireNotNull(profileId)) { it.copy(lookbackDays = 1) }
                val beforeRetry = allWork().map { it.id }.toSet()
                profileScheduler.handleAlarm(profileId)
                awaitCondition { allWork().any { it.id !in beforeRetry } }
                ids = ids + allWork().filter { it.id !in beforeRetry }.map { it.id }
            } else recovery.recoverPendingDates()
        }
        if (partial) {
            awaitCondition {
                val plan = planFiles().filterKeys { it !in previousPlans }.values.singleOrNull()?.second
                plan != null && plan.getValue("residual").jsonArray.size in 1 until plan.getValue("selected").jsonArray.size
            }
            check(count("coverage") == 1) { "Partial ACK must keep the original query" }
            val plan = planFiles().filterKeys { it !in previousPlans }.values.single().second
            val firstAck = values("ack").first().split(",").toSet()
            val residual = plan.getValue("residual").jsonArray.map { it.jsonPrimitive.content }.toSet()
            check(firstAck.size == 7 && residual.size == 3 && count("upload") >= 2) {
                "Expected a real seven-day ACK and failed second production batch"
            }
            check(residual.intersect(firstAck).isEmpty())
            if (profileMode) {
                val ownedProfile = requireNotNull(profileId)
                // Journal ACK precedes the native retry checkpoint. Wait for BOTH and for
                // WorkManager to enter its actual 30-minute backoff before touching the request.
                awaitCondition {
                    val entry = entries.entry(ownedProfile)
                    entry != null && entry.pendingExports.flatMap { it.ownerDates }.map { it.toString() }.toSet() == residual &&
                        allWork().filter { it.id in ids }.let { work ->
                            work.size == ids.size && work.all { it.state == WorkInfo.State.ENQUEUED && it.runAttemptCount > 0 }
                        }
                }
                val checkpoint = requireNotNull(entries.entry(ownedProfile))
                check(ids.size == 1) { "Fixture must own exactly the original profile request" }
                // Cancel ONLY the observed fixture-owned delayed request, not schedule runtime,
                // notification discard, pending rows or recovery generation. KEEP can now admit
                // a new real worker without changing production backoff or replay authority.
                for (id in ids) workManager.cancelWorkById(id).result.get(10, java.util.concurrent.TimeUnit.SECONDS)
                awaitCondition { allWork().filter { it.id in ids }.all { it.state == WorkInfo.State.CANCELLED } }
                val afterStop = requireNotNull(entries.entry(ownedProfile))
                check(afterStop.recoveryGeneration == checkpoint.recoveryGeneration &&
                    afterStop.pendingExports == checkpoint.pendingExports) { "Stopping fixture backoff changed recovery authority" }
                check(planFiles().filterKeys { it !in previousPlans }.values.single().second == plan) {
                    "Stopping fixture backoff changed the frozen plan or ACKs"
                }
                fixtureStoppedBackoffIds += ids
                state.event("fixture_backoff_stop", ids.single().toString())
                state.update(mapOf("fail_upload_after" to "disabled"))
                val initialIds = allWork().map { it.id }.toSet()
                profileScheduler.handleAlarm(ownedProfile)
                awaitCondition { allWork().any { it.id !in initialIds } }
                ids = ids + allWork().filter { it.id !in initialIds }.map { it.id }
            } else {
                awaitCondition { allWork().filter { it.id in ids }.all { it.state.isFinished } }
                check(settings.getExportSettings().pendingScheduledExportRequests.map { it.date.toString() }.toSet() == residual)
                state.update(mapOf("fail_upload_after" to "disabled"))
                recovery.recoverPendingDates() // Production exact-plan recovery, never a new preflight.
            }
        }
        awaitCondition { allWork().filter { it.id in ids }.all { it.state.isFinished } }
        allWork() // Record the final live states before reading the evidence.
        val finalStates = ids.associateWith { id -> synchronized(observedStates) { observedStates[id] } }
        check(finalStates.values.none { it == null }) { "WorkManager evidence was never observed" }
        check(finalStates.all { (id, state) ->
            state == if (id in fixtureStoppedBackoffIds) WorkInfo.State.CANCELLED else WorkInfo.State.SUCCEEDED
        }) { "Worker states: ${finalStates.values}" }
        val newPlans = planFiles().filterKeys { it !in previousPlans }
        if (wide || rebound) {
            check(newPlans.isEmpty() && count("coverage") == 0) { "Fallback must not preflight or save a plan" }
            check(values("capture").distinct().size == lookback) { "Fallback must capture the full lookback" }
            if (rebound) check(count("upload") >= 1 && history.getAllEntries().first().isNotEmpty()) {
                "Rebound scope must still upload and record history"
            }
        } else {
            check(count("coverage") == 1) { "Expected one preflight, observed ${count("coverage")}" }
            val plan = newPlans.values.single().second
            check(plan.getValue("coverage_status").jsonPrimitive.content == if (cancelled) "fallback_full" else "valid") {
                "Expected original valid selection or cancelled conservative fallback"
            }
            check(plan.getValue("residual").jsonArray.isEmpty()) { "Journal residual was not acknowledged" }
            val selected = plan.getValue("selected").jsonArray.map { it.jsonPrimitive.content }
            check(values("capture").sorted() == selected.sorted()) { "Capture differs from frozen selection" }
            if (empty) {
                check(selected.isEmpty() && count("upload") == 0 && history.getAllEntries().first().isEmpty())
            } else check(values("ack").flatMap { it.split(",") }.sorted() == selected.sorted()) { "ACK differs from selected dates" }
            if (today) check(selected == listOf(LocalDate.now().toString()))
            if (today && profileMode) {
                val entry = requireNotNull(entries.entry(requireNotNull(profileId)))
                check(entry.lastRefreshSuccessEpochMillis != null)
                val captures = count("capture"); val queries = count("coverage")
                val beforeRepeat = allWork().map { it.id }.toSet()
                profileScheduler.handleAlarm(profileId)
                awaitCondition { allWork().any { it.id !in beforeRepeat } }
                val repeatIds = allWork().filter { it.id !in beforeRepeat }.map { it.id }.toSet()
                awaitCondition { allWork().filter { it.id in repeatIds }.all { it.state.isFinished } }
                check(allWork().filter { it.id in repeatIds }.all { it.state == WorkInfo.State.SUCCEEDED })
                check(count("capture") == captures && count("coverage") == queries) { "Satisfied Today slot replayed" }
            }
        }
        val pending = settings.getExportSettings().pendingScheduledExportRequests
        check(pending.isEmpty()) { "Legacy native residuals remain" }
        profileId?.let { check(entries.entry(it)?.pendingExports?.isEmpty() == true) }
        val result = "queries=${count("coverage")} captures=${count("capture")} uploads=${count("upload")} acks=${count("ack")} history=${history.getAllEntries().first().size}"
        state.event("result", "PASS $case $result")
        // Stop future synthetic occurrences only AFTER all real journal/native/history assertions.
        scheduler.cancel()
        profileId?.let { id ->
            entries.update(id) { it.copy(isEnabled = false) }
            profileScheduler.cancelProfileRuntime(id)
        }
        result
    }
    /** Synthetic stand-in for a binding written by an earlier output profile; never a real digest. */
    private fun bindScopeElsewhere(scopeId: String) {
        val file = filesDir.toPath().resolve("receiver-coverage/scope-$scopeId.binding")
        com.healthmd.data.receivercoverage.ReceiverCoverageAtomicFile.write(file, "0".repeat(64).toByteArray())
    }
    private suspend fun awaitCondition(condition: suspend () -> Boolean) {
        while (!condition()) delay(100)
    }
    private fun count(kind: String) = values(kind).size
    private fun values(kind: String) = state.events().filter { it.getValue("kind").jsonPrimitive.content == kind }.map { it.getValue("value").jsonPrimitive.content }
    private fun allWork(): List<WorkInfo> = listOf(ExportScheduler.EXPORT_OCCURRENCE_TAG, ScheduledProfileScheduler.EXPORT_WORK_TAG)
        .flatMap { workManager.getWorkInfosByTag(it).get(10, java.util.concurrent.TimeUnit.SECONDS) }.distinctBy { it.id }
        .also { work -> synchronized(observedStates) { work.forEach { observedStates[it.id] = it.state } } }
    private fun planFiles(): Map<String, Pair<JsonObject, JsonObject>> {
        val path = filesDir.toPath().resolve("receiver-coverage/plans")
        if (!Files.exists(path)) return emptyMap()
        return Files.list(path).use { files -> files.iterator().asSequence().filter { it.fileName.toString().endsWith(".json") }.associate { file ->
            val envelope = Json.parseToJsonElement(String(Files.readAllBytes(file), Charsets.UTF_8)).jsonObject
            file.fileName.toString() to (envelope to Json.parseToJsonElement(envelope.getValue("plan").jsonPrimitive.content).jsonObject)
        } }
    }
    override fun onDestroy() { scope.cancel(); super.onDestroy() }
}
