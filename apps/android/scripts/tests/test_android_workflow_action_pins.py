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
            'healthmd-android-phone-upload-${{ needs.build-signed-phone.outputs.version }}-${{ needs.build-signed-phone.outputs.release_sha }}-attempt-${{ github.run_attempt }}',
            'phoneAabSha256:$aab',
            'wearIncluded:false',
            'uploadPrepared:true',
            'Verify retained exact-SHA Android qualification',
            'recoveryQualificationRunId:$qualificationRunId',
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

    def test_production_dispatch_uses_exact_release_source_or_constrained_recovery_tag(self) -> None:
        workflow = (ROOT / ".github/workflows/android-promote-production.yml").read_text()
        required = (
            'expected_tag="android/v$VERSION"',
            'git cat-file -t "$expected_tag"',
            'git rev-parse "$expected_tag^{commit}"',
            'git merge-base --is-ancestor "$tagged_sha" refs/remotes/origin/main',
            '[[ "$GITHUB_REF_NAME" == android/recovery/* ]]',
            'test "$(git rev-parse HEAD)" = "$tagged_sha"',
            'workflowRecovery:$recovery',
        )
        self.assertEqual([], [needle for needle in required if needle not in workflow])
        self.assertNotIn("ops/android-production-", workflow)

    def test_play_access_audit_is_tag_bound_and_cannot_commit_or_upload(self) -> None:
        workflow = (ROOT / ".github/workflows/android-google-play-access-audit.yml").read_text()
        required = (
            "environment: google-play",
            "environment: google-play-qa",
            '[[ "$GITHUB_REF_NAME" == android/v* || "$GITHUB_REF_NAME" == android/recovery/* ]]',
            'git cat-file -t "$tag"',
            'git merge-base --is-ancestor "$release_sha" refs/remotes/origin/main',
            "emptyEditInsertDeleteVerified:true",
            "registeredUploadCertificateMatched:true",
            "expected_sha1='805f26eafd9ed5c37fc72a65636cffa4d101812f'",
            "privateKeyRetained:false",
            "noPlayEditCommit:true",
        )
        self.assertEqual([], [needle for needle in required if needle not in workflow])
        self.assertNotIn(":commit", workflow)
        self.assertNotIn("/bundles", workflow)
        self.assertNotIn("PLAY_CONSOLE_KEY_JSON", workflow)

    def test_workload_identity_is_requested_only_after_build_and_artifact_retention(self) -> None:
        workflow = (ROOT / ".github/workflows/android-release.yml").read_text()
        auth = workflow.index("Authenticate to Google Play with protected Workload Identity")
        build = workflow.index("Build signed phone app bundle")
        cleanup = workflow.index("Remove ephemeral signing credentials after inspection")
        retain = workflow.index("Retain signed phone bundle with native debug symbols")
        upload = workflow.index("Upload phone bundle to Internal Testing")
        self.assertLess(build, cleanup)
        self.assertLess(cleanup, retain)
        self.assertLess(retain, auth)
        self.assertLess(auth, upload)
        self.assertIn("environment: google-play-qa", workflow)
        self.assertIn("environment: google-play", workflow)
        self.assertIn("actions/download-artifact@fa0a91b85d4f404e444e00e005971372dc801d16", workflow)
        self.assertIn("registered_sha1='805f26eafd9ed5c37fc72a65636cffa4d101812f'", workflow)
        self.assertIn("id-token: write", workflow)
        self.assertNotIn("PLAY_CONSOLE_KEY_JSON", workflow)

    def test_ci_sdk_setup_does_not_request_the_retired_tools_package(self) -> None:
        for filename in ("android-ci.yml",):
            lines = (ROOT / ".github/workflows" / filename).read_text().splitlines()
            setups = 0
            for index, line in enumerate(lines):
                if "uses: android-actions/setup-android@" not in line:
                    continue
                setups += 1
                block: list[str] = []
                for following in lines[index + 1:]:
                    if re.match(r"^\s*-\s+(?:name|uses|run):", following):
                        break
                    block.append(following)
                self.assertIn(
                    "packages: platform-tools", "\n".join(block),
                    f"{filename}:{index + 1} inherits the action's retired tools package",
                )
            self.assertGreater(setups, 0, f"No SDK setup exercised in {filename}")

    def test_instrumentation_unlocks_the_synthetic_emulator_and_retains_failure_reports(self) -> None:
        workflow = (ROOT / ".github/workflows/android-ci.yml").read_text()
        instrumentation = workflow.index(":app:connectedFdroidDebugAndroidTest")
        for command in ("shell input keyevent KEYCODE_WAKEUP", "shell wm dismiss-keyguard"):
            self.assertLess(workflow.index(command), instrumentation)
        diagnostics = workflow.split("- name: Retain instrumentation reports and per-test results", 1)[1].split("\n  fdroid:", 1)[0]
        for required in (
            "if: ${{ always() }}", "if-no-files-found: warn", "retention-days: 7",
            "apps/android/healthmd-core/build/outputs/androidTest-results/",
            "apps/android/app/build/outputs/androidTest-results/",
        ):
            self.assertIn(required, diagnostics)
    def test_ci_sdk_setup_explicitly_installs_supported_packages(self) -> None:
        for name in ("android-ci.yml", "practice-ci.yml"):
            workflow = (ROOT / ".github/workflows" / name).read_text()
            sdk_steps = [
                step
                for step in re.split(r"(?m)^      - ", workflow)
                if re.search(r"(?m)^\s*uses: android-actions/setup-android@", step)
            ]
            self.assertTrue(sdk_steps, f"{name} must set up the SDK")
            for step in sdk_steps:
                with self.subTest(workflow=name, step=step.splitlines()[0]):
                    packages = re.search(r"(?m)^\s+packages:\s*([^\n#]+)", step)
                    self.assertIsNotNone(
                        packages,
                        "Override setup-android's obsolete 'tools platform-tools' default",
                    )
                    self.assertEqual(["platform-tools"], packages.group(1).split())

    def test_instrumentation_declares_a_ready_software_ime_before_accessibility_tests(self) -> None:
        workflow = (ROOT / ".github/workflows/android-ci.yml").read_text()
        setting = "settings put secure show_ime_with_hard_keyboard 1"
        readiness = "settings get secure default_input_method"
        enabled = "shell ime list -s"
        instrumentation = ":app:connectedFdroidDebugAndroidTest"
        for requirement in (setting, readiness, enabled, instrumentation):
            self.assertIn(requirement, workflow)
        self.assertLess(workflow.index(setting), workflow.index(instrumentation))
        self.assertLess(workflow.index(readiness), workflow.index(instrumentation))
        self.assertLess(workflow.index(enabled), workflow.index(instrumentation))


if __name__ == "__main__":
    unittest.main()
