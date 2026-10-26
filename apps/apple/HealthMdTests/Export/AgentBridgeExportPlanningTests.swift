import CryptoKit
import Darwin
import Foundation
import HealthMdConnectionCore
import HealthMdCoreRust
import XCTest
#if os(iOS)
import UIKit
#endif
#if canImport(HealthMd)
import HealthKit
@testable import HealthMd
#else
@testable import AgentBridgeRequestSettingsHarness
#endif

@MainActor
final class AgentBridgeExportPlanningTests: XCTestCase {
    // STATIC RETENTION JUSTIFICATION: existing native settings/store tests retain Combine and
    // MainActor objects through process teardown on older iOS runtimes; these use the same owners.
    private static var retainedNativeConfigurationObjects: [AnyObject] = []

    private func nativeState(
        available: Set<String> = ["steps", "heart_rate_avg", "heart_rate_min", "heart_rate_max", "resting_heart_rate", "hrv"],
        zone: String = "America/Los_Angeles", protection: AgentBridgeDiscoveryConfigurationProtection = .locked,
        grants: AgentBridgeDiscoveryNativeGrants = .satisfied, entitlement: AgentBridgeDiscoveryEntitlement = .satisfied,
        foregroundAvailable: Bool = true, protectedDataAvailable: Bool = true
    ) throws -> AgentBridgeNativePlanningFacts {
        try .init(availableNativeMetricIDs: available, sourceCalendarTimezone: AgentBridgeZone(zone), configurationProtection: protection,
                  nativeGrants: grants, entitlement: entitlement, foregroundAvailable: foregroundAvailable, protectedDataAvailable: protectedDataAvailable)
    }

    private func executionRequest(_ rig: Rig, storeDecision: Bool = true, policy: AgentBridgeSettingsPolicy? = nil) throws -> AgentBridgeExecute {
        let plan = try rig.makePlan(policy: policy)
        let binding = try AgentBridgeSemantics.binding(plan)
        if storeDecision {
            try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8),
                authenticatedPeer: rig.peer, authorization: FakeNativeAuthorization(binding: binding))
        }
        let approval = AgentBridgeApproval(approvalId: try id(8), approvedAt: try AgentBridgeUTC("2026-03-09T00:00:00Z"),
            authorityId: plan.authorityReferences.native.authorityId, binding: binding, rights: [.exportExecute])
        return try AgentBridgeExecute(approval: approval, idempotencyKey: id(81), jobId: id(82), plan: plan, requestId: id(83))
    }

    private func cancellationRequest(_ request: AgentBridgeExecute) throws -> AgentBridgeCancel {
        try .init(approvalId: request.approval.approvalId, authorityId: request.plan.authorityReferences.native.authorityId,
            jobId: request.jobId, peer: request.plan.intent.peer,
            requestSha256: AgentBridgeDigest(AgentBridgeV4Codec.sha256(AgentBridgeV4Codec.encode(request))))
    }

    func testCancellationCheckpointIsReadOnlyAndRejectsChangedOrForeignEvidence() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
        let root = rig.directory.appendingPathComponent("captures/" + reservation.job.requestSHA256.rawValue)
        func snapshot() throws -> [String: Data] {
            try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(atPath: root.path).map {
                ($0, try Data(contentsOf: root.appendingPathComponent($0)))
            })
        }
        let spool = try rig.store.openCaptureSpool(reservation, create: true, fileProtection: rig.captureProtection) {}
        let checkpoint: AgentBridgeNativeCaptureSpool.CancellationCheckpoint
        do {
            let day = try AgentBridgeDate("2026-03-08")
            XCTAssertNil(try spool.loadOrBegin(day))
            try spool.commit(day, payload: Data("synthetic".utf8))
            let before = try snapshot()
            checkpoint = try spool.inspectCancellationCheckpoint()
            XCTAssertEqual(checkpoint.capturedDayCount, 1)
            XCTAssertNil(checkpoint.artifactCount); XCTAssertNil(checkpoint.manifestSHA256)
            XCTAssertNil(checkpoint.committedPartitionCount); XCTAssertNil(checkpoint.frontierSHA256)
            XCTAssertNil(checkpoint.completion)
            try spool.requireCancellationCheckpoint(checkpoint)
            XCTAssertEqual(try snapshot(), before)
            XCTAssertThrowsError(try rig.store.openCaptureSpool(reservation, create: false, fileProtection: rig.captureProtection) {}) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .busy)
            }
        } catch { spool.close(); throw error }
        spool.close()
        let retained = try rig.store.openCaptureSpool(reservation, create: false, fileProtection: rig.captureProtection) {}
        defer { retained.close() }
        let before = try snapshot(), reopened = try retained.inspectCancellationCheckpoint()
        XCTAssertEqual(reopened.capturedDayCount, 1)
        XCTAssertThrowsError(try retained.requireCancellationCheckpoint(checkpoint)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .spoolMissingRestartRequired)
        }
        XCTAssertEqual(try snapshot(), before)
        let payload = root.appendingPathComponent("day-2026-03-08.json")
        var bytes = try Data(contentsOf: payload); bytes.append(42)
        try bytes.write(to: payload)
        XCTAssertThrowsError(try retained.requireCancellationCheckpoint(reopened)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .spoolMissingRestartRequired)
        }
        XCTAssertThrowsError(try retained.inspectCancellationCheckpoint()) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .spoolMissingRestartRequired)
        }
    }

    func testUnclaimedCancellationConfirmsOriginalJobAndReplaysWithoutRenewal() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig), job = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer).job
        let cancel = try cancellationRequest(request)
        _ = try rig.service.requestCancellation(cancel, authenticatedPeer: rig.peer); rig.reader.calls = []
        let receipt = try rig.service.finalizeUnclaimedCancellation(cancel, authenticatedPeer: rig.peer)
        XCTAssertEqual(receipt.status, .cancelled); XCTAssertTrue(receipt.sourceAcknowledged)
        XCTAssertEqual(receipt, try job.unclaimedCancellationReceipt())
        let file = rig.directory.appendingPathComponent("state.json"), before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        rig.clock.advance(seconds: 1)
        let restarted = try rig.restartedService()
        XCTAssertEqual(try restarted.finalizeUnclaimedCancellation(cancel, authenticatedPeer: rig.peer), receipt)
        XCTAssertEqual(try restarted.requestCancellation(cancel, authenticatedPeer: rig.peer).terminalReceipt(), receipt)
        XCTAssertThrowsError(try restarted.claimCapture(request, authenticatedPeer: rig.peer)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(try rig.store.snapshot().acceptedJobs, [job]); XCTAssertNil(try rig.store.snapshot().captureClaims)
        XCTAssertTrue(rig.reader.calls.isEmpty)
    }

    func testUnclaimedCancellationRefusesCaptureClaimsOrUnknownSpoolWithoutDeletingIt() throws {
        for mode in ["claim", "orphan", "symlink", "missing_intent"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig), job = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer).job
            if mode == "claim" { _ = try rig.service.claimCapture(request, authenticatedPeer: rig.peer) }
            let cancel = try cancellationRequest(request)
            if mode != "missing_intent" { _ = try rig.service.requestCancellation(cancel, authenticatedPeer: rig.peer) }
            let captures = rig.directory.appendingPathComponent("captures"), outside = rig.parent.appendingPathComponent("synthetic-unrelated")
            if mode == "orphan" {
                try FileManager.default.createDirectory(at: captures.appendingPathComponent(job.requestSHA256.rawValue), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: captures.path)
            }
            if mode == "symlink" {
                try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: false)
                try Data("synthetic".utf8).write(to: outside.appendingPathComponent("sentinel"))
                try FileManager.default.createSymbolicLink(at: captures, withDestinationURL: outside)
            }
            let file = rig.directory.appendingPathComponent("state.json"), before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
            let expected: AgentBridgeValidationError = mode == "claim" ? .busy : mode == "orphan" ? .spoolMissingRestartRequired : .bindingChanged
            XCTAssertThrowsError(try rig.service.finalizeUnclaimedCancellation(cancel, authenticatedPeer: rig.peer)) { XCTAssertEqual($0 as? AgentBridgeValidationError, expected, mode) }
            XCTAssertEqual(try Data(contentsOf: file), before)
            if mode == "orphan" { XCTAssertTrue(FileManager.default.fileExists(atPath: captures.appendingPathComponent(job.requestSHA256.rawValue).path)) }
            if mode == "symlink" { XCTAssertEqual(try Data(contentsOf: outside.appendingPathComponent("sentinel")), Data("synthetic".utf8)) }
        }
    }

    func testAcceptedJobPureReusePreservesDurableIdentityAndRejectsChangedFields() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        let acceptance = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        let job = acceptance.job
        let before = try AgentBridgeV4Codec.canonicalize(JSONEncoder().encode(job))
        for _ in 0..<4 { XCTAssertEqual(try job.request(), request); try job.validate() }
        let copy = job
        XCTAssertEqual(try copy.request(), request); try copy.validate()
        XCTAssertEqual(try AgentBridgeV4Codec.canonicalize(JSONEncoder().encode(copy)), before)
        let restored = try JSONDecoder().decode(AgentBridgeExportAcceptedJob.self, from: before)
        XCTAssertEqual(restored, job); try restored.validate()
        XCTAssertEqual(try restored.request(), request)
        let changed = AgentBridgeExportAcceptedJob(version: job.version, requestBytes: job.requestBytes,
            requestSHA256: try digest("f"), nativeResolution: job.nativeResolution,
            acceptedAt: job.acceptedAt, expiresAt: job.expiresAt)
        XCTAssertNotEqual(changed, job); XCTAssertEqual(try changed.request(), request)
        XCTAssertThrowsError(try changed.validate()); XCTAssertThrowsError(try changed.validate())
        let malformed = AgentBridgeExportAcceptedJob(version: job.version, requestBytes: Data("invalid".utf8),
            requestSHA256: job.requestSHA256, nativeResolution: job.nativeResolution,
            acceptedAt: job.acceptedAt, expiresAt: job.expiresAt)
        XCTAssertThrowsError(try malformed.request()); XCTAssertThrowsError(try malformed.validate())
    }

    func testWarmedAcceptedJobNeverCachesLiveStopExpiryOrPeerAuthority() throws {
        for expired in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig)
            _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
            let cancel = try cancellationRequest(request)
            _ = try rig.service.requestCancellation(cancel, authenticatedPeer: rig.peer)
            let job = try XCTUnwrap(rig.store.snapshot().acceptedJobs?.first)
            for _ in 0..<4 { _ = try job.request(); try job.validate() }
            let stateFile = rig.directory.appendingPathComponent("state.json")
            let before = try Data(contentsOf: stateFile)
            if expired { rig.clock.advance(seconds: 604800) } else { rig.session.revoke() }
            // Structural validity is immutable; current time/trust remain separate mandatory fences.
            try job.validate()
            XCTAssertThrowsError(try rig.service.finalizeUnclaimedCancellation(cancel, authenticatedPeer: rig.peer)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, expired ? .planExpired : .permissionRequired)
            }
            XCTAssertEqual(try Data(contentsOf: stateFile), before)
        }
    }

    func testUnclaimedCancellationRejectsExpiryAndDelayedAuthenticationBeforeConfirmation() throws {
        for mode in ["expired", "delayed_key", "delayed_trust"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig); _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
            let cancel = try cancellationRequest(request); _ = try rig.service.requestCancellation(cancel, authenticatedPeer: rig.peer)
            let file = rig.directory.appendingPathComponent("state.json"), before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
            if mode == "expired" { rig.clock.advance(seconds: 604800) }
            else { rig.keys.onNextLoad { if mode == "delayed_key" { rig.clock.advance(seconds: 604800) } else { rig.session.revoke() } } }
            let expected: AgentBridgeValidationError = mode == "delayed_trust" ? .permissionRequired : .planExpired
            XCTAssertThrowsError(try rig.service.finalizeUnclaimedCancellation(cancel, authenticatedPeer: rig.peer)) { XCTAssertEqual($0 as? AgentBridgeValidationError, expected, mode) }
            XCTAssertEqual(try Data(contentsOf: file), before)
        }
    }

    func testInvalidatedCaptureStopJournalPreservesAmbiguityWithoutRestoringReads() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig); _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
        let directory = rig.directory.appendingPathComponent("captures/" + reservation.job.requestSHA256.rawValue)
        let spool = try rig.store.openCaptureSpool(reservation, create: true, fileProtection: rig.captureProtection,
            stopRequest: { try rig.service.captureStopRequest(reservation, authenticatedPeer: rig.peer) }) {
            _ = try rig.service.captureReadConfiguration(reservation, authenticatedPeer: rig.peer)
        }
        do {
            XCTAssertNil(try spool.loadOrBegin(AgentBridgeDate("2026-03-08")))
            let before = try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(atPath: directory.path).map { ($0, try Data(contentsOf: directory.appendingPathComponent($0))) })
            _ = try rig.service.requestCancellation(cancellationRequest(request), authenticatedPeer: rig.peer); rig.reader.calls = []
            try spool.preserveCaptureStop()
            let stopped = try Data(contentsOf: directory.appendingPathComponent("capture-stop.json"))
            try spool.preserveCaptureStop()
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("capture-stop.json")), stopped)
            for (name, bytes) in before { XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent(name)), bytes) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("day-2026-03-08.json").path))
            XCTAssertThrowsError(try spool.commit(AgentBridgeDate("2026-03-08"), payload: Data("late".utf8))) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
            }
            XCTAssertTrue(rig.reader.calls.isEmpty)
        } catch { spool.close(); throw error }; spool.close()
        let retained = try rig.store.openCaptureSpool(reservation, create: false, fileProtection: rig.captureProtection) {}
        do {
            XCTAssertEqual(try retained.inspectCancellationCheckpoint().capturedDayCount, 0)
            XCTAssertThrowsError(try retained.loadOrBegin(AgentBridgeDate("2026-03-08"))) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
            }
        } catch { retained.close(); throw error }; retained.close()
        let receipt = try rig.restartedService().finalizeCapturedCancellation(cancellationRequest(request), authenticatedPeer: rig.peer, fileProtection: rig.captureProtection)
        XCTAssertEqual(receipt.status, .cancelled); XCTAssertTrue(receipt.sourceAcknowledged); XCTAssertEqual(receipt.artifactCount, 0)
        XCTAssertEqual(receipt.expiresAt, reservation.job.expiresAt); XCTAssertTrue(rig.reader.calls.isEmpty)
    }

    func testCaptureStopJournalRejectsMissingAuthorityCorruptionAndPublicationRaces() throws {
        for mode in ["no_intent", "foreign", "expired_key", "trust", "bad_stop", "header", "publication", "protection"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig); _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
            let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
            let directory = rig.directory.appendingPathComponent("captures/" + reservation.job.requestSHA256.rawValue)
            let spool = try rig.store.openCaptureSpool(reservation, create: true, fileProtection: rig.captureProtection,
                stopRequest: {
                    let stop = try rig.service.captureStopRequest(reservation, authenticatedPeer: rig.peer)
                    if mode == "foreign" {
                        return AgentBridgeCancel(approvalId: stop.approvalId, authorityId: stop.authorityId, jobId: try id(99), peer: stop.peer, requestSha256: stop.requestSha256)
                    }
                    return stop
                }) { _ = try rig.service.captureReadConfiguration(reservation, authenticatedPeer: rig.peer) }
            defer { rig.captureProtection.onRequire = nil; spool.close() }
            XCTAssertNil(try spool.loadOrBegin(AgentBridgeDate("2026-03-08")))
            if mode != "no_intent" { _ = try rig.service.requestCancellation(cancellationRequest(request), authenticatedPeer: rig.peer) }
            let stopped = directory.appendingPathComponent("capture-stop.json")
            if mode == "bad_stop" {
                try Data("unsigned".utf8).write(to: stopped)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: stopped.path)
                let fd = Darwin.open(stopped.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                XCTAssertGreaterThanOrEqual(fd, 0)
                try rig.captureProtection.applyCompleteProtection(fd); Darwin.close(fd)
            }
            if mode == "header" { try Data("bad".utf8).write(to: directory.appendingPathComponent("header.json")) }
            if mode == "expired_key" { rig.keys.onNextLoad { rig.clock.advance(seconds: 604800) } }
            if mode == "trust" { rig.keys.onNextLoad { rig.session.revoke() } }
            if mode == "protection" { rig.captureProtection.denied = true }
            var changed = false
            if mode == "publication" {
                rig.captureProtection.onRequire = { _ in
                    let pending = try FileManager.default.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil).contains {
                        $0.lastPathComponent.hasPrefix("pending-") && ((try? FileManager.default.attributesOfItem(atPath: $0.path)[.size] as? Int) ?? 0) > 0
                    }
                    if !changed && pending { changed = true; try Data("changed".utf8).write(to: directory.appendingPathComponent("header.json")) }
                }
            }
            let expected: AgentBridgeValidationError = ["no_intent", "foreign"].contains(mode) ? .bindingChanged :
                mode == "expired_key" ? .planExpired : ["trust", "protection"].contains(mode) ? .permissionRequired : .spoolMissingRestartRequired
            XCTAssertThrowsError(try spool.preserveCaptureStop()) { XCTAssertEqual($0 as? AgentBridgeValidationError, expected, mode) }
            if mode == "publication" { XCTAssertTrue(changed) }
            if mode == "bad_stop" { XCTAssertEqual(try Data(contentsOf: stopped), Data("unsigned".utf8)) }
            else { XCTAssertFalse(FileManager.default.fileExists(atPath: stopped.path), mode) }
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("day-2026-03-08.json").path))
        }
    }

    func testNativeStopDuringSDKReadDiscardsLateValueAndJournalsTheInvalidatedOwner() async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            let cancel = try self.cancellationRequest(request)
            store.querySumResult = { _, _ in
                do { _ = try rig.service.requestCancellation(cancel, authenticatedPeer: rig.peer) }
                catch { XCTFail("synthetic stop must persist: \(error)") }
                return 123
            }
            do { _ = try await planner.prepareExport(request, manager: manager); XCTFail("late SDK value must not escape") }
            catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
            let job = try XCTUnwrap(rig.store.snapshot().acceptedJobs?.first)
            let directory = rig.directory.appendingPathComponent("captures/" + job.requestSHA256.rawValue)
            let names = try FileManager.default.contentsOfDirectory(atPath: directory.path)
            XCTAssertTrue(names.contains("capture-stop.json")); XCTAssertFalse(names.contains { $0.hasPrefix("day-") })
            XCTAssertEqual(store.queriedSumIdentifiers.count, 1)
            let receipt = try rig.restartedService().finalizeCapturedCancellation(cancel, authenticatedPeer: rig.peer, fileProtection: rig.captureProtection)
            XCTAssertEqual(receipt.status, .cancelled); XCTAssertTrue(receipt.sourceAcknowledged); XCTAssertEqual(receipt.artifactCount, 0)
            XCTAssertEqual(store.queriedSumIdentifiers.count, 1)
        }
    }

    func testCapturedCancellationPreservesPrivateBytesAndReplaysWithoutRenewalOrReadRights() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig); _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
        let spool = try rig.store.openCaptureSpool(reservation, create: true, fileProtection: rig.captureProtection) {}
        do {
            let day = try AgentBridgeDate("2026-03-08")
            XCTAssertNil(try spool.loadOrBegin(day)); try spool.commit(day, payload: Data("synthetic".utf8))
        } catch { spool.close(); throw error }; spool.close()
        let directory = rig.directory.appendingPathComponent("captures/" + reservation.job.requestSHA256.rawValue)
        func bytes() throws -> [String: Data] {
            try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(atPath: directory.path).map { ($0, try Data(contentsOf: directory.appendingPathComponent($0))) })
        }
        let before = try bytes(), cancel = try cancellationRequest(request)
        _ = try rig.service.requestCancellation(cancel, authenticatedPeer: rig.peer)
        rig.clock.advance(seconds: 601)
        try rig.store.revokeNativeDelegation(request.plan.authorityReferences.native,
            expectedGeneration: rig.store.snapshot().generation, authorization: FakeNativeAuthorization())
        rig.reader.calls = []
        let receipt = try rig.service.finalizeCapturedCancellation(cancel, authenticatedPeer: rig.peer, fileProtection: rig.captureProtection)
        XCTAssertEqual(receipt.status, .cancelled); XCTAssertTrue(receipt.sourceAcknowledged); XCTAssertEqual(receipt.artifactCount, 0)
        XCTAssertEqual(try bytes(), before)
        let file = rig.directory.appendingPathComponent("state.json"), ledger = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        rig.clock.advance(seconds: 1)
        XCTAssertEqual(try rig.restartedService().finalizeCapturedCancellation(cancel, authenticatedPeer: rig.peer, fileProtection: rig.captureProtection), receipt)
        XCTAssertEqual(try Data(contentsOf: file), ledger)
        XCTAssertEqual(try rig.store.snapshot().cancellationIntents?.first?.version, 3)
        XCTAssertThrowsError(try rig.service.captureReadConfiguration(reservation, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
        XCTAssertTrue(rig.reader.calls.isEmpty)
    }

    func testCapturedCancellationRefusesMissingIntentActiveWorkerAmbiguityAndExpiredTrust() throws {
        for mode in ["no_intent", "busy", "ambiguous", "header", "expired", "delayed_key", "delayed_trust"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig); _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
            let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
            let spool = try rig.store.openCaptureSpool(reservation, create: true, fileProtection: rig.captureProtection) {}
            defer { spool.close() }
            let day = try AgentBridgeDate("2026-03-08")
            XCTAssertNil(try spool.loadOrBegin(day))
            if mode != "ambiguous" { try spool.commit(day, payload: Data("synthetic".utf8)) }
            if mode != "busy" { spool.close() }
            let cancel = try cancellationRequest(request)
            if mode != "no_intent" { _ = try rig.service.requestCancellation(cancel, authenticatedPeer: rig.peer) }
            if mode == "header" { try FileManager.default.removeItem(at: rig.directory.appendingPathComponent("captures/" + reservation.job.requestSHA256.rawValue + "/header.json")) }
            let file = rig.directory.appendingPathComponent("state.json"), before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
            if mode == "expired" { rig.clock.advance(seconds: 604800) }
            if mode == "delayed_key" { rig.keys.onNextLoad { rig.clock.advance(seconds: 604800) } }
            if mode == "delayed_trust" { rig.keys.onNextLoad { rig.session.revoke() } }
            let expected: AgentBridgeValidationError = mode == "busy" ? .busy : mode == "no_intent" ? .bindingChanged :
                ["expired", "delayed_key"].contains(mode) ? .planExpired : mode == "delayed_trust" ? .permissionRequired : .spoolMissingRestartRequired
            XCTAssertThrowsError(try rig.service.finalizeCapturedCancellation(cancel, authenticatedPeer: rig.peer, fileProtection: rig.captureProtection)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, expected, mode)
            }
            XCTAssertEqual(try Data(contentsOf: file), before)
        }
    }

    func testCancellationIntentPersistsIdempotentlyAndFencesReadsAcrossRestart() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        let accepted = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
        _ = try rig.service.captureReadConfiguration(reservation, authenticatedPeer: rig.peer)
        rig.reader.calls = []
        let cancel = try cancellationRequest(request)
        let intent = try rig.service.requestCancellation(cancel, authenticatedPeer: rig.peer)
        XCTAssertEqual(try intent.request(), cancel)
        let file = rig.directory.appendingPathComponent("state.json"), bytes = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        XCTAssertEqual((try JSONSerialization.jsonObject(with: bytes) as? [String: Any])?["version"] as? Int, 5)
        rig.clock.advance(seconds: 1)
        XCTAssertEqual(try rig.service.requestCancellation(cancel, authenticatedPeer: rig.peer), intent)
        let restarted = try rig.restartedService()
        XCTAssertEqual(try restarted.requestCancellation(cancel, authenticatedPeer: rig.peer), intent)
        XCTAssertThrowsError(try restarted.captureReadConfiguration(reservation, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
        XCTAssertThrowsError(try restarted.claimCapture(request, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
        XCTAssertEqual(try Data(contentsOf: file), bytes)
        XCTAssertEqual(try rig.store.snapshot().acceptedJobs, [accepted.job])
        XCTAssertEqual(try rig.store.snapshot().captureClaims, [reservation.claim])
        XCTAssertTrue(rig.reader.calls.isEmpty)
    }

    func testCancellationIntentCannotTargetAnotherApprovalAuthorityPeerOrMissingJob() throws {
        for mode in ["peer", "job", "approval", "authority", "request", "unaccepted", "trust", "expired", "delayed_key"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig)
            if mode != "unaccepted" { _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer) }
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: AgentBridgeV4Codec.encode(cancellationRequest(request))) as? [String: Any])
            switch mode {
            case "peer":
                var peer = try XCTUnwrap(object["peer"] as? [String: Any]); peer["host_installation_id"] = try id(99).rawValue; object["peer"] = peer
            case "job": object["job_id"] = try id(99).rawValue
            case "approval": object["approval_id"] = try id(99).rawValue
            case "authority": object["authority_id"] = try id(99).rawValue
            case "request": object["request_sha256"] = String(repeating: "0", count: 64)
            default: break
            }
            let cancel = try AgentBridgeV4Codec.decode(AgentBridgeCancel.self, from: JSONSerialization.data(withJSONObject: object))
            let file = rig.directory.appendingPathComponent("state.json"), bytes = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
            rig.reader.calls = []
            if mode == "trust" { rig.session.revoke() }
            if mode == "expired" { rig.clock.advance(seconds: 604800) }
            if mode == "delayed_key" { rig.keys.onNextLoad { rig.clock.advance(seconds: 604800) } }
            let expected: AgentBridgeValidationError = mode == "trust" ? .permissionRequired : ["expired", "delayed_key"].contains(mode) ? .planExpired : .bindingChanged
            XCTAssertThrowsError(try rig.service.requestCancellation(cancel, authenticatedPeer: rig.peer)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, expected, mode)
            }
            XCTAssertEqual(try Data(contentsOf: file), bytes)
            XCTAssertTrue(rig.reader.calls.isEmpty)
        }
    }

    func testCancellationIntentDoesNotBlockUnrelatedJobsOrLoseItsStorageVersion() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        let intent = try rig.service.requestCancellation(cancellationRequest(request), authenticatedPeer: rig.peer)
        XCTAssertThrowsError(try rig.service.claimCapture(request, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
        let other = AgentBridgeExecute(approval: request.approval, idempotencyKey: try id(97), jobId: try id(98), plan: request.plan, requestId: try id(99))
        _ = try rig.service.acceptExecution(other, authenticatedPeer: rig.peer)
        let reservation = try rig.service.claimCapture(other, authenticatedPeer: rig.peer)
        _ = try rig.service.captureReadConfiguration(reservation, authenticatedPeer: rig.peer)
        _ = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { try self.nativeState() }
        let bytes = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        XCTAssertEqual((try JSONSerialization.jsonObject(with: bytes) as? [String: Any])?["version"] as? Int, 5)
        XCTAssertEqual(try rig.store.snapshot().cancellationIntents, [intent])
    }

    func testCancellationIntentRejectsForgedSignedShapeAndVersionWithoutRepair() throws {
        for mode in ["version", "empty", "duplicate", "missing_job", "authority", "expiry", "unknown", "terminal_status", "terminal_ack", "terminal_count", "terminal_job", "terminal_missing_time", "terminal_captured_without_claim", "accepted_job_version"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig)
            let job = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer).job
            _ = try rig.service.requestCancellation(cancellationRequest(request), authenticatedPeer: rig.peer)
            if mode.hasPrefix("terminal_") { _ = try rig.service.finalizeUnclaimedCancellation(cancellationRequest(request), authenticatedPeer: rig.peer) }
            let file = rig.directory.appendingPathComponent("state.json")
            var root = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])
            var state = try XCTUnwrap(root["state"] as? [String: Any])
            let intents = try XCTUnwrap(state["cancellationIntents"] as? [[String: Any]])
            var intent = try XCTUnwrap(intents.first)
            switch mode {
            case "version": root["version"] = 4
            case "empty": state["cancellationIntents"] = [] as [[String: Any]]
            case "duplicate": state["cancellationIntents"] = [intent, intent]
            case "missing_job": state["acceptedJobs"] = [] as [[String: Any]]
            case "accepted_job_version":
                var jobs = try XCTUnwrap(state["acceptedJobs"] as? [[String: Any]])
                jobs[0]["version"] = 2; state["acceptedJobs"] = jobs
            case "authority":
                var cancel = try XCTUnwrap(JSONSerialization.jsonObject(with: AgentBridgeV4Codec.encode(cancellationRequest(request))) as? [String: Any])
                cancel["authority_id"] = try id(99).rawValue
                intent["requestBytes"] = try AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: cancel)).base64EncodedString()
            case "expiry": intent["requestedAt"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(job.expiresAt), options: .fragmentsAllowed)
            case "unknown": intent["unexpected"] = true
            case "terminal_missing_time": intent.removeValue(forKey: "confirmedAt")
            case "terminal_captured_without_claim": intent["version"] = 3
            default:
                let bytes = try XCTUnwrap(Data(base64Encoded: XCTUnwrap(intent["terminalReceiptBytes"] as? String)))
                var receipt = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                switch mode {
                case "terminal_status": receipt["status"] = "complete"
                case "terminal_ack": receipt["source_acknowledged"] = false
                case "terminal_count": receipt["artifact_count"] = 1
                default: receipt["job_id"] = try id(99).rawValue
                }
                intent["terminalReceiptBytes"] = try AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: receipt)).base64EncodedString()
            }
            if ["authority", "expiry", "unknown"].contains(mode) || mode.hasPrefix("terminal_") { state["cancellationIntents"] = [intent] }
            let canonical = try AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: state))
            let key = try XCTUnwrap(rig.keys.key)
            let mac = Data(HMAC<SHA256>.authenticationCode(for: Data("HealthMd.AgentBridge.NativeExportAuthorityStore.v1\0".utf8) + canonical, using: key))
            root["state"] = state; root["mac"] = mac.base64EncodedString()
            let forged = try AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: root))
            try forged.write(to: file)
            XCTAssertThrowsError(try rig.store.snapshot()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged) }
            XCTAssertThrowsError(try rig.restartedService().requestCancellation(cancellationRequest(request), authenticatedPeer: rig.peer)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
            XCTAssertEqual(try Data(contentsOf: file), forged)
        }
    }

    func testCancellationIntentAfterPlanExpiryAndGrantRevocationCreatesNoReadAuthority() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        rig.clock.advance(seconds: 601)
        try rig.store.revokeNativeDelegation(request.plan.authorityReferences.native,
            expectedGeneration: rig.store.snapshot().generation, authorization: FakeNativeAuthorization())
        rig.reader.calls = []
        XCTAssertEqual(try rig.service.requestCancellation(cancellationRequest(request), authenticatedPeer: rig.peer).request(), try cancellationRequest(request))
        XCTAssertTrue(rig.reader.calls.isEmpty)
        XCTAssertThrowsError(try rig.service.claimCapture(request, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
    }

    func testCaptureReadKeepsFrozenSavedOutputAfterPlanningExpiryWithoutPreferenceReads() throws {
        let rig = try Rig(withSaved: true); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig, policy: .savedDeviceSettings(expectedRevision: 7))
        _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
        let original = try PropertyListDecoder().decode(AgentBridgeRequestSettingsResolution.self, from: reservation.job.nativeResolution)
        rig.clock.advance(seconds: 600)
        rig.reader.catalogRevision += 1; rig.reader.saved = nil
        rig.reader.defaults.reads = 0; rig.reader.calls = []
        let frozen = try rig.service.captureReadConfiguration(reservation, authenticatedPeer: rig.peer)
        XCTAssertEqual(frozen.settings.healthSubfolder, original.settings.healthSubfolder)
        XCTAssertEqual(frozen.selection, original.selection)
        XCTAssertEqual(frozen.predictedRelativePaths, original.predictedRelativePaths)
        XCTAssertEqual(rig.reader.defaults.reads, 0)
        XCTAssertTrue(rig.reader.calls.allSatisfy { $0 == "discovery" })
        XCTAssertEqual(try rig.store.snapshot().captureClaims, [reservation.claim])
    }

    func testCaptureReadRejectsUnavailableMetricsAndCurrentNativeAuthorityLoss() throws {
        for mode in ["metric", "permission", "entitlement", "trust", "grant", "delayed_key"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig)
            _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
            let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
            switch mode {
            case "metric": rig.reader.available.remove("steps")
            case "permission": rig.reader.grants = .required
            case "entitlement": rig.reader.entitlement = .required
            case "trust": rig.session.revoke()
            case "grant": try rig.store.revokeNativeDelegation(request.plan.authorityReferences.native, expectedGeneration: rig.store.snapshot().generation, authorization: FakeNativeAuthorization())
            default: rig.keys.onNextLoad { rig.clock.advance(seconds: 604800) }
            }
            XCTAssertThrowsError(try rig.service.captureReadConfiguration(reservation, authenticatedPeer: rig.peer))
        }
    }

    func testCaptureReadRejectsFabricatedReservationBeforeMetadataAndRechecksReadCallbacks() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
        let fake = AgentBridgeExportCaptureReservation(job: reservation.job,
            claim: .init(version: 1, claimID: try id(99), requestSHA256: reservation.claim.requestSHA256, claimedAt: reservation.claim.claimedAt))
        rig.reader.calls = []
        XCTAssertThrowsError(try rig.service.captureReadConfiguration(fake, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        XCTAssertTrue(rig.reader.calls.isEmpty)
        rig.reader.beforeReturn = { rig.reader.grants = .required }
        XCTAssertThrowsError(try rig.service.captureReadConfiguration(reservation, authenticatedPeer: rig.peer))
    }

    func testCaptureReservationRequiresAcceptanceAndCannotBeReclaimedAcrossRestart() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        XCTAssertThrowsError(try rig.service.claimCapture(request, authenticatedPeer: rig.peer))
        let accepted = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        let claim = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
        XCTAssertEqual(claim.job, accepted.job)
        XCTAssertEqual(claim.claim.requestSHA256, accepted.job.requestSHA256)
        let bytes = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        XCTAssertEqual((try JSONSerialization.jsonObject(with: bytes) as? [String: Any])?["version"] as? Int, 4)
        XCTAssertThrowsError(try rig.restartedService().claimCapture(request, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .busy)
        }
        XCTAssertFalse(try rig.restartedService().acceptExecution(request, authenticatedPeer: rig.peer).newlyAccepted)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), bytes)
    }

    func testCaptureReservationFencesStagingAndNeverReclaimsPublishedButUnreturnedClaim() throws {
        for published in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig)
            _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
            var observed = false
            if published {
                rig.publication.onPublished = { state in
                    if state.captureClaims != nil { observed = true; throw AgentBridgeValidationError.bindingChanged }
                }
            } else {
                rig.publication.onPrepared = { state in
                    if state.captureClaims != nil { observed = true; rig.clock.advance(seconds: 600) }
                }
            }
            XCTAssertThrowsError(try rig.service.claimCapture(request, authenticatedPeer: rig.peer))
            XCTAssertTrue(observed)
            rig.publication.onPrepared = nil; rig.publication.onPublished = nil
            if published {
                XCTAssertEqual(try rig.store.snapshot().captureClaims?.count, 1)
                XCTAssertThrowsError(try rig.restartedService().claimCapture(request, authenticatedPeer: rig.peer)) {
                    XCTAssertEqual($0 as? AgentBridgeValidationError, .busy)
                }
            } else { XCTAssertNil(try rig.store.snapshot().captureClaims) }
        }
    }

    func testCaptureReservationRejectsExpiredChangedAndRevokedAuthorityWithoutClaiming() throws {
        for mode in ["expired", "configuration", "trust", "grant"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig)
            _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
            switch mode {
            case "expired": rig.clock.advance(seconds: 600)
            case "configuration": rig.reader.grants = .required
            case "trust": rig.session.revoke()
            default: try rig.store.revokeNativeDelegation(request.plan.authorityReferences.native, expectedGeneration: rig.store.snapshot().generation, authorization: FakeNativeAuthorization())
            }
            XCTAssertThrowsError(try rig.service.claimCapture(request, authenticatedPeer: rig.peer))
            XCTAssertNil(try rig.store.snapshot().captureClaims)
        }
    }

    func testCaptureReservationVersionSurvivesLaterAcceptanceAndCatalogPublication() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
        let another = AgentBridgeExecute(approval: request.approval, idempotencyKey: try id(94), jobId: try id(95), plan: request.plan, requestId: try id(96))
        XCTAssertTrue(try rig.service.acceptExecution(another, authenticatedPeer: rig.peer).newlyAccepted)
        _ = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { try self.nativeState() }
        XCTAssertEqual(try rig.store.snapshot().captureClaims, [reservation.claim])
        let bytes = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        XCTAssertEqual((try JSONSerialization.jsonObject(with: bytes) as? [String: Any])?["version"] as? Int, 4)
    }

    func testDurableAcceptanceReplaysExactStoredJobAfterPlanExpiryWithoutResolvingChangedSettings() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        let first = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        XCTAssertTrue(first.newlyAccepted)
        XCTAssertEqual(try first.job.request(), request)
        XCTAssertEqual(first.job.requestSHA256.rawValue, try AgentBridgeV4Codec.digest(request))
        let bytes = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
        XCTAssertEqual(json["version"] as? Int, 3)
        rig.clock.advance(seconds: 600)
        rig.reader.catalogRevision += 1; rig.reader.entitlement = .required
        let reads = rig.reader.calls.count
        let retry = try rig.restartedService().acceptExecution(request, authenticatedPeer: rig.peer)
        XCTAssertFalse(retry.newlyAccepted)
        XCTAssertEqual(retry.job, first.job)
        XCTAssertEqual(rig.reader.calls.count, reads)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), bytes)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testDurableAcceptanceRejectsChangedIdempotencyBytesAndUnstoredApproval() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
        for changed in [AgentBridgeExecute(approval: request.approval, idempotencyKey: try id(90), jobId: request.jobId, plan: request.plan, requestId: request.requestId),
                        AgentBridgeExecute(approval: request.approval, idempotencyKey: request.idempotencyKey, jobId: request.jobId, plan: request.plan, requestId: try id(91))] {
            XCTAssertThrowsError(try rig.service.acceptExecution(changed, authenticatedPeer: rig.peer)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
        }
        XCTAssertEqual(try rig.store.snapshot().acceptedJobs?.count, 1)
        // The contract scopes a key to (peer, job, key), not globally to the peer.
        let distinctJob = AgentBridgeExecute(approval: request.approval, idempotencyKey: request.idempotencyKey,
            jobId: try id(92), plan: request.plan, requestId: try id(93))
        XCTAssertTrue(try rig.service.acceptExecution(distinctJob, authenticatedPeer: rig.peer).newlyAccepted)
        XCTAssertEqual(try rig.store.snapshot().acceptedJobs?.count, 2)
        let unapproved = try Rig(); defer { unapproved.cleanup() }; try unapproved.enroll()
        XCTAssertThrowsError(try unapproved.service.acceptExecution(executionRequest(unapproved, storeDecision: false), authenticatedPeer: unapproved.peer))
        XCTAssertNil(try unapproved.store.snapshot().acceptedJobs)
    }

    func testDurableAcceptanceFencesStagingAndRecoversPublishedButUnreturnedJob() throws {
        for afterPublication in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig)
            var delayed = false
            let delay: (AgentBridgeExportAuthoritySnapshot) -> Void = { state in
                if !delayed, state.acceptedJobs != nil { delayed = true; rig.clock.advance(seconds: 600) }
            }
            if afterPublication { rig.publication.onPublished = delay } else { rig.publication.onPrepared = delay }
            XCTAssertThrowsError(try rig.service.acceptExecution(request, authenticatedPeer: rig.peer))
            XCTAssertTrue(delayed)
            rig.publication.onPrepared = nil; rig.publication.onPublished = nil
            if afterPublication {
                let recovered = try rig.restartedService().acceptExecution(request, authenticatedPeer: rig.peer)
                XCTAssertFalse(recovered.newlyAccepted)
                XCTAssertEqual(try recovered.job.request(), request)
            } else { XCTAssertNil(try rig.store.snapshot().acceptedJobs) }
        }
    }

    func testDurableAcceptanceRetryRejectsRevokedTrustAndExpiredJob() throws {
        for mode in ["trust", "grant", "expired"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll(expires: "2026-03-20T00:00:00Z")
            let request = try executionRequest(rig)
            _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
            if mode == "trust" { rig.session.revoke() }
            else if mode == "grant" {
                try rig.store.revokeNativeDelegation(request.plan.authorityReferences.native, expectedGeneration: rig.store.snapshot().generation, authorization: FakeNativeAuthorization())
            } else { rig.clock.advance(seconds: 604800) }
            XCTAssertThrowsError(try rig.service.acceptExecution(request, authenticatedPeer: rig.peer))
        }
    }

    func testExecutionPreparationUsesExactStoredDecisionAndResolutionWithoutMutationAcrossRestart() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try executionRequest(rig)
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        for service in [rig.service, try rig.restartedService()] {
            let prepared = try service.prepareExecution(request, authenticatedPeer: rig.peer)
            XCTAssertEqual(prepared.requestBytes, try AgentBridgeV4Codec.encode(request))
            XCTAssertEqual(prepared.requestSHA256.rawValue, try AgentBridgeV4Codec.digest(request))
            let resolution = try prepared.resolution()
            XCTAssertEqual(resolution.peer, request.plan.intent.peer)
            XCTAssertEqual(resolution.destination, request.plan.intent.destination)
            XCTAssertEqual(resolution.predictedRelativePaths, request.plan.predictedPaths.map(\.rawValue))
            XCTAssertEqual(resolution.selection.map(\.semanticID), request.plan.resolvedMetricIds.map(\.rawValue))
        }
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testExecutionPreparationRejectsUnstoredOrReplacedApprovalID() throws {
        for stored in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let original = try executionRequest(rig, storeDecision: stored)
            let approval = AgentBridgeApproval(approvalId: try id(stored ? 84 : 8), approvedAt: original.approval.approvedAt,
                authorityId: original.approval.authorityId, binding: original.approval.binding, rights: [.exportExecute])
            let request = AgentBridgeExecute(approval: approval, idempotencyKey: original.idempotencyKey,
                jobId: original.jobId, plan: original.plan, requestId: original.requestId)
            XCTAssertThrowsError(try rig.service.prepareExecution(request, authenticatedPeer: rig.peer)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .approvalRequired)
            }
        }
    }

    func testExecutionPreparationRevalidatesLiveStateAfterKeyAndConfigurationCallbacks() throws {
        for mode in ["expired_key", "revoked_key", "configuration", "missing_key"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig)
            switch mode {
            case "expired_key": rig.keys.onNextLoad { rig.clock.advance(seconds: 600) }
            case "revoked_key": rig.keys.onNextLoad { rig.session.revoke() }
            case "configuration": rig.reader.entitlement = .required
            default: break
            }
            let service = mode == "missing_key" ? AgentBridgeExportPlanningService(store: try .init(existingDirectory: rig.directory, protectedKeys: FakeProtectedKeys(key: nil)), configuration: rig.reader, clock: rig.clock) : rig.service
            XCTAssertThrowsError(try service.prepareExecution(request, authenticatedPeer: rig.peer))
        }
    }

    func testNativeCatalogReuseRetainsLiveReturnFenceAndPublicationIdentity() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let profiles = ExportProfileStore(userDefaults: rig.reader.defaults)
        Self.retainedNativeConfigurationObjects.append(profiles)
        var facts = try nativeState(), samples = 0, revokeAtReturn = false
        let revoked = try nativeState(grants: .required)
        let reader = AgentBridgeNativeConfigurationReader(defaults: rig.reader.defaults, profiles: profiles) {
            samples += 1
            if revokeAtReturn && samples.isMultiple(of: 2) { facts = revoked }
            return facts
        }
        let first = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }
        rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
        let initial = try reader.readConfiguration(for: rig.peer, policy: nil, catalogPublication: first)
        _ = try reader.readConfiguration(for: rig.peer, policy: nil, catalogPublication: first)
        XCTAssertEqual(samples, 4, "A reused catalog still samples native facts before and after every read")
        revokeAtReturn = true
        XCTAssertThrowsError(try reader.readConfiguration(for: rig.peer, policy: nil, catalogPublication: first)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        revokeAtReturn = false
        let next = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }
        let current = try reader.readConfiguration(for: rig.peer, policy: nil, catalogPublication: next)
        XCTAssertEqual(current.nativeGrants, .required)
        XCTAssertEqual(current.inputs.catalog.revision, next.revision)
        XCTAssertNotEqual(current.inputs.catalog.configurationSHA256, initial.inputs.catalog.configurationSHA256)
        XCTAssertThrowsError(try reader.readConfiguration(for: rig.peer, policy: nil, catalogPublication: first))
        XCTAssertEqual(rig.reader.defaults.reads, 0); XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testNativeConfigurationDiscoveryAndExplicitNeverReadPrivatePreferences() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let profiles = ExportProfileStore(userDefaults: rig.reader.defaults)
        Self.retainedNativeConfigurationObjects.append(profiles)
        let state = try nativeState()
        let publication = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { state }
        let reader = AgentBridgeNativeConfigurationReader(defaults: rig.reader.defaults, profiles: profiles, nativeState: { state })
        rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
        for policy in [nil, AgentBridgeSettingsPolicy.explicit(try output())] {
            let configuration = try reader.readConfiguration(for: rig.peer, policy: policy, catalogPublication: publication)
            XCTAssertNil(configuration.inputs.savedDevice)
            XCTAssertTrue(configuration.inputs.profiles.isEmpty)
        }
        XCTAssertEqual(rig.reader.defaults.reads, 0)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testNativeConfigurationPlansSupportedPoliciesAndRejectsUnsupportedSavedOutputWithoutMutation() async throws {
        for kind in ["explicit", "saved", "profile"] {
            let rig = try Rig(withSaved: true); defer { rig.cleanup() }; try rig.enroll()
            let original = try XCTUnwrap(rig.reader.saved)
            let settings = AdvancedExportSettings(snapshot: original, userDefaults: rig.reader.defaults)
            settings.apply(snapshot: original)
            try await Task.sleep(for: .milliseconds(350))
            rig.reader.defaults.set(original.healthSubfolder, forKey: "healthSubfolder")
            let profiles = ExportProfileStore(userDefaults: rig.reader.defaults)
            Self.retainedNativeConfigurationObjects.append(settings)
            Self.retainedNativeConfigurationObjects.append(profiles)
            let selected = try XCTUnwrap(profiles.add(name: "Selected", settings: original, target: .connectedMac))
            let other = try XCTUnwrap(profiles.add(name: "Active", settings: original, target: .localIPhoneFolder))
            XCTAssertTrue(profiles.activate(id: other.id))
            let revision = try XCTUnwrap(AdvancedExportSettings.nativeConfigurationRevision(defaults: SystemUserDefaults(defaults: rig.reader.defaults)))
            let state = try nativeState()
            _ = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { state }
            let reader = AgentBridgeNativeConfigurationReader(defaults: rig.reader.defaults, profiles: profiles, nativeState: { state })
            let service = AgentBridgeExportPlanningService(store: rig.store, configuration: reader, clock: rig.clock, newPlanID: { try id(6) })
            func send(_ document: AgentBridgeDocument) throws -> AgentBridgeDocument {
                try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: service.handle(
                    AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: document)), authenticatedPeer: rig.peer)).payload
            }
            let before = rig.reader.defaults.persistentDomain(forName: rig.reader.suite)
            rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
            guard case .discovery(let discovery) = try send(.discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer))) else {
                return XCTFail("Expected native discovery")
            }
            XCTAssertEqual(rig.reader.defaults.reads, 0)
            let policy: AgentBridgeSettingsPolicy
            switch kind {
            case "saved": policy = .savedDeviceSettings(expectedRevision: revision)
            case "profile": policy = .profile(profileID: try AgentBridgeUUID(selected.id.uuidString.lowercased()), expectedRevision: 1)
            default: policy = .explicit(try output())
            }
            let response = try send(.planRequest(rig.request(discovery: discovery, policy: policy)))
            if kind == "saved" {
                // Native rehydration supplies default frontmatter fields. The current strict output
                // subset cannot represent them, even for JSON: reject rather than drop output fields.
                // Full saved-settings output acceptance remains an integration requirement.
                XCTAssertEqual(try error(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: response))), .unsupportedCapability)
            } else {
                guard case .plan(let plan) = response else { return XCTFail("Expected supported native configuration plan") }
                XCTAssertEqual(try service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer), plan)
                XCTAssertEqual(plan.intent.settingsPolicy, policy)
            }
            XCTAssertEqual(profiles.activeProfileID, other.id)
            XCTAssertEqual(rig.reader.defaults.writes, 0)
            if kind == "explicit" { XCTAssertEqual(rig.reader.defaults.reads, 0) }
            XCTAssertEqual(rig.reader.defaults.persistentDomain(forName: rig.reader.suite) as NSDictionary?, before as NSDictionary?)
        }
    }

    func testNativeConfigurationRejectsStalePinsStateDriftAndRevokedPeerWithoutFallback() throws {
        for mode in ["stale_saved", "stale_profile", "drift", "revoke"] {
            let rig = try Rig(withSaved: true); defer { rig.cleanup() }
            let profiles = ExportProfileStore(userDefaults: rig.reader.defaults)
            Self.retainedNativeConfigurationObjects.append(profiles)
            let profile = try XCTUnwrap(profiles.add(name: "Selected", settings: XCTUnwrap(rig.reader.saved), target: .localIPhoneFolder))
            let initial = try nativeState()
            let publication = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { initial }
            var reads = 0
            let reader = AgentBridgeNativeConfigurationReader(defaults: rig.reader.defaults, profiles: profiles, nativeState: {
                reads += 1
                if mode == "revoke", reads == 2 { rig.session.revoke() }
                return try self.nativeState(foregroundAvailable: !(mode == "drift" && reads == 2))
            })
            let policy: AgentBridgeSettingsPolicy?
            switch mode {
            case "stale_saved": policy = .savedDeviceSettings(expectedRevision: 7)
            case "stale_profile": policy = .profile(profileID: try AgentBridgeUUID(profile.id.uuidString.lowercased()), expectedRevision: 2)
            default: policy = nil
            }
            rig.reader.defaults.writes = 0
            XCTAssertThrowsError(try reader.readConfiguration(for: rig.peer, policy: policy, catalogPublication: publication)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, mode == "revoke" ? .permissionRequired : .bindingChanged)
            }
            XCTAssertEqual(rig.reader.defaults.writes, 0)
        }
    }

    func testNativeCatalogPublicationPersistsIdempotentlyAndAdvancesAcrossReadinessABA() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let file = rig.directory.appendingPathComponent("state.json")
        let legacyBytes = try Data(contentsOf: file), original = try rig.store.snapshot()
        XCTAssertNil(original.nativeCatalog)
        _ = try rig.store.snapshot()
        XCTAssertEqual(try Data(contentsOf: file), legacyBytes) // Reading v1 never migrates or writes it.
        let ready = try nativeState(), unavailable = try nativeState(foregroundAvailable: false)
        let first = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { ready }
        XCTAssertEqual(first.revision, 1)
        let publishedBytes = try Data(contentsOf: file), generation = try rig.store.snapshot().generation
        let restarted = try AgentBridgeExportAuthorityStore(existingDirectory: rig.directory, protectedKeys: rig.keys)
        XCTAssertEqual(try restarted.snapshot().nativeCatalog, first)
        XCTAssertEqual(try restarted.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { ready }, first)
        XCTAssertEqual(try restarted.snapshot().generation, generation)
        XCTAssertEqual(try Data(contentsOf: file), publishedBytes)
        let second = try restarted.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { unavailable }
        let third = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { ready }
        XCTAssertEqual([second.revision, third.revision], [2, 3])
        XCTAssertEqual(third.factsSHA256, first.factsSHA256)
        let after = try rig.store.snapshot()
        XCTAssertEqual(after.delegations.map(\.sanitizedBytes), original.delegations.map(\.sanitizedBytes))
        XCTAssertEqual(after.delegations.map(\.revoked), original.delegations.map(\.revoked))
        XCTAssertTrue(after.plans.isEmpty); XCTAssertTrue(after.decisions.isEmpty)
        XCTAssertEqual((try JSONSerialization.jsonObject(with: Data(contentsOf: file)) as? [String: Any])?["version"] as? Int, 2)
    }

    func testNativeCatalogMissingOrChangedPublicationRejectsWithoutWireRepairAndInvalidatesOldPlansAfterABA() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let profiles = ExportProfileStore(userDefaults: rig.reader.defaults)
        Self.retainedNativeConfigurationObjects.append(profiles)
        var facts = try nativeState(), samples = 0
        let reader = AgentBridgeNativeConfigurationReader(defaults: rig.reader.defaults, profiles: profiles, nativeState: { samples += 1; return facts })
        let service = AgentBridgeExportPlanningService(store: rig.store, configuration: reader, clock: rig.clock, newPlanID: { try id(6) })
        func send(_ document: AgentBridgeDocument) throws -> Data {
            try service.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: document)), authenticatedPeer: rig.peer)
        }
        let file = rig.directory.appendingPathComponent("state.json"), before = try Data(contentsOf: file)
        XCTAssertEqual(try error(send(.discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer)))), .bindingChanged)
        XCTAssertEqual(samples, 0); XCTAssertEqual(try Data(contentsOf: file), before)
        _ = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }
        guard case .discovery(let discovery) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self,
            from: send(.discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer)))).payload else { return XCTFail("Expected published discovery") }
        guard case .plan(let plan) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self,
            from: send(.planRequest(rig.request(discovery: discovery)))).payload else { return XCTFail("Expected published plan") }
        let accepted = try Data(contentsOf: file)
        facts = try nativeState(foregroundAvailable: false)
        XCTAssertThrowsError(try service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        XCTAssertEqual(try Data(contentsOf: file), accepted) // No reader publication or repair.
        _ = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }
        facts = try nativeState()
        _ = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }
        XCTAssertThrowsError(try service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        XCTAssertEqual(try rig.store.snapshot().plans.count, 1) // No silent replan or new consent.
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
    }

    func testNativeLifecycleRejectsPendingChangesBeforeSignedPublicationAndInvalidatesOldPlans() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let profiles = ExportProfileStore(userDefaults: rig.reader.defaults)
        Self.retainedNativeConfigurationObjects.append(profiles)
        let facts = try nativeState()
        let lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(facts)
        XCTAssertThrowsError(try lifecycle.currentFacts())
        let reader = AgentBridgeNativeConfigurationReader(defaults: rig.reader.defaults, profiles: profiles, nativeState: { try lifecycle.currentFacts() })
        let service = AgentBridgeExportPlanningService(store: rig.store, configuration: reader, clock: rig.clock, newPlanID: { try id(6) })
        let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let discoveryBytes = try service.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload:
            .discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer)))), authenticatedPeer: rig.peer)
        guard case .discovery(let discovery) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: discoveryBytes).payload else {
            return XCTFail("Expected published discovery")
        }
        let planBytes = try service.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload:
            .planRequest(rig.request(discovery: discovery)))), authenticatedPeer: rig.peer)
        guard case .plan(let plan) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: planBytes).payload else {
            return XCTFail("Expected issued plan")
        }
        _ = try service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)
        let before = try rig.store.snapshot()
        // An observed transition may coalesce before deferred SDK sampling. It must not
        // become an unchanged-publication retry or silently renew this issued plan.
        let pendingBytes = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        try lifecycle.observeNativeChange()
        try lifecycle.observe(facts) // Deferred sample has returned to the original value.
        XCTAssertThrowsError(try service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), pendingBytes)
        let changed = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertEqual(changed.factsSHA256, first.factsSHA256)
        XCTAssertEqual(changed.revision, first.revision + 1)
        let after = try rig.store.snapshot()
        XCTAssertEqual(after.generation, before.generation + 1)
        XCTAssertEqual(after.plans.count, 1)
        XCTAssertEqual(after.delegations.map(\.sanitizedBytes), before.delegations.map(\.sanitizedBytes))
        XCTAssertTrue(after.decisions.isEmpty)
        XCTAssertThrowsError(try service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        let file = rig.directory.appendingPathComponent("state.json"), committed = try Data(contentsOf: file)
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        XCTAssertEqual(try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID), changed)
        let restarted = try AgentBridgeExportAuthorityStore(existingDirectory: rig.directory, protectedKeys: rig.keys, publication: rig.publication)
        XCTAssertEqual(try restarted.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }, changed)
        XCTAssertEqual(try Data(contentsOf: file), committed)
    }

    func testNativeLifecycleDoesNotClearObservationRacingSignedPublication() throws {
        for afterSync in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }
            let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
            try lifecycle.observe(facts)
            let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            try lifecycle.observeNativeChange()
            var observed = false
            let callback: (AgentBridgeExportAuthoritySnapshot) -> Void = { _ in
                observed = true
                do { try lifecycle.observeNativeChange() }
                catch { XCTFail("Native observation unexpectedly rejected") }
            }
            if afterSync { rig.publication.onPublished = callback } else { rig.publication.onPrepared = callback }
            XCTAssertThrowsError(try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
            XCTAssertTrue(observed)
            XCTAssertThrowsError(try lifecycle.currentFacts())
            rig.publication.onPrepared = nil; rig.publication.onPublished = nil
            let next = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            XCTAssertGreaterThan(next.revision, first.revision)
            XCTAssertEqual(try lifecycle.currentFacts(), facts)
        }
    }

    func testNativeLifecycleOwnerRestartInvalidatesOldCatalogAndStopCannotRevive() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let facts = try nativeState(), firstOwner = AgentBridgeNativeCatalogLifecycle()
        try firstOwner.observe(facts)
        let first = try firstOwner.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        firstOwner.stop()
        XCTAssertThrowsError(try firstOwner.currentFacts()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertThrowsError(try firstOwner.observe(facts))
        XCTAssertThrowsError(try firstOwner.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID))
        let nextOwner = AgentBridgeNativeCatalogLifecycle()
        try nextOwner.observe(facts)
        let next = try nextOwner.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertEqual(next.revision, first.revision + 1)
        XCTAssertEqual(next.factsSHA256, first.factsSHA256)
        XCTAssertEqual(try nextOwner.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID), next)
    }

    private func nativePlanningSession(_ rig: Rig, _ lifecycle: AgentBridgeNativeCatalogLifecycle, profiles existingProfiles: ExportProfileStore? = nil, responseChannel: DirectSecureChannel? = nil, responseVersions: [Int] = [1, 3, 4], captureProtection: (any AgentBridgeNativeCaptureProtecting)? = nil, transferNegotiation: DirectTransferNegotiation? = DirectTransferCapabilities.current.negotiated(with: .current), peerTransferCapabilities: DirectTransferCapabilities? = .current, beforeNativeRead: @escaping @MainActor () throws -> Void = {}) throws -> AgentBridgeNativePlanningSession {
        let profiles = existingProfiles ?? ExportProfileStore(userDefaults: rig.reader.defaults)
        Self.retainedNativeConfigurationObjects.append(profiles)
        let reader = AgentBridgeNativeConfigurationReader(defaults: rig.reader.defaults, profiles: profiles) {
            try beforeNativeRead()
            return try lifecycle.currentFacts()
        }
        return try AgentBridgeNativePlanningSession(peer: rig.peer, lifecycle: lifecycle, store: rig.store,
            configuration: reader, responseChannel: responseChannel,
            responseNegotiation: AgentBridgeNegotiation(localVersions: responseVersions, remoteVersions: [1, 3, 4], deployedBaseVersion: 1),
            responseTransferNegotiation: transferNegotiation, responsePeerTransferCapabilities: peerTransferCapabilities, captureProtection: captureProtection ?? rig.captureProtection,
            clock: rig.clock, newPlanID: { try id(6) })
    }

    private func nativeDiscoveryBytes(_ rig: Rig) throws -> Data {
        try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer))))
    }

    private func nativeCaptureRequest(_ rig: Rig, planner: AgentBridgeNativePlanningSession, metrics: [String] = ["steps"]) throws -> AgentBridgeExecute {
        func send(_ document: AgentBridgeDocument) throws -> AgentBridgeDocument {
            try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: planner.handle(
                AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: document)))).payload
        }
        guard case .discovery(let discovery) = try send(.discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer))),
              case .plan(let plan) = try send(.planRequest(rig.request(discovery: discovery, metrics: metrics))) else { throw AgentBridgeValidationError.invalidRequest }
        let binding = AgentBridgeSemantics.binding(plan)
        try planner.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authorization: FakeNativeAuthorization(binding: binding))
        guard case .approval(let approval) = try send(.approvalRequest(.init(binding: binding, planId: plan.planId, requestId: id(103)))) else {
            throw AgentBridgeValidationError.invalidRequest
        }
        return try AgentBridgeExecute(approval: approval, idempotencyKey: id(81), jobId: id(82), plan: plan, requestId: id(83))
    }

    #if canImport(HealthMd)
    private func withNativeSDKCapture(metrics: [String], afterCapture: ((Rig, AgentBridgeNativePlanningSession, AgentBridgeExecute, FakeHealthStore, HealthKitManager, Error?) async throws -> Void)? = nil, operation: (Rig, AgentBridgeNativeCaptureContext, FakeHealthStore, HealthKitManager) async throws -> Void) async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let channel = DirectSecureChannel(packetConnection: NativePlanningResponsePackets(), sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
        let request = try nativeCaptureRequest(rig, planner: planner, metrics: metrics)
        let store = FakeHealthStore()
        let capture = HealthKitManager(store: store, userDefaults: rig.reader.defaults)
        Self.retainedNativeConfigurationObjects.append(capture)
        let preferenceReads = rig.reader.defaults.reads, preferenceWrites = rig.reader.defaults.writes
        var originalFailure: Error?
        do {
            try await planner.withCaptureContext(request) { context in
                _ = try context.begin()
                try await operation(rig, context, store, capture)
            }
        } catch { originalFailure = error }
        do { try await afterCapture?(rig, planner, request, store, capture, originalFailure) }
        catch { if originalFailure == nil { originalFailure = error } }
        let claimCount = try rig.store.snapshot().captureClaims?.count
        XCTAssertEqual(claimCount, 1)
        XCTAssertEqual(rig.reader.defaults.reads, preferenceReads)
        XCTAssertEqual(rig.reader.defaults.writes, preferenceWrites)
        if let originalFailure { throw originalFailure }
    }

    private func withNativeExportPreparation(transferNegotiation: DirectTransferNegotiation? = DirectTransferCapabilities.current.negotiated(with: .current), peerTransferCapabilities: DirectTransferCapabilities? = .current, _ operation: (Rig, AgentBridgeNativePlanningSession, AgentBridgeExecute, FakeHealthStore, HealthKitManager) async throws -> Void) async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let channel = DirectSecureChannel(packetConnection: NativePlanningResponsePackets(), sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel, transferNegotiation: transferNegotiation, peerTransferCapabilities: peerTransferCapabilities)
        let request = try nativeCaptureRequest(rig, planner: planner)
        let store = FakeHealthStore()
        let manager = HealthKitManager(store: store, userDefaults: rig.reader.defaults)
        Self.retainedNativeConfigurationObjects.append(manager)
        let reads = rig.reader.defaults.reads, writes = rig.reader.defaults.writes
        var failure: Error?
        do { try await operation(rig, planner, request, store, manager) } catch { failure = error }
        XCTAssertEqual(try rig.store.snapshot().captureClaims?.count, 1)
        XCTAssertEqual(rig.reader.defaults.reads, reads); XCTAssertEqual(rig.reader.defaults.writes, writes)
        if let failure { throw failure }
    }

    private func resumeRequest(_ request: AgentBridgeExecute, transfer: AgentBridgeNativePreparedTransfer,
        frontier: AgentBridgeTransferFrontier) throws -> AgentBridgeResume {
        .init(binding: AgentBridgeSemantics.binding(request.plan), committedPartitionCount: frontier.committedPartitionCount,
            destination: request.plan.intent.destination, frontierSha256: frontier.sha256, jobId: request.jobId,
            manifestSha256: try AgentBridgeDigest(AgentBridgeV4Codec.sha256(transfer.export.manifestCanonical)),
            peer: request.plan.intent.peer, requestSha256: try AgentBridgeDigest(transfer.export.requestSHA256))
    }

    func testNativeResumeRejectsManifestDeletionAtFinalAdmissionCallback() async throws {
        try await checkNativeResumeFinalCallbackDamage("manifest.json")
    }
    func testNativeResumeRejectsProgressCorruptionAtFinalAdmissionCallback() async throws {
        try await checkNativeResumeFinalCallbackDamage("progress.json")
    }
    private func checkNativeResumeFinalCallbackDamage(_ filename: String) async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let transfer = try await planner.prepareTransferExport(request, manager: manager)
            let frontier = try await planner.withRetainedCaptureContext(request) { context in
                _ = try context.begin(); return try context.preserveTransferFrontier()
            }
            let resume = try resumeRequest(request, transfer: transfer, frontier: frontier)
            let path = rig.directory.appendingPathComponent("captures/" + transfer.export.requestSHA256).appendingPathComponent(filename)
            var reads = 0, admissionReads = 0, target = 0
            let profiles = try XCTUnwrap(Self.retainedNativeConfigurationObjects.compactMap { $0 as? ExportProfileStore }.last)
            @MainActor func reconnect() throws -> AgentBridgeNativePlanningSession {
                let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
                _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
                let channel = DirectSecureChannel(packetConnection: NativePlanningResponsePackets(), sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic resume")
                return try nativePlanningSession(rig, lifecycle, profiles: profiles, responseChannel: channel, beforeNativeRead: {
                    reads += 1
                    if reads == target {
                        if filename == "manifest.json" { try FileManager.default.removeItem(at: path) }
                        else { try Data("corrupt".utf8).write(to: path) }
                    }
                })
            }
            try await reconnect().withResumedCaptureContext(resume) { _, context in
                admissionReads = reads; _ = try context.begin()
            }
            XCTAssertGreaterThan(admissionReads, 0)
            reads = 0; target = admissionReads
            store.querySumResult = { _, _ in XCTFail("Resume cannot query SDK"); return nil }
            do {
                try await reconnect().withResumedCaptureContext(resume) { _, context in
                    XCTFail("Changed evidence reached admitted callback"); _ = try context.begin()
                }
                XCTFail("Expected final admission rejection")
            } catch { XCTAssertNotNil(error as? AgentBridgeValidationError) }
            XCTAssertGreaterThanOrEqual(reads, target)
            if filename == "manifest.json" { XCTAssertFalse(FileManager.default.fileExists(atPath: path.path)) }
            else { XCTAssertEqual(try Data(contentsOf: path), Data("corrupt".utf8)) }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }

    func testNativeResumeReopensOriginalJobOnFreshOwnerWithoutSDKOrRewrite() async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let transfer = try await planner.prepareTransferExport(request, manager: manager)
            var frontier: AgentBridgeTransferFrontier?
            try await planner.withRetainedCaptureContext(request) { context in
                _ = try context.begin(); _ = try context.preserveTransferFrontier()
                frontier = try context.recordAcknowledgedTransferPartition(0)
            }
            let directory = rig.directory.appendingPathComponent("captures/" + transfer.export.requestSHA256)
            let progress = try Data(contentsOf: directory.appendingPathComponent("progress.json"))
            let acceptedBeforeReconnect = try rig.store.snapshot().acceptedJobs
            let reconnect = try transferReconnect(rig, capabilities: .current)
            XCTAssertEqual(try rig.store.snapshot().acceptedJobs, acceptedBeforeReconnect)
            // A fresh lifecycle intentionally advances catalog revision; Resume itself is read-only.
            let issuer = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
            store.querySumResult = { _, _ in XCTFail("Resume cannot query SDK"); return nil }
            let resume = try resumeRequest(request, transfer: transfer, frontier: XCTUnwrap(frontier))
            try await reconnect.withResumedCaptureContext(resume) { recovered, context in
                XCTAssertEqual(try AgentBridgeV4Codec.encode(recovered), try AgentBridgeV4Codec.encode(request))
                _ = try context.begin()
                XCTAssertEqual(try context.preserveTransferFrontier(), frontier)
                XCTAssertEqual(try context.preserveManifest(), transfer.export.manifestCanonical)
                XCTAssertEqual(try context.preserveTransferPlan(), transfer.checkpointCanonical)
            }
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("progress.json")), progress)
            XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), issuer)
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }

    func testNativeResumeRejectsJobWithoutRepair() async throws { try await checkNativeResumeDamage("Job") }
    func testNativeResumeRejectsPeerWithoutRepair() async throws { try await checkNativeResumeDamage("Peer") }
    func testNativeResumeRejectsDestinationWithoutRepair() async throws { try await checkNativeResumeDamage("Destination") }
    func testNativeResumeRejectsBindingWithoutRepair() async throws { try await checkNativeResumeDamage("Binding") }
    func testNativeResumeRejectsRequestWithoutRepair() async throws { try await checkNativeResumeDamage("Request") }
    func testNativeResumeRejectsManifestWithoutRepair() async throws { try await checkNativeResumeDamage("Manifest") }
    func testNativeResumeRejectsCountWithoutRepair() async throws { try await checkNativeResumeDamage("Count") }
    func testNativeResumeRejectsFrontierWithoutRepair() async throws { try await checkNativeResumeDamage("Frontier") }
    func testNativeResumeRejectsUninitializedWithoutRepair() async throws { try await checkNativeResumeDamage("Uninitialized") }
    func testNativeResumeRejectsMissingManifestWithoutRepair() async throws { try await checkNativeResumeDamage("MissingManifest") }
    private func checkNativeResumeDamage(_ mode: String) async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let transfer = try await planner.prepareTransferExport(request, manager: manager)
            var frontier: AgentBridgeTransferFrontier?
            try await planner.withRetainedCaptureContext(request) { context in
                _ = try context.begin()
                if mode != "Uninitialized" { frontier = try context.preserveTransferFrontier() }
            }
            // The unchanged transfer's original seed remains independently calculable for the
            // missing-initialization control; no native progress is installed by this fixture.
            let seed = try AgentBridgeTransferFrontier(jobID: request.jobId,
                requestSHA256: AgentBridgeDigest(transfer.export.requestSHA256),
                manifestSHA256: AgentBridgeDigest(AgentBridgeV4Codec.sha256(transfer.export.manifestCanonical)),
                sessionID: AgentBridgeUUID(transfer.session.sessionID.uuidString.lowercased()))
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: AgentBridgeV4Codec.encode(resumeRequest(request, transfer: transfer, frontier: frontier ?? seed))) as? [String: Any])
            switch mode {
            case "Job": object["job_id"] = try id(200).rawValue
            case "Peer":
                var peer = try XCTUnwrap(object["peer"] as? [String: Any]); peer["source_installation_id"] = try id(200).rawValue
                var binding = try XCTUnwrap(object["binding"] as? [String: Any]); binding["peer"] = peer
                object["peer"] = peer; object["binding"] = binding
            case "Destination":
                var destination = try XCTUnwrap(object["destination"] as? [String: Any]); destination["revision"] = 200
                var binding = try XCTUnwrap(object["binding"] as? [String: Any]); binding["destination"] = destination
                object["destination"] = destination; object["binding"] = binding
            case "Binding": var binding = try XCTUnwrap(object["binding"] as? [String: Any]); binding["settings_sha256"] = String(repeating: "0", count: 64); object["binding"] = binding
            case "Request": object["request_sha256"] = String(repeating: "0", count: 64)
            case "Manifest": object["manifest_sha256"] = String(repeating: "0", count: 64)
            case "Count": object["committed_partition_count"] = 1
            case "Frontier": object["frontier_sha256"] = String(repeating: "0", count: 64)
            default: break
            }
            let resume = try AgentBridgeV4Codec.decode(AgentBridgeResume.self, from: JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]))
            let directory = rig.directory.appendingPathComponent("captures/" + transfer.export.requestSHA256)
            if mode == "MissingManifest" { try FileManager.default.removeItem(at: directory.appendingPathComponent("manifest.json")) }
            let progress = try Data(contentsOf: directory.appendingPathComponent("progress.json"))
            let acceptedBeforeReconnect = try rig.store.snapshot().acceptedJobs
            let reconnect = try transferReconnect(rig, capabilities: .current)
            XCTAssertEqual(try rig.store.snapshot().acceptedJobs, acceptedBeforeReconnect)
            // A fresh lifecycle intentionally advances catalog revision; Resume itself is read-only.
            let issuer = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
            store.querySumResult = { _, _ in XCTFail("Rejected Resume cannot query SDK"); return nil }
            do {
                try await reconnect.transmitResumedTransfer(resume) { _, _ in
                    XCTFail("Invalid Resume reached native callback"); throw AgentBridgeValidationError.invalidRequest
                }
                XCTFail("Expected rejected Resume")
            } catch { XCTAssertNotNil(error as? AgentBridgeValidationError) }
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("progress.json")), progress)
            XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), issuer)
            if mode == "MissingManifest" { XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("manifest.json").path)) }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }

    func testNativeResumeAcknowledgementAdvancesOnlyExactPendingPrefixAndReplaysWithoutRewrite() async throws { try await checkNativeResumeAcknowledgement("valid") }
    func testNativeResumeAcknowledgementRejectsChangedManifestWithoutAdvancing() async throws { try await checkNativeResumeAcknowledgement("manifest") }
    func testNativeResumeAcknowledgementRejectsChangedFrontierWithoutAdvancing() async throws { try await checkNativeResumeAcknowledgement("frontier") }
    func testNativeResumeAcknowledgementRejectsChangedCountWithoutAdvancing() async throws { try await checkNativeResumeAcknowledgement("count") }
    func testNativeResumeAcknowledgementRejectsChangedSessionWithoutAdvancing() async throws { try await checkNativeResumeAcknowledgement("session") }
    func testNativeResumeAcknowledgementRejectsUnpreparedWithoutAdvancing() async throws { try await checkNativeResumeAcknowledgement("unprepared") }
    func testNativeResumeAcknowledgementRejectsCorruptPendingWithoutAdvancing() async throws { try await checkNativeResumeAcknowledgement("corrupt") }
    func testNativeResumeAcknowledgementRejectsUninitializedWithoutAdvancing() async throws { try await checkNativeResumeAcknowledgement("uninitialized") }
    func testNativeResumeAcknowledgementRejectsDeniedAckWithoutAdvancing() async throws { try await checkNativeResumeAcknowledgement("rejected") }
    func testNativeResumeAcknowledgementRejectsManifestDeletionBeforePublicationWithoutAdvancing() async throws { try await checkNativeResumeAcknowledgement("publication") }

    func testNativeStandaloneAcknowledgementRejectsManifestDeletionBeforePublicationWithoutAdvancing() async throws { try await checkNativeResumeAcknowledgement("standalone_publication") }

    private func checkNativeResumeAcknowledgement(_ mode: String) async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let transfer = try await planner.prepareTransferExport(request, manager: manager)
            let partition = transfer.partitions[0]
            let seed = try AgentBridgeTransferFrontier(jobID: request.jobId, requestSHA256: AgentBridgeDigest(transfer.export.requestSHA256),
                manifestSHA256: AgentBridgeDigest(AgentBridgeV4Codec.sha256(transfer.export.manifestCanonical)),
                sessionID: AgentBridgeUUID(transfer.session.sessionID.uuidString.lowercased()))
            let expected = try seed.appending(.init(partitionIndex: 0, transferID: AgentBridgeUUID(partition.transferID.uuidString.lowercased()),
                artifactID: AgentBridgeUUID(transfer.export.baseFiles[0].manifest.fileID.uuidString.lowercased()), artifactOffset: 0,
                byteCount: partition.byteCount, chunkCount: Int64(partition.chunkCount), sha256: AgentBridgeDigest(partition.sha256)))
            try await planner.withRetainedCaptureContext(request) { context in
                _ = try context.begin()
                if mode != "uninitialized" { _ = try context.preserveTransferFrontier() }
                if !["unprepared", "uninitialized"].contains(mode) { try context.preserveAwaitingPartitionAcknowledgement(0) }
            }
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: AgentBridgeV4Codec.encode(resumeRequest(request, transfer: transfer, frontier: expected))) as? [String: Any])
            if mode == "manifest" { object["manifest_sha256"] = String(repeating: "0", count: 64) }
            if mode == "frontier" { object["frontier_sha256"] = seed.sha256.rawValue }
            if mode == "count" { object["committed_partition_count"] = 0 }
            let resume = try AgentBridgeV4Codec.decode(AgentBridgeResume.self, from: JSONSerialization.data(withJSONObject: object))
            let ack = try DirectTransferPartitionAcknowledgement(sessionID: mode == "session" ? UUID() : transfer.session.sessionID,
                jobID: transfer.session.jobID, partitionIndex: partition.index, transferID: partition.transferID,
                partitionSHA256: partition.sha256, accepted: mode != "rejected")
            let directory = rig.directory.appendingPathComponent("captures/" + transfer.export.requestSHA256)
            let pendingURL = directory.appendingPathComponent("partition-awaiting-ack.json")
            if mode == "corrupt" { try Data("corrupt".utf8).write(to: pendingURL) }
            let pending = try? Data(contentsOf: pendingURL)
            let before = try Data(contentsOf: directory.appendingPathComponent("progress.json"))
            let accepted = try rig.store.snapshot().acceptedJobs
            let reconnect = try transferReconnect(rig, capabilities: .current)
            let issuer = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
            var damaged = false
            if ["publication", "standalone_publication"].contains(mode) {
                rig.captureProtection.onRequire = { _ in
                    guard !damaged else { return }
                    for name in try FileManager.default.contentsOfDirectory(atPath: directory.path) where name.hasPrefix("pending-") {
                        guard let bytes = try? Data(contentsOf: directory.appendingPathComponent(name)),
                              let signed = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                              let record = signed["record"] as? [String: Any], let encoded = record["payload"] as? String,
                              let payload = Data(base64Encoded: encoded), let progress = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                              progress["committedPartitionCount"] as? Int == 1 else { continue }
                        damaged = true; try FileManager.default.removeItem(at: directory.appendingPathComponent("manifest.json")); break
                    }
                }
            }
            defer { rig.captureProtection.onRequire = nil }
            store.querySumResult = { _, _ in XCTFail("ACK Resume must not query SDK"); return nil }
            var admitted = false
            do {
                if mode == "standalone_publication" {
                    try await reconnect.withRetainedCaptureContext(request) { context in
                        _ = try context.begin(); _ = try context.reconcilePartitionAcknowledgement(ack)
                        admitted = true
                    }
                } else {
                    try await reconnect.withResumedCaptureContext(resume, acknowledging: ack) { recovered, context in
                        admitted = true
                        XCTAssertEqual(try AgentBridgeV4Codec.encode(recovered), try AgentBridgeV4Codec.encode(request))
                        _ = try context.begin(); XCTAssertEqual(try context.preserveTransferFrontier(), expected)
                    }
                }
                if mode != "valid" { XCTFail("Invalid ACK/Resume admitted: " + mode) }
            } catch { if mode == "valid" { throw error }; XCTAssertNotNil(error as? AgentBridgeValidationError) }
            if mode == "valid" {
                XCTAssertTrue(admitted)
                let committed = try Data(contentsOf: directory.appendingPathComponent("progress.json"))
                XCTAssertNotEqual(committed, before)
                try await reconnect.withResumedCaptureContext(resume, acknowledging: ack) { _, context in
                    _ = try context.begin(); XCTAssertEqual(try context.preserveTransferFrontier(), expected)
                }
                XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("progress.json")), committed)
            } else {
                XCTAssertFalse(admitted)
                XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("progress.json")), before)
            }
            if ["publication", "standalone_publication"].contains(mode) { XCTAssertTrue(damaged); XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("manifest.json").path)) }
            XCTAssertEqual(try? Data(contentsOf: pendingURL), pending)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("transfer.json")), transfer.checkpointCanonical)
            XCTAssertEqual(try rig.store.snapshot().acceptedJobs, accepted)
            XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), issuer)
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }

    func testNativePendingAcknowledgementReconcilesExactLostAckWithoutSDK() async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let transfer = try await planner.prepareTransferExport(request, manager: manager)
            let partition = transfer.partitions[0]
            let ack = try DirectTransferPartitionAcknowledgement(sessionID: transfer.session.sessionID, jobID: transfer.session.jobID,
                partitionIndex: partition.index, transferID: partition.transferID, partitionSHA256: partition.sha256, accepted: true)
            let directory = rig.directory.appendingPathComponent("captures/" + transfer.export.requestSHA256)
            let progress = directory.appendingPathComponent("progress.json")
            try await planner.withRetainedCaptureContext(request) { context in
                _ = try context.begin(); _ = try context.preserveTransferFrontier()
                try context.preserveAwaitingPartitionAcknowledgement(0)
                XCTAssertEqual(try context.preserveTransferFrontier().committedPartitionCount, 0)
            }
            let pending = try Data(contentsOf: directory.appendingPathComponent("partition-awaiting-ack.json"))
            store.querySumResult = { _, _ in XCTFail("No SDK while reconciling original ACK"); return nil }
            try await planner.withRetainedCaptureContext(request) { context in
                _ = try context.begin()
                XCTAssertEqual(try context.reconcilePartitionAcknowledgement(ack).committedPartitionCount, 1)
            }
            let committed = try Data(contentsOf: progress)
            try await planner.withRetainedCaptureContext(request) { context in
                _ = try context.begin()
                XCTAssertEqual(try context.reconcilePartitionAcknowledgement(ack).committedPartitionCount, 1)
            }
            XCTAssertEqual(try Data(contentsOf: progress), committed)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("partition-awaiting-ack.json")), pending)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("transfer.json")), transfer.checkpointCanonical)
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }

    func testNativePendingAcknowledgementRejectsUnprepared() async throws { try await checkNativePendingAcknowledgementDamage("unprepared") }
    func testNativePendingAcknowledgementRejectsDeleted() async throws { try await checkNativePendingAcknowledgementDamage("deleted") }
    func testNativePendingAcknowledgementRejectsCorrupt() async throws { try await checkNativePendingAcknowledgementDamage("corrupt") }
    func testNativePendingAcknowledgementRejectsSession() async throws { try await checkNativePendingAcknowledgementDamage("session") }
    func testNativePendingAcknowledgementRejectsJob() async throws { try await checkNativePendingAcknowledgementDamage("job") }
    func testNativePendingAcknowledgementRejectsTransfer() async throws { try await checkNativePendingAcknowledgementDamage("transfer") }
    func testNativePendingAcknowledgementRejectsHash() async throws { try await checkNativePendingAcknowledgementDamage("hash") }
    func testNativePendingAcknowledgementRejectsAhead() async throws { try await checkNativePendingAcknowledgementDamage("ahead") }
    func testNativePendingAcknowledgementRejectsRejected() async throws { try await checkNativePendingAcknowledgementDamage("rejected") }
    func testNativePendingAcknowledgementRejectsOlder() async throws { try await checkNativePendingAcknowledgementDamage("older") }
    private func checkNativePendingAcknowledgementDamage(_ mode: String) async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let transfer = try await planner.prepareTransferExport(request, manager: manager)
            func ack(_ index: Int) throws -> DirectTransferPartitionAcknowledgement {
                let partition = transfer.partitions[index]
                return try .init(sessionID: mode == "session" ? UUID() : transfer.session.sessionID,
                    jobID: mode == "job" ? UUID() : transfer.session.jobID,
                    partitionIndex: mode == "ahead" ? 1 : partition.index,
                    transferID: mode == "transfer" ? UUID() : partition.transferID,
                    partitionSHA256: mode == "hash" ? String(repeating: "0", count: 64) : partition.sha256,
                    accepted: mode != "rejected")
            }
            let directory = rig.directory.appendingPathComponent("captures/" + transfer.export.requestSHA256)
            let pending = directory.appendingPathComponent("partition-awaiting-ack.json")
            try await planner.withRetainedCaptureContext(request) { context in
                _ = try context.begin(); _ = try context.preserveTransferFrontier()
                if mode != "unprepared" { try context.preserveAwaitingPartitionAcknowledgement(0) }
                if mode == "older" {
                    _ = try context.reconcilePartitionAcknowledgement(ack(0))
                    try context.preserveAwaitingPartitionAcknowledgement(1)
                    _ = try context.reconcilePartitionAcknowledgement(ack(1))
                }
            }
            if mode == "deleted" { try FileManager.default.removeItem(at: pending) }
            if mode == "corrupt" { try Data("corrupt".utf8).write(to: pending) }
            let original = try? Data(contentsOf: pending)
            let progress = try Data(contentsOf: directory.appendingPathComponent("progress.json"))
            store.querySumResult = { _, _ in XCTFail("No SDK for rejected ACK"); return nil }
            do {
                try await planner.withRetainedCaptureContext(request) { context in
                    _ = try context.begin(); _ = try context.reconcilePartitionAcknowledgement(ack(0))
                }
                XCTFail("Invalid pending ACK returned: " + mode)
            } catch { XCTAssertNotNil(error as? AgentBridgeValidationError) }
            XCTAssertEqual(try? Data(contentsOf: pending), original)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("progress.json")), progress)
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }

    func testNativeTransferFrontierMigratesV5AndRecoversExactPrefixWithoutSDKOrRewrite() async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let transfer = try await planner.prepareTransferExport(request, manager: manager)
            let directory = rig.directory.appendingPathComponent("captures/" + transfer.export.requestSHA256)
            let progressURL = directory.appendingPathComponent("progress.json")
            let old = try Data(contentsOf: progressURL)
            var prefix: AgentBridgeTransferFrontier?
            try await planner.withRetainedCaptureContext(request) { context in
                _ = try context.begin()
                let seed = try context.preserveTransferFrontier()
                XCTAssertEqual(seed.committedPartitionCount, 0)
                prefix = try context.recordAcknowledgedTransferPartition(0)
                XCTAssertEqual(prefix?.committedPartitionCount, 1)
            }
            let retained = try Data(contentsOf: progressURL)
            XCTAssertNotEqual(retained, old)
            store.querySumResult = { _, _ in XCTFail("No SDK for frontier recovery"); return nil }
            try await planner.withRetainedCaptureContext(request) { context in
                _ = try context.begin()
                XCTAssertEqual(try context.preserveTransferFrontier(), prefix)
                XCTAssertEqual(try context.recordAcknowledgedTransferPartition(0), prefix)
            }
            XCTAssertEqual(try Data(contentsOf: progressURL), retained)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("transfer.json")), transfer.checkpointCanonical)
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }
    func testNativeTransferFrontierRejectsSkippedIndexWithoutAdvancing() async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let transfer = try await planner.prepareTransferExport(request, manager: manager)
            let path = rig.directory.appendingPathComponent("captures/" + transfer.export.requestSHA256 + "/progress.json")
            var before = Data()
            do {
                try await planner.withRetainedCaptureContext(request) { context in
                    _ = try context.begin(); _ = try context.preserveTransferFrontier()
                    before = try Data(contentsOf: path)
                    _ = try context.recordAcknowledgedTransferPartition(1)
                    XCTFail("Skipped acknowledgement cannot advance")
                }
            } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .bindingChanged) }
            XCTAssertEqual(try Data(contentsOf: path), before)
        }
    }
    func testNativeTransferFrontierRejectsSignedInconsistentOrPartialProgressWithoutRepair() async throws {
        for mode in ["digest", "count", "partial", "old-with-frontier"] {
            try await withNativeExportPreparation { rig, planner, request, store, manager in
                store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
                let transfer = try await planner.prepareTransferExport(request, manager: manager)
                let path = rig.directory.appendingPathComponent("captures/" + transfer.export.requestSHA256 + "/progress.json")
                try await planner.withRetainedCaptureContext(request) { context in
                    _ = try context.begin(); _ = try context.preserveTransferFrontier()
                }
                var signed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
                var record = try XCTUnwrap(signed["record"] as? [String: Any])
                let bytes = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(record["payload"] as? String)))
                var payload = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                if mode == "digest" { payload["frontierSHA256"] = String(repeating: "f", count: 64) }
                if mode == "count" { payload["committedPartitionCount"] = 3 }
                if mode == "partial" { payload.removeValue(forKey: "frontierSHA256") }
                if mode == "old-with-frontier" { payload["version"] = 5 }
                record["payload"] = try AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: payload)).base64EncodedString()
                let body = try AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: record))
                signed["record"] = record
                signed["mac"] = Data(HMAC<SHA256>.authenticationCode(for: Data("HealthMd.AgentBridge.NativeCaptureSpool.v1\0".utf8) + body,
                    using: try XCTUnwrap(rig.keys.key))).base64EncodedString()
                let damaged = try AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: signed))
                let handle = try FileHandle(forWritingTo: path); try handle.truncate(atOffset: 0)
                try handle.write(contentsOf: damaged); try handle.synchronize(); try handle.close()
                do {
                    _ = try await planner.prepareRetainedTransferExport(request, manager: manager, core: BridgeRenderTamperCore(mode: "forbid"))
                    XCTFail("Signed inconsistent prefix cannot reset or repair")
                } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .spoolMissingRestartRequired) }
                XCTAssertEqual(try Data(contentsOf: path), damaged)
                XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
            }
        }
    }

    func testNativeTransferSenderHandlesNeededThenAlreadyCommittedWithHistoricalPendingMarker() async throws { try await checkNativeTransferSender("mixed") }
    func testNativeTransferSenderCarriesOriginalBytesWithoutCompletionClaim() async throws {
        try await checkNativeTransferSender("needed")
    }
    func testNativeTransferSenderRejectsCompetingReadersWithoutAbandoningOwner() async throws {
        try await checkNativeTransferSender("contended")
    }
    func testNativeTransferSenderSkipsAlreadyCommittedBytes() async throws {
        try await checkNativeTransferSender("already")
    }
    func testNativeTransferSenderRejectsWrongDispositionAndAbandonsOwner() async throws { try await checkNativeTransferSender("bad-disposition") }
    func testNativeTransferSenderRejectsWrongChunkAcknowledgementAndAbandonsOwner() async throws { try await checkNativeTransferSender("bad-chunk") }
    func testNativeTransferSenderRejectsWrongPartitionAcknowledgementAndAbandonsOwner() async throws { try await checkNativeTransferSender("bad-partition") }
    func testNativeTransferSenderRejectsWrongFinalAcknowledgementAndAbandonsOwner() async throws { try await checkNativeTransferSender("bad-final") }
    func testNativeTransferSenderRechecksOwnerAfterReceiveBeforeAnyFurtherWrite() async throws {
        try await checkNativeTransferSender("revoke")
    }
    func testNativeTransferSenderConsumesKeepalivesBeforeEveryACKAndHostCommit() async throws { try await checkNativeTransferSender("complete-keepalive") }
    func testNativeTransferKeepaliveReceiveCannotBypassOwnerRevocation() async throws { try await checkNativeTransferSender("keepalive-revoke") }
    func testNativeTransferPongWriteCannotBypassOwnerRevocation() async throws { try await checkNativeTransferSender("keepalive-write-revoke") }
    func testNativeTransferConfirmsSourceStopAtEachACKAndHostCommitWithoutAnotherReader() async throws {
        for stage in ["disposition", "chunk", "partition", "final", "host"] { try await checkNativeTransferSender("stop-" + stage) }
    }
    func testNativeTransferSourceStopSurvivesUnavailableReadConfiguration() async throws { try await checkNativeTransferSender("stop-read-revoked") }
    func testNativeResumedTransferConfirmsExactRetainedSourceStop() async throws { try await checkNativeTransferSender("stop-resume") }
    func testNativeTransferSourceStopPreservesExistingCompletion() async throws { try await checkNativeTransferSender("stop-complete") }
    func testNativeTransferSourceStopRejectsForeignJobAndAbandonsOwner() async throws { try await checkNativeTransferSender("stop-foreign") }
    func testNativeTransferOrdinaryCancelledErrorsCannotImpersonateConfirmedSourceStop() async throws {
        for taskError in [false, true] {
            try await withNativeExportPreparation { rig, planner, request, store, manager in
                store.querySumResult = { _, _ in 123 }
                _ = try await planner.prepareTransferExport(request, manager: manager)
                let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
                _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
                let wire = NativePlanningResponsePackets()
                let channel = DirectSecureChannel(packetConnection: wire, sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
                defer { channel.cancel() }
                let profiles = try XCTUnwrap(Self.retainedNativeConfigurationObjects.compactMap { $0 as? ExportProfileStore }.last)
                let reconnect = try nativePlanningSession(rig, lifecycle, profiles: profiles, responseChannel: channel)
                do {
                    try await reconnect.transmitTransfer(request, retained: true) { context in
                        _ = try context.begin()
                        if taskError { throw CancellationError() }
                        throw AgentBridgeValidationError.cancelled
                    }
                    XCTFail("Ordinary cancellation returned success")
                } catch {
                    if taskError { XCTAssertTrue(error is CancellationError) }
                    else { XCTAssertEqual(error as? AgentBridgeValidationError, .cancelled) }
                }
                XCTAssertTrue(channel.isLocallyTerminal); XCTAssertTrue(wire.packets.isEmpty)
                XCTAssertFalse(Task.isCancelled); XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
            }
        }
    }
    func testNativeTransferSourceStopWriteFailureAbandonsOwnerWithoutConfirmedProof() async throws { try await checkNativeTransferSender("stop-write-failure") }

    func testNativeTransferSenderResumesExactPrefixWithoutReplayingBytes() async throws { try await checkNativeTransferSender("resume") }
    func testNativeTransferSenderRejectsHostRewindOfRecordedPrefix() async throws { try await checkNativeTransferSender("rewind") }
    func testNativeCapturedCancellationRefusesManifestWithoutRetainedFrontier() async throws { try await checkNativeTransferSender("cancel-no-frontier") }

    func testNativeTransferSenderPublicationFailurePreventsNextPartitionAndFinalize() async throws { try await checkNativeTransferSender("publication") }

    func testNativeCompletionRequiresExactHostReceiptsAndPersistsReplay() async throws { try await checkNativeTransferSender("complete") }
    func testNativeResumeCarriesRetainedPrefixAndConfirmsOriginalCompletionWithoutCapture() async throws { try await checkNativeTransferSender("complete-resume") }
    func testNativeCompletionRejectsChangedInputWithValidCommitKey() async throws { try await checkNativeTransferSender("complete-bad-input") }
    func testNativeCompletionRejectsReorderedReceipts() async throws { try await checkNativeTransferSender("complete-order") }
    func testNativeCompletionRejectsMissingReceipt() async throws { try await checkNativeTransferSender("complete-missing") }
    func testNativeCompletionRejectsReceiptCorruptionAtFinalSend() async throws { try await checkNativeTransferSender("complete-corrupt") }
    func testNativeCompletionRejectsRevocationAtFinalSend() async throws { try await checkNativeTransferSender("complete-revoke") }

    private func nativeHostCommit(_ artifact: AgentBridgeArtifact, request: AgentBridgeExecute, manifest: Data, badInput: Bool = false) throws -> AgentBridgeCommitReceipt {
        let input = badInput ? try AgentBridgeDigest(String(repeating: "1", count: 64)) : artifact.sha256
        let zero = try AgentBridgeDigest(String(repeating: "0", count: 64))
        let provisional = AgentBridgeCommitReceipt(afterSha256: input, artifactId: artifact.artifactId, beforeSha256: zero, commitKey: zero,
            destination: request.plan.intent.destination, inputSha256: input, jobId: request.jobId,
            manifestSha256: try AgentBridgeDigest(AgentBridgeV4Codec.sha256(manifest)), peer: request.plan.intent.peer,
            relativePath: artifact.relativePath, requestSha256: try AgentBridgeDigest(AgentBridgeV4Codec.sha256(AgentBridgeV4Codec.encode(request))),
            status: .committed, writeMode: try XCTUnwrap(AgentBridgeCommitReceiptWriteMode(rawValue: artifact.writeMode.rawValue)))
        return .init(afterSha256: provisional.afterSha256, artifactId: provisional.artifactId, beforeSha256: provisional.beforeSha256,
            commitKey: try AgentBridgeSemantics.commitKey(provisional), destination: provisional.destination, inputSha256: provisional.inputSha256,
            jobId: provisional.jobId, manifestSha256: provisional.manifestSha256, peer: provisional.peer, relativePath: provisional.relativePath,
            requestSha256: provisional.requestSha256, status: provisional.status, writeMode: provisional.writeMode)
    }

    private func checkNativeTransferSender(_ mode: String) async throws {
        print("Test Case [STOP-DIAG] fixture-begin mode=\(mode) uptime=\(ProcessInfo.processInfo.systemUptime)")
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            print("Test Case [STOP-DIAG] fixture-issuer-ready mode=\(mode) uptime=\(ProcessInfo.processInfo.systemUptime)")
            store.querySumResult = { _, _ in 123 }
            let original = try await planner.prepareTransferExport(request, manager: manager)
            print("Test Case [STOP-DIAG] fixture-original-prepared mode=\(mode) uptime=\(ProcessInfo.processInfo.systemUptime)")
            if mode == "cancel-no-frontier" {
                let job = try XCTUnwrap(rig.store.snapshot().acceptedJobs?.first)
                let directory = rig.directory.appendingPathComponent("captures/" + job.requestSHA256.rawValue)
                XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent("manifest.json").path))
                let state = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("progress.json"))) as? [String: Any])
                let record = try XCTUnwrap(state["record"] as? [String: Any])
                let payload = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(record["payload"] as? String)))
                XCTAssertEqual((try JSONSerialization.jsonObject(with: payload) as? [String: Any])?["version"] as? Int, 5)
                let cancel = try self.cancellationRequest(request)
                _ = try rig.service.requestCancellation(cancel, authenticatedPeer: rig.peer)
                let file = rig.directory.appendingPathComponent("state.json"), before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
                XCTAssertThrowsError(try rig.restartedService().finalizeCapturedCancellation(cancel, authenticatedPeer: rig.peer, fileProtection: rig.captureProtection)) {
                    XCTAssertEqual($0 as? AgentBridgeValidationError, .spoolMissingRestartRequired)
                }
                XCTAssertEqual(try Data(contentsOf: file), before); XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
                return
            }
            let stopTransfer = mode.hasPrefix("stop-")
            let keepalive = mode.contains("keepalive")
            let completion = mode.hasPrefix("complete") || mode == "stop-host"
            let resumedPrefix = mode == "resume" || mode == "complete-resume" || mode == "stop-resume"
            var resumeEnvelope: AgentBridgeResume?
            let originalManifest = try AgentBridgeV4Codec.decode(AgentBridgeArtifactManifest.self, from: original.export.manifestCanonical)
            var hostReceipts = try originalManifest.artifacts.map { try self.nativeHostCommit($0, request: request, manifest: original.export.manifestCanonical, badInput: mode == "complete-bad-input") }
            if mode == "complete-order" { hostReceipts.reverse() }
            if mode == "complete-missing" { hostReceipts.removeLast() }
            let acceptedBeforeResume = try rig.store.snapshot().acceptedJobs
            let originalJob = try XCTUnwrap(acceptedBeforeResume?.first)
            let completionDirectory = rig.directory.appendingPathComponent("captures/" + originalJob.requestSHA256.rawValue)

            if resumedPrefix || mode == "rewind" {
                try await planner.withRetainedCaptureContext(request) { context in
                    _ = try context.begin(); _ = try context.preserveTransferFrontier()
                    _ = try context.recordAcknowledgedTransferPartition(0)
                    if mode == "complete-resume" || mode == "stop-resume" { resumeEnvelope = try self.resumeRequest(request, transfer: original, frontier: context.preserveTransferFrontier()) }
                }
            }
            var priorCompletion: AgentBridgeExecutionReceipt?
            if mode == "stop-complete" {
                try await planner.withRetainedCaptureContext(request) { context in
                    _ = try context.begin(); _ = try context.preserveTransferFrontier()
                    for partition in original.partitions { _ = try context.recordAcknowledgedTransferPartition(Int64(partition.index)) }
                    for receipt in hostReceipts { try context.recordHostCommit(receipt) }
                    priorCompletion = try context.preserveCompletion()
                }
            }
            print("Test Case [STOP-DIAG] fixture-retained-prefix-ready mode=\(mode) uptime=\(ProcessInfo.processInfo.systemUptime)")
            let key = SymmetricKey(data: Data(repeating: 19, count: 32))
            var responses: [DirectMessage] = []
            for partition in original.partitions {
                let already = mode == "already" || (resumedPrefix && partition.index == 0) || (mode == "mixed" && partition.index > 0)
                responses.append(.transferDisposition(try .init(sessionID: original.session.sessionID,
                    jobID: mode == "bad-disposition" ? UUID() : original.session.jobID, partitionIndex: partition.index,
                    partitionSHA256: partition.sha256, disposition: already ? .alreadyCommitted : .needed)))
                if !already {
                    responses.append(.transferChunkAcknowledgement(try .init(transferID: partition.transferID,
                        sequence: mode == "bad-chunk" ? 2 : 1, accepted: true, sha256: partition.sha256)))
                    responses.append(.transferPartitionAcknowledgement(try .init(sessionID: original.session.sessionID,
                        jobID: mode == "bad-partition" ? UUID() : original.session.jobID, partitionIndex: partition.index,
                        transferID: partition.transferID, partitionSHA256: partition.sha256, accepted: true)))
                }
            }
            responses.append(.transferFinalAcknowledgement(try .init(sessionID: original.session.sessionID,
                jobID: original.session.jobID, accepted: true, totalPartitions: original.partitions.count,
                totalBytes: Int64(original.export.totalByteCount) + (mode == "bad-final" ? 1 : 0),
                finalPartitionSHA256: original.partitions.last?.sha256)))
            var incoming = try responses.map { try JSONEncoder().encode($0) }
            if completion { incoming += try hostReceipts.map { try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .commit($0))) } }
            let expectedPongs = keepalive ? incoming.count : 0
            let originalStop = try self.cancellationRequest(request)
            let stop = mode == "stop-foreign" ? AgentBridgeCancel(approvalId: originalStop.approvalId,
                authorityId: originalStop.authorityId, jobId: try id(99), peer: originalStop.peer,
                requestSha256: originalStop.requestSha256) : originalStop
            var stopIndex: Int?
            if stopTransfer {
                if mode == "stop-host" { stopIndex = responses.count }
                else { stopIndex = responses.firstIndex { message in
                    switch (mode, message) {
                    case ("stop-chunk", .transferChunkAcknowledgement),
                         ("stop-partition", .transferPartitionAcknowledgement),
                         ("stop-final", .transferFinalAcknowledgement): return true
                    case (_, .transferDisposition): return !["stop-chunk", "stop-partition", "stop-final"].contains(mode)
                    default: return false
                    }
                } }
                incoming.insert(try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .cancel(stop))), at: try XCTUnwrap(stopIndex))
            }
            let selectedStopIndex = stopIndex
            let stopState = NativeTransferStopState()
            if keepalive {
                incoming = try incoming.flatMap { [try JSONEncoder().encode(DirectMessage.ping), try JSONEncoder().encode(DirectMessage.pong), $0] }
            }
            let inbound = try incoming.enumerated().map { try nativeResponsePacket($0.element, sequence: UInt64($0.offset), key: key) }
            let writeState = NativeTransferWriteState()
            let wire = NativePlanningResponsePackets(beforeWrite: {
                if mode == "stop-write-failure" {
                    try await MainActor.run {
                        if stopState.received { throw CocoaError(.fileWriteUnknown) }
                    }
                }
                // The first pong follows manifest, session, file manifests and transfer-open.
                await MainActor.run {
                    if mode == "keepalive-write-revoke", writeState.count == 3 + original.export.baseFiles.count { rig.session.revoke() }
                    writeState.count += 1
                }
                if completion { try await MainActor.run {
                    if FileManager.default.fileExists(atPath: completionDirectory.appendingPathComponent("completion.json").path) {
                        if mode == "complete-revoke" { rig.session.revoke() }
                        if mode == "complete-corrupt", let first = originalManifest.artifacts.first { try Data("corrupt".utf8).write(to: completionDirectory.appendingPathComponent("host-commit-\(first.artifactId.rawValue).json")) }
                    }
                } }
            }, inbound: inbound, beforeReceive: {
                await MainActor.run {
                    if stopState.nextReceive == selectedStopIndex { stopState.received = true }
                    stopState.nextReceive += 1
                }
                if mode == "revoke" || mode == "keepalive-revoke" { await MainActor.run { rig.session.revoke() } }
            })
            let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
            _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let profiles = try XCTUnwrap(Self.retainedNativeConfigurationObjects.compactMap { $0 as? ExportProfileStore }.last)
            let channel = DirectSecureChannel(packetConnection: wire, sessionKey: key, peerInstallationID: UUID(), peerDisplayName: "Synthetic sender")
            defer { channel.cancel() }
            var finalNativeRead: (() throws -> Void)?
            let reconnect = try nativePlanningSession(rig, lifecycle, profiles: profiles, responseChannel: channel, beforeNativeRead: {
                if mode == "stop-read-revoked", stopState.received { XCTFail("Source stop reentered unavailable read configuration"); throw AgentBridgeValidationError.permissionRequired }
                try finalNativeRead?()
            })
            let job = try XCTUnwrap(rig.store.snapshot().acceptedJobs?.first)
            let directory = rig.directory.appendingPathComponent("captures/" + job.requestSHA256.rawValue)
            store.querySumResult = { _, _ in XCTFail("No SDK on immutable carriage"); return nil }
            var publicationInterrupted = false
            if mode == "publication" {
                rig.captureProtection.onRequire = { _ in
                    guard !publicationInterrupted, let bytes = try? Data(contentsOf: directory.appendingPathComponent("progress.json")),
                          let signed = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                          let record = signed["record"] as? [String: Any], let encoded = record["payload"] as? String,
                          let payload = Data(base64Encoded: encoded), let progress = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                          progress["committedPartitionCount"] as? Int == 1 else { return }
                    publicationInterrupted = true; throw AgentBridgeValidationError.bindingChanged
                }
            }
            defer { rig.captureProtection.onRequire = nil }
            if stopTransfer {
                print("Test Case [STOP-DIAG] fixture-stop-send-begin mode=\(mode) uptime=\(ProcessInfo.processInfo.systemUptime)")
                var failure: Error?
                do {
                    if mode == "stop-resume" { try await reconnect.sendResumedExecutionExport(XCTUnwrap(resumeEnvelope), manager: manager, core: BridgeRenderTamperCore(mode: "forbid")) }
                    else if completion { try await reconnect.sendExecutionExport(request, manager: manager, retained: true, core: BridgeRenderTamperCore(mode: "forbid")) }
                    else { try await reconnect.sendTransferExport(request, manager: manager, retained: true, core: BridgeRenderTamperCore(mode: "forbid")) }
                } catch { failure = error }
                print("Test Case [STOP-DIAG] fixture-stop-send-returned mode=\(mode) uptime=\(ProcessInfo.processInfo.systemUptime)")
                XCTAssertTrue(stopState.received)
                let unsafe = ["stop-foreign", "stop-write-failure"].contains(mode)
                func receipts() throws -> [AgentBridgeExecutionReceipt] {
                    try wire.packets.compactMap { packet in
                        guard case .encrypted(let frame) = packet else { return nil }
                        let bytes = Data(try ManualIPSyncSecurity.open(frame, using: key).dropFirst(16))
                        guard let envelope = try? AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes),
                              case .receipt(let receipt) = envelope.payload else { return nil }
                        return receipt
                    }
                }
                if unsafe {
                    XCTAssertNotNil(failure); XCTAssertTrue(channel.isLocallyTerminal); XCTAssertTrue(try receipts().isEmpty)
                    let count = wire.packets.count
                    do { try await reconnect.sendTransferExport(request, manager: manager, retained: true); XCTFail("Abandoned owner revived") }
                    catch { XCTAssertEqual(wire.packets.count, count) }
                    if mode == "stop-foreign" { XCTAssertTrue(try rig.store.snapshot().cancellationIntents?.isEmpty ?? true) }
                } else {
                    if mode == "stop-complete" { XCTAssertNil(failure) }
                    else { XCTAssertEqual(failure as? AgentBridgeValidationError, .cancelled); XCTAssertFalse(Task.isCancelled) }
                    let receipt = try XCTUnwrap(receipts().last)
                    XCTAssertTrue(receipt.sourceAcknowledged); XCTAssertEqual(receipt.requestSha256.rawValue, original.export.requestSHA256)
                    XCTAssertEqual(receipt.status, priorCompletion?.status ?? .cancelled)
                    let expectedCount = mode == "stop-resume" ? 1 : (["stop-complete", "stop-final", "stop-host"].contains(mode) ? original.partitions.count : 0)
                    XCTAssertEqual(receipt.committedPartitionCount, Int64(expectedCount))
                    if let priorCompletion { XCTAssertEqual(receipt, priorCompletion) }
                    XCTAssertFalse(channel.isLocallyTerminal)
                    let stateFile = rig.directory.appendingPathComponent("state.json"), before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
                    let pendingReads = wire.receiveCount
                    print("Test Case [STOP-DIAG] fixture-replay-begin mode=\(mode) uptime=\(ProcessInfo.processInfo.systemUptime)")
                    try await reconnect.handleAndSend(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .cancel(stop))))
                    print("Test Case [STOP-DIAG] fixture-replay-returned mode=\(mode) uptime=\(ProcessInfo.processInfo.systemUptime)")
                    XCTAssertEqual(try receipts().last, receipt); XCTAssertEqual(try Data(contentsOf: stateFile), before)
                    XCTAssertEqual(wire.receiveCount, pendingReads)
                }
                XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
                return
            }
            let fails = (completion && !["complete", "complete-resume", "complete-keepalive"].contains(mode)) || mode.hasPrefix("bad-") || ["revoke", "rewind", "publication", "keepalive-revoke", "keepalive-write-revoke"].contains(mode)
            do {
                if mode == "contended" {
                    try await reconnect.transmitTransfer(request, retained: true) { context in
                        _ = try context.begin()
                        do { _ = try await reconnect.receiveAndHandleNext(); XCTFail("Competing reader must reject") }
                        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .busy) }
                        do { try await reconnect.handleAndSend(nativeDiscoveryBytes(rig)); XCTFail("Competing response must reject") }
                        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .busy) }
                        do { try await reconnect.withRetainedCaptureContext(request) { _ in XCTFail("Competing capture must reject") }; XCTFail("Expected busy") }
                        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .busy) }
                        return original
                    }
                } else if mode == "complete-resume" {
                    try await reconnect.sendResumedExecutionExport(XCTUnwrap(resumeEnvelope), manager: manager, core: BridgeRenderTamperCore(mode: "forbid"))
                } else if completion {
                    try await reconnect.sendExecutionExport(request, manager: manager, retained: true, core: BridgeRenderTamperCore(mode: "forbid"))
                } else {
                    try await reconnect.sendTransferExport(request, manager: manager, retained: true, core: BridgeRenderTamperCore(mode: "forbid"))
                }
                if fails { XCTFail("Expected acknowledgement/owner rejection") }
            } catch {
                if !fails { throw error }
                if mode != "complete-missing" { XCTAssertNotNil(error as? AgentBridgeValidationError) }
                let count = wire.packets.count
                do { try await reconnect.sendTransferExport(request, manager: manager, retained: true); XCTFail("Failed owner cannot revive") }
                catch { XCTAssertEqual(wire.packets.count, count) }
            }
            var messages: [DirectMessage] = []; var chunks: [DirectTransferChunk] = []; var terminal: [AgentBridgeExecutionReceipt] = []
            let decoder = JSONDecoder(); decoder.dateDecodingStrategy = .iso8601
            for (sequence, packet) in wire.packets.enumerated() {
                guard case .encrypted(let frame) = packet else { return XCTFail("Expected guarded encrypted packet") }
                let plaintext = try ManualIPSyncSecurity.open(frame, using: key)
                let bytes = Data(plaintext.dropFirst(16))
                if sequence == 0 {
                    let envelope = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes)
                    guard case .manifest(let manifest) = envelope.payload else { return XCTFail("Expected original v4 manifest first") }
                    XCTAssertEqual(try AgentBridgeV4Codec.encode(manifest), original.export.manifestCanonical)
                } else if let envelope = try? AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes) {
                    guard case .receipt(let receipt) = envelope.payload else { return XCTFail("Unexpected v4 control") }; terminal.append(receipt)
                } else if DirectTransferBinaryFrame.isBinaryFrame(bytes) {
                    chunks.append(try DirectTransferBinaryFrame.decode(bytes).chunk)
                } else { messages.append(try decoder.decode(DirectMessage.self, from: bytes)) }
            }
            if keepalive {
                XCTAssertEqual(messages.filter { $0 == .pong }.count, fails ? 0 : expectedPongs)
                if !fails { XCTAssertNotNil(reconnect.lastInboundActivityAt); _ = try reconnect.requireCurrent() }
            }
            if mode == "mixed" {
                try await reconnect.withRetainedCaptureContext(request) { context in
                    _ = try context.begin()
                    XCTAssertEqual(try context.preserveTransferFrontier().committedPartitionCount, Int64(original.partitions.count))
                }
            }
            if mode == "complete-resume" {
                XCTAssertEqual(try rig.store.snapshot().acceptedJobs, acceptedBeforeResume)
            }
            XCTAssertEqual(messages.first, .transferSession(original.session))
            XCTAssertEqual(Array(messages.dropFirst().prefix(original.export.baseFiles.count)), original.export.baseFiles.map { .fileManifest($0.manifest) })
            XCTAssertEqual(messages.filter { if case .completionConfirmed = $0 { return true }; return false }.count, completion && !fails ? 1 : 0)
            XCTAssertEqual(terminal.count, completion && !fails ? 1 : 0)
            if completion && !fails {
                let receipt = try XCTUnwrap(terminal.first); XCTAssertTrue(receipt.sourceAcknowledged); XCTAssertEqual(receipt.status, .complete)
                let before = try Data(contentsOf: completionDirectory.appendingPathComponent("completion.json"))
                try await reconnect.withRetainedCaptureContext(request) { context in
                    _ = try context.begin()
                    for commit in hostReceipts { try context.recordHostCommit(commit) }
                    XCTAssertEqual(try context.preserveCompletion(), receipt)
                }
                XCTAssertEqual(try Data(contentsOf: completionDirectory.appendingPathComponent("completion.json")), before)
                let state = try rig.store.snapshot()
                let reservation = AgentBridgeExportCaptureReservation(job: try XCTUnwrap(state.acceptedJobs?.first { $0.requestSHA256 == receipt.requestSha256 }),
                    claim: try XCTUnwrap(state.captureClaims?.first { $0.requestSHA256 == receipt.requestSha256 }))
                let stopped = try rig.store.openCaptureSpool(reservation, create: false, fileProtection: rig.captureProtection) {}
                do {
                    let checkpoint = try stopped.inspectCancellationCheckpoint()
                    XCTAssertEqual(checkpoint.completion, receipt)
                    XCTAssertEqual(checkpoint.manifestSHA256, receipt.manifestSha256.rawValue)
                    XCTAssertEqual(checkpoint.frontierSHA256, receipt.frontierSha256.rawValue)
                    try stopped.requireCancellationCheckpoint(checkpoint)
                    XCTAssertEqual(try Data(contentsOf: completionDirectory.appendingPathComponent("completion.json")), before)
                } catch { stopped.close(); throw error }
                stopped.close()
                var replacedAtNativeCallback = false
                do { try await reconnect.withRetainedCaptureContext(request) { context in
                    _ = try context.begin()
                    let retained = try context.preserveCompletion()
                    finalNativeRead = {
                        if !replacedAtNativeCallback {
                            replacedAtNativeCallback = true
                            let path = completionDirectory.appendingPathComponent("completion.json")
                            let replacement = completionDirectory.appendingPathComponent("pending-" + UUID().uuidString.lowercased())
                            try before.write(to: replacement)
                            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: replacement.path)
                            let fd = Darwin.open(replacement.path, O_RDONLY | O_NOFOLLOW | O_CLOEXEC)
                            guard fd >= 0 else { throw AgentBridgeValidationError.bindingChanged }
                            defer { Darwin.close(fd) }
                            try rig.captureProtection.applyCompleteProtection(fd)
                            guard Darwin.rename(replacement.path, path.path) == 0 else { throw AgentBridgeValidationError.bindingChanged }
                        }
                    }
                    defer { finalNativeRead = nil }
                    XCTAssertThrowsError(try context.requirePreservedCompletion(retained))
                }; XCTFail("An invalidated capture owner must not return success") }
                catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
                XCTAssertTrue(replacedAtNativeCallback)
                XCTAssertEqual(try Data(contentsOf: completionDirectory.appendingPathComponent("completion.json")), before)
                let cancel = try self.cancellationRequest(request)
                _ = try rig.service.requestCancellation(cancel, authenticatedPeer: rig.peer)
                XCTAssertEqual(try rig.restartedService().finalizeCapturedCancellation(cancel, authenticatedPeer: rig.peer,
                    fileProtection: rig.captureProtection), receipt)
                XCTAssertEqual(try Data(contentsOf: completionDirectory.appendingPathComponent("completion.json")), before)
            }
            if !fails {
                XCTAssertEqual(chunks.count, mode == "already" ? 0 : original.partitions.count - (resumedPrefix || mode == "mixed" ? 1 : 0))
                for (chunk, file) in zip(chunks, original.export.baseFiles.dropFirst(resumedPrefix ? 1 : 0)) { XCTAssertEqual(chunk.sequence, 1); XCTAssertEqual(chunk.data, file.content); XCTAssertEqual(chunk.sha256, file.manifest.sha256) }
                XCTAssertEqual(wire.receiveCount, inbound.count)
            }
            if mode == "revoke" { XCTAssertEqual(messages.count, 2 + original.export.baseFiles.count) }
            if mode == "rewind" { XCTAssertTrue(chunks.isEmpty) }
            if mode == "publication" {
                XCTAssertTrue(publicationInterrupted)
                XCTAssertEqual(chunks.count, 1)
                XCTAssertFalse(messages.contains { if case .transferFinalize = $0 { return true }; return false })
                XCTAssertEqual(messages.filter { if case .transferOpen = $0 { return true }; return false }.count, 1)
            }
            let signed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("progress.json"))) as? [String: Any])
            let record = try XCTUnwrap(signed["record"] as? [String: Any])
            let payload = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(record["payload"] as? String)))
            let progress = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
            let count = (!fails || mode == "bad-final" || completion) ? original.partitions.count : (["rewind", "publication"].contains(mode) ? 1 : 0)
            var expected = try AgentBridgeTransferFrontier(jobID: request.jobId, requestSHA256: AgentBridgeDigest(original.export.requestSHA256),
                manifestSHA256: AgentBridgeDigest(AgentBridgeV4Codec.sha256(original.export.manifestCanonical)),
                sessionID: AgentBridgeUUID(original.session.sessionID.uuidString.lowercased()))
            for (index, partition) in original.partitions.prefix(count).enumerated() {
                expected = try expected.appending(.init(partitionIndex: Int64(index), transferID: AgentBridgeUUID(partition.transferID.uuidString.lowercased()),
                    artifactID: AgentBridgeUUID(original.export.baseFiles[index].manifest.fileID.uuidString.lowercased()),
                    artifactOffset: 0, byteCount: partition.byteCount, chunkCount: Int64(partition.chunkCount), sha256: AgentBridgeDigest(partition.sha256)))
            }
            XCTAssertEqual(progress["version"] as? Int, 6)
            XCTAssertEqual(progress["committedPartitionCount"] as? Int, count)
            XCTAssertEqual(progress["frontierSHA256"] as? String, expected.sha256.rawValue)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("transfer.json")), original.checkpointCanonical)
            if mode == "publication" {
                func snapshot() throws -> [String: Data] {
                    try Dictionary(uniqueKeysWithValues: FileManager.default.contentsOfDirectory(atPath: directory.path).map { ($0, try Data(contentsOf: directory.appendingPathComponent($0))) })
                }
                let before = try snapshot(), cancel = try self.cancellationRequest(request)
                _ = try rig.service.requestCancellation(cancel, authenticatedPeer: rig.peer)
                let receipt = try rig.restartedService().finalizeCapturedCancellation(cancel, authenticatedPeer: rig.peer, fileProtection: rig.captureProtection)
                XCTAssertEqual(receipt.status, .cancelled); XCTAssertTrue(receipt.sourceAcknowledged)
                XCTAssertEqual(receipt.artifactCount, Int64(originalManifest.artifacts.count))
                XCTAssertEqual(receipt.manifestSha256.rawValue, AgentBridgeV4Codec.sha256(original.export.manifestCanonical))
                XCTAssertEqual(receipt.committedPartitionCount, 1); XCTAssertEqual(receipt.frontierSha256, expected.sha256)
                XCTAssertEqual(try snapshot(), before)
            }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }

    func testNativeExportProducerPreparesEveryApprovedDayAndRecoversExactSet() async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let result = try await planner.prepareExport(request, manager: manager)
            let job = try XCTUnwrap(rig.store.snapshot().acceptedJobs?.first)
            let resolution = try PropertyListDecoder().decode(AgentBridgeRequestSettingsResolution.self, from: job.nativeResolution)
            XCTAssertEqual(result.requestSHA256, job.requestSHA256.rawValue)
            XCTAssertEqual(result.days.map(\.day), resolution.requestedDays)
            XCTAssertEqual(result.days.map { $0.artifact.relativePath }, resolution.predictedRelativePaths)
            XCTAssertEqual(result.days.count, 2)
            XCTAssertEqual(Set(result.publicArtifactIDs.keys), Set(resolution.requestedDays.map(\.rawValue)))
            XCTAssertEqual(Set(result.publicArtifactIDs.values).count, 2)
            for id in result.publicArtifactIDs.values { _ = try AgentBridgeUUID(id) }
            let progressURL = rig.directory.appendingPathComponent("captures").appendingPathComponent(job.requestSHA256.rawValue).appendingPathComponent("progress.json")
            let progressBefore = try Data(contentsOf: progressURL)
            let manifest = try AgentBridgeV4Codec.decode(AgentBridgeArtifactManifest.self, from: result.manifestCanonical)
            XCTAssertEqual(try AgentBridgeV4Codec.encode(manifest), result.manifestCanonical)
            XCTAssertEqual(manifest.jobId, request.jobId)
            XCTAssertEqual(manifest.requestSha256.rawValue, result.requestSHA256)
            XCTAssertEqual(manifest.binding, AgentBridgeSemantics.binding(request.plan))
            XCTAssertEqual(manifest.captureStatus, .complete)
            XCTAssertEqual(manifest.branchStatuses.map(\.selectorId.rawValue), ["steps"])
            XCTAssertEqual(manifest.branchStatuses.map(\.recordCount), [2])
            XCTAssertEqual(manifest.artifacts.count, result.days.count)
            for (artifact, day) in zip(manifest.artifacts, result.days) {
                XCTAssertEqual(artifact.artifactId.rawValue, result.publicArtifactIDs[day.day.rawValue])
                XCTAssertEqual(artifact.relativePath.rawValue, day.artifact.relativePath)
                XCTAssertEqual(artifact.sha256.rawValue, day.artifact.sha256)
                XCTAssertEqual(artifact.byteCount, Int64(day.artifact.byteCount))
                XCTAssertEqual(artifact.profile, .appleV8); XCTAssertEqual(artifact.writeMode, .overwrite)
            }
            XCTAssertEqual(result.baseFiles.count, manifest.artifacts.count)
            for (file, artifact) in zip(result.baseFiles, manifest.artifacts) {
                XCTAssertEqual(file.manifest.jobID.uuidString.lowercased(), request.jobId.rawValue)
                XCTAssertEqual(file.manifest.fileID.uuidString.lowercased(), artifact.artifactId.rawValue)
                XCTAssertEqual(file.manifest.relativePath, artifact.relativePath.rawValue)
                XCTAssertEqual(file.manifest.byteCount, artifact.byteCount)
                XCTAssertEqual(file.manifest.sha256, artifact.sha256.rawValue)
                XCTAssertEqual(file.manifest.writeMode, .overwrite)
                XCTAssertEqual(file.content.count, Int(file.manifest.byteCount))
                XCTAssertEqual(AgentBridgeV4Codec.sha256(file.content), file.manifest.sha256)
                XCTAssertEqual(try JSONDecoder().decode(DirectExportFileManifest.self,
                    from: JSONEncoder().encode(file.manifest)), file.manifest)
            }
            XCTAssertEqual(result.totalByteCount, result.days.reduce(0) { $0 + $1.artifact.byteCount })
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
            do { _ = try await planner.prepareExport(request, manager: manager); XCTFail("New execution must not replay capture") }
            catch { XCTAssertEqual(error as? AgentBridgeValidationError, .busy) }
            store.errorsForSum[HKQuantityTypeIdentifier.stepCount.rawValue] = NSError(domain: "must-not-query", code: 1)
            let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
            let restored = try await planner.prepareRetainedExport(request, manager: manager, core: BridgeRenderTamperCore(mode: "forbid"))
            XCTAssertEqual(restored.requestSHA256, result.requestSHA256)
            XCTAssertEqual(restored.totalByteCount, result.totalByteCount)
            XCTAssertEqual(restored.publicArtifactIDs, result.publicArtifactIDs)
            XCTAssertEqual(restored.manifestCanonical, result.manifestCanonical)
            XCTAssertEqual(restored.baseFiles.map(\.manifest), result.baseFiles.map(\.manifest))
            XCTAssertEqual(restored.baseFiles.map(\.content), result.baseFiles.map(\.content))
            XCTAssertEqual(try Data(contentsOf: progressURL), progressBefore)
            XCTAssertEqual(restored.days.map(\.day), result.days.map(\.day))
            for (actual, expected) in zip(restored.days, result.days) {
                XCTAssertEqual(actual.artifact, expected.artifact)
                XCTAssertEqual(actual.buildInfo, expected.buildInfo)
            }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
            XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        }
    }

    func testNativeBaseManifestAdapterRejectsMetadataAndWholeSetDrift() async throws {
        try await withNativeExportPreparation { _, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let result = try await planner.prepareExport(request, manager: manager)
            let object = try XCTUnwrap(JSONSerialization.jsonObject(with: result.manifestCanonical) as? [String: Any])
            let changes: [(String, Any)] = [("artifact_id", UUID().uuidString.lowercased()),
                ("relative_path", "different.json"), ("byte_count", 1), ("sha256", String(repeating: "0", count: 64)),
                ("write_mode", "append"), ("profile", "android-frozen-v4"), ("media_type", "text/csv")]
            for (key, value) in changes {
                var changed = object
                var artifacts = try XCTUnwrap(changed["artifacts"] as? [[String: Any]])
                artifacts[0][key] = value; changed["artifacts"] = artifacts
                let bytes = try AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: changed))
                XCTAssertThrowsError(try AgentBridgeNativePreparedExport.make(request: request, days: result.days,
                    totalByteCount: result.totalByteCount, publicArtifactIDs: result.publicArtifactIDs, manifestCanonical: bytes), key)
            }
            XCTAssertThrowsError(try AgentBridgeNativePreparedExport.make(request: request, days: Array(result.days.dropLast()),
                totalByteCount: result.totalByteCount, publicArtifactIDs: result.publicArtifactIDs, manifestCanonical: result.manifestCanonical))
            XCTAssertThrowsError(try AgentBridgeNativePreparedExport.make(request: request, days: result.days,
                totalByteCount: result.totalByteCount + 1, publicArtifactIDs: result.publicArtifactIDs, manifestCanonical: result.manifestCanonical))
            var changed = object; changed["request_sha256"] = String(repeating: "0", count: 64)
            XCTAssertThrowsError(try AgentBridgeNativePreparedExport.make(request: request, days: result.days,
                totalByteCount: result.totalByteCount, publicArtifactIDs: result.publicArtifactIDs,
                manifestCanonical: AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: changed))))
            let artifacts = try XCTUnwrap(object["artifacts"] as? [[String: Any]])
            var partial = object; partial["artifacts"] = Array(artifacts.dropLast())
            XCTAssertThrowsError(try AgentBridgeNativePreparedExport.make(request: request, days: Array(result.days.dropLast()),
                totalByteCount: result.days[0].artifact.byteCount,
                publicArtifactIDs: result.publicArtifactIDs.filter { $0.key == result.days[0].day.rawValue },
                manifestCanonical: AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: partial))))
            var reversed = object; reversed["artifacts"] = Array(artifacts.reversed())
            XCTAssertThrowsError(try AgentBridgeNativePreparedExport.make(request: request, days: Array(result.days.reversed()),
                totalByteCount: result.totalByteCount, publicArtifactIDs: result.publicArtifactIDs,
                manifestCanonical: AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: reversed))))
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }

    private func transferReconnect(_ rig: Rig, capabilities: DirectTransferCapabilities) throws -> AgentBridgeNativePlanningSession {
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let profiles = try XCTUnwrap(Self.retainedNativeConfigurationObjects.compactMap { $0 as? ExportProfileStore }.last)
        let channel = DirectSecureChannel(packetConnection: NativePlanningResponsePackets(), sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic reconnect")
        return try nativePlanningSession(rig, lifecycle, profiles: profiles, responseChannel: channel,
            transferNegotiation: DirectTransferCapabilities.current.negotiated(with: capabilities), peerTransferCapabilities: capabilities)
    }
    private func transferPeer(minimum: Int64 = DirectTransferLimits.minimumPartitionBytes,
        preferred: Int64 = DirectTransferLimits.preferredPartitionBytes,
        maximum: Int64 = DirectTransferLimits.maximumPartitionBytes, window: Int = 4) -> DirectTransferCapabilities {
        .init(protocolVersions: [1], binaryFrameVersions: [1], minimumPartitionBytes: minimum,
            preferredPartitionBytes: preferred, maximumPartitionBytes: maximum, maximumInFlightChunks: window)
    }

    func testRetainedTransferAllowsChangedPreferredTargetWithoutRewritingOriginal() async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            let original = try await planner.prepareTransferExport(request, manager: manager)
            let job = try XCTUnwrap(rig.store.snapshot().acceptedJobs?.first)
            let path = rig.directory.appendingPathComponent("captures").appendingPathComponent(job.requestSHA256.rawValue)
            let progress = try Data(contentsOf: path.appendingPathComponent("progress.json"))
            let capabilities = transferPeer(preferred: DirectTransferLimits.maximumPartitionBytes, window: 8)
            XCTAssertNotEqual(DirectTransferCapabilities.current.negotiated(with: capabilities)?.partitionTargetBytes, original.session.partitionTargetBytes)
            let reconnect = try transferReconnect(rig, capabilities: capabilities)
            store.errorsForSum[HKQuantityTypeIdentifier.stepCount.rawValue] = NSError(domain: "must-not-query", code: 1)
            let restored = try await reconnect.prepareRetainedTransferExport(request, manager: manager, core: BridgeRenderTamperCore(mode: "forbid"))
            XCTAssertEqual(restored.session, original.session); XCTAssertEqual(restored.partitions, original.partitions)
            XCTAssertEqual(restored.checkpointCanonical, original.checkpointCanonical)
            XCTAssertEqual(try Data(contentsOf: path.appendingPathComponent("progress.json")), progress)
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }

    func testRetainedTransferRejectsUnsupportedOriginalTargetOrWindowWithoutMutation() async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            let original = try await planner.prepareTransferExport(request, manager: manager)
            let job = try XCTUnwrap(rig.store.snapshot().acceptedJobs?.first)
            let path = rig.directory.appendingPathComponent("captures").appendingPathComponent(job.requestSHA256.rawValue)
            let progress = try Data(contentsOf: path.appendingPathComponent("progress.json"))
            store.errorsForSum[HKQuantityTypeIdentifier.stepCount.rawValue] = NSError(domain: "must-not-query", code: 1)
            for caps in [transferPeer(window: 2), transferPeer(minimum: DirectTransferLimits.maximumPartitionBytes, preferred: DirectTransferLimits.maximumPartitionBytes)] {
                let reconnect = try transferReconnect(rig, capabilities: caps)
                do { _ = try await reconnect.prepareRetainedTransferExport(request, manager: manager, core: BridgeRenderTamperCore(mode: "forbid")); XCTFail("Current support must cover original limits") }
                catch { XCTAssertEqual(error as? AgentBridgeValidationError, .unsupportedCapability) }
                XCTAssertEqual(try Data(contentsOf: path.appendingPathComponent("progress.json")), progress)
                XCTAssertEqual(try Data(contentsOf: path.appendingPathComponent("transfer.json")), original.checkpointCanonical)
            }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
            let supported = try transferReconnect(rig, capabilities: .current)
            let restored = try await supported.prepareRetainedTransferExport(request, manager: manager, core: BridgeRenderTamperCore(mode: "forbid"))
            XCTAssertEqual(restored.checkpointCanonical, original.checkpointCanonical)
        }
    }

    func testNativeTransferRequiresCurrentPeerCapabilitiesBeforeSDK() async throws {
        try await withNativeExportPreparation(peerTransferCapabilities: nil) { _, planner, request, store, manager in
            do { _ = try await planner.prepareTransferExport(request, manager: manager); XCTFail("A selected value cannot replace original peer support") }
            catch { XCTAssertEqual(error as? AgentBridgeValidationError, .unsupportedCapability) }
            XCTAssertTrue(store.queriedSumIdentifiers.isEmpty)
        }
    }

    func testNativeTransferSupportRejectsInvalidOrUnnegotiatedCapabilities() throws {
        let selected = try XCTUnwrap(DirectTransferCapabilities.current.negotiated(with: .current))
        for caps in [DirectTransferCapabilities(protocolVersions: [2], binaryFrameVersions: [1], minimumPartitionBytes: 1, preferredPartitionBytes: 1, maximumPartitionBytes: Int64.max, maximumInFlightChunks: 4),
            DirectTransferCapabilities(protocolVersions: [1], binaryFrameVersions: [2], minimumPartitionBytes: 1, preferredPartitionBytes: 1, maximumPartitionBytes: Int64.max, maximumInFlightChunks: 4),
            transferPeer(preferred: 1), transferPeer(window: 0)] {
            XCTAssertThrowsError(try AgentBridgeNativeTransferCheckpoint.requireSupported(selected, peer: caps))
        }
        XCTAssertThrowsError(try AgentBridgeNativeTransferCheckpoint.requireSupported(.init(protocolVersion: 1, binaryFrameVersion: 1, partitionTargetBytes: selected.partitionTargetBytes, maximumInFlightChunks: 8), peer: transferPeer(window: 8)))
        XCTAssertNoThrow(try AgentBridgeNativeTransferCheckpoint.requireSupported(.init(protocolVersion: 1, binaryFrameVersion: 1, partitionTargetBytes: selected.partitionTargetBytes, maximumInFlightChunks: 2), peer: .current))
    }

    func testNativeTransferPlanRetainsOriginalSessionPartitionsAndBytes() async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let result = try await planner.prepareTransferExport(request, manager: manager)
            let job = try XCTUnwrap(rig.store.snapshot().acceptedJobs?.first)
            let checkpoint = try AgentBridgeNativeTransferCheckpoint.decode(result.checkpointCanonical)
            XCTAssertEqual(checkpoint.requestContract, "healthmd.agent_execute_request/1")
            XCTAssertEqual(checkpoint.requestSHA256, job.requestSHA256.rawValue)
            XCTAssertEqual(checkpoint.manifestSHA256, AgentBridgeV4Codec.sha256(result.export.manifestCanonical))
            XCTAssertEqual(checkpoint.createdAt, job.acceptedAt.rawValue); XCTAssertEqual(checkpoint.expiresAt, job.expiresAt.rawValue)
            XCTAssertEqual(result.session.jobID.uuidString.lowercased(), request.jobId.rawValue)
            XCTAssertEqual(result.session.sessionID.uuidString.lowercased(), checkpoint.sessionID)
            XCTAssertEqual(result.session.requestFingerprint.sha256, job.requestSHA256.rawValue)
            XCTAssertEqual(result.session.peerBinding.sourceInstallationID.uuidString.lowercased(), request.plan.intent.peer.sourceInstallationID.rawValue)
            XCTAssertEqual(result.session.peerBinding.destinationInstallationID.uuidString.lowercased(), request.plan.intent.peer.hostInstallationID.rawValue)
            XCTAssertEqual(result.maximumInFlightChunks, 4)
            XCTAssertEqual(result.partitions.count, result.export.baseFiles.count)
            var previous: String?
            for (index, pair) in zip(result.partitions, result.export.baseFiles).enumerated() {
                let (partition, file) = pair
                XCTAssertEqual(partition.index, index); XCTAssertEqual(partition.previousSHA256, previous)
                XCTAssertEqual(partition.sourceDates, [file.manifest.fileID.uuidString.lowercased()])
                XCTAssertEqual(partition.itemSegment?.offset, 0); XCTAssertEqual(partition.itemSegment?.isFinalSegment, true)
                XCTAssertEqual(partition.byteCount, file.manifest.byteCount); XCTAssertEqual(partition.chunkCount, 1)
                XCTAssertEqual(partition.sha256, AgentBridgeV4Codec.sha256(file.content)); previous = partition.sha256
            }
            let directory = rig.directory.appendingPathComponent("captures").appendingPathComponent(job.requestSHA256.rawValue)
            let progress = try Data(contentsOf: directory.appendingPathComponent("progress.json"))
            store.errorsForSum[HKQuantityTypeIdentifier.stepCount.rawValue] = NSError(domain: "must-not-query", code: 1)
            let restored = try await planner.prepareRetainedTransferExport(request, manager: manager, core: BridgeRenderTamperCore(mode: "forbid"))
            XCTAssertEqual(restored.session, result.session); XCTAssertEqual(restored.partitions, result.partitions)
            XCTAssertEqual(restored.checkpointCanonical, result.checkpointCanonical)
            XCTAssertEqual(restored.export.manifestCanonical, result.export.manifestCanonical)
            XCTAssertEqual(restored.export.baseFiles.map(\.content), result.export.baseFiles.map(\.content))
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("progress.json")), progress)
            XCTAssertEqual(try Data(contentsOf: directory.appendingPathComponent("transfer.json")), result.checkpointCanonical)
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }
    func testNativeTransferPlanRequiresOriginalNegotiationBeforeSDKRead() async throws {
        try await withNativeExportPreparation(transferNegotiation: nil) { _, planner, request, store, manager in
            do { _ = try await planner.prepareTransferExport(request, manager: manager); XCTFail("Missing negotiated limits cannot default") }
            catch { XCTAssertEqual(error as? AgentBridgeValidationError, .unsupportedCapability) }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 0)
        }
    }
    func testMissingNativeTransferPlanNeverRemintsOnRecovery() async throws { try await checkNativeTransferDamage(corrupt: false) }
    func testCorruptNativeTransferPlanNeverRemintsOnRecovery() async throws { try await checkNativeTransferDamage(corrupt: true) }
    private func checkNativeTransferDamage(corrupt: Bool) async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let result = try await planner.prepareTransferExport(request, manager: manager)
            let path = rig.directory.appendingPathComponent("captures").appendingPathComponent(result.export.requestSHA256).appendingPathComponent("transfer.json")
            if corrupt {
                let handle = try FileHandle(forWritingTo: path); defer { try? handle.close() }
                try handle.truncate(atOffset: 0); try handle.write(contentsOf: Data("{}".utf8)); try handle.synchronize()
            } else { try FileManager.default.removeItem(at: path) }
            do {
                _ = try await planner.prepareRetainedTransferExport(request, manager: manager, core: BridgeRenderTamperCore(mode: "forbid"))
                XCTFail("Pinned transfer metadata cannot be reminted")
            } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .spoolMissingRestartRequired) }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }
    func testInterruptedNativeTransferPlanCannotRegenerateAfterOwnerRestored() async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let fingerprint = AgentBridgeV4Codec.sha256(try AgentBridgeV4Codec.encode(request))
            let directory = rig.directory.appendingPathComponent("captures").appendingPathComponent(fingerprint)
            var interrupted = false
            rig.captureProtection.onRequire = { _ in
                guard !interrupted, let bytes = try? Data(contentsOf: directory.appendingPathComponent("progress.json")),
                      let signed = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      let record = signed["record"] as? [String: Any], let encoded = record["payload"] as? String,
                      let payload = Data(base64Encoded: encoded), let state = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                      state["version"] as? Int == 5 else { return }
                interrupted = true
                XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("transfer.json").path))
                throw AgentBridgeValidationError.bindingChanged
            }
            defer { rig.captureProtection.onRequire = nil }
            do { _ = try await planner.prepareTransferExport(request, manager: manager); XCTFail("Interrupted transfer plan cannot return success") }
            catch { XCTAssertEqual(error as? AgentBridgeValidationError, .bindingChanged) }
            XCTAssertTrue(interrupted); rig.captureProtection.onRequire = nil
            do { _ = try await planner.prepareRetainedTransferExport(request, manager: manager, core: BridgeRenderTamperCore(mode: "forbid")); XCTFail("Missing pinned plan cannot regenerate") }
            catch { XCTAssertEqual(error as? AgentBridgeValidationError, .spoolMissingRestartRequired) }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }
    func testManifestOnlyProgressV4GainsTransferWithoutChangingArtifacts() async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let original = try await planner.prepareExport(request, manager: manager)
            let directory = rig.directory.appendingPathComponent("captures").appendingPathComponent(original.requestSHA256)
            let signed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("progress.json"))) as? [String: Any])
            let record = try XCTUnwrap(signed["record"] as? [String: Any]); let payload = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(record["payload"] as? String)))
            let state = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
            XCTAssertEqual(state["version"] as? Int, 4)
            XCTAssertEqual(Set(state.keys), ["version", "captures", "artifacts", "engine", "publicArtifactIDs", "manifestSHA256", "manifestByteCount"])
            let transfer = try await planner.prepareRetainedTransferExport(request, manager: manager, core: BridgeRenderTamperCore(mode: "forbid"))
            XCTAssertEqual(transfer.export.publicArtifactIDs, original.publicArtifactIDs)
            XCTAssertEqual(transfer.export.manifestCanonical, original.manifestCanonical)
            XCTAssertEqual(transfer.export.baseFiles.map(\.manifest), original.baseFiles.map(\.manifest))
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }
    func testNativeTransferCheckpointFitsMaximumArtifactSet() throws {
        let negotiation = try XCTUnwrap(DirectTransferCapabilities.current.negotiated(with: .current))
        let checkpoint = try AgentBridgeNativeTransferCheckpoint.create(requestSHA256: String(repeating: "a", count: 64),
            manifestSHA256: String(repeating: "b", count: 64), createdAt: "2026-05-29T00:00:00Z", expiresAt: "2026-06-05T00:00:00Z", count: 4096, negotiation: negotiation)
        let bytes = try checkpoint.canonical(); XCTAssertLessThanOrEqual(bytes.count, AgentBridgeNativeTransferCheckpoint.maximumBytes)
        let ids = (0..<4096).map { _ in UUID().uuidString.lowercased() }
        XCTAssertEqual(try AgentBridgeNativeTransferCheckpoint.decode(bytes).validate(requestSHA256: checkpoint.requestSHA256,
            manifestSHA256: checkpoint.manifestSHA256, createdAt: checkpoint.createdAt, expiresAt: checkpoint.expiresAt, artifactIDs: ids).count, 4096)
    }
    func testNativeTransferPlanOwnerRevocationAfterPublicationSuppressesReturn() async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let fingerprint = AgentBridgeV4Codec.sha256(try AgentBridgeV4Codec.encode(request))
            let path = rig.directory.appendingPathComponent("captures").appendingPathComponent(fingerprint).appendingPathComponent("transfer.json")
            var revoked = false
            let session = rig.session
            session.observeChecks { _ in if FileManager.default.fileExists(atPath: path.path) { revoked = true; session.revoke() } }
            do { _ = try await planner.prepareTransferExport(request, manager: manager); XCTFail("Final native revocation cannot return transfer plan") }
            catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
            XCTAssertTrue(revoked); XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }

    func testPublicArtifactIdentityCannotBindBeforeCompleteApprovedSet() async throws {
        try await withNativeExportPreparation { _, planner, request, store, _ in
            do {
                try await planner.withCaptureContext(request) { context in
                    _ = try context.begin()
                    XCTAssertThrowsError(try context.bindPublicArtifactIDs()) {
                        XCTAssertEqual($0 as? AgentBridgeValidationError, .spoolMissingRestartRequired)
                    }
                    XCTAssertThrowsError(try context.configurationForRead())
                }
                XCTFail("A caught incomplete-set failure must invalidate the owner")
            } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 0)
        }
    }

    func testMissingPublicArtifactIdentityProgressCannotRemintOnRecovery() async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let prepared = try await planner.prepareExport(request, manager: manager)
            XCTAssertEqual(prepared.publicArtifactIDs.count, 2)
            let directory = rig.directory.appendingPathComponent("captures").appendingPathComponent(prepared.requestSHA256)
            try FileManager.default.removeItem(at: directory.appendingPathComponent("progress.json"))
            do {
                _ = try await planner.prepareRetainedExport(request, manager: manager, core: BridgeRenderTamperCore(mode: "forbid"))
                XCTFail("Missing identity progress must require a fresh approved job")
            } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .spoolMissingRestartRequired) }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }

    func testIdentityOnlyProgressV3GainsManifestWithoutLosingOriginalUUIDs() async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let ids = try await planner.withCaptureContext(request) { context in
                let resolution = try context.begin()
                for day in resolution.requestedDays {
                    _ = try await AgentBridgeNativeDayRenderer.capture(day: day, manager: manager, context: context)
                }
                return try context.bindPublicArtifactIDs() // Prior version3 producer stopped here.
            }
            let fingerprint = AgentBridgeV4Codec.sha256(try AgentBridgeV4Codec.encode(request))
            let path = rig.directory.appendingPathComponent("captures").appendingPathComponent(fingerprint).appendingPathComponent("progress.json")
            let signed = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: path)) as? [String: Any])
            let record = try XCTUnwrap(signed["record"] as? [String: Any])
            let payload = try XCTUnwrap(Data(base64Encoded: try XCTUnwrap(record["payload"] as? String)))
            let state = try XCTUnwrap(JSONSerialization.jsonObject(with: payload) as? [String: Any])
            XCTAssertEqual(state["version"] as? Int, 3)
            XCTAssertEqual(Set(state.keys), ["version", "captures", "artifacts", "engine", "publicArtifactIDs"])
            let prepared = try await planner.prepareRetainedExport(request, manager: manager, core: BridgeRenderTamperCore(mode: "forbid"))
            XCTAssertEqual(prepared.publicArtifactIDs, ids)
            let manifest = try AgentBridgeV4Codec.decode(AgentBridgeArtifactManifest.self, from: prepared.manifestCanonical)
            XCTAssertEqual(Set(manifest.artifacts.map { $0.artifactId.rawValue }), Set(ids.values))
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }

    func testNativeManifestCountsAbsentSummaryObservations() async throws {
        try await assertNativeManifestObservationCount(steps: nil, expected: 0)
    }
    func testNativeManifestCountsMeaningfulZeroSummaryObservations() async throws {
        try await assertNativeManifestObservationCount(steps: 0, expected: 2)
    }
    private func assertNativeManifestObservationCount(steps: Double?, expected: Int64) async throws {
        try await withNativeExportPreparation { _, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = steps
            let prepared = try await planner.prepareExport(request, manager: manager)
            let manifest = try AgentBridgeV4Codec.decode(AgentBridgeArtifactManifest.self, from: prepared.manifestCanonical)
            XCTAssertEqual(manifest.branchStatuses.count, 1)
            XCTAssertEqual(manifest.branchStatuses.first?.recordCount, expected)
            XCTAssertEqual(manifest.branchStatuses.first?.status, .success)
            XCTAssertEqual(manifest.captureStatus, .complete) // Both date/metadata documents still exist.
            XCTAssertEqual(manifest.artifacts.count, 2)
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }
    func testMissingNativeManifestNeverRebuildsOnRecovery() async throws {
        try await assertNativeManifestRecoveryRejects(mode: "missing")
    }
    func testCorruptNativeManifestNeverRebuildsOnRecovery() async throws {
        try await assertNativeManifestRecoveryRejects(mode: "corrupt")
    }
    private func assertNativeManifestRecoveryRejects(mode: String) async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let prepared = try await planner.prepareExport(request, manager: manager)
            let path = rig.directory.appendingPathComponent("captures").appendingPathComponent(prepared.requestSHA256).appendingPathComponent("manifest.json")
            if mode == "missing" { try FileManager.default.removeItem(at: path) }
            else {
                let file = try FileHandle(forWritingTo: path); defer { try? file.close() }
                try file.truncate(atOffset: 0); try file.write(contentsOf: Data("corrupt".utf8)); try file.synchronize()
            }
            do {
                _ = try await planner.prepareRetainedExport(request, manager: manager, core: BridgeRenderTamperCore(mode: "forbid"))
                XCTFail("A missing or corrupt original manifest cannot be rebuilt")
            } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .spoolMissingRestartRequired) }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }
    func testInterruptedNativeManifestPublicationCannotRegenerateAfterOwnerRestored() async throws {
        try await withNativeExportPreparation { rig, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let fingerprint = AgentBridgeV4Codec.sha256(try AgentBridgeV4Codec.encode(request))
            let directory = rig.directory.appendingPathComponent("captures").appendingPathComponent(fingerprint)
            var interrupted = false
            rig.captureProtection.onRequire = { _ in
                guard !interrupted,
                      let bytes = try? Data(contentsOf: directory.appendingPathComponent("progress.json")),
                      let signed = try? JSONSerialization.jsonObject(with: bytes) as? [String: Any],
                      let record = signed["record"] as? [String: Any], let encoded = record["payload"] as? String,
                      let payload = Data(base64Encoded: encoded),
                      let state = try? JSONSerialization.jsonObject(with: payload) as? [String: Any],
                      state["version"] as? Int == 4 else { return }
                interrupted = true
                XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("manifest.json").path))
                throw AgentBridgeValidationError.bindingChanged
            }
            defer { rig.captureProtection.onRequire = nil }
            do { _ = try await planner.prepareExport(request, manager: manager); XCTFail("Interrupted manifest must not return success") }
            catch { XCTAssertEqual(error as? AgentBridgeValidationError, .bindingChanged) }
            XCTAssertTrue(interrupted)
            rig.captureProtection.onRequire = nil
            do {
                _ = try await planner.prepareRetainedExport(request, manager: manager, core: BridgeRenderTamperCore(mode: "forbid"))
                XCTFail("Pinned but missing manifest cannot be regenerated")
            } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .spoolMissingRestartRequired) }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }

    func testNativeExportProducerNeverReturnsPartialSetAfterLaterSDKFailure() async throws {
        try await withNativeExportPreparation { _, planner, request, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 1
            var core = BridgeRenderTamperCore(mode: "normal")
            core.afterRender = { store.errorsForSum[HKQuantityTypeIdentifier.stepCount.rawValue] = NSError(domain: "synthetic-sdk", code: 1) }
            do { _ = try await planner.prepareExport(request, manager: manager, core: core); XCTFail("A successful partial export must never return") }
            catch { XCTAssertEqual(store.queriedSumIdentifiers.count, 2) }
            do {
                _ = try await planner.prepareRetainedExport(request, manager: manager, core: BridgeRenderTamperCore(mode: "forbid"))
                XCTFail("Ambiguous later SDK day must not be retried")
            } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .spoolMissingRestartRequired) }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }
    }

    func testNativeSpoolProtectionCallbackCannotReplaceVerifiedArtifactInode() async throws {
        try await assertNativeSpoolProtectionReplacement(replaceOnVerification: 1)
    }
    func testNativeSpoolActualReadUsesProtectedOriginalDescriptor() async throws {
        try await assertNativeSpoolProtectionReplacement(replaceOnVerification: 2)
    }
    private func assertNativeSpoolProtectionReplacement(replaceOnVerification: Int) async throws {
        try await withNativeSDKCapture(metrics: ["steps"], afterCapture: { rig, planner, request, store, manager, failure in
            XCTAssertNil(failure)
            var replaced = false
            var verifications = 0
            defer { rig.captureProtection.onRequire = nil }
            do {
                try await planner.withRetainedCaptureContext(request) { context in
                    _ = try context.begin()
                    rig.captureProtection.onRequire = { fd in
                        let path = try AgentBridgeNativeCaptureSpool.protectedPath(fd)
                        guard !replaced, URL(fileURLWithPath: path).lastPathComponent == "artifact-2026-03-08.json" else { return }
                        verifications += 1
                        guard verifications == replaceOnVerification else { return }
                        replaced = true
                        let target = URL(fileURLWithPath: path)
                        let bytes = try Data(contentsOf: target)
                        let backup = target.deletingLastPathComponent().appendingPathComponent("pending-" + UUID().uuidString.lowercased())
                        try FileManager.default.moveItem(at: target, to: backup)
                        try bytes.write(to: target, options: .withoutOverwriting)
                        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: target.path)
                        // The replacement has valid signed bytes but its new inode has no
                        // protection in the explicit synthetic OS dependency.
                    }
                    _ = try await AgentBridgeNativeDayRenderer.capture(day: AgentBridgeDate("2026-03-08"), manager: manager,
                        context: context, core: BridgeRenderTamperCore(mode: "forbid"))
                }
                XCTFail("A replacement inode must not inherit verified protection")
            } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .bindingChanged) }
            XCTAssertTrue(replaced)
            XCTAssertEqual(store.queriedSumIdentifiers.count, 1)
        }) { _, context, _, manager in
            _ = try await AgentBridgeNativeDayRenderer.capture(day: AgentBridgeDate("2026-03-08"), manager: manager, context: context)
        }
    }

    func testNativeSpoolProtectionLossRejectsBeforeAnySDKReadEvenWhenCaught() async throws {
        do { try await withNativeSDKCapture(metrics: ["steps"], afterCapture: { _, _, _, store, _, failure in
            XCTAssertEqual(failure as? AgentBridgeValidationError, .permissionRequired)
            XCTAssertEqual(store.queriedSumIdentifiers.count, 0)
        }) { rig, context, _, manager in
            rig.captureProtection.denied = true
            do {
                _ = try await AgentBridgeNativeDayRenderer.capture(day: AgentBridgeDate("2026-03-08"), manager: manager, context: context)
                XCTFail("Missing protection must deny capture")
            } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
            XCTAssertThrowsError(try context.configurationForRead())
        } } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
    }

    func testNativeSpoolProtectionLossAfterRenderCannotPublishOrRecapture() async throws {
        do { try await withNativeSDKCapture(metrics: ["steps"], afterCapture: { rig, planner, request, store, manager, failure in
            XCTAssertEqual(failure as? AgentBridgeValidationError, .permissionRequired)
            let directory = rig.directory.appendingPathComponent("captures").appendingPathComponent(AgentBridgeV4Codec.sha256(try AgentBridgeV4Codec.encode(request)))
            XCTAssertFalse(FileManager.default.fileExists(atPath: directory.appendingPathComponent("artifact-2026-03-08.json").path))
            rig.captureProtection.denied = false
            do {
                try await planner.withRetainedCaptureContext(request) { _ in XCTFail("Ambiguous artifact must reject before callback") }
                XCTFail("Missing artifact cannot be regenerated")
            } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .spoolMissingRestartRequired) }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 1)
        }) { rig, context, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 1
            var core = BridgeRenderTamperCore(mode: "normal")
            core.afterRender = { rig.captureProtection.denied = true }
            _ = try await AgentBridgeNativeDayRenderer.capture(day: AgentBridgeDate("2026-03-08"), manager: manager, context: context, core: core)
        } } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
    }

    func testBridgeCapturedDayRendersActualFrozenV8WithoutUnselectedMetrics() async throws {
        for value: Double? in [nil, 0, 123] {
            try await withNativeSDKCapture(metrics: ["steps"]) { _, context, store, manager in
                if let value { store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = value }
                let day = try AgentBridgeDate("2026-03-08")
                var captured = try await manager.captureAgentBridgeDay(day, context: context)
                captured.heart.averageHeartRate = 99 // Unselected facts cannot widen the frozen scope.
                let resolution = try context.configurationForRead()
                let result = try await AgentBridgeNativeDayRenderer.render(day: day, data: captured,
                    resolution: resolution, requestSHA256: String(repeating: "a", count: 64))
                let bytes = try result.artifact.content.materializedData()
                let json = try XCTUnwrap(JSONSerialization.jsonObject(with: bytes) as? [String: Any])
                XCTAssertEqual(json["schema_version"] as? Int, 8)
                XCTAssertEqual((json["activity"] as? [String: Any])?["steps"] as? Int, value.map(Int.init))
                XCTAssertNil(json["heart"])
                XCTAssertEqual(json["date"] as? String, day.rawValue)
                XCTAssertEqual(result.artifact.relativePath, resolution.predictedRelativePaths.last)
                XCTAssertEqual(result.artifact.sha256, NativeExportArtifact.sha256(of: bytes))
                XCTAssertEqual(store.queriedSumIdentifiers.count, 1)
            }
        }
    }

    func testBridgeFrozenV8PreservesPublicHeartFieldNames() async throws {
        try await withNativeSDKCapture(metrics: ["steps", "heart_rate_avg", "heart_rate_min", "heart_rate_max", "resting_heart_rate", "hrv"]) { _, context, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            store.statisticsAverages[HKQuantityTypeIdentifier.heartRate.rawValue] = 72
            store.statisticsMins[HKQuantityTypeIdentifier.heartRate.rawValue] = 40
            store.statisticsMaxes[HKQuantityTypeIdentifier.heartRate.rawValue] = 150
            store.statisticsMostRecent[HKQuantityTypeIdentifier.restingHeartRate.rawValue] = 55
            store.statisticsAverages[HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue] = 31
            let day = try AgentBridgeDate("2026-03-08")
            let captured = try await manager.captureAgentBridgeDay(day, context: context)
            let result = try await AgentBridgeNativeDayRenderer.render(day: day, data: captured,
                resolution: context.configurationForRead(), requestSHA256: String(repeating: "a", count: 64))
            let json = try XCTUnwrap(JSONSerialization.jsonObject(with: result.artifact.content.materializedData()) as? [String: Any])
            let heart = try XCTUnwrap(json["heart"] as? [String: Any])
            XCTAssertEqual(Set(heart.keys), ["averageHeartRate", "heartRateMin", "heartRateMax", "restingHeartRate", "hrv"])
            for (key, value) in ["averageHeartRate": 72, "heartRateMin": 40, "heartRateMax": 150, "restingHeartRate": 55, "hrv": 31] {
                XCTAssertEqual(heart[key] as? Int, value, key)
            }
        }
    }

    func testBridgeFrozenRendererRejectsWrongCoreAndCorruptArtifacts() async throws {
        try await withNativeSDKCapture(metrics: ["steps"]) { _, context, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 1
            let day = try AgentBridgeDate("2026-03-08")
            let captured = try await manager.captureAgentBridgeDay(day, context: context)
            let resolution = try context.configurationForRead()
            for mode in ["profile", "path", "digest", "body", "ids", "extra", "registry"] {
                do {
                    _ = try await AgentBridgeNativeDayRenderer.render(day: day, data: captured, resolution: resolution,
                        requestSHA256: String(repeating: "a", count: 64), core: BridgeRenderTamperCore(mode: mode))
                    XCTFail("Invalid core artifact returned: \(mode)")
                } catch let failure as AgentBridgeNativeRenderFailure {
                    XCTAssertEqual(failure, mode == "registry" ? .incompatibleCore : .invalidArtifact)
                }
            }
        }
    }

    func testBridgeFrozenRendererChecksCancellationAfterCoreReturn() async throws {
        try await withNativeSDKCapture(metrics: ["steps"]) { _, context, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 1
            let day = try AgentBridgeDate("2026-03-08")
            let captured = try await manager.captureAgentBridgeDay(day, context: context)
            let resolution = try context.configurationForRead()
            let child = Task {
                try await AgentBridgeNativeDayRenderer.render(day: day, data: captured, resolution: resolution,
                    requestSHA256: String(repeating: "a", count: 64), core: BridgeRenderTamperCore(mode: "cancel"))
            }
            do { _ = try await child.value; XCTFail("Cancelled rendering cannot return an artifact") }
            catch is CancellationError { }
        }
    }

    func testNativeArtifactProducerUsesAcceptedFingerprintAndOriginalOwner() async throws {
        try await withNativeSDKCapture(metrics: ["steps"]) { rig, context, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
            let day = try AgentBridgeDate("2026-03-08")
            let fingerprint = try XCTUnwrap(rig.store.snapshot().acceptedJobs?.first?.requestSHA256.rawValue)
            let result = try await AgentBridgeNativeDayRenderer.capture(day: day, manager: manager, context: context)
            let resolution = try context.configurationForRead()
            let index = try XCTUnwrap(resolution.requestedDays.firstIndex(of: day))
            let path = resolution.predictedRelativePaths[index]
            XCTAssertEqual(result.artifact.id, NativeExportArtifactPlan.artifactID(requestID: fingerprint,
                sessionID: fingerprint + "-" + day.rawValue, profile: .appleHealthDataV8,
                relativePath: path, mediaType: "application/json", writeMode: .overwrite,
                contentSHA256: result.artifact.sha256))
            XCTAssertEqual(store.queriedSumIdentifiers.count, 1)
        }
    }

    func testNativeArtifactProducerFailureOrOwnerLossClosesOperation() async throws {
        for mode in ["profile", "owner"] {
            do { try await withNativeSDKCapture(metrics: ["steps"], afterCapture: { _, _, _, _, _, failure in
                XCTAssertNotNil(failure)
            }) { rig, context, store, manager in
                store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 1
                var core = BridgeRenderTamperCore(mode: mode)
                if mode == "owner" { core.afterRender = { rig.session.revoke() } }
                do {
                    _ = try await AgentBridgeNativeDayRenderer.capture(day: AgentBridgeDate("2026-03-08"),
                        manager: manager, context: context, core: core)
                    XCTFail("Invalid or ownerless artifact returned")
                } catch {
                    XCTAssertThrowsError(try context.configurationForRead())
                    XCTAssertEqual(store.queriedSumIdentifiers.count, 1)
                    if mode == "profile" { XCTAssertEqual(error as? AgentBridgeNativeRenderFailure, .invalidArtifact) }
                    // Swallowing the failure must still make the original operation fail.
                }
            } } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
        }
    }

    func testRetainedArtifactReusesExactBytesWithoutSDKOrCurrentCoreEmpty() async throws { try await assertRetainedArtifactReusesExactBytes(value: nil) }
    func testRetainedArtifactReusesExactBytesWithoutSDKOrCurrentCoreZero() async throws { try await assertRetainedArtifactReusesExactBytes(value: 0) }
    func testRetainedArtifactReusesExactBytesWithoutSDKOrCurrentCorePopulated() async throws { try await assertRetainedArtifactReusesExactBytes(value: 123) }

    private func assertRetainedArtifactReusesExactBytes(value: Double?) async throws {
        var original: AgentBridgeNativeRenderedDay?
        try await withNativeSDKCapture(metrics: ["steps"], afterCapture: { rig, planner, request, store, manager, failure in
            XCTAssertNil(failure)
            let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
            store.errorsForSum[HKQuantityTypeIdentifier.stepCount.rawValue] = NSError(domain: "must-not-query", code: 1)
            try await planner.withRetainedCaptureContext(request) { context in
                _ = try context.begin()
                let result = try await AgentBridgeNativeDayRenderer.capture(day: AgentBridgeDate("2026-03-08"),
                    manager: manager, context: context, core: BridgeRenderTamperCore(mode: "forbid"))
                let expected = try XCTUnwrap(original)
                XCTAssertEqual(result.artifact.id, expected.artifact.id)
                let bytes = try result.artifact.content.materializedData()
                let expectedBytes = try expected.artifact.content.materializedData()
                XCTAssertEqual(bytes, expectedBytes)
                XCTAssertEqual(result.buildInfo, expected.buildInfo)
            }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 1)
            XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        }) { _, context, store, manager in
            if let value { store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = value }
            original = try await AgentBridgeNativeDayRenderer.capture(day: AgentBridgeDate("2026-03-08"), manager: manager, context: context)
        }
    }

    func testRetainedArtifactMissingCorruptOrAmbiguousFilesNeverRegenerateMissing() async throws { try await assertRetainedArtifactNeverRegenerates(mode: "missing") }
    func testRetainedArtifactMissingCorruptOrAmbiguousFilesNeverRegenerateBoth() async throws { try await assertRetainedArtifactNeverRegenerates(mode: "both") }
    func testRetainedArtifactMissingCorruptOrAmbiguousFilesNeverRegenerateCorrupt() async throws { try await assertRetainedArtifactNeverRegenerates(mode: "corrupt") }
    func testRetainedArtifactMissingCorruptOrAmbiguousFilesNeverRegenerateEngine() async throws { try await assertRetainedArtifactNeverRegenerates(mode: "engine") }
    func testRetainedArtifactMissingCorruptOrAmbiguousFilesNeverRegenerateInterrupted() async throws { try await assertRetainedArtifactNeverRegenerates(mode: "interrupted") }

    private func assertRetainedArtifactNeverRegenerates(mode: String) async throws {
        do { try await withNativeSDKCapture(metrics: ["steps"], afterCapture: { rig, planner, request, store, manager, failure in
            XCTAssertEqual(failure != nil, mode == "interrupted")
            let captures = rig.directory.appendingPathComponent("captures")
            let directory = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: captures, includingPropertiesForKeys: nil).first)
            let artifact = directory.appendingPathComponent("artifact-2026-03-08.json")
            switch mode {
            case "missing", "both":
                try FileManager.default.removeItem(at: artifact)
                if mode == "both" { try FileManager.default.removeItem(at: directory.appendingPathComponent("artifact-started-2026-03-08.json")) }
            case "corrupt": try Data("corrupt".utf8).write(to: artifact)
            case "engine": try Data("corrupt".utf8).write(to: directory.appendingPathComponent("progress.json"))
            default: break
            }
            do {
                try await planner.withRetainedCaptureContext(request) { context in
                    _ = try context.begin()
                    _ = try await AgentBridgeNativeDayRenderer.capture(day: AgentBridgeDate("2026-03-08"), manager: manager,
                        context: context, core: BridgeRenderTamperCore(mode: "forbid"))
                }
                XCTFail("Missing or ambiguous artifacts must not regenerate")
            } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .spoolMissingRestartRequired) }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 1)
        }) { _, context, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 1
            _ = try await AgentBridgeNativeDayRenderer.capture(day: AgentBridgeDate("2026-03-08"), manager: manager, context: context,
                core: BridgeRenderTamperCore(mode: mode == "interrupted" ? "profile" : "normal"))
        } } catch { XCTAssertEqual(mode, "interrupted"); XCTAssertEqual(error as? AgentBridgeNativeRenderFailure, .invalidArtifact) }
    }

    func testArtifactRecoveryCompletesOnlyUnstartedDayAndPreservesBothArtifacts() async throws {
        try await withNativeSDKCapture(metrics: ["steps"], afterCapture: { _, planner, request, store, manager, failure in
            XCTAssertNil(failure)
            var artifacts: [String: String] = [:]
            try await planner.withRetainedCaptureContext(request) { context in
                _ = try context.begin()
                let first = try await AgentBridgeNativeDayRenderer.capture(day: AgentBridgeDate("2026-03-08"), manager: manager,
                    context: context, core: BridgeRenderTamperCore(mode: "forbid"))
                let second = try await AgentBridgeNativeDayRenderer.capture(day: AgentBridgeDate("2026-03-07"), manager: manager, context: context)
                artifacts[first.day.rawValue] = first.artifact.sha256; artifacts[second.day.rawValue] = second.artifact.sha256
                XCTAssertNotEqual(first.artifact.id, second.artifact.id)
            }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
            try await planner.withRetainedCaptureContext(request) { context in
                _ = try context.begin()
                for day in ["2026-03-07", "2026-03-08"] {
                    let result = try await AgentBridgeNativeDayRenderer.capture(day: AgentBridgeDate(day), manager: manager,
                        context: context, core: BridgeRenderTamperCore(mode: "forbid"))
                    XCTAssertEqual(result.artifact.sha256, artifacts[day])
                }
            }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }) { _, context, _, manager in
            _ = try await AgentBridgeNativeDayRenderer.capture(day: AgentBridgeDate("2026-03-08"), manager: manager, context: context)
        }
    }

    func testArtifactEngineMismatchRejectsUnstartedDayBeforeSDK() async throws {
        do { try await withNativeSDKCapture(metrics: ["steps"], afterCapture: { _, _, _, store, _, failure in
            XCTAssertEqual(failure as? AgentBridgeValidationError, .bindingChanged)
            XCTAssertEqual(store.queriedSumIdentifiers.count, 1)
        }) { _, context, _, manager in
            _ = try await AgentBridgeNativeDayRenderer.capture(day: AgentBridgeDate("2026-03-08"), manager: manager, context: context)
            _ = try await AgentBridgeNativeDayRenderer.capture(day: AgentBridgeDate("2026-03-07"), manager: manager, context: context,
                core: BridgeRenderTamperCore(mode: "engine-changed"))
        } } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .bindingChanged) }
    }

    func testNativeSpoolDescriptorPathMatchesOpenedSyntheticFile() throws {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-descriptor-" + UUID().uuidString).resolvingSymlinksInPath()
        let fd = open(url.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        XCTAssertGreaterThanOrEqual(fd, 0)
        guard fd >= 0 else { return }
        defer { Darwin.close(fd); try? FileManager.default.removeItem(at: url) }
        let path = try AgentBridgeNativeCaptureSpool.protectedPath(fd)
        // Foundation and F_GETPATH can use different aliases for the app container.
        // The descriptor must still identify the exact synthetic fixture we opened.
        var fixture = stat(), returned = stat()
        XCTAssertEqual(lstat(url.path, &fixture), 0)
        XCTAssertEqual(lstat(path, &returned), 0)
        XCTAssertEqual(fixture.st_dev, returned.st_dev)
        XCTAssertEqual(fixture.st_ino, returned.st_ino)
    }

    #if os(iOS)
    func testNativeSpoolSystemProtectionOnSyntheticDirectory() throws { try assertNativeSpoolCompleteProtection(directory: true) }
    func testNativeSpoolSystemProtectionOnSyntheticFile() throws { try assertNativeSpoolCompleteProtection(directory: false) }
    private func assertNativeSpoolCompleteProtection(directory: Bool) throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("bridge-protection-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: base, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        defer { try? FileManager.default.removeItem(at: base) }
        let target = directory ? base : base.appendingPathComponent("synthetic")
        let fd = directory ? open(target.path, O_RDONLY | O_DIRECTORY | O_NOFOLLOW | O_CLOEXEC) :
            open(target.path, O_RDWR | O_CREAT | O_EXCL | O_NOFOLLOW | O_CLOEXEC, 0o600)
        XCTAssertGreaterThanOrEqual(fd, 0)
        guard fd >= 0 else { return }
        defer { Darwin.close(fd) }
        #if targetEnvironment(simulator)
        // Foundation intentionally omits FileManager data-protection attributes in Simulator.
        // The production provider must deny rather than assert that these files are protected.
        XCTAssertThrowsError(try AgentBridgeNativeCaptureSpool.protect(fd)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
        XCTAssertThrowsError(try AgentBridgeNativeCaptureSpool.verifyProtection(fd)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
        #else
        do {
            try AgentBridgeNativeCaptureSpool.protect(fd)
            try AgentBridgeNativeCaptureSpool.verifyProtection(fd)
        } catch {
            let attributes = try? FileManager.default.attributesOfItem(atPath: target.path)
            let raw = attributes?[.protectionKey]
            let value = (raw as? FileProtectionType)?.rawValue ?? (raw as? String)
            let classification: String
            switch value {
            case FileProtectionType.complete.rawValue: classification = "complete"
            case FileProtectionType.completeUnlessOpen.rawValue: classification = "unless_open"
            case FileProtectionType.completeUntilFirstUserAuthentication.rawValue: classification = "until_first_unlock"
            case FileProtectionType.none.rawValue: classification = "none"
            case nil: classification = "missing_or_unrecognized_type"
            default: classification = "other"
            }
            let pathAvailable = (try? AgentBridgeNativeCaptureSpool.protectedPath(fd)) != nil
            XCTFail("Complete protection unavailable: directory=\(directory), class=\(classification), path=\(pathAvailable), unlocked=\(UIApplication.shared.isProtectedDataAvailable)")
            throw AgentBridgeValidationError.permissionRequired
        }
        #endif
    }
    #endif

    func testFrozenAppleSemanticProfileRequiresExplicitSelection() throws {
        let v8 = try HealthMdCoreService().metricRegistry(profile: .appleHealthDataV8)
        XCTAssertThrowsError(try HealthMdSemanticInputAdapter.sessionConfiguration(sessionID: "ordinary-default",
            selection: MetricSelectionState(), registry: v8, customization: FormatCustomization(),
            calendarTimeZoneIdentifier: "UTC", retainPlatformExtensions: false, rollupPeriods: []))
        _ = try HealthMdSemanticInputAdapter.sessionConfiguration(sessionID: "explicit-historical",
            selection: MetricSelectionState(), registry: v8, profile: .frozenV8, customization: FormatCustomization(),
            calendarTimeZoneIdentifier: "UTC", retainPlatformExtensions: false, rollupPeriods: [])
        let v10 = try HealthMdCoreService().metricRegistry(profile: .appleHealthDataV10)
        XCTAssertThrowsError(try HealthMdSemanticInputAdapter.sessionConfiguration(sessionID: "wrong-historical",
            selection: MetricSelectionState(), registry: v10, profile: .frozenV8, customization: FormatCustomization(),
            calendarTimeZoneIdentifier: "UTC", retainPlatformExtensions: false, rollupPeriods: []))
    }

    func testNativeSDKRetainedCaptureReopensSignedBytesWithoutSDKReadsEmpty() async throws { try await assertNativeSDKRetainedCaptureReopens(value: nil) }
    func testNativeSDKRetainedCaptureReopensSignedBytesWithoutSDKReadsZero() async throws { try await assertNativeSDKRetainedCaptureReopens(value: 0) }
    func testNativeSDKRetainedCaptureReopensSignedBytesWithoutSDKReadsPopulated() async throws { try await assertNativeSDKRetainedCaptureReopens(value: 123) }

    private func assertNativeSDKRetainedCaptureReopens(value: Double?) async throws {
        try await withNativeSDKCapture(metrics: ["steps"], afterCapture: { rig, planner, request, store, manager, failure in
            XCTAssertNil(failure)
            let issuerBytes = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
            store.errorsForSum[HKQuantityTypeIdentifier.stepCount.rawValue] = NSError(domain: "must-not-query", code: 1)
            for _ in 0..<3 { // Exercises independent directory inventories and lock release/reopen.
                try await planner.withRetainedCaptureContext(request) { context in
                    _ = try context.begin()
                    let result = try await manager.captureAgentBridgeDay(AgentBridgeDate("2026-03-08"), context: context)
                    XCTAssertEqual(result.activity.steps, value.map(Int.init))
                }
            }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 1)
            XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), issuerBytes)
        }) { _, context, store, manager in
            if let value { store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = value }
            _ = try await manager.captureAgentBridgeDay(AgentBridgeDate("2026-03-08"), context: context)
        }
    }

    func testNativeSDKRetainedCaptureQueriesOnlyUnstartedDay() async throws {
        try await withNativeSDKCapture(metrics: ["steps"], afterCapture: { _, planner, request, store, manager, _ in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 20
            try await planner.withRetainedCaptureContext(request) { context in
                _ = try context.begin()
                let retained = try await manager.captureAgentBridgeDay(AgentBridgeDate("2026-03-08"), context: context)
                let fresh = try await manager.captureAgentBridgeDay(AgentBridgeDate("2026-03-07"), context: context)
                XCTAssertEqual(retained.activity.steps, 10); XCTAssertEqual(fresh.activity.steps, 20)
            }
            XCTAssertEqual(store.queriedSumIdentifiers.count, 2)
        }) { _, context, store, manager in
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 10
            _ = try await manager.captureAgentBridgeDay(AgentBridgeDate("2026-03-08"), context: context)
        }
    }

    func testNativeSDKCaptureRetainsExclusiveOriginalJobLock() async throws {
        try await withNativeSDKCapture(metrics: ["steps"]) { rig, context, store, manager in
            let snapshot = try rig.store.snapshot()
            let reservation = AgentBridgeExportCaptureReservation(job: try XCTUnwrap(snapshot.acceptedJobs?.first), claim: try XCTUnwrap(snapshot.captureClaims?.first))
            XCTAssertThrowsError(try rig.store.openCaptureSpool(reservation, create: false, fileProtection: rig.captureProtection) {}) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .busy)
            }
            store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 12
            let result = try await manager.captureAgentBridgeDay(AgentBridgeDate("2026-03-08"), context: context)
            XCTAssertEqual(result.activity.steps, 12)
        }
    }

    func testNativeSDKRetainedCaptureRejectsMissingCorruptAndAmbiguousFilesBeforeSDKHeader() async throws { try await assertNativeSDKRetainedCaptureRejects(mode: "header") }
    func testNativeSDKRetainedCaptureRejectsMissingCorruptAndAmbiguousFilesBeforeSDKProgress() async throws { try await assertNativeSDKRetainedCaptureRejects(mode: "progress") }
    func testNativeSDKRetainedCaptureRejectsMissingCorruptAndAmbiguousFilesBeforeSDKPayload() async throws { try await assertNativeSDKRetainedCaptureRejects(mode: "payload") }
    func testNativeSDKRetainedCaptureRejectsMissingCorruptAndAmbiguousFilesBeforeSDKBoth() async throws { try await assertNativeSDKRetainedCaptureRejects(mode: "both") }
    func testNativeSDKRetainedCaptureRejectsMissingCorruptAndAmbiguousFilesBeforeSDKCorrupt() async throws { try await assertNativeSDKRetainedCaptureRejects(mode: "corrupt") }
    func testNativeSDKRetainedCaptureRejectsMissingCorruptAndAmbiguousFilesBeforeSDKExtra() async throws { try await assertNativeSDKRetainedCaptureRejects(mode: "extra") }
    func testNativeSDKRetainedCaptureRejectsMissingCorruptAndAmbiguousFilesBeforeSDKPermissions() async throws { try await assertNativeSDKRetainedCaptureRejects(mode: "permissions") }
    func testNativeSDKRetainedCaptureRejectsMissingCorruptAndAmbiguousFilesBeforeSDKSymlink() async throws { try await assertNativeSDKRetainedCaptureRejects(mode: "symlink") }
    func testNativeSDKRetainedCaptureRejectsMissingCorruptAndAmbiguousFilesBeforeSDKHardlink() async throws { try await assertNativeSDKRetainedCaptureRejects(mode: "hardlink") }
    func testNativeSDKRetainedCaptureRejectsMissingCorruptAndAmbiguousFilesBeforeSDKStarted() async throws { try await assertNativeSDKRetainedCaptureRejects(mode: "started") }

    private func assertNativeSDKRetainedCaptureRejects(mode: String) async throws {
        try await withNativeSDKCapture(metrics: ["steps"], afterCapture: { rig, planner, request, store, manager, failure in
            XCTAssertNil(failure)
            let captures = rig.directory.appendingPathComponent("captures")
            let directory = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: captures, includingPropertiesForKeys: nil).first)
            let payload = directory.appendingPathComponent("day-2026-03-08.json")
            switch mode {
            case "header": try FileManager.default.removeItem(at: directory.appendingPathComponent("header.json"))
            case "progress": try FileManager.default.removeItem(at: directory.appendingPathComponent("progress.json"))
            case "payload", "both":
                try FileManager.default.removeItem(at: payload)
                if mode == "both" { try FileManager.default.removeItem(at: directory.appendingPathComponent("started-2026-03-08.json")) }
            case "corrupt": try Data("corrupt".utf8).write(to: payload)
            case "extra": try Data().write(to: directory.appendingPathComponent("unknown"))
            case "permissions": try FileManager.default.setAttributes([.posixPermissions: 0o644], ofItemAtPath: payload.path)
            case "symlink":
                let moved = rig.parent.appendingPathComponent("saved-payload")
                try FileManager.default.moveItem(at: payload, to: moved)
                try FileManager.default.createSymbolicLink(at: payload, withDestinationURL: moved)
            case "hardlink": try FileManager.default.linkItem(at: payload, to: rig.parent.appendingPathComponent("saved-payload"))
            default: break // claimDay persisted progress and started marker without a result.
            }
            do {
                try await planner.withRetainedCaptureContext(request) { context in
                    _ = try context.begin()
                    _ = try await manager.captureAgentBridgeDay(AgentBridgeDate("2026-03-08"), context: context)
                    XCTFail("Invalid retained capture must not return")
                }
                XCTFail("Invalid retained capture must fail: \(mode)")
            } catch {
                XCTAssertNotNil(error as? AgentBridgeValidationError)
                if mode == "corrupt" { XCTAssertEqual(error as? AgentBridgeValidationError, .spoolMissingRestartRequired) }
            }
            XCTAssertEqual(store.queriedSumIdentifiers.count, mode == "started" ? 0 : 1)
        }) { _, context, _, manager in
            if mode == "started" { _ = try context.claimDay(AgentBridgeDate("2026-03-08")) }
            else { _ = try await manager.captureAgentBridgeDay(AgentBridgeDate("2026-03-08"), context: context) }
        }
    }

    func testNativeSDKCaptureReadsOnlyApprovedMetricsAndPinnedDSTDay() async throws {
        try await withNativeSDKCapture(metrics: ["steps", "heart_rate_avg"]) { _, context, store, manager in
            let start = ISO8601DateFormatter().date(from: "2026-03-08T08:00:00Z")!
            let end = ISO8601DateFormatter().date(from: "2026-03-09T07:00:00Z")!
            var checkedPredicate = false
            store.querySumResult = { identifier, predicate in
                XCTAssertEqual(identifier, .stepCount)
                XCTAssertEqual(predicate, HKQuery.predicateForSamples(withStart: start, end: end))
                checkedPredicate = true
                return 0
            }
            store.statisticsAverages[HKQuantityTypeIdentifier.heartRate.rawValue] = 72
            store.statisticsMins[HKQuantityTypeIdentifier.heartRate.rawValue] = 40
            store.statisticsMaxes[HKQuantityTypeIdentifier.heartRate.rawValue] = 150
            let result = try await manager.captureAgentBridgeDay(AgentBridgeDate("2026-03-08"), context: context)
            XCTAssertTrue(checkedPredicate)
            XCTAssertEqual(result.date, start)
            XCTAssertEqual(result.timeContext.calendarTimeZoneIdentifier, "America/Los_Angeles")
            XCTAssertEqual(result.activity.steps, 0)
            XCTAssertEqual(result.heart.averageHeartRate, 72)
            XCTAssertNil(result.heart.heartRateMin); XCTAssertNil(result.heart.heartRateMax)
            XCTAssertNil(result.heart.hrv); XCTAssertNil(result.heart.restingHeartRate)
            XCTAssertEqual(store.queriedSumIdentifiers, [HKQuantityTypeIdentifier.stepCount.rawValue])
            XCTAssertEqual(store.queriedDiscreteStatisticsOptions, [.average])
            XCTAssertTrue(store.quantitySampleQueries.isEmpty)
            XCTAssertTrue(store.queriedQuantityRecordIdentifiers.isEmpty)
            XCTAssertTrue(store.queriedCategoryIdentifiers.isEmpty)
        }
    }

    func testNativeSDKCaptureUsesReviewedReducersAndPreservesEmptyValues() async throws {
        for populated in [false, true] {
            try await withNativeSDKCapture(metrics: ["steps", "heart_rate_avg", "heart_rate_min", "heart_rate_max", "resting_heart_rate", "hrv"]) { _, context, store, manager in
                if populated {
                    store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = 123
                    store.statisticsAverages[HKQuantityTypeIdentifier.heartRate.rawValue] = 72
                    store.statisticsMins[HKQuantityTypeIdentifier.heartRate.rawValue] = 40
                    store.statisticsMaxes[HKQuantityTypeIdentifier.heartRate.rawValue] = 150
                    store.statisticsMostRecent[HKQuantityTypeIdentifier.restingHeartRate.rawValue] = 55
                    store.statisticsAverages[HKQuantityTypeIdentifier.heartRateVariabilitySDNN.rawValue] = 31
                }
                let result = try await manager.captureAgentBridgeDay(AgentBridgeDate("2026-03-08"), context: context)
                XCTAssertEqual(result.activity.steps, populated ? 123 : nil)
                XCTAssertEqual(result.heart.averageHeartRate, populated ? 72 : nil)
                XCTAssertEqual(result.heart.heartRateMin, populated ? 40 : nil)
                XCTAssertEqual(result.heart.heartRateMax, populated ? 150 : nil)
                XCTAssertEqual(result.heart.restingHeartRate, populated ? 55 : nil)
                XCTAssertEqual(result.heart.hrv, populated ? 31 : nil)
                XCTAssertEqual(store.queriedDiscreteStatisticsOptions, [[.average, .minimum, .maximum]])
            }
        }
    }

    func testNativeSDKCaptureRejectsOutOfScopeAndSDKFailureWithoutFallback() async throws {
        for mode in ["day", "sdk", "invalid"] {
            do {
                try await withNativeSDKCapture(metrics: ["steps"]) { _, context, store, manager in
                    defer { XCTAssertEqual(store.queriedSumIdentifiers.count, mode == "day" ? 0 : 1); XCTAssertTrue(store.quantitySampleQueries.isEmpty) }
                    if mode == "sdk" { store.errorsForSum[HKQuantityTypeIdentifier.stepCount.rawValue] = NSError(domain: "synthetic", code: 1) }
                    if mode == "invalid" { store.statisticsSums[HKQuantityTypeIdentifier.stepCount.rawValue] = .infinity }
                    _ = try await manager.captureAgentBridgeDay(AgentBridgeDate(mode == "day" ? "2026-03-06" : "2026-03-08"), context: context)
                }
                XCTFail("Must reject")
            } catch {
                if mode == "day" { XCTAssertEqual(error as? AgentBridgeValidationError, .invalidRequest) }
                else { XCTAssertNotNil(error as? AgentBridgeNativeCaptureFailure) }
            }
        }
    }

    func testNativeSDKCaptureFailureCannotBeCaughtToRetryOrReturnSuccess() async throws {
        do {
            try await withNativeSDKCapture(metrics: ["steps"]) { _, context, store, manager in
                defer { XCTAssertEqual(store.queriedSumIdentifiers.count, 1) }
                store.errorsForSum[HKQuantityTypeIdentifier.stepCount.rawValue] = NSError(domain: "synthetic", code: 1)
                do { _ = try await manager.captureAgentBridgeDay(AgentBridgeDate("2026-03-08"), context: context); XCTFail("Expected SDK failure") }
                catch { XCTAssertNotNil(error as? AgentBridgeNativeCaptureFailure) }
                store.errorsForSum = [:]
                do { _ = try await manager.captureAgentBridgeDay(AgentBridgeDate("2026-03-08"), context: context); XCTFail("Cannot retry failed capture") }
                catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
                // Deliberately ignore the SDK error and return normally; outer operation must reject.
            }
            XCTFail("Cannot return success after SDK failure")
        } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
    }

    func testNativeSDKCaptureCannotCaptureSuccessfulDayTwiceEvenWhenDuplicateCaught() async throws {
        do {
            try await withNativeSDKCapture(metrics: ["steps"]) { _, context, store, manager in
                defer { XCTAssertEqual(store.queriedSumIdentifiers.count, 2) }
                _ = try await manager.captureAgentBridgeDay(AgentBridgeDate("2026-03-08"), context: context)
                _ = try await manager.captureAgentBridgeDay(AgentBridgeDate("2026-03-07"), context: context)
                do { _ = try await manager.captureAgentBridgeDay(AgentBridgeDate("2026-03-08"), context: context); XCTFail("Cannot recapture successful day") }
                catch { XCTAssertEqual(error as? AgentBridgeValidationError, .busy) }
            }
            XCTFail("Duplicate attempt permanently invalidates operation")
        } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
    }

    func testNativeSDKCaptureRechecksAuthorityAfterActualSDKCallback() async throws {
        do {
            try await withNativeSDKCapture(metrics: ["steps", "heart_rate_avg"]) { rig, context, store, manager in
                store.querySumResult = { _, _ in rig.session.revoke(); return 123 }
                defer { XCTAssertEqual(store.queriedSumIdentifiers.count, 1); XCTAssertTrue(store.queriedDiscreteStatisticsIdentifiers.isEmpty) }
                _ = try await manager.captureAgentBridgeDay(AgentBridgeDate("2026-03-08"), context: context)
            }
            XCTFail("Cannot return SDK value after authority loss")
        } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
    }
    #endif

    func testNativeAcceptedReceiptPrecedesCaptureAndReplaysOriginalBytes() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let wire = NativePlanningResponsePackets(), key = SymmetricKey(data: Data(repeating: 7, count: 32))
        let channel = DirectSecureChannel(packetConnection: wire, sessionKey: key, peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        defer { channel.cancel() }
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
        let request = try nativeCaptureRequest(rig, planner: planner)
        try await planner.withCaptureContext(request) { context in
            XCTAssertEqual(wire.packets.count, 1, "Acceptance must reach the channel before SDK admission")
            _ = try context.begin()
        }
        let job = try XCTUnwrap(rig.store.snapshot().acceptedJobs?.first)
        rig.clock.advance(seconds: 1)
        do { try await planner.withCaptureContext(request) { _ in XCTFail("Retry must not recapture") }; XCTFail("Expected existing job") }
        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .busy) }
        XCTAssertEqual(wire.packets.count, 2)
        var receipts: [Data] = []
        for packet in wire.packets {
            guard case .encrypted(let frame) = packet else { return XCTFail("Expected encrypted receipt") }
            let bytes = Data(try ManualIPSyncSecurity.open(frame, using: key).dropFirst(16))
            let envelope = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes)
            guard case .receipt(let receipt) = envelope.payload else { return XCTFail("Expected accepted receipt") }
            XCTAssertEqual(receipt, try job.acceptedReceipt())
            XCTAssertEqual(receipt.requestSha256.rawValue, AgentBridgeV4Codec.sha256(try AgentBridgeV4Codec.encode(request)))
            XCTAssertEqual(receipt.expiresAt, job.expiresAt)
            XCTAssertEqual(receipt.artifactCount, 0); XCTAssertEqual(receipt.committedPartitionCount, 0)
            XCTAssertEqual(receipt.manifestSha256.rawValue, String(repeating: "0", count: 64))
            XCTAssertEqual(receipt.frontierSha256.rawValue, String(repeating: "0", count: 64))
            XCTAssertFalse(receipt.sourceAcknowledged); XCTAssertEqual(receipt.status, .accepted)
            receipts.append(try AgentBridgeV4Codec.encode(receipt))
        }
        XCTAssertEqual(receipts[0], receipts[1])
        XCTAssertEqual(try rig.store.snapshot().captureClaims?.count, 1)
    }

    func testNativeAcceptedReceiptFailureOrRevocationPreventsCaptureClaim() async throws {
        for revoke in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
            _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let wire = NativePlanningResponsePackets(beforeWrite: {
                try await MainActor.run {
                    XCTAssertEqual(try rig.store.snapshot().acceptedJobs?.count, 1)
                    XCTAssertTrue(try rig.store.snapshot().captureClaims?.isEmpty ?? true)
                    if revoke { rig.session.revoke() }
                    else { throw DirectChannelError.connectionClosed }
                }
            })
            let channel = DirectSecureChannel(packetConnection: wire, sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
            defer { channel.cancel() }
            let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
            let request = try nativeCaptureRequest(rig, planner: planner)
            do { try await planner.withCaptureContext(request) { _ in XCTFail("No SDK callback before accepted receipt") }; XCTFail("Expected denial") }
            catch { if revoke { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) } }
            XCTAssertTrue(wire.packets.isEmpty)
            XCTAssertEqual(try rig.store.snapshot().acceptedJobs?.count, 1)
            XCTAssertTrue(try rig.store.snapshot().captureClaims?.isEmpty ?? true)
        }
    }

    func testNativeCaptureContextOwnsOneClaimAndExpiresEscapedContext() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let channel = DirectSecureChannel(packetConnection: NativePlanningResponsePackets(), sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
        let request = try nativeCaptureRequest(rig, planner: planner)
        let unsupported = try nativePlanningSession(rig, lifecycle, responseChannel: channel, responseVersions: [1, 3])
        let generation = try rig.store.snapshot().generation, checks = rig.session.checks
        do { _ = try await unsupported.withCaptureContext(request) { _ in XCTFail("Unsupported before callback"); return false }; XCTFail("Expected unsupported") }
        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .unsupportedCapability) }
        XCTAssertEqual(rig.session.checks, checks)
        XCTAssertEqual(try rig.store.snapshot().generation, generation)
        var escaped: AgentBridgeNativeCaptureContext?
        let result = try await planner.withCaptureContext(request) { context in
            escaped = context
            let resolution = try context.begin()
            XCTAssertEqual(resolution.selection.map(\.semanticID), request.plan.resolvedMetricIds.map(\.rawValue))
            _ = try context.configurationForRead()
            return "synthetic capture callback"
        }
        XCTAssertEqual(result, "synthetic capture callback")
        XCTAssertThrowsError(try XCTUnwrap(escaped).configurationForRead()) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
        do { _ = try await planner.withCaptureContext(request) { _ in XCTFail("No second callback"); return false }; XCTFail("Expected existing job") }
        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .busy) }
        XCTAssertEqual(try rig.store.snapshot().acceptedJobs?.count, 1)
        XCTAssertEqual(try rig.store.snapshot().captureClaims?.count, 1)
    }

    func testNativeCaptureContextCannotBeginTwiceOrReviveAfterOwnerStop() async throws {
        for stop in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
            _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let channel = DirectSecureChannel(packetConnection: NativePlanningResponsePackets(), sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
            let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
            let request = try nativeCaptureRequest(rig, planner: planner)
            do {
                _ = try await planner.withCaptureContext(request) { context in
                    _ = try context.begin()
                    if stop { lifecycle.stop() }
                    else { XCTAssertThrowsError(try context.begin()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .busy) } }
                    XCTAssertThrowsError(try context.configurationForRead())
                    return false
                }
                XCTFail("Cannot return from closed context")
            } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
            XCTAssertEqual(try rig.store.snapshot().captureClaims?.count, 1)
        }
    }

    func testNativeCaptureContextRejectsConfigurationWhenReadReentrantlyClosesContext() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let channel = DirectSecureChannel(packetConnection: NativePlanningResponsePackets(), sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
        let request = try nativeCaptureRequest(rig, planner: planner)
        var attempted = false, rejectedDuplicate = false
        do {
            _ = try await planner.withCaptureContext(request) { context in
                _ = try context.begin()
                rig.session.observeChecks { _ in
                    guard !attempted else { return }
                    attempted = true
                    do { _ = try context.begin() }
                    catch { rejectedDuplicate = error as? AgentBridgeValidationError == .busy }
                }
                XCTAssertThrowsError(try context.configurationForRead()) {
                    XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
                }
                return false
            }
            XCTFail("Cannot return from reentrantly closed context")
        } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertTrue(attempted)
        XCTAssertTrue(rejectedDuplicate)
        XCTAssertEqual(try rig.store.snapshot().captureClaims?.count, 1)
    }

    func testNativeCaptureContextKeepsOriginalTaskCancellationAcrossSuspensionAndFreshCaller() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let channel = DirectSecureChannel(packetConnection: NativePlanningResponsePackets(), sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
        let request = try nativeCaptureRequest(rig, planner: planner)
        let ready = expectation(description: "capture context suspended")
        var escaped: AgentBridgeNativeCaptureContext?
        var continuation: CheckedContinuation<Void, Never>?
        let task = Task { @MainActor in
            try await planner.withCaptureContext(request) { context in
                _ = try context.begin(); escaped = context
                await withCheckedContinuation { continuation = $0; ready.fulfill() }
                return "ignored cancellation callback"
            }
        }
        defer { task.cancel(); continuation?.resume(); continuation = nil }
        // Protected fsync-backed setup can exceed five seconds on hosted coverage runners.
        await fulfillment(of: [ready], timeout: 30)
        task.cancel()
        XCTAssertThrowsError(try XCTUnwrap(escaped).configurationForRead()) { XCTAssertTrue($0 is CancellationError) }
        continuation?.resume(); continuation = nil
        do { _ = try await task.value; XCTFail("Original cancellation must win") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try rig.store.snapshot().captureClaims?.count, 1)
    }

    func testNativeReceiveCancelsRetainedJobsWithoutCatalogOrReadPermissionAndReplaysExactReceipt() async throws {
        for captured in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig), stop = try cancellationRequest(request)
            _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
            if captured {
                let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
                let spool = try rig.store.openCaptureSpool(reservation, create: true, fileProtection: rig.captureProtection) {
                    _ = try rig.service.captureReadConfiguration(reservation, authenticatedPeer: rig.peer)
                }
                spool.close()
            }
            let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
            _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let key = SymmetricKey(data: Data(repeating: 7, count: 32))
            let bytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .cancel(stop)))
            let wire = NativePlanningResponsePackets(inbound: [
                try nativeResponsePacket(bytes, sequence: 0, key: key), try nativeResponsePacket(bytes, sequence: 1, key: key),
            ])
            let channel = DirectSecureChannel(packetConnection: wire, sessionKey: key, peerInstallationID: UUID(), peerDisplayName: "Synthetic")
            defer { channel.cancel() }
            let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel,
                beforeNativeRead: { XCTFail("Stop cannot restore read configuration"); throw AgentBridgeValidationError.permissionRequired })
            try lifecycle.observeNativeChange()
            rig.reader.grants = .required; rig.reader.calls.removeAll()
            rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
            let first = try await planner.receiveAndHandleNext(on: channel); XCTAssertNil(first)
            let original = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
            let replay = try await planner.receiveAndHandleNext(on: channel); XCTAssertNil(replay)
            XCTAssertEqual(wire.packets.count, 2)
            var receipts: [AgentBridgeExecutionReceipt] = []
            for packet in wire.packets {
                guard case .encrypted(let frame) = packet else { return XCTFail("Expected original encrypted channel") }
                let plaintext = try ManualIPSyncSecurity.open(frame, using: key)
                guard case .receipt(let receipt) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: Data(plaintext.dropFirst(16))).payload else {
                    return XCTFail("Expected terminal execution receipt")
                }
                receipts.append(receipt)
            }
            XCTAssertEqual(receipts[0], receipts[1]); XCTAssertEqual(receipts[0].status, .cancelled)
            XCTAssertTrue(receipts[0].sourceAcknowledged); XCTAssertEqual(receipts[0].artifactCount, 0)
            XCTAssertEqual(receipts[0].requestSha256, stop.requestSha256)
            XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), original)
            XCTAssertTrue(rig.reader.calls.isEmpty); XCTAssertEqual(rig.reader.defaults.reads, 0); XCTAssertEqual(rig.reader.defaults.writes, 0)
            XCTAssertThrowsError(try planner.requireCurrent()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged) }
            XCTAssertFalse(channel.isLocallyTerminal)
        }
    }

    func testPrivateDirectoryMissingLeafClassificationPreservesAncestorAndUnsafeLeafFailures() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let missing = rig.directory.appendingPathComponent("absent", isDirectory: true)
        XCTAssertThrowsError(try AgentBridgeExportPrivateFiles.openDirectory(missing, privateLeaf: true)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        XCTAssertThrowsError(try AgentBridgeExportPrivateFiles.openDirectory(missing, privateLeaf: true,
            missingLeafError: .spoolMissingRestartRequired)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .spoolMissingRestartRequired)
        }
        let missingAncestor = missing.appendingPathComponent("job", isDirectory: true)
        XCTAssertThrowsError(try AgentBridgeExportPrivateFiles.openDirectory(missingAncestor, privateLeaf: true,
            missingLeafError: .spoolMissingRestartRequired)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        let unsafe = rig.directory.appendingPathComponent("unsafe", isDirectory: true)
        try FileManager.default.createDirectory(at: unsafe, withIntermediateDirectories: false,
            attributes: [.posixPermissions: 0o755])
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: unsafe.path)
        XCTAssertThrowsError(try AgentBridgeExportPrivateFiles.openDirectory(unsafe, privateLeaf: true,
            missingLeafError: .spoolMissingRestartRequired)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        let alias = rig.directory.appendingPathComponent("alias", isDirectory: true)
        try FileManager.default.createSymbolicLink(at: alias, withDestinationURL: unsafe)
        XCTAssertThrowsError(try AgentBridgeExportPrivateFiles.openDirectory(alias, privateLeaf: true,
            missingLeafError: .spoolMissingRestartRequired)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
    }

    func testNativeReceiveCannotAcknowledgeForeignExpiredStoppedBusyOrMissingRetainedCancellation() async throws {
        for mode in ["foreign", "expired", "stopped", "busy", "missing"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig), originalStop = try cancellationRequest(request)
            let stop = mode == "foreign" ? AgentBridgeCancel(approvalId: originalStop.approvalId, authorityId: originalStop.authorityId,
                jobId: try id(99), peer: originalStop.peer, requestSha256: originalStop.requestSha256) : originalStop
            _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
            var held: AgentBridgeNativeCaptureSpool?
            if ["busy", "missing"].contains(mode) {
                let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
                if mode == "busy" {
                    held = try rig.store.openCaptureSpool(reservation, create: true, fileProtection: rig.captureProtection) {
                        _ = try rig.service.captureReadConfiguration(reservation, authenticatedPeer: rig.peer)
                    }
                }
            }
            defer { held?.close() }
            let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
            _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let key = SymmetricKey(data: Data(repeating: 7, count: 32))
            let bytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .cancel(stop)))
            let wire = NativePlanningResponsePackets(inbound: [try nativeResponsePacket(bytes, sequence: 0, key: key)])
            let channel = DirectSecureChannel(packetConnection: wire, sessionKey: key, peerInstallationID: UUID(), peerDisplayName: "Synthetic")
            defer { channel.cancel() }
            let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel,
                beforeNativeRead: { XCTFail("Stop cannot read configuration"); throw AgentBridgeValidationError.permissionRequired })
            if mode == "expired" { rig.clock.advance(seconds: 604800) }
            if mode == "stopped" { lifecycle.stop() }
            let expected: AgentBridgeValidationError = mode == "foreign" ? .bindingChanged : mode == "expired" ? .planExpired :
                mode == "stopped" ? .permissionRequired : mode == "busy" ? .busy : .spoolMissingRestartRequired
            do { _ = try await planner.receiveAndHandleNext(on: channel); XCTFail("Expected retained-state rejection: \(mode)") }
            catch { XCTAssertEqual(error as? AgentBridgeValidationError, expected, mode) }
            XCTAssertTrue(wire.packets.isEmpty); XCTAssertTrue(channel.isLocallyTerminal)
            XCTAssertTrue(try rig.store.snapshot().cancellationIntents?.allSatisfy { try $0.terminalReceipt() == nil } ?? true)
        }
    }

    func testNativeCancellationReceiptRechecksTrustExpiryOwnerAndRetainedFilesAtGuardedWriteAndReturn() async throws {
        for afterWrite in [false, true] { for mode in ["trust", "expiry", "owner", "files"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try executionRequest(rig), stop = try cancellationRequest(request)
            _ = try rig.service.acceptExecution(request, authenticatedPeer: rig.peer)
            let reservation = try rig.service.claimCapture(request, authenticatedPeer: rig.peer)
            let spool = try rig.store.openCaptureSpool(reservation, create: true, fileProtection: rig.captureProtection) {
                _ = try rig.service.captureReadConfiguration(reservation, authenticatedPeer: rig.peer)
            }
            spool.close()
            let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
            _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let mutate: @MainActor @Sendable () throws -> Void = {
                switch mode {
                case "trust": rig.session.revoke()
                case "expiry": rig.clock.advance(seconds: 604800)
                case "owner": lifecycle.stop()
                default:
                    let header = rig.directory.appendingPathComponent("captures/" + stop.requestSha256.rawValue + "/header.json")
                    try Data("changed".utf8).write(to: header)
                }
            }
            let key = SymmetricKey(data: Data(repeating: 7, count: 32))
            let bytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .cancel(stop)))
            let wire = NativePlanningResponsePackets(beforeWrite: { if !afterWrite { try await mutate() } },
                afterWrite: { if afterWrite { try await mutate() } }, inbound: [try nativeResponsePacket(bytes, sequence: 0, key: key)])
            let channel = DirectSecureChannel(packetConnection: wire, sessionKey: key, peerInstallationID: UUID(), peerDisplayName: "Synthetic")
            defer { channel.cancel() }
            let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel,
                beforeNativeRead: { XCTFail("Stop cannot read configuration"); throw AgentBridgeValidationError.permissionRequired })
            let expected: AgentBridgeValidationError = mode == "expiry" ? .planExpired : mode == "files" ? .spoolMissingRestartRequired : .permissionRequired
            do { _ = try await planner.receiveAndHandleNext(on: channel); XCTFail("A stale proof must not return success") }
            catch { XCTAssertEqual(error as? AgentBridgeValidationError, expected, mode) }
            XCTAssertEqual(wire.packets.count, afterWrite ? 1 : 0) // Already emitted bytes cannot be recalled.
            XCTAssertTrue(channel.isLocallyTerminal)
        } }
    }

    func testNativeReceiveRoutesDiscoveryAndPreservesBaseAndBinaryFrames() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let key = SymmetricKey(data: Data(repeating: 7, count: 32)), binary = Data("HMDDIRCTsynthetic".utf8)
        let wire = NativePlanningResponsePackets(inbound: [
            try nativeResponsePacket(JSONEncoder().encode(DirectMessage.ping), sequence: 0, key: key),
            try nativeResponsePacket(nativeDiscoveryBytes(rig), sequence: 1, key: key),
            try nativeResponsePacket(binary, sequence: 2, key: key),
        ])
        let channel = DirectSecureChannel(packetConnection: wire, sessionKey: key, peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        defer { channel.cancel() }
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
        let before = try rig.store.snapshot().generation
        rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
        let base = try await planner.receiveAndHandleNext(on: channel)
        XCTAssertEqual(base, .base(.ping))
        let handled = try await planner.receiveAndHandleNext(on: channel)
        XCTAssertNil(handled)
        let frame = try await planner.receiveAndHandleNext(on: channel)
        XCTAssertEqual(frame, .binaryTransferFrame(binary))
        XCTAssertEqual(wire.receiveCount, 3); XCTAssertEqual(wire.packets.count, 1)
        guard case .encrypted(let response) = try XCTUnwrap(wire.packets.first) else { return XCTFail("Expected owned encrypted response") }
        let plaintext = try ManualIPSyncSecurity.open(response, using: key)
        guard case .discovery(let discovery) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: Data(plaintext.dropFirst(16))).payload else { return XCTFail("Expected discovery") }
        XCTAssertEqual(discovery.peer, rig.peer.peer)
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
        XCTAssertEqual(rig.reader.defaults.reads, 0); XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testNativeReceiveRejectsDifferentChannelBeforeReadingOrAuthorityAccess() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let wire = NativePlanningResponsePackets(), otherWire = NativePlanningResponsePackets()
        let key = SymmetricKey(data: Data(repeating: 7, count: 32)), peerID = UUID()
        let channel = DirectSecureChannel(packetConnection: wire, sessionKey: key, peerInstallationID: peerID, peerDisplayName: "Synthetic")
        let other = DirectSecureChannel(packetConnection: otherWire, sessionKey: key, peerInstallationID: peerID, peerDisplayName: "Synthetic")
        defer { channel.cancel(); other.cancel() }
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
        let before = try rig.store.snapshot().generation
        rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
        do { _ = try await planner.receiveAndHandleNext(on: other); XCTFail("A matching peer is not the original channel") }
        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .bindingChanged) }
        XCTAssertEqual(wire.receiveCount, 0); XCTAssertEqual(otherWire.receiveCount, 0)
        XCTAssertTrue(wire.packets.isEmpty); XCTAssertTrue(otherWire.packets.isEmpty)
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertEqual(rig.reader.defaults.reads, 0); XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testNativeReceiveRevokedOwnerCannotReturnBaseOrRevive() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let key = SymmetricKey(data: Data(repeating: 7, count: 32))
        let wire = NativePlanningResponsePackets(inbound: [try nativeResponsePacket(JSONEncoder().encode(DirectMessage.ping), sequence: 0, key: key)],
            beforeReceive: { await MainActor.run { lifecycle.stop() } })
        let channel = DirectSecureChannel(packetConnection: wire, sessionKey: key, peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
        for _ in 0..<2 {
            do { _ = try await planner.receiveAndHandleNext(); XCTFail("Stopped owner cannot return or revive") }
            catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
        }
        XCTAssertEqual(wire.receiveCount, 1); XCTAssertTrue(wire.packets.isEmpty)
        XCTAssertTrue(channel.isLocallyTerminal)
    }

    private func nativeResponsePacket(_ bytes: Data, sequence: UInt64, key: SymmetricKey) throws -> ManualIPSyncPacket {
        var plaintext = Data("HMDSC001".utf8), number = sequence.bigEndian
        withUnsafeBytes(of: &number) { plaintext.append(contentsOf: $0) }
        plaintext.append(bytes)
        return .encrypted(try ManualIPSyncSecurity.seal(plaintext, using: key))
    }

    func testNativeResponseUsesPinnedGuardedChannelWithoutIssuingAuthority() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let wire = NativePlanningResponsePackets(), key = SymmetricKey(data: Data(repeating: 7, count: 32))
        let channel = DirectSecureChannel(packetConnection: wire, sessionKey: key, peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        defer { channel.cancel() }
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
        let before = try rig.store.snapshot().generation
        rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
        let negotiation = try AgentBridgeNegotiation(localVersions: [1, 4], remoteVersions: [1, 4], deployedBaseVersion: 1)
        try await planner.handleAndSend(nativeDiscoveryBytes(rig))
        guard case .encrypted(let frame) = try XCTUnwrap(wire.packets.first) else { return XCTFail("Expected encrypted response") }
        let plaintext = try ManualIPSyncSecurity.open(frame, using: key)
        guard case .discovery(let response) = try negotiation.decode(Data(plaintext.dropFirst(16))).payload else { return XCTFail("Expected owned discovery") }
        XCTAssertEqual(response.peer, rig.peer.peer)
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
        XCTAssertEqual(rig.reader.defaults.reads, 0); XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testNativeResponseUnsupportedNegotiationDoesNotTouchIssuerOrChannel() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let wire = NativePlanningResponsePackets()
        let channel = DirectSecureChannel(packetConnection: wire, sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        defer { channel.cancel() }
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel, responseVersions: [1, 3])
        let checks = rig.session.checks
        do { try await planner.handleAndSend(Data("invalid".utf8)); XCTFail("Expected no extension") }
        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .unsupportedCapability) }
        do { _ = try await planner.receiveAndHandleNext(); XCTFail("Remote4 cannot override the owner's local hello") }
        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .unsupportedCapability) }
        XCTAssertEqual(wire.receiveCount, 0)
        XCTAssertEqual(rig.session.checks, checks)
        XCTAssertTrue(wire.packets.isEmpty); XCTAssertFalse(channel.isLocallyTerminal)
    }

    func testNativeResponseRejectsCompletedPublicationChangeBeforeAndAfterWrite() async throws {
        for afterWrite in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
            let original = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let change: @concurrent @Sendable () async throws -> Void = {
                try await MainActor.run {
                    try lifecycle.recordNativeEvent()
                    _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
                }
            }
            let wire = NativePlanningResponsePackets(beforeWrite: { if !afterWrite { try await change() } }, afterWrite: { if afterWrite { try await change() } })
            let channel = DirectSecureChannel(packetConnection: wire, sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
            let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
                do { try await planner.handleAndSend(nativeDiscoveryBytes(rig)); XCTFail("Expected original publication fence") }
            catch { XCTAssertEqual(error as? AgentBridgeValidationError, .bindingChanged) }
            XCTAssertEqual(try lifecycle.currentPublication().revision, original.revision + 1)
            XCTAssertEqual(wire.packets.count, afterWrite ? 1 : 0)
            XCTAssertTrue(channel.isLocallyTerminal)
            do { try await planner.handleAndSend(nativeDiscoveryBytes(rig)); XCTFail("Cannot revive abandoned response owner") }
            catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
        }
    }

    func testNativeResponseCancellationFromLastReturnPeerCallbackCannotSucceed() async throws {
        var finalCheckCount = 0
        for cancel in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
            _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let wire = NativePlanningResponsePackets()
            let channel = DirectSecureChannel(packetConnection: wire, sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
            defer { channel.cancel() }
            let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
                let before = rig.session.checks
            if cancel {
                let target = before + finalCheckCount
                rig.session.observeChecks { check in if check == target { withUnsafeCurrentTask { $0?.cancel() } } }
            }
            let task = Task { try await planner.handleAndSend(nativeDiscoveryBytes(rig)) }
            do {
                try await task.value
                if cancel { XCTFail("Cancellation during final validator cannot return success") }
            } catch {
                if !cancel { throw error }
                XCTAssertTrue(error is CancellationError)
                XCTAssertTrue(channel.isLocallyTerminal)
            }
            if !cancel { finalCheckCount = rig.session.checks - before; XCTAssertGreaterThan(finalCheckCount, 0) }
            else { XCTAssertEqual(rig.session.checks - before, finalCheckCount) }
        }
    }

    func testNativeResponseRechecksLiveIssuerExpiryAtActualWrite() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let wire = NativePlanningResponsePackets(beforeWrite: { await MainActor.run { rig.clock.advance(seconds: 600) } })
        let channel = DirectSecureChannel(packetConnection: wire, sessionKey: SymmetricKey(size: .bits256), peerInstallationID: UUID(), peerDisplayName: "Synthetic")
        let planner = try nativePlanningSession(rig, lifecycle, responseChannel: channel)
        do { try await planner.handleAndSend(nativeDiscoveryBytes(rig)); XCTFail("Expected expiry after planning") }
        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .planExpired) }
        XCTAssertTrue(wire.packets.isEmpty); XCTAssertTrue(channel.isLocallyTerminal)
    }

    func testOwnerBoundPlannerRetainsDiscoveryThroughPlanReviewAndExactDecision() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let planner = try nativePlanningSession(rig, lifecycle)
        rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
        let before = try rig.store.snapshot().generation
        guard case .discovery(let discovery) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self,
            from: planner.handle(nativeDiscoveryBytes(rig))).payload else { return XCTFail("Expected owned discovery") }
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        let bytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(rig.request(discovery: discovery, policy: .explicit(output())))))
        guard case .plan(let plan) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: planner.handle(bytes)).payload else {
            return XCTFail("Expected plan using the same session's discovery")
        }
        XCTAssertEqual(try planner.reviewNativePlan(planID: plan.planId), plan)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
        let binding = try AgentBridgeSemantics.binding(plan)
        try planner.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8),
            authorization: FakeNativeAuthorization(binding: binding))
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 1)
        XCTAssertTrue(try planner.nativePlansAwaitingReview().isEmpty)
        XCTAssertEqual(rig.reader.defaults.reads, 0); XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testNativeReviewQueueIsReadOnlyAndRemovesConfirmedAndStalePlans() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let planner = try nativePlanningSession(rig, lifecycle)
        guard case .discovery(let discovery) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self,
            from: planner.handle(nativeDiscoveryBytes(rig))).payload else { return XCTFail("Expected discovery") }
        let bytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(rig.request(discovery: discovery, policy: .explicit(output())))))
        guard case .plan(let plan) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: planner.handle(bytes)).payload else { return XCTFail("Expected plan") }
        rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
        let before = try rig.store.snapshot().generation
        XCTAssertEqual(try planner.nativePlansAwaitingReview(), [plan])
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
        try lifecycle.recordNativeEvent()
        XCTAssertThrowsError(try planner.nativePlansAwaitingReview())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertTrue(try planner.nativePlansAwaitingReview().isEmpty)
        XCTAssertEqual(rig.reader.defaults.reads, 0); XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testNativeReviewQueueRejectsStorageLossAfterItsInitialSnapshot() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let planner = try nativePlanningSession(rig, lifecycle)
        guard case .discovery(let discovery) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self,
            from: planner.handle(nativeDiscoveryBytes(rig))).payload else { return XCTFail("Expected discovery") }
        _ = try planner.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(rig.request(discovery: discovery, policy: .explicit(output()))))))
        let removeAt = rig.session.checks + 2
        var removed = false
        rig.session.observeChecks { count in
            if count == removeAt {
                try! FileManager.default.removeItem(at: rig.directory.appendingPathComponent("state.json"))
                removed = true
            }
        }
        XCTAssertThrowsError(try planner.nativePlansAwaitingReview())
        XCTAssertTrue(removed)
    }

    func testOwnerBoundPlannerRejectsPendingAndStoppedOwnerDespiteSamePeerReplacement() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let profiles = ExportProfileStore(userDefaults: rig.reader.defaults)
        let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
        XCTAssertThrowsError(try nativePlanningSession(rig, lifecycle, profiles: profiles))
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let planner = try nativePlanningSession(rig, lifecycle, profiles: profiles)
        try lifecycle.recordNativeEvent()
        rig.reader.defaults.reads = 0; rig.reader.defaults.writes = 0
        XCTAssertThrowsError(try planner.handle(Data("invalid".utf8))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged) }
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        _ = try planner.handle(nativeDiscoveryBytes(rig))
        lifecycle.stop()
        let replacement = AgentBridgeNativeCatalogLifecycle(); try replacement.observe(nativeState())
        _ = try replacement.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertThrowsError(try planner.handle(nativeDiscoveryBytes(rig))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        let fresh = try nativePlanningSession(rig, replacement, profiles: profiles)
        _ = try fresh.handle(nativeDiscoveryBytes(rig))
        XCTAssertEqual(rig.reader.defaults.reads, 0); XCTAssertEqual(rig.reader.defaults.writes, 0)
        XCTAssertEqual(try rig.store.snapshot().delegations.count, 1)
    }

    func testOwnerBoundPlannerRejectsEventDuringFinalPeerReturnCheck() throws {
        var finalCheck = 0
        for inject in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
            _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let planner = try nativePlanningSession(rig, lifecycle)
            var fired = false
            if inject {
                rig.session.observeChecks { count in
                    if count == finalCheck { fired = true; try! lifecycle.recordNativeEvent() }
                }
                XCTAssertThrowsError(try planner.handle(nativeDiscoveryBytes(rig))) {
                    XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
                }
                XCTAssertTrue(fired)
            } else {
                _ = try planner.handle(nativeDiscoveryBytes(rig))
                finalCheck = rig.session.checks
                XCTAssertGreaterThan(finalCheck, 0)
            }
            XCTAssertTrue(try rig.store.snapshot().plans.isEmpty)
        }
    }

    func testOwnerBoundPlannerRejectsSignedStorePublicationOutsideOwner() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
        try lifecycle.observe(facts)
        let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let planner = try nativePlanningSession(rig, lifecycle)
        let next = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID,
            invalidatingObservedChange: true) { facts }
        XCTAssertEqual(next.factsSHA256, first.factsSHA256)
        XCTAssertEqual(next.revision, first.revision + 1)
        guard case .error(let failure) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self,
            from: planner.handle(nativeDiscoveryBytes(rig))).payload else { return XCTFail("Expected binding_changed for mismatched signed publication") }
        XCTAssertEqual(failure.code, .bindingChanged)
    }

    func testOwnerBoundPlannerRejectsCompletedPublicationDuringFinalPeerReturnCheck() throws {
        var finalCheck = 0
        for inject in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let lifecycle = AgentBridgeNativeCatalogLifecycle(); try lifecycle.observe(nativeState())
            let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let planner = try nativePlanningSession(rig, lifecycle)
            var fired = false
            if inject {
                rig.session.observeChecks { count in
                    if count == finalCheck {
                        fired = true
                        try! lifecycle.recordNativeEvent()
                        _ = try! lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
                    }
                }
                XCTAssertThrowsError(try planner.handle(nativeDiscoveryBytes(rig))) {
                    XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
                }
                XCTAssertTrue(fired)
                XCTAssertEqual(try lifecycle.currentPublication().revision, first.revision + 1)
            } else {
                _ = try planner.handle(nativeDiscoveryBytes(rig)); finalCheck = rig.session.checks
                XCTAssertGreaterThan(finalCheck, 0)
            }
            XCTAssertTrue(try rig.store.snapshot().plans.isEmpty)
            XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
        }
    }

    func testNativeAuthorityGrantAndRevokeInvalidateSameOwnerAfterStoreUnlock() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
        try lifecycle.observe(facts)
        let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let relay = AgentBridgeNativeCatalogEventRelay(); relay.replace(with: lifecycle)
        let notifications = AgentBridgeNativeCatalogNotifications(names: [.healthMdAgentExportAuthorityDidChange], relay: relay)
        defer { withExtendedLifetime(notifications) {}; relay.replace(with: nil) }
        try rig.enroll()
        XCTAssertThrowsError(try lifecycle.currentFacts()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged) }
        let next = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertEqual(next.revision, first.revision + 1)
        try rig.store.revokeNativeDelegation(rig.grant().reference(), expectedGeneration: rig.store.snapshot().generation,
                                            authorization: FakeNativeAuthorization())
        XCTAssertTrue(try XCTUnwrap(rig.store.snapshot().delegations.first).revoked)
        XCTAssertThrowsError(try lifecycle.currentFacts()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged) }
        XCTAssertEqual(try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID).revision,
                       next.revision + 1)
    }

    func testNativeAuthoritySetupAndFailedAuthorizedWriteEmitButDeniedAttemptDoesNot() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
        try lifecycle.observe(facts)
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let relay = AgentBridgeNativeCatalogEventRelay(); relay.replace(with: lifecycle)
        let notifications = AgentBridgeNativeCatalogNotifications(names: [.healthMdAgentExportAuthorityDidChange], relay: relay)
        defer { withExtendedLifetime(notifications) {}; relay.replace(with: nil) }
        let other = rig.parent.appendingPathComponent("new-native-authority")
        XCTAssertThrowsError(try AgentBridgeExportAuthorityStore.createPrivateStore(at: other, protectedKeys: rig.keys,
            authorization: FakeNativeAuthorization(deny: true)))
        XCTAssertFalse(FileManager.default.fileExists(atPath: other.path))
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        _ = try AgentBridgeExportAuthorityStore.createPrivateStore(at: other, protectedKeys: rig.keys, authorization: FakeNativeAuthorization())
        XCTAssertThrowsError(try lifecycle.currentFacts())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let before = try rig.store.snapshot().generation
        XCTAssertThrowsError(try rig.store.storeNativeDelegation(rig.grant(), expectedGeneration: before,
            authorization: FakeNativeAuthorization(deny: true)))
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        XCTAssertThrowsError(try rig.store.storeNativeDelegation(rig.grant(), expectedGeneration: before + 1,
            authorization: FakeNativeAuthorization()))
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertThrowsError(try lifecycle.currentFacts()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged) }
    }

    func testNativeAuthorityPublicationReadAndDetachedObserverDoNotInvalidate() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
        try lifecycle.observe(facts)
        let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let relay = AgentBridgeNativeCatalogEventRelay(); relay.replace(with: lifecycle)
        var notifications: AgentBridgeNativeCatalogNotifications? = .init(names: [.healthMdAgentExportAuthorityDidChange], relay: relay)
        try withExtendedLifetime(notifications) {
            _ = try rig.store.snapshot()
        }
        XCTAssertEqual(try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID), first)
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        notifications = nil
        try rig.enroll()
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        relay.replace(with: nil)
        NotificationCenter.default.post(name: .healthMdAgentExportAuthorityDidChange, object: nil)
        XCTAssertThrowsError(try lifecycle.currentFacts()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
    }

    func testFoundationNativeNotificationsLatchBeforeReturnAndDetachWithOwnerLifetime() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let facts = try nativeState(), lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(facts)
        let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let relay = AgentBridgeNativeCatalogEventRelay(), center = NotificationCenter()
        relay.replace(with: lifecycle)
        relay.replace(with: lifecycle) // Reattaching the same owner cannot stop or renew it.
        var notifications: AgentBridgeNativeCatalogNotifications? = .init(
            center: center, names: [.NSSystemTimeZoneDidChange], relay: relay)
        center.post(name: .init("synthetic.unrelated"), object: nil)
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        withExtendedLifetime(notifications) {
            center.post(name: .NSSystemTimeZoneDidChange, object: nil)
            center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        }
        // Both actual Foundation callbacks ran synchronously, before any deferred SDK sampling.
        XCTAssertThrowsError(try lifecycle.currentFacts()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged) }
        let next = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertEqual(next.revision, first.revision + 1)
        notifications = nil
        center.post(name: .NSSystemTimeZoneDidChange, object: nil)
        XCTAssertEqual(try lifecycle.currentFacts(), facts) // Exact tokens were removed on teardown.
        relay.replace(with: nil)
        relay.observeNativeChange() // No owner means no issuer/settings/key work.
        XCTAssertThrowsError(try lifecycle.currentFacts()) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
    }

    #if canImport(HealthMd)
    func testNativeConfigurationProtectionChangesInvalidateCatalogBeforeReturning() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let center = NotificationCenter()
        let manager = ConfigurationProtectionManager(userDefaults: rig.reader.defaults, nativePlanningNotifications: center)
        Self.retainedNativeConfigurationObjects.append(manager)
        let original = manager.isEnabled
        let facts = try nativeState(), lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(facts)
        let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let relay = AgentBridgeNativeCatalogEventRelay()
        relay.replace(with: lifecycle)
        var notifications: AgentBridgeNativeCatalogNotifications? = .init(
            center: center, names: [.healthMdConfigurationProtectionDidChange], relay: relay)
        try withExtendedLifetime(notifications) {
            manager.setEnabled(original)
            XCTAssertEqual(try lifecycle.currentFacts(), facts) // Identical assignments emit no event.
            manager.setEnabled(!original)
            XCTAssertEqual(manager.isEnabled, !original)
            XCTAssertThrowsError(try lifecycle.currentFacts()) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
            manager.setEnabled(original)
            XCTAssertEqual(manager.isEnabled, original)
            XCTAssertThrowsError(try lifecycle.currentFacts()) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
        }
        let next = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertEqual(next.revision, first.revision + 1)
        XCTAssertEqual(next.factsSHA256, first.factsSHA256)
        notifications = nil
        manager.setEnabled(!original)
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        relay.replace(with: nil)
        manager.setEnabled(original)
        XCTAssertThrowsError(try lifecycle.currentFacts()) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
    }

    func testNativePurchaseQuotaTransitionsInvalidatePublishedCatalogBeforeReturning() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let center = NotificationCenter(), keychain = FakeKeychainStore()
        let manager = PurchaseManager(keychain: keychain, defaults: FakeUserDefaults(), nativePlanningNotifications: center)
        Self.retainedNativeConfigurationObjects.append(manager)
        XCTAssertTrue(manager.nativePlanningCanExport)
        let facts = try nativeState(), lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(facts)
        let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let relay = AgentBridgeNativeCatalogEventRelay()
        relay.replace(with: lifecycle)
        var notifications: AgentBridgeNativeCatalogNotifications? = .init(
            center: center, names: [.healthMdNativeExportEligibilityDidChange], relay: relay)
        try withExtendedLifetime(notifications) {
            manager.setFreeExportsUsed(PurchaseManager.freeExportLimit)
            XCTAssertFalse(manager.nativePlanningCanExport)
            XCTAssertThrowsError(try lifecycle.currentFacts()) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
            manager.resetFreeExports()
            XCTAssertTrue(manager.nativePlanningCanExport)
            // Eligibility returned to its original value before any deferred sampler ran.
            XCTAssertThrowsError(try lifecycle.currentFacts()) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
        }
        let next = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertEqual(next.revision, first.revision + 1)
        XCTAssertEqual(next.factsSHA256, first.factsSHA256)
        try withExtendedLifetime(notifications) {
            // Native refresh briefly closes eligibility even if durable facts are unchanged.
            manager.refreshNativePlanningExportEligibility()
            XCTAssertTrue(manager.nativePlanningCanExport)
            XCTAssertThrowsError(try lifecycle.currentFacts()) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
        }
        let refreshed = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertEqual(refreshed.revision, next.revision + 1)
        notifications = nil
        manager.setFreeExportsUsed(PurchaseManager.freeExportLimit)
        XCTAssertEqual(try lifecycle.currentFacts(), facts) // Observer teardown removed its exact token.
        relay.replace(with: nil)
        manager.resetFreeExports()
        XCTAssertThrowsError(try lifecycle.currentFacts()) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
    }
    #endif

    #if canImport(HealthMd)
    func testHealthKitFlowEventsInvalidateSameFactsAndTeardownExactNativeObserver() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let center = NotificationCenter(), healthStore = FakeHealthStore()
        healthStore.authRequestStatus = .unnecessary
        let manager = HealthKitManager(store: healthStore, userDefaults: rig.reader.defaults,
                                       nativePlanningNotifications: center)
        manager.isAuthorized = true
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
        let relay = AgentBridgeNativeCatalogEventRelay()
        relay.replace(with: lifecycle)
        var notifications: AgentBridgeNativeCatalogNotifications? = .init(center: center,
            names: [.healthMdNativeHealthAuthorizationDidChange], relay: relay)
        try lifecycle.observe(facts)
        let first = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        manager.isAuthorized = true // Identical cache assignment is not a completed native flow.
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        _ = try await manager.requestAuthorization()
        XCTAssertThrowsError(try lifecycle.currentPublication())
        let second = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        XCTAssertEqual(second.revision, first.revision + 1)
        _ = try await manager.requestAuthorization() // Repeated flow still invalidates equal metadata.
        XCTAssertThrowsError(try lifecycle.currentFacts())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        manager.isAuthorized = false; manager.isAuthorized = true
        XCTAssertThrowsError(try lifecycle.currentFacts())
        _ = try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        withExtendedLifetime(notifications) { }
        notifications = nil
        manager.isAuthorized = false
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        relay.replace(with: nil)
        manager.isAuthorized = true
        XCTAssertThrowsError(try lifecycle.currentFacts())
        XCTAssertFalse(healthStore.authRequested)
        XCTAssertTrue(healthStore.quantitySampleQueries.isEmpty)
        XCTAssertTrue(healthStore.completedCanonicalQueryIdentifiers.isEmpty)
        XCTAssertTrue(healthStore.workoutRecordQueries.isEmpty)
        XCTAssertTrue(healthStore.medicationRecordQueries.isEmpty)
    }

    #endif

    func testNativeAdmissionDefersSDKUntilConfiguredAndPinsInitialDependencies() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let admission = AgentBridgeNativeCatalogAdmission(), lifecycle = AgentBridgeNativeCatalogLifecycle()
        let facts = try nativeState(), store = rig.store
        let published = expectation(description: "admitted owner published")
        var calls = 0
        var controller: AgentBridgeNativeCatalogRefresh?
        admission.replace(with: lifecycle)
        admission.configure { original in
            XCTAssertTrue(original === lifecycle)
            calls += 1
            controller = try AgentBridgeNativeCatalogRefresh(lifecycle: original) {
                _ = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: original, peer: rig.peer,
                    existingDirectory: rig.directory, sample: { facts }, loadStore: { _ in store })
                published.fulfill()
            }
        }
        admission.configure { _ in XCTFail("Native dependencies were replaced") }
        XCTAssertEqual(calls, 0, "Native admission must not run on the wire handler stack")
        await fulfillment(of: [published], timeout: 3)
        admission.replace(with: lifecycle)
        XCTAssertEqual(calls, 1)
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        admission.replace(with: nil)
        controller?.stop()
        XCTAssertThrowsError(try lifecycle.currentPublication())
    }

    func testInitialReadinessWaitsForColdOwnedPublicationWithoutStartingOrCancelingIt() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), admission = AgentBridgeNativeCatalogAdmission()
        let facts = try nativeState(), store = rig.store
        let entered = expectation(description: "native sample suspended"), completed = expectation(description: "original receiver admitted")
        let gate = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        var result: Result<AgentBridgeNativeCatalogPublication, Error>?
        let receiver = Task {
            do { result = .success(try await lifecycle.awaitInitialPublication()) }
            catch { result = .failure(error) }
            completed.fulfill()
        }
        var controller: AgentBridgeNativeCatalogRefresh?
        defer { receiver.cancel(); gate.continuation.finish(); admission.replace(with: nil); controller?.stop() }
        await Task.yield()
        XCTAssertNil(result)
        let canceled = Task { try await lifecycle.awaitInitialPublication() }
        canceled.cancel()
        do { _ = try await canceled.value; XCTFail("Canceled receiver was admitted") }
        catch { XCTAssertTrue(error is CancellationError) }
        admission.configure { original in
            XCTAssertTrue(original === lifecycle)
            controller = try AgentBridgeNativeCatalogRefresh(lifecycle: original) {
                _ = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: original, peer: rig.peer,
                    existingDirectory: rig.directory, sample: {
                        entered.fulfill(); for await _ in gate.stream { break }; return facts
                    }, loadStore: { _ in store })
            }
        }
        admission.replace(with: lifecycle)
        await fulfillment(of: [entered], timeout: 3)
        XCTAssertNil(result)
        XCTAssertThrowsError(try lifecycle.currentPublication())
        gate.continuation.yield(())
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(try XCTUnwrap(result).get(), try lifecycle.currentPublication())
        admission.replace(with: nil)
        do { _ = try await lifecycle.awaitInitialPublication(); XCTFail("Closed owner was admitted") }
        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
    }

    func testInitialReadinessFailureRejectsWithoutWaitingForAnotherNativeEvent() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), store = rig.store
        let completed = expectation(description: "failed first sample released receiver")
        var result: Result<AgentBridgeNativeCatalogPublication, Error>?
        let receiver = Task {
            do { result = .success(try await lifecycle.awaitInitialPublication()) }
            catch { result = .failure(error) }
            completed.fulfill()
        }
        defer { receiver.cancel(); lifecycle.stop() }
        do {
            _ = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: lifecycle, peer: rig.peer,
                existingDirectory: rig.directory, sample: { throw AgentBridgeValidationError.permissionRequired },
                loadStore: { _ in XCTFail("Failed sample opened issuer storage"); return store })
            XCTFail("Failed sample returned a publication")
        } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
        await fulfillment(of: [completed], timeout: 3)
        do { _ = try XCTUnwrap(result).get(); XCTFail("Failed publication admitted receiver") }
        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .bindingChanged) }
        let facts = try nativeState()
        _ = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: lifecycle, peer: rig.peer,
            existingDirectory: rig.directory, sample: { facts }, loadStore: { _ in store })
        do { _ = try await lifecycle.awaitInitialPublication(); XCTFail("A later event revived failed admission") }
        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .bindingChanged) }
        lifecycle.stop()
        do { _ = try await lifecycle.awaitInitialPublication(); XCTFail("Closed failed owner admitted receiver") }
        catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
    }

    func testInitialReadinessRejectsNativeSetupFailureBeforePublisherEntry() async throws {
        let lifecycle = AgentBridgeNativeCatalogLifecycle()
        let completed = expectation(description: "native setup failure released receiver")
        var failure: Error?
        let receiver = Task {
            do { _ = try await lifecycle.awaitInitialPublication(); XCTFail("Failed setup admitted receiver") }
            catch { failure = error }
            completed.fulfill()
        }
        let controller = try AgentBridgeNativeCatalogRefresh(lifecycle: lifecycle) {
            throw AgentBridgeValidationError.permissionRequired
        }
        defer { receiver.cancel(); controller.stop() }
        await fulfillment(of: [completed], timeout: 3)
        XCTAssertEqual(failure as? AgentBridgeValidationError, .bindingChanged)
    }

    func testNativeAdmissionOwnerReplacementCancelsQueuedIdentityBeforeSampling() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let admission = AgentBridgeNativeCatalogAdmission()
        let old = AgentBridgeNativeCatalogLifecycle(), current = AgentBridgeNativeCatalogLifecycle()
        let facts = try nativeState(), store = rig.store
        let published = expectation(description: "only replacement published")
        let rejected = expectation(description: "old receiver rejected on replacement")
        var oldFailure: Error?
        let oldReceiver = Task {
            do { _ = try await old.awaitInitialPublication(); XCTFail("Replaced owner admitted receiver") }
            catch { oldFailure = error }
            rejected.fulfill()
        }
        defer { oldReceiver.cancel() }
        var controller: AgentBridgeNativeCatalogRefresh?
        var calls = 0
        admission.configure { original in
            calls += 1
            XCTAssertTrue(original === current)
            controller = try AgentBridgeNativeCatalogRefresh(lifecycle: original) {
                _ = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: original, peer: rig.peer,
                    existingDirectory: rig.directory, sample: { facts }, loadStore: { _ in store })
                published.fulfill()
            }
        }
        admission.replace(with: old)
        admission.replace(with: current)
        await fulfillment(of: [published, rejected], timeout: 3)
        XCTAssertEqual(oldFailure as? AgentBridgeValidationError, .permissionRequired)
        let currentPublication = try await current.awaitInitialPublication()
        XCTAssertEqual(currentPublication, try current.currentPublication())
        XCTAssertEqual(calls, 1)
        XCTAssertThrowsError(try old.beginSample())
        XCTAssertEqual(try current.currentFacts(), facts)
        admission.replace(with: nil); controller?.stop()
    }

    func testNativeAdmissionCloseAndStoppedOwnerNeverInvokeSampler() async throws {
        let admission = AgentBridgeNativeCatalogAdmission(), lifecycle = AgentBridgeNativeCatalogLifecycle()
        let unexpected = expectation(description: "closed owner cannot enter SDK"); unexpected.isInverted = true
        admission.configure { _ in unexpected.fulfill() }
        admission.replace(with: lifecycle)
        admission.replace(with: nil)
        admission.replace(with: lifecycle) // A terminal identity cannot be renewed.
        await fulfillment(of: [unexpected], timeout: 0.15)
        XCTAssertThrowsError(try lifecycle.beginSample())
        admission.replace(with: nil)
    }

    func testNativeRefreshControllerSerializesAndCoalescesEventsAcrossActualPublication() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState(), store = rig.store
        let entered = expectation(description: "initial native sample suspended")
        let published = expectation(description: "fresh follow-up published")
        let extra = expectation(description: "no duplicate follow-up"); extra.isInverted = true
        let gate = AsyncStream<Void>.makeStream(bufferingPolicy: .bufferingNewest(1))
        var calls = 0
        let controller = try AgentBridgeNativeCatalogRefresh(lifecycle: lifecycle) {
            _ = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: lifecycle, peer: rig.peer,
                existingDirectory: rig.directory, sample: {
                    calls += 1
                    if calls == 1 { entered.fulfill(); for await _ in gate.stream { break } }
                    if calls > 2 { extra.fulfill() }
                    return facts
                }, loadStore: { _ in store })
            published.fulfill()
        }
        defer { gate.continuation.finish(); controller.stop() }
        await fulfillment(of: [entered], timeout: 3)
        XCTAssertEqual(calls, 1)
        try lifecycle.recordNativeEvent(); try lifecycle.recordNativeEvent()
        XCTAssertThrowsError(try lifecycle.currentPublication())
        XCTAssertThrowsError(try lifecycle.claimRefreshEvents()) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .busy)
        }
        gate.continuation.yield(())
        await fulfillment(of: [published], timeout: 3)
        await fulfillment(of: [extra], timeout: 0.15)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        XCTAssertNotNil(try rig.store.snapshot().nativeCatalog)
    }

    func testNativeRefreshControllerFailureWaitsForNativeEventWithoutSelfRetry() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState(), store = rig.store
        try lifecycle.observe(facts)
        try lifecycle.publish(to: store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let failed = expectation(description: "native refresh failed")
        let retried = expectation(description: "external event schedules refresh")
        let early = expectation(description: "no autonomous retry"); early.isInverted = true
        var calls = 0, allowRetry = false
        let controller = try AgentBridgeNativeCatalogRefresh(lifecycle: lifecycle) {
            calls += 1
            if calls == 1 { failed.fulfill(); throw AgentBridgeValidationError.busy }
            if !allowRetry { early.fulfill() }
            _ = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: lifecycle, peer: rig.peer,
                existingDirectory: rig.directory, sample: { facts }, loadStore: { _ in store })
            retried.fulfill()
        }
        defer { controller.stop() }
        await fulfillment(of: [failed], timeout: 3)
        await fulfillment(of: [early], timeout: 0.15)
        XCTAssertEqual(calls, 1)
        XCTAssertThrowsError(try lifecycle.currentPublication())
        allowRetry = true
        try lifecycle.recordNativeEvent()
        await fulfillment(of: [retried], timeout: 3)
        XCTAssertEqual(calls, 2)
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
    }

    func testNativeRefreshControllerStopCancelsSamplerAndPermanentlyClosesOwner() async throws {
        let lifecycle = AgentBridgeNativeCatalogLifecycle()
        let entered = expectation(description: "native sampler entered")
        let ended = expectation(description: "native sampler canceled")
        let controller = try AgentBridgeNativeCatalogRefresh(lifecycle: lifecycle) {
            defer { ended.fulfill() }
            entered.fulfill()
            try await Task.sleep(for: .seconds(30))
        }
        await fulfillment(of: [entered], timeout: 3)
        controller.stop()
        await fulfillment(of: [ended], timeout: 3)
        XCTAssertThrowsError(try lifecycle.beginSample()) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
        XCTAssertThrowsError(try lifecycle.recordNativeEvent())
        XCTAssertThrowsError(try AgentBridgeNativeCatalogRefresh(lifecycle: lifecycle) { XCTFail("Closed owner restarted") })
    }

    func testNativeRefreshComposesMetadataAndPreservesUnchangedPublication() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), store = rig.store
        let metadata = HealthKitNativePlanningMetadata(providerAvailable: true,
            availableNativeMetricIDs: ["steps"], authorizationFlowSatisfied: true)
        let facts = metadata.planningFacts(sourceCalendarTimezone: try AgentBridgeZone("UTC"),
            configurationProtection: .locked, entitlement: .required,
            foregroundAvailable: true, protectedDataAvailable: true)
        let first = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: lifecycle, peer: rig.peer,
            existingDirectory: rig.directory, sample: { await Task.yield(); return facts }, loadStore: { _ in store })
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        let next = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: lifecycle, peer: rig.peer,
            existingDirectory: rig.directory, sample: { facts }, loadStore: { _ in store })
        XCTAssertEqual(first, next)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
    }

    func testNativeRefreshFailedStaleOrRevokedSamplerCannotOpenIssuerOrReuseCache() async throws {
        for outcome in ["failed", "event", "revoked"] {
            let rig = try Rig(); defer { rig.cleanup() }
            let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState(), store = rig.store
            try lifecycle.observe(facts)
            try lifecycle.publish(to: store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
            do {
                _ = try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: lifecycle, peer: rig.peer,
                    existingDirectory: rig.directory, sample: {
                        await Task.yield()
                        if outcome == "failed" { throw AgentBridgeValidationError.busy }
                        if outcome == "event" { try lifecycle.observeNativeChange() }
                        if outcome == "revoked" { rig.session.revoke() }
                        return facts
                    }, loadStore: { _ in XCTFail("Rejected sampler opened issuer storage"); return store })
                XCTFail("Rejected sampler returned a publication")
            } catch {
                XCTAssertEqual(error as? AgentBridgeValidationError,
                    outcome == "failed" ? .busy : outcome == "event" ? .bindingChanged : .permissionRequired)
            }
            XCTAssertThrowsError(try lifecycle.currentPublication())
            XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        }
    }

    func testNativeRefreshCancellationRejectsBeforeStoreAndBeforePreCancelledSampler() async throws {
        for duringSample in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }
            let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState(), store = rig.store
            try lifecycle.observe(facts)
            try lifecycle.publish(to: store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
            let peer = rig.peer, directory = rig.directory
            let task = Task {
                if !duringSample { withUnsafeCurrentTask { $0?.cancel() } }
                return try await AgentBridgeNativeCatalogPublisher.refresh(lifecycle: lifecycle, peer: peer,
                    existingDirectory: directory, sample: {
                        XCTAssertTrue(duringSample)
                        withUnsafeCurrentTask { $0?.cancel() }
                        return facts
                    }, loadStore: { _ in XCTFail("Canceled refresh opened issuer storage"); return store })
            }
            do { _ = try await task.value; XCTFail("Canceled refresh returned success") }
            catch { XCTAssertTrue(error is CancellationError) }
            if duringSample { XCTAssertThrowsError(try lifecycle.currentPublication()) }
            else { XCTAssertEqual(try lifecycle.currentFacts(), facts) } // No work was started.
        }
    }

    func testNativeCatalogSampleRejectsEventsAcrossSuspensionAndWorkerAdmission() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
        let initial = try lifecycle.observe(facts, sampledDuring: lifecycle.beginSample())
        let store = rig.store
        let first = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer,
            existingDirectory: rig.directory, sample: initial, loadStore: { _ in store })
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        let sampling = try lifecycle.beginSample()
        await Task.yield() // A native event may arrive while SDK metadata is suspended.
        try lifecycle.observeNativeChange()
        XCTAssertThrowsError(try lifecycle.observe(facts, sampledDuring: sampling)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        let accepted = try lifecycle.observe(facts, sampledDuring: lifecycle.beginSample())
        try lifecycle.observeNativeChange() // Event after sample acceptance, before worker admission.
        do {
            _ = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer,
                existingDirectory: rig.directory, sample: accepted, loadStore: { _ in store })
            XCTFail("Stale sampled generation returned a publication")
        } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .bindingChanged) }
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertThrowsError(try lifecycle.currentPublication())
        let fresh = try lifecycle.observe(facts, sampledDuring: lifecycle.beginSample())
        let next = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer,
            existingDirectory: rig.directory, sample: fresh, loadStore: { _ in store })
        XCTAssertGreaterThan(next.revision, first.revision)
    }

    func testNativeCatalogSampleBindsExactOwnerAndChangedFactsGeneration() throws {
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), other = AgentBridgeNativeCatalogLifecycle()
        let ticket = try lifecycle.beginSample(), facts = try nativeState()
        XCTAssertThrowsError(try other.observe(facts, sampledDuring: ticket)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        _ = try lifecycle.observe(facts, sampledDuring: ticket)
        let preceding = try lifecycle.beginSample()
        _ = try lifecycle.observe(nativeState(zone: "UTC"), sampledDuring: preceding)
        XCTAssertThrowsError(try lifecycle.observe(facts, sampledDuring: preceding)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        let stopped = try lifecycle.beginSample()
        lifecycle.stop()
        XCTAssertThrowsError(try lifecycle.observe(facts, sampledDuring: stopped)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
        XCTAssertThrowsError(try lifecycle.beginSample())
    }

    func testNativeCatalogWorkerPublishesOffMainAndPreservesUnchangedGeneration() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
        try lifecycle.observe(facts)
        let store = rig.store
        let first = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer,
            existingDirectory: rig.directory, loadStore: { _ in
                XCTAssertFalse(Thread.isMainThread)
                return store
            })
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        let next = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer,
            existingDirectory: rig.directory, loadStore: { _ in store })
        XCTAssertEqual(next, first)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try lifecycle.currentFacts(), facts)
    }

    func testNativeCatalogWorkerRechecksOwnerAtPreparedAndPostFsyncBoundaries() async throws {
        for afterSync in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }
            let lifecycle = AgentBridgeNativeCatalogLifecycle()
            try lifecycle.observe(nativeState())
            let session = rig.session, store = rig.store
            if afterSync { rig.publication.onPublished = { _ in session.revoke() } }
            else { rig.publication.onPrepared = { _ in session.revoke() } }
            do {
                _ = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer,
                    existingDirectory: rig.directory, loadStore: { _ in store })
                XCTFail("Revoked native owner must suppress publication return")
            } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .permissionRequired) }
            XCTAssertThrowsError(try lifecycle.currentFacts()) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
            rig.publication.onPrepared = nil; rig.publication.onPublished = nil
            XCTAssertEqual(try rig.store.snapshot().nativeCatalog != nil, afterSync)
        }
    }

    func testNativeCatalogWorkerCancellationDuringKeyReadCannotReopenPublishedCache() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle(), facts = try nativeState()
        try lifecycle.observe(facts)
        try lifecycle.publish(to: rig.store, sourceInstallationID: rig.peer.peer.sourceInstallationID)
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        rig.keys.onNextLoad { entered.signal(); release.wait() }
        let store = rig.store, peer = rig.peer, directory = rig.directory
        let task = Task { try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: peer,
            existingDirectory: directory, loadStore: { _ in store }) }
        let reached = await Task.detached { entered.wait(timeout: .now() + 5) == .success }.value
        guard reached else { release.signal(); task.cancel(); _ = try? await task.value; return XCTFail("Worker never reached key boundary") }
        task.cancel()
        release.signal()
        do { _ = try await task.value; XCTFail("Canceled worker returned publication") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertThrowsError(try lifecycle.currentFacts()) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
    }

    func testNativeCatalogWorkerCancellationDuringFinalTrustCheckRejectsReturn() async throws {
        let checkCount = try await nativePublisherCheckCount()

        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(nativeState())
        let cancel = PublicationTaskCancellation(), store = rig.store
        let finalCheck = rig.session.checks + checkCount
        rig.session.observeChecks { if $0 == finalCheck { cancel.request() } }
        let peer = rig.peer, directory = rig.directory
        let task = Task { try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: peer,
            existingDirectory: directory, loadStore: { _ in store }) }
        cancel.install(task)
        do { _ = try await task.value; XCTFail("Cancellation during final trust check returned success") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertTrue(cancel.requested)
        XCTAssertThrowsError(try lifecycle.currentFacts()) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
    }

    private func nativePublisherCheckCount() async throws -> Int {
        // Fresh stores follow the same transaction, so identify the final callback without encoding
        // the implementation's signing/fsync check count in a regression.
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(nativeState())
        let before = rig.session.checks, store = rig.store
        _ = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer,
            existingDirectory: rig.directory, loadStore: { _ in store })
        let count = rig.session.checks - before
        XCTAssertGreaterThan(count, 0)
        return count
    }

    func testNativeCatalogMetadataChangeDuringFinalTrustCheckRejectsReturn() async throws {
        let checkCount = try await nativePublisherCheckCount()
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(nativeState())
        let finalCheck = rig.session.checks + checkCount, store = rig.store
        rig.session.observeChecks { if $0 == finalCheck { try? lifecycle.observeNativeChange() } }
        do {
            _ = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer,
                existingDirectory: rig.directory, loadStore: { _ in store })
            XCTFail("Metadata changed during final trust check but stale publication was returned")
        } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .bindingChanged) }
        XCTAssertThrowsError(try lifecycle.currentFacts())
    }

    func testNativeCatalogAlreadyCancelledWorkerDoesNotLoadPrivateStore() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(nativeState())
        let store = rig.store, keys = rig.keys, peer = rig.peer, directory = rig.directory
        let before = keys.loads
        let task = Task {
            try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: peer,
                existingDirectory: directory, loadStore: { _ in
                    _ = try keys.loadExistingExportAuthorityKey()
                    return store
                })
        }
        task.cancel() // This actor has not yielded, so the async entry sees cancellation first.
        do { _ = try await task.value; XCTFail("Already canceled native task returned publication") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(keys.loads, before)
    }

    func testNativeCatalogWorkerDoesNotCreateMissingPrivateStore() async throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let lifecycle = AgentBridgeNativeCatalogLifecycle()
        try lifecycle.observe(nativeState())
        let missing = rig.parent.appendingPathComponent("missing-native-authority")
        do {
            _ = try await AgentBridgeNativeCatalogPublisher.publish(lifecycle: lifecycle, peer: rig.peer, existingDirectory: missing)
            XCTFail("Missing authority must not bootstrap")
        } catch { XCTAssertEqual(error as? AgentBridgeValidationError, .bindingChanged) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        XCTAssertThrowsError(try lifecycle.currentFacts())
    }

    func testNativeCatalogResamplesAtStagedAndPostFsyncPublicationBoundaries() throws {
        for afterSync in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }
            var facts = try nativeState()
            let unavailable = try nativeState(foregroundAvailable: false)
            let file = rig.directory.appendingPathComponent("state.json"), before = try Data(contentsOf: file)
            var observed = false
            if afterSync { rig.publication.onPublished = { _ in observed = true; facts = unavailable } }
            else { rig.publication.onPrepared = { _ in observed = true; facts = unavailable } }
            XCTAssertThrowsError(try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
            XCTAssertTrue(observed)
            rig.publication.onPrepared = nil; rig.publication.onPublished = nil
            if afterSync {
                let retained = try XCTUnwrap(rig.store.snapshot().nativeCatalog)
                XCTAssertNotEqual(retained.factsSHA256, try facts.fingerprint(sourceInstallationID: rig.peer.peer.sourceInstallationID))
                let next = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }
                XCTAssertEqual(next.revision, 2) // Postpublication failure never rolls a counter back.
            } else { XCTAssertEqual(try Data(contentsOf: file), before) }
        }
    }

    func testNativeCatalogDoesNotRepairMissingStateOrKeyAndRejectsSourceRebinding() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let facts = try nativeState(), file = rig.directory.appendingPathComponent("state.json")
        let publication = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }
        let before = try Data(contentsOf: file)
        XCTAssertThrowsError(try rig.store.publishNativeCatalog(sourceInstallationID: id(99)) { facts }) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        let locked = try AgentBridgeExportAuthorityStore(existingDirectory: rig.directory, protectedKeys: FakeProtectedKeys(key: nil))
        var samples = 0
        XCTAssertThrowsError(try locked.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { samples += 1; return facts }) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired)
        }
        XCTAssertEqual(samples, 0); XCTAssertEqual(try Data(contentsOf: file), before)
        XCTAssertEqual(try rig.store.snapshot().nativeCatalog, publication)
        try FileManager.default.removeItem(at: file)
        XCTAssertThrowsError(try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { samples += 1; return facts })
        XCTAssertEqual(samples, 0); XCTAssertFalse(FileManager.default.fileExists(atPath: file.path))
    }

    func testExhaustedNativeCatalogAllowsExactRetryButCannotResetOrAdvance() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let facts = try nativeState()
        let first = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }
        var fixture = try rig.store.snapshot()
        fixture.nativeCatalog = .init(revision: Int64(Int32.max), sourceInstallationID: first.sourceInstallationID, factsSHA256: first.factsSHA256)
        // Independent signed boundary fixture, using the synthetic protected key and production
        // private payload grammar. No production mutation/reset or test-only writer API is added.
        let payload = try AgentBridgeV4Codec.canonicalize(JSONEncoder().encode(fixture))
        let mac = Data(HMAC<SHA256>.authenticationCode(for: Data("HealthMd.AgentBridge.NativeExportAuthorityStore.v1\0".utf8) + payload,
            using: try XCTUnwrap(rig.keys.key)))
        let signed: [String: Any] = ["version": 2, "state": try JSONSerialization.jsonObject(with: payload), "mac": mac.base64EncodedString()]
        let file = rig.directory.appendingPathComponent("state.json")
        let before = try AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: signed))
        try before.write(to: file)
        XCTAssertEqual(try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }.revision, Int64(Int32.max))
        XCTAssertThrowsError(try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID,
            invalidatingObservedChange: true) { facts }) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .busy)
        }
        XCTAssertEqual(try Data(contentsOf: file), before)
        let changed = try nativeState(foregroundAvailable: false)
        XCTAssertThrowsError(try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { changed }) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .busy)
        }
        XCTAssertEqual(try Data(contentsOf: file), before)
    }

    func testEveryAdvertisedNativeFactChangeAdvancesItsPublicationIdentity() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let base = try nativeState()
        let first = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { base }
        let alternatives = try [nativeState(available: ["steps"]), nativeState(zone: "UTC"), nativeState(protection: .unlockedNative),
            nativeState(grants: .required), nativeState(grants: .unverified), nativeState(entitlement: .required),
            nativeState(foregroundAvailable: false), nativeState(protectedDataAvailable: false)]
        var revision: Int64 = 1
        for changed in alternatives {
            let next = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { changed }
            revision += 1
            XCTAssertEqual(next.revision, revision)
            XCTAssertNotEqual(next.factsSHA256, first.factsSHA256)
            let restored = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { base }
            revision += 1
            XCTAssertEqual(restored.revision, revision)
            XCTAssertEqual(restored.factsSHA256, first.factsSHA256)
        }
        XCTAssertTrue(try rig.store.snapshot().delegations.isEmpty)
        XCTAssertTrue(try rig.store.snapshot().plans.isEmpty)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
    }

    func testPrivateCatalogVersionRequiresExactlyItsPublicationShape() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let facts = try nativeState()
        _ = try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { facts }
        let state = try rig.store.snapshot(), file = rig.directory.appendingPathComponent("state.json")
        for dropCatalog in [false, true] {
            var fixture = state
            if dropCatalog { fixture.nativeCatalog = nil }
            let payload = try AgentBridgeV4Codec.canonicalize(JSONEncoder().encode(fixture))
            let mac = Data(HMAC<SHA256>.authenticationCode(for: Data("HealthMd.AgentBridge.NativeExportAuthorityStore.v1\0".utf8) + payload,
                using: try XCTUnwrap(rig.keys.key)))
            let signed: [String: Any] = ["version": dropCatalog ? 2 : 1,
                "state": try JSONSerialization.jsonObject(with: payload), "mac": mac.base64EncodedString()]
            let bytes = try AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: signed))
            try bytes.write(to: file)
            var samples = 0
            XCTAssertThrowsError(try rig.store.publishNativeCatalog(sourceInstallationID: rig.peer.peer.sourceInstallationID) { samples += 1; return facts }) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
            }
            XCTAssertEqual(samples, 0); XCTAssertEqual(try Data(contentsOf: file), bytes)
        }
    }

    func testDiscoveryAndPlanningKeepPolicySupportStableWhenOnlySelectedConfigurationIsLoaded() throws {
        for kind in ["explicit", "saved", "profile"] {
            let rig = try Rig(withSaved: true); defer { rig.cleanup() }; try rig.enroll()
            let discovery = try rig.discover()
            XCTAssertEqual(discovery.settingsPolicies, [.explicit, .profile, .savedDeviceSettings])
            XCTAssertEqual(rig.reader.defaults.reads, 0)
            let policy: AgentBridgeSettingsPolicy
            switch kind {
            case "saved": policy = .savedDeviceSettings(expectedRevision: 7)
            case "profile": policy = .profile(profileID: try id(50), expectedRevision: 7)
            default: policy = .explicit(output())
            }
            let response = try rig.send(.planRequest(rig.request(discovery: discovery, policy: policy)))
            guard case .plan(let plan) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: response).payload else {
                return XCTFail("The selected configuration must not change supported policy metadata")
            }
            XCTAssertEqual(plan.intent.settingsPolicy, policy)
            XCTAssertEqual(try rig.service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer), plan)
            XCTAssertEqual(rig.reader.defaults.writes, 0)
            if kind == "explicit" { XCTAssertEqual(rig.reader.defaults.reads, 0) }
            else { XCTAssertGreaterThan(rig.reader.defaults.reads, 0) }
        }
    }

    func testNativePlanReviewUsesStoredPlanWithoutIssuingConsentOrChangingPreferences() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), path = rig.directory.appendingPathComponent("state.json")
        let before = try Data(contentsOf: path), generation = try rig.store.snapshot().generation
        let reads = rig.reader.defaults.reads, writes = rig.reader.defaults.writes
        let reviewed = try rig.service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)
        XCTAssertEqual(reviewed, plan)
        XCTAssertEqual(try AgentBridgeSemantics.binding(reviewed), try AgentBridgeSemantics.binding(plan))
        XCTAssertEqual(try rig.restartedService().reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer), plan)
        XCTAssertEqual(try Data(contentsOf: path), before)
        XCTAssertEqual(try rig.store.snapshot().generation, generation)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
        XCTAssertEqual(rig.reader.defaults.reads, reads); XCTAssertEqual(rig.reader.defaults.writes, writes)
        try rig.expectError(.approvalRequired, request: .approvalRequest(.init(
            binding: AgentBridgeSemantics.binding(reviewed), planId: plan.planId, requestId: id(104))))
    }

    func testNativePlanReviewRequiresExecutionDelegationAndNativeReadiness() throws {
        for mode in ["plan_only", "permission", "entitlement"] {
            let rig = try Rig(); defer { rig.cleanup() }
            if mode == "permission" { rig.reader.grants = .required }
            if mode == "entitlement" { rig.reader.entitlement = .required }
            let grant = try rig.grant()
            let eligible = try AgentBridgeExportDelegation(authorityID: grant.authorityID, issuer: grant.issuer,
                grantRevision: grant.grantRevision, peer: grant.peer,
                rights: mode == "plan_only" ? [.discover, .plan] : grant.rights,
                expiresAt: grant.expiresAt, bounds: grant.bounds)
            try rig.store.storeNativeDelegation(eligible, expectedGeneration: 0, authorization: FakeNativeAuthorization())
            let plan = try rig.makePlan(), path = rig.directory.appendingPathComponent("state.json")
            let before = try Data(contentsOf: path)
            XCTAssertThrowsError(try rig.service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)) {
                let expected: AgentBridgeValidationError = mode == "plan_only" ? .approvalRequired :
                    (mode == "entitlement" ? .entitlementRequired : .permissionRequired)
                XCTAssertEqual($0 as? AgentBridgeValidationError, expected)
            }
            XCTAssertEqual(try Data(contentsOf: path), before)
        }
    }

    func testNativePlanReviewRechecksLiveTrustConfigurationAndExpiryBeforeReturn() throws {
        for mode in ["permission", "configuration", "expiry"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let plan = try rig.makePlan(), path = rig.directory.appendingPathComponent("state.json")
            let before = try Data(contentsOf: path)
            var reads = 0
            rig.reader.beforeReturn = {
                reads += 1
                guard reads == 2 else { return }
                switch mode {
                case "permission": rig.session.revoke()
                case "configuration": rig.reader.available.remove("steps")
                default: rig.clock.advance(seconds: 600)
                }
            }
            XCTAssertThrowsError(try rig.service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)) {
                let expected: AgentBridgeValidationError = mode == "permission" ? .permissionRequired :
                    (mode == "configuration" ? .unsupportedMetric : .planExpired)
                XCTAssertEqual($0 as? AgentBridgeValidationError, expected)
            }
            XCTAssertEqual(reads, 2)
            XCTAssertEqual(try Data(contentsOf: path), before)
            rig.reader.beforeReturn = nil
        }
    }

    func testNativePlanReviewRejectsForeignPeerAndUnknownPlanWithoutWrites() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), path = rig.directory.appendingPathComponent("state.json")
        let before = try Data(contentsOf: path)
        let source = try XCTUnwrap(UUID(uuidString: id(1).rawValue)), host = try XCTUnwrap(UUID(uuidString: id(99).rawValue))
        let session = try RevocableNativeSession(source: source, host: host)
        let foreign = try AgentBridgeExportAuthenticatedPeer(nativeSourceInstallationID: source,
            authenticatedHostInstallationID: host, currentNativeSession: session)
        XCTAssertThrowsError(try rig.service.reviewNativePlan(planID: plan.planId, authenticatedPeer: foreign)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .bindingChanged)
        }
        XCTAssertThrowsError(try rig.service.reviewNativePlan(planID: id(99), authenticatedPeer: rig.peer))
        XCTAssertEqual(try Data(contentsOf: path), before)
    }

    func testNativePlanReviewDoesNotRetainAuthorityAfterRevocationOrClockAdvance() throws {
        for revoke in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let plan = try rig.makePlan()
            let reviewed = try rig.service.reviewNativePlan(planID: plan.planId, authenticatedPeer: rig.peer)
            if revoke {
                try rig.store.revokeNativeDelegation(rig.grant().reference(), expectedGeneration: rig.store.snapshot().generation,
                    authorization: FakeNativeAuthorization())
            } else { rig.clock.advanceAfterNextSample(seconds: 600) }
            let path = rig.directory.appendingPathComponent("state.json"), before = try Data(contentsOf: path)
            XCTAssertThrowsError(try rig.service.reviewNativePlan(planID: reviewed.planId, authenticatedPeer: rig.peer)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, revoke ? .approvalRequired : .planExpired)
            }
            XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: reviewed.planId, binding: AgentBridgeSemantics.binding(reviewed),
                approvalID: id(8), authenticatedPeer: rig.peer,
                authorization: LiveExactApprovalAuthorization(planID: reviewed.planId, binding: AgentBridgeSemantics.binding(reviewed))))
            XCTAssertEqual(try Data(contentsOf: path), before)
        }
    }

    func testExactNativeApprovalRejectsConsentLostDuringKeyAndConfigurationReads() throws {
        for duringKey in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
            let path = rig.directory.appendingPathComponent("state.json")
            let before = try Data(contentsOf: path)
            let native = LiveExactApprovalAuthorization(planID: plan.planId, binding: binding)
            var observed = false
            native.onCheck = { count in
                if count == 1 {
                    let loseConsent = { observed = true; native.allowed = false }
                    if duringKey { rig.keys.onNextLoad(loseConsent) }
                    else { rig.reader.beforeReturn = loseConsent }
                }
            }
            XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer, authorization: native)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .approvalRequired)
            }
            rig.reader.beforeReturn = nil
            XCTAssertTrue(observed)
            XCTAssertEqual(try Data(contentsOf: path), before)
            XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
            XCTAssertEqual(rig.reader.defaults.writes, 0)
        }
    }

    func testExactNativeApprovalRechecksConsentAtStagingPublicationAndFinalKeyRead() throws {
        for phase in ["staging", "publication", "return_key"] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
            let path = rig.directory.appendingPathComponent("state.json")
            let before = try Data(contentsOf: path)
            let native = LiveExactApprovalAuthorization(planID: plan.planId, binding: binding)
            var observed = false
            if phase == "staging" {
                rig.publication.onPrepared = { candidate in
                    XCTAssertEqual(candidate.decisions.count, 1)
                    XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: rig.directory.path).contains { $0.hasPrefix("transaction-") })
                    observed = true; native.allowed = false
                }
            } else {
                rig.publication.onPublished = { candidate in
                    XCTAssertEqual(candidate.decisions.count, 1)
                    if phase == "return_key" { rig.keys.onNextLoad { observed = true; native.allowed = false } }
                    else { observed = true; native.allowed = false }
                }
            }
            XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer, authorization: native)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, .approvalRequired)
            }
            XCTAssertTrue(observed)
            if phase == "staging" {
                XCTAssertEqual(try Data(contentsOf: path), before)
                XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
            } else {
                XCTAssertNotEqual(try Data(contentsOf: path), before)
                let approval = try XCTUnwrap(rig.store.snapshot().decisions.first).approval()
                XCTAssertEqual(approval.binding, binding) // Retain the already committed exact decision; never roll back.
                XCTAssertEqual(approval.approvedAt.rawValue, "2026-03-09T00:00:00Z")
            }
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: rig.directory.path).sorted(), ["lock", "state.json"])
        }
    }

    func testExactNativeApprovalSamplesLiveExpiryAfterRepeatedNativeCheck() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        let path = rig.directory.appendingPathComponent("state.json")
        let before = try Data(contentsOf: path)
        let native = LiveExactApprovalAuthorization(planID: plan.planId, binding: binding)
        var delayed = false
        native.onCheck = { count in if count == 2 { delayed = true; rig.clock.advance(seconds: 600) } }
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer, authorization: native)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired)
        }
        XCTAssertTrue(delayed)
        XCTAssertEqual(try Data(contentsOf: path), before)
        XCTAssertTrue(try rig.store.snapshot().decisions.isEmpty)
    }

    func testMissingAuthorityNeverCreatesStoreGrantKeyOrDecision() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let missing = rig.parent.appendingPathComponent("missing")
        XCTAssertThrowsError(try AgentBridgeExportAuthorityStore(existingDirectory: missing, protectedKeys: rig.keys))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        let absentKeys = FakeProtectedKeys(key: nil)
        XCTAssertThrowsError(try AgentBridgeExportAuthorityStore.createPrivateStore(at: missing, protectedKeys: absentKeys, authorization: FakeNativeAuthorization()))
        XCTAssertFalse(FileManager.default.fileExists(atPath: missing.path))
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        let discovery = try rig.discover()
        XCTAssertTrue(discovery.authorityReferences.isEmpty)
        XCTAssertEqual(discovery.features, [.explicitSettings, .zeroHealthPlan])
        XCTAssertEqual(discovery.queryCatalogSha256.rawValue, String(repeating: "0", count: 64))
        XCTAssertTrue(discovery.queryOperations.isEmpty)
        XCTAssertTrue(discovery.projectionProducts.isEmpty)
        let reads = rig.reader.calls.count
        try rig.expectError(.approvalRequired, request: .planRequest(rig.request(discovery: discovery)))
        XCTAssertEqual(rig.reader.calls.count, reads) // Reject missing private authority BEFORE configuration lookup.
        try rig.expectError(.bindingChanged, request: .approvalRequest(.init(binding: rig.unissuedBinding(discovery: discovery), planId: id(6), requestId: id(103))))
        let empty = try rig.store.snapshot()
        XCTAssertEqual(empty.generation, 0)
        XCTAssertEqual(empty.delegations.count + empty.plans.count + empty.decisions.count, 0)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
    }

    func testNativePreapprovedTracerUsesProductionResolverAndNormativeResponse() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        try rig.enroll()
        let discovery = try rig.discover()
        let request = try rig.request(discovery: discovery, metrics: ["hrv", "steps"])
        let response = try rig.send(.planRequest(request))
        guard case .plan(let plan) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: response).payload else { return XCTFail("plan required") }
        XCTAssertEqual(plan.planId, try id(6))
        XCTAssertEqual(plan.resolvedDates, try .exact(.init(startDate: date("2026-03-07"), endDate: date("2026-03-08"))))
        XCTAssertEqual(plan.predictedPaths.map(\.rawValue), ["2026/2026-03-07.json", "2026/2026-03-08.json"])
        XCTAssertEqual(plan.resolvedMetricIds.map(\.rawValue), ["hrv", "steps"])
        XCTAssertEqual(plan.effectiveSettings, output())
        XCTAssertEqual(plan.pathPrediction, .exactRequestedDays)
        XCTAssertTrue(plan.requiredActions.isEmpty)
        XCTAssertEqual(plan.limitations.map(\.rawValue), ["healthkit_read_authorization_unobservable"])
        XCTAssertEqual(plan.expiresAt.rawValue, "2026-03-09T00:10:00Z")
        XCTAssertEqual(plan.authorityReferences.native, try rig.grant().reference())
        XCTAssertEqual(plan.authorityReferences.host, request.hostAuthorityReference)
        XCTAssertEqual(plan.revisions, [])
        let expectedOrigins = outputPointers.map { AgentBridgeOrigin(origin: .request, pointer: "/effective_settings" + $0, revision: 0) } + capturePointers.map { .init(origin: .request, pointer: $0, revision: 0) } + [.init(origin: .request, pointer: "/calendar_timezone", revision: 0), .init(origin: .resolvedCalendar, pointer: "/resolved_dates", revision: 0)]
        XCTAssertEqual(plan.origins, expectedOrigins.sorted { $0.pointer < $1.pointer })
        // Independent literal byte oracle is constructed before any fixture comparison. The expected
        // response pins all effective/capture leaves, not just a digest or a fixture verdict.
        XCTAssertEqual(AgentBridgeV4Codec.sha256(response), Self.tracerResponseSHA256)
        XCTAssertEqual(response, try AgentBridgeV4Codec.canonicalize(response))
        let native = try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: rig.peer)
        XCTAssertEqual(native.issuer, .nativeSource)
        XCTAssertEqual(native.authorityId, plan.authorityReferences.native.authorityId)
        XCTAssertEqual(native.scopeSha256, plan.scopeSha256)
        XCTAssertEqual(native.configurationProtection, .notApplicable)
        XCTAssertEqual(native.rights, [.discover, .exportExecute, .plan])
        XCTAssertNil(native.controlReadScope)
        // Actual resolver's native SDNN mapping, not a Health Connect RMSSD alias.
        let resolved = try AgentBridgeRequestSettingsResolver.resolveWithOutput(request.intent, inputs: rig.reader.inputs, clock: rig.now, calendar: rig.calendar)
        XCTAssertEqual(resolved.native.selection.map(\.sourceSelector), ["HKQuantityTypeIdentifierHeartRateVariabilitySDNN", "HKQuantityTypeIdentifierStepCount"])
        XCTAssertEqual(resolved.native.selection.map(\.sourceReducer), ["discreteAvg", "cumulative"])
        XCTAssertEqual(resolved.native.selection.map(\.canonicalUnit), ["ms", "steps"])
        XCTAssertEqual(try rig.store.snapshot().plans.count, 1)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
        XCTAssertEqual(rig.reader.defaults.reads, 0)
        let effects = try JSONSerialization.jsonObject(with: AgentBridgeV4Codec.encode(plan.sideEffects)) as? [String: Int]
        XCTAssertEqual(effects, ["health_reads": 0, "earliest_date_reads": 0, "content_preview_reads": 0, "quota_consumed": 0, "output_writes": 0, "settings_mutations": 0, "credential_enrollments": 0, "wake_enrollments": 0])
    }

    func testExpiryDuringNativeConsentNeverPersistsALateDecision() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        var consentCompleted = false
        let native = FakeNativeAuthorization(binding: binding, afterAuthorization: {
            consentCompleted = true
            rig.clock.advance(seconds: 600) // Exact issued-plan expiry, while the real native callback runs.
        })
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                               authorization: native)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired) }
        XCTAssertTrue(consentCompleted)
        XCTAssertEqual(rig.now, ISO8601DateFormatter().date(from: "2026-03-09T00:10:00Z"))
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testApprovalRelayRequiresIndependentExactNativeDecisionAndSurvivesRestart() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan()
        let approvalRequest = AgentBridgeApprovalRequest(binding: AgentBridgeSemantics.binding(plan), planId: plan.planId, requestId: try id(103))
        let before = try rig.store.snapshot().generation
        try rig.expectError(.approvalRequired, request: .approvalRequest(approvalRequest))
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: approvalRequest.binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                               authorization: FakeNativeAuthorization(deny: true)))
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
        try rig.service.storeNativeDecision(planID: plan.planId, binding: approvalRequest.binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                            authorization: FakeNativeAuthorization(binding: approvalRequest.binding))
        let bytes = try rig.send(.approvalRequest(approvalRequest))
        let restarted = try rig.restartedService()
        rig.clock.advance(seconds: 30)
        let replay = try restarted.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .approvalRequest(approvalRequest))), authenticatedPeer: rig.peer)
        XCTAssertEqual(bytes, replay)
        guard case .approval(let approval) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes).payload else { return XCTFail("approval required") }
        XCTAssertEqual(approval.approvalId, try id(8))
        XCTAssertEqual(approval.binding, approvalRequest.binding)
        XCTAssertEqual(approval.approvedAt.rawValue, "2026-03-09T00:00:00Z")
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 1)
    }

    func testLiveClockRejectsCachedPlanAfterProtectedKeyDelay() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        _ = try rig.makePlan()
        let state = try rig.store.snapshot(), request = try state.plans[0].request()
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        let loads = rig.keys.loads
        rig.keys.onNextLoad { rig.clock.advance(seconds: 600) }
        let reply = try rig.send(.planRequest(request))
        XCTAssertEqual(try? error(reply), .planExpired)
        XCTAssertGreaterThan(rig.keys.loads, loads)
        XCTAssertEqual(rig.now, ISO8601DateFormatter().date(from: "2026-03-09T00:10:00Z"))
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 1)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testLiveClockRejectsPlanAfterConfigurationCrossesParentExpiry() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll(expires: "2026-03-09T00:01:00Z")
        let request = try rig.request(discovery: rig.discover())
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        var delayed = false
        rig.reader.beforeReturn = {
            if !delayed { delayed = true; rig.clock.advance(seconds: 60) }
        }
        let reply = try rig.send(.planRequest(request))
        XCTAssertEqual(try? error(reply), .approvalRequired)
        XCTAssertTrue(delayed)
        XCTAssertEqual(rig.now, ISO8601DateFormatter().date(from: "2026-03-09T00:01:00Z"))
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 0)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testLiveClockRejectsScopedAuthorityAtLastSessionCallback() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan()
        let start = rig.session.checks
        _ = try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: rig.peer)
        let checksPerReturn = rig.session.checks - start
        let finalCheck = rig.session.checks + checksPerReturn
        var advanced = false
        rig.session.observeChecks { count in
            if count == finalCheck { advanced = true; rig.clock.advance(seconds: 600) }
        }
        XCTAssertThrowsError(try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: rig.peer)) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired)
        }
        XCTAssertTrue(advanced) // Observed callback at the last fence of an otherwise identical return.
        XCTAssertEqual(rig.session.checks, finalCheck)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
    }

    func testLiveClockRejectsCachedApprovalAtLastSessionCallback() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                            authorization: FakeNativeAuthorization(binding: binding))
        let request = AgentBridgeDocument.approvalRequest(.init(binding: binding, planId: plan.planId, requestId: try id(103)))
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), start = rig.session.checks
        _ = try rig.send(request)
        let finalCheck = rig.session.checks + (rig.session.checks - start)
        var advanced = false
        rig.session.observeChecks { count in
            if count == finalCheck { advanced = true; rig.clock.advance(seconds: 600) }
        }
        let reply = try rig.send(request)
        XCTAssertEqual(try? error(reply), .planExpired)
        XCTAssertTrue(advanced)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 1) // Not renewed/evicted.
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testPublicationClockRejectsPlanBeforeAtomicRenameAfterFsync() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try rig.request(discovery: rig.discover())
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        var prepared = false
        rig.publication.onPrepared = { candidate in
            prepared = true
            XCTAssertEqual(candidate.plans.count, 1)
            XCTAssertEqual(candidate.decisions.count, 0)
            XCTAssertEqual(candidate.generation, 2)
            let temporary = try XCTUnwrap(FileManager.default.contentsOfDirectory(at: rig.directory, includingPropertiesForKeys: nil).first { $0.lastPathComponent.hasPrefix("transaction-") })
            let serialized = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: temporary)) as? [String: Any])
            XCTAssertEqual((serialized["state"] as? [String: Any])?["generation"] as? Int, 2)
            rig.clock.advance(seconds: 600) // The actual private candidate is serialized and fsync'ed.
        }
        let reply = try rig.send(.planRequest(request))
        XCTAssertEqual(try? error(reply), .planExpired)
        XCTAssertTrue(prepared)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 0)
        XCTAssertEqual(try rig.store.snapshot().generation, 1)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: rig.directory.path).sorted(), ["lock", "state.json"])
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testPublicationClockRejectsDecisionBeforeAtomicRenameAfterFsync() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        var prepared = false
        rig.publication.onPrepared = { candidate in
            prepared = true
            XCTAssertEqual(candidate.plans.count, 1)
            XCTAssertEqual(candidate.decisions.count, 1)
            XCTAssertEqual(candidate.generation, 3)
            rig.clock.advance(seconds: 600)
        }
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                               authorization: FakeNativeAuthorization(binding: binding))) {
            XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired)
        }
        XCTAssertTrue(prepared)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
        XCTAssertEqual(try rig.store.snapshot().generation, 2)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testDecisionTimestampIsPostConsentAndExactRetryNeverRenewsIt() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        var consentCompleted = false
        try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
            authorization: FakeNativeAuthorization(binding: binding, afterAuthorization: {
                consentCompleted = true; rig.clock.advance(seconds: 30)
            }))
        XCTAssertTrue(consentCompleted)
        let approval = try XCTUnwrap(rig.store.snapshot().decisions.first).approval()
        XCTAssertEqual(approval.approvedAt.rawValue, "2026-03-09T00:00:30Z")
        XCTAssertEqual(approval.binding.expiresAt, plan.expiresAt)
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        rig.clock.advance(seconds: 50)
        try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                            authorization: FakeNativeAuthorization(binding: binding))
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try rig.store.snapshot().decisions[0].approval(), approval)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testProtectedKeyDelayAfterNativeConsentCannotPublishDecision() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        var delayedKeyLoaded = false
        let native = FakeNativeAuthorization(binding: binding, afterAuthorization: {
            rig.keys.onNextLoad { delayedKeyLoaded = true; rig.clock.advance(seconds: 600) }
        })
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                               authorization: native)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired) }
        XCTAssertTrue(delayedKeyLoaded)
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
    }

    func testNativeConsentCannotMaskCurrentConfigOrGrantRevocation() throws {
        for revokeGrant in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
            let before = try rig.store.snapshot().generation
            var consentCompleted = false
            let native = FakeNativeAuthorization(binding: binding, afterAuthorization: {
                consentCompleted = true
                if revokeGrant {
                    try! rig.store.revokeNativeDelegation(binding.authorityReferences.native, expectedGeneration: before, authorization: FakeNativeAuthorization())
                } else { rig.reader.grants = .required }
            })
            XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                                   authorization: native)) {
                XCTAssertEqual($0 as? AgentBridgeValidationError, revokeGrant ? .revisionConflict : .bindingChanged)
            }
            XCTAssertTrue(consentCompleted)
            let state = try rig.store.snapshot()
            XCTAssertEqual(state.decisions.count, 0)
            XCTAssertEqual(state.generation, before + (revokeGrant ? 1 : 0))
            XCTAssertEqual(state.delegations[0].revoked, revokeGrant)
            XCTAssertEqual(rig.reader.defaults.writes, 0)
        }
    }

    func testExpiryAfterPublicationSuppressesPlanAndRetainsUnusableMetadata() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try rig.request(discovery: rig.discover())
        var published = false
        rig.publication.onPublished = { current in
            published = true
            XCTAssertEqual(current.plans.count, 1)
            XCTAssertEqual(current.generation, 2)
            rig.clock.advance(seconds: 600) // Atomic rename/root fsync ALREADY succeeded.
        }
        XCTAssertEqual(try? error(rig.send(.planRequest(request))), .planExpired)
        XCTAssertTrue(published)
        let state = try rig.store.snapshot(), plan = try state.plans[0].plan()
        XCTAssertEqual(state.generation, 2)
        XCTAssertEqual(state.decisions.count, 0)
        XCTAssertEqual(plan.expiresAt.rawValue, "2026-03-09T00:10:00Z")
        let bytes = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        rig.publication.onPublished = nil
        XCTAssertThrowsError(try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: rig.peer)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired) }
        try rig.expectError(.planExpired, request: .planRequest(request))
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: AgentBridgeSemantics.binding(plan), approvalID: id(8), authenticatedPeer: rig.peer,
                                                               authorization: FakeNativeAuthorization(binding: AgentBridgeSemantics.binding(plan)))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired) }
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), bytes)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 1) // No eviction/recreation or expiry renewal.
    }

    func testExpiryAfterDecisionPublicationSuppressesReturnAndEveryLaterAuthorityUse() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        var published = false
        rig.publication.onPublished = { current in
            published = true
            XCTAssertEqual(current.decisions.count, 1)
            rig.clock.advance(seconds: 600)
        }
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                               authorization: FakeNativeAuthorization(binding: binding))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired) }
        XCTAssertTrue(published)
        let state = try rig.store.snapshot(), approval = try state.decisions[0].approval()
        XCTAssertEqual(state.generation, 3)
        XCTAssertEqual(approval.approvedAt.rawValue, "2026-03-09T00:00:00Z") // It was valid AT publication, not late consent.
        let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
        rig.publication.onPublished = nil
        let request = AgentBridgeDocument.approvalRequest(.init(binding: binding, planId: plan.planId, requestId: try id(103)))
        XCTAssertEqual(try? error(rig.send(request)), .planExpired)
        XCTAssertEqual(try? error(rig.restartedService().handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: request)), authenticatedPeer: rig.peer)), .planExpired)
        XCTAssertThrowsError(try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: rig.peer)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .planExpired) }
        XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testRevocationAtPublicationRejectsBeforeRenameAndAfterPublicationSuppressesReturn() throws {
        for afterRename in [false, true] {
            let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
            let request = try rig.request(discovery: rig.discover())
            let before = try Data(contentsOf: rig.directory.appendingPathComponent("state.json"))
            var revoked = false
            let revoke: (AgentBridgeExportAuthoritySnapshot) throws -> Void = { _ in revoked = true; rig.session.revoke() }
            if afterRename { rig.publication.onPublished = revoke } else { rig.publication.onPrepared = revoke }
            XCTAssertThrowsError(try rig.send(.planRequest(request))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
            XCTAssertTrue(revoked)
            let state = try rig.store.snapshot()
            XCTAssertEqual(state.plans.count, afterRename ? 1 : 0)
            XCTAssertEqual(state.decisions.count, 0)
            XCTAssertEqual(state.generation, afterRename ? 2 : 1)
            if !afterRename { XCTAssertEqual(try Data(contentsOf: rig.directory.appendingPathComponent("state.json")), before) }
            XCTAssertEqual(rig.reader.defaults.writes, 0)
        }
    }

    func testDiscoveryNeverReturnsParentExpiredDuringFinalSessionCallback() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll(expires: "2026-03-09T00:01:00Z")
        let start = rig.session.checks
        _ = try rig.discover()
        let finalCheck = rig.session.checks + (rig.session.checks - start)
        var advanced = false
        rig.session.observeChecks { count in
            if count == finalCheck { advanced = true; rig.clock.advance(seconds: 60) }
        }
        let bytes = try rig.send(.discoveryRequest(.init(requestID: id(104), peer: rig.peer.peer)))
        XCTAssertEqual(try? error(bytes), .approvalRequired)
        XCTAssertTrue(advanced)
        XCTAssertEqual(try rig.store.snapshot().generation, 1)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 0)
    }

    func testDiscoveryRechecksParentAfterResponseHashWork() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll(expires: "2026-03-09T00:01:00Z")
        let finalRead = rig.reader.calls.count + 2
        rig.reader.beforeReturn = {
            if rig.reader.calls.count == finalRead { rig.clock.advanceAfterNextSample(seconds: 60) }
        }
        // Final validation first samples time, then performs canonical capability hashing. Model
        // wall time advancing immediately AFTER that sample, before its last return-time sample.
        let reply = try rig.send(.discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer)))
        XCTAssertEqual(try? error(reply), .approvalRequired)
        XCTAssertEqual(rig.now, ISO8601DateFormatter().date(from: "2026-03-09T00:01:00Z"))
        XCTAssertEqual(try rig.store.snapshot().generation, 1)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testGatedActualServiceDiscoveryCandidate() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let value = try rig.discover() // Native typed constructors + REAL stored production service.
        XCTAssertEqual(value.outputSupport.settingPointers, outputPointers)
        XCTAssertEqual(value.authorityReferences, [try rig.grant().reference()])
        XCTAssertEqual(value.outputSupport.formats, [.json])
        XCTAssertEqual(value.outputProfiles, [.appleV8])
        XCTAssertEqual(value.features, [.explicitSettings, .zeroHealthPlan])
        let bytes = try AgentBridgeV4Codec.encode(value)
        XCTAssertEqual(try AgentBridgeV4Codec.decode(AgentBridgeDiscovery.self, from: bytes), value)
        let environment = ProcessInfo.processInfo.environment
        guard environment["HEALTHMD_GENERATE_AGENT_BRIDGE_V4"] == "1" else { return }
        let path = try XCTUnwrap(environment["HEALTHMD_AGENT_BRIDGE_CANDIDATES"])
        let root = "/private/tmp/healthmd-agent-bridge-20261004/evidence/swift-planning-boundaries/"
        guard path == root + "native-discovery-candidates.json" else { throw AgentBridgeValidationError.unsafePath }
        guard !FileManager.default.fileExists(atPath: path) else { throw AgentBridgeValidationError.bindingChanged }
        try bytes.write(to: URL(fileURLWithPath: path), options: .atomic) // Standalone closed discovery DTO ONLY.
        let provenance: [String: Any] = ["format": "standalone healthmd.agent_discovery/1", "producer": "Swift actual AgentBridgeExportPlanningService", "test": "AgentBridgeExportPlanningTests.testGatedActualServiceDiscoveryCandidate", "stage": "after-live-boundary-fix", "byte_count": bytes.count, "sha256": AgentBridgeV4Codec.sha256(bytes), "installed_transport_qualification": false]
        try JSONSerialization.data(withJSONObject: provenance, options: [.sortedKeys, .withoutEscapingSlashes]).write(to: URL(fileURLWithPath: path + ".provenance.json"), options: .atomic)
    }

    func testGatedActualServiceDiscoveryCompleteCandidate() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let discovery = try rig.discover()
        let intent = try rig.intent(metrics: ["heart_rate_avg", "steps"]) // Independent native literal constructors.
        let request = try AgentBridgePlanRequest(authorityId: id(7), authorityRevision: 1, capabilitySha256: discovery.capabilitySha256,
            hostAuthorityReference: .init(authorityId: id(13), grantRevision: 1, grantSha256: digest("2"), issuer: .authorizedHost),
            intent: intent, requestId: id(101))
        let response = try rig.send(.planRequest(request))
        guard case .plan(let plan) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: response).payload else { throw AgentBridgeValidationError.invalidRequest }
        XCTAssertEqual(plan.intent, intent)
        XCTAssertEqual(plan.capabilitySha256, discovery.capabilitySha256)
        XCTAssertEqual(plan.predictedPaths.map(\.rawValue), ["2026/2026-03-07.json", "2026/2026-03-08.json"])
        XCTAssertEqual(plan.resolvedMetricIds.map(\.rawValue), ["heart_rate_avg", "steps"])
        XCTAssertEqual(plan.effectiveSettings, output())
        XCTAssertEqual(discovery.outputSupport.settingPointers, outputPointers)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 1)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
        let environment = ProcessInfo.processInfo.environment
        guard environment["HEALTHMD_GENERATE_AGENT_BRIDGE_V4"] == "1" else { return }
        let path = try XCTUnwrap(environment["HEALTHMD_AGENT_BRIDGE_CANDIDATES"])
        guard path == "/private/tmp/healthmd-agent-bridge-20261004/evidence/swift-planning-boundaries/native-discovery-candidates-complete.json",
              !FileManager.default.fileExists(atPath: path) else { throw AgentBridgeValidationError.unsafePath }
        var sourceRoot = URL(fileURLWithPath: #filePath).resolvingSymlinksInPath()
        for _ in 0..<5 { sourceRoot.deleteLastPathComponent() }
        let sources = [
            "apps/apple/HealthMd/Shared/Export/AgentBridgeExportPlanning.swift",
            "apps/apple/HealthMd/Shared/Export/AgentBridgeExportAuthorityStore.swift",
            "apps/apple/HealthMd/Shared/Export/AgentBridgeRequestSettings.swift",
            "apps/apple/HealthMd/Shared/Core/HealthMdCoreRegistryAdapter.swift",
            "apps/apple/HealthMdTests/Export/AgentBridgeExportPlanningTests.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgeBoundary.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgeCodable.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgeDelegation.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgeDocuments.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgeIntent.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgeJSON.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgeModels.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgePaths.swift",
            "apps/apple/Packages/HealthMdConnectivity/Sources/HealthMdConnectionCore/AgentBridgeSemantics.swift",
            "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json"
        ]
        var hashes: [String: String] = [:]
        for source in sources { hashes[source] = AgentBridgeV4Codec.sha256(try Data(contentsOf: sourceRoot.appendingPathComponent(source))) }
        // CLOSED interoperability wrapper, NOT a wire envelope or issuer permission. DTO values
        // are actual service results. Hashing is native Swift; no Python verdict/fixture forwarding.
        let candidate: [String: Any] = [
            "discovery": try JSONSerialization.jsonObject(with: AgentBridgeV4Codec.encode(discovery)),
            "intent": try JSONSerialization.jsonObject(with: AgentBridgeV4Codec.encode(intent)),
            "plan": try JSONSerialization.jsonObject(with: AgentBridgeV4Codec.encode(plan)),
            "producer": "swift_actual_service", "producer_source_sha256": hashes,
            "source_base": "3bc392c823193ab04aeea4bb71e7cbcb5747b403"
        ]
        let bytes = try AgentBridgeV4Codec.canonicalize(JSONSerialization.data(withJSONObject: candidate, options: [.sortedKeys, .withoutEscapingSlashes]))
        try bytes.write(to: URL(fileURLWithPath: path), options: .atomic)
    }

    func testExactPlanRetryNeverRenewsAndChangedBytesCannotReplaceIssuedIdentity() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try rig.request(discovery: rig.discover())
        let bytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(request)))
        let first = try rig.service.handle(bytes, authenticatedPeer: rig.peer)
        let generation = try rig.store.snapshot().generation
        rig.clock.advance(seconds: 50)
        XCTAssertEqual(try rig.restartedService().handle(bytes, authenticatedPeer: rig.peer), first)
        XCTAssertEqual(try rig.store.snapshot().generation, generation)
        let whitespace = Data(" ".utf8) + bytes
        let rejection = try rig.service.handle(whitespace, authenticatedPeer: rig.peer)
        XCTAssertEqual(try error(rejection), .bindingChanged)
        for changed in [try rig.request(discovery: rig.discover(), metrics: ["heart_rate_min"]),
                        try rig.request(discovery: rig.discover(), destination: .init(bindingID: id(14), identitySHA256: digest("b"), revision: 2, hostInstallationID: rig.peer.peer.hostInstallationID)),
                        try rig.request(discovery: rig.discover(), dates: .allAvailable)] {
            try rig.expectError(.bindingChanged, request: .planRequest(changed))
        }
        rig.clock.advance(seconds: 550)
        let late = try rig.restartedService().handle(bytes, authenticatedPeer: rig.peer)
        XCTAssertEqual(try error(late), .planExpired)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 1)
    }

    func testUnknownWrongHostCopiedIssuerRevisionExpiryRevocationFailClosed() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let discovery = try rig.discover()
        let request = try rig.request(discovery: discovery)
        let foreignSource = try XCTUnwrap(UUID(uuidString: id(1).rawValue)), foreignHost = try XCTUnwrap(UUID(uuidString: id(99).rawValue))
        let foreign = try AgentBridgeExportAuthenticatedPeer(nativeSourceInstallationID: foreignSource, authenticatedHostInstallationID: foreignHost,
                                                            currentNativeSession: RevocableNativeSession(source: foreignSource, host: foreignHost))
        let wrong = try rig.service.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(request))), authenticatedPeer: foreign)
        XCTAssertEqual(try error(wrong), .bindingChanged)
        let foreignDiscovery = try rig.service.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .discoveryRequest(.init(requestID: id(100), peer: foreign.peer)))), authenticatedPeer: foreign)
        guard case .discovery(let filtered) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: foreignDiscovery).payload else { return XCTFail("discovery") }
        XCTAssertTrue(filtered.authorityReferences.isEmpty)
        let unknown = AgentBridgePlanRequest(authorityId: try id(90), authorityRevision: 1, capabilitySha256: discovery.capabilitySha256, hostAuthorityReference: request.hostAuthorityReference, intent: request.intent, requestId: try id(101))
        try rig.expectError(.approvalRequired, request: .planRequest(unknown))
        let stale = AgentBridgePlanRequest(authorityId: request.authorityId, authorityRevision: 2, capabilitySha256: discovery.capabilitySha256, hostAuthorityReference: request.hostAuthorityReference, intent: request.intent, requestId: request.requestId)
        try rig.expectError(.revisionConflict, request: .planRequest(stale))
        let copied = AgentBridgePlanRequest(authorityId: request.authorityId, authorityRevision: 1, capabilitySha256: discovery.capabilitySha256, hostAuthorityReference: discovery.authorityReferences[0], intent: request.intent, requestId: request.requestId)
        try rig.expectError(.approvalRequired, request: .planRequest(copied))
        try rig.store.revokeNativeDelegation(discovery.authorityReferences[0], expectedGeneration: rig.store.snapshot().generation, authorization: FakeNativeAuthorization())
        XCTAssertTrue(try rig.discover().authorityReferences.isEmpty)
        try rig.expectError(.approvalRequired, request: .planRequest(request))
        XCTAssertThrowsError(try rig.enroll(revision: 2)) // Revoked IDs are never recycled.
        let expired = try Rig(); defer { expired.cleanup() }; try expired.enroll(expires: "2026-03-08T23:59:59Z")
        XCTAssertTrue(try expired.discover().authorityReferences.isEmpty)
        try expired.expectError(.approvalRequired, request: .planRequest(expired.request(discovery: expired.discover())))
    }

    func testAllAvailableRemainsLogicalAndPastCompleteDaysResolveGregorianDST() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll(expires: "2026-03-09T00:04:00Z")
        let relative = try rig.makePlan(dates: .pastCompleteDays(days: 2, anchorDate: date("2026-03-09")))
        XCTAssertEqual(relative.predictedPaths.map(\.rawValue), ["2026/2026-03-07.json", "2026/2026-03-08.json"])
        XCTAssertEqual(relative.intent.calendarTimezone.rawValue, "America/Los_Angeles")
        XCTAssertEqual(relative.expiresAt.rawValue, "2026-03-09T00:04:00Z")
        let allRig = try Rig(); defer { allRig.cleanup() }; try allRig.enroll()
        let calls = allRig.reader.calls.count
        let all = try allRig.makePlan(dates: .allAvailable)
        XCTAssertEqual(all.resolvedDates, .allAvailable)
        XCTAssertEqual(all.pathPrediction, .templateOnlyAllAvailable)
        XCTAssertEqual(all.limitations.map(\.rawValue), ["healthkit_read_authorization_unobservable", "history_bounds_unresolved"])
        XCTAssertTrue(all.predictedPaths.isEmpty)
        XCTAssertEqual(allRig.reader.calls.count - calls, 7) // Issuance, pre-rename, post-sync and final-return configuration fences.
        XCTAssertEqual(allRig.reader.defaults.writes, 0)
        XCTAssertEqual(allRig.reader.defaults.reads, 0)
    }

    func testUnsupportedOutputsAndScopeRejectWithoutPreferenceReads() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let discovery = try rig.discover()
        let bad = output(format: .markdown)
        try rig.expectError(.unsupportedCapability, request: .planRequest(rig.request(discovery: discovery, policy: .explicit(bad))))
        try rig.expectError(.unsupportedMetric, request: .planRequest(rig.request(discovery: discovery, metrics: ["android.hrv_rmssd"])))
        try rig.expectError(.queryBudgetExceeded, request: .planRequest(rig.request(discovery: discovery, dates: .exact(.init(startDate: date("2025-01-01"), endDate: date("2026-03-08"))))))
        XCTAssertEqual(try rig.store.snapshot().plans.count, 0)
        XCTAssertEqual(rig.reader.defaults.reads, 0)
        XCTAssertEqual(rig.reader.defaults.writes, 0)
    }

    func testSavedAndProfileRevisionsOutputAndCapabilityChangesInvalidateApproval() throws {
        for policy in [AgentBridgeSettingsPolicy.savedDeviceSettings(expectedRevision: 7), .profile(profileID: try id(50), expectedRevision: 7)] {
            let rig = try Rig(withSaved: true); defer { rig.cleanup() }; try rig.enroll()
            let plan = try rig.makePlan(policy: policy)
            XCTAssertEqual(plan.effectiveSettings.folderTemplate, "saved/{year}")
            XCTAssertEqual(plan.revisions.count, 1)
            XCTAssertEqual(plan.revisions[0].revision, 7)
            XCTAssertEqual(plan.origins.filter { $0.pointer.hasPrefix("/effective_settings/") }.map(\.revision), Array(repeating: 7, count: outputPointers.count))
            XCTAssertEqual(rig.reader.defaults.writes, 0)
            let binding = AgentBridgeSemantics.binding(plan)
            try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                authorization: FakeNativeAuthorization(binding: binding))
            let request = AgentBridgeApprovalRequest(binding: binding, planId: plan.planId, requestId: try id(103))
            var snapshot = try XCTUnwrap(rig.reader.saved)
            snapshot.folderStructure = "changed/{year}"
            rig.reader.saved = snapshot // Same revision cannot silently change frozen output.
            try rig.expectError(.bindingChanged, request: .approvalRequest(request))
        }
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan()
        let request = AgentBridgeApprovalRequest(binding: AgentBridgeSemantics.binding(plan), planId: plan.planId, requestId: try id(103))
        rig.reader.protection = .unlockedNative
        try rig.expectError(.bindingChanged, request: .approvalRequest(request))
        rig.reader.protection = .locked
        rig.reader.available = ["steps", "heart_rate_min"] // Even unchanged catalog revision is caught by frozen native reuse.
        try rig.expectError(.bindingChanged, request: .approvalRequest(request))
    }

    func testConfigurationProtectionConsentEntitlementAndAvailabilityAreIndependent() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        rig.reader.grants = .unverified
        let plan = try rig.makePlan()
        XCTAssertEqual(plan.requiredActions.map(\.rawValue), ["grant_health_access"])
        XCTAssertEqual(try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: rig.peer).nativeConsent, .required)
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: AgentBridgeSemantics.binding(plan), approvalID: id(8), authenticatedPeer: rig.peer,
                                                               authorization: FakeNativeAuthorization(binding: AgentBridgeSemantics.binding(plan)))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        let entitlementRig = try Rig(); defer { entitlementRig.cleanup() }; try entitlementRig.enroll(); entitlementRig.reader.entitlement = .required
        let blocked = try entitlementRig.makePlan()
        XCTAssertEqual(blocked.requiredActions.map(\.rawValue), ["purchase_required"])
        XCTAssertThrowsError(try entitlementRig.service.storeNativeDecision(planID: blocked.planId, binding: AgentBridgeSemantics.binding(blocked), approvalID: id(8), authenticatedPeer: entitlementRig.peer,
                                                                          authorization: FakeNativeAuthorization(binding: AgentBridgeSemantics.binding(blocked)))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .entitlementRequired) }
    }

    func testDispatchRejectsUnknownQueryControlExecutionCancelAndResume() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        for name in ["unknown", "query_request", "control_request", "execute_request", "cancel_request", "resume_request"] {
            let bytes = Data((#"{"protocol_version":4,"type":""# + name + #"","payload":{"schema":"healthmd.agent_discovery_request","schema_version":1,"request_id":"00000000-0000-4000-8000-000000000064","peer":{"source_installation_id":"00000000-0000-4000-8000-000000000001","host_installation_id":"00000000-0000-4000-8000-000000000002","platform":"apple"}}}"#).utf8)
            XCTAssertThrowsError(try rig.service.handle(bytes, authenticatedPeer: rig.peer))
        }
        // A valid known non-planning DTO also rejects, not just mismatched/malformed discriminators.
        let cancel = try AgentBridgeCancel(approvalId: id(8), authorityId: id(7), jobId: id(10), peer: rig.peer.peer, requestSha256: digest("a"))
        XCTAssertThrowsError(try rig.send(.cancel(cancel))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .unsupportedCapability) }
        XCTAssertEqual(rig.reader.calls.count, 0)
        XCTAssertEqual(try rig.store.snapshot().generation, 0)
    }

    func testFreshInBoundsScopeAndOpaqueDestinationNeedNewIssuedPlanAndDecision() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let first = try rig.makePlan()
        let firstBinding = AgentBridgeSemantics.binding(first)
        try rig.service.storeNativeDecision(planID: first.planId, binding: firstBinding, approvalID: id(8), authenticatedPeer: rig.peer,
                                            authorization: FakeNativeAuthorization(binding: firstBinding))
        let changed = try rig.request(discovery: rig.discover(), metrics: ["heart_rate_min"],
                                      destination: .init(bindingID: id(14), identitySHA256: digest("b"), revision: 2, hostInstallationID: rig.peer.peer.hostInstallationID), requestID: id(102))
        let bytes = try rig.send(.planRequest(changed))
        guard case .plan(let second) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes).payload else { return XCTFail("fresh plan required") }
        XCTAssertNotEqual(second.planId, first.planId)
        XCTAssertNotEqual(second.scopeSha256, first.scopeSha256)
        XCTAssertEqual(second.intent.destination, changed.intent.destination) // Opaque bound host reference only, NOT verified host permission.
        XCTAssertEqual(second.authorityReferences.native, first.authorityReferences.native)
        try rig.expectError(.bindingChanged, request: .approvalRequest(.init(binding: firstBinding, planId: second.planId, requestId: id(103))))
        try rig.expectError(.approvalRequired, request: .approvalRequest(.init(binding: AgentBridgeSemantics.binding(second), planId: second.planId, requestId: id(103))))
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 1)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 2)
    }

    func testRevokedNativeSessionInvalidatesCopiedIDsOnEveryPublicServiceEntry() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        let copiedContext = rig.peer // Same immutable IDs AND same revocable session, not authority.
        let requestBytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .discoveryRequest(.init(requestID: id(100), peer: copiedContext.peer))))
        let before = try rig.store.snapshot().generation, configReads = rig.reader.calls.count
        rig.session.revoke()
        XCTAssertThrowsError(try rig.service.handle(requestBytes, authenticatedPeer: copiedContext)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: copiedContext,
                                                               authorization: FakeNativeAuthorization(binding: binding))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertThrowsError(try rig.service.nativeScopedAuthority(planID: plan.planId, authenticatedPeer: copiedContext)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertEqual(rig.reader.calls.count, configReads)
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
        XCTAssertEqual(copiedContext.peer, rig.peer.peer)
    }

    func testRevocationDuringActualConfigurationReadPreventsIssuedPlanPersistence() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try rig.request(discovery: rig.discover())
        rig.reader.beforeReturn = { rig.session.revoke() }
        XCTAssertThrowsError(try rig.send(.planRequest(request))) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertEqual(try rig.store.snapshot().plans.count, 0)
        XCTAssertEqual(rig.reader.calls, ["discovery", "discovery", "explicit"]) // Discovery return also rechecks configuration.
    }

    func testRevocationInsideNativeDecisionAdapterCannotCommitOrReturnApproval() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let plan = try rig.makePlan(), binding = AgentBridgeSemantics.binding(plan)
        let before = try rig.store.snapshot().generation
        let nativeDecision = FakeNativeAuthorization(binding: binding, afterAuthorization: { rig.session.revoke() })
        XCTAssertThrowsError(try rig.service.storeNativeDecision(planID: plan.planId, binding: binding, approvalID: id(8), authenticatedPeer: rig.peer,
                                                               authorization: nativeDecision)) { XCTAssertEqual($0 as? AgentBridgeValidationError, .permissionRequired) }
        XCTAssertEqual(try rig.store.snapshot().generation, before)
        XCTAssertEqual(try rig.store.snapshot().decisions.count, 0)
    }

    func testConcurrentActualHandlesSerializeDiscoveryAndExactPlanCAS() async throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let discoveryBytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer))))
        let discoveries = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<8 { group.addTask { @MainActor in try rig.service.handle(discoveryBytes, authenticatedPeer: rig.peer) } }
            var results: [Data] = []; for try await result in group { results.append(result) }; return results
        }
        XCTAssertEqual(Set(discoveries).count, 1)
        guard case .discovery(let discovery) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: discoveries[0]).payload else { return XCTFail("discovery") }
        let requestBytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(rig.request(discovery: discovery))))
        let replies = try await withThrowingTaskGroup(of: Data.self) { group in
            for _ in 0..<8 { group.addTask { @MainActor in try rig.service.handle(requestBytes, authenticatedPeer: rig.peer) } }
            var results: [Data] = []; for try await result in group { results.append(result) }; return results
        }
        XCTAssertEqual(Set(replies).count, 1)
        XCTAssertEqual(try rig.store.snapshot().generation, 2) // One grant, one issued-plan transaction.
        XCTAssertEqual(try rig.store.snapshot().plans.count, 1)
        let changed = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(rig.request(discovery: discovery, metrics: ["heart_rate_min"]))))
        let contested = try await withThrowingTaskGroup(of: Data.self) { group in
            for bytes in [requestBytes, changed] { group.addTask { @MainActor in try rig.service.handle(bytes, authenticatedPeer: rig.peer) } }
            var results: [Data] = []; for try await result in group { results.append(result) }; return results
        }
        XCTAssertEqual(contested.filter { $0 == replies[0] }.count, 1)
        XCTAssertEqual(try contested.filter { $0 != replies[0] }.map(error), [.bindingChanged])
        XCTAssertEqual(try rig.store.snapshot().generation, 2)
    }

    func testDiscoveryLifetimeAndRestartRequireFreshDiscoveryForNewPlansOnly() throws {
        let rig = try Rig(); defer { rig.cleanup() }; try rig.enroll()
        let request = try rig.request(discovery: rig.discover())
        let bytes = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .planRequest(request)))
        XCTAssertEqual(try error(rig.restartedService().handle(bytes, authenticatedPeer: rig.peer)), .planExpired)
        rig.clock.advance(seconds: 600)
        XCTAssertEqual(try error(rig.service.handle(bytes, authenticatedPeer: rig.peer)), .planExpired)
        XCTAssertEqual(try rig.store.snapshot().plans.count, 0)
    }

    func testRawDuplicateKeysInvalidUTF8AndBoundsRejectBeforeConfiguration() throws {
        let rig = try Rig(); defer { rig.cleanup() }
        let valid = try AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: .discoveryRequest(.init(requestID: id(100), peer: rig.peer.peer))))
        let text = String(decoding: valid, as: UTF8.self)
        for invalid in [Data(text.replacingOccurrences(of: "\"protocol_version\":4", with: "\"protocol_version\":4,\"protocol_\\u0076ersion\":4").utf8),
                        Data([0xff]) + valid,
                        Data(text.replacingOccurrences(of: "\"schema_version\":1", with: "\"schema_version\":true").utf8),
                        Data(repeating: 32, count: AgentBridgeV4Codec.maximumBytes + 1),
                        Data((String(repeating: "[", count: 26) + "0" + String(repeating: "]", count: 26)).utf8),
                        Data((#"{"a":""# + String(repeating: "x", count: 65_537) + #""}"#).utf8)] {
            XCTAssertThrowsError(try rig.service.handle(invalid, authenticatedPeer: rig.peer))
        }
        XCTAssertEqual(rig.reader.calls.count, 0)
    }

    // Independently worked 7,706-byte canonical v4 response. Updating installed policy support
    // changes only capability_sha256 and its derived plan_sha256; every other response byte is fixed.
    private static let tracerResponseSHA256 = "d072a33ec021b2d4de40a0564db00ce1f6d1690b48f1e72431aad1d90e5dda45"
}

private func id(_ n: Int) throws -> AgentBridgeUUID { try AgentBridgeUUID(String(format: "00000000-0000-4000-8000-%012x", n)) }
private func date(_ value: String) throws -> AgentBridgeDate { try AgentBridgeDate(value) }
private func digest(_ char: String) throws -> AgentBridgeDigest { try AgentBridgeDigest(String(repeating: char, count: 64)) }
private func error(_ bytes: Data) throws -> AgentBridgeErrorCode {
    guard case .error(let value) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes).payload else { throw AgentBridgeValidationError.invalidRequest }
    return value.code
}
private func output(format: AgentBridgeFormat = .json, folder: String = "{year}") -> AgentBridgeOutputSettings {
    .init(formats: [format], outputProfile: .appleV8, subfolder: "", folderTemplate: folder, filenameTemplate: "{date}", writeMode: .overwrite,
          presentation: .init(displayUnits: .metric, locale: "en-US", includeMetadata: true, groupByCategory: true,
                              frontmatter: .init(enabledFieldIDs: [], customFields: [], includeUnits: true, includeCaptureDiagnostics: false),
                              markdown: .init(style: .lists, customTemplate: "", placeholderIDs: [])),
          individualEntries: .init(enabled: false, metricIDs: [], folderTemplate: "", filenameTemplate: "{metric}-{date}", categoryFolders: false),
          dailyNotes: .init(enabled: false, only: false, folderTemplate: "", filenameTemplate: "{date}", createIfMissing: false, sectionIDs: []),
          packaging: .looseFiles, dictionary: .none)
}
private let outputPointers = [
    "/daily_notes/create_if_missing", "/daily_notes/enabled", "/daily_notes/filename_template", "/daily_notes/folder_template", "/daily_notes/only", "/daily_notes/section_ids", "/dictionary/type", "/filename_template", "/folder_template", "/formats",
    "/individual_entries/category_folders", "/individual_entries/enabled", "/individual_entries/filename_template", "/individual_entries/folder_template", "/individual_entries/metric_ids", "/output_profile", "/packaging/type", "/presentation/display_units", "/presentation/frontmatter/custom_fields", "/presentation/frontmatter/enabled_field_ids", "/presentation/frontmatter/include_capture_diagnostics", "/presentation/frontmatter/include_units", "/presentation/group_by_category", "/presentation/include_metadata", "/presentation/locale", "/presentation/machine_units", "/presentation/markdown/custom_template", "/presentation/markdown/placeholder_ids", "/presentation/markdown/style", "/subfolder", "/write_mode"
]
private let capturePointers = ["/capture_scope/compatibility_detail", "/capture_scope/native_archive/type", "/capture_scope/selection/all_metrics", "/capture_scope/selection/category_ids", "/capture_scope/selection/metric_ids", "/capture_scope/selection/provider_ids", "/capture_scope/selection/source_ids"]

nonisolated private final class PublicationTaskCancellation: @unchecked Sendable {
    private let lock = NSLock()
    private var task: Task<AgentBridgeNativeCatalogPublication, Error>?
    private var didRequest = false
    var requested: Bool { lock.withLock { didRequest } }
    func install(_ value: Task<AgentBridgeNativeCatalogPublication, Error>) {
        lock.withLock { task = value; if didRequest { value.cancel() } }
    }
    func request() { lock.withLock { didRequest = true; task?.cancel() } }
}

nonisolated private final class RevocableNativeSession: AgentBridgeExportNativeSessionChecking, @unchecked Sendable {
    private let lock = NSLock()
    private let authenticatedPeer: AgentBridgePeer
    private var revoked = false
    private var count = 0
    private var observer: ((Int) -> Void)?
    var checks: Int { lock.lock(); defer { lock.unlock() }; return count }
    func observeChecks(_ callback: @escaping (Int) -> Void) { lock.lock(); defer { lock.unlock() }; observer = callback }
    init(source: UUID, host: UUID) throws {
        authenticatedPeer = try .init(sourceInstallationID: AgentBridgeUUID(source.uuidString.lowercased()), hostInstallationID: AgentBridgeUUID(host.uuidString.lowercased()), platform: .apple)
    }
    func requireCurrent(peer: AgentBridgePeer) throws {
        lock.lock(); count += 1; let check = count, callback = observer; lock.unlock()
        callback?(check)
        lock.lock(); defer { lock.unlock() }
        guard !revoked, peer == authenticatedPeer else { throw AgentBridgeValidationError.permissionRequired }
    }
    func revoke() { lock.lock(); defer { lock.unlock() }; revoked = true }
}

nonisolated private final class AdvancingPlanningClock: AgentBridgeExportClock, @unchecked Sendable {
    private let lock = NSLock()
    private var value = ISO8601DateFormatter().date(from: "2026-03-09T00:00:00Z")!
    private var afterNextSample: TimeInterval?
    func now() -> Date {
        lock.lock(); defer { lock.unlock() }
        let sampled = value
        if let delay = afterNextSample { value = value.addingTimeInterval(delay); afterNextSample = nil }
        return sampled
    }
    func advanceAfterNextSample(seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; afterNextSample = seconds }
    func advance(seconds: TimeInterval) { lock.lock(); defer { lock.unlock() }; value = value.addingTimeInterval(seconds) }
}

nonisolated private final class FakeProtectedKeys: AgentBridgeExportProtectedKeyReading, @unchecked Sendable {
    let key: SymmetricKey?
    private let lock = NSLock()
    private var count = 0
    private var nextLoad: (() -> Void)?
    var loads: Int { lock.lock(); defer { lock.unlock() }; return count }
    func onNextLoad(_ callback: @escaping () -> Void) { lock.lock(); defer { lock.unlock() }; nextLoad = callback }
    init(key: SymmetricKey? = SymmetricKey(data: Data(repeating: 9, count: 32))) { self.key = key }
    func loadExistingExportAuthorityKey() throws -> SymmetricKey? {
        lock.lock(); count += 1; let callback = nextLoad; nextLoad = nil; lock.unlock()
        callback?()
        return key
    }
}
nonisolated private final class LiveExactApprovalAuthorization: AgentBridgeExportNativeAuthorizing {
    private let planID: AgentBridgeUUID
    private let binding: AgentBridgeBinding
    var allowed = true
    var checks = 0
    var onCheck: ((Int) -> Void)?
    init(planID: AgentBridgeUUID, binding: AgentBridgeBinding) { self.planID = planID; self.binding = binding }
    func requireNativeAuthorization(for action: AgentBridgeExportNativeAction) throws {
        guard allowed, case .decideExport(let id, let candidate) = action, id == planID, candidate == binding else {
            throw AgentBridgeValidationError.approvalRequired
        }
        checks += 1
        onCheck?(checks)
    }
}
nonisolated private struct FakeNativeAuthorization: AgentBridgeExportNativeAuthorizing {
    var deny = false
    var binding: AgentBridgeBinding? = nil
    var afterAuthorization: (() -> Void)? = nil
    func requireNativeAuthorization(for action: AgentBridgeExportNativeAction) throws {
        guard !deny else { throw AgentBridgeValidationError.permissionRequired }
        if case .decideExport(_, let candidate) = action, candidate != binding { throw AgentBridgeValidationError.approvalRequired }
        afterAuthorization?()
    }
}
nonisolated private final class PublicationProbe: AgentBridgeExportPublicationObserving {
    var onPrepared: ((AgentBridgeExportAuthoritySnapshot) throws -> Void)?
    var onPublished: ((AgentBridgeExportAuthoritySnapshot) throws -> Void)?
    func prepared(_ state: AgentBridgeExportAuthoritySnapshot) throws { try onPrepared?(state) }
    func published(_ state: AgentBridgeExportAuthoritySnapshot) throws { try onPublished?(state) }
}

@MainActor
private final class ConfigurationProbe: AgentBridgeExportPlanningConfigurationReading {
    let suite = "AgentBridgeExportPlanningTests." + UUID().uuidString
    let defaults: AgentBridgeRequestSettingsDefaultsProbe
    var calls: [String] = []
    var beforeReturn: (() -> Void)?
    var available: Set<String> = ["steps", "heart_rate_avg", "heart_rate_min", "heart_rate_max", "resting_heart_rate", "hrv"]
    var catalogRevision: Int64 = 3
    var saved: ExportSettingsSnapshot?
    var savedRevision: Int64 = 7
    var protection: AgentBridgeDiscoveryConfigurationProtection = .locked
    var grants: AgentBridgeDiscoveryNativeGrants = .satisfied
    var entitlement: AgentBridgeDiscoveryEntitlement = .satisfied
    init() throws { defaults = try XCTUnwrap(AgentBridgeRequestSettingsDefaultsProbe(suiteName: suite)); defaults.reads = 0; defaults.writes = 0 }
    var inputs: AgentBridgeRequestSettingsInputs {
        get throws {
            let snapshot = saved.map { AgentBridgeRequestSettingsSnapshot(revision: savedRevision, settings: $0) }
            return try .init(catalog: .init(registry: HealthMdCoreRegistryAdapter.appleSnapshot(), availableNativeMetricIDs: available, revision: catalogRevision),
                             savedDevice: snapshot, profiles: snapshot.map { [.init(profileID: try! id(50), snapshot: $0, executionBlocked: false)] } ?? [])
        }
    }
    func readConfiguration(for peer: AgentBridgeExportAuthenticatedPeer, policy: AgentBridgeSettingsPolicy?, catalogPublication: AgentBridgeNativeCatalogPublication?) throws -> AgentBridgeExportPlanningConfiguration {
        let kind: String
        switch policy { case nil: kind = "discovery"; case .explicit: kind = "explicit"; case .savedDeviceSettings: kind = "saved"; case .profile: kind = "profile" }
        calls.append(kind)
        if kind == "saved" || kind == "profile" { _ = defaults.string(forKey: "sentinel") }
        beforeReturn?()
        let selectedSaved: AgentBridgeRequestSettingsSnapshot?
        let selectedProfiles: [AgentBridgeRequestSettingsProfile]
        switch policy {
        case .savedDeviceSettings:
            selectedSaved = saved.map { .init(revision: savedRevision, settings: $0) }
            selectedProfiles = []
        case .profile(let requestedID, _):
            selectedSaved = nil
            let knownID = try id(50)
            selectedProfiles = saved.map {
                requestedID == knownID ? [.init(profileID: requestedID, snapshot: .init(revision: savedRevision, settings: $0), executionBlocked: false)] : []
            } ?? []
        default:
            selectedSaved = nil
            selectedProfiles = []
        }
        let selectedInputs = try AgentBridgeRequestSettingsInputs(
            catalog: .init(registry: HealthMdCoreRegistryAdapter.appleSnapshot(), availableNativeMetricIDs: available, revision: catalogRevision),
            savedDevice: selectedSaved, profiles: selectedProfiles)
        return try .init(inputs: selectedInputs, deviceSettingsObjectID: id(5), sourceCalendarTimezone: AgentBridgeZone("America/Los_Angeles"), configurationProtection: protection,
                         nativeGrants: grants, entitlement: entitlement, foregroundAvailable: true, protectedDataAvailable: true)
    }
}
/// Explicit synthetic OS dependency: actual descriptors/inodes, private files, signing and
/// recovery remain production code. This does not qualify physical data protection.
@MainActor
private final class FakeNativeCaptureProtection: AgentBridgeNativeCaptureProtecting {
    var denied = false
    var onRequire: ((Int32) throws -> Void)?
    private var protected: Set<String> = []
    func applyCompleteProtection(_ fd: Int32) throws {
        guard !denied else { throw AgentBridgeValidationError.permissionRequired }
        protected.insert(try identity(fd))
    }
    func requireCompleteProtection(_ fd: Int32) throws {
        guard !denied, protected.contains(try identity(fd)) else { throw AgentBridgeValidationError.permissionRequired }
        try onRequire?(fd)
    }
    private func identity(_ fd: Int32) throws -> String {
        var info = stat()
        guard fstat(fd, &info) == 0 else { throw AgentBridgeValidationError.permissionRequired }
        return "\(info.st_dev):\(info.st_ino)"
    }
}

@MainActor
private final class Rig {
    let parent: URL
    let directory: URL
    let keys = FakeProtectedKeys()
    let captureProtection = FakeNativeCaptureProtection()
    let publication = PublicationProbe()
    let reader: ConfigurationProbe
    let store: AgentBridgeExportAuthorityStore
    let service: AgentBridgeExportPlanningService
    let peer: AgentBridgeExportAuthenticatedPeer
    let session: RevocableNativeSession
    let clock = AdvancingPlanningClock()
    var now: Date { clock.now() }
    var calendar: Calendar { var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: "America/Los_Angeles")!; return c }
    init(withSaved: Bool = false) throws {
        parent = URL(fileURLWithPath: "/private/tmp").appendingPathComponent("healthmd-native-planning-test-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: parent, withIntermediateDirectories: false, attributes: [.posixPermissions: 0o700])
        directory = parent.appendingPathComponent("authority")
        let source = try XCTUnwrap(UUID(uuidString: id(1).rawValue)), host = try XCTUnwrap(UUID(uuidString: id(2).rawValue))
        session = try RevocableNativeSession(source: source, host: host)
        peer = try .init(nativeSourceInstallationID: source, authenticatedHostInstallationID: host, currentNativeSession: session)
        reader = try ConfigurationProbe()
        store = try AgentBridgeExportAuthorityStore.createPrivateStore(at: directory, protectedKeys: keys, authorization: FakeNativeAuthorization(), publication: publication)
        var nextPlanID = 6
        service = AgentBridgeExportPlanningService(store: store, configuration: reader, clock: clock, newPlanID: {
            let chosen = nextPlanID; nextPlanID += 10; return try id(chosen)
        })
        if withSaved {
            let request = try intent(policy: .explicit(output(folder: "saved/{year}")))
            reader.saved = try AgentBridgeRequestSettingsResolver.resolve(request, inputs: reader.inputs, clock: now, calendar: calendar).settings
            reader.defaults.set("synthetic", forKey: "sentinel"); reader.defaults.reads = 0; reader.defaults.writes = 0
        }
    }
    func cleanup() { reader.defaults.removePersistentDomain(forName: reader.suite); try? FileManager.default.removeItem(at: parent) }
    func grant(revision: Int64 = 1, expires: String = "2026-03-09T01:00:00Z") throws -> AgentBridgeExportDelegation {
        try .init(authorityID: id(7), issuer: .nativeSource, grantRevision: revision, peer: peer.peer, rights: [.discover, .exportExecute, .plan], expiresAt: AgentBridgeUTC(expires),
                  bounds: .init(products: [.generatedFiles], projectionDetails: [], projectionObjectIDs: [], projectionFieldIDs: [],
                                metricIDs: ["heart_rate_avg", "heart_rate_max", "heart_rate_min", "hrv", "resting_heart_rate", "steps"].map(AgentBridgeID.init),
                                calendarTimezones: [AgentBridgeZone("America/Los_Angeles"), AgentBridgeZone("UTC")], datePolicy: .authorizedHistory(maxDays: 366, allowAllAvailable: true),
                                formats: [.json], outputProfiles: [.appleV8], writeModes: [.overwrite], compatibilityDetail: [.summary], nativeArchiveProducts: [.none], destinationPolicy: .authenticatedHostBindings))
    }
    func enroll(revision: Int64 = 1, expires: String = "2026-03-09T01:00:00Z") throws {
        try store.storeNativeDelegation(grant(revision: revision, expires: expires), expectedGeneration: store.snapshot().generation, authorization: FakeNativeAuthorization())
    }
    func intent(metrics: [String] = ["steps"], dates: AgentBridgeDates? = nil, destination: AgentBridgeDestination? = nil, policy: AgentBridgeSettingsPolicy? = nil) throws -> AgentBridgeGeneratedIntent {
        try .init(intentID: id(4), peer: peer.peer, destination: destination ?? .init(bindingID: id(3), identitySHA256: digest("1"), revision: 1, hostInstallationID: peer.peer.hostInstallationID),
                  dates: dates ?? .exact(.init(startDate: date("2026-03-07"), endDate: date("2026-03-08"))), calendarTimezone: AgentBridgeZone("America/Los_Angeles"),
                  captureScope: .init(selection: .init(metricIDs: metrics.map(AgentBridgeID.init).sorted { $0.rawValue < $1.rawValue }, categoryIDs: [], sourceIDs: [AgentBridgeID("apple_health")], providerIDs: [], allMetrics: false), compatibilityDetail: .summary, nativeArchive: .none),
                  settingsPolicy: policy ?? .explicit(output()))
    }
    func discover() throws -> AgentBridgeDiscovery {
        let bytes = try send(.discoveryRequest(.init(requestID: id(100), peer: peer.peer)))
        guard case .discovery(let value) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes).payload else { throw AgentBridgeValidationError.invalidRequest }
        return value
    }
    func request(discovery: AgentBridgeDiscovery, metrics: [String] = ["steps"], dates: AgentBridgeDates? = nil, destination: AgentBridgeDestination? = nil, policy: AgentBridgeSettingsPolicy? = nil, requestID: AgentBridgeUUID? = nil) throws -> AgentBridgePlanRequest {
        try .init(authorityId: id(7), authorityRevision: 1, capabilitySha256: discovery.capabilitySha256,
                  hostAuthorityReference: .init(authorityId: id(13), grantRevision: 1, grantSha256: digest("2"), issuer: .authorizedHost),
                  intent: intent(metrics: metrics, dates: dates, destination: destination, policy: policy), requestId: requestID ?? id(101))
    }
    func makePlan(dates: AgentBridgeDates? = nil, policy: AgentBridgeSettingsPolicy? = nil) throws -> AgentBridgePlan {
        let bytes = try send(.planRequest(request(discovery: discover(), dates: dates, policy: policy)))
        guard case .plan(let value) = try AgentBridgeV4Codec.decode(AgentBridgeEnvelope.self, from: bytes).payload else { throw AgentBridgeValidationError.invalidRequest }
        return value
    }
    func unissuedBinding(discovery: AgentBridgeDiscovery) throws -> AgentBridgeBinding {
        try .init(authorityReferences: .init(host: .init(authorityId: id(13), grantRevision: 1, grantSha256: digest("2"), issuer: .authorizedHost), native: grant().reference()),
                  capabilitySha256: discovery.capabilitySha256, destination: intent().destination, expiresAt: AgentBridgeUTC("2026-03-09T00:10:00Z"), peer: peer.peer,
                  planSha256: digest("0"), revisions: [], scopeSha256: digest("0"), settingsSha256: digest("0"))
    }
    func send(_ document: AgentBridgeDocument) throws -> Data { try service.handle(AgentBridgeV4Codec.encode(AgentBridgeEnvelope(payload: document)), authenticatedPeer: peer) }
    func expectError(_ wanted: AgentBridgeErrorCode, request: AgentBridgeDocument) throws { XCTAssertEqual(try error(send(request)), wanted) }
    func restartedService() throws -> AgentBridgeExportPlanningService { AgentBridgeExportPlanningService(store: try .init(existingDirectory: directory, protectedKeys: keys), configuration: reader, clock: clock, newPlanID: { throw AgentBridgeValidationError.invalidRequest }) }
}

/// Actual channel encryption/gates with a synthetic native write boundary. No pairing or consent proof.
@MainActor private final class NativeTransferWriteState { var count = 0 }
@MainActor private final class NativeTransferStopState { var nextReceive = 0; var received = false }

nonisolated private final class NativePlanningResponsePackets: DirectGuardedPacketTransport, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: [ManualIPSyncPacket] = []
    private var inbound: [ManualIPSyncPacket]
    private var receives = 0
    private let beforeReceive: @concurrent @Sendable () async throws -> Void
    private let beforeWrite: @concurrent @Sendable () async throws -> Void
    private let afterWrite: @concurrent @Sendable () async throws -> Void
    var receiveCount: Int { lock.withLock { receives } }
    var packets: [ManualIPSyncPacket] { lock.withLock { stored } }
    init(beforeWrite: @escaping @concurrent @Sendable () async throws -> Void = {}, afterWrite: @escaping @concurrent @Sendable () async throws -> Void = {},
         inbound: [ManualIPSyncPacket] = [], beforeReceive: @escaping @concurrent @Sendable () async throws -> Void = {}) {
        self.beforeWrite = beforeWrite; self.afterWrite = afterWrite; self.inbound = inbound; self.beforeReceive = beforeReceive
    }
    @concurrent func sendGuarded(_ packet: ManualIPSyncPacket, authorize: @escaping @concurrent @Sendable () async throws -> Void) async throws {
        try await beforeWrite()
        try await authorize()
        lock.withLock { stored.append(packet) }
        try await afterWrite()
        try await authorize()
    }
    @concurrent func send(_ packet: ManualIPSyncPacket) async throws { throw AgentBridgeValidationError.unsupportedCapability }
    @concurrent func receive() async throws -> ManualIPSyncPacket {
        try await beforeReceive()
        return try lock.withLock {
            guard !inbound.isEmpty else { throw DirectChannelError.connectionClosed }
            receives += 1
            return inbound.removeFirst()
        }
    }
    func cancel() {}
}

#if canImport(HealthMd)
nonisolated private struct BridgeRenderTamperCore: AppleLooseDailyCoreExecuting {
    let mode: String
    var afterRender: (@MainActor @Sendable () -> Void)? = nil
    private var actual: SystemAppleLooseDailyCoreExecutor { .init(profile: .appleHealthDataV8) }
    func loadContext() async throws -> AppleLooseDailyCoreContext {
        if mode == "registry" { return try await SystemAppleLooseDailyCoreExecutor().loadContext() }
        if mode == "forbid" { XCTFail("Retained artifact must not consult current core"); throw AgentBridgeNativeRenderFailure.renderFailed }
        var result = try await actual.loadContext()
        if mode == "engine-changed" {
            var info = result.buildInfo; info.coreSourceRevision += "-other"
            result = .init(buildInfo: info, registry: result.registry)
        }
        return result
    }
    func processSemantic(configuration: Data, batches: [Data]) async throws -> Data {
        try await actual.processSemantic(configuration: configuration, batches: batches)
    }
    func render(configuration: Data, semanticResult: Data, batches: [Data]) async throws -> CoreArtifactPlan {
        var plan = try await actual.render(configuration: configuration, semanticResult: semanticResult, batches: batches)
        switch mode {
        case "profile": plan.profile = .appleHealthDataV10
        case "path": plan.items[0].relativePath = "unapproved.json"
        case "digest": plan.items[0].sha256 = String(repeating: "0", count: 64)
        case "ids": plan.sessionId = "other-session"
        case "extra": plan.items.append(plan.items[0])
        case "body":
            var json = try JSONSerialization.jsonObject(with: plan.items[0].content) as! [String: Any]
            json["schema_version"] = 10
            let bytes = try JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])
            plan.items[0].content = bytes; plan.items[0].byteCount = UInt64(bytes.count)
            plan.items[0].sha256 = NativeExportArtifact.sha256(of: bytes)
            plan.items[0].artifactId = NativeExportArtifactPlan.artifactID(requestID: plan.requestId, sessionID: plan.sessionId,
                profile: plan.profile, relativePath: plan.items[0].relativePath, mediaType: plan.items[0].mediaType,
                writeMode: plan.items[0].writeMode, contentSHA256: plan.items[0].sha256)
            plan.totalByteCount = UInt64(bytes.count)
        case "cancel": withUnsafeCurrentTask { $0?.cancel() }
        default: break
        }
        await afterRender?()
        return plan
    }
}
#endif
