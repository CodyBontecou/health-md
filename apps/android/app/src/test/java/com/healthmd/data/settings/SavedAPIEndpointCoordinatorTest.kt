package com.healthmd.data.settings

import com.google.common.truth.Truth.assertThat
import com.healthmd.data.export.InMemorySavedEndpointPersistence
import com.healthmd.data.export.SavedAPIEndpointResult
import com.healthmd.data.export.SavedAPIEndpointStore
import com.healthmd.data.export.TokenChange
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportTarget
import kotlinx.coroutines.test.runTest
import org.junit.Test

private class FakeBindingOps(var profiles: List<ExportProfile>, var activeId: String?, var live: String) : EndpointBindingOps {
    val flushed = mutableListOf<String>()
    val rebound = mutableListOf<Pair<String, String>>()
    val unbound = mutableListOf<String>()
    override suspend fun profiles() = profiles
    override suspend fun activeProfileId() = activeId
    override suspend fun liveEndpointUrl() = live
    override suspend fun setLiveEndpointUrl(url: String) { live = url }
    override suspend fun bindActive(url: String) { live = url; flushActive() }
    override suspend fun flushActive() {
        val id = activeId ?: return
        flushed += id
        profiles = profiles.map { if (it.id == id) it.copy(target = ExportTarget.API_ENDPOINT, apiEndpointUrl = live.ifBlank { it.apiEndpointUrl }) else it }
    }
    override suspend fun rebindInactive(profile: ExportProfile, newUrl: String): Boolean {
        rebound += profile.id to newUrl
        profiles = profiles.map { if (it.id == profile.id) it.copy(apiEndpointUrl = newUrl) else it }
        return true
    }
    override suspend fun unbind(profileId: String) {
        unbound += profileId
        profiles = profiles.map { if (it.id == profileId) it.copy(apiEndpointUrl = null) else it }
    }
}

class SavedAPIEndpointCoordinatorTest {
    private fun profile(id: String, target: ExportTarget, url: String?) = ExportProfile(
        id = id, name = id, settingsSnapshotJson = "{}", target = target, apiEndpointUrl = url,
        createdAtEpochMillis = 0, updatedAtEpochMillis = 0,
    )

    private val old = "https://api.example.com/health"
    private val other = "https://other.example.com/in"
    private val ops = FakeBindingOps(
        profiles = listOf(
            profile("daily", ExportTarget.API_ENDPOINT, old),
            profile("weekly", ExportTarget.API_ENDPOINT, old),
            profile("research", ExportTarget.API_ENDPOINT, other),
            profile("vault", ExportTarget.DEVICE_FOLDER, null),
        ),
        activeId = "daily",
        live = old,
    )
    private val coordinator = SavedAPIEndpointCoordinator(SavedAPIEndpointStore(InMemorySavedEndpointPersistence()), ops)

    private suspend fun saved(name: String, url: String) =
        (coordinator.save(null, name, url, TokenChange.Keep) as SavedAPIEndpointResult.Saved).endpoint

    @Test
    fun editingAUrlMovesEveryAutomationThatUsesIt() = runTest {
        val home = saved("Home", old)
        saved("Research", other)

        coordinator.save(home.id, "Home", "https://api.example.com/v2", TokenChange.Keep)

        assertThat(ops.rebound).containsExactly("weekly" to "https://api.example.com/v2")
        assertThat(ops.live).isEqualTo("https://api.example.com/v2")
        assertThat(ops.flushed).containsExactly("daily")
        assertThat(ops.profiles.associate { it.id to it.apiEndpointUrl }).containsExactly(
            "daily", "https://api.example.com/v2",
            "weekly", "https://api.example.com/v2",
            "research", other,
            "vault", null,
        )
        assertThat(coordinator.usedBy(coordinator.endpoints.value.first { it.id == home.id }))
            .containsExactly("daily", "weekly")
    }

    @Test
    fun renameOrTokenOnlyEditsLeaveBindingsAlone() = runTest {
        val home = saved("Home", old)
        coordinator.save(home.id, "Home server", old, TokenChange.Set("secret"))

        assertThat(ops.rebound).isEmpty()
        assertThat(ops.flushed).isEmpty()
        assertThat(ops.live).isEqualTo(old)
    }

    @Test
    fun deletingUnbindsItsAutomationsAndNeverRedirectsThem() = runTest {
        val home = saved("Home", old)
        saved("Research", other)

        coordinator.delete(home.id)

        assertThat(ops.unbound).containsExactly("daily", "weekly")
        assertThat(ops.live).isEmpty()
        val urls = ops.profiles.associate { it.id to it.apiEndpointUrl }
        assertThat(urls["daily"]).isNull()
        assertThat(urls["weekly"]).isNull()
        assertThat(urls["research"]).isEqualTo(other)
        assertThat(coordinator.endpoints.value.map { it.name }).containsExactly("Research")
    }

    @Test
    fun bindingMakesTheEndpointTheActiveAutomationsDestination() = runTest {
        val research = saved("Research", other)
        coordinator.bindToActive(research)

        assertThat(ops.live).isEqualTo(other)
        assertThat(ops.profiles.first { it.id == "daily" }.apiEndpointUrl).isEqualTo(other)
    }
}
