package com.healthmd.diagnostics

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import java.io.File
import java.io.IOException

/** Native lifetime adapter. Unit tests and pre-initialization callers remain no-op. */
object Diagnostics {
    @Volatile private var instance: DiagnosticStore? = null

    @Synchronized
    fun initialize(context: Context): DiagnosticStore {
        instance?.let { return it }
        val store = DiagnosticStore(File(context.noBackupFilesDir, "diagnostics-v1"))
        instance = store
        record(DiagnosticEventID.APP_STARTED)
        (context.applicationContext as? Application)?.registerActivityLifecycleCallbacks(object : Application.ActivityLifecycleCallbacks {
            override fun onActivityResumed(activity: Activity) { record(DiagnosticEventID.NATIVE_LIFECYCLE, mapOf(DiagnosticField.NATIVE_CALLBACK to DiagnosticValue.Text("android_activity_resumed"))) }
            override fun onActivityPaused(activity: Activity) { record(DiagnosticEventID.NATIVE_LIFECYCLE, mapOf(DiagnosticField.NATIVE_CALLBACK to DiagnosticValue.Text("android_activity_paused"))) }
            override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
            override fun onActivityStarted(activity: Activity) = Unit
            override fun onActivityStopped(activity: Activity) = Unit
            override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
            override fun onActivityDestroyed(activity: Activity) = Unit
        })
        return store
    }

    fun record(event: DiagnosticEventID, fields: Map<DiagnosticField, DiagnosticValue> = emptyMap()) {
        val store = instance ?: return
        val caller = Throwable().stackTrace.firstOrNull { it.className.startsWith("com.healthmd.") && !it.className.startsWith("com.healthmd.diagnostics.") }
        val source = "HealthMd/${caller?.fileName ?: "Diagnostics.kt"}:${caller?.lineNumber?.coerceAtLeast(0) ?: 0}"
        store.record(event, fields, source)
    }
    fun peerFields(name: String): Map<DiagnosticField, DiagnosticValue> = instance?.peerFields(name) ?: emptyMap()

    fun errorFields(error: Throwable): Map<DiagnosticField, DiagnosticValue> = mapOf(
        DiagnosticField.ERROR_DOMAIN to DiagnosticValue.Text(when (error) {
            is SecurityException -> "SecurityException"
            is IOException -> "IOException"
            else -> "unknown"
        }),
    )
}
