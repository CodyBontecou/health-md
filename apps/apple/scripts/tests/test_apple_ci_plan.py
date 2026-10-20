#!/usr/bin/env python3
"""Coverage-preserving Apple PR routing and complete change-list regressions."""
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

SCRIPT = Path(__file__).resolve().parents[1] / "apple-ci-plan.py"
SPEC = importlib.util.spec_from_file_location("apple_ci_plan", SCRIPT)
assert SPEC and SPEC.loader
ci = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(ci)


def arguments(**updates):
    values = dict(event_name="pull_request", release_sha="", force_full_qualification="false",
                  files_json=None, event_path="", repository="owner/repo", token="test-token")
    return argparse.Namespace(**(values | updates))


class RoutingTests(unittest.TestCase):
    def assertJobs(self, paths, jobs):
        result = ci.plan(set(paths))
        selected = set(jobs)
        if selected & {"ios", "ios_ui", "macos", "watch"}:
            selected.add("prepare")
        if selected:
            selected.add("policy")
        self.assertEqual(selected, {job for job in ci.JOBS if result[job]})
        self.assertEqual(bool(selected), result["run"])

    def test_plain_docs_keep_macos_coverage_and_generated_document_checks(self):
        for path in ("apps/apple/README.md", "apps/apple/docs/features/notifications.md",
                     "apps/apple/docs/reference/generated/core/metrics.json",
                     "apps/apple/docs/reference/generated/automation/shortcuts.md",
                     "apps/apple/docs/reference/generated/rollups/range.csv",
                     "apps/apple/docs/reference/generated/cli/commands.md"):
            with self.subTest(path=path):
                self.assertJobs([path], {"macos"})

    def test_documents_read_by_shared_xctests_keep_both_unit_suites(self):
        for path in ("apps/apple/docs/testing/lifecycle-audit.md",
                     "apps/apple/docs/testing/appearance-audit.md",
                     "apps/apple/docs/testing/apns-scheduling-preflight.md",
                     "apps/apple/docs/testing/CI-QUALITY-GATES.md",
                     "apps/apple/docs/features/scheduled-exports.md",
                     "apps/apple/docs/experiments/health-md-1499-lifetime-price-experiment.md",
                     "apps/apple/docs/reference/generated/individual/workout.md",
                     "apps/apple/metadata/version/3.4.10/en-US.json"):
            with self.subTest(path=path):
                self.assertJobs([path], {"ios", "macos"})

    def test_ui_test_changes_keep_all_ui_regressions_and_shared_artifact(self):
        self.assertJobs(["apps/apple/HealthMdUITests/ExportJourneyUITests.swift"], {"ios_ui"})

    def test_embedded_cli_keeps_macos_consumer_and_doc_generation(self):
        self.assertJobs(["apps/apple/HealthMdCLI/Sources/HealthMdCLI/main.swift"], {"macos"})

    def test_source_and_build_changes_keep_all_gates(self):
        for path in ("apps/apple/HealthMd/iOS/ExportView.swift",
                     "apps/apple/HealthMd/macOS/MacExportView.swift",
                     "apps/apple/HealthMdTests/iOS/PluginVisualizationResourceTests.swift",
                     "apps/apple/HealthMd.xcodeproj/project.pbxproj",
                     "apps/apple/Packages/HealthMdConnectivity/Sources/Protocol.swift",
                     "apps/apple/Packages/HealthMdCoreRust/Bindings/healthmd_core.swift",
                     "packages/contracts/product-capabilities.json",
                     "packages/healthmd-core-rust/Cargo.lock", "AGENTS.md", "Makefile",
                     ".github/actions/some-new-build-action/action.yml",
                     ".github/workflows/apple-ci.yml"):
            with self.subTest(path=path):
                self.assertJobs([path], ci.ALL)

    def test_external_resources_read_by_shared_tests_keep_both_unit_suites(self):
        for path in ("apps/website/external-sources.json",
                     "apps/website/assets/healthmd-plugin-visualizations.js",
                     "apps/website/assets/visualizations-data/health-sample.json",
                     "apps/website/assets/visualizations-data/health-rollups.json",
                     ".github/workflows/apple-nightly.yml", ".github/workflows/release-ios.yml"):
            with self.subTest(path=path):
                self.assertJobs([path], {"ios", "macos"})

    def test_reviewed_unrelated_components_skip_heavy_apple_jobs(self):
        self.assertJobs(["apps/android/app/src/main/Main.kt", "apps/cli/crates/healthmd-client/src/lib.rs",
                         "apps/website/src/index.ts", "apps/practice/package.json", "apps/wake/src/index.ts",
                         "docs/qa/shared-setup.md", ".github/workflows/website-ci.yml"], set())

    def test_unknown_paths_fail_closed(self):
        for path in ("apps/apple/new-build.toml", "apps/apple/scripts/new-build-helper.sh",
                     "apps/apple/docs/new-generated-input.py", "packages/new-library/src/lib.rs",
                     "new-root-config.json"):
            with self.subTest(path=path):
                self.assertJobs([path], ci.ALL)

    def test_multiple_changes_union_jobs_and_artifact_dependencies(self):
        self.assertJobs(["apps/apple/HealthMdUITests/Launch.swift", "apps/apple/docs/features/export.md"],
                        {"ios_ui", "macos"})

    def test_renames_and_removals_preserve_both_old_and_new_consumers(self):
        paths = ci.record_paths([{"filename": "docs/retired.md", "status": "renamed",
                                  "previous_filename": "apps/apple/HealthMdUITests/Launch.swift"},
                                 {"filename": "apps/apple/docs/reference/generated/individual/workout.md",
                                  "status": "removed"}])
        self.assertJobs(paths, {"ios", "macos", "ios_ui"})


