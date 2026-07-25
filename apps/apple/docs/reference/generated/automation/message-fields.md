# Generated automation message and field inventory

This inventory is generated from production API/control serialization and every current `SyncMessage` Codable case. Paths ending in `[]` describe array elements.

- Generated JSON artifacts inventoried: 28
- Sync messages inventoried: 38

## SyncMessage wire inventory

### `connectedCorpusStatus`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.connectedCorpusStatus` | object |
| `$.connectedCorpusStatus._0` | object |
| `$.connectedCorpusStatus._0.committedBytes` | integer |
| `$.connectedCorpusStatus._0.committedPartitionCount` | integer |
| `$.connectedCorpusStatus._0.currentDate` | integer |
| `$.connectedCorpusStatus._0.expiresAt` | integer |
| `$.connectedCorpusStatus._0.jobID` | string |
| `$.connectedCorpusStatus._0.message` | string |
| `$.connectedCorpusStatus._0.processedDays` | integer |
| `$.connectedCorpusStatus._0.requestFingerprint` | object |
| `$.connectedCorpusStatus._0.requestFingerprint.sha256` | string |
| `$.connectedCorpusStatus._0.requestFingerprint.version` | integer |
| `$.connectedCorpusStatus._0.sessionID` | string |
| `$.connectedCorpusStatus._0.state` | string |
| `$.connectedCorpusStatus._0.totalDays` | integer |
| `$.connectedCorpusStatus._0.updatedAt` | integer |

### `connectedCorpusTransferCancel`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.connectedCorpusTransferCancel` | object |
| `$.connectedCorpusTransferCancel._0` | object |
| `$.connectedCorpusTransferCancel._0.jobID` | string |
| `$.connectedCorpusTransferCancel._0.message` | string |
| `$.connectedCorpusTransferCancel._0.reason` | string |
| `$.connectedCorpusTransferCancel._0.requestedAt` | integer |
| `$.connectedCorpusTransferCancel._0.sessionID` | string |

### `connectedCorpusTransferCancelAck`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.connectedCorpusTransferCancelAck` | object |
| `$.connectedCorpusTransferCancelAck._0` | object |
| `$.connectedCorpusTransferCancelAck._0.accepted` | boolean |
| `$.connectedCorpusTransferCancelAck._0.acknowledgedAt` | integer |
| `$.connectedCorpusTransferCancelAck._0.jobID` | string |
| `$.connectedCorpusTransferCancelAck._0.message` | string |
| `$.connectedCorpusTransferCancelAck._0.sessionID` | string |

### `connectedCorpusTransferDisposition`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.connectedCorpusTransferDisposition` | object |
| `$.connectedCorpusTransferDisposition._0` | object |
| `$.connectedCorpusTransferDisposition._0.disposition` | string |
| `$.connectedCorpusTransferDisposition._0.jobID` | string |
| `$.connectedCorpusTransferDisposition._0.message` | string |
| `$.connectedCorpusTransferDisposition._0.nextPartitionIndex` | integer |
| `$.connectedCorpusTransferDisposition._0.partitionIndex` | integer |
| `$.connectedCorpusTransferDisposition._0.partitionSHA256` | string |
| `$.connectedCorpusTransferDisposition._0.sessionID` | string |

### `connectedCorpusTransferFinalAck`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.connectedCorpusTransferFinalAck` | object |
| `$.connectedCorpusTransferFinalAck._0` | object |
| `$.connectedCorpusTransferFinalAck._0.accepted` | boolean |
| `$.connectedCorpusTransferFinalAck._0.finalPartitionSHA256` | string |
| `$.connectedCorpusTransferFinalAck._0.jobID` | string |
| `$.connectedCorpusTransferFinalAck._0.message` | string |
| `$.connectedCorpusTransferFinalAck._0.requestFingerprint` | object |
| `$.connectedCorpusTransferFinalAck._0.requestFingerprint.sha256` | string |
| `$.connectedCorpusTransferFinalAck._0.requestFingerprint.version` | integer |
| `$.connectedCorpusTransferFinalAck._0.sessionID` | string |

### `connectedCorpusTransferFinalize`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.connectedCorpusTransferFinalize` | object |
| `$.connectedCorpusTransferFinalize._0` | object |
| `$.connectedCorpusTransferFinalize._0.finalPartitionSHA256` | string |
| `$.connectedCorpusTransferFinalize._0.jobID` | string |
| `$.connectedCorpusTransferFinalize._0.partitionCount` | integer |
| `$.connectedCorpusTransferFinalize._0.requestFingerprint` | object |
| `$.connectedCorpusTransferFinalize._0.requestFingerprint.sha256` | string |
| `$.connectedCorpusTransferFinalize._0.requestFingerprint.version` | integer |
| `$.connectedCorpusTransferFinalize._0.sessionID` | string |
| `$.connectedCorpusTransferFinalize._0.totalByteCount` | integer |

### `connectedCorpusTransferOpen`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.connectedCorpusTransferOpen` | object |
| `$.connectedCorpusTransferOpen._0` | object |
| `$.connectedCorpusTransferOpen._0.partition` | object |
| `$.connectedCorpusTransferOpen._0.partition.byteCount` | integer |
| `$.connectedCorpusTransferOpen._0.partition.index` | integer |
| `$.connectedCorpusTransferOpen._0.partition.jobID` | string |
| `$.connectedCorpusTransferOpen._0.partition.sessionID` | string |
| `$.connectedCorpusTransferOpen._0.partition.sha256` | string |
| `$.connectedCorpusTransferOpen._0.partition.sourceDates` | array |
| `$.connectedCorpusTransferOpen._0.partition.sourceDates[]` | integer |
| `$.connectedCorpusTransferOpen._0.session` | object |
| `$.connectedCorpusTransferOpen._0.session.createdAt` | integer |
| `$.connectedCorpusTransferOpen._0.session.jobID` | string |
| `$.connectedCorpusTransferOpen._0.session.partitionTargetBytes` | integer |
| `$.connectedCorpusTransferOpen._0.session.protocolVersion` | integer |
| `$.connectedCorpusTransferOpen._0.session.requestFingerprint` | object |
| `$.connectedCorpusTransferOpen._0.session.requestFingerprint.sha256` | string |
| `$.connectedCorpusTransferOpen._0.session.requestFingerprint.version` | integer |
| `$.connectedCorpusTransferOpen._0.session.sessionID` | string |

### `connectedTransferAbort`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.connectedTransferAbort` | object |
| `$.connectedTransferAbort._0` | object |
| `$.connectedTransferAbort._0.jobID` | string |
| `$.connectedTransferAbort._0.message` | string |
| `$.connectedTransferAbort._0.reason` | string |
| `$.connectedTransferAbort._0.transferID` | string |

### `connectedTransferAck`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.connectedTransferAck` | object |
| `$.connectedTransferAck._0` | object |
| `$.connectedTransferAck._0.accepted` | boolean |
| `$.connectedTransferAck._0.message` | string |
| `$.connectedTransferAck._0.sequence` | integer |
| `$.connectedTransferAck._0.sha256` | string |
| `$.connectedTransferAck._0.transferID` | string |

### `connectedTransferChunk`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.connectedTransferChunk` | object |
| `$.connectedTransferChunk._0` | object |
| `$.connectedTransferChunk._0.data` | string |
| `$.connectedTransferChunk._0.sequence` | integer |
| `$.connectedTransferChunk._0.sha256` | string |
| `$.connectedTransferChunk._0.transferID` | string |

### `connectedTransferComplete`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.connectedTransferComplete` | object |
| `$.connectedTransferComplete._0` | object |
| `$.connectedTransferComplete._0.sha256` | string |
| `$.connectedTransferComplete._0.totalBytes` | integer |
| `$.connectedTransferComplete._0.totalChunks` | integer |
| `$.connectedTransferComplete._0.transferID` | string |

### `connectedTransferFinalAck`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.connectedTransferFinalAck` | object |
| `$.connectedTransferFinalAck._0` | object |
| `$.connectedTransferFinalAck._0.accepted` | boolean |
| `$.connectedTransferFinalAck._0.message` | string |
| `$.connectedTransferFinalAck._0.sha256` | string |
| `$.connectedTransferFinalAck._0.transferID` | string |

### `connectedTransferStart`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.connectedTransferStart` | object |
| `$.connectedTransferStart._0` | object |
| `$.connectedTransferStart._0.chunkBytes` | integer |
| `$.connectedTransferStart._0.manifest` | object |
| `$.connectedTransferStart._0.manifest.jobID` | string |
| `$.connectedTransferStart._0.manifest.kind` | string |
| `$.connectedTransferStart._0.manifest.payloadSchemaVersion` | integer |
| `$.connectedTransferStart._0.protocolVersion` | integer |
| `$.connectedTransferStart._0.sha256` | string |
| `$.connectedTransferStart._0.totalBytes` | integer |
| `$.connectedTransferStart._0.totalChunks` | integer |
| `$.connectedTransferStart._0.transferID` | string |

### `healthData`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.healthData` | object |
| `$.healthData._0` | object |
| `$.healthData._0.deviceName` | string |
| `$.healthData._0.healthRecords` | array |
| `$.healthData._0.healthRecords[]` | object |
| `$.healthData._0.healthRecords[].activity` | object |
| `$.healthData._0.healthRecords[].body` | object |
| `$.healthData._0.healthRecords[].cyclingPerformance` | object |
| `$.healthData._0.healthRecords[].date` | integer |
| `$.healthData._0.healthRecords[].healthKitRecordArchive` | object |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.captureStatus` | string |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.dailyOwnership` | object |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.dailyOwnership.assignmentRule` | string |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.dailyOwnership.calendarIdentifier` | string |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.dailyOwnership.calendarTimeZoneIdentifier` | string |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.dailyOwnership.intervalEnd` | integer |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.dailyOwnership.intervalStart` | integer |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.dailyOwnership.ownerDate` | string |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.externalRecords` | array |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.integrityWarnings` | array |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.medicationInventoryRecords` | array |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.queryManifest` | object |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.queryManifest.results` | array |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.queryManifest.results[]` | object |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.queryManifest.results[].identifier` | string |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.queryManifest.results[].interval` | object |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.queryManifest.results[].interval.endDate` | integer |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.queryManifest.results[].interval.startDate` | integer |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.queryManifest.results[].metricIDs` | array |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.queryManifest.results[].metricIDs[]` | string |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.queryManifest.results[].objectTypeIdentifier` | string |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.queryManifest.results[].operation` | string |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.queryManifest.results[].recordCount` | integer |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.queryManifest.results[].status` | string |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.queryManifest.results[].statusDescription` | string |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.recordSchemaVersion` | integer |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.records` | array |
| `$.healthData._0.healthRecords[].healthKitRecordArchive.schemaIdentifier` | string |
| `$.healthData._0.healthRecords[].healthKitRecordCaptureStatus` | string |
| `$.healthData._0.healthRecords[].hearing` | object |
| `$.healthData._0.healthRecords[].heart` | object |
| `$.healthData._0.healthRecords[].heart.heartRateSamples` | array |
| `$.healthData._0.healthRecords[].heart.hrvSamples` | array |
| `$.healthData._0.healthRecords[].mindfulness` | object |
| `$.healthData._0.healthRecords[].mindfulness.stateOfMind` | array |
| `$.healthData._0.healthRecords[].minerals` | object |
| `$.healthData._0.healthRecords[].mobility` | object |
| `$.healthData._0.healthRecords[].nutrition` | object |
| `$.healthData._0.healthRecords[].other` | object |
| `$.healthData._0.healthRecords[].partialFailures` | array |
| `$.healthData._0.healthRecords[].reproductiveHealth` | object |
| `$.healthData._0.healthRecords[].sleep` | object |
| `$.healthData._0.healthRecords[].sleep.awakeTime` | integer |
| `$.healthData._0.healthRecords[].sleep.coreSleep` | integer |
| `$.healthData._0.healthRecords[].sleep.deepSleep` | integer |
| `$.healthData._0.healthRecords[].sleep.inBedTime` | integer |
| `$.healthData._0.healthRecords[].sleep.remSleep` | integer |
| `$.healthData._0.healthRecords[].sleep.stages` | array |
| `$.healthData._0.healthRecords[].sleep.totalDuration` | integer |
| `$.healthData._0.healthRecords[].symptoms` | object |
| `$.healthData._0.healthRecords[].symptoms.counts` | object |
| `$.healthData._0.healthRecords[].symptoms.samples` | array |
| `$.healthData._0.healthRecords[].timeContext` | object |
| `$.healthData._0.healthRecords[].timeContext.calendarTimeZoneIdentifier` | string |
| `$.healthData._0.healthRecords[].vitals` | object |
| `$.healthData._0.healthRecords[].vitals.bloodGlucoseSamples` | array |
| `$.healthData._0.healthRecords[].vitals.bloodOxygenSamples` | array |
| `$.healthData._0.healthRecords[].vitals.bloodPressureSamples` | array |
| `$.healthData._0.healthRecords[].vitals.respiratoryRateSamples` | array |
| `$.healthData._0.healthRecords[].vitamins` | object |
| `$.healthData._0.healthRecords[].workouts` | array |
| `$.healthData._0.syncTimestamp` | integer |

### `hello`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.hello` | object |
| `$.hello._0` | object |
| `$.hello._0.appVersion` | string |
| `$.hello._0.buildNumber` | string |
| `$.hello._0.canonicalArchiveSchemaVersions` | array |
| `$.hello._0.canonicalArchiveSchemaVersions[]` | integer |
| `$.hello._0.canonicalRawResultSchemaVersions` | array |
| `$.hello._0.canonicalRawResultSchemaVersions[]` | integer |
| `$.hello._0.connectedCorpusTransferCapabilities` | object |
| `$.hello._0.connectedCorpusTransferCapabilities.partitionTargetBounds` | object |
| `$.hello._0.connectedCorpusTransferCapabilities.partitionTargetBounds.maximumBytes` | integer |
| `$.hello._0.connectedCorpusTransferCapabilities.partitionTargetBounds.minimumBytes` | integer |
| `$.hello._0.connectedCorpusTransferCapabilities.partitionTargetBounds.preferredBytes` | integer |
| `$.hello._0.connectedCorpusTransferCapabilities.protocolVersions` | array |
| `$.hello._0.connectedCorpusTransferCapabilities.protocolVersions[]` | integer |
| `$.hello._0.connectedTransferBinaryFrameVersions` | array |
| `$.hello._0.connectedTransferMaximumInFlightChunks` | integer |
| `$.hello._0.installationID` | string |
| `$.hello._0.manualIPSyncRequiresPairing` | boolean |
| `$.hello._0.platform` | string |
| `$.hello._0.protocolVersion` | integer |
| `$.hello._0.supportsAllAvailableHistoryExportRequests` | boolean |
| `$.hello._0.supportsCanonicalHealthDataSelection` | boolean |
| `$.hello._0.supportsChunkedMacExportJobs` | boolean |
| `$.hello._0.supportsDailyNoteOnlyExports` | boolean |
| `$.hello._0.supportsDurableConnectedExportRecovery` | boolean |
| `$.hello._0.supportsGranularPayloads` | boolean |
| `$.hello._0.supportsIPhoneExportRequests` | boolean |
| `$.hello._0.supportsJobCancellation` | boolean |
| `$.hello._0.supportsMacDestinationStatus` | boolean |
| `$.hello._0.supportsMacExportJobs` | boolean |
| `$.hello._0.supportsManualIPSync` | boolean |
| `$.hello._0.supportsPartitionedConnectedExports` | boolean |
| `$.hello._0.supportsPerDateExportCompletion` | boolean |
| `$.hello._0.supportsRequestScopedContextAcquisition` | boolean |
| `$.hello._0.supportsRollupSummaries` | boolean |
| `$.hello._0.supportsSizeBoundedConnectedTransfers` | boolean |
| `$.hello._0.supportsStrictRawStreaming` | boolean |
| `$.hello._0.supportsSummaryOnlyExports` | boolean |

