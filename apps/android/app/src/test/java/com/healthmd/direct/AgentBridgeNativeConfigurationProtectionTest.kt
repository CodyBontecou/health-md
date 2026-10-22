package com.healthmd.direct

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.google.common.truth.Truth.assertThat
import com.healthmd.data.settings.SettingsRepositoryImpl
import com.healthmd.direct.protocol.*
import com.healthmd.domain.repository.NativeConfigurationProtectionObservation
import com.healthmd.domain.repository.NativeConfigurationProtectionSource
import io.mockk.mockk
import java.io.IOException
import java.util.concurrent.atomic.AtomicInteger
import kotlinx.coroutines.*
import kotlinx.coroutines.flow.*
import org.junit.After
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

@RunWith(RobolectricTestRunner::class)
@Config(sdk = [35])
class AgentBridgeNativeConfigurationProtectionTest {
    @get:Rule val temporary = TemporaryFolder()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var owner: AgentBridgeNativeConfigurationProtection? = null

    @After fun close() { owner?.close(); scope.cancel() }

    private suspend fun await(condition: () -> Boolean) {
        withTimeout(5_000) { while (!condition()) delay(5) }
    }

    private fun observe(source: NativeConfigurationProtectionSource?, changed: () -> Unit = {}): AgentBridgeNativeConfigurationProtection =
        AgentBridgeNativeConfigurationProtection(source, changed).also { owner = it; it.start(scope) }

    @Test fun samplingIsPureAndRevisionFenceRejectsQueuedImagesAcrossABA() = runBlocking {
        val values = MutableSharedFlow<NativeConfigurationProtectionObservation?>(replay = 1)
        val reads = AtomicInteger()
        val changes = AtomicInteger()
        val source = NativeConfigurationProtectionSource(values.onEach { reads.incrementAndGet() })
        val native = observe(source) { changes.incrementAndGet() }
        assertThat(native.current()).isNull()
        values.emit(NativeConfigurationProtectionObservation(false, "a"))
        await { native.current() == false }
        val before = reads.get()
        repeat(100) { assertThat(native.current()).isFalse() }
        assertThat(reads.get()).isEqualTo(before)
        val changedBefore = changes.get()
        source.invalidate("b")
        source.invalidate("c") // Final persisted value may equal A, but revision must still match C.
        assertThat(changes.get()).isEqualTo(changedBefore + 2)
        assertThat(native.current()).isNull()
        values.emit(NativeConfigurationProtectionObservation(true, "b"))
        delay(20)
        assertThat(native.current()).isNull()
        values.emit(NativeConfigurationProtectionObservation(false, "c"))
        await { native.current() == false }
        native.close()
        val stopped = changes.get()
        source.invalidate("d")
        values.emit(NativeConfigurationProtectionObservation(true, "d"))
        delay(20)
        assertThat(native.current()).isNull()
        assertThat(changes.get()).isEqualTo(stopped)
    }

    @Test fun ownerAttachingAfterInvalidationCannotAcceptThePreviousCommittedImage() = runBlocking {
        val values = MutableSharedFlow<NativeConfigurationProtectionObservation?>(replay = 1)
        values.emit(NativeConfigurationProtectionObservation(false, "a"))
        val source = NativeConfigurationProtectionSource(values)
        source.invalidate("b") // Native write began before this service owner subscribed.
        val native = observe(source)
        delay(20)
        assertThat(native.current()).isNull()
        values.emit(NativeConfigurationProtectionObservation(true, "b"))
        await { native.current() == true }
    }

