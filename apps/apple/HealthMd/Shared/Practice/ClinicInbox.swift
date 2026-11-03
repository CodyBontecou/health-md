import Foundation
import Observation

struct ClinicReviewFact: Identifiable, Equatable {
    let label: String
    let value: String
    var id: String { label }
}
enum ClinicInboxError: Error { case unavailable }
enum ClinicInboxAccess: String { case clinicCovered, consumer, unavailable }
struct ClinicInboxReview: Identifiable, Equatable {
    let id: String
    let digest: String
    let clinic: String
    let profile: String
    let destination: String
    let metrics: [String]
    /// Complete display facts derived from the same local native snapshot used to compute digest.
    let options: [ClinicReviewFact]
    let schedule: String
    let expiresAt: Date
    let access: ClinicInboxAccess
}
enum ClinicInboxStatus: String, CaseIterable { case requested, running, uploaded, processed, failed, cancelled, expired, revoked }
struct ClinicInboxRefresh: Identifiable, Equatable {
    let id: String
    let connectionID: String
    let clinic: String
    let profile: String
    let destination: String
    let scope: String
    let metrics: [String]
    var status: ClinicInboxStatus
    var receiptPending: Bool = false
    var sharingActive: Bool = true
}
struct ClinicInboxSnapshot: Equatable {
    var synthetic = false
    var reviews: [ClinicInboxReview] = []
    var refreshes: [ClinicInboxRefresh] = []
}

/// Internal presentation port, NOT a SetClinic wire API. Implementations must bind review facts/digest
/// to ClinicNativeOnboarding.preview/accept and use ClinicForegroundRefresh plus trusted native gates.
/// No account, endpoint, credential or production transport is configured by this protocol.
@MainActor
protocol ClinicInboxTransport: AnyObject {
    /// Non-secret account/session generation key, never a token or Authorization value.
    var sessionID: String? { get }
    func load() async throws -> ClinicInboxSnapshot
    func applySetup(id: String, reviewedDigest: String) async throws
    func export(id: String) async throws
    func reportReceipt(id: String) async throws
    /// Commit cancellation/revocation to trusted native authority before returning. Queue any
    /// remote acknowledgment separately; a remote round trip must not defer stopping local work.
    func cancel(id: String) async throws
    func revoke(connectionID: String) async throws
}
@MainActor
final class UnavailableClinicInboxTransport: ClinicInboxTransport {
    var sessionID: String? { nil }
    func load() async throws -> ClinicInboxSnapshot { throw ClinicInboxError.unavailable }
    func applySetup(id: String, reviewedDigest: String) async throws { throw ClinicInboxError.unavailable }
    func export(id: String) async throws { throw ClinicInboxError.unavailable }
    func reportReceipt(id: String) async throws { throw ClinicInboxError.unavailable }
    func cancel(id: String) async throws { throw ClinicInboxError.unavailable }
    func revoke(connectionID: String) async throws { throw ClinicInboxError.unavailable }
}

