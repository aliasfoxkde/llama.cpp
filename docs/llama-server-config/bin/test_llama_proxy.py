#!/usr/bin/env python3
"""Focused tests for the llama-proxy per-operation socket read timeout.

Covers the resilience bug where clients that open a connection and never
finish sending request headers pinned a handler thread forever, wedging the
proxy. Also proves the timeout is per-operation, not an overall stream
deadline: an SSE response with a silent upstream gap longer than the timeout
still completes. Also covers model-list metadata: advertised image input
requires the configured mmproj path to exist as a file.

Additionally covers the production failure mode where a long upstream
inference occupies one request while GET /health must still answer promptly:
the proxy server used in tests is built through proxy.build_server(), the
same construction seam main() uses, so tests exercise the production server
construction.

Run: python3 test_llama_proxy.py
"""

import http.client
import importlib.machinery
import importlib.util
import json
import os
import socket
import sys
import tempfile
import threading
import time
import unittest
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

PROXY_PATH = os.path.join(os.path.dirname(os.path.abspath(__file__)), "llama-proxy")

# Short timeout so the test proves closure quickly; set before module import
# to exercise the env-configurable path.
SOCKET_TIMEOUT = 1.0
# Upstream chunk gap strictly longer than SOCKET_TIMEOUT.
UPSTREAM_CHUNK_DELAY = 2.5
# Upper bound for the stalled client to be closed (generous slack).
CLOSE_LIMIT = SOCKET_TIMEOUT + 4.0

os.environ["LLAMA_PROXY_SOCKET_TIMEOUT"] = str(SOCKET_TIMEOUT)

_saved_dont_write_bytecode = sys.dont_write_bytecode
sys.dont_write_bytecode = True
try:
    _loader = importlib.machinery.SourceFileLoader("llama_proxy_under_test", PROXY_PATH)
    _spec = importlib.util.spec_from_loader(_loader.name, _loader)
    proxy = importlib.util.module_from_spec(_spec)
    _loader.exec_module(proxy)
finally:
    sys.dont_write_bytecode = _saved_dont_write_bytecode


class FakeUpstreamHandler(BaseHTTPRequestHandler):
    """Minimal llama-server stand-in: SSE chat completions with a long gap."""

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        first = 'data: {"choices":[{"delta":{"content":"hello"}}]}\n\n'
        rest = (
            'data: {"choices":[{"delta":{"content":" world"}}]}\n\n'
            "data: [DONE]\n\n"
        )
        body = (first + rest).encode()
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(first.encode())
        self.wfile.flush()
        time.sleep(UPSTREAM_CHUNK_DELAY)
        self.wfile.write(rest.encode())
        self.wfile.flush()

    def log_message(self, format, *args):
        pass


