#if os(macOS)
import Foundation
import Testing
@testable import HealthMd

@MainActor
struct ConnectedMorningReceiverTests {
    // STATIC RETENTION JUSTIFICATION: Match docs/testing/lifecycle-audit.md;
    // these observation fixtures contain only isolated synthetic state.
    private static var retained: [AnyObject] = []

    @Test(arguments: ["daily", "range", "provider", "warning", "resume"])
    func receiverStagesWholeMorningCorpusAndReplaysRetainedPlan(mode: String) async throws {
        let fixture = try await fixture(mode: mode)
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let assembler = try ConnectedCorpusPartitionAssembler(sessionID: fixture.session.sessionID,
            jobID: fixture.session.jobID, targetBytes: fixture.session.partitionTargetBytes)
        let item = try await ConnectedCorpusSpoolItem.encodeHealthDay(fixture.payload, sourceDate: fixture.owner,
            isRequestedDate: true, protocolVersion: fixture.session.protocolVersion)
        assembler.append(item)
        let partition = try #require(try assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: fixture.sessions)
        let opening = ConnectedCorpusTransferOpen(session: fixture.session, partition: partition.descriptor,
            exportManifest: fixture.manifest)
        #expect(manager.open(opening, vaultManager: fixture.vault).disposition == .accept)
        try await manager.applyPartition(fileURL: partition.file.url, descriptor: partition.descriptor, vaultManager: fixture.vault)
        #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path).isEmpty)
        let finalize = ConnectedCorpusTransferFinalize(sessionID: fixture.session.sessionID, jobID: fixture.session.jobID,
            requestFingerprint: fixture.session.requestFingerprint, partitionCount: 1,
            totalByteCount: partition.descriptor.byteCount, finalPartitionSHA256: partition.descriptor.sha256)
        let outcome: MacCorpusFinalizeOutcome
        if mode == "resume" {
            manager.failNextPostRenameRangePlanSyncForTesting = true
            guard case .inProgress = try await manager.finalize(finalize, vaultManager: fixture.vault) else {
                Issue.record("Expected a durably stored plan before destination writes"); return
            }
            #expect(try FileManager.default.contentsOfDirectory(atPath: fixture.destination.path).isEmpty)
            let journal = fixture.sessions.appendingPathComponent(fixture.session.sessionID.uuidString).appendingPathComponent("journal.json")
            let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as? [String: Any])
            let plan = try #require(object["receivedRangePlan"] as? [String: Any])
            #expect(plan["version"] as? Int == 1)
            #expect(plan["notes"] == nil && plan["nextNoteIndex"] == nil)
            #expect(try planDigest(plan) == plan["immutablePlanSHA256"] as? String)
            let rejecting = NoReplan()
            let vault = makeVault(root: fixture.destination, planner: rejecting)
            outcome = try await MacCorpusExportSessionManager(rootURL: fixture.sessions).finalize(finalize, vaultManager: vault)
            #expect(rejecting.calls == 0)
        } else { outcome = try await manager.finalize(finalize, vaultManager: fixture.vault) }
        guard case .files(let result, let acknowledgement) = outcome else {
            Issue.record("Morning corpus must produce committed files"); return
        }
        let providerCount = fixture.payload.externalDailyRecords.count
        #expect(result.totalFilesWritten == (mode == "range" ? 8 : 4) + providerCount)
        #expect(result.externalRecordFileCount == providerCount)
        #expect(result.hasConsistentFileAccounting)
        #expect(result.completedDates == [fixture.owner])
        #expect(acknowledgement.completedDates == [fixture.owner])
        let written = try destinationFiles(in: fixture.destination)
        #expect(written.count == result.totalFilesWritten)
        let operation = try ConnectedMacDailyExportOperation.resolve(settingsSnapshot: fixture.manifest.settingsSnapshot,
            declaredPin: fixture.manifest.effectiveAppleExportEnginePin, supportsRangePlan: true)
        let ownerDates: Set<String> = [fixture.ownerID]
        let frozenZone = try #require(operation.settingsSnapshot.calendarTimeZoneIdentifier)
        let requestedRange = try mode == "range" ? HealthRollupRangeRequest(ownerDateIdentifiers: ownerDates,
            calendarTimeZoneIdentifier: frozenZone) : nil
        let source = try #require(fixture.payload.record)
        let baseline = try #require(try await fixture.vault.materializeHealthDataRange([source],
            settingsSnapshot: operation.settingsSnapshot, operationSurface: .localVaultRangeWithoutSideEffects,
            dailyOutputOwnerDates: ownerDates, requestedRange: requestedRange,
            operationIdentity: .init(requestID: fixture.session.jobID.uuidString.lowercased(),
                sessionID: fixture.session.sessionID.uuidString.lowercased(), capturedAt: fixture.manifest.createdAt,
                calendarTimeZoneIdentifier: frozenZone)))
        for artifact in baseline.operation.artifacts {
            #expect(written[artifact.artifact.relativePath] == (try artifact.artifact.content.materializedData()))
        }
        let dailyJSON = try #require(baseline.operation.artifacts.first { $0.kind == .daily && $0.format == .json })
        let json = try #require(written[dailyJSON.artifact.relativePath])
        let object = try #require(JSONSerialization.jsonObject(with: json) as? [String: Any])
        #expect(object["schema_version"] as? Int == 11)
        let sleep = try #require(object["sleep"] as? [String: Any])
        #expect(sleep["totalDuration"] as? Double == 97_200.5)
        let stage = try #require((sleep["sleepStages"] as? [[String: Any]])?.first)
        #expect(stage["durationSeconds"] as? Double == 97_200.5)
        #expect((stage["metadata"] as? [String: String])?["synthetic"] == "connected-whole-session")
        if let external = fixture.payload.externalDailyRecords.first {
            let data = try #require(written["Health/integrations/whoop/\(fixture.ownerID).json"])
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            #expect(try decoder.decode(ExternalDailyRecord.self, from: data) == external)
        }
        let replay = try await MacCorpusExportSessionManager(rootURL: fixture.sessions).finalize(finalize, vaultManager: fixture.vault)
        guard case .replay(_, let retainedResult) = replay else { Issue.record("Terminal ACK must replay"); return }
        #expect(retainedResult?.totalFilesWritten == result.totalFilesWritten)
        for (path, bytes) in written { #expect(try Data(contentsOf: fixture.destination.appendingPathComponent(path)) == bytes) }
    }

    @Test(arguments: ["foreign-day", "duplicate-sidecar", "corrupt-retained-sidecar", "mutated-materialization"])
    func invalidSidecarsCannotWriteOrReplan(damage: String) async throws {
        let fixture = try await fixture(mode: "provider")
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        var external = fixture.payload.externalDailyRecords
        if damage == "foreign-day" { external[0].date = "2000-01-01" }
        if damage == "duplicate-sidecar" { external += external }
        let payload = ConnectedCorpusHealthDayPayload(sourceDate: fixture.owner, isRequestedDate: true,
            record: fixture.payload.record, externalDailyRecords: external, failure: nil)
        let assembler = try ConnectedCorpusPartitionAssembler(sessionID: fixture.session.sessionID,
            jobID: fixture.session.jobID, targetBytes: fixture.session.partitionTargetBytes)
        assembler.append(try await ConnectedCorpusSpoolItem.encodeHealthDay(payload, sourceDate: fixture.owner,
            isRequestedDate: true, protocolVersion: fixture.session.protocolVersion))
        let partition = try #require(try assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: fixture.sessions)
        #expect(manager.open(.init(session: fixture.session, partition: partition.descriptor,
            exportManifest: fixture.manifest), vaultManager: fixture.vault).disposition == .accept)
        try await manager.applyPartition(fileURL: partition.file.url, descriptor: partition.descriptor, vaultManager: fixture.vault)
        let finalize = ConnectedCorpusTransferFinalize(sessionID: fixture.session.sessionID, jobID: fixture.session.jobID,
            requestFingerprint: fixture.session.requestFingerprint, partitionCount: 1,
            totalByteCount: partition.descriptor.byteCount, finalPartitionSHA256: partition.descriptor.sha256)
        if damage == "mutated-materialization" {
            manager.beforeReceivedRangeSpoolForTesting = { materialized in
                let file = try #require(materialized.providerSidecars.first).artifact
                let original = try Data(contentsOf: file.url)
                let replacement = Data(String(decoding: original, as: UTF8.self)
                    .replacingOccurrences(of: "retained-connected-source", with: "replaced-connected-source").utf8)
                try #require(replacement.count == original.count && replacement != original)
                try replacement.write(to: file.url)
            }
            await #expect(throws: CocoaError.self) {
                _ = try await manager.finalize(finalize, vaultManager: fixture.vault)
            }
        } else if damage == "corrupt-retained-sidecar" {
            manager.failNextPostRenameRangePlanSyncForTesting = true
            guard case .inProgress = try await manager.finalize(finalize, vaultManager: fixture.vault) else {
                Issue.record("Expected retained plan"); return
            }
            let directory = fixture.sessions.appendingPathComponent(fixture.session.sessionID.uuidString)
            let journalURL = directory.appendingPathComponent("journal.json")
            let original = try Data(contentsOf: journalURL)
            let object = try #require(JSONSerialization.jsonObject(with: original) as? [String: Any])
            let plan = try #require(object["receivedRangePlan"] as? [String: Any])
            let artifacts = try #require(plan["artifacts"] as? [[String: Any]])
            let sidecar = try #require(artifacts.first { $0["kind"] as? String == "providerSidecar" })
            let path = try #require(sidecar["spoolRelativePath"] as? String)
            let url = directory.appendingPathComponent(path)
            var bytes = try Data(contentsOf: url); bytes[0] ^= 1; try bytes.write(to: url)
            let rejecting = NoReplan()
            let vault = makeVault(root: fixture.destination, planner: rejecting)
            await #expect(throws: ConnectedCorpusTransferModelError.self) {
                _ = try await MacCorpusExportSessionManager(rootURL: fixture.sessions).finalize(finalize, vaultManager: vault)
            }
            #expect(rejecting.calls == 0)
            #expect(try Data(contentsOf: journalURL) == original)
            #expect(try Data(contentsOf: url) == bytes)
        } else if damage == "foreign-day" {
            await #expect(throws: ConnectedMacDailyExportOperation.ResolutionError.self) {
                _ = try await manager.finalize(finalize, vaultManager: fixture.vault)
            }
        } else {
            await #expect(throws: ConnectedCorpusTransferModelError.self) {
                _ = try await manager.finalize(finalize, vaultManager: fixture.vault)
            }
        }
        #expect(try destinationFiles(in: fixture.destination).isEmpty)
    }

    @Test(arguments: ["notes", "notes-only", "notes-skip", "notes-provider", "notes-resume", "notes-crash", "notes-range", "notes-summary-fallback"])
    func scopedNotesCommitAndResumeWithoutSourceRendering(mode: String) async throws {
        let f = try await fixture(mode: mode)
        defer { try? FileManager.default.removeItem(at: f.root) }
        let note = f.destination.appendingPathComponent("Journal/\(f.ownerID).md")
        let personal = "---\r\nnotes: |\r\n  Personal journal\r\nsleep_deep_hours: 9\r\n---\r\nMy introduction.\r\n"
        if mode != "notes-skip" {
            try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
            try personal.write(to: note, atomically: true, encoding: .utf8)
        }
        let (manager, finalize) = try await openAndApply(f)
        let outcome: MacCorpusFinalizeOutcome
        if mode == "notes-resume" || mode == "notes-crash" {
            if mode == "notes-resume" {
                manager.failNextPostRenameRangePlanSyncForTesting = true
                guard case .inProgress = try await manager.finalize(finalize, vaultManager: f.vault) else { Issue.record("Expected retained plan"); return }
                #expect(try String(contentsOf: note, encoding: .utf8) == personal)
            } else {
                manager.afterReceivedNoteCommitForTesting = { throw CocoaError(.fileWriteUnknown) }
                await #expect(throws: CocoaError.self) { _ = try await manager.finalize(finalize, vaultManager: f.vault) }
                #expect(try String(contentsOf: note, encoding: .utf8) != personal)
            }
            let rejecting = NoReplan()
            let vault = makeVault(root: f.destination, planner: rejecting)
            outcome = try await MacCorpusExportSessionManager(rootURL: f.sessions).finalize(finalize, vaultManager: vault)
            #expect(rejecting.calls == 0)
        } else { outcome = try await manager.finalize(finalize, vaultManager: f.vault) }
        guard case .files(let result, _) = outcome else { Issue.record("Expected terminal note result"); return }
        let skipped = mode == "notes-skip"
        let only = skipped || mode == "notes-only"
        #expect(result.dailyNoteUpdateCount == (skipped ? 0 : 1))
        #expect(result.dailyNoteSkipCount == (skipped ? 1 : 0))
        #expect(result.successCount == (skipped ? 0 : 1))
        #expect(result.totalFilesWritten == (only ? 0 : (mode == "notes-range" ? 8 : 4) + f.payload.externalDailyRecords.count))
        #expect(result.hasConsistentFileAccounting)
        let written = try destinationFiles(in: f.destination)
        #expect(written.count == result.totalFilesWritten + result.dailyNoteUpdateCount)
        if !skipped {
            let text = try String(contentsOf: note, encoding: .utf8)
            #expect(text.contains("Personal journal\r\n"))
            let properties = try #require(MarkdownMerger.frontmatterProperties(named: ["healthmd_daily_injection_v1"], in: text))
            let quoted = try #require(properties.first?.split(separator: ":", maxSplits: 1).last)
            let scalar = try JSONDecoder().decode(String.self, from: Data(quoted.trimmingCharacters(in: .whitespacesAndNewlines).utf8))
            let envelope = try #require(JSONSerialization.jsonObject(with: Data(scalar.utf8)) as? [String: Any])
            let json = try #require(envelope["record_json"] as? String)
            let record = try #require(JSONSerialization.jsonObject(with: Data(json.utf8)) as? [String: Any])
            #expect(record["date"] as? String == f.ownerID)
            #expect((record["sleep"] as? [String: Any])?["totalDuration"] as? Double == 97_200.5)
            if let path = ProcessInfo.processInfo.environment["HEALTHMD_CONNECTED_NOTE_FIXTURE_DIR"] {
                let directory = URL(fileURLWithPath: path, isDirectory: true)
                try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
                try Data(text.utf8).write(to: directory.appendingPathComponent(mode + ".md"))
                try Data(json.utf8).write(to: directory.appendingPathComponent(mode + ".json"))
                if let daily = written["Health/\(f.ownerID).json"] {
                    try daily.write(to: directory.appendingPathComponent(mode + ".daily.json"))
                }
            }
        }
        guard case .replay(_, let replay) = try await MacCorpusExportSessionManager(rootURL: f.sessions).finalize(finalize, vaultManager: f.vault) else {
            Issue.record("Expected exact terminal acknowledgement replay"); return
        }
        #expect(replay?.dailyNoteUpdateCount == result.dailyNoteUpdateCount)
        #expect(replay?.dailyNoteSkipCount == result.dailyNoteSkipCount)
        #expect(try destinationFiles(in: f.destination) == written)
    }

    @Test(arguments: ["edit", "corrupt", "downgrade", "edit-after-write", "symlink-spool",
        "frontier", "foreign-owner", "path-collision", "quota-overflow", "rebound"])
    func retainedNoteDamageCannotWriteCompanionsOrReplan(damage: String) async throws {
        let f = try await fixture(mode: "notes")
        defer { try? FileManager.default.removeItem(at: f.root) }
        let note = f.destination.appendingPathComponent("Journal/\(f.ownerID).md")
        try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        try "Personal note.\r\n".write(to: note, atomically: true, encoding: .utf8)
        let (manager, finalize) = try await openAndApply(f)
        if damage == "edit-after-write" {
            manager.afterReceivedNoteCommitForTesting = { throw CocoaError(.fileWriteUnknown) }
            await #expect(throws: CocoaError.self) { _ = try await manager.finalize(finalize, vaultManager: f.vault) }
        } else {
            manager.failNextPostRenameRangePlanSyncForTesting = true
            guard case .inProgress = try await manager.finalize(finalize, vaultManager: f.vault) else { Issue.record("Expected retained plan"); return }
        }
        let directory = f.sessions.appendingPathComponent(f.session.sessionID.uuidString)
        let journal = directory.appendingPathComponent("journal.json")
        var object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as? [String: Any])
        var plan = try #require(object["receivedRangePlan"] as? [String: Any])
        #expect(plan["version"] as? Int == 2)
        var notes = try #require(plan["notes"] as? [[String: Any]])
        #expect(try planDigest(plan) == plan["immutablePlanSHA256"] as? String)
        if damage == "corrupt" || damage == "symlink-spool" {
            let content = try #require(notes.first?["content"] as? [String: Any])
            let path = try #require(content["spoolRelativePath"] as? String)
            let file = directory.appendingPathComponent(path)
            var bytes = try Data(contentsOf: file)
            if damage == "corrupt" { bytes[0] ^= 1; try bytes.write(to: file) }
            else {
                let foreign = f.root.appendingPathComponent("foreign-note-artifact")
                try bytes.write(to: foreign); try FileManager.default.removeItem(at: file)
                try FileManager.default.createSymbolicLink(at: file, withDestinationURL: foreign)
            }
        } else if ["downgrade", "frontier", "foreign-owner", "path-collision", "quota-overflow"].contains(damage) {
            if damage == "downgrade" {
                plan["version"] = 1; plan.removeValue(forKey: "notes"); plan.removeValue(forKey: "nextNoteIndex")
            } else if damage == "frontier" { plan["nextNoteIndex"] = notes.count + 1 }
            else if damage == "quota-overflow" {
                plan["dataDictionary"] = ["relativePath": "Health/dictionary.json",
                    "spoolRelativePath": "finalization/data-dictionary.artifact", "mediaType": "application/json",
                    "byteCount": NSNumber(value: UInt64.max), "sha256": String(repeating: "a", count: 64)] as [String: Any]
            } else if damage == "foreign-owner" {
                let date = try #require(notes[0]["ownerDate"] as? Double)
                notes[0]["ownerDate"] = date - 86_400; plan["notes"] = notes
            } else {
                let artifacts = try #require(plan["artifacts"] as? [[String: Any]])
                let path = try #require(artifacts.first?["relativePath"] as? String)
                notes[0]["relativePath"] = path
                var content = try #require(notes[0]["content"] as? [String: Any]); content["relativePath"] = path
                notes[0]["content"] = content; plan["notes"] = notes
            }
            plan["immutablePlanSHA256"] = try planDigest(plan)
            object["receivedRangePlan"] = plan; try JSONSerialization.data(withJSONObject: object).write(to: journal)
        } else if damage == "rebound" {
            try FileManager.default.moveItem(at: f.destination, to: f.root.appendingPathComponent("old-vault"))
            try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
            try "Replacement folder.\r\n".write(to: note, atomically: true, encoding: .utf8)
        } else { try "Latest personal edit.\r\n".write(to: note, atomically: true, encoding: .utf8) }
        let before = try destinationFiles(in: f.destination)
        let rejecting = NoReplan()
        let vault = makeVault(root: f.destination, planner: rejecting)
        await #expect(throws: ConnectedCorpusTransferModelError.self) {
            _ = try await MacCorpusExportSessionManager(rootURL: f.sessions).finalize(finalize, vaultManager: vault)
        }
        #expect(rejecting.calls == 0)
        #expect(try destinationFiles(in: f.destination) == before)
    }

    @Test func summaryOnlyKeepsSavedNotePreferenceWithoutChangingTheJournal() async throws {
        let f = try await fixture(mode: "notes-summary-only")
        defer { try? FileManager.default.removeItem(at: f.root) }
        let note = f.destination.appendingPathComponent("Journal/\(f.ownerID).md")
        try FileManager.default.createDirectory(at: note.deletingLastPathComponent(), withIntermediateDirectories: true)
        let personal = Data("Personal journal stays untouched.\r\n".utf8)
        try personal.write(to: note)
        let (manager, finalize) = try await openAndApply(f)
        guard case .files(let result, _) = try await manager.finalize(finalize, vaultManager: f.vault) else {
            Issue.record("Expected summary-only result"); return
        }
        #expect(result.successCount == 1 && result.totalFilesWritten == 4)
        #expect(result.dailyNoteUpdateCount == 0 && result.dailyNoteSkipCount == 0)
        #expect(try Data(contentsOf: note) == personal)
        #expect(result.hasConsistentFileAccounting)
    }

    @Test func taskCancellationAfterNotePublicationDoesNotAcknowledgeIt() async throws {
        let f = try await fixture(mode: "notes-only")
        defer { try? FileManager.default.removeItem(at: f.root) }
        let (manager, finalize) = try await openAndApply(f)
        manager.afterReceivedNoteCommitForTesting = {
            withUnsafeCurrentTask { task in
                #expect(task != nil)
                task?.cancel()
            }
        }
        let job = Task { @MainActor in try await manager.finalize(finalize, vaultManager: f.vault) }
        await #expect(throws: CancellationError.self) { _ = try await job.value }
        let note = f.destination.appendingPathComponent("Journal/\(f.ownerID).md")
        let written = try Data(contentsOf: note)
        let journal = f.sessions.appendingPathComponent(f.session.sessionID.uuidString).appendingPathComponent("journal.json")
        let object = try #require(JSONSerialization.jsonObject(with: Data(contentsOf: journal)) as? [String: Any])
        let plan = try #require(object["receivedRangePlan"] as? [String: Any])
        #expect(plan["nextNoteIndex"] as? Int == 0)
        let rejecting = NoReplan()
        let vault = makeVault(root: f.destination, planner: rejecting)
        let resumed = try await MacCorpusExportSessionManager(rootURL: f.sessions).finalize(finalize, vaultManager: vault)
        guard case .files(let result, _) = resumed else { Issue.record("Expected exact replay after task cancellation"); return }
        #expect(rejecting.calls == 0)
        #expect(result.successCount == 1 && result.dailyNoteUpdateCount == 1 && result.totalFilesWritten == 0)
        #expect(try Data(contentsOf: note) == written)
    }

    private func planDigest(_ plan: [String: Any]) throws -> String {
        try MacCorpusExportSessionManager.receivedRangePlanDigestForTesting(
            JSONSerialization.data(withJSONObject: plan))
    }

    private func openAndApply(_ f: Fixture) async throws -> (MacCorpusExportSessionManager, ConnectedCorpusTransferFinalize) {
        let assembler = try ConnectedCorpusPartitionAssembler(sessionID: f.session.sessionID, jobID: f.session.jobID,
            targetBytes: f.session.partitionTargetBytes)
        for date in f.manifest.transferDates {
            let payload = date == f.owner ? f.payload : ConnectedCorpusHealthDayPayload(sourceDate: date,
                isRequestedDate: false, record: HealthData(date: date,
                    timeContext: .init(timeZone: TimeZone(secondsFromGMT: 0)!, sleepDayAttribution: .morningEnds)),
                externalDailyRecords: [], failure: nil)
            assembler.append(try await ConnectedCorpusSpoolItem.encodeHealthDay(payload, sourceDate: date,
                isRequestedDate: date == f.owner, protocolVersion: f.session.protocolVersion))
        }
        let partition = try #require(try assembler.makeNextPartition(force: true))
        defer { partition.remove() }
        let manager = MacCorpusExportSessionManager(rootURL: f.sessions)
        #expect(manager.open(.init(session: f.session, partition: partition.descriptor, exportManifest: f.manifest), vaultManager: f.vault).disposition == .accept)
        try await manager.applyPartition(fileURL: partition.file.url, descriptor: partition.descriptor, vaultManager: f.vault)
        return (manager, .init(sessionID: f.session.sessionID, jobID: f.session.jobID, requestFingerprint: f.session.requestFingerprint,
            partitionCount: 1, totalByteCount: partition.descriptor.byteCount, finalPartitionSHA256: partition.descriptor.sha256))
    }

    private func destinationFiles(in root: URL) throws -> [String: Data] {
        let base = root.standardizedFileURL.resolvingSymlinksInPath()
        let files = try #require(FileManager.default.enumerator(at: base, includingPropertiesForKeys: [.isRegularFileKey]))
        var result: [String: Data] = [:]
        for case let url as URL in files where (try url.resourceValues(forKeys: [.isRegularFileKey])).isRegularFile == true {
            let file = url.standardizedFileURL.resolvingSymlinksInPath()
            try #require(file.path.hasPrefix(base.path + "/"))
            result[String(file.path.dropFirst(base.path.count + 1))] = try Data(contentsOf: file)
        }
        return result
    }

    private struct Fixture {
        let root: URL
        let sessions: URL
        let destination: URL
        let vault: VaultManager
        let manifest: ConnectedCorpusExportManifest
        let session: ConnectedCorpusTransferSession
        let payload: ConnectedCorpusHealthDayPayload
        let owner: Date
        let ownerID: String
    }

    private func fixture(mode: String) async throws -> Fixture {
        let suite = "ConnectedMorningReceiver.\(UUID())"
        let defaults = try #require(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = AdvancedExportSettings(userDefaults: defaults)
        Self.retained.append(settings)
        let notesOnly = mode == "notes-only" || mode == "notes-skip"
        settings.exportFormats = notesOnly ? [] : Set(ExportFormat.allCases)
        settings.writeMode = .overwrite
        settings.includeDataDictionary = notesOnly
        settings.generateRangeSummary = mode == "range" || mode == "notes-range" || mode == "notes-summary-only" || mode == "notes-summary-fallback" || notesOnly
        settings.summaryOnlyExport = notesOnly || mode == "notes-summary-only" || mode == "notes-summary-fallback"
        settings.archiveExportFiles = notesOnly
        settings.dailyNoteInjection.enabled = mode.hasPrefix("notes")
        settings.dailyNoteInjection.dailyNotesOnly = notesOnly
        settings.dailyNoteInjection.createIfMissing = mode != "notes-skip"
        settings.dailyNoteInjection.folderPath = "Journal"
        settings.individualTracking.globalEnabled = notesOnly
        settings.detailPolicy = .detailedTimeSeries
        settings.metricSelection.enabledMetrics = ["sleep_total", "sleep_core", "sleep_bedtime", "sleep_wake"]
        let zone = try #require(TimeZone(identifier: "UTC"))
        settings.executionSleepCaptureContext = .init(timeZone: zone, sleepDayAttribution: .morningEnds)
        settings.exportTimeZoneOverride = zone
        let snapshot = await MacExportJobBuilder.settingsSnapshotForNewConnectedMacOperation(settings,
            healthSubfolder: "Health", calendarTimeZone: zone, hasNativeOnlyCompanionAction: false,
            operationSurface: .connectedReceivedRangeWithoutSideEffects)
        #expect(try #require(snapshot.appleExportEnginePin).isWakeDate)
        var calendar = Calendar(identifier: .gregorian); calendar.timeZone = zone
        let owner = calendar.startOfDay(for: ExportFixtures.referenceDate)
        let ownerID = APIExportClient.dayString(from: owner, timeZone: zone)
        let withProvider = ["provider", "warning", "resume", "notes-provider"].contains(mode)
        let external = withProvider ? [ExternalDailyRecord(provider: .whoop, date: ownerID, fetchedAt: owner,
            payloads: mode == "warning" ? [] : [.init(name: "cycles", endpoint: "https://synthetic.invalid/cycles",
                statusCode: 200, fetchedAt: owner, data: .object(["synthetic": .string("retained-connected-source")]))],
            warnings: mode == "warning" ? ["Synthetic unavailable connection"] : [])] : []
        let start = owner.addingTimeInterval(-14 * 3600 - 0.25), end = owner.addingTimeInterval(13 * 3600 + 0.25)
        let record = HealthData(date: owner, timeContext: .init(timeZone: zone, sleepDayAttribution: .morningEnds),
            sleep: SleepData(totalDuration: end.timeIntervalSince(start), coreSleep: end.timeIntervalSince(start),
                sessionStart: start, sessionEnd: end,
                stages: [.init(stage: "core", startDate: start, endDate: end, metadata: ["synthetic": "connected-whole-session"])]),
            providers: withProvider ? (mode == "warning" ? HealthProviderSections.normalized(from: external)
                : ExportFixtures.whoopDay.providers) : nil)
        let original = ConnectedCorpusExportManifest(mode: .writeFiles, createdAt: Date(), sourceDeviceName: "Synthetic iPhone",
            sourceTimeZoneIdentifier: zone.identifier, dateRangeStart: owner, dateRangeEnd: owner,
            requestedDates: [owner],
            originalRequestedDates: mode == "notes-summary-fallback"
                ? [owner.addingTimeInterval(-10_000 * 86_400), owner.addingTimeInterval(100 * 86_400)] : nil,
            originalCalendarTimeZoneIdentifier: mode == "notes-summary-fallback" ? zone.identifier : nil,
            requestedDateIdentifiers: [ownerID], transferDates: mode == "notes-summary-fallback"
                ? [owner.addingTimeInterval(-10_000 * 86_400), owner, owner.addingTimeInterval(100 * 86_400)] : [owner],
            settingsSnapshot: snapshot,
            requestedTarget: .init(kind: .connectedMac, displayName: "Synthetic", destinationDisplayName: "Synthetic"))
        // Exercise the ordinary wire encoder: private source grants/context must
        // not leak, while the explicit versioned renderer pin retains meaning.
        let bytes = try JSONEncoder().encode(original)
        let manifest = try JSONDecoder().decode(ConnectedCorpusExportManifest.self, from: bytes)
        #expect(manifest.settingsSnapshot.sleepCaptureContext == nil)
        let session = ConnectedCorpusTransferSession(sessionID: UUID(), jobID: UUID(), requestFingerprint: try .make(for: manifest),
            partitionTargetBytes: ConnectedCorpusTransferConstants.minimumPartitionTargetBytes, createdAt: Date())
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("ConnectedMorning-\(UUID())")
        let destination = root.appendingPathComponent("vault")
        try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
        let vault = makeVault(root: destination)
        return Fixture(root: root, sessions: root.appendingPathComponent("sessions"), destination: destination,
            vault: vault, manifest: manifest, session: session,
            payload: .init(sourceDate: owner, isRequestedDate: true, record: record, externalDailyRecords: external, failure: nil),
            owner: owner, ownerID: ownerID)
    }

    private func makeVault(root: URL, planner: (any AppleLooseDailyExportPlanning)? = nil) -> VaultManager {
        let bookmarks = FakeBookmarkResolver(); bookmarks.accessGranted = true
        let vault = VaultManager(defaults: FakeUserDefaults(), fileSystem: SystemFileSystem(), bookmarkResolver: bookmarks,
            appleLooseDailyPlanner: planner ?? AppleLooseDailyExportPlanner())
        vault.setVaultFolder(root)
        Self.retained.append(vault)
        return vault
    }

    @MainActor private final class NoReplan: AppleLooseDailyRangeExportPlanning {
        var calls = 0
        func plan(healthData: HealthData, settingsSnapshot: ExportSettingsSnapshot, surface: AppleExportOperationSurface) async throws -> AppleLooseDailyPlanResolution {
            calls += 1; throw CocoaError(.coderInvalidValue)
        }
        func planRange(healthData: [HealthData], settingsSnapshot: ExportSettingsSnapshot, surface: AppleExportOperationSurface) async throws -> AppleLooseDailyPlanResolution {
            calls += 1; throw CocoaError(.coderInvalidValue)
        }
        func planRange(healthData: [HealthData], dailyOutputOwnerDates: Set<String>, requestedRange: HealthRollupRangeRequest?,
            settingsSnapshot: ExportSettingsSnapshot, surface: AppleExportOperationSurface,
            operationIdentity: AppleExportOperationIdentity?) async throws -> AppleLooseDailyPlanResolution {
            calls += 1; throw CocoaError(.coderInvalidValue)
        }
    }
}
#endif
