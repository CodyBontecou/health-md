#!/usr/bin/env python3
"""Authenticated streaming HTTPS sink for supervised Health.md export tests.

Request bodies are hashed and discarded incrementally. The server never prints or
persists health payload bytes. Startup-selected faults make failure runs repeatable
without exposing a runtime control endpoint.
"""

from __future__ import annotations

import argparse
import hashlib
import http.server
import json
import os
import pathlib
import re
import socket
import ssl
import sys
import threading
import time
from typing import Iterator

RUN_ID = re.compile(r"^[A-Za-z0-9][A-Za-z0-9_.-]{0,63}$")
FAULTS = {
    "success",
    "delay-read",
    "delay-response",
    "status-429",
    "status-500",
    "close-after-bytes",
    "oversized-response",
}


class SinkError(RuntimeError):
    pass


class ReceiptWriter:
    def __init__(self, root: pathlib.Path):
        self.root = root
        if self.root.is_symlink():
            raise SinkError("receipt-directory-symlink")
        self.root.mkdir(parents=True, exist_ok=True, mode=0o700)
        if self.root.is_symlink():
            raise SinkError("receipt-directory-symlink")
        os.chmod(self.root, 0o700)
        self.lock = threading.Lock()

    def append(self, value: dict) -> None:
        encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode() + b"\n"
        path = self.root / "receipts.ndjson"
        with self.lock:
            if path.is_symlink():
                raise SinkError("receipt-file-symlink")
            descriptor = os.open(
                path,
                os.O_WRONLY | os.O_CREAT | os.O_APPEND | getattr(os, "O_NOFOLLOW", 0),
                0o600,
            )
            try:
                os.write(descriptor, encoded)
                os.fsync(descriptor)
            finally:
                os.close(descriptor)
            os.chmod(path, 0o600)


class ExportSinkServer(http.server.ThreadingHTTPServer):
    daemon_threads = True
    allow_reuse_address = True
    request_queue_size = 16

    def __init__(
        self,
        address,
        handler,
        arguments,
        token: str,
        receipts: ReceiptWriter,
        tls_context: ssl.SSLContext | None = None,
    ):
        self.arguments = arguments
        self.token = token
        self.receipts = receipts
        self.tls_context = tls_context
        self.worker_slots = threading.BoundedSemaphore(
            getattr(arguments, "maximum_workers", 4)
        )
        super().__init__(address, handler)

    def get_request(self):
        connection, address = super().get_request()
        connection.settimeout(getattr(self.arguments, "handshake_timeout_seconds", 5))
        if self.tls_context is None:
            connection.settimeout(getattr(self.arguments, "io_timeout_seconds", 30))
            return connection, address
        try:
            secured = self.tls_context.wrap_socket(connection, server_side=True)
        except Exception:
            connection.close()
            raise
        secured.settimeout(getattr(self.arguments, "io_timeout_seconds", 30))
        return secured, address

    def process_request(self, request, client_address) -> None:
        if not self.worker_slots.acquire(blocking=False):
            self.shutdown_request(request)
            return
        try:
            super().process_request(request, client_address)
        except Exception:
            self.worker_slots.release()
            raise

    def process_request_thread(self, request, client_address) -> None:
        try:
            super().process_request_thread(request, client_address)
        finally:
            self.worker_slots.release()

    def handle_error(self, request, client_address) -> None:
        return


