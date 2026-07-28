import XCTest
@testable import HealthMd

@MainActor
final class ConnectedCorpusSenderTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: AdvancedExportSettings and nested
    // ObservableObjects use Combine subscriptions; retain this fixture to avoid
    // the platform-specific iOS Simulator deinit crash during test teardown.
    private static var retainedSettings: [AdvancedExportSettings] = []

    func testAcceptTransfersFinalizesAndReportsStableState() async throws {
        let fixture = makeFixture()
        let harness = Harness()
        var startedSessionID: UUID?
        var partitionTransferID: UUID?
        var finishedSessionID: UUID?
        var progressDescriptors: [ConnectedCorpusPartitionDescriptor] = []
        let item = try makeItem(date: fixture.date)
        let itemURL = item.file.url

        let result = try await ConnectedCorpusSender.send(
            configuration: fixture.configuration,
            transport: harness.transport(),
            onStateChange: { state in
                switch state {
                case .sessionStarted(let sessionID): startedSessionID = sessionID
                case .partitionStarted(let transferID, _): partitionTransferID = transferID
                case .partitionFinished: break
                case .finished(let sessionID): finishedSessionID = sessionID
                }
            },
            onValidatedPartitionProgress: { descriptor, _, _ in
                progressDescriptors.append(descriptor)
            },
            produceItems: { append in try await append(item) }
        )

        XCTAssertEqual(harness.opens.count, 1)
        XCTAssertEqual(harness.transfers.count, 1)
        XCTAssertEqual(harness.finalizations.count, 1)
        XCTAssertTrue(harness.cancellations.isEmpty)
        XCTAssertEqual(result.sessionID, startedSessionID)
        XCTAssertEqual(result.sessionID, finishedSessionID)
        XCTAssertEqual(harness.transfers[0].transferID, partitionTransferID)
        XCTAssertEqual(harness.opens[0].session.sessionID, result.sessionID)
        XCTAssertEqual(harness.opens[0].partition, harness.transfers[0].manifest.corpusPartition)
        XCTAssertEqual(progressDescriptors, [harness.opens[0].partition])
        XCTAssertFalse(FileManager.default.fileExists(atPath: itemURL.path))
    }

    func testAlreadyCommittedSkipsPhysicalRetransmission() async throws {
        let fixture = makeFixture()
        let harness = Harness()
        harness.openResponse = { open in
            ConnectedCorpusTransferDisposition(
                sessionID: open.session.sessionID,
                jobID: open.session.jobID,
                partitionIndex: open.partition.index,
                partitionSHA256: open.partition.sha256,
                disposition: .alreadyCommitted,
                nextPartitionIndex: open.partition.index + 1
            )
        }

        let result = try await ConnectedCorpusSender.send(
            configuration: fixture.configuration,
            transport: harness.transport(),
            produceItems: { append in
                try await append(try self.makeItem(date: fixture.date))
            }
        )

        XCTAssertEqual(harness.opens.count, 1)
        XCTAssertTrue(harness.transfers.isEmpty)
        XCTAssertEqual(harness.finalizations.count, 1)
        XCTAssertEqual(result.acknowledgement.finalPartitionSHA256, harness.opens[0].partition.sha256)
    }

    func testRetryableTransferAbortReopensAndRetransmitsSamePartition() async throws {
        let fixture = makeFixture(retryDelayNanoseconds: 0)
        let harness = Harness()
        var transferAttempt = 0
        harness.transferResponse = { file, manifest, transferID, progress in
            transferAttempt += 1
            if transferAttempt == 1 {
                return .failure(ConnectedTransferAbort(
                    transferID: transferID,
                    jobID: manifest.jobID,
                    reason: .disconnected,
                    message: "Peer disconnected."
                ))
            }
            progress(1, 1)
            return .success(ConnectedTransferFinalAck(
                transferID: transferID,
                accepted: true,
                sha256: file.sha256,
                message: nil
            ))
        }

        _ = try await ConnectedCorpusSender.send(
            configuration: fixture.configuration,
            transport: harness.transport(),
            produceItems: { append in
                try await append(try self.makeItem(date: fixture.date))
            }
        )

        XCTAssertEqual(harness.opens.count, 2)
        XCTAssertEqual(harness.transfers.count, 2)
        XCTAssertEqual(Set(harness.transfers.map(\.transferID)).count, 1)
        XCTAssertEqual(Set(harness.opens.map(\.partition)).count, 1)
    }

    func testFinalizationRetriesWithoutRetransmittingCommittedPartition() async throws {
        let fixture = makeFixture(retryDelayNanoseconds: 0)
        let harness = Harness()
        var finalizationAttempt = 0
        harness.finalizeResponse = { request in
            finalizationAttempt += 1
            guard finalizationAttempt > 1 else { return nil }
            return ConnectedCorpusTransferFinalAck(
                sessionID: request.sessionID,
                jobID: request.jobID,
                accepted: true,
                requestFingerprint: request.requestFingerprint,
                finalPartitionSHA256: request.finalPartitionSHA256,
                completedDates: [fixture.date],
                successCount: 1,
                totalCount: 1
            )
        }

        _ = try await ConnectedCorpusSender.send(
            configuration: fixture.configuration,
            transport: harness.transport(),
            produceItems: { append in
                try await append(try self.makeItem(date: fixture.date))
            }
        )

        XCTAssertEqual(harness.transfers.count, 1)
        XCTAssertEqual(harness.finalizations.count, 2)
        XCTAssertTrue(harness.cancellations.isEmpty)
    }

    func testRejectedOpenCancelsSessionAndDoesNotTransfer() async throws {
        let fixture = makeFixture()
        let harness = Harness()
        harness.openResponse = { open in
            ConnectedCorpusTransferDisposition(
                sessionID: open.session.sessionID,
                jobID: open.session.jobID,
                partitionIndex: open.partition.index,
                partitionSHA256: open.partition.sha256,
                disposition: .reject,
                nextPartitionIndex: 0,
                message: "Destination unavailable."
            )
        }

        do {
            _ = try await ConnectedCorpusSender.send(
                configuration: fixture.configuration,
                transport: harness.transport(),
                produceItems: { append in
                    try await append(try self.makeItem(date: fixture.date))
                }
            )
            XCTFail("Expected rejection")
        } catch let error as ConnectedCorpusSender.SenderError {
            XCTAssertEqual(error.localizedDescription, "Destination unavailable.")
        }

        XCTAssertEqual(harness.opens.count, 1)
        XCTAssertTrue(harness.transfers.isEmpty)
        XCTAssertEqual(harness.cancellations.count, 1)
        XCTAssertEqual(harness.cancellations[0].reason, .protocolError)
    }

    func testCancellationBeforeAssemblerOwnershipRemovesEncodedSpool() async throws {
        let fixture = makeFixture()
        let harness = Harness()
        let item = try makeItem(date: fixture.date)
        let itemURL = item.file.url

        do {
            _ = try await ConnectedCorpusSender.send(
                configuration: fixture.configuration,
                transport: harness.transport(),
                checkCancellation: { throw CancellationError() },
                produceItems: { append in try await append(item) }
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertEqual(harness.cancellations.count, 1)
        XCTAssertFalse(FileManager.default.fileExists(atPath: itemURL.path))
    }

    func testCancellationAbandonsPendingSpoolAndSendsOneCancel() async throws {
        let fixture = makeFixture()
        let harness = Harness()
        let item = try makeItem(date: fixture.date)
        let itemURL = item.file.url

        do {
            _ = try await ConnectedCorpusSender.send(
                configuration: fixture.configuration,
                transport: harness.transport(),
                produceItems: { append in
                    try await append(item)
                    throw CancellationError()
                }
            )
            XCTFail("Expected cancellation")
        } catch is CancellationError {
            // Expected.
        }

        XCTAssertTrue(harness.opens.isEmpty, "The sub-target item should remain buffered until final flush.")
        XCTAssertEqual(harness.cancellations.count, 1)
        XCTAssertEqual(harness.cancellations[0].reason, .userRequested)
        XCTAssertFalse(FileManager.default.fileExists(atPath: itemURL.path))
    }

    func testMismatchedFinalAcknowledgementFailsAndCancels() async throws {
        let fixture = makeFixture()
        let harness = Harness()
        harness.finalizeResponse = { request in
            ConnectedCorpusTransferFinalAck(
                sessionID: UUID(),
                jobID: request.jobID,
                accepted: true,
                requestFingerprint: request.requestFingerprint,
                finalPartitionSHA256: request.finalPartitionSHA256
            )
        }

        do {
            _ = try await ConnectedCorpusSender.send(
                configuration: fixture.configuration,
                transport: harness.transport(),
                produceItems: { append in
                    try await append(try self.makeItem(date: fixture.date))
                }
            )
            XCTFail("Expected finalization failure")
        } catch let error as ConnectedCorpusSender.SenderError {
            XCTAssertTrue(error.localizedDescription.contains("durably finalize"))
        }

        XCTAssertEqual(harness.transfers.count, 1)
        XCTAssertEqual(harness.cancellations.count, 1)
    }

    private struct Fixture {
        let date: Date
        let configuration: ConnectedCorpusSender.Configuration
    }

    private func makeFixture(retryDelayNanoseconds: UInt64 = 0) -> Fixture {
        let suiteName = "ConnectedCorpusSenderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defaults.removePersistentDomain(forName: suiteName)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.exportFormats = [.json]
        let date = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let manifest = ConnectedCorpusExportManifest(
            mode: .writeFiles,
            createdAt: Date(timeIntervalSince1970: 1_800_000_100),
            sourceDeviceName: "Test iPhone",
            sourceTimeZoneIdentifier: TimeZone.current.identifier,
            dateRangeStart: date,
            dateRangeEnd: date,
            requestedDates: [date],
            requestedDateIdentifiers: [dayString(date)],
            transferDates: [date],
            settingsSnapshot: .from(settings),
            requestedTarget: nil
        )
        return Fixture(
            date: date,
            configuration: ConnectedCorpusSender.Configuration(
                jobID: UUID(),
                manifest: manifest,
                negotiation: ConnectedCorpusTransferNegotiation(
                    protocolVersion: ConnectedCorpusTransferCapabilities.currentProtocolVersion,
                    partitionTargetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes
                ),
                partitionRetryTimeout: 1,
                finalizationRetryTimeout: 1,
                finalizationAttemptTimeout: 0.1,
                retryDelayNanoseconds: retryDelayNanoseconds
            )
        )
    }

    private func makeItem(date: Date) throws -> ConnectedCorpusSpoolItem {
        try ConnectedCorpusSpoolItem.encode(
            ConnectedCorpusHealthDayPayload(
                sourceDate: date,
                isRequestedDate: true,
                record: HealthData(date: date, activity: ActivityData(steps: 123)),
                externalDailyRecords: [],
                failure: nil
            ),
            kind: .macHealthDay,
            sourceDate: date,
            isRequestedDate: true
        )
    }

    private func dayString(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = .current
        formatter.dateFormat = "yyyy-MM-dd"
        return formatter.string(from: date)
    }

    private final class Harness {
        struct TransferCall {
            let file: ConnectedTransferPreparedFile
            let manifest: ConnectedTransferManifest
            let transferID: UUID
        }

        var opens: [ConnectedCorpusTransferOpen] = []
        var transfers: [TransferCall] = []
        var finalizations: [ConnectedCorpusTransferFinalize] = []
        var cancellations: [ConnectedCorpusTransferCancel] = []

        var openResponse: ((ConnectedCorpusTransferOpen) -> ConnectedCorpusTransferDisposition)?
        var transferResponse: ((
            ConnectedTransferPreparedFile,
            ConnectedTransferManifest,
            UUID,
            @escaping ConnectedCorpusSender.ValidatedProgressHandler
        ) -> ConnectedTransferSendResult)?
        var finalizeResponse: ((ConnectedCorpusTransferFinalize) -> ConnectedCorpusTransferFinalAck?)?

        func transport() -> ConnectedCorpusSender.Transport {
            ConnectedCorpusSender.Transport(
                open: { [self] request in
                    opens.append(request)
                    return openResponse?(request) ?? ConnectedCorpusTransferDisposition(
                        sessionID: request.session.sessionID,
                        jobID: request.session.jobID,
                        partitionIndex: request.partition.index,
                        partitionSHA256: request.partition.sha256,
                        disposition: .accept,
                        nextPartitionIndex: request.partition.index
                    )
                },
                sendPartition: { [self] file, manifest, transferID, progress in
                    transfers.append(TransferCall(
                        file: file,
                        manifest: manifest,
                        transferID: transferID
                    ))
                    if let transferResponse {
                        return transferResponse(file, manifest, transferID, progress)
                    }
                    progress(1, 1)
                    return .success(ConnectedTransferFinalAck(
                        transferID: transferID,
                        accepted: true,
                        sha256: file.sha256,
                        message: nil
                    ))
                },
                finalize: { [self] request, _ in
                    finalizations.append(request)
                    if let finalizeResponse {
                        return finalizeResponse(request)
                    }
                    return ConnectedCorpusTransferFinalAck(
                        sessionID: request.sessionID,
                        jobID: request.jobID,
                        accepted: true,
                        requestFingerprint: request.requestFingerprint,
                        finalPartitionSHA256: request.finalPartitionSHA256,
                        successCount: 1,
                        totalCount: 1
                    )
                },
                cancel: { [self] request in
                    cancellations.append(request)
                    return ConnectedCorpusTransferCancelAck(
                        sessionID: request.sessionID,
                        jobID: request.jobID,
                        accepted: true,
                        acknowledgedAt: Date(),
                        message: nil
                    )
                }
            )
        }
    }
}
