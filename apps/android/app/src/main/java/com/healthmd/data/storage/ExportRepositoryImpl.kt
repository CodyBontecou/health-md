package com.healthmd.data.storage

import com.healthmd.data.export.CsvExporter
import com.healthmd.data.export.DailyNoteInjector
import com.healthmd.data.export.IndividualEntryExporter
import com.healthmd.data.export.InjectionResult
import com.healthmd.data.export.JsonExporter
import com.healthmd.data.export.MarkdownExporter
import com.healthmd.data.export.MarkdownMerger
import com.healthmd.data.export.ObsidianBasesExporter
import com.healthmd.domain.exportengine.AndroidDailyAggregateExportPlanner
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshot
import com.healthmd.domain.exportengine.AndroidExportSettingsSnapshotCodec
import com.healthmd.domain.exportengine.ExportArtifactPlan
import com.healthmd.domain.exportengine.ExportArtifactWriteMode
import com.healthmd.domain.exportengine.ExportCommitBarrier
import com.healthmd.domain.exportengine.LocalDailyAggregateExportPlanner
import com.healthmd.domain.exportengine.LocalDailyAggregatePlanningResult
import com.healthmd.domain.exportengine.ExportEngineMode
import com.healthmd.domain.exportengine.ExportEnginePinCodec
import com.healthmd.domain.exportengine.ProductionDailyAggregateNativePlanBuilder
import com.healthmd.domain.exportengine.ShadowExportDiagnosticSink
import com.healthmd.domain.exportengine.isFatalExportEngineFailure
import com.healthmd.domain.model.ExportFailureReason
import com.healthmd.domain.model.ExportFormat
import com.healthmd.domain.model.ExportPreviewDay
import com.healthmd.domain.model.ExportPreviewFile
import com.healthmd.domain.model.ExportPreviewIssue
import com.healthmd.domain.model.ExportPreviewIssueKind
import com.healthmd.domain.model.ExportPreviewSideEffect
import com.healthmd.domain.model.ExportPreviewSideEffectAction
import com.healthmd.domain.model.ExportPreviewSideEffectType
import com.healthmd.domain.model.ExportSettings
import com.healthmd.domain.model.ExportResult
import com.healthmd.domain.model.FailedDateDetail
import com.healthmd.domain.model.HealthData
import com.healthmd.domain.model.ExportTarget
import com.healthmd.domain.model.WriteMode as SettingsWriteMode
import com.healthmd.domain.repository.DurableScheduledFolderOperationStart
import com.healthmd.domain.repository.ExportRepository
import com.healthmd.domain.repository.SettingsRepository
import java.nio.charset.StandardCharsets
import java.time.LocalDate
import java.time.ZoneId
import java.util.Base64
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.withContext
import kotlin.coroutines.coroutineContext

