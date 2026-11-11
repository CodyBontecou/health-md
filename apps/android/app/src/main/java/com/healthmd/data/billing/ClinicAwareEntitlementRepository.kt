package com.healthmd.data.billing

import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.repository.EntitlementRepository
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn

/** General unlock flags remain personal. Only destination-aware admission can use sponsorship. */
class ClinicAwareEntitlementRepository(
    private val personal: EntitlementRepository,
    private val clinic: ClinicSponsorshipManager,
) : EntitlementRepository by personal {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    override val canEnterApp = combine(personal.isUnlocked, clinic.status) { unlocked, sponsorship ->
        unlocked || sponsorship.active
    }.stateIn(scope, SharingStarted.Eagerly, personal.isUnlocked.value)

    override val sponsoredEndpoint = clinic.status.map {
        it.endpoint.takeIf { _ -> it.active && it.sharingAuthorized }
    }.stateIn(scope, SharingStarted.Eagerly, null)

    override suspend fun verifyExportAccess(target: ExportTarget, endpoint: String?): Boolean {
        if (personal.verifyAccess()) return true
        if (target != ExportTarget.API_ENDPOINT || endpoint == null) return false
        clinic.refresh()
        return clinic.authorizeCached(endpoint).isAllowed
    }

    override suspend fun clinicUploadAuthorization(endpoint: String): String? = clinic.uploadAuthorization(endpoint)
}
