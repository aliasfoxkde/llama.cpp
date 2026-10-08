#!/usr/bin/env python3
"""Focused tests for the llama-proxy per-operation socket read timeout.

Covers the resilience bug where clients that open a connection and never
finish sending request headers pinned a handler thread forever, wedging the
proxy. Also proves the timeout is per-operation, not an overall stream
deadline: an SSE response with a silent upstream gap longer than the timeout
still completes.

Run: python3 test_llama_proxy.py
"""

import importlib.machinery
import importlib.util
import json
import os
import socket
import sys
import threading
import time
import unittest
import urllib.request
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

        cls.server = ThreadingHTTPServer(("127.0.0.1", 0), proxy.ProxyHandler)
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
        with urllib.request.urlopen(
            f"http://127.0.0.1:{self.port}/health", timeout=5
        ) as resp:
            self.assertEqual(resp.status, 200)
            self.assertEqual(json.loads(resp.read())["status"], "ok")

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


if __name__ == "__main__":
    unittest.main(verbosity=2)
