package com.healthmd.domain.repository

/** Creates an independent capture view; readiness and permissions remain live checks. */
interface OperationScopedHealthRepository {
    suspend fun forCaptureOperation(): HealthRepository
}

suspend fun HealthRepository.forCaptureOperation(): HealthRepository =
    (this as? OperationScopedHealthRepository)?.forCaptureOperation() ?: this