/// Owns action state across the inbox and review sheet. No export runs on load, polling or navigation.
@Observable @MainActor
final class ClinicInboxModel {
    private(set) var snapshot = ClinicInboxSnapshot()
    private(set) var review: ClinicInboxReview?
    private(set) var loading = false
    private(set) var busy = false
    private(set) var controls: Set<String> = []
    private(set) var unavailable = false
    private(set) var error = false
    var consent = false
    private let transport: any ClinicInboxTransport
    private let enabled: () -> Bool
    private let now: () -> Date
    private var loadedSession: String?
    private var generation = 0
    private var mutationEpoch = 0
    private var cancelledRequests: Set<String> = []
    private var revokedConnections: Set<String> = []
    init(transport: any ClinicInboxTransport = UnavailableClinicInboxTransport(),
         enabled: @escaping () -> Bool = { PracticeFeaturePolicy.current.isEnabled }, now: @escaping () -> Date = Date.init) {
        self.transport = transport; self.enabled = enabled; self.now = now
    }
    var canApply: Bool {
        guard let review else { return false }
        return consent && !busy && controls.isEmpty && !error && review.expiresAt > now() && !review.metrics.isEmpty && !review.digest.isEmpty
            && loadedSession != nil && loadedSession == transport.sessionID && enabled()
    }
    func clear() {
        generation += 1; snapshot = ClinicInboxSnapshot(); review = nil; consent = false
        loadedSession = nil; loading = false; busy = false; controls = []; error = false
        cancelledRequests = []; revokedConnections = []; mutationEpoch += 1
    }
    func dismissReview() { review = nil; consent = false }
    func openReview(_ id: String) {
        guard !busy, controls.isEmpty else { return }
        guard loadedSession == transport.sessionID, loadedSession != nil else { clear(); return }
        review = snapshot.reviews.first { $0.id == id && $0.expiresAt > now() }; consent = false
    }
    func load() async {
        guard !busy, controls.isEmpty else { return }
        // Keep confirmed control fences across same-account reloads, including stale service reads.
        let sameSession = loadedSession != nil && loadedSession == transport.sessionID
        let cancellations = cancelledRequests; let revocations = revokedConnections
        clear(); unavailable = false
        if sameSession { cancelledRequests = cancellations; revokedConnections = revocations }
        guard enabled(), let session = transport.sessionID else { unavailable = true; return }
        let ticket = generation; loading = true
        do {
            let result = try await transport.load()
            guard ticket == generation else { return }
            guard session == transport.sessionID, !Task.isCancelled else { clear(); return }
            publish(result); loadedSession = session; loading = false
        } catch is CancellationError { if ticket == generation { clear() } }
        catch { if ticket == generation { clear(); self.error = true } }
    }
    @discardableResult func apply() async -> Bool {
        guard loadedSession != nil, loadedSession == transport.sessionID else { clear(); return false }
        guard canApply, let selected = review else { return false }
        return await perform { try await self.transport.applySetup(id: selected.id, reviewedDigest: selected.digest) }
    }
    func export(_ id: String) async {
        guard snapshot.refreshes.contains(where: { $0.id == id && $0.status == .requested && $0.sharingActive }) else { return }
        _ = await perform { try await self.transport.export(id: id) }
    }
    func reportReceipt(_ id: String) async {
        guard snapshot.refreshes.contains(where: { $0.id == id && $0.status == .uploaded && $0.receiptPending }) else { return }
        _ = await perform { try await self.transport.reportReceipt(id: id) }
    }
    func cancel(_ id: String) async {
        guard snapshot.refreshes.contains(where: { $0.id == id && [.requested, .running].contains($0.status) }) else { return }
        await control(key: "cancel:" + id, cancelID: id) { try await self.transport.cancel(id: id) }
    }
    func revoke(_ connectionID: String) async {
        guard snapshot.refreshes.contains(where: { $0.connectionID == connectionID && $0.sharingActive }) else { return }
        await control(key: "revoke:" + connectionID, connectionID: connectionID) { try await self.transport.revoke(connectionID: connectionID) }
    }
    private func perform(_ operation: @MainActor () async throws -> Void) async -> Bool {
        guard !busy, !error, controls.isEmpty else { return false }
        guard enabled(), let session = loadedSession, session == transport.sessionID else { clear(); return false }
        let ticket = generation; let epoch = mutationEpoch; busy = true; error = false
        do {
            try await operation()
            guard ticket == generation else { return false }
            guard session == transport.sessionID else { clear(); return false }
            if Task.isCancelled { busy = false; if epoch == mutationEpoch { clear() }; return false }
            let result = try await transport.load()
            guard ticket == generation else { return false }
            guard session == transport.sessionID else { clear(); return false }
            if Task.isCancelled { busy = false; if epoch == mutationEpoch { clear() }; return false }
            if epoch == mutationEpoch { publish(result) }; busy = false; dismissReview(); return true
        } catch is CancellationError {
            if ticket == generation { busy = false; if epoch == mutationEpoch || session != transport.sessionID { clear() } }
            return false
        }
        catch {
            guard ticket == generation else { return false }
            if session == transport.sessionID { busy = false; if epoch == mutationEpoch { self.error = true } }
            else { clear() }
            return false
        }
    }
    /// Control requests never wait for export's busy flag. Their transport updates the native
    /// consent/request authority so the export check stops the next publication or retry.
    private func control(key: String, cancelID: String? = nil, connectionID: String? = nil,
                         operation: @MainActor () async throws -> Void) async {
        guard !controls.contains(key) else { return }
        guard enabled(), let session = loadedSession, session == transport.sessionID else { clear(); return }
        let ticket = generation; mutationEpoch += 1; let epoch = mutationEpoch
        controls.insert(key); error = false
        defer { if ticket == generation { controls.remove(key) } }
        do {
            try await operation()
            guard ticket == generation else { return }
            guard session == transport.sessionID else { clear(); return }
            if let cancelID { cancelledRequests.insert(cancelID) }
            if let connectionID { revokedConnections.insert(connectionID) }
            publish(snapshot)
            let result = try await transport.load()
            guard ticket == generation else { return }
            guard session == transport.sessionID else { clear(); return }
            if epoch == mutationEpoch { publish(result) }
        } catch {
            if ticket == generation {
                if session == transport.sessionID { self.error = true } else { clear() }
            }
        }
    }
    private func publish(_ value: ClinicInboxSnapshot) {
        var reconciled = value
        for index in reconciled.refreshes.indices {
            if cancelledRequests.contains(reconciled.refreshes[index].id),
               [.requested, .running].contains(reconciled.refreshes[index].status) { reconciled.refreshes[index].status = .cancelled }
            if revokedConnections.contains(reconciled.refreshes[index].connectionID) {
                reconciled.refreshes[index].sharingActive = false
                if [.requested, .running].contains(reconciled.refreshes[index].status) { reconciled.refreshes[index].status = .revoked }
            }
        }
        snapshot = reconciled
    }
}

