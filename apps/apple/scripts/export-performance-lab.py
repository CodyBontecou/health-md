#!/usr/bin/env python3
"""Supervised physical-device export performance lab.

The runner drives only allowlisted Health.md production export surfaces. Health
payloads stay in private per-run directories and are never printed. Reports
contain health-free timing, status, byte-count, and telemetry evidence.
"""

from __future__ import annotations

import argparse
import hashlib
import hmac
import json
import os
import pathlib
import platform
import shutil
import secrets
import signal
import ssl
import stat
import statistics
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
import uuid
from dataclasses import asdict, dataclass, field
from typing import Any, Callable, Iterable, Sequence

TELEMETRY_VERSION = 1
RUNNER_VERSION = 1
BUNDLE_ID = "com.codybontecou.obsidianhealth"
DEFAULT_ROOT = pathlib.Path.home() / "Library" / "Application Support" / "HealthMdPerformanceLab"
TERMINAL_STATES = {"completed", "failed", "cancelled", "invalid"}
TARGETS = ("direct-raw", "direct-files", "local-iphone", "api-endpoint", "connected-mac")
APP_TARGETS = {"local-iphone", "api-endpoint", "connected-mac"}
API_FAULTS = {
    "success", "delay-read", "delay-response", "status-429", "status-500",
    "close-after-bytes", "oversized-response",
}

SCENARIOS: dict[str, dict[str, Any]] = {
    "raw-full": {
        "date_args": ["--yesterday"],
        "selection_args": [],
        "max_days": 1,
    },
    "sleep-summary": {
        "date_args": ["--yesterday"],
        "selection_args": ["--category", "Sleep", "--detail", "summary"],
        "max_days": 1,
    },
    "saved-full": {
        "date_args": ["--yesterday"],
        "selection_args": [],
        "max_days": 1,
    },
    "saved-full-provider-enabled": {
        "date_args": ["--yesterday"],
        "selection_args": [],
        "max_days": 1,
    },
    "saved-full-provider-disabled": {
        "date_args": ["--yesterday"],
        "selection_args": ["--all-metrics", "--detail", "lossless"],
        "max_days": 1,
    },
    "lossless-dense": {
        "date_args": ["--yesterday"],
        "selection_args": ["--category", "Heart", "--detail", "lossless"],
        "max_days": 1,
    },
    "multi-day": {
        "date_args": ["--last", "7"],
        "selection_args": [],
        "max_days": 7,
    },
    "thirty-day": {
        "date_args": ["--last", "30"],
        "selection_args": [],
        "max_days": 30,
        "cli_timeout_seconds": 585,
    },
    "interrupt-resume": {
        "date_args": ["--last", "7"],
        "selection_args": [],
        "max_days": 7,
    },
    "cancel": {
        "date_args": ["--last", "7"],
        "selection_args": [],
        "max_days": 7,
    },
    "large-file-backed-blob": {
        "date_args": [],
        "selection_args": [],
        "max_days": 0,
        "debug_only": True,
    },
}

TARGET_SCENARIOS = {
    "direct-raw": {"raw-full"},
    "direct-files": {
        "sleep-summary", "saved-full", "lossless-dense", "multi-day",
        "thirty-day", "interrupt-resume", "cancel",
    },
    "local-iphone": {
        "sleep-summary", "saved-full", "saved-full-provider-enabled",
        "saved-full-provider-disabled", "lossless-dense", "multi-day",
        "cancel", "large-file-backed-blob",
    },
    "api-endpoint": {
        "sleep-summary", "saved-full", "saved-full-provider-enabled",
        "saved-full-provider-disabled", "lossless-dense", "multi-day", "cancel",
    },
    "connected-mac": {
        "sleep-summary", "saved-full", "saved-full-provider-enabled",
        "saved-full-provider-disabled", "lossless-dense", "multi-day", "cancel",
    },
}


class LabError(RuntimeError):
    pass


@dataclass
class LabConfig:
    root: str = str(DEFAULT_ROOT)
    device: str = "Cody Bontecou’s iPhone"
    bundle_id: str = BUNDLE_ID
    cli_path: str = str(DEFAULT_ROOT / "bin" / "healthmd")
    cli_data_dir: str = str(DEFAULT_ROOT / "CLIState")
    cli_port: int = 17648
    mac_vault: str = str(pathlib.Path.home() / "HealthMdPerformanceLab" / "MacVault")
    local_destination_label: str = "HealthMdPerformanceLab"
    api_sink_url: str = "https://healthmd-lab.local:18443/export"
    api_ca_certificate: str = str(DEFAULT_ROOT / "TLS" / "ca-certificate.pem")
    api_server_certificate: str = str(DEFAULT_ROOT / "TLS" / "server-certificate.pem")
    api_server_private_key: str = str(DEFAULT_ROOT / "TLS" / "server-key.pem")
    api_token_file: str = str(DEFAULT_ROOT / "TLS" / "api-token")
    api_receipt_directory: str = str(DEFAULT_ROOT / "APISink")
    minimum_free_gib: float = 5.0
    minimum_iphone_free_gib: float = 2.0
    maximum_wall_seconds: int = 600
    maximum_iphone_footprint_mib: int = 256
    confirmation_delay_seconds: float = 5.0
    cooldown_seconds: float = 10.0
    allow_unsigned_cli: bool = False
    allow_autonomous_runs: bool = False
    lab_binding: str = ""

    @property
    def root_path(self) -> pathlib.Path:
        return pathlib.Path(os.path.abspath(pathlib.Path(self.root).expanduser()))

    @property
    def config_path(self) -> pathlib.Path:
        return self.root_path / "config.json"


@dataclass
class CommandResult:
    exit_code: int
    wall_seconds: float
    peak_rss_bytes: int | None
    timed_out: bool


@dataclass
class RunState:
    runner_version: int
    run_id: str
    target: str
    scenario: str
    state: str
    created_at_epoch: int
    updated_at_epoch: int
    git_commit: str
    dirty_patch_sha256: str
    git_dirty: bool
    app_bundle_id: str
    device_label: str
    cli_version: str | None = None
    job_id: str | None = None
    wall_seconds: float | None = None
    host_peak_rss_bytes: int | None = None
    output_byte_count: int = 0
    output_file_count: int = 0
    completed_day_count: int | None = None
    requested_day_count: int | None = None
    schema_versions: list[int] = field(default_factory=list)
    telemetry_record_count: int = 0
    telemetry_peak_footprint_bytes: int | None = None
    mac_peak_footprint_bytes: int | None = None
    error_code: str | None = None
    api_fault: str | None = None
    mac_installation_id: str | None = None
    new_crash_report_count: int = 0
    payloads_scrubbed: bool = False


class PrivateRunDirectory:
    def __init__(self, root: pathlib.Path, run_id: str):
        if not _safe_identifier(run_id):
            raise LabError("invalid-run-identifier")
        _ensure_private_directory(root)
        _reject_symlink_components(root / "Runs" / run_id)
        self.root = root
        self.run_id = run_id
        self.path = root / "Runs" / run_id
        self.payloads = self.path / "payloads"
        self.logs = self.path / "logs"
        self.evidence = self.path / "evidence"
        for directory in (self.path, self.payloads, self.logs, self.evidence):
            directory.mkdir(parents=True, exist_ok=True, mode=0o700)
            os.chmod(directory, 0o700)

    def write_json(self, relative: str, value: Any) -> pathlib.Path:
        path = self.path / relative
        if self.path not in path.absolute().parents:
            raise LabError("unsafe-run-relative-path")
        _ensure_private_directory(path.parent)
        data = json.dumps(value, sort_keys=True, indent=2).encode("utf-8") + b"\n"
        _private_write(path, data)
        return path

    def load_json(self, relative: str) -> Any:
        return json.loads((self.path / relative).read_text(encoding="utf-8"))


