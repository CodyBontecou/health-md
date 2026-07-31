import importlib.util
import json
import os
import pathlib
import sys
import time
import tempfile
import unittest

SCRIPT = pathlib.Path(__file__).parents[1] / "export-performance-lab.py"
SPEC = importlib.util.spec_from_file_location("export_performance_lab", SCRIPT)
assert SPEC and SPEC.loader
lab = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = lab
SPEC.loader.exec_module(lab)


class ExportPerformanceLabTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.root = pathlib.Path(self.temporary.name) / "lab"
        self.vault = pathlib.Path(self.temporary.name) / "vault"
        self.vault.mkdir(mode=0o700)
        self.config = lab.LabConfig(
            root=str(self.root),
            cli_path="/usr/bin/true",
            cli_data_dir=str(self.root / "CLIState"),
            mac_vault=str(self.vault),
            minimum_free_gib=0,
            allow_unsigned_cli=True,
            lab_binding="a" * 64,
        )
        self.runner = lab.LabRunner(
            self.config,
            pathlib.Path(__file__).parents[4],
            dry_run=True,
        )

    def tearDown(self):
        self.temporary.cleanup()

    def test_dry_run_matrix_creates_only_allowlisted_plans(self):
        result = self.runner.run_matrix(
            targets=["direct-files", "api-endpoint"],
            scenario="sleep-summary",
            repeat=2,
            supervised_ready=False,
        )

        self.assertEqual(result["status"], "planned")
        self.assertEqual(result["run_count"], 4)
        suite = json.loads(
            (self.root / "Runs" / result["suite_id"] / "suite.json").read_text()
        )
        self.assertEqual(suite["targets"], ["direct-files", "api-endpoint"])
        self.assertEqual(len(suite["run_ids"]), 4)
        for run_id in suite["run_ids"]:
            plan_path = self.root / "Runs" / run_id / "plan.json"
            self.assertTrue(plan_path.exists())
            self.assertEqual(plan_path.stat().st_mode & 0o777, 0o600)

    def test_run_matrix_rejects_unknown_targets_and_scenarios(self):
        with self.assertRaises(lab.LabError):
            self.runner.run_matrix(["shell"], "sleep-summary", 1, False)
        with self.assertRaises(lab.LabError):
            self.runner.run_matrix(["direct-raw"], "private-date", 1, False)
        with self.assertRaises(lab.LabError):
            self.runner.run_matrix(["direct-raw"], "sleep-summary", 1, False)
        with self.assertRaises(lab.LabError):
            self.runner.run_matrix(["direct-files"], "large-file-backed-blob", 1, False)
        with self.assertRaises(lab.LabError):
            self.runner.run_matrix(["direct-files"], "saved-full-provider-disabled", 1, False)
        with self.assertRaises(lab.LabError):
            self.runner.run_matrix(["api-endpoint"], "large-file-backed-blob", 1, False)
        with self.assertRaises(lab.LabError):
            self.runner.run_matrix(["api-endpoint"], "thirty-day", 1, False)
        raw = self.runner.run_matrix(["direct-raw"], "raw-full", 1, False)
        self.assertEqual(raw["status"], "planned")
        thirty_day = self.runner.run_matrix(["direct-files"], "thirty-day", 1, False)
        self.assertEqual(thirty_day["status"], "planned")
        self.assertEqual(lab.SCENARIOS["thirty-day"]["date_args"], ["--last", "30"])
        self.assertEqual(lab.SCENARIOS["thirty-day"]["max_days"], 30)
        self.assertEqual(lab.SCENARIOS["thirty-day"]["cli_timeout_seconds"], 585)

    def test_private_root_rejects_symlinked_run_ancestor(self):
        outside = pathlib.Path(self.temporary.name) / "outside"
        outside.mkdir()
        runs = self.root / "Runs"
        self.root.mkdir(exist_ok=True)
        runs.symlink_to(outside, target_is_directory=True)
        with self.assertRaises(lab.LabError):
            lab.PrivateRunDirectory(self.root, "safe-run")

    def test_command_timeout_kills_complete_process_group(self):
        script = pathlib.Path(self.temporary.name) / "spawn-child.py"
        pid_path = pathlib.Path(self.temporary.name) / "child.pid"
        script.write_text(
            "import pathlib,subprocess,time,sys\n"
            "child=subprocess.Popen(['sleep','30'])\n"
            "pathlib.Path(sys.argv[1]).write_text(str(child.pid))\n"
            "time.sleep(30)\n"
        )
        result = self.runner._run_command(
            [sys.executable, str(script), str(pid_path)],
            self.root / "timeout.stdout",
            self.root / "timeout.stderr",
            timeout=1,
            measure=False,
        )
        self.assertTrue(result.timed_out)
        child_pid = int(pid_path.read_text())
        time.sleep(0.2)
        with self.assertRaises(ProcessLookupError):
            os.kill(child_pid, 0)

    def test_config_refuses_group_readable_files_and_unknown_keys(self):
        path = pathlib.Path(self.temporary.name) / "config.json"
        path.write_text(json.dumps({"root": str(self.root)}))
        os.chmod(path, 0o644)
        with self.assertRaises(lab.LabError):
            lab.load_config(path)

        os.chmod(path, 0o600)
        path.write_text(json.dumps({"root": str(self.root), "command": "rm -rf"}))
        with self.assertRaises(lab.LabError):
            lab.load_config(path)

    def test_compare_applies_wall_and_memory_thresholds(self):
        baseline_ids = []
        candidate_ids = []
        for prefix, wall, memory, destination in (
            ("baseline", 10.0, 100 * 1024**2, baseline_ids),
            ("candidate", 13.0, 150 * 1024**2, candidate_ids),
        ):
            run_id = f"{prefix}-run"
            destination.append(run_id)
            directory = lab.PrivateRunDirectory(self.root, run_id)
            state = self._state(run_id, wall, memory)
            self.runner._save_state(directory, state)
            lab._private_write(
                directory.evidence / "telemetry.ndjson",
                (json.dumps({
                    "pipeline": "direct-file",
                    "phase": "render",
                    "elapsed_milliseconds": 1_000 if prefix == "baseline" else 1_400,
                }) + "\n").encode(),
            )
            lab._private_write(
                directory.evidence / "local-digests.json",
                json.dumps({"health.json": "a" * 64}).encode(),
            )
            state.output_file_count = 1
            self.runner._save_state(directory, state)

        baseline_suite = self._suite("baseline-suite", baseline_ids)
        candidate_suite = self._suite("candidate-suite", candidate_ids)
        comparison = self.runner.compare(candidate_suite, baseline_suite)

        self.assertEqual(comparison["status"], "regression")
        self.assertEqual(
            comparison["comparisons"][0]["reasons"],
            ["wall-time", "iphone-footprint", "phase:direct-file/render"],
        )

    def test_compare_rejects_incomplete_runs_and_digest_mismatch(self):
        baseline = lab.PrivateRunDirectory(self.root, "complete-baseline")
        baseline_state = self._state("complete-baseline", 10, 100)
        baseline_state.output_file_count = 1
        self.runner._save_state(baseline, baseline_state)
        lab._private_write(
            baseline.evidence / "local-digests.json",
            json.dumps({"health.json": "a" * 64}).encode(),
        )

        failed = lab.PrivateRunDirectory(self.root, "failed-candidate")
        failed_state = self._state("failed-candidate", 10, 100)
        failed_state.state = "failed"
        failed_state.output_file_count = 1
        self.runner._save_state(failed, failed_state)
        lab._private_write(
            failed.evidence / "local-digests.json",
            json.dumps({"health.json": "a" * 64}).encode(),
        )
        with self.assertRaises(lab.LabError):
            self.runner.compare(
                self._suite("failed-suite", ["failed-candidate"]),
                self._suite("complete-suite", ["complete-baseline"]),
            )

        candidate = lab.PrivateRunDirectory(self.root, "changed-candidate")
        candidate_state = self._state("changed-candidate", 10, 100)
        candidate_state.output_file_count = 1
        self.runner._save_state(candidate, candidate_state)
        lab._private_write(
            candidate.evidence / "local-digests.json",
            json.dumps({"health.json": "b" * 64}).encode(),
        )
        comparison = self.runner.compare(
            self._suite("changed-suite", ["changed-candidate"]),
            "complete-suite",
        )
        self.assertEqual(comparison["status"], "regression")
        self.assertEqual(
            comparison["comparisons"][0]["reasons"],
            ["artifact-sha-mismatch"],
        )

        second = lab.PrivateRunDirectory(self.root, "second-candidate")
        second_state = self._state("second-candidate", 10, 100)
        second_state.output_file_count = 1
        self.runner._save_state(second, second_state)
        lab._private_write(
            second.evidence / "local-digests.json",
            json.dumps({"health.json": "a" * 64}).encode(),
        )
        with self.assertRaises(lab.LabError):
            self.runner.compare(
                self._suite(
                    "mismatched-repeat-suite",
                    ["changed-candidate", "second-candidate"],
                ),
                "complete-suite",
            )

    def test_cleanup_preserves_nonterminal_runs_without_force(self):
        run_id = "unknown-run"
        directory = lab.PrivateRunDirectory(self.root, run_id)
        state = self._state(run_id, 0, 0)
        state.state = "unknown"
        self.runner._save_state(directory, state)

        with self.assertRaises(lab.LabError):
            self.runner.cleanup(run_id)
        self.assertTrue(directory.path.exists())
        result = self.runner.cleanup(run_id, force=True)
        self.assertEqual(result["status"], "success")
        self.assertFalse(directory.path.exists())

    def test_crash_detection_counts_oversized_reports_even_when_not_copied(self):
        directory = lab.PrivateRunDirectory(self.root, "crash-run")
        count = self.runner._collect_new_crash_logs(
            directory,
            {},
            {"JetsamEvent-1.ips": {"size": 11 * 1024 * 1024}},
        )

        self.assertEqual(count, 1)
        self.assertEqual(list((directory.evidence / "crash-logs").iterdir()), [])

    def test_scrub_removes_payloads_but_keeps_health_free_evidence(self):
        run_id = "scrubbed-run"
        directory = lab.PrivateRunDirectory(self.root, run_id)
        state = self._state(run_id, 1, 1)
        self.runner._save_state(directory, state)
        lab._private_write(directory.payloads / "private.json", b"secret")
        lab._private_write(directory.logs / "progress.log", b"date")
        lab._private_write(directory.evidence / "telemetry.ndjson", b"{}\n")

        result = self.runner.scrub(run_id)

        self.assertEqual(result["status"], "success")
        self.assertEqual(list(directory.payloads.iterdir()), [])
        self.assertEqual(list(directory.logs.iterdir()), [])
        self.assertTrue((directory.evidence / "telemetry.ndjson").exists())
        saved = lab.RunState(**directory.load_json("state.json"))
        self.assertTrue(saved.payloads_scrubbed)

    def test_thirty_day_direct_file_validation_requires_complete_v7_receipt(self):
        run_id = "thirty-day-run"
        directory = lab.PrivateRunDirectory(self.root, run_id)
        generated = directory.payloads / "generated"
        generated.mkdir(mode=0o700)
        artifact = generated / "health.json"
        artifact.write_text('{"schema_version":7}')
        os.chmod(artifact, 0o600)
        receipt = {
            "backend": "direct",
            "job_id": "thirty-day-job",
            "destination_path": str(generated.resolve()),
            "relative_paths": ["health.json"],
            "status": "success",
            "files_written": 1,
            "total_bytes": artifact.stat().st_size,
            "success_count": 30,
            "total_count": 30,
            "failed_date_identifiers": [],
        }
        lab._private_write(
            directory.logs / "cli.stdout",
            (json.dumps(receipt) + "\n").encode(),
        )
        lab._private_write(
            directory.evidence / "telemetry.ndjson",
            b'{"pipeline":"direct-file","phase":"job","outcome":"success",'
            b'"footprint_start_bytes":1,"footprint_peak_bytes":1,'
            b'"footprint_end_bytes":1,"available_capacity_start_bytes":9999999999,'
            b'"available_capacity_end_bytes":9999999999,'
            b'"thermal_state_start":"nominal","thermal_state_end":"nominal"}\n',
        )
        state = self._state(run_id, 1, 1)
        state.scenario = "thirty-day"
        state.job_id = "thirty-day-job"
        state.telemetry_peak_footprint_bytes = 1

        self.runner._validate_run(directory, state)

        self.assertEqual(state.completed_day_count, 30)
        self.assertEqual(state.requested_day_count, 30)
        self.assertEqual(state.schema_versions, [7])
        receipt["success_count"] = 29
        lab._private_write(
            directory.logs / "cli.stdout",
            (json.dumps(receipt) + "\n").encode(),
        )
        with self.assertRaises(lab.LabError):
            self.runner._validate_run(directory, state)

        receipt["success_count"] = 30
        lab._private_write(
            directory.logs / "cli.stdout",
            (json.dumps(receipt) + "\n").encode(),
        )
        (directory.evidence / "telemetry.ndjson").unlink()
        with self.assertRaises(lab.LabError):
            self.runner._validate_run(directory, state)

    def test_direct_cancel_requires_terminal_cancelled_telemetry(self):
        run_id = "cancel-run"
        job_id = "cancel-job"
        directory = lab.PrivateRunDirectory(self.root, run_id)
        job_directory = self.root / "CLIState" / "jobs" / job_id
        job_directory.mkdir(parents=True, mode=0o700)
        lab._private_write(
            job_directory / "record.json",
            b'{"state":"cancelled"}\n',
        )
        terminal = {
            "pipeline": "direct-file",
            "phase": "job",
            "outcome": "cancelled",
            "footprint_start_bytes": 1,
            "footprint_peak_bytes": 1,
            "footprint_end_bytes": 1,
            "available_capacity_start_bytes": 9_999_999_999,
            "available_capacity_end_bytes": 9_999_999_999,
            "thermal_state_start": "nominal",
            "thermal_state_end": "nominal",
        }
        lab._private_write(
            directory.evidence / "telemetry.ndjson",
            (json.dumps(terminal) + "\n").encode(),
        )
        state = self._state(run_id, 1, 1)
        state.scenario = "cancel"
        state.job_id = job_id
        state.telemetry_peak_footprint_bytes = 1

        self.runner._validate_run(directory, state)

        terminal["outcome"] = "success"
        lab._private_write(
            directory.evidence / "telemetry.ndjson",
            (json.dumps(terminal) + "\n").encode(),
        )
        with self.assertRaises(lab.LabError):
            self.runner._validate_run(directory, state)

    def test_public_report_excludes_job_ids_paths_and_digests(self):
        run_id = "private-report-run"
        directory = lab.PrivateRunDirectory(self.root, run_id)
        state = self._state(run_id, 2.5, 42)
        state.job_id = "secret-job-id"
        self.runner._save_state(directory, state)
        report = self.runner.report(run_id)
        encoded = json.dumps(report)
        self.assertNotIn("secret-job-id", encoded)
        self.assertNotIn(str(directory.path), encoded)
        self.assertNotIn("digest", encoded)

    def test_telemetry_terminal_detection_requires_fixed_span(self):
        path = pathlib.Path(self.temporary.name) / "telemetry.ndjson"
        path.write_text(json.dumps({"pipeline": "provider", "phase": "run", "outcome": "success"}) + "\n")
        self.assertFalse(lab._telemetry_has_terminal_lab_span(path))
        path.write_text(json.dumps({"pipeline": "export-lab", "phase": "run", "outcome": "success"}) + "\n")
        self.assertTrue(lab._telemetry_has_terminal_lab_span(path))

    def _state(self, run_id, wall, memory):
        return lab.RunState(
            runner_version=1,
            run_id=run_id,
            target="direct-files",
            scenario="saved-full",
            state="completed",
            created_at_epoch=1,
            updated_at_epoch=2,
            git_commit="abc",
            dirty_patch_sha256="def",
            git_dirty=True,
            app_bundle_id=lab.BUNDLE_ID,
            device_label="test-device",
            wall_seconds=wall,
            telemetry_peak_footprint_bytes=memory,
        )

    def _suite(self, suite_id, run_ids):
        directory = lab.PrivateRunDirectory(self.root, suite_id)
        directory.write_json(
            "suite.json",
            {
                "runner_version": 1,
                "suite_id": suite_id,
                "scenario": "saved-full",
                "targets": ["direct-files"],
                "repeat": 1,
                "run_ids": run_ids,
            },
        )
        return suite_id


if __name__ == "__main__":
    unittest.main()
