package com.healthmd.presentation.directcli

import android.app.KeyguardManager
import android.os.Looper
import android.os.UserManager
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.res.stringResource
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.LifecycleEventObserver
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.compose.runtime.DisposableEffect
import com.healthmd.R
import com.healthmd.direct.AgentBridgeExportAuthorityStore
import com.healthmd.direct.AgentBridgeExportNativeSetupConsent
import com.healthmd.direct.protocol.AgentBridgeErrorCode
import com.healthmd.direct.protocol.AgentBridgeException
import com.healthmd.presentation.common.GeistCard
import com.healthmd.presentation.common.LocalConfigurationProtection
import com.healthmd.presentation.theme.AppColors
import com.healthmd.presentation.theme.Spacing
import java.nio.file.Files
import java.nio.file.LinkOption.NOFOLLOW_LINKS
import java.nio.file.NoSuchFileException
import java.nio.file.attribute.BasicFileAttributes

private enum class AgentPermissionSetupStatus { CHECKING, NOT_SET_UP, READY, UNAVAILABLE }

/** Native confirmation only; no wire input, grant issuance, pairing or service start. */
@Composable
internal fun AgentExportPermissionsSetupCard() {
    val context = LocalContext.current
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    val protection by rememberUpdatedState(LocalConfigurationProtection.current)
    var status by remember { mutableStateOf(AgentPermissionSetupStatus.CHECKING) }
    var confirming by remember { mutableStateOf(false) }

    fun refresh() {
        status = try {
            val root = context.dataDir.toPath().resolve("no_backup").resolve(AgentBridgeExportAuthorityStore.DIRECTORY_NAME)
            Files.readAttributes(root, BasicFileAttributes::class.java, NOFOLLOW_LINKS)
            AgentBridgeExportAuthorityStore.forNoBackup(context).access {
                if (it == null) throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
            }
            AgentPermissionSetupStatus.READY
        } catch (_: NoSuchFileException) {
            AgentPermissionSetupStatus.NOT_SET_UP
        } catch (_: Exception) { AgentPermissionSetupStatus.UNAVAILABLE }
    }

    LaunchedEffect(context) { refresh() }
    DisposableEffect(lifecycle) {
        val observer = LifecycleEventObserver { _, event ->
            if (event == Lifecycle.Event.ON_RESUME) refresh()
            if (event == Lifecycle.Event.ON_PAUSE || event == Lifecycle.Event.ON_STOP) confirming = false
        }
        lifecycle.addObserver(observer)
        onDispose { lifecycle.removeObserver(observer) }
    }

    GeistCard {
        Column(verticalArrangement = Arrangement.spacedBy(Spacing.sm)) {
            Text(stringResource(R.string.agent_export_permissions_title), style = MaterialTheme.typography.titleMedium)
            Text(
                stringResource(when (status) {
                    AgentPermissionSetupStatus.CHECKING -> R.string.agent_export_permissions_checking
                    AgentPermissionSetupStatus.NOT_SET_UP -> R.string.agent_export_permissions_intro
                    AgentPermissionSetupStatus.READY -> R.string.agent_export_permissions_ready
                    AgentPermissionSetupStatus.UNAVAILABLE -> R.string.agent_export_permissions_unavailable
                }),
                color = AppColors.textMuted,
                modifier = Modifier.testTag("agent_export_permissions_status"),
            )
            if (status == AgentPermissionSetupStatus.READY) { AgentExportPermissionsManagementControls() }
            if (status == AgentPermissionSetupStatus.NOT_SET_UP) {
                Button(onClick = {
                    if (protection.enabled) protection.onBlockedChange() else confirming = true
                }, modifier = Modifier.testTag("agent_export_permissions_setup")) {
                    Text(stringResource(R.string.agent_export_permissions_setup))
                }
            }
        }
    }
    if (confirming) {
        AlertDialog(
            onDismissRequest = { confirming = false },
            title = { Text(stringResource(R.string.agent_export_permissions_confirmation)) },
            text = { Text(stringResource(R.string.agent_export_permissions_confirmation_body)) },
            dismissButton = {
                TextButton(onClick = { confirming = false }) { Text(stringResource(android.R.string.cancel)) }
            },
            confirmButton = {
                TextButton(onClick = confirm@{
                    if (status != AgentPermissionSetupStatus.NOT_SET_UP) return@confirm
                    confirming = false
                    if (protection.enabled) protection.onBlockedChange()
                    else {
                        status = try {
                            AgentBridgeExportNativeSetupConsent.withNativeConfirmation(requireCurrentNativePolicy = {
                                if (Looper.myLooper() != Looper.getMainLooper() ||
                                    !lifecycle.currentState.isAtLeast(Lifecycle.State.RESUMED) || protection.enabled ||
                                    context.isDeviceProtectedStorage ||
                                    context.getSystemService(UserManager::class.java)?.isUserUnlocked != true ||
                                    context.getSystemService(KeyguardManager::class.java)?.isKeyguardLocked != false) {
                                    throw AgentBridgeException(AgentBridgeErrorCode.APPROVAL_REQUIRED)
                                }
                            }) { consent ->
                                AgentBridgeExportAuthorityStore.initializeNative(context, consent).access {
                                    if (it == null) throw AgentBridgeException(AgentBridgeErrorCode.BINDING_CHANGED)
                                }
                            }
                            AgentPermissionSetupStatus.READY
                        } catch (_: Exception) { AgentPermissionSetupStatus.UNAVAILABLE }
                    }
                }, modifier = Modifier.testTag("agent_export_permissions_confirm")) {
                    Text(stringResource(R.string.agent_export_permissions_confirm))
                }
            },
        )
    }
}
