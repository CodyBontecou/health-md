import base64
import copy
import json
import re
import unittest
from pathlib import Path
from build_source_artifacts import build_schema, compact
from build_transport_schema import build as build_transport
from validator import (HERE, ROOT, Invalid, SCHEMA, ValidatedContent, digest,
                       parse_record, parse_mutation, parse_read, parse_page, strict_json, mutation_digest, v2)


def encode(value):
    return compact(value).encode()


def scenario_outcome(s):
    r = s["remote"]
    event = s["event"]
    if event == "publish": return "mapped_only_after_receipt" if s["native_id"] != r["profile_id"] and s["mutation"]["base_revision"] == 0 else "invalid"
    if event == "replay": return "same_receipt" if s["original"] == s["retry"] else "idempotency_mismatch"
    if event == "observe":
        if r["object_revision"] <= s["base_revision"]: return "unchanged"
        if s["pending"]: return "edit_delete_conflict" if r["deleted"] else "edit_edit_conflict"
        return "keep_local_unlink_review" if r["deleted"] else "pending_local_review"
    if event == "fence": return "eligible_metadata_only" if s["owner"] == s["current"] else "quarantine"
    if event == "adopt": return "existing_mapping_no_duplicate" if s["already_mapped"] else "fresh_blocked_native_id"
    if event == "keep_both": return "independent_identity" if s["new_profile_id"] != r["profile_id"] and s["new_native_id"] != s["new_profile_id"] else "invalid"
    if event == "names": return "four_identities_no_fold" if len(set(s["ids"])) == len(s["names"]) else "invalid"
    if event == "preserve": return "publish_exact_overlay" if s["provenance"] == "verified" else "quarantine"
    if event == "protect": return "blocked_commit" if s["commit"] else "eligible_metadata_only"
    if event == "acceptance": return "accepted_unchanged_candidate_staged" if s["accepted_hash"] != s["fetched_hash"] else "invalid"
    if event == "reset": return "retain_until_complete" if not s["complete_snapshot"] else "quarantine_old_base_no_resurrection" if s["pending"] else "keep_local_unlink_review"
    if event == "snapshot_fence": return "discard_restart_snapshot" if s["first_snapshot_id"] != s["next_snapshot_id"] or s["first_high"] != s["next_high"] else "continue_snapshot"
    if event == "reorder": return "same_immutable_content" if s["previous_hash"] == r["content_hash"] else "invalid"
    if event == "cas": return "gone_never_restore_id" if r["deleted"] else "conflict" if r["object_revision"] != s["base_revision"] else "eligible_metadata_only"
    raise AssertionError("unknown source scenario")


