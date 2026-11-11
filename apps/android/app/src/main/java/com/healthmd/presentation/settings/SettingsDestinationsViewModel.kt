package com.healthmd.presentation.settings

import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import com.healthmd.data.export.APIExportAuthorization
import com.healthmd.data.export.APIExportHeaders
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportRequestHeader
import com.healthmd.data.scheduler.ExportScheduler
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.AgentDataGatewayEndpoint
import com.healthmd.domain.model.ExportHistoryEntry
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.ExportHistoryRepository
import com.healthmd.domain.repository.SettingsRepository
import dagger.hilt.android.lifecycle.HiltViewModel
import java.net.HttpURLConnection
import java.net.URL
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

/** Health-free facts the Settings destination pages derive from local export history. */
object SettingsDestinationActivity {
    /** The newest run that wrote anything to [target], as epoch millis. */
    fun lastSuccess(target: ExportTarget, history: List<ExportHistoryEntry>): Long? =
        history.filter { it.target == target && it.successCount > 0 }.maxOfOrNull { it.timestamp }

    /** "200 OK", "401 Unauthorized"; HTTP reason phrases are protocol tokens, shown untranslated. */
    fun httpStatusText(code: Int): String = REASON_PHRASES[code]?.let { "$code $it" } ?: "HTTP $code"

    /** Redirects and successes prove the host, TLS and path answer; a POST-only 405 does too. */
    fun isReachable(code: Int): Boolean = code in 200 until 400 || code == 405

    private val REASON_PHRASES = mapOf(
        200 to "OK", 201 to "Created", 202 to "Accepted", 204 to "No Content",
        301 to "Moved Permanently", 302 to "Found", 304 to "Not Modified",
        307 to "Temporary Redirect", 308 to "Permanent Redirect",
        400 to "Bad Request", 401 to "Unauthorized", 403 to "Forbidden", 404 to "Not Found",
        405 to "Method Not Allowed", 408 to "Request Timeout", 409 to "Conflict",
        413 to "Content Too Large", 415 to "Unsupported Media Type", 429 to "Too Many Requests",
        500 to "Internal Server Error", 501 to "Not Implemented", 502 to "Bad Gateway",
        503 to "Service Unavailable", 504 to "Gateway Timeout",
    )
}

/** Sends a HEAD request so a configured endpoint can be checked without sending health data. */
fun interface EndpointConnectionTester {
    suspend fun statusCode(url: String, authorization: String?, headers: List<APIExportRequestHeader>): Int
}

open class HeadRequestConnectionTester @Inject constructor() : EndpointConnectionTester {
    override suspend fun statusCode(
        url: String,
        authorization: String?,
        headers: List<APIExportRequestHeader>,
    ): Int = withContext(Dispatchers.IO) {
        val connection = URL(url).openConnection() as HttpURLConnection
        try {
            connection.requestMethod = "HEAD"
            connection.instanceFollowRedirects = false
            connection.connectTimeout = TIMEOUT_MS
            connection.readTimeout = TIMEOUT_MS
            connection.useCaches = false
            connection.setRequestProperty("Accept", "application/json")
            connection.setRequestProperty("User-Agent", "Health.md Android API Export")
            headers.forEach { connection.setRequestProperty(it.name, it.value) }
            authorization?.let { connection.setRequestProperty("Authorization", it) }
            connection.responseCode
        } finally {
            connection.disconnect()
        }
    }

    private companion object {
        const val TIMEOUT_MS = 15_000
    }
}

sealed interface ConnectionTestState {
    data object Idle : ConnectionTestState
    data object Running : ConnectionTestState
    data class Finished(val statusCode: Int) : ConnectionTestState
    data object Failed : ConnectionTestState
}

/**
 * State for Settings' destination and support pages: last deliveries from export history,
 * clearing that history, the API connection test, and removing a saved endpoint or gateway.
 * Saving endpoints stays with [com.healthmd.presentation.export.ExportViewModel].
 */
@HiltViewModel
class SettingsDestinationsViewModel @Inject constructor(
    private val historyRepository: ExportHistoryRepository,
    private val settingsRepository: SettingsRepository,
    private val credentialStore: APIExportCredentialStore,
    private val tester: HeadRequestConnectionTester,
    private val exportScheduler: ExportScheduler? = null,
) : ViewModel() {
    val history: StateFlow<List<ExportHistoryEntry>> = historyRepository.getAllEntries()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    private val _connectionTest = MutableStateFlow<ConnectionTestState>(ConnectionTestState.Idle)
    val connectionTest: StateFlow<ConnectionTestState> = _connectionTest.asStateFlow()
    private var testJob: Job? = null

    fun clearHistory() {
        viewModelScope.launch { historyRepository.clearAll() }
    }

    /** A draft edit makes an earlier result stale. */
    fun resetConnectionTest() {
        testJob?.cancel()
        _connectionTest.value = ConnectionTestState.Idle
    }

    /**
     * Tests the draft URL. A typed token is used as entered; otherwise the saved Authorization
     * and custom headers go with the request. Nonblank drafts replace the stored values;
     * invalid drafts fail without falling back to saved credentials or making a request.
     */
    fun testConnection(draftUrl: String, draftAuthorization: String, draftHeaders: String = "") {
        val url = APIExportEndpoint.normalizedOrNull(draftUrl) ?: return
        testJob?.cancel()
        _connectionTest.value = ConnectionTestState.Running
        testJob = viewModelScope.launch {
            _connectionTest.value = try {
                val typedAuthorization = draftAuthorization.takeIf { it.isNotBlank() }?.let {
                    requireNotNull(APIExportAuthorization.normalizeOrNull(it))
                }
                val typedHeaders = draftHeaders.takeIf { it.isNotBlank() }?.let(APIExportHeaders::parse)
                val authorization = typedAuthorization ?: credentialStore.authorizationHeader()
                val headers = typedHeaders ?: credentialStore.requestHeaders()
                ConnectionTestState.Finished(tester.statusCode(url, authorization, headers))
            } catch (cancelled: CancellationException) {
                throw cancelled
            } catch (_: Exception) {
                ConnectionTestState.Failed
            }
        }
    }

    /** Clears the endpoint and its stored credentials; Export now falls back to the folder. */
    fun removeApiEndpoint() {
        viewModelScope.launch {
            credentialStore.clearAuthorization()
            credentialStore.clearRequestHeaders()
            settingsRepository.updateExportSettingsAtomically { current ->
                current.copy(
                    apiEndpointUrl = "",
                    exportTarget = if (current.exportTarget == ExportTarget.API_ENDPOINT) {
                        ExportTarget.DEVICE_FOLDER
                    } else {
                        current.exportTarget
                    },
                )
            }
            resetConnectionTest()
            runCatching { exportScheduler?.reconcile() }
        }
    }

    fun removeGateway() {
        viewModelScope.launch {
            settingsRepository.updateExportSettingsAtomically { current ->
                current.copy(
                    agentDataGatewayUrl = "",
                    exportTarget = if (current.exportTarget == ExportTarget.AGENT_DATA_GATEWAY) {
                        ExportTarget.DEVICE_FOLDER
                    } else {
                        current.exportTarget
                    },
                )
            }
            runCatching { exportScheduler?.reconcile() }
        }
    }

    companion object {
        fun apiConfigured(url: String) = APIExportEndpoint.isConfigured(url)
        fun gatewayConfigured(url: String) = AgentDataGatewayEndpoint.isConfigured(url)
    }
}