class SocketTimeoutTest(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.upstream = ThreadingHTTPServer(("127.0.0.1", 0), FakeUpstreamHandler)
        proxy.LLAMA_PORT = cls.upstream.server_address[1]
        threading.Thread(target=cls.upstream.serve_forever, daemon=True).start()

        # Built through the production seam, not ThreadingHTTPServer directly.
        cls.server = proxy.build_server(("127.0.0.1", 0), proxy.ProxyHandler)
        cls.port = cls.server.server_address[1]
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.upstream.shutdown()
        cls.upstream.server_close()

    def test_env_timeout_applied(self):
        self.assertEqual(proxy.SOCKET_TIMEOUT, SOCKET_TIMEOUT)
        self.assertEqual(proxy.ProxyHandler.timeout, SOCKET_TIMEOUT)

    def test_incomplete_headers_do_not_wedge_proxy(self):
        # Client that never finishes its headers: the handler thread must be
        # released and the connection closed, not blocked forever.
        stalled = socket.create_connection(("127.0.0.1", self.port), timeout=5)
        stalled.sendall(b"GET /health HTTP/1.1\r\nHost: localhost\r\n")

        # A second client must be served while the first is still stalled.
        conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
        try:
            conn.request("GET", "/health")
            resp = conn.getresponse()
            self.assertEqual(resp.status, 200)
            self.assertEqual(json.loads(resp.read())["status"], "ok")
        finally:
            conn.close()

        # The stalled connection must be closed by the server within the limit.
        stalled.settimeout(CLOSE_LIMIT)
        start = time.monotonic()
        try:
            data = stalled.recv(4096)
            closed = data == b""
        except ConnectionResetError:
            closed = True
        elapsed = time.monotonic() - start
        stalled.close()
        self.assertTrue(closed, "stalled client was never closed")
        self.assertLess(elapsed, CLOSE_LIMIT)

    def test_stream_gap_longer_than_timeout_completes(self):
        body = json.dumps({"model": "Ultra", "input": "hi", "stream": True}).encode()
        request = (
            f"POST /v1/responses HTTP/1.1\r\n"
            f"Host: 127.0.0.1:{self.port}\r\n"
            f"Content-Type: application/json\r\n"
            f"Content-Length: {len(body)}\r\n"
            f"Connection: close\r\n\r\n"
        ).encode() + body

        client = socket.create_connection(("127.0.0.1", self.port), timeout=15)
        client.sendall(request)
        recvs = []
        while True:
            try:
                data = client.recv(4096)
            except ConnectionResetError:
                data = b""
            recvs.append((time.monotonic(), data))
            if not data:
                break
        client.close()

        self.assertEqual(recvs[0][1].split(b"\r\n")[0].split(b" ")[1], b"200")
        stream = b"".join(data for _, data in recvs)
        self.assertIn(b'"hello"', stream)
        self.assertIn(b" world", stream)
        self.assertIn(b"response.completed", stream)

        t_hello = next(t for t, data in recvs if b'"hello"' in data)
        t_end = recvs[-1][0]
        # The silent gap between chunks exceeded the socket timeout; the
        # connection must survive it (timeout is per-operation, not a deadline).
        self.assertGreaterEqual(t_end - t_hello, UPSTREAM_CHUNK_DELAY - 0.3)

    def test_mmproj_metadata_requires_existing_file(self):
        def fetch_models(path):
            conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=5)
            try:
                conn.request("GET", path)
                resp = conn.getresponse()
                self.assertEqual(resp.status, 200)
                return json.loads(resp.read())["models"]
            finally:
                conn.close()

        original = proxy.MODEL_ALIASES["Ultra"]
        try:
            proxy.MODEL_ALIASES["Ultra"] = dict(
                original, mmproj="/nonexistent/mmproj-F16.gguf"
            )
            ultra = next(m for m in fetch_models("/v1/models") if m["id"] == "Ultra")
            self.assertEqual(ultra["input_modalities"], ["text"])

            with tempfile.NamedTemporaryFile(suffix=".gguf") as mmproj:
                proxy.MODEL_ALIASES["Ultra"]["mmproj"] = mmproj.name
                ultra = next(m for m in fetch_models("/models") if m["id"] == "Ultra")
                self.assertEqual(ultra["input_modalities"], ["text", "image"])
        finally:
            proxy.MODEL_ALIASES["Ultra"] = original


# Upper bound for /health to answer while an inference is in flight.
HEALTH_DEADLINE = 5.0
# Safety valves so a failing test can never hang forever.
GATE_WAIT_LIMIT = 30.0


class _ServeInterrupt(Exception):
    """Unwinds main()'s serve_forever in the build-seam test."""


class MainUsesBuildSeamTest(unittest.TestCase):
    """Proves main() constructs its server through proxy.build_server()."""

    def test_main_constructs_server_via_build_server(self):
        built = {}

        class FakeServer:
            def serve_forever(self):
                built["served"] = True
                raise _ServeInterrupt

        def fake_build(address, handler):
            built["address"] = address
            built["handler"] = handler
            return FakeServer()

        original_build = proxy.build_server
        original_start = proxy.start_llama_server
        proxy.start_llama_server = lambda *args, **kwargs: True
        proxy.build_server = fake_build
        try:
            self.assertRaises(_ServeInterrupt, proxy.main)
        finally:
            proxy.build_server = original_build
            proxy.start_llama_server = original_start

        self.assertEqual(built["address"], ("0.0.0.0", proxy.PROXY_PORT))
        self.assertIs(built["handler"], proxy.ProxyHandler)
        self.assertTrue(built["served"])


