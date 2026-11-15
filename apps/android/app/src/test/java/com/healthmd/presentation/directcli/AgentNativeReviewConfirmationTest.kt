package com.healthmd.presentation.directcli

import android.app.KeyguardManager
import android.content.Context
import android.os.Looper
import android.os.UserManager
import androidx.lifecycle.*
import com.healthmd.direct.protocol.AgentBridgeErrorCode
import com.healthmd.direct.protocol.AgentBridgeException
import com.google.common.truth.Truth.assertThat
import io.mockk.*
import org.junit.*

/** Actual native confirmation lease and lifecycle callback. Only OS/Looper facts are intercepted;
 * no app/UI/device is launched and no native consent or issuer data is fabricated. */
class AgentNativeReviewConfirmationTest {
    private val context = mockk<Context>()
    private val user = mockk<UserManager>()
    private val keyguard = mockk<KeyguardManager>()
    private val lifecycle = NativeLifecycle()
    private val main = mockk<Looper>()
    @Before fun setup() {
        mockkStatic(Looper::class)
        every { Looper.getMainLooper() } returns main
        every { Looper.myLooper() } returns main
        every { context.applicationContext } returns context
        every { context.isDeviceProtectedStorage } returns false
        every { context.getSystemService(UserManager::class.java) } returns user
        every { context.getSystemService(KeyguardManager::class.java) } returns keyguard
        every { user.isUserUnlocked } returns true
        every { keyguard.isKeyguardLocked } returns false
    }
    @After fun cleanup() { unmockkStatic(Looper::class) }
    private fun rejected(block: () -> Unit) {
        try { block(); Assert.fail("Expected native policy rejection") }
        catch (failure: AgentBridgeException) { assertThat(failure.code).isEqualTo(AgentBridgeErrorCode.APPROVAL_REQUIRED) }
    }
    @Test fun `only resumed unlocked unprotected main native confirmation creates lease`() {
        rejected { AgentNativeReviewConfirmation.fromNativeConfirmation(context, lifecycle, true) { 0L } }
        every { Looper.myLooper() } returns null
        rejected { AgentNativeReviewConfirmation.fromNativeConfirmation(context, lifecycle, false) { 0L } }
        every { Looper.myLooper() } returns main
        lifecycle.state = Lifecycle.State.STARTED
        rejected { AgentNativeReviewConfirmation.fromNativeConfirmation(context, lifecycle, false) { 0L } }
        lifecycle.state = Lifecycle.State.RESUMED
        every { keyguard.isKeyguardLocked } returns true
        rejected { AgentNativeReviewConfirmation.fromNativeConfirmation(context, lifecycle, false) { 0L } }
        assertThat(lifecycle.observers).isEmpty()
    }
    @Test fun `worker checks are allowed but paused lease never revives on resume`() {
        val lease = AgentNativeReviewConfirmation.fromNativeConfirmation(context, lifecycle, false) { 0L }
        every { Looper.myLooper() } returns null
        lease.requireCurrent(false)
        lifecycle.event(Lifecycle.Event.ON_PAUSE)
        rejected { lease.requireCurrent(false) }
        lifecycle.event(Lifecycle.Event.ON_RESUME)
        rejected { lease.requireCurrent(false) }
        lease.close()
        assertThat(lifecycle.observers).isEmpty()
    }
    @Test fun `unknown or newly protected configuration permanently invalidates confirmation`() {
        for (protected in listOf<Boolean?>(null, true)) {
            val lease = AgentNativeReviewConfirmation.fromNativeConfirmation(context, lifecycle, false) { 0L }
            rejected { lease.requireCurrent(protected) }
            rejected { lease.requireCurrent(false) }
            lease.close()
        }
    }
    @Test fun `worker observes device lock and explicit cancellation before native decision`() {
        val lease = AgentNativeReviewConfirmation.fromNativeConfirmation(context, lifecycle, false) { 0L }
        every { user.isUserUnlocked } returns false
        rejected { lease.requireCurrent(false) }
        every { user.isUserUnlocked } returns true
        rejected { lease.requireCurrent(false) }
        lease.close()
        val next = AgentNativeReviewConfirmation.fromNativeConfirmation(context, lifecycle, false) { 0L }
        next.invalidate()
        rejected { next.requireCurrent(false) }
        next.close()
        assertThat(lifecycle.observers).isEmpty()
    }
    @Test fun `confirmation deadline starts at native tap and never renews after worker delay`() {
        var time = 10L
        val lease = AgentNativeReviewConfirmation.fromNativeConfirmation(context, lifecycle, false) { time }
        every { Looper.myLooper() } returns null
        time += 29_999_999_999L
        lease.requireCurrent(false)
        time++
        rejected { lease.requireCurrent(false) }
        time = 10L
        rejected { lease.requireCurrent(false) }
        lease.close()
    }
    private class NativeLifecycle : Lifecycle() {
        var state = State.RESUMED
        val observers = mutableSetOf<LifecycleObserver>()
        override val currentState: State get() = state
        override fun addObserver(observer: LifecycleObserver) { observers += observer }
        override fun removeObserver(observer: LifecycleObserver) { observers -= observer }
        fun event(event: Event) {
            state = event.targetState
            val owner = object : LifecycleOwner { override val lifecycle: Lifecycle get() = this@NativeLifecycle }
            observers.toList().forEach { (it as LifecycleEventObserver).onStateChanged(owner, event) }
        }
    }
}
