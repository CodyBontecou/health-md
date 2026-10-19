#!/usr/bin/env python3
"""Run the unsigned iOS unit suite with a fresh simulator and isolated outputs."""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import platform
import re
import signal
import subprocess
import sys
import tempfile
import time

from select_ios_simulator import PREFERRED_IPHONES, runtime_version, sdk_major


APPLE_ROOT = Path(__file__).resolve().parents[1]
REPO_ROOT = APPLE_ROOT.parents[1]


def capture(*args: str) -> str:
    return subprocess.check_output(args, text=True).strip()


def select_runtime(payload: dict, sdk: str) -> tuple[str, str]:
    candidates = []
    ranks = {name: index for index, name in enumerate(PREFERRED_IPHONES)}
    for runtime in payload.get("runtimes", []):
        version = runtime_version(runtime.get("identifier", ""))
        if not version or version[0] < 17 or version[0] > sdk_major(sdk) or not runtime.get("isAvailable"):
            continue
        for device in runtime.get("supportedDeviceTypes", []):
            if device.get("productFamily") != "iPhone":
                continue
            candidates.append((version, ranks.get(device.get("name"), len(ranks)),
                               device["identifier"], runtime["identifier"]))
    if not candidates:
        raise ValueError(f"No installed compatible iPhone runtime for SDK {sdk}")
    selected = sorted(candidates, key=lambda item: (
        -item[0][0], -item[0][1], -item[0][2], item[1], item[2]))[0]
    return selected[2], selected[3]


def validate_summary(summary: dict) -> None:
    if (summary.get("result") != "Passed" or type(summary.get("failedTests")) is not int
            or summary["failedTests"] != 0 or type(summary.get("passedTests")) is not int
            or summary["passedTests"] <= 0):
        raise ValueError("xcresult must report Passed with nonzero passed tests and no failures")


def preflight() -> dict:
    if platform.system() != "Darwin" or platform.machine() != "arm64":
        raise ValueError("The pilot requires a native Apple Silicon Mac")
    translated = subprocess.run(["sysctl", "-in", "sysctl.proc_translated"], text=True,
                                stdout=subprocess.PIPE, stderr=subprocess.DEVNULL, check=False)
    if translated.stdout.strip() == "1":
        raise ValueError("Run the pilot natively, outside Rosetta")
    swift = capture("xcrun", "swift", "--version")
    version = re.search(r"Swift version (\d+)\.(\d+)", swift)
    if not version or tuple(map(int, version.groups())) < (6, 3):
        raise ValueError("The installed Xcode must provide Swift 6.3 or newer")
    sdk = capture("xcrun", "--sdk", "iphonesimulator", "--show-sdk-version")
    device, runtime = select_runtime(json.loads(capture("xcrun", "simctl", "list", "runtimes", "-j")), sdk)
    return {"xcode": capture("xcodebuild", "-version"), "swift": swift,
            "sdk": sdk, "device_type": device, "runtime": runtime}


