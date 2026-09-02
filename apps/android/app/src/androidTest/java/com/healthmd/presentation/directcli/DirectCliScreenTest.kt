package com.healthmd.presentation.directcli

import android.content.Context
import android.text.format.Formatter
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.test.assertIsEnabled
import androidx.compose.ui.test.assertIsNotEnabled
import androidx.compose.ui.test.assertTextContains
import androidx.compose.ui.test.junit4.createComposeRule
import androidx.compose.ui.test.onNodeWithContentDescription
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.compose.ui.test.performScrollTo
import androidx.compose.ui.test.performTextClearance
import androidx.compose.ui.test.performTextInput
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import com.healthmd.R
import com.healthmd.direct.DirectCliCompletion
import com.healthmd.direct.DirectCliConnectionState
import com.healthmd.direct.DirectCliFailure
import com.healthmd.presentation.theme.HealthMdTheme
import java.util.concurrent.CopyOnWriteArrayList
import java.util.concurrent.atomic.AtomicInteger
import org.junit.Assert.assertEquals
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

@RunWith(AndroidJUnit4::class)
class DirectCliScreenTest {
    @get:Rule
    val compose = createComposeRule()

    private val context: Context
        get() = ApplicationProvider.getApplicationContext()

    @Test
    fun unpairedWorkflowValidatesFieldsAndInvokesPair() {
        val state = mutableStateOf(DirectCliUiState())
        val pairInvocations = AtomicInteger(0)
        val scanInvocations = AtomicInteger(0)
        val backInvocations = AtomicInteger(0)

        compose.setContent {
            HealthMdTheme {
                DirectCliContent(
                    ui = state.value,
                    connection = DirectCliConnectionState.Idle,
                    onBack = { backInvocations.incrementAndGet() },
                    onHostChange = { value ->
                        state.value = state.value.copy(host = value.trim())
                    },
                    onPortChange = { value ->
                        state.value = state.value.copy(
                            port = value.filter(Char::isDigit).take(5),
                        )
                    },
                    onPairingCodeChange = { value ->
                        state.value = state.value.copy(
                            pairingCode = value.filter(Char::isDigit).take(20),
                        )
                    },
                    onScanQr = { scanInvocations.incrementAndGet() },
                    onPair = { pairInvocations.incrementAndGet() },
                    onSaveEndpoint = {},
                    onConnect = {},
                    onDisconnect = {},
                    onForget = {},
                )
            }
        }

        compose.onNodeWithTag(DirectCliTestTags.SCAN_QR).performClick()
        compose.onNodeWithTag(DirectCliTestTags.PAIR)
            .performScrollTo()
            .assertIsNotEnabled()
        compose.onNodeWithTag(DirectCliTestTags.HOST).performTextInput("192.0.2.10")
        compose.onNodeWithTag(DirectCliTestTags.PORT).performTextClearance()
        compose.onNodeWithTag(DirectCliTestTags.PORT).performTextInput("999999")
        compose.onNodeWithTag(DirectCliTestTags.PAIRING_CODE)
            .performTextInput("1234 5678 9012 3456 7890")
        compose.onNodeWithTag(DirectCliTestTags.PAIR).assertIsNotEnabled()

        compose.onNodeWithTag(DirectCliTestTags.PORT).performTextClearance()
        compose.onNodeWithTag(DirectCliTestTags.PORT).performTextInput("18647")
        compose.onNodeWithTag(DirectCliTestTags.PAIR).assertIsEnabled().performClick()
        compose.onNodeWithTag(DirectCliTestTags.STATUS)
            .assertTextContains(context.getString(R.string.direct_cli_status_not_connected))
        compose.onNodeWithContentDescription(context.getString(R.string.back)).performClick()

        assertEquals("12345678901234567890", state.value.pairingCode)
        assertEquals(1, scanInvocations.get())
        assertEquals(1, pairInvocations.get())
        assertEquals(1, backInvocations.get())
    }

    @Test
    fun pairedWorkflowExposesEndpointConnectionAndForgetActions() {
        val actions = CopyOnWriteArrayList<String>()
        val state = DirectCliUiState(
            host = "192.0.2.10",
            port = "18647",
            pairedListenerName = "Test CLI",
        )

        compose.setContent {
            HealthMdTheme {
                DirectCliContent(
                    ui = state,
                    connection = DirectCliConnectionState.Connected("Test CLI"),
                    onBack = {},
                    onHostChange = {},
                    onPortChange = {},
                    onPairingCodeChange = {},
                    onScanQr = {},
                    onPair = {},
                    onSaveEndpoint = { actions += "save" },
                    onConnect = { actions += "connect" },
                    onDisconnect = { actions += "disconnect" },
                    onForget = { actions += "forget" },
                )
            }
        }

        compose.onNodeWithTag(DirectCliTestTags.PAIRED_LISTENER)
            .assertTextContains(
                context.getString(R.string.direct_cli_paired_listener, "Test CLI"),
            )
        compose.onNodeWithTag(DirectCliTestTags.SAVE_ENDPOINT)
            .performScrollTo()
            .assertIsEnabled()
            .performClick()
        compose.onNodeWithTag(DirectCliTestTags.CONNECT).performScrollTo().performClick()
        compose.onNodeWithTag(DirectCliTestTags.DISCONNECT).performScrollTo().performClick()
        compose.onNodeWithTag(DirectCliTestTags.FORGET).performScrollTo().performClick()
        compose.onNodeWithTag(DirectCliTestTags.STATUS)
            .performScrollTo()
            .assertTextContains(
                context.getString(R.string.direct_cli_status_connected, "Test CLI"),
            )

        assertEquals(listOf("save", "connect", "disconnect", "forget"), actions.toList())
    }

    @Test
    fun statusTextCoversTransferCompletionAndFailureWithoutPayloads() {
        val connection = mutableStateOf<DirectCliConnectionState>(
            DirectCliConnectionState.Transferring(completedBytes = 1_024, totalBytes = 4_096),
        )

        compose.setContent {
            HealthMdTheme {
                DirectCliContent(
                    ui = DirectCliUiState(),
                    connection = connection.value,
                    onBack = {},
                    onHostChange = {},
                    onPortChange = {},
                    onPairingCodeChange = {},
                    onScanQr = {},
                    onPair = {},
                    onSaveEndpoint = {},
                    onConnect = {},
                    onDisconnect = {},
                    onForget = {},
                )
            }
        }

        compose.onNodeWithTag(DirectCliTestTags.STATUS)
            .performScrollTo()
            .assertTextContains(
                context.getString(
                    R.string.direct_cli_status_transferring,
                    Formatter.formatFileSize(context, 1_024),
                    Formatter.formatFileSize(context, 4_096),
                ),
            )

        compose.runOnIdle {
            connection.value = DirectCliConnectionState.Completed(
                DirectCliCompletion.ExportCompleted,
            )
        }
        compose.onNodeWithTag(DirectCliTestTags.STATUS)
            .assertTextContains(context.getString(R.string.direct_cli_status_export_completed))

        compose.runOnIdle {
            connection.value = DirectCliConnectionState.Failed(DirectCliFailure.EXPORT_FAILED)
        }
        compose.onNodeWithTag(DirectCliTestTags.STATUS)
            .assertTextContains(context.getString(R.string.direct_cli_failure_export))
    }
}
