import com.healthmd.data.receivercoverage.*
import java.io.File
import java.io.IOException
import java.time.Instant
import java.util.Base64
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.*
import okhttp3.*
import okio.Buffer
import okio.BufferedSource
import okio.Source
import okio.Timeout
import okio.buffer

private fun hex(s: String) = s.chunked(2).map { it.toInt(16).toByte() }.toByteArray()

private class SyntheticCall(private val wire: Request, private val script: Script) : Call {
    @Volatile private var cancelled = false
    @Volatile private var executed = false
    val released = CountDownLatch(1)
    override fun request() = wire
    override fun isExecuted() = executed
    override fun isCanceled() = cancelled
    override fun timeout() = Timeout()
    override fun clone(): Call = SyntheticCall(wire, script)
    override fun execute(): Response = error("Asynchronous transport required")
    override fun cancel() { cancelled = true; released.countDown() }
    override fun enqueue(callback: Callback) {
        executed = true
        script.started.complete(Unit)
        if (script.mode == "hang") return
        if (script.mode == "unavailable") { callback.onFailure(this, IOException("private server error")); return }
        val body = object : ResponseBody() {
            override fun contentType(): MediaType? = null
            override fun contentLength() = script.contentLength
            private val source: BufferedSource = object : Source {
                val bytes = Buffer().write(script.bytes)
                override fun timeout() = Timeout()
                override fun close() { script.closed = true }
                override fun read(sink: Buffer, byteCount: Long): Long {
                    if (script.mode == "hang_body") {
                        script.reading.complete(Unit)
                        check(released.await(2, TimeUnit.SECONDS)) { "Cancelled read did not stop" }
                        throw IOException("cancelled synthetic read")
                    }
                    return bytes.read(sink, minOf(byteCount, 1024))
                }
            }.buffer()
            override fun source(): BufferedSource = source
        }
        val response = Response.Builder().request(wire).protocol(Protocol.HTTP_1_1)
            .code(script.status).message("synthetic").body(body)
            .apply { script.media?.let { header("Content-Type", it) } }.build()
        // Callback reading runs outside the coroutine, matching OkHttp's Dispatcher behavior.
        Thread { callback.onResponse(this, response) }.apply { isDaemon = true }.start()
    }
}
private class Script(
    val bytes: ByteArray = byteArrayOf(), val status: Int = 200, val media: String? = "application/json",
    val mode: String = "body", val contentLength: Long = -1,
) : Call.Factory {
    val started = CompletableDeferred<Unit>()
    val reading = CompletableDeferred<Unit>()
    @Volatile var closed = false
    var count = 0
    lateinit var call: SyntheticCall
    override fun newCall(request: Request): Call { count++; call = SyntheticCall(request, this); return call }
}
private fun fallback(outcome: ReceiverCoverageOutcome) { check(outcome is ReceiverCoverageOutcome.FallbackFull) }

fun main(args: Array<String>) = runBlocking {
    val preflight = /*PREPARE*/!!
    val request = ReceiverCoverageRequest.freeze(preflight, "occurrence-1", listOf("2026-03-06", "2026-03-07", "2026-03-08"), Instant.parse("2026-03-09T08:00:00Z"))
    for (line in File(args[0]).readLines()) {
        val columns = line.split('\t')
        val bytes = Base64.getDecoder().decode(columns[2])
        val accepted = columns[1] == "valid"
        try {
            val evidence = ReceiverCoverageEvidence.parse(bytes, request)
            check(accepted) { "Invalid parser evidence: ${columns[0]}" }
            println(columns[0] + "\t" + Base64.getEncoder().encodeToString(evidence.normalizedResponse()))
        } catch (e: ReceiverCoveragePreflight.BoundaryException) {
            check(!accepted) { "Rejected valid parser evidence: ${columns[0]}" }
            println(columns[0] + "\tinvalid")
        }
        val script = Script(bytes)
        val outcome = ReceiverCoverageHTTPClient(script).query(request)
        if (accepted) {
            check(outcome is ReceiverCoverageOutcome.Valid)
            check(outcome.evidence.completedDates() == ReceiverCoverageEvidence.parse(bytes, request).completedDates())
        } else fallback(outcome)
        check(script.count == 1 && script.closed)
        check(script.call.request().url.toString() == request.url.toString())
        check(script.call.request().method == "POST")
        check(script.call.request().header("Authorization") == "Bearer synthetic")
        check(script.call.request().header("X-Tenant") == "synthetic")
        check(script.call.request().header("Accept") == "application/json")
        val body = Buffer(); script.call.request().body!!.writeTo(body)
        check(body.readByteArray().contentEquals(request.body()))
    }
    val valid = File(args[1]).readBytes()
    for (status in listOf(204,301,302,307,308,401,429,500)) {
        val script = Script(valid, status = status)
        fallback(ReceiverCoverageHTTPClient(script).query(request)); check(script.count == 1 && script.closed)
    }
    for (media in listOf(null,"text/html","application/jsonp")) {
        fallback(ReceiverCoverageHTTPClient(Script(valid, media = media)).query(request))
    }
    fallback(ReceiverCoverageHTTPClient(Script(mode = "unavailable")).query(request))
    for (length in listOf(-1L,65537L)) {
        val script = Script(ByteArray(65537) { 32 }, contentLength = length)
        fallback(ReceiverCoverageHTTPClient(script).query(request)); check(script.call.isCanceled() && script.closed)
    }
    for (mode in listOf("hang","hang_body")) {
        val script = Script(mode = mode)
        val task = async { ReceiverCoverageHTTPClient(script).query(request) }
        script.started.await()
        if (mode == "hang_body") script.reading.await()
        task.cancel()
        try { task.await(); error("Cancellation became fallback") } catch (_: CancellationException) {}
        check(script.call.isCanceled() && script.count == 1)
        if (mode == "hang_body") withTimeout(1000) { while (!script.closed) yield() }
    }
    val never = Script()
    val cancelled = async {
        currentCoroutineContext().cancel()
        ReceiverCoverageHTTPClient(never).query(request)
    }
    try { cancelled.await(); error("Pre-cancelled query ran") } catch (_: CancellationException) {}
    check(never.count == 0)
    for (mode in listOf("hang","hang_body")) {
        val script = Script(mode = mode)
        fallback(ReceiverCoverageHTTPClient(script, deadlineMillis = 50).query(request))
        check(script.call.isCanceled() && script.count == 1)
        if (mode == "hang_body") withTimeout(1000) { while (!script.closed) yield() }
    }
    val isolated = ReceiverCoverageHTTPClient.isolatedClient()
    check(!isolated.followRedirects && !isolated.followSslRedirects && !isolated.retryOnConnectionFailure)
    check(isolated.authenticator === Authenticator.NONE && isolated.proxyAuthenticator === Authenticator.NONE)
    check(isolated.cookieJar === CookieJar.NO_COOKIES && isolated.cache == null)
    check(isolated.interceptors.isEmpty() && isolated.networkInterceptors.isEmpty() && isolated.callTimeoutMillis == 10000)
    isolated.dispatcher.executorService.shutdown()
    isolated.connectionPool.evictAll()
    println("transport\tok")
}
