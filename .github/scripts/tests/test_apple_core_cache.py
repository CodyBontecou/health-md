import copy
import importlib.util
from pathlib import Path
import tempfile
import unittest


SCRIPT = Path(__file__).resolve().parents[1] / "find-apple-core-cache.py"
spec = importlib.util.spec_from_file_location("apple_core_cache", SCRIPT)
cache = importlib.util.module_from_spec(spec)
spec.loader.exec_module(cache)
promotion_spec = importlib.util.spec_from_file_location("promote_core_inputs", SCRIPT.with_name("promote-apple-core-inputs.py"))
promotion = importlib.util.module_from_spec(promotion_spec)
promotion_spec.loader.exec_module(promotion)


class CompiledInputLookupTests(unittest.TestCase):
    def setUp(self):
        self.current = dict(id=100, repository={"id": 1}, head_repository={"id": 1},
                            workflow_id=42, path=cache.WORKFLOW, event="workflow_dispatch",
                            head_branch="qualification")
        self.run = dict(self.current, id=90, head_sha="c" * 40)
        self.name = "apple-core-inputs-v1-" + "a" * 64 + "-" + "b" * 64
        self.artifact = dict(name=self.name, expired=False, digest="sha256:" + "d" * 64,
                             workflow_run=dict(id=90, repository_id=1, head_repository_id=1,
                                               head_branch="qualification", head_sha="c" * 40))
        self.requests = []

    def lookup(self, runs=None, artifacts=None):
        def get(path):
            self.requests.append(path)
            if path.endswith("/runs/100"):
                return self.current
            if "/workflows/" in path:
                return {"workflow_runs": [self.run] if runs is None else runs}
            return {"artifacts": [self.artifact] if artifacts is None else artifacts}
        return cache.find_cache(get, "owner/repo", 100, "a" * 64, "b" * 64)

    def test_trusted_exact_inputs_do_not_require_prior_test_success(self):
        # Compilation cache may come from a run whose unrelated tests failed;
        # it contains no test outcomes or qualified SDK/source receipts.
        self.run.update(status="completed", conclusion="failure")
        self.assertEqual(self.lookup(), {"run-id": "90", "name": self.name})

    def test_run_identity_mismatches_are_rejected_without_download_lookup(self):
        original = copy.deepcopy(self.run)
        for key, value in [("id", 100), ("id", 101), ("workflow_id", 43),
                           ("path", ".github/workflows/untrusted.yml"),
                           ("event", "pull_request"), ("head_branch", "other"),
                           ("head_repository", {"id": 2}), ("repository", {"id": 2}),
                           ("head_sha", ""), ("head_repository", None)]:
            with self.subTest(key=key, value=value):
                self.run = dict(copy.deepcopy(original), **{key: value})
                self.requests.clear()
                self.assertIsNone(self.lookup())
                self.assertEqual(len(self.requests), 2)

    def test_artifact_identity_and_expiration_must_match(self):
        original = copy.deepcopy(self.artifact)
        mutations = [("name", "apple-sdk27-shared-core"), ("expired", True),
                     ("expired", None), ("digest", ""), ("digest", "sha256:wrong")]
        for key, value in mutations:
            with self.subTest(key=key, value=value):
                self.artifact = dict(copy.deepcopy(original), **{key: value})
                self.assertIsNone(self.lookup())
        for key, value in [("id", 91), ("repository_id", 2), ("head_repository_id", 2),
                           ("head_branch", "other"), ("head_sha", "e" * 40)]:
            with self.subTest(origin=key):
                self.artifact = copy.deepcopy(original)
                self.artifact["workflow_run"][key] = value
                self.assertIsNone(self.lookup())

    def test_duplicate_artifacts_are_not_ambiguous_cache_hits(self):
        self.assertIsNone(self.lookup(artifacts=[self.artifact, self.artifact]))

    def test_pr_and_fork_jobs_can_only_select_main_push_or_dispatch(self):
        self.current.update(event="pull_request", head_repository={"id": 2})
        self.assertIsNone(self.lookup())
        self.assertIn("branch=main", self.requests[1])
        self.run.update(event="push", head_branch="main")
        self.artifact["workflow_run"]["head_branch"] = "main"
        self.assertEqual(self.lookup()["run-id"], "90")

    def test_other_workflow_cannot_select_inputs(self):
        self.current["path"] = ".github/workflows/release-ios.yml"
        self.assertIsNone(self.lookup())
        self.assertEqual(len(self.requests), 1)

    def test_lookup_is_bounded_even_if_recent_runs_have_no_inputs(self):
        self.assertIsNone(self.lookup(runs=[dict(self.run, id=i) for i in range(99, 80, -1)], artifacts=[]))
        self.assertEqual(len(self.requests), 7)

    def test_untrusted_input_cannot_inject_output_or_api_paths(self):
        for repo, fingerprint, digest in [("owner/repo/../../other", "a" * 64, "b" * 64),
                                         ("owner/repo", "a" * 64 + "\nname=bad", "b" * 64),
                                         ("owner/repo", "a" * 64, "bad")]:
            with self.subTest(repo=repo, fingerprint=fingerprint, digest=digest):
                with self.assertRaises(ValueError):
                    cache.find_cache(lambda path: self.fail(path), repo, 100, fingerprint, digest)


class CompiledInputPromotionTests(unittest.TestCase):
    def test_success_copies_only_compilation_and_preserves_current_receipt(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stage, destination = root / "stage", root / "current"
            (stage / "HealthmdCore.xcframework").mkdir(parents=True)
            (stage / "HealthmdCore.xcframework/library.a").write_bytes(b"compiled fixture")
            (stage / ".healthmd-core-source.sha256").write_text("source digest")
            destination.mkdir()
            receipt = destination / ".healthmd-core-sdk27.txt"
            receipt.write_text("current qualified SDK receipt")
            self.assertTrue(promotion.promote(stage, destination, "success"))
            self.assertEqual(receipt.read_text(), "current qualified SDK receipt")
            self.assertEqual((destination / "HealthmdCore.xcframework/library.a").read_bytes(), b"compiled fixture")
            self.assertFalse(stage.exists())

    def test_unavailable_partial_download_is_discarded_without_admission(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stage, destination = root / "stage", root / "current"
            stage.mkdir()
            (stage / "partial.zip").write_bytes(b"incomplete download")
            self.assertFalse(promotion.promote(stage, destination, "failure"))
            self.assertFalse(destination.exists())
            self.assertFalse(stage.exists())
            self.assertFalse(promotion.promote(stage, destination, "failure"))

    def test_successful_download_with_old_receipt_fails_closed(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stage, destination = root / "stage", root / "current"
            stage.mkdir()
            (stage / ".healthmd-core-sdk27.txt").write_text("old receipt")
            with self.assertRaises(ValueError):
                promotion.promote(stage, destination, "success")
            self.assertFalse(destination.exists())
            self.assertFalse(stage.exists())

    def test_successful_download_never_merges_frameworks(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            stage, destination = root / "stage", root / "current"
            for parent in (stage, destination):
                (parent / "HealthmdCore.xcframework").mkdir(parents=True)
            (stage / ".healthmd-core-source.sha256").write_text("digest")
            sentinel = destination / "HealthmdCore.xcframework/sentinel"
            sentinel.write_bytes(b"keep")
            with self.assertRaises(FileExistsError):
                promotion.promote(stage, destination, "success")
            self.assertEqual(sentinel.read_bytes(), b"keep")
            self.assertFalse(stage.exists())


if __name__ == "__main__":
    unittest.main()
