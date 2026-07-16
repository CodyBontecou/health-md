package com.healthmd.rawchanges

import android.content.Context
import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.changes.DeletionChange
import androidx.health.connect.client.changes.UpsertionChange
import androidx.health.connect.client.records.Record
import androidx.health.connect.client.records.metadata.DataOrigin
import androidx.health.connect.client.request.ChangesTokenRequest
import com.healthmd.rawexport.HealthConnectRecordCatalog
import com.healthmd.rawexport.RawProviderCapabilities
import kotlin.reflect.KClass

/** Opaque by construction: no value-bearing toString, serialization, logging, or exception API. */
class SecretChangesToken internal constructor(internal val value: String) {
    init { require(value.isNotBlank()) { "Health Connect returned an empty changes token." } }
    override fun toString(): String = "<opaque-health-connect-changes-token>"
    override fun equals(other: Any?): Boolean = other is SecretChangesToken && value == other.value
    override fun hashCode(): Int = value.hashCode()
}

data class RawNativeIdentity(
    val nativeRecordId: String,
    val typeKey: String,
    val wireType: String,
    val dataOriginPackageName: String,
    val lastKnownRecordHash: String,
)

sealed interface NativeChange {
    data class Upsert(val record: com.healthmd.rawexport.RawRecord) : NativeChange
    data class Delete(val nativeRecordId: String) : NativeChange
}

data class NativeChangesPage(
    val changes: List<NativeChange>,
    val nextToken: SecretChangesToken?,
    val hasMore: Boolean,
    val tokenExpired: Boolean,
)

interface RawChangesSource {
    suspend fun capabilities(): RawProviderCapabilities
    suspend fun createToken(scope: RawChangesScope): SecretChangesToken
    suspend fun getChanges(token: SecretChangesToken): NativeChangesPage
}

class RawChangesProviderException(message: String) : Exception(message)

/** Direct, explicit adapter for connect-client 1.2.0-alpha02 getChangesToken/getChanges. */
class HealthConnectChangesSource(
    private val context: Context,
    private val client: HealthConnectClient,
) : RawChangesSource {
    private val descriptors = HealthConnectRecordCatalog.records.filter { it.changeEligible }
    private val byClass: Map<KClass<out Record>, com.healthmd.rawexport.HealthConnectRecordDescriptor<out Record>> =
        descriptors.associateBy { it.recordClass }

    override suspend fun capabilities(): RawProviderCapabilities {
        val available = HealthConnectClient.getSdkStatus(context) == HealthConnectClient.SDK_AVAILABLE
        if (!available) return RawProviderCapabilities(available = false)
        val permissions = try {
            client.permissionController.getGrantedPermissions()
        } catch (_: Exception) {
            emptySet()
        }
        val features = descriptors.mapNotNull { descriptor ->
            descriptor.featureGate?.takeIf { featureAvailable(it.feature) }?.let { descriptor.featureName }
        }.filterNotNull().toSortedSet()
        return RawProviderCapabilities(
            available = true,
            grantedPermissions = permissions.toSortedSet(),
            availableFeatures = features,
            historicalReadGranted = false,
        )
    }

    override suspend fun createToken(scope: RawChangesScope): SecretChangesToken {
        val canonical = scope.canonical()
        val requested = canonical.recordTypeKeys
        val selected = descriptors.filter { it.wireType in requested }
        require(selected.map { it.wireType }.toSet() == requested) { "Scope contains a type that is not Health Connect changes-eligible." }
        val unavailable = selected.filter { it.featureGate != null && !featureAvailable(it.featureGate.feature) }
        require(unavailable.isEmpty()) { "A selected Health Connect changes feature is unavailable." }
        return try {
            SecretChangesToken(
                client.getChangesToken(
                    ChangesTokenRequest(
                        recordTypes = selected.mapTo(linkedSetOf()) { it.recordClass },
                        dataOriginFilters = canonical.dataOriginPackageNames.mapTo(linkedSetOf()) { DataOrigin(it) },
                    ),
                ),
            )
        } catch (_: SecurityException) {
            throw RawChangesProviderException("Health Connect changes permission was not granted.")
        } catch (_: Exception) {
            // Do not retain a platform cause: some providers echo opaque request arguments.
            throw RawChangesProviderException("Health Connect could not create an incremental changes checkpoint.")
        }
    }

    override suspend fun getChanges(token: SecretChangesToken): NativeChangesPage = try {
        val response = client.getChanges(token.value)
        if (response.changesTokenExpired) {
            NativeChangesPage(emptyList(), null, hasMore = false, tokenExpired = true)
        } else {
            val mapped = response.changes.map { change ->
                when (change) {
                    is UpsertionChange -> {
                        val descriptor = byClass[change.record::class]
                            ?: throw RawChangesProviderException("Health Connect returned a record outside the pinned changes catalog.")
                        val record = descriptor.mapUntyped(change.record)
                            ?: throw RawChangesProviderException("The pinned raw mapper is unavailable for a changed record type.")
                        NativeChange.Upsert(record)
                    }
                    is DeletionChange -> NativeChange.Delete(change.recordId)
                    else -> throw RawChangesProviderException("Health Connect returned an unknown changes event kind.")
                }
            }
            NativeChangesPage(
                changes = mapped,
                nextToken = SecretChangesToken(response.nextChangesToken),
                hasMore = response.hasMore,
                tokenExpired = false,
            )
        }
    } catch (error: RawChangesProviderException) {
        throw error
    } catch (_: SecurityException) {
        throw RawChangesProviderException("Health Connect changes permission was revoked.")
    } catch (_: Exception) {
        // Never retain source messages/causes: platform errors can echo the opaque token.
        throw RawChangesProviderException("Health Connect incremental changes read failed.")
    }

    private fun featureAvailable(feature: Int): Boolean = try {
        client.features.getFeatureStatus(feature) == HealthConnectFeatures.FEATURE_STATUS_AVAILABLE
    } catch (_: Exception) {
        false
    }

    companion object {
        val changeEligibleTypeKeys: Set<String> = HealthConnectRecordCatalog.records
            .filter { it.changeEligible }
            .mapTo(linkedSetOf()) { it.wireType }
    }
}
