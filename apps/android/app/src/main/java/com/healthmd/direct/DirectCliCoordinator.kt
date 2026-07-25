package com.healthmd.direct

import android.os.Build
import com.healthmd.BuildConfig
import com.healthmd.direct.protocol.ANDROID_APPLICATION_PROTOCOL_VERSION
import com.healthmd.direct.protocol.ArtifactFormat
import com.healthmd.direct.protocol.ArtifactKind
import com.healthmd.direct.protocol.ArtifactManifest
import com.healthmd.direct.protocol.ArtifactSchema
import com.healthmd.direct.protocol.ArtifactTransferClient
import com.healthmd.direct.protocol.DirectClient
import com.healthmd.direct.protocol.DirectExportCancelledException
import com.healthmd.direct.protocol.DirectJson
import com.healthmd.direct.protocol.DirectSecureChannel
import com.healthmd.direct.protocol.ErrorCode
import com.healthmd.direct.protocol.ExportAccepted
import com.healthmd.direct.protocol.ExportFailure
import com.healthmd.direct.protocol.ExportPhase
import com.healthmd.direct.protocol.ExportProgress
import com.healthmd.direct.protocol.ExportRequest
import com.healthmd.direct.protocol.JOB_LIFETIME_SECONDS
import com.healthmd.direct.protocol.PeerBinding
import com.healthmd.direct.protocol.ProductCapability
import com.healthmd.direct.protocol.ProductId
import com.healthmd.direct.protocol.ProtocolLimits
import com.healthmd.direct.protocol.ResolvedRange
import com.healthmd.direct.protocol.SettingsPolicy
import com.healthmd.direct.protocol.SourceHello
import com.healthmd.direct.protocol.SourceIdentity
import com.healthmd.direct.protocol.SourceStatus
import com.healthmd.direct.protocol.StatusRequest
import com.healthmd.direct.protocol.TransferPlanBuilder
import com.healthmd.direct.protocol.V2Codec
import com.healthmd.domain.billing.FreemiumPolicy
import com.healthmd.domain.repository.BillingRepository
import com.healthmd.domain.repository.HealthRepository
import com.healthmd.domain.repository.SettingsRepository
import com.healthmd.presentation.export.ExportHistoryAccess
import com.healthmd.rawexport.RawExportFormat
import com.healthmd.rawexport.RawInstant
import com.healthmd.rawexport.RawHealthRepositoryRegistry
import com.healthmd.rawexport.RawSnapshotRequest
import com.healthmd.rawexport.RawSnapshotScope
import javax.inject.Singleton
import java.io.File
import java.security.MessageDigest
import java.time.Instant
import java.time.LocalDate
import java.time.ZoneId
import java.time.temporal.ChronoUnit
import javax.inject.Inject
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.currentCoroutineContext
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.isActive
import kotlinx.coroutines.job
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.serialization.encodeToString
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.boolean
import kotlinx.serialization.json.contentOrNull
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive

sealed interface DirectCliConnectionState {
    data object Idle : DirectCliConnectionState
    data object Pairing : DirectCliConnectionState
    data object WaitingForCli : DirectCliConnectionState
    data class Connected(val listenerName: String) : DirectCliConnectionState
    data class Transferring(val completedBytes: Long, val totalBytes: Long) : DirectCliConnectionState
    data class Completed(val message: String) : DirectCliConnectionState
    data class Failed(val message: String) : DirectCliConnectionState
}

