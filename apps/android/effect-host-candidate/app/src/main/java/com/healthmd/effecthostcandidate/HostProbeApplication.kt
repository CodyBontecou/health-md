package com.healthmd.effecthostcandidate

import android.app.Application
import com.facebook.react.ReactApplication
import com.facebook.react.ReactHost
import com.facebook.react.defaults.DefaultNewArchitectureEntryPoint
import com.facebook.react.defaults.DefaultReactHost
import com.facebook.react.shell.MainReactPackage
import com.facebook.react.soloader.OpenSourceMergedSoMapping
import com.facebook.soloader.SoLoader

class HostProbeApplication : Application(), ReactApplication {
    override val reactHost: ReactHost by lazy {
        DefaultReactHost.getDefaultReactHost(
            context = this,
            packageList = listOf(MainReactPackage(), NativeProbePackage()),
            jsBundleAssetPath = "index.android.bundle",
            useDevSupport = false,
            exceptionHandler = { ProbeRuntime.fail("engine_failure") },
        )
    }
    override fun onCreate() {
        super.onCreate()
        ProbeRuntime.beginSampling()
        SoLoader.init(this, OpenSourceMergedSoMapping)
        DefaultNewArchitectureEntryPoint.load()
        // Explicit private active host with no Activity or surface; not OS background/wake proof.
        reactHost.onHostResume(null)
        reactHost.start()
    }
}
