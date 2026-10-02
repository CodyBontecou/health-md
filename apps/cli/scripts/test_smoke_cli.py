#!/usr/bin/env python3
"""Health-free regression tests for the shared CLI/CI smoke harness."""

import copy
import importlib.util
import json
import os
from pathlib import Path
import sys
import unittest
from unittest import mock

SPEC = importlib.util.spec_from_file_location("smoke_cli", Path(__file__).with_name("smoke-cli.py"))
smoke = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(smoke)


class CatalogTests(unittest.TestCase):
    def setUp(self):
        self.catalog = json.loads(smoke.CATALOG.read_text())

    def test_previous_catalog_without_full_corpus_tools_fails(self):
        stale = [tool for tool in self.catalog if tool["name"] not in {
            "healthmd_export_raw", "healthmd_raw_artifact_read",
        }]
        with self.assertRaisesRegex(smoke.SmokeError, "tool names"):
            smoke.check_tools(stale, self.catalog)

    def test_complete_catalog_matches_even_with_negotiated_ui_metadata(self):
        served = copy.deepcopy(self.catalog)
        for tool in served:
            tool.setdefault("_meta", {})["ui"] = {"resourceUri": smoke.UI_URI}
        smoke.check_tools(served, self.catalog)

    def test_duplicate_names_fail_even_if_total_count_matches(self):
        served = copy.deepcopy(self.catalog)
        served[-1] = served[0]
        with self.assertRaisesRegex(smoke.SmokeError, "duplicate"):
            smoke.check_tools(served, self.catalog)

    def test_schema_drift_fails(self):
        served = copy.deepcopy(self.catalog)
        served[0]["inputSchema"] = {}
        with self.assertRaisesRegex(smoke.SmokeError, "inputSchema"):
            smoke.check_tools(served, self.catalog)

    def test_approval_drift_fails(self):
        served = copy.deepcopy(self.catalog)
        tool = next(tool for tool in served if tool["name"] == "healthmd_export_raw")
        tool["_meta"].clear()
        with self.assertRaisesRegex(smoke.SmokeError, "approval"):
            smoke.check_tools(served, self.catalog)

    def test_read_only_omits_local_job_and_pairing_reads(self):
        names = smoke.tool_index(smoke.read_only_catalog(self.catalog))
        for name in ("healthmd_pairing_status", "healthmd_export_job_status", "healthmd_raw_artifact_read"):
            self.assertNotIn(name, names)
        self.assertIn("healthmd_sleep_sessions", names)
        self.assertTrue(all(tool["annotations"]["readOnlyHint"] for tool in names.values()))
        hidden = sorted(smoke.tool_index(self.catalog).keys() - names.keys())
        messages = smoke.requests(hidden)
        self.assertEqual([message["params"]["name"] for message in messages[5:]], hidden)

    def test_no_read_only_request_starts_an_export(self):
        messages = smoke.requests()
        self.assertEqual({message["params"]["name"] for message in messages if message["method"] == "tools/call"},
                         {"healthmd_capabilities", "healthmd_doctor"})


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.catalog = json.loads(smoke.CATALOG.read_text())

    def responses(self, read_only=False):
        tools = smoke.read_only_catalog(self.catalog) if read_only else self.catalog
        doctor = {"schema": "healthmd.direct_readiness", "schema_version": 1,
                  "status": "not_paired", "ready": False, "message": "Fixture is unpaired."}
        if not read_only:
            doctor["next_tool"] = "healthmd_pairing_start"
        result = {
            1: {"result": {"capabilities": {"extensions": {"io.modelcontextprotocol/ui": {"mimeTypes": [smoke.MIME]}}}}},
            2: {"result": {"tools": tools}},
            3: {"result": {"resources": [{"uri": smoke.UI_URI}]}},
            4: {"result": {"content": [{"type": "text", "text": json.dumps({"query_tool_guidance": {"sleep": "healthmd_sleep_sessions"}})}]}},
            5: {"result": {"isError": False, "content": [{"type": "text", "text": json.dumps(doctor)}]}},
        }
        if read_only:
            hidden = smoke.tool_index(self.catalog).keys() - smoke.tool_index(tools).keys()
            for _ in hidden:
                result[len(result) + 1] = {"error": {"code": -32602, "message": "Unknown tool"}}
        return result

    def test_both_profiles_validate_health_free_session_envelopes(self):
        for read_only in (False, True):
            smoke.check_session(self.responses(read_only), self.catalog, read_only=read_only)

    def test_read_only_must_reject_every_hidden_operation(self):
        responses = self.responses(True)
        responses[6] = {"result": {}}
        with self.assertRaisesRegex(smoke.SmokeError, "accepted a local-only"):
            smoke.check_session(responses, self.catalog, read_only=True)

    def test_read_only_must_not_publish_pairing_resources(self):
        responses = self.responses(True)
        responses[3]["result"]["resources"].append({"uri": "ui://healthmd/fixture-pairing"})
        with self.assertRaisesRegex(smoke.SmokeError, "local-only resource"):
            smoke.check_session(responses, self.catalog, read_only=True)

    def test_doctor_rejects_unexpected_payload_fields(self):
        responses = self.responses()
        content = responses[5]["result"]["content"][0]
        doctor = json.loads(content["text"])
        doctor["unexpected_payload"] = {}
        content["text"] = json.dumps(doctor)
        with self.assertRaisesRegex(smoke.SmokeError, "unexpected doctor readiness fields"):
            smoke.check_session(responses, self.catalog)