class LabRunner:
    def __init__(self, config: LabConfig, repo_root: pathlib.Path, dry_run: bool = False):
        self.config = config
        self.repo_root = repo_root
        self.root = config.root_path
        self.dry_run = dry_run
        _ensure_private_directory(self.root)

    def preflight(self, require_live: bool = True) -> dict[str, Any]:
        checks: list[dict[str, Any]] = []

        def record(name: str, ok: bool, detail: str) -> None:
            checks.append({"name": name, "ok": ok, "detail": detail})

        record("host-platform", platform.system() == "Darwin", platform.system())
        binding_ok = _is_lab_binding(self.config.lab_binding)
        record("private-lab-binding", binding_ok, "configured" if binding_ok else "missing")
        free = shutil.disk_usage(self.root).free
        minimum = int(self.config.minimum_free_gib * 1024**3)
        record("free-disk", free >= minimum, f"{free} bytes available")

        cli = pathlib.Path(self.config.cli_path).expanduser()
        record("cli-executable", cli.is_file() and os.access(cli, os.X_OK), str(cli))
        if cli.is_file() and os.access(cli, os.X_OK):
            signed, identity = self._cli_signing_identity(cli)
            record(
                "stable-cli-signing",
                signed or self.config.allow_unsigned_cli,
                identity if signed else "unsigned",
            )

        parsed_api = urllib.parse.urlparse(self.config.api_sink_url)
        api_shape_ok = parsed_api.scheme == "https" and bool(parsed_api.hostname) \
            and parsed_api.port == 18_443 and parsed_api.path == "/export" \
            and not parsed_api.params and not parsed_api.query and not parsed_api.fragment
        token_path = pathlib.Path(self.config.api_token_file).expanduser()
        token_ok = token_path.is_file() and not token_path.is_symlink() \
            and token_path.stat().st_mode & 0o077 == 0
        record(
            "api-sink-https",
            api_shape_ok and token_ok,
            parsed_api.hostname or "invalid",
        )
        if require_live and parsed_api.scheme == "https" and not self.dry_run:
            sink_status = self.api_sink_status()
            record(
                "api-sink-ready",
                sink_status.get("status") == "ready",
                sink_status.get("fault", "unavailable"),
            )

        vault = pathlib.Path(self.config.mac_vault).expanduser()
        expected_vault = pathlib.Path.home() / "HealthMdPerformanceLab" / "MacVault"
        marker = vault / ".healthmd-performance-lab"
        try:
            marker_matches = hmac.compare_digest(
                marker.read_text(encoding="utf-8").strip(),
                self.config.lab_binding,
            )
        except OSError:
            marker_matches = False
        vault_ok = vault.is_absolute() and vault.is_dir() \
            and not vault.is_symlink() and vault.resolve() == expected_vault.resolve() \
            and marker_matches
        record("mac-vault", vault_ok, str(vault))
        record("devicectl", shutil.which("xcrun") is not None, "xcrun")

        if require_live and not self.dry_run:
            device = self._run_command(
                [
                    "xcrun", "devicectl", "device", "info", "details",
                    "--device", self.config.device,
                    "--json-output", str(self.root / "preflight-device.json"),
                    "--log-output", str(self.root / "preflight-device.log"),
                ],
                self.root / "preflight-device.stdout",
                self.root / "preflight-device.stderr",
                timeout=30,
                measure=False,
            )
            record("physical-iphone", device.exit_code == 0, f"exit {device.exit_code}")
            try:
                self._ensure_exact_mac_app_running()
                mac_ready = True
            except LabError:
                mac_ready = False
            record("exact-debug-mac-app", mac_ready, "single exact process required")

        if require_live and cli.is_file() and not self.dry_run:
            devices_path = self.root / "preflight-direct-devices.json"
            direct = self._run_command(
                [str(cli), "direct", "devices"],
                devices_path,
                self.root / "preflight-direct-devices.err",
                timeout=30,
                measure=False,
            )
            device_count = 0
            if direct.exit_code == 0:
                try:
                    document = json.loads(devices_path.read_text(encoding="utf-8"))
                    devices = document.get("devices", []) if isinstance(document, dict) else []
                    device_count = len(devices) if isinstance(devices, list) else 0
                except (OSError, json.JSONDecodeError):
                    pass
            record(
                "direct-trust",
                direct.exit_code == 0 and device_count > 0,
                f"{device_count} trusted device(s)" if direct.exit_code == 0 else f"exit {direct.exit_code}",
            )

        result = {"schema": "healthmd.export_lab_preflight", "checks": checks}
        result["status"] = "success" if all(item["ok"] for item in checks) else "failure"
        return result

    def api_sink_status(self) -> dict[str, Any]:
        parsed = urllib.parse.urlparse(self.config.api_sink_url)
        health_url = urllib.parse.urlunparse((
            parsed.scheme,
            parsed.netloc,
            "/health",
            "",
            "",
            "",
        ))
        certificate = pathlib.Path(self.config.api_ca_certificate).expanduser() \
            if self.config.api_ca_certificate else None
        if certificate is not None and not certificate.is_file():
            return {"status": "unavailable", "fault": "missing-ca"}
        try:
            context = ssl.create_default_context(
                cafile=str(certificate) if certificate is not None else None
            )
            opener = urllib.request.build_opener(
                urllib.request.ProxyHandler({}),
                urllib.request.HTTPSHandler(context=context),
            )
            with opener.open(health_url, timeout=5) as response:
                document = json.loads(response.read(64 * 1024))
            if isinstance(document, dict):
                return document
        except (OSError, ssl.SSLError, urllib.error.URLError, json.JSONDecodeError):
            pass
        return {"status": "unavailable", "fault": "unreachable"}

    def start_api_sink(self, fault: str) -> dict[str, Any]:
        if fault not in {
            "success", "delay-read", "delay-response", "status-429",
            "status-500", "close-after-bytes", "oversized-response",
        }:
            raise LabError("invalid-api-fault")
        current = self.api_sink_status()
        if current.get("status") == "ready":
            if current.get("fault") == fault:
                return {"schema": "healthmd.export_lab_sink_control", "status": "ready", "fault": fault}
            self.stop_api_sink()

        parsed = urllib.parse.urlparse(self.config.api_sink_url)
        script = self.repo_root / "apps" / "apple" / "scripts" / "export-performance-api-sink.py"
        sink_root = pathlib.Path(self.config.api_receipt_directory).expanduser()
        _ensure_private_directory(sink_root)
        pid_path = sink_root / "server.pid"
        stdout_path = sink_root / "server.stdout"
        stderr_path = sink_root / "server.stderr"
        command = [
            sys.executable, str(script),
            "--bind", "0.0.0.0",
            "--port", str(parsed.port or 443),
            "--certificate", str(pathlib.Path(self.config.api_server_certificate).expanduser()),
            "--private-key", str(pathlib.Path(self.config.api_server_private_key).expanduser()),
            "--token-file", str(pathlib.Path(self.config.api_token_file).expanduser()),
            "--receipt-directory", str(sink_root),
            "--fault", fault,
        ]
        with open(stdout_path, "ab") as stdout, open(stderr_path, "ab") as stderr, open(os.devnull, "rb") as stdin:
            os.chmod(stdout_path, 0o600)
            os.chmod(stderr_path, 0o600)
            process = subprocess.Popen(
                command,
                stdin=stdin,
                stdout=stdout,
                stderr=stderr,
                cwd=self.repo_root,
                start_new_session=True,
                env=self._command_environment(),
            )
        _private_write(pid_path, f"{process.pid}\n".encode())
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            status = self.api_sink_status()
            if status.get("status") == "ready":
                return {"schema": "healthmd.export_lab_sink_control", **status}
            if process.poll() is not None:
                break
            time.sleep(0.2)
        raise LabError("api-sink-start-failed")

    def stop_api_sink(self) -> dict[str, Any]:
        sink_root = pathlib.Path(self.config.api_receipt_directory).expanduser()
        pid_path = sink_root / "server.pid"
        if not pid_path.exists():
            return {"schema": "healthmd.export_lab_sink_control", "status": "stopped"}
        raw = pid_path.read_text(encoding="utf-8").strip()
        if not raw.isdigit():
            raise LabError("invalid-api-sink-pid")
        pid = int(raw)
        process = subprocess.run(
            ["ps", "-p", str(pid), "-o", "command="],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
            check=False,
        )
        if process.returncode == 0:
            if "export-performance-api-sink.py" not in process.stdout:
                raise LabError("api-sink-pid-mismatch")
            os.kill(pid, signal.SIGTERM)
            deadline = time.monotonic() + 5
            while time.monotonic() < deadline:
                try:
                    os.kill(pid, 0)
                except ProcessLookupError:
                    break
                time.sleep(0.1)
        pid_path.unlink(missing_ok=True)
        return {"schema": "healthmd.export_lab_sink_control", "status": "stopped"}

    def pair(self) -> dict[str, Any]:
        cli = pathlib.Path(self.config.cli_path).expanduser()
        if not cli.is_file() or not os.access(cli, os.X_OK):
            raise LabError("stable lab CLI is not installed")
        command = [
            str(cli),
            "--port", str(self.config.cli_port),
            "direct", "pair",
        ]
        env = self._command_environment()
        log_path = self.root / "pairing-result.json"
        error_path = self.root / "pairing-instructions.log"
        started = time.monotonic()
        with open(log_path, "wb") as stdout, open(error_path, "wb") as error_log, open(os.devnull, "rb") as stdin:
            os.chmod(log_path, 0o600)
            os.chmod(error_path, 0o600)
            process = subprocess.Popen(
                command,
                stdin=stdin,
                stdout=stdout,
                stderr=subprocess.PIPE,
                env=env,
                cwd=self.repo_root,
            )
            assert process.stderr is not None

            def relay_instructions() -> None:
                for raw_line in iter(process.stderr.readline, b""):
                    error_log.write(raw_line)
                    error_log.flush()
                    sys.stderr.buffer.write(raw_line)
                    sys.stderr.buffer.flush()

            relay = threading.Thread(target=relay_instructions, daemon=True)
            relay.start()
            try:
                exit_code = process.wait(timeout=180)
            except subprocess.TimeoutExpired:
                process.kill()
                process.wait()
                relay.join(timeout=2)
                raise LabError("pairing-timeout")
            relay.join(timeout=2)
        if exit_code != 0:
            raise LabError("pairing-failed")
        try:
            document = json.loads(log_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise LabError("invalid-pairing-result") from error
        if not isinstance(document, dict) or document.get("status") != "success":
            raise LabError("pairing-failed")
        return {
            "schema": "healthmd.export_lab_pairing",
            "status": "success",
            "elapsed_seconds": round(time.monotonic() - started, 3),
        }

    def run_matrix(
        self,
        targets: Sequence[str],
        scenario: str,
        repeat: int,
        supervised_ready: bool,
    ) -> dict[str, Any]:
        if scenario not in SCENARIOS:
            raise LabError(f"unknown scenario: {scenario}")
        if not supervised_ready and not self.dry_run \
                and not self.config.allow_autonomous_runs:
            raise LabError(
                "physical runs require --supervised-ready unless private autonomous mode is enabled"
            )
        invalid = sorted(set(targets).difference(TARGETS))
        if invalid:
            raise LabError(f"unsupported targets: {', '.join(invalid)}")
        if repeat < 1 or repeat > 20:
            raise LabError("repeat must be between 1 and 20")
        incompatible = [
            target for target in targets
            if scenario not in TARGET_SCENARIOS[target]
        ]
        if incompatible:
            raise LabError(
                f"{scenario} is unsupported for: {', '.join(incompatible)}"
            )

        suite_id = self._new_run_id("suite")
        suite = PrivateRunDirectory(self.root, suite_id)
        child_runs: list[str] = []
        child_states: list[str] = []
        stop_requested = False
        for iteration in range(repeat):
            for target in targets:
                run_id = self._new_run_id(f"{target}-{iteration + 1}")
                child_runs.append(run_id)
                if self.dry_run:
                    self._write_planned_run(run_id, target, scenario)
                    child_states.append("planned")
                else:
                    child_state = self.run_one(run_id, target, scenario).state
                    child_states.append(child_state)
                    if child_state != "completed":
                        stop_requested = True
                        break
                    if self.config.cooldown_seconds > 0:
                        time.sleep(min(self.config.cooldown_seconds, 300))
            if stop_requested:
                break
        suite.write_json(
            "suite.json",
            {
                "runner_version": RUNNER_VERSION,
                "suite_id": suite_id,
                "scenario": scenario,
                "targets": list(targets),
                "repeat": repeat,
                "run_ids": child_runs,
            },
        )
        status = "planned" if self.dry_run else (
            "completed" if all(value == "completed" for value in child_states)
            else "incomplete"
        )
        return {
            "schema": "healthmd.export_lab_suite",
            "status": status,
            "suite_id": suite_id,
            "run_count": len(child_runs),
        }

    def run_one(self, run_id: str, target: str, scenario: str) -> RunState:
        if target not in TARGET_SCENARIOS or scenario not in TARGET_SCENARIOS[target]:
            raise LabError("unsupported-target-scenario")
        run = PrivateRunDirectory(self.root, run_id)
        api_fault = None
        if target == "api-endpoint":
            sink_status = self.api_sink_status()
            if sink_status.get("status") != "ready" \
                    or sink_status.get("fault") not in API_FAULTS:
                raise LabError("api-sink-not-ready")
            api_fault = sink_status["fault"]
        commit, dirty, patch_hash = self._git_identity()
        state = RunState(
            runner_version=RUNNER_VERSION,
            run_id=run_id,
            target=target,
            scenario=scenario,
            state="preparing",
            created_at_epoch=int(time.time()),
            updated_at_epoch=int(time.time()),
            git_commit=commit,
            dirty_patch_sha256=patch_hash,
            git_dirty=dirty,
            app_bundle_id=self.config.bundle_id,
            device_label=self.config.device,
            api_fault=api_fault,
        )
        self._save_state(run, state)
        crash_before: dict[str, dict[str, Any]] = {}
        try:
            crash_before = self._snapshot_device_crash_logs(run, "before")
            if target == "connected-mac":
                run.write_json("evidence/mac-vault-before.json", self._snapshot_mac_vault())
                state.mac_installation_id = self._arm_mac(run_id, run)
            self._arm_iphone(run_id, target, scenario, run, state.mac_installation_id)
            self._wait_for_iphone_arm(run)
            state.state = "running"
            self._save_state(run, state)
            if target == "direct-raw":
                self._run_direct_raw(run, state)
            elif target == "direct-files":
                self._run_direct_files(run, state)
            else:
                if scenario == "cancel":
                    time.sleep(1)
                    self._cancel_iphone_run(run_id, run)
                self._wait_for_app_target(run, state)
            self._collect_telemetry(run, state)
            self._validate_run(run, state)
            state.state = "completed"
        except subprocess.TimeoutExpired:
            state.state = "unknown"
            state.error_code = "operation-timeout"
        except Exception as error:
            if state.state != "unknown":
                state.state = "failed"
            state.error_code = state.error_code or _safe_error_code(error)
        finally:
            try:
                crash_after = self._snapshot_device_crash_logs(run, "after")
                state.new_crash_report_count = self._collect_new_crash_logs(
                    run, crash_before, crash_after
                )
                if state.new_crash_report_count > 0 and state.state == "completed":
                    state.state = "invalid"
                    state.error_code = "new-device-crash-report"
            except Exception:
                if state.state == "completed":
                    state.state = "invalid"
                    state.error_code = "crash-log-collection-failed"
            state.updated_at_epoch = int(time.time())
            self._save_state(run, state)
            try:
                self._end_iphone_run(run_id, run)
                if target == "connected-mac":
                    self._end_mac_run(run_id, run)
            except Exception:
                if state.state == "completed":
                    state.state = "invalid"
                    state.error_code = "telemetry-disarm-failed"
                    self._save_state(run, state)
        return state

    def resume(self, run_id: str) -> dict[str, Any]:
        run = self._existing_run(run_id)
        state = RunState(**run.load_json("state.json"))
        if state.target not in {"direct-raw", "direct-files"} or not state.job_id:
            raise LabError("only a direct run with a durable job ID can be resumed")
        if state.state in TERMINAL_STATES:
            raise LabError("terminal runs cannot be resumed")
        self._arm_iphone(state.run_id, state.target, state.scenario, run)
        self._wait_for_iphone_arm(run)
        cli = str(pathlib.Path(self.config.cli_path).expanduser())
        command = [cli, "--port", str(self.config.cli_port), "resume", state.job_id]
        cli_timeout = SCENARIOS[state.scenario].get("cli_timeout_seconds")
        if cli_timeout is not None:
            command += ["--timeout", str(cli_timeout)]
        if state.target == "direct-raw":
            command += ["--output", str(run.payloads / "raw-result.json")]
        result = self._run_command(
            command,
            run.logs / "resume.stdout",
            run.logs / "resume.stderr",
            timeout=self.config.maximum_wall_seconds,
            measure=True,
        )
        state.wall_seconds = (state.wall_seconds or 0) + result.wall_seconds
        state.host_peak_rss_bytes = max(state.host_peak_rss_bytes or 0, result.peak_rss_bytes or 0)
        try:
            if result.exit_code != 0:
                self._classify_direct_failure(state)
                state.error_code = "resume-failed"
            else:
                self._collect_telemetry(run, state)
                self._validate_run(run, state)
                state.state = "completed"
                state.error_code = None
        except Exception as error:
            state.state = "invalid"
            state.error_code = _safe_error_code(error)
        finally:
            state.updated_at_epoch = int(time.time())
            self._save_state(run, state)
            self._end_iphone_run(state.run_id, run)
        return self._public_state(state)

    def report(self, identifier: str) -> dict[str, Any]:
        run = self._existing_run(identifier)
        suite_path = run.path / "suite.json"
        if suite_path.exists():
            suite = run.load_json("suite.json")
            states = [RunState(**self._existing_run(value).load_json("state.json")) for value in suite["run_ids"]]
            return self._suite_report(suite, states)
        state = RunState(**run.load_json("state.json"))
        return self._public_state(state)

    def compare(self, candidate_id: str, baseline_id: str) -> dict[str, Any]:
        candidate = self._states_for_identifier(candidate_id)
        baseline = self._states_for_identifier(baseline_id)
        if any(state.state != "completed" for state in candidate + baseline):
            raise LabError("comparison requires complete successful runs")
        by_key_candidate = self._group_states(candidate)
        by_key_baseline = self._group_states(baseline)
        direct_candidate_keys = {
            key for key in by_key_candidate if key[0] in {"direct-raw", "direct-files"}
        }
        direct_baseline_keys = {
            key for key in by_key_baseline if key[0] in {"direct-raw", "direct-files"}
        }
        if direct_candidate_keys != direct_baseline_keys or any(
            len(by_key_candidate[key]) != len(by_key_baseline[key])
            for key in direct_candidate_keys
        ):
            raise LabError("direct comparison requires matching targets and repeat counts")
        comparisons: list[dict[str, Any]] = []
        overall = "pass"
        for key in sorted(set(by_key_candidate).intersection(by_key_baseline)):
            current = by_key_candidate[key]
            prior = by_key_baseline[key]
            current_wall = statistics.median(value.wall_seconds or 0 for value in current)
            prior_wall = statistics.median(value.wall_seconds or 0 for value in prior)
            wall_limit = prior_wall + max(prior_wall * 0.15, 1.0)
            current_memory = statistics.median(value.telemetry_peak_footprint_bytes or 0 for value in current)
            prior_memory = statistics.median(value.telemetry_peak_footprint_bytes or 0 for value in prior)
            memory_limit = prior_memory + max(prior_memory * 0.20, 16 * 1024**2)
            status = "pass"
            reasons: list[str] = []
            artifact_evidence = "match"
            if key[0] in {"direct-raw", "direct-files"}:
                artifact_evidence = self._artifact_evidence_status([*current, *prior])
            if artifact_evidence != "match":
                status = "regression"
                reasons.append(f"artifact-{artifact_evidence}")
            if current_wall > wall_limit:
                status = "regression"
                reasons.append("wall-time")
            if prior_memory > 0 and current_memory > memory_limit:
                status = "regression"
                reasons.append("iphone-footprint")
            if current_memory > self.config.maximum_iphone_footprint_mib * 1024**2:
                status = "regression"
                reasons.append("absolute-iphone-footprint")
            current_phases = self._phase_medians(current)
            prior_phases = self._phase_medians(prior)
            phase_regressions = []
            for phase_key in sorted(set(current_phases).intersection(prior_phases)):
                phase_limit = prior_phases[phase_key] + max(
                    prior_phases[phase_key] * 0.25,
                    100.0,
                )
                if prior_phases[phase_key] > 0 \
                        and current_phases[phase_key] > phase_limit:
                    status = "regression"
                    reasons.append(f"phase:{phase_key}")
                    phase_regressions.append({
                        "phase": phase_key,
                        "candidate_median_milliseconds": int(current_phases[phase_key]),
                        "baseline_median_milliseconds": int(prior_phases[phase_key]),
                    })
            if status != "pass":
                overall = "regression"
            comparisons.append(
                {
                    "target": key[0],
                    "scenario": key[1],
                    "api_fault": key[2],
                    "status": status,
                    "reasons": reasons,
                    "candidate_median_wall_seconds": round(current_wall, 3),
                    "baseline_median_wall_seconds": round(prior_wall, 3),
                    "candidate_median_iphone_footprint_bytes": int(current_memory),
                    "baseline_median_iphone_footprint_bytes": int(prior_memory),
                    "phase_regressions": phase_regressions,
                }
            )
        if not comparisons:
            raise LabError("candidate and baseline have no matching target/scenario runs")
        return {"schema": "healthmd.export_lab_comparison", "status": overall, "comparisons": comparisons}

    def scrub(self, identifier: str) -> dict[str, Any]:
        run = self._existing_run(identifier)
        suite_path = run.path / "suite.json"
        identifiers = run.load_json("suite.json")["run_ids"] if suite_path.exists() else [identifier]
        for value in identifiers:
            target = self._existing_run(value)
            state = RunState(**target.load_json("state.json"))
            if state.state not in TERMINAL_STATES:
                raise LabError(f"run {value} is {state.state}; preserve it for status/resume")
            if not self.dry_run:
                self._cleanup_iphone_run(target, state)
                if state.target == "connected-mac":
                    self._cleanup_mac_run(state.run_id)
                if state.target == "api-endpoint":
                    self._remove_api_receipts(state.run_id)
                if state.target in {"direct-raw", "direct-files"} and state.job_id:
                    self._cleanup_cli_job(state.job_id)
            for directory in (target.payloads, target.logs):
                _reject_symlink_components(directory)
                if directory.exists():
                    shutil.rmtree(directory)
                _ensure_private_directory(directory)
            for name in (
                "local-digests.json", "api-sink-receipt.json",
                "mac-vault-before.json", "mac-vault-after.json",
            ):
                path = target.evidence / name
                if path.exists() and not path.is_symlink():
                    path.unlink()
            state.payloads_scrubbed = True
            state.updated_at_epoch = int(time.time())
            self._save_state(target, state)
        return {
            "schema": "healthmd.export_lab_scrub",
            "status": "success",
            "run_count": len(identifiers),
        }

    def cleanup(self, identifier: str, force: bool = False) -> dict[str, Any]:
        run = self._existing_run(identifier)
        suite_path = run.path / "suite.json"
        run_ids = [identifier]
        if suite_path.exists():
            run_ids += list(run.load_json("suite.json")["run_ids"])
        removed: list[str] = []
        for value in reversed(run_ids):
            target = self._existing_run(value)
            state_path = target.path / "state.json"
            state = None
            if state_path.exists():
                state = RunState(**target.load_json("state.json"))
                if state.state not in TERMINAL_STATES and not force:
                    raise LabError(f"run {value} is {state.state}; preserve it for status/resume")
            if state is not None and not self.dry_run:
                try:
                    self._cleanup_iphone_run(target, state)
                    if state.target == "connected-mac":
                        self._cleanup_mac_run(state.run_id)
                    if state.target == "api-endpoint":
                        self._remove_api_receipts(state.run_id)
                    if state.target in {"direct-raw", "direct-files"} and state.job_id:
                        self._cleanup_cli_job(state.job_id)
                except Exception:
                    if not force:
                        raise
            shutil.rmtree(target.path)
            removed.append(value)
        return {"schema": "healthmd.export_lab_cleanup", "status": "success", "removed": removed}

    def _cleanup_iphone_run(
        self,
        run: PrivateRunDirectory,
        state: RunState
    ) -> None:
        query = urllib.parse.urlencode({
            "run": state.run_id,
            "target": state.target,
            "binding": self.config.lab_binding,
        })
        self._devicectl_launch(
            f"healthmd://export-lab/cleanup?{query}",
            run.logs / "cleanup-iphone",
        )

    def _cleanup_mac_run(self, run_id: str) -> None:
        root = pathlib.Path(self.config.mac_vault).expanduser().resolve()
        runs_root = (root / "Runs").resolve()
        destination = (runs_root / run_id).resolve()
        if destination.parent != runs_root or runs_root.parent != root:
            raise LabError("unsafe-mac-cleanup")
        if destination.is_symlink():
            raise LabError("mac-cleanup-symlink")
        if destination.exists():
            shutil.rmtree(destination)
        telemetry = self._mac_lab_root() / "Runs" / run_id
        if telemetry.is_symlink():
            raise LabError("mac-telemetry-cleanup-symlink")
        if telemetry.exists():
            shutil.rmtree(telemetry)

    def _cleanup_cli_job(self, job_id: str) -> None:
        if not _safe_identifier(job_id):
            raise LabError("unsafe-cli-job-id")
        jobs_root = pathlib.Path(self.config.cli_data_dir).expanduser() / "jobs"
        destination = jobs_root / job_id
        record_path = destination / "record.json"
        if not record_path.is_file():
            return
        try:
            record = json.loads(record_path.read_text(encoding="utf-8"))
        except (OSError, json.JSONDecodeError) as error:
            raise LabError("invalid-cli-job-record") from error
        if not isinstance(record, dict) or record.get("state") not in {
            "completed", "failed", "cancelled"
        }:
            raise LabError("cli-job-not-terminal")
        _reject_symlink_components(destination)
        if destination.is_symlink() or destination.parent != jobs_root:
            raise LabError("unsafe-cli-job-cleanup")
        shutil.rmtree(destination)

    def _remove_api_receipts(self, run_id: str) -> None:
        path = pathlib.Path(self.config.api_receipt_directory).expanduser() / "receipts.ndjson"
        if not path.exists():
            return
        retained = [
            value for value in _read_ndjson(path)
            if value.get("run_id") != run_id
        ]
        encoded = b"".join(
            json.dumps(value, sort_keys=True, separators=(",", ":")).encode() + b"\n"
            for value in retained
        )
        _private_write(path, encoded)

    def _run_direct_raw(self, run: PrivateRunDirectory, state: RunState) -> None:
        cli = str(pathlib.Path(self.config.cli_path).expanduser())
        output = run.payloads / "raw-result.json"
        command = [cli, "--port", str(self.config.cli_port), "export"]
        command += SCENARIOS[state.scenario]["date_args"]
        command += ["--raw", "--output", str(output)]
        jobs_before = set(self._job_records())
        result = self._run_direct_command(
            command=command,
            run=run,
            state=state,
            raw_output=output,
        )
        self._apply_command_result(state, result)
        state.cli_version = self._cli_version()
        state.job_id = state.job_id or _extract_job_id(output) \
            or _extract_job_id(run.logs / "cli.stdout") \
            or _extract_job_id(run.logs / "cli.stderr") \
            or self._new_direct_job_id(jobs_before)
        if result.exit_code != 0:
            self._classify_direct_failure(state)
            raise LabError("direct raw export failed")
        if output.exists():
            os.chmod(output, 0o600)

    def _run_direct_files(self, run: PrivateRunDirectory, state: RunState) -> None:
        cli = str(pathlib.Path(self.config.cli_path).expanduser())
        destination = run.payloads / "generated"
        destination.mkdir(mode=0o700)
        command = [cli, "--port", str(self.config.cli_port), "export"]
        command += SCENARIOS[state.scenario]["date_args"]
        if state.scenario in {
            "saved-full", "multi-day", "thirty-day", "interrupt-resume", "cancel"
        }:
            command.append("--use-device-settings")
        else:
            command += SCENARIOS[state.scenario]["selection_args"]
        cli_timeout = SCENARIOS[state.scenario].get("cli_timeout_seconds")
        if cli_timeout is not None:
            command += ["--timeout", str(cli_timeout)]
        command += ["--destination", str(destination)]
        jobs_before = set(self._job_records())
        result = self._run_direct_command(
            command=command,
            run=run,
            state=state,
            raw_output=None,
        )
        self._apply_command_result(state, result)
        state.cli_version = self._cli_version()
        state.job_id = state.job_id or _extract_job_id(run.logs / "cli.stdout") \
            or _extract_job_id(run.logs / "cli.stderr") \
            or self._new_direct_job_id(jobs_before)
        if result.exit_code != 0:
            self._classify_direct_failure(state)
            raise LabError("direct generated-file export failed")

    def _new_direct_job_id(self, jobs_before: set[str]) -> str | None:
        records = self._job_records()
        candidates = [job_id for job_id in records if job_id not in jobs_before]
        if not candidates:
            return None
        jobs_root = pathlib.Path(self.config.cli_data_dir).expanduser() / "jobs"
        return max(
            candidates,
            key=lambda job_id: (jobs_root / job_id / "record.json").stat().st_mtime_ns,
        )

    def _classify_direct_failure(self, state: RunState) -> None:
        record = self._job_records().get(state.job_id or "", {})
        job_state = record.get("state")
        state.state = "failed" if job_state in {"failed", "cancelled"} else "unknown"

    def _run_direct_command(
        self,
        command: Sequence[str],
        run: PrivateRunDirectory,
        state: RunState,
        raw_output: pathlib.Path | None,
    ) -> CommandResult:
        if state.scenario == "cancel":
            interrupted, job_id = self._run_until_job_condition(
                command,
                run,
                log_name="cli-cancel-source",
                condition=lambda record: record.get("state") in {
                    "accepted", "preparing", "transferring"
                },
            )
            state.job_id = job_id
            if not interrupted.timed_out or not job_id:
                raise LabError("cancellable-job-not-observed")
            cli = str(pathlib.Path(self.config.cli_path).expanduser())
            cancelled = self._run_command(
                [cli, "--port", str(self.config.cli_port), "cancel", job_id],
                run.logs / "cli.stdout",
                run.logs / "cli.stderr",
                timeout=self.config.maximum_wall_seconds,
                measure=True,
            )
            return CommandResult(
                exit_code=cancelled.exit_code,
                wall_seconds=interrupted.wall_seconds + cancelled.wall_seconds,
                peak_rss_bytes=max(
                    interrupted.peak_rss_bytes or 0,
                    cancelled.peak_rss_bytes or 0,
                ),
                timed_out=cancelled.timed_out,
            )

        if state.scenario != "interrupt-resume":
            return self._run_command(
                command,
                run.logs / "cli.stdout",
                run.logs / "cli.stderr",
                timeout=self.config.maximum_wall_seconds,
                measure=True,
            )

        interrupted, job_id = self._run_until_job_condition(
            command,
            run,
            log_name="cli-interrupted",
            condition=lambda record: record.get("committedPartitions", 0) >= 1
                and record.get("state") not in {"completed", "failed", "cancelled"},
            interruption_signal=signal.SIGKILL,
        )
        state.job_id = job_id
        if not interrupted.timed_out or not job_id:
            raise LabError("durable-checkpoint-not-observed")
        time.sleep(2)
        cli = str(pathlib.Path(self.config.cli_path).expanduser())
        resume = [
            cli,
            "--port", str(self.config.cli_port),
            "resume", job_id,
            "--timeout", str(self.config.maximum_wall_seconds),
        ]
        if raw_output is not None:
            resume += ["--output", str(raw_output)]
        completed = self._run_command(
            resume,
            run.logs / "cli.stdout",
            run.logs / "cli.stderr",
            timeout=self.config.maximum_wall_seconds,
            measure=True,
        )
        return CommandResult(
            exit_code=completed.exit_code,
            wall_seconds=interrupted.wall_seconds + completed.wall_seconds,
            peak_rss_bytes=max(
                interrupted.peak_rss_bytes or 0,
                completed.peak_rss_bytes or 0,
            ),
            timed_out=completed.timed_out,
        )

    def _run_until_job_condition(
        self,
        command: Sequence[str],
        run: PrivateRunDirectory,
        log_name: str,
        condition: Callable[[dict[str, Any]], bool],
        interruption_signal: signal.Signals = signal.SIGINT,
    ) -> tuple[CommandResult, str | None]:
        known_jobs = set(self._job_records())
        stdout_path = run.logs / f"{log_name}.stdout"
        stderr_path = run.logs / f"{log_name}.stderr"
        executable = ["/usr/bin/time", "-lp", *command]
        started = time.monotonic()
        job_id: str | None = None
        condition_observed = False
        with open(stdout_path, "wb") as stdout, open(stderr_path, "wb") as stderr, open(os.devnull, "rb") as stdin:
            os.chmod(stdout_path, 0o600)
            os.chmod(stderr_path, 0o600)
            process = subprocess.Popen(
                executable,
                stdin=stdin,
                stdout=stdout,
                stderr=stderr,
                env=self._command_environment(),
                cwd=self.repo_root,
                start_new_session=True,
            )
            deadline = time.monotonic() + self.config.maximum_wall_seconds
            while time.monotonic() < deadline:
                records = self._job_records()
                new_ids = sorted(set(records).difference(known_jobs))
                if new_ids:
                    job_id = new_ids[-1]
                    record = records[job_id]
                    if condition(record):
                        condition_observed = True
                        break
                if process.poll() is not None:
                    break
                time.sleep(0.25)
            if condition_observed and process.poll() is None:
                os.killpg(process.pid, interruption_signal)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
            elif process.poll() is None:
                os.killpg(process.pid, signal.SIGTERM)
                process.wait(timeout=5)
        elapsed = time.monotonic() - started
        return (
            CommandResult(
                exit_code=124 if condition_observed else (process.returncode or 1),
                wall_seconds=elapsed,
                peak_rss_bytes=_parse_time_peak_rss(stderr_path),
                timed_out=condition_observed,
            ),
            job_id,
        )

    def _job_records(self) -> dict[str, dict[str, Any]]:
        jobs = pathlib.Path(self.config.cli_data_dir).expanduser() / "jobs"
        records: dict[str, dict[str, Any]] = {}
        if not jobs.is_dir():
            return records
        for path in jobs.glob("*/record.json"):
            job_id = path.parent.name
            if not _safe_identifier(job_id) or path.stat().st_size > 2 * 1024 * 1024:
                continue
            try:
                value = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, json.JSONDecodeError):
                continue
            if isinstance(value, dict):
                records[job_id] = value
        return records

    def _wait_for_iphone_arm(self, run: PrivateRunDirectory) -> None:
        deadline = time.monotonic() + 120
        while time.monotonic() < deadline:
            self._pull_telemetry(run, allow_missing=True)
            telemetry = run.evidence / "telemetry.ndjson"
            if telemetry.exists():
                arm = next((
                    record for record in reversed(_read_ndjson(telemetry))
                    if record.get("pipeline") == "export-lab"
                    and record.get("phase") == "arm"
                    and record.get("outcome") == "success"
                ), None)
                if arm is not None:
                    if arm.get("thermal_state_start") in {"serious", "critical"} \
                            or arm.get("thermal_state_end") in {"serious", "critical"}:
                        raise LabError("iphone-thermal-stop")
                    return
            time.sleep(2)
        raise LabError("iphone-confirmation-timeout")

    def _wait_for_app_target(self, run: PrivateRunDirectory, state: RunState) -> None:
        deadline = time.monotonic() + self.config.maximum_wall_seconds
        while time.monotonic() < deadline:
            self._pull_telemetry(run, allow_missing=True)
            telemetry = run.evidence / "telemetry.ndjson"
            if telemetry.exists() and _telemetry_has_terminal_lab_span(telemetry):
                state.wall_seconds = max(
                    (record.get("run_elapsed_milliseconds", 0) for record in _read_ndjson(telemetry)),
                    default=0,
                ) / 1000
                return
            time.sleep(2)
        raise subprocess.TimeoutExpired(cmd="physical app export", timeout=self.config.maximum_wall_seconds)

    def _arm_mac(self, run_id: str, run: PrivateRunDirectory) -> str:
        self._ensure_exact_mac_app_running()
        inbox = self._mac_lab_root() / "MacInbox"
        _ensure_private_directory(inbox)
        _private_write(
            inbox / f"{run_id}.arm",
            (self.config.lab_binding + "\n").encode(),
        )
        telemetry = self._mac_lab_root() / "Runs" / run_id / "telemetry.ndjson"
        deadline = time.monotonic() + 10
        while time.monotonic() < deadline:
            rejection_path = inbox / f"{run_id}.reject"
            if rejection_path.is_file() and not rejection_path.is_symlink():
                reason = rejection_path.read_text(encoding="utf-8").strip()
                rejection_path.unlink()
                if reason in {"bookmark", "access", "path", "marker", "binding", "verifier"}:
                    raise LabError(f"mac-vault-rejected-{reason}")
                raise LabError("mac-vault-rejected")
            peer_path = telemetry.parent / "mac-peer-id"
            if telemetry.exists() and any(
                record.get("pipeline") == "export-lab"
                and record.get("phase") == "mac-arm"
                for record in _read_ndjson(telemetry)
            ) and peer_path.is_file() and not peer_path.is_symlink():
                peer_id = peer_path.read_text(encoding="utf-8").strip().lower()
                try:
                    return str(uuid.UUID(peer_id))
                except ValueError:
                    pass
            time.sleep(0.2)
        raise LabError("mac-telemetry-arm-timeout")

    def _end_mac_run(self, run_id: str, run: PrivateRunDirectory) -> None:
        self._ensure_exact_mac_app_running()
        inbox = self._mac_lab_root() / "MacInbox"
        _ensure_private_directory(inbox)
        _private_write(inbox / f"{run_id}.end", b"end\n")

    def _mac_lab_root(self) -> pathlib.Path:
        pid = self._exact_mac_process_id()
        result = subprocess.run(
            ["lsof", "-a", "-p", str(pid), "-d", "cwd", "-Fn"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
            check=False,
        )
        cwd = next(
            (pathlib.Path(line[1:]).resolve() for line in result.stdout.splitlines() if line.startswith("n/")),
            None,
        )
        containers = (pathlib.Path.home() / "Library" / "Containers").resolve()
        if cwd is None or cwd.name != "Data" or containers not in cwd.parents:
            raise LabError("unable-to-resolve-mac-sandbox")
        return cwd / "Library" / "Application Support" / "HealthMdPerformanceLab"

    def _mac_app_path(self) -> pathlib.Path:
        path = self.repo_root / "apps" / "apple" / "build" / "DerivedData" \
            / "Build" / "Products" / "Debug" / "Health.md.app"
        if not path.is_dir():
            raise LabError("exact Debug Mac app is not built")
        return path

    def _exact_mac_process_id(self) -> int:
        expected = str(self._mac_app_path() / "Contents" / "MacOS" / "Health.md")
        result = subprocess.run(
            ["pgrep", "-x", "Health.md"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=5,
            check=False,
        )
        matches: list[int] = []
        paths: list[str] = []
        for raw_pid in result.stdout.split():
            command = subprocess.run(
                ["ps", "-p", raw_pid, "-o", "command="],
                stdin=subprocess.DEVNULL,
                stdout=subprocess.PIPE,
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=5,
                check=False,
            ).stdout.strip()
            if command:
                paths.append(command)
                if command == expected:
                    matches.append(int(raw_pid))
        if paths != [expected] or len(matches) != 1:
            raise LabError("exact-single-debug-mac-app-required")
        return matches[0]

    def _ensure_exact_mac_app_running(self) -> None:
        _ = self._exact_mac_process_id()

    def _arm_iphone(
        self,
        run_id: str,
        target: str,
        scenario: str,
        run: PrivateRunDirectory,
        mac_installation_id: str | None = None,
    ) -> None:
        if not _is_lab_binding(self.config.lab_binding):
            raise LabError("private-lab-binding-missing")
        token_path = pathlib.Path(self.config.api_token_file).expanduser()
        token = token_path.read_bytes().strip()
        mode = "autonomous" if self.config.allow_autonomous_runs else "confirm"
        values = {
            "run": run_id,
            "target": target,
            "scenario": scenario,
            "binding": self.config.lab_binding,
            "mode": mode,
        }
        if target == "connected-mac":
            if mac_installation_id is None:
                raise LabError("mac-peer-attestation-missing")
            values["peer"] = mac_installation_id
        control_message = "\n".join((
            run_id,
            target,
            scenario,
            self.config.lab_binding,
            mac_installation_id or "-",
            mode,
        )).encode()
        values["control"] = hmac.new(
            token, control_message, hashlib.sha256
        ).hexdigest()
        if target == "api-endpoint":
            message = "\n".join(
                (run_id, target, scenario, self.config.api_sink_url)
            ).encode()
            values["proof"] = hmac.new(token, message, hashlib.sha256).hexdigest()
        query = urllib.parse.urlencode(values)
        url = f"healthmd://export-lab/run?{query}"
        self._devicectl_launch(url, run.logs / "arm")

    def _cancel_iphone_run(self, run_id: str, run: PrivateRunDirectory) -> None:
        url = "healthmd://export-lab/cancel?" + urllib.parse.urlencode({"run": run_id})
        self._devicectl_launch(url, run.logs / "cancel-iphone")

    def _end_iphone_run(self, run_id: str, run: PrivateRunDirectory) -> None:
        url = "healthmd://export-lab/end?" + urllib.parse.urlencode({"run": run_id})
        self._devicectl_launch(url, run.logs / "disarm")

    def _devicectl_launch(self, payload_url: str, log_prefix: pathlib.Path) -> None:
        command = [
            "xcrun", "devicectl", "device", "process", "launch",
            "--device", self.config.device,
            "--payload-url", payload_url,
            "--activate",
            "--json-output", str(log_prefix.with_suffix(".json")),
            "--log-output", str(log_prefix.with_suffix(".log")),
            self.config.bundle_id,
        ]
        result = self._run_command(
            command,
            log_prefix.with_suffix(".stdout"),
            log_prefix.with_suffix(".stderr"),
            timeout=30,
            measure=False,
        )
        if result.exit_code != 0:
            raise LabError("unable to activate the iPhone export lab")

    def _collect_telemetry(self, run: PrivateRunDirectory, state: RunState) -> None:
        self._pull_telemetry(run, allow_missing=False)
        records = _read_ndjson(run.evidence / "telemetry.ndjson")
        if not records:
            raise LabError("physical run produced no telemetry")
        if any(record.get("telemetry_version") != TELEMETRY_VERSION for record in records):
            raise LabError("unsupported telemetry version")
        sequences = [record.get("sequence") for record in records]
        if sequences != list(range(len(records))):
            raise LabError("telemetry sequence is incomplete")
        state.telemetry_record_count = len(records)
        terminal = next(
            (
                record for record in reversed(records)
                if record.get("pipeline") == "export-lab"
                and record.get("phase") == "run"
            ),
            None,
        )
        if terminal is not None:
            state.output_file_count = int(terminal.get("item_count", 0) or 0)
            state.output_byte_count = int(terminal.get("byte_count", 0) or 0)
            if state.target in APP_TARGETS:
                if state.scenario == "cancel":
                    expected = "cancelled"
                elif state.target == "api-endpoint" and state.api_fault in {
                    "status-429", "status-500", "close-after-bytes", "oversized-response"
                }:
                    expected = "failure"
                else:
                    expected = "success"
                if terminal.get("outcome") != expected:
                    raise LabError("physical-app-target-failed")
        peaks = [record.get("footprint_peak_bytes") for record in records]
        state.telemetry_peak_footprint_bytes = max((value for value in peaks if isinstance(value, int)), default=None)
        if state.target == "connected-mac":
            mac_telemetry = self._mac_lab_root() / "Runs" / run.run_id / "telemetry.ndjson"
            mac_records = _read_ndjson(mac_telemetry)
            if not mac_records:
                raise LabError("connected Mac produced no telemetry")
            mac_copy = run.evidence / "mac-telemetry.ndjson"
            _private_write(mac_copy, mac_telemetry.read_bytes())
            mac_peaks = [record.get("footprint_peak_bytes") for record in mac_records]
            state.mac_peak_footprint_bytes = max(
                (value for value in mac_peaks if isinstance(value, int)),
                default=None,
            )

    def _snapshot_device_crash_logs(
        self,
        run: PrivateRunDirectory,
        label: str,
    ) -> dict[str, dict[str, Any]]:
        if label not in {"before", "after"}:
            raise LabError("invalid-crash-snapshot-label")
        output = run.evidence / f"crash-{label}.json"
        result = self._run_command(
            [
                "xcrun", "devicectl", "device", "info", "files",
                "--device", self.config.device,
                "--domain-type", "systemCrashLogs",
                "--filter", "Name CONTAINS[c] 'Health' OR Name BEGINSWITH 'JetsamEvent'",
                "--json-output", str(output),
                "--log-output", str(run.logs / f"crash-{label}.log"),
            ],
            run.logs / f"crash-{label}.stdout",
            run.logs / f"crash-{label}.stderr",
            timeout=45,
            measure=False,
        )
        if result.exit_code != 0 or not output.is_file():
            raise LabError("crash-log-index-unavailable")
        os.chmod(output, 0o600)
        document = json.loads(output.read_text(encoding="utf-8"))
        files = document.get("result", {}).get("files", [])
        index: dict[str, dict[str, Any]] = {}
        for value in files if isinstance(files, list) else []:
            if not isinstance(value, dict):
                continue
            relative = value.get("relativePath")
            metadata = value.get("metadata", {})
            if isinstance(relative, str) and _safe_crash_relative_path(relative) \
                    and isinstance(metadata, dict):
                index[relative] = metadata
        return index

    def _collect_new_crash_logs(
        self,
        run: PrivateRunDirectory,
        before: dict[str, dict[str, Any]],
        after: dict[str, dict[str, Any]],
    ) -> int:
        new_paths = sorted(set(after).difference(before))
        destination = run.evidence / "crash-logs"
        if new_paths:
            _ensure_private_directory(destination)
        copied = 0
        for relative in new_paths[:20]:
            size = after[relative].get("size", 0)
            if not isinstance(size, int) or size < 0 or size > 10 * 1024**2:
                continue
            target = destination / pathlib.Path(relative).name
            result = self._run_command(
                [
                    "xcrun", "devicectl", "device", "copy", "from",
                    "--device", self.config.device,
                    "--domain-type", "systemCrashLogs",
                    "--source", relative,
                    "--destination", str(target),
                    "--json-output", str(run.logs / f"crash-copy-{copied}.json"),
                    "--log-output", str(run.logs / f"crash-copy-{copied}.log"),
                ],
                run.logs / f"crash-copy-{copied}.stdout",
                run.logs / f"crash-copy-{copied}.stderr",
                timeout=45,
                measure=False,
            )
            if result.exit_code == 0 and target.is_file():
                os.chmod(target, 0o600)
                copied += 1
        return len(new_paths)

    def _pull_telemetry(self, run: PrivateRunDirectory, allow_missing: bool) -> None:
        destination = run.evidence / "telemetry.ndjson"
        if destination.exists():
            destination.unlink()
        source = f"Library/Application Support/HealthMdPerformanceLab/Runs/{run.run_id}/telemetry.ndjson"
        command = [
            "xcrun", "devicectl", "device", "copy", "from",
            "--device", self.config.device,
            "--domain-type", "appDataContainer",
            "--domain-identifier", self.config.bundle_id,
            "--source", source,
            "--destination", str(destination),
            "--json-output", str(run.logs / "telemetry-copy.json"),
            "--log-output", str(run.logs / "telemetry-copy.log"),
        ]
        result = self._run_command(
            command,
            run.logs / "telemetry-copy.stdout",
            run.logs / "telemetry-copy.stderr",
            timeout=30,
            measure=False,
        )
        if result.exit_code != 0 and not allow_missing:
            raise LabError("unable to retrieve physical telemetry")
        if destination.exists():
            os.chmod(destination, 0o600)

    def _direct_file_receipt(self, run: PrivateRunDirectory) -> dict[str, Any]:
        resume_path = run.logs / "resume.stdout"
        names = ("resume.stdout",) if resume_path.exists() else ("cli.stdout",)
        for name in names:
            path = run.logs / name
            if not path.is_file() or path.is_symlink() or path.stat().st_size > 1024**2:
                continue
            try:
                value = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, UnicodeError, json.JSONDecodeError):
                continue
            if not isinstance(value, dict) or value.get("backend") != "direct":
                continue
            integer_keys = ("files_written", "total_bytes", "success_count", "total_count")
            if any(type(value.get(key)) is not int or value[key] < 0 for key in integer_keys):
                continue
            failures = value.get("failed_date_identifiers")
            relative_paths = value.get("relative_paths")
            if not isinstance(failures, list) or any(not isinstance(item, str) for item in failures):
                continue
            if not isinstance(relative_paths, list) \
                    or any(not isinstance(item, str) for item in relative_paths):
                continue
            if not isinstance(value.get("job_id"), str) \
                    or not isinstance(value.get("destination_path"), str) \
                    or not isinstance(value.get("status"), str):
                continue
            return value
        raise LabError("direct-file-receipt-missing")

    def _validate_run(self, run: PrivateRunDirectory, state: RunState) -> None:
        if state.scenario == "cancel":
            if state.target in {"direct-raw", "direct-files"}:
                record = self._job_records().get(state.job_id or "", {})
                if record.get("state") != "cancelled":
                    raise LabError("direct-cancellation-not-terminal")
            state.output_file_count = 0
            state.output_byte_count = 0
            if state.target in {"direct-raw", "direct-files"}:
                pipeline = "direct-raw" if state.target == "direct-raw" else "direct-file"
                self._require_direct_terminal_telemetry(
                    run,
                    pipeline=pipeline,
                    outcome="cancelled",
                )
            self._validate_telemetry_environment(run, state)
            return
        files = [path for path in run.payloads.rglob("*") if path.is_file()]
        if files:
            state.output_file_count = len(files)
            state.output_byte_count = sum(path.stat().st_size for path in files)
            state.schema_versions = sorted(set(_safe_schema_versions(files)))
            local_digests = {
                str(path.relative_to(run.payloads)): _sha256(path)
                for path in files
            }
            run.write_json("evidence/local-digests.json", local_digests)
        if state.target == "direct-files":
            receipt = self._direct_file_receipt(run)
            expected_days = int(SCENARIOS[state.scenario]["max_days"])
            state.completed_day_count = receipt["success_count"]
            state.requested_day_count = receipt["total_count"]
            destination = (run.payloads / "generated").resolve()
            relative_paths = sorted(
                str(path.resolve().relative_to(destination))
                for path in files
                if destination in path.resolve().parents
            )
            if receipt["status"] != "success" \
                    or receipt["job_id"].lower() != (state.job_id or "").lower() \
                    or receipt["destination_path"] != str(destination) \
                    or sorted(receipt["relative_paths"]) != relative_paths \
                    or receipt["success_count"] != expected_days \
                    or receipt["total_count"] != expected_days \
                    or receipt["failed_date_identifiers"] \
                    or receipt["files_written"] != state.output_file_count \
                    or receipt["total_bytes"] != state.output_byte_count:
                raise LabError("direct-file-outcome-mismatch")
            if state.schema_versions != [7]:
                raise LabError("direct-file-schema-mismatch")
            self._require_direct_terminal_telemetry(
                run,
                pipeline="direct-file",
                outcome="success",
            )
        if state.target == "direct-raw":
            self._require_direct_terminal_telemetry(
                run,
                pipeline="direct-raw",
                outcome="success",
            )
        if state.target == "connected-mac":
            before = run.load_json("evidence/mac-vault-before.json")
            after = self._snapshot_mac_vault()
            changed = {
                path: facts for path, facts in after.items()
                if before.get(path) != facts
            }
            if not changed:
                raise LabError("connected-mac-produced-no-files")
            state.output_file_count = len(changed)
            state.output_byte_count = sum(int(value["size"]) for value in changed.values())
            run.write_json("evidence/mac-vault-after.json", after)
        if state.target == "api-endpoint":
            receipt = self._api_receipt(state.run_id)
            expected_receipts = {
                "success": {"accepted"},
                "delay-read": {"accepted"},
                "delay-response": {"accepted"},
                "status-429": {"injected-429"},
                "status-500": {"injected-500"},
                "close-after-bytes": {"injected-close"},
                "oversized-response": {
                    "injected-oversized-response", "peer-disconnected"
                },
            }.get(state.api_fault or "")
            if expected_receipts is None or receipt.get("outcome") not in expected_receipts:
                raise LabError("api-sink-outcome-mismatch")
            state.output_byte_count = int(receipt.get("byte_count", 0))
            run.write_json("evidence/api-sink-receipt.json", receipt)
        self._validate_telemetry_environment(run, state)
        if state.target.startswith("direct") and state.output_file_count == 0:
            raise LabError("direct export retained no validated output")

    @staticmethod
    def _require_direct_terminal_telemetry(
        run: PrivateRunDirectory,
        pipeline: str,
        outcome: str,
    ) -> None:
        records = _read_ndjson(run.evidence / "telemetry.ndjson")
        terminal = next((
            record for record in reversed(records)
            if record.get("pipeline") == pipeline
            and record.get("phase") == "job"
            and record.get("outcome") == outcome
        ), None)
        if terminal is None:
            raise LabError("direct-terminal-telemetry-missing")
        integer_fields = (
            "footprint_start_bytes", "footprint_peak_bytes", "footprint_end_bytes",
            "available_capacity_start_bytes", "available_capacity_end_bytes",
        )
        if any(type(terminal.get(field)) is not int for field in integer_fields) \
                or terminal.get("thermal_state_start") not in {
                    "nominal", "fair", "serious", "critical"
                } \
                or terminal.get("thermal_state_end") not in {
                    "nominal", "fair", "serious", "critical"
                }:
            raise LabError("direct-terminal-telemetry-incomplete")

    def _validate_telemetry_environment(
        self,
        run: PrivateRunDirectory,
        state: RunState,
    ) -> None:
        telemetry_records = _read_ndjson(run.evidence / "telemetry.ndjson")
        thermal_states = [
            value
            for record in telemetry_records
            for value in (
                record.get("thermal_state_start"),
                record.get("thermal_state_end"),
            )
            if isinstance(value, str)
        ]
        if not thermal_states or state.telemetry_peak_footprint_bytes is None:
            raise LabError("iphone-environment-telemetry-missing")
        if any(
            record.get("thermal_state_start") in {"serious", "critical"}
            or record.get("thermal_state_end") in {"serious", "critical"}
            for record in telemetry_records
        ):
            raise LabError("iphone-thermal-stop")
        minimum_iphone_capacity = int(self.config.minimum_iphone_free_gib * 1024**3)
        capacities = [
            value
            for record in telemetry_records
            for value in (
                record.get("available_capacity_start_bytes"),
                record.get("available_capacity_end_bytes"),
            )
            if isinstance(value, int)
        ]
        if not capacities:
            raise LabError("iphone-environment-telemetry-missing")
        if min(capacities) < minimum_iphone_capacity:
            raise LabError("iphone-low-disk-stop")
        if any(record.get("phase") == "rate-limit" for record in telemetry_records):
            raise LabError("provider-rate-limit-stop")
        if state.telemetry_peak_footprint_bytes is not None:
            maximum = self.config.maximum_iphone_footprint_mib * 1024**2
            if state.telemetry_peak_footprint_bytes > maximum:
                raise LabError("iphone-footprint-limit")

    def _snapshot_mac_vault(self) -> dict[str, dict[str, int]]:
        configured = pathlib.Path(self.config.mac_vault).expanduser()
        _reject_symlink_components(configured)
        root = configured.resolve()
        expected = (pathlib.Path.home() / "HealthMdPerformanceLab" / "MacVault").resolve()
        if not root.is_dir() or configured.is_symlink() or root != expected:
            raise LabError("unsafe-mac-vault")
        snapshot: dict[str, dict[str, int]] = {}
        for path in root.rglob("*"):
            if path.is_symlink():
                raise LabError("mac-vault-symlink")
            if not path.is_file():
                continue
            relative = str(path.relative_to(root))
            facts = path.stat()
            snapshot[relative] = {
                "size": facts.st_size,
                "modified_ns": facts.st_mtime_ns,
            }
        return snapshot

    def _api_receipt(self, run_id: str) -> dict[str, Any]:
        path = pathlib.Path(self.config.api_receipt_directory).expanduser() / "receipts.ndjson"
        if not path.is_file() or path.stat().st_size > 64 * 1024 * 1024:
            raise LabError("api-sink-receipt-missing")
        matching = [
            value for value in _read_ndjson(path)
            if value.get("run_id") == run_id
        ]
        if not matching:
            raise LabError("api-sink-receipt-missing")
        outcomes = {value.get("outcome") for value in matching}
        outcome = next(iter(outcomes)) if len(outcomes) == 1 else "mixed"
        accepted = outcome == "accepted"
        return {
            "schema": "healthmd.export_lab_sink_summary",
            "status": "accepted" if accepted else "failure",
            "outcome": outcome,
            "request_count": len(matching),
            "byte_count": sum(int(value.get("byte_count", 0)) for value in matching),
            "sha256": [value.get("sha256") for value in matching],
        }

    def _run_command(
        self,
        command: Sequence[str],
        stdout_path: pathlib.Path,
        stderr_path: pathlib.Path,
        timeout: int,
        measure: bool,
    ) -> CommandResult:
        stdout_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        stderr_path.parent.mkdir(parents=True, exist_ok=True, mode=0o700)
        executable = ["/usr/bin/time", "-lp", *command] if measure else list(command)
        env = self._command_environment()
        started = time.monotonic()
        timed_out = False
        exit_code = 0
        with open(stdout_path, "wb") as stdout, open(stderr_path, "wb") as stderr, open(os.devnull, "rb") as stdin:
            os.chmod(stdout_path, 0o600)
            os.chmod(stderr_path, 0o600)
            process = subprocess.Popen(
                executable,
                stdin=stdin,
                stdout=stdout,
                stderr=stderr,
                env=env,
                cwd=self.repo_root,
                start_new_session=True,
            )
            try:
                exit_code = process.wait(timeout=timeout)
            except subprocess.TimeoutExpired:
                timed_out = True
                exit_code = 124
                os.killpg(process.pid, signal.SIGTERM)
                try:
                    process.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    os.killpg(process.pid, signal.SIGKILL)
                    process.wait(timeout=5)
        wall = time.monotonic() - started
        peak = _parse_time_peak_rss(stderr_path) if measure else None
        return CommandResult(exit_code, wall, peak, timed_out)

    def _command_environment(self) -> dict[str, str]:
        data_directory = pathlib.Path(self.config.cli_data_dir).expanduser()
        _ensure_private_directory(data_directory)
        env = dict(os.environ)
        env.update({
            "NO_COLOR": "1",
            "TERM": "dumb",
            "HEALTHMD_CLI_DATA_DIR": str(data_directory),
        })
        return env

    def _apply_command_result(self, state: RunState, result: CommandResult) -> None:
        state.wall_seconds = result.wall_seconds
        state.host_peak_rss_bytes = result.peak_rss_bytes
        if result.timed_out:
            state.error_code = "operation-timeout"

    def _save_state(self, run: PrivateRunDirectory, state: RunState) -> None:
        state.updated_at_epoch = int(time.time())
        run.write_json("state.json", asdict(state))

    def _public_state(self, state: RunState) -> dict[str, Any]:
        return {
            "schema": "healthmd.export_lab_run",
            "run_id": state.run_id,
            "target": state.target,
            "scenario": state.scenario,
            "state": state.state,
            "wall_seconds": state.wall_seconds,
            "host_peak_rss_bytes": state.host_peak_rss_bytes,
            "iphone_peak_footprint_bytes": state.telemetry_peak_footprint_bytes,
            "mac_peak_footprint_bytes": state.mac_peak_footprint_bytes,
            "output_file_count": state.output_file_count,
            "output_byte_count": state.output_byte_count,
            "completed_day_count": state.completed_day_count,
            "requested_day_count": state.requested_day_count,
            "schema_versions": state.schema_versions,
            "telemetry_record_count": state.telemetry_record_count,
            "error_code": state.error_code,
            "api_fault": state.api_fault,
            "new_crash_report_count": state.new_crash_report_count,
            "payloads_scrubbed": state.payloads_scrubbed,
        }

    def _suite_report(self, suite: dict[str, Any], states: Sequence[RunState]) -> dict[str, Any]:
        return {
            "schema": "healthmd.export_lab_suite_report",
            "suite_id": suite["suite_id"],
            "scenario": suite["scenario"],
            "status": "completed" if all(value.state == "completed" for value in states) else "incomplete",
            "runs": [self._public_state(value) for value in states],
        }

    def _states_for_identifier(self, identifier: str) -> list[RunState]:
        run = self._existing_run(identifier)
        if (run.path / "suite.json").exists():
            suite = run.load_json("suite.json")
            return [RunState(**self._existing_run(value).load_json("state.json")) for value in suite["run_ids"]]
        return [RunState(**run.load_json("state.json"))]

    def _phase_medians(self, states: Sequence[RunState]) -> dict[str, float]:
        totals_by_phase: dict[str, list[int]] = {}
        for state in states:
            run = self._existing_run(state.run_id)
            records = _read_ndjson(run.evidence / "telemetry.ndjson")
            records += _read_ndjson(run.evidence / "mac-telemetry.ndjson")
            run_totals: dict[str, int] = {}
            for record in records:
                pipeline = record.get("pipeline")
                phase = record.get("phase")
                elapsed = record.get("elapsed_milliseconds")
                if not isinstance(pipeline, str) or not isinstance(phase, str) \
                        or not isinstance(elapsed, int):
                    continue
                key = f"{pipeline}/{phase}"
                run_totals[key] = run_totals.get(key, 0) + elapsed
            for key, value in run_totals.items():
                totals_by_phase.setdefault(key, []).append(value)
        return {
            key: statistics.median(values)
            for key, values in totals_by_phase.items()
            if values
        }

    def _artifact_evidence_status(self, states: Sequence[RunState]) -> str:
        canonical: str | None = None
        for state in states:
            path = self._existing_run(state.run_id).evidence / "local-digests.json"
            if not path.is_file() or path.is_symlink() or path.stat().st_size > 2 * 1024**2:
                return "evidence-missing"
            try:
                value = json.loads(path.read_text(encoding="utf-8"))
            except (OSError, UnicodeError, json.JSONDecodeError):
                return "evidence-invalid"
            if not isinstance(value, dict) or len(value) != state.output_file_count:
                return "evidence-invalid"
            if any(
                not isinstance(key, str)
                or not isinstance(digest, str)
                or len(digest) != 64
                or any(character not in "0123456789abcdef" for character in digest)
                for key, digest in value.items()
            ):
                return "evidence-invalid"
            encoded = json.dumps(value, sort_keys=True, separators=(",", ":"))
            if canonical is None:
                canonical = encoded
            elif encoded != canonical:
                return "sha-mismatch"
        return "match" if canonical is not None else "evidence-missing"

    @staticmethod
    def _group_states(
        states: Iterable[RunState]
    ) -> dict[tuple[str, str, str], list[RunState]]:
        grouped: dict[tuple[str, str, str], list[RunState]] = {}
        for state in states:
            if state.state != "completed":
                continue
            grouped.setdefault(
                (state.target, state.scenario, state.api_fault or "none"),
                []
            ).append(state)
        return grouped

    def _existing_run(self, run_id: str) -> PrivateRunDirectory:
        if not _safe_identifier(run_id):
            raise LabError("invalid run identifier")
        path = self.root / "Runs" / run_id
        _reject_symlink_components(path)
        if not path.is_dir() or path.is_symlink():
            raise LabError("run does not exist")
        return PrivateRunDirectory(self.root, run_id)

    def _write_planned_run(self, run_id: str, target: str, scenario: str) -> None:
        run = PrivateRunDirectory(self.root, run_id)
        run.write_json(
            "plan.json",
            {"run_id": run_id, "target": target, "scenario": scenario, "state": "planned"},
        )

    def _new_run_id(self, prefix: str) -> str:
        safe_prefix = prefix.replace("_", "-")[:24]
        return f"{safe_prefix}-{uuid.uuid4().hex[:16]}"

    def _cli_version(self) -> str | None:
        path = pathlib.Path(self.config.cli_path).expanduser()
        if not path.is_file():
            return None
        result = subprocess.run(
            [str(path), "--version"],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.DEVNULL,
            text=True,
            timeout=15,
            check=False,
            env=self._command_environment(),
        )
        return result.stdout.strip()[:128] if result.returncode == 0 else None

    @staticmethod
    def _cli_signing_identity(path: pathlib.Path) -> tuple[bool, str]:
        result = subprocess.run(
            ["codesign", "-dv", "--verbose=4", str(path)],
            stdin=subprocess.DEVNULL,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=15,
            check=False,
        )
        text = result.stderr
        identity = next((line.partition("=")[2] for line in text.splitlines() if line.startswith("Authority=")), "")
        identifier = next((line.partition("=")[2] for line in text.splitlines() if line.startswith("Identifier=")), "")
        return result.returncode == 0 and bool(identifier), f"{identifier} {identity}".strip()

    def _git_identity(self) -> tuple[str, bool, str]:
        commit = subprocess.run(
            ["git", "rev-parse", "HEAD"], cwd=self.repo_root,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, text=True, check=True,
        ).stdout.strip()
        diff = subprocess.run(
            ["git", "diff", "--binary", "HEAD"], cwd=self.repo_root,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True,
        ).stdout
        untracked = subprocess.run(
            ["git", "ls-files", "--others", "--exclude-standard"], cwd=self.repo_root,
            stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=True,
        ).stdout
        digest = hashlib.sha256(diff + b"\0" + untracked).hexdigest()
        return commit, bool(diff or untracked), digest


def load_config(path: pathlib.Path | None) -> LabConfig:
    config = LabConfig()
    selected = path or config.config_path
    _reject_symlink_components(selected)
    if selected.exists():
        mode = selected.stat().st_mode & 0o777
        if mode & 0o077:
            raise LabError("lab config must not be group/world accessible")
        raw = json.loads(selected.read_text(encoding="utf-8"))
        allowed = set(LabConfig.__dataclass_fields__)
        unknown = sorted(set(raw).difference(allowed))
        if unknown:
            raise LabError(f"unknown config keys: {', '.join(unknown)}")
        config = LabConfig(**raw)
    return config


def initialize_config(path: pathlib.Path | None) -> dict[str, Any]:
    config = LabConfig(lab_binding=secrets.token_hex(32))
    root = path.parent if path else config.root_path
    _ensure_private_directory(root)
    target = path or (root / "config.json")
    if target.exists():
        raise LabError("config already exists")
    _private_write(target, json.dumps(asdict(config), sort_keys=True, indent=2).encode() + b"\n")
    mac_vault = pathlib.Path(config.mac_vault).expanduser()
    _ensure_private_directory(mac_vault)
    _private_write(mac_vault / ".healthmd-performance-lab", (config.lab_binding + "\n").encode())
    return {"schema": "healthmd.export_lab_init", "status": "success", "config": str(target)}


def _reject_symlink_components(path: pathlib.Path) -> None:
    absolute = pathlib.Path(os.path.abspath(path.expanduser()))
    current = pathlib.Path(absolute.anchor)
    for component in absolute.parts[1:]:
        current /= component
        try:
            mode = os.lstat(current).st_mode
        except FileNotFoundError:
            continue
        if stat.S_ISLNK(mode) and current not in {
            pathlib.Path("/var"), pathlib.Path("/tmp"), pathlib.Path("/etc")
        }:
            raise LabError("private-path-symlink")


def _ensure_private_directory(path: pathlib.Path) -> None:
    _reject_symlink_components(path)
    path.mkdir(parents=True, exist_ok=True, mode=0o700)
    _reject_symlink_components(path)
    os.chmod(path, 0o700)


def _private_write(path: pathlib.Path, data: bytes) -> None:
    _ensure_private_directory(path.parent)
    _reject_symlink_components(path)
    temporary = path.parent / f".{path.name}.{uuid.uuid4().hex}.tmp"
    flags = os.O_WRONLY | os.O_CREAT | os.O_EXCL | getattr(os, "O_NOFOLLOW", 0)
    descriptor = os.open(temporary, flags, 0o600)
    try:
        view = memoryview(data)
        while view:
            written = os.write(descriptor, view)
            view = view[written:]
        os.fsync(descriptor)
        os.fchmod(descriptor, 0o600)
    finally:
        os.close(descriptor)
    try:
        os.replace(temporary, path)
        directory_descriptor = os.open(path.parent, os.O_RDONLY)
        try:
            os.fsync(directory_descriptor)
        finally:
            os.close(directory_descriptor)
    finally:
        if temporary.exists():
            temporary.unlink()


def _is_lab_binding(value: str) -> bool:
    return len(value) == 64 and all(character in "0123456789abcdef" for character in value)


def _safe_crash_relative_path(value: str) -> bool:
    path = pathlib.PurePosixPath(value)
    return len(value.encode()) <= 512 and not path.is_absolute() \
        and all(part not in {"", ".", ".."} for part in path.parts)


def _safe_identifier(value: str) -> bool:
    return 1 <= len(value.encode()) <= 64 and value[0].isalnum() and all(
        character.isascii() and (character.isalnum() or character in "-_.") for character in value
    )


def _safe_error_code(error: Exception) -> str:
    if isinstance(error, LabError):
        value = str(error).lower().replace(" ", "-")
        filtered = "".join(character for character in value if character.isalnum() or character == "-")
        return filtered[:64] or "lab-error"
    return error.__class__.__name__.lower()[:64]


def _parse_time_peak_rss(path: pathlib.Path) -> int | None:
    for line in path.read_text(encoding="utf-8", errors="replace").splitlines():
        if "maximum resident set size" in line:
            value = line.strip().split()[0]
            if value.isdigit():
                return int(value)
    return None


def _extract_job_id(path: pathlib.Path) -> str | None:
    if not path.exists() or path.stat().st_size > 64 * 1024**2:
        return None
    try:
        text = path.read_text(encoding="utf-8")
    except UnicodeDecodeError:
        return None
    candidates = [text, *reversed(text.splitlines())]
    for candidate in candidates:
        try:
            document = json.loads(candidate)
        except json.JSONDecodeError:
            continue
        if isinstance(document, dict):
            value = document.get("job_id")
            if isinstance(value, str) and len(value) <= 64:
                return value
            raw = document.get("raw_result")
            if isinstance(raw, dict) and isinstance(raw.get("job_id"), str):
                return raw["job_id"][:64]
    return None


def _safe_schema_versions(files: Iterable[pathlib.Path]) -> list[int]:
    versions: list[int] = []
    for path in files:
        if path.suffix.lower() != ".json" or path.stat().st_size > 128 * 1024**2:
            continue
        try:
            document = json.loads(path.read_text(encoding="utf-8"))
        except (json.JSONDecodeError, UnicodeDecodeError, OSError):
            continue
        if isinstance(document, dict):
            value = document.get("schema_version")
            if isinstance(value, int):
                versions.append(value)
            raw = document.get("raw_result")
            if isinstance(raw, dict):
                for day in raw.get("days", []):
                    health = day.get("health_data") if isinstance(day, dict) else None
                    if isinstance(health, dict) and isinstance(health.get("schema_version"), int):
                        versions.append(health["schema_version"])
    return versions


def _sha256(path: pathlib.Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _read_ndjson(path: pathlib.Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    records: list[dict[str, Any]] = []
    with path.open("r", encoding="utf-8") as handle:
        for line in handle:
            if not line.strip():
                continue
            value = json.loads(line)
            if not isinstance(value, dict):
                raise LabError("telemetry record is not an object")
            records.append(value)
    return records


def _telemetry_has_terminal_lab_span(path: pathlib.Path) -> bool:
    return any(
        record.get("pipeline") == "export-lab"
        and record.get("phase") == "run"
        and record.get("outcome") in {"success", "failure", "cancelled"}
        for record in _read_ndjson(path)
    )


def find_repo_root() -> pathlib.Path:
    here = pathlib.Path(__file__).resolve()
    result = subprocess.run(
        ["git", "rev-parse", "--show-toplevel"],
        cwd=here.parent,
        stdout=subprocess.PIPE,
        stderr=subprocess.DEVNULL,
        text=True,
        check=True,
    )
    return pathlib.Path(result.stdout.strip()).resolve()


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--config", type=pathlib.Path)
    parser.add_argument("--dry-run", action="store_true")
    subparsers = parser.add_subparsers(dest="command", required=True)

    subparsers.add_parser("init")
    subparsers.add_parser("pair")
    sink_start = subparsers.add_parser("sink-start")
    sink_start.add_argument(
        "--fault",
        choices=[
            "success", "delay-read", "delay-response", "status-429",
            "status-500", "close-after-bytes", "oversized-response",
        ],
        default="success",
    )
    subparsers.add_parser("sink-stop")
    subparsers.add_parser("sink-status")
    preflight = subparsers.add_parser("preflight")
    preflight.add_argument("--offline", action="store_true")

    run = subparsers.add_parser("run")
    run.add_argument("--targets", default="direct-raw,direct-files")
    run.add_argument("--scenario", choices=sorted(SCENARIOS), default="saved-full")
    run.add_argument("--repeat", type=int, default=1)
    run.add_argument("--supervised-ready", action="store_true")

    resume = subparsers.add_parser("resume")
    resume.add_argument("run_id")

    report = subparsers.add_parser("report")
    report.add_argument("identifier")

    compare = subparsers.add_parser("compare")
    compare.add_argument("candidate")
    compare.add_argument("baseline")

    scrub = subparsers.add_parser("scrub")
    scrub.add_argument("identifier")

    cleanup = subparsers.add_parser("cleanup")
    cleanup.add_argument("identifier")
    cleanup.add_argument("--force", action="store_true")
    return parser


def main(argv: Sequence[str] | None = None) -> int:
    parser = build_parser()
    arguments = parser.parse_args(argv)
    try:
        if arguments.command == "init":
            result = initialize_config(arguments.config)
        else:
            config = load_config(arguments.config)
            runner = LabRunner(config, find_repo_root(), dry_run=arguments.dry_run)
            if arguments.command == "pair":
                result = runner.pair()
            elif arguments.command == "sink-start":
                result = runner.start_api_sink(arguments.fault)
            elif arguments.command == "sink-stop":
                result = runner.stop_api_sink()
            elif arguments.command == "sink-status":
                result = {"schema": "healthmd.export_lab_sink_control", **runner.api_sink_status()}
            elif arguments.command == "preflight":
                result = runner.preflight(require_live=not arguments.offline)
            elif arguments.command == "run":
                targets = [value.strip() for value in arguments.targets.split(",") if value.strip()]
                result = runner.run_matrix(
                    targets=targets,
                    scenario=arguments.scenario,
                    repeat=arguments.repeat,
                    supervised_ready=arguments.supervised_ready,
                )
            elif arguments.command == "resume":
                result = runner.resume(arguments.run_id)
            elif arguments.command == "report":
                result = runner.report(arguments.identifier)
            elif arguments.command == "compare":
                result = runner.compare(arguments.candidate, arguments.baseline)
            elif arguments.command == "scrub":
                result = runner.scrub(arguments.identifier)
            elif arguments.command == "cleanup":
                result = runner.cleanup(arguments.identifier, force=arguments.force)
            else:
                raise LabError("unsupported command")
        print(json.dumps(result, sort_keys=True, indent=2))
        return 0 if result.get("status") not in {"failure", "regression", "incomplete"} else 1
    except (LabError, OSError, subprocess.SubprocessError, json.JSONDecodeError) as error:
        print(
            json.dumps(
                {
                    "schema": "healthmd.export_lab_error",
                    "status": "failure",
                    "error": _safe_error_code(error),
                },
                sort_keys=True,
            )
        )
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