def run_pilot(output: Path, source_sha: str | None) -> int:
    tools = preflight()
    sha = capture("git", "-C", str(REPO_ROOT), "rev-parse", "HEAD")
    if source_sha and (not re.fullmatch(r"[0-9a-f]{40}", source_sha) or sha != source_sha):
        raise ValueError("PILOT_SOURCE_SHA must equal the checked-out 40-character commit")
    dirty = capture("git", "-C", str(REPO_ROOT), "status", "--porcelain", "--untracked-files=all")
    if dirty:
        raise ValueError("The pilot must run in a clean committed checkout")
    # Workflow preflight owns the parent; this exclusive child prevents stale result reuse.
    output = output / "ios-unit"
    output.mkdir(parents=True, exist_ok=False)
    logs = output / "logs"
    logs.mkdir()
    simulator = None
    active = None
    interrupted = False
    started = time.monotonic()
    receipt = {"schema": "healthmd.apple.local-pilot/1", "source_sha": sha,
               "profile": "unsigned-ios-unit-only", "toolchain": tools, "result": "failed"}
    if os.environ.get("GITHUB_ACTIONS") == "true":
        receipt["controller"] = {key: os.environ.get(f"GITHUB_{key.upper()}") for key in
                                 ("repository", "workflow_ref", "workflow_sha", "run_id", "run_attempt")}

    def interrupt(signum, _frame):
        nonlocal interrupted
        interrupted = True
        raise InterruptedError("Pilot interrupted")

    previous_handlers = {sig: signal.signal(sig, interrupt) for sig in (signal.SIGINT, signal.SIGTERM)}

    def logged(args, filename):
        nonlocal active
        print(f"Running {args[0]} ({filename})", flush=True)
        with (logs / filename).open("w") as log:
            active = subprocess.Popen(args, cwd=APPLE_ROOT, stdout=log,
                                      stderr=subprocess.STDOUT, start_new_session=True)
            code = active.wait()
            active = None
        if code:
            raise subprocess.CalledProcessError(code, args)

    try:
        logged(["make", "prepare-healthmd-core-rust"], "prepare-core.log")
        simulator = capture("xcrun", "simctl", "create", f"Healthmd Local Pilot {output.name}",
                            tools["device_type"], tools["runtime"])
        if not re.fullmatch(r"[0-9A-Fa-f-]{36}", simulator):
            raise ValueError("simctl returned an invalid device UUID")
        receipt["simulator_udid"] = simulator
        logged(["xcrun", "simctl", "boot", simulator], "simulator-boot.log")
        logged(["xcrun", "simctl", "bootstatus", simulator, "-b"], "simulator-ready.log")
        result = output / "HealthMd-iOS.xcresult"
        logged(["xcodebuild", "test", "-project", "HealthMd.xcodeproj", "-scheme", "HealthMd-Tests-iOS",
                "-configuration", "Debug-iOS", "-destination", f"platform=iOS Simulator,id={simulator}",
                "-derivedDataPath", str(output / "DerivedData"), "-resultBundlePath", str(result),
                "-parallel-testing-enabled", "NO", "-maximum-concurrent-test-simulator-destinations", "1",
                "-collect-test-diagnostics", "never",
                "-test-timeouts-enabled", "YES", "-default-test-execution-time-allowance", "120",
                "-maximum-test-execution-time-allowance", "300", "CODE_SIGNING_ALLOWED=NO",
                "CODE_SIGNING_REQUIRED=NO", "CODE_SIGN_IDENTITY=", "DEVELOPMENT_TEAM=",
                "PROVISIONING_PROFILE_SPECIFIER="], "xcodebuild-ios.log")
        summary = json.loads(capture("xcrun", "xcresulttool", "get", "test-results", "summary", "--path", str(result)))
        (logs / "ios-test-summary.json").write_text(json.dumps(summary, indent=2) + "\n")
        validate_summary(summary)
        receipt.update(result="passed", passed_tests=summary["passedTests"],
                       skipped_tests=summary.get("skippedTests", 0))
        print(f"Passed: {summary['passedTests']} iOS unit tests", flush=True)
        return 0
    except (subprocess.CalledProcessError, ValueError, InterruptedError) as error:
        receipt["error"] = str(error)
        if interrupted:
            receipt["result"] = "interrupted"
        print(f"Pilot failed: {error}. Logs: {logs}", file=sys.stderr)
        return 130 if interrupted else 1
    finally:
        # Ignore further interrupts while stopping only this run's process/device.
        for sig in previous_handlers:
            signal.signal(sig, signal.SIG_IGN)
        if active and active.poll() is None:
            def stop_group(signum):
                try:
                    os.killpg(active.pid, signum)
                except ProcessLookupError:
                    pass  # The child can exit between poll and signal.
                except OSError as error:
                    receipt.setdefault("cleanup_errors", []).append(f"process-group: {error}")

            stop_group(signal.SIGTERM)
            try:
                active.wait(timeout=10)
            except subprocess.TimeoutExpired:
                stop_group(signal.SIGKILL)
                try:
                    active.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    receipt.setdefault("cleanup_errors", []).append("process-group did not exit")
        if simulator and re.fullmatch(r"[0-9A-Fa-f-]{36}", simulator):
            for action in ("shutdown", "delete"):
                try:
                    cleanup = subprocess.run(["xcrun", "simctl", action, simulator], stdout=subprocess.DEVNULL,
                                             stderr=subprocess.DEVNULL, timeout=30, check=False)
                    if cleanup.returncode:
                        receipt.setdefault("cleanup_errors", []).append(action)
                except (OSError, subprocess.TimeoutExpired):
                    receipt.setdefault("cleanup_errors", []).append(action)
        receipt["elapsed_seconds"] = round(time.monotonic() - started, 2)
        (output / "receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
        for sig, handler in previous_handlers.items():
            signal.signal(sig, handler)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--preflight", action="store_true", help="Check toolchain/runtime without creating a simulator")
    parser.add_argument("--output-dir", default=os.environ.get("PILOT_OUTPUT_DIR"))
    args = parser.parse_args()
    try:
        if args.preflight:
            print(json.dumps(preflight(), indent=2))
            return 0
        if args.output_dir:
            output = Path(args.output_dir).expanduser().resolve()
        else:
            parent = APPLE_ROOT / "build" / "local-actions-pilot"
            parent.mkdir(parents=True, exist_ok=True)
            # Reserve a unique name, then let run_pilot create it exclusively.
            output = Path(tempfile.mkdtemp(prefix="run-", dir=parent))
            output.rmdir()
        return run_pilot(output, os.environ.get("PILOT_SOURCE_SHA"))
    except (ValueError, OSError, subprocess.CalledProcessError) as error:
        print(f"error: {error}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
