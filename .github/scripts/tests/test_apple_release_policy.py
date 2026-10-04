#!/usr/bin/env python3
"""Deterministic checks of both store release workflows (no native/store work)."""

import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

import yaml

from workflow_policy import ROOT, context, permitted, render, workflow

RELEASES = ("release-ios.yml", "release-macos.yml")


class AppleReleasePolicyTests(unittest.TestCase):
    def test_rejected_publications_never_resolve_or_qualify(self):
        for name in RELEASES:
            caller = workflow(name)
            for tag, author in (("healthmd-cli/v1.2.3", "human"),
                                ("android/v1.9.1", "human"),
                                ("v3.0", "github-actions[bot]"),
                                ("v3.0", "healthmd-release[bot]")):
                event = context(caller["name"], event="release", tag=tag, author=author)
                for job in ("resolve-release-sha", "qualify", "release"):
                    with self.subTest(workflow=name, tag=tag, author=author, job=job):
                        self.assertFalse(permitted(caller["jobs"][job], event),
                                         "ineligible publications must not allocate Apple runners")

    def test_manual_and_human_apple_release_paths_remain_eligible(self):
        for name in RELEASES:
            caller = workflow(name)
            for event in (context(caller["name"], release_tag="v3.0"),
                          context(caller["name"], event="release", tag="v3.0")):
                for job in ("resolve-release-sha", "qualify", "release"):
                    with self.subTest(workflow=name, event=event["github"]["event_name"], job=job):
                        self.assertTrue(permitted(caller["jobs"][job], event))

    def test_every_native_qualification_checkout_uses_the_release_sha(self):
        ci = workflow("apple-ci.yml")
        event = context("Apple Release iOS", release_tag="v3.0")
        event["inputs"]["release_sha"] = "old-tag-sha"
        source_jobs = set(ci["jobs"]["gate"]["needs"]) - {"changes", "workflow-policy"}
        for name in sorted(source_jobs):
            step = next(step for step in ci["jobs"][name]["steps"]
                        if step.get("uses", "").startswith("actions/checkout@"))
            with self.subTest(job=name):
                self.assertEqual(render(step["with"]["ref"], event), "old-tag-sha")

    def test_release_changes_trigger_policy_and_apple_gates_with_synchronized_path_maps(self):
        ci = workflow("apple-ci.yml")
        step = next(step for step in ci["jobs"]["changes"]["steps"] if step.get("id") == "detect")
        self.assertEqual(set(ci["on"]["push"]["paths"]), set(step["with"]["paths"].splitlines()))
        for path in (".github/workflows/release-ios.yml", ".github/workflows/release-macos.yml", ".github/scripts/**"):
            self.assertIn(path, ci["on"]["push"]["paths"])
        self.assertIn("workflow-policy", ci["jobs"]["gate"]["needs"])
        self.assertIn("test_apple_*.py", ci["jobs"]["workflow-policy"]["steps"][-1]["run"])

    def test_reusable_release_qualification_always_requests_full_apple_checks(self):
        action = yaml.load((ROOT / ".github/actions/component-changes/action.yml").read_text(), Loader=yaml.BaseLoader)
        script = action["runs"]["steps"][0]["run"]
        with tempfile.TemporaryDirectory() as directory:
            output = Path(directory) / "outputs"
            for event in ("release", "workflow_dispatch", "workflow_call"):
                output.write_text("")
                result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", script], capture_output=True,
                                        text=True, env={**os.environ, "EVENT_NAME": event, "COMPONENT": "Apple CI",
                                                       "GITHUB_OUTPUT": str(output)})
                with self.subTest(event=event):
                    self.assertEqual(result.returncode, 0, result.stderr)
                    self.assertEqual(output.read_text().strip(), "run=true")

    def test_full_apple_gate_rejects_failed_skipped_or_cancelled_checks(self):
        step = workflow("apple-ci.yml")["jobs"]["gate"]["steps"][0]
        script = step["run"]
        env = {key: "true" if key == "CHANGES_RUN" else "success" for key in step["env"]}

        def run(overrides):
            return subprocess.run(["bash", "-c", script], env={**os.environ, **env, **overrides},
                                  capture_output=True, text=True).returncode
        self.assertEqual(run({}), 0)
        for key in env.keys() - {"CHANGES_RUN"}:
            for result in ("failure", "skipped", "cancelled"):
                with self.subTest(check=key, result=result):
                    self.assertNotEqual(run({key: result}), 0)

    def test_archive_and_publication_are_surrounded_by_source_guards(self):
        for name in RELEASES:
            steps = workflow(name)["jobs"]["release"]["steps"]
            names = [step["name"] for step in steps]
            archive = next(i for i, step in enumerate(steps) if "xcodebuild archive" in step.get("run", ""))
            with self.subTest(workflow=name):
                self.assertEqual(names[archive - 1], "Verify qualified source before archive")
                self.assertEqual(names[archive + 1], "Verify qualified source after archive")
                upload = next(i for i, label in enumerate(names) if label.startswith("Upload "))
                self.assertEqual(names[upload - 1], "Verify qualified source before publication")
                self.assertTrue(all("gh release create" not in step.get("run", "") for step in steps))
                for step in steps:
                    if step["name"].startswith("Verify qualified source"):
                        self.assertNotIn("if", step)
                        self.assertIn("apple-release-source.py\" verify", step["run"])

    def test_existing_draft_is_required_before_qualification_not_created_after_upload(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            gh = root / "gh"
            gh.write_text("#!/usr/bin/env python3\nimport os, sys\n"
                          "assert sys.argv[1:3] == ['release', 'view']\n"
                          "print(os.environ['SYNTHETIC_RELEASE'])\n"
                          "sys.exit(int(os.environ.get('SYNTHETIC_EXIT', '0')))\n")
            gh.chmod(0o755)
            for name in RELEASES:
                caller = workflow(name)
                step = next(step for step in caller["jobs"]["resolve-release-sha"]["steps"]
                            if step["name"] == "Verify existing GitHub release record")
                event = context(caller["name"], release_tag="v3.0")
                event["steps"] = {"resolve": {"outputs": {"mode": "tag", "tag": "v3.0"}}}
                event["inputs"]["dry_run"] = False
                self.assertTrue(permitted(step, event))
                for trigger, draft, tag, status, accepted in (
                    ("workflow_dispatch", True, "v3.0", 0, True),
                    ("workflow_dispatch", False, "v3.0", 0, False),
                    ("workflow_dispatch", True, "v3.1", 0, False),
                    ("workflow_dispatch", True, "v3.0", 1, False),
                    ("release", False, "v3.0", 0, True),
                ):
                    env = {**os.environ, "PATH": str(root) + os.pathsep + os.environ["PATH"],
                           "RUNNER_TEMP": str(root), "GITHUB_REPOSITORY": "synthetic/repository",
                           "GITHUB_EVENT_NAME": trigger, "GH_TOKEN": "synthetic-not-a-secret",
                           "RELEASE_TAG": "v3.0", "SYNTHETIC_RELEASE": json.dumps({"tagName": tag, "isDraft": draft}),
                           "SYNTHETIC_EXIT": str(status)}
                    result = subprocess.run(["bash", "-e", "-o", "pipefail", "-c", step["run"]],
                                            capture_output=True, text=True, env=env)
                    with self.subTest(workflow=name, trigger=trigger, draft=draft, tag=tag, status=status):
                        self.assertEqual(result.returncode == 0, accepted, result.stderr)
                event["inputs"]["dry_run"] = True
                self.assertFalse(permitted(step, event))
                event["inputs"]["dry_run"] = False
                event["steps"]["resolve"]["outputs"]["mode"] = "branch"
                self.assertFalse(permitted(step, event))

    def test_recovery_archives_the_qualified_tag_sha_not_new_main(self):
        for name in RELEASES:
            caller = workflow(name)
            event = context(caller["name"], release_tag="v3.0")
            event["needs"] = {"resolve-release-sha": {"outputs": {"sha": "old-tag-sha"}}}
            qualified = render(caller["jobs"]["qualify"]["with"]["release_sha"], event)
            checkout = next(step for step in caller["jobs"]["release"]["steps"]
                            if step.get("uses", "").startswith("actions/checkout@"))
            archived = render(checkout.get("with", {}).get("ref", "${{ github.sha }}"), event)
            with self.subTest(workflow=name):
                self.assertEqual(qualified, "old-tag-sha")
                self.assertEqual(archived, qualified,
                                 "release_tag recovery uses newer workflow code, never newer product source")
                needs = caller["jobs"]["release"]["needs"]
                self.assertIn("resolve-release-sha", needs if isinstance(needs, list) else [needs])
                self.assertIn("qualify", needs if isinstance(needs, list) else [needs])


if __name__ == "__main__":
    unittest.main()
