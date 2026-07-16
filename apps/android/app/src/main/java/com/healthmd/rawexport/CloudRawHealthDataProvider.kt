package com.healthmd.rawexport

import com.healthmd.data.health.providers.cloud.CloudHealthApiClient
import com.healthmd.data.health.providers.cloud.CloudHealthRawResponse
import com.healthmd.data.health.providers.cloud.CloudNativeEndpointResult
import com.healthmd.data.health.providers.cloud.CloudNativeRawPageProvider
import com.healthmd.data.health.providers.cloud.CloudProviderFidelity
import java.util.Base64
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flow
import kotlinx.serialization.json.JsonObject

/** Maps each exact successful cloud page directly to one provider_payload RawRecord. */
class CloudRawHealthDataProvider(
    private val source: CloudNativeRawPageProvider,
    private val apiClient: CloudHealthApiClient,
) : RawHealthDataProvider {
    private val definitions = source.rawEndpointDefinitions
        .map { it.copy(providerId = source.rawProviderId, metricIds = it.metricIds.toSortedSet()) }
        .sortedBy { it.typeKey }

    init {
        require(source.rawFidelityDeclaration.fidelity == CloudProviderFidelity.NATIVE_API_PAYLOAD) {
            "A normalized-only or unsupported provider cannot claim native_api_payload"
        }
        require(definitions.isNotEmpty() && definitions.map { it.typeKey }.distinct().size == definitions.size)
    }

    override fun typeDefinitions(): List<RawProviderTypeDefinition> = definitions

    override suspend fun capabilities(): RawProviderCapabilities {
        val token = apiClient.token(source.rawProviderId)
        val available = token != null || apiClient.isConfigured(source.rawProviderId)
        val authorized = token != null
        return RawProviderCapabilities(
            sdkVersion = "provider-native-http-v1",
            available = available,
            providerId = source.rawProviderId,
            fidelityLevel = RawProviderFidelity.NATIVE_API_PAYLOAD,
            grantedPermissions = if (authorized) setOf("oauth_connected") else emptySet(),
            availableFeatures = definitions.filterNot { it.typeKey.startsWith("unsupported/") }
                .map { it.typeKey }.toSortedSet(),
            historicalReadGranted = authorized,
            nonTransactional = true,
            preservesSourceUnits = true,
            preservesUnknownSdkFields = true,
        )
    }

    override fun stream(request: RawSnapshotRequest): Flow<RawExportItem> = flow {
        emit(RawExportItem.Status(RawSnapshotStatus.RUNNING))
        val capabilities = capabilities()
        val selected = definitions.filter { isSelected(it, request) }
        val selectedKeys = selected.map { it.typeKey }.toSet()
        val results = linkedMapOf<String, CloudNativeEndpointResult>()
        var partial = false

        if (!capabilities.available || "oauth_connected" !in capabilities.grantedPermissions) {
            definitions.forEach { definition ->
                if (definition.typeKey !in selectedKeys) {
                    emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.NOT_SELECTED)))
                } else {
                    val message = "${source.rawProviderId} is not connected for native API reads."
                    emit(RawExportItem.Issue(RawIssue("permission_not_granted", message, RawIssueSeverity.ERROR, definition.typeKey)))
                    emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.PERMISSION_NOT_GRANTED, message)))
                }
            }
            emit(RawExportItem.Status(RawSnapshotStatus.FAILED))
            return@flow
        }

        val unsupported = selected.filter { it.typeKey.startsWith("unsupported/") }
        unsupported.forEach { definition ->
            partial = partial || request.scope == RawSnapshotScope.SELECTED_RECORD_TYPES
            val message = "The selected category has no provider-native endpoint in ${source.rawProviderId}."
            emit(RawExportItem.Issue(RawIssue("unsupported_by_provider", message, recordType = definition.typeKey)))
            emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.UNSUPPORTED_BY_PROVIDER, message)))
        }

        val implementedKeys = selectedKeys - unsupported.map { it.typeKey }.toSet()
        try {
            source.streamNativePages(
                request = request,
                selectedEndpointKeys = implementedKeys,
                observerFor = { endpointKey ->
                    val definition = definitions.first { it.typeKey == endpointKey }
                    com.healthmd.data.health.providers.cloud.CloudRawResponseObserver { response ->
                        emit(RawExportItem.Record(response.toRawRecord(endpointKey, definition.serverAggregation)))
                    }
                },
                onEndpointResult = { result ->
                    if (results.put(result.endpointKey, result) != null) {
                        throw IllegalStateException("Duplicate endpoint result")
                    }
                },
            )
        } catch (cancelled: CancellationException) {
            throw cancelled
        } catch (_: Exception) {
            // Adapters normally isolate endpoint failures. This guard prevents secrets in arbitrary exceptions.
            implementedKeys.filterNot(results::containsKey).forEach { key ->
                results[key] = CloudNativeEndpointResult(
                    endpointKey = key,
                    successfulPageCount = 0,
                    failure = com.healthmd.data.health.providers.cloud.CloudNativeEndpointFailure(
                        code = "native_endpoint_failed",
                        message = "Provider-native endpoint request failed.",
                    ),
                )
            }
        }

        definitions.forEach { definition ->
            when {
                definition.typeKey !in selectedKeys ->
                    emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.NOT_SELECTED)))
                definition in unsupported -> Unit
                else -> {
                    val result = results[definition.typeKey]
                    if (result == null || result.failure != null) {
                        partial = true
                        val failure = result?.failure
                        val message = failure?.message ?: "Provider-native endpoint did not report completion."
                        emit(RawExportItem.Issue(RawIssue(
                            code = failure?.code ?: "native_endpoint_incomplete",
                            message = message,
                            severity = RawIssueSeverity.ERROR,
                            recordType = definition.typeKey,
                            retryable = failure?.retryable ?: true,
                        )))
                        emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.READ_ERROR, message)))
                    } else {
                        emit(RawExportItem.TypeReport(definition.report(RawTypeStatus.EXPORTED)))
                    }
                }
            }
        }

        val knownMetrics = definitions.flatMap { it.metricIds }.toSet()
        if (request.scope == RawSnapshotScope.SELECTED_RECORD_TYPES) {
            (request.selectedMetricIds - knownMetrics).sorted().forEach { metric ->
                partial = true
                emit(RawExportItem.Issue(RawIssue(
                    code = "selection_unknown",
                    message = "No provider-native endpoint or unsupported category is registered for metric '$metric'.",
                )))
            }
        }
        emit(RawExportItem.Status(if (partial) RawSnapshotStatus.PARTIAL else RawSnapshotStatus.COMPLETE))
    }

    private fun isSelected(definition: RawProviderTypeDefinition, request: RawSnapshotRequest): Boolean =
        request.scope == RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA ||
            definition.metricIds.any(request.selectedMetricIds::contains)

    private fun RawProviderTypeDefinition.report(status: RawTypeStatus, message: String? = null) = RawTypeReport(
        typeKey = typeKey,
        wireType = wireType,
        providerId = providerId,
        status = status,
        permission = permission,
        feature = feature,
        rangeBehavior = rangeBehavior,
        pagination = pagination,
        serverAggregation = serverAggregation,
        message = message,
    )

    private fun CloudHealthRawResponse.toRawRecord(endpointKey: String, serverAggregation: Boolean): RawRecord {
        val bytes = responseBytes
        val checksum = RawJson.sha256(bytes)
        val payload = RawProviderPayload(
            providerId = providerId,
            endpointKey = endpointKey,
            endpointIdentifier = endpointIdentifier,
            queryMetadata = queryMetadata.toSortedMap(),
            fetchedAt = RawInstant(fetchedAt.epochSecond, fetchedAt.nano),
            httpStatus = httpStatus,
            contentType = contentType,
            charset = charset,
            responseHeaders = responseHeaders.toSortedMap(String.CASE_INSENSITIVE_ORDER),
            pageOrdinal = pageOrdinal,
            responseBytesBase64 = Base64.getEncoder().encodeToString(bytes),
            responseText = responseText,
            responseSha256 = checksum,
            serverAggregation = serverAggregation,
        )
        return RawRecord(
            wireType = "provider_payload",
            nativeIdentity = "cloud:$providerId:$endpointKey:$pageOrdinal:$checksum",
            recordKind = RawRecordKind.PROVIDER_PAYLOAD,
            source = RawSourceDescriptor(providerId, RawProviderFidelity.NATIVE_API_PAYLOAD, endpointKey),
            fields = JsonObject(emptyMap()),
            providerPayload = payload,
            hash = checksum,
        )
    }
}
