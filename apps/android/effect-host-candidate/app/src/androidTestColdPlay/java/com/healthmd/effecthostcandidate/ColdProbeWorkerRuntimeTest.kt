package com.healthmd.effecthostcandidate

import android.app.job.JobScheduler
import android.os.Build
import android.os.Bundle
import android.os.Process
import android.os.SystemClock
import android.provider.Settings
import androidx.test.platform.app.InstrumentationRegistry
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.work.Data
import androidx.work.OneTimeWorkRequestBuilder
import androidx.work.WorkManager
import org.junit.Test
import org.junit.runner.RunWith
import org.junit.Assert.*
import org.json.JSONObject
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class ColdProbeWorkerRuntimeTest {
    @Test fun enqueueOnly() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        assertEquals("com.healthmd.effecthost.androidcandidate.cold.play", context.packageName)
        val args = InstrumentationRegistry.getArguments()
        val text = args.getString("case_sequence") ?: error("case_required")
        assertTrue(text.matches(Regex("[0-4]")))
        val sequence = text.toInt(); val submitted = SystemClock.elapsedRealtime()
        val boot = Settings.Global.getInt(context.contentResolver, Settings.Global.BOOT_COUNT, -1)
        assertEquals("same_boot", ColdEvidence.sameBoot(boot, boot))
        val schema = if (sequence == 1) "wrong" else "healthmd.candidate_cold_worker"
        val ttl = if (sequence == 2) 0 else 30000
        val payload = "{\"schema\":\"$schema\",\"version\":1,\"case_id\":\"${coldCases[sequence]}\",\"sequence\":$sequence,\"ttl_ms\":$ttl}"
        val data = Data.Builder().putString("payload", payload).putString("submitted_elapsed_ms", submitted.toString()).build()
        val works = (0 until if (sequence == 4) 2 else 1).map {
            OneTimeWorkRequestBuilder<ColdProbeWorker>().setInitialDelay(10000, TimeUnit.MILLISECONDS).setInputData(data).build()
        }
        val (run, controller) = ColdRegistry.issue(context, works.map { it.id.toString() to sequence }, args.getString("preserved_run_nonce"))
        // Enqueue only: WorkManager/SystemJobService owns actual later invocation; never directly invoke Worker.
        WorkManager.getInstance(context).enqueue(works).result.get(5, TimeUnit.SECONDS)
        val schedulerDeadline = SystemClock.elapsedRealtime() + 5000
        check(Build.VERSION.SDK_INT >= 34) { "scheduler_binding_invalid" }
        val namespace = "androidx.work.systemjobscheduler" // Locked2.10 diagnostic, not public AndroidX contract.
        val scheduler = context.getSystemService(JobScheduler::class.java).forNamespace(namespace)
        // Private diagnostic: AOSP multiuser UID layout; no hidden UserHandle calls.
        val ownUid: Int = Process.myUid()
        check(ownUid >= 0 && ownUid == context.applicationInfo.uid) { "scheduler_binding_invalid" }
        val userId: Int = ownUid / 100000
        check(userId >= 0) { "scheduler_binding_invalid" }
        var descriptors: org.json.JSONArray? = null
        while (SystemClock.elapsedRealtime() < schedulerDeadline && descriptors == null) {
            val jobs = scheduler.allPendingJobs.filter {
                it.service.packageName == context.packageName &&
                    it.service.className == "androidx.work.impl.background.systemjob.SystemJobService" &&
                    it.extras.getString("EXTRA_WORK_SPEC_ID") in works.map { w -> w.id.toString() }
            }
            if (jobs.size == works.size) {
                val ordered = works.map { work -> jobs.filter { it.extras.getString("EXTRA_WORK_SPEC_ID") == work.id.toString() } }
                check(ordered.all { it.size == 1 }) { "scheduler_binding_invalid" }
                check(jobs.map { it.id }.toSet().size == jobs.size) { "scheduler_binding_invalid" }
                descriptors = org.json.JSONArray(ordered.map { matches ->
                    val job = matches.single()
                    check(job.id >= 0 && job.extras.get("EXTRA_WORK_SPEC_GENERATION") == 0 &&
                        job.extras.get("EXTRA_IS_PERIODIC") == false) { "scheduler_binding_invalid" }
                    JSONObject().put("work_id", job.extras.getString("EXTRA_WORK_SPEC_ID"))
                        .put("job_id", job.id).put("generation", 0).put("service_package", job.service.packageName)
                        .put("service_class", job.service.className).put("namespace", namespace).put("user_id", userId)
                })
            } else {
                check(jobs.size <= works.size) { "scheduler_binding_invalid" }
                Thread.sleep(25)
            }
        }
        check(descriptors != null) { "scheduler_binding_unobserved" }
        val raw = JSONObject().put("schema", "healthmd.candidate_cold_worker_setup").put("version", 1)
            .put("case_id", coldCases[sequence]).put("sequence", sequence).put("run_nonce", run)
            .put("controller_nonce", controller).put("setup_pid", Process.myPid()).put("boot_count", boot)
            .put("submitted_elapsed_ms", submitted.toString()).put("work_ids", org.json.JSONArray(works.map { it.id.toString() }))
            .put("api", Build.VERSION.SDK_INT).put("user_id", userId).put("job_descriptors", descriptors).toString()
        assertTrue(raw.toByteArray().size <= 2048)
        instrumentation.sendStatus(0, Bundle().apply { putString("cold_setup", raw) })
    }

    @Test fun immutableAdmissionLiterals() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val raw = context.assets.open("cold-worker-v1.json").bufferedReader().use { it.readText() }
        val fixture = JSONObject(raw)
        val negatives = fixture.getJSONArray("admission_negative_cases")
        repeat(negatives.length()) { n ->
            val item = negatives.getJSONObject(n)
            // Exercise raw stimuli without native engine/resource/WorkManager invocation.
            val wd = if (item.has("work_data")) item.getJSONObject("work_data") else JSONObject()
                .put("payload", if (item.has("raw_payload")) item.getString("raw_payload") else "x".repeat(4097))
                .put("submitted_elapsed_ms", "100000")
            val builder = Data.Builder()
            wd.keys().forEach { key ->
                val v = wd.get(key)
                when(v) { is String -> builder.putString(key, v); is Int -> builder.putInt(key, v); is Boolean -> builder.putBoolean(key, v); else -> builder.putString(key, "invalid") }
            }
            try {
                val (frame, submitted) = ColdParser.data(builder.build())
                if (item.has("literal_start_elapsed_ms")) ColdParser.clock(submitted, item.getString("literal_start_elapsed_ms").toLong(), frame.ttl)
                fail("unexpected_admission")
            }
            catch (e: ColdRefusal) { assertEquals(item.getJSONObject("expected").getString("code"), e.code) }
        }
        assertEquals(Long.MAX_VALUE, ColdParser.unsigned("9223372036854775807", Long.MAX_VALUE))
        for (v in listOf("9223372036854775808", "-0", "1.0", "1e0", "01")) {
            try { ColdParser.unsigned(v, Long.MAX_VALUE); fail("unexpected_admission") } catch (_: ColdRefusal) {}
        }
    }

    @Test fun immutableSupplementalNativeBoundaries() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val raw = context.assets.open("cold-worker-v1.json").bufferedReader().use { it.readText() }
        val items = JSONObject(raw).getJSONArray("supplemental_interface_cases")
        val observed = mutableSetOf<String>()
        repeat(items.length()) { n ->
            val item = items.getJSONObject(n); val id = item.getString("case_id")
            val input = item.getJSONObject("input"); val expected = item.getJSONObject("expected")
            when(id) {
                "boot_changed_same_elapsed", "boot_witness_unavailable" -> {
                    val before = if(input.isNull("before_boot_count")) null else input.getInt("before_boot_count")
                    val after = if(input.isNull("after_boot_count")) null else input.getInt("after_boot_count")
                    assertEquals(expected.getString("native_test_result"), ColdEvidence.sameBoot(before, after))
                    assertFalse(expected.getBoolean("same_boot_test_proof"))
                    if(id == "boot_changed_same_elapsed") {
                        // Explicit counterexample: raw elapsed frame accepts even after a different boot.
                        ColdParser.clock(input.getString("submitted_elapsed_ms").toLong(), input.getString("now_elapsed_ms").toLong(), 30000)
                        assertFalse(expected.getBoolean("runtime_reboot_replay_rejection_claim"))
                    }
                    observed.add(id)
                }
                "release_failed_truthful_incomplete" -> {
                    val counts = input.getJSONObject("actual_counts")
                    val complete = ColdEvidence.cleanupComplete(counts.getInt("acquired"), counts.getInt("released"), counts.getInt("unresolved_inspections"), false)
                    assertFalse(complete)
                    assertEquals(expected.getString("phase"), if(complete) "completed" else "incomplete")
                    assertEquals(expected.getInt("ack"), if(complete) 1 else 0)
                    assertEquals(expected.getString("code"), if(complete) "ready" else "cleanup_unverified")
                    assertEquals(1, counts.getInt("active")); assertEquals(0, counts.getInt("released"))
                    assertFalse(expected.getBoolean("work_success")); observed.add(id)
                }
                "stale_control_nonce" -> {
                    assertEquals(expected.getString("code"), ColdEvidence.controlNonce(input.getString("issued_controller_nonce"), input.getString("sent_controller_nonce")))
                    // Actual control uses the nonce gate before looking up work or calling cancelWorkById.
                    val refusal = JSONObject(ColdRegistry.control("cancel", "00000000-0000-4000-8000-000000000001", input.getString("sent_controller_nonce")))
                    assertEquals("control_invalid", refusal.getString("code")); assertTrue(refusal.isNull("work_id"))
                    observed.add(id)
                }
                "worker_process_died_before_control" -> {
                    assertFalse(ColdEvidence.sameProcess(input.getString("active_process_nonce"), input.getString("receiver_process_nonce")))
                    assertFalse(expected.getBoolean("cleanup_ack_claim")); assertFalse(expected.getBoolean("restart_as_ack")); observed.add(id)
                }
                "cancel_dispatch_not_cleanup" -> {
                    assertFalse(ColdEvidence.publishedComplete(input.getString("native_phase"), input.getInt("native_ack")))
                    assertFalse(expected.getBoolean("cleanup_ack_claim")); assertFalse(expected.getBoolean("private_completion")); assertTrue(expected.getBoolean("continue_bounded_poll")); observed.add(id)
                }
                // These two execute against the original JS mailbox at every reviewed registration;
                // they cannot be truthfully counted as native Kotlin tests.
                "forged_ticket_no_properties", "foreign_terminal_no_properties" -> Unit
                else -> fail("unknown_supplemental")
            }
        }
        assertEquals(6, observed.size)
    }
}
