package com.healthmd.automation

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import androidx.test.core.app.ApplicationProvider
import com.google.common.truth.Truth.assertThat
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.Shadows.shadowOf
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AutomationBroadcastResultTest {
    @Test fun asynchronousOrderedResponseReachesCallerAfterReceiverDetaches() {
        val context = ApplicationProvider.getApplicationContext<Context>()
        val action = "com.healthmd.test.ASYNC_AUTOMATION_RESULT"
        val receiver = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                val pending = goAsync()
                val publish = automationResultPublisher(pending)
                Handler(Looper.getMainLooper()).post {
                    publish(2, "Unlock Health.md to run automation exports", Bundle().apply {
                        putString("failure", "PAYWALL_REQUIRED")
                    })
                    pending.finish()
                }
            }
        }
        var receivedCode: Int? = null
        var receivedMessage: String? = null
        var receivedFailure: String? = null
        val caller = object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                receivedCode = resultCode
                receivedMessage = resultData
                receivedFailure = getResultExtras(false)?.getString("failure")
            }
        }
        context.registerReceiver(receiver, IntentFilter(action), Context.RECEIVER_NOT_EXPORTED)
        try {
            context.sendOrderedBroadcast(Intent(action).setPackage(context.packageName), null,
                caller, Handler(Looper.getMainLooper()), 0, null, null)
            shadowOf(Looper.getMainLooper()).idle()
            assertThat(receivedCode).isEqualTo(2)
            assertThat(receivedMessage).isEqualTo("Unlock Health.md to run automation exports")
            assertThat(receivedFailure).isEqualTo("PAYWALL_REQUIRED")
        } finally {
            context.unregisterReceiver(receiver)
        }
    }
}