### `iphoneExportAccepted`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.iphoneExportAccepted` | object |
| `$.iphoneExportAccepted._0` | object |
| `$.iphoneExportAccepted._0.acceptedAt` | integer |
| `$.iphoneExportAccepted._0.jobID` | string |
| `$.iphoneExportAccepted._0.message` | string |

### `iphoneExportCancel`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.iphoneExportCancel` | object |
| `$.iphoneExportCancel.jobID` | string |

### `iphoneExportPreparationProgress`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.iphoneExportPreparationProgress` | object |
| `$.iphoneExportPreparationProgress._0` | object |
| `$.iphoneExportPreparationProgress._0.currentDate` | integer |
| `$.iphoneExportPreparationProgress._0.jobID` | string |
| `$.iphoneExportPreparationProgress._0.message` | string |
| `$.iphoneExportPreparationProgress._0.processedDays` | integer |
| `$.iphoneExportPreparationProgress._0.totalDays` | integer |

### `iphoneExportRawData`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.iphoneExportRawData` | object |
| `$.iphoneExportRawData._0` | object |
| `$.iphoneExportRawData._0.createdAt` | integer |
| `$.iphoneExportRawData._0.dateRangeEnd` | integer |
| `$.iphoneExportRawData._0.dateRangeStart` | integer |
| `$.iphoneExportRawData._0.externalDailyRecords` | array |
| `$.iphoneExportRawData._0.externalDailyRecords[]` | object |
| `$.iphoneExportRawData._0.externalDailyRecords[].date` | string |
| `$.iphoneExportRawData._0.externalDailyRecords[].fetched_at` | integer |
| `$.iphoneExportRawData._0.externalDailyRecords[].payloads` | array |
| `$.iphoneExportRawData._0.externalDailyRecords[].payloads[]` | object |
| `$.iphoneExportRawData._0.externalDailyRecords[].payloads[].data` | object |
| `$.iphoneExportRawData._0.externalDailyRecords[].payloads[].data.fixture_id` | string |
| `$.iphoneExportRawData._0.externalDailyRecords[].payloads[].data.score` | number |
| `$.iphoneExportRawData._0.externalDailyRecords[].payloads[].data.synthetic` | boolean |
| `$.iphoneExportRawData._0.externalDailyRecords[].payloads[].endpoint` | string |
| `$.iphoneExportRawData._0.externalDailyRecords[].payloads[].fetched_at` | integer |
| `$.iphoneExportRawData._0.externalDailyRecords[].payloads[].name` | string |
| `$.iphoneExportRawData._0.externalDailyRecords[].payloads[].status_code` | integer |
| `$.iphoneExportRawData._0.externalDailyRecords[].provider` | string |
| `$.iphoneExportRawData._0.externalDailyRecords[].provider_display_name` | string |
| `$.iphoneExportRawData._0.externalDailyRecords[].schema` | string |
| `$.iphoneExportRawData._0.externalDailyRecords[].schema_version` | integer |
| `$.iphoneExportRawData._0.externalDailyRecords[].warnings` | array |
| `$.iphoneExportRawData._0.externalDailyRecords[].warnings[]` | string |
| `$.iphoneExportRawData._0.failedDateDetails` | array |
| `$.iphoneExportRawData._0.failedDateDetails[]` | object |
| `$.iphoneExportRawData._0.failedDateDetails[].date` | integer |
| `$.iphoneExportRawData._0.failedDateDetails[].errorDetails` | string |
| `$.iphoneExportRawData._0.failedDateDetails[].reason` | string |
| `$.iphoneExportRawData._0.jobID` | string |
| `$.iphoneExportRawData._0.records` | array |
| `$.iphoneExportRawData._0.records[]` | object |
| `$.iphoneExportRawData._0.records[].activity` | object |
| `$.iphoneExportRawData._0.records[].body` | object |
| `$.iphoneExportRawData._0.records[].cyclingPerformance` | object |
| `$.iphoneExportRawData._0.records[].date` | integer |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive` | object |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.captureStatus` | string |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.dailyOwnership` | object |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.dailyOwnership.assignmentRule` | string |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.dailyOwnership.calendarIdentifier` | string |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.dailyOwnership.calendarTimeZoneIdentifier` | string |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.dailyOwnership.intervalEnd` | integer |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.dailyOwnership.intervalStart` | integer |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.dailyOwnership.ownerDate` | string |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.externalRecords` | array |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.integrityWarnings` | array |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.medicationInventoryRecords` | array |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.queryManifest` | object |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.queryManifest.results` | array |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.queryManifest.results[]` | object |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.queryManifest.results[].identifier` | string |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.queryManifest.results[].interval` | object |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.queryManifest.results[].interval.endDate` | integer |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.queryManifest.results[].interval.startDate` | integer |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.queryManifest.results[].metricIDs` | array |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.queryManifest.results[].metricIDs[]` | string |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.queryManifest.results[].objectTypeIdentifier` | string |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.queryManifest.results[].operation` | string |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.queryManifest.results[].recordCount` | integer |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.queryManifest.results[].status` | string |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.queryManifest.results[].statusDescription` | string |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.recordSchemaVersion` | integer |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.records` | array |
| `$.iphoneExportRawData._0.records[].healthKitRecordArchive.schemaIdentifier` | string |
| `$.iphoneExportRawData._0.records[].healthKitRecordCaptureStatus` | string |
| `$.iphoneExportRawData._0.records[].hearing` | object |
| `$.iphoneExportRawData._0.records[].heart` | object |
| `$.iphoneExportRawData._0.records[].heart.heartRateSamples` | array |
| `$.iphoneExportRawData._0.records[].heart.hrvSamples` | array |
| `$.iphoneExportRawData._0.records[].mindfulness` | object |
| `$.iphoneExportRawData._0.records[].mindfulness.stateOfMind` | array |
| `$.iphoneExportRawData._0.records[].minerals` | object |
| `$.iphoneExportRawData._0.records[].mobility` | object |
| `$.iphoneExportRawData._0.records[].nutrition` | object |
| `$.iphoneExportRawData._0.records[].other` | object |
| `$.iphoneExportRawData._0.records[].partialFailures` | array |
| `$.iphoneExportRawData._0.records[].reproductiveHealth` | object |
| `$.iphoneExportRawData._0.records[].sleep` | object |
| `$.iphoneExportRawData._0.records[].sleep.awakeTime` | integer |
| `$.iphoneExportRawData._0.records[].sleep.coreSleep` | integer |
| `$.iphoneExportRawData._0.records[].sleep.deepSleep` | integer |
| `$.iphoneExportRawData._0.records[].sleep.inBedTime` | integer |
| `$.iphoneExportRawData._0.records[].sleep.remSleep` | integer |
| `$.iphoneExportRawData._0.records[].sleep.stages` | array |
| `$.iphoneExportRawData._0.records[].sleep.totalDuration` | integer |
| `$.iphoneExportRawData._0.records[].symptoms` | object |
| `$.iphoneExportRawData._0.records[].symptoms.counts` | object |
| `$.iphoneExportRawData._0.records[].symptoms.samples` | array |
| `$.iphoneExportRawData._0.records[].timeContext` | object |
| `$.iphoneExportRawData._0.records[].timeContext.calendarTimeZoneIdentifier` | string |
| `$.iphoneExportRawData._0.records[].vitals` | object |
| `$.iphoneExportRawData._0.records[].vitals.bloodGlucoseSamples` | array |
| `$.iphoneExportRawData._0.records[].vitals.bloodOxygenSamples` | array |
| `$.iphoneExportRawData._0.records[].vitals.bloodPressureSamples` | array |
| `$.iphoneExportRawData._0.records[].vitals.respiratoryRateSamples` | array |
| `$.iphoneExportRawData._0.records[].vitamins` | object |
| `$.iphoneExportRawData._0.records[].workouts` | array |
| `$.iphoneExportRawData._0.settingsSnapshot` | object |
| `$.iphoneExportRawData._0.settingsSnapshot.archiveExportFiles` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.dailyNoteInjection` | object |
| `$.iphoneExportRawData._0.settingsSnapshot.dailyNoteInjection.createIfMissing` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.dailyNoteInjection.dailyNotesOnly` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.dailyNoteInjection.enabled` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.dailyNoteInjection.filenamePattern` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.dailyNoteInjection.folderPath` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.dailyNoteInjection.injectMarkdownSections` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.exportFormats` | array |
| `$.iphoneExportRawData._0.settingsSnapshot.exportFormats[]` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.filenameFormat` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.folderStructure` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization` | object |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.dateFormat` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.frontmatterConfig` | object |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.frontmatterConfig.customDateKey` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.frontmatterConfig.customFields` | object |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.frontmatterConfig.customTypeKey` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.frontmatterConfig.customTypeValue` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.frontmatterConfig.fields` | array |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.frontmatterConfig.fields[]` | object |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.frontmatterConfig.fields[].customKey` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.frontmatterConfig.fields[].isEnabled` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.frontmatterConfig.fields[].originalKey` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.frontmatterConfig.includeDate` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.frontmatterConfig.includeType` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.frontmatterConfig.keyStyle` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.frontmatterConfig.placeholderFields` | array |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.markdownTemplate` | object |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.markdownTemplate.bulletStyle` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.markdownTemplate.customTemplate` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.markdownTemplate.includeSummary` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.markdownTemplate.sectionHeaderLevel` | integer |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.markdownTemplate.style` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.markdownTemplate.useEmoji` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.timeFormat` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.formatCustomization.unitPreference` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.generateMonthlyRollups` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.generateWeeklyRollups` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.generateYearlyRollups` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.groupByCategory` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.healthSubfolder` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.includeGranularData` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.includeMetadata` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.individualTracking` | object |
| `$.iphoneExportRawData._0.settingsSnapshot.individualTracking.entriesFolder` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.individualTracking.filenameTemplate` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.individualTracking.globalEnabled` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.individualTracking.metricConfigs` | object |
| `$.iphoneExportRawData._0.settingsSnapshot.individualTracking.useCategoryFolders` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.metricSelection` | object |
| `$.iphoneExportRawData._0.settingsSnapshot.metricSelection.enabledCategoryIDs` | array |
| `$.iphoneExportRawData._0.settingsSnapshot.metricSelection.enabledCategoryIDs[]` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.metricSelection.enabledMetricIDs` | array |
| `$.iphoneExportRawData._0.settingsSnapshot.metricSelection.enabledMetricIDs[]` | string |
| `$.iphoneExportRawData._0.settingsSnapshot.organizeFormatsIntoFolders` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.summaryOnlyExport` | boolean |
| `$.iphoneExportRawData._0.settingsSnapshot.writeMode` | string |
| `$.iphoneExportRawData._0.sourceDeviceName` | string |
| `$.iphoneExportRawData._0.totalDays` | integer |

