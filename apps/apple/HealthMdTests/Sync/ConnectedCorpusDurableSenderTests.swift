import XCTest
@testable import HealthMd

@MainActor
final class ConnectedCorpusDurableSenderTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: these Combine-backed ObservableObjects
    // hit a platform-specific iOS Simulator deinit crash during test teardown.
    private static var retainedSettings: [AdvancedExportSettings] = []
    #if os(iOS)
    // STATIC RETENTION JUSTIFICATION: recovery managers hit the same
    // platform-specific iOS Simulator deinit crash during test teardown.
    private static var retainedRecoveryManagers: [IPhoneCorpusExportRecoveryManager] = []
    #endif

    func testRelaunchReplaysPendingPartitionWithoutRecapturingDay() async throws {
        let fixture = try makeFixture(dayCount: 1)
        let firstHarness = Harness()
        firstHarness.openResponse = { _ in nil }
        var produced = 0

        do {
            _ = try await ConnectedCorpusDurableSender.send(
                configuration: .init(jobID: fixture.session.jobID, retryDelayNanoseconds: 0),
                store: fixture.store,
                transport: firstHarness.transport(),
                produceItem: { _, date in
                    produced += 1
                    return try self.makeSmallItem(date: date)
                }
            )
            XCTFail("Expected paused sender")
        } catch let error as ConnectedCorpusDurableSender.DurableSenderError {
            guard case .paused = error else { return XCTFail("Unexpected error: \(error)") }
        }

        let paused = try XCTUnwrap(try fixture.store.load(jobID: fixture.session.jobID))
        let pending = try XCTUnwrap(paused.pendingPartition)
        XCTAssertEqual(produced, 1)
        XCTAssertEqual(paused.state, .paused)
        XCTAssertTrue(FileManager.default.fileExists(
            atPath: fixture.root.appendingPathComponent(
                fixture.session.jobID.uuidString.lowercased()
            ).appendingPathComponent(pending.relativePath).path
        ))

        // A new store instance models an iPhone process relaunch. The Mac's
        // durable journal is authoritative and reports this exact partition as
        // committed even if the sender died before recording the ACK.
        let restoredStore = ConnectedCorpusOutboundStore(rootURL: fixture.root)
        let secondHarness = Harness()
        secondHarness.openResponse = { open in
            Self.disposition(for: open, kind: .alreadyCommitted, next: open.partition.index + 1)
        }
        let result = try await ConnectedCorpusDurableSender.send(
            configuration: .init(jobID: fixture.session.jobID, retryDelayNanoseconds: 0),
            store: restoredStore,
            transport: secondHarness.transport(),
            produceItem: { _, _ in
                XCTFail("A durably spooled day must not be recaptured")
                throw TestError.unexpectedProduction
            }
        )

        XCTAssertEqual(result.sessionID, fixture.session.sessionID)
        XCTAssertEqual(secondHarness.opens.map(\.partition), [pending.descriptor])
        XCTAssertTrue(secondHarness.transfers.isEmpty)
        let completed = try XCTUnwrap(try restoredStore.load(jobID: fixture.session.jobID))
        XCTAssertEqual(completed.state, .completed)
        XCTAssertEqual(completed.completedItemCount, 1)
        XCTAssertTrue(completed.items.isEmpty)
        XCTAssertNil(completed.pendingPartition)
    }

    func testCrashAfterReceiverAckBeforeCheckpointReopensSameDescriptorAndTransferID() async throws {
        let fixture = try makeFixture(dayCount: 1)
        let firstHarness = Harness()
        var injectedCrash = false

        do {
            _ = try await ConnectedCorpusDurableSender.send(
                configuration: .init(jobID: fixture.session.jobID, retryDelayNanoseconds: 0),
                store: fixture.store,
                transport: firstHarness.transport(),
                afterReceiverAcceptedPartition: {
                    if !injectedCrash {
                        injectedCrash = true
                        throw TestError.simulatedCrash
                    }
                },
                produceItem: { _, date in try self.makeSmallItem(date: date) }
            )
            XCTFail("Expected simulated crash to pause")
        } catch let error as ConnectedCorpusDurableSender.DurableSenderError {
            guard case .paused = error else { return XCTFail("Unexpected error: \(error)") }
        }

        XCTAssertEqual(firstHarness.transfers.count, 1)
        let pendingBeforeRelaunch = try XCTUnwrap(
            try fixture.store.load(jobID: fixture.session.jobID)?.pendingPartition
        )
        let restoredStore = ConnectedCorpusOutboundStore(rootURL: fixture.root)
        let secondHarness = Harness()
        secondHarness.openResponse = { open in
            Self.disposition(for: open, kind: .alreadyCommitted, next: open.partition.index + 1)
        }

        _ = try await ConnectedCorpusDurableSender.send(
            configuration: .init(jobID: fixture.session.jobID, retryDelayNanoseconds: 0),
            store: restoredStore,
            transport: secondHarness.transport(),
            produceItem: { _, _ in throw TestError.unexpectedProduction }
        )

        XCTAssertEqual(secondHarness.opens.first?.partition, pendingBeforeRelaunch.descriptor)
        XCTAssertEqual(
            firstHarness.transfers.first?.transferID,
            pendingBeforeRelaunch.transferID
        )
        XCTAssertTrue(secondHarness.transfers.isEmpty)
    }

    func testV1OutboundJournalMigratesWithoutChangingPinnedLegacySession() throws {
        let fixture = try makeFixture(dayCount: 1, protocolVersion: 2)
        let journalURL = fixture.root
            .appendingPathComponent(fixture.session.jobID.uuidString.lowercased())
            .appendingPathComponent("journal.json")
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: Data(contentsOf: journalURL)) as? [String: Any]
        )
        object["version"] = 1
        try JSONSerialization.data(withJSONObject: object, options: [.sortedKeys])
            .write(to: journalURL, options: .atomic)

        let restored = ConnectedCorpusOutboundStore(rootURL: fixture.root)
        let migrated = try XCTUnwrap(try restored.load(jobID: fixture.session.jobID))
        XCTAssertEqual(migrated.version, ConnectedCorpusOutboundJournal.currentVersion)
        XCTAssertEqual(migrated.session.protocolVersion, 2)
    }

    func testV4StreamableItemSurvivesDurableStoreRelaunchWithoutTranscoding() throws {
        let fixture = try makeFixture(
            dayCount: 1,
            protocolVersion: ConnectedCorpusTransferCapabilities.streamableItemProtocolVersion
        )
        let item = try makeSmallItem(
            date: fixture.dates[0],
            protocolVersion: fixture.session.protocolVersion
        )
        let expectedID = item.itemID
        let expectedHash = item.file.sha256
        let expectedBytes = item.file.totalBytes
        _ = try fixture.store.adoptItem(
            item,
            expectedIndex: 0,
            jobID: fixture.session.jobID
        )

        let restored = ConnectedCorpusOutboundStore(rootURL: fixture.root)
        let journal = try XCTUnwrap(try restored.load(jobID: fixture.session.jobID))
        XCTAssertEqual(journal.version, ConnectedCorpusOutboundJournal.currentVersion)
        XCTAssertEqual(journal.session.protocolVersion, 4)
        XCTAssertEqual(journal.items.first?.itemID, expectedID)
        XCTAssertEqual(journal.items.first?.sha256, expectedHash)
        XCTAssertEqual(journal.items.first?.totalBytes, expectedBytes)
        let source = try XCTUnwrap(try restored.spoolItems(for: journal).first)
        try ConnectedCorpusApplicationItemCodec.validateHeader(
            at: source.item.file.url,
            expectedKind: .macHealthDay
        )
    }

    func testRecordedMacResultHidesFinalizingProgressWithoutRemovingRecoveryCheckpoint() throws {
        let fixture = try makeFixture(dayCount: 1)
        let finalizing = try fixture.store.updateState(
            jobID: fixture.session.jobID,
            state: .finalizing,
            message: "Finalizing durable connected export…"
        )

        XCTAssertNotNil(finalizing.interactiveUIProgressSnapshot)
        XCTAssertNotNil(
            try fixture.store.load(jobID: fixture.session.jobID)?.unrecordedProgressSnapshot
        )
        XCTAssertTrue(try fixture.store.markCompletionRecorded(jobID: fixture.session.jobID))

        let recorded = try XCTUnwrap(try fixture.store.load(jobID: fixture.session.jobID))
        XCTAssertEqual(recorded.state, .finalizing)
        XCTAssertTrue(recorded.completionRecorded)
        XCTAssertNil(recorded.unrecordedProgressSnapshot)
        XCTAssertNil(recorded.interactiveUIProgressSnapshot)
        XCTAssertEqual(
            fixture.store.resumableJournals().map(\.jobID),
            [fixture.session.jobID],
            "Hiding stale UI progress must not discard the durable final-ACK checkpoint."
        )
    }

    func testOnlyInteractiveOriginMayDriveExportScreen() {
        XCTAssertTrue(ConnectedCorpusOutboundOrigin.interactiveIPhone.drivesInteractiveExportUI)
        XCTAssertFalse(ConnectedCorpusOutboundOrigin.macInitiated.drivesInteractiveExportUI)
        XCTAssertFalse(ConnectedCorpusOutboundOrigin.scheduledIPhone.drivesInteractiveExportUI)
    }

    func testCLIProgressPreservesDurablyPreparedFrontierBeforePartitionCommit() throws {
        let fixture = try makeFixture(
            dayCount: 1,
            origin: .macInitiated,
            includeCLIRequest: true
        )
        let item = try makeSmallItem(date: fixture.dates[0])
        let prepared = try fixture.store.adoptItem(
            item,
            expectedIndex: 0,
            jobID: fixture.session.jobID
        )

        XCTAssertEqual(prepared.nextItemIndex, 1)
        XCTAssertEqual(prepared.completedItemCount, 0)
        XCTAssertEqual(prepared.progressSnapshot.processedDays, 0)
        XCTAssertEqual(prepared.cliUIProgressSnapshot?.processedDays, 1)
        XCTAssertEqual(prepared.cliUIProgressSnapshot?.committedPartitionCount, 0)
        XCTAssertEqual(prepared.cliUIProgressSnapshot?.committedBytes, 0)
    }

    #if os(iOS)
    func testRecoveryManagerRestoresInterruptedInteractiveSnapshotAsPaused() throws {
        let fixture = try makeFixture(dayCount: 1)
        let manager = IPhoneCorpusExportRecoveryManager(store: fixture.store)
        Self.retainedRecoveryManagers.append(manager)

        XCTAssertEqual(manager.activeSnapshot?.jobID, fixture.session.jobID)
        XCTAssertEqual(manager.activeSnapshot?.state, .paused)
        XCTAssertEqual(manager.activeSnapshot?.processedDays, 0)
        XCTAssertEqual(
            manager.activeSnapshot?.message,
            "Waiting for the same Mac to reconnect…"
        )
    }

    func testRecoveryManagerKeepsInterruptedCLIActivityHiddenWhileDormant() throws {
        let fixture = try makeFixture(
            dayCount: 1,
            origin: .macInitiated,
            includeCLIRequest: true
        )
        let tracker = CLIExportActivityTracker()
        defer { tracker.clear() }
        let manager = IPhoneCorpusExportRecoveryManager(
            store: fixture.store,
            cliActivityTracker: tracker
        )
        Self.retainedRecoveryManagers.append(manager)

        XCTAssertEqual(
            manager.journal(jobID: fixture.session.jobID)?.state,
            .paused
        )
        XCTAssertNil(tracker.snapshot)
        XCTAssertFalse(tracker.keepsScreenAwake)
        XCTAssertEqual(
            fixture.store.resumableJournals().map(\.jobID),
            [fixture.session.jobID],
            "Hiding dormant CLI UI must preserve its resumable checkpoint."
        )
    }

    func testRecoveryManagerClearsOwnedCLIActivityWhenProgressStopsPublishing() throws {
        let fixture = try makeFixture(
            dayCount: 1,
            origin: .macInitiated,
            includeCLIRequest: true
        )
        let tracker = CLIExportActivityTracker()
        defer { tracker.clear() }
        let manager = IPhoneCorpusExportRecoveryManager(
            store: fixture.store,
            cliActivityTracker: tracker
        )
        Self.retainedRecoveryManagers.append(manager)
        let transferring = try fixture.store.updateState(
            jobID: fixture.session.jobID,
            state: .transferring,
            message: "Sending a recovered CLI export…"
        )
        tracker.updateConnected(try XCTUnwrap(transferring.cliUIProgressSnapshot))
        XCTAssertEqual(tracker.snapshot?.jobID, fixture.session.jobID)

        manager.markCompletionRecorded(jobID: fixture.session.jobID)

        XCTAssertNil(tracker.snapshot)
        XCTAssertTrue(
            try XCTUnwrap(manager.journal(jobID: fixture.session.jobID)).completionRecorded
        )
        XCTAssertEqual(
            fixture.store.resumableJournals().map(\.jobID),
            [fixture.session.jobID],
            "UI cleanup must not discard the durable final-ACK checkpoint."
        )
    }

    func testRecoveryManagerDoesNotClearUnrelatedDirectCLIActivity() throws {
        let fixture = try makeFixture(dayCount: 1)
        let tracker = CLIExportActivityTracker()
        defer { tracker.clear() }
        let directJobID = UUID()
        tracker.begin(
            jobID: directJobID,
            source: .direct,
            totalDays: 1,
            message: "Active direct export"
        )

        let manager = IPhoneCorpusExportRecoveryManager(
            store: fixture.store,
            cliActivityTracker: tracker
        )
        Self.retainedRecoveryManagers.append(manager)

        XCTAssertEqual(tracker.snapshot?.jobID, directJobID)
        XCTAssertEqual(tracker.snapshot?.source, .direct)
        XCTAssertEqual(tracker.snapshot?.message, "Active direct export")
    }

    func testPeerDisconnectHidesOrphanedPersistedCLIActivity() throws {
        let fixture = try makeFixture(
            dayCount: 1,
            origin: .macInitiated,
            includeCLIRequest: true
        )
        let tracker = CLIExportActivityTracker()
        defer { tracker.clear() }
        let manager = IPhoneCorpusExportRecoveryManager(
            store: fixture.store,
            cliActivityTracker: tracker
        )
        Self.retainedRecoveryManagers.append(manager)
        let transferring = try fixture.store.updateState(
            jobID: fixture.session.jobID,
            state: .transferring,
            message: "Sending a recovered CLI export…"
        )
        tracker.updateConnected(try XCTUnwrap(transferring.cliUIProgressSnapshot))
        XCTAssertTrue(tracker.keepsScreenAwake)

        manager.handlePeerDisconnected()

        XCTAssertEqual(
            manager.journal(jobID: fixture.session.jobID)?.state,
            .paused
        )
        XCTAssertNil(tracker.snapshot)
        XCTAssertFalse(tracker.keepsScreenAwake)
    }

    func testRecoveryManagerRejectsSecondJobBeforeCreatingCheckpoint() async throws {
        let fixture = try makeFixture(dayCount: 1)
        _ = try fixture.store.updateState(
            jobID: fixture.session.jobID,
            state: .finalizing,
            message: "Finalizing durable connected export…"
        )
        XCTAssertTrue(try fixture.store.markCompletionRecorded(jobID: fixture.session.jobID))
        let manager = IPhoneCorpusExportRecoveryManager(store: fixture.store)
        Self.retainedRecoveryManagers.append(manager)
        XCTAssertNil(
            manager.activeSnapshot,
            "A recorded result hides progress while final-ACK recovery retains sender ownership."
        )
        let secondJobID = UUID()
        let peerBinding = try XCTUnwrap(fixture.session.peerBinding)
        let negotiation = ConnectedCorpusDurableNegotiation(
            transfer: ConnectedCorpusTransferNegotiation(
                protocolVersion: fixture.session.protocolVersion,
                partitionTargetBytes: fixture.session.partitionTargetBytes
            ),
            peerBinding: peerBinding
        )
        var producedItem = false
        var publishedCheckpoint = false

        do {
            _ = try await manager.send(
                origin: .interactiveIPhone,
                jobID: secondJobID,
                manifest: fixture.manifest,
                durableNegotiation: negotiation,
                syncService: SyncService(),
                onCheckpoint: { _ in publishedCheckpoint = true },
                produceItem: { _, date in
                    producedItem = true
                    return try self.makeSmallItem(date: date)
                }
            )
            XCTFail("Expected the persisted export to retain sender ownership")
        } catch let error as IPhoneCorpusExportRecoveryManager.StartError {
            XCTAssertEqual(
                error,
                .exportAlreadyInProgress(
                    jobID: fixture.session.jobID,
                    origin: .interactiveIPhone
                )
            )
        } catch {
            XCTFail("Unexpected error: \(error)")
        }

        XCTAssertFalse(producedItem)
        XCTAssertFalse(publishedCheckpoint)
        XCTAssertNil(manager.journal(jobID: secondJobID))
        XCTAssertNil(manager.activeSnapshot)
        XCTAssertEqual(fixture.store.resumableJournals().map(\.jobID), [fixture.session.jobID])
    }

    func testRecoveryManagerKeepsScheduledRecoveryOutOfInteractiveUI() throws {
        let fixture = try makeFixture(dayCount: 1, origin: .scheduledIPhone)
        let manager = IPhoneCorpusExportRecoveryManager(store: fixture.store)
        Self.retainedRecoveryManagers.append(manager)

        XCTAssertNil(manager.activeSnapshot)
        XCTAssertEqual(manager.resumableSnapshots.map(\.jobID), [fixture.session.jobID])
    }

    func testFastReconnectResumesAfterOldSenderReleasesOwnershipAndKeepsAssertion() async throws {
        let syncService = SyncService()
        let remoteInstallationID = UUID()
        let fixture = try makeFixture(
            dayCount: 1,
            sourceInstallationID: syncService.installationID,
            destinationInstallationID: remoteInstallationID
        )
        let item = try makeSmallItem(date: fixture.dates[0])
        _ = try fixture.store.adoptItem(
            item,
            expectedIndex: 0,
            jobID: fixture.session.jobID
        )

        let harness = FastReconnectHarness()
        let remoteCapabilities = SyncPeerCapabilities.current(
            platform: .macOS,
            installationID: remoteInstallationID
        )
        let manager = IPhoneCorpusExportRecoveryManager(
            store: fixture.store,
            transportProvider: { _ in harness.transport() },
            connectedPeerProvider: { _ in remoteCapabilities }
        )
        Self.retainedRecoveryManagers.append(manager)
        let defaultsName = "ConnectedCorpusFastReconnect.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: defaultsName))
        defaults.removePersistentDomain(forName: defaultsName)
        defer { defaults.removePersistentDomain(forName: defaultsName) }
        let healthKitManager = HealthKitManager(
            store: FakeHealthStore(),
            userDefaults: defaults
        )
        manager.configure(
            syncService: syncService,
            healthKitManager: healthKitManager,
            externalIntegrations: nil
        )
        syncService.connectionState = .connected
        syncService.remoteCapabilities = remoteCapabilities

        XCTAssertEqual(manager.resumeEligibleJob(), fixture.session.jobID)
        await waitUntil { harness.firstOpenStarted }
        XCTAssertTrue(manager.hasRunningExport)

        // A real MCSession is intentionally not connected in this unit test,
        // so pin the public state at the same moment as the reconnect callback.
        syncService.connectionState = .connected
        XCTAssertEqual(manager.resumeEligibleJob(), fixture.session.jobID)
        XCTAssertTrue(syncService.isSyncing)

        // Reconnect arrived while the old sender still owned activeTask.
        harness.releaseFirstOpen()
        await waitUntil { harness.secondOpenStarted }
        syncService.connectionState = .connected
        syncService.remoteCapabilities = remoteCapabilities
        XCTAssertEqual(manager.resumeEligibleJob(), fixture.session.jobID)
        XCTAssertTrue(syncService.isSyncing)
        harness.releaseSecondOpen()

        await waitUntil { harness.resumedOpenStarted }
        XCTAssertEqual(harness.openCount, 3)
        XCTAssertTrue(manager.hasRunningExport)
        manager.reconcileExecutionAssertion(on: syncService)
        XCTAssertTrue(syncService.isSyncing)

        harness.releaseResumedOpen()
        await waitUntil {
            manager.journal(jobID: fixture.session.jobID)?.state == .completed
                && !manager.hasRunningExport
        }
        XCTAssertEqual(
            manager.journal(jobID: fixture.session.jobID)?.completedItemCount,
            1
        )
        XCTAssertFalse(syncService.isSyncing)
    }
    #endif

    func testMacInitiatedFinalAcknowledgementLossResumesFinalizationWithoutRetransmission() async throws {
        let fixture = try makeFixture(dayCount: 1, origin: .macInitiated)
        let firstHarness = Harness()
        firstHarness.finalizeResponse = { _ in nil }

        do {
            _ = try await ConnectedCorpusDurableSender.send(
                configuration: .init(jobID: fixture.session.jobID, retryDelayNanoseconds: 0),
                store: fixture.store,
                transport: firstHarness.transport(),
                produceItem: { _, date in try self.makeSmallItem(date: date) }
            )
            XCTFail("Expected finalization pause")
        } catch let error as ConnectedCorpusDurableSender.DurableSenderError {
            guard case .paused = error else { return XCTFail("Unexpected error: \(error)") }
        }

        let paused = try XCTUnwrap(try fixture.store.load(jobID: fixture.session.jobID))
        XCTAssertEqual(paused.committedPartitionCount, 1)
        XCTAssertTrue(paused.items.isEmpty)
        XCTAssertNil(paused.pendingPartition)
        XCTAssertEqual(firstHarness.transfers.count, 1)

        let restoredStore = ConnectedCorpusOutboundStore(rootURL: fixture.root)
        let secondHarness = Harness()
        _ = try await ConnectedCorpusDurableSender.send(
            configuration: .init(jobID: fixture.session.jobID, retryDelayNanoseconds: 0),
            store: restoredStore,
            transport: secondHarness.transport(),
            produceItem: { _, _ in throw TestError.unexpectedProduction }
        )

        XCTAssertTrue(secondHarness.opens.isEmpty)
        XCTAssertTrue(secondHarness.transfers.isEmpty)
        XCTAssertEqual(secondHarness.finalizations.count, 1)
        XCTAssertEqual(
            secondHarness.finalizations.first?.finalPartitionSHA256,
            paused.lastCommittedPartitionSHA256
        )
    }

    func testItemSpanningPartitionsKeepsOriginalBytesAndOffsetAcrossRelaunch() async throws {
        let fixture = try makeFixture(dayCount: 1)
        let firstHarness = Harness()
        firstHarness.openResponse = { open in
            if open.partition.index == 0 {
                return Self.disposition(for: open, kind: .accept, next: 0)
            }
            return nil
        }

        do {
            _ = try await ConnectedCorpusDurableSender.send(
                configuration: .init(
                    jobID: fixture.session.jobID,
                    retryDelayNanoseconds: 0,
                    maximumImmediateAttempts: 1
                ),
                store: fixture.store,
                transport: firstHarness.transport(),
                produceItem: { _, date in try self.makeLargeItem(date: date, bytes: 40 * 1_024 * 1_024) }
            )
            XCTFail("Expected pause on second partition")
        } catch let error as ConnectedCorpusDurableSender.DurableSenderError {
            guard case .paused = error else { return XCTFail("Unexpected error: \(error)") }
        }

        let paused = try XCTUnwrap(try fixture.store.load(jobID: fixture.session.jobID))
        XCTAssertEqual(paused.committedPartitionCount, 1)
        XCTAssertEqual(paused.items.count, 1)
        XCTAssertGreaterThan(paused.items[0].nextOffset, 0)
        XCTAssertLessThan(paused.items[0].nextOffset, paused.items[0].totalBytes)
        XCTAssertEqual(paused.pendingPartition?.descriptor.index, 1)
        XCTAssertLessThan(
            fixture.store.totalInternalSpoolBytes(jobID: fixture.session.jobID),
            128 * ConnectedCorpusTransferConstants.mebibyte
        )

        let originalItemID = paused.items[0].itemID
        let originalHash = paused.items[0].sha256
        let restoredStore = ConnectedCorpusOutboundStore(rootURL: fixture.root)
        let secondHarness = Harness()
        _ = try await ConnectedCorpusDurableSender.send(
            configuration: .init(jobID: fixture.session.jobID, retryDelayNanoseconds: 0),
            store: restoredStore,
            transport: secondHarness.transport(),
            produceItem: { _, _ in throw TestError.unexpectedProduction }
        )

        XCTAssertEqual(secondHarness.opens.first?.partition.index, 1)
        XCTAssertEqual(secondHarness.opens.first?.partition.previousSHA256, paused.lastCommittedPartitionSHA256)
        let segment = try XCTUnwrap(secondHarness.transfers.first?.manifest.corpusPartition)
        XCTAssertEqual(segment.index, 1)
        let completed = try XCTUnwrap(try restoredStore.load(jobID: fixture.session.jobID))
        XCTAssertEqual(completed.state, .completed)
        XCTAssertTrue(completed.items.isEmpty)
        XCTAssertEqual(originalItemID, paused.items[0].itemID)
        XCTAssertEqual(originalHash, paused.items[0].sha256)
    }

    func testExplicitCancellationAndExpiryDeleteOnlyInternalSpool() async throws {
        var now = Date(timeIntervalSince1970: 1_800_000_000)
        let fixture = try makeFixture(dayCount: 1, now: { now })
        let item = try makeSmallItem(date: fixture.dates[0])
        _ = try fixture.store.adoptItem(item, expectedIndex: 0, jobID: fixture.session.jobID)
        XCTAssertGreaterThan(fixture.store.totalInternalSpoolBytes(jobID: fixture.session.jobID), 0)

        try fixture.store.cancel(jobID: fixture.session.jobID)
        let cancelled = try XCTUnwrap(
            try fixture.store.load(jobID: fixture.session.jobID, allowExpired: true)
        )
        XCTAssertEqual(cancelled.state, .cancelled)
        XCTAssertTrue(cancelled.items.isEmpty)
        XCTAssertNil(cancelled.pendingPartition)

        let expiryFixture = try makeFixture(dayCount: 1, now: { now })
        _ = try expiryFixture.store.adoptItem(
            try makeSmallItem(date: expiryFixture.dates[0]),
            expectedIndex: 0,
            jobID: expiryFixture.session.jobID
        )
        now = now.addingTimeInterval(ConnectedCorpusOutboundStore.retentionInterval + 1)
        XCTAssertEqual(expiryFixture.store.cleanupExpired(now: now), [expiryFixture.session.jobID])
        let expired = try XCTUnwrap(
            try expiryFixture.store.load(jobID: expiryFixture.session.jobID, allowExpired: true)
        )
        XCTAssertEqual(expired.state, .expired)
        XCTAssertTrue(expired.items.isEmpty)
        XCTAssertNil(expired.pendingPartition)
    }

    func testChangedManifestCannotReuseDurableJob() throws {
        let fixture = try makeFixture(dayCount: 1)
        var secondDate = fixture.dates[0].addingTimeInterval(24 * 60 * 60)
        secondDate = Calendar.current.startOfDay(for: secondDate)
        let changed = makeManifest(
            dates: [fixture.dates[0], secondDate],
            settings: fixture.settings,
            createdAt: fixture.manifest.createdAt
        )
        let changedSession = ConnectedCorpusTransferSession(
            sessionID: fixture.session.sessionID,
            jobID: fixture.session.jobID,
            requestFingerprint: try ConnectedCorpusRequestFingerprint.make(for: changed),
            protocolVersion: fixture.session.protocolVersion,
            partitionTargetBytes: fixture.session.partitionTargetBytes,
            createdAt: fixture.session.createdAt,
            peerBinding: fixture.session.peerBinding
        )
        XCTAssertThrowsError(try fixture.store.createOrRestore(
            origin: .interactiveIPhone,
            session: changedSession,
            manifest: changed
        )) { error in
            XCTAssertEqual(error as? ConnectedCorpusOutboundStoreError, .requestChanged)
        }
    }

    private enum TestError: Error {
        case simulatedCrash
        case unexpectedProduction
    }

    private struct Fixture {
        let root: URL
        let store: ConnectedCorpusOutboundStore
        let settings: AdvancedExportSettings
        let dates: [Date]
        let manifest: ConnectedCorpusExportManifest
        let session: ConnectedCorpusTransferSession
    }

    private func makeFixture(
        dayCount: Int,
        origin: ConnectedCorpusOutboundOrigin = .interactiveIPhone,
        protocolVersion: Int = 2,
        includeCLIRequest: Bool = false,
        sourceInstallationID: UUID? = nil,
        destinationInstallationID: UUID? = nil,
        now: @escaping () -> Date = { Date(timeIntervalSince1970: 1_800_000_000) }
    ) throws -> Fixture {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent("durable-sender-tests-\(UUID().uuidString)", isDirectory: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        let suite = "ConnectedCorpusDurableSenderTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retainedSettings.append(settings)
        settings.exportFormats = [.json]
        let start = Calendar.current.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let dates = (0..<dayCount).compactMap {
            Calendar.current.date(byAdding: .day, value: $0, to: start)
        }
        let manifest = makeManifest(dates: dates, settings: settings, createdAt: now())
        let jobID = UUID()
        let session = ConnectedCorpusTransferSession(
            sessionID: UUID(),
            jobID: jobID,
            requestFingerprint: try ConnectedCorpusRequestFingerprint.make(for: manifest),
            protocolVersion: protocolVersion,
            partitionTargetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes,
            createdAt: manifest.createdAt,
            peerBinding: ConnectedCorpusPeerBinding(
                sourceInstallationID: sourceInstallationID ?? UUID(),
                destinationInstallationID: destinationInstallationID ?? UUID()
            )
        )
        let store = ConnectedCorpusOutboundStore(rootURL: root, now: now)
        let macRequest = includeCLIRequest ? IPhoneExportRequest(
            jobID: session.jobID,
            createdAt: manifest.createdAt,
            dateRangeStart: manifest.dateRangeStart,
            dateRangeEnd: manifest.dateRangeEnd,
            requestedBy: .cli,
            settingsPolicy: .requestedDatesOnly,
            responseMode: .writeFiles
        ) : nil
        _ = try store.createOrRestore(
            origin: origin,
            session: session,
            manifest: manifest,
            macRequest: macRequest
        )
        return Fixture(
            root: root,
            store: store,
            settings: settings,
            dates: dates,
            manifest: manifest,
            session: session
        )
    }

    private func makeManifest(
        dates: [Date],
        settings: AdvancedExportSettings,
        createdAt: Date
    ) -> ConnectedCorpusExportManifest {
        ConnectedCorpusExportManifest(
            mode: .writeFiles,
            createdAt: createdAt,
            sourceDeviceName: "Durable Test iPhone",
            sourceTimeZoneIdentifier: TimeZone.current.identifier,
            dateRangeStart: dates.first!,
            dateRangeEnd: dates.last!,
            requestedDates: dates,
            requestedDateIdentifiers: dates.map(dayString),
            transferDates: dates,
            settingsSnapshot: .from(settings),
            requestedTarget: nil
        )
    }

    private func makeSmallItem(
        date: Date,
        protocolVersion: Int = 2
    ) throws -> ConnectedCorpusSpoolItem {
        try ConnectedCorpusSpoolItem.encode(
            ConnectedCorpusHealthDayPayload(
                sourceDate: date,
                isRequestedDate: true,
                record: HealthData(date: date, activity: ActivityData(steps: 456)),
                externalDailyRecords: [],
                failure: nil
            ),
            kind: .macHealthDay,
            sourceDate: date,
            isRequestedDate: true,
            protocolVersion: protocolVersion
        )
    }

    private func makeLargeItem(date: Date, bytes: Int) throws -> ConnectedCorpusSpoolItem {
        let url = try ConnectedTransferFile.makeRestrictedTemporaryFile(prefix: "durable-large-item")
        let handle = try FileHandle(forWritingTo: url)
        let chunk = Data(repeating: 0x5a, count: 1_024 * 1_024)
        for _ in 0..<(bytes / chunk.count) { try handle.write(contentsOf: chunk) }
        try handle.synchronize()
        try handle.close()
        return ConnectedCorpusSpoolItem(
            itemID: UUID(),
            kind: .macHealthDay,
            sourceDate: date,
            isRequestedDate: true,
            file: try ConnectedTransferFile.inspect(url)
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

    private func waitUntil(
        timeoutIterations: Int = 400,
        condition: @escaping @MainActor () -> Bool
    ) async {
        for _ in 0..<timeoutIterations {
            if condition() { return }
            try? await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("Timed out waiting for asynchronous durable sender state")
    }

    private static func disposition(
        for open: ConnectedCorpusTransferOpen,
        kind: ConnectedCorpusTransferDispositionKind,
        next: Int
    ) -> ConnectedCorpusTransferDisposition {
        ConnectedCorpusTransferDisposition(
            sessionID: open.session.sessionID,
            jobID: open.session.jobID,
            partitionIndex: open.partition.index,
            partitionSHA256: open.partition.sha256,
            disposition: kind,
            nextPartitionIndex: next
        )
    }

    #if os(iOS)
    private final class FastReconnectHarness {
        private var firstOpenContinuation: CheckedContinuation<Void, Never>?
        private var secondOpenContinuation: CheckedContinuation<Void, Never>?
        private var resumedOpenContinuation: CheckedContinuation<Void, Never>?
        private(set) var firstOpenStarted = false
        private(set) var secondOpenStarted = false
        private(set) var resumedOpenStarted = false
        private(set) var openCount = 0

        func releaseFirstOpen() {
            firstOpenContinuation?.resume()
            firstOpenContinuation = nil
        }

        func releaseSecondOpen() {
            secondOpenContinuation?.resume()
            secondOpenContinuation = nil
        }

        func releaseResumedOpen() {
            resumedOpenContinuation?.resume()
            resumedOpenContinuation = nil
        }

        func transport() -> ConnectedCorpusSender.Transport {
            ConnectedCorpusSender.Transport(
                open: { [self] request in
                    openCount += 1
                    switch openCount {
                    case 1:
                        firstOpenStarted = true
                        await withCheckedContinuation { firstOpenContinuation = $0 }
                        return nil
                    case 2:
                        secondOpenStarted = true
                        await withCheckedContinuation { secondOpenContinuation = $0 }
                        return nil
                    default:
                        resumedOpenStarted = true
                        await withCheckedContinuation { resumedOpenContinuation = $0 }
                        return ConnectedCorpusDurableSenderTests.disposition(
                            for: request,
                            kind: .accept,
                            next: request.partition.index
                        )
                    }
                },
                sendPartition: { file, _, transferID, progress in
                    progress(1, 1)
                    return .success(ConnectedTransferFinalAck(
                        transferID: transferID,
                        accepted: true,
                        sha256: file.sha256,
                        message: nil
                    ))
                },
                finalize: { request, _ in
                    ConnectedCorpusTransferFinalAck(
                        sessionID: request.sessionID,
                        jobID: request.jobID,
                        accepted: true,
                        requestFingerprint: request.requestFingerprint,
                        finalPartitionSHA256: request.finalPartitionSHA256,
                        successCount: 1,
                        totalCount: 1
                    )
                },
                cancel: { request in
                    ConnectedCorpusTransferCancelAck(
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
    #endif

    private final class Harness {
        struct TransferCall {
            let file: ConnectedTransferPreparedFile
            let manifest: ConnectedTransferManifest
            let transferID: UUID
        }

        var opens: [ConnectedCorpusTransferOpen] = []
        var transfers: [TransferCall] = []
        var finalizations: [ConnectedCorpusTransferFinalize] = []
        var openResponse: ((ConnectedCorpusTransferOpen) -> ConnectedCorpusTransferDisposition?)?
        var transferResponse: ((ConnectedTransferPreparedFile, ConnectedTransferManifest, UUID) -> ConnectedTransferSendResult)?
        var finalizeResponse: ((ConnectedCorpusTransferFinalize) -> ConnectedCorpusTransferFinalAck?)?

        func transport() -> ConnectedCorpusSender.Transport {
            ConnectedCorpusSender.Transport(
                open: { [self] request in
                    opens.append(request)
                    if let openResponse { return openResponse(request) }
                    return ConnectedCorpusDurableSenderTests.disposition(
                        for: request,
                        kind: request.partition.index == 0
                            ? ConnectedCorpusTransferDispositionKind.accept
                            : ConnectedCorpusTransferDispositionKind.resume,
                        next: request.partition.index
                    )
                },
                sendPartition: { [self] file, manifest, transferID, progress in
                    transfers.append(TransferCall(file: file, manifest: manifest, transferID: transferID))
                    progress(1, 1)
                    return transferResponse?(file, manifest, transferID) ?? .success(
                        ConnectedTransferFinalAck(
                            transferID: transferID,
                            accepted: true,
                            sha256: file.sha256,
                            message: nil
                        )
                    )
                },
                finalize: { [self] request, _ in
                    finalizations.append(request)
                    if let finalizeResponse { return finalizeResponse(request) }
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
                cancel: { request in
                    ConnectedCorpusTransferCancelAck(
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
