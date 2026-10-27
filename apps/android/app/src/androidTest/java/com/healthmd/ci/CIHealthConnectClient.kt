package com.healthmd.ci

import androidx.health.connect.client.HealthConnectClient
import androidx.health.connect.client.HealthConnectFeatures
import androidx.health.connect.client.PermissionController
import androidx.health.connect.client.aggregate.AggregationResult
import androidx.health.connect.client.permission.HealthPermission
import androidx.health.connect.client.records.StepsRecord
import androidx.health.connect.client.response.ReadRecordsResponse
import java.lang.reflect.Proxy

/** Only SDK responses are synthetic; native capture, rendering and writes stay real. */
internal fun ciHealthConnectClient(): HealthConnectClient {
    // This SDK fixture is deliberately pinned to the locked connect-client version.
    val aggregate = AggregationResult(mapOf("Steps_count_total" to 1234L), emptyMap(), emptySet())
    check(aggregate[StepsRecord.COUNT_TOTAL] == 1234L)
    val permissions = object : PermissionController {
        override suspend fun getGrantedPermissions() = setOf(HealthPermission.getReadPermission(StepsRecord::class))
        override suspend fun revokeAllPermissions() = error("CI capture is read-only")
    }
    val features = object : HealthConnectFeatures {
        override fun getFeatureStatus(feature: Int) = HealthConnectFeatures.FEATURE_STATUS_UNAVAILABLE
    }
    return HealthConnectClient::class.java.cast(Proxy.newProxyInstance(
        HealthConnectClient::class.java.classLoader,
        arrayOf(HealthConnectClient::class.java),
    ) { proxy, method, arguments ->
        when (method.name) {
            "getPermissionController" -> permissions
            "getFeatures" -> features
            "aggregate" -> aggregate
            "aggregateGroupByPeriod", "aggregateGroupByDuration" -> emptyList<Any>()
            "readRecords" -> ReadRecordsResponse(emptyList<StepsRecord>(), null)
            "toString" -> "CIHealthConnectClient"
            "hashCode" -> System.identityHashCode(proxy)
            "equals" -> proxy === arguments?.firstOrNull()
            else -> error("CI SDK fixture does not support this operation")
        }
    })
}
