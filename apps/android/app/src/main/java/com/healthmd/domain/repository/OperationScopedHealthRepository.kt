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
