package com.healthmd.sharedsetup

import com.healthmd.data.export.APIExportAuthorization
import com.healthmd.data.export.APIExportAuthorizationValidationException
import com.healthmd.data.export.APIExportAuthorizationValidationResult
import com.healthmd.data.export.APIExportCredentialStore
import com.healthmd.data.export.APIExportRequestHeader
import com.healthmd.data.scheduler.ExportScheduler
import com.healthmd.domain.model.APIExportEndpoint
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.repository.SettingsRepository
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

@Singleton
class SharedSetupService private constructor(
    private val repository: SettingsRepository,
    private val scheduler: ExportScheduler,
    private val credentialStore: APIExportCredentialStore,
    private val codec: SharedSetupCodec,
    private val mapper: SharedSetupMapper,
) {
    @Inject
    constructor(
        repository: SettingsRepository,
        scheduler: ExportScheduler,
        credentialStore: APIExportCredentialStore,
    ) : this(
        repository,
        scheduler,
        credentialStore,
        SharedSetupCodec(),
        SharedSetupMapper(),
    )

    internal constructor(
        repository: SettingsRepository,
        scheduler: ExportScheduler,
        credentialStore: APIExportCredentialStore,
        registry: SharedSetupMetricRegistry,
    ) : this(
        repository,
        scheduler,
        credentialStore,
        SharedSetupCodec(registry),
        SharedSetupMapper(registry),
    )

    private val extensionJson = Json { ignoreUnknownKeys = true; encodeDefaults = true }
    private val transactionMutex = Mutex()

    suspend fun exportBytes(): ByteArray {
        val preservedAppleExtension = repository.getPreservedSharedSetupAppleExtension()?.let { encoded ->
            runCatching { extensionJson.decodeFromString<SharedSetupAppleExtension>(encoded) }.getOrNull()
        }
        return codec.encode(mapper.export(repository.getExportSettings(), preservedAppleExtension))
    }

    suspend fun pendingEndpoint(): String? = repository.getPendingSharedSetupEndpoint()

    /** Bounded decode and compatibility analysis only. This method performs zero writes. */
    suspend fun preview(bytes: ByteArray): Result<SharedSetupPreview> = when (val decoded = codec.decode(bytes)) {
        is SharedSetupDecodeResult.Invalid -> Result.failure(IllegalArgumentException(decoded.message))
        is SharedSetupDecodeResult.Valid -> Result.success(mapper.preview(decoded.document, repository.getExportSettings()))
    }

    suspend fun apply(preview: SharedSetupPreview): Result<SharedSetupApplyResult> = transactionMutex.withLock {
        var committedCandidate: ExportSettings? = null
        var previousSettings: ExportSettings? = null
        var previousEndpoint: String? = null
        var previousAppleExtension: String? = null
        val outcome = runCatching {
            val current = repository.getExportSettings().normalized()
            previousSettings = current
            previousEndpoint = repository.getPendingSharedSetupEndpoint()
            previousAppleExtension = repository.getPreservedSharedSetupAppleExtension()
            check(current == preview.expectedCurrent) {
                "Settings changed after review. Review the shared setup again."
            }
            val safeCandidate = preview.candidate.copy(
                scheduleEnabled = false,
                pendingScheduledRetryDates = emptyList(),
                pendingScheduledExportRequests = emptyList(),
                executionEnginePin = null,
                executionEngineAuthorityIsFrozen = false,
            ).normalized()

            // Cancel first so no stale occurrence can start after the settings commit. If either
            // cancellation or the atomic DataStore edit fails, settings remain unchanged.
            scheduler.cancel()
            val preservedAppleExtension = preview.document.platformExtensions.apple?.let {
                extensionJson.encodeToString(it)
            }
            val applied = repository.applySharedSetupTransaction(
                expectedCurrent = current,
                candidate = safeCandidate,
                pendingEndpoint = preview.pendingEndpoint,
                preservedAppleExtension = preservedAppleExtension,
            )
            if (!applied) {
                runCatching { scheduler.reconcile() }
                error("Settings changed while applying. Review the shared setup again.")
            }
            committedCandidate = safeCandidate
            check(repository.getExportSettings() == safeCandidate) {
                "Shared setup persistence verification failed."
            }
            check(repository.getPendingSharedSetupEndpoint() == preview.pendingEndpoint) {
                "Pending endpoint persistence verification failed."
            }
            check(repository.getPreservedSharedSetupAppleExtension() == preservedAppleExtension) {
                "Apple extension persistence verification failed."
            }
            SharedSetupApplyResult(preview.review, canUndo = true)
        }
        if (outcome.isFailure && committedCandidate != null) {
            val rollback = runCatching {
                val restored = repository.rollbackSharedSetupTransaction(requireNotNull(committedCandidate))
                    ?: error("Health.md could not restore the setup because settings changed during rollback.")
                check(restored.normalized() == previousSettings && repository.getExportSettings() == previousSettings) {
                    "Shared setup settings rollback verification failed."
                }
                check(repository.getPendingSharedSetupEndpoint() == previousEndpoint) {
                    "Shared setup endpoint rollback verification failed."
                }
                check(repository.getPreservedSharedSetupAppleExtension() == previousAppleExtension) {
                    "Shared setup extension rollback verification failed."
                }
            }
            runCatching { scheduler.reconcile() }
            if (rollback.isFailure) {
                return@withLock Result.failure(
                    IllegalStateException(
                        "The shared setup failed and the previous setup could not be verified as restored.",
                        rollback.exceptionOrNull(),
                    )
                )
            }
        } else if (outcome.isFailure) {
            runCatching { scheduler.reconcile() }
        }
        outcome
    }

    suspend fun confirmPendingEndpoint(authorization: String): Result<Unit> = transactionMutex.withLock {
        // Fail closed: if the prior secure-store state cannot be read, no verified rollback would
        // ever be possible, so no credential or endpoint mutation is attempted at all.
        val priorAuthorizationRead = runCatching { credentialStore.authorizationHeader() }
        val priorHeadersRead = runCatching { credentialStore.requestHeaders() }
        if (priorAuthorizationRead.isFailure || priorHeadersRead.isFailure) {
            return@withLock Result.failure(
                IllegalStateException("Endpoint credentials could not be read safely. Try again."),
            )
        }
        val previousAuthorization = priorAuthorizationRead.getOrNull()
        val previousHeaders = priorHeadersRead.getOrDefault(emptyList())
        var pending: String? = null
        var previousSettings: ExportSettings? = null
        var confirmedSettings: ExportSettings? = null
        var endpointCommitted = false
        val outcome = runCatching {
            pending = repository.getPendingSharedSetupEndpoint()
                ?: error("There is no imported endpoint waiting for confirmation.")
            val endpoint = requireNotNull(pending)
            val normalized = APIExportEndpoint.normalizedOrNull(endpoint)
            check(normalized == endpoint && endpoint.startsWith("https://")) {
                "The imported endpoint hint is no longer valid."
            }
            val current = repository.getExportSettings().normalized()
            val candidate = current.copy(apiEndpointUrl = endpoint).normalized()
            previousSettings = current
            confirmedSettings = candidate

            // Clear first so neither authorization nor custom request headers from another
            // destination can become attached to the imported endpoint.
            credentialStore.clearAuthorization()
            credentialStore.clearRequestHeaders()
            credentialStore.saveAuthorization(authorization)
            // Verify the persisted secure-store state before committing the endpoint to DataStore:
            // the exact normalized credential must be present and no foreign headers may remain.
            val expectedAuthorization = when (val validated = APIExportAuthorization.validate(authorization)) {
                is APIExportAuthorizationValidationResult.Valid -> validated.normalizedValue
                is APIExportAuthorizationValidationResult.Invalid ->
                    throw APIExportAuthorizationValidationException(validated.reason)
            }
            check(
                credentialStore.authorizationHeader() == expectedAuthorization &&
                    credentialStore.requestHeaders().isEmpty()
            ) {
                "The new endpoint credential could not be verified."
            }

            check(repository.confirmSharedSetupEndpoint(current, endpoint, candidate)) {
                "Settings changed while confirming the endpoint. Try again."
            }
            endpointCommitted = true
            check(repository.getExportSettings() == candidate && repository.getPendingSharedSetupEndpoint() == null) {
                "Endpoint confirmation persistence verification failed."
            }
        }
        if (outcome.isSuccess) return@withLock outcome

        val endpointRolledBack = if (endpointCommitted) {
            val expected = confirmedSettings
            val restored = previousSettings
            val endpoint = pending
            expected != null && restored != null && endpoint != null &&
                runCatching {
                    repository.rollbackSharedSetupEndpointConfirmation(expected, restored, endpoint)
                }.getOrDefault(false)
        } else {
            true
        }
        val credentialRollback = runCatching {
            credentialStore.clearAuthorization()
            credentialStore.clearRequestHeaders()
            // Restore prior credentials only when the prior endpoint was also restored. If a
            // concurrent edit prevented rollback, leaving credentials empty fails closed.
            if (endpointRolledBack) {
                previousAuthorization?.let { credentialStore.saveAuthorization(it) }
                if (previousHeaders.isNotEmpty()) {
                    credentialStore.saveRequestHeaders(
                        previousHeaders.joinToString("\n") { header -> "${header.name}: ${header.value}" }
                    )
                }
            }
        }
        val rollbackVerified = credentialRollback.isSuccess && runCatching {
            if (endpointRolledBack) {
                credentialStore.authorizationHeader() == previousAuthorization &&
                    credentialStore.requestHeaders() == previousHeaders
            } else {
                credentialStore.authorizationHeader() == null &&
                    credentialStore.requestHeaders().isEmpty()
            }
        }.getOrDefault(false)
        if (!rollbackVerified) {
            // Never leave an unverifiable credential attached to any endpoint. Attempt a verified
            // clear, and only state that credentials were cleared when that clear is attested.
            val failClosedClear = runCatching {
                credentialStore.clearAuthorization()
                credentialStore.clearRequestHeaders()
            }
            val failClosedVerified = failClosedClear.isSuccess && runCatching {
                credentialStore.authorizationHeader() == null &&
                    credentialStore.requestHeaders().isEmpty()
            }.getOrDefault(false)
            return@withLock Result.failure(
                IllegalStateException(
                    if (failClosedVerified) {
                        "The endpoint failed and the previous credential could not be verified as restored; credentials were cleared."
                    } else {
                        "The endpoint failed and the previous credential could not be verified as restored."
                    },
                    outcome.exceptionOrNull(),
                ),
            )
        }
        outcome
    }

    suspend fun undo(): Result<Unit> = transactionMutex.withLock {
        var priorAuthorization: String? = null
        var priorHeaders: List<APIExportRequestHeader> = emptyList()
        var cleanupAttempted = false
        var undoCommitted = false
        val outcome = runCatching {
            val current = repository.getExportSettings().normalized()
            val snapshot = repository.getSharedSetupUndo()
                ?: error("No shared setup import is available to undo.")
            val endpointChanges = snapshot.normalized().apiEndpointUrl != current.apiEndpointUrl
            if (endpointChanges) {
                // Clean up first while the Undo snapshot still exists. A secure-store failure now
                // leaves DataStore untouched and retryable. If DataStore later fails, credentials
                // are restored to the still-current endpoint below.
                priorAuthorization = credentialStore.authorizationHeader()
                priorHeaders = credentialStore.requestHeaders()
                cleanupAttempted = true
                credentialStore.clearAuthorization()
                credentialStore.clearRequestHeaders()
                check(credentialStore.authorizationHeader() == null && credentialStore.requestHeaders().isEmpty()) {
                    "Endpoint credentials could not be cleared safely during Undo."
                }
            }
            scheduler.cancel()
            val restored = repository.undoSharedSetupTransaction(current)
                ?: error("Settings changed while undoing. Try again after reviewing current settings.")
            undoCommitted = true
            check(repository.getExportSettings() == restored.normalized()) { "Undo persistence verification failed." }
            scheduler.reconcile()
        }
        if (outcome.isFailure && cleanupAttempted) {
            runCatching {
                credentialStore.clearAuthorization()
                credentialStore.clearRequestHeaders()
                if (!undoCommitted) {
                    priorAuthorization?.let { credentialStore.saveAuthorization(it) }
                    if (priorHeaders.isNotEmpty()) {
                        credentialStore.saveRequestHeaders(
                            priorHeaders.joinToString("\n") { header -> "${header.name}: ${header.value}" }
                        )
                    }
                }
            }.onFailure {
                // A failed credential restoration must still fail closed rather than bind a secret
                // to the wrong endpoint.
                runCatching { credentialStore.clearAuthorization() }
                runCatching { credentialStore.clearRequestHeaders() }
            }
        }
        if (outcome.isFailure) runCatching { scheduler.reconcile() }
        outcome
    }
}