    @Test fun actualDataStoreMutationsSynchronouslyLatchSignedCatalogAndPreserveABAFinalState() = runBlocking {
        val dataStore = PreferenceDataStoreFactory.create(scope = scope) {
            temporary.newFolder().resolve("settings.preferences_pb")
        }
        val repository = SettingsRepositoryImpl(dataStore, mockk<Context>(relaxed = true))
        AgentBridgeExportPlanningFixture().use { f ->
            f.store.initialize(f.native)
            val facts = AgentBridgeNativePlanningFacts(setOf("steps"), f.peer.sourceInstallationId, "UTC",
                AgentBridgeDiscoveryConfigurationProtection.UNLOCKED_NATIVE, AgentBridgeDiscoveryNativeGrants.SATISFIED,
                AgentBridgeDiscoveryEntitlement.SATISFIED, true, true)
            val lifecycle = AgentBridgeNativeCatalogLifecycle()
            lifecycle.observe(facts)
            val native = observe(repository.nativeConfigurationProtection, lifecycle::observeNativeChange)
            await { native.current() == false }
            val first = withContext(Dispatchers.IO) { lifecycle.publish(f.store, f.peer.sourceInstallationId) }
            repository.setPreventAccidentalChanges(false)
            assertThat(lifecycle.currentFacts()).isEqualTo(facts)
            repository.setPreventAccidentalChanges(true)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentFacts() }
            repository.setPreventAccidentalChanges(false)
            f.expect(AgentBridgeErrorCode.BINDING_CHANGED) { lifecycle.currentFacts() }
            await { native.current() == false }
            val next = withContext(Dispatchers.IO) { lifecycle.publish(f.store, f.peer.sourceInstallationId) }
            assertThat(next.revision).isEqualTo(first.revision + 1)
            assertThat(next.factsSha256).isEqualTo(first.factsSha256)
            native.close()
            lifecycle.stop()
            repository.setPreventAccidentalChanges(true)
            assertThat(native.current()).isNull()
            f.expect(AgentBridgeErrorCode.PERMISSION_REQUIRED) { lifecycle.currentFacts() }
        }
    }

    @Test fun malformedPersistedRevisionIsUnknownWithoutReadRepair() = runBlocking {
        val file = temporary.newFolder().resolve("settings.preferences_pb")
        val dataStore = PreferenceDataStoreFactory.create(scope = scope) { file }
        val revision = stringPreferencesKey("native_configuration_protection_revision_v1")
        dataStore.edit { it[revision] = "not-a-revision" }
        val repository = SettingsRepositoryImpl(dataStore, mockk<Context>(relaxed = true))
        val native = observe(repository.nativeConfigurationProtection)
        assertThat(repository.nativeConfigurationProtection.observations.first()).isNull()
        assertThat(native.current()).isNull()
        assertThat(dataStore.data.first()[revision]).isEqualTo("not-a-revision")
        repository.setPreventAccidentalChanges(true) // An actual native change owns the next revision.
        await { native.current() == true }
        assertThat(dataStore.data.first()[revision]).isNotEqualTo("not-a-revision")
    }

    @Test fun failedNativeWriteCannotReopenThePreviousSnapshot() = runBlocking {
        val initial = androidx.datastore.preferences.core.emptyPreferences()
        val dataStore = object : DataStore<Preferences> {
            override val data: Flow<Preferences> = flow { emit(initial); awaitCancellation() }
            override suspend fun updateData(transform: suspend (Preferences) -> Preferences): Preferences {
                transform(initial)
                throw IOException("synthetic commit failure")
            }
        }
        val repository = SettingsRepositoryImpl(dataStore, mockk<Context>(relaxed = true))
        val native = observe(repository.nativeConfigurationProtection)
        await { native.current() == false }
        try { repository.setPreventAccidentalChanges(true); error("expected synthetic write failure") }
        catch (_: IOException) { }
        assertThat(native.current()).isNull()
    }

    @Test fun storageErrorAndScopeCancellationDetachNativeListeners() = runBlocking {
        val fail = CompletableDeferred<Unit>()
        val values = flow<NativeConfigurationProtectionObservation?> {
            emit(NativeConfigurationProtectionObservation(false, "a"))
            fail.await()
            throw IOException("synthetic storage failure")
        }
        val changes = AtomicInteger()
        val source = NativeConfigurationProtectionSource(values)
        val native = observe(source) { changes.incrementAndGet() }
        await { native.current() == false }
        fail.complete(Unit)
        await { native.current() == null }
        native.close()
        val stopped = changes.get()
        source.invalidate("b")
        assertThat(changes.get()).isEqualTo(stopped)
        val second = AgentBridgeNativeConfigurationProtection(
            NativeConfigurationProtectionSource(flow { emit(NativeConfigurationProtectionObservation(true, "c")); awaitCancellation() }),
        ) { }
        second.start(scope)
        await { second.current() == true }
        scope.cancel()
        await { second.current() == null }
        second.close()
    }

    @Test fun unsupportedSourceStaysUnknownUntilOwnerStops() = runBlocking {
        val native = observe(null)
        assertThat(native.current()).isNull()
        native.close()
        assertThat(native.current()).isNull()
    }
}
