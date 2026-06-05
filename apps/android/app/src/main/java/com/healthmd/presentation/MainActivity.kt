package com.healthmd.presentation

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.presentation.theme.HealthMdTheme
import com.healthmd.presentation.navigation.HealthMdNavigation
import dagger.hilt.android.AndroidEntryPoint
import javax.inject.Inject

@AndroidEntryPoint
class MainActivity : ComponentActivity() {

    companion object {
        const val EXTRA_START_ROUTE = "com.healthmd.START_ROUTE"
    }

    @Inject
    lateinit var settingsRepository: SettingsRepository

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            HealthMdTheme {
                HealthMdNavigation(
                    settingsRepository = settingsRepository,
                    initialRoute = intent?.getStringExtra(EXTRA_START_ROUTE),
                )
            }
        }
    }
}
