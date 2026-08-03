package com.healthmd.presentation.directcli

import android.Manifest
import android.app.Notification
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.service.notification.StatusBarNotification
import androidx.compose.ui.test.hasClickAction
import androidx.compose.ui.test.hasTestTag
import androidx.compose.ui.test.hasText
import androidx.compose.ui.test.junit4.createEmptyComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.filters.LargeTest
import androidx.test.platform.app.InstrumentationRegistry
import com.healthmd.R
import com.healthmd.direct.DirectCliCompletion
import com.healthmd.direct.DirectCliConnectionState
import com.healthmd.direct.DirectCliFailure
import com.healthmd.direct.DirectCliInstrumentationEntryPoint
import com.healthmd.presentation.MainActivity
import com.healthmd.presentation.navigation.NavDestination
import dagger.hilt.android.EntryPointAccessors
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Before
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@LargeTest
@RunWith(AndroidJUnit4::class)
class DirectCliLiveE2ETest {
    @get:Rule
    val compose = createEmptyComposeRule()

    private lateinit var context: Context
    private lateinit var entryPoint: DirectCliInstrumentationEntryPoint
    private lateinit var host: String
    private lateinit var pairingCode: String
    private var port: Int = 0
    private var enabled = false
    private var scenario: ActivityScenario<MainActivity>? = null

    @Before
    fun setUp() {
        val arguments = InstrumentationRegistry.getArguments()
        assumeTrue(
            "Run through scripts/run-direct-cli-ui-e2e.sh to enable the live test.",
            arguments.getString(ARG_ENABLED) == "true",
        )
        host = requireNotNull(arguments.getString(ARG_HOST)?.takeIf(String::isNotBlank)) {
            "Missing Direct CLI E2E host."
        }
        port = requireNotNull(arguments.getString(ARG_PORT)?.toIntOrNull()?.takeIf { it in 1..65_535 }) {
            "Missing or invalid Direct CLI E2E port."
        }
        pairingCode = requireNotNull(
            arguments.getString(ARG_PAIRING_CODE)
                ?.takeIf { code -> code.length == 20 && code.all { it in '0'..'9' } },
        ) { "Missing or invalid Direct CLI E2E pairing code." }

        context = ApplicationProvider.getApplicationContext()
        assumeTrue(
            "The live test may only mutate the isolated .e2e application.",
            context.packageName.endsWith(".e2e"),
        )
        entryPoint = EntryPointAccessors.fromApplication(
            context,
            DirectCliInstrumentationEntryPoint::class.java,
        )
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
            InstrumentationRegistry.getInstrumentation().uiAutomation.grantRuntimePermission(
                context.packageName,
                Manifest.permission.POST_NOTIFICATIONS,
            )
        }
        enabled = true
        runBlocking {
            withTimeout(CLEANUP_TIMEOUT_MILLIS) {
                entryPoint.coordinator().cancelActive()
                entryPoint.coordinator().forget()
                entryPoint.settingsRepository().setOnboardingCompleted(true)
            }
        }