### `iphoneExportRejected`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.iphoneExportRejected` | object |
| `$.iphoneExportRejected._0` | object |
| `$.iphoneExportRejected._0.jobID` | string |
| `$.iphoneExportRejected._0.message` | string |
| `$.iphoneExportRejected._0.occurredAt` | integer |
| `$.iphoneExportRejected._0.reason` | string |
| `$.iphoneExportRejected._0.underlyingError` | string |

### `iphoneExportRequest`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.iphoneExportRequest` | object |
| `$.iphoneExportRequest._0` | object |
| `$.iphoneExportRequest._0.createdAt` | integer |
| `$.iphoneExportRequest._0.dateRangeEnd` | integer |
| `$.iphoneExportRequest._0.dateRangeStart` | integer |
| `$.iphoneExportRequest._0.dateSelection` | string |
| `$.iphoneExportRequest._0.jobID` | string |
| `$.iphoneExportRequest._0.rawProfile` | string |
| `$.iphoneExportRequest._0.requestedBy` | string |
| `$.iphoneExportRequest._0.responseMode` | string |
| `$.iphoneExportRequest._0.settingsPolicy` | string |

### `macExportAccepted`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.macExportAccepted` | object |
| `$.macExportAccepted._0` | object |
| `$.macExportAccepted._0.acceptedAt` | integer |
| `$.macExportAccepted._0.jobID` | string |
| `$.macExportAccepted._0.message` | string |

### `macExportCancel`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.macExportCancel` | object |
| `$.macExportCancel.jobID` | string |

### `macExportFailed`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.macExportFailed` | object |
| `$.macExportFailed._0` | object |
| `$.macExportFailed._0.jobID` | string |
| `$.macExportFailed._0.message` | string |
| `$.macExportFailed._0.occurredAt` | integer |
| `$.macExportFailed._0.reason` | string |
| `$.macExportFailed._0.underlyingError` | string |

### `macExportProgress`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.macExportProgress` | object |
| `$.macExportProgress._0` | object |
| `$.macExportProgress._0.currentDate` | integer |
| `$.macExportProgress._0.filesWritten` | integer |
| `$.macExportProgress._0.jobID` | string |
| `$.macExportProgress._0.message` | string |
| `$.macExportProgress._0.phase` | string |
| `$.macExportProgress._0.processedDays` | integer |
| `$.macExportProgress._0.totalDays` | integer |

### `macExportRequest`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.macExportRequest` | object |
| `$.macExportRequest._0` | object |
| `$.macExportRequest._0.createdAt` | integer |
| `$.macExportRequest._0.dateRangeEnd` | integer |
| `$.macExportRequest._0.dateRangeStart` | integer |
| `$.macExportRequest._0.externalDailyRecords` | array |
| `$.macExportRequest._0.externalDailyRecords[]` | object |
| `$.macExportRequest._0.externalDailyRecords[].date` | string |
| `$.macExportRequest._0.externalDailyRecords[].fetched_at` | integer |
| `$.macExportRequest._0.externalDailyRecords[].payloads` | array |
| `$.macExportRequest._0.externalDailyRecords[].payloads[]` | object |
| `$.macExportRequest._0.externalDailyRecords[].payloads[].data` | object |
| `$.macExportRequest._0.externalDailyRecords[].payloads[].data.fixture_id` | string |
| `$.macExportRequest._0.externalDailyRecords[].payloads[].data.score` | number |
| `$.macExportRequest._0.externalDailyRecords[].payloads[].data.synthetic` | boolean |
| `$.macExportRequest._0.externalDailyRecords[].payloads[].endpoint` | string |
| `$.macExportRequest._0.externalDailyRecords[].payloads[].fetched_at` | integer |
| `$.macExportRequest._0.externalDailyRecords[].payloads[].name` | string |
| `$.macExportRequest._0.externalDailyRecords[].payloads[].status_code` | integer |
| `$.macExportRequest._0.externalDailyRecords[].provider` | string |
| `$.macExportRequest._0.externalDailyRecords[].provider_display_name` | string |
| `$.macExportRequest._0.externalDailyRecords[].schema` | string |
| `$.macExportRequest._0.externalDailyRecords[].schema_version` | integer |
| `$.macExportRequest._0.externalDailyRecords[].warnings` | array |
| `$.macExportRequest._0.externalDailyRecords[].warnings[]` | string |
| `$.macExportRequest._0.jobID` | string |
| `$.macExportRequest._0.records` | array |
| `$.macExportRequest._0.records[]` | object |
| `$.macExportRequest._0.records[].activity` | object |
| `$.macExportRequest._0.records[].body` | object |
| `$.macExportRequest._0.records[].cyclingPerformance` | object |
| `$.macExportRequest._0.records[].date` | integer |
| `$.macExportRequest._0.records[].healthKitRecordArchive` | object |
| `$.macExportRequest._0.records[].healthKitRecordArchive.captureStatus` | string |
| `$.macExportRequest._0.records[].healthKitRecordArchive.dailyOwnership` | object |
| `$.macExportRequest._0.records[].healthKitRecordArchive.dailyOwnership.assignmentRule` | string |
| `$.macExportRequest._0.records[].healthKitRecordArchive.dailyOwnership.calendarIdentifier` | string |
| `$.macExportRequest._0.records[].healthKitRecordArchive.dailyOwnership.calendarTimeZoneIdentifier` | string |
| `$.macExportRequest._0.records[].healthKitRecordArchive.dailyOwnership.intervalEnd` | integer |
| `$.macExportRequest._0.records[].healthKitRecordArchive.dailyOwnership.intervalStart` | integer |
| `$.macExportRequest._0.records[].healthKitRecordArchive.dailyOwnership.ownerDate` | string |
| `$.macExportRequest._0.records[].healthKitRecordArchive.externalRecords` | array |
| `$.macExportRequest._0.records[].healthKitRecordArchive.integrityWarnings` | array |
| `$.macExportRequest._0.records[].healthKitRecordArchive.integrityWarnings[]` | object |
| `$.macExportRequest._0.records[].healthKitRecordArchive.integrityWarnings[].code` | string |
| `$.macExportRequest._0.records[].healthKitRecordArchive.integrityWarnings[].message` | string |
| `$.macExportRequest._0.records[].healthKitRecordArchive.integrityWarnings[].metricIDs` | array |
| `$.macExportRequest._0.records[].healthKitRecordArchive.integrityWarnings[].metricIDs[]` | string |
| `$.macExportRequest._0.records[].healthKitRecordArchive.integrityWarnings[].recordUUIDs` | array |
| `$.macExportRequest._0.records[].healthKitRecordArchive.medicationInventoryRecords` | array |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest` | object |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results` | array |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[]` | object |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[].error` | object |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[].error.code` | integer |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[].error.description` | string |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[].error.domain` | string |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[].error.isRecoverable` | boolean |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[].identifier` | string |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[].interval` | object |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[].interval.endDate` | integer |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[].interval.startDate` | integer |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[].metricIDs` | array |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[].metricIDs[]` | string |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[].objectTypeIdentifier` | string |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[].operation` | string |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[].recordCount` | integer |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[].status` | string |
| `$.macExportRequest._0.records[].healthKitRecordArchive.queryManifest.results[].statusDescription` | string |
| `$.macExportRequest._0.records[].healthKitRecordArchive.recordSchemaVersion` | integer |
| `$.macExportRequest._0.records[].healthKitRecordArchive.records` | array |
| `$.macExportRequest._0.records[].healthKitRecordArchive.schemaIdentifier` | string |
| `$.macExportRequest._0.records[].healthKitRecordCaptureStatus` | string |
| `$.macExportRequest._0.records[].hearing` | object |
| `$.macExportRequest._0.records[].heart` | object |
| `$.macExportRequest._0.records[].heart.heartRateSamples` | array |
| `$.macExportRequest._0.records[].heart.hrvSamples` | array |
| `$.macExportRequest._0.records[].mindfulness` | object |
| `$.macExportRequest._0.records[].mindfulness.stateOfMind` | array |
| `$.macExportRequest._0.records[].minerals` | object |
| `$.macExportRequest._0.records[].mobility` | object |
| `$.macExportRequest._0.records[].nutrition` | object |
| `$.macExportRequest._0.records[].other` | object |
| `$.macExportRequest._0.records[].partialFailures` | array |
| `$.macExportRequest._0.records[].partialFailures[]` | object |
| `$.macExportRequest._0.records[].partialFailures[].dataType` | string |
| `$.macExportRequest._0.records[].partialFailures[].date` | integer |
| `$.macExportRequest._0.records[].partialFailures[].dateRangeDescription` | string |
| `$.macExportRequest._0.records[].partialFailures[].errorDescription` | string |
| `$.macExportRequest._0.records[].reproductiveHealth` | object |
| `$.macExportRequest._0.records[].sleep` | object |
| `$.macExportRequest._0.records[].sleep.awakeTime` | integer |
| `$.macExportRequest._0.records[].sleep.coreSleep` | integer |
| `$.macExportRequest._0.records[].sleep.deepSleep` | integer |
| `$.macExportRequest._0.records[].sleep.inBedTime` | integer |
| `$.macExportRequest._0.records[].sleep.remSleep` | integer |
| `$.macExportRequest._0.records[].sleep.stages` | array |
| `$.macExportRequest._0.records[].sleep.totalDuration` | integer |
| `$.macExportRequest._0.records[].symptoms` | object |
| `$.macExportRequest._0.records[].symptoms.counts` | object |
| `$.macExportRequest._0.records[].symptoms.samples` | array |
| `$.macExportRequest._0.records[].timeContext` | object |
| `$.macExportRequest._0.records[].timeContext.calendarTimeZoneIdentifier` | string |
| `$.macExportRequest._0.records[].vitals` | object |
| `$.macExportRequest._0.records[].vitals.bloodGlucoseSamples` | array |
| `$.macExportRequest._0.records[].vitals.bloodOxygenSamples` | array |
| `$.macExportRequest._0.records[].vitals.bloodPressureSamples` | array |
| `$.macExportRequest._0.records[].vitals.respiratoryRateSamples` | array |
| `$.macExportRequest._0.records[].vitamins` | object |
| `$.macExportRequest._0.records[].workouts` | array |
| `$.macExportRequest._0.requestedDates` | array |
| `$.macExportRequest._0.requestedDates[]` | integer |
| `$.macExportRequest._0.requestedTarget` | object |
| `$.macExportRequest._0.requestedTarget.destinationDisplayName` | string |
| `$.macExportRequest._0.requestedTarget.displayName` | string |
| `$.macExportRequest._0.requestedTarget.kind` | string |
| `$.macExportRequest._0.settingsSnapshot` | object |
| `$.macExportRequest._0.settingsSnapshot.archiveExportFiles` | boolean |
| `$.macExportRequest._0.settingsSnapshot.dailyNoteInjection` | object |
| `$.macExportRequest._0.settingsSnapshot.dailyNoteInjection.createIfMissing` | boolean |
| `$.macExportRequest._0.settingsSnapshot.dailyNoteInjection.dailyNotesOnly` | boolean |
| `$.macExportRequest._0.settingsSnapshot.dailyNoteInjection.enabled` | boolean |
| `$.macExportRequest._0.settingsSnapshot.dailyNoteInjection.filenamePattern` | string |
| `$.macExportRequest._0.settingsSnapshot.dailyNoteInjection.folderPath` | string |
| `$.macExportRequest._0.settingsSnapshot.dailyNoteInjection.injectMarkdownSections` | boolean |
| `$.macExportRequest._0.settingsSnapshot.exportFormats` | array |
| `$.macExportRequest._0.settingsSnapshot.exportFormats[]` | string |
| `$.macExportRequest._0.settingsSnapshot.filenameFormat` | string |
| `$.macExportRequest._0.settingsSnapshot.folderStructure` | string |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization` | object |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.dateFormat` | string |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.frontmatterConfig` | object |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.frontmatterConfig.customDateKey` | string |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.frontmatterConfig.customFields` | object |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.frontmatterConfig.customTypeKey` | string |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.frontmatterConfig.customTypeValue` | string |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.frontmatterConfig.fields` | array |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.frontmatterConfig.fields[]` | object |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.frontmatterConfig.fields[].customKey` | string |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.frontmatterConfig.fields[].isEnabled` | boolean |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.frontmatterConfig.fields[].originalKey` | string |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.frontmatterConfig.includeDate` | boolean |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.frontmatterConfig.includeType` | boolean |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.frontmatterConfig.keyStyle` | string |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.frontmatterConfig.placeholderFields` | array |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.markdownTemplate` | object |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.markdownTemplate.bulletStyle` | string |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.markdownTemplate.customTemplate` | string |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.markdownTemplate.includeSummary` | boolean |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.markdownTemplate.sectionHeaderLevel` | integer |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.markdownTemplate.style` | string |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.markdownTemplate.useEmoji` | boolean |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.timeFormat` | string |
| `$.macExportRequest._0.settingsSnapshot.formatCustomization.unitPreference` | string |
| `$.macExportRequest._0.settingsSnapshot.generateMonthlyRollups` | boolean |
| `$.macExportRequest._0.settingsSnapshot.generateWeeklyRollups` | boolean |
| `$.macExportRequest._0.settingsSnapshot.generateYearlyRollups` | boolean |
| `$.macExportRequest._0.settingsSnapshot.groupByCategory` | boolean |
| `$.macExportRequest._0.settingsSnapshot.healthSubfolder` | string |
| `$.macExportRequest._0.settingsSnapshot.includeGranularData` | boolean |
| `$.macExportRequest._0.settingsSnapshot.includeMetadata` | boolean |
| `$.macExportRequest._0.settingsSnapshot.individualTracking` | object |
| `$.macExportRequest._0.settingsSnapshot.individualTracking.entriesFolder` | string |
| `$.macExportRequest._0.settingsSnapshot.individualTracking.filenameTemplate` | string |
| `$.macExportRequest._0.settingsSnapshot.individualTracking.globalEnabled` | boolean |
| `$.macExportRequest._0.settingsSnapshot.individualTracking.metricConfigs` | object |
| `$.macExportRequest._0.settingsSnapshot.individualTracking.useCategoryFolders` | boolean |
| `$.macExportRequest._0.settingsSnapshot.metricSelection` | object |
| `$.macExportRequest._0.settingsSnapshot.metricSelection.enabledCategoryIDs` | array |
| `$.macExportRequest._0.settingsSnapshot.metricSelection.enabledCategoryIDs[]` | string |
| `$.macExportRequest._0.settingsSnapshot.metricSelection.enabledMetricIDs` | array |
| `$.macExportRequest._0.settingsSnapshot.metricSelection.enabledMetricIDs[]` | string |
| `$.macExportRequest._0.settingsSnapshot.organizeFormatsIntoFolders` | boolean |
| `$.macExportRequest._0.settingsSnapshot.summaryOnlyExport` | boolean |
| `$.macExportRequest._0.settingsSnapshot.writeMode` | string |
| `$.macExportRequest._0.sourceDeviceName` | string |

