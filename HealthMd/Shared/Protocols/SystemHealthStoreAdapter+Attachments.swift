import Foundation
@preconcurrency import HealthKit

extension SystemHealthStoreAdapter {
    private struct AttachmentParentOutcome: Sendable {
        var records: [HealthKitExternalRecord] = []
        var parentRelationships: [HealthKitAttachmentParentRelationship] = []
        var queryResults: [HealthKitQueryResult] = []
        var integrityWarnings: [HealthKitRecordIntegrityWarning] = []
    }

    /// One bounded, deterministic sweep over every retained HKObject parent.
    /// The original objects are passed through query result values; this code
    /// never reconstructs a HealthKit parent from archive fields.
    func queryAttachmentRecords(
        parents: [HealthKitAttachmentParentReference],
        interval: HealthKitQueryInterval
    ) async -> HealthKitAttachmentQueryResult {
        let uniqueParents = Self.mergedAttachmentParents(parents)
        guard !uniqueParents.isEmpty else { return HealthKitAttachmentQueryResult() }

        guard #available(iOS 16.0, macOS 13.0, macCatalyst 16.0, watchOS 9.0, visionOS 1.0, *) else {
            let results = uniqueParents.map { parent in
                HealthKitQueryResult(
                    identifier: "\(parent.parentUUID.uuidString):attachments",
                    objectTypeIdentifier: parent.objectTypeIdentifier,
                    operation: "queryAttachmentMetadata",
                    metricIDs: parent.metricAttribution?.metricIDs ?? [],
                    metricAttribution: parent.metricAttribution,
                    interval: interval,
                    status: .unsupported,
                    recordCount: 0,
                    statusDescription: "HKAttachmentStore is unavailable on this OS version."
                )
            }
            return HealthKitAttachmentQueryResult(queryResults: results)
        }

        // Four parent graphs may query/download at once. Attachments within one
        // parent stream serially to avoid unbounded file and iCloud pressure.
        let concurrencyLimit = 4
        var outcomes: [AttachmentParentOutcome] = []
        var lowerBound = 0
        while lowerBound < uniqueParents.count {
            let upperBound = min(lowerBound + concurrencyLimit, uniqueParents.count)
            let batch = Array(uniqueParents[lowerBound..<upperBound])
            await withTaskGroup(of: AttachmentParentOutcome.self) { group in
                for parent in batch {
                    group.addTask { [self] in
                        await attachmentOutcome(for: parent, interval: interval)
                    }
                }
                for await outcome in group {
                    outcomes.append(outcome)
                }
            }
            lowerBound = upperBound
        }

        let rawQueryResults = outcomes.flatMap(\.queryResults)
        let failedResults = rawQueryResults.filter { $0.status != .success }
        let successfulResults = rawQueryResults.filter { $0.status == .success }
        let groupedSuccesses = Dictionary(grouping: successfulResults) { result in
            [result.objectTypeIdentifier ?? "HKAttachment"] + result.metricIDs.sorted()
        }
        let aggregatedSuccesses = groupedSuccesses.values.compactMap { results -> HealthKitQueryResult? in
            guard let first = results.first else { return nil }
            let objectTypeIdentifier = first.objectTypeIdentifier ?? "HKAttachment"
            return HealthKitQueryResult(
                identifier: "attachments:\(objectTypeIdentifier)",
                objectTypeIdentifier: objectTypeIdentifier,
                operation: "queryAttachmentMetadata",
                metricIDs: first.metricIDs,
                metricAttribution: first.metricAttribution,
                interval: interval,
                status: .success,
                recordCount: results.reduce(0) { $0 + $1.recordCount },
                statusDescription: "parent_query_count=\(results.count)"
            )
        }