        scenario = ActivityScenario.launch(
            Intent(context, MainActivity::class.java)
                .putExtra(MainActivity.EXTRA_START_ROUTE, NavDestination.SETTINGS.route),
        )
        waitForNode(hasText("Direct CLI") and hasClickAction())
    }

    @After
    fun tearDown() {
        if (!enabled) return
        entryPoint.coordinator().cancelActive()
        runCatching {
            runBlocking {
                withTimeout(CLEANUP_TIMEOUT_MILLIS) {
                    entryPoint.coordinator().forget()
                    entryPoint.settingsRepository().setOnboardingCompleted(false)
                }
            }
        }
        scenario?.close()
    }

    @Test
    fun settingsUiAndRealServiceCoverWrongCodeReconnectDisconnectStatusForgetAndRepair() {
        compose.onNode(hasText("Direct CLI") and hasClickAction())
            .performScrollTo()
            .performClick()
        waitForNode(hasTestTag(DirectCliTestTags.SCREEN))
        compose.onNodeWithTag(DirectCliTestTags.HOST).assertExists()
        compose.onNodeWithTag(DirectCliTestTags.PORT).assertExists()
        compose.onNodeWithTag(DirectCliTestTags.PAIRING_CODE).assertExists()
        compose.onNodeWithTag(DirectCliTestTags.PAIR).assertExists()

        enterPairingDetails(wrongCode(pairingCode))
        click(DirectCliTestTags.PAIR)
        val rejected = waitForState<DirectCliConnectionState.Failed>("wrong-code rejection")
        assertEquals(DirectCliFailure.PAIRING_FAILED, rejected.reason)
        assertNull(entryPoint.trustStore().load())

        enterPairingDetails(pairingCode)
        click(DirectCliTestTags.PAIR)
        val paired = waitForState<DirectCliConnectionState.Completed>("initial pairing")
        assertEquals(DirectCliCompletion.Paired(LISTENER_NAME), paired.outcome)
        assertEquals(LISTENER_NAME, requireNotNull(entryPoint.trustStore().load()).displayName)
        waitForNode(hasTestTag(DirectCliTestTags.PAIRED_LISTENER))

        click(DirectCliTestTags.CONNECT)
        val connected = waitForState<DirectCliConnectionState.Connected>("trusted reconnect")
        assertEquals(LISTENER_NAME, connected.listenerName)
        val connectedNotificationText =
            context.getString(R.string.direct_cli_status_connected, LISTENER_NAME)
        val foregroundNotification = waitForDirectCliNotification(
            phase = "trusted reconnect",
            expectedText = connectedNotificationText,
        )
        assertTrue(
            foregroundNotification.notification.flags and Notification.FLAG_FOREGROUND_SERVICE != 0,
        )
        assertEquals(
            connectedNotificationText,
            foregroundNotification.notification.extras
                .getCharSequence(Notification.EXTRA_TEXT)
                ?.toString(),
        )
        val disconnectAction = foregroundNotification.notification.actions.single {
            it.title.toString() == context.getString(R.string.direct_cli_disconnect)
        }
        disconnectAction.actionIntent.send()
        waitForState<DirectCliConnectionState.Idle>("notification disconnect action")
        waitForDirectCliNotificationToDisappear()

        click(DirectCliTestTags.CONNECT)
        val status = waitForState<DirectCliConnectionState.Completed>("status session")
        assertEquals(DirectCliCompletion.SessionFinished, status.outcome)

        forgetAndWait("forget before re-pair")
        waitForNode(hasTestTag(DirectCliTestTags.PAIR))
        enterPairingDetails(pairingCode)
        click(DirectCliTestTags.PAIR)
        val repaired = waitForState<DirectCliConnectionState.Completed>("re-pair")
        assertEquals(DirectCliCompletion.Paired(LISTENER_NAME), repaired.outcome)
        assertNotNull(entryPoint.trustStore().load())
        waitForNode(hasTestTag(DirectCliTestTags.PAIRED_LISTENER))
        forgetAndWait("final forget")
    }

    private fun enterPairingDetails(code: String) {
        compose.onNodeWithTag(DirectCliTestTags.HOST).performTextClearance()
        compose.onNodeWithTag(DirectCliTestTags.HOST).performTextInput(host)
        compose.onNodeWithTag(DirectCliTestTags.PORT).performTextClearance()
        compose.onNodeWithTag(DirectCliTestTags.PORT).performTextInput(port.toString())
        compose.onNodeWithTag(DirectCliTestTags.PAIRING_CODE).performTextClearance()
        compose.onNodeWithTag(DirectCliTestTags.PAIRING_CODE).performTextInput(code)
    }

    private fun click(tag: String) {
        compose.onNodeWithTag(tag).performScrollTo().performClick()
    }

    private fun forgetAndWait(phase: String) {
        click(DirectCliTestTags.FORGET)
        waitForState<DirectCliConnectionState.Idle>(phase)
        waitForTrustToDisappear()
    }

    private inline fun <reified T : DirectCliConnectionState> waitForState(phase: String): T = try {
        runBlocking {
            withTimeout(NETWORK_TIMEOUT_MILLIS) {
                @Suppress("UNCHECKED_CAST")
                entryPoint.coordinator().state.first { it is T } as T
            }
        }
    } catch (error: TimeoutCancellationException) {
        throw AssertionError(
            "Timed out during $phase; Direct CLI state was ${entryPoint.coordinator().state.value}.",
            error,
        )
    }

    private fun waitForTrustToDisappear() = runBlocking {
        withTimeout(NETWORK_TIMEOUT_MILLIS) {
            while (entryPoint.trustStore().load() != null) {
                delay(POLL_INTERVAL_MILLIS)
            }
        }
    }

    private fun waitForDirectCliNotification(
        phase: String,
        expectedText: String,
    ): StatusBarNotification = try {
        runBlocking {
            withTimeout(NETWORK_TIMEOUT_MILLIS) {
                var result = directCliNotification(expectedText)
                while (result == null) {
                    delay(POLL_INTERVAL_MILLIS)
                    result = directCliNotification(expectedText)
                }
                requireNotNull(result)
            }
        }
    } catch (error: TimeoutCancellationException) {
        throw AssertionError(
            "Timed out waiting for the Direct CLI notification during $phase.",
            error,
        )
    }

    private fun waitForDirectCliNotificationToDisappear() = try {
        runBlocking {
            withTimeout(NETWORK_TIMEOUT_MILLIS) {
                while (directCliNotification() != null) {
                    delay(POLL_INTERVAL_MILLIS)
                }
            }
        }
    } catch (error: TimeoutCancellationException) {
        throw AssertionError(
            "Timed out waiting for the Direct CLI notification to disappear.",
            error,
        )
    }

    private fun directCliNotification(expectedText: String? = null): StatusBarNotification? =
        context.getSystemService(NotificationManager::class.java)
            .activeNotifications
            .firstOrNull { status ->
                val extras = status.notification.extras
                extras.getCharSequence(Notification.EXTRA_TITLE)?.toString() ==
                    context.getString(R.string.direct_cli_notification_title) &&
                    (expectedText == null ||
                        extras.getCharSequence(Notification.EXTRA_TEXT)?.toString() == expectedText)
            }

    private fun waitForNode(
        matcher: androidx.compose.ui.test.SemanticsMatcher,
        timeoutMillis: Long = UI_TIMEOUT_MILLIS,
    ) {
        compose.waitUntil(timeoutMillis) {
            runCatching {
                compose.onAllNodes(matcher).fetchSemanticsNodes().isNotEmpty()
            }.getOrDefault(false)
        }
    }

    private fun wrongCode(code: String): String {
        val replacement = if (code.first() == '0') '1' else '0'
        return replacement + code.drop(1)
    }

    private companion object {
        const val ARG_ENABLED = "directCliE2E"
        const val ARG_HOST = "directCliHost"
        const val ARG_PORT = "directCliPort"
        const val ARG_PAIRING_CODE = "directCliPairingCode"
        const val LISTENER_NAME = "Rust Android UI E2E CLI"
        const val UI_TIMEOUT_MILLIS = 30_000L
        const val NETWORK_TIMEOUT_MILLIS = 60_000L
        const val CLEANUP_TIMEOUT_MILLIS = 15_000L
        const val POLL_INTERVAL_MILLIS = 25L
    }
}
