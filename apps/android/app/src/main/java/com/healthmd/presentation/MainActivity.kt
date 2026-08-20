package com.healthmd.presentation

import android.content.Intent
import android.os.Bundle
import android.view.WindowManager
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.lifecycleScope
import androidx.lifecycle.repeatOnLifecycle
import com.healthmd.data.export.ExportAwakeCoordinator
import com.healthmd.data.scheduler.ExportScheduler
import com.healthmd.data.settings.ExportProfileCoordinator
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.presentation.theme.HealthMdTheme
import com.healthmd.presentation.navigation.HealthMdNavigation
import com.healthmd.sharedsetup.SharedSetupCoordinator
import com.healthmd.sharedsetup.SharedSetupIntentExtractor
import com.healthmd.sharedsetup.SharedSetupIntentRestoreAction
import com.healthmd.widget.refresh.HealthWidgetLifecycleCoordinator
import com.healthmd.wear.WearPhoneSyncScheduler
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    companion object {
        const val EXTRA_START_ROUTE = "com.healthmd.START_ROUTE"
        const val EXTRA_PROMPT_SCHEDULED_RECOVERY = "com.healthmd.PROMPT_SCHEDULED_RECOVERY"
        const val EXTRA_GOOGLE_DRIVE_OPERATION_ID = "com.healthmd.GOOGLE_DRIVE_OPERATION_ID"
        private const val STATE_HANDLED_EXTERNAL_INTENT = "sharedSetup.handledExternalIntent"
        private const val STATE_SHARED_SETUP_PROCESS_ID = "sharedSetup.processInstanceID"
        private const val STATE_EXTERNAL_DOCUMENT_BYTES = "sharedSetup.externalDocumentBytes"
        private const val STATE_EXTERNAL_IMPORT_FINISHED = "sharedSetup.externalImportFinished"
    }

    private var startRoute by mutableStateOf<String?>(null)
    private var scheduledRecoveryPromptRequestId by mutableStateOf(0L)
    internal var googleDriveOperationId by mutableStateOf<String?>(null)
        private set
    private var handledExternalIntent = false

    @Inject
    lateinit var settingsRepository: SettingsRepository

    @Inject
    lateinit var exportScheduler: ExportScheduler

    @Inject
    lateinit var exportProfileCoordinator: ExportProfileCoordinator

    @Inject
    lateinit var widgetLifecycle: HealthWidgetLifecycleCoordinator

    @Inject
    lateinit var sharedSetupCoordinator: SharedSetupCoordinator
    lateinit var wearPhoneSyncScheduler: WearPhoneSyncScheduler

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val alreadyHandledExternalIntent =
            savedInstanceState?.getBoolean(STATE_HANDLED_EXTERNAL_INTENT) == true
        val restoredExternalBytes = savedInstanceState?.getByteArray(STATE_EXTERNAL_DOCUMENT_BYTES)
        val restoredImportFinished =
            savedInstanceState?.getBoolean(STATE_EXTERNAL_IMPORT_FINISHED) == true
        val sameProcess =
            savedInstanceState?.getString(STATE_SHARED_SETUP_PROCESS_ID) == sharedSetupCoordinator.processInstanceID
        handledExternalIntent = alreadyHandledExternalIntent
        when (
            SharedSetupIntentExtractor.restorationAction(
                wasHandled = alreadyHandledExternalIntent,
                wasFinished = restoredImportFinished,
                hasRestorableBytes = restoredExternalBytes != null,
                sameProcess = sameProcess,
            )
        ) {
            SharedSetupIntentRestoreAction.ACCEPT_SYSTEM_URI ->
                handleLaunchIntent(intent, acceptExternalDocument = true)
            SharedSetupIntentRestoreAction.RESTORE_BYTES -> {
                sharedSetupCoordinator.restoreExternalBytes(requireNotNull(restoredExternalBytes))
                handleLaunchIntent(intent, acceptExternalDocument = false)
            }
            SharedSetupIntentRestoreAction.SKIP -> {
                if (restoredImportFinished) sharedSetupCoordinator.finishExternalImport()
                handleLaunchIntent(intent, acceptExternalDocument = false)
            }
        }
        enableEdgeToEdge()
        // Editing authority (export-profile decision 1): bootstrap the Default profile,
        // apply the active profile onto live settings, and keep edits flushing back.
        exportProfileCoordinator.ensureStarted()
        observeActiveExports()
        setContent {
            HealthMdTheme {
                HealthMdNavigation(
                    settingsRepository = settingsRepository,
                    sharedSetupCoordinator = sharedSetupCoordinator,
                    initialRoute = startRoute,
                    scheduledRecoveryPromptRequestId = scheduledRecoveryPromptRequestId,
                )
            }
        }
    }

    override fun onSaveInstanceState(outState: Bundle) {
        outState.putBoolean(STATE_HANDLED_EXTERNAL_INTENT, handledExternalIntent)
        if (handledExternalIntent) {
            outState.putString(STATE_SHARED_SETUP_PROCESS_ID, sharedSetupCoordinator.processInstanceID)
            outState.putBoolean(
                STATE_EXTERNAL_IMPORT_FINISHED,
                sharedSetupCoordinator.isExternalImportFinished(),
            )
            sharedSetupCoordinator.restorableExternalBytes()?.let {
                outState.putByteArray(STATE_EXTERNAL_DOCUMENT_BYTES, it)
            }
        }
        super.onSaveInstanceState(outState)
    }

    override fun onResume() {
        super.onResume()
        lifecycleScope.launch {
            runCatching { exportScheduler.reconcile() }
            runCatching { widgetLifecycle.refreshFromForeground() }
            runCatching { wearPhoneSyncScheduler.reconcile() }
        }
    }

    private fun observeActiveExports() {
        lifecycleScope.launch {
            repeatOnLifecycle(Lifecycle.State.STARTED) {
                ExportAwakeCoordinator.shared.isExportActive.collectLatest { isActive ->
                    if (isActive) {
                        window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    } else {
                        window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    }
                }
            }
        }
    }

    override fun onNewIntent(intent: Intent) {
        super.onNewIntent(intent)
        setIntent(intent)
        handleLaunchIntent(intent, acceptExternalDocument = true)
    }

    private fun handleLaunchIntent(intent: Intent?, acceptExternalDocument: Boolean) {
        if (acceptExternalDocument) {
            SharedSetupIntentExtractor.uri(intent)?.let { uri ->
                // Record ownership synchronously. The singleton coordinator keeps provider IO alive
                // across Activity recreation and SavedStateHandle restores Review or Success after
                // process death, so the retained system intent must not be applied twice.
                handledExternalIntent = true
                sharedSetupCoordinator.acceptExternalUriAsync(uri)
            }
        }
        startRoute = intent?.getStringExtra(EXTRA_START_ROUTE)
        intent?.getStringExtra(EXTRA_GOOGLE_DRIVE_OPERATION_ID)
            ?.takeIf { it.matches(Regex("[A-Za-z0-9._-]{1,128}")) }
            ?.let { googleDriveOperationId = it }
        if (intent?.getBooleanExtra(EXTRA_PROMPT_SCHEDULED_RECOVERY, false) == true) {
            scheduledRecoveryPromptRequestId = System.currentTimeMillis()
        }
    }

    internal fun consumeGoogleDriveOperationId(operationId: String) {
        if (googleDriveOperationId == operationId) googleDriveOperationId = null
    }
}