class ProfileSyncContractTests(unittest.TestCase):
    def load(self, name):
        return json.loads((HERE / "fixtures" / name).read_bytes())

    def test_full_content_fixtures_hashes_and_exact_preservation(self):
        rows = self.load("content-vectors.json")["positive"]
        for name, row in rows.items():
            with self.subTest(name=name):
                raw = (HERE / "fixtures" / row["file"]).read_bytes()
                content = ValidatedContent.parse(raw, row["sha256"])
                self.assertEqual(content.raw, raw)
                self.assertEqual(list(content.requires_action), row["requires_action"])
                self.assertNotEqual(digest(raw[:-1]), content.sha256)
                self.assertNotEqual(digest(raw + b" "), content.sha256)
                with self.assertRaises(Invalid): ValidatedContent.parse(raw, "0" * 64)
        self.assertEqual(len(rows), 10)

    def test_actual_full_parser_negative_and_positive_vectors(self):
        parsers = {"content": ValidatedContent.parse, "json": lambda b: strict_json(b, 262_144), "record": parse_record, "mutation": parse_mutation, "read": parse_read, "page": parse_page}
        cases = self.load("parser-cases.json")["cases"]
        for c in cases:
            with self.subTest(case=c["id"]):
                raw = b" " * c["repeat"] if "repeat" in c else bytes.fromhex(c["hex"]) if "hex" in c else c["raw"].encode()
                if c["valid"]:
                    parsers[c["entry"]](raw)
                    if "request_hash" in c:
                        self.assertEqual(mutation_digest(raw), c["request_hash"])
                        self.assertNotEqual(mutation_digest(raw + b" "), c["request_hash"])
                else:
                    with self.assertRaises(Invalid): parsers[c["entry"]](raw)
        self.assertGreaterEqual(len(cases), 135)

    def test_shared_source_scenarios_traverse_real_parser(self):
        rows = self.load("scenarios.json")["scenarios"]
        for s in rows:
            with self.subTest(case=s["id"]):
                parse_record(encode(s["remote"]))
                if "mutation" in s: parse_mutation(encode(s["mutation"]))
                if "original" in s: parse_mutation(encode(s["original"]))
                if "retry" in s: parse_mutation(encode(s["retry"]))
                self.assertEqual(scenario_outcome(s), s["expected"])
        self.assertEqual(len(rows), 30)

    def test_closed_projection_is_reproducible_without_v2_change(self):
        self.assertEqual(SCHEMA, build_schema())
        source_pins = json.loads((HERE / "source-pins.json").read_bytes())
        import hashlib
        self.assertEqual(source_pins["shared_setup_schema_sha256"], hashlib.sha256((ROOT / "packages/contracts/shared-setup/v2/shared-setup.schema.json").read_bytes()).hexdigest())
        self.assertEqual(source_pins["metric_registry_sha256"], hashlib.sha256((ROOT / "packages/healthmd-core-rust/crates/healthmd-core/registry/metric-registry-v1.json").read_bytes()).hexdigest())
        data = json.loads((HERE / "codec-data.json").read_bytes())
        self.assertEqual(data["shape"], SCHEMA)
        self.assertEqual(data["registry"], json.loads((HERE / "registry-evidence.json").read_bytes()))
        # Every codec's embedded literal must be exactly the same checked source data.
        paths = ["apps/cloud/src/profile-sync-v1-contract.ts", "apps/apple/HealthMd/Shared/AccountSync/ProfileSyncV1.swift", "apps/android/app/src/main/java/com/healthmd/accountsync/ProfileSyncV1.kt"]
        for path in paths:
            with self.subTest(path=path):
                block = (ROOT / path).read_text().split("// BEGIN GENERATED PINNED DATA", 1)[1].split("// END GENERATED PINNED DATA", 1)[0]
                literals = re.findall(r'"([A-Za-z0-9+/=]+)"', block)
                embedded = json.loads(base64.b64decode("".join(literals)))
                self.assertEqual(embedded, data)

    def test_transport_schema_reproducibility_and_valid_vectors(self):
        schema = json.loads((HERE / "profile-sync.schema.json").read_bytes())
        self.assertEqual(schema, build_transport())
        for c in self.load("parser-cases.json")["cases"]:
            if c["valid"] and c["entry"] not in {"content", "json"}:
                with self.subTest(case=c["id"]):
                    v2.validate_json_schema_subset(strict_json(c["raw"].encode()), schema, "sync transport")
        # Fixed errors cannot echo private configuration or account context.
        error = {"schema": "healthmd.profile_sync", "schema_version": 1, "result": "resync_required"}
        v2.validate_json_schema_subset(error, schema, "sync error")
        with self.assertRaises(v2.ContractValidationError):
            v2.validate_json_schema_subset(dict(error, account_id="synthetic"), schema, "sync error")

    def test_foreign_unchanged_and_local_edit_roundtrip(self):
        source = json.loads((HERE / "fixtures/foreign-unchanged.json").read_bytes())
        edited = json.loads((HERE / "fixtures/foreign-local-edit.json").read_bytes())
        for content in (source, edited): ValidatedContent.parse(encode(content))
        self.assertEqual(source["profile"]["platform_extensions"]["android"], edited["profile"]["platform_extensions"]["android"])
        self.assertEqual(source["profile"]["destination"], edited["profile"]["destination"])
        self.assertEqual(source["profile"]["schedule"], edited["profile"]["schedule"])
        self.assertNotEqual(source["profile"]["name"], edited["profile"]["name"])

    def test_safe_integer_duplicate_and_unicode_rules_are_not_json_schema_only(self):
        for raw in (b'{"a":1,"a":2}', b'{"a":1,"\\u0061":2}', '{"é":1,"e\\u0301":2}'.encode(), b'{"a":1.0}', b'{"a":1e0}', b'{"a":-0}', b'{"a":9007199254740992}', b'{"a":"\\ud800"}', b'\xef\xbb\xbf{}'):
            with self.subTest(raw=raw):
                with self.assertRaises(Invalid): strict_json(raw)

    def test_validated_reference_not_fabricated_from_unchecked_fields(self):
        with self.assertRaises(TypeError): ValidatedContent(raw=b"{}", sha256="0" * 64, requires_action=())
        c = ValidatedContent.parse((HERE / "fixtures/registry-current.json").read_bytes())
        with self.assertRaises(AttributeError): c.sha256 = "0" * 64


if __name__ == "__main__": unittest.main(verbosity=2)
