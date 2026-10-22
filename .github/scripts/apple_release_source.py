#!/usr/bin/env python3
"""Resolve and revalidate Apple release provenance without store credentials.

Workflow-only recovery runs newer main workflow code, but qualification and
archives always use the original tag commit. Nothing rewrites release tags.
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
from pathlib import Path

APPLE_TAG = re.compile(r"v[0-9]+(?:\.[0-9]+){1,2}\Z")
SHA = re.compile(r"[0-9a-f]{40}\Z")
MAIN = "refs/remotes/origin/main"
RECOVERY_PATHS = (".github/workflows/", ".github/actions/", ".github/scripts/")


class PolicyError(Exception):
    pass


def git(*args: str) -> str:
    result = subprocess.run(["git", *args], capture_output=True, text=True)
    if result.returncode:
        raise PolicyError(f"git {' '.join(args)} failed: {result.stderr.strip()}")
    return result.stdout.rstrip("\n")


def require_sha(value: str) -> str:
    if not SHA.fullmatch(value):
        raise PolicyError("Expected a full, immutable Git commit SHA")
    return value


def require_clean_head(expected: str) -> None:
    if git("rev-parse", "HEAD") != require_sha(expected):
        raise PolicyError("Checked-out HEAD does not match the qualified source SHA")
    # Ignored build products are not source. Staged, unstaged, and non-ignored
    # untracked files are all rejected, across the whole repository.
    dirty = git("status", "--porcelain", "--untracked-files=normal")
    if dirty:
        raise PolicyError(f"Release source must be a clean worktree:\n{dirty}")


def refresh_main() -> None:
    # Read only from the remote; never push or move a release tag. Refuse a
    # non-fast-forward main rewrite rather than concealing provenance drift.
    git("fetch", "--no-tags", "origin", "refs/heads/main:" + MAIN)


def require_ancestor(older: str, newer: str) -> None:
    git("merge-base", "--is-ancestor", older, newer)


def tag_identity(tag: str) -> tuple[str, str]:
    if not APPLE_TAG.fullmatch(tag):
        raise PolicyError("Apple release tag must be v<major>.<minor>[.<patch>]")
    ref = "refs/tags/" + tag
    # A same-named branch, revision expression, or mutable branch head is not a tag.
    sha = require_sha(git("rev-parse", "--verify", ref + "^{commit}"))
    tag_object = git("rev-parse", "--verify", ref)
    remote = git("ls-remote", "--exit-code", "--refs", "origin", ref)
    if remote.split() != [tag_object, ref]:
        raise PolicyError(f"Release tag {tag} differs from the pushed remote tag")
    return sha, tag_object


def resolve() -> dict[str, str]:
    workflow_sha = require_sha(os.environ["GITHUB_SHA"])
    require_clean_head(workflow_sha)
    event = os.environ["GITHUB_EVENT_NAME"]
    ref = os.environ["GITHUB_REF"]
    manual_tag = os.environ.get("RELEASE_INPUT_TAG", "")
    if event == "release":
        tag = os.environ.get("RELEASE_EVENT_TAG", "")
        if not tag:
            raise PolicyError("Release publication must identify an existing Apple tag")
        trigger = "release"
    elif event == "workflow_dispatch":
        if manual_tag:
            if ref != "refs/heads/main":
                raise PolicyError("release_tag recovery must be dispatched from main")
            tag, trigger = manual_tag, "manual-release"
        elif ref.startswith("refs/tags/"):
            tag, trigger = ref.removeprefix("refs/tags/"), "tag"
        else:
            if os.environ.get("RELEASE_DRY_RUN") != "true":
                raise PolicyError("Untagged branch dispatch requires dry_run=true")
            return {"sha": workflow_sha, "workflow_sha": workflow_sha, "tag": "",
                    "tag_object": "", "mode": "branch", "version": "", "trigger": "manual"}
    else:
        raise PolicyError("Unsupported Apple release event")

    sha, tag_object = tag_identity(tag)
    project = git("show", sha + ":apps/apple/HealthMd.xcodeproj/project.pbxproj")
    versions = set(re.findall(r"MARKETING_VERSION\s*=\s*([^;\s]+)\s*;", project))
    if versions != {tag[1:]}:
        raise PolicyError("Release tag version must match every committed MARKETING_VERSION")
    refresh_main()
    require_ancestor(sha, MAIN)
    require_ancestor(workflow_sha, MAIN)
    if sha != workflow_sha:
        if event != "workflow_dispatch" or not manual_tag:
            raise PolicyError("Release/tag event SHA must match the immutable tag commit")
        require_ancestor(sha, workflow_sha)
        changed = git("diff", "--name-only", "--no-renames", "-z", sha, workflow_sha).split("\0")
        product_changes = [path for path in changed if path and not path.startswith(RECOVERY_PATHS)]
        if product_changes:
            raise PolicyError("Recovery must be workflow-only; create a new release for source changes:\n"
                              + "\n".join(product_changes))
    return {"sha": sha, "workflow_sha": workflow_sha, "tag": tag, "tag_object": tag_object,
            "mode": "tag", "version": tag[1:], "trigger": trigger}


def verify() -> None:
    sha = require_sha(os.environ["RELEASE_SHA"])
    require_clean_head(sha)
    tag = os.environ.get("RELEASE_TAG", "")
    if tag:
        tagged_sha, tag_object = tag_identity(tag)
        if tagged_sha != sha or tag_object != os.environ["RELEASE_TAG_OBJECT"]:
            raise PolicyError("Release tag changed after qualification; do not retag an existing release")
        refresh_main()
        require_ancestor(sha, MAIN)
        require_ancestor(require_sha(os.environ["GITHUB_SHA"]), MAIN)
    elif os.environ.get("RELEASE_DRY_RUN") != "true":
        raise PolicyError("Only a dry run may archive untagged branch source")
    print(f"Verified clean source {sha} (workflow {os.environ['GITHUB_SHA']}, tag {tag or 'none'})")


def main() -> None:
    # git status from a component directory must still cover the entire repo.
    os.chdir(git("rev-parse", "--show-toplevel"))
    if sys.argv[1:] == ["resolve"]:
        identity = resolve()
        with Path(os.environ["GITHUB_OUTPUT"]).open("a") as output:
            for key, value in identity.items():
                output.write(f"{key}={value}\n")
        print(f"Qualifying {identity['sha']} (workflow {identity['workflow_sha']}, "
              f"tag {identity['tag'] or 'none'})")
    elif sys.argv[1:] == ["verify"]:
        verify()
    else:
        raise PolicyError("Usage: apple_release_source.py resolve|verify")


if __name__ == "__main__":
    try:
        main()
    except (PolicyError, KeyError) as error:
        # Escape Actions annotation control characters; inputs are never shell code.
        message = str(error).replace("%", "%25").replace("\r", "%0D").replace("\n", "%0A")
        print(f"::error::{message}", file=sys.stderr)
        raise SystemExit(1)
