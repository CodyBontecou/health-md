package com.healthmd.effecthostcandidate

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.os.Process
import android.os.SystemClock
import androidx.work.Data
import androidx.work.WorkManager
import com.facebook.react.ReactPackage
import com.facebook.react.bridge.*
import com.facebook.react.uimanager.ViewManager
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.ConcurrentHashMap
import org.json.JSONObject

internal val coldCases = listOf("actual_schedule_no_activity", "unknown_schema_before_acquire", "expiry_before_acquire", "stop_waits_native_ack", "duplicate_request_no_double_acquire")
internal fun uuid(value: String): Boolean = value.matches(Regex("[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}"))
internal class ColdRefusal(val code: String) : RuntimeException()
internal data class ColdFrame(val caseId: String, val sequence: Int, val ttl: Int)
internal object ColdEvidence {
    fun sameBoot(before: Int?, after: Int?): String =
        if (before == null || after == null || before < 0 || after < 0) "unavailable" else if (before != after) "incomplete" else "same_boot"
    fun controlNonce(issued: String, sent: String): String? = if (issued != sent) "control_invalid" else null
    fun sameProcess(recorded: String, current: String): Boolean = recorded == current && uuid(recorded)
    fun cleanupComplete(acquired: Int, released: Int, unresolved: Int, releasing: Boolean): Boolean =
        acquired == released && unresolved == 0 && !releasing
    fun publishedComplete(phase: String, ack: Int): Boolean = phase == "completed" && ack == 1
}

/** Linear ASCII lexical admission BEFORE JSON object construction, engine or resource. */
internal object ColdParser {
    fun unsigned(raw: String, max: Long): Long {
        if (!raw.matches(Regex("0|[1-9][0-9]{0,18}"))) throw ColdRefusal("schema_invalid")
        if (raw.length > max.toString().length || (raw.length == max.toString().length && raw > max.toString())) throw ColdRefusal("schema_invalid")
        return raw.toLong()
    }
    fun frame(raw: String): ColdFrame {
        if (raw.length > 4096 || raw.toByteArray(Charsets.UTF_8).size > 4096) throw ColdRefusal("frame_limit")
        if (raw.any { it.code > 127 || it == '\u0000' }) throw ColdRefusal("schema_invalid")
        var i = 0
        fun white() { while (i < raw.length && raw[i] in " \t\r\n") i++ }
        fun punct(c: Char) { white(); if (i >= raw.length || raw[i++] != c) throw ColdRefusal("schema_invalid") }
        fun string(): String {
            white(); punct('"'); val start = i
            while (i < raw.length && raw[i] != '"') {
                if (raw[i].code < 32 || raw[i] == '\\' || i - start >= 64) throw ColdRefusal("schema_invalid")
                i++
            }
            if (i >= raw.length) throw ColdRefusal("schema_invalid")
            return raw.substring(start, i++)
        }
        val strings = mutableMapOf<String, String>(); val numbers = mutableMapOf<String, Long>()
        punct('{')
        repeat(5) { n ->
            if (n > 0) punct(',')
            val key = string(); punct(':')
            if (key in strings || key in numbers) throw ColdRefusal("schema_invalid")
            when (key) {
                "schema", "case_id" -> strings[key] = string()
                "version", "sequence", "ttl_ms" -> {
                    white(); val start = i
                    while (i < raw.length && raw[i] in '0'..'9' && i-start <= 19) i++
                    numbers[key] = unsigned(raw.substring(start, i), if (key == "ttl_ms") 30000 else if (key == "sequence") 4 else 1)
                }
                else -> throw ColdRefusal("schema_invalid")
            }
        }
        punct('}'); white(); if (i != raw.length) throw ColdRefusal("schema_invalid")
        val caseId = strings["case_id"] ?: throw ColdRefusal("schema_invalid")
        val sequence = numbers["sequence"]?.toInt() ?: throw ColdRefusal("schema_invalid")
        if (strings["schema"] != "healthmd.candidate_cold_worker" || numbers["version"] != 1L || coldCases.getOrNull(sequence) != caseId) throw ColdRefusal("schema_invalid")
        return ColdFrame(caseId, sequence, numbers["ttl_ms"]?.toInt() ?: throw ColdRefusal("schema_invalid"))
    }
    fun clock(submitted: Long, now: Long, ttl: Int) {
        if (now < submitted) throw ColdRefusal("clock_invalid")
        if (now-submitted >= ttl) throw ColdRefusal("expired")
    }
    fun data(data: Data): Pair<ColdFrame, Long> {
        val values = data.keyValueMap
        if (values.keys != setOf("payload", "submitted_elapsed_ms") || values.values.any { it !is String }) throw ColdRefusal("schema_invalid")
        val payload = values["payload"] as String; val submitted = values["submitted_elapsed_ms"] as String
        if (payload.toByteArray(Charsets.UTF_8).size + submitted.length > 8192) throw ColdRefusal("frame_limit")
        return frame(payload) to unsigned(submitted, Long.MAX_VALUE)
    }
}

