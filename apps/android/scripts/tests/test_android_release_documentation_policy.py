#!/usr/bin/env python3
from __future__ import annotations

import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[4]
ANDROID = ROOT / "apps/android"
DOCS = sorted(ANDROID.rglob("*.md")) + [
    ROOT / ".github/workflows/README.md",
    ROOT / "docs/migration/cutover-audit.md",
]
GRADLE_MUTATION = re.compile(
    r"(?:\./)?gradle(?:w)?\b[^\n]*(?:\bpublish[A-Z][A-Za-z]*\b|:[A-Za-z0-9_-]+:publish[A-Z][A-Za-z]*\b)"
)
DIRECT_PRODUCTION_FLAG = re.compile(r"(?:--play-track=production|--track\s+production)\b")
FASTLANE_COMMAND = re.compile(r"(?:bundle\s+exec\s+)?fastlane\s+[^\n`]+")
ALLOWED_FASTLANE_COMMAND = "bundle exec fastlane android validate_wear_release"
GPLAY_REFERENCE = re.compile(r"\bgplay\b(?P<tail>[^`\n]*)")
PUBLISHER_API_MUTATION = re.compile(
    r"(?:curl\b[^\n]*(?:-X|--request)\s*(?:POST|PUT|PATCH|DELETE)[^\n]*androidpublisher\.googleapis\.com|"
    r"androidpublisher\.googleapis\.com[^\n]*(?:edits|tracks)[^\n]*(?:POST|PUT|PATCH|DELETE))",
    re.IGNORECASE,
)


def normalize_shell_continuations(text: str) -> str:
    return re.sub(r"\\\s*\n\s*", " ", text)


def documentation_mutations(text: str) -> list[str]:
    normalized = normalize_shell_continuations(text)
    findings: list[str] = []
    for label, pattern in (
        ("Gradle publisher command", GRADLE_MUTATION),
        ("direct production flag", DIRECT_PRODUCTION_FLAG),
        ("Android Publisher API mutation", PUBLISHER_API_MUTATION),
    ):
        findings.extend(f"{label}: {match.group(0).strip()}" for match in pattern.finditer(normalized))

    for match in FASTLANE_COMMAND.finditer(normalized):
        command = " ".join(match.group(0).split())
        if command != ALLOWED_FASTLANE_COMMAND:
            findings.append(f"Fastlane mutation-capable command: {command}")

    # Documentation may mention the read-only validator (`gplay validate`) or the tool name alone.
    # Any option-bearing or other subcommand is forbidden because it can hide an upload/track edit.
    for match in GPLAY_REFERENCE.finditer(normalized):
        tail = match.group("tail").strip()
        if not tail or tail.startswith(":"):
            continue
        first = tail.split(maxsplit=1)[0]
        if first != "validate":
            findings.append(f"non-validation gplay command: gplay {tail}")
    return findings


