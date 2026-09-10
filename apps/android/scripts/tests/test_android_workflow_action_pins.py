#!/usr/bin/env python3
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
WORKFLOWS = sorted((ROOT / ".github/workflows").glob("android-*.yml"))
USES = re.compile(r"^\s*(?:-\s*)?uses:\s*([^\s#]+)", re.MULTILINE)
PINNED = re.compile(r"^[^./][^@]*@[0-9a-f]{40}$")


class AndroidWorkflowActionPinPolicyTest(unittest.TestCase):
    def test_every_external_action_in_release_and_provenance_path_is_commit_pinned(self) -> None:
        failures: list[str] = []
        for workflow in WORKFLOWS:
            for reference in USES.findall(workflow.read_text()):
                if reference.startswith("./"):
                    continue
                if not PINNED.fullmatch(reference):
                    failures.append(f"{workflow.relative_to(ROOT)}: {reference}")
        self.assertEqual([], failures, "mutable external action refs:\n" + "\n".join(failures))

    def test_protected_evidence_checkout_is_annotated_tagged_and_main_reachable(self) -> None:
        workflow = (ROOT / ".github/workflows/android-wear-evidence.yml").read_text()
        required = (
            'release_tag="android/v$VERSION"',
            'git cat-file -t "$release_tag"',
            'git rev-parse "$release_tag^{commit}"',
            'git merge-base --is-ancestor "$EXPECTED_SHA" refs/remotes/origin/main',
        )
        self.assertEqual([], [needle for needle in required if needle not in workflow])

    def test_phone_upload_is_exact_annotated_tag_and_retains_sha_bound_receipt(self) -> None:
        release = (ROOT / ".github/workflows/android-release.yml").read_text()
        required = (
            'git cat-file -t "$RELEASE_TAG"',
            'git rev-parse "$RELEASE_TAG^{commit}"',
            'healthmd-android-phone-upload-${{ steps.version.outputs.version }}-${{ steps.version.outputs.release_sha }}-attempt-${{ github.run_attempt }}',
            'phoneAabSha256:$aab',
            'wearIncluded:false',
            'uploadPrepared:true',
            'Retain immutable phone upload intent receipt',
        )
        self.assertEqual([], [needle for needle in required if needle not in release])

    def test_deferred_wear_evidence_workflow_retains_its_own_provenance_guards(self) -> None:
        evidence = (ROOT / ".github/workflows/android-wear-evidence.yml").read_text()
        required = (
            'qa_upload_run_id:',
            'path == ".github/workflows/android-release.yml"',
            'submission_run_attempt:',
            'path == ".github/workflows/android-wear-screenshots.yml"',
            'attempts/${run_attempt}',
            'remoteCiRunAttempt:$ciAttempt',
            'ingestRunAttempt:$ingestAttempt',
            'qaPhoneAabSha256:$phoneAab',
            'qaWearAabSha256:$wearAab',
            'qa-upload/jobs.json',
        )
        self.assertEqual([], [needle for needle in required if needle not in evidence])

    def test_screenshot_mutation_is_protected_exact_tag_and_attempt_bound(self) -> None:
        workflow = (ROOT / ".github/workflows/android-wear-screenshots.yml").read_text()
        required = (
            "environment: google-play-qa",
            'test "$GITHUB_REF_NAME" = "$tag"',
            'git cat-file -t "$tag"',
            'git rev-parse "$tag^{commit}"',
            'submission_run_attempt:',
            'path == ".github/workflows/android-wear-evidence-submit.yml"',
            "./scripts/sync-google-play-wear-screenshots.sh",
            "Upload protected screenshot mutation evidence",
        )
        self.assertEqual([], [needle for needle in required if needle not in workflow])

    def test_production_dispatch_runs_only_from_the_exact_annotated_release_tag(self) -> None:
        workflow = (ROOT / ".github/workflows/android-promote-production.yml").read_text()
        required = (
            'test "$GITHUB_REF_NAME" = "android/v$VERSION"',
            'git cat-file -t "$GITHUB_REF_NAME"',
            'git rev-parse "$GITHUB_REF_NAME^{commit}"',
            'git merge-base --is-ancestor "$tagged_sha" refs/remotes/origin/main',
        )
        self.assertEqual([], [needle for needle in required if needle not in workflow])
        self.assertNotIn("ops/android-production-", workflow)

    def test_play_credential_is_materialized_only_after_build_and_artifact_retention(self) -> None:
        workflow = (ROOT / ".github/workflows/android-release.yml").read_text()
        play = workflow.index("Configure ephemeral Google Play credential")
        build = workflow.index("Build signed phone app bundle")
        cleanup = workflow.index("Remove ephemeral signing credentials after inspection")
        retain = workflow.index("Retain signed phone bundle with native debug symbols")
        upload = workflow.index("Upload phone bundle to Internal Testing")
        self.assertLess(build, cleanup)
        self.assertLess(cleanup, retain)
        self.assertLess(retain, play)
        self.assertLess(play, upload)


if __name__ == "__main__":
    unittest.main()
