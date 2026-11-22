package com.healthmd.widget.glance

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Handler
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

/**
 * Regression for Play crash #430: GlanceAppWidgetReceiver claims the broadcast's pending result in
 * `super.onDeleted`, so the widget receiver's own `goAsync()` returned null and `finish()` crashed
 * with a NullPointerException on the IO dispatcher.
 */
@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class ReceiverWorkTest {
    private val context = ApplicationProvider.getApplicationContext<Context>()

    @Test fun workRunsWithoutCrashingWhenGlanceAlreadyClaimedThePendingResult() {
        var claimedByGlance: BroadcastReceiver.PendingResult? = null
        var secondClaim: BroadcastReceiver.PendingResult? = null
        var job: Job? = null
        var ran = false
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                // Mirrors GlanceAppWidgetReceiver.onDeleted, which calls goAsync() itself.
                claimedByGlance = goAsync()
                secondClaim = goAsync()
                job = launchReceiverWork(Dispatchers.Unconfined) { ran = true }
                claimedByGlance?.finish()
            }
        }

        deliver(receiver, "com.healthmd.test.GLANCE_CLAIMED_RESULT")

        assertThat(claimedByGlance).isNotNull()
        assertThat(secondClaim).isNull()
        assertThat(ran).isTrue()
        assertThat(job!!.isCompleted).isTrue()
        assertThat(job!!.isCancelled).isFalse()
    }

    @Test fun workFinishesTheBroadcastWhenItOwnsThePendingResult() {
        var job: Job? = null
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                resultCode = 7
                // The ordered result only reaches the caller once the claimed result is finished.
                job = launchReceiverWork(Dispatchers.Unconfined) { }
            }
        }
        var receivedCode: Int? = null
        val caller = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                receivedCode = resultCode
            }
        }
        val action = "com.healthmd.test.OWNED_RESULT"
        context.registerReceiver(receiver, IntentFilter(action), Context.RECEIVER_NOT_EXPORTED)
        try {
            context.sendOrderedBroadcast(Intent(action).setPackage(context.packageName), null,
                caller, Handler(Looper.getMainLooper()), 0, null, null)
            shadowOf(Looper.getMainLooper()).idle()
            assertThat(job!!.isCompleted).isTrue()
            assertThat(job!!.isCancelled).isFalse()
            assertThat(receivedCode).isEqualTo(7)
        } finally {
            context.unregisterReceiver(receiver)
        }
    }

    private fun deliver(receiver: BroadcastReceiver, action: String) {
        context.registerReceiver(receiver, IntentFilter(action), Context.RECEIVER_NOT_EXPORTED)
        try {
            context.sendBroadcast(Intent(action).setPackage(context.packageName))
            shadowOf(Looper.getMainLooper()).idle()
        } finally {
            context.unregisterReceiver(receiver)
        }
    }
}
