#!/usr/bin/env python3
"""Run a bounded, protocol-complete MCP initialize and tools/list smoke test."""

from __future__ import annotations

import json
import os
import pathlib
import queue
import subprocess
import sys
import threading

PROTOCOL_VERSION = "2025-11-25"
EXPECTED_TOOL_COUNT = 19
RESPONSE_TIMEOUT_SECONDS = 20
EXIT_TIMEOUT_SECONDS = 5


def fail(message: str) -> None:
    raise SystemExit(f"MCP stdio smoke failed: {message}")


def main() -> int:
    if len(sys.argv) != 2:
        fail("usage: smoke-mcp-stdio.py EXECUTABLE")
    executable = pathlib.Path(sys.argv[1]).resolve()
    if not executable.is_file() or not os.access(executable, os.X_OK):
        fail("executable is missing or not executable")

    process = subprocess.Popen(
        [str(executable)],
        stdin=subprocess.PIPE,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        env=os.environ.copy(),
    )
    assert process.stdin is not None
    assert process.stdout is not None
    assert process.stderr is not None
    messages: queue.Queue[object] = queue.Queue()

    def collect_responses() -> None:
        try:
            while line := process.stdout.readline():
                value = json.loads(line)
                if "id" in value:
                    messages.put(value)
            messages.put(RuntimeError("server exited before the expected response"))
        except BaseException as error:
            messages.put(error)

    def send(value: dict[str, object]) -> None:
        process.stdin.write(json.dumps(value, separators=(",", ":")) + "\n")
        process.stdin.flush()

    def receive(expected_id: int) -> dict[str, object]:
        try:
            value = messages.get(timeout=RESPONSE_TIMEOUT_SECONDS)
        except queue.Empty as error:
            process.kill()
            raise subprocess.TimeoutExpired(
                [str(executable)], RESPONSE_TIMEOUT_SECONDS
            ) from error
        if isinstance(value, BaseException):
            process.kill()
            raise value
        if not isinstance(value, dict) or value.get("id") != expected_id:
            process.kill()
            fail(f"unexpected response identifier: {value!r}")
        return value

    reader = threading.Thread(target=collect_responses, daemon=True)
    reader.start()
    return_code = None
    try:
        send(
            {
                "jsonrpc": "2.0",
                "id": 1,
                "method": "initialize",
                "params": {
                    "protocolVersion": PROTOCOL_VERSION,
                    "capabilities": {},
                    "clientInfo": {
                        "name": "healthmd-homebrew-qualification",
                        "version": "1",
                    },
                },
            }
        )
        initialized = receive(1)
        result = initialized.get("result")
        if not isinstance(result, dict):
            fail(f"initialize returned no result: {initialized!r}")
        if result.get("protocolVersion") != PROTOCOL_VERSION:
            fail(f"unexpected protocol version: {result!r}")
        server_info = result.get("serverInfo")
        if not isinstance(server_info, dict) or server_info.get("name") != "healthmd-mcp":
            fail(f"unexpected server identity: {result!r}")

        send(
            {
                "jsonrpc": "2.0",
                "method": "notifications/initialized",
                "params": {},
            }
        )
        send({"jsonrpc": "2.0", "id": 2, "method": "tools/list", "params": {}})
        listed = receive(2)
        listed_result = listed.get("result")
        if not isinstance(listed_result, dict):
            fail(f"tools/list returned no result: {listed!r}")
        tools = listed_result.get("tools")
        if not isinstance(tools, list) or len(tools) != EXPECTED_TOOL_COUNT:
            fail(f"unexpected tool catalog size: {tools!r}")
        if not any(
            isinstance(tool, dict) and tool.get("name") == "healthmd_sleep_sessions"
            for tool in tools
        ):
            fail("healthmd_sleep_sessions is missing from the installed tool catalog")
    finally:
        if not process.stdin.closed:
            try:
                process.stdin.close()
            except BrokenPipeError:
                pass
        try:
            return_code = process.wait(timeout=EXIT_TIMEOUT_SECONDS)
        except subprocess.TimeoutExpired:
            process.kill()
            return_code = process.wait(timeout=EXIT_TIMEOUT_SECONDS)
        reader.join(timeout=EXIT_TIMEOUT_SECONDS)

    stderr = process.stderr.read()
    if reader.is_alive():
        fail("response reader did not stop")
    if return_code != 0:
        fail(f"server exited with {return_code}: {stderr.strip()}")
    if stderr:
        fail(f"server wrote unexpected stderr: {stderr.strip()}")
    print(f"MCP stdio smoke passed: protocol={PROTOCOL_VERSION} tools={EXPECTED_TOOL_COUNT}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
