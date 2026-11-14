import hashlib
import json
from pathlib import Path
import runpy
import tempfile
import unittest

MODULE = runpy.run_path(str(Path(__file__).resolve().parents[1] / "sync-google-play-screenshots.py"))


class FakePlay:
    def __init__(self, *, state="RELEASE_LIFECYCLE_STATE_PUBLISHED", bad_upload=False,
                 bad_commit=False, bad_verification=False):
        self.state = state
        self.bad_upload = bad_upload
        self.bad_commit = bad_commit
        self.bad_verification = bad_verification
        self.calls = []
        self.images = []
        self.edits = 0

    def request(self, method, path, data=None, upload=False):
        self.calls.append((method, path))
        if path == "/tracks/production/releases":
            return {"releases": [{"activeArtifacts": [{"versionCode": "48"}],
                                  "releaseLifecycleState": self.state}]}
        if method == "POST" and path == "/edits":
            self.edits += 1
            return {"id": str(self.edits)}
        if path.endswith("/tracks"):
            return {"tracks": [{"track": "production", "releases": [{"versionCodes": ["48"]}]}]}
        if path.endswith("/listings"):
            return {"listings": [{"language": "en-US", "title": "Health.md"}]}
        if "phoneScreenshots" in path:
            if method == "DELETE":
                self.images = []
                return {}
            if method == "POST":
                digest = "wrong" if self.bad_upload else hashlib.sha256(data).hexdigest()
                self.images.append({"sha256": digest})
                return {"image": {"sha256": digest}}
            if path.startswith("/edits/2/") and self.bad_verification:
                return {"images": []}
            return {"images": list(self.images)}
        if ":commit?" in path:
            if self.bad_commit:
                raise TimeoutError("lost commit response")
            return {"id": "1"}
        if path.endswith(":validate") or method == "DELETE":
            return {}
        raise AssertionError((method, path))


class ScreenshotSyncTest(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.addCleanup(self.temporary.cleanup)
        self.root = Path(self.temporary.name)
        self.evidence = self.root / "evidence"
        self.evidence.mkdir()
        self.group = {"language": "en-US", "imageType": "phoneScreenshots", "images": []}
        for index in (1, 2):
            file = self.root / f"{index}.png"
            file.write_bytes(f"screenshot-{index}".encode())
            self.group["images"].append({"path": file.name, "sha256": hashlib.sha256(file.read_bytes()).hexdigest()})

    def sync(self, play):
        MODULE["sync"](play, self.root, [self.group], 48, self.evidence)

    def test_commits_once_verifies_fresh_edit_and_only_mutates_images(self):
        play = FakePlay()
        self.sync(play)
        receipt = json.loads((self.evidence / "receipt.json").read_text())
        self.assertEqual(2, receipt["verifiedImages"])
        self.assertTrue(receipt["committed"])
        self.assertEqual(1, sum(":commit?" in path for _, path in play.calls))
        self.assertIn(("DELETE", "/edits/2"), play.calls)
        self.assertFalse(any(method != "GET" and (path.endswith("/tracks") or path.endswith("/listings"))
                             for method, path in play.calls))

    def test_order_count_and_digest_are_all_required(self):
        images = [{"sha256": image["sha256"]} for image in self.group["images"]]
        self.assertTrue(MODULE["matches"]({"images": images}, self.group))
        self.assertFalse(MODULE["matches"]({"images": list(reversed(images))}, self.group))
        self.assertFalse(MODULE["matches"]({"images": images[:1]}, self.group))

    def test_unpublished_release_never_creates_edit(self):
        play = FakePlay(state="RELEASE_LIFECYCLE_STATE_IN_REVIEW")
        with self.assertRaisesRegex(ValueError, "published"):
            self.sync(play)
        self.assertEqual(0, play.edits)

    def test_bad_upload_abandons_edit_without_commit(self):
        play = FakePlay(bad_upload=True)
        with self.assertRaisesRegex(ValueError, "digest mismatch"):
            self.sync(play)
        self.assertIn(("DELETE", "/edits/1"), play.calls)
        self.assertFalse(any(":commit?" in path for _, path in play.calls))

    def test_changed_asset_abandons_edit_without_commit(self):
        (self.root / "1.png").write_bytes(b"changed")
        play = FakePlay()
        with self.assertRaisesRegex(ValueError, "changed after intent"):
            self.sync(play)
        self.assertFalse(any(":commit?" in path for _, path in play.calls))

    def test_ambiguous_commit_is_never_retried_or_deleted(self):
        play = FakePlay(bad_commit=True)
        with self.assertRaises(TimeoutError):
            self.sync(play)
        self.assertEqual(1, sum(":commit?" in path for _, path in play.calls))
        self.assertNotIn(("DELETE", "/edits/1"), play.calls)
        self.assertTrue((self.evidence / "commit-intent.json").exists())
        self.assertFalse((self.evidence / "receipt.json").exists())

    def test_verification_failure_does_not_claim_success(self):
        play = FakePlay(bad_verification=True)
        with self.assertRaisesRegex(ValueError, "Committed screenshot"):
            self.sync(play)
        self.assertFalse((self.evidence / "receipt.json").exists())
        self.assertIn(("DELETE", "/edits/2"), play.calls)

    def test_noop_still_verifies_without_reuploading(self):
        play = FakePlay()
        play.images = [{"sha256": image["sha256"]} for image in self.group["images"]]
        self.sync(play)
        self.assertFalse(any("uploadType" in path for _, path in play.calls))


if __name__ == "__main__":
    unittest.main()
