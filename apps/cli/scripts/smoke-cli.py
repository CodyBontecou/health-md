#!/usr/bin/env python3
"""Run hermetic CLI/MCP discovery smoke.

Requires Python 3.11+. Uses temporary file/Codex state and only credential-free
operations; never pairs, opens native credentials, or contacts a device. Native
credential upgrade checks belong to the automated signed-release probes.
"""

from __future__ import annotations

import argparse
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import threading
import time

ROOT = Path(__file__).resolve().parents[1]
CATALOG = ROOT / "crates/healthmd-mcp/assets/mcp-tools-v1.json"
UI_URI = "ui://healthmd/query-visualization-v1"
MIME = "text/html;profile=mcp-app"
MAX_LINE_BYTES = 2 * 1024 * 1024


class SmokeError(RuntimeError):
    """A health-free smoke assertion failed."""


def require(condition: bool, message: str) -> None:
    if not condition:
        raise SmokeError(message)


def tool_index(tools: list[dict]) -> dict[str, dict]:
    names = [tool["name"] for tool in tools]
    require(len(names) == len(set(names)), "duplicate MCP tool declarations")
    return dict(zip(names, tools))


def read_only_catalog(tools: list[dict]) -> list[dict]:
    # Pairing/job/artifact status reads are local-only despite readOnlyHint.
    # These namespace exclusions are intentional least-privilege assertions;
    # the complete declarations/count come from the generated Rust registry.
    return [
        tool for tool in tools
        if tool["annotations"]["readOnlyHint"]
        and not tool["name"].startswith(("healthmd_pairing_", "healthmd_export_"))
        and tool["name"] != "healthmd_raw_artifact_read"
    ]


def check_tools(actual: list[dict], expected: list[dict]) -> None:
    served, canonical = tool_index(actual), tool_index(expected)
    require(served.keys() == canonical.keys(), "served MCP tool names differ from the catalog")
    for name, tool in canonical.items():
        for field in ("inputSchema", "annotations"):
            require(served[name][field] == tool[field], f"MCP {field} drift: {name}")
        for key, value in tool.get("_meta", {}).items():
            require(served[name].get("_meta", {}).get(key) == value, f"MCP approval metadata drift: {name}")


