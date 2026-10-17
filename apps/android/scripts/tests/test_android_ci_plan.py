#!/usr/bin/env python3
"""Regression tests for PR routing, complete changes, and full push qualification."""
from __future__ import annotations

import argparse
import importlib.util
import io
import json
import os
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch


SCRIPT = Path(__file__).resolve().parents[1] / "android-ci-plan.py"
SPEC = importlib.util.spec_from_file_location("android_ci_plan", SCRIPT)
assert SPEC and SPEC.loader
ci = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ci)


def arguments(**updates):
    values = dict(event_name="pull_request", release_sha="", force_full_qualification="false",
                  files_json=None, event_path="", repository="owner/repo", token="test-token")
    return argparse.Namespace(**(values | updates))


class RoutingTest(unittest.TestCase):
    def assertJobs(self, paths, jobs, *, relevant=True):
        result = ci.plan(set(paths))
        self.assertEqual(relevant, result["run"])
        self.assertEqual(set(jobs), {job for job in ci.JOBS if result[job]})
        self.assertEqual("standard", result["accessibility_matrix"])

    def test_phone_change_keeps_both_flavors_without_wear_emulator(self):
        self.assertJobs(["apps/android/app/src/main/java/com/healthmd/Home.kt"], ci.PHONE)

    def test_phone_flavor_change_keeps_both_flavors(self):
        self.assertJobs(["apps/android/app/src/fdroid/java/com/healthmd/Billing.kt"], ci.PHONE)

    def test_shared_android_core_keeps_phone_consumers(self):
        self.assertJobs(["apps/android/healthmd-core/src/main/kotlin/Core.kt"], ci.PHONE)

    def test_wear_change_keeps_wear_and_jvm(self):
        self.assertJobs(["apps/android/wear/src/main/AndroidManifest.xml"], {"test", "wear"})

    def test_wearable_contract_keeps_phone_and_wear_consumers(self):
        self.assertJobs(["apps/android/wearable-contract/src/main/kotlin/Snapshot.kt"], ci.PHONE | {"wear"})

    def test_direct_protocol_keeps_instrumentation_and_live_interop(self):
        self.assertJobs(["apps/android/direct-protocol/src/main/kotlin/DirectCrypto.kt"], {"test", "instrumentation", "interop"})

    def test_cli_source_keeps_its_android_consumers(self):
        for path in ("apps/cli/Cargo.toml", "apps/cli/Cargo.lock",
                     "apps/cli/crates/healthmd-client/src/handshake.rs",
                     "apps/cli/crates/healthmd-client/tests/android_live_listener.rs"):
            with self.subTest(path=path):
                self.assertJobs([path], {"instrumentation", "interop"})

    def test_shared_contracts_core_and_toolchain_keep_every_gate(self):
        for path in ("packages/contracts/render-input/v1/schema.json",
                     "packages/healthmd-core-rust/crates/healthmd-core/src/lib.rs",
                     "apps/android/gradle/libs.versions.toml", "apps/android/settings.gradle.kts",
                     "apps/android/app/build.gradle.kts", "apps/android/gradlew",
                     ".github/actions/component-changes/action.yml",
                     ".github/workflows/android-ci.yml", ".github/workflows/android-release.yml",
                     ".github/workflows/README.md", "AGENTS.md", "Makefile"):
            with self.subTest(path=path):
                self.assertJobs([path], ci.ALL)

    def test_release_and_contract_document_jvm_assertions_still_run(self):
        for path in ("apps/android/docs/export-contract/schemas/healthmd.raw_record.v1.schema.json",
                     "apps/android/docs/export-contract/android-ios-gap-matrix.md",
                     "apps/android/docs/android-desktop-destination.md",
                     "apps/android/play-console/listing/en-US/release-notes/en-US/default.txt",
                     "apps/android/app/src/main/play/release-notes/en-US/default.txt",
                     "apps/android/release-scope.json",
                     "apps/android/scripts/upload-google-play-phone-release.sh"):
            with self.subTest(path=path):
                self.assertJobs([path], {"test"})

    def test_documentation_and_listing_only_need_fast_policy_checks(self):
        for path in ("apps/android/README.md", "apps/android/DESIGN.md",
                     "apps/android/docs/features/manual-export.md",
                     "apps/android/play-store/wear/screenshots/wear-app.png",
                     "apps/android/scripts/tests/test_android_ci_plan.py",
                     "apps/android/scripts/prepare-play-metadata.py",
                     "docs/migration/source-revisions.md"):
            with self.subTest(path=path):
                self.assertJobs([path], set())

    def test_execution_helpers_run_the_gates_that_use_them(self):
        cases = {
            "run-accessibility-ui-tests.sh": {"instrumentation"},
            "test-accessibility-ui-runner.sh": {"instrumentation"},
            "run-direct-cli-ui-e2e.sh": {"instrumentation"},
            "run-wear-emulator-smoke.sh": {"test", "wear"},
            "WearBundleManifestVerifier.java": {"test", "wear"},
            "validate-fdroid-metadata.sh": {"fdroid"},
            "verify-fdroid-artifact.sh": {"fdroid"},
        }
        for name, jobs in cases.items():
            with self.subTest(name=name):
                self.assertJobs([f"apps/android/scripts/{name}"], jobs)

    def test_unclassified_paths_cannot_silently_disable_jobs(self):
        for path in ("apps/android/new-module/src/Main.kt", "apps/android/toolchain.json",
                     "apps/android/scripts/new-build-helper.sh", "apps/android/docs/generated-tool.py",
                     "packages/new-shared-library/src/lib.rs", "new-root-build-config.json"):
            with self.subTest(path=path):
                self.assertJobs([path], ci.ALL)

    def test_unrelated_components_do_not_boot_android(self):
        self.assertJobs(["apps/apple/HealthMd/App.swift", "apps/website/src/index.ts",
                         "apps/practice/package.json", "apps/wake/src/index.ts",
                         "apps/cli/docs/architecture.md", ".github/workflows/website-ci.yml",
                         "docs/qa/shared-setup-v2.md"], set(), relevant=False)

    def test_multiple_changes_union_required_jobs(self):
        self.assertJobs(["apps/android/app/src/main/Home.kt", "apps/android/wear/src/main/Watch.kt"], ci.PHONE | {"wear"})

    def test_removed_file_still_selects_its_consumers(self):
        self.assertJobs(ci.record_paths([{"filename": "apps/android/wear/src/main/Old.kt", "status": "removed"}]), {"test", "wear"})

    def test_rename_out_of_android_keeps_old_consumers(self):
        paths = ci.record_paths([{"filename": "docs/old-app.txt", "status": "renamed",
                                  "previous_filename": "apps/android/app/src/main/Old.kt"}])
        self.assertJobs(paths, ci.PHONE)

    def test_rename_between_modules_unions_both_consumers(self):
        paths = ci.record_paths([{"filename": "apps/android/wear/src/main/New.kt", "status": "renamed",
                                  "previous_filename": "apps/android/app/src/main/Old.kt"}])
        self.assertJobs(paths, ci.PHONE | {"wear"})


