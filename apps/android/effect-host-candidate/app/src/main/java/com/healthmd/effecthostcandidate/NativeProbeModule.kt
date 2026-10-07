package com.healthmd.effecthostcandidate

import android.os.Handler
import android.os.Looper
import com.facebook.react.ReactPackage
import com.facebook.react.bridge.*
import com.facebook.react.uimanager.ViewManager
import org.json.JSONObject
import java.nio.charset.StandardCharsets
import java.util.concurrent.CountDownLatch
import java.util.concurrent.atomic.AtomicReference

/** Linear private admission without input-sized allocations; fixed keys/enums and canonical 1/0 tokens. */
object ProbeAdmission {
    fun rejectFrame(value: String): String? {
        // Any valid UTF-8 encoding needs at least as many bytes as UTF-16 code units.
        // Reject giant input before allocating an encoder, tokens or parsed JSON objects.
        if (value.length > 65536) return "frame_limit"
        var bytes = 0
        var position = 0
        while (position < value.length) {
            val char = value[position++].code
            bytes += when {
                char <= 0x7f -> 1
                char <= 0x7ff -> 2
                char in 0xd800..0xdbff -> {
                    if (position == value.length || value[position].code !in 0xdc00..0xdfff) return "schema_invalid"
                    position++; 4
                }
                char in 0xdc00..0xdfff -> return "schema_invalid"
                else -> 3
            }
            if (bytes > 65536) return "frame_limit"
        }
        position = 0
        fun whitespace() { while (position < value.length && value[position] in " \t\r\n") position++ }
        fun character(expected: Char): Boolean {
            whitespace()
            if (position >= value.length || value[position] != expected) return false
            position++; return true
        }
        var tokenStart = 0
        var tokenEnd = 0
        fun stringToken(): Boolean {
            if (!character('"')) return false
            tokenStart = position
            while (position < value.length) {
                val char = value[position++]
                if (char == '"') { tokenEnd = position - 1; return true }
                // This private profile uses canonical ASCII keys/enums, with no escapes.
                if (char == '\\' || char.code < 0x20) return false
            }
            return false
        }
        fun tokenEquals(expected: String) = tokenEnd - tokenStart == expected.length &&
            value.regionMatches(tokenStart, expected, 0, expected.length)
        if (!character('{')) return "schema_invalid"
        var fields = 0
        repeat(4) { member ->
            if (!stringToken()) return "schema_invalid"
            val field = when {
                tokenEquals("schema") -> 1
                tokenEquals("version") -> 2
                tokenEquals("case_id") -> 4
                tokenEquals("sequence") -> 8
                else -> return "schema_invalid"
            }
            if (fields and field != 0 || !character(':')) return "schema_invalid"
            fields = fields or field
            when (field) {
                1 -> if (!stringToken() || !tokenEquals("healthmd.candidate_host_probe")) return "schema_invalid"
                4 -> if (!stringToken() || !tokenEquals("queue_backpressure")) return "schema_invalid"
                2 -> if (!character('1')) return "schema_invalid"
                8 -> if (!character('0')) return "schema_invalid"
            }
            // Exact delimiter rejects fractional/exponential tokens without numeric conversion.
            if (!character(if (member == 3) '}' else ',')) return "schema_invalid"
        }
        whitespace()
        return if (fields == 15 && position == value.length) null else "schema_invalid"
    }
}

object ProbeRuntime {
    val result = AtomicReference<JSONObject?>()
    val completed = CountDownLatch(1)
    @Volatile var startedNanos: Long = 0
    @Volatile var firstAcquireNanos: Long = 0
    @Volatile var sampledPeakPssBytes: Long = 0
    @Volatile var sampledPeakJavaHeapBytes: Long = 0
    private val samplingLock = Any()
    private var sampling = false
    private val memoryHandler by lazy { Handler(Looper.getMainLooper()) }
    private val memorySample = object : Runnable {
        override fun run() {
            synchronized(samplingLock) {
                if (!sampling) return
                val memory = android.os.Debug.MemoryInfo(); android.os.Debug.getMemoryInfo(memory)
                sampledPeakPssBytes = maxOf(sampledPeakPssBytes, memory.totalPss.toLong() * 1024)
                sampledPeakJavaHeapBytes = maxOf(sampledPeakJavaHeapBytes, Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory())
                memoryHandler.postDelayed(this, 20)
            }
        }
    }
    fun beginSampling() { synchronized(samplingLock) { startedNanos = System.nanoTime(); sampling = true; memorySample.run() } }
    fun stopSampling() { synchronized(samplingLock) { sampling = false; memoryHandler.removeCallbacks(memorySample) } }
    fun fail(code: String) {
        stopSampling()
        if (result.compareAndSet(null, JSONObject().put("result", "failed").put("code", code))) completed.countDown()
    }
}

class NativeProbePackage : ReactPackage {
    override fun createNativeModules(context: ReactApplicationContext): List<NativeModule> = listOf(NativeProbeModule(context))
    override fun createViewManagers(context: ReactApplicationContext): List<ViewManager<*, *>> = emptyList()
}