class AndroidReleaseDocumentationPolicyTest(unittest.TestCase):
    def test_documentation_does_not_advertise_direct_play_mutation_commands(self) -> None:
        failures: list[str] = []
        for document in DOCS:
            failures.extend(
                f"{document.relative_to(ROOT)}: {finding}"
                for finding in documentation_mutations(document.read_text())
            )
        self.assertEqual(
            [],
            failures,
            "direct Play mutation guidance bypasses the paired protected release path:\n"
            + "\n".join(failures),
        )

    def test_detectors_reject_multiline_and_alternate_mutation_examples(self) -> None:
        examples = (
            "```bash\n./gradlew \\\n  publishReleaseBundle\n```",
            "Run `./gradlew :app:publishBundle`.",
            "bundle exec fastlane android ship_candidate",
            "gplay --project health-md tracks update production",
            "curl --request PUT \\\n  https://androidpublisher.googleapis.com/androidpublisher/v3/applications/x/edits/y/tracks/production",
        )
        for example in examples:
            with self.subTest(example=example):
                self.assertTrue(documentation_mutations(example))
        self.assertEqual([], documentation_mutations("Run `gplay validate listing` only."))
        self.assertEqual([], documentation_mutations(ALLOWED_FASTLANE_COMMAND))

    def test_operator_documents_name_the_paired_protected_tracks_and_workflows(self) -> None:
        for relative in (
            "apps/android/README.md",
            "apps/android/PLAY_STORE_COMMANDS.md",
            "apps/android/PLAY_STORE_SETUP.md",
            "apps/android/GRADLE_PLAY_PUBLISHER_SETUP.md",
            "apps/android/PLAY_CONSOLE_BROWSER_PROMPT.md",
            ".github/workflows/README.md",
        ):
            text = (ROOT / relative).read_text()
            with self.subTest(document=relative):
                self.assertIn("qa", text)
                self.assertIn("wear:qa", text)
                self.assertIn("production", text)
                self.assertIn("wear:production", text)
                self.assertIn("android-release.yml", text)
                self.assertIn("android-wear-screenshots.yml", text)
                self.assertIn("android-promote-production.yml", text)

    def test_docs_do_not_advertise_local_screenshot_mutation(self) -> None:
        failures = [
            str(document.relative_to(ROOT))
            for document in DOCS
            if "./scripts/sync-google-play-wear-screenshots.sh" in document.read_text()
        ]
        self.assertEqual([], failures, "local screenshot mutation bypass is documented")

    def test_browser_prompt_is_strictly_read_only_for_release_and_metadata(self) -> None:
        prompt = (ANDROID / "PLAY_CONSOLE_BROWSER_PROMPT.md").read_text()
        required = (
            "This prompt is **read-only**.",
            "Do not save or submit any change.",
            "Never upload an AAB, create/edit a release",
            "The only supported AAB upload is `.github/workflows/android-release.yml`",
            "The only supported production mutation is `.github/workflows/android-promote-production.yml`",
            "Do not save any section.",
        )
        forbidden = (
            "only after explicit approval",
            "without my explicit approval",
            "save drafts",
            "Upload only locales",
            "Release → Testing or production, only after",
        )
        self.assertEqual([], [needle for needle in required if needle not in prompt])
        self.assertEqual([], [needle for needle in forbidden if needle in prompt])

    def test_local_setup_does_not_provision_mutation_credentials(self) -> None:
        setup = (ANDROID / "PLAY_STORE_SETUP.md").read_text()
        self.assertIn(
            "Do not place a QA or production mutation key on a developer workstation",
            setup,
        )
        self.assertIn("Optional local read-only inspection", setup)
        self.assertNotIn("Save it outside the repository, for example", setup)
        self.assertNotIn("permissions needed to upload and manage", setup)

    def test_module_level_gradle_play_publisher_is_removed(self) -> None:
        catalog = (ANDROID / "gradle/libs.versions.toml").read_text()
        self.assertNotIn("com.github.triplet.play", catalog)
        self.assertNotIn("playPublisher", catalog)
        self.assertNotIn("play-publisher", catalog)
        for relative in ("app/build.gradle.kts", "wear/build.gradle.kts"):
            script = (ANDROID / relative).read_text()
            with self.subTest(script=relative):
                self.assertNotIn("libs.plugins.play.publisher", script)
                self.assertNotRegex(script, r"(?m)^play\s*\{")
                self.assertNotIn("serviceAccountCredentials", script)

    def test_fastlane_has_no_play_mutation_lane(self) -> None:
        fastfile = (ANDROID / "fastlane/Fastfile").read_text()
        forbidden = (
            "upload_to_play_store",
            "supply(",
            "lane :internal",
            "lane :beta",
            "lane :production",
            "lane :deploy",
        )
        self.assertEqual([], [needle for needle in forbidden if needle in fastfile])
        self.assertIsNone(GRADLE_MUTATION.search(normalize_shell_continuations(fastfile)))
        self.assertIn("lane :validate_wear_release", fastfile)

    def test_android_workflows_do_not_invoke_module_level_play_publishers(self) -> None:
        failures: list[str] = []
        for workflow in sorted((ROOT / ".github/workflows").glob("android-*.yml")):
            text = normalize_shell_continuations(workflow.read_text())
            if GRADLE_MUTATION.search(text) or "upload_to_play_store" in text or "supply(" in text:
                failures.append(str(workflow.relative_to(ROOT)))
            for command in FASTLANE_COMMAND.findall(text):
                if " ".join(command.split()) != ALLOWED_FASTLANE_COMMAND:
                    failures.append(f"{workflow.relative_to(ROOT)}: {command.strip()}")
        self.assertEqual([], failures, "workflow bypasses paired Play scripts:\n" + "\n".join(failures))

    def test_scanned_cross_component_runbooks_trigger_main_push_ci(self) -> None:
        ci = (ROOT / ".github/workflows/android-ci.yml").read_text()
        self.assertIn("- '.github/workflows/README.md'", ci)
        self.assertIn("- '.github/workflows/android-*.yml'", ci)
        self.assertIn("- 'docs/migration/**'", ci)


if __name__ == "__main__":
    unittest.main()