/** Only synthetic, bounded, native-issued identities are persisted. No user or production state. */
internal object ColdRegistry {
    private val lock = Any()
    private val scheduler = Executors.newSingleThreadScheduledExecutor()
    private lateinit var app: ColdProbeApplication
    val processNonce: String = UUID.randomUUID().toString()
    private var activity = 0
    private var quarantined = false
    private var run = ""
    private var controller = ""
    private data class Issue(val work: String, val caseId: String, val sequence: Int, val generation: Int)
    private val issues = linkedMapOf<String, Issue>()
    private val reserved = mutableSetOf<String>()
    private val stopping = ConcurrentHashMap.newKeySet<String>()
    private val totals = mutableMapOf<String, Pair<Int, Int>>()
    private data class Ticket(val issue: Issue, val invocation: String, val submitted: Long, val ttl: Int,
        val complete: (String?, Boolean) -> Unit, var stopped: Boolean = false, var code: String = "ready",
        var acquired: Int = 0, var released: Int = 0, var inspecting: Int = 0, var releasing: Boolean = false,
        var terminal: Boolean = false, var inspectPromise: Promise? = null,
        var deadlineTask: ScheduledFuture<*>? = null, var inspectTask: ScheduledFuture<*>? = null, var cleanupTask: ScheduledFuture<*>? = null)
    private val tickets = linkedMapOf<String, Ticket>()
    private val queue = ArrayDeque<String>()
    private var waiter: Promise? = null
    private fun logical(i: Issue) = "${i.caseId}:${i.sequence}"
    private fun directory() = File(app.filesDir, "cold-worker-probe/$run")
    private fun fixedJson(fields: List<Pair<String, Any?>>): String = JSONObject().also { j -> fields.forEach { j.put(it.first, it.second ?: JSONObject.NULL) } }.let {
        // JSONObject iteration order is not the contract: explicitly emit listed order.
        fields.joinToString(",", "{", "}") { (k, v) -> JSONObject.quote(k) + ":" + when(v) { null -> "null"; is String -> JSONObject.quote(v); else -> v.toString() } }
    }
    fun initialize(application: ColdProbeApplication) = synchronized(lock) {
        app = application
        try {
            val f = File(app.filesDir, "cold-worker-probe/issued.json")
            if (!f.exists()) return@synchronized
            if (f.length() > 5000) throw ColdRefusal("schema_invalid")
            val j = JSONObject(f.readText()); run = j.getString("run_nonce"); controller = j.getString("controller_nonce")
            check(uuid(run) && uuid(controller))
            val rows = j.getJSONArray("issues"); check(rows.length() in 1..5)
            repeat(rows.length()) { n -> val row = rows.getJSONObject(n)
                val issue = Issue(row.getString("work_id"), row.getString("case_id"), row.getInt("sequence"), row.getInt("generation"))
                check(uuid(issue.work) && coldCases.getOrNull(issue.sequence) == issue.caseId && issue.generation in 1..5)
                check(!issues.containsKey(issue.work)); issues[issue.work] = issue
            }
        } catch (_: Throwable) { issues.clear(); quarantined = true }
    }
    /** Called only by the brief setup instrumentation; engine stays unloaded. */
    fun issue(context: Context, works: List<Pair<String, Int>>, preservedRun: String?): Pair<String, String> = synchronized(lock) {
        check(works.size in 1..5 && tickets.isEmpty()); check(works.all { uuid(it.first) && it.second in 0..4 })
        if (run.isNotEmpty()) {
            // Later setup accepts cleanup only after the harness has saved the exact prior run evidence.
            check(preservedRun == run && uuid(run))
            val dir = directory()
            check(dir.listFiles()?.all { f -> issues.keys.any { f.name == "$it.json" } } != false)
            issues.keys.forEach { work ->
                val f = File(dir, "$work.json"); check(f.exists() && f.length() <= 2048)
                val a = JSONObject(f.readText()); check(a.getString("run_nonce") == run && a.getString("phase") == "completed" && a.getInt("ack") == 1)
                check(a.getInt("active") == 0 && a.getInt("unresolved_inspections") == 0 && a.getInt("acquired") == a.getInt("released"))
                check(WorkManager.getInstance(context).getWorkInfoById(UUID.fromString(work)).get(1000, TimeUnit.MILLISECONDS)?.state?.isFinished == true)
            }
            issues.keys.forEach { check(File(dir, "$it.json").delete()) }; check(dir.delete())
            WorkManager.getInstance(context).pruneWork().result.get(5, TimeUnit.SECONDS)
        }
        run = UUID.randomUUID().toString(); controller = UUID.randomUUID().toString(); issues.clear()
        works.forEachIndexed { n, (work, sequence) -> issues[work] = Issue(work, coldCases[sequence], sequence, n+1) }
        val rows = issues.values.map { i -> JSONObject().put("work_id", i.work).put("case_id", i.caseId).put("sequence", i.sequence).put("generation", i.generation) }
        val encoded = JSONObject().put("run_nonce", run).put("controller_nonce", controller).put("issues", org.json.JSONArray(rows)).toString()
        check(encoded.toByteArray().size <= 5000)
        val parent = File(context.filesDir, "cold-worker-probe"); parent.mkdirs()
        val pending = File(parent, "issued.pending"); pending.writeText(encoded)
        check(pending.renameTo(File(parent, "issued.json")))
        run to controller
    }
    fun activityCreated() = synchronized(lock) { activity++; quarantined = true }
    private fun live(t: Ticket): Boolean {
        val now = SystemClock.elapsedRealtime()
        return !quarantined && activity == 0 && !t.stopped && !stopping.contains(t.issue.work) && !t.terminal && now >= t.submitted && now-t.submitted < t.ttl
    }
    fun current(work: String): Boolean = synchronized(lock) { tickets[work]?.let(::live) == true }
    private fun ack(t: Ticket, phase: String, code: String, value: Int): String {
        val sum = totals[logical(t.issue)] ?: (0 to 0)
        return fixedJson(listOf("schema" to "healthmd.candidate_cold_worker_ack", "version" to 1,
            "run_nonce" to run, "process_nonce" to processNonce, "work_id" to t.issue.work, "invocation_id" to t.invocation,
            "case_id" to t.issue.caseId, "sequence" to t.issue.sequence, "generation" to t.issue.generation,
            "pid" to Process.myPid(), "phase" to phase, "code" to code, "ack" to value,
            "acquired" to t.acquired, "released" to t.released, "active" to (t.acquired-t.released),
            "unresolved_inspections" to t.inspecting, "logical_total_acquired" to sum.first, "logical_total_released" to sum.second))
    }
    private fun writeAck(t: Ticket, phase: String, code: String, value: Int): Boolean = try {
        val raw = ack(t, phase, code, value); check(raw.toByteArray().size <= 2048)
        val dir = directory(); dir.mkdirs()
        val file = File(dir, "${t.issue.work}.json"); val tmp = File(dir, "${t.issue.work}.pending")
        tmp.writeText(raw); check(tmp.renameTo(file)); true
    } catch (_: Throwable) { quarantined = true; false }
    private fun result(t: Ticket, code: String, value: Int): String = fixedJson(listOf(
        "schema" to "healthmd.candidate_cold_worker_result", "version" to 1, "case_id" to t.issue.caseId,
        "sequence" to t.issue.sequence, "work_id" to t.issue.work, "invocation_id" to t.invocation,
        "pid" to Process.myPid(), "code" to code, "acquired" to t.acquired, "released" to t.released,
        "active" to (t.acquired-t.released), "unresolved_inspections" to t.inspecting, "ack" to value,
        "activity_created" to activity, "react_views" to 0, "old_probe_runs" to 0))
    private fun finish(t: Ticket, requested: String) {
        if (t.terminal) return
        val released = ColdEvidence.cleanupComplete(t.acquired, t.released, t.inspecting, t.releasing)
        val code = if (!released) "cleanup_unverified" else requested
        val complete = released && code != "engine_failure" && code != "cleanup_unverified"
        val ackCode = if (code in listOf("ready", "schema_invalid", "expired", "duplicate_request", "stopped", "engine_failure", "cleanup_unverified")) code else "schema_invalid"
        // ACK's narrower closed grammar uses generic admission refusal; normal Result retains its
        // exact frame_limit/clock_invalid/backpressure code. Frozen raw parser expectations unchanged.
        val persisted = writeAck(t, if (complete) "completed" else "incomplete", ackCode, if (complete) 1 else 0)
        t.terminal = true; queue.remove(t.issue.work)
        t.deadlineTask?.cancel(false); t.inspectTask?.cancel(false); t.cleanupTask?.cancel(false)
        if (!complete || !persisted) quarantined = true
        t.complete(result(t, if (persisted) code else "cleanup_unverified", if (complete && persisted) 1 else 0), complete && persisted && code == "ready")
    }
    fun start(work: String, data: Data, completion: (String?, Boolean) -> Unit) = synchronized(lock) {
        val issued = issues[work] ?: kotlin.run { completion(null, false); return@synchronized }
        // Same native WorkUUID replay must NEVER replace an existing ownership journal/witness.
        if (tickets.containsKey(work) || tickets.size >= 5) { completion(null, false); return@synchronized }
        val t = Ticket(issued, UUID.randomUUID().toString(), SystemClock.elapsedRealtime(), 0, completion)
        tickets[work] = t
        try {
            val (frame, submitted) = ColdParser.data(data)
            if (frame.caseId != issued.caseId || frame.sequence != issued.sequence) throw ColdRefusal("schema_invalid")
            val admitted = t.copy(submitted = submitted, ttl = frame.ttl); tickets[work] = admitted
            val now = SystemClock.elapsedRealtime()
            try { ColdParser.clock(submitted, now, frame.ttl) } catch (e: ColdRefusal) { finish(admitted, e.code); return@synchronized }
            if (stopping.contains(work)) { finish(admitted, "stopped"); return@synchronized }
            if (quarantined) { finish(admitted, "engine_failure"); return@synchronized }
            if (!reserved.add(logical(issued))) { finish(admitted, "duplicate_request"); return@synchronized }
            if (queue.size >= 4) { finish(admitted, "backpressure"); return@synchronized }
            queue.addLast(work)
            admitted.deadlineTask = scheduler.schedule({ synchronized(lock) { if (!admitted.terminal) { admitted.code = "expired"; admitted.stopped = true; cleanupDeadline(admitted) } } }, (frame.ttl-(now-submitted)).toLong(), TimeUnit.MILLISECONDS)
            app.startOwnedEngine(work); dispatch()
        } catch (e: ColdRefusal) { finish(t, e.code) }
        catch (_: Throwable) { finish(t, "engine_failure") }
    }
    private fun cleanupDeadline(t: Ticket) {
        if (t.acquired == 0) { finish(t, t.code); return }
        t.cleanupTask = scheduler.schedule({ synchronized(lock) { if (!t.terminal) finish(t, "cleanup_unverified") } }, 5000, TimeUnit.MILLISECONDS)
    }
    fun stop(work: String) {
        stopping.add(work) // immediate concurrent fence, no blocking lock/file I/O in onStopped
        scheduler.execute { synchronized(lock) {
            tickets[work]?.let { t -> if (!t.terminal) { t.stopped = true; t.code = "stopped"; cleanupDeadline(t) } }
        } }
    }
    fun engineFailed() = synchronized(lock) {
        quarantined = true
        tickets.values.filter { !it.terminal }.forEach { t -> t.stopped = true; t.code = "engine_failure"; cleanupDeadline(t) }
        waiter?.resolve(null); waiter = null
    }
    private fun dispatch() {
        val p = waiter ?: return
        while (queue.isNotEmpty()) {
            val work = queue.removeFirst(); val t = tickets[work] ?: continue
            if (t.terminal || !live(t)) continue
            waiter = null
            p.resolve(fixedJson(listOf("work_id" to work, "invocation_id" to t.invocation, "process_nonce" to processNonce,
                "case_id" to t.issue.caseId, "sequence" to t.issue.sequence, "ttl_ms" to t.ttl, "generation" to t.issue.generation, "pid" to Process.myPid(), "submitted_elapsed_ms" to t.submitted.toString())))
            return
        }
    }
    fun take(p: Promise) = synchronized(lock) {
        if (quarantined) { p.resolve(null); return@synchronized }
        if (waiter != null) { p.reject("backpressure", "backpressure"); return@synchronized }
        waiter = p; dispatch()
    }
    fun check(work: String, p: Promise) = synchronized(lock) {
        if (current(work)) p.resolve(true) else p.resolve(false)
    }
    fun acquire(work: String, p: Promise) = synchronized(lock) {
        val t = tickets[work]
        if (t == null || !live(t) || t.acquired != 0 || tickets.values.any { it.acquired != it.released }) { p.reject("scope_invalid", "scope_invalid"); return@synchronized }
        t.acquired = 1; totals[logical(t.issue)] = 1 to 0
        // No async preparation/partial allocation: owned counter and callback are registered atomically.
        p.resolve(t.invocation)
    }
    fun inspect(work: String, handle: String, p: Promise) = synchronized(lock) {
        val t = tickets[work]
        if (t == null || !live(t) || handle != t.invocation || t.acquired != 1 || t.released != 0 || t.inspectPromise != null) { p.reject("scope_invalid", "scope_invalid"); return@synchronized }
        t.inspecting = 1; t.inspectPromise = p
        if (!writeAck(t, "inspection_started", "ready", 0)) { p.reject("engine_failure", "engine_failure"); return@synchronized }
        val delay = if (t.issue.sequence == 3) 5000L else 30L
        t.inspectTask = scheduler.schedule({ synchronized(lock) { if (!t.releasing && !t.terminal) { t.inspectPromise?.resolve("ready"); t.inspectPromise = null; t.inspecting = 0 } } }, delay, TimeUnit.MILLISECONDS)
    }
    fun release(work: String, handle: String, p: Promise) = synchronized(lock) {
        val t = tickets[work]
        if (t == null || handle != t.invocation || t.acquired != 1 || t.released != 0 || t.releasing) { p.reject("cleanup_unverified", "cleanup_unverified"); return@synchronized }
        t.releasing = true
        if (!writeAck(t, "release_pending", t.code, 0)) { p.reject("cleanup_unverified", "cleanup_unverified"); return@synchronized }
        scheduler.schedule({ synchronized(lock) {
            if (t.terminal) { p.reject("cleanup_unverified", "cleanup_unverified"); return@synchronized }
            // Resolve the outstanding native inspection before ACK; no orphaned Promise after interruption.
            t.inspectTask?.cancel(false)
            t.inspectPromise?.resolve("ready"); t.inspectPromise = null; t.inspecting = 0
            t.released = 1; t.releasing = false; totals[logical(t.issue)] = 1 to 1
            p.resolve(null)
        } }, 150, TimeUnit.MILLISECONDS)
    }
    fun terminal(work: String, requested: String, p: Promise) = synchronized(lock) {
        val t = tickets[work]
        if (t == null || t.terminal || requested !in listOf("ready", "stopped", "expired", "engine_failure", "cleanup_unverified")) { p.reject("scope_invalid", "scope_invalid"); return@synchronized }
        finish(t, if (stopping.contains(work)) "stopped" else if (t.stopped) t.code else if (!live(t)) "expired" else requested)
        p.resolve(null)
    }
    fun control(command: String, work: String, nonce: String): String = synchronized(lock) {
        val t = tickets[work]
        ColdEvidence.controlNonce(controller, nonce)?.let { return@synchronized controlResult(it, null, null) }
        if (t == null) return@synchronized controlResult("control_unavailable", null, null)
        if (command == "cancel") {
            if (t.terminal) return@synchronized controlResult("control_unavailable", null, null)
            WorkManager.getInstance(app).cancelWorkById(UUID.fromString(work))
            return@synchronized controlResult("cancel_dispatched", work, null)
        }
        val file = File(directory(), "$work.json")
        if (!file.exists() || file.length() > 2048) return@synchronized controlResult("control_unavailable", null, null)
        val raw = file.readText(); val j = JSONObject(raw)
        if (!ColdEvidence.sameProcess(j.getString("process_nonce"), processNonce) || j.getString("invocation_id") != t.invocation || j.getInt("pid") != Process.myPid()) return@synchronized controlResult("control_unavailable", null, null)
        // Final ACK remains cleanup proof; this publication gate additionally rules out an
        // in-flight WorkManager invocation before optional later background process preparation.
        if (ColdEvidence.publishedComplete(j.getString("phase"), j.getInt("ack"))) {
            val state = WorkManager.getInstance(app).getWorkInfoById(UUID.fromString(work)).get(1000, TimeUnit.MILLISECONDS)?.state
            val expected = when(j.getString("code")) {
                "ready" -> androidx.work.WorkInfo.State.SUCCEEDED
                "stopped" -> androidx.work.WorkInfo.State.CANCELLED
                else -> androidx.work.WorkInfo.State.FAILED
            }
            if (state != expected) return@synchronized controlResult("control_unavailable", null, null)
        }
        val snapshot = ack(t, j.getString("phase"), j.getString("code"), j.getInt("ack"))
        controlResult("ack_snapshot", work, snapshot)
    }
    fun controlResult(code: String, work: String?, raw: String?): String {
        val head = fixedJson(listOf("schema" to "healthmd.candidate_cold_worker_control", "version" to 1, "code" to code,
            "work_id" to work, "process_nonce" to if (work == null) null else processNonce, "snapshot" to null))
        val result = if (raw == null) head else head.dropLast(5) + raw + "}"
        return if (result.toByteArray().size <= 4096) result else controlResult("control_unavailable", null, null)
    }
}

