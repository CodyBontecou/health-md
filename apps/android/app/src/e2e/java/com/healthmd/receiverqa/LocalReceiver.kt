package com.healthmd.receiverqa

import android.content.Context
import java.net.InetAddress
import java.security.KeyStore
import java.time.LocalDate
import javax.net.ssl.KeyManagerFactory
import javax.net.ssl.SSLContext
import okhttp3.mockwebserver.Dispatcher
import okhttp3.mockwebserver.MockResponse
import okhttp3.mockwebserver.MockWebServer
import okhttp3.mockwebserver.RecordedRequest
import kotlinx.serialization.json.*

/** A genuine loopback TLS/HTTP receiver; neither production client nor parser is replaced. */
class LocalReceiver(private val context: Context) {
    private val state = ReceiverQaState(context)
    private val server = MockWebServer()
    val endpoint: String get() = "https://localhost:${server.port}/upload"
    fun start() {
        val keys = KeyStore.getInstance("PKCS12")
        val password = "synthetic-fixture-only".toCharArray()
        context.assets.open("receiver_qa_localhost.p12").use { keys.load(it, password) }
        val manager = KeyManagerFactory.getInstance(KeyManagerFactory.getDefaultAlgorithm()).apply { init(keys, password) }
        val tls = SSLContext.getInstance("TLS").apply { init(manager.keyManagers, null, null) }
        server.bodyLimit = 512 * 1024
        server.useHttps(tls.socketFactory, false)
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                if (request.getHeader("Authorization") != "Bearer receiver-coverage-synthetic")
                    return MockResponse().setResponseCode(401)
                return when (request.path) {
                    "/coverage" -> coverage(request)
                    "/upload" -> upload(request)
                    else -> MockResponse().setResponseCode(404)
                }
            }
        }
        val port = state.read()["port"]?.toInt() ?: 0
        server.start(InetAddress.getByName("127.0.0.1"), port)
        state.update(mapOf("port" to server.port.toString()))
    }
    private fun coverage(request: RecordedRequest): MockResponse {
        val body = Json.parseToJsonElement(request.body.readUtf8()).jsonObject
        require(body.getValue("schema").jsonPrimitive.content == "healthmd.receiver_coverage.request")
        require(body.getValue("schema_version").jsonPrimitive.int == 1)
        state.event("coverage", body.toString())
        val cancel = state.read()["case"]?.endsWith("_cancel") == true && state.read()["cancel_sent"] != "true"
        if (cancel) {
            val manager = androidx.work.WorkManager.getInstance(context)
            val running = listOf(com.healthmd.data.scheduler.ExportScheduler.EXPORT_OCCURRENCE_TAG,
                com.healthmd.data.scheduler.ScheduledProfileScheduler.EXPORT_WORK_TAG)
                .flatMap { manager.getWorkInfosByTag(it).get(2, java.util.concurrent.TimeUnit.SECONDS) }
                .filter { it.state == androidx.work.WorkInfo.State.RUNNING }.distinctBy { it.id }
            check(running.size == 1) { "Cancellation must target one real worker" }
            val id = running.single().id
            state.update(mapOf("cancel_sent" to "true"))
            state.event("cancel_action", id.toString())
            com.healthmd.data.scheduler.ScheduledExportCancelReceiver.pendingIntent(context, id).send()
        }
        val started = System.nanoTime()
        while (state.read()["http_gate"] == "true" && System.nanoTime()-started < 60_000_000_000L) Thread.sleep(50)
        val start = LocalDate.parse(body.getValue("start").jsonPrimitive.content)
        val end = LocalDate.parse(body.getValue("end_exclusive").jsonPrimitive.content)
        val all = generateSequence(start) { it.plusDays(1) }.takeWhile { it < end }.toList()
        val completed = when (state.read()["coverage_mode"]) {
            "all" -> all
            "holes" -> all.filterIndexed { index, _ -> index !in setOf(0,14,29) }
            "none" -> emptyList()
            else -> all.filterIndexed { index, _ -> index != 1 }
        }
        val response = JsonObject(body.toMutableMap().apply {
            put("schema", JsonPrimitive("healthmd.receiver_coverage.response"))
            put("completed_dates", JsonArray(completed.map { JsonPrimitive(it.toString()) }))
        })
        return MockResponse().setHeader("Content-Type","application/json").setBody(response.toString()).also {
            if (cancel) it.setBodyDelay(1, java.util.concurrent.TimeUnit.SECONDS)
        }
    }
    private fun upload(request: RecordedRequest): MockResponse {
        val body = Json.parseToJsonElement(request.body.readUtf8()).jsonObject
        val dates = body.getValue("records").jsonArray.map { it.jsonObject.getValue("date").jsonPrimitive.content }
        state.event("upload", dates.joinToString(","))
        val fail = state.read()["fail_upload_after"]?.toIntOrNull()
        val count = state.events().count { it.getValue("kind").jsonPrimitive.content == "upload" }
        return if (fail != null && count > fail) MockResponse().setResponseCode(503)
        else {
            body.getValue("records").jsonArray.forEach { state.retain(it.jsonObject) }
            state.event("ack", dates.joinToString(","))
            MockResponse().setResponseCode(200)
        }
    }
    fun stop() = server.shutdown()
}
