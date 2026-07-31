import hashlib
import http.client
import importlib.util
import json
import pathlib
import sys
import tempfile
import threading
import time
import types
import unittest

SCRIPT = pathlib.Path(__file__).parents[1] / "export-performance-api-sink.py"
SPEC = importlib.util.spec_from_file_location("export_performance_api_sink", SCRIPT)
assert SPEC and SPEC.loader
sink = importlib.util.module_from_spec(SPEC)
sys.modules[SPEC.name] = sink
SPEC.loader.exec_module(sink)


class ExportPerformanceAPISinkTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory()
        self.receipt_root = pathlib.Path(self.temporary.name) / "receipts"
        self.arguments = types.SimpleNamespace(
            fault="success",
            maximum_request_bytes=1024 * 1024,
            delay_read_milliseconds=1,
            delay_response_seconds=0.01,
            close_after_bytes=8,
            oversized_response_bytes=256,
        )
        self.server = sink.ExportSinkServer(
            ("127.0.0.1", 0),
            sink.ExportSinkHandler,
            self.arguments,
            "0123456789abcdef-test-token",
            sink.ReceiptWriter(self.receipt_root),
        )
        self.thread = threading.Thread(target=self.server.serve_forever, daemon=True)
        self.thread.start()

    def tearDown(self):
        self.server.shutdown()
        self.server.server_close()
        self.thread.join(timeout=2)
        self.temporary.cleanup()

    def test_streams_hashes_and_discards_content_length_body(self):
        body = b'{"private_health_value":123}'
        response = self._post(body)
        self.assertEqual(response.status, 202)
        response.read()

        receipt = self._receipts(minimum=1)[0]
        self.assertEqual(receipt["outcome"], "accepted")
        self.assertEqual(receipt["byte_count"], len(body))
        self.assertEqual(receipt["sha256"], hashlib.sha256(body).hexdigest())
        raw_receipt = (self.receipt_root / "receipts.ndjson").read_text()
        self.assertNotIn("private_health_value", raw_receipt)
        self.assertEqual((self.receipt_root / "receipts.ndjson").stat().st_mode & 0o777, 0o600)

    def test_accepts_chunked_upload_stream(self):
        connection = self._connection()
        connection.request(
            "POST",
            "/export",
            body=[b"first", b"second"],
            headers=self._headers(include_length=False),
            encode_chunked=True,
        )
        response = connection.getresponse()
        self.assertEqual(response.status, 202)
        response.read()
        connection.close()
        receipt = self._receipts(minimum=1)[0]
        self.assertEqual(receipt["byte_count"], 11)

    def test_fault_status_and_oversized_response_are_startup_selected(self):
        self.arguments.fault = "status-429"
        response = self._post(b"payload")
        self.assertEqual(response.status, 429)
        response.read()
        self.assertEqual(self._receipts(minimum=1)[-1]["outcome"], "injected-429")

        self.arguments.fault = "oversized-response"
        response = self._post(b"payload-two")
        self.assertEqual(response.status, 202)
        self.assertEqual(len(response.read()), 256)
        self.assertEqual(
            self._receipts(minimum=2)[-1]["outcome"],
            "injected-oversized-response",
        )

    def test_rejects_missing_authentication_and_run_correlation(self):
        connection = self._connection()
        connection.request("POST", "/export", body=b"payload", headers={"Content-Length": "7"})
        response = connection.getresponse()
        self.assertEqual(response.status, 401)
        response.read()
        connection.close()
        self.assertEqual(self._receipts(), [])

        connection = self._connection()
        headers = self._headers()
        headers["X-HealthMd-Export-Lab-Run"] = "../../private"
        connection.request("POST", "/export", body=b"payload", headers=headers)
        response = connection.getresponse()
        self.assertEqual(response.status, 400)
        response.read()
        connection.close()
        self.assertEqual(self._receipts(), [])

    def _connection(self):
        return http.client.HTTPConnection("127.0.0.1", self.server.server_port, timeout=3)

    def _headers(self, include_length=True):
        headers = {
            "Authorization": "Bearer 0123456789abcdef-test-token",
            "X-HealthMd-Export-Lab-Run": "api-run-123",
            "Content-Type": "application/json",
        }
        if include_length:
            headers["Content-Length"] = "0"
        return headers

    def _post(self, body):
        connection = self._connection()
        headers = self._headers()
        headers["Content-Length"] = str(len(body))
        connection.request("POST", "/export", body=body, headers=headers)
        response = connection.getresponse()
        original_read = response.read

        def read_and_close(*args, **kwargs):
            try:
                return original_read(*args, **kwargs)
            finally:
                connection.close()

        response.read = read_and_close
        return response

    def _receipts(self, minimum=0):
        path = self.receipt_root / "receipts.ndjson"
        deadline = time.monotonic() + 1
        while True:
            values = []
            if path.exists():
                values = [json.loads(line) for line in path.read_text().splitlines() if line]
            if len(values) >= minimum or time.monotonic() >= deadline:
                return values
            time.sleep(0.01)


if __name__ == "__main__":
    unittest.main()
