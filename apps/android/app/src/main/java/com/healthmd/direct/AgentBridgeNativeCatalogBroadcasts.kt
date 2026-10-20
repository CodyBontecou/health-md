package com.healthmd.direct

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import androidx.core.content.ContextCompat
import java.util.concurrent.atomic.AtomicBoolean

/** Native SDK registration owned by the admitted foreground service. The receiver latches metadata
 * invalidation only; it never samples health/settings, opens issuer files, or starts a service. */
internal class AgentBridgeNativeCatalogBroadcasts(private val context: Context, changed: () -> Unit) : AutoCloseable {
    private val closed = AtomicBoolean(false)
    private val receiver = object : BroadcastReceiver() {
        override fun onReceive(context: Context, intent: Intent) {
            if (!closed.get() && (intent.action == Intent.ACTION_TIMEZONE_CHANGED || intent.action == Intent.ACTION_USER_UNLOCKED)) changed()
        }
    }

    init {
        ContextCompat.registerReceiver(context, receiver, IntentFilter().apply {
            addAction(Intent.ACTION_TIMEZONE_CHANGED)
            addAction(Intent.ACTION_USER_UNLOCKED) // First unlock, never ordinary screen lock.
        }, ContextCompat.RECEIVER_NOT_EXPORTED)
    }

    override fun close() {
        if (closed.compareAndSet(false, true)) context.unregisterReceiver(receiver)
    }
}