### `macExportResult`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.macExportResult` | object |
| `$.macExportResult._0` | object |
| `$.macExportResult._0.completedAt` | integer |
| `$.macExportResult._0.completedDates` | array |
| `$.macExportResult._0.completedDates[]` | integer |
| `$.macExportResult._0.dailyNoteSkipCount` | integer |
| `$.macExportResult._0.dailyNoteUpdateCount` | integer |
| `$.macExportResult._0.destinationDisplayName` | string |
| `$.macExportResult._0.destinationPathForDisplay` | string |
| `$.macExportResult._0.externalRecordFileCount` | integer |
| `$.macExportResult._0.failedDateDetails` | array |
| `$.macExportResult._0.failedDateDetails[]` | object |
| `$.macExportResult._0.failedDateDetails[].date` | integer |
| `$.macExportResult._0.failedDateDetails[].errorDetails` | string |
| `$.macExportResult._0.failedDateDetails[].reason` | string |
| `$.macExportResult._0.formatsPerDate` | integer |
| `$.macExportResult._0.jobID` | string |
| `$.macExportResult._0.status` | string |
| `$.macExportResult._0.successCount` | integer |
| `$.macExportResult._0.totalCount` | integer |
| `$.macExportResult._0.totalFilesWritten` | integer |

### `macExportStreamAbort`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.macExportStreamAbort` | object |
| `$.macExportStreamAbort._0` | object |
| `$.macExportStreamAbort._0.jobID` | string |
| `$.macExportStreamAbort._0.message` | string |
| `$.macExportStreamAbort._0.reason` | string |

### `macExportStreamChunk`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.macExportStreamChunk` | object |
| `$.macExportStreamChunk._0` | object |
| `$.macExportStreamChunk._0.externalDailyRecords` | array |
| `$.macExportStreamChunk._0.externalDailyRecords[]` | object |
| `$.macExportStreamChunk._0.externalDailyRecords[].date` | string |
| `$.macExportStreamChunk._0.externalDailyRecords[].fetched_at` | integer |
| `$.macExportStreamChunk._0.externalDailyRecords[].payloads` | array |
| `$.macExportStreamChunk._0.externalDailyRecords[].payloads[]` | object |
| `$.macExportStreamChunk._0.externalDailyRecords[].payloads[].data` | object |
| `$.macExportStreamChunk._0.externalDailyRecords[].payloads[].data.fixture_id` | string |
| `$.macExportStreamChunk._0.externalDailyRecords[].payloads[].data.score` | number |
| `$.macExportStreamChunk._0.externalDailyRecords[].payloads[].data.synthetic` | boolean |
| `$.macExportStreamChunk._0.externalDailyRecords[].payloads[].endpoint` | string |
| `$.macExportStreamChunk._0.externalDailyRecords[].payloads[].fetched_at` | integer |
| `$.macExportStreamChunk._0.externalDailyRecords[].payloads[].name` | string |
| `$.macExportStreamChunk._0.externalDailyRecords[].payloads[].status_code` | integer |
| `$.macExportStreamChunk._0.externalDailyRecords[].provider` | string |
| `$.macExportStreamChunk._0.externalDailyRecords[].provider_display_name` | string |
| `$.macExportStreamChunk._0.externalDailyRecords[].schema` | string |
| `$.macExportStreamChunk._0.externalDailyRecords[].schema_version` | integer |
| `$.macExportStreamChunk._0.externalDailyRecords[].warnings` | array |
| `$.macExportStreamChunk._0.externalDailyRecords[].warnings[]` | string |
| `$.macExportStreamChunk._0.jobID` | string |
| `$.macExportStreamChunk._0.processedTransferDays` | integer |
| `$.macExportStreamChunk._0.records` | array |
| `$.macExportStreamChunk._0.records[]` | object |
| `$.macExportStreamChunk._0.records[].activity` | object |
| `$.macExportStreamChunk._0.records[].body` | object |
| `$.macExportStreamChunk._0.records[].cyclingPerformance` | object |
| `$.macExportStreamChunk._0.records[].date` | integer |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive` | object |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.captureStatus` | string |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.dailyOwnership` | object |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.dailyOwnership.assignmentRule` | string |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.dailyOwnership.calendarIdentifier` | string |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.dailyOwnership.calendarTimeZoneIdentifier` | string |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.dailyOwnership.intervalEnd` | integer |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.dailyOwnership.intervalStart` | integer |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.dailyOwnership.ownerDate` | string |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.externalRecords` | array |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.integrityWarnings` | array |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.medicationInventoryRecords` | array |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.queryManifest` | object |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.queryManifest.results` | array |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.queryManifest.results[]` | object |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.queryManifest.results[].identifier` | string |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.queryManifest.results[].interval` | object |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.queryManifest.results[].interval.endDate` | integer |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.queryManifest.results[].interval.startDate` | integer |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.queryManifest.results[].metricIDs` | array |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.queryManifest.results[].metricIDs[]` | string |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.queryManifest.results[].objectTypeIdentifier` | string |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.queryManifest.results[].operation` | string |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.queryManifest.results[].recordCount` | integer |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.queryManifest.results[].status` | string |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.queryManifest.results[].statusDescription` | string |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.recordSchemaVersion` | integer |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.records` | array |
| `$.macExportStreamChunk._0.records[].healthKitRecordArchive.schemaIdentifier` | string |
| `$.macExportStreamChunk._0.records[].healthKitRecordCaptureStatus` | string |
| `$.macExportStreamChunk._0.records[].hearing` | object |
| `$.macExportStreamChunk._0.records[].heart` | object |
| `$.macExportStreamChunk._0.records[].heart.heartRateSamples` | array |
| `$.macExportStreamChunk._0.records[].heart.hrvSamples` | array |
| `$.macExportStreamChunk._0.records[].mindfulness` | object |
| `$.macExportStreamChunk._0.records[].mindfulness.stateOfMind` | array |
| `$.macExportStreamChunk._0.records[].minerals` | object |
| `$.macExportStreamChunk._0.records[].mobility` | object |
| `$.macExportStreamChunk._0.records[].nutrition` | object |
| `$.macExportStreamChunk._0.records[].other` | object |
| `$.macExportStreamChunk._0.records[].partialFailures` | array |
| `$.macExportStreamChunk._0.records[].reproductiveHealth` | object |
| `$.macExportStreamChunk._0.records[].sleep` | object |
| `$.macExportStreamChunk._0.records[].sleep.awakeTime` | integer |
| `$.macExportStreamChunk._0.records[].sleep.coreSleep` | integer |
| `$.macExportStreamChunk._0.records[].sleep.deepSleep` | integer |
| `$.macExportStreamChunk._0.records[].sleep.inBedTime` | integer |
| `$.macExportStreamChunk._0.records[].sleep.remSleep` | integer |
| `$.macExportStreamChunk._0.records[].sleep.stages` | array |
| `$.macExportStreamChunk._0.records[].sleep.totalDuration` | integer |
| `$.macExportStreamChunk._0.records[].symptoms` | object |
| `$.macExportStreamChunk._0.records[].symptoms.counts` | object |
| `$.macExportStreamChunk._0.records[].symptoms.samples` | array |
| `$.macExportStreamChunk._0.records[].timeContext` | object |
| `$.macExportStreamChunk._0.records[].timeContext.calendarTimeZoneIdentifier` | string |
| `$.macExportStreamChunk._0.records[].vitals` | object |
| `$.macExportStreamChunk._0.records[].vitals.bloodGlucoseSamples` | array |
| `$.macExportStreamChunk._0.records[].vitals.bloodOxygenSamples` | array |
| `$.macExportStreamChunk._0.records[].vitals.bloodPressureSamples` | array |
| `$.macExportStreamChunk._0.records[].vitals.respiratoryRateSamples` | array |
| `$.macExportStreamChunk._0.records[].vitamins` | object |
| `$.macExportStreamChunk._0.records[].workouts` | array |
| `$.macExportStreamChunk._0.sequence` | integer |
| `$.macExportStreamChunk._0.totalTransferDays` | integer |

### `macExportStreamChunkAck`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.macExportStreamChunkAck` | object |
| `$.macExportStreamChunkAck._0` | object |
| `$.macExportStreamChunkAck._0.accepted` | boolean |
| `$.macExportStreamChunkAck._0.filesWritten` | integer |
| `$.macExportStreamChunkAck._0.jobID` | string |
| `$.macExportStreamChunkAck._0.message` | string |
| `$.macExportStreamChunkAck._0.processedDays` | integer |
| `$.macExportStreamChunkAck._0.sequence` | integer |

### `macExportStreamComplete`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.macExportStreamComplete` | object |
| `$.macExportStreamComplete._0` | object |
| `$.macExportStreamComplete._0.iphoneFailedDateDetails` | array |
| `$.macExportStreamComplete._0.iphoneFailedDateDetails[]` | object |
| `$.macExportStreamComplete._0.iphoneFailedDateDetails[].date` | integer |
| `$.macExportStreamComplete._0.iphoneFailedDateDetails[].errorDetails` | string |
| `$.macExportStreamComplete._0.iphoneFailedDateDetails[].reason` | string |
| `$.macExportStreamComplete._0.jobID` | string |
| `$.macExportStreamComplete._0.totalChunks` | integer |

### `macExportStreamStart`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.macExportStreamStart` | object |
| `$.macExportStreamStart._0` | object |
| `$.macExportStreamStart._0.chunkStrategyVersion` | integer |
| `$.macExportStreamStart._0.createdAt` | integer |
| `$.macExportStreamStart._0.dateRangeEnd` | integer |
| `$.macExportStreamStart._0.dateRangeStart` | integer |
| `$.macExportStreamStart._0.jobID` | string |
| `$.macExportStreamStart._0.requestedDates` | array |
| `$.macExportStreamStart._0.requestedDates[]` | integer |
| `$.macExportStreamStart._0.requestedTarget` | object |
| `$.macExportStreamStart._0.requestedTarget.destinationDisplayName` | string |
| `$.macExportStreamStart._0.requestedTarget.displayName` | string |
| `$.macExportStreamStart._0.requestedTarget.kind` | string |
| `$.macExportStreamStart._0.settingsSnapshot` | object |
| `$.macExportStreamStart._0.settingsSnapshot.archiveExportFiles` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.dailyNoteInjection` | object |
| `$.macExportStreamStart._0.settingsSnapshot.dailyNoteInjection.createIfMissing` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.dailyNoteInjection.dailyNotesOnly` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.dailyNoteInjection.enabled` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.dailyNoteInjection.filenamePattern` | string |
| `$.macExportStreamStart._0.settingsSnapshot.dailyNoteInjection.folderPath` | string |
| `$.macExportStreamStart._0.settingsSnapshot.dailyNoteInjection.injectMarkdownSections` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.exportFormats` | array |
| `$.macExportStreamStart._0.settingsSnapshot.exportFormats[]` | string |
| `$.macExportStreamStart._0.settingsSnapshot.filenameFormat` | string |
| `$.macExportStreamStart._0.settingsSnapshot.folderStructure` | string |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization` | object |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.dateFormat` | string |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.frontmatterConfig` | object |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.frontmatterConfig.customDateKey` | string |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.frontmatterConfig.customFields` | object |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.frontmatterConfig.customTypeKey` | string |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.frontmatterConfig.customTypeValue` | string |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.frontmatterConfig.fields` | array |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.frontmatterConfig.fields[]` | object |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.frontmatterConfig.fields[].customKey` | string |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.frontmatterConfig.fields[].isEnabled` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.frontmatterConfig.fields[].originalKey` | string |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.frontmatterConfig.includeDate` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.frontmatterConfig.includeType` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.frontmatterConfig.keyStyle` | string |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.frontmatterConfig.placeholderFields` | array |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.markdownTemplate` | object |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.markdownTemplate.bulletStyle` | string |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.markdownTemplate.customTemplate` | string |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.markdownTemplate.includeSummary` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.markdownTemplate.sectionHeaderLevel` | integer |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.markdownTemplate.style` | string |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.markdownTemplate.useEmoji` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.timeFormat` | string |
| `$.macExportStreamStart._0.settingsSnapshot.formatCustomization.unitPreference` | string |
| `$.macExportStreamStart._0.settingsSnapshot.generateMonthlyRollups` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.generateWeeklyRollups` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.generateYearlyRollups` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.groupByCategory` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.healthSubfolder` | string |
| `$.macExportStreamStart._0.settingsSnapshot.includeGranularData` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.includeMetadata` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.individualTracking` | object |
| `$.macExportStreamStart._0.settingsSnapshot.individualTracking.entriesFolder` | string |
| `$.macExportStreamStart._0.settingsSnapshot.individualTracking.filenameTemplate` | string |
| `$.macExportStreamStart._0.settingsSnapshot.individualTracking.globalEnabled` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.individualTracking.metricConfigs` | object |
| `$.macExportStreamStart._0.settingsSnapshot.individualTracking.useCategoryFolders` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.metricSelection` | object |
| `$.macExportStreamStart._0.settingsSnapshot.metricSelection.enabledCategoryIDs` | array |
| `$.macExportStreamStart._0.settingsSnapshot.metricSelection.enabledCategoryIDs[]` | string |
| `$.macExportStreamStart._0.settingsSnapshot.metricSelection.enabledMetricIDs` | array |
| `$.macExportStreamStart._0.settingsSnapshot.metricSelection.enabledMetricIDs[]` | string |
| `$.macExportStreamStart._0.settingsSnapshot.organizeFormatsIntoFolders` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.summaryOnlyExport` | boolean |
| `$.macExportStreamStart._0.settingsSnapshot.writeMode` | string |
| `$.macExportStreamStart._0.sourceDeviceName` | string |
| `$.macExportStreamStart._0.totalRequestedDays` | integer |
| `$.macExportStreamStart._0.totalTransferDays` | integer |