        return HealthKitAttachmentQueryResult(
            records: outcomes.flatMap(\.records),
            parentRelationships: outcomes.flatMap(\.parentRelationships),
            queryResults: failedResults + aggregatedSuccesses,
            integrityWarnings: outcomes.flatMap(\.integrityWarnings)
        )
    }

    private static func mergedAttachmentParents(
        _ parents: [HealthKitAttachmentParentReference]
    ) -> [HealthKitAttachmentParentReference] {
        var byUUID: [UUID: HealthKitAttachmentParentReference] = [:]
        for parent in parents.sorted(by: {
            if $0.objectTypeIdentifier != $1.objectTypeIdentifier {
                return $0.objectTypeIdentifier < $1.objectTypeIdentifier
            }
            return $0.parentUUID.uuidString < $1.parentUUID.uuidString
        }) {
            guard let existing = byUUID[parent.parentUUID] else {
                byUUID[parent.parentUUID] = parent
                continue
            }
            let left = existing.metricAttribution ?? HealthKitMetricAttribution()
            let right = parent.metricAttribution ?? HealthKitMetricAttribution()
            byUUID[parent.parentUUID] = HealthKitAttachmentParentReference(
                parentUUID: parent.parentUUID,
                objectTypeIdentifier: min(existing.objectTypeIdentifier, parent.objectTypeIdentifier),
                sourceObject: existing.sourceObject ?? parent.sourceObject,
                metricAttribution: HealthKitMetricAttribution(
                    directMetricIDs: left.directMetricIDs + right.directMetricIDs,
                    dependencyMetricIDs: left.dependencyMetricIDs + right.dependencyMetricIDs
                )
            )
        }
        return byUUID.values.sorted {
            if $0.objectTypeIdentifier != $1.objectTypeIdentifier {
                return $0.objectTypeIdentifier < $1.objectTypeIdentifier
            }
            return $0.parentUUID.uuidString < $1.parentUUID.uuidString
        }
    }

    @available(iOS 16.0, macOS 13.0, macCatalyst 16.0, watchOS 9.0, visionOS 1.0, *)
    private func attachmentOutcome(
        for parent: HealthKitAttachmentParentReference,
        interval: HealthKitQueryInterval
    ) async -> AttachmentParentOutcome {
        let attribution = parent.metricAttribution ?? HealthKitMetricAttribution()
        guard let sourceObject = parent.sourceObject else {
            let error = HealthKitQueryError(
                domain: "HealthMd.HealthKitAttachmentCapture",
                code: 1,
                description: "The original HealthKit parent object was unavailable for attachment capture.",
                isRecoverable: true
            )
            return AttachmentParentOutcome(
                queryResults: [HealthKitQueryResult(
                    identifier: "\(parent.parentUUID.uuidString):attachments",
                    objectTypeIdentifier: parent.objectTypeIdentifier,
                    operation: "queryAttachmentMetadata",
                    metricIDs: attribution.metricIDs,
                    metricAttribution: attribution,
                    interval: interval,
                    status: .failure,
                    recordCount: 0,
                    error: error
                )],
                integrityWarnings: [HealthKitRecordIntegrityWarning(
                    code: "attachment_parent_object_unavailable",
                    message: "The retained parent could not be passed to HKAttachmentStore; no attachment metadata was omitted silently.",
                    metricIDs: attribution.metricIDs,
                    recordUUIDs: [parent.parentUUID]
                )]
            )
        }

        let attachmentStore = HKAttachmentStore(healthStore: store)
        let attachments: [HKAttachment]
        do {
            attachments = try await attachmentStore.attachments(for: sourceObject)
        } catch {
            let nsError = error as NSError
            return AttachmentParentOutcome(
                queryResults: [HealthKitQueryResult(
                    identifier: "\(parent.parentUUID.uuidString):attachments",
                    objectTypeIdentifier: parent.objectTypeIdentifier,
                    operation: "queryAttachmentMetadata",
                    metricIDs: attribution.metricIDs,
                    metricAttribution: attribution,
                    interval: interval,
                    status: Self.isCancellationError(error) ? .cancelled : .failure,
                    recordCount: 0,
                    error: HealthKitQueryError(error: nsError, isRecoverable: true)
                )],
                integrityWarnings: [HealthKitRecordIntegrityWarning(
                    code: "attachment_metadata_unavailable",
                    message: "HKAttachmentStore could not return attachment metadata for a retained parent.",
                    metricIDs: attribution.metricIDs,
                    recordUUIDs: [parent.parentUUID]
                )]
            )
        }

        var outcome = AttachmentParentOutcome(queryResults: [HealthKitQueryResult(
            identifier: "\(parent.parentUUID.uuidString):attachments",
            objectTypeIdentifier: parent.objectTypeIdentifier,
            operation: "queryAttachmentMetadata",
            metricIDs: attribution.metricIDs,
            metricAttribution: attribution,
            interval: interval,
            status: .success,
            recordCount: attachments.count
        )])

        for attachment in attachments.sorted(by: { $0.identifier.uuidString < $1.identifier.uuidString }) {
            var exactData: Data?
            var checksum: String?
            do {
                var streamed = Data()
                if attachment.size > 0 { streamed.reserveCapacity(attachment.size) }
                let reader = attachmentStore.dataReader(for: attachment)
                for try await byte in reader.bytes {
                    streamed.append(byte)
                }
                // Empty Data is intentionally successful and receives the checksum
                // of the empty byte sequence.
                exactData = streamed
                checksum = ClinicalDocumentVisionHealthKitRecordMapper.sha256Hex(streamed)
                if streamed.count != attachment.size {
                    outcome.integrityWarnings.append(HealthKitRecordIntegrityWarning(
                        code: "attachment_size_mismatch",
                        message: "The streamed attachment byte count did not match public HKAttachment.size; exact streamed bytes were retained.",
                        metricIDs: attribution.metricIDs,
                        recordUUIDs: [parent.parentUUID]
                    ))
                }
            } catch {
                let nsError = error as NSError
                outcome.queryResults.append(HealthKitQueryResult(
                    identifier: "\(parent.parentUUID.uuidString):attachment:\(attachment.identifier.uuidString):data",
                    objectTypeIdentifier: parent.objectTypeIdentifier,
                    operation: "streamAttachmentData",
                    metricIDs: attribution.metricIDs,
                    metricAttribution: attribution,
                    interval: interval,
                    status: Self.isCancellationError(error) ? .cancelled : .failure,
                    recordCount: 0,
                    error: HealthKitQueryError(error: nsError, isRecoverable: true)
                ))
                outcome.integrityWarnings.append(HealthKitRecordIntegrityWarning(
                    code: "attachment_data_unavailable",
                    message: "Attachment metadata was retained, but HKAttachmentStore could not stream the attachment bytes.",
                    metricIDs: attribution.metricIDs,
                    recordUUIDs: [parent.parentUUID]
                ))
            }

            let value = HealthKitAttachmentValue(
                identifier: attachment.identifier,
                filename: attachment.name,
                uniformTypeIdentifier: attachment.contentType.identifier,
                byteCount: Int64(attachment.size),
                creationDate: attachment.creationDate,
                metadata: Self.typedMetadata(attachment.metadata),
                data: exactData,
                sha256: checksum
            )
            let external = ClinicalDocumentVisionHealthKitRecordMapper.attachment(
                value,
                parentUUID: parent.parentUUID,
                parentObjectTypeIdentifier: parent.objectTypeIdentifier,
                selectedMetricIDs: attribution.metricIDs
            ).attributed(attribution)
            outcome.records.append(external)
            outcome.parentRelationships.append(HealthKitAttachmentParentRelationship(
                parentUUID: parent.parentUUID,
                relationship: HealthKitRecordRelationship(
                    targetExternalIdentifier: external.externalIdentifier,
                    role: "attachment",
                    kind: "attachment"
                )
            ))
        }
        return outcome
    }
}
