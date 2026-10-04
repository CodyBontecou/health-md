import Foundation
#if !PROFILE_SYNC_HOST
import XCTest
@testable import HealthMd
#endif

enum ProfileSyncV1FixtureConformance {
    struct Failure: Error { let caseID: String }
    static func require(_ ok: Bool, _ id: String) throws { if !ok { throw Failure(caseID: id) } }
    static func run(root: URL) throws -> String {
        let directory = root.appendingPathComponent("packages/contracts/profile-sync/v1/fixtures")
        func load(_ file: String) throws -> [String: Any] {
            try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent(file))) as! [String: Any]
        }
        func encode(_ value: Any) throws -> Data { try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys, .withoutEscapingSlashes]) }
        let vectors = try load("content-vectors.json")["positive"] as! [String: [String: Any]]
        for (id, row) in vectors {
            let bytes = try Data(contentsOf: directory.appendingPathComponent(row["file"] as! String))
            let content = try ProfileSyncV1.Content.parse(bytes, expectedHash: row["sha256"] as? String)
            try require(Data(content.contentJSON.utf8) == bytes, id)
            try require(content.requiresAction == row["requires_action"] as! [String], id)
            try require(ProfileSyncV1.contentHash(bytes) == row["sha256"] as! String, id)
            try require(ProfileSyncV1.contentHash(bytes.dropLast()) != content.hash, id + " exact bytes")
        }
        let cases = try load("parser-cases.json")["cases"] as! [[String: Any]]
        for row in cases {
            let id = row["id"] as! String
            let bytes: Data
            if let count = row["repeat"] as? Int { bytes = Data(repeating: 32, count: count) }
            else if let hex = row["hex"] as? String {
                var values: [UInt8] = []; var index = hex.startIndex
                while index < hex.endIndex { let end = hex.index(index, offsetBy: 2); values.append(UInt8(hex[index..<end], radix: 16)!); index = end }
                bytes = Data(values)
            }
            else { bytes = Data((row["raw"] as! String).utf8) }
            var accepted = true
            do {
                switch row["entry"] as! String {
                case "content": _ = try ProfileSyncV1.Content.parse(bytes)
                case "json": _ = try ProfileSyncV1.parseJSON(bytes, maximum: ProfileSyncV1.contentMaximum)
                case "record": _ = try ProfileSyncV1.Record.parse(bytes)
                case "mutation":
                    let mutation = try ProfileSyncV1.parseMutation(bytes)
                    if let expected = row["request_hash"] as? String {
                        try require(mutation.requestHash == expected && ProfileSyncV1.mutationHash(bytes) == expected, id)
                        try require(ProfileSyncV1.mutationHash(bytes + Data([32])) != expected, id + " exact mutation bytes")
                    }
                case "read": _ = try ProfileSyncV1.parseRead(bytes)
                case "page": _ = try ProfileSyncV1.parsePage(bytes)
                default: throw Failure(caseID: id)
                }
            } catch { accepted = false }
            try require(accepted == row["valid"] as! Bool, id)
        }
        let scenarios = try load("scenarios.json")["scenarios"] as! [[String: Any]]
        for s in scenarios {
            let id = s["id"] as! String
            let remote = try ProfileSyncV1.Record.parse(encode(s["remote"]!))
            if let mutation = s["mutation"] { _ = try ProfileSyncV1.parseMutation(encode(mutation)) }
            if let original = s["original"] { _ = try ProfileSyncV1.parseMutation(encode(original)) }
            if let retry = s["retry"] { _ = try ProfileSyncV1.parseMutation(encode(retry)) }
            try require(try outcome(s, remote: remote) == s["expected"] as! String, id)
        }
        let before = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("foreign-unchanged.json"))) as! NSDictionary
        let after = try JSONSerialization.jsonObject(with: Data(contentsOf: directory.appendingPathComponent("foreign-local-edit.json"))) as! NSDictionary
        let a = (before["profile"] as! NSDictionary)["platform_extensions"] as! NSDictionary
        let b = (after["profile"] as! NSDictionary)["platform_extensions"] as! NSDictionary
        try require((a["android"] as! NSDictionary).isEqual(b["android"]), "foreign exact local edit")
        return "\(vectors.count) content fixtures, \(cases.count) parser cases, \(scenarios.count) test-only source scenarios"
    }
    // Test-only source predicates; NOT production reconciliation/transactions/authorization.
    private static func outcome(_ s: [String: Any], remote r: ProfileSyncV1.Record) throws -> String {
        func equivalent(_ a: Any, _ b: Any) throws -> Bool {
            try JSONSerialization.data(withJSONObject: a, options: [.sortedKeys, .fragmentsAllowed]) == JSONSerialization.data(withJSONObject: b, options: [.sortedKeys, .fragmentsAllowed])
        }
        switch s["event"] as! String {
        case "publish": return s["native_id"] as! String != r.profileID && (s["mutation"] as! [String: Any])["base_revision"] as! Int == 0 ? "mapped_only_after_receipt" : "invalid"
        case "replay": return try equivalent(s["original"]!, s["retry"]!) ? "same_receipt" : "idempotency_mismatch"
        case "observe":
            if r.objectRevision <= (s["base_revision"] as! NSNumber).int64Value { return "unchanged" }
            if s["pending"] as! Bool { return r.deleted ? "edit_delete_conflict" : "edit_edit_conflict" }
            return r.deleted ? "keep_local_unlink_review" : "pending_local_review"
        case "fence": return try equivalent(s["owner"]!, s["current"]!) ? "eligible_metadata_only" : "quarantine"
        case "adopt": return s["already_mapped"] as! Bool ? "existing_mapping_no_duplicate" : "fresh_blocked_native_id"
        case "keep_both": return s["new_profile_id"] as! String != r.profileID && s["new_native_id"] as! String != s["new_profile_id"] as! String ? "independent_identity" : "invalid"
        case "names": return Set(s["ids"] as! [String]).count == (s["names"] as! [String]).count ? "four_identities_no_fold" : "invalid"
        case "preserve": return s["provenance"] as! String == "verified" ? "publish_exact_overlay" : "quarantine"
        case "protect": return s["commit"] as! Bool ? "blocked_commit" : "eligible_metadata_only"
        case "acceptance": return s["accepted_hash"] as! String != s["fetched_hash"] as! String ? "accepted_unchanged_candidate_staged" : "invalid"
        case "reset": return !(s["complete_snapshot"] as! Bool) ? "retain_until_complete" : s["pending"] as! Bool ? "quarantine_old_base_no_resurrection" : "keep_local_unlink_review"
        case "snapshot_fence": return s["first_snapshot_id"] as! String != s["next_snapshot_id"] as! String || s["first_high"] as! Int != s["next_high"] as! Int ? "discard_restart_snapshot" : "continue_snapshot"
        case "reorder": return (s["previous_hash"] as! String) == r.content?.hash ? "same_immutable_content" : "invalid"
        case "cas": return r.deleted ? "gone_never_restore_id" : r.objectRevision != (s["base_revision"] as! NSNumber).int64Value ? "conflict" : "eligible_metadata_only"
        default: throw Failure(caseID: s["id"] as! String)
        }
    }
}
#if !PROFILE_SYNC_HOST
final class ProfileSyncV1Tests: XCTestCase {
    func testSharedFixturesAndSourceScenarios() throws {
        let root = URL(fileURLWithPath: #filePath).deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        _ = try ProfileSyncV1FixtureConformance.run(root: root)
    }
}
#endif