class ChangeCompletenessTests(unittest.TestCase):
    @staticmethod
    def metadata(count, head="a" * 40, base="b" * 40):
        return {"changed_files": count, "head": {"sha": head}, "base": {"sha": base}}

    @classmethod
    def event(cls, count):
        return {"number": 7, "pull_request": cls.metadata(count)}

    @staticmethod
    def response(value, next_page=False):
        response = io.StringIO(json.dumps(value))
        response.headers = {"Link": '<https://api.github.com/next>; rel="next"'} if next_page else {}
        return response

    def test_paginates_complete_list_with_source_rename(self):
        first = [{"filename": f"docs/file-{index}.md", "status": "modified"} for index in range(100)]
        last = [{"filename": "docs/retired.md", "status": "renamed",
                 "previous_filename": "apps/apple/HealthMd/Old.swift"}]
        responses = [self.response(self.metadata(101)), self.response(first, True),
                     self.response(last), self.response(self.metadata(101))]
        with patch.object(ci.urllib.request, "urlopen", side_effect=responses) as fetch:
            paths = ci.pr_files(self.event(101), "owner/repo", "test-token")
        self.assertEqual(4, fetch.call_count)
        self.assertIn("page=2", fetch.call_args_list[2].args[0].full_url)
        self.assertIn("apps/apple/HealthMd/Old.swift", paths)

    def test_unknown_count_api_cap_missing_sha_and_context_fail_closed(self):
        for count in (None, -1, True, 3000, 3001):
            with self.subTest(count=count), self.assertRaises(ci.IncompleteChanges):
                ci.pr_files(self.event(count), "owner/repo", "test-token")
        for metadata in ({"changed_files": 1}, self.metadata(1, head="wrong"), self.metadata(1, base="0" * 40)):
            with self.subTest(metadata=metadata), self.assertRaises(ci.IncompleteChanges):
                ci.pr_files({"number": 7, "pull_request": metadata}, "owner/repo", "test-token")
        with self.assertRaises(ci.IncompleteChanges):
            ci.pr_files(self.event(1), "owner/repo", "")

    def test_truncation_duplicates_and_empty_intermediate_pages_fail_closed(self):
        record = {"filename": "docs/one.md", "status": "modified"}
        for records, next_page in (([record], False), ([record, record], False), ([], True)):
            with self.subTest(records=records), patch.object(ci.urllib.request, "urlopen", side_effect=[
                self.response(self.metadata(2)), self.response(records, next_page)
            ]), self.assertRaises(ci.IncompleteChanges):
                ci.pr_files(self.event(2), "owner/repo", "test-token")

    def test_new_head_or_base_before_or_during_pagination_falls_back_to_full(self):
        record = {"filename": "apps/apple/docs/guide.md", "status": "modified"}
        for updated in (self.metadata(1, head="c" * 40), self.metadata(1, base="c" * 40)):
            for responses in ([self.response(updated)], [self.response(self.metadata(1)),
                              self.response([record]), self.response(updated)]):
                with tempfile.TemporaryDirectory() as directory:
                    event = Path(directory) / "event.json"
                    event.write_text(json.dumps(self.event(1)))
                    with patch.object(ci.urllib.request, "urlopen", side_effect=responses):
                        result, _ = ci.determine_plan(arguments(event_path=str(event)))
                    self.assertEqual(ci.full_plan(), result)

    def test_bad_records_cannot_hide_consumers_or_inject_workflow_outputs(self):
        for record in ({"filename": "docs/a.md", "status": "renamed"},
                       {"filename": "docs/a.md", "status": "mystery"},
                       {"filename": "../apps/apple/A.swift", "status": "modified"},
                       {"filename": "apps//apple/A.swift", "status": "modified"},
                       {"filename": "/apps/apple/A.swift", "status": "modified"},
                       {"filename": "docs/a.md\nrun=false", "status": "modified"},
                       {"filename": None, "status": "modified"}):
            with self.subTest(record=record), self.assertRaises(ci.IncompleteChanges):
                ci.record_paths([record])


