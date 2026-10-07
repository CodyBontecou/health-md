package com.healthmd.effecthostcandidate

import android.app.Activity
import android.os.Bundle

/** Native launcher only: no React surface, capture, navigation or permission request. */
class HostProbeActivity : Activity() {
    override fun onCreate(savedInstanceState: Bundle?) { super.onCreate(savedInstanceState) }
}