class ColdProbeModule(context: ReactApplicationContext) : ReactContextBaseJavaModule(context) {
    override fun getName() = "ColdProbe"
    @ReactMethod fun failEngine() { ColdRegistry.engineFailed() }
    @ReactMethod fun take(p: Promise) { ColdRegistry.take(p) }
    @ReactMethod fun check(work: String, p: Promise) { ColdRegistry.check(work, p) }
    @ReactMethod fun acquire(work: String, p: Promise) { ColdRegistry.acquire(work, p) }
    @ReactMethod fun inspect(work: String, handle: String, p: Promise) { ColdRegistry.inspect(work, handle, p) }
    @ReactMethod fun release(work: String, handle: String, p: Promise) { ColdRegistry.release(work, handle, p) }
    @ReactMethod fun terminal(work: String, code: String, p: Promise) { ColdRegistry.terminal(work, code, p) }
}
class ColdProbePackage : ReactPackage {
    override fun createNativeModules(context: ReactApplicationContext): List<NativeModule> = listOf(ColdProbeModule(context))
    override fun createViewManagers(context: ReactApplicationContext): List<ViewManager<*, *>> = emptyList()
}

class ColdProbeControlReceiver : BroadcastReceiver() {
    override fun onReceive(context: Context, intent: Intent) {
        val pending = goAsync()
        val executor = Executors.newSingleThreadExecutor()
        val timeout = Executors.newSingleThreadScheduledExecutor()
        val done = java.util.concurrent.atomic.AtomicBoolean(false)
        fun finish(raw: String) { if (done.compareAndSet(false, true)) { pending.setResultData(raw); pending.finish(); executor.shutdownNow(); timeout.shutdownNow() } }
        timeout.schedule({ finish(ColdRegistry.controlResult("control_unavailable", null, null)) }, 2000, TimeUnit.MILLISECONDS)
        executor.execute {
            try {
                if (intent.action != context.packageName + ".CONTROL" || intent.component?.className != javaClass.name) throw ColdRefusal("control_invalid")
                val extras = intent.extras ?: throw ColdRefusal("control_invalid")
                if (extras.keySet() != setOf("command", "work_id", "controller_nonce")) throw ColdRefusal("control_invalid")
                val values = extras.keySet().associateWith { extras.get(it) }
                if (values.values.any { it !is String }) throw ColdRefusal("control_invalid")
                val command = values["command"] as String; val work = values["work_id"] as String; val nonce = values["controller_nonce"] as String
                if (command !in listOf("cancel", "read_ack") || !uuid(work) || !uuid(nonce) || command.length+work.length+nonce.length > 128) throw ColdRefusal("control_invalid")
                finish(ColdRegistry.control(command, work, nonce))
            } catch (_: Throwable) { finish(ColdRegistry.controlResult("control_invalid", null, null)) }
        }
    }
}
