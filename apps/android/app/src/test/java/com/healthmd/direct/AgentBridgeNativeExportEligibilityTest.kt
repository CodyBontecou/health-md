package com.healthmd.direct

import android.content.Context
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.settings.SettingsRepositoryImpl
import com.healthmd.domain.repository.NativeExportEligibilitySettings
import io.mockk.mockk
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

class AgentBridgeNativeExportEligibilityTest {
    @get:Rule val temporary = TemporaryFolder()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var owner: AgentBridgeNativeExportEligibility? = null

    @After fun close() { owner?.close(); scope.cancel() }

    private suspend fun await(condition: () -> Boolean) {
        withTimeout(5_000) { while (!condition()) delay(5) }
    }

    private fun observe(settings: Flow<NativeExportEligibilitySettings?>,
        unlocked: StateFlow<Boolean> = MutableStateFlow(false), included: Boolean = false,
        changed: () -> Unit = {}): AgentBridgeNativeExportEligibility =
        AgentBridgeNativeExportEligibility(settings, unlocked, included, changed).also { owner = it; it.start(scope) }

    @Test fun `sampling is pure while native emissions fence quota and billing changes`() = runBlocking {
        val settings = MutableStateFlow<NativeExportEligibilitySettings?>(null)
        val billing = MutableStateFlow(false)
        val reads = AtomicInteger()
        val changes = AtomicInteger()
        val native = observe(settings.onEach { reads.incrementAndGet() }, billing) { changes.incrementAndGet() }
        assertThat(native.current()).isFalse()
        settings.value = NativeExportEligibilitySettings(false, 9)
        await { native.current() }
        val before = reads.get()
        repeat(100) { assertThat(native.current()).isTrue() }
        assertThat(reads.get()).isEqualTo(before)
        settings.value = NativeExportEligibilitySettings(false, 10)
        await { !native.current() }
        billing.value = true
        await { native.current() }
        billing.value = false
        assertThat(native.current()).isFalse() // Even before the observer handles the queued emission.
        await { changes.get() >= 4 }
        native.close()
        assertThat(native.current()).isFalse()
        val stopped = changes.get()
        settings.value = NativeExportEligibilitySettings(false, 0)
        delay(20)
        assertThat(native.current()).isFalse()
        assertThat(changes.get()).isEqualTo(stopped)
    }

    @Test fun `failed storage remains unknown without hiding a known billing entitlement`() = runBlocking {
        val fail = CompletableDeferred<Unit>()
        val billing = MutableStateFlow(false)
        val values = flow<NativeExportEligibilitySettings?> {
            emit(NativeExportEligibilitySettings(false, 0))
            fail.await()
            throw IOException("synthetic storage failure")
        }
        val native = observe(values, billing)
        await { native.current() }
        fail.complete(Unit)
        await { !native.current() }
        billing.value = true
        await { native.current() }
        billing.value = false
        assertThat(native.current()).isFalse()
    }

    @Test fun `known billing does not await first private preference emission`() = runBlocking {
        val billing = MutableStateFlow(true)
        val native = observe(flow { awaitCancellation() }, billing)
        await { native.current() }
        billing.value = false
        assertThat(native.current()).isFalse()
    }

    @Test fun `included access bypasses storage but closes with its native scope`() = runBlocking {
        val native = observe(flow { error("included access must not collect settings") }, included = true)
        await { native.current() }
        scope.cancel()
        await { !native.current() }
        native.close()
        assertThat(native.current()).isFalse()
    }

    @Test fun `actual preference snapshots preserve quota transitions and reject corruption without repair`() = runBlocking {
        val store = PreferenceDataStoreFactory.create(scope = scope,
            produceFile = { temporary.newFolder().resolve("native.preferences_pb") })
        val repository = SettingsRepositoryImpl(store, mockk<Context>(relaxed = true))
        repository.setPurchased(false)
        val native = observe(repository.nativeExportEligibility)
        await { native.current() }
        repeat(10) { repository.recordFreeExportUse() }
        await { !native.current() }
        repository.resetFreeExports()
        await { native.current() }
        val key = intPreferencesKey("free_exports_used")
        store.edit { it[key] = -1 }
        await { !native.current() }
        assertThat(store.data.first()[key]).isEqualTo(-1)
        val legacy = intPreferencesKey("free_exports_remaining")
        store.edit { it.remove(key); it[legacy] = 4 }
        assertThat(repository.nativeExportEligibility.first()).isNull()
        assertThat(store.data.first()[legacy]).isEqualTo(4)
        // One atomic preference revision grants known full access, independent of corrupt quota.
        store.edit { it[booleanPreferencesKey("is_purchased")] = true }
        await { native.current() }
        assertThat(store.data.first()[legacy]).isEqualTo(4)
    }

    @Test fun `cancellation closes the cache and cannot be converted to free quota`() = runBlocking {
        val cancel = CompletableDeferred<Unit>()
        val native = observe(flow {
            emit(NativeExportEligibilitySettings(false, 0))
            cancel.await()
            throw CancellationException("native owner cancelled")
        })
        await { native.current() }
        cancel.complete(Unit)
        await { !native.current() }
        assertThat(native.current()).isFalse()
    }
}