class ExportSinkHandler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    server_version = "HealthMdExportLabSink/1"

    @property
    def sink(self) -> ExportSinkServer:
        return self.server  # type: ignore[return-value]

    def log_message(self, format: str, *args) -> None:
        # Paths, headers, and transport details are intentionally not logged.
        return

    def do_GET(self) -> None:
        if self.path != "/health":
            self._json_response(404, {"status": "not_found"})
            return
        self._json_response(
            200,
            {
                "schema": "healthmd.export_lab_sink_status",
                "status": "ready",
                "fault": self.sink.arguments.fault,
            },
        )

    def do_POST(self) -> None:
        started = time.monotonic()
        run_id = self.headers.get("X-HealthMd-Export-Lab-Run", "")
        authorized = self.headers.get("Authorization", "") == f"Bearer {self.sink.token}"
        if self.path != "/export" or not authorized or not RUN_ID.fullmatch(run_id):
            self._drain_rejected_body()
            self._json_response(401 if not authorized else 400, {"status": "rejected"})
            return

        digest = hashlib.sha256()
        byte_count = 0
        outcome = "failure"
        status_code = 0
        try:
            for chunk in self._body_chunks():
                byte_count += len(chunk)
                if byte_count > self.sink.arguments.maximum_request_bytes:
                    raise SinkError("request-too-large")
                digest.update(chunk)
                if self.sink.arguments.fault == "delay-read":
                    time.sleep(self.sink.arguments.delay_read_milliseconds / 1000)
                if (
                    self.sink.arguments.fault == "close-after-bytes"
                    and byte_count >= self.sink.arguments.close_after_bytes
                ):
                    outcome = "injected-close"
                    self.connection.shutdown(socket.SHUT_RDWR)
                    self.connection.close()
                    return

            if self.sink.arguments.fault == "delay-response":
                time.sleep(self.sink.arguments.delay_response_seconds)
            if self.sink.arguments.fault == "status-429":
                status_code = 429
                self.send_response(status_code)
                self.send_header("Retry-After", "1")
                self.send_header("Content-Length", "0")
                self.end_headers()
                outcome = "injected-429"
            elif self.sink.arguments.fault == "status-500":
                status_code = 500
                self._json_response(status_code, {"status": "injected_failure"})
                outcome = "injected-500"
            elif self.sink.arguments.fault == "oversized-response":
                status_code = 202
                response_size = self.sink.arguments.oversized_response_bytes
                self.send_response(status_code)
                self.send_header("Content-Type", "application/octet-stream")
                self.send_header("Content-Length", str(response_size))
                self.end_headers()
                chunk = b"x" * min(128 * 1024, response_size)
                remaining = response_size
                while remaining > 0:
                    count = min(remaining, len(chunk))
                    self.wfile.write(chunk[:count])
                    remaining -= count
                outcome = "injected-oversized-response"
            else:
                status_code = 202
                self._json_response(
                    status_code,
                    {
                        "schema": "healthmd.export_lab_sink_receipt",
                        "status": "accepted",
                        "byte_count": byte_count,
                    },
                )
                outcome = "accepted"
        except (BrokenPipeError, ConnectionResetError):
            outcome = "peer-disconnected"
        except (TimeoutError, socket.timeout, ssl.SSLError):
            self.close_connection = True
            outcome = "transport-timeout"
        except SinkError:
            self.close_connection = True
            status_code = 413
            self._json_response(
                status_code,
                {"status": "request_too_large"},
                close=True,
            )
            outcome = "request-too-large"
        finally:
            self.sink.receipts.append(
                {
                    "schema": "healthmd.export_lab_sink_receipt",
                    "schema_version": 1,
                    "run_id": run_id,
                    "fault": self.sink.arguments.fault,
                    "outcome": outcome,
                    "status_code": status_code,
                    "byte_count": byte_count,
                    "sha256": digest.hexdigest(),
                    "elapsed_milliseconds": int((time.monotonic() - started) * 1000),
                }
            )

    def _body_chunks(self) -> Iterator[bytes]:
        transfer_encoding = self.headers.get("Transfer-Encoding", "").strip().lower()
        raw_length = self.headers.get("Content-Length")
        if transfer_encoding:
            if transfer_encoding != "chunked" or raw_length is not None:
                raise SinkError("invalid-transfer-encoding")
            yield from self._chunked_body()
            return
        if raw_length is None or not raw_length.isdigit():
            raise SinkError("missing-content-length")
        remaining = int(raw_length)
        if remaining > self.sink.arguments.maximum_request_bytes:
            raise SinkError("request-too-large")
        while remaining > 0:
            chunk = self.rfile.read(min(128 * 1024, remaining))
            if not chunk:
                raise SinkError("truncated-body")
            remaining -= len(chunk)
            yield chunk

    def _chunked_body(self) -> Iterator[bytes]:
        while True:
            line = self.rfile.readline(128)
            if not line or len(line) >= 128:
                raise SinkError("invalid-chunk-header")
            size_text = line.split(b";", 1)[0].strip()
            try:
                size = int(size_text, 16)
            except ValueError as error:
                raise SinkError("invalid-chunk-size") from error
            if size == 0:
                trailer_count = 0
                trailer_bytes = 0
                while True:
                    trailer = self.rfile.readline(8192)
                    if trailer in (b"\r\n", b"\n", b""):
                        return
                    trailer_count += 1
                    trailer_bytes += len(trailer)
                    if trailer_count > 32 or trailer_bytes > 16 * 1024:
                        raise SinkError("trailers-too-large")
            remaining = size
            while remaining > 0:
                chunk = self.rfile.read(min(128 * 1024, remaining))
                if not chunk:
                    raise SinkError("truncated-chunk")
                remaining -= len(chunk)
                yield chunk
            if self.rfile.read(2) != b"\r\n":
                raise SinkError("invalid-chunk-ending")

    def _drain_rejected_body(self) -> None:
        try:
            byte_count = 0
            for chunk in self._body_chunks():
                byte_count += len(chunk)
                if byte_count > self.sink.arguments.maximum_request_bytes:
                    raise SinkError("rejected-body-too-large")
        except Exception:
            self.close_connection = True

    def _json_response(self, status: int, value: dict, close: bool = False) -> None:
        encoded = json.dumps(value, sort_keys=True, separators=(",", ":")).encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(encoded)))
        if close:
            self.send_header("Connection", "close")
            self.close_connection = True
        self.end_headers()
        self.wfile.write(encoded)