class NativeProbeModule(context: ReactApplicationContext) : ReactContextBaseJavaModule(context) {
    private val queue = Handler(Looper.getMainLooper())
    private data class Owned(val delay: Long, var work: Runnable? = null, var inspection: Promise? = null, var releasing: Boolean = false)
    private val handles = mutableMapOf<Int, Owned>()
    private val waiting = ArrayDeque<() -> Unit>()
    private var next = 0
    private var acquired = 0
    private var released = 0
    private var releasing = 0
    private var frames = 0
    private var accepted = 0
    private var acknowledged = 0
    private var maxActive = 0
    private var maxQueued = 0
    override fun getName() = "NativeProbe"
    private fun reject(promise: Promise, code: String) { promise.reject(code, code) }
    @ReactMethod fun acquire(delay: Double, promise: Promise) { queue.post {
        if (!delay.isFinite() || delay < 0 || delay > 6000 || handles.size >= 2) reject(promise, "admission_invalid")
        else {
            if (ProbeRuntime.firstAcquireNanos == 0L) ProbeRuntime.firstAcquireNanos = System.nanoTime()
            val token = ++next; handles[token] = Owned(delay.toLong()); acquired++; promise.resolve(token)
        }
    } }
    @ReactMethod fun inspect(token: Double, promise: Promise) { queue.post {
        val owned = handles[token.toInt()]
        if (token != token.toInt().toDouble() || owned == null || owned.inspection != null || owned.releasing) reject(promise, "handle_invalid")
        else {
            owned.inspection = promise
            val work = Runnable { owned.work = null; owned.inspection = null; promise.resolve("ready") }
            owned.work = work; queue.postDelayed(work, owned.delay)
        }
    } }
    @ReactMethod fun release(token: Double, promise: Promise) { queue.post {
        val owned = handles[token.toInt()]
        if (token != token.toInt().toDouble() || owned == null || owned.releasing) reject(promise, "handle_invalid")
        else {
            owned.releasing = true; owned.work?.let { queue.removeCallbacks(it) }; owned.work = null
            owned.inspection?.resolve("cancelled"); owned.inspection = null; releasing++
            // Keep the handle owned until asynchronous native acknowledgment.
            queue.postDelayed({ handles.remove(token.toInt()); released++; releasing--; promise.resolve(null) }, 50)
        }
    } }
    @ReactMethod fun stats(promise: Promise) { queue.post {
        val map = Arguments.createMap()
        for ((key, value) in mapOf("acquired" to acquired, "released" to released, "active" to handles.size,
            "inspecting" to handles.values.count { it.work != null }, "unresolved_inspections" to handles.values.count { it.inspection != null },
            "releasing" to releasing, "accepted_frames" to accepted, "acknowledged_frames" to acknowledged,
            "max_active" to maxActive, "max_queued" to maxQueued, "active_frames" to frames, "queued_frames" to waiting.size)) map.putInt(key, value)
        promise.resolve(map)
    } }
    @ReactMethod fun reset(promise: Promise) { queue.post {
        if (handles.isNotEmpty() || frames != 0 || waiting.isNotEmpty()) reject(promise, "busy")
        else { acquired = 0; released = 0; accepted = 0; acknowledged = 0; maxActive = 0; maxQueued = 0; promise.resolve(null) }
    } }
    private fun drain() { while (frames < 2 && waiting.isNotEmpty()) waiting.removeFirst().invoke() }
    @ReactMethod fun frame(value: String, promise: Promise) { queue.post {
        val rejection = ProbeAdmission.rejectFrame(value)
        if (rejection != null) { reject(promise, rejection); return@post }
        if (frames == 2 && waiting.size == 4) { reject(promise, "backpressure"); return@post }
        accepted++
        val work = {
            frames++; maxActive = maxOf(maxActive, frames)
            queue.postDelayed({ frames--; acknowledged++; promise.resolve("ack"); drain() }, 100)
            Unit
        }
        if (frames < 2) work() else { waiting.addLast(work); maxQueued = maxOf(maxQueued, waiting.size) }
    } }
    @ReactMethod fun report(value: String) { queue.post {
        try {
            if (value.toByteArray(StandardCharsets.UTF_8).size >= 65536) { ProbeRuntime.fail("result_limit"); return@post }
            val parsed = JSONObject(value)
            if (parsed.optString("schema") != "healthmd.candidate_host_probe" || parsed.optInt("version") != 1 ||
                parsed.optString("result") !in setOf("passed", "failed")) { ProbeRuntime.fail("result_schema"); return@post }
            if (handles.isNotEmpty() || frames != 0 || waiting.isNotEmpty()) { ProbeRuntime.fail("cleanup_pending"); return@post }
            // In-memory only; the instrumentation harness validates and emits the allowlisted result.
            ProbeRuntime.stopSampling()
            if (ProbeRuntime.result.compareAndSet(null, parsed)) ProbeRuntime.completed.countDown()
        } catch (_: Exception) { ProbeRuntime.fail("result_schema") }
    } }
    override fun invalidate() {
        queue.post {
            if (handles.isNotEmpty() || frames != 0 || waiting.isNotEmpty()) ProbeRuntime.fail("teardown_pending")
        }
        super.invalidate()
    }
}
