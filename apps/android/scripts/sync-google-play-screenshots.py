#!/usr/bin/env python3
"""Screenshot-only Play edit, invoked by the protected screenshots workflow.

Uses reviewed, validated canonical metadata. Never writes tracks, copy, or icons.
The single commit is never retried; ambiguous outcomes require inspection.
"""
from __future__ import annotations

import argparse
from concurrent.futures import ThreadPoolExecutor
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import urllib.error
import urllib.request

PACKAGE = "com.healthmd.android"
API = f"https://androidpublisher.googleapis.com/androidpublisher/v3/applications/{PACKAGE}"
UPLOAD_API = API.replace("/androidpublisher/v3/", "/upload/androidpublisher/v3/")
IMAGE_TYPES = ("phoneScreenshots", "sevenInchScreenshots", "tenInchScreenshots")


def write_json(path, value):
    path.write_text(json.dumps(value, indent=2) + "\n")


def plan(metadata):
    groups = []
    for locale in sorted(metadata.iterdir()):
        if not locale.is_dir():
            continue
        for image_type in IMAGE_TYPES:
            files = sorted((locale / "images" / image_type).glob("*.png"))
            if not 2 <= len(files) <= 8:
                raise ValueError(f"Invalid screenshot count: {locale.name}/{image_type}")
            groups.append({"language": locale.name, "imageType": image_type, "images": [
                {"path": str(file.relative_to(metadata)),
                 "sha256": hashlib.sha256(file.read_bytes()).hexdigest()}
                for file in files
            ]})
    if not groups:
        raise ValueError("No reviewed screenshots")
    return groups


def matches(response, group):
    # The API returns images in display order; membership alone is insufficient.
    return [image.get("sha256", "").lower() for image in response.get("images", [])] == [
        image["sha256"] for image in group["images"]
    ]


class Play:
    def __init__(self, token):
        self.token = token

    def request(self, method, path, data=None, upload=False):
        url = (UPLOAD_API if upload else API) + path
        headers = {"Authorization": f"Bearer {self.token}"}
        if data is not None:
            headers["Content-Type"] = "image/png" if upload else "application/json"
        request = urllib.request.Request(url, data=data, headers=headers, method=method)
        with urllib.request.urlopen(request, timeout=60) as response:
            body = response.read()
            return json.loads(body) if body else {}