class ExportRepositoryImpl(
    private val fileExportManager: FileExportManager,
    private val markdownExporter: MarkdownExporter,
    private val jsonExporter: JsonExporter,
    private val csvExporter: CsvExporter,
    private val obsidianBasesExporter: ObsidianBasesExporter,
    private val settingsRepository: SettingsRepository,
    private val scheduledFolderJournalStore: ScheduledFolderExportJournalStore? = null,
    private val diagnosticSink: ShadowExportDiagnosticSink = ShadowExportDiagnosticSink { },
    private val dailyAggregatePlanner: LocalDailyAggregateExportPlanner =
        AndroidDailyAggregateExportPlanner(
            nativePlanner = ProductionDailyAggregateNativePlanBuilder(
                markdownExporter = markdownExporter,
                jsonExporter = jsonExporter,
                csvExporter = csvExporter,
                obsidianBasesExporter = obsidianBasesExporter,
            ),
            diagnosticSink = diagnosticSink,
        ),
) : ExportRepository {

    private val dailyNoteInjector = DailyNoteInjector()
    private val individualEntryExporter = IndividualEntryExporter()
    private val markdownMerger = MarkdownMerger()
    private val stagedScheduledFolderOperations = mutableMapOf<String, StagedScheduledFolderOperation>()

    override suspend fun exportHealthData(data: HealthData, settings: ExportSettings): Boolean {
        val folderUri = settingsRepository.getExportFolderUri() ?: return false
        if (settings.selectedExportFormats.isEmpty()) return false

        val selection = try {
            dailyAggregatePlanner.plan(data, settings)
        } catch (error: Throwable) {
            rethrowCancellationOrFatal(error)
            return false
        }
        return when (selection) {
            LocalDailyAggregatePlanningResult.Legacy ->
                exportLegacy(folderUri, data, settings)
            is LocalDailyAggregatePlanningResult.Failed -> false
            is LocalDailyAggregatePlanningResult.Planned ->
                commitAuthoritativePlan(folderUri, selection.plan)
        }
    }

    override suspend fun beginDurableScheduledFolderOperation(
        operationId: String,
        dates: List<LocalDate>,
        settings: ExportSettings,
        settingsSnapshotJson: String,
        requireExistingJournal: Boolean,
    ): DurableScheduledFolderOperationStart {
        val store = scheduledFolderJournalStore ?: return DurableScheduledFolderOperationStart.Failed
        val identity = durableIdentity(operationId, dates, settings, settingsSnapshotJson)
            ?: return DurableScheduledFolderOperationStart.Failed
        return when (val loaded = store.load(operationId)) {
            ScheduledFolderJournalLoad.Corrupt -> DurableScheduledFolderOperationStart.Failed
            ScheduledFolderJournalLoad.Missing -> if (requireExistingJournal) {
                DurableScheduledFolderOperationStart.Failed
            } else {
                startCapturing(store, identity)
            }
            is ScheduledFolderJournalLoad.Found -> {
                if (!identity.matches(loaded.journal) ||
                    (loaded.journal.phase == ScheduledFolderJournalPhase.READY &&
                        !loaded.journal.canResume(identity.ownerDates))
                ) {
                    DurableScheduledFolderOperationStart.Failed
                } else if (loaded.journal.phase == ScheduledFolderJournalPhase.CAPTURING) {
                    startCapturing(store, identity)
                } else {
                    DurableScheduledFolderOperationStart.Resumed(
                        executeDurableJournal(store, loaded.journal, dates),
                    )
                }
            }
        }
    }

    override suspend fun hasResumableDurableScheduledFolderOperation(
        operationId: String,
        dates: List<LocalDate>,
        settings: ExportSettings,
        settingsSnapshotJson: String,
    ): Boolean {
        val store = scheduledFolderJournalStore ?: return false
        val identity = durableIdentity(operationId, dates, settings, settingsSnapshotJson) ?: return false
        val loaded = store.load(operationId)
        return loaded is ScheduledFolderJournalLoad.Found &&
            loaded.journal.phase == ScheduledFolderJournalPhase.READY &&
            identity.matches(loaded.journal) &&
            loaded.journal.canResume(identity.ownerDates)
    }

    override suspend fun stageDurableScheduledFolderDay(
        operationId: String,
        data: HealthData,
        settings: ExportSettings,
    ): Boolean {
        val stage = stagedScheduledFolderOperations[operationId] ?: return false
        if (data.date !in stage.dates || stage.plans.containsKey(data.date)) return false
        val selection = try {
            dailyAggregatePlanner.plan(data, settings)
        } catch (error: Throwable) {
            rethrowCancellationOrFatal(error)
            return false
        }
        val pin = settings.executionEnginePin ?: return false
        if (selection !is LocalDailyAggregatePlanningResult.Planned ||
            selection.mode == ExportEngineMode.legacy ||
            selection.mode != pin.engine ||
            selection.plan.profile != pin.profile ||
            selection.plan.items.isEmpty() ||
            selection.plan.items.any { it.writeMode != ExportArtifactWriteMode.overwrite }
        ) return false
        stage.plans[data.date] = selection.plan
        return true
    }

    override suspend fun finishDurableScheduledFolderOperation(
        operationId: String,
        dates: List<LocalDate>,
        failedDateDetails: List<FailedDateDetail>,
        wasCancelled: Boolean,
    ): ExportResult {
        val store = scheduledFolderJournalStore
        val stage = stagedScheduledFolderOperations.remove(operationId)
        if (store == null || stage == null || stage.dates != dates.distinct().sorted()) {
            return durableFailure(dates, operationId, wasCancelled)
        }
        if (wasCancelled) {
            store.discard(operationId)
            return durableFailure(
                dates = dates,
                operationId = null,
                wasCancelled = true,
                freshCaptureRetryDates = dates.toSet(),
            )
        }

        val failures = failedDateDetails
            .filter { it.date in stage.dates && it.date !in stage.plans }
            .associateBy { it.date }
            .toMutableMap()
        stage.dates.filter { it !in stage.plans && it !in failures }.forEach { date ->
            failures[date] = FailedDateDetail(date, ExportFailureReason.UNKNOWN)
        }
        val journal = stage.identity.toJournal(
            phase = ScheduledFolderJournalPhase.READY,
            days = stage.plans.entries.sortedBy { it.key }.map { (date, plan) ->
                ScheduledFolderJournalDay(
                    ownerDate = date.toString(),
                    artifacts = plan.items.map { item ->
                        ScheduledFolderJournalArtifact(
                            artifactId = item.artifactId,
                            relativePath = item.relativePath,
                            stagingRelativePath = durableStagingPath(
                                item.relativePath,
                                item.artifactId,
                            ),
                            mediaType = item.mediaType,
                            byteCount = item.byteCount.toInt(),
                            sha256 = item.sha256,
                            contentBase64 = Base64.getEncoder().encodeToString(item.content),
                        )
                    },
                )
            },
            failures = failures.values.sortedBy { it.date }.map { failure ->
                ScheduledFolderJournalFailure(
                    ownerDate = failure.date.toString(),
                    reason = failure.reason.name,
                )
            },
        )
        if (!store.save(journal)) return durableFailure(dates, operationId)
        return executeDurableJournal(store, journal, dates)
    }

    override suspend fun discardDurableScheduledFolderOperation(operationId: String) {
        stagedScheduledFolderOperations.remove(operationId)
        scheduledFolderJournalStore?.discard(operationId)
    }

    private suspend fun startCapturing(
        store: ScheduledFolderExportJournalStore,
        identity: ScheduledFolderOperationIdentity,
    ): DurableScheduledFolderOperationStart {
        val header = identity.toJournal(phase = ScheduledFolderJournalPhase.CAPTURING)
        if (!store.save(header)) return DurableScheduledFolderOperationStart.Failed
        stagedScheduledFolderOperations[identity.operationId] = StagedScheduledFolderOperation(
            identity = identity,
            dates = identity.ownerDates.map(LocalDate::parse),
        )
        return DurableScheduledFolderOperationStart.New
    }

    private suspend fun executeDurableJournal(
        store: ScheduledFolderExportJournalStore,
        initial: ScheduledFolderExportJournal,
        requestedDates: List<LocalDate>,
    ): ExportResult {
        coroutineContext.ensureActive()
        return withContext(NonCancellable) {
            executeDurableJournalNonCancellable(store, initial, requestedDates)
        }
    }

    private suspend fun executeDurableJournalNonCancellable(
        store: ScheduledFolderExportJournalStore,
        initial: ScheduledFolderExportJournal,
        requestedDates: List<LocalDate>,
    ): ExportResult {
        var journal = initial
        val successfulDates = linkedSetOf<LocalDate>()
        var commitFailed = false
        var verifiedArtifactCount = 0

        dayLoop@ for (dayIndex in journal.days.indices) {
            val date = LocalDate.parse(journal.days[dayIndex].ownerDate)
            for (artifactIndex in journal.days[dayIndex].artifacts.indices) {
                var artifact = journal.days[dayIndex].artifacts[artifactIndex]
                val expectedBytes = runCatching {
                    Base64.getDecoder().decode(artifact.contentBase64)
                }.getOrNull()
                if (expectedBytes == null) {
                    commitFailed = true
                    break@dayLoop
                }

                if (artifact.state == ScheduledFolderArtifactState.PREPARED) {
                    val observedDocumentId = when (val inspection =
                        fileExportManager.inspectDurableFile(
                            folderUriString = journal.folderUri,
                            relativePath = artifact.relativePath,
                        )
                    ) {
                        FileExportManager.DurableFileInspection.Missing -> null
                        is FileExportManager.DurableFileInspection.Found -> inspection.documentId
                        FileExportManager.DurableFileInspection.Ambiguous,
                        FileExportManager.DurableFileInspection.Unavailable -> {
                            commitFailed = true
                            break@dayLoop
                        }
                    }
                    artifact = artifact.copy(
                        state = ScheduledFolderArtifactState.BINDING,
                        documentId = observedDocumentId,
                    )
                    journal = journal.replacingArtifact(dayIndex, artifactIndex, artifact)
                    if (!store.save(journal)) {
                        commitFailed = true
                        break@dayLoop
                    }
                }

                if (artifact.state == ScheduledFolderArtifactState.BINDING) {
                    val existingFinalDocumentId = artifact.documentId
                    val bindsStaging = existingFinalDocumentId == null
                    val bound = fileExportManager.bindDurableFile(
                        folderUriString = journal.folderUri,
                        relativePath = if (bindsStaging) {
                            artifact.stagingRelativePath
                        } else {
                            artifact.relativePath
                        },
                        mediaType = artifact.mediaType,
                        expectedDocumentId = existingFinalDocumentId,
                        // A persisted staging intent owns its deterministic hidden name and may
                        // safely adopt the same document after a create-before-checkpoint crash.
                        requireMissing = false,
                    )
                    if (bound == null) {
                        commitFailed = true
                        break@dayLoop
                    }
                    artifact = artifact.copy(
                        state = if (bindsStaging) {
                            ScheduledFolderArtifactState.STAGING_BOUND
                        } else {
                            ScheduledFolderArtifactState.BOUND
                        },
                        documentId = bound.documentId,
                    )
                    journal = journal.replacingArtifact(dayIndex, artifactIndex, artifact)
                    if (!store.save(journal)) {
                        commitFailed = true
                        break@dayLoop
                    }
                }

                if (artifact.state == ScheduledFolderArtifactState.STAGING_BOUND) {
                    val stagingDocumentId = artifact.documentId
                    if (stagingDocumentId == null) {
                        commitFailed = true
                        break@dayLoop
                    }
                    var stagingInspection = fileExportManager.inspectDurableFile(
                        folderUriString = journal.folderUri,
                        relativePath = artifact.stagingRelativePath,
                    )
                    val stagingExact = stagingInspection is FileExportManager.DurableFileInspection.Found &&
                        stagingInspection.documentId == stagingDocumentId &&
                        stagingInspection.content.size == artifact.byteCount &&
                        sha256Hex(stagingInspection.content) == artifact.sha256
                    if (!stagingExact) {
                        val sameStagingDocument =
                            stagingInspection is FileExportManager.DurableFileInspection.Found &&
                                stagingInspection.documentId == stagingDocumentId
                        if (!sameStagingDocument || !fileExportManager.overwriteDurableBoundFile(
                                folderUriString = journal.folderUri,
                                relativePath = artifact.stagingRelativePath,
                                expectedDocumentId = stagingDocumentId,
                                content = expectedBytes,
                            )
                        ) {
                            commitFailed = true
                            break@dayLoop
                        }
                        stagingInspection = fileExportManager.inspectDurableFile(
                            folderUriString = journal.folderUri,
                            relativePath = artifact.stagingRelativePath,
                        )
                    }
                    val staged = stagingInspection is FileExportManager.DurableFileInspection.Found &&
                        stagingInspection.documentId == stagingDocumentId &&
                        stagingInspection.content.size == artifact.byteCount &&
                        sha256Hex(stagingInspection.content) == artifact.sha256
                    if (!staged) {
                        commitFailed = true
                        break@dayLoop
                    }
                    artifact = artifact.copy(state = ScheduledFolderArtifactState.STAGING_WRITTEN)
                    journal = journal.replacingArtifact(dayIndex, artifactIndex, artifact)
                    if (!store.save(journal)) {
                        commitFailed = true
                        break@dayLoop
                    }
                }

                if (artifact.state == ScheduledFolderArtifactState.STAGING_WRITTEN) {
                    val stagingDocumentId = artifact.documentId
                    if (stagingDocumentId == null) {
                        commitFailed = true
                        break@dayLoop
                    }
                    val finalInspection = fileExportManager.inspectDurableFile(
                        folderUriString = journal.folderUri,
                        relativePath = artifact.relativePath,
                    )
                    val finalDocumentId = when {
                        finalInspection is FileExportManager.DurableFileInspection.Found &&
                            finalInspection.documentId == stagingDocumentId &&
                            finalInspection.content.size == artifact.byteCount &&
                            sha256Hex(finalInspection.content) == artifact.sha256 -> stagingDocumentId
                        finalInspection == FileExportManager.DurableFileInspection.Missing -> {
                            val staged = fileExportManager.inspectDurableFile(
                                folderUriString = journal.folderUri,
                                relativePath = artifact.stagingRelativePath,
                            )
                            val stagingStillExact =
                                staged is FileExportManager.DurableFileInspection.Found &&
                                    staged.documentId == stagingDocumentId &&
                                    staged.content.size == artifact.byteCount &&
                                    sha256Hex(staged.content) == artifact.sha256
                            if (!stagingStillExact) {
                                commitFailed = true
                                break@dayLoop
                            }
                            val renamed = fileExportManager.renameDurableBoundFile(
                                folderUriString = journal.folderUri,
                                stagingRelativePath = artifact.stagingRelativePath,
                                finalRelativePath = artifact.relativePath,
                                expectedDocumentId = stagingDocumentId,
                            )
                            if (renamed == null) {
                                commitFailed = true
                                break@dayLoop
                            }
                            renamed.documentId
                        }
                        else -> {
                            commitFailed = true
                            break@dayLoop
                        }
                    }
                    artifact = artifact.copy(
                        state = ScheduledFolderArtifactState.BOUND,
                        documentId = finalDocumentId,
                    )
                    journal = journal.replacingArtifact(dayIndex, artifactIndex, artifact)
                    if (!store.save(journal)) {
                        commitFailed = true
                        break@dayLoop
                    }
                }

                val expectedDocumentId = artifact.documentId
                if (expectedDocumentId == null) {
                    commitFailed = true
                    break@dayLoop
                }
                var inspection = fileExportManager.inspectDurableFile(
                    folderUriString = journal.folderUri,
                    relativePath = artifact.relativePath,
                )
                if (artifact.state == ScheduledFolderArtifactState.BOUND) {
                    val alreadyExact = inspection is FileExportManager.DurableFileInspection.Found &&
                        inspection.documentId == expectedDocumentId &&
                        inspection.content.size == artifact.byteCount &&
                        sha256Hex(inspection.content) == artifact.sha256
                    if (!alreadyExact) {
                        val sameBoundDocument = inspection is FileExportManager.DurableFileInspection.Found &&
                            inspection.documentId == expectedDocumentId
                        if (!sameBoundDocument || !fileExportManager.overwriteDurableBoundFile(
                                folderUriString = journal.folderUri,
                                relativePath = artifact.relativePath,
                                expectedDocumentId = expectedDocumentId,
                                content = expectedBytes,
                            )
                        ) {
                            commitFailed = true
                            break@dayLoop
                        }
                        inspection = fileExportManager.inspectDurableFile(
                            folderUriString = journal.folderUri,
                            relativePath = artifact.relativePath,
                        )
                    }
                    val committed = inspection is FileExportManager.DurableFileInspection.Found &&
                        inspection.documentId == expectedDocumentId &&
                        inspection.content.size == artifact.byteCount &&
                        sha256Hex(inspection.content) == artifact.sha256
                    if (!committed) {
                        commitFailed = true
                        break@dayLoop
                    }
                    artifact = artifact.copy(state = ScheduledFolderArtifactState.ACKNOWLEDGED)
                    journal = journal.replacingArtifact(dayIndex, artifactIndex, artifact)
                    if (!store.save(journal)) {
                        commitFailed = true
                        break@dayLoop
                    }
                } else {
                    val stillExact = inspection is FileExportManager.DurableFileInspection.Found &&
                        inspection.documentId == expectedDocumentId &&
                        inspection.content.size == artifact.byteCount &&
                        sha256Hex(inspection.content) == artifact.sha256
                    if (!stillExact) {
                        commitFailed = true
                        break@dayLoop
                    }
                }
                if (date in requestedDates) verifiedArtifactCount++
            }
            successfulDates += date
        }

        val requestedDateSet = requestedDates.toSet()
        val captureFailures = journal.captureFailures.associate { failure ->
            val date = LocalDate.parse(failure.ownerDate)
            date to FailedDateDetail(
                date = date,
                reason = ExportFailureReason.valueOf(failure.reason),
            )
        }
        val unresolvedPlannedDates = journal.days
            .map { LocalDate.parse(it.ownerDate) }
            .filterNot { it in successfulDates }
        val requestedSuccessfulDates = successfulDates.filter { it in requestedDateSet }
        val requestedUnresolvedDates = unresolvedPlannedDates.filter { it in requestedDateSet }
        val requestedCaptureFailures = captureFailures.filterKeys { it in requestedDateSet }
        val failedDetails = buildList {
            addAll(requestedCaptureFailures.values)
            addAll(requestedUnresolvedDates.map { date ->
                FailedDateDetail(date, ExportFailureReason.FILE_WRITE_ERROR)
            })
        }.sortedBy { it.date }
        val retryIds = if (commitFailed) {
            requestedUnresolvedDates.associateWith { journal.operationId }
        } else {
            emptyMap()
        }
        return ExportResult(
            successCount = requestedSuccessfulDates.size,
            totalCount = requestedDates.size,
            failedDateDetails = failedDetails,
            target = ExportTarget.DEVICE_FOLDER,
            artifactCount = verifiedArtifactCount,
            retryFolderOperationIds = retryIds,
            freshCaptureRetryDates = requestedCaptureFailures.keys,
            usesDurableFolderJournal = true,
        )
    }

    private suspend fun durableIdentity(
        operationId: String,
        dates: List<LocalDate>,
        settings: ExportSettings,
        settingsSnapshotJson: String,
    ): ScheduledFolderOperationIdentity? {
        val normalizedDates = dates.distinct().sorted()
        if (dates != normalizedDates || normalizedDates.isEmpty() ||
            !operationId.matches(Regex("[A-Za-z0-9._-]{1,128}")) ||
            settingsSnapshotJson.isBlank() ||
            !AndroidDailyAggregateExportPlanner.supportsNonLegacy(settings)
        ) return null
        val pin = settings.executionEnginePin ?: return null
        if (pin.engine == ExportEngineMode.legacy || !ExportEnginePinCodec.isStructurallyValid(pin)) {
            return null
        }
        val snapshot = AndroidExportSettingsSnapshotCodec.decodeOrNull(settingsSnapshotJson)
            ?: return null
        if (snapshot.enginePin != pin ||
            snapshot.exportTarget != ExportTarget.DEVICE_FOLDER ||
            snapshot.scheduledExportTarget != ExportTarget.DEVICE_FOLDER
        ) return null
        val recapturedSnapshot = runCatching {
            AndroidExportSettingsSnapshot.capture(
                settings = settings,
                pin = pin,
                zone = ZoneId.of(snapshot.ianaTimeZone),
            )
        }.getOrNull() ?: return null
        if (AndroidExportSettingsSnapshotCodec.encodeCanonical(recapturedSnapshot) != settingsSnapshotJson) {
            return null
        }
        val folderUri = settingsRepository.getExportFolderUri()?.takeIf { it.isNotBlank() }
            ?: return null
        return ScheduledFolderOperationIdentity(
            operationId = operationId,
            folderUri = folderUri,
            settingsSnapshotSha256 = sha256Hex(settingsSnapshotJson.toByteArray(StandardCharsets.UTF_8)),
            enginePinJson = ExportEnginePinCodec.encodeCanonical(pin),
            ownerDates = normalizedDates.map(LocalDate::toString),
        )
    }

    private fun durableFailure(
        dates: List<LocalDate>,
        operationId: String? = null,
        wasCancelled: Boolean = false,
        freshCaptureRetryDates: Set<LocalDate> = emptySet(),
    ): ExportResult = ExportResult(
        successCount = 0,
        totalCount = dates.size,
        failedDateDetails = dates.distinct().sorted().map { date ->
            FailedDateDetail(date, ExportFailureReason.FILE_WRITE_ERROR)
        },
        wasCancelled = wasCancelled,
        target = ExportTarget.DEVICE_FOLDER,
        retryFolderOperationIds = operationId?.let { id ->
            dates.associateWith { id }
        }.orEmpty(),
        freshCaptureRetryDates = freshCaptureRetryDates,
        usesDurableFolderJournal = true,
    )

    override suspend fun previewHealthData(data: HealthData, settings: ExportSettings): ExportPreviewDay {
        // Match iOS preview behavior: a destination is required to write an export, but not
        // to inspect the files Health.md would generate. Without a folder, write-mode previews
        // use a new-file baseline because there is no existing destination file to merge.
        val folderUri = settingsRepository.getExportFolderUri()

        if (settings.selectedExportFormats.isEmpty()) {
            return ExportPreviewDay(
                date = data.date,
                issues = listOf(ExportPreviewIssue(ExportPreviewIssueKind.NO_FORMATS_SELECTED)),
            )
        }

        val selection = try {
            dailyAggregatePlanner.plan(data, settings)
        } catch (error: Throwable) {
            rethrowCancellationOrFatal(error)
            return planningFailurePreview(data)
        }
        return when (selection) {
            LocalDailyAggregatePlanningResult.Legacy ->
                previewLegacy(folderUri, data, settings)
            is LocalDailyAggregatePlanningResult.Failed -> planningFailurePreview(data)
            is LocalDailyAggregatePlanningResult.Planned -> previewPlan(data, selection)
        }
    }

    private fun exportLegacy(
        folderUri: String,
        data: HealthData,
        settings: ExportSettings,
    ): Boolean {
        val writeMode = settings.writeMode.toFileWriteMode()
        val aggregateFiles = buildAggregateFiles(data, settings)
        if (aggregateFiles.isEmpty()) return false

        val aggregateSuccess = aggregateFiles.all { planned ->
            fileExportManager.writeFile(
                folderUriString = folderUri,
                subfolder = planned.subfolder,
                fileName = planned.fileName,
                extension = planned.extension,
                content = planned.content,
                writeMode = writeMode,
            )
        }

        val sideEffectSuccess = buildSideEffects(folderUri, data, settings).all { planned ->
            if (!planned.wouldWrite) {
                true
            } else {
                fileExportManager.writeFileAtRelativePath(
                    folderUriString = folderUri,
                    relativePath = planned.relativePath,
                    content = planned.content.orEmpty(),
                    writeMode = writeMode,
                )
            }
        }

        return aggregateSuccess && sideEffectSuccess
    }

    private fun previewLegacy(
        folderUri: String?,
        data: HealthData,
        settings: ExportSettings,
    ): ExportPreviewDay {
        val files = buildAggregateFiles(data, settings).map { planned ->
            val previewContent = contentAfterWriteMode(
                folderUri = folderUri,
                relativePath = planned.relativePath,
                extension = planned.extension,
                newContent = planned.content,
                settings = settings,
            )
            ExportPreviewFile(
                format = planned.format,
                relativePath = planned.relativePath,
                byteCount = previewContent.toByteArray(Charsets.UTF_8).size,
                content = previewContent,
            )
        }

        val sideEffects = buildSideEffects(folderUri, data, settings).map { planned ->
            val previewContent = planned.content?.let { content ->
                if (planned.wouldWrite) {
                    contentAfterWriteMode(
                        folderUri = folderUri,
                        relativePath = planned.relativePath,
                        extension = extensionForRelativePath(planned.relativePath),
                        newContent = content,
                        settings = settings,
                    )
                } else {
                    content
                }
            }
            ExportPreviewSideEffect(
                type = planned.type,
                relativePath = planned.relativePath,
                action = planned.action,
                byteCount = previewContent?.toByteArray(Charsets.UTF_8)?.size ?: 0,
                content = previewContent,
                wouldWrite = planned.wouldWrite,
            )
        }

        return ExportPreviewDay(
            date = data.date,
            files = files,
            sideEffects = sideEffects,
            issues = if (files.isEmpty() && sideEffects.none { it.wouldWrite }) {
                listOf(ExportPreviewIssue(ExportPreviewIssueKind.NO_FILES_WRITTEN))
            } else {
                emptyList()
            },
        )
    }

    private fun commitAuthoritativePlan(folderUri: String, plan: ExportArtifactPlan): Boolean {
        val barrier = ExportCommitBarrier()
        val writes = plan.items.map { item ->
            if (item.writeMode != ExportArtifactWriteMode.overwrite) {
                barrier.markFailed()
                return false
            }
            val bytes = item.content
            val content = bytes.decodeToString()
            if (!content.encodeToByteArray().contentEquals(bytes)) {
                barrier.markFailed()
                return false
            }
            MaterializedPlanWrite(item.relativePath, content)
        }
        barrier.markMaterialized()

        for ((index, write) in writes.withIndex()) {
            if (index == 0) barrier.markCommitting()
            val success = try {
                fileExportManager.writeFileAtRelativePath(
                    folderUriString = folderUri,
                    relativePath = write.relativePath,
                    content = write.content,
                    writeMode = FileExportManager.WriteMode.OVERWRITE,
                )
            } catch (error: Throwable) {
                if (error is CancellationException || error.isFatalExportEngineFailure()) {
                    barrier.markFailed()
                    throw error
                }
                false
            }
            if (!success) {
                barrier.markFailed()
                return false
            }
        }

        if (writes.isEmpty()) {
            barrier.markFailed()
            return false
        }
        barrier.markCompleted()
        return true
    }

    private fun previewPlan(
        data: HealthData,
        selection: LocalDailyAggregatePlanningResult.Planned,
    ): ExportPreviewDay {
        if (selection.plan.items.size != selection.formats.size) return planningFailurePreview(data)
        val files = selection.plan.items.zip(selection.formats).map { (item, format) ->
            val bytes = item.content
            val content = bytes.decodeToString()
            if (!content.encodeToByteArray().contentEquals(bytes)) return planningFailurePreview(data)
            ExportPreviewFile(
                format = format,
                relativePath = item.relativePath,
                byteCount = bytes.size,
                content = content,
            )
        }
        return ExportPreviewDay(
            date = data.date,
            files = files,
            issues = if (files.isEmpty()) {
                listOf(ExportPreviewIssue(ExportPreviewIssueKind.NO_FILES_WRITTEN))
            } else {
                emptyList()
            },
        )
    }

    private fun planningFailurePreview(data: HealthData): ExportPreviewDay = ExportPreviewDay(
        date = data.date,
        failureReason = ExportFailureReason.UNKNOWN,
        issues = listOf(ExportPreviewIssue(ExportPreviewIssueKind.PLANNING_FAILED)),
    )

    override suspend fun hasExportFolder(): Boolean =
        settingsRepository.getExportFolderUri() != null

    override fun getExportFolderName(): String? {
        return null
    }

    private fun buildAggregateFiles(data: HealthData, settings: ExportSettings): List<PlannedAggregateFile> {
        val selectedFormats = settings.selectedExportFormats.sortedBy { it.ordinal }
        if (selectedFormats.isEmpty()) return emptyList()

        val subfolder = settings.aggregateSubfolderPath(data.date)
        val baseName = settings.formatFilename(data.date)

        return selectedFormats.map { format ->
            val fileName = when {
                format == ExportFormat.OBSIDIAN_BASES && ExportFormat.MARKDOWN in selectedFormats -> "${baseName}-bases"
                else -> baseName
            }
            val extension = format.fileExtension
            val content = contentForFormat(format, data, settings)
            PlannedAggregateFile(
                format = format,
                subfolder = subfolder,
                fileName = fileName,
                extension = extension,
                relativePath = relativePath(subfolder, "$fileName.$extension"),
                content = content,
            )
        }
    }

    private fun contentForFormat(format: ExportFormat, data: HealthData, settings: ExportSettings): String = when (format) {
        ExportFormat.MARKDOWN -> markdownExporter.export(
            data = data,
            includeMetadata = settings.includeMetadata,
            groupByCategory = settings.groupByCategory,
            customization = settings.formatCustomization,
            includeGranularData = settings.includeGranularData,
        )
        ExportFormat.OBSIDIAN_BASES -> obsidianBasesExporter.export(
            data = data,
            customization = settings.formatCustomization,
        )
        ExportFormat.JSON -> jsonExporter.export(
            data = data,
            customization = settings.formatCustomization,
            includeGranularData = settings.includeGranularData,
        )
        ExportFormat.CSV -> csvExporter.export(
            data = data,
            customization = settings.formatCustomization,
            includeGranularData = settings.includeGranularData,
        )
    }

    private fun buildSideEffects(
        folderUri: String?,
        data: HealthData,
        settings: ExportSettings,
    ): List<PlannedSideEffect> = buildList {
        dailyNoteSideEffect(folderUri, data, settings)?.let { add(it) }
        addAll(individualEntrySideEffects(data, settings))
    }

    private fun dailyNoteSideEffect(
        folderUri: String?,
        data: HealthData,
        settings: ExportSettings,
    ): PlannedSideEffect? {
        val injectionSettings = settings.dailyNoteInjection
        if (!injectionSettings.enabled) return null

        val relativePath = injectionSettings.resolvedPath(data.date)
        val existing = folderUri?.let { fileExportManager.readFileAtRelativePath(it, relativePath) }
        val (result, content) = dailyNoteInjector.inject(
            existingContent = existing,
            data = data,
            settings = injectionSettings,
            customization = settings.formatCustomization,
        )

        return PlannedSideEffect(
            type = ExportPreviewSideEffectType.DAILY_NOTE,
            relativePath = relativePath,
            action = when (result) {
                InjectionResult.UPDATED -> ExportPreviewSideEffectAction.UPDATE_DAILY_NOTE
                InjectionResult.CREATED -> ExportPreviewSideEffectAction.CREATE_DAILY_NOTE
                InjectionResult.SKIPPED -> ExportPreviewSideEffectAction.SKIP_DAILY_NOTE
                InjectionResult.FAILED -> ExportPreviewSideEffectAction.DAILY_NOTE_FAILED
            },
            content = content,
            wouldWrite = result == InjectionResult.UPDATED || result == InjectionResult.CREATED,
        )
    }

    private fun individualEntrySideEffects(
        data: HealthData,
        settings: ExportSettings,
    ): List<PlannedSideEffect> {
        val trackingSettings = settings.individualTracking
        if (!trackingSettings.globalEnabled) return emptyList()

        return individualEntryExporter.exportEntries(
            data = data,
            settings = trackingSettings,
            customization = settings.formatCustomization,
        ).map { (entryPath, content) ->
            PlannedSideEffect(
                type = ExportPreviewSideEffectType.INDIVIDUAL_ENTRY,
                relativePath = entryPath,
                action = ExportPreviewSideEffectAction.WRITE_INDIVIDUAL_ENTRY,
                content = content,
                wouldWrite = true,
            )
        }
    }

    private fun durableStagingPath(relativePath: String, artifactId: String): String {
        val parent = relativePath.substringBeforeLast('/', missingDelimiterValue = "")
        val fileName = relativePath.substringAfterLast('/')
        val stagingName = ".$fileName.healthmd-${artifactId.take(24)}.pending"
        return listOf(parent, stagingName).filter { it.isNotBlank() }.joinToString("/")
    }

    private fun relativePath(subfolder: String?, fileName: String): String =
        listOfNotNull(subfolder?.trim('/').takeUnless { it.isNullOrBlank() }, fileName)
            .joinToString("/")

    private fun contentAfterWriteMode(
        folderUri: String?,
        relativePath: String,
        extension: String,
        newContent: String,
        settings: ExportSettings,
    ): String {
        val existing = when {
            folderUri == null || settings.writeMode == SettingsWriteMode.OVERWRITE -> null
            else -> fileExportManager.readFileAtRelativePath(folderUri, relativePath)
        }
        val existingFileExists = existing != null ||
            (folderUri != null && settings.writeMode == SettingsWriteMode.APPEND &&
                fileExportManager.fileExistsAtRelativePath(folderUri, relativePath))

        return when {
            settings.writeMode == SettingsWriteMode.APPEND && existing != null -> existing + "\n" + newContent
            settings.writeMode == SettingsWriteMode.APPEND && existingFileExists -> "\n" + newContent
            existing != null && settings.writeMode == SettingsWriteMode.UPDATE && extension.equals("md", ignoreCase = true) ->
                markdownMerger.merge(existing, newContent)
            else -> newContent
        }
    }

    private fun extensionForRelativePath(relativePath: String): String =
        relativePath.substringAfterLast('/').substringAfterLast('.', missingDelimiterValue = "txt")

    private fun SettingsWriteMode.toFileWriteMode(): FileExportManager.WriteMode = when (this) {
        SettingsWriteMode.OVERWRITE -> FileExportManager.WriteMode.OVERWRITE
        SettingsWriteMode.APPEND -> FileExportManager.WriteMode.APPEND
        SettingsWriteMode.UPDATE -> FileExportManager.WriteMode.UPDATE
    }

    private data class ScheduledFolderOperationIdentity(
        val operationId: String,
        val folderUri: String,
        val settingsSnapshotSha256: String,
        val enginePinJson: String,
        val ownerDates: List<String>,
    ) {
        fun toJournal(
            phase: ScheduledFolderJournalPhase,
            days: List<ScheduledFolderJournalDay> = emptyList(),
            failures: List<ScheduledFolderJournalFailure> = emptyList(),
        ): ScheduledFolderExportJournal {
            val journal = ScheduledFolderExportJournal(
                operationId = operationId,
                folderUri = folderUri,
                settingsSnapshotSha256 = settingsSnapshotSha256,
                enginePinJson = enginePinJson,
                ownerDates = ownerDates,
                phase = phase,
                days = days,
                captureFailures = failures,
            )
            return if (phase == ScheduledFolderJournalPhase.READY) {
                journal.copy(planSha256 = scheduledFolderImmutablePlanSha256(journal))
            } else {
                journal
            }
        }

        fun matches(journal: ScheduledFolderExportJournal): Boolean =
            operationId == journal.operationId &&
                folderUri == journal.folderUri &&
                settingsSnapshotSha256 == journal.settingsSnapshotSha256 &&
                enginePinJson == journal.enginePinJson &&
                ownerDates.all { it in journal.ownerDates }
    }

    private data class StagedScheduledFolderOperation(
        val identity: ScheduledFolderOperationIdentity,
        val dates: List<LocalDate>,
        val plans: LinkedHashMap<LocalDate, ExportArtifactPlan> = linkedMapOf(),
    )

    private fun ScheduledFolderExportJournal.canResume(requestedOwnerDates: List<String>): Boolean {
        val requested = requestedOwnerDates.toSet()
        val unresolved = days
            .filter { day ->
                day.artifacts.any { artifact ->
                    artifact.state != ScheduledFolderArtifactState.ACKNOWLEDGED
                }
            }
            .mapTo(linkedSetOf()) { it.ownerDate }
        return requested.all { it in ownerDates } && requested.containsAll(unresolved)
    }

    private fun ScheduledFolderExportJournal.replacingArtifact(
        dayIndex: Int,
        artifactIndex: Int,
        artifact: ScheduledFolderJournalArtifact,
    ): ScheduledFolderExportJournal {
        val updatedDays = days.toMutableList()
        val day = updatedDays[dayIndex]
        val updatedArtifacts = day.artifacts.toMutableList()
        updatedArtifacts[artifactIndex] = artifact
        updatedDays[dayIndex] = day.copy(artifacts = updatedArtifacts)
        return copy(days = updatedDays)
    }

    private data class MaterializedPlanWrite(
        val relativePath: String,
        val content: String,
    )

    private data class PlannedAggregateFile(
        val format: ExportFormat,
        val subfolder: String?,
        val fileName: String,
        val extension: String,
        val relativePath: String,
        val content: String,
    )

    private data class PlannedSideEffect(
        val type: ExportPreviewSideEffectType,
        val relativePath: String,
        val action: ExportPreviewSideEffectAction,
        val content: String?,
        val wouldWrite: Boolean,
    )

    private fun rethrowCancellationOrFatal(error: Throwable) {
        if (error is CancellationException || error.isFatalExportEngineFailure()) throw error
    }
}