### `macStatus`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.macStatus` | object |
| `$.macStatus._0` | object |
| `$.macStatus._0.activeJobID` | string |
| `$.macStatus._0.capabilities` | object |
| `$.macStatus._0.capabilities.appVersion` | string |
| `$.macStatus._0.capabilities.buildNumber` | string |
| `$.macStatus._0.capabilities.canonicalArchiveSchemaVersions` | array |
| `$.macStatus._0.capabilities.canonicalArchiveSchemaVersions[]` | integer |
| `$.macStatus._0.capabilities.canonicalRawResultSchemaVersions` | array |
| `$.macStatus._0.capabilities.canonicalRawResultSchemaVersions[]` | integer |
| `$.macStatus._0.capabilities.connectedCorpusTransferCapabilities` | object |
| `$.macStatus._0.capabilities.connectedCorpusTransferCapabilities.partitionTargetBounds` | object |
| `$.macStatus._0.capabilities.connectedCorpusTransferCapabilities.partitionTargetBounds.maximumBytes` | integer |
| `$.macStatus._0.capabilities.connectedCorpusTransferCapabilities.partitionTargetBounds.minimumBytes` | integer |
| `$.macStatus._0.capabilities.connectedCorpusTransferCapabilities.partitionTargetBounds.preferredBytes` | integer |
| `$.macStatus._0.capabilities.connectedCorpusTransferCapabilities.protocolVersions` | array |
| `$.macStatus._0.capabilities.connectedCorpusTransferCapabilities.protocolVersions[]` | integer |
| `$.macStatus._0.capabilities.connectedTransferBinaryFrameVersions` | array |
| `$.macStatus._0.capabilities.connectedTransferMaximumInFlightChunks` | integer |
| `$.macStatus._0.capabilities.installationID` | string |
| `$.macStatus._0.capabilities.manualIPSyncRequiresPairing` | boolean |
| `$.macStatus._0.capabilities.platform` | string |
| `$.macStatus._0.capabilities.protocolVersion` | integer |
| `$.macStatus._0.capabilities.supportsAllAvailableHistoryExportRequests` | boolean |
| `$.macStatus._0.capabilities.supportsCanonicalHealthDataSelection` | boolean |
| `$.macStatus._0.capabilities.supportsChunkedMacExportJobs` | boolean |
| `$.macStatus._0.capabilities.supportsDailyNoteOnlyExports` | boolean |
| `$.macStatus._0.capabilities.supportsDurableConnectedExportRecovery` | boolean |
| `$.macStatus._0.capabilities.supportsGranularPayloads` | boolean |
| `$.macStatus._0.capabilities.supportsIPhoneExportRequests` | boolean |
| `$.macStatus._0.capabilities.supportsJobCancellation` | boolean |
| `$.macStatus._0.capabilities.supportsMacDestinationStatus` | boolean |
| `$.macStatus._0.capabilities.supportsMacExportJobs` | boolean |
| `$.macStatus._0.capabilities.supportsManualIPSync` | boolean |
| `$.macStatus._0.capabilities.supportsPartitionedConnectedExports` | boolean |
| `$.macStatus._0.capabilities.supportsPerDateExportCompletion` | boolean |
| `$.macStatus._0.capabilities.supportsRequestScopedContextAcquisition` | boolean |
| `$.macStatus._0.capabilities.supportsRollupSummaries` | boolean |
| `$.macStatus._0.capabilities.supportsSizeBoundedConnectedTransfers` | boolean |
| `$.macStatus._0.capabilities.supportsStrictRawStreaming` | boolean |
| `$.macStatus._0.capabilities.supportsSummaryOnlyExports` | boolean |
| `$.macStatus._0.destinationDisplayName` | string |
| `$.macStatus._0.destinationFolderSelected` | boolean |
| `$.macStatus._0.destinationPathForDisplay` | string |
| `$.macStatus._0.folderAccessHealthy` | boolean |
| `$.macStatus._0.isConnected` | boolean |
| `$.macStatus._0.isReadyForExports` | boolean |
| `$.macStatus._0.lastError` | string |

### `ping`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.ping` | object |

### `pong`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.pong` | object |

### `requestAllData`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.requestAllData` | object |

### `requestData`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.requestData` | object |
| `$.requestData.dates` | array |
| `$.requestData.dates[]` | integer |

### `syncProgress`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.syncProgress` | object |
| `$.syncProgress._0` | object |
| `$.syncProgress._0.isComplete` | boolean |
| `$.syncProgress._0.message` | string |
| `$.syncProgress._0.processedDays` | integer |
| `$.syncProgress._0.recordsInBatch` | integer |
| `$.syncProgress._0.totalDays` | integer |

## Generated JSON artifact inventory

### `agent-evidence-response.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.coverage` | object |
| `$.coverage.available_range` | object |
| `$.coverage.available_range.end_date` | string |
| `$.coverage.available_range.start_date` | string |
| `$.coverage.days_considered` | integer |
| `$.coverage.days_with_values` | integer |
| `$.coverage.missing` | array |
| `$.coverage.missing[]` | object |
| `$.coverage.missing[].range` | object |
| `$.coverage.missing[].range.end_date` | string |
| `$.coverage.missing[].range.start_date` | string |
| `$.coverage.missing[].reason` | string |
| `$.coverage.missing[].status` | string |
| `$.coverage.requested_range` | object |
| `$.coverage.requested_range.end_date` | string |
| `$.coverage.requested_range.start_date` | string |
| `$.coverage.status` | string |
| `$.evidence` | array |
| `$.evidence[]` | object |
| `$.evidence[].evidence_id` | string |
| `$.evidence[].locator` | object |
| `$.evidence[].locator.owner_date` | string |
| `$.evidence[].locator.type` | string |
| `$.evidence[].locator.uuid` | string |
| `$.evidence[].source` | object |
| `$.evidence[].source.digest` | string |
| `$.evidence[].source.schema` | string |
| `$.evidence[].source.schema_version` | integer |
| `$.evidence[].source_id` | string |
| `$.items` | array |
| `$.limitations` | array |
| `$.limitations[]` | object |
| `$.limitations[].code` | string |
| `$.limitations[].message` | string |
| `$.packet` | object |
| `$.packet.coverage` | object |
| `$.packet.coverage.available_range` | object |
| `$.packet.coverage.available_range.end_date` | string |
| `$.packet.coverage.available_range.start_date` | string |
| `$.packet.coverage.days_considered` | integer |
| `$.packet.coverage.days_with_values` | integer |
| `$.packet.coverage.missing` | array |
| `$.packet.coverage.missing[]` | object |
| `$.packet.coverage.missing[].range` | object |
| `$.packet.coverage.missing[].range.end_date` | string |
| `$.packet.coverage.missing[].range.start_date` | string |
| `$.packet.coverage.missing[].reason` | string |
| `$.packet.coverage.missing[].status` | string |
| `$.packet.coverage.requested_range` | object |
| `$.packet.coverage.requested_range.end_date` | string |
| `$.packet.coverage.requested_range.start_date` | string |
| `$.packet.coverage.status` | string |
| `$.packet.facts` | array |
| `$.packet.facts[]` | object |
| `$.packet.facts[].evidence` | array |
| `$.packet.facts[].evidence[]` | object |
| `$.packet.facts[].evidence[].evidence_id` | string |
| `$.packet.facts[].evidence[].locator` | object |
| `$.packet.facts[].evidence[].locator.owner_date` | string |
| `$.packet.facts[].evidence[].locator.type` | string |
| `$.packet.facts[].evidence[].locator.uuid` | string |
| `$.packet.facts[].evidence[].source` | object |
| `$.packet.facts[].evidence[].source.digest` | string |
| `$.packet.facts[].evidence[].source.schema` | string |
| `$.packet.facts[].evidence[].source.schema_version` | integer |
| `$.packet.facts[].evidence[].source_id` | string |
| `$.packet.facts[].fact_id` | string |
| `$.packet.facts[].label` | string |
| `$.packet.facts[].owner_date` | string |
| `$.packet.facts[].value` | object |
| `$.packet.facts[].value.type` | string |
| `$.packet.facts[].value.value` | integer |
| `$.packet.kind` | string |
| `$.packet.limitations` | array |
| `$.packet.limitations[]` | object |
| `$.packet.limitations[].code` | string |
| `$.packet.limitations[].message` | string |
| `$.packet.metadata` | object |
| `$.packet.metadata.generated_at` | string |
| `$.packet.metadata.producer` | string |
| `$.packet.packet_id` | string |
| `$.packet.range` | object |
| `$.packet.range.end_date` | string |
| `$.packet.range.start_date` | string |
| `$.packet.schema` | string |
| `$.packet.schema_version` | integer |
| `$.packet.sources` | array |
| `$.packet.sources[]` | object |
| `$.packet.sources[].digest` | string |
| `$.packet.sources[].schema` | string |
| `$.packet.sources[].schema_version` | integer |
| `$.schema` | string |
| `$.schema_version` | integer |
| `$.sources` | array |
| `$.sources[]` | object |
| `$.sources[].digest` | string |
| `$.sources[].schema` | string |
| `$.sources[].schema_version` | integer |

### `agent-query-request.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.dates` | object |
| `$.dates.range` | object |
| `$.dates.range.end_date` | string |
| `$.dates.range.start_date` | string |
| `$.dates.type` | string |
| `$.metrics` | object |
| `$.metrics.metric_ids` | array |
| `$.metrics.metric_ids[]` | string |
| `$.metrics.type` | string |
| `$.operation` | object |
| `$.operation.type` | string |
| `$.page` | object |
| `$.page.max_bytes` | integer |
| `$.page.max_items` | integer |
| `$.schema` | string |
| `$.schema_version` | integer |
| `$.sources` | object |
| `$.sources.type` | string |

### `agent-query-response.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.coverage` | object |
| `$.coverage.available_range` | object |
| `$.coverage.available_range.end_date` | string |
| `$.coverage.available_range.start_date` | string |
| `$.coverage.days_considered` | integer |
| `$.coverage.days_with_values` | integer |
| `$.coverage.missing` | array |
| `$.coverage.missing[]` | object |
| `$.coverage.missing[].range` | object |
| `$.coverage.missing[].range.end_date` | string |
| `$.coverage.missing[].range.start_date` | string |
| `$.coverage.missing[].reason` | string |
| `$.coverage.missing[].status` | string |
| `$.coverage.requested_range` | object |
| `$.coverage.requested_range.end_date` | string |
| `$.coverage.requested_range.start_date` | string |
| `$.coverage.status` | string |
| `$.evidence` | array |
| `$.evidence[]` | object |
| `$.evidence[].evidence_id` | string |
| `$.evidence[].locator` | object |
| `$.evidence[].locator.owner_date` | string |
| `$.evidence[].locator.type` | string |
| `$.evidence[].locator.uuid` | string |
| `$.evidence[].source` | object |
| `$.evidence[].source.digest` | string |
| `$.evidence[].source.schema` | string |
| `$.evidence[].source.schema_version` | integer |
| `$.evidence[].source_id` | string |
| `$.items` | array |
| `$.items[]` | object |
| `$.items[].metric` | object |
| `$.items[].metric.display_name` | string |
| `$.items[].metric.evidence` | array |
| `$.items[].metric.evidence[]` | object |
| `$.items[].metric.evidence[].evidence_id` | string |
| `$.items[].metric.evidence[].locator` | object |
| `$.items[].metric.evidence[].locator.owner_date` | string |
| `$.items[].metric.evidence[].locator.type` | string |
| `$.items[].metric.evidence[].locator.uuid` | string |
| `$.items[].metric.evidence[].source` | object |
| `$.items[].metric.evidence[].source.digest` | string |
| `$.items[].metric.evidence[].source.schema` | string |
| `$.items[].metric.evidence[].source.schema_version` | integer |
| `$.items[].metric.evidence[].source_id` | string |
| `$.items[].metric.limitations` | array |
| `$.items[].metric.metric_id` | string |
| `$.items[].metric.owner_date` | string |
| `$.items[].metric.status` | string |
| `$.items[].metric.value` | object |
| `$.items[].metric.value.type` | string |
| `$.items[].metric.value.value` | integer |
| `$.items[].type` | string |
| `$.limitations` | array |
| `$.next_cursor` | string |
| `$.schema` | string |
| `$.schema_version` | integer |
| `$.sources` | array |
| `$.sources[]` | object |
| `$.sources[].digest` | string |
| `$.sources[].schema` | string |
| `$.sources[].schema_version` | integer |