/// Explicitly injected fixture only; no network, permission, purchase or Health reads.
@MainActor
final class SyntheticClinicInboxTransport: ClinicInboxTransport {
    var sessionID: String? = "session_synthetic"
    var value: ClinicInboxSnapshot
    private(set) var exports = 0
    private(set) var receiptsReported = 0
    init(now: Date = Date()) {
        value = ClinicInboxSnapshot(synthetic: true, reviews: [ClinicInboxReview(id: "setup_synthetic", digest: "digest_synthetic",
            clinic: "Synthetic clinic", profile: "Clinic profile", destination: "Synthetic clinic endpoint",
            metrics: ["Steps", "Average heart rate"], options: [ClinicReviewFact(label: "Formats", value: "JSON, CSV"),
            ClinicReviewFact(label: "Detail", value: "Summary"), ClinicReviewFact(label: "Write mode", value: "Update")],
            schedule: "Daily at 12:00 UTC · starts paused", expiresAt: now.addingTimeInterval(900), access: .clinicCovered)],
            refreshes: [ClinicInboxRefresh(id: "refresh_synthetic", connectionID: "connection_synthetic", clinic: "Synthetic clinic",
            profile: "Clinic profile", destination: "Synthetic clinic endpoint", scope: "1–2 November 2026 · UTC",
            metrics: ["Steps", "Average heart rate"], status: .requested)])
    }
    func load() async throws -> ClinicInboxSnapshot { guard sessionID != nil else { throw ClinicInboxError.unavailable }; return value }
    func applySetup(id: String, reviewedDigest: String) async throws {
        guard value.reviews.contains(where: { $0.id == id && $0.digest == reviewedDigest }) else { throw ClinicInboxError.unavailable }
        value.reviews.removeAll { $0.id == id }
    }
    func export(id: String) async throws { exports += 1; update(id) { $0.status = .uploaded; $0.receiptPending = true } }
    func reportReceipt(id: String) async throws { receiptsReported += 1; update(id) { $0.receiptPending = false } }
    func cancel(id: String) async throws { update(id) { $0.status = .cancelled } }
    func revoke(connectionID: String) async throws {
        for index in value.refreshes.indices where value.refreshes[index].connectionID == connectionID {
            value.refreshes[index].sharingActive = false
            if [.requested, .running].contains(value.refreshes[index].status) { value.refreshes[index].status = .revoked }
        }
    }
    private func update(_ id: String, change: (inout ClinicInboxRefresh) -> Void) {
        if let index = value.refreshes.firstIndex(where: { $0.id == id }) { change(&value.refreshes[index]) }
    }
}
