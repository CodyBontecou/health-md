package com.healthmd.presentation.common

import androidx.compose.ui.focus.FocusDirection
import androidx.compose.ui.focus.FocusManager
import com.google.common.truth.Truth.assertThat
import org.junit.Test

class SafeFocusTest {
    private class RecordingFocusManager(private val failWhen: (Boolean) -> Boolean) : FocusManager {
        val calls = mutableListOf<Boolean>()

        override fun clearFocus(force: Boolean) {
            calls += force
            if (failWhen(force)) throw IllegalArgumentException("ActiveParent with no focused child")
        }

        override fun moveFocus(focusDirection: FocusDirection): Boolean = false
    }

    @Test
    fun clearsNormallyWhenComposeFocusTreeIsConsistent() {
        val manager = RecordingFocusManager { false }
        manager.clearFocusSafely()
        assertThat(manager.calls).containsExactly(false)
    }

    @Test
    fun activeParentWithoutFocusedChildRetriesWithForceInsteadOfCrashing() {
        val manager = RecordingFocusManager { force -> !force }
        manager.clearFocusSafely()
        assertThat(manager.calls).containsExactly(false, true).inOrder()
    }

    @Test
    fun aForcedClearThatAlsoFailsIsSwallowed() {
        val manager = RecordingFocusManager { true }
        manager.clearFocusSafely()
        assertThat(manager.calls).containsExactly(false, true).inOrder()
    }
}
