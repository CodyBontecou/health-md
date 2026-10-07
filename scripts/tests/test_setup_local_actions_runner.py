#!/usr/bin/env python3
"""Runner bootstrap safety tests with synthetic archives and no network/registration."""

from __future__ import annotations

from contextlib import ExitStack, redirect_stderr, redirect_stdout
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import subprocess
import tarfile
import tempfile
import unittest
from unittest.mock import patch

SCRIPT = Path(__file__).resolve().parents[1] / "setup-local-actions-runner.py"
SPEC = importlib.util.spec_from_file_location("setup_local_actions_runner", SCRIPT)
assert SPEC and SPEC.loader
bootstrap = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(bootstrap)

TOKEN = "synthetic-registration-secret"
CONTROLLER = "CodyBontecou/health-md-local-ci"
PRIVATE_CONTROLLER = {"full_name": CONTROLLER, "private": True, "default_branch": "main",
                      "owner": {"login": "CodyBontecou", "type": "User"},
                      "permissions": {"admin": True}}


def archive_bytes(members: tuple[tuple[str, bytes, bytes], ...] = (("config.sh", b"#!/bin/sh\n", tarfile.REGTYPE),)) -> bytes:
    output = io.BytesIO()
    with tarfile.open(fileobj=output, mode="w:gz") as bundle:
        for name, data, kind in members:
            member = tarfile.TarInfo(name)
            member.type = kind
            member.mode = 0o700
            if kind in (tarfile.SYMTYPE, tarfile.LNKTYPE):
                member.linkname = data.decode() if data else "../../escape"
            if kind == tarfile.REGTYPE:
                member.size = len(data)
                bundle.addfile(member, io.BytesIO(data))
            else:
                bundle.addfile(member)
    return output.getvalue()


def release(data: bytes) -> dict:
    return {"tag_name": "v2.999.0", "assets": [{
        "name": "actions-runner-osx-arm64-2.999.0.tar.gz",
        "digest": f"sha256:{hashlib.sha256(data).hexdigest()}",
        "browser_download_url": "https://github.com/actions/runner/releases/download/v2.999.0/actions-runner-osx-arm64-2.999.0.tar.gz"}]}


