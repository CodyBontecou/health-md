#!/usr/bin/env python3
"""Deterministic behavioral tests; live metadata is checked separately in Actions."""
import base64
from contextlib import redirect_stdout
from copy import deepcopy
import importlib.util
import io
import json
from pathlib import Path
import unittest
from urllib.error import HTTPError

spec = importlib.util.spec_from_file_location("availability", Path(__file__).with_name("audit-release-availability.py"))
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)
REPO, VERSION = "CodyBontecou/health-md", "0.1.0-alpha.6"
BASE = f"https://github.com/{REPO}/releases/download/healthmd-cli/v{VERSION}"


def release():
    return {
        "tag_name": f"healthmd-cli/v{VERSION}", "draft": False, "prerelease": True,
        "published_at": "2026-09-04T06:40:05Z", "html_url": BASE,
        "assets": [{"name": name, "state": "uploaded", "size": 1,
                    "browser_download_url": f"{BASE}/{name}"} for name in module.REQUIRED],
    }


def manifest():
    return "".join(f"{'a' * 64}  {name}\n" for name in module.REQUIRED
                   if name not in ("sha256.sum", "sha256.sum.sigstore.json"))


def formula():
    return f'version "{VERSION}"\n' + "".join(
        f'url "{BASE}/{name}"\nsha256 "{"a" * 64}"\n' for name in module.ARCHIVES
        if "windows" not in name and name.endswith(".tar.xz"))


class AvailabilityTests(unittest.TestCase):
    def test_published_preview_with_complete_asset_and_checksum_closure(self):
        self.assertEqual(len(module.validate_release(release(), REPO, VERSION)), len(module.REQUIRED))
        checksums = module.validate_checksums(manifest())
        module.validate_formula(formula(), REPO, VERSION, checksums)

    def test_draft_even_with_assets_is_not_installable(self):
        candidate = release()
        candidate["draft"] = True
        with self.assertRaisesRegex(ValueError, "not a published preview"):
            module.validate_release(candidate, REPO, VERSION)

    def test_wrong_tag_missing_publication_or_nonpreview_is_rejected(self):
        for key, value in (("tag_name", "v1.0.0"), ("published_at", None), ("prerelease", False)):
            candidate = release()
            candidate[key] = value
            with self.subTest(key=key), self.assertRaises(ValueError):
                module.validate_release(candidate, REPO, VERSION)

    def test_every_required_asset_must_be_present_uploaded_nonempty_and_versioned(self):
        for index, asset in enumerate(release()["assets"]):
            for mutation in (None, {"size": 0}, {"state": "open"},
                             {"browser_download_url": "https://github.com/releases/latest"}):
                candidate = release()
                if mutation is None:
                    candidate["assets"].pop(index)
                else:
                    candidate["assets"][index].update(mutation)
                with self.subTest(asset=asset["name"], mutation=mutation), self.assertRaises(ValueError):
                    module.validate_release(candidate, REPO, VERSION)

    def test_duplicate_assets_and_duplicate_or_malformed_checksums_rejected(self):
        candidate = release()
        candidate["assets"].append(deepcopy(candidate["assets"][0]))
        with self.assertRaises(ValueError):
            module.validate_release(candidate, REPO, VERSION)
        for text in (manifest() + manifest(), "bad  healthmd-cli-installer.sh\n", ""):
            with self.subTest(text=text[:10]), self.assertRaises(ValueError):
                module.validate_checksums(text)

    def test_every_required_download_is_in_checksum_manifest(self):
        for line in manifest().splitlines():
            with self.subTest(asset=line[66:]), self.assertRaisesRegex(ValueError, "checksum missing"):
                module.validate_checksums(manifest().replace(line + "\n", ""))

    def test_tap_version_urls_and_hashes_must_match(self):
        for text in (formula().replace(VERSION, "0.1.0-alpha.7"),
                     formula().replace(BASE, "https://example.com"),
                     formula().replace("a" * 64, "b" * 64)):
            with self.subTest(text=text[:50]), self.assertRaises(ValueError):
                module.validate_formula(text, REPO, VERSION, module.validate_checksums(manifest()))

    def test_audit_only_reads_metadata_checksums_and_formula_not_installers(self):
        calls = []
        def get(url, **kwargs):
            calls.append(url)
            if url.endswith("sha256.sum"):
                return manifest().encode()
            if url.endswith("healthmd.rb"):
                return json.dumps({"content": base64.b64encode(formula().encode()).decode()}).encode()
            if url.endswith("alpha.7"):
                raise HTTPError(url, 404, "Not Found", {}, None)
            return json.dumps(release()).encode()
        with redirect_stdout(io.StringIO()):
            module.audit({"repository": REPO, "published_preview": VERSION, "pending": ["0.1.0-alpha.7"]}, get)
        self.assertEqual(len(calls), 4)
        self.assertFalse(any(url.endswith((".sh", ".ps1", ".zip", ".xz", ".dmg")) for url in calls))

    def test_pending_release_publication_requires_doc_refresh(self):
        def get(url, **kwargs):
            if url.endswith("sha256.sum"):
                return manifest().encode()
            if url.endswith("healthmd.rb"):
                return json.dumps({"content": base64.b64encode(formula().encode()).decode()}).encode()
            return json.dumps(release()).encode()
        with self.assertRaisesRegex(ValueError, "no longer a pending draft"):
            module.audit({"repository": REPO, "published_preview": VERSION, "pending": ["0.1.0-alpha.7"]}, get)

    def test_committed_install_examples_match_audited_preview(self):
        module.validate_install_examples(module.ROOT, VERSION)


if __name__ == "__main__":
    unittest.main()