class NativeCredentialsTests(unittest.TestCase):
    def test_empty_devices_passes_on_every_runner(self):
        for runner in ("Linux", "macOS", "Windows"):
            smoke.check_devices(runner, 0, {"schema": "healthmd.direct_devices", "devices": []})

    def test_only_linux_may_lack_native_credentials(self):
        error = {"error": "direct_storage_unavailable"}
        smoke.check_devices("Linux", 1, error)
        for runner in ("macOS", "Windows"):
            with self.assertRaises(smoke.SmokeError):
                smoke.check_devices(runner, 1, error)

    def test_runner_override_cannot_bypass_native_host_requirement(self):
        with mock.patch.object(smoke.sys, "platform", "darwin"), mock.patch.object(
            smoke.sys, "argv", ["smoke-cli.py", "--skip-build", "--runner", "Linux"]
        ):
            with self.assertRaisesRegex(smoke.SmokeError, "must match"):
                smoke.main()

    def test_existing_pairing_in_smoke_state_fails(self):
        with self.assertRaisesRegex(smoke.SmokeError, "paired devices"):
            smoke.check_devices("Linux", 0, {"schema": "healthmd.direct_devices", "devices": [{}]})


class ProcessTests(unittest.TestCase):
    def test_out_of_order_responses_keep_stdin_open(self):
        source = """import json, sys
messages = [json.loads(sys.stdin.readline()) for _ in range(2)]
for message in reversed(messages):
    print(json.dumps({'jsonrpc': '2.0', 'id': message['id'], 'result': {}}), flush=True)
sys.stdin.read()
"""
        messages = [{"jsonrpc": "2.0", "id": identifier, "method": "ping", "params": {}} for identifier in (1, 2)]
        responses = smoke.run_stdio_server([sys.executable, "-u", "-c", source], messages, os.environ.copy())
        self.assertEqual(set(responses), {1, 2})

    def test_initialize_is_completed_before_other_requests(self):
        source = """import json, sys
initialize = json.loads(sys.stdin.readline())
assert initialize['method'] == 'initialize'
print(json.dumps({'jsonrpc': '2.0', 'id': initialize['id'], 'result': {}}), flush=True)
notification = json.loads(sys.stdin.readline())
assert notification == {'jsonrpc': '2.0', 'method': 'notifications/initialized'}
request = json.loads(sys.stdin.readline())
assert request['method'] == 'tools/list'
print(json.dumps({'jsonrpc': '2.0', 'id': request['id'], 'result': {}}), flush=True)
sys.stdin.read()
"""
        responses = smoke.run_stdio_server([sys.executable, "-u", "-c", source], smoke.requests()[:2], os.environ.copy())
        self.assertEqual(set(responses), {1, 2})

    def test_timeout_kills_a_blocked_server(self):
        with self.assertRaisesRegex(smoke.SmokeError, "timeout"):
            smoke.run_stdio_server([sys.executable, "-u", "-c", "import time; time.sleep(60)"],
                                   smoke.requests()[:1], os.environ.copy(), timeout=0.05)

    def test_missing_response_fails(self):
        with self.assertRaises(smoke.SmokeError):
            smoke.run_stdio_server([sys.executable, "-u", "-c", "import sys; sys.stdin.readline()"],
                                   smoke.requests()[:1], os.environ.copy())

    def test_duplicate_response_fails(self):
        source = """import sys
sys.stdin.readline()
print('{"jsonrpc":"2.0","id":1,"result":{}}', flush=True)
print('{"jsonrpc":"2.0","id":1,"result":{}}', flush=True)
sys.stdin.read()
"""
        with self.assertRaises(smoke.SmokeError):
            smoke.run_stdio_server([sys.executable, "-u", "-c", source], smoke.requests()[:2], os.environ.copy())


if __name__ == "__main__":
    unittest.main()
