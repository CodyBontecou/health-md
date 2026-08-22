package com.healthmd.data.scheduler

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.google.common.truth.Truth.assertThat
import io.mockk.mockk
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/** Fresh-store and corruption boundaries for the profile schedule DataStore payload. */
class ScheduledProfileEntryStoreTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var dataStoreScope: CoroutineScope
    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var store: ScheduledProfileEntryStore

    @Before
    fun setUp() {
        dataStoreScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val dataStoreFile = temporaryFolder.newFolder().resolve("scheduled_profiles.preferences_pb")
        dataStore = PreferenceDataStoreFactory.create(
            scope = dataStoreScope,
            produceFile = { dataStoreFile },
        )
        store = ScheduledProfileEntryStore(
            dataStore = dataStore,
            context = mockk<Context>(relaxed = true),
        )
    }

    @After
    fun tearDown() {
        dataStoreScope.cancel()
    }

    private fun entry(profileId: String, hour: Int = 8) = ScheduledProfileEntry(
        profileId = profileId,
        anchorEpochDay = 20_000,
        hour = hour,
        zoneId = "UTC",
    )

    @Test
    fun `upsert creates the first entry when the key is absent`() = runTest {
        assertThat(dataStore.data.first().asMap().keys.map { it.name })
            .doesNotContain(ENTRIES_KEY.name)

        assertThat(store.upsert(entry("first"))).isTrue()

        assertThat(store.getEntries().map { it.profileId }).containsExactly("first")
        assertThat(dataStore.data.first()[ENTRIES_KEY]).isNotNull()
    }

    @Test
    fun `upsert preserves other profiles and replaces only the matching id`() = runTest {
        store.upsert(entry("alpha", hour = 8))
        store.upsert(entry("beta", hour = 9))
        store.upsert(entry("alpha", hour = 10))

        val entries = store.getEntries()
        assertThat(entries.map { it.profileId }).containsExactly("alpha", "beta").inOrder()
        assertThat(entries.single { it.profileId == "alpha" }.hour).isEqualTo(10)
        assertThat(entries.single { it.profileId == "beta" }.hour).isEqualTo(9)
    }

    @Test
    fun `configuration upsert preserves a newer worker success frontier`() = runTest {
        assertThat(
            store.upsert(entry("alpha").copy(lastSuccessEpochMillis = 1234L)),
        ).isTrue()

        assertThat(store.upsert(entry("alpha", hour = 10))).isTrue()

        val stored = store.entry("alpha")!!
        assertThat(stored.hour).isEqualTo(10)
        assertThat(stored.lastSuccessEpochMillis).isEqualTo(1234L)
    }

    @Test
    fun `concurrent progress and configuration updates preserve both changes`() = runTest {
        store.upsert(entry("alpha", hour = 8))

        listOf(
            async(Dispatchers.Default) {
                store.update("alpha") { it.copy(hour = 10) }
            },
            async(Dispatchers.Default) {
                store.recordSuccess("alpha", fireAtMillis = 5678L)
            },
        ).awaitAll()

        val stored = store.entry("alpha")!!
        assertThat(stored.hour).isEqualTo(10)
        assertThat(stored.lastSuccessEpochMillis).isEqualTo(5678L)
    }

    @Test
    fun `legacy migration entry and pending marker commit together`() = runTest {
        val migrated = entry("default").copy(isEnabled = true)

        assertThat(store.beginLegacyMigration(migrated)).isTrue()
        assertThat(store.entry("default")).isEqualTo(migrated)
        assertThat(store.pendingLegacyMigrationProfileId()).isEqualTo("default")

        assertThat(store.finishLegacyMigration("default")).isTrue()
        assertThat(store.pendingLegacyMigrationProfileId()).isNull()
    }

    @Test
    fun `malformed present payload blocks writes without replacing its bytes`() = runTest {
        val corrupt = "{not-json"
        dataStore.edit { it[ENTRIES_KEY] = corrupt }

        assertThat(store.upsert(entry("must-not-overwrite"))).isFalse()

        assertThat(dataStore.data.first()[ENTRIES_KEY]).isEqualTo(corrupt)
        assertThat(store.getEntries()).isEmpty()
    }

    @Test
    fun `concurrent first writes retain both profiles`() = runTest {
        listOf("alpha", "beta").map { profileId ->
            async(Dispatchers.Default) { store.upsert(entry(profileId)) }
        }.awaitAll()

        assertThat(store.getEntries().map { it.profileId })
            .containsExactly("alpha", "beta")
    }

    private companion object {
        val ENTRIES_KEY = stringPreferencesKey("scheduled_profile_entries")
    }
}
