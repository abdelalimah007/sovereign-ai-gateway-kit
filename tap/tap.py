"""tap: a tiny stand-in for a remote model (teaching device, not production).

It plays the role of a remote GPU cloud: it receives exactly what the gateway
sends to the `reasoning` alias, forwards it unchanged to the local Ollama model
and returns Ollama's answer unchanged.

It keeps the last 20 request bodies IN MEMORY ONLY, so the demo can show what
a remote model would have received:
  GET  /last   -> JSON {"model": ..., "messages": [...]} of the latest request
  POST /reset  -> empty the buffer
It writes nothing to disk and never prints request or response bodies.
"""
import collections
import http.client
import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

UPSTREAM_HOST = os.environ.get("TAP_UPSTREAM_HOST", "ollama")
UPSTREAM_PORT = int(os.environ.get("TAP_UPSTREAM_PORT", "11434"))
RING = collections.deque(maxlen=20)  # memory only, lost on restart


class Tap(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, fmt, *args):  # method, path and status only
        print(f"tap {self.command} {self.path} {args[1] if len(args) > 1 else ''}", flush=True)

    def _send(self, code, body, ctype="application/json"):
        self.send_response(code)
        self.send_header("Content-Type", ctype)
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path == "/health":
            return self._send(200, b'{"status":"ok"}')
        if self.path == "/last":
            last = RING[-1] if RING else {}
            out = {"model": last.get("model"), "messages": last.get("messages", [])}
            return self._send(200, json.dumps(out).encode())
        self._send(404, b'{"error":"not found"}')

    def do_POST(self):
        body = self.rfile.read(int(self.headers.get("Content-Length", 0)))
        if self.path == "/reset":
            RING.clear()
            return self._send(200, b'{"status":"reset"}')
        if self.path != "/v1/chat/completions":
            return self._send(404, b'{"error":"not found"}')
        try:
            RING.append(json.loads(body))
        except ValueError:
            return self._send(400, b'{"error":"invalid JSON"}')
        up = http.client.HTTPConnection(UPSTREAM_HOST, UPSTREAM_PORT, timeout=600)
        up.request("POST", self.path, body, {"Content-Type": "application/json"})
        resp = up.getresponse()
        self.send_response(resp.status)
        self.send_header("Content-Type", resp.getheader("Content-Type", "application/json"))
        self.send_header("Connection", "close")
        self.end_headers()
        while chunk := resp.read1(65536):  # relays streamed (SSE) answers as they arrive
            self.wfile.write(chunk)
            self.wfile.flush()
        up.close()
        self.close_connection = True


if __name__ == "__main__":
    ThreadingHTTPServer(("0.0.0.0", 8080), Tap).serve_forever()