def requests(hidden: list[str] | None = None) -> list[dict]:
    result = [
        {"jsonrpc": "2.0", "id": 1, "method": "initialize", "params": {
            "protocolVersion": "2025-11-25", "capabilities": {"extensions": {
                "io.modelcontextprotocol/ui": {"mimeTypes": [MIME]},
            }},
        }},
        {"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}},
        {"jsonrpc": "2.0", "id": 3, "method": "resources/list", "params": {}},
        {"jsonrpc": "2.0", "id": 4, "method": "tools/call", "params": {"name": "healthmd_capabilities", "arguments": {}}},
    ]
    for name in hidden or []:
        result.append({"jsonrpc": "2.0", "id": len(result) + 1, "method": "tools/call", "params": {"name": name, "arguments": {}}})
    return result


def run_stdio_server(command: list[str], messages: list[dict], env: dict, timeout: float = 30) -> dict:
    """Keep stdin open until responses arrive; bound waiting and clean up on failure."""
    process = subprocess.Popen(command, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, env=env)
    responses, failures = {}, []
    expected_ids = {message["id"] for message in messages}
    stderr = bytearray()
    initialized = threading.Event()
    deadline = time.monotonic() + timeout
    initialize_id = messages[0]["id"] if messages and messages[0]["method"] == "initialize" else None

    def collect() -> None:
        try:
            notifications = 0
            while responses.keys() != expected_ids:
                line = process.stdout.readline(MAX_LINE_BYTES + 1)
                require(bool(line), "MCP server exited before every response")
                require(len(line) <= MAX_LINE_BYTES, "oversized MCP smoke response")
                value = json.loads(line)
                if "id" in value:
                    identifier = value["id"]
                    require(identifier in expected_ids and identifier not in responses, "unexpected/duplicate MCP response ID")
                    responses[identifier] = value
                    if identifier == initialize_id:
                        initialized.set()
                else:
                    notifications += 1
                    require(notifications <= 100, "excessive MCP smoke notifications")
        except Exception as error:
            failures.append(error)
            initialized.set()

    def drain_stderr() -> None:
        while chunk := process.stderr.read(4096):
            # Drain continuously to avoid deadlock; never retain arbitrary logs.
            stderr.extend(chunk[:max(0, 4096 - len(stderr))])

    reader = threading.Thread(target=collect, daemon=True)
    logger = threading.Thread(target=drain_stderr, daemon=True)
    reader.start()
    logger.start()
    try:
        def send(message: dict) -> None:
            process.stdin.write((json.dumps(message) + "\n").encode())
            process.stdin.flush()

        remaining = messages
        if initialize_id is not None:
            send(messages[0])
            require(initialized.wait(timeout=timeout), "MCP initialize timeout")
            require(not failures, "invalid/incomplete MCP initialize response")
            send({"jsonrpc": "2.0", "method": "notifications/initialized"})
            remaining = messages[1:]
        for message in remaining:
            send(message)
        reader.join(timeout=max(0, deadline - time.monotonic()))
        require(not reader.is_alive(), "MCP smoke response timeout")
        require(not failures, "invalid/incomplete MCP smoke responses")
        process.stdin.close()
        process.wait(timeout=5)
        logger.join(timeout=5)
        require(process.returncode == 0, "MCP smoke process failed")
        require(not stderr, "MCP smoke emitted unexpected stderr")
        return responses
    finally:
        if process.poll() is None:
            process.kill()
        process.wait(timeout=5)
        reader.join(timeout=5)
        logger.join(timeout=5)
        for stream in (process.stdin, process.stdout, process.stderr):
            if not stream.closed:
                stream.close()


def check_session(responses: dict, catalog: list[dict], *, read_only: bool = False) -> None:
    require(responses[1]["result"]["capabilities"]["extensions"]["io.modelcontextprotocol/ui"]["mimeTypes"] == [MIME], "missing MCP Apps negotiation")
    expected = read_only_catalog(catalog) if read_only else catalog
    check_tools(responses[2]["result"]["tools"], expected)
    served = tool_index(responses[2]["result"]["tools"])
    # Catalog equality alone cannot detect a capability removed from both the
    # runtime and generated declarations. Keep the integration's required tools.
    required = {"healthmd_metric_chart", "healthmd_sleep_sessions"}
    if not read_only:
        required.update({"healthmd_pairing_start", "healthmd_pairing_status",
                         "healthmd_export_raw", "healthmd_raw_artifact_read"})
    require(required <= served.keys(), f"missing required MCP tools: {sorted(required - served.keys())}")
    sleep = served["healthmd_sleep_sessions"]
    require(len(sleep["inputSchema"]["properties"]["dates"]["oneOf"]) == 2, "missing explicit/all-available date alternatives")
    require(sleep["inputSchema"]["examples"][0]["all_pages"] is True, "missing complete traversal example")
    uris = {resource["uri"] for resource in responses[3]["result"]["resources"]}
    require(UI_URI in uris, "missing visualization resource")
    require(not read_only or uris == {UI_URI}, "read-only MCP exposes a local-only resource")
    capability_text = responses[4]["result"]["content"][0]["text"]
    capabilities = json.loads(capability_text)
    require("requires_mac_app" not in capabilities, "obsolete Mac-app capability field")
    require(capabilities["query_tool_guidance"]["sleep"] == "healthmd_sleep_sessions", "missing typed sleep guidance")
    expected_count = 4 + (len(tool_index(catalog).keys() - served.keys()) if read_only else 0)
    require(set(responses) == set(range(1, expected_count + 1)), "unexpected MCP smoke response inventory")
    if read_only:
        for identifier in range(5, len(responses) + 1):
            require(responses[identifier].get("error") == {"code": -32602, "message": "Unknown tool"}, "read-only MCP accepted a local-only operation")


def run(command: list[str], env: dict, *, success: bool = True) -> subprocess.CompletedProcess:
    result = subprocess.run(command, cwd=ROOT, env=env, stdin=subprocess.DEVNULL, capture_output=True, timeout=30)
    require((result.returncode == 0) == success, "unexpected command outcome: " + " ".join(command[1:]))
    return result


def smoke(binary: Path, compatibility: Path) -> tuple[int, int]:
    import tomllib  # Python 3.11+, also used by release/CI scripts.

    with tempfile.TemporaryDirectory(prefix="healthmd-cli-smoke-") as temporary:
        root = Path(temporary)
        env = {**os.environ, "HEALTHMD_CLI_DATA_DIR": str(root / "state"), "CODEX_HOME": str(root / "codex"),
               "HEALTHMD_NO_WAKE": "1", "HEALTHMD_WAKE_TIMEOUT": "0", "NO_COLOR": "1", "TERM": "dumb"}
        executable, launcher = str(binary), str(compatibility)
        for arguments in (["--version"], ["--help"], ["query", "--help"], ["mcp", "serve", "--help"],
                          ["mcp", "serve-read-only", "--help"], ["setup", "codex", "--help"]):
            run([executable, *arguments], env)
        run([launcher, "--help"], env)
        for command in ("serve-http", "serve-hosted"):
            run([executable, "mcp", command, "--help"], env, success=False)
        catalog = json.loads(run([executable, "mcp", "schema"], env).stdout)
        require(catalog["schema"] == "healthmd.mcp_tool_catalog" and catalog["schema_version"] == 1, "unexpected MCP catalog schema")
        expected = json.loads(CATALOG.read_text())
        require(catalog["tools"] == expected, "binary MCP catalog differs from the generated registry asset")
        schema = json.loads(run([executable, "mcp", "schema", "healthmd_sleep_sessions"], env).stdout)
        require(schema["schema"] == "healthmd.mcp_tool_schema", "unexpected typed schema envelope")
        require(schema["tool"] == tool_index(expected)["healthmd_sleep_sessions"], "typed schema differs from the catalog")
        setup = json.loads(run([executable, "setup", "codex", "--skip-pairing"], env).stdout)
        require(setup["schema"] == "healthmd.codex_setup" and setup["configuration"]["same_executable_identity"] is True, "unexpected Codex setup receipt")
        config_path = root / "codex/config.toml"
        original = config_path.read_bytes()
        config = tomllib.loads(original.decode())["mcp_servers"]["healthmd"]
        require(config["args"] == ["mcp", "serve"], "Codex must use the complete same-binary server")
        require(config["tools"]["healthmd_export_files"]["approval_mode"] == "prompt", "missing export approval")
        run([executable, "setup", "codex", "--skip-pairing"], env)
        require(config_path.read_bytes() == original, "Codex setup is not idempotent")
        messages = requests()
        responses = run_stdio_server([executable, "mcp", "serve"], messages, env)
        check_session(responses, expected)
        compatibility_responses = run_stdio_server([launcher], messages, env)
        require(compatibility_responses == responses, "compatibility launcher differs from same-binary MCP")
        read_only = read_only_catalog(expected)
        hidden = sorted(tool_index(expected).keys() - tool_index(read_only).keys())
        responses = run_stdio_server([executable, "mcp", "serve-read-only"], requests(hidden), env)
        check_session(responses, expected, read_only=True)
        return len(expected), len(read_only)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--skip-build", action="store_true", help="test already-built default-feature binaries")
    parser.add_argument("--binary", type=Path, help="default-feature healthmd executable")
    parser.add_argument("--compatibility", type=Path, help="matching healthmd-mcp executable")
    native_runner = {"darwin": "macOS", "win32": "Windows", "linux": "Linux"}.get(sys.platform)
    parser.add_argument("--runner", choices=("Linux", "macOS", "Windows"), default=native_runner)
    arguments = parser.parse_args()
    require(native_runner is not None, "unsupported host platform for native CLI smoke")
    require(arguments.runner == native_runner, "--runner must match the host platform")
    if sys.version_info < (3, 11):
        parser.error("Python 3.11+ is required (for example, python3.14 scripts/smoke-cli.py)")
    require(arguments.skip_build or (arguments.binary is None and arguments.compatibility is None), "custom binaries require --skip-build")
    if not arguments.skip_build:
        subprocess.run(["cargo", "build", "--locked", "--bin", "healthmd", "--bin", "healthmd-mcp"], cwd=ROOT, check=True)
    target = Path(os.environ.get("CARGO_TARGET_DIR", ROOT / "target"))
    if not target.is_absolute():
        target = ROOT / target
    suffix = ".exe" if arguments.runner == "Windows" else ""
    binary = (arguments.binary or target / "debug" / f"healthmd{suffix}").resolve()
    compatibility = (arguments.compatibility or binary.with_name(f"healthmd-mcp{suffix}")).resolve()
    complete, read_only = smoke(binary, compatibility)
    if not arguments.skip_build:
        # These optional builds occur only after default-binary/catalog validation.
        for feature in ("streamable-http", "oauth-resource-server"):
            subprocess.run(["cargo", "run", "--quiet", "--locked", "--bin", "healthmd", "--features", feature, "--", "mcp", "serve-http", "--help"], cwd=ROOT, check=True, stdout=subprocess.DEVNULL)
        subprocess.run(["cargo", "build", "--quiet", "--locked", "--bin", "healthmd", "--all-features"], cwd=ROOT, check=True)
        result = subprocess.run([str(binary), "mcp", "serve-hosted", "--help"], cwd=ROOT, capture_output=True, timeout=30)
        require(result.returncode != 0, "optional build exposes removed serve-hosted")
    print(f"Hermetic CLI/MCP smoke passed ({arguments.runner}): {complete} complete, {read_only} read-only tools; no credentials or device contact")
    return 0


if __name__ == "__main__":
    try:
        raise SystemExit(main())
    except (SmokeError, KeyError, TypeError, ValueError, OSError, subprocess.SubprocessError) as error:
        print(f"CLI/MCP smoke failed: {error}", file=sys.stderr)
        raise SystemExit(1)
