package com.healthmd.domain.repository

/** Creates an independent capture view; readiness and permissions remain live checks. */
interface OperationScopedHealthRepository {
    suspend fun forCaptureOperation(): HealthRepository
}

suspend fun HealthRepository.forCaptureOperation(): HealthRepository =
    (this as? OperationScopedHealthRepository)?.forCaptureOperation() ?: this

/** Private persistence boundary; restoration must not resolve current provider/account choices. */
interface RestorableHealthRepository {
    suspend fun captureProviderAuthority(): com.healthmd.domain.model.HealthProviderCaptureAuthority
    suspend fun restoreProviderAuthority(authority: com.healthmd.domain.model.HealthProviderCaptureAuthority): HealthRepository
}

/** Restores explicit job authority before capture. Missing recovered Morning authority is fatal. */
suspend fun HealthRepository.forCaptureOperation(settings: com.healthmd.domain.model.ExportSettings): HealthRepository {
    val authority = settings.executionProviderCaptureAuthority
    if (authority != null) {
        val restorable = this as? RestorableHealthRepository
            ?: error("This source cannot restore accepted provider authority")
        return restorable.restoreProviderAuthority(authority)
    }
    check(!settings.executionProviderCaptureAuthorityIsFrozen) { "Saved provider capture authority is unavailable" }
    return forCaptureOperation()
}
