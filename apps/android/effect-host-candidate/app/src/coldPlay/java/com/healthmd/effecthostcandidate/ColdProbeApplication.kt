package com.healthmd.effecthostcandidate

import android.app.Application
import android.app.Activity
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import com.facebook.react.ReactApplication
import com.facebook.react.ReactHost
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint
import com.facebook.react.defaults.DefaultReactHost
import com.facebook.react.shell.MainReactPackage
import com.facebook.react.soloader.OpenSourceMergedSoMapping
import com.facebook.soloader.SoLoader

/** No startup engine, activity, React surface, old probe or production state. */
class ColdProbeApplication : Application(), ReactApplication {
    override val reactHost: ReactHost by lazy {
        DefaultReactHost.getDefaultReactHost(this,
            listOf(MainReactPackage(), ColdProbePackage()),
            jsBundleAssetPath = "cold-worker.android.bundle", useDevSupport = false,
            exceptionHandler = { ColdRegistry.engineFailed() })
    }
    private var started = false
    override fun onCreate() {
        super.onCreate()
        ColdRegistry.initialize(this)
        registerActivityLifecycleCallbacks(object : ActivityLifecycleCallbacks {
            override fun onActivityCreated(a: Activity, b: Bundle?) { ColdRegistry.activityCreated() }
            override fun onActivityStarted(a: Activity) {}
            override fun onActivityResumed(a: Activity) {}
            override fun onActivityPaused(a: Activity) {}
            override fun onActivityStopped(a: Activity) {}
            override fun onActivitySaveInstanceState(a: Activity, b: Bundle) {}
            override fun onActivityDestroyed(a: Activity) {}
        })
    }
    fun startOwnedEngine(work: String) {
        Handler(Looper.getMainLooper()).post {
            // Admission can expire or stop during main-thread handoff. No late engine allocation.
            if (!ColdRegistry.current(work)) return@post
            try {
                if (!started) {
                    SoLoader.init(this, OpenSourceMergedSoMapping)
                    DefaultNewArchitectureEntryPoint.load()
                    started = true
                    reactHost.start()
                }
            } catch (_: Throwable) { ColdRegistry.engineFailed() }
        }
    }
}