class ChangeCompletenessTest(unittest.TestCase):
    @staticmethod
    def metadata(count, *, head="a" * 40, base="b" * 40):
        return {"changed_files": count, "head": {"sha": head}, "base": {"sha": base}}

    @classmethod
    def event(cls, count):
        return {"number": 7, "pull_request": cls.metadata(count)}

    @staticmethod
    def response(records, *, next_page=False):
        response = io.StringIO(json.dumps(records))
        response.headers = {"Link": '<https://api.github.com/next>; rel="next"'} if next_page else {}
        return response

    def test_pull_request_paginates_past_one_hundred_files(self):
        first = [{"filename": f"docs/file-{index}.md", "status": "modified"} for index in range(100)]
        last = [{"filename": "apps/android/app/src/main/Changed.kt", "status": "modified"}]
        responses = [self.response(self.metadata(101)), self.response(first, next_page=True),
                     self.response(last), self.response(self.metadata(101))]
        with patch.object(ci.urllib.request, "urlopen", side_effect=responses) as fetch:
            paths = ci.pr_files(self.event(101), "owner/repo", "test-token")
        self.assertEqual(4, fetch.call_count)
        self.assertIn("page=2", fetch.call_args_list[2].args[0].full_url)
        self.assertTrue(fetch.call_args_list[0].args[0].full_url.endswith("/pulls/7"))
        self.assertTrue(fetch.call_args_list[3].args[0].full_url.endswith("/pulls/7"))
        self.assertEqual(ci.PHONE, {job for job in ci.JOBS if ci.plan(paths)[job]})

    def test_pull_request_rename_includes_source_path(self):
        records = [{"filename": "docs/retired.md", "status": "renamed",
                    "previous_filename": "apps/android/wear/src/main/Retired.kt"}]
        responses = [self.response(self.metadata(1)), self.response(records), self.response(self.metadata(1))]
        with patch.object(ci.urllib.request, "urlopen", side_effect=responses):
            paths = ci.pr_files(self.event(1), "owner/repo", "test-token")
        self.assertIn(records[0]["previous_filename"], paths)

    def test_api_cap_or_unknown_expected_count_fails_closed(self):
        for count in (None, -1, True, 3000, 3001):
            with self.subTest(count=count), self.assertRaises(ci.IncompleteChanges):
                ci.pr_files(self.event(count), "owner/repo", "test-token")

    def test_truncated_and_duplicate_api_results_fail_closed(self):
        record = {"filename": "docs/readme.md", "status": "modified"}
        for records in ([record], [record, record]):
            with self.subTest(records=records):
                with patch.object(ci.urllib.request, "urlopen", side_effect=[self.response(self.metadata(2)), self.response(records)]):
                    with self.assertRaises(ci.IncompleteChanges):
                        ci.pr_files(self.event(2), "owner/repo", "test-token")

    def test_missing_pinned_revision_never_uses_current_api_diff(self):
        for pr in ({"changed_files": 1}, self.metadata(1, head="invalid"),
                   self.metadata(1, base="0" * 40)):
            with self.subTest(pr=pr), patch.object(ci.urllib.request, "urlopen") as fetch:
                with self.assertRaises(ci.IncompleteChanges):
                    ci.pr_files({"number": 7, "pull_request": pr}, "owner/repo", "test-token")
                fetch.assert_not_called()

    def assertRevisionFallback(self, responses, *, count):
        with tempfile.TemporaryDirectory() as directory:
            event = Path(directory) / "event.json"
            event.write_text(json.dumps(self.event(count)))
            with patch.object(ci.urllib.request, "urlopen", side_effect=responses):
                result, _ = ci.determine_plan(arguments(event_path=str(event)))
        self.assertEqual(ci.full_plan("full"), result)

    def test_new_head_with_same_file_count_forces_full_matrix(self):
        self.assertRevisionFallback([self.response(self.metadata(1, head="c" * 40))], count=1)

    def test_new_base_with_same_file_count_forces_full_matrix(self):
        self.assertRevisionFallback([self.response(self.metadata(1, base="c" * 40))], count=1)

    def test_revision_race_during_pagination_forces_full_matrix(self):
        first = [{"filename": f"docs/file-{index}.md", "status": "modified"} for index in range(100)]
        last = [{"filename": "docs/new-file.md", "status": "modified"}]
        for current in (self.metadata(101, head="c" * 40), self.metadata(101, base="c" * 40)):
            with self.subTest(current=current):
                responses = [self.response(self.metadata(101)), self.response(first, next_page=True),
                             self.response(last), self.response(current)]
                self.assertRevisionFallback(responses, count=101)

    def test_missing_rename_source_and_malformed_paths_fail_closed(self):
        records = [
            {"filename": "docs/readme.md", "status": "renamed"},
            {"filename": "docs/readme.md", "status": "mystery"},
            {"filename": "../apps/android/app/Hidden.kt", "status": "modified"},
            {"filename": "apps//android/Hidden.kt", "status": "removed"},
            {"filename": "/apps/android/app/Hidden.kt", "status": "modified"},
            {"filename": "docs/readme.md", "status": "modified", "previous_filename": "../bad"},
            {"filename": "docs/readme.md\nrun=false", "status": "modified"},
            {"filename": None, "status": "modified"},
        ]
        for record in records:
            with self.subTest(record=record), self.assertRaises(ci.IncompleteChanges):
                ci.record_paths([record])

