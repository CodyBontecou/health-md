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
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.presentation.theme.HealthMdTheme
import com.healthmd.presentation.navigation.HealthMdNavigation
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
    }

    private var startRoute by mutableStateOf<String?>(null)
    private var scheduledRecoveryPromptRequestId by mutableStateOf(0L)

    @Inject
    lateinit var settingsRepository: SettingsRepository

    @Inject
    lateinit var exportScheduler: ExportScheduler

    @Inject
    lateinit var widgetLifecycle: HealthWidgetLifecycleCoordinator

    @Inject
    lateinit var wearPhoneSyncScheduler: WearPhoneSyncScheduler

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        handleLaunchIntent(intent)
        enableEdgeToEdge()
        observeActiveExports()
        setContent {
            HealthMdTheme {
                HealthMdNavigation(
                    settingsRepository = settingsRepository,
                    initialRoute = startRoute,
                    scheduledRecoveryPromptRequestId = scheduledRecoveryPromptRequestId,
                )
            }
        }
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
        handleLaunchIntent(intent)
    }

    private fun handleLaunchIntent(intent: Intent?) {
        startRoute = intent?.getStringExtra(EXTRA_START_ROUTE)
        if (intent?.getBooleanExtra(EXTRA_PROMPT_SCHEDULED_RECOVERY, false) == true) {
            scheduledRecoveryPromptRequestId = System.currentTimeMillis()
        }
    }
}
