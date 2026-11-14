package com.healthmd.presentation.endpoints

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.export.APIExportAuthorization
import com.healthmd.data.export.SavedAPIEndpointResult
import com.healthmd.data.export.SavedAPIEndpointStore
import com.healthmd.data.export.TokenChange
import com.healthmd.data.settings.ExportProfileRepository
import com.healthmd.data.settings.SavedAPIEndpointCoordinator
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.SavedAPIEndpoint
import com.healthmd.domain.model.SavedAPIEndpointError
import com.healthmd.domain.model.SavedAPIEndpointRules
import com.healthmd.presentation.settings.ConnectionTestState
import com.healthmd.presentation.settings.EndpointConnectionTester
import com.healthmd.presentation.settings.HeadRequestConnectionTester
import com.healthmd.util.runCatchingCancellable
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

/** A saved endpoint with the automations that send to it. */
data class SavedEndpointRow(val endpoint: SavedAPIEndpoint, val usedBy: List<String>)

/** The "New API endpoint" / edit sheet draft. */
data class EndpointSheetState(
    val editingId: String? = null,
    val name: String = SavedAPIEndpointRules.DEFAULT_NAME,
    val url: String = "",
    /** Typed token; blank keeps the saved token when editing. */
    val token: String = "",
    val showToken: Boolean = false,
    val hasSavedToken: Boolean = false,
    val removeSavedToken: Boolean = false,
    val error: SavedAPIEndpointError? = null,
    val test: ConnectionTestState = ConnectionTestState.Idle,
    val saving: Boolean = false,
    val confirmingDelete: Boolean = false,
) {
    val isEditing: Boolean get() = editingId != null
    val urlValid: Boolean get() = APIExportEndpoint.normalizedOrNull(url) != null
}

/**
 * Sheet validation, kept pure for tests: the same rules as the store, against the current list.
 * Saving does not require a passing (or any) connection test.
 */
internal fun validateEndpointSheet(state: EndpointSheetState, existing: List<SavedAPIEndpoint>): SavedAPIEndpointError? =
    SavedAPIEndpointRules.validate(state.name, state.url, state.token, existing, state.editingId) {
        APIExportAuthorization.normalizeOrNull(it) != null
    }

@HiltViewModel
class APIEndpointsViewModel @Inject constructor(
    private val coordinator: SavedAPIEndpointCoordinator,
    private val store: SavedAPIEndpointStore,
    profileRepository: ExportProfileRepository,
    private val tester: HeadRequestConnectionTester,
) : ViewModel() {
    private val connectionTester: EndpointConnectionTester = tester

    val rows: StateFlow<List<SavedEndpointRow>> = combine(coordinator.endpoints, profileRepository.profiles) { endpoints, profiles ->
        endpoints.map { endpoint -> SavedEndpointRow(endpoint, SavedAPIEndpointRules.profilesUsing(endpoint, profiles).map { it.name }) }
    }.stateIn(viewModelScope, SharingStarted.Eagerly, emptyList())

    private val _sheet = MutableStateFlow<EndpointSheetState?>(null)
    /** Null when the sheet is closed. */
    val sheet: StateFlow<EndpointSheetState?> = _sheet.asStateFlow()
    private var testJob: Job? = null

    init {
        viewModelScope.launch { runCatchingCancellable { coordinator.load() } }
    }

    fun openNew() {
        testJob?.cancel()
        _sheet.value = EndpointSheetState()
    }

    fun openEdit(id: String) {
        testJob?.cancel()
        val endpoint = coordinator.endpoints.value.firstOrNull { it.id == id } ?: return
        _sheet.value = EndpointSheetState(
            editingId = endpoint.id,
            name = endpoint.name,
            url = endpoint.url,
            hasSavedToken = endpoint.hasToken,
        )
    }

    fun dismiss() {
        testJob?.cancel()
        _sheet.value = null
    }

    fun update(transform: (EndpointSheetState) -> EndpointSheetState) {
        _sheet.update { state ->
            state?.let(transform)?.let { next ->
                // A changed URL or token makes an earlier test result stale.
                val stale = next.url != state.url || next.token != state.token || next.removeSavedToken != state.removeSavedToken
                next.copy(error = null, test = if (stale) ConnectionTestState.Idle else next.test)
            }
        }
        testJob?.takeIf { _sheet.value?.test == ConnectionTestState.Idle }?.cancel()
    }

    fun testConnection() {
        val state = _sheet.value ?: return
        val url = APIExportEndpoint.normalizedOrNull(state.url) ?: run {
            _sheet.update { it?.copy(error = SavedAPIEndpointError.INVALID_URL) }
            return
        }
        val typed = state.token.takeIf { it.isNotBlank() }?.let { raw ->
            APIExportAuthorization.normalizeOrNull(raw) ?: run {
                _sheet.update { it?.copy(error = SavedAPIEndpointError.INVALID_TOKEN) }
                return
            }
        }
        testJob?.cancel()
        _sheet.update { it?.copy(test = ConnectionTestState.Running) }
        testJob = viewModelScope.launch {
            val result = try {
                val authorization = typed ?: state.editingId
                    ?.takeIf { state.hasSavedToken && !state.removeSavedToken }
                    ?.let { store.authorization(it) }
                ConnectionTestState.Finished(connectionTester.statusCode(url, authorization, emptyList()))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                ConnectionTestState.Failed
            }
            _sheet.update { it?.copy(test = result) }
        }
    }

    /** Saves even when the test failed or never ran; [onSaved] receives the stored endpoint. */
    fun save(onSaved: (SavedAPIEndpoint) -> Unit = {}) {
        val state = _sheet.value ?: return
        validateEndpointSheet(state, coordinator.endpoints.value)?.let { error ->
            _sheet.update { it?.copy(error = error) }
            return
        }
        _sheet.update { it?.copy(saving = true) }
        viewModelScope.launch {
            val token = when {
                state.token.isNotBlank() -> TokenChange.Set(state.token)
                state.removeSavedToken -> TokenChange.Remove
                else -> TokenChange.Keep
            }
            when (val result = runCatchingCancellable { coordinator.save(state.editingId, state.name, state.url, token) }
                .getOrElse { SavedAPIEndpointResult.Invalid(SavedAPIEndpointError.INVALID_URL) }) {
                is SavedAPIEndpointResult.Saved -> {
                    testJob?.cancel()
                    _sheet.value = null
                    onSaved(result.endpoint)
                }
                is SavedAPIEndpointResult.Invalid -> _sheet.update { it?.copy(saving = false, error = result.error) }
            }
        }
    }

    fun requestDelete(confirm: Boolean) = _sheet.update { it?.copy(confirmingDelete = confirm) }

    /** Deletes the endpoint; automations using it become "not configured". */
    fun delete(onDeleted: (SavedAPIEndpoint) -> Unit = {}) {
        val id = _sheet.value?.editingId ?: return
        viewModelScope.launch {
            val removed = runCatchingCancellable { coordinator.delete(id) }.getOrNull()
            _sheet.value = null
            removed?.let(onDeleted)
        }
    }

    /** Binds an endpoint to the active automation (the onboarding Daily note). */
    fun bindToActive(endpoint: SavedAPIEndpoint) {
        viewModelScope.launch { runCatchingCancellable { coordinator.bindToActive(endpoint) } }
    }
}
