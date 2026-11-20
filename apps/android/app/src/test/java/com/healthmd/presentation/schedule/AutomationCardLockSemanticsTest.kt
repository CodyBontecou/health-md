package com.healthmd.presentation.schedule

import android.app.Application
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.test.SemanticsMatcher
import androidx.compose.ui.test.hasContentDescription
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onAllNodesWithContentDescription
import androidx.compose.ui.test.onAllNodesWithTag
import androidx.compose.ui.test.assertCountEquals
import androidx.compose.ui.test.performClick
import com.google.common.truth.Truth.assertThat
import com.healthmd.domain.model.ExportProfile
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportTarget
import com.healthmd.presentation.common.ConfigurationProtectedRegion
import com.healthmd.presentation.common.ConfigurationProtectionUi
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.common.lockedReadOnlyDescription
import com.healthmd.presentation.theme.HealthMdTheme
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith
import org.robolectric.RobolectricTestRunner
import org.robolectric.annotation.Config

/**
 * With Lock configuration on, TalkBack must still read each automation card's name, while the
 * lock is announced once and the cards expose no action that could bypass it.
 */
@RunWith(RobolectricTestRunner::class)
@Config(qualifiers = "w400dp-h2000dp", application = Application::class)
class AutomationCardLockSemanticsTest {
    @get:Rule val compose = createComposeRule()

    private fun profile(id: String, name: String) = ExportProfile(
        id = id,
        name = name,
        settingsSnapshotJson = "snapshot",
        target = ExportTarget.DEVICE_FOLDER,
        createdAtEpochMillis = 1L,
        updatedAtEpochMillis = 1L,
    )

    private fun render(locked: Boolean, onOpen: () -> Unit = {}) = compose.setContent {
        HealthMdTheme {
            CompositionLocalProvider(LocalConfigurationProtection provides ConfigurationProtectionUi(enabled = locked)) {
                ConfigurationProtectedRegion(readableWhenLocked = true) {
                    androidx.compose.foundation.layout.Column {
                        listOf(profile("a", "Default"), profile("b", "Weekly JSON")).forEach { p ->
                            AutomationCard(
                                profile = p,
                                entry = null,
                                settings = ExportSettings(),
                                recentDays = emptyList(),
                                selected = false,
                                hasScheduleAccess = false,
                                onTryFree = {},
                                onToggle = {},
                                onOpen = onOpen,
                            )
                        }
                    }
                }
            }
        }
    }

    private fun startsWith(prefix: String) = SemanticsMatcher("contentDescription starts with $prefix") { node ->
        node.config.getOrElseNullable(SemanticsProperties.ContentDescription) { null }.orEmpty().any { it.startsWith(prefix) }
    }

    @Test
    fun lockedCardsStayReadableWithoutActionsAndTheLockIsAnnouncedOnce() {
        render(locked = true)

        listOf("Default", "Weekly JSON").forEach { name ->
            val card = compose.onNode(startsWith("$name, ")).fetchSemanticsNode()
            assertThat(card.config.contains(SemanticsActions.OnClick)).isFalse()
        }
        val notices = compose.onAllNodesWithContentDescription("Settings are locked").fetchSemanticsNodes()
        assertThat(notices).hasSize(1)
        assertThat(notices.single().config.contains(SemanticsActions.OnClick)).isTrue()
        // Nothing inside a locked card (the Try free button) reaches accessibility services, so
        // only the lock notice is actionable (the merged tree is what TalkBack sees).
        assertThat(
            compose.onAllNodes(SemanticsMatcher.keyIsDefined(SemanticsActions.OnClick))
                .fetchSemanticsNodes(),
        ).hasSize(1)
    }

    @Test
    fun unlockedCardsKeepTheirOpenAction() {
        var opened = 0
        render(locked = false) { opened++ }

        compose.onAllNodesWithContentDescription("Settings are locked").assertCountEquals(0)
        compose.onAllNodes(hasContentDescription("Default, ", substring = true)).assertCountEquals(0)
        compose.onAllNodesWithTag(AutomationsTags.CARD)[0].performClick()
        assertThat(opened).isEqualTo(1)
    }

    @Test
    fun descriptionSkipsBlankParts() {
        assertThat(lockedReadOnlyDescription("Default", " ", null, "Manual")).isEqualTo("Default, Manual")
    }
}
