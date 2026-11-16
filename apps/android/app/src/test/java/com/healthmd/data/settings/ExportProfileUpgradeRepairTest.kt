package com.healthmd.data.settings

import android.content.Context
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.PreferenceDataStoreFactory
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportTarget
import io.mockk.mockk
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.test.runTest
import kotlinx.serialization.builtins.ListSerializer
import kotlinx.serialization.json.Json
import org.junit.After
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

/**
 * Issue #329: upgrading must keep exactly one Default profile and every setting, the upgrade
 * steps must be idempotent, and installs already holding duplicate Defaults must self-repair.
 * Each test drives the same repository calls that [ExportProfileCoordinator] bootstrap makes.
 */
class ExportProfileUpgradeRepairTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    private lateinit var dataStoreScope: CoroutineScope
    private lateinit var dataStore: DataStore<Preferences>
    private lateinit var repository: ExportProfileRepository

    @Before
    fun setUp() {
        dataStoreScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
        val file = temporaryFolder.newFolder().resolve("health_md_settings.preferences_pb")
        dataStore = PreferenceDataStoreFactory.create(scope = dataStoreScope, produceFile = { file })
        repository = ExportProfileRepository(dataStore, mockk<Context>(relaxed = true))
    }

    @After
    fun tearDown() {
        dataStoreScope.cancel()
    }

    /** The repository half of coordinator bootstrap: repair, then synthesize Default if empty. */
    private suspend fun upgradeLaunch() {
        repository.repairDuplicateDefaultsIfNeeded()
        if (repository.getProfiles().isEmpty() && !repository.hasOpaqueProfiles()) {
            repository.migrateDefaultIfNeeded(LIVE_SNAPSHOT, ExportTarget.DEVICE_FOLDER)
        }
    }

    private suspend fun storedState(): Map<Preferences.Key<*>, Any> = dataStore.data.first().asMap()

    @Test
    fun `v16 legacy profile store upgrades to one Default with identical settings`() = runTest {
        // v16 wrote the legacy list key, before the v2 envelope and newer optional fields existed.
        dataStore.edit {
            it[LEGACY_PROFILES] = """[{"id":"v16-default","name":"Default",""" +
                """"settingsSnapshotJson":"{\"exportFormats\":[\"markdown\"]}",""" +
                """"target":"DEVICE_FOLDER","isMigrationDefault":true,""" +
                """"createdAtEpochMillis":10,"updatedAtEpochMillis":20}]"""
            it[LEGACY_ACTIVE] = "v16-default"
            it[SCHEDULE_ENTRIES] = """[{"profileId":"v16-default","isEnabled":true}]"""
        }

        upgradeLaunch()

        val profile = repository.getProfiles().single()
        assertThat(profile.id).isEqualTo("v16-default")
        assertThat(profile.name).isEqualTo("Default")
        assertThat(profile.isMigrationDefault).isTrue()
        assertThat(profile.settingsSnapshotJson).isEqualTo("""{"exportFormats":["markdown"]}""")
        assertThat(profile.target).isEqualTo(ExportTarget.DEVICE_FOLDER)
        assertThat(profile.updatedAtEpochMillis).isEqualTo(20)
        assertThat(repository.getActiveProfileId()).isEqualTo("v16-default")
        // The scheduled entry still resolves to a real profile, so the next trigger can run it.
        assertThat(repository.profileById("v16-default")).isNotNull()
    }

    @Test
    fun `running the upgrade twice gives the same stored state`() = runTest {
        dataStore.edit {
            it[LEGACY_PROFILES] = encodeList(
                defaultProfile("a", createdAt = 1),
                defaultProfile("b", createdAt = 2),
                profile("custom", "Work"),
            )
            it[LEGACY_ACTIVE] = "b"
        }

        upgradeLaunch()
        val first = storedState()
        upgradeLaunch()

        assertThat(storedState()).isEqualTo(first)
        assertThat(repository.getProfiles().count { it.isMigrationDefault }).isEqualTo(1)
    }

    @Test
    fun `pre-profile install synthesizes exactly one Default across repeated launches`() = runTest {
        upgradeLaunch()
        upgradeLaunch()

        val profile = repository.getProfiles().single()
        assertThat(profile.isMigrationDefault).isTrue()
        assertThat(profile.settingsSnapshotJson).isEqualTo(LIVE_SNAPSHOT)
        assertThat(repository.getActiveProfileId()).isEqualTo(profile.id)
    }

    @Test
    fun `identical duplicate Defaults collapse onto the active one`() = runTest {
        dataStore.edit {
            it[ENVELOPE] = envelope(defaultProfile("old", createdAt = 1), defaultProfile("new", createdAt = 2))
            it[ENVELOPE_ACTIVE] = "new"
        }

        assertThat(repository.repairDuplicateDefaultsIfNeeded()).isTrue()

        val profile = repository.getProfiles().single()
        assertThat(profile.id).isEqualTo("new")
        assertThat(profile.name).isEqualTo("Default")
        assertThat(repository.getActiveProfileId()).isEqualTo("new")
        assertThat(repository.repairDuplicateDefaultsIfNeeded()).isFalse()
    }

    @Test
    fun `differently configured duplicate Default is kept as an ordinary profile`() = runTest {
        dataStore.edit {
            it[ENVELOPE] = envelope(
                defaultProfile("a", createdAt = 1),
                defaultProfile("b", createdAt = 2, snapshot = "edited-snapshot"),
            )
            it[ENVELOPE_ACTIVE] = "a"
        }

        assertThat(repository.repairDuplicateDefaultsIfNeeded()).isTrue()

        val profiles = repository.getProfiles()
        assertThat(profiles.map { it.id }).containsExactly("a", "b").inOrder()
        assertThat(profiles.single { it.isMigrationDefault }.id).isEqualTo("a")
        val demoted = profiles.single { it.id == "b" }
        assertThat(demoted.settingsSnapshotJson).isEqualTo("edited-snapshot")
        assertThat(demoted.name).isEqualTo("Default 2")
        assertThat(profiles.map { it.name.lowercase() }.toSet()).hasSize(2)
    }

    @Test
    fun `scheduled duplicate Default is never removed so its schedule keeps a profile`() = runTest {
        dataStore.edit {
            it[ENVELOPE] = envelope(defaultProfile("active", createdAt = 1), defaultProfile("scheduled", createdAt = 2))
            it[ENVELOPE_ACTIVE] = "active"
            it[SCHEDULE_ENTRIES] = """[{"profileId":"scheduled","isEnabled":true}]"""
        }

        repository.repairDuplicateDefaultsIfNeeded()

        assertThat(repository.profileById("scheduled")).isNotNull()
        assertThat(repository.getProfiles().count { it.isMigrationDefault }).isEqualTo(1)
    }

    @Test
    fun `repeated identical record with one id is collapsed and unblocks the store`() = runTest {
        val record = Json.encodeToString(ExportProfile.serializer(), defaultProfile("same", createdAt = 1))
        dataStore.edit {
            it[ENVELOPE] = """{"version":2,"records":[$record,$record]}"""
            it[ENVELOPE_ACTIVE] = "same"
        }
        assertThat(repository.hasOpaqueProfiles()).isTrue()

        assertThat(repository.repairDuplicateDefaultsIfNeeded()).isTrue()

        assertThat(repository.hasOpaqueProfiles()).isFalse()
        assertThat(repository.getProfiles().single().id).isEqualTo("same")
    }

    @Test
    fun `conflicting records with one id stay untouched`() = runTest {
        val first = Json.encodeToString(ExportProfile.serializer(), defaultProfile("same", createdAt = 1))
        val second = Json.encodeToString(
            ExportProfile.serializer(),
            defaultProfile("same", createdAt = 1, snapshot = "other"),
        )
        val raw = """{"version":2,"records":[$first,$second]}"""
        dataStore.edit { it[ENVELOPE] = raw }

        assertThat(repository.repairDuplicateDefaultsIfNeeded()).isFalse()
        assertThat(dataStore.data.first()[ENVELOPE]).isEqualTo(raw)
    }

    private fun defaultProfile(id: String, createdAt: Long, snapshot: String = "snapshot") = ExportProfile(
        id = id,
        name = "Default",
        settingsSnapshotJson = snapshot,
        target = ExportTarget.DEVICE_FOLDER,
        isMigrationDefault = true,
        createdAtEpochMillis = createdAt,
        updatedAtEpochMillis = createdAt,
    )

    private fun profile(id: String, name: String) = ExportProfile(
        id = id,
        name = name,
        settingsSnapshotJson = "snapshot",
        target = ExportTarget.DEVICE_FOLDER,
        createdAtEpochMillis = 5,
        updatedAtEpochMillis = 5,
    )

    private fun encodeList(vararg profiles: ExportProfile): String =
        Json.encodeToString(ListSerializer(ExportProfile.serializer()), profiles.toList())

    private fun envelope(vararg profiles: ExportProfile): String =
        """{"version":2,"records":${encodeList(*profiles)}}"""

    private companion object {
        const val LIVE_SNAPSHOT = "live-settings-snapshot"
        val LEGACY_PROFILES = stringPreferencesKey("export_profiles")
        val LEGACY_ACTIVE = stringPreferencesKey("export_profiles_active_id")
        val ENVELOPE = stringPreferencesKey("export_profiles_v2")
        val ENVELOPE_ACTIVE = stringPreferencesKey("export_profiles_active_id_v2")
        val SCHEDULE_ENTRIES = stringPreferencesKey("scheduled_profile_entries")
    }
}