def sync(play, metadata, groups, code, evidence):
    production = play.request("GET", "/tracks/production/releases")
    write_json(evidence / "production-before.json", production)
    active = [release for release in production.get("releases", [])
              if any(int(artifact["versionCode"]) == code
                     for artifact in release.get("activeArtifacts", []))]
    if len(active) != 1 or active[0].get("releaseLifecycleState") != "RELEASE_LIFECYCLE_STATE_PUBLISHED":
        raise ValueError(f"Expected published production build {code}")
    if any(int(artifact["versionCode"]) > code for release in production.get("releases", [])
           for artifact in release.get("activeArtifacts", [])):
        raise ValueError("A newer production build exists")

    edit = play.request("POST", "/edits", b"{}")['id']
    root = f"/edits/{edit}"
    commit_attempted = False
    try:
        before_tracks = play.request("GET", root + "/tracks")
        before_listings = play.request("GET", root + "/listings")
        write_json(evidence / "listings-before.json", before_listings)
        write_json(evidence / "tracks-before.json", before_tracks)

        def replace(group):
            path = f"/listings/{group['language']}/{group['imageType']}"
            before = play.request("GET", root + path)
            name = f"{group['language']}-{group['imageType']}"
            write_json(evidence / f"{name}-before.json", before)
            if not matches(before, group):
                play.request("DELETE", root + path)
                for image in group["images"]:
                    data = (metadata / image["path"]).read_bytes()
                    if hashlib.sha256(data).hexdigest() != image["sha256"]:
                        raise ValueError("Asset changed after intent")
                    uploaded = play.request("POST", root + path + "?uploadType=media", data, upload=True)
                    if uploaded.get("image", {}).get("sha256", "").lower() != image["sha256"]:
                        raise ValueError(f"Upload digest mismatch: {image['path']}")
            staged = play.request("GET", root + path)
            write_json(evidence / f"{name}-staged.json", staged)
            if not matches(staged, group):
                raise ValueError(f"Screenshot order/digests differ: {name}")
            print(f"Verified {name}: {len(group['images'])} screenshots", flush=True)

        with ThreadPoolExecutor(max_workers=4) as pool:
            list(pool.map(replace, groups))
        if play.request("GET", root + "/tracks") != before_tracks:
            raise ValueError("Track state changed during screenshot edit")
        if play.request("GET", root + "/listings") != before_listings:
            raise ValueError("Listing copy changed during screenshot edit")
        play.request("POST", root + ":validate", b"")
        write_json(evidence / "commit-intent.json", {"editId": edit, "versionCode": code,
                   "changesNotSentForReview": False, "groups": groups})
        commit_attempted = True
        # Exactly once. On a lost response retain the edit ID and fail for operator reconciliation.
        committed = play.request("POST", root + ":commit?changesNotSentForReview=false&changesInReviewBehavior=ERROR_IF_IN_REVIEW", b"")
        write_json(evidence / "commit-response.json", committed)
        if committed.get("id") != edit:
            raise ValueError("Unexpected commit response; inspect retained intent before retrying")
    finally:
        if not commit_attempted:
            play.request("DELETE", root)

    verification = play.request("POST", "/edits", b"{}")['id']
    try:
        for group in groups:
            path = f"/edits/{verification}/listings/{group['language']}/{group['imageType']}"
            remote = play.request("GET", path)
            write_json(evidence / f"{group['language']}-{group['imageType']}-committed.json", remote)
            if not matches(remote, group):
                raise ValueError("Committed screenshot digests/order differ; inspect before retrying")
        write_json(evidence / "receipt.json", {"committed": True, "editId": edit,
                   "versionCode": code, "verifiedGroups": len(groups),
                   "verifiedImages": sum(len(group["images"]) for group in groups),
                   "publication": "Submitted for review; managed publishing remains separate"})
    finally:
        play.request("DELETE", f"/edits/{verification}")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--intent", type=Path, required=True)
    parser.add_argument("--evidence", type=Path)
    parser.add_argument("--version-code", type=int, required=True)
    parser.add_argument("--apply", action="store_true")
    args = parser.parse_args()
    android = Path(__file__).resolve().parents[1]
    with tempfile.TemporaryDirectory(prefix="play-screenshots-") as temporary:
        metadata = Path(temporary) / "metadata"
        subprocess.run(["python3", str(android / "scripts/prepare-play-metadata.py"),
                        "--output-dir", str(metadata)], check=True)
        groups = plan(metadata)
        intent = {"package": PACKAGE, "sourceSha": os.environ["GITHUB_SHA"],
                  "releaseTag": os.environ["RELEASE_TAG"], "versionCode": args.version_code,
                  "groups": groups}
        if not args.apply:
            write_json(args.intent, intent)
            print(f"Prepared {len(groups)} screenshot groups, {sum(len(g['images']) for g in groups)} images")
            return
        if intent != json.loads(args.intent.read_text()):
            raise ValueError("Screenshot intent does not match exact source")
        if not args.evidence:
            raise ValueError("Evidence directory required")
        args.evidence.mkdir(parents=True, exist_ok=True)
        sync(Play(os.environ["ACCESS_TOKEN"]), metadata, groups, args.version_code, args.evidence)


if __name__ == "__main__":
    try:
        main()
    except urllib.error.HTTPError as error:
        # Google errors do not contain credentials; avoid dumping request headers.
        print(f"Google Play HTTP {error.code}: {error.read().decode()[:2000]}", flush=True)
        raise SystemExit(1)
