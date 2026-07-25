package com.healthmd.presentation.oauth

import android.os.Bundle
import androidx.activity.ComponentActivity
import android.widget.Toast
import com.healthmd.R
import com.healthmd.data.health.oauth.OAuthAuthorizationManager
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.AndroidEntryPoint
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.launch
import javax.inject.Inject

@AndroidEntryPoint
class OAuthCallbackActivity : ComponentActivity() {
    @Inject lateinit var oauthAuthorizationManager: OAuthAuthorizationManager
    @Inject lateinit var settingsRepository: SettingsRepository

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        val callbackUri = intent?.data
        if (callbackUri == null) {
            Toast.makeText(this, getString(R.string.health_provider_sign_in_failed), Toast.LENGTH_SHORT).show()
            finish()
            return
        }

        scope.launch {
            runCatching {
                val result = oauthAuthorizationManager.handleCallback(callbackUri)
                settingsRepository.setHealthProviderConnected(result.providerId, true)
                settingsRepository.setSelectedHealthProviderId(result.providerId)
                result
            }.onSuccess { result ->
                Toast.makeText(
                    this@OAuthCallbackActivity,
                    getString(R.string.health_provider_connected, result.providerId),
                    Toast.LENGTH_SHORT,
                ).show()
            }.onFailure { error ->
                Toast.makeText(
                    this@OAuthCallbackActivity,
                    error.message ?: getString(R.string.health_provider_sign_in_failed),
                    Toast.LENGTH_LONG,
                ).show()
            }
            finish()
        }
    }
}
