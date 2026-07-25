package com.healthmd.presentation.directcli

import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.direct.DirectCliConnectionState
import com.healthmd.direct.DirectCliCoordinator
import com.healthmd.direct.DirectCliForegroundService
import com.healthmd.direct.DirectCliTrustStore
import com.healthmd.direct.protocol.DIRECT_PORT
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.launch

data class DirectCliUiState(
    val host: String = "",
    val port: String = DIRECT_PORT.toString(),
    val pairingCode: String = "",
    val pairedListenerName: String? = null,
    val connection: DirectCliConnectionState = DirectCliConnectionState.Idle,
) {
    val hasTrust: Boolean get() = pairedListenerName != null
    val canPair: Boolean
        get() = host.isNotBlank() && port.toIntOrNull() in 1..65_535 &&
            pairingCode.count { it in '0'..'9' } == 20
}

@HiltViewModel
class DirectCliViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    private val trustStore: DirectCliTrustStore,
    coordinator: DirectCliCoordinator,
) : ViewModel() {
    private val saved = trustStore.load()
    private val _uiState = MutableStateFlow(DirectCliUiState(
        host = saved?.host.orEmpty(),
        port = (saved?.port ?: DIRECT_PORT).toString(),
        pairedListenerName = saved?.displayName,
    ))
    val uiState: StateFlow<DirectCliUiState> = _uiState.asStateFlow()
    val connection: StateFlow<DirectCliConnectionState> = coordinator.state

    init {
        viewModelScope.launch {
            connection.collectLatest { state ->
                if (state is DirectCliConnectionState.Completed) refreshTrust()
            }
        }
    }

    fun updateHost(value: String) {
        _uiState.value = _uiState.value.copy(host = value.trim())
    }

    fun updatePort(value: String) {
        _uiState.value = _uiState.value.copy(port = value.filter(Char::isDigit).take(5))
    }

    fun updatePairingCode(value: String) {
        _uiState.value = _uiState.value.copy(
            pairingCode = value.filter { it in '0'..'9' }.take(20),
        )
    }

    fun pair() {
        val state = _uiState.value
        if (!state.canPair) return
        DirectCliForegroundService.pair(
            context = context,
            host = state.host,
            port = requireNotNull(state.port.toIntOrNull()),
            pairingCode = state.pairingCode,
        )
        _uiState.value = state.copy(pairingCode = "")
    }

    fun saveEndpoint() {
        val state = _uiState.value
        val port = state.port.toIntOrNull() ?: return
        if (state.host.isNotBlank() && port in 1..65_535 && trustStore.load() != null) {
            trustStore.updateEndpoint(state.host, port)
            refreshTrust()
        }
    }

    fun connect() {
        if (trustStore.load() != null) DirectCliForegroundService.connect(context)
    }

    fun disconnect() {
        DirectCliForegroundService.stop(context)
    }

    fun forget() {
        DirectCliForegroundService.forget(context)
        _uiState.value = DirectCliUiState()
    }

    fun refreshTrust() {
        val trust = trustStore.load()
        _uiState.value = _uiState.value.copy(
            host = trust?.host ?: _uiState.value.host,
            port = (trust?.port ?: _uiState.value.port.toIntOrNull() ?: DIRECT_PORT).toString(),
            pairedListenerName = trust?.displayName,
        )
    }
}