class BootstrapSafetyTests(unittest.TestCase):
    def test_release_requires_one_official_asset_and_full_sha256_digest(self):
        valid = release(b"archive")
        self.assertEqual(bootstrap.runner_asset(valid)[1], hashlib.sha256(b"archive").hexdigest())
        for case in ("missing_digest", "bad_digest", "foreign_url", "ambiguous_asset"):
            payload = json.loads(json.dumps(valid))
            asset = payload["assets"][0]
            if case == "missing_digest":
                del asset["digest"]
            elif case == "bad_digest":
                asset["digest"] = "sha256:short"
            elif case == "foreign_url":
                asset["browser_download_url"] = "https://github.com.example/actions/runner/releases/download/file"
            else:
                payload["assets"].append(dict(asset))
            with self.subTest(case=case), self.assertRaises(ValueError):
                bootstrap.runner_asset(payload)

    def test_corruption_traversal_links_special_files_and_late_escape_chains_are_refused(self):
        cases = [("digest", archive_bytes(), "0" * 64)]
        for name, member, kind in (("relative_escape", "../escape", tarfile.REGTYPE),
                                   ("absolute_escape", "/escape", tarfile.REGTYPE),
                                   ("symlink", "link", tarfile.SYMTYPE),
                                   ("hardlink", "link", tarfile.LNKTYPE),
                                   ("fifo", "pipe", tarfile.FIFOTYPE)):
            data = archive_bytes((("safe-first", b"safe", tarfile.REGTYPE), (member, b"", kind)))
            cases.append((name, data, hashlib.sha256(data).hexdigest()))
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for name, data, digest in cases:
                destination = root / name
                destination.mkdir()
                archive = root / f"{name}.tgz"
                archive.write_bytes(data)
                with self.subTest(case=name), self.assertRaises(ValueError):
                    bootstrap.extract_archive(archive, destination, digest)
                self.assertEqual(list(destination.iterdir()), [])
            self.assertFalse((root / "escape").exists())

            # Both links look contained before extraction, but jump changes how '..'
            # resolves in alias's target. Refuse the later write and the final chain.
            links = (("directory", b"", tarfile.DIRTYPE),
                     ("directory/alias", b"../jump/../escape", tarfile.SYMTYPE),
                     ("jump", b".", tarfile.SYMTYPE))
            for case, members in (("chain_only", links),
                                  ("chain_write", links + (("directory/alias/payload", b"unsafe", tarfile.REGTYPE),))):
                destination = root / case
                destination.mkdir()
                archive = root / f"{case}.tgz"
                data = archive_bytes(members)
                archive.write_bytes(data)
                with self.subTest(case=case), self.assertRaises(ValueError):
                    bootstrap.extract_archive(archive, destination, hashlib.sha256(data).hexdigest())
                self.assertFalse((root / "escape").exists())

            # A hardlink target also needs validation after earlier links exist:
            # otherwise a subsequent same-name file can overwrite an outside inode.
            outside = root / "escape" / "secret"
            outside.parent.mkdir()
            outside.write_bytes(b"preserve outside file")
            destination = root / "late_hardlink"
            destination.mkdir()
            data = archive_bytes(links + (("copied", b"directory/alias/secret", tarfile.LNKTYPE),
                                          ("copied", b"overwrite outside inode", tarfile.REGTYPE)))
            archive = root / "late_hardlink.tgz"
            archive.write_bytes(data)
            with self.subTest(case="late_hardlink"), self.assertRaises(ValueError):
                bootstrap.extract_archive(archive, destination, hashlib.sha256(data).hexdigest())
            self.assertEqual(outside.read_bytes(), b"preserve outside file")

            # Official runtime archives include links; contained symlinks and hard
            # links must retain their intended contents without requiring execution.
            destination = root / "contained"
            destination.mkdir()
            data = archive_bytes((("target", b"contents", tarfile.REGTYPE),
                                  ("alias", b"target", tarfile.SYMTYPE),
                                  ("hard", b"target", tarfile.LNKTYPE)))
            archive = root / "contained.tgz"
            archive.write_bytes(data)
            bootstrap.extract_archive(archive, destination, hashlib.sha256(data).hexdigest())
            self.assertTrue((destination / "alias").is_symlink())
            self.assertEqual((destination / "alias").read_bytes(), b"contents")
            self.assertEqual((destination / "hard").read_bytes(), b"contents")
            self.assertEqual((destination / "hard").stat().st_ino, (destination / "target").stat().st_ino)

    def invoke(self, destination: Path, *, initial: dict | list[dict] | None = None, name: str = "pilot-test",
               registration_code: int = 0, labels: tuple[str, ...] = (bootstrap.LABEL,),
               controller: dict | None = None):
        data = archive_bytes()
        output, errors = io.StringIO(), io.StringIO()
        api_calls, registrations = [], []
        listings = 0

        def github(endpoint, method="GET"):
            nonlocal listings
            api_calls.append((endpoint, method))
            if endpoint == f"repos/{CONTROLLER}":
                return PRIVATE_CONTROLLER if controller is None else controller
            if "registration-token" in endpoint:
                return {"token": TOKEN}
            if endpoint == "repos/actions/runner/releases/latest":
                return release(data)
            if "actions/runners" in endpoint:
                listings += 1
                if isinstance(initial, list) and listings <= len(initial):
                    return initial[listings - 1]
                if listings == 1:
                    return initial if initial is not None else {"total_count": 0, "runners": []}
                return {"total_count": 1, "runners": [{"name": name,
                        "labels": [{"name": label} for label in labels]}]}
            raise AssertionError(f"Unexpected GitHub API endpoint {endpoint}")

        def registration(args, **kwargs):
            registrations.append((args, kwargs))
            return subprocess.CompletedProcess(args, registration_code,
                                               stdout=f"synthetic diagnostic {TOKEN}")

        previous_umask = os.umask(0o077)
        try:
            with ExitStack() as stack:
                stack.enter_context(patch.object(bootstrap.platform, "system", return_value="Darwin"))
                stack.enter_context(patch.object(bootstrap.platform, "machine", return_value="arm64"))
                stack.enter_context(patch.object(bootstrap, "github", side_effect=github))
                network = stack.enter_context(patch.object(bootstrap.urllib.request, "urlopen",
                                                          side_effect=lambda *args, **kwargs: io.BytesIO(data)))
                stack.enter_context(patch.object(bootstrap.subprocess, "run", side_effect=registration))
                stack.enter_context(patch.dict(os.environ, {key: TOKEN for key in
                                    ("GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN")}))
                stack.enter_context(patch("sys.argv", [str(SCRIPT), "--runner-dir", str(destination), "--name", name]))
                stack.enter_context(redirect_stdout(output))
                stack.enter_context(redirect_stderr(errors))
                code = bootstrap.main()
                downloads = network.call_count
        finally:
            os.umask(previous_umask)
        return code, output.getvalue() + errors.getvalue(), api_calls, registrations, downloads

    def test_public_wrong_owner_or_insufficient_controller_policy_fails_before_install_or_registration(self):
        invalid = [dict(PRIVATE_CONTROLLER, private=False),
                   dict(PRIVATE_CONTROLLER, private="true"),
                   dict(PRIVATE_CONTROLLER, full_name="CodyBontecou/health-md"),
                   dict(PRIVATE_CONTROLLER, owner={"login": "someone-else", "type": "User"}),
                   dict(PRIVATE_CONTROLLER, owner={"login": "CodyBontecou", "type": "Organization"}),
                   dict(PRIVATE_CONTROLLER, default_branch="development"),
                   dict(PRIVATE_CONTROLLER, permissions={"admin": False}),
                   dict(PRIVATE_CONTROLLER, permissions={"admin": "true"}), {}]
        with tempfile.TemporaryDirectory() as temporary:
            for index, metadata in enumerate(invalid):
                destination = Path(temporary) / f"runner-{index}"
                with self.subTest(metadata=metadata):
                    code, output, calls, registrations, downloads = self.invoke(destination, controller=metadata)
                    self.assertEqual(code, 1)
                    self.assertEqual(calls, [(f"repos/{CONTROLLER}", "GET")])
                    self.assertEqual(registrations, [])
                    self.assertEqual(downloads, 0)
                    self.assertFalse(destination.exists())
                    self.assertNotIn(TOKEN, output)

    def test_existing_configuration_duplicate_name_or_invalid_name_cannot_replace_runner(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            for case in ("existing", "duplicate", "paginated_duplicate", "invalid_name"):
                destination = root / case
                if case == "existing":
                    destination.mkdir()
                    (destination / ".runner").write_text("existing registration")
                initial = {"total_count": 1, "runners": [{"name": "pilot-test"}]} if case == "duplicate" else None
                if case == "paginated_duplicate":
                    initial = [{"total_count": 101, "runners": [{"name": f"existing-{number}"} for number in range(100)]},
                               {"total_count": 101, "runners": [{"name": "pilot-test"}]}]
                with self.subTest(case=case):
                    code, _, calls, registrations, downloads = self.invoke(
                        destination, initial=initial, name="unsafe/name" if case == "invalid_name" else "pilot-test")
                    self.assertEqual(code, 1)
                    self.assertEqual(registrations, [])
                    self.assertEqual(downloads, 0)
                    self.assertFalse(any("registration-token" in endpoint for endpoint, _ in calls))
                    if case == "paginated_duplicate":
                        self.assertTrue(any("page=2" in endpoint for endpoint, _ in calls))
                if case == "existing":
                    self.assertEqual((destination / ".runner").read_text(), "existing registration")

    def test_success_registers_only_custom_label_without_inheriting_cli_tokens_or_starting_service(self):
        with tempfile.TemporaryDirectory() as temporary:
            destination = Path(temporary) / "runner"
            code, output, calls, registrations, downloads = self.invoke(destination)
            self.assertEqual(code, 0)
            self.assertEqual(downloads, 1)
            self.assertEqual(len(registrations), 1)
            args, kwargs = registrations[0]
            self.assertEqual(calls[0], (f"repos/{CONTROLLER}", "GET"))
            self.assertTrue(all(not endpoint.startswith("repos/CodyBontecou/health-md/") for endpoint, _ in calls))
            self.assertEqual(args[args.index("--url") + 1], f"https://github.com/{CONTROLLER}")
            self.assertEqual(args[0], str(destination.resolve() / "config.sh"))
            self.assertIn("--no-default-labels", args)
            self.assertEqual(args[args.index("--labels") + 1], bootstrap.LABEL)
            self.assertNotIn("--replace", args)
            self.assertTrue(all(key not in kwargs["env"] for key in
                                ("GH_TOKEN", "GITHUB_TOKEN", "GH_ENTERPRISE_TOKEN", "GITHUB_ENTERPRISE_TOKEN")))
            self.assertNotIn(TOKEN, output)
            self.assertNotIn("svc.sh", " ".join(args))
            self.assertEqual((destination / "config.sh").read_bytes(), b"#!/bin/sh\n")
            self.assertFalse((destination / "config.sh").stat().st_mode & 0o077)
            self.assertTrue(any(method == "POST" and "registration-token" in endpoint for endpoint, method in calls))

    def test_registration_failure_redacts_token_and_does_not_claim_success(self):
        with tempfile.TemporaryDirectory() as temporary:
            code, output, _, registrations, _ = self.invoke(Path(temporary) / "runner", registration_code=1)
            self.assertEqual(code, 1)
            self.assertEqual(len(registrations), 1)
            self.assertNotIn(TOKEN, output)
            self.assertIn("[redacted]", output)
            self.assertNotIn("Start in that directory", output)

    def test_unexpected_default_labels_are_refused_after_registration(self):
        with tempfile.TemporaryDirectory() as temporary:
            code, output, _, registrations, _ = self.invoke(
                Path(temporary) / "runner", labels=(bootstrap.LABEL, "self-hosted"))
            self.assertEqual(code, 1)
            self.assertEqual(len(registrations), 1)
            self.assertIn("do not start", output)
            self.assertNotIn("Start in that directory", output)

    def test_github_auth_failure_does_not_disclose_cli_output(self):
        failure = subprocess.CompletedProcess(["gh"], 1, stdout=TOKEN, stderr=TOKEN)
        with patch.object(bootstrap.subprocess, "run", return_value=failure), self.assertRaises(ValueError) as error:
            bootstrap.github(f"repos/{CONTROLLER}/actions/runners")
        self.assertNotIn(TOKEN, str(error.exception))
        self.assertIn("verify gh auth", str(error.exception))


if __name__ == "__main__":
    unittest.main()