class QualificationAndCliTests(unittest.TestCase):
    def test_push_manual_reusable_release_and_unknown_events_run_every_job(self):
        for name in ("push", "workflow_dispatch", "workflow_call", "release", "schedule", "unknown"):
            with self.subTest(name=name):
                result, _ = ci.determine_plan(arguments(event_name=name, files_json="missing.json"))
                self.assertEqual(ci.full_plan(), result)

    def test_explicit_reusable_qualification_and_release_sha_are_full(self):
        for values in ({"release_sha": "a" * 40}, {"force_full_qualification": "true"},
                       {"force_full_qualification": "invalid"}, {"force_full_qualification": ""}):
            with self.subTest(values=values):
                result, _ = ci.determine_plan(arguments(files_json="missing.json", **values))
                self.assertEqual(ci.full_plan(), result)

    def test_invalid_event_api_errors_or_malformed_offline_lists_run_every_job(self):
        for contents in ("not JSON", "[]", '{"pull_request": {}}'):
            with tempfile.TemporaryDirectory() as directory:
                event = Path(directory) / "event.json"
                event.write_text(contents)
                result, _ = ci.determine_plan(arguments(event_path=str(event)))
                self.assertEqual(ci.full_plan(), result)
        with tempfile.TemporaryDirectory() as directory:
            event = Path(directory) / "event.json"
            event.write_text(json.dumps(ChangeCompletenessTests.event(1)))
            with patch.object(ci.urllib.request, "urlopen", side_effect=OSError("controlled API failure")):
                result, _ = ci.determine_plan(arguments(event_path=str(event)))
            self.assertEqual(ci.full_plan(), result)
        for records in ({"not": "a list"}, ["docs/../hidden"], ["docs/a.md"] * 3000):
            with tempfile.TemporaryDirectory() as directory:
                source = Path(directory) / "files.json"
                source.write_text(json.dumps(records))
                result, _ = ci.determine_plan(arguments(files_json=str(source)))
                self.assertEqual(ci.full_plan(), result)

    def test_cli_writes_every_boolean_output_and_can_never_reduce_push(self):
        for event_name, selected in (("pull_request", {"prepare", "macos", "policy"}), ("push", set(ci.ALL))):
            with self.subTest(event=event_name), tempfile.TemporaryDirectory() as directory:
                source, output = Path(directory) / "files.json", Path(directory) / "output"
                source.write_text(json.dumps(["apps/apple/docs/guide.md"]))
                subprocess.run([sys.executable, str(SCRIPT), "--event-name", event_name,
                                "--files-json", str(source), "--output", str(output)],
                               check=True, capture_output=True, text=True,
                               env=dict(os.environ, FORCE_FULL_QUALIFICATION="false", PYTHONDONTWRITEBYTECODE="1"))
                actual = dict(line.split("=", 1) for line in output.read_text().splitlines())
                self.assertEqual({"run": "true", **{job: str(job in selected).lower() for job in ci.JOBS}}, actual)


if __name__ == "__main__":
    unittest.main()