def read_token(arguments) -> str:
    if arguments.token_file:
        path = pathlib.Path(arguments.token_file).expanduser()
        if path.stat().st_mode & 0o077:
            raise SinkError("token-file-permissions")
        token = path.read_text(encoding="utf-8").strip()
    else:
        token = os.environ.get("HEALTHMD_LAB_API_TOKEN", "").strip()
    if not (16 <= len(token) <= 512) or any(character.isspace() for character in token):
        raise SinkError("invalid-token")
    return token


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind", default="0.0.0.0")
    parser.add_argument("--port", type=int, default=18443)
    parser.add_argument("--certificate", required=True)
    parser.add_argument("--private-key", required=True)
    parser.add_argument("--token-file")
    parser.add_argument("--receipt-directory", required=True)
    parser.add_argument("--fault", choices=sorted(FAULTS), default="success")
    parser.add_argument("--maximum-request-bytes", type=int, default=1024 * 1024 * 1024)
    parser.add_argument("--delay-read-milliseconds", type=int, default=100)
    parser.add_argument("--delay-response-seconds", type=float, default=5)
    parser.add_argument("--close-after-bytes", type=int, default=1024 * 1024)
    parser.add_argument("--oversized-response-bytes", type=int, default=17 * 1024 * 1024)
    parser.add_argument("--maximum-workers", type=int, default=4)
    parser.add_argument("--handshake-timeout-seconds", type=float, default=5)
    parser.add_argument("--io-timeout-seconds", type=float, default=30)
    return parser


def main(argv=None) -> int:
    arguments = build_parser().parse_args(argv)
    try:
        if not (1024 <= arguments.port <= 65535):
            raise SinkError("invalid-port")
        if arguments.fault not in FAULTS:
            raise SinkError("invalid-fault")
        if arguments.maximum_request_bytes < 1:
            raise SinkError("invalid-request-limit")
        if arguments.oversized_response_bytes < 1 \
                or arguments.close_after_bytes < 1 \
                or arguments.delay_read_milliseconds < 0 \
                or arguments.delay_response_seconds < 0:
            raise SinkError("invalid-fault-configuration")
        if not (1 <= arguments.maximum_workers <= 32) \
                or not (0.1 <= arguments.handshake_timeout_seconds <= 60) \
                or not (0.1 <= arguments.io_timeout_seconds <= 300):
            raise SinkError("invalid-server-limits")
        token = read_token(arguments)
        receipts = ReceiptWriter(pathlib.Path(arguments.receipt_directory).expanduser())
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.minimum_version = ssl.TLSVersion.TLSv1_2
        context.load_cert_chain(arguments.certificate, arguments.private_key)
        server = ExportSinkServer(
            (arguments.bind, arguments.port),
            ExportSinkHandler,
            arguments,
            token,
            receipts,
            context,
        )
        print(
            json.dumps(
                {
                    "schema": "healthmd.export_lab_sink_started",
                    "status": "ready",
                    "port": arguments.port,
                    "fault": arguments.fault,
                },
                sort_keys=True,
            ),
            flush=True,
        )
        server.serve_forever(poll_interval=0.5)
        return 0
    except (SinkError, OSError, ssl.SSLError) as error:
        code = str(error)
        safe = "".join(character for character in code if character.isalnum() or character in "-_")[:64]
        print(json.dumps({"schema": "healthmd.export_lab_sink_error", "status": "failure", "error": safe}))
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