### `api-export-v1.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.daily_record_schema` | string |
| `$.daily_record_schema_version` | integer |
| `$.date_range` | object |
| `$.date_range.end` | string |
| `$.date_range.start` | string |
| `$.exported_at` | string |
| `$.failed_date_details` | array |
| `$.failed_date_details[]` | object |
| `$.failed_date_details[].date` | string |
| `$.failed_date_details[].errorDetails` | string |
| `$.failed_date_details[].reason` | string |
| `$.record_count` | integer |
| `$.records` | array |
| `$.records[]` | object |
| `$.records[].date` | string |
| `$.records[].healthkit_record_archive` | object |
| `$.records[].healthkit_record_archive.capture_status` | string |
| `$.records[].healthkit_record_archive.integrity_warnings` | array |
| `$.records[].healthkit_record_archive.medication_inventory` | array |
| `$.records[].healthkit_record_archive.ownership` | object |
| `$.records[].healthkit_record_archive.ownership.assignment_rule` | string |
| `$.records[].healthkit_record_archive.ownership.calendar_identifier` | string |
| `$.records[].healthkit_record_archive.ownership.calendar_timezone_identifier` | string |
| `$.records[].healthkit_record_archive.ownership.interval_end` | string |
| `$.records[].healthkit_record_archive.ownership.interval_start` | string |
| `$.records[].healthkit_record_archive.ownership.owner_date` | string |
| `$.records[].healthkit_record_archive.query_manifest` | object |
| `$.records[].healthkit_record_archive.query_manifest.results` | array |
| `$.records[].healthkit_record_archive.query_manifest.results[]` | object |
| `$.records[].healthkit_record_archive.query_manifest.results[].identifier` | string |
| `$.records[].healthkit_record_archive.query_manifest.results[].interval` | object |
| `$.records[].healthkit_record_archive.query_manifest.results[].interval.end_date` | string |
| `$.records[].healthkit_record_archive.query_manifest.results[].interval.start_date` | string |
| `$.records[].healthkit_record_archive.query_manifest.results[].metric_ids` | array |
| `$.records[].healthkit_record_archive.query_manifest.results[].metric_ids[]` | string |
| `$.records[].healthkit_record_archive.query_manifest.results[].object_type_identifier` | string |
| `$.records[].healthkit_record_archive.query_manifest.results[].operation` | string |
| `$.records[].healthkit_record_archive.query_manifest.results[].record_count` | integer |
| `$.records[].healthkit_record_archive.query_manifest.results[].status` | string |
| `$.records[].healthkit_record_archive.query_manifest.results[].status_description` | string |
| `$.records[].healthkit_record_archive.records` | array |
| `$.records[].healthkit_record_archive.schema` | string |
| `$.records[].healthkit_record_archive.schema_version` | integer |
| `$.records[].raw_capture_status` | string |
| `$.records[].schema` | string |
| `$.records[].schema_version` | integer |
| `$.records[].time_context` | object |
| `$.records[].time_context.calendar_timezone` | string |
| `$.records[].time_context.timestamp_timezone` | string |
| `$.records[].type` | string |
| `$.records[].unit_system` | string |
| `$.records[].units` | object |
| `$.schema` | string |
| `$.schema_version` | integer |
| `$.source` | string |

### `api-export-v2-provider-sidecar.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.daily_record_schema` | string |
| `$.daily_record_schema_version` | integer |
| `$.date_range` | object |
| `$.date_range.end` | string |
| `$.date_range.start` | string |
| `$.exported_at` | string |
| `$.external_record_count` | integer |
| `$.external_record_schema` | string |
| `$.external_record_schema_version` | integer |
| `$.external_records` | array |
| `$.external_records[]` | object |
| `$.external_records[].date` | string |
| `$.external_records[].fetched_at` | string |
| `$.external_records[].payloads` | array |
| `$.external_records[].payloads[]` | object |
| `$.external_records[].payloads[].data` | object |
| `$.external_records[].payloads[].data.fixture_id` | string |
| `$.external_records[].payloads[].data.score` | number |
| `$.external_records[].payloads[].data.synthetic` | boolean |
| `$.external_records[].payloads[].endpoint` | string |
| `$.external_records[].payloads[].fetched_at` | string |
| `$.external_records[].payloads[].name` | string |
| `$.external_records[].payloads[].status_code` | integer |
| `$.external_records[].provider` | string |
| `$.external_records[].provider_display_name` | string |
| `$.external_records[].schema` | string |
| `$.external_records[].schema_version` | integer |
| `$.external_records[].warnings` | array |
| `$.external_records[].warnings[]` | string |
| `$.failed_date_details` | array |
| `$.failed_date_details[]` | object |
| `$.failed_date_details[].date` | string |
| `$.failed_date_details[].errorDetails` | string |
| `$.failed_date_details[].reason` | string |
| `$.record_count` | integer |
| `$.records` | array |
| `$.records[]` | object |
| `$.records[].date` | string |
| `$.records[].healthkit_record_archive` | object |
| `$.records[].healthkit_record_archive.capture_status` | string |
| `$.records[].healthkit_record_archive.integrity_warnings` | array |
| `$.records[].healthkit_record_archive.medication_inventory` | array |
| `$.records[].healthkit_record_archive.ownership` | object |
| `$.records[].healthkit_record_archive.ownership.assignment_rule` | string |
| `$.records[].healthkit_record_archive.ownership.calendar_identifier` | string |
| `$.records[].healthkit_record_archive.ownership.calendar_timezone_identifier` | string |
| `$.records[].healthkit_record_archive.ownership.interval_end` | string |
| `$.records[].healthkit_record_archive.ownership.interval_start` | string |
| `$.records[].healthkit_record_archive.ownership.owner_date` | string |
| `$.records[].healthkit_record_archive.query_manifest` | object |
| `$.records[].healthkit_record_archive.query_manifest.results` | array |
| `$.records[].healthkit_record_archive.query_manifest.results[]` | object |
| `$.records[].healthkit_record_archive.query_manifest.results[].identifier` | string |
| `$.records[].healthkit_record_archive.query_manifest.results[].interval` | object |
| `$.records[].healthkit_record_archive.query_manifest.results[].interval.end_date` | string |
| `$.records[].healthkit_record_archive.query_manifest.results[].interval.start_date` | string |
| `$.records[].healthkit_record_archive.query_manifest.results[].metric_ids` | array |
| `$.records[].healthkit_record_archive.query_manifest.results[].metric_ids[]` | string |
| `$.records[].healthkit_record_archive.query_manifest.results[].object_type_identifier` | string |
| `$.records[].healthkit_record_archive.query_manifest.results[].operation` | string |
| `$.records[].healthkit_record_archive.query_manifest.results[].record_count` | integer |
| `$.records[].healthkit_record_archive.query_manifest.results[].status` | string |
| `$.records[].healthkit_record_archive.query_manifest.results[].status_description` | string |
| `$.records[].healthkit_record_archive.records` | array |
| `$.records[].healthkit_record_archive.schema` | string |
| `$.records[].healthkit_record_archive.schema_version` | integer |
| `$.records[].raw_capture_status` | string |
| `$.records[].schema` | string |
| `$.records[].schema_version` | integer |
| `$.records[].time_context` | object |
| `$.records[].time_context.calendar_timezone` | string |
| `$.records[].time_context.timestamp_timezone` | string |
| `$.records[].type` | string |
| `$.records[].unit_system` | string |
| `$.records[].units` | object |
| `$.schema` | string |
| `$.schema_version` | integer |
| `$.source` | string |

### `control-export-response-cancelled.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.destination_display_name` | string |
| `$.destination_path` | string |
| `$.external_record_count` | integer |
| `$.failure_reason` | string |
| `$.files_written` | integer |
| `$.job_id` | string |
| `$.message` | string |
| `$.status` | string |
| `$.success_count` | integer |
| `$.total_count` | integer |

### `control-export-response-failure.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.destination_display_name` | string |
| `$.destination_path` | string |
| `$.external_record_count` | integer |
| `$.failure_reason` | string |
| `$.files_written` | integer |
| `$.job_id` | string |
| `$.message` | string |
| `$.status` | string |
| `$.success_count` | integer |
| `$.total_count` | integer |

### `control-export-response-partial-success.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.destination_display_name` | string |
| `$.destination_path` | string |
| `$.external_record_count` | integer |
| `$.failure_reason` | string |
| `$.files_written` | integer |
| `$.job_id` | string |
| `$.message` | string |
| `$.status` | string |
| `$.success_count` | integer |
| `$.total_count` | integer |

### `control-export-response-success.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.committed_bytes` | integer |
| `$.committed_partitions` | integer |
| `$.destination_display_name` | string |
| `$.destination_path` | string |
| `$.durable` | boolean |
| `$.expires_at` | string |
| `$.external_record_count` | integer |
| `$.files_written` | integer |
| `$.fraction_complete` | integer |
| `$.job_id` | string |
| `$.message` | string |
| `$.paused` | boolean |
| `$.processed_days` | integer |
| `$.session_id` | string |
| `$.state` | string |
| `$.status` | string |
| `$.success_count` | integer |
| `$.total_count` | integer |

### `control-export-response-timed-out.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.failure_reason` | string |
| `$.job_id` | string |
| `$.message` | string |
| `$.status` | string |

### `control-export-response-unavailable.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.failure_reason` | string |
| `$.message` | string |
| `$.status` | string |

### `control-status.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.active_export` | object |
| `$.active_export.committed_bytes` | integer |
| `$.active_export.committed_partitions` | integer |
| `$.active_export.durable` | boolean |
| `$.active_export.expires_at` | string |
| `$.active_export.fraction_complete` | number |
| `$.active_export.job_id` | string |
| `$.active_export.message` | string |
| `$.active_export.paused` | boolean |
| `$.active_export.processed_days` | integer |
| `$.active_export.session_id` | string |
| `$.active_export.state` | string |
| `$.active_export.total_days` | integer |
| `$.destination` | object |
| `$.destination.display_name` | string |
| `$.destination.path` | string |
| `$.destination.selected` | boolean |
| `$.destination.writable` | boolean |
| `$.iphone` | object |
| `$.iphone.can_trigger_exports` | boolean |
| `$.iphone.can_trigger_raw_exports` | boolean |
| `$.iphone.connected` | boolean |
| `$.iphone.name` | string |
| `$.mac_app` | string |

### `control-strict-raw-request.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.date_range` | object |
| `$.date_range.end` | string |
| `$.date_range.start` | string |
| `$.raw_profile` | string |
| `$.response_mode` | string |
| `$.settings_policy` | string |
| `$.source` | string |
| `$.wait_timeout_seconds` | integer |

### `control-write-files-request.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.date_range` | object |
| `$.date_range.end` | string |
| `$.date_range.start` | string |
| `$.response_mode` | string |
| `$.settings_policy` | string |
| `$.source` | string |
| `$.wait_timeout_seconds` | integer |

### `iphone-export-progress.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.currentDate` | integer |
| `$.jobID` | string |
| `$.message` | string |
| `$.processedDays` | integer |
| `$.totalDays` | integer |

### `iphone-export-request-strict-raw.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.createdAt` | integer |
| `$.dateRangeEnd` | integer |
| `$.dateRangeStart` | integer |
| `$.dateSelection` | string |
| `$.jobID` | string |
| `$.rawProfile` | string |
| `$.requestedBy` | string |
| `$.responseMode` | string |
| `$.settingsPolicy` | string |

### `iphone-export-request-write-files.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.canonicalSelection` | object |
| `$.canonicalSelection.detail_level` | string |
| `$.canonicalSelection.field_pointers` | array |
| `$.canonicalSelection.metric_ids` | array |
| `$.canonicalSelection.metric_ids[]` | string |
| `$.canonicalSelection.object_paths` | array |
| `$.canonicalSelection.source_ids` | array |
| `$.canonicalSelection.source_ids[]` | string |
| `$.createdAt` | integer |
| `$.dateRangeEnd` | integer |
| `$.dateRangeStart` | integer |
| `$.dateSelection` | string |
| `$.jobID` | string |
| `$.requestedBy` | string |
| `$.responseMode` | string |
| `$.settingsPolicy` | string |

