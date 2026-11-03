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
        self.assertEqual([message["params"]["name"] for message in messages[4:]], hidden)

    def test_no_read_only_request_starts_an_export(self):
        messages = smoke.requests()
        self.assertEqual({message["params"]["name"] for message in messages if message["method"] == "tools/call"},
                         {"healthmd_capabilities"})

    def test_hermetic_requests_never_dispatch_credential_or_device_operations(self):
        for hidden in (None, ['healthmd_pairing_start', 'healthmd_export_raw']):
            messages = smoke.requests(hidden)
            # Hidden operations are sent only to the read-only profile, where
            # they must be rejected before dispatch. The only admitted call is
            # the static capabilities catalog, not readiness or paired devices.
            self.assertEqual(messages[3]['params']['name'], 'healthmd_capabilities')
            self.assertNotIn('healthmd_doctor', [m.get('params', {}).get('name') for m in messages])


class SessionTests(unittest.TestCase):
    def setUp(self):
        self.catalog = json.loads(smoke.CATALOG.read_text())

    def responses(self, read_only=False):
        tools = smoke.read_only_catalog(self.catalog) if read_only else self.catalog
        result = {
            1: {"result": {"capabilities": {"extensions": {"io.modelcontextprotocol/ui": {"mimeTypes": [smoke.MIME]}}}}},
            2: {"result": {"tools": tools}},
            3: {"result": {"resources": [{"uri": smoke.UI_URI}]}},
            4: {"result": {"content": [{"type": "text", "text": json.dumps({"query_tool_guidance": {"sleep": "healthmd_sleep_sessions"}})}]}},
        }
        if read_only:
            hidden = smoke.tool_index(self.catalog).keys() - smoke.tool_index(tools).keys()
            for _ in hidden:
                result[len(result) + 1] = {"error": {"code": -32602, "message": "Unknown tool"}}
        return result

    def test_both_profiles_validate_health_free_session_envelopes(self):
        for read_only in (False, True):
            smoke.check_session(self.responses(read_only), self.catalog, read_only=read_only)

    def test_complete_session_requires_main_capabilities_even_if_catalog_also_loses_them(self):
        for name in ("healthmd_metric_chart", "healthmd_pairing_start", "healthmd_pairing_status",
                     "healthmd_export_raw", "healthmd_raw_artifact_read"):
            with self.subTest(name=name):
                catalog = [tool for tool in self.catalog if tool["name"] != name]
                responses = self.responses()
                responses[2]["result"]["tools"] = catalog
                with self.assertRaisesRegex(smoke.SmokeError, "missing required MCP tools"):
                    smoke.check_session(responses, catalog)

    def test_read_only_requires_chart_even_if_catalog_also_loses_it(self):
        catalog = [tool for tool in self.catalog if tool["name"] != "healthmd_metric_chart"]
        responses = self.responses(True)
        responses[2]["result"]["tools"] = smoke.read_only_catalog(catalog)
        with self.assertRaisesRegex(smoke.SmokeError, "missing required MCP tools"):
            smoke.check_session(responses, catalog, read_only=True)

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

class HarnessArgumentsTests(unittest.TestCase):
    def test_runner_override_must_match_the_host(self):
        with mock.patch.object(smoke.sys, "platform", "darwin"), mock.patch.object(
            smoke.sys, "argv", ["smoke-cli.py", "--skip-build", "--runner", "Linux"]
        ):
            with self.assertRaisesRegex(smoke.SmokeError, "must match"):
                smoke.main()

    def test_success_reports_only_hermetic_coverage(self):
        arguments = ['smoke-cli.py', '--skip-build', '--binary', '/fixture/healthmd']
        with mock.patch.object(smoke.sys, 'argv', arguments), \
             mock.patch.object(smoke, 'smoke', return_value=(20, 10)), \
             mock.patch('builtins.print') as output:
            self.assertEqual(smoke.main(), 0)
            self.assertIn('Hermetic CLI/MCP smoke passed', output.call_args.args[0])
            self.assertIn('no credentials or device contact', output.call_args.args[0])


class SmokeBoundaryTests(unittest.TestCase):
    def setUp(self):
        self.session = SessionTests()
        self.session.setUp()

    def local_command(self, command, env, *, success=True):
        arguments = command[1:]
        payload = {}
        if arguments == ['mcp', 'schema']:
            payload = {'schema': 'healthmd.mcp_tool_catalog', 'schema_version': 1,
                       'tools': self.session.catalog}
        elif arguments == ['mcp', 'schema', 'healthmd_sleep_sessions']:
            payload = {'schema': 'healthmd.mcp_tool_schema',
                       'tool': smoke.tool_index(self.session.catalog)['healthmd_sleep_sessions']}
        elif arguments == ['setup', 'codex', '--skip-pairing']:
            path = Path(env['CODEX_HOME']) / 'config.toml'
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text('[mcp_servers.healthmd]\nargs = ["mcp", "serve"]\n'
                            '[mcp_servers.healthmd.tools.healthmd_export_files]\napproval_mode = "prompt"\n')
            payload = {'schema': 'healthmd.codex_setup', 'configuration': {'same_executable_identity': True}}
        else:
            self.assertTrue('--help' in arguments or arguments == ['--version'], arguments)
        return smoke.subprocess.CompletedProcess(command, 0 if success else 1, json.dumps(payload), '')

    def test_default_smoke_never_probes_the_native_store(self):
        def stdio(command, messages, env):
            read_only = 'serve-read-only' in command
            hidden = sorted(smoke.tool_index(self.session.catalog).keys()
                            - smoke.tool_index(smoke.read_only_catalog(self.session.catalog)).keys()) if read_only else None
            self.assertEqual(messages, smoke.requests(hidden))
            return self.session.responses(read_only)

        with mock.patch.object(smoke, 'run', side_effect=self.local_command), \
             mock.patch.object(smoke, 'run_stdio_server', side_effect=stdio) as stdio_call, \
             mock.patch.object(smoke.subprocess, 'run', side_effect=AssertionError('native store probe in hermetic smoke')) as native:
            complete, read_only = smoke.smoke(Path('/fixture/healthmd'), Path('/fixture/healthmd-mcp'))
            self.assertEqual(complete, len(self.session.catalog))
            self.assertEqual(read_only, len(smoke.read_only_catalog(self.session.catalog)))
            self.assertEqual(stdio_call.call_count, 3)
            native.assert_not_called()


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
