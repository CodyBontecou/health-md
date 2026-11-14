#if os(macOS)
import Foundation
import HealthKit
import Network
import XCTest
@testable import HealthMd

/// Synthetic admission-to-destination boundary qualification. The Connected Mac
/// harness serializes controls/chunks and uses real durable receivers/ACKs; it
/// does not exercise encrypted sockets, discovery, hardware, or the iPhone UI.
@MainActor
final class HistoryTargetAdmissionTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: Match docs/testing/lifecycle-audit.md for
    // isolated synthetic Combine-backed settings/vault observation fixtures.
    private static var retained: [AnyObject] = []

    func testResolvedAllTimeAPIAdmissionSendsFrozenDocumentBytesToSocket() async throws {
        for envelopeV2 in [false, true] {
            let sink = try AdmissionAPISink(); try sink.start(); defer { sink.stop() }
            let zoneName = TimeZone.current.secondsFromGMT() == 14 * 3600 ? "Etc/GMT+12" : "Pacific/Kiritimati"
            let fixture = try makeFixture(target: .apiEndpoint,
                calendarTimeZone: try XCTUnwrap(TimeZone(identifier: zoneName)))
            let resolved = try await admit(fixture)
            let admitted = try XCTUnwrap(resolved)
            mutateLiveSettings(fixture.settings)
            let frozen = admitted.selection.makeCaptureSettings(); Self.retained.append(frozen)
            let destination = APIExportDestinationSnapshot(endpointURL: sink.url,
                authorizationHeaderValue: nil, displayName: "Synthetic loopback", redactedEndpointDescription: sink.url.absoluteString)
            let client = APIExportClient(session: .shared, authorizeAccess: { _ in .allowedPersonal },
                clinicContext: { _ in (false, nil) })
            var preparedBodies: [Data] = []
            var preparedHashes: [String] = []
            let upload: APIEndpointExportRunner.PreparedUploader = { batch, destination in
                try batch.bodyArtifact.validateIntegrity()
                preparedBodies.append(try batch.bodyArtifact.materializedData())
                preparedHashes.append(batch.bodyArtifact.descriptor.sha256)
                return try await client.upload(payloadArtifact: batch.bodyArtifact, destination: destination)
            }
            let result: ExportOrchestrator.ExportResult
            if envelopeV2 {
                // The ordinary test host disables Connected Apps. Exercise v2
                // through the existing explicit engine-preparation seam, without
                // changing the host flag or relaxing production provider gates.
                let resolution = try await APIEndpointExportRunner.prepare(dates: resolvedDates(admitted), settings: frozen,
                    destination: destination, calendarTimeZone: try XCTUnwrap(frozen.exportTimeZoneOverride),
                    connectedAppsEnabled: true, fetchHealthData: { date, policy, metrics in
                        try await fixture.manager.fetchHealthData(for: date, detailPolicy: policy,
                            metricSelection: metrics, timeZone: frozen.exportTimeZoneOverride,
                            captureContext: frozen.executionSleepCaptureContext)
                    }, policyResolver: AppleExportEnginePolicyResolver(injectedOverride: "shadow", userDefaults: nil, environment: [:]),
                    diagnosticSink: { _ in })
                guard case .prepared(let operation) = resolution else { return XCTFail("Expected prepared native v2 envelope") }
                result = await APIEndpointExportRunner.commitPreparedOperation(operation, upload: upload)
            } else {
                result = await APIEndpointExportRunner.export(dates: resolvedDates(admitted),
                    healthKitManager: fixture.manager, settings: frozen, destination: destination, upload: upload)
            }
            XCTAssertTrue(result.didCompleteAllRequestedDates)
            XCTAssertEqual(result.completedDates, fixture.dates)
            XCTAssertEqual(sink.bodies, preparedBodies)
            XCTAssertEqual(sink.bodies.map(NativeExportArtifact.sha256), preparedHashes)
            XCTAssertEqual(sink.bodies.count, 1)
            let body = try XCTUnwrap(sink.bodies.first)
            let envelope = try object(body)
            XCTAssertEqual(envelope["schema_version"] as? Int, envelopeV2 ? 2 : 1)
            let range = try XCTUnwrap(envelope["date_range"] as? [String: String])
            XCTAssertEqual(range, ["start": "2026-03-15", "end": "2026-03-16"])
            let records = try XCTUnwrap(envelope["records"] as? [[String: Any]])
            XCTAssertEqual(records.compactMap { $0["date"] as? String }, ["2026-03-15", "2026-03-16"])
            for record in records { try assertFrozenDocument(record) }
            assertOriginalSelection(fixture, admitted: admitted, frozen: frozen)
        }
    }

    func testUnadmittedAPIRequestsNeverReachSocket() async throws {
        let sink = try AdmissionAPISink(); try sink.start(); defer { sink.stop() }
        for rejection in [Rejection.empty, .stale, .cancelled] {
            let fixture = try makeFixture(target: .apiEndpoint)
            let request = Task { @MainActor in try await self.admit(fixture, rejection: rejection) }
            let admitted = try await request.value
            XCTAssertNil(admitted, "Rejected admission must not create an API operation")
            if let admitted {
                let frozen = admitted.selection.makeCaptureSettings(); Self.retained.append(frozen)
                let destination = APIExportDestinationSnapshot(endpointURL: sink.url,
                    authorizationHeaderValue: nil, displayName: "Synthetic", redactedEndpointDescription: sink.url.absoluteString)
                let client = APIExportClient(session: .shared, authorizeAccess: { _ in .allowedPersonal },
                    clinicContext: { _ in (false, nil) })
                _ = await APIEndpointExportRunner.export(dates: resolvedDates(admitted),
                    healthKitManager: fixture.manager, settings: frozen, destination: destination,
                    upload: { batch, destination in try await client.upload(payloadArtifact: batch.bodyArtifact, destination: destination) })
            }
            XCTAssertTrue(sink.bodies.isEmpty)
            XCTAssertTrue(fixture.store.historyRequestedIdentifiers.isEmpty,
                          "Unadmitted discovery must not start history/capture")
        }
    }

    func testResolvedAllTimeConnectedAdmissionCommitsFrozenDaysThroughDurableReceiver() async throws {
        let fixture = try makeFixture(target: .connectedMac)
        let resolved = try await admit(fixture)
        let admitted = try XCTUnwrap(resolved)
        mutateLiveSettings(fixture.settings)
        let harness = try makeConnectedHarness()
        let outcome = try await sendConnected(admitted, fixture: fixture, harness: harness)
        XCTAssertTrue(outcome.acknowledgement.accepted)
        XCTAssertEqual(outcome.acknowledgement.completedDates, fixture.dates)
        XCTAssertEqual(harness.receivedManifests.count, 1)
        let manifest = try XCTUnwrap(harness.receivedManifests.first)
        XCTAssertEqual(manifest.requestedDates, fixture.dates)
        XCTAssertEqual(manifest.requestedDateIdentifiers, ["2026-03-15", "2026-03-16"])
        XCTAssertEqual(manifest.settingsSnapshot.metricSelection.enabledMetricIDs, ["steps"])
        XCTAssertEqual(manifest.settingsSnapshot.exportFormats, [.json])
        XCTAssertEqual(harness.receivedManifestHashes, harness.sentManifestHashes)
        XCTAssertEqual(harness.receivedPartitionHashes, harness.sentPartitionHashes)
        XCTAssertFalse(harness.receivedPartitionHashes.isEmpty)
        XCTAssertEqual(harness.finalRequestFingerprint, try ConnectedCorpusRequestFingerprint.make(for: manifest))
        let files = try jsonFiles(harness.destination)
        XCTAssertEqual(files.count, 2)
        var owners: Set<String> = []
        for bytes in files.values {
            let document = try object(bytes); try assertFrozenDocument(document)
            owners.insert(try XCTUnwrap(document["date"] as? String))
        }
        XCTAssertEqual(owners, ["2026-03-15", "2026-03-16"])
        // The actual negotiated v2 session is native-authoritative. Compare
        // destination files with its shipped native serializer, not a range
        // planner that correctly reports this legacy profile unsupported.
        let originalSettings = manifest.settingsSnapshot.makeAdvancedExportSettings()
        Self.retained.append(originalSettings)
        XCTAssertEqual(harness.producedRecords.count, 2)
        for record in harness.producedRecords {
            let expected = try record.preparedExport(settings: originalSettings).renderArtifact(format: .json)
            defer { try? FileManager.default.removeItem(at: expected.url) }
            let path = ExportPathPlanner.aggregateRelativePath(healthSubfolder: "Health", settings: originalSettings,
                date: record.date, format: .json)
            let received = try XCTUnwrap(files[path], "Expected admitted path \(path); receiver files: \(files.keys.sorted())")
            XCTAssertEqual(received, try expected.materializedData())
            XCTAssertEqual(NativeExportArtifact.sha256(of: received), expected.descriptor.sha256)
        }
        // A real terminal receiver ACK must replay without changing any file.
        let replay = try await harness.receiver.finalize(try XCTUnwrap(harness.lastFinalize), vaultManager: harness.vault)
        guard case .replay(let acknowledgement, _) = replay else { return XCTFail("Expected durable terminal ACK replay") }
        XCTAssertEqual(acknowledgement, outcome.acknowledgement)
        XCTAssertEqual(try jsonFiles(harness.destination), files)
        let frozen = admitted.selection.makeCaptureSettings(); Self.retained.append(frozen)
        assertOriginalSelection(fixture, admitted: admitted, frozen: frozen)
    }

    func testUnadmittedConnectedRequestsCreateNoOutboundOrReceiverJob() async throws {
        let harness = try makeConnectedHarness()
        for rejection in [Rejection.empty, .stale, .cancelled] {
            let fixture = try makeFixture(target: .connectedMac)
            let task = Task { @MainActor in try await self.admit(fixture, rejection: rejection) }
            let admitted = try await task.value
            XCTAssertNil(admitted, "Rejected admission must not create a durable job")
            if let admitted { _ = try await sendConnected(admitted, fixture: fixture, harness: harness) }
            XCTAssertTrue(harness.receivedManifests.isEmpty)
            XCTAssertTrue(harness.receivedPartitionHashes.isEmpty)
            XCTAssertFalse(FileManager.default.fileExists(atPath: harness.outboundRoot.path))
            XCTAssertFalse(FileManager.default.fileExists(atPath: harness.sessions.path))
            XCTAssertTrue(try jsonFiles(harness.destination).isEmpty)
            XCTAssertTrue(fixture.store.historyRequestedIdentifiers.isEmpty)
        }
    }

    private enum Rejection: Equatable { case empty, stale, cancelled }
    private struct Fixture {
        let store: FakeHealthStore
        let manager: HealthKitManager
        let settings: AdvancedExportSettings
        let selection: HealthHistoryExecutionSelection
        let dates: [Date]
    }

    private func makeFixture(target: ExportTargetSelection, calendarTimeZone: TimeZone = .gmt) throws -> Fixture {
        let suite = "HistoryTargetAdmission.\(UUID())"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        addTeardownBlock { defaults.removePersistentDomain(forName: suite) }
        let settings = AdvancedExportSettings(userDefaults: defaults); Self.retained.append(settings)
        settings.exportFormats = [.json]; settings.detailPolicy = .summary
        settings.metricSelection.enabledMetrics = ["steps"]
        settings.generateRangeSummary = false; settings.includeDataDictionary = false
        settings.exportTimeZoneOverride = calendarTimeZone
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = calendarTimeZone
        let first = calendar.startOfDay(for: HealthKitFixtures.referenceDate)
        let dates = (0..<2).map { calendar.date(byAdding: .day, value: $0, to: first)! }
        let store = FakeHealthStore()
        for date in dates { try HealthKitFixtures.populateAllCategories(store, date: date) }
        store.earliestSampleDates[HKQuantityTypeIdentifier.stepCount.rawValue] = dates[0]
        let manager = HealthKitManager(store: store, userDefaults: defaults)
        let selection = HealthHistoryExecutionSelection(scope: .init(metricIDs: ["steps"],
            startDate: dates[0].addingTimeInterval(-365 * 86_400), endDate: dates[1],
            timeZoneIdentifier: calendarTimeZone.identifier, allAvailable: true, profileID: nil, rangeSemantics: .ownerDates),
            settings: .from(settings, appleExportEngineAuthorityIsFrozen: false), target: target, preset: .allTime)
        return Fixture(store: store, manager: manager, settings: settings, selection: selection, dates: dates)
    }

    private func admit(_ f: Fixture, rejection: Rejection? = nil) async throws -> HealthHistoryExportRequest? {
        let coordinator = HealthHistoryAssessmentCoordinator()
        if let rejection {
            f.store.earliestSampleDateQuery = { _ in
                switch rejection {
                case .empty: return nil
                case .stale: await MainActor.run { coordinator.invalidate() }
                case .cancelled: withUnsafeCurrentTask { $0?.cancel() }
                }
                return f.dates[0]
            }
        }
        let request = coordinator.beginExportRequest(selection: f.selection)
        let admitted: HealthHistoryExportRequest
        do {
            guard let resolved = try await coordinator.resolveExportRequest(request,
                liveSelection: { f.selection }, operation: {
                    try await NativeExportDateRangeResolver.resolve(request.dateRangeRequest, using: f.manager,
                        currentRequest: { request.dateRangeRequest }, referenceDate: f.dates[1])
                }) else { return nil }
            admitted = resolved
        } catch is CancellationError {
            XCTAssertEqual(rejection, .cancelled); return nil
        } catch NativeExportDateRangeResolver.ResolutionError.noHealthData {
            XCTAssertEqual(rejection, .empty); return nil
        }
        let assessment = await coordinator.assessExecution(requestID: admitted.id,
            worker: HealthHistoryAssessmentWorker(), notCompleted: f.manager.historyAssessmentNotCompleted(scope: admitted.selection.scope),
            scope: admitted.selection.scope, isCurrent: { coordinator.isCurrent(admitted, liveSelection: f.selection) },
            operation: { await f.manager.assessHistoryAccess(scope: admitted.selection.scope) })
        guard let assessment, !assessment.requiresExplicitContinuation,
              coordinator.isCurrent(admitted, liveSelection: f.selection) else { return nil }
        return admitted
    }

    private func resolvedDates(_ request: HealthHistoryExportRequest) -> [Date] {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: request.selection.scope.timeZoneIdentifier)!
        return ExportOrchestrator.dateRange(from: request.selection.scope.startDate,
            to: request.selection.scope.endDate, calendar: calendar)
    }

    private func mutateLiveSettings(_ settings: AdvancedExportSettings) {
        settings.metricSelection.enabledMetrics = ["heart_rate"]
        settings.exportFormats = [.csv]; settings.exportTimeZoneOverride = TimeZone(identifier: "Asia/Tokyo")!
    }

    private func assertOriginalSelection(_ f: Fixture, admitted: HealthHistoryExportRequest, frozen: AdvancedExportSettings) {
        XCTAssertEqual(f.selection.scope.startDate, f.dates[0].addingTimeInterval(-365 * 86_400))
        XCTAssertEqual(admitted.selection.scope.startDate, f.dates[0])
        XCTAssertEqual(admitted.selection.scope.endDate, f.dates[1])
        XCTAssertEqual(frozen.metricSelection.enabledMetrics, ["steps"])
        XCTAssertEqual(frozen.exportFormats, [.json])
        XCTAssertEqual(frozen.exportTimeZoneOverride?.identifier, f.selection.scope.timeZoneIdentifier)
    }

    private func object(_ bytes: Data) throws -> [String: Any] {
        try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
    }

    private func assertFrozenDocument(_ document: [String: Any]) throws {
        XCTAssertEqual(document["schema"] as? String, HealthMdExportSchema.identifier)
        let activity = try XCTUnwrap(document["activity"] as? [String: Any])
        XCTAssertEqual(activity["steps"] as? Int, 12_500)
        let heart = document["heart"] as? [String: Any]
        XCTAssertNil(heart?["heartRate"], "Later mutable heart selection must not replace admitted steps")
    }

    private func jsonFiles(_ root: URL) throws -> [String: Data] {
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let files = try XCTUnwrap(FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let url as URL in files where url.pathExtension == "json" {
            let file = url.standardizedFileURL.resolvingSymlinksInPath()
            XCTAssertTrue(file.path.hasPrefix(base.path + "/"))
            result[String(file.path.dropFirst(base.path.count + 1))] = try Data(contentsOf: file)
        }
        return result
    }

    private func makeConnectedHarness() throws -> AdmissionConnectedReceiver {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("HistoryAdmission-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let harness = try AdmissionConnectedReceiver(root: root); Self.retained.append(harness.vault)
        return harness
    }

    private func sendConnected(_ request: HealthHistoryExportRequest, fixture: Fixture,
                               harness: AdmissionConnectedReceiver) async throws -> ConnectedCorpusDurableSender.Result {
        let settings = request.selection.makeCaptureSettings(); Self.retained.append(settings)
        let dates = resolvedDates(request)
        let metadata = await MacExportStreamingJobBuilder.metadataForNewOperation(startDate: dates[0], endDate: dates[1],
            settings: settings, healthSubfolder: "Health", destinationDisplayName: "Synthetic Mac",
            enforceConnectedOperationGate: true)
        let manifest = ConnectedCorpusExportManifest(mode: .writeFiles, createdAt: Date(), sourceDeviceName: "Synthetic iPhone",
            sourceTimeZoneIdentifier: "GMT", dateRangeStart: metadata.dateRangeStart, dateRangeEnd: metadata.dateRangeEnd,
            requestedDates: metadata.requestedDates, requestedDateIdentifiers: metadata.requestedDates.map { APIExportClient.dayString(from: $0, timeZone: .gmt) },
            transferDates: metadata.transferDates, settingsSnapshot: metadata.settingsSnapshot, requestedTarget: metadata.requestedTarget)
        let session = ConnectedCorpusTransferSession(sessionID: UUID(), jobID: UUID(),
            requestFingerprint: try .make(for: manifest), protocolVersion: 2,
            partitionTargetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes, createdAt: manifest.createdAt,
            peerBinding: .init(sourceInstallationID: harness.sourceID, destinationInstallationID: harness.destinationID))
        let store = ConnectedCorpusOutboundStore(rootURL: harness.outboundRoot)
        _ = try store.createOrRestore(origin: .interactiveIPhone, session: session, manifest: manifest)
        return try await ConnectedCorpusDurableSender.send(configuration: .init(jobID: session.jobID, retryDelayNanoseconds: 0),
            store: store, transport: harness.transport(), produceItem: { _, date in
                let record = try await fixture.manager.fetchHealthData(for: date, detailPolicy: settings.detailPolicy,
                    metricSelection: settings.metricSelection, timeZone: .gmt, captureContext: settings.executionSleepCaptureContext)
                harness.producedRecords.append(record)
                return try await ConnectedCorpusSpoolItem.encodeHealthDay(.init(sourceDate: date,
                    isRequestedDate: dates.contains(date), record: record, externalDailyRecords: [], failure: nil),
                    sourceDate: date, isRequestedDate: dates.contains(date), protocolVersion: session.protocolVersion)
            })
    }
}

@MainActor
private final class AdmissionConnectedReceiver {
    let sourceID = UUID(), destinationID = UUID()
    let destination: URL, sessions: URL, outboundRoot: URL
    let receiver: MacCorpusExportSessionManager
    let vault: VaultManager
    private let chunks = ConnectedTransferReceiver(inactivityTimeout: 0)
    var receivedManifests: [ConnectedCorpusExportManifest] = []
    var sentPartitionHashes: [String] = [], receivedPartitionHashes: [String] = []
    var sentManifestHashes: [String] = [], receivedManifestHashes: [String] = []
    var producedRecords: [HealthData] = []
    var finalRequestFingerprint: ConnectedCorpusRequestFingerprint?
    var lastFinalize: ConnectedCorpusTransferFinalize?

    init(root: URL) throws {
        destination = root.appendingPathComponent("vault")
        sessions = root.appendingPathComponent("receiver")
        outboundRoot = root.appendingPathComponent("outbound")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let bookmarks = FakeBookmarkResolver(); bookmarks.accessGranted = true
        vault = VaultManager(defaults: FakeUserDefaults(), fileSystem: SystemFileSystem(), bookmarkResolver: bookmarks)
        vault.setVaultFolder(destination)
        receiver = MacCorpusExportSessionManager(rootURL: sessions)
    }

    private func wire(_ message: SyncMessage) throws -> SyncMessage {
        try JSONDecoder().decode(SyncMessage.self, from: JSONEncoder().encode(message))
    }

    func transport() -> ConnectedCorpusSender.Transport {
        .init(open: { [self] request in
            do {
                let sentManifest = try XCTUnwrap(request.exportManifest)
                // The protocol's canonical fingerprint sorts set-valued arrays;
                // raw JSONEncoder byte order is not stable across decoding.
                sentManifestHashes.append(try ConnectedCorpusRequestFingerprint.make(for: sentManifest).sha256)
                guard case .connectedCorpusTransferOpen(let decoded) = try wire(.connectedCorpusTransferOpen(request)) else { throw CocoaError(.coderInvalidValue) }
                let receivedManifest = try XCTUnwrap(decoded.exportManifest)
                receivedManifestHashes.append(try ConnectedCorpusRequestFingerprint.make(for: receivedManifest).sha256)
                receivedManifests.append(receivedManifest)
                let disposition = receiver.open(decoded, vaultManager: vault,
                    localInstallationID: destinationID, remoteInstallationID: sourceID)
                guard case .connectedCorpusTransferDisposition(let reply) = try wire(.connectedCorpusTransferDisposition(disposition)) else { throw CocoaError(.coderInvalidValue) }
                return reply
            } catch { XCTFail("Control wire/receiver rejected: \(error)"); return nil }
        }, sendPartition: { [self] file, manifest, transferID, progress in
            do {
                sentPartitionHashes.append(file.sha256)
                let chunkBytes = ConnectedTransferReceiver.maximumChunkBytes
                let count = Int((file.totalBytes + Int64(chunkBytes) - 1) / Int64(chunkBytes))
                let start = ConnectedTransferStart(protocolVersion: ConnectedTransferStart.corpusPartitionProtocolVersion,
                    transferID: transferID, manifest: manifest, totalBytes: file.totalBytes,
                    totalChunks: count, chunkBytes: chunkBytes, sha256: file.sha256)
                guard case .connectedTransferStart(let decodedStart) = try wire(.connectedTransferStart(start)),
                      case .acknowledgement(let startAck) = chunks.receive(decodedStart), startAck.accepted else { throw CocoaError(.coderInvalidValue) }
                let handle = try FileHandle(forReadingFrom: file.url); defer { try? handle.close() }
                for sequence in 1...count {
                    let data = try XCTUnwrap(handle.read(upToCount: chunkBytes))
                    let chunk = ConnectedTransferChunk(transferID: transferID, sequence: sequence,
                        data: data, sha256: ConnectedTransferFile.sha256Hex(data))
                    guard case .connectedTransferChunk(let decodedChunk) = try wire(.connectedTransferChunk(chunk)),
                          case .acknowledgement(let ack) = chunks.receive(decodedChunk), ack.accepted else { throw CocoaError(.coderInvalidValue) }
                    guard case .connectedTransferAck(let reply) = try wire(.connectedTransferAck(ack)) else { throw CocoaError(.coderInvalidValue) }
                    XCTAssertEqual(reply.sequence, sequence); progress(sequence, count)
                }
                let complete = ConnectedTransferComplete(transferID: transferID, totalBytes: file.totalBytes,
                    totalChunks: count, sha256: file.sha256)
                guard case .connectedTransferComplete(let decodedComplete) = try wire(.connectedTransferComplete(complete)),
                      case .ready(let ready) = chunks.receive(decodedComplete) else { throw CocoaError(.coderInvalidValue) }
                let received = try ConnectedTransferFile.inspect(ready.fileURL)
                XCTAssertEqual(received.totalBytes, file.totalBytes)
                receivedPartitionHashes.append(received.sha256)
                try await receiver.applyPartition(fileURL: ready.fileURL,
                    descriptor: try XCTUnwrap(ready.start.manifest.corpusPartition), vaultManager: vault)
                let acknowledgement = try XCTUnwrap(chunks.finish(transferID: transferID, accepted: true))
                guard case .connectedTransferFinalAck(let reply) = try wire(.connectedTransferFinalAck(acknowledgement)) else { throw CocoaError(.coderInvalidValue) }
                return .success(reply)
            } catch {
                XCTFail("Real transfer/receiver failed: \(error)")
                return .failure(.init(transferID: transferID, jobID: manifest.jobID,
                    reason: .applicationRejected, message: "Synthetic receiver rejected transfer"))
            }
        }, finalize: { [self] request, _ in
            do {
                guard case .connectedCorpusTransferFinalize(let decoded) = try wire(.connectedCorpusTransferFinalize(request)) else { throw CocoaError(.coderInvalidValue) }
                lastFinalize = decoded; finalRequestFingerprint = decoded.requestFingerprint
                let outcome = try await receiver.finalize(decoded, vaultManager: vault)
                guard case .files(_, let acknowledgement) = outcome,
                      case .connectedCorpusTransferFinalAck(let reply) = try wire(.connectedCorpusTransferFinalAck(acknowledgement)) else { throw CocoaError(.coderInvalidValue) }
                return reply
            } catch { XCTFail("Real durable finalization failed: \(error)"); return nil }
        }, cancel: { _ in XCTFail("Unadmitted requests must not reach transport cancellation"); return nil })
    }
}

/// Actual localhost HTTP sink. Access policy is synthetic; URLSession request
/// framing, complete body receipt and HTTP acknowledgement remain real.
private final class AdmissionAPISink: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "history-admission-api-sink")
    private let lock = NSLock()
    private var received: [Data] = []
    var bodies: [Data] { lock.lock(); defer { lock.unlock() }; return received }
    var url: URL { URL(string: "http://127.0.0.1:\(listener.port!.rawValue)/synthetic")! }
    init() throws {
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: "127.0.0.1", port: .any)
        listener = try NWListener(using: parameters)
    }
    func start() throws {
        let ready = DispatchSemaphore(value: 0)
        listener.stateUpdateHandler = { state in
            if case .ready = state { ready.signal() }
            if case .failed = state { ready.signal() }
        }
        listener.newConnectionHandler = { [weak self] connection in
            guard let self else { return }; connection.start(queue: self.queue)
            self.receive(connection, data: Data())
        }
        listener.start(queue: queue)
        guard ready.wait(timeout: .now() + 5) == .success, listener.state == .ready else { throw URLError(.cannotConnectToHost) }
    }
    func stop() { listener.cancel() }
    private func receive(_ connection: NWConnection, data: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 65_536) { [weak self] chunk, _, done, error in
            guard let self else { connection.cancel(); return }
            var accumulated = data; accumulated.append(chunk ?? Data())
            guard let end = accumulated.range(of: Data("\r\n\r\n".utf8)) else {
                if done || error != nil { connection.cancel() } else { self.receive(connection, data: accumulated) }; return
            }
            let headers = String(decoding: accumulated[..<end.lowerBound], as: UTF8.self)
            let length = headers.components(separatedBy: "\r\n").first { $0.lowercased().hasPrefix("content-length:") }
                .flatMap { Int($0.split(separator: ":", maxSplits: 1)[1].trimmingCharacters(in: .whitespaces)) } ?? 0
            guard length > 0, length < 10_000_000 else { connection.cancel(); return }
            if accumulated.count - end.upperBound < length { self.receive(connection, data: accumulated); return }
            self.lock.lock(); self.received.append(Data(accumulated[end.upperBound...].prefix(length))); self.lock.unlock()
            connection.send(content: Data("HTTP/1.1 202 Accepted\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8),
                completion: .contentProcessed { _ in connection.cancel() })
        }
    }
}
#endif
