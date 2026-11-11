package com.healthmd.testing

import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.EntitlementRepository
import kotlinx.coroutines.flow.MutableStateFlow

class FakeExportEntitlements(
    var personalAccess: Boolean = true,
    var clinicEndpoint: String? = null,
    var clinicAuthorization: String? = null,
) : EntitlementRepository {
    override val isUnlocked = MutableStateFlow(personalAccess)
    override suspend fun verifyAccess() = personalAccess
    override suspend fun clinicUploadAuthorization(endpoint: String): String? =
        clinicAuthorization.takeIf { endpoint == clinicEndpoint }
    override suspend fun verifyExportAccess(target: ExportTarget, endpoint: String?) =
        personalAccess || (target == ExportTarget.API_ENDPOINT && endpoint != null && endpoint == clinicEndpoint)
    override fun refresh() = Unit
    override fun debugSetUnlocked(unlocked: Boolean) { personalAccess = unlocked; isUnlocked.value = unlocked }
    override fun debugReset() = debugSetUnlocked(false)
}