class QualificationAndCliTest(unittest.TestCase):
    def test_ordinary_push_keeps_every_job_and_full_matrix_even_with_offline_files(self):
        with tempfile.TemporaryDirectory() as directory:
            files = Path(directory) / "files.json"
            files.write_text(json.dumps(["apps/android/app/src/main/Home.kt"]))
            result, _ = ci.determine_plan(arguments(event_name="push", files_json=str(files)))
        self.assertEqual(ci.full_plan("full"), result)

    def test_push_needs_no_change_detection_or_history(self):
        result, _ = ci.determine_plan(arguments(event_name="push", files_json="missing.json", event_path="missing-event.json"))
        self.assertEqual(ci.full_plan("full"), result)

    def test_manual_reusable_and_other_events_run_full_qualification(self):
        for name in ("workflow_dispatch", "workflow_call", "schedule", "release", "unknown"):
            with self.subTest(name=name):
                result, _ = ci.determine_plan(arguments(event_name=name))
                self.assertEqual(ci.full_plan("full"), result)

    def test_reusable_caller_inherits_push_but_forces_full_qualification(self):
        for force in ("true", "invalid", "", "TRUE"):
            with self.subTest(force=force):
                result, _ = ci.determine_plan(arguments(event_name="push", force_full_qualification=force))
                self.assertEqual(ci.full_plan("full"), result)

    def test_release_sha_cannot_be_bypassed_by_false_force_or_offline_empty_files(self):
        result, _ = ci.determine_plan(arguments(release_sha="abc123", files_json="missing.json"))
        self.assertEqual(ci.full_plan("full"), result)

    def test_api_failure_or_malformed_event_runs_every_job(self):
        for content in ("not JSON", "[]", '{"pull_request": {}}'):
            with self.subTest(content=content), tempfile.TemporaryDirectory() as directory:
                event = Path(directory) / "event.json"
                event.write_text(content)
                result, _ = ci.determine_plan(arguments(event_path=str(event)))
                self.assertEqual(ci.full_plan(), result)

    def test_offline_cli_writes_all_boolean_outputs_and_matrix(self):
        with tempfile.TemporaryDirectory() as directory:
            files = Path(directory) / "files.json"
            output = Path(directory) / "output.txt"
            files.write_text(json.dumps(["apps/android/app/src/main/Home.kt"]))
            env = dict(os.environ, FORCE_FULL_QUALIFICATION="false", PYTHONDONTWRITEBYTECODE="1")
            subprocess.run([sys.executable, str(SCRIPT), "--event-name", "pull_request",
                            "--files-json", str(files), "--output", str(output)], env=env,
                           check=True, capture_output=True, text=True)
            actual = dict(line.split("=", 1) for line in output.read_text().splitlines())
            self.assertEqual({"run": "true", "test": "true", "fdroid": "true", "instrumentation": "true",
                              "wear": "false", "interop": "false", "accessibility_matrix": "standard"}, actual)

    def test_offline_cli_push_cannot_reduce_release_qualification(self):
        with tempfile.TemporaryDirectory() as directory:
            files = Path(directory) / "files.json"
            output = Path(directory) / "output.txt"
            files.write_text("[]")
            env = dict(os.environ, FORCE_FULL_QUALIFICATION="false", PYTHONDONTWRITEBYTECODE="1")
            subprocess.run([sys.executable, str(SCRIPT), "--event-name", "push",
                            "--files-json", str(files), "--output", str(output)], env=env,
                           check=True, capture_output=True, text=True)
            actual = dict(line.split("=", 1) for line in output.read_text().splitlines())
            self.assertEqual({"run": "true", **dict.fromkeys(ci.JOBS, "true"), "accessibility_matrix": "full"}, actual)

    def test_offline_invalid_and_oversized_lists_run_every_job(self):
        for records in ({"not": "a list"}, ["docs/../hidden"] , ["docs/readme.md"] * 3000):
            with self.subTest(records_type=type(records)), tempfile.TemporaryDirectory() as directory:
                files = Path(directory) / "files.json"
                files.write_text(json.dumps(records))
                result, _ = ci.determine_plan(arguments(files_json=str(files)))
                self.assertEqual(ci.full_plan(), result)


if __name__ == "__main__":
    unittest.main()
