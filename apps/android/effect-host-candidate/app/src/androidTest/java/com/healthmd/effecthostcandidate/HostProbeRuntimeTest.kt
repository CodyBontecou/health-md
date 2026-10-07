package com.healthmd.effecthostcandidate

import android.content.pm.ApplicationInfo
import android.os.Bundle
import androidx.test.platform.app.InstrumentationRegistry
import org.json.JSONObject
import org.junit.Assert.*
import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

class HostProbeRuntimeTest {
    @Test fun packagedOfflineFreshProcessAndAcknowledgedTeardown() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val application = context.applicationContext as HostProbeApplication
        assertEquals("com.healthmd.effecthost.androidcandidate.play", context.packageName)
        assertEquals(0, context.applicationInfo.flags and ApplicationInfo.FLAG_DEBUGGABLE)
        val permissions = context.packageManager.getPackageInfo(context.packageName, android.content.pm.PackageManager.GET_PERMISSIONS).requestedPermissions.orEmpty()
        assertFalse(permissions.any { it == "android.permission.INTERNET" || it.startsWith("android.permission.health.") })
        assertTrue(ProbeRuntime.completed.await(30, TimeUnit.SECONDS))
        val result = ProbeRuntime.result.get() ?: error("missing_result")
        assertEquals("passed", result.optString("result"))
        assertEquals(10, result.getJSONArray("observations").length())
        val fixture = JSONObject(context.assets.open("host-probe-v1.json").bufferedReader().use { it.readText() })
        val observations = result.getJSONArray("observations")
        for (i in 0 until fixture.getJSONArray("cases").length()) {
            val expectedCase = fixture.getJSONArray("cases").getJSONObject(i)
            val actual = (0 until observations.length()).map { observations.getJSONObject(it) }
                .single { it.getString("case_id") == expectedCase.getString("case_id") }.getJSONObject("observed")
            val expected = expectedCase.getJSONObject("expected")
            for (key in expected.keys()) assertEquals("${expectedCase.getString("case_id")}:$key", expected.get(key), actual.get(key))
        }
        val destroyed = CountDownLatch(1)
        var success = false
        val started = System.nanoTime()
        application.reactHost.destroy("private_probe_complete", null) { acknowledged -> success = acknowledged; destroyed.countDown() }
        assertTrue(destroyed.await(5, TimeUnit.SECONDS)); assertTrue(success)
        application.reactHost.invalidate()
        result.put("teardown_ack", true).put("teardown_ms", (System.nanoTime() - started) / 1_000_000)
            .put("elapsed_ms", (System.nanoTime() - ProbeRuntime.startedNanos) / 1_000_000)
            .put("startup_to_first_acquire_ms", (ProbeRuntime.firstAcquireNanos - ProbeRuntime.startedNanos) / 1_000_000)
            .put("sampled_peak_pss_bytes", ProbeRuntime.sampledPeakPssBytes)
            .put("sampled_peak_java_heap_bytes", ProbeRuntime.sampledPeakJavaHeapBytes)
            .put("memory_sampling_interval_ms", 20)
            .put("java_heap_used_bytes", Runtime.getRuntime().totalMemory() - Runtime.getRuntime().freeMemory())
        // PSS/heap peaks are sampled every20ms; they are lower bounds on the true peaks.
        instrumentation.sendStatus(0, Bundle().apply { putString("healthmd_candidate_result", result.toString()) })
    }
}
