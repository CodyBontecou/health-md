#!/usr/bin/env python3
"""Run the real resolver/guards from YAML against tiny local Git repositories."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

from workflow_policy import ROOT, context, render, workflow

RELEASES = ("release-ios.yml", "release-macos.yml")
POLICY_PATH = ".github/scripts/apple_release_source.py"


class AppleReleaseSourceTests(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="healthmd-release-policy-")
        self.addCleanup(self.directory.cleanup)
        self.root = Path(self.directory.name)
        self.repo = self.root / "source"
        self.repo.mkdir()
        self.git("init", "-q", "-b", "main")
        self.git("config", "user.email", "policy@example.invalid")
        self.git("config", "user.name", "Synthetic release policy")
        self.write(".gitignore", "build/\n__pycache__/\n")
        self.write("apps/apple/HealthMd.xcodeproj/project.pbxproj", """MARKETING_VERSION = 3.0;
CURRENT_PROJECT_VERSION = 202610040000;
62D100002F60B00000A10000 /* notelet */ = {
    repositoryURL = notelet;
};
62D100012F60B00000A10000 /* Notelet */ = {
    productName = Notelet;
};
62D100022F60B00000A10000 /* build file */ = {
    productRef = 62D100012F60B00000A10000;
};
""")
        self.write("apps/apple/HealthMd/App.swift", "// immutable app source\n")
        self.write(".github/workflows/apple-ci.yml", "# initial workflow\n")
        if (ROOT / POLICY_PATH).exists():
            self.write(POLICY_PATH, (ROOT / POLICY_PATH).read_text())
        self.tag_sha = self.commit("release source")
        self.git("tag", "-a", "v3.0", "-m", "synthetic release")
        self.tag_object = self.git("rev-parse", "refs/tags/v3.0")
        self.remote = self.root / "origin.git"
        self.runner_temp = self.root / "runner"
        self.runner_temp.mkdir()

    def git(self, *args, repo=None):
        return subprocess.check_output(["git", "-C", str(repo or self.repo), *args], text=True,
                                       stderr=subprocess.PIPE).strip()

    def write(self, path, content):
        target = self.repo / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_text(content)

    def commit(self, message):
        self.git("add", ".")
        self.git("commit", "-q", "-m", message)
        return self.git("rev-parse", "HEAD")

    def workflow_fix(self):
        self.write(".github/workflows/apple-ci.yml", "# workflow-only infrastructure fix\n")
        return self.commit("workflow fix")

    def publish_fixture(self):
        # Local clone only: tests never push, dispatch, or contact GitHub.
        self.git("clone", "--quiet", "--bare", str(self.repo), str(self.remote))
        self.git("remote", "add", "origin", str(self.remote))
        self.git("fetch", "--quiet", "origin")

    def event(self, name, *, event="workflow_dispatch", release_tag="v3.0", dry_run=False, ref="refs/heads/main"):
        result = context(workflow(name)["name"], event=event,
                         tag="v3.0" if event == "release" else "", release_tag=release_tag)
        result["github"]["sha"] = self.git("rev-parse", "HEAD")
        result["github"]["ref"] = ref
        result["github"]["ref_name"] = ref.rsplit("/", 1)[-1]
        result["github"]["event"]["inputs"]["dry_run"] = "true" if dry_run else "false"
        result["inputs"]["dry_run"] = dry_run
        return result

    def run_step(self, step, event, *, repo=None, extra_env=None, working_directory=""):
        env = os.environ.copy()
        env.update({"GITHUB_SHA": event["github"]["sha"],
                    "GITHUB_EVENT_NAME": event["github"]["event_name"],
                    "GITHUB_REF": event["github"]["ref"],
                    "GITHUB_REF_NAME": event["github"]["ref_name"],
                    "GITHUB_OUTPUT": str(self.root / "outputs"),
                    "RUNNER_TEMP": str(self.runner_temp)})
        env.update(extra_env or {})
        env.update({key: render(str(value), event) for key, value in step.get("env", {}).items()})
        return subprocess.run(["bash", "-e", "-o", "pipefail", "-c", render(step["run"], event)],
                              cwd=(repo or self.repo) / working_directory, env=env,
                              capture_output=True, text=True)

    def resolve(self, name, event=None):
        step = next(s for s in workflow(name)["jobs"]["resolve-release-sha"]["steps"] if s.get("id") == "resolve")
        (self.root / "outputs").write_text("")
        result = self.run_step(step, event or self.event(name))
        output = dict(line.split("=", 1) for line in (self.root / "outputs").read_text().splitlines() if "=" in line)
        return result, output

    def assert_resolves(self, name, event=None, sha=None):
        result, output = self.resolve(name, event)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertEqual(output["sha"], sha or self.tag_sha)
        return output

    def assert_rejected(self, name, event=None):
        result, _ = self.resolve(name, event)
        self.assertNotEqual(result.returncode, 0, "unsafe source accepted: " + result.stdout)

    def archive_fixture(self, name, event, output):
        event["needs"] = {"resolve-release-sha": {"outputs": output}}
        job = workflow(name)["jobs"]["release"]
        checkout = next(step for step in job["steps"]
                        if step.get("uses", "").startswith("actions/checkout@"))
        self.assertEqual(render(checkout["with"]["ref"], event), output["sha"])
        archive = self.root / name.removesuffix(".yml")
        self.git("clone", "--quiet", "--branch", output["tag"] or "main",
                 str(self.remote), str(archive))
        self.assertEqual(self.git("rev-parse", "HEAD", repo=archive), output["sha"])
        env = {key: render(value, event) for key, value in job["env"].items()}
        load = next(step for step in job["steps"] if step["name"] == "Load current workflow release policy")
        result = self.run_step(load, event, repo=archive, extra_env=env, working_directory="apps/apple")
        self.assertEqual(result.returncode, 0, result.stderr)
        return archive, env

    def guard(self, name, label, event, archive, env):
        step = next(step for step in workflow(name)["jobs"]["release"]["steps"] if step["name"] == label)
        return self.run_step(step, event, repo=archive, extra_env=env, working_directory="apps/apple")

    def test_archive_guards_accept_only_the_clean_qualified_recovery_source(self):
        self.workflow_fix()
        self.publish_fixture()
        for name in RELEASES:
            event = self.event(name)
            output = self.assert_resolves(name, event)
            archive, env = self.archive_fixture(name, event, output)
            for label in ("Verify qualified source at checkout", "Verify qualified source before archive",
                          "Verify qualified source after archive", "Verify qualified source before publication"):
                with self.subTest(workflow=name, guard=label):
                    result = self.guard(name, label, event, archive, env)
                    self.assertEqual(result.returncode, 0, result.stderr)

    def test_archive_guards_reject_tracked_staged_and_untracked_mutations(self):
        self.publish_fixture()
        for name in RELEASES:
            event = self.event(name)
            archive, env = self.archive_fixture(name, event, self.assert_resolves(name, event))
            source = archive / "apps/apple/HealthMd/App.swift"
            for staged in (False, True):
                source.write_text("// changed after qualification\n")
                if staged:
                    self.git("add", str(source), repo=archive)
                with self.subTest(workflow=name, staged=staged):
                    self.assertNotEqual(self.guard(name, "Verify qualified source before archive",
                                                   event, archive, env).returncode, 0)
                self.git("restore", "--source=HEAD", "--staged", "--worktree", str(source), repo=archive)
            unexpected = archive / "unexpected.swift"
            unexpected.write_text("// outside component, still unsafe\n")
            self.assertNotEqual(self.guard(name, "Verify qualified source before publication",
                                           event, archive, env).returncode, 0)
            unexpected.unlink()
            (archive / "build").mkdir()
            (archive / "build/ignored-artifact").write_text("synthetic build product")
            self.assertEqual(self.guard(name, "Verify qualified source after archive",
                                       event, archive, env).returncode, 0)

    def test_tag_movement_after_qualification_blocks_archive_and_publication(self):
        newer_sha = self.workflow_fix()
        self.publish_fixture()
        archives = []
        for name in RELEASES:
            event = self.event(name)
            archives.append((name, event, *self.archive_fixture(name, event, self.assert_resolves(name, event))))
        self.git("update-ref", "refs/tags/v3.0", newer_sha, repo=self.remote)
        for name, event, archive, env in archives:
            for label in ("Verify qualified source before archive", "Verify qualified source before publication"):
                with self.subTest(workflow=name, guard=label):
                    self.assertNotEqual(self.guard(name, label, event, archive, env).returncode, 0)

    def test_same_commit_retagging_still_violates_the_retained_tag_object(self):
        self.git("tag", "-a", "v3.0-replacement", "-m", "different tag annotation", self.tag_sha)
        replacement = self.git("rev-parse", "refs/tags/v3.0-replacement")
        self.publish_fixture()
        archives = []
        for name in RELEASES:
            event = self.event(name)
            output = self.assert_resolves(name, event)
            self.assertEqual(output["tag_object"], self.tag_object)
            archives.append((name, event, *self.archive_fixture(name, event, output)))
        self.git("update-ref", "refs/tags/v3.0", replacement, repo=self.remote)
        self.assertEqual(self.git("rev-parse", "refs/tags/v3.0^{commit}", repo=self.remote), self.tag_sha)
        for name, event, archive, env in archives:
            with self.subTest(workflow=name):
                self.assertNotEqual(self.guard(name, "Verify qualified source before publication",
                                               event, archive, env).returncode, 0)

    def test_branch_dry_run_guard_cannot_be_reused_for_a_real_submission(self):
        self.publish_fixture()
        for name in RELEASES:
            event = self.event(name, release_tag="", dry_run=True)
            output = self.assert_resolves(name, event)
            archive, env = self.archive_fixture(name, event, output)
            self.assertEqual(self.guard(name, "Verify qualified source before archive",
                                       event, archive, env).returncode, 0)
            env["RELEASE_DRY_RUN"] = "false"
            self.assertNotEqual(self.guard(name, "Verify qualified source before publication",
                                           event, archive, env).returncode, 0)

    def test_recovery_can_use_policy_absent_from_the_original_tag(self):
        # A historical product commit need not contain the new workflow guard.
        (self.repo / POLICY_PATH).unlink()
        project = self.repo / "apps/apple/HealthMd.xcodeproj/project.pbxproj"
        project.write_text(project.read_text().replace("MARKETING_VERSION = 3.0;", "MARKETING_VERSION = 3.0.0;"))
        self.tag_sha = self.commit("historical release before workflow guard")
        self.git("tag", "v3.0.0")
        self.write(POLICY_PATH, (ROOT / POLICY_PATH).read_text())
        self.workflow_fix()
        self.publish_fixture()
        for name in RELEASES:
            event = self.event(name, release_tag="v3.0.0")
            archive, env = self.archive_fixture(name, event, self.assert_resolves(name, event))
            self.assertFalse((archive / POLICY_PATH).exists())
            result = self.guard(name, "Verify qualified source before archive", event, archive, env)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(self.git("status", "--porcelain", repo=archive), "")

    def test_version_mismatch_and_unpushed_tag_identity_fail_before_qualification(self):
        self.git("tag", "v3.1")
        self.workflow_fix()
        self.publish_fixture()
        for name in RELEASES:
            with self.subTest(workflow=name, failure="version"):
                self.assert_rejected(name, self.event(name, release_tag="v3.1"))
        self.git("update-ref", "refs/tags/v3.0", self.git("rev-parse", "HEAD"))
        for name in RELEASES:
            with self.subTest(workflow=name, failure="unpushed tag"):
                self.assert_rejected(name)

    def test_lightweight_tags_preserve_the_existing_apple_tag_contract(self):
        self.git("update-ref", "refs/tags/v3.0", self.tag_sha)
        self.publish_fixture()
        for name in RELEASES:
            with self.subTest(workflow=name):
                output = self.assert_resolves(name)
                self.assertEqual(output["tag_object"], self.tag_sha)

    def test_canonical_human_publication_and_tag_dispatch_resolve_the_tag(self):
        self.publish_fixture()
        for name in RELEASES:
            for event in (self.event(name, event="release", release_tag="", ref="refs/tags/v3.0"),
                          self.event(name, release_tag="", ref="refs/tags/v3.0")):
                with self.subTest(workflow=name, event=event["github"]["event_name"]):
                    self.assert_resolves(name, event)

    def test_workflow_only_main_recovery_preserves_original_source(self):
        newer_sha = self.workflow_fix()
        self.publish_fixture()
        self.assertNotEqual(self.tag_sha, newer_sha)
        for name in RELEASES:
            with self.subTest(workflow=name):
                self.assert_resolves(name)

    def test_untagged_branch_is_testing_only(self):
        self.publish_fixture()
        for name in RELEASES:
            with self.subTest(workflow=name):
                self.assert_resolves(name, self.event(name, release_tag="", dry_run=True))
                self.assert_rejected(name, self.event(name, release_tag=""))

    def test_recovery_rejects_product_changes_even_when_pushed_to_main(self):
        self.write("apps/apple/HealthMd/App.swift", "// changed app after release\n")
        self.commit("product changed")
        self.publish_fixture()
        for name in RELEASES:
            with self.subTest(workflow=name):
                self.assert_rejected(name)

    def test_recovery_requires_a_main_workflow_dispatch(self):
        self.workflow_fix()
        self.publish_fixture()
        for name in RELEASES:
            with self.subTest(workflow=name):
                self.assert_rejected(name, self.event(name, ref="refs/heads/testing"))

    def test_release_source_and_workflow_must_be_reachable_from_remote_main(self):
        newer_sha = self.workflow_fix()
        self.publish_fixture()
        self.git("update-ref", "refs/heads/main", self.tag_sha, repo=self.remote)
        for name in RELEASES:
            with self.subTest(workflow=name, source="workflow"):
                self.assert_rejected(name)
        # Now neither the tag nor workflow is reachable from remote main.
        unrelated_tree = self.git("rev-parse", newer_sha + "^{tree}")
        unrelated = subprocess.check_output(["git", "-C", str(self.repo), "commit-tree", unrelated_tree,
                                             "-m", "unrelated main"], text=True).strip()
        self.git("fetch", "--quiet", str(self.repo), unrelated, repo=self.remote)
        self.git("update-ref", "refs/heads/main", unrelated, repo=self.remote)
        # Drop the stale local tracking ref to allow refresh from unrelated history.
        self.git("update-ref", "-d", "refs/remotes/origin/main")
        for name in RELEASES:
            with self.subTest(workflow=name, source="tag"):
                self.assert_rejected(name)

    def test_only_real_apple_tags_are_accepted_not_branches_or_revision_expressions(self):
        self.git("update-ref", "refs/heads/v4.0", self.tag_sha)
        self.git("tag", "healthmd-cli/v1.2.3")
        self.git("tag", "android/v1.9.1")
        self.publish_fixture()
        for name in RELEASES:
            for tag in ("v4.0", "v3.0^{}", "android/v1.9.1", "healthmd-cli/v1.2.3"):
                with self.subTest(workflow=name, tag=tag):
                    self.assert_rejected(name, self.event(name, release_tag=tag))

    def test_dirty_source_is_rejected_including_staged_and_untracked_files(self):
        self.publish_fixture()
        for name in RELEASES:
            for staged in (False, True):
                self.write("apps/apple/HealthMd/App.swift", "// dirty archive\n")
                if staged:
                    self.git("add", "apps/apple/HealthMd/App.swift")
                with self.subTest(workflow=name, staged=staged):
                    self.assert_rejected(name)
                self.git("restore", "--source=HEAD", "--staged", "--worktree", "apps/apple/HealthMd/App.swift")
            self.write("unexpected-source.swift", "// untracked source\n")
            with self.subTest(workflow=name, untracked=True):
                self.assert_rejected(name)
            (self.repo / "unexpected-source.swift").unlink()

    def test_macos_does_not_rewrite_the_tagged_project_before_archiving(self):
        event = self.event("release-macos.yml")
        for step in workflow("release-macos.yml")["jobs"]["release"]["steps"]:
            if step["name"] == "Remove iOS-only Swift packages from macOS release workspace":
                result = self.run_step(step, event, working_directory="apps/apple")
                self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.git("status", "--porcelain"), "",
                         "editing project.pbxproj makes the archive differ from the qualified clean tag")


if __name__ == "__main__":
    unittest.main()