### `mac-export-job.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.createdAt` | integer |
| `$.dateRangeEnd` | integer |
| `$.dateRangeStart` | integer |
| `$.externalDailyRecords` | array |
| `$.externalDailyRecords[]` | object |
| `$.externalDailyRecords[].date` | string |
| `$.externalDailyRecords[].fetched_at` | integer |
| `$.externalDailyRecords[].payloads` | array |
| `$.externalDailyRecords[].payloads[]` | object |
| `$.externalDailyRecords[].payloads[].data` | object |
| `$.externalDailyRecords[].payloads[].data.fixture_id` | string |
| `$.externalDailyRecords[].payloads[].data.score` | number |
| `$.externalDailyRecords[].payloads[].data.synthetic` | boolean |
| `$.externalDailyRecords[].payloads[].endpoint` | string |
| `$.externalDailyRecords[].payloads[].fetched_at` | integer |
| `$.externalDailyRecords[].payloads[].name` | string |
| `$.externalDailyRecords[].payloads[].status_code` | integer |
| `$.externalDailyRecords[].provider` | string |
| `$.externalDailyRecords[].provider_display_name` | string |
| `$.externalDailyRecords[].schema` | string |
| `$.externalDailyRecords[].schema_version` | integer |
| `$.externalDailyRecords[].warnings` | array |
| `$.externalDailyRecords[].warnings[]` | string |
| `$.jobID` | string |
| `$.records` | array |
| `$.records[]` | object |
| `$.records[].activity` | object |
| `$.records[].body` | object |
| `$.records[].cyclingPerformance` | object |
| `$.records[].date` | integer |
| `$.records[].healthKitRecordArchive` | object |
| `$.records[].healthKitRecordArchive.captureStatus` | string |
| `$.records[].healthKitRecordArchive.dailyOwnership` | object |
| `$.records[].healthKitRecordArchive.dailyOwnership.assignmentRule` | string |
| `$.records[].healthKitRecordArchive.dailyOwnership.calendarIdentifier` | string |
| `$.records[].healthKitRecordArchive.dailyOwnership.calendarTimeZoneIdentifier` | string |
| `$.records[].healthKitRecordArchive.dailyOwnership.intervalEnd` | integer |
| `$.records[].healthKitRecordArchive.dailyOwnership.intervalStart` | integer |
| `$.records[].healthKitRecordArchive.dailyOwnership.ownerDate` | string |
| `$.records[].healthKitRecordArchive.externalRecords` | array |
| `$.records[].healthKitRecordArchive.integrityWarnings` | array |
| `$.records[].healthKitRecordArchive.integrityWarnings[]` | object |
| `$.records[].healthKitRecordArchive.integrityWarnings[].code` | string |
| `$.records[].healthKitRecordArchive.integrityWarnings[].message` | string |
| `$.records[].healthKitRecordArchive.integrityWarnings[].metricIDs` | array |
| `$.records[].healthKitRecordArchive.integrityWarnings[].metricIDs[]` | string |
| `$.records[].healthKitRecordArchive.integrityWarnings[].recordUUIDs` | array |
| `$.records[].healthKitRecordArchive.medicationInventoryRecords` | array |
| `$.records[].healthKitRecordArchive.queryManifest` | object |
| `$.records[].healthKitRecordArchive.queryManifest.results` | array |
| `$.records[].healthKitRecordArchive.queryManifest.results[]` | object |
| `$.records[].healthKitRecordArchive.queryManifest.results[].error` | object |
| `$.records[].healthKitRecordArchive.queryManifest.results[].error.code` | integer |
| `$.records[].healthKitRecordArchive.queryManifest.results[].error.description` | string |
| `$.records[].healthKitRecordArchive.queryManifest.results[].error.domain` | string |
| `$.records[].healthKitRecordArchive.queryManifest.results[].error.isRecoverable` | boolean |
| `$.records[].healthKitRecordArchive.queryManifest.results[].identifier` | string |
| `$.records[].healthKitRecordArchive.queryManifest.results[].interval` | object |
| `$.records[].healthKitRecordArchive.queryManifest.results[].interval.endDate` | integer |
| `$.records[].healthKitRecordArchive.queryManifest.results[].interval.startDate` | integer |
| `$.records[].healthKitRecordArchive.queryManifest.results[].metricIDs` | array |
| `$.records[].healthKitRecordArchive.queryManifest.results[].metricIDs[]` | string |
| `$.records[].healthKitRecordArchive.queryManifest.results[].objectTypeIdentifier` | string |
| `$.records[].healthKitRecordArchive.queryManifest.results[].operation` | string |
| `$.records[].healthKitRecordArchive.queryManifest.results[].recordCount` | integer |
| `$.records[].healthKitRecordArchive.queryManifest.results[].status` | string |
| `$.records[].healthKitRecordArchive.queryManifest.results[].statusDescription` | string |
| `$.records[].healthKitRecordArchive.recordSchemaVersion` | integer |
| `$.records[].healthKitRecordArchive.records` | array |
| `$.records[].healthKitRecordArchive.schemaIdentifier` | string |
| `$.records[].healthKitRecordCaptureStatus` | string |
| `$.records[].hearing` | object |
| `$.records[].heart` | object |
| `$.records[].heart.heartRateSamples` | array |
| `$.records[].heart.hrvSamples` | array |
| `$.records[].mindfulness` | object |
| `$.records[].mindfulness.stateOfMind` | array |
| `$.records[].minerals` | object |
| `$.records[].mobility` | object |
| `$.records[].nutrition` | object |
| `$.records[].other` | object |
| `$.records[].partialFailures` | array |
| `$.records[].partialFailures[]` | object |
| `$.records[].partialFailures[].dataType` | string |
| `$.records[].partialFailures[].date` | integer |
| `$.records[].partialFailures[].dateRangeDescription` | string |
| `$.records[].partialFailures[].errorDescription` | string |
| `$.records[].reproductiveHealth` | object |
| `$.records[].sleep` | object |
| `$.records[].sleep.awakeTime` | integer |
| `$.records[].sleep.coreSleep` | integer |
| `$.records[].sleep.deepSleep` | integer |
| `$.records[].sleep.inBedTime` | integer |
| `$.records[].sleep.remSleep` | integer |
| `$.records[].sleep.stages` | array |
| `$.records[].sleep.totalDuration` | integer |
| `$.records[].symptoms` | object |
| `$.records[].symptoms.counts` | object |
| `$.records[].symptoms.samples` | array |
| `$.records[].timeContext` | object |
| `$.records[].timeContext.calendarTimeZoneIdentifier` | string |
| `$.records[].vitals` | object |
| `$.records[].vitals.bloodGlucoseSamples` | array |
| `$.records[].vitals.bloodOxygenSamples` | array |
| `$.records[].vitals.bloodPressureSamples` | array |
| `$.records[].vitals.respiratoryRateSamples` | array |
| `$.records[].vitamins` | object |
| `$.records[].workouts` | array |
| `$.requestedDates` | array |
| `$.requestedDates[]` | integer |
| `$.requestedTarget` | object |
| `$.requestedTarget.destinationDisplayName` | string |
| `$.requestedTarget.displayName` | string |
| `$.requestedTarget.kind` | string |
| `$.settingsSnapshot` | object |
| `$.settingsSnapshot.archiveExportFiles` | boolean |
| `$.settingsSnapshot.dailyNoteInjection` | object |
| `$.settingsSnapshot.dailyNoteInjection.createIfMissing` | boolean |
| `$.settingsSnapshot.dailyNoteInjection.dailyNotesOnly` | boolean |
| `$.settingsSnapshot.dailyNoteInjection.enabled` | boolean |
| `$.settingsSnapshot.dailyNoteInjection.filenamePattern` | string |
| `$.settingsSnapshot.dailyNoteInjection.folderPath` | string |
| `$.settingsSnapshot.dailyNoteInjection.injectMarkdownSections` | boolean |
| `$.settingsSnapshot.exportFormats` | array |
| `$.settingsSnapshot.exportFormats[]` | string |
| `$.settingsSnapshot.filenameFormat` | string |
| `$.settingsSnapshot.folderStructure` | string |
| `$.settingsSnapshot.formatCustomization` | object |
| `$.settingsSnapshot.formatCustomization.dateFormat` | string |
| `$.settingsSnapshot.formatCustomization.frontmatterConfig` | object |
| `$.settingsSnapshot.formatCustomization.frontmatterConfig.customDateKey` | string |
| `$.settingsSnapshot.formatCustomization.frontmatterConfig.customFields` | object |
| `$.settingsSnapshot.formatCustomization.frontmatterConfig.customTypeKey` | string |
| `$.settingsSnapshot.formatCustomization.frontmatterConfig.customTypeValue` | string |
| `$.settingsSnapshot.formatCustomization.frontmatterConfig.fields` | array |
| `$.settingsSnapshot.formatCustomization.frontmatterConfig.fields[]` | object |
| `$.settingsSnapshot.formatCustomization.frontmatterConfig.fields[].customKey` | string |
| `$.settingsSnapshot.formatCustomization.frontmatterConfig.fields[].isEnabled` | boolean |
| `$.settingsSnapshot.formatCustomization.frontmatterConfig.fields[].originalKey` | string |
| `$.settingsSnapshot.formatCustomization.frontmatterConfig.includeDate` | boolean |
| `$.settingsSnapshot.formatCustomization.frontmatterConfig.includeType` | boolean |
| `$.settingsSnapshot.formatCustomization.frontmatterConfig.keyStyle` | string |
| `$.settingsSnapshot.formatCustomization.frontmatterConfig.placeholderFields` | array |
| `$.settingsSnapshot.formatCustomization.markdownTemplate` | object |
| `$.settingsSnapshot.formatCustomization.markdownTemplate.bulletStyle` | string |
| `$.settingsSnapshot.formatCustomization.markdownTemplate.customTemplate` | string |
| `$.settingsSnapshot.formatCustomization.markdownTemplate.includeSummary` | boolean |
| `$.settingsSnapshot.formatCustomization.markdownTemplate.sectionHeaderLevel` | integer |
| `$.settingsSnapshot.formatCustomization.markdownTemplate.style` | string |
| `$.settingsSnapshot.formatCustomization.markdownTemplate.useEmoji` | boolean |
| `$.settingsSnapshot.formatCustomization.timeFormat` | string |
| `$.settingsSnapshot.formatCustomization.unitPreference` | string |
| `$.settingsSnapshot.generateMonthlyRollups` | boolean |
| `$.settingsSnapshot.generateWeeklyRollups` | boolean |
| `$.settingsSnapshot.generateYearlyRollups` | boolean |
| `$.settingsSnapshot.groupByCategory` | boolean |
| `$.settingsSnapshot.healthSubfolder` | string |
| `$.settingsSnapshot.includeGranularData` | boolean |
| `$.settingsSnapshot.includeMetadata` | boolean |
| `$.settingsSnapshot.individualTracking` | object |
| `$.settingsSnapshot.individualTracking.entriesFolder` | string |
| `$.settingsSnapshot.individualTracking.filenameTemplate` | string |
| `$.settingsSnapshot.individualTracking.globalEnabled` | boolean |
| `$.settingsSnapshot.individualTracking.metricConfigs` | object |
| `$.settingsSnapshot.individualTracking.useCategoryFolders` | boolean |
| `$.settingsSnapshot.metricSelection` | object |
| `$.settingsSnapshot.metricSelection.enabledCategoryIDs` | array |
| `$.settingsSnapshot.metricSelection.enabledCategoryIDs[]` | string |
| `$.settingsSnapshot.metricSelection.enabledMetricIDs` | array |
| `$.settingsSnapshot.metricSelection.enabledMetricIDs[]` | string |
| `$.settingsSnapshot.organizeFormatsIntoFolders` | boolean |
| `$.settingsSnapshot.summaryOnlyExport` | boolean |
| `$.settingsSnapshot.writeMode` | string |
| `$.sourceDeviceName` | string |

### `mac-export-result-partial.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.completedAt` | integer |
| `$.completedDates` | array |
| `$.completedDates[]` | integer |
| `$.dailyNoteSkipCount` | integer |
| `$.dailyNoteUpdateCount` | integer |
| `$.destinationDisplayName` | string |
| `$.destinationPathForDisplay` | string |
| `$.externalRecordFileCount` | integer |
| `$.failedDateDetails` | array |
| `$.failedDateDetails[]` | object |
| `$.failedDateDetails[].date` | integer |
| `$.failedDateDetails[].errorDetails` | string |
| `$.failedDateDetails[].reason` | string |
| `$.formatsPerDate` | integer |
| `$.jobID` | string |
| `$.status` | string |
| `$.successCount` | integer |
| `$.totalCount` | integer |
| `$.totalFilesWritten` | integer |

### `mac-export-result-success.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.completedAt` | integer |
| `$.completedDates` | array |
| `$.completedDates[]` | integer |
| `$.dailyNoteSkipCount` | integer |
| `$.dailyNoteUpdateCount` | integer |
| `$.destinationDisplayName` | string |
| `$.destinationPathForDisplay` | string |
| `$.externalRecordFileCount` | integer |
| `$.failedDateDetails` | array |
| `$.formatsPerDate` | integer |
| `$.jobID` | string |
| `$.status` | string |
| `$.successCount` | integer |
| `$.totalCount` | integer |
| `$.totalFilesWritten` | integer |

