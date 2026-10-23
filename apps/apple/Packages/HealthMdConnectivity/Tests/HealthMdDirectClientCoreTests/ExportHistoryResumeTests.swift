import Foundation
import HealthMdConnectionCore
import XCTest
@testable import HealthMdDirectClientCore

final class ExportHistoryResumeTests: XCTestCase {
    private struct Fixture: Decodable {
        let request: DirectExportRequest
        let accepted: DirectExportAccepted
        let session: DirectTransferSession
    }

    func testRawAndFileResumeRejectChangedOrRemovedObservation() async throws {
        var sourceRoot = URL(fileURLWithPath: #filePath)
        for _ in 0..<7 { sourceRoot.deleteLastPathComponent() }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let fixture = try decoder.decode(Fixture.self, from: Data(contentsOf: sourceRoot
            .appendingPathComponent("packages/contracts/export-history/v1/synthetic-direct-job.json")))
        for mode in [DirectResponseMode.rawJSON, .writeFiles] {
            let root = FileManager.default.temporaryDirectory.appendingPathComponent("history-resume-\(UUID().uuidString)")
            defer { try? FileManager.default.removeItem(at: root) }
            let destination = root.appendingPathComponent("vault", isDirectory: true)
            try FileManager.default.createDirectory(at: destination, withIntermediateDirectories: true)
            let layout = try DirectClientStorageLayout(rootURL: root.appendingPathComponent("state"))
            let store = try DirectJobStore(layout: layout)
            let request = DirectExportRequest(jobID: fixture.request.jobID, createdAt: fixture.request.createdAt,
                dateSelection: fixture.request.dateSelection, responseMode: mode,
                rawProfile: mode == .rawJSON ? .healthDataProjection : nil,
                canonicalSelection: fixture.request.canonicalSelection,
                destination: mode == .writeFiles ? .init(rootPath: destination.path) : nil)
            let session = try DirectTransferSession(sessionID: fixture.session.sessionID, jobID: request.jobID,
                requestFingerprint: DirectRequestFingerprint.make(for: request), peerBinding: fixture.session.peerBinding,
                partitionTargetBytes: fixture.session.partitionTargetBytes, createdAt: request.createdAt)
            let original = try XCTUnwrap(fixture.accepted.historyObservation)
            var object = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(original)) as? [String: Any])
            object["request_binding_sha256"] = session.requestFingerprint.sha256
            func observation(_ object: [String: Any]) throws -> ExportHistoryObservation {
                try JSONDecoder().decode(ExportHistoryObservation.self, from: JSONSerialization.data(withJSONObject: object))
            }
            func accepted(_ observation: ExportHistoryObservation?) -> DirectExportAccepted {
                .init(jobID: request.jobID, acceptedAt: fixture.accepted.acceptedAt, peerBinding: session.peerBinding,
                    resolvedDateIdentifiers: fixture.accepted.resolvedDateIdentifiers,
                    sourceTimeZoneIdentifier: fixture.accepted.sourceTimeZoneIdentifier,
                    resolvedCanonicalSelection: fixture.accepted.resolvedCanonicalSelection,
                    historyObservation: observation)
            }
            let first = accepted(try observation(object))
            try await store.save(try DirectJobRecord(request: request, createdAt: request.createdAt))
            let raw = DirectRawReceiver(layout: layout, jobStore: store)
            let files = DirectFileReceiver(layout: layout, jobStore: store)
            func prepare(_ accepted: DirectExportAccepted) async throws {
                if mode == .rawJSON {
                    try await raw.prepare(request: request, accepted: accepted, session: session)
                } else {
                    try await files.prepare(request: request, accepted: accepted, session: session)
                }
            }
            try await prepare(first)
            try await prepare(first)
            object["observation_id"] = "66666666-6666-4666-8666-666666666666"
            for changed in [accepted(try observation(object)), accepted(nil)] {
                do {
                    try await prepare(changed)
                    XCTFail("Resume accepted replaced history evidence")
                } catch {
                    XCTAssertTrue(error is DirectRawReceiverError || error is DirectFileReceiverError)
                }
            }
        }
    }
}
