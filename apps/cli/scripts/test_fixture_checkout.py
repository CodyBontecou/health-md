#!/usr/bin/env python3
"""Keep packaged fixture bytes identical to reviewed sources after Git checkout."""

from __future__ import annotations

import os
import subprocess
import tempfile
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[3]
FIXTURE_PAIRS = {
    "apps/cli/crates/healthmd-operations/tests/fixtures/agent-data-v1/grant-explicit.json":
        "packages/contracts/agent-data/v1/fixtures/grant-explicit.json",
    "apps/cli/crates/healthmd-operations/tests/fixtures/agent-data-v1/query-records.json":
        "packages/contracts/agent-data/v1/fixtures/query-records.json",
    "apps/cli/crates/healthmd-cli/tests/fixtures/apple-api-export-v2-provider-sidecar.json":
        "apps/apple/docs/reference/generated/automation/api-export-v2-provider-sidecar.json",
    "apps/cli/crates/healthmd-cli/tests/fixtures/android-raw-v1-minimal-snapshot.json":
        "apps/android/app/src/test/resources/raw-export/v1/minimal-snapshot.json",
}


class FixtureCheckoutTests(unittest.TestCase):
    def test_checkout_preserves_reviewed_bytes_with_and_without_autocrlf(self) -> None:
        # Exercise Git's real index/checkout conversion on every host, including
        # Linux CI. Do not normalize the comparison or alter the working tree.
        env = {key: value for key, value in os.environ.items() if not key.startswith("GIT_")}
        env["GIT_CONFIG_GLOBAL"] = os.devnull
        env["GIT_CONFIG_NOSYSTEM"] = "1"
        with tempfile.TemporaryDirectory(prefix="healthmd-fixture-checkout-") as directory:
            scratch = Path(directory)
            repository = scratch / "repository"
            repository.mkdir()

            def git(*arguments: str) -> None:
                subprocess.run(
                    ["git", "-C", str(repository), *arguments],
                    env=env,
                    check=True,
                    stdout=subprocess.PIPE,
                    stderr=subprocess.PIPE,
                )

            git("init", "--quiet")
            paths = set(FIXTURE_PAIRS) | set(FIXTURE_PAIRS.values())
            # Include applicable attributes from the source tree, not a copy of
            # the intended policy hard-coded into the test.
            attributes = {Path(".gitattributes")}
            for name in paths:
                for parent in Path(name).parents:
                    candidate = parent / ".gitattributes"
                    if (ROOT / candidate).is_file():
                        attributes.add(candidate)
            for name in paths | {path.as_posix() for path in attributes}:
                destination = repository / name
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes((ROOT / name).read_bytes())
            git("-c", "core.autocrlf=false", "add", "--all")

            for autocrlf in ("false", "true"):
                checkout = scratch / f"checkout-{autocrlf}"
                checkout.mkdir()
                git(
                    "-c", f"core.autocrlf={autocrlf}",
                    "checkout-index", "--all", f"--prefix={checkout.as_posix()}/",
                )
                for mirror, source in FIXTURE_PAIRS.items():
                    with self.subTest(autocrlf=autocrlf, mirror=mirror):
                        reviewed = (ROOT / source).read_bytes()
                        self.assertNotIn(b"\r\n", reviewed, f"reviewed source must be LF: {source}")
                        self.assertEqual((checkout / source).read_bytes(), reviewed, source)
                        self.assertEqual((checkout / mirror).read_bytes(), reviewed, mirror)


if __name__ == "__main__":
    unittest.main()