### `peer-capabilities.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.appVersion` | string |
| `$.buildNumber` | string |
| `$.canonicalArchiveSchemaVersions` | array |
| `$.canonicalArchiveSchemaVersions[]` | integer |
| `$.canonicalRawResultSchemaVersions` | array |
| `$.canonicalRawResultSchemaVersions[]` | integer |
| `$.connectedCorpusTransferCapabilities` | object |
| `$.connectedCorpusTransferCapabilities.partitionTargetBounds` | object |
| `$.connectedCorpusTransferCapabilities.partitionTargetBounds.maximumBytes` | integer |
| `$.connectedCorpusTransferCapabilities.partitionTargetBounds.minimumBytes` | integer |
| `$.connectedCorpusTransferCapabilities.partitionTargetBounds.preferredBytes` | integer |
| `$.connectedCorpusTransferCapabilities.protocolVersions` | array |
| `$.connectedCorpusTransferCapabilities.protocolVersions[]` | integer |
| `$.connectedTransferBinaryFrameVersions` | array |
| `$.connectedTransferMaximumInFlightChunks` | integer |
| `$.installationID` | string |
| `$.manualIPSyncRequiresPairing` | boolean |
| `$.platform` | string |
| `$.protocolVersion` | integer |
| `$.supportsAllAvailableHistoryExportRequests` | boolean |
| `$.supportsCanonicalHealthDataSelection` | boolean |
| `$.supportsChunkedMacExportJobs` | boolean |
| `$.supportsDailyNoteOnlyExports` | boolean |
| `$.supportsDurableConnectedExportRecovery` | boolean |
| `$.supportsGranularPayloads` | boolean |
| `$.supportsIPhoneExportRequests` | boolean |
| `$.supportsJobCancellation` | boolean |
| `$.supportsMacDestinationStatus` | boolean |
| `$.supportsMacExportJobs` | boolean |
| `$.supportsManualIPSync` | boolean |
| `$.supportsPartitionedConnectedExports` | boolean |
| `$.supportsPerDateExportCompletion` | boolean |
| `$.supportsRequestScopedContextAcquisition` | boolean |
| `$.supportsRollupSummaries` | boolean |
| `$.supportsSizeBoundedConnectedTransfers` | boolean |
| `$.supportsStrictRawStreaming` | boolean |
| `$.supportsSummaryOnlyExports` | boolean |

### `raw-result-complete.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.capture_summary` | object |
| `$.capture_summary.cancelled_day_count` | integer |
| `$.capture_summary.complete_day_count` | integer |
| `$.capture_summary.complete_empty_day_count` | integer |
| `$.capture_summary.day_status_counts` | object |
| `$.capture_summary.day_status_counts.complete_empty` | integer |
| `$.capture_summary.failed_day_count` | integer |
| `$.capture_summary.integrity_warning_count` | integer |
| `$.capture_summary.missing_day_count` | integer |
| `$.capture_summary.partial_day_count` | integer |
| `$.capture_summary.partial_failure_count` | integer |
| `$.capture_summary.query_status_counts` | object |
| `$.capture_summary.query_status_counts.cancelled` | integer |
| `$.capture_summary.query_status_counts.failure` | integer |
| `$.capture_summary.query_status_counts.skipped` | integer |
| `$.capture_summary.query_status_counts.success` | integer |
| `$.capture_summary.query_status_counts.unsupported` | integer |
| `$.capture_summary.record_count` | integer |
| `$.capture_summary.retained_day_count` | integer |
| `$.capture_summary.sample_count` | integer |
| `$.capture_summary.warning_day_count` | integer |
| `$.created_at` | string |
| `$.date_range` | object |
| `$.date_range.end` | string |
| `$.date_range.start` | string |
| `$.days` | array |
| `$.days[]` | object |
| `$.days[].capture_status` | string |
| `$.days[].date` | string |
| `$.days[].health_data` | object |
| `$.days[].health_data.date` | string |
| `$.days[].health_data.healthkit_record_archive` | object |
| `$.days[].health_data.healthkit_record_archive.capture_status` | string |
| `$.days[].health_data.healthkit_record_archive.integrity_warnings` | array |
| `$.days[].health_data.healthkit_record_archive.medication_inventory` | array |
| `$.days[].health_data.healthkit_record_archive.ownership` | object |
| `$.days[].health_data.healthkit_record_archive.ownership.assignment_rule` | string |
| `$.days[].health_data.healthkit_record_archive.ownership.calendar_identifier` | string |
| `$.days[].health_data.healthkit_record_archive.ownership.calendar_timezone_identifier` | string |
| `$.days[].health_data.healthkit_record_archive.ownership.interval_end` | string |
| `$.days[].health_data.healthkit_record_archive.ownership.interval_start` | string |
| `$.days[].health_data.healthkit_record_archive.ownership.owner_date` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest` | object |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results` | array |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[]` | object |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].identifier` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].interval` | object |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].interval.end_date` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].interval.start_date` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].metric_ids` | array |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].metric_ids[]` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].object_type_identifier` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].operation` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].record_count` | integer |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].status` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].status_description` | string |
| `$.days[].health_data.healthkit_record_archive.records` | array |
| `$.days[].health_data.healthkit_record_archive.schema` | string |
| `$.days[].health_data.healthkit_record_archive.schema_version` | integer |
| `$.days[].health_data.raw_capture_status` | string |
| `$.days[].health_data.schema` | string |
| `$.days[].health_data.schema_version` | integer |
| `$.days[].health_data.time_context` | object |
| `$.days[].health_data.time_context.calendar_timezone` | string |
| `$.days[].health_data.time_context.timestamp_timezone` | string |
| `$.days[].health_data.type` | string |
| `$.days[].health_data.unit_system` | string |
| `$.days[].health_data.units` | object |
| `$.days[].integrity_warning_codes` | array |
| `$.days[].integrity_warning_count` | integer |
| `$.days[].partial_failure_count` | integer |
| `$.days[].partial_failure_types` | array |
| `$.days[].query_status_counts` | object |
| `$.days[].query_status_counts.cancelled` | integer |
| `$.days[].query_status_counts.failure` | integer |
| `$.days[].query_status_counts.skipped` | integer |
| `$.days[].query_status_counts.success` | integer |
| `$.days[].query_status_counts.unsupported` | integer |
| `$.days[].record_count` | integer |
| `$.days[].sample_count` | integer |
| `$.days[].status` | string |
| `$.missing_dates` | array |
| `$.profile` | string |
| `$.schema` | string |
| `$.schema_version` | integer |
| `$.source_device_name` | string |
| `$.total_requested_days` | integer |

### `raw-result-partial.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.capture_summary` | object |
| `$.capture_summary.cancelled_day_count` | integer |
| `$.capture_summary.complete_day_count` | integer |
| `$.capture_summary.complete_empty_day_count` | integer |
| `$.capture_summary.day_status_counts` | object |
| `$.capture_summary.day_status_counts.missing` | integer |
| `$.capture_summary.day_status_counts.partial` | integer |
| `$.capture_summary.failed_day_count` | integer |
| `$.capture_summary.integrity_warning_count` | integer |
| `$.capture_summary.missing_day_count` | integer |
| `$.capture_summary.partial_day_count` | integer |
| `$.capture_summary.partial_failure_count` | integer |
| `$.capture_summary.query_status_counts` | object |
| `$.capture_summary.query_status_counts.cancelled` | integer |
| `$.capture_summary.query_status_counts.failure` | integer |
| `$.capture_summary.query_status_counts.skipped` | integer |
| `$.capture_summary.query_status_counts.success` | integer |
| `$.capture_summary.query_status_counts.unsupported` | integer |
| `$.capture_summary.record_count` | integer |
| `$.capture_summary.retained_day_count` | integer |
| `$.capture_summary.sample_count` | integer |
| `$.capture_summary.warning_day_count` | integer |
| `$.created_at` | string |
| `$.date_range` | object |
| `$.date_range.end` | string |
| `$.date_range.start` | string |
| `$.days` | array |
| `$.days[]` | object |
| `$.days[].capture_status` | string |
| `$.days[].date` | string |
| `$.days[].failure_code` | string |
| `$.days[].health_data` | object |
| `$.days[].health_data.date` | string |
| `$.days[].health_data.diagnostics` | object |
| `$.days[].health_data.diagnostics.partial_failures` | array |
| `$.days[].health_data.diagnostics.partial_failures[]` | object |
| `$.days[].health_data.diagnostics.partial_failures[].data_type` | string |
| `$.days[].health_data.diagnostics.partial_failures[].date` | string |
| `$.days[].health_data.diagnostics.partial_failures[].date_range_description` | string |
| `$.days[].health_data.diagnostics.partial_failures[].error_description` | string |
| `$.days[].health_data.healthkit_record_archive` | object |
| `$.days[].health_data.healthkit_record_archive.capture_status` | string |
| `$.days[].health_data.healthkit_record_archive.integrity_warnings` | array |
| `$.days[].health_data.healthkit_record_archive.integrity_warnings[]` | object |
| `$.days[].health_data.healthkit_record_archive.integrity_warnings[].code` | string |
| `$.days[].health_data.healthkit_record_archive.integrity_warnings[].message` | string |
| `$.days[].health_data.healthkit_record_archive.integrity_warnings[].metric_ids` | array |
| `$.days[].health_data.healthkit_record_archive.integrity_warnings[].metric_ids[]` | string |
| `$.days[].health_data.healthkit_record_archive.integrity_warnings[].record_uuids` | array |
| `$.days[].health_data.healthkit_record_archive.medication_inventory` | array |
| `$.days[].health_data.healthkit_record_archive.ownership` | object |
| `$.days[].health_data.healthkit_record_archive.ownership.assignment_rule` | string |
| `$.days[].health_data.healthkit_record_archive.ownership.calendar_identifier` | string |
| `$.days[].health_data.healthkit_record_archive.ownership.calendar_timezone_identifier` | string |
| `$.days[].health_data.healthkit_record_archive.ownership.interval_end` | string |
| `$.days[].health_data.healthkit_record_archive.ownership.interval_start` | string |
| `$.days[].health_data.healthkit_record_archive.ownership.owner_date` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest` | object |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results` | array |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[]` | object |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].error` | object |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].error.code` | integer |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].error.description` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].error.domain` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].error.is_recoverable` | boolean |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].identifier` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].interval` | object |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].interval.end_date` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].interval.start_date` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].metric_ids` | array |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].metric_ids[]` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].object_type_identifier` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].operation` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].record_count` | integer |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].status` | string |
| `$.days[].health_data.healthkit_record_archive.query_manifest.results[].status_description` | string |
| `$.days[].health_data.healthkit_record_archive.records` | array |
| `$.days[].health_data.healthkit_record_archive.schema` | string |
| `$.days[].health_data.healthkit_record_archive.schema_version` | integer |
| `$.days[].health_data.raw_capture_status` | string |
| `$.days[].health_data.schema` | string |
| `$.days[].health_data.schema_version` | integer |
| `$.days[].health_data.time_context` | object |
| `$.days[].health_data.time_context.calendar_timezone` | string |
| `$.days[].health_data.time_context.timestamp_timezone` | string |
| `$.days[].health_data.type` | string |
| `$.days[].health_data.unit_system` | string |
| `$.days[].health_data.units` | object |
| `$.days[].integrity_warning_codes` | array |
| `$.days[].integrity_warning_codes[]` | string |
| `$.days[].integrity_warning_count` | integer |
| `$.days[].partial_failure_count` | integer |
| `$.days[].partial_failure_types` | array |
| `$.days[].partial_failure_types[]` | string |
| `$.days[].query_status_counts` | object |
| `$.days[].query_status_counts.cancelled` | integer |
| `$.days[].query_status_counts.failure` | integer |
| `$.days[].query_status_counts.skipped` | integer |
| `$.days[].query_status_counts.success` | integer |
| `$.days[].query_status_counts.unsupported` | integer |
| `$.days[].record_count` | integer |
| `$.days[].sample_count` | integer |
| `$.days[].status` | string |
| `$.missing_dates` | array |
| `$.missing_dates[]` | string |
| `$.profile` | string |
| `$.schema` | string |
| `$.schema_version` | integer |
| `$.source_device_name` | string |
| `$.total_requested_days` | integer |

### `transfer-acknowledgement.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.accepted` | boolean |
| `$.message` | string |
| `$.sequence` | integer |
| `$.sha256` | string |
| `$.transferID` | string |

### `transfer-chunk.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.data` | string |
| `$.sequence` | integer |
| `$.sha256` | string |
| `$.transferID` | string |

### `transfer-complete.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.sha256` | string |
| `$.totalBytes` | integer |
| `$.totalChunks` | integer |
| `$.transferID` | string |

### `transfer-offer.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.chunkBytes` | integer |
| `$.manifest` | object |
| `$.manifest.jobID` | string |
| `$.manifest.kind` | string |
| `$.manifest.payloadSchemaVersion` | integer |
| `$.protocolVersion` | integer |
| `$.sha256` | string |
| `$.totalBytes` | integer |
| `$.totalChunks` | integer |
| `$.transferID` | string |

### `transfer-rejection.json`

| JSON path | Observed type or types |
|---|---|
| `$` | object |
| `$.jobID` | string |
| `$.message` | string |
| `$.reason` | string |
| `$.transferID` | string |