class SlowInferenceUpstreamHandler(BaseHTTPRequestHandler):
    """Upstream whose inference blocks until the test releases it.

    Synchronization is event-driven: inference_entered signals the request
    reached the upstream, release_inference lets the inference finish.
    """

    inference_entered = threading.Event()
    release_inference = threading.Event()
    inference_finished = threading.Event()

    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length", 0)))
        type(self).inference_entered.set()
        if not type(self).release_inference.wait(timeout=GATE_WAIT_LIMIT):
            # Test harness vanished; return without holding the thread.
            return
        body = (
            b'{"object":"chat.completion",'
            b'"choices":[{"message":{"role":"assistant","content":"done"}}]}'
        )
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
        type(self).inference_finished.set()

    def log_message(self, format, *args):
        pass


class HealthDuringLongInferenceTest(unittest.TestCase):
    """Regression for the production failure: while a long upstream
    inference occupies one request, GET /health must still answer promptly
    (before the inference finishes)."""

    def setUp(self):
        for event in (
            SlowInferenceUpstreamHandler.inference_entered,
            SlowInferenceUpstreamHandler.release_inference,
            SlowInferenceUpstreamHandler.inference_finished,
        ):
            event.clear()

        self.upstream = ThreadingHTTPServer(
            ("127.0.0.1", 0), SlowInferenceUpstreamHandler
        )
        proxy.LLAMA_PORT = self.upstream.server_address[1]
        self.server = proxy.build_server(("127.0.0.1", 0), proxy.ProxyHandler)
        self.port = self.server.server_address[1]
        self.threads = [
            threading.Thread(target=self.upstream.serve_forever, daemon=True),
            threading.Thread(target=self.server.serve_forever, daemon=True),
        ]
        for thread in self.threads:
            thread.start()

    def tearDown(self):
        # Always release the gate so no upstream handler thread can hang.
        SlowInferenceUpstreamHandler.release_inference.set()
        self.server.shutdown()
        self.server.server_close()
        self.upstream.shutdown()
        self.upstream.server_close()
        for thread in self.threads:
            thread.join(timeout=5)

    def test_health_responds_while_inference_in_flight(self):
        result = {}

        def run_inference():
            conn = http.client.HTTPConnection("127.0.0.1", self.port, timeout=30)
            try:
                body = json.dumps(
                    {"model": "Ultra",
                     "messages": [{"role": "user", "content": "hi"}]}
                ).encode()
                conn.request(
                    "POST", "/v1/chat/completions", body=body,
                    headers={"Content-Type": "application/json"},
                )
                resp = conn.getresponse()
                result["status"] = resp.status
                result["body"] = resp.read()
            finally:
                conn.close()

        client = threading.Thread(target=run_inference, daemon=True)
        client.start()
        try:
            # Deterministic handoff: wait until the inference is inside the
            # upstream handler and being held open.
            self.assertTrue(
                SlowInferenceUpstreamHandler.inference_entered.wait(timeout=10),
                "inference request never reached the upstream",
            )
            self.assertFalse(
                SlowInferenceUpstreamHandler.inference_finished.is_set(),
                "inference finished before /health was exercised",
            )

            # The upstream inference is still held open; /health must answer.
            start = time.monotonic()
            conn = http.client.HTTPConnection(
                "127.0.0.1", self.port, timeout=HEALTH_DEADLINE
            )
            try:
                conn.request("GET", "/health")
                resp = conn.getresponse()
                elapsed = time.monotonic() - start
                self.assertEqual(resp.status, 200)
                self.assertEqual(json.loads(resp.read())["status"], "ok")
            finally:
                conn.close()
            self.assertFalse(
                SlowInferenceUpstreamHandler.release_inference.is_set(),
                "inference was released before /health completed",
            )
            self.assertFalse(
                SlowInferenceUpstreamHandler.inference_finished.is_set(),
                "inference finished before /health completed",
            )
        finally:
            SlowInferenceUpstreamHandler.release_inference.set()
            client.join(timeout=30)

        self.assertFalse(client.is_alive(), "inference client thread hung")
        self.assertLess(elapsed, HEALTH_DEADLINE)
        self.assertEqual(result.get("status"), 200)
        self.assertTrue(
            SlowInferenceUpstreamHandler.inference_finished.wait(timeout=5),
            "upstream inference handler never completed after release",
        )


if __name__ == "__main__":
    unittest.main(verbosity=2)