@Singleton
class DirectCliCoordinator @Inject constructor(
    private val trustStore: DirectCliTrustStore,
    private val jobStore: DirectCliJobStore,
    private val rawProducer: DirectRawSnapshotProducer,
    private val generatedProducer: DirectGeneratedFilesProducer,
    private val rawRepositories: RawHealthRepositoryRegistry,
    private val healthRepository: HealthRepository,
    private val settingsRepository: SettingsRepository,
    private val billingRepository: BillingRepository,
) {
    private val _state = MutableStateFlow<DirectCliConnectionState>(DirectCliConnectionState.Idle)
    val state: StateFlow<DirectCliConnectionState> = _state.asStateFlow()
    private val protocolJson = Json { encodeDefaults = true; explicitNulls = false }
    private val sessionMutex = Mutex()
    @Volatile private var activeChannel: DirectSecureChannel? = null

    suspend fun pair(host: String, port: Int, pairingCode: String) = sessionMutex.withLock {
        require(pairingCode.count { it in '0'..'9' } == 20) {
            "Android pairing code must be twenty digits."
        }
        _state.value = DirectCliConnectionState.Pairing
        val connected = DirectClient.connect(
            host = host,
            port = port,
            installationId = trustStore.installationId(),
            displayName = Build.MODEL.ifBlank { "Android" },
            pairingCode = pairingCode,
        )
        connected.channel.use { channel ->
            activeChannel = channel
            try {
                negotiate(channel)
                trustStore.save(connected.listener, host, port)
                _state.value = DirectCliConnectionState.Completed(
                    "Paired with ${connected.listener.displayName}.",
                )
            } finally {
                activeChannel = null
            }
        }
    }

    suspend fun connectAndServe() = sessionMutex.withLock {
        val trust = requireNotNull(trustStore.load()) { "Pair with a CLI before connecting." }
        _state.value = DirectCliConnectionState.WaitingForCli
        val connected = DirectClient.connect(
            host = trust.host,
            port = trust.port,
            installationId = trustStore.installationId(),
            displayName = Build.MODEL.ifBlank { "Android" },
            trustedListener = trust,
        )
        connected.channel.use { channel ->
            activeChannel = channel
            try {
                negotiate(channel)
                _state.value = DirectCliConnectionState.Connected(connected.listener.displayName)
                serve(channel)
                if (_state.value is DirectCliConnectionState.Connected) {
                    _state.value = DirectCliConnectionState.Completed("Direct CLI session finished.")
                }
            } finally {
                activeChannel = null
            }
        }
    }

    fun cancelActive() {
        runCatching { activeChannel?.close() }
    }

    suspend fun forget() {
        cancelActive()
        sessionMutex.withLock {
            trustStore.forget()
            jobStore.purgeAll()
            _state.value = DirectCliConnectionState.Idle
        }
    }

    fun reportFailure(message: String) {
        _state.value = DirectCliConnectionState.Failed(message)
    }

    fun resetSession() {
        _state.value = DirectCliConnectionState.Idle
    }

    fun reportDisconnected() {
        if (_state.value !is DirectCliConnectionState.Completed &&
            _state.value !is DirectCliConnectionState.Failed
        ) {
            _state.value = DirectCliConnectionState.Idle
        }
    }

    private suspend fun negotiate(channel: DirectSecureChannel) {
        channel.sendNegotiationHello(trustStore.installationId())
        val listener = channel.receiveNegotiationHello()
        require(listener.platform == "macos_cli") { "The peer is not a Health.md CLI." }
        require(ANDROID_APPLICATION_PROTOCOL_VERSION in listener.protocolVersions) {
            "Update the Health.md CLI before connecting Android."
        }
        require(listener.installationId == channel.listenerInstallationId) {
            "The CLI identity changed during negotiation."
        }
        channel.sendV2("source_hello", SourceHello.serializer(), sourceHello())
    }

    private suspend fun serve(channel: DirectSecureChannel) {
        while (true) {
            val envelope = channel.receiveV2()
            when (envelope.type) {
                "status_request" -> {
                    V2Codec.decodePayload(envelope, StatusRequest.serializer())
                    channel.sendV2("status_response", SourceStatus.serializer(), sourceStatus())
                    return
                }
                "export_request" -> {
                    val request = V2Codec.decodePayload(envelope, ExportRequest.serializer())
                    handleExport(channel, request)
                    return
                }
                "cancel" -> {
                    val payload = V2Codec.decodePayload(
                        envelope,
                        com.healthmd.direct.protocol.JobPayload.serializer(),
                    )
                    jobStore.cancel(payload.jobId)
                    channel.sendV2(
                        "cancel_acknowledged",
                        com.healthmd.direct.protocol.JobPayload.serializer(),
                        payload,
                    )
                    return
                }
                "ping" -> channel.sendV2(
                    "pong",
                    EmptyPayload.serializer(),
                    EmptyPayload(),
                )
                else -> error("The CLI sent an unexpected ${envelope.type} message.")
            }
        }
    }

    private suspend fun handleExport(channel: DirectSecureChannel, request: ExportRequest) {
        var phase = ExportPhase.PREPARING
        try {
            validateRequest(request)
            val fingerprint = V2Codec.requestFingerprint(request)
            if (jobStore.hasIncompletePreparation(request.jobId, fingerprint)) {
                throw MissingSpoolException()
            }
            val existing = try {
                jobStore.load(request.jobId, fingerprint)
            } catch (error: IllegalArgumentException) {
                if (error.message?.contains("request changed") == true) throw error
                throw MissingSpoolException()
            }
            val unlocked = isUnlocked()
            if (existing == null) {
                if (!FreemiumPolicy.canExport(unlocked, settingsRepository.getFreeExportsUsed())) {
                    reject(
                        channel,
                        request.jobId,
                        ErrorCode.QUOTA_EXHAUSTED,
                        phase,
                        "The free export limit has been reached.",
                    )
                    return
                }
                val product = productId(request.product)
                val rawCapabilities = if (product == ProductId.ANDROID_PROVIDER_NATIVE_SNAPSHOT_V1) {
                    val providerId = request.product.getValue("provider_id").jsonPrimitive.content
                    if (providerId == "fitbit" && !isBoundedFitbitRange(request.dateSelection)) {
                        reject(
                            channel,
                            request.jobId,
                            ErrorCode.INVALID_REQUEST,
                            phase,
                            "Fitbit raw export requires an explicit range of at most 366 days.",
                        )
                        return
                    }
                    requireNotNull(rawRepositories.repositoryFor(providerId)).capabilities()
                } else {
                    null
                }
                val sourceAvailable = rawCapabilities?.available ?: healthRepository.isAvailable()
                if (!sourceAvailable) {
                    reject(
                        channel,
                        request.jobId,
                        ErrorCode.SOURCE_UNAVAILABLE,
                        phase,
                        "The requested health provider is unavailable on this device.",
                    )
                    return
                }
                val usesHealthConnect = rawCapabilities?.providerId == "health_connect" ||
                    product == ProductId.GENERATED_FILES_V1
                val permissionsGranted = rawCapabilities?.let {
                    it.providerId != "health_connect" || it.grantedPermissions.isNotEmpty()
                } ?: healthRepository.hasPermissions()
                if (!permissionsGranted) {
                    reject(
                        channel,
                        request.jobId,
                        ErrorCode.PERMISSION_REQUIRED,
                        phase,
                        "Health access is required on the Android device.",
                    )
                    return
                }
                if (usesHealthConnect && healthRepository.isBeforeFirstUnlock()) {
                    reject(
                        channel,
                        request.jobId,
                        ErrorCode.DEVICE_LOCKED,
                        phase,
                        "Unlock the Android device before exporting health data.",
                    )
                    return
                }
                val requestedDates = resolveDates(request.dateSelection, product)
                val needsHistory = ExportHistoryAccess.requiresHistoricalReadPermission(
                    startDate = requestedDates.first(),
                    endDate = requestedDates.last(),
                    firstPermissionGrantDate = settingsRepository.getFirstHealthPermissionGrantDate(),
                )
                val historicalAccessGranted = rawCapabilities?.historicalReadGranted
                    ?: healthRepository.hasHistoricalReadPermission()
                if (needsHistory && usesHealthConnect && !historicalAccessGranted) {
                    reject(
                        channel,
                        request.jobId,
                        ErrorCode.PERMISSION_REQUIRED,
                        phase,
                        "Historical health access is required for the requested dates.",
                    )
                    return
                }
            }
            val journal = if (existing != null) {
                channel.sendV2(
                    "export_accepted",
                    ExportAccepted.serializer(),
                    existing.transfer.accepted,
                )
                existing
            } else {
                prepareJob(channel, request, fingerprint)
            }
            phase = ExportPhase.TRANSFERRING
            val exportContext = currentCoroutineContext()
            val transfer = ArtifactTransferClient(channel)
            transfer.transfer(
                plan = journal.transfer,
                sendAccepted = false,
                onProgress = { committed, total ->
                    _state.value = DirectCliConnectionState.Transferring(committed, total)
                },
                beforeCompletionConfirmed = {
                    // The CLI has committed at this point. Local accounting must never turn that
                    // success into an export rejection or charge this durable job twice.
                    runCatching {
                        val current = requireNotNull(jobStore.load(request.jobId, fingerprint))
                        if (!current.accounted) {
                            if (!unlocked) {
                                kotlinx.coroutines.runBlocking {
                                    settingsRepository.recordFreeExportUseOnce(request.jobId)
                                }
                            }
                            jobStore.markAccounted(request.jobId)
                        }
                    }
                },
                checkCancellation = { exportContext.ensureActive() },
            )
            val completionPersisted = runCatching {
                jobStore.markCompleted(request.jobId)
            }.isSuccess
            if (!journal.completed && completionPersisted) {
                runCatching { settingsRepository.incrementSuccessfulExportCount() }
            }
            _state.value = DirectCliConnectionState.Completed("Android export completed.")
        } catch (error: CancellationException) {
            throw error
        } catch (_: DirectExportCancelledException) {
            jobStore.cancel(request.jobId)
            _state.value = DirectCliConnectionState.Completed("Android export cancelled.")
        } catch (_: DirectGeneratedArtifactLimitException) {
            jobStore.cancel(request.jobId)
            reject(
                channel,
                request.jobId,
                ErrorCode.STAGING_FAILED,
                phase,
                "Generated export exceeds 4,096 files; use fewer dates or disable individual tracking.",
            )
        } catch (_: MissingSpoolException) {
            reject(
                channel,
                request.jobId,
                ErrorCode.SPOOL_MISSING_RESTART_REQUIRED,
                phase,
                "The retained export is missing and must be restarted.",
            )
        } catch (_: Throwable) {
            reject(
                channel,
                request.jobId,
                ErrorCode.INTERNAL_FAILURE,
                phase,
                "The Android export could not be completed safely.",
            )
            _state.value = DirectCliConnectionState.Failed(
                "The Android export could not be completed safely.",
            )
        }
    }

    private suspend fun prepareJob(
        channel: DirectSecureChannel,
        request: ExportRequest,
        fingerprint: String,
    ): DirectJobJournal {
        val dates = resolveDates(request.dateSelection, productId(request.product))
        val productId = productId(request.product)
        jobStore.beginPreparation(request.jobId, fingerprint, request.expiresAt)
        val providerId = request.product["provider_id"]?.jsonPrimitive?.contentOrNull
        val settings = settingsRepository.getExportSettings()
        val settingsHash = if (productId == ProductId.GENERATED_FILES_V1) {
            DirectJson.sha256Hex(protocolJson.encodeToString(settings).toByteArray())
        } else {
            null
        }
        val accepted = ExportAccepted(
            jobId = request.jobId,
            acceptedAt = Instant.now().truncatedTo(ChronoUnit.SECONDS).toString(),
            peerBinding = PeerBinding(
                sourceInstallationId = trustStore.installationId(),
                destinationInstallationId = requireNotNull(trustStore.load()).installationId,
            ),
            productId = productId,
            resolvedRange = ResolvedRange(
                startDate = dates.first().toString(),
                endDate = dates.last().toString(),
                timeZoneId = ZoneId.systemDefault().id,
            ),
            providerId = providerId,
            settingsSnapshotSha256 = settingsHash,
            requestFingerprint = fingerprint,
        )
        channel.sendV2("export_accepted", ExportAccepted.serializer(), accepted)
        channel.sendV2(
            "export_progress",
            ExportProgress.serializer(),
            ExportProgress(
                jobId = request.jobId,
                phase = ExportPhase.PREPARING,
                completedUnits = 0,
                totalUnits = dates.size.toLong(),
                committedBytes = 0,
                message = "Preparing Android export artifacts.",
            ),
        )

        val parentJob = currentCoroutineContext().job
        val cancellationMonitor = CoroutineScope(currentCoroutineContext()).launch(Dispatchers.IO) {
            while (isActive) {
                val envelope = channel.pollV2(PREPARATION_CANCEL_POLL_MILLIS) ?: continue
                when (envelope.type) {
                    "cancel" -> {
                        val payload = V2Codec.decodePayload(
                            envelope,
                            com.healthmd.direct.protocol.JobPayload.serializer(),
                        )
                        require(payload.jobId == request.jobId)
                        jobStore.cancel(request.jobId)
                        channel.sendV2(
                            "cancel_acknowledged",
                            com.healthmd.direct.protocol.JobPayload.serializer(),
                            payload,
                        )
                        _state.value = DirectCliConnectionState.Completed("Android export cancelled.")
                        parentJob.cancel(CancellationException("Direct export cancelled by CLI."))
                        return@launch
                    }
                    "ping" -> channel.sendV2(
                        "pong",
                        EmptyPayload.serializer(),
                        EmptyPayload(),
                    )
                    else -> error("Unexpected message during Android artifact preparation.")
                }
            }
        }
        val jobDirectory = jobStore.directory(request.jobId)
        val transfer = try {
            val (manifests, files) = when (productId) {
            ProductId.ANDROID_PROVIDER_NATIVE_SNAPSHOT_V1 -> {
                val rawRequest = rawRequest(request.product, dates)
                val raw = rawProducer.produce(
                    jobDirectory = jobDirectory,
                    providerId = requireNotNull(providerId),
                    request = rawRequest,
                )
                val artifactId = UUIDs.random()
                val file = File(raw.finalLocation)
                listOf(ArtifactManifest(
                    jobId = request.jobId,
                    artifactId = artifactId,
                    kind = ArtifactKind.RAW_SNAPSHOT,
                    schema = ArtifactSchema("healthmd.raw-snapshot", 1),
                    mediaType = if (raw.format == RawExportFormat.JSON) {
                        "application/vnd.healthmd.raw-snapshot+json"
                    } else {
                        "application/x-ndjson"
                    },
                    byteCount = raw.bytesWritten,
                    sha256 = raw.artifactChecksumSha256,
                    logicalChecksumSha256 = raw.manifest.logicalChecksumSha256,
                    snapshotStatus = raw.manifest.status.name,
                    providerId = providerId,
                )) to mapOf(artifactId to file)
            }
            ProductId.GENERATED_FILES_V1 -> {
                val generated = generatedProducer.produce(
                    jobDirectory = jobDirectory,
                    dates = dates,
                    settings = settings,
                ) { completed, total ->
                    channel.sendV2(
                        "export_progress",
                        ExportProgress.serializer(),
                        ExportProgress(
                            jobId = request.jobId,
                            phase = ExportPhase.READING,
                            completedUnits = completed.toLong(),
                            totalUnits = total.toLong(),
                            committedBytes = 0,
                            message = "Generating Android export files.",
                        ),
                    )
                }
                generated.map { item ->
                    ArtifactManifest(
                        jobId = request.jobId,
                        artifactId = item.artifactId,
                        kind = ArtifactKind.GENERATED_FILE,
                        schema = ArtifactSchema("healthmd.generated-files", 1),
                        mediaType = item.format.mediaType(),
                        byteCount = item.file.length(),
                        sha256 = sha256(item.file),
                        relativePath = item.relativePath,
                        writeMode = item.writeMode,
                    )
                } to generated.associate { it.artifactId to it.file }
            }
                ProductId.ANDROID_DAILY_RECORDS_V1 -> error("Android extraction is not enabled yet.")
            }
            TransferPlanBuilder.build(
                accepted = accepted,
                manifests = manifests,
                artifactFiles = files,
                createdAt = Instant.now().truncatedTo(ChronoUnit.SECONDS).toString(),
                checkCancellation = { parentJob.ensureActive() },
            )
        } finally {
            cancellationMonitor.cancelAndJoin()
        }
        val journal = DirectJobJournal(
            requestFingerprint = fingerprint,
            expiresAt = request.expiresAt,
            transfer = transfer,
        )
        jobStore.save(journal)
        return journal
    }

    private suspend fun sourceHello(): SourceHello {
        val providers = buildSet {
            add(RawHealthRepositoryRegistry.HEALTH_CONNECT)
            val connected = settingsRepository.getConnectedHealthProviderIds()
            addAll(
                rawRepositories.registeredProviderIds().filter { provider ->
                    provider in connected && provider !in UNSUPPORTED_NATIVE_PROVIDERS
                },
            )
        }.sorted()
        return SourceHello(
            source = sourceIdentity(),
            products = listOf(
                ProductCapability(
                    productId = ProductId.ANDROID_PROVIDER_NATIVE_SNAPSHOT_V1,
                    artifactSchema = ArtifactSchema("healthmd.raw-snapshot", 1),
                    formats = listOf(ArtifactFormat.JSON, ArtifactFormat.NDJSON),
                    providers = providers,
                ),
                ProductCapability(
                    productId = ProductId.GENERATED_FILES_V1,
                    artifactSchema = ArtifactSchema("healthmd.generated-files", 1),
                    formats = listOf(
                        ArtifactFormat.MARKDOWN,
                        ArtifactFormat.JSON,
                        ArtifactFormat.CSV,
                        ArtifactFormat.OBSIDIAN_BASES,
                    ),
                    settingsPolicies = listOf(SettingsPolicy.SAVED_DEVICE_SETTINGS),
                ),
            ),
            limits = ProtocolLimits(),
        )
    }

    private suspend fun sourceStatus(): SourceStatus = SourceStatus(
        source = sourceIdentity(),
        appActive = true,
        protectedDataAvailable = !healthRepository.isBeforeFirstUnlock(),
        exportInProgress = _state.value is DirectCliConnectionState.Transferring,
        availableProducts = sourceHello().products.map(ProductCapability::productId),
        message = null,
    )

    private fun sourceIdentity() = SourceIdentity(
        installationId = trustStore.installationId(),
        displayName = Build.MODEL.ifBlank { "Android" },
        appVersion = BuildConfig.VERSION_NAME,
    )

    private suspend fun isUnlocked(): Boolean {
        billingRepository.startConnection()
        return settingsRepository.isPurchased.first() || billingRepository.isUnlocked.first()
    }

    private fun isBoundedFitbitRange(selection: JsonObject): Boolean {
        if (selection["type"]?.jsonPrimitive?.content != "exact") return false
        val start = selection["start_date"]?.jsonPrimitive?.contentOrNull
            ?.let(LocalDate::parse) ?: return false
        val end = selection["end_date"]?.jsonPrimitive?.contentOrNull
            ?.let(LocalDate::parse) ?: return false
        return !end.isBefore(start) && ChronoUnit.DAYS.between(start, end) < MAXIMUM_FITBIT_RAW_DAYS
    }

    private suspend fun resolveDates(
        selection: JsonObject,
        productId: ProductId,
    ): List<LocalDate> {
        return when (selection.getValue("type").jsonPrimitive.content) {
            "exact" -> {
                val start = LocalDate.parse(selection.getValue("start_date").jsonPrimitive.content)
                val end = LocalDate.parse(selection.getValue("end_date").jsonPrimitive.content)
                require(!end.isBefore(start))
                val count = ChronoUnit.DAYS.between(start, end) + 1
                require(count in 1..100_000)
                List(count.toInt()) { index -> start.plusDays(index.toLong()) }
            }
            "all_available" -> {
                val end = LocalDate.now().minusDays(1)
                val start = if (productId == ProductId.GENERATED_FILES_V1) {
                    (healthRepository.getEarliestDataDate() ?: end).coerceAtMost(end)
                } else {
                    // Raw providers receive one bounded instant range rather than one query per day.
                    end.minusDays(99_999)
                }
                val count = ChronoUnit.DAYS.between(start, end) + 1
                require(count in 1..100_000)
                List(count.toInt()) { index -> start.plusDays(index.toLong()) }
            }
            else -> error("Unsupported Android date selection.")
        }
    }

    private fun rawRequest(product: JsonObject, dates: List<LocalDate>): RawSnapshotRequest {
        val zone = ZoneId.systemDefault()
        val start = dates.first().atStartOfDay(zone).toInstant()
        val end = dates.last().plusDays(1).atStartOfDay(zone).toInstant()
        val scopeObject = product.getValue("scope").jsonObject
        val scope = when (scopeObject.getValue("type").jsonPrimitive.content) {
            "selected_record_types" -> RawSnapshotScope.SELECTED_RECORD_TYPES
            "all_authorized_supported_data" -> RawSnapshotScope.ALL_AUTHORIZED_SUPPORTED_DATA
            else -> error("Unsupported Android raw scope.")
        }
        val selected = scopeObject["selected_metric_ids"]?.jsonArray
            ?.map { it.jsonPrimitive.content }
            ?.toSortedSet()
            .orEmpty()
        return RawSnapshotRequest(
            format = when (product.getValue("format").jsonPrimitive.content) {
                "json" -> RawExportFormat.JSON
                "ndjson" -> RawExportFormat.NDJSON
                else -> error("Unsupported Android raw format.")
            },
            scope = scope,
            startTime = RawInstant(start.epochSecond, start.nano),
            endTime = RawInstant(end.epochSecond, end.nano),
            selectedMetricIds = selected,
            includeExerciseRoutes = product.getValue("include_exercise_routes").jsonPrimitive.boolean,
            calendarZoneId = zone.id,
        )
    }

    private fun validateRequest(request: ExportRequest) {
        require(java.util.UUID.fromString(request.jobId).toString() == request.jobId)
        require(request.sourceInstallationId == trustStore.installationId())
        val createdAt = Instant.parse(request.createdAt)
        val expiresAt = Instant.parse(request.expiresAt)
        val now = Instant.now()
        require(createdAt.isBefore(expiresAt))
        require(!createdAt.isAfter(now.plusSeconds(MAXIMUM_CLOCK_SKEW_SECONDS)))
        require(expiresAt.isAfter(now))
        require(ChronoUnit.SECONDS.between(createdAt, expiresAt) in 1..JOB_LIFETIME_SECONDS)
        require(!expiresAt.isAfter(now.plusSeconds(JOB_LIFETIME_SECONDS)))
        val selectionType = request.dateSelection["type"]?.jsonPrimitive?.content
        require(
            request.dateSelection.keys == when (selectionType) {
                "exact" -> setOf("type", "start_date", "end_date")
                "all_available" -> setOf("type")
                else -> emptySet()
            },
        )
        val product = productId(request.product)
        require((product == ProductId.GENERATED_FILES_V1) == (request.destination != null))
        when (product) {
            ProductId.ANDROID_PROVIDER_NATIVE_SNAPSHOT_V1 -> {
                require(
                    request.product.keys == setOf(
                        "product_id",
                        "provider_id",
                        "format",
                        "scope",
                        "include_exercise_routes",
                    ),
                )
                val provider = requireNotNull(
                    request.product["provider_id"]?.jsonPrimitive?.contentOrNull,
                )
                require(provider != "all_connected")
                require(rawRepositories.repositoryFor(provider) != null)
                require(provider !in UNSUPPORTED_NATIVE_PROVIDERS)
                require(request.product.getValue("format").jsonPrimitive.content in setOf("json", "ndjson"))
                val scope = request.product.getValue("scope").jsonObject
                require(
                    scope.keys == when (scope["type"]?.jsonPrimitive?.content) {
                        "selected_record_types" -> setOf("type", "selected_metric_ids")
                        "all_authorized_supported_data" -> setOf("type")
                        else -> emptySet()
                    },
                )
            }
            ProductId.GENERATED_FILES_V1 -> require(
                request.product.keys == setOf("product_id", "settings_policy") &&
                    request.product.getValue("settings_policy").jsonPrimitive.content ==
                    "saved_device_settings",
            )
            ProductId.ANDROID_DAILY_RECORDS_V1 -> Unit
        }
    }

    private fun productId(product: JsonObject): ProductId = when (
        product.getValue("product_id").jsonPrimitive.content
    ) {
        "android_provider_native_snapshot_v1" -> ProductId.ANDROID_PROVIDER_NATIVE_SNAPSHOT_V1
        "generated_files_v1" -> ProductId.GENERATED_FILES_V1
        "android_daily_records_v1" -> ProductId.ANDROID_DAILY_RECORDS_V1
        else -> error("Unsupported Android direct product.")
    }

    private fun reject(
        channel: DirectSecureChannel,
        jobId: String?,
        code: ErrorCode,
        phase: ExportPhase,
        message: String,
    ) {
        runCatching {
            channel.sendV2(
                "export_rejected",
                ExportFailure.serializer(),
                ExportFailure(
                    jobId = jobId,
                    code = code,
                    phase = phase,
                    retryable = false,
                    publicMessage = message,
                ),
            )
        }
        _state.value = DirectCliConnectionState.Failed(message)
    }

    private fun ArtifactFormat.mediaType(): String = when (this) {
        ArtifactFormat.JSON -> "application/json"
        ArtifactFormat.NDJSON -> "application/x-ndjson"
        ArtifactFormat.MARKDOWN -> "text/markdown; charset=utf-8"
        ArtifactFormat.CSV -> "text/csv; charset=utf-8"
        ArtifactFormat.OBSIDIAN_BASES -> "application/yaml; charset=utf-8"
    }

    private fun sha256(file: File): String = file.inputStream().buffered().use { input ->
        val digest = MessageDigest.getInstance("SHA-256")
        val buffer = ByteArray(128 * 1024)
        while (true) {
            val count = input.read(buffer)
            if (count < 0) break
            digest.update(buffer, 0, count)
        }
        digest.digest().joinToString("") { "%02x".format(it) }
    }

    @kotlinx.serialization.Serializable
    private class EmptyPayload

    private class MissingSpoolException : Exception()

    private object UUIDs {
        fun random(): String = java.util.UUID.randomUUID().toString()
    }

    companion object {
        private const val MAXIMUM_CLOCK_SKEW_SECONDS = 5L * 60L
        private const val PREPARATION_CANCEL_POLL_MILLIS = 250
        private const val MAXIMUM_FITBIT_RAW_DAYS = 366L
        private val UNSUPPORTED_NATIVE_PROVIDERS = setOf(
            "polar",
            "samsung_health",
            "huawei_health",
            "garmin",
        )
    }
}
